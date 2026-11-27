-- ============================================================
-- UI Style provider framework
-- ============================================================
--
-- Provides one settings and restoration lifecycle for UI Styles. A provider
-- supplies native fonts and colors, the shared code compares their resolved
-- values before refreshing controls.

local NS = _G.AzerothWaypointNS
local Appearance = NS.Internal.Appearance

function Appearance.CreateStyleProvider(config)
    local styleName = config.label
    local followStyle = "Follow " .. styleName
    local Provider = {
        id = config.key,
        label = styleName,
        addonName = config.addonName,
        counters = { requested = 0, coalesced = 0, applied = 0, surfacesResolved = 0 }
    }
    Provider.options = config.options
    if Provider.options then Provider.options.label = styleName end
    Provider.stylesDisclosure = config.stylesDisclosure
    Provider.stylesSectionHeaders = config.stylesSectionHeaders
    local surfaces = {
        { key = "plaque",          page = "overlay", tab = "Pinpoint",        label = "Pinpoint plaque" },
        { key = "waypoint",        page = "overlay", tab = "World marker",    label = "World marker labels" },
        { key = "navigator",       page = "overlay", tab = "Navigator",       label = "Navigator and distance labels" },
        { key = "windows.options", page = "windows", tab = "Options",         label = "Options window" },
        { key = "windows.queue",   page = "windows", tab = "Queue",           label = "Queue window" },
        { key = "windows.taxi",    page = "windows", tab = "Taxi List",       label = "Taxi List",                    fixedTextSize = true },
        { key = "windows.help",    page = "windows", tab = "Help",            label = "Help window" },
        { key = "windows.search",  page = "windows", tab = "Settings search", label = "Settings search" },
        { key = "travel",          page = "overlay", tab = "Travel actions",  label = "Travel action controls" },
    }
    for index = #NS.Constants.GUIDE_PROVIDERS, 1, -1 do
        local provider = NS.Constants.GUIDE_PROVIDERS[index]
        table.insert(surfaces, 1, {
            key = "guide." .. provider.key,
            page = "viewers",
            tab = provider.label,
            label = provider.label .. " Viewer",
            guide = true,
            forever = provider.forever
        })
    end
    local known = {}
    for _, surface in ipairs(surfaces) do known[surface.key] = surface end
    Provider.surfaces = surfaces
    local facets = {
        enabled = true,
        fonts = true,
        colors = false,
        shell = true,
        header = true,
        controls = true,
        progress = true,
        actions = true
    }
    local fields = {
        fontKey = { type = "dropdown", default = "general", label = "Font" },
        outline = {
            type = "dropdown",
            default = "inherit",
            label = "Text outline",
            values = {
                inherit = followStyle, none = "None", thin = "Thin", thick = "Thick" }
        },
        shadow = {
            type = "dropdown",
            default = "inherit",
            label = "Text shadow",
            values = {
                inherit = followStyle, on = "On", off = "Off" }
        },
        textScale = { type = "slider", default = 1, label = "Text scale", min = 0.5, max = 2, step = 0.05 },
        customSizes = { type = "toggle", default = false, label = "Use custom text sizes" },
        headingSize = { type = "slider", default = 14, label = "Heading size", min = 10, max = 20, step = 1 },
        bodySize = { type = "slider", default = 13, label = "Goal / body text size", min = 9, max = 24, step = 1 },
        tipSize = { type = "slider", default = 12, label = "Notes / context text size", min = 8, max = 22, step = 1 },
        progressSize = { type = "slider", default = 11, label = "Progress text size", min = 8, max = 14, step = 1, guide = true },
        colorSource = {
            type = "dropdown",
            default = config.key,
            label = "Text color source",
            values = {
                [config.key] = styleName .. " palette", custom = "Custom colors below" }
        },
        textColor = { type = "color", default = { 1, 1, 1 }, label = "Goal / body text color", role = "TEXT" },
        titleColor = { type = "color", default = { 0, 0.67, 1 }, label = "Heading color", role = "TITLE" },
        tipColor = { type = "color", default = { 0.93, 0.93, 0.8 }, label = "Notes / context color", role = "LABEL" },
        progressColor = { type = "color", default = { 1, 1, 1 }, label = "Progress text color", role = "VALUE", guide = true },
        completeColor = { type = "color", default = { 0.58, 0.92, 0.52 }, label = "Completed goal color", role = "GOOD", guide = true },
        warningColor = { type = "color", default = { 1, 0.82, 0.2 }, label = "Warning color", role = "WARN", guide = true },
        failedColor = { type = "color", default = { 1, 0.42, 0.32 }, label = "Failed goal color", role = "BAD", guide = true },
        accentSource = {
            type = "dropdown",
            default = config.key,
            label = "Header text accent",
            guide = true,
            values = { [config.key] = styleName .. " accent", custom = "Custom accent below" }
        },
        accentColor = { type = "color", default = { 1, 0.82, 0.2 }, label = "Custom header text accent", role = "ACCENT", guide = true },
        ownProgressWidth = { type = "toggle", default = false, label = "Use custom progress width", guide = true },
        progressWidth = { type = "slider", default = 58, label = "Progress width", min = 40, max = 100, step = 1, guide = true },
    }
    local roleSupport = {
        plaque = { heading = true, tip = true, TITLE = true, LABEL = true },
        waypoint = { body = true, TEXT = true },
        navigator = { body = true, LABEL = true },
        travel = { body = true, TEXT = true },
        ["windows.queue"] = { heading = true, body = true, TITLE = true, TEXT = true },
        ["windows.taxi"] = { TITLE = true, TEXT = true, LABEL = true },
    }
    local sizeRoles = { headingSize = "heading", bodySize = "body", tipSize = "tip", progressSize = "progress" }

    -- These settings are shared by AWP and the UI addon's native options.
    local facetRows = {
        enabled = { label = "Use " .. styleName .. " style", desc = "Apply this area's settings when " .. styleName .. " is the active UI style." },
        fonts = { label = "Apply selected font", desc = "Enable the Font picker below. General follows " .. styleName .. "'s current font. Choose another font to use it in this area." },
        colors = { label = "Apply text colors", desc = "Apply the text-color source and colors below. Turning this off preserves AWP's normal text colors." },
        header = { label = "Use " .. styleName .. " header", desc = "Use " .. styleName .. "'s header background, border, bevel and shadow. Turning this off restores the normal header." },
        controls = { label = "Use " .. styleName .. " buttons", desc = "Style this Viewer's navigation and menu buttons." },
        actions = { label = "Style guide action panels", desc = "Use " .. styleName .. "'s panel and buttons for this guide's movable action panel. Fonts and text colors follow this guide's choices above." },
        progress = { label = "Use " .. styleName .. " progress", desc = "Style this Viewer's progress bar. The selected progress visibility is preserved." },
        shell = { label = "Use " .. styleName .. " panel", desc = "Use " .. styleName .. "'s panel artwork and appearance settings for this area. Turning this off restores the normal panel." },
    }
    local optionSections = {
        { label = "UI Style",             rows = { "enabled" } },
        {
            label = "Font",
            desc = "Choose a font here. Outline and shadow can also be adjusted independently.",
            rows = { "fonts", "fontKey", "outline", "shadow" }
        },
        { label = "Text sizes",           sizing = true,                                                                                                                             rows = { "textScale", "customSizes", "headingSize", "bodySize", "tipSize", "progressSize" } },
        { label = "Text colors",          rows = { "colors", "colorSource", "textColor", "titleColor", "tipColor", "progressColor", "completeColor", "warningColor", "failedColor" } },
        { label = "Header",               guide = true,                                                                                                                              rows = { "header", "accentSource", "accentColor" } },
        { label = "Buttons and progress", guide = true,                                                                                                                              rows = { "controls", "actions", "progress", "ownProgressWidth", "progressWidth" } },
        { label = "Panel",                panel = true,                                                                                                                              rows = { "shell" } },
    }
    local fieldDescriptions = {
        fontKey =
            "Turn on Apply selected font to enable this picker. General follows " ..
            styleName .. ". Other choices apply only to this area.",
        outline =
            followStyle ..
            "'s outline or choose an explicit outline. An explicit choice also applies when Apply selected font is off.",
        shadow =
            followStyle ..
            "'s shadow or choose On or Off. An explicit choice also applies when Apply selected font is off.",
        textScale = "Scale this area's text independently of the font choice and custom text sizes.",
        customSizes =
        "Enable the size controls directly below. Turning this off restores the normal sizes while retaining your choices.",
        colorSource = "Turn on Apply text colors, then use " .. styleName .. "'s palette or choose Custom colors below.",
        ownProgressWidth =
        "Enable the Progress width slider directly below. The bar still fits the available header space.",
        progressWidth = "Turn on Use custom progress width above to enable this slider.",
    }
    for key, field in pairs(config.fields or {}) do
        assert(not fields[key], "Duplicate appearance field: " .. key)
        fields[key] = field
    end
    for _, section in ipairs(config.sections or {}) do optionSections[#optionSections + 1] = section end


    -- ============================================================
    -- Profile values and defaults
    -- ============================================================

    local function CopyValue(value)
        if type(value) == "table" then return { value[1], value[2], value[3] } end
        return value
    end

    local function Validate(key, value, surface)
        if facets[key] ~= nil then
            if type(value) == "boolean" then return value, true end
            return
        end
        local field = fields[key]
        if not field then return end
        if field.surfaces and not field.surfaces[surface] then return end
        if field.type == "toggle" then return value, type(value) == "boolean" end
        if field.type == "slider" then
            if type(value) ~= "number" or value ~= value then return end
            return math.max(field.min, math.min(field.max, value)), true
        end
        if field.type == "color" then
            if type(value) ~= "table" then return end
            for index = 1, 3 do
                if type(value[index]) ~= "number" or value[index] ~= value[index] or value[index] < 0 or value[index] > 1 then return end
            end
            return value, true
        end
        if type(value) ~= "string" or value == "" or field.values and not field.values[value] then return end
        return value, true
    end

    local normalizedSettings = setmetatable({}, { __mode = "k" })
    local fieldSchemas = {}
    for key in pairs(facets) do fieldSchemas[key] = { kind = "boolean" } end
    for key, field in pairs(fields) do
        local kind = field.type == "toggle" and "boolean" or field.type == "slider" and "number"
            or field.type == "color" and "rgb" or "string"
        fieldSchemas[key] = { kind = kind, min = field.min, max = field.max, step = field.step, values = field.values }
    end
    local surfaceSchemas = {}
    for surface in pairs(known) do
        local schema = {}
        for key in pairs(facets) do schema[key] = fieldSchemas[key] end
        for key, field in pairs(fields) do
            if not field.surfaces or field.surfaces[surface] then
                schema[key] = fieldSchemas[key]
            end
        end
        surfaceSchemas[surface] = { kind = "record", fields = schema }
    end
    NS.Internal.RegisterSavedVariableField("account", config.dbKey, {
        kind = "record",
        fields = {
            enabled = { kind = "boolean" }, surfaces = { kind = "map", entries = surfaceSchemas },
        },
        onClean = function()
            for entry in pairs(normalizedSettings) do normalizedSettings[entry] = nil end
        end
    }, true)
    local effective, palette = {}, {}
    local api, font, windowFont, reference
    local applying, lastSignature = false, nil
    local settingKeys = {}
    for key in pairs(facets) do settingKeys[#settingKeys + 1] = key end
    for key in pairs(fields) do settingKeys[#settingKeys + 1] = key end
    table.sort(settingKeys)
    function Provider.GetSettings(surface)
        local db = NS.GetDB()
        if type(db[config.dbKey]) ~= "table" then db[config.dbKey] = { enabled = false, surfaces = {} } end
        local settings = db[config.dbKey]
        if type(settings.enabled) ~= "boolean" then settings.enabled = false end
        if not surface then return settings end
        if not known[surface] then return end
        if type(settings.surfaces) ~= "table" then settings.surfaces = {} end
        local entry = settings.surfaces[surface]
        if type(entry) ~= "table" then
            entry = {}; settings.surfaces[surface] = entry
        end
        if normalizedSettings[entry] then return entry end
        for key, default in pairs(facets) do
            if type(entry[key]) ~= "boolean" then entry[key] = default end
        end
        for key, field in pairs(fields) do
            if not field.surfaces or field.surfaces[surface] then
                local normalized, valid = Validate(key, entry[key], surface)
                if not valid then
                    entry[key] = CopyValue(field.default)
                elseif field.type ~= "color" then
                    entry[key] = normalized
                end
            end
        end
        normalizedSettings[entry] = true
        return entry
    end

    Provider.GetAPI = config.getAPI

    function Provider.IsEnabled(surface, facet)
        local value = effective[surface]
        return value ~= nil and value.enabled and value[facet or "enabled"] == true or false
    end

    function Provider.GetRGB(surface, role, facet)
        -- Viewer text has one selector. UI explicitly requests this palette.
        if known[surface] and known[surface].guide and (facet == nil or facet == "colors") then
            local settings = NS.GetGuideTrackerViewerSettings and NS.GetGuideTrackerViewerSettings(surface:sub(7))
            if not settings or settings.textColorMode ~= "theme" then return end
            facet = "enabled"
        end
        if not Provider.IsEnabled(surface, facet or "colors") then return end
        local current = effective[surface]
        local color = current and current.palette[role or "TEXT"] or palette[role or "TEXT"] or palette.TEXT
        if color then return color[1], color[2], color[3] end
    end

    function Provider.GetFont(surface, textKind)
        local current = effective[surface]
        if not current or not current.enabled then return end
        -- Providers may opt into native control baselines without changing
        -- the ordinary per-area typography used by other text/providers.
        return current.shell and current.controlTextStyles and current.controlTextStyles[textKind] or current.textStyle
    end

    function Provider.GetProgressWidth(surface)
        local current = effective[surface]
        return current and current.enabled and current.progress and current.ownProgressWidth and current.progressWidth or
            nil
    end

    function Provider.RenderVisual(holder, record)
        record.renderers = record.renderers or {}
        local state = record.renderers[config.key]
        if not state then
            state = { root = holder }; record.renderers[config.key] = state
        end
        local result = config.renderVisual(api, state, record, effective[record.surface])
        record.currentState = result
        return result
    end

    function Provider.StyleOptionHighlight(texture, surface)
        if not Provider.IsEnabled(surface, "shell") then return false end
        local r, g, b = Provider.GetRGB(surface, "VALUE", "shell")
        texture:SetColorTexture(r, g, b, 0.03)
        return true
    end

    -- ============================================================
    -- Effective surface styles
    -- ============================================================

    local function ReadFont(sample)
        local file, _, flags = sample:GetFont()
        local sr, sg, sb, sa = sample:GetShadowColor()
        local sx, sy = sample:GetShadowOffset()
        return { file = file, flags = flags, sr = sr, sg = sg, sb = sb, sa = sa, sx = sx, sy = sy }
    end

    local function ResolveTextStyle(settings, source, fixedTextSize)
        local style = {
            scale = fixedTextSize and 1 or settings.textScale,
            customSizes = not fixedTextSize and settings.customSizes,
            sizes = {
                heading = settings.headingSize,
                body = settings.bodySize,
                tip = settings.tipSize,
                progress = settings.progressSize,
                button = settings.bodySize,
                dropdown = settings.bodySize
            }
        }
        if settings.fonts then
            style.file, style.headingFile, style.flags = source.file, source.headingFile, source.flags
            style.size = not fixedTextSize and source.size or nil
            style.sr, style.sg, style.sb, style.sa, style.sx, style.sy = source.sr, source.sg, source.sb, source.sa,
                source.sx, source.sy
            if settings.fontKey ~= "general" then style.file, style.headingFile = api.FontFile(settings.fontKey), nil end
        end
        if settings.outline ~= "inherit" then
            style.flags = ({ none = "", thin = "OUTLINE", thick = "THICKOUTLINE" })[settings.outline]
        end
        if settings.shadow ~= "inherit" then
            style.sr, style.sg, style.sb = 0, 0, 0
            style.sa, style.sx, style.sy = settings.shadow == "off" and 0 or 1, 1, -1
        end
        style.active = settings.fonts or style.customSizes or style.scale ~= 1
            or settings.outline ~= "inherit" or settings.shadow ~= "inherit"
        style.signature = table.concat(
        { style.file or "awp", style.headingFile or "", style.flags or "awp", style.scale,
            tostring(style.customSizes), settings.headingSize, settings.bodySize, settings.tipSize, settings
            .progressSize,
            style.size or "", style.sa or "", style.sx or "", style.sy or "" }, ":")
        return style
    end

    local function ResolveSurface(settings, surface)
        Provider.counters.surfacesResolved = Provider.counters.surfacesResolved + 1
        local resolved = {}
        for key in pairs(facets) do resolved[key] = settings[key] end
        for key in pairs(fields) do resolved[key] = CopyValue(settings[key]) end
        resolved.palette = {}
        for role, color in pairs(palette) do resolved.palette[role] = color end
        if settings.colors and settings.colorSource == "custom" then
            for key, field in pairs(fields) do
                if field.role and field.role ~= "ACCENT" then resolved.palette[field.role] = CopyValue(settings[key]) end
            end
        end
        if settings.accentSource == "custom" then resolved.palette.ACCENT = CopyValue(settings.accentColor) end
        local source = surface:sub(1, 8) == "windows." and windowFont or font
        local fixedTextSize = known[surface].fixedTextSize
        local style = ResolveTextStyle(settings, source, fixedTextSize)
        if source.controlStyles then
            resolved.controlTextStyles = {}
            for _, kind in ipairs({ "button", "dropdown" }) do
                local control = ResolveTextStyle(settings, source.controlStyles[kind], fixedTextSize)
                resolved.controlTextStyles[kind] = control
                style.signature = style.signature .. ":" .. kind .. ":" .. control.signature
            end
        end
        resolved.textStyle = style
        return resolved
    end

    -- Effective settings hold private RGB copies, so in-place edits to a saved
    -- profile can be detected without rebuilding all its visual styles.
    local function SurfaceMatches(saved, previous)
        if not previous then return false end
        for _, key in ipairs(settingKeys) do
            local value, old = saved[key], previous[key]
            if type(value) == "table" then
                if not old or value[1] ~= old[1] or value[2] ~= old[2] or value[3] ~= old[3] then return false end
            elseif value ~= old then
                return false
            end
        end
        return not saved.fonts or saved.fontKey == "general" or previous.textStyle.file == api.FontFile(saved.fontKey)
    end

    local fontFields = { "file", "headingFile", "size", "flags", "sr", "sg", "sb", "sa", "sx", "sy" }
    local function AppendFont(signature, style)
        for _, key in ipairs(fontFields) do
            signature[#signature + 1] = tostring(style and style[key])
        end
    end

    -- ============================================================
    -- Refresh and invalidation
    -- ============================================================

    local function Refresh()
        if applying then return end
        applying = true
        local previous = effective
        api = Provider.active and Provider.GetAPI() or nil
        if api and config.prepare then config.prepare() end
        local root = Provider.GetSettings()
        if not root then error("Appearance settings are unavailable") end
        local signature = { tostring(Provider.active), tostring(root.enabled), tostring(api ~= nil),
            tostring(config.getVersion and config.getVersion() or "") }
        if api and root and root.enabled then
            if config.readFonts then
                font, windowFont = config.readFonts()
            else
                if not reference then
                    reference = CreateFrame("Frame")
                    reference:Hide()
                    reference.font = api.Text(reference, "body")
                    reference.window = CreateFrame("Frame", nil, reference)
                    api.Skin(reference.window, { window = true })
                    reference.windowFont = api.Text(reference.window, "body")
                end
                font, windowFont = ReadFont(reference.font), ReadFont(reference.windowFont)
            end
            local colors = api.Colors()
            palette = {}
            for name, color in pairs(colors) do palette[name] = { color[1], color[2], color[3] } end
            palette.ACCENT = { api.Accent() }
            palette.OFF = palette.OFF or { 0.4, 0.4, 0.4 }
            for _, source in ipairs({ font, windowFont }) do
                AppendFont(signature, source)
                if source.controlStyles then
                    AppendFont(signature, source.controlStyles.button)
                    AppendFont(signature, source.controlStyles.dropdown)
                end
            end
            local roles = {}
            for role in pairs(palette) do roles[#roles + 1] = role end
            table.sort(roles)
            for _, role in ipairs(roles) do
                signature[#signature + 1] = role
                for _, channel in ipairs(palette[role] or {}) do signature[#signature + 1] = tostring(channel) end
            end
        end
        local fingerprint = table.concat(signature, ":")
        local themeChanged = fingerprint ~= lastSignature
        local nextEffective = {}
        local changed = themeChanged
        if api and root.enabled then
            for _, surface in ipairs(surfaces) do
                local key = surface.key
                local saved = Provider.GetSettings(key)
                if themeChanged or not SurfaceMatches(saved, previous[key]) then
                    nextEffective[key] = ResolveSurface(saved, key)
                    changed = true
                else
                    nextEffective[key] = previous[key]
                end
            end
        end
        if not changed then
            applying = false
            return
        end
        Appearance.Restore()
        effective = nextEffective
        Appearance.provider = Provider
        Appearance.RunRefreshCallbacks("beforeVisuals")
        Appearance.Refresh()
        Appearance.RunRefreshCallbacks("afterVisuals")
        if NS.InvalidateOverlaySettings then NS.InvalidateOverlaySettings() end
        local function MetricsChanged(surface, facet)
            local old, current = previous[surface], effective[surface]
            if facet or surface == "windows.options" or surface == "windows.search" then
                local key = facet or "shell"
                if (old and old.enabled and old[key] == true or false) ~=
                    (current and current.enabled and current[key] == true or false) then
                    return true
                end
            end
            if facet then return false end
            local before = old and old.enabled and old.textStyle.active and old.textStyle.signature or nil
            local after = current and current.enabled and current.textStyle.active and current.textStyle.signature or nil
            return before ~= after
        end
        Appearance.Reflow(MetricsChanged)
        Provider.counters.applied = Provider.counters.applied + 1
        if not Provider.visualFailure then lastSignature = fingerprint end
        applying = false
    end

    function Provider.VisualFailed(message)
        effective, lastSignature = {}, nil
        Provider.visualFailure, Provider.lastError = message, message
        Appearance.Restore()
        if not applying then
            if InCombatLockdown and InCombatLockdown() then
                Appearance.deferred = true
            else
                Appearance.RunRefreshCallbacks("afterVisuals")
            end
        end
    end

    local function FlushRefresh()
        Provider.visualFailure = nil
        local ok, err = pcall(Refresh)
        if ok then
            Provider.lastError = Provider.visualFailure; return
        end
        applying = false
        effective, lastSignature = {}, nil
        Appearance.Restore()
        Appearance.RunRefreshCallbacks("afterVisuals")
        local message = tostring(err)
        if Provider.lastError ~= message and NS.Msg then NS.Msg(styleName .. " style unavailable:", message) end
        Provider.lastError = message
    end

    function Provider.RequestRefresh()
        Provider.counters.requested = Provider.counters.requested + 1
        Appearance.RequestRefresh(Provider)
    end

    local function RefreshOptions()
        if config.refreshOptions then config.refreshOptions() end
    end
    Provider.RefreshOptions = RefreshOptions

    function Provider.Apply(active)
        Provider.active = active
        FlushRefresh()
    end

    -- ============================================================
    -- Settings controls
    -- ============================================================

    function Provider.SetSurfaceSettings(surface, values)
        if not known[surface] or type(values) ~= "table" then return false end
        local normalized = {}
        for key, value in pairs(values) do
            local result, valid = Validate(key, value, surface)
            if not valid then return false end
            normalized[key] = CopyValue(result)
        end
        local saved = Provider.GetSettings(surface)
        if not saved then return false end
        local changed = false
        for key, value in pairs(normalized) do
            local old = saved[key]
            local same = old == value or type(old) == "table" and type(value) == "table"
                and old[1] == value[1] and old[2] == value[2] and old[3] == value[3]
            if not same then
                saved[key] = value; changed = true
            end
        end
        if not changed then return true end
        RefreshOptions()
        Provider.RequestRefresh()
        return true
    end

    function Provider.SetSetting(surface, key, value)
        if surface then return Provider.SetSurfaceSettings(surface, { [key] = value }) end
        if key ~= "enabled" or type(value) ~= "boolean" then return false end
        if value then
            Appearance.Select(config.key)
        elseif Appearance.GetSelectedID() == config.key then
            Appearance.Select("awp")
        end
        RefreshOptions()
        return true
    end

    local function CreateOptionItem(surface, fieldKey)
        local key = surface.key
        local field, facet = fields[fieldKey], facetRows[fieldKey]
        local item = {
            _awpSetting = fieldKey,
            type = facet and "toggle" or field.type,
            label = (facet or field).label,
            desc = (facet or field).desc or fieldDescriptions[fieldKey],
            get = function() return Provider.GetSettings(key)[fieldKey] end,
            set = function(value) return Provider.SetSetting(key, fieldKey, value) end,
            default = function()
                if facet then return facets[fieldKey] end
                return CopyValue(field.default)
            end,
        }
        if facet then return item end
        if surface.guide and fieldKey == "colorSource" then
            item.desc =
            "Choose UI colors in this guide's Tracker Viewer settings to use this palette."
        end
        item.values, item.min, item.max, item.step = field.values, field.min, field.max, field.step
        item.unit, item.format = field.unit, field.format
        local public = Provider.GetAPI()
        if fieldKey == "fontKey" and public and public.FontRow then
            local fontRow = public.FontRow(fieldKey, field.label, item.desc)
            for name, value in pairs(fontRow or {}) do if name ~= "key" then item[name] = value end end
        end
        if fieldKey == "fontKey" then
            item.disabled = function() return not Provider.GetSettings(key).fonts end
        elseif fieldKey:find("Size$") then
            item.desc = "Turn on Use custom text sizes above to enable this size control."
            item.disabled = function() return not Provider.GetSettings(key).customSizes end
        elseif field.type == "color" then
            item.desc = fieldKey == "accentColor"
                and "Choose Custom accent below as the Header text accent to enable this color."
                or "Turn on Apply text colors and choose Custom colors below as the Text color source to enable this color."
            item.disabled = function()
                local settings = Provider.GetSettings(key)
                if not settings then return true end
                if fieldKey == "accentColor" then return settings.accentSource ~= "custom" end
                local viewer = surface.guide and NS.GetGuideTrackerViewerSettings(key:sub(7))
                return (surface.guide and viewer.textColorMode ~= "theme" or not surface.guide and not settings.colors)
                    or settings.colorSource ~= "custom"
            end
            if surface.guide and fieldKey ~= "accentColor" then
                item.desc =
                "Choose UI colors in this guide's Tracker Viewer settings, then select Custom colors below here."
            end
        elseif fieldKey == "progressWidth" then
            item.disabled = function() return not Provider.GetSettings(key).ownProgressWidth end
        elseif field.enabledBy then
            item.disabled = function() return Provider.GetSettings(key)[field.enabledBy] ~= field.enabledValue end
        end
        return item
    end

    function Provider.GetOptionSurfaces() return surfaces end

    function Provider.GetOptionGroups(surfaceKey)
        local groups = {}
        if not surfaceKey or surfaceKey == "overview" then
            groups[1] = {
                label = styleName .. " Style",
                desc =
                "General > UI Style controls which style AWP uses. Guide activity and tracker docking are configured separately.",
                items = {
                    {
                        _awpSetting = "enabled",
                        type = "toggle",
                        label = "Enable " .. styleName .. " Styling",
                        desc =
                            "Use " ..
                            styleName ..
                            " as AWP's UI style. Turning this off restores AWP's own look and keeps your settings for each area.",
                        get = function() return Provider.GetSettings().enabled end,
                        set = function(value) return Provider.SetSetting(nil, "enabled", value) end,
                        default = function() return true end
                    },
                }
            }
        end
        local selected = known[surfaceKey]
        for _, surface in ipairs(not surfaceKey and surfaces or selected and { selected } or {}) do
            local key = surface.key
            if surface.guide then
                groups[#groups + 1] = {
                    label = "Viewer text",
                    surface = key,
                    tab = surface.tab,
                    surfaceLabel = surface.label,
                    desc =
                    "Auto colors and final text-size overrides are shared Viewer settings. UI sizes below are the inherited baseline.",
                    items = { {
                        type = "action",
                        label = "Open " .. surface.label .. " text settings",
                        run = function()
                            NS.OpenOptionsPanel()
                            local canvas = NS.Internal.Interface and NS.Internal.Interface.canvas
                            if canvas and canvas.SelectOptionsPage then canvas.SelectOptionsPage(key:sub(7), "viewer") end
                        end
                    } }
                }
            end
            local hasShell = surface.guide or key == "plaque" or key == "travel"
                or key:sub(1, 8) == "windows." and key ~= "windows.search"
            local supported = roleSupport[key]
            for _, section in ipairs(optionSections) do
                if (not section.guide or surface.guide) and (not section.panel or hasShell and not surface.guide)
                    and (not section.sizing or not surface.fixedTextSize)
                    and (not section.surfaces or section.surfaces[key]) then
                    local group = {
                        label = section.label,
                        desc = section.desc,
                        surface = key,
                        surfaceLabel = surface.label,
                        tab = surface.tab,
                        items = {}
                    }
                    for _, fieldKey in ipairs(section.rows) do
                        local field = fields[fieldKey]
                        local usedRole = not field or not supported or (not field.role or supported[field.role])
                            and (not sizeRoles[fieldKey] or supported[sizeRoles[fieldKey]])
                        if usedRole and (not field or not field.guide or surface.guide)
                            and not (surface.guide and fieldKey == "colors") then
                            group.items[#group.items + 1] = CreateOptionItem(surface, fieldKey)
                        end
                    end
                    if #group.items > 0 then groups[#groups + 1] = group end
                end
            end
        end
        return groups
    end

    Appearance.RegisterProvider(Provider)
    return Provider
end
