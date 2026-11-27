local f = assert(loadfile("tests/controller_fixture.lua"))()
assert(loadfile("core/core.lua"))()
assert(loadfile("core/quest_data.lua"))()
assert(loadfile("core/quest_text.lua"))()
assert(loadfile("core/scheduling.lua"))()
local NS, Pad = f.NS, f.Pad
NS.GetDB = function() return f.db end
local settings = { enabled=false, inline=false, types={} }
NS.GetGuideActionSettings = function() return settings end
NS.GetGuideTrackerViewerProviderSettings = function() return {} end
NS.GetActiveGuideProvider = function() return "questierouter" end
NS.RefreshGuideTrackerViewerProvider = function() end
NS.GetGuideTrackerViewerOrder = function() return {"questierouter"} end
NS.GetGuideTrackerViewerProvider = function() return {moduleName="GuideModule"} end
NS.Internal.GuideTrackerViewer = {CreateNativeFrameCloak=function() return {Refresh=function() end} end}
assert(loadfile("integrations/guides/presentation.lua"))()
assert(loadfile("integrations/guides/quest_selection.lua"))()
assert(loadfile("integrations/guides/source_runtime.lua"))()
assert(loadfile("integrations/guides/guide_actions.lua"))()
assert(loadfile("integrations/guides/controller.lua"))()
assert(loadfile("interface/framework/panels.lua"))()
local A = NS.Internal.GuideTrackerViewer.GuideActions
local step, item, multiple = 1, 123, false
f.saved.PADLSTICK = "CLICK AWPControllerGuideAction:LeftButton"
A.Register("questierouter", {
    identity = function() return "guide", step end,
    frames = function() return {} end,
    collect = function()
        local b = A.CreateBuilder("questierouter", "guide", step)
        b:Emit("item", "items", item, "Use quest item", 111, "task1")
        if multiple then b:Emit("spell", "spells", 456, "Cast quest spell", 222, "task1") end
        return b:Finish()
    end,
})
A.Request("questierouter"); f.Flush()
local AWPControllerGuideAction = assert(rawget(_G, "AWPControllerGuideAction"))
local AWPControllerContextAction = assert(rawget(_G, "AWPControllerContextAction"))
assert(not Pad.controls[AWPControllerGuideAction] and not AWPControllerGuideAction:IsMouseEnabled(), "hidden executor became a navigation control")
assert(AWPControllerGuideAction:GetAttribute("item") == "item:123")
AWPControllerGuideAction:HardwareClick(); assert(f.used[#f.used].item == "item:123")
local root = CreateFrame("Frame", "GuideModule", UIParent)
Pad.RegisterWindow(root, {manual=true,guide="questierouter"})
local row = CreateFrame("Frame", nil, root)
row:SetScript("OnMouseUp", function(_, mouse) if mouse=="RightButton" then f.menu=true end end)
row.objectiveKey = 1
Pad.BindGuideRow(row, "questierouter", "other-task")
Pad.Enter(root); f.Flush(); Pad.Select(row); Pad.Observe()
assert(not Pad.contextButton, "focused future task borrowed active task's item")
Pad.BindGuideRow(row, "questierouter", "task1"); Pad.Observe()
assert(Pad.contextButton == "AWPControllerContextAction")
assert(AWPControllerContextAction:GetAttribute("item") == "item:123")
assert(rawget(_G,"AWPControllerMore")):HardwareClick(); assert(f.menu)
-- Crossing providers changes the contextual action/menu, not the active guide
-- or its optional global action. Exercise the actual shared action collector.
local tracker=CreateFrame("Frame","SharedTracker",UIParent)
root:SetParent(tracker);root.parentContainer=tracker;Pad.windows[root].tracker=true
row.x,row.y=100,200
local z=CreateFrame("Frame","ZygorActionsModule",tracker);z.parentContainer=tracker
Pad.RegisterWindow(z,{manual=true,guide="zygor",tracker=true})
local zrow=CreateFrame("Frame",nil,z);zrow.x,zrow.y=100,100
zrow:SetScript("OnMouseUp",function(_,mouse) if mouse=="RightButton" then f.menu="zygor" end end)
local talk=CreateFrame("Button",nil,UIParent)
talk:SetAttribute("type1","macro");talk:SetAttribute("macrotext","/targetexact Eylah Sunhorn")
talk:Hide()
local zBuilds=0
A.Register("zygor",{
    identity=function() return "zygor-guide",8 end,frames=function() return {} end,
    collect=function()
        zBuilds=zBuilds+1
        local builder=A.CreateBuilder("zygor","zygor-guide",8)
        builder:Emit("item","items",999,"Zygor quest item",111,8)
        builder:Emit("target","friendly","Eylah Sunhorn","Talk to Eylah Sunhorn",111,"talk-goal",talk)
        return builder:Finish()
    end,
})
Pad.BindGuideRow(zrow,"zygor",8)
A.Request("zygor");f.Flush()
Pad.Enter(z,zrow);Pad.Observe()
assert(Pad.focusRoot==z and AWPControllerContextAction:GetAttribute("item")=="item:999")
AWPControllerContextAction:HardwareClick();assert(f.used[#f.used].item=="item:999")
assert(rawget(_G,"AWPControllerMore")):HardwareClick();assert(f.menu=="zygor")
zrow.jumps[rawget(_G,"SMART_NAV_INPUT_DIRECTION").UP]();Pad.Observe()
assert(Pad.focusRoot==root and Pad.controls[Pad.focus].guide=="questierouter")
assert(AWPControllerContextAction:GetAttribute("item")=="item:123")
assert(NS.GetActiveGuideProvider()=="questierouter" and AWPControllerGuideAction:GetAttribute("item")=="item:123")
-- Source action notifications update the focused action. Native topology
-- refreshes must not collect or revalidate a guide as a side effect.
local talkRow=CreateFrame("Frame",nil,z)
talkRow:SetScript("OnMouseUp",function() end)
Pad.BindGuideRow(talkRow,"zygor","talk-goal")
Pad.Enter(z,talkRow);f.Flush();Pad.Observe()
assert(not Pad.contextButton)
local builds=zBuilds
for _=1,3 do
    talk:Show();A.Request("zygor");f.Flush()
    assert(Pad.contextLabel=="Talk to Eylah Sunhorn" and Pad.OwnsBinding("PADRSTICK","AWPControllerContextAction"))
    talk:Hide();A.Request("zygor");f.Flush()
    assert(not Pad.contextButton and not Pad.OwnsBinding("PADRSTICK","AWPControllerContextAction"))
end
assert(zBuilds==builds+6)
rawget(_G,"SmartNavigation"):RefreshButtonGroups(z);f.Flush()
assert(zBuilds==builds+6,"navigation refresh rebuilt the guide model")
local ordinary=CreateFrame("Frame",nil,z)
ordinary:SetScript("OnMouseUp",function() end)
Pad.BindGuideRow(ordinary,"zygor","ordinary-goal")
talk:Show();A.Request("zygor");f.Flush()
z.dirties=0;z.MarkDirty=function(self) self.dirties=self.dirties+1 end
Pad.Select(talkRow);f.Flush()
assert(Pad.contextLabel=="Talk to Eylah Sunhorn" and Pad.hint.text:GetText():find("Talk to Eylah Sunhorn",1,true))
local actionHeight,dirty=z._awpControllerHintHeight,z.dirties
Pad.Select(ordinary);f.Flush()
assert(not Pad.contextLabel and not Pad.OwnsBinding("PADRSTICK","AWPControllerContextAction"))
assert(not Pad.hint.text:GetText():find("Talk to Eylah Sunhorn",1,true) and Pad.hint:IsShown(),"ordinary row kept a stale interact prompt or hid its normal hints")
assert(z.dirties==dirty+(actionHeight~=z._awpControllerHintHeight and 1 or 0),"hint content change caused more than its necessary layout update")
Pad.Select(talkRow);f.Flush()
assert(Pad.contextLabel=="Talk to Eylah Sunhorn")
Pad.Enter(root,row);f.Flush();Pad.Observe()
local writes = AWPControllerGuideAction:GetAttribute("item")
f.Combat(true)
step, item = 2, 789
A.Request("questierouter"); f.Flush()
assert(AWPControllerGuideAction:GetAttribute("item") == writes and Pad.actionPending)
AWPControllerGuideAction:HardwareClick(); assert(f.used[#f.used].item == "item:123", "combat action was replaced")
assert(Pad.actionStatus.text:GetText():find("after combat",1,true))
f.Combat(false); f.Flush()
assert(AWPControllerGuideAction:GetAttribute("item") == "item:789" and not Pad.actionPending)
multiple = true; A.Request("questierouter"); f.Flush()
assert(not AWPControllerGuideAction:GetAttribute("type1"), "ambiguous action was guessed")
AWPControllerGuideAction:HardwareClick(); f.Flush()
local picker = assert(rawget(_G,"AWPControllerActionPicker"))
assert(picker:IsShown())
assert(#picker.standard == 2 and picker.standard[1]:GetAttribute("item") == "item:789")
picker.standard[2]:HardwareClick(); f.Flush()
assert(f.used[#f.used].spell == 456 and not picker:IsShown())
Pad.ReleaseGuideRow(row)
assert(not Pad.controls[row].guide and not Pad.controls[row].more, "pooled row retained old actions")
settings.types.items = false; settings.types.spells = false
A.Request("questierouter"); f.Flush(); assert(not AWPControllerGuideAction:GetAttribute("type1"))
f.saved.PADLSTICK = nil; Pad.RefreshGuideAction(); assert(not Pad.actionStatus:IsShown())
-- Upcoming rows have no item buttons, but keep their real task menu.
local Common=NS.Internal.GuideTrackerViewer
Common.Host={IsKTLoaded=function() return false end}
Common.Styles={GetProviderKey=function() return "questierouter" end,
    GetTrackerColorStyle=function() return {r=1,g=1,b=1} end}
Common.Controls={SetStepCheckbox=function() end}
assert(loadfile("integrations/guides/viewer_render.lua"))()
local block=CreateFrame("Frame",nil,root);block.parentModule=root
local later=CreateFrame("Button",nil,block);later.Text=later:CreateFontString();later.Dash=later:CreateTexture()
function block:AddObjective(_,text) later.Text:SetText(text);return later end
function block:GetExistingLine() return later end
local rendered=Common.Render.AddObjective(block,1,{text="Second quest",kind="goal",hideActions=true,ownerStepIndex=2,objectiveKey="second:goal"})
rendered:SetScript("OnMouseUp",function(_,button) if button=="RightButton" then f.menu="second task" end end)
assert(Pad.controls[rendered].more and Pad.controls[rendered].owner=="second:goal")
Pad.Enter(root,rendered);Pad.Observe();assert(rawget(_G,"AWPControllerMore")):HardwareClick();assert(f.menu=="second task")
assert(loadfile("integrations/guides/viewer_actions.lua"))()
Common.Actions.BindRowAction(rendered,{},nil,function() end)
Pad.InvalidateBindings();f.Flush()
assert(not Pad.OwnsBinding("PAD4","AWPControllerMore"),"left-click-only row advertised a menu")
Common.Actions.BindRowAction(rendered,{},function() f.menu="explicit task menu" end)
rendered:SetScript("OnMouseUp",function() end)
Pad.InvalidateBindings();f.Flush()
assert(f.PressKey("PAD4") and f.menu=="explicit task menu","More did not use the row's actual menu command")
Common.Render.ResetLineBindings(rendered)
assert(rendered._awpMoreMenu==nil,"pooled row retained its previous menu command")
-- A decorative heading/support line can reuse the same native row as an
-- actionable objective. Both our scan and Blizzard's focus contract exclude it.
for _, role in ipairs({"heading", "support"}) do
    Common.Render.AddObjective(block,1,{text="Reading context",kind="tip",role=role})
    Pad.Enter(root);f.Flush()
    assert(Pad.controls[rendered].visualOnly and not Pad.CanFocus(rendered) and not f.NativeCanFocus(rendered))
    assert(not Pad.controls[rendered].owner and not Pad.controls[rendered].more)
    assert(not rendered.Dash:IsShown(),"Decorative row retained an objective dash")
    Common.Render.AddObjective(block,1,{text="Quest goal",kind="goal",hideActions=true,ownerStepIndex=2,objectiveKey="second:goal"})
    rendered:SetScript("OnMouseUp",function() end)
    Pad.Enter(root,rendered);f.Flush()
    assert(not Pad.controls[rendered].visualOnly and Pad.CanFocus(rendered) and f.NativeCanFocus(rendered))
    assert(rendered.Dash:IsShown() and Pad.controls[rendered].owner=="second:goal")
end
print("Controller native action model, task ownership, secure execution, ambiguity, combat and later-task menus: passed")
