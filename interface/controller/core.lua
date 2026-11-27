-- ============================================================
-- Controller navigation
-- ============================================================
--
-- Registers AWP windows and controls and manages their temporary controller
-- input. Blizzard owns the native navigation context and saved bindings.

local NS = _G.AzerothWaypointNS
NS.Internal = NS.Internal or {}

local Pad = { windows = setmetatable({}, { __mode = "k" }), controls = setmetatable({}, { __mode = "k" }) }
NS.Internal.Controller = Pad
local directions = { "UP", "DOWN", "LEFT", "RIGHT" }
local pending = {}
local observer = CreateFrame("Frame")
local serial, queued, handoff = 0, false, false
local function Combat() return InCombatLockdown() end
local function Manager()
    local mode = rawget(_G, "GamepadMode")
    return mode and mode.FrameControlsManager
end
local function Navigation() return rawget(_G, "SmartNavigation") end
local function Visible(frame) return frame and frame:IsVisible() end

-- Capture only ownership/security metadata at UI transitions. No user text,
-- native state writes, protected calls or per-frame tracing are involved.
function Pad.SecuritySnapshot(stage)
    if type(issecurevariable) ~= "function" then return end
    local mode, utility = rawget(_G, "GamepadMode"), rawget(_G, "GamepadSharedUtility")
    local objects = {
        { mode and mode.FrameControlsManager,      "focus",      { "focusedFrame", "shownFrames", "isUIFocused", "popupReturnFrames" } },
        { utility and utility.InputBindingManager, "input",      { "bindingSetStack", "activeBindings", "currentCoreBindingActive", "coreBindingListenerFunctions" } },
        { rawget(_G, "SmartNavigation"),           "navigation", { "activeInfo", "currentButton", "bindingActive" } },
    }
    local report = { stage = stage, problems = {} }
    for _, object in ipairs(objects) do
        if type(object[1]) == "table" then
            for _, field in ipairs(object[3]) do
                local secure, owner = issecurevariable(object[1], field)
                if not secure then
                    report.problems[#report.problems + 1] = object[2] ..
                        "." .. field .. "=" .. tostring(owner)
                end
            end
        end
    end
    Pad.securityHistory = Pad.securityHistory or {}
    if #Pad.securityHistory == 12 then table.remove(Pad.securityHistory, 1) end
    Pad.securityHistory[#Pad.securityHistory + 1] = report
end

function Pad.Available()
    local manager, navigation = Manager(), Navigation()
    local helper = rawget(_G, "SmartNavigationSecureHelper")
    return NS.IsWoWForever and NS.IsWoWForever() and InputUtil and InputUtil.IsGamepadUIEnabled
        and manager and manager.GetActiveFrame and manager.FrameShown and manager.FrameHidden and
        manager.HandlePopupShown and manager.HandlePopupHide
        and navigation and navigation.GetActiveFrame and navigation.GetCurrentButton
        and navigation.SetTargetButtonForFrame and navigation.RefreshButtonGroups and navigation.RegisterCallback
        and helper and helper.SetSecureValue
        and rawget(_G, "SmartNavigation_AddJumpNavigationOverride") and rawget(_G, "SMART_NAV_INPUT_DIRECTION")
        and rawget(_G, "SmartNavigation_IsFrameIgnored")
end

function Pad.Enabled()
    if not Pad.Available() then return false end
    local db = NS.GetDB and NS.GetDB()
    return (not db or db.controllerEnabled ~= false) and InputUtil.IsGamepadUIEnabled()
end

function Pad.Within(frame, root)
    while frame do
        if frame == root then return true end
        frame = frame:GetParent()
    end
    return false
end

function Pad.Root(frame)
    while frame do
        if Pad.windows[frame] then return frame end
        frame = frame:GetParent()
    end
end

-- A guide's controls/actions belong to its module, directional navigation
-- belongs to the tracker containing it. Read the current attachment instead of
-- caching it: docking, host switches and provider order can change at runtime.
local function TrackerContainer(root)
    local window = root and Pad.windows[root]
    local container = window and window.tracker and root.parentContainer
    if container and Pad.Within(root, container) then return container end
end

local function SameTracker(first, second)
    local container = TrackerContainer(first)
    return container ~= nil and container == TrackerContainer(second)
end

local function VisualOwnership(frame)
    local current = frame
    while current and not Pad.windows[current] do
        if current._awpControllerVisualOnly then return current, true end
        if current._awpAppearanceOwner then return current._awpAppearanceOwner, frame ~= current._awpAppearanceInput end
        current = current:GetParent()
    end
end

function Pad.CanFocus(frame)
    if not Visible(frame) or frame.IsEnabled and not frame:IsEnabled() then return false end
    if not frame:IsRectValid() or frame:GetWidth() <= 0 or frame:GetHeight() <= 0 then return false end
    if frame.smartNavigationIgnoredContainerFrame or rawget(_G, "SmartNavigation_IsFrameIgnored")(frame) then return false end
    if frame.GetEffectiveAlpha and frame:GetEffectiveAlpha() <= 0 then return false end
    local record = Pad.controls[frame]
    local owner, visualOnly
    if not record or record.visualOnly == nil then owner, visualOnly = VisualOwnership(frame) end
    if visualOnly then return false end
    owner = owner or record and record.controlOwner
    if owner and owner.IsEnabled and not owner:IsEnabled() then return false end
    if record and record.disabled and record.disabled() then return false end
    return not (record and (record.ignore or record.visualOnly or record.container))
end

local function OwnsFocus(root, active)
    local manager = Manager()
    if manager.isUIFocused == false then return false end
    local owner = manager:GetActiveFrame()
    return owner and (Pad.Within(root, owner) or Pad.Within(active, owner))
end

local function Label(frame)
    local text = frame._awpSettingLabel or frame.label or frame.Text or frame.text
    -- Input contents are user data, not an identity or a navigation label.
    -- Reading a large profile string here would also add needless paste work.
    if frame:IsObjectType("EditBox") then
        local label = frame._awpSettingLabel
        return type(label) == "string" and label or label and label.GetText and label:GetText() or frame:GetName()
    end
    if type(text) == "string" then return text end
    if text and text.GetText then return text:GetText() end
    return frame.GetText and frame:GetText() or frame:GetName()
end

function Pad.SetFlag(frame, key, value)
    if not Pad.Available() then return end
    if Combat() then
        pending[frame] = true; return
    end
    rawget(_G, "SmartNavigationSecureHelper"):SetSecureValue(frame, key, value)
end

local nativeKeys = { "smartNavigationCanFocus", "smartNavigationIgnoredContainerFrame", "smartNavigationIgnored" }
local function ControlFlag(frame, record, key, value)
    if frame[key] == value then return end
    record.modifiedNative[key] = true
    Pad.SetFlag(frame, key, value)
end
local function RestoreControl(frame, record)
    if not record.originalNative then return end
    for _, key in ipairs(nativeKeys) do
        if record.modifiedNative[key] then Pad.SetFlag(frame, key, record.originalNative[key]) end
    end
    for key, original in pairs(record.originalDirections or {}) do Pad.SetFlag(frame, key, original.value) end
    record.navigationInstalled, record.flagsApplied = nil, nil
    record.modifiedNative = {}
end

function Pad.RegisterControl(frame, options)
    if not frame then return end
    if not NS.IsWoWForever or not NS.IsWoWForever() then return end
    local record = Pad.controls[frame] or {}
    Pad.controls[frame] = record
    for key, value in pairs(options or {}) do record[key] = value end
    record.id = record.id or Label(frame)
    if Pad.Enabled() and not Combat() then
        if not record.installed then
            record.installed, record.originalNative, record.modifiedNative = true, {}, {}
            for _, key in ipairs(nativeKeys) do record.originalNative[key] = frame[key] end
            record.originalDirections = {}
        end
        if not record.stateObserved and not record.visualOnly and not record.container then
            record.stateObserved = true
            local function StateChanged()
                if Pad.Enabled() and not Combat() then Pad.RegisterControl(frame) end
                Pad.Request(Pad.Root(frame))
            end
            for _, event in ipairs({ "OnEnable", "OnDisable" }) do
                if frame:HasScript(event) then frame:HookScript(event, StateChanged) end
            end
        end
        local owner = record.controlOwner
        if record.nativeAction then ControlFlag(frame, record, "smartNavigationIgnored", false) end
        local excluded = record.ignore or record.visualOnly or record.container
            or frame.IsEnabled and not frame:IsEnabled() or owner and owner.IsEnabled and not owner:IsEnabled()
            or record.disabled and record.disabled() or not frame:IsRectValid() or frame:GetWidth() <= 0 or
            frame:GetHeight() <= 0
            or rawget(_G, "SmartNavigation_IsFrameIgnored")(frame)
        if not record.navigationInstalled and not excluded then
            record.navigationInstalled = true
            for _, direction in ipairs(directions) do
                local move = direction
                local nativeDirection = rawget(_G, "SMART_NAV_INPUT_DIRECTION")[move]
                local key = "smartNavigationOverride-" .. nativeDirection.dirKey
                if not record.originalDirections[key] then record.originalDirections[key] = { value = frame[key] } end
                rawget(_G, "SmartNavigation_AddJumpNavigationOverride")(frame, nativeDirection, function()
                    return Pad.Navigate(frame, move)
                end)
            end
        elseif excluded and record.navigationInstalled then
            for key, original in pairs(record.originalDirections) do Pad.SetFlag(frame, key, original.value) end
            record.navigationInstalled = nil
        end
        local focusable = not excluded
        ControlFlag(frame, record, "smartNavigationCanFocus", focusable)
        -- A false focus opt-in does not exclude native Buttons. Container-only
        -- exclusion skips this stop without suppressing its genuine editors.
        local containerOnly = excluded and true or record.originalNative.smartNavigationIgnoredContainerFrame
        ControlFlag(frame, record, "smartNavigationIgnoredContainerFrame", containerOnly)
        record.flagsApplied = true
    elseif Pad.Enabled() and Combat() then
        pending[frame] = true
    end
    return record
end

-- ============================================================
-- Tracker traversal
-- ============================================================

local function Collect(root, result, path, visualOwner, visualInput)
    local children = { root:GetChildren() }
    for index, child in ipairs(children) do
        local id = path .. "/" .. index
        local record = Pad.controls[child]
        if not child._awpControllerScrollInfrastructure then
            local owner, input = visualOwner, visualInput
            if child._awpControllerVisualOnly then owner, input = child, nil end
            if child._awpAppearanceOwner then owner, input = child._awpAppearanceOwner, child._awpAppearanceInput end
            -- Skin widgets may have native click scripts even with mouse input
            -- disabled. Only the logical control and its real numeric editor are
            -- navigation targets, a slider's mouse proxy is presentation artwork.
            local visualOnly = owner ~= nil and child ~= input
            local click = child:IsObjectType("Button") and child:GetScript("OnClick")
                or child:GetScript("OnMouseUp") or child:GetScript("OnMouseDown")
            local secureAction = child.GetAttribute and (child:GetAttribute("type") or child:GetAttribute("type1"))
            if record or visualOnly or child:IsObjectType("EditBox") or child.OnSmartNavClick or click or secureAction then
                local identity = record and record.id or Label(child) or id
                if child == input then
                    identity = "input:" ..
                        tostring(Pad.controls[owner] and Pad.controls[owner].id or Label(owner) or id)
                end
                record = Pad.RegisterControl(child,
                    { id = identity, visualOnly = visualOnly, controlOwner = owner or false })
                if record and Pad.CanFocus(child) then result[#result + 1] = child end
            end
            if not Pad.windows[child] then Collect(child, result, id, owner, input) end
        end
    end
end

local function FirstToolbar(window)
    for _, button in ipairs(window.toolbar or {}) do if Pad.CanFocus(button) then return button end end
end

-- AWP's module header wraps a toolbar, it is not a second, full-width button.
-- Native template marks are changed only on these AWP-owned frame instances.
function Pad.RegisterGuideToolbar(root, header, buttons)
    local window = Pad.windows[root]
    if not window then return end
    window.toolbar = buttons
    Pad.RegisterControl(header, { id = "toolbar-container", container = true })
    for index, button in ipairs(buttons) do
        Pad.RegisterControl(button, { id = "toolbar:" .. index, toolbar = true, nativeAction = true })
    end
    window.first = function() return FirstToolbar(window) end
    Pad.Request(root)
end

function Pad.Reveal(frame, root)
    local tracker = TrackerContainer(root)
    local scroll = frame:GetParent()
    while scroll do
        if scroll:IsObjectType("ScrollFrame") and scroll.GetVerticalScroll then
            local scale, viewScale = frame:GetEffectiveScale(), scroll:GetEffectiveScale()
            local top, bottom = frame:GetTop(), frame:GetBottom()
            local custom = NS.Internal.GuideTrackerViewer and NS.Internal.GuideTrackerViewer.CustomHost
            local viewTop, viewBottom
            if custom then
                viewTop, viewBottom = custom.GetScrollViewport(scroll)
            else
                viewTop, viewBottom = scroll:GetTop(), scroll:GetBottom()
            end
            if top and bottom and viewTop and viewBottom then
                local delta = top * scale > viewTop * viewScale and viewTop - top * scale / viewScale
                    or bottom * scale < viewBottom * viewScale and viewBottom - bottom * scale / viewScale or 0
                if delta ~= 0 then
                    if custom then
                        custom.SetScrollOffset(scroll, scroll:GetVerticalScroll() + delta)
                    else
                        scroll:SetVerticalScroll(math.max(0,
                            math.min(scroll:GetVerticalScrollRange(), scroll:GetVerticalScroll() + delta)))
                    end
                end
            end
        end
        if scroll == root and not tracker then break end
        scroll = scroll:GetParent()
    end
end

function Pad.Select(frame, root)
    root = root or Pad.Root(frame)
    if not Pad.Enabled() or Combat() or not root or not Pad.CanFocus(frame) then return false end
    local active = Navigation():GetActiveFrame()
    if not Pad.Within(frame, active) or not OwnsFocus(root, active) then return false end
    Pad.Reveal(frame, root)
    Navigation():SetTargetButtonForFrame(active, frame)
    return true
end

local function Position(frame)
    local x, y = frame:GetCenter()
    if x and y then
        local scale = frame:GetEffectiveScale(); return x * scale, y * scale
    end
end

local function FirstGuideRow(window)
    local first, top
    for _, frame in ipairs(window.controls or {}) do
        local record = Pad.controls[frame]
        if record and record.guide and not record.toolbar and Pad.CanFocus(frame) then
            local _, y = Position(frame)
            if y and (not top or y > top) then first, top = frame, y end
        end
    end
    return first
end

local function ToolbarDestination(window, source, direction)
    if not window.toolbar then return end
    local at
    for index, button in ipairs(window.toolbar) do
        if button == source then
            at = index; break
        end
    end
    if at then
        if direction == "LEFT" or direction == "RIGHT" then
            local step = direction == "LEFT" and -1 or 1
            local index = at + step
            while window.toolbar[index] do
                if Pad.CanFocus(window.toolbar[index]) then return window.toolbar[index] end
                index = index + step
            end
            return true
        elseif direction == "DOWN" then
            return FirstGuideRow(window) or true
        end
    elseif direction == "UP" then
        local first = FirstGuideRow(window)
        if first and Pad.Within(source, first) then
            return window.lastToolbar and Pad.CanFocus(window.lastToolbar) and window.lastToolbar or FirstToolbar(window)
        end
    end
end

function Pad.Navigate(source, direction)
    if Pad.modalActive then return true end
    if not Pad.Enabled() or Combat() then return end
    local record, root = Pad.controls[source], Pad.Root(source)
    local window = root and Pad.windows[root]
    if not window then return end
    local active = Navigation():GetActiveFrame()
    if not Pad.Within(root, active) or not OwnsFocus(root, active) then return end
    if pending[root] then
        pending[root] = nil; Pad.Rebuild(root)
    end
    if record and record.navigate then
        local result = record.navigate(direction)
        if result then return result end
    end
    if Pad.adjusting == source and record and record.adjust then
        if record.reorder then
            if direction == "UP" or direction == "DOWN" then record.adjust(direction == "DOWN" and 1 or -1) end
        elseif direction == "LEFT" or direction == "RIGHT" then
            record.adjust(direction == "RIGHT" and 1 or -1)
        end
        return true
    end
    if window.navigate then
        local target = window.navigate(source, direction, window.controls or {})
        if target then
            if target ~= true then Pad.Reveal(target, root) end
            return target
        end
    end
    local toolbar = ToolbarDestination(window, source, direction)
    if toolbar then
        if toolbar ~= true then Pad.Reveal(toolbar, root) end
        return toolbar
    end
    local x, y = Position(source)
    if not x then return end
    local best, bestRoot, score
    for member, context in pairs(Pad.windows) do
        if (member == root or SameTracker(root, member)) and Visible(member) then
            if not context.controls or pending[member] then
                pending[member] = nil; Pad.Rebuild(member)
            end
            for _, candidate in ipairs(context.controls or {}) do
                if candidate ~= source and Pad.CanFocus(candidate) then
                    local cx, cy = Position(candidate)
                    if cx then
                        local dx, dy = cx - x, cy - y
                        local along = direction == "UP" and dy or direction == "DOWN" and -dy
                            or direction == "LEFT" and -dx or dx
                        local across = (direction == "UP" or direction == "DOWN") and math.abs(dx) or math.abs(dy)
                        if along > 0.5 then
                            local distance = along + across * 3
                            if not score or distance < score then best, bestRoot, score = candidate, member, distance end
                        end
                    end
                end
            end
        end
    end
    if best then
        if not Pad.Within(best, active) then
            -- Returning a foreign module's button would leave native input on
            -- the old root. Transfer the root as well and consume this press.
            Pad.TransferTracker(root, bestRoot, best)
            return true
        end
        Pad.Reveal(best, bestRoot)
        return best
    end
    if active ~= root and Pad.Within(root, active) then
        -- The native tracker can continue into its own quests/controls beyond
        -- the AWP group. Standalone AWP navigation stays within that group.
        return
    end
    return true
end

-- ============================================================
-- Focus order and hints
-- ============================================================

function Pad.Rebuild(root)
    local window = Pad.windows[root]
    if not window or not Pad.Enabled() or Combat() then return end
    local before, id, index = Pad.focus, Pad.focusID, Pad.focusIndex or 1
    local controls = {}
    Collect(root, controls, "")
    window.controls = controls
    local active = Navigation():GetActiveFrame()
    if not Pad.modalActive and active and Pad.Within(root, active) and OwnsFocus(root, active) then
        Navigation():RefreshButtonGroups(active)
        local native = Navigation():GetCurrentButton()
        -- Native scans can already have selected an obsolete skin child. Use
        -- the native selection, not only our last observed focus, to repair it.
        if native and Pad.Root(native) == root and not Pad.CanFocus(native) then
            local replacement
            local nativeRecord = Pad.controls[native]
            if nativeRecord and nativeRecord.container then replacement = FirstToolbar(window) end
            local owner = nativeRecord and nativeRecord.controlOwner
            for _, frame in ipairs(controls) do
                if frame == owner then
                    replacement = frame; break
                end
            end
            if not replacement and Pad.focusRoot == root and before and Pad.CanFocus(before) then replacement = before end
            if not replacement then
                for _, frame in ipairs(controls) do
                    if Pad.controls[frame].id == id then
                        replacement = frame; break
                    end
                end
            end
            replacement = replacement or controls[math.min(index, #controls)]
            if replacement then Pad.Select(replacement, root) end
        end
    end
end

function Pad.Request(root)
    if not Pad.Enabled() then return end
    if root then pending[root] = true end
    if Combat() then return end
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        if Combat() then
            queued = false; return
        end
        local work = pending; pending = {}
        for frame in pairs(work) do
            if Pad.windows[frame] then
                Pad.Rebuild(frame)
            elseif Pad.controls[frame] then
                Pad.RegisterControl(frame)
            end
        end
        queued = false
        Pad.Observe()
        if next(pending) then Pad.Request() end
    end)
end

function Pad.Glyph(key)
    local util = rawget(_G, "InputIconTextureSetUtility")
    if util and util.GetActiveInputIconButtonTextures then
        local textures = util.GetActiveInputIconButtonTextures(key)
        local normal = type(textures) == "table" and textures[1]
        if type(normal) == "string" and CreateAtlasMarkup then return CreateAtlasMarkup(normal, 16, 16) end
    end
    return GetBindingText and GetBindingText(key, "KEY_", true) or key
end

local function Hint(root)
    if Pad.hint then return Pad.hint end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("TOOLTIP"); frame:EnableMouse(false)
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.text:SetPoint("CENTER")
    frame.text:SetWordWrap(true)
    frame.measure = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.measure:SetWordWrap(true); frame.measure:Hide()
    Pad.hint = frame
    return frame
end

local function HintHeight(root, height)
    if not root or root._awpControllerHintHeight == height then return end
    root._awpControllerHintHeight = height
    if root._awpSetControllerHintHeight then
        root._awpSetControllerHintHeight(height)
    elseif Pad.windows[root] and Pad.windows[root].tracker and root.MarkDirty then
        root:MarkDirty()
    end
end

function Pad.ReserveHintSpace(root, height)
    local extra = root._awpControllerHintHeight or 0
    if extra > 0 then root:SetHeight(height + extra) end
    root._awpHintAppliedHeight = extra
    -- This is the shared module layout's acknowledgement, not a timer-based
    -- guess. Paint only after the new space is applied, within the host pass.
    local window = Pad.windows[root]
    if window and window.hintLayout and Pad.focusRoot == root then Pad.UpdateHints() end
    return height + extra
end

function Pad.BeginHintLayout(root)
    local extra = root._awpHintAppliedHeight or 0
    if extra > 0 then root:SetHeight(math.max(0, root:GetHeight() - extra)) end
    root._awpHintAppliedHeight = nil
end

local function MoreAvailable(frame, record)
    return record and record.more and (not record.moreAvailable or record.moreAvailable(frame))
end

function Pad.OwnsBinding(key, target)
    return Pad.router and Pad.router:IsShown()
        and GetBindingAction(key, true) == "CLICK " .. target .. ":LeftButton"
end

function Pad.UpdateHints()
    local root, focus = Pad.focusRoot, Pad.focus
    if not root or not focus or not Pad.Enabled() or Combat() or Pad.modalActive then
        if Pad.hint then Pad.hint:Hide() end
        return
    end
    local hint, record = Hint(root), Pad.controls[focus] or {}
    local window = Pad.windows[root]
    -- A host pass may finish after another native selection. Leave the last
    -- complete presentation intact until the new selection is reconciled.
    if window and window.hintLayout and (Navigation():GetCurrentButton() ~= focus or record.id ~= Pad.focusID) then return end
    local width = math.max(100, root:GetWidth() - 12)
    local tracker = Pad.windows[root] and Pad.windows[root].tracker
    local navRoot = Navigation():GetActiveFrame()
    local nativeFooter = navRoot and navRoot.gamepadFooter
    local nativeLegend = nativeFooter and nativeFooter.inputLegend
    local nativeHints = tracker and nativeLegend and nativeLegend:IsVisible()
    local parts, footprint = {}, {}
    local function Add(text, usable)
        footprint[#footprint + 1] = text
        if usable then parts[#parts + 1] = text end
    end
    if not nativeHints then
        Add(
            Pad.Glyph("PAD1") ..
            (Pad.adjusting == focus and " Finish" or " Select") .. "   " .. Pad.Glyph("PAD2") .. " Back",
            true)
    end
    if MoreAvailable(focus, record) then
        Add(Pad.Glyph("PAD4") .. " More actions",
            Pad.OwnsBinding("PAD4", "AWPControllerMore"))
    end
    if Pad.contextLabel and Pad.contextButton then
        Add(Pad.Glyph("PADRSTICK") .. " " .. Pad.contextLabel, Pad.OwnsBinding("PADRSTICK", Pad.contextButton))
    end
    local text, desired = table.concat(parts, "   "), table.concat(footprint, "   ")
    if hint.measure:GetText() ~= desired then hint.measure:SetText(desired) end
    hint.measure:SetWidth(width)
    -- Binding restacks must not resize the tracker and cause another restack.
    -- Reserve command space independently of which hints can currently show.
    local height = desired ~= "" and math.max(20, hint.measure:GetStringHeight() + 8) or 0
    HintHeight(root, height)
    if window and window.hintLayout and root._awpHintAppliedHeight ~= height then return end
    -- Content, bounds and anchor are one committed presentation. Genuine
    -- resizing remains, it never paints against the previous module height.
    hint.root, hint.identity, hint.context, hint.adjusting = root, Pad.focusID, Pad.contextLabel, Pad.adjusting
    if hint.text:GetText() ~= text then hint.text:SetText(text) end
    hint.text:SetWidth(width)
    hint:ClearAllPoints()
    local anchor = root._awpControllerHintAnchor
    hint:SetPoint("BOTTOM", anchor or root, anchor and "TOP" or "BOTTOM", 0, 0)
    hint:SetSize(width, math.max(1, height)); hint:SetShown(text ~= "")
end

-- ============================================================
-- Temporary input bindings
-- ============================================================

-- Scoped overrides are released by a secure state driver, even if Lua receives
-- PLAYER_REGEN_DISABLED after lockdown starts. The optional action key has its
-- own stable executor and is deliberately not part of these menu bindings.
local function EnsureRouter()
    if Pad.router or Combat() then return Pad.router end
    local router = CreateFrame("Frame", "AWPControllerInput", UIParent,
        "SecureHandlerShowHideTemplate,SecureHandlerStateTemplate")
    router:Hide()
    router:SetAttribute("_onshow", [[
        self:ClearBindings()
        if self:GetAttribute("context") then self:SetBindingClick(true, "PADRSTICK", self:GetAttribute("context"), "LeftButton") end
        if self:GetAttribute("more") then self:SetBindingClick(true, "PAD4", "AWPControllerMore", "LeftButton") end
        if self:GetAttribute("back") then self:SetBindingClick(true, "PAD2", "AWPControllerBack", "LeftButton") end
    ]])
    router:SetAttribute("_onhide", [[ self:ClearBindings() ]])
    router:SetAttribute("_onstate-combat", [[ if newstate == "1" then self:Hide() end ]])
    RegisterStateDriver(router, "combat", "[combat] 1; 0")
    for _, role in ipairs({ "More", "Back" }) do
        local button = CreateFrame("Button", "AWPController" .. role, UIParent)
        button:SetSize(1, 1); button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -1000, -1000); button:EnableMouse(false)
        button:RegisterForClicks("AnyUp")
        button:SetScript("OnClick", function()
            if not Pad.Enabled() or Combat() then return end
            if role == "Back" then
                Pad.Back()
            else
                local focus = Pad.focus
                local record = Pad.controls[focus]
                -- Opening a modal owns suspension. A callback that opens
                -- nothing must not leave the tracker with its input removed.
                if MoreAvailable(focus, record) then record.more(focus) end
            end
            Pad.RefreshBindings()
        end)
    end
    Pad.router = router
    return router
end

function Pad.RefreshBindings()
    if Combat() or Pad.modalActive then return end
    local router = EnsureRouter()
    if not router then return end
    local navigation = Navigation()
    if Pad.focus and (navigation:GetCurrentButton() ~= Pad.focus or not Pad.CanFocus(Pad.focus)
            or not OwnsFocus(Pad.focusRoot, navigation:GetActiveFrame())) then
        Pad.ClearFocus(); return
    end
    local record = Pad.controls[Pad.focus]
    local more, back = MoreAvailable(Pad.focus, record) and true or nil, Pad.adjusting and true or nil
    local active = Pad.Enabled() and Pad.focusRoot and Pad.focus and true or false
    Pad.bindingsDirty = nil
    -- Native navigation can replace a priority override without changing our
    -- row or desired command. Cached attributes alone do not prove ownership.
    local owned = (not more or Pad.OwnsBinding("PAD4", "AWPControllerMore"))
        and (not back or Pad.OwnsBinding("PAD2", "AWPControllerBack"))
        and (not Pad.contextButton or Pad.OwnsBinding("PADRSTICK", Pad.contextButton))
    if router:GetAttribute("context") == Pad.contextButton and router:GetAttribute("more") == more
        and router:GetAttribute("back") == back and router:IsShown() == active and owned then
        Pad.UpdateHints(); return
    end
    router:Hide()
    router:SetAttribute("context", Pad.contextButton)
    router:SetAttribute("more", more)
    router:SetAttribute("back", back)
    if active then router:Show() end
    Pad.UpdateHints()
end

local observedNavigation = setmetatable({}, { __mode = "k" })
function Pad.InvalidateBindings()
    Pad.bindingsDirty = true
    Pad.Request()
end

function Pad.ObserveNavigationBindings()
    if not Pad.Available() then return end
    local navigation = Navigation()
    if observedNavigation[navigation] then return end
    observedNavigation[navigation] = true
    -- Native D-pad movement selects internally, bypassing SetTargetButtonForFrame.
    -- Callbacks only enqueue work: publish after native selection/stack changes.
    navigation:RegisterCallback("SelectedButtonUpdated", Pad.InvalidateBindings, Pad)
    navigation:RegisterCallback("SelectedButtonEnabledStateChanged", function()
        Pad.Request(Pad.Root(navigation:GetCurrentButton()))
    end, Pad)
    hooksecurefunc(navigation, "RefreshButtonGroups", Pad.InvalidateBindings)
end

function Pad.ClearFocus()
    HintHeight(Pad.focusRoot, 0)
    if Pad.adjusting then
        local record = Pad.controls[Pad.adjusting]
        if record and record.cancel then record.cancel() end
    end
    Pad.adjusting, Pad.focus, Pad.focusRoot, Pad.focusID, Pad.contextButton, Pad.contextLabel = nil, nil, nil, nil, nil,
        nil
    Pad.bindingsDirty = nil
    if Pad.router and not Combat() then Pad.router:Hide() end
    if Pad.hint then Pad.hint:Hide() end
end

function Pad.Observe()
    if Pad.modalActive then return end
    if not Pad.Enabled() or Combat() then
        Pad.ClearFocus(); return
    end
    local navigation = Navigation()
    local button = navigation:GetCurrentButton()
    local root = button and Pad.Root(button)
    local active = navigation:GetActiveFrame()
    if not root or not Visible(root) or not Pad.Within(root, active) and active ~= root or not OwnsFocus(root, active) then
        Pad.ClearFocus(); return
    end
    if not Pad.CanFocus(button) then
        Pad.Request(root); return
    end
    local selected = Pad.controls[button]
    if button == Pad.focus and root == Pad.focusRoot and selected and selected.id == Pad.focusID then
        if Pad.bindingsDirty then Pad.RefreshBindings() end
        return
    end
    if Pad.adjusting and Pad.adjusting ~= button then
        local record = Pad.controls[Pad.adjusting]
        if record and record.cancel then record.cancel() end
        Pad.adjusting = nil
    end
    local previousRoot = Pad.focusRoot
    local record = Pad.RegisterControl(button)
    Pad.focus, Pad.focusRoot, Pad.focusID = button, root, record and record.id
    if record and record.toolbar then Pad.windows[root].lastToolbar = button end
    for index, frame in ipairs(Pad.windows[root].controls or {}) do
        if frame == button then
            Pad.focusIndex = index; break
        end
    end
    Pad.contextButton, Pad.contextLabel = nil, nil
    if Pad.OnFocus then Pad.OnFocus(button, record) end
    local scroll = button:GetParent()
    local tracker = TrackerContainer(root)
    while scroll and (scroll ~= root or tracker) and not scroll:IsObjectType("ScrollFrame") do scroll = scroll:GetParent() end
    if navigation.SetScrollFrameForFrame then navigation:SetScrollFrameForFrame(active, scroll ~= root and scroll or nil) end
    Pad.RefreshBindings()
    -- Transfer the one visible footer without hiding it or publishing an empty
    -- state. Releasing the old section's space is a real root change, not a row
    -- navigation invalidation, host layout requests coalesce normally.
    if previousRoot and previousRoot ~= root then HintHeight(previousRoot, 0) end
end

function Pad.Arm()
    Pad.Request()
end

function Pad.Leaving(root)
    local window = Pad.windows[root]
    if not window then return end
    if window.listed and Pad.Available() and not Combat() then
        window.listed, window.needsRelease = nil, nil
        if window.popup then Manager():HandlePopupHide(root) else Manager():FrameHidden(root) end
    elseif window.listed and Combat() then
        window.needsRelease = true
    end
    if Pad.focusRoot == root and not handoff then Pad.ClearFocus() end
end

function Pad.TransferTracker(source, target, selection)
    if not SameTracker(source, target) or not Visible(target) or not Pad.Enabled() or Combat() then return false end
    local previous = Pad.windows[source]
    local oldFocus = Navigation():GetCurrentButton()
    handoff = true
    if Pad.windows[target].listed then Pad.Leaving(target) end
    -- Keep a native window registered during ordinary root replacement. Popup
    -- visits instead unwind through their native return stack before reopening
    -- against the original opener, rather than making the old guide the opener.
    if previous.popup then Pad.Leaving(source) end
    if Pad.Enter(target, selection, previous) then
        if not previous.popup then Pad.Leaving(source) end
        previous.opener, previous.openerRoot, previous.openerID, previous.openerIndex = nil, nil, nil, nil
        handoff = false
        Pad.Observe()
        return true
    end
    -- A rejected/hidden target must not leave the player in an abandoned root.
    if Visible(source) then Pad.Enter(source, oldFocus, previous) end
    handoff = false
    Pad.Observe()
    return false
end

-- ============================================================
-- Entering and leaving AWP windows
-- ============================================================

function Pad.Enter(root, selection, previous)
    local window = Pad.windows[root]
    if not window or not Pad.Enabled() or Combat() or not Visible(root) then return false end
    if not previous and Pad.focusRoot and Pad.focusRoot ~= root and SameTracker(Pad.focusRoot, root)
        and Pad.windows[Pad.focusRoot].listed then
        return Pad.TransferTracker(Pad.focusRoot, root, selection)
    end
    if window.listed and not Pad.Within(root, Navigation():GetActiveFrame()) then Pad.Leaving(root) end
    if not window.listed then
        if previous then
            window.opener, window.openerRoot, window.openerID, window.openerIndex = previous.opener, previous.openerRoot,
                previous.openerID, previous.openerIndex
            window.popup = previous.popup
        else
            window.opener = Pad.focus
            window.openerRoot, window.openerID, window.openerIndex = Pad.focusRoot, Pad.focusID, Pad.focusIndex
            window.popup = Pad.focusRoot ~= nil and Pad.focusRoot ~= root
        end
        if window.popup then
            Manager():HandlePopupShown(root)
        elseif Manager():FrameShown(root) ~= true then
            return false
        end
        window.listed = true
    end
    Pad.Rebuild(root)
    local first = selection and Pad.CanFocus(selection) and selection or window.first and window.first() or
        window.controls and window.controls[1]
    if first then Pad.Select(first, root) end
    Pad.Arm()
    return true
end

function Pad.Back(root)
    if Combat() then return true end
    if Pad.adjusting then
        local record = Pad.controls[Pad.adjusting]
        if record and record.cancel then record.cancel() end
        Pad.adjusting = nil; Pad.RefreshBindings(); return true
    end
    root = root or Pad.focusRoot
    local window = root and Pad.windows[root]
    if not window then return end
    local opener = window.opener
    Pad.Leaving(root)
    if window.close then window.close() elseif not window.manual then root:Hide() end
    if opener and Pad.CanFocus(opener) then
        Pad.Select(opener)
    elseif window.openerRoot and Visible(window.openerRoot) then
        local previous = window.openerRoot
        Pad.Rebuild(previous)
        local controls = Pad.windows[previous].controls or {}
        local replacement
        for _, candidate in ipairs(controls) do
            if Pad.controls[candidate].id == window.openerID then
                replacement = candidate; break
            end
        end
        replacement = replacement or controls[math.min(window.openerIndex or 1, #controls)]
        if replacement then Pad.Select(replacement, previous) end
    end
    window.opener, window.openerRoot, window.openerID, window.openerIndex = nil, nil, nil, nil
    return true
end

function Pad.RegisterWindow(root, options)
    if not NS.IsWoWForever or not NS.IsWoWForever() then return end
    if Pad.windows[root] then return Pad.windows[root] end
    serial = serial + 1
    local window = options or {}
    window.order = serial
    Pad.windows[root] = window
    root.SmartNavigationCloseHandler = function() return Pad.Back(root) end
    root.SmartNavigationOnSelect = Pad.InvalidateBindings
    -- Close through the public lifecycle while our frame is still shown. An
    -- OnHide-only cleanup is too late for native input children being hidden.
    local hide, setShown = root.Hide, root.SetShown
    root.Hide = function(self)
        Pad.Leaving(self); return hide(self)
    end
    root.SetShown = function(self, shown)
        if not shown then Pad.Leaving(self) end; return setShown(self, shown)
    end
    -- Constructors assign their scripts after creating the shared shell. Hook
    -- once construction has finished, otherwise their SetScript replaces us.
    C_Timer.After(0, function()
        Pad.ObserveNavigationBindings()
        root:HookScript("OnShow", function()
            C_Timer.After(0,
                function()
                    if not window.manual then Pad.Enter(root) else Pad.Request(root) end; Pad.Arm()
                end)
        end)
        root:HookScript("OnHide", function()
            Pad.Leaving(root); Pad.Arm()
        end)
        root:HookScript("OnSizeChanged", function() Pad.Request(root) end)
        if Visible(root) then
            if not window.manual then Pad.Enter(root) else Pad.Request(root) end; Pad.Arm()
        end
    end)
    return window
end

function NS.SetControllerEnabled(enabled)
    local db = NS.GetDB()
    db.controllerEnabled = enabled == true
    Pad.Refresh()
end

function Pad.OpenMenu()
    if not Pad.Enabled() or Combat() then
        NS.Msg("AWP controller menus require Forever's controller UI outside combat."); return
    end
    if not Pad.menuAnchor then
        Pad.menuAnchor = CreateFrame("Frame", nil, UIParent)
        Pad.menuAnchor:SetSize(1, 1); Pad.menuAnchor:SetPoint("CENTER")
    end
    NS.ShowMinimapButtonMenu(Pad.menuAnchor)
end

function Pad.Refresh()
    Pad.ObserveNavigationBindings()
    if not Combat() then
        for root, window in pairs(Pad.windows) do if window.needsRelease then Pad.Leaving(root) end end
    end
    local enabled = Pad.Enabled() and true or false
    local newlyEnabled = enabled and not Pad.wasEnabled
    Pad.wasEnabled = enabled
    if not enabled then
        for root in pairs(Pad.windows) do Pad.Leaving(root) end
        Pad.ClearFocus()
        if not Combat() and Pad.Available() then
            for frame, record in pairs(Pad.controls) do
                if record.flagsApplied then RestoreControl(frame, record) end
            end
        end
    else
        local candidate
        for root, window in pairs(Pad.windows) do
            if Visible(root) then
                Pad.Request(root)
                if not window.manual and (not candidate or window.order > Pad.windows[candidate].order) then
                    candidate =
                        root
                end
            end
        end
        local nativeOwner = Manager():GetActiveFrame()
        if not nativeOwner or Pad.windows[nativeOwner] then
            local resume = Pad.resumeRoot
            if resume and Visible(resume) then
                Pad.Enter(resume)
            elseif newlyEnabled and candidate then
                Pad.Enter(candidate)
            end
        end
        Pad.resumeRoot = nil
    end
    Pad.Arm()
    if Pad.RefreshGuideAction then Pad.RefreshGuideAction() end
end

function Pad.Diagnostics()
    local root = Pad.focusRoot
    NS.Msg("[CONTROLLER]", "available=" .. tostring(Pad.Available() and true or false),
        "enabled=" .. tostring(Pad.Enabled() and true or false),
        "root=" .. tostring(root and root:GetName()), "control=" .. tostring(Pad.focusID),
        "adjusting=" .. tostring(Pad.adjusting ~= nil))
    local manager, navigation = Manager(), Navigation()
    local nativeRoot = navigation and navigation:GetActiveFrame()
    NS.Msg("[CONTROLLER]", "nativeRoot=" .. tostring(nativeRoot and nativeRoot:GetName()),
        "rightStick=" .. tostring(GetBindingAction("PADRSTICK", true)))
    local checks = {
        { "FrameControlsManager",        manager,                                   { "GetActiveFrame", "FrameShown", "FrameHidden", "HandlePopupShown", "HandlePopupHide" } },
        { "SmartNavigation",             navigation,                                { "GetActiveFrame", "GetCurrentButton", "SetTargetButtonForFrame", "RefreshButtonGroups" } },
        { "SmartNavigationSecureHelper", rawget(_G, "SmartNavigationSecureHelper"), { "SetSecureValue" } },
    }
    for _, check in ipairs(checks) do
        for _, method in ipairs(check[3]) do
            if not check[2] or type(check[2][method]) ~= "function" then
                NS.Msg("[CONTROLLER] Missing current API:",
                    check[1] .. "." .. method)
            end
        end
    end
    if Pad.ActionDiagnostics then Pad.ActionDiagnostics() end
    Pad.SecuritySnapshot("diagnostics")
    for _, report in ipairs(Pad.securityHistory or {}) do
        if #report.problems > 0 then NS.Msg("[CONTROLLER] Security", report.stage, table.concat(report.problems, "; ")) end
    end
end

if NS.IsWoWForever and NS.IsWoWForever() then
    for _, event in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS", "INPUT_DEVICE_INTERFACE_TRANSITION" }) do
        observer:RegisterEvent(event)
    end
    observer:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            Pad.resumeRoot = Pad.focusRoot
            for root in pairs(Pad.windows) do Pad.Leaving(root) end
            Pad.ClearFocus()
        else
            Pad.Refresh()
        end
    end)
end
