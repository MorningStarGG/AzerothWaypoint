local setup = assert(loadfile("tests/daylight_fixture.lua"))
for _, client in ipairs({ "retail", "forever" }) do
    local f = setup()
    f.flavor = client
    local NS, loaded = AzerothWaypointNS, { BtWQuests = true }
    NS.IsAddonLoaded = function(key) return loaded[key] == true end
    NS.IsRoutingEnabled = function() return true end
    local active, ready, clientName = false, false, nil
    C_QuestLog = { IsOnQuest = function() return active end, ReadyForTurnIn = function() return ready end,
        IsComplete = function() return ready end, GetTitleForQuestID = function() return clientName end,
        GetQuestObjectives = function() return {} end }
    C_TaskQuest = nil
    local queries, hooks, updates, manualUpdates = 0, 0, 0, 0
    hooksecurefunc = function(owner, key, hook)
        hooks = hooks + 1
        local original = owner[key]
        owner[key] = function(...) local result = original(...); hook(...); return result end
    end
    assert(loadfile("core/scheduling.lua"))()
    assert(loadfile("core/quest_data.lua"))()
    assert(loadfile("core/quest_text.lua"))()
    assert(loadfile("integrations/external_waypoint_sources.lua"))()
    assert(loadfile("integrations/guides/quest_selection.lua"))()
    local data, selection = NS.Internal.QuestData, NS.Internal.GuideQuestSelection
    NS.TickUpdate = function() updates = updates + 1 end
    NS.ScheduleActiveQuestBackedManualRefresh = function() manualUpdates = manualUpdates + 1 end
    local function Record(name, source)
        return { source = source, GetName = function() queries = queries + 1; return name end }
    end
    local quests, npcs, objects = {}, {}, {}
    BtWQuestsDatabase = {
        GetQuestByID = function(_, id) queries = queries + 1; return quests[id] end,
        GetNPCByID = function(_, id) queries = queries + 1; return npcs[id] end,
        GetObjectByID = function(_, id) queries = queries + 1; return objects[id] end,
        IsItemValidForCharacter = function(_, source) return source.restrictions == true end,
        AddData = function(_, kind, id, value)
            local target = kind == "quest" and quests or kind == "npc" and npcs or objects
            target[id] = value
        end,
        AddDataTable = function(_database, _kind, _items) end,
        UpdateDataTable = function(_database, _kind, _items) end,
    }
    BtWQuestsCharacters = { GetPlayer = function() return {} end }
    assert(loadfile("integrations/btwquests.lua"))()
    assert(hooks == 3)
    assert(NS.ResolveQuestTitle(775) == nil)
    local count = queries
    for _ = 1, 100 do assert(NS.ResolveQuestTitle(775) == nil) end
    assert(queries == count, "Negative title lookup was not cached")
    quests[775] = Record("Journey into Thunder Bluff", { type = "npc", id = 2994 })
    npcs[2994], npcs[3057], npcs[42] = Record("Ancestral Spirit"), Record("Cairne Bloodhoof"), Record("Wolf")
    objects[51] = Record("A Shrine")
    f.Fire("ADDON_LOADED", "BtWQuestsClassic")
    f.Fire("ADDON_LOADED", "BtWQuestsMidnight")
    assert(#f.pending == 1, "Pack loads did not coalesce")
    f.Flush()
    assert(hooks == 3 and updates == 1 and manualUpdates == 1)
    local owner = { questContext = { action = "accept" } }
    local s = NS.ResolveQuestPresentation(775, "Chosen point", owner)
    assert(s.title == "Accept 'Journey into Thunder Bluff'" and s.subtext == "Talk to Ancestral Spirit")
    assert(s.provenance == "BtWQuests" and quests[775].source.parent == nil)
    count = queries
    for _ = 1, 100 do assert(NS.ResolveQuestPresentation(775, "Chosen point", owner) == s) end
    assert(queries == count and #f.pending == 0, "Unchanged reads touched the database or scheduled work")
    owner.questContext.entityKind, owner.questContext.entityID = "Object", 51
    assert(NS.ResolveQuestPresentation(775, "Chosen point", owner).subtext == "Interact with A Shrine",
        "In-place entity changes reused the old presentation")
    owner.questContext.entityKind, owner.questContext.entityID = nil, nil
    active, ready = true, true
    NS.InvalidateQuestPresentation(775)
    s = NS.ResolveQuestPresentation(775, "Chosen point", owner)
    assert(s.subtext == "Ready to turn in" and not s.entityID, "Starter became a finisher")
    owner.questContext = { entityKind = "Npc", entityID = 42, objectiveIndex = 1, objectiveType = "monster" }
    s = NS.ResolveQuestPresentation(775, "Chosen point", owner)
    assert(s.subtext == "Ready to turn in" and s.title == "Turn in 'Journey into Thunder Bluff'",
        "Stale objective became a turn-in recipient or kill instruction")
    owner.questContext = { questID = 775, action = "turnin", entityKind = "Npc", entityID = 3057 }
    assert(NS.ResolveQuestPresentation(775, "Chosen point", owner).subtext == "Talk to Cairne Bloodhoof")
    owner.questContext.questID = 999
    assert(NS.ResolveQuestPresentation(775, "Chosen point", owner).subtext == "Ready to turn in")
    owner.questContext.questID = "invalid"
    assert(NS.ResolveQuestPresentation(775, "Chosen point", owner).subtext == "Ready to turn in")
    owner.questContext = {}
    GetQuestID = function() return 775 end
    Enum = { PlayerInteractionType = { QuestGiver = 4 } }
    local interacting, guid = true, "Creature-0-1-2-3-3057-0000"
    C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function() return interacting end }
    UnitGUID = function(unit) assert(unit == "npc"); return guid end
    UnitName = function() return "Live Cairne" end
    selection.OnDialogEvent("QUEST_COMPLETE")
    assert(NS.ResolveQuestPresentation(775, "Chosen point", owner).subtext == "Talk to Cairne Bloodhoof")
    interacting = false
    selection.OnDialogEvent("QUEST_COMPLETE")
    assert(NS.ResolveQuestPresentation(775, "Chosen point", owner).subtext == "Ready to turn in", "Remote page inferred an NPC")
    interacting, guid = true, "Player-1-3057"
    selection.OnDialogEvent("QUEST_COMPLETE")
    assert(NS.ResolveQuestPresentation(775, "Chosen point", owner).subtext == "Ready to turn in")
    guid = "Creature-0-1-2-3-9999-0000"
    selection.OnDialogEvent("QUEST_COMPLETE")
    assert(NS.ResolveQuestPresentation(775, "Chosen point", owner).subtext == "Talk to Live Cairne")
    selection.OnDialogEvent("QUEST_FINISHED")
    assert(NS.ResolveQuestPresentation(775, "Chosen point", owner).subtext == "Ready to turn in", "Dialog actor was retained")

    loaded.QuestieDB = true
    local ambiguous, noOwner = false, false
    ---@type string?
    local qtName = "Questie Quest"
    ---@type string?
    local qtEntityName = "Questie Cairne"
    LibQuestieDB = { RequireContract = function() return true end,
        Quest = { Get = function(_, field)
            if field == "name" then return qtName end
            if noOwner then return end
            return { ambiguous and { 3057, 2994 } or { 3057 } }
        end }, Npc = { Get = function() return qtEntityName end } }
    assert(loadfile("integrations/questie.lua"))()
    s = NS.ResolveQuestPresentation(775, "Chosen point", owner)
    assert(s.title == (client == "forever" and "Turn in 'Questie Quest'" or "Turn in 'Journey into Thunder Bluff'"))
    assert(s.subtext == (client == "forever" and "Talk to Questie Cairne" or "Ready to turn in"))
    qtName, qtEntityName = nil, nil
    NS.InvalidateQuestPresentation(775)
    s = NS.ResolveQuestPresentation(775, "Chosen point", owner)
    assert(s.title == "Turn in 'Journey into Thunder Bluff'")
    assert(s.subtext == (client == "forever" and "Talk to Cairne Bloodhoof" or "Ready to turn in"),
        "Same-identity entity naming did not fall through to BtWQuests")
    active, ready, ambiguous = false, false, true
    owner.questContext = { action = "accept" }
    NS.InvalidateQuestPresentation(775)
    local acceptText = NS.ResolveQuestPresentation(775, "Chosen point", owner).subtext
    if client == "forever" then assert(acceptText == nil, "Ambiguity was overridden")
    else assert(acceptText == "Talk to Ancestral Spirit") end
    noOwner = true
    NS.InvalidateQuestPresentation(775)
    assert(NS.ResolveQuestPresentation(775, "Chosen point", owner).subtext == "Talk to Ancestral Spirit")
    quests[775].source.restrictions = false
    BtWQuestsDatabase:UpdateDataTable("quest", {})
    BtWQuestsDatabase:AddDataTable("npc", {})
    f.Flush()
    assert(NS.ResolveQuestPresentation(775, "Chosen point", owner).subtext == nil, "Ineligible source was selected")
    quests[775].source.restrictions = true
    BtWQuestsDatabase:UpdateDataTable("quest", {})
    f.Flush()
    assert(NS.ResolveQuestPresentation(775, "Chosen point", owner).subtext == "Talk to Ancestral Spirit")
    clientName = "Client Quest"
    NS.InvalidateQuestPresentation(775)
    assert(NS.ResolveQuestTitle(775) == "Client Quest", "Optional database overrode the client title")
    clientName = nil
    BtWQuestsDatabase:AddData("quest", 775, Record("Unnamed"))
    f.Flush()
    assert(NS.ResolveQuestTitle(775) == nil, "BtWQuests sentinel became a quest title")
    BtWQuestsDatabase.GetQuestByID = function() error("Pack not ready") end
    NS.InvalidateQuestPresentation(775)
    assert(NS.ResolveQuestPresentation(775, "Chosen point", owner).title == "Chosen point")
    loaded.BtWQuests, loaded.QuestieDB = false, false
    NS.InvalidateQuestPresentation()
    assert(NS.ResolveQuestTitle(775) == nil)
    local misses = 0
    data.Register("btwquests", { GetQuestName = function() misses = misses + 1 end })
    for id = 1, 300 do data.GetQuestName(id) end
    assert(misses == 300)
    data.GetQuestName(300)
    assert(misses == 300, "Recent negative title was not reused")
    data.GetQuestName(1)
    assert(misses == 301, "Negative title cache was not bounded")
    assert(data.ID(math.huge) == nil and data.ID(1.5) == nil)
    assert(NS.ResolveQuestTitle({}) == nil and NS.ResolveQuestPresentation(1.5) == nil)
end
print("Quest-data priority, role safety, live dialog, pack invalidation and unchanged-read caching passed on both clients")
