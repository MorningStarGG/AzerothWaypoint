local fixture=assert(loadfile("tests/rxp_viewer_test.lua"))()
local NS=AzerothWaypointNS
local common,API=NS.Internal.GuideTrackerViewer,NS.Internal.RXPProvider
assert(loadfile("integrations/guides/viewer_actions.lua"))()
local runtime=fixture.runtime
local catalog={}
runtime.GetGuideTable=function(id)return catalog[id]end
runtime.GetGuideProgress=function()return 1 end
runtime.GetGuideName=function(guide)return guide.name end
runtime.LoadGuide=function(self,guide)self.currentGuide=guide;API.Schedule("RXP_GUIDE_LOADED")end
runtime.settings.profile.showEnabled=true;runtime.isHidden=false
runtime.v2=nil;runtime.arrowFrame.element=nil;runtime.activeWaypoints={}
local function load(index,passive)
    local name="Guide "..index
    local step={index=1,active=true,elements={{text="Instruction",textOnly=true}}}
    local guide={group="Recent",name=name,steps={step}}
    local id="Recent||"..name;catalog[id]=guide
    runtime.RXPFrame.activeSteps={step}
    if passive then runtime.currentGuide=guide;API.Schedule("automatic_chapter")
    else assert(API.SwitchGuide(id))end
    fixture.drain();fixture.source.drain()
    return id
end
common.SetOpenGuides("rxp",{})
for index=1,7 do load(index)end
local saved=common.GetOpenGuides("rxp")
assert(#saved==6 and saved[1]=="Recent||Guide 2" and saved[6]=="Recent||Guide 7","Seventh guide did not evict the least recent identity")
local state=common.Tabs.GetState("rxp")
assert(state.entries[1].id=="Recent||Guide 7" and state.entries[6].id=="Recent||Guide 2","Menus were not newest first")
local stale=state.entries[2]
load(3)
saved=common.GetOpenGuides("rxp")
assert(#saved==6 and saved[6]=="Recent||Guide 3","Revisiting a guide did not update recency")
assert(not common.Tabs.Run("rxp","close",stale),"Reordered MRU list accepted a stale menu")
local stored=AzerothWaypointCharDB.guideTrackerViewerOpenGuides.rxp
for _=1,100 do API.Schedule("unchanged");fixture.drain();fixture.source.drain();common.Tabs.GetState("rxp")end
assert(AzerothWaypointCharDB.guideTrackerViewerOpenGuides.rxp==stored,"Unchanged refreshes rewrote guide history")
NS.SelectGuideProvider("dugi");load(8,true)
assert(NS.GetActiveGuideProvider()=="dugi" and common.GetOpenGuides("rxp")[6]=="Recent||Guide 8","Automatic chapter stole authority or was not remembered")
local function menu()
    local root={entries={},titles={}}
    function root:CreateButton(label,fn)local child=menu();child.callback=fn;self.entries[label]=child;return child end
    function root:CreateTitle(label)self.titles[label]=true end
    function root:CreateDivider()end
    function root:SetEnabled(value)self.enabled=value end
    function root:SetIsSelected(value)self.selected=value end
    return root
end
local root=menu();common.Tabs.AddMenu("rxp",root)
assert(root.entries["Guide 8"].entries["Switch to Guide"] and root.entries["Guide 8"].entries["Close Guide"]
    and root.entries["Close Current Guide"] and root.entries["Close All Guides"] and root.entries["Open New Guide..."],"Shared guide menu omitted operations")
local listed=common.Actions.GetOpenGuides("rxp")
assert(listed[1].label=="Guide 8" and #listed==6,"Commands and menus read different histories")
local opened=0;runtime.RXPFrame.DropDownMenu=function()opened=opened+1 end
assert(common.Tabs.OpenNew("rxp") and opened==1,"Recent-guide capacity incorrectly demanded a slot close")
local current=API.GetSnapshot().id
state=common.Tabs.GetState("rxp")
assert(common.Tabs.Run("rxp","close",state.entries[2]))
assert(API.GetSnapshot().id==current and #common.GetOpenGuides("rxp")==5,"Closing remembered guide unloaded the active guide")
assert(common.Tabs.Run("rxp","closeAll"));fixture.drain();fixture.source.drain()
assert(#common.GetOpenGuides("rxp")==0 and runtime.currentGuide.empty,"Close All did not use native empty-guide state")
common.SetOpenGuides("rxp",{"a","b","c","d","e","f","g","g"})
assert(#common.GetOpenGuides("rxp")==6 and common.GetOpenGuides("rxp")[1]=="b","Existing history was not normalized")
print("Shared RXP tabs: six-guide MRU, automatic chapters, stable writes, stale menus, commands and native close passed")
