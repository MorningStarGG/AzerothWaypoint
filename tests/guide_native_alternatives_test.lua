local fixture = dofile("tests/guide_parity/fixture.lua")
local adapters = dofile("tests/guide_parity/native_adapters.lua")
local native = dofile("tests/guide_parity/native_function.lua")
local path = dofile("tests/native_path.lua")
local function noop() end
for _, client in ipairs({ "retail", "forever" }) do
    for _, kind in ipairs({ "accept", "turnin" }) do
        local scenario = { current = 1, stop = { kind = kind, alternatives = true, npc = "Quartermaster Brevin", quests = {
            { id = 22001, name = "Quest A", state = kind == "accept" and "available" or "ready" },
            { id = 22002, name = "Quest B", state = kind == "accept" and "available" or "ready" },
        } } }
        local f = fixture.setup(client, scenario)
        adapters.rxp(f, scenario, client)
        local r, api = f.native.runtime, f.NS.Internal.RXPProvider
        local e = r.currentGuide.steps[1].elements[2]
        assert(e.multiple and #e.ids == 2)
        r.functions, r.icons = {}, { daily = "", accept = "", turnin = "" }
        local env = { addon = r, GetQuestId = tonumber, L = function(text) return text end, RXPCData = {} }
        native(client, "RXPGuides/functions.lua", "addon.functions.daily", env)
        native(client, "RXPGuides/functions.lua", "addon.functions.dailyturnin", env)
        local input = assert(io.open(path(client, "RXPGuides/functions.lua"), "rb"))
        local source = input:read("*a"); input:close()
        for _, alias in ipairs({ "acceptmultiple", "turninmultiple" }) do
            local statement = assert(source:match("addon%.functions%." .. alias .. " = addon%.functions%.%w+"))
            local chunk = assert(loadstring(statement)); setfenv(chunk, setmetatable(env, { __index = _G })); chunk()
        end
        e.tag = kind == "accept" and "acceptmultiple" or "turninmultiple"
        assert(r.functions[e.tag] == r.functions[kind == "accept" and "daily" or "dailyturnin"])
        if kind == "accept" then
            r.recentAccept, r.disabledQuests, r.questAccept, r.skipPreReq = {}, {}, {}, {}
            r.IsOnTurnInGuide, r.UpdateItemFrame, r.UpdateStepText = noop, noop, noop
            r.GetQuestName = C_QuestLog.GetTitleForQuestID
            r.SetElementComplete = function(self) self.element.completed = true end
            r.SetElementIncomplete = function(self) self.element.completed = false end
            r.comms = { grouping = { ShareQuest = noop } }
            env.IsOnQuest, env.IsQuestTurnedIn, env.ProcessItems = C_QuestLog.IsOnQuest, C_QuestLog.IsQuestFlaggedCompleted, noop
            env.bit = { band = function() return 0 end }
            native(client, "RXPGuides/functions.lua", "addon.functions.accept", env)
            r.functions.acceptmultiple({ element = e })
            -- Native iteration leaves the last candidate on questId. It is
            -- not proof that the NPC is offering that particular variant.
            assert(e.questId == e.ids[#e.ids] and not e.completed)
        end
        local function expect(id)
            api.Schedule("native_choice_update"); f.flush()
            local target = assert(f.NS.GetGuideTargetProvider("rxp").extractTarget())
            local shown, queue = fixture.publish(f, target)
            assert(shown.overlayTitle == "Talk to Quartermaster Brevin")
            assert(shown.semanticQuestID == id and queue.semanticQuestID == id)
            if id then
                assert(shown.pinpointSubtext == (kind == "accept" and "Accept" or "Turn in") .. " 'Quest B'")
            else
                assert(shown.pinpointSubtext == (kind == "accept" and "Accept Available Quest" or "Turn In Available Quest"))
            end
            return target
        end
        local generic = expect(nil)
        f.openDialog(22002); local specific = expect(22002)
        assert(specific.guideStepIdentity == generic.guideStepIdentity and specific.x == generic.x)
        local builds = api.counters.built
        for _ = 1, 40 do api.Schedule("unchanged_choice") end; f.flush()
        assert(api.counters.built == builds, "Unchanged choice rebuilt cached presentation")
        -- Change the candidates in place while the old quest page remains
        -- open. Neither the cache nor the dialog may retain a removed ID.
        e.ids[2] = 22001
        api.Schedule("candidate_list_changed"); f.flush()
        local changed = f.NS.GetGuideTargetProvider("rxp").extractTarget()
        assert(changed.semanticQuestID ~= 22002, "In-place candidate changes reused the old quest")
        e.ids[2] = 22002
        f.closeDialog(); expect(nil)
        if kind == "accept" then
            -- Quest recovery must also use the candidate list, never its
            -- stale last-iteration questId. Only an actual matching native
            -- acceptance may be selected automatically by Back.
            local pickup = r.currentGuide.steps[1]
            local current = 3
            r.currentGuide.steps = { pickup, { index = 2, stepId = 2, elements = {} },
                { index = 3, stepId = 3, active = true,
                    elements = { { tag = "complete", questId = 22002, text = "Complete Quest B" } } } }
            r.GetGuideProgress = function() return current end
            r.SetStep = function(index) current = index end
            r.IsStepShown = function() return true end
            r.IsQuestTurnedIn = function() return false end
            e.ids[2] = 22001
            local ok, reason, index = api.RunAction("previous")
            assert(not ok and reason == "choose_step" and index == 2 and current == 3,
                "Recovery used a removed native candidate")
            e.ids[2] = 22002
            assert(api.RunAction("previous") and current == 1, "Recovery missed an acceptmultiple candidate")
        end
    end
    print(client .. " native RXP daily/multiple aliases, live choice, closure and candidate-cache ownership passed")
end
