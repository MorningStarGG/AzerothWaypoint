-- ============================================================
-- Dugi Viewer
-- ============================================================
--
-- Renders Dugi's guide steps and coordinates its tracker, guide selection and
-- native frame visibility.

local NS = _G.AzerothWaypointNS

local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer
local Common = NS.Internal and NS.Internal.GuideTrackerViewer
local Host = Common and Common.Host
local CombatProxy = Common and Common.CombatProxy
local SharedControls = Common and Common.Controls
local SharedRender = Common and Common.Render
local ModuleFactory = Common and Common.ModuleFactory
local HeaderStyle = Common and Common.HeaderStyle
local Presentation = NS.Internal and NS.Internal.DugiPresentation
local Styles = Common and Common.Styles
if type(Host) ~= "table" or type(SharedRender) ~= "table" or type(ModuleFactory) ~= "table" then return end

local PROVIDER = "dugi"
local MODULE_NAME = "AwpDugiTrackerModule"
local BLOCK_ID = "AwpDugiCurrentStep"
local module
local attached = false
local lastChatGuide, lastChatStep
local refreshContent, refreshSettings, refreshChat, refreshData = false, false, false, false
local pendingHookInstaller
local hooksInstalled = false
local hookedMethods = setmetatable({}, { __mode = "k" })
local progressGuide
local observedGuide
local viewerSnapshot = { steps = {}, stickies = {} }
if Common.QuestDetails then Common.QuestDetails.RegisterSource(PROVIDER, function() return viewerSnapshot end) end
local nextSteps, nextStickies, relevantIndices, relevantSeen = {}, {}, {}, {}
local DEFAULT_SETTINGS = { enabled = false, hideDugiFrame = false }
local DATA_REFRESH_OPTIONS = { presentationRefresh = true }
local EMPTY_GUIDE_ROW = {
    text = "Open Dugi Guides to select a guide.",
    status = "incomplete",
    kind = "goal",
    action =
    "note",
    fullHeight = true
}

local function GetDugi() return rawget(_G, "DugisGuideViewer") end
local function GetUser() return rawget(_G, "DugisGuideUser") end
local function IsSmallFrameFloating(dugi)
    if not dugi or type(dugi.IsSmallFrameFloating) ~= "function" then return nil end
    local ok, floating = pcall(dugi.IsSmallFrameFloating, dugi)
    if ok then return floating == true end
end
local function IsDugiReady()
    local dugi = GetDugi()
    if type(dugi) ~= "table" or type(dugi.GetQuestStepText) ~= "function" then return false end
    if type(dugi.GuideOn) == "function" then
        local ok, enabled = pcall(dugi.GuideOn, dugi)
        if not ok or not enabled then return false end
    end
    return true
end
local function GetSettings()
    return type(NS.GetGuideTrackerViewerSettings) == "function"
        and NS.GetGuideTrackerViewerSettings(PROVIDER)
        or DEFAULT_SETTINGS
end
local function CurrentIndex()
    local user = GetUser()
    return type(user) == "table" and tonumber(user.CurrentQuestIndex) or nil
end

local function GetRawGuideTitle(dugi)
    local title = rawget(_G, "CurrentTitle")
    if type(title) ~= "string" or title == "" then
        title = type(dugi) == "table" and dugi.CurrentTitle or nil
    end
    return type(title) == "string" and title ~= "" and title or nil
end

local function GetGuideTitle(dugi)
    local title = GetRawGuideTitle(dugi)
    if not title then return nil end
    if type(dugi) == "table" and type(dugi.GetFormattedTitle) == "function" then
        local ok, formatted = pcall(dugi.GetFormattedTitle, dugi, title)
        if ok and type(formatted) == "string" and formatted ~= "" then return formatted end
    end
    return title
end

local function FindPreviousDugiStep(dugi, current)
    if not current or current <= 1 or type(dugi.actions) ~= "table"
        or type(dugi.GetQuestState) ~= "function" or type(dugi.CheckForSkip) ~= "function"
    then
        return nil
    end
    for index = current - 1, 1, -1 do
        if dugi.actions[index] ~= nil then
            local ok, state = pcall(dugi.GetQuestState, dugi, index)
            if not ok then return nil end
            -- Back preserves deliberate skips and Dugi's condition/branch
            -- filtering, it never clears deliberately skipped quests.
            if state == "C" or state == "U" then
                local available, skipped = pcall(dugi.CheckForSkip, dugi, index)
                if not available then return nil end
                if skipped == false then return index end
            end
        end
    end
end

local function ReopenDugiStep(dugi, index)
    if type(dugi.SetChkToNotComplete) ~= "function" or type(dugi.MoveToPrevQuest) ~= "function"
    then
        return false
    end
    local ok = pcall(dugi.SetChkToNotComplete, dugi, index)
    if not ok then return false end
    local moved, result = pcall(dugi.MoveToPrevQuest, dugi)
    return moved and result ~= false
end

-- ============================================================
-- Step and guide commands
-- ============================================================

local function RunDugiAction(action, stepIndex, expectedGuide)
    local dugi = GetDugi()
    if type(dugi) ~= "table" or InCombatLockdown() and action ~= "active" and action ~= "route" then return false,
            "unavailable" end
    if expectedGuide and GetRawGuideTitle(dugi) ~= expectedGuide then return false, "stale_guide" end
    local index = tonumber(stepIndex) or CurrentIndex()
    local function invoke(object, method, ...)
        if type(object) ~= "table" or type(object[method]) ~= "function" then return false end
        local ok, result = pcall(object[method], ...)
        return ok and result ~= false
    end
    local ok = false
    if action == "previous" then
        local previous = FindPreviousDugiStep(dugi, index)
        ok = previous and ReopenDugiStep(dugi, previous) or false
    elseif action == "next" then
        local guides = dugi.Modules and dugi.Modules.Guides
        if index and guides and type(guides.MoveToNextQuest) == "function" then
            ok = invoke(dugi, "SetChkToComplete", dugi, index)
            if ok then ok = invoke(guides, "MoveToNextQuest") end
        end
    elseif action == "complete" or action == "skip" then
        if index then ok = invoke(dugi, action == "complete" and "SetChkToComplete" or "SkipQuest", dugi, index) end
    elseif action == "route" then
        ok = type(NS.ActivateGuideProvider) == "function" and NS.ActivateGuideProvider(PROVIDER,
            "DugiTrackerRoute", { explicit = true }) ~= false
    elseif action == "active" then
        ok = type(NS.SelectGuideProvider) == "function" and
        NS.SelectGuideProvider(PROVIDER, "DugiTrackerMakeActive") ~= false
    elseif action == "guides" or action == "chooser" then
        ok = invoke(dugi, "ShowLargeWindow", dugi)
        if ok and action == "chooser" then
            local main = rawget(_G, "DugisMain")
            if main and main.homeTab then invoke(main.homeTab, "Click", main.homeTab) end
        end
    elseif action == "reload" then
        ok = invoke(dugi, "ReloadCurrentGuide", dugi)
    elseif action == "settings" then
        ok = invoke(dugi, "ShowSettings", dugi)
    end
    if ok then
        if NS.ScheduleGuideProviderEvaluation then NS.ScheduleGuideProviderEvaluation(PROVIDER, "DugiTracker" .. action) end
        if NS.RefreshGuideTrackerViewerProvider then NS.RefreshGuideTrackerViewerProvider(PROVIDER, action) end
    end
    return ok
end

local function AddDugiGuideEntries(root)
    Common.Tabs.AddMenu(PROVIDER, root, module)
end

local function ShowDugiGuideDropdown(anchor)
    local menu = rawget(_G, "MenuUtil")
    if not menu or type(menu.CreateContextMenu) ~= "function" then
        RunDugiAction("chooser"); return
    end
    NS.Internal.Menus.CreateContextMenu(anchor or UIParent, function(_, root)
        root:CreateTitle("Dugi Guides")
        AddDugiGuideEntries(root)
    end)
end

local function ShowDugiActionMenu(anchor)
    local MenuUtil = rawget(_G, "MenuUtil")
    if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then
        return RunDugiAction("guides")
    end
    NS.Internal.Menus.CreateContextMenu(anchor or _G.UIParent, function(_, root)
        root:SetTag("MENU_AWP_DUGI_TRACKER")
        root:CreateTitle("Dugi Tracker Viewer")
        if Common.QuestDetails then Common.QuestDetails.AddMenu(root, anchor) end
        root:CreateButton("Make Dugi Active", function() RunDugiAction("active") end)
        root:CreateButton("Route This Step", function() RunDugiAction("route") end)
        root:CreateButton("Mark Step Complete", function() RunDugiAction("complete") end)
        root:CreateButton("Skip This Step", function() RunDugiAction("skip") end)
        local dugi = GetDugi()
        if dugi and type(dugi.ReloadCurrentGuide) == "function" then
            root:CreateButton("Reload Guide / Recheck Progress", function() RunDugiAction("reload") end)
        end
        if type(root.CreateDivider) == "function" then root:CreateDivider() end
        root:CreateTitle("Open Guides")
        AddDugiGuideEntries(root)
        local search = NS.Internal.DugiProvider
        local options = search and search.GetNearestOptions()
        if options and #options > 0 then
            local nearest = root:CreateButton("Find Nearest")
            for _, option in ipairs(options) do
                local id = option.id
                if option.children then
                    local group = nearest:CreateButton(option.label)
                    group:CreateButton("Any Profession Trainer", function() search.FindNearest(id) end)
                    for _, child in ipairs(option.children) do
                        local spell = child.id
                        group:CreateButton(child.label, function() search.FindNearest(spell) end)
                    end
                else
                    nearest:CreateButton(option.label, function() search.FindNearest(id) end)
                end
            end
        end
    end)
    return true
end

local function CreateControls(frame)
    if type(SharedControls) ~= "table" or type(SharedControls.Create) ~= "function" then return end
    SharedControls.Create(frame, {
        settingsTooltip = "Dugi settings",
        menuTooltip = "Dugi guides and actions",
        previousTooltip = "Previous step",
        nextTooltip = "Next step",
        onSettings = function() RunDugiAction("settings") end,
        onMenu = ShowDugiActionMenu,
        onPrevious = function() RunDugiAction("previous") end,
        onNext = function() RunDugiAction("next") end,
    })
end

local function OnGuideChoiceClick(_, mouseButton)
    if mouseButton == "LeftButton" then RunDugiAction("chooser") end
end

local function WireDugiLine(line, hasGuideLinks, tooltipTitle, tips)
    if not line then return end
    if type(line.EnableMouse) == "function" then
        line:EnableMouse(hasGuideLinks == true or type(tips) == "table" and #tips > 0)
    end
    SharedRender.WireTipTooltip(line, tooltipTitle, tips)
    if type(line.SetScript) == "function" then
        line:SetScript("OnMouseUp", hasGuideLinks and OnGuideChoiceClick or nil)
        if Common.QuestDetails then Common.QuestDetails.WireRow(line, ShowDugiActionMenu) end
    end
end


local function IsGuideLoading(dugi, current)
    if type(dugi) ~= "table" or not GetRawGuideTitle(dugi) then return false end
    if dugi.firstGuideLoaded ~= true then return true end
    if not current then return true end
    return type(dugi.actions) ~= "table"
        or dugi.actions[current] == nil
        or type(dugi.quests1L) ~= "table"
        or dugi.quests1L[current] == nil
end

local function ClearArray(values) for index = #values, 1, -1 do values[index] = nil end end
local function SameArray(first, second)
    if #first ~= #second then return false end
    for index = 1, #first do if first[index] ~= second[index] then return false end end
    return true
end

local function ObserveGuide(dugi, guide)
    if guide and guide ~= observedGuide then
        Common.DugiTabs.GetState()
        observedGuide = guide
    elseif not guide then
        observedGuide = nil
    end
end

local function RefreshViewerSnapshot()
    local dugi, current = GetDugi(), CurrentIndex()
    local guide, title = GetRawGuideTitle(dugi), GetGuideTitle(dugi)
    local loading, total, percent = IsGuideLoading(dugi, current), nil, nil
    if type(dugi) == "table" and type(dugi.SetPercentComplete) == "function"
        and guide and progressGuide ~= guide
    then
        loading = true
    end
    local guides = dugi and dugi.Modules and dugi.Modules.Guides
    if guides and progressGuide == guide then percent = tonumber(guides.percentComplete) end
    if type(dugi) == "table" and type(dugi.GetLastUsedStepIndex) == "function" then
        local ok, value = pcall(dugi.GetLastUsedStepIndex)
        if ok then total = tonumber(value) end
    end
    if total and total < 1 and dugi and dugi.firstGuideLoaded then guide, title, loading = nil, nil, false end
    ClearArray(nextSteps); ClearArray(nextStickies)
    if type(dugi) == "table" and guide and not loading then
        for _, index in ipairs(Presentation.GetRelevantIndices(dugi, current, true, relevantIndices, relevantSeen)) do
            local resolved = Presentation.ResolveStep(dugi, index)
            if resolved then nextSteps[#nextSteps + 1] = resolved end
        end
    end
    local sticky = dugi and dugi.Modules and dugi.Modules.StickyFrame and dugi.Modules.StickyFrame.StickyQuests
    if type(sticky) == "table" and guide and not loading then
        for _, index in ipairs(sticky) do
            if index ~= current then
                local resolved = Presentation.ResolveStep(dugi, tonumber(index))
                if resolved then nextStickies[#nextStickies + 1] = resolved end
            end
        end
    end
    Presentation.RetainViewerSteps(guide and not loading and relevantSeen or nil)
    -- Observe guide identities on the existing coalesced refresh, so visiting
    -- another guide in Dugi's own chooser also retains the guide being left.
    if not loading then ObserveGuide(dugi, guide) end
    local previous = viewerSnapshot
    if previous.guide == guide and previous.title == title and previous.current == current
        and previous.loading == loading and previous.total == total and previous.percent == percent
        and SameArray(previous.steps, nextSteps) and SameArray(previous.stickies, nextStickies)
    then
        return false
    end
    viewerSnapshot = {
        guide = guide,
        title = title,
        current = current,
        loading = loading,
        total = total,
        percent = percent,
        steps = nextSteps,
        stickies = nextStickies
    }
    nextSteps, nextStickies = previous.steps, previous.stickies
    return true
end

-- ============================================================
-- Chat and tracker rows
-- ============================================================

local function OutputStepChat(snapshot, mode)
    local model = Common.Chat.FromSnapshot(snapshot, true)
    model.label = "Dugi"
    return Common.Chat.Output(PROVIDER, model, mode)
end

local function RenderModule(self)
    if not IsDugiReady() then
        self.hasContents = false; return
    end
    local snapshot = viewerSnapshot
    local current, total = snapshot.current, snapshot.total
    local block = self:GetBlock(BLOCK_ID)
    if not block then
        self.hasContents = false; return
    end
    block.parentModule = self
    if block.HeaderButton and type(block.HeaderButton.RegisterForClicks) == "function" then
        block.HeaderButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    local title = snapshot.title
    local blockTitle = title or "No Dugi guide selected"
    local loading = snapshot.loading
    if loading then blockTitle = "Dugi (loading guide...)" end
    if type(SharedControls) == "table" and type(SharedControls.SetBlockHeaderText) == "function" then
        SharedControls.SetBlockHeaderText(block, blockTitle, title ~= nil and not loading)
    elseif block.HeaderText then
        block.HeaderText:SetText(blockTitle)
    end
    if type(SharedControls) == "table" and type(SharedControls.SetModuleHeader) == "function" then
        SharedControls.SetModuleHeader(self, PROVIDER, "Dugi Guides")
    end
    if type(SharedControls) == "table" and type(SharedControls.Update) == "function" then
        local displayCurrent = not loading and current or nil
        SharedControls.Update(self, displayCurrent, loading and 0 or total, loading and 0 or snapshot.percent)
    end
    local currentStep
    for _, step in ipairs(snapshot.steps) do
        if step.ownerStepIndex == current then
            currentStep = step
            break
        end
    end
    if currentStep and not loading then
        block._awpDugiStep, block._awpDugiGuide = current, snapshot.guide
        if not block._awpDugiCompletion then
            block._awpDugiCompletion = {
                checked = false,
                tooltip = "Mark step complete",
                detail = "Skips to the next valid step.",
                onClick = function() RunDugiAction("next", block._awpDugiStep, block._awpDugiGuide) end
            }
        end
        SharedControls.SetStepCheckbox(block, block.HeaderText, block._awpDugiCompletion)
    else
        block._awpDugiStep, block._awpDugiGuide = nil, nil
        SharedControls.SetStepCheckbox(block, block.HeaderText, nil)
    end
    if loading then
        block.height = 28
        if type(self.LayoutBlock) == "function" then pcall(self.LayoutBlock, self, block) end
        self.hasContents = true
        return
    end
    local objectiveKey = 0
    if #snapshot.steps == 0 then
        objectiveKey = 1
        local line = SharedRender.AddObjective(block, objectiveKey, EMPTY_GUIDE_ROW)
        WireDugiLine(line, true)
    else
        for _, presentation in ipairs(snapshot.steps) do
            block._awpOwnerStepIndex = presentation.ownerStepIndex
            for rowIndex, row in ipairs(presentation.rows) do
                objectiveKey = objectiveKey + 1
                local line = SharedRender.AddObjective(block, objectiveKey, row)
                local tips = row.tips
                if rowIndex == 1 and not tips and presentation.fullNote then
                    tips = presentation.tooltipTips
                end
                WireDugiLine(line, presentation.hasGuideLinks, row.tooltipTitle or presentation.title, tips)
            end
        end
    end
    SharedRender.EnsureBlockHeight(block, 28)
    if type(self.LayoutBlock) == "function" then pcall(self.LayoutBlock, self, block) end
    self.hasContents = true
end

-- ============================================================
-- Tracker module and native frames
-- ============================================================

local function CreateModule()
    if module then return module end
    local frame = ModuleFactory.Create({
        host = Host,
        providerKey = "dugi",
        name = MODULE_NAME,
        headerText = "Dugi Guides",
        uiOrder = 2.1,
    })
    if not frame then return nil end
    module = frame
    CreateControls(frame)
    if HeaderStyle then
        HeaderStyle.CaptureBaseline(frame)
        HeaderStyle.Refresh(frame)
    end
    function frame:LayoutContents() RenderModule(self) end

    function frame:OnBlockHeaderClick(block, mouseButton)
        if mouseButton == "LeftButton" then
            ShowDugiGuideDropdown(self)
        elseif mouseButton == "RightButton" then
            ShowDugiActionMenu(block or self)
        end
    end

    return frame
end

local controller = Common.CreateViewerController({
    providerKey = PROVIDER,
    host = Host,
    createModule = CreateModule,
    isEnabled = function() return GetSettings().enabled and IsDugiReady() end,
    onAttach = function()
        attached = true; RefreshViewerSnapshot()
    end,
    onDetach = function() attached = false end,
})
local function MarkDirty() controller:MarkDirty() end
local function Attach() return controller:Attach() end
local function Detach() controller:Detach() end

local function GetNativeModelFrame(dugi)
    local model = dugi and dugi.Modules and dugi.Modules.ModelViewer
    return model and model.Frame or rawget(_G, "DugisGuideViewer_ModelViewer")
end

local cloak = Common.CreateNativeFrameCloak({
    alpha = 0.01,
    anchor = { "TOPLEFT", UIParent, "BOTTOMRIGHT", 200, -200 },
    resolve = function()
        local dugi, frame = GetDugi(), rawget(_G, "DugisSmallFrameContainer")
        local floating = IsSmallFrameFloating(dugi)
        local frames = {}
        if floating then
            if frame then frames[#frames + 1] = frame end
            -- The companion model is parented to UIParent, not the guide.
            local model = GetNativeModelFrame(dugi)
            if model and model ~= frame then frames[#frames + 1] = model end
        end
        return frames, GetSettings().hideDugiFrame and IsDugiReady() and floating == true
    end,
})
local function RestoreNativeFrame() return cloak:Apply({}, false) end
local function HideFloatingNativeFrame()
    local dugi, frame = GetDugi(), rawget(_G, "DugisSmallFrameContainer")
    if not dugi or not (frame or GetNativeModelFrame(dugi)) then return false, "Dugi's floating frame is not ready." end
    if IsSmallFrameFloating(dugi) ~= true then
        RestoreNativeFrame()
        return false, "Disable Dugi's Anchored Small Frame setting before AWP can hide its floating frame safely."
    end
    return cloak:Refresh()
end

local appliedState = {}
local function ApplySettings(force)
    local settings = GetSettings()
    local ready = IsDugiReady()
    local manager, container = Host.GetManager(), Host.GetTrackerFrame()
    local registered = module and Host.IsActuallyRegistered(manager, module, container) or false
    local native = rawget(_G, "DugisSmallFrameContainer")
    local model = GetNativeModelFrame(GetDugi())
    local floating
    local dugi = GetDugi()
    if settings.hideDugiFrame and dugi and type(dugi.IsSmallFrameFloating) == "function" then
        local ok, value = pcall(dugi.IsSmallFrameFloating, dugi)
        if ok then floating = value end
    end
    if force == false and appliedState.settings == settings and appliedState.ready == ready
        and appliedState.manager == manager and appliedState.container == container
        and appliedState.native == native and appliedState.model == model and appliedState.floating == floating
        and appliedState.registered == registered and (not settings.enabled or registered or not ready)
    then
        return false
    end
    if settings.enabled and ready then
        Attach()
    else
        Detach()
    end
    if not ready or not settings.enabled and not settings.chatOutputOnChange then Presentation.RetainViewerSteps(nil) end
    if not ready then Presentation.SetRouteOwner(nil) end
    if module and HeaderStyle then HeaderStyle.Refresh(module) end
    if settings.hideDugiFrame and IsDugiReady() then HideFloatingNativeFrame() else RestoreNativeFrame() end
    if Common.Registry then Common.Registry.RefreshIndicators() end
    appliedState.settings, appliedState.ready = settings, ready
    appliedState.manager, appliedState.container, appliedState.native, appliedState.floating = manager, container, native,
        floating
    appliedState.model = model
    appliedState.registered = module and Host.IsActuallyRegistered(manager, module, container) or false
    return true
end

-- ============================================================
-- Refresh scheduling
-- ============================================================

local function RunRefresh()
    local content, apply, chat, data, install = refreshContent, refreshSettings, refreshChat, refreshData,
        pendingHookInstaller
    refreshContent, refreshSettings, refreshChat, refreshData, pendingHookInstaller = false, false, false, false, nil
    if install then install() end
    local dataChanged = data and Presentation.FlushDataEvents() or false
    if apply then ApplySettings(false) end
    local settings = GetSettings()
    if content or dataChanged then
        local ready = IsDugiReady()
        if ready and (settings.enabled or settings.chatOutputOnChange) then
            if RefreshViewerSnapshot() and attached and settings.enabled then MarkDirty() end
            if chat and settings.chatOutputOnChange and viewerSnapshot.title and not viewerSnapshot.loading
                and (lastChatGuide ~= viewerSnapshot.guide or lastChatStep ~= viewerSnapshot.current)
                and type(NS.Msg) == "function"
            then
                lastChatGuide, lastChatStep = viewerSnapshot.guide, viewerSnapshot.current
                OutputStepChat(viewerSnapshot)
            end
        else
            Presentation.RetainViewerSteps(nil)
            if not ready then Presentation.SetRouteOwner(nil) end
            local dugi = GetDugi()
            if ready and not IsGuideLoading(dugi, CurrentIndex()) then ObserveGuide(dugi, GetRawGuideTitle(dugi)) end
        end
    end
    if dataChanged and type(NS.ScheduleGuideProviderEvaluation) == "function" then
        NS.ScheduleGuideProviderEvaluation(PROVIDER, "DugiDataReady", DATA_REFRESH_OPTIONS)
    end
end

local refreshQueue = NS.Internal.Scheduling.CreateCoalescer(RunRefresh)
local function ScheduleRefresh(reason, install)
    if install then pendingHookInstaller = install end
    if reason == "data_ready" then refreshData = true else refreshContent = true end
    if reason == "settings" then refreshSettings = true end
    if reason == "step" or reason == "guide" then refreshChat = true end
    refreshQueue:Request()
end

NS.GetDugiNativeFrameHideStatus = function()
    if not GetSettings().hideDugiFrame then return "shown", "Dugi's native frame is not hidden by AWP." end
    local dugi = GetDugi()
    if dugi and IsSmallFrameFloating(dugi) == false then
        return "anchored", "Disable Dugi's Anchored Small Frame setting before AWP can hide its floating frame safely."
    end
    return cloak:IsApplied() and "hidden" or "waiting",
        "AWP hides Dugi's floating guide frame and its companion model viewer."
end

NS.GetDugiTrackerViewerStatus = function()
    local settings = GetSettings()
    local host = Host.GetHostID()
    local registered = module and Host.IsActuallyRegistered(Host.GetManager(), module, Host.GetTrackerFrame()) or false
    return {
        enabled = settings.enabled == true,
        attached = attached == true and registered == true,
        moduleCreated = module ~= nil,
        host = host,
        hostReady = not Host.IsKTLoaded() or Host.IsKTReady(),
        dugiReady = IsDugiReady(),
        hooksInstalled = hooksInstalled,
    }
end

local function LoadCommandGuide(query)
    local dugi, catalog = GetDugi(), {}
    if type(dugi.DisplayViewTabInThread) ~= "function" then return false, "loader_unavailable" end
    for _, group in pairs(dugi.guidelist or {}) do
        if type(group) == "table" then
            for _, id in ipairs(group) do
                if type(id) == "string" then
                    local label = id
                    if type(dugi.GetFormattedTitle) == "function" then
                        local ok, value = pcall(dugi.GetFormattedTitle, dugi, id)
                        if ok then label = Presentation.StripMarkup(value) or id end
                    end
                    catalog[#catalog + 1] = { id = id, label = label }
                end
            end
        end
    end
    local id, reason = Common.Actions.ResolveGuide(query or "", catalog)
    if not id then return false, reason end
    return Common.DugiTabs.Load(id)
end
local commandControls = {
    hasGuide = function()
        local dugi = GetDugi()
        return GetRawGuideTitle(dugi) ~= nil and not IsGuideLoading(dugi, CurrentIndex())
    end,
    next = function() return RunDugiAction("next") end,
    prev = function() return RunDugiAction("previous") end,
    skip = function() return RunDugiAction("skip") end,
    complete = function() return RunDugiAction("complete") end,
    active = function() return RunDugiAction("active") end,
    route = function() return RunDugiAction("route") end,
    reload = function() return RunDugiAction("reload") end,
    picker = function() return RunDugiAction("chooser") end,
    settings = function() return RunDugiAction("settings") end,
    menu = function() return ShowDugiActionMenu(UIParent) end,
    tabState = Common.DugiTabs.GetState,
    switch = Common.DugiTabs.Switch,
    close = Common.DugiTabs.Close,
    closeAll = Common.DugiTabs.CloseAll,
    newGuide = Common.DugiTabs.NewGuide,
    load = LoadCommandGuide,
    output = function(mode)
        RefreshViewerSnapshot()
        return OutputStepChat(viewerSnapshot, mode)
    end,
    reset = function()
        NS.SetGuideTrackerViewerProviderSetting(PROVIDER, "hideNative", false)
        NS.ApplyGuideTrackerViewerSettings(PROVIDER)
        local dugi = GetDugi()
        local small = dugi.Modules and dugi.Modules.SmallFrame
        if type(dugi.IsSmallFrameFloating) == "function" and dugi:IsSmallFrameFloating()
            and small and type(small.Reset) == "function" then
            local ok, result = pcall(small.Reset, small); return ok and result ~= false
        end
        return true, "Native frame uncloaked, floating-window reset is unavailable in anchored mode."
    end,
}

NS.RegisterGuideTrackerViewerProvider(PROVIDER, {
    displayName = "Dugi Guides",
    isAvailable = IsDugiReady,
    moduleName = MODULE_NAME,
    applySettings = ApplySettings,
    refresh = ScheduleRefresh,
    isAttached = function() return attached and module ~= nil end,
    controls = commandControls,
    runAction = RunDugiAction,
})

-- ============================================================
-- Hook installation and startup
-- ============================================================

local function InstallHooks()
    local dugi = GetDugi()
    if type(dugi) ~= "table"
        or type(dugi.GetQuestStepText) ~= "function"
    then
        return false
    end
    if not hooksInstalled and dugi.firstGuideLoaded then progressGuide = GetRawGuideTitle(dugi) end
    hooksInstalled = true
    local function hook(object, method, reason, after, rebind)
        if type(object) ~= "table" or type(object[method]) ~= "function" then return end
        local methods = hookedMethods[object] or {}
        hookedMethods[object] = methods
        if methods[method] == object[method] then return end
        hooksecurefunc(object, method, function()
            if after then after() end
            ScheduleRefresh(reason, rebind and InstallHooks or nil)
        end)
        methods[method] = object[method]
    end
    -- DisplayViewTab is coroutine-backed and must remain unwrapped.
    -- UpdateGuideVisualRows runs after parsing and does not yield.
    hook(dugi, "UpdateGuideVisualRows", "guide")
    hook(dugi, "ClearScreen", "guide_cleared")
    hook(dugi, "SetViewTabTitle", "guide")
    hook(dugi, "SetPercentComplete", "step", function() progressGuide = GetRawGuideTitle(dugi) end)
    hook(dugi, "MoveToPrevQuest", "step")
    hook(dugi, "SetChkToComplete", "step")
    hook(dugi, "SetChkToNotComplete", "step")
    hook(dugi, "UnSkipQuest", "step")
    hook(dugi, "SkipQuest", "step")
    hook(dugi, "SettingFrameChkOnClick", "settings")
    -- Mode changes can reload/yield through Dugi's parser. Observe the
    -- non-yielding status refresh instead of wrapping the mode-change methods.
    hook(dugi, "UpdateIconStatus", "settings", nil, true)
    local model = dugi.Modules and dugi.Modules.ModelViewer
    -- Model initialization only defines its UI methods, it does not parse
    -- guides. Rebind after initialization to observe late frame creation.
    hook(model, "Initialize", "settings", nil, true)
    hook(model, "CreateFrame", "settings")
    hook(model, "OnModulesLoaded", "settings")
    local guides = dugi.Modules and dugi.Modules.Guides
    hook(guides, "MoveToNextQuest", "step")
    hook(dugi.DugisArrow, "WaypointsChanged", "waypoint")
    return true
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN"); watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
local presentationEvents = {
    "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "QUEST_DATA_LOAD_RESULT", "QUEST_LOG_UPDATE", "UNIT_NAME_UPDATE",
    "SPELL_DATA_LOAD_RESULT", "SPELLS_CHANGED",
}
local startupTicker
local function StartViewer(reason)
    local alreadyInstalled = hooksInstalled
    if not InstallHooks() then return false end
    if startupTicker then
        startupTicker:Cancel(); startupTicker = nil
    end
    if not alreadyInstalled then
        watcher:UnregisterEvent("ADDON_LOADED")
        for _, event in ipairs(presentationEvents) do pcall(watcher.RegisterEvent, watcher, event) end
    end
    Presentation.Invalidate()
    if type(NS.StartGuideRoutingEvaluation) == "function" then NS.StartGuideRoutingEvaluation() end
    ApplySettings()
    ScheduleRefresh(reason)
    return true
end

local function CheckStartup(reason)
    if StartViewer(reason) or startupTicker or not C_Timer or not C_Timer.NewTicker then return end
    -- Dugi can finish installing its viewer methods after its addon has loaded.
    local remaining = 60
    startupTicker = C_Timer.NewTicker(0.5, function()
        remaining = remaining - 1
        if not StartViewer("late_init") and remaining == 0 then
            startupTicker:Cancel()
            startupTicker = nil
        end
    end)
end

watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "ADDON_LOADED" then
        if unit == "DugisGuideViewerZ" then CheckStartup("late_init") end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        if GetDugi() then CheckStartup("login") end
    elseif hooksInstalled then
        if event == "UNIT_NAME_UPDATE" and unit ~= "target" and unit ~= "npc" then return end
        if Presentation.QueueDataEvent(event, unit) then ScheduleRefresh("data_ready") end
    end
end)
