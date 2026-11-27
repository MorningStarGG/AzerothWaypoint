-- ============================================================
-- GW2 UI styling
-- ============================================================
--
-- Uses GW2 UI's fonts, colors and widget artwork for AWP surfaces and its
-- settings panel.

local NS = _G.AzerothWaypointNS
-- GW2_UI's toolkit adds this method to the font-string metatable.
---@class (partial) FontString
---@field GwSetFontTemplate fun(self: FontString, font: string, textSizeType: number, style?: string, textSizeAddition?: number, skip?: boolean)

local Appearance = NS.Internal.Appearance
local ART = "Interface/AddOns/GW2_UI/textures/uistuff/"
local WHITE, DARK = { 1, 1, 1 }, { 0, 0, 0 }
local DESCRIPTION =
"Match GW2 UI on Retail and Forever. Configure each Viewer and AWP area here or in GW2 UI Settings > AzerothWaypoint."
local PANEL_PREFIX = "AzerothWaypoint_"
local theme = {}
local themeDirty, generation, unavailable = true, 0, nil

local function Engine() return rawget(_G, "GW2_ADDON") end

local API = {}
function API.Accent() return unpack(theme.accent) end

function API.Colors() return theme.palette end

local function SharedMedia()
    local gw = Engine()
    return gw and gw.Libs and gw.Libs.LSM
end

function API.FontFile(key)
    local media = SharedMedia()
    return media and media:Fetch("font", key, true)
end

local function FontChoices()
    local values, order = { general = "Follow GW2 UI" }, { "general" }
    local media = SharedMedia()
    for _, name in ipairs(media and media:List("font") or {}) do
        if not values[name] then
            order[#order + 1] = name
            values[name] = name
        end
    end
    return values, order
end

function API.FontRow() return { choices = FontChoices } end

local cachedSamples
local function GetSamples()
    if not cachedSamples then
        local holder = CreateFrame("Frame")
        holder:Hide()
        cachedSamples = {
            holder = holder,
            button = CreateFrame("Button", nil, holder),
            slider = CreateFrame("Slider", nil, holder),
            check = CreateFrame("CheckButton", nil, holder),
            body = holder:CreateFontString(nil, "ARTWORK"),
            heading = holder:CreateFontString(nil, "ARTWORK"),
            buttonText = holder:CreateFontString(nil, "ARTWORK", "gw_button_font_black"),
            dropdownText = holder:CreateFontString(nil, "ARTWORK"),
            dropdown = CreateFrame("Button", nil, holder)
        }
        cachedSamples.button:EnableMouse(false)
        cachedSamples.slider:EnableMouse(false)
        cachedSamples.check:EnableMouse(false)
    end
    return cachedSamples
end

local function GetAPI()
    local gw = Engine()
    local colors = gw and gw.Colors
    local skin = colors and colors.SkinColors
    local text = colors and colors.TextColors
    local backdrop = gw and gw.BackdropTemplates
    if gw and gw.settings and type(gw.GetFontFamilies) == "function"
        and colors and colors.Accent and text and text.LightHeader
        and skin and skin.SubText and skin.Disabled and skin.Positive and skin.Negative and skin.QuestGold
        and skin.ListHover and skin.ListSelected and skin.StatusBarTrack and skin.DarkIconButton and skin.HighlightWhite
        and skin.HeaderBorder and skin.SeparatorHighlight
        and backdrop and backdrop.DefaultWithSmallBorder and backdrop.OnlyBorder and backdrop.ColorableBorderOnly
        and type(gw.AddEditBoxBackground) == "function" and type(gw.AddSliderValueFill) == "function"
        and gw.Enum and gw.Enum.TextSizeType and gw.Enum.TextSizeType.Normal and gw.Enum.TextSizeType.Header
        and gw.Enum.TextSizeType.Small and gw.settings.fonts then
        local samples = GetSamples()
        for _, entry in ipairs({ { samples.button, "GwSkinButton" }, { samples.button, "GwHandleDropDownBox" },
            { samples.button, "GwCreateBackdrop" }, { samples.button, "GwStripTextures" },
            { samples.slider, "GwSkinSliderFrame" }, { samples.check, "GwSkinCheckButton" }, { samples.body, "GwSetFontTemplate" } }) do
            if type(entry[1][entry[2]]) ~= "function" then
                unavailable = "Missing GW2 UI skin capability: " .. entry[2]
                return
            end
        end
        unavailable = nil
        return API
    end
    unavailable = gw and "Waiting for GW2 UI's fonts and skin helpers." or "GW2 UI is not loaded."
end

local function ReadFont(text, includeSize)
    local file, size, flags = text:GetFont()
    local sr, sg, sb, sa = text:GetShadowColor()
    local sx, sy = text:GetShadowOffset()
    return {
        file = file,
        size = includeSize and size or nil,
        flags = flags or "",
        sr = sr,
        sg = sg,
        sb = sb,
        sa = sa,
        sx = sx,
        sy = sy
    }
end

-- ============================================================
-- Preparing GW2 UI controls
-- ============================================================

local function Prepare()
    if not themeDirty and theme.signature then return end
    local gw = Engine()
    local normal, heading = gw.GetFontFamilies()
    normal = normal ~= "" and normal or UNIT_NAME_FONT
    heading = heading ~= "" and heading or DAMAGE_TEXT_FONT
    local samples = GetSamples()
    -- Native font objects are used only on these owned samples. Logical AWP
    -- text receives their resolved values through the shared restoration path.
    if not samples.dropdown.gwSkinned then
        samples.dropdown.Text = samples.dropdownText
        samples.dropdown:GwHandleDropDownBox(nil, nil, nil, 155)
        samples.dropdown:EnableMouse(false)
    end
    samples.body:GwSetFontTemplate(normal, gw.Enum.TextSizeType.Normal)
    samples.heading:GwSetFontTemplate(heading, gw.Enum.TextSizeType.Header)
    samples.dropdownText:GwSetFontTemplate(normal, gw.Enum.TextSizeType.Small)
    samples.buttonText:SetShadowColor(0, 0, 0, 0)
    samples.buttonText:SetShadowOffset(0, 0)
    local font = ReadFont(samples.body)
    font.headingFile = select(1, samples.heading:GetFont())
    font.controlStyles = { button = ReadFont(samples.buttonText, true), dropdown = ReadFont(samples.dropdownText, true) }
    local colors, skin = gw.Colors, gw.Colors.SkinColors
    local nextTheme = {
        font = font,
        accent = { colors.Accent:GetRGB() },
        palette = {
            TEXT = WHITE,
            VALUE = WHITE,
            CONTROL = { samples.buttonText:GetTextColor() },
            DROPDOWN = { samples.dropdownText:GetTextColor() },
            TITLE = { colors.TextColors.LightHeader:GetRGB() },
            LABEL = { skin.SubText:GetRGB() },
            OFF = { skin.Disabled:GetRGB() },
            GOOD = { skin.Positive:GetRGB() },
            BAD = { skin.Negative:GetRGB() },
            WARN = { skin.QuestGold:GetRGB() }
        },
        backdrops = gw.BackdropTemplates
    }
    local signature = {}
    local function Values(values) for _, value in ipairs(values) do signature[#signature + 1] = tostring(value) end end
    for _, style in ipairs({ font, font.controlStyles.button, font.controlStyles.dropdown }) do
        Values({ style.file, style.flags, style.size or 0, style.sr, style.sg, style.sb, style.sa, style.sx, style.sy })
    end
    Values({ font.headingFile }); Values(nextTheme.accent)
    for _, key in ipairs({ "CONTROL", "DROPDOWN", "TITLE", "LABEL", "OFF", "GOOD", "BAD", "WARN" }) do Values(nextTheme
        .palette[key]) end
    for _, key in ipairs({ "DarkIconButton", "HighlightWhite", "ListSelected", "ListHover", "StatusBarTrack", "HeaderBorder", "SeparatorHighlight" }) do
        nextTheme[key] = { skin[key]:GetRGBA() }
        Values(nextTheme[key])
    end
    nextTheme.signature = table.concat(signature, ":")
    if nextTheme.signature ~= theme.signature then
        generation = generation + 1; theme = nextTheme
    end
    themeDirty = false
end

-- ============================================================
-- Control artwork and state
-- ============================================================

local function Texture(parent, layer, file)
    local region = parent:CreateTexture(nil, layer)
    if file then region:SetTexture(ART .. file) end
    return region
end

local function Fill(parent, layer, file)
    local region = Texture(parent, layer, file)
    region:SetAllPoints()
    return region
end

local function Build(owner, record)
    local kind, holder = record.kind, owner.root
    local gw = Engine()
    local root = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    owner.pending = root
    root:SetAllPoints()
    root:SetFrameLevel(holder:GetFrameLevel())
    local state = { root = root }
    if kind == "artwork" then
        return state
    elseif record.getCollapsed then
        state.disclosure = Texture(root, "ARTWORK", "arrowdown_down.png")
        state.disclosure:SetSize(14, 14)
        state.disclosure:SetPoint("CENTER")
    elseif kind == "button" and (record.facet == "controls" or record.facet == "actions")
        and record.surface:sub(1, 6) == "guide." then
        state.iconFill = Fill(root, "BACKGROUND")
        state.iconHover = Fill(root, "BORDER")
    elseif kind == "button" or kind == "close" then
        local button = CreateFrame("Button", nil, root)
        if kind == "close" then
            button:SetSize(20, 20)
            button:SetPoint("CENTER")
        else
            button:SetAllPoints()
        end
        button:SetFrameLevel(root:GetFrameLevel())
        button:GwSkinButton(kind == "close")
        button:EnableMouse(false)
        state.widget = button
        state.hideText = kind == "close"
        state.iconColor = kind == "close" and WHITE or DARK
        if kind == "button" then state.textKind = "button" end
    elseif kind == "checkbox" then
        holder:SetSize(20, 20)
        local check = CreateFrame("CheckButton", nil, root)
        check:SetAllPoints()
        check:GwSkinCheckButton()
        check:EnableMouse(false)
        state.widget, state.labelEnd = check, holder
    elseif kind == "dropdown" then
        local dropdown = CreateFrame("Button", nil, root)
        dropdown.Text = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dropdown:GwHandleDropDownBox(nil, nil, nil, record.frame:GetWidth())
        dropdown:SetAllPoints()
        dropdown.Text:SetPoint("LEFT", dropdown.backdrop, "LEFT", 6, 0)
        dropdown.Text:SetPoint("RIGHT", dropdown.gw2Arrow, "LEFT", -6, 0)
        dropdown.Text:SetWordWrap(false)
        dropdown:EnableMouse(false)
        state.widget, state.nativeText, state.hideText = dropdown, dropdown.Text, true
    elseif kind == "input" then
        gw.AddEditBoxBackground(root, 0)
    elseif kind == "progress" then
        local bar = CreateFrame("StatusBar", nil, root)
        Fill(root, "BACKGROUND", "gwstatusbar-bg.png")
        bar:SetAllPoints()
        bar:SetFrameLevel(root:GetFrameLevel())
        bar:SetMinMaxValues(0, 100)
        bar:SetStatusBarTexture(ART .. "gwstatusbar.png")
        state.bar = bar
    elseif kind == "slider" then
        local slider = CreateFrame("Slider", nil, root)
        slider:SetPoint("LEFT"); slider:SetPoint("RIGHT")
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(record.min, record.max)
        slider:SetValueStep(record.step)
        slider:SetObeyStepOnDrag(true)
        slider:SetHitRectInsets(-4, -4, -6, -6)
        slider:EnableMouse(true)
        slider:GwSkinSliderFrame()
        gw.AddSliderValueFill(slider)
        slider:SetFrameLevel(root:GetFrameLevel())
        local input = CreateFrame("EditBox", nil, root)
        input:SetSize(64, 18)
        input:SetAutoFocus(false)
        input:SetMaxLetters(16)
        input:SetJustifyH("CENTER")
        input:SetFontObject("GameFontHighlightSmall")
        if record.valueText then input:SetPoint("RIGHT", record.valueText, "RIGHT") end
        gw.AddEditBoxBackground(input, 0)
        Appearance.Text(input, record.surface, "TEXT", "shell")
        state.input, state.interactiveSlider = input, slider
    elseif kind == "reset" then
        state.icon = Fill(root, "ARTWORK")
        state.icon:SetAtlas("common-icon-rotateleft", false)
    elseif kind == "menuRow" then
        state.hover = Fill(root, "BACKGROUND")
        state.hover:SetTexture("Interface/AddOns/GW2_UI/textures/character/menu-hover.png")
    elseif kind == "sectionHeader" then
        local separator = Fill(root, "BACKGROUND")
        separator:SetTexture("Interface/AddOns/GW2_UI/textures/bag/bag-sep.png")
        root:SetBackdrop(theme.backdrops.ColorableBorderOnly)
        state.sectionHover = Fill(root, "ARTWORK")
    elseif kind == "scrollbar" then
        Fill(root, "ARTWORK", "scrollbarmiddle.png")
    elseif kind == "decoration" then
        state.rule = Fill(root, "ARTWORK")
    else
        local backdrop = theme.backdrops
        root:SetBackdrop(kind == "border" and backdrop.OnlyBorder or backdrop.DefaultWithSmallBorder)
        if record.titleTarget then
            local title = Texture(root, "BORDER")
            title:SetAllPoints(record.titleTarget)
            title:SetAlpha(0.18)
            state.title = title
        end
    end
    return state
end

local function Render(_, owner, record)
    if not owner.visual then
        local ok, result = pcall(Build, owner, record)
        if not ok and owner.pending then owner.pending:Hide() end
        owner.pending = nil
        if not ok then error(result, 0) end
        owner.visual = result
    end
    local state = owner.visual
    if state.generation ~= generation then
        if state.bar then state.bar:SetStatusBarColor(API.Accent()) end
        if state.iconFill then state.iconFill:SetColorTexture(unpack(theme.DarkIconButton)) end
        if state.iconHover then state.iconHover:SetColorTexture(unpack(theme.HighlightWhite)) end
        if state.sectionHover then
            state.root:SetBackdropBorderColor(unpack(theme.HeaderBorder))
            state.sectionHover:SetColorTexture(unpack(theme.SeparatorHighlight))
        end
        if record.kind == "scrollbar" then state.scrollTrackColor = theme.StatusBarTrack end
        if state.title then state.title:SetColorTexture(API.Accent()) end
        if state.input then Appearance.Text(state.input, record.surface, "TEXT", "shell") end
        state.generation = generation
    end
    if state.enabled ~= record.enabled then
        state.root:SetAlpha(record.enabled and 1 or 0.55)
        if state.widget then state.widget:SetEnabled(record.enabled) end
        state.enabled = record.enabled
    end
    if record.checked ~= state.checked then
        state.widget:SetChecked(record.checked)
        state.checked = record.checked
    end
    if record.kind == "button" and record.text then
        state.textRole = record.enabled and (state.iconFill and "TEXT" or "CONTROL") or "OFF"
    end
    if state.nativeText then
        local text = record.text and record.text:GetText() or ""
        if text ~= state.text then
            state.nativeText:SetText(text); state.text = text
        end
        Appearance.Text(state.nativeText, record.surface, record.enabled and "DROPDOWN" or "OFF", record.facet,
            "dropdown")
    end
    if record.kind == "close" and state.hovered ~= record.hovered then
        if record.hovered then state.widget:LockHighlight() else state.widget:UnlockHighlight() end
        state.hovered = record.hovered
    end
    if state.disclosure then
        local collapsed = record.getCollapsed() == true
        if state.collapsed ~= collapsed then
            state.disclosure:SetRotation(collapsed and math.pi / 2 or 0)
            state.collapsed = collapsed
        end
        if state.hovered ~= record.hovered then
            state.disclosure:SetAlpha(record.hovered and 1 or 0.8)
            state.hovered = record.hovered
        end
    elseif state.iconHover then
        state.iconHover:SetShown(record.hovered and record.enabled)
    end
    if state.bar then
        if state.value ~= record.value then
            state.bar:SetValue(record.value)
            state.value = record.value
        end
    end
    if state.hover then
        state.hover:SetVertexColor(unpack(record.selected and theme.ListSelected or theme.ListHover))
        state.hover:SetShown(record.selected or record.hovered or false)
    end
    if state.sectionHover then state.sectionHover:SetShown(record.hovered and record.enabled) end
    if state.rule then state.rule:SetColorTexture(API.Accent()) end
    if state.icon then
        if record.hovered then
            state.icon:SetVertexColor(API.Accent())
        else
            state.icon:SetVertexColor(0.8, 0.75, 0.66)
        end
    end
    return state
end

local Provider
local registeredTab, refreshingOptions, writingSetting
local optionRows = {}

-- ============================================================
-- Settings and provider registration
-- ============================================================

local function RefreshSettings()
    local gw, window = Engine(), rawget(_G, "GwSettingsWindow")
    if not registeredTab or not window or not window:IsShown() then return end
    if gw.RefreshConditionalOptions then gw.RefreshConditionalOptions() end
    -- GW builds options lazily and keeps their widgets for native search.
    -- Refresh only our already-visible widgets after AWP changes a value.
    refreshingOptions = true
    for _, option in ipairs(optionRows) do
        local widget = option.__widget
        if widget and widget:IsVisible() then
            local value = option.get()
            if option.optionType == "boolean" then
                widget.checkbutton:SetChecked(value)
            elseif option.optionType == "slider" then
                if widget.slider:GetValue() ~= value and not widget.inputFrame.input:HasFocus() then
                    widget.slider:SetValue(value)
                end
            elseif option.optionType == "dropdown" then
                if option.awpValue ~= value then widget.dropDown:GenerateMenu() end
            elseif option.optionType == "colorPicker" then
                widget.button.bg:SetColorTexture(value.r, value.g, value.b)
            end
            option.awpValue = value
        end
    end
    refreshingOptions = false
end

local refreshQueue = NS.Internal.Scheduling.CreateCoalescer(RefreshSettings)
Provider = Appearance.CreateStyleProvider({
    key = "gw2ui",
    label = "GW2 UI",
    addonName = "GW2_UI",
    dbKey = "gw2uiAppearance",
    stylesDisclosure = true,
    stylesSectionHeaders = true,
    getAPI = GetAPI,
    prepare = Prepare,
    getVersion = function() return generation end,
    readFonts = function() return theme.font, theme.font end,
    renderVisual = Render,
    refreshOptions = function() if registeredTab and not writingSetting then refreshQueue:Request() end end,
    options = { desc = DESCRIPTION, available = function() return Engine() ~= nil end },
})
NS.Internal.GW2UI = Provider

function Provider.GetStatus()
    return GetAPI() and "ready" or "unavailable", Provider.lastError or unavailable
end

function Provider.StyleOptionHighlight(texture, surface)
    if not Provider.IsEnabled(surface, "shell") then return false end
    local r, g, b = Engine().Colors.TextColors.LightHeader:GetRGB()
    texture:SetColorTexture(r, g, b, 0.05)
    return true
end

local widgetMethods = { toggle = "AddOption", slider = "AddOptionSlider", dropdown = "AddOptionDropdown", color =
"AddOptionColorPicker" }
local function AddOption(panel, item, group)
    if item.type == "action" then
        panel:AddOptionButton(item.label, item.desc, { callback = item.run, groupHeaderName = group })
        return
    end
    local function Set(value)
        if refreshingOptions then return end
        writingSetting = true
        local ok, message = pcall(item.set, value)
        writingSetting = false
        if not ok then error(message, 0) end
    end
    local values = { getter = item.get, getDefault = item.default, groupHeaderName = group, setter = Set }
    if item.disabled then values.isVisible = function() return not item.disabled() end end
    if item.type == "color" then
        local function Color(get)
            local value = get()
            return { r = value[1], g = value[2], b = value[3] }
        end
        values.getter = function() return Color(item.get) end
        values.getDefault = function() return Color(item.default) end
        values.setter = function(value) Set({ value.r, value.g, value.b }) end
    elseif item.type == "dropdown" then
        local labels, order
        if item.choices then labels, order = item.choices() else labels = item.values end
        if not labels then return end
        if not order then
            order = {}
            for key in pairs(labels) do order[#order + 1] = key end
            table.sort(order, function(a, b) return labels[a] < labels[b] end)
        end
        local names = {}
        for index, key in ipairs(order) do names[index] = labels[key] end
        values.optionsList, values.optionNames = order, names
    elseif item.type == "slider" then
        values.min, values.max, values.step = item.min, item.max, item.step
        values.decimalNumbers = item.step < 1 and 2 or 0
    end
    local option = panel[widgetMethods[item.type]](panel, item.label, item.desc, values)
    if option then optionRows[#optionRows + 1] = option end
end

local function OpenAWPSettings()
    local window = rawget(_G, "GwSettingsWindow")
    if window then window:Hide() end
    NS.OpenOptionsPanel()
end

local function CreatePanel(parent, key, label)
    local panel = CreateFrame("Frame", nil, parent, "GwSettingsPanelTmpl")
    local gw = Engine()
    panel.panelId = PANEL_PREFIX .. key
    panel.header:SetFont(DAMAGE_TEXT_FONT, 20)
    panel.header:SetTextColor(gw.Colors.TextColors.LightHeader:GetRGB())
    panel.header:SetText(label)
    panel.header:SetWidth(panel.header:GetStringWidth())
    panel.breadcrumb:SetFont(DAMAGE_TEXT_FONT, 12)
    panel.breadcrumb:SetTextColor(gw.Colors.TextColors.LightHeader:GetRGB())
    panel.breadcrumb:SetText("AzerothWaypoint")
    panel.sub:SetFont(UNIT_NAME_FONT, 12)
    panel.sub:SetTextColor(181 / 255, 160 / 255, 128 / 255)
    panel.sub:SetText(DESCRIPTION)
    panel:HookScript("OnShow", function() refreshQueue:Request() end)
    return panel
end

local function RegisterSettings()
    local gw = Engine()
    local tab = gw and gw.GetSettingsTabFrame and gw.GetSettingsTabFrame()
    if not GetAPI() or not tab or tab == registeredTab or type(tab.AddSettingsPanel) ~= "function" then return end
    local base = CreateFrame("Frame", nil, tab, "GwSettingsPanelTmpl")
    base.panelId = PANEL_PREFIX .. "base"
    local order = { { "overview", GENERAL or "General" }, { "viewers", "Guide Viewers" },
        { "overlay",  "World Overlay" }, { "windows", "AWP Windows" } }
    local sections, panels, surfaces = {}, {}, {}
    for _, entry in ipairs(order) do
        local key, label = unpack(entry)
        local panel = CreatePanel(base, key, label)
        sections[#sections + 1] = { name = label, frame = panel }
        panels[key] = panel
    end
    for _, surface in ipairs(Provider.GetOptionSurfaces()) do surfaces[surface.key] = surface end
    panels.overview:AddOptionButton("Open AWP Settings", "Open AzerothWaypoint's main options window.",
        { callback = OpenAWPSettings })
    for _, group in ipairs(Provider.GetOptionGroups()) do
        local surface = surfaces[group.surface]
        if not surface or not surface.forever or NS.IsWoWForever() then
            local panel = panels[surface and surface.page or "overview"]
            local label = group.surfaceLabel and group.surfaceLabel .. " / " .. group.label or group.label
            panel:AddGroupHeader(label)
            for _, item in ipairs(group.items) do AddOption(panel, item, label) end
        end
    end
    tab:AddSettingsPanel(base, "AzerothWaypoint", DESCRIPTION, sections, true)
    registeredTab = tab
end

local hooked
local profileOwner = {}
local function RefreshTheme()
    themeDirty = true; Provider.RequestRefresh()
end
local function Initialize()
    local gw = Engine()
    if not GetAPI() then return end
    if hooked ~= gw then
        hooked = gw
        if type(gw.UpdateFontSettings) == "function" then hooksecurefunc(gw, "UpdateFontSettings", RefreshTheme) end
        do
            local db = gw.globalSettings
            if db and type(db.RegisterCallback) == "function" then
                db.RegisterCallback(profileOwner, "OnProfileChanged", RefreshTheme)
                db.RegisterCallback(profileOwner, "OnProfileCopied", RefreshTheme)
                db.RegisterCallback(profileOwner, "OnProfileReset", RefreshTheme)
            end
        end
    end
    RefreshTheme()
    RegisterSettings()
end

local initializeQueue = NS.Internal.Scheduling.CreateCoalescer(Initialize)
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon ~= "GW2_UI" then return end
    if event == "PLAYER_REGEN_ENABLED" and registeredTab then return end
    if Engine() and not (InCombatLockdown and InCombatLockdown()) then initializeQueue:Request() end
end)
