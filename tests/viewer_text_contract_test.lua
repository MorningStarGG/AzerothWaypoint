local f = dofile("tests/daylight_fixture.lua")
local replaceMethod = dofile("tests/replace_method.lua")
for _, file in ipairs({"core/core.lua","core/routing_backends.lua","core/db_defaults.lua","core/db.lua","core/guide_settings.lua",
    "interface/appearance/controller.lua","integrations/guides/viewer_styles.lua"}) do assert(loadfile(file))() end
local NS = AzerothWaypointNS
local S, A = NS.Internal.GuideTrackerViewer.Styles, NS.Internal.Appearance
local getRGB = A.GetRGB
local function color(key, action, role, status, kind)
    local r,g,b = S.StatusToRGB(status or "incomplete", kind or "goal", action, key, role)
    return string.format("%.2f/%.2f/%.2f",r,g,b)
end
local blue = color("zygor","talk")
local cyan = color("zygor","learn")
local green = color("zygor","accept",nil,"complete")
local gray = color("zygor","accept",nil,"obsolete")
local cream = color("zygor","note")
local warning = color("zygor","note",nil,"warning")
local failed = color("zygor","note",nil,"failed")
local themeReads = 0
replaceMethod(A, "GetRGB", function() themeReads=themeReads+1;return .2,.3,.4 end)
for _, definition in ipairs(NS.Constants.GUIDE_PROVIDERS) do
    local key = definition.key
    for _, action in ipairs({"train","trainer","learnspell","learnpetspell","learnmount","learnpet","skill","skillmax","reachskill"}) do
        assert(color(key,action)==cyan,"Unclassified learning action: "..key.."/"..action)
    end
    assert(color(key,nil,"heading",nil,"tip")==blue and color(key,"note","npc",nil,"tip")==blue)
    assert(color(key,"gossip")==blue and color(key,"clicknpc")==blue)
    assert(color(key,"talk",nil,"complete")==green and color(key,"collect",nil,"skipped")==gray)
    assert(color(key,"talk","note","complete","tip")==cream,"Authored note inherited action completion")
    assert(color(key,"note",nil,"warning","tip")==warning and color(key,"note",nil,"failed","tip")==failed)
    assert(color(key,"future_native_action")=="1.00/1.00/1.00","Unknown live action lost its safe fallback")
    assert(NS.SetGuideTrackerViewerProviderSetting(key,"textColorMode","theme"))
    assert(color(key,"talk")=="0.20/0.30/0.40")
    replaceMethod(A, "GetRGB", function() return nil end)
    assert(color(key,"talk")==blue and NS.GetGuideTrackerViewerSettings(key).textColorMode=="theme")
    replaceMethod(A, "GetRGB", function() themeReads=themeReads+1;return .2,.3,.4 end)
    NS.SetGuideTrackerViewerProviderSetting(key,"textColorMode","custom")
    NS.SetGuideTrackerViewerProviderSetting(key,"textCustomColor",{r=.4,g=.5,b=.6})
    assert(color(key,"kill")=="0.40/0.50/0.60" and color(key,nil,"heading")=="0.40/0.50/0.60")
    NS.SetGuideTrackerViewerProviderSetting(key,"textColorMode","auto")
    local reads = themeReads
    assert(color(key,"talk")==blue and themeReads==reads,"Auto consulted the theme palette")
    local module=f.Frame();module._awpGuideProvider=key;module.usedBlocks={}
    local texts={}
    for _, size in ipairs(NS.Constants.GUIDE_VIEWER_TEXT_SIZES) do
        local text=f.Frame(module);text:SetFont("Native.ttf",15,"OUTLINE");texts[size.role]=text
        A.Text(text,"guide."..key,nil,nil,size.role)
        assert(select(2,text:GetFont())==15,"Default sizes changed the existing look")
        NS.SetGuideTrackerViewerProviderSetting(key,size.key,size.max)
    end
    NS.SetGuideTrackerViewerProviderSetting(key,"customTextSizes",true)
    for _, size in ipairs(NS.Constants.GUIDE_VIEWER_TEXT_SIZES) do
        A.Text(texts[size.role],"guide."..key,nil,nil,size.role)
        assert(select(2,texts[size.role]:GetFont())==size.max)
    end
    local cached=NS.GetGuideTrackerViewerProviderSettings(key)
    for _=1,1000 do assert(NS.GetGuideTrackerViewerProviderSettings(key)==cached) end
    NS.SetGuideTrackerViewerProviderSetting(key,"bodySize",1000)
    assert(NS.GetGuideTrackerViewerSettings(key).bodySize==24)
    NS.SetGuideTrackerViewerProviderSetting(key,"bodySize",0/0)
    assert(NS.GetGuideTrackerViewerSettings(key).bodySize==13)
    NS.SetGuideTrackerViewerProviderSetting(key,"customTextSizes",false)
    for _, size in ipairs(NS.Constants.GUIDE_VIEWER_TEXT_SIZES) do
        A.Text(texts[size.role],"guide."..key,nil,nil,size.role)
        assert(select(2,texts[size.role]:GetFont())==15,"Turning sizes off failed to restore the baseline")
    end
end
assert(not NS.GetGuideTrackerViewerTextSize("zygor","button"),"Viewer sizing affected action controls")
NS.SetGuideTrackerViewerProviderSetting("zygor","chatTextColorMode","theme")
assert(NS.GetGuideTrackerViewerSettings("zygor").chatTextColorMode=="auto","Viewer-only mode leaked into chat")
replaceMethod(A, "GetRGB", getRGB)
-- An explicit Viewer size is final; the selected font face/outline still
-- come from the theme. Returning to inheritance restores its scaled baseline.
local module=f.Frame();module._awpGuideProvider="zygor";module.usedBlocks={}
local text=f.Frame(module);text:SetFont("Native.ttf",15,"OUTLINE")
A.provider={GetFont=function() return {active=true,file="Theme.ttf",size=18,scale=1.5,flags=""} end}
NS.SetGuideTrackerViewerProviderSetting("zygor","bodySize",23)
NS.SetGuideTrackerViewerProviderSetting("zygor","customTextSizes",true)
A.Text(text,"guide.zygor",nil,nil,"body")
assert(text:GetFont()=="Theme.ttf" and select(2,text:GetFont())==23)
NS.SetGuideTrackerViewerProviderSetting("zygor","customTextSizes",false)
A.Text(text,"guide.zygor",nil,nil,"body")
assert(select(2,text:GetFont())==27)
A.provider=nil
A.Text(text,"guide.zygor",nil,nil,"body")
assert(text:GetFont()=="Native.ttf" and select(2,text:GetFont())==15)
local Common=NS.Internal.GuideTrackerViewer
Common.Host={IsKTLoaded=function()return false end}
Common.Controls={SetStepCheckbox=function()end}
assert(loadfile("integrations/guides/viewer_render.lua"))()
local block=f.Frame(module);block.parentModule=module
local line=f.Frame(block);line.Text=f.Frame(line);line.Text:SetWidth(95);line.Text:SetWordWrap(true)
function block:AddObjective(_,value)
    line.Text:SetText(value);line:SetHeight(line.Text:GetStringHeight());self.height=line:GetHeight()+4;return line
end
NS.SetGuideTrackerViewerProviderSetting("zygor","customTextSizes",true)
Common.Render.AddObjective(block,1,{text="A long objective requiring several wrapped lines",kind="goal",fullHeight=true})
assert(select(2,line.Text:GetFont())==23 and line:GetHeight()==math.ceil(line.Text:GetStringHeight())
    and block.height==line:GetHeight()+4,"Viewer font size was applied after the host measured its rows")
print("Seven-guide contextual colors, explicit theme/fallback, fixed colors, typography ownership, cached sizes and restoration passed")
