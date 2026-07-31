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

--------------------------------------------------------------------------------
-- Rich-text helpers (inline icons/colors within a single FontString)
--------------------------------------------------------------------------------

local ICON_SIZE = 16

-- These three coin texture paths have been stable Blizzard assets for the
-- entire retail history of the game (used by every default-UI money
-- display), so they're a safer bet than guessing at a money-formatting
-- global whose exact name/signature can't be verified without a local
-- client (see project memory: WoW addon dev pattern).
local GOLD_ICON = "Interface\\MoneyFrame\\UI-GoldIcon"
local SILVER_ICON = "Interface\\MoneyFrame\\UI-SilverIcon"
local COPPER_ICON = "Interface\\MoneyFrame\\UI-CopperIcon"
local MONEY_TEXT_COLOR = "ffffd200"

local function IconMarkup(icon, size)
    if not icon then return "" end
    return string.format("|T%s:%d|t", icon, size)
end

-- Builds "1,234|Tgoldicon|t56|Tsilvericon|t78|Tcoppericon|t", dropping
-- gold/silver when zero (a fresh character shows "3|Tsilvericon|t12|Tcoppericon|t"
-- instead of misleading zeros) but always keeping copper.
local function BuildMoneySegment(copperTotal)
    copperTotal = math.max(0, math.floor(copperTotal or 0))
    local gold = math.floor(copperTotal / 10000)
    local silver = math.floor((copperTotal % 10000) / 100)
    local copper = copperTotal % 100

    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = string.format("|c%s%s|r%s", MONEY_TEXT_COLOR, FormatNumber(gold), IconMarkup(GOLD_ICON, ICON_SIZE))
    end
    if silver > 0 or gold > 0 then
        parts[#parts + 1] = string.format("|c%s%d|r%s", MONEY_TEXT_COLOR, silver, IconMarkup(SILVER_ICON, ICON_SIZE))
    end
    parts[#parts + 1] = string.format("|c%s%d|r%s", MONEY_TEXT_COLOR, copper, IconMarkup(COPPER_ICON, ICON_SIZE))

    return table.concat(parts, "")
end

-- ITEM_QUALITY_COLORS is the same global table the default UI uses to color
-- item names by rarity (Poor/Common/Rare/Epic/etc.) -- each entry's `.hex`
-- field is a ready-to-concatenate "|cffxxxxxx" prefix. Currencies expose the
-- same quality tiers via GetCurrencyListInfo's `quality` field, so reusing
-- it here gives currencies the same "proper" rarity coloring Blizzard's own
-- Currency tab uses, instead of one flat color for everything.
local function GetQualityColorPrefix(quality)
    local colorInfo = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    if colorInfo and colorInfo.hex then
        return colorInfo.hex
    end
    return "|cffffffff"
end

local function BuildCurrencySegment(currencyData)
    local amount = FormatNumber(currencyData.quantity)
    if currencyData.maxQuantity and currencyData.maxQuantity > 0 then
        amount = amount .. "/" .. FormatNumber(currencyData.maxQuantity)
    end

    return string.format("%s%s%s|r", IconMarkup(currencyData.icon, ICON_SIZE), GetQualityColorPrefix(currencyData.quality), amount)
end

--------------------------------------------------------------------------------
-- Frame & display (no background, single outlined text line)
--------------------------------------------------------------------------------

local MAIN_COLOR = { 1.0, 0.82, 0.0 } -- gold, used as the fallback/base color

local frame = CreateFrame("Frame", "PockezimbaFrame", UIParent)
frame:SetSize(160, 20)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")

local text = frame:CreateFontString(nil, "OVERLAY")
text:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
text:SetTextColor(MAIN_COLOR[1], MAIN_COLOR[2], MAIN_COLOR[3])
text:SetJustifyH("LEFT")
text:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
text:SetText("Pockezimba: loading...")
frame.text = text

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
                icon = info.iconFileID,
                quality = info.quality,
            }
        end
    end

    return result
end

--------------------------------------------------------------------------------
-- Display
--------------------------------------------------------------------------------

local function BuildDisplayLine()
    local db = Pockezimba.db
    local segments = {}

    if db.showGold then
        segments[#segments + 1] = BuildMoneySegment(GetMoney())
    end

    for _, currencyData in ipairs(GetBackpackCurrencies()) do
        segments[#segments + 1] = BuildCurrencySegment(currencyData)
    end

    if #segments == 0 then
        return "Pockezimba: nothing pinned"
    end

    return table.concat(segments, " ")
end

local function RenderDisplay()
    if not Pockezimba.db then return end

    text:SetText(BuildDisplayLine())
    frame:SetSize(math.max(text:GetStringWidth() + 10, 40), math.max(text:GetStringHeight(), 20))
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
            Print("Gold segment shown.")
            RenderDisplay()
        elseif rest == "off" then
            Pockezimba.db.showGold = false
            Print("Gold segment hidden.")
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
