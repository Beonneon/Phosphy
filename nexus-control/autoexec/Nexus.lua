local NEXUS_URL = "https://raw.githubusercontent.com/ic3w0lf22/Roblox-Account-Manager/master/RBX%20Alt%20Manager/Nexus/Nexus.lua"

local ok, source = pcall(game.HttpGet, game, NEXUS_URL)
if not ok or not source then
    warn("[RAM Nexus] failed to download Nexus.lua")
    return
end

local fn, err = loadstring(source, "Nexus")
if not fn then
    warn("[RAM Nexus] failed to compile Nexus.lua: " .. tostring(err))
    return
end

fn()
