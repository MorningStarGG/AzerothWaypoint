-- Use the production backend's action format, then the actual button renderer.
local f=assert(loadfile("tests/polestar_integration_test.lua"))()
local providerNS,r,backend=AzerothWaypointNS,f.runtime,f.backend
f.settings["nav.navRouting"]=false
r.Nav.PlanRoute=function(context)
    return {{kind="hearth",item=6948,from={map=1,c=1,wx=0,wy=0},to=context.target,
        label="Hearth to Bloodhoof Village: saves 4 min"}}
end
backend.PlanRoute(providerNS.record,1,.7,.8,"Destination")
local hearth=assert(providerNS.record.legs[1].specialAction)
assert(hearth.securePayload=="item:6948" and hearth.itemID==6948)
assert(loadfile("tests/equipment_action_test.lua"))()
local NS=AzerothWaypointNS
local function Upvalue(fn,name,seen)
    seen=seen or {};if type(fn)~="function" or seen[fn] then return end;seen[fn]=true
    for i=1,100 do
        local key,value=debug.getupvalue(fn,i);if not key then break end
        if key==name then return value end
        local found=Upvalue(value,name,seen);if found then return found end
    end
end
local icon=assert(Upvalue(NS.SpecialActionShowActive,"secureButtonIcon"))
local replaceMethod=dofile("tests/replace_method.lua")
replaceMethod(icon,"SetTexture",function(_,texture) icon.texture,icon.atlas=texture,nil end)
replaceMethod(icon,"SetAtlas",function(_,atlas) icon.atlas=atlas end)
local query,spellQuery,queries,ready,fail=nil,nil,0,true,false
replaceMethod(C_Item,"GetItemIconByID",function(item)
    query=item;queries=queries+1
    if fail then error("item data temporarily unavailable") end
    if ready and (item==6948 or item=="6948" or item=="item:6948" or item=="Localized Hearthstone"
        or item=="|Hitem:6948::::::::|h[Hearthstone]|h") then return 134414 end
end)
C_Spell={GetSpellTexture=function(spell)
    spellQuery=spell
    if spell==556 or spell=="Localized Recall" then return 136010 end
end}
NS.State.routing.specialActionState=hearth
NS.ApplySpecialAction(hearth)
assert(icon.texture==134414 and query==6948,"Actual Polestar Hearthstone action lost its item icon")
local button=NS.GetSpecialActionButton()
assert(button.attributes.type=="item" and button.attributes.item=="item:6948","Icon resolution changed secure execution")
local function Show(action,expected,atlas)
    NS.State.routing.specialActionState=action
    NS.SpecialActionShowActive(action)
    assert((atlas and icon.atlas or icon.texture)==expected,"Wrong travel icon: "..tostring(action.securePayload))
end
for _,payload in ipairs({6948,"6948","item:6948","Localized Hearthstone","|Hitem:6948::::::::|h[Hearthstone]|h"}) do
    Show({secureType="item",securePayload=payload},134414)
end
Show({secureType="toy",securePayload="item:6948"},134414)
Show({executionType="equip",itemID=6948},134414)
Show({secureType="spell",securePayload="Unresolved localized name",spellID=556},136010)
assert(spellQuery==556,"Explicit spell identity was ignored")
Show({secureType="spell",securePayload="Localized Recall"},136010)
local before=queries
Show({iconTexture=134414},134414)
Show({iconTexture="Interface\\Icons\\INV_Misc_Rune_01"},"Interface\\Icons\\INV_Misc_Rune_01")
Show({iconTexture="poi-door-arrow"},"poi-door-arrow",true)
assert(queries==before,"Explicit artwork queried an unrelated item")
local unknown="Interface\\Icons\\INV_Misc_QuestionMark"
for _,bad in ipairs({0,-1,0/0,math.huge,1.5}) do Show({iconTexture=bad},unknown) end
Show({secureType="macro",securePayload="/use item:6948"},unknown) -- Never parse executable macros for presentation.
ready=false;Show(hearth,unknown)
ready=true;NS.RefreshSpecialActionButtonPresentation();assert(icon.texture==134414,"Missing artwork was cached permanently")
fail=true;Show(hearth,unknown)
fail=false;Show(hearth,134414)
assert(hearth.securePayload=="item:6948" and hearth.itemID==6948)
print("Travel icons: backend-produced Hearthstone, IDs/strings/links/toys/spells, numeric/path/atlas artwork, late data and secure payload preservation passed")
