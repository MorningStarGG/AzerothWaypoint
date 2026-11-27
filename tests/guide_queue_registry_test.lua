local f = assert(loadfile("tests/route_planning_fixture.lua"))()("direct")
local NS = f.NS
for _, name in ipairs({ "state", "items", "routing", "projection", "snapshot" }) do
    assert(loadfile("bridge/routing/queues/" .. name .. ".lua"))()
end
assert(loadfile("interface/queue/model.lua"))()
local Queue, model = NS.RouteQueueInternal, NS.Internal.QueueUI
local empty = NS.GetQueuePanelSnapshot()
assert(#empty.guideQueues == 0 and empty.activeGuideQueueID == nil and empty.guideQueue == nil)
assert(NS.State.routing.guideQueue == nil and Queue.GetActiveGuideQueue() == nil)
assert(NS.GetActiveQueueProjection() == nil)
Queue.ClearGuideQueueProjection("unloaded")
assert(#Queue.GetGuideQueueList() == 0, "A read or clear created a phantom guide")

local q = Queue.EnsureGuideQueue("questierouter", "QuestieRouter")
local p = Queue.EnsureGuideQueue("polestar", "Polestar")
q.projection = { entries = { { title = "Questie objective" } } }
p.projection = { entries = { { title = "Polestar objective" } } }
Queue.SetActiveGuideProvider("polestar")
local snapshot = NS.GetQueuePanelSnapshot()
assert(snapshot.activeGuideQueueID == p.id and #snapshot.guideQueues == 2 and snapshot.guideQueue == nil)
assert(snapshot.guideQueues[1].id == q.id and snapshot.guideQueues[2].id == p.id,
    "Selecting the active provider reordered its queues")
assert(model.ResolveSelectedQueue(snapshot).id == p.id)
NS.SetQueuePanelSelection(q.id)
assert(model.ResolveSelectedQueue(snapshot).id == q.id)
Queue.SetActiveGuideProvider("questierouter")
snapshot = NS.GetQueuePanelSnapshot()
assert(snapshot.activeGuideQueueID == q.id and model.ResolveSelectedQueue(snapshot).id == q.id)
Queue.ClearGuideQueueProjection("questierouter")
snapshot = NS.GetQueuePanelSnapshot()
assert(model.ResolveSelectedQueue(snapshot).id == p.id, "An unavailable selected projection hid the remaining guide")
assert(model.FindQueueByKey(snapshot, "guide") == nil, "The removed generic queue alias is still interpreted")
Queue.ClearGuideQueueProjection()
snapshot = NS.GetQueuePanelSnapshot()
assert(model.ResolveSelectedQueue(snapshot) == nil and #snapshot.guideQueues == 2)
assert(NS.GetActiveQueueProjection() == nil and NS.State.routing.guideQueue == nil)
print("Guide queue registry: empty reads, explicit providers, selection, ordering and canonical snapshots passed")
