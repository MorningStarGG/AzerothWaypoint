local fixture = dofile("tests/guide_parity/fixture.lua")
local adapters = dofile("tests/guide_parity/native_adapters.lua")
local native = dofile("tests/guide_parity/native_function.lua")
local function noop() end
local names = { "Defend the harbor", "Meet Yrel at the Karabor Harbor" }
local function setup(client, provider)
    local scenario = { current = 1, stop = { kind = "accept", quests = { { id = 20001, name = "A quest", state = "available" } } } }
    local f = fixture.setup(client, scenario)
    adapters[provider](f, scenario, client)
    local stage = 1
    local have, need
    local function criteria(id)
        local index = id == 1001 and 1 or 2
        return { description = names[index], criteriaID = 500 + index, completed = index < stage,
            quantity = index < stage and 1 or have or 0, totalQuantity = index < stage and 1 or need or 1,
            quantityString = (index < stage and "1/1" or tostring(have or 0) .. "/" .. tostring(need or 1)) }
    end
    C_ScenarioInfo = {
        GetScenarioInfo = function() return { scenarioID = 10, currentStage = stage } end,
        GetScenarioStepInfo = function() return { stepID = 1000 + stage, numCriteria = 1 } end,
        GetCriteriaInfoByStep = function(id) return criteria(id) end,
        GetCriteriaInfo = function() return criteria(1000 + stage) end,
    }
    C_Scenario = {
        GetInfo = function() return "Harbor scenario", stage, 2 end,
        GetStepInfo = function() return nil, nil, 0 end, GetBonusSteps = function() return {} end,
        GetCriteriaInfoByStep = function(id)
            local c = criteria(id); return c.description, nil, c.completed, c.quantity, c.totalQuantity,
                nil, nil, nil, c.criteriaID
        end,
        GetCriteriaInfo = function() return unpack({ [9] = 500 + stage }, 1, 9) end,
    }
    function f.advance() stage = 2 end
    function f.progress(value, total) have, need = value, total end
    function f.output(title)
        f.frame.Fire("SCENARIO_CRITERIA_UPDATE", 500 + stage)
        f.flush()
        local target = assert(f.NS.GetGuideTargetProvider(provider).extractTarget(), "Scenario lost its destination")
        assert(target.title == title, provider .. " scenario expected " .. title .. ", got " .. tostring(target.title))
        assert(target.mapID == f.map and target.x == f.x and target.y == f.y, "Scenario changed coordinates")
        local shown, queue = fixture.publish(f, target)
        assert(shown.overlayTitle == title and shown.carrierTitle == title and queue.mirrorTitle == title)
        assert(shown.semanticQuestID == nil and queue.semanticQuestID == nil, "Scenario/criteria ID became a quest")
        return target
    end
    return f, f.native.runtime, criteria
end

for _, client in ipairs({ "retail", "forever" }) do
    do
        local f, r = setup(client, "rxp")
        r.functions = {}
        r.SetElementComplete = function(self) self.element.completed = true end
        r.SetElementIncomplete = function(self) self.element.completed = false end
        local env = { addon = r, fmt = string.format, L = function(text) return text end }
        native(client, "RXPGuides/functions.lua", "addon.functions.scenario", env, client == "retail" and 1 or 2)
        local step = { index = 1, stepId = 5, active = true, elements = {} }
        local point = { tag = "goto", zone = f.map, x = f.x*100, y = f.y*100, arrow = true, textOnly = true, step = step }
        step.elements[1] = point
        for i = 1, 2 do
            local e = r.functions.scenario("Fixture", "", tostring(1000+i), "1")
            e.tag, e.step = "scenario", step
            step.elements[i+1] = e
        end
        r.currentGuide.steps, r.RXPFrame.activeSteps = { step }, { step }
        r.arrowFrame.element, r.activeWaypoints = point, { point }
        local function update()
            for i = 2, 3 do r.functions.scenario({ element = step.elements[i] }) end
            f.NS.Internal.RXPProvider.Schedule("SCENARIO_CRITERIA_UPDATE")
        end
        update(); local first = f.output(names[1] .. ": 0/1")
        f.progress(1, 2); update(); f.output(names[1] .. ": 1/2")
        f.progress(nil, nil)
        f.advance(); update()
        assert(step.elements[2].completed and not step.elements[3].completed, "Native RXP did not advance criteria")
        local second = f.output(names[2] .. ": 0/1")
        assert(first.rxpElement ~= second.rxpElement, "RXP reused the old objective owner")
    end
    do
        local f, d = setup(client, "dugi")
        d.actions, d.quests1, d.quests1L, d.quests2, d.tags, d.qid, d.states, d.ReturnTag_cache = {}, {}, {}, {}, {}, {}, {}, {}
        local rows = {}
        for i = 1, 2 do
            d.actions[i], d.quests1[i], d.quests1L[i], d.states[i] = "N", names[i], names[i], "U"
            d.quests2[i] = "(55.0, 55.0)"
            d.tags[i] = "|SID|" .. (500+i) .. "|" .. i .. "|Z|" .. f.map .. "|N|" .. d.quests2[i] .. "|"
            rows[i] = "N " .. names[i] .. " " .. d.tags[i]
        end
        d.guides[CurrentTitle] = function() return table.concat(rows, "\n") end
        local env = { DGV = d, DGU = DugisGuideUser, lastUsedStepIndex = 2, LuaUtils = { RestIfNeeded = noop },
            MoveToNextQuest = function() DugisGuideUser.CurrentQuestIndex = d:FindNextUnchecked() end }
        native(client, "DugisGuideViewerZ/Guides.lua", "DGV:ReturnTag", env)
        native(client, "DugisGuideViewerZ/Guides.lua", "DGV:FindNextUnchecked", env)
        native(client, "DugisGuideViewerZ/Guides.lua", "DGV:UpdateAllSIDs", env)
        d.SetChkToComplete = function(_, i) d.states[i] = "C" end
        d.SetChkToNotComplete = function(_, i) d.states[i] = "U" end
        d.SetCompletedSID, d.UpdateCompletionVisuals = noop, noop
        f.NS.Internal.DugiPresentation.Invalidate()
        d:UpdateAllSIDs(); f.output(names[1])
        f.advance(); d:UpdateAllSIDs()
        assert(DugisGuideUser.CurrentQuestIndex == 2 and d.states[1] == "C", "Native Dugi did not advance the stage")
        f.output(names[2])
    end
    do
        local f, a = setup(client, "apr")
        a.mainStepOptions, a.ActiveQuests, a.stepHandlers = { "Scenario" }, {}, {}
        a.IsDelveRoute, a.IsScenarioTrigTextMatched, a.QpartPart_TrigTextMatch = function() return false end,
            function() return false end, function() return false end
        a.ContainsScenarioStepCriteria = function() return false end
        a.currentStep = { questsList = {}, AddQuestSteps = noop }
        local env = { APR = a, handlers = a.stepHandlers, APRScenarioCompleted = { player = {} } }
        native(client, "APR/APR-Core/utils/QuestUtils.lua", "APR:GetScenarioCriteriaProgressText", env)
        native(client, "APR/APR-Core/features/questing/StepTravelHandlers.lua", "handlers.RenderScenarioProgress", env)
        for i = 1, 2 do
            a.RouteQuestStepList.fixture[i] = { Scenario = { scenarioID = 10, stepID = 1000+i,
                criteriaID = 500+i, criteriaIndex = 1, questID = 1 }, Coord = { x = f.x, y = f.y } }
        end
        a.UpdateNextStep = function() APRData.player.fixture = APRData.player.fixture + 1 end
        local function update()
            a.stepHandlers.RenderScenarioProgress(a:GetStep(APRData.player.fixture))
            f.NS.Internal.APRProvider.Schedule("SCENARIO_CRITERIA_UPDATE")
        end
        update(); f.output(names[1] .. " (0/1)")
        f.progress(1, 2); update(); f.output(names[1] .. " (1/2)")
        f.progress(nil, nil)
        f.advance(); update()
        assert(APRData.player.fixture == 2, "Native APR did not complete the old criteria")
        f.output(names[2] .. " (0/1)")
        assert(f.NS.Internal.APRPresentation.ResolveRowQuestID(a:GetStep(2), "Scenario", 502, 10) == nil)
    end
    do
        local f, w = setup(client, "wowpro")
        w.ObjectiveOperators = {}
        w.dbp = noop
        local env = { WoWPro = w, OBJECTIVE_PATTERN = "^(%d*)([<=>]*)(%d*)$" }
        for _, name in ipairs({ "WoWPro.ObjectiveOperators.ScenarioDone", "WoWPro.ParseObjective", "WoWPro.ScenarioObjectiveStatus" }) do
            native(client, "WoWPro/WoWPro_Broker.lua", name, env)
        end
        w.ObjectiveOperators.S = w.ObjectiveOperators.ScenarioDone
        w.Scenario = { currentStage = 1, Criteria = { { criteriaString = names[1], completed = false, quantity = 0, totalQuantity = 1 } } }
        w.stepcount = 2
        for i = 1, 2 do
            w.QID[i], w.questtext[i] = nil, nil
            f.native.parseRow(i, "N " .. names[i] .. "|SO|" .. i .. ";1|M|55.0,55.0|")
            assert(w.sobjective[i] == i .. ";1", "Native SO parser did not retain the scenario criterion")
        end
        f.NS.Internal.WoWProProvider.Schedule("SCENARIO_UPDATE"); f.output(names[1] .. ": 0/1")
        w.Scenario.Criteria[1].quantity, w.Scenario.Criteria[1].totalQuantity = 1, 2
        -- No selected row, text, coordinates or tag changed. The criteria
        -- event itself must invalidate the cached content.
        f.output(names[1] .. ": 1/2")
        w.Scenario.Criteria[1].totalQuantity = 1
        w.Scenario.Criteria[1].completed, w.Scenario.Criteria[1].quantity = true, 1
        assert(w.ScenarioObjectiveStatus(1, "1"), "Native WoWPro did not complete the old criteria")
        f.advance(); w.ActiveStep, w.Scenario.currentStage = 2, 2
        w.Scenario.Criteria[1] = { criteriaString = names[2], completed = false, quantity = 0, totalQuantity = 1 }
        assert(not w.ScenarioObjectiveStatus(2, "1"))
        f.NS.Internal.WoWProProvider.Schedule("SCENARIO_UPDATE"); f.output(names[2] .. ": 0/1")
    end
    print(client .. " native RXP, Dugi, APR and WoWPro scenario criteria, advancement and presentation passed")
end
