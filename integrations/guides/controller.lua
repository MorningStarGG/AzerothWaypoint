-- ============================================================
-- Controller guide actions
-- ============================================================
--
-- Prepares guide actions for controller use and binds menu and action commands
-- to the focused guide row.

local NS = _G.AzerothWaypointNS
local Pad = NS.Internal.Controller
local Common = NS.Internal.GuideTrackerViewer
local Actions = Common.GuideActions
local ACTION_BINDING = "CLICK AWPControllerGuideAction:LeftButton"
local executors, prepared, requested = {}, {}, {}
local picker
local empty, selections = {}, {}

local function Allowed(key, action)
    return not action.unsupported and NS.GetGuideActionSettings(key).types[action.category] ~= false
end
local function Secure(action) return action.kind ~= "native" or Actions.IsSecureNative(action) end
local function Key() return GetBindingKey(ACTION_BINDING) end

function Pad.NeedsGuideActions(key)
    if not Pad.Available() then return false end
    local db = NS.GetDB and NS.GetDB()
    if db and db.controllerEnabled == false then return false end
    if Key() and NS.GetActiveGuideProvider() == key then return true end
    if not Pad.Enabled() then return false end
    for frame, window in pairs(Pad.windows) do if window.guide == key and frame:IsVisible() then return true end end
    return false
end

function Pad.GuideActionList(key, record)
    local model = Actions.models[key]
    if not model or Actions.providers[key] and Actions.providers[key].lastError then return empty end
    local settings, mask = NS.GetGuideActionSettings(key), 0
    for index, category in ipairs(NS.Constants.GUIDE_ACTION_TYPES) do
        if settings.types[category.key] ~= false then mask = mask + 2 ^ index end
    end
    local owner, stepOwner, action, owners
    if record then owner, stepOwner, action, owners = record.owner, record.stepOwner, record.action, record.owners end
    local cache = record and record.selection or selections[key]
    if not cache or cache.model ~= model or cache.mask ~= mask or cache.owner ~= owner or cache.stepOwner ~= stepOwner
        or cache.action ~= action or cache.owners ~= owners then
        cache = { model = model, mask = mask, owner = owner, stepOwner = stepOwner, action = action, owners = owners, candidates = {}, result = {} }
        if record then record.selection = cache else selections[key] = cache end
        for _, candidate in ipairs(model.actions) do
            local owned = not record or action == candidate
                or owner ~= nil and candidate.owner == owner or stepOwner ~= nil and candidate.owner == stepOwner
                or owners and owners[candidate.owner] == true
            if owned and Allowed(key, candidate) then cache.candidates[#cache.candidates + 1] = candidate end
        end
    end
    -- Native buttons can change before their next model publication. Validate
    -- cached candidates each time, never cache an initial visibility failure.
    local count = 0
    for _, candidate in ipairs(cache.candidates) do
        if Actions.IsCurrent(key, candidate) then
            count = count + 1; cache.result[count] = candidate
        end
    end
    for index = count + 1, #cache.result do cache.result[index] = nil end
    return cache.result
end

-- ============================================================
-- Preparing secure actions
-- ============================================================

local function EnsureExecutors()
    if executors.global or not Pad.Available() or InCombatLockdown() then return end
    for _, role in ipairs({ "global", "context" }) do
        local name = role == "global" and "AWPControllerGuideAction" or "AWPControllerContextAction"
        local button = Actions.CreateButton(UIParent, true, false, name)
        button._awpControllerExecutor = true
        button:EnableMouse(false)
        button:ClearAllPoints(); button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -1000, -1000)
        local kind = role
        button:HookScript("PostClick", function(self, _, down)
            if down or self._awpAction or InCombatLockdown() then return end
            local key, record
            if kind == "global" then
                key = NS.GetActiveGuideProvider()
            else
                record = Pad.controls[Pad.focus]; key = record and record.guide
            end
            if not key then
                NS.Msg("No guide action is available."); return
            end
            local actions = Pad.GuideActionList(key, record)
            if #actions == 1 and not Secure(actions[1]) then
                local ok, reason = Actions.InvokeNative(key, actions[1], "LeftButton", false)
                if not ok and reason then NS.Msg(reason) end
            elseif #actions > 0 then
                Pad.ShowActionPicker(key, actions)
            else
                NS.Msg("No guide action is available for this step.")
            end
        end)
        executors[role] = button
        Actions.Bind(button, nil, nil, true); button:Show()
    end
end

local function Prepare(role, key, actions)
    EnsureExecutors()
    local button = executors[role]
    if not button then return end
    local action = #actions == 1 and Secure(actions[1]) and actions[1] or nil
    if prepared[role] and prepared[role].key == key and prepared[role].action == action then return end
    Actions.Bind(button, key, action, true)
    button:Show()
    prepared[role] = { key = key, action = action }
end

function Pad.ShowActionPicker(key, actions)
    if not Pad.Enabled() or InCombatLockdown() then return end
    local FW = NS.Internal.Interface.Framework
    if not picker then
        picker = CreateFrame("Frame", "AWPControllerActionPicker", UIParent)
        picker:Hide(); picker:SetPoint("CENTER"); picker:SetSize(390, 400); picker:SetFrameStrata("DIALOG")
        local shell = FW.CreatePanelShell(picker,
            { title = "Guide Actions", footerHeight = 1, surface = "windows.options" })
        picker.scroll = CreateFrame("ScrollFrame", nil, shell.bodyFrame, "UIPanelScrollFrameTemplate")
        picker.scroll:SetPoint("TOPLEFT", 12, -8); picker.scroll:SetPoint("BOTTOMRIGHT", -20, 8)
        picker.content = CreateFrame("Frame", nil, picker.scroll)
        picker.content:SetWidth(340); picker.scroll:SetScrollChild(picker.content)
        picker.standard, picker.helpers = {}, {}
        FW.StyleScrollBar(picker.scroll)
    end
    local counts = { standard = 0, helpers = 0 }
    for index, action in ipairs(actions) do
        local helper = not Secure(action)
        local kind = helper and "helpers" or "standard"
        counts[kind] = counts[kind] + 1
        local button = picker[kind][counts[kind]]
        if not button then
            button = Actions.CreateButton(picker.content, not helper, helper)
            button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            button.label:SetPoint("LEFT", button, "RIGHT", 10, 0); button.label:SetWidth(285); button.label:SetJustifyH(
                "LEFT")
            button:HookScript("PostClick",
                function(_, _, down) if not down and not InCombatLockdown() then Pad.Back(picker) end end)
            picker[kind][counts[kind]] = button
        end
        button:ClearAllPoints(); button:SetPoint("TOPLEFT", 0, -(index - 1) * 40)
        button.label:SetText(action.label)
        Actions.Bind(button, key, action, not helper)
        Actions.StyleButton(button, key, action.framedIcon)
        Pad.RegisterControl(button,
            {
                id = "pick:" ..
                    key .. ":" .. tostring(action.owner) .. ":" .. action.kind .. ":" .. tostring(action.payload),
                guide = key,
                action = action,
                label = action.label
            })
    end
    for _, kind in ipairs({ "standard", "helpers" }) do
        for index = counts[kind] + 1, #picker[kind] do Actions.Bind(picker[kind][index], key, nil, kind == "standard") end
    end
    picker.content:SetHeight(math.max(1, #actions * 40))
    picker:SetHeight(math.min(460, 70 + #actions * 40))
    picker.scroll:SetVerticalScroll(0); picker:Show(); Pad.Enter(picker)
end

-- ============================================================
-- Hints and action refresh
-- ============================================================

local function UpdateStatus()
    local state, key = prepared.global, Key()
    if not key or not Pad.Enabled() or not state or not state.action then
        if Pad.actionStatus then Pad.actionStatus:Hide() end
        return
    end
    local status = Pad.actionStatus
    if not status then
        status = CreateFrame("Frame", nil, UIParent)
        status:SetSize(300, 38); status:EnableMouse(false); status:SetFrameStrata("MEDIUM")
        status.icon = status:CreateTexture(nil, "ARTWORK"); status.icon:SetPoint("LEFT"); status.icon:SetSize(28, 28)
        status.text = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status.text:SetPoint("LEFT", status.icon, "RIGHT", 6, 0); status.text:SetWidth(260); status.text:SetJustifyH(
            "LEFT")
        Pad.actionStatus = status
    end
    local panel = Actions.panels[state.key]
    local position = NS.GetGuideActionSettings(state.key).position
    local suffix = Pad.actionPending and "\nNew action will be prepared after combat." or
        InCombatLockdown() and "\nPrepared before combat." or ""
    local panelVisible = panel and panel:IsVisible()
    if status.action == state.action and status.key == key and status.suffix == suffix and status.panel == panel
        and status.panelVisible == panelVisible and status.position == position then
        status:Show(); return
    end
    status.action, status.key, status.suffix, status.panel, status.panelVisible, status.position = state.action, key,
        suffix, panel, panelVisible, position
    status:ClearAllPoints()
    if panel and panel:IsVisible() then
        status:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -4)
    else
        if position then
            status:SetPoint(position.point, UIParent, position.relative, position.x, position.y)
        else
            status:SetPoint("CENTER", UIParent, "CENTER", 240, 120)
        end
    end
    if state.action.iconAtlas then
        status.icon:SetAtlas(state.action.iconAtlas)
    else
        status.icon:SetTexture(state.action.icon or 134400)
    end
    status.text:SetText(Pad.Glyph(key) .. " " .. state.action.label .. suffix)
    local appearance = NS.Internal.Appearance
    if appearance then
        appearance.Tag(status, "guide." .. state.key)
        appearance.Text(status.text, "guide." .. state.key, "TEXT", "actions")
    end
    status:Show()
end

function Pad.RefreshGuideAction()
    if not Pad.Available() then return end
    local key = NS.GetActiveGuideProvider()
    local db = NS.GetDB and NS.GetDB()
    local wanted = Key() and (not db or db.controllerEnabled ~= false)
    local actions = wanted and key and Pad.GuideActionList(key) or empty
    if InCombatLockdown() then
        local old = prepared.global
        local nextAction = #actions == 1 and Secure(actions[1]) and actions[1] or nil
        Pad.actionPending = not old or old.key ~= key or old.action ~= nextAction
    else
        Pad.actionPending = nil
        Prepare("global", key, actions)
        if wanted and key and not Actions.models[key] and not requested[key] then
            requested[key] = true; Actions.Request(key)
        end
    end
    UpdateStatus()
end

function Pad.GuideActionsChanged(key)
    if Actions.models[key] then requested[key] = nil end
    Pad.RefreshGuideAction()
    if Pad.focus then
        local record = Pad.controls[Pad.focus]
        if record and record.guide == key and not InCombatLockdown() then
            Pad.OnFocus(Pad.focus, record); Pad.RefreshBindings()
        end
    end
end

local function GuideMore(line)
    if line._awpMoreMenu ~= nil then
        if line._awpMoreMenu then line._awpMoreMenu(line) end
        return
    end
    local script = line:GetScript("OnMouseUp")
    if script then script(line, "RightButton") end
end
local function HasRowMenu(line)
    if line._awpMoreMenu ~= nil then return type(line._awpMoreMenu) == "function" end
    return type(line:GetScript("OnMouseUp")) == "function"
end

-- ============================================================
-- Tracker row and header bindings
-- ============================================================

function Pad.BindGuideRow(line, key, owner, stepOwner, decorative)
    if not line then return end
    line._awpControllerVisualOnly = decorative == true or nil
    local record = Pad.RegisterControl(line,
        {
            id = "guide:" .. key .. ":" .. tostring(owner) .. ":" .. tostring(line.objectiveKey),
            guide = key,
            visualOnly = decorative == true
        })
    if not record then return end
    if decorative then
        record.owner, record.stepOwner, record.action, record.more, record.moreAvailable = nil, nil, nil, nil, nil
        return
    end
    record.owner, record.stepOwner, record.action = owner, stepOwner, nil
    record.more = GuideMore
    record.moreAvailable = HasRowMenu
end

function Pad.ReleaseGuideRow(line)
    if line then line._awpControllerVisualOnly = nil end
    local record = line and Pad.controls[line]
    if not record then return end
    record.guide, record.owner, record.stepOwner, record.action, record.more, record.owners, record.id = nil, nil, nil,
        nil, nil, nil, nil
    record.selection = nil
    record.moreAvailable = nil
end

function Pad.BindGuideHeader(module, block, key)
    if not NS.IsWoWForever or not NS.IsWoWForever() then return end
    local owner = block._awpTaskAction and block._awpTaskAction.task or block._awpOwnerStepIndex
    if not owner then return end
    local header = block.HeaderButton or block
    Pad.BindGuideRow(header, key, owner)
    local record = Pad.controls[header]
    Pad.RegisterControl(header, { nativeAction = true })
    record.id = "heading:" .. key .. ":" .. tostring(owner)
    record.owners = { [owner] = true }
    for _, line in pairs(block.usedLines or {}) do
        local child = Pad.controls[line]
        if child and child.owner ~= nil then record.owners[child.owner] = true end
    end
    header.OnSmartNavClick = function()
        if not Pad.Enabled() then return end
        if module.OnBlockHeaderClick then module:OnBlockHeaderClick(block, "LeftButton") end
        return true
    end
    record.more = function() if module.OnBlockHeaderClick then module:OnBlockHeaderClick(block, "RightButton") end end
    record.moreAvailable = function() return type(module.OnBlockHeaderClick) == "function" end
end

function Pad.OnFocus(_, record)
    Pad.contextButton, Pad.contextLabel = nil, nil
    if not record or not record.guide or InCombatLockdown() then return end
    local actions = Pad.GuideActionList(record.guide, record)
    if #actions == 0 then return end
    Prepare("context", record.guide, actions)
    Pad.contextButton = "AWPControllerContextAction"
    Pad.contextLabel = #actions > 1 and "Choose action" or actions[1].label
end

-- ============================================================
-- Navigation and diagnostics
-- ============================================================

function Pad.NavigateGuides(actionsOnly)
    if not Pad.Enabled() or InCombatLockdown() then
        NS.Msg("AWP controller navigation requires Forever's controller UI outside combat."); return
    end
    local active = NS.GetActiveGuideProvider()
    local first
    for _, key in ipairs(NS.GetGuideTrackerViewerOrder()) do
        local provider = NS.GetGuideTrackerViewerProvider(key)
        local module = provider and provider.moduleName and _G[provider.moduleName]
        local frame = actionsOnly and Actions.panels[key] or module
        if frame and frame:IsVisible() then
            if key == active then
                first = frame; break
            end
            first = first or frame
        end
    end
    if first then
        Pad.Enter(first)
    else
        NS.Msg(actionsOnly and "No AWP guide action panel is visible." or
            "No AWP guide viewer is visible.")
    end
end

function Pad.ActionDiagnostics()
    local action = prepared.global and prepared.global.action
    local key = Key()
    NS.Msg("[CONTROLLER]", "action=" .. tostring(action and action.label),
        "pending=" .. tostring(Pad.actionPending == true),
        "key=" .. tostring(key), "effective=" .. tostring(key and GetBindingAction(key, true)),
        "context=" .. tostring(Pad.contextLabel))
end

if NS.IsWoWForever and NS.IsWoWForever() then
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS", "INPUT_DEVICE_INTERFACE_TRANSITION" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function() Pad.RefreshGuideAction() end)
    if NS.ScheduleGuideProviderEvaluation and hooksecurefunc then
        hooksecurefunc(NS, "ScheduleGuideProviderEvaluation", function() Pad.RefreshGuideAction() end)
    end
end

_G.BINDING_HEADER_AZEROTHWAYPOINT = "AzerothWaypoint"
_G.BINDING_NAME_AWP_CONTROLLER_GUIDES = "Navigate AWP Guides"
_G.BINDING_NAME_AWP_CONTROLLER_MENU = "Open AWP Menu"
_G["BINDING_NAME_" .. ACTION_BINDING] = "Use Active Guide Action"
