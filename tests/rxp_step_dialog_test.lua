local fixture=assert(loadfile("tests/rxp_viewer_test.lua"))()
local NS=AzerothWaypointNS
local API=NS.Internal.RXPProvider
local function expect(v,m) if not v then error(m,2) end end
local popup,lastMessage,lastRequest
NS.Msg=function(text) lastMessage=text end
_G.StaticPopup_Show=function(name,_,_,data)
    local edit={text="",SetNumeric=function() end,HighlightText=function() end,SetFocus=function() end,
        SetText=function(self,text) self.text=text end,GetText=function(self) return self.text end}
    popup={name=name,data=data,hidden=false,GetEditBox=function() return edit end,Hide=function(self) self.hidden=true end}
    edit.GetParent=function() return popup end
    StaticPopupDialogs[name].OnShow(popup,data)
    return popup
end
local nativeRun=API.RunAction
API.RunAction=function(action,guide,current,index,epoch)
    if action=="previous" then return false,"choose_step",2 end
    lastRequest={action,guide,current,index,epoch}
    return nativeRun(action,guide,current,index,epoch)
end
fixture.controls.onPrevious()
expect(popup and popup.name=="AWP_RXP_GO_TO_STEP" and popup:GetEditBox():GetText()=="2",
    "Back without recovery did not open explicit selection")
local definition=StaticPopupDialogs[popup.name]
popup:GetEditBox():SetText("0")
expect(definition.OnAccept(popup,popup.data)==true and not popup.hidden and lastMessage:find("whole step",1,true),
    "Invalid input was not retained with a useful message")
popup:GetEditBox():SetText("2")
definition.EditBoxOnEnterPressed(popup:GetEditBox())
expect(popup.hidden and lastRequest[1]=="goto" and lastRequest[2]==popup.data.guide
    and lastRequest[3]==popup.data.current and lastRequest[4]==2 and lastRequest[5]==popup.data.epoch,
    "Go to Step lost its guide/current/generation context")
fixture.controls.onPrevious()
fixture.source.messages.RXP_GUIDE_LOADED()
popup:GetEditBox():SetText("2")
definition.OnAccept(popup,popup.data)
expect(lastMessage:find("changed",1,true),"Same-guide reload did not reject the old dialog")
fixture.drain()
fixture.controls.onPrevious()
local combat = true
_G.InCombatLockdown = function() return combat end
definition.OnAccept(popup,popup.data)
expect(lastMessage:find("combat",1,true),"Open dialog executed a combat step action")
combat = false
local entries={}
local root={CreateTitle=function() end,CreateDivider=function() end,CreateRadio=function() end,SetEnabled=function() end}
function root:CreateButton(label,callback) entries[label]=callback;return self end
_G.MenuUtil={CreateContextMenu=function(_,build) build({},root) end}
fixture.controls.onMenu({})
expect(type(entries["Go to Step..."])=="function","Action menu lacks explicit step selection")
entries["Go to Step..."]()
expect(tonumber(popup:GetEditBox():GetText())==API.GetSnapshot().current,"Menu selection did not start from the displayed step")
entries={};fixture.frame:OnBlockHeaderClick({},"LeftButton")
expect(type(entries["Go to Step..."])=="function","Guide-title menu lacks step selection")
API.RunAction=nativeRun
print("RXP Back fallback, Go to Step dialog, validation, reload/combat guards and both menus passed")
