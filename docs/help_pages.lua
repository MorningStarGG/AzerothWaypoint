-- ============================================================
-- Help pages and links
-- ============================================================
--
-- Defines the help pages, linked sections, screenshots and integration
-- descriptions shown in game.

local NS = _G.AzerothWaypointNS
local C = NS.Constants

local MEDIA_ROOT = "Interface\\AddOns\\AzerothWaypoint\\media\\"
local MEDIA = "Interface\\AddOns\\AzerothWaypoint\\media\\help\\"

local function JoinLines(lines)
    return table.concat(lines, "\n")
end

local function Capture(name, width, height, caption)
    return {
        type = "image",
        align = "CENTER",
        texture = MEDIA .. name,
        width = width,
        height = height,
        placeholder = caption,
        caption = caption
    }
end

local function PlaqueSample(plaqueType, caption, height)
    return { width = 236, height = height or 64, frameless = true, plaqueType = plaqueType, caption = caption }
end

-- Content helpers only: all blocks use the existing Help renderer schema.
local function Heading(text, id) return { type = "heading", text = text, id = id } end
local function Link(text, pageID, sectionID)
    return "[[help:" .. pageID .. (sectionID and "#" .. sectionID or "") .. "|" .. text .. "]]"
end
local function Text(lines) return { type = "text", text = JoinLines(lines) } end
local function Note(text) return { type = "note", text = text } end
local function Row(items, gap) return { type = "image_row", items = items, gap = gap or 12 } end

-- ============================================================
-- Integration help content
-- ============================================================

local function BuildIntegrationHelpBlocks()
    local blocks = {
        Heading("Only TomTom is required"),
        Text({
            "Install other addons only for the features you want. Guides provide destinations, travel planners find routes, tracker addons host Guide Viewers, and AWP can match the look of supported UI addons.",
            "",
            "Open /awp options > Integrations to see which integrations are loaded and copy addon links where available.",
        }),
        Heading("Supported integrations"),
    }

    local entries, order = {}, {}
    if type(NS.GetIntegrationInfo) == "function" then
        entries, order = NS.GetIntegrationInfo()
    end
    if type(entries) ~= "table" or #entries == 0 then
        blocks[#blocks + 1] = {
            type = "note",
            text = "No integration data is available.",
        }
        return blocks
    end

    local byCategory = {}
    for _, entry in ipairs(entries) do
        local category = entry.category or "Other"
        byCategory[category] = byCategory[category] or {}
        byCategory[category][#byCategory[category] + 1] = entry
    end

    for _, category in ipairs(order or {}) do
        local group = byCategory[category]
        if group and #group > 0 then
            blocks[#blocks + 1] = {
                type = "heading",
                text = category,
            }

            local lines = {}
            for _, entry in ipairs(group) do
                lines[#lines + 1] = tostring(entry.name or "Integration")
                lines[#lines + 1] = "- " .. tostring(entry.summary or "")
                for _, bullet in ipairs(entry.bullets or {}) do
                    lines[#lines + 1] = "  - " .. tostring(bullet)
                end
                lines[#lines + 1] = ""
            end

            blocks[#blocks + 1] = {
                type = "text",
                text = JoinLines(lines),
            }
        end
    end

    return blocks
end

-- ============================================================
-- Help page definitions
-- ============================================================

-- Existing page IDs are retained for NS.ShowHelp callers. New pages split long topics.
NS.HELP_PAGES = {
    {
        id = "overview",
        title = "Overview",
        hideTitle = true,
        blocks = {
            { type = "image", texture = MEDIA_ROOT .. "banner.png", align = "CENTER", width = 768, height = 256, frameless = true, spacingAfter = 14 },
            Heading("One arrow. More ways to explore Azeroth."),
            Text({
                "AzerothWaypoint (AWP) brings quests, guides, map pins and personal waypoints together in one navigation experience. TomTom provides the arrow, AWP plans the route and adds in-world guidance and waypoint management.",
                "TomTom is the only required addon. Optional integrations add smarter travel routes, guide controls and more ways to customize your UI.",
            }),
            Heading("Get started"),
            Text({
                "1. Install and enable TomTom and AzerothWaypoint.",
                "2. Open /awp options and choose General > Routing Backend. AWP can use an available travel planner or TomTom Direct.",
                "3. Set a map waypoint, select a quest or load a supported guide. Follow the arrow and world markers.",
                "4. To show a guide in your objective tracker, open its settings page > Tracker Viewer and enable the Viewer.",
                "5. Open /awp queue (or use the world map tab) to manage saved destinations.",
            }),
            Capture("MainShot", 630, 350, "Example of the TomTom arrow and in-world destination guidance."),
            Heading("Make it your own"),
            Text({
                "- Travel smarter: use flights, portals, teleports and supported walking paths.",
                "- Find nearby services: open Search Nearby from the minimap menu to locate vendors, trainers and more.",
                "- Keep multiple destinations: save, import and switch between waypoint queues.",
                "- Follow your guides: show multiple Guide Viewers, with one guide directing navigation at a time.",
                "- Customize navigation: choose arrow skins, world markers, plaques and optional UI appearance matching.",
                "- Save your setup: use Profiles to share settings or keep a different setup for each character.",
            }),
            Note(
            "Use the minimap button for quick access. /awp help opens this guide, /awp status shows your current setup, and /awp changelog shows release notes."),
        },
    },
    {
        id = "routing_guides",
        title = "Navigation and Routing",
        intro = "Choose how AWP gets you to a destination.",
        blocks = {
            Heading("How navigation works"),
            Text({
                "A destination can come from a map pin, quest, guide, imported waypoint list or another addon. The Routing Backend decides how to get there, and TomTom and the world overlay show the next part of the route.",
                "",
                "For example, you can follow a RestedXP guide using Zygor travel routing, or follow a personal waypoint using Mapzeroth. Your guide and travel planner do not have to be the same addon.",
                "Selecting another destination changes the active route without necessarily deleting your saved queues.",
            }),
            Heading("Choose a route planner"),
            Text({
                "Open General > Routing Backend. Only available planners can be used.",
                "",
                "- TomTom Direct: points straight to the destination, without travel planning.",
                "- Zygor: uses Zygor travel data (LibRover).",
                "- Farstrider: uses FarstriderLib and its travel data.",
                "- Mapzeroth: plans travel and supported walking routes.",
                "- Dugi: uses Dugi's Taxi System preferences.",
                "- Polestar (Forever): uses its travel settings and terrain data.",
                "- QuestieRouter (Forever): uses its travel settings.",
                "",
                "Choose a travel-aware planner if you want help finding flights, portals, transports or teleport actions. The available travel methods depend on the planner and your character.",
                "If you set a waypoint inside a dungeon or raid, supported routes can guide you to a known entrance first and keep your original waypoint inside. Farstrider's data can fill in a missing entrance.",
            }),
            Heading("If a planner cannot find a route"),
            Text({
                "AWP tries other available planners before falling back to TomTom Direct. Your preferred planner stays selected, and AWP can return to it when a route becomes available. Current guidance stays visible while a replacement is calculated. AWP notifies of a fallback or return to your preferred planner.",
                "",
                "Intentional direct or walking-only settings are respected. Some planners can update routes during combat, others must wait. Loading or active travel can also delay updates.",
            }),
            Heading("Walking routes"),
            Capture("WalkingRoute", 630, 437, "Example of a ground route with several walking points."),
            Text({
                "Mapzeroth can follow supported roads and city streets. Polestar and QuestieRouter can provide terrain paths on Forever with the appropriate navigation packs. Configure walking preferences in the planner itself.",
                "",
                "The arrow points to the next walking point, not necessarily the final destination. Named walking instructions can include the destination and quest purpose. AWP can advance past ordinary corners and recalculate a missed approach, required crossings and stops are kept.",
                "Missing map or terrain coverage keeps ordinary guidance. A route may not know the exact floor or final approach.",
            }),
            Note(
            "Follow ground paths while flying (General) is off by default. When off, a supported planner may bypass ordinary ground points during self-flight if it confirms a valid shortcut. Required stops remain."),
        },
    },
    {
        id = "quest_navigation",
        title = "Quests and Map Waypoints",
        intro = "Route to quests, points of interest and destinations from other addons.",
        blocks = {
            Heading("Set a destination"),
            Capture("BlizzardPOI", 360, 341, "Example of quest and point-of-interest pins on the world map."),
            Text({
                "Set a supported map waypoint or select a quest destination to use AWP navigation. Supported sources include user waypoints, quest pins, tracked and supertracked quests, area POIs, rare/vignette pins, flight masters, gossip destinations, dig sites and housing plots where available.",
                "",
                "Quest destinations can show quest icons, objectives and progress when the necessary information is available.",
            }),
            Heading("Choose how quests are followed"),
            Text({
                "Under General:",
                "- Auto-Route Tracked Quests: start routing newly tracked quests. Active guide steps are protected.",
                "- Auto-Clear Untracked Quests: remove matching quest routes and queue entries when you untrack a quest.",
                "- Auto-Clear Supertracked Quests on Arrival: stop the matching route when you reach its destination.",
                "",
                "On Forever, DaylightUI's quest menu can offer Route with AzerothWaypoint without changing your watched quests.",
            }),
            Heading("Extra quest information"),
            Text({
                "On Forever, the optional separate QuestieDB download can provide NPC, object and item information for identified quests, even without Questie running. On both clients, loaded BtWQuests packs can fill missing quest names and known acceptance or NPC/object details. AWP does not automatically load extra packs. Missing or uncertain information falls back to normal client guidance and preserves explicitly selected coordinates.",
            }),
            Heading("Waypoints from other addons"),
            Capture("SilverDragon", 350, 323, "Example of a rare-spawn destination from SilverDragon."),
            Text({
                "HandyNotes, SilverDragon and RareScanner can create temporary routes without deleting your saved manual queues. WorldQuestTab can also provide world quest destinations.",
                "",
                "For other addons, use General > Addon Waypoint Adoption. Review Detected Addon Callers and use the allowlist or blocklist to decide which unknown addons may create AWP routes.",
            }),
            Heading("Corpse navigation"),
            Text({
                "TomTom corpse waypoints can temporarily guide you to your body. Your saved queues remain available. If you clear the corpse waypoint while dead, the arrow clears, the interrupted route can resume on resurrection. You can also choose a new manual destination while ghosted.",
            }),
        },
    },
    {
        id = "search_nearby",
        title = "Search Nearby",
        intro = "Find nearby services and let AWP guide you there.",
        blocks = {
            Heading("Find a vendor, trainer or other service", "setup"),
            Text({
                "1. Left-click the AWP minimap button.",
                "2. Open Search Nearby and choose a service. Vendor and trainer categories have submenus when available.",
                "3. Follow the TomTom arrow and world markers to the result using your selected Routing Backend.",
                "",
                "Available services depend on your installed addons and current client. Common examples include repair merchants, auctioneers, bankers, mailboxes, innkeepers, profession trainers and workshops. Specific vendor, class trainer and weapon master categories may also be available.",
            }),
            Capture("MinimapButton", 280, 250, "The minimap menu with Search Nearby open."),
            Heading("Which addons provide search results?", "providers"),
            Text({
                "AWP searches available service data from Zygor, Dugi and Polestar (Forever). You do not need to make the guide active or enable its Tracker Viewer.",
                "",
                "General > Guide Viewer Order also determines which search provider is checked first. AWP uses the first matching result from the available providers in that order. Your selected travel planner then routes to that destination, even if another addon supplied the result.",
                "",
                "Specific searches stay specific: a request for an alchemy trainer or a blacksmithing workshop does not fall back to an unrelated service. Class searches skip providers that only support your own class when you request another class. Each guide's own Find Nearest menu still searches that guide alone.",
            }),
            Heading("Search with a command"),
            Text({
                "/awp search help - list available searches.",
                "/awp search vendor - find a supported vendor.",
                "/awp search repair - find repairs.",
                "/awp search mailbox - find a mailbox.",
                "/awp search trainer alchemy - find an alchemy trainer.",
                "/awp search trainer mage - find a mage trainer.",
                "/awp search weapon master swords - find sword training.",
                "/awp search workshop blacksmithing - find a blacksmithing workshop.",
            }),
            Note(
            "If a service is missing, check that Zygor, Dugi or Polestar is installed and ready. Not every provider supports every search. TomTom alone does not provide service-location data."),
        },
    },
    {
        id = "queues",
        title = "Waypoint Queues",
        intro = "Save destinations, build itineraries and switch between routes.",
        blocks = {
            Heading("Open Waypoint Queues"),
            Text({
                "Use the world map side tab, the minimap menu or /awp queue. The active queue is the one currently directing navigation. Other queues can remain saved for later.",
                "",
                "- Manual queues: personal waypoints and multi-stop routes.",
                "- Imported queues: waypoint lists imported from /ttpaste, in their original order.",
                "- Temporary routes: short-lived destinations such as rare spawns or guard directions.",
                "- Guide queues: automatically updated, read-only destinations from loaded guides.",
            }),
            Heading("What happens when I set another waypoint?"),
            Capture("ManualQueueAsk", 590, 236, "Ask mode lets you choose how to add a destination."),
            Text({
                "General > Manual Click Queue Behavior applies to supported map clicks, quest shortcuts and single TomTom /way commands.",
                "",
                "- Create New Queue: save the destination in a new queue.",
                "- Replace Active: replace the current queue. With Preserve Imported and Multi-Stop Queues enabled (default), imported and multi-stop queues stay saved at their current stop.",
                "- Append: add the destination to the current queue.",
                "- Ask: choose the behavior each time.",
            }),
            Note(
            "Use Replace Active for everyday single destinations, Append for an itinerary, or Ask if you frequently switch between the two."),
            Heading("Manage or share a queue"),
            Text({
                "Open queue details to review destinations and travel steps, reorder or remove manual destinations, or show the final destination on the map. Select rows with checkboxes to delete several at once. Guide queues cannot be edited or deleted like manual queues.",
                "",
                "Activate resumes a saved route. Deactivate stops the route and keeps it saved. Export the open queue or all saved manual waypoints as copyable TomTom commands.",
            }),
            Row({
                Capture("QueueUIMain", 224, 343, "Queue list"),
                Capture("QueueUIDetails", 224, 343, "Queue details"),
            }),
            Heading("When a waypoint is cleared"),
            Text({
                "Enable Auto-Clear Manual Waypoints on Arrival and adjust Manual Waypoint Clear Distance in General to clear destinations when you reach them. Removing a TomTom waypoint or using its Remove all waypoints control can cancel the active manual route. When a guide advances while a manual route is active, clearing that manual route will return you to the guide's current step.",
            }),
            Note("If /ttpaste does not form a queue, open /awp queue and /awp status to check what AWP detected."),
        },
    },
    {
        id = "arrow_guide",
        title = "TomTom Arrow and Travel Actions",
        intro = "Choose your arrow style and use travel actions when a route calls for them.",
        blocks = {
            Heading("Arrow appearance"),
            Text({
                "Open TomTom Arrow in settings. Enable Use Custom Arrow Skin, choose Arrow Skin and adjust TomTom Arrow Scale. Turn custom styling off to use TomTom's normal Crazy Arrow. AWP Modern is the default custom skin.",
            }),
            Row({
                Capture("AWP", 112, 156, "AWP"),
                Capture("AWPBomber", 112, 155, "Bomber"),
                Capture("AWPModern", 112, 180, "Modern"),
                Capture("Alliance", 112, 176, "Alliance"),
                Capture("Horde", 112, 176, "Horde"),
            }, 10),
            Text({
                "With Zygor installed and enabled, Starlight and Stealth are also available.",
            }),
            Row({
                Capture("Starlight", 270, 149, "Zygor Starlight"),
                Capture("Stealth", 270, 149, "Zygor Stealth"),
            }, 12),
            Heading("Special travel button"),
            Capture("TravelButton", 297, 102, "Example of a travel action replacing the arrow."),
            Text({
                "Some routes need a click to use an item, spell, toy or other travel action. When the planner provides a usable action, AWP shows a special travel button instead of the arrow. Adjust Special Travel Button Scale to change its size.",
                "",
                "This is separate from " ..
                Link("Guide Actions", "guide_actions", "action_buttons") ..
                ", which help you perform the current guide's instructions. The travel button hides during combat so an outdated travel action cannot be used.",
            }),
            Note("General > Hide During Combat controls which other navigation displays are temporarily hidden."),
        },
    },
    {
        id = "flight_assist",
        title = "Flight Map Assist",
        intro = "Find the right flight on Retail and WoW Forever.",
        blocks = {
            Heading("Follow a planned flight"),
            Capture("FlightHighlight", 195, 289, "Example of a highlighted flight destination."),
            Text({
                "When your route includes a flight path, Show Flight Map Route Marker highlights the intended landing point. The marker is only a visual guide, it does not create another route.",
                "",
                "Auto Take Flight Paths is off by default.",
                "- Disabled lets you select every flight yourself.",
                "- Exact requires a confirmed match to the destination's flight node.",
                "- Strong also accepts a reliable match by position and name.",
                "",
                "Both automatic modes wait until the route is ready for the flight and AWP confirms the departure flight master. If AWP highlights a destination without confirming the departure, select the flight yourself.",
                "",
                "Hold Alt while opening the flight map to skip automatic selection for that interaction.",
            }),
            Note("A RestedXP guide-only flight suggestion is labelled separately and always requires a manual click."),
            Heading("Use the Taxi List"),
            Capture("TaxiList", 350, 282, "Recent and reachable flights with fares and flight times."),
            Text({
                "Enable Show Flight Map Taxi List under General > Routing. Browse the route destination, favorites, recent flights, current-zone flights and reachable destinations grouped by zone. Hover a row to highlight the matching map node, select a reachable flight to take it.",
                "",
                "Reachable flights show fares. InFlight can supply times on both clients. On Forever, AWP can also use times from DaylightUI, Farstrider or Ellesmere UI. A ~ indicates an estimate.",
                "Use Flight Map Taxi List Side to choose Left, Right or Auto (available screen space), and Flight Map Taxi List Text Size to improve readability.",
            }),
        },
    },
    {
        id = "guide_providers",
        title = "Guide Addons",
        intro = "Use supported guides independently of your selected travel planner.",
        blocks = {
            Heading("Choose a guide"),
            Text({
                "Supported guide addons on Retail and Forever: Zygor, Dugi, RestedXP, Azeroth Pilot Reloaded (APR) and WoWPro. Polestar and QuestieRouter are supported on Forever. Install only the guides you want to use.",
                "",
                "Load a guide normally, or open its picker from AWP's minimap menu or Tracker Viewer. Each guide has its own settings page when loaded. Multiple guides can be open, but only one directs navigation at a time. Use Make Active or the guide's supported selection controls to switch.",
            }),
            Heading("Guide navigation and progress"),
            Text({
                "AWP follows each guide addon's own navigation and completion rules. Step controls may behave differently depending on the guide.",
                "",
                "Use the guide title or dropdown menu in the " ..
                Link("Tracker Viewer", "tracker_viewer", "header_controls") ..
                " to switch, open or close guides where supported. Previewing steps or having a guide update in the background does not automatically make it active.",
            }),
            Heading("Zygor"),
            Text({
                "Previous Step returns to an earlier step. Next, Skip This Step and the step checkbox advance to the next valid step.",
                "",
                "Zygor provides optional travel planning and nearby service searches. AWP also offers additional display options for Zygor's original guide window. See " ..
                Link("Zygor Native Viewer", "zygor_integration") .. " for details.",
            }),
            Heading("Dugi"),
            Text({
                "Previous Step returns to an earlier step. Next and the step checkbox advance to the next valid step.",
                "",
                "Dugi supports up to six numbered guide slots, including separate copies of the same guide. Closing an inactive slot keeps the current guide open. If all slots are occupied, choose which one to close before opening another.",
                "",
                "Dugi provides optional travel planning using its own Taxi System preferences, along with nearby service searches.",
            }),
            Heading("RestedXP"),
            Text({
                "Back can return to an earlier step to recover a missing quest acceptance or open Go to Step when the appropriate step is unclear. RestedXP's own pause setting is respected.",
                "",
                "Switch between up to six recently used unique guides. Removing a guide from this list does not delete its progress. Open New Guide opens RestedXP's own guide chooser.",
            }),
            Heading("Azeroth Pilot Reloaded (APR)"),
            Text({
                "Next and the step checkbox skip the current step. Back uses APR's undo feature.",
                "",
                "Open New Guide opens APR's own route browser, where you can choose another route.",
            }),
            Heading("WoWPro"),
            Text({
                "Back can reopen an earlier step to recover a missing quest acceptance or let you choose an earlier step. Skipping a step that affects other steps requires confirmation.",
                "",
                "Switch between up to six recently used unique guides without losing their progress. Open New Guide opens WoWPro's own guide selector, while Current Guide Steps lets you review the steps in the loaded guide.",
            }),
            Heading("Polestar (Forever)"),
            Text({
                "Back and Next preview guide steps. The step checkbox skips the entire step, while individual goal checkboxes follow Polestar's own completion rules.",
                "",
                "When Polestar asks about an escort or group quest, choose whether to attempt or skip it directly from the Viewer. Step explanations, escort notes, warnings about difficult encounters and the optional left-out quest summary are also available.",
                "",
                "When a guide requires a higher level to continue, the Level with ... meanwhile suggestion opens the appropriate leveling guide while keeping the original guide open.",
                "",
                "Polestar provides optional travel planning, terrain-aware walking and nearby service searches. Configure Plan travel routes, Class teleports, Walk real paths and walking style in Polestar's own settings.",
            }),
            Heading("QuestieRouter (Forever)"),
            Text({
                "Unlike traditional step-by-step guides, QuestieRouter dynamically organizes quests into tasks. Follow its automatic task order or choose which eligible task to work on.",
                "",
                "- Choose Task: select an eligible task to follow.",
                "- Make This Task Active: select a task directly from its Viewer menu.",
                "- Return to Automatic Order: let QuestieRouter resume choosing tasks for you.",
                "- Task Actions: open QuestieRouter's own menu to skip quests.",
            }),
            Capture("QuestieRouterChooseTask", 240, 305, "Choose Task shows which tasks are eligible."),
            Text({
                "The Tracker Viewer displays quest descriptions, objectives and progress. Visible Tasks controls how many current and upcoming tasks appear, from one to fourteen (one by default). Future tasks can be previewed but cannot be selected until they become eligible.",
                "",
                "The optional zone banner displays guide artwork and quest progress and is disabled by default. Progress counts completed quests rather than guide steps.",
                "",
                "QuestieRouter also provides optional travel planning and terrain-aware walking with the appropriate navigation packs. Travel and walking preferences are configured in QuestieRouter itself.",
            }),
        },
    },
    {
        id = "tracker_viewer",
        title = "Tracker Viewer",
        intro = "Show your guides directly in your objective tracker.",
        blocks = {
            Heading("Set up a Viewer"),
            Text({
                "1. Open /awp options and choose your installed guide > Tracker Viewer.",
                "2. Enable Tracker Viewer. Repeat for each guide you want to see.",
                "3. Load a guide and make sure your objective tracker is visible.",
                "4. Use General > Guide Viewer Order to arrange your Viewers. The order is saved with your profile and also sets " ..
                Link("Search Nearby provider priority", "search_nearby", "providers") .. ".",
                "",
                "You can display multiple guides at once. The green active indicator identifies the guide currently directing navigation when multiple Viewers are enabled.",
            }),
            Capture("GuideViewerOrder", 320, 237, "Drag guide addons to change their order."),
            Heading("Supported trackers", "supported_trackers"),
            Text({
                "AWP supports several objective trackers for displaying Guide Viewers. Dedicated tracker integrations are recommended to avoid the limitations of experimental Blizzard docking.",
                "",
                "Dedicated tracker integrations:",
                "- Kaliel's Tracker (Retail and Forever)",
                "- GW2 UI Tracker (Retail and Forever)",
                "- Ellesmere UI Quest Tracker (Forever, with custom tracker enabled)",
                "- DaylightUI Quests (Forever)",
                "- Questie Tracker (Forever)",
                "",
                "AWP automatically prefers Kaliel's Tracker when available.",
                "",
                "Experimental tracker integrations:",
                "- Blizzard Objective Tracker (Retail and Forever)",
                "- Ellesmere UI Quest Tracker (Retail, or Forever with custom tracker disabled)",
                "",
                "In shared scrolling trackers, Guide Viewers appear above quests. Scroll back up to return to your guides. With Questie, enable Always Show Tracker to keep Viewers visible when no quests are tracked.",
            }),
            Note(
            "Experimental Blizzard docking can cause blocked actions or other UI errors. This also applies when UI addons such as ElvUI style Blizzard's tracker rather than replace it. For the best experience, use a tracker with dedicated docking support. Show Native Docking Warning Popup controls the reminder."),
            Heading("Use the header controls", "header_controls"),
            Text({
                "- Guide title or guide dropdown: switch or open guides and access guide actions.",
                "- Back / Next: navigate where supported by the guide. QuestieRouter instead provides task selection and automatic ordering.",
                "- Progress bar: view progress, hover for details.",
                "- Settings button: open the guide's menu or settings.",
                "- Collapse: hide this Viewer's rows without disabling the guide.",
                "",
                "Long notes may be grouped under a hoverable row. Click a confirmation instruction when the guide asks you to proceed. Right-click a quest row and choose Open Quest Details to view a quest in your log without advancing the guide or changing tracking.",
            }),
            Capture("QuestDetailsMenu", 280, 206, "Open Quest Details in a Polestar goal menu."),
            Heading("Customize each Viewer", "customize_viewer"),
            Text({
                "Open the guide's AWP settings > Tracker Viewer to customize its progress bar, text and header independently. Hide Guide Addon Name removes the addon name beside the controls. Hide Guide Title removes the current guide's title. Both names remain in the progress and guide-menu tooltips. Compact Active Indicator uses a green dot instead of the Active label. Narrow headers adapt to available space.",
            }),
            Row({
                Capture("TrackerSquareBorder", 300, 25, "Square"),
                Capture("TrackerRoundedBorder", 300, 24, "Rounded"),
            }, 12),
            Capture("TrackerNoProgress", 300, 24, "None (no progress bar)"),
            Heading("Guide text colors", "text_colors"),
            Text({
                "Tracker Viewer Text controls how this guide's instructions are colored:",
                "- Auto: use consistent colors across guides for NPC headings, training and learning, warnings, completed objectives and skipped work. UI text-color settings do not override Auto.",
                "- UI colors: use the text colors supplied by your selected appearance style.",
                "- Fixed or Custom color: use a chosen color instead of contextual colors.",
            }),
            Row({
                Capture("TrackerAutoColor", 320, 122, "Auto: colors follow guide context."),
                Capture("TrackerWhiteColor", 320, 122, "Example: fixed white text."),
            }, 12),
            Heading("Guide text sizes", "text_sizes"),
            Text({
                "Open the guide's AWP settings > Tracker Viewer and enable Use custom Viewer text sizes to adjust these four sizes independently:",
                "- Heading: guide titles and headings.",
                "- Goal: main instructions and objectives.",
                "- Notes / context: supporting information and tips.",
                "- Progress: progress text.",
                "",
                "Leave this option off to keep the existing tracker or UI sizes. Custom sizes keep the selected font, outline and shadow, and guide rows adjust to fit the text. Each guide's sizes are included when importing or exporting its guide settings.",
            }),
            Text({
                "When Kaliel's Tracker is active, you can optionally match its header texture, background color, font, title/icon color and button color.",
            }),
            Note(
            "Tracker Viewer and Hide Native Guide Frame are separate settings. You can show both the AWP Viewer and the original guide window."),
        },
    },
    {
        id = "guide_actions",
        title = "Guide Actions and Chat",
        intro = "Keep useful guide actions nearby and see instructions in your own chat.",
        blocks = {
            Heading("Guide action buttons", "action_buttons"),
            Row({
                Capture("GuideActionsPanel", 237, 132, "Movable action panel"),
                Capture("GuideActionsTracker", 260, 178, "Inline buttons beside Zygor objectives"),
            }),
            Text({
                "Open your guide > Guide Actions.",
                "- Enable Guide Action Panel: show a movable panel, drag its title bar to position it. Each guide remembers its own position.",
                "- Show Actions Beside Steps: show supported item, spell or target buttons beside matching Viewer instructions outside combat.",
                "- Grouped Actions Position: place step-wide buttons above or below objectives where supported (Below is the default).",
                "- Action filters: choose which categories appear in AWP's panel and inline buttons. Inventory Cleanup is off by default.",
                "",
                "Hover an action to see its item or spell tooltip and guide context. Enabled tooltip addons can supply their usual appearance and comparisons.",
            }),
            Heading("Combat and native controls"),
            Text({
                "Prepared standard actions can remain usable during combat. If a guide changes, a pending indicator identifies the update, the replacement takes effect after combat. Native helpers and inline actions retain their normal combat restrictions.",
                "",
                "Hide Native Action Controls is independent of both AWP action displays and filters. If you hide the native controls and turn both AWP displays off, you may have no visible action buttons. Hiding the entire original guide frame is a separate setting. APR, WoWPro and QuestieRouter check embedded action coverage before hiding the whole frame unless native controls are explicitly hidden.",
            }),
            Note(
            "Polestar's optional bag-space helper can be shown through Helpers when enabled in Polestar. Spare bags are equipped first, junk deletion retains its two-click confirmation. AWP does not automatically enable or execute this helper."),
            Heading("Chat Output", "chat_output"),
            Text({
                "Open your guide > Chat Output to show instructions in your own chat when the step changes. Nothing is sent to other players. Chat Step Text chooses contextual or fixed colors. Chat Sticky Summary chooses whether to show no summary, counts only, or counts with titles. Polestar counts along-the-way goals.",
                "",
                "Use /awp <provider> output to show the current step on demand. Add full to include expanded tips and sticky instructions, or sticky to show only sticky instructions, where supported.",
            }),
            Capture("ChatCountTitles", 500, 214, "Example of local guide instructions with a sticky summary."),
        },
    },
    {
        id = "zygor_integration",
        title = "Zygor Native Viewer",
        intro = "Optional display controls specific to Zygor's own guide window.",
        blocks = {
            Heading("Compact the original window"),
            Row({
                Capture("Normal", 220, 80, "Normal"),
                Capture("MinimalMode", 220, 80, "Compact"),
                Capture("MinimalModeHideBGColors", 220, 80, "Compact without backgrounds or colors"),
            }, 12),
            Text({
                "Open the Zygor settings page in AWP.",
                "- Show Only Guide Steps Until Mouseover: keep the instructions visible and reveal the rest of the window on hover.",
                "- Hide Step Backgrounds Until Mouseover: optionally hide row backgrounds or both backgrounds and line colors while compacted.",
                "- Hide Zygor's Native Frame: hide the original window without stopping guide progress or navigation.",
                "",
                "Use the AWP minimap menu, /awp zygor native show or the " ..
                Link("Tracker Viewer controls", "tracker_viewer", "header_controls") .. " to access Zygor again.",
            }),
            Note("For shared " .. Link("Viewer", "tracker_viewer", "customize_viewer") .. ", "
                .. Link("Guide Actions", "guide_actions", "action_buttons") .. " and "
                .. Link("chat settings", "guide_actions", "chat_output")
                .. ", see the corresponding Help pages. Use /awp zygor compact on|off|toggle|status."),
        },
    },
    {
        id = "overlay_overview",
        title = "World Overlay",
        intro = "See the active destination directly in the game world.",
        blocks = {
            Row({
                Capture("Overlay", 300, 300, "World marker"),
                Capture("OverlayFade", 300, 300, "Fade on hover"),
            }, 12),
            Heading("Three ways to find your destination"),
            Text({
                "- Waypoint: the long-range marker in the game world.",
                "- Pinpoint: the close-range marker and optional information plaque.",
                "- Navigator: points toward the destination when it is outside your view.",
                "",
                "Enable 3D World Overlay in World Overlay settings. Fade on Hover reduces the overlay's visibility while your mouse is over it. You can use TomTom alone if you prefer.",
            }),
            Heading("Context Display"),
            Row({
                Capture("FullContext", 220, 113, "Diamond + Icon"),
                Capture("IconOnly", 220, 113, "Icon Only"),
                Capture("ContextHidden", 220, 113, "Hidden"),
            }, 12),
            Text({
                "Choose whether to show a backing diamond and destination icon, just the icon, or neither. Icons and colors can reflect quests, travel steps, services and other destination types.",
            }),
            Note(
            "Auto colors follow available destination context. Choose a preset or Custom to keep a consistent color across destinations."),
        },
    },
    {
        id = "overlay_waypoint_navigator",
        title = "Waypoint and Navigator",
        intro = "Adjust long-distance guidance and off-screen direction.",
        blocks = {
            Row({
                Capture("Waypoint", 300, 303, "Waypoint"),
                Capture("Navigator", 330, 215, "Navigator"),
            }, 12),
            Heading("Waypoint"),
            Text({
                "Use the Waypoint section to enable or disable the long-range marker, change its size and minimum/maximum dynamic size, adjust opacity, or move it vertically. Use Meters instead of Yards changes the overlay's distance units.",
            }),
            Heading("Beacon"),
            Row({
                Capture("Beacon", 220, 150, "Beacon"),
                Capture("BaseOnly", 220, 150, "Base Only"),
                Capture("BeaconOff", 220, 150, "Off"),
            }, 12),
            Text({
                "Choose the full light column, just the ground marker, a distance-based switch from beacon to base, or Off. Beacon Base Distance sets the switch distance. Adjust the beacon's opacity, base height and color separately.",
            }),
            Heading("Footer Text"),
            Row({
                Capture("WaypointFooterAll", 126, 76, "All"),
                Capture("WaypointFooterDistance", 126, 76, "Distance"),
                Capture("WaypointFooterArrivalTime", 126, 76, "Arrival Time"),
                Capture("WaypointFooterDestinationName", 126, 76, "Destination"),
                Capture("WaypointFooterNone", 126, 76, "None"),
            }, 8),
            Text({
                "Choose the destination name, distance, estimated arrival time, all available details or no footer. Info Text Size, Info Text Opacity and Distance/Arrival Time Opacity let you fine-tune the display.",
            }),
            Heading("Navigator"),
            Text({
                "Enable Navigator shows the directional arrow for off-screen destinations. Adjust its size, opacity, distance from screen center and color. Navigator Dynamic Distance adjusts placement with camera zoom.",
            }),
            Note("For a less distracting display, try a smaller marker, lower opacity or a base-only beacon."),
        },
    },
    {
        id = "overlay_pinpoint_plaque",
        title = "Pinpoint and Plaque",
        intro = "Customize what appears as you approach your destination.",
        blocks = {
            Row({
                Capture("Pinpoint", 220, 168, "Full"),
                Capture("PinpointPlaqueOff", 220, 168, "No Plaque"),
                Capture("PinpointOff", 220, 168, "Disabled"),
            }, 12),
            Heading("Close-range guidance"),
            Text({
                "Pinpoint Mode chooses the full marker and plaque, the marker without the plaque, or no close-range display. Show Pinpoint At sets when it appears, Hide Pinpoint At sets when it disappears at arrival. These visual distances are separate from manual waypoint clearing.",
                "",
                "Use Show Destination Info, Show Extended Info and Show Coordinate Fallback to control the information shown. Show Pinpoint Arrows toggles downward chevrons. Adjust Pinpoint Size, Opacity, Base Pinpoint Height and Camera Pinpoint Height to suit your camera and UI.",
            }),
            Heading("Choose a plaque style"),
            Text({
                "All standalone designs work on Retail and Forever.",
            }),
            Row({
                PlaqueSample(C.WORLD_OVERLAY_PLAQUE_MINIMAL, "Minimal"),
                PlaqueSample(C.WORLD_OVERLAY_PLAQUE_FOREVER, "Forever"),
                PlaqueSample(C.WORLD_OVERLAY_PLAQUE_BLIZZARD, "Blizzard"),
            }, 12),
            Row({
                PlaqueSample(C.WORLD_OVERLAY_PLAQUE_CLASSIC, "Classic"),
                PlaqueSample(C.WORLD_OVERLAY_PLAQUE_CLEAN, "Clean"),
                PlaqueSample(C.WORLD_OVERLAY_PLAQUE_MODERN, "Modern"),
            }, 12),
            Row({
                PlaqueSample(C.WORLD_OVERLAY_PLAQUE_FANTASY, "Fantasy", 102),
                PlaqueSample(C.WORLD_OVERLAY_PLAQUE_GLOWING_GEMS, "Glowing Gems", 102),
                PlaqueSample(C.WORLD_OVERLAY_PLAQUE_FUTURE, "Future", 102),
            }, 12),
            Row({
                PlaqueSample(C.WORLD_OVERLAY_PLAQUE_ALLIANCE, "Alliance", 102),
                PlaqueSample(C.WORLD_OVERLAY_PLAQUE_HORDE, "Horde", 102),
                PlaqueSample(C.WORLD_OVERLAY_PLAQUE_STEAMPUNK, "Steampunk", 102),
            }, 12),
            Heading("Fine-tune the plaque"),
            Text({
                "Minimal, Forever, Blizzard, Classic, Clean and Modern support independent Plaque Background Opacity and Plaque Border Opacity. Text and the context diamond stay independent. Minimal, Clean and Modern also support Plaque Border Thickness (1-8 pixels). Each style remembers its own adjustments. Overall Pinpoint Opacity fades the whole marker.",
                "",
                "Animate Plaque Effects toggles glow or pulse effects on designs that support them. If a supported UI styles AWP, disable that UI's styling to use the standalone artwork and supported border controls.",
            }),
            Note(
            "Forever and Blizzard are the default plaques on their respective clients. Fantasy is the former Default artwork, Future is the former image-based Modern style."),
        },
    },
    {
        id = "customization",
        title = "Settings and Customization",
        intro = "Find settings, preview changes and restore individual defaults.",
        blocks = {
            Heading("Find the right setting"),
            Text({
                "Open /awp options (or use the minimap button). Search by a setting name or keyword. Use filters for new or updated settings, navigation, visuals, size and opacity, colors and styles, or integrations. The preview pane shows examples or descriptions for available controls.",
                "",
                "- General: routing, flight assist, waypoint queues, quests, guide order and UI Style.",
                "- Profiles: create, share and switch setups.",
                "- TomTom Arrow: skins, arrow size and travel button size.",
                "- World Overlay: context and visibility: Waypoint, Pinpoint and Navigator have their own controls.",
                "- Guide pages: native window options, Tracker Viewer, Guide Actions and Chat Output.",
                "- Controller (Forever): native controller support and bindings.",
                "- UI pages: customize matching for loaded supported UI addons.",
                "- Integrations and Release Notes: see addon support and recent changes.",
            }),
            Heading("Reset a single setting"),
            Text({
                "A circular Reset icon appears beside changed values. Hover to see the default, click to restore that setting without resetting your profile. Dependent controls may refresh.",
            }),
            Heading("Colors and styles"),
            Text({
                "Auto follows quest, travel or destination context. Preset colors keep a consistent look, Custom lets you pick your own color. Waypoint Text defaults to Gray for readability. Guide text and chat can also use contextual colors or a fixed color. Tracker Viewer text additionally offers "
                .. Link("UI colors", "tracker_viewer", "text_colors") .. " and "
                .. Link("independent text sizes", "tracker_viewer", "text_sizes") .. ". See "
                .. Link("Tracker Viewer", "tracker_viewer") .. " for details.",
            }),
            Heading("Minimap button"),
            Text({
                "Left-click opens the quick menu, right-click opens AWP settings. Drag to move the button around the minimap or place it freely. The menu includes Help, Queue, Search Nearby and controls for loaded guides (even if their Viewers are disabled). The active guide appears first, followed by the other loaded guides in Guide Viewer Order.",
                "",
                "Hide or reset the button in the quick menu or use /awp minimap show or /awp minimap reset. The Blizzard addon compartment remains another way to reach the menu.",
            }),
        },
    },
    {
        id = "appearance",
        title = "UI Style",
        intro = "Match AWP to your UI without changing how navigation works.",
        blocks = {
            Heading("Choose a UI Style"),
            Text({
                "General > UI Style defaults to Automatic. Automatic matches the only available UI style or offers a choice when several are available. Choose AWP to use its original look. Escape dismisses the chooser for this session and keeps your saved choice.",
                "",
                "- DaylightUI: UI style needs only its core addon.",
                "- Ellesmere UI: Enable Blizzard Skins+ and its AzerothWaypoint skin.",
                "- ElvUI: UI style needs only its core addon.",
                "- GW2 UI: Appearance and custom tracker hosting are independent.",
                "",
                "If your selected UI addon is missing or disabled, AWP uses its own appearance and offers available alternatives. /awp status shows the selected and effective style.",
            }),
            Row({
                Capture("AWPOptions", 320, 197, "AWP"),
                Capture("OptionsDaylight", 320, 197, "DaylightUI (WoW Forever)"),
            }),
            Row({
                Capture("OptionsEllesmere", 320, 197, "Ellesmere UI"),
                Capture("OptionsElvUI", 320, 197, "ElvUI"),
            }),
            Heading("Customize individual areas"),
            Text({
                "Open the UI's AWP appearance page (in AWP or the UI's own settings). Both edit the same preferences. Choose each Guide Viewer, guide action panel, plaque, world marker/navigation labels, travel controls and AWP windows independently. Fonts, sizes, colors and panels can be adjusted where supported. For Tracker Viewer text, Auto keeps AWP's contextual colors even when UI text matching is enabled. Choose UI colors on the guide's Tracker Viewer page to use the UI's text colors. Custom Viewer text sizes override inherited sizes without changing the selected font, outline or shadow.",
                "",
                "Turn off a particular area to restore its original appearance. Choosing another provider keeps your saved preferences. Only one provider styles AWP at a time.",
            }),
            Heading("Tracker hosting"),
            Text({
                "UI Style controls how AWP looks. The installed tracker determines where Guide Viewers appear. DaylightUI's tracker requires DaylightUI_Quests, its appearance can work with other hosts. ElvUI uses Blizzard's tracker and retains its experimental docking limitation. Ellesmere UI's custom tracker is supported on Forever. GW2 UI's custom tracker is supported on both clients.",
                "",
                "With GW2 UI's map skin enabled, Waypoint Queues opens beside the map where possible and keeps the quest pane accessible on narrow maps.",
            }),
            Note(
            "Ellesmere UI's AzerothWaypoint settings include a live Search settings filter. Clear Search restores the unfiltered page. Preset changes that require a UI reload follow the UI's normal behavior."),
        },
    },
    {
        id = "profiles",
        title = "Settings Profiles",
        intro = "Keep different setups, back up preferences and share settings between clients.",
        blocks = {
            Heading("Choose or create a profile"),
            Text({
                "Open /awp options > Profiles. Your existing preferences become the Default profile.",
                "",
                "- Account Default: the profile used by characters set to Follow Account Default.",
                "- This Character: use the shared default or select a different named profile.",
                "- Create: start from AWP's defaults for your client.",
                "- Duplicate: copy the profile selected under Manage Profiles.",
                "",
                "Applying a different profile reloads the UI outside combat.",
            }),
            Capture("ProfilesOverview", 270, 234, "Account and character profile choices."),
            Heading("Export settings"),
            Text({
                "Select a profile, click Export and copy the settings string with Ctrl+C. Save it for backup or share it with another player. Profile strings work across Retail and Forever.",
            }),
            Heading("Import only what you need"),
            Text({
                "1. Click Import, paste the string and choose Review Import.",
                "2. Select the sections to import. Layout is unchecked by default to preserve saved frame positions.",
                "3. Review changes and unavailable integration warnings.",
                "4. Create Profile copies the active profile and applies selected sections. Replace Profile updates the selected profile after confirmation.",
                "",
                "Unchecked sections keep their existing settings. Missing values in selected sections use your client's defaults.",
            }),
            Capture("ProfilesImportReview", 470, 297, "An import review with Layout left unchecked."),
            Note(
            "Profiles include AWP preferences, per-guide text-size overrides and frame positions. Waypoint queues, active routes, guide progress, open guide tabs, flight favorites/history and other addons' settings are stored separately."),
        },
    },
    {
        id = "controller",
        title = "Controller (Forever)",
        intro = "Navigate AWP with WoW Forever's native controller UI.",
        blocks = {
            Heading("Get started"),
            Text({
                "Enable the game's controller UI, then open AWP Settings > Controller. AWP does not assign buttons or replace the game's tracker shortcut. In the game's key bindings, the AzerothWaypoint category offers three optional, unbound commands:",
                "",
                "- Navigate AWP Guides: focus the active visible guide or first visible guide in your order.",
                "- Open AWP Menu: open the quick menu.",
                "- Use Active Guide Action: use a prepared action from the active guide.",
            }),
            Heading("Move around the UI"),
            Text({
                "Use the D-pad to move between controls, Select to activate and Back to close menus or leave windows. Focused controls scroll into view. You can move across docked guide sections and navigate AWP settings, queues, Help, dialogs and action panels. Text entry and clipboard actions use the game or operating system's normal facilities.",
            }),
            Heading("Use guide actions"),
            Text({
                "Press the right stick on a focused guide task or objective to use its single action. If several are available, choose from a picker. More actions opens its context menu. Focusing a step does not make the guide active.",
                "",
                "A uniquely prepared standard action can remain usable during combat. If the guide changes, the indicator continues to identify the retained action until a replacement can be prepared after combat. Native helpers keep their normal restrictions. Temporary menu bindings are released in combat.",
            }),
            Heading("Adjust settings"),
            Text({
                "- Sliders: select, adjust Left/Right, then Select or Back to finish.",
                "- Guide order: select a row, move Up/Down, then Select to save or Back to cancel.",
                "- Color editor: adjust numeric channels or hex value, then Apply or Cancel.",
                "- Dropdowns: move through enabled choices and pages of longer lists.",
            }),
            Note(
            "Use /awp controllerdiag or the Controller settings page to check focus, bindings and the prepared action."),
        },
    },
    {
        id = "integrations",
        title = "Integrations",
        intro = "See what optional addons add to AzerothWaypoint.",
        blocks = BuildIntegrationHelpBlocks(),
    },
    {
        id = "commands",
        title = "Commands",
        intro = "Quick access, macros and diagnostic commands.",
        blocks = {
            Heading("Everyday commands"),
            Text({
                "/awp options - open settings (also config or settings).",
                "/awp help - open Help.",
                "/awp queue - open Waypoint Queues.",
                "/awp status - show routing, integrations and current settings.",
                "/awp changelog - open What's New.",
                "/awp repair - check and repair required TomTom/Zygor settings.",
                "/awp routing on|off|toggle - enable or disable AWP routing.",
                "/awp backend direct|zygor|mapzeroth|farstrider|dugi|polestar - choose a planner. QuestieRouter is also selectable in General on Forever.",
            }),
            Heading("Guide commands"),
            Text({
                "Use /awp <provider> help to see commands supported by that guide. Guide Provider names: zygor, dugi, rxp, apr, wowpro, polestar (Forever), questierouter (Forever). Commands work even with the AWP Viewer disabled.",
                "",
                "Examples:",
                "/awp zygor next",
                "/awp zygor compact toggle",
                "/awp dugi list",
                "/awp dugi switch 2",
                "/awp rxp output full",
                "/awp wowpro steps",
                "/awp questierouter tasks",
                "/awp questierouter automatic",
                "",
                "/awp <provider> viewer on|off|toggle|status controls the AWP Tracker Viewer.",
                "/awp <provider> native show|hide|toggle|status controls the guide addon's own window.",
                "Other actions vary by provider. Run list again before using an old index if guides change. Zygor load also accepts step N. Reset restores the native window and a safe position where supported, and preserves guide progress.",
            }),
            Heading("Queue commands"),
            Text({
                "/awp queue list - list queues.",
                "/awp queue use <id|index> - activate a queue.",
                "/awp queue clear [id|index] - clear a queue.",
                "/awp queue remove <id|index> <item> - remove a destination.",
                "/awp queue move <id|index> <from> <to> - reorder destinations.",
                "/awp queue import - import waypoint data.",
            }),
            Heading("Navigation settings"),
            Text({
                "/awp manualclear on|off|toggle",
                "/awp cleardistance <5-100>",
                "/awp trackroute on|off|toggle",
                "/awp untrackclear on|off|toggle",
                "/awp questclear on|off|toggle",
                "/awp addontakeover on|off|toggle|status",
                "/awp minimap show|hide|toggle|reset|status",
                "/awp skin <skin>",
                "/awp scale <0.60-2.00>",
            }),
            Heading("Flight Map Assist"),
            Text({
                "/awp flightassist marker on|off|toggle|status",
                "/awp flightassist auto disabled|exact|strong|status",
                "/awp flightassist catalog on|off|toggle|reset|status",
                "",
                "Catalog reset restores the Taxi List side/open state without clearing favorites or recent flights. Hold Alt to skip automatic flight selection.",
            }),
            Heading("Search Nearby"),
            Text({
                "Open Search Nearby from the minimap menu or use /awp search help. Zygor, Dugi and Polestar (Forever) can provide results. See the Search Nearby Help page for "
                .. Link("provider priority", "search_nearby", "providers") .. " and "
                .. Link("setup", "search_nearby", "setup") .. ".",
                "",
                "Examples:",
                "/awp search vendor",
                "/awp search repair",
                "/awp search auctioneer",
                "/awp search mailbox",
                "/awp search poison vendor",
                "/awp search reagents",
                "/awp search trainer alchemy",
                "/awp search trainer mage",
                "/awp search weapon master swords",
                "/awp search workshop blacksmithing",
            }),
            Heading("Diagnostics"),
            Text({
                "/awp status, /awp waytype and /awp stepdebug are useful for most navigation reports. Other diagnostic commands: /awp debug, /awp diag, /awp routedump, /awp routeenv, /awp traveldiag, /awp mem, /awp churn, /awp resolvercases, /awp plaque and /awp controllerdiag (Forever).",
                "",
                "For slow login or reload reports, include the Startup and TOC groups lines from /awp mem and say whether you logged in or reloaded.",
            }),
        },
    },
    {
        id = "troubleshooting",
        title = "Troubleshooting",
        intro = "Find common fixes without resetting your setup.",
        blocks = {
            Heading("The arrow is missing"),
            Text({
                "Check that TomTom is installed and enabled, AWP routing is on, and you have a destination. Check Hide During Combat if you are fighting. Try /awp status, /awp repair and /reload.",
            }),
            Heading("Two arrows are showing"),
            Text({
                "AWP can offer a prompt to let TomTom show navigation instead of the guide's own arrow. Accept only if you want that change. For Zygor, open /zygor options > Waypoint Arrow and disable Enable Waypoint Arrow. For Polestar, use Let AWP Show Navigation. Turning off AWP routing restores normal Dugi planning and Polestar follower behavior.",
            }),
            Heading("A Viewer is missing"),
            Text({
                "Check the guide addon is enabled, its Tracker Viewer is enabled, a guide is loaded and the tracker is visible and expanded. If the tracker is faint or only appears on hover, check tracker opacity, Edit Mode and mouseover addons. On Forever with Questie, check Always Show Tracker.",
                "",
                "/awp status reports the detected tracker and visibility. After changing tracker addons, try /reload. See "
                ..
                Link("Tracker Viewer", "tracker_viewer", "supported_trackers") ..
                " for supported trackers and the Blizzard docking warning.",
            }),
            Heading("I hid the original guide window"),
            Text({
                "Open the guide's settings in AWP and turn off its native-frame hiding option, or use the minimap menu. /awp <provider> native show restores it where supported. /awp <provider> reset can recover a lost window where the addon offers a safe position reset and preserves guide progress. Dugi's anchored small frame must be disabled before its floating frame can be hidden.",
            }),
            Heading("No guide action buttons are visible"),
            Text({
                "Check the guide's Guide Actions page. Make sure at least one of the AWP action displays is enabled or native action controls are visible, and that the matching category is enabled. Inline buttons and native helpers may be unavailable in combat.",
            }),
            Heading("A guide is visible but is not directing navigation"),
            Text({
                "Only one destination directs navigation at a time. A manual waypoint, temporary route or another guide may be active. Activate the desired guide or queue, or deactivate the current manual queue to return to guide navigation.",
            }),
            Heading("The route looks wrong"),
            Text({
                "Check your preferred and active backend with /awp status. AWP may be using a fallback or a walking-only route according to planner preferences. Some routes lack terrain or floor data. If an addon's waypoint is ignored, check General > Addon Waypoint Adoption and its allow/block lists. Quest data may be delayed after login or quest updates, open the quest log or wait for the next update.",
            }),
            Heading("Nearby search has no result"),
            Text({
                "Check that a supported search provider (Zygor, Dugi or Polestar on Forever) is loaded and ready. Use /awp search help to see available services. Guide Viewer Order determines which provider is tried first, enabling a Viewer is not required.",
            }),
            Heading("The minimap button is missing"),
            Text({
                "Use /awp minimap show or /awp minimap reset. The Blizzard addon compartment can still open the AWP quick menu.",
            }),
            Heading("Guide colors or text sizes are not what I expected"),
            Text({
                "Open the guide's Tracker Viewer settings. Auto keeps AWP's contextual colors, even with UI text-color matching on. Choose UI colors to use the selected style's text colors, or select a fixed color.",
                "Enable Use custom Viewer text sizes to change this guide's heading, goal, notes and progress sizes. Disable it to return to the tracker or UI's sizing. Your selected font, outline and shadow remain in effect.",
            }),
            Heading("The appearance is not what I selected"),
            Text({
                "Check General > UI Style and /awp status for the effective style. Confirm the required UI addon and its skin module are enabled. Check the individual area's matching switch. If a standalone plaque does not appear, disable the UI's appearance setting for Pinpoint Plaque.",
            }),
            Heading("Report a problem"),
            Text({
                "Include your client (Retail or Forever), what you clicked, active guide, selected routing backend, /awp status, /awp waytype and /awp stepdebug for guide routing. Include any Lua error and whether the problem occurs with a particular tracker or UI Style.",
            }),
        },
    },
    {
        id = "whats_new",
        title = "What's New",
        intro = "Recent release notes and highlights.",
        blocks = {
            { type = "recent_changelog", limit = 3 },
        },
    },
}

local _, private = ...
if private and private.finishLoadGroup then private.finishLoadGroup("Takeovers, taxi and docs") end
