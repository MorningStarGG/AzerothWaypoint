-- ============================================================
-- Controller settings widgets
-- ============================================================
--
-- Maps settings widgets to controller actions for toggles, sliders, reordering
-- and color selection.

local NS = _G.AzerothWaypointNS
local Pad = NS.Internal.Controller

function Pad.ToggleAdjustment(frame)
    if not Pad.Enabled() or InCombatLockdown() then return end
    local record = Pad.controls[frame]
    if not record or not record.adjust then return end
    if Pad.adjusting == frame then
        if record.commit then record.commit() end
        Pad.adjusting = nil
    else
        if record.begin then record.begin() end
        Pad.adjusting = frame
    end
    Pad.RefreshBindings()
end

function Pad.Slider(slider, label, step, setter)
    if not NS.IsWoWForever or not NS.IsWoWForever() then return end
    Pad.RegisterControl(slider, {
        id = "slider:" .. label,
        label = label,
        adjust = function(delta)
            local minimum, maximum = slider:GetMinMaxValues()
            local value = slider:GetValue() + delta * step
            value = minimum + math.floor((value - minimum) / step + 0.5) * step
            value = math.max(minimum, math.min(maximum, value))
            if setter then setter(value) end
            slider:SetValue(value)
        end
    })
    slider.OnSmartNavClick = function()
        if Pad.Enabled() then
            Pad.ToggleAdjustment(slider); return true
        end
    end
end

-- Reordering previews only this list. The settings setter runs once on confirm,
-- so cancelling does not reorder trackers or invalidate the active layout.
function Pad.Reorder(row, options)
    if not NS.IsWoWForever or not NS.IsWoWForever() then return end
    local draft
    Pad.RegisterControl(row, {
        id = "order:" .. options.key,
        label = options.label,
        begin = function()
            draft = {}
            for index, key in ipairs(options.get()) do draft[index] = key end
        end,
        adjust = function(delta)
            if not draft then return end
            for index, key in ipairs(draft) do
                if key == options.key then
                    local target = math.max(1, math.min(#draft, index + delta))
                    draft[index], draft[target] = draft[target], draft[index]
                    options.preview(draft)
                    return
                end
            end
        end,
        commit = function()
            if draft then
                options.set(draft); draft = nil; options.preview(options.get())
            end
        end,
        cancel = function()
            draft = nil; options.preview(options.get())
        end,
        reorder = true
    })
    row.OnSmartNavClick = function()
        if Pad.Enabled() then
            Pad.ToggleAdjustment(row); return true
        end
    end
end

-- ============================================================
-- Color channels and input
-- ============================================================

local function Channel(value) return math.max(0, math.min(255, math.floor((tonumber(value) or 0) * 255 + 0.5))) end
local function Hex(values, alpha)
    local rgb = string.format("%02X%02X%02X", Channel(values[1]), Channel(values[2]), Channel(values[3]))
    return alpha == false and rgb or rgb .. string.format("%02X", Channel(values[4]))
end

function Pad.ParseColor(text)
    text = type(text) == "string" and text:gsub("^#", "") or ""
    if (#text ~= 6 and #text ~= 8) or text:find("[^%x]") then return end
    local color = {}
    for index = 1, #text / 2 do color[index] = tonumber(text:sub(index * 2 - 1, index * 2), 16) / 255 end
    color[4] = color[4] or 1
    return color
end

function Pad.ShowColor(anchor, label, color, setter)
    if not Pad.Enabled() or InCombatLockdown() then return end
    local FW = NS.Internal.Interface.Framework
    local frame = Pad.colorEditor
    if not frame then
        frame = CreateFrame("Frame", "AWPControllerColor", UIParent)
        frame:Hide(); frame:SetSize(420, 340); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG")
        Pad.colorEditor = frame
        frame:SetScript("OnHide", function() frame.setter, frame.anchor = nil, nil end)
        local shell = FW.CreatePanelShell(frame,
            { title = "Choose Color", footerHeight = 46, surface = "windows.options" })
        frame.caption = shell.titleText
        frame.sliders, frame.values, frame.channelLabels, frame.channelValues = {}, { 1, 1, 1, 1 }, {}, {}
        frame.preview = shell.bodyFrame:CreateTexture(nil, "ARTWORK")
        frame.preview:SetPoint("TOPRIGHT", -20, -10); frame.preview:SetSize(60, 28)
        for index, name in ipairs({ "Red", "Green", "Blue", "Alpha" }) do
            local channel = index
            local text = shell.bodyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            text:SetPoint("TOPLEFT", 18, -14 - (index - 1) * 44); text:SetText(name)
            local slider = CreateFrame("Slider", nil, shell.bodyFrame)
            slider:SetPoint("TOPLEFT", 95, -12 - (index - 1) * 44); slider:SetSize(220, 20)
            slider:SetOrientation("HORIZONTAL"); slider:SetMinMaxValues(0, 255); slider:SetValueStep(1)
            slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
            local track = slider:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints(); track:SetColorTexture(0.2, 0.2,
                0.2, 1)
            local value = shell.bodyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            value:SetPoint("LEFT", slider, "RIGHT", 10, 0)
            frame.channelLabels[index], frame.channelValues[index] = text, value
            slider:SetScript("OnValueChanged", function(_, number)
                frame.values[channel] = math.floor(number + 0.5) / 255
                value:SetText(tostring(math.floor(number + 0.5)))
                frame.preview:SetColorTexture(unpack(frame.values))
                if frame.hex and not frame.hex:HasFocus() then frame.hex:SetText(Hex(frame.values, frame.useAlpha)) end
            end)
            Pad.Slider(slider, "Color " .. name, 1)
            frame.sliders[index] = slider
        end
        frame.hex = CreateFrame("EditBox", nil, shell.bodyFrame, "InputBoxTemplate")
        frame.hex:SetSize(160, 24); frame.hex:SetPoint("BOTTOMLEFT", 100, 12); frame.hex:SetAutoFocus(false)
        frame.hex:SetMaxLetters(9)
        frame.hex:SetScript("OnEnterPressed", function(self)
            local values = Pad.ParseColor(self:GetText())
            if values then
                for index = 1, 4 do frame.sliders[index]:SetValue(Channel(values[index])) end
                self:ClearFocus()
            else
                NS.Msg("Enter a color as RRGGBB or RRGGBBAA.")
            end
        end)
        local apply = FW.CreatePanelButton(shell.footerFrame)
        apply:SetSize(120, 28); apply:SetPoint("CENTER", -70, 0); apply:SetDisplayText("Apply")
        apply:SetScript("OnClick", function()
            if not frame.setter then return end
            local values = Pad.ParseColor(frame.hex:GetText())
            if not values then
                NS.Msg("Enter a color as RRGGBB or RRGGBBAA."); return
            end
            local callback = frame.setter
            Pad.Back(frame)
            callback(values)
        end)
        local cancel = FW.CreatePanelButton(shell.footerFrame)
        cancel:SetSize(120, 28); cancel:SetPoint("CENTER", 70, 0); cancel:SetDisplayText("Cancel")
        cancel:SetScript("OnClick", function() Pad.Back(frame) end)
    end
    frame.setter, frame.anchor = setter, anchor
    frame.useAlpha = color[4] ~= nil
    frame:SetHeight(frame.useAlpha and 340 or 300)
    frame.hex:SetMaxLetters(frame.useAlpha and 9 or 7)
    frame.caption:SetText(label)
    for index = 1, 4 do
        frame.values[index] = color[index] or 1
        frame.sliders[index]:SetValue(Channel(frame.values[index]))
        local show = index < 4 or frame.useAlpha
        frame.sliders[index]:SetShown(show); frame.channelLabels[index]:SetShown(show); frame.channelValues[index]
            :SetShown(show)
    end
    frame.preview:SetColorTexture(unpack(frame.values))
    frame.hex:SetText(Hex(frame.values, frame.useAlpha))
    frame:Show()
    Pad.Enter(frame)
end

-- ============================================================
-- Settings navigation
-- ============================================================

-- Settings use logical regions before geometric fallback. A sidebar section
-- enters its own page, disclosure controls and scroll infrastructure are separate.
function Pad.SetSettingsNavigation(root, sidebar, getContent, getSections, getActive)
    local window = Pad.windows[root]
    if not window then return end
    window.navigate = function(source, direction, controls)
        local scrollFrame, sections, activeKey = getContent(), getSections(), getActive()
        local side = source._awpSidebarSection or source._awpSidebarDisclosure
        local inContent = scrollFrame and Pad.Within(source, scrollFrame)
        if side and direction == "RIGHT" then
            for _, candidate in ipairs(controls) do
                if scrollFrame and Pad.Within(candidate, scrollFrame) and Pad.CanFocus(candidate) then return candidate end
            end
            return true
        elseif inContent and direction == "LEFT" then
            return sidebar.buttons[activeKey] or true
        elseif source._awpSidebarSection and direction == "LEFT" then
            return source.disclosure or true
        elseif source._awpSidebarDisclosure and direction == "LEFT" then
            return source._awpSidebarDisclosure
        end
        -- Sidebar movement stays in its own list, disclosures cannot pull
        -- focus diagonally away from the selected section.
        if side and (direction == "UP" or direction == "DOWN") then
            local selected = source._awpSidebarDisclosure or source
            local previous, found
            for _, section in ipairs(sections) do
                local candidate = sidebar.buttons[section.key]
                if candidate and Pad.CanFocus(candidate) then
                    if found and direction == "DOWN" then return candidate end
                    if candidate == selected then
                        if direction == "UP" then return previous or true end
                        found = true
                    end
                    previous = candidate
                end
            end
            return true
        end
    end
end
