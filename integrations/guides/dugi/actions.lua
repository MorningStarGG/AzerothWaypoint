-- ============================================================
-- Dugi guide actions
-- ============================================================
--
-- Reads Dugi's native action frames for the shared guide action controls.

local NS = _G.AzerothWaypointNS
local A = NS.Internal.GuideTrackerViewer.GuideActions
local function Runtime() return rawget(_G, "DugisGuideViewer") end
local function Identity()
    if not NS.IsDugiLoaded() then return end
    local r, user = Runtime(), rawget(_G, "DugisGuideUser")
    return rawget(_G, "CurrentTitle") or r.CurrentTitle, user and tonumber(user.CurrentQuestIndex)
end
local function Frames()
    local r, out = Runtime(), {}
    local item = rawget(_G, "DugisItemButton")
    local target = r and r.Modules and r.Modules.Target and r.Modules.Target.Frame
    if item then out[#out + 1] = item end
    if target then out[#out + 1] = target end
    return out
end
A.Register("dugi", {
    identity = Identity,
    frames = Frames,
    describe = function()
        local guide, step = Identity()
        return NS.Internal.GuideSourceRuntime.Call(Runtime(), "GetFormattedTitle", guide) or guide, step
    end,
    collect = function()
        local guide, index = Identity()
        local builder = A.CreateBuilder("dugi", guide, index)
        local r = Runtime()
        local target = r and r.Modules and r.Modules.Target
        local owner = target and tonumber(target.lastSetQuestIndex) or index
        for _, button in ipairs(Frames()) do
            local kind = button:GetAttribute("type*") or button:GetAttribute("*type1") or button:GetAttribute("type") or
            button:GetAttribute("type1")
            local category = "items"
            if kind ~= "item" then
                local p = owner and NS.Internal.DugiPresentation.ResolveStep(r, owner)
                category = p and p.action == "kill" and "hostile"
                    or p and (p.action == "talk" or p.action == "accept" or p.action == "turnin") and "friendly" or
                    "helpers"
            end
            A.Native(builder, button, category, kind == "item" and index or owner,
                kind == "item" and "Dugi guide item" or "Dugi target helper")
        end
        return builder:Finish()
    end,
    install = function()
        local r = Runtime()
        local item = r and r.Modules and r.Modules.ItemButton
        A.Observe("dugi", r, "UpdateGuide")
        A.Observe("dugi", item, "SetUseItem")
        A.Observe("dugi", item, "SetUseItemByQID")
        A.Observe("dugi", rawget(_G, "DugisItemButton"), "SetUseItem")
        A.Observe("dugi", r, "SetTarget")
        A.Observe("dugi", r, "SetNPCTarget")
    end,
})
