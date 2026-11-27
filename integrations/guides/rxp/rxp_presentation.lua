-- ============================================================
-- RestedXP guide presentation
-- ============================================================
--
-- Matches RestedXP waypoints to the owning guide element and resolves its
-- quest or interaction text.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuidePresentation
local P = {}
NS.Internal.RXPPresentation = P
local cache, cacheGuide = {}, nil
local rawFields = { "tag", "text", "rawtext", "tooltipText", "title", "questId", "obj", "objIndex", "id", "qty",
    "completed", "skip", "hidden", "textOnly", "optional", "hideTooltip", "requestFromServer", "zone", "arrowtext", "location" }
local actions = {
    daily = "accept", acceptmultiple = "accept", accept = "accept", turnin = "turnin", dailyturnin = "turnin",
    turninmultiple = "turnin", complete = "complete", scenario = "complete",
    collect = "collect", collectmultiple = "collect", buy = "buy", use = "use", usespell = "cast", cast = "cast",
    gossip = "talk", gossipoption = "talk", treasure = "click", rare = "kill", kill = "kill", mob = "kill", target = "talk", trainer = "train", train = "train",
    ["goto"] = "goto", waypoint = "goto", groundgoto = "goto", flygoto = "goto", questgoto = "goto",
    questwaypoint = "goto", line = "goto", loop = "goto", fly = "fly", fp = "fpath",
    hs = "hearth", hsbatching = "hearth", home = "home", bindlocation = "home", zone = "goto", vehicle = "goto", exitvehicle = "goto", deathskip = "goto", enterScenario = "goto", leaveScenario = "goto",
}
local prefixes = { collect = "Collect", buy = "Buy", use = "Use", cast = "Cast", kill = "Kill", talk = "Talk to",
    train = "Train", goto = "Travel to", fly = "Fly to", fpath = "Get flight path", hearth = "Hearth to", home = "Set Hearth at" }
local travel = { goto = "travel", fly = "flight", fpath = "flight_path", hearth = "hearth", home = "bind" }
-- Presentation color/action is separate from structural ownership. An
-- enterScenario or zone instruction can use the travel palette without
-- becoming an empty coordinate node in the ownership search.
local coordinateTags = {
    ["goto"] = true, waypoint = true, groundgoto = true, flygoto = true,
    questgoto = true, questwaypoint = true, line = true, loop = true,
}
local multipleTags = { daily = true, acceptmultiple = true, dailyturnin = true, turninmultiple = true }
local function QuestCandidates(element)
    if not multipleTags[element.tag] or type(element.ids) ~= "table" then return nil end
    local ids, seen = {}, {}
    for _, value in ipairs(element.ids) do
        local id = tonumber(value)
        if id and id > 0 and id < math.huge and id == math.floor(id) and not seen[id] then
            seen[id], ids[#ids+1] = true, id
        end
    end
    return #ids > 0 and ids or nil
end
local function NoNativeQuestState() end

function P.Call(object, name, ...)
    local fn = object and object[name]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

function P.Text(rxp, value)
    if type(value) ~= "string" then return nil end
    value = P.Call(rxp.settings, "ReplaceColors", value) or value
    if rxp.locale and type(rxp.locale.Get) == "function" then value = P.Call(rxp.locale, "Get", value) or value end
    value = P.Call(rxp, "ReplaceNpcIds", value) or value
    value = value:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|cRXP_[A-Z]+_", ""):gsub("|[rR]", "")
        :gsub("|[Tt][^|]-|[tT]", ""):gsub("|A[^|]-|a", ""):gsub("|H.-|h(.-)|h", "%1")
        :gsub("npc:([^:]+):%d+", "%1"):gsub("::%d+", ""):gsub("\\n", "\n")
    return value:match("^%s*(.-)%s*$") ~= "" and value:match("^%s*(.-)%s*$") or nil
end

local function CoordinateText(rxp, element, text)
    if not coordinateTags[element.tag] then return false end
    if not text then return true end
    -- RXP generates this exact shape for radius-based gotos without authored
    -- text. Use its localized prefix instead of an English-only heuristic.
    local prefix = P.Call(rxp.locale, "Get", "Go to") or "Go to"
    return text:sub(1, #prefix) == prefix
        and text:sub(#prefix + 1):match("^%s+[%d.]+,%s*[%d.]+%s+%([^)]*%)$") ~= nil
end

local function SingleID(values)
    local id
    if type(values) ~= "table" then return nil end
    for key in pairs(values) do if id then return nil end; id = tonumber(key) end
    return id
end

local function UnitID(element)
    local values = element.targets or element.mobs or element.unitscan or element.unitlist
    return type(values) == "table" and tonumber((tostring(values[1] or ""):gsub("^%+", ""))) or nil
end

-- ============================================================
-- Native unit and quest facts
-- ============================================================

local function UnitName(element)
    local values = element.targets or element.mobs or element.unitscan or element.unitlist
    if type(values) ~= "table" or #values ~= 1 or type(values[1]) ~= "string" then return nil end
    local name = values[1]:gsub("^%+", "")
    return not tonumber(name) and name or nil
end

local function UnitCount(element)
    local values = element.targets or element.mobs or element.unitscan or element.unitlist
    return type(values) == "table" and #values or 0
end

local function Identity(rxp, element)
    local item, spell = SingleID(element.activeItems), SingleID(element.activeSpells)
    if element.tag == "usespell" then spell, item = spell or item, nil end
    if element.tag == "cast" and type(element.ids) == "table" and #element.ids == 1 then spell = tonumber(element.ids[1]) end
    return UnitID(element), item, spell, UnitName(element)
end

local function Matches(record, rxp, step)
    if not record or record.dirty or record.title ~= step.title or record.sticky ~= step.sticky
        or record.completed ~= step.completed or record.stepID ~= step.stepId or record.arrowtext ~= step.arrowtext or #record.raw ~= #(step.elements or {}) then return false end
    for index, element in ipairs(step.elements or {}) do
        local previous = record.raw[index]
        for _, field in ipairs(rawFields) do if previous[field] ~= element[field] then return false end end
        local ids = multipleTags[element.tag] and type(element.ids) == "table" and element.ids
        local old = previous.candidateInput
        if ids then
            if not old or #ids ~= #old then return false end
            for i, id in ipairs(ids) do if old[i] ~= id then return false end end
        elseif old then return false end
        if previous.parentIndex then
            if element.parent ~= step.elements[previous.parentIndex] then return false end
        elseif type(element.parent) == "table" and element.parent.step == step then return false end
        local npc, item, spell, name = Identity(rxp, element)
        if previous.npcID ~= npc or previous.activeItem ~= item or previous.activeSpell ~= spell
            or previous.npcName ~= name or previous.npcCount ~= UnitCount(element) then return false end
    end
    return true
end

local function Name(rxp, kind, id)
    if not id then return nil end
    if kind == "quest" then
        -- RXP.GetQuestName may expand quest-log headers. Use AWP's safe query.
        return P.Text(rxp, P.Call(NS, "ResolveQuestTitle", id))
    end
    return P.Text(rxp, P.Call(rxp, kind == "npc" and "GetNpcName"
        or kind == "item" and "GetItemName" or "GetSpellInfo", id))
end

local function QuestActionMatches(text, verb, name)
    return verb and (Common.SameText(text, verb .. " " .. name)
        or Common.SameText(text, verb .. " '" .. name .. "'")
        or Common.SameText(text, verb .. ' "' .. name .. '"')) or false
end

local function RepeatedQuestAction(text, action, name)
    if not name or action ~= "accept" and action ~= "turnin" then return false end
    local verb = action == "accept" and "Accept" or "Turn in"
    local nativeVerb
    if action == "accept" then nativeVerb = rawget(_G, "ACCEPT")
    else nativeVerb = rawget(_G, "TURN_IN_QUEST") end
    text = Common.WithoutCoordinates(text)
    return Common.SameText(text, name) or QuestActionMatches(text, verb, name) or QuestActionMatches(text, nativeVerb, name)
end

local function Context(rxp, title, authored, location, npc, action, questName)
    local tips, seen, suppression = {}, {}, nil
    if npc and (action == "accept" or action == "turnin") then
        tips[1] = { text = "Talk to " .. npc, status = "incomplete", kind = "tip", colorRole = "npc", action = "talk", fullHeight = true }
        seen[Common.NormalizeText(tips[1].text):lower()] = true
    end
    for paragraph in ((authored or "") .. "\n\n"):gmatch("(.-)\n%s*\n") do
        local text = P.Text(rxp, paragraph)
        local removed
        text, removed = Common.TrimLocationSuffix(text, location)
        if removed then suppression = text and "location_suffix" or "location_only" end
        if text and RepeatedQuestAction(text, action, questName) then text, suppression = nil, "repeated_quest_action"
        elseif text and Common.RepeatsAction(text, title, location) then text, suppression = nil, "repeated_action" end
        if text and npc and (Common.SameText(text, npc) or Common.SameText(text, "Speak to " .. npc)) then text = "Talk to " .. npc end
        local key = text and Common.NormalizeText(text):lower()
        if key and not seen[key] then
            seen[key] = true
            tips[#tips + 1] = { text = text, status = "incomplete", kind = "tip", action = action, fullHeight = true }
        end
    end
    return tips, suppression
end

-- ============================================================
-- Presentation cache
-- ============================================================

function P.Invalidate(event, id)
    local changed = false
    for _, record in pairs(cache) do
        if not event or event == "UNIT_NAME_UPDATE" or record.dependencies[id] then
            record.dirty = true
            changed = true
        end
    end
    return changed
end

function P.Retain(indices)
    for index in pairs(cache) do if not indices[index] then cache[index] = nil end end
end

function P.ResolveStep(rxp, step)
    local guide = rxp.currentGuide
    local key = guide and (guide.key or guide.group .. "||" .. guide.name)
    if cacheGuide ~= key then cache, cacheGuide = {}, key end
    local index = step.index or "tip"
    local existing = cache[index]
    if Matches(existing, rxp, step) then return existing.result, false end
    local record = { title = step.title, sticky = step.sticky, completed = step.completed, stepID = step.stepId, arrowtext = step.arrowtext, raw = {}, dependencies = {} }
    local result = { index = step.index, stepID = step.stepId, title = P.Text(rxp, step.title), sticky = step.sticky == true,
        completed = step.completed == true, rows = {}, elements = {} }
    local groups, linkedNPC, linkedMap, ordinals = {}, {}, {}, {}
    local linkedNames, linkedSubjects, ambiguousSubjects = {}, {}, {}
    for ordinal, element in ipairs(step.elements or {}) do ordinals[element] = ordinal end
    local groupMap
    local precedingAction
    for _, element in ipairs(step.elements or {}) do
        local npc = UnitID(element)
        local name = UnitName(element)
        local owner = type(element.parent) == "table" and element.parent
            or element.tag == "target" and precedingAction
        if owner then
            local subject = npc or name
            if UnitCount(element)>1 or subject and linkedSubjects[owner] and linkedSubjects[owner]~=subject then
                ambiguousSubjects[owner] = true
            end
            if subject then linkedSubjects[owner] = subject end
        end
        if npc and owner then linkedNPC[owner] = npc end
        if name and owner then linkedNames[owner] = name end
        if element.zone and type(element.parent) == "table" then linkedMap[element.parent] = element.zone end
        if coordinateTags[element.tag] then precedingAction = nil
        elseif actions[element.tag] and element.tag ~= "target" and element.tag ~= "mob" then precedingAction = element end
    end
    for ordinal, element in ipairs(step.elements or {}) do
        if element.zone and (element.arrow or actions[element.tag] == "goto") then groupMap = element.zone end
        local raw = {}
        for _, field in ipairs(rawFields) do raw[field] = element[field] end
        raw.npcID, raw.activeItem, raw.activeSpell, raw.npcName = Identity(rxp, element)
        raw.npcCount = UnitCount(element)
        raw.parentIndex = ordinals[element.parent]
        raw.questCandidates = QuestCandidates(element)
        if multipleTags[element.tag] and type(element.ids) == "table" then
            raw.candidateInput = {}; for i, id in ipairs(element.ids) do raw.candidateInput[i] = id end
        end
        record.raw[ordinal] = raw
        local action = actions[element.tag] or "note"
        local text = P.Text(rxp, element.text) or P.Text(rxp, element.rawtext)
            or P.Text(rxp, element.title) or P.Text(rxp, element.tooltipText)
        local coordinateOnly = CoordinateText(rxp, element, text)
        local questID = tonumber(element.questId)
        if raw.questCandidates then
            -- Native multi-quest directives repeatedly assign questId while
            -- examining candidates. The last assignment is not an owner.
            local selector = NS.Internal.GuideQuestSelection
            questID = selector and selector.Select(action, raw.questCandidates, #raw.questCandidates > 1,
                NoNativeQuestState, rxp, true) or nil
        end
        local itemID = (action == "collect" or action == "buy") and tonumber(element.id) or raw.activeItem
        local spellID = raw.activeSpell or action == "cast" and tonumber(element.id)
        local questName = Name(rxp, "quest", questID)
        local subject = questName
        local title = text
        local titleSource = title and (coordinateOnly and "generated_coordinate_text" or "authored_text") or "none"
        if action == "talk" and not title and (raw.npcID or raw.npcName) then
            local name = Name(rxp, "npc", raw.npcID) or P.Text(rxp, raw.npcName)
            if name then title = "Talk to " .. name; titleSource = "localized_identity" end
        end
        if subject and (action == "accept" or action == "turnin") then
            title = (action == "accept" and "Accept '" or "Turn in '") .. subject .. "'"
            titleSource = "localized_identity"
        elseif raw.questCandidates then
            title = action == "accept" and "Accept Available Quest" or "Turn In Available Quest"
            titleSource = "unresolved_quest_alternative"
        elseif (action == "complete" or action == "goto") and questID and NS.ResolveQuestObjectiveText then
            local ok, objective = pcall(NS.ResolveQuestObjectiveText, questID, tonumber(element.obj or element.objIndex))
            if ok and objective then title = P.Text(rxp, objective); titleSource = "localized_objective" end
        elseif itemID or spellID then
            subject = Name(rxp, itemID and "item" or "spell", itemID or spellID)
            if subject then title = (prefixes[action] or "Use") .. " "
                .. ((tonumber(element.qty) or 1) > 1 and tostring(element.qty) .. " " or "") .. subject end
            if subject then titleSource = "localized_identity" end
        end
        if title and title:find("%*quest%*") then
            title = P.Text(rxp, element.rawtext)
            titleSource = title and "authored_text" or "none"
        end
        local map = element.zone or linkedMap[element] or groupMap
        local mapInfo = type(map) == "number" and P.Call(C_Map, "GetMapInfo", map)
        local location = mapInfo and mapInfo.name or nil
        local concise, locationRemoved = Common.TrimLocationSuffix(title, location)
        if concise and locationRemoved then
            title, titleSource = concise, titleSource .. "_without_location"
        end
        local npcID = raw.npcID or linkedNPC[element]
        local npc = Name(rxp, "npc", npcID) or P.Text(rxp, raw.npcName or linkedNames[element])
        local authored = P.Text(rxp, element.rawtext) or text
        local tips, suppression = Context(rxp, title, authored, location, npc, action, questName)
        local fact = { ordinal = ordinal, action = action, title = title, tips = tips, suppression = suppression,
            tag = element.tag, role = coordinateTags[element.tag] and "waypoint" or action == "note" and "instruction" or "action",
            coordinateOnly = coordinateOnly, titleSource = titleSource,
            contextSource = #tips > 0 and "distinct_instruction" or "none", questID = questID,
            questCandidates = raw.questCandidates, itemID = itemID, spellID = spellID, npcID = npcID,
            npcName = raw.npcCount<=1 and not ambiguousSubjects[element] and npc or nil,
            objectiveIndex = tonumber(element.obj or element.objIndex), textOnly = element.textOnly, completed = element.completed,
            skip = element.skip, hidden = element.hidden, location = location,
            flightDestination = element.tag == "fly" and P.Text(rxp, element.location) or nil,
            semanticKind = (questID or raw.questCandidates) and "quest" or travel[action] and "travel" or "guide",
            semanticTravelType = travel[action] }
        result.elements[ordinal] = fact
        for _, id in ipairs(raw.questCandidates or {}) do record.dependencies[id] = true end
        for _, id in ipairs({ questID or false, itemID or false, spellID or false, npcID or false }) do
            if id then record.dependencies[id] = true end
        end
        if title and not element.hidden and not element.hideTooltip and not (element.tag == "target" and not text)
            and not (element.parent and not text and (raw.npcID or raw.npcName)) then
            local status = (element.completed or element.skip) and not element.textOnly
            local viewerTips = tips
            local preceding = groups[#groups]
            if npc and (action == "accept" or action == "turnin") and preceding
                and (preceding.action == "note" or preceding.action == "talk")
                and Common.SameText(Common.WithoutCoordinates(preceding.text), "Talk to " .. npc)
            then
                preceding.colorRole = "npc"
                -- The authored NPC instruction is already a Viewer row. Keep
                -- it as navigation context without publishing it twice inline.
                viewerTips = {}
                for _, tip in ipairs(tips) do
                    if not Common.SameText(Common.WithoutCoordinates(tip.text), "Talk to " .. npc) then
                        viewerTips[#viewerTips + 1] = tip
                    end
                end
            end
            local row = { text = title, status = element.skip and not element.textOnly and "skipped" or status and "complete" or "incomplete", kind = "goal", action = action,
                fullHeight = true, tips = viewerTips, questID = questID, questIDs = raw.questCandidates }
            if action == "note" and element.textOnly and #groups > 0 then
                local group = groups[#groups]; group.tips[#group.tips + 1] = { text = title, kind = "tip", status = "incomplete", fullHeight = true }
            else groups[#groups + 1] = row end
        end
    end
    result.rows = Common.GroupTipRows(groups)
    result.title = result.title or (groups[1] and groups[1].text) or "Guide step"
    result.headerRows = result.sticky and Common.PromoteHeaderRow(result.rows, result.title) or result.rows
    record.result = result; cache[index] = record
    return result, true
end

-- ============================================================
-- Target presentation
-- ============================================================

-- Native arrow labels often identify an NPC, while the owning objective says
-- what to do there. Preserve the objective as the primary action and select
-- distinct interaction/procedure text separately, using the same cached facts
-- that feed the Viewer. An arrow label remains primary for a bare waypoint.
function P.ResolveTargetPresentation(rxp, step, waypoint, resolved, fact, waypointOrdinal)
    local arrow = P.Text(rxp, waypoint.arrowtext)
    local arrowSource = arrow and "waypoint_arrowtext" or nil
    if not arrow then
        arrow = P.Text(rxp, step.arrowtext)
        arrowSource = arrow and "step_arrowtext" or nil
    end
    local previous = fact.presentation
    if previous and previous.arrow == arrow and previous.arrowSource == arrowSource
        and previous.waypointOrdinal == waypointOrdinal then return previous end
    local primaryAction = fact.role == "action" and fact.title ~= nil
    local title = primaryAction and fact.title or arrow or fact.title
    local titleSource = primaryAction and fact.titleSource or arrowSource or fact.titleSource
    local context, contextSource
    local function consider(text, source)
        text = Common.TrimLocationSuffix(text, fact.location)
        if not context and text and not Common.RepeatsAction(text, title, fact.location) then
            context, contextSource = text, source
        end
    end
    for _, tip in ipairs(fact.tips) do consider(tip.text, fact.contextSource) end
    if primaryAction then consider(arrow, arrowSource) end
    -- A preceding authored instruction within this waypoint's objective group
    -- can explain the interaction (e.g. kill a named enemy to collect an item).
    -- Do not cross another action or borrow text from another waypoint group.
    if waypointOrdinal and fact.ordinal and waypointOrdinal < fact.ordinal then
        for index = fact.ordinal - 1, waypointOrdinal + 1, -1 do
            local support = resolved.elements[index]
            local element = step.elements[index]
            local companion = element.textOnly and (element.tag == "use" or element.tag == "usespell")
            if support.role == "waypoint" or (support.role == "action" and support.action ~= "talk" and not companion) then break end
            if not support.hidden and not support.skip and not support.completed then
                consider(support.title, "preceding_instruction")
            end
        end
    end
    if fact.questCandidates and #fact.questCandidates > 1 then
        local interaction, quest = Common.DescribeQuestAlternative(fact.action, fact.questID and title or nil, arrow or context)
        if interaction then title, context = interaction, quest end
    end
    previous = { title = title, context = context, titleSource = titleSource,
        contextSource = contextSource or "none", arrow = arrow, arrowSource = arrowSource,
        waypointOrdinal = waypointOrdinal }
    fact.presentation = previous
    return previous
end

-- The common classifier uses the selected destination, not another waypoint's
-- location. Memoize its result on AWP-owned facts so unchanged refreshes do
-- not repeat coordinate/POI checks.
function P.ResolveTravelType(fact, mapID, x, y, title, context)
    if not fact.semanticTravelType then return nil end
    local previous = fact.navigation
    if previous and previous.mapID == mapID and previous.x == x and previous.y == y
        and previous.title == title and previous.context == context then return previous.value end
    local value = P.Call(NS, "ClassifyTravelSemantics", fact.action, mapID, x, y, title, context)
        or fact.semanticTravelType
    fact.navigation = { mapID = mapID, x = x, y = y, title = title, context = context, value = value }
    return value
end

local function MatchesObjective(element, fact, questID, objectiveIndex)
    return fact and (fact.title or fact.role == "action" and (fact.questID or fact.itemID or fact.spellID))
        and not element.completed and not element.skip and not element.hidden
        and (not questID or tonumber(element.questId) == questID)
        and (not objectiveIndex or tonumber(element.obj or element.objIndex) == objectiveIndex)
end

-- ============================================================
-- Waypoint grouping
-- ============================================================

local function StartsWaypointGroup(element, fact, questID, objectiveIndex)
    return not fact.coordinateOnly or type(element.parent) == "table"
        or tonumber(element.questId) ~= questID
        or tonumber(element.obj or element.objIndex) ~= objectiveIndex
end

function P.OwnerOrdinal(step, waypoint, resolved)
    local source = waypoint
    for _ = 1, 8 do
        local ancestor = source.source or source.anchor
        if type(ancestor) ~= "table" then break end
        source = ancestor
    end
    local at, ownerIndex
    local owner = type(waypoint.parent) == "table" and waypoint.parent or source.parent
    for index, element in ipairs(step.elements or {}) do
        if element == waypoint or element == source then at = index end
        if element == owner then ownerIndex = index end
    end
    if ownerIndex then return ownerIndex, "linked_objective", at end
    if not at then return nil, "unassociated_waypoint" end
    local selected = resolved.elements[at]
    if selected.title and selected.titleSource == "localized_objective" then return at, "waypoint_objective", at end
    if selected.title and not selected.coordinateOnly then return at, "authored_waypoint", at end
    local questID = tonumber(source.questId)
    local objectiveIndex = tonumber(source.obj or source.objIndex)
    local instruction, interaction
    for index = at + 1, #step.elements do
        local element, fact = step.elements[index], resolved.elements[index]
        if fact.role == "waypoint" then
            -- Consecutive unlabeled gotos/line points can lead to one action.
            -- Keep the selected coordinates, only share that action's text.
            if instruction or interaction or StartsWaypointGroup(element, fact, questID, objectiveIndex) then break end
        elseif MatchesObjective(element, fact, questID, objectiveIndex) then
            if fact.role == "action" then
                -- RXP's .use/.usespell directives expose buttons and are
                -- explicitly textOnly. They explain an objective, they are
                -- not a completion condition that can take its ownership.
                if element.textOnly and (element.tag == "use" or element.tag == "usespell") then instruction = instruction or index
                elseif fact.action == "talk" then interaction = interaction or index
                else return index, "following_objective", at end
            else instruction = instruction or index end
        end
    end
    if interaction then return interaction, "following_objective", at end
    if instruction then return instruction, "following_instruction", at end
    for index = at - 1, 1, -1 do
        local element, fact = step.elements[index], resolved.elements[index]
        if fact.role == "waypoint" then break end
        if MatchesObjective(element, fact, questID, objectiveIndex) then
            return index, "preceding_objective", at
        end
    end
    return at, "waypoint", at
end
