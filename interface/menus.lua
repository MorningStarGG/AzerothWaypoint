-- ============================================================
-- Shared menu descriptions
-- ============================================================
--
-- Builds one menu description for the mouse and controller renderers.

local NS = _G.AzerothWaypointNS
local Menus = {}
NS.Internal.Menus = Menus

function Menus.UsesController()
    return NS.IsWoWForever and NS.IsWoWForever() and InputUtil and InputUtil.IsGamepadUIEnabled()
end

-- Controller menus use AWP's own navigation context and bindings.
local Node = {}
Node.__index = Node
local function Add(parent, kind, text, callback, selected)
    local entry = setmetatable({ kind = kind, text = text, callback = callback,
        selected = selected, enabled = true, children = {} }, Node)
    parent.children[#parent.children + 1] = entry
    return entry
end
function Node:CreateButton(text, callback) return Add(self, "button", text, callback) end
function Node:CreateTitle(text) return Add(self, "title", text) end
function Node:CreateDivider() return Add(self, "divider") end
function Node:CreateSpacer() return Add(self, "spacer") end
function Node:CreateRadio(text, selected, callback) return Add(self, "radio", text, callback, selected) end
function Node:CreateCheckbox(text, selected, callback) return Add(self, "checkbox", text, callback, selected) end
function Node:SetEnabled(value) self.enabled = value; return self end
function Node:SetIsSelected(value) self.selected = value; return self end
function Node:SetTooltip(callback) self.tooltip = callback; return self end
function Node:SetTag(tag) self.tag = tag; return self end
function Node:AddMenuAcquiredCallback(callback) self.acquired = callback end
function Node:AddMenuReleasedCallback(callback) self.released = callback end

function Menus.Build(owner, generator)
    local root = setmetatable({ children = {}, owner = owner }, Node)
    generator(owner, root)
    return root
end

local defaultStyle, compactStyle
local function CompactStyle(base)
    if base ~= defaultStyle then
        local style = {}
        for key, value in pairs(base) do style[key] = value end
        function style:GetInset()
            local inset = base.GetInset(self)
            return {
                left = inset.left,
                top = inset.top,
                right = inset.right,
                bottom = math.min(inset.bottom, inset.top),
            }
        end
        defaultStyle, compactStyle = base, style
    end
    return compactStyle
end

function Menus.CreateContextMenu(owner, generator, anchor)
    if Menus.UsesController() then
        local modal = NS.Internal.Controller and NS.Internal.Controller.Modal
        if modal then return modal.Menu(owner, Menus.Build(owner, generator)) end
        return
    end

    local util, menu, variants = MenuUtil, rawget(_G, "Menu"), rawget(_G, "MenuVariants")
    local manager = menu and menu.GetManager and menu.GetManager()
    local open = manager and (anchor and manager.OpenMenu or not anchor and manager.OpenContextMenu)
    if not (owner and open and util.CreateRootMenuDescription and menu.PopulateDescription
        and variants and variants.GetDefaultContextMenuMixin) or (not anchor and owner.menuMixin) then
        return util.CreateContextMenu(owner, generator)
    end

    -- Scope the inset to our menu description. Blizzard styles are shared.
    local base = variants.GetDefaultContextMenuMixin()
    local style = type(base.GetInset) == "function" and CompactStyle(base) or base
    local root = util.CreateRootMenuDescription(style)
    menu.PopulateDescription(generator, owner, root)
    if anchor then return open(manager, owner, root, anchor) end
    local popup = open(manager, owner, root)
    if popup and PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    return popup
end

local Dialogs = {}
NS.Internal.Dialogs = Dialogs
function Dialogs.Visible(name)
    local modal = NS.Internal.Controller and NS.Internal.Controller.Modal
    return modal and modal.DialogVisible(name) or StaticPopup_Visible(name)
end
function Dialogs.Hide(name)
    local modal = NS.Internal.Controller and NS.Internal.Controller.Modal
    if modal and modal.DialogVisible(name) then return modal.Close("override") end
    return StaticPopup_Hide(name)
end
function Dialogs.Show(name, text, text2, data)
    if Menus.UsesController() then
        local modal = NS.Internal.Controller and NS.Internal.Controller.Modal
        if modal then return modal.Dialog(name, StaticPopupDialogs[name], text, text2, data) end
        return
    end
    return StaticPopup_Show(name, text, text2, data)
end
