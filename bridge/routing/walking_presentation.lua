-- ============================================================
-- Walking leg descriptions
-- ============================================================
--
-- Builds walking instructions from planner metadata and the live route
-- destination. Display text stays separate from navigation fingerprints.

local NS = _G.AzerothWaypointNS
NS.Internal = NS.Internal or {}
local Display = {}
NS.Internal.RouteWalkingPresentation = Display

function Display.Describe(leg, mode, endpoint, name, instruction)
    leg.walkingDescription = { mode = mode, endpoint = endpoint, name = name, instruction = instruction }
end

local function Final(leg, description)
    local endpoint = description.endpoint
    return leg.routeLegKind == "destination" or endpoint and endpoint.routeLegKind == "destination"
end

function Display.Resolve(record, leg, guideSnapshot)
    local description = leg and leg.walkingDescription
    if not description or leg.routeLegKind == "destination" then return end
    local common = NS.Internal.GuidePresentation
    local target = record.target or record
    local identity = record.identity or record.meta and record.meta.identity
    local corpse = identity and identity.destinationKind == "corpse"
    local context = guideSnapshot and guideSnapshot.destinationPurpose and guideSnapshot or target
    local questID = record.manualQuestID or record.meta and record.meta.manualQuestID
    local quest = not corpse and questID and NS.ResolveQuestPresentation and
        NS.ResolveQuestPresentation(questID, record.title, record)
    local purpose
    if not corpse then
        purpose = common.NormalizeText(context.destinationPurpose)
            or quest and quest.title or common.NormalizeText(record.title or target.title)
    end
    local name = description.name
    if Final(leg, description) then
        name = corpse and "your corpse" or context.destinationName or name
        if not name and not questID and record.authority ~= "guide" and record.type ~= "guide" then name = purpose end
    else
        name = name or description.endpoint and description.endpoint.destinationName
    end
    local old = leg._walkingDisplay
    local action = context.destinationAction or quest and quest.action
    local step = target.guideStepIdentity
    if old and old.description == description and old.name == name and old.purpose == purpose
        and old.action == action and old.step == step then
        return old.value
    end
    local title = description.instruction
    if not title then
        local prefix = description.mode == "road" and "Follow the road" or
            description.mode == "crossing" and "Follow the crossing" or "Follow the path"
        if name then
            title = prefix .. " toward " .. name
        elseif Final(leg, description) and (action == "accept" or action == "turnin") then
            title = prefix .. " to the quest giver"
        else
            title = prefix
        end
    end
    local subtext = purpose
    if common.SameText(title, purpose) or common.SameText(name, purpose) then subtext = nil end
    local value = { title = title, subtext = subtext }
    leg._walkingDisplay = {
        description = description,
        name = name,
        purpose = purpose,
        action = action,
        step = step,
        value = value
    }
    return value
end
