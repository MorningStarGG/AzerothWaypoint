-- Common recovery policy: no planner or client dependency.
local now, timers, wakes = 100, {}, 0
AzerothWaypointNS = { Internal = {}, RequestRouteNavigationProgress = function() wakes = wakes + 1 end }
GetTime = function() return now end
UnitOnTaxi = function() return false end
IsFlying = function() return false end
C_Timer = { NewTimer = function(delay, fn)
    local timer = { at = now + delay, fn = fn }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end }
assert(loadfile("bridge/routing/walking.lua"))()
assert(loadfile("bridge/routing/walking_presentation.lua"))()
local W = AzerothWaypointNS.Internal.RouteWalking
local walk = { from = { c = 1, wx = 0, wy = 0, z = 0 }, to = { c = 1, wx = 100, wy = 0, z = 0 } }
assert(not W.Deviation(walk, 1, 50, 10, 0, 25))
assert(W.Deviation(walk, 1, 50, 30, 0, 25) == "off_path")
assert(W.Deviation(walk, 1, 50, 0, 100, 25) == "wrong_floor")
assert(not W.Deviation(walk, 1, 50, 0, nil, 25), "Unknown height was treated as a wrong floor")
walk.to.wx, walk.to.z = 0, 100
assert(not W.Deviation(walk, 1, 0, 0, 50, 25), "An in-progress vertical transition looked off path")
assert(W.Deviation(walk, 2, 0, 0, 50, 25) == "continent_changed")
local record, state = { currentLeg = {}, _routeAcceptedPlanGeneration = 1 }, {}
local policy = { interval = 2, retrySeconds = 15, retryDistance = 25 }
local ticket = assert(W.BeginRecovery(state, record, 1, 100, 50, 0, policy, "off_path"))
for _ = 1, 20 do assert(not W.BeginRecovery(state, record, 1, 100, 50, 0, policy, "off_path")) end
assert(#timers == 0, "Pending recovery created idle timers")
assert(not W.OriginMatches(ticket, 1, 100, 50, 100), "Same-XY different-floor origin was accepted")
assert(W.OriginMatches(ticket, 1, 100, 50, nil), "Missing height invented a contradiction")
W.CompleteRecovery(state, ticket, false, "no_path")
now = 120
assert(not W.BeginRecovery(state, record, 1, 100, 50, 0, policy, "off_path"), "Stationary failure retried")
ticket = assert(W.BeginRecovery(state, record, 1, 130, 50, 0, policy, "off_path"))
W.CompleteRecovery(state, ticket, false, "no_path")
now = 125
assert(not W.BeginRecovery(state, record, 1, 160, 50, 0, policy, "off_path"))
assert(#timers == 1 and timers[1].at == 135)
for _ = 1, 20 do W.BeginRecovery(state, record, 1, 160, 50, 0, policy, "off_path") end
assert(#timers == 1, "Repeated movement observations multiplied deadlines")
now = 135; timers[1].fn()
assert(wakes == 1)
ticket = assert(W.BeginRecovery(state, record, 1, 160, 50, 0, policy, "off_path"))
local cancelled = 0
ticket.cancel = function() cancelled = cancelled + 1 end
record.currentLeg = {}
assert(W.BeginRecovery(state, record, 1, 160, 50, 0, policy, "off_path"))
assert(cancelled == 1 and ticket.cancelled)
W.CompleteRecovery(state, ticket, true)
assert(state.walkRecovery.ticket, "Obsolete completion cleared a newer request")
W.CancelRecovery(state)
assert(not state.walkRecovery)
-- The old segment can already be outside the recovery radius while the
-- player is confirming the next one. A stationary near miss still wakes.
now = 200
state = { progressLeg=record.currentLeg, rejoinAlong=40, rejoinAt=now }
assert(not W.BeginRecovery(state, record, 1, 0, 35, 0, policy, "off_path"))
local deadline = assert(state.walkRecovery.timer)
assert(deadline.at == 202)
assert(not W.BeginRecovery(state, record, 1, 0, 36, 0, policy, "off_path") and state.walkRecovery.timer == deadline)
now = deadline.at
deadline.fn()
assert(W.BeginRecovery(state, record, 1, 0, 36, 0, policy, "off_path"))
print("Shared walking deviation, floor identity, bounded retries, deadlines and cancellation passed")
