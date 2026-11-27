-- ============================================================
-- Dugi guide presentation
-- ============================================================
--
-- Converts Dugi's guide tags and quest progress into tracker rows and a
-- destination description.

local NS = _G.AzerothWaypointNS
NS.Internal = NS.Internal or {}
local Common = NS.Internal.GuidePresentation
local M = {}
NS.Internal.DugiPresentation = M

local ACTIONS = {
    A = { semantic = "accept", prefix = "Accept" },
    T = { semantic = "turnin", prefix = "Turn in" },
    C = { semantic = "complete", prefix = "Complete" },
    K = { semantic = "kill", prefix = "Kill" },
    B = { semantic = "buy", prefix = "Buy" },
    U = { semantic = "use", prefix = "Use" },
    R = { semantic = "goto", prefix = "Travel to", travel = "travel" },
    F = { semantic = "fly", prefix = "Fly to", travel = "flight" },
    H = { semantic = "hearth", prefix = "Hearth to", travel = "hearth" },
    h = { semantic = "home", prefix = "Set Hearth at", travel = "bind" },
    f = { semantic = "fpath", prefix = "Get flight path", travel = "flight_path" },
}
local PREFIXES = {
    collect = "Collect", use = "Use", kill = "Kill", talk = "Talk to",
    click = "Click", goto = "Travel to", fly = "Fly to", ferry = "Travel by", buy = "Buy",
}
local LOCATION_PREPOSITIONS = { " in ", " at " }
local TRAVEL_DESTINATION_CLAUSES = { " to travel to ", " to " }
local TRAVEL_INTERACTION_VERBS = {
    use = true, click = true, enter = true, take = true, board = true,
    ride = true, talk = true, speak = true, select = true,
}
local cache, cacheGuide, cacheDugi = {}, nil, nil
local sourceGuide, sourceDugi, sourceFactory, sourceLocations
local pendingData = { items = {}, quests = {}, spells = {} }
local pendingAll = {}
local viewerSteps, routeOwner = {}, nil

local function Call(object, method, ...)
    if type(object) ~= "table" or type(object[method]) ~= "function" then return nil end
    local ok, a, b, c, d, e, f = pcall(object[method], object, ...)
    if ok then return a, b, c, d, e, f end
end

local function GetGuide(dugi)
    local title = rawget(_G, "CurrentTitle") or dugi.CurrentTitle
    return type(title) == "string" and title or nil
end

local function NormalizeBreaks(value)
    if type(value) ~= "string" then return nil end
    return value:gsub("<[bB][rR]%s*/?>", "\n"):gsub("</?[bB]>", "")
        :gsub("<[^>]->", ""):gsub("\r", ""):gsub("[ \t]+\n", "\n")
        :gsub("\n[ \t]+", "\n"):gsub("\n\n\n+", "\n\n")
        :gsub("^%s+", ""):gsub("%s+$", "")
end

local function StripMarkup(value, preserveLines)
    value = NormalizeBreaks(value)
    if not value then return nil end
    value = value:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
        :gsub("|[Tt][^|]-|[tT]", ""):gsub("|[Hh][^|]-|[hH]", "")
        :gsub("|[hH]", ""):gsub("|A.-|a", ""):gsub("{([^}]-)}", "%1")
    if preserveLines then value = value:gsub("[ \t]+", " "):gsub(" *\n *", "\n")
    else value = value:gsub("%s+", " ") end
    value = value:match("^%s*(.-)%s*$")
    return value ~= "" and value or nil
end

function M.StripMarkup(value) return StripMarkup(value, false) end
function M.StripMultilineMarkup(value) return StripMarkup(value, true) end
function M.NormalizeRichText(value) return NormalizeBreaks(value) end
function M.GetActionDefinition(action) return ACTIONS[action] end
local function ClearTable(values) for key in pairs(values) do values[key] = nil end end
function M.Invalidate()
    ClearTable(cache)
    ClearTable(viewerSteps); routeOwner = nil
    for _, values in pairs(pendingData) do ClearTable(values) end
    ClearTable(pendingAll)
end

local function PruneCache()
    for index in pairs(cache) do
        if index ~= routeOwner and not viewerSteps[index] then cache[index] = nil end
    end
end

-- ============================================================
-- Viewer step selection
-- ============================================================

function M.RetainViewerSteps(steps)
    ClearTable(viewerSteps)
    if steps then for index in pairs(steps) do viewerSteps[index] = true end end
    PruneCache()
end

function M.SetRouteOwner(index)
    routeOwner = index
    PruneCache()
end

local function AddRelevantIndex(indices, seen, value)
    value = tonumber(value)
    if value and value > 0 and not seen[value] then
        seen[value] = true
        indices[#indices + 1] = value
    end
end

local function AppendRelevantIndices(dugi, includeSticky, indices, seen)
    local count = 0
    for index in dugi.IterateRelevantSteps do
        AddRelevantIndex(indices, seen, index)
        count = count + 1
        if count >= (includeSticky and 12 or 50) then break end
    end
end

function M.GetRelevantIndices(dugi, current, includeSticky, indices, seen)
    indices, seen = indices or {}, seen or {}
    ClearTable(indices); ClearTable(seen)
    AddRelevantIndex(indices, seen, current)
    if type(dugi.IterateRelevantSteps) == "function" then
        pcall(AppendRelevantIndices, dugi, includeSticky, indices, seen)
    end
    local sticky = includeSticky and dugi.Modules and dugi.Modules.StickyFrame
        and dugi.Modules.StickyFrame.StickyQuests
    if type(sticky) == "table" then
        for index = 1, #sticky do AddRelevantIndex(indices, seen, sticky[index]) end
    end
    return indices
end

local function PositiveID(value)
    value = tonumber(value)
    return value and value > 0 and math.floor(value) or nil
end

local function Coordinate(value)
    value = tonumber(value)
    if not value then return nil end
    if value > 1 then value = value / 100 end
    return value >= 0 and value <= 1 and value or nil
end

local function CopyIDs(...)
    local ids = {}
    for index = 1, select("#", ...) do
        local id = PositiveID(select(index, ...))
        if id then ids[#ids + 1] = id end
    end
    return ids
end

local function ItemName(id)
    if not id then return nil end
    local api = rawget(_G, "C_Item")
    local fn = api and (api.GetItemNameByID or api.GetItemInfo)
    if type(fn) ~= "function" then return nil end
    local ok, name = pcall(fn, id)
    return ok and M.StripMarkup(name) or nil
end

local function SpellName(id)
    local api = rawget(_G, "C_Spell")
    if not id or not api or type(api.GetSpellName) ~= "function" then return nil end
    local ok, name = pcall(api.GetSpellName, id)
    return ok and M.StripMarkup(name) or nil
end

local function MapName(id)
    local api = rawget(_G, "C_Map")
    if not id or not api or type(api.GetMapInfo) ~= "function" then return nil end
    local ok, info = pcall(api.GetMapInfo, id)
    return ok and type(info) == "table" and M.StripMarkup(info.name) or nil
end

local DATA_EVENT_KINDS = {
    GET_ITEM_INFO_RECEIVED = "items", ITEM_DATA_LOAD_RESULT = "items",
    QUEST_DATA_LOAD_RESULT = "quests", QUEST_LOG_UPDATE = "quests",
    SPELL_DATA_LOAD_RESULT = "spells", SPELLS_CHANGED = "spells", UNIT_NAME_UPDATE = "npcs",
}
local DATA_PATTERNS = {
    { "items", "item:(%d+)" }, { "spells", "spell:(%d+)" },
    { "quests", "qid:(%d+)" }, { "quests", "quest:(%d+)" }, { "npcs", "npc:(%d+)" },
}

local function ReadDependency(dugi, kind, id)
    if kind == "items" then return ItemName(id) or false end
    if kind == "spells" then return SpellName(id) or false end
    if kind == "npcs" then return M.StripMarkup(Call(dugi, "GetLocalizedNPC", id)) or false end
    return type(NS.ResolveQuestTitle) == "function" and NS.ResolveQuestTitle(id) or false
end

local function AddDependency(dependencies, dugi, kind, id)
    id = PositiveID(id)
    if not id then return end
    local values = dependencies[kind]
    if not values then values = {}; dependencies[kind] = values end
    if values[id] == nil then values[id] = ReadDependency(dugi, kind, id) end
end

local function AddTextDependencies(dependencies, dugi, text)
    if type(text) ~= "string" then return end
    for _, pattern in ipairs(DATA_PATTERNS) do
        for id in text:gmatch(pattern[2]) do AddDependency(dependencies, dugi, pattern[1], id) end
    end
end

local function BuildDependencies(dugi, fact, sourceTitle)
    local dependencies = {}
    AddDependency(dependencies, dugi, "quests", fact.questID)
    AddDependency(dependencies, dugi, "items", fact.itemID)
    AddDependency(dependencies, dugi, "items", fact.lootItemID)
    AddDependency(dependencies, dugi, "spells", fact.titleSpellID)
    for _, id in ipairs(fact.npcIDs) do AddDependency(dependencies, dugi, "npcs", id) end
    AddTextDependencies(dependencies, dugi, sourceTitle)
    AddTextDependencies(dependencies, dugi, fact.tags)
    AddTextDependencies(dependencies, dugi, fact.richNote)
    return dependencies
end

-- Raw events only mark matching cached dependencies. Name resolution and
-- invalidation wait until the Viewer's coalesced flush.
function M.QueueDataEvent(event, id)
    local kind = DATA_EVENT_KINDS[event]
    if not kind then return false end
    if event == "UNIT_NAME_UPDATE" or event == "QUEST_LOG_UPDATE" or event == "SPELLS_CHANGED" then id = nil
    else id = PositiveID(id); if not id then return false end end
    for _, entry in pairs(cache) do
        local dependencies = entry.dependencies and entry.dependencies[kind]
        if dependencies and (id == nil or dependencies[id] ~= nil) then
            if id then pendingData[kind][id] = true else pendingAll[kind] = true end
            return true
        end
    end
    return false
end

function M.FlushDataEvents()
    local changed = false
    for _, entry in pairs(cache) do
        for kind, values in pairs(entry.dependencies) do
            for id, previous in pairs(values) do
                if pendingAll[kind] or pendingData[kind] and pendingData[kind][id] then
                    local different = ReadDependency(cacheDugi, kind, id) ~= previous
                    local fact = entry.value.facts
                    if kind == "quests" and id == fact.questID and fact.objectiveIndex
                        and type(NS.ResolveQuestObjectiveText) == "function"
                    then different = different or NS.ResolveQuestObjectiveText(id, fact.objectiveIndex) ~= fact.objectiveText end
                    if different then entry.invalid = true; changed = true end
                end
            end
        end
    end
    for _, values in pairs(pendingData) do ClearTable(values) end
    ClearTable(pendingAll)
    return changed
end

-- ============================================================
-- Guide text and quest dependencies
-- ============================================================

local function ResolveTokens(dugi, text)
    if type(text) ~= "string" then return nil end
    local unresolved = false
    local function nameOrFallback(name, fallback)
        if name then return name end
        unresolved = true
        return fallback
    end
    text = text:gsub("%(item:(%d+)%)", function(id)
        local name = ItemName(tonumber(id))
        return nameOrFallback(name and ("[" .. name .. "]"), "the item")
    end):gsub("%(npc:(%d+)%)", function(id)
        return nameOrFallback(M.StripMarkup(Call(dugi, "GetLocalizedNPC", tonumber(id))), "the NPC")
    end):gsub("%(spell:(%d+)%)", function(id)
        return nameOrFallback(SpellName(tonumber(id)), "the spell")
    end):gsub("%(qid:(%d+)%)", function(id)
        local name = type(NS.ResolveQuestTitle) == "function" and NS.ResolveQuestTitle(tonumber(id)) or nil
        return nameOrFallback(name and ("[" .. name .. "]"), "the quest")
    end):gsub("%(map:(%d+)%)", function(id)
        return nameOrFallback(MapName(tonumber(id)), "the area")
    end):gsub('%(guide:%s*"([^"]+)"%s*%)', "[%1]")
        :gsub("%(object:%d+%)", function() return nameOrFallback(nil, "the object") end)
    return text, unresolved
end

local function ReadNote(tags)
    if type(tags) ~= "string" then return nil end
    local _, noteStart = tags:find("|[NW]R?|")
    if not noteStart then return nil end
    -- Pipes inside colors and hyperlinks are not guide-tag boundaries.
    local finish = tags:find("|%u[%u%d]*|", noteStart + 1)
    return tags:sub(noteStart + 1, finish and finish - 1 or #tags):gsub("|%s*$", "")
end

local function GetAuthoredLocation(dugi, guide, note)
    if type(note) ~= "string" then return nil end
    local location = note:match("{([^}]+)}")
    if location then return M.StripMarkup(Call(dugi, "TranslateText", "{" .. location .. "}") or location) end

    local factory = type(dugi.guides) == "table" and dugi.guides[guide] or nil
    if sourceDugi ~= dugi or sourceGuide ~= guide or sourceFactory ~= factory then
        sourceDugi, sourceGuide, sourceFactory, sourceLocations = dugi, guide, factory, {}
        -- TranslateText removes braces before ParseRows publishes tags and
        -- quests2. Recover their authored meaning once per guide, outside
        -- layout, without calling or wrapping Dugi's coroutine-backed parser.
        if type(factory) == "function" and type(dugi.TranslateText) == "function" then
            local ok, source = pcall(factory)
            if ok and type(source) == "string" then
                for line in source:gmatch("[^\r\n]+") do
                    local authoredNote = ReadNote(line)
                    local authoredLocation = authoredNote and authoredNote:match("{([^}]+)}")
                    if authoredLocation then
                        local key = Common.NormalizeText(Call(dugi, "TranslateText", authoredNote))
                        local name = M.StripMarkup(Call(dugi, "TranslateText", "{" .. authoredLocation .. "}"))
                        if key and name then
                            local previous = sourceLocations[key]
                            -- An ambiguous source match cannot authorize deleting text.
                            if previous == nil or previous == name then sourceLocations[key] = name
                            else sourceLocations[key] = false end
                        end
                    end
                end
            end
        end
    end
    return sourceLocations[Common.NormalizeText(note)] or nil
end

local function Classify(fact, dugi)
    local definition = ACTIONS[fact.action]
    if definition then return definition.semantic, "explicit_action" end
    if fact.hasGuideLinks then return "note", "guide_choice" end
    if fact.useItemID or fact.titleSpellID then return "use", "use_tag" end
    if fact.titleItemID or fact.lootItemID or Call(dugi, "ReturnTag", "T", fact.index) then
        return "collect", "item_or_collect_tag"
    end
    if Call(dugi, "ReturnTag", "K", fact.index) then return "kill", "kill_tag" end
    if Call(dugi, "ReturnTag", "S", fact.index) or Call(dugi, "ReturnTag", "ST", fact.index) then
        return "talk", "talk_tag"
    end
    if #fact.objectIDs > 0 then return "click", "object_tag" end
    local lower = (fact.note or ""):lower()
    if #fact.npcIDs > 0 and (lower:match("^speak to ") or lower:match("^talk to ")) then
        return "talk", "npc_instruction"
    end
    if lower:match("^click ") then return "click", "instruction" end
    if fact.objectiveText then return "complete", "quest_objective" end
    return "note", "authored_note"
end

local function ReadFacts(dugi, index)
    -- Capture original tags before Dugi formats its mutable display strings.
    local tags = type(dugi.tags) == "table" and dugi.tags[index] or nil
    local sourceTitle = type(dugi.quests1) == "table" and dugi.quests1[index]
        or type(dugi.quests1L) == "table" and dugi.quests1L[index] or nil
    local sourceNote = ReadNote(tags) or type(dugi.quests2) == "table" and dugi.quests2[index] or nil
    local lootItem, lootQuantity = Call(dugi, "ReturnTag", "L", index)
    local fact = {
        index = index, guide = GetGuide(dugi), tags = tags,
        action = type(dugi.actions) == "table" and dugi.actions[index] or nil,
        questID = PositiveID(type(dugi.qid) == "table" and dugi.qid[index]),
        objectiveIndex = PositiveID(Call(dugi, "ReturnTag", "QIDP", index)),
        state = Call(dugi, "GetQuestState", index),
        npcIDs = CopyIDs(Call(dugi, "ReturnTag", "NPC", index)),
        objectIDs = CopyIDs(Call(dugi, "ReturnTag", "OBJ", index)),
        useItemID = PositiveID(Call(dugi, "ReturnTag", "U", index)),
        lootItemID = PositiveID(lootItem), quantity = PositiveID(lootQuantity),
        titleItemID = type(sourceTitle) == "string" and PositiveID(sourceTitle:match("%(item:(%d+)%)")) or nil,
        titleSpellID = type(sourceTitle) == "string" and PositiveID(sourceTitle:match("%(spell:(%d+)%)")) or nil,
        location = GetAuthoredLocation(dugi, GetGuide(dugi), sourceNote),
        mapID = PositiveID(Call(dugi, "ReturnTag", "Z", index)) or PositiveID(dugi.GuideMapID),
        playerPosition = not not Call(dugi, "ReturnTag", "PPOS", index),
    }
    if #fact.npcIDs == 0 and type(sourceTitle) == "string" then
        fact.npcIDs = CopyIDs(sourceTitle:match("%(npc:(%d+)%)"))
    end
    if #fact.objectIDs == 0 and type(sourceTitle) == "string" then
        fact.objectIDs = CopyIDs(sourceTitle:match("%(object:(%d+)%)"))
    end
    if not fact.location and type(sourceNote) == "string" then
        fact.location = MapName(PositiveID(sourceNote:match("%(map:(%d+)%)")))
    end
    local coords = Call(dugi, "getCoords", index)
    local final = type(coords) == "table" and coords[#coords] or nil
    if type(final) == "table" then fact.x, fact.y = Coordinate(final[1]), Coordinate(final[2]) end
    local description = Call(dugi, "GetQuestDescription", index)
    local note = Call(dugi, "GetQuestStepText", index) or sourceNote
    fact.hasGuideLinks = type(sourceNote) == "string" and sourceNote:find("(guide:", 1, true) ~= nil
        or type(note) == "string" and note:find("|Hguide:", 1, true) ~= nil or false
    if fact.hasGuideLinks and type(note) == "string" and not note:find("|Hguide:", 1, true) then
        note = Call(dugi.NPCJournalFrame, "ReplaceSpecialTags", sourceNote, true, index) or note
    end
    local titleText, titleUnresolved = ResolveTokens(dugi, sourceTitle)
    local descriptionText, descriptionUnresolved = ResolveTokens(dugi, description)
    -- A missing entity name is not an authored title. Prefer readable native
    -- text/instructions until the data-ready event supplies its real identity.
    fact.rawTitle = not titleUnresolved and M.StripMarkup(titleText) or nil
    fact.description = not descriptionUnresolved and M.StripMarkup(descriptionText) or nil
    fact.note = M.StripMultilineMarkup(ResolveTokens(dugi, note))
    fact.fullNote, fact.richNote = fact.note, M.NormalizeRichText(note)
    fact.npcName = M.StripMarkup(Call(dugi, "GetLocalizedNPC", fact.npcIDs[1]))
    fact.itemID = fact.useItemID or fact.lootItemID or fact.titleItemID
    fact.itemName = ItemName(fact.itemID)
    if fact.questID and fact.objectiveIndex and type(NS.ResolveQuestObjectiveText) == "function" then
        fact.objectiveText = NS.ResolveQuestObjectiveText(fact.questID, fact.objectiveIndex)
    end
    fact.semantic, fact.actionReason = Classify(fact, dugi)
    return fact
end

-- ============================================================
-- Destination titles and instructions
-- ============================================================

local function ChooseTitle(fact)
    local definition = ACTIONS[fact.action]
    if fact.action == "A" or fact.action == "T" then
        local name = type(NS.ResolveQuestTitle) == "function" and NS.ResolveQuestTitle(fact.questID) or nil
        name = M.StripMarkup(name) or fact.rawTitle
        if name then
            local quoted = "'" .. name .. "'"
            local start, finish
            if fact.description then start, finish = fact.description:find(quoted, 1, true) end
            if start then
                local suffix = fact.description:sub(finish + 1)
                if suffix == "" or fact.npcName and suffix == " (" .. fact.npcName .. ")" then
                    return fact.description:sub(1, finish), "localized_quest_identity"
                end
            end
            return definition.prefix .. " " .. quoted, "quest_identity"
        end
    end
    if fact.objectiveText and fact.semantic == "complete" then return fact.objectiveText, "objective_identity" end
    if fact.semantic == "note" then
        return fact.rawTitle or fact.description or fact.note or "Dugi guide step", "authored_title"
    end
    local subject = fact.semantic == "talk" and fact.npcName or fact.rawTitle
    local prefix = definition and definition.prefix or PREFIXES[fact.semantic]
    if prefix and subject then
        if fact.semantic == "collect" then
            local quantity = fact.quantity
            -- Recover a count only when it immediately precedes the verified
            -- subject after the known action prefix in the authored note.
            local first = (fact.note or ""):match("^([^\n]+)") or ""
            local count, rest = first:match("^" .. prefix .. " (%d+) (.+)")
            if count and rest:sub(1, #subject) == subject then quantity = tonumber(count) end
            if quantity and quantity > 1 then
                return prefix .. " " .. quantity .. " " .. subject, "quantity_identity"
            end
        end
        if fact.description and fact.description:find(subject, 1, true)
            and (definition or fact.semantic == "collect")
        then
            return fact.description, "resolved_description"
        end
        if subject:sub(1, #prefix + 1):lower() == (prefix .. " "):lower() then
            return subject, "authored_action"
        end
        return prefix .. " " .. subject, "action_identity"
    end
    return fact.description or subject or fact.note or "Dugi guide step", "readable_fallback"
end

local function WithoutCoordinates(text)
    text = M.StripMarkup(text and text:gsub("%([%d.]+,%s*[%d.]+%)", ""))
    return text and text:gsub("%.$", "") or nil
end

local LocationOnly = Common.LocationOnly
local RepeatsAction = Common.RepeatsAction
local TrimAuthoredLocationSuffix = Common.TrimLocationSuffix

local function SelectTravelMethodInstruction(text, fact)
    local definition = ACTIONS[fact.action]
    local destination = WithoutCoordinates(fact.rawTitle)
    if not text or not definition or not definition.travel or not destination then return text, false end
    local verb = text:match("^(%a+)%s")
    if not verb or not TRAVEL_INTERACTION_VERBS[verb:lower()] then return text, false end
    -- The title already owns this destination. Preserve the actual interaction
    -- (including names, boarding points and alternatives) as supporting context.
    -- Conditions after the destination and instructions about other travel stay intact.
    for _, clause in ipairs(TRAVEL_DESTINATION_CLAUSES) do
        local suffix = clause .. destination
        if #text > #suffix and Common.SameText(text:sub(-#suffix), suffix) then
            local method = M.StripMarkup(text:sub(1, #text - #suffix))
            if method and method:find("%s") then return method, true end
        end
    end
    return text, false
end

local function SelectInstructions(fact, title)
    local tips, seen, suppression = {}, {}, nil
    -- Authored breaks create tip units, automatic wrapping never does.
    for paragraph in ((fact.note or "") .. "\n\n"):gmatch("(.-)\n%s*\n") do
        local text = WithoutCoordinates(paragraph)
        local locationRemoved
        text, locationRemoved = TrimAuthoredLocationSuffix(text, fact.location)
        if locationRemoved then suppression = text and "location_suffix" or "location_only" end
        local destinationRemoved
        text, destinationRemoved = SelectTravelMethodInstruction(text, fact)
        if destinationRemoved then suppression = "repeated_travel_destination" end
        if text then
            local npcOnly = fact.npcName and (Common.SameText(text, fact.npcName)
                or fact.location and Common.SameText(text, fact.npcName .. " in " .. fact.location))
            if npcOnly and (fact.semantic == "accept" or fact.semantic == "turnin") then
                text = "Talk to " .. fact.npcName
            end
            if fact.semantic == "talk" and fact.npcName
                and RepeatsAction(text, "Speak to " .. fact.npcName, fact.location)
            then
                text = title
            end
            if fact.semantic ~= "note" and text:sub(1, #title):lower() == title:lower()
                and text:sub(#title + 1, #title + 1) == " "
            then
                local remainder = M.StripMarkup(text:sub(#title + 2))
                if remainder and not LocationOnly(remainder, fact.location) then
                    text = remainder:sub(1, 1):upper() .. remainder:sub(2)
                end
            end
            if RepeatsAction(text, title, fact.location) then
                suppression = "repeated_action"
            elseif LocationOnly(text, fact.location) then
                suppression = "location_only"
            else
                local key = text:lower()
                if not seen[key] then
                    seen[key] = true
                    tips[#tips + 1] = { text = text, kind = "tip", status = "passive",
                        colorRole = npcOnly and "npc" or "note", action = npcOnly and "talk" or "note", useFullHeight = true }
                end
            end
        end
    end
    return tips, suppression
end

local function ResolveFacts(fact)
    local title, titleReason = ChooseTitle(fact)
    local conciseTitle, locationRemoved = TrimAuthoredLocationSuffix(title, fact.location)
    if conciseTitle and locationRemoved then
        title, titleReason = conciseTitle, titleReason .. "_without_location"
    end
    local tips, suppression = SelectInstructions(fact, title)
    local context = tips[1] and tips[1].text or nil
    local definition = ACTIONS[fact.action]
    local travel = definition and definition.travel or nil
    if type(NS.ClassifyTravelSemantics) == "function" then
        travel = NS.ClassifyTravelSemantics(fact.semantic, fact.mapID, fact.x, fact.y, title, context) or travel
    end
    local kind = travel and "travel" or fact.questID and "quest" or "guide"
    local semantics = Common.BuildSemanticInfo(kind, travel, fact.questID)
    local snapshot = Common.BuildSnapshot(title, title, context, "dugi", context and "instruction" or suppression,
        nil, fact.index, semantics)
    local complete = fact.state == "C" or fact.state == "X"
    for _, tip in ipairs(tips) do if complete then tip.status = fact.state == "X" and "skipped" or "complete" end end
    local rows = Common.GroupTipRows({ {
        text = title, status = fact.state == "X" and "skipped" or complete and "complete" or "incomplete", kind = "goal",
        action = fact.semantic, questID = fact.questID, useFullHeight = true, tips = tips,
    } })
    local detailParts = {}
    for _, tip in ipairs(tips) do detailParts[#detailParts + 1] = tip.text end
    return {
        title = title, rawTitle = fact.rawTitle or title, subtext = context,
        multilineSubtext = #detailParts > 0 and table.concat(detailParts, "\n\n") or nil, richSubtext = fact.richNote,
        hasGuideLinks = fact.hasGuideLinks, action = fact.action, semantic = fact.semantic,
        semanticKind = kind, semanticTravelType = travel, questID = fact.questID,
        objectiveIndex = fact.objectiveIndex, ownerStepIndex = fact.index,
        rows = rows, facts = fact, snapshot = snapshot, fullNote = fact.fullNote,
        tooltipTips = fact.fullNote and { { text = fact.fullNote, status = "passive", kind = "tip", action = "note" } } or nil,
        titleSource = titleReason, contextSource = context and "authored_instruction" or "none",
        suppressionReason = suppression, actionReason = fact.actionReason,
    }
end

-- ============================================================
-- Step presentation
-- ============================================================

function M.ResolveStep(dugi, index)
    if type(dugi) ~= "table" or type(index) ~= "number" or index < 1 or index ~= math.floor(index) then return nil end
    local guide = GetGuide(dugi)
    if cacheDugi ~= dugi or cacheGuide ~= guide then M.Invalidate(); cacheDugi, cacheGuide = dugi, guide end
    local action = type(dugi.actions) == "table" and dugi.actions[index]
    local sourceTitle = type(dugi.quests1) == "table" and dugi.quests1[index]
    local title = type(dugi.quests1L) == "table" and dugi.quests1L[index]
    local note = type(dugi.quests2) == "table" and dugi.quests2[index]
    local tags = type(dugi.tags) == "table" and dugi.tags[index]
    local questID = type(dugi.qid) == "table" and dugi.qid[index]
    local state = Call(dugi, "GetQuestState", index)
    if not sourceTitle and not title and not note then return nil end
    local previous = cache[index]
    if previous and not previous.invalid and previous.action == action and previous.sourceTitle == sourceTitle
        and previous.title == title and previous.note == note
        and previous.tags == tags and previous.questID == questID and previous.state == state
    then return previous.value end
    local value = ResolveFacts(ReadFacts(dugi, index))
    cache[index] = {
        action = action, sourceTitle = sourceTitle, title = type(dugi.quests1L) == "table" and dugi.quests1L[index],
        note = type(dugi.quests2) == "table" and dugi.quests2[index],
        tags = tags, questID = questID, state = state, value = value,
        dependencies = BuildDependencies(dugi, value.facts, sourceTitle),
    }
    return value
end
