local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

NS.Internal = NS.Internal or {}
NS.Internal.ZygorTrackerViewer = NS.Internal.ZygorTrackerViewer or {}

local Shared = NS.Internal.ZygorTrackerViewer
local Host = {}
Shared.TrackerHost = Host

Host.NATIVE_DOCK_WARNING = "Blizzard native Tracker Viewer docking is experimental and has a known WoW 12.1 taint issue. It may produce protected-action or secret-value errors, may stop working entirely after a future WoW patch, and may be removed from AWP in favor of Kaliel's Tracker-only docking. Kaliel's Tracker is the recommended tracker."
Host.KALIEL_DOCK_STATUS = "Kaliel's Tracker is active and is AWP's recommended Tracker Viewer. It avoids the known Blizzard shared Objective Tracker and World Map taint boundary."

-- ============================================================
-- Objective tracker host detection (Blizzard vs Kaliel's Tracker)
-- and module-registration helpers.
-- ============================================================
--
-- Use each active tracker stack's standard block and line templates. The
-- Blizzard path remains native registration; Kaliel uses its addon-owned
-- templates and container.
-- Blizzard and Kaliel expose similar APIs, but Kaliel forks the mixins.
-- Module headers are constructed from Blizzard's structural template and
-- finished with KT's header mixin in tracker_module.lua. KT 8.7.x hooks its
-- header template's OnLoad path and expects a runtime-created Icon that the
-- template itself does not provide, so that template cannot be instantiated
-- safely by third-party modules.
local BLIZZ_BLOCK_TEMPLATE  = "ObjectiveTrackerAnimBlockTemplate"
local BLIZZ_HEADER_TEMPLATE = "ObjectiveTrackerModuleHeaderTemplate"
local BLIZZ_LINE_TEMPLATE   = "QuestObjectiveLineTemplate"
local KT_BLOCK_TEMPLATE     = "KT_ObjectiveTrackerAnimBlockTemplate"
local KT_LINE_TEMPLATE      = "KT_ObjectiveTrackerLineTemplate"

local function GetKalielsTrackerFrame()
    return rawget(_G, "KT_ObjectiveTrackerFrame")
end

-- KalielsTracker disables Blizzard's tracker entirely
-- When KT is loaded we MUST register with KT's tracker, not Blizzard's.
local function IsKTLoaded()
    return GetKalielsTrackerFrame() ~= nil
end

local function GetDockingSupportStatus()
    if IsKTLoaded() then
        return "kaliel", Host.KALIEL_DOCK_STATUS, false
    end
    return "blizzard", Host.NATIVE_DOCK_WARNING, true
end

local ktInitObserved = false
local ktReadyCallbacks = {}

-- The INIT signal is the primary readiness boundary. This structural check is
-- only for late-loaded AWP copies that missed the one-shot signal: KT assigns
-- its scroll child in the deferred tail of Init(), after SetHooks() has already
-- installed and propagated all of its replacement mixin methods.
local function IsKTLateInitComplete()
    local tracker = rawget(_G, "!KalielsTrackerFrame")
    local scroll = tracker and tracker.Scroll
    local child = tracker and tracker.Child
    if not scroll or not child or type(scroll.GetScrollChild) ~= "function" then
        return false
    end
    local ok, current = pcall(scroll.GetScrollChild, scroll)
    return ok and current == child
end

local function IsKTReady()
    if not IsKTLoaded() then return true end
    if ktInitObserved then return true end
    if IsKTLateInitComplete() then
        ktInitObserved = true
        return true
    end
    return false
end

local function MarkKTReady()
    if ktInitObserved then return end
    ktInitObserved = true

    local callbacks = ktReadyCallbacks
    ktReadyCallbacks = {}
    for _, callback in ipairs(callbacks) do
        pcall(callback)
    end
end

local function RegisterKTReadyCallback(callback)
    if type(callback) ~= "function" then return false end
    if IsKTReady() then
        pcall(callback)
        return true
    end
    ktReadyCallbacks[#ktReadyCallbacks + 1] = callback
    return false
end

do
    local registry = rawget(_G, "EventRegistry")
    if IsKTLoaded() and registry and type(registry.RegisterCallback) == "function" then
        local owner = {}
        pcall(registry.RegisterCallback, registry, "!KalielsTracker.INIT", function()
            MarkKTReady()
        end, owner)
    end
end

local function GetTrackerFrame()
    if IsKTLoaded() then
        return GetKalielsTrackerFrame()
    end
    return rawget(_G, "ObjectiveTrackerFrame")
end

local function GetModuleMixin()
    if IsKTLoaded() then
        return rawget(_G, "KT_ObjectiveTrackerModuleMixin") or rawget(_G, "ObjectiveTrackerModuleMixin")
    end
    return rawget(_G, "ObjectiveTrackerModuleMixin")
end

local function GetHeaderTemplate()
    return BLIZZ_HEADER_TEMPLATE
end

local function GetBlockTemplate()
    return IsKTLoaded() and KT_BLOCK_TEMPLATE or BLIZZ_BLOCK_TEMPLATE
end

local function GetLineTemplate()
    return IsKTLoaded() and KT_LINE_TEMPLATE or BLIZZ_LINE_TEMPLATE
end

local ktModuleToContainer = {}
local KTManagerAdapter = { moduleToContainerMap = ktModuleToContainer }

local function ContainerHasModule(container, frame)
    if not container or not frame then return false end
    local modules = container.modules
    if type(modules) == "table" then
        for _, existing in ipairs(modules) do
            if existing == frame then return true end
        end
    end
    return false
end

function KTManagerAdapter:GetContainerForModule(frame)
    return ktModuleToContainer[frame]
end

function KTManagerAdapter:SetModuleContainer(frame, container)
    if not frame or not container then return false end
    if container ~= GetKalielsTrackerFrame() then return false end

    local oldContainer = ktModuleToContainer[frame]
    if oldContainer and oldContainer ~= container and type(oldContainer.RemoveModule) == "function" then
        pcall(oldContainer.RemoveModule, oldContainer, frame)
    end

    ktModuleToContainer[frame] = container
    container.modules = container.modules or {}

    if not container.init and type(container.OnAdded) == "function" then
        pcall(container.OnAdded, container, 0)
    end

    if type(frame.SetContainer) == "function" then
        pcall(frame.SetContainer, frame, container)
    else
        frame.parentContainer = container
        frame:SetParent(container)
    end

    if not ContainerHasModule(container, frame) then
        table.insert(container.modules, frame)
    end

    container.needsSorting = true
    if type(container.MarkDirty) == "function" then
        pcall(container.MarkDirty, container)
    elseif type(container.Update) == "function" then
        pcall(container.Update, container)
    end
    return true
end

function KTManagerAdapter:UpdateAll()
    local container = GetKalielsTrackerFrame()
    if container and type(container.Update) == "function" then
        pcall(container.Update, container)
    end
end

local function GetManager()
    if IsKTLoaded() then
        return KTManagerAdapter
    end
    return rawget(_G, "ObjectiveTrackerManager")
end

-- ObjectiveTrackerManager:SetModuleContainer silently returns if the container
-- isn't yet in mgr.containers
-- At PLAYER_LOGIN / /reload this is often the case — the tracker manager
-- hasn't completed its own init yet. The coordinator retries until the
-- registration sticks.
local function IsActuallyRegistered(mgr, frame, container)
    if not mgr or not frame or not container then return false end
    if type(mgr.GetContainerForModule) ~= "function" then return false end
    local ok, current = pcall(mgr.GetContainerForModule, mgr, frame)
    return ok and current == container
end

local function TryRegisterOnce(mgr, frame, container)
    if IsActuallyRegistered(mgr, frame, container) then return true end
    if type(mgr.SetModuleContainer) ~= "function" then return false end
    pcall(mgr.SetModuleContainer, mgr, frame, container)
    return IsActuallyRegistered(mgr, frame, container)
end

Host.IsKTLoaded = IsKTLoaded
Host.GetDockingSupportStatus = GetDockingSupportStatus
Host.IsKTReady = IsKTReady
Host.RegisterKTReadyCallback = RegisterKTReadyCallback
Host.GetTrackerFrame = GetTrackerFrame
Host.GetModuleMixin = GetModuleMixin
Host.GetHeaderTemplate = GetHeaderTemplate
Host.GetBlockTemplate = GetBlockTemplate
Host.GetLineTemplate = GetLineTemplate
Host.GetManager = GetManager
Host.IsActuallyRegistered = IsActuallyRegistered
Host.TryRegisterOnce = TryRegisterOnce
