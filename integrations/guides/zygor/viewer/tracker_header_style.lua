local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

NS.Internal = NS.Internal or {}
NS.Internal.ZygorTrackerViewer = NS.Internal.ZygorTrackerViewer or {}

local Shared = NS.Internal.ZygorTrackerViewer
local Host = Shared.TrackerHost
local Style = {}
Shared.TrackerHeaderStyle = Style

-- Kaliel's Tracker deliberately removes its private addon object from
-- AceAddon's registry.  Its already-styled native header regions are the
-- supported integration surface here: read their resolved scalar values and
-- apply those values to AWP-owned regions.  Never retain or reparent a KT
-- texture/font region and never write to KT's profile or native frames.
local baselines = setmetatable({}, { __mode = "k" })
local hookedRegions = setmetatable({}, { __mode = "k" })
local sourceRefreshPending

local KT_MODULE_CANDIDATES = {
    "KT_QuestObjectiveTracker",
    "KT_CampaignQuestObjectiveTracker",
    "KT_WorldQuestObjectiveTracker",
    "KT_BonusObjectiveTracker",
    "KT_AchievementObjectiveTracker",
    "KT_ScenarioObjectiveTracker",
    "KT_AdventureObjectiveTracker",
    "KT_MonthlyActivitiesObjectiveTracker",
    "KT_InitiativeTasksObjectiveTracker",
    "KT_ProfessionsRecipeTracker",
    "KT_UIWidgetObjectiveTracker",
}

local function CopyValues(...)
    return { n = select("#", ...), ... }
end

local function IsNumber(value)
    return type(value) == "number"
end

local function ReadVertexColor(region)
    if not region or type(region.GetVertexColor) ~= "function" then return nil end
    local ok, r, g, b, a = pcall(region.GetVertexColor, region)
    if not ok or not IsNumber(r) or not IsNumber(g) or not IsNumber(b) then return nil end
    return { r = r, g = g, b = b, a = IsNumber(a) and a or 1 }
end

local function ApplyVertexColor(region, color, preserveAlpha)
    if not region or type(region.SetVertexColor) ~= "function" or type(color) ~= "table" then
        return false
    end
    local alpha = IsNumber(color.a) and color.a or 1
    if preserveAlpha and type(region.GetVertexColor) == "function" then
        local ok, _, _, _, currentAlpha = pcall(region.GetVertexColor, region)
        if ok and IsNumber(currentAlpha) then alpha = currentAlpha end
    end
    return pcall(region.SetVertexColor, region, color.r, color.g, color.b, alpha)
end

local function ReadTextColor(fontString)
    if not fontString or type(fontString.GetTextColor) ~= "function" then return nil end
    local ok, r, g, b, a = pcall(fontString.GetTextColor, fontString)
    if not ok or not IsNumber(r) or not IsNumber(g) or not IsNumber(b) then return nil end
    return { r = r, g = g, b = b, a = IsNumber(a) and a or 1 }
end

local function ApplyTextColor(fontString, color)
    if not fontString or type(fontString.SetTextColor) ~= "function" or type(color) ~= "table" then
        return false
    end
    return pcall(fontString.SetTextColor, fontString,
        color.r, color.g, color.b, IsNumber(color.a) and color.a or 1)
end

local function CapturePoints(region)
    if not region or type(region.GetNumPoints) ~= "function" or type(region.GetPoint) ~= "function" then
        return nil
    end
    local okCount, count = pcall(region.GetNumPoints, region)
    if not okCount or not IsNumber(count) then return nil end
    local points = {}
    for index = 1, count do
        local okPoint, point, relativeTo, relativePoint, x, y = pcall(region.GetPoint, region, index)
        if okPoint and point then
            points[#points + 1] = { point, relativeTo, relativePoint, x, y }
        end
    end
    return points
end

local function RestorePoints(region, points)
    if not region or type(points) ~= "table" or type(region.ClearAllPoints) ~= "function"
        or type(region.SetPoint) ~= "function"
    then
        return
    end
    pcall(region.ClearAllPoints, region)
    for index = 1, #points do
        local point = points[index]
        pcall(region.SetPoint, region, point[1], point[2], point[3], point[4], point[5])
    end
end

local function CaptureBackgroundTexture(texture)
    if not texture then return nil end
    local snapshot = { points = CapturePoints(texture) }
    if type(texture.IsShown) == "function" then
        local ok, shown = pcall(texture.IsShown, texture)
        if ok then snapshot.shown = not not shown end
    end
    if snapshot.shown == nil then snapshot.shown = true end
    if type(texture.GetWidth) == "function" then
        local ok, width = pcall(texture.GetWidth, texture)
        if ok and IsNumber(width) then snapshot.width = width end
    end
    if type(texture.GetHeight) == "function" then
        local ok, height = pcall(texture.GetHeight, texture)
        if ok and IsNumber(height) then snapshot.height = height end
    end
    if type(texture.GetAtlas) == "function" then
        local ok, atlas = pcall(texture.GetAtlas, texture)
        if ok then snapshot.atlas = atlas end
    end
    if type(texture.GetTexture) == "function" then
        local ok, value = pcall(texture.GetTexture, texture)
        if ok then snapshot.texture = value end
    end
    if type(texture.GetTexCoord) == "function" then
        local ok, a, b, c, d, e, f, g, h = pcall(texture.GetTexCoord, texture)
        if ok then snapshot.texCoord = CopyValues(a, b, c, d, e, f, g, h) end
    end
    return snapshot
end

local function SetShown(region, shown)
    if shown then
        if type(region.Show) == "function" then pcall(region.Show, region) end
    elseif type(region.Hide) == "function" then
        pcall(region.Hide, region)
    end
end

local function RestoreBackgroundTexture(texture, snapshot)
    if not texture or type(snapshot) ~= "table" then return end
    if snapshot.atlas and type(texture.SetAtlas) == "function" then
        pcall(texture.SetAtlas, texture, snapshot.atlas, false)
    elseif type(texture.SetTexture) == "function" then
        pcall(texture.SetTexture, texture, snapshot.texture)
    end
    if snapshot.texCoord and type(texture.SetTexCoord) == "function" then
        pcall(texture.SetTexCoord, texture, unpack(snapshot.texCoord, 1, snapshot.texCoord.n))
    end
    if IsNumber(snapshot.width) and IsNumber(snapshot.height) and type(texture.SetSize) == "function" then
        pcall(texture.SetSize, texture, snapshot.width, snapshot.height)
    end
    RestorePoints(texture, snapshot.points)
    SetShown(texture, snapshot.shown)
end

local function CaptureFont(fontString)
    if not fontString or type(fontString.GetFont) ~= "function" then return nil end
    local ok, file, size, flags = pcall(fontString.GetFont, fontString)
    if not ok or not file or not IsNumber(size) then return nil end
    local snapshot = { file = file, size = size, flags = flags }
    if type(fontString.GetShadowColor) == "function" then
        local okShadow, r, g, b, a = pcall(fontString.GetShadowColor, fontString)
        if okShadow and IsNumber(r) and IsNumber(g) and IsNumber(b) then
            snapshot.shadowColor = { r, g, b, IsNumber(a) and a or 1 }
        end
    end
    if type(fontString.GetShadowOffset) == "function" then
        local okOffset, x, y = pcall(fontString.GetShadowOffset, fontString)
        if okOffset and IsNumber(x) and IsNumber(y) then snapshot.shadowOffset = { x, y } end
    end
    return snapshot
end

local function ApplyFontSnapshot(fontString, snapshot)
    if not fontString or type(snapshot) ~= "table" or type(fontString.SetFont) ~= "function" then
        return false
    end
    local ok = pcall(fontString.SetFont, fontString, snapshot.file, snapshot.size, snapshot.flags)
    if not ok then return false end
    if snapshot.shadowColor and type(fontString.SetShadowColor) == "function" then
        pcall(fontString.SetShadowColor, fontString, unpack(snapshot.shadowColor))
    end
    if snapshot.shadowOffset and type(fontString.SetShadowOffset) == "function" then
        pcall(fontString.SetShadowOffset, fontString, unpack(snapshot.shadowOffset))
    end
    return true
end

local function CollectButtonTextures(module)
    local controls = module and module._awpControls
    if type(controls) ~= "table" then return {} end
    local textures, seen = {}, {}
    local getters = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }
    for _, key in ipairs({ "settingsBtn", "guideBtn", "nextBtn", "prevBtn" }) do
        local button = controls[key]
        if button then
            for index = 1, #getters do
                local getter = button[getters[index]]
                if type(getter) == "function" then
                    local ok, texture = pcall(getter, button)
                    if ok and texture and not seen[texture] then
                        seen[texture] = true
                        textures[#textures + 1] = texture
                    end
                end
            end
        end
    end
    return textures
end

function Style.CaptureBaseline(module)
    if not module or baselines[module] then return baselines[module] end
    local header = module.Header
    if not header then return nil end
    local title = header.Text or header.HeaderText
    local buttonTextures = CollectButtonTextures(module)
    local buttonColors = {}
    for index = 1, #buttonTextures do
        buttonColors[buttonTextures[index]] = ReadVertexColor(buttonTextures[index])
    end
    local baseline = {
        header = header,
        title = title,
        icon = header.Icon,
        background = header.Background,
        texture = CaptureBackgroundTexture(header.Background),
        backgroundColor = ReadVertexColor(header.Background),
        font = CaptureFont(title),
        titleColor = ReadTextColor(title),
        iconColor = ReadVertexColor(header.Icon),
        buttonTextures = buttonTextures,
        buttonColors = buttonColors,
        applied = {},
    }
    baselines[module] = baseline
    return baseline
end

local function IsUsableSourceHeader(header, targetHeader)
    return header and header ~= targetHeader and header.Background
        and (header.Text or header.HeaderText)
end

local function FindKTSourceHeader(module)
    local targetHeader = module and module.Header
    local container = rawget(_G, "KT_ObjectiveTrackerFrame")
    local modules = container and container.modules
    if type(modules) == "table" then
        for index = 1, #modules do
            local candidate = modules[index]
            local header = candidate and candidate ~= module and candidate.Header or nil
            if IsUsableSourceHeader(header, targetHeader) then return header end
        end
    end
    for index = 1, #KT_MODULE_CANDIDATES do
        local candidate = rawget(_G, KT_MODULE_CANDIDATES[index])
        local header = candidate and candidate ~= module and candidate.Header or nil
        if IsUsableSourceHeader(header, targetHeader) then return header end
    end
    return nil
end

local function FindKTButtonTexture()
    local frame = rawget(_G, "!KalielsTrackerFrame")
    local button = frame and frame.MinimizeButton
    if not button or type(button.GetNormalTexture) ~= "function" then return nil, nil end
    local okTexture, texture = pcall(button.GetNormalTexture, button)
    if not okTexture or not texture then return nil, nil end

    -- KT intentionally turns this texture white while it is hovered.  That is
    -- transient button state, not the configured button color.  Keep the last
    -- applied AWP color until KT's OnLeave restores the resolved color.
    if type(button.IsMouseOver) == "function" then
        local okMouse, mouseOver = pcall(button.IsMouseOver, button)
        if okMouse and mouseOver then return texture, nil end
    end
    return texture, ReadVertexColor(texture)
end

local function ResolveKTAppearance(module)
    local sourceHeader = FindKTSourceHeader(module)
    if not sourceHeader then return nil end
    local sourceTitle = sourceHeader.Text or sourceHeader.HeaderText
    local buttonTexture, buttonColor = FindKTButtonTexture()
    return {
        texture = CaptureBackgroundTexture(sourceHeader.Background),
        backgroundColor = ReadVertexColor(sourceHeader.Background),
        font = CaptureFont(sourceTitle),
        textIconColor = ReadTextColor(sourceTitle),
        buttonColor = buttonColor,
        sourceBackground = sourceHeader.Background,
        sourceTitle = sourceTitle,
        sourceButtonTexture = buttonTexture,
    }
end

local function ApplyResolvedTexture(baseline, snapshot)
    local texture = baseline.background
    if not texture or type(snapshot) ~= "table" then return false end
    if not snapshot.shown then
        SetShown(texture, false)
        return true
    end
    if snapshot.atlas and type(texture.SetAtlas) == "function" then
        pcall(texture.SetAtlas, texture, snapshot.atlas, false)
    elseif type(texture.SetTexture) == "function" then
        pcall(texture.SetTexture, texture, snapshot.texture)
    else
        return false
    end
    if snapshot.texCoord and type(texture.SetTexCoord) == "function" then
        pcall(texture.SetTexCoord, texture, unpack(snapshot.texCoord, 1, snapshot.texCoord.n))
    end
    if IsNumber(snapshot.width) and IsNumber(snapshot.height) and type(texture.SetSize) == "function" then
        pcall(texture.SetSize, texture, snapshot.width, snapshot.height)
    end

    -- Preserve the source's layout shape, but anchor every copied point to
    -- AWP's own header.  This is the boundary that prevents cross-frame
    -- attachment to a KT-owned native module.
    if type(snapshot.points) == "table" and type(texture.ClearAllPoints) == "function"
        and type(texture.SetPoint) == "function"
    then
        pcall(texture.ClearAllPoints, texture)
        for index = 1, #snapshot.points do
            local point = snapshot.points[index]
            pcall(texture.SetPoint, texture, point[1], baseline.header, point[3], point[4], point[5])
        end
    end
    SetShown(texture, true)
    return true
end

local function ApplyTextIconColor(baseline, color)
    if type(color) ~= "table" then return false end
    local applied = ApplyTextColor(baseline.title, color)
    if baseline.icon then
        applied = ApplyVertexColor(baseline.icon, color, false) or applied
    end
    return applied
end

local function ApplyButtonColor(baseline, color)
    if type(color) ~= "table" then return false end
    local applied = false
    for index = 1, #baseline.buttonTextures do
        applied = ApplyVertexColor(baseline.buttonTextures[index], color, true) or applied
    end
    return applied
end

local function RestoreFacet(baseline, facet)
    if facet == "texture" then
        RestoreBackgroundTexture(baseline.background, baseline.texture)
    elseif facet == "backgroundColor" then
        ApplyVertexColor(baseline.background, baseline.backgroundColor, false)
    elseif facet == "font" then
        ApplyFontSnapshot(baseline.title, baseline.font)
    elseif facet == "textIconColor" then
        ApplyTextColor(baseline.title, baseline.titleColor)
        ApplyVertexColor(baseline.icon, baseline.iconColor, false)
    elseif facet == "buttonColor" then
        for texture, color in pairs(baseline.buttonColors) do
            ApplyVertexColor(texture, color, false)
        end
    end
    baseline.applied[facet] = nil
end

local function ScheduleSourceRefresh()
    if sourceRefreshPending then return end
    sourceRefreshPending = true
    local function refresh()
        sourceRefreshPending = false
        if type(NS.RefreshZygorTrackerViewerHeaderStyle) == "function" then
            NS.RefreshZygorTrackerViewerHeaderStyle()
        end
    end
    if type(NS.After) == "function" then
        NS.After(0, refresh)
    else
        local timer = rawget(_G, "C_Timer")
        if type(timer) == "table" and type(timer.After) == "function" then
            timer.After(0, refresh)
        else
            refresh()
        end
    end
end

local function HookRegionMethods(region, methods)
    if not region or type(hooksecurefunc) ~= "function" then return end
    local hooked = hookedRegions[region]
    if not hooked then
        hooked = {}
        hookedRegions[region] = hooked
    end
    for index = 1, #methods do
        local method = methods[index]
        if not hooked[method] and type(region[method]) == "function" then
            local ok = pcall(hooksecurefunc, region, method, ScheduleSourceRefresh)
            if ok then hooked[method] = true end
        end
    end
end

local function InstallKTSourceHooks(values)
    if type(values) ~= "table" then return end
    HookRegionMethods(values.sourceBackground, {
        "SetTexture", "SetAtlas", "SetTexCoord", "SetVertexColor",
        "ClearAllPoints", "SetPoint", "SetSize", "SetWidth", "SetHeight",
        "SetShown", "Show", "Hide",
    })
    HookRegionMethods(values.sourceTitle, {
        "SetFont", "SetTextColor", "SetShadowColor", "SetShadowOffset",
    })
    HookRegionMethods(values.sourceButtonTexture, { "SetVertexColor" })
end

function Style.Refresh(module)
    module = module or type(Shared.GetModuleFrame) == "function" and Shared.GetModuleFrame() or nil
    local baseline = module and (baselines[module] or Style.CaptureBaseline(module)) or nil
    if not baseline then return false end

    local settings = type(NS.GetZygorTrackerViewerSettings) == "function"
        and NS.GetZygorTrackerViewerSettings()
        or nil
    local enabled = settings and settings.ktHeaderStyle or {}
    local ktActive = Host and type(Host.IsKTLoaded) == "function" and Host.IsKTLoaded()
    local values = ktActive and ResolveKTAppearance(module) or nil
    if values then InstallKTSourceHooks(values) end

    local function applyFacet(facet, value, apply)
        if not enabled[facet] or not ktActive then
            if baseline.applied[facet] then RestoreFacet(baseline, facet) end
        elseif value ~= nil and apply(value) then
            baseline.applied[facet] = true
        end
    end

    applyFacet("texture", values and values.texture, function(value)
        return ApplyResolvedTexture(baseline, value)
    end)
    applyFacet("backgroundColor", values and values.backgroundColor, function(value)
        return ApplyVertexColor(baseline.background, value, false)
    end)
    applyFacet("font", values and values.font, function(value)
        return ApplyFontSnapshot(baseline.title, value)
    end)
    applyFacet("textIconColor", values and values.textIconColor, function(value)
        return ApplyTextIconColor(baseline, value)
    end)
    applyFacet("buttonColor", values and values.buttonColor, function(value)
        return ApplyButtonColor(baseline, value)
    end)
    return true
end

function NS.RefreshZygorTrackerViewerHeaderStyle()
    return Style.Refresh()
end
