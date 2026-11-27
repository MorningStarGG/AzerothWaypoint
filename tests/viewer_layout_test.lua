-- Shared Viewer geometry and compact presentation, without a game client.
_G.AzerothWaypointNS = {IsWoWForever=function() return false end}
assert(loadfile("core/core.lua"))()
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/db_defaults.lua"))()
assert(loadfile("core/db.lua"))()
assert(loadfile("core/guide_settings.lua"))()
local NS = AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local Frame = {}
Frame.__index = Frame
local function frame(parent)
    local f=setmetatable({parent=parent,points={},scripts={},width=260,height=26,shown=true,children={}},Frame)
    if parent then parent.children[#parent.children+1]=f end
    return f
end
function Frame:SetPoint(point,relative,relativePoint,x,y)
    if type(relative) ~= "table" then relativePoint,x,y,relative=point,relative,relativePoint,self.parent end
    self.anchorWrites=(self.anchorWrites or 0)+1
    self.points[point]={relative,relativePoint,x or 0,y or 0}
end
function Frame:ClearAllPoints() self.points={} end
function Frame:SetWidth(w)
    if self.width==w then return end
    self.width=w
    if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self) end
    for _,child in ipairs(self.children) do
        if child.points.TOPLEFT and child.points.TOPRIGHT and child.scripts.OnSizeChanged then child.scripts.OnSizeChanged(child) end
    end
end
function Frame:SetHeight(h) self.height=h end
function Frame:SetSize(w,h) self.width,self.height=w,h end
function Frame:GetWidth()
    if self.allPoints then return self.allPoints:GetWidth() end
    if self.points.LEFT and self.points.RIGHT then
        local left,right=self.points.LEFT,self.points.RIGHT
        return right[1]:GetRight()+right[3]-left[1]:GetLeft()-left[3]
    end
    if self.points.TOPLEFT and self.points.TOPRIGHT then return self.parent:GetWidth() end
    return self.width
end
function Frame:GetHeight() return self.height end
function Frame:IsShown() return self.shown end
function Frame:HookScript(event,fn)
    local old=self.scripts[event]
    self.scripts[event]=function(...) if old then old(...) end;fn(...) end
end
function Frame:SetAllPoints(target) self.allPoints=target or self.parent end
function Frame:GetRight()
    if self.allPoints then return self.allPoints:GetRight() end
    local p=self.points.RIGHT
    if p then return (p[2]=="LEFT" and p[1]:GetLeft() or p[1]:GetRight())+p[3] end
    return self:GetLeft()+self:GetWidth()
end
function Frame:GetLeft()
    if self.allPoints then return self.allPoints:GetLeft() end
    if self.points.RIGHT then return self:GetRight()-self:GetWidth() end
    local p=self.points.LEFT or self.points.TOPLEFT
    if p then return (p[2]=="RIGHT" and p[1]:GetRight() or p[1]:GetLeft())+p[3] end
    return self.parent and self.parent:GetLeft() or 0
end
function Frame:GetFrameLevel() return self.level or 2 end
function Frame:SetFrameLevel(level) self.level=level end
function Frame:GetParent() return self.parent end
function Frame:SetParent(parent) self.parent=parent end
function Frame:SetScript(event,fn) self.scripts[event]=fn end
function Frame:CreateTexture() return frame(self) end
Frame.CreateFontString=Frame.CreateTexture
Frame.GetStatusBarTexture=Frame.CreateTexture
function Frame:GetNormalTexture() return self.normal end
function Frame:GetPushedTexture() return self.pushed end
function Frame:GetDisabledTexture() return self.disabled end
function Frame:GetHighlightTexture() return self.highlight end
function Frame:SetNormalTexture(t) self.normal=t end
function Frame:SetPushedTexture(t) self.pushed=t end
function Frame:SetDisabledTexture(t) self.disabled=t end
function Frame:SetAtlas(v) self.atlas=v end
function Frame:SetRotation(v) self.rotation=v end
function Frame:IsEnabled() return self.enabled~=false end
function Frame:SetText(text) self.text=text end
function Frame:GetStringHeight() return self.text=="" and 0 or 16 end
function Frame:Show() self.shown=true end
function Frame:Hide() self.shown=false end
function Frame:SetChecked(v) self.checked=v end
for _,key in ipairs({"EnableMouse","SetNormalAtlas","SetPushedAtlas","SetDisabledAtlas",
    "SetHighlightTexture","SetStatusBarTexture","SetStatusBarColor","SetMinMaxValues","SetValue",
    "SetDrawLayer","SetColorTexture","SetTexture","SetTexCoord","SetVertexColor",
    "SetTextColor","SetJustifyH","SetJustifyV","Enable","Disable","SetFontObject"}) do Frame[key]=function()end end
_G.CreateFrame=function(kind,_,parent,template)
    local f=frame(parent)
    if kind=="Button" then
        for _,key in ipairs({"normal","pushed","disabled","highlight"}) do
            f[key]=frame(f)
            f[key]:SetSize(32,32)
            f[key]:SetPoint("LEFT",f,"LEFT",-8,2)
        end
    end
    -- The installed Blizzard header template has its own fixed 260px width.
    if template=="header" then
        f.Text=frame(f)
        f.MinimizeButton=frame(f)
        f.MinimizeButton:SetSize(16,16)
        f.MinimizeButton:SetPoint("RIGHT",f,"RIGHT",1,0)
    end
    return f
end
_G.Mixin=function(target,source)for k,v in pairs(source)do target[k]=v end end
_G.UIParent=frame()
local container=frame(UIParent)
container.modules={}
local kt=false
local mixin={Update=function(self) self.isDirty=false;return 40 end}
local host={GetTrackerFrame=function()return container end,IsKTLoaded=function()return kt end,
    GetModuleMixin=function()return mixin end,GetHeaderTemplate=function()return "header" end,
    GetLineTemplate=function()return "line" end,GetBlockTemplate=function()return "block" end}
assert(loadfile("integrations/guides/viewer_styles.lua"))()
assert(loadfile("interface/framework/panels.lua"))()
assert(loadfile("integrations/guides/viewer_controls.lua"))()
Common.Host=host
assert(loadfile("integrations/guides/viewer_render.lua"))()
assert(loadfile("integrations/guides/viewer_module.lua"))()
assert(loadfile("integrations/guides/viewer_custom_host.lua"))()
local controls=Common.Controls
local tooltip={}
_G.GameTooltip={SetOwner=function()end,SetText=function(_,v) tooltip.title=v;tooltip.line=nil end,
    AddLine=function(_,v) tooltip.line=v end,Show=function()end,Hide=function()end}
local multipleViewers = true
NS.HasMultipleGuideTrackerViewers = function() return multipleViewers end
local activeProvider="rxp"
NS.GetActiveGuideProvider=function()return activeProvider end
for _,key in ipairs({"zygor","dugi","rxp","polestar","apr","wowpro"}) do
    for _,usingKT in ipairs({false,true}) do
        kt=usingKT
        local module=assert(Common.ModuleFactory.Create({host=host,providerKey=key,name="test"}))
        controls.Create(module,{})
        container.modules={module}
        controls.SetModuleHeader(module,key,key)
        for _,width in ipairs({226,400,160,300,180,226}) do
            Common.CustomHost.Layout(container,width)
            assert(module.Header:GetWidth()==width,"Template header overflowed resized module")
            assert(module._awpControls.prevBtn:GetLeft()>=4 and module._awpControls.settingsBtn:GetRight()<=width-4,
                "Navigation controls escaped the resized header")
        end
        controls.SetModuleHeader(module,key,key)
        local c=module._awpControls
        local function centerY(widget)
            if widget==module.Header then return 0 end
            local p=assert(widget.points.RIGHT)
            return centerY(p[1])+p[4]
        end
        assert(c.progressBar:GetFrameLevel()==module.Header:GetFrameLevel()+2,"Progress fill and counter must both sit above the header")
        for _,button in ipairs({c.prevBtn,c.nextBtn,c.guideBtn,c.settingsBtn}) do
            assert(button.normal.atlas==button.pushed.atlas and button.normal.atlas==button.disabled.atlas)
            assert(button.normal:GetWidth()==8 and button.normal.points.CENTER[3]==0
                and button.normal.points.CENTER[4]==0,"Glyph is not centered inside the shared border")
            assert(button._awpNativeButtonRegions[1].allPoints==button._awpButtonArtHost,"Button border does not fit its artwork host")

        end
        local function checkIndicatorSpacing()
            local collapse=module.Header.MinimizeButton
            local collapseRight=collapse.points.RIGHT[3]
            local indicatorRight=c.activeIndicator.points.RIGHT[3]
            local settingsRight=c.settingsBtn:GetRight()-module.Header:GetWidth()
            assert(collapseRight <= -4,"Collapse button extends into the header border")
            if c.activeIndicator:IsShown() then
                assert(not collapse:IsShown() or indicatorRight <= collapseRight-collapse:GetWidth()-2,"Active indicator overlaps the collapse button")
                assert(settingsRight < indicatorRight-c.activeIndicator:GetWidth(),"Settings overlaps the active indicator")
            elseif collapse:IsShown() then
                assert(math.abs(settingsRight-(collapseRight-collapse:GetWidth()-2))<0.001,
                    "Inactive guide reserves empty indicator space")
            end
        end
        checkIndicatorSpacing()
        assert(module._awpControls.activeDot.shown and not module._awpControls.activeText.shown)
        assert(module._awpControls.activeIndicator.shown==(key=="rxp"))
        NS.SetGuideTrackerViewerProviderSetting(key,"compactActiveIndicator",false)
        controls.SetModuleHeader(module,key,key)
        checkIndicatorSpacing()
        assert(module._awpControls.activeText.shown and not module._awpControls.activeDot.shown)
        NS.SetGuideTrackerViewerProviderSetting(key,"compactActiveIndicator",true)
        NS.SetGuideTrackerViewerProviderSetting(key,"hideGuideTitle",true)
        local block=frame(module);block.parentModule=module;block.HeaderText=frame(block);block.height=0
        function block:SetStringText(text,value) text:SetHeight(0);text:SetText(value);return text:GetStringHeight() end
        controls.Update(module,22,450)
        controls.SetBlockHeaderText(block,"Guide "..key,true)
        assert(block.HeaderText.text=="" and block.height==0,"Hidden title retained a blank row")
        assert(block.HeaderText.shown,"Hidden title changed pooled native visibility")
        controls.SetStepCheckbox(block,block.HeaderText,{checked=false,onClick=function()end})
        assert(not block._awpCheck.shown,"Checkbox floats over an absent first row")
        function block:AddObjective(_,text)
            local line=frame(self);line.Text=frame(line);line.Dash=frame(line)
            line.Text:SetText(text);line:SetHeight(16)
            line:SetPoint("TOPLEFT",self.lastRegion or self.HeaderText,"BOTTOMLEFT",0,-4)
            self.height=self.height+20;self.lastRegion=line
            return line
        end
        local first=Common.Render.AddObjective(block,1,{text="Talk to NPC",kind="goal"})
        assert(first.points.TOPLEFT[1]==block and first.points.TOPLEFT[4]==0,"First instruction retained the title gap")
        Common.Render.EnsureBlockHeight(block,28)
        assert(block.height==16,"Hidden title retains an artificial minimum height")
        assert(block._awpCheck.shown and block._awpCheck.points.TOPRIGHT[1]==first,"Step checkbox did not follow the first instruction")
        local rowBinding={onClick=function()end}
        controls.SetBlockHeaderText(block,"Guide "..key,true);block.lastRegion=nil
        local goal=Common.Render.AddObjective(block,1,{text="Goal",checkbox=rowBinding})
        assert(not block._awpCheck.shown and goal._awpCheck.shown,"Hidden-title step checkbox overlaps an individual goal checkbox")
        controls.SetBlockHeaderText(block,"Guide "..key,true);block.lastRegion=nil
        controls.SetStepCheckbox(block,block.HeaderText,{checked=false,onClick=function()end})
        local heading=Common.Render.AddObjective(block,1,{text="NPC group",kind="tip",role="heading"})
        local instruction=Common.Render.AddObjective(block,2,{text="Accept quest",kind="goal"})
        local supporting=Common.Render.AddObjective(block,3,{text="Instructions",kind="tip",role="support"})
        assert(heading.points.TOPLEFT[1]==block and instruction.points.TOPLEFT[1]==heading,
            "Hidden title moved first goal over its group heading")
        assert(not heading.Dash.shown and instruction.Dash.shown and not supporting.Dash.shown)
        assert(block._awpFirstObjective==instruction and block._awpCheck.points.TOPRIGHT[1]==instruction,
            "Group heading stole the step checkbox")
        assert(block.height==56,"Decorative rows lost their vertical layout slots")
        -- Title-only changes must leave every progress dimension and anchor intact.
        NS.Internal.Appearance={IsEnabled=function()return true end,GetSettings=function()end,GetRGB=function()end,Text=function()end}
        controls.Update(module,22,450)
        local progress=c.progressBar
        local px,py,pw,ph=progress.points.RIGHT[3],progress.points.RIGHT[4],progress:GetWidth(),progress:GetHeight()
        for _,hidden in ipairs({false,true,false,true}) do
            NS.SetGuideTrackerViewerProviderSetting(key,"hideGuideTitle",hidden)
            controls.SetBlockHeaderText(block,"Guide "..key,true)
            controls.Update(module,22,450)
            assert(progress.points.RIGHT[3]==px and progress.points.RIGHT[4]==py
                and progress:GetWidth()==pw and progress:GetHeight()==ph,"Guide title changed header/progress geometry")
            for _,texture in ipairs(progress._awpRoundedBorder) do assert(not texture.shown,"Native rounded border is drawn over Daylight progress") end
        end
        NS.Internal.Appearance=nil
        controls.Update(module,22,450)
        assert(progress._awpRoundedBorder[1].shown,"Turning off Daylight did not restore the native progress border")
        NS.SetGuideTrackerViewerProviderSetting(key,"hideProviderName",true)
        controls.SetModuleHeader(module,key,"Provider "..key)
        assert(module.Header.Text.text=="", "Provider-name setting did not hide the label")
        c.progressBar.scripts.OnEnter(c.progressBar)
        assert(tooltip.title=="Provider "..key and tooltip.line=="22 / 450")
        NS.SetGuideTrackerViewerProviderSetting(key,"hideProviderName",false)
        controls.SetModuleHeader(module,key,"Provider "..key)
        assert(module.Header.Text.text=="Provider "..key)
        c.progressBar.scripts.OnEnter(c.progressBar)
        assert(tooltip.title=="Guide "..key and tooltip.line=="22 / 450")
        -- Dugi updates its progress after setting the block title.
        controls.Update(module,23,450)
        c.progressBar.scripts.OnEnter(c.progressBar)
        assert(tooltip.title=="Guide "..key and tooltip.line=="23 / 450")
        NS.SetGuideTrackerViewerProviderSetting(key,"progressStyle","none")
        controls.Update(module,23,450)
        c.guideBtn.scripts.OnEnter(c.guideBtn)
        assert(tooltip.title=="Guide "..key,"Hidden progress bar made guide name inaccessible")
        controls.SetBlockHeaderText(block,"Sticky: instructions")
        assert(block.HeaderText.text=="Sticky: instructions","Hide title removed a sticky/status heading")
        controls.Update(module,0,0)
        c.progressBar.scripts.OnEnter(c.progressBar)
        assert(tooltip.title=="No active guide","A pooled status retained the previous guide tooltip")
        NS.SetGuideTrackerViewerProviderSetting(key,"hideGuideTitle",false)
        controls.SetBlockHeaderText(block,"Restored guide",true)
        assert(block.HeaderText.text=="Restored guide" and block.HeaderText.height==0)
        -- Width, title, active-label and progress preferences share one layout.
        -- No button escapes the header; centering includes status/collapse.
        for _,hidden in ipairs({false,true}) do
            NS.SetGuideTrackerViewerProviderSetting(key,"hideProviderName",hidden)
            for _,compact in ipairs({false,true}) do
                NS.SetGuideTrackerViewerProviderSetting(key,"compactActiveIndicator",compact)
                for _,style in ipairs({"square","rounded","none"}) do
                    NS.SetGuideTrackerViewerProviderSetting(key,"progressStyle",style)
                    controls.SetModuleHeader(module,key,key)
                    controls.Update(module,22,450)
                    assert(centerY(c.prevBtn)==0 and centerY(c.nextBtn)==0,
                        "Native step arrows diverged from the shared centerline")
                    if style~="none" then
                        assert(centerY(c.progressBar)==0,
                            "Native progress and step-arrow offsets diverged")
                    end
                    c.progressBar._awpRequestedWidth=100
                    for _,width in ipairs({160,180,226,400}) do
                        Common.CustomHost.Layout(container,width)
                        assert(c.prevBtn:GetLeft()>=4-0.001 and c.settingsBtn:GetRight()<=width-4+0.001,
                            "Responsive controls escaped header: "..width.." "..style)
                        checkIndicatorSpacing()
                        local last=module.Header.MinimizeButton:IsShown() and module.Header.MinimizeButton
                            or c.activeIndicator:IsShown() and c.activeIndicator or c.settingsBtn
                        local center=(c.prevBtn:GetLeft()+last:GetRight())/2
                        if hidden then
                            assert(math.abs(center-width/2)<0.001,"Hidden provider name leaves an uneven outer gap")
                        else
                            assert(center>=width/2-0.001,"Visible provider name overlaps the control strip")
                        end
                        if width==400 then
                            if style~="none" then assert(c.progressBar:GetWidth()==100,"Requested bar width was lost after fitting") end
                            assert(c.activeText.shown==not compact,"Requested active label did not return after widening")
                        end
                    end
                end
            end
        end
        -- Ownership alone must reflow the visible strip; inactive text/dot
        -- preferences reserve no space, including when collapse is absent.
        NS.SetGuideTrackerViewerProviderSetting(key,"hideProviderName",true)
        Common.CustomHost.Layout(container,400)
        for _,collapseShown in ipairs({true,false}) do
            if collapseShown then module.Header.MinimizeButton:Show() else module.Header.MinimizeButton:Hide() end
            activeProvider="other"
            NS.SetGuideTrackerViewerProviderSetting(key,"compactActiveIndicator",false)
            controls.SetModuleHeader(module,key,key)
            local inactiveX=c.prevBtn:GetLeft()
            NS.SetGuideTrackerViewerProviderSetting(key,"compactActiveIndicator",true)
            controls.SetModuleHeader(module,key,key)
            assert(c.prevBtn:GetLeft()==inactiveX,"Inactive indicator preference changes header spacing")
            activeProvider=key
            controls.SetModuleHeader(module,key,key)
            assert(c.activeIndicator:IsShown() and c.prevBtn:GetLeft()<inactiveX,
                "Ownership change did not allocate active-indicator space")
            checkIndicatorSpacing()
            local last=collapseShown and module.Header.MinimizeButton or c.activeIndicator
            assert(math.abs((c.prevBtn:GetLeft()+last:GetRight())/2-200)<0.001,
                "Active ownership change uncentered the visible controls")
            activeProvider="other"
            controls.SetModuleHeader(module,key,key)
            assert(not c.activeIndicator:IsShown() and c.prevBtn:GetLeft()==inactiveX,
                "Losing ownership retains indicator space")
        end
        activeProvider="rxp"
        module.Header.MinimizeButton:Show()
        NS.SetGuideTrackerViewerProviderSetting(key,"hideProviderName",false)
        NS.SetGuideTrackerViewerProviderSetting(key,"compactActiveIndicator",true)
        NS.SetGuideTrackerViewerProviderSetting(key,"progressStyle","rounded")
        controls.SetModuleHeader(module,key,key);controls.Update(module,22,450)
        local before=c.settingsBtn.anchorWrites+c.progressBar.anchorWrites
        for _=1,1000 do controls.LayoutHeader(module) end
        assert(c.settingsBtn.anchorWrites+c.progressBar.anchorWrites==before,"Unchanged layout rewrites button anchors")
        -- Daylight bars and button frames share the header's vertical center.
        NS.Internal.Appearance={IsEnabled=function()return true end,GetSettings=function()end,GetRGB=function()end,Text=function()end}
        controls.LayoutHeader(module)
        assert(c.prevBtn.points.RIGHT[4]==0 and c.nextBtn.points.RIGHT[4]==0
            and c.settingsBtn.points.RIGHT[4]==0 and c.progressBar.points.RIGHT[4]==0,
            "Themed border frames use different vertical centers")
        NS.Internal.Appearance.IsEnabled=function(_,facet)return facet=="controls" end
        controls.LayoutHeader(module)
        assert(centerY(c.prevBtn)==0 and centerY(c.nextBtn)==0,
            "Daylight button styling inherits the native arrow offset when progress styling is off")
        NS.Internal.Appearance=nil
    end
end
multipleViewers = false
local module=Common.ModuleFactory.Create({host=host,providerKey="rxp",name="test"})
controls.Create(module,{});controls.SetModuleHeader(module,"rxp","RXP")
assert(not module._awpControls.activeIndicator.shown,"Single Viewer shows an unnecessary active indicator")
NS.SetGuideTrackerViewerProviderSetting("rxp","hideProviderName",true)
controls.SetModuleHeader(module,"rxp","RXP")
local c=module._awpControls
local last=module.Header.MinimizeButton:IsShown() and module.Header.MinimizeButton or c.settingsBtn
assert(math.abs((c.prevBtn:GetLeft()+last:GetRight())/2-module.Header:GetWidth()/2)<0.001,
    "Single-provider controls are not centered")
print("Viewer resizing, six-provider title/tooltip settings, checkbox preservation and active-dot reuse passed")

-- Provider-defined actions reuse the same strip on every host, around progress.
function Frame:Enable() self.enabled=true; self.enableWrites=(self.enableWrites or 0)+1 end
function Frame:Disable() self.enabled=false; self.enableWrites=(self.enableWrites or 0)+1 end
for _,hostID in ipairs({"blizzard","kaliel","ellesmere","daylight"}) do
    kt=hostID=="kaliel"
    local module=Common.ModuleFactory.Create({host=host,providerKey="questierouter",name="task"})
    local snapshot={state="ready",canChooseTask=true,pinned=false}
    local c=controls.Create(module,{
        previousAtlas="common-search-magnifyingglass",nextAtlas="common-icon-rotateleft",
        previousEnabled=function(s)return s and s.canChooseTask end,
        nextEnabled=function(s)return s and s.pinned end, progressUnit="quests"})
    assert(c.prevBtn:GetNormalTexture().atlas=="common-search-magnifyingglass")
    assert(c.nextBtn:GetNormalTexture().atlas=="common-icon-rotateleft")
    for _,hide in ipairs({false,true}) do
        NS.SetGuideTrackerViewerProviderSetting("questierouter","hideProviderName",hide)
        for _,style in ipairs({"square","rounded"}) do
            NS.SetGuideTrackerViewerProviderSetting("questierouter","progressStyle",style)
            for _,width in ipairs({160,180,226,300,400}) do
                module:SetWidth(width)
                controls.SetModuleHeader(module,"questierouter","QuestieRouter")
                controls.Update(module,14,53,26,snapshot)
                assert(c.prevBtn:GetLeft()>=4 and c.settingsBtn:GetRight()<=width-4,hostID.." task buttons escaped header")
                assert(c.prevBtn:GetRight()<c.progressBar:GetLeft() and c.progressBar:GetRight()<c.nextBtn:GetLeft(),
                    hostID.." task controls are not on opposite sides of progress")
                assert(c.prevBtn:IsEnabled() and not c.nextBtn:IsEnabled())
            end
        end
    end
    snapshot.pinned=true;controls.UpdateHeaderActions(module,snapshot)
    assert(c.nextBtn:IsEnabled())
    local writes=(c.prevBtn.enableWrites or 0)+(c.nextBtn.enableWrites or 0)
    local anchors=c.prevBtn.anchorWrites+c.nextBtn.anchorWrites+c.progressBar.anchorWrites
    for _=1,1000 do controls.Update(module,14,53,26,snapshot) end
    assert((c.prevBtn.enableWrites or 0)+(c.nextBtn.enableWrites or 0)==writes,"Unchanged task state repeats enable/disable work")
    assert(c.prevBtn.anchorWrites+c.nextBtn.anchorWrites+c.progressBar.anchorWrites==anchors,"Unchanged task headers rewrite anchors")
end
print("Task header controls: four hosts, opposite-side actions, widths/styles and unchanged-state caching passed")

for _,hostID in ipairs({"blizzard","kaliel","ellesmere","daylight"}) do
    kt=hostID=="kaliel"
    local module=Common.ModuleFactory.Create({host=host,providerKey="questierouter",name="decoration"})
    module.blockOffsetX=20
    local block=frame(module.ContentsFrame);block.offsetX=20
    block:SetPoint("LEFT",module.ContentsFrame,"LEFT",20,0)
    block:SetPoint("RIGHT",module.ContentsFrame,"RIGHT",0,0)
    local decoration=frame(module.ContentsFrame);decoration:SetHeight(80)
    Common.Render.AnchorModuleDecoration(decoration,module,block)
    for _,width in ipairs({160,226,300,400,180}) do
        module:SetWidth(width)
        Common.Render.AnchorModuleDecoration(decoration,module,block)
        assert(decoration:GetLeft()==module.Header:GetLeft() and decoration:GetRight()==module.Header:GetRight(),
            hostID.." decoration does not share header bounds")
        assert(decoration:GetWidth()==width and block:GetWidth()==width-20,"Changed the host's quest indentation")
        assert(decoration.points.TOP[1]==block and decoration:GetHeight()==80,"Lost decoration height/vertical slot")
    end
    local writes=decoration.anchorWrites
    for _=1,1000 do Common.Render.AnchorModuleDecoration(decoration,module,block) end
    assert(decoration.anchorWrites==writes,"Stable decorations rewrite anchors")
    local replacement=frame(module);replacement:SetAllPoints(module);module.Header=replacement
    Common.Render.AnchorModuleDecoration(decoration,module,block)
    assert(decoration.points.LEFT[1]==replacement and decoration.points.RIGHT[1]==replacement,"Header replacement left stale anchors")
    Common.Render.ReleaseModuleDecoration(decoration)
    assert(next(decoration.points)==nil and decoration._awpBlock==nil and decoration._awpDecorationBounds==nil)
    assert(block.offsetX==20 and module.blockOffsetX==20,"Releasing a decoration changed pooled block offsets")
end
print("Full-width decorations: four hosts, symmetric header bounds, preserved quest indentation and cached anchors passed")
