local cloneref = (cloneref or clonereference or function(instance: any)
    return instance
end)
local clonefunction = (clonefunction or copyfunction or function(func) 
    return func 
end)

local HttpService: HttpService = cloneref(game:GetService("HttpService"))
local isfolder, isfile, listfiles = isfolder, isfile, listfiles

if typeof(clonefunction) == "function" then
    

    local
        isfolder_copy,
        isfile_copy,
        listfiles_copy = clonefunction(isfolder), clonefunction(isfile), clonefunction(listfiles)

    local isfolder_success, isfolder_error = pcall(function()
        return isfolder_copy("test" .. tostring(math.random(1000000, 9999999)))
    end)

    if isfolder_success == false or typeof(isfolder_error) ~= "boolean" then
        isfolder = function(folder)
            local success, data = pcall(isfolder_copy, folder)
            return (if success then data else false)
        end

        isfile = function(file)
            local success, data = pcall(isfile_copy, file)
            return (if success then data else false)
        end

        listfiles = function(folder)
            local success, data = pcall(listfiles_copy, folder)
            return (if success then data else {})
        end
    end
end

local SaveManager = {} do
    SaveManager.Folder = "ObsidianLibSettings"
    SaveManager.SubFolder = ""
    SaveManager.Ignore = {}
    SaveManager.Library = nil
    SaveManager.AutoSave = false
    SaveManager._autoSaveThread = nil
    SaveManager._autoSaveHooked = {}
    SaveManager.CustomData = {}
    SaveManager.Parser = {
        Toggle = {
            Save = function(idx, object)
                return { type = "Toggle", idx = idx, value = object.Value }
            end,
            Load = function(idx, data)
                local object = SaveManager.Library.Toggles[idx]
                if object and object.Value ~= data.value then
                    object:SetValue(data.value)
                end
            end,
        },
        Slider = {
            Save = function(idx, object)
                return { type = "Slider", idx = idx, value = tostring(object.Value) }
            end,
            Load = function(idx, data)
                local object = SaveManager.Library.Options[idx]
                if object and object.Value ~= data.value then
                    object:SetValue(data.value)
                end
            end,
        },
        Dropdown = {
            Save = function(idx, object)
                return { type = "Dropdown", idx = idx, value = object.Value, multi = object.Multi }
            end,
            Load = function(idx, data)
                local object = SaveManager.Library.Options[idx]
                if object and object.Value ~= data.value then
                    object:SetValue(data.value)
                end
            end,
        },
        ColorPicker = {
            Save = function(idx, object)
                return { type = "ColorPicker", idx = idx, value = object.Value:ToHex(), transparency = object.Transparency }
            end,
            Load = function(idx, data)
                if SaveManager.Library.Options[idx] then
                    SaveManager.Library.Options[idx]:SetValueRGB(Color3.fromHex(data.value), data.transparency)
                end
            end,
        },
        KeyPicker = {
            Save = function(idx, object)
                return { type = "KeyPicker", idx = idx, mode = object.Mode, key = object.Value, modifiers = object.Modifiers }
            end,
            Load = function(idx, data)
                if SaveManager.Library.Options[idx] then
                    SaveManager.Library.Options[idx]:SetValue({ data.key, data.mode, data.modifiers })
                end
            end,
        },
        Input = {
            Save = function(idx, object)
                return { type = "Input", idx = idx, text = object.Value }
            end,
            Load = function(idx, data)
                local object = SaveManager.Library.Options[idx]
                if object and object.Value ~= data.text and type(data.text) == "string" then
                    SaveManager.Library.Options[idx]:SetValue(data.text)
                end
            end,
        },
    }

    function SaveManager:SetLibrary(library)
        self.Library = library
    end

    function SaveManager:IgnoreThemeSettings()
        self:SetIgnoreIndexes({
            "BackgroundColor", "MainColor", "AccentColor", "OutlineColor", "FontColor", "FontFace", 
            "ThemeManager_ThemeList", "ThemeManager_CustomThemeList", "ThemeManager_CustomThemeName", 
        })
    end

    
    function SaveManager:CheckSubFolder(createFolder)
        if typeof(self.SubFolder) ~= "string" or self.SubFolder == "" then return false end

        if createFolder == true then
            if not isfolder(self.Folder .. "/settings/" .. self.SubFolder) then
                makefolder(self.Folder .. "/settings/" .. self.SubFolder)
            end
        end

        return true
    end

    function SaveManager:GetPaths()
        local paths = {}

        local parts = self.Folder:split("/")
        for idx = 1, #parts do
            local path = table.concat(parts, "/", 1, idx)
            if not table.find(paths, path) then paths[#paths + 1] = path end
        end

        paths[#paths + 1] = self.Folder .. "/themes"
        paths[#paths + 1] = self.Folder .. "/settings"

        if self:CheckSubFolder(false) then
            local subFolder = self.Folder .. "/settings/" .. self.SubFolder
            parts = subFolder:split("/")

            for idx = 1, #parts do
                local path = table.concat(parts, "/", 1, idx)
                if not table.find(paths, path) then paths[#paths + 1] = path end
            end
        end

        return paths
    end

    function SaveManager:BuildFolderTree()
        local paths = self:GetPaths()

        for i = 1, #paths do
            local str = paths[i]
            if isfolder(str) then continue end

            makefolder(str)
        end
    end

    function SaveManager:CheckFolderTree()
        if isfolder(self.Folder) then return end
        SaveManager:BuildFolderTree()

        task.wait(0.1)
    end

    function SaveManager:SetIgnoreIndexes(list)
        for _, key in list do
            self.Ignore[key] = true
        end
    end

    function SaveManager:SetFolder(folder)
        self.Folder = folder
        self:BuildFolderTree()
    end

    function SaveManager:SetSubFolder(folder)
        self.SubFolder = folder
        self:BuildFolderTree()
    end

    function SaveManager:RegisterCustomData(key, saveFn, loadFn)
        self.CustomData[key] = { Save = saveFn, Load = loadFn }
    end

    function SaveManager:Save(name)
        if (not name) then
            return false, "no config file is selected"
        end
        SaveManager:CheckFolderTree()

        local fullPath = self.Folder .. "/settings/" .. name .. ".json"
        if SaveManager:CheckSubFolder(true) then
            fullPath = self.Folder .. "/settings/" .. self.SubFolder .. "/" .. name .. ".json"
        end

        local data = {
            objects = {}
        }

        for idx, toggle in self.Library.Toggles do
            if not toggle.Type then continue end
            if not self.Parser[toggle.Type] then continue end
            if self.Ignore[idx] then continue end

            table.insert(data.objects, self.Parser[toggle.Type].Save(idx, toggle))
        end

        for idx, option in self.Library.Options do
            if not option.Type then continue end
            if not self.Parser[option.Type] then continue end
            if self.Ignore[idx] then continue end

            table.insert(data.objects, self.Parser[option.Type].Save(idx, option))
        end

        if next(self.CustomData) then
            data.custom = {}
            for key, handler in self.CustomData do
                local ok, val = pcall(handler.Save)
                if ok then data.custom[key] = val end
            end
        end

        local success, encoded = pcall(HttpService.JSONEncode, HttpService, data)
        if not success then
            return false, "failed to encode data"
        end

        writefile(fullPath, encoded)
        return true
    end

    function SaveManager:Load(name)
        if (not name) then
            return false, "no config file is selected"
        end
        SaveManager:CheckFolderTree()

        local file = self.Folder .. "/settings/" .. name .. ".json"
        if SaveManager:CheckSubFolder(true) then
            file = self.Folder .. "/settings/" .. self.SubFolder .. "/" .. name .. ".json"
        end

        if not isfile(file) then return false, "invalid file" end

        local success, decoded = pcall(HttpService.JSONDecode, HttpService, readfile(file))
        if not success then return false, "decode error" end

        for _, option in decoded.objects do
            if not option.type then continue end
            if not self.Parser[option.type] then continue end
            if self.Ignore[option.idx] then continue end

            task.spawn(self.Parser[option.type].Load, option.idx, option)
        end

        if decoded.custom and next(self.CustomData) then
            for key, handler in self.CustomData do
                if decoded.custom[key] ~= nil then
                    pcall(handler.Load, decoded.custom[key])
                end
            end
        end

        return true
    end

    function SaveManager:Delete(name)
        if (not name) then
            return false, "no config file is selected"
        end

        local file = self.Folder .. "/settings/" .. name .. ".json"
        if SaveManager:CheckSubFolder(true) then
            file = self.Folder .. "/settings/" .. self.SubFolder .. "/" .. name .. ".json"
        end

        if not isfile(file) then return false, "invalid file" end

        local success = pcall(delfile, file)
        if not success then return false, "delete file error" end

        return true
    end

    function SaveManager:RefreshConfigList()
        local success, data = pcall(function()
            SaveManager:CheckFolderTree()

            local list = {}
            local out = {}

            if SaveManager:CheckSubFolder(true) then
                list = listfiles(self.Folder .. "/settings/" .. self.SubFolder)
            else
                list = listfiles(self.Folder .. "/settings")
            end
            if typeof(list) ~= "table" then list = {} end

            for i = 1, #list do
                local file = list[i]
                if file:sub(-5) == ".json" then
                   

                    local pos = file:find(".json", 1, true)
                    local start = pos

                    local char = file:sub(pos, pos)
                    while char ~= "/" and char ~= "\\" and char ~= "" do
                        pos = pos - 1
                        char = file:sub(pos, pos)
                    end

                    if char == "/" or char == "\\" then
                        table.insert(out, file:sub(pos + 1, start - 1))
                    end
                end
            end

            return out
        end)

        if (not success) then
            if self.Library then
                self.Library:Notify("Failed to load config list: " .. tostring(data))
            else
                warn("Failed to load config list: " .. tostring(data))
            end

            return {}
        end

        return data
    end

    
    function SaveManager:GetAutoloadConfig()
        SaveManager:CheckFolderTree()

        local autoLoadPath = self.Folder .. "/settings/autoload.txt"
        if SaveManager:CheckSubFolder(true) then
            autoLoadPath = self.Folder .. "/settings/" .. self.SubFolder .. "/autoload.txt"
        end

        if isfile(autoLoadPath) then
            local successRead, name = pcall(readfile, autoLoadPath)
            if not successRead then
                return "none"
            end

            name = tostring(name)
            return if name == "" then "none" else name
        end

        return "none"
    end

    function SaveManager:LoadAutoloadConfig()
        SaveManager:CheckFolderTree()

        local accountConfig = self:GetAccountConfig()
        if accountConfig then
            local success, err = self:Load(accountConfig)
            if not success then
                self.Library:Notify("Failed to load account config: " .. err)
                return
            end

            local playerName = game:GetService("Players").LocalPlayer.Name
            self.Library:Notify(string.format("Auto loaded config %q for account %q", accountConfig, playerName))
            return
        end

        local autoLoadPath = self.Folder .. "/settings/autoload.txt"
        if SaveManager:CheckSubFolder(true) then
            autoLoadPath = self.Folder .. "/settings/" .. self.SubFolder .. "/autoload.txt"
        end

        if isfile(autoLoadPath) then
            local successRead, name = pcall(readfile, autoLoadPath)
            if not successRead then
                self.Library:Notify("Failed to load autoload config: write file error")
                return
            end

            local success, err = self:Load(name)
            if not success then
                self.Library:Notify("Failed to load autoload config: " .. err)
                return
            end

            self.Library:Notify(string.format("Auto loaded config %q", name))
        end
    end

    function SaveManager:SaveAutoloadConfig(name)
        SaveManager:CheckFolderTree()

        local autoLoadPath = self.Folder .. "/settings/autoload.txt"
        if SaveManager:CheckSubFolder(true) then
            autoLoadPath = self.Folder .. "/settings/" .. self.SubFolder .. "/autoload.txt"
        end

        local success = pcall(writefile, autoLoadPath, name)
        if not success then return false, "write file error" end

        return true, ""
    end

    function SaveManager:GetAutoSaveState()
        SaveManager:CheckFolderTree()

        local path = self.Folder .. "/settings/autosave.txt"
        if SaveManager:CheckSubFolder(true) then
            path = self.Folder .. "/settings/" .. self.SubFolder .. "/autosave.txt"
        end

        if isfile(path) then
            local ok, val = pcall(readfile, path)
            if ok and val == "true" then return true end
        end

        return false
    end

    function SaveManager:SaveAutoSaveState(enabled)
        SaveManager:CheckFolderTree()

        local path = self.Folder .. "/settings/autosave.txt"
        if SaveManager:CheckSubFolder(true) then
            path = self.Folder .. "/settings/" .. self.SubFolder .. "/autosave.txt"
        end

        pcall(writefile, path, tostring(enabled))
    end

    function SaveManager:DeleteAutoLoadConfig()
        SaveManager:CheckFolderTree()

        local autoLoadPath = self.Folder .. "/settings/autoload.txt"
        if SaveManager:CheckSubFolder(true) then
            autoLoadPath = self.Folder .. "/settings/" .. self.SubFolder .. "/autoload.txt"
        end

        local success = pcall(delfile, autoLoadPath)
        if not success then return false, "delete file error" end

        return true, ""
    end

    function SaveManager:_QueueAutoSave()
        if not self.AutoSave then return end

        local name = self:GetAutoloadConfig()
        if name == "none" then return end

        if self._autoSaveThread then
            task.cancel(self._autoSaveThread)
        end

        self._autoSaveThread = task.delay(1, function()
            self._autoSaveThread = nil
            if not self.AutoSave then return end
            self:Save(name)
        end)
    end

    function SaveManager:_HookElement(idx, element)
        if self._autoSaveHooked[idx] then return end
        if self.Ignore[idx] then return end
        if not element.Type or not self.Parser[element.Type] then return end

        self._autoSaveHooked[idx] = true
        local prev = element.Changed

        element.Changed = function(...)
            if prev then
                prev(...)
            end
            self:_QueueAutoSave()
        end
    end

    function SaveManager:SetupAutoSave()
        for idx, toggle in self.Library.Toggles do
            self:_HookElement(idx, toggle)
        end
        for idx, option in self.Library.Options do
            self:_HookElement(idx, option)
        end

        -- Watch for new elements being added
        local Toggles_mt = getmetatable(self.Library.Toggles)
        if not Toggles_mt or not Toggles_mt.__autosave then
            local mt = Toggles_mt or {}
            local oldNewIndex = mt.__newindex
            mt.__autosave = true
            mt.__newindex = function(t, k, v)
                if oldNewIndex then
                    oldNewIndex(t, k, v)
                else
                    rawset(t, k, v)
                end
                if v and typeof(v) == "table" then
                    self:_HookElement(k, v)
                end
            end
            if not Toggles_mt then
                setmetatable(self.Library.Toggles, mt)
            end
        end

        local Options_mt = getmetatable(self.Library.Options)
        if not Options_mt or not Options_mt.__autosave then
            local mt = Options_mt or {}
            local oldNewIndex = mt.__newindex
            mt.__autosave = true
            mt.__newindex = function(t, k, v)
                if oldNewIndex then
                    oldNewIndex(t, k, v)
                else
                    rawset(t, k, v)
                end
                if v and typeof(v) == "table" then
                    self:_HookElement(k, v)
                end
            end
            if not Options_mt then
                setmetatable(self.Library.Options, mt)
            end
        end
    end

    function SaveManager:_GetAccountConfigsPath()
        local path = self.Folder .. "/settings/accountconfigs.json"
        if SaveManager:CheckSubFolder(false) then
            path = self.Folder .. "/settings/" .. self.SubFolder .. "/accountconfigs.json"
        end
        return path
    end

    function SaveManager:GetAccountConfigs()
        SaveManager:CheckFolderTree()
        local path = self:_GetAccountConfigsPath()
        if not isfile(path) then return {} end

        local ok, raw = pcall(readfile, path)
        if not ok then return {} end

        local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if not ok2 or typeof(data) ~= "table" then return {} end

        return data
    end

    function SaveManager:SaveAccountConfigs(data)
        SaveManager:CheckFolderTree()
        if SaveManager:CheckSubFolder(true) then end

        local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
        if not ok then return false end

        local path = self:_GetAccountConfigsPath()
        pcall(writefile, path, encoded)
        return true
    end

    function SaveManager:GetAccountConfig()
        local configs = self:GetAccountConfigs()
        local playerName = game:GetService("Players").LocalPlayer.Name
        return configs[playerName]
    end

    function SaveManager:_BuildAccountListItems(configs)
        local items = {}
        for account, config in configs do
            table.insert(items, { Key = account, Display = account .. " → " .. config })
        end
        table.sort(items, function(a, b) return a.Key < b.Key end)
        return items
    end

    function SaveManager:BuildConfigSection(tab)
        assert(self.Library, "Must set SaveManager.Library")

        local section = tab:AddRightGroupbox("Configuration", "folder-cog")

        section:AddInput("SaveManager_ConfigName",    { Text = "Config name" })
        section:AddButton("Create config", function()
            local name = self.Library.Options.SaveManager_ConfigName.Value

            if name:gsub(" ", "") == "" then
                self.Library:Notify("Invalid config name (empty)", 2)
                return
            end

            local success, err = self:Save(name)
            if not success then
                self.Library:Notify("Failed to create config: " .. err)
                return
            end

            self.Library:Notify(string.format("Created config %q", name))
            self.Library.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            self.Library.Options.SaveManager_ConfigList:SetValue(nil)
        end)


        section:AddDropdown("SaveManager_ConfigList", { Text = "Config list", Values = self:RefreshConfigList(), AllowNull = true })
        section:AddButton("Load config", function()
            local name = self.Library.Options.SaveManager_ConfigList.Value

            local success, err = self:Load(name)
            if not success then
                self.Library:Notify("Failed to load config: " .. err)
                return
            end

            self.Library:Notify(string.format("Loaded config %q", name))
        end)
        section:AddButton("Overwrite config", function()
            local name = self.Library.Options.SaveManager_ConfigList.Value

            local success, err = self:Save(name)
            if not success then
                self.Library:Notify("Failed to overwrite config: " .. err)
                return
            end

            self.Library:Notify(string.format("Overwrote config %q", name))
        end)

        section:AddButton("Delete config", function()
            local name = self.Library.Options.SaveManager_ConfigList.Value

            local success, err = self:Delete(name)
            if not success then
                self.Library:Notify("Failed to delete config: " .. err)
                return
            end

            self.Library:Notify(string.format("Deleted config %q", name))
            self.Library.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            self.Library.Options.SaveManager_ConfigList:SetValue(nil)
        end)

        section:AddButton("Refresh list", function()
            self.Library.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            self.Library.Options.SaveManager_ConfigList:SetValue(nil)
        end)

        section:AddButton("Set as autoload", function()
            local name = self.Library.Options.SaveManager_ConfigList.Value

            local success, err = self:SaveAutoloadConfig(name)
            if not success then
                self.Library:Notify("Failed to set autoload config: " .. err)
                return
            end

            self.Library:Notify(string.format("Set %q to auto load", name))
            self.AutoloadConfigLabel:SetText("Current autoload config: " .. name)
            if self.AutoSave and self.AutoSaveLabel then
                self.AutoSaveLabel:SetText("Auto Saving: " .. name)
            end
        end)
        section:AddButton("Reset autoload", function()
            local success, err = self:DeleteAutoLoadConfig()
            if not success then
                self.Library:Notify("Failed to set autoload config: " .. err)
                return
            end

            self.Library:Notify("Set autoload to none")
            self.AutoloadConfigLabel:SetText("Current autoload config: none")
            if self.AutoSave and self.AutoSaveLabel then
                self.AutoSaveLabel:SetText("Auto Saving: none (set autoload first)")
            end
        end)

        self.AutoloadConfigLabel = section:AddLabel("Current autoload config: " .. self:GetAutoloadConfig(), true)

        local savedAutoSave = self:GetAutoSaveState()
        local autoSaveConfig = self:GetAutoloadConfig()

        section:AddToggle("SaveManager_AutoSave", {
            Text = "Auto Save Config",
            Default = savedAutoSave,
            Callback = function(value)
                self.AutoSave = value
                self:SaveAutoSaveState(value)
                if value then
                    self:SetupAutoSave()
                    local name = self:GetAutoloadConfig()
                    self.AutoSaveLabel:SetText("Auto Saving: " .. (if name ~= "none" then name else "none (set autoload first)"))
                else
                    self.AutoSaveLabel:SetText("Auto Saving: disabled")
                end
            end,
        })

        self.AutoSaveLabel = section:AddLabel("Auto Saving: " .. (if savedAutoSave then (if autoSaveConfig ~= "none" then autoSaveConfig else "none (set autoload first)") else "disabled"), true)

        if savedAutoSave then
            self.AutoSave = true
            self:SetupAutoSave()
        end

        do
            local Window = self.Library.Window
            local accountConfigs = self:GetAccountConfigs()
            local playerName = game:GetService("Players").LocalPlayer.Name

            local Dialog
            Dialog = Window:AddDialog("SaveManager_AccountConfigs", {
                Title = "Account Configs",
                Description = "Assign a config to each account. When that account logs in, its assigned config loads automatically (overrides autoload)",
                StartHidden = true,                                 
                AutoDismiss = false,
                Width = 400,
                MaxHeight = 350,
                FooterButtons = {
                    Save = {
                        Title = "Assign",
                        Variant = "Primary",
                        Order = 3,
                        Callback = function()
                            local account = self.Library.Options.SaveManager_AccName.Value
                            local config = self.Library.Options.SaveManager_AccConfig.Value

                            if not account or account:gsub("%s", "") == "" then
                                self.Library:Notify("Account name is empty", 2)
                                return
                            end
                            if not config or config == "" then
                                self.Library:Notify("Select a config first", 2)
                                return
                            end

                            accountConfigs[account] = config
                            self:SaveAccountConfigs(accountConfigs)
                            self.Library.Options.SaveManager_AccList:SetItems(self:_BuildAccountListItems(accountConfigs))
                            self.Library:Notify(string.format("Assigned %q → %q", account, config))
                        end,
                    },
                    Remove = {
                        Title = "Remove",
                        Variant = "Destructive",
                        Order = 2,
                        Callback = function()
                            local sel = self.Library.Options.SaveManager_AccList:GetSelected()
                            if not sel then
                                self.Library:Notify("Select an account to remove", 2)
                                return
                            end

                            local account = sel.Key
                            accountConfigs[account] = nil
                            self:SaveAccountConfigs(accountConfigs)
                            self.Library.Options.SaveManager_AccList:SetItems(self:_BuildAccountListItems(accountConfigs))
                            self.Library.Options.SaveManager_AccList:ClearSelection()
                            self.Library:Notify(string.format("Removed account %q", account))
                        end,
                    },
                    Close = {
                        Title = "Close",
                        Variant = "Ghost",
                        Order = 1,
                        Callback = function()
                        Dialog:Dismiss()
                        end,
                    },
                },
            })

            Dialog:AddList("SaveManager_AccList", {
                Text = "Assigned Accounts",
                Items = self:_BuildAccountListItems(accountConfigs),
                Multi = false,
                MaxHeight = 120,
                EmptyText = "No accounts assigned yet.",
                Callback = function(item)
                    self.Library.Options.SaveManager_AccName:SetValue(item.Key)
                end,
            })

            Dialog:AddInput("SaveManager_AccName", { Text = "Account name", Default = playerName, Placeholder = "Exact username" })
            Dialog:AddDropdown("SaveManager_AccConfig", { Text = "Config to load", Values = self:RefreshConfigList(), AllowNull = true })

            section:AddButton("Account configs", function()
                self.Library.Options.SaveManager_AccConfig:SetValues(self:RefreshConfigList())
                accountConfigs = self:GetAccountConfigs()
                self.Library.Options.SaveManager_AccList:SetItems(self:_BuildAccountListItems(accountConfigs))
                Dialog:Show()
            end)

            local currentAcc = accountConfigs[playerName]
            self.AccountConfigLabel = section:AddLabel(
                "Account config: " .. (if currentAcc then currentAcc else "none"),
                true
            )
        end

        section:AddButton("Export config", function()
            local data = {
                objects = {}
            }

            for idx, toggle in self.Library.Toggles do
                if not toggle.Type then continue end
                if not self.Parser[toggle.Type] then continue end
                if self.Ignore[idx] then continue end

                table.insert(data.objects, self.Parser[toggle.Type].Save(idx, toggle))
            end

            for idx, option in self.Library.Options do
                if not option.Type then continue end
                if not self.Parser[option.Type] then continue end
                if self.Ignore[idx] then continue end

                table.insert(data.objects, self.Parser[option.Type].Save(idx, option))
            end

            for _, obj in data.objects do
                if obj.type == "Input" and type(obj.text) == "string" then
                    local lower = obj.text:lower()
                    if lower:find("discord%.com/api/webhooks/") or lower:find("discordapp%.com/api/webhooks/") or lower:find("hooks%.slack%.com/") then
                        obj.text = ""
                    end
                end
            end

            if next(self.CustomData) then
                data.custom = {}
                for key, handler in self.CustomData do
                    local ok, val = pcall(handler.Save)
                    if ok then data.custom[key] = val end
                end
            end

            local success, encoded = pcall(HttpService.JSONEncode, HttpService, data)
            if not success then
                self.Library:Notify("Failed to export config")
                return
            end

            if setclipboard then
                setclipboard(encoded)
                self.Library:Notify("Config exported to clipboard")
            else
                self.Library:Notify("Clipboard not supported")
            end
        end)

        section:AddInput("SaveManager_ImportData", { Text = "Import Config", Placeholder = "Paste config JSON or URL here..." })
        section:AddButton("Import config", function()
            local raw = self.Library.Options.SaveManager_ImportData.Value

            if not raw or raw:gsub("%s", "") == "" then
                self.Library:Notify("Import data is empty", 2)
                return
            end

            raw = raw:gsub("^%s+", ""):gsub("%s+$", "")

            if raw:sub(1, 4) == "http" then
                self.Library:Notify("Fetching config from URL...")
                local ok, response = pcall(request, { Url = raw, Method = "GET" })
                if not ok or not response.Success then
                    self.Library:Notify("Failed to fetch URL: " .. (ok and response.StatusMessage or tostring(response)))
                    return
                end
                raw = response.Body
            end

            local success, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
            if not success or typeof(decoded) ~= "table" or not decoded.objects then
                self.Library:Notify("Invalid config data")
                return
            end

            for _, option in decoded.objects do
                if not option.type then continue end
                if not self.Parser[option.type] then continue end
                if self.Ignore[option.idx] then continue end

                task.spawn(self.Parser[option.type].Load, option.idx, option)
            end

            if decoded.custom and next(self.CustomData) then
                for key, handler in self.CustomData do
                    if decoded.custom[key] ~= nil then
                        pcall(handler.Load, decoded.custom[key])
                    end
                end
            end

            self.Library:Notify("Config imported successfully")
        end)

        self:SetIgnoreIndexes({ "SaveManager_ConfigList", "SaveManager_ConfigName", "SaveManager_ImportData", "SaveManager_AutoSave", "SaveManager_AccName", "SaveManager_AccConfig", "SaveManager_AccList" })
    end

    SaveManager:BuildFolderTree()
end

return SaveManager
