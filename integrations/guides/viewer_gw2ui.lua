-- ============================================================
-- GW2 UI tracker host
-- ============================================================
--
-- Attaches AWP guide modules to GW2 UI's tracker and keeps the guide sections
-- inside its scroll range.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local Custom = Common.CustomHost
local Host = { moduleToContainerMap = {}, counters = { layouts = 0, coalesced = 0 } }
Common.GW2UIHost = Host

local container, active, failure
local callbacks, hooked = {}, {}
local loginComplete, wakeAfterCombat = false, false

local function GetGW() return rawget(_G, "GW2_ADDON") end
local function Locked() return InCombatLockdown and InCombatLockdown() == true end
function Host.IsLayoutLocked()
    if not Locked() then return false end
    wakeAfterCombat = true
    return true
end

function Host.GetRoot() return rawget(_G, "GwQuestTracker") end

function Host.IsSelected()
    local gw = GetGW()
    if not gw then return false end
    if Host.GetRoot() then return true end
    local options = gw.settings and gw.settings.objectives
    return not loginComplete and options and options.enabled == true
        and type(gw.LoadObjectivesTracker) == "function"
        and (not gw.ShouldBlockIncompatibleAddon or not gw.ShouldBlockIncompatibleAddon("Objectives"))
end

local function Resolve()
    local gw, root = GetGW(), Host.GetRoot()
    if not root then return nil, "Waiting for GW2 UI's quest tracker.", not loginComplete end
    local scroll = root.ScrollFrame
    local child = scroll and scroll.Child
    local sections = gw and gw.QuestTrackerScrollableContainer
    if not child or not scroll.GetScrollChild or scroll:GetScrollChild() ~= child
        or type(sections) ~= "table" or type(root.LayoutChanged) ~= "function"
        or type(root.AdjustItemButtonPositions) ~= "function"
        or type(gw.ApplyObjectivesTrackerModuleOrder) ~= "function" or not hooksecurefunc
        or type(gw.ScrollObjectivesTrackerToContainer) ~= "function"
        or type(gw.GetObjectivesScrollViewport) ~= "function"
        or type(scroll.gwScroll) ~= "number" or type(scroll.gwStickyInset) ~= "number"
        or type(scroll.maxScroll) ~= "number" or scroll:IsProtected()
        or (root.IsForbidden and root:IsForbidden()) then
        return nil, "GW2 UI's quest tracker layout is incompatible."
    end
    return root, nil, false, child, sections, gw
end

function Host.GetAvailability()
    if Host.IsLayoutLocked() then return false, "Waiting for combat to end.", true end
    local root, reason, waiting = Resolve()
    return root ~= nil, reason, waiting
end

-- ============================================================
-- Anchoring and scrolling
-- ============================================================

-- GW anchors scrolling sections in a chain and sums their heights. Maintain
-- that chain on insertion, removal, and native reorder.
local function Anchor(section, relative, relativePoint)
    local point, previous, anchor, x, y = section:GetPoint()
    if section:GetNumPoints() == 1 and point == "TOPRIGHT" and previous == relative
        and anchor == relativePoint and x == 0 and y == 0 then
        return false
    end
    section:ClearAllPoints()
    section:SetPoint("TOPRIGHT", relative, relativePoint)
    return true
end

local function PositionSection(state, remove)
    local sections = state.sections
    local index
    for i, section in ipairs(sections) do
        if section == container then
            index = i; break
        end
    end
    local changed = remove or index ~= 1
    if changed then
        if index then table.remove(sections, index) end
        if not remove then table.insert(sections, 1, container) end
    end
    for i, section in ipairs(sections) do
        if Anchor(section, sections[i - 1] or state.child, i == 1 and "TOPRIGHT" or "BOTTOMRIGHT") then changed = true end
    end
    return changed
end

local function RefreshGeometry(state)
    state.root:LayoutChanged()
    state.root:AdjustItemButtonPositions()
end

local function AttachScroll(state, gw)
    local scroll, child = state.root.ScrollFrame, state.child
    local position = 0
    -- GW's scroll-to-target helper consumes only GetTop. Supply the requested
    -- content position without creating a frame or duplicating its private
    -- sticky-header, indicator and item-button updates. Reuse this target.
    local target = {
        GetTop = function()
            local top = child:GetTop()
            return top and top - position
        end
    }
    state.releaseScroll = Custom.RegisterScrollOwner(scroll, {
        -- The frame offset includes the stuck header, GW's logical position
        -- does not. Convert at the boundary, using the inset before the move.
        GetRange = function() return scroll.maxScroll + scroll.gwStickyInset end,
        GetOffset = function() return scroll.gwScroll + scroll.gwStickyInset end,
        SetOffset = function(offset)
            position = math.max(0, offset - scroll.gwStickyInset)
            gw.ScrollObjectivesTrackerToContainer(target)
        end,
        GetViewport = function()
            local top = state.root:GetTop()
            if not top then return end
            local first, last = gw.GetObjectivesScrollViewport()
            return top - first, top - last
        end,
    })
end

-- ============================================================
-- Layout and invalidation
-- ============================================================

local function Flush()
    local state = active
    if not state then return end
    if Locked() then
        state.deferred = true; return
    end
    if #container.modules == 0 then
        active = nil
        state.releaseScroll()
        PositionSection(state, true)
        container:Hide()
        container:ClearAllPoints()
        container:SetParent(UIParent)
        RefreshGeometry(state)
        return
    end
    state.flushing = true
    for _, module in ipairs(container.modules) do
        if module._awpGW2UICollapsePending then
            module._awpGW2UICollapsePending = nil
            module:ToggleCollapsed()
        end
    end
    local changed = false
    if state.reanchor then
        state.reanchor = nil
        changed = PositionSection(state)
    end
    local width = state.root:GetWidth()
    if width > 0 and (state.dirty or state.width ~= width) then
        state.width, state.dirty = width, nil
        local height = Custom.Layout(container, width)
        if height > 0 then container:SetHeight(height) end
        changed = changed or state.height ~= height
        state.height = height
        Host.counters.layouts = Host.counters.layouts + 1
    end
    state.flushing = nil
    if changed then RefreshGeometry(state) end
end

local queue = NS.Internal.Scheduling.CreateCoalescer(Flush)
local function Schedule()
    local state = active
    if not state or state.flushing then return end
    if Locked() then
        state.deferred = true; return
    end
    if not queue:Request() then Host.counters.coalesced = Host.counters.coalesced + 1 end
end

local function MarkDirty()
    if active then
        active.dirty = true; Schedule()
    end
end

function Host.GetContainer()
    if container then return container end
    container = CreateFrame("Frame", "AwpGW2UIGuideContainer", UIParent)
    container:Hide()
    container.modules = {}
    container.IsCollapsed = function() return false end
    -- GW's auto-collapse visits every scrolling section. Guide collapse is
    -- controlled independently through the individual AWP module headers.
    container.SetCollapsed = function() end
    container.MarkDirty, container.ForceExpand = MarkDirty, MarkDirty
    container.RemoveModule = function(_, module)
        if Host.moduleToContainerMap[module] ~= container then return end
        module._awpGW2UICollapsePending = nil
        Custom.Remove(Host, container, module)
        MarkDirty()
    end
    container.DeferModuleCollapse = function(_, module)
        if not Locked() then return false end
        module._awpGW2UICollapsePending = not module._awpGW2UICollapsePending
        Schedule()
        return true
    end
    return container
end

function Host:GetContainerForModule(module) return self.moduleToContainerMap[module] end

function Host:SetModuleContainer(module, target)
    if target ~= Host.GetContainer() or Locked() then return false end
    if not active then
        local root, reason, _, child, sections, gw = Resolve()
        if not root or not gw then return false, reason end
        for _, section in ipairs(sections) do
            if section:GetParent() ~= child then return false, "GW2 UI's scrolling sections have a different parent." end
        end
        if not hooked[gw] then
            hooksecurefunc(gw, "ApplyObjectivesTrackerModuleOrder", function()
                if active then
                    active.reanchor = true; Schedule()
                end
            end)
            hooked[gw] = true
        end
        if not hooked[root] then
            root:HookScript("OnSizeChanged", function(self, width)
                if active and active.root == self and active.width ~= width then Schedule() end
            end)
            hooked[root] = true
        end
        active = { root = root, child = child, sections = sections, reanchor = true }
        AttachScroll(active, gw)
        target:SetParent(child)
        target:Show()
    end
    Custom.Add(self, target, module)
    failure = nil
    MarkDirty()
    return true
end

function Host.UpdateAll() MarkDirty() end

function Host.NoteAttachmentFailure(reason) failure = tostring(reason) end

function Host.GetStatus()
    if not Host.IsSelected() then return "inactive", 0 end
    local ready, reason, waiting = Resolve()
    return active and "attached" or (ready and "ready" or waiting and "waiting" or "unavailable"),
        container and #container.modules or 0, failure or reason
end

function Host.RegisterReadyCallback(callback) callbacks[#callbacks + 1] = callback end

local function Notify()
    for _, callback in ipairs(callbacks) do callback() end
end

local readyQueue = NS.Internal.Scheduling.CreateCoalescer(Notify)
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_LOGIN" then
        loginComplete = true
        if GetGW() then readyQueue:Request() end
    elseif event == "ADDON_LOADED" and addon == "GW2_UI" then
        readyQueue:Request()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if active and active.deferred then
            active.deferred = nil; Schedule()
        end
        if wakeAfterCombat then
            wakeAfterCombat = false; readyQueue:Request()
        end
    end
end)
