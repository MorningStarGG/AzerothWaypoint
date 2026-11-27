local path = dofile("tests/native_path.lua")
local f = dofile("tests/polestar_integration_test.lua")
local NS, runtime = AzerothWaypointNS, f.runtime
local P, Source = NS.Internal.PolestarPresentation, NS.Internal.GuideSourceRuntime
local function noop() end
local L = setmetatable({}, { __index = function(_, k) return k end })
local native = { L = L, Compat = runtime.Compat, Theme = { Hex = function() return "ffffffff" end },
    RegisterDefaults = noop, On = noop, Thousands = tostring, MoneyText = tostring }
assert(loadfile(path("forever", "Polestar/UI/UI.lua")))("Polestar", native)
runtime.UI = native.UI

-- The installed authored hub, not six unrelated synthetic quests. Native
-- Engine grouping and native UI reading helpers are both exercised below.
local guide, original = nil, Polestar
Polestar = setmetatable({ RegisterGuide = function(g)
    if g.id == "forever/horde/tauren/01-mulgore" then guide = g end
end }, { __index = function() return noop end })
assert(loadfile(path("forever", "Polestar_Guides_Horde/Guides.lua")))()
Polestar = original
assert(guide, "Installed Tauren guide missing")
C_QuestLog = { IsOnQuest = function(q) return q == 833 end,
    IsQuestFlaggedCompleted = function(q) return q == 773 or q == 775 or q == 861 end,
    ReadyForTurnIn = function() return false end, GetQuestObjectives = function() return {} end,
    GetTitleForQuestID = function(q) return tostring(q) end }
local engine = dofile("tests/guide_parity/polestar.lua")({}, guide, "forever")
local hubIndex
for i, step in ipairs(guide.steps) do
    if #step.goals == 6 and step.goals[3].quest == 775 then hubIndex = i; break end
end
local view = assert(engine.Engine.GetStepView(assert(hubIndex)))
assert(#view.goals == 6 and #view.groups == 4, "Native hub structure changed; review fixture")
local shown = P.BuildStep(runtime, view, false)
assert(#shown.goals == 6, "Completed goals were collapsed")
local order, headings = {}, {}
for _, row in ipairs(shown.rows) do
    if row.kind == "goal" then
        order[#order + 1] = row.goalIndex
        assert(row.stepIndex == hubIndex and not row.tips, "Lost original owner or injected navigation tips")
    elseif row.role == "heading" then
        headings[#headings + 1] = row.text
        assert(not row.goalIndex and not row.questID, "Heading acquired a goal")
    end
    assert(not row.text:find("Talk to ", 1, true), "Injected NPC objective survived")
end
assert(table.concat(order, ",") == "1,2,3,4,5,6")
assert(#headings == 4 and headings[1] == headings[4] and headings[1] ~= headings[2], "Visits were merged across field work")
assert(shown.rows[#shown.rows].text == P.Text(view.note), "Step note moved into a goal or following section")

local function goal(index, t, text, detail)
    return { index = index, t = t, text = text, detail = detail, status = "active" }
end
local accept = goal(1, "accept", "Accept a quest", "from the WANTED poster, from level 14")
local work = goal(2, "kill", "Kill mobs", "for the quest")
work.progress, work.note = { cur = 2, max = 8 }, "Stay on the ridge."
local finish = goal(3, "turnin", "Turn in a quest", "at the poster")
finish.status = "skipped"
local sample = { index = 19, title = "Ridge", goals = { accept, work, finish }, groups = {
    { kind = "object", name = "WANTED poster", goals = { 1 } },
    { kind = "here", goals = { 2 } }, { kind = "object", name = "WANTED poster", goals = { 3 } },
    { kind = "npc", name = "Empty", goals = {} } } }
local rows = P.BuildStep(runtime, sample).rows
assert(#rows == 7 and rows[1].text == "WANTED poster" and rows[6].text == "WANTED poster")
assert(rows[2].hoverTips[1].text:find("from level 14", 1, true), "Qualifier lost on hover")
assert(rows[4].text:find("2/8", 1, true) and rows[5].text == work.note and rows[5].role == "support")
assert(rows[7].status == "skipped", "Skipped goal disappeared or lost styling")
work.source = { name = "Ridge mobs", kind = "npc" }
work.noticeText, work.xpLeft, work.readyXp = "Check the quest", 120, 50
work.t = "collect"
local subline = P.BuildStep(runtime, sample).rows[5].text
assert(subline:find("Check the quest", 1, true) and subline:find("120 XP to go", 1, true)
    and subline:find("hand them in first", 1, true) and subline:find("Ridge mobs", 1, true),
    "Native warning, XP or source instruction was lost")
work.source, work.noticeText, work.xpLeft, work.readyXp = nil, nil, nil, nil
accept.unavailable, accept.unavailableText = true, "Needs level 14"
rows = P.BuildStep(runtime, sample).rows
assert(rows[3].text == "Needs level 14", "Unavailable warning was hidden with metadata")
accept.unavailable = nil
work.note = string.rep("Long instructions. ", 30)
assert(P.BuildStep(runtime, sample).rows[5].text == P.Text(work.note), "Long instruction was truncated")
work.folded = true; finish.status = "na"
local filtered = P.BuildStep(runtime, sample)
assert(#filtered.goals == 1 and #filtered.rows == 2, "Empty/native-excluded groups were rendered")

-- ReadingGoal merges a starter without borrowing its accept's row identity.
local starter = goal(1, "collect", "Collect a scroll", "A scroll")
starter.starterOf, starter.starter = 2, { item = "Scroll", held = true }
local merged = goal(2, "accept", "Accept the scroll quest")
merged.folded, merged.note, merged.quest = true, "Read it in your bags.", 77
local reading = P.BuildStep(runtime, { index = 22, goals = { starter, merged } })
assert(#reading.goals == 1 and reading.rows[1].text == merged.text and reading.rows[1].goalIndex == 1
    and reading.rows[1].questID == 77 and reading.rows[2].text:find(merged.note, 1, true))

-- Cache ownership covers same-coordinate group and metadata changes, while
-- native reading helpers are never called for unchanged observations.
local api, builds = NS.Internal.PolestarProvider, 0
local getView = runtime.Engine.GetStepView
runtime.Engine.GetStepView = function() return sample end
local build = P.BuildStep
P.BuildStep = function(...) builds = builds + 1; return build(...) end
api.Schedule("reading"); f.drain()
local snapshot, before = api.GetSnapshot(), builds
for _ = 1, 100 do api.Schedule("unchanged"); f.drain() end
assert(builds == before and api.GetSnapshot() == snapshot, "Unchanged refresh rebuilt reading rows")
sample.groups[1].name = "Another poster"
api.Schedule("label"); f.drain()
assert(api.GetSnapshot() ~= snapshot and api.GetSnapshot().steps[1].rows[1].text == "Another poster")
snapshot = api.GetSnapshot()
sample.groups[1].goals, sample.groups[3].goals = { 3 }, { 1 }
finish.status = "active"
api.Schedule("membership"); f.drain()
assert(api.GetSnapshot() ~= snapshot and api.GetSnapshot().steps[1].rows[2].goalIndex == 3)
snapshot = api.GetSnapshot()
accept.detail = "Different hover detail"
api.Schedule("hover"); f.drain()
assert(api.GetSnapshot().signature ~= snapshot.signature, "Hover-only change did not invalidate publication")
local hint = "Timer warning"
native.Timed = { LimitText = function() return hint end, Badge = noop }
f.fire("QUEST_TIMER"); f.drain()
snapshot = api.GetSnapshot(); hint = "Timer changed"
f.fire("QUEST_TIMER"); f.drain()
assert(api.GetSnapshot().signature ~= snapshot.signature, "Native timer helper change was cached")
runtime.Engine.GetStepView, P.BuildStep = getView, build
local nearby = goal(8, "turnin", "Turn in the nearby quest", "at Cairne Bloodhoof")
nearby.step, nearby.appeared, nearby.quest = 51, 17, 99
runtime.Engine.GetWhileHereList = function() return { nearby } end
api.Schedule("nearby"); f.drain()
local here = api.GetSnapshot().steps[#api.GetSnapshot().steps]
assert(here.section == "nearby" and here.rows[1].goalIndex == 8 and here.rows[1].stepIndex == 51
    and here.rows[1].hereSerial == 17 and here.rows[1].hoverTips[1].text == nearby.detail,
    "Nearby goal lost native identity or quest context")
local observation = Source.CreateObservation()
observation:Begin(); P.ObserveStep(observation, sample); assert(observation:Finish())
observation:Begin(); P.ObserveStep(observation, sample); assert(not observation:Finish())
accept.rewards = { items = { { item = 1, itemName = "Reward" } } }
observation:Begin(); P.ObserveStep(observation, sample); assert(observation:Finish())
accept.rewards.items[1].itemName = "Different reward"
observation:Begin(); P.ObserveStep(observation, sample); assert(observation:Finish())

local tab, answer, escort = 1, nil, true
---@type number?
local question = 901
local e = runtime.Engine
local originalTabs = e.GetTabs
e.GetTabs = function() return originalTabs(), tab end
e.GetLiveStep = e.GetStepIndex
e.GroupQuestion = function()
    return question, "The escort", escort and { escort = true, text = "About 12 minutes" } or nil
end
e.AnswerGroup = function(id, value)
    assert(id == question)
    answer, question = value, nil
end
local function currentRows()
    api.Schedule("quest_choice"); f.drain()
    return api.GetSnapshot().steps[1].rows
end
local rowsWithChoice = currentRows()
assert(rowsWithChoice[2].text == "About 12 minutes" and rowsWithChoice[3].text == "Do it")
local stale = rowsWithChoice[3].interaction
tab = 2
assert(not api.RunRowAction(stale) and not answer, "A recycled tab answered the old question")
assert(api.RunRowAction(currentRows()[3].interaction) and answer == "do")
question, escort = 902, false
local groupRows = currentRows()
assert(groupRows[2].text == "Do it with a group")
assert(api.RunRowAction(groupRows[3].interaction) and answer == "skip")
runtime.UI.StepMark = function() return "group", "Elites at your level" end
assert(currentRows()[1].text == "Elites at your level")
rawset(_G, "Polestar", nil)
api.Schedule("runtime_unavailable"); f.drain()
assert(api.GetSnapshot().state ~= "ready", "Missing runtime left stale reading content")
print("Native Polestar hub grouping, full goals, inline/hover reading, warnings, starter identity and bounded cache invalidation passed")
