-- ============================================================
-- DaylightUI tracker host
-- ============================================================
--
-- Controls how AWP guide sections attach to DaylightUI's tracker and share its
-- scroll range.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local Custom = Common.CustomHost
local Host = { moduleToContainerMap = {} }
Common.DaylightHost = Host

-- Named Lua hooks use the public plugin API. The shared scroll-owner bridge
-- preserves native viewport methods while routing external scroll requests
-- through Daylight's logical bounds and owner.
local container, active, failure, failedNamespace
local loginPending
local capabilities = {
    Tracker = { "Wanted", "Queue", "SetHeight", "RefreshEdges", "PinnedHeight", "PlaceControls" },
    Layout = { "Build" },
    Animate = { "State", "place" },
    Scroll = { "Move" },
}
local callbacks = {}
local counters = { requested = 0, coalesced = 0, layouts = 0 }
Host.counters = counters

local function Locked() return InCombatLockdown and InCombatLockdown() == true end

local function GetDaylight()
    if not NS.IsWoWForever or not NS.IsWoWForever() then return end
    return rawget(_G, "DaylightUI")
end

local function GetQuestsModule(dui)
    if dui and type(dui.GetModule) == "function" then return dui:GetModule("Quests") end
end

function Host.BlocksBlizzardDocking()
    local dui = GetDaylight()
    return dui ~= nil and dui.questsOwnTracker == true
end

function Host.IsSelected()
    local dui = GetDaylight()
    if not dui or dui.questsOwnTracker ~= true then return false end
    local mod = GetQuestsModule(dui)
    local tracker = mod and mod.ns and mod.ns.Tracker
    -- Questie can be selected even after Daylight has disabled Blizzard's manager.
    return not tracker or type(tracker.Wanted) ~= "function" or tracker.Wanted() == true
end

local function Resolve()
    local dui = GetDaylight()
    if not dui or type(dui.GetModule) ~= "function" then return nil, "DaylightUI is unavailable." end
    local mod = GetQuestsModule(dui)
    if not mod or not mod.enabled or not mod.ns then
        if loginPending or not dui.loggedIn then return nil, "Waiting for DaylightUI's tracker initialization.", true end
        return nil, "DaylightUI's Quests module is inactive."
    end
    local ns, api = mod.ns, dui.API
    if failedNamespace == ns then return nil, failure end
    if not api or type(api.For) ~= "function" then return nil, "DaylightUI's plugin API is unavailable." end
    for name, methods in pairs(capabilities) do
        local object = ns[name]
        for _, method in ipairs(methods) do
            if type(object) ~= "table" or type(object[method]) ~= "function" then
                return nil, "DaylightUI tracker capability missing: " .. name .. "." .. method
            end
        end
    end
    if not ns.Tracker.Wanted() then
        return nil, "DaylightUI selected Questie's tracker. Enable Questie's tracker and reload if it does not appear.",
            true
    end
    if not ns.Tracker.built then return nil, "Waiting for DaylightUI's tracker initialization.", true end
    if not ns.Tracker.content or not ns.Tracker.view or not ns.Scroll or not ns.Tracker.frames then
        return nil, "DaylightUI's tracker layout is incomplete."
    end
    if not mod.db or type(mod.db.maxHeight) ~= "number" then return nil,
            "DaylightUI's tracker height setting is unavailable." end
    if ns.Tracker.view:IsProtected() then return nil, "DaylightUI's tracker viewport is protected." end
    return ns, nil, false, api.For("AzerothWaypoint"), mod
end

-- ============================================================
-- Host readiness
-- ============================================================

function Host.GetAvailability()
    if Locked() then return false, "Waiting for combat to end.", true end
    local ns, why, waiting = Resolve()
    return ns ~= nil, why, waiting
end

local function Notify()
    for index = 1, #callbacks do callbacks[index]() end
end

function Host.RegisterReadyCallback(callback) callbacks[#callbacks + 1] = callback end

local readyHandle
function Host.WaitForReady()
    if readyHandle or not Host.IsSelected() then return end
    local dui = GetDaylight()
    if not dui then return end
    local mod = GetQuestsModule(dui)
    local ns = mod and mod.ns
    local api = dui.API and dui.API.For and dui.API.For("AzerothWaypoint")
    if not ns or not ns.Tracker or ns.Tracker.built or type(ns.Tracker.Build) ~= "function"
        or not api or type(api.Hook) ~= "function" then
        return
    end
    readyHandle = api.Hook(ns.Tracker, "Build", function()
        local handle = readyHandle
        readyHandle = nil
        if handle then api.Unhook(handle) end
        Notify()
    end)
end

function Host.GetRoot()
    local mod = GetQuestsModule(GetDaylight())
    return mod and mod.ns and mod.ns.Tracker and mod.ns.Tracker.holder
end

-- ============================================================
-- Viewport and scroll ownership
-- ============================================================

local function AttachScroll(s)
    local view, scroll = s.ns.Tracker.view, s.ns.Scroll
    s.releaseScroll = Custom.RegisterScrollOwner(view, {
        GetRange = function()
            local maximum = s.module.db and s.module.db.maxHeight
            if type(maximum) ~= "number" then return 0 end
            local total = s.ns.Tracker.contentHeight or s.ns.Tracker.content:GetHeight()
            -- Scroll.Set uses its configured target while the viewport glides.
            return math.max(0, total - maximum)
        end,
        GetOffset = function() return scroll.offset end,
        SetOffset = function(position)
            if scroll.bar then scroll.bar.Stop() end
            scroll.Move(position)
        end,
        GetViewport = function()
            local top, bottom = view:GetTop(), view:GetBottom()
            if not top or not bottom then return end
            -- Match Daylight's row clipping: the header occupies this inset
            -- only after scrolling. Read its applied inset, including glides.
            local inset = scroll.offset > 0 and scroll.topInset or 0
            return math.max(bottom, top - inset), bottom
        end,
    })
    if view:GetVerticalScroll() ~= scroll.offset then scroll.Move(scroll.offset) end
end

local function Stop()
    local s = active
    if not s then return end
    active = nil
    s.releaseScroll()
    for index = #s.handles, 1, -1 do s.api.Unhook(s.handles[index]) end
    if s.ns.Tracker.controls then s.ns.Tracker.PlaceControls() end
    container:Hide()
    container:SetParent(UIParent)
    for index = #container.modules, 1, -1 do
        local module = container.modules[index]
        Host.moduleToContainerMap[module] = nil
        module.parentContainer, module._awpDaylightCollapsePending = nil, nil
        container.modules[index] = nil
    end
    -- Recompute through Daylight, including native scroll clamping and items.
    s.ns.Tracker.Queue(false, false)
end

local function Flush()
    local s = active
    if not s then return end
    s.scheduled = false
    if Locked() then
        s.deferred = true; return
    end
    if #container.modules == 0 then
        Stop(); return
    end
    s.scheduled = true
    for _, module in ipairs(container.modules) do
        if module._awpDaylightCollapsePending then
            module._awpDaylightCollapsePending = nil
            module._awpDaylightOriginalToggle(module)
        end
    end
    s.scheduled = false
    s.dirty = true
    s.ns.Tracker.Queue(false, false)
end

-- ============================================================
-- Scheduling layout
-- ============================================================

local function Schedule()
    counters.requested = counters.requested + 1
    local s = active
    if not s then return end
    if s.scheduled then
        counters.coalesced = counters.coalesced + 1; return
    end
    if Locked() then
        s.deferred = true; return
    end
    s.scheduled = true
    C_Timer.After(0, function() if active == s then Flush() end end)
end

function Host.GetContainer()
    if container then return container end
    container = CreateFrame("Frame", "AwpDaylightGuideContainer", UIParent)
    container:Hide()
    container.modules = {}
    container.MarkDirty, container.ForceExpand = Schedule, Schedule
    container.IsCollapsed = function() return false end
    container.RemoveModule = function(_, module) Host.RemoveModule(module) end
    return container
end

local function Start()
    if active then return true end
    if Locked() then return false, "Waiting for combat to end." end
    local ns, why, _, api, module = Resolve()
    if not ns then return false, why end
    if not api or type(api.Wrap) ~= "function" or type(api.Hook) ~= "function" or type(api.Unhook) ~= "function" then
        return false, "DaylightUI's named hook API is unavailable."
    end
    local s = { ns = ns, api = api, module = module, handles = {}, height = 0, dirty = true }
    active = s
    AttachScroll(s)
    local parent = Host.GetContainer()
    parent:SetParent(ns.Tracker.content)
    parent:ClearAllPoints()
    parent:SetPoint("TOPLEFT")

    local function Add(handle)
        if not handle then error("DaylightUI declined an AWP tracker hook.") end
        s.handles[#s.handles + 1] = handle
    end
    local function ReserveGuideSpace(options, blocks, height, ...)
        if active ~= s then return blocks, height, ... end
        if type(blocks) ~= "table" or type(height) ~= "number" or type(options) ~= "table"
            or type(options.width) ~= "number" then
            failure, failedNamespace = "DaylightUI's layout result is incompatible.", ns
            s.height = 0
            parent:Hide()
            C_Timer.After(0, function() if active == s then Stop() end end)
            return blocks, height, ...
        end
        if not Locked() and (s.dirty or s.width ~= options.width) then
            s.width = options.width
            s.height = Custom.Layout(parent, options.width)
            s.dirty = false
            counters.layouts = counters.layouts + 1
        end
        -- Daylight supplies fresh rows. Shift their positions and forward its
        -- other results, including the ready-quest membership used in combat.
        if s.height > 0 then
            for index = 1, #blocks do blocks[index].y = blocks[index].y + s.height end
        end
        return blocks, height + s.height, ...
    end
    local ok, err = pcall(function()
        Add(api.Wrap(ns.Layout, "Build", function(original, snap, options, measure)
            return ReserveGuideSpace(options, original(snap, options, measure))
        end))
        Add(api.Wrap(ns.Tracker, "PinnedHeight", function(original)
            if active ~= s or s.height == 0 then return original() end
            local header = ns.Tracker.frames[ns.Tracker.PIN]
            if header and header:IsShown() and ns.Scroll.offset >= ns.Animate.State(header).y then
                return header:GetHeight()
            end
            return 0
        end))
        Add(api.Wrap(ns.Animate, "place", function(original, frame, y, dx, alpha)
            if active == s and s.height > 0 and frame == ns.Tracker.frames[ns.Tracker.PIN]
                and ns.Scroll.offset >= y then
                -- Native placement performs pinning when given origin zero.
                -- Keep Animate.State's logical origin intact for scrolling back.
                return original(frame, 0, dx, alpha)
            end
            return original(frame, y, dx, alpha)
        end))
        Add(api.Hook(ns.Tracker, "RefreshEdges", function()
            if active ~= s or s.height == 0 then return end
            local header = ns.Tracker.frames[ns.Tracker.PIN]
            if header then
                local st = ns.Animate.State(header)
                ns.Animate.place(header, st.y, st.dx, st.a)
            end
        end))
        Add(api.Hook(ns.Tracker, "SetHeight", function()
            if active == s and #parent.modules > 0 then parent:Show() end
        end))
        Add(api.Hook(ns.Tracker, "PlaceControls", function()
            if active ~= s or s.height <= 0 then return end
            local tracker = ns.Tracker
            local header, controls = tracker.frames[tracker.PIN], tracker.controls
            -- With no quest heading, Daylight's filters use the viewport's
            -- first line. Keep that line free for the first guide module.
            if controls and (not header or not header:IsShown()) then
                controls:ClearAllPoints()
                controls:SetPoint("BOTTOMRIGHT", tracker.view, "TOPRIGHT", -6, 4)
            end
        end))
    end)
    if not ok then
        Stop()
        return false, tostring(err)
    end
    return true
end

-- ============================================================
-- Module attachment and refresh
-- ============================================================

function Host:GetContainerForModule(module) return self.moduleToContainerMap[module] end

function Host:SetModuleContainer(module, target)
    if target ~= Host.GetContainer() then return false end
    local ok, why = Start()
    if not ok then
        failure = why; return false, why
    end
    Custom.Add(self, target, module)
    if type(module.ToggleCollapsed) == "function" and not module._awpDaylightOriginalToggle then
        local original = module.ToggleCollapsed
        module._awpDaylightOriginalToggle = original
        module.ToggleCollapsed = function(self)
            if Host.moduleToContainerMap[self] and Locked() then
                self._awpDaylightCollapsePending = not self._awpDaylightCollapsePending
                Schedule()
                return
            end
            return original(self)
        end
    end
    failure = nil
    Schedule()
    return true
end

function Host.RemoveModule(module)
    if not container then return end
    module._awpDaylightCollapsePending = nil
    Custom.Remove(Host, container, module)
    Schedule()
end

function Host.UpdateAll() Schedule() end

function Host.NoteAttachmentFailure(reason) failure = tostring(reason) end

function Host.GetStatus()
    local ready, why = Host.GetAvailability()
    return active and "attached" or (ready and "ready" or "waiting"),
        container and #container.modules or 0, failure or why
end

local lastReady, lastReason, lastSelected
local function RefreshHost()
    local selected, wasActive = Host.IsSelected(), active ~= nil
    local wasSelected = lastSelected
    if active and not Locked() then
        if not selected or Resolve() ~= active.ns then
            Stop()
        elseif active.deferred then
            active.deferred = nil
            Schedule()
        end
    end
    local ready, why = Host.GetAvailability()
    local changed = ready ~= lastReady or why ~= lastReason or selected ~= lastSelected or wasActive and not active
    lastReady, lastReason, lastSelected = ready, why, selected
    if changed and (selected or wasSelected or wasActive) then Notify() end
end

local readyEventsInstalled = false
local function InstallReadyEvents()
    if readyEventsInstalled then return end
    local dui = GetDaylight()
    if not dui then return end
    local api = dui.API and dui.API.For and dui.API.For("AzerothWaypoint")
    if not api or type(api.On) ~= "function" then return end
    readyEventsInstalled = true
    loginPending = not dui.loggedIn
    api.On("Login", function()
        loginPending = nil
        RefreshHost()
    end)
    api.On("StyleChanged", RefreshHost)
    api.On("SettingChanged", function(scope) if scope == "Quests" then RefreshHost() end end)
end

if NS.IsWoWForever and NS.IsWoWForever() and CreateFrame then
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_LOGIN")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("ADDON_LOADED")
    events:SetScript("OnEvent", function(_, event, addon)
        if event == "ADDON_LOADED" and addon ~= "DaylightUI" and addon ~= "DaylightUI_Quests" then return end
        InstallReadyEvents()
        RefreshHost()
    end)
    InstallReadyEvents()
end
