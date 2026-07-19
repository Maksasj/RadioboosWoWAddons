local _, Grouperio = ...

local function FindSetID(frame)
    if type(frame.setID) == "number" then
        return frame.setID
    end
    if type(frame.data) == "table" and type(frame.data.setID) == "number" then
        return frame.data.setID
    end
    if type(frame.elementData) == "table" and type(frame.elementData.setID) == "number" then
        return frame.elementData.setID
    end
    return nil
end

local function CollectRows(frame, depth, results)
    depth = depth or 0
    if depth > 6 or not frame or not frame.GetObjectType then
        return
    end

    local setID = FindSetID(frame)
    if setID and frame.CreateTexture then
        table.insert(results, { frame = frame, setID = setID })
    end

    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            CollectRows(child, depth + 1, results)
        end
    end
end

function Grouperio:DecorateVisibleRows(setsFrame)
    local rows = {}
    CollectRows(setsFrame, 0, rows)

    local enabled = Grouperio.db and Grouperio.db.colorCodingEnabled
    for _, entry in ipairs(rows) do
        local row, setID = entry.frame, entry.setID

        if not row.GrouperioColorBar then
            row.GrouperioColorBar = row:CreateTexture(nil, "OVERLAY")
            row.GrouperioColorBar:SetWidth(3)
            row.GrouperioColorBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.GrouperioColorBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        end

        if enabled then
            local expansionID = Grouperio:GetSetExpansionID(setID)
            local data = Grouperio:GetExpansionData(expansionID)
            row.GrouperioColorBar:SetColorTexture(data.color[1], data.color[2], data.color[3], 0.9)
            row.GrouperioColorBar:Show()
        else
            row.GrouperioColorBar:Hide()
        end
    end
end

function Grouperio:AttachToSetsFrame(setsFrame)
    local ticker = CreateFrame("Frame")
    local elapsed = 0
    ticker:Hide()
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.2 then
            return
        end
        elapsed = 0
        Grouperio:DecorateVisibleRows(setsFrame)
    end)

    setsFrame:HookScript("OnShow", function()
        ticker:Show()
        Grouperio:DecorateVisibleRows(setsFrame)
    end)
    setsFrame:HookScript("OnHide", function()
        ticker:Hide()
    end)

    if setsFrame:IsShown() then
        ticker:Show()
    end

    Grouperio.setsFrame = setsFrame

    if setsFrame.Refresh then
        hooksecurefunc(setsFrame, "Refresh", function()
            Grouperio:ApplyExpansionFilter()
        end)
    end

    Grouperio:CreateExpansionFilterDropdown(setsFrame)
    Grouperio:ApplyExpansionFilter()
end

function Grouperio:RefreshSetsUI()
    if Grouperio.setsFrame then
        Grouperio:DecorateVisibleRows(Grouperio.setsFrame)
    end
end

function Grouperio:TryAttach()
    if Grouperio.attached then
        return
    end
    if not (WardrobeCollectionFrame and WardrobeCollectionFrame.SetsCollectionFrame) then
        return
    end

    local ok, err = pcall(function()
        Grouperio:AttachToSetsFrame(WardrobeCollectionFrame.SetsCollectionFrame)
    end)
    if not ok then
        Grouperio.Print("Attach failed: " .. tostring(err))
        return
    end

    Grouperio.attached = true
end

local function KeysString(frame, label)
    if not frame then
        return label .. ": nil"
    end
    local keys = {}
    for k, v in pairs(frame) do
        table.insert(keys, tostring(k) .. ":" .. type(v))
    end
    table.sort(keys)
    return label .. " (" .. #keys .. " keys): " .. table.concat(keys, ", ")
end

local function EnsureCopyBox()
    if Grouperio.copyBox then
        return Grouperio.copyBox
    end

    local box = CreateFrame("Frame", "GrouperioCopyBox", UIParent, "BackdropTemplate")
    box:SetSize(560, 420)
    box:SetPoint("CENTER")
    box:SetFrameStrata("DIALOG")
    box:SetMovable(true)
    box:EnableMouse(true)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", box.StartMoving)
    box:SetScript("OnDragStop", box.StopMovingOrSizing)
    box:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    box:SetBackdropColor(0, 0, 0, 1)

    local title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Grouperio - Ctrl+A then Ctrl+C to copy")

    local closeButton = CreateFrame("Button", nil, box, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -4, -4)
    closeButton:SetScript("OnClick", function()
        box:Hide()
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -34)
    scrollFrame:SetPoint("BOTTOMRIGHT", -34, 16)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(500)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function()
        box:Hide()
    end)
    scrollFrame:SetScrollChild(editBox)

    box.editBox = editBox
    Grouperio.copyBox = box
    return box
end

function Grouperio:ShowCopyBox(text)
    local box = EnsureCopyBox()
    box.editBox:SetText(text)
    box:Show()
    box.editBox:SetFocus()
    box.editBox:HighlightText()
end

function Grouperio:ScanSetsAPI()
    local lines = {}
    local function Log(msg)
        table.insert(lines, msg)
        Grouperio.Print(msg)
    end

    Log("--- scan start ---")
    Log("WardrobeCollectionFrame: " .. tostring(WardrobeCollectionFrame ~= nil))

    local setsFrame = WardrobeCollectionFrame and WardrobeCollectionFrame.SetsCollectionFrame
    Log("SetsCollectionFrame: " .. tostring(setsFrame ~= nil))
    if setsFrame then
        Log(KeysString(setsFrame.ListContainer, "  ListContainer"))
        local listContainer = setsFrame.ListContainer
        local scrollBox = listContainer and (listContainer.ScrollBox or listContainer.ScrollTarget)
        Log("  ListContainer.ScrollBox present: " .. tostring(listContainer and listContainer.ScrollBox ~= nil))
        Log(KeysString(scrollBox, "  ListContainer.ScrollBox"))
        if scrollBox and scrollBox.GetDataProvider then
            local ok, provider = pcall(scrollBox.GetDataProvider, scrollBox)
            Log("  GetDataProvider() ok=" .. tostring(ok))
            if ok and provider then
                Log(KeysString(provider, "  DataProvider"))
                if provider.GetSize then
                    local ok2, size = pcall(provider.GetSize, provider)
                    Log("  DataProvider:GetSize() = " .. tostring(ok2 and size))
                end
            end
        end
    end

    if C_TransmogSets and C_TransmogSets.GetSetsFilter then
        local ok, filter = pcall(C_TransmogSets.GetSetsFilter)
        Log("GetSetsFilter() ok=" .. tostring(ok) .. " type=" .. type(filter))
        if ok and type(filter) == "table" then
            local parts = {}
            for k, v in pairs(filter) do
                table.insert(parts, tostring(k) .. "=" .. tostring(v))
            end
            Log("  filter contents: " .. table.concat(parts, ", "))
        end
    end

    if Enum and Enum.TransmogSetFilter then
        local parts = {}
        for k, v in pairs(Enum.TransmogSetFilter) do
            table.insert(parts, tostring(k) .. "=" .. tostring(v))
        end
        Log("Enum.TransmogSetFilter: " .. table.concat(parts, ", "))
    else
        Log("Enum.TransmogSetFilter: nil")
    end

    Log(KeysString(C_TransmogSets, "C_TransmogSets"))

    if C_TransmogSets and C_TransmogSets.GetAllSets then
        local ok, sets = pcall(C_TransmogSets.GetAllSets)
        if ok and sets then
            Log("GetAllSets() returned " .. #sets .. " sets")
            for i = 1, math.min(3, #sets) do
                local fields = {}
                for k, v in pairs(sets[i]) do
                    table.insert(fields, tostring(k) .. "=" .. tostring(v))
                end
                Log("  set[" .. i .. "]: " .. table.concat(fields, ", "))
            end
        else
            Log("GetAllSets() failed or returned nil")
        end
    else
        Log("C_TransmogSets.GetAllSets not available")
    end

    if setsFrame then
        local rows = {}
        CollectRows(setsFrame, 0, rows)
        Log("Row-like frames found (with setID field): " .. #rows)
        if rows[1] then
            Log(KeysString(rows[1].frame, "  sample row"))
        end
    end

    Log("--- scan end ---")

    Grouperio:ShowCopyBox(table.concat(lines, "\n"))
end

local attachAttemptFrame = CreateFrame("Frame")
attachAttemptFrame:RegisterEvent("ADDON_LOADED")
attachAttemptFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
attachAttemptFrame:SetScript("OnEvent", function()
    if Grouperio.attached then
        attachAttemptFrame:UnregisterAllEvents()
        return
    end
    Grouperio:TryAttach()
    if Grouperio.attached then
        attachAttemptFrame:UnregisterAllEvents()
    end
end)
