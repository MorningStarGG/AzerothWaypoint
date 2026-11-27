-- ============================================================
-- Zygor quest dialogue context
-- ============================================================
--
-- Matches the game's current quest dialogue to Zygor goal facts for the
-- resolver.

local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

local M = NS.Internal.GuideResolver
local P = M.Private

local NormalizeText = P.NormalizeText
local IsQuestActionFact = P.IsQuestActionFact

-- ============================================================
-- Live dialog quest detection
-- ============================================================

local _dialogSignatureParts = {}

local function AddDialogSignatureEntry(n, source, kind, questID, title, complete)
    title = NormalizeText(title)
    questID = tonumber(questID or 0) or 0
    if not title and questID <= 0 then
        return n
    end

    n = n + 1
    _dialogSignatureParts[n] = tostring(source or "")
        .. "\030" .. tostring(kind or "")
        .. "\030" .. tostring(questID or "")
        .. "\030" .. tostring(title or "")
        .. "\030" .. tostring(complete == true)
    return n
end

local VisitDialog = NS.Internal.GuideQuestSelection.VisitDialog

local function GetLiveDialogQuestSignature()
    local n = 0
    VisitDialog(function(source, kind, id, title, complete)
        n = AddDialogSignatureEntry(n, source, kind, id, title, complete)
    end)
    local signature = table.concat(_dialogSignatureParts, "\031", 1, n)
    for i = 1, n do
        _dialogSignatureParts[i] = nil
    end
    return signature
end

local function CollectLiveDialogQuestEntries()
    local entries = {}
    local directEntries = {}
    local seenEntries = {}
    local seenDirectEntries = {}

    local function addEntry(target, seen, kind, questID, title, complete)
        title = NormalizeText(title)
        questID = tonumber(questID or 0) or 0
        if not title and questID <= 0 then
            return
        end

        local key = table.concat({
            tostring(kind or ""),
            tostring(questID or ""),
            tostring(title or ""),
            tostring(complete == true),
        }, "|")
        if seen[key] then
            return
        end

        seen[key] = true
        target[#target + 1] = {
            kind = kind,
            questID = questID,
            title = title,
            isComplete = complete == true,
        }
    end

    VisitDialog(function(source, kind, id, title, complete)
        if source == "direct" then
            addEntry(directEntries, seenDirectEntries, kind, id, title, complete)
        else
            addEntry(entries, seenEntries, kind, id, title, complete)
        end
    end)

    for _, entry in ipairs(directEntries) do
        addEntry(entries, seenEntries, entry.kind, entry.questID, entry.title, entry.isComplete)
    end

    return entries, directEntries
end

-- ============================================================
-- Matching helpers
-- ============================================================

local function DoesLiveEntryMatchFact(fact, entry)
    if type(fact) ~= "table" or type(entry) ~= "table" or entry.kind ~= fact.action then
        return false
    end

    if fact.questid and entry.questID then
        return fact.questid == entry.questID
    end

    if (fact.questid == nil or entry.questID == nil)
        and fact.questTitle
        and entry.title
    then
        return fact.questTitle == entry.title
    end

    return false
end

local function MatchEntriesToFacts(actionFacts, liveEntries)
    local matchedFact = nil
    local matchedCount = 0
    for _, fact in ipairs(actionFacts or {}) do
        local factMatched = false
        for _, entry in ipairs(liveEntries or {}) do
            if DoesLiveEntryMatchFact(fact, entry) then
                factMatched = true
                break
            end
        end

        if factMatched then
            matchedCount = matchedCount + 1
            if matchedCount == 1 then
                matchedFact = fact
            else
                return nil, "ambiguous"
            end
        end
    end

    if matchedFact then
        return matchedFact, "unique"
    end

    return nil, "none"
end

local function MatchEntriesToSingleFact(fact, liveEntries)
    for _, entry in ipairs(liveEntries or {}) do
        if DoesLiveEntryMatchFact(fact, entry) then
            return fact
        end
    end

    return nil
end

local function BuildFactAnnotation(fact, entries, directEntries)
    if type(fact) ~= "table"
        or fact.visible ~= true
        or fact.suppressed == true
        or not IsQuestActionFact(fact)
        or (fact.action ~= "accept" and fact.action ~= "turnin")
    then
        return nil
    end

    local questID = type(fact.questid) == "number" and fact.questid > 0 and fact.questid or nil
    local directMatch = MatchEntriesToSingleFact(fact, directEntries)
    local dialogMatch = directMatch or MatchEntriesToSingleFact(fact, entries)

    local annotation = {
        secondaryEligible = true,
        matchKind = nil,
        reason = nil,
    }

    if directMatch then
        annotation.matchKind = "direct_match"
    elseif dialogMatch then
        annotation.matchKind = "dialog_match"
    end

    if fact.action == "turnin" then
        if questID == nil then
            annotation.reason = "no_quest_id"
            return annotation
        end

        if annotation.matchKind then
            annotation.reason = annotation.matchKind
            return annotation
        end

        annotation.secondaryEligible = false
        annotation.reason = "turnin_not_offered"
        return annotation
    end

    if questID == nil then
        annotation.reason = "no_quest_id"
        return annotation
    end

    if type(C_QuestLog) == "table" and type(C_QuestLog.GetLogIndexForQuestID) == "function" then
        local logIndex = tonumber(C_QuestLog.GetLogIndexForQuestID(questID) or 0) or 0
        if logIndex > 0 then
            annotation.secondaryEligible = false
            annotation.reason = "accept_in_log"
            return annotation
        end
    end

    annotation.reason = annotation.matchKind or "accept_available"
    return annotation
end

local _matchCacheKeyParts = {}

local function BuildMatchCacheKey(actionFacts)
    local n = 0
    for _, fact in ipairs(actionFacts or {}) do
        n = n + 1
        _matchCacheKeyParts[n] = tostring(type(fact) == "table" and fact.index or "?")
    end
    local key = table.concat(_matchCacheKeyParts, ",", 1, n)
    for i = 1, n do
        _matchCacheKeyParts[i] = nil
    end
    return key
end

-- ============================================================
-- Context
-- ============================================================

local function BuildLiveCurrentnessContext(facts)
    local entries, directEntries = CollectLiveDialogQuestEntries()
    local annotationsByIndex = {}

    for _, fact in ipairs(facts or {}) do
        local annotation = BuildFactAnnotation(fact, entries, directEntries)
        if annotation then
            annotationsByIndex[fact.index] = annotation
        end
    end

    return {
        entries = entries,
        directEntries = directEntries,
        annotationsByIndex = annotationsByIndex,
        matchedLiveFactIndex = nil,
        matchedLiveReason = nil,
        _matchCache = {},
    }
end

local function ResolveMatchedLiveFact(liveCurrentness, actionFacts)
    if type(liveCurrentness) ~= "table" then
        return nil, {}, nil
    end

    local cacheKey = BuildMatchCacheKey(actionFacts)
    local cached = liveCurrentness._matchCache[cacheKey]
    if cached == nil then
        local matchedFact, matchState = MatchEntriesToFacts(actionFacts, liveCurrentness.directEntries)
        local matchReason = nil

        if matchedFact then
            matchReason = "direct_match"
        elseif matchState == "ambiguous" then
            matchReason = "ambiguous_live_match"
        else
            matchedFact, matchState = MatchEntriesToFacts(actionFacts, liveCurrentness.entries)
            if matchedFact then
                matchReason = "dialog_match"
            elseif matchState == "ambiguous" then
                matchReason = "ambiguous_live_match"
            end
        end

        cached = {
            fact = matchedFact,
            reason = matchReason,
        }
        liveCurrentness._matchCache[cacheKey] = cached
    end

    liveCurrentness.matchedLiveFactIndex = cached.fact and cached.fact.index or nil
    liveCurrentness.matchedLiveReason = cached.reason
    return cached.fact, liveCurrentness.entries, cached.reason
end

local function SelectDirectLiveActionFact(liveCurrentness, actionFacts)
    if type(liveCurrentness) ~= "table" then
        return nil, nil
    end

    local matchedFact, matchState = MatchEntriesToFacts(actionFacts, liveCurrentness.directEntries)
    if matchedFact then
        return matchedFact, "direct_match"
    end
    if matchState == "ambiguous" then
        return nil, "ambiguous_live_match"
    end

    return nil, nil
end

-- ============================================================
-- Exports
-- ============================================================

P.BuildLiveCurrentnessContext = BuildLiveCurrentnessContext
P.GetLiveDialogQuestSignature = GetLiveDialogQuestSignature
P.ResolveMatchedLiveFact = ResolveMatchedLiveFact
P.SelectDirectLiveActionFact = SelectDirectLiveActionFact
