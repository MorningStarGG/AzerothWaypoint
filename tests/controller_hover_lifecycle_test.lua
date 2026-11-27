local f=assert(loadfile("tests/controller_fixture.lua"))()
local NS,Pad,Frame=f.NS,f.Pad,f.FrameMethods
function Frame:SetPropagateKeyboardInput() end
function Frame:LockHighlight() self.highlightLocked=true end
function Frame:UnlockHighlight() self.highlightLocked=false end
assert(loadfile("interface/appearance/controller.lua"))()
assert(loadfile("interface/appearance/visuals.lua"))()
local a=NS.Internal.Appearance
local function Provider(id)
    local states={}
    return {id=id,IsEnabled=function() return true end,GetFont=function() end,GetRGB=function() end,
        StyleOptionHighlight=function() end,VisualFailed=function(reason) error(reason) end,
        RenderVisual=function(holder,record)
            local state=states[holder]
            if not state then
                local widget=CreateFrame("Button",nil,holder);widget:EnableMouse(false)
                widget:SetScript("OnEnter",function(self) self.nativeHovered=true;self:LockHighlight() end)
                widget:SetScript("OnLeave",function(self) self.nativeHovered=false;self:UnlockHighlight() end)
                state={widget=widget};states[holder]=state
            end
            state.hovered=record.hovered
            record.currentState=state
            return state
        end}
end
a.provider=Provider("first")
assert(loadfile("interface/framework/panels.lua"))()
assert(loadfile("interface/controller/modal.lua"))()
local button=CreateFrame("Button",nil,UIParent)
local visual=a.RegisterVisual(button,{kind="button",surface="windows.options",selected=true})
button:GetScript("OnEnter")(button);button:GetScript("OnMouseDown")(button)
local old=visual.currentState.widget
assert(visual.hovered and visual.pressed and old.nativeHovered)
button:Hide();button:Show()
assert(not visual.hovered and not visual.pressed and not old.nativeHovered and not old.highlightLocked)
assert(visual.selected,"transient reset cleared semantic selection")
a.SetControllerFocus(button,true);assert(visual.hovered and old.nativeHovered)
a.provider=Provider("second");a.UpdateVisual(button)
assert(not old.nativeHovered and visual.currentState.widget.nativeHovered,"theme switch left cached widget hovered")
a.SetControllerFocus(button,false);assert(not visual.currentState.widget.nativeHovered)
local menus=NS.Internal.Menus
local function Open()
    return menus.CreateContextMenu(UIParent,function(_,menu)
        menu:CreateTitle("Guide")
        menu:CreateButton("Disabled"):SetEnabled(false)
        menu:CreateButton("First action")
        menu:CreateButton("Second action")
    end)
end
for _=1,3 do
    local window=Open()
    local rows=window.rows
    assert(Pad.Modal.GetState().index==3)
    local first,second=a.visuals[rows[3]],a.visuals[rows[4]]
    assert(first.controllerFocused and first.currentState.widget.nativeHovered and not rows[3].focus:IsShown())
    rows[4]:GetScript("OnEnter")(rows[4])
    assert(second.controllerFocused and second.mouseHovered and not first.hovered)
    f.PressKey("PADDUP")
    assert(first.hovered and not second.hovered and not second.currentState.widget.nativeHovered)
    assert(not rows[3].highlightLocked and not rows[4].highlightLocked)
    Pad.Modal.Close("escape")
    for _,pool in pairs(window.rowPools) do for _,row in ipairs(pool) do
        local record=a.visuals[row]
        if row.focus then assert(not record.hovered and not record.pressed and not record.currentState.widget.nativeHovered) end
    end end
end
print("Hidden/reused skin hover, theme changes, semantic selection and single menu focus passed")
