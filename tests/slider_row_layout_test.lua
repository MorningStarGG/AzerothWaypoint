local function Check(provider)
    local fixtures = {ellesmere = "tests/ellesmere_appearance_test.lua", gw2ui = "tests/gw2ui_appearance_test.lua"}
    local c = assert(loadfile(fixtures[provider] or "tests/elvui_fixture.lua"))()
    local f, a = c.f, c.a
    if provider == "daylight" then
        f.dispatchSliderEvents=true
        assert(loadfile("interface/appearance/providers/daylight.lua"))()
    end
    f.Fire("PLAYER_LOGIN"); f.Flush()
    a.Select(provider); f.Flush()
    local parent = f.Frame()
    parent:SetWidth(440)
    a.Tag(parent, "windows.options")
    local frame = getmetatable(parent).__index
    function frame:SetJustifyV() end
    function frame:SetValueStep() end
    function frame:SetThumbTexture(texture) self.thumb = self.thumb or f.Frame(self); self.thumb:SetTexture(texture) end
    function frame:GetThumbTexture() return self.thumb end
    function frame:SetOrientation(value) self.orientation = value end
    function frame:SetFrameStrata() end
    function frame:SetClampedToScreen() end
    local y, refreshes, writes, tags = 0, 0, 0, {}
    assert(loadfile("interface/options/canvas_widgets.lua"))()
    local widgets = AzerothWaypointNS.Internal.Interface.canvas.CreateWidgets({
        CreateFrame=CreateFrame, GetScrollChild=function() return parent end,
        GetCursorY=function() return y end, SetCursorY=function(value) y=value end,
        AddSettingMarkerTag=function(owner,label)
            if label == "No marker" then return end
            local tag=owner:CreateFontString(); tag:SetText(label == "Updated" and "UPDATED 4.3" or "NEW 4.3")
            tags[label]=tag; return tag
        end,
        CreateDropdownButton=function(owner)
            local button=f.Frame(owner)
            button.bg, button.label=button:CreateTexture(),button:CreateFontString()
            button.SetDisplayText=function(self,text) self.label:SetText(text) end
            a.StyleOptionsDropdown(button)
            return button
        end,
        GetOptionText=function(_,value) return value end,
        UnpackOptions=function(getOptions) return getOptions() end,
        RestoreSectionPreview=function() end,
        HideTip=function() end,
        RefreshActiveSection=function() refreshes=refreshes+1;parent:Hide() end,
        PAD=16, SLIDER_H=52, DROPDOWN_H=52,
    })
    local function Add(label, resetScope)
        local value=0.85
        local slider=widgets.AddSlider(label,nil,0,1,0.01,function(v) return string.format("%.0f%%",v*100) end,
            function() return value end,function(v) value=assert(tonumber(string.format("%.2f",v)));writes=writes+1 end,
            function() return 1 end, resetScope)
        return slider, a.visuals[slider]
    end
    local slider, record=Add("Plaque Background Opacity")
    local label, tag=slider._awpSettingLabel,tags["Plaque Background Opacity"]
    local function AssertLayout(stacked)
        local state=record.currentState
        local headerValue=record.applied and state and state.valuePlacement~="below" and state.valuePlacement~="beside" and state.input
        local valueWidth=record.applied and not headerValue and 0 or headerValue and headerValue:GetWidth() or 4 * 13 * 0.5
        assert(label:IsShown() and label:GetAlpha()>0 and label.maxLines~=1,"Label was hidden/truncated")
        assert(tag:IsShown() and tag:GetAlpha()>0,"Badge was hidden")
        assert(tag.point[2]==parent and parent:GetWidth()>0 and parent:GetHeight()>0,
            "Badge depends on a hidden or zero-size numeric-value anchor")
        assert(label:GetWidth()>0 and -slider.point[5]>=-label.point[5]+label:GetStringHeight(),"Label overlaps track")
        assert(record.valueText.point[2]==parent and -record.valueText.point[4]==44,"Reset space was not reserved")
        assert((tag.point[1]=="TOPLEFT")==stacked,"Unexpected badge wrapping")
        if stacked then
            assert(-tag.point[5]>=-label.point[5]+label:GetStringHeight(),"Badge overlaps wrapped label")
        else
            local right=parent:GetWidth()+tag.point[4]
            assert(label.point[4]+label:GetWidth()+8<=right-tag:GetUnboundedStringWidth()+0.01,
                "Label overlaps badge or value")
            assert(-tag.point[4]==44+valueWidth+(valueWidth>0 and 8 or 0),"Badge lost value/reset spacing")
        end
        if provider~="awp" then
            local state=assert(record.currentState)
            if provider=="elvui" then
                assert(state.valuePlacement=="below" and state.input.point[2]~=parent,"ElvUI value moved from below track")
            elseif provider=="daylight" then
                assert(state.valuePlacement=="beside" and state.input.point[1]=="RIGHT","Daylight value is not beside its track")
                assert(slider:GetHeight()==22 and not slider:IsMouseEnabled() and state.interactiveSlider:IsMouseEnabled(),
                    "Daylight track does not own the hitbox")
                local gradientFound=false
                for _, region in ipairs(f.frames) do
                    if region:GetParent()==state.interactiveSlider and region.gradient=="daylight-options" then gradientFound=true;break end
                end
                assert(gradientFound,"Slider fill uses the accent instead of native sweep")
            else
                assert(state.input.point[1]=="RIGHT" and state.input.point[2]==parent,"Visible input does not share page bounds")
                if not stacked then assert(-tag.point[4]==44+state.input:GetWidth()+8,"Reserved width uses invisible native text") end
            end
        end
        assert(-slider.point[5]>-tag.point[5],"Track overlaps header/badge")
    end
    AssertLayout(false)
    local initialY=y
    -- Match disabled plaque and appearance-field rows, including their native
    -- dimming. Badges belong to the page header, not the disabled control.
    slider:Disable();slider:SetAlpha(0.45);label:SetAlpha(0.45);a.UpdateVisual(slider)
    AssertLayout(false)
    slider:Enable();slider:SetAlpha(1);label:SetAlpha(1);a.UpdateVisual(slider)
    if provider=="daylight" then
        local state=record.currentState
        local native=state.interactiveSlider
        -- Model the subpixel difference after client geometry settles, while
        -- a dropdown is pressed. A page refresh would hide the click target.
        assert(loadfile("interface/options/canvas_dropdown.lua"))()
        local selected="one"
        local dropdown=widgets.AddDropdown("Test dropdown",nil,function()
            return {{value="one",text="One"},{value="two",text="Two"}}
        end,function() return selected end,function(v) selected=v end)
        local menu=AzerothWaypointNS.Internal.Interface.canvas.Dropdown
        dropdown:GetScript("OnMouseDown")(dropdown,"LeftButton")
        local height=state.input:GetHeight()
        function state.input:GetHeight() return height+0.0001 end
        slider:GetScript("OnSizeChanged")(slider)
        f.Flush()
        assert(dropdown:IsVisible() and refreshes==0,"Settled slider geometry replaced a pressed dropdown")
        dropdown:GetScript("OnMouseUp")(dropdown,"LeftButton")
        dropdown:GetScript("OnClick")(dropdown,"LeftButton")
        assert(menu.popup and menu.popup:IsShown(),"Dropdown did not open after layout settled")
        menu.popup.rows[2]:GetScript("OnClick")(menu.popup.rows[2])
        assert(selected=="two" and not menu.popup:IsShown(),"Dropdown selection did not commit")
        local before=writes
        local enable=native.SetEnabled
        local held=false
        function native:SetEnabled(enabled)
            assert(not held,"Enabled state was rewritten during drag")
            enable(self,enabled)
        end
        local setNativeValue=native.SetValue
        function native:SetValue(value,byUser)
            assert(not held or byUser,"AWP fed the accepted value back into the held slider")
            setNativeValue(self,value,byUser)
        end
        local box=state.input
        local setText=box.SetText
        local textWrites={}
        function box:SetText(text)
            textWrites[#textWrites+1]=text
            setText(self,text)
        end
        native:GetScript("OnMouseDown")(native,"LeftButton")
        held=true
        assert(native.obeyStep and native:GetThumbTexture():GetWidth()==14,"Daylight drag/hover visuals bypassed")
        native:SetValue(0.40000001,true)
        native:SetValue(0.39999999,true)
        f.Flush()
        native:SetValue(0.65,true)
        f.Flush()
        assert(record.get()==0.65 and writes==before+2 and slider:IsVisible(),"Drag did not retain the control and save each change once")
        assert(table.concat(textWrites,",")=="40%,65%","Drag wrote extra or incorrectly formatted values")
        native:GetScript("OnMouseUp")(native,"LeftButton")
        held=false
        a.UpdateVisual(slider)
        assert(#textWrites==2,"Refreshing an unchanged value rewrote the text")
        slider:Disable();a.UpdateVisual(slider);before=writes
        assert(not native:IsEnabled(),"Disabled setting leaves the Daylight slider enabled")
        native:SetValue(0.2,true)
        assert(record.get()==0.65 and writes==before,"Disabled slider changes a setting")
        slider:Enable();a.UpdateVisual(slider)
        box.focus=true;box:SetText("70%")
        textWrites={}
        box:GetScript("OnEnterPressed")(box)
        assert(math.abs(record.get()-0.7)<1e-8 and native:GetValue()==record.get() and writes==before+1,
            "Numeric input did not validate once and sync the track")
        assert(#textWrites==0,"Numeric input rewrote an already correct value")
        box.focus=true;box:SetText("unsaved");box:ClearFocus()
        assert(box:GetText()=="70%" and writes==before+1,"Blur did not restore the saved value")
    end
    Add("Updated")
    assert(tags.Updated.point[1]=="RIGHT" and tags.Updated:IsShown())
    Add("No marker")
    local count=#f.frames
    for _=1,1000 do a.UpdateVisual(slider);slider:GetScript("OnSizeChanged")(slider) end
    f.Flush()
    assert(#f.frames==count and refreshes==0,"Slider size or value updates create frames or rebuild pages")
    f.dispatchSliderEvents = true
    local size, sizeRecord = Add("Navigator Size")
    local state = sizeRecord.applied and sizeRecord.currentState
    local input = state and state.input
    if input then
        input.HasFocus = function(self) return self.focus end
        input.focus = true
        input:SetText("unfinished")
    end
    local beforeReset, frameCount = writes, #f.frames
    size.reset:GetScript("OnClick")(size.reset)
    assert(size:GetValue() == 1 and sizeRecord.get() == 1 and sizeRecord.valueText:GetText() == "100%")
    assert(not size.reset:IsShown() and writes == beforeReset + 1 and #f.frames == frameCount and refreshes == 0)
    if input then assert(input:HasFocus() and input:GetText() == "100%") end
    if state and state.interactiveSlider then assert(state.interactiveSlider:GetValue() == 1) end
    if provider~="awp" then
        a.Select("awp");f.Flush()
        assert(record.valueText:GetAlpha()==1 and not record.holder:IsShown(),"Native value not restored")
        assert(slider:IsMouseEnabled(),"Stock slider mouse input not restored")
        a.Select(provider);f.Flush()
    end
    parent:Hide()
    parent=f.Frame(); parent:SetWidth(240); a.Tag(parent,"windows.options"); y=0
    slider,record=Add("Plaque Background Opacity")
    label,tag=slider._awpSettingLabel,tags["Plaque Background Opacity"]
    AssertLayout(true)
    assert(y>initialY,"Wrapped row does not reserve additional height")
    local providerSlider = Add("Provider appearance setting", "section")
    local before = writes
    providerSlider.reset:GetScript("OnClick")(providerSlider.reset)
    assert(writes == before + 1 and refreshes == 1, "Provider reset must refresh dependent controls once")
end
for _, provider in ipairs({"awp","daylight","ellesmere","elvui","gw2ui"}) do Check(provider) end
print("Slider rows: stable dropdown clicks and Daylight drag, visible badges, wrapping, reset space and disabled/restored states passed")
