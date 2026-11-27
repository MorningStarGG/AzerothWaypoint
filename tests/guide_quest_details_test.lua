local host, combat, source = "blizzard", false, {}
local log = { [42] = 1, [43] = 2 }
local calls, messages = {}, {}
local function record(kind, id) calls[#calls + 1] = {kind, id} end
InCombatLockdown = function() return combat end
C_QuestLog = { GetLogIndexForQuestID = function(id) return log[id] end,
    GetTitleForQuestID = function(id) return "Quest " .. id end }
C_SuperTrack = { SetSuperTrackedQuestID = function() error("Viewing changed tracking") end }
QuestUtil = { OpenQuestDetails = function(id) record("blizzard", id) end }
AzerothWaypointNS = { Internal = { GuideTrackerViewer = { Host = { GetHostID = function() return host end } } },
    Msg = function(text) messages[#messages + 1] = text end }
assert(loadfile("integrations/guides/viewer_quest_details.lua"))()
local Q = AzerothWaypointNS.Internal.GuideTrackerViewer.QuestDetails
local function frame()
    local value = { scripts = {}, visible = true }
    function value:GetScript(key) return self.scripts[key] end
    function value:SetScript(key, fn) self.scripts[key] = fn end
    function value:EnableMouse(on) self.mouse = on end
    function value:IsVisible() return self.visible end
    return value
end
local function root()
    local menu = { entries = {} }
    function menu:CreateButton(label, callback)
        local entry = root(); entry.label, entry.callback = label, callback
        function entry:SetEnabled(value) self.enabled = value end
        function entry:SetTooltip(callback) self.tooltip = callback end
        self.entries[#self.entries + 1] = entry
        return entry
    end
    return menu
end
local block, line = frame(), frame()
for _, provider in ipairs({ "zygor", "rxp", "dugi", "apr", "wowpro", "polestar", "questierouter" }) do
    Q.RegisterSource(provider, function() return source end)
    Q.Clear(block); Q.BindRow(line, block, {questID=42}, provider)
    local menu = root(); Q.AddMenu(menu, line)
    assert(menu.entries[1].label == "Open Quest Details" and menu.entries[1].enabled)
    menu.entries[1].callback(); assert(calls[#calls][2] == 42)
end
Q.BindRow(line, block, {questID=43}, "questierouter")
local menu = root(); Q.AddMenu(menu, line); menu.entries[1].callback()
assert(calls[#calls][2] == 43, "Clicked quest was replaced by current navigation quest")
Q.Clear(block); Q.BindSection(block, "rxp", {{questID=43,questIDs={42,43,42}}, {questID=99}})
menu = root(); Q.AddMenu(menu, block)
local children = menu.entries[1].entries
assert(#children == 3 and children[1].enabled and children[2].enabled and not children[3].enabled)
assert(children[1].label=="Quest 42" and children[2].label=="Quest 43", "Primary selection reordered authored alternatives")
local stale = children[1].callback; source = {}; local before = #calls; stale()
assert(#calls == before and #messages > 0, "Stale source menu was dispatched")
Q.BindRow(line, block, {questID=42}, "rxp"); menu=root(); Q.AddMenu(menu,line)
stale=menu.entries[1].callback; Q.BindRow(line,block,{questID=43},"rxp"); before=#calls; stale(); assert(#calls==before)
menu=root(); Q.AddMenu(menu,line); stale=menu.entries[1].callback; log[43]=nil; stale(); assert(#calls==before)
log[43]=2; Q.BindRow(line,block,{questID=43},"rxp")
local left=0; line:SetScript("OnMouseUp",function(_,button)if button=="LeftButton" then left=left+1 end end)
local right=0; Q.WireRow(line,function(anchor)assert(anchor==line);right=right+1 end)
line.scripts.OnMouseUp(line,"LeftButton");line.scripts.OnMouseUp(line,"RightButton")
assert(left==1 and right==1, "Quest menu replaced the existing left click")
local function click()
    local m=root();Q.AddMenu(m,line);local entry=m.entries[1];assert(entry);if entry.enabled then entry.callback() end;return entry.enabled
end
combat=true; before=#calls; assert(not click() and #calls==before)
host="ellesmere"; EllesmereUIQuestTracker={ShowQuestDetails=function(id)record("ellesmere",id)end}
assert(click() and calls[#calls][1]=="ellesmere", "Addon-owned details were blocked in combat")
host="daylight"
local reads=0
DaylightUI={GetModule=function()return {enabled=true,ns={Tracker={view={}},Data={Quest=function(id)reads=reads+1;return {id=id,objs={}}end},
    Details={Toggle=function(q)assert(q.objs);record("daylight",q.id)end}}}end}
assert(click() and reads==1 and calls[#calls][1]=="daylight")
host="kaliel";assert(not click())
combat=false
LibStub=function(name)assert(name=="MSA-AceAddon-3.0");return {GetAddon=function(_,key)assert(key=="!KalielsTracker");return {
    OpenService_Open=function(action,id)assert(action=="quest");record("kaliel",id)end}end}end
assert(click() and calls[#calls][1]=="kaliel")
for _, nativeHost in ipairs({"blizzard","questie","gw2ui"}) do host=nativeHost;assert(click() and calls[#calls][1]=="blizzard") end
-- Retail Ellesmere's IsSelected is false: its skin uses this Blizzard branch.
host="blizzard";assert(click() and calls[#calls][1]=="blizzard")
host="daylight";DaylightUI=nil;before=#calls;assert(not click() and #calls==before,"Missing replacement silently opened another view")
Q.BindRow(line,block,{},"rxp");menu=root();Q.AddMenu(menu,line);assert(#menu.entries==0)
print("guide_quest_details_test: passed")
