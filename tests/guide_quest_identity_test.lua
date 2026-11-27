local fixture = dofile("tests/guide_parity/fixture.lua")
local adapters = dofile("tests/guide_parity/native_adapters.lua")
local names = { apr="APRProvider", wowpro="WoWProProvider", rxp="RXPProvider",
    polestar="PolestarProvider", questierouter="QuestieRouterProvider" }
local checked = 0
for _, client in ipairs({"retail", "forever"}) do
    for _, provider in ipairs({"zygor","apr","wowpro","dugi","rxp","polestar","questierouter"}) do
        if client == "forever" or provider ~= "polestar" and provider ~= "questierouter" then
            local scenario = {current=1, stop={kind="turnin",npc="Quartermaster Brevin",quests={
                {id=9001,name="Quest A",state="ready"},{id=9002,name="Quest B",state="ready"}}}}
            local f = fixture.setup(client, scenario)
            adapters[provider](f,scenario,client)
            local rows = {}
            if provider == "zygor" then
                local shared = { TrackerUtil={IsConfirmGoal=function()return false end} }
                f.NS.Internal.ZygorTrackerViewer = shared
                shared.IterateRenderableGoalLines=function(step,visit)
                    for _,goal in ipairs(step.goals) do visit(goal,goal.text or "Quest", "incomplete", "goal") end
                end
                f.load("integrations/guides/zygor/viewer/tracker_rows")
                rows=shared.TrackerRows.BuildDockedGoalRows(f.native.runtime.CurrentStep)
            elseif provider == "dugi" then
                for index=1,2 do
                    local presentation=f.NS.Internal.DugiPresentation.ResolveStep(rawget(_G,"DugisGuideViewer"),index)
                    for _,row in ipairs(presentation.rows)do rows[#rows+1]=row end
                end
            else
                local snapshot=f.NS.Internal[names[provider]].GetSnapshot()
                for _,step in ipairs(snapshot.steps)do
                    for _,row in ipairs(step.rows)do rows[#rows+1]=row end
                end
            end
            local found={}
            for _,row in ipairs(rows)do
                if row.questID then found[row.questID]=true end
                for _,id in ipairs(row.questIDs or {})do found[id]=true end
            end
            assert(found[9001] and found[9002],client.."/"..provider.." lost exact quest identities in rendered rows")
            checked=checked+1
        end
    end
end
print("guide_quest_identity_test: "..checked.." native provider/client row identities passed")
