# AzerothWaypoint

> A TomTom-powered navigation bridge, route planner selector, manual waypoint queue, and 3D world overlay for World of Warcraft.

![](https://github.com/MorningStarGG/AzerothWaypoint/blob/main/media/banner.png?raw=true)

![Version](https://img.shields.io/badge/version-4.1.0-blue)
![Game](https://img.shields.io/badge/World%20of%20Warcraft-Addon-orange)
![Required](https://img.shields.io/badge/Required-TomTom-red)
![Optional](https://img.shields.io/badge/Optional-Zygor%20%7C%20APR%20%7C%20WoWPro%20%7C%20Farstrider%20%7C%20Mapzeroth%20%7C%20InFlight-lightgrey)
![License](https://img.shields.io/badge/license-GPL--3.0-green)

**Support development:** [Donate via PayPal](https://paypal.me/TheThinkCritic)

---

## ZygorWaypoint is now AzerothWaypoint

AzerothWaypoint is the renamed and expanded successor to ZygorWaypoint.

**TomTom is now the only required dependency.** Zygor Guides Viewer is still fully supported, but it is optional. AzerothWaypoint can also work with Azeroth Pilot Reloaded, WoWPro, FarstriderLib, Mapzeroth, Blizzard map and quest sources, imported TomTom waypoint lists, and supported external waypoint addons.

---

## Table of Contents

- [What AzerothWaypoint Does](#what-azerothwaypoint-does)
- [Quick Start](#quick-start)
- [How Navigation Works](#how-navigation-works)
- [Feature Highlights](#feature-highlights)
- [Supported Integrations](#supported-integrations)
- [What's New in 4.1.0](#whats-new-in-410)
- [What Changed in 4.0.0](#what-changed-in-400)
- [Options](#options)
- [Slash Commands](#slash-commands)
- [Installation](#installation)
- [Upgrade Notes](#upgrade-notes)
- [Troubleshooting](#troubleshooting)
- [Known Notes](#known-notes)
- [Author](#author)
- [Contributing](#contributing)
- [License](#license)

---

## What AzerothWaypoint Does

AzerothWaypoint connects multiple waypoint sources to one controlled navigation flow.

It can route and present destinations from:

- TomTom waypoints
- guide steps from Zygor Guides Viewer, Azeroth Pilot Reloaded, and WoWPro
- Blizzard map clicks, quest pins, POIs, supertracked quests, and tracked quests
- imported `/ttpaste` waypoint batches
- supported external waypoint addons like HandyNotes, SilverDragon, and RareScanner

AzerothWaypoint then sends the active route to:

- TomTom's arrow
- AWP's native 3D world overlay
- the waypoint queue UI
- contextual icons, labels, colors, and travel action prompts

In short:

```text
TomTom shows the arrow.
AzerothWaypoint controls the route flow.
Optional integrations provide richer route planning and guide data.
```

---

## Quick Start

1. Install **TomTom** and **AzerothWaypoint**.
2. Optionally install **Zygor Guides Viewer**, **Azeroth Pilot Reloaded**, **WoWPro**, **FarstriderLib**, or **Mapzeroth**.
3. Open options:

```text
/awp options
```

4. Pick your routing backend under **General > Routing Backend**.

| Backend | Best For |
|---|---|
| **TomTom Direct** | Simple direct waypoint navigation. Always available. |
| **Farstrider** | Travel-aware routing with flights, portals, transports, items, spells, and travel nodes. |
| **Mapzeroth** | Mapzeroth travel routing with flights, portals, transports, items, spells, and travel nodes. |
| **Zygor** | Zygor users who want LibRover travel routing, travel actions, search data, and transport support. |

5. Open the waypoint queue UI from the world map side tab or with:

```text
/awp queue
```

6. Use the AzerothWaypoint minimap button for quick access to settings, help, the queue, and supported integration controls.

7. Open help or release notes in-game:

```text
/awp help
/awp changelog
```

---

## How Navigation Works

AzerothWaypoint separates navigation into three layers:

| Layer | Meaning | Examples |
|---|---|---|
| **Source** | Where the destination came from | guide step, map click, quest POI, imported queue, external addon |
| **Backend** | How the route is planned | TomTom Direct, Farstrider, Mapzeroth, Zygor |
| **Carrier** | What presents the route | TomTom arrow, AWP 3D overlay, queue UI |

Example flows:

```text
Guide step -> guide provider -> route backend -> TomTom arrow + 3D overlay

Map click -> manual queue policy -> route backend -> TomTom arrow + 3D overlay

/ttpaste batch -> manual queue -> active queue item -> route backend -> TomTom arrow + 3D overlay

Quest POI -> Blizzard takeover -> quest-aware route -> TomTom arrow + 3D overlay
```

This separation lets manual queues, guide providers, transient addon routes, quest takeovers, and imported waypoint lists coexist without constantly deleting or overriding each other.

---

## Feature Highlights

### TomTom Arrow Bridge

TomTom remains the visible navigation arrow. AzerothWaypoint decides what destination owns the route, which backend should plan it, and what contextual presentation should appear around it.

AWP can:

- push guide, quest, POI, queue, and addon destinations into TomTom
- preserve normal TomTom behavior for direct waypoints
- suppress duplicate guide arrows where appropriate
- apply custom TomTom arrow skins
- show secure travel action buttons for route legs that require an item, spell, toy, hearthstone, portal, or similar action

### Selectable Routing Backends

AWP can route the same destination through different backends:

| Backend | Behavior |
|---|---|
| **TomTom Direct** | Single-leg direct fallback. Always available. |
| **Farstrider** | Uses FarstriderLib and FarstriderLibData when available. |
| **Mapzeroth** | Uses Mapzeroth when available. |
| **Zygor** | Uses Zygor and LibRover when Zygor is available. |

Unavailable backend selections fall back safely.

You can change backends in options or with:

```text
/awp backend direct
/awp backend farstrider
/awp backend mapzeroth
/awp backend zygor
```

### Guide Provider Support

AWP 4.0 is no longer limited to Zygor guide routing.

Supported guide providers:

- **Zygor Guides Viewer**
- **Azeroth Pilot Reloaded**
- **WoWPro**

Guide providers can publish:

- current guide target
- active step title
- subtext or objective progress
- quest metadata
- queue projection

Zygor still has the richest integration because it can also provide search data and a routing backend, but APR and WoWPro now receive much closer to Zygor-style actionable overlay text and queue presentation.

### Manual Waypoint Queues

Manual waypoints are no longer just throwaway TomTom points.

AWP supports:

- persistent manual queues
- imported `/ttpaste` queues
- destination queues for multi-click flows
- transient queues for short-lived external sources
- guide queues shown alongside manual queues
- activate/deactivate without deleting queues
- bulk queue deletion
- per-queue delete icons
- queue detail pages
- final destination focus on the world map

Manual Click Queue Behavior controls how map clicks are handled:

| Mode | Behavior |
|---|---|
| **Create New Queue** | Put the clicked destination in its own new queue. |
| **Replace Active** | Replace the currently active manual queue. |
| **Append** | Add the clicked destination to the current queue. |
| **Ask** | Prompt each time. |

### Blizzard Map and Quest Takeovers

AWP can adopt supported Blizzard navigation sources and route them through the active backend.

Supported Blizzard sources include:

- user waypoints
- quest POIs
- supertracked quests
- tracked quests
- area POIs
- vignettes
- taxi nodes
- gossip POIs
- dig sites
- housing plots

Quest-backed targets can preserve quest metadata, objective context, source labels, icons, and clear behavior where Blizzard exposes enough data.

### 3D World Overlay

AWP includes its own native 3D overlay. It does not require WaypointUI.

Overlay modes:

| Mode | Purpose |
|---|---|
| **Waypoint** | Long-range in-world destination marker. |
| **Pinpoint** | Close-range destination plaque and arrival marker. |
| **Navigator** | Off-screen directional arrow. |

The overlay is aware of:

- quest state
- quest type
- world quest type
- guide provider
- travel route type
- source addon
- manual queue metadata
- external transient sources
- services and profession searches

### Quest-Aware Icons and Text

AWP can present different icon families for:

- available quests
- incomplete quests
- completed quests
- world quests
- daily, weekly, campaign, legendary, artifact, calling, meta, repeatable, and important quests
- racing world quests
- dungeons, raids, delves, portals, taxis, inns, and other travel targets

Quest-backed targets can show objective progress once the quest is active.

### External Addon Waypoint Sources

AWP includes a source registry for addon-created waypoints.

Current source-aware integrations:

- **SilverDragon**
- **RareScanner**
- **HandyNotes**

These are handled as transient manual sources, so they can briefly take over navigation without destroying persistent manual queues.

AWP also includes controls for unknown addon waypoint adoption:

- enable or disable adoption
- review detected callers
- allowlist addon folder names
- blocklist addon folder names

### WorldQuestTab Integration

WorldQuestTab quest pin clicks can be adopted by AzerothWaypoint and routed through the active backend.

AWP captures:

- quest title
- quest ID
- map and coordinates
- source addon
- quest type and world quest metadata when Blizzard exposes it

### Special Travel Actions

Some route legs require using an item, spell, toy, hearthstone, portal, or similar travel action.

When the current route leg needs a special action, AWP can show a secure special travel button in place of normal arrow presentation.

### Combat Visibility

AWP can temporarily hide TomTom, the special travel button, the 3D world overlay, or both while you are in combat, then restore them afterward.

### Minimap Button and Addon Compartment

AWP includes a native minimap button with no external minimap library dependency.

The minimap button can:

- open the AWP quick menu
- open AWP settings
- open in-game help
- open the queue panel
- toggle Tracker Viewer
- toggle Zygor's native viewer when Zygor is loaded
- expose Zygor guide controls when Zygor is loaded
- reset or hide the minimap button

The button can snap around the minimap edge or be dragged away as a free-floating button. AWP also registers a Blizzard addon-compartment entry so the quick menu remains available if you hide the minimap button.

### Flight Map Assist

When the active route uses a flight path, AWP can mark the intended destination on the retail flight map.

- Exact Zygor/LibRover taxi destinations can be matched by Blizzard taxi node ID.
- Mapzeroth and Farstrider routes can use strict coordinate/name matches where the visible flight-map data is clear enough.
- The marker is visual-only; it does not create routes or supertrack taxi nodes.
- Optional `Auto Take Flight Paths` is disabled by default and pressing `Alt` suppresses it for the current flight-map interaction.
- The optional taxi list adds a searchable AWP side panel with the route destination at the top, favorites, recent flights, current-zone flights, and reachable destinations grouped by zone.
- The taxi list can auto-attach to the side with available screen space, follow the flight map when it is moved, center against the visible map area, and resize for shorter lists.
- The taxi list destination text size can be adjusted from General > Routing.
- If InFlight is installed and has timing data for the current route, the taxi list can show exact or estimated flight times.

Options:

```text
General > Routing > Show Flight Map Route Marker
General > Routing > Auto Take Flight Paths
General > Routing > Show Flight Map Taxi List
General > Routing > Flight Map Taxi List Side
General > Routing > Flight Map Taxi List Text Size
```

### Arrow Skins

AWP includes an arrow skin system for TomTom.

Built-in AWP skins:

- AWP
- AWP Bomber
- AWP Modern
- Alliance
- Horde

Zygor skins, when Zygor is loaded:

- Starlight
- Stealth

### Zygor Integration and Viewer Controls

When Zygor is installed, AWP can:

- use compact guide presentation
- hide step backgrounds until mouseover
- hide step backgrounds and line colors until mouseover
- show Zygor guides in the objective tracker with Tracker Viewer
- hide Zygor's native viewer without disabling Zygor guide state or waypoints
- control Zygor steps, guide switching, guide loading, guide closing, menus, and settings from the minimap menu or `/awp zygor` commands
- show the current Zygor step in your own chat frame on step change or on demand with contextual or selected colors
- detect Zygor arrow conflict settings and offer a one-click disable prompt

### Zygor Tracker Viewer

When Zygor is installed, AWP can show the active Zygor guide inside the objective tracker instead of requiring Zygor's full-size native viewer to stay visible.

Tracker Viewer supports:

- Blizzard's default Objective Tracker
- Kaliel's Tracker
- current guide title and step rows
- previous, next, and skip controls
- guide switching and guide picker access
- Zygor menu and settings access
- clickable confirm rows
- active sticky steps grouped above the current step
- long tip-block grouping so large guide steps do not overflow the tracker
- square, rounded, or hidden progress bar styles
- contextual tracker text colors for common Zygor goal types

You can also hide Zygor's native viewer while keeping Zygor's guide engine, active waypoints, guide picker, settings, and guide navigation available through AWP.

### Search Routing

With Zygor installed, AWP can route to nearby services and profession targets:

```text
/awp search vendor
/awp search auctioneer
/awp search banker
/awp search mailbox
/awp search trainer blacksmithing
/awp search workshop engineering
```

Supported services include vendors, repair, auctioneers, bankers, barbers, flight masters, innkeepers, mailboxes, riding trainers, stable masters, transmogrifiers, void storage, profession trainers, and profession workshops.

---

## Supported Integrations

AWP includes an in-game **Integrations** tab in `/awp options` and a matching Help page. Those pages explain what each supported addon or source contributes, show load status, and provides buttons to copy the URLs of the addons.

### Required

| Addon | What AWP Uses It For |
|---|---|
| **TomTom** | Required waypoint carrier and primary arrow display. AWP chooses the active route; TomTom shows it. |

### Guide Addons

| Addon | What AWP Uses It For |
|---|---|
| **Zygor Guides Viewer** | Guide targets, LibRover routing, search data, Zygor-style arrow skins, Tracker Viewer, native viewer hiding, guide controls, and chat step display. |
| **Azeroth Pilot Reloaded** | Guide step targets, guide text, objective context, and guide queue. |
| **WoWPro** | Guide step targets, guide text, objective context, and guide queue. |

### Route Backends

| Backend | What AWP Uses It For |
|---|---|
| **Zygor / LibRover** | Travel-aware routing with rich Zygor route data, including exact taxi node matches where LibRover exposes them. |
| **FarstriderLib / FarstriderLibData** | Travel-aware route planning with flights, portals, transports, items, spells, and travel nodes when available. |
| **Mapzeroth** | Travel-aware route planning with Mapzeroth pathfinding data when available. |

### Flight Map

| Addon | What AWP Uses It For |
|---|---|
| **InFlight** | Optional flight timing data for AWP's flight-map taxi list. |

### Tracker Addons

| Addon | What AWP Uses It For |
|---|---|
| **Kaliel's Tracker** | Optional objective tracker host for AWP's Zygor Tracker Viewer, including Zygor guide rows, sticky steps, long-tip grouping, and header controls. |

### Map and POI Addons

| Addon | What AWP Uses It For |
|---|---|
| **WorldQuestTab** | World quest POI adoption with quest metadata when available. |
| **HandyNotes** | Source-aware temporary POI waypoint adoption, including plugins such as MapNotes. |
| **SilverDragon** | Source-aware rare waypoint adoption as temporary routes. |
| **RareScanner** | Source-aware rare waypoint adoption as temporary routes. |

### Blizzard Sources and Other Addons

AWP can also adopt supported Blizzard map clicks, user waypoints, quest POIs, supertracked quests, tracked quests, area POIs, vignettes, taxi nodes, gossip POIs, dig sites, and housing plots.

Other addons that create normal TomTom or Blizzard waypoint calls can work through AWP's addon waypoint adoption flow. You can review detected callers and manage allow/block lists under **General > Addon Waypoint Adoption**.

---

## What's New in 4.1.0

### Minimap Button

- Added a native AzerothWaypoint minimap button and addon-compartment entry.
- Left-click opens the quick menu. Right-click opens AWP settings.
- The button supports minimap-edge snapping near the minimap and free-floating placement away from it.
- The quick menu opens settings, help, queue, Tracker Viewer controls, Zygor controls, and minimap button management.

### Queue and Tracker Reliability

- `/awp queue` and the minimap button's Open Queue action now force the quest-log side panel open for that interaction, so the AWP queue tab is visible even when the world map normally opens with the quest log hidden.
- `/awp status` reports objective tracker host, hidden state, opacity state, Tracker Viewer state, Zygor native viewer state, chat step-display state, Flight Map Assist and Taxi List state, and minimap button state.
- AWP warns after login or reload if Tracker Viewer is enabled but the active objective tracker is hidden or appears transparent.
- The intermediate surrogate navigation-point notice is throttled so rapidly stepping through guides does not spam chat.
- In-game help page text can now be selected and copied.

### Flight Map Assist

- Added a flight-map marker for route legs that use flight paths.
- Exact Zygor/LibRover taxi destinations can match by Blizzard taxi node ID.
- Mapzeroth and Farstrider flight-path legs can match through strict visible coordinate/name checks where available.
- Added opt-in `Auto Take Flight Paths` modes for exact matches or strong matches. `Auto Take Flight Paths` is disabled by default and pressing `Alt` suppresses it for the current flight-map interaction.
- Added an AWP taxi list attached to the flight map with the route destination at the top, favorites, recent flights, current-zone flights, search, and reachable destinations grouped by zone.
- The taxi list can auto-attach to the side with available screen space, follow the flight map when it is moved, center against the visible map area, and resize for shorter lists.
- If InFlight is installed, AWP can show exact or estimated flight times in the taxi list when matching timing data is available.

### Integrations Page

- Added a bottom-tab **Integrations** page in AWP options and a matching in-game Help page.
- These pages explain supported addons, route backends, tracker addons, flight-map helpers, and Blizzard sources in normal user terms, including load status and buttons to copy the URLs of the addons.

### Zygor Tracker Viewer

- Added an optional Zygor guide display inside Blizzard's Objective Tracker or Kaliel's Tracker.
- Header controls for guide title, previous/next, guide switching, Zygor menu/settings, and progress display.
- Square, rounded border, and hidden tracker progress bar styles.
- Contextual tracker text colors for common Zygor goal types.
- Long tip-block grouping and sticky-step display for large or persistent Zygor guide steps.
- Clickable confirm rows in the tracker.
- No-guide-loaded row that opens Zygor's guide picker.

### Zygor Native Viewer Controls

- Added an option to hide Zygor's native viewer while leaving Zygor's guide logic, waypoints, guide picker, menus, and settings available.
- Added AWP minimap menu controls for Zygor next, previous, skip, guide picker, open guide switching, guide closing, guide menu, and settings.
- Added macro-friendly `/awp zygor` commands for the same guide controls.
- Added `/awp zygor reset` to recover a hidden, lost, or glitched native Zygor viewer.
- Added optional chat step display for the current Zygor step, including step percentage, contextual colors, sticky step summaries, and `/awp zygor output`.
- Closing all Zygor guide tabs now clears AWP's guide route state so the last guide waypoint does not linger.

### Recent 4.0.x Highlights

- HandyNotes support was added, including plugins such as MapNotes.
- WorldQuestTab adoption was improved for world quest and bonus objective clicks.
- Hide During Combat was added and refined for TomTom, the special travel button, and the world overlay.
- The in-game help frame received expanded pages, screenshots, and a page dropdown.

---

## What Changed in 4.0.0

Version 4.0.0 is a major release and rename from the old ZygorWaypoint identity to AzerothWaypoint.

### Big Picture

- Renamed the addon to **AzerothWaypoint**.
- TomTom is now the only required dependency.
- Zygor is optional instead of being the whole routing model.
- APR and WoWPro guide providers were added.
- Farstrider and Mapzeroth route backends were added.
- The old Zygor-only bridge was replaced with a modular route authority system that can choose between multiple sources, guide providers, queues, and route backends.

### Guide Integrations

- Added a guide provider dispatcher.
- Added APR provider support.
- Added WoWPro provider support.
- Enhanced Zygor parity through the existing Zygor resolver.
- Guide queues can remain visible even when another source is the active route.

### Routing and Queues

- Added selectable routing backends.
- Added persistent manual queues.
- Added guide queue projection.
- Added transient queues for short-lived addon sources.
- Added manual click queue behavior: create, replace, append, ask.
- Added queue list/detail UI, bulk delete, queue/destination delete icons, and queue context menus.

### World Overlay

- Reorganized world overlay code into core, assets, pinpoint, presentation, and runtime modules.
- Added and refined contextual icons, tints, quest states, travel types, and external source presentation.
- Added Auto color behavior with contextual hints.
- Added Gray color preset.
- Removed the old None color option because it duplicated White behavior.
- Fixed stale atlas/UV texture carryover when switching icon families.
- Moved overlay media assets into clearer folders.

### Arrow and Travel

- Added registered TomTom arrow skins.
- Added AWP, AWP Bomber, AWP Modern, Alliance, and Horde skins.
- Preserved Starlight and Stealth when Zygor is loaded.
- Added secure special travel button support.
- Added Special Travel Button Scale.

### Options and Help

- Rebuilt options into a custom canvas UI with search, filters, previews, release notes, and section images.
- Added new option sections: About, General, TomTom Arrow, World Overlay, Waypoint, Pinpoint, Navigator, and conditional Zygor.
- Added in-game help and release notes flow.
- Added detected addon caller controls, allowlist, and blocklist.

---

## Options

Open options with:

```text
/awp options
```

or:

```text
/awp config
```

You can also open options through:

```text
Game Menu -> Options -> AddOns -> AzerothWaypoint
```

Options are organized into these sections:

| Section | Controls |
|---|---|
| **About** | Addon summary, help access, release notes, author links |
| **General** | Routing, backend selection, flight map assist, manual queue behavior, quest routing, quest clearing, addon waypoint adoption, minimap button visibility, combat visibility |
| **TomTom Arrow** | Custom arrow skins, arrow scale, special travel button scale |
| **World Overlay** | 3D overlay enablement, hover fade, context display, shared icon and color behavior |
| **Waypoint** | Long-range marker mode, size, opacity, beacon, footer text, units, and colors |
| **Pinpoint** | Close-range marker, plaque style, destination info, arrows, coordinates, colors, and height |
| **Navigator** | Off-screen arrow size, opacity, distance, dynamic distance, and color |
| **Zygor** | Compact Zygor viewer presentation, native viewer hiding, Tracker Viewer, tracker progress style, tracker text colors, and chat step display when Zygor is loaded |

The bottom tabs also include **Release Notes** and **Integrations**. Integrations explains supported addons and sources, shows whether addon-based integrations are loaded, and provides copy-link buttons when addon URLs are configured.

### General Options

General navigation behavior includes:

- Enable Routing
- Routing Backend
- Show Flight Map Route Marker
- Auto Take Flight Paths
- Show Flight Map Taxi List
- Flight Map Taxi List Side
- Flight Map Taxi List Text Size
- Manual Click Queue Behavior
- Auto-Clear Manual Waypoints on Arrival
- Manual Waypoint Clear Distance
- Auto-Route Tracked Quests
- Auto-Clear Untracked Quests
- Auto-Clear Supertracked Quests on Arrival
- Adopt Waypoints from Unknown Addons
- Detected Addon Callers
- Addon Allowlist
- Addon Blocklist
- Show Minimap Button
- Hide During Combat

### TomTom Arrow Options

TomTom arrow controls include:

- Use Custom Arrow Skin
- Arrow Skin
- TomTom Arrow Scale
- Special Travel Button Scale

### World Overlay Options

Shared 3D overlay controls include:

- Enable 3D World Overlay
- Fade on Hover
- Context Display
- Context Diamond color
- Icon color

### Waypoint Options

Long-range marker controls include:

- Waypoint Mode
- Waypoint Size
- Waypoint Min Size
- Waypoint Max Size
- Waypoint Opacity
- Waypoint Vertical Offset
- Beacon Style
- Beacon Base Distance
- Beacon Opacity
- Base Vertical Offset
- Yards/meters display
- Footer Text Mode
- Footer Text Size
- Footer Text Opacity
- Waypoint Text Color
- Beacon Color

### Pinpoint Options

Close-range destination controls include:

- Pinpoint Mode
- Show Pinpoint At
- Hide Pinpoint At
- Pinpoint Size
- Pinpoint Opacity
- Plaque Style
- Animate Plaque Effects
- Show Destination Info
- Show Extended Info
- Show Coordinate Fallback
- Show Pinpoint Arrows
- Base Pinpoint Height
- Camera Pinpoint Height
- Title color
- Subtext color
- Plaque color
- Animated part color
- Chevron color

Plaque styles:

- Default
- Glowing Gems
- Horde
- Alliance
- Modern
- Steampunk

### Navigator Options

Off-screen marker controls include:

- Enable Navigator
- Navigator Size
- Navigator Opacity
- Navigator Distance
- Navigator Dynamic Distance
- Navigator Arrow color

### Zygor Options

Shown only when Zygor is loaded:

- Show Only Guide Steps Until Mouseover
- Hide Step Backgrounds Until Mouseover
- Hide Zygor's Native Frame
- Enable Tracker Viewer
- Tracker Viewer Progress Bar
- Tracker Viewer Text
- Show Step in Chat Frame on Step Change
- Chat Step Text Output
- Chat Sticky Summary Output

---

## Slash Commands

Root command:

```text
/awp
```

### Common Commands

| Command | Description |
|---|---|
| `/awp status` | Show addon status, routing backend, key toggles, and version. |
| `/awp options` | Open options. |
| `/awp config` | Open options. |
| `/awp help` | Open in-game help. |
| `/awp changelog` | Open What's New. |
| `/awp routing on\|off\|toggle` | Enable or disable route ownership. |
| `/awp backend direct\|zygor\|mapzeroth\|farstrider` | Choose routing backend. |
| `/awp flightassist marker on\|off\|toggle\|status` | Toggle the retail flight-map route marker. |
| `/awp flightassist auto disabled\|exact\|strong\|status` | Configure opt-in local auto-take for matched flight paths. |
| `/awp flightassist catalog on\|off\|toggle\|reset\|status` | Control the AWP taxi list attached to the retail flight map. |
| `/awp queue` | Open the waypoint queue panel. |
| `/awp manualclear on\|off\|toggle` | Toggle manual waypoint auto-clear. |
| `/awp cleardistance <5-100>` | Set manual waypoint clear distance. |
| `/awp trackroute on\|off\|toggle` | Toggle auto-routing for newly tracked quests. |
| `/awp untrackclear on\|off\|toggle` | Toggle clearing queue items when quests are untracked. |
| `/awp questclear on\|off\|toggle` | Toggle arrival clear for supertracked quest routes. |
| `/awp addontakeover on\|off\|toggle\|status` | Control unknown addon waypoint adoption. |
| `/awp compact on\|off\|toggle` | Toggle Zygor compact viewer mode. |
| `/awp trackerviewer on\|off\|toggle\|status` | Toggle the Zygor Tracker Viewer. |
| `/awp zygorviewer show\|hide\|toggle\|status` | Show or visually hide Zygor's native viewer. |
| `/awp zygor next\|prev\|skip\|picker\|load <title>\|output [full\|sticky]\|menu\|settings\|list\|switch <index>\|close [index]\|reset` | Control Zygor guides from AWP. |
| `/awp minimap show\|hide\|toggle\|reset\|status` | Control the AWP minimap button. |
| `/awp skin <skin>` | Set TomTom arrow skin. |
| `/awp scale <0.60-2.00>` | Set custom arrow skin scale. |
| `/awp search <type>` | Route to a service or profession target. |
| `/awp repair` | Repair TomTom/Zygor settings AWP depends on. |

### Queue Commands

```text
/awp queue
/awp queue list
/awp queue use <id|index>
/awp queue clear [id|index]
/awp queue remove <id|index> <item>
/awp queue move <id|index> <from> <to>
/awp queue import
```

Queue aliases:

- `queues`
- `queue open`
- `queue show`
- `queue ls`
- `queue rm`
- `queue paste`
- `queue ttpaste`

### Zygor Commands

Zygor commands require Zygor Guides Viewer to be installed and enabled.

```text
/awp trackerviewer on|off|toggle|status
/awp zygorviewer show|hide|toggle|status
/awp zygor next
/awp zygor prev
/awp zygor skip
/awp zygor picker
/awp zygor load <guide title> [step N]
/awp zygor output
/awp zygor output full
/awp zygor output sticky
/awp zygor list
/awp zygor switch <index>
/awp zygor close [current|index|all]
/awp zygor menu
/awp zygor settings
/awp zygor reset
```

These are useful if you hide Zygor's native viewer and want macros or keybinds for guide controls instead of using the minimap menu. The `output` command shows the current step in your own chat only; it does not send anything to say, party, raid, guild, or public channels. The `reset` command shows Zygor's native viewer again and resets Zygor's own window position if it becomes hidden, lost, or glitched.

### Flight Assist Commands

```text
/awp flightassist marker on
/awp flightassist marker off
/awp flightassist marker toggle
/awp flightassist marker status
/awp flightassist auto disabled
/awp flightassist auto exact
/awp flightassist auto strong
/awp flightassist auto status
/awp flightassist catalog on
/awp flightassist catalog off
/awp flightassist catalog toggle
/awp flightassist catalog reset
/awp flightassist catalog status
```

`exact` auto-take uses exact Zygor/LibRover taxi node matches. `strong` also allows strict visible coordinate/name matches from other route backends where available.
The taxi list command controls only the attached flight-map list; `reset` restores its side/open state without clearing favorites or recent flights.

### Search Commands

Search commands require Zygor to be installed and enabled.

```text
/awp search vendor
/awp search repair
/awp search auctioneer
/awp search mailbox
/awp search trainer alchemy
/awp search workshop blacksmithing
```

Common aliases:

- `ah`
- `auction`
- `bank`
- `inn`
- `mail`
- `mog`
- `tmog`
- `store`
- `stables`

---

## Installation

1. Download AzerothWaypoint.
2. Place the folder here:

```text
World of Warcraft/_retail_/Interface/AddOns/AzerothWaypoint/
```

3. If you previously used ZygorWaypoint, delete the old folder:

```text
World of Warcraft/_retail_/Interface/AddOns/ZygorWaypoint/
```

4. Install and enable **TomTom**.
5. Enable any optional supported addons you want to use.
6. Restart the game or run:

```text
/reload
```

7. Open options:

```text
/awp options
```

---

## Upgrade Notes

### From ZygorWaypoint or pre-4.0 development builds

Old ZygorWaypoint settings are not migrated. This was intentional for the v4 rename and development reset.

If the old `ZygorWaypoint` addon folder is still installed, remove or disable it to avoid conflicts.

### WaypointUI

AWP now ships its own 3D world overlay. WaypointUI is not required.

If you still use WaypointUI, AWP may remind you that its native overlay is the recommended setup.

---

## Troubleshooting

### The arrow is missing

Try:

```text
/awp status
/awp repair
/reload
```

Also check that TomTom is installed and enabled.

### Zygor's arrow is still showing

Open Zygor settings:

```text
/zygor options
```

Then go to:

```text
Waypoint Arrow -> Enable Waypoint Arrow
```

Turn it off. AWP may offer a one-click prompt when it detects this conflict.

### A guide addon appears in the queue but is not controlling navigation

That can be normal.

Guide queues can remain visible even when a manual queue, transient route, or another provider currently owns the active route.

Activate the queue from the queue panel or use the guide addon normally to make it the active provider again.

### Imported waypoints are not forming a queue

Check:

- `/awp queue`
- `/awp status`

### The Zygor Tracker Viewer is missing

Check:

- Zygor Guides Viewer is installed, enabled, and loaded.
- **Zygor > Tracker Viewer > Enable Tracker Viewer** is on.
- Blizzard's Objective Tracker or Kaliel's Tracker is visible.
- The tracker is not being hidden or made transparent by another addon.

Use:

```text
/awp status
```

AWP reports which objective tracker host it detected and whether the tracker appears hidden or transparent.

### Unknown addon waypoints are being ignored

Check:

- **General > Adopt Waypoints from Unknown Addons**
- **Detected Addon Callers**
- **Addon Allowlist**
- **Addon Blocklist**

### Quest text or objective progress is stale

Quest data can lag behind Blizzard API updates.

Try opening the quest log, changing tracking, or waiting for the next quest update event.

---

## Known Notes

- Some Blizzard quest/objective data is not immediately available at login or right after a quest state changes.
- Some guide addons expose richer metadata than others. AWP uses addon data first where reliable, then falls back to Blizzard APIs.
- The overlay's dynamic text sizing is limited by Blizzard font behavior and may not animate perfectly smoothly.
- Farstrider (needs FarstriderLibData), Mapzeroth, and Zygor routing depend on their addon being installed and enabled.

---

## Author

AzerothWaypoint is created and maintained by **MorningStarGG**.

- Twitch: [twitch.tv/MorningStarGG](https://www.twitch.tv/MorningStarGG)
- BattleTag: `MorningStar#1136`
- PayPal: [Donate via PayPal](https://paypal.me/TheThinkCritic)

---

## Contributing

Found a bug or have a feature request? Open an issue or submit a pull request. Contributions are welcome.

Good reports include:

- what you clicked or routed
- which guide addon was active
- current routing backend
- `/awp status`
- whether Tracker Viewer or Zygor native viewer hiding was enabled, if the issue involves Zygor display
- `/awp waytype`
- `/awp stepdebug` when guide routing is involved
- any Lua error stack

---

## License

*This addon is provided as-is under the GPL-3.0 [license](LICENSE). You are free to modify and distribute it according to your needs.*

---

**AI Disclaimer:** Parts of this was made with various AI tools to speed development time.
