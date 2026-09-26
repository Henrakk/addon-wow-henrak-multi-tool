local ADDON = "HenrakMultiTool"
local NS = _G[ADDON] or {}
_G[ADDON] = NS

local icons = {}
local sealIcons = {}
local lastPaladinAuraPresent = false

local function UpdateManaBar()
    if not NS.ManaFrame or not NS.GetPlayerClassKey then return end
    local db = NS.GetDB and NS.GetDB()
    if not db or db.enabled == false then
        NS.ManaFrame:Hide()
        return
    end
    local isDruid = NS.GetPlayerClassKey() == "DRUID"
    if not isDruid then
        NS.ManaFrame:Hide()
        return
    end

    local current = UnitPower and UnitPower("player", 0) or 0
    local maximum = UnitPowerMax and UnitPowerMax("player", 0) or 0
    NS.ManaFrame:SetMinMaxValues(0, math.max(1, maximum))
    NS.ManaFrame:SetValue(current)
    NS.ManaFrame.value:SetText(string.format("%d / %d", current, maximum))
    NS.ManaFrame:Show()
end

local function Rebuild()
    if not NS.Frame or not NS.SealFrame or not NS.GetDB then return end
    local db = NS.GetDB()
    if not db then return end

    for _, b in pairs(icons) do
        b:Hide()
    end
    for _, b in pairs(sealIcons) do
        b:Hide()
    end

    local active = NS.GetActiveBuffs and NS.GetActiveBuffs() or {}
    local sealActive = NS.GetSealDisplayBuffs and NS.GetSealDisplayBuffs() or {}
    local sealSize = tonumber(db.sealIconSize) or db.iconSize
    local missingTextSize = tonumber(db.missingTextSize) or NS.DEFAULT_MISSING_TEXT_SIZE
    local timerTextSize = tonumber(db.timerTextSize) or NS.DEFAULT_TIMER_TEXT_SIZE
    local width = math.max(180, #active * (db.iconSize + NS.SPACING) + 16, #sealActive * (sealSize + NS.SPACING) + 16)
    local rowHeight = math.max(db.iconSize, sealSize) + (db.showMissingText and math.max(34, missingTextSize + 22) or 18)
    NS.Frame:SetSize(math.max(180, #active * (db.iconSize + NS.SPACING) + 16), rowHeight)
    NS.Frame.baseHeight = rowHeight
    if NS.Frame.status then
        local statusFont, _, statusFlags = NS.Frame.status:GetFont()
        NS.Frame.status:SetFont(statusFont, missingTextSize, statusFlags)
        NS.Frame.status:SetHeight(missingTextSize + 4)
        NS.Frame.status:SetWidth(NS.Frame:GetWidth() - 16)
        NS.Frame.status:ClearAllPoints()
        NS.Frame.status:SetPoint("TOP", NS.Frame, "TOP", 0, -rowHeight - 4)
    end
    NS.SealFrame:SetSize(math.max(180, #sealActive * (sealSize + NS.SPACING) + 16), rowHeight)
    NS.SealFrame:SetShown(#sealActive > 0)

    local function BuildGroup(buffList, iconList, size, yOffset)
        for i, buff in ipairs(buffList) do
            local parent = buff.isSeal and NS.SealFrame or NS.Frame
            local b = iconList[i] or NS.CreateBuffIcon(parent, i)
            b:SetSize(size, size)
            b.timer:SetWidth(size)
            local timerFont, _, timerFlags = b.timer:GetFont()
            b.timer:SetFont(timerFont, timerTextSize, timerFlags)
            local missingFont, _, missingFlags = b.missing:GetFont()
            b.missing:SetFont(missingFont, missingTextSize, missingFlags)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", parent, "TOPLEFT", 8 + (i - 1) * (size + NS.SPACING), yOffset)
            b:EnableMouse(true)
            b:EnableMouseWheel(false)
            b:Show()
            b.buff = buff
            b.lastPresent = b.lastPresent == true
            local spellID = buff.activeSpellID or NS.GetKnownSpellID(buff) or (buff.spellIDs and buff.spellIDs[1])
            b.icon:SetTexture(NS.SpellTexture(spellID))
            if not InCombatLockdown() then
                if spellID and not buff.isMissingSeal then
                    b:SetAttribute("type", "spell")
                    b:SetAttribute("spell", spellID)
                else
                    b:SetAttribute("type", nil)
                    b:SetAttribute("spell", nil)
                end
            end
            iconList[i] = b
        end
    end

    BuildGroup(active, icons, db.iconSize, -22)
    if #sealActive > 0 then
        BuildGroup(sealActive, sealIcons, sealSize, -22)
    end

    for i = #active + 1, #icons do
        icons[i]:Hide()
    end
    for i = #sealActive + 1, #sealIcons do
        sealIcons[i]:Hide()
    end
end

local function Update()
    if not NS.Frame or not NS.SealFrame or not NS.GetDB then return end
    local db = NS.GetDB()
    if not db then return end
    if not db.enabled then
        NS.Frame:Hide()
        NS.SealFrame:Hide()
        return
    end

    NS.Frame:Show()
    if NS.GetActiveClass() == "PALADIN" and not InCombatLockdown() then
        lastPaladinAuraPresent = false
        for _, aura in ipairs(NS.PaladinAuras or {}) do
            if NS.HasBuff(aura) then
                lastPaladinAuraPresent = true
                break
            end
        end
    end
    if NS.Frame.status then
        if db.showMissingText and NS.GetActiveClass() == "PALADIN" and not lastPaladinAuraPresent then
            NS.Frame.status:SetText(NS.L.AURA_MISSING or "No aura")
            NS.Frame.status:Show()
            NS.Frame:SetHeight((NS.Frame.baseHeight or NS.Frame:GetHeight()) + (tonumber(db.missingTextSize) or NS.DEFAULT_MISSING_TEXT_SIZE) + 8)
        else
            NS.Frame.status:Hide()
            NS.Frame:SetHeight(NS.Frame.baseHeight or NS.Frame:GetHeight())
        end
    end
    local function UpdateGroup(iconList)
    local groupPresent = {}
    local groupAlertShown = {}
    local groupLabelKeys = {
        blessing = "BLESSING_MISSING",
        aura = "AURA_MISSING",
    }
    for _, b in ipairs(iconList) do
        if b:IsShown() and b.buff and b.buff.groupKey then
            local present
            if InCombatLockdown() then
                present = b.lastPresent
            else
                present = NS.HasBuff(b.buff)
            end
            if present then groupPresent[b.buff.groupKey] = true end
        end
    end
    for i, b in ipairs(iconList) do
        if b:IsShown() and b.buff then
            local present, aura
            if not InCombatLockdown() then
                present, aura = NS.HasBuff(b.buff)
                b.lastPresent = present == true
                b.lastAura = aura
                b.lastRemaining = nil
                if aura and aura.expirationTime then
                    local expirationTime = aura.expirationTime
                    if not canaccessvalue or canaccessvalue(expirationTime) then
                        local remaining = expirationTime - GetTime()
                        if remaining > 0 and remaining < 3600 then
                            b.lastRemaining = remaining
                            b.lastRemainingAt = GetTime()
                        end
                    end
                end
            else
                present = b.lastPresent
                aura = b.lastAura
                if b.lastRemaining and b.lastRemainingAt then
                    b.lastRemaining = b.lastRemaining - (GetTime() - b.lastRemainingAt)
                    b.lastRemainingAt = GetTime()
                end
            end
            if present then
                b:SetAlpha(1)
                b.icon:SetDesaturated(false)
                b.missing:Hide()
                if b.lastRemaining and b.lastRemaining > 0 then
                    local remaining = b.lastRemaining
                    if remaining > 0 and remaining < 3600 then
                        if remaining > 60 then
                            local minutes = math.floor(remaining / 60)
                            local seconds = math.floor(remaining % 60)
                            b.timer:SetText(string.format("%dm %ds", minutes, seconds))
                        else
                            b.timer:SetText(string.format("%ds", math.floor(remaining + 0.5)))
                        end
                        b.timer:Show()
                    else
                        b.timer:Hide()
                    end
                else
                    b.timer:Hide()
                end
            else
                b:SetAlpha(0.45)
                b.icon:SetDesaturated(true)
                b.timer:Hide()
                if db.showMissingText or b.buff.isMissingSeal then
                    local label = NS.L[b.buff.labelKey] or NS.SpellName(b.buff.spellIDs[1])
                    if b.buff.groupKey then
                        local groupKey = b.buff.groupKey
                        if groupPresent[groupKey] or groupAlertShown[groupKey] then
                            b.missing:Hide()
                        else
                            b.missing:SetText(NS.L[groupLabelKeys[groupKey]] or label)
                            b.missing:Show()
                            groupAlertShown[groupKey] = true
                        end
                    elseif b.buff.isMissingSeal then
                        b.missing:SetText(label)
                    else
                        b.missing:SetText(label .. " " .. (NS.L.MISSING or "missing"))
                    end
                    if not b.buff.groupKey then b.missing:Show() end
                else
                    b.missing:Hide()
                end
            end
        end
    end
    end
    UpdateGroup(icons)
    UpdateGroup(sealIcons)
end

function NS.Refresh()
    if NS.GetDB then
        local db = NS.GetDB()
        if db and db.activeClass then
            NS.GetActiveClass()
        end
    end
    Rebuild()
    if NS.RestorePosition then
        NS.RestorePosition()
    end
    Update()
    UpdateManaBar()
end

function NS.CreateTrackerFrame()
    local frame = CreateFrame("Frame", "HenrakMultiToolFrame", UIParent, "BackdropTemplate")
    frame:SetSize(360, 70)
    frame:SetPoint("CENTER", 0, -180)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:EnableMouseWheel(true)

    local function StartDrag(self)
        local db = NS.GetDB and NS.GetDB() or {}
        if not db.locked then
            self:StartMoving()
        end
    end

    local function SavePosition(self, key)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        if not point then return end
        local className = NS.GetActiveClass and NS.GetActiveClass() or NS.GetPlayerClassKey()
        local profile = NS.GetClassProfile and NS.GetClassProfile(className)
        if profile then
            local db = NS.GetDB()
            db.positions = db.positions or {}
            db.positions[className] = db.positions[className] or {}
            db.positions[className][key] = { point, relativePoint or point, x or 0, y or 0 }
            profile[key] = db.positions[className][key]
        end
    end

    frame:SetScript("OnDragStart", StartDrag)
    frame:SetScript("OnDragStop", function(self)
        SavePosition(self, "point")
    end)

    frame:SetScript("OnMouseWheel", function(_, delta)
        if not (NS.GetDB and NS.GetDB().locked) then
            local db = NS.GetDB()
            NS.SetIconSize((tonumber(db.iconSize) or NS.DEFAULT_ICON_SIZE) + (delta > 0 and 4 or -4))
        end
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("HenrakMultiTool")

    frame.title = title
    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetJustifyH("CENTER")
    status:SetTextColor(1, 0.25, 0.25)
    status:SetHeight(16)
    status:Hide()
    frame.status = status
    NS.Frame = frame

    local sealFrame = CreateFrame("Frame", "HenrakMultiToolSealFrame", UIParent, "BackdropTemplate")
    sealFrame:SetSize(180, 70)
    sealFrame:SetPoint("CENTER", 0, -280)
    sealFrame:SetMovable(true)
    sealFrame:EnableMouse(true)
    sealFrame:SetClampedToScreen(true)
    sealFrame:RegisterForDrag("LeftButton")
    sealFrame:EnableMouseWheel(true)
    sealFrame:SetScript("OnDragStart", StartDrag)
    sealFrame:SetScript("OnDragStop", function(self)
        SavePosition(self, "sealPoint")
    end)
    sealFrame:SetScript("OnMouseWheel", function(_, delta)
        if not (NS.GetDB and NS.GetDB().locked) then
            local db = NS.GetDB()
            NS.SetSealIconSize((tonumber(db.sealIconSize) or NS.DEFAULT_ICON_SIZE) + (delta > 0 and 4 or -4))
        end
    end)
    local sealTitle = sealFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sealTitle:SetPoint("TOPLEFT", 8, -6)
    sealTitle:SetText(NS.L.SEALS or "Seals")
    sealFrame.title = sealTitle
    NS.SealFrame = sealFrame

    local manaFrame = CreateFrame("StatusBar", "HenrakMultiToolManaFrame", UIParent, "BackdropTemplate")
    manaFrame:SetSize(180, 20)
    manaFrame:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    manaFrame:SetStatusBarColor(0.15, 0.45, 0.95, 1)
    manaFrame:SetMinMaxValues(0, 1)
    manaFrame:SetValue(0)
    manaFrame:SetMovable(true)
    manaFrame:EnableMouse(true)
    manaFrame:SetClampedToScreen(true)
    manaFrame:RegisterForDrag("LeftButton")
    manaFrame:SetScript("OnDragStart", StartDrag)
    manaFrame:SetScript("OnDragStop", function(self)
        SavePosition(self, "manaPoint")
    end)
    local manaTitle = manaFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    manaTitle:SetPoint("BOTTOM", manaFrame, "TOP", 0, 2)
    manaTitle:SetText(NS.L.MANA or "Mana")
    manaFrame.title = manaTitle
    local manaValue = manaFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    manaValue:SetPoint("CENTER")
    manaFrame.value = manaValue
    NS.ManaFrame = manaFrame

    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            elapsed = 0
            Update()
        end
    end)

    frame:RegisterEvent("UNIT_AURA")
    frame:RegisterEvent("UNIT_POWER_UPDATE")
    frame:RegisterEvent("UNIT_MAXPOWER")
    frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    frame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
            if unit == "player" then UpdateManaBar() end
        elseif event == "UNIT_AURA" and unit == "player" then
            if not InCombatLockdown() then
                Rebuild()
            end
            Update()
            UpdateManaBar()
        elseif event == "UNIT_INVENTORY_CHANGED" and unit == "player" then
            if NS.Refresh then NS.Refresh() end
        end
    end)

    return frame
end

function NS.RestorePosition()
    if not NS.Frame or not NS.SealFrame or not NS.ManaFrame or not NS.GetDB then return end
    local db = NS.GetDB()
    if not db then return end
    local className = NS.GetActiveClass and NS.GetActiveClass() or NS.GetPlayerClassKey()
    local profile = NS.GetClassProfile and NS.GetClassProfile(className)
    local positions = db.positions and db.positions[className]
    local point = positions and positions.point or profile and profile.point or db.point
    local sealPoint = positions and positions.sealPoint or profile and profile.sealPoint
    local manaPoint = positions and positions.manaPoint or profile and profile.manaPoint

    local function RestoreFramePosition(frame, saved, defaultY)
        frame:ClearAllPoints()
        if type(saved) == "table" then
            if type(saved[1]) == "string" then
                frame:SetPoint(saved[1], UIParent, saved[2] or saved[1], saved[3] or 0, saved[4] or 0)
            else
                frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", saved[1] or 0, saved[2] or 0)
            end
        else
            frame:SetPoint("CENTER", 0, defaultY)
        end
    end

    RestoreFramePosition(NS.Frame, point, -180)
    RestoreFramePosition(NS.SealFrame, sealPoint, -280)
    NS.ManaFrame:ClearAllPoints()
    if manaPoint then
        if type(manaPoint[1]) == "string" then
            NS.ManaFrame:SetPoint(manaPoint[1], UIParent, manaPoint[2] or manaPoint[1], manaPoint[3] or 0, manaPoint[4] or 0)
        else
            NS.ManaFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", manaPoint[1] or 0, manaPoint[2] or 0)
        end
    elseif PlayerFrame then
        NS.ManaFrame:SetPoint("TOP", PlayerFrame, "BOTTOM", 0, -8)
    else
        NS.ManaFrame:SetPoint("CENTER", 0, -340)
    end
end
