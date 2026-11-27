-- ============================================================
-- Settings profile transfers
-- ============================================================
--
-- Handles profile selection and the export, paste, review and confirmation
-- steps for transfers. Paste capture feeds the review. Save uses the reviewed
-- profile and selected sections, after confirming they are still current.

local NS = _G.AzerothWaypointNS
local Interface = NS.Internal.Interface
local Canvas = Interface.canvas
local W, FW = Canvas.Widgets, Interface.Framework
local Profiles = NS.Internal.Profiles
local Appearance = NS.Internal.Appearance
local CONFIRM = "AWP_PROFILE_CONFIRM"
local NAME = "AWP_PROFILE_NAME"
local FOLLOW = "follow-account"
local PASTE_FIELD_BYTES = 256
local managedID, transfer

local function Confirm(text, action, reload, label)
    StaticPopupDialogs[CONFIRM] = {
        text = "%s",
        button1 = label or (reload and "Apply and Reload" or ACCEPT),
        button2 = CANCEL,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function(_, callback) callback() end,
    }
    NS.Internal.Dialogs.Show(CONFIRM, text, nil, action)
end

local function Refresh(id)
    managedID = id or managedID
    W.RefreshActiveSection()
end

local function NameProfile(prompt, name, action)
    StaticPopupDialogs[NAME] = {
        text = "%s",
        button1 = "Save",
        button2 = CANCEL,
        hasEditBox = true,
        editBoxWidth = 260,
        maxLetters = Profiles.MAX_NAME,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnShow = function(frame, data)
            local edit = frame.EditBox or frame.editBox
            edit:SetMaxBytes(Profiles.MAX_NAME)
            edit:SetText(data.name)
            edit:SetFocus()
            edit:HighlightText()
        end,
        OnAccept = function(frame, data)
            local edit = frame.EditBox or frame.editBox
            local ok, result = data.action(edit:GetText())
            if ok then Refresh(type(ok) == "string" and ok or nil) else NS.Msg(result) end
        end,
    }
    NS.Internal.Dialogs.Show(NAME, prompt, nil, {name=name, action=action})
end

local function Choose(scope, id)
    if id == FOLLOW then id = nil end
    local function Apply()
        local ok, reload = Profiles.SetSelection(scope, id)
        if not ok then NS.Msg(reload)
        elseif reload then ReloadUI()
        else Refresh() end
    end
    if Profiles.SelectionRequiresReload(scope, id) then
        local _, defaultID = Profiles.GetSelection()
        Confirm("Use " .. Profiles.GetName(id or defaultID) .. " and reload the UI?", Apply, true)
    else
        Apply()
    end
end

local function TransferMessage(text, isError)
    transfer.message:SetText(text)
    if isError then transfer.message:SetTextColor(1, 0.35, 0.35)
    else transfer.message:SetTextColor(1, 0.82, 0) end
end

local function SaveImport(replace)
    local frame = transfer
    local preview, sections = frame.preview, frame.sections
    if not preview or not Profiles.HasImportSections(sections) then return end
    local name = frame.name:GetText()
    local confirmation = {}
    frame.importConfirmation = confirmation
    local function Save()
        if frame.importConfirmation ~= confirmation or frame.preview ~= preview or frame.sections ~= sections
            or not frame:IsShown() or (replace and frame.target ~= replace) then return end
        frame.importConfirmation = nil
        local id, reload = Profiles.SaveImport(preview, name, replace, sections)
        if not id then TransferMessage(reload, true); return end
        frame:Hide()
        if reload then ReloadUI() else Refresh(id) end
    end
    if replace then
        local name = Profiles.GetName(replace)
        if not name then TransferMessage("That profile no longer exists.", true); return end
        local active = Profiles.GetSelection() == replace
        Confirm("Apply the selected settings to " .. name .. "?" .. (active and " The UI will reload." or ""),
            Save, active, active and "Apply and Reload" or "Apply")
    else
        Save()
    end
end

local function ReadPaste(frame)
    local capture = frame.capture
    if capture.oversized then return nil, "The settings string is too large." end
    if capture.bytes > 0 then return table.concat(capture.chunks) end
    local text = frame.pasteInput:GetText()
    if #text >= PASTE_FIELD_BYTES then
        return nil, "The full settings string could not be captured. Copy the full export and paste it again."
    end
    return text
end

-- ============================================================
-- Paste capture and status
-- ============================================================

local function ShowPasteStatus(frame)
    local capture = frame.capture
    if capture.oversized then
        TransferMessage("The settings string is too large.", true)
        return
    end
    local bytes = capture.bytes > 0 and capture.bytes or #frame.pasteInput:GetText()
    TransferMessage(bytes > 0 and string.format("Profile string captured · %d bytes", bytes)
        or "Paste a settings string from AzerothWaypoint.", false)
end

local function ResetPaste(frame)
    frame.pasteStatus:Cancel()
    frame.capture = {chunks = {}, bytes = 0}
    frame.pasteInput:SetText("")
end

local function UpdateReview(frame)
    local preview, sections = frame.preview, frame.sections
    local active = Profiles.GetSelection()
    local count, missing, changes = Profiles.DescribeImport(preview, active, sections)
    local client = preview.client == "forever" and "WoW Forever" or "Retail"
    local lines = {
        string.format("Create from %s (active profile). %d selected changes.", Profiles.GetName(active), count),
    }
    local targetName = Profiles.GetName(frame.target)
    local targetChanges = changes
    if targetName then
        local differences = count
        if frame.target ~= active then
            local targetCount, _, targetSections = Profiles.DescribeImport(preview, frame.target, sections)
            differences, targetChanges = targetCount, targetSections
        end
        lines[#lines + 1] = string.format("Replace selected settings in %s. %d selected changes.", targetName, differences)
    end
    for _, section in ipairs(Profiles.importSections) do
        local label = section.label
        if sections[section.id] then
            local number = changes[section.id] or 0
            local targetNumber = targetChanges[section.id] or 0
            if targetName and frame.target ~= active then
                label = string.format("%s (%d / %d)", label, number, targetNumber)
            else
                label = string.format("%s (%d)", label, number)
            end
        end
        frame.sectionChecks[section.id].label:SetText(label)
    end
    if targetName and frame.target ~= active then lines[#lines + 1] = "Counts show Create / Replace." end
    if preview.ignored > 0 then
        lines[#lines + 1] = string.format("%d unrecognized settings will be ignored.", preview.ignored)
    end
    if #missing > 0 then lines[#lines + 1] = "Unavailable here: " .. table.concat(missing, ", ") end
    frame.source:SetText(preview.name .. " · " .. client)
    frame.summary:SetText(table.concat(lines, "\n"))
    frame.summaryBody:SetHeight(frame.summaryTop + math.max(1, frame.summary:GetStringHeight()))
    frame.reviewScroll:UpdateScrollChildRect()
    local canImport = Profiles.HasImportSections(sections)
    frame.primary:SetEnabled(canImport)
    frame.replace:SetEnabled(canImport and targetName ~= nil)
    frame.replace:SetShown(targetName ~= nil)
    TransferMessage(canImport and "Choose which sections to import. Unchecked sections keep their settings."
        or "Select at least one settings section.", false)
end

-- ============================================================
-- Import review
-- ============================================================

local function ReviewImport()
    local frame = transfer
    frame.pasteStatus:Cancel()
    local text, reason = ReadPaste(frame)
    if not text then TransferMessage(reason, true); return end
    local preview
    preview, reason = Profiles.Decode(text)
    if not preview then TransferMessage(reason, true); return end
    frame.preview, frame.sections = preview, {}
    for _, section in ipairs(Profiles.importSections) do
        frame.sections[section.id] = section.checked
        local check = frame.sectionChecks[section.id]
        check:SetChecked(section.checked)
        if Appearance then Appearance.UpdateToggle(check) end
    end
    frame.pasteInput:ClearFocus()
    frame.textArea:Hide()
    frame.clear:Hide()
    frame.name:SetText(Profiles.SuggestName(preview.name))
    frame.review:Show()
    frame.primary:SetDisplayText("Create Profile")
    frame.back:Show()
    UpdateReview(frame)
    frame.reviewScroll:SetVerticalScroll(0)
end

local function BackToInput()
    local frame = transfer
    frame.preview, frame.sections, frame.importConfirmation = nil, nil, nil
    frame.review:Hide()
    frame.back:Hide()
    frame.replace:Hide()
    local exporting = frame.exportText ~= nil
    frame.textArea:Show()
    frame.scroll:SetShown(exporting)
    frame.pasteInput:SetShown(not exporting)
    frame.clear:SetShown(not exporting)
    frame.primary:Enable()
    if exporting then
        frame.primary:SetDisplayText("Select String")
        frame.input:SetFocus()
        frame.input:HighlightText()
        TransferMessage("Copy this string with Ctrl+C.", false)
    else
        frame.primary:SetDisplayText("Review Import")
        frame.pasteInput:SetFocus()
        ShowPasteStatus(frame)
    end
end

-- ============================================================
-- Transfer dialog controls
-- ============================================================

local function TransferButton(parent, text, width, onClick)
    local button = FW.CreatePanelButton(parent)
    button:SetSize(width, 27)
    button:SetDisplayText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function BuildSectionChecks(frame)
    frame.sectionChecks = {}
    local parent = frame.summaryBody
    for index, section in ipairs(Profiles.importSections) do
        local id = section.id
        local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        check:SetSize(22, 22)
        check:SetPoint("TOPLEFT", parent, "TOPLEFT", (index - 1) % 2 * 256, -24 - math.floor((index - 1) / 2) * 24)
        check:SetHitRectInsets(0, -208, 0, 0)
        local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", check, "RIGHT", 4, 0)
        label:SetWidth(206)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        check.label = label
        frame.sectionChecks[id] = check
        check:SetScript("OnClick", function(self)
            if not frame.sections then return end
            local sections = {}
            for key, selected in pairs(frame.sections) do sections[key] = selected end
            sections[id] = self:GetChecked() == true
            frame.sections = sections
            frame.importConfirmation = nil
            UpdateReview(frame)
        end)
        if Appearance then
            Appearance.Text(label, nil, "TEXT")
            Appearance.RegisterToggle(check, {check:GetNormalTexture(), check:GetPushedTexture(),
                check:GetCheckedTexture(), check:GetHighlightTexture()}, label)
        end
    end
    frame.summaryTop = 30 + math.ceil(#Profiles.importSections / 2) * 24
end

local function BuildPasteInput(frame, area)
    local edit = CreateFrame("EditBox", nil, area)
    edit:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -8)
    edit:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -8, 8)
    edit:SetFontObject(ChatFontNormal)
    edit:SetMultiLine(true)
    edit:EnableMouse(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetMaxBytes(PASTE_FIELD_BYTES)
    frame.pasteInput = edit
    -- Only feedback is coalesced. Review reads the buffer that OnChar fills.
    frame.pasteStatus = NS.Internal.Scheduling.CreateCoalescer(function()
        if edit:IsVisible() then ShowPasteStatus(frame) end
    end)
    edit:HookScript("OnChar", function(_, character)
        local capture = frame.capture
        if not capture or frame.preview or capture.oversized or not character or character == "" then return end
        if capture.bytes + #character > Profiles.MAX_STRING then
            capture.oversized = true
            frame.pasteStatus:Request()
            return
        end
        local chunks = capture.chunks
        chunks[#chunks + 1] = character
        capture.bytes = capture.bytes + #character
        frame.pasteStatus:Request()
    end)
    edit:HookScript("OnTextChanged", function(_, user)
        if user and frame.capture and frame.capture.bytes == 0 then frame.pasteStatus:Request() end
    end)
    edit:HookScript("OnKeyDown", function(_, key)
        local paste = key == "V" and (IsControlKeyDown() or (IsMetaKeyDown and IsMetaKeyDown()))
            or key == "INSERT" and IsShiftKeyDown()
        if paste or key == "BACKSPACE" or key == "DELETE" then ResetPaste(frame) end
    end)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
end

local function BuildTransferFrame()
    local frame = CreateFrame("Frame", "AWPProfileTransfer", UIParent)
    frame:SetSize(570, 360)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    local shell = FW.CreatePanelShell(frame, {title="Profile Settings", surface="windows.options", movable=true})
    local body, footer = shell.bodyFrame, shell.footerFrame
    frame.title = shell.titleText

    frame.message = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.message:SetPoint("TOPLEFT", 16, -12)
    frame.message:SetPoint("RIGHT", body, "RIGHT", -16, 0)
    frame.message:SetJustifyH("LEFT")

    local area = CreateFrame("Frame", nil, body)
    area:SetPoint("TOPLEFT", 16, -48)
    area:SetPoint("BOTTOMRIGHT", -16, 12)
    area:SetClipsChildren(true)
    area:EnableMouse(true)
    local border = CreateFrame("Frame", nil, area, "QuestLogBorderFrameTemplate")
    border:SetAllPoints()
    border:EnableMouse(false)
    if Appearance then Appearance.Shell(area, "windows.options", {border}, nil, "inset") end
    frame.textArea = area

    frame.scroll = CreateFrame("ScrollFrame", nil, area, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -8)
    frame.scroll:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -24, 8)
    frame.input = CreateFrame("EditBox", nil, frame.scroll)
    frame.input:SetMultiLine(true)
    frame.input:SetAutoFocus(false)
    frame.input:SetFontObject(ChatFontNormal)
    frame.input:SetMaxBytes(Profiles.MAX_STRING + 1)
    frame.input:SetWidth(510)
    frame.input:SetHeight(200)
    frame.scroll:SetScrollChild(frame.input)
    frame.scroll:EnableMouse(true)
    frame.scroll:SetScript("OnMouseDown", function() frame.input:SetFocus() end)
    frame.scroll:HookScript("OnSizeChanged", function(_, width) frame.input:SetWidth(width) end)
    frame.input:SetScript("OnTextChanged", function(edit, user)
        if user and frame.exportText and edit:GetText() ~= frame.exportText then
            edit:SetText(frame.exportText)
            edit:HighlightText()
        end
    end)
    frame.input:SetScript("OnCursorChanged", function(_, _, y, _, height)
        frame.scroll:UpdateScrollChildRect()
        local offset = frame.scroll:GetVerticalScroll()
        local visible = frame.scroll:GetHeight()
        local top = -y
        if top < offset then frame.scroll:SetVerticalScroll(math.max(0, top))
        elseif top + height > offset + visible then
            frame.scroll:SetVerticalScroll(math.min(frame.scroll:GetVerticalScrollRange(), top + height - visible))
        end
    end)
    frame.input:SetScript("OnEscapePressed", function() frame:Hide() end)

    BuildPasteInput(frame, area)
    area:SetScript("OnMouseDown", function()
        local edit = frame.exportText and frame.input or frame.pasteInput
        edit:SetFocus()
    end)

    frame.review = CreateFrame("Frame", nil, body)
    frame.review:SetPoint("TOPLEFT", 16, -48)
    frame.review:SetPoint("BOTTOMRIGHT", -16, 12)
    local reviewScroll = CreateFrame("ScrollFrame", nil, frame.review, "UIPanelScrollFrameTemplate")
    reviewScroll:SetPoint("TOPLEFT")
    reviewScroll:SetPoint("BOTTOMRIGHT", -16, 43)
    frame.reviewScroll = reviewScroll
    frame.summaryBody = CreateFrame("Frame", nil, reviewScroll)
    frame.summaryBody:SetWidth(510)
    reviewScroll:SetScrollChild(frame.summaryBody)
    frame.source = frame.summaryBody:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.source:SetPoint("TOPLEFT")
    frame.source:SetPoint("RIGHT")
    frame.source:SetJustifyH("LEFT")
    frame.source:SetWordWrap(false)
    BuildSectionChecks(frame)
    frame.summary = frame.summaryBody:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.summary:SetPoint("TOPLEFT", 0, -frame.summaryTop)
    frame.summary:SetPoint("RIGHT")
    frame.summary:SetJustifyH("LEFT")
    frame.summary:SetWordWrap(true)

    local nameLabel = frame.review:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameLabel:SetPoint("BOTTOMLEFT", 0, 23)
    nameLabel:SetText("New profile name")
    frame.name = CreateFrame("EditBox", nil, frame.review, "InputBoxTemplate")
    frame.name:SetPoint("BOTTOMLEFT", 6, 0)
    frame.name:SetSize(250, 22)
    frame.name:SetAutoFocus(false)
    frame.name:SetMaxBytes(Profiles.MAX_NAME)
    frame.name:SetScript("OnEscapePressed", function() frame:Hide() end)

    frame.primary = TransferButton(footer, "Review Import", 130, function()
        if frame.exportText then frame.input:SetFocus(); frame.input:HighlightText()
        elseif frame.preview then SaveImport()
        else ReviewImport() end
    end)
    frame.primary:SetPoint("LEFT", footer, "LEFT", 16, 0)
    frame.replace = TransferButton(footer, "Replace Profile", 130, function() SaveImport(frame.target) end)
    frame.replace:SetPoint("LEFT", frame.primary, "RIGHT", 8, 0)
    frame.clear = TransferButton(footer, "Clear String", 105, function()
        ResetPaste(frame)
        ShowPasteStatus(frame)
        frame.pasteInput:SetFocus()
    end)
    frame.clear:SetPoint("LEFT", frame.primary, "RIGHT", 8, 0)
    frame.back = TransferButton(footer, "Back", 85, BackToInput)
    local close = TransferButton(footer, CLOSE, 80, function() frame:Hide() end)
    close:SetPoint("RIGHT", footer, "RIGHT", -16, 0)
    frame.back:SetPoint("RIGHT", close, "LEFT", -8, 0)
    frame:SetScript("OnHide", function()
        frame.input:ClearFocus()
        frame.pasteInput:ClearFocus()
        frame.name:ClearFocus()
        frame.exportText, frame.preview, frame.target, frame.sections = nil, nil, nil, nil
        frame.importConfirmation, frame.capture = nil, nil
        frame.pasteStatus:Cancel()
        frame.pasteInput:SetText("")
        frame.input:SetText("")
        frame.name:SetText("")
    end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AWPProfileTransfer" end
    return frame
end

-- ============================================================
-- Opening the transfer dialog
-- ============================================================

local function ShowTransfer(id, exporting)
    local text, reason
    if exporting then
        text, reason = Profiles.Export(id)
        if not text then NS.Msg(reason); return end
    end
    transfer = transfer or BuildTransferFrame()
    transfer.exportText = text
    transfer.target = not exporting and id or nil
    transfer.title:SetText(exporting and "Export Settings" or "Import Settings")
    transfer.input:SetText(text or "")
    ResetPaste(transfer)
    transfer:Show()
    transfer:Raise()
    BackToInput()
end

local function AddButtons(first, second, third)
    local previous
    for index, spec in ipairs({first, second, third}) do
        local button = W.AddActionButton(spec[1], 100, spec[2])
        if index == 1 then button:SetPoint("TOPLEFT", W.GetScrollChild(), "TOPLEFT", W.PAD, -W.GetCursorY())
        else button:SetPoint("LEFT", previous, "RIGHT", 8, 0) end
        if spec[3] == false then button:Disable() end
        previous = button
    end
    W.Spacer(30)
end

function Canvas.Renderers.profiles()
    local active, defaultID, overrideID = Profiles.GetSelection()
    local selected = Profiles.GetName(managedID) and managedID or active
    W.SectionHeader("Profile Selection")
    W.AddText("Active profile: " .. Profiles.GetName(active))
    W.AddDropdown("Account Default", "Used by characters that follow the account default.", Profiles.List,
        function() return defaultID end, function(id) Choose("account", id) end)
    W.AddDropdown("This Character", "Follow the account default or use a profile for this character.", function()
        local list = Profiles.List()
        table.insert(list, 1, { value=FOLLOW, text="Follow Account Default" })
        return list
    end, function() return overrideID or FOLLOW end, function(id) Choose("character", id) end)

    W.SectionHeader("Manage Profiles")
    W.AddDropdown("Profile", "Choose a profile to rename, duplicate, export, delete, or replace.", Profiles.List,
        function() return selected end, Refresh)
    AddButtons(
        {"Create", function() NameProfile("Create a profile with AWP defaults.", Profiles.SuggestName("New Profile"), Profiles.Create) end},
        {"Duplicate", function()
            NameProfile("Duplicate " .. Profiles.GetName(selected) .. ".", Profiles.SuggestName(Profiles.GetName(selected)),
                function(name) return Profiles.Create(name, selected) end)
        end},
        {"Rename", function()
            NameProfile("Rename " .. Profiles.GetName(selected) .. ".", Profiles.GetName(selected),
                function(name) return Profiles.Rename(selected, name) end)
        end})
    local codec = Profiles.HasCodec()
    AddButtons(
        {"Delete", function()
            Confirm("Delete " .. Profiles.GetName(selected) .. "?", function()
                local ok, reason = Profiles.Delete(selected)
                if ok then Refresh(active) else NS.Msg(reason) end
            end, false, DELETE)
        end, Profiles.CanDelete(selected)},
        {"Export", function() ShowTransfer(selected, true) end, codec},
        {"Import", function() ShowTransfer(selected, false) end, codec})
    if not codec then W.AddText("Settings strings are unavailable on this client.") end
end
