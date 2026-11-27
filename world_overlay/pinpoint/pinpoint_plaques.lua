local NS                   = _G.AzerothWaypointNS
local C                    = NS.Constants
local M                    = NS.Internal.WorldOverlay
local ROOT_PATH            = "Interface\\AddOns\\AzerothWaypoint\\media\\world-overlay\\"
local PLAQUE_PATH          = ROOT_PATH .. "plaques\\"
local FALLBACK_PLAQUE_TYPE = NS.GetDefaultPlaqueType() or "GlowingGems"

-- ============================================================
-- Plaque spec registry
--
-- Image styles define their own nine-slice artwork. Compact renderers share
-- AWP layout metrics, their artwork is independent of those metrics.
-- ============================================================

local COMPACT_LAYOUT       = {
    renderer = "minimal",
    minW = 140,
    wrapW = 196,
    maxW = 224,
    baseH = 32,
    heightRatio = 0,
    textInsetX = 12,
    textPaddingX = 24,
    textInsetTop = 8,
    textInsetBottom = 8,
    contentSized = true,
    contextOverlap = 4,
}

local function CompactStyle(renderer, fields)
    local spec = {}
    for key, value in pairs(COMPACT_LAYOUT) do spec[key] = value end
    spec.renderer = renderer
    for key, value in pairs(fields or {}) do spec[key] = value end
    return spec
end

local PLAQUE_SPECS = {
    Minimal = COMPACT_LAYOUT,
    Forever = CompactStyle("frame", {
        texture = PLAQUE_PATH .. "ForeverPlaque.blp",
        texW = 128,
        texH = 128,
        sourceRect = { 1, 1, 111, 111 },
        borderOnly = true,
        srcCornerL = 24,
        srcCornerR = 24,
        srcCornerT = 24,
        srcCornerB = 24,
        sliceL = 12,
        sliceR = 12,
        sliceT = 12,
        sliceB = 12,
    }),
    Blizzard = CompactStyle("frame", {
        texture = PLAQUE_PATH .. "BlizzardPlaque.blp",
        texW = 128,
        texH = 128,
        sourceRect = { 1, 1, 111, 111 },
        borderOnly = true,
        srcCornerL = 30,
        srcCornerR = 30,
        srcCornerT = 30,
        srcCornerB = 30,
        sliceL = 15,
        sliceR = 15,
        sliceT = 15,
        sliceB = 15,
    }),
    Classic = CompactStyle("classic"),
    Clean = CompactStyle("clean"),
    Modern = CompactStyle("modern", { baseH = 40, textInsetTop = 12, textInsetBottom = 12 }),

    GlowingGems = {
        -- ── Texture ──────────────────────────────────────────────────────
        -- Each plaque owns its own .blp/.png file. The WoW engine resolves
        -- .blp with .png fallback automatically.
        texture     = PLAQUE_PATH .. "GlowingGemsPlaque",
        texW        = 512, -- source atlas width  (px)
        texH        = 256, -- source atlas height (px)

        -- ── Source corner regions (pixels inside the BLP) ─────────────────
        -- How many source pixels belong to each corner region. Pixels between
        -- corners form the stretchable edge and center bands. All four sides
        -- are set independently to support asymmetric artwork (e.g. a thicker
        -- left border or flared bottom edge).
        srcCornerL  = 96, -- from left edge
        srcCornerR  = 96, -- from right edge
        srcCornerT  = 72, -- from top edge
        srcCornerB  = 72, -- from bottom edge

        -- ── Display slice sizes (screen pixels) ───────────────────────────
        -- How large each corner piece renders on screen. Corners use SetSize()
        -- with these values — they are ALWAYS fixed, NEVER stretch. Each side
        -- is independent, a plaque with a thicker bottom just has a larger sliceB.
        sliceL      = 36,
        sliceT      = 28,
        sliceR      = 36,
        sliceB      = 28,

        -- ── Initial panel frame sizing ────────────────────────────────────
        -- Starting dimensions. LayoutPinpointText in frames.lua can resize
        -- the panel dynamically once text content is known.
        minW        = 140, -- minimum width
        baseH       = 72,  -- base height
        maxH        = 96,
        wrapW       = 196,
        maxW        = 224,
        heightRatio = 0.28,
    },

    HordePlaque = {
        texture     = PLAQUE_PATH .. "HordePlaque",
        texW        = 512,
        texH        = 256,

        srcCornerL  = 88,
        srcCornerR  = 88,
        srcCornerT  = 90,
        srcCornerB  = 90,

        sliceL      = 33,
        sliceT      = 35,
        sliceR      = 33,
        sliceB      = 35,

        minW        = 160,
        baseH       = 90,
        maxH        = 110,
        wrapW       = 196,
        maxW        = 224,
        heightRatio = 0.28,
    },

    AlliancePlaque = {
        texture     = PLAQUE_PATH .. "AlliancePlaque",
        texW        = 512,
        texH        = 256,

        srcCornerL  = 112,
        srcCornerR  = 112,
        srcCornerT  = 74,
        srcCornerB  = 74,

        sliceL      = 42,
        sliceT      = 30,
        sliceR      = 42,
        sliceB      = 30,

        minW        = 160,
        baseH       = 80,
        maxH        = 110,
        wrapW       = 196,
        maxW        = 244,
        heightRatio = 0.28,
    },

    Fantasy = {
        texture     = PLAQUE_PATH .. "FantasyPlaque",
        texW        = 512,
        texH        = 256,

        srcCornerL  = 80,
        srcCornerR  = 80,
        srcCornerT  = 60,
        srcCornerB  = 60,

        sliceL      = 30,
        sliceT      = 24,
        sliceR      = 30,
        sliceB      = 24,

        minW        = 100,
        baseH       = 62,
        maxH        = 96,
        wrapW       = 196,
        maxW        = 224,
        heightRatio = 0.28,
    },

    [C.WORLD_OVERLAY_PLAQUE_FUTURE] = {
        texture     = PLAQUE_PATH .. "FuturePlaque",
        texW        = 512,
        texH        = 256,

        srcCornerL  = 80,
        srcCornerR  = 80,
        srcCornerT  = 56,
        srcCornerB  = 56,

        sliceL      = 30,
        sliceT      = 21,
        sliceR      = 30,
        sliceB      = 21,

        minW        = 100,
        baseH       = 68,
        maxH        = 96,
        wrapW       = 196,
        maxW        = 224,
        heightRatio = 0.28,
    },

    SteamPunkPlaque = {
        texture      = PLAQUE_PATH .. "SteamPunkPlaque",
        texW         = 512,
        texH         = 256,

        srcCornerL   = 112,
        srcCornerR   = 112,
        srcCornerT   = 88,
        srcCornerB   = 88,

        sliceL       = 42,
        sliceT       = 34,
        sliceR       = 42,
        sliceB       = 34,

        minW         = 100,
        baseH        = 86,
        maxH         = 112,
        wrapW        = 196,
        maxW         = 234, -- slightly more than some due to bulky sides
        heightRatio  = 0.28,

        -- SteamPunk has visually heavier side assemblies than the other plaques,
        -- so its text host needs a larger horizontal inset than the global default.
        textInsetX   = 20, -- default is 16
        textPaddingX = 28, -- kept default here
    },
}

for name, defaults in pairs(C.PLAQUE_APPEARANCE_DEFAULTS) do
    for key, value in pairs(defaults) do PLAQUE_SPECS[name][key] = value end
end

-- ============================================================
-- Internal helpers (module-local, not exported)
-- ============================================================

local function ConfigurePinpointTextureSampling(texture)
    if not texture then
        return
    end

    texture:SetTexelSnappingBias(0)
    texture:SetSnapToPixelGrid(false)
end

local function SetCompositeVertexColor(self, r, g, b, a)
    local textures = self and self.__awpTextures or nil
    if type(textures) ~= "table" then
        return
    end

    for _, texture in ipairs(textures) do
        texture:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    end
end

-- Creates a single texture from an atlas, normalizing UVs against the
-- caller-supplied texW/texH so each plaque's own BLP dimensions are used.
local function CreateAtlasTexture(parent, texW, texH, atlasTexture, drawLayer, blendMode, srcL, srcR, srcT, srcB)
    local texture = parent:CreateTexture(nil, drawLayer)
    texture:SetTexture(atlasTexture)
    texture:SetTexCoord(
        srcL / texW,
        srcR / texW,
        srcT / texH,
        srcB / texH
    )
    ConfigurePinpointTextureSampling(texture)
    if blendMode then
        texture:SetBlendMode(blendMode)
    end
    return texture
end

-- Shared nine-slice geometry. New frame artwork may crop an exported sheet;
-- older artwork keeps its original full-sheet bounds and fixed corner sizes.
local function ConfigureComposite(layer, spec, width, height)
    if width <= 0 or height <= 0 then return end
    if layer._spec == spec and layer._width == width and layer._height == height then return end
    if layer._spec ~= spec then
        for _, texture in ipairs(layer.__awpTextures) do
            texture:SetTexture(spec.texture)
            ConfigurePinpointTextureSampling(texture)
        end
    end
    layer._spec, layer._width, layer._height = spec, width, height
    local crop = spec.sourceRect
    local x0, y0 = crop and crop[1] or 0, crop and crop[2] or 0
    local x1, y1 = crop and crop[3] or spec.texW, crop and crop[4] or spec.texH
    local l, r, t, b = spec.sliceL, spec.sliceR, spec.sliceT, spec.sliceB
    if crop then
        l, r = math.min(l, width / 2), math.min(r, width / 2)
        t, b = math.min(t, height / 2), math.min(b, height / 2)
    end
    local sl, sr = x0 + spec.srcCornerL * l / spec.sliceL, x1 - spec.srcCornerR * r / spec.sliceR
    local st, sb = y0 + spec.srcCornerT * t / spec.sliceT, y1 - spec.srcCornerB * b / spec.sliceB
    local function uv(texture, left, right, top, bottom)
        texture:SetTexCoord(left / spec.texW, right / spec.texW, top / spec.texH, bottom / spec.texH)
    end
    uv(layer.TopLeft, x0, sl, y0, st); layer.TopLeft:SetSize(l, t)
    uv(layer.TopRight, sr, x1, y0, st); layer.TopRight:SetSize(r, t)
    uv(layer.BottomLeft, x0, sl, sb, y1); layer.BottomLeft:SetSize(l, b)
    uv(layer.BottomRight, sr, x1, sb, y1); layer.BottomRight:SetSize(r, b)
    if not layer.Top then return end
    uv(layer.Top, sl, sr, y0, st)
    layer.Top:SetPoint("TOPLEFT", layer, "TOPLEFT", l, 0)
    layer.Top:SetPoint("TOPRIGHT", layer, "TOPRIGHT", -r, 0); layer.Top:SetHeight(t)
    uv(layer.Bottom, sl, sr, sb, y1)
    layer.Bottom:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", l, 0)
    layer.Bottom:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", -r, 0); layer.Bottom:SetHeight(b)
    uv(layer.Left, x0, sl, st, sb)
    layer.Left:SetPoint("TOPLEFT", layer, "TOPLEFT", 0, -t)
    layer.Left:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 0, b); layer.Left:SetWidth(l)
    uv(layer.Right, sr, x1, st, sb)
    layer.Right:SetPoint("TOPRIGHT", layer, "TOPRIGHT", 0, -t)
    layer.Right:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", 0, b); layer.Right:SetWidth(r)
    if crop then
        layer.Top:SetShown(width > l + r); layer.Bottom:SetShown(width > l + r)
        layer.Left:SetShown(height > t + b); layer.Right:SetShown(height > t + b)
    end
    if layer.Center then
        uv(layer.Center, sl, sr, st, sb)
        layer.Center:SetPoint("TOPLEFT", layer, "TOPLEFT", l, -t)
        layer.Center:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", -r, b)
    end
end

local function CreateCompositeLayer(parent, spec, drawLayer, blendMode, cornersOnly)
    local layer = CreateFrame("Frame", nil, parent)
    layer.__awpTextures = {}
    layer.SetVertexColor = SetCompositeVertexColor
    local function add(name, point)
        local texture = CreateAtlasTexture(layer, spec.texW, spec.texH, spec.texture, drawLayer, blendMode, 0, 1, 0, 1)
        layer[name] = texture
        layer.__awpTextures[#layer.__awpTextures + 1] = texture
        if point then texture:SetPoint(point) end
    end
    add("TopLeft", "TOPLEFT"); add("TopRight", "TOPRIGHT")
    add("BottomLeft", "BOTTOMLEFT"); add("BottomRight", "BOTTOMRIGHT")
    if not cornersOnly then
        add("Top"); add("Bottom"); add("Left"); add("Right")
        if not spec.borderOnly then add("Center") end
    end
    ConfigureComposite(layer, spec, spec.minW, spec.baseH)
    if spec.sourceRect then
        layer:SetScript("OnSizeChanged", function(self, w, h) ConfigureComposite(self, spec, w, h) end)
    end
    return layer
end

-- A renderer owns its alpha partitions. Text and the semantic marker are
-- separate frames, overall pinpoint fading still applies to their common host.
local function SetLayerTint(self, r, g, b, a)
    if self._r == r and self._g == g and self._b == b and self._a == a and not self._appearanceDirty then return end
    self._r, self._g, self._b, self._a = r, g, b, a
    self._appearanceDirty = nil
    for _, part in ipairs(self.parts) do
        local c = part.color
        local alpha = c[4]
        if part.role == "background" then
            alpha = self._backgroundOpacity or alpha
        elseif part.role == "border" then
            alpha = self._borderOpacity or alpha
        else
            -- Shadows and bevel highlights keep their authored relative strength.
            alpha = alpha * (self._borderOpacity or 1)
        end
        part.texture:SetVertexColor(c[1] * r, c[2] * g, c[3] * b, alpha * a)
    end
    if self.low then
        local alpha = (self._backgroundOpacity or self.defaultBackgroundOpacity) * a
        self.low:SetRGBA(0.025 * r, 0.028 * g, 0.033 * b, alpha)
        self.high:SetRGBA(0.065 * r, 0.067 * g, 0.073 * b, alpha)
        self.fill:SetGradient("VERTICAL", self.low, self.high)
    end
    if self.border then self.border:SetVertexColor(r, g, b, (self._borderOpacity or 1) * a) end
    if self.stockBorder then self:SetBackdropBorderColor(r, g, b, (self._borderOpacity or 1) * a) end
end

local function SetLayerAppearance(self, appearance)
    local bg = appearance.backgroundOpacity / 100
    local rim = appearance.borderOpacity / 100
    local width = appearance.borderThickness or self.defaultThickness
    if self._backgroundOpacity == bg and self._borderOpacity == rim and self._thickness == width then return end
    self._backgroundOpacity, self._borderOpacity = bg, rim
    if self.ConfigureThickness and self._thickness ~= width then self:ConfigureThickness(width) end
    self._thickness = width
    self._appearanceDirty = true
    self:SetVertexColor(self._r or 1, self._g or 1, self._b or 1, self._a or 1)
end

local function SetRectangleInsets(texture, left, top, right, bottom)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", texture:GetParent(), "TOPLEFT", left, -top)
    texture:SetPoint("BOTTOMRIGHT", texture:GetParent(), "BOTTOMRIGHT", -right, bottom)
end

local function SetRingInsets(ring, outer, inner)
    ring.top:SetHeight(inner - outer)
    ring.top:ClearAllPoints()
    ring.top:SetPoint("TOPLEFT", ring.top:GetParent(), "TOPLEFT", outer, -outer)
    ring.top:SetPoint("TOPRIGHT", ring.top:GetParent(), "TOPRIGHT", -outer, -outer)
    ring.bottom:ClearAllPoints()
    ring.bottom:SetPoint("BOTTOMLEFT", ring.bottom:GetParent(), "BOTTOMLEFT", outer, outer)
    ring.bottom:SetPoint("BOTTOMRIGHT", ring.bottom:GetParent(), "BOTTOMRIGHT", -outer, outer)
    ring.bottom:SetHeight(inner - outer)
    ring.left:ClearAllPoints()
    ring.left:SetPoint("TOPLEFT", ring.left:GetParent(), "TOPLEFT", outer, -inner)
    ring.left:SetPoint("BOTTOMLEFT", ring.left:GetParent(), "BOTTOMLEFT", outer, inner)
    ring.left:SetWidth(inner - outer)
    ring.right:ClearAllPoints()
    ring.right:SetPoint("TOPRIGHT", ring.right:GetParent(), "TOPRIGHT", -outer, -inner)
    ring.right:SetPoint("BOTTOMRIGHT", ring.right:GetParent(), "BOTTOMRIGHT", -outer, inner)
    ring.right:SetWidth(inner - outer)
end

-- Minimal uses hollow rectangular rings, so transparent fill never reveals
-- an opaque keyline, border or shadow underneath the middle of the plaque.
local function CreateMinimalLayer(parent)
    local layer = CreateFrame("Frame", nil, parent)
    layer:SetAllPoints(parent)
    layer:EnableMouse(false)
    layer.parts = {}
    layer.SetVertexColor, layer.SetAppearance = SetLayerTint, SetLayerAppearance
    layer.defaultThickness = COMPACT_LAYOUT.borderThickness
    layer.defaultBackgroundOpacity = COMPACT_LAYOUT.backgroundOpacity / 100
    local function ring(outer, inner, color, role, sublevel)
        local result = {}
        for _, side in ipairs({ "top", "bottom", "left", "right" }) do
            local texture = layer:CreateTexture(nil, "BACKGROUND", nil, sublevel)
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            layer.parts[#layer.parts + 1] = { texture = texture, color = color, role = role }
            result[side] = texture
        end
        SetRingInsets(result, outer, inner)
        return result
    end
    for i = 4, 1, -1 do ring(-i, 0, { 0, 0, 0, 0.035 }, "decoration", -8) end
    ring(0, 1, { 0.008, 0.01, 0.012, 1 }, "border", -7)
    layer.rim = ring(1, 2, { 0.30, 0.27, 0.19, COMPACT_LAYOUT.borderOpacity / 100 }, "border", -6)
    layer.fill = layer:CreateTexture(nil, "BACKGROUND", nil, -5)
    layer.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    layer.low, layer.high = CreateColor(0, 0, 0), CreateColor(0, 0, 0)
    function layer:ConfigureThickness(width)
        SetRingInsets(self.rim, 1, width + 1)
        SetRectangleInsets(self.fill, width + 1, width + 1, width + 1, width + 1)
    end

    layer:SetAppearance(C.PLAQUE_APPEARANCE_DEFAULTS.Minimal)
    return layer
end

local function ShapeMask(parent, texture, name, margin)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(PLAQUE_PATH .. "plaque-" .. name .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetTextureSliceMargins(margin or 12, margin or 12, margin or 12, margin or 12)
    mask:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    return mask
end

-- Only the new standalone styles use these primitives. Shapes and their tint
-- coefficients are allocated once, and all resize work belongs to the engine's
-- sliced masks or the cropped image layer's OnSizeChanged callback.
---@class AWPStandalonePlaqueTexture : Texture
---@field _shapeMask MaskTexture
local function CreateStyledLayer(parent, spec, name)
    local layer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    layer:SetAllPoints(parent)
    layer:EnableMouse(false)
    layer.parts = {}
    layer.SetVertexColor, layer.SetAppearance = SetLayerTint, SetLayerAppearance
    local function shape(inset, color, mask, sublevel, margin, role)
        local texture = layer:CreateTexture(nil, "BACKGROUND", nil, sublevel or -5)
        ---@cast texture AWPStandalonePlaqueTexture
        texture:SetTexture("Interface\\Buttons\\WHITE8X8")
        texture:SetPoint("TOPLEFT", layer, "TOPLEFT", inset, -inset)
        texture:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", -inset, inset)
        layer.parts[#layer.parts + 1] = { texture = texture, color = color, role = role or "border" }
        if mask then texture._shapeMask = ShapeMask(layer, texture, mask, margin) end
        return texture
    end
    if spec.renderer == "frame" then
        layer.fill = shape(5.5, { 0.078, 0.078, 0.09, spec.backgroundOpacity / 100 }, "chamfer-fill", nil, nil,
            "background")
        layer.border = CreateCompositeLayer(layer, spec, "ARTWORK", nil, false)
        layer.border:SetFrameLevel(layer:GetFrameLevel())
        layer.border:SetAllPoints(layer)
        -- A hollow mask removes the embedded game-center alpha, including the
        -- inner portions of the corner slices, it preserves the original rim.
        local ring = layer:CreateMaskTexture()
        ring:SetTexture(PLAQUE_PATH .. "plaque-chamfer-ring.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ring:SetTextureSliceMargins(12, 12, 12, 12)
        ring:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        ring:SetAllPoints(layer)
        for _, texture in ipairs(layer.border.__awpTextures) do texture:AddMaskTexture(ring) end
        layer.ringMask = ring
    elseif spec.renderer == "classic" then
        layer:SetBackdrop({
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 16,
            tileEdge = true,
            insets = { left = 5.5, right = 6, top = 6, bottom = 5.5 }
        })
        layer.fill = layer:CreateTexture(nil, "BACKGROUND")
        layer.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
        layer.fill:SetPoint("TOPLEFT", layer, "TOPLEFT", 5.5, -6)
        layer.fill:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", -6, 5.5)
        layer.parts[#layer.parts + 1] = {
            texture = layer.fill,
            color = { 0.078, 0.078, 0.09, spec.backgroundOpacity / 100 },
            role =
            "background"
        }
        layer.stockBorder = true
    elseif spec.renderer == "clean" or spec.renderer == "modern" then
        local modern = spec.renderer == "modern"
        layer.defaultThickness = spec.borderThickness
        local prefix = modern and "modern" or "clean"
        if modern then
            layer.shadow = shape(-4, { 0, 0, 0, 0.35 }, "shadow", -8, 16, "decoration")
            layer.outline = shape(0, { 0.024, 0.024, 0.027, 1 }, "outline-6", -7)
        end
        layer.band = shape(0, modern and { 0.10, 0.09, 0.065, spec.borderOpacity / 100 } or
            { 1, 1, 1, spec.borderOpacity / 100 }, prefix .. "-rim-" .. layer.defaultThickness, -6)
        if modern then layer.innerLine = shape(0, { 0.024, 0.024, 0.027, 1 }, "modern-inner-8", -5) end
        layer.fill = shape(0,
            modern and { 0.078, 0.078, 0.09, spec.backgroundOpacity / 100 } or
            { 0.08, 0.08, 0.08, spec.backgroundOpacity / 100 },
            prefix .. "-fill-" .. layer.defaultThickness, -5, nil, "background")
        if modern then
            local function bevel(color)
                local texture = layer:CreateTexture(nil, "ARTWORK")
                texture:SetTexture("Interface\\Buttons\\WHITE8X8")
                texture:SetHeight(1)
                layer.parts[#layer.parts + 1] = { texture = texture, color = color, role = "decoration" }
                return texture
            end
            layer.bevelTop = bevel({ 1, 1, 1, 0.06 })
            layer.bevelBottom = bevel({ 0, 0, 0, 0.35 })
        end
        function layer:ConfigureThickness(width)
            local function mask(texture, name)
                texture._shapeMask:SetTexture(PLAQUE_PATH .. "plaque-" .. name .. ".tga",
                    "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            end
            mask(self.band, prefix .. "-rim-" .. width)
            mask(self.fill, prefix .. "-fill-" .. width)
            if modern then
                self.outline:SetShown(width >= 3)
                self.innerLine:SetShown(width >= 3)
                if width >= 3 then mask(self.innerLine, "modern-inner-" .. width) end
                self.bevelTop:ClearAllPoints()
                self.bevelTop:SetPoint("TOPLEFT", self, "TOPLEFT", width, -width)
                self.bevelTop:SetPoint("TOPRIGHT", self, "TOPRIGHT", -width, -width)
                self.bevelBottom:ClearAllPoints()
                self.bevelBottom:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", width, width)
                self.bevelBottom:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -width, width)
            end
        end
    end
    layer:SetAppearance(C.PLAQUE_APPEARANCE_DEFAULTS[name])
    return layer
end

local function SetPanelVertexColor(panel, r, g, b, a)
    r, g, b, a = r or 1, g or 1, b or 1, a or 1
    if panel._tintR == r and panel._tintG == g and panel._tintB == b and panel._tintA == a then return end
    panel._tintR, panel._tintG, panel._tintB, panel._tintA = r, g, b, a
    panel._renderer:SetVertexColor(r, g, b, a)
end

local function UpdateAtlasLayer(panel, spec)
    ConfigureComposite(panel, spec, spec.minW, spec.baseH)
    panel:SetSize(spec.minW, spec.baseH)
end

local function UpdatePanel(panel, plaqueType)
    if not panel then return end
    local name = PLAQUE_SPECS[plaqueType] and plaqueType or FALLBACK_PLAQUE_TYPE
    local spec = PLAQUE_SPECS[name] or PLAQUE_SPECS[FALLBACK_PLAQUE_TYPE]
    local renderer
    if spec.renderer == "minimal" then
        if not panel._minimal then panel._minimal = CreateMinimalLayer(panel) end
        renderer = panel._minimal
    elseif spec.renderer then
        if not panel._styles then panel._styles = {} end
        if not panel._styles[name] then panel._styles[name] = CreateStyledLayer(panel, spec, name) end
        renderer = panel._styles[name]
    else
        if not panel._atlas then
            panel._atlas = CreateCompositeLayer(panel, spec, "BACKGROUND", nil, false)
            panel._atlas:SetAllPoints(panel)
        elseif panel.__awpPlaqueType ~= name then
            UpdateAtlasLayer(panel._atlas, spec)
        end
        renderer = panel._atlas
    end
    if panel._renderer and panel._renderer ~= renderer then panel._renderer:Hide() end
    renderer:Show()
    panel._renderer = renderer
    panel.__awpPlaqueType, panel.__awpPlaqueSpec = name, spec
    panel:SetSize(spec.minW, spec.baseH)
    if renderer.SetAppearance then
        local appearance = NS.GetPlaqueAppearance(name)
        renderer:SetAppearance(appearance)
        panel._backgroundOpacity, panel._borderOpacity, panel._borderThickness =
            appearance.backgroundOpacity, appearance.borderOpacity, appearance.borderThickness
    end
    -- Newly selected artwork inherits the active tint even when it is unchanged.
    renderer:SetVertexColor(panel._tintR or 1, panel._tintG or 1, panel._tintB or 1, panel._tintA or 1)
end

M.Plaques = {
    CreateAtlasTexture = CreateAtlasTexture,
    SetCompositeVertexColor = SetCompositeVertexColor,
    ConfigurePinpointTextureSampling = ConfigurePinpointTextureSampling,
    CreatePanel = function(parent, plaqueType)
        local panel = CreateFrame("Frame", nil, parent)
        panel.SetVertexColor = SetPanelVertexColor
        UpdatePanel(panel, plaqueType)
        return panel
    end,
    UpdatePanel = UpdatePanel,
    ApplyAppearance = function(panel, appearance)
        local background, border, thickness = appearance.backgroundOpacity, appearance.borderOpacity,
            appearance.borderThickness
        if panel._backgroundOpacity == background and panel._borderOpacity == border and panel._borderThickness == thickness then return end
        panel._backgroundOpacity, panel._borderOpacity, panel._borderThickness = background, border, thickness
        if panel._renderer.SetAppearance then panel._renderer:SetAppearance(appearance) end
    end,
    GetAppearanceSupport = function(plaqueType)
        local defaults = C.PLAQUE_APPEARANCE_DEFAULTS[plaqueType]
        return defaults ~= nil, defaults ~= nil and defaults.borderThickness ~= nil
    end,
    GetAppearanceDefaults = function(plaqueType)
        local defaults = C.PLAQUE_APPEARANCE_DEFAULTS[plaqueType]
        return defaults and defaults.backgroundOpacity or 85, defaults and defaults.borderOpacity or 100,
            defaults and defaults.borderThickness or 1
    end,
    GetSpec = function(plaqueType)
        return PLAQUE_SPECS[plaqueType] or PLAQUE_SPECS[FALLBACK_PLAQUE_TYPE]
    end,
}

function M.Plaques.ShowSample(parent, panel, plaqueType, useDefaults)
    if not panel then
        panel = M.Plaques.CreatePanel(parent, plaqueType)
        panel:SetPoint("CENTER", parent, "CENTER")
        local textHost = CreateFrame("Frame", nil, panel)
        textHost:SetAllPoints()
        textHost:SetFrameLevel(panel:GetFrameLevel() + 3)
        local title = textHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("BOTTOM", textHost, "CENTER", 0, 1)
        title:SetText("Your destination")
        local context = textHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        context:SetPoint("TOP", textHost, "CENTER", 0, -1)
        context:SetText("Travel and quest instructions")
    elseif panel.__awpPlaqueType ~= plaqueType then
        UpdatePanel(panel, plaqueType)
    end
    plaqueType = panel.__awpPlaqueType
    panel:SetSize(224, math.max(52, panel.__awpPlaqueSpec.baseH))
    M.PlaqueAnimations.ShowSampleEffects(panel, plaqueType, useDefaults)
    local appearance
    if useDefaults then
        appearance = C.PLAQUE_APPEARANCE_DEFAULTS[plaqueType]
    else
        appearance = NS.GetPlaqueAppearance(plaqueType)
    end
    if appearance then M.Plaques.ApplyAppearance(panel, appearance) end
    panel:Show()
    return panel
end

-- Layout is independent of artwork. Resolve these once, not while measuring
-- each frame, and share the same specification between creation and rendering.
local layoutSpecs = {}
local thicknessLayouts = {}
local cfg = M.Config
for name, spec in pairs(PLAQUE_SPECS) do
    layoutSpecs[name] = {
        minW = spec.minW,
        wrapW = spec.wrapW,
        maxW = spec.maxW,
        baseH = spec.baseH,
        maxH = spec.maxH,
        heightRatio = spec.heightRatio,
        textInsetX = spec.textInsetX or cfg.PINPOINT_TEXT_INSET_X,
        textPaddingX = spec.textPaddingX or cfg.PINPOINT_PANEL_TEXT_PADDING_X,
        textInsetTop = spec.textInsetTop or cfg.PINPOINT_TEXT_INSET_TOP,
        textInsetBottom = spec.textInsetBottom or cfg.PINPOINT_TEXT_INSET_BOTTOM,
        contextOverlap = spec.contextOverlap or (cfg.PINPOINT_CONTEXT_SIZE * 0.5 + cfg.PINPOINT_CONTEXT_OFFSET_Y),
        contentSized = spec.contentSized,
    }
    if spec.renderer == "minimal" or spec.renderer == "clean" or spec.renderer == "modern" then
        thicknessLayouts[name] = {}
        for width = 1, 8 do
            local layout = {}
            for key, value in pairs(layoutSpecs[name]) do layout[key] = value end
            local inset = width + (spec.renderer == "minimal" and 1 or 0) + 4
            layout.textInsetX = math.max(layout.textInsetX, inset)
            layout.textPaddingX = layout.textInsetX * 2
            layout.textInsetTop = math.max(layout.textInsetTop, inset)
            layout.textInsetBottom = math.max(layout.textInsetBottom, inset)
            thicknessLayouts[name][width] = layout
        end
    end
end
local themedLayout = COMPACT_LAYOUT

function M.Plaques.GetLayoutSpec(frame)
    if frame and frame.__awpThemedPlaque then return themedLayout end
    local name = frame and frame.__awpPlaqueType or FALLBACK_PLAQUE_TYPE
    local width = frame and frame.Panel and frame.Panel._borderThickness or 0
    if thicknessLayouts[name] and thicknessLayouts[name][width] then return thicknessLayouts[name][width] end
    return layoutSpecs[name] or layoutSpecs[FALLBACK_PLAQUE_TYPE] or layoutSpecs.GlowingGems
end
