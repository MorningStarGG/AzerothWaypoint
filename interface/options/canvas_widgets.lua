-- ============================================================
-- Settings control factories
-- ============================================================
--
-- Creates settings controls bound to the current canvas section, including
-- reset, preview and layout behavior.

local NS = _G.AzerothWaypointNS
local C = NS.Constants

NS.Internal.Interface = NS.Internal.Interface or {}
NS.Internal.Interface.canvas = NS.Internal.Interface.canvas or {}

local M = NS.Internal.Interface.canvas

function M.CreateWidgets(ctx)
    local CreateFrame = ctx.CreateFrame
    local ColorPickerFrame = ctx.ColorPickerFrame
    local GameTooltip = ctx.GameTooltip
    local CreatePanelButton = ctx.CreatePanelButton
    local CreateDropdownButton = ctx.CreateDropdownButton
    local GetOpts = ctx.GetOpts
    local GetOptionText = ctx.GetOptionText
    local UnpackOptions = ctx.UnpackOptions
    local ShowTip = ctx.ShowTip
    local HideTip = ctx.HideTip
    local ShowHoverPreview = ctx.ShowHoverPreview
    local ShowDropdownOptionPreview = ctx.ShowDropdownOptionPreview
    local RestoreSectionPreview = ctx.RestoreSectionPreview
    local AddSettingMarkerTag = ctx.AddSettingMarkerTag
    local RefreshActiveSection = ctx.RefreshActiveSection
    local RecordSettingAnchor = ctx.RecordSettingAnchor or function(_) end
    local GetScrollChild = ctx.GetScrollChild
    local GetCursorY = ctx.GetCursorY
    local SetCursorY = ctx.SetCursorY

    local PAD = ctx.PAD
    local SECTION_H = ctx.SECTION_H
    local SPACER_H = ctx.SPACER_H
    local TOGGLE_H = ctx.TOGGLE_H
    local SLIDER_H = ctx.SLIDER_H
    local DROPDOWN_H = ctx.DROPDOWN_H
    local COLOR_H = ctx.COLOR_H
    local COLOR_TEXT_DIM = ctx.COLOR_TEXT_DIM

    local function RefreshSection()
        if type(RefreshActiveSection) == "function" then
            RefreshActiveSection()
        end
    end

    local function SameValue(value, default)
        if type(value) ~= type(default) then return false end
        if type(value) == "number" then
            -- Sliders and color pickers can round-trip through float values.
            return math.abs(value - default) < 0.000001
        end
        if type(value) ~= "table" then return value == default end
        for key, item in pairs(value) do
            if not SameValue(item, default[key]) then return false end
        end
        for key in pairs(default) do
            if value[key] == nil then return false end
        end
        return true
    end

    local function AddReset(label, y, getter, setter, default, format, afterReset)
        local page = GetScrollChild()
        local button
        local function SetValue(value)
            if GetScrollChild() ~= page then return false end
            setter(value)
            if GetScrollChild() ~= page then return false end
            if button then button.Refresh() end
            return true
        end
        if not default then return nil, SetValue end
        button = CreateFrame("Button", nil, page)
        button:SetSize(20, 20)
        button:SetPoint("TOPRIGHT", GetScrollChild(), "TOPRIGHT", -PAD, -y - 2)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("CENTER")
        icon:SetAtlas("common-icon-rotateleft", false)
        local function Tint(role)
            local r, g, b
            if role == "ACCENT" then r, g, b = 1, 0.82, 0 else r, g, b = 0.72, 0.66, 0.58 end
            icon:SetVertexColor(r, g, b, 1)
        end
        Tint("LABEL")
        button.icon = icon
        local function Update()
            if SameValue(getter(), default()) then button:Hide() else button:Show() end
        end
        button.Refresh = Update
        button:SetScript("OnEnter", function(self)
            Tint("ACCENT")
            local value = default()
            ShowTip(self, "Reset " .. label, "Default: " .. (format and format(value) or tostring(value))
                .. "\nRestore this setting's default value. Other settings are unchanged.")
        end)
        button:SetScript("OnLeave", function() Tint("LABEL"); HideTip() end)
        button:SetScript("OnClick", function()
            if GetScrollChild() ~= page or not SetValue(default()) then return end
            HideTip()
            if afterReset then afterReset() else RefreshSection() end
        end)
        if NS.Internal.Appearance then
            NS.Internal.Appearance.RegisterVisual(button, {kind="reset",target=icon,regions={icon}})
        end
        Update()
        return button, SetValue
    end

    -- ============================================================
    -- Section text and buttons
    -- ============================================================

    local function SectionHeader(text)
        local scrollChild = GetScrollChild()
        local y = GetCursorY()

        local lbl = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetTextColor(1, 0.82, 0, 1)
        lbl:SetText(text:upper())
        if NS.Internal.Appearance then NS.Internal.Appearance.Text(lbl, nil, "TITLE", "shell") end
        lbl:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -y - 8)

        local line = scrollChild:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 0.82, 0, 0.22)
        line:SetHeight(1)
        line:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
        line:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        line:SetPoint("TOP", lbl, "CENTER", 0, 0)
        if NS.Internal.Appearance then NS.Internal.Appearance.Decoration(line) end

        SetCursorY(y + SECTION_H)
        return lbl
    end

    local function Spacer(h)
        SetCursorY(GetCursorY() + (h or SPACER_H))
    end

    local function AddText(text, fontObject, color, indent, gap, existing)
        local scrollChild = GetScrollChild()
        local y = GetCursorY()
        indent = indent or 0

        local fs = existing or scrollChild:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlightSmall")
        local textWidth = math.max(1, (scrollChild:GetWidth() or 0) - (PAD + indent) - PAD)
        fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD + indent, -y)
        fs:SetWidth(textWidth)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        fs:SetMaxLines(0)
        if color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
        fs:SetText(text or "")
        if NS.Internal.Appearance then NS.Internal.Appearance.Text(fs, nil, "TEXT", "colors") end
        if existing then fs:Show() end

        SetCursorY(y + math.max(16, fs:GetStringHeight()) + (gap or 8))
        return fs
    end

    local function AddActionButton(text, width, onClick)
        local btn = CreatePanelButton(GetScrollChild())
        btn:SetSize(width or 118, 24)
        btn:SetDisplayText(text)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    -- ============================================================
    -- Toggle and slider controls
    -- ============================================================

    local function AddToggle(label, tooltip, getter, setter, default, resetScope)
        RecordSettingAnchor(label)
        local scrollChild = GetScrollChild()
        local y = GetCursorY()
        local check = CreateFrame("CheckButton", nil, scrollChild)
        local function RefreshToggle()
            check:SetChecked(getter())
            if NS.Internal.Appearance then NS.Internal.Appearance.UpdateToggle(check) end
        end
        local reset, setValue = AddReset(label, y, getter, setter, default,
            function(value) return value and "On" or "Off" end, resetScope ~= "section" and RefreshToggle)
        check:SetHeight(TOGGLE_H)
        check:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -y)
        -- The row and its reset are separate controls. Leave the reset's hit
        -- area outside the toggle instead of relying on sibling frame order.
        check:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -PAD - (default and 28 or 0), -y)
        local checked = getter()
        check:SetChecked(checked)

        check.rowHighlight = check:CreateTexture(nil, "BACKGROUND")
        check.rowHighlight:SetPoint("TOPLEFT", check, "TOPLEFT", -4, -1)
        check.rowHighlight:SetPoint("BOTTOMRIGHT", check, "BOTTOMRIGHT", 4, 1)
        check.rowHighlight:SetColorTexture(1, 0.82, 0, 0.07)
        check.rowHighlight:Hide()

        check.boxBorder = check:CreateTexture(nil, "ARTWORK")
        check.boxBorder:SetSize(14, 14)
        check.boxBorder:SetPoint("LEFT", check, "LEFT", 2, 0)
        check.boxBorder:SetColorTexture(0.72, 0.54, 0.30, 0.78)

        check.boxInset = check:CreateTexture(nil, "ARTWORK")
        check.boxInset:SetPoint("TOPLEFT", check.boxBorder, "TOPLEFT", 2, -2)
        check.boxInset:SetPoint("BOTTOMRIGHT", check.boxBorder, "BOTTOMRIGHT", -2, 2)
        check.boxInset:SetColorTexture(0.020, 0.018, 0.016, 0.96)

        local checkedTex = check:CreateTexture(nil, "OVERLAY")
        checkedTex:SetSize(18, 18)
        checkedTex:SetPoint("CENTER", check.boxBorder, "CENTER", 0, 0)
        checkedTex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        checkedTex:SetVertexColor(1, 0.78, 0.24, 1)
        check:SetCheckedTexture(checkedTex)
        check:SetChecked(checked)

        local pushedTex = check:CreateTexture(nil, "OVERLAY")
        pushedTex:SetAllPoints(check.boxBorder)
        pushedTex:SetColorTexture(1, 0.82, 0, 0.12)
        check:SetPushedTexture(pushedTex)

        local lbl = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", check, "LEFT", 22, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(true)
        lbl:SetMaxLines(0)
        lbl:SetText(label)
        if NS.Internal.Appearance then NS.Internal.Appearance.Text(lbl, nil, "TEXT") end
        check._awpSettingLabel = lbl

        local tag = AddSettingMarkerTag(scrollChild, label)
        if tag then
            tag:SetPoint("RIGHT", check, "RIGHT", -4, 0)
            lbl:SetPoint("RIGHT", tag, "LEFT", -8, 0)
        else
            lbl:SetPoint("RIGHT", check, "RIGHT", -4, 0)
        end

        check:SetScript("OnEnter", function(self)
            local appearance = NS.Internal.Appearance
            local surface = appearance and appearance.FindSurface(self)
            if not (appearance and appearance.StyleOptionHighlight(self.rowHighlight, surface)) then
                self.rowHighlight:SetColorTexture(1, 0.82, 0, 0.07)
            end
            self.rowHighlight:Show()
            ShowTip(self, label, tooltip)
        end)
        check:SetScript("OnLeave", function(self)
            self.rowHighlight:Hide()
            HideTip()
        end)
        check:SetScript("OnClick", function(self)
            local v = self:GetChecked()
            if not setValue(v == true or v == 1) then return end
            if resetScope == "section" then RefreshSection() else RefreshToggle() end
        end)

        if NS.Internal.Appearance then
            NS.Internal.Appearance.RegisterToggle(check, { check.boxBorder, check.boxInset, checkedTex, pushedTex }, lbl, {1,0.82,0,0.07})
        end
        local rowHeight = math.max(TOGGLE_H, lbl:GetStringHeight() + 8)
        if rowHeight > TOGGLE_H then check:SetHeight(rowHeight) end
        if reset then
            check.reset = reset
            reset:ClearAllPoints()
            reset:SetPoint("RIGHT", scrollChild, "TOPRIGHT", -PAD, -y - rowHeight / 2)
        end
        SetCursorY(y + rowHeight)
        return check
    end

    local function AddSlider(label, tooltip, minV, maxV, step, formatter, getter, setter, default, resetScope)
        RecordSettingAnchor(label)
        local scrollChild = GetScrollChild()
        local y = GetCursorY()

        local lbl = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -y - 6)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(label)
        lbl:SetWordWrap(true)
        lbl:SetNonSpaceWrap(true)
        lbl:SetMaxLines(0)
        if NS.Internal.Appearance then NS.Internal.Appearance.Text(lbl, nil, "TEXT") end

        local valText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valText:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -PAD, -y - 6)
        valText:SetJustifyH("RIGHT")

        local tag = AddSettingMarkerTag(scrollChild, label)
        if tag then tag:SetWordWrap(false) end

        -- AWP draws the track and thumb itself. An inherited options backdrop
        -- would remain behind appearance-provider visuals as a second border.
        local slider = CreateFrame("Slider", nil, scrollChild)
        slider:SetOrientation("HORIZONTAL")
        slider:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD + 4, -y - 26)
        slider:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -PAD - 4, -y - 26)
        slider:SetHeight(16)
        slider:SetMinMaxValues(minV, maxV)
        slider._awpSettingLabel = lbl
        slider:SetValueStep(step)
        local record, afterReset
        if resetScope ~= "section" then
            afterReset = function()
                local value = getter()
                slider:SetValue(value)
                -- The skin preserves unfinished input during drag updates.
                -- An explicit reset also replaces the draft in this field.
                local state = record and record.applied and record.currentState
                if state and state.input and state.input:HasFocus() then
                    state.input:SetText(formatter and formatter(value) or tostring(value))
                end
            end
        end
        local reset, setValue = AddReset(label, y, getter, setter, default, formatter, afterReset)
        local trackOuter = slider:CreateTexture(nil, "BACKGROUND")
        trackOuter:SetPoint("TOPLEFT",  slider, "TOPLEFT",  0, -6)
        trackOuter:SetPoint("TOPRIGHT", slider, "TOPRIGHT", 0, -6)
        trackOuter:SetHeight(4)
        trackOuter:SetColorTexture(0.52, 0.35, 0.16, 0.55)

        local trackInner = slider:CreateTexture(nil, "ARTWORK")
        trackInner:SetPoint("TOPLEFT",  slider, "TOPLEFT",  1, -7)
        trackInner:SetPoint("TOPRIGHT", slider, "TOPRIGHT", -1, -7)
        trackInner:SetHeight(2)
        trackInner:SetColorTexture(0.045, 0.033, 0.025, 0.98)

        slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local thumb = slider:GetThumbTexture()
        if thumb then
            thumb:SetSize(8, 18)
            thumb:SetVertexColor(0.88, 0.62, 0.22, 0.95)
        end

        local function LayoutRow(state)
            local width = scrollChild:GetWidth()
            local labelWidth = lbl:GetUnboundedStringWidth()
            local tagWidth = tag and tag:GetUnboundedStringWidth() or 0
            local valueControl = state and state.input
            local below = state and state.valuePlacement == "below"
            local beside = state and state.valuePlacement == "beside"
            local valueWidth = 0
            if not below and not beside then
                if valueControl then
                    valueWidth = valueControl:GetWidth()
                else
                    local text = valText:GetText()
                    valueWidth = valText:GetUnboundedStringWidth()
                    for _, bound in ipairs({minV, maxV}) do
                        valText:SetText(formatter and formatter(bound) or tostring(bound))
                        valueWidth = math.max(valueWidth, valText:GetUnboundedStringWidth())
                    end
                    valText:SetText(text)
                end
            end
            local valueHeight = valueControl and valueControl:GetHeight() or valText:GetStringHeight()
            local valueGap = valueWidth > 0 and 8 or 0
            local rightInset = PAD + (reset and 28 or 0)
            local available = math.max(1, width - PAD - rightInset - valueWidth - valueGap)
            local stacked = tag and labelWidth + tagWidth + 8 > available
            lbl:SetWidth(math.max(1, available - (tag and not stacked and tagWidth + 8 or 0)))
            local labelHeight = lbl:GetStringHeight()
            local tagHeight = tag and tag:GetStringHeight() or 0
            local primaryHeight = math.max(16, labelHeight, (below or beside) and 0 or valueHeight, not stacked and tagHeight or 0)
            local headerCenterY = -y - 6 - primaryHeight / 2
            lbl:ClearAllPoints()
            lbl:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, headerCenterY + labelHeight / 2)
            if tag then
                tag:ClearAllPoints()
                -- Below/beside value fields have no header value rectangle.
                -- Keep the visible badge anchored to the page in every style.
                if stacked then tag:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -y - 6 - primaryHeight - 2)
                else tag:SetPoint("RIGHT", scrollChild, "TOPRIGHT", -rightInset - valueWidth - valueGap, headerCenterY) end
            end
            valText:ClearAllPoints()
            valText:SetPoint("RIGHT", scrollChild, "TOPRIGHT", -rightInset, headerCenterY)
            if valueControl and not below and not beside then
                valueControl:ClearAllPoints()
                valueControl:SetPoint("RIGHT", scrollChild, "TOPRIGHT", -rightInset, headerCenterY)
            end
            local headerHeight = primaryHeight + (stacked and tagHeight + 2 or 0)
            local trackHeight = beside and math.max(16, valueHeight) or 16
            slider:ClearAllPoints()
            slider:SetHeight(trackHeight)
            slider:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD + 4, -y - 6 - headerHeight - 4)
            slider:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -PAD - 4, -y - 6 - headerHeight - 4)
            return math.max(SLIDER_H, 6 + headerHeight + 4 + trackHeight + (below and valueHeight + 4 or 0) + 10)
        end

        local function refresh()
            local v = slider:GetValue()
            valText:SetText(formatter and formatter(v) or tostring(v))
            if reset then reset.Refresh() end
        end

        slider:SetValue(getter())
        refresh()

        slider:SetScript("OnValueChanged", function(self, v, byUser)
            if byUser then setValue(v) end
            refresh()
        end)
        if NS.Internal.Controller then NS.Internal.Controller.Slider(slider, label, step, setValue) end

        if tooltip then
            slider:SetScript("OnEnter", function(self)
                ShowTip(self, label, tooltip)
            end)
            slider:SetScript("OnLeave", HideTip)
        end

        if default then
            slider.reset = reset
        end
        local appearance = NS.Internal.Appearance
        record = appearance and appearance.RegisterSlider(slider, { trackOuter, trackInner, thumb },
            getter, setValue, minV, maxV, step, formatter, valText)
        -- Page construction sets vertical positions once. Value and size events
        -- must never replace the focused controls when native geometry settles.
        SetCursorY(y + LayoutRow(record and record.applied and record.currentState))
        return slider
    end

    -- ============================================================
    -- Dropdowns and editable lists
    -- ============================================================

    local function AddDropdown(label, tooltip, optionsFunc, getter, setter, default, resetScope)
        RecordSettingAnchor(label)
        local scrollChild = GetScrollChild()
        local y = GetCursorY()

        local lbl = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -y - 6)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(label)
        if NS.Internal.Appearance then NS.Internal.Appearance.Text(lbl, nil, "TEXT") end

        local tag = AddSettingMarkerTag(scrollChild, label)
        if tag then tag:SetPoint("LEFT", lbl, "RIGHT", 8, 0) end

        local btn = CreateDropdownButton(scrollChild)
        btn._awpSettingLabel = lbl
        btn:SetHeight(22)
        btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -y - 24)
        btn:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -PAD, -y - 24)

        local function refresh()
            btn:SetDisplayText(GetOptionText(optionsFunc, getter()))
        end
        local function AfterReset()
            if M.Dropdown and M.Dropdown.Close then M.Dropdown.Close(btn) end
            refresh()
        end
        local reset, setValue = AddReset(label, y, getter, setter, default,
            function(value) return GetOptionText(optionsFunc, value) end, resetScope ~= "section" and AfterReset)
        refresh()

        if tooltip then
            btn:HookScript("OnEnter", function(self) ShowTip(self, label, tooltip) end)
            btn:HookScript("OnLeave", HideTip)
        end

        btn:SetScript("OnClick", function(self)
            if not (M.Dropdown and M.Dropdown.Open) then return end
            M.Dropdown.Open(self, {
                label = label,
                options = UnpackOptions(optionsFunc),
                currentValue = getter(),
                width = self:GetWidth(),
                onHover = function(opt)
                    ShowDropdownOptionPreview(label, opt.value, opt.text)
                end,
                onLeave = RestoreSectionPreview,
                onSelect = function(value)
                    if not setValue(value) then return end
                    if resetScope == "section" then RefreshSection() return end
                    refresh()
                    RestoreSectionPreview()
                end,
            })
        end)

        btn.reset = reset

        SetCursorY(y + DROPDOWN_H)
        return btn
    end

    local function AddTextInputList(label, tooltip, placeholder, listGetter, addEntry, removeEntry, clearEntries)
        RecordSettingAnchor(label)
        local scrollChild = GetScrollChild()
        local y = GetCursorY()
        local list = type(listGetter) == "function" and listGetter() or {}

        local lbl = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -y - 5)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(label)
        if NS.Internal.Appearance then NS.Internal.Appearance.Text(lbl, nil, "TEXT") end

        local tag = AddSettingMarkerTag(scrollChild, label)
        if tag then tag:SetPoint("LEFT", lbl, "RIGHT", 8, 0) end

        local edit = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
        edit:SetAutoFocus(false)
        edit:SetHeight(22)
        edit:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD + 4, -y - 25)
        edit:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -PAD - 126, -y - 25)
        edit:SetFontObject("GameFontHighlightSmall")
        edit:SetMaxLetters(64)
        edit:SetTextInsets(6, 6, 0, 0)

        local hint = edit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("LEFT", edit, "LEFT", 8, 0)
        hint:SetPoint("RIGHT", edit, "RIGHT", -8, 0)
        hint:SetJustifyH("LEFT")
        hint:SetText(placeholder or "Addon name")

        local function refreshHint()
            if edit:GetText() == "" and not edit:HasFocus() then
                hint:Show()
            else
                hint:Hide()
            end
        end

        local function commit()
            local text = edit:GetText()
            if type(addEntry) == "function" and text ~= "" then
                addEntry(text)
                edit:SetText("")
                edit:ClearFocus()
                RefreshSection()
            end
        end

        edit:SetScript("OnEditFocusGained", refreshHint)
        edit:SetScript("OnEditFocusLost", refreshHint)
        edit:SetScript("OnTextChanged", refreshHint)
        edit:SetScript("OnEnterPressed", commit)
        edit:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            self:ClearFocus()
        end)
        refreshHint()

        local addBtn = CreatePanelButton(scrollChild)
        addBtn:SetSize(54, 22)
        addBtn:SetPoint("LEFT", edit, "RIGHT", 8, 0)
        addBtn:SetDisplayText("Add")
        addBtn:SetScript("OnClick", commit)

        local clearBtn = CreatePanelButton(scrollChild)
        clearBtn:SetSize(58, 22)
        clearBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
        clearBtn:SetDisplayText("Clear")
        clearBtn:SetScript("OnClick", function()
            if type(clearEntries) == "function" then
                clearEntries()
                RefreshSection()
            end
        end)

        if tooltip then
            edit:SetScript("OnEnter", function(self) ShowTip(self, label, tooltip) end)
            edit:SetScript("OnLeave", HideTip)
            addBtn:HookScript("OnEnter", function(self) ShowTip(self, label, tooltip) end)
            addBtn:HookScript("OnLeave", HideTip)
            clearBtn:HookScript("OnEnter", function(self) ShowTip(self, label, tooltip) end)
            clearBtn:HookScript("OnLeave", HideTip)
        end

        local rowY = y + 54
        if #list == 0 then
            local empty = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            empty:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD + 6, -rowY)
            empty:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
            empty:SetJustifyH("LEFT")
            empty:SetText("No entries.")
            rowY = rowY + 18
        else
            for _, addonName in ipairs(list) do
                local row = CreateFrame("Frame", nil, scrollChild)
                row:SetHeight(24)
                row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -rowY)
                row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -PAD, -rowY)

                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.bg:SetColorTexture(0.035, 0.028, 0.022, 0.70)

                local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                text:SetPoint("LEFT", row, "LEFT", 8, 0)
                text:SetPoint("RIGHT", row, "RIGHT", -76, 0)
                text:SetJustifyH("LEFT")
                text:SetText(tostring(addonName))

                local removeBtn = CreatePanelButton(row)
                removeBtn:SetSize(66, 20)
                removeBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
                removeBtn:SetDisplayText("Remove")
                removeBtn:SetScript("OnClick", function()
                    if type(removeEntry) == "function" then
                        removeEntry(addonName)
                        RefreshSection()
                    end
                end)

                rowY = rowY + 26
            end
        end

        SetCursorY(rowY + 4)
        return edit
    end

    local function AddRecentAddonCallerList(label, tooltip, listGetter, allowEntry, denyEntry, clearEntries)
        RecordSettingAnchor(label)
        local scrollChild = GetScrollChild()
        local y = GetCursorY()
        local list = type(listGetter) == "function" and listGetter() or {}

        local lbl = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -y - 5)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(label)
        if NS.Internal.Appearance then NS.Internal.Appearance.Text(lbl, nil, "TEXT") end

        local clearBtn = CreatePanelButton(scrollChild)
        clearBtn:SetSize(96, 22)
        clearBtn:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -PAD, -y - 1)
        clearBtn:SetDisplayText("Clear Recent")
        clearBtn:SetScript("OnClick", function()
            if type(clearEntries) == "function" then
                clearEntries()
                RefreshSection()
            end
        end)

        if tooltip then
            clearBtn:HookScript("OnEnter", function(self) ShowTip(self, label, tooltip) end)
            clearBtn:HookScript("OnLeave", HideTip)
        end

        local rowY = y + 30
        if #list == 0 then
            local empty = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            empty:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD + 6, -rowY)
            empty:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
            empty:SetJustifyH("LEFT")
            if COLOR_TEXT_DIM then
                empty:SetTextColor(COLOR_TEXT_DIM[1], COLOR_TEXT_DIM[2], COLOR_TEXT_DIM[3], 0.9)
            end
            empty:SetText("No unknown addon waypoint calls detected this session.")
            rowY = rowY + 22
        else
            for _, entry in ipairs(list) do
                local row = CreateFrame("Frame", nil, scrollChild)
                row:SetHeight(34)
                row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -rowY)
                row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -PAD, -rowY)

                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.bg:SetColorTexture(0.035, 0.028, 0.022, 0.70)

                local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                name:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -4)
                name:SetPoint("RIGHT", row, "RIGHT", -150, 0)
                name:SetJustifyH("LEFT")
                name:SetText(tostring(entry.addonName or "-"))

                local detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
                detail:SetPoint("RIGHT", row, "RIGHT", -150, 0)
                detail:SetJustifyH("LEFT")
                detail:SetText(string.format(
                    "%s, %s, %d calls",
                    tostring(entry.lastApiKind or "unknown"),
                    tostring(entry.lastDecision or "-"),
                    tonumber(entry.count) or 0
                ))

                local allowBtn = CreatePanelButton(row)
                allowBtn:SetSize(54, 22)
                allowBtn:SetPoint("RIGHT", row, "RIGHT", -62, 0)
                allowBtn:SetDisplayText("Allow")
                allowBtn:SetScript("OnClick", function()
                    if type(allowEntry) == "function" then
                        allowEntry(entry.addonName)
                        RefreshSection()
                    end
                end)

                local denyBtn = CreatePanelButton(row)
                denyBtn:SetSize(54, 22)
                denyBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
                denyBtn:SetDisplayText("Block")
                denyBtn:SetScript("OnClick", function()
                    if type(denyEntry) == "function" then
                        denyEntry(entry.addonName)
                        RefreshSection()
                    end
                end)

                rowY = rowY + 38
            end
        end

        SetCursorY(rowY + 4)
    end

    -- ============================================================
    -- Ordered lists
    -- ============================================================

    local function AddReorderList(label, getter, setter, default, getLabel)
        RecordSettingAnchor(label)
        local page = GetScrollChild()
        local order = getter()
        local _, setValue = AddReset(label, GetCursorY(), getter, setter, default, function(values)
            local labels = {}
            for index, key in ipairs(values) do labels[index] = getLabel(key) end
            return table.concat(labels, ", ")
        end)
        AddText("Drag a guide up or down to change its tracker position.", "GameFontHighlightSmall", COLOR_TEXT_DIM)

        local rowHeight = 24
        local list = CreateFrame("Frame", nil, page)
        list:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -GetCursorY())
        list:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, -GetCursorY())
        list:SetHeight(rowHeight * #order)
        local marker = list:CreateTexture(nil, "OVERLAY")
        marker:SetHeight(2)
        marker:SetColorTexture(1, 0.82, 0, 1)
        marker:Hide()

        local rows = {}
        local dragIndex, markerIndex
        local function DropIndex()
            local left, bottom, width, height = list:GetRect()
            if not left then return end
            local x, y = GetCursorPosition()
            local scale = list:GetEffectiveScale()
            x, y = x / scale, y / scale
            local viewport = page:GetParent()
            local viewBottom, viewTop = viewport:GetBottom(), viewport:GetTop()
            if not viewBottom or not viewTop then return end
            if x < left or x > left + width or y < bottom or y > bottom + height
                or y < viewBottom or y > viewTop then return end
            return math.min(#order, math.floor((bottom + height - y) / rowHeight) + 1)
        end

        local function EndDrag()
            list:SetScript("OnUpdate", nil)
            marker:Hide()
            dragIndex, markerIndex = nil, nil
        end
        list:SetScript("OnHide", EndDrag)

        local function UpdateMarker()
            local index = DropIndex()
            if index == markerIndex then return end
            markerIndex = index
            if not index or index == dragIndex then marker:Hide(); return end
            local before = index < dragIndex
            local edge, y = before and "TOP" or "BOTTOM", before and 1 or -1
            marker:ClearAllPoints()
            marker:SetPoint("LEFT", rows[index], edge .. "LEFT", 0, y)
            marker:SetPoint("RIGHT", rows[index], edge .. "RIGHT", 0, y)
            marker:Show()
        end

        local function ShowOrder()
            for index, key in ipairs(order) do rows[index].label:SetText(getLabel(key)) end
            local pad = NS.Internal.Controller
            if pad then
                local byKey = {}
                for index, key in ipairs(order) do byKey[key] = rows[index] end
                local function Preview(values)
                    for index, key in ipairs(values) do
                        local item = byKey[key]
                        item:ClearAllPoints()
                        item:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * rowHeight)
                        item:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -(index - 1) * rowHeight)
                    end
                end
                for index, key in ipairs(order) do
                    pad.Reorder(rows[index], { key = key, label = getLabel(key), get = getter, preview = Preview,
                        set = function(values) if setValue(values) then RefreshSection() end end })
                end
            end
        end

        for index = 1, #order do
            local row = CreateFrame("Button", nil, list)
            row:SetHeight(rowHeight - 2)
            row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * rowHeight)
            row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -(index - 1) * rowHeight)
            row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
            row:EnableMouse(true)
            row:RegisterForDrag("LeftButton")

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.035, 0.028, 0.022, 0.70)
            for offset = -3, 3, 3 do
                local grip = row:CreateTexture(nil, "ARTWORK")
                grip:SetSize(10, 1)
                grip:SetPoint("LEFT", row, "LEFT", 8, offset)
                grip:SetColorTexture(0.72, 0.66, 0.58, 1)
                if NS.Internal.Appearance then NS.Internal.Appearance.Decoration(grip) end
            end
            local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("LEFT", row, "LEFT", 26, 0)
            text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            text:SetJustifyH("LEFT")
            if NS.Internal.Appearance then NS.Internal.Appearance.Text(text, nil, "TEXT") end
            row.label = text
            rows[index] = row
            row:SetScript("OnDragStart", function()
                dragIndex = index
                list:SetScript("OnUpdate", UpdateMarker)
            end)
            row:SetScript("OnDragStop", function()
                local from = dragIndex
                local to = from and DropIndex()
                EndDrag()
                if not from or not to or from == to then return end
                local key = table.remove(order, from)
                table.insert(order, to, key)
                if setValue(order) then
                    order = getter()
                    ShowOrder()
                end
            end)
        end
        ShowOrder()
        SetCursorY(GetCursorY() + list:GetHeight() + 4)
        return list
    end

    -- ============================================================
    -- Color controls
    -- ============================================================

    local function AddColorRow(label, tooltip, modeGetter, modeSetter, customGetter, customSetter, refreshFn, plain, defaultMode, defaultColor, modeOptions)
        RecordSettingAnchor(label)
        local scrollChild = GetScrollChild()
        local y = GetCursorY()
        local opts = GetOpts()
        local copyColor = opts.CopyColorTable
        local colorModeOpts = modeOptions or opts.CreateWorldOverlayColorModeOptions

        local lbl = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -y - 6)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(label)
        if NS.Internal.Appearance then NS.Internal.Appearance.Text(lbl, nil, "TEXT") end

        local tag = AddSettingMarkerTag(scrollChild, label)
        if tag then tag:SetPoint("LEFT", lbl, "RIGHT", 8, 0) end

        local SWATCH_W = 26
        local swatch = CreateFrame("Button", nil, scrollChild)
        swatch._awpSettingLabel = lbl
        swatch:SetSize(SWATCH_W, 22)
        swatch:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -PAD, -y - 24)

        local swatchBorder = swatch:CreateTexture(nil, "BACKGROUND")
        swatchBorder:SetAllPoints()
        swatchBorder:SetColorTexture(0.62, 0.42, 0.18, 0.75)

        local swatchTex = swatch:CreateTexture(nil, "ARTWORK")
        swatchTex:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
        swatchTex:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)

        local swatchAutoLabel = swatch:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        swatchAutoLabel:SetPoint("CENTER", swatch, "CENTER", 0, 0)
        swatchAutoLabel:SetText("~")
        swatchAutoLabel:SetTextColor(0.72, 0.66, 0.58, 0.85)
        swatchAutoLabel:Hide()

        local function GetEffectiveColor()
            local mode = modeGetter()
            if mode == C.WORLD_OVERLAY_COLOR_CUSTOM then
                local color = customGetter()
                if type(color) == "table" then
                    return color.r or 1, color.g or 1, color.b or 1, 1
                end
                return 0.95, 0.84, 0.44, 1
            end

            local preset = C.WORLD_OVERLAY_COLOR_PRESETS and C.WORLD_OVERLAY_COLOR_PRESETS[mode]
            if preset then
                return preset.r or 1, preset.g or 1, preset.b or 1, 1
            end
            return nil -- Auto: dynamic, no fixed color
        end

        local function refreshSwatch()
            local r, g, b, a = GetEffectiveColor()
            if r then
                swatchTex:SetColorTexture(r, g, b, a or 1)
                swatchAutoLabel:Hide()
            else
                swatchTex:SetColorTexture(0.10, 0.08, 0.06, 0.95)
                swatchAutoLabel:Show()
            end
            if swatch.reset then swatch.reset.Refresh() end
        end

        local ddBtn = CreateDropdownButton(scrollChild)
        ddBtn:SetHeight(22)
        ddBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -y - 24)
        ddBtn:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -(PAD + SWATCH_W + 6), -y - 24)

        if plain then ddBtn:Hide() end
        local function refreshVisibility()
            local mode = modeGetter()
            swatch:SetAlpha((mode == C.WORLD_OVERLAY_COLOR_CUSTOM or mode == C.WORLD_OVERLAY_COLOR_AUTO) and 1 or 0.75)
        end

        local function refreshDD()
            ddBtn:SetDisplayText(GetOptionText(colorModeOpts, modeGetter()))
            refreshVisibility()
            refreshSwatch()
        end
        -- The shared picker can outlive this row or be opened by another addon.
        local pickerEdit
        local function EndPickerEdit()
            local edit = pickerEdit
            pickerEdit = nil
            if edit and ColorPickerFrame.swatchFunc == edit.swatchFunc then ColorPickerFrame:Hide() end
        end
        swatch:HookScript("OnHide", EndPickerEdit)
        if defaultMode then
            swatch.reset = AddReset(label, y, function()
                return { mode = modeGetter(), color = defaultColor and copyColor(customGetter()) }
            end, function(value)
                EndPickerEdit()
                if M.Dropdown and M.Dropdown.Close then M.Dropdown.Close(ddBtn) end
                if value.color and not SameValue(copyColor(customGetter()), value.color) then customSetter(value.color) end
                if modeGetter() ~= value.mode then modeSetter(value.mode) end
                if refreshFn then refreshFn() end
            end, function()
                return { mode = defaultMode(), color = defaultColor and copyColor(defaultColor()) }
            end, function(value)
                local mode = GetOptionText(colorModeOpts, value.mode)
                if not value.color then return mode end
                local color = value.color
                local hex = string.format("#%02X%02X%02X", math.floor(color.r * 255 + 0.5),
                    math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5))
                if plain then return hex end
                return mode .. " (custom color: " .. hex .. ")"
            end, refreshDD)
        end
        refreshDD()

        if tooltip then
            ddBtn:HookScript("OnEnter", function(self) ShowTip(self, label, tooltip) end)
            ddBtn:HookScript("OnLeave", HideTip)
        end

        ddBtn:SetScript("OnClick", function(self)
            if not (M.Dropdown and M.Dropdown.Open) then return end
            M.Dropdown.Open(self, {
                label = label,
                options = UnpackOptions(colorModeOpts),
                currentValue = modeGetter(),
                width = self:GetWidth(),
                getSwatchColor = function(opt)
                    if opt.value == C.WORLD_OVERLAY_COLOR_CUSTOM then
                        return GetEffectiveColor()
                    end
                    local preset = C.WORLD_OVERLAY_COLOR_PRESETS and C.WORLD_OVERLAY_COLOR_PRESETS[opt.value]
                    if preset then
                        return preset.r or 1, preset.g or 1, preset.b or 1, 1
                    end
                    return nil
                end,
                onHover = function(opt)
                    ShowDropdownOptionPreview(label, opt.value, opt.text)
                end,
                onLeave = RestoreSectionPreview,
                onSelect = function(value)
                    if GetScrollChild() ~= scrollChild then return end
                    EndPickerEdit()
                    modeSetter(value)
                    if refreshFn then refreshFn() end
                    refreshDD()
                    RestoreSectionPreview()
                end,
            })
        end)

        swatch:SetScript("OnEnter", function(self) ShowTip(self, label, tooltip) end)
        swatch:SetScript("OnLeave", HideTip)
        swatch:SetScript("OnClick", function()
            if modeGetter() ~= C.WORLD_OVERLAY_COLOR_CUSTOM then return end
            local color = customGetter()
            local safe = copyColor(color)
            local edit = { r = safe.r, g = safe.g, b = safe.b }
            local function ApplyColor(value)
                if pickerEdit ~= edit or GetScrollChild() ~= scrollChild or ColorPickerFrame.swatchFunc ~= edit.swatchFunc then return end
                if SameValue(copyColor(customGetter()), value) then return end
                customSetter(value)
                if refreshFn then refreshFn() end
                refreshSwatch()
            end
            edit.swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                ApplyColor({ r = r, g = g, b = b })
            end
            edit.cancelFunc = function(prev) ApplyColor(copyColor(prev)) end
            pickerEdit = edit
            ColorPickerFrame:SetupColorPickerAndShow(edit)
        end)
        local pad = NS.Internal.Controller
        if pad and NS.IsWoWForever and NS.IsWoWForever() then
            pad.RegisterControl(swatch, { id = "color:" .. label })
            swatch.OnSmartNavClick = function()
                if not pad.Enabled() then return end
                if modeGetter() ~= C.WORLD_OVERLAY_COLOR_CUSTOM then return true end
                EndPickerEdit()
                local color = copyColor(customGetter())
                pad.ShowColor(swatch, label, {color.r, color.g, color.b, color.a}, function(value)
                    if GetScrollChild() ~= scrollChild then return end
                    customSetter({r=value[1], g=value[2], b=value[3], a=color.a ~= nil and value[4] or nil})
                    if refreshFn then refreshFn() end
                    refreshSwatch()
                end)
                return true
            end
        end

        SetCursorY(y + COLOR_H)
        return swatch
    end

    return {
        SectionHeader = SectionHeader,
        Spacer = Spacer,
        AddText = AddText,
        AddActionButton = AddActionButton,
        AddToggle = AddToggle,
        AddSlider = AddSlider,
        AddDropdown = AddDropdown,
        AddTextInputList = AddTextInputList,
        AddRecentAddonCallerList = AddRecentAddonCallerList,
        AddReorderList = AddReorderList,
        AddColorRow = AddColorRow,
        GetScrollChild = GetScrollChild,
        GetCursorY = GetCursorY,
        SetCursorY = SetCursorY,
        RefreshActiveSection = RefreshActiveSection,
        PAD = PAD,
        COLOR_TEXT_DIM = ctx.COLOR_TEXT_DIM,
        COLOR_GOLD = ctx.COLOR_GOLD,
    }
end
