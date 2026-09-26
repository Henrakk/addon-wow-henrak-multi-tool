local ADDON = "HenrakMultiTool"
local NS = _G[ADDON] or {}
_G[ADDON] = NS

NS.DEFAULT_ICON_SIZE = 48
NS.MIN_ICON_SIZE = 24
NS.MAX_ICON_SIZE = 72
NS.DEFAULT_MISSING_TEXT_SIZE = 12
NS.MIN_MISSING_TEXT_SIZE = 8
NS.MAX_MISSING_TEXT_SIZE = 24
NS.DEFAULT_TIMER_TEXT_SIZE = 12
NS.MIN_TIMER_TEXT_SIZE = 6
NS.MAX_TIMER_TEXT_SIZE = 32
NS.SPACING = 6
NS.ROW_HEIGHT = 58
NS.L = NS.L or {}

local function EnsureDB()
    if type(HenrakMultiToolDB) ~= "table" then
        if type(PaladinCaernSidheDB) == "table" then
            HenrakMultiToolDB = PaladinCaernSidheDB
        else
            HenrakMultiToolDB = {}
        end
    end
    if type(PaladinCaernSidheDB) ~= "table" then
        PaladinCaernSidheDB = HenrakMultiToolDB
    end
    return HenrakMultiToolDB
end
NS.GetDB = EnsureDB

function NS.SetIconSize(size)
    local db = NS.GetDB()
    local value = tonumber(size) or db.iconSize or NS.DEFAULT_ICON_SIZE
    if value < NS.MIN_ICON_SIZE then value = NS.MIN_ICON_SIZE end
    if value > NS.MAX_ICON_SIZE then value = NS.MAX_ICON_SIZE end
    db.iconSize = value
    if NS.Refresh then NS.Refresh() end
end

function NS.SetSealIconSize(size)
    local db = NS.GetDB()
    local value = tonumber(size) or db.sealIconSize or NS.DEFAULT_ICON_SIZE
    if value < NS.MIN_ICON_SIZE then value = NS.MIN_ICON_SIZE end
    if value > NS.MAX_ICON_SIZE then value = NS.MAX_ICON_SIZE end
    db.sealIconSize = value
    if NS.Refresh then NS.Refresh() end
end

function NS.GetPlayerClassKey()
    if UnitClass then
        local _, englishClass = UnitClass("player")
        if englishClass then
            return string.upper(englishClass)
        end
    end
    return "PALADIN"
end

function NS.HasShieldEquipped()
    local getItemInfoInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
    if NS.GetPlayerClassKey() ~= "PALADIN" or not GetInventoryItemID or not getItemInfoInstant then return false end
    local itemID = GetInventoryItemID("player", 17)
    if not itemID then return false end
    local _, _, _, equipLocation = getItemInfoInstant(itemID)
    return equipLocation == "INVTYPE_SHIELD"
end

function NS.SetActiveClass(className)
    local key = string.upper(className or NS.GetPlayerClassKey())
    local db = NS.GetDB()
    if not NS.ClassBuffs[key] then
        key = NS.GetPlayerClassKey()
    end
    db.activeClass = key
    db.autoClass = false
    if NS.Refresh then NS.Refresh() end
    return key
end

function NS.GetClassProfile(className)
    local db = NS.GetDB()
    local classKey = string.upper(className or NS.GetActiveClass())
    db.classProfiles = db.classProfiles or {}
    db.classProfiles[classKey] = db.classProfiles[classKey] or { enabled = true, buffs = {} }

    local profile = db.classProfiles[classKey]
    if not profile then
        profile = { enabled = true, buffs = {} }
        db.classProfiles[classKey] = profile
    end
    if not profile.buffs then profile.buffs = {} end
    for _, buff in ipairs(NS.ClassBuffs[classKey] or {}) do
        if profile.buffs[buff.key] == nil then
            profile.buffs[buff.key] = buff.default
        end
    end
    return profile
end

function NS.GetActiveClass()
    local db = NS.GetDB()
    if db.autoClass ~= false then
        db.activeClass = NS.GetPlayerClassKey()
    end
    local classKey = string.upper(db.activeClass or NS.GetPlayerClassKey())
    if not NS.ClassBuffs[classKey] then
        classKey = "PALADIN"
    end
    db.activeClass = classKey
    return classKey
end

function NS.GetKnownSpellID(buff)
    if not buff or not buff.spellIDs then return nil end

    local knownSpellID
    for _, spellID in ipairs(buff.spellIDs) do
        local known
        if IsSpellKnown then
            local ok, result = pcall(IsSpellKnown, spellID)
            known = ok and result
        elseif IsPlayerSpell then
            local ok, result = pcall(IsPlayerSpell, spellID)
            known = ok and result
        else
            return spellID
        end
        if known then
            knownSpellID = spellID
        end
    end
    return knownSpellID
end

function NS.GetActiveBuffs()
    local classKey = NS.GetActiveClass()
    local profile = NS.GetClassProfile(classKey)
    local hasShield = classKey == "PALADIN" and NS.HasShieldEquipped and NS.HasShieldEquipped()
    local buffs = {}
    for _, buff in ipairs(NS.ClassBuffs[classKey] or {}) do
        local known = NS.GetKnownSpellID(buff) ~= nil
        local available = known
        if buff.requiresShield then available = hasShield end
        if not buff.isSeal and available
            and profile.enabled ~= false
            and (profile.buffs[buff.key] == nil or profile.buffs[buff.key] ~= false)
        then
            table.insert(buffs, buff)
        end
    end
    return buffs
end

function NS.GetSealBuffs()
    local classKey = NS.GetActiveClass()
    local profile = NS.GetClassProfile(classKey)
    local seals = {}
    for _, buff in ipairs(NS.ClassBuffs[classKey] or {}) do
        if buff.isSeal
            and profile.enabled ~= false
            and (profile.buffs[buff.key] == nil or profile.buffs[buff.key] ~= false) then
            table.insert(seals, buff)
        end
    end
    return seals
end

function NS.GetSealDisplayBuffs()
    local seals = NS.GetSealBuffs()
    local active = {}
    for _, seal in ipairs(seals) do
        local present, aura = NS.HasBuff(seal)
        if present then
            local displaySeal = {}
            for key, value in pairs(seal) do
                displaySeal[key] = value
            end
            displaySeal.activeSpellID = aura and (aura.spellId or aura.spellID)
            table.insert(active, displaySeal)
            if #active == 2 then break end
        end
    end
    if #active > 0 then return active end
    if #seals == 0 then return {} end
    return {{
        key = "SealMissing",
        labelKey = "SEAL_MISSING",
        spellIDs = seals[1].spellIDs,
        isSeal = true,
        isMissingSeal = true,
    }}
end

function NS.CopyDefaults()
    local db = EnsureDB()
    db.enabled = db.enabled ~= false
    db.iconSize = math.max(NS.MIN_ICON_SIZE, math.min(NS.MAX_ICON_SIZE, tonumber(db.iconSize) or NS.DEFAULT_ICON_SIZE))
    db.sealIconSize = math.max(NS.MIN_ICON_SIZE, math.min(NS.MAX_ICON_SIZE, tonumber(db.sealIconSize) or db.iconSize))
    db.missingTextSize = math.max(NS.MIN_MISSING_TEXT_SIZE, math.min(NS.MAX_MISSING_TEXT_SIZE, tonumber(db.missingTextSize) or NS.DEFAULT_MISSING_TEXT_SIZE))
    db.timerTextSize = math.max(NS.MIN_TIMER_TEXT_SIZE, math.min(NS.MAX_TIMER_TEXT_SIZE, tonumber(db.timerTextSize) or NS.DEFAULT_TIMER_TEXT_SIZE))
    db.showNames = db.showNames ~= false
    db.showMissingText = db.showMissingText ~= false
    db.locked = db.locked == true
    db.autoClass = db.autoClass ~= false
    db.activeClass = db.activeClass or NS.GetPlayerClassKey()
    db.classProfiles = db.classProfiles or {}
    db.positions = db.positions or {}

    for className, classBuffs in pairs(NS.ClassBuffs) do
        for _, buff in ipairs(classBuffs) do
            local profile = NS.GetClassProfile(className)
            if profile.buffs[buff.key] == nil then
                profile.buffs[buff.key] = buff.default
            end
        end
    end

    if db.point then
        local profile = NS.GetClassProfile(NS.GetActiveClass())
        if not profile.point then
            profile.point = db.point
        end
        db.point = nil
    end

    for className in pairs(NS.ClassBuffs) do
        local profile = NS.GetClassProfile(className)
        db.positions[className] = db.positions[className] or {}
        if profile.point and not db.positions[className].point then
            db.positions[className].point = profile.point
        end
        if profile.sealPoint and not db.positions[className].sealPoint then
            db.positions[className].sealPoint = profile.sealPoint
        end
    end
end

function NS.SpellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and texture then return texture end
    end
    if GetSpellTexture then
        local ok, texture = pcall(GetSpellTexture, spellID)
        if ok and texture then return texture end
    end
    return 134400
end

function NS.SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and name then return name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and name then return name end
    end
    return tostring(spellID)
end

function NS.HasBuff(buff)
    local wanted = {}
    local wantedNames = {}
    for _, id in ipairs(buff.spellIDs or {}) do
        wanted[id] = true
        wantedNames[NS.SpellName(id)] = true
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        for name in pairs(wantedNames) do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
            if ok and aura then
                return true, aura
            end
        end
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 64 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok then return false end
            if not aura then break end
            local spellID = aura.spellId or aura.spellID
            local canReadSpellID = spellID and (not canaccessvalue or canaccessvalue(spellID))
            if spellID and canReadSpellID and wanted[spellID] then
                return true, aura
            end
            if aura.name and wantedNames[aura.name] then
                return true, aura
            end
        end
    elseif C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        for i = 1, 64 do
            local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, "player", i)
            if not ok then return false end
            if not aura then break end
            local spellID = aura.spellId or aura.spellID
            local canReadSpellID = spellID and (not canaccessvalue or canaccessvalue(spellID))
            if spellID and canReadSpellID and wanted[spellID] then
                return true, aura
            end
            if aura.name and wantedNames[aura.name] then
                return true, aura
            end
        end
    elseif UnitAura then
        for i = 1, 64 do
            local ok, name, icon, count, debuffType, duration, expirationTime, source, _, _, spellID = pcall(UnitAura, "player", i, "HELPFUL")
            if not ok then
                return false
            end
            if not name then break end
            if spellID and wanted[spellID] then
                return true, {
                    name = name,
                    icon = icon,
                    duration = duration,
                    expirationTime = expirationTime,
                    spellId = spellID,
                }
            end
            if name and wantedNames[name] then
                return true, {
                    name = name,
                    icon = icon,
                    duration = duration,
                    expirationTime = expirationTime,
                    spellId = spellID,
                }
            end
        end
    end

    return false
end
