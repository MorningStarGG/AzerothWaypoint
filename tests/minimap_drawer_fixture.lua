local f=assert(loadfile("tests/daylight_fixture.lua"))()
local NS=AzerothWaypointNS
local now=100
GetTime=function() return now end
NS.State={}
local strip=f.Frame(UIParent)
local cell=f.Frame(strip)
local owner=f.Frame(cell)
local drawer={strip=strip,on=true,open=true,lastOver=now,watchCalls=0}
function drawer.Watch()
    drawer.watchCalls=drawer.watchCalls+1
    if drawer.on and drawer.open and GetTime()-drawer.lastOver>=1 then drawer.open=false end
end
local module={enabled=true,ns={Drawer=drawer}}
local replaceMethod=dofile("tests/replace_method.lua")
replaceMethod(DaylightUI,"GetModule",function(_,name) if name=="InfoPanel" then return module end end)
assert(loadfile("integrations/minimap_menu.lua"))()
local function Description()
    local d={acquired={},released={}}
    function d:AddMenuAcquiredCallback(fn) self.acquired[#self.acquired+1]=fn end
    function d:AddMenuReleasedCallback(fn) self.released[#self.released+1]=fn end
    function d:Acquire(menu) for _,fn in ipairs(self.acquired) do fn(menu) end end
    function d:Release(menu) for _,fn in ipairs(self.released) do fn(menu) end end
    return d
end
local function Menu(ownerFrame) return {GetOwnerRegion=function() return ownerFrame end} end
return {f=f,NS=NS,drawer=drawer,module=module,owner=owner,Description=Description,Menu=Menu,
    Time=function(value) now=value end,Hold=function(d,button) NS.Internal.MinimapMenus.HoldDrawer(d,button or owner) end}
