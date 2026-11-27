-- ============================================================
-- RestedXP guide provider
-- ============================================================
--
-- Tracks RestedXP's active guide, waypoint loops and travel instructions and
-- exposes its native guide actions.

local NS = _G.AzerothWaypointNS
local P = NS.Internal.RXPPresentation
local API = { counters = { received = 0, coalesced = 0, built = 0, reused = 0, waypoint = 0 } }
NS.Internal.RXPProvider = API
local snapshot, target, requestedIntent, worldLoading
local listeners, hooked = {}, setmetatable({}, { __mode = "k" })
local routeSchedule, reason, nativeRefresh
local viewerMenuAnchor, menuRuntime
local gate, empty = {}, {}
local lastStepSelection
local guideEpoch = 0
local loopCursor
local flightLookup, travelIntent, flightCompletion
local requiredMethods = { "GetGuideProgress", "SetStep", "RegisterMessage", "GetGuideTable", "LoadGuide",
    "ReloadGuide", "ActiveStepElementPostClick", "UpdateMap", "UpdateGotoSteps" }
local gateFields = { "zone", "mapID", "x", "y", "wx", "wy", "instance", "wpHash", "hidden", "skip", "completed", "arrow",
    "title", "arrowtext", "lowPrio", "tag", "questId", "obj", "objIndex" }

-- AceAddon owns the object, these are RXP's current engine extensions, not
-- methods on AceAddon or on the separate RXPGuides registration facade.
---@class AWP_RXPRuntime: AceAddon
---@field currentGuide table?
---@field emptyGuide table
---@field settings table?
---@field RXPFrame table?
---@field player table?
---@field arrowFrame table?
---@field activeWaypoints table?
---@field ui table?
---@field v2 table?
---@field addonLoaded boolean?
---@field isHidden boolean?
---@field RegisterMessage function
---@field GetGuideProgress function
---@field SetStep function
---@field ReloadGuide function
---@field LoadGuide function
---@field ActiveStepElementPostClick function
---@field IsQuestTurnedIn function
---@field IsStepShown function
---@field UpdateMap function
---@field UpdateGotoSteps function
---@field ShowMenu function?
---@field FPDB table?
---@field taxiPos table?
---@field SetElementComplete function?

---@return AWP_RXPRuntime?
function API.GetRuntime()
    if not LibStub then return nil end
    local ok, ace = pcall(LibStub, "AceAddon-3.0", true)
    if not ok or not ace or type(ace.GetAddon) ~= "function" then return nil end
    local found, rxp = pcall(ace.GetAddon, ace, "RXPGuides", true)
    if not found or type(rxp) ~= "table" then return nil end
    ---@cast rxp AWP_RXPRuntime
    for _, name in ipairs(requiredMethods) do if type(rxp[name]) ~= "function" then return nil end end
    return rxp
end

function NS.IsRXPLoaded() return API.GetRuntime() ~= nil end

local function Secret(value) return type(issecretvalue) == "function" and issecretvalue(value) end
local function Numeric(value) return type(value) == "number" and not Secret(value) end
local function GuideID(rxp)
    local guide = rxp and rxp.currentGuide
    if guide and not guide.empty and type(guide.group) == "string" and type(guide.name) == "string" then
        return guide.group .. "||" .. guide.name
    end
end

function API.IsPaused(rxp)
    local profile = rxp and rxp.settings and rxp.settings.profile
    return profile and (profile.showEnabled == false or profile.hideGuideWindow == true
        or rxp.isHidden == true and not worldLoading) or false
end

local function LocalStep(rxp, element)
    local node = element
    for _ = 1, 8 do
        if type(node) ~= "table" then return nil end
        local step = node.step
        if step and step.active and step.index and rxp.currentGuide and rxp.currentGuide.steps
            and rxp.currentGuide.steps[step.index] == step then
            return step
        end
        node = node.source or node.anchor
    end
end

-- ============================================================
-- Death steps and eligible goals
-- ============================================================

local function DeathStep(rxp)
    for _, step in ipairs(rxp.RXPFrame.activeSteps or {}) do
        for _, element in ipairs(step.elements or {}) do
            if element.tag == "deathskip" and step.active then return step end
        end
    end
end

local function Eligible(rxp, element)
    if type(element) ~= "table" or element.hidden or element.skip or element.arrow == false then return nil end
    if type(element.parent) == "table" and (element.parent.skip or element.parent.completed) and not element.parent.textOnly then return nil end
    if element.completed and not element.textOnly then return nil end
    local step = LocalStep(rxp, element)
    if not step and element.generated == 1 and element.wpHash == 0 then step = DeathStep(rxp) end
    if not step or step.completed or step.skip or not element.arrow and not element.generated then return nil end
    return step
end

local function Coordinates(element)
    local map = element.zone or element.mapID
    if Numeric(map) and map > 0 and Numeric(element.x) and Numeric(element.y) then
        local x, y = element.x / 100, element.y / 100
        if x >= 0 and x <= 1 and y >= 0 and y <= 1 then return map, x, y end
    end
    if Numeric(element.wx) and Numeric(element.wy) and LibStub then
        local ok, hbd = pcall(LibStub, "HereBeDragons-2.0", true)
        if ok and hbd then
            if not Numeric(map) then map = P.Call(hbd, "GetPlayerZone", hbd) end
            if Numeric(map) then
                local x, y = P.Call(hbd, "GetZoneCoordinatesFromWorld", hbd, element.wx, element.wy, map)
                if Numeric(x) and Numeric(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return map, x, y end
            end
        end
    end
end

local function NativeSelection(rxp)
    local selected = rxp.arrowFrame and rxp.arrowFrame.element
    local step = Eligible(rxp, selected)
    local map, x, y
    if step then map, x, y = Coordinates(selected) end
    if map then return selected, step, map, x, y end
    for pass = 1, 2 do
        for _, element in ipairs(rxp.activeWaypoints or {}) do
            step = Eligible(rxp, element)
            if step and (pass == 2 or not element.lowPrio) then
                map, x, y = Coordinates(element)
                if map then return element, step, map, x, y end
            end
        end
    end
end

-- #loop repeats authored gotos, .loop/.line have a different native engine.
-- With disableArrow, RXP reopens reached #loop points whenever its hidden
-- arrow is tested. Own only the simple arrival sequence, never native flags.
-- Cursor records contain copied scalars, not retained RXP steps/elements.
local function LoopStep(rxp)
    local cursor = loopCursor
    local guide = rxp.currentGuide
    if not cursor or not guide or cursor.epoch ~= guideEpoch or cursor.group ~= guide.group
        or cursor.name ~= guide.name or cursor.key ~= guide.key or worldLoading or API.IsPaused(rxp)
        or not (rxp.settings and rxp.settings.profile and rxp.settings.profile.disableArrow)
        or not NS.IsRoutingEnabled() or P.Call(rxp, "GetGuideProgress") ~= cursor.progress then
        return nil
    end
    local step = guide.steps and guide.steps[cursor.step]
    if step and type(step.elements) == "table" and step.active and step.loop and not step.skip and not step.completed and not step.hidden
        and step.stepId == cursor.stepID and #step.elements == cursor.elementCount then
        return step
    end
end

-- ============================================================
-- Loop point selection
-- ============================================================

local function LoopPointMatches(point, element)
    return element and element.tag == "goto" and not element.generated and not element.dynamic
        and not element.activationRadius and not element.currentObjective and not element.persistent
        and element.textOnly and element.radius == point.radius
        and (element.zone or element.mapID) == point.sourceMap and element.x == point.sourceX
        and element.y == point.sourceY and element.wx == point.sourceWX and element.wy == point.sourceWY
        and element.instance == point.sourceInstance
end

local function LoopPointAvailable(element)
    local parent = type(element.parent) == "table" and element.parent
    return element.arrow and not element.hidden
        and not (parent and (parent.completed or parent.skip) and not parent.textOnly)
end

local function BuildLoopCursor(rxp, step, current)
    if not step or not step.loop or not step.active or not Numeric(step.index)
        or step.completed or step.skip or step.hidden then
        return nil
    end
    local ok, hbd = pcall(LibStub, "HereBeDragons-2.0", true)
    if not ok or not hbd or type(hbd.GetPlayerWorldPosition) ~= "function"
        or type(hbd.GetWorldVector) ~= "function" then
        return nil
    end
    local points = {}
    local resolved = P.ResolveStep(rxp, step)
    for ordinal, element in ipairs(step.elements or {}) do
        -- Never partially take over a mixed/generated/conditional sequence.
        if element.tag == "line" or element.tag == "loop" or element.generated then return nil end
        if element.arrow and (element.zone or element.mapID or element.wx) then
            if element.tag ~= "goto" or not element.textOnly or not Numeric(element.radius) or element.radius <= 0
                or element.dynamic or element.activationRadius or element.currentObjective or element.persistent then
                return nil
            end
            if Secret(element.wx) or Secret(element.wy) or Secret(element.instance) then return nil end
            local map, x, y = Coordinates(element)
            if not map then return nil end
            local wx, wy, instance = element.wx, element.wy, element.instance
            if not Numeric(wx) or not Numeric(wy) or not Numeric(instance) then
                wx, wy, instance = P.Call(hbd, "GetWorldCoordinatesFromZone", hbd, x, y, map)
            end
            if not Numeric(wx) or not Numeric(wy) or not Numeric(instance) then return nil end
            local owner = P.OwnerOrdinal(step, element, resolved)
            if not owner or resolved.elements[owner].role ~= "action" then owner = nil end
            local objective = owner and step.elements[owner]
            points[#points + 1] = {
                ordinal = ordinal,
                mapID = map,
                x = x,
                y = y,
                wx = wx,
                wy = wy,
                instance = instance,
                radius = element.radius,
                owner = owner,
                ownerTag = objective and objective.tag,
                ownerQuestID = objective and objective.questId,
                ownerObjective = objective and (objective.obj or objective.objIndex),
                ownerID = objective and objective.id,
                sourceMap = element.zone or element.mapID,
                sourceX = element.x,
                sourceY = element.y,
                sourceWX = element.wx,
                sourceWY = element.wy,
                sourceInstance = element.instance
            }
        end
    end
    if #points == 0 then return nil end
    local guide = rxp.currentGuide
    return {
        group = guide.group,
        name = guide.name,
        key = guide.key,
        epoch = guideEpoch,
        step = step.index,
        stepID = step.stepId,
        elementCount = #step.elements,
        progress = current,
        points = points,
        index = 1,
        hbd = hbd
    }
end

local function UpdateLoopCursor(step)
    local cursor = loopCursor
    local points, hbd = cursor.points, cursor.hbd
    local px, py, instance = P.Call(hbd, "GetPlayerWorldPosition", hbd)
    local positioned = Numeric(px) and Numeric(py) and Numeric(instance) and instance ~= -1
    for _, point in ipairs(points) do
        local element = step.elements[point.ordinal]
        if not LoopPointMatches(point, element) then return false end
        point.available = LoopPointAvailable(element)
        local owner = point.owner and step.elements[point.owner]
        if point.owner and (not owner or owner.tag ~= point.ownerTag or owner.questId ~= point.ownerQuestID
                or (owner.obj or owner.objIndex) ~= point.ownerObjective or owner.id ~= point.ownerID) then
            return false
        end
        if owner and (owner.completed or owner.skip or owner.hidden) then point.available = false end
        point.inside = nil
        if positioned then
            if instance == point.instance then
                local _, distance = P.Call(hbd, "GetWorldVector", hbd, instance, px, py, point.wx, point.wy)
                if Numeric(distance) and distance >= 0 then point.inside = distance <= point.radius end
            else
                point.inside = false
            end
        end
        -- Overlapping/single-point loops must not spin at rest. A reached
        -- point becomes consumable again only after leaving its radius.
        if point.inside == false then point.consumed = false end
    end
    for _ = 1, #points do
        local point = points[cursor.index]
        if point.available and (point.inside ~= true or point.consumed) then break end
        if point.available then point.consumed = true end
        cursor.index = cursor.index % #points + 1
    end
    return true
end

local function LoopSelection(step)
    local point = loopCursor.points[loopCursor.index]
    if point.available then return step.elements[point.ordinal], step, point.mapID, point.x, point.y, true end
    return nil, nil, nil, nil, nil, true
end

local function Selection(rxp, current)
    local selected, step, map, x, y = NativeSelection(rxp)
    -- Guide-linked deathskip remains RXP-owned even while an authored loop
    -- is active. Ordinary native resets cannot change the cursor's owner.
    if selected and selected.generated == 1 and selected.wpHash == 0 then
        loopCursor = nil
        return selected, step, map, x, y
    end
    local cursorStep = LoopStep(rxp)
    if cursorStep and UpdateLoopCursor(cursorStep) then return LoopSelection(cursorStep) end
    loopCursor = nil
    if rxp.settings and rxp.settings.profile and rxp.settings.profile.disableArrow and NS.IsRoutingEnabled() then
        if not step then
            for _, active in ipairs(rxp.RXPFrame.activeSteps or {}) do
                if active.active and active.loop and rxp.currentGuide.steps[active.index] == active then
                    step = active; break
                end
            end
        end
        loopCursor = BuildLoopCursor(rxp, step, current)
        if loopCursor and UpdateLoopCursor(step) then return LoopSelection(step) end
        loopCursor = nil
    end
    return selected, step, map, x, y
end

local function SharesQuestAction(a, b)
    for _, first in ipairs(a.elements or {}) do
        if first.questId and not first.skip and not first.completed
            and (first.tag == "accept" or first.tag == "turnin" or first.tag == "complete") then
            for _, second in ipairs(b.elements or {}) do
                if second.questId == first.questId and second.tag == first.tag
                    and not second.skip and not second.hidden then
                    return true
                end
            end
        end
    end
    return false
end

-- ============================================================
-- Hearth and travel destinations
-- ============================================================

local function HearthDestination(rxp, current)
    local guide = rxp.currentGuide
    local steps = guide and guide.steps
    if not steps then return end
    for _, origin in ipairs(rxp.RXPFrame.activeSteps or {}) do
        if origin.active and origin.index and steps[origin.index] == origin and not origin.skip and not origin.completed then
            local hearth
            for _, element in ipairs(origin.elements or {}) do
                if (element.tag == "hs" or element.tag == "hsbatching")
                    and not element.completed and not element.skip and not element.hidden
                    and element.arrow ~= false then
                    hearth = true; break
                end
            end
            if hearth then
                local destination
                if not origin.completewith or origin.completewith == "next" then
                    -- A normal hearth instruction immediately preceding its
                    -- destination. Never walk past intervening guide steps.
                    if current == origin.index or current == origin.index + 1 then
                        local following = steps[origin.index + 1]
                        if following and (not following.requires or following.requires == origin.label) then
                            destination = following
                        end
                    end
                else
                    -- Concurrent hearths can point backwards to a labelled
                    -- quest while its coordinate-bearing duplicate is waiting
                    -- at the current step. Require both the native label link
                    -- and matching quest/action identity before using it.
                    local anchorIndex = guide.labels and guide.labels[origin.completewith]
                    local anchor = anchorIndex and steps[anchorIndex]
                    local following = steps[current]
                    if anchor and anchorIndex == origin.index + 1
                        and (current == origin.index or current == anchorIndex)
                        and (not anchor.requires or anchor.requires == origin.label)
                    then
                        destination = anchor
                    elseif anchor and anchor.active and current > origin.index and following
                        and following.requires == origin.completewith and SharesQuestAction(anchor, following)
                    then
                        destination = following
                    end
                end
                if destination and not destination.skip and not destination.completed and not destination.hidden then
                    for _, element in ipairs(destination.elements or {}) do
                        -- Only an authored point can establish the arrival
                        -- destination, loops/generated points still belong to
                        -- native waypoint progression.
                        if element.tag == "line" or element.tag == "loop" then break end
                        if (element.tag == "goto" or element.tag == "waypoint") and element.arrow ~= false
                            and not element.skip and not element.hidden and not element.generated
                            and not (element.completed and not element.textOnly)
                        then
                            local map, x, y = Coordinates(element)
                            if map then return element, destination, map, x, y, origin.index end
                        end
                    end
                end
            end
        end
    end
end

local function FlightName(value)
    value = NS.Internal.GuidePresentation.NormalizeText(value)
    return value and value:upper()
end

local function SameScalars(a, b)
    if not a or not b then return a == b end
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key, value in pairs(b) do if a[key] ~= value then return false end end
    return true
end

-- Index only the requested name, timing tables and native nodes stay RXP-owned.
local function ResolveFlightNode(rxp, name)
    local faction = rxp.player and rxp.player.faction
    if not flightLookup or flightLookup.runtime ~= rxp or flightLookup.db ~= rxp.FPDB
        or flightLookup.positions ~= rxp.taxiPos or flightLookup.faction ~= faction then
        flightLookup = { runtime = rxp, db = rxp.FPDB, positions = rxp.taxiPos, faction = faction, names = {} }
    end
    local normalized = FlightName(name)
    if not normalized then return nil, "missing_flight_name" end
    local previous = flightLookup.names[normalized]
    if previous then return previous.node, previous.reason end
    local database = type(rxp.FPDB) == "table" and rxp.FPDB[faction]
    local exact, short, names, seen = {}, {}, {}, {}
    local function consider(id, name)
        if not Numeric(id) or id <= 0 or type(name) ~= "string" then return end
        local full = FlightName(name)
        if full == normalized then
            if seen[id] ~= "exact" then exact[#exact + 1] = id end
            seen[id], names[id] = "exact", name
        elseif not seen[id] then
            -- Guides also name zones, e.g. .fly Westfall. Require a complete
            -- comma-delimited name component, never an arbitrary substring.
            for part in name:gmatch("[^,]+") do
                if FlightName(part) == normalized then
                    short[#short + 1], seen[id], names[id] = id, "short", name; break
                end
            end
        end
    end
    for id, data in pairs(type(database) == "table" and database or empty) do
        if type(data) == "table" then consider(id, data.name) end
    end
    for _, nodes in pairs(type(rxp.taxiPos) == "table" and rxp.taxiPos or empty) do
        for id, point in pairs(type(nodes) == "table" and nodes or empty) do
            if type(point) == "table" then
                local flag = point.flag
                local permitted = type(database) == "table" and database[id] ~= nil
                    or Numeric(flag) and (faction == "Alliance" and flag % 2 == 1
                        or faction == "Horde" and math.floor(flag / 2) % 2 == 1)
                if permitted then consider(id, point.name) end
            end
        end
    end
    local matches = #exact > 0 and exact or short
    local node, failure
    if #matches ~= 1 then
        failure = #matches > 1 and "ambiguous_flight_name" or "unknown_flight_name"
    else
        local id = matches[1]
        node = { nodeID = id, name = names[id] }
        for world, nodes in pairs(type(rxp.taxiPos) == "table" and rxp.taxiPos or empty) do
            local point = type(nodes) == "table" and nodes[id]
            if Numeric(world) and type(point) == "table" and Numeric(point.wx) and Numeric(point.wy)
                and point.wx == point.wx and point.wy == point.wy
                and math.abs(point.wx) < math.huge and math.abs(point.wy) < math.huge then
                if node.worldID ~= nil then
                    node.worldID, node.worldX, node.worldY = nil, nil, nil
                    failure = "ambiguous_flight_position"; break
                end
                -- taxiPos uses UnitPosition order, HBD/C_Map use the reverse.
                node.worldID, node.worldX, node.worldY = world, point.wy, point.wx
            end
        end
        failure = failure or (node.worldID == nil and "missing_flight_position" or nil)
    end
    flightLookup.names[normalized] = { node = node, reason = failure }
    return node, failure
end

local function FlightStepReady(step, flight)
    for _, element in ipairs(step.elements or {}) do
        if element ~= flight and not element.completed and not element.skip and not element.hidden then
            local tag = element.tag
            -- Targeting metadata and authored prose do not require a visit.
            -- Quest/use/gossip actions and mandatory movement still do.
            if tag == "line" or tag == "loop" or element.generated then
                return false
            elseif tag == "goto" or tag == "waypoint" or tag == "groundgoto" or tag == "flygoto" then
                if not element.textOnly then return false end
            elseif tag ~= "target" and tag ~= "mob"
                and (not element.textOnly or tag == "use" or tag == "usespell" or tag == "cast"
                    or tag == "gossip" or tag == "gossipoption") then
                return false
            end
        end
    end
    return true
end

-- ============================================================
-- Flight instructions
-- ============================================================

local function FlightInstruction(rxp, current, selectedStep)
    local guide = rxp.currentGuide
    local candidate, owner, ordinal
    for _, step in ipairs(rxp.RXPFrame.activeSteps or {}) do
        local linked = step.completewith == "next" and step.index and step.index + 1
            or guide.labels and guide.labels[step.completewith]
        if step.active and not step.skip and not step.completed and not step.hidden
            and guide.steps[step.index] == step and (step.index == current or linked == current) then
            for index, element in ipairs(step.elements or {}) do
                if element.tag == "fly" and not element.completed and not element.skip
                    and not element.hidden and element.arrow ~= false then
                    if candidate and FlightName(candidate.location) ~= FlightName(element.location) then
                        return { reason = "conflicting_flight_instructions" }
                    end
                    if not candidate or step.index == current then candidate, owner, ordinal = element, step, index end
                end
            end
        end
    end
    if not candidate then return end
    local node, failure = ResolveFlightNode(rxp, candidate.location)
    local intent = {
        kind = "flight",
        guideID = GuideID(rxp),
        guideEpoch = guideEpoch,
        stepIndex = owner.index,
        currentStep = current,
        elementIndex = ordinal,
        destinationName = P.Text(rxp, candidate.location),
        nodeID = node and node.nodeID,
        name = node and node.name,
        reason = failure,
        routeEligible = FlightStepReady(owner, candidate) and (not selectedStep or selectedStep == owner),
    }
    if not intent.routeEligible then intent.reason = "departure_or_other_objective" end
    if node and node.worldID ~= nil and not failure then
        if not node.mapResolved then
            local map, x, y = P.Call(NS, "ResolveUserWaypointMapCoordsFromWorldPosition",
                node.worldX, node.worldY, nil, node.worldID)
            if Numeric(map) and map > 0 and Numeric(x) and Numeric(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                node.mapID, node.x, node.y = map, x, y
            end
            node.mapResolved = true
        end
        if node.mapID then
            intent.mapID, intent.x, intent.y = node.mapID, node.x, node.y
        else
            intent.reason = intent.reason or "unresolved_flight_map"
        end
    end
    return intent
end

function API.OnDestinationReached(record, expected)
    local rxp = API.GetRuntime()
    local intent = travelIntent
    if not rxp or not intent or expected ~= intent or not intent.routeEligible or worldLoading or API.IsPaused(rxp)
        or not record or not record.target or record.target.guideTravelIntent ~= intent
        or intent.guideID ~= GuideID(rxp) or intent.guideEpoch ~= guideEpoch
        or P.Call(rxp, "GetGuideProgress") ~= intent.currentStep
        or not target or target.guideTravelIntent ~= intent or type(rxp.SetElementComplete) ~= "function"
        or NS.GetActiveGuideProvider() ~= "rxp" or InCombatLockdown and InCombatLockdown() then
        return false
    end
    local step = rxp.currentGuide.steps[intent.stepIndex]
    local element = step and step.elements and step.elements[intent.elementIndex]
    if not step or not step.active or step.skip or step.completed or not element or element.tag ~= "fly"
        or element.skip or element.completed or element.hidden or element.arrow == false
        or FlightName(element.location) ~= FlightName(intent.destinationName) or not FlightStepReady(step, element) then
        return false
    end
    local ok = pcall(rxp.SetElementComplete, element)
    flightCompletion = ok and "completed_native_flight_instruction" or "native_completion_failed"
    API.Schedule("RXPFlightArrival")
    return ok
end

local function RememberGuide(id)
    local common = NS.Internal.GuideTrackerViewer
    if id and common then common.RememberOpenGuide("rxp", id) end
end

-- ============================================================
-- Guide refresh
-- ============================================================

local function Refresh()
    local handoffQuestIDs, handoffAction
    local rxp = API.GetRuntime()
    local guide = rxp and rxp.currentGuide
    local id = GuideID(rxp)
    if lastStepSelection and lastStepSelection.guide ~= id then lastStepSelection = nil end
    local state = "ready"
    if not rxp or not rxp.settings or not rxp.RXPFrame or worldLoading or rxp.addonLoaded == false then
        state = "loading"
    elseif API.IsPaused(rxp) then
        state = "paused"
    elseif not id then
        state = "empty"
    elseif not guide or not guide.steps or #guide.steps == 0 then
        state = "loading"
    end
    local current = rxp and P.Call(rxp, "GetGuideProgress") or 0
    current = type(current) == "number" and current or 0
    local total = guide and guide.steps and #guide.steps or 0
    local steps, retained = {}, {}
    if state == "ready" and rxp and rxp.RXPFrame then
        for _, step in ipairs(rxp.RXPFrame.activeSteps or {}) do
            if step.active and not step.hidewindow and not step.hidetip then
                local resolved, built = P.ResolveStep(rxp, step)
                API.counters[built and "built" or "reused"] = API.counters[built and "built" or "reused"] + 1
                steps[#steps + 1] = resolved; retained[step.index or "tip"] = true
            end
        end
    end
    local nextTarget
    local nextIntent
    local navigationReason = state == "ready" and "no_eligible_active_waypoint" or state
    if state == "ready" and rxp and id and guide and guide.steps then
        local element, step, map, x, y, loopOwned = Selection(rxp, current)
        nextIntent = FlightInstruction(rxp, current, step)
        if SameScalars(travelIntent, nextIntent) then nextIntent = travelIntent end
        local flightArrival
        if nextIntent and nextIntent.routeEligible and nextIntent.mapID then
            local flightStep = guide.steps[nextIntent.stepIndex]
            local flightElement = flightStep and flightStep.elements and flightStep.elements[nextIntent.elementIndex]
            if flightElement then
                flightArrival = true
                step, element = flightStep, flightElement
                map, x, y, loopOwned = nextIntent.mapID, nextIntent.x, nextIntent.y, nil
            end
        end
        local hearthOrigin
        if not element then element, step, map, x, y, hearthOrigin = HearthDestination(rxp, current) end
        if element and step and map and x and y then
            navigationReason = "unresolved_waypoint_owner"
            local resolved = P.ResolveStep(rxp, step)
            retained[step.index or "tip"] = true
            local ordinal, ownerReason, waypointOrdinal
            if flightArrival and nextIntent then
                ordinal, ownerReason = nextIntent.elementIndex, "flight_arrival"
            else
                ordinal, ownerReason, waypointOrdinal = P.OwnerOrdinal(step, element, resolved)
            end
            local fact = ordinal and resolved.elements[ordinal]
            if not fact and element.generated == 1 and element.wpHash == 0 then
                fact = {
                    title = P.Text(rxp, element.title),
                    action = "goto",
                    semanticKind = "travel",
                    semanticTravelType = "travel",
                    tag = "deathskip",
                    role = "action",
                    titleSource = "native_deathskip",
                    contextSource = "none",
                    tips = {}
                }; ownerReason = "deathskip"
            end
            if fact then
                handoffQuestIDs, handoffAction = fact.questCandidates, fact.questCandidates and fact.action
                local presentation = P.ResolveTargetPresentation(rxp, step, element, resolved, fact, waypointOrdinal)
                local title, titleSource = presentation.title, presentation.titleSource
                if not title then
                    local info = P.Call(C_Map, "GetMapInfo", map)
                    local name = info and P.Text(rxp, info.name)
                    title = name and ("Travel to " .. name) or "Guide waypoint"
                    titleSource = name and "map_name_fallback" or "generic_waypoint_fallback"
                end
                local context = presentation.context
                local travelType = P.ResolveTravelType(fact, map, x, y, title, context)
                if flightArrival and nextIntent then
                    local name = type(nextIntent.name) == "string" and
                        P.Text(rxp, string.match(nextIntent.name, "^([^,]+)")) or nextIntent.destinationName
                    title, titleSource, context, travelType = "Travel to " .. name, "resolved_flight_arrival", nil,
                        "travel"
                end
                nextTarget = {
                    mapID = map,
                    x = x,
                    y = y,
                    guideProvider = "rxp",
                    kind = "guide_goal",
                    title = title,
                    subtext = context,
                    semanticKind = travelType and "travel" or fact.semanticKind,
                    semanticTravelType = travelType,
                    semanticQuestID = fact.questID,
                    iconHintQuestID = fact.questID,
                    iconHintKind = travelType or ((fact.questID or fact.questCandidates) and "quest" or "guide"),
                    source = "rxp.step#" .. tostring(step.index),
                    guideStepIdentity = id .. "\031" .. tostring(step.stepId or step.index),
                    guideTravelIntent = flightArrival and nextIntent or nil,
                    rxpOwner = step.index,
                    rxpElement = ordinal,
                    rxpAction = fact.action,
                    rxpWaypoint = waypointOrdinal,
                    rxpElementTag = fact.tag,
                    rxpElementRole = fact.role,
                    rxpOwnerReason = hearthOrigin and ("hearth_followup:" .. ownerReason) or ownerReason,
                    rxpTravelSource = hearthOrigin,
                    rxpSuppression = fact.suppression,
                    rxpTitleSource = titleSource,
                    rxpContextSource = flightArrival and "none" or presentation.contextSource
                }
                NS.Internal.GuidePresentation.SetDestinationContext(nextTarget, not flightArrival and fact.npcName,
                    "npc", fact.action, fact.questID, title)
                navigationReason = flightArrival and "flight_arrival" or hearthOrigin and "hearth_followup" or
                    loopOwned and "loop_cursor" or "waypoint"
            end
        end
    end
    P.Retain(retained)
    local title = guide and (P.Call(rxp, "GetGuideName", guide) or guide.displayname or guide.name)
    title = rxp and P.Text(rxp, title) or nil
    local changed = not snapshot or snapshot.id ~= id or snapshot.state ~= state or snapshot.current ~= current
        or snapshot.total ~= total or snapshot.title ~= title or #snapshot.steps ~= #steps
        or snapshot.navigationReason ~= navigationReason or snapshot.guideEpoch ~= guideEpoch or
        travelIntent ~= nextIntent
        or snapshot.handoffQuestIDs ~= handoffQuestIDs or snapshot.handoffAction ~= handoffAction
    if not changed then
        for index = 1, #steps do
            if snapshot.steps[index] ~= steps[index] then
                changed = true; break
            end
        end
    end
    local targetChanged = (target == nil) ~= (nextTarget == nil)
    if target and nextTarget then
        for key, value in pairs(nextTarget) do
            if target[key] ~= value then
                targetChanged = true; break
            end
        end
        if not targetChanged then
            for key, value in pairs(target) do
                if nextTarget[key] ~= value then
                    targetChanged = true; break
                end
            end
        end
    end
    if changed or targetChanged then
        if id and (not snapshot or snapshot.id ~= id) then RememberGuide(id) end
        snapshot = {
            id = id,
            title = title,
            current = current,
            total = total,
            state = state,
            steps = steps,
            navigationReason = navigationReason,
            guideEpoch = guideEpoch,
            travelIntent = nextIntent,
            handoffQuestIDs = handoffQuestIDs,
            handoffAction = handoffAction
        }
        if nextIntent and travelIntent ~= nextIntent then flightCompletion = nil end
        travelIntent = nextIntent
        target = nextTarget
    end
    return changed or targetChanged
end

local function RunRefresh()
    local intent, refreshNative, why = requestedIntent, nativeRefresh, reason
    requestedIntent, nativeRefresh = false, false
    local previousTravel = travelIntent
    local changed = Refresh()
    if (changed or intent) and routeSchedule then
        routeSchedule(why or "RXPUpdated", intent and { explicit = true, allowProviderSwitch = true } or nil)
    end
    if changed or refreshNative then for _, callback in ipairs(listeners) do callback(snapshot, changed) end end
    if previousTravel ~= travelIntent and NS.GetActiveGuideProvider() == "rxp" and NS.RefreshFlightMapAssist then
        NS.RefreshFlightMapAssist()
    end
end

local refreshQueue = NS.Internal.Scheduling.CreateCoalescer(RunRefresh)

function API.Schedule(why, explicit)
    API.counters.received = API.counters.received + 1
    requestedIntent = requestedIntent or explicit
    if why == "guide_quest_dialog" then P.Invalidate() end
    nativeRefresh = nativeRefresh or why == "native_ui"
    reason = why
    if not refreshQueue:Request() then API.counters.coalesced = API.counters.coalesced + 1 end
end

function API.GetSnapshot()
    if not snapshot then Refresh() end; return snapshot
end

if NS.Internal.GuideQuestSelection then NS.Internal.GuideQuestSelection.Watch(API) end

function API.Subscribe(callback) listeners[#listeners + 1] = callback end

function API.Activate(why)
    API.Schedule(why, true)
    if NS.SelectGuideProvider then NS.SelectGuideProvider("rxp", why) end
end

local function ObserveWaypoint(rxp)
    local element = rxp.arrowFrame and rxp.arrowFrame.element or empty
    local step = element.step or element.source and element.source.step
    local cursorStep = LoopStep(rxp)
    local loopOwned = cursorStep and not (element.generated == 1 and element.wpHash == 0)
        and UpdateLoopCursor(cursorStep)
    if loopOwned then
        element, step = LoopSelection(cursorStep)
        element, step = element or empty, step or cursorStep
    elseif loopCursor then
        loopCursor = nil
    end
    local guide = rxp.currentGuide
    local parent = type(element.parent) == "table" and element.parent or empty
    local changed = gate.guide ~= (guide and guide.key) or gate.step ~= (step and step.index)
        or gate.active ~= (step and step.active) or gate.paused ~= API.IsPaused(rxp)
        or gate.parentSkip ~= parent.skip
        or gate.parentComplete ~= parent.completed or gate.loopOwned ~= (loopOwned == true)
    for _, field in ipairs(gateFields) do
        local value = element[field]
        if loopOwned and (field == "skip" or field == "lowPrio") then value = nil end
        if Secret(value) then return end
        if gate[field] ~= value then changed = true end
    end
    if not changed then return end
    gate.guide, gate.step, gate.active, gate.paused = guide and guide.key, step and step.index, step and step.active,
        API.IsPaused(rxp)
    gate.parentSkip, gate.parentComplete = parent.skip, parent.completed
    gate.loopOwned = loopOwned == true
    for _, field in ipairs(gateFields) do
        gate[field] = element[field]
        if loopOwned and (field == "skip" or field == "lowPrio") then gate[field] = nil end
    end
    API.counters.waypoint = API.counters.waypoint + 1
    API.Schedule("RXPWaypointChanged")
end

local function ExplicitCallback(original)
    return function(...)
        local result = original(...)
        if GuideID(API.GetRuntime()) then API.Activate("RXPNativeGuideSelected") end
        return result
    end
end

-- ============================================================
-- Viewer menus and guide selection
-- ============================================================

local function CopyMenu(rxp, menu, seen)
    if type(menu) ~= "table" then return menu end
    seen = seen or {}
    if seen[menu] then return seen[menu] end
    local copy = {}; seen[menu] = copy
    for key, value in pairs(menu) do
        if type(value) == "table" and type(key) == "number" then
            local entry = {}; copy[key] = entry
            for field, scalar in pairs(value) do entry[field] = scalar end
            if value.menuList then entry.menuList = CopyMenu(rxp, value.menuList, seen) end
            if type(value.func) == "function" and type(value.arg1) == "string" and type(value.arg2) == "string"
                and P.Call(rxp, "GetGuideTable", value.arg1, value.arg2) then
                entry.func = ExplicitCallback(value.func)
            end
        else
            copy[key] = value
        end
    end
    return copy
end

local function InstallHooks(schedule)
    routeSchedule = schedule
    local rxp = API.GetRuntime()
    if not rxp then return end
    if hooked[rxp] then return end
    hooked[rxp] = true
    for _, event in ipairs({ "RXP_GUIDE_LOADED", "RXP_STEP_ACTIVATED", "RXP_STEP_COMPLETE", "RXP_OBJECTIVE_COMPLETE",
        "RXPGuidesV2_GuideStepsChanged" }) do
        local message = event
        rxp:RegisterMessage(message, function()
            if message == "RXP_GUIDE_LOADED" then
                guideEpoch = guideEpoch + 1; lastStepSelection = nil; loopCursor = nil; flightLookup = nil
            end
            API.Schedule(message)
        end)
    end
    rxp:RegisterMessage("RXPGuidesV2_QuestDataLoaded", function(_, questID)
        if P.Invalidate("QUEST_DATA_LOAD_RESULT", questID) then API.Schedule("RXPQuestDataReady") end
    end)
    rxp:RegisterMessage("RXPGuidesV2_UpdateActiveSteps", function(_, _, player)
        if rxp.player and player == rxp.player.name then API.Schedule("RXPActiveSteps") end
    end)
    rxp:RegisterMessage("RXPGuidesV2_GuideWindowRefresh", function() API.Schedule("native_ui") end)
    if type(hooksecurefunc) == "function" then
        hooksecurefunc(rxp, "UpdateMap", function(reset) if reset then ObserveWaypoint(rxp) end end)
        hooksecurefunc(rxp, "UpdateGotoSteps", function() ObserveWaypoint(rxp) end)
        if rxp.settings and type(rxp.settings.ToggleActive) == "function" then
            hooksecurefunc(rxp.settings, "ToggleActive", function() API.Schedule("native_ui") end)
        end
    end
    local originalMenu = rxp.ShowMenu
    if type(originalMenu) == "function" then
        menuRuntime = rxp
        rxp.ShowMenu = function(self, menu, menuFrame, anchor, x, y, ...)
            if viewerMenuAnchor then anchor, x, y = viewerMenuAnchor, 0, 0 end
            return originalMenu(self, CopyMenu(rxp, menu), menuFrame, anchor, x, y, ...)
        end
    end
    local chooser = rxp.ui and rxp.ui.v2 and rxp.ui.v2.configurator
    if chooser and type(chooser.GetGuideChoices) == "function" then
        local original = chooser.GetGuideChoices
        chooser.GetGuideChoices = function(self, ...)
            local values = original(self, ...)
            local copy = {}
            for index, entry in ipairs(values or {}) do
                local value = {}; copy[index] = value
                for key, scalar in pairs(entry) do value[key] = scalar end
                if type(entry.callback) == "function" then value.callback = ExplicitCallback(entry.callback) end
            end
            return copy
        end
    end
end

function API.OpenViewerMenu(anchor)
    local rxp = API.GetRuntime()
    if not rxp or menuRuntime ~= rxp or type(rxp.ShowMenu) ~= "function" then return false end
    local v2 = rxp.v2
    local open, owner = rxp.RXPFrame and rxp.RXPFrame.DropDownMenu, nil
    if v2 and type(v2.IsGuideWindowEnabled) == "function" then
        local ok, enabled = pcall(v2.IsGuideWindowEnabled, v2)
        if not ok then return false end
        if enabled == true then open, owner = v2.ShowSettingsMenu, v2 end
    end
    if type(open) ~= "function" then return false end
    -- Both current native builders use ShowMenu synchronously. Scope the
    -- anchor to this invocation, later native menus and callbacks keep their
    -- original anchors and the existing explicit-selection handling.
    local previous = viewerMenuAnchor
    viewerMenuAnchor = anchor
    local ok = pcall(open, owner)
    viewerMenuAnchor = previous
    return ok
end

local function IsSelectableStep(rxp, guide, step)
    return step and not step.sticky and not step.hidewindow and not step.hidden and not step.disabled
        and P.Call(rxp, "IsStepShown", step, guide) == true
end

local function MissingQuest(rxp, questID)
    -- Read current game state, not historical element.completed/skip flags.
    -- RXP's turn-in query also covers its short event/API synchronization gap.
    if not Numeric(questID) or questID <= 0 or type(C_QuestLog) ~= "table"
        or type(C_QuestLog.IsOnQuest) ~= "function" or type(C_QuestLog.IsQuestFlaggedCompleted) ~= "function"
        or type(rxp.IsQuestTurnedIn) ~= "function" then
        return nil
    end
    local known, onQuest = pcall(C_QuestLog.IsOnQuest, questID)
    local completedKnown, completed = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
    local nativeKnown, nativeCompleted = pcall(rxp.IsQuestTurnedIn, questID)
    if not known or not completedKnown or not nativeKnown or Secret(onQuest) or Secret(completed)
        or Secret(nativeCompleted) or type(onQuest) ~= "boolean" or type(completed) ~= "boolean"
        or (nativeCompleted ~= nil and type(nativeCompleted) ~= "boolean") then
        return nil
    end
    return not onQuest and not completed and not nativeCompleted
end

local function AcceptsQuest(element, questID)
    if element.tag == "accept" then return element.questId == questID end
    if element.tag == "daily" or element.tag == "acceptmultiple" then
        for _, id in ipairs(element.ids or {}) do if id == questID then return true end end
    end
    return false
end

local function FindQuestRecovery(rxp, guide, current)
    local questID, destination
    local resolved = P.ResolveStep(rxp, guide.steps[current])
    for index, objective in ipairs(guide.steps[current].elements or {}) do
        local fact = resolved.elements[index]
        -- Association alone is insufficient: these actions actually require
        -- the quest. Accept steps and incidental quest-labelled notes do not.
        if fact and (fact.action == "complete" or fact.action == "turnin") and not objective.hidden and not objective.optional then
            -- Use the same candidate resolution as presentation, a native
            -- daily loop's last questId cannot identify a missing quest.
            if fact.questCandidates and not fact.questID then return nil, "ambiguous_missing_quests" end
            if MissingQuest(rxp, fact.questID) == true then
                if questID and questID ~= fact.questID then return nil, "ambiguous_missing_quests" end
                questID = fact.questID
            end
        end
    end
    if not questID then return nil, "no_missing_quest" end
    for index = current - 1, 1, -1 do
        local step = guide.steps[index]
        if not step.sticky and not step.hidewindow and not step.hidden and not step.disabled then
            for _, element in ipairs(step.elements or {}) do
                if not element.hidden and AcceptsQuest(element, questID)
                    and IsSelectableStep(rxp, guide, step)
                    and (not element.requiredTurnIn or P.Call(rxp, "IsQuestTurnedIn", element.requiredTurnIn)) then
                    destination = index
                    break
                end
            end
        end
        if destination then break end
    end
    return destination, destination and "missing_quest" or "no_accept_step", questID
end

local function SelectNativeStep(rxp, guide, current, index, reason, questID)
    local limit = #guide.steps + (reason == "next" and 1 or 0)
    if not Numeric(index) or index ~= math.floor(index) or index < 1 or index > limit then
        return false, "invalid_step"
    end
    local destination = guide.steps[index]
    local id = GuideID(rxp)
    if rxp.currentGuide ~= guide or P.Call(rxp, "GetGuideProgress") ~= current then return false, "stale" end
    -- Same operation as RXP's own Go to step menu. No completion, queued-step,
    -- waypoint or SavedVariables fields are reset by AWP.
    loopCursor = nil
    local ok = pcall(rxp.SetStep, index)
    if not ok then return false, "selection_failed" end
    if reason == "next" and rxp.currentGuide ~= guide then
        API.Schedule("RXPNextGuide"); return true
    end
    if rxp.currentGuide ~= guide or GuideID(rxp) ~= id or guide.steps[index] ~= destination then
        API.Schedule("RXPStepSelectionChangedGuide")
        return false, "stale"
    end
    lastStepSelection = {
        guide = id,
        origin = current,
        requested = index,
        stepID = destination and destination.stepId,
        reason = reason,
        questID = questID,
        immediate = P.Call(rxp, "GetGuideProgress")
    }
    API.Schedule("RXPStepSelected")
    if reason == "missing_quest" and lastStepSelection.immediate == current then return false, "choose_step", index end
    return true
end

function API.RunAction(action, expectedGuide, expectedStep, requestedStep, expectedEpoch)
    local rxp = API.GetRuntime()
    if not rxp then return false end
    if action == "settings" then
        if not rxp.settings or type(rxp.settings.OpenSettings) ~= "function" then return false, "settings_unavailable" end
        local ok, result = pcall(rxp.settings.OpenSettings); return ok and result ~= false
    end
    if action == "chooser" then
        if rxp.v2 and rxp.v2.IsGuideWindowEnabled and rxp.v2:IsGuideWindowEnabled() then
            if type(rxp.v2.ShowGuideSelectionMenu) ~= "function" then return false, "chooser_unavailable" end
            local ok, result = pcall(rxp.v2.ShowGuideSelectionMenu, rxp.v2); return ok and result ~= false
        end
        if not rxp.RXPFrame or type(rxp.RXPFrame.DropDownMenu) ~= "function" then return false, "chooser_unavailable" end
        local ok, result = pcall(rxp.RXPFrame.DropDownMenu); return ok and result ~= false
    end
    if action == "active" then
        API.Activate("RXPViewerAction"); return true
    end
    if API.IsPaused(rxp) or action ~= "route" and InCombatLockdown and InCombatLockdown() then
        return false,
            "unavailable"
    end
    local id, current = GuideID(rxp), P.Call(rxp, "GetGuideProgress")
    if expectedGuide and expectedGuide ~= id or expectedStep and expectedStep ~= current
        or expectedEpoch and expectedEpoch ~= guideEpoch then
        return false, "stale"
    end
    if action == "route" then
        API.Activate("RXPViewerRoute"); return true
    end
    if action == "reload" then
        local ok, result = pcall(rxp.ReloadGuide, rxp, true); return ok and result ~= false
    end
    if action == "close" then
        local ok, result = pcall(rxp.LoadGuide, rxp, rxp.emptyGuide); return ok and result ~= false
    end
    local guide = rxp.currentGuide
    local steps = guide and guide.steps
    local step = steps and current and steps[current]
    if not Numeric(current) or not guide or not steps or not step then return false, "unavailable" end
    if action == "goto" then return SelectNativeStep(rxp, guide, current, requestedStep, "explicit") end
    if action == "previous" then
        local recovery, reason, questID = FindQuestRecovery(rxp, guide, current)
        if rxp.currentGuide ~= guide or P.Call(rxp, "GetGuideProgress") ~= current then return false, "stale" end
        if recovery then
            -- If native conditions have already returned this recovery to its
            -- starting point, repeated Back must not retry the same barrier.
            -- Explicit selection or a quest/guide change permits a fresh try.
            if lastStepSelection and lastStepSelection.reason == "missing_quest" and lastStepSelection.guide == id
                and lastStepSelection.requested == recovery and lastStepSelection.questID == questID
                and current >= lastStepSelection.origin then
                return false, "choose_step", recovery
            end
            return SelectNativeStep(rxp, guide, current, recovery, reason, questID)
        end
        for index = current - 1, 1, -1 do
            if IsSelectableStep(rxp, guide, steps[index]) then return false, "choose_step", index end
        end
        return false, "no_previous_step"
    end
    if action == "next" or action == "complete" or action == "skip" then
        for _, element in ipairs(step.elements or {}) do
            if rxp.currentGuide ~= guide or guide.steps[current] ~= step or GuideID(rxp) ~= id
                or P.Call(rxp, "GetGuideProgress") ~= current then
                return true
            end
            if not element.textOnly and not element.optional and not element.completed and not element.skip and not element.hidden then
                local parent = { element = element }
                local ok = pcall(rxp.ActiveStepElementPostClick, {
                    GetParent = function() return parent end, GetChecked = function() return true end,
                })
                if not ok then return false end
            end
        end
        if rxp.currentGuide == guide and guide.steps[current] == step and GuideID(rxp) == id
            and P.Call(rxp, "GetGuideProgress") == current then
            return SelectNativeStep(rxp, guide, current, current + 1, "next")
        end
        API.Schedule("RXPNext"); return true
    end
    return false
end

-- ============================================================
-- Switching guides
-- ============================================================

function API.SwitchGuide(id)
    local rxp = API.GetRuntime()
    if not rxp or InCombatLockdown and InCombatLockdown() then return false end
    local guide = P.Call(rxp, "GetGuideTable", id)
    if not guide then return false end
    local ok = pcall(rxp.LoadGuide, rxp, guide)
    if ok then API.Activate("RXPGuideSelected") end
    return ok
end

NS.RegisterExternalWaypointSource("rxp", {
    displayName = "RestedXP",
    aliases = { "RXPGuides", "RestedXP", "RXP" },
    stackMatches = { "interface\\addons\\rxpguides", "rxpguides\\" },
    guideProvider = "rxp",
    transient = true,
    iconKey = "rxp"
})
NS.RegisterGuideTargetProvider("rxp", {
    label = "RestedXP",
    displayName = "RestedXP",
    icon = "Interface\\AddOns\\RXPGuides\\Textures\\rxp_logo-64.blp",
    isLoaded = NS.IsRXPLoaded,
    structuredPresentation = true,
    hasGuide = function()
        local s = API.GetSnapshot()
        return s.id ~= nil and (s.state == "ready" or s.state == "paused")
    end,
    getVisibilityState = function()
        local rxp = API.GetRuntime()
        return rxp and "visible" or "absent"
    end,
    getActivationToken = function()
        local r = API.GetRuntime(); return r and (GuideID(r) or "") .. "\031" .. tostring(P.Call(r, "GetGuideProgress"))
    end,
    extractTarget = function()
        API.GetSnapshot(); return target, target == nil
    end,
    getTravelIntent = function()
        return not worldLoading and snapshot and snapshot.state == "ready" and travelIntent or
            nil
    end,
    onDestinationReached = API.OnDestinationReached,
    installHooks = InstallHooks,
    getDebugLines = function()
        local s = API.GetSnapshot()
        return { "rxp state=" .. s.state .. " guide=" .. tostring(s.id) .. " step=" .. s.current
        .. " navigation=" .. tostring(s.navigationReason),
            "owner=" .. tostring(target and target.rxpOwner) .. " element=" .. tostring(target and target.rxpElement)
            .. " waypoint=" .. tostring(target and target.rxpWaypoint)
            .. " travelSource=" .. tostring(target and target.rxpTravelSource)
            .. " tag=" ..
            tostring(target and target.rxpElementTag) .. " role=" .. tostring(target and target.rxpElementRole)
            .. " action=" ..
            tostring(target and target.rxpAction) .. " source=" .. tostring(target and target.rxpOwnerReason)
            .. " titleSource=" .. tostring(target and target.rxpTitleSource)
            .. " contextSource=" .. tostring(target and target.rxpContextSource)
            .. " suppression=" .. tostring(target and target.rxpSuppression)
            .. " destination=" .. (target and string.format("%d@%.4f,%.4f", target.mapID, target.x, target.y) or "none"),
            "title=" .. tostring(target and target.title) .. " context=" .. tostring(target and target.subtext),
            "loopPoint=" .. (loopCursor and (loopCursor.index .. "/" .. #loopCursor.points) or "native"),
            "flight=" .. tostring(travelIntent and travelIntent.destinationName)
            .. " flightOwner=" .. tostring(travelIntent and travelIntent.stepIndex)
            .. " node=" .. tostring(travelIntent and travelIntent.nodeID)
            .. " flightReason=" .. tostring(travelIntent and travelIntent.reason)
            .. " lastFlightCompletion=" .. tostring(flightCompletion),
            "selection=" .. tostring(lastStepSelection and lastStepSelection.reason)
            .. " requested=" .. tostring(lastStepSelection and lastStepSelection.requested)
            .. " immediate=" .. tostring(lastStepSelection and lastStepSelection.immediate)
            .. " quest=" .. tostring(lastStepSelection and lastStepSelection.questID) }
    end,
})

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "ADDON_LOADED", "TAXIMAP_OPENED",
    "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED", "QUEST_DATA_LOAD_RESULT", "SPELL_DATA_LOAD_RESULT", "UNIT_NAME_UPDATE",
    "QUEST_REMOVED", "QUEST_ACCEPTED", "QUEST_TURNED_IN" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function(_, event, id, questID)
    if event == "PLAYER_LEAVING_WORLD" then
        worldLoading = true
    elseif event == "PLAYER_ENTERING_WORLD" then
        worldLoading = false
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "TAXIMAP_OPENED" then flightLookup = nil end
    if event == "ADDON_LOADED" and id ~= "RXPGuides" then return end
    if event == "QUEST_REMOVED" or event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" then
        if event == "QUEST_ACCEPTED" and Numeric(questID) then id = questID end
        if lastStepSelection and lastStepSelection.questID == id then lastStepSelection = nil end
        if not Numeric(id) or not P.Invalidate(event, id) then return end
    elseif event:find("DATA") or event == "GET_ITEM_INFO_RECEIVED" or event == "UNIT_NAME_UPDATE" then
        if event == "UNIT_NAME_UPDATE" and id ~= "target" and id ~= "npc" then return end
        if not P.Invalidate(event, id) then return end
    elseif NS.StartGuideRoutingEvaluation then
        NS.StartGuideRoutingEvaluation()
    end
    API.Schedule(event)
end)
