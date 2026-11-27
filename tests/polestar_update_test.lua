local replaceMethod = dofile("tests/replace_method.lua")
local NativePath = dofile("tests/native_path.lua")
local f = assert(loadfile("tests/polestar_integration_test.lua"))()
local NS, r, backend = AzerothWaypointNS, f.runtime, f.backend
local api, P = NS.Internal.PolestarProvider, NS.Internal.PolestarPresentation
f.settings["nav.navRouting"] = false
local membership, plans = { [9173] = true }, {}
r.Nav.travel.PortalItems = function() return membership end
r.Nav.PlanRoute = function(value)
    plans[#plans + 1] = value
    return { { kind = "walk", from = { c = 1, wx = 0, wy = 0, map = 1 }, to = value.target } }
end
backend.PlanRoute(NS.record, 1, .85, .85, "Exact")
local context = assert(plans[1], "Polestar did not receive the planner inputs")
assert(context.items[9173] and context.items ~= membership, "Portal eligibility was not copied into planning")
local ok, haveItem = NS.validator(); assert(ok)
membership[9173] = nil
local valid, noItem = NS.validator()
assert(valid and haveItem ~= noItem and context.items[9173], "Portal eligibility change was missed or retained mutable data")
replaceMethod(r.Nav.travel, "PortalItems", function() error("inaccessible inventory") end)
assert(NS.validator() == false, "Failed portal inventory replaced the accepted fingerprint")
replaceMethod(r.Nav.travel, "PortalItems", function() return nil end)
assert(NS.validator(), "No gated portal items is a valid native result")

local from, to = { c = 1, wx = 0, wy = 0, map = 1 }, { c = 2, wx = 500, wy = 500, map = 2 }
replaceMethod(r.Nav, "PlanRoute", function() return { { kind = "airship", from = from, to = to, label = "Board the skycutter" } } end)
r.Compat.GetPlayerWorldPosition = function() return 1, 0, 0 end
backend.PlanRoute(NS.record, 2, .85, .85, "Exact quest")
local first = NS.record.currentLeg
assert(first.polestarKind == "airship" and first.routeTravelType == "airship" and first.activationCoords.x == 0)
assert(first.title == "Board the skycutter" and NS.record.legs[#NS.record.legs].x == .85)
backend.PollNavigationLeg(NS.record)
assert(NS.record.currentLeg == first, "Airship advanced at its departure dock")
replaceMethod(r.Compat, "GetPlayerWorldPosition", function() return 2, 500, 500 end)
NS.AdvanceActiveRouteLeg = function(record, leg, generation)
    assert(record.currentLeg == leg and record._routeAcceptedPlanGeneration == generation)
    record.currentLegIndex = record.currentLegIndex + 1
    record.currentLeg = record.legs[record.currentLegIndex]
    return true
end
backend.PollNavigationLeg(NS.record)
assert(NS.record.currentLeg ~= first, "Airship did not advance at its arrival dock")

-- Native text supplies positive/negative verbs; AWP must not manufacture
-- executable travel actions from ordinary equipment or aura goals.
local categories = {
    accept="accept", turnin="turnin", complete="complete", abandon="info", destroy="info", deposit="use", equip="use",
    kill="kill", collect="collect", ["goto"]="travel", talk="talk", interact="click", use="use", sethome="bind",
    hearth="hearth", die="travel", getfp="learnflight", fly="flight", enter="travel", train="learn", buy="buy",
    auction="buy", vendor="buy", level="level", money="note", task="note", note="note", skill="learn", learn="learn",
    cast="cast", buff="cast", craft="craft", rep="complete", explore="travel", achieve="achieve", wait="note",
}
for verb, action in pairs(categories) do
    local fact = assert(P.Resolve(r, { t = verb, text = "Native instruction (keep this condition)", status = "active" }))
    assert(fact.action == action and fact.title == "Native instruction (keep this condition)", verb)
end
local file = assert(io.open(NativePath("forever", "Polestar/Core/Guides.lua"), "r"))
local nativeVerbs = file:read("*a"); file:close()
local required = assert(nativeVerbs:match("local REQUIRED = {(.-)\n}"))
for verb in required:gmatch("\n%s*([%a]+)%s*=") do assert(categories[verb], "New native goal verb needs review: " .. verb) end

local nativeView = r.Engine.GetStepView(1)
local viewReads, builds, getView, buildStep = 0, 0, r.Engine.GetStepView, P.BuildStep
r.Engine.GetStepView = function(index, shared)
    assert(shared == true, "Polestar's shared native view was not requested")
    viewReads = viewReads + 1; return getView(index)
end
P.BuildStep = function(...) builds = builds + 1; return buildStep(...) end
api.Schedule("observe"); f.drain()
local saved = api.GetSnapshot()
local before = builds
for _ = 1, 200 do api.Schedule("unchanged"); f.drain() end
assert(viewReads > 0 and builds == before and api.GetSnapshot() == saved, "Unchanged observations rebuilt normalized presentation")
nativeView.goals[1].npcName = "Localized NPC"
api.Schedule("native_update"); f.drain()
assert(api.GetSnapshot().target.subtext == "Talk to Localized NPC", "Native name change was not observed")
local refreshes = 0
f.provider.installHooks(function(_, intent)
    refreshes = refreshes + 1
    assert(intent and intent.presentationRefresh and not intent.explicit, "Name readiness changed navigation authority")
end)
f.drain()
local plain = r.UI.PlainGoalText
r.UI.PlainGoalText = function(goal) return goal.t == "accept" and "Localized quest ready" or plain(goal) end
f.fire("NAME_LEARNED"); f.drain()
assert(refreshes > 0 and api.GetSnapshot().target.title == "Localized quest ready", "Unchanged raw goal missed name readiness")
nativeView.goals[1].tickable = false
api.Schedule("native_update"); f.drain()
assert(api.GetSnapshot().steps[1].rows[1].tickable == false, "Checkbox change was lost")

local previous = r.Engine.GetStepView
replaceMethod(r.Engine, "GetStepView", function(index, shared)
    local view = previous(index, shared); view.why = "This step requires a profession you do not have."; return view
end)
f.settings["guideWindow.leftOut"] = true
local leftOut = { { quest = 123, title = "A missed quest", text = "Requires another quest first", kind = "pre" } }
r.Engine.LeftOutHere = function() return leftOut end
api.Schedule("native_update"); f.drain()
local rows = api.GetSnapshot().steps[1].rows
assert(rows[#rows].text == "1 left out here" and rows[#rows].tips[1].text:find("Requires another quest first", 1, true))
local copiedReason = rows[#rows].tips[1].text
leftOut[1].text = "Changed native explanation"
assert(rows[#rows].tips[1].text == copiedReason, "Native explanation table escaped into cached rows")
api.Schedule("native_update"); f.drain()
assert(api.GetSnapshot().steps[1].rows[#rows].tips[1].text:find("Changed native explanation", 1, true))
print("Polestar update: portal membership, airship arrival, all native verbs, cached views and explanations passed")
