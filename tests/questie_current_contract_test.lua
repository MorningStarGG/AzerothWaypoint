local NativePath=dofile("tests/native_path.lua")
local source=assert(io.open(NativePath("forever","Questie/Modules/Tracker/QuestieTracker.lua"),"r"))
local text=source:read("*a");source:close()
local method=assert(text:match("(function QuestieTracker:UpdateHeight%(%)%s.-\nend)"),"Native tracker height method changed")
local writes=0
local function Frame(height)
    return {height=height,GetHeight=function(self) return self.height end,
        SetHeight=function(self,value) self.height=value;writes=writes+1 end,
        GetTop=function() error("Native height depends on unresolved screen position") end,
        GetBottom=function() error("Native height depends on unresolved screen position") end}
end
local base,header,viewport,child=Frame(25),Frame(20),Frame(25),Frame(25)
viewport.ScrollChildFrame=child
local lines={}
local pool={GetCurrentLine=function() return lines[#lines] end,GetHighestIndex=function() return #lines end,
    GetLine=function(i) return lines[i] end}
local tracker={}
local questie={db={profile={trackerFontSizeZone=12,trackerHeightRatio=.35,TrackerHeight=160,trackerHeaderEnabled=true},
    char={isTrackerExpanded=true}}}
local fn=assert(loadstring(method))
setfenv(fn,setmetatable({QuestieTracker=tracker,Questie=questie,trackerHeaderFrame=header,
    trackerBaseFrame=base,trackerQuestFrame=viewport,TrackerBaseFrame={},TrackerLinePool=pool,
    GetScreenHeight=function() return 1000 end},{__index=_G}))
fn()
tracker:UpdateHeight()
assert(writes==0,"Native empty expanded pass now writes geometry; review AWP's capture policy")
questie.db.char.isTrackerExpanded=false
tracker:UpdateHeight()
assert(writes==3 and base.height==35 and child.height==35,"Native empty collapsed geometry contract changed")
questie.db.char.isTrackerExpanded=true
for _,height in ipairs({18,23,31}) do
    local row=Frame(height);row.label={GetStringHeight=function() return height end};lines[#lines+1]=row
end
lines[3].mode="zone"
tracker:UpdateHeight()
assert(child.height==72 and base.height==112 and viewport.height==72,"Native row-height sum changed")
local config=assert(loadfile(NativePath("forever","QuestieDB/src/config.lua")))()
assert(config.minSupportedContract<=4 and config.contractVersion>=4,"Installed QuestieDB no longer supports AWP's consumer contract")
print("Installed Questie empty/expanded/collapsed and row-height contracts, and QuestieDB consumer contract 4 passed")
