-- ============================================================
-- Polestar Viewer
-- ============================================================
--
-- Renders Polestar's guide goals and nearby opportunities and connects their
-- rows to native guide actions.

local NS = _G.AzerothWaypointNS
if not NS.IsWoWForever() then return end
local Common = NS.Internal.GuideTrackerViewer
local API, P = NS.Internal.PolestarProvider, NS.Internal.PolestarPresentation
if Common.QuestDetails then Common.QuestDetails.RegisterSource("polestar", API.GetSnapshot) end
if Common.Actions and API.GetRowActionState then
    Common.Actions.RegisterRowProvider("polestar", { available = API.GetRowActionState, run = API.RunRowAction })
end
local Host, Controls, Render = Common.Host, Common.Controls, Common.Render
local module, lastChatGuide, lastChatStep

local function Settings() return NS.GetGuideTrackerViewerSettings("polestar") end
local function Run(action, goal)
    local s = API.GetSnapshot()
    return API.Action(action, s.id, s.rawCurrent, goal)
end

local function OpenNativeMenu(anchor)
    local r = API.GetRuntime()
    local guide = r and r.UI and r.UI.GuideFrame
    local button = guide and guide.menuButton
    if button and type(button.GetScript) == "function" then
        local ok, onClick = pcall(button.GetScript, button, "OnClick")
        if ok and type(onClick) == "function" then
            -- A manually closed native window stops refreshing its step view.
            -- Refresh it on demand so the native menu's quest-pin entries are
            -- current, without showing the window or changing its preferences.
            local frame = guide.frame
            if frame and type(frame.IsShown) == "function" then
                local readable, shown = pcall(frame.IsShown, frame)
                if readable and not shown then
                    if type(guide.Render) ~= "function" or not pcall(guide.Render) then return Run("settings") end
                end
            end
            if pcall(onClick, anchor or module or UIParent, "LeftButton") then return true end
        end
    end
    return Run("settings")
end

local function CloseGuide(id)
    local r = API.GetRuntime()
    if not r or InCombatLockdown() then return false, "unavailable" end
    for i, tab in ipairs(P.Call(r.Engine, "GetTabs") or {}) do
        if tab.guideId == id then
            local ok, result = pcall(r.Engine.CloseTab, i)
            if ok and result ~= false then
                API.Schedule("close"); return true
            end
            return false, "native_close_failed"
        end
    end
    return false, "stale_guide"
end
local function PrintChat(s, mode)
    if not s.id then return false, "no_guide" end
    local model = Common.Chat.FromSnapshot(s)
    model.label, model.summaryLabel, model.summaryUnit = "Polestar", "Along the way", "goals"
    for i, step in ipairs(model.stickies) do
        model.stickies[i] = { title = step.title, rows = step.rows, count = #(step.goals or {}) }
    end
    return Common.Chat.Output("polestar", model, mode)
end

-- ============================================================
-- Guide choices and menus
-- ============================================================

local function Guides(root)
    local s = API.GetSnapshot()
    if #s.tabs == 0 then root:CreateTitle("No open guides") end
    for _, tab in ipairs(s.tabs) do
        root:CreateRadio(tab.title, function() return API.GetSnapshot().id == tab.id end,
            function() API.SelectTab(tab.id) end)
    end
    root:CreateButton("Open New Guide...", function() Run("chooser") end)
    if #s.tabs > 0 then
        local close = root:CreateButton("Close Open Guide")
        for _, tab in ipairs(s.tabs) do
            close:CreateButton(tab.title, function() CloseGuide(tab.id) end)
        end
    end
end

local function Nearest(root)
    local r = API.GetRuntime()
    local nearby = r and r.Nav and r.Nav.nearby
    local function add(parent, entry)
        parent:CreateButton(entry.label, function()
            if InCombatLockdown() then return end
            API.FindNearest(entry.key, entry.line, entry.label)
        end)
    end
    for _, entry in ipairs(P.Call(nearby, "MenuItems") or {}) do
        if entry.separator then
            root:CreateDivider()
        elseif entry.page or entry.weapons then
            local page = root:CreateButton(entry.label)
            for _, item in ipairs(entry.page or entry.weapons) do
                add(page, { label = item.label, key = item.key or entry.key, line = item.line })
            end
        else
            add(root, entry)
        end
    end
end

local function Menu(anchor, titleOnly)
    if not MenuUtil or not MenuUtil.CreateContextMenu then return Run("chooser") end
    NS.Internal.Menus.CreateContextMenu(anchor or module or UIParent, function(_, root)
        root:CreateTitle("Polestar")
        if not titleOnly and Common.QuestDetails then Common.QuestDetails.AddMenu(root, anchor) end
        root:CreateButton("Make Polestar Active", function() Run("active") end)
        if not titleOnly then
            root:CreateButton("Route Selected Goal", function()
                local r = API.GetRuntime()
                local wp = r and P.Call(r.Engine, "GetWaypoint")
                if wp then API.Action("route", API.GetSnapshot().id, wp.stepIndex, wp.goalIndex) end
            end)
            root:CreateButton("Skip Step", function() Run("skip") end)
            root:CreateButton("Recheck Guide", function() Run("recheck") end)
            root:CreateButton("Open Polestar Settings", function() Run("settings") end)
            local nearest = root:CreateButton("Find Nearest", function() return MenuResponse.Open end)
            Nearest(nearest)
            root:CreateDivider()
        end
        Guides(root)
    end)
end

-- ============================================================
-- Tracker rows and layout
-- ============================================================

local function WireLine(line, row, snapshot)
    local tips = row.hoverTips or row.tips
    Render.WireTipTooltip(line, row.tooltipTitle, tips)
    if row.interaction and Common.Actions then
        local more = row.interaction.action == "level_return" and function(anchor) Menu(anchor) end or nil
        Common.Actions.BindRowAction(line, row.interaction, more)
        return
    end
    line:SetScript("OnMouseUp", nil)
    line:EnableMouse(row.hereSerial ~= nil or row.goalIndex ~= nil and row.stepIndex ~= nil
        or type(tips) == "table" and #tips > 0)
    if not row.hereSerial and (not row.goalIndex or not row.stepIndex) then
        if Common.QuestDetails then Common.QuestDetails.WireRow(line) end
        return
    end
    local guide, step, goal, epoch = snapshot.id, row.stepIndex, row.goalIndex, snapshot.epoch
    local function route()
        if row.hereSerial then return API.Action("here", guide, snapshot.rawCurrent, row.hereSerial, epoch) end
        return API.Action("route", guide, step, goal, epoch)
    end
    line:SetScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" then
            route(); return
        end
        if not MenuUtil then return end
        NS.Internal.Menus.CreateContextMenu(line, function(_, root)
            if Common.QuestDetails then Common.QuestDetails.AddMenu(root, line) end
            root:CreateButton("Route This Goal", route)
            if row.tickable then
                root:CreateButton(row.ticked and "Undo Manual Checkoff" or "Mark Goal Complete",
                    function() API.Action("toggle", guide, step, goal, epoch) end)
            end
        end)
    end)
end

NS.OpenPolestarViewerMenu = Menu

local function Layout(self)
    local s = API.GetSnapshot()
    Controls.SetModuleHeader(self, "polestar", "Polestar")
    Controls.Update(self, s.current, s.total, s.count and s.count > 0 and (s.done or 0) * 100 / s.count or nil)
    if s.state ~= "ready" then
        local block = self:GetBlock("AwpPolestarStatus")
        if not block then
            self.hasContents = false; return
        end
        Controls.SetBlockHeaderText(block, s.state == "loading" and "Polestar (loading guide...)"
            or s.state == "complete" and "Polestar (guide complete)" or "Polestar (no guide selected)")
        Controls.SetStepCheckbox(block, block.HeaderText, nil)
        local line = Render.AddObjective(block, 1,
            { text = "Click here to select a guide.", kind = "goal", action = "note", fullHeight = true })
        if line then
            Render.WireTipTooltip(line, nil, nil)
            line:EnableMouse(true)
            line:SetScript("OnMouseUp", function() Run("chooser") end)
        end
        block.height = math.max(block.height or 0, 42)
        self:LayoutBlock(block); self.hasContents = true; return
    end
    for ordinal, step in ipairs(s.steps) do
        local block = self:GetBlock("AwpPolestarStep" .. ordinal)
        if block then
            block.parentModule = self
            block._awpOwnerStepIndex = step.index
            Controls.SetBlockHeaderText(block, step.section == "nearby" and "While you're here"
                or step.sticky and ("Along the way: " .. (step.title or s.title or "Goals")) or s.title,
                step.section ~= "nearby" and not step.sticky)
            local binding
            if not step.sticky then
                local guide, index, epoch = s.id, s.rawCurrent, s.epoch
                binding = {
                    checked = false,
                    tooltip = "Skip Step",
                    detail = "Skips this entire Polestar step. Back and Next only preview steps.",
                    onClick = function() API.Action("skip", guide, index, nil, epoch) end
                }
            end
            Controls.SetStepCheckbox(block, block.HeaderText, binding)
            for i, row in ipairs(step.rows) do
                local line = Render.AddObjective(block, i, row)
                if line then WireLine(line, row, s) end
            end
            Render.EnsureBlockHeight(block, #step.rows > 0 and 28 or 22)
            self:LayoutBlock(block)
        end
    end
    self.hasContents = true
end

-- ============================================================
-- Tracker module lifecycle
-- ============================================================

local function CreateModule()
    if module then return module end
    module = Common.ModuleFactory.Create({
        host = Host,
        providerKey = "polestar",
        name = "AwpPolestarTrackerModule",
        headerText = "Polestar",
        uiOrder = 2.3
    })
    if not module then return end
    Controls.Create(module, {
        settingsTooltip = "Polestar menu",
        menuTooltip = "Polestar guides and actions",
        previousTooltip = "Preview previous step",
        nextTooltip = "Preview next step",
        onSettings = OpenNativeMenu,
        onMenu = function(anchor) Menu(anchor) end,
        onPrevious = function() Run("previous") end,
        onNext = function() Run("next") end
    })
    function module:LayoutContents() Layout(self) end

    function module:OnBlockHeaderClick(block, button) Menu(block, button == "LeftButton") end

    if Common.HeaderStyle then
        Common.HeaderStyle.CaptureBaseline(module); Common.HeaderStyle.Refresh(module)
    end
    return module
end
local controller = Common.CreateViewerController({
    providerKey = "polestar",
    host = Host,
    createModule = CreateModule,
    isEnabled = function() return Settings().enabled and NS.IsPolestarLoaded() end
})

local cloak = Common.CreateNativeFrameCloak({
    resolve = function()
        local frame = rawget(_G, "PolestarGuideFrame")
        return frame and { frame } or {}, Settings().hideNative and API.GetRuntime() ~= nil
    end
})
local function Apply()
    local s = Settings()
    if s.enabled and API.GetRuntime() then controller:Attach() else controller:Detach() end
    local frame = rawget(_G, "PolestarGuideFrame")
    cloak:Apply(frame and { frame } or {}, s.hideNative and API.GetRuntime() ~= nil)
    if module and Common.HeaderStyle then Common.HeaderStyle.Refresh(module) end
end

local PROMPT = "AWP_POLESTAR_ARROW"
local Recommend = NS.Internal.StartupNotices.RegisterArrow(PROMPT, {
    deferCombat = true,
    check = function()
        local r = API.GetRuntime()
        local db = rawget(_G, "AzerothWaypointCharDB")
        if not r or not db or db.polestarArrowPromptShown or P.Call(r, "Get", "nav.arrowToFollower") or not NS.IsRoutingEnabled()
            or not API.GetSnapshot().id or not (Settings().enabled or NS.GetActiveGuideProvider() == "polestar")
            or not (P.Call(r, "Get", "nav.arrow") or P.Call(r, "Get", "nav.useTomTomArrow")) then
            return false
        end
        return true
    end,
    dialog = {
        text =
        "Let AWP show navigation while AWP routing is enabled? Polestar's arrow stays hidden even when another guide is active, and follows its own preferences again when AWP routing is turned off.",
        button1 = "Let AWP Show Navigation",
        button2 = "Keep Current Setting",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function()
            local current = API.GetRuntime()
            if current then pcall(current.Set, "nav.arrowToFollower", true) end
            AzerothWaypointCharDB.polestarArrowPromptShown = true
        end,
        OnCancel = function() AzerothWaypointCharDB.polestarArrowPromptShown = true end,
    },
})

NS.MaybeShowPolestarArrowRecommendationPopup = Recommend

API.Subscribe(function(s, changed)
    if changed then
        Apply()
        controller:MarkDirty()
        local settings = NS.GetGuideTrackerViewerProviderSettings("polestar")
        if settings.chatOutputOnChange and s.id and (lastChatGuide ~= s.id or lastChatStep ~= s.rawCurrent) then
            lastChatGuide, lastChatStep = s.id, s.rawCurrent
            PrintChat(s)
        end
        Recommend()
    end
end)
NS.GetPolestarTrackerViewerStatus = function()
    return {
        enabled = Settings().enabled,
        attached = controller:IsAttached(),
        moduleCreated = module ~= nil,
        host = Host.GetHostID(),
        state = API.GetSnapshot().state,
        nativeHidden = cloak:IsApplied()
    }
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
    route = function()
        local r = API.GetRuntime()
        local waypoint = r and P.Call(r.Engine, "GetWaypoint")
        return waypoint and API.Action("route", API.GetSnapshot().id, waypoint.stepIndex, waypoint.goalIndex) or false
    end,
    reload = function() return Run("recheck") end,
    picker = function() return Run("chooser") end,
    settings = function() return Run("settings") end,
    menu = function() return OpenNativeMenu(UIParent) end,
    guides = function()
        local s, out = API.GetSnapshot(), {}
        for _, tab in ipairs(s.tabs) do out[#out + 1] = { id = tab.id, label = tab.title, active = s.id == tab.id } end
        return out
    end,
    switch = function(entry) return API.SelectTab(entry.id) end,
    close = function(entry) return CloseGuide(entry.id) end,
    load = function(query)
        local r, catalog = API.GetRuntime(), {}
        if not r.Guides or type(r.Engine.OpenTab) ~= "function" then return false, "loader_unavailable" end
        for _, guide in ipairs(P.Call(r.Guides, "List") or {}) do
            catalog[#catalog + 1] = { id = guide.id, label = P.Text(guide.title or guide.name) or guide.id }
        end
        local id, reason = Common.Actions.ResolveGuide(query or "", catalog)
        if not id then return false, reason end
        local ok, result = pcall(r.Engine.OpenTab, id, true)
        if ok and type(result) == "number" then
            API.Activate(); return true
        end
        return false
    end,
    output = function(mode) return PrintChat(API.GetSnapshot(), mode) end,
    reset = function()
        NS.SetGuideTrackerViewerProviderSetting("polestar", "hideNative", false)
        NS.ApplyGuideTrackerViewerSettings("polestar")
        local r = API.GetRuntime()
        if type(r.Set) ~= "function" then return false, "window_reset_unavailable" end
        local ok, result = pcall(r.Set, "ui.pos", nil); return ok and result ~= false
    end,
}
NS.RegisterGuideTrackerViewerProvider("polestar",
    {
        displayName = "Polestar",
        controls = commandControls,
        moduleName = "AwpPolestarTrackerModule",
        applySettings = Apply,
        refresh = function() controller:MarkDirty() end,
        isAvailable = NS.IsPolestarLoaded,
        isAttached = function() return controller:IsAttached() end
    })
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_REGEN_ENABLED" }) do watcher:RegisterEvent(event) end
watcher:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "Polestar" then return end
    Apply(); Recommend()
end)
