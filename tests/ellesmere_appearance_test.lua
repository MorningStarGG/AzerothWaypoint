local f = assert(loadfile("tests/daylight_fixture.lua"))()
local Frame = getmetatable(f.Frame())
function Frame:CreateTexture() return f.Frame(self) end
function Frame:CreateFontString() return f.Frame(self) end
function Frame:SetTexture(value) self.textureFile = value end
function Frame:SetAtlas(value) self.atlas = value end
function Frame:SetBlendMode(value) self.blendMode = value end
local backdropMethods = {
    SetBackdrop = function(self, value) self.backdrop = value end,
    SetBackdropColor = function(self, ...) self.backdropColor = {...} end,
    SetBackdropBorderColor = function(self, ...) self.borderColor = {...} end,
}
for method in pairs(backdropMethods) do Frame[method] = nil end
local createFrame = CreateFrame
CreateFrame = function(kind, name, parent, template)
    local frame = createFrame(kind, name, parent, template)
    if template and template:find("BackdropTemplate", 1, true) then
        for method, fn in pairs(backdropMethods) do frame[method] = fn end
    end
    return frame
end
assert(CreateFrame("EditBox").SetBackdrop == nil, "Plain edit boxes must not inherit backdrop methods")
function Frame:SetVertexColor(...) self.vertex = {...} end
function Frame:GetVertexColor() return unpack(self.vertex or {1,1,1,1}) end
function Frame:SetColorTexture(...) self.colorTexture = {...} end
function Frame:SetAutoFocus() end
function Frame:SetJustifyH() end
function Frame:SetMaxLetters() end
function Frame:SetStatusBarTexture(value) self.statusTexture = value; self.texture=f.Frame(self) end
function Frame:SetStatusBarColor(...) self.statusColor = {...} end
function Frame:SetHighlightTexture(texture) self.highlight = texture end
function Frame:GetNormalTexture() return self.normal end
function Frame:GetPushedTexture() return nil end
function Frame:GetDisabledTexture() return nil end
function Frame:IsEnabled() return self.enabled ~= false end
function Frame:SetEnabled(value) self.enabled = value end
function Frame:EnableKeyboard() end
function Frame:SetText(value) self.text = value end
function Frame:HasFocus() return false end
function Frame:ClearFocus() end
function Frame:GetScript(key) return self.scripts and self.scripts[key] end
function Frame:SetTextColor(...) self.color = {...} end
function Frame:GetTextColor() return unpack(self.color or {1,1,1,1}) end
local look, modern, skinsEnabled = "eui", false, true
local callbacks, invalidations, pageRefreshes = {}, 0, 0
local ui = {
    FONT_ORDER = {"Expressway", "---", "Friz Quadrata"},
    GetFontsDB = function() return {} end,
    GetActiveProfileData = function() return {} end,
    ProfileWindowSkinLook = function() return look end,
    RenderedLook = function() return false end,
    GetFontUseShadow = function() return true end,
    GetFontPath = function() return "Ellesmere.ttf" end,
    GetFontOutlineFlag = function() return "" end,
    DD_BG_R=0.1,DD_BG_G=0.1,DD_BG_B=0.11,DD_BG_A=1,DD_BG_HA=1,DD_BRD_A=0.15,
    WB_COLOURS={0.08,0.08,0.08,1,0.1,0.1,0.1,1,1,1,1,0.15,1,1,1,0.3,1,1,1,1,1,1,1,1},
    FOREVER_BORDER={fill=2.75,corner=9,line=2},
    RoundBody=function(frame,texture) assert(texture);local mask=f.Frame(frame);mask:SetAllPoints(texture);texture:AddMaskTexture(mask);return mask end,
    MakeRoundedBorder=function(frame,r,g,b,a,body)
        if body then local mask=f.Frame(frame);mask:SetAllPoints(frame);body:AddMaskTexture(mask) end
        return {SetColor=function()end}
    end,
    MakeDropdownArrow=function(frame) local arrow=f.Frame(frame);arrow:SetSize(12,12);arrow:SetPoint("RIGHT",-8,0);return arrow end,
    ResolveFontName = function(key) return key .. ".ttf" end,
    StockAtlas = function(texture, atlas) texture:SetAtlas(atlas) end,
    ForeverBorder = function(frame) return {box = f.Frame(frame)} end,
    ForeverBorderSeat = function(ring, rel) ring.box:SetAllPoints(rel) end,
    ForeverBorderShown = function(ring, shown) ring.box:SetShown(shown) end,
    RegisterPlugin = function(_, spec) f.euiPlugin = spec; return true end,
    GetPluginModuleKey = function(_, key) return "plugin:AzerothWaypoint:" .. key end,
    InvalidateModulePageCache = function() invalidations = invalidations + 1 end,
    GetActiveModule = function() return nil end,
    RefreshPage = function() pageRefreshes = pageRefreshes + 1 end,
    IsSearchPrebuild = function() return f.prebuild == true end,
}
local skin = {
    apiVersion = 4, IsEnabled = function() return skinsEnabled end,
    GetStyle = function() return modern and "modern" or "eui" end,
    GetFont = function() return "Ellesmere.ttf", "" end,
    GetAccentColor = function() return 0.1, 0.8, 0.6 end,
    GetPanelColor = function() return 0.08, 0.08, 0.08, 0.92 end,
    Shell = function(frame, options) frame.nativeShell = true; frame.nativeShellOptions = options end,
    Panel = function(frame) frame.nativePanel = true end,
    Button = function(frame) frame.nativeButton = true end,
    EditBox = function(frame) frame.nativeInput = true end,
    ApplyBarFill = function(bar) bar:SetStatusBarColor(0.1,0.8,0.6,0.95) end,
    OnLooksChanged = function(fn) callbacks[#callbacks+1] = fn end,
}
ui.MakeStyledButton=function(frame,_,size,colors)
 local bg=f.Frame(frame);bg:SetAllPoints();bg:SetColorTexture(unpack(colors,1,4))
 local border=ui.MakeRoundedBorder(frame,1,1,1,0.15,bg)
 return bg,border,f.Frame(frame)
end
_G.Enum={UITextureSliceMode={Stretched=1}}
ui.RegisterSkin = function(name, fn) assert(name == "AzerothWaypoint"); f.skinCallback = fn; fn(skin) end
_G.EllesmereUI = ui
assert(loadfile("core/core.lua"))()
assert(loadfile("interface/appearance/controller.lua"))()
assert(loadfile("interface/appearance/visuals.lua"))()
assert(loadfile("interface/appearance/provider.lua"))()
assert(loadfile("interface/appearance/providers/daylight.lua"))()
assert(loadfile("interface/appearance/providers/ellesmere.lua"))()
local a, d, e = AzerothWaypointNS.Internal.Appearance, AzerothWaypointNS.Internal.Daylight, AzerothWaypointNS.Internal.Ellesmere
f.Fire("PLAYER_LOGIN"); f.Flush()
assert(not e.GetSettings().enabled and not e.IsEnabled("plaque"))
assert(#f.euiPlugin.modules == 4 and #callbacks == 1)
local root = f.Frame(); a.Tag(root,"plaque")
local text = f.Frame(root); text:SetTextColor(0.3,0.4,0.5,0.9); a.Text(text,"plaque","TITLE")
local art = f.Frame(root); art:SetAlpha(0.65); a.Shell(root,"plaque",{art})
local bar = f.Frame(); bar.texture = f.Frame(bar); bar:SetValue(42); a.StyleProgress(bar,"guide.zygor")
local button = f.Frame(); button._awpButtonArtHost = button; button._awpNativeButtonRegions = {f.Frame(button)}
button.normal = f.Frame(button); a.StyleButton(button,"guide.zygor")
local slider = CreateFrame("Slider"); a.Tag(slider,"windows.options")
local sliderValue = 15
local sliderRegions = {f.Frame(slider),f.Frame(slider),f.Frame(slider)}
slider:SetValue(sliderValue)
a.RegisterSlider(slider,sliderRegions,function() return sliderValue end,function(value) sliderValue=value end,
    0,100,1,tostring,f.Frame(slider))
assert(a.Select("ellesmere")); f.Flush()
assert(a.GetSelectedID() == "ellesmere" and not e.lastError, e.lastError)
assert(text:GetFont() == "Ellesmere.ttf" and art:GetAlpha() == 0)
assert(a.GetRGB("plaque","TITLE") == nil, "Semantic colors changed by default")
assert(bar._awpAppearanceBar:GetValue() == 42 and bar.texture:GetAlpha() == 0)
assert(a.visuals[button].currentState and button._awpNativeButtonRegions[1]:GetAlpha()==0)
e.SetSetting("guide.dugi","fonts",false); f.Flush()
assert(e.GetSettings("guide.zygor").fonts and not e.GetSettings("guide.dugi").fonts)
local function change(value, isModern)
    look, modern = value, isModern
    for _, fn in ipairs(callbacks) do fn() end
    f.Flush()
    local actual, reason = e.GetStatus(); assert(not reason,reason); return actual
end
local insetFrame, taxiFrame = f.Frame(), f.Frame()
local inset = a.Shell(insetFrame, "windows.queue", { f.Frame(insetFrame) }, nil, "inset")
local taxiShell = a.Shell(taxiFrame, "windows.taxi", { f.Frame(taxiFrame) }, nil, "window")
local scrollBar = f.Frame(taxiFrame)
local scrollThumb, scrollTrack = f.Frame(scrollBar), f.Frame(scrollBar)
local scrollbar = a.RegisterVisual(scrollBar, { kind = "scrollbar", surface = "windows.taxi", target = scrollThumb,
    track = scrollTrack, regions = { scrollThumb, scrollTrack } })
for _, style in ipairs({"classic", "blizzard", "forever", "eui"}) do
    assert(change(style) == style)
    assert(art:GetAlpha() == 0 and not e.lastError, e.lastError)
    assert(inset.applied and inset.currentState.inputKind and taxiShell.applied)
    assert(scrollbar.currentState.thumb:GetWidth() == 4 and scrollbar.currentState.thumb.colorTexture[4] == 0.3)
    assert(scrollTrack:GetAlpha() == 0 and not scrollbar.holder.awpScrollTrack)
    if style == "forever" then
        assert(inset.currentState.rim and taxiShell.currentState.rim)
    elseif style == "classic" or style == "blizzard" then
        assert(inset.currentState.root.backdrop.edgeSize == 8)
        assert(taxiShell.currentState.root.backdrop.edgeSize == 16)
    else
        assert(inset.currentState.border and taxiShell.currentState.root.nativeShell)
    end
    local input = assert(a.visuals[slider].currentState.input)
    assert(type(input.SetBackdrop) == "function", "Styled slider input is missing its backdrop template")
    if style == "classic" or style == "blizzard" then assert(input.backdrop and input.backdrop.edgeFile) end
    input:SetText("29"); input:GetScript("OnEnterPressed")(input)
    assert(sliderValue == 29 and slider:GetValue() == 29, "Styled numeric input lost its binding")
end
assert(change(false,true) == "eui", "The window background was confused with the overall look")
assert(change(nil,false) == "eui")
local count, applied = #f.frames, e.counters.applied
for _=1,1000 do e.RequestRefresh() end
f.Flush(); assert(e.counters.applied == applied and #f.frames == count)
e.SetSetting(nil,"enabled",false); f.Flush()
assert(text:GetFont() == "AWP.ttf" and art:GetAlpha() == 0.65)
assert(scrollThumb:GetAlpha() == 1 and scrollTrack:GetAlpha() == 1 and not scrollbar.holder:IsShown())
assert(bar.texture:GetAlpha() == 1 and not bar._awpAppearanceBar)
assert(button._awpNativeButtonRegions[1]:GetAlpha()==1)
assert(sliderRegions[1]:GetAlpha()==1 and not a.visuals[slider].holder:IsShown())
for _=1,5 do
    a.Select("daylight"); f.Flush(); assert(text:GetFont() == "Daylight.ttf")
    a.Select("ellesmere"); f.Flush(); assert(text:GetFont() == "Ellesmere.ttf")
    assert(not d.GetSettings().enabled and e.GetSettings().enabled)
end
f.combat = true; a.Select("awp"); f.Flush()
assert(a.deferred and art:GetAlpha() == 0)
f.combat = false; f.Fire("PLAYER_REGEN_ENABLED"); f.Flush()
assert(art:GetAlpha() == 0.65 and text:GetFont() == "AWP.ttf")
f.flavor = "retail"; a.Select("ellesmere"); change("forever")
assert(e.GetStatus() == "blizzard", "Forever-only art used on Retail")
local fontPath = ui.GetFontPath; ui.GetFontPath = nil; e.RequestRefresh(); f.Flush()
assert(not e.GetAPI() and select(2,e.GetStatus()):find("GetFontPath",1,true))
assert(text:GetFont() == "AWP.ttf" and art:GetAlpha() == 0.65)
ui.GetFontPath = fontPath; skinsEnabled = false; e.RequestRefresh(); f.Flush()
assert(not e.GetAPI() and art:GetAlpha() == 0.65)
skinsEnabled = true; e.RequestRefresh(); f.Flush(); assert(text:GetFont() == "Ellesmere.ttf")
-- Native pages use the public full-width row factory, including disabled
-- predicates, typed colors, defaults and a side-effect-free search prebuild.
local rows = {}
local openSettings
ui.Widgets = {
    SectionHeader = function() return nil,30 end,
    DualRow = function(_,_,_,cfg) rows[#rows+1] = cfg; return nil,50 end,
    Button = function(_, _, text, _, onClick)
        if text == "Open AWP Settings" then assert(not openSettings); openSettings = onClick
        else assert(text:match("^Open .+ Viewer text settings$") and type(onClick)=="function") end
        return nil, 50
    end,
}
f.prebuild = true
local frameCount = #f.frames
for _, module in ipairs(f.euiPlugin.modules) do assert(module.buildPage(module.pages[1],root,0) > 0) end
assert(#f.frames == frameCount, "Search prebuild created frames")
local hostClosed, opened
ui.CloseConfig = function() hostClosed = true end
AzerothWaypointNS.OpenOptionsPanel = function() assert(hostClosed); opened = true end
assert(openSettings)
openSettings()
assert(opened)
local fonts, fontPicker, colors
for _, cfg in ipairs(rows) do
    if cfg.text == "Apply selected font" and not fonts then fonts = cfg end
    if cfg.text == "Font" and not fontPicker then fontPicker = cfg end
    if cfg.type == "colorpicker" and not colors then colors = cfg end
end
fonts.setValue(false); f.Flush(); assert(fontPicker.disabled())
fonts.setValue(true); f.Flush(); assert(not fontPicker.disabled())
assert(type(colors.getValue()) == "number")
assert(invalidations > 0 and pageRefreshes == 0, "Hidden options were rebuilt")
print("Ellesmere appearance: looks, clients, exclusivity, restoration, combat, missing capabilities, native settings and bounded refresh passed")

return {f=f,ui=ui,a=a,e=e,skin=skin,change=change}
