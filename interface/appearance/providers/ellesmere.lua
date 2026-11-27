-- ============================================================
-- Ellesmere UI styling
-- ============================================================
--
-- Builds Ellesmere-styled controls and registers AWP's options in Ellesmere's
-- settings window.

local NS = _G.AzerothWaypointNS
local Appearance = NS.Internal.Appearance
local skin, registered, pluginRegistered, unavailableReason
---@type table<string, any>
local theme = {}
local themeDirty, themeGeneration = true, 0
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ICON = { 1, 1, 1 }
local MASK = "Interface\\AddOns\\AzerothWaypoint\\media\\interface\\chamfer-mask.tga"
local API = {}
local requiredSkin = { "IsEnabled", "GetStyle", "GetAccentColor", "GetPanelColor", "ApplyBarFill", "OnLooksChanged" }
local requiredCore = { "GetFontPath", "GetFontOutlineFlag", "GetFontUseShadow", "MakeRoundedBorder", "RoundBody",
    "MakeStyledButton", "MakeDropdownArrow",
    "ProfileWindowSkinLook", "GetActiveProfileData", "GetFontsDB", "RenderedLook" }

local function UI() return rawget(_G, "EllesmereUI") end

local function InspectAPI()
    local ui = UI()
    if not ui then
        unavailableReason = "Ellesmere UI is not loaded."; return
    end
    if not skin then
        unavailableReason = "Enable Blizzard Skins+ and its AzerothWaypoint addon skin."; return
    end
    for _, name in ipairs(requiredSkin) do
        if type(skin[name]) ~= "function" then
            unavailableReason = "Missing Ellesmere skin capability: " .. name; return
        end
    end
    for _, name in ipairs(requiredCore) do
        if type(ui[name]) ~= "function" then
            unavailableReason = "Missing Ellesmere control capability: " .. name; return
        end
    end
    if not skin.IsEnabled() then
        unavailableReason = "Ellesmere addon skinning is disabled for AzerothWaypoint."; return
    end
    unavailableReason = nil
    return API
end

local function GetAPI()
    local ok, result = pcall(InspectAPI)
    if ok then return result end
    unavailableReason = tostring(result)
end

local function ResolveLook(ui)
    local look = ui.ProfileWindowSkinLook(ui.GetActiveProfileData(), ui.GetFontsDB())
    -- A current profile can have no window-style selection yet. The native
    -- rendered look is valid in that state, not an older-API alternative.
    if not look then look = ui.RenderedLook() end
    if look == "forever" and not NS.IsWoWForever() then return "blizzard" end
    if look == "forever" or look == "classic" or look == "blizzard" then return look end
    return "eui"
end

local function Prepare()
    if not themeDirty and theme.signature then return end
    local ui = UI()
    local nextTheme = {
        look = ResolveLook(ui),
        windowStyle = skin.GetStyle(),
        font = ui.GetFontPath(),
        flags = ui.GetFontOutlineFlag(),
        shadow = ui.GetFontUseShadow(),
        accent = { skin.GetAccentColor() },
        panel = { skin.GetPanelColor() },
        button = ui.WB_COLOURS,
        input = { ui.DD_BG_R, ui.DD_BG_G, ui.DD_BG_B, ui.DD_BG_A },
        inputHover = ui.DD_BG_HA,
        borderAlpha = ui.DD_BRD_A or 0.15
    }
    if not nextTheme.font or not nextTheme.button or not nextTheme.input[1] then
        error(
            "Ellesmere control palette is not ready")
    end
    if nextTheme.look == "forever" and (type(ui.ForeverBorder) ~= "function" or type(ui.ForeverBorderSeat) ~= "function"
            or type(ui.ForeverBorderShown) ~= "function" or not ui.FOREVER_BORDER) then
        error("Missing Ellesmere Forever border helpers")
    end
    local values = { nextTheme.look, nextTheme.windowStyle, nextTheme.font, nextTheme.flags or "", tostring(nextTheme
        .shadow),
        tostring(nextTheme.inputHover), tostring(nextTheme.borderAlpha) }
    for _, color in ipairs({ nextTheme.accent, nextTheme.panel, nextTheme.input, nextTheme.button }) do
        for _, value in ipairs(color) do values[#values + 1] = tostring(value) end
    end
    nextTheme.signature = table.concat(values, ":")
    nextTheme.renderKey = nextTheme.look .. ":" .. nextTheme.windowStyle
    if theme.signature ~= nextTheme.signature then
        themeGeneration = themeGeneration + 1
        nextTheme.generation = themeGeneration
        theme = nextTheme
    end
    themeDirty = false
end

local function ReadFonts()
    local font = {
        file = theme.font,
        flags = theme.flags or "",
        sr = 0,
        sg = 0,
        sb = 0,
        sa = theme.shadow and 1 or 0,
        sx = theme.shadow and 1 or 0,
        sy = theme.shadow and -1 or 0
    }
    return font, font
end

function API.Accent()
    if theme.accent then return unpack(theme.accent) end; return skin.GetAccentColor()
end

function API.Colors()
    return {
        TEXT = { 1, 1, 1 },
        LABEL = { 0.72, 0.72, 0.72 },
        VALUE = { 1, 1, 1 },
        TITLE = theme.accent,
        BUTTON = { 1, 0.82, 0 },
        BUTTON_HIGHLIGHT = { 1, 1, 1 },
        BUTTON_DISABLED = { 0.5, 0.5, 0.5 },
        GOOD = { 0.58, 0.92, 0.52 },
        WARN = { 1, 0.82, 0.2 },
        BAD = { 1, 0.42, 0.32 },
        OFF = { 0.4, 0.4, 0.4 }
    }
end

function API.FontFile(key)
    local ui = UI()
    return key == "general" and ui.GetFontPath() or ui.ResolveFontName(key)
end

local function FontChoices()
    local ui = UI()
    local nativeValues, nativeOrder
    if type(ui.BuildFontDropdownData) == "function" then
        nativeValues, nativeOrder = ui.BuildFontDropdownData()
    end

    -- Both settings panels use plain labels and keep AWP's saved inherit key.
    local values, order = { general = "Follow Ellesmere" }, { "general" }
    for _, key in ipairs(nativeOrder or ui.FONT_ORDER or {}) do
        if key ~= "__global" and key ~= "---" and not values[key] then
            local entry = nativeValues and nativeValues[key] or key
            local label = type(entry) == "table" and entry.text or entry
            if type(label) == "string" then
                values[key] = label
                order[#order + 1] = key
            end
        end
    end
    return values, order
end

function API.FontRow(key, label, desc)
    return { key = key, label = label, desc = desc, choices = FontChoices }
end

-- ============================================================
-- Borders and control artwork
-- ============================================================

local function NewLayer(parent, kind)
    local frame = CreateFrame(kind or "Frame", nil, parent, "BackdropTemplate")
    frame:SetAllPoints(parent); frame:EnableMouse(false); frame:SetFrameLevel(parent:GetFrameLevel())
    return frame
end

-- A fill and all its interaction washes take the same shape. The sliced mask
-- is original AWP coverage (32 square, 5-unit chamfers), not AddonSkins artwork.
local function Chamfer(frame, texture)
    local mask = frame:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetTextureSliceMargins(9, 9, 9, 9)
    mask:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    mask:SetAllPoints(frame); texture:AddMaskTexture(mask)
    return mask
end

local function Fill(frame, layer)
    local fill = frame:CreateTexture(nil, layer or "BACKGROUND")
    fill:SetAllPoints(); fill:SetColorTexture(1, 1, 1, 1)
    return fill
end

-- Stock backdrop artwork has its own interior, not the EUI rounded shape.
-- Keep the native tooltip/dialog insets proportional to the rendered edge.
local STOCK_TOOLTIP = {
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
}
local STOCK_DIALOG = {
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local function StockBorder(frame, kind, fill)
    local window = kind == "window" or kind == "panel" or kind == "menu"
    local profile = theme.look == "classic" and window and STOCK_DIALOG or STOCK_TOOLTIP
    local edgeSize = (kind == "window" or kind == "panel") and 16 or 8
    local scale = edgeSize / profile.edgeSize
    local source = profile.insets
    local insets = {
        left = source.left * scale,
        right = source.right * scale,
        top = source.top * scale,
        bottom = source.bottom * scale,
    }
    frame:SetBackdrop({ edgeFile = profile.edgeFile, edgeSize = edgeSize, tileEdge = true, insets = insets })
    if fill then
        -- Backdrop insets apply only to a backdrop's own background texture.
        -- Our palette-driven fill must use that same interior explicitly.
        fill:ClearAllPoints()
        fill:SetPoint("TOPLEFT", frame, "TOPLEFT", insets.left, -insets.top)
        fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -insets.right, insets.bottom)
    end
    return insets
end

local function Border(frame, kind, fill)
    local ui = UI()
    local state = { root = frame, fill = fill }
    if theme.look == "forever" then
        if fill then state.mask = Chamfer(frame, fill) end
        state.rim = ui.ForeverBorder(frame, "ARTWORK", 1)
        ui.ForeverBorderSeat(state.rim, frame, "TOPLEFT", 0, 0, 0, 0)
        ui.ForeverBorderShown(state.rim, true)
        local inset = ui.FOREVER_BORDER.fill
        state.insets = { left = inset, right = inset, top = inset, bottom = inset }
    elseif theme.look == "classic" or theme.look == "blizzard" then
        state.insets = StockBorder(frame, kind, fill)
    else
        state.border = ui.MakeRoundedBorder(frame, 1, 1, 1, theme.borderAlpha, fill)
    end
    return state
end

local function Panel(frame, kind)
    return Border(frame, kind, Fill(frame))
end

local function NumericInput(parent, record)
    local input = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    input:SetAutoFocus(false); input:SetSize(72, 22); input:SetMaxLetters(16); input:SetJustifyH("CENTER")
    input:SetPoint("BOTTOMRIGHT", record.frame, "TOPRIGHT", record.frame.reset and -28 or 0, 4)
    local state = Panel(input, "input")
    state.input = input
    return state
end

-- ============================================================
-- Widget creation and updates
-- ============================================================

local function MakeVisual(holder, record)
    local ui = UI()
    local kind = record.kind == "close" and "button" or record.kind
    local root = NewLayer(holder, kind == "button" and "Button" or "Frame")
    local state
    if record.kind == "close" and theme.look == "eui" then
        if type(skin.CloseButton) ~= "function" then error("Missing Ellesmere close-button helper") end
        state = { root = root, widget = root, hideText = true }
        skin.CloseButton(root)
    elseif kind == "window" and theme.look == "eui" then
        if type(skin.Shell) ~= "function" then error("Missing Ellesmere window shell") end
        state = { root = root }
        -- Let the native shell follow EUI/Modern backgrounds. AWP's existing
        -- title area is taller than the native fixed 25-unit strip, so its
        -- matching wash follows that area without moving text or controls.
        skin.Shell(root, { noBorder = true, noTopBar = true })
        if record.titleTarget then
            state.titleBand = root:CreateTexture(nil, "BACKGROUND", nil, -5)
            state.titleBand:SetAllPoints(record.titleTarget)
            state.titleBand:SetColorTexture(0, 0, 0, 0.5)
        end
    elseif kind == "header" and theme.look == "eui" then
        -- Ellesmere owns the section's bottom divider, including its physical
        -- pixel size. AWP supplies the header fill without adding another line.
        state = { root = root, fill = Fill(root) }
    elseif kind == "progress" then
        state = { root = root, keepProgressBorder = theme.look == "classic" }
        state.bar = CreateFrame("StatusBar", nil, root)
        state.bar:SetAllPoints(); state.bar:SetFrameLevel(root:GetFrameLevel()); state.bar:SetMinMaxValues(0, 100)
        state.bar:SetStatusBarTexture(WHITE); state.bar:EnableMouse(false)
        state.track = Fill(state.bar); state.track:SetColorTexture(0.04, 0.04, 0.04, 1)
        skin.ApplyBarFill(state.bar)
        local mask = theme.look == "forever" and Chamfer(state.bar, state.track) or ui.RoundBody(state.bar, state.track,
            2)
        if mask then state.bar:GetStatusBarTexture():AddMaskTexture(mask) end
        if theme.look == "forever" or theme.look == "blizzard" then
            local frame = NewLayer(root)
            frame:SetFrameLevel(root:GetFrameLevel() + 1)
            state.progressFrame = Border(frame, "progress")
            local inset = state.progressFrame.insets
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", root, "TOPLEFT", -inset.left, inset.top)
            frame:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", inset.right, -inset.bottom)
        end
    elseif kind == "slider" then
        state = { root = root }
        state.track = Fill(root); state.track:ClearAllPoints(); state.track:SetPoint("LEFT"); state.track:SetPoint(
            "RIGHT"); state.track:SetHeight(4)
        state.track:SetColorTexture(0.16, 0.16, 0.17, 1); ui.RoundBody(root, state.track, 2)
        state.fill = Fill(root, "BORDER"); state.fill:ClearAllPoints(); state.fill:SetPoint("LEFT"); state.fill
            :SetHeight(4)
        ui.RoundBody(root, state.fill, 2)
        state.thumb = Fill(root, "OVERLAY"); state.thumb:ClearAllPoints(); state.thumb:SetSize(14, 14)
        state.thumb:SetPoint("CENTER", record.regions[3], "CENTER"); ui.RoundBody(root, state.thumb, 7)
        state.numeric = NumericInput(root, record); state.input = state.numeric.input
    elseif kind == "artwork" then
        state = { root = root }
    elseif kind == "border" then
        state = Border(root, kind)
    elseif kind == "reset" then
        state = { root = root, icon = root:CreateTexture(nil, "ARTWORK") }
        state.icon:SetAllPoints(); state.icon:SetAtlas("common-icon-rotateleft", false)
    elseif kind == "scrollbar" then
        local thumb = root:CreateTexture(nil, "ARTWORK")
        thumb:SetPoint("TOP", root, "TOP")
        thumb:SetPoint("BOTTOM", root, "BOTTOM")
        thumb:SetWidth(4)
        thumb:SetColorTexture(1, 1, 1, 0.3)
        state = { root = root, thumb = thumb }
    elseif kind == "decoration" or kind == "menuRow" then
        state = { root = root, fill = Fill(root) }
        ui.RoundBody(root, state.fill, 2)
    elseif kind == "button" and theme.look == "classic" then
        state = { root = root, nativeButton = true }
        state.fill = Fill(root)
        state.fill:SetTexture("Interface\\Buttons\\UI-Panel-Button-Up")
        state.fill:SetTexCoord(0, 0.625, 0, 0.6875)
        state.highlight = Fill(root, "OVERLAY")
        state.highlight:SetTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
        state.highlight:SetTexCoord(0, 0.625, 0, 0.6875)
        state.highlight:SetBlendMode("ADD")
    elseif kind == "button" and theme.look == "eui" then
        state = { root = root, widget = root }
        state.fill, state.border, state.emptyLabel = ui.MakeStyledButton(root, "", 13, theme.button)
    else
        state = Panel(root, kind)
        if kind == "checkbox" then
            holder:ClearAllPoints(); holder:SetPoint("LEFT", record.target, "LEFT"); holder:SetSize(20, 20)
            state.check = root:CreateTexture(nil, "OVERLAY"); state.check:SetAllPoints()
            state.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        elseif kind == "dropdown" then
            state.arrow = ui.MakeDropdownArrow(root, 12, ui.PanelPP)
        end
    end
    if record.kind == "close" and theme.look ~= "eui" then
        state.hideText = true
        state.closeGlyph = root:CreateTexture(nil, "OVERLAY")
        state.closeGlyph:SetAtlas("uitools-icon-close", false)
        state.closeGlyph:SetSize(14, 14)
        state.closeGlyph:SetPoint("CENTER", root, "CENTER", 0, 0)
    end
    if kind == "dropdown" or kind == "input" or kind == "inset" then state.inputKind = true end
    return state
end

local function Paint(state, record)
    local kind = record.kind == "close" and "button" or record.kind
    if kind == "button" then state.iconColor = ICON end
    if state.bar and state.value ~= record.value then
        state.bar:SetValue(record.value); state.value = record.value
    end
    if state.generation == theme.generation and state.hovered == record.hovered and state.pressed == record.pressed
        and state.enabled == record.enabled and state.selected == record.selected and state.checked == record.checked
        and state.focused == record.focused then
        return
    end
    state.generation, state.hovered, state.pressed, state.enabled, state.selected, state.checked =
        theme.generation, record.hovered, record.pressed, record.enabled, record.selected, record.checked
    state.focused = record.focused
    local accent = theme.accent
    if state.nativeButton then
        state.fill:SetTexture(record.pressed and "Interface\\Buttons\\UI-Panel-Button-Down" or
            "Interface\\Buttons\\UI-Panel-Button-Up")
        state.fill:SetVertexColor(1, 1, 1, record.enabled and 1 or 0.4)
        state.highlight:SetShown(record.enabled and (record.hovered or record.selected) == true)
        state.textRole = not record.enabled and "BUTTON_DISABLED"
            or (record.kind == "close" or record.hovered or record.selected) and "BUTTON_HIGHLIGHT" or "BUTTON"
    elseif state.fill then
        local color = state.inputKind and theme.input or theme.panel
        local r, g, b, a = color[1], color[2], color[3], color[4] or 1
        if kind == "button" then
            local c = theme.button
            local first = record.hovered and 5 or 1
            r, g, b, a = c[first], c[first + 1], c[first + 2], c[first + 3]
        elseif kind == "header" and theme.look ~= "eui" then
            a = 0.95
        elseif kind == "menuRow" then
            r, g, b = accent[1], accent[2], accent[3]; a = record.hovered and 0.12 or record.selected and 0.07 or 0
        elseif kind == "slider" then
            r, g, b, a = accent[1], accent[2], accent[3], 1
        elseif kind == "decoration" then
            r, g, b, a = accent[1], accent[2], accent[3], 0.12
        end
        if record.pressed then r, g, b = r * 0.8, g * 0.8, b * 0.8 end
        state.fill:SetColorTexture(r, g, b, a)
    end
    if state.border then state.border:SetColor(1, 1, 1, (record.hovered or record.focused) and 0.3 or theme.borderAlpha) end
    if state.icon then state.icon:SetVertexColor(unpack(record.hovered and accent or { 0.65, 0.65, 0.65, 1 })) end
    if state.closeGlyph then state.closeGlyph:SetVertexColor(1, 1, 1, record.hovered and 1 or 0.75) end
    if state.check then
        state.check:SetShown(record.checked); state.check:SetVertexColor(unpack(accent))
    end
    state.root:SetAlpha(record.enabled and 1 or 0.4)
    if state.input then
        state.input:SetFont(theme.font, 12, theme.flags or "")
        state.numeric.fill:SetColorTexture(unpack(theme.input))
    end
end

local function RenderVisual(_, owner, record)
    owner.looks = owner.looks or {}
    local key = theme.renderKey
    local state = owner.looks[key]
    if not state then
        state = MakeVisual(owner.root, record); owner.looks[key] = state
    end
    if owner.visible ~= state then
        if owner.visible then owner.visible.root:Hide() end
        owner.visible = state
        state.root:Show()
    end
    Paint(state, record)
    return state
end

local optionsPending = false
local optionGroups
local optionModules = { "overview", "viewers", "overlay", "windows" }
local pendingOptionModules, moduleSearch, modulePages = {}, {}, {}
local searchHeaders = {}

-- ============================================================
-- Option groups and refresh
-- ============================================================

local function OptionGroups()
    if not optionGroups then optionGroups = NS.Internal.Ellesmere.GetOptionGroups() end
    return optionGroups
end

local function OptionCategory(group)
    return not group.surface and "overview" or group.surface:sub(1, 6) == "guide." and "viewers"
        or group.surface:sub(1, 8) == "windows." and "windows" or "overlay"
end

local function ParkSearchHeader(kind)
    local pages = searchHeaders[kind]
    local state = pages and pages[modulePages[kind]]
    if not state or not state.root:IsVisible() then return end
    local parent = state.root:GetParent()
    -- Ellesmere tears down the header before rebuilding the body. Keep our
    -- own input visible through that synchronous pass so focus/selection stay
    -- intact, the header builder reattaches the same frame before returning.
    state.root:SetParent(UIParent)
    return state, parent
end

local function FlushOptions()
    optionsPending = false
    local ui = UI()
    if not ui or not pluginRegistered then return end
    local active, refreshActive = ui:GetActiveModule(), false
    local parked, parkedParent
    for key in pairs(pendingOptionModules) do
        local moduleKey = ui.GetPluginModuleKey("AzerothWaypoint", key)
        if active == moduleKey then
            refreshActive = true
            parked, parkedParent = ParkSearchHeader(key)
        end
        ui:InvalidateModulePageCache(moduleKey)
        pendingOptionModules[key] = nil
    end
    if refreshActive then
        local ok, err = pcall(ui.RefreshPage, ui, true)
        -- A deferred or failed native build must not leave controls on UIParent.
        if parked and parked.root:GetParent() == UIParent then
            parked.root:Hide()
            parked.root:SetParent(parkedParent)
        end
        if not ok then error(err, 0) end
    end
end

local function RefreshOptions(kind)
    if kind then
        pendingOptionModules[kind] = true
    else
        optionGroups = nil
        for _, key in ipairs(optionModules) do pendingOptionModules[key] = true end
    end
    if optionsPending then return end
    optionsPending = true
    C_Timer.After(0, FlushOptions)
end

local Ellesmere = Appearance.CreateStyleProvider({
    key = "ellesmere",
    label = "Ellesmere UI",
    addonName = "EllesmereUI",
    dbKey = "ellesmereAppearance",
    getAPI = GetAPI,
    refreshOptions = RefreshOptions,
    prepare = Prepare,
    readFonts = ReadFonts,
    renderVisual = RenderVisual,
    getVersion = function() return themeGeneration end,
    options = {
        available = function() return UI() ~= nil end,
        desc =
        "Match Ellesmere UI on Retail and Forever. Enable Blizzard Skins+ and its AzerothWaypoint skin. Tracker hosting is configured separately."
    },
})
NS.Internal.Ellesmere = Ellesmere

function Ellesmere.GetStatus() return theme.look, Ellesmere.lastError or unavailableReason end

local function Changed()
    themeDirty = true
    RefreshOptions()
    Ellesmere.RequestRefresh()
end

local function OnSharedFontRegistered(_, kind, name)
    if kind ~= "font" or type(name) ~= "string" then return end
    local ui = UI()
    if ui and type(ui.GetFontName) == "function" and ui.GetFontName() == name then
        -- Invalidate the cached base even while another provider is selected.
        -- The queued refresh reads the path after Ellesmere invalidates its cache.
        Changed()
        return
    end
    if not Ellesmere.active or name == "general" then return end
    local settings = Ellesmere.GetSettings()
    if not settings.enabled or type(settings.surfaces) ~= "table" then return end
    for _, surface in pairs(settings.surfaces) do
        if type(surface) == "table" and surface.fontKey == name
            and surface.enabled ~= false and surface.fonts ~= false then
            Changed()
            return
        end
    end
end

-- ============================================================
-- Settings search and page registration
-- ============================================================

local function SetSearch(kind, value)
    value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    local search = moduleSearch[kind]
    local key = value:lower()
    if search and search.key == key then
        search.text = value; return
    end
    if not search and value == "" then return end
    local terms = {}
    for word in key:gmatch("%S+") do terms[#terms + 1] = word end
    moduleSearch[kind] = { text = value, key = key, terms = terms, page = modulePages[kind] }
    RefreshOptions(kind)
end

local function MatchesSearch(group, item, search)
    if not search or #search.terms == 0 then return true end
    if not item.searchText then
        item.searchText = table.concat({ group.surfaceLabel or "", group.label or "", group.desc or "",
            item.label or "", item.desc or "" }, " "):lower()
    end
    for _, term in ipairs(search.terms) do
        if not item.searchText:find(term, 1, true) then return false end
    end
    return true
end

local function SyncSearchInput(kind, state)
    local ui = UI()
    local file, flags = ui.GetFontPath(), ui.GetFontOutlineFlag() or ""
    if state.font ~= file or state.flags ~= flags then
        state.input:SetFont(file, 13, flags)
        state.label:SetFont(file, 13, flags)
        state.placeholder:SetFont(file, 11, flags)
        state.font, state.flags = file, flags
    end
    local search = moduleSearch[kind]
    if not state.input:HasFocus() or state.search ~= search then
        state.syncing = true
        state.input:SetText(search and search.text or "")
        state.syncing = false
    end
    state.search = search
end

local function CreateSearchHeader(kind, parent)
    local ui = UI()
    local root = CreateFrame("Frame", nil, parent)
    root:SetHeight(50)
    local input = CreateFrame("EditBox", nil, root)
    input:SetHeight(28)
    input:SetAutoFocus(false)
    input:SetMaxLetters(120)
    input:SetJustifyH("LEFT")
    input:SetTextInsets(10, 10, 0, 0)
    input:SetTextColor(1, 1, 1, 0.9)
    local fill = input:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(input)
    fill:SetColorTexture(0, 0, 0, 0.5)
    ui.MakeRoundedBorder(input, 1, 1, 1, 0.2, fill)
    local label = root:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetText("Search settings")
    label:SetTextColor(1, 1, 1, 0.9)
    label:SetPoint("LEFT", root, "LEFT", 20, 0)
    local placeholder = input:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    placeholder:SetPoint("LEFT", input, "LEFT", 10, 0)
    placeholder:SetText("Search module settings...")
    placeholder:SetTextColor(0.7, 0.7, 0.7, 0.45)
    local clear = CreateFrame("Button", nil, root)
    clear:SetSize(120, 28)
    clear:SetPoint("RIGHT", root, "RIGHT", -20, 0)
    ui.MakeStyledButton(clear, "Clear Search", 13, ui.WB_COLOURS, function()
        input:SetText("")
        input:SetFocus()
    end)
    input:SetPoint("LEFT", label, "RIGHT", 16, 0)
    input:SetPoint("RIGHT", clear, "LEFT", -16, 0)
    local state = { root = root, input = input, label = label, placeholder = placeholder, clear = clear }
    input:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        placeholder:SetShown(text == "")
        if not state.syncing then
            SetSearch(kind, text); state.search = moduleSearch[kind]
        end
    end)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEscapePressed", function(self)
        self:SetText(""); self:ClearFocus()
    end)
    root:SetScript("OnShow", function() SyncSearchInput(kind, state) end)
    root:SetScript("OnHide", function() input:ClearFocus() end)
    return state
end

local function BuildSearchHeader(kind, page, parent, width)
    local ui = UI()
    if ui.IsSearchPrebuild() then return 0 end
    if not searchHeaders[kind] then searchHeaders[kind] = {} end
    local state = searchHeaders[kind][page]
    if not state then
        state = CreateSearchHeader(kind, parent)
        searchHeaders[kind][page] = state
    end
    state.root:SetParent(parent)
    state.root:ClearAllPoints()
    state.root:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    state.root:SetWidth(width or parent:GetWidth())
    state.root:SetFrameLevel(parent:GetFrameLevel() + 1)
    state.root:Show()
    SyncSearchInput(kind, state)
    return 50
end

local function Values(item)
    if item.choices then return item.choices() end
    local values = type(item.values) == "function" and item.values() or item.values or {}
    local order = {}
    for key in pairs(values) do order[#order + 1] = key end
    table.sort(order, function(a, b) return tostring(values[a]) < tostring(values[b]) end)
    return values, order
end

local function OpenAWPSettings()
    UI().CloseConfig()
    NS.OpenOptionsPanel()
end

local function BuildPage(kind, page, parent, offset)
    local ui, start = UI(), offset
    local widgets = ui.Widgets
    -- Hidden global-search prebuild ignores local filters. Ordinary page builds
    -- and local filtering reuse the cached setting metadata.
    local search
    if not ui.IsSearchPrebuild() then
        search = moduleSearch[kind]
        if search and #search.terms > 0 and search.page ~= page then
            -- Native tab/deep-link navigation must show its requested page,
            -- rather than leave a global-search result hidden by our filter.
            SetSearch(kind, "")
            search = nil
        end
        modulePages[kind] = page
    end
    local filtering = search and #search.terms > 0
    local count = 0
    local fontValues, fontOrder
    for _, group in ipairs(OptionGroups()) do
        if OptionCategory(group) == kind and (filtering or page == "All" or page == "Overview" or page == group.tab) then
            local sectionShown = false
            for _, item in ipairs(group.items) do
                if MatchesSearch(group, item, search) then
                    if not sectionShown then
                        local _, height = widgets:SectionHeader(parent,
                            (group.surfaceLabel and group.surfaceLabel .. " — " or "") .. group.label, offset)
                        offset = offset - height
                        sectionShown = true
                    end
                    count = count + 1
                    if item.type == "action" then
                        local _, height = widgets:Button(parent, item.label, offset, item.run)
                        offset = offset - height
                    else
                        local values, order
                        if item.choices == FontChoices then
                            if not fontValues then fontValues, fontOrder = FontChoices() end
                            values, order = fontValues, fontOrder
                        else
                            values, order = Values(item)
                        end
                        local cfg = {
                            type = item.type == "color" and "colorpicker" or item.type,
                            text = item.label,
                            tooltip = item.desc,
                            disabledTooltip = item.desc,
                            disabled = item.disabled,
                            min = item.min,
                            max = item.max,
                            step = item.step,
                            values = values,
                            order = order,
                            noCapture = true,
                            getValue = item.get,
                            setValue = item.set
                        }
                        if item.type == "color" then
                            cfg.getValue = function() return unpack(item.get()) end
                            cfg.setValue = function(r, g, b) item.set({ r, g, b }) end
                        end
                        local row, height = widgets:DualRow(parent, offset, cfg)
                        offset = offset - height
                        -- Hidden search prebuild uses stub widgets and must create no UI.
                        if row and not ui.IsSearchPrebuild() then
                            local region = row._leftRegion
                            if region then region:SetWidth(region:GetWidth() - 24) end
                            local reset = CreateFrame("Button", nil, row)
                            reset:SetSize(20, 20); reset:SetPoint("RIGHT", -4, 0)
                            local icon = reset:CreateTexture(nil, "ARTWORK")
                            icon:SetSize(14, 14); icon:SetPoint("CENTER"); icon:SetAtlas("common-icon-rotateleft", false)
                            icon:SetVertexColor(0.7, 0.7, 0.7, 1)
                            reset:SetScript("OnEnter", function()
                                icon:SetVertexColor(API.Accent())
                                GameTooltip:SetOwner(reset, "ANCHOR_RIGHT"); GameTooltip:SetText("Reset " .. item.label,
                                    1, 1, 1, 1, true); GameTooltip:Show()
                            end)
                            reset:SetScript("OnLeave",
                                function()
                                    icon:SetVertexColor(0.7, 0.7, 0.7, 1); GameTooltip:Hide()
                                end)
                            reset:SetScript("OnClick", function()
                                if not item.disabled or not item.disabled() then item.set(item.default()) end
                            end)
                        end
                    end
                end
            end
        end
    end
    if filtering and count == 0 then
        local _, height = widgets:SectionHeader(parent, "No matching settings. Clear Search to show all settings.",
            offset)
        offset = offset - height
    end
    if kind == "overview" and page == "Overview" and not filtering then
        local _, height = widgets:Button(parent, "Open AWP Settings", offset, OpenAWPSettings)
        offset = offset - height
    end
    return start - offset
end

local function RegisterPlugin(ui)
    if pluginRegistered or type(ui.RegisterPlugin) ~= "function" then return end
    local modules = {}
    for _, kind in ipairs(optionModules) do
        local key = kind
        local pages, seen = { key == "overview" and "Overview" or "All" }, {}
        for _, group in ipairs(OptionGroups()) do
            local category = OptionCategory(group)
            if category == key and group.tab and not seen[group.tab] then
                pages[#pages + 1], seen[group.tab] = group.tab,
                    true
            end
        end
        local titles = {
            overview = "Overview",
            viewers = "Guide Viewers",
            overlay = "World Overlay",
            windows =
            "AWP Windows"
        }
        local headerBuilders = {}
        for _, name in ipairs(pages) do
            local page = name
            headerBuilders[page] = function(parent, width) return BuildSearchHeader(key, page, parent, width) end
        end
        modules[#modules + 1] = {
            key = key,
            title = titles[key],
            pages = pages,
            description =
            "AWP-owned appearance preferences. Search filters all tabs in this module as you type. Guide activity and tracker docking are independent.",
            getHeaderBuilder = function(page) return headerBuilders[page] end,
            buildPage = function(page, parent, offset)
                local height = BuildPage(key, page, parent, offset)
                -- getHeaderBuilder restores cached headers, the initial build
                -- must explicitly install its header through the public API.
                if not ui.IsSearchPrebuild() then ui:SetContentHeader(headerBuilders[page]) end
                return height
            end,
            onPageCacheRestore = function()
                SetSearch(key, ""); ui:RefreshPage()
            end,
            onModuleLeave = function() SetSearch(key, "") end,
            onReset = function()
                for _, group in ipairs(OptionGroups()) do
                    local category = OptionCategory(group)
                    if category == key then for _, item in ipairs(group.items) do item.set(item.default()) end end
                end
            end
        }
    end
    pluginRegistered = ui.RegisterPlugin("AzerothWaypoint", { label = "AzerothWaypoint", modules = modules }) == true
end

local function Initialize()
    local ui = UI()
    if not ui then return end
    RegisterPlugin(ui)
    if registered or type(ui.RegisterSkin) ~= "function" then return end
    registered = true
    ui.RegisterSkin("AzerothWaypoint", function(facade)
        skin = facade
        if type(skin.OnLooksChanged) == "function" then skin.OnLooksChanged(Changed) end
        Changed()
    end)
    local sharedMedia = LibStub and LibStub("LibSharedMedia-3.0", true)
    if sharedMedia and type(sharedMedia.RegisterCallback) == "function" then
        sharedMedia.RegisterCallback(Ellesmere, "LibSharedMedia_Registered", OnSharedFontRegistered)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_LOGIN" or addon == "EllesmereUI" or addon == "EllesmereUIBlizzardSkin" then Initialize() end
end)
