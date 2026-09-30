local ADDON = "MultiTool"
local NS = _G[ADDON] or {}
_G[ADDON] = NS

local frame
local sessionXP = 0
local sessionStartedAt = 0
local previousLevel
local previousXP
local previousXPMax

local function GetQuestIDForIndex(index)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(index)
        return info and info.questID
    end
    return nil
end

local function GetQuestRewardXP(index, questID)
    -- Try every known calling convention across client/server API flavors
    -- until one returns a positive value.
    local xp

    if GetQuestLogRewardXP then
        xp = tonumber((GetQuestLogRewardXP(index)))
        if xp and xp > 0 then return xp end
    end

    if questID then
        if C_QuestLog and C_QuestLog.GetQuestLogRewardXP then
            xp = tonumber((C_QuestLog.GetQuestLogRewardXP(questID)))
            if xp and xp > 0 then return xp end
        end
        if GetQuestLogRewardXP then
            xp = tonumber((GetQuestLogRewardXP(questID)))
            if xp and xp > 0 then return xp end
        end
    end

    if SelectQuestLogEntry and GetQuestLogSelection and GetQuestLogRewardXP then
        local previousSelection = GetQuestLogSelection()
        SelectQuestLogEntry(index)
        xp = tonumber((GetQuestLogRewardXP()))
        SelectQuestLogEntry(previousSelection)
        if xp and xp > 0 then return xp end
    end

    return 0
end

local function IsQuestComplete(isComplete)
    return isComplete == 1 or isComplete == true
end

local function IsQuestLogEntryComplete(index, questID)
    -- Prefer the legacy API: it reliably reflects the same "Quest Complete!"
    -- state shown in the default quest log UI, on servers where the modern
    -- C_QuestLog API exists but doesn't populate isComplete.
    if GetQuestLogTitle then
        local _, _, _, _, _, _, isComplete = GetQuestLogTitle(index)
        if IsQuestComplete(isComplete) then return true end
    end

    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(index)
        if info and IsQuestComplete(info.isComplete) then return true end
    end

    if questID then
        if C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then
            return true
        end
        if _G.IsQuestComplete and _G.IsQuestComplete(questID) then
            return true
        end
    end

    return false
end

local function GetNumQuestLogEntriesCompat()
    if GetNumQuestLogEntries then return GetNumQuestLogEntries() end
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then return C_QuestLog.GetNumQuestLogEntries() end
    return 0
end

local function IsQuestLogHeader(index)
    if GetQuestLogTitle then
        local _, _, _, _, isHeader = GetQuestLogTitle(index)
        return isHeader
    end
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(index)
        return info and info.isHeader
    end
    return false
end

local function GetCompletedQuestXP()
    local total = 0
    local entryCount = GetNumQuestLogEntriesCompat()
    for index = 1, entryCount do
        if not IsQuestLogHeader(index) then
            local questID = GetQuestIDForIndex(index)
            if IsQuestLogEntryComplete(index, questID) then
                total = total + GetQuestRewardXP(index, questID)
            end
        end
    end
    return total
end

local function DebugQuestXP()
    print("|cff70d5ffMultiTool|r: quest XP debug")
    print("  C_QuestLog available: " .. tostring(C_QuestLog ~= nil))
    if C_QuestLog then
        print("  C_QuestLog.GetInfo: " .. tostring(C_QuestLog.GetInfo ~= nil))
        print("  C_QuestLog.GetQuestLogRewardXP: " .. tostring(C_QuestLog.GetQuestLogRewardXP ~= nil))
        print("  C_QuestLog.IsComplete: " .. tostring(C_QuestLog.IsComplete ~= nil))
    end
    print("  GetQuestLogTitle: " .. tostring(GetQuestLogTitle ~= nil))
    print("  GetQuestLogRewardXP: " .. tostring(GetQuestLogRewardXP ~= nil))
    print("  SelectQuestLogEntry: " .. tostring(SelectQuestLogEntry ~= nil))
    print("  IsQuestComplete (global): " .. tostring(_G.IsQuestComplete ~= nil))

    local entryCount = GetNumQuestLogEntriesCompat()
    print(string.format("  Quest log entries: %d", entryCount))

    for index = 1, entryCount do
        if not IsQuestLogHeader(index) then
            local title
            local legacyComplete
            if GetQuestLogTitle then
                title, _, _, _, _, _, legacyComplete = GetQuestLogTitle(index)
            end
            local questID = GetQuestIDForIndex(index)
            local modernComplete
            if C_QuestLog and C_QuestLog.GetInfo then
                local info = C_QuestLog.GetInfo(index)
                if info then
                    title = title or info.title
                    modernComplete = info.isComplete
                end
            end
            local resolvedComplete = IsQuestLogEntryComplete(index, questID)
            local xp = GetQuestRewardXP(index, questID)
            print(string.format(
                "  [%d] %s | legacyComplete=%s | modernComplete=%s | resolved=%s | questID=%s | xp=%s",
                index, tostring(title), tostring(legacyComplete), tostring(modernComplete),
                tostring(resolvedComplete), tostring(questID), tostring(xp)
            ))
        end
    end

    print(string.format("  Total completed quest XP: %s", tostring(GetCompletedQuestXP())))
end
NS.DebugQuestXP = DebugQuestXP

local function GetXPState()
    if not UnitXP or not UnitXPMax then return nil end
    local current = UnitXP("player") or 0
    local maximum = UnitXPMax("player") or 0
    if maximum <= 0 then return nil end
    return UnitLevel("player") or 1, current, maximum, (GetXPExhaustion and GetXPExhaustion()) or 0
end


local function FormatNumber(value)
    value = math.floor(tonumber(value) or 0)
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(value)
    end
    return tostring(value)
end

local function FormatElapsed(seconds)
    seconds = math.max(0, math.floor(seconds))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainder = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, remainder)
end

local function RecordXP(level, current, maximum)
    if previousLevel then
        local gained = 0
        if level == previousLevel and current >= previousXP then
            gained = current - previousXP
        elseif level > previousLevel then
            gained = math.max(0, previousXPMax - previousXP) + current
        end
        sessionXP = sessionXP + gained
    end
    previousLevel = level
    previousXP = current
    previousXPMax = maximum
end

local function ShowTooltip(level, current, maximum, rested, questXP)
    if not GameTooltip then return end
    local elapsed = GetTime() - sessionStartedAt
    local rate = elapsed > 0 and sessionXP * 3600 / elapsed or 0
    GameTooltip:SetOwner(frame, "ANCHOR_TOP")
    GameTooltip:SetText(NS.L.XP_SESSION_TITLE or "Session statistics")
    GameTooltip:AddLine(string.format(NS.L.XP_SESSION_GAINED or "XP gained: %s", FormatNumber(sessionXP)), 1, 1, 1)
    GameTooltip:AddLine(string.format(NS.L.XP_SESSION_RATE or "XP per hour: %s", FormatNumber(rate)), 1, 1, 1)
    GameTooltip:AddLine(string.format(NS.L.XP_SESSION_TIME or "Session: %s", FormatElapsed(elapsed)), 1, 1, 1)
    GameTooltip:AddLine(string.format(NS.L.XP_RESTED or "Rested XP: %s", FormatNumber(rested)), 0.45, 0.75, 1)
    GameTooltip:AddLine(string.format(NS.L.XP_PROGRESS or "Level %d | %s / %s XP | %s%%", level, FormatNumber(current), FormatNumber(maximum), string.format("%.1f", current / maximum * 100)), 0.8, 0.8, 0.8)
    if questXP > 0 then
        local projectedXP = current + questXP
        GameTooltip:AddLine(string.format(NS.L.XP_QUEST_PROJECTION or "Completed quest XP: %s", FormatNumber(questXP)), 1, 0.72, 0.1)
        GameTooltip:AddLine(string.format(NS.L.XP_AFTER_QUESTS or "After turn-in: %s / %s XP (%s%%)", FormatNumber(projectedXP), FormatNumber(maximum), string.format("%.1f", projectedXP / maximum * 100)), 1, 0.72, 0.1)
    end
    GameTooltip:AddLine(NS.L.XP_CLICK_HINT or "Click to reset session statistics.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function NS.RefreshXPBar()
    if not frame then return end
    local db = NS.GetDB and NS.GetDB()
    if not db or db.xpBarEnabled == false then
        frame:Hide()
        return
    end

    local level, current, maximum, rested = GetXPState()
    if not level then
        frame:Hide()
        return
    end

    RecordXP(level, current, maximum)
    local questXP = GetCompletedQuestXP()
    local projectedXP = current + questXP
    frame:SetSize(db.xpBarWidth or 800, db.xpBarHeight or 34)
    frame:SetMinMaxValues(0, maximum)
    frame:SetValue(current)
    frame.text:SetShown(db.xpBarShowText ~= false)

    local width = frame:GetWidth()
    local xpOffset = width * current / maximum
    local restedWidth = db.xpBarShowRested ~= false and width * math.min(rested, maximum - current) / maximum or 0
    frame.rested:ClearAllPoints()
    frame.rested:SetPoint("LEFT", frame, "LEFT", xpOffset, 0)
    frame.rested:SetSize(math.max(0, restedWidth), frame:GetHeight())
    frame.rested:SetShown(restedWidth > 0)
    -- The visible segment can't exceed the bar's own width (XP past the level
    -- cap would overflow into the next level), but the displayed number and
    -- percentage below are never clamped, so an over-100% projection is shown.
    local questProjectionWidth = width * math.min(questXP, maximum - current) / maximum
    frame.questProjection:ClearAllPoints()
    frame.questProjection:SetPoint("LEFT", frame, "LEFT", xpOffset, 0)
    frame.questProjection:SetSize(math.max(0, questProjectionWidth), frame:GetHeight())
    frame.questProjection:SetShown(questProjectionWidth > 0)
    local percent = current / maximum * 100
    local projectedPercent = projectedXP / maximum * 100
    frame.levelText:SetText(string.format(NS.L.XP_LEVEL or "Level %d", level))
    if questXP > 0 then
        frame.text:SetText(string.format(NS.L.XP_BAR_PROJECTION or "Projected: %s XP", FormatNumber(projectedXP)))
        frame.percentText:SetText(string.format("%.1f%%", projectedPercent))
    else
        frame.text:SetText(string.format("%s / %s XP", FormatNumber(current), FormatNumber(maximum)))
        frame.percentText:SetText(string.format("%.1f%%", percent))
    end
    frame.levelText:SetShown(db.xpBarShowText ~= false)
    frame.percentText:SetShown(db.xpBarShowText ~= false)
    frame:Show()
    if frame:IsMouseOver() then
        ShowTooltip(level, current, maximum, rested, questXP)
    end
end

local function ResetSession()
    sessionXP = 0
    sessionStartedAt = GetTime()
    local level, current, maximum = GetXPState()
    previousLevel = level
    previousXP = current
    previousXPMax = maximum
    NS.RefreshXPBar()
    print("|cff70d5ffMultiTool|r: " .. (NS.L.XP_RESET or "XP session statistics reset."))
end

function NS.CreateXPBar()
    if frame then return frame end
    local db = NS.GetDB and NS.GetDB() or {}
    sessionStartedAt = GetTime()

    frame = CreateFrame("StatusBar", "MultiToolXPBar", UIParent, "BackdropTemplate")
    frame:SetSize(db.xpBarWidth or 800, db.xpBarHeight or 34)
    frame:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame:SetStatusBarColor(0.48, 0.22, 0.82, 1)
    frame:SetMinMaxValues(0, 1)
    frame:SetValue(0)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)

    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints(frame)
    frame.background:SetColorTexture(0.025, 0.035, 0.055, 0.96)

    frame.rested = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    frame.rested:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.rested:SetVertexColor(0.3, 0.62, 1, 0.7)

    frame.questProjection = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    frame.questProjection:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.questProjection:SetVertexColor(1, 0.72, 0.1, 0.95)
    frame.questProjection:Hide()

    frame.border = {}
    for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local texture = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        texture:SetColorTexture(0.42, 0.48, 0.6, 0.9)
        frame.border[edge] = texture
    end
    frame.border.TOP:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.border.TOP:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.border.TOP:SetHeight(1)
    frame.border.BOTTOM:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    frame.border.BOTTOM:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.border.BOTTOM:SetHeight(1)
    frame.border.LEFT:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.border.LEFT:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    frame.border.LEFT:SetWidth(1)
    frame.border.RIGHT:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.border.RIGHT:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.border.RIGHT:SetWidth(1)

    frame.highlight = frame:CreateTexture(nil, "OVERLAY", nil, 6)
    frame.highlight:SetColorTexture(1, 1, 1, 0.12)
    frame.highlight:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    frame.highlight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    frame.highlight:SetHeight(1)

    frame.levelText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.levelText:SetPoint("LEFT", frame, "LEFT", 8, 0)
    frame.levelText:SetJustifyH("LEFT")
    frame.levelText:SetTextColor(1, 1, 1)

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.text:SetPoint("CENTER", frame, "CENTER")
    frame.text:SetJustifyH("CENTER")
    frame.text:SetTextColor(1, 1, 1)

    frame.percentText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.percentText:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    frame.percentText:SetJustifyH("RIGHT")
    frame.percentText:SetTextColor(1, 1, 1)

    local function SavePosition(self)
        local point, _, relativePoint, x, y = self:GetPoint(1)
        db.xpBarPoint = { point or "CENTER", relativePoint or point or "CENTER", x or 0, y or 0 }
    end

    frame:SetScript("OnMouseDown", function(self, button)
        self.xpPressedButton = button
        if button == "LeftButton" then
            self.xpDraggedDuringPress = false
        end
    end)
    frame:SetScript("OnDragStart", function(self)
        local currentDB = NS.GetDB and NS.GetDB()
        if self.xpPressedButton == "LeftButton" and currentDB and currentDB.xpBarLocked == false then
            self.xpDragging = true
            self.xpDraggedDuringPress = true
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        if not self.xpDragging then return end
        self:StopMovingOrSizing()
        self.xpDragging = false
        SavePosition(self)
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if self.xpDragging then
            self:StopMovingOrSizing()
            self.xpDragging = false
            SavePosition(self)
        end
        if self.xpDraggedDuringPress then
            self.xpDraggedDuringPress = false
            self.xpPressedButton = nil
            return
        end
        self.xpPressedButton = nil
        ResetSession()
    end)
    frame:SetScript("OnEnter", function()
        local level, current, maximum, rested = GetXPState()
        if level then ShowTooltip(level, current, maximum, rested, GetCompletedQuestXP()) end
    end)
    frame:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local point = db.xpBarPoint
    if type(point) == "table" then
        frame:SetPoint(point[1] or "CENTER", UIParent, point[2] or point[1] or "CENTER", point[3] or 0, point[4] or 0)
    else
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180)
    end

    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 1 then
            elapsed = 0
            NS.RefreshXPBar()
        end
    end)
    frame:RegisterEvent("PLAYER_XP_UPDATE")
    frame:RegisterEvent("PLAYER_LEVEL_UP")
    frame:RegisterEvent("UPDATE_EXHAUSTION")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("QUEST_LOG_UPDATE")
    frame:SetScript("OnEvent", NS.RefreshXPBar)

    NS.XPBar = frame
    NS.RefreshXPBar()
    return frame
end

function NS.RegisterXPOptions(category)
    if not category or not Settings or NS.XPSettingsRegistered then return end
    NS.XPSettingsRegistered = true
    local db = NS.GetDB and NS.GetDB() or {}

    local function AddCheckbox(settingName, key, defaultValue, labelKey)
        if not Settings.RegisterAddOnSetting or not Settings.CreateCheckbox then return end
        local setting = Settings.RegisterAddOnSetting(
            category,
            ADDON .. "_" .. settingName,
            key,
            db,
            "boolean",
            NS.L[labelKey] or labelKey,
            defaultValue
        )
        if setting then
            if setting.SetValueChangedCallback then
                setting:SetValueChangedCallback(function(_, value)
                    db[key] = value == true
                    NS.RefreshXPBar()
                end)
            end
            Settings.CreateCheckbox(category, setting, NS.L[labelKey] or labelKey)
        end
    end

    local function AddSlider(settingName, key, minimum, maximum, step, labelKey, defaultValue)
        if not Settings.RegisterAddOnSetting or not Settings.CreateSlider then return end
        local setting = Settings.RegisterAddOnSetting(
            category,
            ADDON .. "_" .. settingName,
            key,
            db,
            "number",
            NS.L[labelKey] or labelKey,
            defaultValue
        )
        if setting then
            Settings.CreateSlider(category, setting, {
                minValue = minimum,
                maxValue = maximum,
                steps = math.floor((maximum - minimum) / step),
            })
            if setting.SetValueChangedCallback then
                setting:SetValueChangedCallback(function(_, value)
                    local newValue = tonumber(value)
                    if not newValue then return end
                    db[key] = math.max(minimum, math.min(maximum, newValue))
                    NS.RefreshXPBar()
                end)
            end
        end
    end

    AddCheckbox("xpBarEnabled", "xpBarEnabled", true, "XP_ENABLE")
    AddSlider("xpBarWidth", "xpBarWidth", 240, 1400, 40, "XP_WIDTH", db.xpBarWidth or 800)
    AddSlider("xpBarHeight", "xpBarHeight", 14, 48, 2, "XP_HEIGHT", db.xpBarHeight or 34)
    AddCheckbox("xpBarShowText", "xpBarShowText", true, "XP_SHOW_TEXT")
    AddCheckbox("xpBarShowRested", "xpBarShowRested", true, "XP_SHOW_RESTED")
    AddCheckbox("xpBarLocked", "xpBarLocked", false, "XP_LOCKED")
end
