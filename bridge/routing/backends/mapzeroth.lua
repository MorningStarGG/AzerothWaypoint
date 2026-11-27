-- ============================================================
-- Mapzeroth routing backend
-- ============================================================
--
-- Builds AWP routes from Mapzeroth's travel and road data and coordinates
-- ownership of native navigation. The adapter reads Mapzeroth planner data
-- while AWP owns navigation, including route handoffs during corpse runs.

local NS = _G.AzerothWaypointNS

-- ============================================================
-- Walking state and required planner methods
-- ============================================================

local Private = {}
local Walking = NS.Internal.RouteWalking
local ROAD_RECOVERY = { interval = 2, retrySeconds = 15, retryDistance = 25 }
Private.roadCounters = { expanded = 0, points = 0, failed = 0 }

local REQUIRED = {
    { "GetPlayerStart" },
    { "PlaceAt" },
    { "GetPlayerContext" },
    { "GetKnownTeleports" },
    { "GetFlightSpeedMultiplier" },
    { "MeetsRequirements" },
    { "Journey",                 "Build" },
    { "Journey",                 "PlanEntry" },
    { "World",                   "GetNode" },
    { "World",                   "LivePhases" },
    { "TravelGraph",             "Build" },
    { "HasNodeName" },
}

local NAVIGATION_REQUIRED = {
    { "Panel",          "StartRoute" }, { "Panel", "RouteToQuest" },
    { "WaypointPrompt", "OnWaypointChanged" }, { "WaypointPrompt", "ShowQuest" },
    { "WaypointPrompt", "Answer" }, { "WaypointPrompt", "IsQuestShown" },
    { "WaypointPrompt", "Hide" }, { "WaypointPrompt", "Settle" },
    { "Corpse",    "Lead" }, { "GetCorpseTarget" }, { "QuestArrow", "Route" },
    { "Navigator", "Resume" }, { "Navigator", "Stop" }, { "MultiRoute", "Run" },
    { "Navigation", "IsActive" },
}

local ROUTE_OPTION_KEYS = { "loadingScreenTax", "maxCooldown", "assumeFlightsFound", "roadPreference", "reagentSaving" }
local ROUTE_OPTION = {}
for _, key in ipairs(ROUTE_OPTION_KEYS) do ROUTE_OPTION[key] = true end

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

---@param addon table
---@param contract string[][]
local function MissingCapability(addon, contract)
    for _, path in ipairs(contract) do
        if type(ResolvePath(addon, path)) ~= "function" then return table.concat(path, ".") end
    end
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
    status.missing = MissingCapability(addon, REQUIRED) or MissingCapability(addon, NAVIGATION_REQUIRED)
    if status.missing then
        status.compatible = false
        status.reason = "Mapzeroth is missing required capability " .. status.missing .. "."
        return status
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
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number"
        or x ~= x or y ~= y or x < 0 or x > 1 or y < 0 or y > 1 then
        return nil
    end
    return { id = id, mapID = mapID, x = x, y = y }
end

local function Finite(value)
    return Accessible(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function RoadPoint(addon, point, maps)
    local copy = CopyPoint(point)
    local world = type(point.world) == "table" and point.world
    local wx, wy, c
    if world then
        wx, wy, c = Scalar(world.x), Scalar(world.y), Scalar(world.continent)
    elseif addon.TravelGraph and type(addon.TravelGraph.WorldPosition) == "function" then
        local ok
        ok, wx, wy, c = pcall(addon.TravelGraph.WorldPosition, point)
        if not ok then return end
    end
    if not Finite(wx) or not Finite(wy) or not Finite(c) then return end
    if not copy and addon.Navigation and type(addon.Navigation.MapPoint) == "function" then
        for _, mapID in ipairs(maps) do
            local ok, x, y = pcall(addon.Navigation.MapPoint, point, mapID)
            if ok and Finite(x) and Finite(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                copy = { mapID = mapID, x = x, y = y }; break
            end
        end
    end
    if not copy then return end
    copy.wx, copy.wy, copy.c, copy.anchor = wx, wy, c, not world
    copy.required = false
    if copy.anchor then
        local milestoneOK, milestone = Call(addon.World, "IsMilestone", copy.id)
        local containerOK, container = Call(addon.World, "GetNodeContainer", copy.id)
        local indoorOK, indoor = Call(addon.World, "GetFlag", containerOK and container, "indoor")
        copy.required = milestoneOK and Scalar(milestone) == true or indoorOK and Scalar(indoor) == true
            or Scalar(point.interior) == true or Scalar(point.kind) == "entrance"
    end
    return copy
end

-- ============================================================
-- Walking geometry and source data
-- ============================================================

local function CopyWalkingPoints(addon, path, maps)
    local points = {}
    for _, point in ipairs(path) do
        if type(point) ~= "table" then return end
        local copy = RoadPoint(addon, point, maps)
        local last = points[#points]
        if not copy or last and copy.c ~= last.c then
            return
        end
        if not copy.anchor then points.roads = true end
        if last and last.wx == copy.wx and last.wy == copy.wy then
            if copy.anchor then points[#points] = copy end
        else
            local before = points[#points - 1]
            if before and not last.anchor then
                local ax, ay = last.wx - before.wx, last.wy - before.wy
                local bx, by = copy.wx - last.wx, copy.wy - last.wy
                if math.abs(ax * by - ay * bx) < 0.000001 and ax * bx + ay * by >= 0 then points[#points] = nil end
            end
            points[#points + 1] = copy
        end
    end
    if #points < 2 then return end
    points[1].required, points[#points].required = true, true
    return points
end

-- Called only while copying a freshly planned walk. Never cache native plan
-- tables or expand roads from the validation/movement paths.
local function CopyWalkingPath(addon, step)
    local path = step.path
    if type(path) ~= "table" or #path < 2 or #path > 8192 then return end
    local maps, seen = {}, {}
    for _, point in ipairs(path) do
        if type(point) ~= "table" then
            Private.roadCounters.failed = Private.roadCounters.failed + 1; return
        end
        local mapID = Scalar(point.mapID)
        for _ = 1, 16 do
            if type(mapID) ~= "number" or not Finite(mapID) or seen[mapID] then break end
            seen[mapID], maps[#maps + 1] = true, mapID
            local ok, info = false, nil
            if C_Map and type(C_Map.GetMapInfo) == "function" then ok, info = pcall(C_Map.GetMapInfo, mapID) end
            mapID = ok and type(info) == "table" and Scalar(info.parentMapID) or nil
            if mapID == 0 then break end
        end
    end
    local expanded = path
    if addon.RoadData and addon.RoadNet and type(addon.RoadNet.Expand) == "function" then
        local ok, value = pcall(addon.RoadNet.Expand, addon.RoadNet, path)
        if not ok or type(value) ~= "table" or #value < 2 or #value > 8192 then
            Private.roadCounters.failed = Private.roadCounters.failed + 1
            return CopyWalkingPoints(addon, path, maps)
        end
        expanded = value
    end
    local points = CopyWalkingPoints(addon, expanded, maps)
    if not points then
        Private.roadCounters.failed = Private.roadCounters.failed + 1
        return CopyWalkingPoints(addon, path, maps)
    end
    Private.roadCounters.expanded = Private.roadCounters.expanded + 1
    Private.roadCounters.points = Private.roadCounters.points + #points
    return points
end

local SOURCE_FIELDS = {
    "id", "name", "method", "spellID", "itemID", "toy", "to", "cost", "cooldown",
    "equipSeconds", "equipCooldown", "loadingScreens", "consumable", "sharedCooldown", "faction",
}
local CONTEXT_STATE_FIELDS = {
    "faction", "class", "race", "raceID", "level", "loadingScreenTax", "maxCooldown", "money", "hearthNode",
    "ghost", "ghostSpeed",
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

-- A native direct flight edge proves more than a flyable-map flag: the
-- graph already excludes walls and incompatible phases. Copy only its proof.
local function AirborneProof(addon, step, session, points)
    local graph = session and session.graph
    local path = step.path
    if not graph or type(graph.adjacency) ~= "table" or not points
        or type(path) ~= "table" or #path < 2 then
        return
    end
    local from, to = path[1], path[#path]
    local fromID, toID = Scalar(from.id), Scalar(to.id)
    if type(fromID) ~= "string" or type(toID) ~= "string" or Scalar(from.mapID) ~= Scalar(to.mapID) then return end
    local approved = false
    for _, edge in ipairs(graph.adjacency[fromID] or {}) do
        if Scalar(edge.to) == toID and Scalar(edge.method) == "fly" and edge.inPhase == nil then
            approved = true; break
        end
    end
    if not approved then return end
    local containerPath
    for _, point in ipairs(path) do
        local ok, container = Call(addon.World, "GetNodeContainer", Scalar(point.id))
        if not ok or not container then
            ok, container = Call(addon.World, "GetContainerForMap", Scalar(point.mapID),
                graph.phase)
        end
        if not ok or type(container) ~= "table" or type(Scalar(container.path)) ~= "string" then return end
        local flyOK, fly = Call(addon.World, "GetFlag", container, "fly")
        local indoorOK, indoor = Call(addon.World, "GetFlag", container, "indoor")
        local phaseOK, phase = Call(addon.World, "GetPhase", container)
        local milestoneOK, milestone = Call(addon.World, "IsMilestone", Scalar(point.id))
        if not flyOK or Scalar(fly) ~= true or not indoorOK or Scalar(indoor) ~= false or not phaseOK or phase ~= nil
            or not milestoneOK or milestone == true or containerPath and containerPath ~= container.path then
            return
        end
        containerPath = container.path
    end
    for index = 2, #points - 1 do if points[index].required then return end end
    return { mapID = Scalar(from.mapID), container = containerPath }
end

local FOREVER_SANCTUM_OUTER = "ENTRANCE_SW_WIZARDS_SANCTUM_OUTER"
local FOREVER_SANCTUM_INNER = "ENTRANCE_SW_WIZARDS_SANCTUM_INNER"

local function IsForeverDoorway(from, to)
    return from == FOREVER_SANCTUM_OUTER and to == FOREVER_SANCTUM_INNER
        or from == FOREVER_SANCTUM_INNER and to == FOREVER_SANCTUM_OUTER
end

local function CopyStep(step, addon, session)
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
    if copy.method == "walk" then
        copy.walking = CopyWalkingPath(addon, step)
        if copy.walking then copy.walking.airborne = AirborneProof(addon, step, session, copy.walking) end
    end
    return type(copy.method) == "string" and copy or nil
end

-- The "readable" native plan can merge the doorway into a walk or hide
-- its zero-cost step. Recover that exact edge from the same plan's raw
-- itinerary. Expand native road geometry separately on each side.
local function CopyPlanSteps(plan, addon, session, forever)
    local steps, doors = {}, nil
    if forever and type(plan.raw) == "table" then
        for _, edge in ipairs(plan.raw) do
            if type(edge) == "table" and Scalar(edge.method) == "walk"
                and IsForeverDoorway(Scalar(edge.from), Scalar(edge.to)) then
                doors = doors or {}
                doors[edge.to] = edge.from
            end
        end
    end
    local function Add(step)
        local copy = CopyStep(step, addon, session)
        if copy then steps[#steps + 1] = copy end
    end
    local function AddDoorway(from, to)
        Add({ method = "walk", fromID = from, nodeID = to })
        if doors then doors[to] = nil end
    end
    for _, step in ipairs(type(plan.steps) == "table" and plan.steps or {}) do
        if type(step) == "table" and doors and Scalar(step.method) == "walk" then
            local from = Scalar(step.fromID)
            if from and doors[from] then AddDoorway(doors[from], from) end
            local path = step.path
            local first = 1
            if type(path) == "table" then
                for i = 2, #path do
                    local left, right = path[i - 1], path[i]
                    left = type(left) == "table" and Scalar(left.id)
                    right = type(right) == "table" and Scalar(right.id)
                    if right and doors[right] == left and IsForeverDoorway(left, right) then
                        if i - 1 > first then
                            local segment = {}
                            for j = first, i - 1 do segment[#segment + 1] = path[j] end
                            Add({ method = "walk", fromID = from, nodeID = left, path = segment })
                        end
                        AddDoorway(left, right)
                        first, from = i, right
                    end
                end
            end
            if first == 1 then
                Add(step)
                if IsForeverDoorway(from, Scalar(step.nodeID)) then doors[step.nodeID] = nil end
            elseif first < #path then
                local segment = {}
                for j = first, #path do segment[#segment + 1] = path[j] end
                Add({
                    method = "walk",
                    fromID = from,
                    nodeID = step.nodeID,
                    path = segment,
                    name = step.name,
                    text = step.text
                })
            end
        else
            if doors and type(step) == "table" then
                local from = Scalar(step.fromID)
                if from and doors[from] then AddDoorway(doors[from], from) end
            end
            Add(step)
        end
    end
    if doors then
        local goal = Scalar(plan.goal)
        if goal and doors[goal] then AddDoorway(doors[goal], goal) end
    end
    return steps
end

-- State validation runs on noisy game events, so it must remain bounded. Do
-- not build Mapzeroth's graph here: even with its geometry cache, Build()
-- creates thousands of adjacency entries, and serializing those entries made
-- one validation allocate tens of megabytes. This streaming digest covers the
-- inputs that decide graph membership and costs without retaining per-edge
-- strings or tables.
local HASH_MOD_A = 2147483647
local HASH_MOD_B = 2147483629

-- ============================================================
-- Travel state fingerprints
-- ============================================================

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

-- ============================================================
-- Planner nodes and route context
-- ============================================================

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

local function UnavailableCooldown() return math.huge end

function Private.PlanRoute(request)
    if type(request) ~= "table" then return false, nil, { code = "invalid_request", message = "Invalid route request." } end
    local combat = InCombatLockdown and InCombatLockdown()
    local status = Private.GetCompatibilityStatus()
    if not status.compatible then
        return false, nil,
            { code = "incompatible", message = status.reason, missing = status.missing }
    end
    local addon = Addon()
    local okStart, start, startReason = Call(addon, "GetPlayerStart")
    if not okStart or type(start) ~= "table" then
        return false, nil,
            { code = "missing_start", message = tostring(startReason or start or "No player start position.") }
    end
    local ctx, contextReason = BuildContext(addon)
    if not ctx then return false, nil, { code = "context", message = tostring(contextReason) } end
    if combat then
        -- Native ability selection treats an unknown cooldown as ready. Limit
        -- only this search's portable actions while keeping the world graph.
        ctx.cooldownRemaining, ctx.itemCooldownRemaining = UnavailableCooldown, UnavailableCooldown
    end
    local okPlace, destination = Call(addon, "PlaceAt", request.mapID, request.x, request.y, "AWP")
    if not okPlace or type(destination) ~= "table" then
        return false, nil, { code = "unsupported_destination", message = "Mapzeroth cannot place this destination." }
    end
    -- PlaceAt rounds the node ID. Independent clicks in the same cell still
    -- need their own projection and should stay out of Mapzeroth's node cache.
    destination.nocache = true
    local okSession, session, buildReason = Call(addon.Journey, "Build", ctx, start, { destination })
    if not okSession or type(session) ~= "table" then
        return false, nil,
            { code = "build", message = tostring(buildReason or session or "Mapzeroth graph build failed.") }
    end
    local entry = {
        name = request.title or "Route",
        nodeID = destination.id,
        nodeIDs = { destination.id },
        dest =
            destination
    }
    local okPlan, plan, hint = Call(addon.Journey, "PlanEntry", session, entry)
    if not okPlan then return false, nil, { code = "planner", message = tostring(plan) } end
    if type(plan) ~= "table" then
        return false, nil, { code = "no_path", message = tostring(hint or plan or "Mapzeroth found no path.") }
    end
    local steps = CopyPlanSteps(plan, addon, session, NS.IsWoWForever and NS.IsWoWForever() and not ctx.ghost)
    if #steps == 0 then return false, nil, { code = "empty_steps", message = "Mapzeroth returned no usable steps." } end
    local fingerprint, fingerprintReason = NS.RouteSpecials.COMBAT_TRAVEL_STATE, nil
    if not combat then fingerprint, fingerprintReason = BuildStateFingerprint(addon, ctx) end
    if not fingerprint then
        return false, nil, { code = "snapshot", message = tostring(fingerprintReason or "State snapshot failed.") }
    end
    local preferenceOK, preference = Call(addon.Options, "Get", "roadPreference")
    return true, {
        steps = steps,
        start = CopyPoint(start),
        destination = CopyPoint(destination),
        cost = Scalar(plan.cost),
        fare = Scalar(plan.fare),
        stateFingerprint = fingerprint,
        ghost = ctx.ghost == true,
        roadPreference = preferenceOK and Scalar(preference) or nil,
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
-- compatibility helpers above, mutable Mapzeroth objects never leave here.
local backend = { id = "mapzeroth", counters = Private.roadCounters }
NS.RoutingBackend_Mapzeroth = backend
local walkingStates = setmetatable({}, { __mode = "k" })

local MOVEMENT_ADVANCE_YARDS = 55
local COORD_EPSILON = 0.0005
local MAGE_TOWER_NODE = "STORMWIND_MAGE_TOWER_ENTRANCE"
local function ForeverSanctumCrossing(step)
    local sanctum = RouteSpecials.Sanctum
    if not sanctum then return end
    local from, to = step.fromID, step.nodeID
    if IsForeverDoorway(from, to) then
        return sanctum.ForeverDoorway(from == FOREVER_SANCTUM_OUTER)
    end
    if step.method == "portal" and from == "PORTAL_DALARAN_STORMWIND" and to == "PORTAL_STORMWIND_DALARAN" then
        return sanctum.ForeverPortalArrival()
    end
end
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

function backend.GetCompatibilityStatus()
    return Private.GetCompatibilityStatus()
end

function backend.GetReadiness()
    if not IsLoaded() then return "unavailable", "mapzeroth_not_loaded" end
    local addon = Addon()
    if type(addon) ~= "table" then return "unavailable", "mapzeroth_missing_addon" end
    local missing = MissingCapability(addon, REQUIRED) or MissingCapability(addon, NAVIGATION_REQUIRED)
    if missing then return "unavailable", "mapzeroth_missing_" .. missing end
    if type(addon.World.generation) == "number" and addon.World.generation > 0 then return "ready" end
    if type(addon.World.Build) == "function" then return "waiting", "mapzeroth_world_initializing" end
    return "unavailable", "mapzeroth_missing_world_builder"
end

function backend.IsAvailable()
    return backend.GetReadiness() == "ready"
end

local observedWorlds = setmetatable({}, { __mode = "k" })
function backend.InstallReadinessHooks(notify)
    local addon = Addon()
    local world = addon and addon.World
    if not world or observedWorlds[world] or type(world.Build) ~= "function" then return end
    hooksecurefunc(world, "Build", notify)
    observedWorlds[world] = true
end

local function Accept(record, legs, reason)
    return RouteSpecials.CompletePlan(record, "mapzeroth", "success", legs, reason)
end

local function ReportFailure(record, reason)
    return RouteSpecials.CompletePlan(record, "mapzeroth", "failed", nil, reason)
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

-- ============================================================
-- Translating route steps
-- ============================================================

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
    if node then
        mapID, x, y = node.mapID, node.x, node.y
    elseif type(RouteSpecials.GetMageTowerEntryFallback) == "function" then
        mapID, x, y = RouteSpecials.GetMageTowerEntryFallback()
    end
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
            semanticKind = "equip",
            executionType = "equip",
            itemID = itemID,
            name = step.text or step.name,
            destinationName = step.name,
            activationMode = "portable",
            sourceBackend = "mapzeroth",
            routeDependency = { kind = "item", id = itemID },
        }
    end
    if not source then return nil end
    local secureType, payload
    local spellID, itemID = tonumber(source.spellID), tonumber(source.itemID)
    if itemID and source.toy == true then
        secureType, payload = "toy", itemID
    elseif itemID then
        secureType, payload = "item", itemID
    elseif spellID then
        secureType, payload = "spell", spellID
    end
    if not secureType then return nil end
    local dependencyKind = secureType == "spell" and "spell" or secureType == "toy" and "toy" or "item"
    return {
        semanticKind = step.method == "hearthstone" and "hearthstone" or "teleport",
        secureType = secureType,
        securePayload = payload,
        name = step.text or step.name,
        destinationName = step.name,
        activationMode = activationCoords and "location" or "portable",
        activationCoords = activationCoords,
        activationRadiusYards = 15,
        sourceBackend = "mapzeroth",
        routeDependency = { kind = dependencyKind, id = payload },
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

local function StepToLeg(step, result, request, crossing)
    local sourcePoint, destinationPoint = StepEndpoints(step, result)
    local method = step.method
    local point = (method == "portal" or method == "taxi" or TRANSPORT[method] or method == "equip") and sourcePoint or
        destinationPoint
    if crossing or (method == "teleport" or method == "hearthstone") and sourcePoint then
        point = sourcePoint
    end
    if type(point) ~= "table" or type(point.mapID) ~= "number" or type(point.x) ~= "number" or type(point.y) ~= "number" then return nil end
    local activationCoords = sourcePoint and { mapID = sourcePoint.mapID, x = sourcePoint.x, y = sourcePoint.y } or nil
    if method == "teleport" or method == "hearthstone" or method == "equip" then activationCoords = nil end
    local isEntrance = request.instanceRouteIntent and destinationPoint
        and
        CoordsMatch(destinationPoint.mapID, destinationPoint.x, destinationPoint.y, request.mapID, request.x, request.y,
            0.025)
    local leg = {
        mapID = point.mapID,
        x = point.x,
        y = point.y,
        kind = method,
        routeLegKind = "carrier",
        title = step.text or step.name or request.title,
        source = "mapzeroth",
        routeTravelType = TravelType(method, request, isEntrance),
        arrivalRadius = MOVEMENT[method] and MOVEMENT_ADVANCE_YARDS or 15,
        activationCoords = activationCoords,
        specialAction = MakeSpecialAction(step, activationCoords),
        mapzerothNodeID = step.nodeID,
        mapzerothFromID = step.fromID,
    }
    if crossing then
        if method == "walk" then
            leg.kind, leg.arrivalRadius = "entrance", 15
            leg.title = crossing.title
        end
        RouteSpecials.Sanctum.SetCrossing(leg, crossing)
    end
    if method == "taxi" then
        leg.taxi = {
            sourceNodeID = type(step.fromID) == "string" and tonumber(step.fromID:match("^TAXI_(%d+)$")) or nil,
            nodeID = type(step.nodeID) == "string" and tonumber(step.nodeID:match("^TAXI_(%d+)$")) or nil,
            operator = "mapzeroth",
            final = false,
        }
    end
    return leg
end

local function AppendWalkingLegs(legs, step, endpoint, nextStep)
    local points = step.walking
    local addon = Addon()
    local ok, named = Call(addon, "HasNodeName", step.nodeID)
    local approach = nextStep and nextStep.method ~= "walk"
    local first, last = step.path and step.path[1], step.path and step.path[#step.path]
    local crossing = first and last and type(first.mapID) == "number" and type(last.mapID) == "number"
        and first.mapID ~= last.mapID
    local mode = points and points.roads and "road" or "path"
    NS.Internal.RouteWalkingPresentation.Describe(endpoint, mode, endpoint,
        (ok and named or approach or crossing) and step.name or nil,
        (ok and named or approach or crossing) and step.text or nil)
    for _, leg in ipairs(NS.Internal.RouteWalking.BuildFixedLegs(points, endpoint, "mapzeroth",
        points and points.roads and "Follow the road" or "Follow the path")) do legs[#legs + 1] = leg end
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
    local sameEndpoint = type(last) == "table" and not last.sanctumCrossing and (last.kind == "walk"
        and RouteSpecials.SameWalkingEndpoint(last, final)
        or last.kind ~= "walk" and CoordsMatch(last.mapID, last.x, last.y, final.mapID, final.x, final.y, COORD_EPSILON))
    if sameEndpoint then
        last.routeLegKind = "destination"
        last.title = final.title or last.title
        if MOVEMENT[last.kind] then
            last.routeTravelType = nil
            if last.kind == "walk" then last.mapID, last.x, last.y = final.mapID, final.x, final.y end
        end
        ApplyFinalMetadata(last, request)
        return
    end
    local leg = RouteSpecials.MakeDestinationLeg("mapzeroth", final.mapID, final.x, final.y, final.title or request
        .title)
    leg.routeTravelType = request.instanceRouteIntent and request.instanceRouteIntent.travelType or nil
    leg.arrivalRadius = 15
    ApplyFinalMetadata(leg, request)
    legs[#legs + 1] = leg
end

local function MarkFinalTaxiLegs(legs)
    for index = 1, #legs do
        local taxi = legs[index].taxi
        if taxi and (not legs[index + 1] or not legs[index + 1].taxi) then taxi.final = true end
    end
end


local function PlanRoute(record, mapID, x, y, title)
    if type(record) ~= "table" or type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return false end
    local status = backend.GetCompatibilityStatus()
    if not status.compatible then
        return ReportFailure(record, "mapzeroth_incompatible_fallback")
    end
    local request = BuildPlanningRequest(record, mapID, x, y, title)
    local ok, result, failure = Private.PlanRoute(request)
    if not ok or type(result) ~= "table" then
        local code = type(failure) == "table" and failure.code or "planner"
        if code == "no_path" and IsCombatLocked() then
            return RouteSpecials.CompletePlan(record, "mapzeroth", "deferred", nil, "combat")
        end
        return ReportFailure(record, "mapzeroth_" .. tostring(code) .. "_fallback")
    end
    local legs, sanctumQueued = {}, false
    local forever = NS.IsWoWForever and NS.IsWoWForever()
    local needsSanctumEntry = not forever and not result.ghost
        and type(RouteSpecials.PlayerNeedsWizardsSanctumEntry) == "function"
        and RouteSpecials.PlayerNeedsWizardsSanctumEntry(result.start) or false
    for index = 1, #result.steps do
        local step = result.steps[index]
        local sanctum = not forever and (IsSanctumNode(step.nodeID) or IsSanctumNode(step.fromID))
        local crossing = forever and not result.ghost and ForeverSanctumCrossing(step) or nil
        if sanctum and needsSanctumEntry and not sanctumQueued then
            EnsureMageTowerEntry(legs); sanctumQueued = true
        end
        local leg = StepToLeg(step, result, request, crossing)
        if leg then
            if not result.ghost and sanctum and type(RouteSpecials.MakeWizardsSanctumArrivalGate) == "function" then
                leg.arrivalGate = RouteSpecials.MakeWizardsSanctumArrivalGate()
            end
            if step.method == "walk" and not crossing then
                AppendWalkingLegs(legs, step, leg, result.steps[index + 1])
            else
                legs[#legs + 1] = leg
            end
        end
    end
    if #legs == 0 then return ReportFailure(record, "mapzeroth_invalid_steps_fallback") end
    AppendExactDestination(legs, request)
    MarkFinalTaxiLegs(legs)
    record.backend = "mapzeroth"
    record._mapzerothRoadPreference = result.roadPreference
    local accepted = Accept(record, legs, request.reason)
    if accepted then record._routeBackendStateFingerprint = result.stateFingerprint end
    return accepted
end

-- ============================================================
-- Planning and walking progress
-- ============================================================

function backend.BeginPlan(attempt)
    return PlanRoute(attempt.record, attempt.mapID, attempt.x, attempt.y, attempt.title)
end

function backend.AdoptPlan(attempt, owner)
    Walking.CancelRecovery(walkingStates[owner])
    walkingStates[owner] = nil
    owner._routeBackendStateFingerprint = attempt.record._routeBackendStateFingerprint
    owner._mapzerothRoadPreference = attempt.record._mapzerothRoadPreference
end

function backend.ReleasePlan(record)
    Walking.CancelRecovery(walkingStates[record])
    walkingStates[record] = nil
end

function backend.WantsNavigationProgress(record)
    return record.backend == "mapzeroth" and record.currentLeg and record.currentLeg.fixedWalkingGeometry == true
end

function backend.ReadNavigationProgress()
    local ok, map, x, y = pcall(NS.GetPlayerMapPosition)
    if ok then return map, x, y end
end

function backend.CanFlyWalkingSection(record, group)
    local proof = group.airborne
    if not proof or IsCombatLocked() then return false end
    local addon = Addon()
    local startOK, start = Call(addon, "GetPlayerStart")
    if not startOK or type(start) ~= "table" or Scalar(start.mapID) ~= proof.mapID then return false end
    local containerOK, container = Call(addon.World, "GetContainerForMap", proof.mapID)
    if not containerOK or type(container) ~= "table" or Scalar(container.path) ~= proof.container then return false end
    local flyOK, fly = Call(addon.World, "GetFlag", container, "fly")
    local indoorOK, indoor = Call(addon.World, "GetFlag", container, "indoor")
    local phaseOK, phase = Call(addon.World, "GetPhase", container)
    return flyOK and Scalar(fly) == true and indoorOK and Scalar(indoor) == false and phaseOK and phase == nil
end

function backend.StopNavigationProgress(record, generation)
    local s = walkingStates[record]
    if s and (s.generation == nil or s.generation == generation) then
        Walking.CancelRecovery(s)
        walkingStates[record] = nil
    end
end

function backend.PollNavigationLeg(record, sampled, map, x, y, _, observedAt)
    local leg = record and record.currentLeg
    local walk = leg and leg.walking
    local state = walkingStates[record]
    if not walk or IsCombatLocked() or NS.State.routing.specialActionCasting
        or NS.IsRouteEquipmentTransactionActive and NS.IsRouteEquipmentTransactionActive()
        or not NS.IsActiveRouteRecord(record, false) then
        if state then state.progressAt, state.lastRejection = nil, "no_eligible_segment" end
        return false
    end
    if not sampled then map, x, y = backend.ReadNavigationProgress() end
    if not state then
        state = {}; walkingStates[record] = state
    end
    state.leg, state.generation = leg, record._routeAcceptedPlanGeneration
    if not map or not x or not y then
        state.progressAt = nil; return false
    end
    local ok, c, wx, wy = pcall(NS.GetWorldPositionFromMapCoords, map, x, y)
    if not ok or c ~= walk.to.c or not Finite(wx) or not Finite(wy) then
        state.progressAt = nil; return false
    end
    local nextLeg = record.legs[(record.currentLegIndex or 1) + 1]
    local nextWalk = nextLeg and nextLeg.walking
    if not walk.required and nextWalk and nextWalk.group == walk.group and not nextLeg.specialAction
        and Walking.Progress(state, record, c, wx, wy, nil, observedAt) then
        return true
    end
    local reason = Walking.Deviation(walk, c, wx, wy, nil, 60)
    if not reason then
        Walking.CancelRecovery(state); return false
    end
    local ticket = Walking.BeginRecovery(state, record, c, wx, wy, nil, ROAD_RECOVERY, reason)
    if ticket then
        ticket.cancel = function() NS.CancelRouteGeometryRefresh(record, ticket) end
        local started = NS.RequestRouteGeometryRefresh(record, ticket, function(success, failure)
            Walking.CompleteRecovery(state, ticket, success, failure)
        end, function()
            local m, px, py = backend.ReadNavigationProgress()
            if not m or not px or not py then return false end
            local valid, cc, xx, yy = pcall(NS.GetWorldPositionFromMapCoords, m, px, py)
            return valid and Walking.OriginMatches(ticket, cc, xx, yy, nil, 25)
        end)
        if not started then Walking.CompleteRecovery(state, ticket, false, "planner_busy") end
    end
    return false
end

function backend.Clear(record, reason)
    if type(record) ~= "table" then return end
    Walking.CancelRecovery(walkingStates[record])
    walkingStates[record] = nil
    NS.ClearAcceptedRoutePlan(record, reason or "mapzeroth_clear")
end

function backend.GetWalkingDiagnostics()
    local c = Private.roadCounters
    local record = NS.GetActiveAuthorityRecord and NS.GetActiveAuthorityRecord()
    local leg = record and record.currentLeg
    local s = record and walkingStates[record]
    local distance = leg and NS.GetPlayerWaypointDistance and NS.GetPlayerWaypointDistance(leg.mapID, leg.x, leg.y)
    local addon = Addon()
    local ok, preference = Call(addon and addon.Options, "Get", "roadPreference")
    return string.format(
            "roads expanded=%d points=%d failed=%d leg=%s radius=%s required=%s distance=%s lastMoveAge=%s advance=%s rejected=%s preference=%s acceptedPreference=%s caughtUp=%s movementLimit=%s",
            c.expanded, c.points, c.failed, tostring(record and record.currentLegIndex),
            tostring(leg and leg.arrivalRadius),
            tostring(leg and leg.walking and leg.walking.required), tostring(distance),
            tostring(s and s.progressAt and GetTime() - s.progressAt), tostring(record and record._coreLastAdvanceReason),
            tostring(Walking.ProgressReason(record, s)), tostring(ok and preference or nil),
            tostring(record and record._mapzerothRoadPreference),
            tostring(s and s.lastAdvanced), tostring(s and s.movementAllowance)) .. " recovery="
        .. tostring(s and s.walkRecovery and s.walkRecovery.reason)
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
    local requestClass = (reason == "SPELL_UPDATE_COOLDOWN" or reason == "BAG_UPDATE_COOLDOWN") and "cooldown" or
        "structural"
    return NS.RequestRouteBackendStateValidation("mapzeroth", reason or "mapzeroth_invalidated", requestClass)
end

local wasGhost = false

local function IsGhost()
    return UnitIsGhost and UnitIsGhost("player") and true or false
end

function backend.OnLifeStateChanged()
    local ghost = IsGhost()
    if wasGhost == ghost then return end
    wasGhost = ghost
    backend.OnPlanInvalidated("mapzeroth_ghost_changed")
end

local nativeAddon
local ownsNativeNavigation = false
local ownershipGeneration = 0
local installedGuards = setmetatable({}, { __mode = "k" })

-- ============================================================
-- Native navigation ownership
-- ============================================================

local function NativeMayResume(addon, generation)
    return nativeAddon == addon and not ownsNativeNavigation and generation == ownershipGeneration
end

local function Pack(...) return { n = select("#", ...), ... } end

local function InstallNativeNavigationGuards(addon)
    if installedGuards[addon] then return true end
    local missing = MissingCapability(addon, NAVIGATION_REQUIRED)
    if missing then return false, missing end
    local guard = {}
    installedGuards[addon] = guard
    local panel, prompt, navigator = addon.Panel, addon.WaypointPrompt, addon.Navigator
    local startRoute, nativeFollow = panel.StartRoute, panel.RouteToQuest
    panel.StartRoute = function(...)
        if ownsNativeNavigation then
            NS.Msg("AWP routing is active. Turn it off to start a trip in Mapzeroth's navigator.")
            return
        end
        return startRoute(...)
    end
    panel.RouteToQuest = function(self, questID, ...)
        if not ownsNativeNavigation then return nativeFollow(self, questID, ...) end
        return NS.Internal.BlizzardTakeovers.RouteFollowedQuest(questID, "mapzeroth")
    end

    local waypointChanged = prompt.OnWaypointChanged
    prompt.OnWaypointChanged = function(...)
        if ownsNativeNavigation then return end
        return waypointChanged(...)
    end
    local showQuest, answer = prompt.ShowQuest, prompt.Answer
    local offeredQuestID
    prompt.ShowQuest = function(self, quest, ...)
        if ownsNativeNavigation and ((UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
                or (NS.IsInternalSuperTrackMutation and NS.IsInternalSuperTrackMutation())
                or NS.Internal.BlizzardTakeovers.IsQuestRouteCurrent(quest.questID, "mapzeroth")) then
            return
        end
        offeredQuestID = quest.questID
        return showQuest(self, quest, ...)
    end
    prompt.Answer = function(self, choice, ...)
        if ownsNativeNavigation and choice == "route" and self:IsQuestShown() then
            local questID = offeredQuestID
            offeredQuestID = nil
            self:Hide()
            return NS.Internal.BlizzardTakeovers.RouteFollowedQuest(questID, "mapzeroth", true)
        end
        return answer(self, choice, ...)
    end

    local nativeLead = addon.Corpse.Lead
    addon.Corpse.Lead = function(self, with, ...)
        if not ownsNativeNavigation then return nativeLead(self, with, ...) end
        if not IsGhost() or (IsInInstance and IsInInstance()) then return false end
        local target = addon:GetCorpseTarget()
        if not target then return false end
        local title = addon.L and addon.L.PICK_CORPSE or CORPSE or "Corpse"
        return NS.RequestCorpseRoute(target.mapID, target.x, target.y, title, "Mapzeroth",
            with == "tomtom" and "direct" or "mapzeroth")
    end
    local routeToQuest = addon.QuestArrow.Route
    addon.QuestArrow.Route = function(questID, ...)
        if not ownsNativeNavigation then return routeToQuest(questID, ...) end
        return NS.Internal.BlizzardTakeovers.RouteQuestExplicitly(questID, "mapzeroth")
    end

    -- Resume can outlive the native corpse trip. Protect its completion,
    -- before the native callback starts navigation or commits UI changes.
    -- Other MultiRoute jobs (including previews) retain their own lifecycle.
    local run, resume = addon.MultiRoute.Run, navigator.Resume
    addon.MultiRoute.Run = function(self, work, done, ...)
        local generation = guard.resumeGeneration
        if generation == nil then return run(self, work, done, ...) end
        return run(self, work, function(...)
            if NativeMayResume(addon, generation) then return done(...) end
        end, ...)
    end
    navigator.Resume = function(self, ...)
        if not NativeMayResume(addon, ownershipGeneration) then return false end
        local previous = guard.resumeGeneration
        guard.resumeGeneration = ownershipGeneration
        local result = Pack(pcall(resume, self, ...))
        guard.resumeGeneration = previous
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end
    return true
end

function backend.RefreshNativeNavigationOwnership()
    local addon = Addon()
    if type(addon) ~= "table" then
        if nativeAddon ~= nil then
            ownershipGeneration = ownershipGeneration + 1
            nativeAddon, ownsNativeNavigation = nil, false
        end
        return
    end
    local enabled = NS.IsRoutingEnabled()
    if nativeAddon ~= addon then
        ownershipGeneration = ownershipGeneration + 1
        nativeAddon, ownsNativeNavigation = addon, false
    end
    local installed, missing = InstallNativeNavigationGuards(addon)
    if not installed then
        local reason = "Mapzeroth's current navigation contract is missing " .. missing .. ". Update Mapzeroth."
        if backend._nativeContractError ~= reason then NS.Msg(reason) end
        backend._nativeContractError = reason
        return false, reason
    end
    backend._nativeContractError = nil
    if ownsNativeNavigation == enabled then return true end
    ownershipGeneration = ownershipGeneration + 1
    ownsNativeNavigation = enabled
    if enabled then
        Call(addon.WaypointPrompt, "Hide")
        local ok, active = Call(addon.Navigation, "IsActive")
        if ok and active then Call(addon.Navigator, "Stop") end
    else
        Call(addon.WaypointPrompt, "Settle")
    end
    return true
end

local function OnRouteOptionChanged(key)
    backend.OnPlanInvalidated("MAPZEROTH_OPTION_" .. key)
end

local EVENTS = {
    "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "PLAYER_EQUIPMENT_CHANGED", "SPELLS_CHANGED",
    "NEW_TOY_ADDED", "HEARTHSTONE_BOUND", "TAXIMAP_OPENED", "TAXIMAP_CLOSED",
    "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "SKILL_LINES_CHANGED", "UPDATE_FACTION",
    "PLAYER_MONEY", "CALENDAR_UPDATE_EVENT_LIST",
    "ZONE_CHANGED_NEW_AREA", "SPELL_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED",
}

function backend.Initialize()
    if backend._eventFrame then return end
    wasGhost = IsGhost()
    if type(NS.RegisterRouteBackendStateValidator) == "function" then
        NS.RegisterRouteBackendStateValidator("mapzeroth", ValidateState, NS.ProbeRouteTravelDependency)
    end
    local frame = CreateFrame("Frame")
    backend._eventFrame = frame
    for index = 1, #EVENTS do pcall(frame.RegisterEvent, frame, EVENTS[index]) end
    if not Addon() then frame:RegisterEvent("ADDON_LOADED") end
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    frame:SetScript("OnEvent", function(self, event, arg1, _, spellID)
        if event == "ADDON_LOADED" then
            if arg1 == "Mapzeroth" then
                self:UnregisterEvent(event)
                backend.RefreshNativeNavigationOwnership()
                Private.RegisterOptionsCallback(OnRouteOptionChanged)
            end
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then return end
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if Private.IsMakeCampSpell(spellID) then backend.OnPlanInvalidated("mapzeroth_camp_changed") end
            return
        end
        backend.OnPlanInvalidated(event)
    end)
    backend.RefreshNativeNavigationOwnership()
    Private.RegisterOptionsCallback(OnRouteOptionChanged)
end
