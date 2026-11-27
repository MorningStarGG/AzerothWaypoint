-- ============================================================
-- Guide tab menus
-- ============================================================
--
-- Reads each guide's tab controls and builds menu entries for opening,
-- switching and closing guides.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local Tabs = { LIMIT = Common.GUIDE_TAB_LIMIT }
Common.Tabs = Tabs
local snapshots = {}

local function Controls(key)
    local provider = NS.GetGuideTrackerViewerProvider(key)
    if not provider or type(provider.controls) ~= "table" then return end
    if type(provider.isAvailable) == "function" and not provider.isAvailable() then return end
    return provider.controls
end

function Tabs.Supports(key)
    local controls = Controls(key)
    return controls and type(controls.tabState) == "function" or false
end

local function Equal(a, b)
    if not a or a.mode ~= b.mode or a.source ~= b.source or a.capacity ~= b.capacity
        or a.mutable ~= b.mutable or a.reason ~= b.reason or #a.slots ~= #b.slots then
        return false
    end
    for index, slot in ipairs(b.slots) do
        local previous = a.slots[index]
        if previous.id ~= slot.id or previous.index ~= slot.index or previous.label ~= slot.label
            or previous.active ~= slot.active or previous.owned ~= slot.owned then
            return false
        end
    end
    return true
end

function Tabs.GetState(key)
    local controls = Controls(key)
    if not controls or type(controls.tabState) ~= "function" then return end
    local ok, raw = pcall(controls.tabState)
    if not ok or type(raw) ~= "table" then return end
    local state = {
        mode = raw.mode,
        source = raw.source,
        capacity = raw.capacity or Tabs.LIMIT,
        mutable = raw.mutable ~= false,
        reason = raw.reason,
        slots = {},
        entries = {}
    }
    for _, value in ipairs(raw.slots or {}) do
        if type(value) == "table" and type(value.id) == "string" then
            local slot = {
                id = value.id,
                index = value.index,
                label = value.label or value.id,
                active = value.active == true,
                owned = value.owned == true
            }
            if state.mode ~= "recent" and slot.id ~= "" then
                local prefix = type(slot.index) == "number" and slot.index > 0 and ("Tab " .. slot.index) or
                "Current Guide"
                slot.label = prefix .. " — " .. slot.label
            end
            state.slots[#state.slots + 1] = slot
            if slot.id ~= "" then state.entries[#state.entries + 1] = slot end
        end
    end
    local previous = snapshots[key]
    if Equal(previous, state) then return previous end
    state.epoch = previous and previous.epoch + 1 or 1
    for _, slot in ipairs(state.slots) do slot.epoch, slot.source = state.epoch, state.source end
    snapshots[key] = state
    return state
end

local function Call(key, action, entry, guideID)
    local controls = Controls(key)
    local fn = controls and controls[action]
    if type(fn) ~= "function" then return false, "action_unavailable" end
    local ok, result, reason = pcall(fn, entry, guideID)
    if not ok then return false, "action_failed" end
    return result == true, reason
end

function Tabs.Run(key, action, expected)
    local state = Tabs.GetState(key)
    if not state then return false, "provider_unavailable" end
    if InCombatLockdown() then return false, "combat" end
    if not state.mutable then return false, state.reason or "guide_controls_unavailable" end
    if expected then
        if expected.epoch ~= state.epoch or expected.source ~= state.source then return false,
                "guide_list_changed_list_again" end
        local found
        for _, entry in ipairs(state.entries) do
            if entry.index == expected.index and entry.id == expected.id then
                found = entry; break
            end
        end
        if not found then return false, "stale_guide" end
        expected = found
    end
    return Call(key, action, expected)
end

local function Report(ok, reason)
    if not ok and NS.Msg then NS.Msg("Guide control:", reason or "action unavailable") end
    return ok
end

function Tabs.OpenNew(key, anchor, guideID)
    local state = Tabs.GetState(key)
    if not state then return false, "provider_unavailable" end
    if InCombatLockdown() or not state.mutable then return false, state.reason or "guide_controls_unavailable" end
    if state.mode == "recent" or #state.entries < state.capacity then return Call(key, "newGuide", nil, guideID) end
    if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then return false, "close_a_tab_first" end
    NS.Internal.Menus.CreateContextMenu(anchor or UIParent, function(_, root)
        root:CreateTitle("All guide slots are occupied. Choose a tab to close:")
        for _, entry in ipairs(state.entries) do
            root:CreateButton("Close " .. entry.label, function()
                local fresh = Tabs.GetState(key)
                if not fresh or fresh.epoch ~= state.epoch or InCombatLockdown() or not fresh.mutable then
                    return Report(false, "guide_list_changed_list_again")
                end
                return Report(Call(key, "newGuide", entry, guideID))
            end)
        end
        root:CreateButton("Cancel", function() end)
    end)
    return true, "Choose a tab to close."
end

function Tabs.AddMenu(key, root, anchor)
    local state = Tabs.GetState(key)
    if not state then
        root:CreateTitle("Guide controls unavailable"); return
    end
    local active
    for _, entry in ipairs(state.entries) do
        if entry.active then active = entry end
        local submenu = root:CreateButton(entry.label)
        if submenu.SetIsSelected then submenu:SetIsSelected(entry.active) end
        submenu:CreateButton("Switch to Guide", function() Report(Tabs.Run(key, "switch", entry)) end)
            :SetEnabled(state.mutable and not InCombatLockdown())
        submenu:CreateButton(state.mode == "recent" and "Close Guide" or "Close Tab",
            function() Report(Tabs.Run(key, "close", entry)) end)
            :SetEnabled(state.mutable and not InCombatLockdown())
    end
    if #state.entries == 0 then root:CreateTitle("No open guides") end
    root:CreateDivider()
    if active then
        root:CreateButton("Close Current Guide", function() Report(Tabs.Run(key, "close", active)) end)
            :SetEnabled(state.mutable and not InCombatLockdown())
    end
    if #state.entries > 0 then
        root:CreateButton("Close All Guides", function()
            local fresh = Tabs.GetState(key)
            if not fresh or fresh.epoch ~= state.epoch then return Report(false, "guide_list_changed_list_again") end
            Report(Tabs.Run(key, "closeAll"))
        end):SetEnabled(state.mutable and not InCombatLockdown())
    end
    root:CreateButton("Open New Guide...", function() Report(Tabs.OpenNew(key, anchor)) end)
        :SetEnabled(state.mutable and not InCombatLockdown())
end
