local NativePath=dofile("tests/native_path.lua")
local x=assert(loadfile("tests/minimap_drawer_fixture.lua"))()
local dui=DaylightUI
dui.Style={ICON_CROP={0,1,0,1}}
dui.Motion={Tween=function(_,_,to,_,update) update(to) end}
dui.Widgets={}
local ns={Panel={mapArea={IsMouseOver=function() return false end}}}
assert(loadfile(NativePath("forever","DaylightUI_InfoPanel/Drawer.lua")))("DaylightUI_InfoPanel",ns)
local drawer=ns.Drawer
x.module.ns=ns
drawer.on,drawer.open,drawer.lastOver=true,true,100
drawer.strip=x.owner:GetParent():GetParent()
drawer.glyph=x.f.Frame()
drawer.glyph.IsMouseOver=function() return false end
drawer.glyph.goal,drawer.glyph.dots=1,{}
-- Keep native collection's observation baseline equal; no UI creation is needed.
local function Upvalue(fn,name,value)
    for i=1,100 do
        local key,old=debug.getupvalue(fn,i);if not key then break end
        if key==name then debug.setupvalue(fn,i,value);return old end
    end
    error("Native drawer contract changed: "..name)
end
Upvalue(drawer.Watch,"changed",function() return false end)
local closes=0
local replaceMethod=dofile("tests/replace_method.lua")
replaceMethod(drawer,"Close",function() closes=closes+1;drawer.open=false end)
local d=x.Description();local root=x.Menu(x.owner);local submenu=x.Menu(x.f.Frame())
x.Hold(d);d:Acquire(root)
x.Time(105);drawer.Watch()
assert(drawer.open and closes==0,"Installed native drawer closed over AWP's root menu")
d:Acquire(submenu);d:Release(submenu)
x.Time(110);drawer.Watch();assert(drawer.open and x.f.hooks==1)
d:Release(root);assert(x.f.hooks==0)
x.Time(110.5);drawer.Watch();assert(drawer.open)
x.Time(111.1);drawer.Watch()
assert(not drawer.open and closes==1,"Installed native drawer did not resume its normal timeout")
print("Installed Daylight drawer watcher retains AWP menus/submenus and resumes native dismissal without new timers")
