-- ============================================================
-- Walking progression and recovery
-- ============================================================
--
-- Tracks movement along a walking section and decides when the active route
-- can advance or rejoin the path. A backend supplies the walking geometry and
-- required stops. Progress uses movement evidence to advance within the
-- current walking section.

local NS = _G.AzerothWaypointNS
local Walking = { RejoinDistance = 60 }
NS.Internal.RouteWalking = Walking

local function Finite(value)
    return type(value) == "number" and not (issecretvalue and issecretvalue(value))
        and value == value and math.abs(value) < math.huge
end

local function Segment(walk, x, y)
    if walk.length < .01 then return 0, math.huge, walk.length end
    local dx, dy = x - walk.from.wx, y - walk.from.wy
    local lateral = dx * walk.uy - dy * walk.ux
    return dx * walk.ux + dy * walk.uy, lateral * lateral, walk.length
end

function Walking.Speed()
    if type(GetUnitSpeed) ~= "function" then return end
    local ok, speed = pcall(GetUnitSpeed, "player")
    if ok and Finite(speed) and speed >= 0 then return speed end
end

function Walking.MovementLimit(elapsed, speed, previousSpeed)
    local measured = math.max(Finite(speed) and speed or 0, Finite(previousSpeed) and previousSpeed or 0)
    return math.min(200, math.max(40, measured * elapsed + 10))
end

local function BooleanCall(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok and type(value) == "boolean" and not (issecretvalue and issecretvalue(value)) then return value end
end

function Walking.ReadMode()
    local taxi = BooleanCall(UnitOnTaxi, "player")
    if taxi == true then return "taxi" end
    local flying = BooleanCall(IsFlying)
    local gliding = BooleanCall(C_PlayerInfo and C_PlayerInfo.GetGlidingInfo)
    if flying == true or gliding == true then return "flying" end
    if flying == false then return "ground" end
    return "unknown"
end

local airborne = setmetatable({}, { __mode = "k" })
local flightChecks = setmetatable({}, { __mode = "k" })

function Walking.Forget(record)
    airborne[record], flightChecks[record] = nil, nil
end

function Walking.UpdateFlight(record, backend, mode, followGround)
    local leg, generation = record.currentLeg, record._routeAcceptedPlanGeneration
    local saved = airborne[record]
    if saved and (saved.generation ~= generation or saved.leg ~= leg) then
        Walking.Forget(record); saved = nil
    end
    -- Flight shortcuts replace route geometry, which core defers during combat.
    if mode == "taxi" or mode == "unknown" or InCombatLockdown() then return false end
    if saved then
        if mode == "flying" and not followGround and saved.mapID == NS.GetPlayerMapID() then return false end
        local ground = saved.ground
        if not NS.ReplaceActiveRouteLegs(record, leg, generation, ground) then return false end
        Walking.Forget(record)
        local section = ground[1].walking.group
        section.joined, section.createdAt = nil, GetTime()
        backend.PollNavigationLeg(record)
        -- Restoration is temporary continuity. The existing planning coordinator
        -- rebuilds from the landing position once, without replaying old roads.
        NS.RequestRoutePlan(record, NS.GetSelectedBackendID(), record.meta, "refresh")
        return true
    end
    local w = leg and leg.walking
    if mode ~= "flying" or followGround or not w or not w.group.airborne then
        flightChecks[record] = nil; return false
    end
    local check = flightChecks[record]
    if check and check.group == w.group and check.generation == generation then return false end
    flightChecks[record] = { group = w.group, generation = generation }
    if not backend.CanFlyWalkingSection or not backend.CanFlyWalkingSection(record, w.group) then return false end
    local ground, endpoint = {}, nil
    for i = record.currentLegIndex or 1, #record.legs do
        local candidate = record.legs[i]
        local point = candidate.walking
        if not point or point.group ~= w.group or candidate.specialAction or candidate.arrivalGate then return false end
        ground[#ground + 1] = candidate
        if point.required then
            endpoint = candidate; break
        end
    end
    if not endpoint or #ground < 2 then return false end
    local shortcut = {}
    for key, value in pairs(endpoint) do shortcut[key] = value end
    shortcut.walking = nil
    shortcut.airborneShortcut, shortcut.fixedWalkingGeometry = true, true
    shortcut.routeGeometryKey = (endpoint.routeGeometryKey or "") .. ":airborne"
    if not NS.ReplaceActiveRouteLegs(record, leg, generation, { shortcut }, endpoint) then return false end
    airborne[record] = {
        ground = ground,
        leg = shortcut,
        generation = record._routeAcceptedPlanGeneration,
        mapID = NS.GetPlayerMapID()
    }
    return true
end

-- ============================================================
-- Binding a walking section
-- ============================================================

-- Copied, normalized geometry, native tables never enter this description.
function Walking.Bind(leg, group, from, to, required)
    group.createdAt = group.createdAt or GetTime()
    local dx, dy = to.wx - from.wx, to.wy - from.wy
    local length = math.sqrt(dx * dx + dy * dy)
    local start = group.boundDistance or 0
    leg.walking = {
        group = group,
        from = from,
        to = to,
        required = required == true,
        start = start,
        length = length,
        ux = length > 0 and dx / length or 0,
        uy = length > 0 and dy / length or 0
    }
    group.boundDistance = start + length
end

-- A required stop cannot be skipped by ordinary progress. It can still become
-- obsolete when the player takes another route. Adapters replan that case;
-- this test is not permission to advance across a passage or a transport.
function Walking.Deviation(walk, c, x, y, z, radius)
    local a, b = walk.from, walk.to
    if c ~= a.c or c ~= b.c then return "continent_changed" end
    local dx, dy = b.wx - a.wx, b.wy - a.wy
    local length = dx * dx + dy * dy
    local t = length > 0 and math.max(0, math.min(1, ((x - a.wx) * dx + (y - a.wy) * dy) / length)) or 0
    if (x - a.wx - dx * t) ^ 2 + (y - a.wy - dy * t) ^ 2 > radius ^ 2 then return "off_path" end
    -- A vertical segment includes both decks while it is being traversed.
    -- Never infer the player's floor from the nearest later segment.
    if Finite(z) and Finite(a.z) and Finite(b.z)
        and (z < math.min(a.z, b.z) - 10 or z > math.max(a.z, b.z) + 10) then
        return "wrong_floor"
    end
end

function Walking.OriginMatches(ticket, c, x, y, z, maxDistance)
    return c == ticket.c and Finite(x) and Finite(y)
        and (not Finite(ticket.z) or not Finite(z) or math.abs(ticket.z - z) <= 10)
        and (not maxDistance or (x - ticket.x) ^ 2 + (y - ticket.y) ^ 2 < maxDistance ^ 2)
end

function Walking.CancelRecovery(state, expected)
    local recovery = state and state.walkRecovery
    if not recovery or expected and recovery.ticket ~= expected then return end
    state.walkRecovery = nil
    if recovery.timer then recovery.timer:Cancel() end
    local ticket = recovery.ticket
    if ticket then
        ticket.cancelled = true
        if ticket.cancel then ticket.cancel() end
    end
end

function Walking.CompleteRecovery(state, ticket, success, reason)
    local recovery = state.walkRecovery
    if not recovery or recovery.ticket ~= ticket then return end
    recovery.ticket, recovery.failed = nil, not success
    recovery.reason = reason or (success and "recovered" or "search_failed")
    recovery.failedAt = not success and GetTime() or nil
end

-- Only an actual deviation calls this. One deadline wakes the existing
-- movement monitor, idle ticks never perform searches or expand road data.
function Walking.BeginRecovery(state, record, c, x, y, z, policy, reason, earliestAt)
    if not Finite(c) or not Finite(x) or not Finite(y) or Walking.ReadMode() == "taxi" then return end
    local leg, generation = record.currentLeg, record._routeAcceptedPlanGeneration
    local recovery = state.walkRecovery
    if recovery and (recovery.leg ~= leg or recovery.generation ~= generation) then
        Walking.CancelRecovery(state); recovery = nil
    end
    if not recovery then
        recovery = { leg = leg, generation = generation }
        state.walkRecovery = recovery
    end
    if recovery.ticket then return end
    local now, deadline = GetTime(), earliestAt or 0
    if recovery.asked then deadline = math.max(deadline, recovery.asked + policy.interval) end
    -- Give a player already following the outgoing road a chance to confirm
    -- it before launching a search. The existing deadline also wakes at rest.
    if state.rejoinAlong and state.progressLeg == leg then
        deadline = math.max(deadline, state.rejoinAt + policy.interval)
    end
    if recovery.failed then
        local moved = c ~= recovery.c or (x - recovery.x) ^ 2 + (y - recovery.y) ^ 2 >= policy.retryDistance ^ 2
            or Finite(z) and Finite(recovery.z) and math.abs(z - recovery.z) > 10
        if not moved then return end
        deadline = math.max(deadline, recovery.failedAt + policy.retrySeconds)
    end
    if now < deadline then
        if not recovery.timer then
            recovery.timer = C_Timer.NewTimer(deadline - now, function()
                recovery.timer = nil
                if state.walkRecovery == recovery and record.currentLeg == leg
                    and record._routeAcceptedPlanGeneration == generation then
                    NS.RequestRouteNavigationProgress(record, "walking_recovery_ready")
                end
            end)
        end
        return
    end
    if recovery.timer then
        recovery.timer:Cancel(); recovery.timer = nil
    end
    local ticket = { leg = leg, generation = generation, c = c, x = x, y = y, z = z }
    recovery.ticket, recovery.asked, recovery.reason = ticket, now, reason
    recovery.c, recovery.x, recovery.y, recovery.z = c, x, y, z
    return ticket
end

-- ============================================================
-- Fixed walking legs
-- ============================================================

-- Backend-specific readers supply copied world/map points and required anchors.
-- Stage construction and the progress contract are shared across road engines.
function Walking.BuildFixedLegs(points, endpoint, source, title)
    if type(points) ~= "table" or #points < 2 or #points == 2 and not Finite(points[2].z) then return { endpoint } end
    local legs, group = {}, { airborne = points.airborne }
    for index = 2, #points do
        local point, previous = points[index], points[index - 1]
        local leg = index == #points and endpoint or {
            mapID = point.mapID,
            x = point.x,
            y = point.y,
            title = title or "Follow the path",
            kind = "walk",
            routeLegKind = "carrier",
            routeTravelType = "travel",
            source = source,
            arrivalRadius = Walking.ArrivalRadius(previous, point, points[index + 1]),
        }
        leg.fixedWalkingGeometry, leg.preservePlanOnArrival = true, true
        Walking.Bind(leg, group, previous, point, point.required)
        if leg ~= endpoint then
            local description = endpoint.walkingDescription
            NS.Internal.RouteWalkingPresentation.Describe(leg, description and description.mode or "path", endpoint,
                description and description.name, description and description.instruction)
        end
        leg.routeGeometryKey = table.concat({ previous.c, previous.wx, previous.wy, point.wx, point.wy,
            point.required and "stop" or "corner", points.airborne and points.airborne.container or "ground" }, ":")
        if Finite(previous.z) or Finite(point.z) then
            leg.routeGeometryKey = leg.routeGeometryKey .. ":" .. tostring(previous.z) .. ":" .. tostring(point.z)
        end
        legs[#legs + 1] = leg
    end
    group.endpoint = legs[#legs]
    -- A backend refining one itinerary edge at a time can certify the start
    -- of the following edge. It is evidence for passing this junction only.
    -- The following leg keeps its own planner, arrival and publication.
    local exit = points.continuation
    if exit then
        Walking.Bind(exit, group, points[#points], exit.to, true)
        group.continuation = exit
        endpoint.routeGeometryKey = endpoint.routeGeometryKey .. ":exit:" .. exit.to.wx .. ":" .. exit.to.wy
            .. ":" .. tostring(exit.to.z)
    end
    return legs
end

local function SegmentForLeg(group, leg)
    if not leg then return end
    if leg.walking then return leg.walking end
    local exit = group.continuation
    if exit and exit.leg == leg then return exit.walking end
end

-- ============================================================
-- Passed points and floor matching
-- ============================================================

-- Adjacent fixed segments only. Callers own combat, floor/transition gates,
-- plan identity and advancement, this helper owns the movement observation.
local function Passed(state, leg, nextWalk, c, x, y, z, generation, now, observedAt)
    local w = leg.walking
    local group, to = w.group, w.to
    local oldX, oldY, oldZ, oldAt, oldSpeed = state.progressX, state.progressY, state.progressZ, state.progressAt,
        state.progressSpeed
    local same = state.progressGroup == group and state.progressGeneration == generation and state.progressC == c
    local sameLeg, approached = state.progressLeg == leg, state.progressApproached
    if same and sameLeg and oldAt and oldX == x and oldY == y and oldZ == z then return nil, "unchanged" end
    -- Idle scalar observations keep an approach current without rerunning
    -- geometry or pathfinding. A long gap without observations remains stale.
    if same and sameLeg and oldAt and Finite(observedAt) and observedAt > oldAt and observedAt <= now then oldAt =
        observedAt end
    state.progressGroup, state.progressGeneration, state.progressC = group, generation, c
    state.progressLeg, state.progressX, state.progressY, state.progressZ, state.progressAt = leg, x, y, z, now
    state.progressSpeed = Walking.Speed()
    state.progressApproached = false
    if not nextWalk or nextWalk.to.c ~= c then return nil, "no_adjacent_segment" end
    if Finite(to.z) and (not Finite(z) or math.abs(z - to.z) > 10) then return nil, "wrong_floor" end
    local along, lateral, incoming = Segment(w, x, y)
    local outgoingAlong, outgoingLateral, outgoing = Segment(nextWalk, x, y)
    if incoming < 0.01 or outgoing < 0.01 then return nil, "short_segment" end
    local corridor = math.min(10, math.min(incoming, outgoing) * 0.5)
    local near = math.min(20, math.min(incoming, outgoing) * 0.5)
    local onIncoming = along >= 0 and along <= incoming and lateral <= corridor ^ 2
    local onOutgoing = outgoingAlong > 0 and outgoingAlong <= outgoing and outgoingLateral <= corridor ^ 2
    local nearPoint = (x - to.wx) ^ 2 + (y - to.wy) ^ 2 <= near ^ 2
    state.progressApproached = onIncoming and nearPoint
        or same and sameLeg and approached and onOutgoing and nearPoint
    if not same or not oldAt or now <= oldAt or now - oldAt > 1 then
        state.progressApproached = onIncoming and nearPoint; return nil, "initial_or_stale_sample"
    end
    local dx, dy = x - oldX, y - oldY
    local moved = dx * dx + dy * dy
    if moved <= 0 or moved > Walking.MovementLimit(now - oldAt, state.progressSpeed, oldSpeed) ^ 2 then
        state.progressApproached = onIncoming and nearPoint; return nil, "discontinuous_movement"
    end
    if Finite(to.z) and (not Finite(oldZ) or math.abs(oldZ - to.z) > 10) then return nil, "wrong_previous_floor" end
    local oldAlong, oldLateral = Segment(w, oldX, oldY)
    local wasIncoming = oldAlong >= 0 and oldAlong <= incoming and oldLateral <= corridor ^ 2
    local oldNear = (oldX - to.wx) ^ 2 + (oldY - to.wy) ^ 2 <= near ^ 2
    local forward = dx * w.ux + dy * w.uy > 0
    local t = math.max(0, math.min(1, ((to.wx - oldX) * dx + (to.wy - oldY) * dy) / moved))
    local swept = wasIncoming and forward and
        (oldX + dx * t - to.wx) ^ 2 + (oldY + dy * t - to.wy) ^ 2 <= leg.arrivalRadius ^ 2
    local turn = w.ux * nextWalk.ux + w.uy * nextWalk.uy
    local passed = (wasIncoming and oldNear or sameLeg and approached) and onOutgoing and nearPoint and turn > -0.5
        and dx * nextWalk.ux + dy * nextWalk.uy > 0
    if swept then return "walking_swept_arrival" end
    if passed then return "walking_passed_point" end
    return nil, "outside_passing_corridor"
end

local function Ordinary(leg, group)
    local w = leg and leg.walking
    return w and w.group == group and not w.required and not leg.specialAction
        and not leg.arrivalGate and leg.routeLegKind ~= "destination"
end

local function FloorMatches(point, z)
    return not Finite(point.z) or Finite(z) and math.abs(point.z - z) <= 10
end

-- Compare finite road segments. Distance from the extension of a road past
-- its endpoint would also be zero, even while walking away from that road.
local function Project(w, x, y)
    local along, lateral = Segment(w, x, y)
    local onSegment = math.max(0, math.min(w.length, along))
    return w.start + onSegment, lateral + (along - onSegment) ^ 2
end

local REJOIN_WINDOW, REJOIN_SEGMENTS = Walking.RejoinDistance, 32
local REJOIN_CORRIDOR, REJOIN_MARGIN = 10, 4
local function OnProjectedFloor(w, along, z)
    if Finite(w.from.z) and Finite(w.to.z) then
        local height = w.from.z + (w.to.z - w.from.z) * (along - w.start) / w.length
        return Finite(z) and math.abs(z - height) <= 10
    end
    return FloorMatches(w.from, z) and FloorMatches(w.to, z)
end

-- ============================================================
-- Rejoining the route
-- ============================================================

local function Rejoin(state, record, index, c, x, y, z, oldZ, dx, dy, moved)
    local walk = record.currentLeg.walking
    local start, currentDistanceSq = Project(walk, x, y)
    if currentDistanceSq <= REJOIN_MARGIN ^ 2 then return nil, "on_current_segment" end

    -- Nearby branches must be distinguishable in world space as well as in
    -- route order. Multiple short adjoining segments at a bend are one place
    -- along the road, two passes through a crossing can be far apart along it.
    local firstNear = currentDistanceSq <= REJOIN_CORRIDOR ^ 2 and start or nil
    local best, bestIndex, bestAlong, bestDistanceSq
    local previous = walk
    for i = index + 1, math.min(#record.legs, index + REJOIN_SEGMENTS) do
        local leg = record.legs[i]
        local w = SegmentForLeg(walk.group, leg)
        if not Ordinary(record.legs[i - 1], walk.group) or not w or w.group ~= walk.group
            or w.from.c ~= c or w.to.c ~= c or w.start - start > REJOIN_WINDOW
            or w.length < .01 or leg.specialAction or leg.arrivalGate
            or previous.ux * w.ux + previous.uy * w.uy <= -.5
            or walk.ux * w.ux + walk.uy * w.uy <= -.9 then
            break
        end
        if i > index + 1 and (not FloorMatches(previous.from, z) or not FloorMatches(previous.from, oldZ)) then break end
        local along, distanceSq = Project(w, x, y)
        if distanceSq <= REJOIN_CORRIDOR ^ 2 and along - start <= REJOIN_WINDOW then
            if firstNear and along - firstNear > 2 * REJOIN_CORRIDOR then return nil, "ambiguous_branch" end
            firstNear = firstNear or along
            if not bestDistanceSq or distanceSq < bestDistanceSq then
                best, bestIndex, bestAlong, bestDistanceSq = w, i, along, distanceSq
            end
        end
        previous = w
    end
    if not best or math.sqrt(bestDistanceSq) + REJOIN_MARGIN >= math.sqrt(currentDistanceSq) then
        return nil, "no_clear_rejoin"
    end
    -- Where the backend supplied heights, check the floor at the projection.
    -- The endpoint can be higher on a gradual slope. An unknown player height
    -- cannot establish passage on a known floor.
    local previousAlong = Project(best, x - dx, y - dy)
    if not OnProjectedFloor(best, bestAlong, z) or not OnProjectedFloor(best, previousAlong, oldZ) then
        return nil, "wrong_floor"
    end
    local forward = dx * best.ux + dy * best.uy
    if forward <= 0 or forward * forward < .49 * moved then return nil, "not_following_segment" end

    -- Require continued forward travel on the same stretch (possibly across
    -- several short segments). A single relocation or crossing cannot commit.
    local last = state.rejoinAlong
    if not last or bestAlong <= last or bestAlong - last > math.sqrt(moved) * 1.5 + 1 then
        state.rejoinStart, state.rejoinAt = bestAlong, state.progressAt
    end
    state.rejoinAlong = bestAlong
    if bestAlong - state.rejoinStart >= 3 then return bestIndex, "walking_rejoin" end
    return nil, "confirming_rejoin"
end

-- Establish passage in order, using one observation for all crossed points.
-- The swept corridor must contain every crossed corner, not just a later
-- segment near the player. This prevents switchbacks from becoming shortcuts.
function Walking.Progress(state, record, c, x, y, z, observedAt)
    local index, leg = record.currentLegIndex or 1, record.currentLeg
    local w = leg and leg.walking
    if not w then return false end
    local group, generation, now = w.group, record._routeAcceptedPlanGeneration, GetTime()
    local nextLeg = record.legs[index + 1]
    local nextWalk = SegmentForLeg(group, nextLeg)
    local oldX, oldY, oldZ, oldAt = state.progressX, state.progressY, state.progressZ, state.progressAt
    local oldSpeed = state.progressSpeed
    local same = state.progressGroup == group and state.progressGeneration == generation and state.progressC == c
    if same and Finite(observedAt) and oldAt and observedAt > oldAt and observedAt <= now then oldAt = observedAt end
    local pending = state.catchUp
    state.catchUp = nil
    local continuing = pending and pending.leg == leg and pending.generation == generation and pending.c == c
        and pending.x == x and pending.y == y and pending.z == z
    if continuing then
        oldX, oldY, oldZ, oldAt, same = pending.fromX, pending.fromY, pending.fromZ, pending.at, true
    end
    local joining = not group.joined and now - group.createdAt <= 1
    group.joined = true
    local sameLeg = state.progressLeg == leg
    local reason, rejection = Passed(state, leg, nextWalk and nextWalk.group == group and nextWalk,
        c, x, y, z, generation, now, observedAt)
    if rejection == "unchanged" and not continuing then return false end
    state.lastRejection = rejection
    if not Ordinary(leg, group) then
        state.rejoinAlong, state.lastRejection = nil, "required_stop"
        return false
    end
    if joining then
        oldX, oldY, oldZ, oldAt = w.from.wx, w.from.wy, w.from.z, group.createdAt
        same = w.from.c == c
    end
    local elapsed = oldAt and now - oldAt
    local dx, dy = oldX and x - oldX, oldY and y - oldY
    local moved = dx and dy and dx * dx + dy * dy
    local limit = Walking.MovementLimit(elapsed or 0, state.progressSpeed, oldSpeed)
    state.movementAllowance = limit
    local selected = reason and index + 1 or nil
    local continuous = same and moved and moved > 0 and elapsed and elapsed >= 0 and elapsed <= 1 and moved <= limit ^ 2
    if same and moved and moved > 0 and (joining or continuing or continuous) then
        local along, lateral, length = Segment(w, oldX, oldY)
        local connected = continuing or lateral <= 100 and along >= -10 and along <= length + leg.arrivalRadius
        local sweptAlong = continuing and pending.sweptAlong or -10
        local span = math.sqrt(moved)
        for i = index, math.min(#record.legs - 1, index + 127) do
            local current, following = record.legs[i], record.legs[i + 1]
            local a, b = current.walking, SegmentForLeg(group, following)
            if not connected or not Ordinary(current, group) or not b or b.group ~= group
                or a.from.c ~= c or a.to.c ~= c or b.to.c ~= c
                or not FloorMatches(a.to, z) or not FloorMatches(a.to, oldZ) then
                break
            end
            if a.length < .01 or b.length < .01 or a.ux * b.ux + a.uy * b.uy <= -.5
                or dx * a.ux + dy * a.uy <= 0 or dx * b.ux + dy * b.uy <= 0 then
                break
            end
            local projection = ((a.to.wx - oldX) * dx + (a.to.wy - oldY) * dy) / span
            local t = math.max(0, math.min(1, projection / span))
            if projection < sweptAlong or projection < 0 or projection > span + current.arrivalRadius
                or (oldX + t * dx - a.to.wx) ^ 2 + (oldY + t * dy - a.to.wy) ^ 2 > 100 then
                break
            end
            sweptAlong = projection
            local outAlong, outLateral = Segment(b, x, y)
            if outAlong > 0 and outLateral <= 100 then selected = i + 1 end
        end
    end
    if not selected and continuous and sameLeg and elapsed > 0 and not joining and not continuing
        and nextWalk and nextWalk.group == group then
        selected, reason = Rejoin(state, record, index, c, x, y, z, oldZ, dx, dy, moved)
        state.lastRejection = reason
    end
    if state.lastRejection ~= "confirming_rejoin" then state.rejoinAlong = nil end
    if not selected then return false end
    if reason ~= "walking_rejoin" then
        reason = joining and "walking_join" or selected > index + 1 and "walking_catch_up" or reason or
        "walking_passed_point"
    end
    if NS.AdvanceActiveWalkingLegs(record, leg, generation, selected, reason) then
        Walking.CancelRecovery(state)
        state.lastAdvanced, state.lastRejection = selected - index, nil
        if selected == index + 128 then
            -- Carry the already validated movement observation across the work
            -- budget only while the player, leg and generation stay unchanged.
            state.catchUp = {
                leg = record.currentLeg,
                generation = generation,
                c = c,
                x = x,
                y = y,
                z = z,
                fromX = oldX,
                fromY = oldY,
                fromZ = oldZ,
                at = oldAt,
                sweptAlong = ((record.legs[selected - 1].walking.to.wx - oldX) * dx
                    + (record.legs[selected - 1].walking.to.wy - oldY) * dy) / math.sqrt(moved)
            }
        end
        return true
    end
    return false
end

function Walking.ProgressReason(record, state)
    local leg = record and record.currentLeg
    if not leg or not leg.walking then return nil end
    if leg.walking.required then return "required_stop" end
    if state and state.progressLeg == leg and state.progressGeneration == record._routeAcceptedPlanGeneration then
        return state.lastRejection
    end
    return "awaiting_movement"
end

function Walking.ArrivalRadius(from, to, nextPoint)
    local distance = math.sqrt((to.wx - from.wx) ^ 2 + (to.wy - from.wy) ^ 2)
    if nextPoint then
        distance = math.min(distance,
            math.sqrt((nextPoint.wx - to.wx) ^ 2 + (nextPoint.wy - to.wy) ^ 2))
    end
    return math.max(1, math.min(5, distance / 2))
end
