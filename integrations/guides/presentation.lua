-- ============================================================
-- Guide destination snapshots
-- ============================================================
--
-- Builds the guide destination snapshot used for navigation text, icons and
-- quest context.

local NS = _G.AzerothWaypointNS

NS.Internal = NS.Internal or {}
local Presentation = {}
NS.Internal.GuidePresentation = Presentation

function Presentation.NormalizeText(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
        :gsub("%s+", " "):match("^%s*(.-)%s*$")
    return text ~= "" and text or nil
end

function Presentation.SameText(a, b)
    a, b = Presentation.NormalizeText(a), Presentation.NormalizeText(b)
    return a ~= nil and b ~= nil and a:lower() == b:lower()
end

-- Providers supply the subject of their selected native goal, never a name
-- parsed out of instructions or an arbitrary quest giver from a database.
-- Scalars keep provider snapshots reusable without nested-table churn.
function Presentation.SetDestinationContext(target, name, kind, action, questID, purpose, questTitle)
    name, purpose = Presentation.NormalizeText(name), Presentation.NormalizeText(purpose)
    if action == "accept" or action == "turnin" then
        questTitle = Presentation.NormalizeText(questTitle)
            or NS.ResolveQuestTitle and Presentation.NormalizeText(NS.ResolveQuestTitle(questID))
        if questTitle then purpose = (action == "accept" and "Accept '" or "Turn in '") .. questTitle .. "'" end
    end
    target.destinationName, target.destinationKind = name, name and kind or nil
    target.destinationAction, target.destinationPurpose = action, purpose
end

local function FormatCoordinateSubtext(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return string.format("x: %.1f, y: %.1f", x * 100, y * 100)
end

function Presentation.DestinationSubtext(text, x, y)
    if text then return text, "instruction" end
    if NS.GetWorldOverlaySetting and NS.GetWorldOverlaySetting("worldOverlayShowCoordinateFallback") then
        local coordinates = FormatCoordinateSubtext(x, y)
        if coordinates then return coordinates, "coordinate_fallback" end
    end
end

-- A choice at a known NPC has the same subject before and after the game
-- identifies a specific quest. Leave other authored instructions intact.
function Presentation.DescribeQuestAlternative(action, questTitle, context)
    if type(context) ~= "string" or not context:match("^Talk to [^\r\n]+$") then return nil end
    local available = action == "accept" and "Accept Available Quest" or "Turn In Available Quest"
    return context, questTitle or available
end

function Presentation.WithoutCoordinates(text)
    if type(text) ~= "string" then return nil end
    text = Presentation.NormalizeText(text:gsub("%([%d.]+,%s*[%d.]+%)", ""))
    return text and text:gsub("%.$", "") or nil
end

function Presentation.LocationOnly(text, location)
    return type(text) == "string" and type(location) == "string" and location ~= "" and
        (Presentation.SameText(text, location)
            or Presentation.SameText(text, "in " .. location) or Presentation.SameText(text, "at " .. location))
end

local locationPrefixes = { " in ", " at " }
function Presentation.TrimLocationSuffix(text, location)
    if type(text) ~= "string" or type(location) ~= "string" or location == "" then return text, false end
    local clean = Presentation.WithoutCoordinates(text)
    if Presentation.LocationOnly(clean, location) then return nil, true end
    for _, prefix in ipairs(locationPrefixes) do
        local suffix = prefix .. location
        if clean and #clean > #suffix and Presentation.SameText(clean:sub(- #suffix), suffix) then
            return Presentation.NormalizeText(clean:sub(1, #clean - #suffix)), true
        end
    end
    return text, false
end

function Presentation.RepeatsAction(text, title, location)
    text, title = Presentation.WithoutCoordinates(text), Presentation.WithoutCoordinates(title)
    text = Presentation.TrimLocationSuffix(text, location)
    title = Presentation.TrimLocationSuffix(title, location)
    return Presentation.SameText(text, title)
end

-- ============================================================
-- Quest semantics and destination snapshots
-- ============================================================

function Presentation.BuildSemanticInfo(kind, travelType, questID)
    questID = type(questID) == "number" and questID > 0 and questID or nil
    travelType = NS.NormalizeTravelType(travelType)
    kind = type(kind) == "string" and kind or nil
    if travelType then kind = "travel" elseif questID and kind == nil then kind = "quest" end
    if not kind and not travelType and not questID then return nil end
    return { semanticKind = kind, semanticTravelType = travelType, semanticQuestID = questID }
end

local signatureParts = {}
function Presentation.UpdateSnapshotContentSig(snapshot)
    if type(snapshot) ~= "table" then return end
    signatureParts[1] = tostring(snapshot.mirrorTitle or "")
    signatureParts[2] = tostring(snapshot.pinpointSubtext or "")
    signatureParts[3] = tostring(snapshot.clusterKind or "")
    signatureParts[4] = tostring(snapshot.subtextReason or "")
    signatureParts[5] = tostring(snapshot.semanticKind or "")
    signatureParts[6] = tostring(snapshot.semanticTravelType or "")
    signatureParts[7] = tostring(snapshot.semanticQuestID or "")
    snapshot.contentSig = table.concat(signatureParts, "\031", 1, 7)
end

function Presentation.BuildSnapshot(rawTitle, title, subtext, clusterKind, reason, headerFact, matchedIndex, semantics)
    local snapshot = {
        rawArrowTitle = rawTitle,
        mirrorTitle = title or rawTitle,
        pinpointSubtext = subtext,
        clusterKind = clusterKind,
        subtextReason = reason,
        headerGoalNum = headerFact and headerFact.index,
        matchedLiveGoalNum = matchedIndex,
        resolverBypassed = false,
        semanticKind = semantics and semantics.semanticKind,
        semanticTravelType = semantics and semantics.semanticTravelType,
        semanticQuestID = semantics and semantics.semanticQuestID,
    }
    Presentation.UpdateSnapshotContentSig(snapshot)
    return snapshot
end

function Presentation.ApplyRoutePolicy(snapshot, context, fallbackAllowed)
    if type(snapshot) ~= "table" or type(context) ~= "table" or context.kind ~= "route" then return snapshot end
    local travelType = type(context.routeTravelType) == "string" and context.routeTravelType or nil
    local semanticTravel = type(snapshot.semanticTravelType) == "string" and snapshot.semanticTravelType or nil
    if context.legKind == "carrier" and semanticTravel and snapshot.rawArrowTitle
        and snapshot.mirrorTitle ~= snapshot.rawArrowTitle
    then
        snapshot.mirrorTitle = snapshot.rawArrowTitle
        Presentation.UpdateSnapshotContentSig(snapshot)
    end
    if context.legKind == "carrier" and snapshot.pinpointSubtext ~= nil
        and not NS.IsInstanceRouteTravelType(travelType)
        and (semanticTravel ~= nil or snapshot.semanticKind == "quest")
    then
        snapshot.pinpointSubtext = nil
        snapshot.subtextReason = "carrier_leg_suppressed"
        snapshot.routePresentationAllowed = false
        Presentation.UpdateSnapshotContentSig(snapshot)
        return snapshot
    end
    if travelType ~= nil then
        snapshot.semanticKind = "travel"
        snapshot.semanticTravelType = travelType
        Presentation.UpdateSnapshotContentSig(snapshot)
    end
    snapshot.routePresentationAllowed = fallbackAllowed ~= false
    return snapshot
end

-- Group authored tips, automatic wrapping never creates additional tip units.
-- Preserve all provider metadata, including checkbox/confirmation bindings.
function Presentation.GroupTipRows(groups)
    local rows = {}
    for _, group in ipairs(groups or {}) do
        local tips = group.tips
        local count = type(tips) == "table" and #tips or 0
        local row = {}
        for key, value in pairs(group) do if key ~= "tips" then row[key] = value end end
        if count >= 3 then
            row.text = string.format("%s (%d tips)", group.text, count)
            row.tooltipTitle = group.text
            row.tips = tips
            row.useFullHeight = false
        end
        rows[#rows + 1] = row
        if count < 3 then
            for _, tip in ipairs(tips or {}) do rows[#rows + 1] = tip end
        end
    end
    return rows
end

-- A sticky/concurrent step can promote its first goal into a block header.
-- Preserve its instructions and grouped-tip tooltip without repeating that
-- same goal as the first body row. Inputs remain cached, read-only rows.
function Presentation.PromoteHeaderRow(rows, header)
    local first = rows and rows[1]
    if not first or not Presentation.SameText(first.tooltipTitle or first.text, header) then return rows end
    local body = {}
    if first.tips and #first.tips > 0 then
        body[1] = {
            text = string.format("(%d tips)", #first.tips),
            status = first.status,
            kind = "tip",
            tooltipTitle = header,
            tips = first.tips
        }
    end
    for index = 2, #rows do body[#body + 1] = rows[index] end
    return body
end
