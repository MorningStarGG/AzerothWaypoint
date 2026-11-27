-- ============================================================
-- Guide Viewer colors
-- ============================================================
--
-- Resolves guide action and status colors for tracker rows and chat using the
-- selected viewer settings.

local NS = _G.AzerothWaypointNS
local C = NS.Constants

NS.Internal = NS.Internal or {}
NS.Internal.GuideTrackerViewer = NS.Internal.GuideTrackerViewer or {}

local Styles = {}
NS.Internal.GuideTrackerViewer.Styles = Styles

local STATUS_RGB = {
    incomplete = { 1.00, 1.00, 1.00 },
    passive    = { 0.93, 0.93, 0.80 },
    warning    = { 1.00, 0.82, 0.20 },
    failed     = { 1.00, 0.42, 0.32 },
    impossible = { 1.00, 0.42, 0.32 },
    obsolete   = { 0.55, 0.55, 0.55 },
}

local TIP_RGB = { 0.93, 0.93, 0.80 }
local COMPLETE_RGB = { 0.58, 0.92, 0.52 }

local ACTION_RGB = {
    accept = {1.00, 0.82, 0.30}, turnin = {1.00, 0.82, 0.30}, confirm = {1.00, 0.82, 0.30},
    complete = {1.00, 0.80, 0.80}, kill = {1.00, 0.67, 0.67}, avoid = {1.00, 0.54, 0.45},
    goto = {1.00, 0.93, 0.47}, talk = {0.00, 0.67, 1.00},
    learn = {0.67, 0.93, 1.00}, collect = {0.67, 0.93, 1.00}, note = TIP_RGB,
}

-- Native actions remain untouched. This registry classifies only their visual
-- meaning, adapter metadata disambiguates instructions from authored notes.
local actionFamilies = {}
local families = {
    accept = "accept multiq",
    turnin = "turnin turninany",
    complete = "complete goal achieve achievetext scenariogoal scenariobonus scenariostage scenarioend scenariostart q quest count countremains level ding rep petding petlevel houselevel expcollect",
    kill = "kill killboss bosshp from grind",
    avoid = "avoid",
    goto = "goto walk zombiewalk fly fpath ferry home hearth arrive at subzone mapmarker discover findcity invehicle outvehicle ontaxi offtaxi enter travel flight ship zeppelin airship tram bind learnflight",
    talk = "talk talknpcs gossip clicknpc gotonpc stablemaster",
    learn = "learn train trainer learnspell learnpetspell learnmount learnpet skill skillmax reachskill openskill specialtalent specialtalentactive",
    collect = "collect buy vendor cast click extraaction craft firstcraft create earn farm get goldcollect goldtracker repcollect use useany userune getrune toy equip equipped unequip unequipped itemset itemname _item activepet petaction petspecies havebuff nobuff havebuilding follower furniture appearance polish trash bank deposit destroy buff",
    confirm = "confirm",
    note = "info note tip text abandon loadguide nexttab noquest questchoice playerchoice playertitle worldquestqueue reload popuptext image webheader webimage webinfo condition guideflag onlyinsticky notinsticky oncomplete phase debugevent debugvar devmsg wait money task",
}
for family, names in pairs(families) do
    for name in names:gmatch("%S+") do actionFamilies[name] = family end
end
Styles.ActionFamilies = actionFamilies

local trackerColorStyles = {}

local function GetFlatRGBForMode(mode, customColor)
    if mode == nil or mode == C.WORLD_OVERLAY_COLOR_AUTO or mode == "theme" then return nil end
    local color = mode == C.WORLD_OVERLAY_COLOR_CUSTOM and customColor
        or C.WORLD_OVERLAY_COLOR_PRESETS and C.WORLD_OVERLAY_COLOR_PRESETS[mode]
    if type(color) ~= "table" then return 1, 1, 1 end
    return color.r or 1, color.g or 1, color.b or 1
end

Styles.GetFlatRGBForMode = GetFlatRGBForMode

function Styles.GetProviderKey(owner)
    if type(owner) ~= "table" then return nil end
    local module = owner.parentModule or owner.parentBlock and owner.parentBlock.parentModule or owner
    return module._awpGuideProvider
end

local function GetConfiguredFlatRGB(providerKey)
    if type(NS.GetGuideTrackerViewerSettings) ~= "function" then return nil end
    local settings = NS.GetGuideTrackerViewerSettings(providerKey)
    local mode = settings and settings.textColorMode or C.WORLD_OVERLAY_COLOR_AUTO
    return GetFlatRGBForMode(mode, settings and settings.textCustomColor)
end

local function NormalizeAction(goalOrAction)
    local action = type(goalOrAction) == "table" and goalOrAction.action or goalOrAction
    if type(action) ~= "string" then return nil end
    action = action:lower()
    return action ~= "" and action or nil
end

local function ColorRole(kind, role)
    return role or (kind == "tip" and "note" or "action")
end

local function StatusRole(status, role)
    if status == "warning" then return "WARN" end
    if status == "failed" or status == "impossible" then return "BAD" end
    if role ~= "heading" and role ~= "note" and role ~= "progress" then
        if status == "complete" then return "GOOD" end
        if status == "skipped" or status == "obsolete" then return "MUTED" end
    end
    return role == "heading" and "TITLE" or role == "progress" and "VALUE"
        or role == "note" and "LABEL" or "TEXT"
end

local function GetRGBTable(status, kind, goalOrAction, role)
    role = ColorRole(kind, role)
    local state = StatusRole(status, role)
    if state == "WARN" then return STATUS_RGB.warning end
    if state == "BAD" then return STATUS_RGB.failed end
    if state == "GOOD" then return COMPLETE_RGB end
    if state == "MUTED" then return STATUS_RGB.obsolete end
    if role == "heading" or role == "npc" then return ACTION_RGB.talk end
    if role == "note" then return TIP_RGB end
    if role == "progress" then return STATUS_RGB.incomplete end
    local action = NormalizeAction(goalOrAction)
    local family = action and actionFamilies[action]
    return family and ACTION_RGB[family] or role == "instruction" and TIP_RGB or STATUS_RGB.incomplete
end

function Styles.StatusToRGB(status, kind, goalOrAction, providerKey, role)
    local settings = providerKey and NS.GetGuideTrackerViewerSettings and NS.GetGuideTrackerViewerSettings(providerKey)
    local mode = settings and settings.textColorMode or C.WORLD_OVERLAY_COLOR_AUTO
    if mode == "theme" then
        if StatusRole(status, ColorRole(kind, role)) == "MUTED" then return unpack(STATUS_RGB.obsolete) end
        local appearance = NS.Internal.Appearance
        if appearance and providerKey then
            local r, g, b = appearance.GetRGB("guide." .. providerKey, StatusRole(status, ColorRole(kind, role)))
            if r then return r, g, b end
        end
    end
    local r, g, b = GetFlatRGBForMode(mode, settings and settings.textCustomColor)
    if r then return r, g, b end
    local color = GetRGBTable(status, kind, goalOrAction, role)
    return color[1], color[2], color[3]
end

function Styles.StatusToRGBForColorMode(status, kind, goalOrAction, mode, customColor)
    local r, g, b = GetFlatRGBForMode(mode or C.WORLD_OVERLAY_COLOR_AUTO, customColor)
    if r then return r, g, b end
    local color = GetRGBTable(status, kind, goalOrAction)
    return color[1], color[2], color[3]
end

function Styles.GetTrackerColorStyle(status, kind, goalOrAction, providerKey, role)
    local r, g, b = Styles.StatusToRGB(status, kind, goalOrAction, providerKey, role)
    local key = string.format("%.3f:%.3f:%.3f", r, g, b)
    local style = trackerColorStyles[key]
    if style then return style end
    local highlight = {
        r = r + (1 - r) * 0.18,
        g = g + (1 - g) * 0.18,
        b = b + (1 - b) * 0.18,
    }
    style = { r = r, g = g, b = b, reverse = highlight }
    highlight.reverse = style
    trackerColorStyles[key] = style
    return style
end

function Styles.ApplyText(text, providerKey, textKind, role, status, action)
    if not text then return end
    local appearance = NS.Internal.Appearance
    if appearance and appearance.Text then appearance.Text(text, "guide." .. providerKey, nil, nil, textKind) end
    if text.SetTextColor then
        local r, g, b = Styles.StatusToRGB(status or "incomplete", "goal", action, providerKey, role)
        text:SetTextColor(r, g, b)
    end
end

function Styles.UsesFlatColor(providerKey)
    return GetConfiguredFlatRGB(providerKey) ~= nil
end

function Styles.Colorize(text, r, g, b)
    if type(NS.SanitizeDiagnosticText) == "function" then text = NS.SanitizeDiagnosticText(text or "")
    else text = tostring(text or "") end
    return string.format("|cff%02x%02x%02x%s|r",
        math.floor((tonumber(r) or 1) * 255 + 0.5),
        math.floor((tonumber(g) or 1) * 255 + 0.5),
        math.floor((tonumber(b) or 1) * 255 + 0.5), text)
end

function Styles.OutputChatLine(text, status, kind, action, settings)
    local r, g, b = Styles.StatusToRGBForColorMode(status, kind, action,
        settings.chatTextColorMode, settings.chatTextCustomColor)
    local message = Styles.Colorize(text, r, g, b)
    local chatFrame = rawget(_G, "DEFAULT_CHAT_FRAME")
    if chatFrame then chatFrame:AddMessage("    " .. message)
    elseif type(NS.Msg) == "function" then NS.Msg(message) end
end

function Styles.OutputChatHeader(label, title, current, total, settings)
    if type(NS.Msg) ~= "function" then return end
    local r, g, b = Styles.GetFlatRGBForMode(settings.chatTextColorMode, settings.chatTextCustomColor)
    NS.Msg(Styles.Colorize(string.format("%s: %s - Step %d / %d", label, title or "Guide",
        current or 0, total or 0), r or 0, g or 0.67, b or 1))
end
