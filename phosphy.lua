local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local PhosphyRepo = "https://raw.githubusercontent.com/Beonneon/Phosphy/refs/heads/main/"
local Library = loadstring(game:HttpGet(PhosphyRepo .. "LibraryV3.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(PhosphyRepo .. "SaveManagerV3.lua"))()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Anti-AFK
local VirtualUser = game:GetService("VirtualUser")
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

repeat task.wait(0.1) until LocalPlayer and LocalPlayer.PlayerScripts:FindFirstChild("PlayerData", true)

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
local AurasModule = require(Modules:WaitForChild("Auras"))
local TapSkinsModule = require(Modules:WaitForChild("TapSkins"))

repeat task.wait(0.1) until PlayerData.Data and PlayerData.Data.Items

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
local AurasRemote = Events:WaitForChild("Auras")
local TapSkinsRemote = Events:WaitForChild("TapSkins")
local TradeRemote = Events:WaitForChild("Trade")
local AdditionalRemote = Events:WaitForChild("Additional")
local SettingsRemote = Events:WaitForChild("Settings")
local PotionCraftingRemote = Events:WaitForChild("PotionCrafting")

local MainUI = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("MainUI")
local Rewards = MainUI.Frames.Rewards

local EggList = {}
for name, data in pairs(EggsModule.Eggs) do
    if data.Currency ~= "Robux" then
        table.insert(EggList, name)
    end
end
table.sort(EggList)

local function BuildEggProgressionOrder()
    local clicksEggs = {}
    local robuxEggs = {}

    for name, data in pairs(EggsModule.Eggs) do
        if data.Currency == "Robux" then
            table.insert(robuxEggs, { name = name, price = data.Price or 0 })
        else
            table.insert(clicksEggs, { name = name, price = data.Price or 0 })
        end
    end

    table.sort(clicksEggs, function(a, b) return a.price < b.price end)
    table.sort(robuxEggs, function(a, b) return a.price < b.price end)

    local order = {}
    for _, entry in ipairs(clicksEggs) do table.insert(order, entry.name) end
    for _, entry in ipairs(robuxEggs) do table.insert(order, entry.name) end

    return order
end

local EggProgressionOrder = BuildEggProgressionOrder()

local MerchantItemList = {}
for itemName in pairs(Items.Items) do
    table.insert(MerchantItemList, itemName)
end
table.sort(MerchantItemList)

local MerchantDefaultSelected = {}
for _, name in ipairs(MerchantItemList) do
    MerchantDefaultSelected[name] = true
end

local function fmtNum(n)
    if n >= 1e12 then
        return string.format("%.0fT", n / 1e12)
    elseif n >= 1e9 then
        return string.format("%.0fB", n / 1e9)
    elseif n >= 1e6 then
        return string.format("%.0fM", n / 1e6)
    elseif n >= 1e3 then
        return string.format("%.0fK", n / 1e3)
    end
    return tostring(n)
end

local RebirthTiers = {}
local RebirthTierKeys = {}
for i, amount in ipairs(RebirthsModule.Rebirths) do
    local label = fmtNum(amount) .. (amount == 1 and " Rebirth" or " Rebirths")
    table.insert(RebirthTiers, label)
    RebirthTierKeys[label] = i
end
table.insert(RebirthTiers, "Infinity Rebirth")
RebirthTierKeys["Infinity Rebirth"] = "Inf"

local UpgradeList = {}
local UpgradeDefaultSelected = {}
for name in pairs(UpgradesModule.Upgrades) do
    table.insert(UpgradeList, name)
    UpgradeDefaultSelected[name] = true
end
table.sort(UpgradeList)

local CraftPetList = {}
for name, data in pairs(PetsModule.Pets) do
    if data.Rarity ~= "Celestial" then
        table.insert(CraftPetList, name)
    end
end
table.sort(CraftPetList)

local CraftSuccessRates = { "20%", "40%", "60%", "80%", "100%" }
local CraftSuccessMap = { ["20%"] = 1, ["40%"] = 2, ["60%"] = 3, ["80%"] = 4, ["100%"] = 5 }

local ItemUseList = {}
for itemName in pairs(PlayerData.Data.Items) do
    table.insert(ItemUseList, itemName)
end
table.sort(ItemUseList)

local PotionCraftList = {}
local PotionCraftLookup = {}
for itemName, itemData in pairs(Items.Items) do
    local isPotion = tostring(itemName):find("Potion", 1, true) ~= nil
    if type(itemData) == "table" then
        isPotion = isPotion
            or itemData.Type == "Potion"
            or itemData.Category == "Potion"
            or itemData.ItemType == "Potion"
    end

    if isPotion and not PotionCraftLookup[itemName] then
        PotionCraftLookup[itemName] = true
        table.insert(PotionCraftList, itemName)
    end
end
table.sort(PotionCraftList)

local AuraList = {}
for name in pairs(AurasModule.Auras) do
    table.insert(AuraList, name)
end
table.sort(AuraList)

local TapSkinList = {}
for name in pairs(TapSkinsModule.TapSkins) do
    table.insert(TapSkinList, name)
end
table.sort(TapSkinList)

local AllPetNamesList = {}
for name in pairs(PetsModule.Pets) do
    table.insert(AllPetNamesList, name)
end
table.sort(AllPetNamesList)

local RarityList = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Exclusive", "Secret", "Celestial" }
local GameSettingsList = { "BetterQuality", "Music", "HideOtherPets", "HideAuras" }
local SummaryMetricList = {
    "Eggs Hatched",
    "Rebirths Gained",
    "Gems Gained",
    "Spins Gained",
    "Evil Spins Gained",
    "Items Net Change",
    "Total Rebirths",
    "Total Gems",
    "Total Eggs Hatched",
    "Total Time Played",
}
local SummaryMetricDefaultSelected = {}
for _, metricName in ipairs(SummaryMetricList) do
    SummaryMetricDefaultSelected[metricName] = true
end

local shopData = {}
local shopSeed = nil
MerchantRemote.OnClientEvent:Connect(function(data, seed)
    if type(data) ~= "table" then return end
    if shopSeed == seed then return end
    shopSeed = seed
    shopData = data
end)
MerchantRemote:FireServer("GetFruitShop")

local function AddCheckbox(groupbox, id, text, default)
    groupbox:AddCheckbox(id, { Text = text, Default = default or false })
end

local function AddDropdown(groupbox, id, text, values, default, multi)
    groupbox:AddDropdown(id, { Text = text, Values = values, Default = default, Multi = multi })
end

local function AddSlider(groupbox, id, text, min, max, default, suffix)
    groupbox:AddSlider(id, {
        Text = text,
        Min = min,
        Max = max,
        Default = default,
        Rounding = 0,
        Suffix = suffix,
    })
end

local function AddDivider(groupbox, text)
    groupbox:AddDivider(text)
end

local Options = Library.Options
local Toggles = Library.Toggles
local SendAlertWebhookTest
local SendSummaryWebhookTest

local Window = Library:CreateWindow({
    Title = "Phosphy",
    Footer = "disc : neonbeon 1.13",
    Icon = 111288992980872,
    Compact = true,
    SidebarCompactWidth = 56,
    NotifySide = "Right",
    ShowCustomCursor = false,
    UnlockMouseWhileOpen = false,
})

local Tabs = {
    Main = Window:AddTab("Main", "user"),
    Pets = Window:AddTab("Pets", "paw-print"),
    Performance = Window:AddTab("Performance", "zap"),
    Webhook = Window:AddTab("Webhook", "bell"),
    Misc = Window:AddTab("Misc", "settings"),
    ["UI Settings"] = Window:AddTab("UI Settings", "folder-cog"),
}

local IndexStatusImage
local IndexLabelPet
local IndexLabelEgg
local IndexLabelRarity
local IndexLabelStage
local IndexLabelProgress

do
    local ACBox = Tabs.Main:AddLeftGroupbox("Auto Clicker", "mouse")
    AddCheckbox(ACBox, "ToggleAC", "Toggle AC")

    local ARBox = Tabs.Main:AddLeftGroupbox("Auto Rebirth", "refresh-cw")
    AddDropdown(ARBox, "RebirthTier", "Tier", RebirthTiers, RebirthTiers[1], false)
    ARBox:AddInput("InfRebirthDelay", { Text = "Inf Delay (s)", Default = "0.5", Placeholder = "Minimum 0.01" })
    AddCheckbox(ARBox, "ToggleAutoRebirth", "Auto Rebirth")

    local SpinBox = Tabs.Main:AddLeftGroupbox("Auto Spin", "rotate-cw")
    AddCheckbox(SpinBox, "ToggleAutoSpin", "Auto Spin")
    AddCheckbox(SpinBox, "ToggleConvertSpins", "Convert Spins to Evil")
    AddCheckbox(SpinBox, "ToggleAutoEvilSpin", "Auto Evil Spin")

    local AutoUseBox = Tabs.Main:AddLeftGroupbox("Auto Use Items", "zap")
    AddDropdown(AutoUseBox, "ItemUseSelect", "Items", ItemUseList, {}, true)
    AddCheckbox(AutoUseBox, "ToggleAutoUseItems", "Auto Use")

    local PotionCraftBox = Tabs.Main:AddLeftGroupbox("Auto Potion Crafting", "flask-conical")
    AddDropdown(PotionCraftBox, "PotionCraftSelect", "Potions", PotionCraftList, {}, true)
    AddCheckbox(PotionCraftBox, "ToggleAutoPotionCraft", "Auto Craft Potions")

    local UpgradeBox = Tabs.Main:AddRightGroupbox("Auto Upgrade", "arrow-up")
    AddDropdown(UpgradeBox, "UpgradeSelect", "Upgrades", UpgradeList, UpgradeDefaultSelected, true)
    AddCheckbox(UpgradeBox, "ToggleAutoUpgrade", "Auto Upgrade")
    task.defer(function()
        Options.UpgradeSelect:SetValue(UpgradeDefaultSelected)
    end)

    local MerchantBox = Tabs.Main:AddRightGroupbox("Fruit Shop", "shopping-cart")
    AddDropdown(MerchantBox, "MerchantItems", "Items to Buy", MerchantItemList, MerchantDefaultSelected, true)
    AddCheckbox(MerchantBox, "ToggleAutoBuy", "Auto Buy")
    task.defer(function()
        Options.MerchantItems:SetValue(MerchantDefaultSelected)
    end)

    local ClaimBox = Tabs.Main:AddRightGroupbox("Auto Claim", "gift")
    AddCheckbox(ClaimBox, "ToggleClaimGifts", "Auto Claim Gifts")
    AddCheckbox(ClaimBox, "ToggleClaimDaily", "Auto Claim Daily")
    AddCheckbox(ClaimBox, "ToggleClaimAchievements", "Auto Claim Achievements")
    AddCheckbox(ClaimBox, "ToggleClaimChests", "Auto Claim Chests")
    AddCheckbox(ClaimBox, "ToggleClaimSeason", "Auto Claim Season")
    AddCheckbox(ClaimBox, "ToggleClaimQuests", "Auto Claim Quests")

    local AurasBox = Tabs.Main:AddRightGroupbox("Auto Auras", "zap")
    AddDropdown(AurasBox, "AuraSelect", "Auras to Buy", AuraList, {}, true)
    AddCheckbox(AurasBox, "ToggleAutoBuyAuras", "Auto Buy Auras")
    AddCheckbox(AurasBox, "ToggleAutoEquipBestAura", "Auto Equip Best Aura")

    local TapSkinsBox = Tabs.Main:AddRightGroupbox("Auto TapSkins", "mouse-pointer")
    AddDropdown(TapSkinsBox, "TapSkinSelect", "Skins to Buy", TapSkinList, {}, true)
    AddCheckbox(TapSkinsBox, "ToggleAutoBuyTapSkins", "Auto Buy TapSkins")
    AddCheckbox(TapSkinsBox, "ToggleAutoEquipBestTapSkin", "Auto Equip Best TapSkin")

    local AHBox = Tabs.Pets:AddLeftGroupbox("Auto Hatch", "egg")
    AddDropdown(AHBox, "EggSelect", "Egg", EggList, EggList[1], false)
    AddCheckbox(AHBox, "ToggleAH", "Toggle Auto Hatch")
    AddCheckbox(AHBox, "ToggleAutoEquipBest", "Auto Equip Best")
    AddCheckbox(AHBox, "ToggleNoHatchAnim", "No Hatch Animation")

    local IndexStatusBox = Tabs.Pets:AddLeftGroupbox("Index Status", "compass")
    IndexStatusImage = IndexStatusBox:AddImage("IndexStatusImage", {
        Image = "rbxassetid://0",
        Height = 130,
        BackgroundTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
    })
    IndexLabelPet = IndexStatusBox:AddLabel({ Text = "Pet: -", DoesWrap = false })
    IndexLabelEgg = IndexStatusBox:AddLabel({ Text = "Egg: -", DoesWrap = false })
    IndexLabelRarity = IndexStatusBox:AddLabel({ Text = "Rarity: -", DoesWrap = false })
    IndexLabelStage = IndexStatusBox:AddLabel({ Text = "Stage: Idle", DoesWrap = false })
    IndexLabelProgress = IndexStatusBox:AddLabel({ Text = "Progress: -", DoesWrap = false })

    local AutoIndexBox = Tabs.Pets:AddLeftGroupbox("Auto Index", "search")
    AddDropdown(AutoIndexBox, "IndexRaritySelect", "Target Rarities", RarityList, {}, true)
    AddDropdown(AutoIndexBox, "IndexIgnoreEggs", "Ignore Eggs", EggList, {}, true)
    AddDropdown(AutoIndexBox, "IndexCraftVariants", "Craft Variants", { "Golden", "Diamond" }, {}, true)
    AddDropdown(AutoIndexBox, "IndexDeleteRarities", "Delete Rarities", RarityList, {}, true)
    AddDropdown(AutoIndexBox, "IndexIgnorePets", "Never Delete Pets", AllPetNamesList, {}, true)
    AddCheckbox(AutoIndexBox, "ToggleAutoClaimIndexReward", "Auto Claim Index Reward")
    AddCheckbox(AutoIndexBox, "ToggleAutoIndex", "Auto Index")

    local MachineTabs = Tabs.Pets:AddRightTabbox("Pet Machines")
    local GoldenBox = MachineTabs:AddTab("Golden", "star")
    AddDropdown(GoldenBox, "GoldenPetSelect", "Pets", CraftPetList, {}, true)
    AddDropdown(GoldenBox, "GoldenSuccessRate", "Success Rate", CraftSuccessRates, "100%", false)
    AddCheckbox(GoldenBox, "ToggleAutoGolden", "Auto Craft Golden")

    local DiamondBox = MachineTabs:AddTab("Diamond", "diamond")
    AddDropdown(DiamondBox, "DiamondPetSelect", "Pets", CraftPetList, {}, true)
    AddDropdown(DiamondBox, "DiamondSuccessRate", "Success Rate", CraftSuccessRates, "100%", false)
    AddCheckbox(DiamondBox, "ToggleAutoDiamond", "Auto Craft Diamond")
end

local function TeleportToEgg(eggName)
    local egg = workspace.Game.Eggs:FindFirstChild(eggName)
    if not egg or not LocalPlayer.Character then return end

    local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.CFrame = egg:GetPivot() + Vector3.new(0, 5, 0)
    end
end

local function getBatch(eggName)
    local eggData = EggsModule.Eggs[eggName]
    if not eggData then return nil end

    local price = eggData.Price
    local currency = eggData.Currency
    local currencyAmount = PlayerData.Data[currency] or 0
    local petCount = #LocalPlayer.Pets:GetChildren()
    local maxStorage = PlayerData.Data.MaxStorage or 0
    local hasPass = table.find(PlayerData.Data.Passes, "x8EggsHatch") ~= nil

    if hasPass and price * 8 <= currencyAmount and petCount + 8 <= maxStorage then
        return "Q"
    elseif price * 3 <= currencyAmount and petCount + 3 <= maxStorage then
        return "R"
    elseif price <= currencyAmount and petCount + 1 <= maxStorage then
        return "E"
    end

    return nil
end

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

local function GetBestAvailableRebirthIndex()
    local level = PlayerData.Data.RebirthButtons or 0
    local maxUnlocked = 4 + level
    return math.min(maxUnlocked, #RebirthsModule.Rebirths)
end

local function IsProgressionTargetAvailable()
    local label = Options.ProgressionRebirthTarget.Value
    local key = RebirthTierKeys[label]
    if not key then return true end

    if key == "Inf" then
        return table.find(PlayerData.Data.Passes, "InfinityRebirth") ~= nil
    end

    local level = PlayerData.Data.RebirthButtons or 0
    return key <= 4 + level
end

do
    local ProgressionBox = Tabs.Misc:AddLeftGroupbox("Auto Progression", "trending-up")

    local function GetConfigList()
        local list = { "None" }
        local ok, result = pcall(function()
            return SaveManager:RefreshConfigList()
        end)

        if ok and result then
            for _, name in ipairs(result) do
                table.insert(list, name)
            end
        end

        return list
    end

    AddDropdown(ProgressionBox, "TutorialLoadConfig", "Load Config After", GetConfigList(), "None", false)

    ProgressionBox:AddButton({
        Text = "Refresh Config List",
        Func = function()
            local fresh = GetConfigList()
            Options.TutorialLoadConfig:SetValues(fresh)

            local current = Options.TutorialLoadConfig.Value
            if not table.find(fresh, current) then
                Options.TutorialLoadConfig:SetValue("None")
            end

            Library:Notify("Config list refreshed! (" .. (#fresh - 1) .. " found)")
        end,
    })

    local progressionRebirthDefault = RebirthTiers[#RebirthsModule.Rebirths] or RebirthTiers[#RebirthTiers]
    AddDropdown(ProgressionBox, "ProgressionRebirthTarget", "Rebirth Until Tier", RebirthTiers, progressionRebirthDefault, false)
    AddCheckbox(ProgressionBox, "ToggleProgressionRebirth", "Auto Progression Rebirth")

    ProgressionBox:AddButton({
        Text = "Start Auto Progression",
        Func = function()
            local fresh = GetConfigList()
            Options.TutorialLoadConfig:SetValues(fresh)

            local current = Options.TutorialLoadConfig.Value
            if not table.find(fresh, current) then
                Options.TutorialLoadConfig:SetValue("None")
            end

            local stage = PlayerData.Data and PlayerData.Data.TutorialStage or 0

            if stage >= 6 then
                Library:Notify("Tutorial already complete! (Stage " .. stage .. ")")

                local configName = Options.TutorialLoadConfig.Value
                if configName and configName ~= "None" then
                    local ok, err = SaveManager:Load(configName)
                    if ok then
                        Library:Notify("Config loaded: " .. configName)
                        task.wait(0.5)
                        if Toggles.ToggleAH.Value then
                            TeleportToEgg(Options.EggSelect.Value)
                        end
                    else
                        Library:Notify("Config load failed: " .. tostring(err))
                    end
                end

                return
            end

            Library:Notify("Auto Progression: Starting from stage " .. stage .. "...")

            task.spawn(function()
                -- Stage 1 to 2: need 50 clicks
                if (PlayerData.Data.TutorialStage or 0) <= 1 then
                    Library:Notify("Auto Progression: Stage 1 - clicking 50x...")
                    for _ = 1, 80 do
                        ClickRemote:FireServer()
                        task.wait(0.1)
                    end

                    local waited = 0
                    repeat
                        task.wait(0.2)
                        waited += 0.2
                    until (PlayerData.Data.TutorialStage or 0) >= 2 or waited >= 8
                end

                -- Stage 2 to 3: hatch Starter egg
                if (PlayerData.Data.TutorialStage or 0) <= 2 then
                    Library:Notify("Auto Progression: Stage 2 - hatching Starter egg...")
                    TeleportToEgg("Starter")
                    task.wait(0.5)
                    EggRemote:FireServer("Starter", "E")
                    task.wait(1)
                    PetActionRemote:FireServer("Equip Best")
                    task.wait(0.5)

                    local waited = 0
                    repeat
                        task.wait(0.2)
                        waited += 0.2
                    until (PlayerData.Data.TutorialStage or 0) >= 3 or waited >= 8
                end

                -- Stage 3 to 4: equip pet
                if (PlayerData.Data.TutorialStage or 0) <= 3 then
                    Library:Notify("Auto Progression: Stage 3 - equipping pet...")
                    PetActionRemote:FireServer("Equip Best")
                    task.wait(0.5)

                    local waited = 0
                    repeat
                        task.wait(0.2)
                        waited += 0.2
                    until (PlayerData.Data.TutorialStage or 0) >= 4 or waited >= 8
                end

                -- Stage 4 to 5: rebirth
                if (PlayerData.Data.TutorialStage or 0) <= 4 then
                    Library:Notify("Auto Progression: Stage 4 - clicking for rebirth...")
                    for _ = 1, 120 do
                        ClickRemote:FireServer()
                        task.wait(0.05)
                    end

                    RebirthRemote:FireServer(1)
                    task.wait(1)

                    local waited = 0
                    repeat
                        task.wait(0.2)
                        waited += 0.2
                    until (PlayerData.Data.TutorialStage or 0) >= 5 or waited >= 8
                end

                -- Stage 5 to 6: finish tutorial
                if (PlayerData.Data.TutorialStage or 0) <= 5 then
                    Library:Notify("Auto Progression: Stage 5 - finishing...")
                    AdditionalRemote:FireServer("TutorialEnd")
                    task.wait(1)
                end

                local final = PlayerData.Data.TutorialStage or 0
                if final >= 6 then
                    Library:Notify("Tutorial complete!")

                    local configName = Options.TutorialLoadConfig.Value
                    if configName and configName ~= "None" then
                        task.wait(0.5)

                        local ok, err = SaveManager:Load(configName)
                        if ok then
                            Library:Notify("Config loaded: " .. configName)
                            task.wait(0.5)
                            if Toggles.ToggleAH.Value then
                                TeleportToEgg(Options.EggSelect.Value)
                            end
                        else
                            Library:Notify("Config load failed: " .. tostring(err))
                            task.wait(0.3)
                            if Toggles.ToggleAH.Value then
                                TeleportToEgg(Options.EggSelect.Value)
                            end
                        end
                    else
                        task.wait(0.3)
                        if Toggles.ToggleAH.Value then
                            TeleportToEgg(Options.EggSelect.Value)
                        end
                    end
                else
                    Library:Notify("Still at stage " .. final .. " - try manually.")
                end
            end)
        end,
    })

    local CodesBox = Tabs.Misc:AddLeftGroupbox("Codes", "key")
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
        end,
    })

    local AutoAcceptTradeBox = Tabs.Misc:AddLeftGroupbox("Auto Accept Trade", "check-circle")
    AddCheckbox(AutoAcceptTradeBox, "ToggleAutoAcceptTrade", "Accept All Requests")
    AutoAcceptTradeBox:AddInput("AutoAcceptTradeUsers", {
        Text = "Accept Only From (user1,user2,...)",
        Placeholder = "Leave blank to accept from anyone",
    })

    local AutoConfirmTradeBox = Tabs.Misc:AddLeftGroupbox("Auto Confirm Trade", "check-square")
    AddCheckbox(AutoConfirmTradeBox, "ToggleAutoConfirmTrade", "Auto Confirm Trade")

    local AutoTradeBox = Tabs.Misc:AddLeftGroupbox("Auto Trade", "repeat")
    AutoTradeBox:AddInput("AutoTradeUsernames", {
        Text = "Usernames (user1,user2,...)",
        Placeholder = "player1,player2",
    })
    AddCheckbox(AutoTradeBox, "ToggleAutoTrade", "Auto Send Trade Requests")

    local MiscBox = Tabs.Misc:AddRightGroupbox("Misc", "shield")
    AddCheckbox(MiscBox, "ToggleDisableAutoRejoin", "Disable Auto Rejoin")

    local PerformanceTabs = Tabs.Performance:AddLeftTabbox("Performance")
    local PerformanceBox = PerformanceTabs:AddTab("Boost", "zap")
    local FpsCapBox = PerformanceTabs:AddTab("FPS Cap", "monitor")
    local Render3DBox = PerformanceTabs:AddTab("3D", "eye-off")

    AddCheckbox(PerformanceBox, "TogglePerformance", "Enable Performance")

    FpsCapBox:AddInput("FpsCapValue", { Text = "FPS Limit", Placeholder = "e.g. 60" })
    AddCheckbox(FpsCapBox, "ToggleFpsCap", "Enable FPS Cap")

    AddCheckbox(Render3DBox, "ToggleDisable3D", "Disable 3D Rendering")

    local AutoSettingsBox = Tabs.Misc:AddRightGroupbox("Auto Settings", "sliders")
    AddDropdown(AutoSettingsBox, "SettingsWantOn", "Force ON", GameSettingsList, {}, true)
    AddDropdown(AutoSettingsBox, "SettingsWantOff", "Force OFF", GameSettingsList, {}, true)
    AddCheckbox(AutoSettingsBox, "ToggleAutoSettings", "Auto Apply Settings")

    local WebhookTabs = Tabs.Webhook:AddLeftTabbox("Webhook")
    local WebhookBox = WebhookTabs:AddTab("Alerts", "bell")
    local SummaryWebhookBox = WebhookTabs:AddTab("Summary", "bar-chart-3")
    local PingTypes = { "None", "User", "Role" }
    AddDivider(WebhookBox, "Discord")
    WebhookBox:AddInput("WebhookURL", { Text = "Webhook URL", Placeholder = "discord.com/api/webhooks/..." })
    WebhookBox:AddInput("WebhookPingID", { Text = "Ping ID", Placeholder = "User or Role ID" })
    AddDropdown(WebhookBox, "WebhookPingType", "Ping Type", PingTypes, "None", false)
    WebhookBox:AddButton({
        Text = "Test Alert Webhook",
        Func = function()
            if SendAlertWebhookTest then SendAlertWebhookTest() end
        end,
    })
    AddDivider(WebhookBox, "Hatches")
    AddDropdown(WebhookBox, "WebhookNotifyRarities", "Notify Rarities", RarityList, {}, true)
    AddDropdown(WebhookBox, "WebhookPingRarities", "Ping Rarities", RarityList, {}, true)
    AddCheckbox(WebhookBox, "ToggleWebhook", "Enable Webhook")

    AddDivider(SummaryWebhookBox, "Discord")
    SummaryWebhookBox:AddInput("WebhookSummaryURL", { Text = "Summary Webhook URL", Placeholder = "discord.com/api/webhooks/..." })
    SummaryWebhookBox:AddButton({
        Text = "Test Summary Webhook",
        Func = function()
            if SendSummaryWebhookTest then SendSummaryWebhookTest() end
        end,
    })
    AddDivider(SummaryWebhookBox, "Metrics")
    AddDropdown(SummaryWebhookBox, "SummaryMetrics", "Summary Metrics", SummaryMetricList, SummaryMetricDefaultSelected, true)
    task.defer(function()
        Options.SummaryMetrics:SetValue(SummaryMetricDefaultSelected)
    end)
    AddDivider(SummaryWebhookBox, "Timer")
    AddSlider(SummaryWebhookBox, "WebhookSummaryMinutes", "Every", 1, 60, 10, "m")
    AddCheckbox(SummaryWebhookBox, "ToggleWebhookSummary", "Summary Webhook")
end

local function UpdateIndexStatus(target)
    if not target then
        IndexStatusImage:SetImage("rbxassetid://0")
        IndexLabelPet:SetText("Pet: -")
        IndexLabelEgg:SetText("Egg: -")
        IndexLabelRarity:SetText("Rarity: -")
        IndexLabelStage:SetText("Stage: Idle")
        IndexLabelProgress:SetText("Progress: -")
        return
    end

    local petData = PetsModule.Pets[target.pet]
    if petData and petData.IDs then
        local assetId = petData.IDs[target.variant] or petData.IDs.Normal
        if assetId then
            IndexStatusImage:SetImage(assetId)
        end
    end

    local rarity = petData and petData.Rarity or "?"
    IndexLabelPet:SetText("Pet: " .. target.pet)
    IndexLabelEgg:SetText("Egg: " .. target.egg)
    IndexLabelRarity:SetText("Rarity: " .. rarity)

    local stageMap = { Normal = "Hatching Normal", Golden = "Crafting Golden", Diamond = "Crafting Diamond" }
    IndexLabelStage:SetText("Stage: " .. (stageMap[target.variant] or target.variant))

    local indexed = #PlayerData.Data.Index
    local total = 0
    for _ in pairs(PetsModule.Pets) do
        total = total + 3
    end
    IndexLabelProgress:SetText("Progress: " .. indexed .. "/" .. total)
end

local hookRefFn = nil
local hookRefOriginal = nil

local function InstallNoHatchHook()
    if hookRefFn then return end

    task.spawn(function()
        local attempts = 0
        while not hookRefFn and attempts < 200 do
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

                            hookRefFn = conn.Function
                            hookRefOriginal = original
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

local teleportHookOriginal = nil
local teleportNamecallOriginal = nil

local function ShouldBlockTeleport(self, method)
    return Toggles.ToggleDisableAutoRejoin.Value
        and self == TeleportService
        and (
            method == "Teleport"
            or method == "TeleportAsync"
            or method == "TeleportToPlaceInstance"
        )
end

local function InstallTeleportBlock()
    if not teleportHookOriginal then
        teleportHookOriginal = hookfunction(TeleportService.Teleport, newcclosure(function(self, placeId, ...)
            if ShouldBlockTeleport(self, "Teleport") then
                return
            end
            return teleportHookOriginal(self, placeId, ...)
        end))
    end

    if hookmetamethod and not teleportNamecallOriginal then
        teleportNamecallOriginal = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local method = getnamecallmethod and getnamecallmethod() or nil
            if ShouldBlockTeleport(self, method) then
                return
            end
            return teleportNamecallOriginal(self, ...)
        end))
    end
end

local function RemoveTeleportBlock()
    if teleportHookOriginal then
        hookfunction(TeleportService.Teleport, teleportHookOriginal)
        teleportHookOriginal = nil
    end
    if hookmetamethod and teleportNamecallOriginal then
        hookmetamethod(game, "__namecall", teleportNamecallOriginal)
        teleportNamecallOriginal = nil
    end
end

Toggles.ToggleDisableAutoRejoin:OnChanged(function(state)
    if state then
        InstallTeleportBlock()
    else
        RemoveTeleportBlock()
    end
end)

local Tasks = {}

local function StopTask(name)
    if Tasks[name] then
        task.cancel(Tasks[name])
        Tasks[name] = nil
    end
end

local function StartAC()
    StopTask("AC")
    Tasks.AC = task.spawn(function()
        while Toggles.ToggleAC.Value do
            ClickRemote:FireServer()
            task.wait(0.1)
        end
    end)
end

Toggles.ToggleAC:OnChanged(function(state)
    if state then
        StartAC()
    else
        StopTask("AC")
    end
end)

local function StartAH()
    StopTask("AH")

    local eggName = Options.EggSelect.Value
    SwitchRemote:FireServer("AutoHatching", true)
    TeleportToEgg(eggName)

    Tasks.AH = task.spawn(function()
        while Toggles.ToggleAH.Value do
            local batch = getBatch(eggName)
            if batch then
                EggRemote:FireServer(eggName, batch)
            else
                task.wait(0.1)
            end
            task.wait(0.1)
        end
    end)
end

Toggles.ToggleAH:OnChanged(function(state)
    if state then
        StartAH()
    else
        StopTask("AH")
        SwitchRemote:FireServer("AutoHatching", false)
    end
end)

Options.EggSelect:OnChanged(function()
    if Toggles.ToggleAH.Value then
        StartAH()
    end
end)

local function canAffordRebirth(label)
    local key = RebirthTierKeys[label]
    if not key then return false end

    if key == "Inf" then
        return true
    end

    local cost = RebirthsModule.Rebirths[key] * 100 * (1 + PlayerData.Data.Rebirths)
    return PlayerData.Data.Clicks >= cost
end

local function GetInfRebirthDelay()
    local raw = Options.InfRebirthDelay and Options.InfRebirthDelay.Value
    local delay = tonumber(raw) or 0.5
    return math.max(0.01, delay)
end

local function StartAutoRebirth()
    StopTask("AutoRebirth")
    Tasks.AutoRebirth = task.spawn(function()
        while Toggles.ToggleAutoRebirth.Value do
            local label = Options.RebirthTier.Value
            local key = RebirthTierKeys[label]

            if key and canAffordRebirth(label) then
                RebirthRemote:FireServer(key)
                task.wait(key == "Inf" and GetInfRebirthDelay() or 0.5)
            else
                task.wait(0.5)
            end
        end
    end)
end

Toggles.ToggleAutoRebirth:OnChanged(function(state)
    if state then
        StartAutoRebirth()
    else
        StopTask("AutoRebirth")
    end
end)

local function StartAutoSpin()
    StopTask("AutoSpin")
    Tasks.AutoSpin = task.spawn(function()
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
    if state then
        if Toggles.ToggleConvertSpins.Value then
            Toggles.ToggleConvertSpins:SetValue(false)
        end
        StartAutoSpin()
    else
        StopTask("AutoSpin")
    end
end)

local function StartConvertSpins()
    StopTask("ConvertSpins")
    Tasks.ConvertSpins = task.spawn(function()
        while Toggles.ToggleConvertSpins.Value do
            if (PlayerData.Data.Spins or 0) >= 5 then
                EvilSpinRemote:FireServer(false, "Convert")
                task.wait(1.5)
            else
                task.wait(2)
            end
        end
    end)
end

Toggles.ToggleConvertSpins:OnChanged(function(state)
    if state then
        if Toggles.ToggleAutoSpin.Value then
            Toggles.ToggleAutoSpin:SetValue(false)
        end
        StartConvertSpins()
    else
        StopTask("ConvertSpins")
    end
end)

local function StartAutoEvilSpin()
    StopTask("AutoEvilSpin")
    Tasks.AutoEvilSpin = task.spawn(function()
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
    if state then
        StartAutoEvilSpin()
    else
        StopTask("AutoEvilSpin")
    end
end)

local function StartAutoUpgrade()
    StopTask("AutoUpgrade")
    Tasks.AutoUpgrade = task.spawn(function()
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
    if state then
        StartAutoUpgrade()
    else
        StopTask("AutoUpgrade")
    end
end)

local function StartAutoEquipBest()
    StopTask("AutoEquipBest")
    Tasks.AutoEquipBest = task.spawn(function()
        while Toggles.ToggleAutoEquipBest.Value do
            PetActionRemote:FireServer("Equip Best")
            task.wait(10)
        end
    end)
end

Toggles.ToggleAutoEquipBest:OnChanged(function(state)
    if state then
        StartAutoEquipBest()
    else
        StopTask("AutoEquipBest")
    end
end)

local function StartAutoBuy()
    StopTask("AutoBuy")
    Tasks.AutoBuy = task.spawn(function()
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
    if state then
        StartAutoBuy()
    else
        StopTask("AutoBuy")
    end
end)

local function StartAutoUseItems()
    StopTask("AutoUseItems")
    Tasks.AutoUseItems = task.spawn(function()
        while Toggles.ToggleAutoUseItems.Value do
            local selected = Options.ItemUseSelect.Value
            for itemName in pairs(selected) do
                local count = PlayerData.Data.Items and PlayerData.Data.Items[itemName] or 0
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
    if state then
        StartAutoUseItems()
    else
        StopTask("AutoUseItems")
    end
end)

local function StartAutoPotionCraft()
    StopTask("AutoPotionCraft")
    Tasks.AutoPotionCraft = task.spawn(function()
        while Toggles.ToggleAutoPotionCraft.Value do
            local selected = Options.PotionCraftSelect.Value

            for craftName in pairs(selected) do
                if not Toggles.ToggleAutoPotionCraft.Value then break end
                PotionCraftingRemote:FireServer(craftName)
                task.wait(1)
            end

            task.wait(2)
        end
    end)
end

Toggles.ToggleAutoPotionCraft:OnChanged(function(state)
    if state then
        if not next(Options.PotionCraftSelect.Value) then
            Library:Notify("Auto Potion Crafting: Select at least one potion first!")
            Toggles.ToggleAutoPotionCraft:SetValue(false)
            return
        end
        StartAutoPotionCraft()
    else
        StopTask("AutoPotionCraft")
    end
end)

local function StartClaimGifts()
    StopTask("ClaimGifts")
    Tasks.ClaimGifts = task.spawn(function()
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
    if state then
        StartClaimGifts()
    else
        StopTask("ClaimGifts")
    end
end)

local function StartClaimDaily()
    StopTask("ClaimDaily")
    Tasks.ClaimDaily = task.spawn(function()
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
    if state then
        StartClaimDaily()
    else
        StopTask("ClaimDaily")
    end
end)

local function StartClaimAchievements()
    StopTask("ClaimAchievements")
    Tasks.ClaimAchievements = task.spawn(function()
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
    if state then
        StartClaimAchievements()
    else
        StopTask("ClaimAchievements")
    end
end)

local function StartClaimChests()
    StopTask("ClaimChests")
    Tasks.ClaimChests = task.spawn(function()
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
    if state then
        StartClaimChests()
    else
        StopTask("ClaimChests")
    end
end)

local function StartAutoGolden()
    StopTask("AutoGolden")
    Tasks.AutoGolden = task.spawn(function()
        while Toggles.ToggleAutoGolden.Value do
            local selected = Options.GoldenPetSelect.Value
            local needed = CraftSuccessMap[Options.GoldenSuccessRate.Value] or 5

            for petName in pairs(selected) do
                local ids = {}
                for _, pet in pairs(LocalPlayer.Pets:GetChildren()) do
                    if pet:FindFirstChild("PetType")
                        and pet.PetType.Value == "Normal"
                        and pet.Name == petName
                        and pet:FindFirstChild("ID")
                    then
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
    if state then
        StartAutoGolden()
    else
        StopTask("AutoGolden")
    end
end)

local function StartAutoDiamond()
    StopTask("AutoDiamond")
    Tasks.AutoDiamond = task.spawn(function()
        while Toggles.ToggleAutoDiamond.Value do
            local selected = Options.DiamondPetSelect.Value
            local needed = CraftSuccessMap[Options.DiamondSuccessRate.Value] or 5

            for petName in pairs(selected) do
                local ids = {}
                for _, pet in pairs(LocalPlayer.Pets:GetChildren()) do
                    if pet:FindFirstChild("PetType")
                        and pet.PetType.Value == "Golden"
                        and pet.Name == petName
                        and pet:FindFirstChild("ID")
                    then
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
    if state then
        StartAutoDiamond()
    else
        StopTask("AutoDiamond")
    end
end)

local function StartClaimSeason()
    StopTask("ClaimSeason")
    Tasks.ClaimSeason = task.spawn(function()
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
    if state then
        StartClaimSeason()
    else
        StopTask("ClaimSeason")
    end
end)

local function StartClaimQuests()
    StopTask("ClaimQuests")
    Tasks.ClaimQuests = task.spawn(function()
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
    if state then
        StartClaimQuests()
    else
        StopTask("ClaimQuests")
    end
end)

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

local function StartAutoBuyAuras()
    StopTask("AutoBuyAuras")
    Tasks.AutoBuyAuras = task.spawn(function()
        while Toggles.ToggleAutoBuyAuras.Value do
            local selected = Options.AuraSelect.Value

            for auraName in pairs(selected) do
                local auraData = AurasModule.Auras[auraName]
                if auraData and not table.find(PlayerData.Data.Auras, auraName) then
                    local price = auraData.Price or 0
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
    if state then
        StartAutoBuyAuras()
    else
        StopTask("AutoBuyAuras")
    end
end)

local function StartAutoEquipBestAura()
    StopTask("AutoEquipBestAura")
    Tasks.AutoEquipBestAura = task.spawn(function()
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
    if state then
        StartAutoEquipBestAura()
    else
        StopTask("AutoEquipBestAura")
    end
end)

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

local function StartAutoBuyTapSkins()
    StopTask("AutoBuyTapSkins")
    Tasks.AutoBuyTapSkins = task.spawn(function()
        while Toggles.ToggleAutoBuyTapSkins.Value do
            local selected = Options.TapSkinSelect.Value

            for skinName in pairs(selected) do
                local skinData = TapSkinsModule.TapSkins[skinName]
                if skinData and not table.find(PlayerData.Data.TapSkins, skinName) then
                    local price = skinData.Price or 0
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
    if state then
        StartAutoBuyTapSkins()
    else
        StopTask("AutoBuyTapSkins")
    end
end)

local function StartAutoEquipBestTapSkin()
    StopTask("AutoEquipBestTapSkin")
    Tasks.AutoEquipBestTapSkin = task.spawn(function()
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
    if state then
        StartAutoEquipBestTapSkin()
    else
        StopTask("AutoEquipBestTapSkin")
    end
end)

local function StartAutoClaimIndexReward()
    StopTask("AutoClaimIndexReward")
    Tasks.AutoClaimIndexReward = task.spawn(function()
        while Toggles.ToggleAutoClaimIndexReward.Value do
            local questText = LocalPlayer.PlayerGui.MainUI.Frames.Index.Quest.Text
            local current, threshold = questText:match("(%d+)/(%d+)")
            current = tonumber(current)
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
    if state then
        StartAutoClaimIndexReward()
    else
        StopTask("AutoClaimIndexReward")
    end
end)

local function ApplySettingsPass()
    local wantOn = Options.SettingsWantOn.Value
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
    StopTask("AutoSettings")
    Tasks.AutoSettings = task.spawn(function()
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
        task.delay(0.5, function()
            if not Toggles.ToggleAutoSettings.Value then return end

            local wantOn = Options.SettingsWantOn.Value
            local wantOff = Options.SettingsWantOff.Value
            if not next(wantOn) and not next(wantOff) then
                Library:Notify("Auto Settings: Select at least one setting first!")
                Toggles.ToggleAutoSettings:SetValue(false)
                return
            end

            StartAutoSettings()
        end)
    else
        StopTask("AutoSettings")
    end
end)

local performanceApp = nil

local function StartPerformance()
    if performanceApp then return end

    local NEUTRAL = Color3.fromRGB(115, 115, 115)
    local Workspace = game:GetService("Workspace")
    local Lighting = game:GetService("Lighting")
    local cacheFile = "PhosphyHub/ClickBreakers/performance_cache.jsonl"

    local function pcallDo(fn)
        local ok = pcall(fn)
        return ok
    end

    local function canUseFileCache()
        return writefile and appendfile and readfile
    end

    local function ensureCacheFolder()
        if not makefolder then return end
        pcall(function()
            if not isfolder or not isfolder("PhosphyHub") then
                makefolder("PhosphyHub")
            end
        end)
        pcall(function()
            if not isfolder or not isfolder("PhosphyHub/ClickBreakers") then
                makefolder("PhosphyHub/ClickBreakers")
            end
        end)
    end

    local function instancePath(inst)
        local path = {}
        local cur = inst
        while cur and cur ~= game do
            table.insert(path, 1, cur.Name)
            cur = cur.Parent
        end
        return path
    end

    local function resolvePath(path)
        local rootName = path and path[1]
        if not rootName then return nil end

        local ok, cur = pcall(function()
            return game:GetService(rootName)
        end)
        if not ok or not cur then
            cur = game:FindFirstChild(rootName)
        end
        if not cur then return nil end

        for i = 2, #path do
            cur = cur:FindFirstChild(path[i])
            if not cur then return nil end
        end

        return cur
    end

    local function encodeValue(value)
        local valueType = typeof(value)
        if valueType == "Color3" then
            return { Type = "Color3", R = value.R, G = value.G, B = value.B }
        elseif valueType == "EnumItem" then
            local enumType = tostring(value.EnumType):match("%.([^%.]+)$")
            return { Type = "EnumItem", EnumType = enumType, Name = value.Name }
        end
        return { Type = "Raw", Value = value }
    end

    local function decodeValue(value)
        if not value then return nil end
        if value.Type == "Color3" then
            return Color3.new(value.R, value.G, value.B)
        elseif value.Type == "EnumItem" and value.EnumType and Enum[value.EnumType] then
            return Enum[value.EnumType][value.Name]
        end
        return value.Value
    end

    local function set(inst, prop, value)
        return pcallDo(function()
            inst[prop] = value
        end)
    end

    local function clear(inst, prop)
        if not set(inst, prop, "") then
            set(inst, prop, "rbxassetid://0")
        end
    end

    local function destroy(inst)
        if inst and inst.Parent then
            pcallDo(function()
                inst:Destroy()
            end)
        end
    end

    local old = getgenv and getgenv().PhosphySimpleStripper
    if old and old.Unload then
        pcallDo(old.Unload)
    end

    ensureCacheFolder()
    if canUseFileCache() then
        pcall(function()
            writefile(cacheFile, "")
        end)
    end

    local app = {
        Running = true,
        Connections = {},
        PlayerConnections = {},
        Seen = {},
        MemoryCache = {},
    }
    performanceApp = app

    if getgenv then
        getgenv().PhosphySimpleStripper = app
    end

    local function cacheProps(inst, props)
        if not app.Running then return end

        local path = instancePath(inst)
        local key = table.concat(path, "\0")
        if app.Seen[key] then return end
        app.Seen[key] = true

        local values = {}
        for _, prop in ipairs(props) do
            local ok, value = pcall(function()
                return inst[prop]
            end)
            if ok then
                values[prop] = encodeValue(value)
            end
        end

        local record = { Path = path, Props = values }
        if canUseFileCache() then
            pcall(function()
                appendfile(cacheFile, HttpService:JSONEncode(record) .. "\n")
            end)
        else
            table.insert(app.MemoryCache, record)
        end
    end

    local function restoreRecord(record)
        local inst = resolvePath(record.Path)
        if not inst then return end

        for prop, value in pairs(record.Props or {}) do
            set(inst, prop, decodeValue(value))
        end
    end

    local function restoreCachedProps()
        if canUseFileCache() then
            local ok, contents = pcall(function()
                return readfile(cacheFile)
            end)
            if ok and contents then
                for line in contents:gmatch("[^\r\n]+") do
                    local okDecode, record = pcall(HttpService.JSONDecode, HttpService, line)
                    if okDecode and record then
                        restoreRecord(record)
                    end
                end
            end
            pcall(function()
                writefile(cacheFile, "")
            end)
        else
            for _, record in ipairs(app.MemoryCache) do
                restoreRecord(record)
            end
            table.clear(app.MemoryCache)
        end
    end

    local function isLightingEffect(inst)
        return inst:IsA("PostEffect")
            or inst:IsA("Atmosphere")
            or inst:IsA("Sky")
            or inst:IsA("BloomEffect")
            or inst:IsA("BlurEffect")
            or inst:IsA("ColorCorrectionEffect")
            or inst:IsA("DepthOfFieldEffect")
            or inst:IsA("SunRaysEffect")
    end

    local function applyLightingBoost()
        cacheProps(Lighting, {
            "GlobalShadows",
            "Brightness",
            "ClockTime",
            "FogEnd",
            "FogStart",
            "FogColor",
            "Ambient",
            "OutdoorAmbient",
            "ShadowSoftness",
            "EnvironmentDiffuseScale",
            "EnvironmentSpecularScale",
        })

        for _, child in ipairs(Lighting:GetChildren()) do
            if isLightingEffect(child) then
                cacheProps(child, { "Enabled" })
                set(child, "Enabled", false)
            end
        end

        local ok, quality = pcall(function()
            return settings().Rendering.QualityLevel
        end)
        if ok then
            app.QualityLevel = quality
        end

        set(Lighting, "GlobalShadows", false)
        set(Lighting, "Brightness", 2)
        set(Lighting, "FogEnd", 100000)
        set(Lighting, "FogStart", 99999)
        set(Lighting, "Ambient", Color3.fromRGB(178, 178, 178))
        set(Lighting, "OutdoorAmbient", Color3.fromRGB(178, 178, 178))
        set(Lighting, "ShadowSoftness", 0)
        set(Lighting, "EnvironmentDiffuseScale", 0)
        set(Lighting, "EnvironmentSpecularScale", 0)

        pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end)
    end

    local function connect(signal, fn, bucket)
        local ok, conn = pcall(function()
            return signal:Connect(fn)
        end)
        if ok and conn then
            table.insert(bucket or app.Connections, conn)
        end
    end

    local function disconnectAll(list)
        for _, conn in ipairs(list) do
            pcallDo(function()
                conn:Disconnect()
            end)
        end
        table.clear(list)
    end

    local function strip(inst)
        if not inst then
            return
        end

        if inst.Name == "Tag" and inst.Parent and inst.Parent.Name == "HumanoidRootPart" then
            destroy(inst)
        elseif inst:IsA("BasePart") then
            cacheProps(inst, { "Color", "Material", "MaterialVariant", "Reflectance", "CastShadow" })
            set(inst, "Color", NEUTRAL)
            set(inst, "Material", Enum.Material.SmoothPlastic)
            set(inst, "MaterialVariant", "")
            set(inst, "Reflectance", 0)
            set(inst, "CastShadow", false)
            if inst:IsA("MeshPart") then
                clear(inst, "MeshId")
                clear(inst, "TextureID")
                clear(inst, "TextureId")
            end
        elseif inst:IsA("SpecialMesh") then
            clear(inst, "MeshId")
            clear(inst, "TextureId")
        elseif inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("SurfaceAppearance") then
            destroy(inst)
        elseif inst:IsA("Shirt") or inst:IsA("Pants") or inst:IsA("ShirtGraphic") then
            destroy(inst)
        elseif inst:IsA("BodyColors") then
            cacheProps(inst, {
                "HeadColor3",
                "LeftArmColor3",
                "LeftLegColor3",
                "RightArmColor3",
                "RightLegColor3",
                "TorsoColor3",
            })
            set(inst, "HeadColor3", NEUTRAL)
            set(inst, "LeftArmColor3", NEUTRAL)
            set(inst, "LeftLegColor3", NEUTRAL)
            set(inst, "RightArmColor3", NEUTRAL)
            set(inst, "RightLegColor3", NEUTRAL)
            set(inst, "TorsoColor3", NEUTRAL)
        elseif inst:IsA("ParticleEmitter")
            or inst:IsA("Trail")
            or inst:IsA("Beam")
            or inst:IsA("Smoke")
            or inst:IsA("Fire")
            or inst:IsA("Sparkles")
        then
            destroy(inst)
        end
    end

    local function keepIsland(inst)
        local cur = inst
        while cur and cur ~= Workspace do
            local n = string.lower(cur.Name)
            if n:find("bridge", 1, true)
                or n:find("islands_circle", 1, true)
                or n:find("teleport", 1, true)
                or n:find("entrance", 1, true)
                or n:find("portal", 1, true)
                or n:find("prompt", 1, true)
                or n:find("button", 1, true)
                or n:find("shop", 1, true)
                or n:find("egg", 1, true)
                or n:find("chest", 1, true)
            then
                return true
            end
            cur = cur.Parent
        end
        return inst:FindFirstChildWhichIsA("ProximityPrompt", true)
            or inst:FindFirstChildWhichIsA("ClickDetector", true)
            or inst:FindFirstChildWhichIsA("TouchTransmitter", true)
    end

    local function cleanIslands()
        local gameFolder = Workspace:FindFirstChild("Game")
        local islands = gameFolder and gameFolder:FindFirstChild("Islands")
        if not islands then return end
        for _, island in ipairs(islands:GetChildren()) do
            for _, inst in ipairs(island:GetDescendants()) do
                if inst:IsA("MeshPart") and not keepIsland(inst) then
                    destroy(inst)
                end
            end
        end
    end

    local function stripTree(root)
        if not root then
            return
        end
        strip(root)
        for _, inst in ipairs(root:GetDescendants()) do
            strip(inst)
        end
    end

    local function removeOtherPlayer(player)
        if player and player ~= LocalPlayer then
            destroy(player.Character)
            local model = Workspace:FindFirstChild(player.Name)
            if model then
                destroy(model)
            end
        end
    end

    local function watchPlayer(player)
        if not player or player == LocalPlayer then
            return
        end
        if app.PlayerConnections[player] then
            disconnectAll(app.PlayerConnections[player])
        end
        app.PlayerConnections[player] = {}
        removeOtherPlayer(player)
        connect(player.CharacterAdded, function(char)
            task.defer(function()
                if app.Running then
                    destroy(char)
                end
            end)
        end, app.PlayerConnections[player])
    end

    function app.Unload()
        app.Running = false
        disconnectAll(app.Connections)
        for player, list in pairs(app.PlayerConnections) do
            disconnectAll(list)
            app.PlayerConnections[player] = nil
        end
        restoreCachedProps()
        if app.QualityLevel then
            pcall(function()
                settings().Rendering.QualityLevel = app.QualityLevel
            end)
        end
        if getgenv and getgenv().PhosphySimpleStripper == app then
            getgenv().PhosphySimpleStripper = nil
        end
        performanceApp = nil
    end

    applyLightingBoost()
    stripTree(game)
    cleanIslands()

    connect(game.DescendantAdded, function(inst)
        strip(inst)
        local gameFolder = Workspace:FindFirstChild("Game")
        local islands = gameFolder and gameFolder:FindFirstChild("Islands")
        if islands and inst:IsDescendantOf(islands) and inst:IsA("MeshPart") and not keepIsland(inst) then
            destroy(inst)
        end
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        watchPlayer(player)
    end

    connect(Players.PlayerAdded, watchPlayer)
    connect(Players.PlayerRemoving, function(player)
        removeOtherPlayer(player)
        if app.PlayerConnections[player] then
            disconnectAll(app.PlayerConnections[player])
            app.PlayerConnections[player] = nil
        end
    end)

    print("[PhosphySimpleStripper] active")
end

local function StopPerformance()
    if performanceApp and performanceApp.Unload then
        performanceApp.Unload()
        performanceApp = nil
    end
end

Toggles.TogglePerformance:OnChanged(function(state)
    if state then
        StartPerformance()
    else
        StopPerformance()
    end
end)

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
    if state then
        ApplyFpsCap()
    else
        RemoveFpsCap()
    end
end)

Options.FpsCapValue:OnChanged(function()
    if Toggles.ToggleFpsCap.Value then
        ApplyFpsCap()
    end
end)

local disable3DRestore = nil

local function DisableRendering()
    if disable3DRestore then return end

    local Lighting = game:GetService("Lighting")
    local cam = workspace.CurrentCamera
    if not cam then
        RunService:Set3dRenderingEnabled(false)
        disable3DRestore = function()
            RunService:Set3dRenderingEnabled(true)
            disable3DRestore = nil
        end
        return
    end

    local savedFogEnd = Lighting.FogEnd
    local savedFogStart = Lighting.FogStart
    local savedFogColor = Lighting.FogColor
    local savedBrightness = Lighting.Brightness
    local savedCamType = cam.CameraType
    local savedCamCFrame = cam.CFrame

    Lighting.FogEnd = 0
    Lighting.FogStart = 0
    Lighting.FogColor = Color3.fromRGB(0, 0, 0)
    Lighting.Brightness = 0
    cam.CameraType = Enum.CameraType.Scriptable
    cam.CFrame = CFrame.new(0, 1e8, 0)
    RunService:Set3dRenderingEnabled(false)

    disable3DRestore = function()
        RunService:Set3dRenderingEnabled(true)
        Lighting.FogEnd = savedFogEnd
        Lighting.FogStart = savedFogStart
        Lighting.FogColor = savedFogColor
        Lighting.Brightness = savedBrightness
        cam.CameraType = savedCamType
        cam.CFrame = savedCamCFrame
        disable3DRestore = nil
    end
end

local function EnableRendering()
    if disable3DRestore then
        disable3DRestore()
    end
end

Toggles.ToggleDisable3D:OnChanged(function(state)
    if state then
        DisableRendering()
    else
        EnableRendering()
    end
end)

local autoAcceptTradeConn = nil

local function InstallAutoAcceptTrade()
    if autoAcceptTradeConn then
        autoAcceptTradeConn:Disconnect()
        autoAcceptTradeConn = nil
    end

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
    if state then
        InstallAutoAcceptTrade()
    else
        if autoAcceptTradeConn then
            autoAcceptTradeConn:Disconnect()
            autoAcceptTradeConn = nil
        end
    end
end)

local autoConfirmTradeConn = nil
local currentTradePartner = nil

local function InstallAutoConfirmTrade()
    if autoConfirmTradeConn then
        autoConfirmTradeConn:Disconnect()
        autoConfirmTradeConn = nil
    end

    local confirmDebounce = nil
    autoConfirmTradeConn = TradeRemote.OnClientEvent:Connect(function(eventType, partnerName)
        if not Toggles.ToggleAutoConfirmTrade.Value then return end

        if eventType == "CreateTrade" then
            currentTradePartner = partnerName
        elseif eventType == "ClearTrade" or eventType == "TradeEnd" then
            currentTradePartner = nil
            if confirmDebounce then
                task.cancel(confirmDebounce)
                confirmDebounce = nil
            end
            return
        end

        if eventType ~= "CreateTrade" and eventType ~= "Cancel" then return end
        if not currentTradePartner then return end

        if confirmDebounce then
            task.cancel(confirmDebounce)
            confirmDebounce = nil
        end

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
    if state then
        InstallAutoConfirmTrade()
    else
        if autoConfirmTradeConn then
            autoConfirmTradeConn:Disconnect()
            autoConfirmTradeConn = nil
        end
        currentTradePartner = nil
    end
end)

local function StartAutoTrade()
    StopTask("AutoTrade")
    Tasks.AutoTrade = task.spawn(function()
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
                    local inTrade = targetPD and targetPD:FindFirstChild("InTrade") and targetPD.InTrade.Value
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
        StopTask("AutoTrade")
    end
end)

local function RunDeletePass(craftProtectedPet)
    local deleteRarities = Options.IndexDeleteRarities.Value
    local ignorePets = Options.IndexIgnorePets.Value
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

local function GetIndexed()
    local indexed = {}
    for _, entry in ipairs(PlayerData.Data.Index) do
        indexed[entry] = true
    end
    return indexed
end

local function getNextIndexTarget()
    local targetRarities = Options.IndexRaritySelect.Value
    local ignoreEggs = Options.IndexIgnoreEggs.Value
    local craftVariants = Options.IndexCraftVariants.Value
    local indexed = GetIndexed()

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
            if craftVariants.Golden and not indexed[petName .. "_Golden"] then
                return { egg = eggName, pet = petName, variant = "Golden" }
            end
            if craftVariants.Diamond and not indexed[petName .. "_Diamond"] then
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
    StopTask("AutoIndex")

    Tasks.AutoIndex = task.spawn(function()
        local lastTargetKey = nil
        local deleteTimer = 0
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
                Library:Notify("Auto Index: " .. target.pet .. " [" .. target.variant .. "] - " .. target.egg)
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
                    if batch then
                        EggRemote:FireServer(target.egg, batch)
                        task.wait(0.3)
                    else
                        task.wait(1)
                    end
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
                        if batch then
                            EggRemote:FireServer(target.egg, batch)
                            task.wait(0.3)
                        else
                            task.wait(1)
                        end
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
        StopTask("AutoIndex")
        UpdateIndexStatus(nil)
        SwitchRemote:FireServer("AutoHatching", false)
    end
end)

local function StartProgressionRebirth()
    StopTask("ProgressionRebirth")
    Tasks.ProgressionRebirth = task.spawn(function()
        local lastNotifiedTier = nil
        local rebirthTimer = 0
        local upgradeTimer = 0

        while Toggles.ToggleProgressionRebirth.Value do
            if IsProgressionTargetAvailable() then
                Library:Notify("Auto Progression: Target rebirth tier is now unlocked! Stopping.")
                Toggles.ToggleProgressionRebirth:SetValue(false)
                break
            end

            ClickRemote:FireServer()

            rebirthTimer = rebirthTimer + 0.1
            if rebirthTimer >= 0.5 then
                rebirthTimer = 0

                local bestIndex = GetBestAvailableRebirthIndex()
                if bestIndex >= 1 then
                    local cost = RebirthsModule.Rebirths[bestIndex] * 100 * (1 + PlayerData.Data.Rebirths)
                    if PlayerData.Data.Clicks >= cost then
                        if lastNotifiedTier ~= bestIndex then
                            lastNotifiedTier = bestIndex
                            Library:Notify(
                                "Auto Progression: Rebirthing at tier "
                                    .. bestIndex
                                    .. " ("
                                    .. fmtNum(RebirthsModule.Rebirths[bestIndex])
                                    .. ")"
                            )
                        end

                        RebirthRemote:FireServer(bestIndex)
                    end
                end
            end

            upgradeTimer = upgradeTimer + 0.1
            if upgradeTimer >= 2 then
                upgradeTimer = 0

                local upgradeData = UpgradesModule.Upgrades.RebirthButtons
                if upgradeData then
                    local current = PlayerData.Data.RebirthButtons or 0
                    local price = upgradeData.Prices and upgradeData.Prices[current]
                    if current < upgradeData.Max and price and PlayerData.Data.Gems >= price then
                        UpgradesRemote:FireServer("RebirthButtons")
                        task.wait(0.3)
                    end
                end
            end

            task.wait(0.1)
        end
    end)
end

Toggles.ToggleProgressionRebirth:OnChanged(function(state)
    if state then
        if IsProgressionTargetAvailable() then
            Library:Notify("Auto Progression: Target tier is already unlocked!")
            Toggles.ToggleProgressionRebirth:SetValue(false)
            return
        end
        StartProgressionRebirth()
    else
        StopTask("ProgressionRebirth")
    end
end)

local EMBED_COLOR = 0x00C8B4
local httpReq = (syn and syn.request) or (http and http.request) or request

local function ResolveAssetURL(assetId, size)
    size = size or "420x420"

    for attempt = 1, 2 do
        local ok, res = pcall(httpReq, {
            Url = "https://thumbnails.roproxy.com/v1/assets?assetIds="
                .. assetId
                .. "&returnPolicy=PlaceHolder&size="
                .. size
                .. "&format=Png",
            Method = "GET",
        })

        if not ok or not res or res.StatusCode ~= 200 then return nil end

        local ok2, body = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if not ok2 or not body or not body.data or not body.data[1] then return nil end

        local entry = body.data[1]
        if entry.state == "Completed" then
            return entry.imageUrl
        end

        if attempt == 1 then
            task.wait(2)
        end
    end

    return nil
end

local function ResolveIconURL(assetId)
    local url = ResolveAssetURL(assetId, "150x150")
    if url then return url end

    local ok, res = pcall(httpReq, {
        Url = "https://assetdelivery.roproxy.com/v2/assetId/" .. assetId,
        Method = "GET",
    })

    if ok and res and res.StatusCode == 200 then
        local ok2, body = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if ok2 and body and body.location then
            return body.location
        end
    end

    return nil
end

local function ResolveAvatarURL(userId)
    local ok, res = pcall(httpReq, {
        Url = "https://thumbnails.roproxy.com/v1/users/avatar-headshot?userIds="
            .. tostring(userId)
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

    local assetId = tostring(data.IDs[petType] or data.IDs.Normal):match("%d+")
    if not assetId then return nil end

    return ResolveAssetURL(assetId, "512x512")
end

local PhosphyIconURL = nil
task.spawn(function()
    PhosphyIconURL = ResolveIconURL("111288992980872")
end)

local cachedAvatarURL = nil
task.spawn(function()
    cachedAvatarURL = ResolveAvatarURL(LocalPlayer.UserId)
end)

local function BuildEmbed(petName, rarity, petType, petImageURL, playerAvatarURL)
    local embed = {
        title = rarity .. " - " .. petName .. " Hatched!",
        color = EMBED_COLOR,
        fields = {
            { name = "Pet", value = petName, inline = true },
            { name = "Rarity", value = rarity, inline = true },
            { name = "Type", value = petType or "Normal", inline = true },
            { name = "Player", value = LocalPlayer.Name, inline = true },
            { name = "Eggs Hatched", value = tostring(PlayerData.Data.Eggs), inline = true },
        },
        footer = { text = "Phosphy - ClickBreakers" },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }

    if petImageURL then
        embed.image = { url = petImageURL }
    end
    if playerAvatarURL then
        embed.thumbnail = { url = playerAvatarURL }
    end

    return embed
end

local function PostWebhook(url, content, embeds)
    if not httpReq then return false end

    local payload = HttpService:JSONEncode({
        username = "Phosphy",
        avatar_url = PhosphyIconURL or nil,
        content = content and content ~= "" and content or nil,
        embeds = embeds,
    })

    local ok = pcall(httpReq, {
        Url = url,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = payload,
    })
    return ok
end

local function MakeSummarySnapshot()
    local itemCounts = {}
    local data = PlayerData.Data or {}
    local function pickNumber(names)
        for _, name in ipairs(names) do
            local value = data[name]
            if type(value) == "number" then
                return value
            end
        end
        return 0
    end

    for itemName, count in pairs(data.Items or {}) do
        if type(count) == "number" then
            itemCounts[itemName] = count
        end
    end

    return {
        Eggs = pickNumber({ "TotalEggsHatched", "EggsHatchedTotal", "TotalEggs", "EggsTotal", "EggsHatched", "Eggs" }),
        Rebirths = pickNumber({ "TotalRebirths", "RebirthsTotal", "TotalRebirth", "RebirthTotal", "Rebirths" }),
        Gems = pickNumber({ "TotalGems", "GemsTotal", "TotalGem", "GemTotal", "GemsEarned", "Gems" }),
        Spins = data.Spins or 0,
        EvilSpins = data.EvilSpins or 0,
        Items = itemCounts,
    }
end

local function DeltaNumber(before, after)
    return math.max(0, (after or 0) - (before or 0))
end

local function NetDeltaNumber(before, after)
    return (after or 0) - (before or 0)
end

local function fmtSigned(n)
    if n > 0 then
        return "+" .. fmtNum(n)
    elseif n < 0 then
        return "-" .. fmtNum(math.abs(n))
    end
    return "0"
end

local function GetItemDelta(beforeItems, afterItems)
    local total = 0
    local changed = {}
    local seen = {}

    for itemName, afterCount in pairs(afterItems or {}) do
        local delta = NetDeltaNumber(beforeItems and beforeItems[itemName] or 0, afterCount)
        if delta ~= 0 then
            total = total + delta
            table.insert(changed, { Name = itemName, Amount = delta })
        end
        seen[itemName] = true
    end

    for itemName, beforeCount in pairs(beforeItems or {}) do
        if not seen[itemName] then
            local delta = NetDeltaNumber(beforeCount, 0)
            if delta ~= 0 then
                total = total + delta
                table.insert(changed, { Name = itemName, Amount = delta })
            end
        end
    end

    table.sort(changed, function(a, b)
        if math.abs(a.Amount) == math.abs(b.Amount) then
            return a.Name < b.Name
        end
        return math.abs(a.Amount) > math.abs(b.Amount)
    end)

    return total, changed
end

local function IsSummaryMetricEnabled(metricName)
    local selected = Options.SummaryMetrics and Options.SummaryMetrics.Value
    return type(selected) == "table" and selected[metricName] == true
end

local function HasSummaryMetricSelected()
    local selected = Options.SummaryMetrics and Options.SummaryMetrics.Value
    return type(selected) == "table" and next(selected) ~= nil
end

local function BuildItemsSummary(total, changed)
    if total == 0 and #changed == 0 then
        return "```0```"
    end

    local lines = { "Net: " .. fmtSigned(total) }
    for i = 1, math.min(10, #changed) do
        table.insert(lines, changed[i].Name .. " " .. fmtSigned(changed[i].Amount))
    end

    return "```" .. table.concat(lines, "\n") .. "```"
end

local function MakeSummaryTotals()
    return {
        Eggs = 0,
        Rebirths = 0,
        Gems = 0,
        Spins = 0,
        EvilSpins = 0,
        Items = 0,
        ItemBreakdown = {},
    }
end

local function AddSummaryDelta(totals, beforeSnapshot, afterSnapshot)
    totals.Eggs = totals.Eggs + DeltaNumber(beforeSnapshot.Eggs, afterSnapshot.Eggs)
    totals.Rebirths = totals.Rebirths + DeltaNumber(beforeSnapshot.Rebirths, afterSnapshot.Rebirths)
    totals.Gems = totals.Gems + DeltaNumber(beforeSnapshot.Gems, afterSnapshot.Gems)
    totals.Spins = totals.Spins + DeltaNumber(beforeSnapshot.Spins, afterSnapshot.Spins)
    totals.EvilSpins = totals.EvilSpins + DeltaNumber(beforeSnapshot.EvilSpins, afterSnapshot.EvilSpins)

    local itemTotal, itemBreakdown = GetItemDelta(beforeSnapshot.Items, afterSnapshot.Items)
    totals.Items = totals.Items + itemTotal
    for _, entry in ipairs(itemBreakdown) do
        totals.ItemBreakdown[entry.Name] = (totals.ItemBreakdown[entry.Name] or 0) + entry.Amount
    end
end

local function GetSortedItemBreakdown(itemBreakdown)
    local changed = {}
    for itemName, amount in pairs(itemBreakdown or {}) do
        if amount ~= 0 then
            table.insert(changed, { Name = itemName, Amount = amount })
        end
    end

    table.sort(changed, function(a, b)
        if math.abs(a.Amount) == math.abs(b.Amount) then
            return a.Name < b.Name
        end
        return math.abs(a.Amount) > math.abs(b.Amount)
    end)

    return changed
end

local _summaryAssetCache = {}
local SummaryAssetFallbackIds = {
    Clicks = "116095918726107",
    Gems = "131695933949458",
    Rebirths = "135239736724543",
    Tokens = "127939928005660",
    ClickPotion = "106966827319533",
    LuckPotion = "115747548629342",
    RebirthPotion = "86758925741935",
    Apple = "83665462783963",
    Avocado = "116847557727594",
    Carrot = "80510292226789",
    Strawberry = "119089130768711",
    Orange = "120266331790622",
    Banana = "113775632511058",
    Spins = "83525450643033",
    ExclusiveEgg = "111956887458876",
    SpringEgg = "80970859422088",
    CandyEgg = "91146585214034",
    MoltenEgg = "111956887458876",
    ["Surprise Box"] = "100225564613014",
    EvilSpins = "137237084740768",
}

local function GetSummaryAssetId(name)
    if SummaryAssetFallbackIds[name] then
        return SummaryAssetFallbackIds[name]
    end

    local raw = Items.Items and Items.Items[name]
    if type(raw) == "string" then
        return raw:match("%d+")
    elseif type(raw) == "table" then
        local image = raw.Image or raw.Icon or raw.Asset or raw.AssetId or raw.ID
        if image then return tostring(image):match("%d+") end
    end
    return nil
end

local function GetSummaryAssetURL(name)
    if _summaryAssetCache[name] ~= nil then
        return _summaryAssetCache[name] or nil
    end

    local assetId = GetSummaryAssetId(name)
    if not assetId then
        _summaryAssetCache[name] = false
        return nil
    end

    local url = ResolveAssetURL(assetId, "150x150")
    _summaryAssetCache[name] = url or false
    return url
end

local function ReadLeaderstatValue(names)
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if not leaderstats then return nil end

    for _, name in ipairs(names) do
        local stat = leaderstats:FindFirstChild(name)
        if stat and stat.Value ~= nil then
            return stat.Value
        end
    end

    return nil
end

local function GetDisplayStat(primaryNames, fallbackNames)
    local data = PlayerData.Data or {}

    for _, name in ipairs(primaryNames) do
        local value = data[name]
        if type(value) == "number" then return fmtNum(value) end
        if type(value) == "string" and value ~= "" then return value end
    end

    local leaderValue = ReadLeaderstatValue(primaryNames)
        or ReadLeaderstatValue(fallbackNames or {})
    if leaderValue ~= nil then
        return tostring(leaderValue)
    end

    for _, name in ipairs(fallbackNames or {}) do
        local value = data[name]
        if type(value) == "number" then return fmtNum(value) end
        if type(value) == "string" and value ~= "" then return value end
    end

    return "0"
end

local function GetTotalTimePlayed()
    local data = PlayerData.Data or {}
    local candidates = {
        data.TotalPlaytime,
        data.TotalPlayTime,
        data.TimePlayed,
        data.Playtime,
        data.PlayTime,
        data.TotalTimePlayed,
        data.TimePlayedTotal,
        data.PlaytimeTotal,
        data.PlayTimeTotal,
    }

    for _, value in ipairs(candidates) do
        if type(value) == "number" then
            return value
        end
    end

    local gifts = LocalPlayer:FindFirstChild("Gifts")
    local timer = gifts and gifts:FindFirstChild("Timer")
    if timer and type(timer.Value) == "number" then
        return timer.Value
    end

    return 0
end

local function fmtDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local days = math.floor(seconds / 86400)
    seconds = seconds % 86400
    local hours = math.floor(seconds / 3600)
    seconds = seconds % 3600
    local minutes = math.floor(seconds / 60)

    if days > 0 then
        return string.format("%dd %dh %dm", days, hours, minutes)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    end

    return string.format("%dm", minutes)
end

local function AddSummaryMetric(entries, metricName, value, imageName)
    if IsSummaryMetricEnabled(metricName) then
        table.insert(entries, {
            Name = metricName,
            Value = value,
            ImageName = imageName,
        })
    end
end

local function BuildSummaryMetricEntries(totals, itemBreakdown)
    local entries = {}
    AddSummaryMetric(entries, "Eggs Hatched", fmtNum(totals.Eggs), "ExclusiveEgg")
    AddSummaryMetric(entries, "Rebirths Gained", fmtNum(totals.Rebirths), "Rebirths")
    AddSummaryMetric(entries, "Gems Gained", fmtNum(totals.Gems), "Gems")
    AddSummaryMetric(entries, "Spins Gained", fmtNum(totals.Spins), "Spins")
    AddSummaryMetric(entries, "Evil Spins Gained", fmtNum(totals.EvilSpins), "EvilSpins")
    AddSummaryMetric(entries, "Items Net Change", BuildItemsSummary(totals.Items, itemBreakdown), itemBreakdown[1] and itemBreakdown[1].Name or "Surprise Box")
    AddSummaryMetric(entries, "Total Rebirths", GetDisplayStat({
        "TotalRebirths",
        "RebirthsTotal",
        "TotalRebirth",
        "RebirthTotal",
    }, { "Rebirths" }), "Rebirths")
    AddSummaryMetric(entries, "Total Gems", GetDisplayStat({
        "TotalGems",
        "GemsTotal",
        "TotalGem",
        "GemTotal",
    }, { "Gems" }), "Gems")
    AddSummaryMetric(entries, "Total Eggs Hatched", GetDisplayStat({
        "TotalEggsHatched",
        "EggsHatchedTotal",
        "TotalEggs",
        "EggsTotal",
        "EggsHatched",
    }, { "Eggs" }), "ExclusiveEgg")
    AddSummaryMetric(entries, "Total Time Played", fmtDuration(GetTotalTimePlayed()), "Tokens")
    return entries
end

local function BuildSummaryEmbeds(minutes, totals, isTest)
    local itemBreakdown = GetSortedItemBreakdown(totals.ItemBreakdown)
    local entries = BuildSummaryMetricEntries(totals, itemBreakdown)
    local embeds = {}

    for i, entry in ipairs(entries) do
        if i > 10 then break end

        local iconURL = entry.ImageName and GetSummaryAssetURL(entry.ImageName)
        local author = { name = entry.Name }
        if iconURL then
            author.icon_url = iconURL
        end

        local embed = {
            color = EMBED_COLOR,
            author = author,
            description = tostring(entry.Value),
        }

        if i == 1 then
            embed.title = isTest and "Summary Webhook Test" or "Progress Summary"
            embed.fields = {
                { name = "Window", value = isTest and "Test" or tostring(minutes) .. " minute(s)", inline = true },
                { name = "Player", value = LocalPlayer.Name, inline = true },
            }
            if cachedAvatarURL then
                embed.thumbnail = { url = cachedAvatarURL }
            end
            embed.footer = { text = "Phosphy - ClickBreakers" }
            embed.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        end

        table.insert(embeds, embed)
    end

    return embeds
end

SendAlertWebhookTest = function()
    local url = Options.WebhookURL.Value
    if not url or url == "" then
        Library:Notify("Alert Webhook: Enter a URL first!")
        return
    end

    local ok = PostWebhook(url, "", {
        {
            title = "Alert Webhook Test",
            color = EMBED_COLOR,
            fields = {
                { name = "Player", value = LocalPlayer.Name, inline = true },
                { name = "Webhook", value = "Alerts", inline = true },
            },
            footer = { text = "Phosphy - ClickBreakers" },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        },
    })
    Library:Notify(ok and "Alert webhook test sent!" or "Alert webhook test failed.")
end

SendSummaryWebhookTest = function()
    local url = Options.WebhookSummaryURL.Value
    if not url or url == "" then
        Library:Notify("Summary Webhook: Enter a URL first!")
        return
    end
    if not HasSummaryMetricSelected() then
        Library:Notify("Summary Webhook: Select at least one metric!")
        return
    end

    local totals = MakeSummaryTotals()
    local ok = PostWebhook(url, "", BuildSummaryEmbeds(tonumber(Options.WebhookSummaryMinutes.Value) or 10, totals, true))
    Library:Notify(ok and "Summary webhook test sent!" or "Summary webhook test failed.")
end

local function StartWebhookSummary()
    StopTask("WebhookSummary")

    local url = Options.WebhookSummaryURL.Value
    if not url or url == "" then
        Library:Notify("Summary Webhook: Enter a URL first!")
        Toggles.ToggleWebhookSummary:SetValue(false)
        return
    end
    if not HasSummaryMetricSelected() then
        Library:Notify("Summary Webhook: Select at least one metric!")
        Toggles.ToggleWebhookSummary:SetValue(false)
        return
    end

    Tasks.WebhookSummary = task.spawn(function()
        local lastSnapshot = MakeSummarySnapshot()

        while Toggles.ToggleWebhookSummary.Value do
            local minutes = math.clamp(tonumber(Options.WebhookSummaryMinutes.Value) or 10, 1, 60)
            local waited = 0
            local seconds = minutes * 60
            local totals = MakeSummaryTotals()

            while Toggles.ToggleWebhookSummary.Value and waited < seconds do
                task.wait(1)
                local currentSnapshot = MakeSummarySnapshot()
                AddSummaryDelta(totals, lastSnapshot, currentSnapshot)
                lastSnapshot = currentSnapshot
                waited = waited + 1
            end

            if not Toggles.ToggleWebhookSummary.Value then break end

            if not HasSummaryMetricSelected() then
                Library:Notify("Summary Webhook: Select at least one metric!")
                Toggles.ToggleWebhookSummary:SetValue(false)
                break
            end

            local currentUrl = Options.WebhookSummaryURL.Value
            if currentUrl and currentUrl ~= "" then
                PostWebhook(currentUrl, "", BuildSummaryEmbeds(minutes, totals, false))
            else
                Library:Notify("Summary Webhook: URL is empty. Stopping.")
                Toggles.ToggleWebhookSummary:SetValue(false)
                break
            end
        end
    end)
end

local webhookConn = nil

local function InstallWebhookListener()
    if webhookConn then
        webhookConn:Disconnect()
        webhookConn = nil
    end

    webhookConn = EggRemote.OnClientEvent:Connect(function(eventType, _, _, pets)
        if eventType ~= "Unbox" then return end
        if not Toggles.ToggleWebhook.Value then return end

        local url = Options.WebhookURL.Value
        if not url or url == "" then return end
        if not pets then return end

        task.spawn(function()
            local pingStr = ""
            local pingType = Options.WebhookPingType.Value
            local pingID = Options.WebhookPingID.Value or ""

            if pingType == "User" and pingID ~= "" then
                pingStr = "<@" .. pingID .. "> "
            elseif pingType == "Role" and pingID ~= "" then
                pingStr = "<@&" .. pingID .. "> "
            end

            local notifyRarities = Options.WebhookNotifyRarities.Value
            local pingRarities = Options.WebhookPingRarities.Value
            local pingEmbeds = {}

            for _, petInfo in pairs(pets) do
                local petName = petInfo.PetName
                local petType = type(petInfo) == "table" and petInfo.PetType or "Normal"
                local petData = PetsModule.Pets[petName]
                if not petData then continue end

                local rarity = petData.Rarity
                local shouldNotify = notifyRarities[rarity]
                local shouldPing = pingRarities[rarity]
                if not shouldNotify and not shouldPing then continue end

                local petImg = GetPetImageURL(petName, petType)
                local embed = BuildEmbed(petName, rarity, petType, petImg, cachedAvatarURL)

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
    if state then
        InstallWebhookListener()
    else
        if webhookConn then
            webhookConn:Disconnect()
            webhookConn = nil
        end
    end
end)

Toggles.ToggleWebhookSummary:OnChanged(function(state)
    if state then
        StartWebhookSummary()
    else
        StopTask("WebhookSummary")
    end
end)

Options.WebhookSummaryMinutes:OnChanged(function()
    if Toggles.ToggleWebhookSummary.Value then
        StartWebhookSummary()
    end
end)

Library:OnUnload(function()
    if hookRefFn and hookRefOriginal then
        hookfunction(hookRefFn, hookRefOriginal)
        hookRefFn = nil
        hookRefOriginal = nil
    end

    RemoveTeleportBlock()
    RemoveFpsCap()
    StopPerformance()
    EnableRendering()

    local taskNames = {}
    for name in pairs(Tasks) do
        table.insert(taskNames, name)
    end
    for _, name in ipairs(taskNames) do
        StopTask(name)
    end

    if autoAcceptTradeConn then
        autoAcceptTradeConn:Disconnect()
        autoAcceptTradeConn = nil
    end
    if autoConfirmTradeConn then
        autoConfirmTradeConn:Disconnect()
        autoConfirmTradeConn = nil
    end
    if webhookConn then
        webhookConn:Disconnect()
        webhookConn = nil
    end

    currentTradePartner = nil
    UpdateIndexStatus(nil)
    SwitchRemote:FireServer("AutoHatching", false)
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
SaveManager:SetFolder("PhosphyHub/ClickBreakers")
SaveManager:SetSubFolder("Lobby")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()
