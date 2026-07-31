local ADDON_NAME, Pockezimba = ...

local DEFAULTS = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -160,
    locked = false,
    showGold = true,
}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd200Pockezimba:|r " .. tostring(msg))
end
Pockezimba.Print = Print

-- Formats a number with thousands separators, e.g. 12510 -> "12,510"
local function FormatNumber(n)
    n = math.floor((n or 0) + 0.5)
    local sign = ""
    if n < 0 then
        sign = "-"
        n = -n
    end

    local formatted = tostring(n)
    local inserted
    repeat
        formatted, inserted = formatted:gsub("^(%d+)(%d%d%d)", "%1,%2")
    until inserted == 0

    return sign .. formatted
end

-- Formats copper as "1,234g 56s 78c". Silver/copper are always shown once
-- gold is present (so amounts stay easy to scan), but gold/silver are
-- dropped entirely when zero so a fresh character shows "3s 12c" instead of
-- a misleading "0g 3s 12c".
local function FormatMoney(copperTotal)
    copperTotal = math.max(0, math.floor(copperTotal or 0))
    local gold = math.floor(copperTotal / 10000)
    local silver = math.floor((copperTotal % 10000) / 100)
    local copper = copperTotal % 100

    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = FormatNumber(gold) .. "g"
    end
    if silver > 0 or gold > 0 then
        parts[#parts + 1] = silver .. "s"
    end
    parts[#parts + 1] = copper .. "c"

    return table.concat(parts, " ")
end

--------------------------------------------------------------------------------
-- Frame & display (no background, outlined text only)
--------------------------------------------------------------------------------

local MAIN_COLOR = { 1.0, 0.82, 0.0 } -- gold

local frame = CreateFrame("Frame", "PockezimbaFrame", UIParent)
frame:SetSize(160, 20)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")

local goldText = frame:CreateFontString(nil, "OVERLAY")
goldText:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
goldText:SetTextColor(MAIN_COLOR[1], MAIN_COLOR[2], MAIN_COLOR[3])
goldText:SetJustifyH("LEFT")
goldText:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
goldText:SetText("Pockezimba: loading...")
frame.goldText = goldText

-- Per-currency lines, created lazily, one per currency currently pinned to
-- show on the backpack (mirrors Blizzard's own BackpackTokenFrame list).
local currencyLines = {}
local LINE_GAP = -2

local function HideCurrencyLinesFrom(fromIndex)
    for i = fromIndex, #currencyLines do
        currencyLines[i]:Hide()
    end
end

local function SavePosition()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not point then return end
    Pockezimba.db.point = point
    Pockezimba.db.relativePoint = relativePoint
    Pockezimba.db.x = x
    Pockezimba.db.y = y
end

frame:SetScript("OnDragStart", function(self)
    if not Pockezimba.db or Pockezimba.db.locked then return end
    self:StartMoving()
end)

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)

local function ApplyLockState()
    if not Pockezimba.db then return end
    -- EnableMouse(false) makes the frame fully click-through while pinned.
    frame:EnableMouse(not Pockezimba.db.locked)
end
Pockezimba.ApplyLockState = ApplyLockState

local function RestorePosition()
    local db = Pockezimba.db
    frame:ClearAllPoints()
    frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
end
Pockezimba.RestorePosition = RestorePosition

--------------------------------------------------------------------------------
-- Currency scanning
--------------------------------------------------------------------------------

-- Walks the same currency list Blizzard's own Character > Currency tab
-- displays, returning only the entries whose "Show on Backpack" star is
-- toggled on (the ones that already appear above the bags in the default
-- UI) -- skipping headers and anything not yet discovered. Wrapped in pcall
-- throughout since C_CurrencyInfo's shape has shifted across client
-- versions and there's no local client available to verify field names
-- against (see project memory: WoW addon dev pattern).
local function GetBackpackCurrencies()
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyListSize or not C_CurrencyInfo.GetCurrencyListInfo then
        return {}
    end

    local okSize, size = pcall(C_CurrencyInfo.GetCurrencyListSize)
    if not okSize or not size then
        return {}
    end

    local result = {}
    for i = 1, size do
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, i)
        if ok and info and not info.isHeader and info.isShowInBackpack and info.discovered ~= false then
            result[#result + 1] = {
                name = info.name,
                quantity = info.quantity or 0,
                maxQuantity = info.maxQuantity or 0,
            }
        end
    end

    return result
end

--------------------------------------------------------------------------------
-- Display
--------------------------------------------------------------------------------

local function RecalculateFrameSize()
    local width = goldText:IsShown() and goldText:GetStringWidth() or 0
    local height = goldText:IsShown() and (goldText:GetStringHeight() + 2) or 0

    for _, line in ipairs(currencyLines) do
        if line:IsShown() then
            width = math.max(width, line:GetStringWidth())
            height = height + line:GetStringHeight() + 2
        end
    end

    frame:SetSize(math.max(width + 10, 40), math.max(height, 20))
end

local function RenderDisplay()
    local db = Pockezimba.db
    if not db then return end

    local currencies = GetBackpackCurrencies()

    if db.showGold then
        goldText:SetText(FormatMoney(GetMoney()))
        goldText:Show()
    elseif #currencies == 0 then
        -- Nothing to show at all -- surface a hint instead of an empty frame.
        goldText:SetText("Pockezimba: nothing pinned")
        goldText:Show()
    else
        goldText:Hide()
    end

    goldText:ClearAllPoints()
    goldText:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

    local anchor = goldText:IsShown() and goldText or nil
    for i, currencyData in ipairs(currencies) do
        local line = currencyLines[i]
        if not line then
            line = frame:CreateFontString(nil, "OVERLAY")
            line:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
            line:SetTextColor(MAIN_COLOR[1], MAIN_COLOR[2], MAIN_COLOR[3])
            line:SetJustifyH("LEFT")
            currencyLines[i] = line
        end

        line:ClearAllPoints()
        if anchor then
            line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, LINE_GAP)
        else
            line:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        end

        if currencyData.maxQuantity and currencyData.maxQuantity > 0 then
            line:SetText(string.format("%s: %s/%s", currencyData.name, FormatNumber(currencyData.quantity), FormatNumber(currencyData.maxQuantity)))
        else
            line:SetText(string.format("%s: %s", currencyData.name, FormatNumber(currencyData.quantity)))
        end
        line:Show()
        anchor = line
    end
    HideCurrencyLinesFrom(#currencies + 1)

    RecalculateFrameSize()
end
Pockezimba.RenderDisplay = RenderDisplay

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- Debounced refresh so back-to-back events (e.g. several currencies
-- updating in the same server tick) don't trigger a full re-render per
-- event.
local updatePending = false
local function RequestUpdate()
    if updatePending then return end
    updatePending = true
    C_Timer.After(0.2, function()
        updatePending = false
        RenderDisplay()
    end)
end
Pockezimba.RequestUpdate = RequestUpdate

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end

        PockezimbaDB = PockezimbaDB or {}
        for key, value in pairs(DEFAULTS) do
            if PockezimbaDB[key] == nil then
                PockezimbaDB[key] = value
            end
        end
        Pockezimba.db = PockezimbaDB

        RestorePosition()
        ApplyLockState()

        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_MONEY")
        self:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    else
        RequestUpdate()
    end
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

SLASH_POCKEZIMBA1 = "/pkz"
SLASH_POCKEZIMBA2 = "/pockezimba"
SlashCmdList["POCKEZIMBA"] = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(%S*)")
    cmd = (cmd or ""):lower()
    rest = (rest or ""):lower()

    if cmd == "lock" or cmd == "pin" then
        Pockezimba.db.locked = true
        ApplyLockState()
        Print("Locked in place. Mouse clicks now pass through.")
    elseif cmd == "unlock" then
        Pockezimba.db.locked = false
        ApplyLockState()
        Print("Unlocked. Left-click and drag to reposition.")
    elseif cmd == "refresh" then
        RenderDisplay()
        Print("Refreshed.")
    elseif cmd == "gold" then
        if rest == "on" then
            Pockezimba.db.showGold = true
            Print("Gold line shown.")
            RenderDisplay()
        elseif rest == "off" then
            Pockezimba.db.showGold = false
            Print("Gold line hidden.")
            RenderDisplay()
        else
            Print("Usage: /pkz gold on|off")
        end
    elseif cmd == "reset" then
        Pockezimba.db.point = DEFAULTS.point
        Pockezimba.db.relativePoint = DEFAULTS.relativePoint
        Pockezimba.db.x = DEFAULTS.x
        Pockezimba.db.y = DEFAULTS.y
        RestorePosition()
        Print("Position reset to center of screen.")
    else
        Print("Commands: /pkz lock|pin, /pkz unlock, /pkz refresh, /pkz gold on|off, /pkz reset")
        Print("Tip: pin currencies to show here via Character panel > Currency tab > right-click a currency > \"Show on Backpack\".")
    end
end
