local replaceMethod = dofile("tests/replace_method.lua")
local NativePath = dofile("tests/native_path.lua")
-- Lua 5.1: exercises the owned planner and the installed native search loop.
local function check(value, message) assert(value, message) end
local now, profile, combat, routing, activeRecord = 0, 0, false, true, nil
local frames, released, accepted, publications, allocated = {}, 0, 0, 0, 0
_G.GetTime = function() return now end
local profilerRunning = true
_G.debugprofilestop = function()
    if not profilerRunning then return 0 end
    profile = profile + 0.05
    return profile
end
_G.InCombatLockdown = function() return combat end
_G.CreateFrame = function()
    local f = { scripts = {} }
    function f:SetScript(k, v) self.scripts[k] = v end
    function f:RegisterEvent() end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    frames[#frames + 1] = f; return f
end
_G.C_Item = { GetItemInfoInstant = function() return nil, nil, nil, "" end,
    GetItemCount = function() return 1 end, GetItemCooldown = function() return 0, 0 end,
    GetItemNameByID = function() return "Teleport item" end, IsEquippedItem = function() return false end }
_G.C_Spell = { GetSpellName = function() return "Teleport" end, GetSpellCooldown = function() return { startTime = 0, duration = 0 } end }
_G.C_SpellBook = { FindSpellBookSlotForSpell = function() return 1 end }
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }
_G.UnitClass = function() return "Mage", "MAGE" end
_G.UnitRace = function() return "Human", "Human" end
_G.UnitLevel = function() return 80 end
_G.UnitFactionGroup = function() return "Alliance" end
_G.GetBindLocation = function() return "Inn" end
_G.PlayerHasToy = function() return false end
_G.DGV_USETAXISYSTEM = 1
_G.DugisGuideUser = {}
local enabled = true
local dugi = { Modules = {}, UserSetting = function() return enabled end, UiMapId2Floor = function() return 0 end,
    GetPlayerMapPositionDisruptive = function() return 1, 0, .1, .2 end,
    UnpackXY = function() return .8, .9 end, GetMapNameFromID = function(_, id) return "Map " .. id end,
    GetFlightMasterName = function() return "Flight destination" end }
_G.DugisGuideViewer = dugi
local pooled = {}
local methods = {}
function methods:BindToAutoroutineLifetime(dispose)
    if dugi.currentAutoroutine then dugi.currentAutoroutine.boundObjects[self] = dispose end
    return self
end
function methods:SetList(...) for k in pairs(self) do self[k] = nil end; for i = 1, select("#", ...) do self[i] = select(i, ...) end end
function methods:Unpack() return unpack(self) end
function methods:Length() return #self end
function methods:Insert(value) self[#self + 1] = value end
dugi.GetCreateTable = function(...)
    local t = setmetatable({ ... }, { __index = methods }); pooled[t] = true; allocated = allocated + 1; return t
end
dugi.tPool = function(t)
    check(pooled[t], "Double disposal or foreign table released")
    pooled[t] = nil; released = released + 1
    if dugi.currentAutoroutine then dugi.currentAutoroutine.boundObjects[t] = nil end
end
function dugi:AddRouteWaypoint(_map, _floor, _x, _y, _title, _cue) publications = publications + 1 end
local builders = {}
for _, name in ipairs({ "Character", "FlightMaster", "FlightHop", "BoundTeleport", "UnboundTeleport", "ZenPilgrimageReturn",
    "FlightMasterWhistle", "StaticPortals", "LocalPortals", "InstancePortals", "InstanceExit", "Boats" }) do builders[name] = {} end
function builders.Character:AddWaypoint(route) return dugi:AddRouteWaypoint(route.map or 2, 0, route.x or .8, route.y or .9) end
builders.UnboundTeleport.Build = function(...) end
local taxi = { RouteBuilders = builders }
dugi.Modules.Taxi = taxi
dugi.Modules.TaxiData = { GetFullData = function() return { [1] = { [11] = {}, [22] = { m = 2, f = 0, coord = 1 } } } end }
local requests, validators = {}, {}
local NS = { State = { routing = {} }, IsRoutingEnabled = function() return routing end,
    IsAddonLoaded = function(name) return name == "DugisGuideViewerZ" end,
    GetActiveAuthorityRecord = function() return activeRecord end,
    GetPlayerMapPosition = function() return 1, .1, .2 end, GetPlayerMapID = function() return 1 end,
    GetWorldPositionFromMapCoords = function(_, x, y) return 1, x*1000, y*1000 end,
    RegisterRouteBackendStateValidator = function(id, fn) validators[id] = fn end,
    RequestRouteBackendStateValidation = function(...) requests[#requests + 1] = { ... } end,
    RecomputeCarrier = function() end, GetPlayerWaypointDistance = function() return 0 end,
    AdvanceActiveRouteLeg = function() return true end,
    AcceptBackendPlan = function(record, _, legs, reason)
        accepted = accepted + 1; record.legs, record.currentLeg, record.reason = legs, legs[1], reason
    end }
_G.AzerothWaypointNS = NS
local mode, kind, itemRoute = "route", "Character", nil
local function route(name)
    local t = dugi.GetCreateTable(); t.builder = builders[name]; return t
end
local function walk() return route("Character") end
local function original(self, parent, m1, f1, x1, y1, m2, f2, x2, y2, ...)
    local temp = dugi.GetCreateTable()
    if mode == "no_path" then dugi.tPool(temp); return nil end
    if mode == "yield" then coroutine.yield() end
    if mode == "error" then error("fixture error") end
    if mode == "timeout" then while true do coroutine.yield() end end
    if mode == "entries" then
        if parent then dugi.tPool(temp); return nil end
        for i = 1, 20001 do self:GetBestRoute(temp, m1, f1, x1 + i, y1, m2, f2, x2, y2) end
    end
    if mode == "unusable_item" then
        local result = builders.UnboundTeleport:Build(nil, parent, m1, f1, x1, y1, m2, f2, x2, y2, 65274, "89158:2::1")
        check(result == nil, "Unusable wearable candidate entered native builder")
        dugi.tPool(temp); return walk()
    end
    if mode == "cycle" then self:GetBestRoute(temp, m1, f1, x1, y1, m2, f2, x2, y2, ...) end
    if mode == "depth" then return self:GetBestRoute(temp, m1, f1, x1 + .00001, y1, m2, f2, x2, y2, ...) end
    dugi.tPool(temp)
    local t = route(kind)
    if kind == "Character" then return t end
    t.m, t.f, t.x, t.y = 2, 0, .8, .9
    if kind == "FlightMaster" then t[1], t[2], t.c, t.headId, t.tailId = walk(), walk(), 1, 11, 22
    elseif kind == "FlightHop" then t.m2, t.f2, t.x2, t.y2 = 2, 0, .8, .9
    elseif kind == "BoundTeleport" or kind == "UnboundTeleport" or kind == "ZenPilgrimageReturn" or kind == "FlightMasterWhistle" then
        t.spell, t.item, t.tail = not itemRoute and 556 or nil, itemRoute, walk()
    else
        t.mSource, t.fSource, t.xSouce, t.ySource = 1, 0, .2, .3
        t.mPort, t.fPort, t.xPort, t.yPort = 2, 0, .8, .9
        t.head, t.tail, t.engVehicle = kind ~= "InstanceExit" and walk() or nil, walk(), "Zeppelin"
        if mode == "sanctum_retail" then
            t.mSource, t.xSouce, t.ySource = 84, .4808, .9196
            t.mPort, t.xPort, t.yPort = 2339, .4129, .2745
        elseif mode == "sanctum_forever" then
            t.mSource, t.xSouce, t.ySource = 1416, .12, .562
            t.mPort, t.xPort, t.yPort = 1453, .499, .867
        end
        t.spell = 999 -- portal prerequisite must never become a portable action
    end
    return t
end
taxi.GetBestRoute = function(self, ...)
    if routing then return NS.RoutingBackend_Dugi.RunNativePlanner(original, self, ...) end
    return original(self, ...)
end
dugi.SetSmartWaypoint = function(_, m, f, x, y, _, om, of, ox, oy)
    check(om == 1 and ox == 10 and oy == 20, "Missing explicit player origin")
    local result = taxi:GetBestRoute(nil, om, of, ox / 100, oy / 100, m, f, x / 100, y / 100)
    check(result == nil, "Native root escaped interception")
end
assert(loadfile("bridge/routing/shared.lua"))()
assert(loadfile("tests/route_cleanup_fixture.lua"))()
assert(loadfile("bridge/routing/backends/dugi.lua"))()
local plannerFixture = assert(loadfile("tests/planner_attempt_fixture.lua"))().Install(NS.RoutingBackend_Dugi)
local backend = NS.RoutingBackend_Dugi; backend.Initialize()
local f = frames[1]
local function start()
    local record = {}; activeRecord = record; backend.PlanRoute(record, 2, .8, .9, "Exact quest")
    return record
end
local function tick(n)
    for _ = 1, n or 100 do
        now = now + .01
        if f.shown then f.scripts.OnUpdate() end; plannerFixture.Flush()
    end
end
check(backend.IsAvailable(), "Complete current installation rejected")
for _, name in ipairs({ "Character", "FlightMaster", "FlightHop", "BoundTeleport", "UnboundTeleport", "ZenPilgrimageReturn",
    "FlightMasterWhistle", "StaticPortals", "LocalPortals", "InstancePortals", "InstanceExit", "Boats" }) do
    kind = name
    local record = start(); tick()
    check(record.reason == "dugi_plan", name .. " did not translate")
    local last = record.legs[#record.legs]
    check(last.x == .8 and last.y == .9 and last.title == "Exact quest", "Exact final destination lost")
    if name == "StaticPortals" then
        for _, leg in ipairs(record.legs) do check(not leg.specialAction, "Portal prerequisite became a spell") end
    elseif name == "FlightMaster" then
        for _, leg in ipairs(record.legs) do if leg.taxi then check(not leg.taxi.nodeID, "NPC ID used as taxi-node ID") end end
    end
    check(next(pooled) == nil, name .. " leaked pooled objects")
end
check(publications == 0, "Published a native trip")

for _, flavor in ipairs({ "retail", "forever" }) do
    kind, mode = "LocalPortals", "sanctum_" .. flavor
    local record = start(); tick()
    local portal
    for _, leg in ipairs(record.legs) do if leg.kind == "portal" then portal = leg; break end end
    if flavor == "retail" then
        check(portal and portal.mapID == 84 and portal.sanctumDeparture == "inside",
            "Dugi omitted the Retail portal's known interior origin")
    else
        check(portal and portal.mapID == 1416 and portal.sanctumCrossing
            and portal.sanctumCrossing.mapID == 1453,
            "Dugi moved the Forever remote portal or lost its confirmed interior arrival")
    end
end
mode = "route"

-- The native character builder can round-trip the final map point through
-- world coordinates. Only numerical identity may remove its final walk.
do
    local add = builders.Character.AddWaypoint
    local project = replaceMethod(NS, "GetWorldPositionFromMapCoords", function(_, x,y) return 1, x*10000, y*10000 end)
    local offset, cue = 0.00000153608322, nil
    replaceMethod(builders.Character, "AddWaypoint", function()
        return dugi:AddRouteWaypoint(2, 0, .8, .9 + offset, "Follow the path", cue)
    end)
    kind = "Character"
    local record = start(); tick()
    check(#record.legs == 1 and record.currentLeg.routeLegKind == "destination",
        "Dugi duplicated a final walking endpoint because of map conversion precision")
    check(record.currentLeg.x == .8 and record.currentLeg.y == .9, "Dugi changed the exact requested destination")
    offset = .0002
    record = start(); tick()
    check(#record.legs == 2 and record.legs[1].routeLegKind == "carrier", "Dugi discarded a real approach point")
    offset, cue = 0, "upstairs"
    record = start(); tick()
    check(#record.legs == 2 and record.legs[1].dugiCue == "upstairs", "Dugi discarded a required stair instruction")
    assert(loadfile("integrations/guides/presentation.lua"))()
    check(NS.Internal.RouteWalkingPresentation.Resolve(record,record.legs[1]).title=="Go upstairs",
        "Shared walking presentation replaced Dugi's native stair cue")
    builders.Character.AddWaypoint, NS.GetWorldPositionFromMapCoords = add, project
end
local validator = assert(validators.dugi, "Dugi did not register its validator")
do
    local original = builders.Character.AddWaypoint
    local advance = NS.AdvanceActiveWalkingLegs
    local middleMap, middleFloor, middleCue = 2, 0, nil
    replaceMethod(builders.Character, "AddWaypoint", function(_, route)
        route[2], route[3], route[4], route[5] = 2, 0, .4, .2
        dugi:AddRouteWaypoint(2, 0, .44, .2)
        dugi:AddRouteWaypoint(middleMap, middleFloor, .44, .265, nil, middleCue)
        dugi:AddRouteWaypoint(2, 0, .8, .9)
    end)
    local record = start(); tick()
    assert(record.legs[3].walking.required and record.legs[3].routeLegKind == "destination")
    record.currentLegIndex = 1
    assert(backend.WantsNavigationProgress(record))
    NS.AdvanceActiveWalkingLegs = function(owner, leg, _, nextIndex, reason)
        assert(owner == record and leg == record.currentLeg)
        owner.currentLegIndex, owner.currentLeg, owner._coreLastAdvanceReason = nextIndex, owner.legs[nextIndex], reason
        return true
    end
    backend.PollNavigationLeg(record, true, 2, .4, .2)
    dofile("tests/walking_corner_replay.lua")(function(x,y)
        now = now + .21
        backend.PollNavigationLeg(record, true, 2, .4+x/1000, .2+y/1000)
    end, record)
    for _, barrier in ipairs({"upstairs", "map", "floor"}) do
        middleCue = barrier == "upstairs" and barrier or nil
        middleFloor = barrier == "floor" and 1 or 0
        middleMap = barrier == "map" and 1 or 2
        record = start(); tick()
        assert(not backend.WantsNavigationProgress(record), "Dugi skipped a " .. barrier .. " boundary")
        assert(not record.legs[2].walking, "Dugi treated a " .. barrier .. " instruction as ordinary geometry")
    end
    NS.AdvanceActiveWalkingLegs = advance
    builders.Character.AddWaypoint = original
end
check(validator(), "Initial state snapshot failed")
itemRoute, kind = 65274, "UnboundTeleport"
local inventoryType = "INVTYPE_CLOAK"
C_Item.GetItemInfoInstant = function() return nil, nil, nil, inventoryType end
local canEquip = true
NS.CanExecuteRouteEquipmentItem = function() return canEquip end
local equipment = start(); tick()
check(equipment.legs[1].specialAction.executionType == "equip", "Wearable item omitted equip transaction")
check(equipment.legs[2].specialAction.securePayload == 65274
    and equipment.legs[2].specialAction.routeDependency.id == 65274, "Item-use payload/dependency lost numeric ID")
canEquip = false
mode = "unusable_item"; local excluded = start(); tick()
check(excluded.reason == "dugi_plan", "Unusable wearable blocked alternative route")
itemRoute, mode = nil, "route"
inventoryType = ""
local valid, fingerprint = validator()
local cooldown = { startTime = {}, duration = 0 }
C_Spell.GetSpellCooldown = function() return cooldown end
check(validator() == false, "Inaccessible cooldown accepted as changed state")
cooldown = { startTime = 0, duration = 0 }
local validAgain, same = validator()
check(valid and validAgain and fingerprint == same, "Failed snapshot altered stable backend state")
kind, mode = "Character", "cycle"
local r = start(); tick(); check(r.reason == "dugi_plan" and backend.counters.cycles > 0, "Cycle did not prune branch")
mode = "yield"; r = start(); tick(1)
local held = accepted
NS.State.routing.specialActionCasting = true; tick(400)
check(accepted == held, "Pending search replaced a plan during casting")
NS.State.routing.specialActionCasting = false; mode = "route"; tick(200)
check(r.reason == "dugi_plan", "Cast pause consumed the search deadline")
for _, failure in ipairs({ "error", "depth", "timeout" }) do
    mode = failure; r = start(); tick(400)
    check(r._fixtureResult.status == "failed", failure .. " failed to report a terminal result")
    check(next(pooled) == nil, failure .. " leaked native objects")
end
profilerRunning = false
mode = "entries"; r = start(); tick(1)
check(r._fixtureResult.reason == "dugi_entry_limit" and next(pooled) == nil, "Query-entry budget failed to dispose the request")
profilerRunning = true
mode = "yield"; r = start(); tick(1); backend.Clear(r)
check(next(pooled) == nil, "Cancellation leaked owned objects")
mode = "yield"; r = start(); tick(1); local before = accepted
combat = true; tick(1)
check(accepted == before and next(pooled) == nil, "Combat transition retained the old search")
tick(200)
check(accepted == before + 1 and r.reason == "dugi_plan" and next(pooled) == nil, "Combat search did not finish")
combat, mode = false, "route"; f.scripts.OnEvent(f, "PLAYER_REGEN_ENABLED"); backend.PlanRoute(r, 2, .8, .9, "Exact quest"); tick()
check(r.reason == "dugi_plan", "Post-combat restart missing")
combat = true
local pending = { mapID = 2, x = .8, y = .9 }
NS.State.routing.pendingManualAuthority = pending
backend.PlanRoute(pending, 2, .8, .9, "Pending manual")
tick(200)
check(pending.reason == "dugi_plan", "Pending manual route was not accepted during combat")
check(backend.PollNavigationLeg({currentLeg = {dugiArrival = {mapID = 2, x = .8, y = .9}}}),
    "Combat prevented an observed transport arrival")
NS.State.routing.pendingManualAuthority = nil
mode = "no_path"; r = start(); tick()
check(r._fixtureResult.status == "deferred" and r._fixtureResult.reason == "combat", "Missing combat path was discarded")
mode = "route"
combat = true
r = {target = {mapID = 2, x = .8, y = .9}}
activeRecord = r
backend.PlanRoute(r, 2, .8, .9, "Replaced")
r.target.x = .3
combat = false; f.scripts.OnEvent(f, "PLAYER_REGEN_ENABLED"); tick(200)
check(r.reason ~= "dugi_plan", "Stale combat destination was restarted")
mode = "yield"; r = start(); tick(1); activeRecord = {}; tick()
check(next(pooled) == nil, "Stale authority leaked allocations")
mode, enabled = "route", false; r = start(); check(r._fixtureResult.mode == "intentional_direct", "Master setting ignored")
enabled = true
local beforeAlloc = allocated
check(taxi:GetBestRoute(nil, 1, 0, .1, .2, 2, 0, .8, .9) == nil and allocated == beforeAlloc, "Foreign call entered planner")
-- Native caller execution remains a direct yielding Lua call when routing is off.
routing = false; mode = "yield"
local thread = coroutine.create(function() local t = taxi:GetBestRoute(nil, 1, 0, .1, .2, 2, 0, .8, .9); dugi.tPool(t) end)
check(coroutine.resume(thread), "Native yield wrapped in a C boundary")
check(coroutine.resume(thread), "Native resume failed")
check(next(pooled) == nil and dugi.currentAutoroutine == nil, "Foreign call ownership contaminated")
print("Dugi backend: typed routes, exact destination, pool ownership, cycles, budgets, failures, cancellation and combat passed")

-- Exercise the installed implementations, not just the simulated route tree.
for _, client in ipairs({ "retail", "forever" }) do
    local path = NativePath(client, "DugisGuideViewerZ/Taxi.lua")
    local file = assert(io.open(path, "rb")); local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
    local function extract(first, following, expression, environment)
        local a = assert(source:find(first, 1, true)); local b = assert(source:find(following, a + #first, true))
        local chunk = assert(loadstring(source:sub(a, b - 1) .. "\nreturn " .. expression))
        setfenv(chunk, environment); return chunk()
    end
    local environment = setmetatable({ DGV = dugi, Taxi = taxi, RouteBuilders = builders,
        order = { "StaticPortals", "Character" }, routeStackDefaultLimit = 6,
        GetCreateTable = function(...) return dugi.GetCreateTable(...):BindToAutoroutineLifetime(dugi.tPool) end,
        tContains = function(t, item) for _, value in ipairs(t) do if value == item then return true end end end,
        tPool = dugi.tPool, PoolRoute = dugi.tPool, IsBest = function() return false end,
        CheckEncapsulatedZones = function(_, ...) return ... end,
        YieldAutoroutine = function() coroutine.yield() end,
        SetExtraData = function() error("Native trip metadata published") end,
    }, { __index = _G })
    function taxi:IsBuilderEnabled() return true end
    builders.StaticPortals.Iterate = function(_, parent, ...)
        return taxi:GetBestRoute(parent or {}, ...)
    end
    builders.Character.Iterate = function(_, _, _, _, _, _, m2, _, x2, y2, prior)
        if prior then return nil end
        check(m2 == 2 and x2 == .8 and y2 == .9, "Native percentage conversion was changed")
        return walk()
    end
    original = extract("function Taxi:GetBestRoute(", "local encapsulatedZones", "Taxi.GetBestRoute", environment)
    replaceMethod(taxi, "GetBestRoute", function(self, ...)
        if routing then return backend.RunNativePlanner(original, self, ...) end
        return original(self, ...)
    end)
    dugi.Modules.Corpse = {}
    dugi.SetSmartWaypoint = extract("function DGV:SetSmartWaypoint(", "function DGV:SPELLS_CHANGED", "DGV.SetSmartWaypoint", environment)
    routing, mode, kind = true, "route", "Character"
    local record = start(); tick(200)
    check(record.reason == "dugi_plan", client .. " native search did not finish safely")
    local ordinaryOrder = environment.order
    environment.order = { "BoundTeleport", "UnboundTeleport", "ZenPilgrimageReturn", "FlightMasterWhistle", "StaticPortals", "Character" }
    local restrictedCalls = 0
    for index = 1, 4 do
        builders[environment.order[index]].Iterate = function() restrictedCalls = restrictedCalls + 1 end
    end
    combat = true
    record = start(); tick(200)
    check(record.reason == "dugi_plan" and restrictedCalls == 0, client .. " combat search entered a portable-action builder")
    combat = false
    record = start(); tick(200)
    check(record.reason == "dugi_plan" and restrictedCalls >= 4, client .. " portable travel stayed excluded")
    for index = 1, 4 do builders[environment.order[index]].Iterate = nil end
    environment.order = ordinaryOrder
    check(next(pooled) == nil and dugi.currentAutoroutine == nil and publications == 0,
        client .. " native search leaked allocations, context or publications")
    print(client .. ": installed GetBestRoute and SetSmartWaypoint, recursive branch pruning and pool cleanup passed")

    -- Replay the actual recursive builders implicated by the guide-switch
    -- timeout. Their route publication methods must never be called.
    environment.order = { "InstancePortals", "StaticPortals", "BoundTeleport", "Character" }
    environment.GetCreateRoute = function(builder, best, parent)
        local t = dugi.GetCreateTable(); t.builder, t.currentBest, t.parentRoute = builder, best, parent; return t
    end
    environment.CheckRequirements = function(_, ...) return ... end
    environment.strsplit = function(separator, text)
        local out = {}; for piece in (text .. separator):gmatch("(.-)" .. separator) do out[#out + 1] = piece end
        return unpack(out)
    end
    environment.CheckStackLoop = function() return false end
    environment.IsBest = function() return true end
    environment.GetUsefulBindLocation = function() return 1, 0, .8, .9 end
    environment.GetSpellInfo = function() return nil end
    environment.FindSpellBookSlotForSpell = function() return false end
    environment.GetUsableItem = function(id) return id end
    environment.itemHearthstone = 6948
    dugi.GetMapContinent_dugiOld = function() return 1 end
    builders.Character.Build = function() return walk() end
    builders.InstancePortals.Build = extract("function RouteBuilders.InstancePortals:Build(",
        "function RouteBuilders.InstancePortals:IsBest(", "RouteBuilders.InstancePortals.Build", environment)
    builders.StaticPortals.Build = extract("function RouteBuilders.StaticPortals:Build(",
        "function RouteBuilders.StaticPortals:Estimate(", "RouteBuilders.StaticPortals.Build", environment)
    builders.BoundTeleport.Build = extract("function RouteBuilders.BoundTeleport:Build(",
        "function RouteBuilders.BoundTeleport:Estimate(", "RouteBuilders.BoundTeleport.Build", environment)
    builders.InstancePortals.Iterate = function(best, parent, m1, f1, x1, y1, m2, f2, x2, y2, prior)
        if prior then return end
        return builders.InstancePortals:Build(best, parent, m1, f1, x1, y1, m2, f2, x2, y2, "1:0:1:2:0:1")
    end
    replaceMethod(builders.StaticPortals, "Iterate", function(best, parent, m1, f1, x1, y1, m2, f2, x2, y2, prior)
        if prior then return end
        return builders.StaticPortals:Build(best, parent, m1, f1, x1, y1, 2, m2, f2, x2, y2, ":1:0:1:2:0:1")
    end)
    builders.BoundTeleport.Iterate = function(best, parent, m1, f1, x1, y1, m2, f2, x2, y2, prior)
        if prior then return end
        return builders.BoundTeleport:Build(best, parent, m1, f1, x1, y1, m2, f2, x2, y2)
    end
    -- The native builders can request the synthetic source itself.
    replaceMethod(builders.Character, "Iterate", function(_, _, _, _, _, _, _, _, _, _, prior) if not prior then return walk() end end)
    local beforeCycles = backend.counters.cycles
    record = start(); tick(400)
    check(not f.shown and backend.counters.cycles > beforeCycles, "Native recursive builders escaped cycle/budget guards")
    check(next(pooled) == nil and dugi.currentAutoroutine == nil and publications == 0,
        "Native recursive-builder cleanup or publication isolation failed")
    print(client .. ": actual InstancePortals / StaticPortals / BoundTeleport recursion bounded and fully disposed")
    builders.InstancePortals.Iterate, builders.BoundTeleport.Iterate = nil, nil
end
