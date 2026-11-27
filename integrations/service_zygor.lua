-- ============================================================
-- Zygor nearby services
-- ============================================================
--
-- Connects Zygor's WhoWhere service search to AWP and adopts the resulting
-- waypoint.

local NS = _G.AzerothWaypointNS
local Search = NS.Internal.ServiceSearch
local runtime = { whoWhereSearchAdoptionSerial = 0, vendorFallbackToken = 0 }
local managedSearch
local serviceTypes = {
    auctioneer = "Auctioneer",
    banker = "Banker",
    barber = "Barber",
    flightmaster = "Flightmaster",
    innkeeper = "Innkeeper",
    repair = "Repair",
    riding = "TrainerRiding",
    stable = "Stable Master",
    transmogrifier = "Transmogrifier",
    vendor = "Vendor",
    voidstorage = "Void Storage",
    poisons = "Poisons",
    reagents = "Reagents",
    arrows = "Arrows",
    bullets = "Bullets",
    pettrainer = "ClassHunter pets"
}
local function NativeType(query)
    if query.service == "trainer" or query.service == "workshop" then
        local profession = Search.Professions[query.profession]
        if profession then return "Trainer" .. profession .. (query.service == "workshop" and "Workshop" or "") end
    elseif query.service == "class" then
        local class = Search.Classes[query.classToken]
        if class then return "Class" .. class end
    else
        return serviceTypes[query.service]
    end
end

local WHOWHERE_SEARCH_SOURCE_ADDON = "Zygor"
local WHOWHERE_SEARCH_QUEUE_SOURCE_TYPE = "transient_source"

-- ============================================================
-- WhoWhere search hint keys
-- ============================================================

local WHOWHERE_HINT_KEYS = {
    ["Auctioneer"]                    = "npc_auctioneer",
    ["Banker"]                        = "npc_banker",
    ["Barber"]                        = "npc_barber",
    ["Flightmaster"]                  = "npc_flightmaster",
    ["Innkeeper"]                     = "npc_innkeeper",
    ["Repair"]                        = "npc_repair",
    ["TrainerRiding"]                 = "npc_trainer_riding",
    ["Stable Master"]                 = "npc_stable_master",
    ["Transmogrifier"]                = "npc_transmogrifier",
    ["Vendor"]                        = "npc_vendor",
    ["Void Storage"]                  = "npc_void_storage",
    ["TrainerAlchemy"]                = "npc_trainer_alchemy",
    ["TrainerArchaeology"]            = "npc_trainer_archaeology",
    ["TrainerBandages"]               = "npc_trainer_bandages",
    ["TrainerBlacksmithing"]          = "npc_trainer_blacksmithing",
    ["TrainerCooking"]                = "npc_trainer_cooking",
    ["TrainerEnchanting"]             = "npc_trainer_enchanting",
    ["TrainerEngineering"]            = "npc_trainer_engineering",
    ["TrainerFirst Aid"]              = "npc_trainer_first_aid",
    ["TrainerFishing"]                = "npc_trainer_fishing",
    ["TrainerHerbalism"]              = "npc_trainer_herbalism",
    ["TrainerInscription"]            = "npc_trainer_inscription",
    ["TrainerJewelcrafting"]          = "npc_trainer_jewelcrafting",
    ["TrainerLeatherworking"]         = "npc_trainer_leatherworking",
    ["TrainerMining"]                 = "npc_trainer_mining",
    ["TrainerSkinning"]               = "npc_trainer_skinning",
    ["TrainerTailoring"]              = "npc_trainer_tailoring",
    ["TrainerAlchemyWorkshop"]        = "npc_workshop_alchemy",
    ["TrainerArchaeologyWorkshop"]    = "npc_workshop_archaeology",
    ["TrainerBandagesWorkshop"]       = "npc_workshop_bandages",
    ["TrainerBlacksmithingWorkshop"]  = "npc_workshop_blacksmithing",
    ["TrainerCookingWorkshop"]        = "npc_workshop_cooking",
    ["TrainerEnchantingWorkshop"]     = "npc_workshop_enchanting",
    ["TrainerEngineeringWorkshop"]    = "npc_workshop_engineering",
    ["TrainerFirst AidWorkshop"]      = "npc_workshop_first_aid",
    ["TrainerFishingWorkshop"]        = "npc_workshop_fishing",
    ["TrainerHerbalismWorkshop"]      = "npc_workshop_herbalism",
    ["TrainerInscriptionWorkshop"]    = "npc_workshop_inscription",
    ["TrainerJewelcraftingWorkshop"]  = "npc_workshop_jewelcrafting",
    ["TrainerLeatherworkingWorkshop"] = "npc_workshop_leatherworking",
    ["TrainerMiningWorkshop"]         = "npc_workshop_mining",
    ["TrainerSkinningWorkshop"]       = "npc_workshop_skinning",
    ["TrainerTailoringWorkshop"]      = "npc_workshop_tailoring",
}

-- ============================================================
-- WhoWhere hook machinery
-- ============================================================

local function SetWhoWherePendingSearchKind(WW, kind)
    if type(WW) ~= "table" then
        return
    end

    WW.awpPendingSearchKind = type(kind) == "string" and kind or nil
end

local function TagCurrentWhoWhereWaypoint(WW)
    if type(WW) ~= "table" then
        return
    end

    local currentWay = WW.CurrentWay
    local pendingKind = type(WW.awpPendingSearchKind) == "string" and WW.awpPendingSearchKind or nil
    WW.awpPendingSearchKind = nil

    if type(currentWay) ~= "table" or currentWay.type ~= "manual" or pendingKind == nil then
        return
    end

    currentWay.searchKind = pendingKind
    return currentWay, pendingKind
end

local function ResolveWhoWhereWaypointTitle(waypoint, fallback)
    if type(waypoint) ~= "table" then
        return fallback or "Search result"
    end

    if type(waypoint.GetArrowTitle) == "function" then
        local ok, title = pcall(waypoint.GetArrowTitle, waypoint)
        if ok and type(title) == "string" and title ~= "" then
            return title
        end
    end
    if type(waypoint.GetTitle) == "function" then
        local ok, title = pcall(waypoint.GetTitle, waypoint)
        if ok and type(title) == "string" and title ~= "" then
            return title
        end
    end
    if type(waypoint.title) == "string" and waypoint.title ~= "" then
        return waypoint.title
    end

    return fallback or "Search result"
end

local function BuildWhoWhereSearchMeta(mapID, x, y, searchKind)
    if type(NS.BuildManualIdentity) ~= "function" or type(NS.BuildRouteMeta) ~= "function" then
        return {
            sourceAddon = WHOWHERE_SEARCH_SOURCE_ADDON,
            searchKind = searchKind,
            queueSourceType = WHOWHERE_SEARCH_QUEUE_SOURCE_TYPE,
        }
    end

    local identity = NS.BuildManualIdentity(mapID, x, y)
    return NS.BuildRouteMeta(identity, {
        sourceAddon = WHOWHERE_SEARCH_SOURCE_ADDON,
        searchKind = searchKind,
        queueSourceType = WHOWHERE_SEARCH_QUEUE_SOURCE_TYPE,
    })
end

local function AdoptWhoWhereSearchWaypoint(WW, waypoint, searchKind, serial)
    if serial ~= runtime.whoWhereSearchAdoptionSerial then
        return false
    end
    if type(WW) ~= "table" then
        return false
    end

    waypoint = type(waypoint) == "table" and waypoint or WW.CurrentWay
    searchKind = type(searchKind) == "string" and searchKind
        or type(waypoint) == "table" and waypoint.searchKind
        or nil
    if type(waypoint) ~= "table" or type(searchKind) ~= "string" or searchKind == "" then
        return false
    end

    local mapID, x, y
    if type(NS.ReadWaypointCoords) == "function" then
        mapID, x, y = NS.ReadWaypointCoords(waypoint)
    else
        mapID, x, y = waypoint.map or waypoint.mapid or waypoint.mapID or waypoint.m, waypoint.x, waypoint.y
    end
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return false
    end

    local title = ResolveWhoWhereWaypointTitle(waypoint, "Search result")
    local meta = BuildWhoWhereSearchMeta(mapID, x, y, searchKind)
    if type(NS.RequestManualRoute) == "function" then
        return NS.RequestManualRoute(mapID, x, y, title, meta) == true
    end
    if type(NS.RouteViaBackend) == "function" then
        return NS.RouteViaBackend(mapID, x, y, title, meta, { authority = "manual" }) == true
    end
    return false
end

local function ScheduleWhoWhereSearchAdoption(WW, waypoint, searchKind)
    if type(WW) ~= "table" or type(waypoint) ~= "table" or type(searchKind) ~= "string" then
        return
    end

    runtime.whoWhereSearchAdoptionSerial = (tonumber(runtime.whoWhereSearchAdoptionSerial) or 0) + 1
    local serial = runtime.whoWhereSearchAdoptionSerial
    local revision = Search.Revision()
    local function adopt()
        if revision ~= Search.Revision() then return end
        AdoptWhoWhereSearchWaypoint(WW, waypoint, searchKind, serial)
    end

    if type(NS.After) == "function" then
        NS.After(0, adopt)
    elseif type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(0, adopt)
    else
        adopt()
    end
end

local function getWhoWhere()
    local Z = NS.ZGV()
    local WW = Z and Z.WhoWhere
    if not Z or not WW then return end

    if type(WW.FindNPC) ~= "function" or type(WW.FindMailbox) ~= "function" then
        return
    end

    if not runtime.whoWhereFallbackHooked then
        NS.HookZygorWhoWhereFallbacks()
    end

    if Z.startups ~= nil or not Z.NPCData or not Z.MailboxData or not WW.WorkerFrame then
        return
    end

    return Z, WW
end

local function triggerVendorFallback(WW)
    runtime.pendingVendorFallback = nil
    NS.Msg("Vendor search did not resolve a vendor waypoint. Falling back to nearest repair.")
    return WW:FindNPC("Repair")
end

function NS.HookZygorWhoWhereFallbacks()
    if runtime.whoWhereFallbackHooked then return end

    local Z = NS.ZGV()
    local WW = Z and Z.WhoWhere
    if not Z or not WW then return end

    if type(WW.FindNPC) ~= "function"
        or type(WW.FindMailbox) ~= "function"
        or type(WW.SetWaypoint) ~= "function"
        or type(WW.PathFoundHandler) ~= "function"
    then
        return
    end

    local originalFindNPC = WW.FindNPC
    local originalPathFoundHandler = WW.PathFoundHandler
    local originalFindMailbox = WW.FindMailbox
    local originalSetWaypoint = WW.SetWaypoint
    local originalFindSmart = WW.FindNPC_Smart
    local originalFindDirect = WW.FindNPC_Direct

    WW.SetWaypoint = function(self, ...)
        local job = managedSearch
        local thread = coroutine.running()
        if job and job.ww == self and job.thread and thread == job.thread then
            job.capture(...)
            return
        end
        if thread and thread == self.awpNativeSearchThread and self.awpNativeSearchRevision ~= Search.Revision() then return end
        local result = originalSetWaypoint(self, ...)
        local waypoint, searchKind = TagCurrentWhoWhereWaypoint(self)
        ScheduleWhoWhereSearchAdoption(self, waypoint, searchKind)
        return result
    end

    WW.FindMailbox = function(self, ...)
        Search.Cancel()
        SetWhoWherePendingSearchKind(self, "npc_mailbox")
        local result = originalFindMailbox(self, ...)
        self.awpNativeSearchThread, self.awpNativeSearchRevision = self.thread, Search.Revision()
        return result
    end

    WW.FindNPC = function(self, typ, m, f, x, y)
        Search.Cancel()
        SetWhoWherePendingSearchKind(self, WHOWHERE_HINT_KEYS[typ])
        if typ ~= "Vendor" then
            runtime.pendingVendorFallback = nil
            return originalFindNPC(self, typ, m, f, x, y)
        end

        if not Z.db.profile.pathfinding or type(self.FindNPC_Smart) ~= "function" then
            runtime.pendingVendorFallback = nil
            return originalFindNPC(self, typ, m, f, x, y)
        end

        self.debuglast = { typ, m, f, x, y }
        self.debugtrace = debugstack()

        runtime.vendorFallbackToken = runtime.vendorFallbackToken + 1
        local token = runtime.vendorFallbackToken
        runtime.pendingVendorFallback = {
            token = token,
            originalWay = self.CurrentWay,
        }

        local searchStarted = self:FindNPC_Smart(typ, nil, function(searchState, path, ext, reason)
            local pending = runtime.pendingVendorFallback
            if not pending or pending.token ~= token then
                return
            end

            if searchState == "progress" then
                return
            end

            runtime.pendingVendorFallback = nil

            if searchState == "success" then
                return originalPathFoundHandler(searchState, path, ext, reason)
            end

            if searchState == "failure" then
                return triggerVendorFallback(self)
            end

            SetWhoWherePendingSearchKind(self, nil)
            return originalPathFoundHandler(searchState, path, ext, reason)
        end)

        if searchStarted == false then
            return triggerVendorFallback(self)
        end
    end

    -- Native searches remain native. Their asynchronous callbacks are scoped to
    -- the navigation intent that launched them, just like shared slash searches.
    if originalFindSmart then
        WW.FindNPC_Smart = function(self, typ, goal, handler)
            if not (managedSearch and managedSearch.starting) then Search.Cancel() end
            local revision = Search.Revision()
            local callback = handler or originalPathFoundHandler
            return originalFindSmart(self, typ, goal, function(...)
                if revision == Search.Revision() then return callback(...) end
            end)
        end
    end
    if originalFindDirect then
        WW.FindNPC_Direct = function(self, ...)
            local owned = managedSearch and managedSearch.starting
            if not owned then Search.Cancel() end
            local result = originalFindDirect(self, ...)
            if not owned then self.awpNativeSearchThread, self.awpNativeSearchRevision = self.thread, Search.Revision() end
            return result
        end
    end
    -- The shared adapter uses the native mailbox worker without issuing a
    -- second navigation intent through the public native-menu entry point.
    WW.awpFindMailbox = originalFindMailbox

    runtime.whoWhereFallbackHooked = true
end

local function FindZygorType(query, complete, selectedType)
    local Z, WW = getWhoWhere()
    if not Z or not WW then return nil end
    local typ = selectedType or NativeType(query)
    if not typ and query.service ~= "mailbox" then return nil end
    if typ and (typ == "Flightmaster" or typ == "Innkeeper") and WW.LeechLibRover then WW:LeechLibRover() end
    -- A new search replaces WhoWhere's previous direct worker and vendor retry.
    runtime.pendingVendorFallback = nil
    WW.awpPendingSearchKind = nil
    if WW.thread then
        WW.thread = nil; WW.WorkerFrame:SetScript("OnUpdate", nil)
    end
    local job = { ww = WW, starting = true, alive = true }
    managedSearch = job
    local kind = query.service == "mailbox" and "npc_mailbox" or WHOWHERE_HINT_KEYS[typ] or "gossip_poi"
    local function point(map, x, y, identity)
        local title = type(identity) == "string" and tonumber(identity) == nil and identity or nil
        if not title and Z.Localizers and Z.Localizers.GetTranslatedNPC then
            title = Z.Localizers:GetTranslatedNPC(tonumber(identity) or identity)
        end
        return {
            mapID = map,
            x = x,
            y = y,
            title = title or query.label,
            meta = { sourceAddon = "Zygor", searchKind = kind }
        }
    end
    local function cancel()
        job.alive = false
        if managedSearch == job then managedSearch = nil end
        if job.thread and WW.thread == job.thread then WW.thread = nil end
        if job.update and WW.WorkerFrame:GetScript("OnUpdate") == job.update then
            WW.WorkerFrame:SetScript("OnUpdate", nil)
        end
    end
    local function finish(result)
        if not job.alive then return end
        cancel()
        complete(result)
    end
    local smart = typ and typ ~= "Flightmaster" and typ ~= "Innkeeper" and Z.db.profile.pathfinding
    if smart then
        if not WW.FindNPC_Smart or not Z.NPCData.raw or type(Z.NPCData.raw[typ]) ~= "string" then
            cancel(); return nil
        end
        local ok, started = pcall(WW.FindNPC_Smart, WW, typ, nil, function(status, path)
            if not job.alive or status == "progress" then return end
            local destination
            if status == "success" then
                for _, node in ipairs(path or {}) do
                    if node.type == "end" then destination = point(node.m, node.x, node.y, node.title) end
                end
            end
            finish(destination)
        end)
        job.starting = false
        if not ok or started == false then
            cancel(); return nil
        end
    else
        if typ and (not WW.FindNPC_Direct or not Z.NPCData.raw or type(Z.NPCData.raw[typ]) ~= "string") then
            cancel(); return nil
        end
        job.capture = function(map, x, y, identity) job.point = point(map, x, y, identity) end
        local ok = pcall(function()
            if typ then WW:FindNPC_Direct(typ) else WW:awpFindMailbox() end
        end)
        job.starting = false
        if not ok or not WW.thread then
            cancel(); return nil
        end
        job.thread = WW.thread
        local step = WW.WorkerFrame:GetScript("OnUpdate")
        if not step then
            cancel(); return nil
        end
        job.update = function(...)
            if not job.alive then return end
            if WW.thread ~= job.thread then
                finish(nil); return
            end
            local stepped = pcall(step, ...)
            if not stepped or WW.thread == nil or coroutine.status(job.thread) == "dead" then finish(job.point) end
        end
        WW.WorkerFrame:SetScript("OnUpdate", job.update)
    end
    return "pending", cancel
end

local function FindZygor(query, complete)
    if query.service ~= "vendor" then return FindZygorType(query, complete) end
    -- Repair merchants can buy items too. Retain WhoWhere's vendor/repair
    -- preference without reporting a pending vendor search as a failure.
    local alive, generation, cancel = true, 0, nil
    local function run(typ)
        generation = generation + 1
        local token = generation
        local function receive(point)
            if not alive or generation ~= token then return end
            if not point and typ == "Vendor" then return run("Repair") end
            alive = false
            complete(point)
        end
        local result, stop = FindZygorType(query, receive, typ)
        if not alive or token ~= generation then return end
        cancel = stop
        if result ~= "pending" then receive(result) end
    end
    run("Vendor")
    return "pending", function()
        alive = false; if cancel then cancel() end
    end
end

local choices, observed, capabilities = {}, {}, {}
for service in pairs(serviceTypes) do choices[#choices + 1] = Search.Query(service) end
choices[#choices + 1] = Search.Query("mailbox")
for profession in pairs(Search.Professions) do
    choices[#choices + 1] = Search.Query("trainer", profession)
    choices[#choices + 1] = Search.Query("workshop", profession)
end
for class in pairs(Search.Classes) do choices[#choices + 1] = Search.Query("class", class) end
local function GetCapabilities()
    local Z = NS.ZGV()
    local WW = Z and Z.WhoWhere
    local raw = Z and Z.NPCData and Z.NPCData.raw
    local ready = Z and WW and not Z.startups and raw and Z.MailboxData and WW.WorkerFrame
        and type(WW.FindNPC) == "function" and type(WW.FindMailbox) == "function"
    local changed = observed.ready ~= ready or observed.raw ~= raw or observed.mail ~= (Z and Z.MailboxData)
    observed.ready, observed.raw, observed.mail = ready, raw, Z and Z.MailboxData
    local forever, class = NS.IsWoWForever(), Search.PlayerClass()
    if observed.forever ~= forever or observed.class ~= class then changed = true end
    observed.forever, observed.class = forever, class
    for i, query in ipairs(choices) do
        local typ = NativeType(query)
        local value = ready and (query.service == "mailbox" and Z.MailboxData or raw[typ]) or nil
        if observed[i] ~= value then observed[i], changed = value, true end
    end
    if not changed then return capabilities end
    capabilities = {}
    if not ready then return capabilities end
    for i, query in ipairs(choices) do
        local value = observed[i]
        local allowed = (query.service ~= "class" and query.service ~= "pettrainer" or forever)
            and (query.service ~= "workshop" and query.service ~= "riding" or not forever)
            and (query.service ~= "poisons" or forever and class == "ROGUE")
        if allowed and (query.service == "mailbox" or type(value) == "string" and value:find("%d+=")) then
            capabilities[#capabilities + 1] = query
        end
    end
    return capabilities
end
Search.Register("zygor", { label = "Zygor", Find = FindZygor, GetCapabilities = GetCapabilities })
