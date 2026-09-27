local ADDON = "HenrakMultiTool"
local NS = _G[ADDON] or {}
_G[ADDON] = NS

function NS.CreateBuffIcon(frame, index)
    local db = NS.GetDB and NS.GetDB() or {}
    local size = tonumber(db.iconSize) or NS.DEFAULT_ICON_SIZE
    local b = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate,BackdropTemplate")
    b:RegisterForClicks("AnyDown")
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.glow:SetSize(size * 1.65, size * 1.65)
    b.glow:SetVertexColor(1, 0.12, 0.05, 1)
    b.glow:Hide()
    b.missing = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.missing:SetPoint("TOP", b, "BOTTOM", 0, -2)
    b.missing:SetJustifyH("CENTER")
    b.missing:SetTextColor(1, 0.25, 0.25)
    local missingFont, _, missingFlags = b.missing:GetFont()
    b.missing:SetFont(missingFont, tonumber(db.missingTextSize) or NS.DEFAULT_MISSING_TEXT_SIZE, missingFlags)
    b.missing:Hide()
    b.timer = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.timer:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.timer:SetWidth(size)
    b.timer:SetJustifyH("CENTER")
    b.timer:SetWordWrap(false)
    b.timer:SetTextColor(1, 1, 1)
    b.timer:Hide()
    b:SetScript("OnEnter", function(self)
        if not self.buff then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(NS.L[self.buff.labelKey] or self.buff.key)
        GameTooltip:AddLine(NS.L.CLICK_TO_CAST or "Click to cast", 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return b
end
