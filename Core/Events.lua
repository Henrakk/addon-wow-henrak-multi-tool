local ADDON = "MultiTool"
local NS = _G[ADDON] or {}
_G[ADDON] = NS

local initialized = false

function NS.AutoSelectClass()
    if not NS.GetDB then return end
    local db = NS.GetDB()
    if db.autoClass ~= false then
        db.activeClass = NS.GetPlayerClassKey()
    end
    if NS.Refresh then NS.Refresh() end
end

local function Init()
    if initialized then return end
    initialized = true

    if NS.CopyDefaults then
        NS.CopyDefaults()
    end

    if not NS.Frame and NS.CreateTrackerFrame then
        NS.CreateTrackerFrame()
    end

    if NS.CreateXPBar then
        NS.CreateXPBar()
    end

    if NS.RegisterOptions then
        NS.RegisterOptions()
    end

    if NS.RestorePosition then
        NS.RestorePosition()
    end

    if NS.AutoSelectClass then
        NS.AutoSelectClass()
    end

    if NS.Refresh then
        NS.Refresh()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        Init()
    end
end)
