local _, Auctiozimba = ...

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
    if Auctiozimba.copyBox then
        return Auctiozimba.copyBox
    end

    local box = CreateFrame("Frame", "AuctiozimbaCopyBox", UIParent, "BackdropTemplate")
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
    title:SetText("Auctiozimba - Ctrl+A then Ctrl+C to copy")

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
    Auctiozimba.copyBox = box
    return box
end

function Auctiozimba:ShowCopyBox(text)
    local box = EnsureCopyBox()
    box.editBox:SetText(text)
    box:Show()
    box.editBox:SetFocus()
    box.editBox:HighlightText()
end

function Auctiozimba:ScanAuctionHouseAPI()
    local lines = {}
    local function Log(msg)
        table.insert(lines, msg)
        Auctiozimba.Print(msg)
    end

    Log("--- scan start ---")
    Log("AuctionHouseFrame: " .. tostring(AuctionHouseFrame ~= nil))
    if AuctionHouseFrame then
        Log(KeysString(AuctionHouseFrame, "  AuctionHouseFrame"))

        local resultsFrame = AuctionHouseFrame.BrowseResultsFrame
        Log("  BrowseResultsFrame: " .. tostring(resultsFrame ~= nil))
        if resultsFrame then
            Log(KeysString(resultsFrame, "    BrowseResultsFrame"))
            local scrollBox = resultsFrame.ScrollBox
            Log("    ScrollBox present: " .. tostring(scrollBox ~= nil))
            if scrollBox and scrollBox.GetDataProvider then
                local ok, provider = pcall(scrollBox.GetDataProvider, scrollBox)
                Log("    GetDataProvider() ok=" .. tostring(ok))
                if ok and provider then
                    Log(KeysString(provider, "    DataProvider"))
                    if provider.GetSize then
                        local ok2, size = pcall(provider.GetSize, provider)
                        Log("    DataProvider:GetSize() = " .. tostring(ok2 and size))
                    end
                    if provider.Find then
                        local ok3, first = pcall(provider.Find, provider, 1)
                        if ok3 and first then
                            Log(KeysString(first, "    First row elementData"))
                        end
                    end
                end
            end
        end
    end
    Log("--- scan end ---")

    Auctiozimba:ShowCopyBox(table.concat(lines, "\n"))
end

local function AttachToAuctionHouse()
    if not AuctionHouseFrame or Auctiozimba.attached then
        return
    end

    AuctionHouseFrame:HookScript("OnShow", function()
        Auctiozimba:ShowPanel()
    end)
    AuctionHouseFrame:HookScript("OnHide", function()
        Auctiozimba:HidePanel()
    end)

    local resultsFrame = AuctionHouseFrame.BrowseResultsFrame
    if resultsFrame and resultsFrame.Refresh then
        hooksecurefunc(resultsFrame, "Refresh", function()
            Auctiozimba:ApplyFolderFilter()
        end)
    end

    Auctiozimba.attached = true

    if AuctionHouseFrame:IsShown() then
        Auctiozimba:ShowPanel()
    end
end

local attachFrame = CreateFrame("Frame")
attachFrame:RegisterEvent("ADDON_LOADED")
attachFrame:SetScript("OnEvent", function(self, event, name)
    if name ~= "Blizzard_AuctionHouseUI" then
        return
    end

    local ok, err = pcall(AttachToAuctionHouse)
    if not ok then
        Auctiozimba.Print("Attach failed: " .. tostring(err) .. " - try /azimba scan for details.")
    end
    self:UnregisterEvent("ADDON_LOADED")
end)

if AuctionHouseFrame then
    AttachToAuctionHouse()
end
