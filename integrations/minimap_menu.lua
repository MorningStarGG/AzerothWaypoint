-- ============================================================
-- DaylightUI minimap drawer
-- ============================================================
--
-- Keeps DaylightUI's minimap drawer open while an AWP menu or submenu owns the
-- interaction.

local NS = _G.AzerothWaypointNS
local Menus = {}
NS.Internal.MinimapMenus = Menus

local function InDrawer(owner, drawer)
    if not drawer.on or not drawer.open or not drawer.strip then return false end
    for _ = 1, 32 do
        if not owner or owner.IsForbidden and owner:IsForbidden() then return false end
        if owner == drawer.strip then return true end
        if type(owner.GetParent) ~= "function" then return false end
        owner = owner:GetParent()
    end
    return false
end

-- Daylight's native watcher already owns the timeout. Extend its keep-alive
-- inputs only for this AWP root menu, using the plugin API's reversible hook.
-- Root callbacks are shared with submenus: release only the acquired root.
function Menus.HoldDrawer(description, owner)
    local dui = rawget(_G, "DaylightUI")
    if not dui or type(dui.GetModule) ~= "function" or not dui.API or type(dui.API.For) ~= "function"
        or type(description.AddMenuAcquiredCallback) ~= "function" or type(description.AddMenuReleasedCallback) ~= "function" then
        return
    end
    local module = dui:GetModule("InfoPanel")
    local drawer = module and module.enabled and module.ns and module.ns.Drawer
    if not drawer or type(drawer.Watch) ~= "function" or not InDrawer(owner, drawer) then return end
    local api = dui.API.For("AzerothWaypoint")
    if not api or type(api.Wrap) ~= "function" or type(api.Unhook) ~= "function" then return end
    local root, handle
    description:AddMenuAcquiredCallback(function(menu)
        if type(menu.GetOwnerRegion) ~= "function" or menu:GetOwnerRegion() ~= owner or handle then return end
        root = menu
        handle = api.Wrap(drawer, "Watch", function(original, ...)
            if InDrawer(owner, drawer) then drawer.lastOver = GetTime() end
            return original(...)
        end)
    end)
    description:AddMenuReleasedCallback(function(menu)
        if menu ~= root then return end
        -- Resume the ordinary linger interval after selection, Escape or an
        -- outside click. Manual drawer closure and module disable still work.
        if handle then
            if InDrawer(owner, drawer) then drawer.lastOver = GetTime() end
            api.Unhook(handle)
            handle = nil
        end
        root = nil
    end)
end
