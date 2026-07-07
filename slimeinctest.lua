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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Options = Library.Options
local Toggles = Library.Toggles
local Session = "phosphy-slime-" .. tostring(os.clock())
local Tasks = {}
local Connections = {}
local LastSentAt = {}
local TotemIds = {}
local SpeedHumanoid = nil
local OriginalWalkSpeed = nil
local LatestAmuletRollId = nil
local LatestAmuletSummary = "No amulet roll yet."
local LatestAmuletTarget = nil
local LatestAmuletTargetIndex = nil
local AmuletRollPending = false
local AmuletChoicePending = false
local AmuletPickPending = false
local AmuletStatusLabel = nil
local FastAmuletsRequested = false
local DataController = nil
local Extra = {
    Version = "1.3.24",
    PerfLighting = game:GetService("Lighting"),
    BlessingActionPending = false,
    BlessingActionSerial = 0,
    BlessingActionTimeout = 0.45,
    BlessingFailureRetrySeconds = 1,
    BlessingOptionFields = { "key", "name", "id", "blessing" },
    BlessingRemotes = {},
    RemoteCache = {},
    RemoteRoot = nil,
    CleanbotRollPending = false,
    CleanbotRollSerial = 0,
    BossState = {
        status = "unknown",
        health = 0,
        maxHealth = 0,
    },
    BossLastStateRequestAt = 0,
    BossLastStartRequestAt = 0,
    BossMoveCFrame = nil,
    BossMoveUntil = 0,
    BossMoveReason = nil,
    BossParrySent = {},
    BossSplitPickups = {},
    BossCardPickPending = {},
    BossLastVictoryPayload = nil,
    BossLastVictoryCloseAt = 0,
    BossCardSpendActive = false,
    BossCardStatusAt = 0,
    BossKillCoins = nil,
    BossCoinsLabel = nil,
    BossStatusLabel = nil,
    UndeadMiniBoss = nil,
    UndeadLastStateRequestAt = 0,
    UndeadLastHitAt = 0,
    UndeadStatusLabel = nil,
    QuestClaimLastAttempt = {},
    QuestClaimStatusLabel = nil,
    Constants = nil,
    SpawnIdQueue = {},
    SpawnIdQueued = {},
    AutoMidasGoldCount = 0,
    AutoMidasGoldCountSource = "session",
    AutoMidasHeldGoldBar = nil,
    BuffComboHeldGoldBar = nil,
    BuffComboLastCrateClaimAt = 0,
    BuffComboRunning = false,
    BuffComboFreshTotemId = nil,
    BuffComboFreshTotemExpiresAt = 0,
    BuffComboIgnoredTotems = {},
    AmuletNextRollAt = 0,
    AmuletPickTimeout = 0.75,
    AmuletNextRollDelay = 0.12,
    AmuletTargetLocked = false,
    AmuletStatusLastDisplayAt = 0,
    AmuletRollPendingAt = 0,
    AmuletRollResultHandler = nil,
    AmuletPickResultHandler = nil,
    AmuletSuppressedConnections = {},
    AmuletVisualConnectionsDisabled = false,
    StardustMachineRequestCooldown = 60,
    StardustReadyPrinted = false,
}
local ReadyActionLastFiredAt = {}
local PotionRequestedUntil = {}
local ActiveBoosts = {}
local BoostStateReady = false
local BoostStateLastRequestedAt = 0
local FallingStarMovePosition = nil
local FallingStarMoveUntil = 0
local MidasMovePosition = nil
local MidasMoveUntil = 0
local MidasLastCollectAt = {}
local PalCollectionActive = false
local AutofarmCFrame = CFrame.new(
    -5.32521152,
    4.3090837,
    -6.48988485,
    0.99855119,
    0.014181748,
    0.05190669,
    -0.0107820705,
    0.997814,
    -0.0651995018,
    -0.0527178794,
    0.064545393,
    0.996521235
)

local Marker = Workspace:FindFirstChild("PhosphySlimeCollector")
if not Marker then
    Marker = Instance.new("Folder")
    Marker.Name = "PhosphySlimeCollector"
    Marker.Parent = Workspace
end
Marker:SetAttribute("Session", Session)
Marker:SetAttribute("Enabled", false)

LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

local function notify(message)
    if Library and Library.Notify then
        Library:Notify(message)
    else
        warn("[Phosphy Slime] " .. tostring(message))
    end
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
    local cached = Extra.RemoteCache[name]
    if cached and cached.Parent then
        return cached
    end

    local remotes = getRemotes()
    if not remotes then
        return nil
    end

    local remote = remotes:FindFirstChild(name) or remotes:WaitForChild(name, waitSeconds or 10)
    if remote then
        Extra.RemoteCache[name] = remote
    end
    return remote
end

function Extra.setExecutorConnectionEnabled(connection, enabled)
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
        local changed = pcall(function()
            connection.Enabled = enabled
        end)
        return changed
    end

    return false
end

function Extra.getExecutorConnectionCallback(connection)
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

function Extra.getFunctionDebugText(callback)
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

function Extra.isAmuletVisualCallback(callback)
    return Extra.getFunctionDebugText(callback):find("ExportedGuiWiring", 1, true) ~= nil
end

function Extra.fireExecutorConnection(connection, callback, ...)
    for _, methodName in ipairs({ "Fire", "fire" }) do
        local ok, method = pcall(function()
            return connection[methodName]
        end)

        if ok and typeof(method) == "function" then
            local fired = pcall(method, connection, ...)
            if not fired then
                fired = pcall(method, ...)
            end
            if fired then
                return true
            end
        end
    end

    if typeof(callback) == "function" then
        return pcall(callback, ...)
    end

    return false
end

function Extra.amuletVisualSuppressionEnabled()
    return not Toggles.ToggleAmuletHideRollVisuals
        or Toggles.ToggleAmuletHideRollVisuals.Value == true
end

function Extra.autoAmuletRollEnabled()
    return Toggles.ToggleAutoAmuletRoll
        and Toggles.ToggleAutoAmuletRoll.Value == true
end

function Extra.shouldSuppressAmuletRollVisuals()
    return Extra.amuletVisualSuppressionEnabled()
        and Extra.autoAmuletRollEnabled()
        and not Extra.AmuletTargetLocked
end

function Extra.isOwnAmuletSignalConnection(connection)
    local callback = Extra.getExecutorConnectionCallback(connection)

    return typeof(callback) == "function"
        and (callback == Extra.AmuletRollResultHandler or callback == Extra.AmuletPickResultHandler)
end

function Extra.enableAllAmuletSignalConnections()
    if typeof(getconnections) ~= "function" then
        return 0
    end

    local enabled = 0
    for _, remoteName in ipairs({ "AmuletRollResult", "AmuletPickResult" }) do
        local remote = getRemote(remoteName, 2)
        if remote then
            local ok, signalConnections = pcall(getconnections, remote.OnClientEvent)
            if ok and typeof(signalConnections) == "table" then
                for _, connection in ipairs(signalConnections) do
                    if Extra.setExecutorConnectionEnabled(connection, true) then
                        enabled += 1
                    end
                end
            end
        end
    end

    Marker:SetAttribute("AmuletSignalConnectionsEnabled", enabled)
    return enabled
end

function Extra.disableAmuletVisualConnections()
    if not Extra.amuletVisualSuppressionEnabled() then
        return false
    end

    if Extra.AmuletVisualConnectionsDisabled then
        return true
    end

    if typeof(getconnections) ~= "function" then
        Marker:SetAttribute("AmuletVisualSuppressor", "getconnections unavailable")
        return false
    end

    local disabled = 0
    for _, remoteName in ipairs({ "AmuletRollResult" }) do
        local remote = getRemote(remoteName, 2)
        if remote then
            local ok, signalConnections = pcall(getconnections, remote.OnClientEvent)
            if ok and typeof(signalConnections) == "table" then
                for _, connection in ipairs(signalConnections) do
                    local callback = Extra.getExecutorConnectionCallback(connection)
                    if not Extra.isOwnAmuletSignalConnection(connection)
                        and Extra.isAmuletVisualCallback(callback) then
                        if Extra.setExecutorConnectionEnabled(connection, false) then
                            disabled += 1
                            Extra.AmuletSuppressedConnections[#Extra.AmuletSuppressedConnections + 1] = {
                                Connection = connection,
                                RemoteName = remoteName,
                                Callback = Extra.getExecutorConnectionCallback(connection),
                            }
                        end
                    end
                end
            end
        end
    end

    Marker:SetAttribute("AmuletVisualConnectionsDisabled", disabled)
    Marker:SetAttribute("AmuletVisualSuppressor", disabled > 0 and "connection filter" or "cleanup only")
    Extra.AmuletVisualConnectionsDisabled = disabled > 0
    return disabled > 0
end

function Extra.restoreAmuletVisualConnections()
    for _, entry in ipairs(Extra.AmuletSuppressedConnections) do
        Extra.setExecutorConnectionEnabled(entry.Connection or entry, true)
    end

    Extra.enableAllAmuletSignalConnections()
    Extra.AmuletSuppressedConnections = {}
    Extra.AmuletVisualConnectionsDisabled = false
    Marker:SetAttribute("AmuletVisualConnectionsDisabled", 0)
    Marker:SetAttribute("AmuletVisualSuppressor", "off")
end

function Extra.showAmuletRollVisualsForTarget(options, rollId)
    local suppressedConnections = Extra.AmuletSuppressedConnections
    stopTask("AmuletVisualCleanup")
    Extra.restoreAmuletVisualConnections()

    if #suppressedConnections == 0 then
        Marker:SetAttribute("AmuletTargetVisualsReplayed", 0)
        Marker:SetAttribute("AmuletVisualSuppressor", "target live")
        return false
    end

    Extra.cleanupAmuletRollVisuals()

    local replayed = 0
    for _, entry in ipairs(suppressedConnections) do
        if entry.RemoteName == "AmuletRollResult" then
            if Extra.fireExecutorConnection(entry.Connection, entry.Callback, options, rollId) then
                replayed += 1
            end
        end
    end

    Marker:SetAttribute("AmuletTargetVisualsReplayed", replayed)
    Marker:SetAttribute("AmuletVisualSuppressor", replayed > 0 and "target replay" or "target restored")
    return replayed > 0
end

function Extra.cleanupAmuletRollVisuals()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        local amuletsGui = playerGui:FindFirstChild("AmuletsGui")
        local dropped = amuletsGui and amuletsGui:FindFirstChild("DroppedAmuletsGui", true)
        if dropped and dropped:IsA("GuiObject") then
            dropped.Visible = false
            dropped.BackgroundTransparency = 1
        end

        local function clearContainer(container)
            if not container or not container:IsA("GuiObject") then
                return
            end

            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("GuiObject") then
                    child:Destroy()
                end
            end
        end

        if dropped then
            clearContainer(dropped:FindFirstChild("LeftAmulets"))
            clearContainer(dropped:FindFirstChild("RightAmulets"))
        else
            for _, item in ipairs(playerGui:GetDescendants()) do
                if item.Name == "DroppedAmuletsGui" and item:IsA("GuiObject") then
                    item.Visible = false
                    item.BackgroundTransparency = 1
                elseif item.Name == "LeftAmulets" or item.Name == "RightAmulets" then
                    clearContainer(item)
                end
            end
        end

        local background = amuletsGui and amuletsGui:FindFirstChild("Background")
        if background and background:IsA("GuiObject") then
            background.BackgroundTransparency = 1
            if background:IsA("ImageLabel") or background:IsA("ImageButton") then
                background.ImageTransparency = 1
            end
        end

        local blur = Extra.PerfLighting and Extra.PerfLighting:FindFirstChild("Blur")
        if blur and blur:IsA("BlurEffect") then
            blur.Size = 0
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

function Extra.queueAmuletRollVisualCleanup()
    Extra.cleanupAmuletRollVisuals()
    task.defer(function()
        Extra.cleanupAmuletRollVisuals()
    end)
    task.delay(0.05, function()
        Extra.cleanupAmuletRollVisuals()
    end)
    task.delay(0.15, function()
        Extra.cleanupAmuletRollVisuals()
    end)
end

function Extra.startAmuletVisualCleanup()
    if Tasks.AmuletVisualCleanup then
        return
    end

    Tasks.AmuletVisualCleanup = task.spawn(function()
        while Extra.shouldSuppressAmuletRollVisuals() do
            Extra.cleanupAmuletRollVisuals()
            task.wait(0.08)
        end

        Tasks.AmuletVisualCleanup = nil
    end)
end

function Extra.refreshAmuletVisualSuppression()
    if Extra.shouldSuppressAmuletRollVisuals() then
        if not Extra.AmuletVisualConnectionsDisabled then
            Extra.enableAllAmuletSignalConnections()
        end
        Extra.disableAmuletVisualConnections()
        Extra.queueAmuletRollVisualCleanup()
        Extra.startAmuletVisualCleanup()
    else
        stopTask("AmuletVisualCleanup")
        Extra.restoreAmuletVisualConnections()
    end
end

local function getProfileData()
    if not DataController then
        local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
        local client = playerScripts and playerScripts:FindFirstChild("Client")
        local controllers = client and client:FindFirstChild("Controllers")
        local module = controllers and controllers:FindFirstChild("DataController")

        if module and module:IsA("ModuleScript") then
            local ok, controller = pcall(require, module)
            if ok and typeof(controller) == "table" then
                DataController = controller
            end
        end
    end

    if DataController and typeof(DataController.get) == "function" then
        local ok, data = pcall(DataController.get)
        if ok then
            return data
        end
    end

    return nil
end

function Extra.getBlessingController()
    if Extra.BlessingController then
        return Extra.BlessingController
    end

    local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
    local client = playerScripts and playerScripts:FindFirstChild("Client")
    local controllers = client and client:FindFirstChild("Controllers")
    local module = controllers and controllers:FindFirstChild("BlessingController")
    if module and module:IsA("ModuleScript") then
        local ok, controller = pcall(require, module)
        if ok and typeof(controller) == "table" then
            Extra.BlessingController = controller
        end
    end

    return Extra.BlessingController
end

local function applyBoostState(profileOrBoosts)
    local boosts = profileOrBoosts
    if typeof(profileOrBoosts) == "table" and typeof(profileOrBoosts.boosts) == "table" then
        boosts = profileOrBoosts.boosts
    end

    if typeof(boosts) ~= "table" then
        return false
    end

    ActiveBoosts = table.clone(boosts)
    BoostStateReady = true
    return true
end

local function ensureBoostState()
    local remotes = getRemotes()
    if not remotes then
        return
    end

    local profileLoaded = remotes:FindFirstChild("ProfileLoaded")
    if profileLoaded and not Connections.PotionProfileLoaded then
        Connections.PotionProfileLoaded = profileLoaded.OnClientEvent:Connect(function(profile)
            applyBoostState(profile)
        end)
    end

    local profileUpdated = remotes:FindFirstChild("ProfileUpdated")
    if profileUpdated and not Connections.PotionProfileUpdated then
        Connections.PotionProfileUpdated = profileUpdated.OnClientEvent:Connect(function(field, value)
            if field == "boosts" then
                applyBoostState(value)
            end
        end)
    end

    local profileUpdatedBatch = remotes:FindFirstChild("ProfileUpdatedBatch")
    if profileUpdatedBatch and not Connections.PotionProfileUpdatedBatch then
        Connections.PotionProfileUpdatedBatch = profileUpdatedBatch.OnClientEvent:Connect(function(updates)
            if typeof(updates) == "table" and updates.boosts ~= nil then
                applyBoostState(updates.boosts)
            end
        end)
    end

    local boostActivated = remotes:FindFirstChild("BoostActivated")
    if boostActivated and not Connections.PotionBoostActivated then
        Connections.PotionBoostActivated = boostActivated.OnClientEvent:Connect(function(boostId, expiresAt)
            if typeof(boostId) == "string" and typeof(expiresAt) == "number" then
                ActiveBoosts[boostId] = expiresAt
                BoostStateReady = true
            end
        end)
    end

    local now = os.clock()
    if not BoostStateReady and now - BoostStateLastRequestedAt >= 3 then
        local requestProfile = remotes:FindFirstChild("RequestProfile")
        if requestProfile then
            BoostStateLastRequestedAt = now
            requestProfile:FireServer()
        end
    end
end

local function isBoostActive(boostId)
    local profile = getProfileData()
    local boosts = profile and profile.boosts
    if typeof(boosts) == "table" then
        applyBoostState(boosts)
    else
        ensureBoostState()
    end

    if not BoostStateReady then
        return nil
    end

    local expiresAt = ActiveBoosts[boostId]
    return typeof(expiresAt) == "number" and os.time() < expiresAt
end

function Extra.getBoostRemainingSeconds(boostId)
    local active = isBoostActive(boostId)
    if active ~= true then
        return active, 0
    end

    local expiresAt = ActiveBoosts[boostId]
    if typeof(expiresAt) ~= "number" then
        return true, nil
    end

    return true, math.max(0, expiresAt - os.time())
end

function Extra.formatShortSeconds(seconds)
    if typeof(seconds) ~= "number" then
        return ""
    end

    seconds = math.max(0, math.ceil(seconds))
    local minutes = math.floor(seconds / 60)
    local remainder = seconds % 60
    if minutes > 0 then
        return string.format(" (%d:%02d)", minutes, remainder)
    end
    return string.format(" (%ds)", remainder)
end

local function canFireReadyAction(name, minimumDelay)
    local now = os.clock()
    local lastFiredAt = ReadyActionLastFiredAt[name] or 0
    if now - lastFiredAt < (minimumDelay or 2) then
        return false
    end

    ReadyActionLastFiredAt[name] = now
    return true
end

local function getCollectSlimesRemote() return getRemote("CollectSlimes", 10) end
local function getActivateEmpoweredBoostRemote() return getRemote("ActivateEmpoweredBoost", 10) end
local function getUsePotionRemote() return getRemote("UsePotion", 10) end
local function getPurchaseShopItemRemote() return getRemote("PurchaseShopItem", 10) end
local function getActivatePlinkoBallRemote() return getRemote("ActivatePlinkoBall", 10) end
local function getCrateCollectedRemote() return getRemote("CrateCollected", 10) end
local function getGodlyOrbCollectedRemote() return getRemote("GodlyOrbCollected", 10) end
local function getGemBobAbilityRequestedRemote() return getRemote("GemBobAbilityRequested", 10) end
local function getGemBobGemBatchRemote() return getRemote("GemBobGemBatch", 10) end
local function getCollectGemBobGemsRemote() return getRemote("CollectGemBobGems", 10) end
local function getRollRoombaRemote() return getRemote("RollRoomba", 10) end
local function getRoombaRollResultRemote() return getRemote("RoombaRollResult", 10) end
local function getActivateStardustMachineRemote() return getRemote("ActivateStardustMachine", 10) end
local function getStardustStarFallingRemote() return getRemote("StardustStarFalling", 10) end
local function getFallingStarAwardedRemote() return getRemote("FallingStarAwarded", 10) end

local function getSlimesFolder()
    local runtime = Workspace:FindFirstChild("Runtime") or Workspace:WaitForChild("Runtime", 10)
    if not runtime then
        return nil
    end
    return runtime:FindFirstChild("Slimes") or runtime:WaitForChild("Slimes", 10)
end

local function getRoot()
    local character = LocalPlayer.Character
    if not character then
        return nil
    end

    local root = character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        return root
    end

    return nil
end

local function getHumanoid()
    local character = LocalPlayer.Character
    if not character then
        return nil
    end

    return character:FindFirstChildOfClass("Humanoid")
end

function Extra.instanceCFrame(value)
    if typeof(value) == "CFrame" then
        return value
    end
    if typeof(value) == "Vector3" then
        return CFrame.new(value)
    end
    if typeof(value) == "string" then
        value = Workspace:FindFirstChild(value, true)
    end
    if typeof(value) ~= "Instance" or not value.Parent then
        return nil
    end
    if value:IsA("BasePart") then
        return value.CFrame
    end
    if value:IsA("Model") then
        return value:GetPivot()
    end

    local part = value:FindFirstChildWhichIsA("BasePart", true)
    return part and part.CFrame or nil
end

local function setFallingStarMovementTarget(position, holdSeconds)
    if typeof(position) ~= "Vector3" then
        return
    end

    FallingStarMovePosition = position
    FallingStarMoveUntil = os.clock() + math.max(0.35, tonumber(holdSeconds) or 0.35)
end

local function getTotemAreaCFrame()
    local totem = Workspace:FindFirstChild("Totem")
    local area = totem and totem:FindFirstChild("TotemArea")
    if not area then
        return nil, nil
    end

    if area:IsA("BasePart") then
        return area.CFrame, area
    end

    if area:IsA("Model") then
        return area:GetPivot(), area
    end

    return nil, area
end

local function getPriorityMovementTarget()
    if PalCollectionActive then
        return nil, "Collecting Pals"
    end

    if Extra.getBossPriorityMovementTarget then
        local bossTarget, bossReason = Extra.getBossPriorityMovementTarget()
        if bossTarget then
            return bossTarget, bossReason or "Boss"
        end
    end

    if Extra.BossMoveCFrame and os.clock() <= (Extra.BossMoveUntil or 0)
        and Toggles.ToggleAutoBossMove and Toggles.ToggleAutoBossMove.Value
        and ((Toggles.ToggleAutoBossFight and Toggles.ToggleAutoBossFight.Value)
        or (Toggles.ToggleAutoBossStart and Toggles.ToggleAutoBossStart.Value)
        or (Toggles.ToggleAutoBossPayOpen and Toggles.ToggleAutoBossPayOpen.Value)
        or (Toggles.ToggleAutoUndeadBoss and Toggles.ToggleAutoUndeadBoss.Value)) then
        return Extra.BossMoveCFrame, Extra.BossMoveReason or "Boss"
    end

    Extra.BossMoveCFrame = nil
    Extra.BossMoveUntil = 0
    Extra.BossMoveReason = nil

    if FallingStarMovePosition and os.clock() <= FallingStarMoveUntil then
        return CFrame.new(FallingStarMovePosition + Vector3.new(0, 3, 0)), "Falling Star"
    end

    FallingStarMovePosition = nil
    FallingStarMoveUntil = 0

    if MidasMovePosition and os.clock() <= MidasMoveUntil then
        return CFrame.new(MidasMovePosition + Vector3.new(0, 3, 0)), "Midas Bar"
    end

    MidasMovePosition = nil
    MidasMoveUntil = 0

    if Extra.CSlimeMoveCFrame and Toggles.ToggleAutoCSlime and Toggles.ToggleAutoCSlime.Value then
        return Extra.CSlimeMoveCFrame, "CS Slime"
    end

    local autoFarm = Toggles.ToggleAutoFarm and Toggles.ToggleAutoFarm.Value
    local autoTotem = Toggles.ToggleAutoTotemContact and Toggles.ToggleAutoTotemContact.Value
    if autoTotem then
        local totemCFrame = getTotemAreaCFrame()
        if totemCFrame then
            return totemCFrame, "Totem"
        end
    end

    if autoFarm then
        return AutofarmCFrame, "Autofarm"
    end

    return nil, "None"
end

local function startMovementCoordinator()
    disconnect("MovementCoordinator")
    local lastMode = "None"

    Connections.MovementCoordinator = RunService.Heartbeat:Connect(function()
        if Marker:GetAttribute("Session") ~= Session then
            disconnect("MovementCoordinator")
            return
        end

        local target, mode = getPriorityMovementTarget()
        local root = getRoot()
        if target and root then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = target
        end

        if mode ~= lastMode then
            lastMode = mode
            Marker:SetAttribute("MovementPriority", mode)
        end
    end)
end

local PalDefinitions = {
    { key = "mx6rt", displayName = "mx6rt", path = { "Zones", "Lvl125", "mx6rt" } },
    { key = "papaBear", displayName = "Papa Bear Candied, Destroyer of Worlds", path = { "Zones", "Lvl125", "Papa Bear Candied, Destroyer of Worlds" } },
    { key = "pieselo", displayName = "Pieselo", path = { "Zones", "Tier15", "Pieselo" } },
    { key = "wrkiRvAlaa", displayName = "WRKiRvAlaa", path = { "Zones", "Lvl50", "WRKiRvAlaa" } },
    { key = "blazdij", displayName = "blazdij", path = { "Zones", "Lvl50", "blazdij" } },
    { key = "mask", displayName = "Mask", path = { "Zones", "Tier15", "Mask" } },
    { key = "adi", displayName = "Adi", path = { "Zones", "Lvl75", "Adi" } },
    { key = "angy", displayName = "Angy", path = { "Zones", "Lvl225", "Angy" } },
    { key = "bombixa", displayName = "Bombixa", path = { "Map", "Bombixa" } },
    { key = "czonik", displayName = "Czonik", path = { "Zones", "Tier15", "Czonik" } },
    { key = "diament", displayName = "Diament", path = { "Zones", "Lvl175", "Diament" } },
    { key = "dreamless", displayName = "Dreamless", path = { "Zones", "Lvl200", "Dreamless" } },
    { key = "duckyDMan", displayName = "DuckyDMan", path = { "Zones", "Lvl10", "DuckyDMan" } },
    { key = "dzej", displayName = "Dzej", path = { "Zones", "Lvl150", "Dzej" } },
    { key = "kubos", displayName = "Kubos", path = { "Zones", "Lvl5", "Kubos" } },
    { key = "ni3znajomy", displayName = "Ni3znajomy", path = { "Zones", "Lvl25", "Ni3znajomy" } },
    { key = "res", displayName = "Res", path = { "Zones", "Lvl175", "Res" } },
    { key = "sirYStudio", displayName = "SirY_Studio", path = { "Map", "SirY_Studio" } },
    { key = "voidWisp", displayName = "VoidWisp", path = { "Map", "VoidWisp" } },
    { key = "yesen2", displayName = "yesen2", path = { "Zones", "Lvl175", "yesen2" } },
    { key = "bartero111", displayName = "Bartero111" },
}

local function resolvePalInstance(definition)
    if definition.key == "bartero111" then
        local crate = Workspace:FindFirstChild("GoldenSlimeCrate", true)
        local bartero = crate and crate:FindFirstChild("Bartero111", true)
        if bartero and (bartero:IsA("BasePart") or bartero:IsA("Model")) then
            return bartero
        end
    end

    local path = definition.path
    local target = path and Workspace:FindFirstChild(path[1], true) or nil
    if target then
        for index = 2, #path do
            target = target and target:FindFirstChild(path[index]) or nil
        end
    end

    if target and (target:IsA("BasePart") or target:IsA("Model")) then
        return target
    end

    for _, instance in ipairs(Workspace:GetDescendants()) do
        if (instance:IsA("BasePart") or instance:IsA("Model"))
            and (instance.Name == definition.displayName or instance.Name == definition.key)
            and not instance:GetFullName():find("DisplayPals", 1, true) then
            return instance
        end
    end

    return nil
end

local function palInstanceCFrame(instance)
    if instance:IsA("BasePart") then
        return instance.CFrame
    end
    if instance:IsA("Model") then
        return instance:GetPivot()
    end
    return nil
end

local function applyTemporaryNoclip(states)
    local character = LocalPlayer.Character
    if not character then
        return
    end

    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            if states[part] == nil then
                states[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end
end

local function collectAllPals()
    if PalCollectionActive then
        return 0, 0, "Pal collection is already running."
    end

    local remote = getRemote("PalFound", 10)
    local root = getRoot()
    if not remote or not root then
        return 0, #PalDefinitions, "Pal remote or character root was not found."
    end

    PalCollectionActive = true
    local startCFrame = root.CFrame
    local collisionStates = {}
    local noclipConnection = RunService.Stepped:Connect(function()
        applyTemporaryNoclip(collisionStates)
    end)
    applyTemporaryNoclip(collisionStates)

    local fired = 0
    local missing = 0
    local ok, err = pcall(function()
        for _, definition in ipairs(PalDefinitions) do
            local target = resolvePalInstance(definition)
            local targetCFrame = target and palInstanceCFrame(target) or nil
            local currentRoot = getRoot()

            if targetCFrame and currentRoot then
                currentRoot.AssemblyLinearVelocity = Vector3.zero
                currentRoot.AssemblyAngularVelocity = Vector3.zero
                currentRoot.CFrame = targetCFrame + Vector3.new(0, 3, 0)
                task.wait(0.25)
                remote:FireServer(definition.key)
                fired += 1
                task.wait(0.15)
            else
                missing += 1
            end
        end
    end)

    noclipConnection:Disconnect()
    for part, canCollide in pairs(collisionStates) do
        if part.Parent then
            part.CanCollide = canCollide
        end
    end

    local returnRoot = getRoot()
    if returnRoot then
        returnRoot.AssemblyLinearVelocity = Vector3.zero
        returnRoot.AssemblyAngularVelocity = Vector3.zero
        returnRoot.CFrame = startCFrame
    end
    PalCollectionActive = false

    Marker:SetAttribute("PalsLastFireCount", fired)
    Marker:SetAttribute("PalsLastMissingCount", missing)
    Marker:SetAttribute("PalsLastCollectAt", Workspace:GetServerTimeNow())

    if not ok then
        return fired, missing, tostring(err)
    end
    return fired, missing, nil
end

local function unlockVault()
    local remote = getRemote("OpenedSafe", 10)
    if not remote then
        return false
    end

    local args = {
        { 4, 6, 2, 9 },
    }
    remote:FireServer(unpack(args))
    Marker:SetAttribute("VaultUnlockRequestedAt", Workspace:GetServerTimeNow())
    return true
end

local function applyPlayerSpeed()
    local humanoid = getHumanoid()
    if not humanoid then
        return false
    end

    if humanoid ~= SpeedHumanoid then
        SpeedHumanoid = humanoid
        OriginalWalkSpeed = humanoid.WalkSpeed
    end

    local speedOption = Options.PlayerSpeed
    local speed = math.max(0, tonumber(speedOption and speedOption.Value) or 50)
    if humanoid.WalkSpeed ~= speed then
        humanoid.WalkSpeed = speed
    end
    Marker:SetAttribute("PlayerSpeed", speed)
    return true
end

local function stopPlayerSpeed()
    disconnect("PlayerSpeed")

    if SpeedHumanoid and SpeedHumanoid.Parent and OriginalWalkSpeed then
        SpeedHumanoid.WalkSpeed = OriginalWalkSpeed
    end

    SpeedHumanoid = nil
    OriginalWalkSpeed = nil
    Marker:SetAttribute("PlayerSpeedEnabled", false)
end

local function startPlayerSpeed()
    disconnect("PlayerSpeed")
    Marker:SetAttribute("PlayerSpeedEnabled", true)
    applyPlayerSpeed()

    Connections.PlayerSpeed = RunService.Heartbeat:Connect(function()
        if not (Toggles.TogglePlayerSpeed and Toggles.TogglePlayerSpeed.Value) then
            stopPlayerSpeed()
            return
        end

        applyPlayerSpeed()
    end)
end

local function getSlimePosition(slime)
    if slime:IsA("BasePart") then
        return slime.Position
    end

    if slime:IsA("Model") then
        if slime.PrimaryPart then
            return slime.PrimaryPart.Position
        end

        local part = slime:FindFirstChildWhichIsA("BasePart", true)
        if part then
            return part.Position
        end
    end

    return nil
end

local function getSlimeId(slime)
    local id = slime:GetAttribute("SlimeId")
    if typeof(id) == "number" or typeof(id) == "string" then
        return tostring(id)
    end

    local fromName = tostring(slime.Name):match("%d+")
    if fromName then
        return tostring(fromName)
    end

    return nil
end

local function getNumberOption(id, fallback)
    local option = Options[id]
    local value = option and option.Value
    value = tonumber(value)
    if value == nil then
        return fallback
    end
    return value
end

local function getRadius()
    return math.max(1, getNumberOption("CollectorRadius", 5000))
end

local function getBatchSize()
    return math.max(1, math.floor(getNumberOption("CollectorBatchSize", 500)))
end

local function getRetryDelay()
    return 0.3
end

local function getTickDelay()
    return 0.05
end

local function getActualCollectorParticle()
    local collector = Workspace:FindFirstChild("Collector", true)
    if not collector then
        return nil
    end

    local attachment = collector:FindFirstChild("Attachment")
    if not attachment then
        return nil
    end

    local particle = attachment:FindFirstChild("KolkoParticle")
    if particle and particle:IsA("ParticleEmitter") then
        return particle
    end

    return nil
end

local function resizeActualCollectorRing()
    if not Toggles.ToggleActualRing or not Toggles.ToggleActualRing.Value then
        return
    end

    local particle = getActualCollectorParticle()
    if not particle then
        return
    end

    local ringSize = math.max(2, getRadius())
    particle.Size = NumberSequence.new(ringSize)
end

local function collectIds(ids)
    if #ids == 0 then
        return false
    end

    local collectSlimes = getCollectSlimesRemote()
    if not collectSlimes then
        notify("CollectSlimes remote was not found.")
        return false
    end

    collectSlimes:FireServer(ids)
    return true
end

function Extra.queueSpawnId(id, spawnCFrame)
    if typeof(id) ~= "string" or id == "" or Extra.SpawnIdQueued[id] then
        return false
    end

    local position = nil
    if typeof(spawnCFrame) == "CFrame" then
        position = spawnCFrame.Position
    elseif typeof(spawnCFrame) == "Vector3" then
        position = spawnCFrame
    end

    Extra.SpawnIdQueued[id] = true
    Extra.SpawnIdQueue[#Extra.SpawnIdQueue + 1] = {
        id = id,
        position = position,
    }
    return true
end

function Extra.flushSpawnIds()
    if #Extra.SpawnIdQueue == 0 then
        return 0
    end

    local root = getRoot()
    if not root then
        return 0
    end

    local now = os.clock()
    local radius = getRadius()
    local collectAll = Toggles.ToggleCollectAll and Toggles.ToggleCollectAll.Value
    local batchSize = getBatchSize()
    local ids = {}

    while #ids < batchSize and #Extra.SpawnIdQueue > 0 do
        local entry = table.remove(Extra.SpawnIdQueue, 1)
        Extra.SpawnIdQueued[entry.id] = nil

        local inRange = entry.position == nil or (entry.position - root.Position).Magnitude <= radius
        if collectAll or inRange then
            LastSentAt[entry.id] = now
            ids[#ids + 1] = entry.id
        end
    end

    if collectIds(ids) then
        Marker:SetAttribute("InstantSpawnLastBatch", #ids)
        Marker:SetAttribute("InstantSpawnLastFireAt", Workspace:GetServerTimeNow())
        return #ids
    end

    return 0
end

function Extra.stopInstantSpawnCollector()
    stopTask("InstantSpawnCollector")
    disconnect("InstantSlimeSpawned")
    disconnect("InstantSlimeSpawnedBatch")
    table.clear(Extra.SpawnIdQueue)
    table.clear(Extra.SpawnIdQueued)
    Marker:SetAttribute("InstantSpawnCollector", false)
end

function Extra.startInstantSpawnCollector()
    Extra.stopInstantSpawnCollector()

    local spawned = getRemote("SlimeSpawned", 10)
    local spawnedBatch = getRemote("SlimeSpawnedBatch", 10)
    if not spawned or not spawnedBatch then
        notify("Slime spawn remotes were not found.")
        return
    end

    Marker:SetAttribute("InstantSpawnCollector", true)
    Connections.InstantSlimeSpawned = spawned.OnClientEvent:Connect(function(id, spawnCFrame)
        Extra.queueSpawnId(id, spawnCFrame)
    end)
    Connections.InstantSlimeSpawnedBatch = spawnedBatch.OnClientEvent:Connect(function(payloads)
        if typeof(payloads) ~= "table" then
            return
        end

        for _, payload in pairs(payloads) do
            if typeof(payload) == "table" then
                Extra.queueSpawnId(payload.id, payload.cf)
            end
        end
    end)

    Tasks.InstantSpawnCollector = task.spawn(function()
        while Toggles.ToggleHugeCollector and Toggles.ToggleHugeCollector.Value
            and Toggles.ToggleInstantSpawnCollector and Toggles.ToggleInstantSpawnCollector.Value do
            Extra.flushSpawnIds()
            task.wait(getTickDelay())
        end
    end)
end

function Extra.getSlimeCandidates(root, includeAll)
    local slimes = getSlimesFolder()
    local now = os.clock()
    local radius = getRadius()
    local retryDelay = getRetryDelay()
    local collectAll = Toggles.ToggleCollectAll and Toggles.ToggleCollectAll.Value
    local candidates = {}
    if not slimes or not root then
        return candidates
    end

    for _, slime in ipairs(slimes:GetChildren()) do
        local id = getSlimeId(slime)
        if id and (not LastSentAt[id] or now - LastSentAt[id] >= retryDelay) then
            local position = getSlimePosition(slime)
            if position then
                local distance = (position - root.Position).Magnitude
                if includeAll or collectAll or distance <= radius then
                    table.insert(candidates, {
                        Id = id,
                        Distance = distance,
                        Position = position,
                    })
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        return a.Distance < b.Distance
    end)

    return candidates
end

function Extra.teleportToSlimeCandidate(candidate)
    local position = candidate and candidate.Position
    local root = getRoot()
    if typeof(position) ~= "Vector3" or not root then
        return false
    end

    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
    Marker:SetAttribute("SlimeLastTeleportAt", Workspace:GetServerTimeNow())
    return true
end

local function collectNearbyOnce(teleportFirst)
    local root = getRoot()
    if not root then
        return 0
    end

    local candidates = Extra.getSlimeCandidates(root, teleportFirst == true)
    if teleportFirst == true and candidates[1] and Extra.teleportToSlimeCandidate(candidates[1]) then
        task.wait(0.2)
        root = getRoot()
        candidates = Extra.getSlimeCandidates(root, false)
    end

    local now = os.clock()
    local batchSize = getBatchSize()
    local ids = {}
    for index = 1, math.min(batchSize, #candidates) do
        local id = candidates[index].Id
        LastSentAt[id] = now
        ids[#ids + 1] = id
    end

    if collectIds(ids) then
        return #ids
    end

    return 0
end

local function fireEmpoweredBoostStack(count, delaySeconds)
    local remote = getActivateEmpoweredBoostRemote()
    if not remote then
        notify("ActivateEmpoweredBoost remote was not found.")
        return 0
    end

    count = math.max(1, math.floor(tonumber(count) or 10))
    delaySeconds = math.max(0, tonumber(delaySeconds) or 0.08)

    for _ = 1, count do
        remote:FireServer()
        if delaySeconds > 0 then
            task.wait(delaySeconds)
        end
    end

    return count
end

local function maxEmpoweredBoost()
    return fireEmpoweredBoostStack(10, 0.1)
end

local function getPlinkoMachine()
    local zones = Workspace:FindFirstChild("Zones", true)
    local lvl10 = zones and zones:FindFirstChild("Lvl10")
    local machine = lvl10 and lvl10:FindFirstChild("PlinkoBallMachine")
    return machine or Workspace:FindFirstChild("PlinkoBallMachine", true)
end

local function isReadyLabel(label)
    return label ~= nil and tostring(label.Text):upper():match("^%s*READY%s*$") ~= nil
end

local function findPlinko4xEndParts()
    local machine = getPlinkoMachine()
    if not machine then
        return {}
    end

    local labels = {}
    for _, descendant in ipairs(machine:GetDescendants()) do
        if descendant:IsA("TextLabel") and tostring(descendant.Text):upper():find("X4", 1, true) then
            local surfaceGui = descendant.Parent
            local adornee = surfaceGui and surfaceGui.Adornee
            local parentPart = surfaceGui and surfaceGui.Parent
            local part = if adornee and adornee:IsA("BasePart") then adornee elseif parentPart and parentPart:IsA("BasePart") then parentPart else nil
            if part then
                labels[#labels + 1] = part.Position
            end
        end
    end

    local endParts = {}
    for _, descendant in ipairs(machine:GetDescendants()) do
        if descendant.Name == "EndPart" and descendant:IsA("BasePart") then
            endParts[#endParts + 1] = descendant
        end
    end

    local chosen = {}
    local used = {}
    for _, labelPosition in ipairs(labels) do
        local bestPart = nil
        local bestDistance = math.huge

        for _, endPart in ipairs(endParts) do
            if not used[endPart] then
                local distance = (endPart.Position - labelPosition).Magnitude
                if distance < bestDistance then
                    bestPart = endPart
                    bestDistance = distance
                end
            end
        end

        if bestPart then
            used[bestPart] = true
            chosen[#chosen + 1] = bestPart
        end
    end

    return chosen
end

local function firePlinko4x()
    local remote = getActivatePlinkoBallRemote()
    if not remote then
        notify("ActivatePlinkoBall remote was not found.")
        return 0
    end

    local parts = findPlinko4xEndParts()
    if #parts == 0 then
        notify("No Plinko X4 end part found.")
        return 0
    end

    remote:FireServer()
    task.wait(0.1)
    remote:FireServer(parts[1])
    Marker:SetAttribute("PlinkoLastUsedAt", Workspace:GetServerTimeNow())
    return 1
end

local function fireCrateBoost(kind, count, delaySeconds)
    local remote = getCrateCollectedRemote()
    if not remote then
        notify("CrateCollected remote was not found.")
        return 0
    end

    kind = kind or "crate"
    count = math.max(1, math.floor(tonumber(count) or 1))
    delaySeconds = math.max(0, tonumber(delaySeconds) or 0.15)

    for _ = 1, count do
        remote:FireServer(kind)
        if delaySeconds > 0 then
            task.wait(delaySeconds)
        end
    end

    return count
end

local function getFallingStarRoots()
    local roots = {}
    local runtime = Workspace:FindFirstChild("Runtime")
    if runtime then
        roots[#roots + 1] = runtime
    end

    local namedRoots = { "FallingStars", "StardustStars", "Collectibles" }
    for _, name in ipairs(namedRoots) do
        local root = Workspace:FindFirstChild(name)
        if root then
            roots[#roots + 1] = root
        end
    end

    return roots
end

local function isFallingStarPart(part)
    if not (part and part:IsA("BasePart")) then
        return false
    end

    local fullName = part:GetFullName()
    local blockedNames = { "SpawnPoints", "Audio", "Leaderboard", "World.Map" }
    for _, blocked in ipairs(blockedNames) do
        if fullName:find(blocked, 1, true) then
            return false
        end
    end

    local current = part
    while current and current ~= Workspace do
        local compactName = tostring(current.Name):lower():gsub("%s+", "")
        if compactName:find("fallingstar", 1, true) or compactName:find("starduststar", 1, true) then
            return true
        end
        current = current.Parent
    end

    return false
end

local function findFallingStarParts()
    local found = {}
    local used = {}

    for _, root in ipairs(getFallingStarRoots()) do
        for _, descendant in ipairs(root:GetDescendants()) do
            if isFallingStarPart(descendant) and not used[descendant] then
                used[descendant] = true
                found[#found + 1] = descendant
            end
        end
    end

    return found
end

local function payloadToPosition(value, depth)
    depth = depth or 0
    if depth > 3 then
        return nil
    end

    local valueType = typeof(value)
    if valueType == "Vector3" then
        return value
    end
    if valueType == "CFrame" then
        return value.Position
    end
    if valueType == "Instance" then
        if value:IsA("BasePart") then
            return value.Position
        end
        if value:IsA("Model") then
            return value:GetPivot().Position
        end
        return nil
    end
    if valueType ~= "table" then
        return nil
    end

    local preferredKeys = {
        "position",
        "Position",
        "targetPosition",
        "TargetPosition",
        "landingPosition",
        "LandingPosition",
        "hitPosition",
        "HitPosition",
        "pos",
        "cframe",
        "CFrame",
    }

    for _, key in ipairs(preferredKeys) do
        local found = payloadToPosition(value[key], depth + 1)
        if found then
            return found
        end
    end

    for _, nested in pairs(value) do
        local found = payloadToPosition(nested, depth + 1)
        if found then
            return found
        end
    end

    return nil
end

local function collectFallingStarPart(part)
    if Extra.bossHasMovementPriority and Extra.bossHasMovementPriority() then
        return false
    end

    local root = getRoot()
    if not (root and part and part.Parent) then
        return false
    end

    local holdSeconds = 0.25
    setFallingStarMovementTarget(part.Position, holdSeconds + 0.15)
    root.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
    task.wait(holdSeconds)

    if typeof(firetouchinterest) == "function" then
        pcall(firetouchinterest, root, part, 0)
        task.wait(0.05)
        pcall(firetouchinterest, root, part, 1)
    end

    return true
end

local function collectFallingStarPosition(position, holdSeconds)
    if Extra.bossHasMovementPriority and Extra.bossHasMovementPriority() then
        return false
    end

    local root = getRoot()
    if not (root and typeof(position) == "Vector3") then
        return false
    end

    holdSeconds = math.max(0.4, tonumber(holdSeconds) or 0.4)
    setFallingStarMovementTarget(position, holdSeconds)
    root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
    task.wait(math.min(0.25, holdSeconds))

    return true
end

local function collectFallingStars(position)
    if Extra.bossHasMovementPriority and Extra.bossHasMovementPriority() then
        FallingStarMovePosition = nil
        FallingStarMoveUntil = 0
        Marker:SetAttribute("FallingStarLastCollectCount", 0)
        Marker:SetAttribute("FallingStarSkippedForBoss", Workspace:GetServerTimeNow())
        return 0
    end

    local maxStars = 8
    local collected = 0

    if position and collectFallingStarPosition(position, 3) then
        Marker:SetAttribute("FallingStarLastCollectCount", 1)
        Marker:SetAttribute("FallingStarLastCollectAt", Workspace:GetServerTimeNow())
        return 1
    end

    if FallingStarMovePosition and os.clock() <= FallingStarMoveUntil then
        return 0
    end

    for _, part in ipairs(findFallingStarParts()) do
        if collected >= maxStars then
            break
        end
        if collectFallingStarPart(part) then
            collected += 1
        end
    end

    Marker:SetAttribute("FallingStarLastCollectCount", collected)
    Marker:SetAttribute("FallingStarLastCollectAt", Workspace:GetServerTimeNow())
    return collected
end

local function getStardustCooldownLabel()
    local field = Workspace:FindFirstChild("StardustMachineField", true)
    local mainPart = field and field:FindFirstChild("mainpart")
    local cooldownGui = mainPart and mainPart:FindFirstChild("CooldownGui")
    local cooldown = cooldownGui and cooldownGui:FindFirstChild("Cooldown")
    return cooldown and cooldown:IsA("TextLabel") and cooldown or nil
end

function Extra.getStardustCooldownRemaining()
    local profile = getProfileData()
    if typeof(profile) ~= "table" then
        Marker:SetAttribute("StardustMachineSafeReady", "no-profile")
        return nil
    end

    if profile.stardustMachineFixed ~= true then
        Marker:SetAttribute("StardustMachineSafeReady", "not-fixed")
        return nil
    end

    local upgrades = profile.upgrades
    local cooldownUpgrade = 0
    if typeof(upgrades) == "table" then
        cooldownUpgrade = tonumber(upgrades.stardustMachineCooldown) or 0
    end

    local lastUsed = tonumber(profile.stardustMachineLastUsed)
    if not lastUsed then
        Marker:SetAttribute("StardustMachineSafeReady", "no-last-used")
        return nil
    end

    local cooldown = math.max(
        0,
        28800 - cooldownUpgrade * 3600
    )
    local remaining = math.max(0, lastUsed + cooldown - os.time())
    Marker:SetAttribute("StardustMachineCooldownRemaining", remaining)
    Marker:SetAttribute("StardustMachineSafeReady", remaining <= 0 and "ready" or "cooldown")
    return remaining
end

local function isStardustMachineReady()
    local label = getStardustCooldownLabel()
    if not label then
        Extra.StardustReadyPrinted = false
        Marker:SetAttribute("StardustMachineSafeReady", "no-gui-label")
        Marker:SetAttribute("StardustMachineGuiText", "")
        return false
    end

    local guiText = tostring(label.Text)
    Marker:SetAttribute("StardustMachineGuiText", guiText)
    if not guiText:upper():match("^%s*READY!?%s*$") then
        Extra.StardustReadyPrinted = false
        Marker:SetAttribute("StardustMachineSafeReady", "gui-cooldown")
        return false
    end

    local gui = label:FindFirstAncestorWhichIsA("BillboardGui") or label:FindFirstAncestorWhichIsA("SurfaceGui")
    if gui and not gui.Enabled then
        Extra.StardustReadyPrinted = false
        Marker:SetAttribute("StardustMachineSafeReady", "gui-disabled")
        return false
    end

    local remaining = Extra.getStardustCooldownRemaining()
    if remaining == nil or remaining > 0 then
        Extra.StardustReadyPrinted = false
        return false
    end

    if not Extra.StardustReadyPrinted then
        Extra.StardustReadyPrinted = true
        print("[slimeinc] Stardust machine GUI is READY; auto fire enabled.")
    end

    return true
end

function Extra.getStardustRequestThrottleRemaining()
    local lastRequest = tonumber(Marker:GetAttribute("StardustMachineLastRequestAt")
        or Marker:GetAttribute("StardustMachineLastRequest")) or 0
    Marker:SetAttribute("StardustMachineRetryDelay", Extra.StardustMachineRequestCooldown)
    local remaining = Extra.StardustMachineRequestCooldown - (Workspace:GetServerTimeNow() - lastRequest)
    return math.max(0, remaining)
end

local function requestFallingStarBoost()
    if not isStardustMachineReady() then
        return false
    end

    local throttleRemaining = Extra.getStardustRequestThrottleRemaining()
    Marker:SetAttribute("StardustMachineClientThrottleRemaining", math.ceil(throttleRemaining))
    if throttleRemaining > 0 then
        return false
    end

    if not canFireReadyAction("StardustMachine", Extra.StardustMachineRequestCooldown) then
        return false
    end

    local remote = getActivateStardustMachineRemote()
    if not remote then
        notify("ActivateStardustMachine remote was not found.")
        return false
    end

    remote:FireServer()
    local requestTime = Workspace:GetServerTimeNow()
    Marker:SetAttribute("StardustMachineLastRequest", requestTime)
    Marker:SetAttribute("StardustMachineLastRequestAt", requestTime)
    Marker:SetAttribute("StardustMachineClientThrottleRemaining", Extra.StardustMachineRequestCooldown)
    return true
end

local function startFallingStarListeners()
    disconnect("StardustStarFalling")
    disconnect("FallingStarAwarded")

    local fallingRemote = getStardustStarFallingRemote()
    if fallingRemote then
        Connections.StardustStarFalling = fallingRemote.OnClientEvent:Connect(function(...)
            Marker:SetAttribute("FallingStarLastEventAt", Workspace:GetServerTimeNow())
            if not (Toggles.ToggleAutoCollectFallingStars and Toggles.ToggleAutoCollectFallingStars.Value) then
                return
            end

            local args = { ... }
            local position = payloadToPosition(args[1])
            if not position then
                for _, value in ipairs(args) do
                    position = payloadToPosition(value)
                    if position then
                        break
                    end
                end
            end

            if position then
                Marker:SetAttribute("FallingStarDropPosition", tostring(position))
            end

            task.delay(7.5, function()
                if Toggles.ToggleAutoCollectFallingStars and Toggles.ToggleAutoCollectFallingStars.Value then
                    collectFallingStars(position)
                end
            end)
        end)
    end

    local awardedRemote = getFallingStarAwardedRemote()
    if awardedRemote then
        Connections.FallingStarAwarded = awardedRemote.OnClientEvent:Connect(function(...)
            Marker:SetAttribute("FallingStarLastAwardAt", Workspace:GetServerTimeNow())
            Marker:SetAttribute("FallingStarLastAwardArgs", select("#", ...))
        end)
    end
end

local function stopFallingStarAutomation()
    stopTask("FallingStars")
    disconnect("StardustStarFalling")
    disconnect("FallingStarAwarded")
end

local function startFallingStarAutomation()
    stopTask("FallingStars")
    startFallingStarListeners()

    Tasks.FallingStars = task.spawn(function()
        while Marker:GetAttribute("Session") == Session
            and ((Toggles.ToggleAutoFallingStars and Toggles.ToggleAutoFallingStars.Value)
            or (Toggles.ToggleAutoCollectFallingStars and Toggles.ToggleAutoCollectFallingStars.Value)) do
            if Toggles.ToggleAutoFallingStars and Toggles.ToggleAutoFallingStars.Value then
                requestFallingStarBoost()
            end

            if Toggles.ToggleAutoCollectFallingStars and Toggles.ToggleAutoCollectFallingStars.Value then
                collectFallingStars()
            end

            task.wait(0.75)
        end
    end)
end

local function refreshFallingStarAutomation()
    if (Toggles.ToggleAutoFallingStars and Toggles.ToggleAutoFallingStars.Value)
        or (Toggles.ToggleAutoCollectFallingStars and Toggles.ToggleAutoCollectFallingStars.Value) then
        startFallingStarAutomation()
    else
        stopFallingStarAutomation()
    end
end

do
local BossAutomationConfig = {
    unlockPrestige = 1,
    spawnCostAmount = 2500,
    earlyStartCostAmount = 8000,
    paidStartCountdownSeconds = 60,
    activeBossName = "ActiveBoss",
    bossZonePath = { "World", "BossRelated", "BossZone" },
    bossSpawnPath = { "World", "BossRelated", "BossSpawn" },
    bossTeleportEnterPath = { "World", "BossRelated", "BossTeleport", "Enter" },
    bossTeleportGoalPath = { "World", "BossRelated", "BossTeleport", "Goal" },
}

Extra.BossCardValues = { "---", "Undead Echo", "Skelly Hunger", "Bone Focus", "Raid Spark", "Second Soul" }
Extra.BossCardLabelToId = {
    ["Undead Echo"] = "undeadEcho",
    ["Skelly Hunger"] = "skellyHunger",
    ["Bone Focus"] = "boneFocus",
    ["Raid Spark"] = "raidSpark",
    ["Second Soul"] = "secondSoul",
}
Extra.BossCardIdToLabel = {
    undeadEcho = "Undead Echo",
    skellyHunger = "Skelly Hunger",
    boneFocus = "Bone Focus",
    raidSpark = "Raid Spark",
    secondSoul = "Second Soul",
}
Extra.BossAttackVisualPrefixes = {
    "BossShockwave",
    "BossThunderWarning",
    "BossThunderJumpPrompt",
    "BossGroundBiteWarning",
    "BossBladeStormCut",
    "BossSpinBlade",
    "BossGroundBiteSlime_",
    "BossSplitDrop_",
    "BossParryGoo",
    "BossStarBlazing",
    "BossShocker",
    "BossChaosSaber",
    "BossChaosBuster",
    "LocalBossSpawnPreview",
}

local function getBossRemote(name)
    return getRemote(name, 5)
end

local function bossFindChildLoose(parent, name)
    if not parent then
        return nil
    end

    local found = parent:FindFirstChild(name)
    if found then
        return found
    end

    local wanted = tostring(name):lower()
    for _, child in ipairs(parent:GetChildren()) do
        if tostring(child.Name):lower() == wanted then
            return child
        end
    end

    return nil
end

local function bossFindDescendantLoose(root, name)
    if not root then
        return nil
    end

    local found = root:FindFirstChild(name, true)
    if found then
        return found
    end

    local wanted = tostring(name):lower()
    for _, descendant in ipairs(root:GetDescendants()) do
        if tostring(descendant.Name):lower() == wanted then
            return descendant
        end
    end

    return nil
end

local function bossFindPath(root, path)
    local current = root
    for _, name in ipairs(path) do
        current = bossFindChildLoose(current, name)
        if not current then
            return nil
        end
    end

    return current
end

local function bossResolvePath(path, fallbackName)
    local found = bossFindPath(Workspace, path)
    if found then
        return found
    end

    local bossRelated = bossFindDescendantLoose(Workspace, "BossRelated")
    if bossRelated and fallbackName then
        found = bossFindDescendantLoose(bossRelated, fallbackName)
        if found then
            return found
        end
    end

    if fallbackName then
        return bossFindDescendantLoose(Workspace, fallbackName)
    end

    return nil
end

local function bossInstanceCFrame(instance)
    if typeof(instance) ~= "Instance" then
        return nil
    end

    if instance:IsA("Attachment") then
        return instance.WorldCFrame
    end

    return Extra.instanceCFrame(instance)
end

local function bossOffsetCFrame(cframe, yOffset)
    if typeof(cframe) ~= "CFrame" then
        return nil
    end

    return cframe + Vector3.new(0, yOffset or 0, 0)
end

function Extra.bossAutomationEnabled()
    return (Toggles.ToggleAutoBossStart and Toggles.ToggleAutoBossStart.Value)
        or (Toggles.ToggleAutoBossFight and Toggles.ToggleAutoBossFight.Value)
        or (Toggles.ToggleAutoBossPayOpen and Toggles.ToggleAutoBossPayOpen.Value)
        or (Toggles.ToggleAutoBossBuyCards and Toggles.ToggleAutoBossBuyCards.Value)
        or (Toggles.ToggleAutoBossCloseVictory and Toggles.ToggleAutoBossCloseVictory.Value)
end

function Extra.bossFightEnabled()
    return Toggles.ToggleAutoBossFight and Toggles.ToggleAutoBossFight.Value or false
end

function Extra.bossPayOpenEnabled()
    return Toggles.ToggleAutoBossPayOpen and Toggles.ToggleAutoBossPayOpen.Value or false
end

function Extra.bossCardPickEnabled()
    return Toggles.ToggleAutoBossBuyCards and Toggles.ToggleAutoBossBuyCards.Value or false
end

function Extra.bossAttackVfxRemovalEnabled()
    return Toggles.ToggleAutoBossRemoveAttackVfx and Toggles.ToggleAutoBossRemoveAttackVfx.Value or false
end

function Extra.bossMoveEnabled()
    return Toggles.ToggleAutoBossMove and Toggles.ToggleAutoBossMove.Value
        and ((Toggles.ToggleAutoBossStart and Toggles.ToggleAutoBossStart.Value)
            or Extra.bossFightEnabled()
            or Extra.bossPayOpenEnabled()
            or (Toggles.ToggleAutoUndeadBoss and Toggles.ToggleAutoUndeadBoss.Value))
end

function Extra.bossHasMovementPriority()
    if not (Toggles.ToggleAutoBossMove and Toggles.ToggleAutoBossMove.Value) then
        return false
    end

    local state = Extra.BossState or {}
    if state.status == "active" and Extra.bossFightEnabled() then
        return true
    end

    if state.status == "spawning" then
        return (Toggles.ToggleAutoBossStart and Toggles.ToggleAutoBossStart.Value)
            or Extra.bossPayOpenEnabled()
            or Extra.bossFightEnabled()
    end

    return false
end

function Extra.getBossPriorityMovementTarget()
    if not Extra.bossHasMovementPriority() then
        return nil, nil
    end

    local state = Extra.BossState or {}
    local target = state.status == "active" and Extra.getBossFightCFrame() or (Extra.getBossFightCFrame() or Extra.getBossStartCFrame())
    if target then
        Extra.BossMoveCFrame = target
        Extra.BossMoveUntil = os.clock() + 1.25
        Extra.BossMoveReason = state.status == "spawning" and "Boss Entry" or "Boss Arena"
        return target, Extra.BossMoveReason
    end

    return nil, nil
end

function Extra.bossParryEnabled()
    return Extra.bossFightEnabled()
        and Toggles.ToggleAutoBossParry
        and Toggles.ToggleAutoBossParry.Value
end

function Extra.bossSplitPickupEnabled()
    return Extra.bossFightEnabled()
        and Toggles.ToggleAutoBossSplitPickups
        and Toggles.ToggleAutoBossSplitPickups.Value
end

function Extra.undeadEnabled()
    return Toggles.ToggleAutoUndeadBoss and Toggles.ToggleAutoUndeadBoss.Value or false
end

function Extra.undeadMoveEnabled()
    return Extra.undeadEnabled()
        and (not Toggles.ToggleAutoUndeadMove or Toggles.ToggleAutoUndeadMove.Value)
        and Toggles.ToggleAutoBossMove and Toggles.ToggleAutoBossMove.Value
end

function Extra.setBossStatus(message)
    local text = tostring(message)
    Marker:SetAttribute("BossAutomationStatus", text)
    if Extra.BossStatusLabel then
        pcall(function()
            Extra.BossStatusLabel:SetText(text)
        end)
    end
end

function Extra.setUndeadStatus(message)
    local text = tostring(message)
    Marker:SetAttribute("UndeadAutomationStatus", text)
    if Extra.UndeadStatusLabel then
        pcall(function()
            Extra.UndeadStatusLabel:SetText(text)
        end)
    end
end

function Extra.formatBossCoins(value)
    local coins = tonumber(value)
    if not coins then
        return "unknown"
    end

    coins = math.floor(coins)
    local sign = ""
    if coins < 0 then
        sign = "-"
        coins = -coins
    end

    local text = tostring(coins)
    local chunks = {}
    while #text > 3 do
        table.insert(chunks, 1, string.sub(text, -3))
        text = string.sub(text, 1, #text - 3)
    end
    table.insert(chunks, 1, text)
    return sign .. table.concat(chunks, ",")
end

function Extra.setBossCoinCount(value, source)
    local coins = tonumber(value)
    if coins then
        coins = math.max(0, math.floor(coins))
        Extra.BossKillCoins = coins
        Marker:SetAttribute("BossKillCoins", coins)
        if source then
            Marker:SetAttribute("BossKillCoinsSource", tostring(source))
        end
    end

    if Extra.BossCoinsLabel then
        pcall(function()
            Extra.BossCoinsLabel:SetText("Boss Coins: " .. Extra.formatBossCoins(Extra.BossKillCoins))
        end)
    end

    return Extra.BossKillCoins
end

function Extra.refreshBossCoinCount()
    local profile = getProfileData()
    if profile and tonumber(profile.bossKillCoins) then
        return Extra.setBossCoinCount(profile.bossKillCoins, "profile")
    end

    return Extra.setBossCoinCount(Extra.BossKillCoins)
end

function Extra.isBossAttackVisual(instance)
    if typeof(instance) ~= "Instance" then
        return false
    end

    local name = tostring(instance.Name)
    for _, prefix in ipairs(Extra.BossAttackVisualPrefixes) do
        if string.sub(name, 1, #prefix) == prefix then
            return true
        end
    end

    if instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam") then
        return instance:FindFirstAncestor("ClientBossVfx") ~= nil
    end

    return false
end

function Extra.removeBossAttackVfx()
    local folder = Workspace:FindFirstChild("ClientBossVfx")
    if not folder then
        return 0
    end

    local removed = 0
    for _, descendant in ipairs(folder:GetDescendants()) do
        if Extra.isBossAttackVisual(descendant) then
            removed += 1
            pcall(function()
                descendant:Destroy()
            end)
        end
    end

    if removed > 0 then
        Marker:SetAttribute("BossAttackVfxRemoved", removed)
        Marker:SetAttribute("BossAttackVfxRemovedAt", Workspace:GetServerTimeNow())
    end
    return removed
end

function Extra.startBossAttackVfxCleaner()
    stopTask("BossAttackVfx")
    Extra.removeBossAttackVfx()

    Tasks.BossAttackVfx = task.spawn(function()
        while Marker:GetAttribute("Session") == Session and Extra.bossAttackVfxRemovalEnabled() do
            Extra.removeBossAttackVfx()
            task.wait(0.2)
        end
    end)
end

function Extra.stopBossAttackVfxCleaner()
    stopTask("BossAttackVfx")
end

function Extra.refreshBossAttackVfxCleaner()
    if Extra.bossAttackVfxRemovalEnabled() then
        Extra.startBossAttackVfxCleaner()
    else
        Extra.stopBossAttackVfxCleaner()
    end
end

function Extra.describeBossState()
    local state = Extra.BossState or {}
    local status = tostring(state.status or "unknown")
    local health = tonumber(state.health) or 0
    local maxHealth = tonumber(state.maxHealth) or 0

    if status == "active" and maxHealth > 0 then
        return string.format("Boss active: %d/%d HP.", math.floor(health), math.floor(maxHealth))
    end

    if status == "spawning" then
        local entryClosesAt = tonumber(state.entryClosesAt)
        if entryClosesAt then
            local remaining = math.max(0, math.ceil(entryClosesAt - Workspace:GetServerTimeNow()))
            return "Boss portal/spawn active. Entry window: " .. tostring(remaining) .. "s."
        end
        return "Boss is spawning."
    end

    if status == "inactive" then
        return "Boss inactive."
    end

    return "Boss state: " .. status .. "."
end

function Extra.applyBossState(payload)
    if typeof(payload) ~= "table" then
        return false
    end

    local status = payload.status
    local health = payload.health
    local maxHealth = payload.maxHealth
    if typeof(status) ~= "string" or typeof(health) ~= "number" or typeof(maxHealth) ~= "number" then
        return false
    end

    Extra.BossState = {
        status = status,
        health = health,
        maxHealth = maxHealth,
        spawnStartedAt = typeof(payload.spawnStartedAt) == "number" and payload.spawnStartedAt or nil,
        spawnedByUserId = typeof(payload.spawnedByUserId) == "number" and payload.spawnedByUserId or nil,
        spawnCFrame = typeof(payload.spawnCFrame) == "CFrame" and payload.spawnCFrame or nil,
        entryClosesAt = typeof(payload.entryClosesAt) == "number" and payload.entryClosesAt or nil,
    }

    Marker:SetAttribute("BossStatus", status)
    Marker:SetAttribute("BossHealth", health)
    Marker:SetAttribute("BossMaxHealth", maxHealth)
    Marker:SetAttribute("BossEntryClosesAt", Extra.BossState.entryClosesAt or 0)
    Extra.setBossStatus(Extra.describeBossState())
    return true
end

function Extra.requestBossState(force)
    local now = os.clock()
    if not force and now - (Extra.BossLastStateRequestAt or 0) < 5 then
        return false
    end

    local remote = getBossRemote("RequestBossState")
    if not remote then
        Extra.setBossStatus("RequestBossState remote was not found.")
        return false
    end

    Extra.BossLastStateRequestAt = now
    Marker:SetAttribute("BossLastStateRequest", Workspace:GetServerTimeNow())
    remote:FireServer()
    return true
end

function Extra.getBossRelated()
    return bossResolvePath({ "World", "BossRelated" }, "BossRelated")
end

function Extra.getActiveBossInstance()
    local bossRelated = Extra.getBossRelated()
    local activeName = BossAutomationConfig.activeBossName
    if bossRelated then
        return bossFindChildLoose(bossRelated, activeName) or bossFindDescendantLoose(bossRelated, activeName)
    end

    return bossFindDescendantLoose(Workspace, activeName)
end

function Extra.getBossStartCFrame()
    local enter = bossResolvePath(BossAutomationConfig.bossTeleportEnterPath, "Enter")
    local enterCFrame = bossInstanceCFrame(enter)
    if enterCFrame then
        return bossOffsetCFrame(enterCFrame, 3)
    end

    local spawn = bossResolvePath(BossAutomationConfig.bossSpawnPath, "BossSpawn")
    local spawnCFrame = bossInstanceCFrame(spawn)
    if spawnCFrame then
        return bossOffsetCFrame(spawnCFrame, 3)
    end

    local state = Extra.BossState or {}
    if typeof(state.spawnCFrame) == "CFrame" then
        return bossOffsetCFrame(state.spawnCFrame, 3)
    end

    return nil
end

function Extra.getBossFightCFrame()
    local activeBoss = Extra.getActiveBossInstance()
    local activeCFrame = bossInstanceCFrame(activeBoss)
    local stayAbove = not Toggles.ToggleAutoBossStayAbove or Toggles.ToggleAutoBossStayAbove.Value
    if stayAbove and activeCFrame then
        local hoverHeight = math.max(8, getNumberOption("AutoBossHoverHeight", 24))
        return bossOffsetCFrame(activeCFrame, hoverHeight)
    end

    local goal = bossResolvePath(BossAutomationConfig.bossTeleportGoalPath, "Goal")
    local goalCFrame = bossInstanceCFrame(goal)
    if goalCFrame then
        return bossOffsetCFrame(goalCFrame, 3)
    end

    local zone = bossResolvePath(BossAutomationConfig.bossZonePath, "BossZone")
    local zoneCFrame = bossInstanceCFrame(zone)
    if zoneCFrame then
        return bossOffsetCFrame(zoneCFrame, 3)
    end

    if activeCFrame then
        return bossOffsetCFrame(activeCFrame, 8)
    end

    return Extra.getBossStartCFrame()
end

function Extra.setBossMoveTarget(cframe, holdSeconds, reason)
    if typeof(cframe) ~= "CFrame" then
        return false
    end

    Extra.BossMoveCFrame = cframe
    Extra.BossMoveUntil = os.clock() + math.max(0.25, tonumber(holdSeconds) or 0.75)
    Extra.BossMoveReason = reason or "Boss"

    local root = getRoot()
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = cframe
    end

    return true
end

function Extra.updateBossMovementTarget(reason, holdSeconds)
    if not Extra.bossMoveEnabled() then
        return false
    end

    local state = Extra.BossState or {}
    local target
    if state.status == "active" or state.status == "spawning" then
        target = Extra.getBossFightCFrame()
    else
        target = Extra.getBossStartCFrame()
    end

    return Extra.setBossMoveTarget(target, holdSeconds or 1.25, reason or "Boss")
end

function Extra.fireBossStart(force)
    local state = Extra.BossState or {}
    if state.status == "active" then
        Extra.setBossStatus("Boss is already active.")
        return false
    end

    local now = os.clock()
    local retrySeconds = math.max(10, getNumberOption("AutoBossStartRetrySeconds", 60))
    if not force and now - (Extra.BossLastStartRequestAt or 0) < retrySeconds then
        return false
    end

    local profile = getProfileData()
    local prestige = profile and tonumber(profile.prestige) or nil
    if prestige and prestige < BossAutomationConfig.unlockPrestige then
        Extra.setBossStatus("Prestige 1 required for boss.")
        return false
    end

    local power = profile and tonumber(profile.power) or nil
    local earlyRemote = getBossRemote("BossEarlyStartRequested")
    local spawnRemote = getBossRemote("BossSpawnRequested")
    local remote = nil
    local remoteName = nil
    local wantEarlyStart = force or Extra.bossPayOpenEnabled()
    local wantSpawnStart = force
        or (Toggles.ToggleAutoBossStart and Toggles.ToggleAutoBossStart.Value)
        or Extra.bossPayOpenEnabled()

    if state.status == "spawning" then
        Extra.updateBossMovementTarget("Boss Entry", 2)

        if not wantEarlyStart then
            Extra.setBossStatus(Extra.describeBossState())
            return false
        end

        local entryClosesAt = tonumber(state.entryClosesAt)
        local remaining = entryClosesAt and math.max(0, math.ceil(entryClosesAt - Workspace:GetServerTimeNow())) or nil
        if remaining and remaining <= BossAutomationConfig.paidStartCountdownSeconds then
            Extra.setBossStatus("Boss already starting soon (" .. tostring(remaining) .. "s).")
            return false
        end
        if not earlyRemote then
            Extra.setBossStatus("BossEarlyStartRequested remote was not found.")
            return false
        end
        if power and power < BossAutomationConfig.earlyStartCostAmount then
            Extra.setBossStatus("Need " .. tostring(BossAutomationConfig.earlyStartCostAmount) .. " power for early boss start.")
            return false
        end

        if Extra.bossMoveEnabled() then
            task.wait(0.12)
        end

        Extra.BossLastStartRequestAt = now
        Marker:SetAttribute("BossLastStartRemote", "BossEarlyStartRequested")
        Marker:SetAttribute("BossLastStartRequest", Workspace:GetServerTimeNow())
        earlyRemote:FireServer()
        Extra.setBossStatus("Boss early start fired during entry window.")
        return true
    end

    if wantEarlyStart and earlyRemote and (not power or power >= BossAutomationConfig.earlyStartCostAmount) then
        remote = earlyRemote
        remoteName = "BossEarlyStartRequested"
    elseif wantSpawnStart and spawnRemote and (not power or power >= BossAutomationConfig.spawnCostAmount) then
        remote = spawnRemote
        remoteName = "BossSpawnRequested"
    end

    if not remote then
        if wantEarlyStart and earlyRemote and power and power < BossAutomationConfig.earlyStartCostAmount then
            Extra.setBossStatus("Need " .. tostring(BossAutomationConfig.earlyStartCostAmount) .. " power for early boss start.")
        elseif wantSpawnStart and spawnRemote and power and power < BossAutomationConfig.spawnCostAmount then
            Extra.setBossStatus("Need " .. tostring(BossAutomationConfig.spawnCostAmount) .. " power for boss spawn.")
        else
            Extra.setBossStatus("Boss start remote was not found.")
        end
        return false
    end

    if Extra.bossMoveEnabled() then
        Extra.updateBossMovementTarget("Boss Start", 1.5)
        task.wait(0.12)
    end

    Extra.BossLastStartRequestAt = now
    Marker:SetAttribute("BossLastStartRemote", remoteName)
    Marker:SetAttribute("BossLastStartRequest", Workspace:GetServerTimeNow())
    remote:FireServer()
    Extra.setBossStatus("Boss start fired with " .. remoteName .. ".")
    return true
end

function Extra.handleBossParrySequence(payload)
    if not Extra.bossParryEnabled() or typeof(payload) ~= "table" then
        return false
    end

    local sequence = tonumber(payload.sequence)
    local prompts = payload.prompts
    if not sequence or typeof(prompts) ~= "table" then
        return false
    end

    local scheduled = 0
    local offsetSeconds = math.clamp(getNumberOption("AutoBossParryOffsetMs", 50) / 1000, 0, 0.2)
    for _, prompt in pairs(prompts) do
        if typeof(prompt) == "table" then
            local promptId = tonumber(prompt.promptId)
            local expiresAt = tonumber(prompt.expiresAt)
            local targetAt = tonumber(prompt.parryStartAt) or tonumber(prompt.activeAt) or tonumber(prompt.startAt)
            if promptId and expiresAt and targetAt and Workspace:GetServerTimeNow() < expiresAt then
                local key = tostring(math.floor(sequence)) .. ":" .. tostring(math.floor(promptId))
                if not Extra.BossParrySent[key] then
                    Extra.BossParrySent[key] = true
                    scheduled += 1
                    task.delay(math.max(0, targetAt - Workspace:GetServerTimeNow() + offsetSeconds), function()
                        if not Extra.bossParryEnabled() then
                            return
                        end
                        if Workspace:GetServerTimeNow() > expiresAt + 0.08 then
                            return
                        end

                        local remote = getBossRemote("BossParryAttempt")
                        if remote then
                            remote:FireServer(math.floor(sequence), math.floor(promptId))
                            Marker:SetAttribute("BossLastParryAttempt", key)
                            Marker:SetAttribute("BossLastParryAttemptAt", Workspace:GetServerTimeNow())
                        end
                    end)
                end
            end
        end
    end

    if scheduled > 0 then
        Extra.setBossStatus("Scheduled " .. tostring(scheduled) .. " boss parry attempt(s).")
    end
    return scheduled > 0
end

function Extra.collectBossSplitPickup(payload)
    if not Extra.bossSplitPickupEnabled() or typeof(payload) ~= "table" then
        return false
    end

    local pickupId = tonumber(payload.pickupId)
    if not pickupId then
        return false
    end

    pickupId = math.floor(pickupId)
    local now = os.clock()
    if now - (Extra.BossSplitPickups[pickupId] or 0) < 0.75 then
        return false
    end

    Extra.BossSplitPickups[pickupId] = now
    local position = payloadToPosition(payload.position or payload)
    if position and Extra.bossMoveEnabled() then
        Extra.setBossMoveTarget(CFrame.new(position + Vector3.new(0, 3, 0)), 1, "Boss Split Pickup")
        task.wait(0.15)
    end

    local remote = getBossRemote("BossSplitPickupCollected")
    if not remote then
        Extra.setBossStatus("BossSplitPickupCollected remote was not found.")
        return false
    end

    remote:FireServer(pickupId)
    Marker:SetAttribute("BossLastSplitPickup", pickupId)
    Marker:SetAttribute("BossLastSplitPickupAt", Workspace:GetServerTimeNow())
    Extra.setBossStatus("Boss split pickup collected: " .. tostring(pickupId) .. ".")
    return true
end

function Extra.selectedBossCardId()
    local option = Options.BossCardPick
    local value = option and option.Value or "---"
    if typeof(value) == "table" then
        for key, selected in pairs(value) do
            if selected == true then
                value = key
                break
            elseif typeof(selected) == "string" then
                value = selected
                break
            end
        end
    end

    value = tostring(value or "---")
    if value == "---" then
        return nil
    end

    return Extra.BossCardLabelToId[value] or value
end

function Extra.bossCardId(card)
    if typeof(card) ~= "table" then
        return nil
    end

    local id = card.id or card.Id or card.key or card.name
    if id == nil then
        return nil
    end

    return tostring(id)
end

function Extra.bossCardLabel(card, id)
    if typeof(card) == "table" then
        return tostring(card.title or card.displayName or card.name or Extra.BossCardIdToLabel[id] or id)
    end

    return tostring(Extra.BossCardIdToLabel[id] or id)
end

function Extra.bossVictoryCards(payload)
    local cards = {}
    if typeof(payload) ~= "table" then
        return cards
    end

    local source = typeof(payload.cards) == "table" and payload.cards or payload
    for _, card in pairs(source) do
        local id = Extra.bossCardId(card)
        if id then
            table.insert(cards, card)
        end
    end
    return cards
end

function Extra.chooseBossVictoryCard(cards)
    if typeof(cards) ~= "table" or #cards <= 0 then
        return nil
    end

    local selectedId = Extra.selectedBossCardId()
    if Toggles.ToggleAutoBossRandomCard and Toggles.ToggleAutoBossRandomCard.Value then
        return cards[math.random(1, #cards)]
    end

    if selectedId then
        for _, card in ipairs(cards) do
            if Extra.bossCardId(card) == selectedId then
                return card
            end
        end
    end

    return cards[1]
end

function Extra.fireBossCardUpgrade(card)
    local id = Extra.bossCardId(card)
    if not id then
        Extra.setBossStatus("Could not read boss card id.")
        return false
    end

    local cost = math.max(1, tonumber(card.cost) or 1)
    local coins = Extra.BossKillCoins
    if coins == nil then
        coins = Extra.refreshBossCoinCount()
    end
    if coins and coins < cost then
        Extra.setBossStatus("Need " .. tostring(cost) .. " boss coin(s) for " .. Extra.bossCardLabel(card, id) .. ".")
        return false
    end

    local remote = getBossRemote("BossUpgradeRequested")
    if not remote then
        Extra.setBossStatus("BossUpgradeRequested remote was not found.")
        return false
    end

    Extra.BossCardPickPending[id] = os.clock()
    Marker:SetAttribute("BossLastCardPick", id)
    Marker:SetAttribute("BossLastCardPickAt", Workspace:GetServerTimeNow())
    remote:FireServer(id)
    if coins then
        Extra.setBossCoinCount(coins - cost, "estimate")
    end
    return true, id, cost
end

function Extra.closeBossVictoryRewards(reason, force)
    local now = os.clock()
    if not force and now - (Extra.BossLastVictoryCloseAt or 0) < 3 then
        return false
    end
    Extra.BossLastVictoryCloseAt = now

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        for _, name in ipairs({ "BossVictoryWarning", "BossVictoryRewards", "BossRewardChestBurst" }) do
            local gui = playerGui:FindFirstChild(name)
            if gui then
                pcall(function()
                    gui:Destroy()
                end)
            end
        end
    end

    local closeRemote = getBossRemote("BossVictoryClosed")
    if closeRemote then
        closeRemote:FireServer()
        Marker:SetAttribute("BossVictoryClosedAt", Workspace:GetServerTimeNow())
        Marker:SetAttribute("BossVictoryClosedReason", tostring(reason or "auto"))
        return true
    end

    Extra.setBossStatus("BossVictoryClosed remote was not found.")
    return false
end

function Extra.startBossCardSpendLoop(payload)
    if not Extra.bossCardPickEnabled() then
        return false
    end
    if typeof(payload) ~= "table" then
        Extra.setBossStatus("Boss victory payload had no card table.")
        return false
    end

    Extra.BossLastVictoryPayload = payload
    if tonumber(payload.bossKillCoins) then
        Extra.setBossCoinCount(payload.bossKillCoins, "victory")
    else
        Extra.refreshBossCoinCount()
    end

    local cards = Extra.bossVictoryCards(payload)
    if #cards <= 0 then
        Extra.setBossStatus("Boss victory had no offered cards.")
        return false
    end

    stopTask("BossCardSpend")
    Tasks.BossCardSpend = task.spawn(function()
        Extra.BossCardSpendActive = true
        local fired = 0
        local unknownCoinReads = 0

        while Marker:GetAttribute("Session") == Session and Extra.bossCardPickEnabled() do
            local activePayload = Extra.BossLastVictoryPayload
            local activeCards = Extra.bossVictoryCards(activePayload)
            local chosen = Extra.chooseBossVictoryCard(activeCards)
            if not chosen then
                Extra.setBossStatus("Boss card spender stopped: no offered cards.")
                break
            end

            local id = Extra.bossCardId(chosen)
            local cost = math.max(1, tonumber(chosen.cost) or 1)
            local coins = Extra.BossKillCoins
            if coins == nil then
                coins = Extra.refreshBossCoinCount()
            end
            if coins and coins < cost then
                Extra.setBossStatus("Boss card spender done. Boss Coins: " .. Extra.formatBossCoins(coins) .. ".")
                break
            end

            local burst = math.max(1, math.floor(getNumberOption("AutoBossCardSpendBurst", 20)))
            if coins then
                burst = math.min(burst, math.max(1, math.floor(coins / cost)))
                unknownCoinReads = 0
            else
                unknownCoinReads += 1
                burst = 1
                if unknownCoinReads > 3 then
                    Extra.setBossStatus("Boss card spender paused: coin count is unknown.")
                    break
                end
            end

            Extra.BossLastCardBuyOk = nil
            for index = 1, burst do
                if not Extra.bossCardPickEnabled() then
                    break
                end

                local ok = Extra.fireBossCardUpgrade(chosen)
                if not ok then
                    break
                end

                fired += 1
                if index % 20 == 0 then
                    task.wait()
                end
            end

            Extra.setBossStatus("Boss card spender fired "
                .. tostring(fired)
                .. " buy(s). Last: "
                .. Extra.bossCardLabel(chosen, id)
                .. ". Boss Coins: "
                .. Extra.formatBossCoins(Extra.BossKillCoins)
                .. ".")

            task.wait(math.clamp(getNumberOption("AutoBossCardSpendDelayMs", 50) / 1000, 0, 2))
            if Extra.BossLastCardBuyOk == false then
                Extra.setBossStatus("Boss card spender stopped after server rejected a buy.")
                break
            end
        end

        Extra.BossCardSpendActive = false
        Tasks.BossCardSpend = nil
        if fired > 0 and Toggles.ToggleAutoBossCloseVictory and Toggles.ToggleAutoBossCloseVictory.Value then
            task.delay(0.75, function()
                Extra.closeBossVictoryRewards("card-spend-complete", false)
            end)
        end
    end)

    Extra.setBossStatus("Boss card spender started. Boss Coins: " .. Extra.formatBossCoins(Extra.BossKillCoins) .. ".")
    return true
end

function Extra.pickBossVictoryCard(payload)
    return Extra.startBossCardSpendLoop(payload)
end

function Extra.handleBossUpgradeResult(ok, payload)
    local id = nil
    local reason = nil
    if typeof(payload) == "table" then
        id = payload.id or payload.cardId or payload.upgradeId
        reason = payload.reason or payload.error or payload.message
        if typeof(payload.bossKillCoins) == "number" then
            Extra.setBossCoinCount(payload.bossKillCoins, "upgrade-result")
        end
        if typeof(payload.bossUpgrades) == "table" and typeof(Extra.BossLastVictoryPayload) == "table" then
            Extra.BossLastVictoryPayload.bossUpgrades = payload.bossUpgrades
        end
    elseif payload ~= nil then
        reason = tostring(payload)
    end

    Extra.BossLastCardBuyOk = ok == true
    if id ~= nil then
        Extra.BossCardPickPending[tostring(id)] = nil
    else
        Extra.BossCardPickPending = {}
    end

    if ok then
        if not Extra.BossCardSpendActive or os.clock() - (Extra.BossCardStatusAt or 0) > 0.5 then
            Extra.BossCardStatusAt = os.clock()
            Extra.setBossStatus("Boss card bought: "
                .. Extra.bossCardLabel(nil, id or "upgrade")
                .. ". Boss Coins: "
                .. Extra.formatBossCoins(Extra.BossKillCoins)
                .. ".")
        end
    else
        Extra.setBossStatus("Boss card buy failed: " .. tostring(reason or "unknown") .. ".")
    end

    if Toggles.ToggleAutoBossCloseVictory and Toggles.ToggleAutoBossCloseVictory.Value and not Extra.BossCardSpendActive then
        task.delay(ok and 0.35 or 0.75, function()
            Extra.closeBossVictoryRewards(ok and "card-result" or "card-failed", false)
        end)
    end
end

function Extra.applyUndeadMiniBossState(payload)
    if typeof(payload) ~= "table" then
        return false
    end

    if payload.active == true then
        local position = payloadToPosition(payload.position or payload)
        local id = payload.id
        if id == nil or not position then
            Extra.setUndeadStatus("Undead mini boss active, missing id/position.")
            return false
        end

        Extra.UndeadMiniBoss = {
            id = id,
            position = position,
            health = tonumber(payload.health) or 0,
            maxHealth = tonumber(payload.maxHealth) or 0,
        }
        Marker:SetAttribute("UndeadMiniBossId", tostring(id))
        Marker:SetAttribute("UndeadMiniBossHealth", Extra.UndeadMiniBoss.health)
        Marker:SetAttribute("UndeadMiniBossMaxHealth", Extra.UndeadMiniBoss.maxHealth)

        if Extra.undeadMoveEnabled() then
            Extra.setBossMoveTarget(CFrame.new(position + Vector3.new(0, 3, 0)), 1.25, "Undead Mini Boss")
        end

        if Extra.UndeadMiniBoss.maxHealth > 0 then
            Extra.setUndeadStatus("Undead mini boss: "
                .. tostring(math.floor(Extra.UndeadMiniBoss.health))
                .. "/"
                .. tostring(math.floor(Extra.UndeadMiniBoss.maxHealth))
                .. " HP.")
        else
            Extra.setUndeadStatus("Undead mini boss active.")
        end
        return true
    end

    Extra.UndeadMiniBoss = nil
    if payload.defeated == true then
        Extra.setUndeadStatus("Undead mini boss defeated.")
    else
        Extra.setUndeadStatus("Waiting for undead mini boss.")
    end
    return false
end

function Extra.requestUndeadMiniBossState(force)
    local now = os.clock()
    if not force and now - (Extra.UndeadLastStateRequestAt or 0) < 5 then
        return false
    end

    local remote = getBossRemote("RequestUndeadMiniBossState")
    if not remote then
        Extra.setUndeadStatus("RequestUndeadMiniBossState remote was not found.")
        return false
    end

    Extra.UndeadLastStateRequestAt = now
    Marker:SetAttribute("UndeadLastStateRequest", Workspace:GetServerTimeNow())
    remote:FireServer()
    return true
end

function Extra.hitUndeadMiniBoss(force)
    if not Extra.undeadEnabled() then
        return false
    end

    local info = Extra.UndeadMiniBoss
    if typeof(info) ~= "table" or info.id == nil then
        return false
    end

    local now = os.clock()
    local delaySeconds = math.max(0.25, getNumberOption("AutoUndeadHitDelayMs", 500) / 1000)
    if not force and now - (Extra.UndeadLastHitAt or 0) < delaySeconds then
        return false
    end

    local position = info.position
    if typeof(position) == "Vector3" then
        if Extra.undeadMoveEnabled() then
            Extra.setBossMoveTarget(CFrame.new(position + Vector3.new(0, 3, 0)), delaySeconds + 0.35, "Undead Mini Boss")
        else
            local root = getRoot()
            if root and (root.Position - position).Magnitude > 54 then
                Extra.setUndeadStatus("Undead mini boss is out of hit range.")
                return false
            end
        end
    end

    local remote = getBossRemote("UndeadMiniBossHitRequested")
    if not remote then
        Extra.setUndeadStatus("UndeadMiniBossHitRequested remote was not found.")
        return false
    end

    Extra.UndeadLastHitAt = now
    Marker:SetAttribute("UndeadLastHitId", tostring(info.id))
    Marker:SetAttribute("UndeadLastHitAt", Workspace:GetServerTimeNow())
    remote:FireServer(info.id)
    return true
end

function Extra.disconnectUndeadEvents()
    disconnect("UndeadMiniBossStateChanged")
end

function Extra.connectUndeadEvents()
    Extra.disconnectUndeadEvents()

    local stateRemote = getBossRemote("UndeadMiniBossStateChanged")
    if stateRemote then
        Connections.UndeadMiniBossStateChanged = stateRemote.OnClientEvent:Connect(function(payload)
            Extra.applyUndeadMiniBossState(payload)
        end)
    end
end

function Extra.startAutoUndeadLoop()
    stopTask("AutoUndead")
    Extra.connectUndeadEvents()
    Extra.requestUndeadMiniBossState(true)

    Tasks.AutoUndead = task.spawn(function()
        while Marker:GetAttribute("Session") == Session and Extra.undeadEnabled() do
            Extra.requestUndeadMiniBossState(false)
            Extra.hitUndeadMiniBoss(false)
            task.wait(0.2)
        end
    end)
end

function Extra.stopAutoUndeadLoop()
    stopTask("AutoUndead")
    Extra.disconnectUndeadEvents()
    Extra.UndeadMiniBoss = nil
    if Extra.BossMoveReason == "Undead Mini Boss" then
        Extra.BossMoveCFrame = nil
        Extra.BossMoveUntil = 0
        Extra.BossMoveReason = nil
    end
    Extra.setUndeadStatus("Auto Undead is off.")
end

function Extra.refreshAutoUndead()
    if Extra.undeadEnabled() then
        Extra.startAutoUndeadLoop()
    else
        Extra.stopAutoUndeadLoop()
    end
end

function Extra.disconnectBossEvents()
    disconnect("BossStateChanged")
    disconnect("BossSpawnResult")
    disconnect("BossParrySequence")
    disconnect("BossParryResult")
    disconnect("BossSplitPickupSpawned")
    disconnect("BossVictoryRewards")
    disconnect("BossUpgradeResult")
    disconnect("BossThunderWave")
end

function Extra.connectBossEvents()
    Extra.disconnectBossEvents()

    local stateRemote = getBossRemote("BossStateChanged")
    if stateRemote then
        Connections.BossStateChanged = stateRemote.OnClientEvent:Connect(function(payload)
            Extra.applyBossState(payload)
        end)
    end

    local spawnResultRemote = getBossRemote("BossSpawnResult")
    if spawnResultRemote then
        Connections.BossSpawnResult = spawnResultRemote.OnClientEvent:Connect(function(ok, reason)
            if ok then
                Extra.setBossStatus("Boss start accepted.")
            else
                Extra.setBossStatus("Boss start denied: " .. tostring(reason or "unknown"))
            end
            Extra.requestBossState(true)
        end)
    end

    local parrySequenceRemote = getBossRemote("BossParrySequence")
    if parrySequenceRemote then
        Connections.BossParrySequence = parrySequenceRemote.OnClientEvent:Connect(function(payload)
            Extra.handleBossParrySequence(payload)
        end)
    end

    local parryResultRemote = getBossRemote("BossParryResult")
    if parryResultRemote then
        Connections.BossParryResult = parryResultRemote.OnClientEvent:Connect(function(promptId, hit, reason)
            Marker:SetAttribute("BossLastParryResultPrompt", tostring(promptId))
            Marker:SetAttribute("BossLastParryResultHit", hit == true)
            Marker:SetAttribute("BossLastParryResultReason", tostring(reason or ""))
        end)
    end

    local pickupRemote = getBossRemote("BossSplitPickupSpawned")
    if pickupRemote then
        Connections.BossSplitPickupSpawned = pickupRemote.OnClientEvent:Connect(function(payload)
            task.spawn(Extra.collectBossSplitPickup, payload)
        end)
    end

    local thunderRemote = getBossRemote("BossThunderWave")
    if thunderRemote then
        Connections.BossThunderWave = thunderRemote.OnClientEvent:Connect(function()
            if Extra.bossAttackVfxRemovalEnabled() then
                task.defer(Extra.removeBossAttackVfx)
            end
            if Extra.bossFightEnabled() then
                Extra.updateBossMovementTarget("Boss Thunder Dodge", 3)
            end
        end)
    end

    local upgradeResultRemote = getBossRemote("BossUpgradeResult")
    if upgradeResultRemote then
        Connections.BossUpgradeResult = upgradeResultRemote.OnClientEvent:Connect(function(ok, payload)
            Extra.handleBossUpgradeResult(ok, payload)
        end)
    end

    local victoryRemote = getBossRemote("BossVictoryRewards")
    if victoryRemote then
        Connections.BossVictoryRewards = victoryRemote.OnClientEvent:Connect(function(...)
            Marker:SetAttribute("BossLastVictoryAt", Workspace:GetServerTimeNow())
            Marker:SetAttribute("BossLastVictoryArgs", select("#", ...))
            Extra.setBossStatus("Boss victory rewards received.")
            local payload = select(1, ...)
            local pickedCard = Extra.pickBossVictoryCard(payload)
            if Toggles.ToggleAutoBossCloseVictory and Toggles.ToggleAutoBossCloseVictory.Value then
                task.delay(pickedCard and 2.5 or 1, function()
                    if not Extra.BossCardSpendActive then
                        Extra.closeBossVictoryRewards(pickedCard and "victory-fallback" or "victory", false)
                    end
                end)
            end
        end)
    end
end

function Extra.startAutoBossLoop()
    stopTask("AutoBoss")
    Extra.connectBossEvents()
    Extra.requestBossState(true)

    Tasks.AutoBoss = task.spawn(function()
        while Marker:GetAttribute("Session") == Session and Extra.bossAutomationEnabled() do
            Extra.requestBossState(false)

            if (Toggles.ToggleAutoBossStart and Toggles.ToggleAutoBossStart.Value)
                or Extra.bossPayOpenEnabled() then
                Extra.fireBossStart(false)
            end

            if Extra.bossMoveEnabled() then
                local status = Extra.BossState and Extra.BossState.status or "unknown"
                if status == "active" or status == "spawning" then
                    Extra.updateBossMovementTarget("Boss Arena", 1.5)
                end
            end

            task.wait(1)
        end
    end)
end

function Extra.stopAutoBossLoop()
    stopTask("AutoBoss")
    Extra.disconnectBossEvents()
    if Extra.BossMoveReason ~= "Undead Mini Boss" or not Extra.undeadEnabled() then
        Extra.BossMoveCFrame = nil
        Extra.BossMoveUntil = 0
        Extra.BossMoveReason = nil
    end
    Extra.setBossStatus("Auto Boss is off. " .. Extra.describeBossState())
end

function Extra.refreshAutoBoss()
    if Extra.bossAutomationEnabled() then
        Extra.startAutoBossLoop()
    else
        Extra.stopAutoBossLoop()
    end
end
end

do
local function getQuestConstants()
    if Extra.Constants then
        return Extra.Constants
    end

    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local module = shared and shared:FindFirstChild("Constants")
    if module and module:IsA("ModuleScript") then
        local ok, constants = pcall(require, module)
        if ok and typeof(constants) == "table" then
            Extra.Constants = constants
            return constants
        end
    end

    return nil
end

local function questClaimCooldown()
    return math.max(30, getNumberOption("AutoQuestClaimRetrySeconds", 120))
end

local function questClaimReady(key)
    return os.clock() - (Extra.QuestClaimLastAttempt[key] or 0) >= questClaimCooldown()
end

local function markQuestClaimAttempt(key)
    Extra.QuestClaimLastAttempt[key] = os.clock()
end

function Extra.autoQuestClaimsEnabled()
    return (Toggles.ToggleAutoDailyQuestClaim and Toggles.ToggleAutoDailyQuestClaim.Value)
        or (Toggles.ToggleAutoQuestClaim and Toggles.ToggleAutoQuestClaim.Value)
end

function Extra.setQuestClaimStatus(message)
    local text = tostring(message)
    Marker:SetAttribute("QuestClaimStatus", text)
    if Extra.QuestClaimStatusLabel then
        pcall(function()
            Extra.QuestClaimStatusLabel:SetText(text)
        end)
    end
end

function Extra.claimReadyDailyQuests(profile)
    if not (Toggles.ToggleAutoDailyQuestClaim and Toggles.ToggleAutoDailyQuestClaim.Value) then
        return 0
    end
    if typeof(profile) ~= "table" or typeof(profile.dailyQuests) ~= "table" then
        return 0
    end

    local dailyQuests = profile.dailyQuests.quests
    if typeof(dailyQuests) ~= "table" then
        return 0
    end

    local remote = getRemote("ClaimDailyQuest", 10)
    if not remote then
        Extra.setQuestClaimStatus("ClaimDailyQuest remote was not found.")
        return 0
    end

    local fired = 0
    for _, quest in pairs(dailyQuests) do
        if typeof(quest) == "table" and quest.id ~= nil and quest.claimed ~= true then
            local progress = tonumber(quest.progress) or 0
            local goal = tonumber(quest.goal) or math.huge
            local key = "daily:" .. tostring(quest.id)
            if progress >= goal and questClaimReady(key) then
                markQuestClaimAttempt(key)
                remote:FireServer(quest.id)
                fired += 1
                Marker:SetAttribute("LastDailyQuestClaimId", tostring(quest.id))
                Marker:SetAttribute("LastDailyQuestClaimAt", Workspace:GetServerTimeNow())
                task.wait(0.15)
            end
        end
    end

    return fired
end

function Extra.claimReadyQuests(profile)
    if not (Toggles.ToggleAutoQuestClaim and Toggles.ToggleAutoQuestClaim.Value) then
        return 0
    end
    if typeof(profile) ~= "table" or typeof(profile.quests) ~= "table" then
        return 0
    end

    local constants = getQuestConstants()
    local questList = constants and constants.QUESTS
    local progress = profile.quests.progress
    local claimed = profile.quests.claimed
    if typeof(questList) ~= "table" or typeof(progress) ~= "table" or typeof(claimed) ~= "table" then
        return 0
    end

    local remote = getRemote("ClaimQuest", 10)
    if not remote then
        Extra.setQuestClaimStatus("ClaimQuest remote was not found.")
        return 0
    end

    local fired = 0
    for _, quest in pairs(questList) do
        if typeof(quest) == "table" and quest.id ~= nil and claimed[quest.id] ~= true then
            local goal = tonumber(quest.goal)
            local value = tonumber(progress[quest.statKey]) or 0
            local key = "quest:" .. tostring(quest.id)
            if goal and value >= goal and questClaimReady(key) then
                markQuestClaimAttempt(key)
                remote:FireServer(quest.id)
                fired += 1
                Marker:SetAttribute("LastQuestClaimId", tostring(quest.id))
                Marker:SetAttribute("LastQuestClaimAt", Workspace:GetServerTimeNow())
                task.wait(0.15)
            end
        end
    end

    return fired
end

function Extra.claimReadyQuestRewards()
    local profile = getProfileData()
    if typeof(profile) ~= "table" then
        Extra.setQuestClaimStatus("Waiting for profile data.")
        return 0
    end

    local daily = Extra.claimReadyDailyQuests(profile)
    local regular = Extra.claimReadyQuests(profile)
    local total = daily + regular
    if total > 0 then
        Extra.setQuestClaimStatus("Claim fired: " .. tostring(daily) .. " daily, " .. tostring(regular) .. " quest.")
    else
        Extra.setQuestClaimStatus("No ready quest rewards.")
    end

    return total
end

function Extra.connectQuestClaimEvents()
    disconnect("QuestClaimed")
    disconnect("DailyQuestClaimed")

    local questClaimed = getRemote("QuestClaimed", 5)
    if questClaimed then
        Connections.QuestClaimed = questClaimed.OnClientEvent:Connect(function(...)
            Marker:SetAttribute("QuestClaimedAt", Workspace:GetServerTimeNow())
            Marker:SetAttribute("QuestClaimedArgs", select("#", ...))
            Extra.setQuestClaimStatus("Quest claim confirmed.")
        end)
    end

    local dailyClaimed = getRemote("DailyQuestClaimed", 5)
    if dailyClaimed then
        Connections.DailyQuestClaimed = dailyClaimed.OnClientEvent:Connect(function(...)
            Marker:SetAttribute("DailyQuestClaimedAt", Workspace:GetServerTimeNow())
            Marker:SetAttribute("DailyQuestClaimedArgs", select("#", ...))
            Extra.setQuestClaimStatus("Daily quest claim confirmed.")
        end)
    end
end

function Extra.startAutoQuestClaims()
    stopTask("AutoQuestClaims")
    Extra.connectQuestClaimEvents()
    Tasks.AutoQuestClaims = task.spawn(function()
        while Marker:GetAttribute("Session") == Session and Extra.autoQuestClaimsEnabled() do
            local fired = Extra.claimReadyQuestRewards()
            task.wait(fired > 0 and 5 or 15)
        end
    end)
end

function Extra.stopAutoQuestClaims()
    stopTask("AutoQuestClaims")
    disconnect("QuestClaimed")
    disconnect("DailyQuestClaimed")
    Extra.setQuestClaimStatus("Auto quest claims are off.")
end

function Extra.refreshAutoQuestClaims()
    if Extra.autoQuestClaimsEnabled() then
        Extra.startAutoQuestClaims()
    else
        Extra.stopAutoQuestClaims()
    end
end
end

local function fireGodlyOrbClaim(count, delaySeconds)
    local remote = getGodlyOrbCollectedRemote()
    if not remote then
        notify("GodlyOrbCollected remote was not found.")
        return 0
    end

    count = math.max(1, math.floor(tonumber(count) or 1))
    delaySeconds = math.max(0, tonumber(delaySeconds) or 0)

    for _ = 1, count do
        remote:FireServer()
        if delaySeconds > 0 then
            task.wait(delaySeconds)
        end
    end

    return count
end

function Extra.findMidasGoldBarTouchPart(position)
    local bestPart = nil
    local bestDistance = math.huge
    local targetPosition = payloadToPosition(position)

    for _, instance in ipairs(Workspace:GetDescendants()) do
        if instance:IsA("BasePart") and instance.Name == "RadiusCircle" then
            local model = instance:FindFirstAncestorWhichIsA("Model")
            if model and model:GetAttribute("ClientMidasGoldBarVisual") == true then
                local distance = targetPosition and (instance.Position - targetPosition).Magnitude or 0
                if distance < bestDistance then
                    bestPart = instance
                    bestDistance = distance
                end
            end
        end
    end

    if bestPart and (not targetPosition or bestDistance <= 25) then
        return bestPart
    end
    return nil
end

function Extra.touchMidasGoldBar(position)
    local root = getRoot()
    local part = Extra.findMidasGoldBarTouchPart(position)
    if not (root and part and typeof(firetouchinterest) == "function") then
        return false
    end

    pcall(firetouchinterest, root, part, 0)
    task.wait(0.05)
    pcall(firetouchinterest, root, part, 1)
    Marker:SetAttribute("MidasLastTouchPart", part:GetFullName())
    return true
end

local function collectMidasGoldBar(id, position)
    if Extra.bossHasMovementPriority and Extra.bossHasMovementPriority() then
        MidasMovePosition = nil
        MidasMoveUntil = 0
        Marker:SetAttribute("MidasSkippedForBoss", Workspace:GetServerTimeNow())
        return false
    end

    if typeof(id) ~= "string" and typeof(id) ~= "number" then
        return false
    end

    local key = tostring(id)
    local now = os.clock()
    if now - (MidasLastCollectAt[key] or 0) < 1 then
        return false
    end

    local remote = getRemote("CollectGoldBar", 10)
    if not remote then
        notify("CollectGoldBar remote was not found.")
        return false
    end

    local targetPosition = payloadToPosition(position)
    if targetPosition then
        MidasMovePosition = targetPosition
        MidasMoveUntil = os.clock() + 5

        local deadline = os.clock() + 5
        while FallingStarMovePosition and os.clock() <= FallingStarMoveUntil and os.clock() < deadline do
            task.wait(0.05)
        end

        if FallingStarMovePosition and os.clock() <= FallingStarMoveUntil then
            return false
        end

        MidasMoveUntil = os.clock() + 0.8

        local root = getRoot()
        if root then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = CFrame.new(targetPosition + Vector3.new(0, 3, 0))
        end

        task.wait(0.2)
        if FallingStarMovePosition and os.clock() <= FallingStarMoveUntil then
            return false
        end
    end

    MidasLastCollectAt[key] = os.clock()
    remote:FireServer(id)
    Marker:SetAttribute("MidasLastGoldBarId", key)
    Marker:SetAttribute("MidasLastGoldBarCollectAt", Workspace:GetServerTimeNow())
    return true
end

function Extra.setAutoMidasStatus(message)
    local text = tostring(message)
    Marker:SetAttribute("AutoMidasStatus", text)
    Marker:SetAttribute("AutoMidasGoldCount", Extra.AutoMidasGoldCount)
    Marker:SetAttribute("AutoMidasGoldCountSource", Extra.AutoMidasGoldCountSource)
    Marker:SetAttribute("AutoMidasHeldGoldBar", Extra.AutoMidasHeldGoldBar ~= nil)

    if Extra.AutoMidasStatusLabel then
        pcall(function()
            Extra.AutoMidasStatusLabel:SetText(text)
        end)
    end
end

function Extra.getMidasTagLabel()
    local runtime = Workspace:FindFirstChild("Runtime")
    local followers = runtime and runtime:FindFirstChild("Followers")
    if not followers then
        return nil
    end

    local expectedName = LocalPlayer.Name .. "_MidasBob"
    local follower = followers:FindFirstChild(expectedName)
    if not follower then
        local expectedLower = expectedName:lower()
        for _, child in ipairs(followers:GetChildren()) do
            if tostring(child.Name):lower() == expectedLower then
                follower = child
                break
            end
        end
    end

    if not follower then
        return nil
    end

    local body = follower:FindFirstChild("body")
    local mainBody = body and body:FindFirstChild("MainBody")
    local tag = mainBody and mainBody:FindFirstChild("MidasTag")
    tag = tag or follower:FindFirstChild("MidasTag", true)
    local label = tag and tag:FindFirstChild("TextLabel", true)
    if label and (label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox")) then
        return label
    end
    return nil
end

function Extra.getMidasTagCount()
    local label = Extra.getMidasTagLabel()
    if not label then
        return nil
    end

    local ok, contentText = pcall(function()
        return label.ContentText
    end)
    local text = ok and tostring(contentText or "") or ""
    if text == "" then
        text = tostring(label.Text or "")
    end

    local count = tonumber(text:match("%d+"))
    if not count then
        return nil
    end
    return math.clamp(math.floor(count), 0, 10)
end

function Extra.syncAutoMidasCountFromTag()
    local count = Extra.getMidasTagCount()
    if count == nil then
        return false
    end

    Extra.AutoMidasGoldCount = count
    Extra.AutoMidasGoldCountSource = "midas-tag"
    Marker:SetAttribute("AutoMidasGoldCount", Extra.AutoMidasGoldCount)
    Marker:SetAttribute("AutoMidasGoldCountSource", Extra.AutoMidasGoldCountSource)
    Marker:SetAttribute("BuffComboMidasCount", Extra.AutoMidasGoldCount)
    Marker:SetAttribute("BuffComboMidasCountSource", Extra.AutoMidasGoldCountSource)
    return true
end

function Extra.resetAutoMidasCount(source)
    Extra.AutoMidasGoldCount = 0
    Extra.AutoMidasGoldCountSource = source or "reset"
    Extra.AutoMidasHeldGoldBar = nil
    Extra.BuffComboHeldGoldBar = nil
    Extra.setAutoMidasStatus("Auto Midas count: " .. tostring(Extra.AutoMidasGoldCount) .. "/10.")
end

function Extra.refreshAutoMidasBoostState()
    Extra.syncAutoMidasCountFromTag()
    if isBoostActive("midasBob") ~= true then
        return false
    end

    if Extra.AutoMidasGoldCount ~= 0 or Extra.AutoMidasGoldCountSource ~= "boost-active" then
        Extra.resetAutoMidasCount("boost-active")
        Extra.setAutoMidasStatus("Midas boost active. Auto Midas count forced to 0/10.")
    end
    return true
end

function Extra.noteMidasGoldCollected(source)
    if Extra.refreshAutoMidasBoostState() then
        return 0
    end

    if not Extra.syncAutoMidasCountFromTag() then
        Extra.AutoMidasGoldCount = math.clamp(Extra.AutoMidasGoldCount + 1, 0, 10)
        Extra.AutoMidasGoldCountSource = source or "observed"
    end
    Extra.setAutoMidasStatus("Collected Midas bar: "
        .. tostring(Extra.AutoMidasGoldCount) .. "/10.")
    task.delay(0.25, function()
        if not Extra.refreshAutoMidasBoostState() then
            Extra.syncAutoMidasCountFromTag()
        end
        Extra.setAutoMidasStatus("Midas tag count: " .. tostring(Extra.AutoMidasGoldCount) .. "/10.")
    end)
    return Extra.AutoMidasGoldCount
end

function Extra.collectAutoMidasGoldBar(id, position)
    if Extra.refreshAutoMidasBoostState() then
        return false
    end

    Extra.syncAutoMidasCountFromTag()
    if Toggles.ToggleAutoMidasHoldAt9 and Toggles.ToggleAutoMidasHoldAt9.Value
        and Extra.AutoMidasGoldCount >= 9 then
        Extra.AutoMidasHeldGoldBar = {
            id = id,
            position = position,
            receivedAt = os.clock(),
        }
        Extra.setAutoMidasStatus("Holding Midas bar at 9/10.")
        return true
    end

    task.spawn(function()
        if collectMidasGoldBar(id, position) then
            Extra.AutoMidasHeldGoldBar = nil
            Extra.noteMidasGoldCollected("observed")
        end
    end)
    return true
end

function Extra.collectHeldAutoMidasGoldBar()
    local held = Extra.AutoMidasHeldGoldBar
    if not held then
        return false
    end

    Extra.AutoMidasHeldGoldBar = nil
    return Extra.collectAutoMidasGoldBar(held.id, held.position)
end

local function connectMidasGoldEvents()
    local spawned = getRemote("GoldBarSpawned", 10)
    if spawned and not Connections.MidasGoldBarSpawned then
        Connections.MidasGoldBarSpawned = spawned.OnClientEvent:Connect(function(id, position)
            Marker:SetAttribute("MidasLastGoldBarSpawnedAt", Workspace:GetServerTimeNow())
            if Extra.handleBuffComboGoldBar and Extra.handleBuffComboGoldBar(id, position) then
                return
            end
            if Toggles.ToggleAutoMidasGold and Toggles.ToggleAutoMidasGold.Value then
                Extra.collectAutoMidasGoldBar(id, position)
            end
        end)
    end

    local cleared = getRemote("GoldBarCleared", 10)
    if cleared and not Connections.MidasGoldBarCleared then
        Connections.MidasGoldBarCleared = cleared.OnClientEvent:Connect(function(id)
            if typeof(id) == "string" or typeof(id) == "number" then
                MidasLastCollectAt[tostring(id)] = nil
            end
        end)
    end

    local boostActivated = getRemote("BoostActivated", 10)
    if boostActivated and not Connections.MidasBoostActivated then
        Connections.MidasBoostActivated = boostActivated.OnClientEvent:Connect(function(boostId, expiresAt)
            if boostId == "midasBob" and typeof(expiresAt) == "number" and expiresAt > os.time() then
                Extra.resetAutoMidasCount("boost-reset")
                Extra.setAutoMidasStatus("Midas boost activated. Auto Midas count reset to 0/10.")
            end
        end)
    end
end

local function getGemBobActionButton()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local actionGui = playerGui and playerGui:FindFirstChild("GemBobActionGui")
    local button = actionGui and actionGui:FindFirstChild("ActionButton", true)
    return button and button:IsA("TextButton") and button or nil
end

local function isGemStormReady()
    local button = getGemBobActionButton()
    if not button or not tostring(button.Text):upper():find("READY", 1, true) then
        return false
    end

    local gui = button:FindFirstAncestorWhichIsA("BillboardGui")
    return not gui or gui.Enabled
end

local function fireGemStorm()
    if not isGemStormReady() or not canFireReadyAction("GemStorm", 3) then
        return false
    end

    local remote = getGemBobAbilityRequestedRemote()
    if not remote then
        notify("GemBobAbilityRequested remote was not found.")
        return false
    end

    remote:FireServer()
    Marker:SetAttribute("GemStormLastRequest", Workspace:GetServerTimeNow())
    return true
end

local function claimGemIds(ids)
    local remote = getCollectGemBobGemsRemote()
    if not remote or #ids == 0 then
        return 0
    end

    local claimed = 0
    local batchLimit = 50
    for first = 1, #ids, batchLimit do
        local batch = {}
        for index = first, math.min(first + batchLimit - 1, #ids) do
            batch[#batch + 1] = ids[index]
        end

        remote:FireServer(batch)
        claimed += #batch
        task.wait(0.05)
    end

    Marker:SetAttribute("GemIdsLastClaimed", claimed)
    Marker:SetAttribute("GemClaimLastFire", Workspace:GetServerTimeNow())
    return claimed
end

local function scheduleGemBatchClaims(gems)
    if typeof(gems) ~= "table" then
        return
    end

    local pending = {}
    for _, gem in pairs(gems) do
        if typeof(gem) == "table" and typeof(gem.id) == "string" then
            pending[#pending + 1] = {
                id = gem.id,
                spawnAt = typeof(gem.spawnAt) == "number" and gem.spawnAt or Workspace:GetServerTimeNow(),
            }
        end
    end

    table.sort(pending, function(left, right)
        return left.spawnAt < right.spawnAt
    end)

    task.spawn(function()
        local index = 1
        while index <= #pending and Toggles.ToggleAutoCollectGemStorm and Toggles.ToggleAutoCollectGemStorm.Value do
            local waitSeconds = pending[index].spawnAt - Workspace:GetServerTimeNow()
            if waitSeconds > 0 then
                task.wait(waitSeconds)
            end

            local ready = {}
            local now = Workspace:GetServerTimeNow() + 0.1
            while index <= #pending and pending[index].spawnAt <= now do
                ready[#ready + 1] = pending[index].id
                index += 1
            end

            if #ready > 0 then
                claimGemIds(ready)
            end
        end
    end)
end

local AbilityRemotes = {
    { name = "ActivateHolyBeam", toggle = "ToggleAbilityHolyBeam" },
    { name = "ActivateVoid", toggle = "ToggleAbilityVoid" },
    { name = "ActivateLuckyRush", toggle = "ToggleAbilityLuckyRush" },
    { name = "ActivateAutocollect", toggle = "ToggleAbilityAutocollect" },
}

local PotionOptions = {
    { id = "rainbowPotion", toggle = "TogglePotionRainbow" },
    { id = "energyPotion", toggle = "TogglePotionEnergy" },
    { id = "godlyPotion", toggle = "TogglePotionGodly" },
    { id = "amuletLuckPotion", toggle = "TogglePotionAmuletLuck" },
    { id = "elementalPotion", toggle = "TogglePotionElemental" },
}

Extra.ComboPotionOptions = {
    { label = "Godly Potion", id = "godlyPotion", inventory = "godlyPotions", costCurrency = "sp", costAmount = 10 },
    { label = "Rainbow Potion", id = "rainbowPotion", inventory = "rainbowPotions", costCurrency = "sp", costAmount = 49, skipIfRemainingAbove = 600 },
    { label = "Energy Potion", id = "energyPotion", inventory = "energyPotions", costCurrency = "rt", costAmount = 15 },
    { label = "Amulet Luck Potion", id = "amuletLuckPotion", inventory = "amuletLuckPotions", costCurrency = "sd", costAmount = 49 },
    { label = "Elemental Potion", id = "elementalPotion", inventory = "elementalPotions", costCurrency = "sd", costAmount = 250 },
}
Extra.ComboPotionLabels = {}
Extra.ComboPotionByLabel = {}
for _, potion in ipairs(Extra.ComboPotionOptions) do
    Extra.ComboPotionLabels[#Extra.ComboPotionLabels + 1] = potion.label
    Extra.ComboPotionByLabel[potion.label] = potion
end

Extra.AutoUpgradeBoards = (function()
local UpgradeLegacyKeys = {
    AutoHolyBeamUpgrade = "autoHolyBeam", AutoVoidUpgrade = "autoVoid", BeamCooldownUpgrade = "beamCooldown",
    BeamSizeUpgrade = "beamSize", BeamUpgrade = "beam", CollectingRadiusUpgrade = "collectingRadius",
    CorruptChanceUpgrade = "corruptChance", CorruptPowerUpgrade = "corruptPower",
    CorruptedSlimeCooldownUpgrade = "corruptedSlimeCooldown", CorruptedSlimeMaxCapUpgrade = "corruptedSlimeMaxCap",
    CorruptedSlimeValueUpgrade = "corruptedSlimeValue", FallingStarsLuckUpgrade = "fallingStarsLuck",
    GemSpawnChanceUpgrade = "gemSpawnChance", GemTierUpgrade = "gemTier", GemValueUpgrade = "gemValue",
    GemValueUpgrade2 = "gemValue2", GiantSlimeChanceUpgrade = "giantSlimeChance",
    GodlySlimeChanceUpgrade = "godlySlimeChance", HolyBeamCooldownUpgrade = "holyBeamCooldown",
    HolyBeamUpgrade = "holyBeam", LevelMultiplierUpgrade = "levelMultiplier",
    LevelMultiplierUpgrade2 = "levelMultiplier2", LevelMultiplierUpgrade3 = "levelMultiplier3",
    LongerHolyBeamUpgrade = "longerHolyBeam", LuckyRushCooldownUpgrade = "luckyRushCooldown",
    LuckyRushPowerUpgrade = "luckyRushPower", LuckyRushUpgrade = "luckyRush", MaxCapUpgrade = "maxCap",
    MoreFallingStarsUpgrade = "moreFallingStars", MoreSlimesUpgrade = "moreSlimes",
    MoreSlimesUpgrade2 = "moreSlimes2", MoreSlimesUpgrade3 = "moreSlimes3",
    PlayerMovespeedUpgrade = "playerMovespeed", RoombaSizeUpgrade = "roombaSize",
    RoombaSpeedUpgrade = "roombaSpeed", RoombaUpgrade = "roomba", ShinyChanceUpgrade = "shinyChance",
    ShinyChanceUpgrade2 = "shinyChance2", ShinyMultiplierUpgrade = "shinyMultiplier",
    SlimeTierUpgrade = "slimeTier", SlimeTierUpgrade2 = "slimeTier2", SlimeValueUpgrade = "slimeValue",
    SlimeValueUpgrade2 = "slimeValue2", SpawnRateUpgrade = "spawnRate",
    StardustMachineCooldownUpgrade = "stardustMachineCooldown", StardustMultiplierUpgrade = "stardustMultiplier",
    TitanicSlimeChanceUpgrade = "titanicSlimeChance", VoidCooldownUpgrade = "voidCooldown",
    VoidDurationUpgrade = "voidDuration", VoidMultiplierUpgrade = "voidMultiplier", VoidUpgrade = "void",
}
local AutoUpgradeBoardOrder = { "Main", "Lvl5", "Lvl25", "Lvl50", "Lvl75", "Tier15", "Lvl150", "Lvl200", "Lvl250", "Lvl350", "Lvl400" }
local AutoUpgradeBoardMeta = {
    Main = { name = "Main", icon = "house" }, Lvl5 = { name = "Level 5", icon = "sparkles" },
    Lvl25 = { name = "Level 25", icon = "gem" }, Lvl50 = { name = "Level 50", icon = "zap" },
    Lvl75 = { name = "Level 75", icon = "bot" }, Tier15 = { name = "Tier 15", icon = "crown" },
    Lvl150 = { name = "Level 150", icon = "bug" }, Lvl200 = { name = "Level 200", icon = "circle-dot" },
    Lvl250 = { name = "Level 250", icon = "star" }, Lvl350 = { name = "Level 350", icon = "sparkles" },
    Lvl400 = { name = "Level 400", icon = "meteor" },
}
local AutoUpgradeLabelOverrides = { gemValue2 = "Gem Value (SP)", slimeValue2 = "Slime Value (SP)" }
local AutoUpgradeFallbackEntries = {
    Main = { { "EXP Multiplier", "levelMultiplier" }, { "Slime Cooldown", "spawnRate" }, { "Slime Max Cap", "maxCap" }, { "Slime Tier", "slimeTier" }, { "Slime Value", "slimeValue" } },
    Lvl5 = { { "Slime Value (SP)", "slimeValue2" }, { "More Slimes", "moreSlimes" }, { "Collecting Area", "collectingRadius" }, { "Shiny Spawn Chance", "shinyChance" }, { "Player Movespeed", "playerMovespeed" } },
    Lvl25 = { { "Gem Spawn Chance", "gemSpawnChance" }, { "Holy Orb Cooldown", "holyBeamCooldown" }, { "Holy Orb Duration", "longerHolyBeam" }, { "Holy Orb", "holyBeam" }, { "Gem Value (SP)", "gemValue2" }, { "Gem Value", "gemValue" }, { "Gem Tier", "gemTier" } },
    Lvl50 = { { "Beam Cooldown", "beamCooldown" }, { "More Slimes", "moreSlimes2" }, { "Beam Size", "beamSize" }, { "Beam", "beam" }, { "Shiny Multiplier", "shinyMultiplier" } },
    Lvl75 = { { "Cleanbot Size", "roombaSize" }, { "Cleanbot Speed", "roombaSpeed" }, { "Cleanbot", "roomba" } },
    Tier15 = { { "Slime Tier", "slimeTier2" }, { "Shiny Spawn Chance", "shinyChance2" }, { "Titanic Slime Chance", "titanicSlimeChance" }, { "Auto Holy Orb", "autoHolyBeam" }, { "Giant Slime Chance", "giantSlimeChance" }, { "EXP Multiplier", "levelMultiplier2" } },
    Lvl150 = { { "Glitch Chance", "corruptChance" }, { "EXP Multiplier", "levelMultiplier3" }, { "Glitch Power", "corruptPower" }, { "More Slimes", "moreSlimes3" }, { "Corrupted Slime Max Cap", "corruptedSlimeMaxCap" }, { "Corrupted Slime Cooldown", "corruptedSlimeCooldown" }, { "Corrupted Slime Value", "corruptedSlimeValue" } },
    Lvl200 = { { "Void Orb", "void" }, { "Void Multiplier", "voidMultiplier" }, { "Void Orb Cooldown", "voidCooldown" }, { "Void Orb Duration", "voidDuration" } },
    Lvl250 = { { "Auto Void Orb", "autoVoid" }, { "Lucky Rush", "luckyRush" }, { "Lucky Rush Power", "luckyRushPower" }, { "Lucky Rush Cooldown", "luckyRushCooldown" } },
    Lvl350 = { { "Godly Slime Chance", "godlySlimeChance" } },
    Lvl400 = { { "Stardust Multiplier", "stardustMultiplier" }, { "Falling Stars Luck", "fallingStarsLuck" }, { "Stardust Machine Cooldown", "stardustMachineCooldown" }, { "More Falling Stars", "moreFallingStars" } },
}

local function prettyUpgradeLabel(text, key)
    if AutoUpgradeLabelOverrides[key] then
        return AutoUpgradeLabelOverrides[key]
    end

    local words = {}
    for word in tostring(text or key):gmatch("%S+") do
        words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2):lower()
    end
    return table.concat(words, " ")
        :gsub("Exp", "EXP")
        :gsub("Sp", "SP")
        :gsub("Ge", "GE")
end

local function makeAutoUpgradeBoard(id, source)
    local meta = AutoUpgradeBoardMeta[id] or { name = id, icon = "circle-dot" }
    local entries = {}
    for _, entry in ipairs(source or {}) do
        entries[#entries + 1] = { label = entry.label or entry[1], key = entry.key or entry[2] }
    end
    return { id = id, name = meta.name, icon = meta.icon, entries = entries }
end

local function buildFallbackAutoUpgradeBoards()
    local boards = {}
    for _, id in ipairs(AutoUpgradeBoardOrder) do
        boards[#boards + 1] = makeAutoUpgradeBoard(id, AutoUpgradeFallbackEntries[id])
    end
    return boards
end

local function autoUpgradeBoardId(model, zones, mainUpgrades)
    local current = model
    while current and current ~= game do
        if current == mainUpgrades then
            return "Main"
        end
        if zones and current.Parent == zones then
            return current.Name
        end
        current = current.Parent
    end
    return nil
end

local function pushAutoUpgradeEntry(boardMap, boardId, label, key)
    if not (boardId and key) then
        return
    end

    local entries = boardMap[boardId]
    if not entries then
        entries = {}
        boardMap[boardId] = entries
    end
    entries[#entries + 1] = { label = prettyUpgradeLabel(label, key), key = key }
end

local function discoverAutoUpgradeBoards()
    local world = Workspace:FindFirstChild("World") or Workspace:WaitForChild("World", 5)
    local map = world and world:FindFirstChild("Map")
    local zones = world and world:FindFirstChild("Zones")
    local mainUpgrades = map and map:FindFirstChild("MainUpgrades")
    local boardMap = {}

    for _, root in ipairs({ mainUpgrades, zones }) do
        if root then
            for _, screen in ipairs(root:GetDescendants()) do
                if screen.Name == "Screen" and screen.Parent then
                    local surfaceGui = screen:FindFirstChild("SurfaceGui")
                    local title = surfaceGui and surfaceGui:FindFirstChild("TitleText")
                    local note = screen.Parent:FindFirstChild("Note")
                    local dataName = note and note:FindFirstChild("DataName")
                    local key = (dataName and UpgradeLegacyKeys[dataName.Value]) or UpgradeLegacyKeys[screen.Parent.Name]
                    pushAutoUpgradeEntry(boardMap, autoUpgradeBoardId(screen.Parent, zones, mainUpgrades), title and title.Text or screen.Parent.Name, key)
                end
            end
        end
    end

    local boards = {}
    for _, id in ipairs(AutoUpgradeBoardOrder) do
        if boardMap[id] and #boardMap[id] > 0 then
            boards[#boards + 1] = makeAutoUpgradeBoard(id, boardMap[id])
        end
    end
    return #boards > 0 and boards or buildFallbackAutoUpgradeBoards()
end

return discoverAutoUpgradeBoards()
end)()

local function upgradeSelectionId(board)
    return "UpgradeSelect" .. board.id
end

local function upgradeToggleId(board)
    return "ToggleAutoUpgrade" .. board.id
end

local function upgradeBoardLabels(board)
    local labels = {}
    for _, entry in ipairs(board.entries) do
        labels[#labels + 1] = entry.label
    end
    return labels
end

local function multiSelectionContains(selection, label)
    if typeof(selection) == "string" then
        return selection == label
    end

    if typeof(selection) ~= "table" then
        return false
    end

    if selection[label] == true then
        return true
    end

    for _, value in pairs(selection) do
        if value == label then
            return true
        end
    end

    return false
end

Extra.BlessingDefinitions = {
    { key = "SlimeValue", label = "Slime Value", progressionKey = "slimeValue", rarity = "Basic" },
    { key = "SlimeSpawnRate", label = "Slime Spawn Rate", progressionKey = "slimeSpawnRate", rarity = "Basic" },
    { key = "ExpMultiplier", label = "EXP Multiplier", progressionKey = "expMultiplier", rarity = "Basic" },
    { key = "MoreSlimes", label = "More Slimes", progressionKey = "moreSlimes", rarity = "Basic" },
    { key = "ShinyChance", label = "Shiny Chance", progressionKey = "shinyChance", rarity = "Legendary" },
    { key = "PlinkoBallBlessing", label = "Plinko Ball Power", progressionKey = "plinkoBall", rarity = "Legendary" },
    { key = "PlinkoBallCooldownBlessing", label = "Plinko Ball Cooldown", progressionKey = "plinkoBallCooldown", rarity = "Legendary" },
    { key = "PlinkoBallDurationBlessing", label = "Plinko Ball Duration", progressionKey = "plinkoBallDuration", rarity = "Legendary" },
    { key = "GemChance", label = "Gem Chance", progressionKey = "gemChance", rarity = "Basic" },
    { key = "GemValue", label = "Gem Value", progressionKey = "gemValue", rarity = "Basic" },
    { key = "GemBobCooldownBlessing", label = "Gem Storm Cooldown", progressionKey = "gemBobCooldown", rarity = "Legendary" },
    { key = "GemBobDurationBlessing", label = "Gem Storm Duration", progressionKey = "gemBobDuration", rarity = "Legendary" },
    { key = "Fortune", label = "Fortune", progressionKey = "fortune", rarity = "Mythic" },
    { key = "HugeBeam", label = "Huge Beam", progressionKey = "hugeBeam", rarity = "Mythic" },
    { key = "GiantSlimeChance", label = "Giant Slime Chance", progressionKey = "giantSlimeChance", rarity = "Legendary" },
    { key = "TitanicSlimeChance", label = "Titanic Slime Chance", progressionKey = "titanicSlimeChance", rarity = "Legendary" },
    { key = "CorruptedSlimeValue", label = "Corrupted Slime Value", progressionKey = "corruptedSlimeValue", rarity = "Basic" },
    { key = "CorruptChance", label = "Corrupt Chance", progressionKey = "corruptChance", rarity = "Legendary" },
    { key = "CorruptPower", label = "Corrupt Power", progressionKey = "corruptPower", rarity = "Legendary" },
    { key = "PartyBob", label = "Party Bob", progressionKey = "partyBob", rarity = "Mythic" },
    { key = "LuckyRushCooldown", label = "Lucky Rush Cooldown", progressionKey = "luckyRushCooldown", rarity = "Legendary" },
    { key = "AmuletStats", label = "Amulet Stats", progressionKey = "amuletStats", rarity = "Legendary" },
    { key = "GodlySlimeChance", label = "Godly Slime Chance", progressionKey = "godlySlimeChance", rarity = "Mythic" },
}
Extra.BlessingByKey = {}
Extra.BlessingByLabel = {}
Extra.BlessingLabels = {}
Extra.BlessingRarityRank = { Basic = 1, Legendary = 2, Mythic = 3 }
for _, definition in ipairs(Extra.BlessingDefinitions) do
    Extra.BlessingByKey[definition.key] = definition
    Extra.BlessingByLabel[definition.label] = definition
    Extra.BlessingLabels[#Extra.BlessingLabels + 1] = definition.label
end

local function purchaseUpgradeBoard(board)
    local remote = getRemote("PurchaseUpgrade", 10)
    local option = Options[upgradeSelectionId(board)]
    if not remote or not option then
        return 0
    end

    local fired = 0
    for _, entry in ipairs(board.entries) do
        if multiSelectionContains(option.Value, entry.label) then
            remote:FireServer(entry.key, "Max")
            fired += 1
            task.wait(0.12)
        end
    end

    Marker:SetAttribute("AutoUpgradeLastBoard", board.name)
    Marker:SetAttribute("AutoUpgradeLastFireCount", fired)
    Marker:SetAttribute("AutoUpgradeLastFireAt", Workspace:GetServerTimeNow())
    return fired
end

local function anyAutoUpgradeEnabled()
    local masterToggle = Toggles.ToggleAutoUpgradesMaster
    if masterToggle and not masterToggle.Value then
        return false
    end

    for _, board in ipairs(Extra.AutoUpgradeBoards) do
        local toggle = Toggles[upgradeToggleId(board)]
        if toggle and toggle.Value then
            return true
        end
    end
    return false
end

local function startAutoUpgradeLoop()
    stopTask("AutoUpgrades")

    Tasks.AutoUpgrades = task.spawn(function()
        while anyAutoUpgradeEnabled() do
            for _, board in ipairs(Extra.AutoUpgradeBoards) do
                local toggle = Toggles[upgradeToggleId(board)]
                if toggle and toggle.Value then
                    purchaseUpgradeBoard(board)
                end
            end
            task.wait(0.5)
        end
    end)
end

local function refreshAutoUpgradeLoop()
    if anyAutoUpgradeEnabled() then
        startAutoUpgradeLoop()
    else
        stopTask("AutoUpgrades")
    end
end

function Extra.setBlessingStatus(message)
    local text = tostring(message)
    Marker:SetAttribute("AutoBlessingStatus", text)
    if Extra.BlessingStatusLabel then
        pcall(function()
            Extra.BlessingStatusLabel:SetText(text)
        end)
    end
end

function Extra.setBlessingPriorityStatus()
    local order = Extra.BlessingPickPriority or {}
    local lines = { "Priority:" }
    for index, label in ipairs(order) do
        lines[#lines + 1] = string.format("%d. %s", index, label)
    end
    local text = #order > 0 and table.concat(lines, "\n") or "Priority: Random"
    Marker:SetAttribute("BlessingPickPriority", text)
    if Extra.BlessingPriorityLabel then
        pcall(function()
            Extra.BlessingPriorityLabel:SetText(text)
        end)
    end
end

function Extra.syncBlessingPickPriority(selection)
    selection = typeof(selection) == "table" and selection or {}
    local nextOrder = {}
    local included = {}

    for _, label in ipairs(Extra.BlessingPickPriority or {}) do
        if multiSelectionContains(selection, label) then
            nextOrder[#nextOrder + 1] = label
            included[label] = true
        end
    end

    for _, label in ipairs(Extra.BlessingLabels) do
        if not included[label] and multiSelectionContains(selection, label) then
            nextOrder[#nextOrder + 1] = label
            included[label] = true
        end
    end

    Extra.BlessingPickPriority = nextOrder
    Extra.setBlessingPriorityStatus()
end

function Extra.restoreBlessingPickPriority(savedOrder)
    if typeof(savedOrder) ~= "table" then
        return
    end

    local order = {}
    local selection = {}
    for _, label in ipairs(savedOrder) do
        if typeof(label) == "string" and Extra.BlessingByLabel[label] and not selection[label] then
            order[#order + 1] = label
            selection[label] = true
        end
    end

    Extra.BlessingPickPriority = order
    local option = Options.BlessingPickPriority
    if option then
        option:SetValue(selection)
    else
        Extra.setBlessingPriorityStatus()
    end
end

function Extra.blessingRuleSelected(optionId, definition)
    local option = Options[optionId]
    return option and multiSelectionContains(option.Value, definition.label) or false
end

function Extra.blessingIsBlacklisted(definition)
    return Extra.blessingRuleSelected("BlessingSacrificeBlacklist", definition)
end

function Extra.blessingOptionName(value)
    if typeof(value) == "string" then
        return Extra.BlessingByKey[value] and value or nil
    end
    if typeof(value) ~= "table" then
        return nil
    end

    for _, field in ipairs(Extra.BlessingOptionFields) do
        local candidate = value[field]
        if typeof(candidate) == "string" and Extra.BlessingByKey[candidate] then
            return candidate
        end
    end
    return nil
end

function Extra.bestBlessingOption(options)
    if typeof(options) ~= "table" then
        return nil, false
    end

    local offered = {}
    local offeredByLabel = {}
    for index, value in pairs(options) do
        local key = Extra.blessingOptionName(value)
        if not key and value == true then
            key = Extra.blessingOptionName(index)
        end

        local definition = key and Extra.BlessingByKey[key] or nil
        if definition then
            offered[#offered + 1] = key
            offeredByLabel[definition.label] = key
        end
    end

    for _, label in ipairs(Extra.BlessingPickPriority or {}) do
        if offeredByLabel[label] then
            return offeredByLabel[label], true
        end
    end

    if #offered < 1 then
        return nil, false
    end
    return offered[math.random(1, #offered)], false
end

function Extra.findSacrificialBlessing(profile)
    local progression = profile and profile.blessingProgression
    if typeof(progression) ~= "table" then
        return nil
    end

    local best = nil
    local bestRank = math.huge
    for _, definition in ipairs(Extra.BlessingDefinitions) do
        local count = tonumber(progression[definition.progressionKey]) or 0
        if count > 0 and not Extra.blessingIsBlacklisted(definition) then
            local rank = Extra.BlessingRarityRank[definition.rarity] or 0
            if rank < bestRank then
                best = definition
                bestRank = rank
            end
        end
    end
    return best
end

function Extra.getBlessingRemote(name)
    local remote = Extra.BlessingRemotes[name]
    if remote and remote.Parent then
        return remote
    end

    remote = getRemote(name, 10)
    Extra.BlessingRemotes[name] = remote
    return remote
end

function Extra.markBlessingActionPending(timeoutSeconds)
    Extra.BlessingActionPending = true
    Extra.BlessingActionSerial += 1
    local serial = Extra.BlessingActionSerial
    task.delay(timeoutSeconds or 4, function()
        if Extra.BlessingActionPending and Extra.BlessingActionSerial == serial then
            Extra.BlessingActionPending = false
        end
    end)
end

function Extra.connectBlessingEvents()
    if Connections.BlessingResult then
        return true
    end

    local remote = Extra.getBlessingRemote("BlessingResult")
    if not remote then
        notify("BlessingResult remote was not found.")
        return false
    end

    Connections.BlessingResult = remote.OnClientEvent:Connect(function(slot, options, success)
        local now = Workspace:GetServerTimeNow()
        Extra.BlessingActionPending = false
        Marker:SetAttribute("BlessingLastSlot", tonumber(slot) or 0)
        Marker:SetAttribute("BlessingLastResultAt", now)

        if success and typeof(options) == "table" then
            Extra.BlessingRetryAfter = now + 0.1
            Extra.BlessingPendingOptions = options
            Extra.setBlessingStatus("Blessing options received. Evaluating priorities...")
        elseif success then
            Extra.BlessingRetryAfter = now + 0.1
            Extra.BlessingPendingOptions = nil
            Extra.setBlessingStatus("Blessing choice accepted.")
        else
            Extra.BlessingRetryAfter = now + Extra.BlessingFailureRetrySeconds
            Extra.setBlessingStatus("Blessing request rejected or unavailable. Retrying soon.")
        end
    end)
    return true
end

function Extra.autoBlessingStep(forceRoll)
    if Extra.BlessingActionPending then
        return false
    end

    local now = Workspace:GetServerTimeNow()
    if now < (Extra.BlessingRetryAfter or 0) then
        return false
    end

    local activateRemote = Extra.getBlessingRemote("ActivateBlessing")
    local rerollRemote = Extra.getBlessingRemote("RerollBlessing")
    if not activateRemote or not rerollRemote or not Extra.connectBlessingEvents() then
        Extra.setBlessingStatus("Blessing remotes were not found.")
        return false
    end

    local options = Extra.BlessingPendingOptions
    if typeof(options) ~= "table" then
        local controller = Extra.getBlessingController()
        if controller and typeof(controller.getPendingOptions) == "function" then
            local ok, pending = pcall(controller.getPendingOptions)
            if ok and typeof(pending) == "table" then
                options = pending
            end
        end
    end

    if typeof(options) == "table" then
        local choice, matchedPriority = Extra.bestBlessingOption(options)
        if not choice then
            Extra.setBlessingStatus("No recognized blessing card was offered.")
            return false
        end

        local autoReroll = Toggles.ToggleAutoBlessingReroll and Toggles.ToggleAutoBlessingReroll.Value
        if autoReroll and #(Extra.BlessingPickPriority or {}) > 0 and not matchedPriority then
            local profile = getProfileData()
            local gemEnergy = profile and (tonumber(profile.gemEnergy) or 0) or 0
            if gemEnergy < 10 then
                Extra.setBlessingStatus(string.format("Need 10 GE to reroll choices. Current GE: %s", tostring(gemEnergy)))
                return false
            end

            local pendingRerollRemote = Extra.getBlessingRemote("RerollPendingBlessings")
            if not pendingRerollRemote then
                Extra.setBlessingStatus("RerollPendingBlessings remote was not found.")
                return false
            end

            Extra.BlessingPendingOptions = nil
            Extra.markBlessingActionPending(Extra.BlessingActionTimeout)
            pendingRerollRemote:FireServer()
            Marker:SetAttribute("BlessingLastPendingRerollAt", now)
            Extra.setBlessingStatus("Rerolling offered choices without sacrificing...")
            return true
        end

        Extra.BlessingPendingOptions = nil
        Extra.markBlessingActionPending(Extra.BlessingActionTimeout)
        local controller = Extra.getBlessingController()
        local usedController = false
        if controller and typeof(controller.getPendingOptions) == "function" and typeof(controller.pick) == "function" then
            local pendingOk, pending = pcall(controller.getPendingOptions)
            if pendingOk and typeof(pending) == "table" then
                usedController = pcall(controller.pick, choice)
            end
        end
        if not usedController then
            activateRemote:FireServer(choice)
        end
        local definition = Extra.BlessingByKey[choice]
        Extra.setBlessingStatus("Selecting " .. (definition and definition.label or choice) .. ".")
        Marker:SetAttribute("BlessingLastChoice", choice)
        return true
    end

    local profile = getProfileData()
    if not profile then
        Extra.setBlessingStatus("Waiting for profile data...")
        return false
    end

    local autoRoll = forceRoll == true or (Toggles.ToggleAutoBlessing and Toggles.ToggleAutoBlessing.Value)
    local autoSacrifice = Toggles.ToggleAutoBlessingSacrifice and Toggles.ToggleAutoBlessingSacrifice.Value
    if (autoRoll or autoSacrifice) and (tonumber(profile.blessingSlots) or 0) > 0 then
        Extra.markBlessingActionPending(Extra.BlessingActionTimeout)
        activateRemote:FireServer()
        Extra.setBlessingStatus("Rolling an available blessing slot...")
        return true
    end

    if not autoSacrifice then
        Extra.setBlessingStatus("Waiting for a free blessing slot. Auto Sacrifice is off.")
        return false
    end

    local gemEnergy = tonumber(profile.gemEnergy) or 0
    if gemEnergy < 10 then
        Extra.setBlessingStatus(string.format("Need 10 GE to sacrifice. Current GE: %s", tostring(gemEnergy)))
        Extra.BlessingRetryAfter = now + Extra.BlessingFailureRetrySeconds
        return false
    end

    local sacrifice = Extra.findSacrificialBlessing(profile)
    if sacrifice then
        Extra.markBlessingActionPending(Extra.BlessingActionTimeout)
        rerollRemote:FireServer(sacrifice.key)
        Extra.setBlessingStatus("Sacrificing " .. sacrifice.label .. " for a new roll.")
        Marker:SetAttribute("BlessingLastSacrifice", sacrifice.key)
        return true
    end

    Extra.setBlessingStatus("Waiting for a non-blacklisted owned blessing to sacrifice.")
    Extra.BlessingRetryAfter = now + Extra.BlessingFailureRetrySeconds
    return false
end

function Extra.autoBlessingEnabled()
    return (Toggles.ToggleAutoBlessing and Toggles.ToggleAutoBlessing.Value)
        or (Toggles.ToggleAutoBlessingSacrifice and Toggles.ToggleAutoBlessingSacrifice.Value)
        or (Toggles.ToggleAutoBlessingReroll and Toggles.ToggleAutoBlessingReroll.Value)
end

function Extra.startAutoBlessing()
    stopTask("AutoBlessing")
    Extra.connectBlessingEvents()
    Tasks.AutoBlessing = task.spawn(function()
        while Extra.autoBlessingEnabled() do
            Extra.autoBlessingStep()
            task.wait(0.03)
        end
    end)
end

function Extra.refreshAutoBlessing()
    if Extra.autoBlessingEnabled() then
        Extra.startAutoBlessing()
        return
    end

    stopTask("AutoBlessing")
    Extra.BlessingActionPending = false
    Extra.BlessingRetryAfter = 0
    Extra.setBlessingStatus("Auto Blessing is off.")
end

local function fireAbilitiesOnce()
    local remotes = getRemotes()
    if not remotes then
        notify("Abilities remotes folder was not found.")
        return 0
    end

    local fired = 0
    for _, ability in ipairs(AbilityRemotes) do
        local toggle = Toggles[ability.toggle]
        if not toggle or toggle.Value then
            local remote = remotes:FindFirstChild(ability.name)
            if remote then
                remote:FireServer()
                fired += 1
                task.wait(0.05)
            end
        end
    end

    Marker:SetAttribute("AbilitiesLastFired", fired)
    Marker:SetAttribute("AbilitiesLastFireTime", Workspace:GetServerTimeNow())
    return fired
end

local function fireSelectedPotionsOnce()
    local remote = getUsePotionRemote()
    if not remote then
        notify("UsePotion remote was not found.")
        return 0
    end

    local fired = 0
    for _, potion in ipairs(PotionOptions) do
        local toggle = Toggles[potion.toggle]
        local active = isBoostActive(potion.id)
        local requestReady = os.clock() >= (PotionRequestedUntil[potion.id] or 0)
        if toggle and toggle.Value and active == false and requestReady then
            remote:FireServer(potion.id)
            PotionRequestedUntil[potion.id] = os.clock() + 5
            fired += 1
            task.wait(0.05)
        end
    end

    Marker:SetAttribute("PotionsLastFired", fired)
    Marker:SetAttribute("PotionsLastFireTime", Workspace:GetServerTimeNow())
    return fired
end

local function startAutoPotionsLoop()
    stopTask("AutoPotions")

    Tasks.AutoPotions = task.spawn(function()
        while Toggles.ToggleAutoPotions and Toggles.ToggleAutoPotions.Value do
            fireSelectedPotionsOnce()
            task.wait(1)
        end
    end)
end

local function updateTotemMarker()
    local count = 0
    local firstId = ""
    for id in pairs(TotemIds) do
        count += 1
        if firstId == "" then
            firstId = id
        end
    end

    Marker:SetAttribute("KnownTotemCount", count)
    Marker:SetAttribute("FirstKnownTotemId", firstId)
end

local function rememberTotemId(id)
    if typeof(id) ~= "string" and typeof(id) ~= "number" then
        return false
    end

    id = tostring(id)
    if id == "" then
        return false
    end

    TotemIds[id] = true
    updateTotemMarker()
    return true
end

local function claimTotemId(id, inside)
    local remote = getRemote("TotemContactChanged", 10)
    if not remote then
        notify("TotemContactChanged remote was not found.")
        return false
    end

    if not rememberTotemId(id) then
        return false
    end

    remote:FireServer(tostring(id), inside ~= false)
    Marker:SetAttribute("TotemLastClaimId", tostring(id))
    Marker:SetAttribute("TotemLastClaimAt", Workspace:GetServerTimeNow())
    return true
end

local function claimKnownTotems()
    local claimed = 0
    for id in pairs(TotemIds) do
        if claimTotemId(id, true) then
            claimed += 1
            task.wait(0.05)
        end
    end

    Marker:SetAttribute("TotemLastClaimCount", claimed)
    return claimed
end

local function connectTotemEvents()
    local spawned = getRemote("TotemSpawned", 10)
    if spawned and not Connections.TotemSpawned then
        Connections.TotemSpawned = spawned.OnClientEvent:Connect(function(id, position, duration)
            local remembered = rememberTotemId(id)
            if Extra.handleBuffComboTotemSpawn then
                Extra.handleBuffComboTotemSpawn(id, position, duration)
            end
            if remembered and Toggles.ToggleAutoTotemContact and Toggles.ToggleAutoTotemContact.Value then
                task.defer(claimTotemId, id, true)
            end
        end)
    end

    local cleared = getRemote("TotemCleared", 10)
    if cleared and not Connections.TotemCleared then
        Connections.TotemCleared = cleared.OnClientEvent:Connect(function(id)
            if typeof(id) == "string" or typeof(id) == "number" then
                local key = tostring(id)
                TotemIds[key] = nil
                if Extra.BuffComboFreshTotemId == key then
                    Extra.BuffComboFreshTotemId = nil
                    Extra.BuffComboFreshTotemExpiresAt = 0
                end
                updateTotemMarker()
            end
        end)
    end
end

local function startAutoTotemContact()
    connectTotemEvents()
    claimKnownTotems()
end

function Extra.setBuffComboStatus(message)
    local text = tostring(message)
    Marker:SetAttribute("BuffComboStatus", text)
    Marker:SetAttribute("BuffComboMidasCount", Extra.AutoMidasGoldCount)
    Marker:SetAttribute("BuffComboMidasCountSource", Extra.AutoMidasGoldCountSource or "event")
    Marker:SetAttribute("BuffComboHasHeldGoldBar", Extra.BuffComboHeldGoldBar ~= nil)

    if Extra.BuffComboStatusLabel then
        pcall(function()
            Extra.BuffComboStatusLabel:SetText(text)
        end)
    end
end

function Extra.buffComboEnabled()
    return Toggles.ToggleBuffCombo and Toggles.ToggleBuffCombo.Value or false
end

function Extra.getBuffComboHoldCount()
    return math.clamp(math.floor(getNumberOption("BuffComboHoldMidasCount", 9)), 1, 9)
end

function Extra.getSelectedComboPotions()
    local option = Options.BuffComboPotion
    local selection = option and option.Value
    local selected = {}

    for _, potion in ipairs(Extra.ComboPotionOptions) do
        if multiSelectionContains(selection, potion.label) then
            selected[#selected + 1] = potion
        end
    end

    if #selected == 0 then
        selected[#selected + 1] = Extra.ComboPotionByLabel["Godly Potion"] or Extra.ComboPotionOptions[1]
    end

    return selected
end

function Extra.getBuffComboPotion()
    return Extra.getSelectedComboPotions()[1]
end

function Extra.getCrateController()
    local now = os.clock()
    if Extra.CrateController and now - (Extra.CrateControllerCheckedAt or 0) < 30 then
        return Extra.CrateController
    end
    if Extra.CrateControllerFailedAt and now - Extra.CrateControllerFailedAt < 5 then
        return nil
    end

    Extra.CrateControllerCheckedAt = now
    local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
    local client = playerScripts and playerScripts:FindFirstChild("Client")
    local controllers = client and client:FindFirstChild("Controllers")
    local module = controllers and controllers:FindFirstChild("CrateController")
    if not (module and module:IsA("ModuleScript")) then
        Extra.CrateControllerFailedAt = now
        return nil
    end

    local ok, controller = pcall(require, module)
    if ok and typeof(controller) == "table" then
        Extra.CrateController = controller
        Extra.CrateControllerFailedAt = nil
        return controller
    end

    Extra.CrateControllerFailedAt = now
    Marker:SetAttribute("BuffComboCrateRequireError", tostring(controller))
    return nil
end

function Extra.findClaimableCratePrompt()
    local directNames = { "GoldenSlimeCrate", "SlimeCrate" }
    for _, name in ipairs(directNames) do
        local crate = Workspace:FindFirstChild(name)
        local prompt = crate and crate:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt and prompt.Enabled then
            return prompt
        end
    end

    for _, child in ipairs(Workspace:GetChildren()) do
        local lower = child.Name:lower()
        if lower:find("crate", 1, true) then
            local prompt = child:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt and prompt.Enabled then
                return prompt
            end
        end
    end

    return nil
end

function Extra.clearLocalCrateVisuals()
    for _, child in ipairs(Workspace:GetChildren()) do
        local lower = child.Name:lower()
        if lower == "slimecrate" or lower == "goldenslimecrate"
            or (lower:find("crate", 1, true) and child:FindFirstChild("MainCrate", true)) then
            pcall(function()
                child:Destroy()
            end)
        end
    end
end

function Extra.getCrateReadiness()
    local boostActive = Extra.getCrateBoostActive and Extra.getCrateBoostActive() == true

    local sinceClaim = os.clock() - (Extra.BuffComboLastCrateClaimAt or 0)
    if Extra.BuffComboLastCrateClaimAt > 0 and sinceClaim < 1000 then
        local message = "Crate remote cooldown: " .. tostring(math.ceil(1000 - sinceClaim)) .. "s"
        if boostActive then
            return true, "Crate boost active; " .. message, true, false
        end
        return false, message, false, false
    end

    local controller = Extra.getCrateController()
    if controller and typeof(controller.getNextSpawnTime) == "function" then
        local ok, nextSpawn = pcall(controller.getNextSpawnTime)
        if ok and typeof(nextSpawn) == "number" then
            local remaining = math.max(0, math.ceil(nextSpawn - Workspace:GetServerTimeNow()))
            if remaining <= 0 then
                return true, "Crate timer elapsed; remote check allowed.", boostActive, true
            end

            local status = "Waiting for crate timer: " .. tostring(remaining) .. "s"
            if boostActive then
                return true, "Crate boost active; " .. status, true, false
            end
            return false, status, false, false
        end
    end

    if Toggles.ToggleBuffComboTrustClientCrate and Toggles.ToggleBuffComboTrustClientCrate.Value then
        local prompt = Extra.findClaimableCratePrompt()
        if prompt then
            return true, "Client crate prompt trusted.", boostActive, true
        end

        if controller and typeof(controller.isCrateActive) == "function" then
            local ok, active = pcall(controller.isCrateActive)
            if ok and active == true then
                return true, "Client crate controller trusted.", boostActive, true
            end
        end
    end

    if boostActive then
        return true, "Crate boost already active; client crate visual ignored.", true, false
    end

    return false, "Waiting for crate boost or server timer. Client crate visual ignored.", false, false
end

function Extra.getTotemBoostActive()
    local profile = getProfileData()
    local boosts = profile and profile.boosts
    if typeof(boosts) == "table" then
        applyBoostState(boosts)
    else
        ensureBoostState()
    end

    local value = ActiveBoosts.totem
    if typeof(value) == "number" then
        return value > 0
    end

    return BoostStateReady and false or nil
end

function Extra.workspaceTotemExists()
    local totem = Workspace:FindFirstChild("Totem")
    return totem ~= nil, totem
end

function Extra.touchWorkspaceTotem()
    local _, totem = Extra.workspaceTotemExists()
    local root = getRoot()
    if not (totem and root and typeof(firetouchinterest) == "function") then
        return false
    end

    local hitbox = totem:FindFirstChild("TotemHitbox", true) or totem:FindFirstChild("TotemArea", true)
    if not (hitbox and hitbox:IsA("BasePart")) then
        return false
    end

    pcall(firetouchinterest, root, hitbox, 0)
    task.wait(0.05)
    pcall(firetouchinterest, root, hitbox, 1)
    return true
end

function Extra.hasKnownTotem()
    if Extra.getTotemBoostActive() == true then
        return true, "active"
    end

    local hasWorkspaceTotem = Extra.workspaceTotemExists()
    if hasWorkspaceTotem then
        for id in pairs(TotemIds) do
            return true, id
        end
        return true, "workspace"
    end

    if Toggles.ToggleBuffComboFreshTotem and Toggles.ToggleBuffComboFreshTotem.Value then
        if Extra.BuffComboFreshTotemId then
            local expiresAt = tonumber(Extra.BuffComboFreshTotemExpiresAt) or 0
            if expiresAt > 0 and Workspace:GetServerTimeNow() >= expiresAt then
                Extra.BuffComboFreshTotemId = nil
                Extra.BuffComboFreshTotemExpiresAt = 0
                Marker:SetAttribute("BuffComboFreshTotemId", "")
                Marker:SetAttribute("BuffComboFreshTotemExpiresAt", 0)
                return false, nil
            end
            return true, Extra.BuffComboFreshTotemId
        end
        return false, nil
    end

    for id in pairs(TotemIds) do
        return true, id
    end
    return false, nil
end

function Extra.handleBuffComboTotemSpawn(id, position, duration)
    if not Extra.buffComboEnabled() then
        return
    end

    if typeof(id) ~= "string" and typeof(id) ~= "number" then
        return
    end

    id = tostring(id)
    if Extra.BuffComboIgnoredTotems and Extra.BuffComboIgnoredTotems[id] then
        return
    end

    local durationSeconds = tonumber(duration)
    local expiresAt = 0
    if durationSeconds then
        expiresAt = Workspace:GetServerTimeNow() + math.max(0, durationSeconds)
    end

    Extra.BuffComboFreshTotemId = id
    Extra.BuffComboFreshTotemExpiresAt = expiresAt
    Marker:SetAttribute("BuffComboFreshTotemId", id)
    Marker:SetAttribute("BuffComboFreshTotemExpiresAt", expiresAt)
    if durationSeconds then
        Extra.setBuffComboStatus("Fresh totem ready: " .. id .. " for "
            .. tostring(math.ceil(math.max(0, durationSeconds))) .. "s.")
    else
        Extra.setBuffComboStatus("Fresh totem ready: " .. id .. ".")
    end
end

function Extra.boostActiveText(boostIds, positiveValue)
    if typeof(boostIds) == "string" then
        boostIds = { boostIds }
    end

    local sawUnknown = false
    local profile = getProfileData()
    local boosts = profile and profile.boosts
    if typeof(boosts) == "table" then
        applyBoostState(boosts)
    end

    for _, boostId in ipairs(boostIds) do
        if positiveValue and typeof(ActiveBoosts[boostId]) == "number" and ActiveBoosts[boostId] > 0 then
            return "active"
        end

        local active, remaining = Extra.getBoostRemainingSeconds(boostId)
        if active == true then
            return "active" .. Extra.formatShortSeconds(remaining)
        end
        if active == nil then
            sawUnknown = true
        end
    end

    return sawUnknown and "unknown" or "false"
end

function Extra.getCrateBoostActive()
    local sawUnknown = false
    for _, boostId in ipairs({ "goldenCrateDrop", "crateDrop" }) do
        local active = isBoostActive(boostId)
        if active == true then
            return true
        end
        if active == nil then
            sawUnknown = true
        end
    end

    return sawUnknown and nil or false
end

function Extra.profileCurrencyAmount(currency)
    local profile = getProfileData()
    if typeof(profile) ~= "table" then
        return nil
    end

    local keys = {
        tostring(currency),
        tostring(currency):upper(),
        tostring(currency):lower(),
    }

    for _, key in ipairs(keys) do
        local value = tonumber(profile[key])
        if value ~= nil then
            return value
        end
    end

    for _, containerName in ipairs({ "currencies", "currency", "wallet" }) do
        local container = profile[containerName]
        if typeof(container) == "table" then
            for _, key in ipairs(keys) do
                local value = tonumber(container[key])
                if value ~= nil then
                    return value
                end
            end
        end
    end

    return nil
end

function Extra.potionShouldUse(potion)
    local active, remaining = Extra.getBoostRemainingSeconds(potion.id)
    if active == nil then
        return nil, "Waiting for boost state."
    end

    if active == true then
        local threshold = tonumber(potion.skipIfRemainingAbove)
        if threshold and typeof(remaining) == "number" and remaining <= threshold then
            return true, potion.label .. " is under refresh threshold."
        end

        if threshold then
            return false, potion.label .. " active" .. Extra.formatShortSeconds(remaining) .. "."
        end

        return false, potion.label .. " already active."
    end

    return true, potion.label .. " is not active."
end

function Extra.checkComboPotionBudget(potions)
    local profile = getProfileData()
    if typeof(profile) ~= "table" then
        return false, "Waiting for profile before buying combo potions."
    end

    local needed = {}
    for _, potion in ipairs(potions) do
        local shouldUse, reason = Extra.potionShouldUse(potion)
        if shouldUse == nil then
            return false, reason
        end

        local owned = tonumber(profile[potion.inventory]) or 0
        if shouldUse and owned <= 0 then
            local currency = tostring(potion.costCurrency or "sp")
            needed[currency] = (needed[currency] or 0) + (tonumber(potion.costAmount) or 0)
        end
    end

    for currency, totalCost in pairs(needed) do
        local balance = Extra.profileCurrencyAmount(currency)
        if balance == nil then
            return false, "Waiting for " .. tostring(currency):upper() .. " balance before buying combo potions."
        end
        if balance < totalCost then
            return false, "Need " .. tostring(totalCost) .. " " .. tostring(currency):upper()
                .. " for selected potions; have " .. tostring(balance) .. "."
        end
    end

    return true, "Potion budget ready."
end

function Extra.boolStatus(value)
    if value == nil then
        return "unknown"
    end
    return value and "true" or "false"
end

function Extra.compactDebugValue(value, depth)
    depth = depth or 0
    local valueType = typeof(value)

    if valueType == "number" or valueType == "string" or valueType == "boolean" then
        return tostring(value)
    end
    if valueType == "Vector3" or valueType == "CFrame" then
        return tostring(value)
    end
    if valueType ~= "table" then
        return valueType
    end
    if depth >= 2 then
        return "table"
    end

    local parts = {}
    local count = 0
    for key, nested in pairs(value) do
        count += 1
        if count > 12 then
            parts[#parts + 1] = "..."
            break
        end
        parts[#parts + 1] = tostring(key) .. "=" .. Extra.compactDebugValue(nested, depth + 1)
    end

    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

function Extra.profileDebugMatches(patterns)
    local profile = getProfileData()
    if typeof(profile) ~= "table" then
        return "profile=nil"
    end

    local lines = {}
    local function visit(path, value, depth)
        if depth > 4 then
            return
        end

        local lowerPath = tostring(path):lower()
        for _, pattern in ipairs(patterns) do
            if lowerPath:find(pattern, 1, true) then
                lines[#lines + 1] = tostring(path) .. " = " .. Extra.compactDebugValue(value, 0)
                break
            end
        end

        if typeof(value) == "table" then
            for key, nested in pairs(value) do
                visit(path .. "." .. tostring(key), nested, depth + 1)
            end
        end
    end

    visit("profile", profile, 0)
    table.sort(lines)
    if #lines == 0 then
        return "no profile keys matched"
    end
    return table.concat(lines, "\n")
end

function Extra.printBuffComboDebug()
    ensureBoostState()
    Extra.refreshAutoMidasBoostState()

    local crateReady, crateStatus, crateAlreadyBoosted, crateClaimable = Extra.getCrateReadiness()
    local totemReady, totemId = Extra.hasKnownTotem()
    local lines = {
        "[slimeinc debug] Buff combo state",
        "version=" .. tostring(Extra.Version),
        "midasBoost=" .. tostring(isBoostActive("midasBob")),
        "midasEventCount=" .. tostring(Extra.AutoMidasGoldCount)
            .. " source=" .. tostring(Extra.AutoMidasGoldCountSource),
        "heldGoldBar=" .. Extra.compactDebugValue(Extra.BuffComboHeldGoldBar, 0),
        "totemReady=" .. tostring(totemReady) .. " id=" .. tostring(totemId),
        "totemBoost=" .. tostring(Extra.getTotemBoostActive()),
        "crateReady=" .. tostring(crateReady) .. " alreadyBoosted=" .. tostring(crateAlreadyBoosted)
            .. " claimable=" .. tostring(crateClaimable),
        "crateStatus=" .. tostring(crateStatus),
        "crateBoost=" .. tostring(Extra.getCrateBoostActive()),
        "boosts=" .. Extra.compactDebugValue(ActiveBoosts, 0),
        "profile matches:",
        Extra.profileDebugMatches({ "midas", "gold", "bar", "bob", "crate", "totem" }),
    }
    local text = table.concat(lines, "\n")
    print(text)
    Marker:SetAttribute("BuffComboDebug", text:sub(1, 4096))
    return text
end

function Extra.updateBuffComboInfo()
    if not Extra.BuffComboInfoLabel then
        return
    end

    if not Extra.refreshAutoMidasBoostState() then
        Extra.syncAutoMidasCountFromTag()
    end
    local midasCount = Extra.AutoMidasGoldCount or 0
    local midasSource = tostring(Extra.AutoMidasGoldCountSource or "event")

    local totemReady, totemId = Extra.hasKnownTotem()
    local crateReady, crateStatus, crateAlreadyBoosted = Extra.getCrateReadiness()
    local potionParts = {}
    for _, potion in ipairs(Extra.getSelectedComboPotions()) do
        potionParts[#potionParts + 1] = potion.label .. "=" .. Extra.boostActiveText(potion.id)
    end
    local lines = {
        "Midas boost: " .. Extra.boostActiveText("midasBob"),
        "Midas bar: " .. tostring(math.clamp(math.floor(tonumber(midasCount) or 0), 0, 10))
            .. "/10 (" .. midasSource .. ")",
        "Totem: " .. Extra.boolStatus(totemReady)
            .. (totemId and totemId ~= "active" and (" [" .. tostring(totemId) .. "]") or ""),
        "Totem boost: " .. Extra.boostActiveText("totem", true),
        "Crate boost: " .. Extra.boostActiveText({ "goldenCrateDrop", "crateDrop" }),
        "Crate available: " .. Extra.boolStatus(crateReady),
        "Crate status: " .. tostring(crateStatus),
        "Potions: " .. table.concat(potionParts, ", "),
    }
    local text = table.concat(lines, "\n")

    Marker:SetAttribute("BuffComboInfo", text)
    pcall(function()
        Extra.BuffComboInfoLabel:SetText(text)
    end)
end

function Extra.startBuffComboInfoLoop()
    stopTask("BuffComboInfo")
    Tasks.BuffComboInfo = task.spawn(function()
        while Marker:GetAttribute("Session") == Session do
            Extra.updateBuffComboInfo()
            task.wait(1)
        end
    end)
end

function Extra.purchaseComboPotionIfNeeded(potion)
    if not potion then
        return true, "No potion selected."
    end

    local shouldUse, useReason = Extra.potionShouldUse(potion)
    if shouldUse == nil then
        return false, useReason
    end
    if not shouldUse then
        return true, useReason, false
    end

    local profile = getProfileData()
    local owned = profile and tonumber(profile[potion.inventory]) or nil
    local shouldBuy = Toggles.ToggleBuffComboBuyPotion and Toggles.ToggleBuffComboBuyPotion.Value
    if (owned == nil or owned <= 0) and shouldBuy then
        local currency = tostring(potion.costCurrency or "sp")
        local cost = tonumber(potion.costAmount) or 0
        local balance = Extra.profileCurrencyAmount(currency)
        if balance == nil then
            return false, "Waiting for " .. currency:upper() .. " balance before buying " .. potion.label .. "."
        end
        if balance < cost then
            return false, "Need " .. tostring(cost) .. " " .. currency:upper() .. " for "
                .. potion.label .. "; have " .. tostring(balance) .. "."
        end

        local purchase = getPurchaseShopItemRemote()
        if not purchase then
            return false, "PurchaseShopItem remote was not found."
        end

        purchase:FireServer(potion.id)
        Marker:SetAttribute("BuffComboLastPotionPurchase", potion.id)
        task.wait(0.25)
    elseif owned ~= nil and owned <= 0 then
        return false, "No " .. potion.label .. " owned."
    end

    return true, "Potion ready.", true
end

function Extra.useComboPotion()
    local potions = Extra.getSelectedComboPotions()
    if #potions == 0 then
        return true
    end

    local budgetOk, budgetReason = Extra.checkComboPotionBudget(potions)
    if not budgetOk then
        Extra.setBuffComboStatus(budgetReason)
        return false
    end

    local remote = getUsePotionRemote()
    if not remote then
        Extra.setBuffComboStatus("UsePotion remote was not found.")
        return false
    end

    local used = {}
    local skipped = {}
    for _, potion in ipairs(potions) do
        local ok, reason, shouldFire = Extra.purchaseComboPotionIfNeeded(potion)
        if not ok then
            Extra.setBuffComboStatus(reason)
            return false
        end

        if shouldFire then
            remote:FireServer(potion.id)
            PotionRequestedUntil[potion.id] = os.clock() + 5
            used[#used + 1] = potion.id
            task.wait(0.1)
        else
            skipped[#skipped + 1] = potion.id .. ":" .. tostring(reason)
        end
    end

    Marker:SetAttribute("BuffComboLastPotionUsed", table.concat(used, ","))
    Marker:SetAttribute("BuffComboLastPotionSkipped", table.concat(skipped, " | "))
    return true
end

function Extra.handleBuffComboGoldBar(id, position)
    if not Extra.buffComboEnabled() then
        return false
    end

    if Extra.refreshAutoMidasBoostState() then
        Extra.setBuffComboStatus("Midas boost is active; combo count held at 0/10.")
        return true
    end

    local holdCount = Extra.getBuffComboHoldCount()
    local key = tostring(id)

    if Extra.AutoMidasGoldCount < holdCount then
        task.spawn(function()
            if collectMidasGoldBar(id, position) then
                local count = Extra.noteMidasGoldCollected("combo")
                Extra.setBuffComboStatus("Collected Midas bar. Combo count: "
                    .. tostring(count) .. "/" .. tostring(holdCount) .. ".")
            end
        end)
        return true
    end

    Extra.BuffComboHeldGoldBar = {
        id = id,
        position = position,
        receivedAt = os.clock(),
    }
    Marker:SetAttribute("BuffComboHeldGoldBarId", key)
    Extra.setBuffComboStatus("Holding final Midas bar " .. key .. " until crate + totem + potion are ready.")
    return true
end

function Extra.finishBuffCombo()
    local held = Extra.BuffComboHeldGoldBar
    if not held then
        Extra.setBuffComboStatus("Waiting for the final Midas bar to spawn.")
        return false
    end

    local crateReady, crateStatus, crateAlreadyBoosted, crateClaimable = Extra.getCrateReadiness()
    if not crateReady then
        Extra.setBuffComboStatus(crateStatus)
        return false
    end

    if Toggles.ToggleBuffComboRequireTotem and Toggles.ToggleBuffComboRequireTotem.Value then
        local hasTotem, totemId = Extra.hasKnownTotem()
        if not hasTotem then
            Extra.setBuffComboStatus(
                Toggles.ToggleBuffComboFreshTotem and Toggles.ToggleBuffComboFreshTotem.Value
                    and "Waiting for a fresh totem spawn."
                    or "Waiting for a totem spawn id."
            )
            return false
        end
        Extra.BuffComboTotemAlreadyActive = totemId == "active"
        Extra.BuffComboReadyTotemId = totemId
    end

    if crateClaimable then
        Extra.setBuffComboStatus("Claiming crate boost...")
        if fireCrateBoost("goldenCrate", 1, 0) < 1 then
            Extra.setBuffComboStatus("Crate claim failed.")
            return false
        end
        Extra.BuffComboLastCrateClaimAt = os.clock()
        Extra.clearLocalCrateVisuals()
        task.wait(0.15)
    elseif crateAlreadyBoosted then
        Extra.setBuffComboStatus("Using already-active crate boost.")
    else
        Extra.setBuffComboStatus(crateStatus)
        return false
    end

    if Toggles.ToggleBuffComboRequireTotem and Toggles.ToggleBuffComboRequireTotem.Value
        and not Extra.BuffComboTotemAlreadyActive then
        local claimed = 0
        if Extra.BuffComboReadyTotemId and Extra.BuffComboReadyTotemId ~= "active" then
            if Extra.BuffComboReadyTotemId == "workspace" then
                claimed = Extra.touchWorkspaceTotem() and 1 or 0
            else
                claimed = claimTotemId(Extra.BuffComboReadyTotemId, true) and 1 or 0
            end
        else
            claimed = claimKnownTotems()
        end
        Marker:SetAttribute("BuffComboTotemsClaimed", claimed)
        if claimed < 1 then
            Extra.setBuffComboStatus("Totem disappeared before claim.")
            return false
        end
    end

    Extra.setBuffComboStatus("Using combo potion...")
    if not Extra.useComboPotion() then
        return false
    end

    Extra.setBuffComboStatus("Collecting final Midas bar for x5 buff...")
    if collectMidasGoldBar(held.id, held.position) then
        Extra.BuffComboHeldGoldBar = nil
        Extra.noteMidasGoldCollected("combo-fired")
        Extra.setBuffComboStatus("Combo fired: crate + totem + potion + Midas.")
        task.defer(function()
            if Toggles.ToggleBuffCombo then
                Toggles.ToggleBuffCombo:SetValue(false)
            end
        end)
        return true
    end

    Extra.setBuffComboStatus("Final Midas bar collect failed; keeping it held.")
    return false
end

function Extra.startBuffCombo()
    stopTask("BuffCombo")
    connectMidasGoldEvents()
    connectTotemEvents()

    Extra.BuffComboHeldGoldBar = nil
    Extra.BuffComboTotemAlreadyActive = false
    Extra.BuffComboReadyTotemId = nil
    Extra.BuffComboFreshTotemId = nil
    Extra.BuffComboFreshTotemExpiresAt = 0
    Extra.BuffComboIgnoredTotems = {}
    for id in pairs(TotemIds) do
        Extra.BuffComboIgnoredTotems[tostring(id)] = true
    end
    Extra.BuffComboRunning = true
    Extra.setBuffComboStatus("Buff combo armed. Midas count " .. tostring(Extra.AutoMidasGoldCount) .. "/"
        .. tostring(Extra.getBuffComboHoldCount()) .. ".")

    Tasks.BuffCombo = task.spawn(function()
        while Extra.buffComboEnabled() do
            if Extra.refreshAutoMidasBoostState() then
                Extra.setBuffComboStatus("Midas boost is active; waiting with count at 0/10.")
            elseif Extra.AutoMidasGoldCount >= Extra.getBuffComboHoldCount() then
                Extra.finishBuffCombo()
            else
                Extra.setBuffComboStatus("Collecting Midas bars until "
                    .. tostring(Extra.getBuffComboHoldCount()) .. ". Current: "
                    .. tostring(Extra.AutoMidasGoldCount) .. " from "
                    .. tostring(Extra.AutoMidasGoldCountSource or "event") .. ".")
            end

            task.wait(1)
        end

        Extra.BuffComboRunning = false
    end)
end

function Extra.stopBuffCombo()
    stopTask("BuffCombo")
    Extra.BuffComboRunning = false
    Extra.setBuffComboStatus("Buff combo is off.")
end

local AmuletCountValues = { "1", "2", "3", "4" }
Extra.AmuletTypeValues = {
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
Extra.AmuletTypeAliases = {
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
    glitch = "CorruptedAmulet",
    glitchamulet = "CorruptedAmulet",
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
Extra.AmuletCombinedStatFields = {
    Slimes = { "slimesBonus", "slimeBonus", "slimeMultiplier", "slimesMultiplier" },
    Exp = { "expBonus", "expMultiplier", "xpBonus", "xpMultiplier" },
    Gems = { "gemsBonus", "gemBonus", "gemsMultiplier", "gemMultiplier" },
}
Extra.AmuletCustomComboSlots = {}
Extra.AmuletCustomComboSlotLimit = 6

local AmuletPreferredFields = {
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

local rollAmuletOnce
local pickLatestAmulet

local function setAmuletStatus(text, forceDisplay)
    LatestAmuletSummary = tostring(text or "No amulet roll yet.")

    local markerText = LatestAmuletSummary
    if #markerText > 1024 then
        markerText = markerText:sub(1, 1021) .. "..."
    end

    Marker:SetAttribute("AmuletLatestInfo", markerText)

    if AmuletStatusLabel then
        local now = os.clock()
        if not forceDisplay and now - Extra.AmuletStatusLastDisplayAt < 0.5 then
            return
        end

        Extra.AmuletStatusLastDisplayAt = now
        pcall(function()
            AmuletStatusLabel:SetText(LatestAmuletSummary)
        end)
    end
end

local function getSelectedAmuletCounts()
    local dropdown = Options.AmuletOptionCounts
    if not dropdown or typeof(dropdown.Value) ~= "table" then
        return {}
    end

    return dropdown.Value
end

local function hasSelectedAmuletCounts()
    for _, active in pairs(getSelectedAmuletCounts()) do
        if active then
            return true
        end
    end

    return false
end

local function isSelectedAmuletCount(count)
    return getSelectedAmuletCounts()[tostring(count)] == true
end

function Extra.normalizeAmuletTypeName(value)
    if value == nil then
        return nil
    end

    local compact = tostring(value):lower():gsub("%s+", ""):gsub("[^%w]", "")
    return Extra.AmuletTypeAliases[compact] or Extra.AmuletTypeAliases[compact:gsub("amulet$", "")]
end

function Extra.getSelectedAmuletTypes()
    local dropdown = Options.AmuletRequiredTypes
    if not dropdown or typeof(dropdown.Value) ~= "table" then
        return {}
    end

    local selected = {}
    for value, active in pairs(dropdown.Value) do
        if active then
            local amuletType = Extra.normalizeAmuletTypeName(value)
            if amuletType then
                selected[amuletType] = true
            end
        end
    end

    return selected
end

function Extra.hasSelectedAmuletTypes()
    for _, active in pairs(Extra.getSelectedAmuletTypes()) do
        if active then
            return true
        end
    end

    return false
end

function Extra.getAmuletComboFromDropdown(dropdownId)
    local dropdown = Options[dropdownId]
    if not dropdown or typeof(dropdown.Value) ~= "table" then
        return {}
    end

    local combo = {}
    for value, active in pairs(dropdown.Value) do
        if active then
            local amuletType = Extra.normalizeAmuletTypeName(value)
            if amuletType and not table.find(combo, amuletType) then
                combo[#combo + 1] = amuletType
            end
        end
    end

    return combo
end

function Extra.getSelectedAmuletCombos()
    local selected = {}
    for _, slot in pairs(Extra.AmuletCustomComboSlots) do
        if slot.Active then
            local combo = Extra.getAmuletComboFromDropdown(slot.DropdownId)
            if #combo > 0 then
                selected[#selected + 1] = combo
            end
        end
    end

    return selected
end

function Extra.hasSelectedAmuletCombos()
    return #Extra.getSelectedAmuletCombos() > 0
end

function Extra.shouldRequireSelectedAmuletType()
    return Toggles.ToggleRequireAmuletType
        and Toggles.ToggleRequireAmuletType.Value
        and (Extra.hasSelectedAmuletTypes() or Extra.hasSelectedAmuletCombos())
end

function Extra.getAmuletMinimumStats()
    return {
        Slimes = math.max(0, getNumberOption("AmuletMinCombinedSlimesInput", 0)),
        Exp = math.max(0, getNumberOption("AmuletMinCombinedExpInput", 0)),
        Gems = math.max(0, getNumberOption("AmuletMinCombinedGemsInput", 0)),
    }
end

function Extra.hasAmuletMinimumStats()
    for _, minimum in pairs(Extra.getAmuletMinimumStats()) do
        if minimum > 0 then
            return true
        end
    end

    return false
end

function Extra.shouldMatchAnyAmuletMinimumStat()
    return Toggles.ToggleAmuletAnyMinimumStat
        and Toggles.ToggleAmuletAnyMinimumStat.Value
end

function Extra.shouldMatchAmuletRuleGroupsWithOr()
    return Toggles.ToggleAmuletRulesUseOr
        and Toggles.ToggleAmuletRulesUseOr.Value
        and Extra.shouldRequireSelectedAmuletType()
        and Extra.hasAmuletMinimumStats()
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

local function appendAmuletField(parts, used, option, key, label)
    if used[key] then
        return false
    end

    local text = compactAmuletValue(option[key])
    if not text then
        return false
    end

    used[key] = true
    parts[#parts + 1] = tostring(label or key) .. "=" .. text
    return true
end

local function getOptionKeys(option)
    local keys = {}
    for key in pairs(option) do
        keys[#keys + 1] = key
    end

    table.sort(keys, function(left, right)
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

function Extra.optionMatchesSelectedAmuletType(option)
    local amuletType = Extra.normalizeAmuletTypeName(getAmuletType(option))
    if not amuletType then
        return false
    end

    return Extra.getSelectedAmuletTypes()[amuletType] == true
end

function Extra.getAmuletTypeIndex(options, keys)
    local present = {}
    local firstKey = {}

    for _, key in ipairs(keys) do
        local amuletType = Extra.normalizeAmuletTypeName(getAmuletType(options[key]))
        if amuletType then
            present[amuletType] = true
            firstKey[amuletType] = firstKey[amuletType] or key
        end
    end

    return present, firstKey
end

function Extra.matchAmuletCombos(options, keys)
    local combos = Extra.getSelectedAmuletCombos()
    if #combos == 0 then
        return true, nil
    end

    local present, firstKey = Extra.getAmuletTypeIndex(options, keys)
    for _, combo in ipairs(combos) do
        local matched = true
        local matchedKey = nil
        for _, amuletType in ipairs(combo) do
            if not present[amuletType] then
                matched = false
                break
            end
            matchedKey = matchedKey or firstKey[amuletType]
        end

        if matched then
            return true, matchedKey
        end
    end

    return false, nil
end

function Extra.matchSelectedAmuletTypes(options, keys)
    local selected = Extra.getSelectedAmuletTypes()
    local hasSelection = false
    for _ in pairs(selected) do
        hasSelection = true
        break
    end

    if not hasSelection then
        return true, nil
    end

    local present, firstKey = Extra.getAmuletTypeIndex(options, keys)
    if Toggles.ToggleRequireAllAmuletTypes and Toggles.ToggleRequireAllAmuletTypes.Value then
        local matchedKey = nil
        for amuletType in pairs(selected) do
            if not present[amuletType] then
                return false, nil
            end
            matchedKey = matchedKey or firstKey[amuletType]
        end

        return true, matchedKey
    end

    for amuletType in pairs(selected) do
        if present[amuletType] then
            return true, firstKey[amuletType]
        end
    end

    return false, nil
end

function Extra.matchAmuletTypeRules(options, keys)
    if not Extra.shouldRequireSelectedAmuletType() then
        return true, nil
    end

    if Extra.hasSelectedAmuletCombos() then
        local comboMatched, comboKey = Extra.matchAmuletCombos(options, keys)
        if comboMatched then
            return true, comboKey
        end

        return false, nil, "combo"
    end

    local typeMatched, typeKey = Extra.matchSelectedAmuletTypes(options, keys)
    if typeMatched then
        return true, typeKey
    end

    return false, nil, "type"
end

function Extra.getAmuletStatValue(option, statName)
    if typeof(option) ~= "table" then
        return 0
    end

    for _, field in ipairs(Extra.AmuletCombinedStatFields[statName] or {}) do
        local value = option[field]
        if typeof(value) == "number" then
            return value
        end
    end

    return 0
end

function Extra.getCombinedAmuletStats(options, keys)
    local combined = {
        Slimes = 0,
        Exp = 0,
        Gems = 0,
    }

    for _, key in ipairs(keys) do
        for statName in pairs(combined) do
            combined[statName] += Extra.getAmuletStatValue(options[key], statName)
        end
    end

    return combined
end

function Extra.formatAmuletNumber(value)
    local rounded = math.floor((tonumber(value) or 0) * 100 + 0.5) / 100
    if rounded == math.floor(rounded) then
        return tostring(math.floor(rounded))
    end

    return tostring(rounded):gsub("0+$", ""):gsub("%.$", "")
end

function Extra.matchAmuletMinimumStats(options, keys)
    local minimums = Extra.getAmuletMinimumStats()
    if not Extra.hasAmuletMinimumStats() then
        return true
    end

    local combined = Extra.getCombinedAmuletStats(options, keys)
    if Extra.shouldMatchAnyAmuletMinimumStat() then
        for statName, minimum in pairs(minimums) do
            if minimum > 0 and (combined[statName] or 0) >= minimum then
                return true
            end
        end

        return false, "value"
    end

    for statName, minimum in pairs(minimums) do
        if minimum > 0 and (combined[statName] or 0) < minimum then
            return false, "value"
        end
    end

    return true
end

function Extra.describeCombinedAmuletStats(options, keys)
    local combined = Extra.getCombinedAmuletStats(options, keys)
    return "Combined: Slimes +" .. Extra.formatAmuletNumber(combined.Slimes)
        .. " | Exp +" .. Extra.formatAmuletNumber(combined.Exp)
        .. " | Gems +" .. Extra.formatAmuletNumber(combined.Gems)
end

local function summarizeAmuletOption(option, index, matched)
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

    for _, key in ipairs(AmuletPreferredFields) do
        appendAmuletField(parts, used, option, key)
    end

    local added = 0
    for _, key in ipairs(getOptionKeys(option)) do
        if added >= 7 then
            break
        end

        if appendAmuletField(parts, used, option, key) then
            added += 1
        end
    end

    for _, key in ipairs(getOptionKeys(option)) do
        if added >= 10 then
            break
        end

        local nested = option[key]
        if typeof(nested) == "table" then
            for _, nestedKey in ipairs(getOptionKeys(nested)) do
                if added >= 10 then
                    break
                end

                local text = compactAmuletValue(nested[nestedKey])
                if text then
                    parts[#parts + 1] = tostring(key) .. "." .. tostring(nestedKey) .. "=" .. text
                    added += 1
                end
            end
        end
    end

    return table.concat(parts, " | ")
end

local function getOrderedAmuletOptionKeys(options)
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

local function findSelectedAmuletTarget(options)
    local keys = getOrderedAmuletOptionKeys(options)
    local count = #keys
    if isSelectedAmuletCount(count) then
        if Extra.shouldMatchAmuletRuleGroupsWithOr() then
            local typeMatched, targetIndex, typeMissReason = Extra.matchAmuletTypeRules(options, keys)
            local valueMatched, valueMissReason = Extra.matchAmuletMinimumStats(options, keys)
            if typeMatched or valueMatched then
                return count, targetIndex
            end

            if typeMissReason and valueMissReason then
                return nil, nil, "rules"
            end

            return nil, nil, typeMissReason or valueMissReason
        end

        local typeMatched, targetIndex, typeMissReason = Extra.matchAmuletTypeRules(options, keys)
        if not typeMatched then
            return nil, nil, typeMissReason
        end

        local valueMatched, valueMissReason = Extra.matchAmuletMinimumStats(options, keys)
        if not valueMatched then
            return nil, nil, valueMissReason
        end

        return count, targetIndex
    end

    return nil, nil
end

local function summarizeAmuletRoll(options, rollId, target, targetIndex, missReason)
    local lines = {}
    if target then
        lines[#lines + 1] = "Roll " .. tostring(rollId or "?") .. " hit selected count: " .. tostring(target) .. " option(s)."
    elseif missReason == "combo" then
        lines[#lines + 1] = "Roll " .. tostring(rollId or "?") .. " hit selected count, but missed required combo."
    elseif missReason == "type" then
        lines[#lines + 1] = "Roll " .. tostring(rollId or "?") .. " hit selected count, but missed required amulet type."
    elseif missReason == "value" then
        lines[#lines + 1] = "Roll " .. tostring(rollId or "?") .. " hit selected count, but missed minimum combined values."
    elseif missReason == "rules" then
        lines[#lines + 1] = "Roll " .. tostring(rollId or "?") .. " hit selected count, but missed combo/type and minimum values."
    else
        lines[#lines + 1] = "Roll " .. tostring(rollId or "?") .. " did not hit a selected option count."
    end

    if typeof(options) ~= "table" then
        lines[#lines + 1] = "Payload: " .. tostring(options)
        return table.concat(lines, "\n")
    end

    local count = 0
    local keys = getOrderedAmuletOptionKeys(options)
    lines[#lines + 1] = Extra.describeCombinedAmuletStats(options, keys)
    for _, key in ipairs(keys) do
        count += 1
        if count <= 4 then
            lines[#lines + 1] = summarizeAmuletOption(options[key], key, key == targetIndex)
        end
    end

    if count == 0 then
        lines[#lines + 1] = "No new options were sent."
    elseif count > 4 then
        lines[#lines + 1] = "+" .. tostring(count - 4) .. " more option(s)"
    end

    return table.concat(lines, "\n")
end

local function enableFastAmulets()
    if FastAmuletsRequested then
        return true
    end

    local remote = getRemote("UpdateSetting", 10)
    if not remote then
        return false
    end

    FastAmuletsRequested = true
    remote:FireServer("fastAmulets", true)
    Marker:SetAttribute("FastAmuletsRequested", true)
    return true
end

pickLatestAmulet = function(choice, quiet)
    if Marker:GetAttribute("Session") ~= Session then
        return false
    end

    enableFastAmulets()
    local remote = getRemote("PickAmulet", 10)
    if not remote then
        notify("PickAmulet remote was not found.")
        return false
    end

    if LatestAmuletRollId == nil then
        if not quiet then
            notify("No amulet roll id yet.")
        end
        return false
    end

    if not AmuletChoicePending or AmuletPickPending then
        if not quiet then
            notify("No unhandled amulet choice is ready.")
        end
        return false
    end

    if quiet and choice == "OLD" and (Extra.AmuletTargetLocked or LatestAmuletTarget ~= nil) then
        return false
    end

    AmuletPickPending = true
    local pickedRollId = LatestAmuletRollId
    remote:FireServer(choice, LatestAmuletRollId)
    Marker:SetAttribute("AmuletLastPicked", choice)
    Marker:SetAttribute("AmuletLastPickRollId", tostring(LatestAmuletRollId))
    Marker:SetAttribute("AmuletLastPickAt", Workspace:GetServerTimeNow())

    if not quiet then
        notify("Amulet pick fired: " .. tostring(choice))
    end

    task.delay(Extra.AmuletPickTimeout, function()
        if Marker:GetAttribute("Session") ~= Session then
            return
        end

        if LatestAmuletRollId ~= pickedRollId then
            return
        end

        AmuletPickPending = false
        if choice == "OLD" and not Extra.AmuletTargetLocked and LatestAmuletTarget == nil then
            Extra.AmuletNextRollAt = os.clock() + Extra.AmuletNextRollDelay
            if Extra.shouldSuppressAmuletRollVisuals() then
                Extra.queueAmuletRollVisualCleanup()
            elseif not Extra.autoAmuletRollEnabled() then
                setAmuletStatus(LatestAmuletSummary, true)
            end
        end
    end)

    return true
end

local function connectAmuletEvents()
    Extra.refreshAmuletVisualSuppression()

    local rollResult = getRemote("AmuletRollResult", 10)
    if not rollResult then
        notify("AmuletRollResult remote was not found.")
        return false
    end

    Extra.AmuletRollResultHandler = Extra.AmuletRollResultHandler or function(options, rollId)
        if Marker:GetAttribute("Session") ~= Session then
            disconnect("AmuletRollResult")
            return
        end

        AmuletRollPending = false
        AmuletChoicePending = true
        AmuletPickPending = false
        LatestAmuletRollId = rollId

        local target, targetIndex, missReason = findSelectedAmuletTarget(options)
        LatestAmuletTarget = target
        LatestAmuletTargetIndex = targetIndex
        Extra.AmuletTargetLocked = target ~= nil
        setAmuletStatus(
            summarizeAmuletRoll(options, rollId, target, targetIndex, missReason),
            true
        )

        Marker:SetAttribute("AmuletLastRollId", tostring(rollId))
        Marker:SetAttribute("AmuletLastTarget", target or "")
        Marker:SetAttribute("AmuletLastTargetIndex", targetIndex and tostring(targetIndex) or "")
        Marker:SetAttribute("AmuletLastResultAt", Workspace:GetServerTimeNow())

        if target then
            if Extra.amuletVisualSuppressionEnabled() then
                Extra.showAmuletRollVisualsForTarget(options, rollId)
            end

            if Toggles.ToggleAutoAmuletRoll and Toggles.ToggleAutoAmuletRoll.Value then
                Toggles.ToggleAutoAmuletRoll:SetValue(false)
            end

            notify("Amulet roll hit " .. tostring(target) .. " option(s). Choose Select New or Keep Old.")
            return
        end

        if Extra.shouldSuppressAmuletRollVisuals() then
            Extra.queueAmuletRollVisualCleanup()
        end
    end

    if not Connections.AmuletRollResult then
        Connections.AmuletRollResult = rollResult.OnClientEvent:Connect(Extra.AmuletRollResultHandler)
    end

    local pickResult = getRemote("AmuletPickResult", 2)
    Extra.AmuletPickResultHandler = Extra.AmuletPickResultHandler or function(choice, rollId, ok, message)
        if Marker:GetAttribute("Session") ~= Session then
            disconnect("AmuletPickResult")
            return
        end

        if rollId == LatestAmuletRollId then
            AmuletPickPending = false
            if ok == true then
                AmuletChoicePending = false
                if choice == "OLD" then
                    Extra.AmuletNextRollAt = os.clock() + Extra.AmuletNextRollDelay
                end
            else
                AmuletChoicePending = false
                Extra.AmuletTargetLocked = false
                LatestAmuletTarget = nil
                Extra.AmuletNextRollAt = os.clock() + 0.35
                setAmuletStatus("Amulet pick was rejected. Retrying on the next roll.", true)
            end
        end

        if Extra.shouldSuppressAmuletRollVisuals() then
            Extra.queueAmuletRollVisualCleanup()
        end

        Marker:SetAttribute("AmuletLastPickResult", tostring(ok))
        Marker:SetAttribute("AmuletLastPickMessage", tostring(message or ""))
        Marker:SetAttribute("AmuletLastPickChoice", tostring(choice or ""))
    end

    if pickResult and not Connections.AmuletPickResult then
        Connections.AmuletPickResult = pickResult.OnClientEvent:Connect(Extra.AmuletPickResultHandler)
    end

    return true
end

rollAmuletOnce = function()
    local now = os.clock()
    if AmuletRollPending and now - (Extra.AmuletRollPendingAt or 0) > 3 then
        AmuletRollPending = false
        setAmuletStatus("Amulet roll timed out. Retrying soon.", true)
    end

    if AmuletChoicePending then
        if Extra.autoAmuletRollEnabled()
            and not AmuletPickPending
            and not Extra.AmuletTargetLocked
            and LatestAmuletTarget == nil then
            pickLatestAmulet("OLD", true)
        end
        return false
    end

    if AmuletRollPending then
        return false
    end

    if now < (Extra.AmuletNextRollAt or 0) then
        return false
    end

    enableFastAmulets()
    connectAmuletEvents()

    local remote = getRemote("RollAmulet", 10)
    if not remote then
        notify("RollAmulet remote was not found.")
        return false
    end

    AmuletRollPending = true
    Extra.AmuletRollPendingAt = os.clock()
    local rollStartedAt = Extra.AmuletRollPendingAt
    remote:FireServer()
    Marker:SetAttribute("AmuletRolledAt", Workspace:GetServerTimeNow())
    if not Extra.autoAmuletRollEnabled() or LatestAmuletRollId == nil then
        setAmuletStatus("Rolling amulet...", true)
    else
        Marker:SetAttribute("AmuletRollState", "rolling")
    end

    task.delay(3, function()
        if AmuletRollPending and Extra.AmuletRollPendingAt == rollStartedAt then
            AmuletRollPending = false
            setAmuletStatus("Amulet roll timed out. Retrying soon.", true)
        end
    end)

    return true
end

local function startAutoAmuletRoll()
    stopTask("AutoAmuletRoll")
    enableFastAmulets()

    if not hasSelectedAmuletCounts() then
        notify("Select at least one amulet option count first.")
        if Toggles.ToggleAutoAmuletRoll then
            Toggles.ToggleAutoAmuletRoll:SetValue(false)
        end
        return
    end

    if Toggles.ToggleRequireAmuletType
        and Toggles.ToggleRequireAmuletType.Value
        and not (Extra.hasSelectedAmuletTypes() or Extra.hasSelectedAmuletCombos()) then
        notify("Select at least one required amulet type or combo first.")
        Toggles.ToggleAutoAmuletRoll:SetValue(false)
        return
    end

    connectAmuletEvents()
    Tasks.AutoAmuletRoll = task.spawn(function()
        while Toggles.ToggleAutoAmuletRoll and Toggles.ToggleAutoAmuletRoll.Value do
            rollAmuletOnce()
            task.wait(math.max(0.03, getNumberOption("AutoAmuletRollDelayMs", 50) / 1000))
        end
    end)
end

function Extra.setCSlimeStatus(message)
    local text = tostring(message)
    Marker:SetAttribute("CSlimeStatus", text)
    if Extra.CSlimeStatusLabel then
        pcall(function()
            Extra.CSlimeStatusLabel:SetText(text)
        end)
    end
end

function Extra.getCSlimeBaseplateCFrame()
    local world = Workspace:FindFirstChild("World")
    local zones = world and world:FindFirstChild("Zones")
    local level = zones and zones:FindFirstChild("Lvl150")
    local baseplate = level and level:FindFirstChild("CorruptedBaseplate")
    if not baseplate then
        return nil
    end

    if baseplate:IsA("BasePart") then
        return baseplate.CFrame * CFrame.new(0, (baseplate.Size.Y / 2) + 2.5, 0)
    end

    local part = baseplate:FindFirstChildWhichIsA("BasePart", true)
    if part then
        return part.CFrame * CFrame.new(0, (part.Size.Y / 2) + 2.5, 0)
    end
    return Extra.instanceCFrame(baseplate)
end

function Extra.startAutoCSlime()
    stopTask("AutoCSlime")
    disconnect("CSlimeSpawn")
    Extra.CSlimeMoveCFrame = nil
    Extra.setCSlimeStatus("Finding the Level 150 corrupted baseplate...")

    Tasks.AutoCSlime = task.spawn(function()
        while Toggles.ToggleAutoCSlime and Toggles.ToggleAutoCSlime.Value do
            local target = Extra.getCSlimeBaseplateCFrame()
            if not target then
                Extra.CSlimeMoveCFrame = nil
                Extra.setCSlimeStatus("Waiting for World.Zones.Lvl150.CorruptedBaseplate...")
                task.wait(0.5)
                continue
            end

            Extra.CSlimeMoveCFrame = target
            local root = getRoot()
            if root then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                root.CFrame = target
            end

            Extra.setCSlimeStatus("Touching the corrupted baseplate...")
            task.wait(0.6)
            Extra.CSlimeMoveCFrame = nil
            Marker:SetAttribute("CSlimeLastCollectAt", Workspace:GetServerTimeNow())

            local interval = math.max(1, getNumberOption("CSlimeCollectDelaySeconds", 10))
            Extra.setCSlimeStatus(string.format("Baseplate visited. Next visit in %d seconds.", interval))
            task.wait(interval)
        end

        Extra.CSlimeMoveCFrame = nil
    end)
end

function Extra.stopAutoCSlime()
    stopTask("AutoCSlime")
    disconnect("CSlimeSpawn")
    Extra.CSlimeMoveCFrame = nil
    Extra.setCSlimeStatus("Auto CS slime is off.")
end

local fireCleanbotRoll

function Extra.setCleanbotStatus(message)
    local text = tostring(message)
    Marker:SetAttribute("CleanbotStatus", text)
    if Extra.CleanbotStatusLabel then
        pcall(function()
            Extra.CleanbotStatusLabel:SetText(text)
        end)
    end
end

function Extra.cleanbotAutoRollEnabled()
    return Toggles.ToggleAutoCleanbotRoll and Toggles.ToggleAutoCleanbotRoll.Value or false
end

function Extra.equipCleanbot(cleanbot)
    local remote = getRemote("EquipRoomba", 10)
    if not remote then
        return false
    end

    remote:FireServer(cleanbot)
    Marker:SetAttribute("CleanbotLastEquipRequest", tostring(cleanbot))
    return true
end

local function startCleanbotResultListener()
    if Connections.CleanbotResult then
        return true
    end

    local remote = getRoombaRollResultRemote()
    if not remote then
        notify("RoombaRollResult remote was not found.")
        return false
    end

    Connections.CleanbotResult = remote.OnClientEvent:Connect(function(cleanbot, isNew)
        Extra.CleanbotRollPending = false
        Marker:SetAttribute("CleanbotLastResult", tostring(cleanbot))
        Marker:SetAttribute("CleanbotLastWasNew", isNew == true)
        Marker:SetAttribute("CleanbotLastResultTime", Workspace:GetServerTimeNow())

        local autoBest = Toggles.ToggleAutoBestCleanbot and Toggles.ToggleAutoBestCleanbot.Value
        if autoBest and cleanbot == "HugeRoomba" then
            Extra.BestCleanbotRank = 2
            Extra.equipCleanbot("HugeRoomba")
            Extra.setCleanbotStatus("Huge Cleanbot found and equipped.")
        elseif autoBest and cleanbot == "VoidRoomba" then
            local profile = getProfileData()
            local owned = profile and profile.roombas
            local ownsHuge = Extra.BestCleanbotRank == 2
                or (typeof(owned) == "table" and owned.hugeRoomba == true)
            if not ownsHuge then
                Extra.BestCleanbotRank = 1
                Extra.equipCleanbot("VoidRoomba")
                Extra.setCleanbotStatus("Void Cleanbot equipped.")
            else
                Extra.setCleanbotStatus("Void rolled; keeping Huge equipped.")
            end
        elseif autoBest then
            Extra.setCleanbotStatus("Rolled " .. tostring(cleanbot) .. "; keeping the best owned Cleanbot.")
        else
            Extra.setCleanbotStatus("Rolled " .. tostring(cleanbot) .. ".")
        end

        if Extra.cleanbotAutoRollEnabled() then
            task.delay(0.05, function()
                if Extra.cleanbotAutoRollEnabled() then
                    fireCleanbotRoll()
                end
            end)
        end
    end)
    return true
end

fireCleanbotRoll = function()
    if Extra.CleanbotRollPending then
        return false
    end

    local remote = getRollRoombaRemote()
    if not remote or not startCleanbotResultListener() then
        notify("RollRoomba remote was not found.")
        return false
    end

    Extra.CleanbotRollPending = true
    Extra.CleanbotRollSerial += 1
    local serial = Extra.CleanbotRollSerial
    remote:FireServer()
    Marker:SetAttribute("CleanbotRollLastFire", Workspace:GetServerTimeNow())

    task.delay(5, function()
        if Extra.CleanbotRollPending and Extra.CleanbotRollSerial == serial then
            Extra.CleanbotRollPending = false
            if Extra.cleanbotAutoRollEnabled() then
                fireCleanbotRoll()
            end
        end
    end)

    return true
end

local function startBeamBoostLoop()
    stopTask("BeamBoost")

    Tasks.BeamBoost = task.spawn(function()
        local fired = maxEmpoweredBoost()
        Marker:SetAttribute("BeamBoostLastTopUp", fired)

        while Toggles.ToggleAutoBeamBoost and Toggles.ToggleAutoBeamBoost.Value do
            task.wait(29)
            if Toggles.ToggleAutoBeamBoost and Toggles.ToggleAutoBeamBoost.Value then
                fireEmpoweredBoostStack(1, 0)
                Marker:SetAttribute("BeamBoostLastTopUp", 1)
            end
        end
    end)
end

local function startGodlyOrbLoop()
    stopTask("GodlyOrb")

    Tasks.GodlyOrb = task.spawn(function()
        while Toggles.ToggleAutoGodlyOrb and Toggles.ToggleAutoGodlyOrb.Value do
            fireGodlyOrbClaim(1, 0)
            task.wait(math.max(0.25, getNumberOption("GodlyOrbClaimDelayMs", 1000) / 1000))
        end
    end)
end

local function startAutoPlinkoLoop()
    stopTask("AutoPlinko")

    Tasks.AutoPlinko = task.spawn(function()
        while Toggles.ToggleAutoPlinko and Toggles.ToggleAutoPlinko.Value do
            firePlinko4x()
            task.wait(30)
        end
    end)
end

local function startAutoCrateLoop()
    stopTask("AutoCrate")

    Tasks.AutoCrate = task.spawn(function()
        while Toggles.ToggleAutoCrate and Toggles.ToggleAutoCrate.Value do
            fireCrateBoost("goldenCrate", 1, 0)
            task.wait(math.max(1, getNumberOption("AutoDropBoostIntervalSeconds", 30)))
        end
    end)
end

local function startGemStormLoop()
    stopTask("GemStorm")

    Tasks.GemStorm = task.spawn(function()
        while Toggles.ToggleAutoGemStorm and Toggles.ToggleAutoGemStorm.Value do
            fireGemStorm()
            task.wait(0.5)
        end
    end)
end

local function startAutoAbilitiesLoop()
    stopTask("AutoAbilities")

    Tasks.AutoAbilities = task.spawn(function()
        while Toggles.ToggleAutoAbilities and Toggles.ToggleAutoAbilities.Value do
            fireAbilitiesOnce()
            task.wait(math.max(0.25, getNumberOption("AutoAbilitiesIntervalMs", 1000) / 1000))
        end
    end)
end

local function startAutoCleanbotLoop()
    stopTask("AutoCleanbot")
    if startCleanbotResultListener() then
        fireCleanbotRoll()
    end
end

function Extra.startAutoBestCleanbot()
    if not startCleanbotResultListener() then
        return
    end

    local profile = getProfileData()
    local owned = profile and profile.roombas
    if typeof(owned) == "table" and owned.hugeRoomba == true then
        Extra.BestCleanbotRank = 2
        Extra.equipCleanbot("HugeRoomba")
        Extra.setCleanbotStatus("Huge Cleanbot was already owned and is now equipped.")
        return
    end

    if typeof(owned) == "table" and owned.voidRoomba == true then
        Extra.BestCleanbotRank = 1
        Extra.equipCleanbot("VoidRoomba")
        Extra.setCleanbotStatus("Void Cleanbot was already owned and is now equipped.")
    else
        Extra.BestCleanbotRank = 0
        Extra.setCleanbotStatus("Watching Cleanbot rolls for Void or Huge.")
    end
end

local function startGemAutoCollect()
    disconnect("GemBatch")

    local remote = getGemBobGemBatchRemote()
    if not remote then
        notify("GemBobGemBatch remote was not found.")
        return
    end

    Connections.GemBatch = remote.OnClientEvent:Connect(function(gems)
        if Toggles.ToggleAutoCollectGemStorm and Toggles.ToggleAutoCollectGemStorm.Value then
            scheduleGemBatchClaims(gems)
        end
    end)
end

local function updateMarker()
    Marker:SetAttribute("Session", Session)
    Marker:SetAttribute("Enabled", Toggles.ToggleHugeCollector and Toggles.ToggleHugeCollector.Value or false)
    Marker:SetAttribute("Radius", getRadius())
    Marker:SetAttribute("BatchSize", getBatchSize())
    Marker:SetAttribute("TickDelay", getTickDelay())
    Marker:SetAttribute("RetryDelay", getRetryDelay())
    Marker:SetAttribute("CollectAll", Toggles.ToggleCollectAll and Toggles.ToggleCollectAll.Value or false)
end

local function startRingVisual()
    disconnect("RingVisual")
    Connections.RingVisual = RunService.Heartbeat:Connect(function()
        if Marker:GetAttribute("Session") ~= Session then
            disconnect("RingVisual")
            return
        end

        resizeActualCollectorRing()
    end)
end

local function startCollector()
    stopTask("Collector")
    updateMarker()
    startRingVisual()
    if Toggles.ToggleInstantSpawnCollector and Toggles.ToggleInstantSpawnCollector.Value then
        Extra.startInstantSpawnCollector()
    end

    Tasks.Collector = task.spawn(function()
        while Marker:GetAttribute("Session") == Session
            and Toggles.ToggleHugeCollector
            and Toggles.ToggleHugeCollector.Value
        do
            updateMarker()
            resizeActualCollectorRing()
            collectNearbyOnce()
            task.wait(getTickDelay())
        end

        Marker:SetAttribute("Enabled", false)
    end)
end

local function stopCollector()
    Marker:SetAttribute("Enabled", false)
    stopTask("Collector")
    Extra.stopInstantSpawnCollector()
end

Extra.PerfVfx = {
    ParticleEmitter = true,
    Trail = true,
    Beam = true,
    Fire = true,
    Smoke = true,
    Sparkles = true,
    PointLight = true,
    SpotLight = true,
    SurfaceLight = true,
    Highlight = true,
    BloomEffect = true,
    BlurEffect = true,
    DepthOfFieldEffect = true,
    SunRaysEffect = true,
    ColorCorrectionEffect = true,
}

function Extra.perfToggle(id, fallback)
    local toggle = Toggles[id]
    if not toggle then
        return fallback == true
    end
    return toggle.Value == true
end

function Extra.perfOption(id, fallback)
    local option = Options[id]
    local value = option and tonumber(option.Value)
    return value or fallback
end

function Extra.safeSet(instance, property, value)
    if not instance then
        return false
    end
    return pcall(function()
        instance[property] = value
    end)
end

function Extra.findPath(root, path)
    local current = root
    for _, name in ipairs(path) do
        current = current and current:FindFirstChild(name)
        if not current then
            return nil
        end
    end
    return current
end

function Extra.perfPlayerGui()
    return LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui") or nil
end

function Extra.perfMainGui()
    local gui = Extra.perfPlayerGui()
    return gui and gui:FindFirstChild("MainGui") or nil
end

function Extra.setPerfStatus(text)
    text = tostring(text)
    Marker:SetAttribute("PerformanceStatus", text)
    if Extra.PerformanceStatusLabel then
        pcall(function()
            Extra.PerformanceStatusLabel:SetText(text)
        end)
    end
end

function Extra.disablePerfVfx(instance)
    if not instance then
        return 0
    end

    local className = instance.ClassName
    if className == "ParticleEmitter" then
        Extra.safeSet(instance, "Enabled", false)
        Extra.safeSet(instance, "Rate", 0)
        pcall(function()
            instance:Clear()
        end)
        return 1
    end

    if Extra.PerfVfx[className] then
        Extra.safeSet(instance, "Enabled", false)
        return 1
    end

    if className == "Explosion" then
        Extra.safeSet(instance, "Visible", false)
        Extra.safeSet(instance, "BlastPressure", 0)
        Extra.safeSet(instance, "BlastRadius", 0)
        return 1
    end

    return 0
end

function Extra.hidePerfWorldObject(instance)
    if not instance then
        return 0
    end

    if instance:IsA("BasePart") then
        Extra.safeSet(instance, "Transparency", 1)
        Extra.safeSet(instance, "LocalTransparencyModifier", 1)
        Extra.safeSet(instance, "CastShadow", false)
        return 1
    end

    if instance:IsA("Decal") or instance:IsA("Texture") then
        Extra.safeSet(instance, "Transparency", 1)
        return 1
    end

    if instance:IsA("SurfaceGui") or instance:IsA("BillboardGui") then
        Extra.safeSet(instance, "Enabled", false)
        return 1
    end

    return Extra.disablePerfVfx(instance)
end

function Extra.hidePerfTree(root)
    if not root then
        return 0
    end

    local count = Extra.hidePerfWorldObject(root)
    for _, descendant in ipairs(root:GetDescendants()) do
        count += Extra.hidePerfWorldObject(descendant)
    end
    return count
end

function Extra.setPerfGuiRoot(root, hidden)
    if not root then
        return 0
    end

    if root:IsA("ScreenGui") or root:IsA("BillboardGui") or root:IsA("SurfaceGui") then
        Extra.safeSet(root, "Enabled", not hidden)
        return 1
    end

    if root:IsA("GuiObject") then
        Extra.safeSet(root, "Visible", not hidden)
        return 1
    end

    return 0
end

function Extra.sweepPerfVfx()
    local count = 0
    local roots = { Workspace, ReplicatedStorage, Extra.PerfLighting }
    local gui = Extra.perfPlayerGui()
    if gui then
        roots[#roots + 1] = gui
    end

    for _, root in ipairs(roots) do
        count += Extra.disablePerfVfx(root)
        for _, descendant in ipairs(root:GetDescendants()) do
            count += Extra.disablePerfVfx(descendant)
        end
    end

    if Extra.perfToggle("TogglePerfNoShadows", true) then
        Extra.safeSet(Extra.PerfLighting, "GlobalShadows", false)
    end
    if Extra.perfToggle("TogglePerfLowQuality", true) then
        pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end)
    end

    return count
end

function Extra.sweepPerfSlimes()
    return Extra.hidePerfTree(Extra.findPath(Workspace, { "Runtime", "Slimes" }))
end

function Extra.perfSlimesFolder()
    return Extra.findPath(Workspace, { "Runtime", "Slimes" })
end

function Extra.startPerfSlimeWatcher()
    disconnect("PerfSlimeChildAdded")
    disconnect("PerfSlimeDescendantAdded")

    if not Extra.perfToggle("TogglePerfHideSlimes", true)
        or not Extra.perfToggle("TogglePerfAutoHideNewSlimes", true) then
        Marker:SetAttribute("PerfSlimeWatcher", false)
        return false
    end

    local slimes = Extra.perfSlimesFolder()
    if not slimes then
        Marker:SetAttribute("PerfSlimeWatcher", false)
        return false
    end

    Connections.PerfSlimeChildAdded = slimes.ChildAdded:Connect(function(slime)
        task.defer(function()
            Extra.hidePerfTree(slime)
        end)
    end)
    Connections.PerfSlimeDescendantAdded = slimes.DescendantAdded:Connect(function(descendant)
        task.defer(function()
            Extra.hidePerfWorldObject(descendant)
        end)
    end)

    Marker:SetAttribute("PerfSlimeWatcher", true)
    return true
end

function Extra.stopPerfSlimeWatcher()
    disconnect("PerfSlimeChildAdded")
    disconnect("PerfSlimeDescendantAdded")
    Marker:SetAttribute("PerfSlimeWatcher", false)
end

function Extra.sweepPerfCleanbots()
    local count = Extra.hidePerfTree(Extra.findPath(Workspace, { "Runtime", "Roombas" }))
    local zones = Extra.findPath(Workspace, { "World", "Zones" })
    if zones then
        for _, item in ipairs(zones:GetDescendants()) do
            local name = tostring(item.Name):lower()
            if name:find("roomba", 1, true) and not name:find("upgrade", 1, true) then
                count += Extra.hidePerfTree(item)
            end
        end
    end
    return count
end

function Extra.sweepPerfBobs()
    local count = 0
    local followers = Extra.findPath(Workspace, { "Runtime", "Followers" })
    if followers then
        for _, follower in ipairs(followers:GetChildren()) do
            if tostring(follower.Name):lower():find("bob", 1, true) then
                count += Extra.hidePerfTree(follower)
            end
        end
    end

    local interactables = Workspace:FindFirstChild("Interactables")
    if interactables then
        count += Extra.hidePerfTree(interactables:FindFirstChild("GiftBobSpawnPos"))
        count += Extra.hidePerfTree(interactables:FindFirstChild("GiftBobSpawnOrb"))
        count += Extra.hidePerfTree(interactables:FindFirstChild("GiftBobCam"))
    end
    return count
end

function Extra.sweepPerfUpgradeBoards()
    local count = Extra.hidePerfTree(Extra.findPath(Workspace, { "World", "Map", "MainUpgrades" }))
    local world = Workspace:FindFirstChild("World")
    if world then
        for _, item in ipairs(world:GetDescendants()) do
            if tostring(item.Name):find("Upgrade", 1, true) then
                count += Extra.hidePerfTree(item)
            end
        end
    end
    return count
end

function Extra.sweepPerfTopki()
    local count = 0
    local topki = Extra.findPath(Workspace, { "World", "Topki" })
    if topki then
        for _, child in ipairs(topki:GetChildren()) do
            local name = tostring(child.Name):lower()
            if name:find("leaderboard", 1, true)
                or name:find("donat", 1, true)
                or name:find("contrib", 1, true) then
                count += Extra.hidePerfTree(child)
            end
        end
    end
    return count
end

function Extra.sweepPerfHud()
    local count = 0
    local gui = Extra.perfMainGui()
    local hideHud = Extra.perfToggle("TogglePerfHideHud", false)
    if gui then
        count += Extra.setPerfGuiRoot(gui:FindFirstChild("Stats"), hideHud and Extra.perfToggle("TogglePerfHideStats", true))
        count += Extra.setPerfGuiRoot(gui:FindFirstChild("Boosts"), hideHud and Extra.perfToggle("TogglePerfHideBoosts", true))
        count += Extra.setPerfGuiRoot(gui:FindFirstChild("Lvl"), hideHud and Extra.perfToggle("TogglePerfHideTopHud", true))
        count += Extra.setPerfGuiRoot(gui:FindFirstChild("Capacity"), hideHud and Extra.perfToggle("TogglePerfHideTopHud", true))
        count += Extra.setPerfGuiRoot(gui:FindFirstChild("Abilities"), hideHud and Extra.perfToggle("TogglePerfHideButtons", true))
        count += Extra.setPerfGuiRoot(gui:FindFirstChild("Options"), hideHud and Extra.perfToggle("TogglePerfHideButtons", true))
        count += Extra.setPerfGuiRoot(gui:FindFirstChild("DailyQuestHud"), hideHud and Extra.perfToggle("TogglePerfHideInfo", true))
    end

    count += Extra.setPerfGuiRoot(Extra.perfPlayerGui() and Extra.perfPlayerGui():FindFirstChild("InfoInterface"), hideHud and Extra.perfToggle("TogglePerfHideInfo", true))
    return count
end

function Extra.isPerfCurrencyPopupText(text)
    local upper = tostring(text or ""):upper()
    return upper:find("GODLY ESSENCE", 1, true)
        or upper:find("POWER", 1, true)
        or upper:match("%f[%w]GE%f[%W]")
        or (upper:match("%f[%w]P%f[%W]") and (upper:find("+", 1, true) or upper:find("%d")))
end

function Extra.hidePerfCurrencyPopupText(label)
    if not (label and (label:IsA("TextLabel") or label:IsA("TextButton"))) then
        return 0
    end
    if not Extra.isPerfCurrencyPopupText(label.Text) then
        return 0
    end

    Extra.safeSet(label, "Visible", false)
    Extra.safeSet(label, "TextTransparency", 1)
    Extra.safeSet(label, "TextStrokeTransparency", 1)
    return 1
end

function Extra.sweepPerfPopups()
    local count = 0
    local gui = Extra.perfPlayerGui()
    local main = Extra.perfMainGui()
    local roots = {}
    local announcements = main and main:FindFirstChild("Announcements")
    local popUpScreen = gui and gui:FindFirstChild("PopUpScreen")
    if announcements then
        roots[#roots + 1] = announcements
    end
    if popUpScreen then
        roots[#roots + 1] = popUpScreen
    end

    for _, root in ipairs(roots) do
        if root then
            for _, item in ipairs(root:GetDescendants()) do
                count += Extra.hidePerfCurrencyPopupText(item)
            end
        end
    end
    return count
end

function Extra.sweepPerformance()
    local count = 0
    if Extra.perfToggle("TogglePerfVfx", true) then
        count += Extra.sweepPerfVfx()
    end
    if Extra.perfToggle("TogglePerfHideSlimes", true) then
        count += Extra.sweepPerfSlimes()
        if Extra.perfToggle("TogglePerfAutoHideNewSlimes", true) then
            Extra.startPerfSlimeWatcher()
        else
            Extra.stopPerfSlimeWatcher()
        end
    else
        Extra.stopPerfSlimeWatcher()
    end
    if Extra.perfToggle("TogglePerfHideCleanbots", true) then
        count += Extra.sweepPerfCleanbots()
    end
    if Extra.perfToggle("TogglePerfHideBobs", true) then
        count += Extra.sweepPerfBobs()
    end
    if Extra.perfToggle("TogglePerfHideGemBob", true) then
        count += Extra.hidePerfTree(Workspace:FindFirstChild("GemBob"))
    end
    if Extra.perfToggle("TogglePerfHideBoards", true) then
        count += Extra.sweepPerfUpgradeBoards()
    end
    if Extra.perfToggle("TogglePerfHideTopki", true) then
        count += Extra.sweepPerfTopki()
    end
    count += Extra.sweepPerfHud()
    if Extra.perfToggle("TogglePerfHidePopups", true) then
        count += Extra.sweepPerfPopups()
    end

    Marker:SetAttribute("PerformanceLastTouched", count)
    Marker:SetAttribute("PerformanceLastSweepAt", Workspace:GetServerTimeNow())
    Marker:SetAttribute("PerformanceEnabled", false)
    Extra.setPerfStatus("One-time FPS boost touched " .. tostring(count) .. " item(s).")
    return count
end

function Extra.showPerformanceHud()
    local gui = Extra.perfMainGui()
    if gui then
        for _, name in ipairs({ "Stats", "Boosts", "Lvl", "Capacity", "Abilities", "Options", "DailyQuestHud" }) do
            Extra.setPerfGuiRoot(gui:FindFirstChild(name), false)
        end
    end
    Extra.setPerfGuiRoot(Extra.perfPlayerGui() and Extra.perfPlayerGui():FindFirstChild("InfoInterface"), false)
end

function Extra.stopPerformance()
    stopTask("Performance")
    Marker:SetAttribute("PerformanceEnabled", false)
    Extra.showPerformanceHud()
    Extra.setPerfStatus("HUD restored. World FPS hides restore on rejoin.")
end

local Window = Library:CreateWindow({
    Title = "slimeinc v" .. Extra.Version,
    Footer = "disc : neonbeon | slimeinc v" .. Extra.Version,
    Icon = 111288992980872,
    Compact = true,
    SidebarCompactWidth = 56,
    NotifySide = "Right",
    ShowCustomCursor = false,
    UnlockMouseWhileOpen = false,
})

local Tabs = {
    Main = Window:AddTab("Main", "house"),
    Automation = Window:AddTab("Automation", "bot"),
    Performance = Window:AddTab("Performance", "gauge"),
    Blessings = Window:AddTab("Blessings", "sparkles"),
    AutoUpgrade = Window:AddTab("Auto Upgrade", "circle-arrow-up"),
    ["UI Settings"] = Window:AddTab("UI Settings", "folder-cog"),
}

local AutoUpgradeTabboxGroups = {
    { title = "Early Boards", side = "Left", indexes = { 1, 2, 3 } },
    { title = "Ability Boards", side = "Right", indexes = { 4, 5, 6 } },
    { title = "Advanced Boards", side = "Left", indexes = { 7, 8, 9 } },
    { title = "Endgame Boards", side = "Right", indexes = { 10, 11 } },
}

do
    local AutoUpgradeControlsBox = Tabs.AutoUpgrade:AddLeftGroupbox("Controls", "power")
    AutoUpgradeControlsBox:AddCheckbox("ToggleAutoUpgradesMaster", {
        Text = "Enable Auto Upgrades",
        Default = true,
    })
end

do
    local PerfCoreBox = Tabs.Performance:AddLeftGroupbox("Core", "gauge")
    PerfCoreBox:AddCheckbox("TogglePerfVfx", {
        Text = "Disable VFX",
        Default = true,
    })
    PerfCoreBox:AddCheckbox("TogglePerfNoShadows", {
        Text = "No Shadows",
        Default = true,
    })
    PerfCoreBox:AddCheckbox("TogglePerfLowQuality", {
        Text = "Low Render Quality",
        Default = true,
    })
    PerfCoreBox:AddButton({
        Text = "Apply FPS Boost Once",
        Func = function()
            task.spawn(function()
                notify("FPS boost touched: " .. tostring(Extra.sweepPerformance()))
            end)
        end,
    })
    PerfCoreBox:AddButton({
        Text = "Show HUD",
        Func = function()
            Extra.showPerformanceHud()
            notify("HUD roots shown. World hides restore on rejoin.")
        end,
    })
    Extra.PerformanceStatusLabel = PerfCoreBox:AddLabel({
        Text = "FPS boost is one-time. HUD toggles update live.",
        DoesWrap = true,
    })
end

do
    local PerfWorldBox = Tabs.Performance:AddRightGroupbox("World", "eye-off")
    PerfWorldBox:AddCheckbox("TogglePerfHideSlimes", {
        Text = "Hide Slimes",
        Default = true,
    })
    PerfWorldBox:AddCheckbox("TogglePerfAutoHideNewSlimes", {
        Text = "Keep New Slimes Hidden",
        Default = true,
    })
    PerfWorldBox:AddCheckbox("TogglePerfHideCleanbots", {
        Text = "Hide Cleanbots",
        Default = true,
    })
    PerfWorldBox:AddCheckbox("TogglePerfHideBobs", {
        Text = "Hide Bob Followers",
        Default = true,
    })
    PerfWorldBox:AddCheckbox("TogglePerfHideGemBob", {
        Text = "Hide Gem Bob",
        Default = true,
    })
    PerfWorldBox:AddCheckbox("TogglePerfHideBoards", {
        Text = "Hide Upgrade Boards",
        Default = true,
    })
    PerfWorldBox:AddCheckbox("TogglePerfHideTopki", {
        Text = "Hide Leaderboards / Donate",
        Default = true,
    })
end

do
    local PerfHudBox = Tabs.Performance:AddLeftGroupbox("HUD", "sliders-horizontal")
    PerfHudBox:AddCheckbox("TogglePerfHideHud", {
        Text = "Hide HUD",
        Default = false,
    })
    PerfHudBox:AddCheckbox("TogglePerfHideStats", {
        Text = "Hide Currency HUD",
        Default = true,
    })
    PerfHudBox:AddCheckbox("TogglePerfHideBoosts", {
        Text = "Hide Boost Icons",
        Default = true,
    })
    PerfHudBox:AddCheckbox("TogglePerfHideTopHud", {
        Text = "Hide Level / Capacity",
        Default = true,
    })
    PerfHudBox:AddCheckbox("TogglePerfHideButtons", {
        Text = "Hide Buttons",
        Default = true,
    })
    PerfHudBox:AddCheckbox("TogglePerfHideInfo", {
        Text = "Hide Server Info",
        Default = true,
    })
    PerfHudBox:AddCheckbox("TogglePerfHidePopups", {
        Text = "Hide GE / P Popups",
        Default = true,
    })
end

local function addAutoUpgradeBoardTab(tabbox, board)
    if not (tabbox and board and board.entries and #board.entries > 0) then
        return
    end

    local labels = upgradeBoardLabels(board)
    local boardTab = tabbox:AddTab(board.name, board.icon)

    boardTab:AddDropdown(upgradeSelectionId(board), {
        Text = "Selected Upgrades",
        Values = labels,
        Multi = true,
        AllowNull = true,
        Default = table.clone(labels),
    })
    boardTab:AddButton({
        Text = "Buy Selected Max",
        Func = function()
            task.spawn(function()
                notify(board.name .. " upgrades fired: " .. tostring(purchaseUpgradeBoard(board)))
            end)
        end,
    })
    boardTab:AddButton({
        Text = "Select All",
        Func = function()
            Options[upgradeSelectionId(board)]:SetValue(table.clone(labels))
        end,
    })
    boardTab:AddButton({
        Text = "Clear Selection",
        Func = function()
            Options[upgradeSelectionId(board)]:SetValue({})
        end,
    })
    boardTab:AddCheckbox(upgradeToggleId(board), {
        Text = "Auto Buy Selected",
        Default = false,
    })
end

for _, group in ipairs(AutoUpgradeTabboxGroups) do
    local tabbox
    if group.side == "Left" then
        tabbox = Tabs.AutoUpgrade:AddLeftTabbox(group.title)
    else
        tabbox = Tabs.AutoUpgrade:AddRightTabbox(group.title)
    end

    for _, index in ipairs(group.indexes) do
        addAutoUpgradeBoardTab(tabbox, Extra.AutoUpgradeBoards[index])
    end
end

do
local BlessingRulesBox = Tabs.Blessings:AddLeftGroupbox("Sacrifice Rules", "list-checks")
BlessingRulesBox:AddDropdown("BlessingSacrificeBlacklist", {
    Text = "Protected Blacklist",
    Values = Extra.BlessingLabels,
    Multi = true,
    AllowNull = true,
    Default = {},
})
BlessingRulesBox:AddButton({
    Text = "Clear Blacklist",
    Func = function()
        Options.BlessingSacrificeBlacklist:SetValue({})
    end,
})
end

do
local AutoBlessingBox = Tabs.Blessings:AddRightGroupbox("Auto Blessing", "sparkles")
AutoBlessingBox:AddDropdown("BlessingPickPriority", {
    Text = "Pick Priority",
    Values = Extra.BlessingLabels,
    Multi = true,
    AllowNull = true,
    Default = {},
    Callback = Extra.syncBlessingPickPriority,
})
AutoBlessingBox:AddButton({
    Text = "Clear Pick Priority",
    Func = function()
        Options.BlessingPickPriority:SetValue({})
    end,
})
Extra.BlessingPriorityLabel = AutoBlessingBox:AddLabel({
    Text = "Priority: Random",
    DoesWrap = true,
})
AutoBlessingBox:AddCheckbox("ToggleAutoBlessing", {
    Text = "Auto Roll / Pick",
    Default = false,
})
AutoBlessingBox:AddCheckbox("ToggleAutoBlessingSacrifice", {
    Text = "Auto Sacrifice (10 GE)",
    Default = false,
})
AutoBlessingBox:AddCheckbox("ToggleAutoBlessingReroll", {
    Text = "Auto Reroll Choices (10 GE)",
    Default = false,
})
AutoBlessingBox:AddButton({
    Text = "Run One Step",
    Func = function()
        notify("Auto blessing step fired: " .. tostring(Extra.autoBlessingStep(true)))
    end,
})
Extra.BlessingStatusLabel = AutoBlessingBox:AddLabel({
    Text = "Auto Blessing is off.",
    DoesWrap = true,
})
end

local CollectorBox = Tabs.Main:AddLeftGroupbox("Collector", "magnet")
CollectorBox:AddCheckbox("ToggleHugeCollector", {
    Text = "Auto Collect Slimes",
    Default = true,
})
CollectorBox:AddCheckbox("ToggleInstantSpawnCollector", {
    Text = "Instant Spawn Collection",
    Default = true,
})
CollectorBox:AddCheckbox("ToggleActualRing", {
    Text = "Big Actual Ring",
    Default = true,
})
CollectorBox:AddCheckbox("ToggleCollectAll", {
    Text = "Collect All Slimes",
    Default = false,
})
CollectorBox:AddSlider("CollectorRadius", {
    Text = "Circle Radius",
    Min = 25,
    Max = 10000,
    Default = 5000,
    Rounding = 0,
    Suffix = " studs",
})
CollectorBox:AddSlider("CollectorBatchSize", {
    Text = "Batch Size",
    Min = 1,
    Max = 1000,
    Default = 500,
    Rounding = 0,
    Suffix = " ids",
})
CollectorBox:AddButton({
    Text = "Collect Once",
    Func = function()
        notify("Collected " .. tostring(collectNearbyOnce(true)) .. " slime id(s).")
    end,
})
CollectorBox:AddButton({
    Text = "Really Big Preset",
    Func = function()
        Options.CollectorRadius:SetValue(10000)
        Options.CollectorBatchSize:SetValue(1000)
        resizeActualCollectorRing()
        updateMarker()
        notify("Really big collector preset applied.")
    end,
})

local BeamBoostBox = Tabs.Automation:AddLeftGroupbox("Beam Boost", "zap")
BeamBoostBox:AddButton({
    Text = "Max Beam Boost",
    Func = function()
        task.spawn(function()
            local fired = maxEmpoweredBoost()
            notify("Beam boost max fired: " .. tostring(fired))
        end)
    end,
})
BeamBoostBox:AddCheckbox("ToggleAutoBeamBoost", {
    Text = "Auto Keep Max",
    Default = false,
})

local AbilityBox = Tabs.Automation:AddRightGroupbox("Abilities", "wand-sparkles")
AbilityBox:AddSlider("AutoAbilitiesIntervalMs", {
    Text = "Ability Interval",
    Min = 250,
    Max = 10000,
    Default = 1000,
    Rounding = 0,
    Suffix = " ms",
})
AbilityBox:AddButton({
    Text = "Use Abilities Once",
    Func = function()
        task.spawn(function()
            notify("Abilities fired: " .. tostring(fireAbilitiesOnce()))
        end)
    end,
})
AbilityBox:AddCheckbox("ToggleAutoAbilities", {
    Text = "Auto Abilities",
    Default = false,
})
AbilityBox:AddCheckbox("ToggleAbilityHolyBeam", {
    Text = "Use Holy Beam",
    Default = true,
})
AbilityBox:AddCheckbox("ToggleAbilityVoid", {
    Text = "Use Void",
    Default = true,
})
AbilityBox:AddCheckbox("ToggleAbilityLuckyRush", {
    Text = "Use Lucky Rush",
    Default = true,
})
AbilityBox:AddCheckbox("ToggleAbilityAutocollect", {
    Text = "Use Autocollect",
    Default = false,
})

local PotionBox = Tabs.Automation:AddLeftGroupbox("Potions", "flask-conical")
PotionBox:AddButton({
    Text = "Use Selected Potions",
    Func = function()
        task.spawn(function()
            notify("Potions fired: " .. tostring(fireSelectedPotionsOnce()))
        end)
    end,
})
PotionBox:AddCheckbox("ToggleAutoPotions", {
    Text = "Auto Potions",
    Default = false,
})
PotionBox:AddCheckbox("TogglePotionRainbow", {
    Text = "Rainbow Potion",
    Default = true,
})
PotionBox:AddCheckbox("TogglePotionEnergy", {
    Text = "Energy Potion",
    Default = false,
})
PotionBox:AddCheckbox("TogglePotionGodly", {
    Text = "Godly Potion",
    Default = false,
})
PotionBox:AddCheckbox("TogglePotionAmuletLuck", {
    Text = "Amulet Luck Potion",
    Default = false,
})
PotionBox:AddCheckbox("TogglePotionElemental", {
    Text = "Elemental Potion",
    Default = false,
})

local TotemBox = Tabs.Automation:AddRightGroupbox("Totems", "badge-plus")
TotemBox:AddCheckbox("ToggleAutoTotemContact", {
    Text = "Auto Totem Contact",
    Default = false,
})

local AmuletBox = Tabs.Automation:AddLeftGroupbox("Auto Amulet", "gem")
function Extra.countActiveAmuletCustomComboSlots()
    local count = 0
    for _, slot in pairs(Extra.AmuletCustomComboSlots) do
        if slot.Active then
            count += 1
        end
    end

    return count
end

function Extra.hideAmuletCustomComboSlot(index)
    local slot = Extra.AmuletCustomComboSlots[index]
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

    Marker:SetAttribute("AmuletCustomComboSlots", Extra.countActiveAmuletCustomComboSlots())
    return true
end

function Extra.showAmuletCustomComboSlot()
    for index = 1, Extra.AmuletCustomComboSlotLimit do
        local slot = Extra.AmuletCustomComboSlots[index]
        if slot and not slot.Active then
            slot.Active = true
            if slot.Dropdown then
                slot.Dropdown:SetVisible(true)
            end
            if slot.RemoveButton then
                slot.RemoveButton:SetVisible(true)
            end

            Marker:SetAttribute("AmuletCustomComboSlots", Extra.countActiveAmuletCustomComboSlots())
            return true
        end
    end

    notify("Max custom combo dropdowns are already added.")
    return false
end

function Extra.createAmuletCustomComboSlot(groupbox, index)
    local slot = {
        Active = false,
        DropdownId = "AmuletCustomCombo" .. tostring(index),
    }
    Extra.AmuletCustomComboSlots[index] = slot

    slot.Dropdown = groupbox:AddDropdown(slot.DropdownId, {
        Text = "Custom Combo " .. tostring(index),
        Values = Extra.AmuletTypeValues,
        Multi = true,
        AllowNull = true,
        Default = {},
    })
    slot.RemoveButton = groupbox:AddButton({
        Text = "Remove Combo " .. tostring(index),
        Func = function()
            Extra.hideAmuletCustomComboSlot(index)
        end,
    })

    slot.Dropdown:SetVisible(false)
    slot.RemoveButton:SetVisible(false)
    return slot
end

AmuletBox:AddDropdown("AmuletOptionCounts", {
    Text = "Stop On Option Count",
    Values = AmuletCountValues,
    Multi = true,
    AllowNull = true,
    Default = { "4" },
})
AmuletBox:AddDropdown("AmuletRequiredTypes", {
    Text = "Required Amulet Type",
    Values = Extra.AmuletTypeValues,
    Multi = true,
    AllowNull = true,
    Default = {},
})
AmuletBox:AddButton({
    Text = "Add Custom Combo",
    Func = function()
        Extra.showAmuletCustomComboSlot()
    end,
})
for index = 1, Extra.AmuletCustomComboSlotLimit do
    Extra.createAmuletCustomComboSlot(AmuletBox, index)
end
AmuletBox:AddCheckbox("ToggleRequireAmuletType", {
    Text = "Require Types/Combos",
    Default = false,
})
AmuletBox:AddCheckbox("ToggleRequireAllAmuletTypes", {
    Text = "Selected Types Are Combo",
    Default = false,
})
AmuletBox:AddCheckbox("ToggleAmuletRulesUseOr", {
    Text = "Combo/Type OR Min Value",
    Default = false,
})
AmuletBox:AddCheckbox("ToggleAmuletAnyMinimumStat", {
    Text = "Any Min Value Passes",
    Default = false,
})
AmuletBox:AddInput("AmuletMinCombinedSlimesInput", {
    Text = "Min Slimes Total",
    Default = "0",
    Numeric = true,
    AllowEmpty = false,
    EmptyReset = "0",
    ClearTextOnFocus = false,
    Placeholder = "0",
})
AmuletBox:AddInput("AmuletMinCombinedExpInput", {
    Text = "Min Exp Total",
    Default = "0",
    Numeric = true,
    AllowEmpty = false,
    EmptyReset = "0",
    ClearTextOnFocus = false,
    Placeholder = "0",
})
AmuletBox:AddInput("AmuletMinCombinedGemsInput", {
    Text = "Min Gems Total",
    Default = "0",
    Numeric = true,
    AllowEmpty = false,
    EmptyReset = "0",
    ClearTextOnFocus = false,
    Placeholder = "0",
})
AmuletBox:AddSlider("AutoAmuletRollDelayMs", {
    Text = "Roll Delay",
    Min = 0,
    Max = 500,
    Default = 50,
    Rounding = 0,
    Suffix = " ms",
})
AmuletBox:AddCheckbox("ToggleAmuletHideRollVisuals", {
    Text = "Hide Roll Cards/Animation",
    Default = true,
})
AmuletBox:AddCheckbox("ToggleAutoAmuletRoll", {
    Text = "Auto Roll Until Count",
    Default = false,
})
AmuletBox:AddButton({
    Text = "Roll Amulet Once",
    Func = function()
        notify("Amulet roll fired: " .. tostring(rollAmuletOnce()))
    end,
})
AmuletBox:AddButton({
    Text = "Select New",
    Func = function()
        pickLatestAmulet("NEW")
    end,
})
AmuletBox:AddButton({
    Text = "Keep Old",
    Func = function()
        pickLatestAmulet("OLD")
    end,
})
AmuletStatusLabel = AmuletBox:AddLabel({
    Text = LatestAmuletSummary,
    DoesWrap = true,
})

do
local CSlimeBox = Tabs.Automation:AddLeftGroupbox("CS Slime", "circle-dot")
CSlimeBox:AddSlider("CSlimeCollectDelaySeconds", {
    Text = "Collect Interval",
    Min = 1,
    Max = 360,
    Default = 10,
    Rounding = 0,
    Suffix = " s",
})
CSlimeBox:AddCheckbox("ToggleAutoCSlime", {
    Text = "Auto Teleport and Collect",
    Default = false,
})
Extra.CSlimeStatusLabel = CSlimeBox:AddLabel({
    Text = "Auto CS slime is off.",
    DoesWrap = true,
})
end

local DropBoostBox = Tabs.Automation:AddLeftGroupbox("Plinko / Crates", "gift")
DropBoostBox:AddSlider("AutoDropBoostIntervalSeconds", {
    Text = "Crate Interval",
    Min = 1,
    Max = 300,
    Default = 30,
    Rounding = 0,
    Suffix = " s",
})
DropBoostBox:AddButton({
    Text = "Get Plinko 4x",
    Func = function()
        task.spawn(function()
            local fired = firePlinko4x()
            notify(fired > 0 and "Plinko 4x fired." or "Plinko 4x could not fire.")
        end)
    end,
})
DropBoostBox:AddCheckbox("ToggleAutoPlinko", {
    Text = "Auto Plinko 4x",
    Default = false,
})
DropBoostBox:AddButton({
    Text = "Get Crate Boost",
    Func = function()
        task.spawn(function()
            local fired = fireCrateBoost("goldenCrate", 1, 0)
            notify("Golden-first crate boost fired: " .. tostring(fired))
        end)
    end,
})
DropBoostBox:AddCheckbox("ToggleAutoCrate", {
    Text = "Auto Crate Boost",
    Default = false,
})

local FallingStarBox = Tabs.Automation:AddRightGroupbox("Falling Stars", "star")
FallingStarBox:AddCheckbox("ToggleAutoFallingStars", {
    Text = "Auto Start Machine",
    Default = false,
})
FallingStarBox:AddCheckbox("ToggleAutoCollectFallingStars", {
    Text = "Auto Collect Stars",
    Default = true,
})

do
local QuestClaimBox = Tabs.Automation:AddRightGroupbox("Quest Claims", "badge-check")
QuestClaimBox:AddSlider("AutoQuestClaimRetrySeconds", {
    Text = "Claim Retry Cooldown",
    Min = 30,
    Max = 600,
    Default = 120,
    Rounding = 0,
    Suffix = " s",
})
QuestClaimBox:AddCheckbox("ToggleAutoDailyQuestClaim", {
    Text = "Auto Daily Quest Claims",
    Default = true,
})
QuestClaimBox:AddCheckbox("ToggleAutoQuestClaim", {
    Text = "Auto Quest/Achievement Claims",
    Default = true,
})
Extra.QuestClaimStatusLabel = QuestClaimBox:AddLabel({
    Text = "Auto quest claims are off.",
    DoesWrap = true,
})
end

local BossBox = Tabs.Automation:AddRightGroupbox("Boss", "swords")
BossBox:AddSlider("AutoBossStartRetrySeconds", {
    Text = "Start Retry",
    Min = 10,
    Max = 300,
    Default = 60,
    Rounding = 0,
    Suffix = " s",
})
BossBox:AddSlider("AutoBossParryOffsetMs", {
    Text = "Parry Offset",
    Min = 0,
    Max = 180,
    Default = 50,
    Rounding = 0,
    Suffix = " ms",
})
BossBox:AddSlider("AutoBossHoverHeight", {
    Text = "Boss Hover Height",
    Min = 8,
    Max = 60,
    Default = 24,
    Rounding = 0,
})
BossBox:AddSlider("AutoUndeadHitDelayMs", {
    Text = "Undead Hit Delay",
    Min = 250,
    Max = 2000,
    Default = 500,
    Rounding = 0,
    Suffix = " ms",
})
BossBox:AddSlider("AutoBossCardSpendBurst", {
    Text = "Card Spend Burst",
    Min = 1,
    Max = 100,
    Default = 20,
    Rounding = 0,
})
BossBox:AddSlider("AutoBossCardSpendDelayMs", {
    Text = "Card Spend Delay",
    Min = 0,
    Max = 500,
    Default = 50,
    Rounding = 0,
    Suffix = " ms",
})
BossBox:AddButton({
    Text = "Refresh Boss State",
    Func = function()
        Extra.connectBossEvents()
        notify("Boss state requested: " .. tostring(Extra.requestBossState(true)))
    end,
})
BossBox:AddButton({
    Text = "Start Boss Once",
    Func = function()
        task.spawn(function()
            Extra.connectBossEvents()
            notify("Boss start fired: " .. tostring(Extra.fireBossStart(true)))
        end)
    end,
})
BossBox:AddButton({
    Text = "Pay Open Boss Once",
    Func = function()
        task.spawn(function()
            Extra.connectBossEvents()
            notify("Boss pay/open fired: " .. tostring(Extra.fireBossStart(true)))
        end)
    end,
})
BossBox:AddDropdown("BossCardPick", {
    Text = "Card Pick",
    Values = Extra.BossCardValues,
    Multi = false,
    Default = "---",
})
BossBox:AddCheckbox("ToggleAutoBossStart", {
    Text = "Auto Start Boss",
    Default = false,
})
BossBox:AddCheckbox("ToggleAutoBossPayOpen", {
    Text = "Auto Pay Open Boss",
    Default = false,
})
BossBox:AddCheckbox("ToggleAutoBossFight", {
    Text = "Auto Fight Boss",
    Default = false,
})
BossBox:AddCheckbox("ToggleAutoBossMove", {
    Text = "Auto Enter/Move",
    Default = true,
})
BossBox:AddCheckbox("ToggleAutoBossStayAbove", {
    Text = "Stay Above Boss",
    Default = true,
})
BossBox:AddCheckbox("ToggleAutoBossParry", {
    Text = "Auto Parry",
    Default = true,
})
BossBox:AddCheckbox("ToggleAutoBossSplitPickups", {
    Text = "Auto Split Pickups",
    Default = true,
})
BossBox:AddCheckbox("ToggleAutoBossBuyCards", {
    Text = "Auto Card Pick",
    Default = false,
})
BossBox:AddCheckbox("ToggleAutoBossRandomCard", {
    Text = "Random Card Pick",
    Default = false,
})
BossBox:AddCheckbox("ToggleAutoBossCloseVictory", {
    Text = "Auto Close Victory",
    Default = false,
})
BossBox:AddCheckbox("ToggleAutoBossRemoveAttackVfx", {
    Text = "Remove Boss Attack VFX",
    Default = true,
})
BossBox:AddCheckbox("ToggleAutoUndeadBoss", {
    Text = "Auto Undead Mini Boss",
    Default = false,
})
BossBox:AddCheckbox("ToggleAutoUndeadMove", {
    Text = "Move To Undead Boss",
    Default = true,
})
Extra.BossCoinsLabel = BossBox:AddLabel({
    Text = "Boss Coins: unknown",
    DoesWrap = true,
})
Extra.BossStatusLabel = BossBox:AddLabel({
    Text = "Auto Boss is off. Boss state: unknown.",
    DoesWrap = true,
})
Extra.UndeadStatusLabel = BossBox:AddLabel({
    Text = "Auto Undead is off.",
    DoesWrap = true,
})

local OrbBox = Tabs.Automation:AddRightGroupbox("Godly Orb", "sparkles")
OrbBox:AddSlider("GodlyOrbClaimDelayMs", {
    Text = "Orb Claim Delay",
    Min = 250,
    Max = 10000,
    Default = 1000,
    Rounding = 0,
    Suffix = " ms",
})
OrbBox:AddButton({
    Text = "Claim Godly Orb",
    Func = function()
        task.spawn(function()
            notify("Godly orb claim fired: " .. tostring(fireGodlyOrbClaim(1, 0)))
        end)
    end,
})
OrbBox:AddCheckbox("ToggleAutoGodlyOrb", {
    Text = "Auto Claim Godly Orb",
    Default = true,
})

local MidasBox = Tabs.Automation:AddRightGroupbox("Midas Bob", "coins")
MidasBox:AddCheckbox("ToggleAutoMidasGold", {
    Text = "Auto Golden Ingot",
    Default = true,
})
MidasBox:AddCheckbox("ToggleAutoMidasHoldAt9", {
    Text = "Hold At 9/10",
    Default = false,
})
MidasBox:AddButton({
    Text = "Collect Held Bar",
    Func = function()
        notify(Extra.collectHeldAutoMidasGoldBar()
            and "Held Midas bar collect fired."
            or "No held Midas bar.")
    end,
})
Extra.AutoMidasStatusLabel = MidasBox:AddLabel({
    Text = "Auto Midas count: 0/10.",
    DoesWrap = true,
})

do
local BuffComboBox = Tabs.Automation:AddRightGroupbox("Buff Combo", "timer-reset")
BuffComboBox:AddDropdown("BuffComboPotion", {
    Text = "Potions",
    Values = Extra.ComboPotionLabels,
    Multi = true,
    AllowNull = true,
    Default = { "Godly Potion", "Rainbow Potion" },
})
BuffComboBox:AddSlider("BuffComboHoldMidasCount", {
    Text = "Hold At Midas Count",
    Min = 1,
    Max = 9,
    Default = 9,
    Rounding = 0,
})
BuffComboBox:AddCheckbox("ToggleBuffComboBuyPotion", {
    Text = "Buy Potion If Missing",
    Default = true,
})
BuffComboBox:AddCheckbox("ToggleBuffComboRequireTotem", {
    Text = "Require Totem",
    Default = true,
})
BuffComboBox:AddCheckbox("ToggleBuffComboFreshTotem", {
    Text = "Require Fresh Totem",
    Default = true,
})
BuffComboBox:AddCheckbox("ToggleBuffComboTrustClientCrate", {
    Text = "Trust Client Crate",
    Default = false,
})
BuffComboBox:AddCheckbox("ToggleBuffCombo", {
    Text = "Run One Buff Combo",
    Default = false,
})
BuffComboBox:AddButton({
    Text = "Print Bob/Crate Debug",
    Func = function()
        task.spawn(function()
            Extra.printBuffComboDebug()
            notify("Printed Bob/crate debug to console.")
        end)
    end,
})
Extra.BuffComboStatusLabel = BuffComboBox:AddLabel({
    Text = "Buff combo is off.",
    DoesWrap = true,
})
Extra.BuffComboInfoLabel = BuffComboBox:AddLabel({
    Text = "Midas boost: unknown\nMidas bar: 0/10\nTotem: unknown\nCrate boost: unknown\nCrate available: unknown",
    DoesWrap = true,
})
end

local GemStormBox = Tabs.Automation:AddRightGroupbox("Gem Storm", "gem")
GemStormBox:AddCheckbox("ToggleAutoGemStorm", {
    Text = "Auto Gem Storm",
    Default = false,
})
GemStormBox:AddCheckbox("ToggleAutoCollectGemStorm", {
    Text = "Auto Collect Gems",
    Default = true,
})

local CleanbotBox = Tabs.Automation:AddRightGroupbox("Cleanbot", "bot")
CleanbotBox:AddButton({
    Text = "Roll Cleanbot Once",
    Func = function()
        notify("Cleanbot roll fired: " .. tostring(fireCleanbotRoll()))
    end,
})
CleanbotBox:AddCheckbox("ToggleAutoCleanbotRoll", {
    Text = "Auto Roll Cleanbot",
    Default = true,
})
CleanbotBox:AddCheckbox("ToggleAutoBestCleanbot", {
    Text = "Auto Equip Best Cleanbot",
    Default = false,
})
Extra.CleanbotStatusLabel = CleanbotBox:AddLabel({
    Text = "Cleanbot automation ready.",
    DoesWrap = true,
})

local PlayerBox = Tabs.Main:AddLeftGroupbox("Player", "person-standing")
PlayerBox:AddCheckbox("ToggleAutoFarm", {
    Text = "Auto Farm",
    Default = false,
})
PlayerBox:AddSlider("PlayerSpeed", {
    Text = "Walk Speed",
    Min = 16,
    Max = 250,
    Default = 50,
    Rounding = 0,
    Suffix = " speed",
})
PlayerBox:AddCheckbox("TogglePlayerSpeed", {
    Text = "Player Speed",
    Default = false,
})

local PalVaultBox = Tabs.Main:AddRightGroupbox("Pals / Vault", "key-round")
PalVaultBox:AddButton({
    Text = "Collect All Pals",
    Func = function()
        task.spawn(function()
            local fired, missing, err = collectAllPals()
            if err then
                notify("Pal route stopped: " .. err)
            else
                notify(string.format("Pal route finished: %d fired, %d unavailable.", fired, missing))
            end
        end)
    end,
})
PalVaultBox:AddButton({
    Text = "Unlock Vault (4629)",
    Func = function()
        notify(unlockVault() and "Vault unlock request fired." or "OpenedSafe remote was not found.")
    end,
})

local InfoBox = Tabs.Main:AddRightGroupbox("Live Tuning", "sliders-horizontal")
InfoBox:AddLabel({
    Text = "Workspace marker: PhosphySlimeCollector",
    DoesWrap = true,
})
InfoBox:AddButton({
    Text = "Stop Collector",
    Func = function()
        Toggles.ToggleHugeCollector:SetValue(false)
        stopCollector()
        notify("Collector stopped.")
    end,
})
InfoBox:AddButton({
    Text = "Start Collector",
    Func = function()
        Toggles.ToggleHugeCollector:SetValue(true)
        startCollector()
        notify("Collector started.")
    end,
})

for _, board in ipairs(Extra.AutoUpgradeBoards) do
    Toggles[upgradeToggleId(board)]:OnChanged(refreshAutoUpgradeLoop)
end
Toggles.ToggleAutoUpgradesMaster:OnChanged(refreshAutoUpgradeLoop)

Toggles.ToggleHugeCollector:OnChanged(function(state)
    if state then
        startCollector()
    else
        stopCollector()
    end
end)

Toggles.ToggleInstantSpawnCollector:OnChanged(function(state)
    if state and Toggles.ToggleHugeCollector and Toggles.ToggleHugeCollector.Value then
        Extra.startInstantSpawnCollector()
    else
        Extra.stopInstantSpawnCollector()
    end
end)

Toggles.ToggleActualRing:OnChanged(function()
    updateMarker()
    resizeActualCollectorRing()
end)

Toggles.ToggleCollectAll:OnChanged(updateMarker)
Toggles.ToggleAutoBeamBoost:OnChanged(function(state)
    if state then
        startBeamBoostLoop()
    else
        stopTask("BeamBoost")
    end
end)
Toggles.ToggleAutoAbilities:OnChanged(function(state)
    if state then
        startAutoAbilitiesLoop()
    else
        stopTask("AutoAbilities")
    end
end)
Toggles.ToggleAutoPotions:OnChanged(function(state)
    if state then
        startAutoPotionsLoop()
    else
        stopTask("AutoPotions")
    end
end)
Toggles.ToggleAutoTotemContact:OnChanged(function(state)
    if state then
        startAutoTotemContact()
    else
        stopTask("AutoTotemContact")
    end
end)
Toggles.ToggleAutoAmuletRoll:OnChanged(function(state)
    if state then
        startAutoAmuletRoll()
    else
        stopTask("AutoAmuletRoll")
        Extra.refreshAmuletVisualSuppression()
        setAmuletStatus(LatestAmuletSummary, true)
    end
end)
Toggles.ToggleAmuletHideRollVisuals:OnChanged(function()
    Extra.refreshAmuletVisualSuppression()
end)
Toggles.ToggleAutoCSlime:OnChanged(function(state)
    if state then
        Extra.startAutoCSlime()
    else
        Extra.stopAutoCSlime()
    end
end)
Toggles.ToggleAutoBlessing:OnChanged(function(state)
    Extra.refreshAutoBlessing()
end)
Toggles.ToggleAutoBlessingSacrifice:OnChanged(function(state)
    Extra.refreshAutoBlessing()
end)
Toggles.ToggleAutoBlessingReroll:OnChanged(function(state)
    Extra.refreshAutoBlessing()
end)
Toggles.ToggleAutoGodlyOrb:OnChanged(function(state)
    if state then
        startGodlyOrbLoop()
    else
        stopTask("GodlyOrb")
    end
end)
Toggles.ToggleAutoPlinko:OnChanged(function(state)
    if state then
        startAutoPlinkoLoop()
    else
        stopTask("AutoPlinko")
    end
end)
Toggles.ToggleAutoCrate:OnChanged(function(state)
    if state then
        startAutoCrateLoop()
    else
        stopTask("AutoCrate")
    end
end)
Toggles.ToggleAutoFallingStars:OnChanged(function()
    refreshFallingStarAutomation()
end)
Toggles.ToggleAutoCollectFallingStars:OnChanged(function()
    refreshFallingStarAutomation()
end)
Toggles.ToggleAutoDailyQuestClaim:OnChanged(function()
    Extra.refreshAutoQuestClaims()
end)
Toggles.ToggleAutoQuestClaim:OnChanged(function()
    Extra.refreshAutoQuestClaims()
end)
Toggles.ToggleAutoBossStart:OnChanged(function()
    Extra.refreshAutoBoss()
end)
Toggles.ToggleAutoBossPayOpen:OnChanged(function()
    Extra.refreshAutoBoss()
end)
Toggles.ToggleAutoBossFight:OnChanged(function()
    Extra.refreshAutoBoss()
end)
Toggles.ToggleAutoBossMove:OnChanged(function(state)
    if state then
        Extra.refreshAutoBoss()
        Extra.refreshAutoUndead()
    else
        Extra.BossMoveCFrame = nil
        Extra.BossMoveUntil = 0
        Extra.BossMoveReason = nil
    end
end)
Toggles.ToggleAutoBossStayAbove:OnChanged(function()
    if Extra.bossMoveEnabled() then
        Extra.updateBossMovementTarget("Boss Hover", 1.5)
    end
end)
Toggles.ToggleAutoBossParry:OnChanged(function()
    if Extra.bossAutomationEnabled() then
        Extra.refreshAutoBoss()
    end
end)
Toggles.ToggleAutoBossSplitPickups:OnChanged(function()
    if Extra.bossAutomationEnabled() then
        Extra.refreshAutoBoss()
    end
end)
Toggles.ToggleAutoBossBuyCards:OnChanged(function(state)
    if not state then
        stopTask("BossCardSpend")
        Extra.BossCardSpendActive = false
    elseif typeof(Extra.BossLastVictoryPayload) == "table" then
        Extra.startBossCardSpendLoop(Extra.BossLastVictoryPayload)
    end
    Extra.refreshAutoBoss()
end)
Toggles.ToggleAutoBossRandomCard:OnChanged(function()
    if Extra.bossAutomationEnabled() then
        Extra.refreshAutoBoss()
    end
end)
Toggles.ToggleAutoBossCloseVictory:OnChanged(function()
    Extra.refreshAutoBoss()
end)
Toggles.ToggleAutoBossRemoveAttackVfx:OnChanged(function()
    Extra.refreshBossAttackVfxCleaner()
end)
Toggles.ToggleAutoUndeadBoss:OnChanged(function()
    Extra.refreshAutoUndead()
end)
Toggles.ToggleAutoUndeadMove:OnChanged(function(state)
    if state then
        Extra.refreshAutoUndead()
    elseif Extra.BossMoveReason == "Undead Mini Boss" then
        Extra.BossMoveCFrame = nil
        Extra.BossMoveUntil = 0
        Extra.BossMoveReason = nil
    end
end)
Toggles.ToggleAutoGemStorm:OnChanged(function(state)
    if state then
        startGemStormLoop()
    else
        stopTask("GemStorm")
    end
end)
Toggles.ToggleAutoCollectGemStorm:OnChanged(function(state)
    if state then
        startGemAutoCollect()
    else
        disconnect("GemBatch")
    end
end)
Toggles.ToggleAutoCleanbotRoll:OnChanged(function(state)
    if state then
        startAutoCleanbotLoop()
    else
        stopTask("AutoCleanbot")
    end
end)
Toggles.ToggleAutoBestCleanbot:OnChanged(function(state)
    if state then
        Extra.startAutoBestCleanbot()
    end
end)
Toggles.ToggleAutoMidasGold:OnChanged(function(state)
    if state then
        connectMidasGoldEvents()
    end
end)
Toggles.ToggleAutoMidasHoldAt9:OnChanged(function(state)
    if not state and Toggles.ToggleAutoMidasGold and Toggles.ToggleAutoMidasGold.Value then
        Extra.collectHeldAutoMidasGoldBar()
    end
end)
Toggles.ToggleBuffCombo:OnChanged(function(state)
    if state then
        Extra.startBuffCombo()
    else
        Extra.stopBuffCombo()
    end
end)
Toggles.ToggleAutoFarm:OnChanged(function(state)
    Marker:SetAttribute("AutoFarmEnabled", state == true)
end)
Toggles.TogglePlayerSpeed:OnChanged(function(state)
    if state then
        startPlayerSpeed()
    else
        stopPlayerSpeed()
    end
end)
Options.CollectorRadius:OnChanged(function()
    updateMarker()
    resizeActualCollectorRing()
end)
Options.CollectorBatchSize:OnChanged(updateMarker)
Options.PlayerSpeed:OnChanged(function()
    if Toggles.TogglePlayerSpeed and Toggles.TogglePlayerSpeed.Value then
        applyPlayerSpeed()
    end
end)
Options.BuffComboPotion:OnChanged(function()
    Extra.updateBuffComboInfo()
end)
function Extra.bindPerformanceHudToggle(toggleId)
    local toggle = Toggles[toggleId]
    if toggle then
        toggle:OnChanged(function()
            Extra.sweepPerfHud()
            if toggleId == "TogglePerfHidePopups" and toggle.Value then
                Extra.sweepPerfPopups()
            end
        end)
    end
end
Extra.bindPerformanceHudToggle("TogglePerfHideStats")
Extra.bindPerformanceHudToggle("TogglePerfHideBoosts")
Extra.bindPerformanceHudToggle("TogglePerfHideTopHud")
Extra.bindPerformanceHudToggle("TogglePerfHideButtons")
Extra.bindPerformanceHudToggle("TogglePerfHideInfo")
Extra.bindPerformanceHudToggle("TogglePerfHidePopups")
Extra.bindPerformanceHudToggle("TogglePerfHideHud")

Toggles.TogglePerfHideSlimes:OnChanged(function(state)
    if state and Toggles.TogglePerfAutoHideNewSlimes and Toggles.TogglePerfAutoHideNewSlimes.Value then
        Extra.sweepPerfSlimes()
        Extra.startPerfSlimeWatcher()
    else
        Extra.stopPerfSlimeWatcher()
    end
end)
Toggles.TogglePerfAutoHideNewSlimes:OnChanged(function(state)
    if state and Toggles.TogglePerfHideSlimes and Toggles.TogglePerfHideSlimes.Value then
        Extra.sweepPerfSlimes()
        Extra.startPerfSlimeWatcher()
    else
        Extra.stopPerfSlimeWatcher()
    end
end)

Library:OnUnload(function()
    Marker:SetAttribute("Session", "unloaded-" .. tostring(os.clock()))
    Marker:SetAttribute("Enabled", false)
    stopPlayerSpeed()
    Extra.stopPerformance()
    Extra.stopPerfSlimeWatcher()
    stopTask("AmuletVisualCleanup")
    Extra.restoreAmuletVisualConnections()

    for name in pairs(Tasks) do
        stopTask(name)
    end

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
SaveManager:SetFolder("PhosphyHub/slimeinc")
SaveManager:SetSubFolder("Collector")
SaveManager:RegisterCustomData("BlessingPickPriorityOrder", function()
    local savedOrder = {}
    for index, label in ipairs(Extra.BlessingPickPriority or {}) do
        savedOrder[index] = label
    end
    return savedOrder
end, function(savedOrder)
    task.delay(0.1, function()
        Extra.restoreBlessingPickPriority(savedOrder)
    end)
end)
SaveManager:BuildConfigSection(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()

if Options.CollectorRadius.Value < 5000 then
    Options.CollectorRadius:SetValue(5000)
end
if Options.AutoAmuletRollDelayMs.Value > 50 then
    Options.AutoAmuletRollDelayMs:SetValue(50)
end

startRingVisual()
startMovementCoordinator()
connectMidasGoldEvents()
enableFastAmulets()
Extra.resetAutoMidasCount("session")
if Toggles.ToggleHugeCollector.Value then
    startCollector()
end
if Toggles.ToggleAutoGodlyOrb.Value then
    startGodlyOrbLoop()
end
if Toggles.ToggleAutoAbilities.Value then
    startAutoAbilitiesLoop()
end
if Toggles.ToggleAutoPotions.Value then
    startAutoPotionsLoop()
end
if Toggles.ToggleAutoTotemContact.Value then
    startAutoTotemContact()
end
if Toggles.ToggleBuffCombo.Value then
    Extra.startBuffCombo()
end
connectAmuletEvents()
if Toggles.ToggleAutoAmuletRoll.Value then
    startAutoAmuletRoll()
end
if Toggles.ToggleAutoCSlime.Value then
    Extra.startAutoCSlime()
end
if Extra.autoBlessingEnabled() then
    Extra.startAutoBlessing()
end
if Toggles.ToggleAutoPlinko.Value then
    startAutoPlinkoLoop()
end
if Toggles.ToggleAutoCrate.Value then
    startAutoCrateLoop()
end
if Toggles.ToggleAutoFallingStars.Value or Toggles.ToggleAutoCollectFallingStars.Value then
    startFallingStarAutomation()
end
if Extra.autoQuestClaimsEnabled() then
    Extra.startAutoQuestClaims()
end
task.defer(Extra.refreshBossCoinCount)
if Extra.bossAttackVfxRemovalEnabled() then
    Extra.startBossAttackVfxCleaner()
end
if Extra.bossAutomationEnabled() then
    Extra.startAutoBossLoop()
end
if Extra.undeadEnabled() then
    Extra.startAutoUndeadLoop()
end
if Toggles.ToggleAutoGemStorm.Value then
    startGemStormLoop()
end
if Toggles.ToggleAutoCollectGemStorm.Value then
    startGemAutoCollect()
end
if Toggles.ToggleAutoBestCleanbot.Value then
    Extra.startAutoBestCleanbot()
end
if Toggles.ToggleAutoCleanbotRoll.Value then
    startAutoCleanbotLoop()
end
if Toggles.TogglePlayerSpeed.Value then
    startPlayerSpeed()
end
if anyAutoUpgradeEnabled() then
    startAutoUpgradeLoop()
end

Extra.startBuffComboInfoLoop()
notify("slimeinc loaded.")
