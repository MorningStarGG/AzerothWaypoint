local NS = _G.AzerothWaypointNS
local C = NS.Constants
local M = NS.Internal.Interface.canvas
local Data = M.Data or {}
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

local function JoinLines(lines)
    return table.concat(lines or {}, "\n")
end

local function GetOpts() return NS.Internal.Interface.options end
local function GetDefs() return NS.Internal.OverlaySettingDefs end

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

local function EstimateLinkButtonWidth(text)
    text = tostring(text or "")
    return math.max(104, math.min(178, (#text * 6) + 28))
end

local function AddIntegrationCard(entry)
    if type(entry) ~= "table" then
        return
    end

    local opts = GetOpts()
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

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
    title:SetPoint("RIGHT", card, "RIGHT", -150, 0)
    title:SetJustifyH("LEFT")
    title:SetText(entry.name or "Integration")

    local statusText, statusColor = "Unknown", COLOR_TEXT_DIM
    if type(NS.GetIntegrationDisplayStatus) == "function" then
        statusText, statusColor = NS.GetIntegrationDisplayStatus(entry)
    end

    local status = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -11)
    status:SetJustifyH("RIGHT")
    status:SetText(statusText)
    if type(statusColor) == "table" then
        status:SetTextColor(statusColor[1], statusColor[2], statusColor[3], statusColor[4] or 1)
    end

    local summary = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
    summary:SetWidth(innerW)
    summary:SetJustifyH("LEFT")
    summary:SetJustifyV("TOP")
    summary:SetWordWrap(true)
    summary:SetTextColor(COLOR_TEXT_DIM[1], COLOR_TEXT_DIM[2], COLOR_TEXT_DIM[3], 1)
    summary:SetText(entry.summary or "")

    local summaryH = math.max(16, math.ceil(summary:GetStringHeight() or summary:GetHeight() or 16))
    local details = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    details:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -8)
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
    local detailsH = math.max(16, math.ceil(details:GetStringHeight() or details:GetHeight() or 16))

    local links = GetIntegrationLinks(entry)
    local buttonH = 0
    if #links > 0 then
        local gap = 6
        local lineH = 26
        local rows = {}
        local currentRow = { width = 0, buttons = {} }

        for _, linkData in ipairs(links) do
            local text = GetLinkButtonText(linkData)
            local width = EstimateLinkButtonWidth(text)
            width = math.min(width, innerW)
            local projectedWidth = currentRow.width > 0 and (currentRow.width + gap + width) or width
            if currentRow.width > 0 and projectedWidth > innerW then
                rows[#rows + 1] = currentRow
                currentRow = { width = 0, buttons = {} }
                projectedWidth = width
            end
            currentRow.buttons[#currentRow.buttons + 1] = {
                text = text,
                width = width,
                link = linkData,
            }
            currentRow.width = projectedWidth
        end
        if #currentRow.buttons > 0 then
            rows[#rows + 1] = currentRow
        end

        for rowIndex, rowData in ipairs(rows) do
            local x = math.max(innerW - (rowData.width or 0), 0)
            for _, buttonData in ipairs(rowData.buttons or {}) do
                local linkData = buttonData.link
                local hasUrl = HasLinkUrl(linkData)

                local button = FW.CreatePanelButton(card)
                button:SetSize(buttonData.width, 22)
                button:SetPoint("TOPLEFT", details, "BOTTOMLEFT", x, -10 - ((rowIndex - 1) * lineH))
                button:SetDisplayText(buttonData.text)
                button:SetEnabled(hasUrl)
                button:SetScript("OnClick", function()
                    if hasUrl and opts and type(opts.ShowCopyLinkPopup) == "function" then
                        opts.ShowCopyLinkPopup(linkData.url)
                    end
                end)

                x = x + buttonData.width + gap
            end
        end

        buttonH = 10 + (#rows * lineH)
    end

    local totalH = 10 + 18 + 7 + summaryH + 8 + detailsH + buttonH + 12
    totalH = math.max(totalH, 98)
    card:SetHeight(totalH)
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

local function RenderGeneral()
    local opts = GetOpts()

    SectionHeader("Routing")
    AddToggle("Enable Routing",
        "When enabled, AzerothWaypoint owns the active TomTom arrow and routes manual/guide targets through the selected backend.",
        function() return NS.IsRoutingEnabled() end,
        function(v)
            NS.GetDB().routingEnabled = v and true or false
            if type(NS.RecomputeCarrier) == "function" then NS.RecomputeCarrier() end
        end)
    AddDropdown("Routing Backend",
        "Selects the route planner. Using TomTom directly is always available.",
        opts.CreateRoutingBackendOptions,
        function() return NS.GetDB().routingBackend or "direct" end,
        function(v)
            if type(NS.SetBackend) == "function" then NS.SetBackend(v) else NS.GetDB().routingBackend = v end
        end)
    AddToggle("Show Flight Map Route Marker",
        "When a route uses a flight path, marks the intended destination on the flight map.",
        function()
            local s = type(NS.GetFlightMapAssistSettings) == "function" and NS.GetFlightMapAssistSettings() or nil
            return s and s.marker == true or false
        end,
        function(v)
            if type(NS.SetFlightMapAssistSetting) == "function" then
                NS.SetFlightMapAssistSetting("marker", v)
            end
        end)
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
        end)
    AddToggle("Show Flight Map Taxi List",
        "Shows a AWP taxi list attached to the flight map with route destination, favorites, recent flights, search, and reachable destinations.",
        function()
            return type(NS.IsFlightMapCatalogEnabled) == "function" and NS.IsFlightMapCatalogEnabled()
        end,
        function(v)
            if type(NS.SetFlightMapCatalogEnabled) == "function" then
                NS.SetFlightMapCatalogEnabled(v)
            end
        end)
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
        end)
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
        end)
    AddDropdown("Hide During Combat",
        "Temporarily hides TomTom, the special travel button, the 3D overlay, or both while you are in combat. Selected displays restore when combat ends.",
        opts.CreateCombatHideModeOptions,
        function() return NS.GetCombatHideMode() end,
        function(v) NS.SetCombatHideMode(v) end)
    AddDropdown("Quick-Start Popup",
        "Controls whether the quick-start help guide opens automatically on login.",
        opts.CreateStartupHelpModeOptions,
        function() return NS.GetStartupHelpMode() end,
        function(v) NS.SetStartupHelpMode(v) end)
    AddDropdown("What's New Popup",
        "Controls whether What's New opens automatically on login after addon updates.",
        opts.CreateStartupHelpModeOptions,
        function() return NS.GetStartupWhatsNewMode() end,
        function(v) NS.SetStartupWhatsNewMode(v) end)

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
        end)

    Spacer()
    SectionHeader("Manual Waypoints")
    AddDropdown("Manual Click Queue Behavior",
        "Controls how map pins, POI clicks, and manual waypoints are added to the AWP queue system.",
        opts.CreateManualClickQueueModeOptions,
        function() return type(NS.GetManualClickQueueMode) == "function" and NS.GetManualClickQueueMode() or "" end,
        function(v) if type(NS.SetManualClickQueueMode) == "function" then NS.SetManualClickQueueMode(v) end end)
    AddToggle("Auto-Clear Manual Waypoints on Arrival",
        "When enabled, AzerothWaypoint clears the active manual destination when you enter the selected range.",
        function() return NS.IsManualWaypointAutoClearEnabled() end,
        function(v) NS.SetManualWaypointAutoClearEnabled(v) end)
    AddSlider("Manual Waypoint Clear Distance",
        "Clears the active waypoint when you arrive within this many yards.",
        C.MANUAL_CLEAR_DISTANCE_MIN, C.MANUAL_CLEAR_DISTANCE_MAX, C.MANUAL_CLEAR_DISTANCE_STEP,
        function(v) return string.format("%d yd", NS.NormalizeManualWaypointClearDistance(v)) end,
        function() return NS.GetManualWaypointClearDistance() end,
        function(v) NS.SetManualWaypointClearDistance(v) end)

    Spacer()
    SectionHeader("Quest Tracking")
    AddToggle("Auto-Route Tracked Quests",
        "When enabled, tracking a quest can set it as your current waypoint. Visible guide steps are protected from accidental manual takeover.",
        function() return NS.IsTrackedQuestAutoRouteEnabled() end,
        function(v) NS.SetTrackedQuestAutoRouteEnabled(v) end)
    AddToggle("Auto-Clear Untracked Quests",
        "When enabled, untracking a quest removes matching AWP quest waypoints and queue entries. Visible guide steps are protected.",
        function() return NS.IsUntrackedQuestAutoClearEnabled() end,
        function(v) NS.SetUntrackedQuestAutoClearEnabled(v) end)
    AddToggle("Auto-Clear Supertracked Quests on Arrival",
        "When enabled, supertracked Blizzard quests use Auto-Clear Manual Waypoints on Arrival and the Manual Waypoint Clear Distance.",
        function() return NS.IsSuperTrackedQuestAutoClearEnabled() end,
        function(v) NS.SetSuperTrackedQuestAutoClearEnabled(v) end)

    Spacer()
    SectionHeader("Addon Waypoint Adoption")
    AddToggle("Adopt Waypoints from Unknown Addons",
        "When enabled, Blizzard waypoint calls from addons without dedicated AWP support can become manual AWP routes unless the addon is blocked.",
        function() return NS.IsGenericAddonBlizzardTakeoverEnabled() end,
        function(v) NS.SetGenericAddonBlizzardTakeoverEnabled(v) end)
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
end

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
        end)
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
        end)

    Spacer()
    SectionHeader("Scale")
    AddSlider("TomTom Arrow Scale",
        "Applies when a custom TomTom skin is enabled.",
        C.SCALE_MIN, C.SCALE_MAX, C.SCALE_STEP,
        function(v) return string.format("%.2fx", NS.NormalizeScale(v)) end,
        function() return NS.GetArrowScale() end,
        function(v)
            NS.SetArrowScale(v); opts.ApplySkinAndScale()
        end)
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
        end)
end

local function RenderOverlay()
    local opts = GetOpts()

    SectionHeader("Display")
    AddToggle("Enable 3D World Overlay",
        "Shows AWP's 3D overlay for waypoint, pinpoint, navigator, and plaque presentation.",
        function() return NS.IsWorldOverlayEnabled() end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayEnabled", v); opts.RefreshWorldOverlay()
        end)
    AddToggle("Fade on Hover",
        "Fades the 3D overlay while your mouse is over it.",
        function() return NS.GetWorldOverlaySetting("worldOverlayFadeOnHover") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayFadeOnHover", v); opts.RefreshWorldOverlay()
        end)
    AddDropdown("Context Display",
        "Controls the 3D overlay context marker. Context Diamond + Icon shows both layers. Icon Only hides the diamond. Hidden turns both off.",
        opts.CreateWorldOverlayContextDisplayOptions,
        function() return NS.GetWorldOverlaySetting("worldOverlayContextDisplayMode") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayContextDisplayMode", v); opts.RefreshWorldOverlay()
        end)

    Spacer()
    SectionHeader("Colors")
    AddColorRow("Context Diamond",
        "Controls the color of the diamond behind waypoint, pinpoint, and navigator icons.",
        function() return NS.GetWorldOverlaySetting("worldOverlayContextDiamondColorMode") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayContextDiamondColorMode", v); opts.RefreshWorldOverlay()
        end,
        function() return NS.GetWorldOverlaySetting("worldOverlayContextDiamondCustomColor") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayContextDiamondCustomColor", v); opts.RefreshWorldOverlay()
        end)
    AddColorRow("Icons",
        "Controls the context icon color.",
        function() return NS.GetWorldOverlaySetting("worldOverlayIconColorMode") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayIconColorMode", v); opts.RefreshWorldOverlay()
        end,
        function() return NS.GetWorldOverlaySetting("worldOverlayIconCustomColor") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayIconCustomColor", v); opts.RefreshWorldOverlay()
        end)
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
        end)

    local d = DEFS.worldOverlayWaypointSize
    AddSlider("Waypoint Size", "Scales the 3D waypoint frame.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayWaypointSize") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayWaypointSize", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayWaypointSizeMin
    AddSlider("Waypoint Min Size", "Sets the minimum dynamic waypoint scale.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayWaypointSizeMin") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayWaypointSizeMin", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayWaypointSizeMax
    AddSlider("Waypoint Max Size", "Sets the maximum dynamic waypoint scale.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayWaypointSizeMax") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayWaypointSizeMax", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayWaypointOpacity
    AddSlider("Waypoint Opacity", "Controls 3D waypoint opacity.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayWaypointOpacity") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayWaypointOpacity", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayWaypointOffsetY
    AddSlider("Vertical Offset", "Shifts the waypoint up or down on screen.", d.min, d.max, d.step, fmtPx,
        function() return NS.GetWorldOverlaySetting("worldOverlayWaypointOffsetY") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayWaypointOffsetY", v); opts.RefreshWorldOverlay()
        end)

    Spacer()
    SectionHeader("Beacon")
    AddDropdown("Beacon Style",
        "Controls the 3D waypoint beacon. Beacon shows the full column. Base Only shows just the base. Distance Based swaps within range. Off hides it.",
        opts.CreateWorldOverlayBeaconStyleOptions,
        function() return NS.GetWorldOverlaySetting("worldOverlayBeaconStyle") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayBeaconStyle", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayBeaconBaseDistance
    AddSlider("Beacon Base Distance", "Controls when Distance Based mode swaps to base only.", d.min, d.max, d.step,
        fmtDst,
        function() return NS.GetWorldOverlaySetting("worldOverlayBeaconBaseDistance") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayBeaconBaseDistance", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayBeaconOpacity
    AddSlider("Beacon Opacity", "Controls the beacon opacity.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayBeaconOpacity") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayBeaconOpacity", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayBeaconBaseOffsetY
    AddSlider("Base Vertical Offset", "Sets the base-only waypoint vertical position when the column is hidden.", d.min,
        d.max, d.step, fmtPx,
        function() return NS.GetWorldOverlaySetting("worldOverlayBeaconBaseOffsetY") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayBeaconBaseOffsetY", v); opts.RefreshWorldOverlay()
        end)

    AddToggle("Use Meters instead of Yards", "Formats overlay distance text in meters instead of yards.",
        function() return NS.GetWorldOverlaySetting("worldOverlayUseMeters") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayUseMeters", v); opts.RefreshWorldOverlay()
        end)

    Spacer()
    SectionHeader("Footer Info Text")
    AddDropdown("Footer Text", "Chooses which info appears in the waypoint footer.",
        opts.CreateWorldOverlayInfoOptions,
        function() return NS.GetWorldOverlaySetting("worldOverlayFooterText") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayFooterText", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayInfoTextSize
    AddSlider("Info Text Size", "Scales the waypoint footer info text.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayInfoTextSize") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayInfoTextSize", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayInfoTextOpacity
    AddSlider("Info Text Opacity", "Controls the opacity of the waypoint footer info text.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayInfoTextOpacity") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayInfoTextOpacity", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlaySubtextOpacity
    AddSlider("Distance/Arrival Time Opacity", "Controls the opacity of the distance and arrival-time text.", d.min,
        d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlaySubtextOpacity") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlaySubtextOpacity", v); opts.RefreshWorldOverlay()
        end)

    Spacer()
    SectionHeader("Colors")
    AddColorRow("Waypoint Text", "Controls the waypoint footer text color.",
        function() return NS.GetWorldOverlaySetting("worldOverlayWaypointTextColorMode") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayWaypointTextColorMode", v); opts.RefreshWorldOverlay()
        end,
        function() return NS.GetWorldOverlaySetting("worldOverlayWaypointTextCustomColor") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayWaypointTextCustomColor", v); opts.RefreshWorldOverlay()
        end)
    AddColorRow("Beacon", "Controls the 3D waypoint beacon color.",
        function() return NS.GetWorldOverlaySetting("worldOverlayBeaconColorMode") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayBeaconColorMode", v); opts.RefreshWorldOverlay()
        end,
        function() return NS.GetWorldOverlaySetting("worldOverlayBeaconCustomColor") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayBeaconCustomColor", v); opts.RefreshWorldOverlay()
        end)
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
        end)

    local d = DEFS.worldOverlayPinpointDistance
    AddSlider("Show Pinpoint At", "Switches from the large waypoint to the close-range pinpoint within this distance.",
        d.min, d.max, d.step, fmtDst,
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointDistance") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointDistance", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayHideDistance
    AddSlider("Hide Pinpoint At", "Hides the 3D overlay within this arrival range.", d.min, d.max, d.step, fmtDst,
        function() return NS.GetWorldOverlaySetting("worldOverlayHideDistance") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayHideDistance", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayPinpointSize
    AddSlider("Pinpoint Size", "Scales the 3D pinpoint.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointSize") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointSize", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayPinpointOpacity
    AddSlider("Pinpoint Opacity", "Controls 3D pinpoint opacity.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointOpacity") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointOpacity", v); opts.RefreshWorldOverlay()
        end)

    Spacer()
    SectionHeader("Plaque")
    AddDropdown("Plaque Style", "Selects the plaque style used for the pinpoint.",
        opts.CreateWorldOverlayPlaqueTypeOptions,
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointPlaqueType") end,
        function(v)
            local saved = NS.SetWorldOverlaySetting("worldOverlayPinpointPlaqueType", v)
            NS.SwapNativePinpointPlaque(saved)
            opts.RefreshWorldOverlay()
        end)
    AddToggle("Animate Plaque Effects",
        "Enables supported plaque pulse, glow, and gem effects.",
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointAnimatePlaqueEffects") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointAnimatePlaqueEffects", v); opts.RefreshWorldOverlay()
        end)
    AddToggle("Show Destination Info",
        "Shows the title inside the 3D pinpoint plaque.",
        function() return NS.GetWorldOverlaySetting("worldOverlayShowDestinationInfo") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayShowDestinationInfo", v); opts.RefreshWorldOverlay()
        end)
    AddToggle("Show Extended Info",
        "Shows extended quest or guide context inside the 3D pinpoint plaque.",
        function() return NS.GetWorldOverlaySetting("worldOverlayShowExtendedInfo") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayShowExtendedInfo", v); opts.RefreshWorldOverlay()
        end)
    AddToggle("Show Coordinate Fallback",
        "Shows x/y coordinates in the pinpoint plaque when no other extended text is available.",
        function() return NS.GetWorldOverlaySetting("worldOverlayShowCoordinateFallback") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayShowCoordinateFallback", v); opts.RefreshWorldOverlay()
        end)
    AddToggle("Show Pinpoint Arrows",
        "Shows the animated downward chevrons under the 3D pinpoint context icon.",
        function() return NS.GetWorldOverlaySetting("worldOverlayShowPinpointArrows") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayShowPinpointArrows", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayPinpointManualVerticalGap
    AddSlider("Base Pinpoint Height", "Sets the pinpoint's base vertical height when Camera Pinpoint Height is off.",
        d.min, d.max, d.step, fmtPx,
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointManualVerticalGap") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointManualVerticalGap", v); opts.RefreshWorldOverlay()
        end)
    AddToggle("Camera Pinpoint Height",
        "Automatically adjusts the pinpoint's vertical height when panning the camera higher or lower.",
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointAutoVerticalAdjust") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointAutoVerticalAdjust", v); opts.RefreshWorldOverlay()
        end)

    Spacer()
    SectionHeader("Colors")
    AddColorRow("Pinpoint Title", "Controls the pinpoint title text color.",
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointTitleColorMode") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointTitleColorMode", v); opts.RefreshWorldOverlay()
        end,
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointTitleCustomColor") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointTitleCustomColor", v); opts.RefreshWorldOverlay()
        end)
    AddColorRow("Pinpoint Subtext", "Controls the pinpoint subtext color.",
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointSubtextColorMode") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointSubtextColorMode", v); opts.RefreshWorldOverlay()
        end,
        function() return NS.GetWorldOverlaySetting("worldOverlayPinpointSubtextCustomColor") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPinpointSubtextCustomColor", v); opts.RefreshWorldOverlay()
        end)
    AddColorRow("Pinpoint Plaque", "Controls the pinpoint plaque panel tint.",
        function() return NS.GetWorldOverlaySetting("worldOverlayPlaqueColorMode") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPlaqueColorMode", v); opts.RefreshWorldOverlay()
        end,
        function() return NS.GetWorldOverlaySetting("worldOverlayPlaqueCustomColor") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayPlaqueCustomColor", v); opts.RefreshWorldOverlay()
        end)
    AddColorRow("Animated Parts", "Controls pinpoint gem and glow colors.",
        function() return NS.GetWorldOverlaySetting("worldOverlayAnimatedColorMode") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayAnimatedColorMode", v); opts.RefreshWorldOverlay()
        end,
        function() return NS.GetWorldOverlaySetting("worldOverlayAnimatedCustomColor") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayAnimatedCustomColor", v); opts.RefreshWorldOverlay()
        end)
    AddColorRow("Chevrons", "Controls the animated downward chevron arrows.",
        function() return NS.GetWorldOverlaySetting("worldOverlayArrowColorMode") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayArrowColorMode", v); opts.RefreshWorldOverlay()
        end,
        function() return NS.GetWorldOverlaySetting("worldOverlayArrowCustomColor") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayArrowCustomColor", v); opts.RefreshWorldOverlay()
        end)
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
        end)

    local d = DEFS.worldOverlayNavigatorSize
    AddSlider("Navigator Size", "Scales the 3D navigator.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayNavigatorSize") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayNavigatorSize", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayNavigatorOpacity
    AddSlider("Navigator Opacity", "Controls 3D navigator opacity.", d.min, d.max, d.step, fmtPct,
        function() return NS.GetWorldOverlaySetting("worldOverlayNavigatorOpacity") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayNavigatorOpacity", v); opts.RefreshWorldOverlay()
        end)

    d = DEFS.worldOverlayNavigatorDistance
    AddSlider("Navigator Distance", "Moves the navigator farther from or closer to screen center.", d.min, d.max, d.step,
        function(v) return string.format("%.1fx", v) end,
        function() return NS.GetWorldOverlaySetting("worldOverlayNavigatorDistance") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayNavigatorDistance", v); opts.RefreshWorldOverlay()
        end)

    AddToggle("Navigator Dynamic Distance", "Adjusts navigator distance based on camera zoom.",
        function() return NS.GetWorldOverlaySetting("worldOverlayNavigatorDynamicDistance") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayNavigatorDynamicDistance", v); opts.RefreshWorldOverlay()
        end)

    Spacer()
    SectionHeader("Colors")
    AddColorRow("Navigator Arrow", "Controls the navigator arrow color.",
        function() return NS.GetWorldOverlaySetting("worldOverlayNavArrowColorMode") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayNavArrowColorMode", v); opts.RefreshWorldOverlay()
        end,
        function() return NS.GetWorldOverlaySetting("worldOverlayNavArrowCustomColor") end,
        function(v)
            NS.SetWorldOverlaySetting("worldOverlayNavArrowCustomColor", v); opts.RefreshWorldOverlay()
        end)
end

local function RenderZygor()
    local opts = GetOpts()
    local function RefreshZygorTrackerViewer()
        if type(NS.ApplyZygorTrackerViewerSettings) == "function" then
            NS.ApplyZygorTrackerViewerSettings()
        end
    end

    SectionHeader("Zygor Guides Viewer")
    AddToggle("Show Only Guide Steps Until Mouseover",
        "Keeps the visible guide step rows on screen while fading out the rest of Zygor's guide frame until you mouse over it.",
        function() return NS.IsGuideStepsOnlyHoverEnabled() end,
        function(v)
            NS.SetGuideStepsOnlyHoverEnabled(v); opts.RefreshViewerChromeMode()
        end)
    AddDropdown("Hide Step Backgrounds Until Mouseover",
        "Controls which guide step row backgrounds are hidden while compact guide mode is active.",
        opts.CreateGuideStepBackgroundHoverOptions,
        function() return NS.GetGuideStepBackgroundsHoverMode() end,
        function(v)
            NS.SetGuideStepBackgroundsHoverMode(v); opts.RefreshViewerChromeMode()
        end)
    AddToggle("Hide Zygor's Native Frame",
        "Hide Zygor's full-size viewer while keeping guide state, waypoints, guide picker, and settings active.",
        function()
            local s = NS.GetZygorTrackerViewerSettings()
            return s.hideZygorFrame
        end,
        function(v)
            NS.SetZygorTrackerViewerSetting("hideZygorFrame", v)
            RefreshZygorTrackerViewer()
        end)

    Spacer()
    SectionHeader("Tracker Viewer")
    AddToggle("Enable Tracker Viewer",
        "Shows Zygor guide steps inside the objective tracker. Supports Blizzard's Objective Tracker and Kaliel's Tracker.",
        function()
            local s = NS.GetZygorTrackerViewerSettings()
            return s.enabled
        end,
        function(v)
            NS.SetZygorTrackerViewerSetting("enabled", v)
            RefreshZygorTrackerViewer()
        end)
    AddDropdown("Tracker Viewer Progress Bar",
        "Controls whether the Tracker Viewer progress bar is square, rounded border, or hidden.",
        opts.CreateZygorTrackerViewerProgressStyleOptions,
        function()
            local s = NS.GetZygorTrackerViewerSettings()
            return s.progressStyle
        end,
        function(v)
            NS.SetZygorTrackerViewerSetting("progressStyle", v)
            RefreshZygorTrackerViewer()
        end)
    AddColorRow("Tracker Viewer Text",
        "Auto uses contextual step colors. Selecting a fixed color forces Tracker Viewer text to the chosen color.",
        function()
            local s = NS.GetZygorTrackerViewerSettings()
            return s.textColorMode
        end,
        function(v)
            NS.SetZygorTrackerViewerSetting("textColorMode", v)
        end,
        function()
            local s = NS.GetZygorTrackerViewerSettings()
            return s.textCustomColor
        end,
        function(v)
            NS.SetZygorTrackerViewerSetting("textCustomColor", v)
        end,
        RefreshZygorTrackerViewer)

    Spacer()
    SectionHeader("Chat Step Display")
    AddToggle("Show Step in Chat on Step Change",
        "Shows the current Zygor step in your own chat when Zygor changes steps. This is local-only and is not sent to other players.",
        function()
            local s = NS.GetZygorStepChatSettings()
            return s.outputOnChange
        end,
        function(v)
            NS.SetZygorStepChatSetting("outputOnChange", v)
        end)
    AddColorRow("Chat Step Text",
        "Auto uses contextual text colors. Selecting a fixed color will force `/awp zygor output` and step-change chat text to the chosen color.",
        function()
            local s = NS.GetZygorStepChatSettings()
            return s.textColorMode
        end,
        function(v)
            NS.SetZygorStepChatSetting("textColorMode", v)
        end,
        function()
            local s = NS.GetZygorStepChatSettings()
            return s.textCustomColor
        end,
        function(v)
            NS.SetZygorStepChatSetting("textCustomColor", v)
        end)
    AddDropdown("Chat Sticky Summary",
        "Controls how active Zygor sticky steps are summarized in your chat step display.",
        opts.CreateZygorStepChatStickySummaryOptions,
        function()
            local s = NS.GetZygorStepChatSettings()
            return s.stickySummary
        end,
        function(v)
            NS.SetZygorStepChatSetting("stickySummary", v)
        end)
end

Renderers.about = RenderAbout
Renderers.release = RenderReleaseNotes
Renderers.integrations = RenderIntegrations
Renderers.general = RenderGeneral
Renderers.tomtom = RenderTomTomArrow
Renderers.overlay = RenderOverlay
Renderers.waypoint = RenderWaypoint
Renderers.pinpoint = RenderPinpoint
Renderers.navigator = RenderNavigator
Renderers.zygor = RenderZygor
