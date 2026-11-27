-- ============================================================
-- Questie and QuestieDB integration
-- ============================================================
--
-- Supplies Questie quest and entity data and identifies the quest behind a
-- clicked pin.

local NS = _G.AzerothWaypointNS
local Data = { label = "QuestieDB", counters = { queries = 0, failed = 0 } }
NS.Internal.QuestieData = Data
local questContext
local hooked = setmetatable({}, { __mode = "k" })
local entityKinds = { Npc = true, Object = true, Item = true }
local roleKinds = { "Npc", "Object", "Item" }

local function Call(owner, name, ...)
    if type(owner) ~= "table" or type(owner[name]) ~= "function" then return nil end
    local ok, a, b, c = pcall(owner[name], ...)
    if ok then return a, b, c end
    Data.counters.failed = Data.counters.failed + 1
end
local function ID(value)
    return type(value) == "number" and not (issecretvalue and issecretvalue(value))
        and value > 0 and value < math.huge and value % 1 == 0 and value or nil
end
local function Database()
    if not NS.IsWoWForever() or not NS.IsAddonLoaded("QuestieDB") then return end
    local db = rawget(_G, "LibQuestieDB")
    if Call(db, "RequireContract", 4) == true and type(db.Quest) == "table" then return db end
end
local function Questie()
    if not NS.IsWoWForever() or not NS.IsAddonLoaded("Questie") then return end
    local q = rawget(_G, "Questie")
    if q and q.API and q.API.isReady == true then return q end
end
function Data.GetLoadedModule(name)
    local loader = rawget(_G, "QuestieLoader")
    -- ImportModule creates empty modules. Never manufacture readiness.
    local entry = loader and loader._modules and loader._modules[name]
    return type(entry) == "table" and entry or nil
end

function Data.GetStatus()
    return {
        questieLoaded = NS.IsAddonLoaded("Questie"),
        questieReady = Questie() ~= nil,
        databaseLoaded = NS.IsAddonLoaded("QuestieDB"),
        databaseReady = Database() ~= nil
    }
end

function Data.GetQuestName(id)
    local db = Database()
    if not db or not ID(id) then return end
    Data.counters.queries = Data.counters.queries + 1
    local name = Call(db.Quest, "Get", id, "name")
    return type(name) == "string" and name ~= "" and name or nil
end

function Data.GetRoleEntity(id, action)
    local db = Database()
    if not db or not ID(id) then return end
    Data.counters.queries = Data.counters.queries + 1
    local kind, entity
    if action == "accept" or action == "turnin" then
        local owners = Call(db.Quest, "Get", id, action == "accept" and "startedBy" or "finishedBy")
        if type(owners) == "table" then
            local count, seen = 0, {}
            for index, category in ipairs(roleKinds) do
                local values = owners[index]
                for _, value in ipairs(type(values) == "table" and values or {}) do
                    local key = ID(value) and category .. value
                    if key and not seen[key] then
                        seen[key] = true
                        count, kind, entity = count + 1, category, value
                    end
                end
            end
            if count > 1 then return nil, nil, "ambiguous" end
            if count ~= 1 then kind, entity = nil, nil end
        end
    end
    return kind, entity
end

function Data.GetEntityName(kind, entity)
    local db = Database()
    if not db or not ID(entity) or not entityKinds[kind] then return end
    Data.counters.queries = Data.counters.queries + 1
    local name = Call(db[kind], "Get", entity, "name")
    if type(name) ~= "string" or name == "" then return end
    return name
end

NS.Internal.QuestData.Register("questie", Data)

-- ============================================================
-- Pin destinations and click context
-- ============================================================

function Data.ResolveDestination(id)
    if not Questie() or not ID(id) then return end
    local db, distances, zones = Data.GetLoadedModule("QuestieDB"), Data.GetLoadedModule("DistanceUtils"),
        Data.GetLoadedModule("ZoneDB")
    local q = Call(db, "GetQuest", db, id)
    local spawn, area
    if q then spawn, area = Call(distances, "GetNearestSpawnForQuest", q) end
    if type(spawn) ~= "table" or not ID(area) then return end
    local map = Call(zones, "GetUiMapIdByAreaId", zones, area)
    local x, y = spawn[1], spawn[2]
    if ID(map) and type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
        return map, x / 100, y / 100, "questie_live_destination"
    end
end

local function PinContext(map, x, y)
    if questContext then return questContext end
    if type(GetMouseFoci) ~= "function" then return end
    for _, frame in ipairs(GetMouseFoci()) do
        ---@cast frame any
        local d = frame.data
        if type(d) == "table" and type(d.QuestData) == "table" and ID(d.Id) and d.QuestData.Id == d.Id
            and frame.UiMapID == map and type(frame.x) == "number" and type(frame.y) == "number"
            and math.abs(frame.x / 100 - x) < 0.000001 and math.abs(frame.y / 100 - y) < 0.000001 then
            local kinds = { monster = "Npc", object = "Object", item = "Item" }
            local objective = d.ObjectiveData
            local entityID = objective and ID(objective.Id)
            if not entityID and d.Type ~= "item" then entityID = ID(d.ObjectiveTargetId) end
            return {
                questID = d.Id,
                objectiveIndex = ID(d.ObjectiveIndex),
                entityKind = kinds[d.Type],
                entityID = entityID,
                objectiveType = objective and objective.Type,
                action = d.Type == "available" and "accept" or d.Type == "complete" and "turnin" or nil
            }
        end
    end
end
NS.RegisterExternalWaypointSource("questie", {
    displayName = "Questie",
    aliases = { "Questie" },
    stackMatches = { "interface\\addons\\questie\\" },
    iconKey = "questie",
    resolveMetadata = function(map, x, y)
        if not Questie() then return end
        return PinContext(map, x, y)
    end,
})

local Request = NS.Internal.QuestData.RequestRefresh
local function Install()
    if not NS.IsWoWForever() then return end
    local q = rawget(_G, "Questie")
    local api = q and q.API
    if api and not hooked[api] then
        hooked[api] = true
        if type(api.RegisterOnReady) == "function" then
            pcall(api.RegisterOnReady, function()
                Install(); Request()
            end)
        end
        if type(api.RegisterForQuestUpdates) == "function" then pcall(api.RegisterForQuestUpdates, Request) end
    end
    if Questie() then
        local tracker = Data.GetLoadedModule("TrackerUtils")
        if tracker and type(tracker.SetQuestTomTomTarget) == "function" and not hooked[tracker] then
            hooked[tracker] = true
            local original = tracker.SetQuestTomTomTarget
            tracker.SetQuestTomTomTarget = function(id, expected)
                local previous = questContext
                questContext = ID(id) and { questID = id } or nil
                local ok, result = pcall(original, id, expected)
                questContext = previous
                if not ok then error(result, 0) end
                return result
            end
        end
    end
    local db = Database()
    if db and not hooked[db] then
        hooked[db] = true
        if db.l10n and type(db.l10n.onLocaleChanged) == "table" then
            table.insert(db.l10n.onLocaleChanged, function() Request() end)
        end
        for _, key in ipairs({ "ApplyRegisteredCorrections", "SetCorrection", "RegisterRuntimeCorrection" }) do
            if type(db[key]) == "function" then hooksecurefunc(db, key, function() Request() end) end
        end
    end
end
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED"); watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon ~= "Questie" and addon ~= "QuestieDB" and addon ~= "AzerothWaypoint" then return end
    Install(); Request()
end)
