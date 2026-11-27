local path = dofile("tests/native_path.lua")
local noop = dofile("tests/guide_parity/fixture.lua").noop
local adapters = {}

local function loadProvider(f, key, stem)
    f.load("integrations/guides/" .. key .. "/" .. stem .. "_presentation")
    f.load("integrations/guides/" .. key .. "/" .. stem .. "_provider")
    return assert(f.NS.GetGuideTargetProvider(key))
end

local function selectTitle(kind, name)
    local verb = kind == "accept" and "Accept" or "Turn in"
    return verb .. " '" .. name .. "'"
end

local function npcFor(stop, quest) return quest.npc or stop.npc end
local function talk(npc) return npc and "Talk to " .. npc or nil end
local function locals(f, stop, quest)
    return f.x + (quest.offset or 0), f.y, stop.instruction
        or stop.objective and stop.objective.instruction or talk(npcFor(stop, quest))
end

function adapters.zygorGoalFacts(resolver, facts)
    local goals = {}
    for index, fact in ipairs(facts) do
        goals[index] = {
            action = fact.action, map = fact.mapID, x = fact.x, y = fact.y,
            questid = fact.questid, npcid = fact.npcid, orlogic = fact.orlogic,
            quest = fact.questTitle and { title = fact.questTitle }, force_noway = fact.suppressed == true,
            tooltip = fact.tooltip, GetText = function() return fact.text end,
            IsVisible = function() return fact.visible end, GetStatus = function() return fact.status end,
        }
    end
    return resolver.Private.BuildFacts({ goals = goals })
end

function adapters.zygor(f, scenario)
    local stop = scenario.stop
    local current, goals = nil, {}
    for i, quest in ipairs(stop.quests) do
        local kind = quest.kind or stop.kind
        local x, y, context = locals(f, stop, quest)
        if npcFor(stop, quest) and (i == 1 or npcFor(stop, stop.quests[i - 1]) ~= npcFor(stop, quest)) then
            goals[#goals + 1] = { action = stop.helper or "talk", text = context,
                npc = stop.structuredSubject and npcFor(stop,quest) or nil,
                npcid = stop.structuredSubject and 101 or nil }
            if i == 1 and stop.quests[2] and not npcFor(stop, stop.quests[2]) and not quest.offset then
                goals[#goals + 1] = { action = "clicknpc", text = "Talk to Guardian Yrel" }
            end
        elseif i > 1 and stop.quests[i-1].offset and npcFor(stop, stop.quests[i-1]) ~= npcFor(stop, quest) then
            goals[#goals + 1] = { action = "text", text = "Wait for the caravan." }
        end
        if i == 1 and stop.instruction and not npcFor(stop, quest) then
            goals[#goals + 1] = { action = stop.helper or "text", text = stop.instruction }
        end
        local objective = stop.objective
        if objective and objective.instruction then
            goals[#goals + 1] = { action = objective.helper, text = objective.instruction }
        end
        goals[#goals + 1] = {
            action = objective and (objective.action == "kill" and "kill" or "q") or kind,
            questid = quest.id, quest = { title = quest.name },
            orlogic = stop.alternatives and i or nil,
            text = quest.text or objective and objective.text or selectTitle(kind, quest.name),
            tooltip = objective and objective.text or nil, map = f.map, x = x, y = y,
            GetStatus = function()
                return (quest.state == "rewarded" or kind == "accept" and quest.state == "active")
                    and "complete" or "incomplete"
            end,
        }
        if i == scenario.current then current = #goals end
    end
    local step = { goals = goals, current_waypoint_goal_num = current }
    for i, goal in ipairs(goals) do
        goal.num, goal.parentStep = i, step
        goal.GetText = function(self) return self.text end
        goal.IsVisible = function(self) return self.visible ~= false end
    end
    local zygor = { CurrentStep = step, CurrentGuide = { title = "Parity fixture" },
        Frame = { IsVisible = function() return true end } }
    f.NS.ZGV = function() return zygor end
    if stop.noAnchor then
        local pointer = { ArrowFrame = { waypoint = { map = f.map, x = f.x, y = f.y,
            type = "way", arrowtitle = "Turned in 'Quest A'", goal = goals[current] } } }
        f.NS.GetZygorPointer = function() return zygor, pointer end
    end
    local root = "integrations/guides/zygor/"
    for _, name in ipairs({ "facts", "live_context", "scan", "presentation_context", "snapshot", "resolve" }) do
        f.load(root .. "guide_resolver/" .. name)
    end
    f.load(root .. "guide_resolver")
    f.load(root .. "source")
    f.load(root .. "zygor_provider")
    f.native = { runtime = zygor, entry = "BuildFacts -> canonical goal -> provider extraction" }
    return f.NS.GetGuideTargetProvider("zygor").extractTarget()
end

function adapters.apr(f, scenario, client)
    local stop = scenario.stop
    local ids = {}
    local quest = stop.quests[scenario.current]
    local x, y, note = locals(f, stop, quest)
    for _, candidate in ipairs(stop.quests) do
        if npcFor(stop, candidate) == npcFor(stop, quest) and candidate.offset == quest.offset
            and candidate.kind == quest.kind then
            ids[#ids + 1] = candidate.id
        end
    end
    local key = (quest.kind or stop.kind) == "accept" and "PickUp" or "Done"
    if stop.alternatives then key = key .. "DB" end
    local step = { [key] = ids, ExtraLineText = note, Coord = { x = x, y = y } }
    if stop.noAnchor then step.Coord = nil end
    if stop.objective then
        step[key], step.Qpart = nil, { [quest.id] = { 1 } }
    end
    _G.APRData = { player = { fixture = 1 } }
    local apr = { ActiveRoute = "fixture", PlayerID = "player" }
    local core = assert(loadfile(path(client, "APR/APR-Core/utils/StepUtils.lua")))
    local env = setmetatable({ APR = apr, LibStub = function()
        return { GetLocale = function() return {} end }
    end }, { __index = _G })
    setfenv(core, env)()
    apr.RouteQuestStepList = { fixture = { step } }
    if stop.noAnchor and stop.quests[2] then
        local q = stop.quests[2]
        apr.RouteQuestStepList.fixture[2] = { PickUp = { q.id }, Coord = { x = f.x + q.offset, y = f.y } }
    end
    apr.GetRouteSteps = function() return apr.RouteQuestStepList.fixture end
    apr.GetStepCoord = function(_, selected) return selected.Coord, f.map end
    apr.GetRouteMapID = function() return f.map end
    apr.GetPlayerMapPos = function(_, _, py, px) return px, py end
    _G.APR = apr
    f.native = { runtime = apr, entry = "GetStep -> GetStepString -> structured row" }
    local provider = loadProvider(f, "apr", "apr")
    f.NS.Internal.APRProvider.RefreshNow()
    return provider.extractTarget()
end

local function split(delimiter, text)
    local parts, from = {}, 1
    while true do
        local index = text:find(delimiter, from, true)
        if not index then break end
        parts[#parts + 1] = text:sub(from, index - 1)
        from = index + #delimiter
    end
    parts[#parts + 1] = text:sub(from)
    return unpack(parts)
end

function adapters.wowpro(f, scenario, client)
    local stop, current = scenario.stop, scenario.current
    local quest = stop.quests[current]
    local x, y, note = locals(f, stop, quest)
    local ids, questLog = {}, {}
    for _, candidate in ipairs(stop.quests) do
        if npcFor(stop, candidate) == npcFor(stop, quest) and candidate.offset == quest.offset
            and candidate.kind == quest.kind then
            ids[#ids + 1] = candidate.id
        end
        if candidate.state == "ready" or candidate.state == "active" then
            questLog[candidate.id] = { title = candidate.name, complete = candidate.state == "ready" }
        end
    end
    _G.WoWProDB = { char = { currentguide = "fixture" } }
    _G.WoWProCharDB = { Guide = {} }
    local wowpro = {
        ActiveStep = 1, GuideLoaded = true, stepcount = 1, Guides = { fixture = { zone = "Fixture zone" } },
        QuestLog = questLog, DebugLevel = 0, Tags = {}, action = {}, step = {}, why = {},
        Error = function(_, msg, ...) error(string.format(msg, ...)) end,
        Warning = function(_, msg, ...) error(string.format(msg, ...)) end,
        ValidZone = function() return "Fixture zone", f.map end,
        IntListVerify = function(value)
            for _, id in ipairs({split(value:find("^", 1, true) and "^" or "&", value)}) do
                if not id:match("^%d+$") then return false end
            end
            return true
        end,
        ValidateMapCoords = function(_, _, _, _, value) return value:match("^%d+%.%d+,%d+%.%d+$") ~= nil end,
        GrailLocalizeQuestName = function(_, _, _, authored) return authored end,
        GrailCheckQuestName = noop, GrailIsQuestObsolete = noop, GrailQuestLevel = function() return nil end, ExpandMarkup = noop,
    }
    _G.WoWPro = wowpro
    local parser = assert(loadfile(path(client, "WoWPro/WoWPro_Parser.lua")))
    local env = setmetatable({ WoWPro_Locale = setmetatable({}, { __index = function(_, key) return key end }),
        tinsert = table.insert, tremove = table.remove }, { __index = _G })
    setfenv(parser, env)()
    for _, tag in pairs(wowpro.TagTable) do
        if tag.key and wowpro[tag.key] == nil then wowpro[tag.key] = {} end
    end
    local kind = quest.kind or stop.kind
    local action = kind == "accept" and "A" or kind == "turnin" and "T" or "C"
    local row = string.format("%s %s|QID|%s|", action, quest.name,
        table.concat(ids, stop.alternatives and "^" or "&"))
    if not stop.noAnchor then row = row .. string.format("M|%.4f,%.4f|", x * 100, y * 100) end
    if stop.objective then row = row .. "QO|1|" end
    if note then row = row .. "N|" .. note .. "|" end
    local function parseRow(index, text)
        -- Native guide loading clears its tag arrays before parsing a row.
        for _, tag in pairs(wowpro.TagTable) do
            if tag.key then wowpro[tag.key][index] = nil end
        end
        local trim, oldSplit = string.trim, string.split
        string.trim, string.split = function(value) return value:match("^%s*(.-)%s*$") end, split
        local ok, result = pcall(wowpro.ParseQuestLine, nil, "Fixture zone", index, text)
        string.trim, string.split = trim, oldSplit
        assert(ok and result == index, tostring(result))
    end
    parseRow(1, row)
    if stop.noAnchor and stop.quests[2] then
        local q = stop.quests[2]
        parseRow(2, string.format("A %s|QID|%d|M|%.4f,%.4f|", q.name, q.id, (f.x+q.offset)*100, f.y*100))
    end
    local provider = loadProvider(f, "wowpro", "wowpro")
    f.native = { runtime = wowpro, entry = "ParseQuestLine -> selected tagged row", parseRow = parseRow }
    f.NS.Internal.WoWProProvider.RefreshNow()
    return provider.extractTarget()
end

function adapters.dugi(f, scenario, client)
    local stop, current = scenario.stop, scenario.current
    local dugi = { actions = {}, quests1 = {}, quests1L = {}, quests2 = {}, tags = {}, qid = {}, states = {},
        guides = {}, GuideMapID = f.map }
    local rows = {}
    for index, quest in ipairs(stop.quests) do
        local x, y, note = locals(f, stop, quest)
        local objective = stop.objective
        local kind = quest.kind or stop.kind
        local action = kind == "accept" and "A" or kind == "turnin" and "T"
            or objective.action == "kill" and "K" or "C"
        local subject = objective and (objective.subject or objective.text) or quest.name
        local n = string.format("%s%s(%.4f, %.4f)", note or "", note and " " or "", x * 100, y * 100)
        dugi.actions[index], dugi.quests1[index], dugi.quests1L[index] = action, subject, subject
        dugi.quests2[index], dugi.tags[index], dugi.qid[index] = n,
            "|N|" .. n .. "|Z|" .. f.map .. "|QID|" .. quest.id .. (objective and ".1" or "") .. "|", quest.id
        local complete = quest.state == "rewarded" or (kind == "accept" and quest.state == "active")
        dugi.states[index] = complete and "C" or "U"
        rows[index] = string.format("%s %s |QID|%d|N|%s|", action, subject, quest.id, n)
    end
    if stop.structuredSubject then
        for index in ipairs(stop.quests) do dugi.tags[index] = dugi.tags[index] .. "NPC|101|" end
        dugi.GetLocalizedNPC = function(_,id) if id==101 then return stop.npc end end
    end
    _G.CurrentTitle = "Parity fixture"
    _G.DugisGuideUser = { CurrentQuestIndex = current }
    _G.DugisGuideViewer = dugi
    dugi.guides[CurrentTitle] = function() return table.concat(rows, "\n") end
    local native = dofile("tests/guide_parity/native_function.lua")
    local env = { DGV = dugi, DGU = DugisGuideUser, lastUsedStepIndex = #stop.quests,
        LuaUtils = { RestIfNeeded = noop } }
    dugi.ReturnTag_cache = {}
    native(client, "DugisGuideViewerZ/Guides.lua", "DGV:ReturnTag", env)
    dugi.GetQuestState = function(_, index) return dugi.states[index] end
    dugi.GetQuestStepText = function(_, index) return dugi.quests2[index] end
    dugi.GetQuestDescription = dugi.GetQuestStepText
    dugi.CheckForSkip = function() return false end
    dugi.RestIfNeeded = noop
    native(client, "DugisGuideViewerZ/Guides.lua", "DGV:FindNextUnchecked", env)
    if stop.npc and not stop.alternatives and stop.kind ~= "mixed" then current = dugi:FindNextUnchecked() end
    DugisGuideUser.CurrentQuestIndex = current
    f.native = { runtime = dugi, entry = "ReturnTag -> FindNextUnchecked", environment = env }
    local x, y = locals(f, stop, stop.quests[current])
    dugi.DugisArrow = { getFinalWaypoint = function()
        if stop.noAnchor then return end
        return { map = f.map, x = x * 100, y = y * 100, guideIndex = DugisGuideUser.CurrentQuestIndex, isRouteDestination = true }
    end }
    local provider = loadProvider(f, "dugi", "dugi")
    return provider.extractTarget()
end

local function nativeRXP(client, kind)
    local file = assert(io.open(path(client, "RXPGuides/functions.lua"), "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local addon = { functions = {}, InsertQuestGuide = noop, pickUpList = {}, turnInList = {} }
    local env = setmetatable({ addon = addon, GetQuestId = tonumber, L = function(s) return s end,
        bit = { band = function() return 0 end }, CheckNpcIds = noop }, { __index = _G })
    local code = assert(source:match("(function addon%.functions%." .. kind .. "%(.-\nend)"))
    local chunk = assert(loadstring(code, "@RXPGuides/functions.lua"))
    setfenv(chunk, env)()
    return addon.functions[kind]
end

function adapters.rxp(f, scenario, client)
    local stop = scenario.stop
    local steps, points = {}, {}
    for i, quest in ipairs(stop.quests) do
        local tag = stop.objective and "complete" or quest.kind or stop.kind
        local native = nativeRXP(client, tag)
        local x, y, context = locals(f, stop, quest)
        local step = { index = i, stepId = i, active = i == scenario.current, arrowtext = context }
        local point = { tag = "goto", zone = f.map, x = x * 100, y = y * 100, textOnly = true, arrow = true, step = step }
        local authored = stop.objective and stop.objective.text or quest.name
        local objective = native("Parity fixture", authored, quest.id, stop.objective and 1 or nil)
        objective.tag, objective.step = tag, step
        if stop.structuredSubject then
            local subject = nativeRXP(client,"target")("Parity fixture",nil,npcFor(stop,quest))
            objective.targets = subject.targets
        end
        objective.completed = quest.state == "rewarded" or (tag == "accept" and quest.state == "active")
        step.elements = { point, objective }
        steps[i], points[i] = step, point
    end
    local current = scenario.current
    if stop.alternatives then
        local step = steps[1]
        step.active, step.arrowtext = true, talk(stop.npc)
        local ids = {}; for _, quest in ipairs(stop.quests) do ids[#ids+1] = quest.id end
        local tag = stop.kind == "accept" and "daily" or "dailyturnin"
        local objective = nativeRXP(client, tag)("Parity fixture", "Accept whichever variant is available", unpack(ids))
        objective.tag, objective.step = tag, step
        step.elements = { points[1], objective }
        steps, current = { step }, 1
    end
    if stop.npc and #steps > 1 and stop.kind ~= "mixed" then
        local grouped = { index = 1, stepId = 1, active = true, arrowtext = talk(stop.npc), elements = { points[1] } }
        for _, step in ipairs(steps) do
            local objective = step.elements[2]
            objective.step = grouped
            grouped.elements[#grouped.elements + 1] = objective
        end
        points[1].step = grouped
        steps, current = { grouped }, 1
    end
    local rxp = { currentGuide = { group = "Parity", name = "Fixture", steps = steps },
        RXPFrame = { activeSteps = { steps[current] } }, arrowFrame = { element = points[current] },
        activeWaypoints = { points[current] }, settings = { profile = {}, ReplaceColors = function(text) return text end },
        GetGuideProgress = function() return current end, SetStep = noop, RegisterMessage = noop, GetGuideTable = noop,
        LoadGuide = noop, ReloadGuide = noop, ActiveStepElementPostClick = noop, UpdateMap = noop, UpdateGotoSteps = noop }
    if stop.noAnchor then
        points[current].zone, points[current].x, points[current].y = nil, nil, nil
    end
    rxp.ScheduleTask, rxp.ProcessGeneratedSteps, rxp.QueueMessage, rxp.lastStepUpdate = noop, noop, noop, -2
    rxp.v2 = { IsGuideWindowEnabled = function() return true end, events = { Trigger = noop } }
    dofile("tests/guide_parity/native_function.lua")(client, "RXPGuides/GuideWindow.lua", "addon.UpdateStepCompletion",
        { addon = rxp, activeSteps = rxp.RXPFrame.activeSteps, RXPCData = { stepSkip = {} } })
    rxp.UpdateStepCompletion()
    f.native = { runtime = rxp, entry = "native directives -> UpdateStepCompletion -> selected waypoint" }
    _G.LibStub = function(name)
        if name == "AceAddon-3.0" then return { GetAddon = function() return rxp end } end
    end
    local provider = loadProvider(f, "rxp", "rxp")
    f.NS.Internal.RXPProvider.Schedule("Parity scenario")
    f.flush()
    return provider.extractTarget()
end

function adapters.polestar(f, scenario, client)
    local stop = scenario.stop
    local goals = {}
    for i, quest in ipairs(stop.quests) do
        local x, y = locals(f, stop, quest)
        local kind = quest.kind or stop.kind
        local complete = quest.state == "rewarded" or (kind == "accept" and quest.state == "active")
        goals[i] = { index = i, t = stop.objective and stop.objective.action or kind, status = complete and "done" or "active",
            quest = quest.id, npcName = npcFor(stop, quest), map = f.map, x = x * 100, y = y * 100,
            text = stop.objective and stop.objective.text or selectTitle(kind, quest.name),
            note = stop.instruction or stop.objective and stop.objective.instruction or nil }
    end
    local authored = {}
    for i, goal in ipairs(goals) do
        authored[i] = { t = goal.t, quest = goal.quest, title = stop.quests[i].name, either = stop.alternatives or nil,
            npc = goal.npcName and 101 or nil,
            target = stop.objective and stop.objective.subject or nil, npcName = goal.npcName,
            map = goal.map, x = goal.x, y = goal.y, note = goal.note }
        if stop.noAnchor and i == scenario.current then authored[i].map, authored[i].x, authored[i].y = nil, nil, nil end
    end
    local g = { id = "parity/fixture", title = "Fixture", steps = { { goals = authored } } }
    local native, own = dofile("tests/guide_parity/polestar.lua")(f, g, client)
    local view = native.Engine.GetStepView(1)
    local current = own.currentGoal(1, view.groups, view.focus)
    if not stop.noAnchor and (stop.kind == "mixed" or not stop.npc and #stop.quests > 1) then current = scenario.current end
    local goal = current and view.goals[current]
    -- The real selector's result supplies the arrow's runtime slot. The
    -- provider still reads the installed engine's public GetWaypoint method.
    for i = 1, 10 do
        local name = debug.getupvalue(native.Engine.GetWaypoint, i)
        if name == "waypoint" then
            debug.setupvalue(native.Engine.GetWaypoint, i, goal and { map = goal.map, x = goal.x, y = goal.y,
                stepIndex = 1, goalIndex = current } or nil)
            break
        end
    end
    _G.Polestar = native
    f.native.refresh = function()
        -- Stand in for the next engine evaluation's revision, not its goal
        -- choice. Both the view and selector remain the native functions.
        for i = 1, 10 do
            local name, value = debug.getupvalue(native.Engine.GetStepView, i)
            if name == "generation" then debug.setupvalue(native.Engine.GetStepView, i, value + 1); break end
        end
        local nextView = native.Engine.GetStepView(1)
        local selected = own.currentGoal(1, nextView.groups, nextView.focus)
        local goal = selected and nextView.goals[selected]
        for i = 1, 10 do
            local name = debug.getupvalue(native.Engine.GetWaypoint, i)
            if name == "waypoint" then
                debug.setupvalue(native.Engine.GetWaypoint, i, goal and { map = goal.map, x = goal.x, y = goal.y,
                    stepIndex = 1, goalIndex = selected } or nil); break
            end
        end
        f.NS.Internal.PolestarProvider.Schedule("WAYPOINT_CHANGED"); f.flush()
    end
    local provider = loadProvider(f, "polestar", "polestar")
    f.NS.Internal.PolestarProvider.Schedule("Parity scenario")
    f.flush()
    return provider.extractTarget()
end

function adapters.questierouter(f, scenario, client)
    local q = dofile("tests/guide_parity/questierouter.lua")(f, scenario, client)
    _G.QuestieRouter, _G.Questie = q, { db = { char = { complete = {} } } }
    f.load("integrations/guides/questierouter/runtime")
    local provider = loadProvider(f, "questierouter", "questierouter")
    f.NS.Internal.QuestieRouterProvider.RefreshNow()
    return provider.extractTarget()
end

return adapters
