# AzerothWaypoint

> A TomTom-powered navigation bridge, route planner, waypoint queue, and 3D world overlay for World of Warcraft. One navigation arrow. Smarter routes. Your favorite guides. A more connected World of Warcraft experience.

![](https://github.com/MorningStarGG/AzerothWaypoint/blob/main/media/banner.png?raw=true)
![Version](https://img.shields.io/badge/version-4.3.0-blue)
![Game](https://img.shields.io/badge/Clients-Retail%20%7C%20WoW%20Forever-orange)
![Required](https://img.shields.io/badge/Required-TomTom-red)
![License](https://img.shields.io/badge/license-GPL--3.0-green)

**Support development:** [Donate via PayPal](https://paypal.me/TheThinkCritic)

---

**AzerothWaypoint (AWP)** brings your quests, guide addons, map destinations, and custom waypoints together into one navigation experience. Follow smarter travel routes, organize multiple destinations, display guides directly in your objective tracker, and customize how navigation looks both on your screen and in the game world.

**TomTom is the only required addon.** Everything else is optional, so you can build the navigation experience that works best for you.

**Support development:** [Donate via PayPal](https://paypal.me/TheThinkCritic)

---

## Feature Highlights

- **Smart Travel Routing** — Find your way using flight paths, portals, boats, zeppelins, teleport spells, travel items, and supported walking routes.
- **Unified Navigation** — Follow quests, guide steps, map pins, rare spawns, and custom destinations using a single TomTom arrow.
- **Integrated Guide Viewers** — Display supported guides directly in your objective tracker, with guide controls, progress, tips, and optional action buttons.
- **3D World Navigation** — Follow in-world markers, destination plaques, and off-screen arrows that adapt to your destination.
- **Waypoint Queues** — Create, save, import, reorder, and switch between multiple sets of destinations without losing your progress.
- **Flight Map Assist** — Highlight the correct flight destination, browse available flights, save favorites, and optionally take matched flights automatically on Retail and WoW Forever.
- **Quest-Aware Guidance** — See relevant quest icons, objective progress, and destination information as you travel.
- **UI Style** — Match AWP to DaylightUI, Ellesmere UI, ElvUI, or GW2 UI, or customize its standalone appearance.
- **Settings Profiles** — Share settings between characters, back up your preferences, and import or export profiles across supported clients.

## Recent Additions

The latest features described here expand AWP beyond navigation into a more complete guide and questing experience:

- **QuestieRouter and QuestieDB (WoW Forever)** — QuestieRouter guide viewing, task selection, optional travel and terrain routing, and richer quest information from QuestieDB.
- **APR and WoWPro Tracker Viewers** — Both guides now have independent viewers, appearance settings, chat output, and guide controls.
- **Guide Actions** — Movable action panels and optional buttons beside guide steps make relevant items, spells, targets, and supported helpers easier to access.
- **Dugi Travel Routing** — Use Dugi's Taxi System as a travel planner for any supported destination, not just Dugi guide steps.
- **Expanded Walking Routes** — Follow supported roads and terrain paths through Mapzeroth, Polestar, and QuestieRouter on Forever.
- **Expanded UI Integrations** — Independent appearance matching, additional tracker hosts, improved plaque customization, and individual setting resets.

See `/awp changelog` for detailed release notes.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
- [Navigation and Routing](#navigation-and-routing)
- [Waypoint Queues](#waypoint-queues)
- [Quest and Map Navigation](#quest-and-map-navigation)
- [3D World Overlay and Arrow](#3d-world-overlay-and-arrow)
- [Flight Map Assist](#flight-map-assist)
- [Guide Integration](#guide-integration)
- [Tracker Viewer](#tracker-viewer)
- [Guide Actions](#guide-actions)
- [Appearance and Customization](#appearance-and-customization)
- [Supported Integrations](#supported-integrations)
- [Options and Profiles](#options-and-profiles)
- [Slash Commands](#slash-commands)
- [Troubleshooting](#troubleshooting)
- [Compatibility and Known Limitations](#compatibility-and-known-limitations)
- [Upgrading from ZygorWaypoint](#upgrading-from-zygorwaypoint)
- [Author](#author)
- [Contributing](#contributing)
- [License](#license)

---

## Quick Start

1. Install and enable **AzerothWaypoint** and **TomTom**.
2. Install any optional guide or travel addon you want to use.
3. Type `/awp options` to open settings.
4. Under **General > Routing Backend**, choose how AWP should plan your routes. TomTom Direct works without any additional integrations.
5. Select a supported quest, map destination, guide step, or TomTom waypoint and start navigating.

Want to display guides in your objective tracker? Open the guide's AWP settings page and enable **Tracker Viewer**.

Want to plan several destinations? Open the **Waypoint Queues** tab on the world map or type `/awp queue`.

The AWP minimap button gives you quick access to settings, help, queues, Search Nearby, and supported guide controls. You can keep it attached to the minimap, move it elsewhere, or hide it and use Blizzard's addon compartment instead.

## Installation

Download AzerothWaypoint and place its folder in the appropriate AddOns directory:

**Retail**

```text
World of Warcraft/_retail_/Interface/AddOns/AzerothWaypoint/
```

**WoW Forever**

```text
World of Warcraft/_forever_/Interface/AddOns/AzerothWaypoint/
```

Install TomTom, enable both addons, and restart the game or type `/reload`.

Optional integrations must be installed and enabled separately. Open `/awp options` and select **Integrations** to see supported addons, their current status, and available addon links.

---

## Navigation and Routing

AzerothWaypoint separates **where you want to go** from **how you get there**. Your destination can come from a guide, quest, map pin, waypoint queue, or another addon, while your chosen route planner determines the journey.

TomTom displays the navigation arrow, and AWP manages the route, contextual information, and optional world markers.

### Choose Your Route Planner

You do not have to use the route planner belonging to your active guide. For example, you can follow a RestedXP guide while using Zygor or Mapzeroth to plan your travel.

| Route planner | What it offers |
|---|---|
| **TomTom Direct** | Simple, direct navigation. Always available. |
| **Zygor / LibRover** | Travel-aware routes, transport connections, and rich flight-path information. |
| **Farstrider** | Routes using flights, portals, transports, spells, items, and travel nodes. Requires FarstriderLib and its data. |
| **Mapzeroth** | Travel-aware routing, supported walking paths, instance entrances, toys, and wearable teleport items. |
| **Polestar** | Forever travel planning with optional terrain-aware walking. |
| **Dugi** | Travel planning using Dugi's Taxi System and your existing Dugi travel preferences. |
| **QuestieRouter** | Forever travel planning with optional navigation packs for walking routes. |

Change your planner under **General > Routing Backend** at any time.

### Automatic Route Fallback

If your preferred planner cannot find a route, AWP tries other available planners before falling back to direct navigation. Your saved preference is not changed, and AWP attempts to return to it when appropriate.

The fallback priority is:

**Zygor → Farstrider → Mapzeroth → Polestar → Dugi → QuestieRouter → TomTom Direct**

Unavailable integrations are skipped. Existing guidance remains visible while a replacement route is calculated where possible. If you explicitly choose TomTom Direct, AWP keeps using direct navigation.

### Walking and Ground Routes

Supported planners can guide you along actual roads or terrain paths rather than pointing straight at the final destination.

- **Mapzeroth:** Follows supported roads and capital streets on Forever, and available walking data on Retail.
- **Polestar and QuestieRouter:** Offer optional terrain-aware walking on Forever when the appropriate navigation packs are installed.
- The arrow, world marker, and active map pin follow the current route point and advance as you travel.
- The original destination is preserved, including its quest information and arrival behavior.
- Areas without supported walking data fall back to ordinary navigation.

Configure walking preferences in the relevant planner. **General > Routing > Follow ground paths while flying** controls whether supported ground paths remain active during self-flight. This option is off by default, flight shortcuts depend on the planner and client. Forever currently uses ground and taxi guidance without self-flight shortcuts.

### Travel Actions

When a route requires a spell, hearthstone, toy, travel item, or another supported action, AWP can display a travel button in place of the normal arrow.

Supported wearable teleport items can be equipped, used, and restored as part of the travel action. Boats, airships, zeppelins, and other transport stops use relevant instructions and icons when available.

### Find Nearby Services

Supported guide integrations provide convenient searches for nearby services such as vendors, repair NPCs, auctioneers, bankers, mailboxes, profession trainers, and workshops.

`/awp search` tries ready Zygor, Dugi and Polestar integrations in **General > Guide Viewer Order**. The guide does not need to be active or have its Viewer enabled. The first matching result uses your selected AWP travel planner.

Open the minimap icon's **Search Nearby** submenu to browse the combined services your available providers support. Vendors, professions, classes, weapon masters and workshops have their own submenus where available. Each entry uses the same fallback as the command. Class choices include every class a provider can explicitly search, providers restricted to your own class are skipped for other classes. Use `/awp search help` for the current list.

```text
/awp search vendor
/awp search repair
/awp search auctioneer
/awp search mailbox
/awp search trainer blacksmithing
/awp search workshop engineering
```

General vendor searches include supported food/drink, poison, reagent and repair merchants. Use `/awp search food`, `/awp search drink`, `/awp search poison vendor` or `/awp search reagents` for that specific merchant category. A named profession or workshop requires a provider that identifies that service, a generic trainer is not a substitute. Each guide's Find Nearest menu remains tied to that guide.

---

## Waypoint Queues

Turn individual waypoints into organized, reusable destination lists.

Open the queue panel using `/awp queue` or the side tab on the world map.

### Queue Features

- Create and save multiple manual waypoint queues.
- Import TomTom waypoint batches, including `/ttpaste` lists.
- Add, remove, and reorder destinations.
- Activate or deactivate a queue without deleting it.
- View guide destinations alongside manual queues.
- Inspect queue details and focus the final destination on the world map.
- Delete individual queues or remove several at once.

Temporary destinations from supported external addons can take over navigation without deleting your saved queues.

### Choose What Happens When You Add a Waypoint

**General > Manual Click Queue Behavior** applies to supported map clicks, quest shortcuts, and individual TomTom `/way` commands.

| Mode | Behavior |
|---|---|
| **Create New Queue** | Create a separate queue for the new destination. |
| **Replace Active** | Replace the active queue. Imported and multi-stop queues are preserved by default. |
| **Append** | Add the destination to the active queue. |
| **Ask** | Choose what to do each time. |

You can also configure automatic waypoint clearing and the distance at which AWP considers a manual destination reached.

---

## Quest and Map Navigation

AWP can take supported destinations directly from Blizzard's map and quest interface and plan a route using your preferred travel addon.

Supported destinations include:

- Tracked and supertracked quests, quest pins, and user waypoints.
- World quests, area points of interest, and vignettes.
- Flight masters, dig sites, gossip locations, and housing plots where available.
- Waypoints from WorldQuestTab, HandyNotes, SilverDragon, and RareScanner.

### Quest-Aware Guidance

Quest destinations can display their current title, objective progress, relevant instructions, and quest-specific icons across the arrow, world markers, destination plaque, and queue.

Different quest types and states are visually distinguished, including available, incomplete, and completed quests, world quests, campaign quests, daily and weekly quests, and other supported categories.

Options are available to automatically route newly tracked quests and clear routes when quests are untracked or their configured arrival conditions are met.

### Quest information: QuestieDB and BtWQuests

On Forever, Questie and the separately installed **QuestieDB** can enrich ordinary quest destinations with localized NPC, object, and item information.

QuestieDB can provide this information even without Questie running or when a destination comes from another supported source. When the necessary information is unavailable, AWP retains normal quest guidance and respects explicitly selected coordinates.

On Retail and Forever, loaded **BtWQuests** quest packs can fill missing quest names, acceptance sources and known NPC/object names if QuestieDB is not installed/enabled. If neither are there AWP will show what information is available.

### Waypoints from Other Addons

Other addons that create standard TomTom or Blizzard waypoints may also work with AWP. Under **General > Addon Waypoint Adoption**, you can enable unknown-addon support, review detected callers, and manage allowed or blocked addons.

---

## 3D World Overlay and Arrow

AWP includes its own customizable 3D navigation overlay. No additional world-overlay addon is required.

| Overlay | What it shows |
|---|---|
| **Waypoint** | A long-range marker and optional beacon in the game world. |
| **Pinpoint** | A close-range destination marker with a plaque, contextual information, and arrival guidance. |
| **Navigator** | A directional indicator when the destination is outside your view. |

Markers adapt to quests, travel stops, guide instructions, services, and other destinations. Customize their size, opacity, colors, distance display, text, and appearance independently.

### Arrow Skins

Give TomTom a different look with built-in AWP skins:

**AWP, AWP Bomber, AWP Modern, Alliance, and Horde.**

Zygor users can also select **Starlight** and **Stealth**. AWP Modern is the default custom arrow skin.

Arrow size and travel-button size can be adjusted separately. AWP can also temporarily hide navigation elements during combat and restore them afterward.

---

## Flight Map Assist

AWP can highlight the flight destination needed for your current route when you speak to a flight master.

### Flight Destination Marker

The marker helps identify the correct flight path without changing your map tracking. Matching depends on the travel information provided by your selected planner.

### Flight List

An optional panel beside the flight map gives you access to:

- Your current route's flight destination.
- Searchable reachable destinations grouped by zone.
- Favorite and recently used flights.
- Flights within your current zone.
- Flight times from InFlight on both clients. On Forever, the list can also use DaylightUI, Farstrider or Ellesmere UI. A tilde (~) marks an estimate.

The panel can choose its side automatically, follow the flight map, and adjust its height. You can also customize destination text size.

### Automatic Flight Selection

| Mode | Behavior |
|---|---|
| **Disabled** | You choose flights manually. This is the default. |
| **Exact** | Automatically takes a flight when an exact supported taxi-node match is available. |
| **Strong** | Also allows reliable destination matches using map position and name. |

Both automatic modes wait until the route is ready for the flight and AWP confirms the departure flight master. AWP can highlight the destination so you can find and select the flight yourself.

Hold **Alt** to suppress automatic flight selection for the current flight-map interaction.

Configure these features under **General > Routing**.

---

## Guide Integration

Use your preferred leveling or questing guide with AWP's navigation, regardless of which supported route planner you choose.

| Guide | Retail | Forever | Optional travel planner |
|---|:---:|:---:|:---:|
| Zygor Guides Viewer | ✓ | ✓ | ✓ |
| Dugi Guides | ✓ | ✓ | ✓ |
| RestedXP Guides | ✓ | ✓ | — |
| Azeroth Pilot Reloaded (APR) | ✓ | ✓ | — |
| WoWPro | ✓ | ✓ | — |
| Polestar | — | ✓ | ✓ |
| QuestieRouter | — | ✓ | ✓ |

Support depends on compatible current addon releases and available game data.

Multiple guide addons can remain visible at the same time, but only one destination controls navigation at a time. A manual route or another guide can become active without deleting your existing guide progress.

### Zygor Guides Viewer

Zygor integration includes guide navigation, LibRover travel planning, service searches, optional chat instructions, guide switching, and Tracker Viewer support.

- Access native guide tabs, the guide chooser, goal checkoffs, and nearest-service searches.
- View supported quest explanations, buff, equipment, and quest actions.
- Configure travel route style inside Zygor.

If you prefer Zygor's original window, AWP also offers compact display and hover-based options. If you use Tracker Viewer instead, you can hide the original window while keeping the guide running.

### Dugi Guides

Follow Dugi guides using any available AWP route planner, or select **Dugi** to use its own Taxi System preferences.

Guide switching uses Dugi's numbered guide slots, with up to six managed slots available through AWP when needed with Kaliel's Tracker. Separate copies of a guide can occupy separate slots. Closing a slot does not delete guide progress.

Optional native-window hiding applies to Dugi's floating window, not its anchored mode.

### RestedXP Guides

AWP follows RestedXP's authored destinations, including guide-linked deathskip routes, while preserving its instructions and progress.

Access RestedXP's native chooser and settings, switch between up to six recently used guides, reload a guide, or jump to a step. Back can return to an earlier quest acceptance when appropriate, or let you choose a step if the intended recovery point is unclear.

RestedXP's own pause and completion behavior remain unchanged.

### Azeroth Pilot Reloaded (APR)

APR supports an independent Tracker Viewer, guide actions, chat instructions, and navigation through your chosen planner.

Next and the step checkbox use APR's native skip behavior, Back uses its undo feature. Route selection opens APR's own route browser.

### WoWPro

WoWPro supports an independent Tracker Viewer, guide actions, chat instructions, and remembered guide switching.

Back can reopen an earlier missing quest acceptance or ask you to choose an earlier step. Quest progress is rechecked, and skips that affect dependent steps retain their confirmation.

### Polestar (WoW Forever)

Polestar can provide guide destinations, travel planning, and optional terrain-aware walking independently of your active guide.

- Access native guide tabs, the guide chooser, step previews, goal checkoffs, and nearest-service searches.
- View supported quest explanations, buff, equipment, bank, and bag-space actions.
- Choose whether to do or skip an escort or group quest directly in Tracker Viewer. Escort notes and warnings about hard fights appear with the step.
- Configure travel routes, class teleports, walking paths, and route style inside Polestar.
- Follow terrain paths when the required navigation packs are installed.

AWP respects Polestar's travel restrictions during escorts and timed quests. Native bag-management confirmations remain in place.

Accept the **Let AWP Show Navigation** prompt if you want AWP to replace Polestar's navigation arrow. Its normal arrow preferences apply again when AWP routing is disabled.

### QuestieRouter (WoW Forever)

QuestieRouter provides a guide source, independent Tracker Viewer, and optional route planner.

Unlike linear guides, QuestieRouter organizes quests into tasks. Use **Choose Task** to select a specific task, **Return to Automatic Order** to resume its recommended ordering, or its native task menu to skip quests.

- Access native guide viewer, the guide chooser, step management, and nearest-service searches.
- View supported quest explanations, buff, equipment, and quest/step actions.
- Configure travel route style inside QuestieRouter.

The Viewer keeps individual quest progress visible within grouped tasks and supports an optional native guide banner. Up to six unique guides are remembered in its guide menus.

QuestieRouter's travel planner respects its own transport and walking preferences.

---

## Tracker Viewer

Display your supported guide directly inside your objective tracker instead of keeping a separate guide window open.

Each supported guide has its own optional Viewer and independent settings. Enable it from that guide's page in `/awp options`.

### Viewer Features

- Current guide title, instructions, objective progress, and grouped tips.
- Guide selection, step navigation, and native menus where supported.
- Sticky or along-the-way objectives displayed with the current instructions.
- Independent text colors and text sizes, progress-bar styles, and compact header options.
- **Hide Guide Addon Name** and **Hide Guide Title** keep Tracker Viewer headers compact. Both names stay available in tooltips.
- Optional local chat output when guide steps change.
- Optional hiding of the original guide window without stopping the guide.

Viewer controls follow the behavior of each guide. Not every guide supports the same step commands or navigation controls.

### Guide Text Colors and Sizes

Open the guide's **Tracker Viewer** settings to customize it independently.

**Tracker Viewer Text** offers Auto for consistent contextual colors across guides, UI colors for matching the selected UI style, or a chosen text color.

Enable **Use custom Viewer text sizes** to adjust headings, goals, notes/context and progress separately. Leave it disabled to keep your existing tracker or UI sizes. Your chosen font, outline and shadow stay the same, and the Viewer adjusts its layout to fit the text. These sizes are included in guide profile imports and exports.

### Supported Objective Trackers

AzerothWaypoint supports several objective trackers for displaying Guide Viewers. **Dedicated tracker integrations are recommended** to avoid the limitations of experimental Blizzard docking.

| Tracker | Availability | Docking Support | Notes |
|---|---|---|---|
| **Kaliel's Tracker** | Retail / Forever | Dedicated | Automatically preferred when available. |
| **Ellesmere UI Quest Tracker** | Retail / Forever | Dedicated (Forever only) | Uses experimental Blizzard docking on Retail or when the custom tracker is disabled. |
| **DaylightUI Quests** | Forever | Dedicated | Guides share the tracker alongside native quest sections. |
| **Questie Tracker** | Forever | Dedicated | Guides appear above quests in the shared scroll area. |
| **GW2 UI Tracker** | Retail / Forever | Dedicated | Guides share the custom tracker's scroll area above quests. |
| **Blizzard Objective Tracker** | Retail / Forever | Experimental | No additional tracker addon required. |

When using a shared scrolling tracker, scroll back up to return to your guides. Questie users can enable **Always Show Tracker** to keep Guide Viewers visible when no quests are tracked.

> **Compatibility warning:** Experimental Blizzard docking can cause blocked actions or other UI errors. For the best experience, use a tracker with dedicated docking support. See [Compatibility and Known Limitations](#compatibility-and-known-limitations).

### Guide Chat Output

Guide instructions can be printed automatically when the active step changes or manually through the guide's named slash commands. Output is visible only in your own chat frame.

Choose whether sticky objectives are omitted, summarized by count, or listed by title. Use `output full` for expanded instructions and `output sticky` for sticky objectives only, where supported.

---

## Guide Actions

Supported guide actions can be displayed in AWP so you don't have to switch back to the original guide window whenever a step requires an item, spell, target, or helper action.

Each guide has independent **Guide Actions** settings:

- A movable action panel with its own saved position.
- Optional action buttons beside matching guide steps.
- Filters for the types of actions displayed.
- Optional hiding of the original guide's action controls.

The panel, inline buttons, and native-control hiding are opt-in. Inventory Cleanup is also disabled by default.

Guide actions retain their original confirmations and restrictions. Standard prepared actions remain usable according to WoW's combat rules, while some native helper actions are available only outside combat. If a guide changes during combat, prepared buttons retain their previous action until they can safely update.

**Note:** Hiding native action controls while both AWP action displays are disabled can leave you without visible action buttons. Guide actions are separate from the navigation travel button.

---

## Appearance and Customization

Customize AWP on its own or match it to your existing UI addon. Appearance settings are independent of guide selection, travel routing, and tracker hosting.

### UI Styles

| UI addon | Retail | Forever | Requirements |
|---|:---:|:---:|---|
| **AWP** | ✓ | ✓ | Built-in appearance, no additional addon. |
| **DaylightUI** | — | ✓ | DaylightUI core for appearance, DaylightUI_Quests for tracker hosting. |
| **Ellesmere UI** | ✓ | ✓ | Blizzard Skins+ and its enabled AzerothWaypoint skin. |
| **ElvUI** | ✓ | ✓ | ElvUI, no additional skin plugin required. |
| **GW2 UI** | ✓ | ✓ | GW2 UI, enable its tracker separately for Viewer docking. |

Select **General > UI Style** to choose a style. Automatic is the default: AWP uses the only available supported style, or asks you to choose if more than one is available.

Choose **AWP** at any time to return to the built-in appearance. Switching providers preserves your previous customization settings. If an explicitly selected UI addon becomes unavailable, AWP uses its built-in appearance and offers available alternatives.

### Customize Individual Elements

Appearance settings can be adjusted separately for supported elements, including guide Viewers and action panels, destination plaques, navigation labels, travel controls, and AWP windows.

Depending on the selected provider and element, options include fonts, text size, outlines, colors, progress bars, buttons, panel backgrounds, and borders. For guide text, Auto preserves contextual colors even with UI text matching enabled. Select UI colors to use the UI style's text colors. Other supported semantic color-matching options remain separate.

You can manage supported appearance settings from AWP or the AzerothWaypoint section of your UI addon's own settings. Both edit the same preferences.

### Pinpoint Plaques

Choose from several destination plaque styles, including:

**Minimal, Forever, Blizzard, Classic, Clean, Modern, Fantasy, Glowing Gems, Horde, Alliance, Future, and Steampunk.**

All built-in styles work without an appearance addon. Supported styles offer separate background and border opacity, with adjustable border thickness for Minimal, Clean, and Modern. Each style remembers its own adjustments.

The default plaque is **Blizzard** on Retail and **Forever** on WoW Forever. A selected UI style can also style the plaque while retaining your navigation information.

---

## Supported Integrations

AWP works independently with TomTom, and optional addons expand what it can do.

| Category | Supported addons and sources |
|---|---|
| **Required** | TomTom |
| **Guides** | Zygor, Dugi, RestedXP, APR, WoWPro, Polestar (Forever), QuestieRouter (Forever) |
| **Travel planning** | Zygor / LibRover, FarstriderLib / FarstriderLibData, Mapzeroth, Dugi, Polestar (Forever), QuestieRouter (Forever) |
| **Quest information** | Blizzard quest data, QuestieDB (Forever), then loaded BtWQuests packs (both clients) |
| **Map and rare waypoints** | WorldQuestTab, HandyNotes and supported plugins, SilverDragon, RareScanner |
| **Flight timing** | InFlight (both clients), DaylightUI, FarstriderLib Data and Ellesmere UI (Forever) |
| **Objective trackers** | Kaliel's Tracker, Blizzard, Ellesmere UI, DaylightUI, Questie, GW2 UI, subject to client availability |
| **Appearance** | DaylightUI (Forever), Ellesmere UI, ElvUI, GW2 UI |

See the in-game **Integrations** page for detected addon status and available links. Not every feature or optional addon is available on both clients.

---

## Options and Profiles

Open settings with `/awp options`, `/awp config`, or `/awp settings`. You can also use **Game Menu > Options > AddOns > AzerothWaypoint**, the minimap menu, or the supported UI addon's AWP settings shortcut.

### Settings Overview

| Section | Customize |
|---|---|
| **General** | Travel planner, UI Style, queue behavior, quest routing, flight assist, external waypoints, minimap button, and combat visibility. |
| **TomTom Arrow** | Arrow skins, arrow size, and travel-button size. |
| **World Overlay** | Overlay visibility, hover fading, context display, and shared colors. |
| **Waypoint** | Long-range markers, beacons, distance units, size, opacity, and footer text. |
| **Pinpoint** | Arrival distance, plaque style, destination information, effects, size, height, and colors. |
| **Navigator** | Off-screen arrows, size, opacity, distance, and colors. |
| **Guide settings** | Independent Tracker Viewers, guide actions, chat output, and native window controls. |
| **Appearance settings** | Matching and customization for the selected UI provider. |
| **Profiles** | Character and account settings, importing, exporting, and duplication. |

Individual value controls include **Reset** buttons to restore their default values. In-game Help, Release Notes, and Integrations provide additional information without leaving the game. Follow links in Help to jump to related topics and sections.

### Settings Profiles

Create profiles, duplicate existing settings, choose an account-wide default, or assign a different profile to a character. Existing settings become the Default profile.

Use **Export** to create a shareable profile string. **Import** previews differences and unavailable integrations before you save the imported settings as a new profile or replace an existing one. Changing active settings reloads the UI.

Profiles can be shared across Retail and Forever. They include navigation preferences, appearance, Guide Viewer and action settings (including custom Viewer text sizes), and AWP window positions. Waypoint queues, guide progress, guide tabs, flight history, and other addons' settings remain with their original installation.

---

## Slash Commands

Most features are available through the settings window and minimap menu. Slash commands are useful for quick access, macros, and troubleshooting.

### Common Commands

| Command | Description |
|---|---|
| `/awp` | Main addon command. |
| `/awp options` | Open settings (`config` and `settings` also work). |
| `/awp help` | Open in-game help. |
| `/awp changelog` | View release notes. |
| `/awp status` | Show routing, integration, and addon status. |
| `/awp queue` | Open Waypoint Queues. |
| `/awp routing on\|off\|toggle` | Enable or disable AWP routing. |
| `/awp backend <name>` | Select a travel planner. |
| `/awp repair` | Repair required TomTom/Zygor settings. |
| `/awp skin <skin>` | Select an arrow skin. |
| `/awp scale <0.60-2.00>` | Adjust custom arrow size. |
| `/awp minimap show\|hide\|toggle\|reset\|status` | Manage the minimap button. |

Documented planner names include `direct`, `zygor`, `farstrider`, `mapzeroth`, `dugi`, and `polestar`. QuestieRouter can be selected from settings on Forever when available.

<details>

<summary><strong>Waypoint and quest commands</strong></summary>

```text
/awp queue list
/awp queue use <id|index>
/awp queue clear [id|index]
/awp queue remove <id|index> <item>
/awp queue move <id|index> <from> <to>
/awp queue import
/awp manualclear on|off|toggle
/awp cleardistance <5-100>
/awp trackroute on|off|toggle
/awp untrackclear on|off|toggle
/awp questclear on|off|toggle
/awp addontakeover on|off|toggle|status
```

Queue aliases include `queues`, `queue open`, `queue show`, `queue ls`, `queue rm`, `queue paste`, and `queue ttpaste`.

</details>

<details>

<summary><strong>Guide commands</strong></summary>

Use a named guide provider to control its guide, even when its Tracker Viewer is disabled.

```text
/awp zygor help
/awp dugi help
/awp rxp help
/awp polestar help
/awp apr help
/awp wowpro help
```

Examples:

```text
/awp dugi next
/awp dugi prev
/awp rxp active
/awp polestar route
/awp dugi list
/awp dugi switch 2
/awp rxp load <group||name or unique exact title>
/awp dugi close current
/awp rxp output full
/awp rxp output sticky
/awp dugi viewer on
/awp dugi native hide
/awp rxp reset
```

Available actions vary by provider and include `next`, `prev`, `skip`, `complete`, `active`, `route`, `reload`, `picker`, `load`, `menu`, `settings`, `list`, `switch`, `close`, `output`, `status`, `reset`, `viewer`, and `native`.

Use the provider's `help` command for supported arguments. Refresh the guide list before selecting an index if guides have changed. Loading and switching follow native guide progress restoration. Reset restores supported guide window visibility and position, it does not reset guide progress or profiles.

Zygor command examples:

```text
/awp zygor compact on|off|toggle|status
/awp zygor viewer on|off|toggle|status
/awp zygor native show|hide|toggle|status
/awp zygor load <guide title> [step N]
/awp zygor close [current|index|all]
```

</details>

<details>

<summary><strong>Flight Map Assist commands (Retail and Forever)</strong></summary>

```text
/awp flightassist marker on|off|toggle|status
/awp flightassist auto disabled|exact|strong|status
/awp flightassist catalog on|off|toggle|reset|status
```

Resetting the flight list restores its side and open state without clearing favorites or recent flights.

</details>

<details>

<summary><strong>Service search commands</strong></summary>

```text
/awp search vendor
/awp search repair
/awp search auctioneer
/awp search banker
/awp search mailbox
/awp search trainer alchemy
/awp search workshop blacksmithing
```

Additional supported services include barbers, flight masters, innkeepers, riding trainers, stable masters, transmogrifiers, and void storage.

Common aliases include `ah`, `auction`, `bank`, `inn`, `mail`, `mog`, `tmog`, `store`, and `stables`.

</details>

<details>

<summary><strong>Diagnostic commands</strong></summary>

```text
/awp status
/awp waytype
/awp stepdebug
/awp churn 30
/awp mem
```

These commands help diagnose routing, guide, tracker, and performance issues.

</details>

---

## Troubleshooting

### The navigation arrow is missing

Make sure TomTom and AWP are installed and enabled. Check whether routing is enabled and whether combat visibility settings are hiding the arrow.

```text
/awp status
/awp repair
/reload
```

### Two navigation arrows are showing

AWP can recommend disabling a guide addon's competing arrow. Accept the recommendation if you want to use TomTom as your only navigation arrow. AWP does not silently change these guide preferences.

For Zygor, you can also open `/zygor options` and disable **Waypoint Arrow > Enable Waypoint Arrow**.

### A guide is visible but isn't controlling navigation

Another guide, quest, or manual queue may currently be active. Select the intended guide using its controls or activate the desired queue from Waypoint Queues. Other visible guides retain their progress.

### Tracker Viewer is missing

Check that the guide addon is installed and loaded, its **Tracker Viewer** option is enabled in AWP, and the objective tracker is visible.

On Forever with Questie, enable **Always Show Tracker**. Use `/awp status` to check which tracker AWP detected and whether it appears hidden or transparent.

### Imported waypoints aren't appearing in a queue

Open `/awp queue` and check `/awp status`.

### Another addon's waypoints are being ignored

Check **General > Addon Waypoint Adoption**, including the detected caller list, allowlist, and blocklist.

### Quest information hasn't updated

Quest information may take a moment to become available after login or a quest change. Try opening the quest log, changing quest tracking, or waiting for the next quest update.

### Appearance matching isn't working

Check that your chosen appearance addon and any required modules are enabled. Verify **General > UI Style** and use `/awp status` to check the selected and currently applied appearance.

---

## Compatibility and Known Limitations

- **Blizzard tracker docking:** Experimental on both clients. It can cause protected-action or secret-value errors due to Blizzard's shared tracker and world map code. Future game updates may break this feature or require its removal. The native-docking warning can be restored under **Zygor > Tracker Viewer > Show Native Docking Warning Popup**. See [Supported Objective Trackers](#supported-objective-trackers) for custom tracker options.
- **Addon compatibility:** Integrations target current supported addon releases. Mapzeroth does not provide a supported public integration API, if its required functionality changes, AWP falls back to another available planner. Farstrider requires its data library.
- **Travel availability:** A calculated route cannot guarantee that every connection is usable in your character's current phase or circumstances.
- **Walking coverage:** Mapzeroth road paths are not a complete terrain or floor navigation system. Polestar and QuestieRouter terrain guidance requires compatible navigation packs and map coverage.
- **Combat restrictions:** Some guide actions, layout changes, routing updates, and appearance changes must wait until combat or other protected game transitions finish.
- **Quest information:** Available detail varies by client, guide addon, and quest data. AWP uses normal guidance when richer information is unavailable.
- **Overlay text:** Dynamic text resizing is subject to Blizzard's font-rendering limitations.
- **Optional features:** Tracker Viewers, guide chat output, and native guide-window hiding are optional. QuestieRouter, Polestar, and DaylightUI are currently Forever integrations.

<details>

<summary><strong>Advanced integration behavior</strong></summary>

- Preferred-planner recovery can be requested after moving 100 yards while using a fallback, with retry delays of 10, 20, 40, and 60 seconds. Confirmed travel transitions, map changes, and travel-capability changes can bypass the delay. Ordinary inventory and cooldown updates do not.
- Dugi's native duplicate travel searches are bypassed while AWP routing is enabled. The Dugi backend follows the existing Taxi System setting and respects direct navigation when it is disabled.
- Polestar retains its native route-line appearance, AWP follows the current route point without adding a separate map-line renderer. Its native follower integration prevents competing navigation while AWP routing is active.
- Native guide-window hiding leaves guide engines running. AWP does not automatically enable native helper bars, alter guide completion flags, or reset guide progress.
- Only one UI Style can style AWP at a time. Tracker hosting is selected separately. ElvUI uses Blizzard's tracker and therefore shares its native docking limitation.
- With GW2 UI's map skin, Waypoint Queues opens beside the map when space permits, or over its canvas on narrower layouts while preserving access to the quest pane.
- The original Default plaque identity has been retired in favor of client-specific defaults. Fantasy and Future preserve the earlier illustrated and image-based designs respectively. Valid saved style choices remain intact.

</details>

---

## Upgrading from ZygorWaypoint

AzerothWaypoint is the renamed and expanded successor to **ZygorWaypoint**. It no longer requires Zygor and supports multiple guides, travel planners, and waypoint sources.

TomTom is the only required dependency. Existing AWP settings become the Default profile when profiles are introduced. Recognized queues, guide state, positions, and preferences are retained during normal settings cleanup, obsolete settings are removed.

---

## Author

AzerothWaypoint is created and maintained by **MorningStarGG**.

- Twitch: [twitch.tv/MorningStarGG](https://www.twitch.tv/MorningStarGG)
- BattleTag: `MorningStar#1136`
- PayPal: [Support development](https://paypal.me/TheThinkCritic)

## Contributing

Found a bug, have a suggestion, or want to contribute? Open an issue or submit a pull request.

Helpful bug reports include your game client, the active guide and route planner, what you were trying to do, and the output of `/awp status`. For guide or navigation issues, include `/awp stepdebug` and `/awp waytype` where relevant. For display issues, include your tracker and appearance settings. Include any Lua errors and steps to reproduce the problem.

## License

AzerothWaypoint is provided as-is under the [GPL-3.0 license](LICENSE).

**AI Disclaimer:** Parts of this addon were developed with the assistance of AI tools to help accelerate development.
