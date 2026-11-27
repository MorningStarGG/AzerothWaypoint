-- ============================================================
-- Tracker host selection
-- ============================================================
--
-- Selects the active tracker host and adapts its module registration and
-- ordering for guide viewers.

local NS                            = _G.AzerothWaypointNS

---@diagnostic disable: need-check-nil, undefined-field

NS.Internal                         = NS.Internal or {}
NS.Internal.GuideTrackerViewer      = NS.Internal.GuideTrackerViewer or {}

local Daylight                      = NS.Internal.GuideTrackerViewer.DaylightHost
local Host                          = {}
local Ellesmere                     = NS.Internal.GuideTrackerViewer.EllesmereHost
local Questie                       = NS.Internal.GuideTrackerViewer.QuestieHost
local GW2UI                         = NS.Internal.GuideTrackerViewer.GW2UIHost
NS.Internal.GuideTrackerViewer.Host = Host

Host.NATIVE_DOCK_WARNING            =
"Blizzard tracker docking is experimental and can cause blocked actions or other UI errors. See Tracker Viewer in AWP Help for supported dedicated quest trackers."
Host.KALIEL_DOCK_STATUS             =
"Kaliel's Tracker is active. Your guide Viewers use Kaliel's tracker layout."

-- ============================================================
-- Objective tracker host detection (Blizzard vs Kaliel's Tracker)
-- and module-registration helpers.
-- ============================================================
--
-- Use each active tracker stack's standard block and line templates. The
-- Blizzard path remains native registration, Kaliel uses its addon-owned
-- templates and container.
-- Blizzard and Kaliel expose similar APIs, but Kaliel forks the mixins.
-- Module headers are constructed from Blizzard's structural template and
-- finished with KT's header mixin in tracker_module.lua. KT 8.7.x hooks its
-- header template's OnLoad path and expects a runtime-created Icon that the
-- template itself does not provide, so that template cannot be instantiated
-- safely by third-party modules.
local BLIZZ_BLOCK_TEMPLATE          = "ObjectiveTrackerAnimBlockTemplate"
local BLIZZ_HEADER_TEMPLATE         = "ObjectiveTrackerModuleHeaderTemplate"
local BLIZZ_LINE_TEMPLATE           = "QuestObjectiveLineTemplate"
local KT_BLOCK_TEMPLATE             = "KT_ObjectiveTrackerAnimBlockTemplate"
local KT_LINE_TEMPLATE              = "KT_ObjectiveTrackerLineTemplate"

local function GetKalielsTrackerFrame()
    return rawget(_G, "KT_ObjectiveTrackerFrame")
end

-- KalielsTracker disables Blizzard's tracker entirely
-- When KT is loaded we MUST register with KT's tracker, not Blizzard's.
local function IsKTLoaded()
    return GetKalielsTrackerFrame() ~= nil
end

local function GetCustomHost()
    if Ellesmere and Ellesmere.IsSelected() then return Ellesmere, "ellesmere" end
    if Daylight and Daylight.IsSelected() then return Daylight, "daylight" end
    if Questie and Questie.IsSelected() then return Questie, "questie" end
    if GW2UI and GW2UI.IsSelected() then return GW2UI, "gw2ui" end
    -- Daylight's native suppression persists during the handoff to Questie.
    if Daylight and Daylight.BlocksBlizzardDocking and Daylight.BlocksBlizzardDocking() then return Daylight, "daylight" end
end

local function IsBlizzardHost()
    return not IsKTLoaded() and not GetCustomHost()
end

local function GetHostID()
    if IsKTLoaded() then return "kaliel" end
    local _, id = GetCustomHost()
    return id or "blizzard"
end

local function GetDockingSupportStatus()
    local id = GetHostID()
    if id == "kaliel" then
        return "kaliel", Host.KALIEL_DOCK_STATUS, false
    end
    if id == "ellesmere" then
        return "ellesmere",
            "Ellesmere UI's custom tracker hosts the guide modules in its shared scrolling area. AWP manages the combined layout without registering guide modules with Blizzard's tracker.",
            false
    end
    if id == "daylight" then
        local _, _, reason = Daylight.GetStatus()
        return "daylight",
            reason or
            "DaylightUI hosts the guide Viewers in its shared scrolling tracker on WoW Forever, without Blizzard module registration.",
            false
    end
    if id == "questie" then
        local _, reason = Questie.GetAvailability()
        return "questie",
            reason or
            "Guide Viewers share Questie's scrolling tracker on WoW Forever. With no tracked quests, enable Questie's Always Show Tracker option to keep the guides visible.",
            false
    end
    if id == "gw2ui" then
        local _, reason = GW2UI.GetAvailability()
        return "gw2ui", reason or "Guide Viewers share GW2 UI's scrolling tracker above its quests.", false
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

-- ============================================================
-- Host readiness
-- ============================================================

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
    local custom = GetCustomHost()
    if custom then return custom.GetContainer() end
    return rawget(_G, "ObjectiveTrackerFrame")
end

local hostLabels = {
    kaliel = "Kaliel's Tracker",
    ellesmere = "Ellesmere UI Quest Tracker",
    daylight = "DaylightUI Quest Tracker",
    questie = "Questie Tracker",
    gw2ui = "GW2 UI Quest Tracker",
    blizzard = "Blizzard Objective Tracker",
}
local hostSupport = {
    kaliel = "custom tracker",
    ellesmere = "custom tracker, combined guide layout",
    daylight = "custom tracker, shared scrolling on Forever",
    questie = "custom tracker, shared scrolling on Forever",
    gw2ui = "custom tracker, shared scrolling on Retail and Forever",
    blizzard = "experimental, known taint risk",
}

local function ReadFrame(frame, key, expectedType)
    local method = frame and frame[key]
    if type(method) ~= "function" then return end
    local ok, value = pcall(method, frame)
    if ok and type(value) == expectedType and not (issecretvalue and issecretvalue(value)) then return value end
end

function NS.GetObjectiveTrackerVisibilityStatus()
    local host = GetHostID()
    local frame, support
    if host == "ellesmere" then
        frame = Ellesmere.GetRoot()
    elseif host == "daylight" then
        frame = Daylight.GetRoot()
    elseif host == "questie" then
        frame = Questie.GetRoot()
        local _, reason = Questie.GetAvailability()
        support = reason
    elseif host == "gw2ui" then
        frame = GW2UI.GetRoot()
        local _, reason = GW2UI.GetAvailability()
        support = reason
    else
        frame = GetTrackerFrame()
    end
    local shown = ReadFrame(frame, "IsShown", "boolean")
    local visible = ReadFrame(frame, "IsVisible", "boolean")
    local alpha = ReadFrame(frame, "GetEffectiveAlpha", "number") or ReadFrame(frame, "GetAlpha", "number")
    local hidden = shown == false or visible == false
    local transparent = alpha ~= nil and alpha <= 0.05
    return {
        id = host,
        host = hostLabels[host],
        support = support or hostSupport[host],
        frame = frame,
        exists = frame ~= nil,
        shown = shown == true,
        visible = visible == true,
        hardHidden = hidden,
        alpha = alpha,
        transparent = transparent,
        visibility = not frame and "missing" or hidden and "hidden" or visible and "visible" or "unknown",
        opacity = alpha == nil and "unknown" or transparent and "transparent" or "normal"
    }
end

local warnedHidden = {}
function Host.WarnIfHidden()
    local id = GetHostID()
    if id == "questie" or warnedHidden[id] then return end
    local status = NS.GetObjectiveTrackerVisibilityStatus()
    if status.hardHidden then
        warnedHidden[id] = true
        NS.Msg("|cffffcc00AzerothWaypoint:|r Tracker Viewer has guide steps ready, but " .. status.host .. " is hidden.")
    end
end

-- ============================================================
-- Header templates and module storage
-- ============================================================

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
    local custom = GetCustomHost()
    if custom then return custom end
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
    local order = NS.GetGuideTrackerViewerSortOrder and NS.GetGuideTrackerViewerSortOrder(frame._awpGuideProvider)
    if order then frame.uiOrder = order end
    local ok, result, reason = pcall(mgr.SetModuleContainer, mgr, frame, container)
    if not ok then
        if mgr == Ellesmere or mgr == Daylight or mgr == Questie or mgr == GW2UI then mgr.NoteAttachmentFailure(result) end
        return false, tostring(result)
    end
    if result == false and reason then return false, reason end
    return IsActuallyRegistered(mgr, frame, container)
end

local deferredOrder

-- ============================================================
-- Guide ordering and registration
-- ============================================================

function Host.RefreshGuideOrder()
    local manager, container = GetManager(), GetTrackerFrame()
    if not manager or not container or type(container.modules) ~= "table" then return end
    if (IsBlizzardHost() and InCombatLockdown()) or (manager.IsLayoutLocked and manager.IsLayoutLocked()) then
        if not deferredOrder then
            deferredOrder = CreateFrame("Frame")
            deferredOrder:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                Host.RefreshGuideOrder()
            end)
        end
        deferredOrder:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    local order, changed = NS.GetGuideTrackerViewerOrder(), false
    for _, module in ipairs(container.modules) do
        local rank = module._awpGuideProvider and NS.GetGuideTrackerViewerSortOrder(module._awpGuideProvider, order)
        if rank and module.uiOrder ~= rank then
            module.uiOrder, changed = rank, true
        end
    end
    if not changed then return end
    if IsKTLoaded() or IsBlizzardHost() then container.needsSorting = true end
    if type(container.MarkDirty) == "function" then
        container:MarkDirty()
    elseif type(manager.UpdateAll) == "function" then
        manager:UpdateAll()
    end
end

Host.IsKTLoaded = IsKTLoaded
Host.IsBlizzardHost = IsBlizzardHost
function Host.IsEllesmereHost() return GetHostID() == "ellesmere" end

function Host.IsDaylightHost() return GetHostID() == "daylight" end

function Host.GetAttachmentAvailability()
    local id = GetHostID()
    if id == "daylight" then
        local ready, reason, waiting = Daylight.GetAvailability()
        if not ready and waiting then Daylight.WaitForReady() end
        return ready, reason, waiting
    end
    if id == "questie" then return Questie.GetAvailability() end
    if id == "gw2ui" then return GW2UI.GetAvailability() end
    return true
end

function Host.RegisterReadyCallback(callback)
    if Daylight then Daylight.RegisterReadyCallback(callback) end
    if Questie and Questie.RegisterReadyCallback then Questie.RegisterReadyCallback(callback) end
    if GW2UI then GW2UI.RegisterReadyCallback(callback) end
    return RegisterKTReadyCallback(callback)
end

Host.GetHostID = GetHostID
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
