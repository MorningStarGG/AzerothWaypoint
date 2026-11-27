-- ============================================================
-- QuestieRouter task presentation
-- ============================================================
--
-- Describes QuestieRouter tasks and their objectives for the tracker and
-- destination plaque.

local NS = _G.AzerothWaypointNS
local R, Common = NS.Internal.GuideSourceRuntime, NS.Internal.GuidePresentation
local P = {}
NS.Internal.QuestieRouterPresentation = P
local actions = { pickup = "accept", turnin = "turnin", objective = "complete" }
local objectiveActions = { combat = "kill", collect = "collect", gossip = "talk" }
local objectiveTypes = { monster = "kill", killcredit = "kill", item = "collect", object = "click", event = "complete" }

local function QuestID(value)
    value = R.Scalar(value)
    return type(value) == "number" and value > 0 and value < math.huge and value == math.floor(value) and value or nil
end

function P.TaskKey(task)
    if not task then return nil end
    local ids = {}
    for _, id in ipairs(task.questIds or {}) do
        if type(R.Scalar(id)) == "number" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    -- Match the native task identity, including alternative NPCs for a quest.
    return tostring(task.kind) ..
    ":" .. table.concat(ids, ",") .. ":" .. tostring(R.Scalar(task.npcId or task.npc) or "")
end

local function PlainParagraphs(text)
    if type(text) ~= "string" then return end
    local lines = {}
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\\n", "\n"):gsub("|n", "\n")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = R.PlainText(line) or ""
    end
    local plain = table.concat(lines, "\n"):match("^%s*(.-)%s*$")
    if plain ~= "" then return plain end
end

local function DetailRow(text, action)
    return { text = text, action = action, kind = "tip", status = "passive", fullHeight = true }
end

local function ViewerRows(task, groups, primary, notes, title, action, npc, context)
    local heading = R.PlainText(task.questName)
    if npc and task.kind == "pickup" then
        heading = context
    elseif npc and task.kind == "turnin" then
        heading = "Turn in to " .. npc
    end

    local details = {}
    local description = PlainParagraphs(task.description)
    if description then details[1] = DetailRow(description, action) end
    local tips = {}
    for _, note in ipairs(notes) do
        if note ~= description and not Common.RepeatsAction(note, title) then
            tips[#tips + 1] = DetailRow(note, action)
        end
    end
    if primary then
        primary.tips = tips
        for _, row in ipairs(Common.GroupTipRows(groups)) do details[#details + 1] = row end
    else
        for _, tip in ipairs(tips) do details[#details + 1] = tip end
    end
    return details, heading or (primary and "Guide task" or title)
end

function P.Describe(task, showRows)
    local action = actions[task.kind] or "info"
    local ids, groups, notes = {}, {}, {}
    for _, id in ipairs(task.questIds or {}) do
        id = QuestID(id); if id then ids[#ids + 1] = id end
    end
    local ordinal = 0
    for _, line in ipairs(task.lines or {}) do
        if line.note then
            local text = showRows and PlainParagraphs(line.text) or R.PlainText(line.text)
            if text then notes[#notes + 1] = text end
        else
            ordinal = ordinal + 1
            local text = R.PlainText(line.text)
            if text then
                local id = QuestID(task.kind == "objective" and ids[1] or (task.questIds or {})[ordinal])
                local rowAction = id and action or "info"
                if task.kind == "objective" then
                    rowAction = objectiveActions[line.icon] or "complete"
                elseif not id and line.icon == "gossip" then
                    rowAction = "talk"
                end
                if rowAction == "accept" then
                    text = "Accept '" .. text .. "'"
                elseif rowAction == "turnin" then
                    text = "Turn in '" .. text .. "'"
                end
                groups[#groups + 1] = {
                    text = text,
                    action = rowAction,
                    kind = "goal",
                    fullHeight = true,
                    status = line.done and "complete" or "incomplete",
                    questID = id
                }
            end
        end
    end
    local primary = groups[1]
    for _, row in ipairs(groups) do if row.status ~= "complete" then
            primary = row; break
        end end
    local title = primary and primary.text or R.PlainText(task.questName) or "Guide task"
    local point = task.point
    local objectiveText = task.kind == "objective" and point and R.PlainText(point.objText)
    if objectiveText then
        title = objectiveText
        local have, need = R.Scalar(point.have), R.Scalar(point.need)
        if type(have) == "number" and type(need) == "number" and have >= 0 and need > 0
            and have < math.huge and need < math.huge and (need > 1 or point.objType == "monster" or point.objType == "item") then
            title = string.format("%s: %d/%d", title, have, need)
        end
        action = objectiveTypes[point.objType] or "complete"
    end
    if #ids > 1 and #ids == #groups and task.kind ~= "objective" then
        title = (action == "accept" and "Accept " or "Turn in ") .. #ids .. " quests"
    end
    if #ids == 0 then action = primary and primary.action or "info" end
    local npc = R.PlainText(task.npc)
    local npcID = task.npcId or point and point.npcId
    local context = npc and ((npcID and "Talk to " or "Interact with ") .. npc) or R.PlainText(notes[1])
    if context and Common.SameText(context, title) then context = nil end
    local rows, heading
    if showRows then
        rows, heading = ViewerRows(task, groups, primary, notes, title, action, npc, context)
    end
    return title, context, rows, ids, action, heading, groups
end

-- ============================================================
-- Quest state and destination text
-- ============================================================

local function NativeQuestState(task)
    -- The native planner builds turn-in groups from ready quests in the log.
    if task.kind == "turnin" then return true, true end
end

function P.Destination(task, title, context, groups, ids, action, key)
    local point = task.point
    if task.kind == "objective" then
        -- Describe already chose the current objective (including its live
        -- count). The quest heading belongs to the tracker, not over the
        -- active action on the arrow and plaque.
        return title, context, ids[1], key .. ":" .. tostring(point.objectiveIndex or "")
    end
    if #ids == 0 or (action ~= "accept" and action ~= "turnin") then
        return title, context, nil, key
    end

    local candidates = {}
    for _, row in ipairs(groups) do
        if row.questID and row.status ~= "complete" then candidates[#candidates + 1] = row.questID end
    end
    local id = NS.Internal.GuideQuestSelection.Select(action, candidates, false, NativeQuestState, task, true)
    local verb = action == "accept" and "Accept" or "Turn in"
    title = verb .. (#ids == 1 and " quest" or " quests")
    for _, row in ipairs(groups) do
        if id and row.questID == id then
            title = row.text; break
        end
    end
    -- Membership changes after every hand-in. Navigation still belongs to
    -- the same interaction at the same NPC/object, the chooser owns TaskKey.
    local actor = task.npcId or point.npcId or R.PlainText(task.npc)
    local stop = actor and task.kind .. ":" .. tostring(actor) or key
    return title, context, id, stop, candidates
end
