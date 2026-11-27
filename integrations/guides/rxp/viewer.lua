-- ============================================================
-- RestedXP Viewer
-- ============================================================
--
-- Renders RestedXP steps in the tracker and forwards step selection and guide
-- controls to the native guide.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local API, P = NS.Internal.RXPProvider, NS.Internal.RXPPresentation
if Common.QuestDetails then Common.QuestDetails.RegisterSource("rxp", API.GetSnapshot) end
local Host, Controls, Render = Common.Host, Common.Controls, Common.Render
local module
local lastChatGuide, lastChatStep
local WAITING_CONCURRENT_ROWS = { {
    text = "Complete the active steps above to continue.",
    kind = "tip",
    status = "passive",
    fullHeight = true
} }
local WAITING_DATA_ROWS = { {
    text = "Waiting for RestedXP's active step data.",
    kind = "tip",
    status = "passive",
    fullHeight = true
} }

local function Settings() return NS.GetGuideTrackerViewerSettings("rxp") end
local STEP_PROMPT = "AWP_RXP_GO_TO_STEP"

local function StepSelectionMessage(reason, total)
    if type(NS.Msg) ~= "function" then return end
    if reason == "invalid_step" then
        NS.Msg("RestedXP: Enter a whole step number from 1 to " .. tostring(total) .. ".")
    elseif reason == "stale" then
        NS.Msg("RestedXP's guide or step changed. Open Go to Step again.")
    elseif reason == "unavailable" then
        NS.Msg("RestedXP step controls are unavailable while paused or in combat.")
    elseif reason == "no_previous_step" then
        NS.Msg("There is no earlier selectable step. Use Go to Step to choose a destination.")
    else
        NS.Msg("RestedXP could not select that step.")
    end
end

local function AcceptStepSelection(dialog, data)
    local index = tonumber(dialog:GetEditBox():GetText())
    local ok, reason = API.RunAction("goto", data.guide, data.current, index, data.epoch)
    if not ok then
        StepSelectionMessage(reason, data.total)
        return reason == "invalid_step" -- keep invalid input available to correct
    end
    return false
end

local function ShowStepSelection(suggested)
    local s = API.GetSnapshot()
    if s.state ~= "ready" or not s.id or InCombatLockdown() then
        StepSelectionMessage("unavailable"); return false
    end
    StaticPopupDialogs[STEP_PROMPT] = StaticPopupDialogs[STEP_PROMPT] or {
        text = "Go to RestedXP step (1-%d).\nRestedXP will continue from the selected point.",
        button1 = "Go to Step",
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 8,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnShow = function(dialog, data)
            local edit = dialog:GetEditBox()
            edit:SetText(tostring(data.suggested)); edit:HighlightText(); edit:SetFocus()
        end,
        OnAccept = AcceptStepSelection,
        EditBoxOnEnterPressed = function(edit)
            local dialog = edit:GetParent()
            if not AcceptStepSelection(dialog, dialog.data) then dialog:Hide() end
        end,
        EditBoxOnEscapePressed = function(edit) edit:GetParent():Hide() end,
    }
    return NS.Internal.Dialogs.Show(STEP_PROMPT, s.total, nil, {
        guide = s.id, current = s.current, total = s.total, suggested = suggested or s.current, epoch = s.guideEpoch,
    }) ~= nil
end

-- ============================================================
-- Step and guide actions
-- ============================================================

local function Run(action)
    local s = API.GetSnapshot()
    local ok, reason, suggested = API.RunAction(action, s.id, s.current, nil, s.guideEpoch)
    if not ok and reason == "choose_step" then return ShowStepSelection(suggested) end
    if not ok and reason then StepSelectionMessage(reason, s.total) end
    return ok
end

local function NativeFrames()
    local rxp = API.GetRuntime()
    local frames = {}
    if not rxp then return frames end
    if rxp.RXPFrame then
        frames[#frames + 1] = rxp.RXPFrame
        local current = rxp.RXPFrame.CurrentStepFrame
        for _, frame in ipairs(current and current.framePool or {}) do
            if frame.step and frame.step.tip then frames[#frames + 1] = frame end
        end
    end
    local v2 = rxp.v2 and rxp.v2.state
    local window = v2 and v2.guideWindow
    if window and window.frame then frames[#frames + 1] = window.frame end
    local player = v2 and v2.player and rxp.player and v2.player[rxp.player.name]
    local active = player and player.activeStepFrame
    if active and active.frame then frames[#frames + 1] = active.frame end
    return frames
end

local cloak = Common.CreateNativeFrameCloak({
    resolve = function()
        return NativeFrames(), Settings().hideNative and API.GetRuntime() ~= nil
    end
})

local function CloseGuide(id)
    local s = API.GetSnapshot()
    if s.id == id and not API.RunAction("close", id, s.current, nil, s.guideEpoch) then return false end
    local list = {}
    for _, current in ipairs(Common.GetOpenGuides("rxp") or {}) do
        if current ~= id then list[#list + 1] = current end
    end
    Common.SetOpenGuides("rxp", list)
    API.Schedule("RXPGuideClosed")
    return true
end

local function OpenGuides(root)
    Common.Tabs.AddMenu("rxp", root, module)
end

local function Menu(anchor, titleOnly)
    if not MenuUtil or not MenuUtil.CreateContextMenu then return Run("chooser") end
    NS.Internal.Menus.CreateContextMenu(anchor or module or UIParent, function(_, root)
        root:CreateTitle("RestedXP Guides")
        if not titleOnly and Common.QuestDetails then Common.QuestDetails.AddMenu(root, anchor) end
        if not titleOnly then
            local current = API.GetSnapshot()
            local function runStep(action) API.RunAction(action, current.id, current.current, nil, current.guideEpoch) end
            root:CreateButton("Make RestedXP Active", function() Run("active") end)
            local enabled = current.state == "ready" and not InCombatLockdown()
            root:CreateButton("Route This Step", function() runStep("route") end):SetEnabled(current.state == "ready")
            root:CreateButton("Mark Step Complete", function() runStep("complete") end):SetEnabled(enabled)
            root:CreateButton("Skip This Step", function() runStep("skip") end):SetEnabled(enabled)
            root:CreateButton("Reload Guide / Recheck Progress", function() runStep("reload") end)
            root:CreateButton("Open RestedXP Settings", function() Run("settings") end)
            root:CreateDivider()
        end
        root:CreateButton("Go to Step...", function() ShowStepSelection() end)
            :SetEnabled(API.GetSnapshot().state == "ready" and not InCombatLockdown())
        OpenGuides(root)
    end)
end

local function RenderRows(block, rows, offset)
    local index = offset or 0
    for _, row in ipairs(rows) do
        index = index + 1
        local line = Render.AddObjective(block, index, row)
        if line then
            line:SetScript("OnMouseUp", nil)
            Render.WireTipTooltip(line, row.tooltipTitle, row.tips)
            if Common.QuestDetails then Common.QuestDetails.WireRow(line, function(anchor) Menu(anchor, false) end) end
        end
    end
    return index
end

local function RenderModule(self)
    local s = API.GetSnapshot()
    Controls.SetModuleHeader(self, "rxp", "RestedXP Guides")
    Controls.Update(self, s.state == "ready" and s.current or 0, s.state == "ready" and s.total or 0)
    if s.state ~= "ready" then
        local block = self:GetBlock("AwpRXPStatus")
        if not block then
            self.hasContents = false; return
        end
        Controls.SetBlockHeaderText(block, s.state == "loading" and "RestedXP (loading guide...)"
            or s.state == "paused" and "RestedXP (paused)" or "RestedXP (no guide selected)")
        Controls.SetStepCheckbox(block, block.HeaderText, nil)
        local line = Render.AddObjective(block, 1,
            {
                text = s.state == "paused" and "Open RestedXP settings to resume guide processing."
                    or "Click here to select a guide.",
                kind = "goal",
                action = "note",
                fullHeight = true
            })
        if line then
            Render.WireTipTooltip(line, nil, nil)
            line:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" then Run(s.state == "paused" and "settings" or "chooser") end
            end)
        end
        block.height = math.max(block.height or 0, 42)
        self:LayoutBlock(block); self.hasContents = true; return
    end
    local guideBlock = self:GetBlock("AwpRXPGuide")
    if not guideBlock then
        self.hasContents = false; return
    end
    guideBlock.parentModule = self
    Controls.SetBlockHeaderText(guideBlock, s.title or "RestedXP Guide", true)
    local lineCount, currentVisible = 0, false
    for _, step in ipairs(s.steps) do
        guideBlock._awpOwnerStepIndex = step.index
        if step.sticky then
            local block = self:GetBlock("AwpRXPStep" .. tostring(step.index or "tip"))
            if block then
                block.parentModule = self
                block._awpOwnerStepIndex = step.index
                Controls.SetBlockHeaderText(block, "Sticky: " .. step.title)
                if Common.QuestDetails then Common.QuestDetails.BindSection(block, "rxp", step.rows) end
                Controls.SetStepCheckbox(block, block.HeaderText, nil)
                local count = RenderRows(block, step.headerRows)
                block.height = math.max(block.height or 0, count > 0 and 28 or 22)
                self:LayoutBlock(block)
            end
        else
            lineCount = RenderRows(guideBlock, step.rows, lineCount)
            if step.index == s.current then currentVisible = true end
        end
    end
    if currentVisible then
        if not guideBlock._awpRXPBinding then
            local binding = {}
            binding.onClick = function() API.RunAction("complete", binding.guide, binding.step, nil, binding.epoch) end
            guideBlock._awpRXPBinding = binding
        end
        guideBlock._awpRXPBinding.guide, guideBlock._awpRXPBinding.step = s.id, s.current
        guideBlock._awpRXPBinding.epoch = s.guideEpoch
        Controls.SetStepCheckbox(guideBlock, guideBlock.HeaderText, guideBlock._awpRXPBinding)
    else
        Controls.SetStepCheckbox(guideBlock, guideBlock.HeaderText, nil)
    end
    if lineCount == 0 then
        lineCount = RenderRows(guideBlock, #s.steps > 0 and WAITING_CONCURRENT_ROWS or WAITING_DATA_ROWS)
    end
    Render.EnsureBlockHeight(guideBlock, lineCount > 0 and 28 or 22)
    self:LayoutBlock(guideBlock)
    self.hasContents = true
end

-- ============================================================
-- Native menus and viewer registration
-- ============================================================

local function OpenNativeMenu(anchor)
    if API.OpenViewerMenu(anchor) then return true end
    return Run("settings")
end

local function CreateModule()
    if module then return module end
    module = Common.ModuleFactory.Create({
        host = Host,
        providerKey = "rxp",
        name = "AwpRXPTrackerModule",
        headerText =
        "RestedXP Guides",
        uiOrder = 2.2
    })
    if not module then return end
    Controls.Create(module, {
        settingsTooltip = "RestedXP menu",
        menuTooltip = "RestedXP guides and actions",
        previousTooltip = "Go back / recover a missing quest",
        onSettings = OpenNativeMenu,
        onMenu = function(anchor) Menu(anchor) end,
        onPrevious = function() Run("previous") end,
        onNext = function() Run("next") end
    })
    function module:LayoutContents() RenderModule(self) end

    function module:OnBlockHeaderClick(block, button)
        Menu(block or self, button == "LeftButton")
    end

    if Common.HeaderStyle then
        Common.HeaderStyle.CaptureBaseline(module); Common.HeaderStyle.Refresh(module)
    end
    return module
end

local controller = Common.CreateViewerController({
    providerKey = "rxp",
    host = Host,
    createModule = CreateModule,
    isEnabled = function() return Settings().enabled and API.GetRuntime() ~= nil end,
    isAvailable = function()
        local rxp = API.GetRuntime(); return rxp and rxp.RXPFrame and rxp.settings
    end
})

-- ============================================================
-- Settings and refresh
-- ============================================================

local function ApplySettings()
    local settings = Settings()
    if settings.enabled and API.GetRuntime() then controller:Attach() else controller:Detach() end
    cloak:Apply(NativeFrames(), settings.hideNative and API.GetRuntime() ~= nil)
    if module and Common.HeaderStyle then Common.HeaderStyle.Refresh(module) end
    if type(NS.MaybeShowRXPArrowRecommendationPopup) == "function" then NS.MaybeShowRXPArrowRecommendationPopup() end
end

local function PrintChat(s, mode)
    if s.state ~= "ready" then return false, "no_guide" end
    local model = Common.Chat.FromSnapshot(s)
    model.label = "RestedXP"
    return Common.Chat.Output("rxp", model, mode)
end
local function OutputChat(s)
    local settings = NS.GetGuideTrackerViewerProviderSettings("rxp")
    if not settings.chatOutputOnChange or s.state ~= "ready" then return end
    if s.id == lastChatGuide and s.current == lastChatStep then return end
    lastChatGuide, lastChatStep = s.id, s.current
    PrintChat(s)
end

API.Subscribe(function(s, changed)
    if changed and Settings().enabled then controller:Attach() end
    if changed then
        OutputChat(s)
        if type(NS.MaybeShowRXPArrowRecommendationPopup) == "function" then NS.MaybeShowRXPArrowRecommendationPopup() end
    end
    cloak:Apply(NativeFrames(), Settings().hideNative and API.GetRuntime() ~= nil)
end)

NS.GetRXPTrackerViewerStatus = function()
    local s = API.GetSnapshot()
    return {
        enabled = Settings().enabled,
        attached = controller:IsAttached(),
        host = Host.GetHostID(),
        state = s.state,
        moduleCreated = module ~= nil,
        nativeHidden = cloak:IsApplied()
    }
end

local function CommandGuides()
    local rxp, out, current = API.GetRuntime(), {}, API.GetSnapshot().id
    local ids, seen = {}, {}
    for _, id in ipairs(Common.GetOpenGuides("rxp") or {}) do
        ids[#ids + 1] = id; seen[id] = true
    end
    if current and not seen[current] then ids[#ids + 1] = current end
    for index = #ids, 1, -1 do
        local id = ids[index]
        local guide = rxp and P.Call(rxp, "GetGuideTable", id)
        if guide then
            out[#out + 1] = {
                id = id,
                label = P.Text(rxp, P.Call(rxp, "GetGuideName", guide) or guide.name) or id,
                active = id == current
            }
        end
    end
    return out
end
local commandControls = {
    hasGuide = function()
        local s = API.GetSnapshot()
        return s.id ~= nil and s.state == "ready"
    end,
    next = function() return Run("next") end,
    prev = function() return Run("previous") end,
    skip = function() return Run("skip") end,
    complete = function() return Run("complete") end,
    active = function() return Run("active") end,
    route = function() return Run("route") end,
    reload = function() return Run("reload") end,
    picker = function() return Run("chooser") end,
    settings = function() return Run("settings") end,
    menu = function() return API.OpenViewerMenu(UIParent) end,
    tabState = function()
        local s = API.GetSnapshot()
        return {
            mode = "recent",
            source = "rxp:" .. tostring(s.guideEpoch),
            slots = CommandGuides(),
            mutable = s.state ~= "loading" and s.state ~= "paused",
            reason = s.state
        }
    end,
    newGuide = function() return Run("chooser") end,
    switch = function(entry)
        local ok = API.SwitchGuide(entry.id)
        return ok, ok and "Guide switch requested." or "guide_switch_unavailable"
    end,
    close = function(entry) return CloseGuide(entry.id) end,
    closeAll = function()
        local s = API.GetSnapshot()
        if s.id and not API.RunAction("close", s.id, s.current, nil, s.guideEpoch) then return false end
        Common.SetOpenGuides("rxp", {})
        API.Schedule("RXPGuideClosed")
        return true
    end,
    load = function(query)
        local rxp, catalog = API.GetRuntime(), {}
        for _, guide in pairs(rxp.guides or {}) do
            if type(guide) == "table" and type(guide.group) == "string" and type(guide.name) == "string" then
                catalog[#catalog + 1] = {
                    id = guide.group .. "||" .. guide.name,
                    label = P.Text(rxp, P.Call(rxp, "GetGuideName", guide) or guide.name) or guide.name
                }
            end
        end
        local id, reason = Common.Actions.ResolveGuide(query or "", catalog)
        if not id then return false, reason end
        return API.SwitchGuide(id)
    end,
    output = function(mode) return PrintChat(API.GetSnapshot(), mode) end,
    reset = function()
        NS.SetGuideTrackerViewerProviderSetting("rxp", "hideNative", false)
        NS.ApplyGuideTrackerViewerSettings("rxp")
        return true, "Native frames uncloaked. RXP does not expose a verified guide-window position reset."
    end,
}

NS.RegisterGuideTrackerViewerProvider("rxp", {
    displayName = "RestedXP Guides",
    controls = commandControls,
    moduleName = "AwpRXPTrackerModule",
    applySettings = ApplySettings,
    refresh = function() if Settings().enabled then controller:MarkDirty() end end,
    isAvailable = NS.IsRXPLoaded,
    isAttached = function() return controller:IsAttached() end
})

-- Only the explicit button changes RXP's arrow preference. Dismissing the
-- prompt remembers the choice per character, just like the other guides.
local PROMPT = "AWP_RXP_ARROW_RECOMMENDATION"
NS.MaybeShowRXPArrowRecommendationPopup = NS.Internal.StartupNotices.RegisterArrow(PROMPT, {
    deferCombat = true,
    check = function()
        local rxp = API.GetRuntime()
        if not rxp or not rxp.settings or not rxp.settings.profile or rxp.settings.profile.disableArrow then return false end
        local snapshot = API.GetSnapshot()
        if snapshot.state ~= "ready" or not snapshot.id then return false end
        local db = AzerothWaypointCharDB
        if not db or db.rxpArrowPromptShown or not NS.IsRoutingEnabled() then return false end
        if not (Settings().enabled or NS.GetActiveGuideProvider() == "rxp") then return false end
        return true
    end,
    dialog = {
        text = "AWP is navigating RestedXP guide targets. Turn off RestedXP's own arrow to avoid duplicate arrows?",
        button1 = "Turn Off RestedXP Arrow",
        button2 = "Keep Enabled",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function()
            local current = API.GetRuntime()
            if current and current.settings then
                current.settings.profile.disableArrow = true; if current.arrowFrame then current.arrowFrame:Hide() end
            end
            AzerothWaypointCharDB.rxpArrowPromptShown = true
        end,
        OnCancel = function() AzerothWaypointCharDB.rxpArrowPromptShown = true end,
    },
})

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ADDON_LOADED" }) do watcher:RegisterEvent(event) end
watcher:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "RXPGuides" then return end
    ApplySettings()
    if C_Timer and C_Timer.After then C_Timer.After(2, NS.MaybeShowRXPArrowRecommendationPopup) end
end)
