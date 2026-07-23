local _, Auctiozimba = ...

-- Blizzard has been migrating StaticPopup fields from lowerCamelCase to
-- PascalCase (e.g. .Text on CheckButtons); the edit box field name isn't
-- consistent across client builds, so check both.
local function GetPopupEditBox(self)
    return self.editBox or self.EditBox
end

StaticPopupDialogs["AUCTIOZIMBA_NEW_FOLDER"] = {
    text = "Folder name:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnAccept = function(self)
        local editBox = GetPopupEditBox(self)
        local folder = Auctiozimba:CreateFolder(editBox and editBox:GetText())
        if folder then
            Auctiozimba:SelectFolder(folder.id)
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local folder = Auctiozimba:CreateFolder(self:GetText())
        if folder then
            Auctiozimba:SelectFolder(folder.id)
        end
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["AUCTIOZIMBA_RENAME_FOLDER"] = {
    text = "Rename folder to:",
    button1 = "Rename",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self, data)
        local editBox = GetPopupEditBox(self)
        if editBox then
            editBox:SetText(data.name)
            editBox:HighlightText()
        end
    end,
    OnAccept = function(self, data)
        local editBox = GetPopupEditBox(self)
        Auctiozimba:RenameFolder(data.id, editBox and editBox:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
        local data = self:GetParent().data
        Auctiozimba:RenameFolder(data.id, self:GetText())
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["AUCTIOZIMBA_DELETE_FOLDER"] = {
    text = "Delete folder '%s' and its saved items?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        Auctiozimba:DeleteFolder(data.id)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local PANEL_WIDTH = 220
local ROW_HEIGHT = 20

local function CreatePanel()
    local panel = CreateFrame("Frame", "AuctiozimbaPanel", AuctionHouseFrame, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, AuctionHouseFrame:GetHeight())
    panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 2, 0)
    panel:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.9)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Auctiozimba")

    local newFolderButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    newFolderButton:SetSize(100, 22)
    newFolderButton:SetPoint("TOP", title, "BOTTOM", 0, -8)
    newFolderButton:SetText("New Folder")
    newFolderButton:SetScript("OnClick", function()
        StaticPopup_Show("AUCTIOZIMBA_NEW_FOLDER")
    end)

    local filterCheckbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    filterCheckbox:SetPoint("TOPLEFT", newFolderButton, "BOTTOMLEFT", -4, -6)
    filterCheckbox.Text:SetText("Filter results to folder")
    filterCheckbox:SetScript("OnClick", function(self)
        Auctiozimba:SetFilterEnabled(self:GetChecked())
    end)
    panel.filterCheckbox = filterCheckbox

    local folderScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    folderScroll:SetPoint("TOPLEFT", filterCheckbox, "BOTTOMLEFT", 4, -10)
    folderScroll:SetPoint("RIGHT", panel, "RIGHT", -26, 0)
    folderScroll:SetHeight(150)

    local folderContent = CreateFrame("Frame", nil, folderScroll)
    folderContent:SetSize(PANEL_WIDTH - 40, 1)
    folderScroll:SetScrollChild(folderContent)
    panel.folderContent = folderContent
    panel.folderButtons = {}

    local sep = panel:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.15)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", folderScroll, "BOTTOMLEFT", -4, -8)
    sep:SetPoint("RIGHT", panel, "RIGHT", -8, 0)

    local itemsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemsLabel:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 4, -8)
    itemsLabel:SetText("Items (click to price-check, right-click to remove)")
    itemsLabel:SetWidth(PANEL_WIDTH - 30)
    itemsLabel:SetJustifyH("LEFT")
    itemsLabel:SetWordWrap(true)

    local itemScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    itemScroll:SetPoint("TOPLEFT", itemsLabel, "BOTTOMLEFT", -4, -6)
    itemScroll:SetPoint("RIGHT", panel, "RIGHT", -26, 0)
    itemScroll:SetPoint("BOTTOM", panel, "BOTTOM", 0, 60)

    local itemContent = CreateFrame("Frame", nil, itemScroll)
    itemContent:SetSize(PANEL_WIDTH - 40, 1)
    itemScroll:SetScrollChild(itemContent)
    panel.itemContent = itemContent
    panel.itemButtons = {}

    local addLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 50)
    addLabel:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
    addLabel:SetJustifyH("LEFT")
    addLabel:SetWordWrap(true)
    addLabel:SetText("Drag an item here (from bags/bank), or shift-click it then press Enter, to add it to the selected folder:")

    local addBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    addBox:SetSize(PANEL_WIDTH - 30, 20)
    addBox:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 20)
    addBox:SetAutoFocus(false)
    addBox:SetScript("OnEnterPressed", function(self)
        local folder = Auctiozimba:GetSelectedFolder()
        if not folder then
            Auctiozimba.Print("Select (or create) a folder first.")
        else
            Auctiozimba:AddItemLinkToFolder(folder.id, self:GetText())
        end
        self:SetText("")
        self:ClearFocus()
    end)
    addBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    addBox:SetScript("OnReceiveDrag", function(self)
        local folder = Auctiozimba:GetSelectedFolder()
        if not folder then
            Auctiozimba.Print("Select (or create) a folder first.")
            ClearCursor()
            return
        end
        Auctiozimba:AddCursorItemToFolder(folder.id)
    end)
    panel.addBox = addBox

    return panel
end

function Auctiozimba:GetPanel()
    if not self.panel then
        self.panel = CreatePanel()
        self.panel:Hide()
    end
    return self.panel
end

function Auctiozimba:ShowPanel()
    local panel = self:GetPanel()
    panel:Show()
    panel.filterCheckbox:SetChecked(self.db.filterEnabled)
    self:RefreshFolderListUI()
    self:RefreshItemListUI()
end

function Auctiozimba:HidePanel()
    if self.panel then
        self.panel:Hide()
    end
end

function Auctiozimba:TogglePanel()
    local panel = self:GetPanel()
    if panel:IsShown() then
        self:HidePanel()
    else
        self:ShowPanel()
    end
end

function Auctiozimba:RefreshFolderListUI()
    local panel = self.panel
    if not panel then
        return
    end

    local ok, err = pcall(function()
        self:_DrawFolderListUI(panel)
    end)
    if not ok then
        Auctiozimba.Print("Folder list failed to redraw: " .. tostring(err))
    end
end

function Auctiozimba:_DrawFolderListUI(panel)
    local folders = self:GetFolders()
    local buttons = panel.folderButtons

    for index, folder in ipairs(folders) do
        local button = buttons[index]
        if not button then
            button = CreateFrame("Button", nil, panel.folderContent)
            button:SetSize(PANEL_WIDTH - 40, ROW_HEIGHT)
            button:SetPoint("TOPLEFT", panel.folderContent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            button.highlight = button:CreateTexture(nil, "BACKGROUND")
            button.highlight:SetAllPoints()
            button.highlight:SetColorTexture(1, 1, 1, 0.12)
            button.highlight:Hide()

            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            button.text:SetPoint("LEFT", 4, 0)
            button.text:SetPoint("RIGHT", -4, 0)
            button.text:SetJustifyH("LEFT")

            buttons[index] = button
        else
            button:SetPoint("TOPLEFT", panel.folderContent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        end

        button:Show()
        button.folderID = folder.id
        button.text:SetText(folder.name .. " (" .. #folder.itemOrder .. ")")
        button.highlight:SetShown(self.db.selectedFolderID == folder.id)

        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" and MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(button, function(_, rootDescription)
                    rootDescription:CreateButton("Rename", function()
                        StaticPopup_Show("AUCTIOZIMBA_RENAME_FOLDER", nil, nil, { id = folder.id, name = folder.name })
                    end)
                    rootDescription:CreateButton("Delete", function()
                        StaticPopup_Show("AUCTIOZIMBA_DELETE_FOLDER", folder.name, nil, { id = folder.id })
                    end)
                end)
            else
                Auctiozimba:SelectFolder(folder.id)
            end
        end)
    end

    for index = #folders + 1, #buttons do
        buttons[index]:Hide()
    end

    panel.folderContent:SetHeight(math.max(1, #folders * ROW_HEIGHT))
end

local function SearchItem(itemID)
    if not (C_AuctionHouse and C_AuctionHouse.MakeItemKey and C_AuctionHouse.SendSearchQuery) then
        return
    end
    local ok, itemKey = pcall(C_AuctionHouse.MakeItemKey, itemID)
    if not ok or not itemKey then
        return
    end
    local sorts = {}
    if Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price then
        table.insert(sorts, { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false })
    end
    pcall(C_AuctionHouse.SendSearchQuery, itemKey, sorts, true)
end

function Auctiozimba:RefreshItemListUI()
    local panel = self.panel
    if not panel then
        return
    end

    local folder = self:GetSelectedFolder()
    local itemIDs = folder and folder.itemOrder or {}
    local buttons = panel.itemButtons

    for index, itemID in ipairs(itemIDs) do
        local button = buttons[index]
        if not button then
            button = CreateFrame("Button", nil, panel.itemContent)
            button:SetSize(PANEL_WIDTH - 40, ROW_HEIGHT)
            button:SetPoint("TOPLEFT", panel.itemContent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetSize(16, 16)
            button.icon:SetPoint("LEFT", 0, 0)

            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.text:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
            button.text:SetPoint("RIGHT", -4, 0)
            button.text:SetJustifyH("LEFT")

            buttons[index] = button
        else
            button:SetPoint("TOPLEFT", panel.itemContent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        end

        button:Show()
        button.itemID = itemID

        local cached = Auctiozimba:CacheItemInfo(itemID)
        if cached and cached.name then
            button.icon:SetTexture(cached.icon or 134400)
            button.text:SetText(cached.name)
        else
            button.icon:SetTexture(134400)
            button.text:SetText("Loading item " .. itemID .. "...")
        end

        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then
                if folder then
                    Auctiozimba:RemoveItemFromFolder(folder.id, itemID)
                end
            else
                SearchItem(itemID)
            end
        end)
    end

    for index = #itemIDs + 1, #buttons do
        buttons[index]:Hide()
    end

    panel.itemContent:SetHeight(math.max(1, #itemIDs * ROW_HEIGHT))
end
