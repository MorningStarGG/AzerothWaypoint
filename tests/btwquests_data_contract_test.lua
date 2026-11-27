local native = dofile("tests/guide_parity/native_function.lua")
local path = dofile("tests/native_path.lua")
for _, client in ipairs({ "retail", "forever" }) do
    local f = dofile("tests/daylight_fixture.lua")
    f.flavor = client
    local NS = AzerothWaypointNS
    NS.IsAddonLoaded = function(name) return name == "BtWQuests" end
    NS.RegisterExternalWaypointSource = function() end
    local db, mixin = { quest = {}, npc = {}, object = {} }, {}
    local env = { Database = db, DataMixin = mixin, format = string.format }
    local file = "BtWQuests/BtWQuestsDatabase.lua"
    for _, method in ipairs({ "Database:GetData", "Database:GetQuestByID", "Database:GetNPCByID",
        "Database:GetObjectByID", "Database:EvalText", "DataMixin:GetName" }) do
        native(client, file, method, env)
    end
    local function Capture(kind, records)
        for id, record in pairs(records) do
            record.database = db
            setmetatable(record, { __index = mixin })
            db[kind][id] = record
        end
    end
    db.AddQuestsTable = function(_, records) Capture("quest", records) end
    db.AddNPCsTable = function(_, records) Capture("npc", records) end
    db.AddObjectsTable = function(_, records) Capture("object", records) end
    local pack = client == "forever" and "BtWQuestsClassic" or "BtWQuestsMidnight"
    for _, name in ipairs({ "Quests", "NPCs", "Objects" }) do
        local chunk = assert(loadfile(path(client, pack .. "/Database/" .. name .. ".lua")))
        setfenv(chunk, setmetatable({ BtWQuestsDatabase = db }, { __index = _G }))()
    end
    _G.BtWQuestsDatabase = db
    -- Any accidental use of a native loader, click, graph or UI API fails.
    db.LoadQuest = function() error("Enrichment loaded a content pack") end
    db.CreateItem = function() error("Enrichment mutated the native source") end
    C_QuestLog = { IsOnQuest = function() return false end, ReadyForTurnIn = function() return false end }
    C_TaskQuest = nil
    assert(loadfile("core/quest_data.lua"))()
    assert(loadfile("core/quest_text.lua"))()
    assert(loadfile("integrations/btwquests.lua"))()
    local id = client == "forever" and 775 or 86509
    local npc = client == "forever" and 2994 or 240691
    local name = client == "forever" and "Journey into Thunder Bluff" or "Friend or Fiend"
    local actor = client == "forever" and "Ancestral Spirit" or "Decimus"
    local owner = { questContext = { questID = id, action = "accept" } }
    local view = NS.ResolveQuestPresentation(id, "Exact selected point", owner)
    assert(view.title == "Accept '" .. name .. "'" and view.subtext == "Talk to " .. actor)
    assert(view.entityKind == "Npc" and view.entityID == npc and view.provenance == "BtWQuests")
    assert(db.quest[id].source.parent == nil and db.quest[id].source.index == nil)
    C_QuestLog.IsOnQuest, C_QuestLog.ReadyForTurnIn = function() return true end, function() return true end
    NS.InvalidateQuestPresentation(id)
    assert(NS.ResolveQuestPresentation(id, "Exact selected point", owner).subtext == "Ready to turn in",
        "Installed acceptance source was reused as a finisher")
    if client == "forever" then
        owner.questContext = { questID = 775, action = "turnin", entityKind = "Npc", entityID = 3057 }
        assert(NS.ResolveQuestPresentation(id, "Exact selected point", owner).subtext == "Talk to Cairne Bloodhoof")
    end
    assert(NS.Internal.QuestData.GetQuestName(999999999) == nil)
end
print("Installed Retail and Forever BtWQuests getters, data packs and role boundaries passed")
