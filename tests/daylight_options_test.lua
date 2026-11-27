local NativePath = dofile("tests/native_path.lua")
local f=assert(loadfile("tests/daylight_fixture.lua"))()
assert(loadfile("core/core.lua"))()
assert(loadfile("interface/appearance/controller.lua"))()
assert(loadfile("interface/appearance/visuals.lua"))()
assert(loadfile("interface/appearance/provider.lua"))()
assert(loadfile("interface/appearance/providers/daylight.lua"))()
f.Fire("PLAYER_LOGIN");f.Flush()
local NS=AzerothWaypointNS
local d=NS.Internal.Daylight
local pages=f.settingsModule.options.pages
assert(#pages==4)
local expectedTabs={viewers=7,overlay=4,windows=5}
local bySurface={}
local expectedRows=0
local settingsButton
for _,page in ipairs(pages)do
 local tabs={}
 for _,group in ipairs(page.groups)do
  if group.surface then
   assert(type(group.tab)=="string" and #group.tab<=16 and group.label~=group.surfaceLabel)
   tabs[group.tab]=true
   bySurface[group.surface]=bySurface[group.surface] or {}
   bySurface[group.surface][group.label]=group
  end
  for _,item in ipairs(group.items)do
   if item.type == "button" and page.id == "main" then
    assert(page.id == "main" and not settingsButton and item.text == "Open AWP Settings")
    settingsButton = item
   elseif item.type == "button" then
    assert(page.id=="viewers" and type(item.func)=="function")
    expectedRows=expectedRows+1
   else
    expectedRows=expectedRows+1
    assert(type(item.get)=="function" and type(item.set)=="function" and type(item.default)=="function")
    local value=item.default() -- Includes false defaults; these must not become nil.
    assert(value~=nil)
   end
  end
 end
 if expectedTabs[page.id] then
  local n=0;for _ in pairs(tabs)do n=n+1 end
  assert(n==expectedTabs[page.id],"Missing native provider/surface tabs")
 end
end
assert(settingsButton)
local showing, opened, toggles = true, 0, 0
DaylightUI.OptionsPanel = {
    IsShown = function() return showing end,
    Toggle = function() toggles = toggles + 1; showing = not showing end,
}
NS.OpenOptionsPanel = function() assert(not showing); opened = opened + 1 end
settingsButton.func()
settingsButton.func()
assert(opened == 2 and toggles == 1, "Shortcut must close a visible host before opening AWP")
for surface,cards in pairs(bySurface)do
 local seen={}
 for _,card in pairs(cards)do
  for i,item in ipairs(card.items)do
   if item.type~="button" then
   assert(not seen[item._awpSetting],"Setting appears in more than one card: "..surface.." "..item._awpSetting)
   seen[item._awpSetting]=true
   if item._awpSetting=="fontKey" then
    assert(card.items[i-1]._awpSetting=="fonts" and card.items[i-1].label=="Apply selected font")
    assert(item.desc:find("Apply selected font",1,true))
   elseif item._awpSetting=="progressWidth" then assert(card.items[i-1]._awpSetting=="ownProgressWidth")end
   if item.disabled then assert(type(item.desc)=="string" and item.desc~="")end
   end
  end
 end
 assert(seen.enabled and seen.fonts and seen.fontKey and seen.colorSource)
 assert(seen.colors == (not surface:find("guide.",1,true) and true or nil))
 for _,key in ipairs{"background","border","bevel","ownOpacity","opacity","ownBorderWidth","borderWidth"}do
  assert(not seen[key],"Removed shell control is still exposed: "..surface.." "..key)
 end
 if surface:find("guide.",1,true)==1 then
  assert(cards.Header and cards["Buttons and progress"] and not cards.Panel)
  assert(#cards.Header.items==3 and cards.Header.items[1]._awpSetting=="header")
 else assert(not cards.Header and not cards["Buttons and progress"])end
 if cards.Panel then assert(#cards.Panel.items==1 and cards.Panel.items[1]._awpSetting=="shell")end
end
local z=bySurface["guide.zygor"].Font.items
local other=d.GetSettings("guide.dugi").fonts
assert(z[1].set(false));assert(z[2].disabled())
assert(z[1].set(true));assert(not z[2].disabled())
assert(d.GetSettings("guide.dugi").fonts==other,"Provider settings crossed tabs")
assert(z[2].set("example"));assert(z[2].get()=="example")
local fresh=d.GetOptionGroups()
local found=false
for _,g in ipairs(fresh)do
 if g.surface=="guide.zygor" and g.label=="Font"then
  assert(g.items[2].get()=="example" and not g.items[2].disabled());found=true
 end
end
assert(found,"AWP groups did not share the native page's saved values")
-- The AWP canvas consumes the same card/row definitions in the same order.
local labels={}
local function record(label)labels[#labels+1]=label end
NS.Internal.Interface=NS.Internal.Interface or {}
NS.Internal.Interface.canvas={Widgets={SectionHeader=function()end,Spacer=function()end,AddText=function()end,
 AddToggle=record,AddSlider=record,AddDropdown=record,AddColorRow=record, AddActionButton=function(label) record(label);return f.Frame() end,
 GetScrollChild=function()return UIParent end, GetCursorY=function()return 0 end, SetCursorY=function()end}}
assert(loadfile("interface/options/canvas_data.lua"))()
assert(loadfile("interface/options/canvas_sections.lua"))()
local canvas = NS.Internal.Interface.canvas
NS.GetGuideTargetProvider = function() end
local _, sections = canvas.Data.BuildSections()
local expected, rowCount = {}, 0
for _, group in ipairs(fresh) do
 local key = group.surface or "overview"
 expected[key] = expected[key] or {}
 for _, item in ipairs(group.items) do expected[key][#expected[key] + 1] = item.label end
end
canvas.RenderAppearanceSection(sections.daylight)
assert(#labels == 1 and labels[1] == expected.overview[1])
rowCount = #labels
for _, key in ipairs({ "daylight.viewers", "daylight.overlay", "daylight.windows" }) do
 local section = sections[key]
 for _, choice in ipairs(section.choices) do
  labels = {}
  canvas.RenderAppearanceSection(section, choice.value)
  local rows = expected[choice.value]
  assert(labels[1] == section.picker and #labels == #rows + 1)
  for index, label in ipairs(rows) do assert(labels[index + 1] == label) end
  rowCount = rowCount + #rows
 end
end
assert(rowCount == expectedRows, "AWP and Daylight expose different row sets")
-- Validate against installed native code without including it in AWP.
local path=NativePath("forever", "DaylightUI/Options/Registry.lua")
local h=io.open(path)
if h then
 local source=h:read("*a");h:close()
 local at=assert(source:find('Options.RegisterSection("core"',1,true))
 local dui=DaylightUI
 dui.L=setmetatable({},{__index=function(_,key)return key end})
 dui.On=function()end;dui.Fire=function()end;dui.DB={GENERAL_DEFAULTS={}}
 assert(loadstring(source:sub(1,at-1)))("DaylightUI",dui)
 for _,page in ipairs(pages)do
  local errors=dui.Options.ValidatePage(page)
  assert(#errors==0,table.concat(errors,"\n"))
 end
 assert(z[1].set(false));assert(dui.Options.IsDisabled({},z[2]))
 assert(z[1].set(true));assert(not dui.Options.IsDisabled({},z[2]))
 print("Installed Daylight page validation and font dependency passed")
end
f.Flush()
print("Daylight options: provider tabs, compact cards, adjacent dependencies, defaults and shared canvas rows passed")
