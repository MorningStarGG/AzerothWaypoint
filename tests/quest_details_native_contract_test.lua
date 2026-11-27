local path=dofile("tests/native_path.lua")
local native=dofile("tests/guide_parity/native_function.lua")
local ss, shown, opened, ping = {}, nil, 0, nil
local combat=false
local kt={db={profile={questLog={detailsShow=true}}},QuestLog={}}
function kt:NewSubsystem(name)assert(name=="OpenService");return ss end
function kt:Addon_IsModule(module)assert(module==self.QuestLog);return true end
kt.InCombatBlocked=function()return combat end
C_GameRules={IsGameRuleActive=function()return false end};Enum={GameRule={WorldMapDisabled=1}}
QuestLogDisplayMode={Quests=1};QuestMapFrame={SetDisplayMode=function()end}
C_Map={OpenWorldMap=function()opened=opened+1 end}
GetCVarBool=function()return true end
KT_QuestMapFrame_ShowQuestDetails=function(id)shown=id end
GetQuestUiMapID=function()return 1412 end
EventRegistry={TriggerEvent=function(_,event,id)if event=="MapCanvas.PingQuestID" then ping=id end end}
StaticPopup_Hide=function()end
C_SuperTrack={GetSuperTrackedQuestID=function()return 0 end,SetSuperTrackedQuestID=function()error("Details changed tracking")end}
assert(loadfile(path("forever","!KalielsTracker/Core/System/Subsystems/OpenService.lua")))("!KalielsTracker",kt)
ss:Init();kt.OpenService_Open("quest",42);assert(shown==42 and opened==1)
kt.db.profile.questLog.detailsShow=false;shown=nil;kt.OpenService_Open("quest",43);assert(shown==nil and ping==43)
combat=true;local before=opened;kt.OpenService_Open("quest",42);assert(opened==before)
local overridden
kt.OpenService_Override("quest",function(id)overridden=id end);kt.OpenService_Open("quest",43);assert(overridden==43)

-- Run Daylight's actual quest-record builder and its menu's details toggle.
local data={Objectives=function()return {{text="Objective"}}end,Tag=function()return "quest"end,
    PartyOn=function()end,TimeLeft=function()end}
local calls=0
local env={Data=data,DaylightUI={Npc={Data={QuestColor=function()return {}end}}},
    C_QuestLog={GetLogIndexForQuestID=function(id)assert(id==42);return 1 end,
        GetInfo=function()return {title="Quest",level=5}end,IsComplete=function()return false end},
    api=function(object,key)return object[key]end,call=function(fn,...)if fn then return fn(...)end end,
    ns={},GetQuestLogSpecialItemInfo=function()end}
native("forever","DaylightUI_Quests/Data.lua","Data.Quest",env)
local quest=data.Quest(42)
assert(quest.id==42 and quest.title=="Quest" and #quest.objs==1)
local details={Show=function(q)assert(q==quest);calls=calls+1 end}
native("forever","DaylightUI_Quests/Details.lua","Details.Toggle",{Details=details})
details.Toggle(quest);assert(calls==1)

-- Ellesmere's Forever-only window takes the ID; repeated use follows its toggle.
local eui={}
local window={shown=false}
function window:IsShown()return self.shown end
function window:Hide()self.shown=false end
function window:Show()self.shown=true end
local euiEnv={EQT=eui,scroll={SetVerticalScroll=function()end},Place=function()end,Refresh=function()end}
euiEnv.Build=function()euiEnv.win=window end
native("forever","EllesmereUIQuestTracker/EllesmereUIQuestTracker_Details.lua","EQT.ShowQuestDetails",euiEnv)
eui.ShowQuestDetails(42);assert(window.shown and euiEnv.questID==42)
eui.ShowQuestDetails(42);assert(not window.shown)
eui.ShowQuestDetails(43);assert(window.shown and euiEnv.questID==43)
-- These same files are installed on Retail but must not supply its quest view.
for _,file in ipairs({"Custom", "Details"}) do
    local retailNS={EQT={}}
    local chunk=assert(loadfile(path("retail","EllesmereUIQuestTracker/EllesmereUIQuestTracker_"..file..".lua")))
    setfenv(chunk,setmetatable({EllesmereUI={IS_FOREVER=false}}, {__index=_G}))("EllesmereUIQuestTracker",retailNS)
    assert(next(retailNS.EQT)==nil and not retailNS.UseCustomTracker,"Forever replacement was enabled on Retail")
end
print("quest_details_native_contract_test: installed Kaliel, Daylight and Ellesmere contracts passed")
