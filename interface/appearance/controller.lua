-- ============================================================
-- UI Style selection
-- ============================================================
--
-- Chooses the active UI Style and owns its lifecycle. The controller selects a
-- provider, then refreshes or restores the registered controls as their
-- effective style changes.

local NS = _G.AzerothWaypointNS
NS.Internal = NS.Internal or {}
local Appearance = {
    texts = setmetatable({}, { __mode = "k" }),
    shells = setmetatable({}, { __mode = "k" }),
    moduleTexts = setmetatable({}, { __mode = "k" })
}
NS.Internal.Appearance = Appearance

local providers, providerOrder = {}, {}
-- Feature owners can adjust their baseline and layout around a UI style application.
local refreshCallbacks = { beforeVisuals = {}, afterVisuals = {}, afterRefresh = {} }
local refreshPending = false
local loggedIn, automaticID, choiceOffered = false, "awp", false
local availableChoices, readyProviders = {}, {}
local effectiveID, fallbackReason, missingChoicePending = "awp", nil, false
local offeredChoiceKey
local CHOICE_POPUP = "AWP_APPEARANCE_CHOICE"

function Appearance.RegisterProvider(provider)
    providers[provider.id] = provider
    providerOrder[#providerOrder + 1] = provider
end

function Appearance.RegisterRefreshCallback(phase, callback)
    local callbacks = refreshCallbacks[phase]
    callbacks[#callbacks + 1] = callback
end

function Appearance.RunRefreshCallbacks(phase)
    for _, callback in ipairs(refreshCallbacks[phase]) do
        local ok, message = pcall(callback)
        if not ok then
            if geterrorhandler then
                geterrorhandler()(message)
            else
                error(message, 0)
            end
        end
    end
end

function Appearance.GetPreference()
    local id = NS.GetDB().appearanceProvider
    return (id == "awp" or providers[id]) and id or "auto"
end

-- ============================================================
-- Style selection
-- ============================================================

function Appearance.GetSelectedID()
    local id = Appearance.GetPreference()
    return id == "auto" and automaticID or id
end

function Appearance.GetEffectiveID() return effectiveID end

local function ProviderLabel(id)
    return id == "auto" and "Automatic" or providers[id] and providers[id].label or "AWP"
end

function Appearance.GetSelectionStatus()
    local text = "Selected: " ..
        ProviderLabel(Appearance.GetPreference()) .. ", using: " .. ProviderLabel(effectiveID) .. "."
    return fallbackReason and text .. " " .. fallbackReason or text
end

local function SyncSelection(id)
    local changed = false
    for _, provider in ipairs(providerOrder) do
        local settings, enabled = provider.GetSettings(), provider.id == id
        if settings.enabled ~= enabled then
            settings.enabled = enabled; changed = true
        end
    end
    return changed
end

local function RefreshOptions()
    for _, provider in ipairs(providerOrder) do if provider.RefreshOptions then provider.RefreshOptions() end end
end

local function AvailableProviders()
    local available, ready = {}, {}
    for _, provider in ipairs(providerOrder) do
        local ok, api = pcall(provider.GetAPI)
        if ok and api then
            available[#available + 1] = provider; ready[provider.id] = true
        end
    end
    return available, ready
end

local function SelectedAddonAbsent()
    local provider = providers[Appearance.GetPreference()]
    return provider and provider.addonName and not NS.IsAddonLoaded(provider.addonName)
end

local function SelectChoice(data, index)
    if Appearance.GetPreference() ~= data.preference then return end
    local id = data[index]
    if not id then return end
    if id ~= "awp" then
        local provider = providers[id]
        local ok, api = pcall(provider.GetAPI)
        if not ok or not api then
            Appearance.RequestRefresh(); return
        end
    end
    Appearance.Select(id, true)
end

-- Readiness is evaluated on coalesced startup/UI signals, never in visual
-- updates. A late UI initialization can therefore join the automatic choice.
local function RequestChoice(attempt)
    local visible = choiceOffered and StaticPopup_Visible and NS.Internal.Dialogs.Visible(CHOICE_POPUP)
    if choiceOffered and not visible then return end
    local preference = Appearance.GetPreference()
    local missing = preference ~= "auto" and SelectedAddonAbsent()
    local available = availableChoices
    if missing then
        if readyProviders[preference] or #available == 0 then return end
    elseif preference ~= "auto" or #available < 2 then
        return
    end
    local notices = NS.Internal.StartupNotices
    if InCombatLockdown() then
        Appearance.deferred = true
        return notices.Retry(RequestChoice, attempt)
    end
    if notices.ShouldDefer(CHOICE_POPUP) then
        return notices.Retry(RequestChoice, attempt)
    end
    local ids = { preference = preference }
    for index, provider in ipairs(available) do ids[index] = provider.id end
    ids[#ids + 1] = "awp"
    local choiceKey = preference .. ":" .. table.concat(ids, ",")
    if visible and offeredChoiceKey == choiceKey then return end
    if visible then NS.Internal.Dialogs.Hide(CHOICE_POPUP) end
    local text = missing and (ProviderLabel(preference)
            .. " is your selected UI style. While that addon is unavailable, AzerothWaypoint uses its own look. Which UI style would you like to use?"
            .. "\n\nEscape keeps your saved selection and uses AWP's look for this session.")
        or
        "Several supported UI styles are available. Which should AzerothWaypoint match?\n\nYou can change this in General > UI Style. Escape keeps AWP's original appearance for this session."
    local dialog = {
        text = text,
        button1 = available[1].label,
        button2 = available[2] and available[2].label or "Use AWP Style",
        button3 = #available == 2 and "Use AWP Style" or nil,
        OnAccept = function(_, data) SelectChoice(data, 1) end,
        OnCancel = function(_, data, reason) if reason == "clicked" then SelectChoice(data, 2) end end,
        OnAlt = function(_, data) SelectChoice(data, 3) end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = notices.PreferredIndex(),
    }
    if #available > 2 then
        dialog.button1, dialog.button2 = "Choose UI Style", "Use AWP Style"
        dialog.OnCancel = function(_, data, reason) if reason == "clicked" then SelectChoice(data, #data) end end
        dialog.OnAccept = function(_, data)
            NS.Internal.Menus.CreateContextMenu(UIParent, function(_, menu)
                menu:CreateTitle("AzerothWaypoint UI Style")
                for index, id in ipairs(data) do
                    local choice = index
                    menu:CreateButton(ProviderLabel(id), function() SelectChoice(data, choice) end)
                end
            end)
        end
    end
    StaticPopupDialogs[CHOICE_POPUP] = dialog
    if NS.Internal.Dialogs.Show(CHOICE_POPUP, nil, nil, ids) then
        choiceOffered, offeredChoiceKey = true, choiceKey
    else
        choiceOffered = false
        notices.Retry(RequestChoice, attempt)
    end
end

local function ScheduleMissingChoice()
    if missingChoicePending or choiceOffered and not NS.Internal.Dialogs.Visible(CHOICE_POPUP) then return end
    missingChoicePending = true
    -- Give login and late addon initialization a chance to finish first.
    C_Timer.After(1, function()
        missingChoicePending = false; RequestChoice()
    end)
end

function Appearance.GetProviders() return providerOrder end

function Appearance.Select(id, fromChoice)
    if id ~= "auto" and id ~= "awp" and not providers[id] then return false end
    NS.GetDB().appearanceProvider = id
    if not fromChoice and NS.Internal.Dialogs.Visible(CHOICE_POPUP) then NS.Internal.Dialogs.Hide(CHOICE_POPUP) end
    if id ~= "auto" then
        SyncSelection(id)
    else
        choiceOffered = false
    end
    RefreshOptions()
    Appearance.RequestRefresh()
    return true
end

-- ============================================================
-- Deferred refresh and provider access
-- ============================================================

local function FlushProviderRefresh()
    refreshPending = false
    if InCombatLockdown and InCombatLockdown() then
        Appearance.deferred = true; return
    end
    local preference = Appearance.GetPreference()
    if loggedIn then availableChoices, readyProviders = AvailableProviders() end
    if preference == "auto" then
        local available = availableChoices
        automaticID = #available == 1 and available[1].id or "awp"
        if SyncSelection(automaticID) then RefreshOptions() end
        if loggedIn and #available > 1 then
            RequestChoice()
        elseif StaticPopup_Hide then
            NS.Internal.Dialogs.Hide(CHOICE_POPUP)
        end
    elseif SyncSelection(Appearance.GetSelectedID()) then
        RefreshOptions()
    end
    local selectedID = Appearance.GetSelectedID()
    local selected = readyProviders[selectedID] and providers[selectedID] or nil
    effectiveID = selected and selectedID or "awp"
    fallbackReason = nil
    if providers[selectedID] and not selected then
        fallbackReason = SelectedAddonAbsent() and (ProviderLabel(selectedID) .. " is not loaded or is disabled.")
            or (ProviderLabel(selectedID) .. " appearance is not ready, check its integration settings.")
        if loggedIn and #availableChoices > 0 and SelectedAddonAbsent() then ScheduleMissingChoice() end
    end
    if StaticPopup_Visible and NS.Internal.Dialogs.Visible(CHOICE_POPUP) and preference ~= "auto" and not SelectedAddonAbsent() then
        NS.Internal.Dialogs.Hide(CHOICE_POPUP)
    end
    local previous = Appearance.provider
    if previous and previous ~= selected then previous.Apply(false) end
    Appearance.provider = selected
    if selected then selected.Apply(true) end
    if selected and selected.lastError then effectiveID, fallbackReason = "awp", selected.lastError end
    if Appearance.FlushDeferredVisuals then Appearance.FlushDeferredVisuals() end
    Appearance.RunRefreshCallbacks("afterRefresh")
end

function Appearance.RequestRefresh(provider)
    if provider and Appearance.GetPreference() ~= "auto"
        and provider ~= Appearance.provider and Appearance.GetSelectedID() ~= provider.id
        and (Appearance.GetPreference() == "awp" or effectiveID ~= "awp") then
        return
    end
    if refreshPending then
        if provider then provider.counters.coalesced = provider.counters.coalesced + 1 end
        return
    end
    refreshPending = true
    C_Timer.After(0, FlushProviderRefresh)
end

local function Delegate(method, ...)
    local provider = Appearance.provider
    if provider then return provider[method](...) end
end

function Appearance.IsEnabled(...) return Delegate("IsEnabled", ...) or false end

function Appearance.GetRGB(...) return Delegate("GetRGB", ...) end

function Appearance.GetFont(...) return Delegate("GetFont", ...) end

function Appearance.GetProgressWidth(...) return Delegate("GetProgressWidth", ...) end

function Appearance.GetAPI(...) return Delegate("GetAPI", ...) end

function Appearance.StyleOptionHighlight(...) return Delegate("StyleOptionHighlight", ...) end

function Appearance.GetProviderChoices()
    local choices = { { value = "auto", text = "Automatic (match available UI)" }, { value = "awp", text = "AWP" } }
    for _, provider in ipairs(providerOrder) do
        local ok, api = pcall(provider.GetAPI)
        if ok and api or Appearance.GetPreference() == provider.id then
            choices[#choices + 1] = {
                value = provider.id,
                text = provider.label ..
                    (ok and api and "" or " (unavailable)")
            }
        end
    end
    return choices
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
local appearanceAddons = { DaylightUI = true, EllesmereUI = true, EllesmereUIBlizzardSkin = true, ElvUI = true, GW2_UI = true }
events:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_LOGIN" then
        loggedIn = true; Appearance.RequestRefresh()
    elseif event == "ADDON_LOADED" then
        if loggedIn and appearanceAddons[addon] then Appearance.RequestRefresh() end
    elseif Appearance.deferred then
        Appearance.deferred = nil; Appearance.RequestRefresh()
    end
end)

-- ============================================================
-- Surface ownership and font restoration
-- ============================================================

-- Explicitly registered AWP surfaces only. No discovery walk through foreign UI.
function Appearance.Tag(frame, surface) if frame then frame._awpAppearanceSurface = surface end end

function Appearance.FindSurface(frame)
    while frame do
        if frame._awpAppearanceSurface then return frame._awpAppearanceSurface end
        frame = frame.GetParent and frame:GetParent()
    end
end

local function FindModule(frame)
    while frame do
        if frame._awpGuideProvider and type(frame.usedBlocks) == "table" then return frame end
        frame = frame.GetParent and frame:GetParent()
    end
end

local EMPTY_FONT = {}
local function FontChanged(text, record)
    local file, size, flags = text:GetFont()
    return file ~= record.appliedFile or size ~= record.appliedSize or flags ~= record.appliedFlags
end

local function CaptureFont(text, record)
    record.file, record.size, record.flags = text:GetFont()
    if text.GetShadowColor then record.sr, record.sg, record.sb, record.sa = text:GetShadowColor() end
    if text.GetShadowOffset then record.sx, record.sy = text:GetShadowOffset() end
end

local function RestoreFont(text, record)
    if not record.fontApplied then return end
    local r, g, b, a
    if text.GetTextColor then r, g, b, a = text:GetTextColor() end
    -- Styling changes resolved values only, never font-object inheritance.
    -- Reassigning an EditBox's returned Font can create a native inheritance
    -- cycle and overflow the client stack, restore just what we changed.
    if record.file then text:SetFont(record.file, record.size, record.flags) end
    if record.sr and text.SetShadowColor then text:SetShadowColor(record.sr, record.sg, record.sb, record.sa) end
    if record.sx and text.SetShadowOffset then text:SetShadowOffset(record.sx, record.sy) end
    if r and text.SetTextColor then text:SetTextColor(r, g, b, a) end
    record.fontApplied = nil
end

function Appearance.ApplyText(text, record)
    if record.owner and FindModule(text) ~= record.owner then
        if record.fontApplied and not FontChanged(text, record) then RestoreFont(text, record) end
        Appearance.texts[text] = nil
        local index = Appearance.moduleTexts[record.owner]
        if index then index[text] = nil end
        return
    end
    local provider = Appearance.provider
    if record.fontApplied and FontChanged(text, record) then
        -- The owning renderer applied a new baseline (for example KT restyling).
        record.fontApplied = nil
        CaptureFont(text, record)
    end
    if not record.fontApplied then CaptureFont(text, record) end
    local font = provider and provider.GetFont(record.surface, record.kind)
    local viewerKey = record.surface and record.surface:match("^guide%.(.+)$")
    local override = record.owner and viewerKey and NS.GetGuideTrackerViewerTextSize
        and NS.GetGuideTrackerViewerTextSize(viewerKey, record.kind)
    if (font and font.active or override) and record.size then
        font = font or EMPTY_FONT
        local size = override or
            math.max(6, (font.customSizes and font.sizes[record.kind] or font.size or record.size) * (font.scale or 1))
        local file = record.kind == "heading" and font.headingFile or font.file
        local fileName, currentSize, flags = text:GetFont()
        if fileName ~= (file or record.file) or currentSize ~= size or flags ~= (font.flags or record.flags) then
            text:SetFont(file or record.file, size, font.flags or record.flags)
        end
        if font.sr and text.SetShadowColor then text:SetShadowColor(font.sr, font.sg, font.sb, font.sa) end
        if font.sx and text.SetShadowOffset then text:SetShadowOffset(font.sx, font.sy) end
        record.appliedFile, record.appliedSize, record.appliedFlags = text:GetFont()
        record.fontApplied = true
    else
        RestoreFont(text, record)
    end
    if record.role and text.SetTextColor then
        local r, g, b
        if provider then r, g, b = provider.GetRGB(record.surface, record.role, record.colorFacet) end
        if r then
            if text.GetTextColor then
                local cr, cg, cb, ca = text:GetTextColor()
                if not record.colorApplied or cr ~= record.appliedR or cg ~= record.appliedG or cb ~= record.appliedB then
                    record.r, record.g, record.b, record.a = cr, cg, cb, ca
                end
            end
            text:SetTextColor(r, g, b, record.a or 1)
            record.appliedR, record.appliedG, record.appliedB = r, g, b
            record.colorApplied = true
        elseif record.colorApplied then
            text:SetTextColor(record.r, record.g, record.b, record.a)
            record.colorApplied = nil
        end
    end
end

function Appearance.Text(text, surface, role, colorFacet, kind)
    if not text or not text.GetFont then return end
    local record = Appearance.texts[text]
    surface = surface or record and record.surface or Appearance.FindSurface(text)
    if not surface then return end
    if not record then
        record = {}
        Appearance.texts[text] = record
        CaptureFont(text, record)
    elseif not record.fontApplied then
        CaptureFont(text, record)
    end
    record.surface, record.role, record.colorFacet = surface, role, colorFacet or "colors"
    record.kind = kind or ((role == "TITLE" or role == "ACCENT") and "heading"
        or role == "LABEL" and "tip" or role == "VALUE" and "progress" or "body")
    local module = FindModule(text)
    if module then
        if record.owner and record.owner ~= module then
            local previous = Appearance.moduleTexts[record.owner]
            if previous then previous[text] = nil end
        end
        local index = Appearance.moduleTexts[module]
        if not index then
            index = setmetatable({}, { __mode = "k" }); Appearance.moduleTexts[module] = index
        end
        record.owner, index[text] = module, record
    end
    Appearance.ApplyText(text, record)
end

-- Native/KT pools can hand a freed AWP row to another module. Restore its
-- appearance before leaving our update, and stop tracking that pooled object.
function Appearance.PruneModule(module)
    local index = Appearance.moduleTexts[module]
    if not index then return end
    for text, record in pairs(index) do
        local parent = text.GetParent and text:GetParent()
        local line = parent and parent.parentBlock and parent
        local block = parent and (parent.parentBlock or parent.parentModule and parent.id and parent)
        local unused = FindModule(text) ~= module
        if block then
            local used = module.usedBlocks and module.usedBlocks[block.template]
            unused = unused or not used or used[block.id] ~= block
            if line then unused = unused or not block.usedLines or block.usedLines[line.objectiveKey] ~= line end
        end
        if unused then
            if record.fontApplied and not FontChanged(text, record) then RestoreFont(text, record) end
            if record.colorApplied and text.SetTextColor then text:SetTextColor(record.r, record.g, record.b, record.a) end
            Appearance.texts[text], index[text] = nil, nil
        end
    end
end

function Appearance.Restore()
    for text, record in pairs(Appearance.texts) do
        RestoreFont(text, record)
        if record.colorApplied then
            text:SetTextColor(record.r, record.g, record.b, record.a)
            record.colorApplied = nil
        end
    end
    if Appearance.RestoreVisuals then Appearance.RestoreVisuals() end
end

function Appearance.Refresh()
    for text, record in pairs(Appearance.texts) do Appearance.ApplyText(text, record) end
    if Appearance.RefreshVisuals then Appearance.RefreshVisuals() end
end
