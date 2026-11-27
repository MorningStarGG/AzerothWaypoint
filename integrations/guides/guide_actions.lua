-- ============================================================
-- Guide action controls
-- ============================================================
--
-- Collects native guide actions and presents them in movable panels and beside
-- their owning tracker rows. An action belongs to a provider, guide and step.
-- Reused controls must resolve against the current owner before executing the
-- action.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local Actions = { providers = {}, models = {}, panels = {}, counters = { received = 0, coalesced = 0, built = 0, reused = 0 } }
Common.GuideActions = Actions
Actions.Types = NS.Constants.GUIDE_ACTION_TYPES
local attributes = { "type", "type1", "type2", "*type1", "type*", "shift-type*", "item", "item1", "item2", "item*", "toy",
    "spell", "spell1", "spell2", "unit",
    "macrotext", "macrotext1", "macrotext2", "shift-type1", "shift-macrotext", "shift-macrotext1",
    "ctrl-type1", "ctrl-macrotext1", "alt-type1", "alt-macrotext1", "shift-macrotext2", "itemid", "spellid", "petaction",
    "petid", "useOnKeyDown" }
local scripts = { "PreClick", "OnClick", "PostClick" }
local attributeIndex = {}
for index, name in ipairs(attributes) do attributeIndex[name] = index end
local modifiers = { "shift", "ctrl", "alt" }
local function Scalar(value) return NS.Internal.GuideSourceRuntime.Scalar(value) end
local function Combat() return InCombatLockdown() == true end
local function Settings(key) return NS.GetGuideActionSettings(key) end
local function NeedsCoverage(key)
    local provider = Actions.providers[key]
    return provider and provider.refreshViewerCloak and NS.GetGuideTrackerViewerProviderSettings(key).hideNative
        and not Settings(key).hideNative
end
function Actions.NeedsModel(key)
    local settings = Settings(key)
    local pad = NS.Internal.Controller
    return settings.enabled or settings.inline or NeedsCoverage(key) or
        pad and pad.NeedsGuideActions and pad.NeedsGuideActions(key)
end

local function Interested(key)
    local provider = Actions.providers[key]
    return Actions.NeedsModel(key) or Settings(key).hideNative and not (provider and provider.placementEvents)
end
local function BindingValue(button, index)
    if index <= #attributes then return Scalar(button:GetAttribute(attributes[index])) end
    if index == #attributes + #scripts + 1 then
        local kind = button:GetAttribute("type1") or button:GetAttribute("type") or button:GetAttribute("type*")
        return type(kind) == "string" and button[kind] or nil
    end
    return button:GetScript(scripts[index - #attributes])
end
local bindingCount = #attributes + #scripts + 1
local function NativeRevision(key, button)
    local provider = Actions.providers[key]
    if not provider or not provider.nativeRevision then return true, nil end
    local ok, value = pcall(provider.nativeRevision, button)
    if ok then return true, Scalar(value) end
    return false
end
local standardTypes = { item = true, spell = true, toy = true, macro = true, target = true, focus = true, assist = true }
local function SecureNative(action)
    if not action or action.kind ~= "native" or not action.binding then return false end
    for _, name in ipairs({ "type", "type1", "type2", "*type1", "type*", "shift-type*", "shift-type1", "ctrl-type1", "alt-type1" }) do
        local value = action.binding[attributeIndex[name]]
        if standardTypes[value] then return true end
    end
    return false
end
Actions.IsSecureNative = SecureNative
local builders = {}
local dataRevisions = {}
local inlineCoverage, viewerState, viewerCloaks, inlineState, layoutCoverage = {}, {}, {}, {}, {}

-- ============================================================
-- Building an action snapshot
-- ============================================================

-- A builder compares scalar fields in place and allocates an immutable action
-- only when its binding changes. Prepared combat actions never get mutated.
function Actions.CreateBuilder(key, guide, step)
    guide, step = Scalar(guide), Scalar(step)
    if type(guide) ~= "string" or type(step) ~= "number" or step <= 0 or step >= math.huge then guide, step = nil, nil end
    local previous = Actions.models[key]
    local provider = Actions.providers[key]
    local title, displayStep
    if provider and provider.describe then title, displayStep = provider.describe() end
    title, displayStep = Scalar(title), Scalar(displayStep)
    if type(title) ~= "string" then title = guide end
    if type(displayStep) ~= "number" then displayStep = step end
    local builder = builders[key]
    if builder then
        builder.guide, builder.step, builder.previous, builder.count, builder.output = guide, step,
            previous and previous.actions or builder.empty, 0, nil
        builder.model = previous
        builder.title, builder.displayStep = title, displayStep
        builder.dataReadyChanged = builder.resolvedRevision ~= (dataRevisions[key] or 0)
        return builder
    end
    builder = {
        key = key,
        guide = guide,
        step = step,
        title = title,
        displayStep = displayStep,
        previous = previous and previous.actions or {},
        count = 0,
        empty = {},
        model = previous,
        dataReadyChanged = true
    }
    builders[key] = builder
    function builder:Emit(kind, category, payload, label, icon, owner, native, unsupported, iconRegion, portrait,
                          framedIcon, instruction)
        local guide, step = self.guide, self.step
        if not guide or not step then return end
        payload, label, icon, owner = Scalar(payload), Scalar(label), Scalar(icon), Scalar(owner)
        if type(label) ~= "string" then label = "Guide action" end
        if type(icon) ~= "number" and type(icon) ~= "string" then icon = nil end
        if kind == "item" or kind == "toy" or kind == "spell" or kind == "equip" then
            if type(payload) ~= "number" or payload <= 0 or payload >= math.huge or payload ~= math.floor(payload) then return end
        elseif kind == "target" then
            if type(payload) ~= "string" or payload == "" or payload:find("[\r\n%[%]]") then return end
        elseif kind ~= "native" then
            return
        end
        self.count = self.count + 1
        local old = self.previous[self.count]
        local fallbackIcon = icon
        local atlas, ulx, uly, llx, lly, urx, ury, lrx, lry
        if type(iconRegion) == "table" or type(iconRegion) == "userdata" then
            atlas = type(iconRegion.GetAtlas) == "function" and Scalar(iconRegion:GetAtlas()) or nil
            if type(atlas) ~= "string" or atlas == "" then atlas = nil end
            local file = not atlas and type(iconRegion.GetTexture) == "function" and Scalar(iconRegion:GetTexture())
            if atlas then
                icon = nil
            elseif type(file) == "number" or type(file) == "string" then
                icon = file
                if type(iconRegion.GetTexCoord) == "function" then
                    ulx, uly, llx, lly, urx, ury, lrx, lry = iconRegion:GetTexCoord()
                    ulx, uly, llx, lly = Scalar(ulx), Scalar(uly), Scalar(llx), Scalar(lly)
                    urx, ury, lrx, lry = Scalar(urx), Scalar(ury), Scalar(lrx), Scalar(lry)
                end
            end
        end
        local cropped = type(ulx) == "number" and type(uly) == "number" and type(llx) == "number" and
            type(lly) == "number"
            and type(urx) == "number" and type(ury) == "number" and type(lrx) == "number" and type(lry) == "number"
            and (ulx ~= 0 or uly ~= 0 or llx ~= 0 or lly ~= 1 or urx ~= 1 or ury ~= 0 or lrx ~= 1 or lry ~= 1)
        portrait = Scalar(portrait)
        if type(portrait) ~= "number" or portrait <= 0 then portrait = nil end
        framedIcon = framedIcon == true or nil
        instruction = Scalar(instruction)
        if type(instruction) ~= "string" or instruction == "" then instruction = nil end
        local oldCoords = old and old.iconCoords
        local nativeRevision
        if native then
            local ok, revision = NativeRevision(self.key, native)
            if not ok then error("The native guide action state could not be read.") end
            nativeRevision = revision
        end
        local same = old and old.kind == kind and old.category == category and old.payload == payload
            and old.label == label and old.icon == icon and old.owner == owner and old.native == native
            and old.iconAtlas == atlas and old.portrait == portrait and old.fallbackIcon == fallbackIcon
            and old.framedIcon == framedIcon and old.tooltipInstruction == instruction
            and (not cropped and not oldCoords or cropped and oldCoords
                and ulx == oldCoords[1] and uly == oldCoords[2] and llx == oldCoords[3] and lly == oldCoords[4]
                and urx == oldCoords[5] and ury == oldCoords[6] and lrx == oldCoords[7] and lry == oldCoords[8])
            and old.guide == guide and old.step == step and old.unsupported == unsupported
            and old.guideTitle == self.title and old.displayStep == self.displayStep and
            old.nativeRevision == nativeRevision
        if same and native then
            for index = 1, bindingCount do
                if old.binding[index] ~= BindingValue(native, index) then
                    same = false; break
                end
            end
        end
        local action = old
        if not same then
            action = {
                kind = kind,
                category = category,
                payload = payload,
                label = label,
                icon = icon,
                owner = owner,
                native = native,
                guide = guide,
                step = step,
                guideTitle = self.title,
                displayStep = self.displayStep,
                unsupported = unsupported,
                nativeRevision = nativeRevision,
                tooltipInstruction = instruction,
                fallbackIcon = fallbackIcon,
                iconAtlas = atlas,
                portrait = portrait,
                framedIcon = framedIcon,
                iconCoords = cropped and { ulx, uly, llx, lly, urx, ury, lrx, lry } or nil
            }
            local tooltipKind = kind == "equip" and "item" or kind
            if kind == "native" then
                tooltipKind = category == "spells" and "spell" or
                    (category == "items" or category == "equipment") and "item" or nil
            end
            if (tooltipKind == "item" or tooltipKind == "toy" or tooltipKind == "spell")
                and type(payload) == "number" and payload > 0 and payload < math.huge and payload == math.floor(payload) then
                action.tooltipKind, action.tooltipID = tooltipKind, payload
            end
            if native then
                action.binding = {}
                for index = 1, bindingCount do action.binding[index] = BindingValue(native, index) end
                local nativeKind = action.binding[attributeIndex.type1] or action.binding[attributeIndex.type] or
                    action.binding[attributeIndex["type*"]]
                if action.tooltipKind == "item" and nativeKind == "toy" then action.tooltipKind = "toy" end
            end
            if not self.output then
                self.output = {}
                for index = 1, self.count - 1 do self.output[index] = self.previous[index] end
            end
        end
        if self.output then self.output[self.count] = action end
    end

    function builder:Finish()
        self.resolvedRevision = dataRevisions[self.key] or 0
        local previous, guide, step = self.model, self.guide, self.step
        if not self.output and self.count == #self.previous and previous and previous.guide == guide and previous.step == step
            and previous.title == self.title and previous.displayStep == self.displayStep then
            Actions.counters.reused = Actions.counters.reused + 1; return previous, false
        end
        if not self.output then
            self.output = {}; for index = 1, self.count do self.output[index] = self.previous[index] end
        end
        Actions.counters.built = Actions.counters.built + 1
        return { guide = guide, step = step, title = self.title, displayStep = self.displayStep, actions = self.output },
            true
    end

    return builder
end

local function NameIcon(builder, kind, id)
    if type(id) ~= "number" then return nil end
    local previous = builder.previous[builder.count + 1]
    local sameKind = previous and (previous.kind == kind or previous.kind == "native"
        and (previous.category == "spells" and kind == "spell" or previous.category ~= "spells" and kind ~= "spell"))
    if not builder.dataReadyChanged and sameKind and previous.payload == id then
        return previous.label,
            previous.fallbackIcon
    end
    if kind == "spell" and C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(id)
        return info and Scalar(info.name), info and Scalar(info.iconID)
    elseif C_Item then
        local name = type(C_Item.GetItemNameByID) == "function" and Scalar(C_Item.GetItemNameByID(id))
        local icon = type(C_Item.GetItemIconByID) == "function" and Scalar(C_Item.GetItemIconByID(id))
        return name, icon
    end
end
function Actions.IsNativeVisible(button)
    return button and button:IsShown() and (type(button.IsVisible) ~= "function" or button:IsVisible())
end

function Actions.Typed(builder, kind, category, id, owner, native, label, iconRegion)
    local name, icon = NameIcon(builder, kind, id)
    builder:Emit(kind, category, id, name or label or "Guide action", icon, owner, native, nil, iconRegion, nil, nil,
        name and label ~= name and label or nil)
end

function Actions.Native(builder, button, category, owner, label, unsupported, iconRegion, portrait, framedIcon)
    if not button or type(button.GetAttribute) ~= "function" or not Actions.IsNativeVisible(button) then return end
    iconRegion = iconRegion or button.icon or button.Icon
    if not iconRegion and type(button.GetNormalTexture) == "function" then iconRegion = button:GetNormalTexture() end
    local kind = Scalar(button:GetAttribute("type1") or button:GetAttribute("type"))
    local payload = Scalar(button:GetAttribute(kind == "spell" and "spell" or kind == "toy" and "toy" or "item"))
    local hasCallback = button:GetScript("PreClick") or button:GetScript("PostClick") or button:GetAttribute("unit")
    -- Plain native secure item/spell buttons need no callback forwarding.
    -- Macro, cycling, equipment, pet and custom handlers retain native clicks.
    if not hasCallback and (category == "items" or category == "spells") and (kind == "item" or kind == "spell" or kind == "toy") then
        payload = payload or Scalar(button:GetAttribute(kind .. "1"))
        local id = type(payload) == "number" and payload or
            type(payload) == "string" and tonumber(payload:match("^item:(%d+)$"))
        id = id or Scalar(button.itemId or button.itemID)
        if type(id) == "number" then
            local name, resolvedIcon = NameIcon(builder, kind, id)
            builder:Emit(kind, category, id, name or label or button.name or (kind .. " " .. id), resolvedIcon, owner,
                button, unsupported, iconRegion, portrait, framedIcon)
            return
        end
    end
    if category == "items" or category == "spells" or category == "equipment" then
        local value = Scalar(button:GetAttribute("item*") or button:GetAttribute("item1") or button:GetAttribute("item"))
        local id = type(value) == "string" and tonumber(value:match("^item:(%d+)$")) or
            Scalar(button.itemId or button.itemID)
        -- A custom click remains native even when it exposes a proven tooltip ID.
        -- Zygor macros publish itemid/spellid, RXP also publishes numeric payloads.
        id = id or Scalar(button:GetAttribute(category == "spells" and "spellid" or "itemid"))
        if not id and (category == "spells" and kind == "spell" or category ~= "spells" and (kind == "item" or kind == "toy")) then
            id = type(payload) == "number" and payload or nil
        end
        local name, resolvedIcon = NameIcon(builder, category == "spells" and "spell" or "item", id)
        builder:Emit("native", category, id, name or label or "Native guide action", resolvedIcon, owner, button,
            unsupported, iconRegion, portrait, framedIcon)
        return
    end
    builder:Emit("native", category, nil, label or "Native guide action", nil, owner, button, unsupported, iconRegion,
        portrait, framedIcon)
end

-- ============================================================
-- Native and secure action execution
-- ============================================================

function Actions.IsCurrent(key, action)
    local provider = Actions.providers[key]
    if not provider or not action or action.unsupported then return false end
    local ok, guide, step = pcall(provider.identity)
    if not ok or guide ~= action.guide or step ~= action.step then return false end
    if action.native then
        if not action.native:IsShown() then return false end
        local accessible, revision = NativeRevision(key, action.native)
        if not accessible or revision ~= action.nativeRevision then return false end
        for index = 1, bindingCount do
            local accessible, value = pcall(BindingValue, action.native, index)
            if not accessible or action.binding[index] ~= value then return false end
        end
    end
    return true
end

function Actions.InvokeNative(key, action, button, down)
    if Combat() then return false, "This guide helper is unavailable during combat." end
    if not Actions.IsCurrent(key, action) then
        Actions.Request(key); return false, "The guide action changed."
    end
    if SecureNative(action) then return false, "Use the guide action button's secure binding." end
    local ok, errorText = pcall(action.native.Click, action.native, button, down)
    if not ok then return false, tostring(errorText) end
    return true
end

local function ClearButton(button)
    for _, name in ipairs(attributes) do if name ~= "useOnKeyDown" then button:SetAttribute(name, nil) end end
end
-- An open item tooltip calls back here when its data arrives while the same button is hovered.
local Tooltip
local tooltipSetters = { item = "SetItemByID", toy = "SetToyByItemID", spell = "SetSpellByID" }
local function UpdateTooltip(button)
    local tip = GameTooltip
    if tip and not tip:IsForbidden() and tip:IsOwned(button) and tip:IsShown() then
        Tooltip(button)
    else
        button.UpdateTooltip = nil
    end
end
local function AccessibleTooltip()
    local tip = GameTooltip
    if tip and not tip:IsForbidden() then return tip end
end
local function ClearTooltip(button)
    button.UpdateTooltip = nil
    local tip = AccessibleTooltip()
    if tip and tip:IsOwned(button) then tip:Hide() end
end
local function CopyNativeBinding(button, action, live)
    for index, name in ipairs(attributes) do
        if name ~= "useOnKeyDown" then
            local value
            if live then value = Scalar(action.native:GetAttribute(name)) else value = action.binding[index] end
            button:SetAttribute(name, value)
        end
    end
end
function Actions.Bind(button, key, action, secure)
    local tip = AccessibleTooltip()
    local hovered = button._awpAction ~= action and tip and tip:IsOwned(button)
    if button._awpAction ~= action then ClearTooltip(button) end
    ClearButton(button)
    button._awpAction, button._awpActionKey = action, key
    local pad = NS.Internal.Controller
    if pad and not button._awpControllerExecutor then
        local record = pad.RegisterControl(button)
        if record then
            record.guide, record.action = key, action
            record.id = action and
                ("action:" .. tostring(key) .. ":" .. tostring(action.owner) .. ":" .. action.kind .. ":" .. tostring(action.payload)) or
                nil
        end
    end
    if not action then
        button:Hide(); return
    end
    local icon = button.icon
    icon:SetTexCoord(0, 1, 0, 1)
    if action.iconAtlas then
        icon:SetAtlas(action.iconAtlas)
    else
        icon:SetTexture(action.icon or 134400)
        if action.iconCoords then icon:SetTexCoord(unpack(action.iconCoords)) end
    end
    if action.portrait and type(SetPortraitTextureFromCreatureDisplayID) == "function" then
        pcall(SetPortraitTextureFromCreatureDisplayID, icon, action.portrait)
    end
    if SecureNative(action) then
        -- Execute the copied attributes through this button's own template.
        -- Calling the native secure OnClick through Lua loses secure execution.
        CopyNativeBinding(button, action)
    elseif action.kind == "native" then
        button:SetScript("OnClick", function(_, mouse, down)
            local ok, reason = Actions.InvokeNative(key, action, mouse, down)
            if not ok and NS.Msg then NS.Msg(reason) end
        end)
    else
        -- The secure template keeps its own OnClick handler. Never replace it.
        if not secure then button:SetScript("OnClick", nil) end
        if action.kind == "item" then
            button:SetAttribute("type1", "item"); button:SetAttribute("item", "item:" .. action.payload)
        elseif action.kind == "toy" then
            button:SetAttribute("type1", "toy"); button:SetAttribute("toy", action.payload)
        elseif action.kind == "spell" then
            button:SetAttribute("type1", "spell"); button:SetAttribute("spell", action.payload)
        elseif action.kind == "target" then
            button:SetAttribute("type1", "macro"); button:SetAttribute("macrotext",
                "/cleartarget\n/targetexact " .. action.payload)
        elseif action.kind == "equip" then
            button:SetAttribute("type1", "macro"); button:SetAttribute("macrotext",
                "/equip [nocombat] item:" .. action.payload)
        end
        -- An explicitly empty native modifier macro disables that combination;
        -- it must not become an unmodified item/spell cast on our typed button.
        if action.binding then
            for _, modifier in ipairs(modifiers) do
                if action.binding[attributeIndex[modifier .. "-macrotext1"]] == "" then
                    button:SetAttribute(
                        modifier .. "-type1", "")
                end
            end
        end
    end
    button:Show()
    if hovered and button:IsMouseOver() then Tooltip(button) end
end

Tooltip = function(button)
    local action = button._awpAction
    local tip = AccessibleTooltip()
    if not action or not tip or not button:IsVisible() then
        ClearTooltip(button); return
    end
    tip:SetOwner(button, "ANCHOR_RIGHT")
    local setter = tooltipSetters[action.tooltipKind]
    local filled = setter and pcall(tip[setter], tip, action.tooltipID)
    -- Native item processing owns comparisons and the active UI's data hooks.
    -- Never inspect secret tooltip lines or call the guide's hover handler.
    tip = AccessibleTooltip()
    if not tip or not tip:IsOwned(button) then
        button.UpdateTooltip = nil; return
    end
    if not filled or tip:NumLines() == 0 then tip:SetText(action.label or "Guide action", 1, 0.82, 0.2) end
    if action.tooltipInstruction then tip:AddLine(action.tooltipInstruction, 1, 1, 1, true) end
    tip:AddLine((action.guideTitle or button._awpActionKey) .. ", step " .. tostring(action.displayStep or action.step),
        1, 0.82, 0.2, true)
    if action.kind == "native" and not SecureNative(action) or action.kind == "equip" then
        tip:AddLine(
            "Available outside combat.", 1, 1, 1, true)
    end
    if Combat() then tip:AddLine("Prepared binding is held until combat ends.", 1, 0.82, 0.2, true) end
    if not pcall(tip.Show, tip) then
        button.UpdateTooltip = nil; return
    end
    button.UpdateTooltip = UpdateTooltip
end

-- ============================================================
-- Buttons and panel layout
-- ============================================================

local function NewButton(parent, secure, helper, name)
    local template = not helper and (secure and "SecureActionButtonTemplate" or "InsecureActionButtonTemplate") or nil
    local button = CreateFrame("Button", name, parent, template)
    button:SetSize(28, 28); button:RegisterForClicks("AnyDown", "AnyUp")
    if not helper then button:SetAttribute("useOnKeyDown", false) end
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2); button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetAllPoints(button)
    button._awpButtonArtHost, button._awpNativeButtonRegions = button, { border }
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", ClearTooltip)
    button:SetScript("OnHide", ClearTooltip)
    if not helper then
        button:SetScript("PreClick", function(self, mouse, down)
            self._awpNativePrepared = nil
            if not Combat() and self._awpAction and not Actions.IsCurrent(self._awpActionKey, self._awpAction) then
                ClearTooltip(self); ClearButton(self); Actions.Request(self._awpActionKey)
                return
            end
            local action = self._awpAction
            if not Combat() and not down and SecureNative(action) then
                local pre = action.binding[#attributes + 1]
                local ok, reason = true, nil
                if pre then ok, reason = pcall(pre, action.native, mouse, false) end
                if not ok then
                    ClearButton(self); if NS.Msg then NS.Msg("Guide action:", tostring(reason)) end; return
                end
                local provider = Actions.providers[self._awpActionKey]
                local valid, guide, step = pcall(provider.identity)
                if not valid or guide ~= action.guide or step ~= action.step then
                    ClearButton(self); Actions.Request(self._awpActionKey); return
                end
                CopyNativeBinding(self, action, true)
                self._awpNativePrepared = action
            end
        end)
        button:SetScript("PostClick", function(self, mouse, down)
            local action = self._awpNativePrepared
            self._awpNativePrepared = nil
            if not action or down or Combat() then return end
            local post = action.binding[#attributes + 3]
            if post then
                local ok, reason = pcall(post, action.native, mouse, false)
                if not ok and NS.Msg then NS.Msg("Guide action:", tostring(reason)) end
            end
            Actions.Request(self._awpActionKey)
        end)
    end
    return button
end
Actions.CreateButton = NewButton
local PANEL_BUTTON_SIZE, PANEL_COLUMNS, PANEL_GAP, PANEL_PADDING = 28, 6, 4, 8
local PANEL_STRIDE = PANEL_BUTTON_SIZE + PANEL_GAP

local function LayoutPanel(panel)
    local count = #panel.buttons
    if count == 0 then return end
    local rows = math.ceil(count / PANEL_COLUMNS)
    local buttonWidth = math.min(count, PANEL_COLUMNS) * PANEL_STRIDE - PANEL_GAP
    local titleWidth = math.ceil(panel.title:GetUnboundedStringWidth())
    local _, fontSize = panel.title:GetFont()
    local titleHeight = math.max(panel.title:GetStringHeight(), fontSize or 0)
    local headerHeight = math.max(22, math.ceil(titleHeight) + 10)
    -- Leave room for the pending marker without moving prepared buttons in combat.
    local width = math.max(buttonWidth, titleWidth + 12) + 2 * PANEL_PADDING
    local height = headerHeight + rows * PANEL_STRIDE - PANEL_GAP + PANEL_PADDING
    if panel._awpLayoutWidth ~= width or panel._awpLayoutHeight ~= height then
        panel:SetSize(width, height)
        panel._awpLayoutWidth, panel._awpLayoutHeight = width, height
    end
    if panel._awpHeaderHeight ~= headerHeight then
        panel.handle:SetHeight(headerHeight)
        panel._awpHeaderHeight = headerHeight
    end
    for index, button in ipairs(panel.buttons) do
        local row, column = math.floor((index - 1) / PANEL_COLUMNS), (index - 1) % PANEL_COLUMNS
        local rowCount = math.min(count - row * PANEL_COLUMNS, PANEL_COLUMNS)
        local x = (column - (rowCount - 1) / 2) * PANEL_STRIDE
        local y = -headerHeight - row * PANEL_STRIDE
        if button._awpPanelX ~= x or button._awpPanelY ~= y then
            button:ClearAllPoints(); button:SetPoint("TOP", panel, "TOP", x, y)
            button._awpPanelX, button._awpPanelY = x, y
        end
    end
end

function Actions.RefreshPanelSizes()
    if Combat() then return end
    for _, panel in pairs(Actions.panels) do
        if panel:IsShown() and not panel._awpPending then LayoutPanel(panel) end
    end
end

local appearance = NS.Internal.Appearance
if appearance and appearance.RegisterRefreshCallback then
    appearance.RegisterRefreshCallback("afterRefresh", Actions.RefreshPanelSizes)
end

local function Panel(key)
    if Actions.panels[key] then return Actions.panels[key] end
    local frame = CreateFrame("Frame", "AwpGuideActions" .. key, UIParent, "BackdropTemplate")
    local offset = 120
    for index, definition in ipairs(NS.Constants.GUIDE_PROVIDERS) do
        if definition.key == key then
            offset = offset - (index - 1) * 66; break
        end
    end
    frame._awpDefaultY = offset
    frame:Hide(); frame:SetPoint("CENTER", UIParent, "CENTER", 240, offset)
    if NS.Internal.Controller then NS.Internal.Controller.RegisterWindow(frame, { manual = true, guide = key }) end
    frame.background = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.background:SetAllPoints(); frame.background:EnableMouse(false)
    frame.background:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame.background:SetBackdropColor(0.04, 0.04, 0.04, 0.95); frame.background:SetBackdropBorderColor(0.35, 0.3, 0.15, 1)
    frame.handle = CreateFrame("Button", nil, frame)
    frame.handle:SetPoint("TOPLEFT"); frame.handle:SetPoint("TOPRIGHT"); frame.handle:SetHeight(22)
    frame.handle:RegisterForDrag("LeftButton")
    frame.title = frame.handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.title:SetPoint("TOPLEFT", 6, -5); frame.title:SetPoint("TOPRIGHT", -6, -5)
    frame.title:SetWordWrap(false); frame.title:SetJustifyH("CENTER")
    frame:EnableMouse(true); frame:SetMovable(true); frame:SetClampedToScreen(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not Combat() then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        if Combat() then return end
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        NS.SetGuideActionSetting(key, "position", { point = point, relative = relative, x = x, y = y })
    end)
    frame.handle:SetScript("OnDragStart", function() frame:GetScript("OnDragStart")(frame) end)
    frame.handle:SetScript("OnDragStop", function() frame:GetScript("OnDragStop")(frame) end)
    frame.handle:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Guide actions", 1, 0.82, 0.2)
        if frame._awpPending then GameTooltip:AddLine("New actions will be loaded after combat.", 1, 0.82, 0.2, true) end
        GameTooltip:AddLine("Drag this title bar to move the panel outside combat. Position is saved for this guide.", 1,
            1, 1, true)
        GameTooltip:Show()
    end)
    frame.handle:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local appearance = NS.Internal.Appearance
    if appearance then
        appearance.Shell(frame, "guide." .. key, { frame.background }, "actions")
        appearance.Text(frame.title, "guide." .. key, "TITLE", "actions", "heading")
    end
    frame.standard, frame.helpers, frame.buttons = {}, {}, {}
    Actions.panels[key] = frame
    return frame
end

local function StyleActionButton(button, key, framed)
    local appearance = NS.Internal.Appearance
    if appearance and (button._awpStyledActionKey ~= key or button._awpStyledFramedIcon ~= framed) then
        appearance.StyleButton(button, "guide." .. key, "actions", framed)
        button._awpStyledActionKey = key
    end
    if button._awpStyledFramedIcon ~= framed then
        local inset = framed and 0 or 2
        button.icon:SetPoint("TOPLEFT", inset, -inset)
        button.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
        button._awpNativeButtonRegions[1]:SetShown(not framed)
        button._awpStyledFramedIcon = framed
    end
end
Actions.StyleButton = StyleActionButton

local function Allowed(key, action) return not action.unsupported and Settings(key).types[action.category] ~= false end
local function Apply(key)
    if Combat() then return end
    local settings, model = Settings(key), Actions.models[key]
    local panel = Actions.panels[key]
    if settings.enabled and model and #model.actions > 0 then panel = panel or Panel(key) end
    if not panel then return end
    local standard, helper, count = 0, 0, 0
    if settings.enabled and model then
        for _, action in ipairs(model.actions) do
            if Allowed(key, action) then
                local complex = action.kind == "native" and not SecureNative(action)
                local pool, index
                if complex then
                    helper = helper + 1; pool, index = panel.helpers, helper
                else
                    standard = standard + 1; pool, index = panel.standard, standard
                end
                pool[index] = pool[index] or NewButton(panel, true, complex)
                local button = pool[index]
                Actions.Bind(button, key, action, true); count = count + 1
                panel.buttons[count] = button
                StyleActionButton(button, key, action.framedIcon)
            end
        end
    end
    for index = standard + 1, #panel.standard do Actions.Bind(panel.standard[index], key, nil, true) end
    for index = helper + 1, #panel.helpers do Actions.Bind(panel.helpers[index], key, nil, true) end
    for index = #panel.buttons, count + 1, -1 do panel.buttons[index] = nil end
    panel._awpPending = false
    local definition = NS.Constants.GUIDE_PROVIDER_BY_KEY[key]
    panel._awpPreparedTitle = definition.label ..
        (key == "questierouter" and "" or " · Step " .. tostring(model and model.displayStep or "-"))
    panel.title:SetText(panel._awpPreparedTitle)
    LayoutPanel(panel)
    local position = settings.position
    if position then
        panel:ClearAllPoints(); panel:SetPoint(position.point, UIParent, position.relative, position.x, position.y); panel._awpPositioned = true
    elseif panel._awpPositioned then
        panel:ClearAllPoints(); panel:SetPoint("CENTER", UIParent, "CENTER", 240, panel._awpDefaultY); panel._awpPositioned = false
    end
    if count > 0 then panel:Show() else panel:Hide() end
end

-- ============================================================
-- Native control visibility
-- ============================================================

function Actions.CanHideNative(key)
    local settings, provider = Settings(key), Actions.providers[key]
    if settings.hideNative then return true end
    local model, panel = Actions.models[key], Actions.panels[key]
    if provider and provider.lastError then
        return false,
            "Guide actions could not be read; native controls remain visible."
    end
    if not model or not model.guide or not model.step then return false, "Guide action coverage is not ready." end
    if provider and provider.identity then
        local ok, guide, step = pcall(provider.identity)
        if not ok or guide ~= model.guide or step ~= model.step then return false, "Guide action coverage is not ready." end
    end
    local panelButtons = settings.enabled and panel and panel:IsVisible() and panel.buttons
    for _, action in ipairs(model.actions) do
        if action.unsupported then
            return false,
                "A required native guide action is unsupported, native controls remain visible."
        end
        if settings.types[action.category] ~= false then
            local inline = settings.inline and inlineCoverage[key] and inlineCoverage[key][action]
            local covered = inline and inline:IsVisible()
            if not covered and panelButtons then
                for _, button in ipairs(panelButtons) do
                    if button._awpAction == action and button:IsVisible() then
                        covered = true; break
                    end
                end
            end
            if not covered then
                return false,
                    "Enable an action panel or show every required action inline before hiding native controls."
            end
        end
    end
    return true
end

local pending, force = {}, {}
local queue = NS.Internal.Scheduling.CreateCoalescer(function()
    for key in pairs(pending) do
        pending[key] = nil
        local provider = Actions.providers[key]
        local settings, combat = Settings(key), Combat()
        local refreshRows = inlineState[key] and not settings.inline
        if provider and Actions.NeedsModel(key) then
            local ok, model, changed = pcall(provider.collect)
            if ok and model then
                local recovered = provider.lastError ~= nil
                provider.lastError, Actions.models[key] = nil, model
                if combat then
                    local panel = Actions.panels[key]
                    if panel and changed and not panel._awpPending then
                        panel._awpPending = true; panel.title:SetText(panel._awpPreparedTitle .. " *")
                    end
                elseif changed or recovered or force[key] then
                    Apply(key)
                    refreshRows = refreshRows or settings.inline
                    if NeedsCoverage(key) then provider.refreshViewerCloak() end
                end
            elseif not ok then
                local hadError = provider.lastError ~= nil
                provider.lastError = tostring(model)
                if not hadError and NeedsCoverage(key) then provider.refreshViewerCloak() end
            end
        elseif not combat then
            if Actions.panels[key] and Actions.panels[key]:IsShown() then Apply(key) end
        end
        if provider then
            if settings.hideNative or provider.nativeHideWanted then provider.cloak:Refresh() end
            provider.nativeHideWanted = settings.hideNative
        end
        if not combat then
            if refreshRows then NS.RefreshGuideTrackerViewerProvider(key, "guide_actions") end
            inlineState[key] = settings.inline
        end
        force[key] = nil
        if NS.Internal.Controller and NS.Internal.Controller.GuideActionsChanged then
            NS.Internal.Controller
                .GuideActionsChanged(key)
        end
    end
end)

-- ============================================================
-- Refresh and provider registration
-- ============================================================

function Actions.Request(key, settingsChanged)
    if not Actions.providers[key] then return end
    if settingsChanged and not Combat() and Actions.providers[key].install then pcall(Actions.providers[key].install) end
    Actions.counters.received = Actions.counters.received + 1
    pending[key], force[key] = true, force[key] or settingsChanged == true
    if not queue:Request() then Actions.counters.coalesced = Actions.counters.coalesced + 1 end
end

local function AppendControlChildren(frames, ...)
    for index = 1, select("#", ...) do Actions.AppendNativeControls(frames, select(index, ...)) end
end
function Actions.AppendNativeControls(frames, frame)
    if not frame then return end
    frames[#frames + 1] = frame
    if type(frame.GetChildren) == "function" then
        AppendControlChildren(frames, frame:GetChildren())
    end
end

function Actions.Register(key, provider)
    provider.refreshViewerCloak = viewerCloaks[key]
    Actions.providers[key] = provider
    if provider.subscribe then provider.subscribe(function() if Interested(key) then Actions.Request(key) end end) end
    provider.cloak = Common.CreateNativeFrameCloak({
        actionControls = true,
        resolve = function()
            local wanted = Settings(key).hideNative
            return wanted and provider.frames and provider.frames() or {}, wanted
        end
    })
end

function Actions.RegisterViewerCloak(key, refresh)
    viewerCloaks[key] = refresh
    if Actions.providers[key] then Actions.providers[key].refreshViewerCloak = refresh end
end

local hooked = setmetatable({}, { __mode = "k" })
function Actions.Observe(key, object, method)
    if not object or type(object[method]) ~= "function" then return end
    local names = hooked[object] or {}; hooked[object] = names
    if names[method] then return end
    names[method] = true
    hooksecurefunc(object, method, function() if Interested(key) then Actions.Request(key) end end)
end

function Actions.GetStatus(key)
    local model, panel = Actions.models[key], Actions.panels[key]
    return model and #model.actions or 0, panel and panel:IsShown() or false, panel and panel._awpPending or false,
        Actions.providers[key] and Actions.providers[key].lastError
end

function Actions.ViewerChanged(key)
    if not Actions.providers[key] then return end
    local settings = NS.GetGuideTrackerViewerProviderSettings(key)
    local state = (settings.enabled and 1 or 0) + (settings.hideNative and 2 or 0)
    if viewerState[key] ~= state then
        viewerState[key] = state
        if Interested(key) or Actions.panels[key] then Actions.Request(key, true) end
    end
end

function Actions.EndLayout(key)
    if not NeedsCoverage(key) or not Settings(key).inline then
        layoutCoverage[key] = nil
        return
    end
    local covered = Actions.CanHideNative(key)
    if layoutCoverage[key] ~= covered then
        layoutCoverage[key] = covered
        Actions.providers[key].refreshViewerCloak()
    end
end

local function HasItemDependency(key, id)
    local model = Actions.models[key]
    for _, action in ipairs(model and model.actions or {}) do
        if action.payload == id and (action.category == "items" or action.category == "equipment") then return true end
    end
    return false
end

local INLINE_SIZE, INLINE_GAP, INLINE_INSET = 24, 4, 2
local INLINE_STRIDE = INLINE_SIZE + INLINE_GAP
local MIN_TEXT_WIDTH, INLINE_TEXT_GAP, INLINE_BOTTOM_PADDING = 72, 0, 0
local STEP_ACTION_LINE = "AwpGuideStepActions"
local trailingActionRows = setmetatable({}, { __mode = "kv" })

-- ============================================================
-- Inline action rows
-- ============================================================

function Actions.ReleaseRow(line)
    local pad = NS.Internal.Controller
    if pad and pad.ReleaseGuideRow then pad.ReleaseGuideRow(line) end
    local group = line and line._awpInlineActions
    if not group then return end
    local trailingBlock = group.trailingBlock
    if trailingBlock then
        if trailingActionRows[trailingBlock] == line then trailingActionRows[trailingBlock] = nil end
        group.trailingBlock = nil
    end
    for _, button in ipairs(group.buttons) do
        local coverage = inlineCoverage[button._awpActionKey]
        if coverage and coverage[button._awpAction] == button then coverage[button._awpAction] = nil end
        ClearTooltip(button); button:Hide(); button._awpAction = nil
    end
    local text = line.Text
    if group.textWidth and text then
        text:ClearAllPoints()
        for index = 1, group.pointCount do text:SetPoint(unpack(group.points[index], 1, 5)) end
        text:SetWidth(group.textWidth)
        if group.wordWrap ~= nil then text:SetWordWrap(group.wordWrap) end
        if group.maxLines ~= nil then text:SetMaxLines(group.maxLines) end
        group.textWidth = nil
    end
end

function Actions.BeginLayout(module)
    if module._awpInlineOwners then for owner in pairs(module._awpInlineOwners) do module._awpInlineOwners[owner] = nil end end
    if module._awpStepActionStrips then for block in pairs(module._awpStepActionStrips) do module._awpStepActionStrips[block] = nil end end
end

local function NarrowRowText(line, group, inset)
    local text = line.Text
    group.textWidth, group.pointCount = text:GetWidth(), text:GetNumPoints()
    group.wordWrap = nil
    if type(text.CanWordWrap) == "function" then group.wordWrap = text:CanWordWrap() end
    group.maxLines = type(text.GetMaxLines) == "function" and text:GetMaxLines() or nil
    local hadRightAnchor, hadLeftAnchor, rightAnchor = false, false, "RIGHT"
    local rightY = 0
    for index = 1, group.pointCount do
        local point, relative, relativePoint, x, y = text:GetPoint(index)
        local saved = group.points[index] or {}
        group.points[index] = saved
        saved[1], saved[2], saved[3], saved[4], saved[5] = point, relative, relativePoint, x, y
        if point:find("RIGHT", 1, true) then
            hadRightAnchor, rightAnchor, rightY = true, point, y or 0
        elseif point:find("LEFT", 1, true) then
            hadLeftAnchor = true
        end
    end
    if hadRightAnchor and hadLeftAnchor then group.textWidth = 0 end
    text:ClearAllPoints()
    for index = 1, group.pointCount do
        local point = group.points[index]
        if not point[1]:find("RIGHT", 1, true) then text:SetPoint(unpack(point, 1, 5)) end
    end
    if not hadLeftAnchor then text:SetPoint("LEFT", line, "LEFT", 0, 0) end
    text:SetWidth(0)
    text:SetPoint(rightAnchor, line, rightAnchor, -inset, rightY)
    if group.wordWrap ~= nil then text:SetWordWrap(true) end
    if group.maxLines ~= nil then text:SetMaxLines(0) end
end

local function GetActionRowWidth(line, block)
    local module = block and block.parentModule
    if module and not block.fixedWidth and type(module.GetWidth) == "function" then
        local width = module:GetWidth()
        if width > 0 then
            -- Rows are built before AnchorBlock. A pooled row can still report
            -- its previous width, so use the bounds the host will anchor to.
            return math.max(0, width - (block.offsetX or module.blockOffsetX or 0) + (block.rightEdgeOffset or 0))
        end
    end
    local width = line:GetWidth()
    if width <= 0 and block then return block:GetWidth() end
    return width
end

local function LayoutInlineButtons(line, key, owner, model, count, block, strip)
    Actions.ReleaseRow(line)
    local group = line._awpInlineActions
    if not group then
        group = { buttons = {}, standard = {}, helpers = {}, points = {} }; line._awpInlineActions = group
        line:HookScript("OnHide", function() Actions.ReleaseRow(line) end)
    end
    local width = GetActionRowWidth(line, block)
    local left = line.GetLeft and line:GetLeft()
    local textLeft = line.Text and line.Text.GetLeft and line.Text:GetLeft()
    local textInset = left and textLeft and math.max(0, textLeft - left) or 24
    local inset = count * INLINE_STRIDE - INLINE_GAP + INLINE_INSET + INLINE_TEXT_GAP
    local beside = not strip and line.Text and width - textInset - inset >= MIN_TEXT_WIDTH
    if beside then NarrowRowText(line, group, inset) end

    local oldHeight = line:GetHeight()
    local textHeight = 0
    if not strip then
        local measured = line.Text and line.Text.GetStringHeight and line.Text:GetStringHeight() or 0
        textHeight = math.ceil(math.max(oldHeight, measured))
    end
    local columns = beside and count or math.max(1, math.floor((width - 2 * INLINE_INSET + INLINE_GAP) / INLINE_STRIDE))
    local offset = not strip and not beside and textHeight + INLINE_GAP or 0
    local n = 0
    for _, action in ipairs(model.actions) do
        if action.owner == owner and Allowed(key, action) then
            n = n + 1
            -- Insecure buttons are safe children of all hosts' pooled rows.
            local helper = action.kind == "native" and not SecureNative(action)
            local pool = helper and group.helpers or group.standard
            local button = pool[n]
            if not button then
                button = NewButton(line, false, helper); pool[n] = button
            end
            group.buttons[n] = button
            local column, row = (n - 1) % columns, math.floor((n - 1) / columns)
            button:SetSize(INLINE_SIZE, INLINE_SIZE); button:ClearAllPoints()
            local y = -offset - row * INLINE_STRIDE
            if beside then
                button:SetPoint("TOPRIGHT", line, "TOPRIGHT", -INLINE_INSET - column * INLINE_STRIDE, y)
            else
                local rowCount = math.min(count - row * columns, columns)
                button:SetPoint("TOP", line, "TOP", (column - (rowCount - 1) / 2) * INLINE_STRIDE, y)
            end
            Actions.Bind(button, key, action, true)
            StyleActionButton(button, key, action.framedIcon)
            inlineCoverage[key] = inlineCoverage[key] or {}
            inlineCoverage[key][action] = button
        end
    end
    local height = math.max(textHeight,
        offset + math.ceil(count / columns) * INLINE_STRIDE - INLINE_GAP + INLINE_BOTTOM_PADDING)
    line:SetHeight(height)
    if block then block.height = (block.height or 0) + height - oldHeight end
end

local function InlineCount(key, owner, model)
    local count = 0
    for _, action in ipairs(model.actions) do
        if action.owner == owner and Allowed(key, action) then count = count + 1 end
    end
    return count
end

local function ClaimActionOwner(key, owner, model, module)
    if not owner then return end
    if module and module._awpInlineOwners and module._awpInlineOwners[owner] ~= nil then return end
    local count = InlineCount(key, owner, model)
    if module then
        module._awpInlineOwners = module._awpInlineOwners or {}
        module._awpInlineOwners[owner] = count > 0
    end
    if count > 0 then return count end
end

function Actions.HasGroupedActions(key)
    return Actions.providers[key] and Actions.providers[key].stepActions == true
end

function Actions.BindRow(line, key, owner, module, block, stepOwner)
    local pad = NS.Internal.Controller
    if line and pad and pad.BindGuideRow then pad.BindGuideRow(line, key, owner, stepOwner) end
    local model = Actions.models[key]
    if not line or Combat() or not model or not Settings(key).inline then return end
    module = module or line.parentBlock and line.parentBlock.parentModule
    block = block or line.parentBlock
    if module and block and Actions.HasGroupedActions(key) then
        stepOwner = stepOwner or owner
        if ClaimActionOwner(key, stepOwner, model, module) then
            module._awpStepActionStrips = module._awpStepActionStrips or {}
            module._awpStepActionStrips[block] = stepOwner
        end
        if owner == stepOwner then return end
    end
    local count = ClaimActionOwner(key, owner, model, module)
    if count then LayoutInlineButtons(line, key, owner, model, count, block) end
end

local function AddStepStrip(key, owner, model, count, block)
    local line = block:AddObjective(STEP_ACTION_LINE, "", nil, false, nil, nil, false, INLINE_SIZE)
    if not line then return end
    if line.Dash then line.Dash:Hide() end
    LayoutInlineButtons(line, key, owner, model, count, block, true)
    return line
end

function Actions.LayoutLeadingStepStrip(block, key, owner)
    local model = Actions.models[key]
    if not model or not Actions.HasGroupedActions(key) or Combat() then return end
    local settings = Settings(key)
    if not settings.inline or settings.groupPosition ~= "above" then return end
    local count = ClaimActionOwner(key, owner, model, block.parentModule)
    if count then return AddStepStrip(key, owner, model, count, block) end
end

function Actions.LayoutStepStrip(module, block)
    local strips = module._awpStepActionStrips
    local owner = strips and strips[block]
    if not owner then return end
    strips[block] = nil
    local key = module._awpGuideProvider
    local model = Actions.models[key]
    if not model then return end
    local count = InlineCount(key, owner, model)
    if count > 0 then
        local line = AddStepStrip(key, owner, model, count, block)
        if line then
            trailingActionRows[block] = line
            line._awpInlineActions.trailingBlock = block
        end
    end
end

function Actions.GetTrailingPadding(module)
    local block = module.lastBlock
    local line = block and trailingActionRows[block]
    return line and line:IsShown() and INLINE_BOTTOM_PADDING or 0
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "GET_ITEM_INFO_RECEIVED", "QUEST_LOG_UPDATE" }) do
    watcher:RegisterEvent(
        event)
end
watcher:SetScript("OnEvent", function(_, event, argument)
    if not Actions.observingPublication and type(NS.ScheduleGuideProviderEvaluation) == "function" then
        Actions.observingPublication = true
        hooksecurefunc(NS, "ScheduleGuideProviderEvaluation", function(key)
            local provider = Actions.providers[key]
            if provider and not provider.placementEvents and Interested(key) then Actions.Request(key) end
        end)
    end
    for key, provider in pairs(Actions.providers) do
        if event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then
            if provider.install then pcall(provider.install) end
        end
        if event == "PLAYER_REGEN_DISABLED" then
            NS.RefreshGuideTrackerViewerProvider(key, "combat_inline_hidden")
        elseif (event ~= "GET_ITEM_INFO_RECEIVED" or HasItemDependency(key, argument))
            and (Interested(key) or Actions.panels[key]
                or (event == "PLAYER_LOGIN" or event == "ADDON_LOADED") and Settings(key).hideNative) then
            if event == "GET_ITEM_INFO_RECEIVED" or event == "SPELLS_CHANGED" then
                dataRevisions[key] = (dataRevisions[key] or 0) +
                    1
            end
            Actions.Request(key, event == "PLAYER_REGEN_ENABLED")
        end
    end
end)
