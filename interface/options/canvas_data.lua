-- ============================================================
-- Settings catalog
-- ============================================================
--
-- Defines the settings catalog used by the sidebar, previews, search and
-- guide-specific settings pages.

local NS = _G.AzerothWaypointNS
local C = NS.Constants

NS.Internal.Interface = NS.Internal.Interface or {}
NS.Internal.Interface.canvas = NS.Internal.Interface.canvas or {}

local M = NS.Internal.Interface.canvas
local Data = {}
M.Data = Data

local MEDIA_HELP = "Interface\\AddOns\\AzerothWaypoint\\media\\help\\"

Data.MEDIA_HELP = MEDIA_HELP
Data.ICON_PATH = "Interface\\AddOns\\AzerothWaypoint\\media\\icon.png"

Data.PREVIEW_IMAGE_SIZES = {
    [MEDIA_HELP .. "MainShot.tga"] = { w = 700, h = 389 },
    [MEDIA_HELP .. "ProfilesOverview.tga"] = { w = 411, h = 356 },
    [MEDIA_HELP .. "Starlight.tga"] = { w = 330, h = 150 },
    [MEDIA_HELP .. "Stealth.tga"] = { w = 330, h = 150 },
    [MEDIA_HELP .. "Waypoint.tga"] = { w = 353, h = 350 },
    [MEDIA_HELP .. "Navigator.tga"] = { w = 360, h = 235 },

    [MEDIA_HELP .. "Normal.tga"] = { w = 330, h = 120 },
    [MEDIA_HELP .. "MinimalMode.tga"] = { w = 330, h = 120 },
    [MEDIA_HELP .. "MinimalModeHideBG.tga"] = { w = 330, h = 120 },
    [MEDIA_HELP .. "MinimalModeHideBGColors.tga"] = { w = 330, h = 120 },

    [MEDIA_HELP .. "Pinpoint.tga"] = { w = 350, h = 267 },
    [MEDIA_HELP .. "PinpointPlaqueOff.tga"] = { w = 350, h = 267 },
    [MEDIA_HELP .. "PinpointOff.tga"] = { w = 350, h = 267 },

    [MEDIA_HELP .. "FullContext.tga"] = { w = 250, h = 129 },
    [MEDIA_HELP .. "IconOnly.tga"] = { w = 250, h = 129 },
    [MEDIA_HELP .. "ContextHidden.tga"] = { w = 250, h = 129 },

    [MEDIA_HELP .. "Beacon.tga"] = { w = 250, h = 171 },
    [MEDIA_HELP .. "BeaconOff.tga"] = { w = 250, h = 171 },
    [MEDIA_HELP .. "BaseOnly.tga"] = { w = 250, h = 171 },


    [MEDIA_HELP .. "ManualQueueAsk.tga"] = { w = 590, h = 236 },
    [MEDIA_HELP .. "TravelButton.tga"] = { w = 297, h = 102 },
    [MEDIA_HELP .. "AWP.tga"] = { w = 191, h = 266 },
    [MEDIA_HELP .. "AWPBomber.tga"] = { w = 192, h = 266 },
    [MEDIA_HELP .. "AWPModern.tga"] = { w = 192, h = 308 },
    [MEDIA_HELP .. "Alliance.tga"] = { w = 192, h = 302 },
    [MEDIA_HELP .. "Horde.tga"] = { w = 192, h = 302 },
    [MEDIA_HELP .. "Overlay.tga"] = { w = 782, h = 782 },
    [MEDIA_HELP .. "OverlayFade.tga"] = { w = 782, h = 782 },

    [MEDIA_HELP .. "WaypointFooterAll.tga"] = { w = 344, h = 207 },
    [MEDIA_HELP .. "WaypointFooterNone.tga"] = { w = 344, h = 207 },
    [MEDIA_HELP .. "WaypointFooterDestinationName.tga"] = { w = 344, h = 207 },
    [MEDIA_HELP .. "WaypointFooterArrivalTime.tga"] = { w = 344, h = 207 },
    [MEDIA_HELP .. "WaypointFooterDistance.tga"] = { w = 344, h = 207 },


    [MEDIA_HELP .. "TrackerViewer.tga"] = { w = 416, h = 253 },
    [MEDIA_HELP .. "TrackerViewerMulti.tga"] = { w = 303, h = 684 },
    [MEDIA_HELP .. "QuestieRouterViewer.tga"] = { w = 313, h = 562 },
    [MEDIA_HELP .. "QuestieRouterBanner.tga"] = { w = 321, h = 120 },
    [MEDIA_HELP .. "GuideActionsPanel.tga"] = { w = 158, h = 88 },
    [MEDIA_HELP .. "TrackerRoundedBorder.tga"] = { w = 394, h = 31 },
    [MEDIA_HELP .. "TrackerSquareBorder.tga"] = { w = 394, h = 31 },
    [MEDIA_HELP .. "TrackerNoProgress.tga"] = { w = 394, h = 31 },
    [MEDIA_HELP .. "TrackerAutoColor.tga"] = { w = 416, h = 159 },
    [MEDIA_HELP .. "TrackerWhiteColor.tga"] = { w = 416, h = 159 },

    [MEDIA_HELP .. "MinimapButton.tga"] = { w = 484, h = 433 },

    [MEDIA_HELP .. "ChatCountTitles.tga"] = { w = 587, h = 251 },
    [MEDIA_HELP .. "ChatStickyDisabled.tga"] = { w = 587, h = 149 },
    [MEDIA_HELP .. "ChatCountOnly.tga"] = { w = 587, h = 199 },
    [MEDIA_HELP .. "ChatColorWhite.tga"] = { w = 587, h = 251 },

    [MEDIA_HELP .. "FlightHighlight.tga"] = { w = 259, h = 384 },
    [MEDIA_HELP .. "TaxiList.tga"] = { w = 423, h = 341 },

}

Data.TWITCH_URL = "https://www.twitch.tv/MorningStarGG"
Data.ABOUT_SUMMARY =
"One navigation arrow for quests, guides, map pins and personal waypoints."
Data.ABOUT_DESCRIPTION = table.concat({
    "Follow quests and guides, find nearby services, organize waypoint queues and see your next destination in the game world.",
    "",
    "TomTom is the only required addon. Optional integrations add travel planning, guide Viewers, action buttons and UI appearance matching. Save and share settings with Profiles.",
}, "\n")

Data.SECTION_DEFS = {
    { key = "about",     label = "About",         image = MEDIA_HELP .. "MainShot.tga",  desc = Data.ABOUT_SUMMARY },
    { key = "general",   label = "General",       image = MEDIA_HELP .. "MainShot.tga",  desc = "Route planning, flight assistance, waypoint queues, quest tracking, guide order and UI Style." },
    { key = "profiles",  label = "Profiles",      image = MEDIA_HELP .. "ProfilesOverview.tga", desc = "Create, switch, back up and selectively import settings profiles." },
    { key = "tomtom",    label = "TomTom Arrow",  image = MEDIA_HELP .. "Starlight.tga", desc = "Choose an arrow style and adjust arrow and travel button sizes." },
    { key = "overlay",   label = "World Overlay", image = MEDIA_HELP .. "Overlay.tga",   desc = "3D overlay visibility, fade behavior, and context display.", hasChildren = true, defaultExpanded = true },
    { key = "waypoint",  label = "Waypoint",      image = MEDIA_HELP .. "Waypoint.tga",  desc = "Long-range waypoint size, opacity, beacon, and footer text.",     parent = "overlay" },
    { key = "pinpoint",  label = "Pinpoint",      image = MEDIA_HELP .. "Pinpoint.tga",  desc = "Close-range marker, plaque style, arrows, and arrival behavior.", parent = "overlay" },
    { key = "navigator", label = "Navigator",     image = MEDIA_HELP .. "Navigator.tga", desc = "Off-screen destination arrow.",                                   parent = "overlay" },
}
if NS.IsWoWForever and NS.IsWoWForever() then
    table.insert(Data.SECTION_DEFS, 4, { key = "controller", label = "Controller", image = MEDIA_HELP .. "TrackerViewer.tga",
        desc = "Forever controller navigation, guide actions, optional bindings and diagnostics." })
end

Data.ZYGOR_SECTION = {
    key = "zygor",
    label = "Zygor",
    image = MEDIA_HELP .. "Normal.tga",
    desc =
    "Settings for optional Zygor Guides integration, compact guide display, tracker viewer UI, and chat step display.",
}

Data.DUGI_SECTION = {
    key = "dugi",
    label = "Dugi",
    image = MEDIA_HELP .. "TrackerViewer.tga",
    desc = "Dugi guide targets, optional travel planning, Tracker Viewer, and local chat controls (/awp dugi help).",
}

Data.POLESTAR_SECTION = {
    key = "polestar", label = "Polestar", image = MEDIA_HELP .. "TrackerViewerMulti.tga",
    desc = "Polestar guide routing, independent Tracker Viewer and native-configured travel/walking on WoW Forever.",
}

Data.RXP_SECTION = {
    key = "rxp", label = "RestedXP Guides", image = MEDIA_HELP .. "TrackerViewer.tga",
    desc = "RestedXP guide routing, Tracker Viewer, native guide cloaking and chat output.",
}

Data.GUIDE_SECTIONS = { zygor = Data.ZYGOR_SECTION, dugi = Data.DUGI_SECTION,
    rxp = Data.RXP_SECTION, polestar = Data.POLESTAR_SECTION,
    questierouter = { key = "questierouter", label = "QuestieRouter", image = MEDIA_HELP .. "QuestieRouterViewer.tga",
        desc = "QuestieRouter task navigation, independent Tracker Viewer and optional route planning on WoW Forever." } }
for _, definition in ipairs(C.GUIDE_PROVIDERS) do
    if not Data.GUIDE_SECTIONS[definition.key] then
        Data.GUIDE_SECTIONS[definition.key] = { key = definition.key, label = definition.label,
            image = MEDIA_HELP .. "TrackerViewer.tga",
            desc = definition.title .. " guide targets, independent Tracker Viewer, native controls, guide actions and chat output." }
    end
end

Data.GUIDE_PAGES = {
    { id = "viewer", label = "Tracker Viewer", desc = "Dock the Viewer and configure its header, progress and step text." },
    { id = "actions", label = "Guide Actions", desc = "Configure the movable panel, inline buttons, and action filters." },
    { id = "chat", label = "Chat Output", desc = "Configure local guide step announcements and sticky summaries." },
}
for _, section in pairs(Data.GUIDE_SECTIONS) do section.hasChildren = true end

local appearancePages = {
    { id = "viewers", label = "Guide Viewers", picker = "Guide", desc = "Style each guide's Tracker Viewer independently." },
    { id = "overlay", label = "World Overlay", picker = "Area", desc = "Style the plaque, navigation labels, or travel action controls." },
    { id = "windows", label = "AWP Windows", picker = "Area", desc = "Style AWP's options, queue, Taxi List, help, or settings search." },
}

-- ============================================================
-- Sidebar sections
-- ============================================================

function Data.BuildSections()
    local sections, byKey = {}, {}
    local function Add(section)
        sections[#sections + 1], byKey[section.key] = section, section
    end
    for _, section in ipairs(Data.SECTION_DEFS) do Add(section) end
    for _, definition in ipairs(C.GUIDE_PROVIDERS) do
        local provider = NS.GetGuideTargetProvider(definition.key)
        if provider and (not definition.forever or NS.IsWoWForever()) and provider.isLoaded() then
            local root = Data.GUIDE_SECTIONS[definition.key]
            Add(root)
            for _, page in ipairs(Data.GUIDE_PAGES) do
                Add({ key = root.key .. "." .. page.id, parent = root.key, label = page.label,
                    image = MEDIA_HELP .. (page.id == "actions" and "GuideActionsPanel.tga" or "TrackerViewer.tga"),
                    desc = page.desc })
            end
        end
    end
    for _, provider in ipairs(NS.Internal.Appearance.GetProviders()) do
        local options = provider.options
        if options and options.available() then
            Add({ key = provider.id, label = options.label, desc = options.desc, provider = provider, hasChildren = true })
            local pages = {}
            for _, page in ipairs(appearancePages) do
                local section = { key = provider.id .. "." .. page.id, parent = provider.id, label = page.label,
                    desc = page.desc, picker = page.picker, provider = provider, choices = {}, surfaces = {} }
                Add(section)
                pages[page.id] = section
            end
            for _, surface in ipairs(provider.GetOptionSurfaces()) do
                if not surface.forever or NS.IsWoWForever() then
                    local section = pages[surface.page]
                    local label = surface.guide and surface.tab or surface.label
                    local choices = section.choices
                    choices[#choices + 1] = { value = surface.key, text = label }
                    section.surfaces[surface.key] = label
                    if not section.defaultSurface and (not surface.guide or byKey[surface.key:sub(7)]) then
                        section.defaultSurface = surface.key
                    end
                end
            end
            if not pages.viewers.defaultSurface then pages.viewers.defaultSurface = pages.viewers.choices[1].value end
        end
    end
    return sections, byKey
end


Data.OPTION_PREVIEWS = {
    ["Show QuestieRouter Banner"] = {
        image = MEDIA_HELP .. "QuestieRouterBanner.tga",
        desc = "Show the zone artwork, guide title and quest progress above QuestieRouter's current task.",
    },
    ["Enable Guide Action Panel"] = {
        image = MEDIA_HELP .. "GuideActionsPanel.tga",
        desc = "Move the panel by dragging its title bar. Each guide remembers its own position.",
    },
    ["Hide Dugi Native Guide Frame"] = {
        image = MEDIA_HELP .. "TrackerViewer.tga",
        desc = "Hides Dugi's floating guide frame and its companion model viewer. Dugi's Anchored Small Frame must be disabled first.",
    },
    ["Use Custom Arrow Skin"] = {
        image = MEDIA_HELP .. "Stealth.tga",
        desc = "Use a custom skin in place of TomTom's default Crazy Arrow art.",
    },
    ["Arrow Skin"] = {
        image = MEDIA_HELP .. "Starlight.tga",
        desc = "Registered skins appear here automatically, including Zygor skins when Zygor is loaded.",
    },
    ["Hide During Combat"] = {
        image = MEDIA_HELP .. "Overlay.tga",
        desc = "Temporarily hides selected navigation displays while you are in combat, then restores them afterward.",
    },
    ["Quick-Start Popup"] = {
        image = MEDIA_HELP .. "MainShot.tga",
        desc = "Controls whether quick-start guide opens automatically on login.",
    },
    ["What's New Popup"] = {
        image = MEDIA_HELP .. "MainShot.tga",
        desc = "Controls whether What's New opens automatically on login after addon updates.",
    },
    ["Enable 3D World Overlay"] = {
        image = MEDIA_HELP .. "Overlay.tga",
        desc = "Shows active destinations as in-world markers.",
    },
    ["Fade on Hover"] = {
        image = MEDIA_HELP .. "OverlayFade.tga",
        desc = "Fades the overlay while the mouse is over it.",
    },
    ["Waypoint"] = {
        image = MEDIA_HELP .. "Waypoint.tga",
        desc = "Waypoint controls affect the long-range in-world destination marker.",
    },
    ["Pinpoint Mode"] = {
        image = MEDIA_HELP .. "Pinpoint.tga",
        desc = "Pinpoint controls affect the close-range destination display.",
    },
    ["Plaque Style"] = {
        image = MEDIA_HELP .. "Pinpoint.tga",
        desc = "Plaques frame close-range destination text and quest context. Standalone styles work on both clients; active appearance-shell matching overrides the selected artwork.",
    },
    ["Enable Navigator"] = {
        image = MEDIA_HELP .. "Navigator.tga",
        desc = "The navigator arrow appears when the target is outside the camera view.",
    },
    ["Manual Click Queue Behavior"] = {
        image = MEDIA_HELP .. "ManualQueueAsk.tga",
        desc = "Choose whether manual map clicks create, replace, append, or prompt.",
    },
    ["Special Travel Button Scale"] = {
        image = MEDIA_HELP .. "TravelButton.tga",
        desc =
        "Scales the special travel action button shown for hearthstones, items, spells, and other travel actions.",
    },
    ["Show Flight Map Route Marker"] = {
        image = MEDIA_HELP .. "FlightHighlight.tga",
        desc =
        "Marks the route flight path destination on the flight map when the active route uses a taxi.",
    },
    ["Auto Take Flight Paths"] = {
        image = MEDIA_HELP .. "FlightHighlight.tga",
        desc =
        "Automatically takes flight paths from the flight map. Hold Alt to skip.",
    },
    ["Show Flight Map Taxi List"] = {
        image = MEDIA_HELP .. "TaxiList.tga",
        desc =
        "Shows an AWP taxi list attached to the flight map with favorites, recent flights, current-zone flights, search, and reachable destinations.",
    },
    ["Flight Map Taxi List Side"] = {
        image = MEDIA_HELP .. "TaxiList.tga",
        desc = "Chooses which side of the flight map the AWP taxi list attaches to.",
    },
    ["Flight Map Taxi List Text Size"] = {
        image = MEDIA_HELP .. "TaxiList.tga",
        desc = "Adjusts text size in the attached flight map taxi list.",
    },
    ["Show Minimap Button"] = {
        image = MEDIA_HELP .. "MinimapButton.tga",
        desc = "Shows the AzerothWaypoint minimap button.",
    },
    ["Show Only Guide Steps Until Mouseover"] = {
        image = MEDIA_HELP .. "MinimalMode.tga",
        desc = "Compacts the Zygor guide frame until you mouse over it.",
    },
    ["Show Native Docking Warning Popup"] = {
        image = MEDIA_HELP .. "TrackerViewer.tga",
        desc =
        "Shows the native-docking risk warning after login or reload when Tracker Viewer attaches to Blizzard's objective tracker.",
    },
    ["Tracker Viewer Progress Bar"] = {
        image = MEDIA_HELP .. "TrackerRoundedBorder.tga",
        desc = "Choose square, rounded border, or no progress bar for the tracker Viewer.",
    },
    ["Tracker Viewer Text"] = {
        image = MEDIA_HELP .. "TrackerAutoColor.tga",
        desc = "Use contextual Tracker Viewer text colors or force all step text one selected color.",
    },
    ["Match Kaliel Header Texture"] = {
        image = MEDIA_HELP .. "TrackerViewer.tga",
        desc = "Optionally matches Kaliel's selected module-header texture, including hidden backgrounds.",
    },
    ["Match Kaliel Header Background Color"] = {
        image = MEDIA_HELP .. "TrackerViewer.tga",
        desc = "Optionally matches Kaliel's resolved shared, border, or class header color.",
    },
    ["Match Kaliel Header Font"] = {
        image = MEDIA_HELP .. "TrackerViewer.tga",
        desc = "Optionally matches Kaliel's resolved header font and shadow.",
    },
    ["Match Kaliel Header Text/Icon Color"] = {
        image = MEDIA_HELP .. "TrackerViewer.tga",
        desc = "Optionally matches Kaliel's title and collapse-indicator color.",
    },
    ["Match Kaliel Header Button Color"] = {
        image = MEDIA_HELP .. "TrackerViewer.tga",
        desc = "Optionally matches Kaliel's header-button color for AWP-owned controls.",
    },
    ["Show Step in Chat on Step Change"] = {
        image = MEDIA_HELP .. "ChatCountTitles.tga",
        desc =
        "Shows the selected guide step in your own chat frame when that provider changes steps. This is local-only and is not sent to other players.",
    },
    ["Chat Step Text"] = {
        image = MEDIA_HELP .. "ChatCountTitles.tga",
        desc = "Use contextual colors or force displayed guide step text to one selected color.",
    },
    ["Chat Sticky Summary"] = {
        image = MEDIA_HELP .. "ChatCountTitles.tga",
        desc = "Controls whether chat step output includes active sticky step count or titles.",
    },
    ["Hide Zygor's Native Frame"] = {
        image = MEDIA_HELP .. "TrackerViewer.tga",
        desc = "Hides Zygor's full-size viewer while keeping guide state, waypoints, guide picker, and menus available.",
    },
    ["Hide RestedXP Native Guide Frames"] = {
        image = MEDIA_HELP .. "TrackerViewer.tga",
        desc = "Cloaks guide windows without pausing the guide engine. Item, targeting, timer and party windows remain available.",
    },
}

Data.COLOR_OPTION_VALUE_PREVIEWS = {
    [C.WORLD_OVERLAY_COLOR_AUTO] = {
        desc = "Auto uses contextual target hints, such as quest state, destination type, route type, or source addon.",
    },
}

Data.OPTION_VALUE_PREVIEWS = {
    ["Arrow Skin"] = {
        [C.SKIN_STARLIGHT] = { image = MEDIA_HELP .. "Starlight.tga", desc = "Zygor Starlight arrow skin." },
        [C.SKIN_STEALTH] = { image = MEDIA_HELP .. "Stealth.tga", desc = "Zygor Stealth arrow skin." },
        ["AWP"] = {
            image = MEDIA_HELP .. "AWP.tga",
            desc = "AWP arrow skin.",
        },
        ["AWP Bomber"] = {
            image = MEDIA_HELP .. "AWPBomber.tga",
            desc = "AWP Bomber arrow skin.",
        },
        ["AWP Modern"] = {
            image = MEDIA_HELP .. "AWPModern.tga",
            desc = "AWP Modern arrow skin.",
        },
        ["Alliance"] = {
            image = MEDIA_HELP .. "Alliance.tga",
            desc = "Alliance arrow skin.",
        },
        ["Horde"] = {
            image = MEDIA_HELP .. "Horde.tga",
            desc = "Horde arrow skin.",
        },
    },
    ["Hide Step Backgrounds Until Mouseover"] = {
        ["Disabled"] = {
            image = MEDIA_HELP .. "MinimalMode.tga",
            desc = "Shows normal guide step backgrounds.",
        },
        ["Hide Step Backgrounds"] = {
            image = MEDIA_HELP .. "MinimalModeHideBG.tga",
            desc = "Hides guide step row backgrounds until mouseover.",
        },
        ["Hide Step Backgrounds + Line Colors"] = {
            image = MEDIA_HELP .. "MinimalModeHideBGColors.tga",
            desc = "Hides guide step row backgrounds and removes goal line colors until mouseover.",
        },
    },
    ["Auto Take Flight Paths"] = {
        [C.FLIGHT_MAP_AUTO_TAKE_DISABLED] = {
            image = MEDIA_HELP .. "FlightHighlight.tga",
            desc = "Never auto-take flight paths.",
        },
        [C.FLIGHT_MAP_AUTO_TAKE_EXACT] = {
            image = MEDIA_HELP .. "FlightHighlight.tga",
            desc = "Auto-take only exact Zygor/LibRover taxi-node matches for route.",
        },
        [C.FLIGHT_MAP_AUTO_TAKE_STRONG] = {
            image = MEDIA_HELP .. "FlightHighlight.tga",
            desc = "Auto-take exact matches and strict coordinate/name matches for route.",
        },
    },
    ["Flight Map Taxi List Side"] = {
        ["auto"] = {
            image = MEDIA_HELP .. "TaxiList.tga",
            desc =
            "Auto attaches the taxi list to the side with available screen space and updates as the flight map moves.",
        },
        ["left"] = {
            image = MEDIA_HELP .. "TaxiList.tga",
            desc = "Attach the taxi list to the left side of the flight map.",
        },
        ["right"] = {
            image = MEDIA_HELP .. "TaxiList.tga",
            desc = "Attach the taxi list to the right side of the flight map.",
        },
    },
    ["Tracker Viewer Progress Bar"] = {
        ["square"] = {
            image = MEDIA_HELP .. "TrackerSquareBorder.tga",
            desc = "Uses a square progress bar.",
        },
        ["rounded"] = {
            image = MEDIA_HELP .. "TrackerRoundedBorder.tga",
            desc = "Uses a rounded progress bar.",
        },
        ["none"] = {
            image = MEDIA_HELP .. "TrackerNoProgress.tga",
            desc = "Hides the progress bar.",
        },
    },
    ["Tracker Viewer Text"] = {
        [C.WORLD_OVERLAY_COLOR_AUTO] = {
            image = MEDIA_HELP .. "TrackerAutoColor.tga",
            desc = "Use contextual tracker viewer text colors.",
        },
        [C.WORLD_OVERLAY_COLOR_CUSTOM] = {
            image = MEDIA_HELP .. "TrackerWhiteColor.tga",
            desc = "Use selected text color for tracker viewer goal rows. White is shown.",
        },
    },
    ["Chat Step Text"] = {
        [C.WORLD_OVERLAY_COLOR_AUTO] = {
            image = MEDIA_HELP .. "ChatCountTitles.tga",
            desc = "Use contextual colors for `/awp zygor output` and step-change chat text.",
        },
        [C.WORLD_OVERLAY_COLOR_CUSTOM] = {
            image = MEDIA_HELP .. "ChatColorWhite.tga",
            desc = "Use selected text color for `/awp zygor output` and step-change chat text. White is shown.",
        },
    },
    ["Chat Sticky Summary"] = {
        [C.ZYGOR_STEP_CHAT_STICKY_NONE] = {
            image = MEDIA_HELP .. "ChatStickyDisabled.tga",
            desc = "`/awp zygor output` and step-change chat display won't mention active sticky steps.",
        },
        [C.ZYGOR_STEP_CHAT_STICKY_COUNT] = {
            image = MEDIA_HELP .. "ChatCountOnly.tga",
            desc = "`/awp zygor output` and step-change chat display will show only the number of active sticky steps.",
        },
        [C.ZYGOR_STEP_CHAT_STICKY_TITLES] = {
            image = MEDIA_HELP .. "ChatCountTitles.tga",
            desc =
            "`/awp zygor output` and step-change chat display will show the number of active sticky steps and their titles.",
        },
    },
    ["Manual Click Queue Behavior"] = {
        ["ask"] = {
            image = MEDIA_HELP .. "ManualQueueAsk.tga",
            desc = "Shows a prompt so you can create, replace, or append the manual waypoint.",
        },
    },
    ["Hide During Combat"] = {
        [C.COMBAT_HIDE_MODE_DISABLED] = { desc = "Keeps TomTom, the special travel button, and the 3D overlay visible during combat." },
        [C.COMBAT_HIDE_MODE_TOMTOM] = { desc = "Hides the TomTom arrow and special travel button during combat, then restores them afterward." },
        [C.COMBAT_HIDE_MODE_OVERLAY] = { desc = "Hides the 3D world overlay during combat and restores it afterward." },
        [C.COMBAT_HIDE_MODE_BOTH] = { desc = "Hides TomTom, the special travel button, and the 3D world overlay during combat." },
    },
    ["Quick-Start Popup"] = {
        [C.STARTUP_HELP_MODE_ACCOUNT] = { desc = "Shows the first-time quick-start guide once per account." },
        [C.STARTUP_HELP_MODE_CHARACTER] = { desc = "Shows the first-time quick-start guide once per character." },
        [C.STARTUP_HELP_MODE_DISABLED] = { desc = "Disables the automatic first-time quick-start guide on login." },
    },
    ["What's New Popup"] = {
        [C.STARTUP_HELP_MODE_ACCOUNT] = { desc = "Shows What's New once per addon update per account." },
        [C.STARTUP_HELP_MODE_CHARACTER] = { desc = "Shows What's New once per addon update per character." },
        [C.STARTUP_HELP_MODE_DISABLED] = { desc = "Disables automatic What's New popups after addon updates." },
    },
    ["Context Display"] = {
        [C.WORLD_OVERLAY_CONTEXT_DISPLAY_DIAMOND_ICON] = { image = MEDIA_HELP .. "FullContext.tga", desc = "Shows both the context diamond and destination icon." },
        [C.WORLD_OVERLAY_CONTEXT_DISPLAY_ICON_ONLY] = { image = MEDIA_HELP .. "IconOnly.tga", desc = "Shows the destination icon without the backing diamond." },
        [C.WORLD_OVERLAY_CONTEXT_DISPLAY_HIDDEN] = { image = MEDIA_HELP .. "ContextHidden.tga", desc = "Hides both the context diamond and destination icon." },
    },
    ["Waypoint"] = {
        [C.WORLD_OVERLAY_WAYPOINT_MODE_FULL] = { image = MEDIA_HELP .. "Waypoint.tga", desc = "Shows the full long-range waypoint presentation." },
        [C.WORLD_OVERLAY_WAYPOINT_MODE_DISABLED] = { desc = "Hides the long-range waypoint presentation." },
    },
    ["Footer Text"] = {
        [C.WORLD_OVERLAY_INFO_ALL] = { image = MEDIA_HELP .. "WaypointFooterAll.tga", desc = "Shows destination name, distance, and arrival time." },
        [C.WORLD_OVERLAY_INFO_DISTANCE] = { image = MEDIA_HELP .. "WaypointFooterDistance.tga", desc = "Shows only the distance." },
        [C.WORLD_OVERLAY_INFO_ARRIVAL] = { image = MEDIA_HELP .. "WaypointFooterArrivalTime.tga", desc = "Shows only the estimated arrival time." },
        [C.WORLD_OVERLAY_INFO_DESTINATION] = { image = MEDIA_HELP .. "WaypointFooterDestinationName.tga", desc = "Shows only the destination name." },
        [C.WORLD_OVERLAY_INFO_NONE] = { image = MEDIA_HELP .. "WaypointFooterNone.tga", desc = "Hides waypoint footer text." },
    },
    ["Beacon Style"] = {
        [C.WORLD_OVERLAY_BEACON_STYLE_BEACON] = { image = MEDIA_HELP .. "Beacon.tga", desc = "Shows the full vertical beacon column." },
        [C.WORLD_OVERLAY_BEACON_STYLE_BASE] = { image = MEDIA_HELP .. "BaseOnly.tga", desc = "Shows only the destination base marker." },
        [C.WORLD_OVERLAY_BEACON_STYLE_DISTANCE] = { image = MEDIA_HELP .. "Waypoint.tga", desc = "Shows the full beacon at range, then switches to base-only near the destination." },
        [C.WORLD_OVERLAY_BEACON_STYLE_OFF] = { image = MEDIA_HELP .. "BeaconOff.tga", desc = "Hides the waypoint beacon art." },
    },
    ["Pinpoint Mode"] = {
        [C.WORLD_OVERLAY_PINPOINT_MODE_FULL] = { image = MEDIA_HELP .. "Pinpoint.tga", desc = "Shows the close-range pinpoint, plaque, and context marker." },
        [C.WORLD_OVERLAY_PINPOINT_MODE_NO_PLAQUE] = { image = MEDIA_HELP .. "PinpointPlaqueOff.tga", desc = "Shows the pinpoint marker without the title plaque." },
        [C.WORLD_OVERLAY_PINPOINT_MODE_DISABLED] = { image = MEDIA_HELP .. "PinpointOff.tga", desc = "Disables the close-range pinpoint presentation." },
    },
    ["Plaque Style"] = {
        [C.WORLD_OVERLAY_PLAQUE_FANTASY] = { plaqueType = C.WORLD_OVERLAY_PLAQUE_FANTASY, desc = "Fantasy: the original illustrated pinpoint plaque." },
        [C.WORLD_OVERLAY_PLAQUE_MINIMAL] = { plaqueType = C.WORLD_OVERLAY_PLAQUE_MINIMAL, desc = "A compact dark plaque with a fine border and subtle shading." },
        [C.WORLD_OVERLAY_PLAQUE_FOREVER] = { plaqueType = C.WORLD_OVERLAY_PLAQUE_FOREVER, desc = "A bronze chamfered frame. Works on both clients without Ellesmere." },
        [C.WORLD_OVERLAY_PLAQUE_BLIZZARD] = { plaqueType = C.WORLD_OVERLAY_PLAQUE_BLIZZARD, desc = "A silver chamfered frame. Works on both clients without Ellesmere." },
        [C.WORLD_OVERLAY_PLAQUE_CLASSIC] = { plaqueType = C.WORLD_OVERLAY_PLAQUE_CLASSIC, desc = "A traditional game dialog border around a compact dark panel." },
        [C.WORLD_OVERLAY_PLAQUE_CLEAN] = { plaqueType = C.WORLD_OVERLAY_PLAQUE_CLEAN, desc = "An AWP-drawn rounded dark panel with a thin neutral border." },
        [C.WORLD_OVERLAY_PLAQUE_MODERN] = { plaqueType = C.WORLD_OVERLAY_PLAQUE_MODERN, desc = "An AWP-drawn rounded shell with a warm border, subtle bevel and soft shadow. Does not require Daylight." },
        [C.WORLD_OVERLAY_PLAQUE_GLOWING_GEMS] = { plaqueType = C.WORLD_OVERLAY_PLAQUE_GLOWING_GEMS, desc = "A gemmed plaque with animated glow support." },
        [C.WORLD_OVERLAY_PLAQUE_HORDE] = { plaqueType = C.WORLD_OVERLAY_PLAQUE_HORDE, desc = "A Horde-themed pinpoint plaque." },
        [C.WORLD_OVERLAY_PLAQUE_ALLIANCE] = { plaqueType = C.WORLD_OVERLAY_PLAQUE_ALLIANCE, desc = "An Alliance-themed pinpoint plaque." },
        [C.WORLD_OVERLAY_PLAQUE_FUTURE] = { plaqueType = C.WORLD_OVERLAY_PLAQUE_FUTURE, desc = "Future: the existing image-based plaque, previously named Modern." },
        [C.WORLD_OVERLAY_PLAQUE_STEAMPUNK] = { plaqueType = C.WORLD_OVERLAY_PLAQUE_STEAMPUNK, desc = "A brass steampunk pinpoint plaque." },
    },
}

Data.SEARCH_FILTERS = {
    { value = "all",          text = "All Settings" },
    { value = "new",          text = "New Settings",     desc = "Settings added in this version." },
    { value = "updated",      text = "Updated Settings", desc = "Existing settings changed in this version." },
    { value = "navigation",   text = "Navigation Flow",  desc = "Routing, queues, manual waypoints, and tracked quests." },
    { value = "visual",       text = "Visual Markers",   desc = "World overlay, waypoints, pinpoint, navigator, and arrow presentation." },
    { value = "sizing",       text = "Size & Opacity",   desc = "Scale, distance, opacity, offset, and height controls." },
    { value = "styles",       text = "Colors & Styles",  desc = "Skins, colors, plaques, context display, and text styling." },
    { value = "integrations", text = "Integrations",     desc = "TomTom, Zygor, guide addons, routing backends, tracker addons, map/POI addons, and flight-map helpers." },
}

Data.OPTION_PREVIEWS["Hide Polestar Native Guide Frame"] = {
    image = MEDIA_HELP .. "TrackerViewer.tga",
    desc = "Cloaks only Polestar's guide window. Its engine, picker, settings and item controls remain available.",
}

-- ============================================================
-- Tracker and integration availability
-- ============================================================

function Data.HasKalielHeaderSettings()
    return type(NS.IsAddonLoaded) == "function" and NS.IsAddonLoaded("!KalielsTracker")
        and rawget(_G, "KT_ObjectiveTrackerFrame") ~= nil
end

local sharedGuideOptions = {
    { id = "enabled", page = "viewer", label = "Enable Tracker Viewer",
        desc = "Show this guide's instructions inside your objective tracker.", tags = "enable show guide steps dock embedded objective quest tracker kaliel blizzard experimental", zygorAdded = "4.1.0", zygorUpdated = "4.2.0" },
    { id = "hideProviderName", page = "viewer", label = "Hide Guide Addon Name",
        desc = "Hide the addon name beside this Viewer's controls. The name remains in the progress and guide-menu tooltips.", tags = "hide guide provider name addon label header compact spacing tooltip hover" },
    { id = "hideGuideTitle", page = "viewer", label = "Hide Guide Title",
        desc = "Hide the current guide's title. The title remains in the progress and guide-menu tooltips. Guide switching stays in the menu.", tags = "hide guide title heading name header compact spacing tooltip hover" },
    { id = "compactActiveIndicator", page = "viewer", label = "Compact Active Indicator",
        desc = "Use a small green dot in place of the Active label when multiple Viewers are enabled. Narrow headers use the dot automatically.", tags = "active green dot navigation indicator header compact" },
    { id = "nativeWarning", page = "viewer", label = "Show Native Docking Warning Popup",
        desc = "Show a warning after login or reload when a Viewer attaches to Blizzard's objective tracker.", tags = "blizzard native docking warning popup taint risk reminder login reload", zygorAdded = "4.1.2" },
    { id = "progressStyle", page = "viewer", label = "Tracker Viewer Progress Bar",
        desc = "Choose a square or rounded progress bar, or hide it.", tags = "progress bar square rounded border percent header step completion", zygorAdded = "4.1.0" },
    { id = "textColorMode", page = "viewer", label = "Tracker Viewer Text",
        desc = "Auto colors instructions by context. UI colors uses the selected UI style's text colors when available. Choose a preset or Custom for one fixed color.", tags = "contextual semantic theme UI colors settings tint text palette training npc", zygorAdded = "4.1.0", zygorUpdated = "5.0.0" },
    { id = "customTextSizes", page = "viewer", label = "Use custom Viewer text sizes",
        desc = "Set independent heading, goal, notes/context and progress sizes. Keep the inherited font, outline and shadow.", tags = "font text size scale heading goal body notes context progress readability" },
    { id = "ktHeaderTexture", page = "viewer", label = "Match Kaliel Header Texture",
        desc = "Use Kaliel's module-header artwork or hidden-background setting.", tags = "kaliel kt header texture artwork sprites background", requiresKaliel = true, zygorAdded = "4.1.1" },
    { id = "ktHeaderBackgroundColor", page = "viewer", label = "Match Kaliel Header Background Color",
        desc = "Use Kaliel's chosen header background color.", tags = "kaliel kt header background colors border class", requiresKaliel = true, zygorAdded = "4.1.1" },
    { id = "ktHeaderFont", page = "viewer", label = "Match Kaliel Header Font",
        desc = "Use Kaliel's header font, outline and shadow. Custom Viewer text sizes can override its size.", tags = "kaliel kt header font face size outline shadow", requiresKaliel = true, zygorAdded = "4.1.1" },
    { id = "ktHeaderTextIconColor", page = "viewer", label = "Match Kaliel Header Text/Icon Color",
        desc = "Use Kaliel's title and collapse icon colors.", tags = "kaliel kt header text icon collapse indicator color", requiresKaliel = true, zygorAdded = "4.1.1" },
    { id = "ktHeaderButtonColor", page = "viewer", label = "Match Kaliel Header Button Color",
        desc = "Use Kaliel's header button color for the guide controls.", tags = "kaliel kt header button color controls", requiresKaliel = true, zygorAdded = "4.1.1" },
    { id = "chatOutputOnChange", page = "chat", label = "Show Step in Chat on Step Change",
        desc = "Show the current guide instructions in your own chat when the step changes.", tags = "chat step announce output local on step change", zygorAdded = "4.1.0" },
    { id = "chatTextColorMode", page = "chat", label = "Chat Step Text",
        desc = "Use contextual colors or choose one fixed color for guide instructions in your own chat.", tags = "chat local contextual text color tint custom fixed", zygorAdded = "4.1.0" },
    { id = "chatStickySummary", page = "chat", label = "Chat Sticky Summary",
        desc = "Choose whether your chat includes a sticky summary, and whether it shows the count or titles. Polestar summarizes along-the-way goals.", tags = "chat sticky stickies count titles summary local output", zygorAdded = "4.1.0" },
}
Data.GUIDE_OPTIONS = {}
for _, option in ipairs(sharedGuideOptions) do Data.GUIDE_OPTIONS[option.id] = option end

Data.OPTION_PREVIEWS[Data.GUIDE_OPTIONS.enabled.label] = {
    image = MEDIA_HELP .. "TrackerViewer.tga",
    desc = Data.GUIDE_OPTIONS.enabled.desc,
}

Data.UI_STYLE = { label = "UI Style",
    desc = "Match your UI or choose AWP for its original look. Automatic uses the only available UI style or offers a choice when several are available. If your selected addon is unavailable, AWP uses its own look and keeps your choice. Each Viewer and area keeps its own settings." }
Data.GUIDE_VIEWER_ORDER = { label = "Guide Viewer Order",
    desc = "Drag guide addons into the order you want in the tracker. Search Nearby checks supported guide addons in the same order." }
Data.FLIGHT_ROUTE_MARKER = { label = "Show Flight Map Route Marker",
    desc = "Highlight the intended flight destination when your route includes a flight path. Works on Retail and Forever." }

-- ============================================================
-- Setting options
-- ============================================================

local function BaseOptions() return {
    { key = "profiles", label = "Settings Profiles", desc = "Create, duplicate and manage profiles. Use the account default or choose a different profile for this character.", added = "5.0.0", tags = "profile profiles account character default duplicate rename delete switch layout" },
    { key = "profiles", label = "Import", desc = "Review a settings string, select the sections to import, and create or update a profile. Layout is excluded by default.", added = "5.0.0", tags = "profile import restore paste settings string share" },
    { key = "profiles", label = "Export", desc = "Copy a profile as a settings string for backup or sharing between Retail and Forever.", added = "5.0.0", tags = "profile export backup copy share settings string" },
    { key = "general", label = Data.GUIDE_VIEWER_ORDER.label, desc = Data.GUIDE_VIEWER_ORDER.desc, added = "5.0.0",
        tags = "guide viewer tracker provider order reorder drag sorting top bottom nearby service search priority" },
    { key = "general", label = "Reset individual settings", desc = "Restore one changed setting to its default without resetting your profile. Hover Reset to see the default.", added = "5.0.0", tags = "reset default defaults restore undo settings options daylight per setting" },
    { key = "about",        label = "About",                                     desc = Data.ABOUT_SUMMARY,                                                                                                                                               tags = "addon overview information features navigation help" },
    { key = "general",      label = "Enable Routing",                            desc = "Let AWP manage navigation from guides, quests, maps and waypoints. Turning this off returns routing to the original addons.",                                                                                                             added = "3.0.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Reworked for v4 route ownership and backend selection.",                                                                   tags = "route routing navigation ownership enable disable on off" },
    { key = "general",      label = "Routing Backend",                           desc = "Choose how AWP plans routes: Zygor, Farstrider, Mapzeroth, Dugi, TomTom Direct, Polestar (Forever) or QuestieRouter (Forever). AWP can try other available planners if your preferred one fails.",                                                 added = "4.0.0",                                                                                                                                                                                            updated = "5.0.0",                                                                                                                                                             note = "Farstrider, Mapzeroth, and Zygor use the current flavor-specific addon and travel data.", tags = "direct tomtom farstrider mapzeroth zygor polestar dugi taxi system travel planner forever retail backend fallback recovery preferred retry walking roads streets terrain road preference astral recall escort follower" },
    { key = "general",      label = "Follow ground paths while flying",         desc = "Keep following ground paths during self-flight. When off, AWP may skip ordinary walking points if the planner confirms a flying shortcut. Required stops remain.", added = "5.0.0", tags = "walking flying flight skyriding mounted ground roads terrain path shortcut progression required stops retail forever" },
    { key = "general",      label = Data.FLIGHT_ROUTE_MARKER.label, desc = Data.FLIGHT_ROUTE_MARKER.desc,                                                                                                   added = "4.1.0",                                                                                                                                                                                            tags = "flight map flightmap taxi flight path taxi node marker route zygor librover mapzeroth farstrider fly fp inflight auto automatic" },
    { key = "general",      label = "Auto Take Flight Paths",                    desc = "Automatically take a flight when it confidently matches your route. Off by default; hold Alt to skip for the current flight window.",                                                                                added = "4.1.0",                                                                                                                                                                                            tags = "flight map flightmap taxi flight path auto take exact strong disabled zygor librover mapzeroth farstrider alt suppress fly fp" },
    { key = "general",      label = "Show Flight Map Taxi List",                 desc = "Show reachable flights, fares, favorites, recent flights and the suggested destination in a searchable list beside the flight window. Times appear when available.",       added = "4.1.0",                                                                                                                                                                                            tags = "flight map flightmap taxi flight path list catalog favorites recent current zone search route destination fly fp" },
    { key = "general",      label = "Flight Map Taxi List Side",                 desc = "Choose which side of the flight window the Taxi List opens on. Auto uses the available screen space.",                                             added = "4.1.0",                                                                                                                                                                                            tags = "flight map flightmap taxi flight path list catalog side left right auto destination fly fp" },
    { key = "general",      label = "Flight Map Taxi List Text Size",            desc = "Adjust destination name text size in the Taxi List.",                                                                                        added = "4.1.0",                                                                                                                                                                                            tags = "flight map flightmap taxi flight path list catalog text size font destination readable readability" },
    { key = "general",      label = "Hide During Combat",                        desc = "Choose which navigation displays to hide while fighting. The travel action button is unavailable during combat.",                                                              added = "4.0.0b",                                                                                                                                                                                           tags = "combat hide tomtom arrow travel button special action overlay world overlay both disabled" },
    { key = "general",      label = "Quick-Start Popup",                         desc = "Show the first-time setup guide once per account, once per character, or never automatically.",                                                       added = "4.0.0b",                                                                                                                                                                                           tags = "help popup login startup account character disabled first time quick start overview guide" },
    { key = "general",      label = "What's New Popup",                          desc = "Show release notes after an update once per account, once per character, or never automatically.",                                                         added = "4.0.0b",                                                                                                                                                                                           tags = "whats new changelog popup login startup account character disabled updates release notes" },
    { key = "general",      label = "Show Minimap Button",                       desc = "Show the AWP minimap button for settings, Help, queues, nearby service searches and guide controls.",                                                   added = "4.1.0",                                                                                                                                                                                            tags = "minimap minimapbutton button addon compartment addoncompartment icon broker ldb databroker quick menu settings help queue zygor tracker viewer show hide toggle reset" },
    { key = "general",      label = "Manual Click Queue Behavior",               desc = "Choose whether a new map waypoint, quest shortcut or single /way command creates a queue, replaces the active queue, appends a stop, or asks each time.",                                                                                                         added = "4.0.0",                                                                                                                                                                                            note = "Adds explicit create, replace, append, and ask behavior for map clicks.",                                                                                              tags = "create new queue replace active append ask prompt" },
    { key = "general",      label = "Preserve Imported and Multi-Stop Queues",   desc = "When using Replace Active, keep imported and multi-stop queues saved at their current stop and navigate to the new destination separately.",                                                                             added = "5.0.0",                                                                                                                                                                                            tags = "preserve protect pause replace active imported import ttpaste multi stop manual queue waypoint" },
    { key = "general",      label = "Auto-Clear Manual Waypoints on Arrival",    desc = "Automatically clear a manual destination when you reach it, not at intermediate travel steps.",                                                                                                         added = "2.3.0",                                                                                                                                                                                            tags = "manual waypoint queue arrival destination automatic clear remove complete" },
    { key = "general",      label = "Manual Waypoint Clear Distance",            desc = "Choose how close you must be to a manual destination before it clears automatically.",                                                                                                       added = "2.3.0",                                                                                                                                                                                            tags = "manual waypoint arrival radius range yards threshold clear remove distance" },
    { key = "general",      label = "Auto-Route Tracked Quests",                 desc = "Automatically route newly tracked quests without interrupting a guide that is currently directing navigation.",                                                                added = "3.1.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Now uses v4 route authority and guide protection.",                                                                        tags = "quest tracked tracking watched watch automatic route blizzard guide authority protected" },
    { key = "general",      label = "Auto-Clear Untracked Quests",               desc = "Remove matching quest routes and queue entries when you stop tracking a quest.",                                                                                added = "4.0.0",                                                                                                                                                                                            tags = "quest tracking untracking queue clear" },
    { key = "general",      label = "Auto-Clear Supertracked Quests on Arrival", desc = "Clear the route to a supertracked quest when you reach its destination.",                                                                                                added = "3.1.0",                                                                                                                                                                                            tags = "quest supertrack supertracked arrival destination automatic clear remove complete blizzard" },
    { key = "general",      label = "Adopt Waypoints from Unknown Addons",       desc = "Allow supported waypoint requests from addons that do not have a dedicated AWP integration.",                                                                                   added = "4.0.0",                                                                                                                                                                                            tags = "addon allowlist blocklist worldquesttab" },
    { key = "general",      label = "Detected Addon Callers",                    desc = "Review addons that have requested waypoints and choose whether to allow or block them.",                                                                                      added = "4.0.0",                                                                                                                                                                                            tags = "addon allowlist blocklist" },
    { key = "general",      label = "Addon Allowlist",                           desc = "Enter addon folder names that AWP may accept waypoints from through general addon support.",                                                                                                   added = "4.0.0",                                                                                                                                                                                            tags = "addon allowlist allow" },
    { key = "general",      label = "Addon Blocklist",                           desc = "Enter addon folder names that AWP should ignore through general addon support.",                                                                                                     added = "4.0.0",                                                                                                                                                                                            tags = "addon blocklist block" },
    { key = "tomtom",       label = "Use Custom Arrow Skin",                     desc = "Replace TomTom's original arrow artwork with an AWP or supported guide skin.",                                                                                                   added = "3.0.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Now uses the registered arrow skin system.",                                                                               tags = "zygor starlight stealth" },
    { key = "tomtom",       label = "Arrow Skin",                                desc = "Choose how the TomTom arrow looks. Zygor skins appear when Zygor is loaded.",                                                                                                                           added = "3.0.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Now lists registered skins dynamically, including Zygor skins when available.",                                            tags = "tomtom default zygor starlight stealth awp awp bomber awp modern alliance horde" },
    { key = "tomtom",       label = "TomTom Arrow Scale",                        desc = "Make the custom TomTom arrow larger or smaller.",                                                                                                                     added = "3.0.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Moved into the v4 arrow skin settings.",                                                                                   tags = "zygor arrow scale" },
    { key = "tomtom",       label = "Special Travel Button Scale",               desc = "Adjust the size of the button that appears when a route needs a usable travel item, spell or similar action.",                                  added = "4.0.0",                                                                                                                                                                                            note = "Adds a scale control for the special travel button.",                                                                                                                  tags = "travel action button hearthstone portal item spell" },
    { key = "overlay",      label = "Enable 3D World Overlay",                   desc = "Show or hide the in-world waypoint overlay.",                                                                                                                    added = "3.0.0",                                                                                                                                                                                            tags = "world overlay 3d marker in world waypoint show hide toggle enable disable" },
    { key = "overlay",      label = "Fade on Hover",                             desc = "Fade the 3D overlay while the mouse is over it.",                                                                                                                added = "3.0.0",                                                                                                                                                                                            tags = "world overlay 3d mouse mouseover hover fade transparency alpha" },
    { key = "overlay",      label = "Context Display",                           desc = "Choose context display: diamond and icon, icon only, or hidden.",                                                                                                added = "3.0.0",                                                                                                                                                                                            tags = "context diamond + icon context diamond icon icon only hidden" },
    { key = "overlay",      label = "Context Diamond",                           desc = "Change the context diamond color.",                                                                                                                              added = "3.0.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Color modes now use Auto contextual hints and the Gray preset.",                                                           tags = "color tint auto blue custom cyan gold gray green pink purple red silver white" },
    { key = "overlay",      label = "Icons",                                     desc = "Change overlay icon color.",                                                                                                                                     added = "3.0.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Color modes now use Auto contextual hints and the Gray preset.",                                                           tags = "color tint auto blue custom cyan gold gray green pink purple red silver white" },
    { key = "waypoint",     label = "Waypoint",                                  desc = "Control the long-range waypoint marker.",                                                                                                                        added = "3.0.0",                                                                                                                                                                                            tags = "enabled disabled" },
    { key = "waypoint",     label = "Waypoint Size",                             desc = "Scale the 3D waypoint frame.",                                                                                                                                   added = "3.0.0",                                                                                                                                                                                            tags = "world overlay marker scale frame large small sizing" },
    { key = "waypoint",     label = "Waypoint Min Size",                         desc = "Set the minimum dynamic waypoint scale.",                                                                                                                        added = "3.0.0",                                                                                                                                                                                            tags = "world overlay marker scale minimum min dynamic clamp distance sizing" },
    { key = "waypoint",     label = "Waypoint Max Size",                         desc = "Set the maximum dynamic waypoint scale.",                                                                                                                        added = "3.0.0",                                                                                                                                                                                            tags = "world overlay marker scale maximum max dynamic clamp distance sizing" },
    { key = "waypoint",     label = "Waypoint Opacity",                          desc = "Change waypoint marker opacity.",                                                                                                                                added = "3.0.0",                                                                                                                                                                                            tags = "transparency transparent alpha visibility" },
    { key = "waypoint",     label = "Vertical Offset",                           desc = "Move the waypoint marker up or down.",                                                                                                                           added = "3.0.0",                                                                                                                                                                                            tags = "world overlay marker height position up down vertical z offset" },
    { key = "waypoint",     label = "Beacon Style",                              desc = "Choose beacon, base only, distance based, or off.",                                                                                                              added = "3.0.0",                                                                                                                                                                                            tags = "world overlay beam marker beacon base only distance based off disabled style" },
    { key = "waypoint",     label = "Beacon Base Distance",                      desc = "Set the distance where the beacon switches to base-only.",                                                                                                       added = "3.0.0",                                                                                                                                                                                            tags = "world overlay beacon base only switch range threshold yards distance" },
    { key = "waypoint",     label = "Beacon Opacity",                            desc = "Change beacon opacity.",                                                                                                                                         added = "3.0.0",                                                                                                                                                                                            tags = "transparency transparent alpha visibility" },
    { key = "waypoint",     label = "Base Vertical Offset",                      desc = "Move the base-only beacon vertically.",                                                                                                                          added = "3.0.0",                                                                                                                                                                                            tags = "world overlay beacon base only height position up down vertical z offset" },
    { key = "waypoint",     label = "Use Meters instead of Yards",               desc = "Format overlay distance in meters.",                                                                                                                             added = "3.0.0",                                                                                                                                                                                            tags = "world overlay distance units metric meters metres yards measurement" },
    { key = "waypoint",     label = "Footer Text",                               desc = "Choose waypoint footer information.",                                                                                                                            added = "3.0.0",                                                                                                                                                                                            tags = "all distance arrival time destination name none" },
    { key = "waypoint",     label = "Info Text Size",                            desc = "Scale waypoint footer text.",                                                                                                                                    added = "3.0.0",                                                                                                                                                                                            tags = "world overlay footer font text scale destination distance arrival time sizing" },
    { key = "waypoint",     label = "Info Text Opacity",                         desc = "Change waypoint footer text opacity.",                                                                                                                           added = "3.0.0",                                                                                                                                                                                            tags = "transparency transparent alpha visibility" },
    { key = "waypoint",     label = "Distance/Arrival Time Opacity",             desc = "Change distance and arrival time text opacity.",                                                                                                                 added = "3.0.0",                                                                                                                                                                                            tags = "transparency transparent alpha visibility" },
    { key = "waypoint",     label = "Waypoint Text",                             desc = "Change waypoint footer text color.",                                                                                                                             added = "3.0.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Color modes now use Auto contextual hints and the Gray preset.",                                                           tags = "color tint auto blue custom cyan gold gray green pink purple red silver white" },
    { key = "waypoint",     label = "Beacon",                                    desc = "Change 3D beacon color.",                                                                                                                                        added = "3.0.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Color modes now use Auto contextual hints and the Gray preset.",                                                           tags = "color tint auto blue custom cyan gold gray green pink purple red silver white" },
    { key = "pinpoint",     label = "Pinpoint Mode",                             desc = "Control the close-range pinpoint display.",                                                                                                                      added = "3.0.0",                                                                                                                                                                                            tags = "full plaque off no plaque disabled box dialog popup overhead" },
    { key = "pinpoint",     label = "Show Pinpoint At",                          desc = "Set the distance where the overlay switches to pinpoint mode.",                                                                                                  added = "3.0.0",                                                                                                                                                                                            tags = "close range switch threshold radius yards marker display distance" },
    { key = "pinpoint",     label = "Hide Pinpoint At",                          desc = "Set the arrival distance where the pinpoint display hides.",                                                                                                     added = "3.0.0",                                                                                                                                                                                            tags = "arrival range threshold radius yards marker hide disappear complete distance" },
    { key = "pinpoint",     label = "Pinpoint Size",                             desc = "Scale the 3D pinpoint.",                                                                                                                                         added = "3.0.0",                                                                                                                                                                                            tags = "close range marker scale large small sizing world overlay" },
    { key = "pinpoint",     label = "Pinpoint Opacity",                          desc = "Change pinpoint opacity.",                                                                                                                                       added = "3.0.0",                                                                                                                                                                                            tags = "transparency transparent alpha visibility" },
    { key = "pinpoint", label = "Plaque Background Opacity", desc = "Remember separate middle opacity for each standalone Minimal, Forever, Blizzard, Classic, Clean and Modern plaques. Reset restores the current design's original opacity. Text and diamond remain independent.", added = "5.0.0", tags = "plaque panel background fill middle opacity alpha transparent transparency style default" },
    { key = "pinpoint", label = "Plaque Border Opacity", desc = "Remember frame opacity independently for each standalone plaque. Shadow and bevel strength follow the border; background and text remain independent.", added = "5.0.0", tags = "plaque frame border trim rim outline shadow bevel opacity alpha transparent transparency" },
    { key = "pinpoint", label = "Plaque Border Thickness", desc = "Adjust Minimal, Clean and Modern plaque borders from 1-8 pixels. Reset restores the current design's thickness. Padding grows to keep instructions inside the frame.", added = "5.0.0", tags = "plaque frame border rim outline thickness width size pixels padding minimal clean modern" },
    { key = "pinpoint",     label = "Plaque Style",                              desc = "Choose standalone plaque artwork; appearance-addon shell matching overrides it while enabled.",                                                                                      added = "3.0.0", updated = "5.0.0",                                                                                                                                                                                            tags = "fantasy default minimal minimalist forever blizzard classic clean modern future compact dark rounded chamfer bronze silver shell border gradient glowing gems horde alliance steampunk steam punk" },
    { key = "pinpoint",     label = "Animate Plaque Effects",                    desc = "Toggle animated plaque pulse, glow, and gem effects.",                                                                                                           added = "3.0.0",                                                                                                                                                                                            tags = "animation animated pulse glow gems effects on off enable disable style" },
    { key = "pinpoint",     label = "Show Destination Info",                     desc = "Show the title inside the pinpoint plaque.",                                                                                                                     added = "3.0.0",                                                                                                                                                                                            tags = "title name label target text plaque marker show hide" },
    { key = "pinpoint",     label = "Show Extended Info",                        desc = "Show quest or guide context in the plaque.",                                                                                                                     added = "3.0.0",                                                                                                                                                                                            tags = "quest guide context objective details subtext plaque marker show hide" },
    { key = "pinpoint",     label = "Show Coordinate Fallback",                  desc = "Show coordinates when no extended text exists.",                                                                                                                 added = "3.0.0",                                                                                                                                                                                            tags = "coords coordinates map position x y fallback text plaque marker show hide" },
    { key = "pinpoint",     label = "Show Pinpoint Arrows",                      desc = "Show animated downward chevrons.",                                                                                                                               added = "3.0.0",                                                                                                                                                                                            tags = "chevrons arrows downward direction animation marker show hide" },
    { key = "pinpoint",     label = "Base Pinpoint Height",                      desc = "Adjust the pinpoint height.",                                                                                                                                    added = "3.0.0",                                                                                                                                                                                            tags = "marker height position up down vertical z offset world overlay" },
    { key = "pinpoint",     label = "Camera Pinpoint Height",                    desc = "Adjust pinpoint height based on camera pitch.",                                                                                                                  added = "3.0.0",                                                                                                                                                                                            tags = "marker height position camera pitch angle dynamic vertical z offset" },
    { key = "pinpoint",     label = "Pinpoint Title",                            desc = "Change pinpoint title color.",                                                                                                                                   added = "3.0.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Color modes now use Auto contextual hints and the Gray preset.",                                                           tags = "color tint auto blue custom cyan gold gray green pink purple red silver white" },
    { key = "pinpoint",     label = "Pinpoint Subtext",                          desc = "Change pinpoint subtext color.",                                                                                                                                 added = "3.0.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Color modes now use Auto contextual hints and the Gray preset.",                                                           tags = "color tint auto blue custom cyan gold gray green pink purple red silver white" },
    { key = "pinpoint",     label = "Pinpoint Plaque",                           desc = "Change pinpoint plaque color.",                                                                                                                                  added = "3.0.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Color modes now use Auto contextual hints and the Gray preset.",                                                           tags = "color tint auto blue custom cyan gold gray green pink purple red silver white" },
    { key = "pinpoint",     label = "Animated Parts",                            desc = "Change plaque gem and glow colors.",                                                                                                                             added = "3.0.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Color modes now use Auto contextual hints and the Gray preset.",                                                           tags = "color tint auto blue custom cyan gold gray green pink purple red silver white" },
    { key = "pinpoint",     label = "Chevrons",                                  desc = "Change pinpoint chevron colors.",                                                                                                                                added = "3.0.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Color modes now use Auto contextual hints and the Gray preset.",                                                           tags = "color tint auto blue custom cyan gold gray green pink purple red silver white" },
    { key = "navigator",    label = "Enable Navigator",                          desc = "Show the off-screen navigator arrow.",                                                                                                                           added = "3.0.0",                                                                                                                                                                                            tags = "offscreen off screen arrow direction indicator show hide toggle enable disable" },
    { key = "navigator",    label = "Navigator Size",                            desc = "Scale the navigator.",                                                                                                                                           added = "3.0.0",                                                                                                                                                                                            tags = "offscreen off screen arrow scale large small sizing" },
    { key = "navigator",    label = "Navigator Opacity",                         desc = "Change navigator opacity.",                                                                                                                                      added = "3.0.0",                                                                                                                                                                                            tags = "transparency transparent alpha visibility" },
    { key = "navigator",    label = "Navigator Distance",                        desc = "Move the navigator closer to or farther away from the screen center.",                                                                                           added = "3.0.0",                                                                                                                                                                                            tags = "offscreen off screen arrow position radius center near far offset" },
    { key = "navigator",    label = "Navigator Dynamic Distance",                desc = "Adjust navigator distance with camera zoom.",                                                                                                                    added = "3.0.0",                                                                                                                                                                                            tags = "offscreen off screen arrow position radius camera zoom automatic adaptive" },
    { key = "navigator",    label = "Navigator Arrow",                           desc = "Change navigator arrow color.",                                                                                                                                  added = "3.0.0",                                                                                                                                                                                            updated = "4.0.0",                                                                                                                                                             note = "Color modes now use Auto contextual hints and the Gray preset.",                                                           tags = "color tint auto blue custom cyan gold gray green pink purple red silver white" },
    { key = "zygor",        label = "Show Only Guide Steps Until Mouseover",     desc = "Compact the Zygor guide frame until you mouse over it.",                                                                                                         added = "3.0.0",                                                                                                                                                                                            tags = "zygor guide viewer compact minimal mode mouseover collapse hide controls current step" },
    { key = "zygor",        label = "Hide Step Backgrounds Until Mouseover",     desc = "Fade guide step row backgrounds while compacted.",                                                                                                               added = "3.0.0",                                                                                                                                                                                            tags = "hide step backgrounds hide step backgrounds + line colors line colors goal lines disabled mouseover zygor" },
    { key = "zygor",        label = "Hide Zygor's Native Frame",                 desc = "Hide Zygor's full-size viewer while keeping guide state, waypoints, guide picker, and settings menus available.",                                                added = "4.1.0",                                                                                                                                                                                            tags = "tracker viewer hide native guide zygor frame viewer window fullsize big main visual cloak hidden minimap menu" },
    { key = "dugi",         label = "Hide Dugi Native Guide Frame",              desc = "Hide Dugi's floating guide frame and model viewer.",                                                                                                             added = "5.0.0",                                                                                                                                                                                            tags = "dugi hide native floating guide frame model viewer npc preview cloak restore anchored small frame objective tracker safe runtime" },
    { key = "integrations", label = "Integrations",                              desc = "Supported addon integrations, route backends, map sources, and what AWP uses them for.",                                                                         tags = "addons integrations tomtom zygor dugi dugisguideviewer restedxp rxp rxpguides polestar apr wowpro farstrider mapzeroth inflight kaliel kalielstracker objective tracker worldquesttab handynotes silverdragon rarescanner blizzard" },
    { key = "release",      label = "Release Notes",                             desc = "Recent changes and version notes.",                                                                                                                              tags = "changelog whats new updates versions history patch notes" },
    { key = "polestar", label = "Open Polestar Settings"              , desc = "Configure native travel routes, class teleports, real walking paths and route style in Polestar.", added = "5.0.0", tags = "polestar forever backend routing travel class teleports walk real paths terrain navigation roads safe route style settings" },
    { key = "polestar", label = "Hide Polestar Native Guide Frame"    , desc = "Cloak native guide frames without pausing Polestar or hiding item and targeting controls."       , added = "5.0.0", tags = "polestar forever native frames hide cloak engine pause" },
    { key = "rxp", label = "Hide RestedXP Native Guide Frames", desc = "Cloak native guide frames without pausing RestedXP or hiding item and targeting controls.", added = "5.0.0", tags = "restedxp rxp native frames hide cloak engine pause" },
} end

-- The settings window shares this catalog between search and release badges.
local cachedOptions, markersByPage
function Data.GetOptions()
    if cachedOptions then return cachedOptions, markersByPage end
    local options = BaseOptions()
    if not NS.IsWoWForever() then
        for index = #options, 1, -1 do
            local entry = options[index]
            if entry.key == "polestar" then
                table.remove(options, index)
            else
                if entry.label == "Routing Backend" then entry.desc = entry.desc:gsub(", TomTom Direct, Polestar %(Forever%) or QuestieRouter %(Forever%)", ", or TomTom Direct") end
                if entry.tags then entry.tags = entry.tags:gsub(" polestar", ""):gsub(" questierouter", "") end
            end
        end
    end

    local guideActions = NS.Internal.GuideTrackerViewer and NS.Internal.GuideTrackerViewer.GuideActions
    for _, definition in ipairs(C.GUIDE_PROVIDERS) do
        if not definition.forever or NS.IsWoWForever() then
            for _, size in ipairs(C.GUIDE_VIEWER_TEXT_SIZES) do
                options[#options + 1] = {key=definition.key, page="viewer", label=size.label,
                    desc="Independent Viewer text size; enable Use custom Viewer text sizes to override tracker/UI sizing.",
                    tags=definition.key .. " tracker viewer font text size heading goal body notes context progress"}
            end
            for _, option in ipairs(sharedGuideOptions) do
                local zygor = definition.key == "zygor"
                options[#options + 1] = { key = definition.key, page = option.page, label = option.label,
                    desc = option.desc, tags = definition.key .. " " .. option.tags, requiresKaliel = option.requiresKaliel,
                    added = zygor and option.zygorAdded or "5.0.0", updated = zygor and option.zygorUpdated or nil,
                    note = zygor and option.id == "enabled" and "Blizzard tracker docking is experimental." or nil }
            end
            for _, option in ipairs({
                { "Enable Guide Action Panel", "Keep a movable action panel for this guide. Prepared standard bindings remain usable in combat; native callback helpers require leaving combat." },
                { "Show Actions Beside Steps", "Show guide action buttons beside matching Viewer rows outside combat, on every supported tracker host." },
                { "Hide Native Action Controls", "Hide this guide's native action controls independently of AWP's panel, inline buttons and filters." },
                { "Reset Guide Action Panel Position", "Restore this guide's action panel to its default position." },
            }) do
                options[#options + 1] = { key = definition.key, page = "actions", label = option[1], desc = option[2], added = "5.0.0",
                    tags = definition.key .. " guide viewer action panel inline buttons item toy spell target friendly hostile equipment pet extra helper cleanup combat secure native hide filters" }
            end
            if guideActions and guideActions.HasGroupedActions(definition.key) then
                options[#options + 1] = { key = definition.key, page = "actions", label = "Grouped Actions Position",
                    desc = "Center step-wide action buttons above or below the objectives. Below is the default.", added = "5.0.0",
                    tags = definition.key .. " tracker viewer guide actions icons grouped position placement center above below objective" }
            end
            for _, category in ipairs(C.GUIDE_ACTION_TYPES) do
                local label = category.label
                options[#options + 1] = { key = definition.key, page = "actions", label = "Show " .. label,
                    desc = "Filter " .. label:lower() .. " in this guide's action panel and inline buttons only.", added = "5.0.0",
                    tags = definition.key .. " guide viewer action panel inline button category filter " .. label:lower() }
            end
            if definition.key == "apr" or definition.key == "wowpro" or definition.key == "questierouter" then
                options[#options + 1] = { key = definition.key, label = "Hide Native Guide Frame",
                    desc = "Hide the original guide window while keeping the guide running. Some embedded actions must be covered before the window can be hidden.",
                    added = "5.0.0", tags = definition.key .. " guide addon hide native window frame" }
                options[#options + 1] = { key = definition.key, label = "Open " .. definition.label .. " Guide Browser",
                    desc = "Open the addon's native guide browser.", tags = "guide selector chooser picker route" }
            end
            if definition.key == "questierouter" then
                options[#options + 1] = { key = definition.key, label = "Visible Tasks",
                    desc = "Choose how many current and upcoming QuestieRouter tasks to show in the Tracker Viewer.",
                    added = "5.0.0", tags = "questierouter guide tracker steps upcoming current task count" }
                options[#options + 1] = { key = definition.key, label = "Show QuestieRouter Banner",
                    desc = "Show static native banner artwork, guide title and quest progress above the tasks. Defaults off.",
                    added = "5.0.0", tags = "questie questierouter zone banner artwork picture header title quests progress static" }
            end
        end
    end

    local overviewLabels = {
        ["Show Only Guide Steps Until Mouseover"] = true,
        ["Hide Step Backgrounds Until Mouseover"] = true,
        ["Hide Zygor's Native Frame"] = true,
        ["Hide Dugi Native Guide Frame"] = true,
        ["Hide RestedXP Native Guide Frames"] = true,
        ["Hide Polestar Native Guide Frame"] = true,
        ["Hide Native Guide Frame"] = true,
        ["Open Polestar Settings"] = true,
        ["Open APR Guide Browser"] = true,
        ["Open WoWPro Guide Browser"] = true,
        ["Open QuestieRouter Guide Browser"] = true,
    }
    for _, entry in ipairs(options) do
        if Data.GUIDE_SECTIONS[entry.key] and not entry.page and not overviewLabels[entry.label] then
            entry.page = "viewer"
        end
    end

    options[#options + 1] = { key = "general", label = Data.UI_STYLE.label,
        desc = Data.UI_STYLE.desc,
        added = "5.0.0", tags = "appearance provider theme style skin automatic default popup chooser multiple daylight ellesmere elvui gw2_ui gw2ui gw2 classic modern forever blizzard" }
    for _, provider in ipairs(NS.Internal.Appearance.GetProviders()) do
        if provider.options then
            options[#options + 1] = { key = provider.id, label = "Enable " .. provider.label .. " Styling",
                desc = provider.options.desc, added = "5.0.0",
                tags = provider.id .. " appearance theme skin fonts text colors header buttons progress plaque panels reset" }
        end
    end

    local markers = {}
    for _, entry in ipairs(options) do
        if entry.added or entry.updated or entry.note then
            local page = entry.page and entry.key .. "." .. entry.page or entry.key
            local rows = markers[page]
            if not rows then
                rows = {}
                markers[page] = rows
            end
            if not rows[entry.label] then rows[entry.label] = entry end
        end
    end
    cachedOptions, markersByPage = options, markers
    return options, markers
end
