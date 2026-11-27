-- Database and client APIs are fixture boundaries. Task construction, quest
-- exclusion, grouping and selection are the installed addon's own code.
local path = dofile("tests/native_path.lua")
return function(f, scenario, client)
    local stop = scenario.stop
    local records, points, active = {}, {}, {}
    local guide = { key = "fixture", zone = "Fixture zone", areaId = 1, quests = {}, info = {}, order = {} }
    local q = { ready = true, db = { enabled = true }, charDB = { activeGuide = guide.key },
        zoneGuideByKey = { [guide.key] = guide }, On = function() end, RegisterModule = function() end,
        L = setmetatable({}, { __index = function(_, key) return key end }) }
    q.HBD = {
        GetPlayerWorldPosition = function() return 550, 550, 1 end,
        GetWorldDistance = function(_, _, ax, ay, bx, by) return math.sqrt((ax-bx)^2+(ay-by)^2) end,
    }
    for i, quest in ipairs(stop.quests) do
        local objective = quest.objective or stop.objective
        local npc = quest.npc or stop.npc or stop.objectName
        guide.quests[i], guide.info[quest.id], guide.order[quest.id] = { quest.id }, {}, i
        records[quest.id] = { Id = quest.id, name = quest.name, level = 1,
            Starts = quest.id, Finisher = quest.id, Objectives = {}, Description = quest.description }
        if objective then
            records[quest.id].Objectives[1] = { Description = objective.text,
                Type = objective.type or (objective.action == "kill" and "killcredit" or "event"),
                Collected = objective.have, Needed = objective.need, Completed = objective.done }
        end
        if quest.state == "active" or quest.state == "ready" then active[#active+1] = quest.id end
        points[quest.id] = { uiMapId = f.map, x = f.x + (quest.offset or 0), y = f.y,
            wx = (f.x + (quest.offset or 0)) * 1000, wy = f.y * 1000, instance = 1,
            -- Same NPCs share identity; a different NPC must not merge merely
            -- because it occupies the same coordinate.
            name = npc, npcId = not stop.objectName and npc and 100 + (quest.npc and i or 0), dist = 20 + (quest.distance or 0) }
    end
    local function copyPoint(id)
        if stop.noAnchor and id == stop.quests[scenario.current].id then return end
        local p = {}; for k,v in pairs(assert(points[id])) do p[k] = v end; return p
    end
    q.Bridge = {
        UiMapOf = function() return f.map end, CandidateMaps = function() return { f.map } end,
        IterateActive = function()
            local live = {}
            for _, quest in ipairs(stop.quests) do
                if quest.state == "active" or quest.state == "ready" then live[#live+1] = quest.id end
            end
            local index = 0; return function() index = index + 1; return live[index] end
        end,
        GetQuest = function(_, id) return records[id] end,
        IsQuestComplete = function(_, quest) return C_QuestLog.ReadyForTurnIn(quest.Id) end,
        NearestNpcOrObject = function(_, id) return copyPoint(id) end,
        ObjectiveArea = function(_, quest) return copyPoint(quest.Id) end,
        NumQuestsInLog = function() return #active end,
        QuestStatus = function(_, id)
            for _, quest in ipairs(stop.quests) do if quest.id == id then return quest.state end end
            error("Unknown native quest " .. tostring(id))
        end,
        QuestieDB = { QueryQuestSingle = function(id, field)
            assert(field == "exclusiveTo")
            local exclusive = {}
            if stop.alternatives then
                for _, quest in ipairs(stop.quests) do if quest.id ~= id then exclusive[#exclusive+1] = quest.id end end
            end
            return exclusive
        end },
    }
    q.QuestNote = function(id)
        for _, quest in ipairs(stop.quests) do
            if quest.id == id then local o = quest.objective or stop.objective; return o and o.instruction end
        end
    end
    _G.UnitLevel = function() return 10 end
    assert(loadfile(path(client, "QuestieRouter/Guide/Steps.lua")))("QuestieRouter", q)
    assert(loadfile(path(client, "QuestieRouter/Guide/Planner.lua")))("QuestieRouter", q)
    local tasks = q.Planner:BuildTasks(guide)
    local selected = q.Planner:Choose(tasks)
    q.Planner.plan = { tasks = tasks, steps = q.Steps:FromTasks(tasks) }
    if not stop.npc and #stop.quests > 1 then
        local id = stop.quests[scenario.current].id
        for _, step in ipairs(q.Planner.plan.steps) do
            if step.questIds[1] == id then q.Planner:PinStep(step); break end
        end
        local pinned = q.Planner:MatchPinned(guide, q.Planner.plan.steps)
        selected = pinned and pinned.point or selected
    end
    q.target = selected
    f.native = { runtime = q, entry = "Planner:BuildTasks -> Planner:Choose -> Steps:FromTasks" }
    return q
end
