-- Native equivalents use each guide's explicit row/goal ownership instead of
-- pretending that every format contains Zygor's detached pointer and corridor
-- fields. Inputs and expectations are authored here, never read from a resolver
-- result. The reference matrix records that distinction.
local cases = {}
local function quest(id, npc, names, states, at, owner, action, instruction)
    local quests = {}
    for i, name in ipairs(names) do
        quests[i] = { id = 18000 + i, name = name, state = states[i] }
    end
    local kind = action or "accept"
    local chosen = quests[owner]
    local expected = chosen and { questID = chosen.id,
        title = (kind == "turnin" and "Turn in" or "Accept") .. " '" .. chosen.name .. "'",
        subtext = instruction or npc and "Talk to " .. npc,
        icon = kind == "turnin" and "CompleteQuest" or "AvailableQuest" } or { suppressed = true }
    local scenario = { id = id, references = { id }, current = at,
        stop = { kind = kind, npc = npc, quests = quests, instruction = instruction }, expected = expected }
    cases[#cases + 1] = scenario
    return scenario
end
local function pickup(id, npc, names, states, at, owner, instruction)
    return quest(id, npc, names, states, at, owner, "accept", instruction)
end

local hidden = pickup("hidden_or_cluster", "Commander Althea", { "Quest A", "Quest B" },
    { "available", "available" }, 1, 1)
hidden.stop.alternatives, hidden.stop.hidden = true, true
hidden.expected.title, hidden.expected.subtext = "Talk to Commander Althea", "Accept Available Quest"
hidden.expected.questID = nil

quest("stale_accept_secondary_suppressed", "Field Marshal Brock", { "Go to the Front", "Disruption - Forge Camp: Mageddon" },
    { "ready", "active" }, 1, 1, "turnin")
for _, id in ipairs({ "actionable_accept_click_helper", "actionable_accept_click_helper_bridged_complete" }) do
    local s = pickup(id, nil, { "Invisible Ramparts", "Defenstrations" },
        { id:find("bridged", 1, true) and "rewarded" or "active", "available" }, 2, 2,
        "Click Defense Pylon Central Control Console")
    s.stop.helper, s.stop.objectName = "click", "Defense Pylon Central Control Console"
end
pickup("stale_completed_title_promotes_primary_action", "Exarch Othaar",
    { "The Exarch Council", "Naielle, The Rangari", "Hataaru, the Artificer" },
    { "rewarded", "active", "available" }, 3, 3)
pickup("stale_block_title_prefers_current_goal_action", "Prophet Velen",
    { "The Clarity Elixir", "The Fate of Karabor" }, { "active", "available" }, 2, 2)
pickup("stale_completed_block_title_bridges_guidance_to_talk_header", "Prophet Velen",
    { "The Clarity Elixir", "The Fate of Karabor" }, { "rewarded", "available" }, 2, 2)
pickup("multi_accept_block_prefers_header_context", "Exarch Othaar",
    { "The Exarch Council", "Naielle, The Rangari", "Hataaru, the Artificer" },
    { "rewarded", "available", "available" }, 2, 2)
pickup("split_multi_accept_block_recovers_talk_header", "Rangari Saa'to",
    { "On the Offensive", "Harbingers of the Void", "The Great Salvation" },
    { "available", "active", "available" }, 3, 1)
pickup("presentation_current_action_owns_title_over_sibling_raw_match", "Prophet Velen",
    { "Quest A", "Quest B" }, { "active", "available" }, 2, 2)
pickup("presentation_bridged_completed_corridor_promotes_primary_title_owner", "Prophet Velen",
    { "Quest A", "Quest B" }, { "rewarded", "available" }, 2, 2)
local direct = pickup("presentation_direct_header_beats_corridor_fallback", "Archmage Khadgar",
    { "Quest A", "Quest B" }, { "rewarded", "available" }, 2, 2)
direct.stop.quests[1].npc = "Prophet Velen"
pickup("presentation_corridor_recovers_preceding_talk_header", "Rangari Arepheon",
    { "Quest A", "Quest B" }, { "rewarded", "available" }, 2, 2)
local broken = pickup("presentation_corridor_stops_on_broken_bridge", nil,
    { "Quest A", "Quest B" }, { "rewarded", "available" }, 2, 2)
broken.stop.quests[1].npc = "Rangari Arepheon"
broken.expected.coordinates = "x: 55.0, y: 55.0"

quest("mixed_turnin_accept_block_prefers_header_context", "Field Marshal Brock", { "Quest A", "Quest B" },
    { "ready", "available" }, 1, 1, "turnin")
pickup("nearby_turnin_accept_shared_header_bridge", "Prophet Velen",
    { "Into Twilight", "The Clarity Elixir" }, { "active", "available" }, 2, 2)
local drift = pickup("nearby_turnin_accept_no_header_no_bridge", nil,
    { "Quest A", "Quest B" }, { "active", "available" }, 2, 2)
drift.stop.quests[1].offset = -.0002
drift.expected.coordinates = "x: 55.0, y: 55.0"
pickup("stale_completed_anchor_shared_header_seed_bridge", "Prophet Velen",
    { "Into Twilight", "The Clarity Elixir" }, { "rewarded", "available" }, 2, 2)
pickup("completed_turnin_bridge_recovers_talk_header_with_drift", "Rangari Arepheon",
    { "The Void's Advance", "Gestating Genesaur" }, { "rewarded", "available" }, 2, 2)
local noAnchor = pickup("stale_completed_anchor_no_header_no_seed_bridge", nil,
    { "Quest A", "Quest B" }, { "active", "available" }, 1, nil)
noAnchor.stop.noAnchor = true
noAnchor.stop.kind = "mixed"
noAnchor.stop.quests[1].kind, noAnchor.stop.quests[1].state = "turnin", "rewarded"
noAnchor.stop.quests[1].text = "Turned in 'Quest A'"
noAnchor.stop.quests[2].kind = "accept"
noAnchor.stop.quests[2].offset = .0002
pickup("detached_accept_title_detour", "Field Marshal Brock", { "Disruption - Forge Camp: Mageddon" },
    { "available" }, 1, 1)
quest("detached_turnin_title_detour", "Baros Alexston", { "Establish Your Garrison" }, { "ready" }, 1, 1, "turnin")
quest("detached_turnin_title_detour_without_live", "Baros Alexston", { "Supply Drop" }, { "ready" }, 1, 1, "turnin")
quest("detached_turnin_accept_priority_without_live", "Baros Alexston", { "Supply Drop", "New Orders" },
    { "ready", "available" }, 1, 1, "turnin")
pickup("passive_kill_preferred_over_get", nil, { "Disruption - Forge Camp: Mageddon" }, { "available" }, 1, 1,
    "Kill Daetan Swiftplume").stop.helper = "kill"
pickup("passive_get_fallback", nil, { "Disruption - Forge Camp: Mageddon" }, { "available" }, 1, 1,
    "Collect Noblegarden Trinket (0)").stop.helper = "get"
local finished = pickup("canonical_all_cluster_goals_complete_no_override", nil, { "Quest A", "Quest B" },
    { "active", "active" }, 2, nil)
finished.expected = { noAction = true }
for _, id in ipairs({ "live_direct_accept_seed_beats_stale_first_incomplete_turnin", "completed_three_turnin_corridor_recovers_talk_header" }) do
    pickup(id, "Rexxar", { "Old Orders", "Old Supplies", "Old Allies", "Eye in the Sky" },
        { "rewarded", "rewarded", "rewarded", "available" }, 4, 4)
end
local unrelated = pickup("completed_turnin_corridor_stops_on_unrelated_visible_fact", nil,
    { "Old Orders", "Eye in the Sky" }, { "rewarded", "available" }, 2, 2)
unrelated.stop.quests[1].npc = "Rexxar"
unrelated.expected.coordinates = "x: 55.0, y: 55.0"
local boundary = pickup("ready_turnin_before_accept_seed_stops_on_unrelated_visible_fact", nil,
    { "Vengeance for the Fallen", "Mercy for the Living" }, { "active", "available" }, 2, 2)
boundary.stop.quests[1].npc = "Khaano"
boundary.expected.coordinates = "x: 55.0, y: 55.0"

local function objective(id, title, instruction, helper)
    cases[#cases + 1] = { id = id, references = { id }, current = 1,
        stop = { kind = "objective", objective = { text = title, action = "complete", helper = helper or "text", instruction = instruction },
            quests = { { id = 19001, name = "The current quest", state = "active" } } },
        expected = { questID = 19001, title = title, subtext = instruction, icon = "IncompleteQuest" } }
end
objective("instruction_neighbor_confirm", "Click Here Once Baron Alexston Arrives",
    "Wait for Baron Alexston to appear and walk to this location.")
objective("talk_invehicle_instruction_neighbor", "Talk to Dungar Longdrink", "Take a Flight to Embaari Village, Shadowmoon Valley")
objective("taxi_npcid_proof_neutral_subtext", "Talk to Dungar Longdrink", "Speak with the flight master")
objective("taxi_text_fallback_begin_flying", "Talk to Innkeeper", "Begin Flying to Stormwind")
objective("taxi_no_proof_non_taxi_npc", "Talk to Quest Giver", "Continue your journey")
objective("confirm_instruction_sanitizes_tooltip_template_tokens", "Hold this position", "Wait for 10 enemies to arrive")
objective("q_objective_tooltip_template_prefers_passive_kill_context", "Slay 5 Fel-cursed Creatures", "Kill enemies", "kill")
objective("get_objective_passive_kill_preferred_over_guidance", "Collect 1000 Raw Elekk Steaks", "Kill Rockhide enemies", "kill")
objective("objective_helper_cluster_prefers_setup_guidance", "Complete the Elixir", "You can reach all of the ingredients from this location.")
objective("objective_interaction_chain_promotes_talk_title", "Talk to Sylene", 'Select "I need a Shadowmoon orc illusion."', "gossip")
objective("objective_interaction_chain_bridges_text_to_gossip", "Talk to Vindicator Maraad", 'Select "I am ready to join the attack against the Iron Horde."', "gossip")
objective("objective_interaction_chain_bridges_passive_kill_to_gossip", "Talk to Soulbinder Halaari", 'Select "So be it."', "gossip")
objective("scenario_goal_prefers_objective_text_subtext", "Defend K'ara Until it Becomes Fully Empowered", "Kill the enemies that attack in waves")
objective("scenario_end_prefers_passive_kill_subtext", "Defeat Commander Vorka", "Kill Commander Vorka", "kill")
objective("scenario_start_click_helper", "Begin the Daggerspine Point Scenario", "Click Curious Obelisk", "click")
objective("objective_gossip_only_bridges_passive_kill_to_subtext", "Defeat Soulbinder Halaari", 'Select "So be it."', "gossip")
objective("detached_q_suppressed_by_gossip", "Talk to Shelly Hamby", 'Select "Gather Shelly\'s report."', "gossip")
objective("home_step_header_fallback_semantic_inn", "Make Highpass Inn Your Home", "Talk to Trader Yula", "talk")
objective("detached_warning_q_clicknpc", "Build Your Barracks", "Click Architect Table", "click")
objective("get_click_helper", "Collect Draenei Bucket (0/1)", "Click Draenei Buckets", "click")
objective("havebuff_click_helper", "Carry the Crystal", "Click Charged Resonance Crystal", "click")
objective("canonical_scenariogoal_completed_stage_advances_to_next_objective", "Meet Yrel at the Karabor Harbor", nil)
return cases
