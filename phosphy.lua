local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- Anti-AFK (no UI)
-- ============================================================
local VirtualUser = game:GetService("VirtualUser")
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- Wait for PlayerData to be ready before anything else
repeat task.wait(0.1) until
    LocalPlayer and
    LocalPlayer.PlayerScripts:FindFirstChild("PlayerData", true)

-- Modules (resolved early so PlayerData.Data is valid for the rest of the script)
local Modules = ReplicatedStorage:WaitForChild("Game"):WaitForChild("Modules")
local EggsModule = require(Modules:WaitForChild("Eggs"))
local PetsModule = require(Modules:WaitForChild("Pets"))
local SeasonModule = require(Modules:WaitForChild("Season"))
local Playtime = require(Modules:WaitForChild("Playtime"))
local Achievements = require(Modules:WaitForChild("Achievements"))
local Items = require(Modules:WaitForChild("Items"))
local RebirthsModule = require(Modules:WaitForChild("Rebirths"))
local UpgradesModule = require(Modules:WaitForChild("Upgrades"))
local PlayerData = require(LocalPlayer.PlayerScripts:FindFirstChild("PlayerData", true))
local Format = require(Modules:WaitForChild("Format"))
local CodesModule = require(Modules:WaitForChild("Codes"))

-- Wait for PlayerData.Data.Items to be populated before building item list
repeat task.wait(0.1) until PlayerData.Data and PlayerData.Data.Items

-- Remotes
local Events = ReplicatedStorage:WaitForChild("Game"):WaitForChild("Events")
local ClickRemote = Events:WaitForChild("Click")
local SwitchRemote = Events:WaitForChild("Switch")
local EggRemote = Events:WaitForChild("Egg")
local RewardsRemote = Events:WaitForChild("Rewards")
local MerchantRemote = Events:WaitForChild("Merchant")
local ChestRemote = Events:WaitForChild("Chests")
local SpinRemote = Events:WaitForChild("Spin")
local EvilSpinRemote = Events:WaitForChild("EvilSpin")
local RebirthRemote = Events:WaitForChild("Rebirth")
local UpgradesRemote = Events:WaitForChild("Upgrades")
local PetActionRemote = Events:WaitForChild("PetAction")
local SeasonRemote = Events:WaitForChild("Season")
local CodesRemote = Events:WaitForChild("Codes")
local ItemsRemote = Events:WaitForChild("Items")

local MainUI = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("MainUI")
local Rewards = MainUI.Frames.Rewards

-- Build egg list (exclude Robux eggs)
local EggList = {}
for name, data in pairs(EggsModule.Eggs) do
    if data.Currency ~= "Robux" then
        table.insert(EggList, name)
    end
end
table.sort(EggList)

-- Build merchant item list
local MerchantItemList = {}
for itemName in pairs(Items.Items) do
    table.insert(MerchantItemList, itemName)
end
table.sort(MerchantItemList)

local MerchantDefaultSelected = {}
for _, name in ipairs(MerchantItemList) do
    MerchantDefaultSelected[name] = true
end

-- Number formatter
local function fmtNum(n)
    if n >= 1e12 then return string.format("%.0fT", n / 1e12)
    elseif n >= 1e9 then return string.format("%.0fB", n / 1e9)
    elseif n >= 1e6 then return string.format("%.0fM", n / 1e6)
    elseif n >= 1e3 then return string.format("%.0fK", n / 1e3)
    else return tostring(n) end
end

-- Build rebirth tier list
local RebirthTiers = {}
local RebirthTierKeys = {}
for i, amount in ipairs(RebirthsModule.Rebirths) do
    local label = fmtNum(amount) .. (amount == 1 and " Rebirth" or " Rebirths")
    table.insert(RebirthTiers, label)
    RebirthTierKeys[label] = i
end
if table.find(PlayerData.Data.Passes, "InfinityRebirth") then
    table.insert(RebirthTiers, "Infinity Rebirth")
    RebirthTierKeys["Infinity Rebirth"] = "Inf"
end

-- Build upgrade list
local UpgradeList = {}
local UpgradeDefaultSelected = {}
for name in pairs(UpgradesModule.Upgrades) do
    table.insert(UpgradeList, name)
    UpgradeDefaultSelected[name] = true
end
table.sort(UpgradeList)

-- Build craft pet list (all non-Celestial pets)
local CraftPetList = {}
for name, data in pairs(PetsModule.Pets) do
    if data.Rarity ~= "Celestial" then
        table.insert(CraftPetList, name)
    end
end
table.sort(CraftPetList)

local CraftSuccessRates = { "20%", "40%", "60%", "80%", "100%" }
local CraftSuccessMap = { ["20%"] = 1, ["40%"] = 2, ["60%"] = 3, ["80%"] = 4, ["100%"] = 5 }

-- Build item use list from PlayerData.Data.Items
local ItemUseList = {}
for itemName in pairs(PlayerData.Data.Items) do
    table.insert(ItemUseList, itemName)
end
table.sort(ItemUseList)

-- Shop state
local shopData = {}
local shopSeed = nil
MerchantRemote.OnClientEvent:Connect(function(data, seed)
    if type(data) ~= "table" then return end
    if shopSeed == seed then return end
    shopSeed = seed
    shopData = data
end)
MerchantRemote:FireServer("GetFruitShop")

-- UI helpers
local function AddCheckbox(groupbox, id, text, default)
    groupbox:AddCheckbox(id, { Text = text, Default = default or false })
end
local function AddDropdown(groupbox, id, text, values, default, multi)
    groupbox:AddDropdown(id, { Text = text, Values = values, Default = default, Multi = multi })
end

-- Window
local Options = Library.Options
local Toggles = Library.Toggles

local Window = Library:CreateWindow({
    Title = "Phosphy",
    Footer = "disc : neonbeon",
    Icon = 111288992980872,
    NotifySide = "Right",
    ShowCustomCursor = false,
    UnlockMouseWhileOpen = false,
})

local Tabs = {
    Main = Window:AddTab("Main", "user"),
    Pets = Window:AddTab("Pets", "paw-print"),
    ["UI Settings"] = Window:AddTab("UI Settings", "folder-cog"),
}

-- LEFT SIDE
local ACBox = Tabs["Main"]:AddLeftGroupbox("Auto Clicker", "mouse")
AddCheckbox(ACBox, "ToggleAC", "Toggle AC")

local ARBox = Tabs["Main"]:AddLeftGroupbox("Auto Rebirth", "refresh-cw")
AddDropdown(ARBox, "RebirthTier", "Tier", RebirthTiers, RebirthTiers[1], false)
AddCheckbox(ARBox, "ToggleAutoRebirth", "Auto Rebirth")

local SpinBox = Tabs["Main"]:AddLeftGroupbox("Auto Spin", "rotate-cw")
AddCheckbox(SpinBox, "ToggleAutoSpin", "Auto Spin")
AddCheckbox(SpinBox, "ToggleAutoEvilSpin", "Auto Evil Spin")

local AutoUseBox = Tabs["Main"]:AddLeftGroupbox("Auto Use Items", "zap")
AddDropdown(AutoUseBox, "ItemUseSelect", "Items", ItemUseList, {}, true)
AddCheckbox(AutoUseBox, "ToggleAutoUseItems", "Auto Use")

-- Codes box
local CodesBox = Tabs["Main"]:AddLeftGroupbox("Codes", "key")
CodesBox:AddButton({
    Text = "Redeem All Codes",
    Func = function()
        local codes = CodesModule.Codes or CodesModule
        local claimed = PlayerData.Data.RedeemedCodes or {}
        local count = 0
        for code in pairs(codes) do
            if not table.find(claimed, code) then
                CodesRemote:FireServer(code)
                count = count + 1
                task.wait(0.25)
            end
        end
        Library:Notify("Attempted " .. count .. " code(s)!")
    end
})

-- ============================================================
-- Misc box (Disable Auto Rejoin)
-- ============================================================
local MiscBox = Tabs["Main"]:AddLeftGroupbox("Misc", "shield")
AddCheckbox(MiscBox, "ToggleDisableAutoRejoin", "Disable Auto Rejoin")

-- RIGHT SIDE
local UpgradeBox = Tabs["Main"]:AddRightGroupbox("Auto Upgrade", "arrow-up")
AddDropdown(UpgradeBox, "UpgradeSelect", "Upgrades", UpgradeList, UpgradeDefaultSelected, true)
AddCheckbox(UpgradeBox, "ToggleAutoUpgrade", "Auto Upgrade")
task.defer(function()
    Options.UpgradeSelect:SetValue(UpgradeDefaultSelected)
end)

local MerchantBox = Tabs["Main"]:AddRightGroupbox("Fruit Shop", "shopping-cart")
AddDropdown(MerchantBox, "MerchantItems", "Items to Buy", MerchantItemList, MerchantDefaultSelected, true)
AddCheckbox(MerchantBox, "ToggleAutoBuy", "Auto Buy")
task.defer(function()
    Options.MerchantItems:SetValue(MerchantDefaultSelected)
end)

local ClaimBox = Tabs["Main"]:AddRightGroupbox("Auto Claim", "gift")
AddCheckbox(ClaimBox, "ToggleClaimGifts", "Auto Claim Gifts")
AddCheckbox(ClaimBox, "ToggleClaimDaily", "Auto Claim Daily")
AddCheckbox(ClaimBox, "ToggleClaimAchievements", "Auto Claim Achievements")
AddCheckbox(ClaimBox, "ToggleClaimChests", "Auto Claim Chests")
AddCheckbox(ClaimBox, "ToggleClaimSeason", "Auto Claim Season")
AddCheckbox(ClaimBox, "ToggleClaimQuests", "Auto Claim Quests")

-- Pets tab
local AHBox = Tabs["Pets"]:AddLeftGroupbox("Auto Hatch", "egg")
AddDropdown(AHBox, "EggSelect", "Egg", EggList, EggList[1], false)
AddCheckbox(AHBox, "ToggleAH", "Toggle Auto Hatch")
AddCheckbox(AHBox, "ToggleAutoEquipBest", "Auto Equip Best")
AddCheckbox(AHBox, "ToggleNoHatchAnim", "No Hatch Animation")

local GoldenBox = Tabs["Pets"]:AddRightGroupbox("Golden Machine", "star")
AddDropdown(GoldenBox, "GoldenPetSelect", "Pets", CraftPetList, {}, true)
AddDropdown(GoldenBox, "GoldenSuccessRate", "Success Rate", CraftSuccessRates, "100%", false)
AddCheckbox(GoldenBox, "ToggleAutoGolden", "Auto Craft Golden")

local DiamondBox = Tabs["Pets"]:AddRightGroupbox("Diamond Machine", "diamond")
AddDropdown(DiamondBox, "DiamondPetSelect", "Pets", CraftPetList, {}, true)
AddDropdown(DiamondBox, "DiamondSuccessRate", "Success Rate", CraftSuccessRates, "100%", false)
AddCheckbox(DiamondBox, "ToggleAutoDiamond", "Auto Craft Diamond")

-- ============================================================
-- No Hatch Animation hook
-- ============================================================
local _hookRef_fn = nil
local _hookRef_original = nil

local function InstallNoHatchHook()
    if _hookRef_fn then return end
    task.spawn(function()
        local attempts = 0
        while not _hookRef_fn and attempts < 200 do
            attempts = attempts + 1
            local conns = getconnections(EggRemote.OnClientEvent)
            for _, conn in pairs(conns) do
                local ok, ups = pcall(getupvalues, conn.Function)
                if ok then
                    for _, v in pairs(ups) do
                        if type(v) == "table" and v.Unbox then
                            local original
                            original = hookfunction(conn.Function, newcclosure(function(eventType, ...)
                                if eventType == "Unbox" and Toggles.ToggleNoHatchAnim.Value then
                                    return
                                end
                                return original(eventType, ...)
                            end))
                            _hookRef_fn = conn.Function
                            _hookRef_original = original
                            return
                        end
                    end
                end
            end
            task.wait(0.05)
        end
    end)
end

InstallNoHatchHook()

-- ============================================================
-- Disable Auto Rejoin hook
-- Hooks TeleportService:Teleport and blocks it while the
-- checkbox is enabled. Restored on unload or when unchecked.
-- ============================================================
local _teleportHookOriginal = nil

local function InstallTeleportBlock()
    if _teleportHookOriginal then return end -- already hooked
    _teleportHookOriginal = hookfunction(TeleportService.Teleport, newcclosure(function(self, placeId, ...)
        -- If the checkbox is on, silently swallow the auto-rejoin teleport
        if Toggles.ToggleDisableAutoRejoin.Value then
            return
        end
        return _teleportHookOriginal(self, placeId, ...)
    end))
end

local function RemoveTeleportBlock()
    if _teleportHookOriginal then
        hookfunction(TeleportService.Teleport, _teleportHookOriginal)
        _teleportHookOriginal = nil
    end
end

Toggles.ToggleDisableAutoRejoin:OnChanged(function(state)
    if state then
        InstallTeleportBlock()
    else
        RemoveTeleportBlock()
    end
end)

-- ============================================================
-- LOGIC
-- ============================================================

-- Batch detection
local function getBatch(eggName)
    local eggData = EggsModule.Eggs[eggName]
    if not eggData then return nil end
    local price = eggData.Price
    local currency = eggData.Currency
    local currencyAmount = PlayerData.Data[currency] or 0
    local petCount = #LocalPlayer.Pets:GetChildren()
    local maxStorage = PlayerData.Data.MaxStorage or 0
    local hasPass = table.find(PlayerData.Data.Passes, "x8EggsHatch") ~= nil
    if hasPass and price * 8 <= currencyAmount and petCount + 8 <= maxStorage then return "Q"
    elseif price * 3 <= currencyAmount and petCount + 3 <= maxStorage then return "R"
    elseif price <= currencyAmount and petCount + 1 <= maxStorage then return "E"
    end
    return nil
end

-- Auto Clicker
local actask
local function StartAC()
    if actask then task.cancel(actask) actask = nil end
    actask = task.spawn(function()
        while Toggles.ToggleAC.Value do
            ClickRemote:FireServer()
            task.wait(0.1)
        end
    end)
end
Toggles.ToggleAC:OnChanged(function(state)
    if state then StartAC()
    else if actask then task.cancel(actask) actask = nil end end
end)

-- Teleport helper
local function TeleportToEgg(eggName)
    local egg = workspace.Game.Eggs:FindFirstChild(eggName)
    if not egg or not LocalPlayer.Character then return end
    local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.CFrame = egg:GetPivot() + Vector3.new(0, 5, 0) end
end

-- Auto Hatch
local ahtask
local function StartAH()
    if ahtask then task.cancel(ahtask) ahtask = nil end
    local eggName = Options.EggSelect.Value
    SwitchRemote:FireServer("AutoHatching", true)
    TeleportToEgg(eggName)
    ahtask = task.spawn(function()
        while Toggles.ToggleAH.Value do
            local batch = getBatch(eggName)
            if batch then EggRemote:FireServer(eggName, batch)
            else task.wait(0.1) end
            task.wait(0.1)
        end
    end)
end
Toggles.ToggleAH:OnChanged(function(state)
    if state then StartAH()
    else
        if ahtask then task.cancel(ahtask) ahtask = nil end
        SwitchRemote:FireServer("AutoHatching", false)
    end
end)
Options.EggSelect:OnChanged(function()
    if Toggles.ToggleAH.Value then StartAH() end
end)

-- Auto Rebirth
local autorebirththask
local function canAffordRebirth(label)
    local key = RebirthTierKeys[label]
    if not key then return false end
    if key == "Inf" then
        return PlayerData.Data.Rebirths > 0
            and PlayerData.Data.Clicks >= 100 * PlayerData.Data.Rebirths
    end
    local cost = RebirthsModule.Rebirths[key] * 100 * (1 + PlayerData.Data.Rebirths)
    return PlayerData.Data.Clicks >= cost
end
local function StartAutoRebirth()
    if autorebirththask then task.cancel(autorebirththask) autorebirththask = nil end
    autorebirththask = task.spawn(function()
        while Toggles.ToggleAutoRebirth.Value do
            local label = Options.RebirthTier.Value
            local key = RebirthTierKeys[label]
            if key and canAffordRebirth(label) then
                RebirthRemote:FireServer(key)
                task.wait(0.5)
            else
                task.wait(0.5)
            end
        end
    end)
end
Toggles.ToggleAutoRebirth:OnChanged(function(state)
    if state then StartAutoRebirth()
    else if autorebirththask then task.cancel(autorebirththask) autorebirththask = nil end end
end)

-- Auto Spin
local autospintask
local function StartAutoSpin()
    if autospintask then task.cancel(autospintask) autospintask = nil end
    autospintask = task.spawn(function()
        while Toggles.ToggleAutoSpin.Value do
            if PlayerData.Data.Spins > 0 then
                SpinRemote:FireServer(false)
                task.wait(5)
            else
                task.wait(1)
            end
        end
    end)
end
Toggles.ToggleAutoSpin:OnChanged(function(state)
    if state then StartAutoSpin()
    else if autospintask then task.cancel(autospintask) autospintask = nil end end
end)

-- Auto Evil Spin
local autoevilspintask
local function StartAutoEvilSpin()
    if autoevilspintask then task.cancel(autoevilspintask) autoevilspintask = nil end
    autoevilspintask = task.spawn(function()
        while Toggles.ToggleAutoEvilSpin.Value do
            if PlayerData.Data.EvilSpins > 0 then
                EvilSpinRemote:FireServer(false)
                task.wait(5)
            else
                task.wait(1)
            end
        end
    end)
end
Toggles.ToggleAutoEvilSpin:OnChanged(function(state)
    if state then StartAutoEvilSpin()
    else if autoevilspintask then task.cancel(autoevilspintask) autoevilspintask = nil end end
end)

-- Auto Upgrade
local autoupgradetask
local function StartAutoUpgrade()
    if autoupgradetask then task.cancel(autoupgradetask) autoupgradetask = nil end
    autoupgradetask = task.spawn(function()
        while Toggles.ToggleAutoUpgrade.Value do
            local selected = Options.UpgradeSelect.Value
            for name, data in pairs(UpgradesModule.Upgrades) do
                if not Toggles.ToggleAutoUpgrade.Value then break end
                if selected[name] then
                    local current = PlayerData.Data[name] or 0
                    local price = data.Prices and data.Prices[current]
                    if current < data.Max and price and PlayerData.Data.Gems >= price then
                        UpgradesRemote:FireServer(name)
                        task.wait(0.3)
                    end
                end
            end
            task.wait(1)
        end
    end)
end
Toggles.ToggleAutoUpgrade:OnChanged(function(state)
    if state then StartAutoUpgrade()
    else if autoupgradetask then task.cancel(autoupgradetask) autoupgradetask = nil end end
end)

-- Auto Equip Best
local autoequiptask
local function StartAutoEquipBest()
    if autoequiptask then task.cancel(autoequiptask) autoequiptask = nil end
    autoequiptask = task.spawn(function()
        while Toggles.ToggleAutoEquipBest.Value do
            PetActionRemote:FireServer("Equip Best")
            task.wait(10)
        end
    end)
end
Toggles.ToggleAutoEquipBest:OnChanged(function(state)
    if state then StartAutoEquipBest()
    else if autoequiptask then task.cancel(autoequiptask) autoequiptask = nil end end
end)

-- Auto Buy Merchant
local autobuytask
local function StartAutoBuy()
    if autobuytask then task.cancel(autobuytask) autobuytask = nil end
    autobuytask = task.spawn(function()
        while Toggles.ToggleAutoBuy.Value do
            MerchantRemote:FireServer("GetFruitShop")
            task.wait(1)
            local selected = Options.MerchantItems.Value
            for i, item in ipairs(shopData) do
                if selected[item.ItemName] then
                    local bought = PlayerData.Data["Item" .. i .. "Stock"] or 0
                    local remaining = item.Stock - bought
                    if remaining > 0 then
                        MerchantRemote:FireServer("Buy", item.ItemName)
                        task.wait(0.3)
                    end
                end
            end
            task.wait(5)
        end
    end)
end
Toggles.ToggleAutoBuy:OnChanged(function(state)
    if state then StartAutoBuy()
    else if autobuytask then task.cancel(autobuytask) autobuytask = nil end end
end)

-- Auto Use Items
local autouseitemstask
local function StartAutoUseItems()
    if autouseitemstask then task.cancel(autouseitemstask) autouseitemstask = nil end
    autouseitemstask = task.spawn(function()
        while Toggles.ToggleAutoUseItems.Value do
            local selected = Options.ItemUseSelect.Value
            for itemName in pairs(selected) do
                local count = (PlayerData.Data.Items and PlayerData.Data.Items[itemName]) or 0
                if count > 0 then
                    ItemsRemote:FireServer(itemName)
                    task.wait(0.3)
                end
            end
            task.wait(2)
        end
    end)
end
Toggles.ToggleAutoUseItems:OnChanged(function(state)
    if state then StartAutoUseItems()
    else if autouseitemstask then task.cancel(autouseitemstask) autouseitemstask = nil end end
end)

-- Auto Claim Gifts
local claimgiftstask
local function StartClaimGifts()
    if claimgiftstask then task.cancel(claimgiftstask) claimgiftstask = nil end
    claimgiftstask = task.spawn(function()
        while Toggles.ToggleClaimGifts.Value do
            local timer = LocalPlayer.Gifts.Timer.Value
            for _, v in pairs(Rewards:GetChildren()) do
                if string.find(v.Name, "Buttons") and v:FindFirstChild("UIListLayout") then
                    for _, btn in pairs(v:GetChildren()) do
                        if btn:IsA("TextButton") then
                            local req = Playtime.Gifts[btn.Name]
                            if req and req <= timer and not LocalPlayer.Gifts:FindFirstChild(btn.Name) then
                                RewardsRemote:FireServer("Playtime", btn.Name)
                                task.wait(0.3)
                            end
                        end
                    end
                end
            end
            task.wait(5)
        end
    end)
end
Toggles.ToggleClaimGifts:OnChanged(function(state)
    if state then StartClaimGifts()
    else if claimgiftstask then task.cancel(claimgiftstask) claimgiftstask = nil end end
end)

-- Auto Claim Daily
local claimdailytask
local function StartClaimDaily()
    if claimdailytask then task.cancel(claimdailytask) claimdailytask = nil end
    claimdailytask = task.spawn(function()
        while Toggles.ToggleClaimDaily.Value do
            local Daily = Rewards.CanvasGroup.Daily
            for _, v in pairs(Daily:GetChildren()) do
                if string.find(v.Name, "Day") then
                    if PlayerData.Data.DailyDay >= v.LayoutOrder then
                        if not table.find(PlayerData.Data.DailyRewardsClaimed, v.LayoutOrder) then
                            RewardsRemote:FireServer("Daily", v.LayoutOrder)
                            task.wait(0.3)
                        end
                    end
                end
            end
            task.wait(5)
        end
    end)
end
Toggles.ToggleClaimDaily:OnChanged(function(state)
    if state then StartClaimDaily()
    else if claimdailytask then task.cancel(claimdailytask) claimdailytask = nil end end
end)

-- Auto Claim Achievements
local claimachtask
local function StartClaimAchievements()
    if claimachtask then task.cancel(claimachtask) claimachtask = nil end
    claimachtask = task.spawn(function()
        while Toggles.ToggleClaimAchievements.Value do
            for name, data in pairs(Achievements) do
                if PlayerData.Data[name] then
                    local stage = PlayerData.Data[name .. "_Stage"]
                    if stage and stage <= data.Max then
                        local pct = Format:Percentage(PlayerData.Data[name], data.Rewards[stage].Req)
                        if pct >= 100 then
                            RewardsRemote:FireServer("Achievements", name)
                            task.wait(0.3)
                        end
                    end
                end
            end
            task.wait(5)
        end
    end)
end
Toggles.ToggleClaimAchievements:OnChanged(function(state)
    if state then StartClaimAchievements()
    else if claimachtask then task.cancel(claimachtask) claimachtask = nil end end
end)

-- Auto Claim Chests
local claimchesttask
local function StartClaimChests()
    if claimchesttask then task.cancel(claimchesttask) claimchesttask = nil end
    claimchesttask = task.spawn(function()
        while Toggles.ToggleClaimChests.Value do
            for _, v in pairs(LocalPlayer.Chests:GetChildren()) do
                if v.Value <= 0 then
                    ChestRemote:FireServer(v.Name)
                    task.wait(0.5)
                end
            end
            task.wait(5)
        end
    end)
end
Toggles.ToggleClaimChests:OnChanged(function(state)
    if state then StartClaimChests()
    else if claimchesttask then task.cancel(claimchesttask) claimchesttask = nil end end
end)

-- Auto Golden Craft (Normal → Golden)
local autogoldentask
local function StartAutoGolden()
    if autogoldentask then task.cancel(autogoldentask) autogoldentask = nil end
    autogoldentask = task.spawn(function()
        while Toggles.ToggleAutoGolden.Value do
            local selected = Options.GoldenPetSelect.Value
            local needed = CraftSuccessMap[Options.GoldenSuccessRate.Value] or 5
            for petName in pairs(selected) do
                local ids = {}
                for _, pet in pairs(LocalPlayer.Pets:GetChildren()) do
                    if pet:FindFirstChild("PetType") and pet.PetType.Value == "Normal"
                       and pet.Name == petName and pet:FindFirstChild("ID") then
                        table.insert(ids, pet.ID.Value)
                        if #ids >= needed then break end
                    end
                end
                if #ids >= needed then
                    PetActionRemote:FireServer("GoldenMachine", { ids, petName })
                    task.wait(1)
                end
            end
            task.wait(2)
        end
    end)
end
Toggles.ToggleAutoGolden:OnChanged(function(state)
    if state then StartAutoGolden()
    else if autogoldentask then task.cancel(autogoldentask) autogoldentask = nil end end
end)

-- Auto Diamond Craft (Golden → Diamond)
local autodiamondtask
local function StartAutoDiamond()
    if autodiamondtask then task.cancel(autodiamondtask) autodiamondtask = nil end
    autodiamondtask = task.spawn(function()
        while Toggles.ToggleAutoDiamond.Value do
            local selected = Options.DiamondPetSelect.Value
            local needed = CraftSuccessMap[Options.DiamondSuccessRate.Value] or 5
            for petName in pairs(selected) do
                local ids = {}
                for _, pet in pairs(LocalPlayer.Pets:GetChildren()) do
                    if pet:FindFirstChild("PetType") and pet.PetType.Value == "Golden"
                       and pet.Name == petName and pet:FindFirstChild("ID") then
                        table.insert(ids, pet.ID.Value)
                        if #ids >= needed then break end
                    end
                end
                if #ids >= needed then
                    PetActionRemote:FireServer("DiamondMachine", { ids, petName })
                    task.wait(1)
                end
            end
            task.wait(2)
        end
    end)
end
Toggles.ToggleAutoDiamond:OnChanged(function(state)
    if state then StartAutoDiamond()
    else if autodiamondtask then task.cancel(autodiamondtask) autodiamondtask = nil end end
end)

-- Auto Claim Season Rewards (Free + Premium if pass owned)
local claimseasontask
local function StartClaimSeason()
    if claimseasontask then task.cancel(claimseasontask) claimseasontask = nil end
    claimseasontask = task.spawn(function()
        while Toggles.ToggleClaimSeason.Value do
            local currentSeason = SeasonModule.CurrentSeason
            local playerLevel = PlayerData.Data["SeasonLVL" .. currentSeason]
            local freeClaimed = PlayerData.Data["SeasonFreeClaimed" .. currentSeason]
            local premiumClaimed = PlayerData.Data["SeasonPremiumClaimed" .. currentSeason]
            local hasPremium = PlayerData.Data["PremiumPass" .. currentSeason]
            for tier in pairs(SeasonModule.Rewards) do
                if tier <= playerLevel then
                    if not table.find(freeClaimed, tier) then
                        SeasonRemote:FireServer("Claim", "Free", tier)
                        task.wait(0.3)
                    end
                    if hasPremium and not table.find(premiumClaimed, tier) then
                        SeasonRemote:FireServer("Claim", "Premium", tier)
                        task.wait(0.3)
                    end
                end
            end
            task.wait(5)
        end
    end)
end
Toggles.ToggleClaimSeason:OnChanged(function(state)
    if state then StartClaimSeason()
    else if claimseasontask then task.cancel(claimseasontask) claimseasontask = nil end end
end)

-- Auto Claim Season Quests
local claimquesttask
local function StartClaimQuests()
    if claimquesttask then task.cancel(claimquesttask) claimquesttask = nil end
    claimquesttask = task.spawn(function()
        while Toggles.ToggleClaimQuests.Value do
            local currentSeason = SeasonModule.CurrentSeason
            local passQuests = PlayerData.Data["PassQuests" .. currentSeason]
            local questsClaimed = PlayerData.Data["PassQuestsClaimed" .. currentSeason]
            for slotIndex, questKey in pairs(passQuests) do
                local questData = SeasonModule.Quests[questKey]
                if questData then
                    local pct = Format:Percentage(PlayerData.Data[questData.Currency], questData.Req)
                    if pct >= 100 and not table.find(questsClaimed, questKey) then
                        SeasonRemote:FireServer("Quest", slotIndex)
                        task.wait(0.3)
                    end
                end
            end
            task.wait(5)
        end
    end)
end
Toggles.ToggleClaimQuests:OnChanged(function(state)
    if state then StartClaimQuests()
    else if claimquesttask then task.cancel(claimquesttask) claimquesttask = nil end end
end)

-- Unload cleanup
Library:OnUnload(function()
    -- Restore egg animation hook
    if _hookRef_fn and _hookRef_original then
        hookfunction(_hookRef_fn, _hookRef_original)
        _hookRef_fn = nil
        _hookRef_original = nil
    end

    -- Restore teleport hook
    RemoveTeleportBlock()

    if actask then task.cancel(actask) actask = nil end
    if ahtask then task.cancel(ahtask) ahtask = nil end
    if autorebirththask then task.cancel(autorebirththask) autorebirththask = nil end
    if autospintask then task.cancel(autospintask) autospintask = nil end
    if autoevilspintask then task.cancel(autoevilspintask) autoevilspintask = nil end
    if autoupgradetask then task.cancel(autoupgradetask) autoupgradetask = nil end
    if autoequiptask then task.cancel(autoequiptask) autoequiptask = nil end
    if autobuytask then task.cancel(autobuytask) autobuytask = nil end
    if autouseitemstask then task.cancel(autouseitemstask) autouseitemstask = nil end
    if claimgiftstask then task.cancel(claimgiftstask) claimgiftstask = nil end
    if claimdailytask then task.cancel(claimdailytask) claimdailytask = nil end
    if claimachtask then task.cancel(claimachtask) claimachtask = nil end
    if claimchesttask then task.cancel(claimchesttask) claimchesttask = nil end
    if autogoldentask then task.cancel(autogoldentask) autogoldentask = nil end
    if autodiamondtask then task.cancel(autodiamondtask) autodiamondtask = nil end
    if claimseasontask then task.cancel(claimseasontask) claimseasontask = nil end
    if claimquesttask then task.cancel(claimquesttask) claimquesttask = nil end
    SwitchRemote:FireServer("AutoHatching", false)
end)

-- Settings Tab
local Settings = Tabs["UI Settings"]:AddRightGroupbox("General", "wrench")
Settings:AddLabel("MenuBind"):AddKeyPicker("MenuKeybind", {
    Default = "RightShift",
    NoUI = true,
    Text = "Menu keybind"
})
Settings:AddButton({
    Text = "Unload",
    Func = function() Library:Unload() end
})

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("PhosphyHub")
ThemeManager:SetDefaultTheme({
    FontColor = Color3.fromRGB(220, 255, 250),
    MainColor = Color3.fromRGB(25, 25, 25),
    AccentColor = Color3.fromRGB(0, 200, 180),
    BackgroundColor = Color3.fromRGB(15, 15, 15),
    OutlineColor = Color3.fromRGB(40, 40, 40),
})
ThemeManager:ApplyToTab(Tabs["UI Settings"])
ThemeManager:LoadDefault()

SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
SaveManager:SetFolder("PhosphyHub/ClickBreakers")
SaveManager:SetSubFolder("Lobby")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()
