local DependencyCommit = "9c6d37050aa04c2bf1a3e446d809d316efe94c8e"

local function fetchDependency(name, urls)
    local errors = {}

    for _, url in ipairs(urls) do
        for attempt = 1, 3 do
            local ok, source = pcall(game.HttpGet, game, url)
            if ok and typeof(source) == "string" and #source > 0 then
                return source
            end

            errors[#errors + 1] = string.format("%s attempt %d: %s", url, attempt, tostring(source))
            task.wait(0.35 * attempt)
        end
    end

    error("Failed to download " .. name .. ":\n" .. table.concat(errors, "\n"))
end

local function loadDependency(name, urls)
    local source = fetchDependency(name, urls)
    local chunk, compileError = loadstring(source, "@" .. name)
    if not chunk then
        error("Failed to compile " .. name .. ": " .. tostring(compileError))
    end
    return chunk()
end

local function phosphyDependency(fileName)
    return {
        "https://raw.githubusercontent.com/Beonneon/Phosphy/refs/heads/main/" .. fileName,
        "https://cdn.jsdelivr.net/gh/Beonneon/Phosphy@" .. DependencyCommit .. "/" .. fileName,
        "https://raw.githubusercontent.com/Beonneon/Phosphy/" .. DependencyCommit .. "/" .. fileName,
    }
end

local Library = loadDependency("LibraryV3.lua", phosphyDependency("LibraryV3.lua"))
local ThemeManager = loadDependency("ThemeManager.lua", {
    "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/addons/ThemeManager.lua",
    "https://cdn.jsdelivr.net/gh/deividcomsono/Obsidian@main/addons/ThemeManager.lua",
})
local SaveManager = loadDependency("SaveManagerV3.lua", phosphyDependency("SaveManagerV3.lua"))

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Options = Library.Options
local Toggles = Library.Toggles

local Tasks = {}
local Connections = {}
local RemoteCache = {}
local StatusLabel = nil

local State = {
    active = true,
    fastRequested = false,
    rollPending = false,
    rollPendingAt = 0,
    choicePending = false,
    pickPending = false,
    pickSerial = 0,
    pickRetry = 0,
    pickChoice = nil,
    choiceReadyAt = 0,
    targetLocked = false,
    latestOptions = nil,
    latestRollId = nil,
    latestTarget = nil,
    latestTargetIndex = nil,
    latestMissReason = nil,
    latestSummary = "No amulet roll yet.",
    statusText = "No amulet roll yet.",
    nextRollAt = 0,
    rolls = 0,
    keptOld = 0,
    selectedNew = 0,
    loadingSettings = false,
    lastWebhookAt = 0,
}

local Extra = {
    RemoteRoot = nil,
    VisualConnectionsDisabled = false,
    SuppressedConnections = {},
    CachedAmuletsGui = nil,
    LastFullGuiScanAt = 0,
    LastVisualCleanupAt = 0,
    WebhookSent = {},
    ComboSlots = {},
    ComboSlotLimit = 6,
}

local Config = {
    PickTimeout = 0.45,
    PickRetryDelay = 0.11,
    SlowRetryDelay = 0.22,
    MaxPickRetries = 60,
    RollTimeout = 3,
    StatusThrottle = 0.35,
    AutoFallbackWait = 0.18,
}

local CountValues = { "1", "2", "3", "4" }
local RuleValues = {
    "Count Only",
    "Count + Type/Combo",
    "Count + Min Total",
    "Count + Type/Combo + Min Total",
    "Count + Type/Combo OR Min Total",
}
local MinModeValues = {
    "All Active Min Totals",
    "Any Active Min Total",
}
local AmuletTypeValues = {
    "Void",
    "Titanic",
    "Summoner",
    "Hasty",
    "Lucky",
    "Godly",
    "Gift",
    "Corrupted",
    "Glitch",
    "Stardust",
    "Slimes",
    "Exp",
    "Gems",
    "Move Speed",
    "Giant",
    "Corrupt Chance",
    "404",
}

local TypeAliases = {
    void = "VoidAmulet",
    voidamulet = "VoidAmulet",
    titanic = "TitanicAmulet",
    titanicamulet = "TitanicAmulet",
    summoner = "SummonerAmulet",
    summoneramulet = "SummonerAmulet",
    hasty = "HastyAmulet",
    hastyamulet = "HastyAmulet",
    lucky = "LuckyAmulet",
    luckyamulet = "LuckyAmulet",
    godly = "GodlyAmulet",
    godlyamulet = "GodlyAmulet",
    gift = "GiftAmulet",
    giftamulet = "GiftAmulet",
    corrupted = "CorruptedAmulet",
    corruptedamulet = "CorruptedAmulet",
    corrupt = "CorruptedAmulet",
    glitch = "GlitchAmulet",
    glitchamulet = "GlitchAmulet",
    stardust = "StardustAmulet",
    stardustamulet = "StardustAmulet",
    slimes = "SlimesAmulet",
    slimesamulet = "SlimesAmulet",
    exp = "ExpAmulet",
    expamulet = "ExpAmulet",
    gems = "GemsAmulet",
    gemsamulet = "GemsAmulet",
    movespeed = "MoveSpeedAmulet",
    movespeedamulet = "MoveSpeedAmulet",
    giant = "GiantAmulet",
    giantamulet = "GiantAmulet",
    corruptchance = "CorruptChanceAmulet",
    corruptchanceamulet = "CorruptChanceAmulet",
    ["404"] = "Amulet404",
    amulet404 = "Amulet404",
}

local TypeAlternates = {
    glitch = { "GlitchAmulet", "CorruptedAmulet" },
    glitchamulet = { "GlitchAmulet", "CorruptedAmulet" },
}

local StatFields = {
    Slimes = { "slimesBonus", "slimeBonus", "slimesMultiplier", "slimeMultiplier" },
    Exp = { "expBonus", "expMultiplier", "xpBonus", "xpMultiplier" },
    Gems = { "gemsBonus", "gemBonus", "gemsMultiplier", "gemMultiplier" },
}

local PreferredFields = {
    "rarity",
    "tier",
    "level",
    "value",
    "amount",
    "multiplier",
    "slimeMultiplier",
    "slimesMultiplier",
    "expMultiplier",
    "gemsMultiplier",
    "luckMultiplier",
    "luck",
    "speed",
    "moveSpeed",
    "cooldown",
    "duration",
    "chance",
}

local Handlers = {}
local rollAmuletOnce
local pickLatestAmulet

local function notify(message)
    if Library and Library.Notify then
        Library:Notify(tostring(message))
    else
        warn("[AutoAmulet] " .. tostring(message))
    end
end

local function readGlobalString(name)
    if typeof(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and typeof(env) == "table" and typeof(env[name]) == "string" then
            return env[name]
        end
    end

    if typeof(_G) == "table" and typeof(_G[name]) == "string" then
        return _G[name]
    end

    return ""
end

local function stopTask(name)
    local taskRef = Tasks[name]
    Tasks[name] = nil
    if taskRef then
        pcall(task.cancel, taskRef)
    end
end

local function disconnect(name)
    local connection = Connections[name]
    Connections[name] = nil
    if connection then
        pcall(function()
            connection:Disconnect()
        end)
    end
end

local function getRemotes()
    if Extra.RemoteRoot and Extra.RemoteRoot.Parent then
        return Extra.RemoteRoot
    end

    Extra.RemoteRoot = ReplicatedStorage:FindFirstChild("Remotes")
        or ReplicatedStorage:WaitForChild("Remotes", 10)
    return Extra.RemoteRoot
end

local function getRemote(name, waitSeconds)
    local cached = RemoteCache[name]
    if cached and cached.Parent then
        return cached
    end

    local remotes = getRemotes()
    if not remotes then
        return nil
    end

    local remote = remotes:FindFirstChild(name) or remotes:WaitForChild(name, waitSeconds or 10)
    if remote then
        RemoteCache[name] = remote
    end
    return remote
end

local function getNumberOption(id, fallback)
    local option = Options[id]
    local value = option and option.Value
    if typeof(value) == "string" then
        value = value:gsub(",", ""):match("[-+]?%d*%.?%d+")
    end
    value = tonumber(value)
    if value == nil then
        return fallback
    end
    return value
end

local function getRollDelay()
    return math.max(0, getNumberOption("AutoAmuletRollDelayMs", 0) / 1000)
end

local function getPickDelay()
    return math.max(0, getNumberOption("AutoAmuletPickDelayMs", 100) / 1000)
end

local function getStatusEvery()
    return math.max(1, math.floor(getNumberOption("AutoAmuletStatusEvery", 10)))
end

local function setStatus(message, force)
    local text = tostring(message or State.statusText or State.latestSummary or "No amulet roll yet.")
    State.statusText = text
    if not StatusLabel then
        return
    end

    if not force and State.lastStatusAt and os.clock() - State.lastStatusAt < Config.StatusThrottle then
        return
    end

    State.lastStatusAt = os.clock()
    pcall(function()
        StatusLabel:SetText(text)
    end)
end

local function isAutoRolling()
    return Toggles.ToggleAutoAmuletRoll and Toggles.ToggleAutoAmuletRoll.Value == true
end

local function shouldShowAutoStatus()
    if not isAutoRolling() then
        return true
    end

    local every = getStatusEvery()
    return State.rolls <= 3 or State.rolls % every == 0
end

local function setAutoRolling(enabled)
    if Toggles.ToggleAutoAmuletRoll then
        Toggles.ToggleAutoAmuletRoll:SetValue(enabled == true)
    end
end

local function compactKey(value)
    return tostring(value or ""):lower():gsub("%s+", ""):gsub("[^%w]", "")
end

local function normalizeAmuletTypeName(value)
    local compact = compactKey(value)
    return TypeAliases[compact] or TypeAliases[compact:gsub("amulet$", "")]
end

local function getSelectionTypeTokens(value)
    local compact = compactKey(value)
    local tokens = {}
    local alternates = TypeAlternates[compact] or TypeAlternates[compact:gsub("amulet$", "")]
    if alternates then
        for _, token in ipairs(alternates) do
            tokens[token] = true
        end
    end

    local normalized = normalizeAmuletTypeName(value)
    if normalized then
        tokens[normalized] = true
    end
    return tokens
end

local function getSelectedMap(id)
    local option = Options[id]
    if not option or typeof(option.Value) ~= "table" then
        return {}
    end
    return option.Value
end

local function hasSelectedValues(id)
    for _, active in pairs(getSelectedMap(id)) do
        if active then
            return true
        end
    end
    return false
end

local function isSelectedAmuletCount(count)
    return getSelectedMap("AmuletOptionCounts")[tostring(count)] == true
end

local function getSelectedAmuletTypes()
    local selected = {}
    for value, active in pairs(getSelectedMap("AmuletRequiredTypes")) do
        if active then
            for token in pairs(getSelectionTypeTokens(value)) do
                selected[token] = true
            end
        end
    end
    return selected
end

local function hasTypeRules()
    for _ in pairs(getSelectedAmuletTypes()) do
        return true
    end

    for _, slot in ipairs(Extra.ComboSlots) do
        if slot.Active then
            for _, active in pairs(getSelectedMap(slot.DropdownId)) do
                if active then
                    return true
                end
            end
        end
    end
    return false
end

local function compactAmuletValue(value)
    local valueType = typeof(value)
    if valueType == "number" then
        local rounded = math.floor(value * 1000 + 0.5) / 1000
        if rounded == math.floor(rounded) then
            return tostring(math.floor(rounded))
        end
        return tostring(rounded)
    end
    if valueType == "string" or valueType == "boolean" then
        return tostring(value)
    end
    if valueType == "Vector3" then
        return string.format("%.1f, %.1f, %.1f", value.X, value.Y, value.Z)
    end
    if valueType == "Color3" then
        return string.format(
            "rgb(%d,%d,%d)",
            math.floor(value.R * 255 + 0.5),
            math.floor(value.G * 255 + 0.5),
            math.floor(value.B * 255 + 0.5)
        )
    end
    return nil
end

local function getOptionKeys(option)
    local keys = {}
    if typeof(option) ~= "table" then
        return keys
    end
    for key in pairs(option) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)
    return keys
end

local function getOrderedOptionKeys(options)
    local keys = {}
    if typeof(options) ~= "table" then
        return keys
    end
    for key in pairs(options) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
        if typeof(left) == "number" and typeof(right) == "number" then
            return left < right
        end
        return tostring(left) < tostring(right)
    end)
    return keys
end

local function getAmuletType(option)
    if typeof(option) ~= "table" then
        return nil
    end
    local amuletType = option.amuletType or option.AmuletType or option.type or option.Type or option.name or option.Name
    if typeof(amuletType) == "string" then
        return amuletType
    end
    return nil
end

local function getTypeIndex(options, keys)
    local present = {}
    local firstKey = {}
    for _, key in ipairs(keys) do
        local amuletType = normalizeAmuletTypeName(getAmuletType(options[key]))
        if amuletType then
            present[amuletType] = true
            firstKey[amuletType] = firstKey[amuletType] or key
        end
    end
    return present, firstKey
end

local function getCustomCombos()
    local combos = {}
    for _, slot in ipairs(Extra.ComboSlots) do
        if slot.Active then
            local combo = {}
            local used = {}
            for value, active in pairs(getSelectedMap(slot.DropdownId)) do
                if active then
                    local alternatives = getSelectionTypeTokens(value)
                    local option = {}
                    for token in pairs(alternatives) do
                        option[#option + 1] = token
                    end
                    table.sort(option)
                    if #option > 0 then
                        combo[#combo + 1] = option
                        used[tostring(value)] = true
                    end
                end
            end
            if #combo > 0 then
                combos[#combos + 1] = combo
            end
        end
    end
    return combos
end

local function comboMatchesPresent(combo, present, firstKey)
    local matchedKey = nil
    for _, alternatives in ipairs(combo) do
        local found = false
        for _, token in ipairs(alternatives) do
            if present[token] then
                matchedKey = matchedKey or firstKey[token]
                found = true
                break
            end
        end
        if not found then
            return false, nil
        end
    end
    return true, matchedKey
end

local function matchTypeRules(options, keys)
    if not hasTypeRules() then
        return true, nil
    end

    local present, firstKey = getTypeIndex(options, keys)
    for token in pairs(getSelectedAmuletTypes()) do
        if present[token] then
            return true, firstKey[token]
        end
    end

    for _, combo in ipairs(getCustomCombos()) do
        local matched, matchedKey = comboMatchesPresent(combo, present, firstKey)
        if matched then
            return true, matchedKey
        end
    end
    return false, nil
end

local function getStatValue(option, statName)
    if typeof(option) ~= "table" then
        return 0
    end

    for _, field in ipairs(StatFields[statName] or {}) do
        local value = option[field]
        if typeof(value) == "number" then
            return value
        end
        if typeof(value) == "string" then
            value = tonumber(value:gsub(",", ""):match("[-+]?%d*%.?%d+"))
            if value then
                return value
            end
        end
    end
    return 0
end

local function getCombinedStats(options, keys)
    local combined = {
        Slimes = 0,
        Exp = 0,
        Gems = 0,
    }
    for _, key in ipairs(keys) do
        for statName in pairs(combined) do
            combined[statName] += getStatValue(options[key], statName)
        end
    end
    return combined
end

local function formatNumber(value)
    local rounded = math.floor((tonumber(value) or 0) * 100 + 0.5) / 100
    if rounded == math.floor(rounded) then
        return tostring(math.floor(rounded))
    end
    return tostring(rounded):gsub("0+$", ""):gsub("%.$", "")
end

local function getMinimumStats()
    return {
        Slimes = math.max(0, getNumberOption("AmuletMinCombinedSlimesInput", 0)),
        Exp = math.max(0, getNumberOption("AmuletMinCombinedExpInput", 0)),
        Gems = math.max(0, getNumberOption("AmuletMinCombinedGemsInput", 0)),
    }
end

local function hasMinimumStats()
    for _, minimum in pairs(getMinimumStats()) do
        if minimum > 0 then
            return true
        end
    end
    return false
end

local function matchMinimumStats(combined)
    local minimums = getMinimumStats()
    if not hasMinimumStats() then
        return true
    end

    local anyMode = Options.AmuletMinimumMode
        and Options.AmuletMinimumMode.Value == "Any Active Min Total"
    if anyMode then
        for statName, minimum in pairs(minimums) do
            if minimum > 0 and (combined[statName] or 0) >= minimum then
                return true
            end
        end
        return false
    end

    for statName, minimum in pairs(minimums) do
        if minimum > 0 and (combined[statName] or 0) < minimum then
            return false
        end
    end
    return true
end

local function describeMinimums()
    local parts = {}
    for statName, minimum in pairs(getMinimumStats()) do
        if minimum > 0 then
            parts[#parts + 1] = statName .. ">=" .. formatNumber(minimum)
        end
    end
    if #parts == 0 then
        return "none"
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local function appendField(parts, used, option, key)
    if used[key] then
        return false
    end

    local text = compactAmuletValue(option[key])
    if not text then
        return false
    end

    used[key] = true
    parts[#parts + 1] = tostring(key) .. "=" .. text
    return true
end

local function summarizeOption(option, index, matched)
    if typeof(option) ~= "table" then
        return "[" .. tostring(index) .. "] " .. tostring(option)
    end

    local amuletType = getAmuletType(option) or "UnknownAmulet"
    local parts = {
        "[" .. tostring(index) .. "] " .. amuletType .. (matched and " (TARGET)" or ""),
    }
    local used = {
        amuletType = true,
        AmuletType = true,
        type = true,
        Type = true,
        name = true,
        Name = true,
    }

    for _, key in ipairs(PreferredFields) do
        appendField(parts, used, option, key)
    end

    local added = 0
    for _, key in ipairs(getOptionKeys(option)) do
        if added >= 8 then
            break
        end
        if appendField(parts, used, option, key) then
            added += 1
        end
    end

    return table.concat(parts, " | ")
end

local function summarizeRoll(options, rollId, target, targetIndex, missReason, combined)
    local lines = {}
    if target then
        lines[#lines + 1] = "Roll " .. tostring(rollId or "?") .. " MATCH: " .. tostring(target) .. " option(s)."
    elseif missReason == "count" then
        lines[#lines + 1] = "Roll " .. tostring(rollId or "?") .. " missed selected option count."
    elseif missReason == "type" then
        lines[#lines + 1] = "Roll " .. tostring(rollId or "?") .. " hit count, missed type/combo."
    elseif missReason == "min" then
        lines[#lines + 1] = "Roll " .. tostring(rollId or "?") .. " hit count, missed min total."
    elseif missReason == "rules" then
        lines[#lines + 1] = "Roll " .. tostring(rollId or "?") .. " hit count, missed type/combo and min total."
    else
        lines[#lines + 1] = "Roll " .. tostring(rollId or "?") .. " checked."
    end

    combined = combined or getCombinedStats(options, getOrderedOptionKeys(options))
    lines[#lines + 1] = "Combined: Slimes +" .. formatNumber(combined.Slimes)
        .. " | Exp +" .. formatNumber(combined.Exp)
        .. " | Gems +" .. formatNumber(combined.Gems)
    lines[#lines + 1] = "Rule: " .. tostring(Options.AmuletMatchRule and Options.AmuletMatchRule.Value or "Count Only")
        .. " | Min: " .. describeMinimums()

    if typeof(options) ~= "table" then
        lines[#lines + 1] = "Payload: " .. tostring(options)
        return table.concat(lines, "\n")
    end

    local keys = getOrderedOptionKeys(options)
    for index, key in ipairs(keys) do
        if index <= 4 then
            lines[#lines + 1] = summarizeOption(options[key], key, key == targetIndex)
        end
    end
    if #keys == 0 then
        lines[#lines + 1] = "No options were sent."
    elseif #keys > 4 then
        lines[#lines + 1] = "+" .. tostring(#keys - 4) .. " more option(s)"
    end
    return table.concat(lines, "\n")
end

local function findSelectedTarget(options)
    local keys = getOrderedOptionKeys(options)
    local count = #keys
    local combined = getCombinedStats(options, keys)
    if not isSelectedAmuletCount(count) then
        return nil, nil, "count", combined
    end

    local rule = Options.AmuletMatchRule and Options.AmuletMatchRule.Value or "Count Only"
    local typeActive = hasTypeRules()
    local minActive = hasMinimumStats()
    local typeMatched, typeKey = matchTypeRules(options, keys)
    local minMatched = matchMinimumStats(combined)

    if rule == "Count Only" then
        return count, nil, nil, combined
    end

    if rule == "Count + Type/Combo" then
        if not typeActive or typeMatched then
            return count, typeKey, nil, combined
        end
        return nil, nil, "type", combined
    end

    if rule == "Count + Min Total" then
        if not minActive or minMatched then
            return count, nil, nil, combined
        end
        return nil, nil, "min", combined
    end

    if rule == "Count + Type/Combo OR Min Total" then
        if not typeActive and not minActive then
            return count, nil, nil, combined
        end
        if (typeActive and typeMatched) or (minActive and minMatched) then
            return count, typeKey, nil, combined
        end
        return nil, nil, "rules", combined
    end

    if (not typeActive or typeMatched) and (not minActive or minMatched) then
        return count, typeKey, nil, combined
    end
    if typeActive and not typeMatched and minActive and not minMatched then
        return nil, nil, "rules", combined
    end
    if typeActive and not typeMatched then
        return nil, nil, "type", combined
    end
    return nil, nil, "min", combined
end

local function cleanupAmuletRollVisuals()
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        local function clearContainer(container)
            if container and container:IsA("GuiObject") then
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("GuiObject") then
                        child:Destroy()
                    end
                end
            end
        end

        local function hideGuiObject(guiObject)
            if guiObject and guiObject:IsA("GuiObject") then
                guiObject.Visible = false
                guiObject.BackgroundTransparency = 1
                if guiObject:IsA("ImageLabel") or guiObject:IsA("ImageButton") then
                    guiObject.ImageTransparency = 1
                end
            end
        end

        local amuletsGui = Extra.CachedAmuletsGui
        if not amuletsGui or not amuletsGui.Parent then
            amuletsGui = playerGui:FindFirstChild("AmuletsGui")
            Extra.CachedAmuletsGui = amuletsGui
        end

        if amuletsGui then
            local dropped = amuletsGui:FindFirstChild("DroppedAmuletsGui", true)
            hideGuiObject(dropped)
            clearContainer(dropped and dropped:FindFirstChild("LeftAmulets"))
            clearContainer(dropped and dropped:FindFirstChild("RightAmulets"))
            hideGuiObject(amuletsGui:FindFirstChild("Background"))
        elseif os.clock() - Extra.LastFullGuiScanAt > 1 then
            Extra.LastFullGuiScanAt = os.clock()
            for _, item in ipairs(playerGui:GetDescendants()) do
                if item.Name == "DroppedAmuletsGui" then
                    hideGuiObject(item)
                elseif item.Name == "LeftAmulets" or item.Name == "RightAmulets" then
                    clearContainer(item)
                elseif item.Name == "Background" then
                    hideGuiObject(item)
                end
            end
        end
    end

    local camera = Workspace.CurrentCamera
    if camera then
        pcall(function()
            camera.FieldOfView = 70
        end)
    end

    local runtime = Workspace:FindFirstChild("Runtime")
    local amulets = runtime and runtime:FindFirstChild("Amulets")
    if amulets then
        for _, item in ipairs(amulets:GetChildren()) do
            if item:GetAttribute("AmuletRollReveal") == true then
                item:Destroy()
            end
        end
    end
end

local function setExecutorConnectionEnabled(connection, enabled)
    local methods = enabled and { "Enable", "enable" } or { "Disable", "disable" }
    for _, methodName in ipairs(methods) do
        local ok, method = pcall(function()
            return connection[methodName]
        end)
        if ok and typeof(method) == "function" then
            local called = pcall(method, connection)
            if not called then
                called = pcall(method)
            end
            if called then
                return true
            end
        end
    end

    local hasEnabled = pcall(function()
        return connection.Enabled
    end)
    if hasEnabled then
        return pcall(function()
            connection.Enabled = enabled
        end)
    end
    return false
end

local function getConnectionCallback(connection)
    for _, key in ipairs({ "Function", "Callback", "func" }) do
        local ok, callback = pcall(function()
            return connection[key]
        end)
        if ok and typeof(callback) == "function" then
            return callback
        end
    end
    return nil
end

local function getFunctionDebugText(callback)
    if typeof(callback) ~= "function" then
        return ""
    end

    local parts = {}
    if typeof(debug) == "table" then
        if typeof(debug.info) == "function" then
            local ok, source, line, name = pcall(function()
                return debug.info(callback, "sln")
            end)
            if ok then
                parts[#parts + 1] = tostring(source or "")
                parts[#parts + 1] = tostring(line or "")
                parts[#parts + 1] = tostring(name or "")
            end
        end
        if typeof(debug.getinfo) == "function" then
            local ok, info = pcall(debug.getinfo, callback)
            if ok and typeof(info) == "table" then
                parts[#parts + 1] = tostring(info.source or "")
                parts[#parts + 1] = tostring(info.short_src or "")
                parts[#parts + 1] = tostring(info.name or "")
                parts[#parts + 1] = tostring(info.linedefined or "")
            end
        end
    end
    return table.concat(parts, " ")
end

local function isOwnSignalConnection(connection)
    local callback = getConnectionCallback(connection)
    return callback == Handlers.roll or callback == Handlers.pick
end

local function isAmuletVisualCallback(callback)
    return getFunctionDebugText(callback):find("ExportedGuiWiring", 1, true) ~= nil
end

local function restoreAmuletVisualConnections()
    for _, entry in ipairs(Extra.SuppressedConnections) do
        setExecutorConnectionEnabled(entry.Connection, true)
    end
    Extra.SuppressedConnections = {}
    Extra.VisualConnectionsDisabled = false
end

local function disableAmuletVisualConnections()
    if Extra.VisualConnectionsDisabled or typeof(getconnections) ~= "function" then
        return false
    end

    local remote = getRemote("AmuletRollResult", 2)
    if not remote then
        return false
    end

    local ok, signalConnections = pcall(getconnections, remote.OnClientEvent)
    if not ok or typeof(signalConnections) ~= "table" then
        return false
    end

    local disabled = 0
    for _, connection in ipairs(signalConnections) do
        local callback = getConnectionCallback(connection)
        if not isOwnSignalConnection(connection) and isAmuletVisualCallback(callback) then
            if setExecutorConnectionEnabled(connection, false) then
                disabled += 1
                Extra.SuppressedConnections[#Extra.SuppressedConnections + 1] = {
                    Connection = connection,
                }
            end
        end
    end

    Extra.VisualConnectionsDisabled = disabled > 0
    return Extra.VisualConnectionsDisabled
end

local function shouldHideVisuals()
    return Toggles.ToggleAmuletHideRollVisuals and Toggles.ToggleAmuletHideRollVisuals.Value == true
end

local function queueVisualCleanup()
    if not shouldHideVisuals() then
        return
    end

    local now = os.clock()
    if now - Extra.LastVisualCleanupAt < 0.05 then
        return
    end
    Extra.LastVisualCleanupAt = now

    cleanupAmuletRollVisuals()
    task.delay(0.1, cleanupAmuletRollVisuals)
    if not Extra.VisualConnectionsDisabled then
        task.delay(0.25, cleanupAmuletRollVisuals)
    end
end

local function refreshVisualSuppression()
    if shouldHideVisuals() and isAutoRolling() then
        local disabled = disableAmuletVisualConnections()
        queueVisualCleanup()
        if not disabled and not Tasks.VisualCleanup then
            Tasks.VisualCleanup = task.spawn(function()
                while State.active and shouldHideVisuals() and isAutoRolling() do
                    cleanupAmuletRollVisuals()
                    task.wait(0.25)
                end
                Tasks.VisualCleanup = nil
            end)
        end
    else
        stopTask("VisualCleanup")
        restoreAmuletVisualConnections()
    end
end

local function enableFastAmulets()
    if State.fastRequested then
        return true
    end

    local remote = getRemote("UpdateSetting", 5)
    if not remote then
        return false
    end

    State.fastRequested = true
    remote:FireServer("fastAmulets", true)
    return true
end

local function connectAmuletEvents()
    local rollResult = getRemote("AmuletRollResult", 10)
    local pickResult = getRemote("AmuletPickResult", 5)
    if not rollResult then
        notify("AmuletRollResult remote was not found.")
        return false
    end
    if not pickResult then
        notify("AmuletPickResult remote was not found.")
    end

    if not Connections.AmuletRollResult then
        Connections.AmuletRollResult = rollResult.OnClientEvent:Connect(Handlers.roll)
    end
    if pickResult and not Connections.AmuletPickResult then
        Connections.AmuletPickResult = pickResult.OnClientEvent:Connect(Handlers.pick)
    end

    refreshVisualSuppression()
    return true
end

local function scheduleNextRoll(delaySeconds)
    State.nextRollAt = os.clock() + math.max(0, delaySeconds or 0)
    if not isAutoRolling() then
        return
    end

    task.delay(math.max(0, delaySeconds or 0), function()
        if State.active and isAutoRolling() then
            rollAmuletOnce()
        end
    end)
end

local function getWebhookUrl()
    local option = Options.WebhookUrlInput
    local value = option and option.Value
    if typeof(value) ~= "string" or value == "" then
        value = readGlobalString("AutoAmuletWebhook")
    end

    value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return ""
    end

    if not value:match("^https://discord%.com/api/webhooks/")
        and not value:match("^https://discordapp%.com/api/webhooks/") then
        return ""
    end

    return value
end

local function getRequestFunction()
    if typeof(request) == "function" then
        return request
    end
    if typeof(http_request) == "function" then
        return http_request
    end
    if typeof(syn) == "table" and typeof(syn.request) == "function" then
        return syn.request
    end
    if typeof(http) == "table" and typeof(http.request) == "function" then
        return http.request
    end
    return nil
end

local function shortText(text, maxLength)
    text = tostring(text or "")
    maxLength = maxLength or 1500
    if #text <= maxLength then
        return text
    end
    return text:sub(1, maxLength - 3) .. "..."
end

local function sendWebhook(eventName, description, rollId, toggleId)
    local toggle = Toggles[toggleId or "ToggleWebhookOnTarget"]
    if not toggle or toggle.Value ~= true then
        return false
    end

    local url = getWebhookUrl()
    if url == "" then
        return false
    end

    local eventKey = tostring(eventName) .. ":" .. tostring(rollId or os.clock())
    if Extra.WebhookSent[eventKey] then
        return false
    end
    Extra.WebhookSent[eventKey] = true

    task.spawn(function()
        local requestFunction = getRequestFunction()
        if not requestFunction then
            setStatus("Webhook request function unavailable.\n" .. tostring(State.latestSummary), true)
            return
        end

        local now = os.clock()
        if now - State.lastWebhookAt < 0.5 then
            task.wait(0.5 - (now - State.lastWebhookAt))
        end
        State.lastWebhookAt = os.clock()

        local payload = {
            username = "Auto Amulet",
            embeds = {
                {
                    title = tostring(eventName),
                    color = 51444,
                    description = shortText(description, 3500),
                    fields = {
                        {
                            name = "Rolls",
                            value = tostring(State.rolls),
                            inline = true,
                        },
                        {
                            name = "Selected New",
                            value = tostring(State.selectedNew),
                            inline = true,
                        },
                        {
                            name = "Kept Old",
                            value = tostring(State.keptOld),
                            inline = true,
                        },
                    },
                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                },
            },
        }

        local ok, result = pcall(requestFunction, {
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = HttpService:JSONEncode(payload),
        })
        if not ok then
            warn("[AutoAmulet] webhook failed: " .. tostring(result))
        end
    end)
    return true
end

local function retryPick(choice, reason, delaySeconds)
    if not State.choicePending or State.latestRollId == nil then
        return false
    end

    State.pickRetry += 1
    if State.pickRetry > Config.MaxPickRetries then
        State.pickPending = false
        setStatus(
            "Pick retry limit hit. Still holding roll " .. tostring(State.latestRollId)
                .. " for manual buttons.\nLast reject: " .. tostring(reason or "unknown")
                .. "\n" .. tostring(State.latestSummary),
            true
        )
        setAutoRolling(false)
        return false
    end

    local rollId = State.latestRollId
    local retryNumber = State.pickRetry
    if retryNumber <= 3 or retryNumber % 5 == 0 then
        setStatus(
            "Pick " .. tostring(choice) .. " retry " .. tostring(retryNumber)
                .. " on roll " .. tostring(rollId) .. ": " .. tostring(reason or "retrying")
                .. "\n" .. tostring(State.latestSummary),
            true
        )
    end

    task.delay(delaySeconds or Config.PickRetryDelay, function()
        if State.active
            and State.choicePending
            and not State.pickPending
            and tostring(State.latestRollId) == tostring(rollId) then
            pickLatestAmulet(choice, true)
        end
    end)
    return true
end

pickLatestAmulet = function(choice, quiet)
    enableFastAmulets()
    connectAmuletEvents()

    choice = tostring(choice or ""):upper()
    if choice ~= "NEW" and choice ~= "OLD" then
        if not quiet then
            notify("Pick choice must be NEW or OLD.")
        end
        return false
    end

    if State.latestRollId == nil then
        if not quiet then
            notify("No amulet roll id yet.")
        end
        return false
    end

    if not State.choicePending then
        if not quiet then
            notify("No unhandled amulet choice is ready.")
        end
        return false
    end

    if State.pickPending then
        return false
    end

    local remote = getRemote("PickAmulet", 10)
    if not remote then
        notify("PickAmulet remote was not found.")
        return false
    end

    State.pickPending = true
    State.pickChoice = choice
    State.pickSerial += 1
    local serial = State.pickSerial
    local rollId = State.latestRollId
    remote:FireServer(choice, rollId)

    if shouldHideVisuals() then
        queueVisualCleanup()
    end

    task.delay(Config.PickTimeout, function()
        if State.active
            and State.pickPending
            and State.pickSerial == serial
            and tostring(State.latestRollId) == tostring(rollId) then
            State.pickPending = false
            retryPick(choice, "pick timeout", Config.PickRetryDelay)
        end
    end)

    if not quiet then
        notify("Amulet pick fired: " .. choice)
    end
    return true
end

local function handleReadyChoice()
    if os.clock() < (State.choiceReadyAt or 0) then
        return
    end

    if State.latestTarget then
        if Toggles.ToggleAutoAmuletSelectNew and Toggles.ToggleAutoAmuletSelectNew.Value then
            pickLatestAmulet("NEW", true)
        elseif isAutoRolling() then
            setAutoRolling(false)
            setStatus("Target matched. Auto stopped for manual Select New/Keep Old.\n" .. State.latestSummary, true)
        end
        return
    end

    if isAutoRolling() then
        pickLatestAmulet("OLD", true)
    end
end

Handlers.roll = function(options, rollId)
    if not State.active then
        disconnect("AmuletRollResult")
        return
    end

    State.rollPending = false
    State.choicePending = true
    State.pickPending = false
    State.pickRetry = 0
    State.choiceReadyAt = os.clock() + getPickDelay()
    State.latestOptions = options
    State.latestRollId = rollId
    State.rolls += 1

    local target, targetIndex, missReason, combined = findSelectedTarget(options)
    State.latestTarget = target
    State.latestTargetIndex = targetIndex
    State.latestMissReason = missReason
    State.targetLocked = target ~= nil
    State.latestSummary = summarizeRoll(options, rollId, target, targetIndex, missReason, combined)

    if target then
        setStatus(State.latestSummary .. "\nTarget met. " .. (
            Toggles.ToggleAutoAmuletSelectNew and Toggles.ToggleAutoAmuletSelectNew.Value
                and "Selecting NEW now."
                or "Waiting for manual pick."
        ), true)
        sendWebhook("Auto Amulet Target Hit", State.latestSummary, rollId, "ToggleWebhookOnTarget")
    elseif isAutoRolling() then
        if shouldShowAutoStatus() then
            setStatus(State.latestSummary .. "\nMissed target. Keeping OLD now.", false)
        end
    else
        setStatus(State.latestSummary, true)
    end

    if shouldHideVisuals() then
        queueVisualCleanup()
    end
    task.delay(getPickDelay(), function()
        if State.active
            and State.choicePending
            and not State.pickPending
            and tostring(State.latestRollId) == tostring(rollId) then
            handleReadyChoice()
        end
    end)
end

Handlers.pick = function(choice, rollId, ok, message)
    if not State.active then
        disconnect("AmuletPickResult")
        return
    end

    if tostring(rollId) ~= tostring(State.latestRollId) then
        return
    end

    local pickChoice = tostring(choice or State.pickChoice or ""):upper()
    State.pickPending = false

    if ok == true then
        State.choicePending = false
        State.pickRetry = 0
        if pickChoice == "NEW" then
            State.selectedNew += 1
            setStatus(
                "Selected NEW on roll " .. tostring(rollId)
                    .. ". Hits this session: " .. tostring(State.selectedNew)
                    .. "\n" .. tostring(State.latestSummary),
                true
            )
            sendWebhook(
                "Auto Amulet Selected New",
                "Selected NEW on roll " .. tostring(rollId) .. ".\n" .. tostring(State.latestSummary),
                tostring(rollId) .. ":new",
                "ToggleWebhookOnNewSelected"
            )
            if Toggles.ToggleStopAfterAutoNew and Toggles.ToggleStopAfterAutoNew.Value then
                setAutoRolling(false)
            else
                scheduleNextRoll(getRollDelay())
            end
        else
            State.keptOld += 1
            if shouldHideVisuals() then
                queueVisualCleanup()
            end
            if shouldShowAutoStatus() then
                setStatus(
                    "Kept OLD. Rolls: " .. tostring(State.rolls)
                        .. " | Kept: " .. tostring(State.keptOld)
                        .. " | New: " .. tostring(State.selectedNew)
                        .. "\n" .. tostring(State.latestSummary),
                    false
                )
            end
            scheduleNextRoll(getRollDelay())
        end
        return
    end

    State.choicePending = true
    local text = tostring(message or "rejected")
    local lower = text:lower()
    local delaySeconds = lower:find("slow", 1, true) and Config.SlowRetryDelay or Config.PickRetryDelay

    if pickChoice == "OLD" then
        State.choicePending = false
        State.targetLocked = false
        State.latestTarget = nil
        State.pickRetry = 0
        if shouldShowAutoStatus() then
            setStatus(
                "Keep OLD was rejected on roll " .. tostring(rollId)
                    .. ". Rolling again after " .. tostring(math.floor(delaySeconds * 1000 + 0.5)) .. " ms.\n"
                    .. tostring(State.latestSummary),
                true
            )
        end
        scheduleNextRoll(delaySeconds)
        return
    end

    if pickChoice == "NEW" and State.pickRetry >= 8 then
        setStatus(
            "Select NEW rejected too many times. Auto stopped so the target is not skipped.\n"
                .. tostring(State.latestSummary),
            true
        )
        setAutoRolling(false)
        return
    end

    retryPick(pickChoice ~= "" and pickChoice or State.pickChoice or "OLD", text, delaySeconds)
end

rollAmuletOnce = function()
    if not State.active then
        return false
    end

    local now = os.clock()
    if State.rollPending and now - State.rollPendingAt > Config.RollTimeout then
        State.rollPending = false
        setStatus("Roll timed out. Retrying soon.\n" .. tostring(State.latestSummary), true)
    end

    if State.choicePending then
        if not State.pickPending then
            handleReadyChoice()
        end
        return false
    end

    if State.pickPending or State.rollPending or now < State.nextRollAt then
        return false
    end

    enableFastAmulets()
    if not connectAmuletEvents() then
        return false
    end

    local remote = getRemote("RollAmulet", 10)
    if not remote then
        notify("RollAmulet remote was not found.")
        return false
    end

    State.rollPending = true
    State.rollPendingAt = os.clock()
    local startedAt = State.rollPendingAt
    remote:FireServer()

    if State.rolls == 0 then
        setStatus("Rolling first amulet...", true)
    elseif isAutoRolling() and shouldShowAutoStatus() then
        setStatus("Rolling next amulet...\nLast:\n" .. tostring(State.latestSummary), false)
    elseif not isAutoRolling() then
        setStatus("Rolling amulet...\nLast:\n" .. tostring(State.latestSummary), true)
    end

    task.delay(Config.RollTimeout, function()
        if State.active and State.rollPending and State.rollPendingAt == startedAt then
            State.rollPending = false
            setStatus("Roll timed out. Retrying soon.\n" .. tostring(State.latestSummary), true)
            scheduleNextRoll(0.1)
        end
    end)
    return true
end

local function startAutoRoll()
    stopTask("AutoAmuletRoll")
    if not hasSelectedValues("AmuletOptionCounts") then
        notify("Select at least one option count first.")
        setAutoRolling(false)
        return
    end

    enableFastAmulets()
    if not connectAmuletEvents() then
        setAutoRolling(false)
        return
    end

    refreshVisualSuppression()
    Tasks.AutoAmuletRoll = task.spawn(function()
        while State.active and isAutoRolling() do
            rollAmuletOnce()
            task.wait(Config.AutoFallbackWait)
        end
        refreshVisualSuppression()
    end)
end

local function countActiveComboSlots()
    local count = 0
    for _, slot in ipairs(Extra.ComboSlots) do
        if slot.Active then
            count += 1
        end
    end
    return count
end

local function hideComboSlot(index)
    local slot = Extra.ComboSlots[index]
    if not slot then
        return false
    end

    slot.Active = false
    if slot.Dropdown then
        slot.Dropdown:SetValue({})
        slot.Dropdown:SetVisible(false)
    end
    if slot.RemoveButton then
        slot.RemoveButton:SetVisible(false)
    end
    return true
end

local function showComboSlot(index)
    local slot = Extra.ComboSlots[index]
    if not slot then
        return false
    end

    slot.Active = true
    if slot.Dropdown then
        slot.Dropdown:SetVisible(true)
    end
    if slot.RemoveButton then
        slot.RemoveButton:SetVisible(true)
    end
    return true
end

local function showNextComboSlot()
    for index = 1, Extra.ComboSlotLimit do
        if Extra.ComboSlots[index] and not Extra.ComboSlots[index].Active then
            showComboSlot(index)
            return true
        end
    end
    notify("Max combo dropdowns are already added.")
    return false
end

local function createComboSlot(groupbox, index)
    local defaultCombo = index == 1 and { "Summoner", "Corrupted" } or {}
    local slot = {
        Active = index == 1,
        DropdownId = "AmuletCustomCombo" .. tostring(index),
    }
    Extra.ComboSlots[index] = slot

    slot.Dropdown = groupbox:AddDropdown(slot.DropdownId, {
        Text = "Combo " .. tostring(index),
        Values = AmuletTypeValues,
        Multi = true,
        AllowNull = true,
        Default = defaultCombo,
    })
    slot.RemoveButton = groupbox:AddButton({
        Text = "Remove Combo " .. tostring(index),
        Func = function()
            hideComboSlot(index)
        end,
    })

    slot.Dropdown:SetVisible(slot.Active)
    slot.RemoveButton:SetVisible(slot.Active)
    return slot
end

local function restoreSavedComboSlots()
    for index, slot in ipairs(Extra.ComboSlots) do
        if slot.Dropdown and typeof(slot.Dropdown.Value) == "table" then
            for _, active in pairs(slot.Dropdown.Value) do
                if active then
                    showComboSlot(index)
                    break
                end
            end
        end
    end
end

local function hasAnyComboSelection()
    for _, slot in ipairs(Extra.ComboSlots) do
        if slot.Dropdown and typeof(slot.Dropdown.Value) == "table" then
            for _, active in pairs(slot.Dropdown.Value) do
                if active then
                    return true
                end
            end
        end
    end
    return false
end

local function setOptionValue(id, value)
    local option = Options[id]
    if option and typeof(option.SetValue) == "function" then
        pcall(function()
            option:SetValue(value)
        end)
    end
end

local function applyRecommendedTarget(force)
    if not force and (hasSelectedValues("AmuletRequiredTypes") or hasAnyComboSelection() or hasMinimumStats()) then
        return false
    end

    setOptionValue("AmuletOptionCounts", { "4" })
    setOptionValue("AmuletMatchRule", "Count + Type/Combo OR Min Total")
    setOptionValue("AmuletRequiredTypes", {})
    setOptionValue("AmuletMinimumMode", "All Active Min Totals")
    setOptionValue("AmuletMinCombinedSlimesInput", "0")
    setOptionValue("AmuletMinCombinedExpInput", "400")
    setOptionValue("AmuletMinCombinedGemsInput", "0")

    for index = 2, Extra.ComboSlotLimit do
        hideComboSlot(index)
    end
    showComboSlot(1)
    setOptionValue("AmuletCustomCombo1", { "Summoner", "Corrupted" })
    return true
end

pcall(function()
    Connections.Idled = LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

local Window = Library:CreateWindow({
    Title = "Auto Amulet Standalone",
    Footer = "disc : neonbeon | autoamulet",
    Icon = 111288992980872,
    Compact = true,
    SidebarCompactWidth = 56,
    NotifySide = "Right",
    ShowCustomCursor = false,
    UnlockMouseWhileOpen = false,
})

local Tabs = {
    Main = Window:AddTab("Auto Amulet", "gem"),
    ["UI Settings"] = Window:AddTab("UI Settings", "folder-cog"),
}

local TargetBox = Tabs.Main:AddLeftGroupbox("Target", "crosshair")
TargetBox:AddDropdown("AmuletOptionCounts", {
    Text = "Option Count",
    Values = CountValues,
    Multi = true,
    AllowNull = true,
    Default = { "4" },
})
TargetBox:AddDropdown("AmuletMatchRule", {
    Text = "Match Rule",
    Values = RuleValues,
    Default = "Count + Type/Combo OR Min Total",
})
TargetBox:AddDropdown("AmuletRequiredTypes", {
    Text = "Any Type",
    Values = AmuletTypeValues,
    Multi = true,
    AllowNull = true,
    Default = {},
})
TargetBox:AddButton({
    Text = "Add Combo",
    Func = showNextComboSlot,
})
TargetBox:AddButton({
    Text = "Use Recommended Target",
    Func = function()
        applyRecommendedTarget(true)
        notify("Target set to 4 options, Summoner + Corrupted, or 400+ Exp.")
    end,
})
for index = 1, Extra.ComboSlotLimit do
    createComboSlot(TargetBox, index)
end
TargetBox:AddDropdown("AmuletMinimumMode", {
    Text = "Min Mode",
    Values = MinModeValues,
    Default = "All Active Min Totals",
})
TargetBox:AddInput("AmuletMinCombinedSlimesInput", {
    Text = "Min Slimes Total",
    Default = "0",
    Numeric = true,
    AllowEmpty = false,
    EmptyReset = "0",
    ClearTextOnFocus = false,
    Placeholder = "0",
})
TargetBox:AddInput("AmuletMinCombinedExpInput", {
    Text = "Min Exp Total",
    Default = "400",
    Numeric = true,
    AllowEmpty = false,
    EmptyReset = "0",
    ClearTextOnFocus = false,
    Placeholder = "0",
})
TargetBox:AddInput("AmuletMinCombinedGemsInput", {
    Text = "Min Gems Total",
    Default = "0",
    Numeric = true,
    AllowEmpty = false,
    EmptyReset = "0",
    ClearTextOnFocus = false,
    Placeholder = "0",
})

local RollBox = Tabs.Main:AddRightGroupbox("Rolling", "refresh-cw")
RollBox:AddSlider("AutoAmuletRollDelayMs", {
    Text = "Extra Roll Delay",
    Min = 0,
    Max = 500,
    Default = 0,
    Rounding = 0,
    Suffix = " ms",
})
RollBox:AddSlider("AutoAmuletPickDelayMs", {
    Text = "Pick Delay",
    Min = 0,
    Max = 300,
    Default = 100,
    Rounding = 0,
    Suffix = " ms",
})
RollBox:AddSlider("AutoAmuletStatusEvery", {
    Text = "Status Every",
    Min = 1,
    Max = 50,
    Default = 10,
    Rounding = 0,
    Suffix = " rolls",
})
RollBox:AddCheckbox("ToggleAmuletHideRollVisuals", {
    Text = "Hide Roll Cards/Animation",
    Default = true,
})
RollBox:AddCheckbox("ToggleAutoAmuletSelectNew", {
    Text = "Auto Select New On Match",
    Default = true,
})
RollBox:AddCheckbox("ToggleStopAfterAutoNew", {
    Text = "Stop After Auto New",
    Default = true,
})
RollBox:AddInput("WebhookUrlInput", {
    Text = "Webhook URL",
    Default = readGlobalString("AutoAmuletWebhook"),
    Numeric = false,
    AllowEmpty = true,
    ClearTextOnFocus = false,
    Placeholder = "https://discord.com/api/webhooks/...",
})
RollBox:AddCheckbox("ToggleWebhookOnTarget", {
    Text = "Webhook On Target",
    Default = true,
})
RollBox:AddCheckbox("ToggleWebhookOnNewSelected", {
    Text = "Webhook On New",
    Default = true,
})
RollBox:AddCheckbox("ToggleAutoAmuletRoll", {
    Text = "Auto Roll",
    Default = false,
})
RollBox:AddButton({
    Text = "Roll Once",
    Func = function()
        notify("Roll fired: " .. tostring(rollAmuletOnce()))
    end,
})
RollBox:AddButton({
    Text = "Select New",
    Func = function()
        pickLatestAmulet("NEW")
    end,
})
RollBox:AddButton({
    Text = "Keep Old",
    Func = function()
        pickLatestAmulet("OLD")
    end,
})
RollBox:AddButton({
    Text = "Test Webhook",
    Func = function()
        if sendWebhook(
            "Auto Amulet Test",
            "Webhook test from the standalone auto amulet script.",
            "test-" .. tostring(os.clock()),
            "ToggleWebhookOnTarget"
        ) then
            notify("Webhook test sent.")
        else
            notify("Webhook not sent. Check URL and toggle.")
        end
    end,
})
RollBox:AddButton({
    Text = "Reset Counters",
    Func = function()
        State.rolls = 0
        State.keptOld = 0
        State.selectedNew = 0
        setStatus("Counters reset.\n" .. tostring(State.latestSummary), true)
    end,
})
StatusLabel = RollBox:AddLabel({
    Text = State.latestSummary,
    DoesWrap = true,
})

Toggles.ToggleAutoAmuletRoll:OnChanged(function(enabled)
    if State.loadingSettings then
        return
    end

    if enabled then
        startAutoRoll()
    else
        stopTask("AutoAmuletRoll")
        refreshVisualSuppression()
        setStatus("Auto roll stopped.\n" .. tostring(State.latestSummary), true)
    end
end)

Toggles.ToggleAmuletHideRollVisuals:OnChanged(function()
    refreshVisualSuppression()
end)

Toggles.ToggleAutoAmuletSelectNew:OnChanged(function(enabled)
    if enabled and State.choicePending and State.latestTarget and not State.pickPending then
        pickLatestAmulet("NEW", true)
    end
end)

Library:OnUnload(function()
    State.active = false
    for name in pairs(Tasks) do
        stopTask(name)
    end
    restoreAmuletVisualConnections()
    for name in pairs(Connections) do
        disconnect(name)
    end
end)

do
    local UISettings = Tabs["UI Settings"]:AddRightGroupbox("General", "wrench")
    UISettings:AddLabel("MenuBind"):AddKeyPicker("MenuKeybind", {
        Default = "RightShift",
        NoUI = true,
        Text = "Menu keybind",
    })
    UISettings:AddButton({
        Text = "Unload",
        Func = function()
            Library:Unload()
        end,
    })
end

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("PhosphyHub")
ThemeManager:SetDefaultTheme({
    FontColor = Color3.fromRGB(220, 255, 250),
    MainColor = Color3.fromRGB(25, 25, 25),
    AccentColor = Color3.fromRGB(0, 200, 180),
    BackgroundColor = Color3.fromRGB(15, 15, 15),
    OutlineColor = Color3.fromRGB(0, 95, 85),
})
ThemeManager:ApplyToTab(Tabs["UI Settings"])
ThemeManager:LoadDefault()

SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
SaveManager:SetFolder("PhosphyHub")
SaveManager:SetSubFolder("AutoAmuletStandalone")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
State.loadingSettings = true
SaveManager:LoadAutoloadConfig()
State.loadingSettings = false

restoreSavedComboSlots()
applyRecommendedTarget(false)
connectAmuletEvents()
enableFastAmulets()
refreshVisualSuppression()
setStatus(State.latestSummary, true)

if Toggles.ToggleAutoAmuletRoll and Toggles.ToggleAutoAmuletRoll.Value then
    startAutoRoll()
end
