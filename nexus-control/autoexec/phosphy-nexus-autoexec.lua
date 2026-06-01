-- Phosphy Nexus autoexec
-- 1. Host relay-server.js somewhere with WebSocket support.
-- 2. Put that host below without ws:// or wss://, for example:
--    local RELAY_HOST = "your-relay.up.railway.app"
-- 3. Vercel hosts only the dashboard UI; this autoexec connects accounts to the relay.

local RELAY_HOST = "localhost:8787"
local PHOSPHY_URL = "https://raw.githubusercontent.com/Beonneon/Phosphy/refs/heads/main/phosphy.lua"
local NEXUS_URL = "https://raw.githubusercontent.com/ic3w0lf22/Roblox-Account-Manager/master/RBX%20Alt%20Manager/Nexus/Nexus.lua"

repeat task.wait() until game:IsLoaded()

local HttpService = game:GetService("HttpService")

if getgenv().PhosphyNexusRemoteRunning then
    return
end
getgenv().PhosphyNexusRemoteRunning = true

local oldNexus = getgenv().Nexus
if oldNexus then
    pcall(function()
        oldNexus.Terminated = true
        oldNexus.IsConnected = false
        if oldNexus.Socket then
            oldNexus.Socket:Close()
        end
        for _, conn in pairs(oldNexus.Connections or {}) do
            pcall(function()
                conn:Disconnect()
            end)
        end
    end)
    getgenv().Nexus = nil
end

local okNexus, nexusSource = pcall(game.HttpGet, game, NEXUS_URL)
if okNexus and nexusSource then
    nexusSource = nexusSource:gsub("if%s+not%s+Nexus_Version%s+then%s*Nexus:Connect%(%s*%)%s*end", "")
    local nexusFn = loadstring(nexusSource, "Nexus")
    if nexusFn then
        nexusFn()
    end
end

repeat task.wait(0.1) until getgenv().Nexus

local function safeLog(message)
    if Nexus and Nexus.IsConnected then
        pcall(function()
            Nexus:Log(tostring(message))
        end)
    end
end

local function exposePhosphy(source)
    local marker = "local Options = Library.Options\nlocal Toggles = Library.Toggles"
    local replacement = marker .. "\ngetgenv().PhosphyRemote = { Library = Library, Options = Options, Toggles = Toggles }"
    if source:find(marker, 1, true) then
        return source:gsub(marker, replacement, 1)
    end
    return source
end

if not getgenv().PhosphyRemote then
    local ok, source = pcall(game.HttpGet, game, PHOSPHY_URL)
    if ok and source then
        local fn, err = loadstring(exposePhosphy(source), "Phosphy")
        if fn then
            task.spawn(fn)
            safeLog("Phosphy loaded with remote control bridge")
        else
            safeLog("Phosphy load failed: " .. tostring(err))
        end
    else
        safeLog("Failed to download Phosphy")
    end
end

local function waitForBridge()
    for _ = 1, 100 do
        local bridge = getgenv().PhosphyRemote
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

    if Nexus and Nexus.IsConnected then
        pcall(function()
            Nexus:Send("PhosphyState", {
                Content = HttpService:JSONEncode({
                    Toggles = toggles,
                    Options = options,
                })
            })
        })
    end
end

Nexus:AddCommand("phosphy:set", function(message)
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
    local kind = payload.kind
    local value = payload.value

    if kind == "toggle" then
        local toggle = bridge.Toggles[id]
        if toggle then
            toggle:SetValue(value == true)
            safeLog("Toggle " .. tostring(id) .. " = " .. tostring(value == true))
            task.delay(0.25, collectState)
        else
            safeLog("Missing toggle: " .. tostring(id))
        end
        return
    end

    if kind == "option" then
        local option = bridge.Options[id]
        if option then
            option:SetValue(value)
            safeLog("Option " .. tostring(id) .. " = " .. tostring(value))
            task.delay(0.25, collectState)
        else
            safeLog("Missing option: " .. tostring(id))
        end
        return
    end

    if kind == "button" then
        if id == "unload" and bridge.Library then
            bridge.Library:Unload()
            safeLog("Phosphy unloaded")
        end
        return
    end

    safeLog("Unknown phosphy control kind: " .. tostring(kind))
end)

task.spawn(function()
    Nexus:Connect(RELAY_HOST, true)
end)

task.spawn(function()
    while task.wait(3) do
        if Nexus.IsConnected then
            collectState()
        end
    end
end)
