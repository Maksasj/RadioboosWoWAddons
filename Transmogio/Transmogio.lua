local ADDON_NAME, Transmogio = ...

local DEFAULTS = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -200,
    locked = false,
    expanded = false,
}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffTransmogio:|r " .. tostring(msg))
end
Transmogio.Print = Print

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
-- Frame & display (no background, outlined text only)
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "TransmogioFrame", UIParent)
frame:SetSize(220, 20)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")

local text = frame:CreateFontString(nil, "OVERLAY")
text:SetPoint("TOP", frame, "TOP", 0, 0)
text:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
text:SetTextColor(0.85, 0.35, 0.95, 1) -- purple/pink
text:SetText("Transmogio: loading...")
frame.text = text

-- Small "+"/"-" toggle hugging the left edge of the summary line, independent
-- of the main frame's own mouse state so it still works while pinned/locked.
local toggleButton = CreateFrame("Button", nil, frame)
toggleButton:SetSize(14, 14)
toggleButton:SetPoint("RIGHT", frame, "LEFT", -2, 0)
toggleButton:RegisterForClicks("LeftButtonUp")

local toggleText = toggleButton:CreateFontString(nil, "OVERLAY")
toggleText:SetPoint("CENTER", toggleButton, "CENTER", 0, 0)
toggleText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
toggleText:SetTextColor(0.85, 0.35, 0.95, 1)
toggleButton.text = toggleText

local function UpdateToggleGlyph()
    if not Transmogio.db then return end
    toggleText:SetText(Transmogio.db.expanded and "-" or "+")
end
Transmogio.UpdateToggleGlyph = UpdateToggleGlyph

-- Per-category lines, created lazily and shown only while expanded.
local categoryLines = {}
local CATEGORY_LINE_GAP = -1

local function GetOrCreateCategoryLine(index)
    local line = categoryLines[index]
    if not line then
        line = frame:CreateFontString(nil, "OVERLAY")
        line:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        line:SetTextColor(0.85, 0.35, 0.95, 1)
        line:SetJustifyH("CENTER")
        categoryLines[index] = line
    end

    line:ClearAllPoints()
    if index == 1 then
        line:SetPoint("TOP", text, "BOTTOM", 0, -3)
    else
        line:SetPoint("TOP", categoryLines[index - 1], "BOTTOM", 0, CATEGORY_LINE_GAP)
    end

    return line
end

local function HideCategoryLinesFrom(fromIndex)
    for i = fromIndex, #categoryLines do
        categoryLines[i]:Hide()
    end
end

local function SavePosition()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not point then return end
    Transmogio.db.point = point
    Transmogio.db.relativePoint = relativePoint
    Transmogio.db.x = x
    Transmogio.db.y = y
end

frame:SetScript("OnDragStart", function(self)
    if not Transmogio.db or Transmogio.db.locked then return end
    self:StartMoving()
end)

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)

local function ApplyLockState()
    if not Transmogio.db then return end
    -- EnableMouse(false) makes the frame fully click-through while pinned.
    frame:EnableMouse(not Transmogio.db.locked)
end
Transmogio.ApplyLockState = ApplyLockState

local function RestorePosition()
    local db = Transmogio.db
    frame:ClearAllPoints()
    frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
end
Transmogio.RestorePosition = RestorePosition

--------------------------------------------------------------------------------
-- Transmog counting
--------------------------------------------------------------------------------

-- Enum.TransmogCollectionType covers categories 1 (Head) through 29 (Paired).
-- Each GetCategoryAppearances call is wrapped in pcall since category
-- availability/validity can vary between client builds.
local NUM_CATEGORIES = 29

-- Fallback labels for when GetCategoryInfo returns an empty/nil name (happens
-- for some of the less common weapon categories), so every category always
-- gets a real label instead of "Category N".
local CATEGORY_NAMES = {
    [1] = "Head",
    [2] = "Shoulder",
    [3] = "Back",
    [4] = "Chest",
    [5] = "Shirt",
    [6] = "Tabard",
    [7] = "Wrist",
    [8] = "Hands",
    [9] = "Waist",
    [10] = "Legs",
    [11] = "Feet",
    [12] = "Wand",
    [13] = "One-Handed Axes",
    [14] = "One-Handed Swords",
    [15] = "One-Handed Maces",
    [16] = "Daggers",
    [17] = "Fist Weapons",
    [18] = "Shields",
    [19] = "Held In Off-hand",
    [20] = "Two-Handed Axes",
    [21] = "Two-Handed Swords",
    [22] = "Two-Handed Maces",
    [23] = "Staves",
    [24] = "Polearms",
    [25] = "Bows",
    [26] = "Guns",
    [27] = "Crossbows",
    [28] = "Warglaives",
    [29] = "Paired Weapons",
}

-- Returns totalCollected, totalPossible, categories where categories is an
-- array of { name, collected, total } for every non-empty category (skipping
-- categories your class/spec can't use at all, e.g. weapon types).
--
-- Uses the same dedicated per-category count functions Blizzard's own
-- Wardrobe UI reads to render its "collected / total" progress bar
-- (WardrobeItemsCollectionMixin:UpdateProgressBar), instead of manually
-- tallying C_TransmogCollection.GetCategoryAppearances -- that array isn't
-- pre-filtered to what your character can actually use (it includes every
-- armor-type variant of a slot), and guessing at which per-item flags
-- replicate the UI's own filtering proved unreliable.
local function RecountAppearances()
    if not C_TransmogCollection
        or not C_TransmogCollection.GetFilteredCategoryCollectedCount
        or not C_TransmogCollection.GetFilteredCategoryTotal then
        return nil, nil, nil
    end

    local totalCollected, totalPossible = 0, 0
    local categories = {}

    for categoryID = 1, NUM_CATEGORIES do
        local okTotal, catTotal = pcall(C_TransmogCollection.GetFilteredCategoryTotal, categoryID)
        local okCollected, catCollected = pcall(C_TransmogCollection.GetFilteredCategoryCollectedCount, categoryID)

        if okTotal and catTotal and catTotal > 0 then
            catCollected = (okCollected and catCollected) or 0
            totalPossible = totalPossible + catTotal
            totalCollected = totalCollected + catCollected

            local name
            if C_TransmogCollection.GetCategoryInfo then
                local okName, categoryName = pcall(C_TransmogCollection.GetCategoryInfo, categoryID)
                if okName and categoryName and categoryName ~= "" then
                    name = categoryName
                end
            end

            categories[#categories + 1] = {
                name = name or CATEGORY_NAMES[categoryID] or ("Category " .. categoryID),
                collected = catCollected,
                total = catTotal,
            }
        end
    end

    return totalCollected, totalPossible, categories
end

-- Only the collected counts are shown for now -- the "total possible"
-- figures from GetFilteredCategoryTotal still don't reliably match the
-- Wardrobe window, while the collected counts do.
local function RenderDisplay(collected, possible, categories)
    if not collected then
        text:SetText("Mog: n/a")
        HideCategoryLinesFrom(1)
        frame:SetSize(160, 20)
        return
    end

    text:SetText(string.format("Mog: %s", FormatNumber(collected)))

    local width = text:GetStringWidth()
    local height = text:GetStringHeight()

    if Transmogio.db and Transmogio.db.expanded then
        for i, categoryData in ipairs(categories) do
            local line = GetOrCreateCategoryLine(i)
            line:SetText(string.format("%s: %s", categoryData.name, FormatNumber(categoryData.collected)))
            line:Show()
            width = math.max(width, line:GetStringWidth())
            height = height + line:GetStringHeight() + 2
        end
        HideCategoryLinesFrom(#categories + 1)
    else
        HideCategoryLinesFrom(1)
    end

    frame:SetSize(math.max(width + 10, 40), math.max(height, 20))
end

local function UpdateDisplay()
    local collected, possible, categories = RecountAppearances()
    RenderDisplay(collected, possible, categories)
    return collected, possible, categories
end
Transmogio.UpdateDisplay = UpdateDisplay

toggleButton:SetScript("OnClick", function()
    Transmogio.db.expanded = not Transmogio.db.expanded
    UpdateToggleGlyph()
    UpdateDisplay()
end)

-- Debounced refresh so back-to-back events (e.g. several appearances
-- collected at once) don't trigger a full recount per event.
local updatePending = false
local function RequestUpdate()
    if updatePending then return end
    updatePending = true
    C_Timer.After(0.5, function()
        updatePending = false
        UpdateDisplay()
    end)
end
Transmogio.RequestUpdate = RequestUpdate

-- Blizzard's own Wardrobe UI checks this (see WardrobeCollectionFrameMixin)
-- before trusting collection data, and refreshes when the client fires
-- SEARCH_DB_LOADED. That's the real signal for "the collection database has
-- finished loading" -- far more reliable than guessing with a poll loop.
local function IsCollectionDataReady()
    if not C_TransmogCollection or not C_TransmogCollection.IsSearchDBLoading then
        return true
    end
    local ok, loading = pcall(C_TransmogCollection.IsSearchDBLoading)
    return ok and not loading
end
Transmogio.IsCollectionDataReady = IsCollectionDataReady

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end

        TransmogioDB = TransmogioDB or {}
        for key, value in pairs(DEFAULTS) do
            if TransmogioDB[key] == nil then
                TransmogioDB[key] = value
            end
        end
        Transmogio.db = TransmogioDB

        RestorePosition()
        ApplyLockState()
        UpdateToggleGlyph()

        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
        self:RegisterEvent("SEARCH_DB_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        if IsCollectionDataReady() then
            RequestUpdate()
        else
            -- SEARCH_DB_LOADED will fire and trigger the recount below.
            -- This one-shot timer is just a safety net in case that event
            -- doesn't fire on some client/build.
            C_Timer.After(8, RequestUpdate)
        end
    elseif event == "SEARCH_DB_LOADED" or event == "TRANSMOG_COLLECTION_UPDATED" then
        RequestUpdate()
    end
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

SLASH_TRANSMOGIO1 = "/tmo"
SLASH_TRANSMOGIO2 = "/transmogio"
SlashCmdList["TRANSMOGIO"] = function(msg)
    local cmd = (msg or ""):match("^%s*(%S*)"):lower()

    if cmd == "lock" or cmd == "pin" then
        Transmogio.db.locked = true
        ApplyLockState()
        Print("Locked in place. Mouse clicks now pass through.")
    elseif cmd == "unlock" then
        Transmogio.db.locked = false
        ApplyLockState()
        Print("Unlocked. Left-click and drag to reposition.")
    elseif cmd == "refresh" then
        UpdateDisplay()
        Print("Recounted transmog appearances.")
    elseif cmd == "expand" or cmd == "maximize" then
        Transmogio.db.expanded = true
        UpdateToggleGlyph()
        UpdateDisplay()
    elseif cmd == "collapse" or cmd == "minimize" then
        Transmogio.db.expanded = false
        UpdateToggleGlyph()
        UpdateDisplay()
    elseif cmd == "reset" then
        Transmogio.db.point = DEFAULTS.point
        Transmogio.db.relativePoint = DEFAULTS.relativePoint
        Transmogio.db.x = DEFAULTS.x
        Transmogio.db.y = DEFAULTS.y
        RestorePosition()
        Print("Position reset to center of screen.")
    else
        Print("Commands: /tmo lock|pin, /tmo unlock, /tmo refresh, /tmo expand, /tmo collapse, /tmo reset")
    end
end
