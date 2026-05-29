local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TeleportService   = game:GetService("TeleportService")
local HttpService        = game:GetService("HttpService")
local RunService         = game:GetService("RunService")
local LocalPlayer        = Players.LocalPlayer

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

-- Modules
local Modules = ReplicatedStorage:WaitForChild("Game"):WaitForChild("Modules")
local EggsModule       = require(Modules:WaitForChild("Eggs"))
local PetsModule       = require(Modules:WaitForChild("Pets"))
local SeasonModule     = require(Modules:WaitForChild("Season"))
local Playtime         = require(Modules:WaitForChild("Playtime"))
local Achievements     = require(Modules:WaitForChild("Achievements"))
local Items            = require(Modules:WaitForChild("Items"))
local RebirthsModule   = require(Modules:WaitForChild("Rebirths"))
local UpgradesModule   = require(Modules:WaitForChild("Upgrades"))
local PlayerData       = require(LocalPlayer.PlayerScripts:FindFirstChild("PlayerData", true))
local Format           = require(Modules:WaitForChild("Format"))
local CodesModule      = require(Modules:WaitForChild("Codes"))
local AurasModule      = require(Modules:WaitForChild("Auras"))
local TapSkinsModule   = require(Modules:WaitForChild("TapSkins"))

repeat task.wait(0.1) until PlayerData.Data and PlayerData.Data.Items

-- Remotes
local Events            = ReplicatedStorage:WaitForChild("Game"):WaitForChild("Events")
local ClickRemote       = Events:WaitForChild("Click")
local SwitchRemote      = Events:WaitForChild("Switch")
local EggRemote         = Events:WaitForChild("Egg")
local RewardsRemote     = Events:WaitForChild("Rewards")
local MerchantRemote    = Events:WaitForChild("Merchant")
local ChestRemote       = Events:WaitForChild("Chests")
local SpinRemote        = Events:WaitForChild("Spin")
local EvilSpinRemote    = Events:WaitForChild("EvilSpin")
local RebirthRemote     = Events:WaitForChild("Rebirth")
local UpgradesRemote    = Events:WaitForChild("Upgrades")
local PetActionRemote   = Events:WaitForChild("PetAction")
local SeasonRemote      = Events:WaitForChild("Season")
local CodesRemote       = Events:WaitForChild("Codes")
local ItemsRemote       = Events:WaitForChild("Items")
local AurasRemote       = Events:WaitForChild("Auras")
local TapSkinsRemote    = Events:WaitForChild("TapSkins")
local TradeRemote       = Events:WaitForChild("Trade")
local AdditionalRemote  = Events:WaitForChild("Additional")
local SettingsRemote    = Events:WaitForChild("Settings")

local MainUI  = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("MainUI")
local Rewards = MainUI.Frames.Rewards

-- ============================================================
-- Build egg list (excluding Robux eggs from auto hatch)
-- ============================================================
local EggList = {}
for name, data in pairs(EggsModule.Eggs) do
    if data.Currency ~= "Robux" then
        table.insert(EggList, name)
    end
end
table.sort(EggList)

-- ============================================================
-- Dynamic egg progression order
-- ============================================================
local function BuildEggProgressionOrder()
    local clicksEggs = {}
    local robuxEggs  = {}
    for name, data in pairs(EggsModule.Eggs) do
        if data.Currency == "Robux" then
            table.insert(robuxEggs, { name = name, price = data.Price or 0 })
        else
            table.insert(clicksEggs, { name = name, price = data.Price or 0 })
        end
    end
    table.sort(clicksEggs, function(a, b) return a.price < b.price end)
    table.sort(robuxEggs,  function(a, b) return a.price < b.price end)
    local order = {}
    for _, entry in ipairs(clicksEggs) do table.insert(order, entry.name) end
    for _, entry in ipairs(robuxEggs)  do table.insert(order, entry.name) end
    return order
end

local EggProgressionOrder = BuildEggProgressionOrder()

-- ============================================================
-- Build merchant item list
-- ============================================================
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

-- Build craft pet list
local CraftPetList = {}
for name, data in pairs(PetsModule.Pets) do
    if data.Rarity ~= "Celestial" then
        table.insert(CraftPetList, name)
    end
end
table.sort(CraftPetList)

local CraftSuccessRates = { "20%", "40%", "60%", "80%", "100%" }
local CraftSuccessMap   = { ["20%"] = 1, ["40%"] = 2, ["60%"] = 3, ["80%"] = 4, ["100%"] = 5 }

-- Build item use list
local ItemUseList = {}
for itemName in pairs(PlayerData.Data.Items) do
    table.insert(ItemUseList, itemName)
end
table.sort(ItemUseList)

-- Build Aura list
local AuraList = {}
for name in pairs(AurasModule.Auras) do
    table.insert(AuraList, name)
end
table.sort(AuraList)

-- Build TapSkin list
local TapSkinList = {}
for name in pairs(TapSkinsModule.TapSkins) do
    table.insert(TapSkinList, name)
end
table.sort(TapSkinList)

-- Build full pet name list (for auto-delete ignore dropdown)
local AllPetNamesList = {}
for name in pairs(PetsModule.Pets) do
    table.insert(AllPetNamesList, name)
end
table.sort(AllPetNamesList)

-- Rarity list
local RarityList = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Exclusive", "Secret", "Celestial" }

-- Settings booleans available in-game
local GameSettingsList = { "BetterQuality", "Music", "HideOtherPets", "HideAuras" }

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
    Main            = Window:AddTab("Main",         "user"),
    Pets            = Window:AddTab("Pets",         "paw-print"),
    Misc            = Window:AddTab("Misc",         "settings"),
    ["UI Settings"] = Window:AddTab("UI Settings",  "folder-cog"),
}

-- ============================================================
-- MAIN TAB – LEFT SIDE
-- ============================================================
local ACBox = Tabs["Main"]:AddLeftGroupbox("Auto Clicker", "mouse")
AddCheckbox(ACBox, "ToggleAC", "Toggle AC")

local ARBox = Tabs["Main"]:AddLeftGroupbox("Auto Rebirth", "refresh-cw")
AddDropdown(ARBox, "RebirthTier", "Tier", RebirthTiers, RebirthTiers[1], false)
AddCheckbox(ARBox, "ToggleAutoRebirth", "Auto Rebirth")

local SpinBox = Tabs["Main"]:AddLeftGroupbox("Auto Spin", "rotate-cw")
AddCheckbox(SpinBox, "ToggleAutoSpin",     "Auto Spin")
AddCheckbox(SpinBox, "ToggleAutoEvilSpin", "Auto Evil Spin")

local AutoUseBox = Tabs["Main"]:AddLeftGroupbox("Auto Use Items", "zap")
AddDropdown(AutoUseBox, "ItemUseSelect", "Items", ItemUseList, {}, true)
AddCheckbox(AutoUseBox, "ToggleAutoUseItems", "Auto Use")

-- ============================================================
-- MAIN TAB – RIGHT SIDE
-- ============================================================
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
AddCheckbox(ClaimBox, "ToggleClaimGifts",        "Auto Claim Gifts")
AddCheckbox(ClaimBox, "ToggleClaimDaily",         "Auto Claim Daily")
AddCheckbox(ClaimBox, "ToggleClaimAchievements",  "Auto Claim Achievements")
AddCheckbox(ClaimBox, "ToggleClaimChests",        "Auto Claim Chests")
AddCheckbox(ClaimBox, "ToggleClaimSeason",        "Auto Claim Season")
AddCheckbox(ClaimBox, "ToggleClaimQuests",        "Auto Claim Quests")

local AurasBox = Tabs["Main"]:AddRightGroupbox("Auto Auras", "zap")
AddDropdown(AurasBox, "AuraSelect", "Auras to Buy", AuraList, {}, true)
AddCheckbox(AurasBox, "ToggleAutoBuyAuras",      "Auto Buy Auras")
AddCheckbox(AurasBox, "ToggleAutoEquipBestAura", "Auto Equip Best Aura")

local TapSkinsBox = Tabs["Main"]:AddRightGroupbox("Auto TapSkins", "mouse-pointer")
AddDropdown(TapSkinsBox, "TapSkinSelect", "Skins to Buy", TapSkinList, {}, true)
AddCheckbox(TapSkinsBox, "ToggleAutoBuyTapSkins",      "Auto Buy TapSkins")
AddCheckbox(TapSkinsBox, "ToggleAutoEquipBestTapSkin", "Auto Equip Best TapSkin")

-- ============================================================
-- PETS TAB – LEFT SIDE
-- ============================================================
local AHBox = Tabs["Pets"]:AddLeftGroupbox("Auto Hatch", "egg")
AddDropdown(AHBox, "EggSelect", "Egg", EggList, EggList[1], false)
AddCheckbox(AHBox, "ToggleAH",            "Toggle Auto Hatch")
AddCheckbox(AHBox, "ToggleAutoEquipBest", "Auto Equip Best")
AddCheckbox(AHBox, "ToggleNoHatchAnim",   "No Hatch Animation")

-- Index Status display
local IndexStatusBox   = Tabs["Pets"]:AddLeftGroupbox("Index Status", "compass")
local IndexStatusImage = IndexStatusBox:AddImage("IndexStatusImage", {
    Image                  = "rbxassetid://0",
    Height                 = 130,
    BackgroundTransparency = 1,
    ScaleType              = Enum.ScaleType.Fit,
})
local IndexLabelPet      = IndexStatusBox:AddLabel({ Text = "Pet: —",      DoesWrap = false })
local IndexLabelEgg      = IndexStatusBox:AddLabel({ Text = "Egg: —",      DoesWrap = false })
local IndexLabelRarity   = IndexStatusBox:AddLabel({ Text = "Rarity: —",   DoesWrap = false })
local IndexLabelStage    = IndexStatusBox:AddLabel({ Text = "Stage: Idle", DoesWrap = false })
local IndexLabelProgress = IndexStatusBox:AddLabel({ Text = "Progress: —", DoesWrap = false })

-- Auto Index
local AutoIndexBox = Tabs["Pets"]:AddLeftGroupbox("Auto Index", "search")
AddDropdown(AutoIndexBox, "IndexRaritySelect",   "Target Rarities",            RarityList,            {}, true)
AddDropdown(AutoIndexBox, "IndexIgnoreEggs",     "Ignore Eggs",                EggList,               {}, true)
AddDropdown(AutoIndexBox, "IndexCraftVariants",  "Craft Variants",             {"Golden", "Diamond"}, {}, true)
AutoIndexBox:AddLabel({ Text = "Auto Delete runs only while Auto Index is ON.", DoesWrap = true })
AddDropdown(AutoIndexBox, "IndexDeleteRarities", "Delete Rarities",            RarityList,            {}, true)
AddDropdown(AutoIndexBox, "IndexIgnorePets",     "Never Delete Pets",          AllPetNamesList,       {}, true)
AddCheckbox(AutoIndexBox, "ToggleAutoClaimIndexReward", "Auto Claim Index Reward")
AddCheckbox(AutoIndexBox, "ToggleAutoIndex",     "Auto Index")

-- ============================================================
-- PETS TAB – RIGHT SIDE
-- ============================================================
local GoldenBox = Tabs["Pets"]:AddRightGroupbox("Golden Machine", "star")
AddDropdown(GoldenBox, "GoldenPetSelect",   "Pets", CraftPetList, {}, true)
AddDropdown(GoldenBox, "GoldenSuccessRate", "Success Rate", CraftSuccessRates, "100%", false)
AddCheckbox(GoldenBox, "ToggleAutoGolden",  "Auto Craft Golden")

local DiamondBox = Tabs["Pets"]:AddRightGroupbox("Diamond Machine", "diamond")
AddDropdown(DiamondBox, "DiamondPetSelect",   "Pets", CraftPetList, {}, true)
AddDropdown(DiamondBox, "DiamondSuccessRate", "Success Rate", CraftSuccessRates, "100%", false)
AddCheckbox(DiamondBox, "ToggleAutoDiamond",  "Auto Craft Diamond")

-- ============================================================
-- SHARED HELPERS (defined early so Tutorial button can use them)
-- ============================================================

local function TeleportToEgg(eggName)
    local egg = workspace.Game.Eggs:FindFirstChild(eggName)
    if not egg or not LocalPlayer.Character then return end
    local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.CFrame = egg:GetPivot() + Vector3.new(0, 5, 0) end
end

local function getBatch(eggName)
    local eggData = EggsModule.Eggs[eggName]
    if not eggData then return nil end
    local price          = eggData.Price
    local currency       = eggData.Currency
    local currencyAmount = PlayerData.Data[currency] or 0
    local petCount       = #LocalPlayer.Pets:GetChildren()
    local maxStorage     = PlayerData.Data.MaxStorage or 0
    local hasPass        = table.find(PlayerData.Data.Passes, "x8EggsHatch") ~= nil
    if hasPass and price * 8 <= currencyAmount and petCount + 8 <= maxStorage then return "Q"
    elseif price * 3 <= currencyAmount and petCount + 3 <= maxStorage then return "R"
    elseif price <= currencyAmount and petCount + 1 <= maxStorage then return "E"
    end
    return nil
end

-- Parse comma-separated username string into a trimmed list
local function ParseUsernames(raw)
    local names = {}
    for name in (raw or ""):gmatch("[^,]+") do
        local trimmed = name:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            table.insert(names, trimmed)
        end
    end
    return names
end

-- ============================================================
-- MISC TAB – LEFT SIDE
-- ============================================================

-- Tutorial
local TutorialBox = Tabs["Misc"]:AddLeftGroupbox("Tutorial", "book-open")
TutorialBox:AddLabel({ Text = "Walks through all 5 stages then loads your config.", DoesWrap = true })

local function GetConfigList()
    local list = { "None" }
    local ok, result = pcall(function() return SaveManager:RefreshConfigList() end)
    if ok and result then
        for _, name in ipairs(result) do
            table.insert(list, name)
        end
    end
    return list
end

AddDropdown(TutorialBox, "TutorialLoadConfig", "Load Config After", GetConfigList(), "None", false)

TutorialBox:AddButton({
    Text = "Refresh Config List",
    Func = function()
        local fresh = GetConfigList()
        Options.TutorialLoadConfig:SetValues(fresh)
        local current = Options.TutorialLoadConfig.Value
        if not table.find(fresh, current) then
            Options.TutorialLoadConfig:SetValue("None")
        end
        Library:Notify("Config list refreshed! (" .. (#fresh - 1) .. " found)")
    end
})

TutorialBox:AddButton({
    Text = "Auto Complete Tutorial",
    Func = function()
        -- Auto-refresh config list
        local fresh = GetConfigList()
        Options.TutorialLoadConfig:SetValues(fresh)
        local current = Options.TutorialLoadConfig.Value
        if not table.find(fresh, current) then
            Options.TutorialLoadConfig:SetValue("None")
        end

        local stage = PlayerData.Data and PlayerData.Data.TutorialStage or 0

        if stage >= 6 then
            Library:Notify("Tutorial already complete! (Stage " .. stage .. ")")
            return
        end

        Library:Notify("Auto Tutorial: Starting from stage " .. stage .. "...")

        task.spawn(function()
            -- ── Stage 1 → 2: need 50 clicks ──────────────────────
            if (PlayerData.Data.TutorialStage or 0) <= 1 then
                Library:Notify("Auto Tutorial: Stage 1 — clicking 50x...")
                for _ = 1, 80 do
                    ClickRemote:FireServer()
                    task.wait(0.1)
                end
                local waited = 0
                repeat task.wait(0.2) waited += 0.2
                until (PlayerData.Data.TutorialStage or 0) >= 2 or waited >= 8
            end

            -- ── Stage 2 → 3: teleport to Starter egg then hatch 1 ─
            if (PlayerData.Data.TutorialStage or 0) <= 2 then
                Library:Notify("Auto Tutorial: Stage 2 — hatching Starter egg...")
                TeleportToEgg("Starter")
                task.wait(0.5)
                EggRemote:FireServer("Starter", "E")
                task.wait(1)
                PetActionRemote:FireServer("Equip Best")
                task.wait(0.5)
                local waited = 0
                repeat task.wait(0.2) waited += 0.2
                until (PlayerData.Data.TutorialStage or 0) >= 3 or waited >= 8
            end

            -- ── Stage 3 → 4: equip a pet ─────────────────────────
            if (PlayerData.Data.TutorialStage or 0) <= 3 then
                Library:Notify("Auto Tutorial: Stage 3 — equipping pet...")
                PetActionRemote:FireServer("Equip Best")
                task.wait(0.5)
                local waited = 0
                repeat task.wait(0.2) waited += 0.2
                until (PlayerData.Data.TutorialStage or 0) >= 4 or waited >= 8
            end

            -- ── Stage 4 → 5: rebirth ─────────────────────────────
            if (PlayerData.Data.TutorialStage or 0) <= 4 then
                Library:Notify("Auto Tutorial: Stage 4 — clicking for rebirth...")
                for _ = 1, 120 do
                    ClickRemote:FireServer()
                    task.wait(0.05)
                end
                RebirthRemote:FireServer(1)
                task.wait(1)
                local waited = 0
                repeat task.wait(0.2) waited += 0.2
                until (PlayerData.Data.TutorialStage or 0) >= 5 or waited >= 8
            end

            -- ── Stage 5 → 6: TutorialEnd ─────────────────────────
            if (PlayerData.Data.TutorialStage or 0) <= 5 then
                Library:Notify("Auto Tutorial: Stage 5 — finishing...")
                AdditionalRemote:FireServer("TutorialEnd")
                task.wait(1)
            end

            -- ── Result ────────────────────────────────────────────
            local final = PlayerData.Data.TutorialStage or 0
            if final >= 6 then
                Library:Notify("✅ Tutorial complete!")
                local configName = Options.TutorialLoadConfig.Value
                if configName and configName ~= "None" then
                    task.wait(0.5)
                    local ok, err = SaveManager:Load(configName)
                    if ok then
                        Library:Notify("✅ Config loaded: " .. configName)
                    else
                        Library:Notify("⚠️ Config load failed: " .. tostring(err))
                    end
                end
            else
                Library:Notify("⚠️ Still at stage " .. final .. " — try manually.")
            end
        end)
    end
})

-- Codes
local CodesBox = Tabs["Misc"]:AddLeftGroupbox("Codes", "key")
CodesBox:AddButton({
    Text = "Redeem All Codes",
    Func = function()
        local codes   = CodesModule.Codes or CodesModule
        local claimed = PlayerData.Data.RedeemedCodes or {}
        local count   = 0
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

-- Auto Accept Trade
local AutoAcceptTradeBox = Tabs["Misc"]:AddLeftGroupbox("Auto Accept Trade", "check-circle")
AddCheckbox(AutoAcceptTradeBox, "ToggleAutoAcceptTrade", "Accept All Requests")
AutoAcceptTradeBox:AddLabel({ Text = "Leave usernames blank to accept from anyone.", DoesWrap = true })
AutoAcceptTradeBox:AddInput("AutoAcceptTradeUsers", {
    Text        = "Accept Only From (user1,user2,...)",
    Placeholder = "Leave blank to accept from anyone",
})

-- Auto Confirm Trade
local AutoConfirmTradeBox = Tabs["Misc"]:AddLeftGroupbox("Auto Confirm Trade", "check-square")
AutoConfirmTradeBox:AddLabel({ Text = "Automatically clicks Ready when a trade starts.", DoesWrap = true })
AddCheckbox(AutoConfirmTradeBox, "ToggleAutoConfirmTrade", "Auto Confirm Trade")

-- Auto Trade (send requests)
local AutoTradeBox = Tabs["Misc"]:AddLeftGroupbox("Auto Trade", "repeat")
AutoTradeBox:AddLabel({ Text = "Comma-separated usernames to trade with.", DoesWrap = true })
AutoTradeBox:AddInput("AutoTradeUsernames", {
    Text        = "Usernames (user1,user2,...)",
    Placeholder = "player1,player2",
})
AddCheckbox(AutoTradeBox, "ToggleAutoTrade", "Auto Send Trade Requests")

-- ============================================================
-- MISC TAB – RIGHT SIDE
-- ============================================================

-- Misc
local MiscBox = Tabs["Misc"]:AddRightGroupbox("Misc", "shield")
AddCheckbox(MiscBox, "ToggleDisableAutoRejoin", "Disable Auto Rejoin")

-- ============================================================
-- AUTO SETTINGS
-- ============================================================
local AutoSettingsBox = Tabs["Misc"]:AddRightGroupbox("Auto Settings", "sliders")
AutoSettingsBox:AddLabel({ Text = "Select desired state for each setting. Only fires when value needs to change.", DoesWrap = true })
AddDropdown(AutoSettingsBox, "SettingsWantOn",  "Force ON",  GameSettingsList, {}, true)
AddDropdown(AutoSettingsBox, "SettingsWantOff", "Force OFF", GameSettingsList, {}, true)
AddCheckbox(AutoSettingsBox, "ToggleAutoSettings", "Auto Apply Settings")

-- ============================================================
-- FPS CAP
-- ============================================================
local FpsCapBox = Tabs["Misc"]:AddRightGroupbox("FPS Cap", "monitor")
FpsCapBox:AddLabel({ Text = "Caps your client FPS via RunService throttle.", DoesWrap = true })
FpsCapBox:AddInput("FpsCapValue", { Text = "FPS Limit", Placeholder = "e.g. 60" })
AddCheckbox(FpsCapBox, "ToggleFpsCap", "Enable FPS Cap")

-- Webhook
local WebhookBox = Tabs["Misc"]:AddRightGroupbox("Webhook", "bell")
local PingTypes  = { "None", "User", "Role" }
WebhookBox:AddInput("WebhookURL",    { Text = "Webhook URL", Placeholder = "discord.com/api/webhooks/..." })
WebhookBox:AddInput("WebhookPingID", { Text = "Ping ID",     Placeholder = "User or Role ID" })
AddDropdown(WebhookBox, "WebhookPingType",       "Ping Type",       PingTypes,  "None", false)
AddDropdown(WebhookBox, "WebhookNotifyRarities", "Notify Rarities", RarityList, {}, true)
AddDropdown(WebhookBox, "WebhookPingRarities",   "Ping Rarities",   RarityList, {}, true)
AddCheckbox(WebhookBox, "ToggleWebhook", "Enable Webhook")

-- ============================================================
-- Index Status helper
-- ============================================================
local function UpdateIndexStatus(target)
    if not target then
        IndexStatusImage:SetImage("rbxassetid://0")
        IndexLabelPet:SetText("Pet: —")
        IndexLabelEgg:SetText("Egg: —")
        IndexLabelRarity:SetText("Rarity: —")
        IndexLabelStage:SetText("Stage: Idle")
        IndexLabelProgress:SetText("Progress: —")
        return
    end
    local petData = PetsModule.Pets[target.pet]
    if petData and petData.IDs then
        local assetId = petData.IDs[target.variant] or petData.IDs["Normal"]
        if assetId then IndexStatusImage:SetImage(assetId) end
    end
    local rarity = petData and petData.Rarity or "?"
    IndexLabelPet:SetText("Pet: " .. target.pet)
    IndexLabelEgg:SetText("Egg: " .. target.egg)
    IndexLabelRarity:SetText("Rarity: " .. rarity)
    local stageMap = { Normal = "Hatching Normal", Golden = "Crafting Golden", Diamond = "Crafting Diamond" }
    IndexLabelStage:SetText("Stage: " .. (stageMap[target.variant] or target.variant))
    local indexed = #PlayerData.Data.Index
    local total = 0
    for _ in pairs(PetsModule.Pets) do total = total + 3 end
    IndexLabelProgress:SetText("Progress: " .. indexed .. "/" .. total)
end

-- ============================================================
-- No Hatch Animation hook
-- ============================================================
local _hookRef_fn       = nil
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
                                if eventType == "Unbox" and Toggles.ToggleNoHatchAnim.Value then return end
                                return original(eventType, ...)
                            end))
                            _hookRef_fn       = conn.Function
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
-- ============================================================
local _teleportHookOriginal = nil

local function InstallTeleportBlock()
    if _teleportHookOriginal then return end
    _teleportHookOriginal = hookfunction(TeleportService.Teleport, newcclosure(function(self, placeId, ...)
        if Toggles.ToggleDisableAutoRejoin.Value then return end
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
    if state then InstallTeleportBlock()
    else RemoveTeleportBlock() end
end)

-- ============================================================
-- LOGIC
-- ============================================================

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
            local key   = RebirthTierKeys[label]
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
                    local price   = data.Prices and data.Prices[current]
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

-- Auto Equip Best (pets)
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
                    local bought    = PlayerData.Data["Item" .. i .. "Stock"] or 0
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

-- Auto Golden Craft
local autogoldentask
local function StartAutoGolden()
    if autogoldentask then task.cancel(autogoldentask) autogoldentask = nil end
    autogoldentask = task.spawn(function()
        while Toggles.ToggleAutoGolden.Value do
            local selected = Options.GoldenPetSelect.Value
            local needed   = CraftSuccessMap[Options.GoldenSuccessRate.Value] or 5
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

-- Auto Diamond Craft
local autodiamondtask
local function StartAutoDiamond()
    if autodiamondtask then task.cancel(autodiamondtask) autodiamondtask = nil end
    autodiamondtask = task.spawn(function()
        while Toggles.ToggleAutoDiamond.Value do
            local selected = Options.DiamondPetSelect.Value
            local needed   = CraftSuccessMap[Options.DiamondSuccessRate.Value] or 5
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

-- Auto Claim Season Rewards
local claimseasontask
local function StartClaimSeason()
    if claimseasontask then task.cancel(claimseasontask) claimseasontask = nil end
    claimseasontask = task.spawn(function()
        while Toggles.ToggleClaimSeason.Value do
            local currentSeason  = SeasonModule.CurrentSeason
            local playerLevel    = PlayerData.Data["SeasonLVL" .. currentSeason]
            local freeClaimed    = PlayerData.Data["SeasonFreeClaimed" .. currentSeason]
            local premiumClaimed = PlayerData.Data["SeasonPremiumClaimed" .. currentSeason]
            local hasPremium     = PlayerData.Data["PremiumPass" .. currentSeason]
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
            local passQuests    = PlayerData.Data["PassQuests" .. currentSeason]
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

-- ============================================================
-- Auto Auras
-- ============================================================
local function GetBestOwnedAura()
    local bestName, bestMult = nil, -1
    for _, auraName in ipairs(PlayerData.Data.Auras or {}) do
        local data = AurasModule.Auras[auraName]
        if data and (data.Multiplier or 0) > bestMult then
            bestMult = data.Multiplier
            bestName = auraName
        end
    end
    return bestName
end

local autoaurabuytask
local function StartAutoBuyAuras()
    if autoaurabuytask then task.cancel(autoaurabuytask) autoaurabuytask = nil end
    autoaurabuytask = task.spawn(function()
        while Toggles.ToggleAutoBuyAuras.Value do
            local selected = Options.AuraSelect.Value
            for auraName in pairs(selected) do
                local auraData = AurasModule.Auras[auraName]
                if auraData and not table.find(PlayerData.Data.Auras, auraName) then
                    local price    = auraData.Price or 0
                    local currency = auraData.Currency or "Gems"
                    if (PlayerData.Data[currency] or 0) >= price then
                        AurasRemote:FireServer("Buy", auraName)
                        task.wait(0.5)
                    end
                end
            end
            task.wait(3)
        end
    end)
end
Toggles.ToggleAutoBuyAuras:OnChanged(function(state)
    if state then StartAutoBuyAuras()
    else if autoaurabuytask then task.cancel(autoaurabuytask) autoaurabuytask = nil end end
end)

local autoequipbestauratask
local function StartAutoEquipBestAura()
    if autoequipbestauratask then task.cancel(autoequipbestauratask) autoequipbestauratask = nil end
    autoequipbestauratask = task.spawn(function()
        while Toggles.ToggleAutoEquipBestAura.Value do
            local best = GetBestOwnedAura()
            if best and PlayerData.Data.AuraEquipped ~= best then
                AurasRemote:FireServer("Equip", best)
                task.wait(0.5)
            end
            task.wait(3)
        end
    end)
end
Toggles.ToggleAutoEquipBestAura:OnChanged(function(state)
    if state then StartAutoEquipBestAura()
    else if autoequipbestauratask then task.cancel(autoequipbestauratask) autoequipbestauratask = nil end end
end)

-- ============================================================
-- Auto TapSkins
-- ============================================================
local function GetBestOwnedTapSkin()
    local bestName, bestMult = nil, -1
    for _, skinName in ipairs(PlayerData.Data.TapSkins or {}) do
        local data = TapSkinsModule.TapSkins[skinName]
        if data and (data.Multiplier or 0) > bestMult then
            bestMult = data.Multiplier
            bestName = skinName
        end
    end
    return bestName
end

local autotapskinbuytask
local function StartAutoBuyTapSkins()
    if autotapskinbuytask then task.cancel(autotapskinbuytask) autotapskinbuytask = nil end
    autotapskinbuytask = task.spawn(function()
        while Toggles.ToggleAutoBuyTapSkins.Value do
            local selected = Options.TapSkinSelect.Value
            for skinName in pairs(selected) do
                local skinData = TapSkinsModule.TapSkins[skinName]
                if skinData and not table.find(PlayerData.Data.TapSkins, skinName) then
                    local price    = skinData.Price or 0
                    local currency = skinData.Currency or "Gems"
                    if (PlayerData.Data[currency] or 0) >= price then
                        TapSkinsRemote:FireServer("Buy", skinName)
                        task.wait(0.5)
                    end
                end
            end
            task.wait(3)
        end
    end)
end
Toggles.ToggleAutoBuyTapSkins:OnChanged(function(state)
    if state then StartAutoBuyTapSkins()
    else if autotapskinbuytask then task.cancel(autotapskinbuytask) autotapskinbuytask = nil end end
end)

local autoequipbesttapskintask
local function StartAutoEquipBestTapSkin()
    if autoequipbesttapskintask then task.cancel(autoequipbesttapskintask) autoequipbesttapskintask = nil end
    autoequipbesttapskintask = task.spawn(function()
        while Toggles.ToggleAutoEquipBestTapSkin.Value do
            local best = GetBestOwnedTapSkin()
            if best and PlayerData.Data.TapEquipped ~= best then
                TapSkinsRemote:FireServer("Equip", best)
                task.wait(0.5)
            end
            task.wait(3)
        end
    end)
end
Toggles.ToggleAutoEquipBestTapSkin:OnChanged(function(state)
    if state then StartAutoEquipBestTapSkin()
    else if autoequipbesttapskintask then task.cancel(autoequipbesttapskintask) autoequipbesttapskintask = nil end end
end)

-- ============================================================
-- Auto Claim Index Reward
-- ============================================================
local autoclaimindexrewardtask
local function StartAutoClaimIndexReward()
    if autoclaimindexrewardtask then task.cancel(autoclaimindexrewardtask) autoclaimindexrewardtask = nil end
    autoclaimindexrewardtask = task.spawn(function()
        while Toggles.ToggleAutoClaimIndexReward.Value do
            local questText = LocalPlayer.PlayerGui.MainUI.Frames.Index.Quest.Text
            local current, threshold = questText:match("(%d+)/(%d+)")
            current   = tonumber(current)
            threshold = tonumber(threshold)
            if current and threshold and current >= threshold then
                AdditionalRemote:FireServer("IndexReward")
                task.wait(2)
            end
            task.wait(5)
        end
    end)
end
Toggles.ToggleAutoClaimIndexReward:OnChanged(function(state)
    if state then StartAutoClaimIndexReward()
    else if autoclaimindexrewardtask then task.cancel(autoclaimindexrewardtask) autoclaimindexrewardtask = nil end end
end)

-- ============================================================
-- AUTO SETTINGS
-- ============================================================
local autosettingstask

local function ApplySettingsPass()
    local wantOn  = Options.SettingsWantOn.Value
    local wantOff = Options.SettingsWantOff.Value
    for _, settingName in ipairs(GameSettingsList) do
        local current = PlayerData.Data[settingName]
        if wantOn[settingName] and current ~= true then
            SettingsRemote:FireServer(settingName)
            task.wait(0.3)
        elseif wantOff[settingName] and current ~= false then
            SettingsRemote:FireServer(settingName)
            task.wait(0.3)
        end
    end
end

local function StartAutoSettings()
    if autosettingstask then task.cancel(autosettingstask) autosettingstask = nil end
    autosettingstask = task.spawn(function()
        ApplySettingsPass()
        while Toggles.ToggleAutoSettings.Value do
            task.wait(5)
            if Toggles.ToggleAutoSettings.Value then
                ApplySettingsPass()
            end
        end
    end)
end

Toggles.ToggleAutoSettings:OnChanged(function(state)
    if state then
        local wantOn  = Options.SettingsWantOn.Value
        local wantOff = Options.SettingsWantOff.Value
        if not next(wantOn) and not next(wantOff) then
            Library:Notify("Auto Settings: Select at least one setting first!")
            Toggles.ToggleAutoSettings:SetValue(false)
            return
        end
        StartAutoSettings()
    else
        if autosettingstask then task.cancel(autosettingstask) autosettingstask = nil end
    end
end)

-- ============================================================
-- FPS CAP
-- ============================================================
local function ApplyFpsCap()
    local val = tonumber(Options.FpsCapValue.Value)
    if val and val > 0 then
        setfpscap(val)
    end
end

local function RemoveFpsCap()
    setfpscap(0)
end

Toggles.ToggleFpsCap:OnChanged(function(state)
    if state then ApplyFpsCap()
    else RemoveFpsCap() end
end)

Options.FpsCapValue:OnChanged(function()
    if Toggles.ToggleFpsCap.Value then
        ApplyFpsCap()
    end
end)

-- ============================================================
-- Auto Accept Trade Request
-- ============================================================
local autoAcceptTradeConn = nil

local function InstallAutoAcceptTrade()
    if autoAcceptTradeConn then autoAcceptTradeConn:Disconnect() autoAcceptTradeConn = nil end
    autoAcceptTradeConn = TradeRemote.OnClientEvent:Connect(function(eventType, senderName)
        if eventType ~= "TradeRequest" then return end
        if not Toggles.ToggleAutoAcceptTrade.Value then return end

        local whitelist = ParseUsernames(Options.AutoAcceptTradeUsers.Value)
        if #whitelist > 0 then
            local allowed = false
            for _, name in ipairs(whitelist) do
                if name:lower() == tostring(senderName):lower() then
                    allowed = true
                    break
                end
            end
            if not allowed then return end
        end

        local sender = Players:FindFirstChild(senderName)
        if sender then
            task.wait(0.1)
            TradeRemote:FireServer({ "AcceptRequest", sender })
        end
    end)
end

Toggles.ToggleAutoAcceptTrade:OnChanged(function(state)
    if state then InstallAutoAcceptTrade()
    else if autoAcceptTradeConn then autoAcceptTradeConn:Disconnect() autoAcceptTradeConn = nil end end
end)

-- ============================================================
-- Auto Confirm Trade
-- ============================================================
local autoConfirmTradeConn = nil
local currentTradePartner  = nil

local function InstallAutoConfirmTrade()
    if autoConfirmTradeConn then autoConfirmTradeConn:Disconnect() autoConfirmTradeConn = nil end
    local confirmDebounce = nil
    autoConfirmTradeConn = TradeRemote.OnClientEvent:Connect(function(eventType, partnerName)
        if not Toggles.ToggleAutoConfirmTrade.Value then return end

        if eventType == "CreateTrade" then
            currentTradePartner = partnerName
        elseif eventType == "ClearTrade" or eventType == "TradeEnd" then
            currentTradePartner = nil
            if confirmDebounce then task.cancel(confirmDebounce) confirmDebounce = nil end
            return
        end

        if eventType ~= "CreateTrade" and eventType ~= "Cancel" then return end
        if not currentTradePartner then return end

        if confirmDebounce then task.cancel(confirmDebounce) confirmDebounce = nil end
        confirmDebounce = task.delay(0.75, function()
            confirmDebounce = nil
            if not Toggles.ToggleAutoConfirmTrade.Value then return end
            if not currentTradePartner then return end
            local partner = Players:FindFirstChild(currentTradePartner)
            if partner then
                TradeRemote:FireServer({ "AcceptTrade", partner })
            end
        end)
    end)
end

Toggles.ToggleAutoConfirmTrade:OnChanged(function(state)
    if state then InstallAutoConfirmTrade()
    else
        if autoConfirmTradeConn then autoConfirmTradeConn:Disconnect() autoConfirmTradeConn = nil end
        currentTradePartner = nil
    end
end)

-- ============================================================
-- Auto Trade (send requests to specific players)
-- ============================================================
local autotradetask
local function StartAutoTrade()
    if autotradetask then task.cancel(autotradetask) autotradetask = nil end
    autotradetask = task.spawn(function()
        while Toggles.ToggleAutoTrade.Value do
            local usernames = ParseUsernames(Options.AutoTradeUsernames.Value)
            if #usernames == 0 then
                task.wait(3)
                continue
            end
            for _, name in ipairs(usernames) do
                if not Toggles.ToggleAutoTrade.Value then break end
                local target = Players:FindFirstChild(name)
                if target and target ~= LocalPlayer then
                    local targetPD = target:FindFirstChild("PlayerData")
                    local inTrade  = targetPD and targetPD:FindFirstChild("InTrade") and targetPD.InTrade.Value
                    if not inTrade then
                        TradeRemote:FireServer({ "TradeRequest", target })
                        task.wait(3.5)
                    end
                end
            end
            task.wait(5)
        end
    end)
end
Toggles.ToggleAutoTrade:OnChanged(function(state)
    if state then
        local usernames = ParseUsernames(Options.AutoTradeUsernames.Value)
        if #usernames == 0 then
            Library:Notify("Auto Trade: Enter at least one username first!")
            Toggles.ToggleAutoTrade:SetValue(false)
            return
        end
        StartAutoTrade()
    else
        if autotradetask then task.cancel(autotradetask) autotradetask = nil end
    end
end)

-- ============================================================
-- AUTO DELETE helper (used exclusively by Auto Index)
-- ============================================================
local function RunDeletePass(craftProtectedPet)
    local deleteRarities = Options.IndexDeleteRarities.Value
    local ignorePets     = Options.IndexIgnorePets.Value
    if not next(deleteRarities) then return end

    local toDelete = {}
    for _, pet in pairs(LocalPlayer.Pets:GetChildren()) do
        local petName = pet.Name
        local petData = PetsModule.Pets[petName]
        if petData
            and deleteRarities[petData.Rarity]
            and petName ~= craftProtectedPet
            and not ignorePets[petName]
            and pet:FindFirstChild("ID")
        then
            table.insert(toDelete, pet.ID.Value)
        end
    end
    if #toDelete > 0 then
        for i = 1, #toDelete, 100 do
            local chunk = {}
            for j = i, math.min(i + 99, #toDelete) do
                table.insert(chunk, toDelete[j])
            end
            PetActionRemote:FireServer("Delete", chunk)
            task.wait(0.3)
        end
    end
end

-- ============================================================
-- AUTO INDEX
-- ============================================================
local autoindextask

local function GetIndexed()
    local indexed = {}
    for _, entry in ipairs(PlayerData.Data.Index) do
        indexed[entry] = true
    end
    return indexed
end

local function getNextIndexTarget()
    local targetRarities = Options.IndexRaritySelect.Value
    local ignoreEggs     = Options.IndexIgnoreEggs.Value
    local craftVariants  = Options.IndexCraftVariants.Value
    local indexed        = GetIndexed()

    for _, eggName in ipairs(EggProgressionOrder) do
        if ignoreEggs[eggName] then continue end
        local eggData = EggsModule.Eggs[eggName]
        if not eggData then continue end

        for _, petEntry in ipairs(eggData.Pets) do
            local petName = petEntry.Name
            local petData = PetsModule.Pets[petName]
            if not petData then continue end
            if not targetRarities[petData.Rarity] then continue end

            if not indexed[petName .. "_Normal"] then
                return { egg = eggName, pet = petName, variant = "Normal" }
            end
            if craftVariants["Golden"] and not indexed[petName .. "_Golden"] then
                return { egg = eggName, pet = petName, variant = "Golden" }
            end
            if craftVariants["Diamond"] and not indexed[petName .. "_Diamond"] then
                return { egg = eggName, pet = petName, variant = "Diamond" }
            end
        end
    end

    return nil
end

local function CollectPetIds(petName, petType, limit)
    local ids = {}
    for _, pet in pairs(LocalPlayer.Pets:GetChildren()) do
        if pet.Name == petName
           and pet:FindFirstChild("PetType")
           and pet.PetType.Value == petType
           and pet:FindFirstChild("ID")
        then
            table.insert(ids, pet.ID.Value)
            if limit and #ids >= limit then break end
        end
    end
    return ids
end

local function StartAutoIndex()
    if autoindextask then task.cancel(autoindextask) autoindextask = nil end

    autoindextask = task.spawn(function()
        local lastTargetKey     = nil
        local deleteTimer       = 0
        local craftProtectedPet = nil

        while Toggles.ToggleAutoIndex.Value do

            if next(Options.IndexDeleteRarities.Value) then
                deleteTimer = deleteTimer + 0.3
                if deleteTimer >= 3 then
                    deleteTimer = 0
                    RunDeletePass(craftProtectedPet)
                end
            else
                deleteTimer = 0
            end

            local target = getNextIndexTarget()

            if not target then
                UpdateIndexStatus(nil)
                craftProtectedPet = nil
                Library:Notify("Auto Index: All target pets indexed!")
                Toggles.ToggleAutoIndex:SetValue(false)
                break
            end

            craftProtectedPet = target.pet

            local targetKey = target.egg .. "|" .. target.pet .. "|" .. target.variant
            if targetKey ~= lastTargetKey then
                lastTargetKey = targetKey
                UpdateIndexStatus(target)
                Library:Notify(
                    "Auto Index: " .. target.pet ..
                    " [" .. target.variant .. "] — " .. target.egg
                )
                SwitchRemote:FireServer("AutoHatching", true)
                TeleportToEgg(target.egg)
                task.wait(0.5)
            end

            if target.variant == "Normal" then
                local batch = getBatch(target.egg)
                if batch then
                    EggRemote:FireServer(target.egg, batch)
                    task.wait(0.3)
                else
                    task.wait(1)
                end

            elseif target.variant == "Golden" then
                local normalIds = CollectPetIds(target.pet, "Normal", 5)
                if #normalIds >= 5 then
                    PetActionRemote:FireServer("GoldenMachine", { normalIds, target.pet })
                    task.wait(1)
                else
                    local batch = getBatch(target.egg)
                    if batch then EggRemote:FireServer(target.egg, batch) task.wait(0.3)
                    else task.wait(1) end
                end

            elseif target.variant == "Diamond" then
                local goldenIds = CollectPetIds(target.pet, "Golden", 5)
                if #goldenIds >= 5 then
                    PetActionRemote:FireServer("DiamondMachine", { goldenIds, target.pet })
                    task.wait(1)
                else
                    local normalIds = CollectPetIds(target.pet, "Normal", 5)
                    if #normalIds >= 5 then
                        PetActionRemote:FireServer("GoldenMachine", { normalIds, target.pet })
                        task.wait(1)
                    else
                        local batch = getBatch(target.egg)
                        if batch then EggRemote:FireServer(target.egg, batch) task.wait(0.3)
                        else task.wait(1) end
                    end
                end
            end
        end

        craftProtectedPet = nil
        UpdateIndexStatus(nil)
        SwitchRemote:FireServer("AutoHatching", false)
    end)
end

Toggles.ToggleAutoIndex:OnChanged(function(state)
    if state then
        if not next(Options.IndexRaritySelect.Value) then
            Library:Notify("Auto Index: Select at least one rarity first!")
            Toggles.ToggleAutoIndex:SetValue(false)
            return
        end
        StartAutoIndex()
    else
        if autoindextask then task.cancel(autoindextask) autoindextask = nil end
        UpdateIndexStatus(nil)
        SwitchRemote:FireServer("AutoHatching", false)
    end
end)

-- ============================================================
-- WEBHOOK SYSTEM
-- ============================================================
local EMBED_COLOR = 0x00C8B4
local httpReq = (syn and syn.request) or (http and http.request) or request

local function ResolveAssetURL(assetId, size)
    size = size or "420x420"
    for attempt = 1, 2 do
        local ok, res = pcall(httpReq, {
            Url    = "https://thumbnails.roproxy.com/v1/assets?assetIds=" .. assetId
                   .. "&returnPolicy=PlaceHolder&size=" .. size .. "&format=Png",
            Method = "GET",
        })
        if not ok or not res or res.StatusCode ~= 200 then return nil end
        local ok2, body = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if not ok2 or not body or not body.data or not body.data[1] then return nil end
        local entry = body.data[1]
        if entry.state == "Completed" then return entry.imageUrl end
        if attempt == 1 then task.wait(2) end
    end
    return nil
end

local function ResolveIconURL(assetId)
    local url = ResolveAssetURL(assetId, "150x150")
    if url then return url end
    local ok, res = pcall(httpReq, {
        Url    = "https://assetdelivery.roproxy.com/v2/assetId/" .. assetId,
        Method = "GET",
    })
    if ok and res and res.StatusCode == 200 then
        local ok2, body = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if ok2 and body and body.location then return body.location end
    end
    return nil
end

local function ResolveAvatarURL(userId)
    local ok, res = pcall(httpReq, {
        Url    = "https://thumbnails.roproxy.com/v1/users/avatar-headshot?userIds=" .. tostring(userId)
               .. "&size=420x420&format=Png",
        Method = "GET",
    })
    if not ok or not res or res.StatusCode ~= 200 then return nil end
    local ok2, body = pcall(HttpService.JSONDecode, HttpService, res.Body)
    if not ok2 or not body or not body.data or not body.data[1] then return nil end
    return body.data[1].imageUrl
end

local function GetPetImageURL(petName, petType)
    local data = PetsModule.Pets[petName]
    if not data or not data.IDs then return nil end
    local assetId = tostring(data.IDs[petType] or data.IDs["Normal"]):match("%d+")
    if not assetId then return nil end
    return ResolveAssetURL(assetId, "512x512")
end

local PhosphyIconURL = nil
task.spawn(function() PhosphyIconURL = ResolveIconURL("111288992980872") end)

local cachedAvatarURL = nil
task.spawn(function() cachedAvatarURL = ResolveAvatarURL(LocalPlayer.UserId) end)

local function BuildEmbed(petName, rarity, petType, petImageURL, playerAvatarURL)
    local embed = {
        title  = "🥚  " .. rarity .. " — " .. petName .. " Hatched!",
        color  = EMBED_COLOR,
        fields = {
            { name = "Pet",          value = petName,                         inline = true },
            { name = "Rarity",       value = rarity,                          inline = true },
            { name = "Type",         value = petType or "Normal",             inline = true },
            { name = "Player",       value = LocalPlayer.Name,                inline = true },
            { name = "Eggs Hatched", value = tostring(PlayerData.Data.Eggs),  inline = true },
        },
        footer    = { text = "Phosphy  •  ClickBreakers" },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    if petImageURL     then embed.image     = { url = petImageURL     } end
    if playerAvatarURL then embed.thumbnail = { url = playerAvatarURL } end
    return embed
end

local function PostWebhook(url, content, embeds)
    local payload = HttpService:JSONEncode({
        username   = "Phosphy",
        avatar_url = PhosphyIconURL or nil,
        content    = (content and content ~= "") and content or nil,
        embeds     = embeds,
    })
    pcall(httpReq, {
        Url     = url,
        Method  = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body    = payload,
    })
end

local webhookConn = nil

local function InstallWebhookListener()
    if webhookConn then webhookConn:Disconnect() webhookConn = nil end
    webhookConn = EggRemote.OnClientEvent:Connect(function(eventType, _, _, pets)
        if eventType ~= "Unbox" then return end
        if not Toggles.ToggleWebhook.Value then return end
        local url = Options.WebhookURL.Value
        if not url or url == "" then return end
        if not pets then return end

        task.spawn(function()
            local pingStr  = ""
            local pingType = Options.WebhookPingType.Value
            local pingID   = Options.WebhookPingID.Value or ""
            if pingType == "User" and pingID ~= "" then
                pingStr = "<@" .. pingID .. "> "
            elseif pingType == "Role" and pingID ~= "" then
                pingStr = "<@&" .. pingID .. "> "
            end

            local notifyRarities = Options.WebhookNotifyRarities.Value
            local pingRarities   = Options.WebhookPingRarities.Value
            local pingEmbeds     = {}

            for _, petInfo in pairs(pets) do
                local petName = petInfo.PetName
                local petType = (type(petInfo) == "table" and petInfo.PetType) or "Normal"
                local petData = PetsModule.Pets[petName]
                if not petData then continue end

                local rarity       = petData.Rarity
                local shouldNotify = notifyRarities[rarity]
                local shouldPing   = pingRarities[rarity]
                if not shouldNotify and not shouldPing then continue end

                local petImg = GetPetImageURL(petName, petType)
                local embed  = BuildEmbed(petName, rarity, petType, petImg, cachedAvatarURL)

                if shouldPing and #pingEmbeds < 10 then
                    table.insert(pingEmbeds, embed)
                elseif shouldNotify then
                    PostWebhook(url, "", { embed })
                    task.wait(0.5)
                end
            end

            if #pingEmbeds > 0 then
                PostWebhook(url, pingStr, pingEmbeds)
            end
        end)
    end)
end

Toggles.ToggleWebhook:OnChanged(function(state)
    if state then InstallWebhookListener()
    else if webhookConn then webhookConn:Disconnect() webhookConn = nil end end
end)

-- ============================================================
-- Unload cleanup
-- ============================================================
Library:OnUnload(function()
    if _hookRef_fn and _hookRef_original then
        hookfunction(_hookRef_fn, _hookRef_original)
        _hookRef_fn       = nil
        _hookRef_original = nil
    end
    RemoveTeleportBlock()
    RemoveFpsCap()

    if actask                    then task.cancel(actask)                    actask                    = nil end
    if ahtask                    then task.cancel(ahtask)                    ahtask                    = nil end
    if autorebirththask          then task.cancel(autorebirththask)          autorebirththask          = nil end
    if autospintask              then task.cancel(autospintask)              autospintask              = nil end
    if autoevilspintask          then task.cancel(autoevilspintask)          autoevilspintask          = nil end
    if autoupgradetask           then task.cancel(autoupgradetask)           autoupgradetask           = nil end
    if autoequiptask             then task.cancel(autoequiptask)             autoequiptask             = nil end
    if autobuytask               then task.cancel(autobuytask)               autobuytask               = nil end
    if autouseitemstask          then task.cancel(autouseitemstask)          autouseitemstask          = nil end
    if claimgiftstask            then task.cancel(claimgiftstask)            claimgiftstask            = nil end
    if claimdailytask            then task.cancel(claimdailytask)            claimdailytask            = nil end
    if claimachtask              then task.cancel(claimachtask)              claimachtask              = nil end
    if claimchesttask            then task.cancel(claimchesttask)            claimchesttask            = nil end
    if autogoldentask            then task.cancel(autogoldentask)            autogoldentask            = nil end
    if autodiamondtask           then task.cancel(autodiamondtask)           autodiamondtask           = nil end
    if claimseasontask           then task.cancel(claimseasontask)           claimseasontask           = nil end
    if claimquesttask            then task.cancel(claimquesttask)            claimquesttask            = nil end
    if autoaurabuytask           then task.cancel(autoaurabuytask)           autoaurabuytask           = nil end
    if autoequipbestauratask     then task.cancel(autoequipbestauratask)     autoequipbestauratask     = nil end
    if autotapskinbuytask        then task.cancel(autotapskinbuytask)        autotapskinbuytask        = nil end
    if autoequipbesttapskintask  then task.cancel(autoequipbesttapskintask)  autoequipbesttapskintask  = nil end
    if autoclaimindexrewardtask  then task.cancel(autoclaimindexrewardtask)  autoclaimindexrewardtask  = nil end
    if autotradetask             then task.cancel(autotradetask)             autotradetask             = nil end
    if autoindextask             then task.cancel(autoindextask)             autoindextask             = nil end
    if autosettingstask          then task.cancel(autosettingstask)          autosettingstask          = nil end
    if autoAcceptTradeConn       then autoAcceptTradeConn:Disconnect()       autoAcceptTradeConn       = nil end
    if autoConfirmTradeConn      then autoConfirmTradeConn:Disconnect()      autoConfirmTradeConn      = nil end
    if webhookConn               then webhookConn:Disconnect()               webhookConn               = nil end

    currentTradePartner = nil
    UpdateIndexStatus(nil)
    SwitchRemote:FireServer("AutoHatching", false)
end)

-- ============================================================
-- UI Settings Tab
-- ============================================================
local UISettings = Tabs["UI Settings"]:AddRightGroupbox("General", "wrench")
UISettings:AddLabel("MenuBind"):AddKeyPicker("MenuKeybind", {
    Default = "RightShift",
    NoUI    = true,
    Text    = "Menu keybind"
})
UISettings:AddButton({
    Text = "Unload",
    Func = function() Library:Unload() end
})

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("PhosphyHub")
ThemeManager:SetDefaultTheme({
    FontColor       = Color3.fromRGB(220, 255, 250),
    MainColor       = Color3.fromRGB(25, 25, 25),
    AccentColor     = Color3.fromRGB(0, 200, 180),
    BackgroundColor = Color3.fromRGB(15, 15, 15),
    OutlineColor    = Color3.fromRGB(40, 40, 40),
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
