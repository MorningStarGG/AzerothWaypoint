local NS = _G.AzerothWaypointNS

NS.CHANGELOG_DATA = {
    {
        version = "5.0.1",
        sections = {
            {
                title = "Mapzeroth",
                entries = {
                    { text = "Updated support for Mapzeroth 1.7.0 on WoW Forever and 2.4.0 on Retail. An earlier Mapzeroth quest trip can no longer replace your active AWP route when the quest objective moves. Explicit **Route with Mapzeroth** actions still work.", level = 1 },
                    { text = "Added **Search Nearby > Next Profession Rank** on WoW Forever. Find the trainer, book vendor, or quest giver for your next rank and get directions using your selected travel planner. Try `/awp search next rank first aid`.",             level = 1 },
                    { text = "Added Mapzeroth as a fallback for verified dungeon and raid entrances when Blizzard and Farstrider have no result. This includes entrance data for the five new Forever dungeons.",                                                         level = 1 },
                }
            },
            {
                title = "Ellesmere UI (WoW Forever)",
                entries = {
                    { text = "The Taxi List now uses Ellesmere UI 9.9.6's recorded time for the exact flight route when available, adjusted for Frequent Flier.",                                                                                                    level = 1 },
                    { text = "Reduced unnecessary tracker layout work when Ellesmere UI reorders quests by distance.",                                                                                                                                               level = 1 },
                    { text = "Added a startup prompt when AWP's World Overlay and Ellesmere UI's **Show Waypoints in the World** are both enabled. You can turn off Ellesmere's marker immediately, ask to be reminded later, or dismiss the reminder permanently.", level = 1 },
                }
            },
        },
    },
    {
        version = "5.0.0",
        sections = {
            {
                title = "Release Highlights",
                entries = {
                    { text = "**New guide integrations:** Dugi Guides, RestedXP, Polestar and QuestieRouter join the supported guide sources: Zygor, APR, and WoWPro. New independent Tracker Viewers for APR and WoWPro as well.", level = 1 },
                    { text = "**Controller support (WoW Forever):** Navigate guide steps, action panels, waypoint queues, settings, menus and dialogs using a controller.",                                                         level = 1 },
                    { text = "**Smarter travel routing:** New Dugi, Polestar and QuestieRouter routing backends, including support for walking routes, automatic planner fallback and route recovery.",                             level = 1 },
                    { text = "**Expanded quest support:** Improved quest details and objective progress, plus Questie and QuestieDB integration on Forever.",                                                                       level = 1 },
                    { text = "**Flight Map Assist:** Taxi List, route markers, hover highlights and optional automatic flight selection now support both clients. Added flight fare cost to the AWP Taxi List.",                    level = 1 },
                    { text = "**Guide Actions:** Optional movable action panels and inline item, spell and target controls for supported guides.",                                                                                  level = 1 },
                    { text = "**Expanded UI integration:** DaylightUI, Ellesmere UI, ElvUI and GW2 UI appearance matching, with automatic style selection and additional tracker integrations.",                                    level = 1 },
                    { text = "**New destination styles:** Additional pinpoint plaques with independent background, border and thickness controls.",                                                                                 level = 1 },
                    { text = "**Settings profiles:** Share, back up and import AWP settings across characters and supported clients.",                                                                                              level = 1 },
                }
            },
            {
                title = "Guide Integrations",
                entries = {
                    { text = "**Dugi Guides (Retail and Forever)**",                                                                                                                                                                                                                                  level = 1 },
                    { text = "Added guide navigation through the selected AWP routing backend, an independent Tracker Viewer, native guide controls and Find Nearest service search.",                                                                                                                level = 2 },
                    { text = "Added optional Dugi Taxi System routing for guide and manual destinations, including travel actions and wearable teleport items. Dugi's travel preferences are respected.",                                                                                             level = 2 },
                    { text = "Added six numbered guide slots, including multiple copies of a guide, using native tabs where available or AWP-managed slots when needed. Closing inactive slots preserves the current guide, opening a guide when all slots are full requires choosing one to close.", level = 2 },
                    { text = "Hiding Dugi's native guide frame also hides its companion model viewer. Both are restored when hiding is disabled or anchored mode is used.",                                                                                                                           level = 2 },
                    { text = "**RestedXP (Retail and Forever)**",                                                                                                                                                                                                                                     level = 1 },
                    { text = "Added guide navigation, an independent Tracker Viewer, native guide selection and settings, and six remembered recent guides with progress preserved.",                                                                                                                 level = 2 },
                    { text = "Supports native settings menus, including when the native guide window is hidden.",                                                                                                                                                                                     level = 2 },
                    { text = "Added native Back, Next and objective-skip controls, Go to Step, and guide reload without losing progress. Back can recover a missing quest from its earlier acceptance step or open Go to Step when the correct step is uncertain.",                                   level = 2 },
                    { text = "Respects RestedXP's pause settings and displays a paused message in the Viewer.",                                                                                                                                                                                       level = 2 },
                    { text = "**Polestar (WoW Forever)**",                                                                                                                                                                                                                                            level = 1 },
                    { text = "Added Polestar as both a guide source and an optional routing backend. Its backend can plan routes for any AWP destination.",                                                                                                                                           level = 2 },
                    { text = "Added an independent Tracker Viewer with access to Polestar's native guide menu, tabs, goal controls and settings, even when its native window is hidden.",                                                                                                             level = 2 },
                    { text = "Travel planning respects Polestar's own travel, class teleport, terrain walking and route-style preferences.",                                                                                                                                                          level = 2 },
                    { text = "Expanded travel support including airships, item-required portals, inventory-aware routing, probable flight paths and Astral Recall. Routes can use connections offered by the flight master you are talking to.",                                                      level = 2 },
                    { text = "Tracker Viewer shows Polestar's escort and group quest choices, escort notes and warnings about hard fights.",                                                                                                                                                          level = 2 },
                    { text = "Support for native buff, equipment, banking, training, reputation and achievement goals, along with material requirements, special hand-ins and quest explanations.",                                                                                                   level = 2 },
                    { text = "Displays Polestar's optional left-out quest summary and supports its bag-space helper, including spare-bag equipment and the native two-click junk deletion confirmation.",                                                                                             level = 2 },
                    { text = "Previewing steps with Back or Next won't interrupt an active manual waypoint. Explicit guide or goal selection will switch navigation.",                                                                                                                                level = 2 },
                    { text = "Uses Polestar's supported follower integration and offers a **Let AWP Show Navigation** prompt to avoid competing arrows without silently changing native preferences.",                                                                                                level = 2 },
                    { text = "**QuestieRouter (WoW Forever)**",                                                                                                                                                                                                                                       level = 1 },
                    { text = "Added QuestieRouter as a guide source, independent Tracker Viewer and selectable travel backend.",                                                                                                                                                                      level = 2 },
                    { text = "Supports dynamic task ordering, manual task selection, return to automatic order, native quest skipping and six remembered recent guides. Progress reflects completed quests rather than artificial linear steps.",                                                     level = 2 },
                    { text = "Displays quest titles, descriptions, objective progress and grouped notes. The Visible Tasks setting supports up to 14 tasks, including the current task.",                                                                                                             level = 2 },
                    { text = "Includes an optional native banner above guide tasks, disabled by default.",                                                                                                                                                                                            level = 2 },
                    { text = "Select a task from its heading or objective, or use **Choose Task** and **Return to Automatic Order** in the Viewer header.",                                                                                                                                           level = 2 },
                    { text = "Travel routing respects native walking and transport preferences, flight destinations, required crossings and exact final destinations. Optional navigation packs provide terrain walking directions.",                                                                 level = 2 },
                    { text = "Includes floor handling, instance entrance labels, native NPC and quest identification, and route updates when settings or travel data change.",                                                                                                                        level = 2 },
                    { text = "**Azeroth Pilot Reloaded and WoWPro (Retail and Forever)**",                                                                                                                                                                                                            level = 1 },
                    { text = "Added independent Tracker Viewers with the shared appearance, progress, tips, checkboxes, chat, native-window hiding and guide controls available to other providers.",                                                                                                 level = 2 },
                    { text = "APR uses its native Back, Skip and route browser. Loot and merchant steps now retain the correct associated quest in the Viewer, arrow, plaque and queue.",                                                                                                             level = 2 },
                    { text = "WoWPro Back can recover an earlier missing quest acceptance or offer earlier-step selection when needed. Dependent skips retain their confirmation.",                                                                                                                   level = 2 },
                    { text = "Added WoWPro's native Current Guide Steps window and guide selector, plus six remembered recent guides with progress restoration.",                                                                                                                                     level = 2 },
                    { text = "Preserved WoWPro's multi-point waypoint progression and prevented already completed points from reappearing.",                                                                                                                                                          level = 2 },
                }
            },
            {
                title = "Tracker Viewers and Guide Actions",
                entries = {
                    { text = "**Shared Tracker Viewers**",                                                                                                                                                                                                                                                                                                                                 level = 1 },
                    { text = "Expanded the common Viewer experience across supported guide addons, with independent appearance, progress, chat and visibility settings. Multiple guides can be displayed while only one controls navigation.",                                                                                                                                             level = 2 },
                    { text = "Added support for reordering guide Viewers under **General > Guide Viewer Order**. The order is saved in the active profile and also determines nearby service search priority.",                                                                                                                                                                            level = 2 },
                    { text = "Auto text colors now use consistent colors across guides for NPC headings, training and learning, warnings, completed objectives and skipped work. Added a **UI colors** option.",                                                                                                                                                                           level = 2 },
                    { text = "Added **Use custom Viewer text sizes** to each guide's Tracker Viewer settings, with separate heading, goal, notes/context and progress sizes. Existing sizes remain unchanged until enabled, fonts, outlines and shadows continue to follow the selected style. Rows resize to fit, and size overrides are included in guide profile imports and exports.", level = 2 },
                    { text = "Added **Hide Guide Addon Name**, **Hide Guide Title**, and **Compact Active Indicator** to each Tracker Viewer. Hidden names remain in the progress and guide-menu tooltips.",                                                                                                                                                                               level = 2 },
                    { text = "Improved header spacing, alignment, progress sizing, collapse controls and narrow-width layouts across tracker hosts. Inactive Viewers no longer reserve unnecessary active-indicator space.",                                                                                                                                                               level = 2 },
                    { text = "Improved step checkbox placement and spacing when guide titles are hidden.",                                                                                                                                                                                                                                                                                 level = 2 },
                    { text = "Added consistent local chat output options: none, count or titles for sticky summaries, full instructions, or sticky instructions only.",                                                                                                                                                                                                                    level = 2 },
                    { text = "Guide arrow recommendations are coordinated with other startup notices and change native settings only when explicitly accepted.",                                                                                                                                                                                                                           level = 2 },
                    { text = "**Guide Actions and quest details**",                                                                                                                                                                                                                                                                                                                        level = 1 },
                    { text = "Added independent movable action panels, optional inline action buttons and category filters for supported guides. Panels include drag handles and remember their positions separately.",                                                                                                                                                                    level = 2 },
                    { text = "Native action controls can be hidden independently of the AWP panel, inline buttons and native guide window. Inventory Cleanup is disabled by default and retains native confirmations.",                                                                                                                                                                    level = 2 },
                    { text = "Prepared item, spell and target actions can remain available during combat. If the guide changes, the panel indicates that an update is pending and applies the replacement after combat. Native helper actions remain subject to their original restrictions.",                                                                                             level = 2 },
                    { text = "Action buttons show native item, equipment, toy and spell tooltips, including supported tooltip-addon styling and comparisons.",                                                                                                                                                                                                                             level = 2 },
                    { text = "Added **Open Quest Details** to quest-related guide row and section menus. Sections containing several quests offer a choice, viewing details does not change guide progress, tracking or navigation.",                                                                                                                                                      level = 2 },
                    { text = "Guide actions remain separate from the travel button used for route-related items and spells.",                                                                                                                                                                                                                                                              level = 2 },
                    { text = "**Guide menus and commands**",                                                                                                                                                                                                                                                                                                                               level = 1 },
                    { text = "Expanded named guide commands, including guide switching, loading, local chat output, Viewer visibility, native-window visibility and safe window recovery. Unsupported native actions report that they are unavailable rather than changing unrelated settings.",                                                                                           level = 2 },
                    { text = "Removed the old Zygor Viewer shortcuts `/awp trackerviewer` and `/awp zygorviewer` and their aliases. Use `/awp zygor viewer` and `/awp zygor native` for their respective controls.",                                                                                                                                                                       level = 2 },
                    { text = "Moved Zygor's compact-window control to `/awp zygor compact on|off|toggle|status`.",                                                                                                                                                                                                                                                                         level = 2 },
                    { text = "The minimap menu now lists loaded guides in the configured Viewer order, including disabled Viewers, with provider-specific shortcuts and independent visibility controls. Added **Search Nearby** for browsing supported services.",                                                                                                                        level = 2 },
                    { text = "Added support for native guide transitions from Zygor guide-loading rows and Polestar's suggested alternative guides.",                                                                                                                                                                                                                                      level = 2 },
                    { text = "Background guide updates no longer take navigation away from another active guide or manual destination.",                                                                                                                                                                                                                                                   level = 2 },
                }
            },
            {
                title = "Controller Support (WoW Forever)",
                entries = {
                    { text = "Added shared controller navigation for guide Viewers, action panels, settings, waypoint queues, help, menus and dialogs.",                                                                                                                            level = 1 },
                    { text = "Guide toolbars and task rows support directional navigation, skipping disabled controls and decorative elements. Navigation between docked guide sections preserves the correct guide's actions and menu controls without making that guide active.", level = 1 },
                    { text = "Press the right stick on a focused task to use its available action or open a picker when multiple actions are available. Additional task actions remain available through menus.",                                                                   level = 1 },
                    { text = "Added three optional, unbound key bindings under **AzerothWaypoint**: Navigate AWP Guides, Open AWP Menu and Use Active Guide Action.",                                                                                                               level = 1 },
                    { text = "Added controller-friendly slider adjustment, numeric editing, paged dropdowns, color editing and guide reordering with confirm/cancel controls.",                                                                                                     level = 1 },
                    { text = "DaylightUI and GW2 UI controller scrolling respects visible tracker boundaries, pinned headers, scroll indicators and quest-item buttons.",                                                                                                           level = 1 },
                    { text = "Added a Controller settings page and `/awp controllerdiag` for diagnostics without changing the player's controller layout.",                                                                                                                         level = 1 },
                }
            },
            {
                title = "Navigation and Travel",
                entries = {
                    { text = "**Search Nearby**",                                                                                                                                                                                                                                                                  level = 1 },
                    { text = "Added shared nearby-service search through the minimap menu and `/awp search`. Available Zygor, Dugi and Polestar (Forever) integrations are checked in Guide Viewer Order, the first matching result uses the selected travel planner, even when that guide's Viewer is disabled.", level = 2 },
                    { text = "Browse supported vendor, profession, class, weapon master and workshop categories. Specific searches do not substitute unrelated services, and each guide's native Find Nearest menu remains provider-specific.",                                                                    level = 2 },
                    { text = "**Automatic route fallback and recovery**",                                                                                                                                                                                                                                          level = 1 },
                    { text = "If a travel planner fails, AWP now tries other available planners before falling back to TomTom Direct. Your selected backend remains preferred, intentional direct and walking settings are respected.",                                                                            level = 2 },
                    { text = "Existing guidance remains visible while a replacement route is calculated. AWP can return to the preferred planner automatically and announces successful fallback or recovery in chat.",                                                                                            level = 2 },
                    { text = "Recovery attempts are spaced out to avoid repeated searches while moving. After 100 yards of movement, retries use increasing 10/20/40/60-second delays, meaningful map or travel changes can trigger an earlier retry.",                                                            level = 2 },
                    { text = "Improved handling of loading, casts, equipment use, transport transitions and combat. Late results no longer replace cleared or superseded destinations.",                                                                                                                           level = 2 },
                    { text = "Added preferred/active planner information and per-backend fallback and recovery diagnostics.",                                                                                                                                                                                      level = 2 },
                    { text = "**Walking routes and destination guidance**",                                                                                                                                                                                                                                        level = 1 },
                    { text = "Added Mapzeroth road and capital-street walking routes on Forever, respecting its native Walking routes setting.",                                                                                                                                                                   level = 2 },
                    { text = "Improved fixed walking directions for Mapzeroth, Polestar and QuestieRouter. Ordinary route points advance when reached or passed nearby, including during fast mounted movement, while required crossings, floors and transport stops remain protected.",                           level = 2 },
                    { text = "Arrow, world marker and map pins advance together. Route updates preserve walking progress and exact destinations instead of returning to already passed points.",                                                                                                                   level = 2 },
                    { text = "Added recovery when leaving Mapzeroth roads or QuestieRouter paths, and Polestar lift boarding, departure and missed-landings.",                                                                                                                                                     level = 2 },
                    { text = "Added **Follow ground paths while flying**, disabled by default. On supported Retail routes, self-flight can bypass ground directions when the planner approves flight connectivity, landing restores walking guidance. Required stops remain intact.",                              level = 2 },
                    { text = "Walking instructions now name the destination when known, with quest or objective context underneath. Named lifts, stairs, passages and transport approaches retain their specific instructions.",                                                                                   level = 2 },
                    { text = "Improved consistency of walking labels across TomTom, plaques and queue details, including consecutive hand-ins at the same identified NPC.",                                                                                                                                        level = 2 },
                    { text = "**Travel actions and transport**",                                                                                                                                                                                                                                                   level = 1 },
                    { text = "Added distinct boat, airship and zeppelin icons across supported route planners, guides and world markers.",                                                                                                                                                                         level = 2 },
                    { text = "Improved travel-button icons for items, spells and Hearthstones, including Polestar's Hearthstone.",                                                                                                                                                                                 level = 2 },
                    { text = "Travel buttons hide during combat to prevent use of an action from an earlier route and return with the current action afterward.",                                                                                                                                                  level = 2 },
                    { text = "Switching destinations during a travel spell cast allows the cast to finish before deferred planning resumes.",                                                                                                                                                                      level = 2 },
                    { text = "Farstrider connecting flights identify the departure flight master and the final landing. Boat, zeppelin and Deeprun Tram legs advance at the receiving dock. Dungeon and raid exits advance when you leave the instance.",                                                          level = 2 },
                    { text = "Farstrider routes update when its travel data changes, including newly discovered Forever flight paths.",                                                                                                                                                                            level = 2 },
                    { text = "Routes to waypoints inside dungeons and raids can use Farstrider's verified entrance when Blizzard's entrance is unavailable.",                                                                                                                                                      level = 2 },
                    { text = "Polestar points toward the receiving dock once a ride is underway. Queue details show the estimated time remaining when available.",                                                                                                                                                 level = 2 },
                    { text = "Mapzeroth quest-follow requests reuse equivalent active routes, and corpse-trip resumption respects AWP routing without interfering with native previews.",                                                                                                                          level = 2 },
                }
            },
            {
                title = "Flight Map Assist (Retail and Forever)",
                entries = {
                    { text = "Extended the Taxi List, route marker, hover highlights and optional automatic flight selection to WoW Forever.",                                                                                                                       level = 1 },
                    { text = "InFlight timing works on both clients. On Forever, the Taxi List can also use DaylightUI's recorded or bundled times, then Farstrider or Ellesmere UI estimates.",                                                                     level = 1 },
                    { text = "Reachable destinations show their current fare in the Taxi List and tooltip.",                                                                                                                                                         level = 1 },
                    { text = "Automatic flight selection rechecks the route and departure flight master before boarding, including when the route changes as the flight map opens. A connecting ticket is selected when the flight map confirms the planned stops.", level = 1 },
                    { text = "Improved tooltip and hover-marker updates when the destination beneath the cursor changes.",                                                                                                                                           level = 1 },
                }
            },
            {
                title = "Quest, Map and Waypoint Improvements",
                entries = {
                    { text = "**Quest support and Questie (WoW Forever)**",                                                                                                                                                                                                     level = 1 },
                    { text = "Improved ordinary quest destinations with shared action information, objective progress and quest context across the arrow, overlay, plaque and queue.",                                                                                          level = 2 },
                    { text = "Optional QuestieDB data can enrich identified quests even when Questie is not running or the waypoint came from another source. Missing data retains normal Blizzard behavior.",                                                                  level = 2 },
                    { text = "Questie pins and tracker waypoints retain the correct quest and objective while preserving explicitly selected coordinates. Ready quest data can also fill missing destinations for existing automatic quest following.",                         level = 2 },
                    { text = "Added **Route with AzerothWaypoint** to DaylightUI's quest tracker and journal menus without changing watched quests.",                                                                                                                           level = 2 },
                    { text = "**Map waypoints and queues**",                                                                                                                                                                                                                    level = 1 },
                    { text = "Added export of all saved manual waypoints or the open queue as copyable TomTom commands.",                                                                                                                                                       level = 2 },
                    { text = "Improved map clicks near zone boundaries, including Forever QuestieRouter clicks, so destinations use the outdoor zone beneath the cursor when identifiable.",                                                                                    level = 2 },
                    { text = "Improved waypoint placement when map information becomes available late and preserved quest icons and NPC context on final walking approaches.",                                                                                                  level = 2 },
                    { text = "Switching between guides and manual waypoints now consistently honors the latest selection, even during route calculation or TomTom pin updates.",                                                                                                level = 2 },
                    { text = "Clearing a manual route after the guide has advanced now resumes the latest guide step through the selected planner.",                                                                                                                            level = 2 },
                    { text = "Original Ctrl-click map pins remain visible when a route starts with a Hearthstone or another travel action, removing the pin clears its manual route.",                                                                                          level = 2 },
                    { text = "Improved Forever Shift- and Alt-click handling with Zygor, Polestar and QuestieRouter, preventing duplicate or leftover waypoints.",                                                                                                              level = 2 },
                    { text = "TomTom's **Remove all waypoints** now cancels pending manual routes, including those cleared during combat.",                                                                                                                                     level = 2 },
                    { text = "Queue counts include collapsed sections, and empty queues display a properly spaced empty-state message. Wrapped queue names fit their rows.",                                                                                                    level = 2 },
                    { text = "**Combat navigation**",                                                                                                                                                                                                                           level = 1 },
                    { text = "Manual waypoints and current guide destinations can update during combat.",                                                                                                                                                                       level = 2 },
                    { text = "TomTom Direct, Farstrider, Mapzeroth and Dugi can plan during combat on both clients. Forever also supports combat planning with Zygor, QuestieRouter and Polestar. Retail Zygor displays direct guidance while waiting for its native planner.", level = 2 },
                    { text = "AWP rechecks destinations after combat when travel options were restricted. Interrupted QuestieRouter terrain searches resume from the current position when needed.",                                                                            level = 2 },
                    { text = "Clearing or replacing a route during combat no longer allows an outdated planning result to restore it afterward.",                                                                                                                               level = 2 },
                    { text = "**Corpse waypoints**",                                                                                                                                                                                                                            level = 1 },
                    { text = "Improved corpse recognition across all travel backends.",                                                                                                                                                                                         level = 2 },
                    { text = "Corpse routes remain temporary, preserve saved manual queues and clear with TomTom's normal corpse waypoint removal.",                                                                                                                            level = 2 },
                    { text = "Clearing a corpse waypoint while dead or ghosted clears the arrow, the interrupted guide or queue resumes on resurrection. New manual destinations remain available while ghosted.",                                                              level = 2 },
                    { text = "When Blizzard tracks the corpse, its world marker points to the body while TomTom can follow a walking route.",                                                                                                                                   level = 2 },
                }
            },
            {
                title = "UI Integrations and Appearance",
                entries = {
                    { text = "**Automatic appearance selection**",                                                                                                                                                                                                                  level = 1 },
                    { text = "AWP now automatically matches a supported UI addon when exactly one is ready. When several are available, a startup chooser offers each style and the original AWP appearance.",                                                                      level = 2 },
                    { text = "Supports DaylightUI, Ellesmere UI, ElvUI and GW2 UI, with DaylightUI limited to Forever. Only one provider styles AWP at a time.",                                                                                                                    level = 2 },
                    { text = "Explicit choices are remembered. Select **General > UI Style > Automatic** to restore automatic selection.",                                                                                                                                          level = 2 },
                    { text = "If the selected UI addon is unavailable, AWP temporarily restores its original appearance and offers available alternatives without discarding saved preferences. Escape dismisses the chooser for that session.",                                    level = 2 },
                    { text = "Styling remains independent of routing and tracker hosting. Tracker Viewer Auto colors remain contextual, even when UI text matching is enabled, choose UI colors to use the UI style instead.",                                                      level = 2 },
                    { text = "**Tracker hosting**",                                                                                                                                                                                                                                 level = 1 },
                    { text = "Added Questie tracker hosting on Forever, placing enabled guide Viewers above quests in its shared scrolling area. Fixed empty-tracker sizing when Viewers detach.",                                                                                  level = 2 },
                    { text = "Added GW2 UI tracker hosting on Retail and Forever, with independently collapsible guide sections above native quests.",                                                                                                                              level = 2 },
                    { text = "Improved DaylightUI and Ellesmere UI custom tracker spacing, guide widths, action placement and shared scrolling behavior. DaylightUI's native tracker opacity and mouseover fade also apply to guide sections.",                                     level = 2 },
                    { text = "Ellesmere UI supports guide Viewers on both clients. Dedicated tracker hosting is available on Forever. AWP uses Blizzard docking on Retail and on Forever when the custom tracker is off. AWP still selects Kaliel's Tracker first when available.", level = 2 },
                    { text = "Supported dedicated trackers avoid experimental Blizzard docking. The warning still applies when ElvUI or Ellesmere UI uses Blizzard's tracker.",                                                                                                     level = 2 },
                    { text = "**DaylightUI (WoW Forever)**",                                                                                                                                                                                                                        level = 1 },
                    { text = "Added DaylightUI styling for guide Viewers, action panels, plaques, navigation labels, travel controls and AWP windows.",                                                                                                                             level = 2 },
                    { text = "Independent appearance settings for guide Viewers, action panels, plaques, navigation labels and AWP windows.",                                                                                                                                       level = 2 },
                    { text = "Headers and panels use DaylightUI's full appearance, with independent border-width and background-opacity overrides for plaques and windows.",                                                                                                        level = 2 },
                    { text = "AWP's DaylightUI settings are shared between both settings windows.",                                                                                                                                                                                 level = 2 },
                    { text = "DaylightUI's minimap drawer stays open while AWP menus are in use and resumes its normal timeout afterward.",                                                                                                                                         level = 2 },
                    { text = "**Ellesmere UI (Retail and Forever)**",                                                                                                                                                                                                               level = 1 },
                    { text = "Added Ellesmere UI styling for the EUI, Blizzard, Classic and Forever looks for guide Viewers, action panels, plaques, navigation labels, travel controls and AWP windows.",                                                                          level = 2 },
                    { text = "Added independent styling controls for guide Viewers, action panels, navigation labels, plaques and AWP windows, with shared settings in Ellesmere UI's AzerothWaypoint section.",                                                                    level = 2 },
                    { text = "Added live search across the Ellesmere UI AzerothWaypoint settings pages, including setting descriptions, Clear Search and empty-result feedback. Search retains focus while results update.",                                                        level = 2 },
                    { text = "AWP's Ellesmere UI settings are shared between both settings windows.",                                                                                                                                                                               level = 2 },
                    { text = "Requires Blizzard Skins+ and its AzerothWaypoint addon skin. Preset changes follow Ellesmere UI's normal reload requirements.",                                                                                                                       level = 2 },
                    { text = "**ElvUI (Retail and Forever)**",                                                                                                                                                                                                                      level = 1 },
                    { text = "Added ElvUI styling for guide Viewers, action panels, plaques, navigation labels, travel controls and AWP windows.",                                                                                                                                  level = 2 },
                    { text = "Uses ElvUI's native fonts, media, controls and settings-widget styling, with improved sidebar buttons, sliders and close controls.",                                                                                                                  level = 2 },
                    { text = "AWP and ElvUI settings share appearance preferences for related ElvUI settings. ElvUI also provides shortcuts to AWP options, queue and help.",                                                                                                       level = 2 },
                    { text = "**GW2 UI (Retail and Forever)**",                                                                                                                                                                                                                     level = 1 },
                    { text = "Added GW2 UI styling with shared config in AWP settings and GW2 UI's AzerothWaypoint section.",                                                                                                                                                       level = 2 },
                    { text = "When the GW2 UI map skin is active, Waypoint Queues opens beside the map when space allows and keeps the quest pane accessible.",                                                                                                                     level = 2 },
                    { text = "Appearance and tracker updates preserve unchanged layouts and apply deferred changes after combat.",                                                                                                                                                  level = 2 },
                }
            },
            {
                title = "Arrow and Pinpoint Customization",
                entries = {
                    { text = "Added standalone **Minimal, Forever, Blizzard, Classic, Clean and Modern** plaques on Retail and Forever.",                                                                                                      level = 1 },
                    { text = "Forever uses a bronze frame, Blizzard a silver frame, Classic the traditional dialog border, Minimal a compact dark panel, Clean a rounded dark panel, and Modern a warm rounded design with bevel and shadow.", level = 1 },
                    { text = "Renamed the previous Modern plaque to **Future**, preserving its artwork and saved selection. The original Default plaque is now **Fantasy**.",                                                                  level = 1 },
                    { text = "Added independent background and border opacity for all six new standalone styles. Minimal, Clean and Modern also support 1-8 pixel border thickness with automatic text spacing.",                              level = 1 },
                    { text = "Plaque adjustments are remembered per style.",                                                                                                                                                                   level = 1 },
                }
            },
            {
                title = "Settings, Profiles and Help",
                entries = {
                    { text = "**Settings profiles and sharing**",                                                                                                                                                                        level = 1 },
                    { text = "Added a Profiles page with shared account defaults and optional per-character profile selection. Existing settings become the Default profile.",                                                           level = 2 },
                    { text = "Create, duplicate, rename and back up profiles, or export a copyable settings string for sharing across Retail and Forever.",                                                                              level = 2 },
                    { text = "Imports preview changes and unavailable integrations before saving a new profile or explicitly replacing an existing one.",                                                                                level = 2 },
                    { text = "Profiles include AWP appearance, preferences and frame positions. Queues, active navigation, guide progress and other addons' settings are not included. Queue's can be exported in AWP's Queue window.",  level = 2 },
                    { text = "In-game Help links jump directly to related pages and sections. On WoW Forever, you can follow them with a controller.",                                                                                   level = 2 },
                    { text = "**Settings usability**",                                                                                                                                                                                   level = 1 },
                    { text = "Added individual Reset controls for AWP settings on both clients, with or without appearance matching. Reset icons appear only when values differ from their defaults and show the default in a tooltip.", level = 2 },
                    { text = "Improved slider spacing, editable values, labels and NEW/UPDATED badges, including disabled settings and narrow layouts.",                                                                                 level = 2 },
                    { text = "Fixed settings refreshes interrupting dropdown clicks, slider drags or color editing.",                                                                                                                    level = 2 },
                    { text = "Updated in-game Help for guide controls, routing, UI Style, provider-specific commands and live plaque previews.",                                                                                         level = 2 },
                }
            },
            {
                title = "Performance, Stability and Diagnostics",
                entries = {
                    { text = "Reduced unnecessary guide progress scans, route searches, layout rebuilds and appearance refreshes when information has not changed.",                                                level = 1 },
                    { text = "Improved shared route and guide handling to prevent outdated results, empty guide queues, stale helper actions and inactive guide updates from interfering with current navigation.", level = 1 },
                    { text = "Improved startup handling for optional addons, late tracker initialization and appearance selection.",                                                                                level = 1 },
                    { text = "Deferred settings search and release-badge indexing, along with certain diagnostic setup, until first use.",                                                                          level = 1 },
                    { text = "Expanded `/awp mem` with startup file-group and initialization timings, and improved `/awp churn` cancellation and routing statistics.",                                              level = 1 },
                    { text = "Improved saved-settings validation, removing retired or unrecognized fields while preserving recognized queues, guide identities, positions and disabled-integration preferences.",   level = 1 },
                }
            },
        },
    },
    {
        version = "4.2.0",
        sections = {
            {
                title = "WoW Forever support",
                entries = {
                    { text = "Added WoW Forever to the same addon package as Retail, with shared SavedVariables names and capability-based feature checks.",                            level = 1 },
                    { text = "Added client-flavor detection that uses the bounded Forever interface range instead of project IDs.",                                                     level = 1 },
                    { text = "Updated quest-watch handling to the current `C_QuestLog.GetQuestWatchType` contract and removed the obsolete Mapzeroth `LEARNED_SPELL_IN_TAB` listener.", level = 1 },
                }
            },
            {
                title = "Support and diagnostics",
                entries = {
                    { text = "Added client flavor and Forever integration availability to `/awp status`, updated integration cards, and documented both installation paths and the client support matrix.", level = 1 },
                    { text = "Generalized the experimental Blizzard Tracker Viewer warning to the modern shared Objective Tracker and World Map taint boundary on both supported clients.",                 level = 1 },
                }
            },
            {
                title = "Options and help",
                entries = {
                    { text = "Updated and added search tags for options inside addon settings that were lacking or missing tags.", level = 1 },
                }
            },
        },
    },
    {
        version = "4.1.4",
        sections = {
            {
                title = "TomTom 4.4 compatibility",
                entries = {
                    { text = "Updated AWP's carrier and queue waypoints to use TomTom 4.4's new `minimap`, `world`, and zero clear-distance options, removing obsolete waypoint fields.",                                                                               level = 1 },
                    { text = "Arrow settings, theme, and target observation now use TomTom's public callbacks. Target changes retain AWP's next-frame skin refresh, while duplicate refresh requests are combined without changing arrival/navigation state tracking.", level = 1 },
                    { text = "`/awp repair` now restores TomTom's clear distance through `profile.persistence.cleardistance`.",                                                                                                                                         level = 1 },
                }
            },
        },
    },
    {
        version = "4.1.3",
        sections = {
            {
                title = "Mapzeroth 2.x compatibility",
                entries = {
                    { text = "Updated the existing routing backend for Mapzeroth 2.x",                                                                                                                                    level = 1 },
                    { text = "Added complete Mapzeroth 2.x `equip` route support through equip, confirm, use, and restore transaction.",                                                                                  level = 1 },
                    { text = "AWP restores prior main-hand and offhand equipment only when its own teleport item is still equipped, defers restoration through combat, and never overwrites a later manual gear change.", level = 1 },
                    { text = "Route validation and same-target replanning remain held through the equip/use sequence so an item's equip cooldown cannot discard the selected route before use.",                          level = 1 },
                }
            },
            {
                title = "InFlight integration updates",
                entries = {
                    { text = "InFlight timing now uses the current combined `SpeedFactor` API, including Frequent Flier exactly once.", level = 1 },
                }
            },
        },
    },
    {
        version = "4.1.2",
        sections = {
            {
                title = "Native Tracker Viewer support status",
                entries = {
                    { text = "Blizzard native docking remains available at order 2, but is now explicitly experimental because WoW 12.1's shared Objective Tracker and World Map execution can retain AWP taint and later report protected-action or secret-value errors.",                    level = 1 },
                    { text = "Native docking may stop working entirely after a future WoW patch and may be removed from AWP in favor of Kaliel's Tracker-only docking. Kaliel's Tracker is the recommended tracker viewer and is selected automatically whenever it is installed and loaded.", level = 1 },
                    { text = "Tracker Viewer settings, help, and `/awp status` now report the active tracker viewer and its support status.",                                                                                                                                                  level = 1 },
                    { text = "Added a startup warning when Tracker Viewer attaches to Blizzard's native tracker. **Okay, remind me later** repeats it next login/reload, **Don't remind me again** disables it account-wide, and the Tracker Viewer settings can restore it.",                 level = 1 },
                }
            },
            {
                title = "Blizzard quest tracker taint cleanup and mitigation",
                entries = {
                    { text = "Removed the Scenario aura/cooldown replacement shims completely. AWP no longer replaces `ShouldShowMawBuffs` or `ScenarioSpellButtonMixin.UpdateCooldown`.",                                                                  level = 1 },
                    { text = "Retained the two narrow risk reductions that tested cleanly: AWP stays at order 2 without assigning Blizzard's `hasDisplayPriority` field, and guide refreshes no longer force a redundant synchronous full-tracker update.", level = 1 },
                    { text = "Retained the Blizzard-only combat proxy for tracked Quest and Campaign Quest headers. It reports that the action is unavailable in combat and leaves Blizzard's normal click behavior untouched outside combat.",             level = 1 },
                }
            },
            {
                title = "Known Blizzard native quest tracker limitation",
                entries = {
                    { text = "Clicking a native tracked quest out of combat can still transfer AWP taint into reusable `WorldMapFrame.mapID` and `mapArtID` state. A later map open during combat may report `SetPassThroughButtons` or `SetPropagateMouseClicks` even though the keybind for world map still opens the map.", level = 1 },
                    { text = "The combat proxy mitigates the tracker-click path only while combat-locked, it does not make Blizzard native docking taint-free. No map-pin, quest-handler, World Map, or Blizzard container functions are patched.",                                                                            level = 1 },
                }
            },
        },
    },
    {
        version = "4.1.1",
        sections = {
            {
                title = "Kaliel's Tracker header styling",
                entries = {
                    { text = "Added five independent, opt-in settings to match Kaliel's header texture, background color, font, title/collapse-icon color, and AWP header-button color. Every setting defaults off and restores AWP's original appearance when disabled.", level = 1 },
                }
            },
            {
                title = "Mapzeroth and Farstrider routing performance",
                entries = {
                    { text = "Cooldown events no longer run backend capability scans or route planning during combat. Repeated combat events are combined into one validation after combat ends.", level = 1 },
                    { text = "Out-of-combat cooldown bursts are combined into one fixed validation window, while inventory, toy, spellbook, and hearthstone changes remain responsive.",           level = 1 },
                    { text = "Accepted routes now retain numeric travel-action dependencies so selected spells and items can be checked separately from full route discovery.",                    level = 1 },
                    { text = "Failed or inaccessible backend state scans no longer fall through into unnecessary replans.",                                                                        level = 1 },
                    { text = "`/awp churn` now reports per-backend validation, coalescing, combat deferral, state-change, failure, stale-work, and dependency-check counts.",                      level = 1 },
                }
            },
            {
                title = "Objective tracker freeze in scenario content",
                entries = {
                    { text = "Fixed Blizzard's objective tracker locking up while the Tracker Viewer is docked into it. In delves, vaults, incursions and other scenario content, Blizzard's scenario tracker reads aura and spell-cooldown data that the 12.1 client withholds from addon-influenced code. When that read failed it aborted the tracker's module layout partway, so quests, world quests, campaign and achievement blocks all stopped updating.", level = 1 },
                    { text = "Tracker Viewer now wraps the two affected Blizzard entry points for exactly as long as it is docked, falling back to a safe result only when the original call actually fails, and restores Blizzard's originals the moment the viewer is disabled. Behavior is unchanged whenever the original call succeeds.",                                                                                                                     level = 1 },
                }
            },
            {
                title = "Performance fixes",
                entries = {
                    { text = "Guide step updates no longer force a second full objective tracker layout on every goal-progress tick.", level = 1 },
                }
            },
        },
    },
    {
        version = "4.1.0d",
        sections = {
            {
                title = "Kaliel's Tracker compatibility",
                entries = {
                    { text = "Fixed a Kaliel's Tracker 8.7.x error when Tracker Viewer attached and the tracker attempted to collapse its header before the expected header icon existed.",                                                                 level = 1 },
                    { text = "Tracker Viewer now creates the Kaliel-compatible header structure before applying Kaliel's header behavior, preserving its styling and click-to-collapse interaction without writing into Kaliel's private module settings.", level = 1 },
                    { text = "Tracker Viewer now waits for Kaliel's deferred initialization to finish before attaching, including late-load and reload handling.",                                                                                          level = 1 },
                }
            },
        },
    },
    {
        version = "4.1.0c",
        sections = {
            {
                title = "Patch 12.1 Compatibility",
                entries = {
                    { text = "Bumped TOC to patch 12.1.0.",                                                                                                                                                                                                                                                          level = 1 },
                    { text = "Blizzard moved `GetNextWaypointForMap` from `C_SuperTrack` to `C_Navigation` in 12.1. AWP now calls it from its new location.",                                                                                                                                                        level = 1 },
                    { text = "That call sits on the 3D world overlay's route validation path, which runs 20 times per second while a waypoint is tracked. On 12.1 it raised a silent Lua error on every pass, which could stop the 3D overlay from drawing and raise CPU use for as long as a waypoint was active.", level = 1 },
                }
            },
        },
    },
    {
        version = "4.1.0b",
        sections = {
            {
                title = "Blizzard Quest POI Routing",
                entries = {
                    { text = "Fixed supertracked Blizzard quest POIs that could jump from the clicked active quest destination back to a quest-offer or quest-giver location after opening the map or refreshing quest-log data.", level = 1 },
                    { text = "Active supertracked and tracked quest refreshes now resolve through active quest/task destination data. Actual quest-offer pins still use quest-offer resolution.",                                  level = 1 },
                }
            },
        },
    },
    {
        version = "4.1.0a",
        sections = {
            {
                title = "TOC BUMP",
                entries = {
                    { text = "Bumped TOC to patch 12.0.7", level = 1 },
                }
            },
        },
    },
    {
        version = "4.1.0",
        sections = {
            {
                title = "Zygor Tracker Viewer",
                entries = {
                    { text = "Added a new Tracker Viewer, an optional Zygor guide display that docks the current guide cleanly into the objective tracker instead of requiring Zygor's full-size native viewer.",                                          level = 1 },
                    { text = "Tracker Viewer supports both Blizzard's Objective Tracker and Kaliel's Tracker.",                                                                                                                                            level = 1 },
                    { text = "The Zygor tracker header shows the guide title, previous/next step buttons, guide switching, Zygor menu/settings access, and square, rounded, or hidden progress bar styles.",                                               level = 1 },
                    { text = "Added contextual Tracker Viewer text colors for accept, turn-in, complete, travel, kill, talk, use, and tip rows, plus an option to force all tracker step text to a selected color.",                                       level = 1 },
                    { text = "Long Zygor tip blocks collapse by section in Tracker Viewer when a single step contains many tips, with hover tooltips for collapsed rows so large steps, such as raid-mechanic instructions, do not overflow the tracker.", level = 1 },
                    { text = "Active Zygor sticky steps display as separate grouped tracker blocks above the current guide step in Tracker Viewer.",                                                                                                       level = 1 },
                    { text = "Confirm rows such as `Click Here to Continue` can be clicked to continue to the next Zygor step in Tracker Viewer mode.",                                                                                                    level = 1 },
                    { text = "When no Zygor guide is loaded, Tracker Viewer shows a message that opens Zygor's guide picker.",                                                                                                                             level = 1 },
                }
            },
            {
                title = "Zygor native viewer controls",
                entries = {
                    { text = "Added `Hide Zygor's Native Frame` as a Zygor option, so users can visually hide Zygor's full-size viewer.",                                                                                                                                           level = 1 },
                    { text = "Native Zygor viewer hiding cloaks and moves the viewer off screen while keeping Zygor's guide engine, active guide state, waypoints, guide picker, and settings available.",                                                                          level = 1 },
                    { text = "Added open-guide switching, current-guide closing, guide picker, Zygor guide menu, and Zygor settings actions for users who keep Zygor's native viewer hidden.",                                                                                      level = 1 },
                    { text = "Added macro-friendly `/awp zygor` guide controls for next, previous, skip, guide picker, guide loading by title, menu, settings, open-guide list, guide switching, and guide closing.",                                                               level = 1 },
                    { text = "Added `/awp zygor reset` to recover a lost or glitched native Zygor viewer. It unhides the viewer and resets Zygor's own window back to its default position. This is intended as a recovery option if the native viewer ever becomes inaccessible.", level = 1 },
                    { text = "Added optional local chat-frame step display for the current Zygor step on step change, including step percentage, contextual or selected text colors, and sticky step summaries.",                                                                   level = 1 },
                    { text = "Added `/awp zygor output` to show the current Zygor step in your own chat frame with step percentage, contextual or selected text colors, and sticky step summaries.",                                                                                level = 1 },
                }
            },
            {
                title = "Native minimap button",
                entries = {
                    { text = "Added an AzerothWaypoint minimap button.",                                                                                                                                                    level = 1 },
                    { text = "Left-click opens the AWP quick menu, right-click opens AWP settings, dragging supports minimap-edge snapping near the minimap and free-floating placement when pulled away.",                 level = 1 },
                    { text = "Minimap button position and visibility can be controlled with `/awp minimap show|hide|toggle|reset|status`.",                                                                                 level = 1 },
                    { text = "Added addon compartment support with the same quick menu, tooltip, and settings access so users can still reach the same AWP menu when the minimap button is hidden.",                        level = 1 },
                    { text = "The minimap quick menu includes Tracker Viewer toggle, Zygor native viewer toggle, Zygor guide controls, Open AWP Settings, Open Help, Open Queue, reset position, and hide button actions.", level = 1 },
                }
            },
            {
                title = "Flight Map Assist",
                entries = {
                    { text = "Added Flight Map Assist, which can highlight the intended flight path destination when the active AWP route includes a matched taxi leg.",                                                 level = 1 },
                    { text = "Added an optional AWP taxi list attached to the flight map, with route destination, favorites, recent flights, current-zone flights, search, and reachable destinations grouped by zone.", level = 1 },
                    { text = "The taxi list can auto-attach to the side with available screen space, update its side when the flight map is moved, center against the visible map area, and resize based on content.",   level = 1 },
                    { text = "Taxi list text-size option for adjusting font readability in the list of destinations.",                                                                                                   level = 1 },
                    { text = "Taxi list rows can take reachable flights, toggle favorites, and pulse the matching map node on hover.",                                                                                   level = 1 },
                    { text = "When InFlight is installed and has matching timing data, the AWP taxi list can show exact or estimated flight times without importing or copying InFlight's database.",                    level = 1 },
                    { text = "Zygor / LibRover taxi legs carry exact Blizzard taxi node metadata for precise flight map matching.",                                                                                      level = 1 },
                    { text = "Mapzeroth `flightpath` legs now normalize to AWP taxi route legs, allowing strict visible coordinate/name matching where available.",                                                      level = 1 },
                    { text = "Added opt-in `Auto Take Flight Paths` modes for exact matches or strong matches. This is disabled by default, and holding `Alt` suppresses it for the current flight-map interaction.",    level = 1 },
                    { text = "Added `/awp flightassist marker on|off|toggle|status`, `/awp flightassist auto disabled|exact|strong|status`, and `/awp flightassist catalog on|off|toggle|reset|status`.",                level = 1 },
                }
            },
            {
                title = "Queue panel access",
                entries = {
                    { text = "`/awp queue`, `/awp queue list`, and the minimap button's Open Queue action now force the quest-log side panel open for that interaction so the AWP queue tab is visible even when the user's normal world-map quest log panel is hidden.", level = 1 },
                    { text = "The forced queue-open path does not change saved user map or quest-log settings. It behaves like an explicit quest-log open only for the requested queue display action.",                                                                  level = 1 },
                }
            },
            {
                title = "Objective tracker diagnostics",
                entries = {
                    { text = "Added objective tracker visibility diagnostics that prefer Kaliel's Tracker when present and fall back to Blizzard's ObjectiveTrackerFrame.",                                                                                                      level = 1 },
                    { text = "`/awp status` now reports the objective tracker viewer, hard-hidden state, opacity state, Tracker Viewer state, Zygor native viewer state, local chat-frame step-display state, Flight Map Assist and Taxi List state, and minimap button state.", level = 1 },
                    { text = "AWP now warns after login or reload when Tracker Viewer is enabled but the active objective tracker is hard-hidden, or when it appears transparent due to tracker opacity or mouseover behavior.",                                                 level = 1 },
                }
            },
            {
                title = "Options and help",
                entries = {
                    { text = "Added Zygor options for Enable Tracker Viewer, Hide Zygor's Native Frame, Tracker Viewer Progress Bar, Tracker Viewer Text, Show Step in Chat Frame on Step Change, Chat-Frame Step Text, and Chat-Frame Sticky Summary.", level = 1 },
                    { text = "Added General > Routing options for Show Flight Map Route Marker, Auto Take Flight Paths, Show Flight Map Taxi List, Flight Map Taxi List Side, and Flight Map Taxi List Text Size.",                                      level = 1 },
                    { text = "Added General > Interface > Show Minimap Button.",                                                                                                                                                                         level = 1 },
                    { text = "Added a bottom-tab Integrations page in AWP options and a matching Help page that explain supported addons, route backends, Blizzard sources, and what AWP uses each for.",                                                level = 1 },
                    { text = "Updated option previews and help media for Tracker Viewer, tracker progress bar styles, tracker text colors, and the minimap button.",                                                                                     level = 1 },
                    { text = "Reorganized in-game help to give Zygor Integration its own page and added a dedicated Zygor Tracker Viewer page.",                                                                                                         level = 1 },
                    { text = "Added minimap button documentation to the Options and Customization help page.",                                                                                                                                           level = 1 },
                    { text = "Updated command help for `/awp trackerviewer`, `/awp zygorviewer`, `/awp zygor`, and `/awp minimap`.",                                                                                                                     level = 1 },
                    { text = "In-game help page text is now selectable. Drag-select any command or text and press Ctrl+C to copy it.",                                                                                                                   level = 1 },
                }
            },
            {
                title = "Text rendering fixes",
                entries = {
                    { text = "Escaped literal pipe characters in help text so command examples such as `on|off|toggle` display correctly instead of being interpreted as WoW markup.",         level = 1 },
                    { text = "Escaped literal pipe characters in chat diagnostics while preserving valid WoW color, atlas, texture, and hyperlink escapes.",                                   level = 1 },
                    { text = "Tracker Viewer rows now strip Zygor inline color markup before applying AWP tracker colors, preventing stale Zygor styling from leaking into docked step rows.", level = 1 },
                }
            },
            {
                title = "General Fixes",
                entries = {
                    { text = "Closing all Zygor guide tabs now invalidates AWP's guide route state so the last guide waypoint is cleared instead of lingering after Zygor has no active guide.",                                      level = 1 },
                    { text = "`/awp zygor output` labels the active step with a \"Current step:\" header and uses a clear indent hierarchy, so the active step's objectives don't blend into the sticky block displayed above them.", level = 1 },
                    { text = "Throttled the surrogate navigation point chat notice to once every 30 seconds while preserving the existing once-per-waypoint guard.",                                                                  level = 1 },
                    { text = "Removed the duplicate AWP prefix from the surrogate navigation point notice.",                                                                                                                          level = 1 },
                }
            },
            {
                title = "Developer reference material",
                entries = {
                    { text = "Added RestedXP reference documentation and template files for future guide-provider work.", level = 1 },
                    { text = "Added Dugi folder for future guide-provider work.",                                         level = 1 },
                }
            },
        },
    },
    {
        version = "4.0.1b",
        sections = {
            {
                title = "Native overlay long-distance routing",
                entries = {
                    { text = "Improved surrogate navigation point selection for far-away world overlay targets by projecting through the real world map, trying target/player map lineage candidates, validating round trips, and logging clearer failure reasons.", level = 1 },
                    { text = "Avoided replacing the real target with a surrogate when Blizzard's native navigation can already resolve the target map directly.",                                                                                                    level = 1 },
                    { text = "Cleared unavailable surrogate hosts instead of falling back to an unroutable original target, preventing repeated native-navigation retries and hidden overlay churn on unsupported long-distance routes.",                            level = 1 },
                    { text = "Added a short settle window after setting the native navigation host so transient missing-waypoint or frame-destroyed events do not immediately mark a fresh route probe as failed.",                                                  level = 1 },
                    { text = "Added a one-time in-game notice when AWP uses an intermediate navigation point because Blizzard may not reliably supertrack the requested target at the current distance.",                                                            level = 1 },
                }
            },
            {
                title = "Manual route cancellation",
                entries = {
                    { text = "Pending manual routes with planned legs can now present through TomTom before the strict route transaction is fully committed.",                                                                    level = 1 },
                    { text = "Removing TomTom's active waypoint while a strict manual route is still pending now cancels the pending manual queue transaction cleanly instead of treating it like a committed manual authority.", level = 1 },
                    { text = "Manual arrival checks now run only for committed manual authority routes, avoiding arrival cleanup against pending transactions.",                                                                  level = 1 },
                }
            },
            {
                title = "Adopted Blizzard waypoint stability",
                entries = {
                    { text = "Blizzard supertrack-clear suppression now applies to every adopted user waypoint publish, not only manual ask-mode clicks, so AWP-adopted waypoints are less likely to be cleared immediately after adoption.", level = 1 },
                }
            },
        },
    },
    {
        version = "4.0.1a",
        sections = {
            {
                title = "SilverDragon waypoint adoption taint fix",
                entries = {
                    { text = "Removed the SilverDragon-specific deferred TomTom adoption path. SilverDragon waypoints now adopt synchronously through the same `RouteExternalTomTomWaypoint` path other external sources already use.", level = 1 },
                }
            },
            {
                title = "Special travel button combat safety",
                entries = {
                    { text = "Disarm requests that arrive during combat lockdown are now queued onto `PLAYER_REGEN_ENABLED` via a new `pendingSpecialActionClear` flag, mirroring the existing `pendingSpecialAction` re-apply, instead of partially clearing protected attributes mid-combat.", level = 1 },
                    { text = "Centralized the out-of-combat secure-button reset into `ParkSecureActionButton` - clear state driver, hide, clear points, reparent to `UIParent`, recenter - so every cleanup site takes the same safe sequence.",                                                 level = 1 },
                    { text = "`ShowSecureActionVisuals` now defers the whole presentation update during combat lockdown rather than running `HideSpecialActionVisuals` partway through.",                                                                                                        level = 1 },
                }
            },
        },
    },
    {
        version = "4.0.1",
        sections = {
            {
                title = "HandyNotes integration",
                entries = {
                    { text = "Added HandyNotes - including plugins such as MapNotes and HandyNotes_TheWarWithin - as a recognized transient external waypoint source, adopted from both `C_Map.SetUserWaypoint` and `TomTom:AddWaypoint` calls.",                                                                                                                                                           level = 1 },
                    { text = "Added a generic HandyNotes icon spec used for adopted HandyNotes waypoints.",                                                                                                                                                                                                                                                                                                 level = 1 },
                    { text = "MapNotes pin clicks now reverse-map the HandyNotes plugin iterator's icon path back to one of the existing AWP icons (portal, travel, inn, dungeon, delve, profession trainer, vendor, mailbox, banker, auctioneer, barber, transmog, stable master) so the overlay reflects the kind of pin that was clicked.",                                                              level = 1 },
                    { text = "Snapshotted the open tooltip's first line at right-click time so the \"Set map waypoint\" option in HandyNotes plugins preserves the node label even though `C_Map.SetUserWaypoint` itself accepts no title. Captured text is cleaned of inline icon textures, atlas escapes, and hyperlink wrappers before use.",                                                            level = 1 },
                    { text = "Plugin OnClick hooks are installed at login and on every subsequent `RegisterPluginDB`, so HandyNotes plugins that load after AWP are still covered.",                                                                                                                                                                                                                        level = 1 },
                    { text = "Per-source icon resolver framework: `RegisterExternalWaypointSource` accepts an optional `resolveIconKey(mapID, x, y)` callback, and `NS.ResolveExternalWaypointIconKey` threads the result through meta, authority record (and persistence), queue items, and presentation snapshot - including both content signatures - so per-call icon overrides cache-bust correctly.", level = 1 },
                    { text = "`/awp waytype` now also prints `sourceAddonIconKey=` so the resolved icon hint can be inspected.",                                                                                                                                                                                                                                                                            level = 1 },
                }
            },
            {
                title = "Routing fixes",
                entries = {
                    { text = "Fallback route outcomes are no longer treated as failures even for strict route records, so the fallback completes instead of rolling back the pending manual queue transaction.", level = 1 },
                }
            },
            {
                title = "WhoWhere search adoption",
                entries = {
                    { text = "Zygor WhoWhere search results are now adopted as transient manual routes via `RequestManualRoute` instead of only being tagged, so the search result's title flows through to the overlay. A per-adoption serial guards against stale results when the search changes mid-frame.", level = 1 },
                }
            },
            {
                title = "Help frame",
                entries = {
                    { text = "Replaced the static page X / N indicator with a clickable dropdown that lists every help page by name. The dropdown closes when the help frame is hidden.", level = 1 },
                }
            },
        },
    },
    {
        version = "4.0.0d",
        sections = {
            {
                title = "TomTom combat visibility",
                entries = {
                    { text = "Replaced the secure-parent host approach with a root-frame alpha cloak so TomTom's full crazy arrow stack (textures and text) hides together without calling protected hide/show paths.", level = 1 },
                    { text = "Disabled mouse input on the cloaked arrow, skipping the call when the arrow is protected during combat lockdown to avoid blocked-action errors.",                                         level = 1 },
                    { text = "Restored the arrow through TomTom's own `ShowHideCrazyArrow()` path after combat ends.",                                                                                                  level = 1 },
                    { text = "Kept `[combat] hide, show` secure visibility scoped to the special travel button only.",                                                                                                  level = 1 },
                    { text = "Fixed Hide During Combat's disabled state so it no longer creates or briefly reparents TomTom's arrow into the secure combat visibility host.",                                           level = 1 },
                }
            },
            {
                title = "TomTom arrow-skin protected-call safety",
                entries = {
                    { text = "Only resizes TomTom's root arrow frame when dimensions actually change.",                                                        level = 1 },
                    { text = "Skips root-size writes only when in combat lockdown AND the arrow frame is protected, so out-of-combat resizes always proceed.", level = 1 },
                }
            },
            {
                title = "External waypoint adoption",
                entries = {
                    { text = "Deferred SilverDragon TomTom waypoint adoption to the next frame.",             level = 1 },
                    { text = "Deduped matching Blizzard user-waypoint publishes from the same secure click.", level = 1 },
                }
            },
        },
    },
    {
        version = "4.0.0c",
        sections = {
            {
                title = "Routing fixes",
                entries = {
                    { text = "Restricted third-party POIButton supertrack calls to the addon adoption controls instead of treating them as native Blizzard POI clicks.",                                                                 level = 1 },
                    { text = "Fixed task-zone and world-quest-style supertracked POIs being cleared as missing when they are valid map tasks but not normal quest-log entries.",                                                         level = 1 },
                    { text = "Added task-zone and world-quest-style cleanup for explicit completion, full progress, and expiry signals.",                                                                                                level = 1 },
                    { text = "Fixed RareScanner popup waypoint clicks being adopted more than once from a single click by treating the mouse-down publish as a transient duplicate while preserving normal clear and removal behavior.", level = 1 },
                    { text = "Fixed registered external waypoint sources that publish both TomTom and Blizzard user-waypoint signals in one action, such as SilverDragon, from creating duplicate AWP route adoptions.",                 level = 1 },
                    { text = "Preserved named TomTom waypoint titles when a matching nameless Blizzard user-waypoint signal follows in the same external-addon publish burst.",                                                          level = 1 },
                    { text = "Fixed arrival auto-clear for transient external TomTom waypoint routes by validating active transient queues as well as persistent manual queues.",                                                        level = 1 },
                }
            },
        },
    },
    {
        version = "4.0.0b",
        sections = {
            {
                title = "Routing and combat visibility",
                entries = {
                    { text = "Added Hide During Combat with options for Disabled, TomTom + Travel Button, World Overlay, and Both.",                                                                                                   level = 1 },
                    { text = "TomTom combat hiding uses a secure visibility wrapper so the TomTom arrow and special travel button can be hidden during combat without protected-frame errors.",                                        level = 1 },
                    { text = "Added player control lost/gained route refresh handling so taxi and flightpath start/end events replan the active route and recompute the TomTom carrier.",                                              level = 1 },
                    { text = "Added separate Quick-Start Popup and What's New Popup settings, each with account-wide, per-character, and disabled modes. Quick-start defaults to per-character, What's New defaults to account-wide.", level = 1 },
                }
            },
            {
                title = "Compatibility fixes",
                entries = {
                    { text = "Added a WorldQuestTab click fallback for bonus objectives and other non-world-quest entries that have valid quest coordinates but do not emit Blizzard waypoint or supertrack signals.", level = 1 },
                    { text = "Added transparency, transparent, alpha, and visibility tags to the opacity options so searching transparency will find the opacity controls.",                                           level = 1 },
                    { text = "Prevented transient external waypoint sources such as RareScanner and SilverDragon from opening the manual queue placement prompt.",                                                     level = 1 },
                    { text = "Renamed addon waypoint adoption list internals and wording to Allowlist/Blocklist.",                                                                                                     level = 1 },
                    { text = "Fixed update detection for lettered hotfix versions such as 4.0.0a to 4.0.0b.",                                                                                                          level = 1 },
                }
            },
        },
    },
    {
        version = "4.0.0a",
        sections = {
            {
                title = "Compatibility fixes",
                entries = {
                    { text = "Fixed the native world overlay failing to load when Zygor Guides Viewer is disabled or unavailable.",                                                   level = 1 },
                    { text = "Removed an accidental hard dependency on Zygor guide-resolver helpers from the shared world overlay presentation layer.",                               level = 1 },
                    { text = "Added safe fallback helpers for overlay text normalization, coordinate subtext, guide-goal visibility, quest IDs, goal coordinates, and goal actions.", level = 1 },
                    { text = "Guarded Zygor canonical-goal handling so APR, WoWPro, manual routing, queues, and non-Zygor routing backends can initialize normally without Zygor.",   level = 1 },
                }
            },
        },
    },
    {
        version = "4.0.0",
        sections = {
            {
                title = "AzerothWaypoint rename and v4 reset",
                entries = {
                    { text = "AzerothWaypoint replaces ZygorWaypoint across the addon TOC, namespace, media paths, help text, settings text, chat output, and `/awp` command surface.",                                             level = 1 },
                    { text = "Legacy v1/v2/v3 SavedVariables migration/repair paths were removed. `ApplyDBDefaults` now fills and normalizes the new database shape instead of carrying old upgrade logic.",                        level = 1 },
                    { text = "Startup detects an old `ZygorWaypoint` addon still loaded/installed and warns about the conflict. `StartZygorWaypointConflictReminders` repeats a reminder until the old addon is disabled/removed.", level = 1 },
                    { text = "TomTom is the only required dependency. Zygor Guides Viewer, APR, WoWPro, Mapzeroth, FarstriderLib, FarstriderLibData, and WorldQuestTab are optional integrations.",                                 level = 1 },
                }
            },
            {
                title = "Startup prompts and first-run guidance",
                entries = {
                    { text = "Added a Zygor arrow conflict prompt: when Zygor's own Waypoint Arrow is enabled, AWP offers a one-click \"Turn Off Zygor Arrow\" action or a decline option.", level = 1 },
                    { text = "The Zygor arrow prompt is delayed at startup so it does not collide with other startup popups.",                                                               level = 1 },
                }
            },
            {
                title = "Guide provider system",
                entries = {
                    { text = "Replaced the old Zygor-only guide path with a guide provider dispatcher.",                                                                     level = 1 },
                    { text = "Added built-in providers for:",                                                                                                                level = 1 },
                    { text = "Zygor Guides Viewer.",                                                                                                                         level = 2 },
                    { text = "Azeroth Pilot Reloaded.",                                                                                                                      level = 2 },
                    { text = "WoWPro.",                                                                                                                                      level = 2 },
                    { text = "Providers register label, icon, tint, size, visibility, extraction, activation token, hooks, and debug behavior through the provider API.",    level = 1 },
                    { text = "Guide provider state is tracked separately per provider, with active-provider persistence and passive guide queue projection.",                level = 1 },
                    { text = "Explicit guide activation can switch the active guide provider while manual/transient route authority remains higher priority.",               level = 1 },
                    { text = "Guide queues can exist for providers that are visible but not currently controlling the active route.",                                        level = 1 },
                    { text = "Provider and presentation files are loaded from the TOC, but provider-specific code exits early when the source addon is not loaded/enabled.", level = 1 },
                }
            },
            {
                title = "Zygor integration",
                entries = {
                    { text = "Preserved Zygor parity including:",                                                                                                                            level = 1 },
                    { text = "Zygor guide resolver.",                                                                                                                                        level = 2 },
                    { text = "Canonical target extraction.",                                                                                                                                 level = 2 },
                    { text = "LibRover-backed routing backend.",                                                                                                                             level = 2 },
                    { text = "Zygor POI takeover.",                                                                                                                                          level = 2 },
                    { text = "Compact viewer chrome.",                                                                                                                                       level = 2 },
                    { text = "Starlight and Stealth arrow themes.",                                                                                                                          level = 2 },
                    { text = "Moved Zygor POI support out of `bridge/takeovers/tomtom_bridge_zygor_poi_takeover.lua` into `integrations/guides/zygor/zygor_poi.lua`.",                       level = 1 },
                    { text = "Zygor provider code now participates in the same provider arbitration system as APR and WoWPro.",                                                              level = 1 },
                    { text = "Zygor guide presentation continues to use the existing resolver, facts, live context, presentation context, snapshots, cases, scans, and resolution modules.", level = 1 },
                }
            },
            {
                title = "APR integration",
                entries = {
                    { text = "Added APR provider support under `integrations/guides/apr/`.",                                                                                   level = 1 },
                    { text = "Extracts active step, route coordinates, title, visibility, activation token, and guide queue projection.",                                      level = 1 },
                    { text = "APR coordinates are treated as APR world-space coordinates, not 0-100 map percentages.",                                                         level = 1 },
                    { text = "Added `apr_presentation.lua` for actionable APR overlay titles:",                                                                                level = 1 },
                    { text = "`Accept 'Quest Name'`",                                                                                                                          level = 2 },
                    { text = "`Turn in 'Quest Name'`",                                                                                                                         level = 2 },
                    { text = "exact objective text for progress steps when available.",                                                                                        level = 2 },
                    { text = "Multi-quest pickup/turn-in steps select one actionable quest title at a time instead of cramming multiple quest names into one title.",          level = 1 },
                    { text = "APR helper text uses `ExtraLineText`, `ExtraLineText2`, and APR text/locale resolution helpers.",                                                level = 1 },
                    { text = "Quest-backed APR steps set quest semantics and quest icon hints only when a real quest ID is found.",                                            level = 1 },
                    { text = "Added APR debug output for action key, quest IDs, primary quest ID, title source, subtext source, final title, final subtext, and coordinates.", level = 1 },
                    { text = "Added `integrations/guides/apr/APR-Route-Syntax.md` as local implementation reference material.",                                                level = 1 },
                }
            },
            {
                title = "WoWPro integration",
                entries = {
                    { text = "Added WoWPro provider support under `integrations/guides/wowpro/`.",                                                                                 level = 1 },
                    { text = "Extracts active step index, guide ID, map ID, coordinate strings, visibility, and queue projection.",                                                level = 1 },
                    { text = "WoWPro coordinates are parsed as 0-100 percentages and converted to AWP's 0-1 coordinate format.",                                                   level = 1 },
                    { text = "Multi-coordinate WoWPro steps choose the final destination target used by WoWPro's own routing logic.",                                              level = 1 },
                    { text = "Added `wowpro_presentation.lua` for actionable WoWPro overlay titles:",                                                                              level = 1 },
                    { text = "accept steps.",                                                                                                                                      level = 2 },
                    { text = "turn-in steps.",                                                                                                                                     level = 2 },
                    { text = "completion/progress steps.",                                                                                                                         level = 2 },
                    { text = "note/instruction steps.",                                                                                                                            level = 2 },
                    { text = "travel, use, and loot actions.",                                                                                                                     level = 2 },
                    { text = "Completion steps can use the WoWPro note as title while objective progress becomes subtext, such as `1/6 Blackrock Worg slain`.",                    level = 1 },
                    { text = "Quest progress subtext prefers WoWPro objective data and falls back to shared Blizzard quest helpers.",                                              level = 1 },
                    { text = "WoWPro TomTom and `C_Map.SetUserWaypoint` signals are handled as guide provider input, not generic manual queue adoption.",                          level = 1 },
                    { text = "Added WoWPro debug output for action, raw step, note, QO data, quest IDs, primary quest ID, title/subtext sources, final title, and final subtext.", level = 1 },
                    { text = "Added `integrations/guides/wowpro/WoWPro-Syntax.md` as local implementation reference material.",                                                    level = 1 },
                }
            },
            {
                title = "Routing backends",
                entries = {
                    { text = "Routing is now planned by selectable backends instead of being tied directly to one guide addon.",                                                      level = 1 },
                    { text = "Added four routing backends:",                                                                                                                          level = 1 },
                    { text = "TomTom Direct: always-available single-leg fallback.",                                                                                                  level = 2 },
                    { text = "Farstrider: FarstriderLib/FarstriderLibData routing with portals, boats, zeppelins, items, spells, and availability invalidation.",                     level = 2 },
                    { text = "Mapzeroth: Mapzeroth graph routing with travel nodes and instance entrance support.",                                                                   level = 2 },
                    { text = "Zygor: LibRover-backed routing for Zygor users.",                                                                                                       level = 2 },
                    { text = "TomTom Direct: always-available single-leg fallback. PURE TomTom, no pathfinding.",                                                                     level = 2 },
                    { text = "First-run backend priority is Zygor > Farstrider > Mapzeroth > TomTom Direct.",                                                                         level = 1 },
                    { text = "Invalid or unavailable backend selections fall back to Direct.",                                                                                        level = 1 },
                    { text = "The backend dropdown exposes backend availability and disabled/missing states.",                                                                        level = 1 },
                    { text = "Route signatures include guide provider/source details so identical coordinates from different providers do not merge into the wrong authority state.", level = 1 },
                    { text = "Added backend-specific fallback handling for missing planners, no-path results, empty plans, timeout fallbacks, and direct fallback legs.",             level = 1 },
                }
            },
            {
                title = "Routing engine rewrite",
                entries = {
                    { text = "Replaced the old monolithic bridge sync model with modular `bridge/routing/` files.",                                                                                 level = 1 },
                    { text = "Added explicit routing layers:",                                                                                                                                      level = 1 },
                    { text = "Authority: current manual/guide ownership and persisted manual route state.",                                                                                         level = 2 },
                    { text = "Identity: normalized metadata for manual routes, map pins, quests, area POIs, vignettes, taxis, dig sites, housing plots, Zygor POIs, and external callers.",         level = 2 },
                    { text = "Backend: pluggable route planning.",                                                                                                                                  level = 2 },
                    { text = "Carrier: TomTom Arrow synchronization.",                                                                                                                              level = 2 },
                    { text = "Presentation: shared title, subtext, icon hint, semantic kind, and route leg display data.",                                                                          level = 2 },
                    { text = "Persistent active-route source now survives reload/login when possible.",                                                                                             level = 1 },
                    { text = "Route environment tracking captures zone, real zone, subzone, minimap zone, indoor state, and route gate matching.",                                                  level = 1 },
                    { text = "The v3 TickUpdate heartbeat is no longer the primary route driver, v4 routing reacts through explicit evaluator and invalidation paths. Cleaner and more efficient.", level = 1 },
                    { text = "Improved TomTom carrier synchronization, external clear detection, route invalidation, and guide visibility hooks.",                                                  level = 1 },
                }
            },
            {
                title = "Special travel actions",
                entries = {
                    { text = "Added route legs for items, spells, toys, hearthstones, and similar travel actions.",                                  level = 1 },
                    { text = "Added a secure special travel button that replaces the arrow when the current route leg requires a clickable action.", level = 1 },
                    { text = "Added combat-safe secure attribute handling.",                                                                         level = 1 },
                    { text = "Added route replan suppression while a special action is being prepared or clicked.",                                  level = 1 },
                    { text = "Added Special Travel Button Scale in the TomTom Arrow options section.",                                               level = 1 },
                    { text = "Added special travel button preview metadata and help media.",                                                         level = 1 },
                }
            },
            {
                title = "Manual queues",
                entries = {
                    { text = "Added queue modules under `bridge/routing/queues/` for state, items, routing, policy, projection, and snapshots.",                                               level = 1 },
                    { text = "Added persistent manual queues with stable queue IDs, labels, active item index, item metadata, and route restoration.",                                         level = 1 },
                    { text = "Added destination queues for multi-destination manual-click flows.",                                                                                             level = 1 },
                    { text = "Added route queues for single route-like entries.",                                                                                                              level = 1 },
                    { text = "Added transient queues for short-lived external sources such as SilverDragon, RareScanner, and gossip-style (such as guard directions) transient destinations.", level = 1 },
                    { text = "Added guide-projected queues so active guide destinations appear in the queue panel even when another source controls the route.",                               level = 1 },
                    { text = "Manual queues stay listed when guide routing is active.",                                                                                                        level = 1 },
                    { text = "Guide queues stay listed when a manual queue is active.",                                                                                                        level = 1 },
                    { text = "`StopUsingManualQueue` lets a queue stop controlling the active route without deleting that queue.",                                                             level = 1 },
                    { text = "Queue follow-up advances to the next queued destination after clear/arrival.",                                                                                   level = 1 },
                    { text = "Imported `/ttpaste` and similar multi-waypoint batches are always stored and routed as ordered AWP queues.",                                                     level = 1 },
                }
            },
            {
                title = "Queue UI",
                entries = {
                    { text = "Added a waypoint queue side tab on the world map.",                                                                                                                          level = 1 },
                    { text = "Added queue list view, detail view, summary panel, scrollable rows, and queue sections.",                                                                                    level = 1 },
                    { text = "Queue sections include transient queues, manual queues, and user guide queues.",                                                                                             level = 1 },
                    { text = "Added queue activation, queue deactivation, queue clearing, destination activation, destination removal, final-destination focus, import support, and quest-log switching.", level = 1 },
                    { text = "Added per-row delete icons",                                                                                                                                                 level = 1 },
                    { text = "Added checkbox multi-select for queues and destinations.",                                                                                                                   level = 1 },
                    { text = "Added bulk delete icons inside the panel/detail borders.",                                                                                                                   level = 1 },
                    { text = "Added context menus for queue rows and destination rows.",                                                                                                                   level = 1 },
                    { text = "Guide queues are read-only.",                                                                                                                                                level = 1 },
                    { text = "Added `/awp queue` commands for panel/open/show, list/ls, use, clear, remove/rm, move, import/paste/ttpaste, and help.",                                                     level = 1 },
                }
            },
            {
                title = "Manual click queue prompt",
                entries = {
                    { text = "Added Manual Click Queue Behavior with Create New Queue, Replace Active, Append, and Ask.",                                        level = 1 },
                    { text = "Default mode is `replace`.",                                                                                                       level = 1 },
                    { text = "Unknown/invalid saved mode values normalize to `create`.",                                                                         level = 1 },
                    { text = "Ask mode opens a prompt so each manual destination can be placed as a new queue, replacement, or appended to the existing queue.", level = 1 },
                    { text = "Ask mode is integrated with user waypoint and map pin takeover flows.",                                                            level = 1 },
                    { text = "Added help/preview/search metadata for the prompt and behavior values.",                                                           level = 1 },
                }
            },
            {
                title = "Blizzard, TomTom, and addon takeovers",
                entries = {
                    { text = "Expanded takeover coverage for:",                                                                                                          level = 1 },
                    { text = "User waypoints.",                                                                                                                          level = 2 },
                    { text = "Quests and supertracked quests.",                                                                                                          level = 2 },
                    { text = "Area POIs.",                                                                                                                               level = 2 },
                    { text = "Vignettes.",                                                                                                                               level = 2 },
                    { text = "Taxi destinations.",                                                                                                                       level = 2 },
                    { text = "Gossip POIs.",                                                                                                                             level = 2 },
                    { text = "Dig sites.",                                                                                                                               level = 2 },
                    { text = "Housing plots.",                                                                                                                           level = 2 },
                    { text = "Added shared Blizzard takeover core handling for map pin changed/cleared behavior and adoption retries.",                                  level = 1 },
                    { text = "Added quest-backed manual metadata for quest ID, quest state, quest type, world quest type, source addon, semantic kind, and icon hints.", level = 1 },
                    { text = "Improved presentation for available, incomplete, complete, repeatable, world quest, dungeon, raid, delve, racing, and travel targets.",    level = 1 },
                    { text = "Improved tracked, untracked, supertracked, removed, and turned-in quest cleanup behavior for both active routes and queue items.",         level = 1 },
                    { text = "Added unknown addon waypoint adoption controls with a toggle, allowlist, blocklist, recent caller list, and chat commands.",               level = 1 },
                }
            },
            {
                title = "WorldQuestTab integration",
                entries = {
                    { text = "Added `integrations/worldquesttab_takeover.lua`.",                                                                level = 1 },
                    { text = "WorldQuestTab quest pin clicks now route through the v4 routing pipeline.",                                       level = 1 },
                    { text = "Captures title, quest ID, map, coordinates, source addon, and quest context from WorldQuestTab where available.", level = 1 },
                    { text = "Falls back to Blizzard quest APIs when WorldQuestTab data is not ready.",                                         level = 1 },
                }
            },
            {
                title = "External waypoint source registry",
                entries = {
                    { text = "Added `integrations/external_waypoint_sources.lua`.",                                                                                   level = 1 },
                    { text = "Added metadata descriptors for SilverDragon and RareScanner.",                                                                          level = 1 },
                    { text = "Centralized external source normalization, display names, transient behavior, stack/path matching, and icon keys.",                     level = 1 },
                    { text = "Replaced scattered SilverDragon/RareScanner checks in routing, queues, presentation, and world overlay content with registry helpers.", level = 1 },
                    { text = "Persisted source keys remain lowercase.",                                                                                               level = 1 },
                }
            },
            {
                title = "World overlay architecture",
                entries = {
                    { text = "Renamed the internal namespace to `NS.Internal.WorldOverlay`.",                                                                            level = 1 },
                    { text = "Split the former `world_overlay/native/` folder into:",                                                                                    level = 1 },
                    { text = "`world_overlay/core/`",                                                                                                                    level = 2 },
                    { text = "`world_overlay/assets/`",                                                                                                                  level = 2 },
                    { text = "`world_overlay/pinpoint/`",                                                                                                                level = 2 },
                    { text = "`world_overlay/presentation/`",                                                                                                            level = 2 },
                    { text = "`world_overlay/runtime/`",                                                                                                                 level = 2 },
                    { text = "Split API, config, state, icons, quest types, colors, content, frames, host, render, plaques, and plaque animation into focused modules.", level = 1 },
                    { text = "Moved shared textures from `media/world-overlay/waypoint/` to `media/world-overlay/`.",                                                    level = 1 },
                    { text = "Moved plaque textures into `media/world-overlay/plaques/`.",                                                                               level = 1 },
                }
            },
            {
                title = "World overlay presentation",
                entries = {
                    { text = "Moved icon specs and quest type handling into `world_overlay/assets/`.",                                                                                                                     level = 1 },
                    { text = "Moved color and content presentation into `world_overlay/presentation/`.",                                                                                                                   level = 1 },
                    { text = "Fixed atlas/texture carryover by resetting texture coordinates before applying atlas icons in `world_overlay/presentation/content.lua`.",                                                    level = 1 },
                    { text = "Added Gray as a neutral preset.",                                                                                                                                                            level = 1 },
                    { text = "Waypoint footer text defaults to Gray, while Auto uses contextual icon/spec tint.",                                                                                                          level = 1 },
                    { text = "Removed the old None color option because it because it was identical to White which we already offered.",                                                                                   level = 1 },
                    { text = "Color dropdown options are alphabetized and include Auto, Custom, Blue, Cyan, Gold, Gray, Green, Pink, Purple, Red, Silver, and White.",                                                     level = 1 },
                    { text = "Added shared Auto dropdown preview text explaining contextual target hints.",                                                                                                                level = 1 },
                    { text = "Added icon/tint support for gossip services, external sources, quest families, world quests, racing quests, dungeons, raids, delves, portals, taxis, inns, route legs, and travel actions.", level = 1 },
                    { text = "Available quest POIs no longer show in-progress objective subtext before the quest is accepted.",                                                                                            level = 1 },
                    { text = "Quest objective text refresh now uses shared quest helpers and cache invalidation.",                                                                                                         level = 1 },
                }
            },
            {
                title = "Pinpoint, waypoint, and navigator",
                entries = {
                    { text = "Moved plaque assets into the plaque media folder.",                                                                                      level = 1 },
                    { text = "Added help media for overlay base/fade, navigator, small navigator, pinpoint, pinpoint off, pinpoint plaque off, and all footer modes.", level = 1 },
                    { text = "Improved display state cleanup around waypoint, pinpoint, navigator, arrival, and hidden transitions.",                                  level = 1 },
                }
            },
            {
                title = "TomTom arrow skins",
                entries = {
                    { text = "Added a TomTom arrow skin framework system in `core/arrowskins.lua`.",                                                           level = 1 },
                    { text = "Added AWP, AWP Bomber, AWP Modern, Alliance, and Horde skins.",                                                                  level = 1 },
                    { text = "Each new skin ships nav, arrival, and specular assets as appropriate.",                                                          level = 1 },
                    { text = "Kept Starlight and Stealth Zygor mirror skins when Zygor is loaded.",                                                            level = 1 },
                    { text = "Added skin preset support for single-image custom arrows, TomTom classic/modern layouts, and Zygor mirror/full sprite layouts.", level = 1 },
                    { text = "Added per-skin options previews.",                                                                                               level = 1 },
                    { text = "Fixed preview key collisions for skins with spaces/custom IDs.",                                                                 level = 1 },
                    { text = "Preserved the last selected custom skin when toggling Use Custom Arrow Skin off and on.",                                        level = 1 },
                }
            },
            {
                title = "Options UI",
                entries = {
                    { text = "Replaced the old options panel with a custom options panel under `interface/options/`.",                                                                                                                                                                                      level = 1 },
                    { text = "Added About, General, TomTom Arrow, World Overlay, Waypoint, Pinpoint, Navigator, and conditional Zygor sections.",                                                                                                                                                           level = 1 },
                    { text = "Added option search, filters, release notes, preview pane, dropdown value previews, and reusable widgets.",                                                                                                                                                                   level = 1 },
                    { text = "Added image previews for option sections, arrow skins, Zygor compact/background modes, manual queue prompts, overlay enable/fade states, context display variants, waypoint/beacon/footer modes, pinpoint modes, plaque styles, navigator, and special travel button scale.", level = 1 },
                    { text = "Added search metadata for settings/sub-options that were rendered in `canvas_sections.lua` but not discoverable from `Data.OPTIONS`.",                                                                                                                                        level = 1 },
                    { text = "Added Detected Addon Callers UI with allow/deny controls.",                                                                                                                                                                                                                   level = 1 },
                    { text = "The options window remembers its on-screen position.",                                                                                                                                                                                                                        level = 1 },
                    { text = "Added a new Zygor arrow conflict prompt.",                                                                                                                                                                                                                                    level = 1 },
                }
            },
            {
                title = "Help, screenshots, and documentation",
                entries = {
                    { text = "Refreshed help pages for Overview, Arrow and Guide, World Overlay, Waypoint and Navigator, Pinpoint and Plaque, Customization, Commands, and What's New.",                                                                                                                                                                               level = 1 },
                    { text = "Added help screenshots for AWP arrow skins, Zygor arrow/guide modes, manual queue prompts, queue UI list/detail views, Blizzard POI and SilverDragon adoption, options panels, overlay base/fade states, context display variants, waypoint/beacon/footer modes, navigator, pinpoint modes, plaque styles, and special travel buttons.", level = 1 },
                    { text = "Replaced old ZWP option media with AWP option and options-general media.",                                                                                                                                                                                                                                                               level = 1 },
                }
            },
            {
                title = "Commands and aliases",
                entries = {
                    { text = "Added `/awp backend direct|zygor|mapzeroth|farstrider`.",                                                                                              level = 1 },
                    { text = "Added `/awp queue ...` with `panel`, `open`, `show`, `list`, `ls`, `use`, `clear`, `remove`, `rm`, `move`, `import`, `paste`, `ttpaste`, and `help`.", level = 1 },
                    { text = "Added `/awp untrackclear` and `/awp untrackedclear`.",                                                                                                 level = 1 },
                    { text = "Added `/awp addontakeover`, `/awp unknownaddons`, and `/awp addonwaypoints`.",                                                                         level = 1 },
                    { text = "Added/expanded diagnostics:",                                                                                                                          level = 1 },
                    { text = "`/awp routedump` / `/awp routecheck`",                                                                                                                 level = 2 },
                    { text = "`/awp routeenv` / `/awp routenv` / `/awp envroute`",                                                                                                   level = 2 },
                    { text = "`/awp traveldiag` / `/awp tdiag`",                                                                                                                     level = 2 },
                    { text = "`/awp churn`",                                                                                                                                         level = 2 },
                    { text = "`/awp churnmem` / `/awp churnphases`",                                                                                                                 level = 2 },
                    { text = "`/awp resolvercases` / `/awp resolvercase`",                                                                                                           level = 2 },
                    { text = "`/awp stepdebug`",                                                                                                                                     level = 2 },
                    { text = "`/awp waytype`",                                                                                                                                       level = 2 },
                    { text = "`/awp plaque` / `/awp pinpoint`",                                                                                                                      level = 2 },
                    { text = "Added/kept aliases:",                                                                                                                                  level = 1 },
                    { text = "`/awp options` / `/awp config`",                                                                                                                       level = 2 },
                    { text = "`/awp manualclear` / `/awp autoclear`",                                                                                                                level = 2 },
                    { text = "`/awp trackroute` / `/awp trackedroute`",                                                                                                              level = 2 },
                    { text = "`/awp questclear` / `/awp superquestclear`",                                                                                                           level = 2 },
                    { text = "`/awp compact` / `/awp guidechrome` / `/awp guidehover`",                                                                                              level = 2 },
                    { text = "`/awp help` / `/awp tour`",                                                                                                                            level = 2 },
                    { text = "`/awp changelog` / `/awp whatsnew` / `/awp whatnew` / `/awp new`",                                                                                     level = 2 },
                    { text = "Existing status, debug, diag, mem, skin, scale, routing, cleardistance, search, and repair commands continue under `/awp`.",                           level = 1 },
                }
            },
            {
                title = "Diagnostics",
                entries = {
                    { text = "Expanded `/awp waytype` for live overlay target inspection and preview targets.",                                                                                                                                  level = 1 },
                    { text = "Added source-aware waytype output for guide provider, quest hints, source addon, icon source, atlas/texture, tint, route leg, quest type, and quest status.",                                                      level = 1 },
                    { text = "Expanded route diagnostics with active source, backend, selected backend, carrier source, carrier kind, route legs, route outcome, current special action, and route environment.",                                level = 1 },
                    { text = "Expanded churn diagnostics with resolver hits/misses, manual metadata lookup, route plan accept/skip counts, backend invalidations, driver updates, world overlay updates, host sync, and optional phase memory.", level = 1 },
                    { text = "Expanded guide diagnostics for Zygor, APR, and WoWPro provider-specific output.",                                                                                                                                  level = 1 },
                }
            },
            {
                title = "Quest text and presentation helpers",
                entries = {
                    { text = "Added `core/quest_text.lua`.",                                                                                                        level = 1 },
                    { text = "Added shared quest helpers for:",                                                                                                     level = 1 },
                    { text = "quest titles.",                                                                                                                       level = 2 },
                    { text = "exact indexed objective text.",                                                                                                       level = 2 },
                    { text = "first unfinished objective or ready-to-turn-in text.",                                                                                level = 2 },
                    { text = "Updated world overlay content to reuse shared quest helpers while preserving cache behavior.",                                        level = 1 },
                    { text = "Shared quest text helpers are now used by takeovers and guide presentation layers instead of duplicating Blizzard quest API calls.",  level = 1 },
                    { text = "Quest cache invalidation now reacts to quest accepted, removed, turned in, completed, progress, gossip, and quest log update flows.", level = 1 },
                }
            },
            {
                title = "Search and repair",
                entries = {
                    { text = "Preserved `/awp search` support for services, profession trainers, profession workshops, vendor fallback, repair fallback, and aliases but only functions when Zygor is installed and enabled.", level = 1 },
                    { text = "Updated command/help text for the renamed addon and v4 routing backend behavior.",                                                                                                               level = 1 },
                    { text = "Kept `/awp repair` for current TomTom/Zygor external setting repair where relevant.",                                                                                                            level = 1 },
                    { text = "Removed old pre-v4 SavedVariables migration behavior from repair/default application.",                                                                                                          level = 1 },
                }
            },
            {
                title = "Stability and polish",
                entries = {
                    { text = "Improved reload/login behavior so the last controlling source is restored where possible.",                                                 level = 1 },
                    { text = "Fixed untrack-clear behavior so queue items are not removed when the setting is disabled.",                                                 level = 1 },
                    { text = "Added external clear detection and queue preservation for manual, transient, and guide-backed routes.",                                     level = 1 },
                    { text = "Reduced icon flicker/stale state when switching between addon POIs, gossip POIs, quest pins, atlas icons, texture icons, and route icons.", level = 1 },
                    { text = "Improved TomTom Arrow suppression for WoWPro and other guide-provider signals to reduce protected-function taint risk.",                    level = 1 },
                    { text = "Added guards so APR, WoWPro, and Zygor can retake route authority after another provider was active.",                                      level = 1 },
                    { text = "Improved title/subtext mirroring so provider presentation flows through the carrier and overlay consistently.",                             level = 1 },
                }
            },
        },
    },
}
