return function()
    local calls, messages, nativeCallbacks, timers = {}, {}, {}, {}
    local order = {"zygor", "dugi", "polestar"}
    local worker = {scripts = {}}
    function worker:SetScript(key, fn) self.scripts[key] = fn end
    function worker:GetScript(key) return self.scripts[key] end
    ---@type table<string, any>
    local z = {NPCData = {raw = {Vendor = "", Repair = "", TrainerAlchemy = "", Flightmaster = ""}},
        MailboxData = {}, db = {profile = {pathfinding = true}},
        Localizers = {GetTranslatedNPC = function(_, id) return "NPC " .. tostring(id) end}}
    ---@type table<string, any>
    local ww = {WorkerFrame = worker}
    z.WhoWhere = ww
    ww.SetWaypoint = function(self, map, x, y, id)
        self.nativeWrites = (self.nativeWrites or 0) + 1
        self.CurrentWay = {type = "manual", map = map, x = x, y = y, title = tostring(id)}
    end
    ww.PathFoundHandler = function(status, path)
        if status == "success" then
            local p = path[#path]; ww:SetWaypoint(p.m, p.x, p.y, p.title)
        end
    end
    ww.FindNPC_Smart = function(_, typ, _, callback)
        nativeCallbacks[#nativeCallbacks + 1] = {kind = typ, done = callback or ww.PathFoundHandler}
    end
    ww.FindNPC = function(self, typ) return self:FindNPC_Smart(typ) end
    ww.FindNPC_Direct = function(self)
        self.thread = coroutine.create(function() self:SetWaypoint(1, .2, .3, 99) end)
        worker:SetScript("OnUpdate", function()
            local ok, reason = coroutine.resume(self.thread); assert(ok, reason)
            if coroutine.status(self.thread) == "dead" then self.thread = nil; worker:SetScript("OnUpdate", nil) end
        end)
    end
    ww.FindMailbox = function(self) return self:FindNPC_Direct("Mailbox") end
    ---@type table<string, any>
    local ns = {Internal = {Interface = {options = {}}}, State = {}, Constants = {},
        IsWoWForever = function() return true end,
        ZGV = function() return z end,
        GetGuideTrackerViewerOrder = function() return order end,
        Msg = function(...)
            local values = {}; for i = 1, select("#", ...) do values[i] = tostring(select(i, ...)) end
            messages[#messages + 1] = table.concat(values, " ")
        end,
        After = function(_, fn) timers[#timers + 1] = fn end,
        BuildManualIdentity = function(map, x, y) return {map = map, x = x, y = y} end,
        BuildRouteMeta = function(_, meta) return meta end,
        RequestManualRoute = function(map, x, y, title, meta)
            calls[#calls + 1] = {map = map, x = x, y = y, title = title, meta = meta}; return true
        end}
    _G.AzerothWaypointNS = ns
    assert(loadfile("core/routing_backends.lua"))()
    assert(loadfile("core/service_search.lua"))()
    assert(loadfile("interface/commands_settings.lua"))()
    assert(loadfile("integrations/service_zygor.lua"))()
    assert(loadfile("interface/commands_search.lua"))()
    return {NS = ns, search = ns.Internal.ServiceSearch, command = ns.Internal.Interface.commands.handleSearch,
        z = z, ww = ww, worker = worker, callbacks = nativeCallbacks, calls = calls, messages = messages,
        timers = timers, order = order}
end
