-- ============================================================
-- Queue window controls
-- ============================================================
--
-- Builds shared queue controls and measures their icons, headers and scroll
-- content.

local NS = _G.AzerothWaypointNS
NS.Internal = NS.Internal or {}
NS.Internal.QueueUI = NS.Internal.QueueUI or {}
local M = NS.Internal.QueueUI
local ui = M.ui
local FW = NS.Internal.Interface and NS.Internal.Interface.Framework

M.BULK_DELETE_RIGHT_INSET = 18

local _iconKeyParts = {}

local function GetNativeOverlay()
    return NS.Internal and NS.Internal.WorldOverlay or nil
end

local function NormalizeQueueIconSpec(iconDef)
    if type(iconDef) ~= "table" then
        return nil
    end
    if iconDef.atlas or iconDef.texture then
        return iconDef
    end
    if type(iconDef.icon) == "string" then
        return {
            texture = iconDef.icon,
            tint = iconDef.iconTint,
            key = iconDef.key or iconDef.displayName or iconDef.icon,
            recolor = iconDef.recolor,
        }
    end
    return nil
end

local function BuildIconSpecKey(iconDef)
    if type(iconDef) ~= "table" then
        return nil
    end
    local tint = type(iconDef.tint) == "table" and iconDef.tint or nil
    _iconKeyParts[1] = tostring(iconDef.key or "")
    _iconKeyParts[2] = tostring(iconDef.atlas or "")
    _iconKeyParts[3] = tostring(iconDef.texture or "")
    _iconKeyParts[4] = tostring(iconDef.recolor == true)
    _iconKeyParts[5] = tostring(tint and tint.r or "")
    _iconKeyParts[6] = tostring(tint and tint.g or "")
    _iconKeyParts[7] = tostring(tint and tint.b or "")
    _iconKeyParts[8] = tostring(tint and tint.a or "")
    return table.concat(_iconKeyParts, "\031", 1, 8)
end

function M.ApplyQueueIcon(texture, iconDef, size)
    if not texture then
        return false
    end
    iconDef = NormalizeQueueIconSpec(iconDef)
    if not iconDef then
        texture._awpQueueIconKey = nil
        texture:Hide()
        return false
    end

    local iconKey = BuildIconSpecKey(iconDef)
    texture:SetSize(size or 16, size or 16)
    if texture._awpQueueIconKey ~= iconKey then
        local native = GetNativeOverlay()
        if native and type(native.SetIconTexture) == "function" then
            native.SetIconTexture(texture, iconDef)
        elseif iconDef.atlas then
            texture:SetTexCoord(0, 1, 0, 1)
            texture:SetAtlas(iconDef.atlas, false, true)
            if type(texture.SetDesaturated) == "function" then
                texture:SetDesaturated(false)
            end
            texture:SetVertexColor(1, 1, 1, 1)
        else
            texture:SetTexture(iconDef.texture)
            texture:SetTexCoord(0, 1, 0, 1)
            if type(texture.SetDesaturated) == "function" then
                texture:SetDesaturated(iconDef.recolor == true)
            end
            local tint = type(iconDef.tint) == "table" and iconDef.tint or nil
            texture:SetVertexColor(tint and tint.r or 1, tint and tint.g or 1, tint and tint.b or 1, tint and tint.a or 1)
        end
        texture._awpQueueIconKey = iconKey
    end
    texture:Show()
    return true
end

M.DETAIL_HEADER_TEXT_TOP_OFFSET = -34
local DETAIL_HEADER_TEXT_TOP_OFFSET = M.DETAIL_HEADER_TEXT_TOP_OFFSET
M.DETAIL_HEADER_TEXT_GAP = 4
local DETAIL_HEADER_TEXT_GAP = M.DETAIL_HEADER_TEXT_GAP
M.DETAIL_HEADER_ICON_SIZE = 28
local DETAIL_HEADER_ICON_SIZE = M.DETAIL_HEADER_ICON_SIZE
M.DETAIL_HEADER_ICON_LEFT = 12
local DETAIL_HEADER_ICON_LEFT = M.DETAIL_HEADER_ICON_LEFT
M.DETAIL_HEADER_ICON_TEXT_GAP = 8
local DETAIL_HEADER_ICON_TEXT_GAP = M.DETAIL_HEADER_ICON_TEXT_GAP
local DETAIL_HEADER_ICON_CENTER_X = DETAIL_HEADER_ICON_LEFT + (DETAIL_HEADER_ICON_SIZE * 0.5)

-- ============================================================
-- Header and scroll measurements
-- ============================================================

local function GetVisibleFontStringHeight(fontString, fallback)
    if not fontString or (type(fontString.IsShown) == "function" and not fontString:IsShown()) then
        return 0
    end

    local height = type(fontString.GetStringHeight) == "function" and fontString:GetStringHeight() or nil
    if type(height) == "number" and height > 0 then
        return height
    end
    return fallback or 14
end

function M.LayoutDetailHeaderIdentity(content, iconShown)
    if type(content) ~= "table" or not content.detailHeader or not content.detailHeadline then
        return
    end

    local textLeft = iconShown
        and (DETAIL_HEADER_ICON_LEFT + DETAIL_HEADER_ICON_SIZE + DETAIL_HEADER_ICON_TEXT_GAP)
        or 12
    content.detailHeadline:ClearAllPoints()
    content.detailHeadline:SetPoint("TOPLEFT", content.detailHeader, "TOPLEFT", textLeft, DETAIL_HEADER_TEXT_TOP_OFFSET)
    content.detailHeadline:SetPoint("RIGHT", content.detailHeader, "RIGHT", -36, 0)

    if iconShown and content.detailIcon then
        local blockHeight = GetVisibleFontStringHeight(content.detailHeadline, 16)
        if content.detailSubline and content.detailSubline:IsShown() then
            blockHeight = blockHeight + DETAIL_HEADER_TEXT_GAP + GetVisibleFontStringHeight(content.detailSubline, 14)
        end
        if content.detailHint and content.detailHint:IsShown() then
            blockHeight = blockHeight + DETAIL_HEADER_TEXT_GAP + GetVisibleFontStringHeight(content.detailHint, 14)
        end

        content.detailIcon:ClearAllPoints()
        content.detailIcon:SetPoint(
            "CENTER",
            content.detailHeader,
            "TOPLEFT",
            DETAIL_HEADER_ICON_CENTER_X,
            DETAIL_HEADER_TEXT_TOP_OFFSET - (blockHeight * 0.5)
        )
    end
end


function M.GetScrollContentWidth(scrollFrame, minimumWidth)
    local width = type(scrollFrame) == "table" and scrollFrame:GetWidth() or 0
    return math.max(math.floor(width or 0), minimumWidth or 1)
end

function M.CreateQueueBorder(parent)
    -- Standalone queues can open before the client has built its quest log.
    local questLogLoaded = rawget(_G, "QuestMapFrame") ~= nil
    local border = CreateFrame("Frame", nil, parent, questLogLoaded and "QuestLogBorderFrameTemplate" or nil)
    border:SetAllPoints()
    if not questLogLoaded then
        local frame = border:CreateTexture(nil, "BORDER")
        frame:SetAtlas("questlog-frame")
        frame:SetAllPoints()
        local detail = border:CreateTexture(nil, "ARTWORK")
        detail:SetAtlas("questlog-frame-filigree", true)
        detail:SetPoint("TOP", 0, 1)
    end
    return border
end

-- ============================================================
-- Borders and shared controls
-- ============================================================

function M.CreateInsetBorder(parent)
    local border = M.CreateQueueBorder(parent)
    local appearance = NS.Internal.Appearance
    if appearance then
        appearance.Shell(parent, "windows.queue", { border }, nil, "inset")
    end
    return border
end

local function UpdateSectionArt(row, isSection)
    local appearance = NS.Internal.Appearance
    if not appearance then return end
    local record = appearance.visuals[row]
    if record then
        -- Both views reuse their rows for headers and ordinary entries.
        local useNativeArt = not isSection
        if record.useNativeArt ~= useNativeArt then
            record.useNativeArt = useNativeArt
            appearance.UpdateVisual(row)
        end
    elseif isSection then
        appearance.RegisterVisual(row, {
            kind = "sectionHeader", surface = "windows.queue", useNativeArt = false,
            regions = { row.bg, row:GetHighlightTexture() },
        })
    end
end

function M.UpdateSectionAppearance(row, collapsed, onClick)
    UpdateSectionArt(row, collapsed ~= nil)
    local button = row.disclosure
    if collapsed == nil then
        if button then button:Hide() end
        return
    end
    if not button then
        button = FW.CreateDisclosureButton(row, 20)
        button:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        button:RegisterForClicks("LeftButtonUp")
        button:SetScript("OnClick", function(self) onClick(self:GetParent()) end)
        row.disclosure = button
    end
    button:SetCollapsed(collapsed)
    button:Show()
    return button
end


function M.CreateContextMenuButton(rootDescription, text, callback, enabled)
    local elementDescription = rootDescription:CreateButton(text, callback)
    if enabled == false and elementDescription and type(elementDescription.SetEnabled) == "function" then
        elementDescription:SetEnabled(false)
    end
    return elementDescription
end

function M.AddContextMenuDivider(rootDescription)
    if type(rootDescription.CreateDivider) == "function" then
        rootDescription:CreateDivider()
    end
end

function M.SetContentPageBounds(page, bottomInset)
    if not page or not ui.content then
        return
    end

    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", ui.content, "TOPLEFT", 12, -42)
    page:SetPoint("BOTTOMRIGHT", ui.content, "BOTTOMRIGHT", -12, bottomInset or 12)
end

function M.StyleQueueButton(button)
    local appearance = NS.Internal.Appearance
    if not appearance then return end
    local regions = {}
    -- UIPanelButtonTemplate also draws its three-piece background as texture layers.
    for _, region in ipairs({ button:GetRegions() }) do
        if region:GetObjectType() == "Texture" then
            regions[#regions + 1] = region
        end
    end
    appearance.RegisterVisual(button, {
        kind = "button", surface = "windows.queue", text = button:GetFontString(), regions = regions,
    })
end

function M.ReflowFooterButtons(viewMode, selectedQueue, queueType)
    if not ui.content then
        return 0
    end

    local visibleButtons = {}
    local availableWidth = math.max((ui.content:GetWidth() or 0) - 24, 160)
    local function addButton(button, width)
        if button and button:IsShown() then
            button:SetWidth(math.min(width, availableWidth))
            visibleButtons[#visibleButtons + 1] = button
        end
    end

    if viewMode == "detail" and type(selectedQueue) == "table" then
        if queueType == "manual" then
            addButton(ui.content.useButton, 96)
        end
        addButton(ui.content.clearButton, 60)
        addButton(ui.content.exportButton, 78)
    else
        addButton(ui.content.importButton, 72)
        addButton(ui.content.exportButton, 84)
        addButton(ui.content.questsButton, 84)
    end

    if #visibleButtons == 0 then
        return 0
    end

    -- Group buttons into rows, then center each row horizontally.
    local rows = {}
    local curRow = { width = 0 }
    rows[1] = curRow
    for index = 1, #visibleButtons do
        local btn = visibleButtons[index]
        local w = btn:GetWidth() or 0
        local gap = curRow.width > 0 and 6 or 0
        if curRow.width > 0 and curRow.width + gap + w > availableWidth then
            curRow = { width = 0 }
            rows[#rows + 1] = curRow
        end
        gap = curRow.width > 0 and 6 or 0
        curRow[#curRow + 1] = btn
        curRow.width = curRow.width + gap + w
    end

    local bottom = 12
    local totalHeight = 0

    for rowIndex = 1, #rows do
        local row = rows[rowIndex]
        -- Center this row within the available area (left margin = 12).
        local startX = math.floor(12 + (availableWidth - row.width) / 2)
        local cursorX = startX
        local rowHeight = 0

        for btnIndex = 1, #row do
            local btn = row[btnIndex]
            local w = btn:GetWidth() or 0
            local h = btn:GetHeight() or 24
            btn:ClearAllPoints()
            btn:SetPoint("BOTTOMLEFT", ui.content, "BOTTOMLEFT", cursorX, bottom + totalHeight)
            cursorX = cursorX + w + 6
            if h > rowHeight then rowHeight = h end
        end

        totalHeight = totalHeight + rowHeight
        if rowIndex < #rows then
            totalHeight = totalHeight + 6
        end
    end

    return totalHeight
end

-- ============================================================
-- Bulk selection controls
-- ============================================================

function M.UpdateBulkDeleteButton(selectedQueue, queueType, viewMode)
    local button = ui.content and ui.content.bulkDeleteButton or nil
    if not button then
        return
    end

    local count = 0
    local enabled = false
    local anchorFrame = ui.content.listPage
    if viewMode == "detail"
        and queueType == "manual"
        and type(selectedQueue) == "table"
        and type(selectedQueue.id) == "string"
    then
        count = #M.GetSelectedQueueItemIndexes(selectedQueue.id)
        enabled = count > 0 and type(NS.RemoveQueueItems) == "function"
        button.deleteMode = "items"
        button.queueKey = selectedQueue.id
        anchorFrame = ui.content.summaryPanel or ui.content.detailPage
    else
        count = #M.GetSelectedQueueIDs()
        enabled = count > 0 and type(NS.ClearQueuesByID) == "function"
        button.deleteMode = "queues"
        button.queueKey = nil
    end

    button.deleteCount = count
    button:SetShown(count > 0)
    button:SetEnabled(enabled)
    button:SetAlpha(enabled and 1 or 0.45)
    if count <= 0 then
        return
    end

    button:ClearAllPoints()
    button:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -M.BULK_DELETE_RIGHT_INSET, 14)
end
