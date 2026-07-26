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

-- Formats a signed count, e.g. 3 -> "+3", -2 -> "-2", 0 -> "+0"
local function FormatSigned(n)
    n = math.floor((n or 0) + 0.5)
    if n >= 0 then
        return "+" .. FormatNumber(n)
    end
    return FormatNumber(n)
end

-- Formats a collected/possible ratio as a percentage string, e.g. "21.734"
local function FormatPercent(collected, possible)
    if not possible or possible <= 0 then
        return "0.000"
    end
    return string.format("%.3f", (collected / possible) * 100)
end

-- Formats a count/elapsed-seconds pair as an hourly rate, e.g. "23.7/hr"
local function FormatRate(count, elapsedSeconds)
    if not elapsedSeconds or elapsedSeconds <= 0 then
        return "0.0/hr"
    end
    return string.format("%.1f/hr", count / (elapsedSeconds / 3600))
end

-- Formats a duration in seconds as a compact elapsed string, e.g. "5m 32s"
local function FormatElapsed(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, secs)
    else
        return string.format("%ds", secs)
    end
end

--------------------------------------------------------------------------------
-- Frame & display (no background, outlined text only)
--------------------------------------------------------------------------------

local MAIN_COLOR = { 0.85, 0.35, 0.95 } -- purple/pink
local CATEGORY_COLOR = { 0.45, 0.75, 1.0 } -- light blue

local frame = CreateFrame("Frame", "TransmogioFrame", UIParent)
frame:SetSize(220, 20)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")

local text = frame:CreateFontString(nil, "OVERLAY")
text:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
text:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
text:SetTextColor(MAIN_COLOR[1], MAIN_COLOR[2], MAIN_COLOR[3])
text:SetJustifyH("LEFT")
text:SetText("Transmogio: loading...")
frame.text = text

-- Always-visible clickable line: "Click to start session" when idle, or the
-- live delta + elapsed time (click to end) once a session is running.
local sessionText = frame:CreateFontString(nil, "OVERLAY")
sessionText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -2)
sessionText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
sessionText:SetTextColor(MAIN_COLOR[1], MAIN_COLOR[2], MAIN_COLOR[3])
sessionText:SetJustifyH("LEFT")
sessionText:Hide()
frame.sessionText = sessionText

-- Transparent click-catcher layered exactly over sessionText (SetAllPoints
-- keeps it in sync automatically as the text/frame resizes).
local sessionButton = CreateFrame("Button", nil, frame)
sessionButton:SetAllPoints(sessionText)
sessionButton:RegisterForClicks("LeftButtonUp")
sessionButton:SetScript("OnEnter", function()
    sessionText:SetTextColor(1, 1, 1)
end)
sessionButton:SetScript("OnLeave", function()
    sessionText:SetTextColor(MAIN_COLOR[1], MAIN_COLOR[2], MAIN_COLOR[3])
end)
sessionButton:Hide()

-- Always-visible line (not gated behind expand) showing the most recently
-- collected appearance and a live-counting elapsed time since then.
local lastItemText = frame:CreateFontString(nil, "OVERLAY")
lastItemText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -2)
lastItemText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
lastItemText:SetTextColor(MAIN_COLOR[1], MAIN_COLOR[2], MAIN_COLOR[3])
lastItemText:SetJustifyH("LEFT")
lastItemText:Hide()
frame.lastItemText = lastItemText

-- Lines stacked directly beneath the main summary, top to bottom, each shown
-- only conditionally -- re-anchors them to sit flush against whichever ones
-- are currently visible (no gaps left behind by a hidden line).
local stackedLines = { sessionText, lastItemText }

local function AnchorStackedLines()
    local anchor = text
    for _, line in ipairs(stackedLines) do
        if line:IsShown() then
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
            anchor = line
        end
    end
    return anchor
end

-- Small "+"/"-" toggle hugging the left edge of the summary line, independent
-- of the main frame's own mouse state so it still works while pinned/locked.
local toggleButton = CreateFrame("Button", nil, frame)
toggleButton:SetSize(14, 14)
toggleButton:SetPoint("RIGHT", frame, "LEFT", -2, 0)
toggleButton:RegisterForClicks("LeftButtonUp")

local toggleText = toggleButton:CreateFontString(nil, "OVERLAY")
toggleText:SetPoint("CENTER", toggleButton, "CENTER", 0, 0)
toggleText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
toggleText:SetTextColor(MAIN_COLOR[1], MAIN_COLOR[2], MAIN_COLOR[3])
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
        line:SetTextColor(CATEGORY_COLOR[1], CATEGORY_COLOR[2], CATEGORY_COLOR[3])
        line:SetJustifyH("LEFT")
        categoryLines[index] = line
    end

    line:ClearAllPoints()
    if index == 1 then
        line:SetPoint("TOPLEFT", AnchorStackedLines(), "BOTTOMLEFT", 0, -3)
    else
        line:SetPoint("TOPLEFT", categoryLines[index - 1], "BOTTOMLEFT", 0, CATEGORY_LINE_GAP)
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

-- GetFilteredCategoryTotal/GetFilteredCategoryCollectedCount only return
-- correct numbers for whichever category was last marked active via
-- SetSearchAndFilterCategory -- Blizzard's own WardrobeItemsCollectionMixin
-- calls that before every read (see SetActiveCategory in
-- Blizzard_Collections/Blizzard_Wardrobe.lua).
--
-- Critically, switching the active category kicks off an *asynchronous*
-- search recompute -- Blizzard's own UI never reads the filtered totals
-- right after calling SetSearchAndFilterCategory, it waits for the
-- TRANSMOG_SEARCH_UPDATED event (matching Enum.TransmogSearchType.Items and
-- the category just set) before trusting them (see OnSearchUpdate). Reading
-- immediately after the Set call returns 0 for everything, since the
-- recompute hasn't finished. C_TransmogCollection.IsSearchInProgress is used
-- as a fast-path check (categories with nothing to recompute settle
-- instantly, e.g. weapon types the current class can't use) so this doesn't
-- have to wait a full event round-trip for every one of the 29 categories.
local searchUpdateFrame = CreateFrame("Frame")
searchUpdateFrame:Hide()
searchUpdateFrame:RegisterEvent("TRANSMOG_SEARCH_UPDATED")

local pendingCategoryID
local pendingOnSettled

searchUpdateFrame:SetScript("OnEvent", function(_, _, searchType, category)
    if not pendingCategoryID then return end
    if Enum.TransmogSearchType and searchType ~= Enum.TransmogSearchType.Items then return end
    if category ~= pendingCategoryID then return end

    local callback = pendingOnSettled
    pendingCategoryID = nil
    pendingOnSettled = nil
    if callback then callback() end
end)

-- Safety net per category in case TRANSMOG_SEARCH_UPDATED never fires (e.g.
-- an unexpected client behavior we haven't seen) -- reads whatever is
-- available instead of stalling the recount forever.
local RECOUNT_CATEGORY_TIMEOUT = 0.5

local recounting = false
local rerunRequested = false

-- Walks all categories one at a time (never in parallel -- SetSearchAndFilterCategory
-- is single shared state, so overlapping recounts would corrupt each other's
-- reads), calling onComplete(totalCollected, totalPossible, categories) when
-- done. categories is an array of { name, collected, total } for every
-- non-empty category (skipping categories your class/spec can't use at all).
local function RecountAppearancesAsync(onComplete)
    if recounting then
        rerunRequested = true
        return
    end

    if not C_TransmogCollection
        or not C_TransmogCollection.GetFilteredCategoryCollectedCount
        or not C_TransmogCollection.GetFilteredCategoryTotal
        or not C_TransmogCollection.SetSearchAndFilterCategory then
        onComplete(nil, nil, nil)
        return
    end

    recounting = true

    local totalCollected, totalPossible = 0, 0
    local categories = {}

    local ProcessCategory

    local function Finish()
        recounting = false
        onComplete(totalCollected, totalPossible, categories)
        if rerunRequested then
            rerunRequested = false
            RecountAppearancesAsync(onComplete)
        end
    end

    local function ReadCategory(categoryID)
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

        if categoryID >= NUM_CATEGORIES then
            Finish()
        else
            ProcessCategory(categoryID + 1)
        end
    end

    ProcessCategory = function(categoryID)
        pcall(C_TransmogCollection.SetSearchAndFilterCategory, categoryID)

        local inProgress = false
        if C_TransmogCollection.IsSearchInProgress and Enum.TransmogSearchType then
            local ok, result = pcall(C_TransmogCollection.IsSearchInProgress, Enum.TransmogSearchType.Items)
            inProgress = ok and result
        end

        if not inProgress then
            ReadCategory(categoryID)
            return
        end

        pendingCategoryID = categoryID
        pendingOnSettled = function()
            ReadCategory(categoryID)
        end

        C_Timer.After(RECOUNT_CATEGORY_TIMEOUT, function()
            if pendingCategoryID == categoryID then
                pendingCategoryID = nil
                pendingOnSettled = nil
                ReadCategory(categoryID)
            end
        end)
    end

    ProcessCategory(1)
end

-- Resolves a display name for a visualID via its first available source.
local function GetAppearanceDisplayName(visualID)
    if not C_TransmogCollection or not C_TransmogCollection.GetAppearanceSources then
        return nil
    end
    local ok, sources = pcall(C_TransmogCollection.GetAppearanceSources, visualID)
    if not ok or not sources or not sources[1] then
        return nil
    end
    return sources[1].name
end

-- C_TransmogCollection.GetLatestAppearance() turned out to be nil in practice
-- (confirmed in-game) -- it's evidently a transient/notification-style value
-- (likely cleared once you've viewed the Wardrobe window), not a persistent
-- "most recently collected" record, so it can't be used here. Instead this
-- keeps its own snapshot of every collected visualID (built once per
-- session, from C_TransmogCollection.GetCategoryAppearances across all
-- categories) and diffs against it on every scan to find what's newly
-- collected. Isn't gated by the class-proficiency filtering concerns that
-- rule out GetCategoryAppearances for the total/collected *counts* --
-- isCollected on an individual entry is accurate regardless of that.
local collectedSnapshot -- nil until the first scan establishes a baseline

local function ScanForNewAppearance()
    if not Transmogio.db or not C_TransmogCollection or not C_TransmogCollection.GetCategoryAppearances then
        return
    end

    local isFirstScan = (collectedSnapshot == nil)
    local snapshot = collectedSnapshot or {}
    local newestVisualID

    for categoryID = 1, NUM_CATEGORIES do
        local ok, appearances = pcall(C_TransmogCollection.GetCategoryAppearances, categoryID)
        if ok and appearances then
            for _, appearanceInfo in ipairs(appearances) do
                if appearanceInfo.isCollected then
                    if not snapshot[appearanceInfo.visualID] then
                        newestVisualID = appearanceInfo.visualID
                    end
                    snapshot[appearanceInfo.visualID] = true
                end
            end
        end
    end

    collectedSnapshot = snapshot

    -- Don't alert on the baseline scan itself -- everything already
    -- collected looks "new" the first time, since there's nothing to diff
    -- against yet.
    if isFirstScan or not newestVisualID then
        return
    end

    Transmogio.db.lastAppearanceID = newestVisualID
    Transmogio.db.lastAppearanceName = GetAppearanceDisplayName(newestVisualID) or "Unknown Appearance"
    Transmogio.db.lastAppearanceTime = time()
end

-- "Today" resets at local midnight and is tracked in TransmogioDB so it
-- persists across relogs/reloads within the same day (a plain in-memory
-- session counter would reset on every reload instead).
local function GetTodayDateString()
    return date("%Y-%m-%d")
end

local function UpdateDailyBaseline(collected)
    if not Transmogio.db then return end
    local today = GetTodayDateString()
    if Transmogio.db.dailyDate ~= today then
        Transmogio.db.dailyDate = today
        Transmogio.db.dailyBaselineCollected = collected
    end
end

local function GetTodayDelta(collected)
    if not Transmogio.db or not Transmogio.db.dailyBaselineCollected then
        return 0
    end
    return collected - Transmogio.db.dailyBaselineCollected
end

-- Manual session tracking, started/stopped via /tmo startsession /tmo
-- stopsession. Persisted in TransmogioDB so an active session survives a
-- /reload. sessionDeltaCache holds the delta as of the last recount so the
-- 1-second ticker can keep the elapsed time live without re-running one.
local sessionDeltaCache = 0

local function IsSessionActive()
    return Transmogio.db and Transmogio.db.sessionActive
end

local function StartSession(collected)
    if not Transmogio.db then return end
    Transmogio.db.sessionActive = true
    Transmogio.db.sessionBaselineCollected = collected
    Transmogio.db.sessionStartTime = time()
    sessionDeltaCache = 0
end
Transmogio.StartSession = StartSession

local function StopSession()
    if not Transmogio.db then return end
    Transmogio.db.sessionActive = false
end
Transmogio.StopSession = StopSession

local function RecalculateFrameSize()
    local width = text:GetStringWidth()
    local height = text:GetStringHeight()

    for _, line in ipairs(stackedLines) do
        if line:IsShown() then
            width = math.max(width, line:GetStringWidth())
            height = height + line:GetStringHeight() + 2
        end
    end

    if Transmogio.db and Transmogio.db.expanded then
        for _, line in ipairs(categoryLines) do
            if line:IsShown() then
                width = math.max(width, line:GetStringWidth())
                height = height + line:GetStringHeight() + 2
            end
        end
    end

    frame:SetSize(math.max(width + 10, 40), math.max(height, 20))
end

-- Refreshes just the "last item" line's elapsed-time counter, driven by a
-- 1-second ticker so it keeps counting up without a full recount.
local function UpdateLastItemLine()
    if not Transmogio.db or not Transmogio.db.lastAppearanceName then
        lastItemText:Hide()
        return
    end

    local elapsed = time() - (Transmogio.db.lastAppearanceTime or time())
    lastItemText:SetText(string.format("Last: %s (%s ago)", Transmogio.db.lastAppearanceName, FormatElapsed(elapsed)))
    lastItemText:Show()
end

-- Refreshes the session line's elapsed time, same 1-second-ticker approach
-- as UpdateLastItemLine -- sessionDeltaCache only changes on an actual
-- recount, but the elapsed time keeps counting every tick. Always shown
-- (idle prompt when no session running, live stats once started) so it
-- doubles as the start/stop button via sessionButton overlaid on top of it.
local function UpdateSessionLine()
    if not IsSessionActive() then
        sessionText:SetText("Click to start session")
        sessionText:Show()
        sessionButton:Show()
        return
    end

    local elapsed = time() - (Transmogio.db.sessionStartTime or time())
    sessionText:SetText(string.format("Session: %s (%s, %s) - click to end", FormatSigned(sessionDeltaCache), FormatElapsed(elapsed), FormatRate(sessionDeltaCache, elapsed)))
    sessionText:Show()
    sessionButton:Show()
end

C_Timer.NewTicker(1, function()
    if not lastItemText:IsShown() and not sessionText:IsShown() then return end
    UpdateLastItemLine()
    UpdateSessionLine()
    AnchorStackedLines()
    RecalculateFrameSize()
end)

local function RenderDisplay(collected, possible, categories)
    if not collected then
        text:SetText("Mog: n/a")
        HideCategoryLinesFrom(1)
        frame:SetSize(160, 20)
        return
    end

    UpdateDailyBaseline(collected)
    local todayDelta = GetTodayDelta(collected)

    text:SetText(string.format("Mog: %s/%s (%s%%) [%s today]", FormatNumber(collected), FormatNumber(possible), FormatPercent(collected, possible), FormatSigned(todayDelta)))

    if IsSessionActive() then
        sessionDeltaCache = collected - (Transmogio.db.sessionBaselineCollected or collected)
    end
    UpdateSessionLine()
    UpdateLastItemLine()
    AnchorStackedLines()

    if Transmogio.db and Transmogio.db.expanded then
        for i, categoryData in ipairs(categories) do
            local line = GetOrCreateCategoryLine(i)
            line:SetText(string.format("%s: %s/%s (%s%%)", categoryData.name, FormatNumber(categoryData.collected), FormatNumber(categoryData.total), FormatPercent(categoryData.collected, categoryData.total)))
            line:Show()
        end
        HideCategoryLinesFrom(#categories + 1)
    else
        HideCategoryLinesFrom(1)
    end

    RecalculateFrameSize()
end

local function UpdateDisplay()
    ScanForNewAppearance()
    RecountAppearancesAsync(RenderDisplay)
end
Transmogio.UpdateDisplay = UpdateDisplay

-- Shared by both the /tmo startsession|stopsession commands and clicking
-- the session line itself.
local function DoStartSession()
    RecountAppearancesAsync(function(collected, possible, categories)
        StartSession(collected)
        RenderDisplay(collected, possible, categories)
        Print("Session started. Tracking new appearances from now.")
    end)
end

local function DoStopSession()
    if not IsSessionActive() then
        Print("No active session.")
        return
    end
    local delta = sessionDeltaCache
    local elapsed = time() - (Transmogio.db.sessionStartTime or time())
    StopSession()
    UpdateSessionLine()
    AnchorStackedLines()
    RecalculateFrameSize()
    Print(string.format("Session ended: %s appearances in %s (%s).", FormatSigned(delta), FormatElapsed(elapsed), FormatRate(delta, elapsed)))
end

sessionButton:SetScript("OnClick", function()
    if IsSessionActive() then
        DoStopSession()
    else
        DoStartSession()
    end
end)

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
        ScanForNewAppearance()
        RecountAppearancesAsync(function(collected, possible, categories)
            RenderDisplay(collected, possible, categories)
            Print("Recounted transmog appearances.")
        end)
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
    elseif cmd == "lastdebug" then
        local snapshotCount = 0
        if collectedSnapshot then
            for _ in pairs(collectedSnapshot) do
                snapshotCount = snapshotCount + 1
            end
        end
        Print(string.format("Snapshot: %s (%d collected visualIDs tracked)",
            collectedSnapshot and "built" or "not built yet", snapshotCount))
        Print(string.format("Saved: id=%s name=%s time=%s",
            tostring(Transmogio.db.lastAppearanceID), tostring(Transmogio.db.lastAppearanceName), tostring(Transmogio.db.lastAppearanceTime)))
    elseif cmd == "resettoday" then
        RecountAppearancesAsync(function(collected, possible, categories)
            Transmogio.db.dailyDate = GetTodayDateString()
            Transmogio.db.dailyBaselineCollected = collected
            RenderDisplay(collected, possible, categories)
            Print("Today's counter reset to +0.")
        end)
    elseif cmd == "startsession" then
        DoStartSession()
    elseif cmd == "stopsession" or cmd == "endsession" then
        DoStopSession()
    else
        Print("Commands: /tmo lock|pin, /tmo unlock, /tmo refresh, /tmo expand, /tmo collapse, /tmo reset, /tmo resettoday, /tmo startsession, /tmo stopsession, /tmo lastdebug")
    end
end
