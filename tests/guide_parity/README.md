# Guide presentation parity

Run `python tests/run.py` from the addon checkout to run the regressions and see the guide coverage report. The installed checks use the Retail and Forever addon directories by default. Set `AWP_RETAIL_ADDONS` and `AWP_FOREVER_ADDONS` to override them. The standalone suite skips the installed-addon checks.

The normal full suite fails if any reference case has no native mapping, a mapping fails, or a fixture references an unknown or duplicate case. `python tests/run.py --require-guide-parity` also prints the exact source-backed exclusions. It is no longer an optional coverage gate.

The 74 reference IDs are explicitly mapped in `cases.lua` and `extended_cases.lua`. Expected outputs are authored independently; the adapters never receive them. The reference expectations are checked against the approved Zygor baseline, not regenerated from the current implementation.

There are separate checks for different boundaries. Do not describe a display equivalent as proof that another guide implements Zygor's private recovery algorithm.

| Check | What it proves |
| --- | --- |
| Original resolver cases | All 74 original goal/status/context/patch combinations, including actual Zygor-specific pointer recovery, template tokens, broken corridors and taxi-coordinate proof; both coordinate settings and both client configurations. |
| Runtime-goal extraction | Those same original facts pass through `BuildFacts` before resolution, preserving action, quest/NPC identity, visibility, status and suppression. |
| Native display equivalents | Corresponding authored native rows/goals produce the intended active action, context, quest identity and icon through the provider, arrow/plaque presentation and destination queue projection. Intermediate portal legs retain their own title and omit final quest metadata. These are explicit-owner equivalents where a format does not have Zygor's detached-pointer representation. |
| `guide_native_progression_test.lua` | Quest A becomes accepted and Quest B takes ownership at the same coordinates for all 12 installed provider/client combinations. Tests native selection/completion where the guide owns it and the shared handoff selector where it owns selection within a native grouped step. Native-derived results then run through the real asynchronous coordinator, stale-plan rejection, metadata adoption, accepted-plan reuse and manual authority. |
| `guide_native_scenario_test.lua` | Real RXP scenario directives, Dugi `SID`/stage tags, APR scenario handlers and WoWPro `SO` tags consume scenario criteria and advance presentation. Criteria/scenario IDs never become quest IDs. This is distinct from generic defend/escort/event quests. |
| `guide_native_helpers_test.lua` | Real RXP use/spell/gossip directives, their item/spell/option fields and explicit parent ownership; negative cases across another waypoint at identical coordinates; late item-name arrival and cache invalidation. |
| `guide_native_alternatives_test.lua` | Native RXP daily/multiple aliases, their temporary last-candidate assignment, direct quest dialog, dialog closure, same-stop identity, unchanged refresh reuse and in-place candidate-array changes. Back-to-pickup recovery uses the same candidate ownership and rejects candidates removed from the native list. |

Native selection boundaries:

| Provider | Installed code exercised | Fixture boundary |
| --- | --- | --- |
| Zygor | Goal extraction, canonical selection, source/provider extraction and resolver | Goal methods and pointer/current-step input represent the native runtime. AWP's canonical selector is production code. |
| Dugi | `Guides.lua` `ReturnTag`, `FindNextUnchecked`, `CompleteQID`, `UpdateAllSIDs` | Saved row states, client APIs and UI setters. Native functions choose the next unchecked row. |
| APR | Full `StepUtils.lua`, native `GetStep` runtime copies, quest completion predicate, scenario progress reader/handler | Authored route lists, selected serialized step, client APIs and progression/UI callbacks. AWP chooses the first unfinished quest within native grouped pickups/turn-ins. |
| WoWPro | Full `WoWPro_Parser.lua`, native `SO` tags and scenario predicates | Selected serialized row, quest-log/scenario runtime and UI. AWP chooses within `QID` groups; a scenario-status test does not claim to run the entire guide engine. |
| RXP | Native accept/turn-in/complete/use/gossip/scenario/daily functions, alias statements, `UpdateStepCompletion` | Client APIs, current native waypoint/parent, UI callbacks and inventory/group-sharing callbacks. No in-game automation runs. |
| Polestar | Full `Core/Guides.lua` validation and `Core/Engine.lua`, real step views, statuses, `GoalDone` and `Own.currentGoal` | Initial private guide/player/current-step slots and evaluation revision. For explicit selected-owner cases, the waypoint slot is the input; ordinary grouped progression uses the real selector's result. |
| QuestieRouter | Full `Guide/Planner.lua` and `Guide/Steps.lua`: `BuildTasks`, `Choose`, exclusive quest filtering, `FromTasks`, pin matching | Questie database/bridge and game APIs. The native planner produces the task owner; no expected quest index is supplied. |

The full matrix currently has **874 passing display mappings and 14 source-backed exclusions**, with **zero unresolved mappings**. Those 14 are:

- Dugi, both clients: the five unresolved same-step OR/dialog cases (`visible_or_accept_cluster`, `visible_or_turnin_cluster`, `hidden_or_cluster`, `alternate_or_direct_live_match_prefers_direct_entry`, `alternate_or_ambiguous_live_match_falls_back_generic`). `Guides.lua` publishes one QID for each current row. `OID` and optional-row logic resolve prerequisites/skips; they are not an unresolved candidate list on that row. Ordered handoffs and unrelated-row boundaries are still tested.
- QuestieRouter: the two passive helper fallbacks on a **pickup** task (`passive_kill_preferred_over_get`, `passive_get_fallback`). Native `Steps:FromTasks` publishes `QuestNote` only on objective tasks; pickup tasks do not expose these passive helper rows. Their objective-task counterparts are tested.
- QuestieRouter and Polestar: `canonical_scenariogoal_completed_stage_advances_to_next_objective`. Their native goal/planner formats do not expose a scenario-stage counter. Generic defend/escort/event objectives remain tested on both. The four formats with native scenario counters have separate scenario tests on both clients.

Useful native differences are explicit assertions, not broad acceptance patterns: Polestar retains its native objective counts and quest-purpose detail; Dugi removes trailing punctuation from concise instructions; QuestieRouter names object interactions with `Interact with` and resolves exclusive quests before publishing its task. An explicit native selected step remains authoritative; a Zygor stale-seed correction is not imposed on that different input.

To extend coverage, add a native input plus independent expectations, then add a transition or negative case for the behavior it claims to exercise. Never pass an expected goal index to a native selector, replace an unsupported native mechanic with an ordinary quest and count it as that mechanic, or use a missing fixture as an exclusion. Installed source changes should fail their parser/function contracts when they no longer fit.

These are automated API-boundary tests, not a claim that the game client was played. Live Retail/Forever checks remain useful for native event timing and rendered appearance. Tests stay in the development repository and are excluded from addon packaging.
