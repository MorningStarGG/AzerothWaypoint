-- ============================================================
-- Dugi guide tabs
-- ============================================================
--
-- Tracks open Dugi guides and applies tab changes through its native guide
-- loader.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local Tabs = {}
Common.DugiTabs = Tabs
local slots, activeSlot, observedTitle, reservation, pendingLoad, passiveTitle

local function Runtime() return rawget(_G, "DugisGuideViewer") end
local function Current()
    local dugi = Runtime()
    local id = rawget(_G, "CurrentTitle") or dugi and dugi.CurrentTitle
    return type(id) == "string" and id ~= "" and id or nil
end

local function Busy()
    local dugi = Runtime()
    if not dugi then return true end
    local threads = type(dugi.ThreadInProgress) == "function" and dugi or rawget(_G, "LuaUtils")
    if threads and type(threads.ThreadInProgress) == "function" then
        local ok, loading = pcall(threads.ThreadInProgress, threads, "DisplayViewTab")
        if not ok or loading then return true end
    end
    return dugi.firstGuideLoaded == false
end

local function Native()
    local dugi = Runtime()
    local modules = dugi and dugi.Modules
    if type(modules) ~= "table" then return end
    local first, second = "SmallFrame", "Objectives"
    if type(dugi.IsSmallFrameFloating) == "function" and not dugi:IsSmallFrameFloating() then
        first, second = second,
            first
    end
    for _, key in ipairs({ first, second }) do
        local source = modules[key]
        local owner = source and type(source.trackerModuleName) == "string" and rawget(_G, source.trackerModuleName)
        if owner and type(owner.SetGuideForActiveTab) == "function" and owner.TabContainer
            and type(owner.TabContainer.GetChildren) == "function" then
            local tabs = {}
            for _, child in ipairs({ owner.TabContainer:GetChildren() }) do
                local tab = child.tab
                if type(tab) == "table" and tab.used and type(tab.tabIndex) == "number" then
                    tabs[#tabs + 1] = { frame = child, tab = tab }
                end
            end
            if #tabs > 0 then
                table.sort(tabs, function(a, b) return a.tab.tabIndex < b.tab.tabIndex end)
                return owner, tabs
            end
        end
    end
end

local function Save()
    Common.SetOpenGuides("dugi", slots)
    Common.SetActiveGuideSlot("dugi", activeSlot)
end

local function Managed(current)
    if not slots then
        slots = Common.GetOpenGuides("dugi")
        local user = rawget(_G, "DugisGuideUser")
        if not slots then
            slots = {}
            for index, tab in ipairs(user and user.smallFrameTabs or {}) do
                slots[index] = type(tab) == "table" and type(tab.guide) == "string" and tab.guide or ""
                if type(tab) == "table" and tab.active then activeSlot = index end
            end
        end
        activeSlot = Common.GetActiveGuideSlot("dugi") or activeSlot or 1
        for index = #slots + 1, Common.GUIDE_TAB_LIMIT do slots[index] = "" end
        if slots[activeSlot] == nil then activeSlot = 1 end
        if current then
            local found
            for index, id in ipairs(slots) do if id == current and (not found or index == activeSlot) then found = index end end
            if not found then
                for index = 1, Common.GUIDE_TAB_LIMIT do
                    if slots[index] == "" then
                        found = index; break
                    end
                end
                found = found or activeSlot
                slots[found] = current
            end
            activeSlot = found
        end
        observedTitle = current
        Save()
    end
    if pendingLoad and current == pendingLoad.id then
        slots[pendingLoad.index], activeSlot = current, pendingLoad.index
        pendingLoad, reservation = nil, nil
        observedTitle = current
        Save()
    elseif current ~= observedTitle then
        if current then
            local found
            if not reservation then
                for index, id in ipairs(slots) do
                    if id == current and (not found or index == activeSlot) then
                        found =
                            index
                    end
                end
            end
            activeSlot = found or activeSlot
            slots[activeSlot] = current
        elseif slots[activeSlot] == observedTitle then
            slots[activeSlot] = ""
        end
        observedTitle, reservation = current, nil
        Save()
    end
    return slots
end

local function Label(id)
    local dugi = Runtime()
    if id ~= "" and dugi and type(dugi.GetFormattedTitle) == "function" then
        local ok, text = pcall(dugi.GetFormattedTitle, dugi, id)
        if ok then return NS.Internal.DugiPresentation.StripMarkup(text) or id end
    end
    return id
end

-- ============================================================
-- Tab state
-- ============================================================

function Tabs.GetState()
    local current = Current()
    local owner, native = Native()
    local out, mode, source = {}, "saved", "saved"
    if native then
        mode, source = "native", tostring(owner)
        for _, handle in ipairs(native) do
            local tab = handle.tab
            local id = type(tab.guide) == "string" and tab.guide or ""
            out[#out + 1] = {
                id = id,
                index = tab.tabIndex,
                active = tab.active == true and id == current,
                label = Label(
                    id)
            }
        end
    elseif Common.Host.IsKTLoaded() then
        mode, source = "managed", "dugi-managed:" .. tostring(Runtime())
        for index, id in ipairs(Managed(current)) do
            out[#out + 1] = { id = id, index = index, label = Label(id), active = index == activeSlot and id == current, owned = true }
        end
    else
        local user = rawget(_G, "DugisGuideUser")
        local found
        for index, tab in ipairs(user and user.smallFrameTabs or {}) do
            local id = type(tab) == "table" and type(tab.guide) == "string" and tab.guide or ""
            if id == current then found = true end
            out[#out + 1] = {
                id = id,
                index = index,
                label = Label(id),
                active = type(tab) == "table" and
                    tab.active == true and id == current
            }
        end
        if current and not found then out[#out + 1] = { id = current, index = 0, label = Label(current), active = true } end
    end
    local busy = Busy()
    return {
        mode = mode,
        source = source,
        slots = out,
        capacity = mode == "native" and math.min(Common.GUIDE_TAB_LIMIT, #out) or Common.GUIDE_TAB_LIMIT,
        mutable = mode ~= "saved" and not busy,
        reason = busy and "guide_loading" or mode == "saved" and "native_tabs_unavailable" or nil
    }
end

local function Find(expected)
    local state = Tabs.GetState()
    if not state.mutable or InCombatLockdown() then return nil, state.reason or "combat" end
    for _, entry in ipairs(state.slots) do
        if entry.index == expected.index and entry.id == expected.id and entry.owned == (expected.owned or nil)
            and (not expected.source or expected.source == state.source) then
            return entry, state
        end
    end
    return nil, "stale_guide"
end

-- The native setter is synchronous: it changes its selected slot and runs
-- LayoutTabs. Temporarily selecting a slot here never loads a guide/parser.
local function NativeTransaction(clear, selectIndex)
    local owner, handles = Native()
    if not owner or not handles or not handles[1] or Busy() then return false end
    local saved, selected = {}, nil
    for _, handle in ipairs(handles) do
        local tab = handle.tab
        saved[#saved + 1] = { tab = tab, guide = tab.guide, type = tab.type, active = tab.active }
        if tab.active then selected = tab.tabIndex end
    end
    selected = selectIndex or selected or handles[1].tab.tabIndex
    local function select(index)
        local chosen
        for _, handle in ipairs(handles) do
            local tab = handle.tab
            tab.active = tab.tabIndex == index
            if tab.active then chosen = tab end
        end
        return assert(chosen, "Native tab disappeared")
    end
    local function set(id, kind)
        assert(owner:SetGuideForActiveTab(id, kind) ~= false, "Native setter rejected tab update")
    end
    local function restore()
        for _, value in ipairs(saved) do
            pcall(function()
                select(value.tab.tabIndex); set(value.guide, value.type)
            end)
        end
        local original
        for _, value in ipairs(saved) do
            value.tab.guide, value.tab.type, value.tab.active = value.guide, value.type, value.active
            if value.active then original = value end
        end
        if original then pcall(function() set(original.guide, original.type) end) end
        for _, value in ipairs(saved) do value.tab.active = value.active end
    end
    local ok = pcall(function()
        for _, handle in ipairs(handles) do
            if clear[handle.tab.tabIndex] then
                select(handle.tab.tabIndex); set("", "Clear")
            end
        end
        local tab = select(selected)
        set(tab.guide, tab.type)
    end)
    if not ok then restore() end
    return ok, restore
end

local function Notify()
    if NS.ScheduleGuideProviderEvaluation then NS.ScheduleGuideProviderEvaluation("dugi", "DugiTabsChanged") end
    if NS.RefreshGuideTrackerViewerProvider then NS.RefreshGuideTrackerViewerProvider("dugi", "tabs") end
end

function Tabs.IsPassiveSelection(id)
    local passive = passiveTitle ~= nil and passiveTitle == id
    passiveTitle = nil
    return passive
end

function Tabs.Switch(expected, options)
    local entry, state = Find(expected)
    if not entry then return false, state end
    local dugi = Runtime()
    local explicit = not (options and options.passive)
    local loading
    pendingLoad, passiveTitle = nil, nil
    if state.mode == "managed" then
        if entry.id ~= Current() then
            if type(dugi.DisplayViewTabInThread) ~= "function" then return false, "loader_unavailable" end
            pendingLoad = { id = entry.id, index = entry.index }
            if not explicit then passiveTitle = entry.id end
            local ok = pcall(dugi.DisplayViewTabInThread, dugi, entry.id, nil, true)
            if not ok then
                pendingLoad, passiveTitle = nil, nil; return false, "guide_load_failed"
            end
            loading = true
        else
            activeSlot = entry.index; Save()
        end
    elseif entry.id == Current() then
        if not NativeTransaction({}, entry.index) then return false, "native_tab_update_failed" end
    else
        local _, handles = Native()
        local found
        for _, handle in ipairs(handles or {}) do
            if handle.tab.tabIndex == entry.index and handle.tab.guide == entry.id then
                local handler = handle.frame:GetScript("OnMouseDown")
                if type(handler) ~= "function" then return false, "native_tab_controls_unavailable" end
                if not explicit then passiveTitle = entry.id end
                found = pcall(handler, handle.frame, "LeftButton")
                loading = found
                break
            end
        end
        if not found then
            passiveTitle = nil; return false, "native_tab_controls_unavailable"
        end
    end
    if explicit then NS.SelectGuideProvider("dugi", "DugiTabSelected") end
    Notify()
    return true, loading and "Guide switch requested." or nil
end

-- ============================================================
-- Closing and reopening guides
-- ============================================================

local function ClearCurrent()
    local dugi = Runtime()
    if type(dugi.ClearGuide) ~= "function" then return false end
    local ok, result = pcall(dugi.ClearGuide)
    return ok and result ~= false and Current() == nil
end

function Tabs.Close(expected, options)
    local entry, state = Find(expected)
    if not entry then return false, state end
    pendingLoad, passiveTitle = nil, nil
    if state.mode == "managed" then
        if entry.active and not ClearCurrent() then return false, "guide_clear_failed" end
        slots[entry.index] = ""
        if entry.active then observedTitle = nil end
        Save()
    else
        local ok, restore = NativeTransaction({ [entry.index] = true })
        if not ok then return false, "native_tab_update_failed" end
        if entry.active and not ClearCurrent() then
            if restore then restore() end
            return false, "guide_clear_failed"
        end
    end
    Notify()
    if entry.active and not (options and options.noSelect) then
        for _, remaining in ipairs(Tabs.GetState().slots) do
            if remaining.id ~= "" then
                local ok, why = Tabs.Switch(remaining, { passive = true })
                return ok, ok and "Tab closed, next guide load requested." or why
            end
        end
    end
    return true
end

function Tabs.CloseAll()
    local state = Tabs.GetState()
    if InCombatLockdown() or not state.mutable then return false, state.reason or "combat" end
    local restore
    if state.mode == "native" then
        local clear = {}; for _, entry in ipairs(state.slots) do clear[entry.index] = true end
        local ok
        ok, restore = NativeTransaction(clear)
        if not ok then return false, "native_tab_update_failed" end
    end
    if Current() and not ClearCurrent() then
        if restore then restore() end
        return false, "guide_clear_failed"
    end
    if state.mode == "managed" then
        for index in ipairs(slots) do slots[index] = "" end
        activeSlot, observedTitle, pendingLoad, passiveTitle, reservation = 1, nil, nil, nil, nil
        Save()
    end
    Notify()
    return true
end

function Tabs.NewGuide(closeEntry, guideID)
    local dugi = Runtime()
    if not dugi or guideID and type(dugi.DisplayViewTabInThread) ~= "function" then return false, "loader_unavailable" end
    if not guideID and type(dugi.ShowLargeWindow) ~= "function" then return false, "chooser_unavailable" end
    local previous
    for _, entry in ipairs(Tabs.GetState().slots) do
        if entry.active then
            previous = entry; break
        end
    end
    local function restoreSelection()
        pendingLoad, passiveTitle, reservation = nil, nil, nil
        local available = Tabs.GetState().slots
        if previous then
            for _, entry in ipairs(available) do
                if entry.id == previous.id and entry.index == previous.index then
                    return Tabs.Switch(entry,
                        { passive = true })
                end
            end
        end
        for _, entry in ipairs(available) do if entry.id ~= "" then return Tabs.Switch(entry, { passive = true }) end end
    end
    if closeEntry then
        local ok, why = Tabs.Close(closeEntry, { noSelect = true })
        if not ok then return false, why end
    end
    local state = Tabs.GetState()
    if InCombatLockdown() or not state.mutable then return false, state.reason or "combat" end
    local occupied = 0
    for _, entry in ipairs(state.slots) do if entry.id ~= "" then occupied = occupied + 1 end end
    if occupied >= state.capacity then return false, "close_a_tab_first" end
    local empty
    for _, entry in ipairs(state.slots) do
        if entry.id == "" and entry.index <= state.capacity and (not empty or closeEntry and entry.index == closeEntry.index) then
            empty =
                entry
        end
    end
    if not empty then return false, "close_a_tab_first" end
    if state.mode == "native" and not NativeTransaction({}, empty.index) then return false, "native_tab_update_failed" end
    if Current() and not ClearCurrent() then
        restoreSelection(); return false, "guide_clear_failed"
    end
    if state.mode == "managed" then
        activeSlot, observedTitle, reservation = empty.index, nil, true; Save()
    end
    if guideID then
        if state.mode == "managed" then pendingLoad = { id = guideID, index = empty.index } end
        local ok = pcall(dugi.DisplayViewTabInThread, dugi, guideID, nil, true)
        if not ok then
            restoreSelection(); return false, "guide_load_failed"
        end
        NS.SelectGuideProvider("dugi", "DugiGuideSelected")
    else
        local ok = pcall(dugi.ShowLargeWindow, dugi)
        if not ok then
            restoreSelection(); return false, "chooser_unavailable"
        end
        local main = rawget(_G, "DugisMain")
        if main and main.homeTab and type(main.homeTab.Click) == "function" then main.homeTab:Click() end
    end
    Notify()
    return true, guideID and "Guide load requested." or "Guide chooser opened."
end

function Tabs.Load(id)
    local state = Common.Tabs.GetState("dugi")
    if not state then return false, "provider_unavailable" end
    local match
    for _, entry in ipairs(state.entries) do if entry.id == id and (not match or entry.active) then match = entry end end
    if match then return Common.Tabs.Run("dugi", "switch", match) end
    return Common.Tabs.OpenNew("dugi", nil, id)
end
