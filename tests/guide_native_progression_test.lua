local fixture = dofile("tests/guide_parity/fixture.lua")
local adapters = dofile("tests/guide_parity/native_adapters.lua")
local native = dofile("tests/guide_parity/native_function.lua")
local coordinator = dofile("tests/guide_parity/coordinator.lua")
local function noop() end
for _, client in ipairs({ "retail", "forever" }) do
    for _, key in ipairs({ "zygor", "dugi", "apr", "wowpro", "rxp", "polestar", "questierouter" }) do
        if client == "forever" or key ~= "polestar" and key ~= "questierouter" then
            local scenario = { current = 1, stop = { kind = "accept", npc = "Quartermaster Brevin", quests = {
                { id = 21001, name = "Quest A", state = "available" }, { id = 21002, name = "Quest B", state = "available" } } } }
            local f = fixture.setup(client, scenario)
            adapters[key](f, scenario, client)
            local r = f.native.runtime
            local function read(id, title)
                local target = assert(f.NS.GetGuideTargetProvider(key).extractTarget())
                local shown, queue, icon = fixture.publish(f, target)
                assert(shown.overlayTitle == title and shown.semanticQuestID == id and icon == "AvailableQuest")
                assert(queue.mirrorTitle == title and queue.semanticQuestID == id)
                assert(target.mapID == f.map and target.x == f.x and target.y == f.y)
                -- Freeze the provider's resolved protocol before constructing a
                -- separate coordinator namespace. No expected string enters it.
                local copy = {}; for k,v in pairs(target) do copy[k] = v end
                copy.title, copy.subtext = shown.overlayTitle, shown.pinpointSubtext
                copy.semanticKind, copy.semanticQuestID = shown.semanticKind, shown.semanticQuestID
                copy.iconHintKind, copy.iconHintQuestID = shown.iconHintKind, shown.semanticQuestID
                return copy
            end
            local first = read(21001, "Accept 'Quest A'")
            scenario.stop.quests[1].state = "active"
            if key == "zygor" then
                f.NS.MarkGuideResolverFactsDirty("QUEST_LOG_UPDATE")
            elseif key == "dugi" then
                r.SetChkToComplete = function(_, i) r.states[i] = "C" end
                native(client, "DugisGuideViewerZ/Guides.lua", "DGV:CompleteQID", f.native.environment)
                r:CompleteQID(21001, "A")
                DugisGuideUser.CurrentQuestIndex = r:FindNextUnchecked()
                assert(DugisGuideUser.CurrentQuestIndex == 2)
            elseif key == "apr" then
                r.ActiveQuests = { [21001] = {} }
                assert(not r:IsRollbackStepComplete(r:GetStep(1)), "Grouped APR step completed before every pickup")
                f.NS.Internal.APRProvider.Schedule("QUEST_LOG_UPDATE"); f.flush()
            elseif key == "wowpro" then
                r.QuestLog[21001] = { title = "Quest A" }
                f.NS.Internal.WoWProProvider.Schedule("QUEST_LOG_UPDATE"); f.flush()
            elseif key == "rxp" then
                r.functions, r.pickUpList, r.recentAccept, r.disabledQuests, r.questAccept, r.skipPreReq = {}, {}, {}, {}, {}, {}
                r.InsertQuestGuide, r.UpdateStepText, r.UpdateItemFrame, r.IsOnTurnInGuide = noop, noop, noop, noop
                r.comms, r.icons = { grouping = { ShareQuest = noop } }, { accept = "" }
                r.GetQuestName = C_QuestLog.GetTitleForQuestID
                r.SetElementComplete = function(self) self.element.completed = true end
                r.SetElementIncomplete = function(self) self.element.completed = false end
                local env = { addon = r, IsOnQuest = C_QuestLog.IsOnQuest, IsQuestTurnedIn = C_QuestLog.IsQuestFlaggedCompleted,
                    GetQuestId = tonumber, ProcessItems = noop, bit = { band = function() return 0 end } }
                native(client, "RXPGuides/functions.lua", "addon.functions.accept", env)
                for _, e in ipairs(r.currentGuide.steps[1].elements) do
                    if e.tag == "accept" then r.functions.accept({ element = e }, "QUEST_ACCEPTED", 21001) end
                end
                r.UpdateStepCompletion()
                assert(not r.currentGuide.steps[1].completed, "Grouped RXP step completed before the next pickup")
                f.NS.Internal.RXPProvider.Schedule("QUEST_ACCEPTED"); f.flush()
            elseif key == "polestar" then
                assert(r.Engine.GoalDone(1, 1) and not r.Engine.GoalDone(1, 2))
                f.native.refresh()
                assert(r.Engine.GetWaypoint().goalIndex == 2)
            elseif key == "questierouter" then
                local tasks = r.Planner:BuildTasks(r.Planner:GetGuide())
                r.target = r.Planner:Choose(tasks)
                r.Planner.plan = { tasks = tasks, steps = r.Steps:FromTasks(tasks) }
                assert(r.target.questId == 21002)
                f.NS.Internal.QuestieRouterProvider.RefreshNow()
            end
            local second = read(21002, "Accept 'Quest B'")
            coordinator(client, key, first, second)
            print(client .. " / " .. key .. " native quest progression and asynchronous routing passed")
        end
    end
end
