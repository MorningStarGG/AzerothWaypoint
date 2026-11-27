-- ============================================================
-- Shared source Viewer
-- ============================================================
--
-- Builds viewer controls and tracker rows for guide sources that use the
-- shared viewer implementation.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local R = NS.Internal.GuideSourceRuntime
local SourceViewer = {}
Common.SourceViewer = SourceViewer

function SourceViewer.Register(config)
    local key, api = config.key, config.api
    if Common.QuestDetails then Common.QuestDetails.RegisterSource(key, api.GetSnapshot) end
    local definition = NS.Constants.GUIDE_PROVIDER_BY_KEY[key]
    local Host, Controls, Render = Common.Host, Common.Controls, Common.Render
    local module, lastChat, hideReason
    if api.GetRowActionState and Common.Actions then
        Common.Actions.RegisterRowProvider(key, { available = api.GetRowActionState, run = api.RunRowAction })
    end
    local function Settings() return NS.GetGuideTrackerViewerProviderSettings(key) end
    local function Report(ok, reason)
        if not ok and reason and NS.Msg then NS.Msg(definition.label .. ":", reason) end
        return ok, reason
    end
    local function Invoke(action, guide, step, requested, epoch)
        local called, ok, reason, suggested = pcall(api.RunAction, action, guide, step, requested, epoch)
        if not called then return false, "Native guide action failed: " .. tostring(ok) end
        return ok, reason, suggested
    end
    local function Run(action, requested)
        local s = api.GetSnapshot()
        local ok, reason, suggested = Invoke(action, s.id, s.current, requested, s.epoch)
        if reason == "choose_step" then
            local name = "AWP_GUIDE_STEP_" .. key:upper()
            StaticPopupDialogs[name] = StaticPopupDialogs[name] or {
                text = "Reopen an earlier " .. definition.label .. " step (1-%d). Native quest progress is rechecked.",
                button1 = "Reopen Step",
                button2 = CANCEL,
                hasEditBox = true,
                maxLetters = 8,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                OnShow = function(dialog, data)
                    local edit = dialog:GetEditBox(); edit:SetText(tostring(data.suggested)); edit:HighlightText(); edit
                        :SetFocus()
                end,
                OnAccept = function(dialog, data)
                    local index = tonumber(dialog:GetEditBox():GetText())
                    Report(Invoke("goto", data.guide, data.current, index, data.epoch))
                end,
            }
            return NS.Internal.Dialogs.Show(name, math.max(1, s.current - 1), nil,
                { guide = s.id, current = s.current, epoch = s.epoch, suggested = suggested or s.current - 1 }) ~= nil
        elseif reason == "confirm_skip" then
            local request = api.pendingSkip
            local name = "AWP_GUIDE_SKIP_" .. key:upper()
            StaticPopupDialogs[name] = StaticPopupDialogs[name] or {
                text = "Skipping this step also skips these dependent steps:\n%s",
                button1 = "Skip Steps",
                button2 = CANCEL,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                OnAccept = function(_, data)
                    local called, accepted, message = pcall(api.ConfirmSkip, data)
                    if called then Report(accepted, message) else Report(false, "Native skip failed.") end
                end,
            }
            return NS.Internal.Dialogs.Show(name, suggested, nil, request) ~= nil
        end
        return Report(ok, reason)
    end

    -- ============================================================
    -- Guide choices and commands
    -- ============================================================

    local function GuideList()
        if api.GetGuideList then return api.GetGuideList() end
        local native = api.GetRuntime()
        local s, slots = api.GetSnapshot(), {}
        local history = Common.GetOpenGuides(key) or {}
        for i = #history, 1, -1 do
            local id = history[i]
            if native and native.Guides and native.Guides[id] then
                slots[#slots + 1] = {
                    id = id,
                    index = i,
                    label = R.Call(native, "GetGuideName", id) or id,
                    active = s.id == id,
                    owned = true
                }
            end
        end
        return { mode = "recent", source = key, capacity = Common.GUIDE_TAB_LIMIT, slots = slots }
    end
    local function Close(entry)
        local s, list = api.GetSnapshot(), Common.GetOpenGuides(key) or {}
        if s.id == entry.id and not Run("close") then return false end
        for index = #list, 1, -1 do if list[index] == entry.id then table.remove(list, index) end end
        Common.SetOpenGuides(key, list); return true
    end
    local function Menu(anchor, guidesOnly, taskAction)
        if not MenuUtil or not MenuUtil.CreateContextMenu then return end
        NS.Internal.Menus.CreateContextMenu(anchor or UIParent, function(_, root)
            root:CreateTitle(definition.title)
            if not guidesOnly and Common.QuestDetails then Common.QuestDetails.AddMenu(root, anchor) end
            if taskAction then Common.Actions.AddRowMenuEntry(root, taskAction) end
            if not guidesOnly then
                if config.dynamicTasks then
                    api.AddTaskMenu(root)
                else
                    for _, item in ipairs({ { "Make Active",                     "active" }, { "Route This Step", "route" },
                        { config.skipHeader and "Skip Step" or "Mark Step Complete", "complete" },
                        { "Skip Step",                                               "skip" }, { "Recheck Progress", "reload" } }) do
                        local action = item[2]
                        root:CreateButton(item[1], function() Run(action) end):SetEnabled(not InCombatLockdown())
                    end
                end
                root:CreateDivider()
            end
            if config.guideSteps then
                local s = api.GetSnapshot()
                root:CreateButton("Current Guide Steps", function() Run("steps") end)
                    :SetEnabled(s.id ~= nil and s.state ~= "loading" and not InCombatLockdown())
            end
            if config.history then
                Common.Tabs.AddMenu(key, root, anchor)
            else
                root:CreateButton("Open Route Browser", function() Run("chooser") end)
            end
            root:CreateButton("Open " .. definition.label .. " Settings", function() Run("settings") end)
            if hideReason then root:CreateTitle(hideReason) end
        end)
    end
    local function Layout(self)
        local s = api.GetSnapshot()
        if config.resetLayout then config.resetLayout(self, s) end
        Controls.SetModuleHeader(self, key, definition.title)
        Controls.Update(self, s.state == "ready" and (s.displayCurrent or s.current) or nil,
            s.displayTotal or s.total or 0,
            s.fraction and s.fraction * 100 or nil, s)
        if s.state ~= "ready" then
            local block = self:GetBlock("Awp" .. definition.suffix .. "Status")
            if not block then
                self.hasContents = false; return
            end
            local state = s.state == "loading" and "loading guide..." or s.state == "paused" and "paused" or
            "no guide selected"
            Controls.SetBlockHeaderText(block, definition.label .. " (" .. state .. ")")
            Controls.SetStepCheckbox(block, block.HeaderText, nil)
            local line = Render.AddObjective(block, 1,
                {
                    text = s.message or (s.state == "paused" and "Open native settings to resume."
                        or "Click here to select a guide."),
                    action = "info",
                    kind = "goal",
                    fullHeight = true
                })
            if line then
                line:EnableMouse(true)
                line:SetScript("OnMouseUp", function() Run(s.state == "paused" and "settings" or "chooser") end)
            end
            Render.EnsureBlockHeight(block, 42); self:LayoutBlock(block); self.hasContents = true; return
        end
        local decorated = config.beforeLayout and config.beforeLayout(self, s)
        if config.dynamicTasks and s.steps[1] and s.steps[1].taskKey then
            local hideTitle = decorated or Settings().hideGuideTitle
            Controls.SetGuideTitleTooltip(self, s.title, hideTitle)
            if not hideTitle then
                local heading = self:GetBlock("Awp" .. definition.suffix .. "GuideTitle")
                if heading then
                    heading.parentModule = self
                    Controls.SetBlockHeaderText(heading, s.title, true)
                    Controls.SetStepCheckbox(heading, heading.HeaderText, nil)
                    self:LayoutBlock(heading)
                end
            end
        end
        for ordinal, section in ipairs(s.steps or {}) do
            local isTask = config.dynamicTasks and section.taskKey ~= nil
            local block = self:GetBlock("Awp" .. definition.suffix .. "Step" .. ordinal)
            if block then
                block.parentModule = self
                block._awpOwnerStepIndex = section.ownerStepIndex
                local heading = s.title
                if isTask then
                    heading = section.preview and ("Preview: " .. section.title) or section.title
                elseif section.sticky then
                    heading = "Along the way: " .. (section.title or s.title)
                end
                Controls.SetBlockHeaderText(block, heading, not isTask and not section.sticky, decorated)
                local guide, index, epoch = s.id, s.current, s.epoch
                local taskAction = isTask and {
                    provider = key,
                    action = "pin",
                    guide = guide,
                    current = index,
                    task = section.taskKey,
                    epoch = epoch,
                    label = "Make This Task Active"
                } or nil
                block._awpTaskAction = taskAction
                Controls.SetStepCheckbox(block, block.HeaderText,
                    not config.dynamicTasks and not section.sticky and section.ownerStepIndex == s.current and {
                        checked = false,
                        tooltip = config.skipHeader and "Skip Step" or "Mark Step Complete",
                        detail = config.skipHeader and "Uses APR's native skip and undo behavior." or
                        "Uses WoWPro's native completion behavior.",
                        onClick = function() Report(Invoke("complete", guide, index, nil, epoch)) end,
                    } or nil)
                for i, row in ipairs(section.rows) do
                    local line = Render.AddObjective(block, i, row)
                    if line then
                        Render.WireTipTooltip(line, row.tooltipTitle, row.tips)
                        local owner = row.ownerStepIndex
                        line:EnableMouse(true)
                        if taskAction and Common.Actions then
                            Common.Actions.BindRowAction(line, taskAction,
                                not section.preview and function(anchor) Menu(anchor, false) end or nil,
                                function(anchor, descriptor) Menu(anchor, true, descriptor) end)
                        elseif not section.preview then
                            line:SetScript("OnMouseUp", function(_, button)
                                if button == "RightButton" then
                                    Menu(line, false)
                                elseif not config.dynamicTasks and config.history and row.kind == "goal" and owner then
                                    Report(Invoke("waypoint", guide, index, owner, epoch))
                                end
                            end)
                        end
                        if Common.QuestDetails then Common.QuestDetails.WireRow(line,
                                function(anchor) Menu(anchor, false) end) end
                    end
                end
                Render.EnsureBlockHeight(block, #section.rows > 0 and 28 or 22)
                if self:LayoutBlock(block) == false and isTask then break end
            elseif isTask then
                break
            end
        end
        self.hasContents = true
    end

    -- ============================================================
    -- Tracker module lifecycle
    -- ============================================================

    local function CreateModule()
        module = Common.ModuleFactory.Create({
            host = Host,
            providerKey = key,
            name = definition.module,
            headerText = definition.title,
            uiOrder = definition.order
        })
        if not module then return end
        local actions = config.headerActions
        local left, right = actions and actions.left, actions and actions.right
        local function Click(action, fallback, anchor)
            if not action then return Run(fallback) end
            if InCombatLockdown() then return Report(false, "This action cannot be completed during combat.") end
            local s = api.GetSnapshot()
            if action.enabled and not action.enabled(s) then return end
            if action.menu then
                if not MenuUtil or not MenuUtil.CreateContextMenu then return end
                return NS.Internal.Menus.CreateContextMenu(anchor, function(_, root) action.menu(root, s) end)
            end
            return Run(action.action)
        end
        Controls.Create(module, {
            settingsTooltip = definition.label .. " native menu",
            menuTooltip = "Guide actions",
            hideNavigation = config.dynamicTasks and not actions,
            progressUnit = config.dynamicTasks and "quests" or nil,
            previousTooltip = left and left.tooltip or "Previous step",
            nextTooltip = right and right.tooltip or (config.skipHeader and "Skip Step" or "Complete Step"),
            previousAtlas = left and left.atlas,
            nextAtlas = right and right.atlas,
            previousEnabled = left and left.enabled,
            nextEnabled = right and right.enabled,
            onPrevious = function(anchor) return Click(left, "previous", anchor) end,
            onNext = function(anchor) return Click(right, "next", anchor) end,
            onSettings = function() Run("menu") end,
            onMenu = function(anchor) Menu(anchor, false) end
        })
        function module:LayoutContents() Layout(self) end

        function module:OnBlockHeaderClick(block, button)
            if button == "LeftButton" and block._awpTaskAction then
                Menu(block, true, block._awpTaskAction)
            elseif button == "LeftButton" and not config.history then
                Run("chooser")
            else
                Menu(block, button == "LeftButton")
            end
        end

        Common.HeaderStyle.CaptureBaseline(module); Common.HeaderStyle.Refresh(module)
        return module
    end
    local controller = Common.CreateViewerController({
        providerKey = key,
        host = Host,
        createModule = CreateModule,
        isEnabled = function() return Settings().enabled and config.isLoaded() end
    })
    local cloak = Common.CreateNativeFrameCloak({
        resolve = function()
            local wanted = Settings().hideNative and config.isLoaded()
            hideReason = nil
            local actions = Common.GuideActions
            if wanted then
                local covered, reason
                if actions then covered, reason = actions.CanHideNative(key) end
                if not covered then wanted, hideReason = false, reason or "Native action coverage is not ready." end
            end
            return config.frames(), wanted
        end
    })
    if Common.GuideActions and Common.GuideActions.RegisterViewerCloak then
        Common.GuideActions.RegisterViewerCloak(key, function() cloak:Schedule() end)
    end

    -- ============================================================
    -- Applying settings and subscriptions
    -- ============================================================

    local function Apply()
        if Settings().enabled and config.isLoaded() then
            controller:Attach()
        else
            if module and config.resetLayout then config.resetLayout(module) end
            controller:Detach()
        end
        cloak:Refresh()
        if module then Common.HeaderStyle.Refresh(module) end
    end
    local controls = {}
    controls.hasGuide = function()
        local s = api.GetSnapshot()
        return s.id ~= nil and s.state == "ready"
    end
    for _, name in ipairs({ "skip", "reload", "active", "route", "settings", "menu" }) do
        local action = name; controls[action] = function() return Run(action) end
    end
    controls.picker = function() return Run("chooser") end
    if not config.dynamicTasks then
        controls.prev = function() return Run("previous") end
        controls.next = function() return Run("next") end
        controls.complete = function() return Run("complete") end
    end
    if config.guideSteps then controls.steps = function() return Run("steps") end end
    controls.output = function(mode) return Common.Actions.OutputSnapshot(key, api.GetSnapshot(), mode, true) end
    if config.history then
        controls.tabState, controls.newGuide = GuideList, function() return Run("chooser") end
        controls.switch = function(entry)
            if api.SwitchGuide then return api.SwitchGuide(entry) end
            local native = api.GetRuntime()
            if not native or not native.Guides[entry.id] then return false, "guide_unavailable" end
            native:LoadGuide(entry.id); api.Activate("AWPGuideSwitch"); return true, "Guide loading requested."
        end
        controls.close = Close
        controls.closeAll = function()
            if api.GetSnapshot().id and not Run("close") then return false end
            Common.SetOpenGuides(key, {}); return true
        end
        controls.load = function(query)
            local native, catalog = api.GetRuntime(), {}
            for id, guide in pairs(native and (native.Guides or native.zoneGuideByKey) or {}) do
                catalog[#catalog + 1] = { id = id, label = type(guide) == "table" and (guide.name or guide.zone) or
                R.Call(native, "GetGuideName", id) or id }
            end
            local id, reason = Common.Actions.ResolveGuide(query or "", catalog)
            if not id then return false, reason end
            return controls.switch({ id = id })
        end
    end
    if config.dynamicTasks then
        controls.tasks, controls.automatic = function() return Run("tasks") end, function() return Run("automatic") end
        controls.commandLabels = { skip = "skip (native task menu)" }
        controls.menuLabels = { skip = "Native Task Actions" }
    end
    if config.headerActions then
        controls.getActionState = function(action)
            local enabled, reason = Common.Actions.GetDefaultActionState(key, action)
            if not enabled then return false, reason end
            for _, item in pairs(config.headerActions) do
                if action == (item.action or item.command) and item.enabled and not item.enabled(api.GetSnapshot()) then
                    return false, item.tooltip .. " is unavailable."
                end
            end
            return true
        end
    end
    NS.RegisterGuideTrackerViewerProvider(key,
        {
            displayName = definition.title,
            moduleName = definition.module,
            controls = controls,
            isAvailable = config.isLoaded,
            applySettings = Apply,
            refresh = function() controller:MarkDirty() end,
            isAttached = function() return controller:IsAttached() end
        })
    local lastGuide
    api.Subscribe(function(s, changed)
        if config.history and s.state == "ready" and s.id ~= lastGuide then
            lastGuide = s.id; Common.RememberOpenGuide(key, s.id)
        elseif not s.id then
            lastGuide = nil
        end
        if changed then
            Apply(); controller:MarkDirty()
            local chatKey = s.id and s.id .. ":" .. (s.taskKey or s.current)
            if Settings().chatOutputOnChange and s.id and lastChat ~= chatKey then
                lastChat = chatKey; controls.output()
            end
        end
    end)
    local watcher = CreateFrame("Frame")
    if config.headerActions then watcher:RegisterEvent("PLAYER_REGEN_DISABLED") end
    for _, event in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_REGEN_ENABLED" }) do watcher:RegisterEvent(event) end
    watcher:SetScript("OnEvent", function(_, event, addon)
        if event == "ADDON_LOADED" and addon ~= config.addon and addon ~= "AzerothWaypoint" then return end
        if config.headerActions and module then Controls.UpdateHeaderActions(module, api.GetSnapshot()) end
        if event == "PLAYER_REGEN_DISABLED" then return end
        Apply(); if config.isLoaded() then api.Schedule(event) end
    end)
    return {
        Apply = Apply,
        GetStatus = function()
            return {
                enabled = Settings().enabled,
                attached = controller:IsAttached(),
                moduleCreated = module ~= nil,
                host = Host.GetHostID(),
                state = api.GetSnapshot().state,
                nativeHidden = cloak:IsApplied(),
                hideReason = hideReason
            }
        end
    }
end
