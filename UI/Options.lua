local ADDON = "HenrakMultiTool"
local NS = _G[ADDON] or {}
_G[ADDON] = NS

local function Refresh()
    if NS.Refresh then NS.Refresh() end
end

function NS.RegisterOptions()
    if not NS.L then NS.L = {} end
    if NS.CopyDefaults then NS.CopyDefaults() end
    if not Settings or not Settings.RegisterVerticalLayoutCategory then return end

    local category, layout = Settings.RegisterVerticalLayoutCategory(NS.L.TITLE or "HenrakMultiTool")
    if not category then return end

    NS.SettingsCategory = category
    if Settings.RegisterAddOnCategory then
        Settings.RegisterAddOnCategory(category)
    end

    local db = NS.GetDB and NS.GetDB() or {}

    local function safeCreateCheckbox(setting, label)
        if not Settings or not Settings.CreateCheckbox or not setting then return end
        Settings.CreateCheckbox(category, setting, label)
    end

    local function addCheckbox(settingName, key, defaultValue, labelKey, descriptionKey)
        if not Settings.RegisterAddOnSetting or not Settings.CreateCheckbox then return end
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_" .. settingName, key, db, "boolean", NS.L[labelKey] or labelKey, defaultValue)
        safeCreateCheckbox(setting, NS.L[descriptionKey] or descriptionKey)
    end

    local function addSlider(settingName, key, minimum, maximum, step, labelKey, defaultValue)
        if not Settings.RegisterAddOnSetting or not Settings.CreateSlider then return end
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_" .. settingName, key, db, "number", NS.L[labelKey] or labelKey, defaultValue)
        Settings.CreateSlider(category, setting, {
            minValue = minimum,
            maxValue = maximum,
            steps = math.floor((maximum - minimum) / step),
        })
        if setting and setting.SetValueChangedCallback then
            setting:SetValueChangedCallback(function(_, value)
                local newValue = tonumber(value)
                if not newValue then return end
                newValue = math.max(minimum, math.min(maximum, newValue))
                db[key] = newValue
                Refresh()
            end)
        end
    end

    local setting = Settings.RegisterAddOnSetting(
        category, ADDON .. "_enabled", "enabled",
        db, "boolean", NS.L.ENABLE or "Enable tracker", true
    )
    safeCreateCheckbox(setting, NS.L.ENABLE_DESC or "Show the tracker.")

    addCheckbox("autoClass", "autoClass", true, "AUTO_CLASS", "AUTO_CLASS_DESC")

    if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(NS.L.DISPLAY or "Display"))
    end

    addSlider("iconSize", "iconSize", NS.MIN_ICON_SIZE, NS.MAX_ICON_SIZE, 2, "ICON_SIZE", db.iconSize or NS.DEFAULT_ICON_SIZE)
    addSlider("sealIconSize", "sealIconSize", NS.MIN_ICON_SIZE, NS.MAX_ICON_SIZE, 2, "SEAL_ICON_SIZE", db.sealIconSize or db.iconSize or NS.DEFAULT_ICON_SIZE)
    addSlider("missingTextSize", "missingTextSize", NS.MIN_MISSING_TEXT_SIZE, NS.MAX_MISSING_TEXT_SIZE, 1, "MISSING_TEXT_SIZE", db.missingTextSize or NS.DEFAULT_MISSING_TEXT_SIZE)
    addSlider("timerTextSize", "timerTextSize", NS.MIN_TIMER_TEXT_SIZE, NS.MAX_TIMER_TEXT_SIZE, 1, "TIMER_TEXT_SIZE", db.timerTextSize or NS.DEFAULT_TIMER_TEXT_SIZE)

    addCheckbox("showMissingText", "showMissingText", true, "SHOW_MISSING", "SHOW_MISSING_DESC")
    addCheckbox("showNames", "showNames", true, "SHOW_NAMES", "SHOW_NAMES")
    addCheckbox("locked", "locked", false, "LOCK", "LOCK_DESC")

    if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(NS.L.BAGS or "Bags"))
    end
    addCheckbox("showBagSlots", "showBagSlots", true, "SHOW_BAG_SLOTS", "SHOW_BAG_SLOTS_DESC")

    if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(NS.L.BUFFS or "Buffs to track"))
    end

    local className = NS.GetPlayerClassKey and NS.GetPlayerClassKey() or NS.GetActiveClass()
    local profile = NS.GetClassProfile and NS.GetClassProfile(className) or { buffs = {} }
    for _, buff in ipairs(NS.ClassBuffs[className] or {}) do
        local label = NS.L[buff.labelKey] or buff.key
        local variable = "class_" .. className .. "_" .. buff.key
        local value = profile.buffs and profile.buffs[buff.key]
        local buffSetting = Settings.RegisterAddOnSetting and Settings.RegisterAddOnSetting(
            category, ADDON .. "_" .. variable, buff.key,
            profile.buffs, "boolean", label, value ~= false
        )
        if buffSetting then
            if buffSetting.SetValueChangedCallback then
                buffSetting:SetValueChangedCallback(function(_, newValue)
                    profile.buffs[buff.key] = newValue == true
                    Refresh()
                end)
            end
            if Settings.CreateCheckbox then
                Settings.CreateCheckbox(category, buffSetting, label)
            end
        end
    end

    if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(NS.L.XP_TITLE or "Experience Bar"))
    end
    if NS.RegisterXPOptions then
        NS.RegisterXPOptions(category)
    end

    if category and category.SetCommit then
        category:SetCommit(function()
            Refresh()
        end)
    end
end

local function GetClassNames()
    local list = {}
    for className in pairs(NS.ClassBuffs or {}) do
        table.insert(list, className)
    end
    table.sort(list)
    return list
end

SLASH_HENRAKMULTITOOL1 = "/henrak"
SLASH_HENRAKMULTITOOL2 = "/hmt"
SlashCmdList.HENRAKMULTITOOL = function(msg)
    local db = NS.GetDB and NS.GetDB() or {}
    msg = string.lower(msg or "")
    local cmd, arg = msg:match("^(%S+)%s*(.*)$")

    if cmd == "lock" then
        db.locked = true
        print("|cff70d5ffHenrakMultiTool|r: " .. (NS.L.LOCKED or "locked"))
    elseif cmd == "unlock" then
        db.locked = false
        print("|cff70d5ffHenrakMultiTool|r: " .. (NS.L.UNLOCKED or "unlocked"))
    elseif cmd == "reset" then
        local className = NS.GetActiveClass and NS.GetActiveClass() or NS.GetPlayerClassKey()
        local profile = NS.GetClassProfile and NS.GetClassProfile(className)
        if profile then
            profile.point = nil
            profile.sealPoint = nil
            profile.manaPoint = nil
        end
        local positions = db.positions and db.positions[className]
        if positions then
            positions.point = nil
            positions.sealPoint = nil
            positions.manaPoint = nil
        end
        if NS.RestorePosition then NS.RestorePosition() end
        print("|cff70d5ffHenrakMultiTool|r: " .. (NS.L.RESET or "position reset"))
    elseif cmd == "class" then
        local className = string.upper(arg or "")
        if NS.ClassBuffs and NS.ClassBuffs[className] then
            db.activeClass = className
            db.autoClass = false
            if NS.Refresh then NS.Refresh() end
            print("|cff70d5ffHenrakMultiTool|r: class set to " .. className)
        else
            local names = GetClassNames()
            print("|cff70d5ffHenrakMultiTool|r: available classes: " .. table.concat(names, ", "))
        end
    elseif cmd == "size" then
        local size = tonumber(arg)
        if size then
            NS.SetIconSize(size)
            print("|cff70d5ffHenrakMultiTool|r: icon size = " .. tostring(size))
        end
    elseif cmd == "auto" then
        db.autoClass = true
        NS.AutoSelectClass()
        print("|cff70d5ffHenrakMultiTool|r: auto class enabled")
    else
        if Settings and Settings.OpenToCategory and NS.SettingsCategory then
            Settings.OpenToCategory(NS.SettingsCategory:GetID())
        else
            print("|cff70d5ffHenrakMultiTool|r: /henrak class <CLASS>, /henrak size <N>, /henrak auto, /henrak lock, /henrak unlock, /henrak reset")
        end
    end
end
