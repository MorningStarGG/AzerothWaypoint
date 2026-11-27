assert(loadfile("tests/addon_load_order_test.lua"))()
local ns = AzerothWaypointNS
hooksecurefunc = function() end
local regionLists, childLists, countReads, writes = 0, 0, 0, 0
local function region(kind, alpha)
    return {
        alpha = alpha,
        IsObjectType = function(_, name) return kind == name end,
        GetAlpha = function(self) return self.alpha end,
        SetAlpha = function(self, value)
            writes = writes + 1
            self.alpha = value
        end,
    }
end
local function owner()
    local frame = { regions = {}, children = {} }
    for i = 1, 16 do frame.regions[i] = region("Texture", i / 16) end
    function frame:GetRegions() regionLists = regionLists + 1; return unpack(self.regions) end
    function frame:GetChildren() childLists = childLists + 1; return unpack(self.children) end
    function frame:GetNumRegions() countReads = countReads + 1; return #self.regions end
    function frame:GetNumChildren() countReads = countReads + 1; return #self.children end
    return frame
end
local root = owner()
root.children = { owner(), owner(), owner() }
SuperTrackedFrame = root
ns.State.init.playerLoggedIn = true
local refresh = ns.RefreshSuperTrackedFrameSuppression
refresh()
assert(writes == 64)
regionLists, childLists, countReads = 0, 0, 0
refresh()
assert(writes == 64, "Unchanged visuals rewrote alpha")
assert(regionLists == 4 and childLists == 4 and countReads == 0,
    ("Four-frame scan made %d region, %d child and %d count queries"):format(regionLists, childLists, countReads))

local detached = table.remove(root.children)
local text, ignored = region("FontString", 0.6), region("Line", 0.9)
root.regions = {text, ignored}
root.children[1].children = { root } -- Shared or cyclic owners are visited once.
refresh()
assert(detached.regions[1].alpha == 1 / 16 and text.alpha == 0 and ignored.alpha == 0.9)
text.alpha = 0.2
refresh()
assert(text.alpha == 0, "External alpha change escaped suppression")
local frame = root
for _ = 1, 6 do
    local child = owner()
    frame.children = {child}
    frame = child
end
refresh()
assert(frame.regions[1].alpha == 1 / 16, "Suppression crossed its depth limit")
SuperTrackedFrame = owner()
refresh()
assert(text.alpha == 0.6 and SuperTrackedFrame.regions[1].alpha == 0, "Root replacement lost the original alpha")
-- On release Blizzard can still report the user waypoint as selected while
-- the navigation frame and its screen position belong to the corpse.
Enum.SuperTrackingType = { UserWaypoint = 1, Corpse = 2 }
local priority = Enum.SuperTrackingType.Corpse
C_SuperTrack = {
    GetHighestPrioritySuperTrackingType = function() return priority end,
    IsSuperTrackingUserWaypoint = function() return true end,
}
local m = ns.Internal.WorldOverlay
m.target.active, m.target.kind, m.target.title = true, "route", "Follow the path"
refresh()
assert(SuperTrackedFrame.regions[1].alpha == 1 / 16, "AWP suppressed Blizzard's active corpse marker")
assert(not m.EnsureNativeNavigationHost() and m.ResolveMode() == "hidden",
    "A walking leg claimed the corpse navigation frame")
priority = Enum.SuperTrackingType.UserWaypoint
local updates = 0
ns.UpdateNativeWorldOverlay = function() updates = updates + 1 end
ns.OnNativeNavFrameDestroyed()
assert(updates == 1 and m.overlay.routeProbeValid ~= false, "Destroying the corpse frame blocked the next waypoint")
refresh()
assert(SuperTrackedFrame.regions[1].alpha == 0, "User waypoint control did not resume")
ns.State.init.playerLoggedIn = false
refresh()
assert(SuperTrackedFrame.regions[1].alpha == 1 / 16)
