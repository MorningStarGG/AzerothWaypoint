-- ============================================================
-- DaylightUI styling
-- ============================================================
--
-- Builds AWP controls with DaylightUI's widget and font APIs and refreshes
-- them when the skin is ready.

local NS = _G.AzerothWaypointNS
local STYLE_NAME = "DaylightUI"
local registered = false
local SCROLL_TRACK = { 1, 1, 1, 0.04 }
local gradientMode, setBarGradient

local function Prepare()
    local ui = rawget(_G, "DaylightUI")
    assert(type(ui.API.GetSetting) == "function", "Missing current Daylight settings capability: API.GetSetting")
    assert(type(ui.Style) == "table" and type(ui.Style.SetBarGradient) == "function",
        "Missing current Daylight gradient capability: Style.SetBarGradient")
    gradientMode = ui.API.GetSetting("general", "gradients.off") == true and "flat" or "gradient"
    setBarGradient = ui.Style.SetBarGradient
end

local function BuildSlider(api, state, record)
    local widgets = rawget(_G, "DaylightUI").Widgets
    local input = api.Input(state.root, { height = 22, justify = "CENTER", maxLetters = 16 })
    input:SetWidth(60)
    input:SetPoint("RIGHT", state.root, "RIGHT")
    input:SetTextColor(unpack(api.Colors().VALUE))

    local slider = CreateFrame("Slider", nil, state.root)
    slider:SetPoint("LEFT", state.root, "LEFT")
    slider:SetPoint("RIGHT", input, "LEFT", -10, 0)
    slider:SetHeight(18)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(record.min, record.max)
    slider:SetValueStep(record.step)
    slider:SetObeyStepOnDrag(true)
    slider:SetHitRectInsets(-4, -4, -6, -6)
    slider:EnableMouse(true)

    -- Borrow only the track, thumb and hover effects. AWP owns the value box
    -- and its formatting, including percentages and custom distance units.
    local look = widgets.SliderLook(slider, {})
    local range = record.max - record.min
    function state.UpdateFill()
        look.Fill((slider:GetValue() - record.min) / range)
    end

    slider:HookScript("OnSizeChanged", state.UpdateFill)
    state.input, state.interactiveSlider = input, slider
    state.valuePlacement = "beside"
end

-- ============================================================
-- Surface rendering
-- ============================================================

local function Surface(api, state, record, settings)
    local root = state.root
    local kind = record.kind
    if not state.initialized then
        if kind == "progress" then
            state.bar = api.Bar(root)
            state.gradientMode = gradientMode
            state.bar:SetAllPoints(); state.bar:EnableMouse(false); state.bar:SetMinMaxValues(0, 100)
            state.bar:SetFrameLevel(root:GetFrameLevel())
        elseif kind == "button" or kind == "close" then
            if kind == "close" then
                -- Shared window controls keep ownership of clicks and forward visual events.
                state.widget = api.Close(root)
                state.hideText = true
            else
                state.widget = api.Button(root, "", (record.target or record.frame):GetHeight())
            end
            state.widget:SetAllPoints(); state.widget:EnableMouse(false)
            state.widget:SetFrameLevel(root:GetFrameLevel())
        elseif kind == "checkbox" then
            state.widget = api.Switch(root)
            state.widget:ClearAllPoints(); state.widget:SetPoint("LEFT"); state.widget:EnableMouse(false)
            root:SetSize(state.widget:GetWidth(), state.widget:GetHeight())
            state.labelEnd = state.widget
        elseif kind == "dropdown" or kind == "input" then
            state.widget = api.Input(root, { height = record.frame:GetHeight() })
            state.widget:SetAllPoints(); state.widget:EnableMouse(false); state.widget:EnableKeyboard(false)
            state.widget:SetFrameLevel(root:GetFrameLevel())
            if kind == "dropdown" then
                state.arrow = root:CreateTexture(nil, "ARTWORK")
                state.arrow:SetTexture(api.Media("ui-chevron.png")); state.arrow:SetSize(14, 14)
                state.arrow:SetPoint("RIGHT", -10, 0)
            end
        elseif kind == "slider" then
            BuildSlider(api, state, record)
        elseif kind == "reset" then
            state.icon = root:CreateTexture(nil, "ARTWORK")
            state.icon:SetAllPoints(); state.icon:SetTexture(api.Media("ui-reset.png"))
        elseif kind == "artwork" then
            -- The replaced artwork is decorative, not a content panel.
        elseif kind == "border" then
            api.Skin(root, { window = true, lean = true })
        elseif kind == "inset" then
            api.Skin(root, { window = true, borderPx = 1, bgAlpha = 0.38, noBevel = true })
        elseif kind == "scrollbar" then
            state.thumb = root:CreateTexture(nil, "ARTWORK")
            state.thumb:SetPoint("TOP", root, "TOP")
            state.thumb:SetPoint("BOTTOM", root, "BOTTOM")
            state.thumb:SetWidth(4)
            state.thumb:SetTexture(api.Media("ui-pill.png"))
            state.scrollTrackColor = SCROLL_TRACK
        elseif kind == "decoration" then
            state.fill = root:CreateTexture(nil, "BACKGROUND"); state.fill:SetAllPoints()
            state.fill:SetColorTexture(1, 1, 1, 0.08)
        elseif kind == "menuRow" then
            state.fill = root:CreateTexture(nil, "BACKGROUND"); state.fill:SetAllPoints()
        else
            state.shell = true
        end
        state.initialized = true
    end
    if state.shell then
        local width = settings and settings.panelBorderSource == "custom" and settings.panelBorderWidth or nil
        local opacity = settings and settings.panelBackgroundSource == "custom" and settings.panelBackgroundOpacity or
        nil
        if not state.shellApplied or state.borderWidth ~= width or state.backgroundOpacity ~= opacity then
            api.Skin(root, { window = true, borderPx = width, bgAlpha = opacity })
            state.shellApplied, state.borderWidth, state.backgroundOpacity = true, width, opacity
        end
    end
    if state.bar then
        if state.gradientMode ~= gradientMode then
            -- Daylight resolves the current global policy when its helper runs.
            if setBarGradient then setBarGradient(state.bar, true) end
            state.gradientMode = gradientMode
        end
        if state.value ~= record.value then
            state.bar:SetValue(record.value)
            state.value = record.value
        end
    end
    if kind == "checkbox" then state.widget.SetOn(record.checked) end
    if kind == "button" and state.enabled ~= record.enabled then
        state.widget.SetOff(not record.enabled)
        state.enabled = record.enabled
        -- SetOff also samples the physical mouse, even on a decorative widget.
        -- The shared hover owner must reapply its state after this mutation.
        state.hoverRevision = (state.hoverRevision or 0) + 1
    end
    if kind == "button" then state.iconColor = api.Colors().TEXT end
    if state.arrow then state.arrow:SetVertexColor(0.72, 0.72, 0.72, 1) end
    if state.thumb then state.thumb:SetVertexColor(1, 1, 1, record.hovered and 0.38 or 0.22) end
    if kind == "menuRow" then state.fill:SetColorTexture(1, 1, 1,
            record.hovered and 0.07 or record.selected and 0.04 or 0) end
    if state.icon then
        local ui = rawget(_G, "DaylightUI")
        local widgets = ui and ui.Widgets
        if record.hovered and widgets and widgets.TintDaylight then
            widgets.TintDaylight(state.icon)
        else
            local color = widgets and widgets.COLORS and widgets.COLORS.faint
            if color then state.icon:SetVertexColor(unpack(color)) else state.icon:SetVertexColor(0.72, 0.66, 0.58, 1) end
        end
    end
    return state
end

local panelSurfaces = {
    plaque = true,
    ["windows.options"] = true,
    ["windows.queue"] = true,
    ["windows.help"] = true,
    ["windows.search"] = true,
    ["windows.taxi"] = true
}
local Daylight = NS.Internal.Appearance.CreateStyleProvider({
    key = "daylight",
    label = STYLE_NAME,
    addonName = "DaylightUI",
    dbKey = "daylightAppearance",
    fields = {
        panelBorderSource = {
            type = "dropdown",
            default = "inherit",
            label = "Border width",
            surfaces = panelSurfaces,
            values = { inherit = "Follow " .. STYLE_NAME, custom = "Custom width" },
            desc =
            "Follow " .. STYLE_NAME .. "'s border width or set a width for this area. Buttons and inputs keep their normal sizing."
        },
        panelBorderWidth = {
            type = "slider",
            default = 8,
            label = "Custom border width",
            min = 1,
            max = 16,
            step = 1,
            unit = "px",
            surfaces = panelSurfaces,
            enabledBy = "panelBorderSource",
            enabledValue = "custom",
            format = function(v) return string.format("%.0f px", v) end,
            desc =
            "Select Custom width above. " .. STYLE_NAME .. " still supplies the border, bevel and shadow."
        },
        panelBackgroundSource = {
            type = "dropdown",
            default = "inherit",
            label = "Background opacity",
            surfaces = panelSurfaces,
            values = { inherit = "Follow " .. STYLE_NAME, custom = "Custom opacity" },
            desc =
            "Follow " .. STYLE_NAME .. "'s window background opacity or set an opacity for this area."
        },
        panelBackgroundOpacity = {
            type = "slider",
            default = 1,
            label = "Custom background opacity",
            min = 0,
            max = 1,
            step = 0.01,
            unit = "%",
            surfaces = panelSurfaces,
            enabledBy = "panelBackgroundSource",
            enabledValue = "custom",
            format = function(v) return string.format("%.0f%%", v * 100) end,
            desc =
            "Select Custom opacity directly above. This changes the panel background without fading its text, border or controls."
        },
    },
    sections = { {
        label = "Panel overrides",
        surfaces = panelSurfaces,
        rows = { "panelBorderSource", "panelBorderWidth", "panelBackgroundSource", "panelBackgroundOpacity" }
    } },
    options = {
        available = function() return NS.IsWoWForever() and rawget(_G, "DaylightUI") ~= nil end,
        desc =
        "DaylightUI hosts Guide Viewers independently of your UI Style. You can edit these settings here or in DaylightUI's AzerothWaypoint section."
    },
    renderVisual = Surface,
    prepare = Prepare,
    getVersion = function() return gradientMode end,
    getAPI = function()
        if not NS.IsWoWForever or not NS.IsWoWForever() then return end
        local ui = rawget(_G, "DaylightUI")
        return ui and ui.API
    end,
    refreshOptions = function()
        local ui = rawget(_G, "DaylightUI")
        local panel = ui and ui.OptionsPanel
        if panel and type(panel.Refresh) == "function" then pcall(panel.Refresh) end
    end,

})
NS.Internal.Daylight = Daylight

-- ============================================================
-- Font and addon readiness
-- ============================================================

local function OnSharedFontRegistered(_, kind, name)
    if kind ~= "font" or type(name) ~= "string" or not Daylight.active then return end
    local settings = Daylight.GetSettings()
    if not settings.enabled or type(settings.surfaces) ~= "table" then return end

    -- Daylight emits StyleChanged for its own picks. AWP stores its area
    -- overrides separately and needs to observe those font registrations.
    local fontKey = "lsm:" .. name
    for _, surface in pairs(settings.surfaces) do
        if type(surface) == "table" and surface.fontKey == fontKey
            and surface.enabled ~= false and surface.fonts ~= false then
            Daylight.RequestRefresh()
            return
        end
    end
end

local function Initialize()
    local api = Daylight.GetAPI()
    if not api or registered then return end
    local dui = rawget(_G, "DaylightUI")
    if type(api.For) ~= "function" or type(dui.RegisterPlugin) ~= "function" or type(dui.RegisterModule) ~= "function" then return end
    registered = true
    dui:RegisterPlugin("AzerothWaypoint", {
        needs = { 1, 3 },
        short = "AWP",
        icon = "Interface\\AddOns\\AzerothWaypoint\\media\\icon.png",
        blurb = "Guide Viewers and optional AzerothWaypoint appearance matching."
    })
    local groups = Daylight.GetOptionGroups()
    local pages = {
        { id = "main",    label = "Overview",      groups = { groups[1] } },
        { id = "viewers", label = "Guide Viewers", desc = "Choose a provider tab, then configure its appearance. The active navigation provider is selected independently.", groups = {} },
        { id = "overlay", label = "World Overlay", desc = "Choose an overlay area, then configure its font, text colors and panel.",                                         groups = {} },
        { id = "windows", label = "AWP Windows",   desc = "Choose an AWP window or settings search to style independently.",                                                 groups = {} },
    }
    for index = 2, #groups do
        local group = groups[index]
        for _, item in ipairs(group.items) do
            if item.type == "action" then item.type, item.text, item.func = "button", item.label, item.run end
        end
        local page = group.surface:sub(1, 6) == "guide." and pages[2]
            or group.surface:sub(1, 8) == "windows." and pages[4] or pages[3]
        page.groups[#page.groups + 1] = group
    end
    pages[1].groups[#pages[1].groups + 1] = {
        label = "AzerothWaypoint",
        items = {
            {
                type = "button",
                label = "AWP settings",
                text = "Open AWP Settings",
                func = function()
                    local panel = dui.OptionsPanel
                    if panel and panel.IsShown() then panel.Toggle() end
                    NS.OpenOptionsPanel()
                end
            },
        }
    }
    dui:RegisterModule("AzerothWaypointAppearance", {
        plugin = "AzerothWaypoint",
        label = "Appearance",
        defaults = {},
        options = { pages = pages }
    })
    local owner = api.For("AzerothWaypoint")
    owner.On("StyleChanged", Daylight.RequestRefresh)
    owner.On("Login", Daylight.RequestRefresh)
    local sharedMedia = LibStub and LibStub("LibSharedMedia-3.0", true)
    if sharedMedia and type(sharedMedia.RegisterCallback) == "function" then
        sharedMedia.RegisterCallback(Daylight, "LibSharedMedia_Registered", OnSharedFontRegistered)
    end
    Daylight.RequestRefresh()
end

if not NS.IsWoWForever or not NS.IsWoWForever() then return end
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_REGEN_ENABLED" then
        Daylight.RequestRefresh()
    elseif event ~= "ADDON_LOADED" or addon == "DaylightUI" or addon == "AzerothWaypoint" then
        Initialize()
    end
end)
