-- ============================================================
-- Quest and entity data
-- ============================================================
--
-- Reads quest and entity data from Questie and BtWQuests and coalesces updates
-- when provider data changes. The provider layer supplies quest and entity
-- records. Refresh callbacks run when the source data changes so consumers can
-- rebuild their own snapshots.

local NS = _G.AzerothWaypointNS
local Data = { generation = 0 }
NS.Internal.QuestData = Data
local providers, order = {}, { "questie", "btwquests" }
local names, ring, nextSlot = {}, {}, 1
local pending, allDirty, refresh = {}, false, nil
local kinds = { Npc = true, Object = true, Item = true }

function Data.Public(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

function Data.ID(value)
    value = Data.Public(value)
    return type(value) == "number" and value > 0 and value < math.huge and value % 1 == 0 and value or nil
end

function Data.Name(value)
    value = Data.Public(value)
    if type(value) ~= "string" then return end
    value = value:gsub("%s+", " "):match("^%s*(.-)%s*$")
    if value ~= "" and value ~= "Unnamed" then return value end
end

function Data.ClearNames(id)
    if id then names[id] = nil else names, ring, nextSlot = {}, {}, 1 end
end

-- ============================================================
-- Quest data providers
-- ============================================================

function Data.Register(key, provider)
    providers[key] = provider
    Data.generation = Data.generation + 1
    Data.ClearNames()
    if NS.InvalidateQuestPresentation then NS.InvalidateQuestPresentation() end
end

local function Read(provider, method, ...)
    if not provider or type(provider[method]) ~= "function" then return end
    local ok, a, b, c = pcall(provider[method], ...)
    if ok then return a, b, c end
end

-- Bound both hits and misses. Pack registration/readiness invalidates misses;
-- title resolution never loads an expansion or copies a provider's database.
function Data.GetQuestName(id)
    if not Data.ID(id) then return end
    local cached = names[id]
    if cached then return cached.name, cached.provenance end
    local name, provenance
    for _, key in ipairs(order) do
        local provider = providers[key]
        name = Data.Name(Read(provider, "GetQuestName", id))
        if name then
            provenance = provider.label; break
        end
    end
    local old = ring[nextSlot]
    if old and names[old.id] == old then names[old.id] = nil end
    cached = { id = id, name = name, provenance = provenance }
    names[id], ring[nextSlot] = cached, cached
    nextSlot = nextSlot % 256 + 1
    return name, provenance
end

local function ResolveEntity(id, context, action)
    local kind, entity = Data.Public(context.entityKind), Data.ID(context.entityID)
    local contextID = Data.ID(context.questID)
    if kinds[kind] and entity and (type(context.questID) == "nil" or contextID == id)
        and (action == "complete" or (action and Data.Public(context.action) == action)) then
        return kind, entity
    end
    local selection = NS.Internal.GuideQuestSelection
    if selection and selection.GetVerifiedQuestActor then
        local actor, name = selection.GetVerifiedQuestActor(id, action)
        if actor then return "Npc", actor, name end
    end
    if action ~= "accept" and action ~= "turnin" then return end
    for _, key in ipairs(order) do
        local category, owner, reason = Read(providers[key], "GetRoleEntity", id, action)
        if kinds[category] and Data.ID(owner) then return category, owner end
        -- An explicitly ambiguous source is not evidence for a different,
        -- lower-priority database to choose one of those recipients.
        if reason == "ambiguous" then return end
    end
end
function Data.GetFacts(id, context, action)
    local kind, entity, liveName = ResolveEntity(id, context, action)
    if not entity then return end
    local name, provenance
    for _, key in ipairs(order) do
        local provider = providers[key]
        name = Data.Name(Read(provider, "GetEntityName", kind, entity))
        if name then
            provenance = provider.label; break
        end
    end
    if not name then name, provenance = Data.Name(liveName), "quest_dialog" end
    if not name then return end
    return {
        entityKind = kind,
        entityID = entity,
        name = name,
        provenance = provenance,
        context = (action == "accept" or action == "turnin") and
            (kind == "Npc" and "Talk to " or kind == "Item" and "Use " or "Interact with ") .. name or nil
    }
end

-- ============================================================
-- Refresh scheduling
-- ============================================================

-- Provider mutations share one next-frame refresh. Ordinary presentation
-- reads have no timers, UI operations, or provider registration work.
function Data.RequestRefresh(id)
    if Data.ID(id) then pending[id] = true else allDirty = true end
    if not refresh then
        refresh = NS.Internal.Scheduling.CreateCoalescer(function()
            Data.generation = Data.generation + 1
            local invalidate = NS.InvalidateNativeOverlayQuestCaches or NS.InvalidateQuestPresentation
            if allDirty then invalidate() else for questID in pairs(pending) do invalidate(questID) end end
            for questID in pairs(pending) do pending[questID] = nil end
            allDirty = false
            if NS.ScheduleActiveQuestBackedManualRefresh then NS.ScheduleActiveQuestBackedManualRefresh("quest_data") end
            if NS.TickUpdate then NS.TickUpdate() end
        end)
    end
    refresh:Request()
end
