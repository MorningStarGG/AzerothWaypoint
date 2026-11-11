local NS = _G.AzerothWaypointNS

-- ============================================================
-- Mapzeroth backend
-- ============================================================

local Private = {}

local REQUIRED = {
    { "GetPlayerStart" },
    { "PlaceAt" },
    { "GetPlayerContext" },
    { "GetKnownTeleports" },
    { "GetFlightSpeedMultiplier" },
    { "MeetsRequirements" },
    { "Journey", "Build" },
    { "Journey", "PlanEntry" },
    { "World", "GetNode" },
    { "World", "LivePhases" },
    { "TravelGraph", "Build" },
}

local ROUTE_OPTION = {
    loadingScreenTax = true,
    maxCooldown = true,
    assumeFlightsFound = true,
}
local ROUTE_OPTION_KEYS = { "loadingScreenTax", "maxCooldown", "assumeFlightsFound" }

local function Addon()
    return rawget(_G, "MapzerothAddon")
end

local function AddonVersion()
    local api = rawget(_G, "C_AddOns")
    local getMetadata = type(api) == "table" and api.GetAddOnMetadata or rawget(_G, "GetAddOnMetadata")
    if type(getMetadata) ~= "function" then return nil end
    local ok, value = pcall(getMetadata, "Mapzeroth", "Version")
    return ok and type(value) == "string" and value or nil
end

local function IsLoaded()
    local api = rawget(_G, "C_AddOns")
    local fn = type(api) == "table" and api.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded")
    if type(fn) ~= "function" then return Addon() ~= nil end
    local ok, loaded = pcall(fn, "Mapzeroth")
    return ok and loaded == true
end

local function IsInstalled()
    local api = rawget(_G, "C_AddOns")
    local fn = type(api) == "table" and api.GetAddOnInfo or rawget(_G, "GetAddOnInfo")
    if type(fn) ~= "function" then return IsLoaded() or Addon() ~= nil end
    local ok, name = pcall(fn, "Mapzeroth")
    return ok and name ~= nil
end

local function ResolvePath(root, path)
    local value = root
    for index = 1, #path do
        value = type(value) == "table" and value[path[index]] or nil
    end
    return value
end

function Private.GetCompatibilityStatus()
    local status = {
        installed = IsInstalled(),
        loaded = IsLoaded(),
        version = AddonVersion(),
    }
    local addon = Addon()
    if not status.loaded then
        status.compatible = false
        status.missing = "loaded addon"
        status.reason = "Mapzeroth is not loaded."
        return status
    end
    if type(addon) ~= "table" then
        status.compatible = false
        status.reason = "Mapzeroth is loaded, but its addon object is unavailable."
        status.missing = "MapzerothAddon"
        return status
    end
    for index = 1, #REQUIRED do
        local path = REQUIRED[index]
        if type(ResolvePath(addon, path)) ~= "function" then
            status.compatible = false
            status.missing = table.concat(path, ".")
            status.reason = "Mapzeroth is missing required capability " .. status.missing .. "."
            return status
        end
    end
    status.compatible = true
    status.reason = nil
    return status
end

local function Accessible(value)
    local secret = rawget(_G, "issecretvalue")
    if type(secret) == "function" then
        local ok, result = pcall(secret, value)
        if not ok or result == true then return false end
    end
    local canAccess = rawget(_G, "canaccessvalue")
    if type(canAccess) == "function" then
        local ok, result = pcall(canAccess, value)
        if not ok or result ~= true then return false end
    end
    return true
end

local function Scalar(value)
    if not Accessible(value) then return nil end
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then return value end
    return nil
end

local function Call(object, method, ...)
    local fn = type(object) == "table" and object[method] or nil
    if type(fn) ~= "function" then return false, "missing " .. tostring(method) end
    local ok, a, b, c = pcall(fn, object, ...)
    if not ok then return false, tostring(a) end
    return true, a, b, c
end

local function CopyPoint(point)
    if type(point) ~= "table" then return nil end
    local id, mapID, x, y = Scalar(point.id), Scalar(point.mapID), Scalar(point.x), Scalar(point.y)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return { id = id, mapID = mapID, x = x, y = y }
end

local SOURCE_FIELDS = {
    "id", "name", "method", "spellID", "itemID", "toy", "to", "cost", "cooldown",
    "equipSeconds", "equipCooldown", "loadingScreens", "consumable", "sharedCooldown", "faction",
}
local CONTEXT_STATE_FIELDS = {
    "faction", "class", "race", "raceID", "level", "loadingScreenTax", "maxCooldown", "money", "hearthNode",
}

local function CopySource(source)
    if type(source) ~= "table" then return nil end
    local copy = {}
    for index = 1, #SOURCE_FIELDS do
        local key = SOURCE_FIELDS[index]
        local value = Scalar(source[key])
        if value ~= nil then copy[key] = value end
    end
    if type(source.toList) == "table" then
        copy.toList = {}
        for index = 1, #source.toList do
            local value = Scalar(source.toList[index])
            if value ~= nil then copy.toList[#copy.toList + 1] = value end
        end
    end
    return copy
end

local function CopyStep(step)
    if type(step) ~= "table" then return nil end
    local copy = {
        method = Scalar(step.method),
        nodeID = Scalar(step.nodeID),
        fromID = Scalar(step.fromID),
        seconds = Scalar(step.seconds),
        name = Scalar(step.name),
        text = Scalar(step.text),
        clickPortal = Scalar(step.clickPortal) == true or nil,
        approx = Scalar(step.approx) == true or nil,
        source = CopySource(step.source),
    }
    if type(step.via) == "table" then
        copy.via = {}
        for index = 1, #step.via do
            local value = Scalar(step.via[index])
            if value ~= nil then copy.via[#copy.via + 1] = value end
        end
    end
    if type(step.path) == "table" then
        copy.path = {}
        for index = 1, #step.path do
            local point = CopyPoint(step.path[index])
            if point then copy.path[#copy.path + 1] = point end
        end
    end
    return type(copy.method) == "string" and copy or nil
end

-- State validation runs on noisy game events, so it must remain bounded. Do
-- not build Mapzeroth's graph here: even with its geometry cache, Build()
-- creates thousands of adjacency entries, and serializing those entries made
-- one validation allocate tens of megabytes. This streaming digest covers the
-- inputs that decide graph membership and costs without retaining per-edge
-- strings or tables.
local HASH_MOD_A = 2147483647
local HASH_MOD_B = 2147483629

local function NewStateHash()
    return { a = 5381, b = 52711, fields = 0 }
end

local function FeedText(hash, value)
    local text = value == nil and "" or tostring(value)
    for index = 1, #text do
        local byte = string.byte(text, index)
        hash.a = (hash.a * 33 + byte) % HASH_MOD_A
        hash.b = (hash.b * 65599 + byte) % HASH_MOD_B
    end
    hash.a = (hash.a * 33 + 255) % HASH_MOD_A
    hash.b = (hash.b * 65599 + 255) % HASH_MOD_B
    hash.fields = hash.fields + 1
end

local function FeedValue(hash, value)
    if not Accessible(value) then
        FeedText(hash, "secret")
        return
    end
    local kind = type(value)
    FeedText(hash, kind)
    if kind == "string" or kind == "number" or kind == "boolean" then
        FeedText(hash, value)
    end
end

local function FeedPoint(hash, label, point)
    FeedText(hash, label)
    FeedValue(hash, type(point) == "table" and point.id or nil)
    FeedValue(hash, type(point) == "table" and point.mapID or nil)
    FeedValue(hash, type(point) == "table" and point.x or nil)
    FeedValue(hash, type(point) == "table" and point.y or nil)
end

local function FeedFunctionResult(hash, label, fn, ...)
    FeedText(hash, label)
    if type(fn) ~= "function" then
        FeedText(hash, "missing")
        return true
    end
    local ok, value = pcall(fn, ...)
    if not ok then return false, tostring(value) end
    FeedValue(hash, value)
    return true
end

local function FeedAvailableTravelActions(hash, addon, ctx)
    local ok, abilities = Call(addon, "GetKnownTeleports", ctx)
    if not ok or type(abilities) ~= "table" then
        return false, tostring(abilities or "travel abilities unavailable")
    end
    FeedText(hash, "available")
    FeedValue(hash, #abilities)
    for index = 1, #abilities do
        local entry = abilities[index]
        if type(entry) ~= "table" then return false, "invalid travel ability" end
        FeedValue(hash, index)
        FeedValue(hash, entry.to)
        FeedValue(hash, entry.cost)
        FeedValue(hash, entry.method)
        FeedValue(hash, entry.loadingScreens)
        FeedValue(hash, entry.bias)
        local source = type(entry.ability) == "table" and entry.ability or nil
        for fieldIndex = 1, #SOURCE_FIELDS do
            FeedValue(hash, source and source[SOURCE_FIELDS[fieldIndex]] or nil)
        end
        local destinations = type(source) == "table" and source.toList or nil
        if type(destinations) == "table" then
            FeedValue(hash, #destinations)
            for destinationIndex = 1, #destinations do
                FeedValue(hash, destinations[destinationIndex])
            end
        else
            FeedValue(hash, 0)
        end
    end
    return true
end

local function FeedMovementState(hash, addon, ctx)
    local abilities = type(addon.Abilities) == "table" and addon.Abilities or nil
    local forms = abilities and abilities.GroundForms or nil
    FeedText(hash, "groundForms")
    if type(forms) == "table" then
        FeedValue(hash, #forms)
        for index = 1, #forms do
            local form = forms[index]
            if type(form) == "table" then
                local ok, reason = FeedFunctionResult(hash, "formKnown", ctx.knowsSpell, form.spellID)
                if not ok then return false, reason end
                local talents = form.talents
                if type(talents) == "table" then
                    for talentIndex = 1, #talents do
                        local talent = talents[talentIndex]
                        ok, reason = FeedFunctionResult(hash, "talentRank", ctx.talentRank, talent and talent.spellID)
                        if not ok then return false, reason end
                    end
                end
            end
        end
    else
        FeedValue(hash, 0)
    end
    local ridingSkillCount = type(addon.RidingSkills) == "table" and #addon.RidingSkills or 0
    for index = 1, ridingSkillCount do
        local skill = addon.RidingSkills[index]
        local ok, reason = FeedFunctionResult(hash, "ridingKnown", ctx.knowsSpell, skill and skill.spellID)
        if not ok then return false, reason end
    end
    local ok, multiplier = Call(addon, "GetFlightSpeedMultiplier", ctx)
    if not ok then return false, tostring(multiplier or "flight speed unavailable") end
    FeedText(hash, "flightSpeed")
    FeedValue(hash, multiplier)
    return true
end

local function FeedPhaseState(hash, addon, ctx)
    local world = addon.World
    if type(world) ~= "table" or type(world.LivePhases) ~= "function" then return false, "phase API unavailable" end
    local ok, phases = pcall(world.LivePhases, world, ctx.mapArtID, ctx.questCompleted)
    if not ok or type(phases) ~= "table" then return false, tostring(phases or "phase state unavailable") end
    local groups = {}
    for group in pairs(phases) do groups[#groups + 1] = group end
    table.sort(groups, function(a, b) return tostring(a) < tostring(b) end)
    FeedText(hash, "phases")
    FeedValue(hash, #groups)
    for index = 1, #groups do
        local group = groups[index]
        FeedValue(hash, group)
        FeedValue(hash, phases[group])
    end
    return true
end

local function FeedAuthoredEdgeState(hash, addon, ctx)
    local edges = type(addon.Edges) == "table" and addon.Edges or {}
    FeedText(hash, "authoredEdges")
    FeedValue(hash, #edges)
    for index = 1, #edges do
        local edge = edges[index]
        if type(edge) ~= "table" then return false, "invalid authored edge" end
        local ok, available = true, true
        if edge.requirements ~= nil then
            ok, available = pcall(addon.MeetsRequirements, addon, edge.requirements, ctx)
            if not ok then return false, tostring(available) end
            FeedText(hash, "requirements")
            FeedValue(hash, index)
            FeedValue(hash, available == true)
        end
        if edge.method == "taxi" then
            local reason
            FeedText(hash, "taxi")
            FeedValue(hash, index)
            ok, reason = FeedFunctionResult(hash, "flightFromFound", ctx.flightNodeFound, edge.from)
            if not ok then return false, reason end
            ok, reason = FeedFunctionResult(hash, "flightToFound", ctx.flightNodeFound, edge.to)
            if not ok then return false, reason end
            ok, reason = FeedFunctionResult(hash, "flightFromUsable", ctx.flightUsable, edge.from)
            if not ok then return false, reason end
            ok, reason = FeedFunctionResult(hash, "flightToUsable", ctx.flightUsable, edge.to)
            if not ok then return false, reason end
            ok, reason = FeedFunctionResult(hash, "fareFactor", ctx.fareFactor, edge.from)
            if not ok then return false, reason end
        end
    end
    return true
end

local function BuildStateFingerprint(addon, ctx)
    if type(addon) ~= "table" or type(ctx) ~= "table" then return nil, "state unavailable" end
    local hash = NewStateHash()
    FeedText(hash, "mapzeroth2")
    FeedValue(hash, addon.World and addon.World.generation)
    for index = 1, #CONTEXT_STATE_FIELDS do
        local key = CONTEXT_STATE_FIELDS[index]
        FeedText(hash, key)
        FeedValue(hash, ctx[key])
    end
    FeedPoint(hash, "hearthPlace", ctx.hearthPlace)
    FeedPoint(hash, "campPlace", ctx.campPlace)

    local options = addon.Options
    for index = 1, #ROUTE_OPTION_KEYS do
        local key = ROUTE_OPTION_KEYS[index]
        local ok, reason = FeedFunctionResult(hash, "option:" .. key, options and options.Get, options, key)
        if not ok then return nil, reason end
    end

    local ok, reason = FeedAvailableTravelActions(hash, addon, ctx)
    if not ok then return nil, reason end
    ok, reason = FeedMovementState(hash, addon, ctx)
    if not ok then return nil, reason end
    ok, reason = FeedPhaseState(hash, addon, ctx)
    if not ok then return nil, reason end
    ok, reason = FeedAuthoredEdgeState(hash, addon, ctx)
    if not ok then return nil, reason end

    return string.format("mz2:%08x:%08x:%d", hash.a, hash.b, hash.fields)
end

local function BuildContext(addon)
    local ok, ctx = Call(addon, "GetPlayerContext")
    if not ok or type(ctx) ~= "table" then return nil, ctx or "player context unavailable" end
    local upstreamEquippable = ctx.isEquippable
    local upstreamEquipped = ctx.isEquipped
    local upstreamHasItem = ctx.hasItem
    local function IsUpstreamEquippable(itemID)
        if type(upstreamEquippable) ~= "function" then return false end
        local success, value = pcall(upstreamEquippable, itemID)
        return success and value == true
    end
    local function IsUpstreamEquipped(itemID)
        if type(upstreamEquipped) ~= "function" then return false end
        local success, value = pcall(upstreamEquipped, itemID)
        return success and value == true
    end
    ctx.isEquippable = function(itemID)
        return IsUpstreamEquippable(itemID)
            and type(NS.CanExecuteRouteEquipmentItem) == "function"
            and NS.CanExecuteRouteEquipmentItem(itemID) == true
    end
    ctx.hasItem = function(itemID)
        local owns = false
        if type(upstreamHasItem) == "function" then
            local success, value = pcall(upstreamHasItem, itemID)
            owns = success and value == true
        end
        if not owns then return false end
        if IsUpstreamEquippable(itemID) and not IsUpstreamEquipped(itemID)
            and (type(NS.CanExecuteRouteEquipmentItem) ~= "function" or not NS.CanExecuteRouteEquipmentItem(itemID))
        then
            return false
        end
        return true
    end
    return ctx
end

function Private.ResolveNode(nodeID)
    local status = Private.GetCompatibilityStatus()
    if not status.compatible or type(nodeID) ~= "string" then return nil end
    local addon = Addon()
    local ok, node = Call(addon.World, "GetNode", nodeID)
    if not ok or type(node) ~= "table" then return nil end
    local copy = CopyPoint(node)
    if not copy then return nil end
    copy.kind = Scalar(node.kind)
    copy.container = Scalar(node.container)
    copy.interior = Scalar(node.interior)
    return copy
end

function Private.PlanRoute(request)
    if type(request) ~= "table" then return false, nil, { code = "invalid_request", message = "Invalid route request." } end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false, nil, { code = "combat", message = "Mapzeroth planning is deferred during combat." }
    end
    local status = Private.GetCompatibilityStatus()
    if not status.compatible then return false, nil, { code = "incompatible", message = status.reason, missing = status.missing } end
    local addon = Addon()
    local okStart, start, startReason = Call(addon, "GetPlayerStart")
    if not okStart or type(start) ~= "table" then
        return false, nil, { code = "missing_start", message = tostring(startReason or start or "No player start position.") }
    end
    local ctx, contextReason = BuildContext(addon)
    if not ctx then return false, nil, { code = "context", message = tostring(contextReason) } end
    local okPlace, destination = Call(addon, "PlaceAt", request.mapID, request.x, request.y, "AWP")
    if not okPlace or type(destination) ~= "table" then
        return false, nil, { code = "unsupported_destination", message = "Mapzeroth cannot place this destination." }
    end
    local okSession, session, buildReason = Call(addon.Journey, "Build", ctx, start, { destination })
    if not okSession or type(session) ~= "table" then
        return false, nil, { code = "build", message = tostring(buildReason or session or "Mapzeroth graph build failed.") }
    end
    local entry = { name = request.title or "Route", nodeID = destination.id, nodeIDs = { destination.id }, dest = destination }
    local okPlan, plan, hint = Call(addon.Journey, "PlanEntry", session, entry)
    if not okPlan or type(plan) ~= "table" then
        return false, nil, { code = "no_path", message = tostring(hint or plan or "Mapzeroth found no path.") }
    end
    local steps = {}
    for index = 1, #(type(plan.steps) == "table" and plan.steps or {}) do
        local step = CopyStep(plan.steps[index])
        if step then steps[#steps + 1] = step end
    end
    if #steps == 0 then return false, nil, { code = "empty_steps", message = "Mapzeroth returned no usable steps." } end
    local fingerprint, fingerprintReason = BuildStateFingerprint(addon, ctx)
    if not fingerprint then
        return false, nil, { code = "snapshot", message = tostring(fingerprintReason or "State snapshot failed.") }
    end
    return true, {
        steps = steps,
        start = CopyPoint(start),
        destination = CopyPoint(destination),
        cost = Scalar(plan.cost),
        fare = Scalar(plan.fare),
        stateFingerprint = fingerprint,
    }
end

function Private.SnapshotState()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return false, "combat" end
    local status = Private.GetCompatibilityStatus()
    if not status.compatible then return false, status.reason end
    local addon = Addon()
    local ctx, contextReason = BuildContext(addon)
    if not ctx then return false, contextReason end
    local fingerprint, fingerprintReason = BuildStateFingerprint(addon, ctx)
    if not fingerprint then return false, fingerprintReason end
    return true, fingerprint
end

function Private.RegisterOptionsCallback(callback)
    if Private._optionsCallbackRegistered or type(callback) ~= "function" then return false end
    local status = Private.GetCompatibilityStatus()
    local addon = Addon()
    if not status.compatible or type(addon.Options) ~= "table" or type(addon.Options.OnChange) ~= "function" then return false end
    local ok = pcall(addon.Options.OnChange, addon.Options, function(key)
        if ROUTE_OPTION[key] then callback(key) end
    end)
    if ok then Private._optionsCallbackRegistered = true end
    return ok
end

function Private.IsMakeCampSpell(spellID)
    local addon = Addon()
    if type(addon) ~= "table" or type(addon.IsMakeCamp) ~= "function" then return false end
    local ok, result = pcall(addon.IsMakeCamp, addon, spellID)
    return ok and result == true
end



local RouteSpecials = NS.RouteSpecials or {}

-- Route translation consumes only the copied values produced by the private
-- compatibility helpers above; mutable Mapzeroth objects never leave here.
local backend = { id = "mapzeroth" }
NS.RoutingBackend_Mapzeroth = backend

local MOVEMENT_ADVANCE_YARDS = 55
local COORD_EPSILON = 0.0005
local MAGE_TOWER_NODE = "STORMWIND_MAGE_TOWER_ENTRANCE"
local SANCTUM_NODES = {
    STORMWIND_PORTAL_ROOM_LOWER = true,
    STORMWIND_PORTAL_ROOM_UPPER = true,
    STORMWIND_DARK_PORTAL_BL_NPC = true,
}
local MOVEMENT = { walk = true, transition = true, fly = true, phaseswitch = true }
local TRANSPORT = { ship = true, zeppelin = true, tram = true }

local function IsCombatLocked()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function CoordsMatch(aMap, ax, ay, bMap, bx, by, epsilon)
    if type(RouteSpecials.CoordsMatch) == "function" then
        return RouteSpecials.CoordsMatch(aMap, ax, ay, bMap, bx, by, epsilon or COORD_EPSILON)
    end
    return aMap == bMap and type(ax) == "number" and type(ay) == "number"
        and type(bx) == "number" and type(by) == "number"
        and math.abs(ax - bx) <= (epsilon or COORD_EPSILON)
        and math.abs(ay - by) <= (epsilon or COORD_EPSILON)
end

local function DestinationSignature(mapID, x, y, title)
    return table.concat({ tostring(mapID), string.format("%.5f", x), string.format("%.5f", y), tostring(title or "") }, "|")
end

local function CurrentDestinationSignature(record)
    if type(record) ~= "table" then return nil end
    local dest = type(record.destination) == "table" and record.destination or record.target or record
    if type(dest) ~= "table" or type(dest.mapID) ~= "number" or type(dest.x) ~= "number" or type(dest.y) ~= "number" then return nil end
    return DestinationSignature(dest.mapID, dest.x, dest.y, dest.title)
end

function backend.GetCompatibilityStatus()
    return Private.GetCompatibilityStatus()
end

function backend.IsAvailable()
    return backend.GetCompatibilityStatus().compatible == true
end

local function Accept(record, legs, reason)
    if type(NS.AcceptBackendPlan) == "function" then return NS.AcceptBackendPlan(record, "mapzeroth", legs, reason) end
    record.backend, record.legs, record.currentLegIndex = "mapzeroth", legs, nil
    return true
end

local function DirectFallback(record, mapID, x, y, title, reason)
    record._mapzerothFallbackReason = reason
    return Accept(record, {{
        mapID = mapID, x = x, y = y, title = title,
        kind = "destination", routeLegKind = "destination", source = "mapzeroth",
    }}, reason or "mapzeroth_direct_fallback")
end

local function BuildPlanningRequest(record, mapID, x, y, title)
    local request = { mapID = mapID, x = x, y = y, title = title }
    local intent = type(NS.ResolveInstanceRouteIntent) == "function"
        and NS.ResolveInstanceRouteIntent(mapID, x, y, title) or nil
    local entrance = type(intent) == "table" and intent.entrance or nil
    if type(intent) == "table" and type(entrance) == "table" and type(entrance.mapID) == "number"
        and type(entrance.x) == "number" and type(entrance.y) == "number"
    then
        request.mapID, request.x, request.y = entrance.mapID, entrance.x, entrance.y
        request.title = title or intent["instanceName"]
        request.instanceRouteIntent = intent
        request.reason = "mapzeroth_instance_entrance_plan"
    else
        request.reason = "mapzeroth_plan"
    end
    request.final = { mapID = mapID, x = x, y = y, title = title }
    local metadata = type(record.destination) == "table" and record.destination
        or type(record.target) == "table" and record.target or record
    request.finalMetadata = type(metadata) == "table" and metadata or nil
    return request
end

local function ResolvePoint(nodeID, fallback)
    local node = Private.ResolveNode(nodeID)
    return node or (type(fallback) == "table" and fallback or nil)
end

local function StepEndpoints(step, result)
    local path = type(step.path) == "table" and step.path or nil
    local source = path and path[1] or ResolvePoint(step.fromID, result.start)
    local destination = path and path[#path] or ResolvePoint(step.nodeID, result.destination)
    return source, destination
end

local function IsSanctumNode(nodeID)
    return SANCTUM_NODES[nodeID] == true
        or (type(nodeID) == "string" and nodeID:match("^STORMWIND_.+_PORTAL$") ~= nil)
end

local function EnsureMageTowerEntry(legs)
    local node = Private.ResolveNode(MAGE_TOWER_NODE)
    local mapID, x, y
    if node then mapID, x, y = node.mapID, node.x, node.y
    elseif type(RouteSpecials.GetMageTowerEntryFallback) == "function" then mapID, x, y = RouteSpecials.GetMageTowerEntryFallback() end
    if type(RouteSpecials.EnsureMageTowerEntryBeforeWizardsSanctumLeg) == "function" then
        RouteSpecials.EnsureMageTowerEntryBeforeWizardsSanctumLeg(legs, "mapzeroth", mapID, x, y)
    end
end

local function MakeSpecialAction(step, activationCoords)
    local source = type(step.source) == "table" and step.source or nil
    if step.method == "equip" then
        local itemID = source and tonumber(source.itemID)
        if not itemID then return nil end
        return {
            semanticKind = "equip", executionType = "equip", itemID = itemID,
            name = step.text or step.name, destinationName = step.name,
            activationMode = "portable", sourceBackend = "mapzeroth",
            routeDependency = { kind = "item", id = itemID },
        }
    end
    if not source then return nil end
    local secureType, payload
    local spellID, itemID = tonumber(source.spellID), tonumber(source.itemID)
    if itemID and source.toy == true then secureType, payload = "toy", itemID
    elseif itemID then secureType, payload = "item", itemID
    elseif spellID then secureType, payload = "spell", spellID end
    if not secureType then return nil end
    local dependencyKind = secureType == "spell" and "spell" or secureType == "toy" and "toy" or "item"
    return {
        semanticKind = step.method == "hearthstone" and "hearthstone" or "teleport",
        secureType = secureType, securePayload = payload,
        name = step.text or step.name, destinationName = step.name,
        activationMode = activationCoords and "location" or "portable",
        activationCoords = activationCoords, activationRadiusYards = 15,
        sourceBackend = "mapzeroth", routeDependency = { kind = dependencyKind, id = payload },
    }
end

local function TravelType(method, request, isEntrance)
    if isEntrance and request.instanceRouteIntent then return request.instanceRouteIntent.travelType end
    if method == "taxi" then return "taxi" end
    if method == "portal" then return "portal" end
    if method == "hearthstone" then return "hearth" end
    if method == "teleport" or method == "equip" then return method end
    if TRANSPORT[method] then return method end
    return "travel"
end

local function StepToLeg(step, result, request)
    local sourcePoint, destinationPoint = StepEndpoints(step, result)
    local method = step.method
    local point = (method == "portal" or method == "taxi" or TRANSPORT[method] or method == "equip") and sourcePoint or destinationPoint
    if (method == "teleport" or method == "hearthstone") and sourcePoint then point = sourcePoint end
    if type(point) ~= "table" or type(point.mapID) ~= "number" or type(point.x) ~= "number" or type(point.y) ~= "number" then return nil end
    local activationCoords = sourcePoint and { mapID = sourcePoint.mapID, x = sourcePoint.x, y = sourcePoint.y } or nil
    if method == "teleport" or method == "hearthstone" or method == "equip" then activationCoords = nil end
    local isEntrance = request.instanceRouteIntent and destinationPoint
        and CoordsMatch(destinationPoint.mapID, destinationPoint.x, destinationPoint.y, request.mapID, request.x, request.y, 0.025)
    local leg = {
        mapID = point.mapID, x = point.x, y = point.y,
        kind = method, routeLegKind = "carrier", title = step.text or step.name or request.title,
        source = "mapzeroth", routeTravelType = TravelType(method, request, isEntrance),
        arrivalRadius = MOVEMENT[method] and MOVEMENT_ADVANCE_YARDS or 15,
        activationCoords = activationCoords, specialAction = MakeSpecialAction(step, activationCoords),
        mapzerothNodeID = step.nodeID, mapzerothFromID = step.fromID,
    }
    if method == "taxi" then
        leg.taxi = {
            nodeID = type(step.nodeID) == "string" and tonumber(step.nodeID:match("^TAXI_(%d+)$")) or nil,
            operator = "mapzeroth", final = false,
        }
    end
    return leg
end

local function ApplyFinalMetadata(leg, request)
    local metadata = request.finalMetadata
    if type(metadata) ~= "table" then return end
    for _, key in ipairs({ "areaPoiID", "journalInstanceID", "guideProvider", "rawTitle", "sourceKind" }) do
        local value = metadata[key]
        if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then leg[key] = value end
    end
end

local function AppendExactDestination(legs, request)
    local final, last = request.final, legs[#legs]
    if type(last) == "table" and CoordsMatch(last.mapID, last.x, last.y, final.mapID, final.x, final.y, COORD_EPSILON) then
        last.routeLegKind = "destination"
        last.title = final.title or last.title
        if MOVEMENT[last.kind] then last.routeTravelType = nil end
        ApplyFinalMetadata(last, request)
        return
    end
    local leg = {
        mapID = final.mapID, x = final.x, y = final.y, title = final.title or request.title,
        kind = "destination", routeLegKind = "destination", source = "mapzeroth",
        routeTravelType = request.instanceRouteIntent and request.instanceRouteIntent.travelType or nil,
        arrivalRadius = 15,
    }
    ApplyFinalMetadata(leg, request)
    legs[#legs + 1] = leg
end

local function MarkFinalTaxiLegs(legs)
    for index = 1, #legs do
        local taxi = legs[index].taxi
        if taxi and (not legs[index + 1] or not legs[index + 1].taxi) then taxi.final = true end
    end
end

local function SameAcceptedTarget(record, signature)
    return type(record) == "table" and record._mapzerothDestinationSignature == signature
        and type(record.legs) == "table" and #record.legs > 0
end

function backend.PlanRoute(record, mapID, x, y, title)
    if type(record) ~= "table" or type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return false end
    local signature = DestinationSignature(mapID, x, y, title)
    if IsCombatLocked() then
        backend._deferredPlan = { record = record, signature = signature }
        if SameAcceptedTarget(record, signature) then return true end
        record.backend, record._mapzerothDestinationSignature = "mapzeroth", signature
        return DirectFallback(record, mapID, x, y, title, "mapzeroth_combat_fallback")
    end
    local status = backend.GetCompatibilityStatus()
    if not status.compatible then
        record._mapzerothCompatibilityReason = status.reason
        return DirectFallback(record, mapID, x, y, title, "mapzeroth_incompatible_fallback")
    end
    local request = BuildPlanningRequest(record, mapID, x, y, title)
    local ok, result, failure = Private.PlanRoute(request)
    if not ok or type(result) ~= "table" then
        record._mapzerothLastFailure = type(failure) == "table" and failure or { message = tostring(failure) }
        local code = type(failure) == "table" and failure.code or "planner"
        return DirectFallback(record, mapID, x, y, title, "mapzeroth_" .. tostring(code) .. "_fallback")
    end
    local legs, sanctumQueued = {}, false
    local needsSanctumEntry = type(RouteSpecials.PlayerNeedsWizardsSanctumEntry) == "function"
        and RouteSpecials.PlayerNeedsWizardsSanctumEntry(result.start) or false
    for index = 1, #result.steps do
        local step = result.steps[index]
        local sanctum = IsSanctumNode(step.nodeID) or IsSanctumNode(step.fromID)
        if sanctum and needsSanctumEntry and not sanctumQueued then EnsureMageTowerEntry(legs); sanctumQueued = true end
        local leg = StepToLeg(step, result, request)
        if leg then
            if sanctum and type(RouteSpecials.MakeWizardsSanctumArrivalGate) == "function" then
                leg.arrivalGate = RouteSpecials.MakeWizardsSanctumArrivalGate()
            end
            legs[#legs + 1] = leg
        end
    end
    if #legs == 0 then return DirectFallback(record, mapID, x, y, title, "mapzeroth_invalid_steps_fallback") end
    AppendExactDestination(legs, request)
    MarkFinalTaxiLegs(legs)
    record.backend, record._mapzerothDestinationSignature = "mapzeroth", signature
    record._mapzerothFallbackReason, record._mapzerothCompatibilityReason, record._mapzerothLastFailure = nil, nil, nil
    local accepted = Accept(record, legs, request.reason)
    if accepted then record._routeBackendStateFingerprint = result.stateFingerprint end
    return accepted
end

function backend.PollCurrentLeg(record)
    return type(NS.PollNeutralRouteLeg) == "function" and NS.PollNeutralRouteLeg(record, "mapzeroth_poll") or false
end

function backend.Clear(record, reason)
    if type(record) ~= "table" then return end
    if type(NS.CancelRouteEquipmentTransaction) == "function" then NS.CancelRouteEquipmentTransaction(record, reason or "mapzeroth_clear") end
    if backend._deferredPlan and backend._deferredPlan.record == record then backend._deferredPlan = nil end
    if type(NS.ClearRouteTravelDependencies) == "function" then NS.ClearRouteTravelDependencies(record) end
    for _, key in ipairs({
        "legs", "currentLegIndex", "currentLeg", "specialAction", "replanReason", "_corePlanning",
        "_coreRoutePending", "planFingerprint", "lastPlanSkippedAt", "lastPlanSkipReason",
        "lastPlanSkipStatus", "lastPlanSkippedFingerprint", "routeOutcome", "routeOutcomeReason",
        "routeOutcomeAt", "_routeBackendStateFingerprint", "_mapzerothDestinationSignature",
        "_mapzerothFallbackReason", "_mapzerothCompatibilityReason", "_mapzerothLastFailure",
    }) do record[key] = nil end
end

local function ValidateState()
    if IsCombatLocked() then return false, "combat" end
    if type(NS.IsRouteEquipmentTransactionActive) == "function" and NS.IsRouteEquipmentTransactionActive() then
        return false, "equipment transaction"
    end
    return Private.SnapshotState()
end

function backend.OnPlanInvalidated(reason)
    if type(NS.RequestRouteBackendStateValidation) ~= "function" then return false end
    local requestClass = (reason == "SPELL_UPDATE_COOLDOWN" or reason == "BAG_UPDATE_COOLDOWN") and "cooldown" or "structural"
    return NS.RequestRouteBackendStateValidation("mapzeroth", reason or "mapzeroth_invalidated", requestClass)
end

local EVENTS = {
    "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "PLAYER_EQUIPMENT_CHANGED", "SPELLS_CHANGED",
    "NEW_TOY_ADDED", "HEARTHSTONE_BOUND", "TAXIMAP_OPENED", "TAXIMAP_CLOSED",
    "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "SKILL_LINES_CHANGED", "UPDATE_FACTION",
    "PLAYER_MONEY", "CALENDAR_UPDATE_EVENT_LIST",
    "ZONE_CHANGED_NEW_AREA", "SPELL_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED",
}

local function HandleDeferredPlan()
    local pending = backend._deferredPlan
    backend._deferredPlan = nil
    if type(pending) ~= "table" or type(pending.record) ~= "table" then return end
    local active = type(NS.GetActiveAuthorityRecord) == "function" and NS.GetActiveAuthorityRecord() or nil
    if type(active) ~= "table" or active ~= pending.record then return end
    if active["backend"] ~= "mapzeroth" or CurrentDestinationSignature(active) ~= pending.signature then return end
    if type(NS.ScheduleActiveRouteRefresh) == "function" then NS.ScheduleActiveRouteRefresh("mapzeroth_post_combat_plan") end
end

function backend.Initialize()
    if backend._eventFrame then return end
    if type(NS.RegisterRouteBackendStateValidator) == "function" then
        NS.RegisterRouteBackendStateValidator("mapzeroth", ValidateState, NS.ProbeRouteTravelDependency)
    end
    local frame = CreateFrame("Frame")
    backend._eventFrame = frame
    for index = 1, #EVENTS do pcall(frame.RegisterEvent, frame, EVENTS[index]) end
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    frame:SetScript("OnEvent", function(_, event, _, _, spellID)
        if event == "PLAYER_REGEN_ENABLED" then NS.After(0, HandleDeferredPlan); return end
        if event == "UNIT_SPELLCAST_SUCCEEDED" and not Private.IsMakeCampSpell(spellID) then return end
        backend.OnPlanInvalidated(event)
    end)
    Private.RegisterOptionsCallback(function(key)
        backend.OnPlanInvalidated("MAPZEROTH_OPTION_" .. tostring(key))
    end)
end
