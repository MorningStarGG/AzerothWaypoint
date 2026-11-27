local replaceMethod = dofile("tests/replace_method.lua")
local f=assert(loadfile("tests/daylight_fixture.lua"))()
local sharedFontEvent, sharedFontFile
local sharedMedia = {}
function sharedMedia.RegisterCallback(_, event, handler)
    assert(event == "LibSharedMedia_Registered" and not sharedFontEvent)
    sharedFontEvent = handler
end
LibStub = function(name)
    if name == "LibSharedMedia-3.0" then return sharedMedia end
end
assert(loadfile("core/core.lua"))()
assert(loadfile("interface/appearance/controller.lua"))()
assert(loadfile("interface/appearance/visuals.lua"))()
assert(loadfile("interface/appearance/provider.lua"))()
assert(loadfile("interface/appearance/providers/daylight.lua"))()
local a,d=AzerothWaypointNS.Internal.Appearance,AzerothWaypointNS.Internal.Daylight
f.Fire("PLAYER_LOGIN");f.Flush()
assert(f.plugin.name=="AzerothWaypoint" and f.settingsModule.defaults)
assert(not d.GetSettings().enabled and d.GetSettings("guide.dugi").enabled)
local root=f.Frame();a.Tag(root,"plaque")
local text=f.Frame(root);a.Text(text,nil,"TEXT")
local panel=f.Frame(root);local background=f.Frame(panel);background:SetAlpha(0.45)
a.Shell(panel,"plaque",{background})
assert(text:GetFont()=="AWP.ttf" and background:GetAlpha()==0.45)
d.SetSetting(nil,"enabled",true);f.Flush()
assert(text:GetFont()=="Daylight.ttf" and select(2,text:GetFont())==13)
assert(background:GetAlpha()==0 and not d.GetRGB("plaque","TEXT"))
-- EditBox GetFontObject can expose a native font inheritance node. Appearance
-- never changes that graph, so refreshing a shell must not assign it back.
local edit=f.Frame(root)
function edit:GetFontObject() error("Appearance must not capture native font nodes") end
function edit:SetFontObject() error("Appearance must not reassign native font inheritance") end
edit:SetFont("Search.ttf",12,"OUTLINE")
a.Text(edit,"windows.search","TEXT")
d.SetSetting("guide.zygor","header",false);f.Flush()
assert(not d.lastError and edit:GetFont()=="Daylight.ttf")
d.SetSetting("guide.zygor","header",true);f.Flush()
d.SetSetting(nil,"enabled",false);f.Flush()
assert(edit:GetFont()=="Search.ttf" and select(2,edit:GetFont())==12)
d.SetSetting(nil,"enabled",true);f.Flush()
local count=#f.frames
d.SetSetting("plaque","colors",true);f.Flush()
assert(text.r==f.palette.TEXT[1] and #f.frames==count,"A toggle created duplicate shells")
d.SetSetting("guide.zygor","colors",true);f.Flush()
assert(not d.GetRGB("guide.zygor","TEXT"),"A theme switch overrode Auto")
f.viewerSettings.zygor.textColorMode="theme"
assert(d.GetRGB("guide.zygor","TEXT") and not d.GetRGB("guide.dugi","TEXT"))
d.SetSetting("guide.dugi","enabled",false);f.Flush()
-- Both UIs use the exact same getters and setters.
local groups=f.settingsModule.options.pages[1].groups
assert(groups[1].items[1].get())
groups[1].items[1].set(false);f.Flush()
assert(text:GetFont()=="AWP.ttf" and background:GetAlpha()==0.45)
assert(d.GetSettings("plaque").colors and not d.GetSettings("guide.dugi").enabled)
groups[1].items[1].set(true);f.Flush()
assert(text:GetFont()=="Daylight.ttf" and #f.frames==count)
-- Underlying appearance changes while themed are restored accurately.
text:SetFont("KT.ttf",17,"THICKOUTLINE");a.Text(text,"plaque","TEXT")
d.SetSetting(nil,"enabled",false);f.Flush()
assert(text:GetFont()=="KT.ttf" and select(2,text:GetFont())==17)
-- Theme changes coalesce, and combat holds only the pending refresh.
local applied=d.counters.applied
for _=1,100 do f.Emit("StyleChanged") end
f.Flush();assert(d.counters.applied==applied,"Disabled appearance should ignore theme bursts")
f.combat=true;d.SetSetting(nil,"enabled",true);f.Flush()
assert(text:GetFont()=="KT.ttf" and a.deferred)
f.combat=false;f.Fire("PLAYER_REGEN_ENABLED");f.Flush()
assert(text:GetFont()=="Daylight.ttf")
-- Invalid provider updates are atomic, and public widgets are reused/restored.
local before=d.GetSettings("guide.dugi").enabled
assert(not d.SetSurfaceSettings("guide.dugi",{enabled=not before,unknown=true}))
assert(d.GetSettings("guide.dugi").enabled==before)
local check=f.Frame(root);check.boxBorder=f.Frame(check);check:SetChecked(true)
local checked=f.Frame(check);checked:SetAlpha(0.7)
local label=f.Frame(root);label:SetPoint("LEFT",check.boxBorder,"RIGHT",6,0)
a.RegisterToggle(check,{checked},label)
local switch=f.frames[#f.frames]
assert(switch:GetWidth()==36 and switch:GetHeight()==20,"Public switch was resized without its artwork")
assert(a.visuals[check].holder.point[1]=="LEFT" and a.visuals[check].holder.point[2]==check.boxBorder)
assert(label.point[2]==switch and label.point[3]=="RIGHT" and label.point[4]==8,"Themed toggle overlaps its label")
local gradientsOff, gradientUpdates = false, 0
f.api.GetSetting = function(scope, path)
    assert(scope == "general" and path == "gradients.off")
    return gradientsOff
end
DaylightUI.Style = {SetBarGradient = function(bar, useDaylight)
    assert(useDaylight)
    bar.gradient = not gradientsOff
    gradientUpdates = gradientUpdates + 1
end}
local newBar = f.api.Bar
f.api.Bar = function(parent)
    local native = newBar(parent)
    native.gradient = not gradientsOff -- Daylight's constructor uses the current option.
    return native
end
f.Emit("StyleChanged"); f.Flush()
local bar=f.Frame();bar.texture=f.Frame(bar);bar:SetValue(43)
a.StyleProgress(bar,"guide.zygor")
assert(not a.shells[bar],"A window shell was added over the progress track")
assert(bar._awpAppearanceBar:GetValue()==43 and bar.texture:GetAlpha()==0)
assert(bar._awpAppearanceBar:GetFrameLevel()==bar:GetFrameLevel()-1,"Daylight fill must sit immediately beneath the counter")
local themedBar = bar._awpAppearanceBar
assert(themedBar.gradient and gradientUpdates == 0)
gradientsOff = true
f.Emit("StyleChanged"); f.Flush()
assert(bar._awpAppearanceBar == themedBar and themedBar:GetValue() == 43 and not themedBar.gradient and gradientUpdates == 1)
local another = f.Frame(); another:SetValue(19)
a.StyleProgress(another, "guide.zygor")
local anotherThemedBar = another._awpAppearanceBar
assert(not anotherThemedBar.gradient and gradientUpdates == 1)
for _ = 1, 10 do f.Emit("StyleChanged") end
f.Flush()
assert(gradientUpdates == 1, "An unchanged Daylight style notification restyled the progress fill")

gradientsOff = false
f.combat = true
f.Emit("StyleChanged"); f.Flush()
assert(not themedBar.gradient and gradientUpdates == 1)
f.combat = false
f.Fire("PLAYER_REGEN_ENABLED"); f.Flush()
assert(themedBar.gradient and anotherThemedBar.gradient and gradientUpdates == 3)
assert(bar._awpAppearanceBar == themedBar and themedBar:GetValue() == 43 and anotherThemedBar:GetValue() == 19)

local currentStyle = DaylightUI.Style
DaylightUI.Style = nil
f.Emit("StyleChanged"); f.Flush()
assert(d.lastError and d.lastError:find("Style.SetBarGradient", 1, true)
    and bar.texture:GetAlpha() == 1, "Missing current gradient API must restore native appearance")
DaylightUI.Style = currentStyle
f.Emit("StyleChanged"); f.Flush()
assert(not d.lastError and bar._awpAppearanceBar == themedBar)
local getSetting = f.api.GetSetting
f.api.GetSetting = nil
f.Emit("StyleChanged"); f.Flush()
assert(d.lastError and d.lastError:find("API.GetSetting", 1, true))
f.api.GetSetting = getSetting
f.Emit("StyleChanged"); f.Flush()
assert(not d.lastError)
local countAfterWidgets=#f.frames
for _=1,10 do
 d.SetSetting(nil,"enabled",false);f.Flush();a.StyleProgress(bar,"guide.zygor")
 assert(checked:GetAlpha()==0.7 and bar.texture:GetAlpha()==1)
 assert(label.point[2]==check.boxBorder and label.point[4]==6,"Unstyled checkbox spacing was not restored")
 d.SetSetting(nil,"enabled",true);f.Flush();a.StyleProgress(bar,"guide.zygor")
 assert(label.point[2]==switch and label.point[4]==8,"Re-enabling styling lost label spacing")
end
assert(#f.frames==countAfterWidgets,"Repeated toggles accumulated public widgets")
-- A failed public API cannot strand partial styling or permanently stop refresh.
local colors=f.api.Colors
f.api.Colors=function()error("fixture: unavailable palette")end
f.Emit("StyleChanged");f.Flush()
assert(d.lastError and not d.IsEnabled("plaque"))
f.api.Colors=colors;f.Emit("StyleChanged");f.Flush()
assert(not d.lastError and d.IsEnabled("plaque"))
-- Typed rows and native live binding: the current switch updates in the same setter call.
local rows, kinds={},{}
assert(#f.settingsModule.options.pages==4)
for _,page in ipairs(f.settingsModule.options.pages)do
 for _,group in ipairs(page.groups)do
  for _,item in ipairs(group.items)do
   kinds[item.type]=true
   if group.surface=="guide.dugi" and item.label=="Use DaylightUI style" then rows.dugi=item end
  end
 end
end
assert(kinds.dropdown and kinds.slider and kinds.color and rows.dugi)
local overview = d.GetOptionGroups("overview")[1]
assert(overview.label == "DaylightUI Style" and overview.desc:find("General > UI Style", 1, true))
assert(overview.items[1].desc:find("Use DaylightUI as AWP's UI style", 1, true))
local visible,refreshes=nil,0
DaylightUI.OptionsPanel={Refresh=function() refreshes=refreshes+1;visible=rows.dugi.get() end}
rows.dugi.set(true);assert(visible==true)
rows.dugi.set(false);assert(visible==false and refreshes==2)
f.Flush()
-- Font, outline, shadow, per-role sizes and colors produce actual rendering changes.
d.SetSurfaceSettings("plaque",{fontKey="example",outline="thick",shadow="off",textScale=1.25})
f.Flush()
assert(text:GetFont()=="example.ttf" and select(3,text:GetFont())=="THICKOUTLINE")
assert(select(2,text:GetFont())==17*1.25 and text.shadowAlpha==0)

-- Daylight emits no StyleChanged event for a font picked only by an AWP area.
local fontFile = f.api.FontFile
f.api.FontFile = function(key)
    if key == "lsm:Late font" then return sharedFontFile or "Daylight.ttf" end
    return fontFile(key)
end
d.SetSetting("plaque", "fontKey", "lsm:Late font")
f.Flush()
assert(text:GetFont() == "Daylight.ttf")
local requested = d.counters.requested
assert(sharedFontEvent, "AWP did not subscribe to shared font registration")
sharedFontEvent("LibSharedMedia_Registered", "font", "Unrelated font")
sharedFontEvent("LibSharedMedia_Registered", "statusbar", "Late font")
assert(d.counters.requested == requested)
f.combat = true
sharedFontFile = "Late.ttf"
sharedFontEvent("LibSharedMedia_Registered", "font", "Late font")
assert(d.counters.requested == requested + 1)
f.Flush()
assert(text:GetFont() == "Daylight.ttf" and a.deferred)
f.combat = false
f.Fire("PLAYER_REGEN_ENABLED")
f.Flush()
assert(text:GetFont() == "Late.ttf", "A shared font picked only by AWP kept its fallback")
d.SetSetting("plaque", "fontKey", "example")
f.Flush()
f.api.FontFile = fontFile

d.SetSurfaceSettings("plaque",{customSizes=true,bodySize=18,tipSize=10,headingSize=20,textScale=1,
 colorSource="custom",textColor={0.2,0.3,0.4}})
f.Flush()
local note=f.Frame(root);a.Text(note,"plaque",nil,nil,"tip")
local title=f.Frame(root);a.Text(title,"plaque",nil,nil,"heading")
assert(select(2,text:GetFont())==18 and select(2,note:GetFont())==10 and select(2,title:GetFont())==20)
assert(text.r==0.2 and text.g==0.3 and text.b==0.4)
-- Old development preferences cannot strip components from the complete shell.
for _,surface in ipairs(d.surfaces)do
 local settings=d.GetSettings(surface.key)
 settings.background=false;settings.border=false;settings.bevel=false
 settings.ownOpacity=true;settings.opacity=0
 settings.ownBorderWidth=true;settings.borderWidth=4
end
f.Emit("StyleChanged");f.Flush()
for _,surface in ipairs(d.surfaces)do
 local frame=f.Frame()
 d.SetSetting(surface.key,"enabled",true);f.Flush()
 a.Shell(frame,surface.key)
 local opts=a.shells[frame].holder.skinOptions
 assert(opts.window==true)
 for key in pairs(opts)do assert(key=="window","AWP overrides a Daylight shell component: "..key)end
end
for _,key in ipairs{"background","border","bevel","ownOpacity","opacity","ownBorderWidth","borderWidth"}do
 assert(not d.SetSetting("plaque",key,false),"Removed shell control is still accepted: "..key)
end
d.SetSetting(nil,"enabled",false);f.Flush()
assert(text:GetFont()=="KT.ttf" and select(2,text:GetFont())==17 and background:GetAlpha()==0.45)
-- Shared native/KT pools do not retain or receive AWP's appearance after release.
d.SetSetting(nil,"enabled",true);f.Flush()
local module=f.Frame();module._awpGuideProvider="zygor";module.usedBlocks={}
local block=f.Frame(module);block.parentModule=module;block.id="step";block.template="block";block.usedLines={}
module.usedBlocks.block={step=block}
local line=f.Frame(block);line.parentBlock=block;line.objectiveKey=1;line._awpGuideProvider="zygor"
block.usedLines[1]=line
local pooled=f.Frame(line);a.Text(pooled,"guide.zygor")
assert(pooled:GetFont()=="Daylight.ttf")
block.usedLines[1]=nil;a.PruneModule(module)
assert(pooled:GetFont()=="AWP.ttf" and not a.texts[pooled])
line:SetParent(f.Frame());pooled:SetFont("Native.ttf",12,"")
f.Emit("StyleChanged");f.Flush()
assert(pooled:GetFont()=="Native.ttf","Style refresh modified a released native row")
-- Real module styling must use the public bar directly, without the window
-- border, bevel or shadow obscuring a small progress track.
local guideHeader=f.Frame();guideHeader.Text=f.Frame(guideHeader);guideHeader:SetFrameLevel(6)
local progress=f.Frame(guideHeader);progress:SetSize(58,14);progress:SetFrameLevel(8)
progress.texture=f.Frame(progress);progress:SetValue(34)
progress._awpBaseRequestedWidth = 58
local guide={_awpGuideProvider="zygor",Header=guideHeader,_awpControls={progressBar=progress,counter=f.Frame(progress)}}
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/viewer_styles.lua"))()
assert(loadfile("integrations/guides/viewer_controls.lua"))()
assert(loadfile("integrations/guides/viewer_header_style.lua"))()
local common = AzerothWaypointNS.Internal.GuideTrackerViewer
local headerStyle = common.HeaderStyle
local fitWidth, dirty = 100, 0
common.Controls.LayoutHeader = function(module)
    assert(module == guide)
    progress:SetWidth(math.min(fitWidth, progress._awpRequestedWidth))
end
guide.MarkDirty = function() dirty = dirty + 1 end
_G.AwpAppearanceFixtureGuide = guide
common.Registry = { providers = { zygor = { moduleName = "AwpAppearanceFixtureGuide" } } }
assert(headerStyle.Refresh(guide))
local headerShell=a.shells[guideHeader]
assert(headerShell.holder:IsShown())
d.SetSetting("guide.zygor","header",false);f.Flush()
assert(not headerShell.holder:IsShown(),"Disabling Daylight header left its shell visible")
d.SetSetting("guide.zygor","header",true);f.Flush()
assert(headerShell.holder:IsShown(),"Re-enabling Daylight header did not restore its shell")
local fill=progress._awpAppearanceBar
assert(not a.shells[progress] and not a.shells[fill],"Guide progress inherited the full window shell")
assert(fill:GetParent()==a.visuals[progress].holder and progress:GetHeight()==14 and fill:GetHeight()==14
    and fill:GetWidth()==progress:GetWidth() and fill:GetValue()==34,"Daylight fill does not occupy the full progress rectangle")
assert(fill:GetFrameLevel()>guideHeader:GetFrameLevel() and fill:GetFrameLevel()<progress:GetFrameLevel())
local beforeFrames=#f.frames
for _=1,10 do headerStyle.Refresh(guide) end
assert(#f.frames==beforeFrames,"Repeated guide styling accumulates progress decorations")
d.SetSetting("guide.zygor","progress",false);f.Flush()
assert(not fill:IsShown() and progress.texture:GetAlpha()==1,"Native progress did not restore")
d.SetSetting("guide.zygor","progress",true);f.Flush()
assert(fill:IsShown() and fill:GetValue()==34 and not a.shells[progress])
-- A guide's fitted bar width is never saved as its requested preference.
fitWidth = 42
local phases = {}
a.RegisterRefreshCallback("beforeVisuals", function()
    assert(progress.texture:GetAlpha() == 1)
    phases[#phases + 1] = "baseline"
end)
a.RegisterRefreshCallback("afterVisuals", function()
    assert(progress._awpRequestedWidth == (a.GetProgressWidth("guide.zygor") or 58))
    phases[#phases + 1] = "geometry"
end)
a.RegisterRefreshCallback("afterRefresh", function() phases[#phases + 1] = "settled" end)
local beforeDirty = dirty
d.SetSurfaceSettings("guide.zygor",{ownProgressWidth=true,progressWidth=100});f.Flush()
assert(progress._awpRequestedWidth==100 and progress:GetWidth()==42)
assert(table.concat(phases, ",") == "baseline,geometry,settled" and dirty == beforeDirty + 1)
phases = {}
f.combat = true
d.SetSetting("guide.zygor", "progressWidth", 90); f.Flush()
assert(#phases == 0 and progress._awpRequestedWidth == 100)
f.combat = false; f.Fire("PLAYER_REGEN_ENABLED"); f.Flush()
assert(table.concat(phases, ",") == "baseline,geometry,settled" and progress._awpRequestedWidth == 90)
phases = {}
local availableColors = replaceMethod(f.api, "Colors", function() error("fixture: late palette failure") end)
f.Emit("StyleChanged"); f.Flush()
assert(table.concat(phases, ",") == "geometry,settled" and a.GetEffectiveID() == "awp")
assert(progress._awpRequestedWidth == 58 and progress.texture:GetAlpha() == 1 and not fill:IsShown())
f.api.Colors = availableColors
f.Emit("StyleChanged"); f.Flush()
assert(progress._awpRequestedWidth == 90 and fill:IsShown())
local renderVisual = d.RenderVisual
d.RenderVisual = function() error("fixture: visual failed outside refresh") end
local lateControl = f.Frame()
a.RegisterVisual(lateControl, { kind = "button", surface = "windows.options" })
assert(progress._awpRequestedWidth == 58 and progress.texture:GetAlpha() == 1 and not fill:IsShown())
d.RenderVisual = renderVisual
f.Emit("StyleChanged"); f.Flush()
assert(progress._awpRequestedWidth == 90 and fill:IsShown())
d.SetSetting("guide.zygor","ownProgressWidth",false);f.Flush()
assert(progress._awpRequestedWidth==58,"Restoration saved the constrained width instead of the original preference")
local framesAfterRecovery, dirtyAfterRecovery = #f.frames, dirty
for _=1,10 do d.RequestRefresh() end
f.Flush()
assert(#f.frames == framesAfterRecovery and dirty == dirtyAfterRecovery, "Unchanged appearance rebuilt the Viewer")
-- A preview border must never cover its image with a window background.
local preview=f.Frame();a.Tag(preview,"windows.options")
local previewBorder=a.RegisterVisual(preview,{kind="border"})
assert(previewBorder.currentState.root.skinOptions.lean==true)
-- Use Daylight's dedicated X while the original AWP button owns the click.
local close = f.Frame(preview)
local label, background = f.Frame(close), f.Frame(close)
local clicks = 0
close:SetScript("OnClick", function() clicks = clicks + 1 end)
local closeVisual = a.RegisterVisual(close, {kind="close", regions={background}, text=label})
local closeWidget = closeVisual.currentState.widget
assert(closeWidget.isDaylightClose and not closeWidget:IsMouseEnabled())
assert(label:GetAlpha() == 0 and background:GetAlpha() == 0)
close:GetScript("OnEnter")(close)
assert(closeWidget.hovered)
close:GetScript("OnClick")(close)
close:GetScript("PostClick")(close)
close:GetScript("OnLeave")(close)
assert(clicks == 1 and closeWidget.playedClick and not closeWidget.hovered)
d.SetSetting("windows.options", "shell", false); f.Flush()
assert(not closeWidget:IsShown() and label:GetAlpha() == 1 and background:GetAlpha() == 1)
d.SetSetting("windows.options", "shell", true); f.Flush()
assert(closeVisual.currentState.widget == closeWidget and closeWidget:IsShown() and label:GetAlpha() == 0)
-- Queue footer buttons have native three-piece artwork in addition to the highlight.
local queueUI = { ui = {} }
AzerothWaypointNS.Internal.QueueUI = queueUI
assert(loadfile("interface/queue/widgets.lua"))()
local button = f.Frame()
button:SetSize(72, 24)
local left, middle, right, highlight, text = f.Frame(button), f.Frame(button), f.Frame(button), f.Frame(button), f.Frame(button)
text.objectType = "FontString"
text:SetText("Export All")
highlight:SetAlpha(0.6)
function button:GetRegions() return left, middle, right, highlight, text end
function button:GetFontString() return text end
queueUI.StyleQueueButton(button)
local styled = a.visuals[button].currentState.widget
assert(styled:IsShown() and text:GetAlpha() == 1)
assert(left:GetAlpha() == 0 and middle:GetAlpha() == 0 and right:GetAlpha() == 0 and highlight:GetAlpha() == 0)
button:Disable()
button:GetScript("OnDisable")(button)
assert(styled.off and middle:GetAlpha() == 0)
d.SetSetting("windows.queue", "shell", false); f.Flush()
assert(not styled:IsShown() and text:GetAlpha() == 1 and not button:IsEnabled())
assert(left:GetAlpha() == 1 and middle:GetAlpha() == 1 and right:GetAlpha() == 1 and highlight:GetAlpha() == 0.6)
-- Retail never applies Daylight, even with saved switches and the global present.
f.flavor="retail"
f.Emit("StyleChanged");f.Flush()
assert(not d.GetAPI())
print("Daylight appearance: defaults, shared controls, independent colors, baseline restoration, coalescing and combat passed")
