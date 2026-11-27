-- ============================================================
-- ElvUI styling
-- ============================================================
--
-- Uses ElvUI's templates, fonts and option groups to style AWP and expose its
-- appearance settings.

local NS = _G.AzerothWaypointNS
local Appearance = NS.Internal.Appearance
---@type any
local engine, skins
---@type any
local theme = {}
local API = {}
local dirty, generation, registered, subscribed = true, 0, false, false
local unavailable, sample, fontValues, fontOrder, fontPaths
local WHITE = { 1, 1, 1 }
local MUTED = { 0.65, 0.65, 0.65 }
local requiredSkins = { "HandleButton", "HandleCloseButton", "HandleNextPrevButton",
    "HandleEditBox", "HandleSliderFrame", "HandleStatusBar", "Ace3_SkinCheckBox", "Ace3_RegisterAsWidget" }

local function Engine()
    local addon = rawget(_G, "ElvUI")
    return type(addon) == "table" and addon[1] or nil
end

local function Inspect()
    local e = Engine()
    if not e or type(e.GetModule) ~= "function" then
        unavailable = "ElvUI is not loaded."; return
    end
    local s = e:GetModule("Skins", true)
    if not s or not s.Initialized or not s.db or not e.db or not e.db.general or not e.media
        or not e.private or not e.private.general or not e.Libs or not e.Libs.LSM then
        unavailable = "Waiting for ElvUI's skinning and media initialization."; return
    end
    for _, name in ipairs(requiredSkins) do
        if type(s[name]) ~= "function" then
            unavailable = "Missing ElvUI skin capability: " .. name; return
        end
    end
    if type(e.Scale) ~= "function" or not e.Media or not e.Media.Textures then
        unavailable = "ElvUI's pixel and texture helpers are unavailable."; return
    end
    if not e.Libs.EP or type(e.Libs.EP.RegisterPlugin) ~= "function" or type(e.Libs.EP.HookInitialize) ~= "function" then
        unavailable = "ElvUI's plugin library is unavailable."; return
    end
    engine, skins, unavailable = e, s, nil
    return API
end

local function GetAPI()
    local ok, value = pcall(Inspect)
    if ok then return value end
    unavailable = tostring(value)
end

---@return any
local function Frame(kind, parent)
    local frame = CreateFrame(kind or "Frame", nil, parent)
    frame:EnableMouse(false)
    frame:SetAllPoints(parent)
    frame:SetFrameLevel(parent:GetFrameLevel())
    return frame
end

local function Prepare()
    if not dirty and theme.signature then return end
    if not sample then
        local holder = CreateFrame("Frame")
        holder:Hide()
        sample = holder:CreateFontString(nil, "ARTWORK")
    end
    if type(sample.FontTemplate) ~= "function" then error("ElvUI's font toolkit is unavailable") end
    -- Resolve NONE, SHADOW and SLUG through ElvUI itself, without registering
    -- AWP's logical text in its global font-refresh collection.
    sample:FontTemplate(engine.db.general.font, 13, nil, true)
    local file, _, flags = sample:GetFont()
    local sr, sg, sb, sa = sample:GetShadowColor()
    local sx, sy = sample:GetShadowOffset()
    local nextTheme = {
        font = { file = file, flags = flags, sr = sr, sg = sg, sb = sb, sa = sa, sx = sx, sy = sy },
        accent = { unpack(engine.media.rgbvaluecolor) },
        border = { unpack(engine.media.bordercolor) },
        background = { unpack(engine.media.backdropcolor) },
        faded = { unpack(engine.media.backdropfadecolor) },
        norm = engine.media.normTex,
        gloss = engine.media.glossTex,
        pixel = engine.mult,
        pixelMode = engine.PixelMode,
        borderWidth = engine.Border,
        twoPixels = engine.twoPixelsPlease,
        checkbox = skins.db.checkBoxSkin
    }
    if not file or not nextTheme.norm or not nextTheme.accent[1] then
        error("ElvUI's resolved appearance is incomplete")
    end
    local signature = { file, flags or "", tostring(sa), tostring(sx), tostring(sy), nextTheme.norm,
        nextTheme.gloss or "", tostring(nextTheme.pixel), tostring(nextTheme.pixelMode),
        tostring(nextTheme.borderWidth), tostring(nextTheme.twoPixels), tostring(nextTheme.checkbox) }
    for _, color in ipairs({ nextTheme.accent, nextTheme.border, nextTheme.background, nextTheme.faded }) do
        for _, channel in ipairs(color) do signature[#signature + 1] = tostring(channel) end
    end
    nextTheme.signature = table.concat(signature, ":")
    if nextTheme.signature ~= theme.signature then
        generation = generation + 1
        theme = nextTheme
    end
    dirty = false
end

local function FontChoices()
    if not fontValues then
        fontValues, fontOrder = { general = "Follow ElvUI" }, { "general" }
        fontPaths = { ["Follow ElvUI"] = engine.Libs.LSM:Fetch("font", engine.db.general.font) }
        local names = {}
        for name, path in pairs(engine.Libs.LSM:HashTable("font")) do
            fontPaths[name] = path
            if name ~= "general" then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            fontValues[name] = name; fontOrder[#fontOrder + 1] = name
        end
    end
    return fontValues, fontOrder
end

function API.Accent() return unpack(theme.accent) end

function API.Colors()
    return {
        TEXT = { 1, 1, 1 },
        LABEL = { 0.75, 0.75, 0.75 },
        VALUE = { 1, 1, 1 },
        TITLE = theme.accent,
        GOOD = { 0.58, 0.92, 0.52 },
        WARN = { 1, 0.82, 0.2 },
        BAD = { 1, 0.42, 0.32 },
        OFF = { 0.4, 0.4, 0.4 }
    }
end

function API.FontFile(key) return engine.Libs.LSM:Fetch("font", key) end

function API.FontRow(key, label, desc)
    return {
        key = key,
        label = label,
        desc = desc,
        choices = FontChoices
    }
end

-- ============================================================
-- Templates and control construction
-- ============================================================

-- Helpers may strip textures, resize or install scripts. Their entire input is
-- an owned visual, the logical AWP control and secure bindings stay untouched.
---@param frame any
local function Template(frame, name)
    if type(frame.SetTemplate) ~= "function" then error("ElvUI's backdrop toolkit is unavailable") end
    frame:SetTemplate(name, nil, true)
end

---@param frame any
local function Own(frame)
    frame.ignoreUpdates, frame.ignoreFrameTemplates = true, true
    if frame.backdrop then frame.backdrop.ignoreUpdates, frame.backdrop.ignoreFrameTemplates = true, true end
end

local function NumericInput(root)
    local input = CreateFrame("EditBox", nil, root)
    input:SetAutoFocus(false); input:SetMaxLetters(16); input:SetJustifyH("CENTER")
    input:SetFontObject("GameFontHighlightSmall")
    input:SetSize(70, 15)
    input:EnableMouse(true)
    Own(input)
    return input
end

local function Checkbox(root, record)
    local button = Frame("CheckButton", root)
    local widget = { frame = button, checked = record.checked }
    button.obj = widget
    widget.checkbg = button:CreateTexture(nil, "ARTWORK")
    widget.checkbg:SetAllPoints(button)
    widget.check = button:CreateTexture(nil, "OVERLAY")
    widget.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    widget.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    widget.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    widget.text:SetText(record.label and record.label:GetText() or "")
    widget.text:Hide()
    function widget:SetLabel(text) self.text:SetText(text) end

    function widget:SetType() end

    function widget:SetDisabled(disabled)
        self.disabled = disabled
        self.check:SetDesaturated(disabled)
    end

    -- Use the same settings-widget helper as ElvUI's options. Its optional
    -- extension hooks also see only these owned textures and widget methods.
    skins:Ace3_SkinCheckBox(widget, widget.check, widget.checkbg, widget.highlight)
    Own(widget.checkbg)
    return button, widget
end

local function ControlText(root, source)
    local text = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if source then
        local file, size, flags = source:GetFont()
        if file then text:SetFont(file, size, flags) end
    end
    return text
end

local function Build(owner, record)
    local kind = record.kind
    local holder = owner.root
    local root = Frame((kind == "button" or kind == "close" or record.navigation) and "Button" or "Frame", holder)
    owner.pending = root
    local state = { root = root }
    if kind == "artwork" then
        -- Decorative AWP art is hidden by the shared registry.
    elseif kind == "button" or kind == "close" then
        state.widget = root
        if kind == "close" then
            skins:HandleCloseButton(root); state.hideText = true
        else
            skins:HandleButton(root); state.iconColor = WHITE
        end
    elseif kind == "checkbox" then
        holder:ClearAllPoints(); holder:SetPoint("LEFT", record.target or record.frame, "LEFT"); holder:SetSize(24, 24)
        state.widget, state.check = Checkbox(root, record)
        state.labelEnd, state.labelGap = holder, 0
    elseif kind == "dropdown" then
        state.widget = Frame("Button", root)
        state.nativeText = ControlText(root, record.text)
        skins:Ace3_RegisterAsWidget({ type = "Dropdown", dropdown = root, button = state.widget, text = state.nativeText })
        -- AWP owns the outer layout, the native helper owns the arrow and text.
        root.backdrop:ClearAllPoints(); root.backdrop:SetAllPoints(root)
        state.hideText = true
    elseif kind == "input" then
        skins:HandleEditBox(root, "Default")
        root.backdrop:ClearAllPoints(); root.backdrop:SetAllPoints(root)
    elseif kind == "inset" then
        Template(root, "Default")
    elseif kind == "progress" then
        state.bar = Frame("StatusBar", root)
        state.bar:SetMinMaxValues(0, 100)
        skins:HandleStatusBar(state.bar, theme.accent, "Transparent")
        state.bar:SetAllPoints(root); state.bar:SetFrameLevel(root:GetFrameLevel())
    elseif kind == "slider" then
        state.valuePlacement = "below"
        state.slider = Frame("Slider", root)
        state.slider:SetOrientation("HORIZONTAL")
        state.slider:SetMinMaxValues(record.min, record.max)
        state.slider:SetValueStep(record.step)
        state.input = NumericInput(root)
        state.lowtext = root:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        state.hightext = root:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        state.lowtext:SetText(record.format and record.format(record.min) or tostring(record.min))
        state.hightext:SetText(record.format and record.format(record.max) or tostring(record.max))
        skins:Ace3_RegisterAsWidget({
            type = "Slider",
            slider = state.slider,
            editbox = state.input,
            lowtext = state.lowtext,
            hightext = state.hightext
        })
        state.slider:ClearAllPoints(); state.slider:SetPoint("LEFT"); state.slider:SetPoint("RIGHT")
    elseif kind == "reset" then
        state.icon = root:CreateTexture(nil, "ARTWORK")
        state.icon:SetAllPoints(); state.icon:SetAtlas("common-icon-rotateleft", false)
    elseif kind == "menuRow" and record.navigation then
        skins:HandleButton(root, true)
        state.widget = root
        state.fill = root:CreateTexture(nil, "ARTWORK"); state.fill:SetAllPoints()
        state.nativeText = ControlText(root, record.text)
        state.nativeText:SetPoint("LEFT", root, "LEFT", 4, 0)
        state.nativeText:SetPoint("RIGHT", root, "RIGHT", -4, 0)
        state.nativeText:SetJustifyH("CENTER")
        state.hideText = true
    elseif kind == "decoration" or kind == "scrollbar" or kind == "menuRow" then
        state.fill = root:CreateTexture(nil, "BACKGROUND"); state.fill:SetAllPoints()
    elseif kind == "header" then
        -- ElvUI removes the decorative native header background, AWP must not
        -- add a box or extra section lines to its transparent header treatment.
    else
        Template(root, "Transparent")
        state.borderOnly = kind == "border"
    end
    Own(root)
    root:SetFrameLevel(holder:GetFrameLevel())
    if state.widget then Own(state.widget) end
    if state.bar then Own(state.bar) end
    if state.slider then Own(state.slider) end
    if state.input then Own(state.input) end
    owner.pending = nil
    return state
end

-- ============================================================
-- Applying widget state
-- ============================================================

---@param frame any
local function RefreshTemplate(frame)
    if frame.template then frame:SetTemplate(frame.template, frame.glossTex, true) end
    if frame.backdrop and frame.backdrop.template then
        frame.backdrop:SetTemplate(frame.backdrop.template, frame.backdrop.glossTex, true)
    end
end

local function Render(_, owner, record)
    local state = owner.visual
    if not state then
        local ok, result = pcall(Build, owner, record)
        if not ok then
            if owner.pending then
                owner.pending:Hide(); owner.pending = nil
            end
            error(result)
        end
        state = result
        owner.visual = state
    end
    if record.navigation then state.textRole = not record.enabled and "OFF" or record.selected and "TEXT" or "WARN" end
    local refreshed = state.generation ~= generation
    if refreshed then
        RefreshTemplate(state.root)
        if state.widget then RefreshTemplate(state.widget) end
        if state.bar then
            RefreshTemplate(state.bar)
            state.bar:SetStatusBarTexture(theme.norm); state.bar:SetStatusBarColor(unpack(theme.accent))
        end
        if state.slider then RefreshTemplate(state.slider) end
        if state.input then
            RefreshTemplate(state.input)
            Appearance.Text(state.input, record.surface, "TEXT", "shell")
        end
        if state.lowtext then
            Appearance.Text(state.lowtext, record.surface, "TEXT", "shell")
            Appearance.Text(state.hightext, record.surface, "TEXT", "shell")
        end
        if state.check then RefreshTemplate(state.check.checkbg) end
        if state.borderOnly then state.root:SetBackdropColor(0, 0, 0, 0) end
        state.generation = generation
    end
    if state.value ~= record.value then
        if state.bar then state.bar:SetValue(record.value) end
        if state.slider then state.slider:SetValue(record.value) end
        state.value = record.value
    end
    local enabledChanged = state.enabled ~= record.enabled
    if enabledChanged then
        if state.widget then state.widget:SetEnabled(record.enabled) end
        if state.slider then state.slider:SetEnabled(record.enabled) end
        state.root:SetAlpha(record.enabled and 1 or 0.4)
        state.enabled = record.enabled
    end
    if state.widget and record.enabled and (refreshed or enabledChanged) then
        local handler = state.widget:GetScript(record.hovered and "OnEnter" or "OnLeave")
        if handler then handler(state.widget) end
    end
    if state.check and (state.checked ~= record.checked or enabledChanged or refreshed) then
        state.widget:SetChecked(record.checked)
        state.check.checked = record.checked
        state.check.check:SetShown(record.checked)
        state.check:SetDisabled(not record.enabled)
        state.checked = record.checked
    end
    if state.nativeText then
        local text = record.text and record.text:GetText() or ""
        if state.text ~= text then
            state.nativeText:SetText(text); state.text = text
        end
        Appearance.Text(state.nativeText, record.surface, state.textRole or (record.enabled and "TEXT" or "OFF"),
            record.facet)
    end
    if state.icon then state.icon:SetVertexColor(unpack(record.hovered and theme.accent or MUTED)) end
    if state.fill then
        if record.kind == "menuRow" then
            state.fill:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3],
                record.selected and 0.35 or record.hovered and 0.2 or 0)
        elseif record.kind == "scrollbar" then
            state.scrollTrackColor = theme.faded
            state.fill:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 1)
        else
            state.fill:SetColorTexture(theme.border[1], theme.border[2], theme.border[3], 0.5)
        end
    end
    return state
end

local optionsPending, optionsBuilt = false, false

-- ============================================================
-- Options and registration
-- ============================================================

local function RefreshOptions()
    if optionsPending then return end
    optionsPending = true
    C_Timer.After(0, function()
        optionsPending = false
        local e = Engine()
        local registry = optionsBuilt and e and e.Libs and e.Libs.AceConfigRegistry
        if registry then registry:NotifyChange("ElvUI") end
    end)
end

local Provider = Appearance.CreateStyleProvider({
    key = "elvui",
    label = "ElvUI",
    addonName = "ElvUI",
    dbKey = "elvuiAppearance",
    getAPI = GetAPI,
    prepare = Prepare,
    renderVisual = Render,
    refreshOptions = RefreshOptions,
    readFonts = function() return theme.font, theme.font end,
    getVersion = function() return generation end,
    options = {
        available = function() return Engine() ~= nil end,
        desc =
        "Independent ElvUI appearance on Retail and Forever. The same preferences are available in ElvUI > AzerothWaypoint. Tracker docking is unchanged, Blizzard native docking remains experimental."
    },
})
NS.Internal.ElvUI = Provider
function Provider.GetStatus() return theme.signature and "ready" or nil, Provider.lastError or unavailable end

local function Changed()
    dirty = true
    fontValues, fontOrder, fontPaths = nil, nil, nil
    Provider.RequestRefresh()
end

local function OptionsItem(item, order)
    if item.type == "action" then
        return {
            type = "execute",
            name = item.label,
            desc = item.desc,
            order = order,
            func =
                item.run
        }
    end
    local option = {
        name = item.label,
        desc = item.desc,
        order = order,
        disabled = item.disabled,
        type = ({ toggle = "toggle", slider = "range", dropdown = "select", color = "color" })[item.type],
        min = item.min,
        max = item.max,
        step = item.step,
        get = function() return item.get() end,
        set = function(_, value) item.set(value) end
    }
    if item.type == "dropdown" then
        local function Values()
            if item.choices then return item.choices() end
            return type(item.values) == "function" and item.values() or item.values
        end
        option.values = Values
        if item._awpSetting == "fontKey" then
            option.dialogControl = "LSM30_Font"
            option.values = function()
                FontChoices(); return fontPaths
            end
            option.get = function()
                local key = item.get(); return key == "general" and "Follow ElvUI" or key
            end
            option.set = function(_, key) item.set(key == "Follow ElvUI" and "general" or key) end
        end
    elseif item.type == "color" then
        option.get = function() return unpack(item.get()) end
        option.set = function(_, r, g, b) item.set({ r, g, b }) end
        option.hasAlpha = false
    end
    return option
end

local function BuildOptions()
    local e = Engine()
    if not e or not e.Options then return end
    local root = { type = "group", name = "AzerothWaypoint", childGroups = "tree", args = {} }
    local settingsShortcut = {
        type = "execute",
        name = "Open AWP Settings",
        order = 1,
        func = function()
            e:Config_CloseWindow()
            NS.OpenOptionsPanel()
        end
    }
    if not GetAPI() then
        root.args.options = settingsShortcut
        root.args.notice = { type = "description", name = unavailable or "Waiting for ElvUI initialization.", order = 2 }
        e.Options.args.AzerothWaypoint = root
        optionsBuilt = true
        return
    end
    local reset = C_Texture.GetAtlasInfo("common-icon-rotateleft")
    local resetCoords = { reset.leftTexCoord, reset.rightTexCoord, reset.topTexCoord, reset.bottomTexCoord }
    local categories = {
        overview = { name = "Overview", order = 1 },
        viewers = { name = "Guide Viewers", order = 2 },
        overlay = { name = "World Overlay", order = 3 },
        windows = { name = "AWP Windows", order = 4 },
    }
    for key, category in pairs(categories) do
        category.type, category.childGroups, category.args = "group", "tab", {}
        root.args[key] = category
    end
    for index, group in ipairs(Provider.GetOptionGroups()) do
        local category = not group.surface and categories.overview or
            group.surface:sub(1, 6) == "guide." and categories.viewers
            or group.surface:sub(1, 8) == "windows." and categories.windows or categories.overlay
        local key = group.surface or "main"
        local surface = category.args[key]
        if not surface then
            surface = { type = "group", name = group.surfaceLabel or "Appearance", order = index, args = {} }
            category.args[key] = surface
        end
        local section = { type = "group", inline = true, name = group.label, order = index, args = {} }
        surface.args["group" .. index] = section
        for n, item in ipairs(group.items) do
            section.args[item._awpSetting or "enabled"] = OptionsItem(item, n * 2)
            if item.type ~= "action" then
                section.args[(item._awpSetting or "enabled") .. "Reset"] = {
                    type = "execute",
                    name = "",
                    image = reset.file,
                    imageWidth = 16,
                    imageHeight = 16,
                    imageCoords = resetCoords,
                    desc = "Reset " .. item.label,
                    order = n * 2 + 1,
                    width = 0.2,
                    disabled = item.disabled,
                    func = function() item.set(item.default()) end
                }
            end
        end
        section.args.resetSection = {
            type = "execute",
            name = "Reset " .. group.label,
            order = 1000,
            func = function() for _, item in ipairs(group.items) do if item.set then item.set(item.default()) end end end
        }
    end
    categories.overview.args.shortcuts = {
        type = "group",
        inline = true,
        name = "AWP",
        order = 1000,
        args = {
            options = settingsShortcut,
            queue = { type = "execute", name = "Open AWP Queue", order = 2, func = function() NS.ShowQueuePanel() end },
            help = { type = "execute", name = "Open AWP Help", order = 3, func = function() NS.ShowHelp("overview") end },
            notice = { type = "description", order = 4, name = "Appearance does not change the tracker host. ElvUI uses Blizzard's Objective Tracker, AWP native docking remains experimental." },
        }
    }
    e.Options.args.AzerothWaypoint = root
    optionsBuilt = true
end

local function Initialize()
    local e = Engine()
    if not e then return end
    local ep = e.Libs and e.Libs.EP
    if not registered and ep and type(ep.RegisterPlugin) == "function" and type(ep.HookInitialize) == "function" then
        registered = true
        ep:RegisterPlugin("AzerothWaypoint", BuildOptions)
        ep:HookInitialize(Provider, Initialize)
    end
    if not GetAPI() then return end
    if not subscribed then
        subscribed = true
        for _, name in ipairs({ "UpdateMedia", "UpdateEnd", "PixelScaleChanged", "LSM_Update" }) do
            if type(e[name]) == "function" then hooksecurefunc(e, name, Changed) end
        end
    end
    if optionsBuilt then
        BuildOptions(); RefreshOptions()
    end
    Changed()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_LOGIN" or addon == "ElvUI" or addon == "ElvUI_Options" or addon == "AzerothWaypoint" then
        Initialize()
    end
end)
