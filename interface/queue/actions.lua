-- ============================================================
-- Queue window commands
-- ============================================================
--
-- Handles queue window commands, including activation, removal, import and
-- export.

local NS = _G.AzerothWaypointNS
NS.Internal = NS.Internal or {}
NS.Internal.QueueUI = NS.Internal.QueueUI or {}
local M = NS.Internal.QueueUI
-- M.Refresh is assigned by panel.lua later in TOC order. These functions are
-- registered as callbacks and only run after every queue UI module has loaded.

function M.SelectQueue(key)
    if type(NS.SetQueuePanelSelection) == "function" then
        NS.SetQueuePanelSelection(key)
    end
end

function M.ActivateQueueDestination(queueID, itemIndex)
    itemIndex = tonumber(itemIndex)
    if type(queueID) ~= "string" or not itemIndex or type(NS.RouteQueueByID) ~= "function" then
        return false
    end
    return NS.RouteQueueByID(queueID, itemIndex)
end

local function CenterMapCanvas()
    return type(M.CenterMapCanvas) == "function" and M.CenterMapCanvas() or false
end

function M.FocusQueueFinalDestination(queue)
    local finalEntry = M.GetQueueFinalEntry(queue)
    if type(finalEntry) ~= "table" or type(finalEntry.mapID) ~= "number" then
        return false
    end

    local questMapFrame = type(M.EnsureWorldMapLoaded) == "function" and M.EnsureWorldMapLoaded() or nil
    local mapFrame = type(M.GetMapCanvasFrame) == "function" and M.GetMapCanvasFrame() or nil
    if not questMapFrame or not mapFrame or type(mapFrame.SetMapID) ~= "function" then
        return false
    end

    local mapID = finalEntry.mapID
    mapFrame:SetMapID(mapID)

    CenterMapCanvas()
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(0, CenterMapCanvas)
    end
    return true
end

function M.IsQueueUsableFromList(queueType)
    return queueType == "manual" or queueType == "guide"
end

function M.IsQueueClearableFromList(queueType)
    return queueType == "manual" or queueType == "transient"
end

function M.IsQueueDetailsToggleable(queue, queueType)
    return false
end

function M.OpenQueueDetails(queueKey)
    if type(queueKey) ~= "string" then
        return false
    end
    M.SelectQueue(queueKey)
    M.SetViewMode("detail")
    M.Refresh()
    return true
end

function M.UseQueueByKey(queueKey)
    if type(queueKey) ~= "string" then
        return false
    end
    if M.IsGuideQueueKey(queueKey) then
        if type(NS.ActivateGuideQueueByID) ~= "function" then
            return false
        end
        M.SelectQueue(queueKey)
        local ok = NS.ActivateGuideQueueByID(queueKey, "queue_ui")
        M.Refresh()
        return ok == true
    end
    if type(NS.SetActiveManualQueue) ~= "function" then
        return false
    end
    M.SelectQueue(queueKey)
    NS.SetActiveManualQueue(queueKey)
    M.Refresh()
    return true
end

function M.IsManualQueueActive(queueKey, snapshot)
    if type(queueKey) ~= "string" or M.IsGuideQueueKey(queueKey) then
        return false
    end

    local record = type(NS.GetManualAuthority) == "function" and NS.GetManualAuthority() or nil
    if type(record) == "table" then
        return record.queueID == queueKey
    end

    if type(snapshot) == "table" and snapshot.activeManualQueueID == queueKey then
        return true
    end

    if type(snapshot) == "table" then
        return false
    end

    snapshot = type(NS.GetQueuePanelSnapshot) == "function" and NS.GetQueuePanelSnapshot() or nil
    return type(snapshot) == "table" and snapshot.activeManualQueueID == queueKey
end

-- ============================================================
-- Stopping and clearing queues
-- ============================================================

function M.StopUsingQueueByKey(queueKey)
    if type(queueKey) ~= "string" or M.IsGuideQueueKey(queueKey) or type(NS.StopUsingManualQueue) ~= "function" then
        return false
    end
    M.SelectQueue(queueKey)
    NS.StopUsingManualQueue(queueKey)
    M.Refresh()
    return true
end

function M.ToggleQueueUseByKey(queueKey)
    if M.IsManualQueueActive(queueKey) then
        return M.StopUsingQueueByKey(queueKey)
    end
    return M.UseQueueByKey(queueKey)
end

function M.ClearQueueByKey(queueKey)
    if type(queueKey) ~= "string" or M.IsGuideQueueKey(queueKey) or type(NS.ClearQueueByID) ~= "function" then
        return false
    end

    local selectedKey = type(NS.GetQueuePanelSelection) == "function" and NS.GetQueuePanelSelection() or nil
    NS.ClearQueueByID(queueKey)
    if selectedKey == queueKey then
        if type(NS.SetQueuePanelSelection) == "function" then
            NS.SetQueuePanelSelection(nil)
        end
        M.SetViewMode("list")
    end
    M.Refresh()
    return true
end

function M.RemoveQueueDestination(queueKey, itemIndex)
    itemIndex = tonumber(itemIndex)
    if type(queueKey) ~= "string" or M.IsGuideQueueKey(queueKey) or not itemIndex or type(NS.RemoveQueueItem) ~= "function" then
        return false
    end

    NS.RemoveQueueItem(queueKey, itemIndex)
    M.Refresh()
    return true
end

function M.DeleteSelectedQueues()
    local queueIDs = M.GetSelectedQueueIDs()
    if #queueIDs == 0 or type(NS.ClearQueuesByID) ~= "function" then
        return false
    end

    local selectedKey = type(NS.GetQueuePanelSelection) == "function" and NS.GetQueuePanelSelection() or nil
    NS.ClearQueuesByID(queueIDs)
    local uiState = M.GetQueueUIState()
    for index = 1, #queueIDs do
        uiState.selectedQueues[queueIDs[index]] = nil
        uiState.selectedItems[queueIDs[index]] = nil
        if selectedKey == queueIDs[index] and type(NS.SetQueuePanelSelection) == "function" then
            NS.SetQueuePanelSelection(nil)
            M.SetViewMode("list")
        end
    end
    M.Refresh()
    return true
end

-- ============================================================
-- Bulk item removal
-- ============================================================

function M.DeleteSelectedQueueItems(queueKey)
    local itemIndexes = M.GetSelectedQueueItemIndexes(queueKey)
    if type(queueKey) ~= "string" or #itemIndexes == 0 or type(NS.RemoveQueueItems) ~= "function" then
        return false
    end

    NS.RemoveQueueItems(queueKey, itemIndexes)
    M.ClearQueueItemSelection(queueKey)
    M.Refresh()
    return true
end

function M.ToggleQueueDetailsByKey(queueKey)
    if type(queueKey) ~= "string" or M.IsGuideQueueKey(queueKey) or type(NS.ToggleQueueDetails) ~= "function" then
        return false
    end
    NS.ToggleQueueDetails(queueKey)
    M.Refresh()
    return true
end

function M.OpenImportWindow()
    if type(NS.OpenTomTomPasteWindow) == "function" then
        return NS.OpenTomTomPasteWindow()
    end
    if type(NS.Msg) == "function" then
        NS.Msg("TomTom paste window is unavailable.")
    end
    return false
end

function M.FormatWaypointExport(queues)
    local lines = {}
    for _, queue in ipairs(queues) do
        for _, item in ipairs(queue.items or {}) do
            local map, x, y = item.mapID, item.x, item.y
            if type(map) == "number" and map > 0 and map < math.huge and map % 1 == 0
                and type(x) == "number" and x >= 0 and x <= 1 and type(y) == "number" and y >= 0 and y <= 1 then
                local coords = ("/way #%d %.6f %.6f"):format(map, x * 100, y * 100):gsub(",", ".")
                local title = type(item.title) == "string" and item.title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    :gsub("%c+", " "):gsub("^%s+", ""):gsub("%s+$", "") or ""
                lines[#lines + 1] = title == "" and coords or (coords .. " " .. title)
            end
        end
    end
    return table.concat(lines, "\n")
end

local exportWindow

-- ============================================================
-- Export window and context menus
-- ============================================================

local function BuildExportWindow()
    local frame = CreateFrame("Frame", "AWPWaypointExport", UIParent)
    frame:SetSize(500, 320)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    local shell = NS.Internal.Interface.Framework.CreatePanelShell(frame, {
        title = "Export TomTom Waypoints", surface = "windows.queue", movable = true,
    })
    local message = shell.bodyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    message:SetPoint("TOPLEFT", 14, -12)
    message:SetText("Copy these lines and paste them into TomTom with /ttpaste.")
    local scroll = CreateFrame("ScrollFrame", nil, shell.bodyFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -36)
    scroll:SetPoint("BOTTOMRIGHT", -30, 14)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(450)
    edit:SetHeight(18)
    scroll:SetScrollChild(edit)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    edit:SetScript("OnTextChanged", function(self, fromUser)
        if fromUser and self:GetText() ~= frame.exportText then self:SetText(frame.exportText) end
    end)
    frame:SetScript("OnHide", function()
        edit:ClearFocus()
        edit:SetText("")
        frame.exportText = nil
    end)
    frame.edit = edit
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = frame:GetName() end
    return frame
end

function M.OpenExportWindow()
    local snapshot = NS.GetQueuePanelSnapshot()
    local queues = snapshot.manualQueues
    if M.GetViewMode() == "detail" then
        local queue, queueType = M.ResolveSelectedQueue(snapshot)
        if queueType ~= "manual" then return false end
        queues = { queue }
    end
    local text = M.FormatWaypointExport(queues)
    if text == "" then return false end
    exportWindow = exportWindow or BuildExportWindow()
    exportWindow.exportText = text
    exportWindow.edit:SetText(text)
    exportWindow:Show()
    exportWindow.edit:SetFocus()
    exportWindow.edit:HighlightText()
    return true
end

function M.ShowQueueDestinationContextMenu(owner, rowTitle, queueKey, itemIndex, removable)
    itemIndex = tonumber(itemIndex)
    if type(queueKey) ~= "string" or M.IsGuideQueueKey(queueKey) or not itemIndex then
        return false
    end

    if type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
        NS.Internal.Menus.CreateContextMenu(owner, function(_, rootDescription)
            if type(rootDescription.CreateTitle) == "function" then
                rootDescription:CreateTitle(tostring(rowTitle or "Queued Destination"))
            end

            M.CreateContextMenuButton(rootDescription, "Switch to this Destination", function()
                M.ActivateQueueDestination(queueKey, itemIndex)
                M.Refresh()
            end)

            if removable then
                M.AddContextMenuDivider(rootDescription)
                M.CreateContextMenuButton(rootDescription, "Remove Destination", function()
                    M.RemoveQueueDestination(queueKey, itemIndex)
                end)
            end
        end)
        return true
    end

    return false
end


function M.ShowQueueRowContextMenu(owner, queue, queueType, queueKey)
    if type(queueKey) ~= "string" or type(queue) ~= "table" then
        return false
    end

    M.SelectQueue(queueKey)
    M.Refresh()

    if type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
        NS.Internal.Menus.CreateContextMenu(owner, function(_, rootDescription)
            if type(rootDescription.CreateTitle) == "function" then
                rootDescription:CreateTitle(tostring(queue.label or queueKey or "Queue"))
            end

            M.CreateContextMenuButton(rootDescription, "Open Queue", function()
                M.OpenQueueDetails(queueKey)
            end)

            if M.IsQueueUsableFromList(queueType) then
                if M.IsManualQueueActive(queueKey) then
                    M.CreateContextMenuButton(rootDescription, "Deactivate Queue", function()
                        M.StopUsingQueueByKey(queueKey)
                    end)
                else
                    M.CreateContextMenuButton(rootDescription, "Activate Queue", function()
                        M.UseQueueByKey(queueKey)
                    end)
                end
            end

            if M.IsQueueDetailsToggleable(queue, queueType) then
                M.CreateContextMenuButton(rootDescription,
                    queue.detailsExpanded and "Hide Route Details" or "Show Route Details",
                    function()
                        M.ToggleQueueDetailsByKey(queueKey)
                    end)
            end

            if type(M.GetQueueFinalEntry(queue)) == "table" then
                M.CreateContextMenuButton(rootDescription, "Show Final Destination", function()
                    M.FocusQueueFinalDestination(queue)
                end)
            end

            if M.IsQueueClearableFromList(queueType) then
                M.AddContextMenuDivider(rootDescription)
                M.CreateContextMenuButton(rootDescription, "Clear Queue", function()
                    M.ClearQueueByKey(queueKey)
                end)
            end
        end)
        return true
    end

    return false
end
