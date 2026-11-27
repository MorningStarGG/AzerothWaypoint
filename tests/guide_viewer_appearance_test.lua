local function expect(value, message) if not value then error(message, 2) end end
_G.AzerothWaypointNS = {IsWoWForever=function() return false end}
assert(loadfile("core/core.lua"))()
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/db_defaults.lua"))()
assert(loadfile("core/db.lua"))()
assert(loadfile("core/guide_settings.lua"))()
local NS = AzerothWaypointNS
local providers = { "zygor", "dugi", "rxp", "polestar" }
local function set(key, setting, value) assert(NS.SetGuideTrackerViewerProviderSetting(key, setting, value)) end
local function settings(key) return NS.GetGuideTrackerViewerSettings(key) end
local db = NS.GetDB()
-- The unreleased shared schema has no migration or runtime fallback.
db.guideTrackerViewerTextColorMode, db.guideTrackerViewerProgressStyle = "custom", "none"
db.guideTrackerViewerTextCustomColor = {r=1,g=0,b=0}
db.guideTrackerViewerKTHeaderFont = true
for _, key in ipairs(providers) do
    expect(settings(key).textColorMode == "auto" and settings(key).progressStyle == "rounded"
        and not settings(key).ktHeaderStyle.font, "Unreleased shared appearance was inherited")
end
expect(not NS.SetGuideTrackerViewerSetting("progressStyle", "none"), "Host setter still accepts appearance")
local colors = { zygor={r=1,g=0,b=0}, dugi={r=0,g=1,b=0}, rxp={r=0,g=0,b=1}, polestar={r=1,g=.5,b=0} }
for _, key in ipairs(providers) do set(key,"textColorMode","custom");set(key,"textCustomColor",colors[key]) end
set("zygor","progressStyle","square");set("dugi","progressStyle","none");set("rxp","progressStyle","rounded")
local zygor, dugi, rxp = settings("zygor"), settings("dugi"), settings("rxp")
db.guideTrackerViewerDugiTextCustomColor.g = .8
expect(settings("dugi") ~= dugi and settings("zygor") == zygor and settings("rxp") == rxp,
    "In-place provider color mutation invalidated unrelated snapshots")
set("dugi","textCustomColor",colors.dugi)
for _, key in ipairs(providers) do settings(key) end
collectgarbage("collect");collectgarbage("stop")
local start = collectgarbage("count")
for _=1,10000 do for _,key in ipairs(providers) do settings(key) end end
local allocated = collectgarbage("count")-start
collectgarbage("restart")
expect(allocated<2,"Unchanged provider settings allocate temporary tables: "..allocated)

local Common = NS.Internal.GuideTrackerViewer
assert(loadfile("integrations/guides/viewer_styles.lua"))()
local function widget()
    return setmetatable({}, {__index=function(_,key)
        if not key:match("^%u") or key=="MinimizeButton" then return nil end
        return function(self,...)
            if key=="CreateTexture" or key=="CreateFontString" or key=="GetStatusBarTexture" then return widget() end
            if key=="GetFrameLevel" then return 1 end
            if key=="SetTextColor" then self.color={...} end
            if key=="SetText" then self.text=(...) end
            if key=="Show" then self.shown=true end
            if key=="Hide" then self.shown=false end
        end
    end})
end
_G.CreateFrame=widget
assert(loadfile("interface/framework/panels.lua"))()
assert(loadfile("integrations/guides/viewer_controls.lua"))()
Common.Host={IsKTLoaded=function()return false end}
assert(loadfile("integrations/guides/viewer_render.lua"))()
local modules={}
for _,key in ipairs(providers) do
    local module=widget();module.Header=widget();module.Header.Text=widget();module._awpGuideProvider=key
    modules[key]=module
    Common.Controls.Create(module,{})
    Common.Controls.Update(module,2,10)
    expect(module._awpControls.progressBar._awpProgressStyle==settings(key).progressStyle,
        "Shared header read another provider's progress style")
    local block={parentModule=module,HeaderText=widget()}
    Common.Controls.SetBlockHeaderText(block,"Guide")
    local color=colors[key]
    expect(block.HeaderText.color[1]==color.r and block.HeaderText.color[2]==color.g
        and block.HeaderText.color[3]==color.b,"Guide header color crossed provider boundaries")
    function block:AddObjective() return {Text=widget(),parentBlock=self} end
    local line=Common.Render.AddObjective(block,1,{text="Collect",action="collect"})
    expect(line.Text.color[1]==color.r and line.Text.color[2]==color.g and line.Text.color[3]==color.b,
        "Shared row read another provider's color")
    _G.GameTooltip={SetOwner=function()end,SetText=function()end,Show=function()end,
        AddLine=function(self,_,r,g,b)self.color={r,g,b}end}
    Common.Render.ShowTipGroupTooltip(line,"Tips",{{text="Instruction",kind="tip"}})
    expect(GameTooltip.color[1]==color.r and GameTooltip.color[2]==color.g and GameTooltip.color[3]==color.b,
        "Tips tooltip read another provider's color")
    modules[key].block=block
end
-- Reusing a native pooled line under a different module changes its color.
local reused={Text=widget(),parentBlock=modules.zygor.block}
Common.Render.ApplyLineColor(reused,"incomplete","goal","collect")
reused.parentBlock=modules.rxp.block
Common.Render.ApplyLineColor(reused,"incomplete","goal","collect")
expect(reused.Text.color[3]==1 and reused.Text.color[1]==0,"Pooled row retained its previous provider's style")

-- Exercise the actual KT adapter with distinct enabled facets per module.
local pending={}
NS.After=function(_,fn)pending[#pending+1]=fn end
_G.C_Timer={After=NS.After}
_G.hooksecurefunc=function(object,method,callback)
    local original=object[method]
    object[method]=function(...)original(...);callback(...)end
end
local function region(texture,r,g,b,a)
    local value={texture=texture,color={r,g,b,a},shown=true,font={"AWPFont",12,"OUTLINE"}}
    function value:GetTexture()return self.texture end
    function value:SetTexture(v)self.texture=v end
    function value:GetVertexColor()return unpack(self.color)end
    function value:SetVertexColor(...)self.color={...}end
    value.GetTextColor,value.SetTextColor=value.GetVertexColor,value.SetVertexColor
    function value:GetFont()return unpack(self.font)end
    function value:SetFont(...)self.font={...}end
    function value:GetNumPoints()return 0 end
    function value:IsShown()return self.shown end
    function value:Show()self.shown=true end
    function value:Hide()self.shown=false end
    return value
end
local native={Header={Background=region("KT",.2,.3,.4,.5),Text=region(nil,.1,.9,.3,1)}}
native.Header.Text.font={"KTFont",18,""};native.Header.Background.shown=false
_G.KT_ObjectiveTrackerFrame={modules={native}}
local ktButton=region(nil,.9,.4,.1,1)
_G["!KalielsTrackerFrame"]={MinimizeButton={GetNormalTexture=function()return ktButton end}}
NS.Internal.ZygorTrackerViewer={}
NS.Internal.GuideTrackerViewer.Host={IsKTLoaded=function()return true end}
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/viewer_header_style.lua"))()
for _,key in ipairs(providers) do
    local module=modules[key]
    module.Header={Background=region("AWP",.7,.8,.9,.6),Text=region(nil,.7,.8,.9,1),Icon=region(nil,.7,.8,.9,1)}
    module.buttonTexture=region(nil,.7,.8,.9,.35)
    module._awpControls={settingsBtn={GetNormalTexture=function()return module.buttonTexture end}}
    Common.HeaderStyle.CaptureBaseline(module)
end
set("zygor","ktHeaderTexture",true)
set("dugi","ktHeaderBackgroundColor",true);set("dugi","ktHeaderFont",true)
set("rxp","ktHeaderTextIconColor",true);set("rxp","ktHeaderButtonColor",true)
NS.RefreshZygorTrackerViewerHeaderStyle()
expect(not modules.zygor.Header.Background.shown and modules.dugi.Header.Background.shown
    and modules.rxp.Header.Background.shown,"KT texture option affected another module")
expect(modules.dugi.Header.Background.color[1]==.2 and modules.zygor.Header.Background.color[1]==.7,
    "KT background option affected another module")
expect(modules.dugi.Header.Text.font[1]=="KTFont" and modules.zygor.Header.Text.font[1]=="AWPFont",
    "KT font option affected another module")
expect(modules.rxp.Header.Text.color[2]==.9 and modules.dugi.Header.Text.color[2]==.8,
    "KT title option affected another module")
expect(modules.rxp.buttonTexture.color[1]==.9 and modules.rxp.buttonTexture.color[4]==.35
    and modules.dugi.buttonTexture.color[1]==.7,"KT button tint crossed provider boundaries or changed state alpha")
for _,key in ipairs(providers) do
    for _,facet in ipairs({"ktHeaderTexture","ktHeaderBackgroundColor","ktHeaderFont","ktHeaderTextIconColor","ktHeaderButtonColor"}) do
        set(key,facet,false)
    end
end
NS.RefreshZygorTrackerViewerHeaderStyle()
for _,key in ipairs(providers) do
    local module=modules[key]
    expect(module.Header.Background.shown and module.Header.Background.texture=="AWP"
        and module.Header.Background.color[1]==.7 and module.Header.Text.font[1]=="AWPFont"
        and module.Header.Text.color[1]==.7 and module.buttonTexture.color[1]==.7,
        "Disabling provider facets failed to restore that module's baseline")
end
set("rxp","ktHeaderTextIconColor",true)
native.Header.Text:SetTextColor(.3,.4,.8,1)
local queue=pending;pending={};for _,fn in ipairs(queue)do fn()end
expect(modules.rxp.Header.Text.color[3]==.8 and modules.zygor.Header.Text.color[3]==.9,
    "KT source hook did not respect per-module facet settings")
expect(#KT_ObjectiveTrackerFrame.modules==1,"AWP modified KT's native module list")
print("Independent four-provider colors, headers, progress, tips, pooled rows, cached reads and KT facets passed")
