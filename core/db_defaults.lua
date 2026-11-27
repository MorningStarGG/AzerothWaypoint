-- ============================================================
-- Saved settings defaults
-- ============================================================
--
-- Declares account and overlay defaults before the saved-data readers load.

local NS = _G.AzerothWaypointNS
local C = NS.Constants

local function CopyOverlayColor(color)
    color = color or C.WORLD_OVERLAY_COLOR_PRESETS[C.WORLD_OVERLAY_COLOR_GOLD] or { r = 0.95, g = 0.84, b = 0.44 }
    return {
        r = color.r or 1,
        g = color.g or 1,
        b = color.b or 1,
    }
end

local DEFAULT_OVERLAY_CUSTOM_COLOR = CopyOverlayColor(C.WORLD_OVERLAY_COLOR_PRESETS[C.WORLD_OVERLAY_COLOR_GOLD])
local DEFAULT_GUIDE_TRACKER_VIEWER_TEXT_COLOR = CopyOverlayColor(C.WORLD_OVERLAY_COLOR_PRESETS
    [C.WORLD_OVERLAY_COLOR_WHITE])
local VIEWER_APPEARANCE_DEFAULTS = {
    CustomTextSizes = false,
    TextColorMode = C.WORLD_OVERLAY_COLOR_AUTO,
    TextCustomColor = DEFAULT_GUIDE_TRACKER_VIEWER_TEXT_COLOR,
    ProgressStyle = "rounded",
    HideGuideTitle = false,
    HideProviderName = true,
    CompactActiveIndicator = true,
    KTHeaderTexture = false,
    KTHeaderBackgroundColor = false,
    KTHeaderFont = false,
    KTHeaderTextIconColor = false,
    KTHeaderButtonColor = false,
}
for _, size in ipairs(C.GUIDE_VIEWER_TEXT_SIZES) do
    VIEWER_APPEARANCE_DEFAULTS[size.suffix] = size.default
end

-- ============================================================
-- Saved preference defaults
-- ============================================================

local DB_DEFAULTS = {
    appearanceProvider                            = "auto",
    guideStepsOnlyHover                           = false,
    guideStepBackgroundsHover                     = C.GUIDE_STEP_BACKGROUND_MODE_NONE,
    manualWaypointAutoClear                       = false,
    manualWaypointClearDistance                   = C.MANUAL_CLEAR_DISTANCE_DEFAULT,
    trackedQuestAutoRoute                         = false,
    untrackedQuestAutoClear                       = false,
    superTrackedQuestAutoClear                    = false,
    genericAddonBlizzardTakeoverEnabled           = true,
    manualClickQueueMode                          = "replace",
    preserveManualQueuesOnReplace                 = true,

    routingEnabled                                = true,
    routingBackend                                = "direct", -- first-run auto-selects zygor | farstrider | mapzeroth | polestar | dugi | direct
    followGroundPathsWhileFlying                  = false,
    flightMapAssistMarker                         = true,
    flightMapAutoTakeMode                         = C.FLIGHT_MAP_AUTO_TAKE_DISABLED,
    flightMapCatalogEnabled                       = true,
    flightMapCatalogCollapsed                     = false,
    flightMapCatalogSide                          = "auto",
    flightMapCatalogFontSize                      = C.FLIGHT_MAP_CATALOG_FONT_SIZE_DEFAULT,
    flightMapCatalogFavorites                     = {},
    flightMapCatalogRecent                        = {},
    flightMapCatalogRecentMax                     = 12,
    combatHideMode                                = C.COMBAT_HIDE_MODE_DISABLED,
    startupHelpMode                               = C.STARTUP_HELP_MODE_CHARACTER,
    startupWhatsNewMode                           = C.STARTUP_HELP_MODE_ACCOUNT,
    resumeManualRoute                             = true,
    arrowSkin                                     = C.SKIN_AWP_MODERN,
    arrowScale                                    = C.SCALE_DEFAULT,
    specialTravelDisplayMode                      = "replace_arrow", -- "replace_arrow" | "companion_icon"
    specialTravelButtonScale                      = C.SCALE_DEFAULT,

    guideTrackerViewerDockMode                    = "tracker",
    guideTrackerViewerPosition                    = nil, -- { point, relPoint, x, y }
    guideTrackerViewerNativeWarningPopup          = true,
    guideTrackerViewerZygorEnabled                = false,
    guideTrackerViewerZygorHideNative             = false,
    guideTrackerViewerPolestarEnabled             = false,
    guideTrackerViewerPolestarHideNative          = false,
    guideTrackerViewerPolestarChatOutputOnChange  = false,
    guideTrackerViewerPolestarChatTextColorMode   = C.WORLD_OVERLAY_COLOR_AUTO,
    guideTrackerViewerPolestarChatTextCustomColor = DEFAULT_GUIDE_TRACKER_VIEWER_TEXT_COLOR,
    guideTrackerViewerPolestarChatStickySummary   = C.ZYGOR_STEP_CHAT_STICKY_TITLES,
    guideTrackerViewerRXPEnabled                  = false,
    guideTrackerViewerRXPHideNative               = false,
    guideTrackerViewerRXPChatOutputOnChange       = false,
    guideTrackerViewerRXPChatTextColorMode        = C.WORLD_OVERLAY_COLOR_AUTO,
    guideTrackerViewerRXPChatTextCustomColor      = DEFAULT_GUIDE_TRACKER_VIEWER_TEXT_COLOR,
    guideTrackerViewerRXPChatStickySummary        = C.ZYGOR_STEP_CHAT_STICKY_TITLES,
    guideTrackerViewerDugiEnabled                 = false,
    guideTrackerViewerDugiHideNative              = false,
    guideTrackerViewerDugiChatOutputOnChange      = false,
    guideTrackerViewerDugiChatTextColorMode       = C.WORLD_OVERLAY_COLOR_AUTO,
    guideTrackerViewerDugiChatTextCustomColor     = DEFAULT_GUIDE_TRACKER_VIEWER_TEXT_COLOR,
    guideTrackerViewerDugiChatStickySummary       = C.ZYGOR_STEP_CHAT_STICKY_TITLES,
    guideTrackerViewerZygorChatOutputOnChange     = false,
    guideTrackerViewerZygorChatTextColorMode      = C.WORLD_OVERLAY_COLOR_AUTO,
    guideTrackerViewerZygorChatTextCustomColor    = DEFAULT_GUIDE_TRACKER_VIEWER_TEXT_COLOR,
    guideTrackerViewerZygorChatStickySummary      = C.ZYGOR_STEP_CHAT_STICKY_TITLES,

    controllerEnabled                             = true,
    minimapButtonEnabled                          = true,
    minimapButtonPosition                         = nil, -- { point, relPoint, x, y }
    -- manualAuthority is the persisted authority record, nil by default
    -- and only set when there is an active manual route to resume.
}

for _, provider in ipairs(C.GUIDE_PROVIDERS) do
    local prefix = "guideTrackerViewer" .. provider.suffix
    DB_DEFAULTS[prefix .. "Enabled"] = false
    DB_DEFAULTS[prefix .. "HideNative"] = false
    if provider.key == "questierouter" then
        DB_DEFAULTS[prefix .. "ShowBanner"] = false
        DB_DEFAULTS[prefix .. "VisibleTasks"] = 1
    end
    DB_DEFAULTS[prefix .. "ChatOutputOnChange"] = false
    DB_DEFAULTS[prefix .. "ChatTextColorMode"] = C.WORLD_OVERLAY_COLOR_AUTO
    DB_DEFAULTS[prefix .. "ChatStickySummary"] = C.ZYGOR_STEP_CHAT_STICKY_TITLES
    for field, value in pairs(VIEWER_APPEARANCE_DEFAULTS) do
        DB_DEFAULTS[prefix .. field] = type(value) == "table" and CopyOverlayColor(value) or value
    end
    DB_DEFAULTS[prefix .. "ChatTextCustomColor"] = CopyOverlayColor(DEFAULT_GUIDE_TRACKER_VIEWER_TEXT_COLOR)
end

local OVERLAY_SETTING_DEFS = {
    worldOverlayEnabled = { default = true, kind = "boolean" },
    worldOverlayFadeOnHover = { default = true, kind = "boolean" },
    worldOverlayContextDisplayMode = {
        default = C.WORLD_OVERLAY_CONTEXT_DISPLAY_DIAMOND_ICON,
        kind = "string",
        values = C.WORLD_OVERLAY_CONTEXT_DISPLAY_MODES,
    },
    worldOverlayPinpointDistance = { default = 35, kind = "number", min = 25, max = 500, step = 5 },
    worldOverlayHideDistance = { default = 0, kind = "number", min = 0, max = 500, step = 5 },
    worldOverlayUseMeters = { default = false, kind = "boolean" },
    worldOverlayWaypointMode = { default = C.WORLD_OVERLAY_WAYPOINT_MODE_FULL, kind = "string", values = C.WORLD_OVERLAY_WAYPOINT_MODES },
    worldOverlayWaypointSize = { default = 1, kind = "number", min = 0.5, max = 5, step = 0.1 },
    worldOverlayWaypointSizeMin = { default = 0.75, kind = "number", min = 0.125, max = 1, step = 0.125 },
    worldOverlayWaypointSizeMax = { default = 1, kind = "number", min = 1, max = 2, step = 0.1 },
    worldOverlayWaypointOpacity = { default = 1, kind = "number", min = 0.1, max = 1, step = 0.1 },
    worldOverlayWaypointOffsetY = { default = -25, kind = "number", min = -200, max = 200, step = 5 },
    worldOverlayBeaconStyle = { default = C.WORLD_OVERLAY_BEACON_STYLE_DISTANCE, kind = "string", values = C.WORLD_OVERLAY_BEACON_STYLES },
    worldOverlayBeaconBaseDistance = { default = 75, kind = "number", min = 5, max = 500, step = 5 },
    worldOverlayBeaconOpacity = { default = 1, kind = "number", min = 0.1, max = 1, step = 0.1 },
    worldOverlayBeaconBaseOffsetY = { default = 25, kind = "number", min = -200, max = 200, step = 5 },
    worldOverlayInfoTextSize = { default = 1, kind = "number", min = 0.1, max = 2, step = 0.1 },
    worldOverlayInfoTextOpacity = { default = 1, kind = "number", min = 0, max = 1, step = 0.1 },
    worldOverlaySubtextOpacity = { default = 0.7, kind = "number", min = 0, max = 1, step = 0.1 },
    worldOverlayFooterText = {
        default = C.WORLD_OVERLAY_INFO_ALL,
        kind = "string",
        values = {
            [C.WORLD_OVERLAY_INFO_ALL] = true,
            [C.WORLD_OVERLAY_INFO_DISTANCE] = true,
            [C.WORLD_OVERLAY_INFO_ARRIVAL] = true,
            [C.WORLD_OVERLAY_INFO_DESTINATION] = true,
            [C.WORLD_OVERLAY_INFO_NONE] = true,
        },
    },
    worldOverlayPinpointMode = { default = C.WORLD_OVERLAY_PINPOINT_MODE_FULL, kind = "string", values = C.WORLD_OVERLAY_PINPOINT_MODES },
    worldOverlayPinpointPlaqueType = {
        default = NS.GetDefaultPlaqueType(),
        kind = "string",
        values = C.WORLD_OVERLAY_PLAQUE_TYPES,
    },
    worldOverlayPinpointSize = { default = 1, kind = "number", min = 0.5, max = 2, step = 0.1 },
    worldOverlayPinpointOpacity = { default = 1, kind = "number", min = 0.1, max = 1, step = 0.1 },
    worldOverlayPinpointAnimatePlaqueEffects = { default = true, kind = "boolean" },
    worldOverlayPinpointAutoVerticalAdjust = { default = true, kind = "boolean" },
    worldOverlayPinpointManualVerticalGap = { default = 75, kind = "number", min = 75, max = 800, step = 1 },
    worldOverlayShowDestinationInfo = { default = true, kind = "boolean" },
    worldOverlayShowExtendedInfo = { default = true, kind = "boolean" },
    worldOverlayShowCoordinateFallback = { default = true, kind = "boolean" },
    worldOverlayShowPinpointArrows = { default = true, kind = "boolean" },
    worldOverlayNavigatorShow = { default = true, kind = "boolean" },
    worldOverlayNavigatorSize = { default = 1, kind = "number", min = 0.5, max = 2, step = 0.1 },
    worldOverlayNavigatorOpacity = { default = 1, kind = "number", min = 0.1, max = 1, step = 0.1 },
    worldOverlayNavigatorDistance = { default = 1, kind = "number", min = 0.1, max = 3, step = 0.1 },
    worldOverlayNavigatorDynamicDistance = { default = true, kind = "boolean" },
    worldOverlayWaypointTextColorMode = { default = C.WORLD_OVERLAY_COLOR_GRAY, kind = "string", values = C.WORLD_OVERLAY_COLOR_MODES },
    worldOverlayWaypointTextCustomColor = { default = DEFAULT_OVERLAY_CUSTOM_COLOR, kind = "color" },
    worldOverlayPinpointTitleColorMode = { default = C.WORLD_OVERLAY_COLOR_AUTO, kind = "string", values = C.WORLD_OVERLAY_COLOR_MODES },
    worldOverlayPinpointTitleCustomColor = { default = DEFAULT_OVERLAY_CUSTOM_COLOR, kind = "color" },
    worldOverlayPinpointSubtextColorMode = { default = C.WORLD_OVERLAY_COLOR_AUTO, kind = "string", values = C.WORLD_OVERLAY_COLOR_MODES },
    worldOverlayPinpointSubtextCustomColor = { default = DEFAULT_OVERLAY_CUSTOM_COLOR, kind = "color" },
    worldOverlayBeaconColorMode = { default = C.WORLD_OVERLAY_COLOR_AUTO, kind = "string", values = C.WORLD_OVERLAY_COLOR_MODES },
    worldOverlayBeaconCustomColor = { default = DEFAULT_OVERLAY_CUSTOM_COLOR, kind = "color" },
    worldOverlayContextDiamondColorMode = { default = C.WORLD_OVERLAY_COLOR_AUTO, kind = "string", values = C.WORLD_OVERLAY_COLOR_MODES },
    worldOverlayContextDiamondCustomColor = { default = DEFAULT_OVERLAY_CUSTOM_COLOR, kind = "color" },
    worldOverlayIconColorMode = { default = C.WORLD_OVERLAY_COLOR_AUTO, kind = "string", values = C.WORLD_OVERLAY_COLOR_MODES },
    worldOverlayIconCustomColor = { default = DEFAULT_OVERLAY_CUSTOM_COLOR, kind = "color" },
    worldOverlayArrowColorMode = { default = C.WORLD_OVERLAY_COLOR_AUTO, kind = "string", values = C.WORLD_OVERLAY_COLOR_MODES },
    worldOverlayArrowCustomColor = { default = DEFAULT_OVERLAY_CUSTOM_COLOR, kind = "color" },
    worldOverlayNavArrowColorMode = { default = C.WORLD_OVERLAY_COLOR_AUTO, kind = "string", values = C.WORLD_OVERLAY_COLOR_MODES },
    worldOverlayNavArrowCustomColor = { default = DEFAULT_OVERLAY_CUSTOM_COLOR, kind = "color" },
    worldOverlayPlaqueColorMode = { default = C.WORLD_OVERLAY_COLOR_AUTO, kind = "string", values = C.WORLD_OVERLAY_COLOR_MODES },
    worldOverlayPlaqueCustomColor = { default = DEFAULT_OVERLAY_CUSTOM_COLOR, kind = "color" },
    worldOverlayAnimatedColorMode = { default = C.WORLD_OVERLAY_COLOR_AUTO, kind = "string", values = C.WORLD_OVERLAY_COLOR_MODES },
    worldOverlayAnimatedCustomColor = { default = DEFAULT_OVERLAY_CUSTOM_COLOR, kind = "color" },
}

NS.Internal = NS.Internal or {}
NS.Internal.DBDefaults = DB_DEFAULTS
NS.Internal.OverlaySettingDefs = OVERLAY_SETTING_DEFS
local GUIDE_ACTION_DEFAULTS = { enabled = false, inline = false, hideNative = false, groupPosition = "below" }
NS.Internal.GuideActionDefaults = GUIDE_ACTION_DEFAULTS

-- Validation uses the same fallback colors as first-run settings.
NS.Internal.SavedColorDefaults = {
    overlay = DEFAULT_OVERLAY_CUSTOM_COLOR,
    viewer = DEFAULT_GUIDE_TRACKER_VIEWER_TEXT_COLOR,
    copy = CopyOverlayColor,
}
