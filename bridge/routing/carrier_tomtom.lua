local NS = _G.AzerothWaypointNS
local state = NS.State

-- ============================================================
-- TomTom carrier
-- ============================================================
--
-- The single writer to TomTom. Owns:
--   - the live carrier UID representing the active AWP target
--   - crazy-arrow hijack/release lifecycle (opt-in per active carrier)
--   - title/status updates on the arrow
--   - route-menu clear/remove integration
--   - external-TomTom-waypoint hook

local Signature = NS.Signature
local externalWaypointBuffer = {}
local pendingRemovedTomTomUIDs = {}
local pendingRemovedTomTomFlush = false
local tomTomCallbackOwner = {}

local EXTERNAL_SOURCE_STACK_START = 3
local EXTERNAL_SOURCE_STACK_COUNT = 12
local EXTERNAL_DUAL_PUBLISH_DEDUPE_SECONDS = 0.5

local function GetTimeSafe()
    return type(GetTime) == "function" and GetTime() or 0
end

local function GetTomTomAddon()
    return rawget(_G, "TomTom")
end

local function HasUsableTomTom()
    local tomtom = GetTomTomAddon()
    return type(tomtom) == "table" and type(tomtom.AddWaypoint) == "function"
end

local function CopyWaypointOptions(opts)
    local copy = {}
    if type(opts) == "table" then
        for key, value in pairs(opts) do
            copy[key] = value
        end
    end
    return copy
end

local function NormalizeSourceAddonCandidate(value)
    if type(value) ~= "string" then
        return nil
    end
    local normalized = value:gsub("^%s+", ""):gsub("%s+$", "")
    if normalized == "" then
        return nil
    end
    local externalSource = type(NS.NormalizeExternalWaypointSource) == "function"
        and NS.NormalizeExternalWaypointSource(normalized)
        or nil
    if externalSource then
        return externalSource
    end
    normalized = normalized:gsub("/", "\\"):lower()
    if normalized == "wowpro" or normalized:find("\\wowpro\\", 1, true) or normalized:find("interface\\addons\\wowpro", 1, true) then
        return "WoWPro"
    end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function IsGuideProviderTomTomSource(sourceAddon)
    sourceAddon = NormalizeSourceAddonCandidate(sourceAddon)
    return type(NS.GetExternalWaypointGuideProvider) == "function"
        and NS.GetExternalWaypointGuideProvider(sourceAddon) ~= nil
end

local function ScheduleGuideProviderForTomTomSource(sourceAddon, reason)
    sourceAddon = NormalizeSourceAddonCandidate(sourceAddon)
    local providerKey = type(NS.GetExternalWaypointGuideProvider) == "function"
        and NS.GetExternalWaypointGuideProvider(sourceAddon)
        or nil
    if not providerKey then
        return false
    end
    if type(NS.ScheduleGuideProviderEvaluation) == "function" then
        -- A publication is a state update, including during addon startup.
        -- Explicit selections are captured by the guide provider itself.
        NS.ScheduleGuideProviderEvaluation(providerKey, reason or (providerKey .. "TomTom"))
    end
    return true
end

local function ResolveExplicitTomTomSourceAddon(opts, uid)
    if type(opts) == "table" and opts.corpse == true or type(uid) == "table" and uid.corpse == true then
        return "TomTom"
    end
    local fields = {
        type(opts) == "table" and opts.from or nil,
        type(opts) == "table" and opts.source or nil,
        type(uid) == "table" and uid.from or nil,
        type(uid) == "table" and uid.source or nil,
    }
    for index = 1, #fields do
        local sourceAddon = NormalizeSourceAddonCandidate(fields[index])
        if sourceAddon then
            return sourceAddon
        end
    end
    return nil
end

local function ResolveDebugStackTomTomSourceAddon()
    if type(debugstack) ~= "function" then
        return nil
    end
    local stack = debugstack(
        EXTERNAL_SOURCE_STACK_START,
        EXTERNAL_SOURCE_STACK_COUNT,
        EXTERNAL_SOURCE_STACK_COUNT
    )
    local btw = NS.Internal.BtWQuests
    if btw and btw.IsTomTomPublisher(stack) then return "btwquests" end
    return NormalizeSourceAddonCandidate(stack)
end

local function ResolveExternalTomTomSourceAddon(opts, uid, allowDebugStack)
    return NormalizeSourceAddonCandidate(type(uid) == "table" and uid.awpSourceAddon or nil)
        or NormalizeSourceAddonCandidate(type(opts) == "table" and opts.awpSourceAddon or nil)
        or ResolveExplicitTomTomSourceAddon(opts, uid)
        or (allowDebugStack and ResolveDebugStackTomTomSourceAddon() or nil)
end

local function BuildExternalPublishKey(sourceAddon, mapID, x, y)
    sourceAddon = NormalizeSourceAddonCandidate(sourceAddon)
    if not sourceAddon
        or type(mapID) ~= "number"
        or type(x) ~= "number"
        or type(y) ~= "number"
        or type(Signature) ~= "function"
    then
        return nil
    end
    return sourceAddon .. "\031" .. Signature(mapID, x, y), sourceAddon
end

function NS.NoteExternalTomTomWaypointAdoption(sourceAddon, mapID, x, y, title)
    local key, normalizedSource = BuildExternalPublishKey(sourceAddon, mapID, x, y)
    if not key then
        return false
    end

    state.routing.recentExternalTomTomAdoption = {
        key = key,
        sourceAddon = normalizedSource,
        title = title,
        expiresAt = GetTimeSafe() + EXTERNAL_DUAL_PUBLISH_DEDUPE_SECONDS,
    }
    return true
end

function NS.IsRecentExternalTomTomWaypointAdoption(sourceAddon, mapID, x, y)
    local recent = type(state.routing) == "table" and state.routing.recentExternalTomTomAdoption or nil
    if type(recent) ~= "table" then
        return false
    end

    if GetTimeSafe() > (tonumber(recent.expiresAt) or 0) then
        state.routing.recentExternalTomTomAdoption = nil
        return false
    end

    local key = BuildExternalPublishKey(sourceAddon, mapID, x, y)
    return key ~= nil and recent.key == key
end

local function GetLocalizedMapNameForWaypoint(mapID)
    if type(mapID) ~= "number" then
        return nil
    end
    local tomtom = GetTomTomAddon()
    local hbd = tomtom and tomtom.hbd or nil
    if hbd and type(hbd.GetLocalizedMap) == "function" then
        local name = hbd:GetLocalizedMap(mapID)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID) or nil
    local name = mapInfo and mapInfo.name or nil
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function NormalizeExternalTomTomTitle(mapID, x, y, opts)
    if type(opts) ~= "table" then
        return nil
    end
    if opts.from ~= "TomTom/way" then
        return opts.title
    end
    local tomtom = GetTomTomAddon()
    local genericTitle = tomtom and tomtom.L and tomtom.L["TomTom waypoint"] or nil
    if type(genericTitle) ~= "string" or genericTitle == "" or opts.title ~= genericTitle then
        return opts.title
    end
    local mapName = GetLocalizedMapNameForWaypoint(mapID)
    if type(mapName) == "string" and type(x) == "number" and type(y) == "number" then
        return string.format("%s %.0f, %.0f", mapName, x * 100, y * 100)
    end
    return opts.title
end

local function IsAWPWaypoint(uid)
    return type(uid) == "table" and
        (uid.fromAWP == true or uid.awpCarrier == true or uid.from == "AzerothWaypoint:Carrier")
end

local function IsQueueProjectionWaypoint(uid)
    return type(uid) == "table"
        and uid.awpQueueProjection == true
end

local function RouteQueueProjectionWaypoint(uid)
    if not IsQueueProjectionWaypoint(uid)
        or type(uid.awpQueueID) ~= "string"
        or tonumber(uid.awpQueueItemIndex) == nil
        or uid.awpQueueEntryType ~= "destination"
        or type(NS.RouteQueueByID) ~= "function"
    then
        return false
    end
    return NS.RouteQueueByID(uid.awpQueueID, tonumber(uid.awpQueueItemIndex))
end

local function IsExternalTomTomWaypoint(uid)
    return type(uid) == "table"
        and type(uid[1]) == "number"
        and type(uid[2]) == "number"
        and type(uid[3]) == "number"
        and not IsAWPWaypoint(uid)
end

-- ============================================================
-- External waypoint index
-- ============================================================

local function GetExternalWaypointSig(uid)
    if not IsExternalTomTomWaypoint(uid) then
        return nil
    end
    return Signature and Signature(uid[1], uid[2], uid[3]) or nil
end

local function GetExternalWaypointIndex()
    state.routing.externalWaypointsBySig = state.routing.externalWaypointsBySig or {}
    return state.routing.externalWaypointsBySig
end

local function IsTomTomWaypointActive(tomtom, uid)
    if not tomtom or type(uid) ~= "table" or type(tomtom.waypoints) ~= "table" then
        return false
    end
    local mapWaypoints = type(uid[1]) == "number" and tomtom.waypoints[uid[1]] or nil
    if type(mapWaypoints) ~= "table" then
        return false
    end
    for _, activeUID in pairs(mapWaypoints) do
        if activeUID == uid then
            return true
        end
    end
    return false
end

local function IndexExternalTomTomWaypoint(uid)
    local sig = GetExternalWaypointSig(uid)
    if type(sig) ~= "string" then
        return
    end
    local index = GetExternalWaypointIndex()
    local bucket = index[sig]
    if type(bucket) ~= "table" then
        bucket = {}
        index[sig] = bucket
    end
    bucket[uid] = true
end

local function UnindexExternalTomTomWaypoint(uid)
    local sig = GetExternalWaypointSig(uid)
    local index = state.routing.externalWaypointsBySig
    if type(index) ~= "table" or type(sig) ~= "string" then
        return
    end
    local bucket = index[sig]
    if type(bucket) ~= "table" then
        return
    end
    bucket[uid] = nil
    if next(bucket) == nil then
        index[sig] = nil
    end
end

local function GetIndexedExternalTomTomWaypointBySig(sig)
    local tomtom = GetTomTomAddon()
    local index = state.routing.externalWaypointsBySig
    if type(sig) ~= "string" or type(index) ~= "table" or not tomtom then
        return nil
    end
    local bucket = index[sig]
    if type(bucket) ~= "table" then
        return nil
    end
    for uid in pairs(bucket) do
        if IsTomTomWaypointActive(tomtom, uid) then
            return uid
        end
        bucket[uid] = nil
    end
    if next(bucket) == nil then
        index[sig] = nil
    end
    return nil
end

local function GetIndexedExternalTomTomWaypointsBySig(sig)
    local tomtom = GetTomTomAddon()
    local index = state.routing.externalWaypointsBySig
    if type(sig) ~= "string" or type(index) ~= "table" or not tomtom then
        return 0
    end
    local bucket = index[sig]
    if type(bucket) ~= "table" then
        return 0
    end
    local count = 0
    for uid in pairs(bucket) do
        if IsTomTomWaypointActive(tomtom, uid) then
            count = count + 1
            externalWaypointBuffer[count] = uid
        else
            bucket[uid] = nil
        end
    end
    if next(bucket) == nil then
        index[sig] = nil
    end
    return count
end

local function RebuildExternalTomTomWaypointIndex(tomtom)
    state.routing.externalWaypointsBySig = {}
    if not tomtom or type(tomtom.waypoints) ~= "table" then
        return
    end
    for _, mapWaypoints in pairs(tomtom.waypoints) do
        if type(mapWaypoints) == "table" then
            for _, uid in pairs(mapWaypoints) do
                IndexExternalTomTomWaypoint(uid)
            end
        end
    end
end

function NS.GetExternalTomTomWaypointBySig(sig)
    return GetIndexedExternalTomTomWaypointBySig(sig)
end

-- ============================================================
-- UID lifecycle
-- ============================================================
--
-- The live carrier UID lives in state.routing.carrierState.uid.
-- Publishing at the same coordinates can reuse the indexed pin.
-- Build the waypoint options table TomTom expects. Title is AWP's choice.
local function BuildCarrierOpts(title, meta)
    local opts = {}
    if type(meta) == "table" then
        for k, v in pairs(meta) do
            opts[k] = v
        end
    end

    -- The carrier waypoint is an internal AWP route leg, not a user-owned
    -- persistent TomTom destination. TomTom must never auto-remove it on
    -- arrival, because AWP owns leg advancement and explicit clear.
    opts.title           = title or "AWP Route"
    opts.arrowtitle      = opts.title
    opts.from            = "AzerothWaypoint:Carrier"
    opts.cleardistance   = 0
    opts.arrivaldistance = 15
    opts.callbacks       = nil
    opts.persistent      = false
    opts.minimap         = true
    opts.world           = true
    opts.awpCarrier      = true
    -- Publish the arrow once the carrier owns the returned UID.
    opts.crazy           = false
    -- Marker used by this carrier's TomTom hook so internal carrier
    -- writes are never adopted as external user waypoints.
    opts.fromAWP         = true
    return opts
end

local function GetTomTomWaypointKey(tomtom, mapID, x, y, title)
    if type(tomtom) == "table" and type(tomtom.GetKeyArgs) == "function" then
        local ok, key = pcall(tomtom.GetKeyArgs, tomtom, mapID, x, y, title)
        if ok then
            return key
        end
    end
end

local function UpdateIndexedTomTomWaypointTitle(tomtom, uid, title)
    if type(tomtom) ~= "table" or type(uid) ~= "table" then
        return false
    end
    title = title or "AWP Route"

    local mapID, x, y = uid[1], uid[2], uid[3]
    local mapWaypoints = type(tomtom.waypoints) == "table"
        and type(mapID) == "number"
        and tomtom.waypoints[mapID]
        or nil

    local indexedKey = nil
    if type(mapWaypoints) == "table" then
        local oldKey = GetTomTomWaypointKey(tomtom, mapID, x, y, uid.title)
        if oldKey and mapWaypoints[oldKey] == uid then
            indexedKey = oldKey
        else
            for key, activeUID in pairs(mapWaypoints) do
                if activeUID == uid then
                    indexedKey = key
                    break
                end
            end
        end
    end

    local newKey = GetTomTomWaypointKey(tomtom, mapID, x, y, title)
    local existing = newKey and mapWaypoints and mapWaypoints[newKey]
    if existing and existing ~= uid then return true, existing end

    uid.title = title
    uid.arrowtitle = title

    if type(mapWaypoints) ~= "table" then
        return false
    end
    if not indexedKey then
        return false
    end

    if newKey and newKey ~= indexedKey then
        mapWaypoints[indexedKey] = nil
        mapWaypoints[newKey] = uid
    end
    return true
end

local function PromoteQueueProjectionToCarrier(uid, opts)
    if not IsQueueProjectionWaypoint(uid) then
        return false
    end

    local published = state.routing and state.routing.publishedQueueState or nil
    if type(published) == "table" and type(published.uidByEntryKey) == "table" then
        local uidByEntryKey = published.uidByEntryKey
        for key, publishedUID in pairs(uidByEntryKey) do
            if publishedUID == uid then
                uidByEntryKey[key] = nil
            end
        end
        published.signature = nil
    end

    opts = type(opts) == "table" and opts or {}
    uid.from = "AzerothWaypoint:Carrier"
    uid.fromAWP = true
    uid.awpCarrier = true
    uid.awpQueueProjection = nil
    uid.awpQueueID = nil
    uid.awpQueueItemIndex = nil
    uid.awpQueueEntryType = nil
    uid.cleardistance = opts.cleardistance
    uid.arrivaldistance = opts.arrivaldistance
    uid.persistent = opts.persistent
    uid.minimap = opts.minimap
    uid.world = opts.world
    return true
end

local function SetCarrierArrowTitle(tomtom, carrier, title)
    if type(carrier) ~= "table" or not carrier.uid then
        return false
    end
    title = title or "AWP Route"
    carrier.title = title
    local indexed, existing = UpdateIndexedTomTomWaypointTitle(tomtom, carrier.uid, title)
    if existing then
        -- Match TomTom's AddWaypoint deduplication instead of overwriting a
        -- source-owned UID (notably the native corpse) at the new title key.
        NS.Internal.CarrierTomTom.RemoveCarrierUID(tomtom, carrier.uid)
        if state.routing.carrierState ~= carrier then return false end
        carrier.uid = existing
        state.routing.lastPushedCarrierUID = existing
        PromoteQueueProjectionToCarrier(existing, BuildCarrierOpts(title))
    end
    local setCrazyArrow = state.routing.originalSetCrazyArrow or tomtom and tomtom.SetCrazyArrow
    if indexed and type(tomtom) == "table" and type(setCrazyArrow) == "function" then
        pcall(setCrazyArrow, tomtom, carrier.uid, 15, title)
    end
    return indexed
end

function NS.PushCarrierWaypoint(mapID, x, y, title, meta, previous)
    if not HasUsableTomTom() then return false end
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return false
    end

    local tomtom = GetTomTomAddon()
    local routing = state.routing
    local carrier = routing.carrierState or {}
    previous = previous or carrier
    routing.carrierState = carrier
    local newSig = Signature and Signature(mapID, x, y) or string.format("%s:%s:%s", mapID, x, y)

    if previous.sig == newSig and previous.uid
        and (previous.uid.corpse ~= true or type(meta) == "table" and type(meta.identity) == "table"
            and meta.identity.destinationKind == "corpse") then
        if IsTomTomWaypointActive(tomtom, previous.uid) then
            carrier.uid = previous.uid
            SetCarrierArrowTitle(tomtom, carrier, title)
            return true
        end
    elseif previous.uid then
        NS.Internal.CarrierTomTom.RemoveCarrierUID(tomtom, previous.uid)
        if routing.carrierState ~= carrier then return false end
    end

    local opts = BuildCarrierOpts(title, meta)
    local published = state.routing.publishedQueueState
    local publishedUIDs = published and published.uidByEntryKey
    local key = publishedUIDs and GetTomTomWaypointKey(tomtom, mapID, x, y, opts.title)
    local uid = key and publishedUIDs[key]
    local mapWaypoints = type(tomtom.waypoints) == "table" and tomtom.waypoints[mapID]
    if not IsQueueProjectionWaypoint(uid) or not mapWaypoints or mapWaypoints[key] ~= uid then
        local ok
        ok, uid = pcall(tomtom.AddWaypoint, tomtom, mapID, x, y, opts)
        if not ok or not uid then return false end
        if routing.carrierState ~= carrier then
            local current = routing.carrierState
            if uid.awpCarrier and not uid.awpQueueProjection and not (current and current.uid == uid)
                and IsTomTomWaypointActive(tomtom, uid) then
                NS.Internal.CarrierTomTom.RemoveCarrierUID(tomtom, uid)
            end
            return false
        end
    end
    PromoteQueueProjectionToCarrier(uid, opts)

    carrier.mapID, carrier.x, carrier.y = mapID, x, y
    carrier.sig, carrier.uid = newSig, uid
    routing.lastPushedCarrierUID = uid

    -- Make this waypoint the active crazy-arrow target. AddWaypoint just
    -- creates the pin, SetCrazyArrow makes it the live navigation arrow.
    -- The carrier owns arrival display, but not clear/removal.
    return SetCarrierArrowTitle(tomtom, carrier, title)
end

function NS.ClearCarrierWaypoint()
    local carrier = state.routing.carrierState
    state.routing.carrierState = nil
    state.routing.lastPushedCarrierUID = nil
    if not carrier or not carrier.uid then
        return
    end

    local tomtom = GetTomTomAddon()
    if tomtom and NS.Internal and NS.Internal.CarrierTomTom then
        NS.Internal.CarrierTomTom.RemoveCarrierUID(tomtom, carrier.uid)
    end
end

-- ============================================================
-- Queue pins on the map
-- ============================================================

local function BuildQueueProjectionOpts(entry)
    entry = type(entry) == "table" and entry or {}
    local opts = {
        title = entry.title or "AWP Queue",
        from = "AzerothWaypoint:Queue",
        fromAWP = true,
        awpQueueProjection = true,
        awpQueueID = entry.queueID,
        awpQueueItemIndex = entry.queueItemIndex,
        awpQueueEntryType = entry.entryType,
        persistent = false,
        crazy = false,
        cleardistance = 0,
        minimap = true,
        world = true,
    }
    return opts
end

local function BuildQueueProjectionSignature(entries, queueKey)
    if type(queueKey) ~= "string" or type(entries) ~= "table" then
        return nil
    end
    local parts = { queueKey }
    for index = 1, #entries do
        local entry = entries[index]
        parts[#parts + 1] = table.concat({
            tostring(type(entry) == "table" and entry.key or index),
            tostring(type(entry) == "table" and entry.title or "-"),
        }, ":", 1, 2)
    end
    return table.concat(parts, "\031")
end

function NS.ClearPublishedQueuePins()
    local routing = state.routing
    local published = routing.publishedQueueState
    if published and not published.queueKey and published.uidByEntryKey and not next(published.uidByEntryKey) then return end
    -- A removal listener may publish a new queue before this loop returns.
    routing.publishedQueueState = { uidByEntryKey = {} }
    if type(published) ~= "table" or type(published.uidByEntryKey) ~= "table" then
        return
    end

    local tomtom = GetTomTomAddon()
    if tomtom and NS.Internal and NS.Internal.CarrierTomTom then
        for key, uid in pairs(published.uidByEntryKey) do
            local carrier = routing.carrierState
            if routing.publishedQueueState.uidByEntryKey[key] ~= uid and not (carrier and carrier.uid == uid) then
                NS.Internal.CarrierTomTom.RemoveCarrierUID(tomtom, uid)
            end
        end
    end
end

function NS.PublishQueueProjectionPins()
    if not HasUsableTomTom() then
        return false
    end

    local entries, queueKey = nil, nil
    if type(NS.GetActiveQueuePublishedEntries) == "function" then
        entries, queueKey = NS.GetActiveQueuePublishedEntries()
    end
    if type(entries) ~= "table" or #entries == 0 or type(queueKey) ~= "string" then
        NS.ClearPublishedQueuePins()
        return false
    end

    local signature = BuildQueueProjectionSignature(entries, queueKey)
    local published = state.routing.publishedQueueState or {}
    local carrier = state.routing.carrierState
    local carrierUID = carrier and carrier.uid
    local carrierTitle = type(carrierUID) == "table" and carrierUID.title or nil
    if published.signature == signature and published.carrierUID == carrierUID and published.carrierTitle == carrierTitle then
        return true
    end

    local tomtom = GetTomTomAddon()
    local addWaypoint = state.routing.originalAddWaypoint or tomtom and tomtom.AddWaypoint
    if not tomtom or type(addWaypoint) ~= "function" then
        return false
    end

    if published.queueKey ~= queueKey or type(published.uidByEntryKey) ~= "table" then
        NS.ClearPublishedQueuePins()
        if state.routing.carrierState ~= carrier then return false end
        published = state.routing.publishedQueueState
    end
    published.queueKey, published.signature = queueKey, nil
    local uidByEntryKey = published.uidByEntryKey
    local carrierKey = type(carrierUID) == "table"
        and GetTomTomWaypointKey(tomtom, carrierUID[1], carrierUID[2], carrierUID[3], carrierTitle)
    local wanted = {}
    for index, entry in ipairs(entries) do
        if type(entry) == "table" and type(entry.mapID) == "number"
            and type(entry.x) == "number" and type(entry.y) == "number"
        then
            -- TomTom identifies a pin by coordinates and title. A queue index
            -- is click metadata and can change while the pin stays in place.
            local key = GetTomTomWaypointKey(tomtom, entry.mapID, entry.x, entry.y, entry.title or "AWP Queue")
                or entry.key or tostring(index)
            local prior = wanted[key]
            if key ~= carrierKey and (not prior or entry.isTopLevel and not prior.isTopLevel) then
                wanted[key] = entry
            end
        end
    end
    for key, uid in pairs(uidByEntryKey) do
        local entry = wanted[key]
        if uid == carrierUID or not entry or type(uid) ~= "table" or uid.title ~= (entry.title or "AWP Queue") then
            uidByEntryKey[key] = nil
            if uid ~= carrierUID then
                NS.Internal.CarrierTomTom.RemoveCarrierUID(tomtom, uid)
                if state.routing.carrierState ~= carrier or state.routing.publishedQueueState ~= published then return false end
            end
        end
    end
    local complete = true
    for key, entry in pairs(wanted) do
        local uid = uidByEntryKey[key]
        if not uid then
            local opts = BuildQueueProjectionOpts(entry)
            local ok, addedUID = pcall(addWaypoint, tomtom, entry.mapID, entry.x, entry.y, opts)
            if state.routing.carrierState ~= carrier or state.routing.publishedQueueState ~= published then
                local current = state.routing.publishedQueueState
                if ok and IsQueueProjectionWaypoint(addedUID) and not (current and current.uidByEntryKey[key] == addedUID)
                    and IsTomTomWaypointActive(tomtom, addedUID) then
                    NS.Internal.CarrierTomTom.RemoveCarrierUID(tomtom, addedUID)
                end
                return false
            end
            if ok and addedUID then
                uid = addedUID
                if uid ~= carrierUID then uidByEntryKey[key] = uid end
            else
                complete = false
            end
        end
        if type(uid) == "table" and uid ~= carrierUID and uid.corpse ~= true then
            uid.fromAWP = true
            uid.awpQueueProjection = true
            uid.awpQueueID = entry.queueID
            uid.awpQueueItemIndex = entry.queueItemIndex
            uid.awpQueueEntryType = entry.entryType
        end
    end

    published.signature = complete and signature or nil
    published.carrierUID = carrierUID
    published.carrierTitle = carrierTitle
    return true
end

-- ============================================================
-- External TomTom waypoint hook
-- ============================================================

local function ShouldDivertExternalTomTomAdd(mapID, x, y, opts)
    if type(NS.IsRoutingEnabled) == "function" and not NS.IsRoutingEnabled() then
        return false
    end
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return false
    end
    if type(opts) == "table" and (opts.fromAWP == true or opts.awpCarrier == true or opts.from == "AzerothWaypoint:Carrier") then
        return false
    end
    if IsGuideProviderTomTomSource(ResolveExplicitTomTomSourceAddon(opts, nil)) then
        return false
    end
    return true
end

local function BuildExternalTomTomCallbacks(opts)
    local tomtom = GetTomTomAddon()
    if not tomtom or type(tomtom.DefaultCallbacks) ~= "function" then
        return type(opts) == "table" and opts.callbacks or nil
    end

    local callbackOpts = CopyWaypointOptions(opts)
    callbackOpts.cleardistance = 0

    local callbacks = tomtom:DefaultCallbacks(callbackOpts) or {}
    local externalCallbacks = type(opts) == "table" and opts.callbacks or nil
    if type(externalCallbacks) == "table" then
        for key, value in pairs(externalCallbacks) do
            if key ~= "distance" then
                callbacks[key] = value
            end
        end
    end
    return callbacks
end

local function PrepareExternalTomTomAddOptions(mapID, x, y, opts)
    if not ShouldDivertExternalTomTomAdd(mapID, x, y, opts) then
        return opts
    end

    local copied = CopyWaypointOptions(opts)
    copied.title = NormalizeExternalTomTomTitle(mapID, x, y, copied)
    local sourceAddon = ResolveExternalTomTomSourceAddon(copied, nil, true)
    if type(sourceAddon) == "string" then
        copied.awpSourceAddon = sourceAddon
    end
    copied.crazy = false
    copied.cleardistance = 0
    copied.callbacks = BuildExternalTomTomCallbacks(copied)
    return copied
end

local function PrepareGuideProviderTomTomAddOptions(opts)
    if type(NS.IsRoutingEnabled) == "function" and not NS.IsRoutingEnabled() then
        return opts, nil
    end
    local sourceAddon = ResolveExternalTomTomSourceAddon(opts, nil, true)
    if not IsGuideProviderTomTomSource(sourceAddon) then
        return opts, nil
    end

    local copied = CopyWaypointOptions(opts)
    copied.awpSourceAddon = sourceAddon
    copied.crazy = false
    return copied, sourceAddon
end

local function QueueSlashWaypointBatch(mapID, x, y, title)
    state.routing.slashBatchEntries = state.routing.slashBatchEntries or {}
    state.routing.slashBatchEntries[#state.routing.slashBatchEntries + 1] = {
        mapID = mapID,
        x = x,
        y = y,
        title = title,
    }

    if state.routing.slashBatchScheduled then
        return true
    end

    state.routing.slashBatchScheduled = true
    NS.After(0, function()
        local entries = state.routing.slashBatchEntries
        state.routing.slashBatchEntries = nil
        state.routing.slashBatchScheduled = false
        if type(entries) ~= "table" or type(entries[1]) ~= "table" then
            return
        end

        if type(NS.IsRoutingEnabled) == "function" and not NS.IsRoutingEnabled() then
            return
        end

        if #entries > 1 then
            NS.RouteImportedWaypointBatch(entries)
            return
        end

        local first = entries[1]
        local uid = Signature and GetIndexedExternalTomTomWaypointBySig(Signature(first.mapID, first.x, first.y)) or nil
        local meta = type(NS.CreateRouteMetaForExternalWaypoint) == "function"
            and NS.CreateRouteMetaForExternalWaypoint(uid, first.mapID, first.x, first.y, first.title)
            or nil
        NS.RequestManualRoute(first.mapID, first.x, first.y, first.title, meta, {
            clickContext = { source = "tomtom_way", explicit = true },
        })
    end)
    return true
end

local function RouteExternalTomTomWaypoint(mapID, x, y, title, uid)
    if type(NS.IsRoutingEnabled) == "function" and not NS.IsRoutingEnabled() then
        return false
    end
    if state.routing.slashBatchScheduled then
        return true
    end

    local meta = type(NS.CreateRouteMetaForExternalWaypoint) == "function"
        and NS.CreateRouteMetaForExternalWaypoint(uid, mapID, x, y, title)
        or nil
    local current = type(NS.GetManualAuthority) == "function" and NS.GetManualAuthority() or nil
    local corpseIdentity = NS.GetCorpseRouteIdentity(state.routing.pendingManualAuthority)
        or NS.GetCorpseRouteIdentity(current)
    local incomingIdentity = NS.GetCorpseRouteIdentity(meta)
    if incomingIdentity and corpseIdentity
        and (corpseIdentity.kind == "corpse" or NS.RouteIdentitiesMatch(corpseIdentity, incomingIdentity)) then
        -- A corpse source can publish again after spirit release, including
        -- after a route was already acquired from Mapzeroth.
        return true
    end
    local adopted = NS.AdoptExternalWaypoint(mapID, x, y, title, meta)
    if adopted then
        NS.NoteExternalTomTomWaypointAdoption(
            type(uid) == "table" and uid.awpSourceAddon or nil,
            mapID,
            x,
            y,
            title
        )
    end
    return adopted
end

local function IsRareScannerMouseDownPublish(sourceAddon)
    sourceAddon = NormalizeSourceAddonCandidate(sourceAddon)
    return sourceAddon == "rarescanner"
        and type(NS.IsRareScannerClickPhaseDown) == "function"
        and NS.IsRareScannerClickPhaseDown()
end

local function ReassertCarrierArrow()
    local tomtom = GetTomTomAddon()
    local originalSetCrazyArrow = state.routing.originalSetCrazyArrow
    local carrier = state.routing.carrierState
    if not tomtom or type(originalSetCrazyArrow) ~= "function" or type(carrier) ~= "table" or not carrier.uid then
        return
    end
    pcall(originalSetCrazyArrow, tomtom, carrier.uid, 15, carrier.title or "AWP Route")
end

function NS.InstallExternalTomTomHooks()
    local tomtom = GetTomTomAddon()
    if not tomtom or type(tomtom.AddWaypoint) ~= "function" then
        return
    end
    if state.routing._externalTomTomHooksInstalled then
        return
    end

    state.routing.originalAddWaypoint = state.routing.originalAddWaypoint or tomtom.AddWaypoint
    state.routing.originalSetCrazyArrow = state.routing.originalSetCrazyArrow or tomtom.SetCrazyArrow
    RebuildExternalTomTomWaypointIndex(tomtom)

    tomtom.AddWaypoint = function(self, mapID, x, y, opts)
        local originalAddWaypoint = state.routing.originalAddWaypoint
        if type(originalAddWaypoint) ~= "function" then
            return nil
        end

        local effectiveOpts, guideSourceAddon = PrepareGuideProviderTomTomAddOptions(opts)
        local divert = guideSourceAddon == nil and ShouldDivertExternalTomTomAdd(mapID, x, y, opts)
        if guideSourceAddon == nil then
            effectiveOpts = PrepareExternalTomTomAddOptions(mapID, x, y, opts)
        end
        local uid = originalAddWaypoint(self, mapID, x, y, effectiveOpts)
        -- TomTom can return a previously published UID when its key matches.
        -- Prefer the current publisher over metadata from that older click.
        local sourceAddon = guideSourceAddon or (divert and effectiveOpts.awpSourceAddon)
            or ResolveExternalTomTomSourceAddon(effectiveOpts, uid, false)
        if NS.CaptureExternalWaypointMetadata then
            NS.CaptureExternalWaypointMetadata(sourceAddon, uid, mapID, x, y)
        end
        if guideSourceAddon then
            if type(uid) == "table" then
                uid.awpSourceAddon = guideSourceAddon
            end
            if NS.ObserveGuideTomTomWaypoint then NS.ObserveGuideTomTomWaypoint(guideSourceAddon, "added", uid) end
            ScheduleGuideProviderForTomTomSource(guideSourceAddon, "GuideTomTomAddWaypoint")
        elseif type(uid) == "table" and divert then
            if type(sourceAddon) == "string" then
                uid.awpSourceAddon = sourceAddon
            end
            IndexExternalTomTomWaypoint(uid)
        elseif type(uid) == "table" then
            if ScheduleGuideProviderForTomTomSource(sourceAddon, "GuideTomTomAddWaypoint") then
                uid.awpSourceAddon = sourceAddon
            end
        end

        local effectiveTitle = type(uid) == "table" and uid.title
            or type(effectiveOpts) == "table" and effectiveOpts.title
            or type(opts) == "table" and opts.title
            or nil

        if divert then
            if IsRareScannerMouseDownPublish(sourceAddon) then
                return uid
            end
            if type(opts) == "table" and opts.from == "TomTom/way" then
                QueueSlashWaypointBatch(mapID, x, y, effectiveTitle)
            else
                RouteExternalTomTomWaypoint(mapID, x, y, effectiveTitle, uid)
            end
        end

        return uid
    end

    if type(tomtom.SetCrazyArrow) == "function" then
        tomtom.SetCrazyArrow = function(self, uid, dist, title)
            local originalSetCrazyArrow = state.routing.originalSetCrazyArrow
            if type(originalSetCrazyArrow) ~= "function" then
                return nil
            end
            if IsQueueProjectionWaypoint(uid) then
                RouteQueueProjectionWaypoint(uid)
                ReassertCarrierArrow()
                return nil
            end
            if not IsExternalTomTomWaypoint(uid) or (type(NS.IsRoutingEnabled) == "function" and not NS.IsRoutingEnabled()) then
                return originalSetCrazyArrow(self, uid, dist, title)
            end
            local sourceAddon = ResolveExternalTomTomSourceAddon(nil, uid, false)
            if NS.ObserveGuideTomTomWaypoint then NS.ObserveGuideTomTomWaypoint(sourceAddon, "selected", uid) end
            if ScheduleGuideProviderForTomTomSource(sourceAddon, "GuideTomTomSetCrazyArrow") then
                return nil
            end

            local adopted = RouteExternalTomTomWaypoint(uid[1], uid[2], uid[3], title or uid.title, uid)
            if adopted then
                ReassertCarrierArrow()
                return nil
            end
            return originalSetCrazyArrow(self, uid, dist, title)
        end
    end

    state.routing._externalTomTomHooksInstalled = true
end

-- ============================================================
-- Carrier-UID removal detection
-- ============================================================
--
-- When the user right-clicks the TomTom arrow and chooses Remove, or
-- otherwise dismisses the waypoint through TomTom, its public
-- WaypointRemoved callback fires. AWP observes that callback so it can clear
-- manualAuthority and stop the world overlay from re-syncing the destination.
--
-- We must NOT react when AWP itself removed the UID (during
-- PushCarrierWaypoint's old-UID teardown, or ClearCarrierWaypoint).
-- A counter lets the callback ignore those self-initiated removes.

local awpInitiatedRemove = 0

local function IsAWPInitiatedRemove()
    return awpInitiatedRemove > 0
end

local function ForgetExternalClearedCarrier(resetQueuePins)
    local routing = NS.State.routing
    if type(routing) ~= "table" then
        return
    end
    routing.carrierState = nil
    routing.lastPushedCarrierUID = nil
    if resetQueuePins and type(NS.ClearPublishedQueuePins) == "function" then
        NS.ClearPublishedQueuePins()
    end
end

local function ReassertGuideCarrierAfterExternalClear(reason, resetQueuePins)
    local routing = NS.State.routing
    if type(routing) ~= "table" then
        return false
    end
    if type(NS.GetGuideRouteState) ~= "function" or not NS.GetGuideRouteState() then
        return false
    end
    if type(NS.GetGuideVisibilityState) == "function"
        and NS.GetGuideVisibilityState() ~= "visible"
    then
        return false
    end

    ForgetExternalClearedCarrier(resetQueuePins)
    if type(NS.RecomputeCarrier) == "function" then
        NS.RecomputeCarrier()
    end
    if type(NS.Log) == "function" then
        NS.Log("Guide waypoint clear ignored", tostring(reason or "-"))
    end
    return true
end

local function HandleExternalCarrierRemove(uid)
    if not uid then return end
    if IsAWPInitiatedRemove() then return end
    local cs = NS.State.routing and NS.State.routing.carrierState
    if not cs or cs.uid ~= uid then return false end
    -- Our carrier UID was removed externally. Manual authority routes
    -- must run the explicit-clear fan-out first. Guide routes are read-only:
    -- TomTom can remove the physical UID, but the live guide step remains
    -- authoritative and is immediately re-pushed.
    if cs.source == "manual"
        and cs.authorityPending == true
        and type(NS.State.routing.pendingManualAuthority) == "table"
    then
        ForgetExternalClearedCarrier(false)
        if type(NS.CancelPendingManualRoute) == "function" then
            NS.CancelPendingManualRoute("remove_waypoint")
        end
        if type(NS.RecomputeCarrier) == "function" then
            NS.RecomputeCarrier()
        end
        return true
    elseif type(NS.GetManualAuthority) == "function" and NS.GetManualAuthority() then
        if type(NS.HandleExplicitManualAuthorityRemove) == "function" then
            NS.HandleExplicitManualAuthorityRemove()
            return true
        end
    elseif cs.source == "guide"
        and type(NS.GetGuideRouteState) == "function"
        and NS.GetGuideRouteState()
    then
        if not ReassertGuideCarrierAfterExternalClear("remove_waypoint", false) then
            ForgetExternalClearedCarrier(false)
            if type(NS.RecomputeCarrier) == "function" then
                NS.RecomputeCarrier()
            end
        end
        return true
    end
    NS.State.routing.carrierState = nil
    NS.State.routing.lastPushedCarrierUID = nil
    if type(NS.RecomputeCarrier) == "function" then
        NS.RecomputeCarrier()
    end
    return true
end

local function GetActiveExternalManualSig()
    local record = type(NS.GetManualAuthority) == "function" and NS.GetManualAuthority() or nil
    local identity = type(record) == "table" and type(record.identity) == "table" and record.identity or nil
    if type(identity) ~= "table" or identity.kind ~= "external_tomtom" then
        return nil
    end
    return identity.queueSig or identity.externalSig or identity.sig
end

local function HandleTomTomWaypointRemoved(uid)
    if not uid then
        return
    end
    if HandleExternalCarrierRemove(uid) then
        return
    end

    local sig = GetExternalWaypointSig(uid)
    UnindexExternalTomTomWaypoint(uid)
    if IsAWPInitiatedRemove() then
        return
    end
    local published = state.routing.publishedQueueState
    if published and published.uidByEntryKey then
        for key, publishedUID in pairs(published.uidByEntryKey) do
            if publishedUID == uid then published.uidByEntryKey[key], published.signature = nil, nil end
        end
    end

    if type(NS.NoteQueuedTomTomWaypointCleared) == "function" then
        NS.NoteQueuedTomTomWaypointCleared(uid)
    end

    local active = type(NS.GetManualAuthority) == "function" and NS.GetManualAuthority() or nil
    local identity = active and active.identity
    local sameDestinationKind = (type(uid) == "table" and uid.corpse == true)
        == (type(identity) == "table" and identity.destinationKind == "corpse")
    if sameDestinationKind and type(sig) == "string" and sig == GetActiveExternalManualSig()
        and type(NS.HandleExplicitManualAuthorityRemove) == "function"
    then
        NS.HandleExplicitManualAuthorityRemove()
    end
end

local function QueueTomTomWaypointRemoved(uid)
    if not uid or IsAWPInitiatedRemove() then
        return
    end

    pendingRemovedTomTomUIDs[uid] = true
    if pendingRemovedTomTomFlush then
        return
    end

    pendingRemovedTomTomFlush = true
    NS.After(0, function()
        pendingRemovedTomTomFlush = false
        for removedUID in pairs(pendingRemovedTomTomUIDs) do
            pendingRemovedTomTomUIDs[removedUID] = nil
            HandleTomTomWaypointRemoved(removedUID)
        end
    end)
end

local function DiscardPendingTomTomWaypointRemovals()
    for uid in pairs(pendingRemovedTomTomUIDs) do
        pendingRemovedTomTomUIDs[uid] = nil
    end
end

local function RebuildCarrierAfterTomTomReload()
    local tomtom = GetTomTomAddon()
    RebuildExternalTomTomWaypointIndex(tomtom)

    local routing = state.routing
    routing.carrierState = nil
    routing.lastPushedCarrierUID = nil
    routing.publishedQueueState = {
        queueKey = nil,
        signature = nil,
        uidByEntryKey = {},
    }

    if type(NS.RecomputeCarrier) == "function" then
        NS.RecomputeCarrier()
    end
end

local function HandleExplicitTomTomRemoveAll()
    if NS.Internal.ServiceSearch then NS.Internal.ServiceSearch.Cancel() end
    RebuildExternalTomTomWaypointIndex(GetTomTomAddon())
    local routing = state.routing
    routing.queueAfterCorpse = nil
    local record = routing.manualAuthority
    local pending = routing.pendingManualAuthority
    local queueID = record and record.queueID
    -- A click can own the Blizzard pin before its queue transaction commits.
    -- Release that request while the host still knows which pin it owns.
    if pending then
        if pending.queueID and pending.queueID == routing.activeQueueKey then queueID = pending.queueID end
        NS.CancelPendingManualRoute("remove_all")
        if routing.pendingManualAuthority or routing.manualAuthority ~= record then return end
    end
    if queueID and NS.ClearQueueByID and NS.ClearQueueByID(queueID) then return end
    if record then
        NS.HandleExplicitManualAuthorityRemove()
    else
        ForgetExternalClearedCarrier(true)
        if NS.RecomputeCarrier then NS.RecomputeCarrier() end
    end
end

local function InstallTomTomRemoveAllIntentHook(reload)
    local dialogs = rawget(_G, "StaticPopupDialogs")
    local dialog = type(dialogs) == "table" and dialogs.TOMTOM_REMOVE_ALL_CONFIRM or nil
    if type(dialog) ~= "table" or type(dialog.OnAccept) ~= "function" then
        return
    end

    hooksecurefunc(dialog, "OnAccept", function()
        -- ResetProfile emits WaypointsReloaded inside OnAccept. Consume the
        -- reset here so a later click cannot be cleared by a next-frame timer.
        if reload.pending then
            reload:Cancel()
            HandleExplicitTomTomRemoveAll()
        end
    end)
end

function NS.InstallCarrierTomTomHooks()
    local tomtom = GetTomTomAddon()
    if not tomtom then return end
    if NS.State.routing._carrierHooksInstalled then return end

    if type(tomtom.RegisterCallback) == "function" then
        tomtom.RegisterCallback(tomTomCallbackOwner, "WaypointRemoved", function(_, uid)
            if NS.ObserveGuideTomTomWaypoint then
                NS.ObserveGuideTomTomWaypoint(ResolveExternalTomTomSourceAddon(nil, uid, false), "removed", uid)
            end
            QueueTomTomWaypointRemoved(uid)
        end)
        local reload = NS.Internal.Scheduling.CreateCoalescer(RebuildCarrierAfterTomTomReload)
        tomtom.RegisterCallback(tomTomCallbackOwner, "WaypointsReloaded", function()
            -- TomTom discarded the whole collection. Its earlier per-pin
            -- callbacks belong to the reload and should not advance a queue.
            DiscardPendingTomTomWaypointRemovals()
            reload:Request()
        end)
        InstallTomTomRemoveAllIntentHook(reload)
    end

    NS.State.routing._carrierHooksInstalled = true
end

-- Wrap the in-module helper that performs AWP-initiated removes so the
-- counter is bumped only around our own RemoveWaypoint calls. Called
-- from PushCarrierWaypoint (when tearing down an old UID) and from
-- ClearCarrierWaypoint (full teardown).
local function AWPRemoveCarrierUID(tomtom, uid)
    if not tomtom or not uid or type(tomtom.RemoveWaypoint) ~= "function" then
        return
    end
    -- An adopted native corpse UID may also serve as our carrier. TomTom
    -- still owns its lifetime and must be able to remove it on resurrection.
    if type(uid) == "table" and uid.corpse == true then return end
    awpInitiatedRemove = awpInitiatedRemove + 1
    pcall(tomtom.RemoveWaypoint, tomtom, uid)
    awpInitiatedRemove = awpInitiatedRemove - 1
end
NS.Internal = NS.Internal or {}
NS.Internal.CarrierTomTom = NS.Internal.CarrierTomTom or {}
NS.Internal.CarrierTomTom.RemoveCarrierUID = AWPRemoveCarrierUID

function NS.RemoveExternalTomTomWaypointsBySig(sig)
    local tomtom = GetTomTomAddon()
    if type(sig) ~= "string" or not tomtom or type(tomtom.RemoveWaypoint) ~= "function" then
        return
    end

    local count = GetIndexedExternalTomTomWaypointsBySig(sig)
    if count <= 0 then
        return
    end

    awpInitiatedRemove = awpInitiatedRemove + 1
    for index = 1, count do
        local uid = externalWaypointBuffer[index]
        externalWaypointBuffer[index] = nil
        if uid then
            pcall(tomtom.RemoveWaypoint, tomtom, uid)
            UnindexExternalTomTomWaypoint(uid)
        end
    end
    awpInitiatedRemove = awpInitiatedRemove - 1
end
