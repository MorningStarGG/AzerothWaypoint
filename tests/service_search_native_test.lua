local fixture = dofile("tests/service_search_fixture.lua")
local native = dofile("tests/guide_parity/native_function.lua")
local nativePath = dofile("tests/native_path.lua")
for _, client in ipairs({"retail", "forever"}) do
    local f = fixture()
    local file = (client == "forever" and "ZygorGuidesViewerForever" or "ZygorGuidesViewer") .. "/WhoWhere.lua"
    local input = assert(io.open(nativePath(client, file), "rb"))
    local source = input:read("*a"):gsub("\r\n", "\n"); input:close()
    local queued, values = {}, {}
    local rover = {GetPlayerPosition = function() return .1, .1, 1412 end,
        QueueFindPath = function(...)
            local args = {...}; queued[#queued + 1] = {done = args[8], options = args[9]}
        end}
    local function copy(p) local out = {}; for k, v in pairs(p) do out[k] = v end; return out end
    local function iterate(list)
        local i = 0
        return function() i = i + 1; if list[i] then return i, list[i] end end
    end
    f.z.NPCData.iterate = function(_, kind) return iterate(values[kind] or {}) end
    f.z.NPCData.parseNPC = copy
    f.z.MailboxData.iterate = function() return iterate(values.mailbox or {}) end
    f.z.MailboxData.parseMailbox = copy
    f.z.GetCurrentMapContinent = function() return 1 end
    f.z.GetMapContinent = function() return 1 end
    f.z.Pointer = {ShowWaiting = function() end}
    local env = {WW = f.ww, ZGV = f.z, LibRover = rover,
        HBD = {GetZoneDistance = function(_, _, x, y, _, px, py) return (x - px)^2 + (y - py)^2 end}}
    setmetatable(env, {__index = _G})
    for _, name in ipairs({"CalcStep", "CalcThread_Direct", "CalcMailboxThread"}) do
        local body = assert(source:match("(local function " .. name .. "%b().-\nend)"), name)
        body = body:gsub("^local function", "function")
        local chunk = assert(loadstring(body, "@installed-" .. client .. "-" .. name))
        setfenv(chunk, env); chunk()
    end
    for _, method in ipairs({"WW:FindNPC", "WW:FindNPC_Smart", "WW:FindNPC_Direct", "WW:FindMailbox"}) do
        native(client, file, method, env)
    end
    f.search.Register("dugi", {label = "Dugi", Find = function()
        return {mapID = 1412, x = .4, y = .5, title = "Fallback", meta = {sourceAddon = "Dugi"}}
    end})
    values.Repair = {{m = 1412, x = 20, y = 30}}
    f.command("repair")
    assert(#queued == 1 and #f.calls == 0, "Native smart search did not remain pending")
    queued[1].done("progress")
    assert(#f.calls == 0)
    queued[1].done("failure")
    assert(#f.calls == 1 and f.calls[1].title == "Fallback")
    f.command("repair")
    local stale = queued[#queued].done
    f.search.Cancel()
    stale("success", {{type = "end", m = 1412, x = .1, y = .1, title = "old"}})
    assert(#f.calls == 1 and not f.ww.nativeWrites)
    values.Flightmaster = {{m = 1412, x = 80, y = 80}, {m = 1412, x = 20, y = 20}}
    f.command("flightmaster")
    f.worker:GetScript("OnUpdate")(f.worker, .1)
    assert(#f.calls == 2 and f.calls[2].x == .2 and f.calls[2].title == "NPC 2")
    assert(not f.worker:GetScript("OnUpdate") and not f.ww.thread and not f.ww.nativeWrites)
    values.mailbox = {}
    f.command("mailbox")
    f.worker:GetScript("OnUpdate")(f.worker, .1)
    assert(#f.calls == 3 and f.calls[3].title == "Fallback", "Empty native mailbox worker never fell back")
    values.mailbox = {{m = 1412, x = 30, y = 40}}
    f.command("mailbox")
    f.worker:GetScript("OnUpdate")(f.worker, .1)
    assert(#f.calls == 4 and f.calls[4].meta.searchKind == "npc_mailbox" and f.calls[4].x == .3)
    assert(not f.worker:GetScript("OnUpdate") and not f.ww.nativeWrites)
    print(client .. " installed WhoWhere smart/direct/mailbox completion and cancellation passed")
end

-- Exercise Dugi's actual profession-menu identifier contract, not labels inferred
-- from a tooltip. Its native GetNearest and AWP must pick the same point.
dofile("tests/dugi_provider_test.lua")
local ns, dugi = AzerothWaypointNS, assert(rawget(_G, "DugisGuideViewer"))
local points = {}
dugi.IterateAllFindNearestPoints = function()
    local i = 0
    return function() i = i + 1; return points[i] end
end
for _, client in ipairs({"retail", "forever"}) do
    local path = "DugisGuideViewerZ/WorldMapTracking.lua"
    local input = assert(io.open(nativePath(client, path), "rb"))
    local source = input:read("*a"):gsub("\r\n", "\n"); input:close()
    local definitions = assert(source:match("local englishProfessionTable%s*=%s*setmetatable%(%s*(%b{})"))
    local names = assert(loadstring("return " .. definitions))()
    ---@type table<string, any>
    local env = {DGV = dugi, GetDistance = function(p) return p[7] end}
    native(client, path, "GetNearest", env)
    local observed
    ns.RequestManualRoute = function(_, _, _, title) observed = title; return true end
    local count = 0
    for spell, name in pairs(names) do
        points = {{882, 0, 10, 1, "Wrong profession", "not-this-profession", 1},
            {882, 0, 10, 2, name .. " trainer", spell, 10}}
        assert(env.GetNearest(spell) == points[2], "Dugi's native profession identifier changed")
        assert(ns.Internal.ServiceSearch.Request({service = "trainer", profession = name:lower(), label = name .. " Trainer"}, "dugi"))
        assert(observed == name .. " trainer", "AWP failed the native " .. name .. " trainer contract")
        count = count + 1
    end
    print(client .. " Dugi native trainer identifiers: " .. count .. " exact profession mappings passed")
end

local polestar = dofile("tests/polestar_integration_test.lua").runtime
local input = assert(io.open(nativePath("forever", "Polestar/Nav/Nearby.lua"), "rb"))
local nearbySource = input:read("*a"):gsub("\r\n", "\n"); input:close()
local literal = assert(nearbySource:match("local KINDS = (%b{})"))
local kindEnv = {L = setmetatable({}, {__index = function(_, key) return key end})}
local chunk = assert(loadstring("return " .. literal)); setfenv(chunk, kindEnv)
local nearby = {KINDS = chunk()}
local byKey = {}; for _, kind in ipairs(nearby.KINDS) do byKey[kind.key] = kind end
local observedKind, observedLine
nearby.Rank = function(points) return points[1] end
local env = {Nearby = nearby, ALIAS = {}, BY_KEY = byKey, ns = {Compat = {GetPlayerWorldPosition = function() end}},
    candidates = function(kind, line)
        observedKind, observedLine = kind.key, line
        return {{map = 1, x = 20, y = 30, name = kind.key}}
    end}
native("forever", "Polestar/Nav/Nearby.lua", "Nearby.Find", env)
polestar.Nav.nearby = nearby
polestar.Compat.SKILL_LINES = {alchemy = 171}
local search = AzerothWaypointNS.Internal.ServiceSearch
for _, service in ipairs({"trainer", "food", "reagents", "repair", "transmogrifier"}) do
    assert(search.Request({service = service, profession = service == "trainer" and "alchemy" or nil, label = service}, "polestar"))
    assert(observedKind == service and (service ~= "trainer" or observedLine == 171))
end
assert(not search.Request({service = "poisons", label = "Poison Vendor"}, "polestar"),
    "Polestar claimed a poison-specific service absent from its native categories")
print("Polestar native categories and profession-specific Find contract passed")
