-- ============================================================
-- Polestar guide provider
-- ============================================================
--
-- Publishes Polestar's active guide destination and forwards guide choices and
-- service searches to its native APIs.

local NS = _G.AzerothWaypointNS
local P = NS.Internal.PolestarPresentation
local Source = NS.Internal.GuideSourceRuntime
local QuestSelection = NS.Internal.GuideQuestSelection
local EMPTY = {}
local API = { counters = { received = 0, coalesced = 0, built = 0, reused = 0, waypoint = 0 } }
NS.Internal.PolestarProvider = API
local snapshot = { state = "loading", current = 0, total = 0, steps = {}, tabs = {} }
local target, explicit, routeSchedule, subscribed
local epoch, presentationRevision = 0, 0
local observation = Source.CreateObservation()
local listeners, hooked = {}, setmetatable({}, { __mode = "k" })
local required = { "GetGuide", "GetStepIndex", "GetStepView", "GetWaypoint", "GetTabs", "Prev", "Next", "Skip", "AimGoal" }
local waypointFields = { "stepIndex", "goalIndex", "map", "x", "y", "f", "z", "r", "spot", "area", "search" }
local readingHelpers = { "ReadingGoal", "GoalLine", "GoalSubline", "GoalDetail", "GroupName" }

function API.GetRuntime()
    if not NS.IsWoWForever() then return nil end
    local r = rawget(_G, "Polestar")
    if type(r) ~= "table" or type(r.On) ~= "function" or type(r.Off) ~= "function" then return nil end
    for _, key in ipairs(required) do if type(r.Engine) ~= "table" or type(r.Engine[key]) ~= "function" then return nil end end
    return r
end

NS.IsPolestarLoaded = function() return API.GetRuntime() ~= nil end
function API.GetSnapshot() return snapshot end

function API.Subscribe(fn) listeners[#listeners + 1] = fn end

if not NS.IsWoWForever() then return end
local Native = NS.Internal.NativeMapWaypoints

local function ContentSignature(s, t)
    s.target = t
    local parts = { Source.Signature(s), s.rawCurrent, s.done or 0, s.count or 0, epoch, s.destinationReason or "" }
    for _, step in ipairs(s.steps) do
        parts[#parts + 1] = tostring(step.index) .. (step.sticky and "s" or "")
        for _, row in ipairs(step.rows) do
            parts[#parts + 1] = table.concat({ row.goalIndex or "", row.stepIndex or "",
                row.hereSerial or "", tostring(row.tickable), tostring(row.ticked) }, ":")
            local d = row.interaction
            if d then
                parts[#parts + 1] = table.concat({ d.action, d.step, d.epoch, d.target or "", d.goal or "",
                    d.tab or "", d.quest or "", d.answer or "" }, ":")
            end
        end
    end
    for _, tab in ipairs(s.tabs) do
        parts[#parts + 1] = tab.id; parts[#parts + 1] = tab.title
    end
    if t then
        parts[#parts + 1] = tostring(t.navigationHeight) .. ":" .. tostring(t.navigationContinent)
        local area = t.navigationArea
        if area then
            parts[#parts + 1] = table.concat({ area.id, area.radius, area.arrivalRadius,
                tostring(area.search), tostring(area.height), tostring(area.continent), area.spotCount or 0 }, ":")
        end
    end
    return table.concat(parts, "\031")
end

local function PublicNumber(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return end
    if type(value) == "number" and value == value and math.abs(value) < math.huge then return value end
end

local function NavigationArea(r, wp, map, x, y, guideID)
    local radius = PublicNumber(wp.area)
    local arrival = PublicNumber(wp.r) or PublicNumber(r.Nav and r.Nav.DEFAULT_RADIUS)
    if not radius or radius <= 0 or not arrival or arrival < 0 then return end
    local spot = PublicNumber(wp.spot)
    local c = P.Call(r.Compat, "MapToWorld", map, x * 100, y * 100)
    return {
        id = table.concat({ guideID, wp.stepIndex, wp.goalIndex, spot or "single" }, ":"),
        radius = radius,
        arrivalRadius = arrival,
        search = wp.search == true,
        spot = spot,
        spotCount = type(wp.spots) == "table" and #wp.spots or nil,
        height = PublicNumber(wp.z),
        continent = PublicNumber(c)
    }
end

local function NativeQuestState(runtime, id)
    return P.Call(runtime.Compat, "IsOnQuest", id), P.Call(runtime.Compat, "IsQuestReadyForTurnIn", id)
end

local function LevelReturn(d)
    local r = API.GetRuntime()
    local e, frame = r and r.Engine, r and r.UI and r.UI.GuideFrame
    local g = P.Call(e, "GetGuide")
    if not g or g.id ~= d.guide or epoch ~= d.epoch or P.Call(e, "GetStepIndex") ~= d.step then return end
    local view = P.Call(e, "GetStepView", d.step, true)
    local goal = view and view.goals and view.goals[d.goal]
    local step = g.steps and g.steps[d.step]
    local raw = step and step.goals and step.goals[d.goal]
    if not goal or goal.status == "done" or goal.status == "na" or goal.status == "skipped" or not raw then return end
    local back = P.Call(frame, "LevelBack", g, raw)
    if type(back) == "table" and type(back.id) == "string" and tonumber(raw.level) then return back, tonumber(raw.level),
            frame end
end

-- ============================================================
-- Guide questions and row actions
-- ============================================================

local function LiveQuestion(engine, step)
    if not step or P.Call(engine, "GetLiveStep") ~= step then return end
    local quest, title, info = P.Call(engine, "GroupQuestion")
    if type(quest) == "number" then
        if type(info) ~= "table" then info = nil end
        return quest, P.Text(title), info and info.escort == true, info and P.Text(info.text)
    end
end

local function ResolveGroupAnswer(d)
    local r = API.GetRuntime()
    local e = r and r.Engine
    local answer = e and rawget(e, "AnswerGroup")
    if type(answer) ~= "function" or (d.answer ~= "do" and d.answer ~= "skip") then return end
    local g = P.Call(e, "GetGuide")
    local _, tab = P.Call(e, "GetTabs")
    if g and g.id == d.guide and epoch == d.epoch and tab == d.tab
        and P.Call(e, "GetStepIndex") == d.step and LiveQuestion(e, d.step) == d.quest then
        return answer
    end
end

function API.GetRowActionState(d)
    if InCombatLockdown() then return false, "This guide control is unavailable during combat." end
    if d.action == "group_choice" then
        return ResolveGroupAnswer(d) ~= nil, "The quest choice changed."
    end
    local back = LevelReturn(d)
    return back ~= nil and back.id == d.target, "The guide suggestion changed."
end

function API.RunRowAction(d)
    if d.action == "group_choice" then
        if InCombatLockdown() then return false, "This guide control is unavailable during combat." end
        local answer = ResolveGroupAnswer(d)
        if not answer then return false, "The quest choice changed." end
        answer(d.quest, d.answer)
        API.Schedule("quest_choice")
        return true
    end
    local enabled, reason = API.GetRowActionState(d)
    if not enabled then return false, reason end
    local back, _, frame = LevelReturn(d)
    if not frame or type(frame.GoLevel) ~= "function" then return false, "Native guide switching is unavailable." end
    local ok = pcall(frame.GoLevel, back)
    if ok then API.Activate() end
    return ok
end

local function AddGroupChoice(step, runtime, guideID, tab, quest, title, escort, note)
    local L = runtime.L or EMPTY
    local caption = escort and "Escort quest: %s" or "Group quest: %s"
    local heading = string.format(L[caption] or caption, title or tostring(quest))
    table.insert(step.rows, 1, { text = heading, kind = "info", role = "support", status = "warning", fullHeight = true })
    if note then
        table.insert(step.rows, 2,
            { text = note, kind = "info", role = "support", status = "passive", fullHeight = true })
    end
    local accept = escort and "Do it" or "Do it with a group"
    local index = note and 3 or 2
    for offset, answer in ipairs({ "do", "skip" }) do
        local key = answer == "do" and accept or "Skip it"
        local label = L[key] or key
        table.insert(step.rows, index + offset - 1, {
            text = label,
            kind = "info",
            fullHeight = true,
            hideActions = true,
            objectiveKey = "group_choice:" .. quest .. ":" .. answer,
            interaction = {
                provider = "polestar",
                action = "group_choice",
                guide = guideID,
                tab = tab,
                step = step.index,
                epoch = epoch,
                quest = quest,
                answer = answer,
                label = label
            }
        })
    end
end

local function AddLevelReturn(step, view, guideID)
    for _, goal in ipairs(view.goals or EMPTY) do
        if goal.t == "level" then
            local d = {
                provider = "polestar",
                action = "level_return",
                guide = guideID,
                step = view.index,
                goal = goal.index,
                epoch = epoch
            }
            local back, level = LevelReturn(d)
            if back then
                d.target = back.id
                local r = API.GetRuntime()
                local locales = r and rawget(r, "L")
                local format = locales and locales["Level with %s meanwhile: this guide picks up at level %d"]
                    or "Level with %s meanwhile: this guide picks up at level %d"
                local text = string.format(format, back.title or back.id, level)
                d.label = text
                local at = #step.rows + 1
                for i, row in ipairs(step.rows) do if row.goalIndex == goal.index then
                        at = i + 1; break
                    end end
                table.insert(step.rows, at, {
                    text = text,
                    kind = "info",
                    status = "passive",
                    fullHeight = true,
                    interaction = d,
                    hideActions = true
                })
            end
        end
    end
end

local function ResolveAlternative(r, guide, waypoint, view, goal, fact)
    local steps = guide.steps
    local step = steps and steps[waypoint.stepIndex]
    local authored = step and step.goals
    local raw = authored and authored[waypoint.goalIndex]
    if not (QuestSelection and raw and raw.either) or (fact.action ~= "accept" and fact.action ~= "turnin") then return end
    local ids, candidates = {}, {}
    for index, candidate in ipairs(view.goals) do
        local definition = authored[index]
        if definition and definition.either and candidate.t == goal.t and type(candidate.quest) == "number"
            and candidate.map == goal.map and candidate.x == goal.x and candidate.y == goal.y and candidate.f == goal.f
            and candidate.npc == goal.npc and candidate.npcName == goal.npcName
            and candidate.status ~= "na" and candidate.status ~= "skipped" and not candidate.unavailable
        then
            ids[#ids + 1], candidates[candidate.quest] = candidate.quest, candidate
        end
    end
    if #ids < 2 then return end
    local id = QuestSelection.Select(fact.action, ids, true, NativeQuestState, r, true)
    local _, choice
    if id then _, choice = P.GoalFacts(r, view, candidates[id]) end
    local title, context = NS.Internal.GuidePresentation.DescribeQuestAlternative(fact.action,
        choice and choice.title, fact.context)
    if title then return { ids = ids, questID = id, title = title, context = context } end
end

local function Refresh()
    local r = API.GetRuntime()
    local e = r and r.Engine
    local g = P.Call(e, "GetGuide")
    local at = P.Call(e, "GetStepIndex") or 0
    local current = P.Call(e, "StepNumber", at) or at
    local total = P.Call(e, "StepTotal") or 0
    local done, count = P.Call(e, "GetProgress")
    local tabs, activeTab = P.Call(e, "GetTabs")
    local view = g and P.Call(e, "GetStepView", at, true)
    local along, nearby = P.Call(e, "GetAlong"), P.Call(e, "GetWhileHereList")
    local wp = P.Call(e, "GetWaypoint")
    local owner = g and type(wp) == "table" and wp.stepIndex and
        (wp.stepIndex == at and view or P.Call(e, "GetStepView", wp.stepIndex, true))
    local leftOut = g and P.Call(r, "Get", "guideWindow.leftOut") and P.Call(e, "LeftOutHere", at)
    local quest, questionTitle, escort, escortNote = LiveQuestion(e, view and view.index)
    local ui = r and r.UI
    local _, caution = P.Call(ui, "StepMark", view, g and g.steps and g.steps[at])
    observation:Begin()
    observation:Push(r ~= nil); observation:Push(g and g.id); observation:Push(g and g.title)
    observation:Push(at); observation:Push(current); observation:Push(total)
    observation:Push(type(UnitLevel) == "function" and UnitLevel("player"))
    observation:Push(done); observation:Push(count); observation:Push(epoch); observation:Push(presentationRevision)
    observation:Push(quest); observation:Push(questionTitle); observation:Push(escort); observation:Push(escortNote)
    observation:Push(caution)
    for _, method in ipairs(readingHelpers) do
        observation:Push(ui and type(ui[method]) == "function")
    end
    observation:Push(activeTab)
    for _, tab in ipairs(tabs or EMPTY) do
        observation:Push(tab.guideId); observation:Push(tab.title)
    end
    P.ObserveStep(observation, view)
    for _, step in ipairs(along or EMPTY) do P.ObserveStep(observation, step) end
    for _, goal in ipairs(nearby or EMPTY) do
        -- A nearby entry has the same copied goal fields as a normal goal.
        P.ObserveGoal(observation, goal)
        observation:Push(goal.appeared)
    end
    if owner ~= view then P.ObserveStep(observation, owner) else observation:Push("current_owner") end
    for _, key in ipairs(waypointFields) do
        observation:Push(wp and wp[key])
    end
    observation:Push(wp and type(wp.spots) == "table" and #wp.spots)
    for _, entry in ipairs(leftOut or EMPTY) do
        observation:Push(entry.quest); observation:Push(entry.title); observation:Push(entry.kind); observation:Push(
        entry.text)
    end
    if not observation:Finish() then
        API.counters.reused = API.counters.reused + 1; return false
    end
    local nextSnapshot = {
        id = g and g.id,
        title = P.Text(g and g.title),
        current = current,
        rawCurrent = at,
        epoch = epoch,
        total = total,
        state = not r and "absent" or not g and "empty" or at == 0 and "complete" or "ready",
        steps = {},
        tabs = {},
        destinationReason = "no_native_waypoint",
        done = done,
        count = count
    }
    for i, tab in ipairs(tabs or EMPTY) do
        nextSnapshot.tabs[#nextSnapshot.tabs + 1] = {
            id = tab.guideId,
            title = P.Text(tab.title) or tab.guideId,
            index = i,
            active = i == activeTab
        }
    end
    if view then
        nextSnapshot.steps[1] = P.BuildStep(r, view, false)
        AddLevelReturn(nextSnapshot.steps[1], view, g.id)
        P.AddLeftOut(nextSnapshot.steps[1], leftOut)
        if quest then
            AddGroupChoice(nextSnapshot.steps[1], r, g.id, activeTab, quest, questionTitle, escort, escortNote)
        elseif type(caution) == "string" and caution ~= "" then
            table.insert(nextSnapshot.steps[1].rows, 1, {
                text = caution,
                kind = "info",
                role = "support",
                status = "warning",
                fullHeight = true
            })
        end
    end
    for _, step in ipairs(along or EMPTY) do nextSnapshot.steps[#nextSnapshot.steps + 1] = P.BuildStep(r, step, true) end
    for _, goal in ipairs(nearby or EMPTY) do
        local here = P.BuildStep(r, { index = goal.step, title = "While you're here", goals = { goal } }, true)
        here.section = "nearby"
        for _, row in ipairs(here.rows) do if row.goalIndex == goal.index then row.hereSerial = goal.appeared end end
        if #here.rows > 0 then nextSnapshot.steps[#nextSnapshot.steps + 1] = here end
    end
    local nextTarget
    if r and g and type(wp) == "table" and wp.stepIndex and wp.goalIndex then
        nextSnapshot.destinationReason = "unavailable_native_owner"
        local goal = owner and owner.goals and owner.goals[wp.goalIndex]
        local map, x, y = P.Coordinates(r, wp)
        if map and goal and goal.status ~= "na" and goal.status ~= "skipped" and goal.status ~= "done" and not goal.unavailable then
            local _, fact = P.GoalFacts(r, owner, goal)
            if fact then
                local alternative = ResolveAlternative(r, g, wp, owner, goal, fact)
                if alternative then
                    nextSnapshot.handoffQuestIDs, nextSnapshot.handoffAction = alternative.ids, fact.action
                end
                local questID = fact.questID
                if alternative then questID = alternative.questID end
                nextTarget = {
                    mapID = map,
                    x = x,
                    y = y,
                    title = alternative and alternative.title or fact.title,
                    subtext = alternative and alternative.context or fact.context,
                    guideProvider = "polestar",
                    kind = "guide_goal",
                    source = "polestar.step#" .. wp.stepIndex,
                    guideStepIdentity = g.id .. "\031" .. wp.stepIndex .. ":" .. wp.goalIndex,
                    semanticKind = fact.travelType and "travel" or fact.questID and "quest" or "guide",
                    semanticTravelType = fact.travelType,
                    semanticQuestID = questID,
                    iconHintQuestID = questID,
                    iconHintKind = fact.travelType or (fact.questID and "quest" or "guide"),
                    polestarOwner = wp.stepIndex,
                    polestarGoal = wp.goalIndex,
                    polestarAction = fact.action,
                    polestarTitleSource = fact.titleSource,
                    polestarContextSource = fact.contextSource,
                    polestarSuppression = fact.suppression
                }
                NS.Internal.GuidePresentation.SetDestinationContext(nextTarget, fact.destinationName,
                    fact.destinationKind,
                    fact.action, questID, nextTarget.title)
                nextTarget.navigationArea = NavigationArea(r, wp, map, x, y, g.id)
                local height = PublicNumber(wp.z)
                local continent = PublicNumber(P.Call(r.Compat, "MapToWorld", map, x * 100, y * 100))
                if height and continent then nextTarget.navigationHeight, nextTarget.navigationContinent = height,
                        continent end
                nextSnapshot.destinationReason = "native_goal"
            end
        end
    end
    local sig = ContentSignature(nextSnapshot, nextTarget)
    if sig == snapshot.signature then
        API.counters.reused = API.counters.reused + 1; return false
    end
    API.counters.built = API.counters.built + 1
    nextSnapshot.signature = sig
    snapshot, target = nextSnapshot, nextTarget
    return true
end

-- ============================================================
-- Evaluating the guide target
-- ============================================================

local function Evaluate()
    local intent = explicit
    explicit = false
    local changed = Refresh()
    if routeSchedule and (changed or intent) then
        routeSchedule("PolestarUpdated",
            intent and { explicit = true, allowProviderSwitch = true } or { presentationRefresh = true })
    end
    for _, fn in ipairs(listeners) do fn(snapshot, changed) end
end
local refreshQueue = NS.Internal.Scheduling.CreateCoalescer(Evaluate)
function API.Schedule(reason, intent)
    API.counters.received = API.counters.received + 1
    if reason == "WAYPOINT_CHANGED" then API.counters.waypoint = API.counters.waypoint + 1 end
    if reason == "guide_quest_dialog" then presentationRevision = presentationRevision + 1 end
    explicit = explicit or intent
    if not refreshQueue:Request() then API.counters.coalesced = API.counters.coalesced + 1 end
end

if QuestSelection then QuestSelection.Watch(API) end
function API.Activate()
    if NS.SelectGuideProvider then NS.SelectGuideProvider("polestar", "PolestarSelected") end
    API.Schedule("explicit", true)
end

local function WireNativeTabs()
    local r = API.GetRuntime()
    local frame = r and r.UI and r.UI.GuideFrame
    for _, tab in ipairs(frame and frame.tabs or EMPTY) do
        if not tab._awpPolestarTab then
            tab._awpPolestarTab = true
            tab:HookScript("OnClick", function(_, button) if button == "LeftButton" then API.Activate() end end)
        end
    end
end

local serviceKinds = {
    trainer = "gossip_poi",
    class = "gossip_poi",
    weapon = "gossip_poi",
    repair = "npc_repair",
    reagents = "npc_vendor",
    vendor = "npc_vendor",
    food = "npc_vendor",
    general = "npc_vendor",
    arrows = "npc_vendor",
    bullets = "npc_vendor",
    ranged = "npc_vendor",
    innkeeper = "npc_innkeeper",
    bank = "npc_banker",
    mailbox = "npc_mailbox",
    auction = "npc_auctioneer",
    flight = "npc_flightmaster",
    flightmaster = "npc_flightmaster",
    stable = "npc_stable_master"
}

local function SearchPoint(point, label, searchKind)
    local r = API.GetRuntime()
    if not r or InCombatLockdown() then return false end
    local map, x, y = P.Coordinates(r, point)
    if not map then return false end
    local service = searchKind or point.stop
    local metadata = { sourceAddon = "polestar", searchKind = serviceKinds[service] or service, queueSourceType =
    "transient_source" }
    local height = PublicNumber(point.z)
    local continent = PublicNumber(P.Call(r.Compat, "MapToWorld", map, x * 100, y * 100))
    if height and continent then metadata.navigationHeight, metadata.navigationContinent = height, continent end
    return { mapID = map, x = x, y = y, title = P.Text(label) or "Polestar waypoint", meta = metadata }
end

function API.RoutePoint(point, label, searchKind)
    local result = SearchPoint(point, label, searchKind)
    return result and NS.Internal.ServiceSearch.Publish(result) or false
end

local nearbyKinds = {
    auctioneer = "auction",
    banker = "bank",
    flightmaster = "flight",
    innkeeper = "innkeeper",
    mailbox = "mailbox",
    repair = "repair",
    vendor = "vendor",
    stable = "stable",
    transmogrifier = "transmogrifier",
    trainer = "trainer",
    food = "food",
    reagents = "reagents",
    class = "class",
    weapon = "weapon",
    general = "general",
    arrows = "arrows",
    bullets = "bullets",
    ranged = "ranged"
}
local Search = NS.Internal.ServiceSearch
local capabilityCache = {}
local function CodexAvailable(r)
    if r.Codex and type(r.Codex.IsLoaded) == "function" and r.Codex.IsLoaded() then return true end
    return C_AddOns and type(C_AddOns.DoesAddOnExist) == "function" and C_AddOns.DoesAddOnExist("Polestar_Codex")
        and NS.IsAddonEnabledForCurrentCharacter and NS.IsAddonEnabledForCurrentCharacter("Polestar_Codex") == true or
        false
end
local function GetCapabilities()
    local r = API.GetRuntime()
    local nearby = r and r.Nav and r.Nav.nearby
    local skills = r and r.Compat and r.Compat.SKILL_LINES
    local info = r and r.Compat and type(r.Compat.GetPlayerInfo) == "function" and r.Compat.GetPlayerInfo() or EMPTY
    local available = r and nearby and type(nearby.Find) == "function" and CodexAvailable(r) or false
    local cache = capabilityCache
    if cache.runtime == r and cache.nearby == nearby and cache.skills == skills and cache.available == available
        and cache.class == info.class and cache.level == info.level and cache.faction == info.faction
        and cache.generation == Search.Generation() then
        return cache.capabilities
    end
    cache.runtime, cache.nearby, cache.skills, cache.available = r, nearby, skills, available
    cache.class, cache.level, cache.faction, cache.generation = info.class, info.level, info.faction, Search.Generation()
    local capabilities = {}
    cache.capabilities = capabilities
    if not r or not nearby or type(nearby.Find) ~= "function" then return capabilities end
    local kinds = {}
    for _, kind in ipairs(nearby.KINDS or EMPTY) do
        if not nearby.Fits or nearby.Fits(kind) then kinds[kind.key] = true end
    end
    if kinds.class and (available or r.Engine and type(r.Engine.NearestClassTrainer) == "function") then
        local query = Search.Query("class", info.class)
        if query then capabilities[#capabilities + 1] = query end
    end
    if not available then return capabilities end
    for service, key in pairs(nearbyKinds) do
        if kinds[key] and service ~= "class" and service ~= "weapon" then
            if service == "trainer" then
                capabilities[#capabilities + 1] = Search.Query("trainer")
                for profession in pairs(Search.Professions) do
                    if skills and skills[profession] then capabilities[#capabilities + 1] = Search.Query("trainer",
                            profession) end
                end
            else
                capabilities[#capabilities + 1] = Search.Query(service)
            end
        end
    end
    local weapons = kinds.weapon and nearby.Weapons and nearby.Weapons() or EMPTY
    if #weapons > 0 then
        capabilities[#capabilities + 1] = Search.Query("weapon")
        for _, weapon in ipairs(weapons) do
            local query = Search.Query("weapon", weapon.line, weapon.label .. " Trainer")
            if query then capabilities[#capabilities + 1] = query end
        end
    end
    return capabilities
end

-- ============================================================
-- Nearby service search
-- ============================================================

local function FindNearby(query)
    local r = API.GetRuntime()
    local nearby = r and r.Nav and r.Nav.nearby
    if not r or not nearby or InCombatLockdown() then return nil end
    local key = nearbyKinds[query.service]
    if not key then return nil end
    local supported = false
    for _, kind in ipairs(nearby.KINDS or {}) do
        if kind.key == key and (not nearby.Fits or nearby.Fits(kind)) then
            supported = true; break
        end
    end
    if not supported then return nil end
    if query.service == "class" then
        local info = r.Compat and r.Compat.GetPlayerInfo and r.Compat.GetPlayerInfo()
        if not info or query.classToken ~= info.class then return nil end
    end
    local line = query.weaponLine
    if query.service == "weapon" and line and nearby.Weapons then
        local eligible = false
        for _, weapon in ipairs(nearby.Weapons()) do if weapon.line == line then
                eligible = true; break
            end end
        if not eligible then return nil end
    end
    if query.profession then
        local skills = r.Compat and r.Compat.SKILL_LINES
        line = skills and skills[query.profession]
        if not line then return nil end
    end
    local point, reason = nearby.Find(key, line)
    if not point then
        if reason == "missing" or reason == "disabled" or reason == "empty" then
            return nil, "Nearby services need Polestar_Codex installed, enabled and ready."
        end
        return nil, "No matching nearby service is available."
    end
    return SearchPoint(point, point.name or query.label, key)
end

Search.Register("polestar", { label = "Polestar", Find = FindNearby, GetCapabilities = GetCapabilities })

function API.FindNearest(key, line, label)
    for service, native in pairs(nearbyKinds) do
        if native == key then
            local subject = service == "weapon" and line or nil
            if service == "trainer" and line then
                local r = API.GetRuntime()
                for profession, id in pairs(r and r.Compat and r.Compat.SKILL_LINES or EMPTY) do
                    if id == line then
                        subject = profession; break
                    end
                end
                if not subject then return false end
            end
            local query = Search.Query(service, subject, label)
            return query and Search.Request(query, "polestar") or false
        end
    end
    return false
end

local function Hook(object, key, callback)
    if type(object) ~= "table" or type(object[key]) ~= "function" then return end
    hooked[object] = hooked[object] or {}
    if hooked[object][key] then return end
    hooked[object][key] = true
    hooksecurefunc(object, key, callback)
end

local suppressed = {
    ["nav.tomtom"] = true,
    ["nav.followTomTom"] = true,
    ["nav.spfHandoff"] = true
}
local suppressionRuntime
local followerRuntime
local followerOwned = false
local FOLLOWER_OWNER = "AzerothWaypoint"
local observed = {}
local observedFields = { "stepIndex", "goalIndex", "map", "x", "y", "f", "z", "spot", "area", "search" }
local function ObserveFollower()
    local r = API.GetRuntime()
    if not r or not followerOwned or r ~= followerRuntime then return end
    local waypoint = P.Call(r.Engine, "GetWaypoint")
    local changed = false
    for _, key in ipairs(observedFields) do
        local value = type(waypoint) == "table" and waypoint[key] or nil
        local kind = type(value)
        if kind ~= "number" and kind ~= "string" and kind ~= "boolean" then value = nil end
        if type(issecretvalue) == "function" and issecretvalue(value) then value = nil end
        if observed[key] ~= value then observed[key], changed = value, true end
    end
    if changed then API.Schedule("follower") end
end

function NS.RefreshPolestarNavigationOwnership()
    local r = API.GetRuntime()
    local wanted = NS.IsRoutingEnabled()
    if InCombatLockdown() then return end
    if followerRuntime and (not wanted or followerRuntime ~= r) then
        local api = followerRuntime.Nav.API
        local ok = pcall(api.Unfollow, FOLLOWER_OWNER)
        if not ok then return end
        followerRuntime, followerOwned = nil, false
    end
    local api = r and r.Nav and r.Nav.API
    if not wanted or followerOwned or type(api) ~= "table" or type(api.Follow) ~= "function"
        or type(api.Unfollow) ~= "function" then
        return
    end
    local ok, followed = pcall(api.Follow, FOLLOWER_OWNER, ObserveFollower, { pin = true, shows = true })
    if ok and followed == true then followerRuntime, followerOwned = r, true end
end

function API.GetFollowerStatus() return followerOwned end

local function Install()
    local r = API.GetRuntime()
    if not r then return false end
    if subscribed ~= r then
        subscribed = r
        for _, event in ipairs({ "GUIDE_CHANGED", "STEP_CHANGED", "STEP_UPDATED", "WAYPOINT_CHANGED", "TABS_CHANGED",
            "GUIDES_REGISTERED", "PACKS_CHANGED", "GUIDE_COMPLETED", "WHILE_HERE_CHANGED", "QUEST_TIMER",
            "NAME_LEARNED", "NAMES_LOADED", "QUESTDB_LOADED", "PARTY_PROGRESS", "TIMED_PULL" }) do
            P.Call(r, "On", event, function()
                if event == "GUIDE_CHANGED" then epoch = epoch + 1 end
                -- These helpers can change their text without changing a goal's
                -- coordinates or scalar view fields (names, timers, party work).
                if event == "NAME_LEARNED" or event == "NAMES_LOADED" or event == "QUESTDB_LOADED"
                    or event == "QUEST_TIMER" or event == "PARTY_PROGRESS" or event == "TIMED_PULL" then
                    presentationRevision = presentationRevision + 1
                end
                API.Schedule(event)
            end)
        end
        P.Call(r, "On", "SETTING_CHANGED", function(path)
            presentationRevision = presentationRevision + 1
            API.Schedule("settings")
            local b = NS.RoutingBackend_Polestar
            if b and (path == "" or path == "nav" or path == "nav.travel" or path == "nav.teleports"
                    or path == "nav.navRouting" or path == "nav.routeStyle") then
                b.OnPlanInvalidated("settings")
            end
        end)
    end
    if suppressionRuntime ~= r and type(r.Get) == "function" then
        local original = r.Get
        if Native then Native.InstallPolestar(r, original) end
        r.Get = function(path)
            if suppressed[path] and NS.IsRoutingEnabled() then return false end
            if path == "nav.mapPlan" and Native and Native.PolestarYields() then return false end
            return original(path)
        end
        suppressionRuntime = r
    end
    Hook(r.UI and r.UI.Picker, "LoadSelected", API.Activate)
    Hook(r.UI and r.UI.GuideFrame, "AimGoal", API.Activate)
    Hook(r.Engine, "AimAlong", API.Activate)
    Hook(r.Engine, "AimWhileHere", API.Activate)
    local function CurrentPoint(point)
        if P.Call(r.Nav, "IsHeld") then return nil end
        return P.Call(r.Nav, "IsOverride") == true and P.Call(r.Nav, "GetTarget") == point
    end
    Hook(r.Nav, "SetTarget", function()
        if not NS.IsRoutingEnabled() or not P.Call(r.Nav, "IsOverride") then return end
        local point = P.Call(r.Nav, "GetTarget")
        if type(point) ~= "table" then return end
        if not Native or type(r.Nav.ReleaseTarget) ~= "function" then
            API.RoutePoint(point, point.label)
            return
        end
        local map, x, y = P.Coordinates(r, point)
        if map then
            Native.Adopt("polestar", point, CurrentPoint, r.Nav.ReleaseTarget, map, x, y,
                P.Text(point.label) or "Polestar waypoint")
        end
    end)
    Hook(r.UI and r.UI.GuideFrame, "RenderTabs", WireNativeTabs)
    WireNativeTabs()
    NS.RefreshPolestarNavigationOwnership()
    API.Schedule("ready")
    return true
end

-- ============================================================
-- Guide commands and registration
-- ============================================================

function API.Action(action, guideID, stepIndex, goalIndex, expectedEpoch)
    local r = API.GetRuntime()
    if not r then return false end
    if action == "active" then
        API.Activate(); return true
    end
    local e, ui = r.Engine, r.UI
    local g = P.Call(e, "GetGuide")
    if InCombatLockdown() then
        if action ~= "route" or not g or g.id ~= guideID or expectedEpoch and epoch ~= expectedEpoch then return false end
        local waypoint = P.Call(e, "GetWaypoint")
        if not waypoint or not goalIndex or stepIndex ~= waypoint.stepIndex or goalIndex ~= waypoint.goalIndex then return false end
        API.Activate()
        return true
    end
    if action == "chooser" then return ui and type(ui.ShowPicker) == "function" and
        pcall(ui.ShowPicker, { newTab = true }) or false end
    if action == "settings" then return ui and type(ui.ShowOptions) == "function" and pcall(ui.ShowOptions, "guide") or
        false end
    if not g or g.id ~= guideID or expectedEpoch and epoch ~= expectedEpoch then return false end
    if action ~= "route" and action ~= "toggle" and P.Call(e, "GetStepIndex") ~= stepIndex then return false end
    -- Native previews publish step changes through the existing subscriptions.
    if action == "previous" then return pcall(e.Prev) end
    if action == "next" then return pcall(e.Next) end
    local methods = { skip = "Skip", complete = "Skip", recheck = "SetGuide" }
    local ok
    if action == "here" then
        for i, entry in ipairs(P.Call(e, "GetWhileHereList") or EMPTY) do
            if entry.appeared == goalIndex then
                local success, result = pcall(e.AimWhileHere, i)
                ok = success and result ~= false; break
            end
        end
    elseif action == "route" or action == "toggle" then
        local view = P.Call(e, "GetStepView", stepIndex, true)
        if not goalIndex or not view or not view.goals[goalIndex] then return false end
        if action == "toggle" and not view.goals[goalIndex].tickable then return false end
        local method = action == "toggle" and "ToggleGoal"
            or stepIndex == P.Call(e, "GetStepIndex") and "AimGoal" or "AimAlong"
        local success, result = pcall(e[method], stepIndex, goalIndex)
        ok = success and result ~= false
    elseif methods[action] then
        ok = pcall(e[methods[action]], action == "recheck" and g.id or nil)
    else
        return false
    end
    if ok then API.Activate() end
    return ok
end

function API.SelectTab(id)
    local r = API.GetRuntime()
    if not r or InCombatLockdown() then return false end
    for i, tab in ipairs(P.Call(r.Engine, "GetTabs") or EMPTY) do
        if tab.guideId == id then
            local ok = pcall(r.Engine.SelectTab, i); if ok then API.Activate() end; return ok
        end
    end
    return false
end

NS.RegisterExternalWaypointSource("polestar", {
    displayName = "Polestar",
    aliases = { "Polestar" },
    stackMatches = { "interface\\addons\\polestar\\", "polestar\\" },
    guideProvider = "polestar",
    transient = true
})
NS.RegisterGuideTargetProvider("polestar", {
    label = "Polestar",
    displayName = "Polestar",
    icon = "Interface\\AddOns\\Polestar\\Media\\UI\\logo",
    isLoaded = NS.IsPolestarLoaded,
    structuredPresentation = true,
    hasGuide = function() return snapshot.id ~= nil end,
    getVisibilityState = function() return API.GetRuntime() and "visible" or "absent" end,
    getActivationToken = function() return (snapshot.id or "") .. ":" .. (snapshot.rawCurrent or 0) end,
    extractTarget = function() return target, target == nil end,
    installHooks = function(schedule)
        routeSchedule = schedule; return Install()
    end,
    getDebugLines = function()
        return { "polestar state=" ..
        snapshot.state .. " guide=" .. tostring(snapshot.id) .. " step=" .. snapshot.current,
            "owner=" .. tostring(target and target.polestarOwner) .. " goal=" .. tostring(target and target.polestarGoal)
            .. " action=" .. tostring(target and target.polestarAction) .. " title=" .. tostring(target and target.title)
            ..
            " context=" ..
            tostring(target and target.subtext) .. " suppression=" .. tostring(target and target.polestarSuppression),
            "destination=" ..
            tostring(snapshot.destinationReason) .. " titleSource=" .. tostring(target and target.polestarTitleSource)
            .. " contextSource=" .. tostring(target and target.polestarContextSource),
            "follower=" .. tostring(followerOwned) .. " routing=" .. tostring(NS.IsRoutingEnabled()) }
    end,
})
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "ITEM_DATA_LOAD_RESULT",
    "QUEST_DATA_LOAD_RESULT", "SPELL_DATA_LOAD_RESULT", "PLAYER_REGEN_ENABLED" }) do pcall(watcher.RegisterEvent, watcher,
        event) end
watcher:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and (type(addon) ~= "string" or not addon:match("^Polestar")) then return end
    if not subscribed then
        Install()
    else
        presentationRevision = presentationRevision + 1
        API.Schedule(event)
    end
    NS.RefreshPolestarNavigationOwnership()
end)
