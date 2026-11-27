local NativePath = dofile("tests/native_path.lua")
local context = assert(loadfile("tests/ellesmere_appearance_test.lua"))()
local f, a, e, ui, skin = context.f, context.a, context.e, context.ui, context.skin
f.prebuild, f.flavor = false, "forever"
local Frame = getmetatable(f.Frame())
function Frame:IsForbidden() return false end

-- Execute the installed close helper on an AWP-owned visual. Its native glyph
-- and hover scripts must never replace the logical button's click handler.
local sourceFile = assert(io.open(NativePath("retail", "EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin_WindowEngine.lua")))
local source = sourceFile:read("*a"); sourceFile:close()
local first = assert(source:find("function WSkin.CloseButton(btn)", 1, true))
local last = assert(source:find("-- Active-filter reset", first, true))
local chunk = assert(loadstring(source:sub(first, last - 1) .. "\nreturn WSkin.CloseButton"))
local foreign = setmetatable({}, { __mode = "k" })
local owners = {}
setfenv(chunk, setmetatable({ WSkin = {},
    GetFFD = function(frame)
        if not foreign[frame] then foreign[frame] = {} end
        return foreign[frame]
    end,
    FadeRegions = function(frame) owners[frame] = true end,
}, { __index = _G }))
skin.CloseButton = chunk()

assert(loadfile("interface/framework/panels.lua"))()
local framework = AzerothWaypointNS.Internal.Interface.Framework
local function panel()
    local frame = f.Frame()
    frame:SetSize(600, 400)
    return framework.CreatePanelShell(frame, { surface = "windows.options", title = "AzerothWaypoint",
        titleHeight = 44, closeBorder = true })
end

for _, modern in ipairs({false, true}) do
    context.change("eui", modern)
    local shell = panel()
    local window = a.visuals[shell.frame]
    local state = window.currentState
    assert(window.applied and state.root.nativeShell, e.lastError)
    assert(state.root.nativeShellOptions.noBorder and state.root.nativeShellOptions.noTopBar)
    assert(not state.border and not state.fill, "Window still has an AWP rounded panel above the native shell")
    assert(state.titleBand.allPoints == shell.titleFrame, "Title strip ignores AWP's title area")
    local r, g, b = shell.titleText:GetTextColor()
    local ar, ag, ab = skin.GetAccentColor()
    assert(r == ar and g == ag and b == ab, "The title lost its accent color")

    local close = shell.closeButton
    local record = assert(a.visuals[close])
    local visual = record.currentState
    assert(record.kind == "close" and owners[visual.root] and not owners[close])
    assert(visual.hideText and not visual.border and not visual.fill)
    assert(close.label:GetAlpha() == 0 and close.bg:GetAlpha() == 0 and close.border:GetAlpha() == 0)
    local glyph = foreign[visual.root].x
    assert(glyph.atlas == "uitools-icon-close" and glyph:GetWidth() == 14)
    assert(select(4, glyph:GetVertexColor()) == 0.75)
    local clicks = 0
    close:SetScript("OnClick", function() clicks = clicks + 1 end)
    close:GetScript("OnEnter")(close)
    assert(select(4, glyph:GetVertexColor()) == 1)
    close:GetScript("OnClick")(close)
    close:GetScript("OnLeave")(close)
    assert(clicks == 1 and select(4, glyph:GetVertexColor()) == 0.75)

    local header = f.Frame(shell.frame)
    a.Tag(header, "guide.zygor")
    -- Ellesmere's divider is parented outside the header and can be less than
    -- one UI unit tall. Preserve it rather than adding or resizing a second.
    local hostRoot = f.Frame()
    local divider = f.Frame(hostRoot)
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 7, 0)
    divider:SetHeight(0.8); divider:SetAlpha(1); divider:Show()
    local hiddenLine = f.Frame(header)
    hiddenLine:SetHeight(1); hiddenLine:Hide()
    local headerRecord = a.RegisterVisual(header, {kind = "header", facet = "header"})
    local headerState = headerRecord.currentState
    assert(headerState.fill and not headerState.line and not headerState.border and not headerState.mask,
        "AWP added a separator or outline to the EUI section header")
    assert(not headerState.root.nativeShell)

    local normal = f.Frame(shell.frame)
    local buttonRecord = a.RegisterVisual(normal, {kind = "button"})
    assert(buttonRecord.currentState.border and not buttonRecord.currentState.hideText,
        "An ordinary button lost its native border")

    local count = #f.frames
    for _ = 1, 1000 do a.UpdateVisual(shell.frame); a.UpdateVisual(close); a.UpdateVisual(header) end
    assert(#f.frames == count, "Chrome refreshes allocate new visual frames")
    assert(divider:IsShown() and divider:GetHeight() == 0.8 and divider:GetAlpha() == 1)
    assert(divider:GetParent() == hostRoot and divider.point[3] == "BOTTOMLEFT" and not hiddenLine:IsShown(),
        "AWP changed the host divider or revealed a hidden template line")
    a.Select("awp"); f.Flush()
    assert(close.label:GetAlpha() == 1 and close.bg:GetAlpha() == 1 and close.border:GetAlpha() == 1)
    assert(not record.applied and not window.applied and not headerRecord.applied)
    assert(not record.holder:IsShown() and not window.holder:IsShown())
    assert(divider:IsShown() and divider:GetHeight() == 0.8 and not hiddenLine:IsShown())
    a.Select("ellesmere"); f.Flush()
    assert(record.currentState == visual and close.label:GetAlpha() == 0)

    for _, look in ipairs({"forever","blizzard","classic"}) do
        context.change(look, false)
        local boxed = record.currentState
        local icon = assert(boxed.closeGlyph, "Boxed close still depends on font metrics")
        assert(boxed.hideText and close.label:GetAlpha() == 0)
        assert(icon.atlas == "uitools-icon-close" and icon:GetWidth() == 14 and icon:GetHeight() == 14)
        local point, relative, relativePoint, x, y = icon:GetPoint()
        assert(point == "CENTER" and relative == boxed.root and relativePoint == "CENTER" and x == 0 and y == 0,
            "Close icon is not centered in the boxed visual")
        assert(boxed.rim or boxed.root.backdrop or boxed.nativeButton, "Boxed close lost its style border")
        close:GetScript("OnEnter")(close)
        assert(select(4,icon:GetVertexColor()) == 1)
        close:GetScript("OnLeave")(close)
        assert(select(4,icon:GetVertexColor()) == 0.75)
        close:SetEnabled(false); a.UpdateVisual(close)
        assert(boxed.root:GetAlpha() == 0.4)
        close:SetEnabled(true); a.UpdateVisual(close)
        assert(boxed.root:GetAlpha() == 1)
        close.label:SetFont("UnusuallyTall.ttf",24,"OUTLINE"); a.UpdateVisual(close)
        assert(icon:GetWidth() == 14 and icon:GetHeight() == 14 and select(5,icon:GetPoint()) == 0,
            "Font changes moved or resized the close icon")
        local frameCount = #f.frames
        for _ = 1, 1000 do a.UpdateVisual(close) end
        assert(#f.frames == frameCount)
        a.Select("awp"); f.Flush()
        assert(close.label:GetAlpha() == 1 and not record.applied and not record.holder:IsShown())
        local beforeClick = clicks
        close:GetScript("OnClick")(close)
        assert(clicks == beforeClick + 1, "Close click handler was replaced or invoked twice")
        a.Select("ellesmere"); f.Flush()
        assert(record.currentState == boxed and close.label:GetAlpha() == 0)
    end
    context.change("eui", modern)
    assert(record.currentState == visual and close.label:GetAlpha() == 0)
end

print("Ellesmere chrome: native Modern close, font-independent centered boxed close icons, hover/disabled states, caching and restoration passed")
