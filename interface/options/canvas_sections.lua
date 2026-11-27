-- ============================================================
-- Settings page renderers
-- ============================================================
--
-- Builds the contents of each settings section using the shared canvas
-- widgets.

local NS = _G.AzerothWaypointNS
local C = NS.Constants
local M = NS.Internal.Interface.canvas
local Data = M.Data or {}
local GuideOption = Data.GUIDE_OPTIONS
local W = M.Widgets or {}
local FW = NS.Internal.Interface.Framework
local CreateFrame = _G.CreateFrame

local Renderers = M.Renderers or {}
M.Renderers = Renderers

local BANNER_PATH = "Interface\\AddOns\\AzerothWaypoint\\media\\banner.png"
local BANNER_W = 768
local BANNER_H = 256
local MEDIA_HELP = Data.MEDIA_HELP or "Interface\\AddOns\\AzerothWaypoint\\media\\help\\"
local ABOUT_SUMMARY = Data.ABOUT_SUMMARY or ""
local ABOUT_DESCRIPTION = Data.ABOUT_DESCRIPTION or ""
local TWITCH_URL = Data.TWITCH_URL or ""
local COLOR_TEXT_DIM = W.COLOR_TEXT_DIM or { 0.72, 0.66, 0.58, 1 }
local PAD = W.PAD or 16
local ChangelogFormat = NS.ChangelogFormat or {}

local SectionHeader = W.SectionHeader
local Spacer = W.Spacer
local AddText = W.AddText
local AddActionButton = W.AddActionButton
local AddToggle = W.AddToggle
local AddSlider = W.AddSlider
local AddDropdown = W.AddDropdown
local AddColorRow = W.AddColorRow
local AddTextInputList = W.AddTextInputList
local AddRecentAddonCallerList = W.AddRecentAddonCallerList
local Default = (NS.Internal.Interface.options or {}).SettingDefault
local ViewerDefault = (NS.Internal.Interface.options or {}).ViewerDefault
local ActionDefault = (NS.Internal.Interface.options or {}).ActionDefault

local function JoinLines(lines)
    return table.concat(lines or {}, "\n")
end

local function GetOpts() return NS.Internal.Interface.options end
local function GetDefs() return NS.Internal.OverlaySettingDefs end

local function AddOverlayColor(label, description, modeKey, colorKey)
    return AddColorRow(label, description,
        function() return NS.GetWorldOverlaySetting(modeKey) end,
        function(value) NS.SetWorldOverlaySetting(modeKey, value) end,
        function() return NS.GetWorldOverlaySetting(colorKey) end,
        function(value) NS.SetWorldOverlaySetting(colorKey, value) end,
        GetOpts().RefreshWorldOverlay, nil, Default(modeKey), Default(colorKey))
end

local function AddActionRow(label, width, onClick, centered)
    if M.RecordSettingAnchor then M.RecordSettingAnchor(label) end
    local button = AddActionButton(label, width, onClick)
    local point = centered and "TOP" or "TOPLEFT"
    button:SetPoint(point, W.GetScrollChild(), point, centered and 0 or PAD, -W.GetCursorY())
    W.SetCursorY(W.GetCursorY() + 32)
end

local function AppearanceDropdownChoices(item)
    local values, order
    if item.choices then values, order = item.choices()
    elseif type(item.values) == "function" then values = item.values()
    else values = item.values end
    values = values or {}
    if not order then
        order = {}
        for key in pairs(values) do order[#order + 1] = key end
        table.sort(order, function(a,b) return tostring(values[a]) < tostring(values[b]) end)
    end
    local result = {}
    for _, key in ipairs(order) do result[#result + 1] = {value=key,text=values[key]} end
    return result
end

local function RenderAppearanceGroup(group)
    SectionHeader(group.label)
    if group.desc then AddText(group.desc, "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 8) end
    for _, item in ipairs(group.items) do
        if M.RecordSettingAnchor then M.RecordSettingAnchor(item._awpSetting) end
        local description = item.desc or "Independent appearance for this AWP area. Overrides are retained while matching is off."
        local control
        if item.type == "toggle" then
            control = AddToggle(item.label, description, item.get, item.set, item.default, "section")
        elseif item.type == "slider" then
            control = AddSlider(item.label, description, item.min, item.max, item.step,
                item.format or function(value) return string.format(item.step < 1 and "%.2f" or "%.0f", value) end, item.get, item.set, item.default, "section")
        elseif item.type == "dropdown" then
            control = AddDropdown(item.label, description, function() return AppearanceDropdownChoices(item) end, item.get, item.set, item.default, "section")
        elseif item.type == "color" then
            control = AddColorRow(item.label, description,
                function() return C.WORLD_OVERLAY_COLOR_CUSTOM end, function() end,
                function() local value=item.get();return {r=value[1],g=value[2],b=value[3]} end,
                function(value) item.set({value.r,value.g,value.b}) end, nil, true, function() return C.WORLD_OVERLAY_COLOR_CUSTOM end, function() local v = item.default(); return {r=v[1],g=v[2],b=v[3]} end)
        elseif item.type == "action" then
            AddActionRow(item.label, 260, item.run)
        end
        if control and item.disabled then
            local enabled = not item.disabled()
            if control.SetEnabled then control:SetEnabled(enabled) else control:EnableMouse(enabled) end
            control:SetAlpha(enabled and 1 or 0.45)
            if control._awpSettingLabel then control._awpSettingLabel:SetAlpha(enabled and 1 or 0.45) end
            if control.reset then control.reset:SetEnabled(enabled) end
        end
    end
end

-- ============================================================
-- About, release notes and integration reference
-- ============================================================

local function RenderAbout()
    local opts = GetOpts()
    local scrollChild = W.GetScrollChild()
    local cursorY = W.GetCursorY()

    local availableW = math.max(1, (scrollChild:GetWidth() or 0) - (PAD * 2))
    local bannerW = math.min(BANNER_W, availableW)
    local bannerH = math.max(1, math.floor(BANNER_H * (bannerW / BANNER_W) + 0.5))
    local bannerX = PAD + math.max(0, math.floor((availableW - bannerW) / 2 + 0.5))

    local banner = scrollChild:CreateTexture(nil, "ARTWORK")
    banner:SetTexture(BANNER_PATH)
    banner:SetSize(bannerW, bannerH)
    banner:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", bannerX, -cursorY)

    W.SetCursorY(cursorY + bannerH + 14)

    local textIndent = 0
    AddText(ABOUT_SUMMARY, "GameFontHighlight", COLOR_TEXT_DIM, textIndent, 8)
    AddText(ABOUT_DESCRIPTION, "GameFontHighlightSmall", COLOR_TEXT_DIM, textIndent, 8)

    local first = AddActionButton("Help", 88, function()
        if type(NS.ShowHelp) == "function" then NS.ShowHelp("overview") end
    end)
    first:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -W.GetCursorY())

    local whatsNew = AddActionButton("What's New", 118, function()
        if type(NS.ShowWhatsNew) == "function" then
            NS.ShowWhatsNew()
        elseif type(NS.ShowChangelog) == "function" then
            NS.ShowChangelog()
        end
    end)
    whatsNew:SetPoint("LEFT", first, "RIGHT", 8, 0)

    local copy = AddActionButton("Copy Twitch", 118, function()
        if opts and type(opts.ShowCopyLinkPopup) == "function" then
            opts.ShowCopyLinkPopup(TWITCH_URL)
        end
    end)
    copy:SetPoint("LEFT", whatsNew, "RIGHT", 8, 0)
    W.SetCursorY(W.GetCursorY() + 40)

    SectionHeader("Key Systems")
    AddText("- Routing backend selection for Farstrider, Mapzeroth, Zygor or use TomTom Directly.",
        "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 5)
    AddText("- Guide provider support for Zygor, Azeroth Pilot Reloaded, and WoWPro.", "GameFontHighlightSmall",
        COLOR_TEXT_DIM, 0, 5)
    AddText("- Manual waypoint queues with create, replace, append, ask, import, activate, and bulk delete tools.",
        "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 5)
    AddText(
        "- Blizzard waypoint adoption for quests, area POIs, vignettes, taxis, dig sites, housing plots, and gossip POIs.",
        "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 5)
    AddText("- External waypoint source support for temporary callers such as SilverDragon and RareScanner.",
        "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 5)
    AddText(
        "- Native 3D overlay with controls for waypoints, pinpoints, navigator arrows, plaques, icons, colors, and footer text.",
        "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 5)
    AddText("- Custom TomTom arrow skins, special travel action replacement, and route-aware travel buttons.",
        "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 5)
    AddText("- Tracked quest routing, untracked quest cleanup, reload restoration, and auto waypoint clearing.",
        "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 5)

    Spacer(8)
    SectionHeader("Links")
    AddText("Twitch: " .. TWITCH_URL, "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 6)
end

local function RenderReleaseNotes()
    SectionHeader("Release Notes")

    local data = NS.CHANGELOG_DATA
    if type(data) ~= "table" or #data == 0 then
        AddText("No changelog data available.", "GameFontHighlight", COLOR_TEXT_DIM, 0, 8)
        return
    end

    if type(ChangelogFormat.FormatReleaseText) == "function" then
        AddText(ChangelogFormat.FormatReleaseText(data, 8), "GameFontHighlight", COLOR_TEXT_DIM, 0, 12)
        return
    end

    AddText("No changelog formatter available.", "GameFontHighlight", COLOR_TEXT_DIM, 0, 8)
end

local function HasLinkUrl(link)
    return type(link) == "table" and type(link.url) == "string" and link.url ~= ""
end

local function GetIntegrationLinks(entry)
    local links = {}
    if type(entry) ~= "table" then
        return links
    end

    if type(entry.links) == "table" then
        for _, link in ipairs(entry.links) do
            if type(link) == "table" then
                links[#links + 1] = {
                    label = tostring(link.label or "Copy Link"),
                    url = type(link.url) == "string" and link.url or "",
                }
            end
        end
    end

    if #links == 0 and (entry.builtin ~= true or (type(entry.url) == "string" and entry.url ~= "")) then
        links[#links + 1] = {
            label = "Copy Link",
            url = type(entry.url) == "string" and entry.url or "",
            fallback = true,
        }
    end

    return links
end

local function GetLinkButtonText(link)
    if type(link) ~= "table" then
        return "Link"
    end
    if link.fallback and not HasLinkUrl(link) then
        return "Link Pending"
    end
    return link.label or "Copy Link"
end

local function AddIntegrationCard(entry)
    if type(entry) ~= "table" then
        return
    end

    local opts = GetOpts()
    local appearance = NS.Internal.Appearance
    local scrollChild = W.GetScrollChild()
    local y = W.GetCursorY()
    local cardW = math.max(240, (scrollChild:GetWidth() or 0) - (PAD * 2))
    local innerW = math.max(160, cardW - 24)

    local card = CreateFrame("Frame", nil, scrollChild)
    card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -y)
    card:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -PAD, -y)

    card.bg = card:CreateTexture(nil, "BACKGROUND")
    card.bg:SetAllPoints()
    card.bg:SetColorTexture(0.030, 0.024, 0.018, 0.76)

    card.border = card:CreateTexture(nil, "BORDER")
    card.border:SetAllPoints()
    card.border:SetColorTexture(0.55, 0.36, 0.18, 0.36)

    -- The shared button skin sits below the button. Put both above the card art.
    local content = CreateFrame("Frame", nil, card)
    content:SetAllPoints(card)

    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -10)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(true)
    title:SetText(entry.name or "Integration")

    local statusText, statusColor = "Unknown", COLOR_TEXT_DIM
    if type(NS.GetIntegrationDisplayStatus) == "function" then
        statusText, statusColor = NS.GetIntegrationDisplayStatus(entry)
    end

    local status = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPRIGHT", content, "TOPRIGHT", -12, -11)
    status:SetJustifyH("RIGHT")
    status:SetWordWrap(true)
    status:SetText(statusText)
    if type(statusColor) == "table" then
        status:SetTextColor(statusColor[1], statusColor[2], statusColor[3], statusColor[4] or 1)
    end

    if appearance then
        appearance.Text(title, nil, "TITLE", "shell")
        appearance.Text(status)
    end
    local statusW = math.min(math.ceil(status:GetUnboundedStringWidth()), math.floor(innerW * 0.45))
    status:SetWidth(statusW)
    title:SetWidth(innerW - statusW - 12)
    local headerH = math.ceil(math.max(18, title:GetStringHeight(), status:GetStringHeight() + 1))
    local summaryTop = 10 + headerH + 7

    local summary = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -summaryTop)
    summary:SetWidth(innerW)
    summary:SetJustifyH("LEFT")
    summary:SetJustifyV("TOP")
    summary:SetWordWrap(true)
    summary:SetTextColor(COLOR_TEXT_DIM[1], COLOR_TEXT_DIM[2], COLOR_TEXT_DIM[3], 1)
    summary:SetText(entry.summary or "")
    if appearance then appearance.Text(summary, nil, "LABEL", "colors", "body") end

    local summaryH = math.max(16, math.ceil(summary:GetStringHeight()))
    local detailsTop = summaryTop + summaryH + 8
    local details = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    details:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -detailsTop)
    details:SetWidth(innerW)
    details:SetJustifyH("LEFT")
    details:SetJustifyV("TOP")
    details:SetWordWrap(true)
    details:SetTextColor(0.88, 0.84, 0.74, 1)

    local bulletLines = {}
    for _, line in ipairs(entry.bullets or {}) do
        bulletLines[#bulletLines + 1] = "- " .. tostring(line)
    end
    details:SetText(JoinLines(bulletLines))
    if appearance then appearance.Text(details, nil, "TEXT") end
    local detailsH = math.max(16, math.ceil(details:GetStringHeight()))

    local links = GetIntegrationLinks(entry)
    local buttonH = 0
    if #links > 0 then
        local gap = 6
        local rows = {}
        local currentRow = { width = 0, height = 0, buttons = {} }

        for _, link in ipairs(links) do
            local hasUrl = HasLinkUrl(link)
            local button = FW.CreatePanelButton(content, { height = 22 })
            button:SetDisplayText(GetLinkButtonText(link))
            button:SetEnabled(hasUrl)
            button:SetScript("OnClick", function()
                if hasUrl and opts and type(opts.ShowCopyLinkPopup) == "function" then
                    opts.ShowCopyLinkPopup(link.url)
                end
            end)

            local label = button.label
            label:SetWordWrap(true)
            local width = math.min(innerW, math.max(104, math.ceil(label:GetUnboundedStringWidth()) + 28))
            button:SetWidth(width)
            local height = math.max(22, math.ceil(label:GetStringHeight()) + 8)
            button:SetHeight(height)

            local rowWidth = currentRow.width > 0 and currentRow.width + gap + width or width
            if rowWidth > innerW then
                rows[#rows + 1] = currentRow
                currentRow = { width = 0, height = 0, buttons = {} }
                rowWidth = width
            end
            currentRow.buttons[#currentRow.buttons + 1] = button
            currentRow.width = rowWidth
            currentRow.height = math.max(currentRow.height, height)
        end
        rows[#rows + 1] = currentRow

        buttonH = 10
        for _, row in ipairs(rows) do
            local x = innerW - row.width
            for _, button in ipairs(row.buttons) do
                button:SetPoint("TOPLEFT", details, "TOPLEFT", x, -(detailsH + buttonH))
                x = x + button:GetWidth() + gap
            end
            buttonH = buttonH + row.height + 4
        end
    end

    local totalH = math.max(98, detailsTop + detailsH + buttonH + 12)
    card:SetHeight(totalH)
    if appearance then appearance.Shell(card, nil, { card.bg, card.border }, nil, "inset") end
    W.SetCursorY(y + totalH + 10)
end

local function RenderIntegrations()
    SectionHeader("Integrations")
    AddText(
        "AzerothWaypoint is built around TomTom and can optionally cooperate with guide addons, route backends, map/POI addons, flight-map helpers, and Blizzard's own map and quest data. This page explains what AWP uses each integration for in normal user terms.",
        "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 10)
    AddText(
        "Use Copy Link when available to copy the addon's page.",
        "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 12)

    local entries, order = {}, {}
    if type(NS.GetIntegrationInfo) == "function" then
        entries, order = NS.GetIntegrationInfo()
    end
    if type(entries) ~= "table" or #entries == 0 then
        AddText("No integration data is available.", "GameFontHighlight", COLOR_TEXT_DIM, 0, 8)
        return
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
            SectionHeader(category)
            for _, entry in ipairs(group) do
                AddIntegrationCard(entry)
            end
            Spacer(2)
        end
    end
end

-- ============================================================
-- Navigation, routing and overlay preferences
-- ============================================================

local function RenderGeneral()
    local opts = GetOpts()

    local appearance = NS.Internal.Appearance
    if appearance then
        SectionHeader("Appearance")
        AddDropdown(Data.UI_STYLE.label, Data.UI_STYLE.desc,
            appearance.GetProviderChoices, appearance.GetPreference, appearance.Select, Default("appearanceProvider"), "section")
        AddText(appearance.GetSelectionStatus(), "GameFontNormalSmall", COLOR_TEXT_DIM, 0, 8)
    end

    SectionHeader("Routing")
    AddToggle("Enable Routing",
        "When enabled, AzerothWaypoint owns the active TomTom arrow and routes manual/guide targets through the selected backend.",
        NS.IsRoutingEnabled, NS.SetRoutingEnabled, Default("routingEnabled"))
    AddDropdown("Routing Backend",
        "Selects the preferred planner. Failed routes try other available planners, then Direct. AWP retries your preference after progress/state changes and announces actual handoffs.",
        opts.CreateRoutingBackendOptions,
        function() return NS.GetDB().routingBackend or "direct" end,
        function(v)
            if type(NS.SetBackend) == "function" then NS.SetBackend(v) else NS.GetDB().routingBackend = v end
        end, Default("routingBackend"))
    AddToggle("Follow ground paths while flying",
        "Keep ordinary ground-path points during actual self-flight. When off, AWP bypasses them only if the backend confirms a valid airborne shortcut. Required stops and flight paths are unchanged; ground-mounted travel follows the path.",
        function() return NS.GetDB().followGroundPathsWhileFlying == true end,
        function(v)
            NS.GetDB().followGroundPathsWhileFlying = v == true
            local record = NS.GetActiveAuthorityRecord()
            if record and NS.RequestRouteNavigationProgress then NS.RequestRouteNavigationProgress(record, "walking_flight_preference") end
        end, Default("followGroundPathsWhileFlying"))
    AddToggle(Data.FLIGHT_ROUTE_MARKER.label, Data.FLIGHT_ROUTE_MARKER.desc,
        function()
            local s = type(NS.GetFlightMapAssistSettings) == "function" and NS.GetFlightMapAssistSettings() or nil
            return s and s.marker == true or false
        end,
        function(v)
            if type(NS.SetFlightMapAssistSetting) == "function" then
                NS.SetFlightMapAssistSetting("marker", v)
            end
        end, Default("flightMapAssistMarker"))
    AddDropdown("Auto Take Flight Paths",
        "Takes the route flight path when you open the flight map. Alt suppresses auto-take for the current interaction.",
        opts.CreateFlightMapAutoTakeModeOptions,
        function()
            local s = type(NS.GetFlightMapAssistSettings) == "function" and NS.GetFlightMapAssistSettings() or nil
            return s and s.autoTakeMode or C.FLIGHT_MAP_AUTO_TAKE_DISABLED
        end,
        function(v)
            if type(NS.SetFlightMapAssistSetting) == "function" then
                NS.SetFlightMapAssistSetting("autoTakeMode", v)
            end
        end, Default("flightMapAutoTakeMode"))
    AddToggle("Show Flight Map Taxi List",
        "Shows a AWP taxi list attached to the flight map with route destination, favorites, recent flights, search, and reachable destinations.",
        function()
            return type(NS.IsFlightMapCatalogEnabled) == "function" and NS.IsFlightMapCatalogEnabled()
        end,
        function(v)
            if type(NS.SetFlightMapCatalogEnabled) == "function" then
                NS.SetFlightMapCatalogEnabled(v)
            end
        end, Default("flightMapCatalogEnabled"))
    AddDropdown("Flight Map Taxi List Side",
        "Chooses which side of the flight map the AWP taxi list attaches to. Auto uses the side with room. The list can also be hidden.",
        opts.CreateFlightMapCatalogSideOptions,
        function()
            local s = type(NS.GetFlightMapCatalogSettings) == "function" and NS.GetFlightMapCatalogSettings() or nil
            return s and s.side or "auto"
        end,
        function(v)
            if type(NS.SetFlightMapCatalogSetting) == "function" then
                NS.SetFlightMapCatalogSetting("side", v)
            end
        end, Default("flightMapCatalogSide"))
    AddSlider("Flight Map Taxi List Text Size",
        "Adjusts text size in the attached flight map taxi list.",
        C.FLIGHT_MAP_CATALOG_FONT_SIZE_MIN,
        C.FLIGHT_MAP_CATALOG_FONT_SIZE_MAX,
        C.FLIGHT_MAP_CATALOG_FONT_SIZE_STEP,
        function(v) return string.format("%d px", math.floor((tonumber(v) or 0) + 0.5)) end,
        function()
            local s = type(NS.GetFlightMapCatalogSettings) == "function" and NS.GetFlightMapCatalogSettings() or nil
            return s and s.fontSize or C.FLIGHT_MAP_CATALOG_FONT_SIZE_DEFAULT
        end,
        function(v)
            if type(NS.SetFlightMapCatalogSetting) == "function" then
                NS.SetFlightMapCatalogSetting("fontSize", v)
            end
        end, Default("flightMapCatalogFontSize"))
    AddDropdown("Hide During Combat",
        "Temporarily hides TomTom, the special travel button, the 3D overlay, or both while you are in combat. Selected displays restore when combat ends.",
        opts.CreateCombatHideModeOptions,
        function() return NS.GetCombatHideMode() end,
        function(v) NS.SetCombatHideMode(v) end, Default("combatHideMode"))
    AddDropdown("Quick-Start Popup",
        "Controls whether the quick-start help guide opens automatically on login.",
        opts.CreateStartupHelpModeOptions,
        function() return NS.GetStartupHelpMode() end,
        function(v) NS.SetStartupHelpMode(v) end, Default("startupHelpMode"))
    AddDropdown("What's New Popup",
        "Controls whether What's New opens automatically on login after addon updates.",
        opts.CreateStartupHelpModeOptions,
        function() return NS.GetStartupWhatsNewMode() end,
        function(v) NS.SetStartupWhatsNewMode(v) end, Default("startupWhatsNewMode"))

    Spacer()
    SectionHeader("Interface")
    AddToggle("Show Minimap Button",
        "Shows the AzerothWaypoint minimap button for quick access to settings, help, queue, and integration controls.",
        function()
            return type(NS.IsMinimapButtonEnabled) == "function" and NS.IsMinimapButtonEnabled()
        end,
        function(v)
            if type(NS.SetMinimapButtonEnabled) == "function" then
                NS.SetMinimapButtonEnabled(v)
            end
        end, Default("minimapButtonEnabled"))

    Spacer()
    SectionHeader("Manual Waypoints")
    AddDropdown("Manual Click Queue Behavior",
        "Controls how map clicks, quest shortcuts, and single TomTom /way commands enter AWP's manual queues.",
        opts.CreateManualClickQueueModeOptions,
        function() return type(NS.GetManualClickQueueMode) == "function" and NS.GetManualClickQueueMode() or "" end,
        function(v) if type(NS.SetManualClickQueueMode) == "function" then NS.SetManualClickQueueMode(v) end end, Default("manualClickQueueMode"))
    AddToggle("Preserve Imported and Multi-Stop Queues",
        "With Replace active, keep imported queues and queues with multiple stops saved at their current stop. A new destination becomes active separately. Turn this off to replace the whole active queue.",
        NS.IsManualQueuePreservationEnabled, NS.SetManualQueuePreservationEnabled, Default("preserveManualQueuesOnReplace"))
    AddToggle("Auto-Clear Manual Waypoints on Arrival",
        "When enabled, AzerothWaypoint clears the active manual destination when you enter the selected range.",
        function() return NS.IsManualWaypointAutoClearEnabled() end,
        function(v) NS.SetManualWaypointAutoClearEnabled(v) end, Default("manualWaypointAutoClear"))
    AddSlider("Manual Waypoint Clear Distance",
        "Clears the active waypoint when you arrive within this many yards.",
        C.MANUAL_CLEAR_DISTANCE_MIN, C.MANUAL_CLEAR_DISTANCE_MAX, C.MANUAL_CLEAR_DISTANCE_STEP,
        function(v) return string.format("%d yd", NS.NormalizeManualWaypointClearDistance(v)) end,
        function() return NS.GetManualWaypointClearDistance() end,
        function(v) NS.SetManualWaypointClearDistance(v) end, Default("manualWaypointClearDistance"))

    Spacer()
    SectionHeader("Quest Tracking")
    AddToggle("Auto-Route Tracked Quests",
        "When enabled, tracking a quest can set it as your current waypoint. Visible guide steps are protected from accidental manual takeover.",
        function() return NS.IsTrackedQuestAutoRouteEnabled() end,
        function(v) NS.SetTrackedQuestAutoRouteEnabled(v) end, Default("trackedQuestAutoRoute"))
    AddToggle("Auto-Clear Untracked Quests",
        "When enabled, untracking a quest removes matching AWP quest waypoints and queue entries. Visible guide steps are protected.",
        function() return NS.IsUntrackedQuestAutoClearEnabled() end,
        function(v) NS.SetUntrackedQuestAutoClearEnabled(v) end, Default("untrackedQuestAutoClear"))
    AddToggle("Auto-Clear Supertracked Quests on Arrival",
        "When enabled, supertracked Blizzard quests use Auto-Clear Manual Waypoints on Arrival and the Manual Waypoint Clear Distance.",
        function() return NS.IsSuperTrackedQuestAutoClearEnabled() end,
        function(v) NS.SetSuperTrackedQuestAutoClearEnabled(v) end, Default("superTrackedQuestAutoClear"))

    Spacer()
    SectionHeader("Addon Waypoint Adoption")
    AddToggle("Adopt Waypoints from Unknown Addons",
        "When enabled, Blizzard waypoint calls from addons without dedicated AWP support can become manual AWP routes unless the addon is blocked.",
        function() return NS.IsGenericAddonBlizzardTakeoverEnabled() end,
        function(v) NS.SetGenericAddonBlizzardTakeoverEnabled(v) end, Default("genericAddonBlizzardTakeoverEnabled"))
    AddRecentAddonCallerList("Detected Addon Callers",
        "Recent unknown addon calls to Blizzard waypoint or supertracking APIs. Allow adds the addon to the allowlist. Block adds the addon to the blocklist.",
        function()
            return type(NS.GetRecentGenericAddonBlizzardTakeoverCallers) == "function"
                and NS.GetRecentGenericAddonBlizzardTakeoverCallers()
                or {}
        end,
        function(addonName)
            if type(NS.AddGenericAddonBlizzardTakeoverListEntry) == "function" then
                NS.AddGenericAddonBlizzardTakeoverListEntry("allowlist", addonName)
            end
        end,
        function(addonName)
            if type(NS.AddGenericAddonBlizzardTakeoverListEntry) == "function" then
                NS.AddGenericAddonBlizzardTakeoverListEntry("blocklist", addonName)
            end
        end,
        function()
            if type(NS.ClearRecentGenericAddonBlizzardTakeoverCallers) == "function" then
                NS.ClearRecentGenericAddonBlizzardTakeoverCallers()
            end
        end)
    AddTextInputList("Addon Allowlist",
        "Addons in this list are allowed to create manual AWP routes through Blizzard waypoint APIs even when unknown adoption is disabled.",
        "Addon folder name",
        function() return NS.GetGenericAddonBlizzardTakeoverList("allowlist") end,
        function(addonName) NS.AddGenericAddonBlizzardTakeoverListEntry("allowlist", addonName) end,
        function(addonName) NS.RemoveGenericAddonBlizzardTakeoverListEntry("allowlist", addonName) end,
        function() NS.ClearGenericAddonBlizzardTakeoverList("allowlist") end)
    AddTextInputList("Addon Blocklist",
        "Addons in this list are never adopted by the generic waypoint takeover layer.",
        "Addon folder name",
        function() return NS.GetGenericAddonBlizzardTakeoverList("blocklist") end,
        function(addonName) NS.AddGenericAddonBlizzardTakeoverListEntry("blocklist", addonName) end,
        function(addonName) NS.RemoveGenericAddonBlizzardTakeoverListEntry("blocklist", addonName) end,
        function() NS.ClearGenericAddonBlizzardTakeoverList("blocklist") end)

    Spacer()
    SectionHeader(Data.GUIDE_VIEWER_ORDER.label)
    AddText(Data.GUIDE_VIEWER_ORDER.desc, "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 8)
    W.AddReorderList(Data.GUIDE_VIEWER_ORDER.label, NS.GetGuideTrackerViewerOrder, NS.SetGuideTrackerViewerOrder,
        NS.GetDefaultGuideTrackerViewerOrder, function(key)
            local provider = C.GUIDE_PROVIDER_BY_KEY[key]
            return provider.label .. (provider.forever and not NS.IsWoWForever() and " (Forever)" or "")
        end)
end

-- ============================================================
-- TomTom arrow settings
-- ============================================================

local function RenderTomTomArrow()
    local opts = GetOpts()

    SectionHeader("Arrow Skin")
    AddToggle("Use Custom Arrow Skin",
        "When enabled, TomTom's Crazy Arrow uses a registered AzerothWaypoint arrow skin.",
        function() return NS.GetSkinChoice() ~= C.SKIN_DEFAULT end,
        function(v)
            if v then
                NS.SetSkinChoice(opts.GetPreferredCustomSkin())
            else
                local skin = NS.GetSkinChoice()
                if skin ~= C.SKIN_DEFAULT then opts.rememberedCustomSkin = skin end
                NS.SetSkinChoice(C.SKIN_DEFAULT)
            end
            opts.ApplySkinAndScale()
        end, Default("useCustomSkin"))
    AddDropdown("Arrow Skin",
        "Select the registered skin to use when the custom TomTom arrow option is enabled.",
        opts.CreateSkinOptions,
        function()
            local skin = NS.GetSkinChoice()
            if skin == C.SKIN_DEFAULT then return opts.GetPreferredCustomSkin() end
            opts.rememberedCustomSkin = skin
            return skin
        end,
        function(v)
            opts.rememberedCustomSkin = v
            if NS.GetSkinChoice() ~= C.SKIN_DEFAULT then
                NS.SetSkinChoice(v)
                opts.ApplySkinAndScale()
            end
        end, Default("customSkin"))

    Spacer()
    SectionHeader("Scale")
    AddSlider("TomTom Arrow Scale",
        "Applies when a custom TomTom skin is enabled.",
        C.SCALE_MIN, C.SCALE_MAX, C.SCALE_STEP,
        function(v) return string.format("%.2fx", NS.NormalizeScale(v)) end,
        function() return NS.GetArrowScale() end,
        function(v)
            NS.SetArrowScale(v); opts.ApplySkinAndScale()
        end, Default("arrowScale"))
    AddSlider("Special Travel Button Scale",
        "Scales the special travel button shown for route legs that require a spell, item, toy, hearthstone, portal, or similar action.",
        C.SCALE_MIN, C.SCALE_MAX, C.SCALE_STEP,
        function(v) return string.format("%.2fx", NS.NormalizeScale(v)) end,
        function() return NS.GetSpecialTravelButtonScale() end,
        function(v)
            NS.SetSpecialTravelButtonScale(v)
            if type(NS.RefreshSpecialActionButtonPresentation) == "function" then
                NS.RefreshSpecialActionButtonPresentation()
            end
        end, Default("specialTravelButtonScale"))
end

-- ============================================================
-- World overlay settings
-- ============================================================

local function RenderOverlay()
    local opts = GetOpts()

    SectionHeader("Display")
    AddToggle("Enable 3D World Overlay",
        "Shows AWP's 3D overlay for waypoint, pinpoint, navigator, and plaque presentation.",
        function() return NS.IsWorldOverlayEnabled() end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayEnabled", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayEnabled"))
    AddToggle("Fade on Hover",
        "Fades the 3D overlay while your mouse is over it.",
        function() return NS.GetWorldOverlaySetting("worldOverlayFadeOnHover") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayFadeOnHover", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayFadeOnHover"))
    AddDropdown("Context Display",
        "Controls the 3D overlay context marker. Context Diamond + Icon shows both layers. Icon Only hides the diamond. Hidden turns both off.",
        opts.CreateWorldOverlayContextDisplayOptions,
        function() return NS.GetWorldOverlaySetting("worldOverlayContextDisplayMode") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayContextDisplayMode", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayContextDisplayMode"))

    Spacer()
    SectionHeader("Colors")
    AddOverlayColor("Context Diamond", "Controls the color of the diamond behind waypoint, pinpoint, and navigator icons.",
        "worldOverlayContextDiamondColorMode", "worldOverlayContextDiamondCustomColor")
    AddOverlayColor("Icons", "Controls the context icon color.",
        "worldOverlayIconColorMode", "worldOverlayIconCustomColor")
end

local function RenderWaypoint()
    local opts   = GetOpts()
    local DEFS   = GetDefs()
    local fmtPct = function(v) return string.format("%.0f%%", v * 100) end
    local fmtPx  = function(v) return string.format("%+d px", v) end
    local fmtDst = opts.FormatWorldOverlayDistance

    SectionHeader("Waypoint")
    AddDropdown("Waypoint",
        "Controls the waypoint beacon. Disabled hides the beacon entirely.",
        opts.CreateWorldOverlayWaypointModeOptions,
        function() return NS.GetWorldOverlaySetting("worldOverlayWaypointMode") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayWaypointMode", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayWaypointMode"))

    local d = DEFS.worldOverlayWaypointSize
    AddSlider("Waypoint Size", "Scales the 3D waypoint frame.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayWaypointSize") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayWaypointSize", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayWaypointSize"))

    d = DEFS.worldOverlayWaypointSizeMin
    AddSlider("Waypoint Min Size", "Sets the minimum dynamic waypoint scale.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayWaypointSizeMin") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayWaypointSizeMin", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayWaypointSizeMin"))

    d = DEFS.worldOverlayWaypointSizeMax
    AddSlider("Waypoint Max Size", "Sets the maximum dynamic waypoint scale.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayWaypointSizeMax") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayWaypointSizeMax", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayWaypointSizeMax"))

    d = DEFS.worldOverlayWaypointOpacity
    AddSlider("Waypoint Opacity", "Controls 3D waypoint opacity.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayWaypointOpacity") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayWaypointOpacity", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayWaypointOpacity"))

    d = DEFS.worldOverlayWaypointOffsetY
    AddSlider("Vertical Offset", "Shifts the waypoint up or down on screen.", d.min, d.max, d.step, fmtPx,
        function() return NS.GetWorldOverlaySetting("worldOverlayWaypointOffsetY") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayWaypointOffsetY", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayWaypointOffsetY"))

    Spacer()
    SectionHeader("Beacon")
    AddDropdown("Beacon Style",
        "Controls the 3D waypoint beacon. Beacon shows the full column. Base Only shows just the base. Distance Based swaps within range. Off hides it.",
        opts.CreateWorldOverlayBeaconStyleOptions,
        function() return NS.GetWorldOverlaySetting("worldOverlayBeaconStyle") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayBeaconStyle", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayBeaconStyle"))

    d = DEFS.worldOverlayBeaconBaseDistance
    AddSlider("Beacon Base Distance", "Controls when Distance Based mode swaps to base only.", d.min, d.max, d.step,
        fmtDst,
        function() return NS.GetWorldOverlaySetting("worldOverlayBeaconBaseDistance") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayBeaconBaseDistance", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayBeaconBaseDistance"))

    d = DEFS.worldOverlayBeaconOpacity
    AddSlider("Beacon Opacity", "Controls the beacon opacity.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayBeaconOpacity") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayBeaconOpacity", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayBeaconOpacity"))

    d = DEFS.worldOverlayBeaconBaseOffsetY
    AddSlider("Base Vertical Offset", "Sets the base-only waypoint vertical position when the column is hidden.", d.min,
        d.max, d.step, fmtPx,
        function() return NS.GetWorldOverlaySetting("worldOverlayBeaconBaseOffsetY") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayBeaconBaseOffsetY", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayBeaconBaseOffsetY"))

    AddToggle("Use Meters instead of Yards", "Formats overlay distance text in meters instead of yards.",
        function() return NS.GetWorldOverlaySetting("worldOverlayUseMeters") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayUseMeters", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayUseMeters"))

    Spacer()
    SectionHeader("Footer Info Text")
    AddDropdown("Footer Text", "Chooses which info appears in the waypoint footer.",
        opts.CreateWorldOverlayInfoOptions,
        function() return NS.GetWorldOverlaySetting("worldOverlayFooterText") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayFooterText", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayFooterText"))

    d = DEFS.worldOverlayInfoTextSize
    AddSlider("Info Text Size", "Scales the waypoint footer info text.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayInfoTextSize") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayInfoTextSize", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayInfoTextSize"))

    d = DEFS.worldOverlayInfoTextOpacity
    AddSlider("Info Text Opacity", "Controls the opacity of the waypoint footer info text.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayInfoTextOpacity") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayInfoTextOpacity", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayInfoTextOpacity"))

    d = DEFS.worldOverlaySubtextOpacity
    AddSlider("Distance/Arrival Time Opacity", "Controls the opacity of the distance and arrival-time text.", d.min,
        d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlaySubtextOpacity") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlaySubtextOpacity", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlaySubtextOpacity"))

    Spacer()
    SectionHeader("Colors")
    AddOverlayColor("Waypoint Text", "Controls the waypoint footer text color.",
        "worldOverlayWaypointTextColorMode", "worldOverlayWaypointTextCustomColor")
    AddOverlayColor("Beacon", "Controls the 3D waypoint beacon color.",
        "worldOverlayBeaconColorMode", "worldOverlayBeaconCustomColor")
end

local function RenderPinpoint()
    local opts   = GetOpts()
    local DEFS   = GetDefs()
    local fmtPct = function(v) return string.format("%.0f%%", v * 100) end
    local fmtPx  = function(v) return string.format("%d px", v + 0.5) end
    local fmtDst = opts.FormatWorldOverlayDistance

    SectionHeader("Pinpoint")
    AddDropdown("Pinpoint Mode",
        "Controls the close-range pinpoint. Full shows everything. Plaque Off hides the title panel. Disabled hides the pinpoint entirely.",
        opts.CreateWorldOverlayPinpointModeOptions,
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointMode") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointMode", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayPinpointMode"))

    local d = DEFS.worldOverlayPinpointDistance
    AddSlider("Show Pinpoint At", "Switches from the large waypoint to the close-range pinpoint within this distance.",
        d.min, d.max, d.step, fmtDst,
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointDistance") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointDistance", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayPinpointDistance"))

    d = DEFS.worldOverlayHideDistance
    AddSlider("Hide Pinpoint At", "Hides the 3D overlay within this arrival range.", d.min, d.max, d.step, fmtDst,
        function() return NS.GetWorldOverlaySetting("worldOverlayHideDistance") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayHideDistance", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayHideDistance"))

    d = DEFS.worldOverlayPinpointSize
    AddSlider("Pinpoint Size", "Scales the 3D pinpoint.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointSize") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointSize", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayPinpointSize"))

    d = DEFS.worldOverlayPinpointOpacity
    AddSlider("Pinpoint Opacity", "Controls 3D pinpoint opacity.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointOpacity") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointOpacity", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayPinpointOpacity"))

    Spacer()
    SectionHeader("Plaque")
    local plaqueControls = {}
    local function RefreshPlaqueControls()
        local plaques = NS.Internal.WorldOverlay.Plaques
        local opacity, thickness = plaques.GetAppearanceSupport(NS.GetWorldOverlaySetting("worldOverlayPinpointPlaqueType"))
        local provider = NS.Internal.Appearance
        local themed = provider and provider.IsEnabled("plaque", "shell")
        for _, entry in ipairs(plaqueControls) do
            local enabled = not themed and (entry.thickness and thickness or not entry.thickness and opacity)
            local control = entry.control
            if control.SetEnabled then control:SetEnabled(enabled) else control:EnableMouse(enabled) end
            control:SetAlpha(enabled and 1 or 0.45)
            if control._awpSettingLabel then control._awpSettingLabel:SetAlpha(enabled and 1 or 0.45) end
            if control.reset then control.reset:SetEnabled(enabled) end
            control:SetValue(entry.get())
            if control.reset and control.reset.Refresh then control.reset.Refresh() end
        end
    end
    AddDropdown("Plaque Style", "Selects the pinpoint plaque. All styles work without an appearance addon. UI Styles can replace this artwork through their plaque shell setting.",
        opts.CreateWorldOverlayPlaqueTypeOptions,
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointPlaqueType") end,
        function(v)
            local saved = NS.SetWorldOverlaySetting("worldOverlayPinpointPlaqueType", v)
            NS.SwapNativePinpointPlaque(saved)
            opts.RefreshWorldOverlay()
            RefreshPlaqueControls()
        end, Default("worldOverlayPinpointPlaqueType"))
    local appearance = NS.Internal.Appearance
    if appearance and appearance.provider and appearance.IsEnabled("plaque", "shell") then
        AddText(appearance.provider.label .. " is styling the plaque. Disable its plaque shell matching to see the selected standalone style.",
            "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 8)
    end
    AddText("Separate opacity: Minimal, Forever, Blizzard, Classic, Clean and Modern. Thickness: Minimal, Clean and Modern. Reset restores the current style's original value. Appearance-addon shells use their own controls.",
        "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 8)
    local function PlaqueSlider(label, key, tooltip, thickness)
        local definition = C.PLAQUE_APPEARANCE_FIELDS[key]
        local function Selected() return NS.GetWorldOverlaySetting("worldOverlayPinpointPlaqueType") end
        local function StyleDefault()
            local defaults = C.PLAQUE_APPEARANCE_DEFAULTS[Selected()]
            return defaults and defaults[key] or (thickness and 1 or 0)
        end
        local function GetValue()
            local settings = NS.GetPlaqueAppearance(Selected())
            return settings and settings[key] or StyleDefault()
        end
        local control = AddSlider(label, tooltip, definition.min, definition.max, definition.step,
            function(value) return string.format(thickness and "%d px" or "%d%%", value) end,
            GetValue,
            function(value)
                NS.SetPlaqueAppearanceSetting(Selected(), key, value)
                opts.RefreshWorldOverlay()
            end,
            StyleDefault)
        plaqueControls[#plaqueControls + 1] = {control = control, thickness = thickness, get = GetValue}
    end
    PlaqueSlider("Plaque Background Opacity", "backgroundOpacity",
        "Changes only this plaque's middle from 0-100% before overall pinpoint fading. Each style remembers its own adjustments; Reset restores its original opacity. Does not fade text or the diamond.")
    PlaqueSlider("Plaque Border Opacity", "borderOpacity",
        "Changes only this plaque's frame. Each style remembers its own adjustments. Shadows and bevel highlights follow the border. Text and background remain independent.")
    PlaqueSlider("Plaque Border Thickness", "borderThickness",
        "Sets this plaque's border to 1-8 pixels for Minimal, Clean and Modern. Each style remembers its own adjustment; Reset restores its original thickness. Text padding grows when needed.", true)
    RefreshPlaqueControls()
    AddToggle("Animate Plaque Effects",
        "Enables supported plaque pulse, glow, and gem effects.",
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointAnimatePlaqueEffects") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointAnimatePlaqueEffects", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayPinpointAnimatePlaqueEffects"))
    AddToggle("Show Destination Info",
        "Shows the title inside the 3D pinpoint plaque.",
        function() return NS.GetWorldOverlaySetting("worldOverlayShowDestinationInfo") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayShowDestinationInfo", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayShowDestinationInfo"))
    AddToggle("Show Extended Info",
        "Shows extended quest or guide context inside the 3D pinpoint plaque.",
        function() return NS.GetWorldOverlaySetting("worldOverlayShowExtendedInfo") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayShowExtendedInfo", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayShowExtendedInfo"))
    AddToggle("Show Coordinate Fallback",
        "Shows x/y coordinates in the pinpoint plaque when no other extended text is available.",
        function() return NS.GetWorldOverlaySetting("worldOverlayShowCoordinateFallback") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayShowCoordinateFallback", v)
            if NS.ScheduleActiveGuidePresentationRefresh then
                NS.ScheduleActiveGuidePresentationRefresh("coordinate_fallback_setting")
            end
            opts.RefreshWorldOverlay()
        end, Default("worldOverlayShowCoordinateFallback"))
    AddToggle("Show Pinpoint Arrows",
        "Shows the animated downward chevrons under the 3D pinpoint context icon.",
        function() return NS.GetWorldOverlaySetting("worldOverlayShowPinpointArrows") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayShowPinpointArrows", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayShowPinpointArrows"))

    d = DEFS.worldOverlayPinpointManualVerticalGap
    AddSlider("Base Pinpoint Height", "Sets the pinpoint's base vertical height when Camera Pinpoint Height is off.",
        d.min, d.max, d.step, fmtPx,
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointManualVerticalGap") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointManualVerticalGap", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayPinpointManualVerticalGap"))
    AddToggle("Camera Pinpoint Height",
        "Automatically adjusts the pinpoint's vertical height when panning the camera higher or lower.",
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointAutoVerticalAdjust") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointAutoVerticalAdjust", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayPinpointAutoVerticalAdjust"))

    Spacer()
    SectionHeader("Colors")
    AddOverlayColor("Pinpoint Title", "Controls the pinpoint title text color.",
        "worldOverlayPinpointTitleColorMode", "worldOverlayPinpointTitleCustomColor")
    AddOverlayColor("Pinpoint Subtext", "Controls the pinpoint subtext color.",
        "worldOverlayPinpointSubtextColorMode", "worldOverlayPinpointSubtextCustomColor")
    AddOverlayColor("Pinpoint Plaque", "Controls the pinpoint plaque panel tint.",
        "worldOverlayPlaqueColorMode", "worldOverlayPlaqueCustomColor")
    AddOverlayColor("Animated Parts", "Controls pinpoint gem and glow colors.",
        "worldOverlayAnimatedColorMode", "worldOverlayAnimatedCustomColor")
    AddOverlayColor("Chevrons", "Controls the animated downward chevron arrows.",
        "worldOverlayArrowColorMode", "worldOverlayArrowCustomColor")
end

local function RenderNavigator()
    local opts = GetOpts()
    local DEFS = GetDefs()
    local fmtPct = function(v) return string.format("%.0f%%", v * 100) end

    SectionHeader("Navigator")
    AddToggle("Enable Navigator", "Shows the off-screen navigator arrow when the active destination leaves the screen.",
        function() return NS.GetWorldOverlaySetting("worldOverlayNavigatorShow") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayNavigatorShow", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayNavigatorShow"))

    local d = DEFS.worldOverlayNavigatorSize
    AddSlider("Navigator Size", "Scales the 3D navigator.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayNavigatorSize") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayNavigatorSize", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayNavigatorSize"))

    d = DEFS.worldOverlayNavigatorOpacity
    AddSlider("Navigator Opacity", "Controls 3D navigator opacity.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayNavigatorOpacity") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayNavigatorOpacity", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayNavigatorOpacity"))

    d = DEFS.worldOverlayNavigatorDistance
    AddSlider("Navigator Distance", "Moves the navigator farther from or closer to screen center.", d.min, d.max, d.step,
        function(v) return string.format("%.1fx", v) end,
        function() return NS.GetWorldOverlaySetting("worldOverlayNavigatorDistance") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayNavigatorDistance", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayNavigatorDistance"))

    AddToggle("Navigator Dynamic Distance", "Adjusts navigator distance based on camera zoom.",
        function() return NS.GetWorldOverlaySetting("worldOverlayNavigatorDynamicDistance") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayNavigatorDynamicDistance", v); opts.RefreshWorldOverlay()
        end, Default("worldOverlayNavigatorDynamicDistance"))

    Spacer()
    SectionHeader("Colors")
    AddOverlayColor("Navigator Arrow", "Controls the navigator arrow color.",
        "worldOverlayNavArrowColorMode", "worldOverlayNavArrowCustomColor")
end

-- ============================================================
-- Guide Viewer settings and provider actions
-- ============================================================

local function RefreshGuideTrackerViewers(providerKey)
    if type(NS.ApplyGuideTrackerViewerSettings) == "function" then NS.ApplyGuideTrackerViewerSettings(providerKey) end
end

local function RenderGuideTrackerViewerAppearance(providerKey)
    local opts = GetOpts()
    local function RefreshAppearance() RefreshGuideTrackerViewers(providerKey) end
    AddText("Appearance settings below apply only to this guide provider's Tracker Viewer.",
        "GameFontNormalSmall", { 0.82, 0.82, 0.82, 1 }, 0, 10)
    do
        local trackerHost = NS.Internal
            and NS.Internal.GuideTrackerViewer
            and NS.Internal.GuideTrackerViewer.Host
        local _, supportText, isWarning
        if trackerHost and type(trackerHost.GetDockingSupportStatus) == "function" then
            _, supportText, isWarning = trackerHost.GetDockingSupportStatus()
        elseif rawget(_G, "KT_ObjectiveTrackerFrame") then
            supportText = "Kaliel's Tracker is active. Your guide Viewers use Kaliel's tracker layout."
            isWarning = false
        else
            supportText = "Blizzard tracker docking is experimental and can cause blocked actions or other UI errors. See Tracker Viewer in AWP Help for supported custom trackers."
            isWarning = true
        end
        AddText(
            supportText,
            "GameFontNormal",
            isWarning and { 1.00, 0.45, 0.25, 1 } or { 0.35, 0.90, 0.45, 1 },
            0,
            12
        )
    end

    AddToggle(GuideOption.nativeWarning.label, GuideOption.nativeWarning.desc,
        function()
            local s = NS.GetGuideTrackerViewerSettings()
            return s.nativeDockWarningPopup ~= false
        end,
        function(v)
            NS.SetGuideTrackerViewerSetting("nativeDockWarningPopup", v)
        end, Default("guideTrackerViewerNativeWarningPopup"))

    local appearance = NS.Internal.Appearance
    local appearanceID = appearance and appearance.GetEffectiveID()
    local page = appearanceID and appearanceID .. ".viewers"
    local themePage = page and M.GetSection and M.GetSection(page)
    if themePage then
        local provider = themePage.provider
        AddActionRow("Open " .. provider.options.label .. " Viewer Styling", 242,
            function() M.SelectOptionsPage(page, "guide." .. providerKey) end, true)
    end

    AddToggle(GuideOption.hideProviderName.label, GuideOption.hideProviderName.desc,
        function() return NS.GetGuideTrackerViewerSettings(providerKey).hideProviderName end,
        function(value)
            NS.SetGuideTrackerViewerProviderSetting(providerKey, "hideProviderName", value)
            RefreshAppearance()
        end, ViewerDefault(providerKey, "HideProviderName"))
    AddToggle(GuideOption.hideGuideTitle.label, GuideOption.hideGuideTitle.desc,
        function() return NS.GetGuideTrackerViewerSettings(providerKey).hideGuideTitle end,
        function(value)
            NS.SetGuideTrackerViewerProviderSetting(providerKey, "hideGuideTitle", value)
            RefreshAppearance()
        end, ViewerDefault(providerKey, "HideGuideTitle"))
    AddToggle(GuideOption.compactActiveIndicator.label, GuideOption.compactActiveIndicator.desc,
        function() return NS.GetGuideTrackerViewerSettings(providerKey).compactActiveIndicator end,
        function(value)
            NS.SetGuideTrackerViewerProviderSetting(providerKey, "compactActiveIndicator", value)
            RefreshAppearance()
        end, ViewerDefault(providerKey, "CompactActiveIndicator"))

    AddDropdown(GuideOption.progressStyle.label, GuideOption.progressStyle.desc,
        opts.CreateGuideTrackerViewerProgressStyleOptions,
        function()
            local s = NS.GetGuideTrackerViewerSettings(providerKey)
            return s.progressStyle
        end,
        function(v)
            NS.SetGuideTrackerViewerProviderSetting(providerKey, "progressStyle", v)
            RefreshAppearance()
        end, ViewerDefault(providerKey, "ProgressStyle"))
    AddColorRow(GuideOption.textColorMode.label, GuideOption.textColorMode.desc,
        function()
            local s = NS.GetGuideTrackerViewerSettings(providerKey)
            return s.textColorMode
        end,
        function(v)
            NS.SetGuideTrackerViewerProviderSetting(providerKey, "textColorMode", v)
        end,
        function()
            local s = NS.GetGuideTrackerViewerSettings(providerKey)
            return s.textCustomColor
        end,
        function(v)
            NS.SetGuideTrackerViewerProviderSetting(providerKey, "textCustomColor", v)
        end,
        RefreshAppearance, nil, ViewerDefault(providerKey, "TextColorMode"), ViewerDefault(providerKey, "TextCustomColor"),
        opts.CreateGuideTrackerViewerColorModeOptions)

    Spacer()
    SectionHeader("Viewer Text Sizes")
    AddToggle(GuideOption.customTextSizes.label, GuideOption.customTextSizes.desc,
        function() return NS.GetGuideTrackerViewerSettings(providerKey).customTextSizes end,
        function(value) NS.SetGuideTrackerViewerProviderSetting(providerKey, "customTextSizes", value); RefreshAppearance() end,
        ViewerDefault(providerKey, "CustomTextSizes"), "section")
    for _, size in ipairs(C.GUIDE_VIEWER_TEXT_SIZES) do
        AddSlider(size.label, "Independent size for this guide. Enable Use custom Viewer text sizes to apply it.",
            size.min, size.max, 1, function(value) return string.format("%d px", value) end,
            function() return NS.GetGuideTrackerViewerSettings(providerKey)[size.key] end,
            function(value)
                NS.SetGuideTrackerViewerProviderSetting(providerKey, size.key, value)
                if NS.GetGuideTrackerViewerSettings(providerKey).customTextSizes then RefreshAppearance() end
            end,
            ViewerDefault(providerKey, size.suffix))
    end

    if Data.HasKalielHeaderSettings() then
        Spacer()
        SectionHeader("Kaliel Header Styling")

        local function AddKalielStyleToggle(label, description, settingKey, styleKey)
            AddToggle(label, description,
                function()
                    local settings = NS.GetGuideTrackerViewerSettings(providerKey)
                    return settings.ktHeaderStyle and settings.ktHeaderStyle[styleKey] == true
                end,
                function(value)
                    NS.SetGuideTrackerViewerProviderSetting(providerKey, settingKey, value)
                    RefreshAppearance()
                end, ViewerDefault(providerKey, settingKey:gsub("^kt", "KT")))
        end

        AddKalielStyleToggle(GuideOption.ktHeaderTexture.label, GuideOption.ktHeaderTexture.desc,
            "ktHeaderTexture", "texture")
        AddKalielStyleToggle(GuideOption.ktHeaderBackgroundColor.label, GuideOption.ktHeaderBackgroundColor.desc,
            "ktHeaderBackgroundColor", "backgroundColor")
        AddKalielStyleToggle(GuideOption.ktHeaderFont.label, GuideOption.ktHeaderFont.desc,
            "ktHeaderFont", "font")
        AddKalielStyleToggle(GuideOption.ktHeaderTextIconColor.label, GuideOption.ktHeaderTextIconColor.desc,
            "ktHeaderTextIconColor", "textIconColor")
        AddKalielStyleToggle(GuideOption.ktHeaderButtonColor.label, GuideOption.ktHeaderButtonColor.desc,
            "ktHeaderButtonColor", "buttonColor")
    end


end

local groupedActionPositions = {
    { value = "above", text = "Above objectives" },
    { value = "below", text = "Below objectives" },
}
local function GetGroupedActionPositions() return groupedActionPositions end

local function RenderGuideActionSettings(providerKey)
    local function Settings() return NS.GetGuideActionSettings(providerKey) end
    local function Set(key, value) NS.SetGuideActionSetting(providerKey, key, value) end
    Spacer()
    SectionHeader("Guide Actions")
    AddToggle("Enable Guide Action Panel", "Show a movable panel when this guide supplies an action for the current step. Keep the guide addon's own action features enabled. Prepared standard actions remain usable during combat; native callback helpers require leaving combat.",
        function() return Settings().enabled end, function(value) Set("enabled", value) end, ActionDefault("enabled"))
    AddToggle("Show Actions Beside Steps", "Show matching action buttons beside Viewer rows, outside combat. The separate action panel retains prepared combat actions. Works on every supported tracker host.",
        function() return Settings().inline end, function(value) Set("inline", value) end, ActionDefault("inline"))
    local viewer = NS.Internal.GuideTrackerViewer
    if viewer and viewer.GuideActions and viewer.GuideActions.HasGroupedActions(providerKey) then
        AddDropdown("Grouped Actions Position", "Center step-wide action buttons above or below the objectives.",
            GetGroupedActionPositions, function() return Settings().groupPosition end,
            function(value) Set("groupPosition", value) end, ActionDefault("groupPosition"))
    end
    AddToggle("Hide Native Action Controls", "Hide this guide's native action controls independently of AWP's panel, inline buttons and filters. With both AWP displays off, you may have no visible action buttons.",
        function() return Settings().hideNative end, function(value) Set("hideNative", value) end, ActionDefault("hideNative"))
    for _, category in ipairs(C.GUIDE_ACTION_TYPES) do
        local key = category.key
        AddToggle("Show " .. category.label, "Include this category in this guide's action panel and inline buttons. Inventory cleanup is off by default and retains native confirmation.",
            function() return Settings().types[key] end, function(value) Set(key, value) end, function() return category.default ~= false end)
    end
    AddActionRow("Reset Guide Action Panel Position", 230, function() Set("position", nil) end)
end

local function RenderGuideTrackerChatSettings(providerKey)
    local function Settings() return NS.GetGuideTrackerViewerProviderSettings(providerKey) end
    local function Set(key, value) NS.SetGuideTrackerViewerProviderSetting(providerKey, key, value) end
    Spacer()
    SectionHeader("Chat Step Display")
    AddToggle(GuideOption.chatOutputOnChange.label, GuideOption.chatOutputOnChange.desc,
        function() return Settings().chatOutputOnChange end,
        function(value) Set("chatOutputOnChange", value) end, ViewerDefault(providerKey, "ChatOutputOnChange"))
    AddColorRow(GuideOption.chatTextColorMode.label, GuideOption.chatTextColorMode.desc,
        function() return Settings().chatTextColorMode end,
        function(value) Set("chatTextColorMode", value) end,
        function() return Settings().chatTextCustomColor end,
        function(value) Set("chatTextCustomColor", value) end, nil, nil, ViewerDefault(providerKey, "ChatTextColorMode"), ViewerDefault(providerKey, "ChatTextCustomColor"))
    AddDropdown(GuideOption.chatStickySummary.label, GuideOption.chatStickySummary.desc,
        GetOpts().CreateGuideStepChatStickySummaryOptions,
        function() return Settings().chatStickySummary end,
        function(value) Set("chatStickySummary", value) end, ViewerDefault(providerKey, "ChatStickySummary"))
end

local function RenderZygor()
    local opts = GetOpts()

    SectionHeader("Zygor Guides Viewer")
    AddToggle("Show Only Guide Steps Until Mouseover",
        "Keeps the visible guide step rows on screen while fading out the rest of Zygor's guide frame until you mouse over it.",
        function() return NS.IsGuideStepsOnlyHoverEnabled() end,
        function(v)
            NS.SetGuideStepsOnlyHoverEnabled(v); opts.RefreshViewerChromeMode()
        end, Default("guideStepsOnlyHover"))
    AddDropdown("Hide Step Backgrounds Until Mouseover",
        "Controls which guide step row backgrounds are hidden while compact guide mode is active.",
        opts.CreateGuideStepBackgroundHoverOptions,
        function() return NS.GetGuideStepBackgroundsHoverMode() end,
        function(v)
            NS.SetGuideStepBackgroundsHoverMode(v); opts.RefreshViewerChromeMode()
        end, Default("guideStepBackgroundsHover"))
    AddToggle("Hide Zygor's Native Frame",
        "Hide Zygor's full-size viewer while keeping guide state, waypoints, guide picker, and settings active.",
        function()
            local s = NS.GetGuideTrackerViewerSettings("zygor")
            return s.hideZygorFrame
        end,
        function(v)
            NS.SetGuideTrackerViewerProviderSetting("zygor", "hideNative", v)
            RefreshGuideTrackerViewers()
        end, ViewerDefault("zygor", "HideNative"))
end

local function RenderDugi()
    SectionHeader("Dugi Guides")
    AddToggle("Hide Dugi Native Guide Frame",
        "Hides Dugi's floating guide frame at runtime without disabling Dugi. If Anchored Small Frame is enabled in Dugi, AWP leaves it untouched; disable that Dugi setting first.",
        function() return NS.GetGuideTrackerViewerSettings("dugi").hideDugiFrame end,
        function(value)
            NS.SetGuideTrackerViewerProviderSetting("dugi", "hideNative", value)
            RefreshGuideTrackerViewers("dugi")
        end, ViewerDefault("dugi", "HideNative"), "section")

    if type(NS.GetDugiNativeFrameHideStatus) == "function" then
        local status, message = NS.GetDugiNativeFrameHideStatus()
        AddText(message, "GameFontNormalSmall",
            status == "anchored" and { 1, 0.65, 0.2, 1 } or { 0.75, 0.75, 0.75, 1 }, 0, 10)
    end

end

local function RenderRXP()
    SectionHeader("RestedXP Guides")
    AddToggle("Hide RestedXP Native Guide Frames", "Cloak guide windows without pausing RestedXP. Item, target and party controls remain available.",
        function() return NS.GetGuideTrackerViewerSettings("rxp").hideNative end,
        function(value) NS.SetGuideTrackerViewerProviderSetting("rxp", "hideNative", value); RefreshGuideTrackerViewers() end, ViewerDefault("rxp", "HideNative"))
end

function M.RenderAppearanceSection(section, surface)
    local provider = section.provider
    if section.picker then
        SectionHeader(section.label)
        AddDropdown(section.picker, section.desc, function() return section.choices end,
            function() return surface end, function(value) M.SelectOptionsPage(section.key, value) end)
        Spacer()
    else
        if provider.GetStatus then
            local status, reason = provider.GetStatus()
            local message = reason or status and "Following: " .. status
            if message then AddText(message, "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 8) end
        end
    end
    for _, group in ipairs(provider.GetOptionGroups(surface or "overview")) do
        RenderAppearanceGroup(group)
    end
end

-- ============================================================
-- Settings page registration
-- ============================================================

Renderers.about = RenderAbout
Renderers.release = RenderReleaseNotes
Renderers.integrations = RenderIntegrations
Renderers.general = RenderGeneral
Renderers.controller = function()
    local pad = NS.Internal.Controller
    SectionHeader("Controller")
    AddToggle("Enable AWP Controller Support", "Uses Forever's native navigation for AWP windows and guide steps. Your controller layout and existing tracker shortcut are preserved.",
        function() return NS.GetDB().controllerEnabled ~= false end, NS.SetControllerEnabled, Default("controllerEnabled"))
    AddText("Assign optional shortcuts under the AzerothWaypoint section of the game's key bindings: Navigate AWP Guides, Open AWP Menu, and Use Active Guide Action. AWP assigns no buttons automatically.", "GameFontHighlightSmall", COLOR_TEXT_DIM)
    SectionHeader("Guide Actions")
    AddText("While an AWP step has controller focus, press the right stick to use its action. Several actions open a picker. More actions opens the step's existing menu. Focusing a step does not activate its guide.", "GameFontHighlightSmall", COLOR_TEXT_DIM)
    AddText("The optional Use Active Guide Action shortcut can use the item or spell prepared before combat. If the guide changes in combat, the indicator still names the prepared action; its replacement is prepared after combat. Ambiguous steps do not prepare a combat shortcut.", "GameFontHighlightSmall", COLOR_TEXT_DIM)
    AddActionRow("Navigate AWP Guides", 230, function() if pad then pad.NavigateGuides() end end)
    AddActionRow("Navigate Guide Action Panels", 230, function() if pad then pad.NavigateGuides(true) end end)
    AddActionRow("Controller Diagnostics", 230, function() if pad then pad.Diagnostics() end end)
end
Renderers.tomtom = RenderTomTomArrow
Renderers.overlay = RenderOverlay
Renderers.waypoint = RenderWaypoint
Renderers.pinpoint = RenderPinpoint
Renderers.navigator = RenderNavigator
Renderers.zygor = RenderZygor
Renderers.dugi = RenderDugi
Renderers.rxp = RenderRXP
for _, key in ipairs({ "apr", "wowpro", "questierouter" }) do
    local providerKey = key
    Renderers[providerKey] = function()
        local definition = C.GUIDE_PROVIDER_BY_KEY[providerKey]
        SectionHeader(definition.title)
        AddToggle("Hide Native Guide Frame", "Cloak the native guide without stopping its engine. Required action controls must be covered before the native guide is hidden.",
            function() return NS.GetGuideTrackerViewerProviderSettings(providerKey).hideNative end,
            function(value) NS.SetGuideTrackerViewerProviderSetting(providerKey, "hideNative", value); RefreshGuideTrackerViewers(providerKey) end, ViewerDefault(providerKey, "HideNative"))
        AddText(providerKey == "questierouter" and "QuestieRouter dynamically orders tasks. Choose Task pins an eligible task; Return to Automatic Order releases it. Native Task Actions includes skipping that task's quests. Progress counts completed quests, not fixed steps."
            or providerKey == "apr" and "Next and the header checkbox use APR's native Skip Step. Back uses APR's native undo. Route selection stays in APR's route browser."
            or "Back recovers an unambiguous missing quest acceptance, otherwise asks for an earlier step. WoWPro rechecks quest progress. Skipping dependent steps requires confirmation.",
            "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 8)
        AddActionRow("Open " .. definition.label .. " Guide Browser", 240,
            function() NS.Internal.GuideTrackerViewer.Actions.Run(providerKey, "picker") end)
    end
end
Renderers.polestar = function()
    SectionHeader("Polestar")
    AddToggle("Hide Polestar Native Guide Frame", "Cloak the guide window while keeping its engine, chooser and item controls available.",
        function() return NS.GetGuideTrackerViewerSettings("polestar").hideNative end,
        function(value) NS.SetGuideTrackerViewerProviderSetting("polestar", "hideNative", value); RefreshGuideTrackerViewers() end, ViewerDefault("polestar", "HideNative"))
    AddText("Configure travel routes, class teleports, Walk real paths and route style inside Polestar. AWP uses those preferences.",
        "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 8)
    AddActionRow("Open Polestar Settings", 180, function()
        NS.Internal.PolestarProvider.Action("settings")
    end)
end

local guidePages = {
    viewer = function(provider)
        local key = provider.key
        local function Set(field, value)
            NS.SetGuideTrackerViewerProviderSetting(key, field, value)
            RefreshGuideTrackerViewers(key)
        end
        SectionHeader("Tracker Viewer")
        AddToggle(GuideOption.enabled.label, GuideOption.enabled.desc,
            function() return NS.GetGuideTrackerViewerProviderSettings(key).enabled end,
            function(value) Set("enabled", value) end, ViewerDefault(key, "Enabled"))
        if key == "questierouter" then
            AddSlider("Visible Tasks", "Show this many QuestieRouter tasks in AWP, including the current task.",
                1, C.QUESTIEROUTER_VIEWER_MAX_TASKS, 1, function(value) return tostring(value) end,
                function() return NS.GetGuideTrackerViewerProviderSettings(key).visibleTasks end,
                function(value) Set("visibleTasks", value) end, ViewerDefault(key, "VisibleTasks"))
            AddToggle("Show QuestieRouter Banner", "Show its native zone artwork, guide title and quest progress above the tasks.",
                function() return NS.GetGuideTrackerViewerProviderSettings(key).showBanner end,
                function(value) Set("showBanner", value) end, ViewerDefault(key, "ShowBanner"))
        end
        RenderGuideTrackerViewerAppearance(key)
    end,
    actions = function(provider) RenderGuideActionSettings(provider.key) end,
    chat = function(provider) RenderGuideTrackerChatSettings(provider.key) end,
}
for _, definition in ipairs(C.GUIDE_PROVIDERS) do
    local provider = definition
    for _, page in ipairs(Data.GUIDE_PAGES) do
        local render = guidePages[page.id]
        Renderers[provider.key .. "." .. page.id] = function() render(provider) end
    end
end
