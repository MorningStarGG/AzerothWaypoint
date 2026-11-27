local f = assert(loadfile("tests/daylight_fixture.lua"))()
local NS = AzerothWaypointNS
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("integrations/guides/presentation.lua"))()
assert(loadfile("integrations/guides/source_runtime.lua"))()
local Runtime = NS.Internal.GuideSourceRuntime
local data = { id = "g", state = "ready", current = 2, total = 10, steps = {} }
local changed, reads, explicit = true, 0, 0
NS.ScheduleGuideProviderEvaluation = function(_, _, intent) if intent and intent.explicit then explicit = explicit + 1 end end
NS.SelectGuideProvider = function() return true end
local api = Runtime.Create({ key = "test", changed = function() local value = changed; changed = false; return value end,
    read = function() reads = reads + 1; local result = {}; for k,v in pairs(data) do result[k] = v end; return result end })
api.Schedule("initial"); f.Flush()
local snapshot = api.GetSnapshot()
for _ = 1, 100 do api.Schedule("unchanged") end
f.Flush()
assert(reads == 1 and snapshot == api.GetSnapshot() and explicit == 0)
api.Schedule("SPELLS_CHANGED"); f.Flush()
assert(reads == 2 and snapshot == api.GetSnapshot(), "Data-ready signal ignored or rebuilt unchanged output")
api.Activate("MakeActive"); f.Flush()
assert(reads == 3 and explicit == 1)
data.id = "other"; changed = true; api.Schedule("passive_load"); f.Flush()
assert(api.GetSnapshot().epoch == 2 and explicit == 1 and not api.IsCurrent("g", 2, 1))
data.displayCurrent = 5; changed = true; api.Schedule("progress"); f.Flush()
assert(api.GetSnapshot().displayCurrent == 5)
local rows = Runtime.Rows("Collect Journal", "Collect Journal in Ridge\nKill the guard\nOpen the chest\nUse the key", "collect", nil, "Ridge")
assert(#rows == 1 and #rows[1].tips == 3, "Shared action/context and three-tip policy was lost")
print("guide_source_runtime_test: passed")

local observation = AzerothWaypointNS.Internal.GuideSourceRuntime.CreateObservation()
observation:Begin(); observation:Push(nil); assert(observation:Finish())
observation:Begin(); observation:Push(false); assert(observation:Finish(), "False and absent were conflated")
observation:Begin(); observation:Push(false); assert(not observation:Finish())
