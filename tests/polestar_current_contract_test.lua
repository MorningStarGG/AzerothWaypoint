local NativePath = dofile("tests/native_path.lua")
local fixture = assert(loadfile("tests/polestar_integration_test.lua"))()
local r, NS = fixture.runtime, AzerothWaypointNS
local backend, provider = fixture.backend, NS.Internal.PolestarProvider
local P = NS.Internal.PolestarPresentation
local context
fixture.settings["nav.navRouting"] = false
r.Nav.PlanRoute = function(value)
    context = value
    return { { kind = "walk", from = { map = 1, c = 1, wx = 0, wy = 0 }, to = value.target } }
end
local escort, timed, count = false, false, 0
r.Engine.EscortRunning = function() return escort end
r.Compat.QuestTimerRunning = function() return timed end
local taxiSeen = { [1] = true }
r.Nav.GetTaxiSeen = function() return taxiSeen end
r.Nav.TaxiMaybe = function(id) return id == 234 end
r.Nav.BoundInn = function() return { c = 1, wx = 900, wy = 0, map = 1 } end
r.Compat.GetItemCount = function() return count end
r.Compat.GetItemBaseCooldown = function() return 3600 end
r.Transit.Teleports = function() return { { spell = 556, bind = true, name = "Astral Recall", ready = 0, length = 900 } } end
local function plan()
    backend.PlanRoute(NS.record, 1, .85, .85, "Current contract")
    assert(context)
    return context
end
local c = plan()
assert(c.seen[1] and c.level and c.maybe({ id = 234 }) and not c.maybe({ id = 345 }))
assert(c.hearth and c.noStone and c.teleports[1].bind and c.teleports[1].length == 900,
    "Astral Recall needs a usable Hearthstone or lost bind metadata")
count = 1
c = plan()
assert(not c.noStone and c.hearthLength == 3600)
local valid, normal = NS.validator()
assert(valid)
escort = true
c = plan()
assert(c.walkOnly and not c.hearth and not c.teleports, "Escort allowed transport or teleport")
local validEscort, escortFingerprint = NS.validator()
assert(validEscort and escortFingerprint ~= normal)
escort, timed = false, true
c = plan()
assert(not c.walkOnly and not c.hearth and not c.teleports, "Ordinary timer policy changed")
timed = false
local _, beforeSeen = NS.validator()
taxiSeen[2] = true
assert(select(2, NS.validator()) ~= beforeSeen, "Flight observation missing from fingerprint")

-- Native localized material formatting consumes a copied, bounded structure.
local ui = { L = setmetatable({}, { __index = function(_, key) return key end }),
    Compat = r.Compat, Thousands = tostring, RegisterDefaults = function() end, On = function() end }
assert(loadfile(NativePath("forever", "Polestar/UI/UI.lua")))("Polestar", ui)
r.UI.MaterialsLine = ui.UI.MaterialsLine
local nativeGoal = { t = "auction", text = "Buy Linen Cloth", status = "active", index = 1,
    materials = { bank = 12, mail = 3, toGet = 5, alts = { { name = "Other", count = 2 } } } }
local copied = P.CopyGoal(nativeGoal)
local fact = P.Resolve(r, copied)
assert(fact.action == "buy" and fact.context:find("12 in your bank", 1, true) and fact.context:find("5 to buy", 1, true))
nativeGoal.materials.bank, nativeGoal.materials.alts[1].name = 99, "Changed"
assert(copied.materials.bank == 12 and copied.materials.alts[1].name == "Other")
assert(P.Resolve(r, { t = "collect", text = "Gather Cloth" }).action == "collect")
assert(P.Resolve(r, { t = "getfp", text = "Learn the flight path" }).travelType == "taxi")
assert(P.Resolve(r, { t = "enter", text = "Enter the mine" }).action == "travel")
assert(P.Resolve(r, { t = "turnin", text = "Turn in Task", directText = "Accept and hand in during the same conversation" }).context)

-- Load Polestar's installed public follower API, without running its login/UI.
r.L = ui.L
local messages, modules, tickers = {}, {}, {}
for _, name in ipairs({ "RegisterDefaults", "RegisterEvent", "UnregisterEvent", "OnLogin", "OnInit" }) do r[name] = function() end end
r.On = function(event, fn) messages[event] = fn end
r.SafeCall = function(fn) return fn() end
r.NewTicker = function(_, fn)
    local ticker = { callback = fn, Cancel = function(self) self.cancelled = true end }
    tickers[#tickers + 1] = ticker
    return ticker
end
r.Nav.RegisterModule = function(value) modules[#modules + 1] = value end
r.Nav.GetTarget = function() return { map = 1, x = 50, y = 50, label = "Guide target" } end
r.Nav.Reapply = function() for _, value in ipairs(modules) do if value.OnTarget then value:OnTarget() end end end
local samples = 0
r.Nav.Sample = function() samples = samples + 1 end
r.Nav.arrow = { frame = { IsShown = function() return false end } }
assert(loadfile(NativePath("forever", "Polestar/Nav/Journey.lua")))("Polestar", r)
local routing = true
NS.IsRoutingEnabled = function() return routing end
NS.RefreshPolestarNavigationOwnership()
assert(provider.GetFollowerStatus() and r.Nav.FollowerPins() and r.Nav.FollowerShows())
local ticker = assert(tickers[1], "Polestar follower did not start its ticker")
assert(#tickers == 1 and not ticker.cancelled)
ticker.callback()
assert(samples == 1, "Hidden native arrow lost native route sampling")
fixture.drain()
local received = provider.counters.received
for _ = 1, 100 do messages.ROUTE_ADVANCED() end
fixture.drain()
assert(provider.counters.received == received, "Unchanged follower notifications rebuilt the guide")
for _, guide in ipairs({ "zygor", "dugi", "rxp", "polestar" }) do
    NS.GetActiveGuideProvider = function() return guide end
    NS.RefreshPolestarNavigationOwnership()
    assert(provider.GetFollowerStatus() and #tickers == 1, "Guide switch released follower")
end
assert(r.Get("nav.tomtom") == false, "TomTom conflict protection removed")
fixture.settings["nav.blizzardWaypoint"] = true
assert(r.Get("nav.blizzardWaypoint") == true, "Private Blizzard setting interception remains")
routing = false
local inCombat = true
_G.InCombatLockdown = function() return inCombat end
NS.RefreshPolestarNavigationOwnership()
assert(provider.GetFollowerStatus() and not ticker.cancelled, "Combat toggle invoked native bridge refresh")
inCombat = false
NS.RefreshPolestarNavigationOwnership()
assert(not provider.GetFollowerStatus() and not r.Nav.FollowerPins() and not r.Nav.FollowerShows() and ticker.cancelled)
assert(r.Get("nav.tomtom") == true and fixture.settings["nav.arrow"] == nil, "Native preferences changed")
routing = true
NS.RefreshPolestarNavigationOwnership()
assert(provider.GetFollowerStatus() and #tickers == 2, "Follower failed to rearm after routing toggle")
print("Polestar current travel inputs, presentation and installed follower lifecycle passed")
