local NS = _G.AzerothWaypointNS

NS.CHANGELOG_DATA = {
    {
        version = "4.1.0b",
        sections = {
            { title = "Blizzard Quest POI Routing", entries = {
                { text = "Fixed supertracked Blizzard quest POIs that could jump from the clicked active quest destination back to a quest-offer or quest-giver location after opening the map or refreshing quest-log data.", level = 1 },
                { text = "Active supertracked and tracked quest refreshes now resolve through active quest/task destination data. Actual quest-offer pins still use quest-offer resolution.", level = 1 },
            }},
        },
    },
    {
        version = "4.1.0a",
        sections = {
            { title = "TOC BUMP", entries = {
                { text = "Bumped TOC to patch 12.0.7", level = 1 },
            }},
        },
    },
    {
        version = "4.1.0",
        sections = {
            { title = "Zygor Tracker Viewer", entries = {
                { text = "Added a new Tracker Viewer, an optional Zygor guide display that docks the current guide cleanly into the objective tracker instead of requiring Zygor's full-size native viewer.", level = 1 },
                { text = "Tracker Viewer supports both Blizzard's Objective Tracker and Kaliel's Tracker.", level = 1 },
                { text = "The Zygor tracker header shows the guide title, previous/next step buttons, guide switching, Zygor menu/settings access, and square, rounded, or hidden progress bar styles.", level = 1 },
                { text = "Added contextual Tracker Viewer text colors for accept, turn-in, complete, travel, kill, talk, use, and tip rows, plus an option to force all tracker step text to a selected color.", level = 1 },
                { text = "Long Zygor tip blocks collapse by section in Tracker Viewer when a single step contains many tips, with hover tooltips for collapsed rows so large steps, such as raid-mechanic instructions, do not overflow the tracker.", level = 1 },
                { text = "Active Zygor sticky steps display as separate grouped tracker blocks above the current guide step in Tracker Viewer.", level = 1 },
                { text = "Confirm rows such as `Click Here to Continue` can be clicked to continue to the next Zygor step in Tracker Viewer mode.", level = 1 },
                { text = "When no Zygor guide is loaded, Tracker Viewer shows a message that opens Zygor's guide picker.", level = 1 },
            }},
            { title = "Zygor native viewer controls", entries = {
                { text = "Added `Hide Zygor's Native Frame` as a Zygor option, so users can visually hide Zygor's full-size viewer.", level = 1 },
                { text = "Native Zygor viewer hiding cloaks and moves the viewer off screen while keeping Zygor's guide engine, active guide state, waypoints, guide picker, and settings available.", level = 1 },
                { text = "Added open-guide switching, current-guide closing, guide picker, Zygor guide menu, and Zygor settings actions for users who keep Zygor's native viewer hidden.", level = 1 },
                { text = "Added macro-friendly `/awp zygor` guide controls for next, previous, skip, guide picker, guide loading by title, menu, settings, open-guide list, guide switching, and guide closing.", level = 1 },
                { text = "Added `/awp zygor reset` to recover a lost or glitched native Zygor viewer. It unhides the viewer and resets Zygor's own window back to its default position. This is intended as a recovery option if the native viewer ever becomes inaccessible.", level = 1 },
                { text = "Added optional local chat-frame step display for the current Zygor step on step change, including step percentage, contextual or selected text colors, and sticky step summaries.", level = 1 },
                { text = "Added `/awp zygor output` to show the current Zygor step in your own chat frame with step percentage, contextual or selected text colors, and sticky step summaries.", level = 1 },
            }},
            { title = "Native minimap button", entries = {
                { text = "Added an AzerothWaypoint minimap button.", level = 1 },
                { text = "Left-click opens the AWP quick menu; right-click opens AWP settings; dragging supports minimap-edge snapping near the minimap and free-floating placement when pulled away.", level = 1 },
                { text = "Minimap button position and visibility can be controlled with `/awp minimap show|hide|toggle|reset|status`.", level = 1 },
                { text = "Added addon compartment support with the same quick menu, tooltip, and settings access so users can still reach the same AWP menu when the minimap button is hidden.", level = 1 },
                { text = "The minimap quick menu includes Tracker Viewer toggle, Zygor native viewer toggle, Zygor guide controls, Open AWP Settings, Open Help, Open Queue, reset position, and hide button actions.", level = 1 },
            }},
            { title = "Flight Map Assist", entries = {
                { text = "Added Flight Map Assist, which can highlight the intended flight path destination when the active AWP route includes a matched taxi leg.", level = 1 },
                { text = "Added an optional AWP taxi list attached to the flight map, with route destination, favorites, recent flights, current-zone flights, search, and reachable destinations grouped by zone.", level = 1 },
                { text = "The taxi list can auto-attach to the side with available screen space, update its side when the flight map is moved, center against the visible map area, and resize based on content.", level = 1 },
                { text = "Taxi list text-size option for adjusting font readability in the list of destinations.", level = 1 },
                { text = "Taxi list rows can take reachable flights, toggle favorites, and pulse the matching map node on hover.", level = 1 },
                { text = "When InFlight is installed and has matching timing data, the AWP taxi list can show exact or estimated flight times without importing or copying InFlight's database.", level = 1 },
                { text = "Zygor / LibRover taxi legs carry exact Blizzard taxi node metadata for precise flight map matching.", level = 1 },
                { text = "Mapzeroth `flightpath` legs now normalize to AWP taxi route legs, allowing strict visible coordinate/name matching where available.", level = 1 },
                { text = "Added opt-in `Auto Take Flight Paths` modes for exact matches or strong matches. This is disabled by default, and holding `Alt` suppresses it for the current flight-map interaction.", level = 1 },
                { text = "Added `/awp flightassist marker on|off|toggle|status`, `/awp flightassist auto disabled|exact|strong|status`, and `/awp flightassist catalog on|off|toggle|reset|status`.", level = 1 },
            }},
            { title = "Queue panel access", entries = {
                { text = "`/awp queue`, `/awp queue list`, and the minimap button's Open Queue action now force the quest-log side panel open for that interaction so the AWP queue tab is visible even when the user's normal world-map quest log panel is hidden.", level = 1 },
                { text = "The forced queue-open path does not change saved user map or quest-log settings. It behaves like an explicit quest-log open only for the requested queue display action.", level = 1 },
            }},
            { title = "Objective tracker diagnostics", entries = {
                { text = "Added objective tracker visibility diagnostics that prefer Kaliel's Tracker when present and fall back to Blizzard's ObjectiveTrackerFrame.", level = 1 },
                { text = "`/awp status` now reports the objective tracker host, hard-hidden state, opacity state, Tracker Viewer state, Zygor native viewer state, local chat-frame step-display state, Flight Map Assist and Taxi List state, and minimap button state.", level = 1 },
                { text = "AWP now warns after login or reload when Tracker Viewer is enabled but the active objective tracker is hard-hidden, or when it appears transparent due to tracker opacity or mouseover behavior.", level = 1 },
            }},
            { title = "Options and help", entries = {
                { text = "Added Zygor options for Enable Tracker Viewer, Hide Zygor's Native Frame, Tracker Viewer Progress Bar, Tracker Viewer Text, Show Step in Chat Frame on Step Change, Chat-Frame Step Text, and Chat-Frame Sticky Summary.", level = 1 },
                { text = "Added General > Routing options for Show Flight Map Route Marker, Auto Take Flight Paths, Show Flight Map Taxi List, Flight Map Taxi List Side, and Flight Map Taxi List Text Size.", level = 1 },
                { text = "Added General > Interface > Show Minimap Button.", level = 1 },
                { text = "Added a bottom-tab Integrations page in AWP options and a matching Help page that explain supported addons, route backends, Blizzard sources, and what AWP uses each for.", level = 1 },
                { text = "Updated option previews and help media for Tracker Viewer, tracker progress bar styles, tracker text colors, and the minimap button.", level = 1 },
                { text = "Reorganized in-game help to give Zygor Integration its own page and added a dedicated Zygor Tracker Viewer page.", level = 1 },
                { text = "Added minimap button documentation to the Options and Customization help page.", level = 1 },
                { text = "Updated command help for `/awp trackerviewer`, `/awp zygorviewer`, `/awp zygor`, and `/awp minimap`.", level = 1 },
                { text = "In-game help page text is now selectable. Drag-select any command or text and press Ctrl+C to copy it.", level = 1 },
            }},
            { title = "Text rendering fixes", entries = {
                { text = "Escaped literal pipe characters in help text so command examples such as `on|off|toggle` display correctly instead of being interpreted as WoW markup.", level = 1 },
                { text = "Escaped literal pipe characters in chat diagnostics while preserving valid WoW color, atlas, texture, and hyperlink escapes.", level = 1 },
                { text = "Tracker Viewer rows now strip Zygor inline color markup before applying AWP tracker colors, preventing stale Zygor styling from leaking into docked step rows.", level = 1 },
            }},
            { title = "General Fixes", entries = {
                { text = "Closing all Zygor guide tabs now invalidates AWP's guide route state so the last guide waypoint is cleared instead of lingering after Zygor has no active guide.", level = 1 },
                { text = "`/awp zygor output` labels the active step with a \"Current step:\" header and uses a clear indent hierarchy, so the active step's objectives don't blend into the sticky block displayed above them.", level = 1 },
                { text = "Throttled the surrogate navigation point chat notice to once every 30 seconds while preserving the existing once-per-waypoint guard.", level = 1 },
                { text = "Removed the duplicate AWP prefix from the surrogate navigation point notice.", level = 1 },
            }},
            { title = "Developer reference material", entries = {
                { text = "Added RestedXP reference documentation and template files for future guide-provider work.", level = 1 },
                { text = "Added Dugi folder for future guide-provider work.", level = 1 },
            }},
        },
    },
    {
        version = "4.0.1b",
        sections = {
            { title = "Native overlay long-distance routing", entries = {
                { text = "Improved surrogate navigation point selection for far-away world overlay targets by projecting through the real world map, trying target/player map lineage candidates, validating round trips, and logging clearer failure reasons.", level = 1 },
                { text = "Avoided replacing the real target with a surrogate when Blizzard's native navigation can already resolve the target map directly.", level = 1 },
                { text = "Cleared unavailable surrogate hosts instead of falling back to an unroutable original target, preventing repeated native-navigation retries and hidden overlay churn on unsupported long-distance routes.", level = 1 },
                { text = "Added a short settle window after setting the native navigation host so transient missing-waypoint or frame-destroyed events do not immediately mark a fresh route probe as failed.", level = 1 },
                { text = "Added a one-time in-game notice when AWP uses an intermediate navigation point because Blizzard may not reliably supertrack the requested target at the current distance.", level = 1 },
            }},
            { title = "Manual route cancellation", entries = {
                { text = "Pending manual routes with planned legs can now present through TomTom before the strict route transaction is fully committed.", level = 1 },
                { text = "Removing TomTom's active waypoint while a strict manual route is still pending now cancels the pending manual queue transaction cleanly instead of treating it like a committed manual authority.", level = 1 },
                { text = "Manual arrival checks now run only for committed manual authority routes, avoiding arrival cleanup against pending transactions.", level = 1 },
            }},
            { title = "Adopted Blizzard waypoint stability", entries = {
                { text = "Blizzard supertrack-clear suppression now applies to every adopted user waypoint publish, not only manual ask-mode clicks, so AWP-adopted waypoints are less likely to be cleared immediately after adoption.", level = 1 },
            }},
        },
    },
    {
        version = "4.0.1a",
        sections = {
            { title = "SilverDragon waypoint adoption taint fix", entries = {
                { text = "Removed the SilverDragon-specific deferred TomTom adoption path. SilverDragon waypoints now adopt synchronously through the same `RouteExternalTomTomWaypoint` path other external sources already use.", level = 1 },
            }},
            { title = "Special travel button combat safety", entries = {
                { text = "Disarm requests that arrive during combat lockdown are now queued onto `PLAYER_REGEN_ENABLED` via a new `pendingSpecialActionClear` flag, mirroring the existing `pendingSpecialAction` re-apply, instead of partially clearing protected attributes mid-combat.", level = 1 },
                { text = "Centralized the out-of-combat secure-button reset into `ParkSecureActionButton` - clear state driver, hide, clear points, reparent to `UIParent`, recenter - so every cleanup site takes the same safe sequence.", level = 1 },
                { text = "`ShowSecureActionVisuals` now defers the whole presentation update during combat lockdown rather than running `HideSpecialActionVisuals` partway through.", level = 1 },
            }},
        },
    },
    {
        version = "4.0.1",
        sections = {
            { title = "HandyNotes integration", entries = {
                { text = "Added HandyNotes - including plugins such as MapNotes and HandyNotes_TheWarWithin - as a recognized transient external waypoint source, adopted from both `C_Map.SetUserWaypoint` and `TomTom:AddWaypoint` calls.", level = 1 },
                { text = "Added a generic HandyNotes icon spec used for adopted HandyNotes waypoints.", level = 1 },
                { text = "MapNotes pin clicks now reverse-map the HandyNotes plugin iterator's icon path back to one of the existing AWP icons (portal, travel, inn, dungeon, delve, profession trainer, vendor, mailbox, banker, auctioneer, barber, transmog, stable master) so the overlay reflects the kind of pin that was clicked.", level = 1 },
                { text = "Snapshotted the open tooltip's first line at right-click time so the \"Set map waypoint\" option in HandyNotes plugins preserves the node label even though `C_Map.SetUserWaypoint` itself accepts no title. Captured text is cleaned of inline icon textures, atlas escapes, and hyperlink wrappers before use.", level = 1 },
                { text = "Plugin OnClick hooks are installed at login and on every subsequent `RegisterPluginDB`, so HandyNotes plugins that load after AWP are still covered.", level = 1 },
                { text = "Per-source icon resolver framework: `RegisterExternalWaypointSource` accepts an optional `resolveIconKey(mapID, x, y)` callback, and `NS.ResolveExternalWaypointIconKey` threads the result through meta, authority record (and persistence), queue items, and presentation snapshot - including both content signatures - so per-call icon overrides cache-bust correctly.", level = 1 },
                { text = "`/awp waytype` now also prints `sourceAddonIconKey=` so the resolved icon hint can be inspected.", level = 1 },
            }},
            { title = "Routing fixes", entries = {
                { text = "Fallback route outcomes are no longer treated as failures even for strict route records, so the fallback completes instead of rolling back the pending manual queue transaction.", level = 1 },
            }},
            { title = "WhoWhere search adoption", entries = {
                { text = "Zygor WhoWhere search results are now adopted as transient manual routes via `RequestManualRoute` instead of only being tagged, so the search result's title flows through to the overlay. A per-adoption serial guards against stale results when the search changes mid-frame.", level = 1 },
            }},
            { title = "Help frame", entries = {
                { text = "Replaced the static page X / N indicator with a clickable dropdown that lists every help page by name. The dropdown closes when the help frame is hidden.", level = 1 },
            }},
        },
    },
    {
        version = "4.0.0d",
        sections = {
            { title = "TomTom combat visibility", entries = {
                { text = "Replaced the secure-parent host approach with a root-frame alpha cloak so TomTom's full crazy arrow stack (textures and text) hides together without calling protected hide/show paths.", level = 1 },
                { text = "Disabled mouse input on the cloaked arrow, skipping the call when the arrow is protected during combat lockdown to avoid blocked-action errors.", level = 1 },
                { text = "Restored the arrow through TomTom's own `ShowHideCrazyArrow()` path after combat ends.", level = 1 },
                { text = "Kept `[combat] hide; show` secure visibility scoped to the special travel button only.", level = 1 },
                { text = "Fixed Hide During Combat's disabled state so it no longer creates or briefly reparents TomTom's arrow into the secure combat visibility host.", level = 1 },
            }},
            { title = "TomTom arrow-skin protected-call safety", entries = {
                { text = "Only resizes TomTom's root arrow frame when dimensions actually change.", level = 1 },
                { text = "Skips root-size writes only when in combat lockdown AND the arrow frame is protected, so out-of-combat resizes always proceed.", level = 1 },
            }},
            { title = "External waypoint adoption", entries = {
                { text = "Deferred SilverDragon TomTom waypoint adoption to the next frame.", level = 1 },
                { text = "Deduped matching Blizzard user-waypoint publishes from the same secure click.", level = 1 },
            }},
        },
    },
    {
        version = "4.0.0c",
        sections = {
            { title = "Routing fixes", entries = {
                { text = "Restricted third-party POIButton supertrack calls to the addon adoption controls instead of treating them as native Blizzard POI clicks.", level = 1 },
                { text = "Fixed task-zone and world-quest-style supertracked POIs being cleared as missing when they are valid map tasks but not normal quest-log entries.", level = 1 },
                { text = "Added task-zone and world-quest-style cleanup for explicit completion, full progress, and expiry signals.", level = 1 },
                { text = "Fixed RareScanner popup waypoint clicks being adopted more than once from a single click by treating the mouse-down publish as a transient duplicate while preserving normal clear and removal behavior.", level = 1 },
                { text = "Fixed registered external waypoint sources that publish both TomTom and Blizzard user-waypoint signals in one action, such as SilverDragon, from creating duplicate AWP route adoptions.", level = 1 },
                { text = "Preserved named TomTom waypoint titles when a matching nameless Blizzard user-waypoint signal follows in the same external-addon publish burst.", level = 1 },
                { text = "Fixed arrival auto-clear for transient external TomTom waypoint routes by validating active transient queues as well as persistent manual queues.", level = 1 },
            }},
        },
    },
    {
        version = "4.0.0b",
        sections = {
            { title = "Routing and combat visibility", entries = {
                { text = "Added Hide During Combat with options for Disabled, TomTom + Travel Button, World Overlay, and Both.", level = 1 },
                { text = "TomTom combat hiding uses a secure visibility wrapper so the TomTom arrow and special travel button can be hidden during combat without protected-frame errors.", level = 1 },
                { text = "Added player control lost/gained route refresh handling so taxi and flightpath start/end events replan the active route and recompute the TomTom carrier.", level = 1 },
                { text = "Added separate Quick-Start Popup and What's New Popup settings, each with account-wide, per-character, and disabled modes. Quick-start defaults to per-character; What's New defaults to account-wide.", level = 1 },
            }},
            { title = "Compatibility fixes", entries = {
                { text = "Added a WorldQuestTab click fallback for bonus objectives and other non-world-quest entries that have valid quest coordinates but do not emit Blizzard waypoint or supertrack signals.", level = 1 },
                { text = "Added transparency, transparent, alpha, and visibility tags to the opacity options so searching transparency will find the opacity controls.", level = 1 },
                { text = "Prevented transient external waypoint sources such as RareScanner and SilverDragon from opening the manual queue placement prompt.", level = 1 },
                { text = "Renamed addon waypoint adoption list internals and wording to Allowlist/Blocklist.", level = 1 },
                { text = "Fixed update detection for lettered hotfix versions such as 4.0.0a to 4.0.0b.", level = 1 },
            }},
        },
    },
    {
        version = "4.0.0a",
        sections = {
            { title = "Compatibility fixes", entries = {
                { text = "Fixed the native world overlay failing to load when Zygor Guides Viewer is disabled or unavailable.", level = 1 },
                { text = "Removed an accidental hard dependency on Zygor guide-resolver helpers from the shared world overlay presentation layer.", level = 1 },
                { text = "Added safe fallback helpers for overlay text normalization, coordinate subtext, guide-goal visibility, quest IDs, goal coordinates, and goal actions.", level = 1 },
                { text = "Guarded Zygor canonical-goal handling so APR, WoWPro, manual routing, queues, and non-Zygor routing backends can initialize normally without Zygor.", level = 1 },
            }},
        },
    },
}
