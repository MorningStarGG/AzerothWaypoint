-- Same movement trace in each backend's coordinate system. The route turns
-- from (0,0) at (40,0) toward (40,65). The closest approach is about 17 yd.
return function(move, record)
    local initial = record.currentLegIndex
    local generation = record._routeAcceptedPlanGeneration
    for x = 1, 16 do move(x, 0) end
    for offset = 1, 24 do move(16 + offset, offset) end
    assert(record.currentLegIndex == initial + 1, "Still pointing at the missed turn 24 yards along the outgoing road")
    assert(record._coreLastAdvanceReason == "walking_rejoin", "Missed turn did not rejoin the accepted road")
    assert(record._routeAcceptedPlanGeneration == generation, "Rejoining the road rebuilt the route")
    for _ = 1, 15 do move(40, 24) end
    assert(record.currentLegIndex == initial + 1, "Stationary player advanced twice")
end
