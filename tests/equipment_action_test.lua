-- Standalone Lua 5.1 fixture test for AWP's equip/use/restore transaction.

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

local inventory = { [13] = 111 }
local combat = false
local eventFrame

local function region()
    local object = {}
    local noop = function() end
    for _, name in ipairs({
        "SetAllPoints", "SetPoint", "SetTexture", "SetAtlas", "SetBlendMode", "SetWidth", "SetHeight",
        "SetScale", "SetText", "Show", "Hide", "SetFontObject", "SetJustifyH", "SetShown",
        "SetAlpha",
    }) do object[name] = noop end
    object.GetText = function() return "Route" end
    object.IsVisible = function() return true end
    return object
end

local function frame()
    ---@type table<string, table|function>
    local object = { hooks = {}, scripts = {}, attributes = {} }
    local noop = function() end
    for _, name in ipairs({
        "SetSize", "Hide", "Show", "RegisterForClicks", "SetFrameStrata", "SetHighlightTexture",
        "ClearAllPoints", "SetParent", "SetPoint", "SetScale", "SetFrameLevel", "RegisterEvent",
        "RegisterUnitEvent", "SetAlpha",
    }) do object[name] = noop end
    object.CreateTexture = function() return region() end
    object.CreateFontString = function() return region() end
    object.HookScript = function(self, name, fn) self.hooks[name] = fn end
    object.SetScript = function(self, name, fn) self.scripts[name] = fn end
    object.GetScript = function(self, name) return self.scripts[name] end
    object.SetAttribute = function(self, key, value)
        assert(not combat, "secure payload changed during combat")
        self.attributes[key] = value
    end
    object.GetFrameLevel = function() return 1 end
    object.GetEffectiveScale = function() return 1 end
    object.GetCenter = function() return 100, 100 end
    object.GetBottom = function() return 80 end
    object.GetRight = function() return 120 end
    return object
end

_G.UIParent = frame()
_G.RegisterStateDriver = function(btn, _, rule) assert(not combat); btn.visibility = rule end
_G.UnregisterStateDriver = function(btn) assert(not combat); btn.visibility = nil end
_G.InCombatLockdown = function() return combat end
_G.C_CVar = { GetCVarBool = function() return false end }
_G.C_Item = {
    GetItemInfoInstant = function(itemID)
        if itemID == 222 then return itemID, nil, nil, "INVTYPE_TRINKET" end
    end,
    EquipItemByName = function(itemID, slot) inventory[slot] = itemID end,
    GetItemIconByID = function() return 12345 end,
}
_G.GetInventoryItemID = function(_, slot) return inventory[slot] end
_G.PickupInventoryItem = function(slot) inventory[slot] = nil end
_G.PutItemInBackpack = function() end
_G.CreateFrame = function()
    local created = frame()
    if not eventFrame then eventFrame = created end
    return created
end

local record = { _routeAcceptedPlanGeneration = 3 }
local advanced = 0
_G.AzerothWaypointNS = {
    State = {},
    After = function(_, fn) fn() end,
    GetDB = function() return {} end,
    GetTomTomArrow = function()
        local arrow = frame()
        arrow.title = region()
        return arrow
    end,
    SuppressTomTomArrowDisplay = function() end,
    GetActiveAuthorityRecord = function() return record end,
    GetRouteSpecialActionIdentity = function() return "equip/222" end,
    AdvanceActiveRouteAction = function(identity, generation)
        if identity == "equip/222" and generation == 3 then advanced = advanced + 1; return true end
        return false
    end,
    FlushDeferredRouteBackendStateValidations = function() end,
    FlushDeferredRouteActionRefresh = function() end,
}

assert(loadfile("bridge/routing/special_actions.lua"))()
local NS = _G.AzerothWaypointNS
local equipAction = {
    executionType = "equip", itemID = 222, semanticKind = "equip", activationMode = "portable",
    routeDependency = { kind = "item", id = 222 }, name = "Equip teleport trinket",
}
local useAction = {
    secureType = "item", securePayload = 222, routeDependency = { kind = "item", id = 222 },
}

NS.State.routing.specialActionState = equipAction
NS.ApplySpecialAction(equipAction)
local button = NS.GetSpecialActionButton()
button.hooks.OnClick(button, "LeftButton", false)
expect(inventory[13] == 222 and advanced == 1, "equip was not confirmed and advanced exactly once")
expect(NS.IsRouteEquipmentTransactionActive(), "transaction ended before the item-use leg")
expect(NS.SyncRouteEquipmentTransaction(record, useAction) == false, "item-use leg did not retain transaction")
NS.SyncRouteEquipmentTransaction(record, nil)
expect(inventory[13] == 111 and not NS.IsRouteEquipmentTransactionActive(), "prior equipment was not restored")

inventory[13] = 111
NS.State.routing.specialActionState = equipAction
NS.ApplySpecialAction(equipAction)
button.hooks.OnClick(button, "LeftButton", false)
inventory[13] = 333
NS.SyncRouteEquipmentTransaction(record, nil)
expect(inventory[13] == 333, "manual equipment change was overwritten")

inventory[13] = 111
NS.State.routing.specialActionState = equipAction
NS.ApplySpecialAction(equipAction)
button.hooks.OnClick(button, "LeftButton", false)
combat = true
expect(NS.SyncRouteEquipmentTransaction(record, nil) == false and inventory[13] == 222,
    "restoration was not deferred during combat")
combat = false
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
expect(inventory[13] == 111 and not NS.IsRouteEquipmentTransactionActive(), "combat-deferred restoration failed")

-- Clearing the route removes the button while the player's actual cast continues.
local timers, refreshes = {}, 0
NS.After = function(delay, fn) timers[delay] = fn end
NS.ScheduleActiveRouteRefresh = function() refreshes = refreshes + 1 end
local routing = NS.State.routing
local function travelClick()
    routing.specialActionState = useAction
    NS.ApplySpecialAction(useAction)
    button.hooks.OnClick(button, "LeftButton", false)
    assert(routing.specialActionCasting)
end
travelClick()
local event = eventFrame.scripts.OnEvent
event(eventFrame, "UNIT_SPELLCAST_START", "player", "travel-1")
routing.specialActionState = nil
NS.DisarmSpecialActionButton()
expect(routing.specialActionCasting and not routing.specialActionPresented and not button.attributes.type,
    "route teardown released the live travel cast")
event(eventFrame, "UNIT_SPELLCAST_FAILED", "player", "another-spell")
expect(routing.specialActionCasting and refreshes == 0, "unrelated cast ended travel")
event(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "travel-1")
expect(not routing.specialActionCasting and refreshes == 1, "travel completion did not release planning once")
local oldTimeout = timers[30]
travelClick()
NS.DisarmSpecialActionButton()
oldTimeout()
expect(routing.specialActionCasting, "old timeout released the next click")
timers[2]()
expect(not routing.specialActionCasting and refreshes == 2, "a click without a cast kept planning frozen")

routing.specialActionState = useAction
NS.ApplySpecialAction(useAction)
assert(button.visibility == "[combat] hide; show")
combat = true
event(eventFrame, "PLAYER_REGEN_DISABLED")
assert(not routing.specialActionPresented and routing.pendingSpecialAction == useAction)
routing.specialActionState = nil
NS.DisarmSpecialActionButton()
combat = false
event(eventFrame, "PLAYER_REGEN_ENABLED")
assert(not button.attributes.type and not button.visibility and not routing.pendingSpecialAction)

print("equipment_action_test: ok")
