-- ============================================================
-- Guide Viewer row actions
-- ============================================================
--
-- Checks row actions against the owning guide adapter. Descriptors keep copied
-- IDs and revisions so a reused row can be checked against the current guide.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local Actions = {}
Common.Actions = Actions
local printed = {}
local rowProviders = {}

function Actions.RegisterRowProvider(key, provider) rowProviders[key] = provider end

function Actions.GetRowActionState(descriptor)
    local provider = descriptor and rowProviders[descriptor.provider]
    if not provider then return false, "Guide action is unavailable." end
    local ok, enabled, reason = pcall(provider.available, descriptor)
    if not ok then return false, "Guide action is unavailable." end
    if enabled ~= true then return false, reason or "Guide action is unavailable." end
    return true
end

function Actions.RunRowAction(descriptor)
    local enabled, reason = Actions.GetRowActionState(descriptor)
    if not enabled then return false, reason end
    local provider = rowProviders[descriptor.provider]
    local ok, result, message = pcall(provider.run, descriptor)
    if not ok then return false, "Native guide action failed." end
    if result ~= true then return false, message or "Native guide action failed." end
    return true, message
end

function Actions.AddRowMenuEntry(root, descriptor)
    local item = root:CreateButton(descriptor.label, function()
        local ok, reason = Actions.RunRowAction(descriptor)
        if not ok and reason and NS.Msg then NS.Msg(reason) end
    end)
    local enabled, reason = Actions.GetRowActionState(descriptor)
    item:SetEnabled(enabled)
    if not enabled and reason and item.SetTooltip then item:SetTooltip(function(tooltip) tooltip:AddLine(reason) end) end
    return item
end

function Actions.BindRowAction(line, descriptor, rightClick, leftMenu)
    -- Controller More invokes the same command directly. A left-click-only
    -- interaction is not evidence that a right-click menu exists.
    line._awpMoreMenu = rightClick or false
    line:EnableMouse(true)
    line:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            if rightClick then rightClick(line) end
        elseif button == "LeftButton" then
            if leftMenu then return leftMenu(line, descriptor) end
            local ok, reason = Actions.RunRowAction(descriptor)
            if not ok and reason and NS.Msg then NS.Msg(reason) end
        end
    end)
end

local aliases = {
    forward = "next",
    previous = "prev",
    back = "prev",
    force = "skip",
    new = "picker",
    open = "load",
    guidemenu = "menu",
    options = "settings",
    resetwindow = "reset",
    fix = "reset",
    print = "output",
    step = "output",
    guides = "list",
    tabs = "list",
    select = "switch",
    activate = "switch",
    clear = "close"
}

-- ============================================================
-- Guide controls and snapshots
-- ============================================================

local function Controls(key)
    local provider = NS.GetGuideTrackerViewerProvider(key)
    if not provider then return nil end
    if type(provider.isAvailable) == "function" and not provider.isAvailable() then return nil end
    return provider.controls, provider
end

function Actions.GetOpenGuides(key)
    if Common.Tabs.Supports(key) then
        local state = Common.Tabs.GetState(key)
        return state and state.entries or {}
    end
    local controls = Controls(key)
    local out = {}
    if not controls or type(controls.guides) ~= "function" then return out end
    for _, entry in ipairs(controls.guides() or {}) do
        if type(entry.id) == "string" and entry.id ~= "" then
            out[#out + 1] = {
                id = entry.id,
                label = entry.label or entry.id,
                active = entry.active == true,
                index = entry.index,
                owned = entry.owned
            }
        end
    end
    return out
end

-- Catalogs are read only on an explicit load command. Never choose an
-- arbitrary partial title or retain a provider's mutable guide objects.
function Actions.ResolveGuide(query, catalog)
    local matches, exact, seen = {}, nil, {}
    for _, entry in ipairs(catalog) do
        if entry.id == query then exact = entry.id end
        if not seen[entry.id] and entry.label and entry.label:lower() == query:lower() then
            matches[#matches + 1] = entry; seen[entry.id] = true
        end
    end
    if exact then return exact end
    if #matches == 1 then return matches[1].id end
    if #matches > 1 then
        NS.Msg("Several guides have that title. Use a canonical guide ID:")
        for _, entry in ipairs(matches) do NS.Msg(entry.id) end
        return nil, "ambiguous_guide"
    end
    return nil, "guide_not_found"
end

function Actions.OutputSnapshot(key, snapshot, mode, currentOnly)
    if not snapshot or not snapshot.title then return false, "no_guide" end
    return Common.Chat.Output(key, Common.Chat.FromSnapshot(snapshot, currentOnly), mode)
end

function Actions.Run(key, action, arg)
    if Common.Tabs.Supports(key) then
        if action == "picker" then return Common.Tabs.OpenNew(key) end
        if action == "switch" or action == "close" or action == "closeAll" then return Common.Tabs.Run(key, action, arg) end
    end
    local controls = Controls(key)
    if not controls then return false, "provider_unavailable" end
    local fn = controls[action]
    if type(fn) ~= "function" then return false, "unsupported_action" end
    if controls.getActionState then
        local enabled, reason = controls.getActionState(action)
        if not enabled then return false, reason end
    end
    -- These are non-yielding integration entry points, never native parsers.
    local ok, result, reason = pcall(fn, arg)
    if not ok then return false, "action_failed" end
    if result ~= true then return false, reason or "action_unavailable" end
    return true, reason
end

function Actions.GetActionState(key, action)
    local controls = Controls(key)
    if not controls or type(controls[action]) ~= "function" then return false, "Action unavailable." end
    if type(controls.getActionState) == "function" then return controls.getActionState(action) end
    return Actions.GetDefaultActionState(key, action)
end

local requiresGuide = {
    next = true,
    prev = true,
    skip = true,
    complete = true,
    active = true,
    route = true,
    reload = true,
    tasks = true,
    automatic = true,
    output = true,
    steps = true
}
local combatActions = { active = true, route = true, output = true, compact = true }

function Actions.GetDefaultActionState(key, action)
    local controls = Controls(key)
    if not controls or type(controls[action]) ~= "function" then return false, "Action unavailable." end
    local target = NS.GetGuideTargetProvider and NS.GetGuideTargetProvider(key)
    if requiresGuide[action] then
        local present
        if controls.hasGuide then
            present = controls.hasGuide()
        elseif target and target.hasGuide then
            present = target.hasGuide()
        end
        local list = present == nil and type(controls.guides) == "function" and controls.guides()
        local tabs = present == nil and type(controls.tabState) == "function" and controls.tabState()
        if present == false or present == nil and (list and #list == 0 or tabs and tabs.slots and #tabs.slots == 0) then
            return false, "No guide selected."
        end
    end
    if InCombatLockdown() and not combatActions[action] then
        return false, "This guide control is unavailable during combat."
    end
    return true
end

local function IndexedGuide(key, arg)
    local list = printed[key] or Actions.GetOpenGuides(key)
    local number = tonumber(arg)
    local state = Common.Tabs.Supports(key) and Common.Tabs.GetState(key)
    local entry
    if number and number == math.floor(number) then
        if state and state.mode ~= "recent" then
            for _, candidate in ipairs(list) do if candidate.index == number then
                    entry = candidate; break
                end end
        else
            entry = list[number]
        end
    end
    if not entry then return nil, "no_guide_at_index" end
    for _, current in ipairs(Actions.GetOpenGuides(key)) do
        if current.id == entry.id and current.index == entry.index and current.owned == entry.owned
            and current.epoch == entry.epoch and current.source == entry.source then
            return current
        end
    end
    return nil, "guide_list_changed_list_again"
end

local commandOrder = { "next", "prev", "skip", "complete", "active", "route", "reload", "tasks", "automatic",
    "picker", "load", "menu", "settings", "steps", "output", "reset", "compact" }
local commandLabels = { load = "load <guide>", output = "output [full|sticky]" }

-- ============================================================
-- Slash command help and dispatch
-- ============================================================

local function ShowCommandHelp(key)
    local provider = NS.GetGuideTrackerViewerProvider(key)
    local controls = provider and provider.controls
    if not controls then
        NS.Msg(key .. ": guide addon is unavailable."); return
    end
    local commands = {}
    for _, command in ipairs(commandOrder) do
        if type(controls[command]) == "function" then
            commands[#commands + 1] = controls.commandLabels and controls.commandLabels[command] or
            commandLabels[command] or command
        end
    end
    if controls.guides or controls.tabState then
        commands[#commands + 1] = "list"
        if controls.switch or controls.tabState then commands[#commands + 1] = "switch <index>" end
        if controls.close or controls.tabState then commands[#commands + 1] = "close [current|index|all]" end
    end
    commands[#commands + 1] = "status"
    commands[#commands + 1] = "viewer on|off|toggle|status"
    commands[#commands + 1] = "native show|hide|toggle|status"
    NS.Msg("/awp " .. key .. " " .. table.concat(commands, " | "))
end

function Actions.Handle(key, input)
    local action, arg = (input or ""):match("^%s*(%S+)%s*(.-)%s*$")
    action, arg = aliases[(action or ""):lower()] or (action or ""):lower(), arg or ""
    if key == "zygor" and action == "output" and arg:lower() == "stickies" then arg = "sticky" end
    if action == "" or action == "help" then
        return ShowCommandHelp(key)
    end
    local controls, provider = Controls(key)
    if not controls or not provider then
        NS.Msg(key .. ": guide addon is unavailable."); return
    end
    if action == "list" then
        local list = Actions.GetOpenGuides(key); printed[key] = list
        local tabState = Common.Tabs.Supports(key) and Common.Tabs.GetState(key)
        if #list == 0 then NS.Msg(provider.displayName .. ": no open guides.") end
        for i, entry in ipairs(list) do
            local number = tabState and tabState.mode ~= "recent" and entry.index or i
            NS.Msg(string.format("%s%d. %s", entry.active and "* " or "  ", number, entry.label))
        end
        return
    elseif action == "status" then
        local settings = NS.GetGuideTrackerViewerProviderSettings(key)
        NS.Msg(provider.displayName, "active:", NS.GetActiveGuideProvider() == key, "viewer:", settings.enabled,
            "native hidden:", settings.hideNative, "open guides:", #Actions.GetOpenGuides(key))
        return
    elseif action == "viewer" or action == "native" then
        local settings = NS.GetGuideTrackerViewerProviderSettings(key)
        local field = action == "viewer" and "enabled" or "hideNative"
        arg = arg:lower()
        if arg == "" or arg == "status" then
            NS.Msg(provider.displayName, action, settings[field]); return
        end
        local value
        if arg == "toggle" then
            value = not settings[field]
        elseif action == "viewer" and (arg == "on" or arg == "enable") or action == "native" and arg == "hide" then
            value = true
        elseif action == "viewer" and (arg == "off" or arg == "disable") or action == "native" and arg == "show" then
            value = false
        else
            NS.Msg("Invalid " .. action .. " option."); return
        end
        NS.SetGuideTrackerViewerProviderSetting(key, field, value)
        NS.ApplyGuideTrackerViewerSettings(key)
        NS.Msg(provider.displayName, action, value)
        return
    end
    if InCombatLockdown() and not combatActions[action] then
        NS.Msg("This guide control is unavailable during combat.")
        return
    end
    local ok, reason
    if action == "switch" then
        local entry; entry, reason = IndexedGuide(key, arg)
        if entry then ok, reason = Actions.Run(key, "switch", entry) end
    elseif action == "close" then
        local list = Actions.GetOpenGuides(key)
        if arg:lower() == "all" then
            if Common.Tabs.Supports(key) then
                ok, reason = Actions.Run(key, "closeAll")
            else
                ok = true
                for i = #list, 1, -1 do
                    local closed, why = Actions.Run(key, "close", list[i])
                    if not closed then ok, reason = false, why end
                end
            end
        else
            local entry
            if arg == "" or arg:lower() == "current" then
                for _, candidate in ipairs(list) do if candidate.active then
                        entry = candidate; break
                    end end
            else
                entry, reason = IndexedGuide(key, arg)
            end
            if entry then ok, reason = Actions.Run(key, "close", entry) end
        end
    elseif action == "output" and arg ~= "" and arg ~= "full" and arg ~= "sticky" then
        ok, reason = false, "output_requires_full_or_sticky"
    else
        if action == "load" and arg == "" then action = "picker" end
        ok, reason = Actions.Run(key, action, arg ~= "" and arg or nil)
    end
    if ok and action == "output" then return end
    local suffix = (action == "load" or action == "reload" or action == "route") and " requested." or " completed."
    NS.Msg(provider.displayName .. ": " .. (ok and (reason or (action .. suffix)) or (reason or "action unavailable")))
end
