-- These are authored inputs and independent display expectations. Native
-- adapters translate the input; they never see the expected presentation.
local cases = {}

local function handoff(key, reference, kind, npc, status, current, owner)
    local stop = { kind = kind, npc = npc, quests = {} }
    for i, state in ipairs(status) do
        stop.quests[i] = { id = 9000 + i, name = "Quest " .. string.char(64 + i), state = state }
    end
    local verb = kind == "accept" and "Accept" or "Turn in"
    cases[#cases + 1] = {
        id = key, references = { reference }, stop = stop, current = current,
        expected = { questID = stop.quests[owner].id, title = verb .. " '" .. stop.quests[owner].name .. "'",
            subtext = "Talk to " .. npc, icon = kind == "accept" and "AvailableQuest" or "CompleteQuest" },
    }
end

handoff("single_pickup", "canonical_solo_goal_no_cluster_no_override",
    "accept", "Healer Moswen", { "available" }, 1, 1)
handoff("completed_first_pickup", "canonical_earliest_completes_advances_to_next",
    "accept", "Sergeant Aldric", { "active", "available", "available" }, 2, 2)
handoff("completed_middle_pickup", "canonical_middle_complete_accept_selects_first_remaining",
    "accept", "Warden Thelassa", { "available", "active", "available" }, 2, 1)
handoff("later_pickup_selected", "canonical_raw_later_incomplete_not_earliest",
    "accept", "Spiritwalker Yalna", { "available", "available", "available" }, 3, 1)
handoff("completed_middle_turnin", "canonical_middle_complete_turnin_selects_first_remaining",
    "turnin", "Overseer Vinara", { "ready", "rewarded", "ready" }, 2, 1)
handoff("ordered_turnin", "multi_turnin_block_prefers_header_context",
    "turnin", "Quartermaster Brevin", { "ready", "ready" }, 1, 1)
handoff("profile_without_npc_context", "canonical_nearby_drift_without_bridge_no_override",
    "accept", "Healer Moswen", { "available", "available" }, 2, 2)
local separate = cases[#cases]
separate.stop.quests[1].npc = "Healer Moswen"
separate.stop.quests[1].offset = -.0002
separate.stop.npc = nil
separate.expected.subtext = nil
separate.expected.coordinates = "x: 55.0, y: 55.0"

local function choice(key, reference, kind, npc, available, live)
    handoff(key, reference, kind, npc, available, 1, live or 1)
    local case = cases[#cases]
    case.stop.alternatives = true
    case.stop.dialog = live and case.stop.quests[live].id or nil
    local result = case.expected
    result.subtext = live and result.title or (kind == "accept" and "Accept Available Quest" or "Turn In Available Quest")
    result.title = "Talk to " .. npc
    if not live then result.questID, result.icon = nil, "AvailableQuest" end
end
choice("unresolved_pickup_choice", "visible_or_accept_cluster",
    "accept", "Field Marshal Brock", { "available", "available" })
choice("unresolved_turnin_choice", "visible_or_turnin_cluster",
    "turnin", "Quartermaster Brevin", { "ready", "ready" })
choice("quest_window_disambiguates_choice", "alternate_or_direct_live_match_prefers_direct_entry",
    "accept", "Archivist Lyra", { "available", "available" }, 2)
choice("gossip_list_remains_ambiguous", "alternate_or_ambiguous_live_match_falls_back_generic",
    "accept", "Lorekeeper Sela", { "available", "available" })
cases[#cases].stop.gossip = true

cases[#cases + 1] = {
    id = "visible_kill_objective",
    references = { "visible_kill_goal_keeps_quest_semantics" },
    current = 1,
    stop = { kind = "objective", objective = { text = "Kill Witch Lord Morkurk", subject = "Witch Lord Morkurk", action = "kill" },
        quests = { { id = 34980, name = "A threat at the keep", state = "active" } } },
    expected = { questID = 34980, title = "Kill Witch Lord Morkurk", icon = "IncompleteQuest" },
}

local function objective(reference, id, name, title, action, instruction)
    cases[#cases + 1] = { id = reference, references = { reference }, current = 1,
        stop = { kind = "objective", objective = { text = title, action = "complete",
            helper = action, instruction = instruction },
            quests = { { id = id, name = name, state = "active" } } },
        expected = { questID = id, title = title, subtext = instruction, icon = "IncompleteQuest" },
    }
end
objective("q_objective_text_fallback", 34779, "Defend the Camp", "Defend the Camp",
    "text", "Kill the enemies that attack")
objective("q_click_helper", 34587, "Find the Blueprints", "Find the Blueprints",
    "click", "Click Garrison Blueprint: Barracks")
objective("q_use_helper", 33813, "Douse the Bookshelf Fire", "Douse the Bookshelf Fire",
    "use", "Use the Draenei Bucket")
objective("objective_gossip_only_keeps_objective_title", 33080, "Obtain an Orc Disguise From Sylene",
    "Obtain an Orc Disguise From Sylene", "gossip", 'Select "I need a Shadowmoon orc illusion."')

handoff("carrier_keeps_its_own_title", "carrier_leg_suppressed",
    "accept", "Commander Althea", { "available" }, 1, 1)
cases[#cases].carrierTitle = "Accept 'Quest A'"

objective("carrier_portal_q_click_helper_suppressed", 83677, "Loot the Treasure", "Loot the Treasure",
    "click", "Click Sturdy Chest")
cases[#cases].carrierTitle = "Click the Portal to Stormwind City"

local function mixed(reference, npc, quests, current, owner)
    local quest = quests[owner]
    local verb = quest.kind == "accept" and "Accept" or "Turn in"
    cases[#cases + 1] = { id = reference, references = { reference }, current = current,
        stop = { kind = "mixed", npc = npc, quests = quests },
        expected = { questID = quest.id, title = verb .. " '" .. quest.name .. "'", subtext = "Talk to " .. npc,
            icon = quest.kind == "accept" and "AvailableQuest" or "CompleteQuest" } }
end
mixed("stale_turnin_secondary_suppressed", "Prophet Velen", {
    { id = 34575, name = "Step Three: Prophet!", kind = "turnin", state = "active" },
    { id = 34582, name = "Finding a Foothold", kind = "accept", state = "available" },
}, 2, 2)
mixed("ready_turnin_before_accept_seed_prefers_turnin", "Khaano", {
    { id = 35640, name = "Vengeance for the Fallen", kind = "turnin", state = "ready" },
    { id = 35633, name = "Scout Forensics", kind = "turnin", state = "rewarded" },
    { id = 35644, name = "Mercy for the Living", kind = "accept", state = "available" },
}, 3, 1)
mixed("ready_turnin_before_accept_seed_keeps_accept_without_ready_proof", "Khaano", {
    { id = 35640, name = "Vengeance for the Fallen", kind = "turnin", state = "active" },
    { id = 35633, name = "Scout Forensics", kind = "turnin", state = "rewarded" },
    { id = 35644, name = "Mercy for the Living", kind = "accept", state = "available" },
}, 3, 3)

return cases
