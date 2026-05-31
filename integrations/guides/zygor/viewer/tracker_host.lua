local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

NS.Internal = NS.Internal or {}
NS.Internal.ZygorTrackerViewer = NS.Internal.ZygorTrackerViewer or {}

local Shared = NS.Internal.ZygorTrackerViewer
local Host = {}
Shared.TrackerHost = Host

-- ============================================================
-- Objective tracker host detection (Blizzard vs Kaliel's Tracker)
-- and module-registration helpers.
-- ============================================================
--
-- Use the active tracker stack's standard templates.
-- Blizzard and Kaliel expose similar APIs, but Kaliel forks the mixins.
local BLIZZ_BLOCK_TEMPLATE  = "ObjectiveTrackerAnimBlockTemplate"
local BLIZZ_HEADER_TEMPLATE = "ObjectiveTrackerModuleHeaderTemplate"
local BLIZZ_LINE_TEMPLATE   = "QuestObjectiveLineTemplate"
local KT_BLOCK_TEMPLATE     = "KT_ObjectiveTrackerAnimBlockTemplate"
local KT_HEADER_TEMPLATE    = "KT_ObjectiveTrackerModuleHeaderTemplate"
local KT_LINE_TEMPLATE      = "KT_ObjectiveTrackerLineTemplate"

local function GetKalielsTrackerFrame()
    return rawget(_G, "KT_ObjectiveTrackerFrame")
end

-- KalielsTracker disables Blizzard's tracker entirely
-- When KT is loaded we MUST register with KT's tracker, not Blizzard's.
local function IsKTLoaded()
    return GetKalielsTrackerFrame() ~= nil
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
    return IsKTLoaded() and KT_HEADER_TEMPLATE or BLIZZ_HEADER_TEMPLATE
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
Host.GetTrackerFrame = GetTrackerFrame
Host.GetModuleMixin = GetModuleMixin
Host.GetHeaderTemplate = GetHeaderTemplate
Host.GetBlockTemplate = GetBlockTemplate
Host.GetLineTemplate = GetLineTemplate
Host.GetManager = GetManager
Host.IsActuallyRegistered = IsActuallyRegistered
Host.TryRegisterOnce = TryRegisterOnce
