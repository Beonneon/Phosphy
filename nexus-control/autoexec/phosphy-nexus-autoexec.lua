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

if not getgenv().Nexus then
    local ok, source = pcall(game.HttpGet, game, NEXUS_URL)
    if ok and source then
        source = source:gsub("if not Nexus_Version then%s*Nexus:Connect%(%s*%)%s*end", "")
        loadstring(source, "Nexus")()
    end
end

repeat task.wait(0.1) until getgenv().Nexus

Nexus:Connect(RELAY_HOST, true)
if not Nexus.IsConnected then
    Nexus.Connected:Wait()
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
            Nexus:Log("Phosphy loaded with remote control bridge")
        else
            Nexus:Log("Phosphy load failed: " .. tostring(err))
        end
    else
        Nexus:Log("Failed to download Phosphy")
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

    Nexus:Send("PhosphyState", {
        Content = HttpService:JSONEncode({
            Toggles = toggles,
            Options = options,
        })
    })
end

Nexus:AddCommand("phosphy:set", function(message)
    local ok, payload = pcall(HttpService.JSONDecode, HttpService, message)
    if not ok or type(payload) ~= "table" then
        Nexus:Log("Bad phosphy:set payload")
        return
    end

    local bridge = waitForBridge()
    if not bridge then
        Nexus:Log("Phosphy bridge is not ready")
        return
    end

    local id = payload.id
    local kind = payload.kind
    local value = payload.value

    if kind == "toggle" then
        local toggle = bridge.Toggles[id]
        if toggle then
            toggle:SetValue(value == true)
            Nexus:Log("Toggle " .. tostring(id) .. " = " .. tostring(value == true))
            task.delay(0.25, collectState)
        else
            Nexus:Log("Missing toggle: " .. tostring(id))
        end
        return
    end

    if kind == "option" then
        local option = bridge.Options[id]
        if option then
            option:SetValue(value)
            Nexus:Log("Option " .. tostring(id) .. " = " .. tostring(value))
            task.delay(0.25, collectState)
        else
            Nexus:Log("Missing option: " .. tostring(id))
        end
        return
    end

    if kind == "button" then
        if id == "unload" and bridge.Library then
            bridge.Library:Unload()
            Nexus:Log("Phosphy unloaded")
        end
        return
    end

    Nexus:Log("Unknown phosphy control kind: " .. tostring(kind))
end)

Nexus:Log("Phosphy Nexus autoexec ready")
task.spawn(function()
    while task.wait(3) do
        if Nexus.IsConnected then
            collectState()
        end
    end
end)
