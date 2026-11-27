-- ============================================================
-- Styled control state and restoration
-- ============================================================
--
-- Tracks the original appearance and input state of styled controls so each UI
-- style can be removed cleanly.

local NS = _G.AzerothWaypointNS
local Appearance = NS.Internal.Appearance
local visuals = setmetatable({}, { __mode = "k" })
local reflows = setmetatable({}, { __mode = "k" })
local deferredVisuals = setmetatable({}, { __mode = "k" })
Appearance.visuals = visuals

local function SavePoints(region)
    local points = {}
    if region.GetNumPoints then
        for index = 1, region:GetNumPoints() do points[index] = { region:GetPoint(index) } end
    end
    return points
end

local function RestorePoints(region, points)
    if not points or #points == 0 then return end
    region:ClearAllPoints()
    for _, point in ipairs(points) do region:SetPoint(unpack(point)) end
end

local function ForwardHover(frame, record, override)
    local state = record.applied and record.currentState
    local widget = state and state.widget
    if not widget or widget == frame then return end
    local hovered = override == nil and record.enabled and record.hovered or override == true
    -- A provider increments this only when a native widget method invalidates
    -- its hover state. Ordinary paints keep the cached transition intact.
    local revision = state.hoverRevision
    if record.hoverWidget == widget and record.widgetHovered == hovered
        and record.widgetHoverRevision == revision then
        return
    end
    record.hoverWidget, record.widgetHovered, record.widgetHoverRevision = widget, hovered, revision
    if not hovered and widget.UnlockHighlight then widget:UnlockHighlight() end
    local handler = widget:GetScript(hovered and "OnEnter" or "OnLeave")
    if handler then handler(widget) end
end

local function Restore(record)
    ForwardHover(record.frame, record, false)
    if record.holder then record.holder:Hide() end
    local current = record.currentState
    if current then
        if current.widget then current.widget:Hide() end
        if current.bar then current.bar:Hide() end
        if current.root then current.root:Hide() end
    end
    if not record.applied then return end
    for region, alpha in pairs(record.alpha) do
        region:SetAlpha(alpha)
        record.alpha[region] = nil
    end
    if record.valueText then record.valueText:SetAlpha(record.valueAlpha or 1) end
    if record.mouseEnabled ~= nil then
        record.frame:EnableMouse(record.mouseEnabled); record.mouseEnabled = nil
    end
    if record.hiddenTextAlpha ~= nil then
        record.text:SetAlpha(record.hiddenTextAlpha)
        record.hiddenTextAlpha = nil
    end
    if record.highlight and record.highlightOriginal then record.highlight:SetColorTexture(unpack(record
        .highlightOriginal)) end
    if record.label then RestorePoints(record.label, record.labelPoints) end
    if record.kind == "progress" then
        record.frame._awpAppearanceBar, record.frame._awpAppearanceKeepProgressBorder = nil, nil
    end
    for _, tint in ipairs(record.tints or {}) do
        if tint.applied then
            tint.region:SetVertexColor(unpack(tint.original))
            tint.applied = false
        end
    end
    if record.rootAlpha then
        record.frame:SetAlpha(record.rootAlpha); record.rootAlpha = nil
    end
    record.applied = false
end

-- ============================================================
-- Slider text and input
-- ============================================================

local function SyncInputText(input, record)
    local value = record.get()
    local text = record.format and record.format(value) or tostring(value)
    if input:GetText() ~= text then input:SetText(text) end
end

local function HideArtwork(regions, savedAlpha)
    for _, region in ipairs(regions) do
        local alpha = region:GetAlpha()
        if savedAlpha[region] == nil then savedAlpha[region] = alpha end
        if alpha ~= 0 then region:SetAlpha(0) end
    end
end

local function SameSliderValue(record, left, right)
    -- Native sliders and saved settings can round the same step differently.
    return math.abs(left - right) <= record.step * 0.0001
end

local function CommitSliderValue(record, value)
    local saved = record.get()
    if not SameSliderValue(record, value, saved) then
        record.set(value)
        saved = record.get()
    end
    if not SameSliderValue(record, record.frame:GetValue(), saved) then record.frame:SetValue(saved) end
    return saved
end

local function InputBindings(input, record)
    if record.boundInput == input then return end
    record.boundInput = input
    local function Reset(self)
        self:ClearFocus()
        SyncInputText(self, record)
    end
    input:HookScript("OnEditFocusLost", function(self) SyncInputText(self, record) end)
    input:SetScript("OnEscapePressed", Reset)
    input:SetScript("OnEnterPressed", function(self)
        if record.frame.IsEnabled and not record.frame:IsEnabled() then
            Reset(self); return
        end
        local value = tonumber(self:GetText():match("^%s*([%+%-]?[%d%.]+)"))
        if value and record.format and record.format(1):find("100%%") then value = value / 100 end
        if value then
            value = record.min + math.floor((value - record.min) / record.step + 0.5) * record.step
            CommitSliderValue(record, math.max(record.min, math.min(record.max, value)))
        end
        Reset(self)
    end)
end

local function ReadState(record)
    local frame = record.frame
    record.enabled = not frame.IsEnabled or frame:IsEnabled()
    if record.kind == "menuRow" and frame.option and frame.option.disabled then record.enabled = false end
    record.hovered = record.mouseHovered == true or record.controllerFocused == true
    if not record.enabled then record.hovered, record.pressed = false, false end
    if record.kind == "checkbox" then
        local checked = frame:GetChecked()
        record.checked = checked == true or checked == 1
    elseif record.kind == "progress" or record.kind == "slider" then
        record.value = frame:GetValue()
    end
end

local function BindSlider(slider, record)
    if record.boundSlider == slider then return end
    record.boundSlider = slider
    slider:HookScript("OnValueChanged", function(self, value, byUser)
        local state = record.currentState
        if not byUser or record.updating or not record.applied or not record.enabled or state.interactiveSlider ~= self then return end
        local saved = CommitSliderValue(record, value)
        if not SameSliderValue(record, self:GetValue(), saved) then self:SetValue(saved) end
    end)
    for _, event in ipairs({ "OnEnter", "OnLeave" }) do
        slider:HookScript(event, function()
            local handler = record.frame:GetScript(event)
            if handler then handler(record.frame) end
        end)
    end
end

-- ============================================================
-- Applying widget state
-- ============================================================

function Appearance.UpdateVisual(frame)
    local record = visuals[frame]
    if not record or record.updating then return end
    if InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        deferredVisuals[frame] = true
        Appearance.deferred = true; return
    end
    deferredVisuals[frame] = nil
    record.updating = true
    local provider = Appearance.provider
    if record.useNativeArt or not provider or not provider.IsEnabled(record.surface, record.facet)
        or (record.requiresDisclosureSkin and not provider.stylesDisclosure)
        or (record.kind == "sectionHeader" and not provider.stylesSectionHeaders) then
        Restore(record); record.updating = false; return
    end
    if record.provider ~= provider then
        Restore(record)
        record.provider = provider
        record.holders = record.holders or {}
        record.holder = record.holders[provider.id]
    end
    if not record.holder then
        local holder = CreateFrame("Frame", nil, frame)
        holder:EnableMouse(false)
        record.holder, record.holders[provider.id] = holder, holder
        if record.kind == "checkbox" then
            holder:SetPoint("LEFT", record.target or frame, "LEFT")
        else
            holder:SetAllPoints(record.target or frame)
        end
    end
    local holder = record.holder
    -- A skin can contain buttons with styling scripts, but the source frame
    -- owns its action. Only the numeric editor adds a distinct input control.
    holder._awpAppearanceOwner = frame
    local level = math.max(0, frame:GetFrameLevel() - 1)
    if record.kind == "checkbox" or record.kind == "slider" then level = frame:GetFrameLevel() + 1 end
    if holder:GetFrameLevel() ~= level then holder:SetFrameLevel(level) end
    ReadState(record)
    local ok, result = pcall(provider.RenderVisual, holder, record)
    if not ok or not result then
        Restore(record)
        provider.VisualFailed(tostring(result or ("Unavailable visual: " .. record.kind)))
        record.updating = false
        return
    end
    holder._awpAppearanceInput = result.input
    if result.root then result.root:Show() end
    if result.widget then result.widget:Show() end
    if result.bar then result.bar:Show() end
    if record.track and result.scrollTrackColor then
        local track = holder.awpScrollTrack
        if not track then
            track = holder:CreateTexture(nil, "BACKGROUND", nil, -2)
            track:SetAllPoints(record.track)
            holder.awpScrollTrack = track
        end
        track:SetColorTexture(unpack(result.scrollTrackColor))
    end
    local scrollFrame = record.scrollFrame
    local range = scrollFrame and scrollFrame:GetVerticalScrollRange()
    holder:SetShown(type(range) ~= "number" or range > 0)
    HideArtwork(record.regions, record.alpha)
    local styledDisclosure = provider.stylesDisclosure and record.getCollapsed
    if styledDisclosure and record.disclosureRegions then HideArtwork(record.disclosureRegions, record.alpha) end
    if record.kind == "progress" then
        frame._awpAppearanceBar = result.bar
        frame._awpAppearanceKeepProgressBorder = result.keepProgressBorder == true
    end
    if record.label then
        if not record.labelPoints then record.labelPoints = SavePoints(record.label) end
        record.label:SetPoint("LEFT", result.labelEnd or holder, "RIGHT", result.labelGap or 8, 0)
    end
    if record.valueText then
        record.valueAlpha = record.valueAlpha or record.valueText:GetAlpha()
        record.valueText:SetAlpha(0)
    end
    if record.highlight then provider.StyleOptionHighlight(record.highlight, record.surface) end
    if record.text then
        Appearance.Text(record.text, record.surface,
            result.textRole or (not record.enabled and "OFF" or record.selected and "TITLE" or "TEXT"), record.facet,
            result.textKind)
        -- FontString color alpha and region alpha can share native state. Hide
        -- replaced glyphs after applying text styling, not before it.
        if result.hideText then
            if record.hiddenTextAlpha == nil then record.hiddenTextAlpha = record.text:GetAlpha() end
            record.text:SetAlpha(0)
        elseif record.hiddenTextAlpha ~= nil then
            record.text:SetAlpha(record.hiddenTextAlpha)
            record.hiddenTextAlpha = nil
        end
    end
    if result.input then
        InputBindings(result.input, record)
        if result.input:IsEnabled() ~= record.enabled then
            if record.enabled then result.input:Enable() else result.input:Disable() end
        end
        if not result.input:HasFocus() then SyncInputText(result.input, record) end
    end
    if result.interactiveSlider then
        local slider = result.interactiveSlider
        BindSlider(slider, record)
        if record.mouseEnabled == nil then
            record.mouseEnabled = frame:IsMouseEnabled()
            frame:EnableMouse(false)
        end
        if slider:IsEnabled() ~= record.enabled then slider:SetEnabled(record.enabled) end
        if not SameSliderValue(record, slider:GetValue(), record.value) then slider:SetValue(record.value) end
        if result.value ~= record.value then
            result.value = record.value
            if result.UpdateFill then result.UpdateFill() end
        end
    end
    if record.kind == "slider" and result.fill then
        local fraction = math.max(0, math.min(1, (record.value - record.min) / (record.max - record.min)))
        result.fill:SetWidth(math.max(0.01, frame:GetWidth() * fraction))
    end
    if result.iconColor and record.tints and not styledDisclosure then
        for _, tint in ipairs(record.tints) do
            local r, g, b, a = tint.region:GetVertexColor()
            if not tint.applied or r ~= tint.r or g ~= tint.g or b ~= tint.b or a ~= tint.a then
                tint.original = { r, g, b, a }
            end
            tint.r, tint.g, tint.b = result.iconColor[1], result.iconColor[2], result.iconColor[3]
            tint.a = record.enabled and tint.shade or 0.4
            tint.region:SetVertexColor(tint.r, tint.g, tint.b, tint.a)
            tint.applied = true
        end
    end
    record.applied, record.updating = true, false
    ForwardHover(frame, record)
end

function Appearance.FlushDeferredVisuals()
    for frame in pairs(deferredVisuals) do Appearance.UpdateVisual(frame) end
end

-- ============================================================
-- Mouse and controller interaction
-- ============================================================

-- Visibility and pooled reuse do not guarantee a mouse-leave event. Clear
-- transient state without changing checked/selected values or user settings.
function Appearance.ResetInteraction(frame)
    local record = visuals[frame]
    if not record then return end
    local dirty = record.mouseHovered or record.controllerFocused or record.hovered or record.pressed or record.focused
    record.mouseHovered, record.controllerFocused, record.hovered, record.pressed, record.focused = false, false, false,
        false, false
    if dirty then Appearance.UpdateVisual(frame) end
    ForwardHover(frame, record)
end

function Appearance.SetControllerFocus(frame, focused)
    local record = visuals[frame]
    if not record then return false end
    if not focused then
        if record.controllerFocused or record.mouseHovered or record.hovered or record.pressed then Appearance
                .ResetInteraction(frame) end
    elseif not record.controllerFocused then
        record.controllerFocused = true
        Appearance.UpdateVisual(frame)
        ForwardHover(frame, record)
    end
    return record.applied and record.enabled
end

local function HookState(frame, record, event, key, value)
    frame:HookScript(event, function(_, ...)
        if key then record[key] = value end
        Appearance.UpdateVisual(frame)
        if event == "OnEnter" or event == "OnLeave" then
            ForwardHover(frame, record); return
        end
        local state = record.applied and record.currentState
        local widget = state and state.widget
        local handler = widget and widget:GetScript(event)
        if handler and (record.enabled or event == "OnLeave") then handler(widget, ...) end
    end)
end

function Appearance.RegisterVisual(frame, descriptor)
    if not frame then return end
    local surface = descriptor.surface or Appearance.FindSurface(frame)
    if not surface then return end
    local record = visuals[frame]
    if not record then
        record = { frame = frame, alpha = {}, hovered = false, mouseHovered = false, pressed = false }
        visuals[frame] = record
        for key, value in pairs(descriptor) do record[key] = value end
        record.surface, record.facet, record.regions = surface, descriptor.facet or "shell", descriptor.regions or {}
        if record.kind == "window" or record.kind == "panel" or record.kind == "header" or record.kind == "menu" then
            Appearance.shells[frame] = record
        end
        if frame.HookScript then
            HookState(frame, record, "OnSizeChanged")
            HookState(frame, record, "OnEnter", "mouseHovered", true)
            HookState(frame, record, "OnLeave", "mouseHovered", false)
            frame:HookScript("OnHide", function() Appearance.ResetInteraction(frame) end)
            if record.kind == "button" or record.kind == "close" or record.kind == "dropdown" or record.kind == "checkbox" then
                HookState(frame, record, "OnMouseDown", "pressed", true)
                HookState(frame, record, "OnMouseUp", "pressed", false)
                HookState(frame, record, "OnEnable")
                HookState(frame, record, "OnDisable")
                HookState(frame, record, "PostClick")
            elseif record.kind == "input" then
                HookState(frame, record, "OnEditFocusGained", "focused", true)
                HookState(frame, record, "OnEditFocusLost", "focused", false)
            elseif record.kind == "progress" or record.kind == "slider" then
                HookState(frame, record, "OnValueChanged")
                if record.kind == "slider" then
                    HookState(frame, record, "OnEnable"); HookState(frame, record, "OnDisable")
                end
            end
        end
        if record.scrollFrame then
            record.scrollFrame:HookScript("OnScrollRangeChanged", function()
                Appearance.UpdateVisual(frame)
            end)
        end
    else
        -- Pooled menu rows retain the registration but receive new semantics.
        record.surface = surface
        if descriptor.selected ~= nil then record.selected = descriptor.selected end
        if descriptor.text then record.text = descriptor.text end
        if descriptor.tints then record.tints = descriptor.tints end
        if descriptor.regions and descriptor.regions ~= record.regions then
            for _, region in ipairs(descriptor.regions) do
                local present = false
                for _, current in ipairs(record.regions) do if current == region then
                        present = true; break
                    end end
                if not present then record.regions[#record.regions + 1] = region end
            end
        end
    end
    Appearance.UpdateVisual(frame)
    return record
end

local decorations = setmetatable({}, { __mode = "k" })

-- ============================================================
-- Decorations and layout
-- ============================================================

function Appearance.Decoration(region, surface)
    if not region then return end
    local holder = decorations[region]
    if not holder then
        holder = CreateFrame("Frame", nil, region:GetParent())
        holder:SetAllPoints(region); holder:EnableMouse(false)
        decorations[region] = holder
    end
    Appearance.RegisterVisual(holder, { kind = "decoration", surface = surface, regions = { region } })
end

function Appearance.Shell(frame, surface, regions, facet, kind)
    if not frame then return end
    local record = visuals[frame]
    if record then
        Appearance.UpdateVisual(frame); return record
    end
    return Appearance.RegisterVisual(frame,
        { kind = kind or "panel", surface = surface, regions = regions, facet = facet })
end

function Appearance.RestoreVisuals()
    for _, record in pairs(visuals) do Restore(record) end
end

function Appearance.RefreshVisuals()
    for frame in pairs(visuals) do Appearance.UpdateVisual(frame) end
end

function Appearance.StyleButton(button, surface, facet, useNativeArt)
    if visuals[button] then
        visuals[button].surface = surface or visuals[button].surface
        visuals[button].facet = facet or visuals[button].facet
        visuals[button].useNativeArt = useNativeArt
        Appearance.UpdateVisual(button); return visuals[button]
    end
    local tints = {}
    for _, pair in ipairs({ { "GetNormalTexture", 1 }, { "GetPushedTexture", 0.8 }, { "GetDisabledTexture", 0.4 } }) do
        local region = button[pair[1]] and button[pair[1]](button)
        if region then tints[#tints + 1] = { region = region, shade = pair[2] } end
    end
    return Appearance.RegisterVisual(button,
        {
            kind = "button",
            surface = surface,
            facet = facet or "controls",
            useNativeArt = useNativeArt,
            target = button._awpButtonArtHost,
            regions = button._awpNativeButtonRegions or {},
            tints = tints
        })
end

function Appearance.StyleProgress(bar, surface)
    local texture = bar:GetStatusBarTexture()
    Appearance.RegisterVisual(bar,
        { kind = "progress", surface = surface, facet = "progress", regions = texture and { texture } or {} })
end

function Appearance.RegisterToggle(check, regions, label, highlightColor)
    Appearance.RegisterVisual(check, {
        kind = "checkbox",
        target = check.boxBorder,
        regions = regions,
        label = label,
        highlight = check.rowHighlight,
        highlightOriginal = highlightColor
    })
end

function Appearance.UpdateToggle(check) Appearance.UpdateVisual(check) end

function Appearance.RegisterSlider(slider, regions, get, set, min, max, step, format, valueText)
    return Appearance.RegisterVisual(slider, {
        kind = "slider",
        regions = regions,
        get = get,
        set = set,
        min = min,
        max = max,
        step = step,
        format = format,
        valueText = valueText
    })
end

function Appearance.StyleOptionsDropdown(button)
    Appearance.RegisterVisual(button, {
        kind = "dropdown",
        text = button.label,
        regions = { button.bg, button.border, button.inset, button.arrow }
    })
end

function Appearance.RegisterReflow(frame, callback)
    reflows[frame] = { callback = callback, surface = Appearance.FindSurface(frame) }
end

function Appearance.Reflow(changed)
    for frame, record in pairs(reflows) do
        if frame:IsShown() and (changed(record.surface)
                or record.surface == "windows.options" and (changed("windows.search") or changed("plaque", "shell"))) then
            record.callback(frame)
        end
    end
end
