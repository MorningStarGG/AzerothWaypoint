local f=assert(loadfile("tests/controller_fixture.lua"))()
local Pad=f.Pad
local root=CreateFrame("Frame","HintGuide",UIParent);root:Hide();root:SetSize(180,100)
root.MarkDirty=function(self) self.dirty=(self.dirty or 0)+1 end
Pad.RegisterWindow(root,{manual=true,tracker=true})
local row=CreateFrame("Button",nil,root);Pad.RegisterControl(row,{id="row",more=function() end})
root:Show();f.Flush();Pad.Enter(root);Pad.Select(row,root);Pad.Observe()
root.gamepadFooter={inputLegend={IsVisible=function() return true end}}
Pad.contextLabel="Use a quest item with a deliberately long localized name"
CreateFrame("Button","HintContextAction",UIParent)
Pad.contextButton="HintContextAction";Pad.RefreshBindings()
local text=Pad.hint.text:GetText()
assert(text:find("More actions",1,true) and not text:find(" Select",1,true) and not text:find(" Back",1,true))
local extra=root._awpControllerHintHeight
assert(extra>20 and Pad.hint:GetHeight()==extra,"long hints were not measured")
assert(Pad.ReserveHintSpace(root,100)==100+extra)
Pad.BeginHintLayout(root);assert(root:GetHeight()==100)
assert(Pad.ReserveHintSpace(root,100)==100+extra,"hint space accumulated across layouts")
root:SetWidth(360);Pad.Request(root);f.Flush();assert(root._awpControllerHintHeight<extra)
assert(Pad.hint.point[1]=="BOTTOM" and Pad.hint.point[2]==root and Pad.hint.point[3]=="BOTTOM")
Pad.ClearFocus();assert(root._awpControllerHintHeight==0 and not Pad.hint:IsShown())
print("Controller hints: native deduplication, action labels, reserved height, wrapping and resize passed")
