-- Install the real core cleanup contract while preserving each backend unit
-- fixture's fake planner/carrier boundary. No cleanup implementation is copied.
local NS = AzerothWaypointNS
NS.Internal = NS.Internal or {}
assert(loadfile("bridge/routing/walking.lua"))()
assert(loadfile("bridge/routing/walking_presentation.lua"))()
local before = {}
for key, value in pairs(NS) do before[key] = value end
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("bridge/routing/core.lua"))()
assert(loadfile("bridge/routing/validation.lua"))()
assert(loadfile("bridge/routing/progress.lua"))()
local clear, cancel = NS.ClearAcceptedRoutePlan, NS.CancelRouteBackendStateValidations
for key in pairs(NS) do NS[key] = before[key] end
NS.ClearAcceptedRoutePlan = clear
NS.CancelRouteBackendStateValidations = before.CancelRouteBackendStateValidations or cancel
