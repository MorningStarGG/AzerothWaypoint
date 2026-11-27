local session = assert(loadfile("tests/guide_restore_test.lua"))()
local NS, db, adapters, routes, flush = session("polestar")
local routingEnabled = true
NS.IsRoutingEnabled = function() return routingEnabled end
NS.NormalizeExternalWaypointSource = function(value)
    if type(value) ~= "string" then return nil end
    local key = value:lower()
    if adapters[key] then return key end
end
NS.GetExternalWaypointGuideProvider = function(key) return adapters[key] and key or nil end
NS.StartGuideRoutingEvaluation(); flush()
local originalSets, originalCrazy = 0, nil
_G.TomTom = {
    AddWaypoint = function(_, map, x, y, opts)
        originalCrazy = opts.crazy
        return { map, x, y, title = opts.title, from = opts.from }
    end,
    SetCrazyArrow = function(_self, _uid, _distance, _title) originalSets = originalSets + 1 end,
}
assert(loadfile("bridge/routing/carrier_tomtom.lua"))()
NS.InstallExternalTomTomHooks()
for _, provider in ipairs({ "zygor", "dugi", "rxp" }) do
    local uid = TomTom:AddWaypoint(1, .1, .2, { from = provider, title = "Native restored guide", crazy = true })
    assert(originalCrazy == false, "Guide publication took native arrow ownership")
    TomTom:SetCrazyArrow(uid, 15, "Native restored guide")
    flush()
    assert(NS.GetActiveGuideProvider() == "polestar" and db.activeGuideProvider == "polestar",
        "Passive " .. provider .. " publication replaced restored Polestar")
    assert(not NS.State.routing.manualAuthority and originalSets == 0, "Guide publication became manual or replaced the carrier")
end
-- Explicit selection still wins, and its later publications update normally.
NS.SelectGuideProvider("zygor"); flush()
assert(NS.GetActiveGuideProvider() == "zygor" and db.activeGuideProvider == "zygor")
TomTom:AddWaypoint(1, .1, .2, { from = "polestar", title = "Passive Polestar", crazy = true }); flush()
assert(NS.GetActiveGuideProvider() == "zygor", "The fix only protected Polestar instead of the selected provider")
routingEnabled = false
local uid = TomTom:AddWaypoint(1, .1, .2, { from = "zygor", crazy = true })
assert(originalCrazy == true, "Disabling AWP failed to restore native waypoint behavior")
TomTom:SetCrazyArrow(uid, 15, "Native arrow")
assert(originalSets == 1, "Disabled routing still intercepted the native arrow")
print("Passive guide TomTom publications preserve selection; explicit selection and routing-off behavior passed")
