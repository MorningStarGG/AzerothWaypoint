-- ============================================================
-- External waypoint sources
-- ============================================================
--
-- Registers external waypoint sources and retains their metadata when AWP
-- adopts a waypoint.

local NS = _G.AzerothWaypointNS

NS.Internal = NS.Internal or {}

local registry = NS.Internal.ExternalWaypointSources or {
    byKey = {},
    order = {},
}
NS.Internal.ExternalWaypointSources = registry

local function TrimString(value)
    if type(value) ~= "string" then
        return nil
    end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return nil
    end
    return value
end

local function NormalizeNeedle(value)
    value = TrimString(value)
    if not value then
        return nil
    end
    return value:gsub("/", "\\"):lower()
end

local function NormalizeKey(value)
    value = NormalizeNeedle(value)
    if not value or value:find("\\", 1, true) then
        return nil
    end
    return value
end

local function CopyStringList(list)
    local out = {}
    if type(list) ~= "table" then
        return out
    end
    for index = 1, #list do
        local value = NormalizeNeedle(list[index])
        if value then
            out[#out + 1] = value
        end
    end
    return out
end

function NS.RegisterExternalWaypointSource(key, spec)
    key = NormalizeKey(key)
    if not key or type(spec) ~= "table" then
        return false
    end

    if registry.byKey[key] == nil then
        registry.order[#registry.order + 1] = key
    end

    registry.byKey[key] = {
        key = key,
        displayName = TrimString(spec.displayName) or key,
        transient = spec.transient == true,
        iconKey = TrimString(spec.iconKey) or key,
        guideProvider = NormalizeKey(spec.guideProvider),
        onTomTomWaypoint = type(spec.onTomTomWaypoint) == "function" and spec.onTomTomWaypoint or nil,
        stackMatches = CopyStringList(spec.stackMatches),
        aliases = CopyStringList(spec.aliases),
        resolveIconKey = type(spec.resolveIconKey) == "function" and spec.resolveIconKey or nil,
        resolveMetadata = type(spec.resolveMetadata) == "function" and spec.resolveMetadata or nil,
    }
    return true
end

local waypointMetadata = setmetatable({}, { __mode = "k" })
function NS.CaptureExternalWaypointMetadata(sourceAddon, uid, mapID, x, y)
    if type(uid) ~= "table" then return end
    local source = NS.GetExternalWaypointSourceInfo(sourceAddon)
    local previous = waypointMetadata[uid]
    if previous and previous.source ~= source then waypointMetadata[uid] = nil end
    if not source or not source.resolveMetadata then return end
    local ok, value = pcall(source.resolveMetadata, mapID, x, y)
    -- Some publishers can explicitly report that a reused UID has no quest.
    if ok and value == false then waypointMetadata[uid] = nil end
    if not ok or type(value) ~= "table" then return end
    local copy = {}
    for _, key in ipairs({ "questID", "objectiveIndex", "entityID" }) do
        local id = value[key]
        if type(id) == "number" and not (issecretvalue and issecretvalue(id)) and id > 0 and id < math.huge and id % 1 == 0 then copy[key] =
            id end
    end
    if not copy.questID then return end
    if value.entityKind == "Npc" or value.entityKind == "Object" or value.entityKind == "Item" then copy.entityKind =
        value.entityKind end
    if value.action == "accept" or value.action == "turnin" then copy.action = value.action end
    if value.objectiveType == "monster" or value.objectiveType == "item" or value.objectiveType == "object" then copy.objectiveType =
        value.objectiveType end
    waypointMetadata[uid] = { source = source, context = copy }
end

-- ============================================================
-- Metadata lookup and source matching
-- ============================================================

function NS.GetExternalWaypointMetadata(uid)
    local captured = waypointMetadata[uid]
    return captured and captured.context or nil
end

function NS.ResolveExternalWaypointIconKey(sourceAddon, mapID, x, y)
    local source = NS.GetExternalWaypointSourceInfo(sourceAddon)
    if type(source) ~= "table" then
        return nil
    end
    local resolver = source.resolveIconKey
    if type(resolver) ~= "function"
        or type(mapID) ~= "number"
        or type(x) ~= "number"
        or type(y) ~= "number"
    then
        return nil
    end
    local ok, key = pcall(resolver, mapID, x, y)
    if ok and type(key) == "string" and key ~= "" then
        return key
    end
    return nil
end

function NS.NormalizeExternalWaypointSource(value)
    local normalized = NormalizeNeedle(value)
    if not normalized then
        return nil
    end

    for index = 1, #registry.order do
        local key = registry.order[index]
        local source = registry.byKey[key]
        if source then
            if normalized == key or normalized == NormalizeNeedle(source.displayName) then
                return key
            end

            local aliases = source.aliases
            for aliasIndex = 1, #aliases do
                if normalized == aliases[aliasIndex] then
                    return key
                end
            end

            local stackMatches = source.stackMatches
            for matchIndex = 1, #stackMatches do
                if normalized:find(stackMatches[matchIndex], 1, true) then
                    return key
                end
            end
        end
    end
end

function NS.GetExternalWaypointSourceInfo(sourceAddon)
    local key = NS.NormalizeExternalWaypointSource(sourceAddon)
    return key and registry.byKey[key] or nil
end

function NS.IsTransientExternalWaypointSource(sourceAddon)
    local source = NS.GetExternalWaypointSourceInfo(sourceAddon)
    return type(source) == "table" and source.transient == true or false
end

function NS.GetExternalWaypointGuideProvider(sourceAddon)
    local source = NS.GetExternalWaypointSourceInfo(sourceAddon)
    return type(source) == "table" and source.guideProvider or nil
end

-- Opaque TomTom UIDs remain native-owned. A guide observer may copy their
-- coordinates and observe lifecycle, but never changes the foreign record.
function NS.ObserveGuideTomTomWaypoint(sourceAddon, event, uid)
    local source = NS.GetExternalWaypointSourceInfo(sourceAddon)
    if source and source.onTomTomWaypoint then pcall(source.onTomTomWaypoint, event, uid) end
end
