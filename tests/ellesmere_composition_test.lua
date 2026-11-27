local NativePath = dofile("tests/native_path.lua")
local context=assert(loadfile("tests/ellesmere_appearance_test.lua"))()
local f,ui,a,e,skin=context.f,context.ui,context.a,context.e,context.skin
f.prebuild=false;f.flavor="forever"

-- Exercise the installed constructor rather than merely marking a fake button
-- as skinned. Its body must be handed to MakeRoundedBorder for clipping.
local handle=io.open(NativePath("forever", "EllesmereUI/EllesmereUI_UICore.lua"))
assert(handle,"Installed Ellesmere source required for this contract test")
local source=handle:read("*a");handle:close()
local first=assert(source:find("local function MakeStyledButton",1,true))
local last=assert(source:find("local WB_COLOURS",first,true))
local chunk=assert(loadstring(source:sub(first,last-1).."\nreturn MakeStyledButton"))
ui.L=function(text)return text end
setfenv(chunk,setmetatable({EllesmereUI=ui,
    SolidTex=function(parent,_,r,g,b,alpha)local tex=f.Frame(parent);tex:SetColorTexture(r,g,b,alpha);return tex end,
    MakeFont=function(parent)return f.Frame(parent)end,
},{__index=_G}))
ui.MakeStyledButton=chunk()
context.change("eui",false)

local root=f.Frame();root:SetSize(226,400);a.Tag(root,"windows.options")
local function make(kind,width,height)
    local frame=f.Frame(root);frame:SetSize(width or 226,height or 24)
    local old=f.Frame(frame);old:SetAlpha(0.7)
    local record=a.RegisterVisual(frame,{kind=kind,regions={old}})
    assert(record.applied,e.lastError)
    return frame,record,old
end
local button,buttonRecord=make("button",100,24)
local buttonState=buttonRecord.currentState
assert(buttonState.widget and buttonState.emptyLabel,"A window shell was substituted for the native button")
assert(buttonState.fill.masks and #buttonState.fill.masks>0,"Native button body was not clipped")
assert(not buttonState.widget.nativeShell and not buttonState.widget.nativeInput)
button:GetScript("OnEnter")(button)
assert(buttonState.fill.colorTexture[1]==ui.WB_COLOURS[5],"Native hover recipe was not forwarded")
button.enabled=false;button:GetScript("OnDisable")(button)
assert(not buttonRecord.hovered and not buttonRecord.pressed)
button.enabled=true;button:GetScript("OnEnable")(button)

local dropdown,dropdownRecord=make("dropdown")
local dropdownState=dropdownRecord.currentState
assert(dropdownState.arrow and dropdownState.fill and dropdownState.fill.masks)
assert(not dropdownState.input and not dropdownState.widget and not dropdownState.root.nativeInput,
    "Dropdown still layers an EditBox skin beneath a panel")
local calls=0
dropdown:SetScript("OnClick",function()calls=calls+1 end)
dropdown:GetScript("OnClick")(dropdown);assert(calls==1)

local plaque=f.Frame(root);a.Tag(plaque,"plaque");plaque:SetSize(370,72)
local plaqueArt=f.Frame(plaque);plaqueArt:SetAlpha(0.8)
a.Shell(plaque,"plaque",{plaqueArt})
context.change("forever",false)
local plaqueRecord=a.visuals[plaque]
local state=plaqueRecord.currentState
assert(not state.root.backdrop,"Rectangular backdrop remains behind the Forever corners")
assert(state.mask and state.fill.masks[1]==state.mask)
assert(state.mask.textureFile:find("AzerothWaypoint",1,true) and not state.mask.textureFile:find("AddonSkins",1,true))
assert(state.mask.sliceMode==Enum.UITextureSliceMode.Stretched and state.mask.slices[1]==9)
assert(dropdownRecord.currentState.mask and not dropdownRecord.currentState.root.nativeInput)

local maskFile=assert(io.open("media/interface/chamfer-mask.tga","rb"))
local bytes=maskFile:read("*a");maskFile:close()
assert(bytes:byte(3)==2 and bytes:byte(17)==32 and bytes:byte(18)==0x28)
local width,height=bytes:byte(13)+256*bytes:byte(14),bytes:byte(15)+256*bytes:byte(16)
assert(width==32 and height==32 and #bytes==18+width*height*4)
local function alpha(x,y)return bytes:byte(18+(y*width+x)*4+4)end
for y=0,height-1 do for x=0,width-1 do
    local inside=math.min(x,width-1-x)+math.min(y,height-1-y)>=5
    assert(alpha(x,y)==(inside and 255 or 0),"Chamfer alpha spills beyond the declared shape")
end end

-- The same fill supplies normal, hover, pressed and disabled states. Resizing
-- never installs an unmasked replacement or accumulates masks and layers.
local frameCount=#f.frames
for _,size in ipairs({{100,24},{226,24},{370,72},{600,120},{20,20}})do
    plaque:SetSize(size[1],size[2]);a.UpdateVisual(plaque)
    assert(plaqueRecord.currentState==state and state.mask.allPoints==state.root)
    assert(#state.fill.masks==1 and #f.frames==frameCount)
end
dropdown:GetScript("OnEnter")(dropdown);dropdown:GetScript("OnMouseDown")(dropdown)
assert(dropdownRecord.currentState.mask==dropdownRecord.currentState.fill.masks[1])
dropdown.enabled=false;dropdown:GetScript("OnDisable")(dropdown)
assert(dropdownRecord.currentState.root:GetAlpha()==0.4 and not dropdownRecord.hovered)
dropdown.enabled=true;dropdown:GetScript("OnEnable")(dropdown)

local reads=0
local getFont=ui.GetFontPath
ui.GetFontPath=function(...)reads=reads+1;return getFont(...)end
local applied=e.counters.applied
collectgarbage("collect");collectgarbage("stop")
local memory=collectgarbage("count")
for _=1,2000 do a.UpdateVisual(plaque);a.UpdateVisual(dropdown)end
local allocated=collectgarbage("count")-memory
collectgarbage("restart")
assert(reads==0 and #f.frames==frameCount and e.counters.applied==applied)
assert(allocated<8,"Unchanged visual updates allocate: "..allocated.." KB")
ui.GetFontPath=getFont

-- A runtime rendering error restores every surface, not a partially skinned UI.
local border=ui.MakeRoundedBorder
ui.MakeRoundedBorder=function()error("fixture: unavailable rounded border")end
local _,failure,old=make("artwork") -- Does not require a border.
local bad=f.Frame(root);local badArt=f.Frame(bad)
context.change("eui",false)
a.RegisterVisual(bad,{kind="input",regions={badArt}})
assert(e.lastError and not e.IsEnabled("windows.options"))
assert(not plaqueRecord.applied and plaqueArt:GetAlpha()==0.8)
ui.MakeRoundedBorder=border;e.RequestRefresh();f.Flush()
assert(not e.lastError and plaqueRecord.applied)
a.Select("awp");f.Flush()
assert(plaqueArt:GetAlpha()==0.8 and not plaqueRecord.holder:IsShown())
print("Ellesmere composition: installed button recipe, typed dropdown, complete chamfer coverage, resizing, bounded updates and failure restoration passed")
