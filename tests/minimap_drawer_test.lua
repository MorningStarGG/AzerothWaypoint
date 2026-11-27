local x=assert(loadfile("tests/minimap_drawer_fixture.lua"))()
local d=x.Description()
local root,child=x.Menu(x.owner),x.Menu(x.f.Frame())
x.Hold(d)
assert(x.f.hooks==0,"Drawer wrapped before the menu opened")
d:Acquire(root)
assert(x.f.hooks==1)
x.Time(105);x.drawer.Watch()
assert(x.drawer.open and x.drawer.lastOver==105 and x.drawer.watchCalls==1)
d:Acquire(child);d:Release(child)
assert(x.f.hooks==1,"Closing a submenu released the root menu hold")
x.Time(110);x.drawer.Watch();assert(x.drawer.open)
d:Release(root)
assert(x.f.hooks==0 and x.drawer.lastOver==110)
x.Time(110.5);x.drawer.Watch();assert(x.drawer.open)
x.Time(111.1);x.drawer.Watch();assert(not x.drawer.open,"Normal timeout did not resume after menu dismissal")
-- Selection, Escape, outside click and menu replacement all release the root.
for _,reason in ipairs({"selection","escape","outside","replacement"}) do
    x.drawer.open=true
    local menu=x.Menu(x.owner);local description=x.Description()
    x.Hold(description);description:Acquire(menu);description:Release(menu)
    assert(x.f.hooks==0,"Menu dismissal leaked the drawer wrapper: "..reason)
end
x.drawer.open=true
local manual=x.Description();local menu=x.Menu(x.owner)
x.Hold(manual);manual:Acquire(menu)
local last=x.drawer.lastOver
x.drawer.open=false;x.Time(120);x.drawer.Watch()
assert(not x.drawer.open and x.drawer.lastOver==last,"Manual drawer closure was overridden")
manual:Release(menu);assert(x.f.hooks==0)
x.drawer.open=true
local disabled=x.Description();menu=x.Menu(x.owner)
x.Hold(disabled);disabled:Acquire(menu)
x.drawer.on=false;x.Time(130);x.drawer.Watch()
assert(x.drawer.lastOver==last,"Disabled drawer kept receiving a hold")
disabled:Release(menu);assert(x.f.hooks==0)
x.drawer.on=true
for _,button in ipairs({UIParent,x.f.Frame(UIParent)}) do
    local foreign=x.Description();x.Hold(foreign,button)
    foreign:Acquire(x.Menu(button));assert(x.f.hooks==0,"Another container acquired a Daylight drawer hold")
end
x.module.enabled=false
local unavailable=x.Description();x.Hold(unavailable);unavailable:Acquire(x.Menu(x.owner));assert(x.f.hooks==0)
x.NS.Internal.MinimapMenus.HoldDrawer({},x.owner) -- Missing menu callbacks are unsupported, not an error.
print("Scoped drawer hold: root/submenus, dismissal, normal linger, manual close, disable and foreign owners passed")
