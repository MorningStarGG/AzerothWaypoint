local f = dofile("tests/daylight_fixture.lua")
local NS = AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local role, bound, questBound
NS.Internal.Appearance = { Text = function(text, _, _, _, kind)
    role = kind; text:SetFont("Fixture.ttf", kind == "heading" and 21 or kind == "tip" and 11 or 14, "")
end }
Common.Styles = { GetProviderKey = function() return "polestar" end,
    GetTrackerColorStyle = function() return {r=1,g=1,b=1} end }
Common.Controls = { SetStepCheckbox = function(line, _, value) line.check = value end }
Common.QuestDetails = { Clear = function() end, BindRow = function() questBound = true end }
Common.GuideActions = { ReleaseRow = function() end, LayoutLeadingStepStrip = function() end,
    BindRow = function() bound = true end }

for _, kt in ipairs({false,true}) do
    Common.Host = { IsKTLoaded = function() return kt end }
    assert(loadfile("integrations/guides/viewer_render.lua"))()
    for _, width in ipairs({90,300}) do
        local line = f.Frame(); line.Text = f.Frame(line); line.Dash = f.Frame(line)
        line.Text:SetWidth(width); line.Text:SetWordWrap(true)
        local block = {height=0,parentModule={lineSpacing=4}}
        function block:GetExistingLine() return line end
        function block:AddObjective(_,text)
            line.Text:SetText(text)
            line:SetHeight(line.Text:GetStringHeight())
            self.height = self.height + line:GetHeight() + 4
            return line
        end
        for _, entry in ipairs({
            {role="heading",kind="tip",size=21}, {kind="goal",size=14},
            {role="support",kind="tip",size=11}, {kind="goal",size=14},
        }) do
            block.height, bound, questBound = 0, false, false
            local decorative = entry.role ~= nil
            Common.Render.AddObjective(block,1,{text="A long instruction that wraps within the tracker",kind=entry.kind,
                role=entry.role,fullHeight=true})
            local measured = math.ceil(line.Text:GetStringHeight())
            assert(line:GetHeight()==measured and block.height==measured+4,
                "Role font height retained the pooled row's previous measurement")
            assert(line.Text.size==entry.size and role==(entry.role=="heading" and "heading" or entry.kind=="tip" and "tip" or "body"))
            assert(bound~=decorative and questBound~=decorative and line.Dash:IsShown()~=decorative,
                "Decorative role acquired objective actions or ordinary row lost them")
        end
    end
end
print("Shared heading/support fonts, narrow wrapping, pooled role transitions, measured block heights and action exclusion passed")
