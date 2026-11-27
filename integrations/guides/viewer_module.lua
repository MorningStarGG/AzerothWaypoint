-- ============================================================
-- Guide Viewer module construction
-- ============================================================
--
-- Creates tracker modules with the storage and header behavior required by the
-- selected host. The host owns how guide sections attach to its tracker. The
-- module stores only the per-guide controls and layout state.

local NS = _G.AzerothWaypointNS

local CreateFrame = _G.CreateFrame
local Mixin = _G.Mixin

NS.Internal = NS.Internal or {}
NS.Internal.GuideTrackerViewer = NS.Internal.GuideTrackerViewer or {}

local Factory = {}
NS.Internal.GuideTrackerViewer.ModuleFactory = Factory

local function ApplyModuleMixin(frame, source, usingKT)
    if type(source) ~= "table" then return false end
    if usingKT then
        if type(Mixin) ~= "function" then return false end
        Mixin(frame, source)
        return true
    end
    -- This field must remain untouched (secure nil) on Blizzard's objective tracker.
    for key, value in pairs(source) do
        if key ~= "hasDisplayPriority" then frame[key] = value end
    end
    return true
end

local function FinishKTHeader(header, parentModule)
    if not header then return end
    -- KT's hooked SetCollapsed requires Icon before its header mixin OnLoad.
    if not header.Icon and type(header.CreateTexture) == "function" then
        local icon = header:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetTexture("Interface\\AddOns\\!KalielsTracker\\Media\\UI-KT-HeaderButtons")
        icon:SetTexCoord(0.5, 1, 0.75, 1)
        icon:SetPoint("LEFT", -6, 2)
        header.Icon = icon
    end
    local headerMixin = rawget(_G, "KT_ObjectiveTrackerModuleHeaderMixin")
    if type(Mixin) == "function" and type(headerMixin) == "table" then
        Mixin(header, headerMixin)
        if type(header.OnLoad) == "function" then pcall(header.OnLoad, header) end
    end
    if header.Text then
        local fontObject = rawget(_G, "KT_ObjectiveTrackerHeaderFont")
        if fontObject and type(header.Text.SetFontObject) == "function" then
            pcall(header.Text.SetFontObject, header.Text, fontObject)
        end
        header.Text:ClearAllPoints()
        header.Text:SetPoint("LEFT", 10, 1)
    end
    if header.MinimizeButton then header.MinimizeButton:Hide() end
    header:EnableMouse(true)
    header:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and type(parentModule.ToggleCollapsed) == "function" then
            parentModule:ToggleCollapsed()
        end
    end)
end

local function InitializeStorage(frame)
    local names = {
        "usedBlocks", "cachedBlocks", "cachedBlocksByTemplate", "usedTimerBars",
        "usedProgressBars", "usedRightEdgeFrames", "timerBars", "progressBars",
        "fanfares", "cachedOrderList",
    }
    for index = 1, #names do frame[names[index]] = frame[names[index]] or {} end
    frame.numCachedBlocks = frame.numCachedBlocks or 0
end

function Factory.Create(config)
    config = type(config) == "table" and config or {}
    local Host = config.host
    if type(Host) ~= "table" or type(config.name) ~= "string" then return nil end
    local container = Host.GetTrackerFrame()
    if not container then return nil end
    local usingKT = Host.IsKTLoaded()
    local width = usingKT and 260 or 240
    local frame = CreateFrame("Frame", config.name, container)
    frame._awpGuideProvider = config.providerKey
    if NS.Internal.Appearance then NS.Internal.Appearance.Tag(frame, "guide." .. config.providerKey) end
    frame:Hide()
    frame:SetSize(width, 10)
    frame:SetPoint("TOP")
    if not ApplyModuleMixin(frame, Host.GetModuleMixin(), usingKT) then
        frame:Hide()
        return nil
    end

    local ok, header = pcall(CreateFrame, "Frame", nil, frame, Host.GetHeaderTemplate())
    if not ok or not header then
        header = CreateFrame("Frame", nil, frame)
        header:SetSize(width, 22)
        header.Text = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        header.Text:SetPoint("LEFT", 2, 0)
    end
    if usingKT then
        header:SetWidth(width)
        FinishKTHeader(header, frame)
    end
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    frame.Header = header

    local contents = CreateFrame("Frame", nil, frame)
    contents:SetPoint("TOP", header, "BOTTOM")
    contents:SetPoint("LEFT")
    contents:SetPoint("RIGHT")
    contents:SetPoint("BOTTOM")
    frame.ContentsFrame = contents

    frame.headerText = config.headerText or config.name
    frame.events = {}
    frame.lineTemplate = Host.GetLineTemplate()
    frame.blockTemplate = Host.GetBlockTemplate()
    frame.rightEdgeFrameSpacing = config.rightEdgeFrameSpacing or 2
    frame.uiOrder = tonumber(config.uiOrder) or 2
    if usingKT then frame.hasDisplayPriority = false end
    InitializeStorage(frame)

    if type(frame.OnLoad) == "function" then pcall(frame.OnLoad, frame) end
    if type(frame.OnEvent) == "function" then
        frame:SetScript("OnEvent", function(self, event, ...) self:OnEvent(event, ...) end)
    end
    if type(frame.OnHide) == "function" then
        frame:SetScript("OnHide", function(self) self:OnHide() end)
    end
    if frame.Header and frame.Header.Text then frame.Header.Text:SetText(frame.headerText) end
    local function noop() end
    for _, name in ipairs({ "PlayAddAnimation", "PlayRemoveAnimation", "SetCollapsed", "UpdateMinimizeButton" }) do
        if type(frame.Header[name]) ~= "function" then frame.Header[name] = noop end
    end

    local originalLayoutBlock = frame.LayoutBlock
    if type(originalLayoutBlock) == "function" then
        function frame:LayoutBlock(block, ...)
            local pad = NS.Internal.Controller
            if pad and pad.BindGuideHeader then pad.BindGuideHeader(self, block, config.providerKey) end
            local actions = NS.Internal.GuideTrackerViewer.GuideActions
            if actions then actions.LayoutStepStrip(self, block) end
            return originalLayoutBlock(self, block, ...)
        end
    end

    local originalUpdate = frame.Update
    function frame:Update(availableHeight, dirtyUpdate)
        if NS.Internal.Controller and NS.Internal.Controller.BeginHintLayout then NS.Internal.Controller.BeginHintLayout(
            self) end
        local actions = NS.Internal.GuideTrackerViewer.GuideActions
        if actions then actions.BeginLayout(self) end
        local collapsed = self.parentContainer
            and type(self.parentContainer.IsCollapsed) == "function"
            and self.parentContainer:IsCollapsed()
        if not collapsed and (not availableHeight or availableHeight <= 0) then availableHeight = 8000 end
        if type(originalUpdate) == "function" then
            local height, truncated = originalUpdate(self, availableHeight, dirtyUpdate)
            if NS.Internal.Controller and NS.Internal.Controller.ReserveHintSpace then height = NS.Internal.Controller
                .ReserveHintSpace(self, height or self:GetHeight()) end
            if NS.Internal.Appearance then NS.Internal.Appearance.PruneModule(self) end
            if actions then actions.EndLayout(config.providerKey) end
            if self._awpCheckHostVisibility then self._awpCheckHostVisibility() end
            if NS.Internal.Controller then NS.Internal.Controller.Request(self) end
            return height, truncated
        end
        if type(self.LayoutContents) == "function" then self:LayoutContents() end
        if actions then actions.EndLayout(config.providerKey) end
        if self._awpCheckHostVisibility then self._awpCheckHostVisibility() end
        if NS.Internal.Controller then NS.Internal.Controller.Request(self) end
        local height = self:GetHeight()
        if NS.Internal.Controller and NS.Internal.Controller.ReserveHintSpace then height = NS.Internal.Controller
            .ReserveHintSpace(self, height) end
        return height, false
    end

    function frame:IsDisplayable() return self.hasContents == true end

    function frame:GetContextMenuParent() return self.parentContainer or _G.UIParent end

    if NS.Internal.Controller then NS.Internal.Controller.RegisterWindow(frame,
            { manual = true, guide = config.providerKey, tracker = true, hintLayout = true }) end
    return frame, usingKT
end
