-- Phosphy dashboard autoexec.
-- This uses its own websocket so Roblox Account Manager's Nexus.lua can stay
-- connected to localhost:5242 and keep ClientCanReceive true.

local RELAY_HOST = "localhost:8787"
local PHOSPHY_URL = "https://raw.githubusercontent.com/Beonneon/Phosphy/refs/heads/main/phosphy.lua"

repeat task.wait() until game:IsLoaded()

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    repeat
        LocalPlayer = Players.LocalPlayer
        task.wait()
    until LocalPlayer
end

local env = getgenv and getgenv() or _G
if env.PhosphyDashboardBridge and env.PhosphyDashboardBridge.Stop then
    pcall(function()
        env.PhosphyDashboardBridge:Stop()
    end)
end

local WSConnect
if syn and syn.websocket then
    WSConnect = syn.websocket.connect
end
if not WSConnect and Krnl then
    repeat task.wait() until Krnl.WebSocket and Krnl.WebSocket.connect
    WSConnect = Krnl.WebSocket.connect
end
if not WSConnect and WebSocket then
    WSConnect = WebSocket.connect
end
if not WSConnect then
    warn("[PhosphyDashboard] websocket is not supported by this executor")
    return
end

local bridgeApp = {
    Running = true,
    IsConnected = false,
    Socket = nil,
    Connections = {},
    OldVolume = UserGameSettings.MasterVolume,
    OldQualityLevel = nil,
}
env.PhosphyDashboardBridge = bridgeApp

local function disconnectAll()
    for _, conn in ipairs(bridgeApp.Connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    table.clear(bridgeApp.Connections)
end

function bridgeApp:Stop()
    self.Running = false
    self.IsConnected = false
    disconnectAll()
    if self.Socket then
        pcall(function()
            self.Socket:Close()
        end)
    end
    if env.PhosphyDashboardBridge == self then
        env.PhosphyDashboardBridge = nil
    end
end

local function encode(value)
    return HttpService:UrlEncode(tostring(value or ""))
end

local function send(command, payload)
    if not bridgeApp.IsConnected or not bridgeApp.Socket then return false end
    local ok = pcall(function()
        bridgeApp.Socket:Send(HttpService:JSONEncode({
            Name = command,
            Payload = payload,
        }))
    end)
    return ok
end

local function safeLog(message)
    send("Log", { Content = tostring(message) })
end

local function exposePhosphy(source)
    local marker = "local Options = Library.Options\nlocal Toggles = Library.Toggles"
    local replacement = marker .. "\ngetgenv().PhosphyRemote = { Library = Library, Options = Options, Toggles = Toggles }"
    if source:find(marker, 1, true) then
        return source:gsub(marker, replacement, 1)
    end
    return source
end

if not env.PhosphyRemote then
    local ok, source = pcall(game.HttpGet, game, PHOSPHY_URL)
    if ok and source then
        local fn, err = loadstring(exposePhosphy(source), "Phosphy")
        if fn then
            task.spawn(fn)
            safeLog("Phosphy loaded with dashboard bridge")
        else
            safeLog("Phosphy load failed: " .. tostring(err))
        end
    else
        safeLog("Failed to download Phosphy")
    end
end

local function waitForBridge()
    for _ = 1, 100 do
        local bridge = env.PhosphyRemote
        if bridge and bridge.Toggles and bridge.Options then
            return bridge
        end
        task.wait(0.1)
    end
    return nil
end

local function collectState()
    local bridge = waitForBridge()
    if not bridge then return end

    local toggles = {}
    for id, toggle in pairs(bridge.Toggles) do
        if type(id) == "string" and toggle and toggle.Value ~= nil then
            toggles[id] = toggle.Value == true
        end
    end

    local options = {}
    for id, option in pairs(bridge.Options) do
        if type(id) == "string" and option and option.Value ~= nil then
            options[id] = option.Value
        end
    end

    send("PhosphyState", {
        Content = HttpService:JSONEncode({
            Toggles = toggles,
            Options = options,
        }),
    })
end

local function applyPhosphyPayload(message)
    local ok, payload = pcall(HttpService.JSONDecode, HttpService, message)
    if not ok or type(payload) ~= "table" then
        safeLog("Bad phosphy:set payload")
        return
    end

    local bridge = waitForBridge()
    if not bridge then
        safeLog("Phosphy bridge is not ready")
        return
    end

    local id = payload.id
    if payload.kind == "toggle" then
        local toggle = bridge.Toggles[id]
        if toggle then
            toggle.SetValue(toggle, payload.value == true)
            safeLog("Toggle " .. tostring(id) .. " = " .. tostring(payload.value == true))
            task.delay(0.25, collectState)
        else
            safeLog("Missing toggle: " .. tostring(id))
        end
        return
    end

    if payload.kind == "option" then
        local option = bridge.Options[id]
        if option then
            option.SetValue(option, payload.value)
            safeLog("Option " .. tostring(id) .. " = " .. tostring(payload.value))
            task.delay(0.25, collectState)
        else
            safeLog("Missing option: " .. tostring(id))
        end
        return
    end

    if payload.kind == "button" and id == "unload" and bridge.Library then
        bridge.Library.Unload(bridge.Library)
        safeLog("Phosphy unloaded")
    end
end

local function runScript(message)
    local fn, err = loadstring(message)
    if not fn then
        safeLog(err)
        return
    end

    local fnEnv = getfenv(fn)
    fnEnv.Player = LocalPlayer
    fnEnv.print = function(...)
        local parts = {}
        for _, value in pairs({ ... }) do
            table.insert(parts, tostring(value))
        end
        safeLog(table.concat(parts, " "))
    end
    if newcclosure then
        fnEnv.print = newcclosure(fnEnv.print)
    end

    local ok, runErr = pcall(fn)
    if not ok then
        safeLog(runErr)
    end
end

local function enablePerformance(message)
    local targetFps = tonumber(message) or 8
    if not bridgeApp.OldQualityLevel then
        pcall(function()
            bridgeApp.OldQualityLevel = settings().Rendering.QualityLevel
        end)
    end
    pcall(function()
        RunService:Set3dRenderingEnabled(false)
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        setfpscap(targetFps)
    end)
    safeLog("Performance mode set to " .. tostring(targetFps) .. " FPS")
end

local function handleCommand(rawMessage)
    rawMessage = tostring(rawMessage or "")
    local splitAt = rawMessage:find(" ")
    local command = splitAt and rawMessage:sub(1, splitAt - 1):lower() or rawMessage:lower()
    local message = splitAt and rawMessage:sub(splitAt + 1) or ""

    if command == "phosphy:set" then
        applyPhosphyPayload(message)
    elseif command == "execute" then
        runScript(message)
    elseif command == "rejoin" then
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId)
    elseif command == "teleport" then
        local s = message:find(" ")
        local placeId = s and message:sub(1, s - 1) or message
        local jobId = s and message:sub(s + 1)
        if jobId then
            TeleportService:TeleportToPlaceInstance(tonumber(placeId), jobId)
        else
            TeleportService:Teleport(tonumber(placeId))
        end
    elseif command == "mute" then
        bridgeApp.OldVolume = UserGameSettings.MasterVolume
        UserGameSettings.MasterVolume = 0
        safeLog("Muted")
    elseif command == "unmute" then
        UserGameSettings.MasterVolume = bridgeApp.OldVolume or 1
        safeLog("Unmuted")
    elseif command == "performance" then
        enablePerformance(message)
    elseif command ~= "" then
        safeLog("Unknown command: " .. command)
    end
end

task.spawn(function()
    while bridgeApp.Running do
        local url = ("ws://%s/Nexus?name=%s&id=%s&jobId=%s&placeId=%s"):format(
            RELAY_HOST,
            encode(LocalPlayer.Name),
            encode(LocalPlayer.UserId),
            encode(game.JobId),
            encode(game.PlaceId)
        )

        local ok, socket = pcall(WSConnect, url)
        if ok and socket then
            bridgeApp.Socket = socket
            bridgeApp.IsConnected = true
            disconnectAll()

            table.insert(bridgeApp.Connections, socket.OnMessage:Connect(handleCommand))
            table.insert(bridgeApp.Connections, socket.OnClose:Connect(function()
                bridgeApp.IsConnected = false
            end))

            safeLog("Phosphy dashboard bridge connected")
            collectState()

            while bridgeApp.Running and bridgeApp.IsConnected do
                if not send("ping") then
                    break
                end
                collectState()
                task.wait(3)
            end
        end

        bridgeApp.IsConnected = false
        disconnectAll()
        if bridgeApp.Socket then
            pcall(function()
                bridgeApp.Socket:Close()
            end)
            bridgeApp.Socket = nil
        end

        task.wait(5)
    end
end)
