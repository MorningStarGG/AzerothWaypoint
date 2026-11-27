local NativePath = dofile("tests/native_path.lua")
-- Load the installed Daylight slider visuals against mocked game widgets.
return function()
    local widgets={KNOB=12,KNOB_BIG=14,SLIDER_BOX=60}
    local dui={Motion={FAST=0.1,Tween=function(_,_,to,_,fn) if fn then fn(to) end end}}
    function widgets.Tint(texture,c) texture:SetVertexColor(unpack(c)) end
    function widgets.TintDaylight(texture) texture.gradient="daylight-options" end
    local env=setmetatable({W=widgets,DUI=dui,MEDIA="Daylight/",C={track={0.17,0.17,0.19,1}}},{__index=_G})
    local file=assert(io.open(NativePath("forever", "DaylightUI/Options/Widgets.lua")))
    local text=file:read("*a");file:close()
    local start=assert(text:find("function W.SliderLook",1,true))
    local finish=assert(text:find("function W.Slider(parent, spec)",start,true))
    local chunk=assert(loadstring(text:sub(start,finish-1)))
    setfenv(chunk,env);chunk()
    return widgets
end
