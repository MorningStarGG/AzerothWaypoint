local fixture = dofile("tests/service_search_fixture.lua")
local f = fixture()
local search, queried = f.search, {}
local function point(title)
    return {mapID = 1412, x = 0, y = .4, title = title, meta = {sourceAddon = title}}
end
search.Register("dugi", {label = "Dugi", Find = function(q)
    queried[#queried + 1] = q
    if q.service == "repair" then return point("Dugi repair") end
end})
f.order[1], f.order[2], f.order[3] = "rxp", "dugi", "zygor"
f.command("repair")
assert(#f.calls == 1 and f.calls[1].title == "Dugi repair" and #f.callbacks == 0,
    "Search ignored guide order or depended on active/enabled Viewers")
assert(f.calls[1].meta.queueSourceType == "transient_source" and f.calls[1].x == 0)
f.command("trainer alchemy")
assert(queried[#queried].profession == "alchemy" and #f.callbacks == 1,
    "A specific profession was degraded to a generic trainer")
f.callbacks[1].done("progress")
assert(#f.calls == 1, "Pending search was treated as a completed result")
f.callbacks[1].done("success", {{type = "end", m = 1412, x = .7, y = .8, title = "123"}})
assert(#f.calls == 2 and f.calls[2].title == "NPC 123" and f.calls[2].meta.searchKind == "npc_trainer_alchemy")
assert(not f.ww.nativeWrites, "Shared search launched a second native navigator")

-- A later request, native menu search, or explicit destination invalidates old callbacks.
f.command("trainer alchemy")
local stale = f.callbacks[#f.callbacks].done
f.command("repair")
stale("success", {{type = "end", m = 1, x = .1, y = .1, title = "stale"}})
assert(#f.calls == 3 and f.calls[3].title == "Dugi repair")
f.command("trainer alchemy")
stale = f.callbacks[#f.callbacks].done
search.Cancel()
stale("failure")
assert(#f.calls == 3, "Cancelled search fell back or changed navigation")
f.command("trainer alchemy")
stale = f.callbacks[#f.callbacks].done
f.ww:FindNPC("Repair")
stale("success", {{type = "end", m = 1, x = .1, y = .1, title = "stale"}})
assert(#f.calls == 3)
local native = f.callbacks[#f.callbacks].done
f.command("repair")
native("success", {{type = "end", m = 1, x = .1, y = .1, title = "stale native"}})
assert(not f.ww.nativeWrites, "Late native search displaced the newer shared request")
f.ww:FindNPC_Direct("Flightmaster")
f.command("repair")
f.worker:GetScript("OnUpdate")(f.worker, .1)
assert(not f.ww.nativeWrites, "Superseded native direct worker published an old pin")

f.order[1], f.order[2], f.order[3] = "zygor", "dugi", "polestar"
f.command("vendor")
local vendor = f.callbacks[#f.callbacks]
assert(vendor.kind == "Vendor")
vendor.done("failure")
assert(f.callbacks[#f.callbacks].kind == "Repair", "General vendor search excluded repair merchants")
f.callbacks[#f.callbacks].done("success", {{type = "end", m = 1, x = .1, y = .2, title = "repair merchant"}})
assert(f.calls[#f.calls].title == "repair merchant")

f.command("flightmaster")
assert(f.worker:GetScript("OnUpdate"), "Direct native worker did not start")
f.worker:GetScript("OnUpdate")(f.worker, .1)
assert(f.calls[#f.calls].title == "NPC 99" and not f.worker:GetScript("OnUpdate"),
    "Direct worker completion was not adopted/cleaned up")
assert(not f.ww.nativeWrites)
f.command("mailbox")
f.command("repair")
assert(not f.worker:GetScript("OnUpdate") and f.ww.thread == nil, "Superseded native worker remained active")

local old = #f.calls
search.Register("polestar", {label = "Polestar", Find = function() error("data not ready") end})
f.z.NPCData.raw.TrainerAlchemy = nil
f.command("trainer alchemy")
assert(#f.calls == old and f.messages[#f.messages]:find("No available guide", 1, true),
    "Exhausted/failed providers replaced the existing route")
f.command("workshop engineering")
assert(queried[#queried].service == "workshop" and queried[#queried].profession == "engineering")
for _, name in ipairs({"poison vendor", "poisons", "reagent vendor", "food", "drink"}) do
    f.command(name)
    local expected = name:find("poison") and "poisons" or name:find("reagent") and "reagents" or "food"
    assert(queried[#queried].service == expected and not queried[#queried].zygorType,
        "Explicit merchant category was broadened to a generic vendor")
end
f.command("unknown service")
assert(#f.calls == old)
local count = #queried
search.Request({service = "repair", label = "Repair"}, "polestar")
assert(#queried == count, "Named provider menu silently used another provider")
assert(#f.timers == 0 and not f.worker:GetScript("OnUpdate"), "Search left idle polling or queued adoption work")
print("Shared service search order, exact requests, vendor categories, async ownership and idle cleanup passed")
