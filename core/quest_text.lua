-- ============================================================
-- Quest titles and objective text
-- ============================================================
--
-- Combines live quest-log progress and quest data into the titles and
-- objective text guides display.

local NS = _G.AzerothWaypointNS

local function NormalizeText(value)
    if (issecretvalue and issecretvalue(value)) or type(value) ~= "string" then
        return nil
    end
    value = value:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return nil
    end
    return value
end

local function NormalizeQuestID(value)
    value = NS.Internal.QuestData.Public(value)
    if type(value) ~= "number" and type(value) ~= "string" then return end
    return NS.Internal.QuestData.ID(tonumber(value))
end

local function NormalizeObjectiveIndex(value)
    return NormalizeQuestID(value)
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
end

-- ============================================================
-- Live quest progress
-- ============================================================

local function GetQuestObjectives(questID)
    if type(C_QuestLog) ~= "table" or type(C_QuestLog.GetQuestObjectives) ~= "function" then
        return nil
    end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if ok and type(objectives) == "table" then
        return objectives
    end
end

local function IsQuestInLog(questID)
    if type(C_QuestLog) ~= "table" then
        return nil
    end

    if type(C_QuestLog.IsOnQuest) == "function" then
        local ok, active = pcall(C_QuestLog.IsOnQuest, questID)
        if ok and type(active) == "boolean" then
            return active
        end
    end

    if type(C_QuestLog.GetLogIndexForQuestID) == "function" then
        local ok, logIndex = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
        if ok and type(logIndex) == "number" then
            return logIndex > 0
        end
    end

    return nil
end

local function IsQuestReadyForTurnIn(questID)
    return SafeCall(C_QuestLog and C_QuestLog.ReadyForTurnIn, questID)
end

-- Guide alternatives need to distinguish missing client data from a known
-- negative. A repeatable in the current log may also have a reward history.
function NS.ReadGuideQuestState(questID)
    local active = IsQuestInLog(questID)
    local ready = IsQuestReadyForTurnIn(questID)
    if ready == nil and active then ready = SafeCall(C_QuestLog.IsComplete, questID) end
    return active, ready, SafeCall(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, questID)
end

local function QuoteQuestAction(action, title)
    title = NormalizeText(title)
    if not title then
        return nil
    end
    return action .. " '" .. title .. "'"
end

-- ============================================================
-- Quest titles and cached presentation
-- ============================================================

function NS.ResolveQuestTitle(questID)
    questID = NormalizeQuestID(questID)
    if not questID then
        return nil
    end

    local title = type(C_QuestLog) == "table"
        and SafeCall(C_QuestLog.GetTitleForQuestID, questID)
        or nil
    title = NormalizeText(title)
    if title then
        return title
    end

    title = type(C_TaskQuest) == "table"
        and SafeCall(C_TaskQuest.GetQuestInfoByQuestID, questID)
        or nil
    title = NormalizeText(title)
    if title then return title end
    local data = NS.Internal and NS.Internal.QuestData
    return data and data.GetQuestName(questID) or nil
end

-- Quest state is owned by the client. Optional databases only supply identities.
local presentationEpoch, questEpochs = 0, {}
local presentations = setmetatable({}, { __mode = "k" })
local defaultOwners, emptyContext = {}, {}

function NS.InvalidateQuestPresentation(questID)
    local data = NS.Internal and NS.Internal.QuestData
    if data then data.ClearNames(questID) end
    if type(questID) == "number" and questID > 0 then
        questEpochs[questID] = (questEpochs[questID] or 0) + 1
    else
        presentationEpoch = presentationEpoch + 1
        questEpochs, defaultOwners = {}, {}
    end
end

function NS.ResolveQuestPresentation(questID, fallbackTitle, owner)
    questID = NormalizeQuestID(questID)
    if not questID then return nil end
    if type(owner) ~= "table" then
        defaultOwners[questID] = defaultOwners[questID] or {}
        owner = defaultOwners[questID]
    end
    local context = owner.questContext or owner.meta and owner.meta.questContext or emptyContext
    if type(context) ~= "table" then context = emptyContext end
    local data = NS.Internal and NS.Internal.QuestData
    local public = data.Public
    local contextAction, contextID = public(context.action), public(context.questID)
    local entityKind, entityID = public(context.entityKind), public(context.entityID)
    local objectiveIndex, objectiveType = public(context.objectiveIndex), public(context.objectiveType)
    local identity = owner.identity or owner.meta and owner.meta.identity
    local questSource = identity and public(identity.questSource)
    local selection = NS.Internal.GuideQuestSelection
    local dialogRevision = selection and selection.GetDialogRevision() or 0
    local cached = presentations[owner]
    local revision = questEpochs[questID] or 0
    if cached and cached.questID == questID and cached.epoch == presentationEpoch and cached.revision == revision
        and cached.fallback == fallbackTitle and cached.context == context
        and cached.contextAction == contextAction and cached.contextID == contextID
        and cached.contextKind == entityKind and cached.contextEntity == entityID
        and cached.contextIndex == objectiveIndex and cached.contextType == objectiveType
        and cached.questSource == questSource and cached.dataGeneration == data.generation
        and cached.dialogRevision == dialogRevision then
        return cached
    end
    local ready, active = IsQuestReadyForTurnIn(questID), IsQuestInLog(questID)
    local offer = questSource == "quest_offer"
    local action = ready and "turnin" or active and "complete" or (contextAction == "accept" or offer) and "accept" or
        nil
    local facts = data and data.GetFacts(questID, context, action) or nil
    local name = NS.ResolveQuestTitle(questID)
    local title = name and action and
        QuoteQuestAction(action == "turnin" and "Turn in" or action == "accept" and "Accept" or "Complete", name)
        or NormalizeText(fallbackTitle) or name
    local objective, index
    if active and not ready then
        local objectives = GetQuestObjectives(questID)
        index = NormalizeObjectiveIndex(objectiveIndex)
        objective = objectives and index and objectives[index]
        if not objective and objectives then
            for i, candidate in ipairs(objectives) do
                if candidate.finished ~= true then
                    objective, index = candidate, i; break
                end
            end
        end
    end
    local detail = facts and facts.context
    local objectiveText = objective and NormalizeText(objective.text or objective.description)
    if objectiveText then
        -- A selected objective owns its text, a quest-wide point retains the quest title.
        if objectiveIndex then title = objectiveText else detail = objectiveText end
    elseif active and not ready and objectiveIndex and facts and facts.name then
        local verb = objectiveType == "monster" and "Kill " or objectiveType == "item" and "Collect "
            or objectiveType == "object" and "Interact with "
        if verb then title = verb .. facts.name end
    elseif ready and not detail then
        detail = "Ready to turn in"
    end
    if detail == title then detail = nil end
    cached = {
        questID = questID,
        epoch = presentationEpoch,
        revision = revision,
        fallback = fallbackTitle,
        context = context,
        title = title,
        subtext = detail,
        action = action,
        objectiveIndex = index,
        contextAction = contextAction,
        contextID = contextID,
        contextKind = entityKind,
        contextEntity = entityID,
        contextIndex = objectiveIndex,
        contextType = objectiveType,
        questSource = questSource,
        dataGeneration = data.generation,
        dialogRevision = dialogRevision,
        provenance = facts and facts.provenance or "client",
        entityKind = facts and facts.entityKind,
        entityID = facts and facts.entityID
    }
    presentations[owner] = cached
    return cached
end

function NS.IsQuestInLog(questID)
    questID = NormalizeQuestID(questID)
    return questID and IsQuestInLog(questID) or false
end

function NS.IsQuestReadyForTurnIn(questID)
    questID = NormalizeQuestID(questID)
    return questID and IsQuestReadyForTurnIn(questID) or false
end

-- ============================================================
-- Objective text
-- ============================================================

function NS.ResolveQuestActionTitle(questID, fallbackTitle)
    questID = NormalizeQuestID(questID)
    if not questID then
        return NormalizeText(fallbackTitle)
    end

    local title = NormalizeText(fallbackTitle) or NS.ResolveQuestTitle(questID)
    if not title then
        return nil
    end

    if IsQuestReadyForTurnIn(questID) then
        return QuoteQuestAction("Turn in", title)
    end
    if IsQuestInLog(questID) then
        return QuoteQuestAction("Complete", title)
    end
    return QuoteQuestAction("Accept", title)
end

function NS.ResolveQuestObjectiveText(questID, objectiveIndex)
    questID = NormalizeQuestID(questID)
    objectiveIndex = NormalizeObjectiveIndex(objectiveIndex)
    if not questID or not objectiveIndex then
        return nil
    end

    local objectives = GetQuestObjectives(questID)
    local objective = objectives and objectives[objectiveIndex] or nil
    if type(objective) ~= "table" then
        return nil
    end

    return NormalizeText(objective.text or rawget(objective, "description"))
end

function NS.ResolveFirstUnfinishedQuestObjectiveText(questID)
    questID = NormalizeQuestID(questID)
    if not questID then
        return nil
    end

    if IsQuestReadyForTurnIn(questID) then
        return "Ready to turn in"
    end

    if not IsQuestInLog(questID) then
        return nil
    end

    local objectives = GetQuestObjectives(questID)
    if type(objectives) ~= "table" then
        return nil
    end

    for _, objective in ipairs(objectives) do
        if type(objective) == "table" and objective.finished ~= true then
            local text = NormalizeText(objective.text or rawget(objective, "description"))
            if text then
                return text
            end
        end
    end
end
