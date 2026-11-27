-- ============================================================
-- Controller menus
-- ============================================================
--
-- Owns the controller menu stack, focused row and return to the originating
-- control.

local NS = _G.AzerothWaypointNS
local Pad = NS.Internal.Controller
local Modal = {}
Pad.Modal = Modal
local current, frame, router
-- Activating a submenu renders its rows, whose click handlers call Activate again.
local Render
local CONTENT_PADDING = 12

local function ResetRow(row)
    if not row.focus then return end
    row.focus:Hide(); row:UnlockHighlight()
    local appearance = NS.Internal.Appearance
    if appearance and appearance.ResetInteraction then appearance.ResetInteraction(row) end
end

local function Value(value)
    if type(value) == "function" then return value() end
    return value
end

local function IsAction(entry)
    return entry and (entry.kind == "button" or entry.kind == "radio" or entry.kind == "checkbox")
end

-- This context owns only AWP input. Native menu/popup binding groups and the
-- native footer are never acquired, edited or released by this presenter.
function Modal.Close(reason)
    local state = current
    if not state then return end
    Pad.SecuritySnapshot("before " .. state.kind .. " close")
    current, Pad.modalActive = nil, nil
    if router and not InCombatLockdown() then router:Hide() end
    for _, pool in pairs(frame.rowPools) do for _, row in ipairs(pool) do ResetRow(row) end end
    frame:Hide()
    if GameTooltip then GameTooltip:Hide() end
    if state.description and state.description.released then state.description.released(frame) end
    if state.dialog then
        if reason and state.dialog.OnCancel then state.dialog.OnCancel(frame, state.data, reason) end
        if state.dialog.OnHide then state.dialog.OnHide(frame, state.data) end
    end
    if not current then
        frame.data = nil; frame.editBox:SetText("")
    end
    local nav = rawget(_G, "SmartNavigation")
    if not current and not InCombatLockdown() and nav and nav:GetActiveFrame() == state.nativeRoot
        and state.focus and Pad.CanFocus(state.focus)
        and (not state.focusID or Pad.controls[state.focus] and Pad.controls[state.focus].id == state.focusID) then
        if Pad.Select(state.focus, state.focusRoot) then Pad.Observe() end
    end
    Pad.Arm()
    Pad.SecuritySnapshot("after " .. state.kind .. " close")
    return state
end

local function Back()
    if not current then return end
    if #current.stack > 1 then
        table.remove(current.stack)
        Render()
    else
        Modal.Close("escape")
    end
end

-- ============================================================
-- Focus and activation
-- ============================================================

local function Focus(index)
    if not current then return end
    local entries = current.entries
    current.index = IsAction(entries[index]) and index or nil
    current.stack[#current.stack].index = current.index
    for i, row in ipairs(frame.rows) do
        if row:IsShown() and row.focus then
            local chosen = i == current.index
            row:UnlockHighlight()
            local appearance = NS.Internal.Appearance
            local themed = appearance and appearance.SetControllerFocus and appearance.SetControllerFocus(row, chosen)
            row.focus:SetShown(chosen and not themed)
        end
    end
    local row = frame.rows[current.index]
    local top = current.offsets and current.offsets[current.index] or 0
    local position, height = frame.scroll:GetVerticalScroll(), frame.scroll:GetHeight()
    if top < position then
        frame.scroll:SetVerticalScroll(top)
    elseif row and top + row:GetHeight() > position + height then
        frame.scroll:SetVerticalScroll(top + row:GetHeight() - height)
    end
    local selected = entries[current.index]
    local selectHint = selected and Value(selected.enabled) ~= false and Pad.Glyph("PAD1") .. " Select   " or ""
    frame.hints:SetText(selectHint .. Pad.Glyph("PAD2") .. (#current.stack > 1 and " Back" or " Close"))
    if GameTooltip then
        GameTooltip:Hide()
        if row and selected and selected.tooltip then
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); selected.tooltip(GameTooltip); GameTooltip:Show()
        end
    end
end

local function Move(delta)
    if not current then return end
    local index = (current.index or 1) + delta
    while current.entries[index] do
        if IsAction(current.entries[index]) then
            Focus(index); return
        end
        index = index + delta
    end
end

local function Activate(submenuOnly)
    local state = current
    local entry = state and state.entries[state.index or 1]
    if not IsAction(entry) or Value(entry.enabled) == false then return end
    if entry.children and #entry.children > 0 then
        state.stack[#state.stack + 1] = { description = entry }; Render(); return
    end
    if submenuOnly then return end
    local callback = entry.callback
    if state.kind == "dialog" then
        local keep = callback and callback()
        if current == state and keep ~= true then Modal.Close() end
        return
    end
    Modal.Close()
    if callback then callback() end
end

-- ============================================================
-- Reusing and rendering rows
-- ============================================================

-- Pool by presentation role: structural entries never acquire button scripts,
-- focus artwork or missing-font separator text, even when menu slots are reused.
local function AcquireRow(kind, used)
    local role = IsAction({ kind = kind }) and "action" or kind
    local pool = frame.rowPools[role]
    if not pool then
        pool = {}; frame.rowPools[role] = pool
    end
    used[role] = (used[role] or 0) + 1
    local row = pool[used[role]]
    if row then return row end
    if role == "action" then
        row = NS.Internal.Interface.Framework.CreatePanelButton(frame.content)
        row.focus = row:CreateTexture(nil, "OVERLAY")
        row.focus:SetColorTexture(1, 0.82, 0, 0.16); row.focus:SetAllPoints()
        row:SetScript("OnClick", function()
            Focus(row.menuIndex); Activate()
        end)
        row:HookScript("OnEnter", function() Focus(row.menuIndex) end)
        row:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    else
        row = CreateFrame("Frame", nil, frame.content)
        row:EnableMouse(false)
        if role == "title" then
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.label:SetPoint("LEFT", 6, 0); row.label:SetJustifyH("LEFT")
            row.label:SetPoint("RIGHT", -6, 0)
            local appearance = NS.Internal.Appearance
            if appearance then appearance.Text(row.label, "windows.options", "TITLE", "shell") end
        elseif role == "divider" then
            row.line = row:CreateTexture(nil, "ARTWORK")
            row.line:SetColorTexture(0.65, 0.65, 0.65, 0.45)
            row.line:SetPoint("LEFT", 6, 0); row.line:SetPoint("RIGHT", -6, 0); row.line:SetHeight(1)
            local appearance = NS.Internal.Appearance
            if appearance then appearance.RegisterVisual(row, { kind = "decoration", target = row.line, regions = { row.line } }) end
        else
            assert(role == "spacer", "Unsupported AWP menu entry kind")
        end
    end
    pool[used[role]] = row
    return row
end

Render = function()
    local state = current
    local page = state.stack[#state.stack]
    local entries = page.description.children
    state.entries, state.offsets = entries, {}
    state.contentWidth = math.max(1, frame.scroll:GetWidth())
    frame.content:SetWidth(state.contentWidth)
    frame.shell.titleText:SetText(page.description.text or "AzerothWaypoint")
    for _, pool in pairs(frame.rowPools) do for _, row in ipairs(pool) do
            ResetRow(row); row:Hide()
        end end
    frame.rows = {}
    local used, offset = {}, 0
    frame.scroll:SetVerticalScroll(0)
    for i, entry in ipairs(entries) do
        local row = AcquireRow(entry.kind, used)
        frame.rows[i], row.menuKind, row.menuIndex = row, entry.kind, i
        state.offsets[i] = offset
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -offset)
        row:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0, -offset)
        if IsAction(entry) then
            row:SetEnabled(Value(entry.enabled) ~= false)
            local selected = Value(entry.selected)
            local prefix = ""
            if entry.kind == "checkbox" then
                prefix = selected and "[x] " or "[ ] "
            elseif entry.kind == "radio" then
                prefix = selected and "(*) " or "( ) "
            elseif selected then
                prefix = "* "
            end
            row:SetDisplayText(prefix ..
            tostring(entry.text or "") .. (entry.children and #entry.children > 0 and "  >" or ""))
        elseif entry.kind == "title" then
            row.label:SetText(entry.text or "")
        end
        if row.label then
            row.label:SetWordWrap(true)
            row:SetHeight(math.max(IsAction(entry) and 30 or 22, row.label:GetStringHeight() + 10))
        else
            row:SetHeight(entry.kind == "divider" and 10 or 8)
        end
        offset = offset + row:GetHeight() + 2
        row:Show()
    end
    frame.content:SetHeight(math.max(1, offset))
    state.contentHeight = offset
    frame:SetHeight(math.min(520, math.max(130, 82 + offset + (state.edit and 100 or 0))))
    local first = page.index
    if not IsAction(entries[first]) then
        first = nil
        for i, entry in ipairs(entries) do
            if IsAction(entry) and Value(entry.enabled) ~= false then
                first = i; break
            end
        end
        if not first then for i, entry in ipairs(entries) do if IsAction(entry) then
                    first = i; break
                end end end
    end
    Focus(first)
end

-- ============================================================
-- Modal frame and bindings
-- ============================================================

local function Ensure()
    if frame then return end
    local FW = NS.Internal.Interface.Framework
    local cover = CreateFrame("Button", nil, UIParent)
    cover:Hide(); cover:SetAllPoints(UIParent); cover:SetFrameStrata("FULLSCREEN_DIALOG")
    cover:SetScript("OnClick", function() Modal.Close("escape") end)
    frame = CreateFrame("Frame", "AWPControllerModal", cover)
    frame:Hide(); frame:SetSize(420, 200); frame:SetClampedToScreen(true); frame:SetPoint("CENTER", UIParent, "CENTER")
    local shell = FW.CreatePanelShell(frame, {
        title = "AzerothWaypoint",
        footerHeight = 34,
        surface = "windows.options",
        controller = false,
        onClose = Back
    })
    frame.rows, frame.rowPools, frame.cover, frame.shell = {}, {}, cover, shell
    frame.GetOwnerRegion = function() return current and current.owner end
    frame.body = shell.bodyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.body:SetPoint("TOPLEFT", 16, -8); frame.body:SetWidth(380); frame.body:SetJustifyH("LEFT"); frame.body
        :SetWordWrap(true)
    frame.scroll = CreateFrame("ScrollFrame", nil, shell.bodyFrame)
    frame.scroll:SetPoint("TOPLEFT", CONTENT_PADDING, -6); frame.scroll:SetPoint("BOTTOMRIGHT", -CONTENT_PADDING, 6)
    frame.content = CreateFrame("Frame", nil, frame.scroll); frame.content:SetHeight(1); frame.scroll:SetScrollChild(
    frame.content)
    frame.scroll:SetScript("OnSizeChanged", function(_, width)
        -- Height changes follow row measurement. Only a new available width
        -- invalidates wrapping, ordinary focus movement does not lay out rows.
        if current and width > 0 and current.contentWidth ~= width then Render() end
    end)
    frame.scroll:EnableMouseWheel(true)
    frame.scroll:SetScript("OnMouseWheel", function(_, delta) Move(delta > 0 and -1 or 1) end)
    frame.editBox = CreateFrame("EditBox", nil, frame)
    frame.EditBox = frame.editBox
    frame.GetEditBox = function(self) return self.editBox end
    frame.editBox:SetAutoFocus(false); frame.editBox:SetSize(370, 28)
    frame.editBox:SetPoint("TOP", shell.bodyFrame, "TOP", 0, -60)
    frame.editBox:SetFontObject("ChatFontNormal")
    local bg = frame.editBox:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.8)
    frame.editBox:SetScript("OnEnterPressed", function(self)
        if current and current.dialog and current.dialog.EditBoxOnEnterPressed then
            current.dialog.EditBoxOnEnterPressed(self)
        else
            Activate()
        end
    end)
    frame.editBox:SetScript("OnEscapePressed", function() Modal.Close("escape") end)
    frame.hints = shell.footerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.hints:SetPoint("CENTER"); frame.hints:SetWidth(390); frame.hints:SetWordWrap(true)
    frame:SetScript("OnHide", function()
        cover:Hide(); if current then Modal.Close("override") end
    end)
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.1 or not current then return end
        elapsed = 0
        local nav = rawget(_G, "SmartNavigation")
        local ownerRecord = current.owner and Pad.controls[current.owner]
        if (current.owner and current.owner.IsVisible and not current.owner:IsVisible())
            or (current.ownerID and (not ownerRecord or ownerRecord.id ~= current.ownerID))
            or (nav and nav:GetActiveFrame() ~= current.nativeRoot) then
            Modal.Close("override")
        end
    end)
    frame:EnableKeyboard(true)
    frame:SetScript("OnKeyDown", function(_, key)
        frame:SetPropagateKeyboardInput(false)
        if key == "ESCAPE" then
            Back()
        elseif key == "UP" then
            Move(-1)
        elseif key == "DOWN" then
            Move(1)
        elseif key == "ENTER" and not frame.editBox:HasFocus() then
            Activate()
        else
            frame:SetPropagateKeyboardInput(true)
        end
    end)
    router = CreateFrame("Frame", nil, UIParent, "SecureHandlerShowHideTemplate,SecureHandlerStateTemplate")
    router:Hide()
    router:SetAttribute("_onshow", [[
        self:ClearBindings()
        local prefix = "AWPModal"
        self:SetBindingClick(true,"PADDUP",prefix.."Up")
        self:SetBindingClick(true,"PADDDOWN",prefix.."Down")
        self:SetBindingClick(true,"PADDLEFT",prefix.."Left")
        self:SetBindingClick(true,"PADDRIGHT",prefix.."Right")
        self:SetBindingClick(true,"PAD1",prefix.."Select")
        self:SetBindingClick(true,"PAD2",prefix.."Back")
        self:SetBindingClick(true,"PAD3",prefix.."Ignore")
        self:SetBindingClick(true,"PAD4",prefix.."Ignore")
        self:SetBindingClick(true,"PADRSTICK",prefix.."Ignore")
    ]])
    router:SetAttribute("_onhide", "self:ClearBindings()")
    router:SetAttribute("_onstate-combat", "if newstate == 'combat' then self:Hide() end")
    RegisterStateDriver(router, "combat", "[combat] combat; clear")
    for role, callback in pairs({ Up = function() Move(-1) end, Down = function() Move(1) end,
        Left = Back, Right = function() if current and current.kind == "menu" then Activate(true) end end,
        Select = function() Activate() end, Back = Back, Ignore = function() end }) do
        local button = CreateFrame("Button", "AWPModal" .. role, UIParent)
        button:SetSize(1, 1); button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -1000, -1000)
        button:EnableMouse(false); button:RegisterForClicks("AnyUp")
        button:SetScript("OnClick", function() if current and not InCombatLockdown() then callback() end end)
    end
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_DISABLED"); events:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
    events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    events:SetScript("OnEvent", function(_, event, addon)
        if event == "ADDON_ACTION_FORBIDDEN" then
            if addon == "AzerothWaypoint" then Pad.SecuritySnapshot("forbidden action") end
            return
        end
        if event == "PLAYER_REGEN_DISABLED" or not NS.Internal.Menus.UsesController() then Modal.Close("override") end
    end)
end

-- ============================================================
-- Opening menus and dialogs
-- ============================================================

local function Open(owner, state)
    if InCombatLockdown() then return end
    if current then Modal.Close("override") end
    Ensure()
    local nav = rawget(_G, "SmartNavigation")
    state.focus = Pad.focus or nav and nav:GetCurrentButton()
    state.focusRoot = state.focus and Pad.Root(state.focus)
    state.focusID = state.focus and Pad.controls[state.focus] and Pad.controls[state.focus].id
    state.nativeRoot = nav and nav:GetActiveFrame()
    state.owner = owner
    state.ownerID = owner and Pad.controls[owner] and Pad.controls[owner].id
    Pad.SecuritySnapshot("before " .. state.kind .. " open")
    current, Pad.modalActive = state, true
    Pad.ClearFocus()
    frame.body:Hide(); frame.editBox:Hide(); frame.scroll:Show()
    frame.scroll:ClearAllPoints(); frame.scroll:SetPoint("TOPLEFT", frame.shell.bodyFrame, "TOPLEFT", CONTENT_PADDING, -6)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame.shell.bodyFrame, "BOTTOMRIGHT", -CONTENT_PADDING, 6)
    Render()
    frame.cover:Show(); frame:Show(); router:Show()
    Pad.SecuritySnapshot("after " .. state.kind .. " open")
    return frame
end

function Modal.Menu(owner, description)
    local result = Open(owner, { kind = "menu", description = description, stack = { { description = description } } })
    if result and description.acquired then description.acquired(result) end
    return result
end

function Modal.DialogVisible(name) return current and current.name == name and frame:IsShown() and frame end

function Modal.Dialog(name, dialog, text, text2, data)
    if not dialog then return end
    local description = { text = "AzerothWaypoint", children = {} }
    local state = {
        kind = "dialog",
        name = name,
        dialog = dialog,
        data = data,
        edit = dialog.hasEditBox,
        stack = { { description = description } }
    }
    for i, method in ipairs({ "OnAccept", "OnCancel", "OnAlt" }) do
        if dialog["button" .. i] then
            description.children[#description.children + 1] = {
                kind = "button",
                text = dialog["button" .. i],
                enabled = true,
                callback = function() if dialog[method] then return dialog[method](frame, data,
                            method == "OnCancel" and "clicked" or nil) end end
            }
        end
    end
    local result = Open(UIParent, state)
    if not result then return end
    frame.data = data
    local body = dialog.text or ""
    if text ~= nil then body = string.format(body, text, text2) end
    frame.body:SetText(body); frame.body:Show()
    local bodyHeight = frame.body:GetStringHeight() + 22
    local offset = bodyHeight + (dialog.hasEditBox and 38 or 0)
    frame.scroll:SetPoint("TOPLEFT", frame.shell.bodyFrame, "TOPLEFT", CONTENT_PADDING, -offset)
    frame:SetHeight(math.max(180, 82 + state.contentHeight + offset))
    if dialog.hasEditBox then
        frame.editBox:SetPoint("TOP", frame.shell.bodyFrame, "TOP", 0, -bodyHeight)
        frame.editBox:SetMaxLetters(dialog.maxLetters or 0); frame.editBox:SetText(""); frame.editBox:Show()
    end
    if dialog.OnShow then dialog.OnShow(frame, data) end
    return frame
end

function Modal.GetState() return current end
