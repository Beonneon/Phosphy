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
local CleanbotRollPending = false
local CleanbotRollSerial = 0
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
local LastVisitedTotemArea = nil
local TotemAutofarmResumeAt = 0
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

    local autoFarm = Toggles.ToggleAutoFarm and Toggles.ToggleAutoFarm.Value
    local autoTotem = Toggles.ToggleAutoTotemContact and Toggles.ToggleAutoTotemContact.Value
    local totemCFrame, totemArea = getTotemAreaCFrame()
    if not totemArea then
        LastVisitedTotemArea = nil
    elseif (autoFarm or autoTotem) and totemCFrame and totemArea ~= LastVisitedTotemArea then
        LastVisitedTotemArea = totemArea
        TotemAutofarmResumeAt = os.clock() + 0.75
        Marker:SetAttribute("TotemTeleportedAt", Workspace:GetServerTimeNow())
        return totemCFrame, "Totem Teleport"
    end

    if autoFarm then
        if os.clock() < TotemAutofarmResumeAt then
            return nil, "Totem Contact"
        end
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
    local current = tonumber(LocalPlayer:GetAttribute("EmpoweredStack")) or 0
    local missing = math.max(0, 10 - math.floor(current))
    if missing == 0 then
        return 0
    end

    return fireEmpoweredBoostStack(missing, 0.08)
end

local function getPlinkoMachine()
    local zones = Workspace:FindFirstChild("Zones", true)
    local lvl10 = zones and zones:FindFirstChild("Lvl10")
    local machine = lvl10 and lvl10:FindFirstChild("PlinkoBallMachine")
    return machine or Workspace:FindFirstChild("PlinkoBallMachine", true)
end

local function getPlinkoCooldownLabel()
    local zones = Workspace:FindFirstChild("Zones", true)
    local lvl10 = zones and zones:FindFirstChild("Lvl10")
    local field = lvl10 and lvl10:FindFirstChild("PlinkoBallField")
    local mainPart = field and field:FindFirstChild("mainpart")
    local cooldownGui = mainPart and mainPart:FindFirstChild("CooldownGui")
    local cooldown = cooldownGui and cooldownGui:FindFirstChild("Cooldown")
    return cooldown and cooldown:IsA("TextLabel") and cooldown or nil
end

local function isReadyLabel(label)
    return label ~= nil and tostring(label.Text):upper():match("^%s*READY%s*$") ~= nil
end

local function isPlinkoReady()
    return isReadyLabel(getPlinkoCooldownLabel())
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
    if not isPlinkoReady() or not canFireReadyAction("Plinko", 2) then
        return 0
    end

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

local function collectFallingStarPosition(position)
    local root = getRoot()
    if not (root and typeof(position) == "Vector3") then
        return false
    end

    local holdSeconds = 0.25
    setFallingStarMovementTarget(position, holdSeconds + 0.15)
    root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
    task.wait(holdSeconds)

    return true
end

local function collectFallingStars(position)
    local maxStars = 8
    local collected = 0

    if position and collectFallingStarPosition(position) then
        collected += 1
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
            local position
            for _, value in ipairs(args) do
                position = payloadToPosition(value)
                if position then
                    break
                end
            end

            task.delay(1.5, function()
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

local fireCleanbotRoll

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
        CleanbotRollPending = false
        Marker:SetAttribute("CleanbotLastResult", tostring(cleanbot))
        Marker:SetAttribute("CleanbotLastWasNew", isNew == true)
        Marker:SetAttribute("CleanbotLastResultTime", Workspace:GetServerTimeNow())

        if Toggles.ToggleAutoCleanbotRoll and Toggles.ToggleAutoCleanbotRoll.Value then
            task.delay(0.05, function()
                if Toggles.ToggleAutoCleanbotRoll and Toggles.ToggleAutoCleanbotRoll.Value then
                    fireCleanbotRoll()
                end
            end)
        end
    end)
    return true
end

fireCleanbotRoll = function()
    if CleanbotRollPending then
        return false
    end

    local remote = getRollRoombaRemote()
    if not remote or not startCleanbotResultListener() then
        notify("RollRoomba remote was not found.")
        return false
    end

    CleanbotRollPending = true
    CleanbotRollSerial += 1
    local serial = CleanbotRollSerial
    remote:FireServer()
    Marker:SetAttribute("CleanbotRollLastFire", Workspace:GetServerTimeNow())

    task.delay(5, function()
        if CleanbotRollPending and CleanbotRollSerial == serial then
            CleanbotRollPending = false
            if Toggles.ToggleAutoCleanbotRoll and Toggles.ToggleAutoCleanbotRoll.Value then
                fireCleanbotRoll()
            end
        end
    end)

    return true
end

local function startBeamBoostLoop()
    stopTask("BeamBoost")

    Tasks.BeamBoost = task.spawn(function()
        while Toggles.ToggleAutoBeamBoost and Toggles.ToggleAutoBeamBoost.Value do
            local fired = maxEmpoweredBoost()

            if fired > 0 then
                Marker:SetAttribute("BeamBoostLastTopUp", fired)
            end

            task.wait(0.5)
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
            task.wait(0.5)
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
end

local Window = Library:CreateWindow({
    Title = "slimeinc",
    Footer = "disc : neonbeon | slimeinc",
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
    ["UI Settings"] = Window:AddTab("UI Settings", "folder-cog"),
}

local CollectorBox = Tabs.Main:AddLeftGroupbox("Collector", "magnet")
CollectorBox:AddCheckbox("ToggleHugeCollector", {
    Text = "Auto Collect Slimes",
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
            notify(fired > 0 and "Plinko 4x fired." or "Plinko is not ready yet.")
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

Toggles.ToggleHugeCollector:OnChanged(function(state)
    if state then
        startCollector()
    else
        stopCollector()
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
        LastVisitedTotemArea = nil
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
Toggles.ToggleAutoMidasGold:OnChanged(function(state)
    if state then
        connectMidasGoldEvents()
    end
end)
Toggles.ToggleAutoFarm:OnChanged(function(state)
    Marker:SetAttribute("AutoFarmEnabled", state == true)
    if state then
        LastVisitedTotemArea = nil
    end
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

Library:OnUnload(function()
    Marker:SetAttribute("Session", "unloaded-" .. tostring(os.clock()))
    Marker:SetAttribute("Enabled", false)
    stopPlayerSpeed()

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
if Toggles.ToggleAutoCleanbotRoll.Value then
    startAutoCleanbotLoop()
end
if Toggles.TogglePlayerSpeed.Value then
    startPlayerSpeed()
end

notify("slimeinc loaded.")
