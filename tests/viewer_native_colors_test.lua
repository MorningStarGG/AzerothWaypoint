local fixture=dofile("tests/guide_parity/fixture.lua")
local adapters=dofile("tests/guide_parity/native_adapters.lua")
local apis={apr="APRProvider",wowpro="WoWProProvider",rxp="RXPProvider",polestar="PolestarProvider",questierouter="QuestieRouterProvider"}
local count=0
for _, client in ipairs({"retail","forever"}) do
    for _, key in ipairs({"zygor","dugi","rxp","apr","wowpro","polestar","questierouter"}) do
        if client=="forever" or key~="polestar" and key~="questierouter" then
            for _, kind in ipairs({"accept","turnin"}) do
                local scenario={current=1,stop={kind=kind,npc="Fixture trainer",quests={{id=9001,name="Quest A",state=kind=="accept" and "available" or "ready"}}}}
                local f=fixture.setup(client,scenario)
                assert(adapters[key](f,scenario,client))
                f.load("integrations/guides/viewer_styles")
                local S=f.NS.Internal.GuideTrackerViewer.Styles
                local rows={}
                if key=="zygor" then
                    f.load("integrations/guides/zygor/viewer/shared")
                    f.NS.Internal.ZygorTrackerViewer.IterateRenderableGoalLines(f.native.runtime.CurrentStep,function(goal,text,status,rowKind)
                        rows[#rows+1]={text=text,status=status,kind=rowKind,action=goal.action}
                    end,true)
                elseif key=="dugi" then rows=f.NS.Internal.DugiPresentation.ResolveStep(f.native.runtime,1).rows
                else
                    for _, step in ipairs(f.NS.Internal[apis[key]].GetSnapshot().steps) do
                        for _, row in ipairs(step.rows) do rows[#rows+1]=row end
                    end
                end
                local actionRow
                for _, row in ipairs(rows) do
                    if row.kind=="goal" and row.action==kind then actionRow=row;break end
                end
                assert(actionRow,client.."/"..key.." did not produce its native quest row")
                local r,g,b=S.StatusToRGB(actionRow.status,actionRow.kind,actionRow.action,key,actionRow.colorRole)
                assert(r==1 and g==.82 and b==.30,client.."/"..key.." quest row diverged from the Zygor color benchmark")
                for _, row in ipairs(rows) do
                    if row.colorRole=="npc" or row.action=="talk" then
                        r,g,b=S.StatusToRGB(row.status,row.kind,row.action,key,row.colorRole)
                        assert(r==0 and g==.67 and b==1,client.."/"..key.." NPC context lost its color")
                    end
                end
                count=count+1
                if key=="dugi" then
                    f.native.runtime.states[1]="X"
                    local skipped=f.NS.Internal.DugiPresentation.ResolveStep(f.native.runtime,1).rows[1]
                    assert(skipped.status=="skipped")
                elseif key=="wowpro" then
                    local api=f.NS.Internal.WoWProProvider
                    local before=api.GetSnapshot()
                    local character=assert(rawget(_G,"WoWProCharDB"))
                    character.Guide.fixture={skipped={[1]=true}}
                    api.Schedule("skip_changed");f.flush()
                    assert(api.GetSnapshot()~=before and api.GetSnapshot().steps[1].rows[1].status=="skipped",
                        "Native skipped state was cached as completion or an unchanged row")
                end
            end
        end
    end
end
assert(count==24)
print("24 native-parser/engine acceptance and turn-in row color cases passed across both clients and all seven guides")
