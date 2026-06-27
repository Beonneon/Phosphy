local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local PhosphyRepo = "https://raw.githubusercontent.com/Beonneon/Phosphy/refs/heads/main/"

local Library = loadstring(game:HttpGet(PhosphyRepo .. "LibraryV3.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(PhosphyRepo .. "SaveManagerV3.lua"))()

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
    return math.max(0, getNumberOption("CollectorRetryMs", 300) / 1000)
end

local function getTickDelay()
    return math.max(0.01, getNumberOption("CollectorTickMs", 50) / 1000)
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

local function getPlinkoMachine()
    local zones = Workspace:FindFirstChild("Zones", true)
    local lvl10 = zones and zones:FindFirstChild("Lvl10")
    local machine = lvl10 and lvl10:FindFirstChild("PlinkoBallMachine")
    return machine or Workspace:FindFirstChild("PlinkoBallMachine", true)
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

local function firePlinko4x(count, delaySeconds)
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

    count = math.max(1, math.floor(tonumber(count) or 1))
    delaySeconds = math.max(0, tonumber(delaySeconds) or 0.15)

    local fired = 0
    for index = 1, count do
        local part = parts[((index - 1) % #parts) + 1]
        remote:FireServer()
        task.wait(math.max(0.1, delaySeconds))
        remote:FireServer(part)
        fired += 1
        if delaySeconds > 0 then
            task.wait(delaySeconds)
        end
    end

    return fired
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

local function fireGemStorm()
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
        Marker:SetAttribute("CleanbotLastResult", tostring(cleanbot))
        Marker:SetAttribute("CleanbotLastWasNew", isNew == true)
        Marker:SetAttribute("CleanbotLastResultTime", Workspace:GetServerTimeNow())
    end)
    return true
end

local function fireCleanbotRoll()
    local remote = getRollRoombaRemote()
    if not remote or not startCleanbotResultListener() then
        notify("RollRoomba remote was not found.")
        return false
    end

    remote:FireServer()
    Marker:SetAttribute("CleanbotRollLastFire", Workspace:GetServerTimeNow())
    return true
end

local function startBeamBoostLoop()
    stopTask("BeamBoost")

    Tasks.BeamBoost = task.spawn(function()
        while Toggles.ToggleAutoBeamBoost and Toggles.ToggleAutoBeamBoost.Value do
            local fired = fireEmpoweredBoostStack(
                getNumberOption("BeamBoostCount", 10),
                getNumberOption("BeamBoostFireDelayMs", 80) / 1000
            )

            if fired > 0 then
                notify("Beam boost max fired: " .. tostring(fired))
            end

            task.wait(math.max(1, getNumberOption("BeamBoostRefreshSeconds", 25)))
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
            firePlinko4x(
                getNumberOption("Plinko4xFireCount", 1),
                getNumberOption("DropBoostDelayMs", 150) / 1000
            )
            task.wait(math.max(1, getNumberOption("AutoDropBoostIntervalSeconds", 30)))
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
            task.wait(math.max(1, getNumberOption("GemStormRetrySeconds", 5)))
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
    startCleanbotResultListener()

    Tasks.AutoCleanbot = task.spawn(function()
        while Toggles.ToggleAutoCleanbotRoll and Toggles.ToggleAutoCleanbotRoll.Value do
            fireCleanbotRoll()
            task.wait(math.max(0.25, getNumberOption("CleanbotRollIntervalMs", 1000) / 1000))
        end
    end)
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
    Main = Window:AddTab("Main", "circle"),
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
CollectorBox:AddSlider("CollectorTickMs", {
    Text = "Loop Delay",
    Min = 10,
    Max = 1000,
    Default = 50,
    Rounding = 0,
    Suffix = " ms",
})
CollectorBox:AddSlider("CollectorRetryMs", {
    Text = "Retry Delay",
    Min = 0,
    Max = 5000,
    Default = 300,
    Rounding = 0,
    Suffix = " ms",
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
        Options.CollectorTickMs:SetValue(25)
        resizeActualCollectorRing()
        updateMarker()
        notify("Really big collector preset applied.")
    end,
})

local BeamBoostBox = Tabs.Main:AddRightGroupbox("Beam Boost", "zap")
BeamBoostBox:AddSlider("BeamBoostCount", {
    Text = "Max Fire Count",
    Min = 1,
    Max = 30,
    Default = 10,
    Rounding = 0,
    Suffix = " fires",
})
BeamBoostBox:AddSlider("BeamBoostFireDelayMs", {
    Text = "Fire Delay",
    Min = 0,
    Max = 1000,
    Default = 80,
    Rounding = 0,
    Suffix = " ms",
})
BeamBoostBox:AddSlider("BeamBoostRefreshSeconds", {
    Text = "Auto Refresh",
    Min = 1,
    Max = 60,
    Default = 25,
    Rounding = 0,
    Suffix = " s",
})
BeamBoostBox:AddButton({
    Text = "Max Beam Boost",
    Func = function()
        task.spawn(function()
            local fired = fireEmpoweredBoostStack(
                getNumberOption("BeamBoostCount", 10),
                getNumberOption("BeamBoostFireDelayMs", 80) / 1000
            )
            notify("Beam boost max fired: " .. tostring(fired))
        end)
    end,
})
BeamBoostBox:AddCheckbox("ToggleAutoBeamBoost", {
    Text = "Auto Keep Max",
    Default = false,
})

local AbilityBox = Tabs.Main:AddRightGroupbox("Abilities", "wand-sparkles")
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

local DropBoostBox = Tabs.Main:AddRightGroupbox("Plinko / Crates", "gift")
DropBoostBox:AddSlider("Plinko4xFireCount", {
    Text = "Plinko 4x Fires",
    Min = 1,
    Max = 25,
    Default = 1,
    Rounding = 0,
    Suffix = " fires",
})
DropBoostBox:AddSlider("DropBoostDelayMs", {
    Text = "Fire Delay",
    Min = 0,
    Max = 1000,
    Default = 150,
    Rounding = 0,
    Suffix = " ms",
})
DropBoostBox:AddSlider("AutoDropBoostIntervalSeconds", {
    Text = "Auto Interval",
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
            local fired = firePlinko4x(
                getNumberOption("Plinko4xFireCount", 1),
                getNumberOption("DropBoostDelayMs", 150) / 1000
            )
            notify("Plinko 4x fired: " .. tostring(fired))
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
            local fired = fireCrateBoost("goldenCrate", 1, getNumberOption("DropBoostDelayMs", 150) / 1000)
            notify("Golden-first crate boost fired: " .. tostring(fired))
        end)
    end,
})
DropBoostBox:AddCheckbox("ToggleAutoCrate", {
    Text = "Auto Crate Boost",
    Default = false,
})

local OrbBox = Tabs.Main:AddLeftGroupbox("Godly Orb", "sparkles")
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

local GemStormBox = Tabs.Main:AddLeftGroupbox("Gem Storm", "gem")
GemStormBox:AddSlider("GemStormRetrySeconds", {
    Text = "Request Interval",
    Min = 1,
    Max = 60,
    Default = 5,
    Rounding = 0,
    Suffix = " s",
})
GemStormBox:AddButton({
    Text = "Start Gem Storm",
    Func = function()
        notify("Gem Storm requested: " .. tostring(fireGemStorm()))
    end,
})
GemStormBox:AddCheckbox("ToggleAutoGemStorm", {
    Text = "Auto Gem Storm",
    Default = false,
})
GemStormBox:AddCheckbox("ToggleAutoCollectGemStorm", {
    Text = "Auto Collect Gems",
    Default = true,
})

local CleanbotBox = Tabs.Main:AddLeftGroupbox("Cleanbot", "bot")
CleanbotBox:AddSlider("CleanbotRollIntervalMs", {
    Text = "Roll Interval",
    Min = 250,
    Max = 10000,
    Default = 1000,
    Rounding = 0,
    Suffix = " ms",
})
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
Options.CollectorRadius:OnChanged(function()
    updateMarker()
    resizeActualCollectorRing()
end)
Options.CollectorBatchSize:OnChanged(updateMarker)
Options.CollectorTickMs:OnChanged(updateMarker)
Options.CollectorRetryMs:OnChanged(updateMarker)

Library:OnUnload(function()
    Marker:SetAttribute("Session", "unloaded-" .. tostring(os.clock()))
    Marker:SetAttribute("Enabled", false)

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

startRingVisual()
if Toggles.ToggleHugeCollector.Value then
    startCollector()
end
if Toggles.ToggleAutoGodlyOrb.Value then
    startGodlyOrbLoop()
end
if Toggles.ToggleAutoAbilities.Value then
    startAutoAbilitiesLoop()
end
if Toggles.ToggleAutoPlinko.Value then
    startAutoPlinkoLoop()
end
if Toggles.ToggleAutoCrate.Value then
    startAutoCrateLoop()
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

notify("slimeinc loaded.")
