local ADDON = "MultiTool"
local NS = _G[ADDON] or {}
_G[ADDON] = NS

-- Combat rules followed by this file:
--  * Reading auras and updating purely visual state (SetAlpha, SetDesaturated,
--    SetTexture, FontString text/visibility) is allowed in combat.
--  * The icon buttons are secure frames, and so are the frames that parent
--    them: Show/Hide/SetPoint/SetSize/SetHeight/SetAttribute on any of them is
--    blocked in combat. That work only happens out of combat (Rebuild() and
--    the frame sizing in RenderStatusLine()); when something changed during
--    combat, refreshPending is set and NS.Refresh() runs on PLAYER_REGEN_ENABLED.
--  * Aura fields can be unreadable ("secret") in combat. All reads go through
--    NS.CanRead / NS.GetAuraTiming, and when aura data is hidden we keep
--    displaying the last known state instead of guessing.

local SEAL_DEFAULT_DURATION = 30
local SEAL_RECAST_GRACE = 2
local EXPIRY_WARNING_RATIO = 0.05

local icons = {}
local sealIcons = {}
local sealTimers = {}
local paladinAuraPresent = false
local refreshPending = false
local warningFlashOn = false
local warningFlashElapsed = 0
local reportedErrors = {}

local function InCombat()
    return InCombatLockdown ~= nil and InCombatLockdown() and true or false
end

-- Runs fn so that one failing component cannot freeze the whole tracker;
-- each distinct failure is reported once instead of spamming the chat.
local function Guarded(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not reportedErrors[label] then
        reportedErrors[label] = true
        print("|cff70d5ffMultiTool|r: error in " .. label .. ": " .. tostring(err))
    end
    return ok
end

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

local function FormatRemaining(remaining)
    local secondsLeft = math.max(1, math.floor(remaining))
    if secondsLeft >= 60 then
        return string.format("%dm %ds", math.floor(secondsLeft / 60), secondsLeft % 60)
    end
    return string.format("%ds", secondsLeft)
end

local function SetButtonTimer(button, remaining)
    if remaining and remaining > 0 and remaining < 3600 then
        button.timer:SetText(FormatRemaining(remaining))
        button.timer:Show()
    else
        button.timer:Hide()
    end
end

local function SetButtonPresence(button, present)
    button:SetAlpha(present and 1 or 0.45)
    button.icon:SetDesaturated(not present)
end

local function UpdateExpiryAlert()
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
            local isSeal = button.buff and button.buff.isSeal
            local remaining
            if button:IsShown() and button.buff and button.present
                and button.duration and button.expiresAt then
                remaining = button.expiresAt - now
            end

            local expiring = remaining and remaining > 0
                and remaining <= button.duration * EXPIRY_WARNING_RATIO
            if expiring then
                local label = NS.L[button.buff.labelKey] or button.buff.key or "Buff"
                table.insert(lines, string.format(
                    NS.L.BUFF_EXPIRING_LINE or "%s (%ds)",
                    label,
                    math.max(1, math.ceil(remaining))
                ))
            end

            if button.glow then
                if isSeal and expiring then
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
                    if isSeal and button.timer then
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

-- Seals ----------------------------------------------------------------------
-- sealTimers[key] = { seal, order, duration, expiresAt, castAt, previousExpiresAt }
-- One entry per active seal. The live aura is the source of truth; the cast
-- event only restarts the countdown immediately, until the refreshed aura
-- (always expiring later than before the recast) is seen.

local function CastMatchesSeal(seal, castValues)
    for _, sealSpellID in ipairs(seal.spellIDs or {}) do
        local sealName = NS.SpellName(sealSpellID)
        for _, castValue in ipairs(castValues) do
            if NS.CanRead(castValue)
                and (tonumber(castValue) == sealSpellID or castValue == sealName) then
                return true
            end
        end
    end
    return false
end

local function CollectActiveSeals(now)
    local list = {}
    for key, timer in pairs(sealTimers) do
        if timer.expiresAt and timer.expiresAt <= now then
            sealTimers[key] = nil
        else
            list[#list + 1] = timer
        end
    end
    table.sort(list, function(a, b) return a.order < b.order end)
    return list
end

local function ShowButtonSeal(button, seal)
    if button.displayKey == seal.key then return end
    button.displayKey = seal.key
    local spellID = seal.activeSpellID or NS.GetKnownSpellID(seal) or (seal.spellIDs and seal.spellIDs[1])
    button.icon:SetTexture(NS.SpellTexture(spellID))
end

local function RenderSealStatus()
    if not NS.SealFrame then return end

    local now = GetTime()
    local active = CollectActiveSeals(now)

    if NS.SealFrame.title then
        local primary = active[1]
        local remaining = primary and primary.expiresAt and primary.expiresAt - now
        NS.SealFrame.title:SetText(remaining and FormatRemaining(remaining) or "")
    end

    local buttons = {}
    for _, button in ipairs(sealIcons) do
        if button:IsShown() and button.buff and button.buff.isSeal then
            buttons[#buttons + 1] = button
        end
    end

    -- Buttons are built out of combat for the seals active at that time. If the
    -- seal changed since (e.g. cast in combat), the button of a seal that is no
    -- longer active shows the seal that is.
    local assigned, used = {}, {}
    for _, button in ipairs(buttons) do
        for _, timer in ipairs(active) do
            if not used[timer] and timer.seal.key == button.buff.key then
                assigned[button] = timer
                used[timer] = true
                break
            end
        end
    end
    for _, button in ipairs(buttons) do
        if not assigned[button] then
            for _, timer in ipairs(active) do
                if not used[timer] then
                    assigned[button] = timer
                    used[timer] = true
                    break
                end
            end
        end
    end

    for _, button in ipairs(buttons) do
        local timer = assigned[button]
        if timer then
            ShowButtonSeal(button, timer.seal)
            button.present, button.duration, button.expiresAt = true, timer.duration, timer.expiresAt
            SetButtonPresence(button, true)
            button.missing:Hide()
            SetButtonTimer(button, timer.expiresAt and timer.expiresAt - now)
        else
            ShowButtonSeal(button, button.buff)
            button.present, button.duration, button.expiresAt = false, nil, nil
            SetButtonPresence(button, false)
            button.timer:Hide()
            button.missing:Hide()
        end
    end
end

local function UpdateSealStates()
    if not NS.GetSealBuffs then return end
    if InCombat() and not NS.AuraDataReadable() then return end

    local now = GetTime()
    for index, seal in ipairs(NS.GetSealBuffs()) do
        local present, aura = NS.HasBuff(seal)
        local timer = sealTimers[seal.key]
        local inGrace = timer and timer.castAt and now - timer.castAt < SEAL_RECAST_GRACE

        if present then
            if not timer then
                timer = {}
                sealTimers[seal.key] = timer
            end
            timer.seal, timer.order = seal, index

            local readable, duration, expiration = NS.GetAuraTiming(aura)
            if readable and expiration then
                if expiration > now and (not inGrace or expiration > (timer.previousExpiresAt or 0)) then
                    timer.duration, timer.expiresAt = duration, expiration
                    timer.castAt, timer.previousExpiresAt = nil, nil
                end
            elseif readable then
                -- Aura without expiration: active, but nothing to count down.
                if not inGrace then timer.duration, timer.expiresAt = nil, nil end
            elseif not timer.expiresAt then
                timer.duration = timer.duration or SEAL_DEFAULT_DURATION
                timer.expiresAt = now + timer.duration
            end
        elseif timer and not inGrace then
            sealTimers[seal.key] = nil
        end
    end
end

-- Regular buffs -----------------------------------------------------------------

local function UpdateBuffStates()
    if InCombat() and not NS.AuraDataReadable() then return end

    for _, button in ipairs(icons) do
        if button:IsShown() and button.buff then
            local present, aura = NS.HasBuff(button.buff)
            button.present = present == true
            if present then
                local readable, duration, expiration = NS.GetAuraTiming(aura)
                if readable then
                    button.duration, button.expiresAt = duration, expiration
                end
            else
                button.duration, button.expiresAt = nil, nil
            end
        end
    end
end

local function UpdatePaladinAura()
    if NS.GetActiveClass() ~= "PALADIN" then
        paladinAuraPresent = false
        return
    end
    if InCombat() and not NS.AuraDataReadable() then return end

    paladinAuraPresent = false
    for _, aura in ipairs(NS.PaladinAuras or {}) do
        if NS.HasBuff(aura) then
            paladinAuraPresent = true
            break
        end
    end
end

local GROUP_MISSING_KEYS = {
    blessing = "BLESSING_MISSING",
    aura = "AURA_MISSING",
}

local function RenderBuffIcons(db, now)
    local groupPresent = {}
    for _, button in ipairs(icons) do
        if button:IsShown() and button.buff and button.buff.groupKey and button.present then
            groupPresent[button.buff.groupKey] = true
        end
    end

    local groupAlertShown = {}
    for _, button in ipairs(icons) do
        if button:IsShown() and button.buff then
            if button.present then
                SetButtonPresence(button, true)
                button.missing:Hide()
                SetButtonTimer(button, button.expiresAt and button.expiresAt - now)
            else
                SetButtonPresence(button, false)
                button.timer:Hide()
                if db.showMissingText then
                    local buff = button.buff
                    local label = NS.L[buff.labelKey] or NS.SpellName(buff.spellIDs[1])
                    local groupKey = buff.groupKey
                    if groupKey then
                        if groupPresent[groupKey] or groupAlertShown[groupKey] then
                            button.missing:Hide()
                        else
                            button.missing:SetText(NS.L[GROUP_MISSING_KEYS[groupKey]] or label)
                            button.missing:Show()
                            groupAlertShown[groupKey] = true
                        end
                    else
                        button.missing:SetText(label .. " " .. (NS.L.MISSING or "missing"))
                        button.missing:Show()
                    end
                else
                    button.missing:Hide()
                end
            end
        end
    end
end

local function RenderStatusLine(db)
    local frame = NS.Frame
    local status = frame and frame.status
    if not status then return end

    local missing = db.showMissingText and NS.GetActiveClass() == "PALADIN" and not paladinAuraPresent
    if missing then
        status:SetText(NS.L.AURA_MISSING or "No aura")
        status:Show()
    else
        status:Hide()
    end

    -- Resizing the frame is protected (it parents secure buttons).
    if not InCombat() then
        local height = frame.baseHeight or frame:GetHeight()
        if missing then
            height = height + (tonumber(db.missingTextSize) or NS.DEFAULT_MISSING_TEXT_SIZE) + 8
        end
        if math.abs(frame:GetHeight() - height) > 0.01 then
            frame:SetHeight(height)
        end
    end
end

-- Draws the current state; no aura reads, so it is cheap enough to run often.
local function Render()
    local db = NS.GetDB and NS.GetDB()
    if not db or not db.enabled or not NS.Frame then return end

    Guarded("render buffs", RenderBuffIcons, db, GetTime())
    Guarded("render seals", RenderSealStatus)
    Guarded("render status", RenderStatusLine, db)
    Guarded("render expiry alert", UpdateExpiryAlert)
end

local function ResetSealTimerAfterCast(...)
    local castValues = { ... }
    if #castValues == 0 or not NS.GetSealBuffs then return end

    for index, seal in ipairs(NS.GetSealBuffs()) do
        if CastMatchesSeal(seal, castValues) then
            local now = GetTime()
            local timer = sealTimers[seal.key]
            if not timer then
                timer = {}
                sealTimers[seal.key] = timer
            end
            timer.seal, timer.order = seal, index
            timer.previousExpiresAt = timer.expiresAt
            timer.castAt = now
            timer.duration = timer.duration or SEAL_DEFAULT_DURATION
            timer.expiresAt = now + timer.duration
            Render()
            return
        end
    end
end

function NS.DebugSeal()
    local function say(text) print("|cff70d5ffMultiTool|r " .. text) end
    local function show(value)
        if NS.CanRead(value) then return tostring(value) end
        return "<secret>"
    end

    local class = NS.GetActiveClass()
    say(string.format("seal debug: class=%s inCombat=%s auraDataReadable=%s",
        class, tostring(InCombat()), tostring(NS.AuraDataReadable())))

    for _, buff in ipairs(NS.ClassBuffs[class] or {}) do
        if buff.isSeal then
            local present, aura = NS.HasBuff(buff)
            say(string.format("  %s: known=%s present=%s ids=%s name=%s",
                buff.key, tostring(NS.GetKnownSpellID(buff)), tostring(present),
                table.concat(buff.spellIDs, ","), tostring(NS.SpellName(buff.spellIDs[1]))))
            if present and aura then
                say(string.format("    aura: name=%s id=%s duration=%s expires=%s",
                    show(aura.name), show(aura.spellId or aura.spellID), show(aura.duration), show(aura.expirationTime)))
            end
        end
    end

    local now = GetTime()
    for key, timer in pairs(sealTimers) do
        say(string.format("  timer %s: remaining=%s duration=%s", key,
            tostring(timer.expiresAt and timer.expiresAt - now), tostring(timer.duration)))
    end

    say("  player buffs:")
    local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for i = 1, 40 do
        local name, spellID, duration, expiration
        if byIndex then
            local ok, aura = pcall(byIndex, "player", i, "HELPFUL")
            if not ok or not aura then break end
            name, spellID = aura.name, aura.spellId or aura.spellID
            duration, expiration = aura.duration, aura.expirationTime
        elseif UnitAura then
            local auraName, _, _, _, auraDuration, auraExpiration, _, _, _, auraSpellID = UnitAura("player", i, "HELPFUL")
            if not auraName then break end
            name, spellID, duration, expiration = auraName, auraSpellID, auraDuration, auraExpiration
        else
            break
        end
        say(string.format("    [%d] %s id=%s duration=%s expires=%s",
            i, show(name), show(spellID), show(duration), show(expiration)))
    end
end

local function Rebuild()
    if not NS.Frame or not NS.SealFrame or not NS.GetDB then return end
    if InCombat() then
        refreshPending = true
        return
    end
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
            if not b.buff or b.buff.key ~= buff.key then
                b.present, b.duration, b.expiresAt = false, nil, nil
            end
            b.buff = buff
            local spellID = buff.activeSpellID or NS.GetKnownSpellID(buff) or (buff.spellIDs and buff.spellIDs[1])
            b.icon:SetTexture(NS.SpellTexture(spellID))
            b.displayKey = buff.key
            if spellID and not buff.isMissingSeal then
                b:SetAttribute("type", "spell")
                b:SetAttribute("spell", spellID)
            else
                b:SetAttribute("type", nil)
                b:SetAttribute("spell", nil)
            end
            iconList[i] = b
        end
    end

    BuildGroup(active, icons, db.iconSize, -6)
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

-- Polls the auras, then draws. Safe to call in combat (see rules at the top).
local function Update()
    if not NS.Frame or not NS.SealFrame or not NS.GetDB then return end
    local db = NS.GetDB()
    if not db then return end

    local inCombat = InCombat()
    if inCombat then refreshPending = true end

    if not db.enabled then
        if not inCombat then
            NS.Frame:Hide()
            NS.SealFrame:Hide()
        end
        if NS.ExpiryWarning then NS.ExpiryWarning:Hide() end
        return
    end
    if not inCombat then NS.Frame:Show() end

    Guarded("seal update", UpdateSealStates)
    Guarded("buff update", UpdateBuffStates)
    Guarded("aura update", UpdatePaladinAura)
    Render()
end

function NS.Refresh()
    if InCombat() then
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

    local pollElapsed = 0
    local renderElapsed = 0
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
        pollElapsed = pollElapsed + dt
        if pollElapsed >= 0.5 then
            pollElapsed = 0
            renderElapsed = 0
            Update()
        end
        renderElapsed = renderElapsed + dt
        if renderElapsed >= 0.2 then
            renderElapsed = 0
            Render()
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
        Guarded("seal cast", ResetSealTimerAfterCast, ...)
    elseif event == "UNIT_AURA" and unit == "player" then
        Rebuild()
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
