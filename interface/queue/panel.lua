-- ============================================================
-- Queue window and map tab
-- ============================================================
--
-- Owns the queue window and its map tab, including attached and detached
-- display and refresh on map events.

local NS = _G.AzerothWaypointNS
NS.Internal = NS.Internal or {}
NS.Internal.QueueUI = NS.Internal.QueueUI or {}
local M = NS.Internal.QueueUI
local ui = M.ui
local MapHost = M.MapHost

-- The map callbacks create the queue tab on first use and are also installed by its constructor.
local CreateQueueTabUI
local AWPQueueTabMixin

function M.GetWorldMapFrame()
    return _G["QuestMapFrame"]
end

function M.GetMapCanvasFrame()
    return WorldMapFrame or _G["QuestMapFrame"]
end

function M.EnsureWorldMapLoaded()
    if not M.GetWorldMapFrame()
        and type(C_AddOns) == "table"
        and type(C_AddOns.LoadAddOn) == "function"
    then
        pcall(C_AddOns.LoadAddOn, "Blizzard_WorldMap")
    end
    return M.GetWorldMapFrame()
end

function M.CenterMapCanvas()
    local mapFrame = M.GetMapCanvasFrame()
    local scrollContainer = mapFrame and mapFrame.ScrollContainer or nil
    if not scrollContainer
        or type(scrollContainer.SetNormalizedHorizontalScroll) ~= "function"
        or type(scrollContainer.SetNormalizedVerticalScroll) ~= "function"
    then
        return false
    end

    scrollContainer.targetScrollX = 0.5
    scrollContainer.targetScrollY = 0.5
    scrollContainer.currentScrollX = 0.5
    scrollContainer.currentScrollY = 0.5
    scrollContainer:SetNormalizedHorizontalScroll(0.5)
    scrollContainer:SetNormalizedVerticalScroll(0.5)
    return true
end

local function SetQueueTabChecked(checked)
    if ui.tab and type(ui.tab.SetChecked) == "function" then
        ui.tab:SetChecked(checked)
    end
end

local function BuildOfficialModeSet()
    local modes = {}
    if type(QuestLogDisplayMode) == "table" then
        for _, displayMode in pairs(QuestLogDisplayMode) do
            modes[displayMode] = true
        end
    end
    return modes
end

local function IsQuestMapSideTab(frame)
    return type(frame) == "table"
        and frame.displayMode ~= nil
        and frame.OnEnter ~= nil
        and type(frame.IsShown) == "function"
        and frame:IsShown()
end

local function HideQueueTab()
    ui.active = false
    if ui.companion and ui.companion._awpDragging then
        ui.companion:StopMovingOrSizing()
        ui.companion._awpDragging = nil
    end
    if ui.content then
        ui.content:Hide()
    end
    SetQueueTabChecked(false)
end

-- ============================================================
-- Map tab placement
-- ============================================================

local function PlaceQuestMapSideTabs()
    local questMapFrame = M.GetWorldMapFrame()
    if ui.companionHost or MapHost.UsesDetachedControls() or not questMapFrame or not questMapFrame:IsShown()
        or MapHost.UsesCompanion(WorldMapFrame, questMapFrame) then
        return
    end

    local officialModes = BuildOfficialModeSet()
    local officialTabs = {}
    local addonTabs = {}

    local children = { questMapFrame:GetChildren() }
    for index = 1, #children do
        local child = children[index]
        if IsQuestMapSideTab(child) then
            if officialModes[child.displayMode] then
                officialTabs[#officialTabs + 1] = child
            else
                addonTabs[#addonTabs + 1] = child
            end
        end
    end

    -- Clear all addon tab anchors before rebuilding the stack. Otherwise two
    -- addons can anchor to each other's stale positions during display-mode swaps.
    for index = 1, #addonTabs do
        addonTabs[index]:ClearAllPoints()
    end

    local placedTabs = officialTabs
    for index = 1, #addonTabs do
        local tab = addonTabs[index]
        local numShown = #placedTabs

        if numShown == 0 then
            tab:SetPoint("LEFT", questMapFrame, "RIGHT")
        else
            local row = numShown % ui.maxTabsPerColumn
            local relativePoint = "BOTTOMLEFT"
            local offsetY = -3
            local anchorTab = placedTabs[numShown]

            if row == 0 then
                anchorTab = placedTabs[numShown + 1 - ui.maxTabsPerColumn] or anchorTab
                relativePoint = "TOPRIGHT"
                offsetY = 0
            end

            tab:SetPoint("TOPLEFT", anchorTab, relativePoint, 0, offsetY)
        end

        placedTabs[#placedTabs + 1] = tab
    end
end

local function ScheduleQueueTabPlacement()
    if ui.companionHost or MapHost.UsesDetachedControls() then return end
    PlaceQuestMapSideTabs()
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(0, PlaceQuestMapSideTabs)
        C_Timer.After(0.05, PlaceQuestMapSideTabs)
        C_Timer.After(0.15, PlaceQuestMapSideTabs)
    end
end

local function HookOtherCustomMapTabs()
    local questMapFrame = M.GetWorldMapFrame()
    if MapHost.UsesDetachedControls() or not questMapFrame or MapHost.UsesCompanion(WorldMapFrame, questMapFrame) then
        return
    end

    ui.hookedTabs = ui.hookedTabs or setmetatable({}, { __mode = "k" })
    local officialModes = BuildOfficialModeSet()
    local children = { questMapFrame:GetChildren() }
    for index = 1, #children do
        local child = children[index]
        if child ~= ui.tab
            and child.displayMode
            and not officialModes[child.displayMode]
            and type(child.SetChecked) == "function"
            and not ui.hookedTabs[child]
        then
            ui.hookedTabs[child] = true
            child:HookScript("OnMouseUp", function(self, button, upInside)
                if not ui.companionHost and not MapHost.UsesDetachedControls() and button == "LeftButton" and upInside then
                    HideQueueTab()
                end
            end)
            child:HookScript("OnShow", ScheduleQueueTabPlacement)
            child:HookScript("OnHide", ScheduleQueueTabPlacement)
        end
    end
end

-- ============================================================
-- Window header and footer
-- ============================================================

local function UpdateHeader(selectedQueue, queueType, viewMode)
    if not ui.content then
        return
    end

    if viewMode == "detail" and type(selectedQueue) == "table" then
        ui.content.title:SetText(tostring(selectedQueue.label or "Queue"))
    else
        ui.content.title:SetText("Waypoint Queues")
    end
end

local function UpdateFooterState(selectedQueue, queueType, viewMode, snapshot)
    if not ui.content then
        return
    end

    local isDetail = viewMode == "detail" and type(selectedQueue) == "table"
    local canUse = (queueType == "manual" or queueType == "guide") and type(selectedQueue) == "table"
    local canClear = queueType == "manual" or queueType == "transient"
    local isActiveManualQueue = canUse and M.IsManualQueueActive(selectedQueue.id, {
        activeManualQueueID = snapshot and snapshot.activeManualQueueID,
    })
    local canUseAction = false
    if canUse and queueType == "manual" then
        if isActiveManualQueue then
            canUseAction = type(NS.StopUsingManualQueue) == "function"
        else
            canUseAction = type(NS.SetActiveManualQueue) == "function"
        end
    elseif canUse and queueType == "guide" then
        canUseAction = type(NS.ActivateGuideQueueByID) == "function"
    end

    ui.content.backButton:SetShown(isDetail)

    ui.content.useButton:SetShown(isDetail and canUse)
    ui.content.useButton:SetEnabled(canUseAction)
    ui.content.useButton:SetText(isActiveManualQueue and "Deactivate" or "Activate")

    ui.content.clearButton:SetShown(isDetail and canClear)
    ui.content.clearButton:SetEnabled(canClear)

    ui.content.toggleDetailsButton:SetShown(false)
    ui.content.toggleDetailsButton:SetEnabled(false)

    ui.content.importButton:SetShown(not isDetail)
    ui.content.importButton:SetEnabled(type(NS.OpenTomTomPasteWindow) == "function")
    local manualQueues = snapshot and snapshot.manualQueues
    ui.content.exportButton:SetShown(not isDetail or queueType == "manual")
    ui.content.exportButton:SetText(isDetail and "Export" or "Export All")
    ui.content.exportButton:SetEnabled((isDetail and queueType == "manual" and #(selectedQueue.items or {}) > 0)
        or (not isDetail and type(manualQueues) == "table" and #manualQueues > 0))

    ui.content.questsButton:SetShown(not isDetail and not ui.companionHost)

    local footerHeight = M.ReflowFooterButtons(viewMode, selectedQueue, queueType)
    M.UpdateBulkDeleteButton(selectedQueue, queueType, viewMode)
    local bottomInset = footerHeight > 0 and (footerHeight + 20) or 12

    if isDetail then
        M.SetContentPageBounds(ui.content.detailPage, bottomInset)
    else
        M.SetContentPageBounds(ui.content.listPage, bottomInset)
    end
end

local function ClearQuestLogDisplayMode(questMapFrame)
    if not questMapFrame or type(questMapFrame.SetDisplayMode) ~= "function" then
        return false
    end

    ui.settingDisplayMode = true
    if type(QuestLogDisplayMode) == "table" and QuestLogDisplayMode.Quests ~= nil then
        pcall(questMapFrame.SetDisplayMode, questMapFrame, QuestLogDisplayMode.Quests)
    end
    local ok = pcall(questMapFrame.SetDisplayMode, questMapFrame)
    ui.settingDisplayMode = nil
    return ok
end

local function CreateCompanionControls(content, worldMap)
    local companion = CreateFrame("Frame", nil, worldMap)
    companion:SetMovable(true)

    local close = CreateFrame("Button", nil, content, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", HideQueueTab)
    content.closeButton = close
    local appearance = NS.Internal.Appearance
    if appearance then
        appearance.RegisterVisual(close, {
            kind = "close",
            regions = { close:GetNormalTexture(), close:GetPushedTexture(), close:GetHighlightTexture() },
        })
    end

    local drag = CreateFrame("Frame", nil, content)
    drag:SetPoint("TOPLEFT", 4, -4)
    drag:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", -36, -37)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        companion._awpDragging = true
        companion:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        companion:StopMovingOrSizing()
        companion._awpDragging = nil
        companion._awpMoved = true
    end)
    drag:Hide()
    content.dragHandle = drag
    return companion
end

-- ============================================================
-- Map host lifecycle
-- ============================================================

local function SyncQueueHost(worldMap, questMap)
    local detached = MapHost.UsesDetachedControls()
    if not ui.content or (not detached and (not ui.tab or not worldMap or not questMap)) then return end
    local companionHost = detached or MapHost.UsesCompanion(worldMap, questMap)
    local wasDetached, wasCompanion = ui.detachedHost == true, ui.companionHost == true
    local changed = companionHost ~= wasCompanion or detached ~= wasDetached
    ui.companionHost, ui.detachedHost = companionHost, detached

    if changed then
        local tab, content = ui.tab, ui.content
        if tab and not wasDetached then
            if not wasCompanion and tab:GetParent() == questMap then
                ui.stockTabStrata, ui.stockTabLevel = tab:GetFrameStrata(), tab:GetFrameLevel()
            end
            if detached then ui.stockTabScale = tab:GetScale() end
        end
        local parent = questMap
        if companionHost then
            ui.companion = ui.companion or CreateCompanionControls(content, detached and UIParent or worldMap)
            ui.companion._awpMoved = nil
            parent = ui.companion
            if detached then parent:SetParent(UIParent) end
        elseif tab then
            if ui.companion._awpDragging then
                ui.companion:StopMovingOrSizing()
                ui.companion._awpDragging = nil
            end
            tab:SetFrameStrata(ui.stockTabStrata or questMap:GetFrameStrata())
            tab:SetFrameLevel(ui.stockTabLevel or questMap:GetFrameLevel() + 1)
        end

        if tab then
            tab:SetParent(detached and UIParent or companionHost and worldMap or questMap)
            if wasDetached and not detached then tab:SetScale(ui.stockTabScale) end
            tab:SetAlpha(1)
            tab:SetShown(not detached)
        end
        content:SetParent(parent)
        if ui.companion then ui.companion:SetAlpha(1) end
        content:SetAlpha(1)
        content:ClearAllPoints()
        content:SetAllPoints(companionHost and ui.companion or questMap.ContentsAnchor)
        content.closeButton:SetShown(companionHost)
        content:EnableMouse(companionHost)
        if not companionHost and tab then
            content.dragHandle:Hide()
            tab:ClearAllPoints()
            tab:SetPoint("LEFT", questMap, "RIGHT")
            if ui.active and worldMap:IsShown() then ClearQuestLogDisplayMode(questMap) end
            ScheduleQueueTabPlacement()
        end
    end

    if companionHost and not detached and worldMap:IsVisible() then
        ui.tab:SetFrameStrata(worldMap:GetFrameStrata())
        ui.tab:SetFrameLevel(math.max(worldMap:GetFrameLevel(), questMap:GetFrameLevel()) + 10)
        local floating = MapHost.Layout(worldMap, questMap, ui.tab, ui.content:IsShown() and ui.companion or nil)
        ui.content.dragHandle:SetShown(floating == true)
    end
end

local function OnQueueMapHide()
    if ui.companionHost and not MapHost.UsesDetachedControls() then HideQueueTab() end
end

local hostLayout = NS.Internal.Scheduling.CreateCoalescer(function()
    if MapHost.UsesDetachedControls() or ui.detachedHost then return end
    local worldMap, questMap = WorldMapFrame, M.GetWorldMapFrame()
    if not questMap then return end
    local wasCompanionHost = ui.companionHost
    SyncQueueHost(worldMap, questMap)
    if (ui.companionHost or wasCompanionHost) and ui.content and ui.content:IsVisible() then M.Refresh() end
end)

local function RequestHostLayout()
    if not MapHost.UsesDetachedControls() then hostLayout:Request() end
end

local function WatchQueueHost()
    MapHost.Watch(WorldMapFrame, M.GetWorldMapFrame(), RequestHostLayout, OnQueueMapHide)
end

-- Only the visible map needs observation. Map notifications are handled on
-- the next frame, apart from the native map's controller and panel handlers.
local detachedObservation = {}
local detachedObserver
local layoutElapsed, discoveryElapsed = 0, 0
local detachedReflow = NS.Internal.Scheduling.CreateCoalescer(function()
    if ui.detachedHost and ui.content and ui.content:IsShown() then M.Refresh() end
end)

local function StopDetachedObservation()
    if detachedObserver then detachedObserver:Hide() end
    detachedObservation.neighbors = nil
    layoutElapsed, discoveryElapsed = 0, 0
end

local function FollowDetachedAlpha(worldMap)
    local alpha = worldMap:GetEffectiveAlpha()
    if ui.tab:GetAlpha() ~= alpha then ui.tab:SetAlpha(alpha) end
    if ui.companion:GetAlpha() ~= alpha then ui.companion:SetAlpha(alpha) end
end

local function LayoutDetachedQueue(rediscover, opening)
    if not ui.detachedHost then return end
    if ui.detachedMapClosed then
        if ui.detachedMapOpen then HideQueueTab() end
        ui.detachedMapClosed, ui.detachedMapOpen = nil, nil
    end
    local worldMap = WorldMapFrame
    if not worldMap or not worldMap:IsVisible() or not ui.tab then
        StopDetachedObservation()
        if ui.tab then ui.tab:Hide() end
        if ui.detachedMapOpen then HideQueueTab() end
        ui.detachedMapOpen = nil
        if opening or ui.content:IsShown() then
            ui.companion:SetAlpha(1)
            ui.content.dragHandle:Show()
            MapHost.PlaceStandalone(ui.companion)
        end
        return
    end

    ui.detachedMapOpen = true
    if rediscover then discoveryElapsed = 0 end
    local floating = MapHost.LayoutDetached(worldMap, M.GetWorldMapFrame(), ui.tab, ui.companion,
        opening or ui.content:IsShown(), detachedObservation, rediscover)
    ui.content.dragHandle:SetShown(floating == true)
    FollowDetachedAlpha(worldMap)
    if not detachedObserver then
        detachedObserver = CreateFrame("Frame", nil, UIParent)
        detachedObserver:SetScript("OnUpdate", function(_, elapsed)
            if not WorldMapFrame or not WorldMapFrame:IsVisible() then LayoutDetachedQueue(false); return end
            FollowDetachedAlpha(WorldMapFrame)
            layoutElapsed, discoveryElapsed = layoutElapsed + elapsed, discoveryElapsed + elapsed
            if layoutElapsed < 0.25 then return end
            layoutElapsed = 0
            local discover = discoveryElapsed >= 1
            LayoutDetachedQueue(discover)
        end)
    end
    detachedObserver:Show()
end

local function ShowQueueTabContent(options)
    options = options or {}
    local detached = MapHost.UsesDetachedControls()
    local questMapFrame = M.GetWorldMapFrame()
    if not detached then questMapFrame = M.EnsureWorldMapLoaded() end
    if not ui.content or (not detached and not questMapFrame) then
        return false
    end

    WatchQueueHost()
    SyncQueueHost(WorldMapFrame, questMapFrame)
    if not ui.companionHost and (options.resetDisplayMode or not ui.content:IsShown()) then
        ClearQuestLogDisplayMode(questMapFrame)
    end

    if detached then LayoutDetachedQueue(false, true) end
    ui.active = true
    ui.content:Show()
    SetQueueTabChecked(true)
    if detached then
        -- Wait for the newly anchored content to resolve its width before
        -- measuring the scroll child and laying out the footer.
        detachedReflow:Request()
    elseif ui.companionHost then
        RequestHostLayout()
    else
        M.Refresh()
        ScheduleQueueTabPlacement()
    end
    return true
end

local detachedRefresh = NS.Internal.Scheduling.CreateCoalescer(function()
    if MapHost.UsesDetachedControls() then
        if not ui.content and not (WorldMapFrame and WorldMapFrame:IsVisible()) then return end
        local entering = not ui.detachedHost
        if not CreateQueueTabUI() then return end
        LayoutDetachedQueue(true)
        if entering and ui.content:IsShown() then detachedReflow:Request() end
    elseif ui.detachedHost then
        StopDetachedObservation()
        ui.detachedMapOpen, ui.detachedMapClosed = nil, nil
        if not (WorldMapFrame and WorldMapFrame:IsVisible()) then HideQueueTab() end
        if CreateQueueTabUI() and ui.active then ShowQueueTabContent() end
    end
end)

-- ============================================================
-- Refresh and page selection
-- ============================================================

function M.Refresh()
    if not ui.content or (ui.detachedHost and (not ui.content:IsShown() or (ui.content:GetWidth() or 0) <= 0)) then
        return
    end

    local snapshot = type(NS.GetQueuePanelSnapshot) == "function" and NS.GetQueuePanelSnapshot() or nil
    M.PruneBulkSelections(snapshot)
    local rows = M.BuildQueueRows(snapshot or {})
    local selectedKey = type(NS.GetQueuePanelSelection) == "function" and NS.GetQueuePanelSelection() or nil
    local exactSelectedQueue = M.FindQueueByKey(snapshot, selectedKey)
    local viewMode = M.GetViewMode()

    if viewMode == "detail" and type(exactSelectedQueue) ~= "table" then
        viewMode = "list"
        M.SetViewMode(viewMode)
        if type(NS.SetQueuePanelSelection) == "function" then
            NS.SetQueuePanelSelection(nil)
        end
        selectedKey = nil
    end

    local selectedQueue, queueType = M.ResolveSelectedQueue(snapshot)
    if type(selectedQueue) == "table" and type(NS.SetQueuePanelSelection) == "function" then
        NS.SetQueuePanelSelection(selectedQueue.id)
        selectedKey = selectedQueue.id
    end

    if viewMode == "detail" and type(selectedQueue) ~= "table" then
        viewMode = "list"
        M.SetViewMode(viewMode)
    end

    UpdateHeader(selectedQueue, queueType, viewMode)
    UpdateFooterState(selectedQueue, queueType, viewMode, snapshot)

    ui.content.listPage:SetShown(viewMode == "list")
    ui.content.detailPage:SetShown(viewMode == "detail" and type(selectedQueue) == "table")

    M.RenderListPage(snapshot, rows, selectedKey)
    if viewMode == "detail" and type(selectedQueue) == "table" then
        M.RenderDetailPage(selectedQueue, queueType, M.BuildDetailRows(selectedQueue, queueType))
    else
        M.RenderDetailPage(nil, nil, nil)
    end
    if NS.Internal.Controller then NS.Internal.Controller.Request(ui.content) end
end

local function EnsureCallbacksRegistered()
    if ui.callbacksRegistered or type(EventRegistry) ~= "table" then
        return
    end
    ui.callbacksRegistered = true

    EventRegistry:RegisterCallback("WorldMapOnShow", function()
        if MapHost.UsesDetachedControls() or ui.detachedHost then
            detachedRefresh:Request()
            return
        end
        if not ui.tab or not ui.content then
            CreateQueueTabUI()
        end
        WatchQueueHost()
        SyncQueueHost(WorldMapFrame, M.GetWorldMapFrame())
        HookOtherCustomMapTabs()
        if ui.companionHost then
            RequestHostLayout()
        else
            ScheduleQueueTabPlacement()
        end
        if ui.active then
            ShowQueueTabContent()
        else
            SetQueueTabChecked(false)
        end
    end, ui)

    EventRegistry:RegisterCallback("WorldMapOnHide", function()
        if MapHost.UsesDetachedControls() or ui.detachedHost then
            ui.detachedMapClosed = true
            detachedRefresh:Request()
        end
    end, ui)

    -- ============================================================
    -- Window creation and resizing
    -- ============================================================

    local function OnMapResized()
        if MapHost.UsesDetachedControls() or ui.detachedHost then detachedRefresh:Request() end
    end
    EventRegistry:RegisterCallback("WorldMapMinimized", OnMapResized, ui)
    EventRegistry:RegisterCallback("WorldMapMaximized", OnMapResized, ui)

    EventRegistry:RegisterCallback("QuestLog.SetDisplayMode", function(_, displayMode)
        if MapHost.UsesDetachedControls() or ui.detachedHost then
            detachedRefresh:Request()
            return
        end
        HookOtherCustomMapTabs()
        ScheduleQueueTabPlacement()
        if not ui.companionHost and not ui.settingDisplayMode and displayMode ~= nil then
            HideQueueTab()
        end
    end, ui)
end

local function EnsureQueueTabMixin()
    if AWPQueueTabMixin then
        return AWPQueueTabMixin
    end
    local SidePanelTabButtonMixin = _G["SidePanelTabButtonMixin"]
    if type(SidePanelTabButtonMixin) ~= "table" then
        return nil
    end

    AWPQueueTabMixin = CreateFromMixins(SidePanelTabButtonMixin)

    function AWPQueueTabMixin:OnMouseDown(button)
        SidePanelTabButtonMixin.OnMouseDown(self, button)
    end

    function AWPQueueTabMixin:OnMouseUp(button, upInside)
        SidePanelTabButtonMixin.OnMouseUp(self, button, upInside)
        if button == "LeftButton" and upInside then
            if ui.companionHost and ui.content and ui.content:IsShown() then
                HideQueueTab()
            else
                ShowQueueTabContent()
            end
        end
    end

    function AWPQueueTabMixin:OnEnter()
        SidePanelTabButtonMixin.OnEnter(self)
    end

    function AWPQueueTabMixin:SetChecked(checked)
        SidePanelTabButtonMixin.SetChecked(self, checked)
        if self.Icon then
            self.Icon:SetSize(24, 24)
            self.Icon:SetAlpha(checked and 1 or 0.55)
        end
    end

    return AWPQueueTabMixin
end

local function CreateQueueTab(questMapFrame, detached)
    local tabMixin = EnsureQueueTabMixin()
    if not tabMixin then return end
    local tab = CreateFrame("Button", "AWPQuestMapQueueTab", detached and UIParent or questMapFrame,
        "LargeSideTabButtonTemplate")
    Mixin(tab, tabMixin)
    tab.displayMode = "AWP_QUEUE"
    if NS.Internal.Controller then NS.Internal.Controller.RegisterControl(tab, { id = "awp-queue-map-tab" }) end
    tab.tooltipText = "AzerothWaypoint Queues"
    tab.activeAtlas = "islands-queue-prop-compass"
    tab.inactiveAtlas = "islands-queue-prop-compass"
    tab.useAtlasSize = false
    ui.stockTabScale = tab:GetScale()
    tab:ClearAllPoints()
    if detached then
        tab:Hide()
    else
        tab:SetPoint("LEFT", questMapFrame, "RIGHT")
        ui.stockTabStrata, ui.stockTabLevel = tab:GetFrameStrata(), tab:GetFrameLevel()
    end
    tab:SetScript("OnMouseDown", tab.OnMouseDown)
    tab:SetScript("OnMouseUp", tab.OnMouseUp)
    tab:SetScript("OnEnter", tab.OnEnter)
    tab:SetScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    tab:SetChecked(ui.active == true)
    return tab
end

CreateQueueTabUI = function()
    local detached = MapHost.UsesDetachedControls()
    local questMapFrame = M.GetWorldMapFrame()
    if not detached then
        questMapFrame = M.EnsureWorldMapLoaded()
        if not questMapFrame or not questMapFrame.ContentsAnchor then return false end
    end
    EnsureCallbacksRegistered()
    WatchQueueHost()
    if not detached and not ui.layoutHooksRegistered then
        ui.layoutHooksRegistered = true
        HookOtherCustomMapTabs()
        if type(questMapFrame.HookScript) == "function" then
            questMapFrame:HookScript("OnSizeChanged", ScheduleQueueTabPlacement)
        end
        if questMapFrame.ContentsAnchor and type(questMapFrame.ContentsAnchor.HookScript) == "function" then
            questMapFrame.ContentsAnchor:HookScript("OnSizeChanged", function()
                if not MapHost.UsesDetachedControls() and not ui.companionHost and ui.content and ui.content:IsShown() then
                    M.Refresh()
                end
                ScheduleQueueTabPlacement()
            end)
        end
    end

    if not ui.tab and (questMapFrame or (detached and WorldMapFrame)) then
        ui.tab = CreateQueueTab(questMapFrame, detached)
    end
    if not detached and not ui.tab then return false end
    if ui.content then
        if detached ~= (ui.detachedHost == true) then SyncQueueHost(WorldMapFrame, questMapFrame) end
        return true
    end

    local content = CreateFrame("Frame", "AWPQuestMapQueueContent", detached and UIParent or questMapFrame)
    content.displayMode = "AWP_QUEUE"
    if NS.Internal.Appearance then NS.Internal.Appearance.Tag(content, "windows.queue") end
    if not detached then
        content:SetPoint("TOPLEFT", questMapFrame.ContentsAnchor, "TOPLEFT")
        content:SetPoint("BOTTOMRIGHT", questMapFrame.ContentsAnchor, "BOTTOMRIGHT")
    end
    content:Hide()
    content:SetScript("OnShow", function()
        ui.active = true
        if not ui.companionHost then M.Refresh() end
    end)
    content:SetScript("OnSizeChanged", function(self)
        if ui.detachedHost and self:IsShown() then detachedReflow:Request() end
    end)
    content:SetScript("OnHide", function()
        if ui.detachedHost or MapHost.UsesDetachedControls() then return end
        local questMapFrame = M.GetWorldMapFrame()
        if questMapFrame and questMapFrame:IsShown() then
            ui.active = false
            SetQueueTabChecked(false)
        end
    end)
    ui.content = content
    if NS.Internal.Controller then NS.Internal.Controller.RegisterWindow(content, { close = function() HideQueueTab() end }) end

    content.bg = content:CreateTexture(nil, "BACKGROUND")
    content.bg:SetAtlas("QuestLog-main-background", true)
    content.bg:SetPoint("TOPLEFT")
    content.bg:SetPoint("BOTTOMRIGHT")

    content.border = M.CreateQueueBorder(content)

    content.title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    content.title:SetPoint("TOP", content, "TOP", 0, -18)
    content.title:SetJustifyH("CENTER")
    content.title:SetText("Waypoint Queues")

    if NS.Internal.Appearance then
        NS.Internal.Appearance.Text(content.title, "windows.queue", "TITLE")
        NS.Internal.Appearance.Shell(content, "windows.queue", { content.bg, content.border })
    end

    M.CreateListPage(content)
    M.CreateDetailPage(content)

    content.useButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    content.useButton:SetSize(96, 24)
    content.useButton:SetText("Activate")
    content.useButton:SetScript("OnClick", function()
        local key = type(NS.GetQueuePanelSelection) == "function" and NS.GetQueuePanelSelection() or nil
        M.ToggleQueueUseByKey(key)
    end)

    content.clearButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    content.clearButton:SetSize(96, 24)
    content.clearButton:SetText("Clear")
    content.clearButton:SetScript("OnClick", function()
        local key = type(NS.GetQueuePanelSelection) == "function" and NS.GetQueuePanelSelection() or nil
        M.ClearQueueByKey(key)
    end)

    content.toggleDetailsButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    content.toggleDetailsButton:SetSize(110, 24)
    content.toggleDetailsButton:SetText("Show Details")
    content.toggleDetailsButton:Hide()
    content.toggleDetailsButton:SetScript("OnClick", function()
        local key = type(NS.GetQueuePanelSelection) == "function" and NS.GetQueuePanelSelection() or nil
        M.ToggleQueueDetailsByKey(key)
    end)

    content.questsButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    content.questsButton:SetSize(110, 24)
    content.questsButton:SetPoint("RIGHT", content, "BOTTOMRIGHT", -12, 12)
    content.questsButton:SetText("Quest Log")
    content.questsButton:SetScript("OnClick", function()
        local questMapFrame = M.EnsureWorldMapLoaded()
        if questMapFrame
            and type(QuestLogDisplayMode) == "table"
            and QuestLogDisplayMode.Quests ~= nil
        then
            questMapFrame:SetDisplayMode(QuestLogDisplayMode.Quests)
        else
            HideQueueTab()
        end
    end)

    content.importButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    content.importButton:SetSize(96, 24)
    content.importButton:SetPoint("RIGHT", content.questsButton, "LEFT", -8, 0)
    content.importButton:SetText("Import")
    content.importButton:SetScript("OnClick", M.OpenImportWindow)
    content.importButton:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Import TomTom Waypoints", 1, 1, 1)
            GameTooltip:AddLine("Open TomTom's /ttpaste window.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    content.importButton:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    content.exportButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    content.exportButton:SetSize(84, 24)
    content.exportButton:SetScript("OnClick", M.OpenExportWindow)

    for _, button in ipairs({ content.useButton, content.clearButton, content.toggleDetailsButton,
        content.questsButton, content.importButton, content.exportButton, content.backButton }) do
        M.StyleQueueButton(button)
    end

    content.bulkDeleteButton = CreateFrame("Button", nil, content)
    content.bulkDeleteButton:SetSize(26, 26)
    content.bulkDeleteButton:Hide()
    content.bulkDeleteButton.icon = content.bulkDeleteButton:CreateTexture(nil, "ARTWORK")
    content.bulkDeleteButton.icon:SetPoint("CENTER")
    content.bulkDeleteButton.icon:SetSize(22, 22)
    content.bulkDeleteButton.icon:SetAtlas("common-icon-delete", false)
    content.bulkDeleteButton.glow = content.bulkDeleteButton:CreateTexture(nil, "OVERLAY")
    content.bulkDeleteButton.glow:SetPoint("CENTER")
    content.bulkDeleteButton.glow:SetSize(24, 24)
    content.bulkDeleteButton.glow:SetAtlas("common-icon-delete", false)
    content.bulkDeleteButton.glow:SetBlendMode("ADD")
    content.bulkDeleteButton.glow:SetAlpha(0.7)
    content.bulkDeleteButton.glow:Hide()
    content.bulkDeleteButton:SetScript("OnClick", function(self)
        if self.deleteMode == "items" then
            M.DeleteSelectedQueueItems(self.queueKey)
        else
            M.DeleteSelectedQueues()
        end
    end)
    content.bulkDeleteButton:SetScript("OnEnter", function(self)
        if self.glow then
            self.glow:Show()
        end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if self.deleteMode == "items" then
                GameTooltip:SetText("Remove selected destinations", 1, 1, 1)
                GameTooltip:AddLine(string.format("%d selected", tonumber(self.deleteCount) or 0), 0.8, 0.8, 0.8)
            else
                GameTooltip:SetText("Delete selected queues", 1, 1, 1)
                GameTooltip:AddLine(string.format("%d selected", tonumber(self.deleteCount) or 0), 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end
    end)
    content.bulkDeleteButton:SetScript("OnLeave", function(self)
        if self.glow then
            self.glow:Hide()
        end
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    if NS.Internal.Appearance then NS.Internal.Appearance.RegisterReflow(content, M.Refresh) end
    SyncQueueHost(WorldMapFrame, questMapFrame)
    return true
end

-- ============================================================
-- Public window controls
-- ============================================================

local function IsShown(frame)
    if not frame or type(frame.IsShown) ~= "function" then
        return false
    end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

local function OpenWorldMap()
    local worldMap = WorldMapFrame
    if IsShown(worldMap) then
        return true
    end
    if type(ToggleWorldMap) == "function" then
        local ok = pcall(ToggleWorldMap)
        if ok and IsShown(WorldMapFrame) then
            return true
        end
    end
    worldMap = WorldMapFrame
    if worldMap and type(worldMap.Show) == "function" then
        local ok = pcall(worldMap.Show, worldMap)
        return ok and IsShown(worldMap)
    end
    return false
end

local function SetQuestLogDisplayMode(questMapFrame)
    if not questMapFrame or type(questMapFrame.SetDisplayMode) ~= "function" then
        return false
    end

    ui.settingDisplayMode = true
    local ok = false
    if type(QuestLogDisplayMode) == "table" and QuestLogDisplayMode.Quests ~= nil then
        ok = pcall(questMapFrame.SetDisplayMode, questMapFrame, QuestLogDisplayMode.Quests)
    end
    if not ok then
        ok = pcall(questMapFrame.SetDisplayMode, questMapFrame)
    end
    ui.settingDisplayMode = nil
    return ok
end

local function ForceQuestLogSidePanel()
    M.EnsureWorldMapLoaded()

    if type(OpenQuestLog) == "function" then
        pcall(OpenQuestLog)
    elseif type(ToggleQuestLog) == "function" and not IsShown(WorldMapFrame) then
        pcall(ToggleQuestLog)
    end

    OpenWorldMap()

    local questMapFrame = M.EnsureWorldMapLoaded()
    if questMapFrame then
        if not IsShown(questMapFrame) and type(questMapFrame.Show) == "function" then
            pcall(questMapFrame.Show, questMapFrame)
        end
        SetQuestLogDisplayMode(questMapFrame)
    end

    return IsShown(questMapFrame)
end

local function OpenQueueInQuestMap(options)
    options = options or {}
    local questMapFrame = M.EnsureWorldMapLoaded()
    if not questMapFrame then
        return false
    end
    if not CreateQueueTabUI() then
        return false
    end

    if options.forceQuestLog and not MapHost.UsesCompanion(WorldMapFrame, questMapFrame) then
        ForceQuestLogSidePanel()
    else
        OpenWorldMap()
    end

    M.SetViewMode("list")

    local schedule = type(NS.After) == "function"
        and NS.After
        or function(_, callback)
            if type(callback) == "function" then
                callback()
            end
        end

    schedule(0, function()
        if MapHost.UsesDetachedControls() then
            NS.ShowQueuePanel(options)
            return
        end
        local frame = M.EnsureWorldMapLoaded()
        if not frame then
            return
        end
        local companionHost = MapHost.UsesCompanion(WorldMapFrame, frame)
        if companionHost and not IsShown(WorldMapFrame) then return end
        local useQuestLog = options.forceQuestLog and not companionHost
        if useQuestLog then
            ForceQuestLogSidePanel()
        end
        ShowQueueTabContent({ resetDisplayMode = useQuestLog })
        if useQuestLog and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(0.05, function()
                if not MapHost.UsesDetachedControls() and not MapHost.UsesCompanion(WorldMapFrame, frame)
                    and ui.active and ui.content and ui.content:IsShown() then
                    ShowQueueTabContent({ resetDisplayMode = true })
                end
            end)
        end
    end)
    return true
end

function NS.RefreshQueuePanel()
    if ui.content and ui.content:IsShown() then
        M.Refresh()
    end
end

function NS.ShowQueuePanel(options)
    if MapHost.UsesDetachedControls() then
        if not CreateQueueTabUI() then return false end
        M.SetViewMode("list")
        return ShowQueueTabContent()
    elseif OpenQueueInQuestMap(options) then
        return true
    end
    NS.Msg("Queue UI unavailable: World Map could not be opened.")
    return false
end

local initializer = CreateFrame("Frame")
initializer:RegisterEvent("PLAYER_LOGIN")
initializer:RegisterEvent("ADDON_LOADED")
initializer:RegisterEvent("UI_SCALE_CHANGED")
initializer:RegisterEvent("DISPLAY_SIZE_CHANGED")
initializer:RegisterEvent("CVAR_UPDATE")
initializer:SetScript("OnEvent", function(_, event, arg1)
    if event == "CVAR_UPDATE" then
        if type(arg1) == "string" and arg1:lower() == "inputdeviceinterfacestyle"
            and (MapHost.UsesDetachedControls() or ui.detachedHost) then
            detachedRefresh:Request()
        end
        return
    end
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        if MapHost.UsesDetachedControls() or ui.detachedHost then
            detachedRefresh:Request()
        elseif ui.companionHost then
            RequestHostLayout()
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        EnsureCallbacksRegistered()
        if MapHost.UsesDetachedControls() then
            detachedRefresh:Request()
        elseif M.GetWorldMapFrame() then
            CreateQueueTabUI()
        end
        return
    end

    if MapHost.UsesDetachedControls() then
        if WorldMapFrame and WorldMapFrame:IsVisible() then detachedRefresh:Request() end
    elseif arg1 == "Blizzard_WorldMap" then
        CreateQueueTabUI()
    elseif arg1 == "DaylightUI" or arg1 == "DaylightUI_Quests" or arg1 == "Spoken_Places"
        or arg1 == "GW2_UI" or arg1 == "Mapzeroth" then
        WatchQueueHost()
        RequestHostLayout()
    end
end)

local _, private = ...
if private and private.finishLoadGroup then private.finishLoadGroup("Viewers and windows") end
