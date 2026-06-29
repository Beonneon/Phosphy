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
    Version = "1.2.1",
    PerfLighting = game:GetService("Lighting"),
    BlessingActionPending = false,
    BlessingActionSerial = 0,
    CleanbotRollPending = false,
    CleanbotRollSerial = 0,
    SpawnIdQueue = {},
    SpawnIdQueued = {},
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
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
    end
    return remotes
end

local function getRemote(name, waitSeconds)
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild(name) or remotes:WaitForChild(name, waitSeconds or 10)
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
        local ok, profile = pcall(DataController.get)
        if ok and typeof(profile) == "table" then
            return profile
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

local function canFireReadyAction(name, minimumDelay)
    local now = os.clock()
    local lastFiredAt = ReadyActionLastFiredAt[name] or 0
    if now - lastFiredAt < (minimumDelay or 2) then
        return false
    end

    ReadyActionLastFiredAt[name] = now
    return true
end

local function getCollectSlimesRemote()
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild("CollectSlimes") or remotes:WaitForChild("CollectSlimes", 10)
end

local function getActivateEmpoweredBoostRemote()
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild("ActivateEmpoweredBoost") or remotes:WaitForChild("ActivateEmpoweredBoost", 10)
end

local function getUsePotionRemote()
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild("UsePotion") or remotes:WaitForChild("UsePotion", 10)
end

local function getActivatePlinkoBallRemote()
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild("ActivatePlinkoBall") or remotes:WaitForChild("ActivatePlinkoBall", 10)
end

local function getCrateCollectedRemote()
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild("CrateCollected") or remotes:WaitForChild("CrateCollected", 10)
end

local function getGodlyOrbCollectedRemote()
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild("GodlyOrbCollected") or remotes:WaitForChild("GodlyOrbCollected", 10)
end

local function getGemBobAbilityRequestedRemote()
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild("GemBobAbilityRequested") or remotes:WaitForChild("GemBobAbilityRequested", 10)
end

local function getGemBobGemBatchRemote()
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild("GemBobGemBatch") or remotes:WaitForChild("GemBobGemBatch", 10)
end

local function getCollectGemBobGemsRemote()
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild("CollectGemBobGems") or remotes:WaitForChild("CollectGemBobGems", 10)
end

local function getRollRoombaRemote()
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild("RollRoomba") or remotes:WaitForChild("RollRoomba", 10)
end

local function getRoombaRollResultRemote()
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild("RoombaRollResult") or remotes:WaitForChild("RoombaRollResult", 10)
end

local function getActivateStardustMachineRemote()
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild("ActivateStardustMachine") or remotes:WaitForChild("ActivateStardustMachine", 10)
end

local function getStardustStarFallingRemote()
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild("StardustStarFalling") or remotes:WaitForChild("StardustStarFalling", 10)
end

local function getFallingStarAwardedRemote()
    local remotes = getRemotes()
    if not remotes then
        return nil
    end
    return remotes:FindFirstChild("FallingStarAwarded") or remotes:WaitForChild("FallingStarAwarded", 10)
end

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

local function collectNearbyOnce()
    local slimes = getSlimesFolder()
    local root = getRoot()
    if not slimes or not root then
        return 0
    end

    local now = os.clock()
    local radius = getRadius()
    local batchSize = getBatchSize()
    local retryDelay = getRetryDelay()
    local collectAll = Toggles.ToggleCollectAll and Toggles.ToggleCollectAll.Value
    local candidates = {}

    for _, slime in ipairs(slimes:GetChildren()) do
        local id = getSlimeId(slime)
        if id and (not LastSentAt[id] or now - LastSentAt[id] >= retryDelay) then
            local position = getSlimePosition(slime)
            if position then
                local distance = (position - root.Position).Magnitude
                if collectAll or distance <= radius then
                    table.insert(candidates, {
                        Id = id,
                        Distance = distance,
                    })
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        return a.Distance < b.Distance
    end)

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

local function isStardustMachineReady()
    local label = getStardustCooldownLabel()
    if not isReadyLabel(label) then
        return false
    end

    local gui = label:FindFirstAncestorWhichIsA("BillboardGui") or label:FindFirstAncestorWhichIsA("SurfaceGui")
    return not gui or gui.Enabled
end

local function requestFallingStarBoost()
    if not isStardustMachineReady() or not canFireReadyAction("StardustMachine", 3) then
        return false
    end

    local remote = getActivateStardustMachineRemote()
    if not remote then
        notify("ActivateStardustMachine remote was not found.")
        return false
    end

    remote:FireServer()
    Marker:SetAttribute("StardustMachineLastRequest", Workspace:GetServerTimeNow())
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
        while (Toggles.ToggleAutoFallingStars and Toggles.ToggleAutoFallingStars.Value)
            or (Toggles.ToggleAutoCollectFallingStars and Toggles.ToggleAutoCollectFallingStars.Value) do
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

local function collectMidasGoldBar(id, position)
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

local function connectMidasGoldEvents()
    local spawned = getRemote("GoldBarSpawned", 10)
    if spawned and not Connections.MidasGoldBarSpawned then
        Connections.MidasGoldBarSpawned = spawned.OnClientEvent:Connect(function(id, position)
            Marker:SetAttribute("MidasLastGoldBarSpawnedAt", Workspace:GetServerTimeNow())
            if Toggles.ToggleAutoMidasGold and Toggles.ToggleAutoMidasGold.Value then
                task.spawn(collectMidasGoldBar, id, position)
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

local AutoUpgradeBoards = {
    {
        id = "Main",
        name = "Main",
        icon = "house",
        entries = {
            { label = "EXP Multiplier", key = "levelMultiplier" },
            { label = "Slime Cooldown", key = "spawnRate" },
            { label = "Slime Max Cap", key = "maxCap" },
            { label = "Slime Tier", key = "slimeTier" },
            { label = "Slime Value", key = "slimeValue" },
        },
    },
    {
        id = "Lvl5",
        name = "Level 5",
        icon = "sparkles",
        entries = {
            { label = "Slime Value (SP)", key = "slimeValue2" },
            { label = "More Slimes", key = "moreSlimes" },
            { label = "Collecting Area", key = "collectingRadius" },
            { label = "Shiny Spawn Chance", key = "shinyChance" },
            { label = "Player Movespeed", key = "playerMovespeed" },
        },
    },
    {
        id = "Lvl25",
        name = "Level 25",
        icon = "gem",
        entries = {
            { label = "Gem Spawn Chance", key = "gemSpawnChance" },
            { label = "Holy Orb Cooldown", key = "holyBeamCooldown" },
            { label = "Holy Orb Duration", key = "longerHolyBeam" },
            { label = "Holy Orb", key = "holyBeam" },
            { label = "Gem Value (SP)", key = "gemValue2" },
            { label = "Gem Value", key = "gemValue" },
            { label = "Gem Tier", key = "gemTier" },
        },
    },
    {
        id = "Lvl50",
        name = "Level 50",
        icon = "zap",
        entries = {
            { label = "Beam Cooldown", key = "beamCooldown" },
            { label = "More Slimes", key = "moreSlimes2" },
            { label = "Beam Size", key = "beamSize" },
            { label = "Beam", key = "beam" },
            { label = "Shiny Multiplier", key = "shinyMultiplier" },
        },
    },
    {
        id = "Lvl75",
        name = "Level 75",
        icon = "bot",
        entries = {
            { label = "Cleanbot Size", key = "roombaSize" },
            { label = "Cleanbot Speed", key = "roombaSpeed" },
            { label = "Cleanbot", key = "roomba" },
        },
    },
    {
        id = "Tier15",
        name = "Tier 15",
        icon = "crown",
        entries = {
            { label = "Slime Tier", key = "slimeTier2" },
            { label = "Shiny Spawn Chance", key = "shinyChance2" },
            { label = "Titanic Slime Chance", key = "titanicSlimeChance" },
            { label = "Auto Holy Orb", key = "autoHolyBeam" },
            { label = "Giant Slime Chance", key = "giantSlimeChance" },
            { label = "EXP Multiplier", key = "levelMultiplier2" },
        },
    },
    {
        id = "Lvl150",
        name = "Level 150",
        icon = "bug",
        entries = {
            { label = "Glitch Chance", key = "corruptChance" },
            { label = "EXP Multiplier", key = "levelMultiplier3" },
            { label = "Glitch Power", key = "corruptPower" },
            { label = "More Slimes", key = "moreSlimes3" },
            { label = "Corrupted Slime Max Cap", key = "corruptedSlimeMaxCap" },
            { label = "Corrupted Slime Cooldown", key = "corruptedSlimeCooldown" },
            { label = "Corrupted Slime Value", key = "corruptedSlimeValue" },
        },
    },
    {
        id = "Lvl200",
        name = "Level 200",
        icon = "circle-dot",
        entries = {
            { label = "Void Orb", key = "void" },
            { label = "Void Multiplier", key = "voidMultiplier" },
            { label = "Void Orb Cooldown", key = "voidCooldown" },
            { label = "Void Orb Duration", key = "voidDuration" },
        },
    },
    {
        id = "Lvl250",
        name = "Level 250",
        icon = "star",
        entries = {
            { label = "Auto Void Orb", key = "autoVoid" },
            { label = "Lucky Rush", key = "luckyRush" },
            { label = "Lucky Rush Power", key = "luckyRushPower" },
            { label = "Lucky Rush Cooldown", key = "luckyRushCooldown" },
        },
    },
    {
        id = "Lvl350",
        name = "Level 350",
        icon = "sparkles",
        entries = {
            { label = "Godly Slime Chance", key = "godlySlimeChance" },
        },
    },
    {
        id = "Lvl400",
        name = "Level 400",
        icon = "meteor",
        entries = {
            { label = "Stardust Multiplier", key = "stardustMultiplier" },
            { label = "Falling Stars Luck", key = "fallingStarsLuck" },
            { label = "Stardust Machine Cooldown", key = "stardustMachineCooldown" },
            { label = "More Falling Stars", key = "moreFallingStars" },
        },
    },
}

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

    for _, board in ipairs(AutoUpgradeBoards) do
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
            for _, board in ipairs(AutoUpgradeBoards) do
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

function Extra.blessingIsWhitelisted(definition)
    return Extra.blessingRuleSelected("BlessingSacrificeWhitelist", definition)
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

    for _, field in ipairs({ "key", "name", "id", "blessing" }) do
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
        if count > 0 and Extra.blessingIsWhitelisted(definition) and not Extra.blessingIsBlacklisted(definition) then
            local rank = Extra.BlessingRarityRank[definition.rarity] or 0
            if rank < bestRank then
                best = definition
                bestRank = rank
            end
        end
    end
    return best
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

    local remote = getRemote("BlessingResult", 10)
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
            Extra.BlessingRetryAfter = now + 5
            Extra.setBlessingStatus("Blessing request rejected or unavailable. Retrying in 5 seconds.")
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

    local activateRemote = getRemote("ActivateBlessing", 10)
    local rerollRemote = getRemote("RerollBlessing", 10)
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

            local pendingRerollRemote = getRemote("RerollPendingBlessings", 10)
            if not pendingRerollRemote then
                Extra.setBlessingStatus("RerollPendingBlessings remote was not found.")
                return false
            end

            Extra.BlessingPendingOptions = nil
            Extra.markBlessingActionPending(1.5)
            pendingRerollRemote:FireServer()
            Marker:SetAttribute("BlessingLastPendingRerollAt", now)
            Extra.setBlessingStatus("Rerolling offered choices without sacrificing...")
            return true
        end

        Extra.BlessingPendingOptions = nil
        Extra.markBlessingActionPending(1.5)
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
        Extra.markBlessingActionPending(1.5)
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
        return false
    end

    local sacrifice = Extra.findSacrificialBlessing(profile)
    if sacrifice then
        Extra.markBlessingActionPending(1.5)
        rerollRemote:FireServer(sacrifice.key)
        Extra.setBlessingStatus("Sacrificing " .. sacrifice.label .. " for a new roll.")
        Marker:SetAttribute("BlessingLastSacrifice", sacrifice.key)
        return true
    end

    Extra.setBlessingStatus("Waiting for a whitelisted owned blessing to sacrifice.")
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
        Connections.TotemSpawned = spawned.OnClientEvent:Connect(function(id)
            if rememberTotemId(id) and Toggles.ToggleAutoTotemContact and Toggles.ToggleAutoTotemContact.Value then
                task.defer(claimTotemId, id, true)
            end
        end)
    end

    local cleared = getRemote("TotemCleared", 10)
    if cleared and not Connections.TotemCleared then
        Connections.TotemCleared = cleared.OnClientEvent:Connect(function(id)
            if typeof(id) == "string" or typeof(id) == "number" then
                TotemIds[tostring(id)] = nil
                updateTotemMarker()
            end
        end)
    end
end

local function startAutoTotemContact()
    connectTotemEvents()
    claimKnownTotems()
end

local AmuletCountValues = { "1", "2", "3", "4" }

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

local function setAmuletStatus(text)
    LatestAmuletSummary = tostring(text or "No amulet roll yet.")

    local markerText = LatestAmuletSummary
    if #markerText > 1024 then
        markerText = markerText:sub(1, 1021) .. "..."
    end

    Marker:SetAttribute("AmuletLatestInfo", markerText)

    if AmuletStatusLabel then
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
    local count = #getOrderedAmuletOptionKeys(options)
    if isSelectedAmuletCount(count) then
        return count, nil
    end

    return nil, nil
end

local function summarizeAmuletRoll(options, rollId, target, targetIndex)
    local lines = {}
    if target then
        lines[#lines + 1] = "Roll " .. tostring(rollId or "?") .. " hit selected count: " .. tostring(target) .. " option(s)."
    else
        lines[#lines + 1] = "Roll " .. tostring(rollId or "?") .. " did not hit a selected option count."
    end

    if typeof(options) ~= "table" then
        lines[#lines + 1] = "Payload: " .. tostring(options)
        return table.concat(lines, "\n")
    end

    local count = 0
    for _, key in ipairs(getOrderedAmuletOptionKeys(options)) do
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

    AmuletPickPending = true
    remote:FireServer(choice, LatestAmuletRollId)
    Marker:SetAttribute("AmuletLastPicked", choice)
    Marker:SetAttribute("AmuletLastPickRollId", tostring(LatestAmuletRollId))
    Marker:SetAttribute("AmuletLastPickAt", Workspace:GetServerTimeNow())

    if not quiet then
        notify("Amulet pick fired: " .. tostring(choice))
    end

    task.delay(0.35, function()
        AmuletPickPending = false
    end)

    return true
end

local function connectAmuletEvents()
    local rollResult = getRemote("AmuletRollResult", 10)
    if not rollResult then
        notify("AmuletRollResult remote was not found.")
        return false
    end

    if not Connections.AmuletRollResult then
        Connections.AmuletRollResult = rollResult.OnClientEvent:Connect(function(options, rollId)
            AmuletRollPending = false
            AmuletChoicePending = true
            AmuletPickPending = false
            LatestAmuletRollId = rollId

            local target, targetIndex = findSelectedAmuletTarget(options)
            LatestAmuletTarget = target
            LatestAmuletTargetIndex = targetIndex
            setAmuletStatus(summarizeAmuletRoll(options, rollId, target, targetIndex))

            Marker:SetAttribute("AmuletLastRollId", tostring(rollId))
            Marker:SetAttribute("AmuletLastTarget", target or "")
            Marker:SetAttribute("AmuletLastTargetIndex", targetIndex and tostring(targetIndex) or "")
            Marker:SetAttribute("AmuletLastResultAt", Workspace:GetServerTimeNow())

            if target then
                if Toggles.ToggleAutoAmuletRoll and Toggles.ToggleAutoAmuletRoll.Value then
                    Toggles.ToggleAutoAmuletRoll:SetValue(false)
                end

                notify("Amulet roll hit " .. tostring(target) .. " option(s). Choose Select New or Keep Old.")
                return
            end

            if Toggles.ToggleAutoAmuletRoll and Toggles.ToggleAutoAmuletRoll.Value then
                task.defer(function()
                    if Toggles.ToggleAutoAmuletRoll and Toggles.ToggleAutoAmuletRoll.Value then
                        pickLatestAmulet("OLD", true)
                    end
                end)
            end
        end)
    end

    local pickResult = getRemote("AmuletPickResult", 2)
    if pickResult and not Connections.AmuletPickResult then
        Connections.AmuletPickResult = pickResult.OnClientEvent:Connect(function(choice, rollId, ok, message)
            if rollId == LatestAmuletRollId then
                AmuletPickPending = false
                if ok == true then
                    AmuletChoicePending = false
                end
            end

            Marker:SetAttribute("AmuletLastPickResult", tostring(ok))
            Marker:SetAttribute("AmuletLastPickMessage", tostring(message or ""))
            Marker:SetAttribute("AmuletLastPickChoice", tostring(choice or ""))
        end)
    end

    return true
end

rollAmuletOnce = function()
    enableFastAmulets()
    connectAmuletEvents()

    if AmuletRollPending or AmuletChoicePending then
        return false
    end

    local remote = getRemote("RollAmulet", 10)
    if not remote then
        notify("RollAmulet remote was not found.")
        return false
    end

    AmuletRollPending = true
    remote:FireServer()
    Marker:SetAttribute("AmuletRolledAt", Workspace:GetServerTimeNow())
    setAmuletStatus("Rolling amulet...")

    task.delay(3, function()
        if AmuletRollPending then
            AmuletRollPending = false
            setAmuletStatus("Amulet roll timed out. Try Roll Once again.")
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

    connectAmuletEvents()
    Tasks.AutoAmuletRoll = task.spawn(function()
        while Toggles.ToggleAutoAmuletRoll and Toggles.ToggleAutoAmuletRoll.Value do
            if not AmuletRollPending then
                rollAmuletOnce()
            end
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
    if gui then
        count += Extra.setPerfGuiRoot(gui:FindFirstChild("Stats"), Extra.perfToggle("TogglePerfHideStats", true))
        count += Extra.setPerfGuiRoot(gui:FindFirstChild("Boosts"), Extra.perfToggle("TogglePerfHideBoosts", true))
        count += Extra.setPerfGuiRoot(gui:FindFirstChild("Lvl"), Extra.perfToggle("TogglePerfHideTopHud", true))
        count += Extra.setPerfGuiRoot(gui:FindFirstChild("Capacity"), Extra.perfToggle("TogglePerfHideTopHud", true))
        count += Extra.setPerfGuiRoot(gui:FindFirstChild("Abilities"), Extra.perfToggle("TogglePerfHideButtons", true))
        count += Extra.setPerfGuiRoot(gui:FindFirstChild("Options"), Extra.perfToggle("TogglePerfHideButtons", true))
        count += Extra.setPerfGuiRoot(gui:FindFirstChild("DailyQuestHud"), Extra.perfToggle("TogglePerfHideInfo", true))
    end

    count += Extra.setPerfGuiRoot(Extra.perfPlayerGui() and Extra.perfPlayerGui():FindFirstChild("InfoInterface"), Extra.perfToggle("TogglePerfHideInfo", true))
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
        addAutoUpgradeBoardTab(tabbox, AutoUpgradeBoards[index])
    end
end

do
local BlessingRulesBox = Tabs.Blessings:AddLeftGroupbox("Sacrifice Rules", "list-checks")
BlessingRulesBox:AddDropdown("BlessingSacrificeWhitelist", {
    Text = "Sacrifice Whitelist",
    Values = Extra.BlessingLabels,
    Multi = true,
    AllowNull = true,
    Default = {},
})
BlessingRulesBox:AddDropdown("BlessingSacrificeBlacklist", {
    Text = "Protected Blacklist",
    Values = Extra.BlessingLabels,
    Multi = true,
    AllowNull = true,
    Default = {},
})
BlessingRulesBox:AddButton({
    Text = "Clear Whitelist",
    Func = function()
        Options.BlessingSacrificeWhitelist:SetValue({})
    end,
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
        notify("Collected " .. tostring(collectNearbyOnce()) .. " slime id(s).")
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
AmuletBox:AddDropdown("AmuletOptionCounts", {
    Text = "Stop On Option Count",
    Values = AmuletCountValues,
    Multi = true,
    AllowNull = true,
    Default = { "4" },
})
AmuletBox:AddSlider("AutoAmuletRollDelayMs", {
    Text = "Roll Delay",
    Min = 0,
    Max = 500,
    Default = 50,
    Rounding = 0,
    Suffix = " ms",
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

for _, board in ipairs(AutoUpgradeBoards) do
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
    end
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

Library:OnUnload(function()
    Marker:SetAttribute("Session", "unloaded-" .. tostring(os.clock()))
    Marker:SetAttribute("Enabled", false)
    stopPlayerSpeed()
    Extra.stopPerformance()

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

notify("slimeinc loaded.")
