local NativePath = dofile("tests/native_path.lua")
-- Exercise the installed, unmodified planner as well as AWP's synthetic fixtures.
local root = NativePath("forever", "Polestar/")
local chunk = loadfile(root .. "Nav/Travel.lua")
if not chunk then print("Polestar native planner: installed source unavailable; fixture skipped"); return end
local r = { Nav = {}, Compat = {}, L = setmetatable({}, { __index = function(_, key) return key end }) }
local function noop() end
r.RegisterDefaults, r.RegisterEvent, r.RegisterCommand = noop, noop, noop
r.OnLogin, r.OnInit, r.On = noop, noop, noop
r.Nav.RegisterModule = function() end
r.Get = function() return true end
GetTime = function() return 100 end
debugprofilestop = function() return 0 end
chunk("Polestar", r)
local nav = r.Nav
nav.RegisterTravelData({ build = "fixture",
    taxi = { { 1, 1, 0, 0, 1, 0, 0, 3, "Start" }, { 2, 1, 1000, 0, 1, 100, 0, 3, "End" } },
    flights = { 1, 2, 1000 },
})
local function plan(target, options)
    local p = { c = 1, wx = 0, wy = 0, map = 1, target = target, known = { [1] = true, [2] = true }, faction = 1, speed = 7 }
    for k, v in pairs(options or {}) do p[k] = v end
    return nav.PlanRoute(p)
end
local target = { c = 1, wx = 1000, wy = 0, map = 1, label = "Final" }
local route = assert(plan(target))
local flew
for _, leg in ipairs(route) do if leg.kind == "fly" then
    assert(leg.stops[#leg.stops].id == 2); flew = true
end end
assert(flew, "Native flight contract changed")
assert(nav.GetRoute() == nil, "Pure planner changed native active route")
local function hasFlight(legs)
    for _, leg in ipairs(legs or {}) do if leg.kind == "fly" then return true end end
    return false
end
local landingRefused = false
local function landingCost(_, x)
    if x == 1000 and landingRefused then return false, nil, true end
    return nil
end
local beyondLanding = {c = 1, wx = 1200, wy = 0, map = 1, label = "Unmeasured final walk"}
assert(hasFlight(plan(beyondLanding, {walkCost = landingCost})), "Unknown landing cost removed a native flight")
landingRefused = true
assert(not hasFlight(plan(beyondLanding, {walkCost = landingCost})), "Verified landing refusal did not remove a native flight")
do
    nav.RegisterTravelData({ taxi = {
        { 1, 1, 0, 0, 1, 0, 0, 3, "Start", nil, 10 },
        { 2, 1, 1000, 0, 1, 100, 0, 3, "End", nil, 10 },
    } }, true)
    local from = nav.GetTravelData().taxiById[1]
    from.z = 10
    GetTaxiMapID = function() return 12 end
    r.Compat.GetPlayerFaction = function() return "Alliance" end
    r.Compat.GetPlayerUnitPosition = function() return 0, 0, 10, 1 end
    local offer = { map = 12, node = from, faction = 1, reachable = { [2] = true } }
    nav.travel.taxiOffer = offer
    local offered = assert(plan(target, { z = 10, liveTaxi = true }))
    assert(offered[1].taxiOffer == offer and offered[1].stops[2].id == 2,
        "The planner must accept an offered flight that the regular graph cannot supply")
    assert(not hasFlight(plan(target, { z = 10 })) and not hasFlight(plan(target, { z = 0, liveTaxi = true })))
    nav.travel.taxiOffer = nil
end
for _, kind in ipairs({ "boat", "zeppelin", "airship", "tram" }) do
    nav.RegisterTravelData({ transports = { { id = kind, kind = kind, faction = 3,
        a = { "A", 1, 0, 0, 1, 0, 0 }, b = { "B", 2, 0, 0, 2, 0, 0 },
        ab = 60, ba = 60, waitA = 0, waitB = 0 } } }, true)
    route = assert(plan({ c = 2, wx = 10, wy = 0, map = 2, label = "Across" }))
    local found
    for _, leg in ipairs(route) do if leg.kind == kind then found = true end end
    assert(found, "Native transport contract changed: " .. kind)
end
nav.RegisterTravelData({ portals = { { id = "portal", name = "Portal", faction = 3,
    a = { "A", 1, 0, 0, 1, 0, 0 }, b = { "B", 2, 0, 0, 2, 0, 0 }, seconds = 5 } } }, true)
route = assert(plan({ c = 2, wx = 10, wy = 0, map = 2, label = "Across" }))
local portal
for _, leg in ipairs(route) do if leg.kind == "portal" then portal = true end end
assert(portal, "Native portal contract changed")
nav.RegisterTravelData({ portals = { { id = "item_gate", name = "Transpolyporter", faction = 3, item = 9173,
    a = { "A", 1, 0, 0, 1, 0, 0 }, b = { "B", 2, 0, 0, 2, 0, 0 }, seconds = 5 } } }, true)
assert(not plan({ c = 2, wx = 10, wy = 0, map = 2, label = "Across" }), "Native portal ignored required item")
assert(plan({ c = 2, wx = 10, wy = 0, map = 2, label = "Across" }, { items = { [9173] = true } }), "Native gated portal did not accept membership")
nav.RegisterTravelData({}, true)
route = assert(plan(target, { walkOnly = true }))
assert(route[1].kind == "walk", "Native walk-only contract changed")
local query,places
places={}
route=assert(plan({c=1,wx=1000,wy=0,z=0,map=1},{z=20,places=places,walkOnly=true,
    walkCost=function(c,x,y,start,z) query={c,x,y,start,z};return 1400,1400,true end}))
assert(query and query[4] and query[5]==20 and route[#route].to.z==0,
    "Native planner no longer passes origin/goal floors through its cost contract")
assert(places[1].z==20 and places[1].start,"Native measurement origin contract changed")
print("Installed Polestar pure-planner contract passed")
