-- ============================================================
-- Guide quest selection
-- ============================================================
--
-- Matches visible quest dialogue to guide candidates and selects the quest the
-- guide should present.

local NS = _G.AzerothWaypointNS
local Selection = {}
NS.Internal.GuideQuestSelection = Selection

local function GetDirectQuestFrameDialogEntry(event)
    local questID = type(GetQuestID) == "function" and GetQuestID() or nil
    if type(questID) ~= "number" or questID <= 0 then
        return nil
    end

    local title = nil
    local questInfoTitleHeader = rawget(_G, "QuestInfoTitleHeader")
    if questInfoTitleHeader and type(questInfoTitleHeader.GetText) == "function" then
        title = questInfoTitleHeader:GetText()
    end
    if not title and type(C_QuestLog) == "table" and type(C_QuestLog.GetTitleForQuestID) == "function" then
        title = C_QuestLog.GetTitleForQuestID(questID)
    end

    local kind = nil
    local questFrame = rawget(_G, "QuestFrame")
    local questFrameProgressPanel = rawget(_G, "QuestFrameProgressPanel")
    local questFrameRewardPanel = rawget(_G, "QuestFrameRewardPanel")
    local questFrameCompleteQuestButton = rawget(_G, "QuestFrameCompleteQuestButton")
    local questFrameCompleteButton = rawget(_G, "QuestFrameCompleteButton")
    local questFrameAcceptButton = rawget(_G, "QuestFrameAcceptButton")

    if event == "QUEST_DETAIL" then
        kind = "accept"
    elseif event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        kind = "turnin"
    elseif questFrame and questFrame.DetailPanel and questFrame.DetailPanel:IsShown() then
        kind = "accept"
    elseif questFrameAcceptButton and questFrameAcceptButton:IsVisible() then
        kind = "accept"
    elseif (questFrameProgressPanel and questFrameProgressPanel:IsShown())
        or (questFrameRewardPanel and questFrameRewardPanel:IsShown())
        or (questFrameCompleteQuestButton and questFrameCompleteQuestButton:IsVisible())
        or (questFrameCompleteButton and questFrameCompleteButton:IsVisible())
    then
        kind = "turnin"
    end

    if kind == nil and type(C_QuestLog) == "table" and type(C_QuestLog.GetLogIndexForQuestID) == "function" then
        local logIndex = tonumber(C_QuestLog.GetLogIndexForQuestID(questID) or 0) or 0
        kind = logIndex > 0 and "turnin" or "accept"
    end

    if not kind then
        return nil
    end

    local complete = event == "QUEST_COMPLETE"
    if not complete and kind == "turnin" and type(C_QuestLog) == "table" and type(C_QuestLog.IsComplete) == "function" then
        complete = C_QuestLog.IsComplete(questID) == true
    end

    return kind, questID, title, complete
end

local function VisitQuestList(visit)
    if type(C_GossipInfo) == "table" then
        if type(C_GossipInfo.GetAvailableQuests) == "function" then
            local available = C_GossipInfo.GetAvailableQuests() or {}
            for _, info in ipairs(available) do
                visit("gossip", "accept", info.questID, info.title, false)
            end
        end
        if type(C_GossipInfo.GetActiveQuests) == "function" then
            local active = C_GossipInfo.GetActiveQuests() or {}
            for _, info in ipairs(active) do
                visit("gossip", "turnin", info.questID, info.title, info.isComplete)
            end
        end
    end

    if type(GetNumAvailableQuests) == "function" and type(GetAvailableTitle) == "function" then
        for i = 1, GetNumAvailableQuests() or 0 do
            local questID = nil
            if type(GetAvailableQuestInfo) == "function" then
                local _, _, _, _, infoQuestID = GetAvailableQuestInfo(i)
                questID = infoQuestID
            end
            visit("available", "accept", questID, GetAvailableTitle(i), false)
        end
    end

    if type(GetNumActiveQuests) == "function" and type(GetActiveTitle) == "function" then
        for i = 1, GetNumActiveQuests() or 0 do
            local questID = nil
            if type(GetActiveQuestID) == "function" then
                questID = GetActiveQuestID(i)
            end
            visit("active", "turnin", questID, GetActiveTitle(i), false)
        end
    end
end

-- ============================================================
-- Matching live quest dialogue
-- ============================================================

-- Without a specific event, Zygor collects both lists and the open quest
-- page for its live evidence and cache signature.
function Selection.VisitDialog(visit, event)
    local listing = event == "GOSSIP_SHOW" or event == "QUEST_GREETING"
    if not event or listing then VisitQuestList(visit) end
    if not listing then
        local kind, questID, title, complete = GetDirectQuestFrameDialogEntry(event)
        if kind then visit("direct", kind, questID, title, complete) end
    end
end

local watched = {}
local dialog
local dialogRevision = 0

function Selection.GetDialogRevision()
    return dialogRevision
end

-- A live actor is evidence only for the quest page actually being offered
-- by that NPC. Remote completion and unrelated targets cannot name a finisher.
function Selection.GetVerifiedQuestActor(id, action)
    if not dialog or not dialog[action] or dialog[action][id] ~= 2 then return end
    local data = NS.Internal.QuestData
    if not data or type(GetQuestID) ~= "function" then return end
    local ok, current = pcall(GetQuestID)
    if not ok or data.ID(current) ~= id then return end
    local manager = C_PlayerInteractionManager
    local interaction = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.QuestGiver
    if not manager or not interaction or type(manager.IsInteractingWithNpcOfType) ~= "function" then return end
    local interacting, result = pcall(manager.IsInteractingWithNpcOfType, interaction)
    if not interacting or data.Public(result) ~= true or type(UnitGUID) ~= "function" then return end
    local read, guid = pcall(UnitGUID, "npc")
    guid = read and data.Public(guid) or nil
    if type(guid) ~= "string" then return end
    local kind, npcID = guid:match("^(%a+)%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return end
    npcID = data.ID(tonumber(npcID))
    if not npcID then return end
    local named, name = false, nil
    if type(UnitName) == "function" then named, name = pcall(UnitName, "npc") end
    return npcID, named and data.Name(name) or nil
end

function Selection.Watch(api)
    watched[#watched + 1] = api
end

local function ReadDialog(event, previous)
    local evidence = { accept = {}, turnin = {}, listedAccept = {} }
    Selection.VisitDialog(function(source, action, id, _, ready)
        if type(id) ~= "number" or id <= 0 then return end
        if action == "accept" then
            if source ~= "direct" then
                evidence.listedAccept[id] = true
            elseif previous and previous.listedAccept[id] then
                evidence.listedAccept = previous.listedAccept
            end
        end
        if action == "turnin" and not ready then return end
        evidence[action][id] = source == "direct" and 2 or 1
    end, event)
    return evidence
end

local dialogOpen = {
    GOSSIP_SHOW = true,
    QUEST_GREETING = true,
    QUEST_DETAIL = true,
    QUEST_PROGRESS = true,
    QUEST_COMPLETE = true
}

-- ============================================================
-- Refresh and selection
-- ============================================================

-- Only refresh stops whose candidate IDs occur in the old/new dialog or in
-- the acceptance/reward event. Native plan updates cover ordinary progress.
function Selection.OnDialogEvent(event, questID)
    local previous = dialog
    dialog = dialogOpen[event] and ReadDialog(event, previous) or nil
    dialogRevision = dialogRevision + 1
    for _, api in ipairs(watched) do
        local stop = api.GetSnapshot()
        if stop.handoffQuestIDs then
            local action = stop.handoffAction
            for _, id in ipairs(stop.handoffQuestIDs) do
                if id == questID or (previous and previous[action][id]) or (dialog and dialog[action][id]) then
                    api.Schedule("guide_quest_dialog")
                    break
                end
            end
        end
    end
end

-- Ordered stops keep the first actionable sibling. Dialog specificity only
-- breaks ties for mutually exclusive variants. Unknown readiness can supply
-- a fallback, but cannot outrank a known ready turn-in.
function Selection.Select(action, ids, alternatives, nativeState, owner, useDialog)
    local offers = useDialog and dialog and dialog[action]
    -- Only a quest list containing one of this stop's candidates describes
    -- what is available here. Opening an individual quest isn't a full list.
    local listed
    if action == "accept" and offers then
        for _, id in ipairs(ids) do
            if dialog.listedAccept[id] then
                listed = dialog.listedAccept; break
            end
        end
    end
    local bestID, bestRank, tied = nil, 0, false
    for _, id in ipairs(ids) do
        local active, ready, rewarded = NS.ReadGuideQuestState(id)
        local nativeActive, nativeReady = nativeState(owner, id)
        if active == nil then active = nativeActive end
        if ready == nil then ready = nativeReady end
        local offer = offers and offers[id]
        local rank = 0
        if action == "accept" then
            if not active and (not rewarded or offer) and (not listed or listed[id]) then
                rank = alternatives and (offer or 0) or 2
            end
        elseif offer or (active ~= false and ready == true) then
            rank = alternatives and (offer or 0) + 2 or 2
        elseif ready ~= false and active ~= false and (active or not rewarded) then
            rank = (not alternatives or active) and 1 or 0
        end
        if rank > bestRank then
            bestID, bestRank, tied = id, rank, false
        elseif rank == bestRank then
            tied = true
        end
    end
    if alternatives and tied then return nil end
    return bestID
end
