local ADDON = "MultiTool"
local NS = _G[ADDON] or {}
_G[ADDON] = NS

local icons = {}
local sealIcons = {}
local lastPaladinAuraPresent = false
local refreshPending = false
local warningFlashOn = false
local warningFlashElapsed = 0
local sealState = { active = false }

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

local function UpdateBagSlots()
    local button = NS.BagSlotsButton
    if not button or not NS.GetDB then return end
    local db = NS.GetDB()
    if not db or not db.enabled or db.showBagSlots == false then
        button:Hide()
        return
    end

    local container = C_Container
    local getNumSlots = container and container.GetContainerNumSlots or GetContainerNumSlots
    local getNumFreeSlots = container and container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if not getNumSlots or not getNumFreeSlots then return end

    local totalSlots = 0
    local freeSlots = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        totalSlots = totalSlots + (getNumSlots(bag) or 0)
        freeSlots = freeSlots + (getNumFreeSlots(bag) or 0)
    end

    button:SetText(string.format(NS.L.BAG_SLOTS_BUTTON or "%d free slots", freeSlots))
    button:Show()
    button.freeSlots = freeSlots
    button.totalSlots = totalSlots
end

local function UpdateExpiryAlert(inCombat)
    local warning = NS.ExpiryWarning
    if not warning then return end

    local db = NS.GetDB and NS.GetDB()
    if not db or db.enabled == false then
        warning:Hide()
        return
    end

    local now = GetTime()
    local lines = {}
    local function CheckGroup(iconList)
        for _, button in ipairs(iconList) do
            local remaining
            if button:IsShown() and button.buff and button.lastPresent
                and button.lastDuration and button.lastRemaining and button.lastRemainingAt then
                remaining = button.lastRemaining - (now - button.lastRemainingAt)
            end

            local expiring = remaining and remaining > 0
                and remaining <= button.lastDuration * 0.05
            if expiring then
                local label = NS.L[button.buff.labelKey] or button.buff.key or "Buff"
                table.insert(lines, string.format(
                    NS.L.BUFF_EXPIRING_LINE or "%s (%ds)",
                    label,
                    math.max(1, math.ceil(remaining))
                ))
            end

            if button.timer and not (button.buff and button.buff.isSeal)
                and remaining and remaining > 0 and remaining < 3600 then
                if inCombat then
                    if remaining > 60 then
                        button.timer:SetText(string.format("%dm %ds", math.floor(remaining / 60), math.floor(remaining % 60)))
                    else
                        button.timer:SetText(string.format("%ds", math.floor(remaining + 0.5)))
                    end
                    button.timer:Show()
                end
            end

            if button.glow then
                if button.buff and button.buff.isSeal and expiring then
                    button.glow:SetAlpha(warningFlashOn and 1 or 0.25)
                    button.glow:Show()
                    if button.timer then
                        if warningFlashOn then
                            button.timer:SetTextColor(1, 0.08, 0.08)
                        else
                            button.timer:SetTextColor(1, 1, 1)
                        end
                    end
                else
                    button.glow:Hide()
                    if button.buff and button.buff.isSeal and button.timer then
                        button.timer:SetTextColor(1, 1, 1)
                    end
                end
            end
        end
    end

    CheckGroup(icons)
    CheckGroup(sealIcons)

    if #lines == 0 then
        warning:Hide()
        return
    end

    warning.text:SetText((NS.L.BUFF_EXPIRING_HEADER or "BUFF EXPIRING") .. "\n" .. table.concat(lines, "\n"))
    warning:SetAlpha(warningFlashOn and 1 or 0.3)
    warning:Show()
end

local function GetSealDurationAndExpiration(aura)
    if not aura then return nil, nil end

    local duration = aura.duration
    local expirationTime = aura.expirationTime
    if not duration or not expirationTime then return nil, nil end
    return duration, expirationTime
end

local function FormatRemaining(remaining)
    local secondsLeft = math.max(1, math.floor(remaining))
    if secondsLeft >= 60 then
        return string.format("%dm %ds", math.floor(secondsLeft / 60), secondsLeft % 60)
    end
    return string.format("%ds", secondsLeft)
end

local function RenderSealStatus()
    if not NS.SealFrame then return end

    local now = GetTime()
    local remaining = sealState.expiresAt and sealState.expiresAt - now
    if remaining and remaining <= 0 then
        sealState.active = false
        sealState.key = nil
        sealState.expiresAt = nil
        remaining = nil
    end

    if NS.SealFrame.title then
        NS.SealFrame.title:SetText(sealState.active and remaining and FormatRemaining(remaining) or "")
    end

    local firstShownButton
    local matchingButton
    for _, button in ipairs(sealIcons) do
        if button:IsShown() and button.buff and button.buff.isSeal then
            firstShownButton = firstShownButton or button
            if sealState.active
                and (button.buff.key == sealState.key or button.buff.isMissingSeal) then
                matchingButton = button
                break
            end
        end
    end
    local timerButton = matchingButton or firstShownButton

    for _, button in ipairs(sealIcons) do
        if button:IsShown() and button.buff and button.buff.isSeal then
            local isActive = sealState.active
                and (button == timerButton or button.buff.key == sealState.key or button.buff.isMissingSeal)
            button.lastPresent = isActive
            button.lastDuration = sealState.duration
            button.lastRemaining = isActive and remaining or nil
            button.lastRemainingAt = now

            if isActive then
                button:SetAlpha(1)
                button.icon:SetDesaturated(false)
                button.missing:Hide()
                if remaining and button.timer then
                    button.timer:SetText(FormatRemaining(remaining))
                    button.timer:Show()
                elseif button.timer then
                    button.timer:Hide()
                end
            else
                button:SetAlpha(0.45)
                button.icon:SetDesaturated(true)
                if button.timer then button.timer:Hide() end
                button.missing:Hide()
            end
        end
    end
end

local function UpdateSealStatus()
    if not NS.GetSealBuffs then return end

    local inCombat = InCombatLockdown and InCombatLockdown()
    local activeSeal, activeAura
    for _, seal in ipairs(NS.GetSealBuffs()) do
        local present, aura = NS.HasBuff(seal)
        if present then
            activeSeal = seal
            activeAura = aura
            break
        end
    end

    if activeSeal then
        if sealState.key ~= activeSeal.key then
            sealState.duration = nil
            sealState.expiresAt = nil
        end
        sealState.active = true
        sealState.key = activeSeal.key
        local duration, expirationTime = GetSealDurationAndExpiration(activeAura)
        if expirationTime and expirationTime > GetTime() then
            -- Always trust the live aura data: a fresh cast/recast always
            -- produces a new expiration further in the future, so there is
            -- no need to compare against previously stored values before
            -- accepting it. This guarantees the countdown resumes from the
            -- full duration as soon as the server confirms the refresh.
            sealState.duration = duration and duration > 0 and duration or sealState.duration
            sealState.expiresAt = expirationTime
        elseif not sealState.expiresAt then
            sealState.duration = sealState.duration or 30
            sealState.expiresAt = GetTime() + sealState.duration
        end
    elseif not inCombat or not sealState.expiresAt or sealState.expiresAt <= GetTime() then
        sealState.active = false
        sealState.key = nil
        sealState.duration = nil
        sealState.expiresAt = nil
    end

    RenderSealStatus()
end

local function ResetSealTimerAfterCast(...)
    local castValues = {...}
    if #castValues == 0 then return end

    for _, seal in ipairs(NS.GetSealBuffs and NS.GetSealBuffs() or {}) do
        -- Match on the seal's own localized name rather than raw numeric
        -- spell IDs: IDs can be unreliable to compare across servers
        -- (this server may not use the same spell ID layout as retail),
        -- which was causing unrelated casts like Judgement or Exorcism to
        -- be misidentified as a seal cast and wrongly restart the
        -- countdown. The localized name is the same identity already used
        -- (and proven reliable) for buff detection in NS.HasBuff.
        local sealLabel = seal.labelKey and NS.L[seal.labelKey]
        local matchesSpell = false
        if sealLabel then
            for _, castValue in ipairs(castValues) do
                local castSpellID = tonumber(castValue)
                local castName = castSpellID and NS.SpellName and NS.SpellName(castSpellID)
                    or (type(castValue) == "string" and castValue or nil)
                if castName == sealLabel then
                    matchesSpell = true
                    break
                end
            end
        end
        if matchesSpell then
            -- A successful cast (even of the same seal already active)
            -- always restarts the countdown from the full duration right
            -- away; UpdateSealStatus will then reconcile it with the real
            -- aura expiration as soon as that data is available.
            local now = GetTime()
            sealState.active = true
            sealState.key = seal.key
            sealState.duration = 30
            sealState.expiresAt = now + sealState.duration
            RenderSealStatus()
            UpdateExpiryAlert(true)
            return
        end
    end
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

    local function BuildGroup(buffList, iconList, size, yOffset, positionKey)
        for i, buff in ipairs(buffList) do
            local parent = buff.isSeal and NS.SealFrame or NS.Frame
            local b = iconList[i] or NS.CreateBuffIcon(parent, i)
            b:SetSize(size, size)
            if b.glow then b.glow:SetSize(size * 1.65, size * 1.65) end
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

    BuildGroup(active, icons, db.iconSize, -6, "point")
    if #sealActive > 0 then
        BuildGroup(sealActive, sealIcons, sealSize, -22, "sealPoint")
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
        if NS.ExpiryWarning then NS.ExpiryWarning:Hide() end
        return
    end
    UpdateSealStatus()
    if InCombatLockdown and InCombatLockdown() then
        refreshPending = true
        UpdateExpiryAlert(true)
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
                b.lastDuration = nil
                b.lastRemainingAt = nil
                if present and aura then
                    local duration = aura.duration
                    local expirationTime = aura.expirationTime
                    local readable = duration and expirationTime
                        and (not canaccessvalue or (canaccessvalue(duration) and canaccessvalue(expirationTime)))
                    if readable then
                        if duration > 0 then b.lastDuration = duration end
                        local remaining = expirationTime - GetTime()
                        if remaining > 0 then
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
                if db.showMissingText and not b.buff.isSeal then
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
    UpdateExpiryAlert(false)
end

function NS.Refresh()
    if InCombatLockdown and InCombatLockdown() then
        refreshPending = true
        UpdateManaBar()
        UpdateBagSlots()
        return
    end
    refreshPending = false
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
    UpdateBagSlots()
end

function NS.CreateTrackerFrame()
    local frame = CreateFrame("Frame", "MultiToolFrame", UIParent, "BackdropTemplate")
    frame:SetSize(360, 70)
    frame:SetPoint("CENTER", 0, -180)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
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

    frame.SavePosition = SavePosition

    local function CreateMoveHandle(movableFrame, positionKey)
        local handle = CreateFrame("Button", nil, movableFrame, "BackdropTemplate")
        handle:SetSize(16, 16)
        handle:SetPoint("BOTTOM", movableFrame, "TOP", 0, 2)
        handle:SetFrameLevel(movableFrame:GetFrameLevel() + 10)
        handle:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        handle:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
        handle:SetBackdropBorderColor(0.75, 0.75, 0.75, 1)
        local function StopHandleMove()
            if not handle.isMoving then return end
            handle.isMoving = nil
            movableFrame:StopMovingOrSizing()
            movableFrame:SavePosition(positionKey)
        end
        handle:SetScript("OnMouseDown", function(_, mouseButton)
            if mouseButton ~= "LeftButton" then return end
            local currentDB = NS.GetDB and NS.GetDB()
            if currentDB and not currentDB.locked and not InCombatLockdown() then
                handle.isMoving = true
                movableFrame:StartMoving()
            end
        end)
        handle:SetScript("OnMouseUp", function(_, mouseButton)
            if mouseButton == "LeftButton" then StopHandleMove() end
        end)
        handle:SetScript("OnUpdate", function()
            if handle.isMoving and not IsMouseButtonDown("LeftButton") then
                StopHandleMove()
            end
        end)
        handle:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(0.3, 0.8, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(NS.L.MOVE_HANDLE_TOOLTIP or "Drag to move")
            GameTooltip:Show()
        end)
        handle:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.75, 0.75, 0.75, 1)
            GameTooltip:Hide()
        end)
        movableFrame.moveHandle = handle
        handle:Hide()
    end

    CreateMoveHandle(frame, "point")

    frame:SetScript("OnMouseWheel", function(_, delta)
        if not (NS.GetDB and NS.GetDB().locked) then
            local db = NS.GetDB()
            NS.SetIconSize((tonumber(db.iconSize) or NS.DEFAULT_ICON_SIZE) + (delta > 0 and 4 or -4))
        end
    end)

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetJustifyH("CENTER")
    status:SetTextColor(1, 0.25, 0.25)
    status:SetHeight(16)
    status:Hide()
    frame.status = status
    NS.Frame = frame

    local sealFrame = CreateFrame("Frame", "MultiToolSealFrame", UIParent, "BackdropTemplate")
    sealFrame:SetSize(180, 70)
    sealFrame:SetPoint("CENTER", 0, -280)
    sealFrame:SetMovable(true)
    sealFrame:EnableMouse(true)
    sealFrame:SetClampedToScreen(true)
    sealFrame:EnableMouseWheel(true)
    sealFrame:SetScript("OnMouseWheel", function(_, delta)
        if not (NS.GetDB and NS.GetDB().locked) then
            local db = NS.GetDB()
            NS.SetSealIconSize((tonumber(db.sealIconSize) or NS.DEFAULT_ICON_SIZE) + (delta > 0 and 4 or -4))
        end
    end)
    local sealTimer = sealFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sealTimer:SetPoint("TOPLEFT", sealFrame, "TOPLEFT", 8, -6)
    sealTimer:SetWidth(tonumber(NS.GetDB().sealIconSize) or NS.DEFAULT_ICON_SIZE)
    sealTimer:SetJustifyH("LEFT")
    sealTimer:SetTextColor(1, 1, 1)
    sealFrame.title = sealTimer
    sealFrame.SavePosition = SavePosition
    CreateMoveHandle(sealFrame, "sealPoint")
    NS.SealFrame = sealFrame

    local manaFrame = CreateFrame("StatusBar", "MultiToolManaFrame", UIParent, "BackdropTemplate")
    manaFrame:SetSize(180, 20)
    manaFrame.background = manaFrame:CreateTexture(nil, "BACKGROUND")
    manaFrame.background:SetAllPoints(manaFrame)
    manaFrame.background:SetColorTexture(0.08, 0.08, 0.08, 0.9)
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

    local expiryWarning = CreateFrame("Frame", "MultiToolExpiryWarning", UIParent)
    expiryWarning:SetSize(1000, 180)
    expiryWarning:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    expiryWarning:SetFrameStrata("HIGH")
    local expiryText = expiryWarning:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    expiryText:SetPoint("CENTER")
    expiryText:SetWidth(960)
    expiryText:SetHeight(170)
    expiryText:SetJustifyH("CENTER")
    expiryText:SetJustifyV("MIDDLE")
    expiryText:SetWordWrap(true)
    local expiryFont = expiryText:GetFont()
    if expiryFont then expiryText:SetFont(expiryFont, 32, "OUTLINE") end
    expiryText:SetTextColor(1, 0.2, 0.12)
    expiryWarning.text = expiryText
    expiryWarning:Hide()
    NS.ExpiryWarning = expiryWarning

    local bagSlotsButton = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
    bagSlotsButton:SetSize(150, 26)
    bagSlotsButton:SetMovable(true)
    bagSlotsButton:SetClampedToScreen(true)
    bagSlotsButton:RegisterForDrag("LeftButton")
    bagSlotsButton:SetScript("OnDragStart", StartDrag)
    bagSlotsButton:SetScript("OnDragStop", function(self)
        SavePosition(self, "bagsPoint")
    end)
    bagSlotsButton:SetScript("OnClick", function()
        if ToggleAllBags then ToggleAllBags() end
    end)
    bagSlotsButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(NS.L.BAG_SLOTS_TOOLTIP or "Click to open your bags")
        GameTooltip:AddLine(string.format(
            NS.L.BAG_SLOTS_DETAIL or "%d free of %d slots",
            self.freeSlots or 0,
            self.totalSlots or 0
        ), 1, 1, 1)
        GameTooltip:Show()
    end)
    bagSlotsButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    NS.BagSlotsButton = bagSlotsButton

    local elapsed = 0
    local sealTimerElapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        local db = NS.GetDB and NS.GetDB()
        local canMove = db and not db.locked and not (InCombatLockdown and InCombatLockdown())
        for _, movableFrame in ipairs({ frame, sealFrame }) do
            local handle = movableFrame.moveHandle
            if handle then
                handle:SetShown(canMove and (handle.isMoving or movableFrame:IsMouseOver() or handle:IsMouseOver()))
            end
        end
        warningFlashElapsed = warningFlashElapsed + dt
        if warningFlashElapsed >= 0.4 then
            warningFlashElapsed = warningFlashElapsed - 0.4
            warningFlashOn = not warningFlashOn
        end
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            elapsed = 0
            Update()
        end
        sealTimerElapsed = sealTimerElapsed + dt
        if sealTimerElapsed >= 0.2 then
            sealTimerElapsed = 0
            RenderSealStatus()
        end
    end)

    return frame
end

function NS.RestorePosition()
    if not NS.Frame or not NS.SealFrame or not NS.ManaFrame or not NS.BagSlotsButton or not NS.GetDB then return end
    local db = NS.GetDB()
    if not db then return end
    local className = NS.GetActiveClass and NS.GetActiveClass() or NS.GetPlayerClassKey()
    local profile = NS.GetClassProfile and NS.GetClassProfile(className)
    local positions = db.positions and db.positions[className]
    local point = positions and positions.point or profile and profile.point or db.point
    local sealPoint = positions and positions.sealPoint or profile and profile.sealPoint
    local manaPoint = positions and positions.manaPoint or profile and profile.manaPoint
    local bagsPoint = positions and positions.bagsPoint or profile and profile.bagsPoint

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
    RestoreFramePosition(NS.BagSlotsButton, bagsPoint, -390)
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

local eventFrame = CreateFrame("Frame")
NS.EventFrame = eventFrame
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
eventFrame:RegisterEvent("UNIT_MAXPOWER")
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event, unit, ...)
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        if unit == "player" then UpdateManaBar() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
        ResetSealTimerAfterCast(...)
    elseif event == "UNIT_AURA" and unit == "player" then
        if not InCombatLockdown() then Rebuild() end
        Update()
        UpdateManaBar()
    elseif event == "UNIT_INVENTORY_CHANGED" and unit == "player" then
        if NS.Refresh then NS.Refresh() end
    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
        UpdateBagSlots()
    elseif event == "PLAYER_REGEN_ENABLED" and refreshPending then
        if NS.Refresh then NS.Refresh() end
    end
end)
