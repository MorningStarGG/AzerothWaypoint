local f = dofile("tests/controller_fixture.lua")
local NS, Frame = f.NS, f.FrameMethods
function Frame:SetPropagateKeyboardInput(value) self.propagate = value end
function Frame:LockHighlight() self.highlightLocked = true end
function Frame:UnlockHighlight() self.highlightLocked = false end
NS.Constants = NS.Constants or {}
NS.State = NS.State or {}
NS.After = C_Timer.After
NS.SafeCall = function(fn, ...) if fn then return fn(...) end end
assert(loadfile("interface/framework/panels.lua"))()
assert(loadfile("interface/controller/modal.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("interface/startup_notices.lua"))()
assert(loadfile("core/init.lua"))("AzerothWaypoint", {})

local popup = "AWP_RECOMMEND_ELLESMERE_MARKER"
local modal = f.Pad.Modal
local visible, shown, writes = {}, 0, 0
local overlay, enabled, dismissed, ignoreSet = true, true, false, false
NS.IsWorldOverlayEnabled = function() return overlay end
NS.HasDismissedEllesmereMarkerPrompt = function() return dismissed end
NS.DismissEllesmereMarkerPrompt = function() dismissed = true end
StaticPopup_Visible = function(name) return visible[name] end
StaticPopup_Show = function(name)
    assert(name == popup)
    visible[name] = true
    shown = shown + 1
    return {}
end
local addon = {
    _InGameNavigation = {
        Get = function(key) assert(key == "enabled"); return enabled end,
        Set = function(value)
            assert(value == false and not f.combat, "Changed a setting without a safe explicit acceptance")
            writes = writes + 1
            if not ignoreSet then enabled = value end
        end,
    },
}
local function StartSession(controller)
    visible, f.controller = {}, controller
    StaticPopupDialogs[popup] = nil
    assert(loadfile("interface/options/shared.lua"))()
    return NS.MaybeShowEllesmereMarkerRecommendationPopup
end
local function Press(role) assert(rawget(_G, "AWPModal" .. role)):HardwareClick() end
local function Mouse(choice)
    assert(visible[popup])
    visible[popup] = nil
    local handler = StaticPopupDialogs[popup][choice]
    if handler then handler() end
end

local request = StartSession(false)
request()
assert(shown == 0 and #f.pending == 0, "Missing module started polling")
EllesmereUI = addon
overlay = false; request()
overlay, f.forever = true, false; request()
f.forever, enabled = true, false; request()
assert(shown == 0 and #f.pending == 0, "Prompt appeared without both Forever overlays")
enabled = true

local init = NS.State.init
local onEvent = init.frame:GetScript("OnEvent")
onEvent(init.frame, "ADDON_LOADED", "EllesmereUIForeverEssentials")
assert(shown == 0, "Module load showed the popup before login")
init.playerLoggedIn = true
visible.AWP_RECOMMEND_NATIVE_OVERLAY = true
onEvent(init.frame, "ADDON_LOADED", "EllesmereUIForeverEssentials")
request()
assert(shown == 0 and #f.pending == 1, "Late loading bypassed popup arbitration")
visible.AWP_RECOMMEND_NATIVE_OVERLAY = nil
f.combat = true
table.remove(f.pending, 1)()
assert(shown == 0 and #f.pending == 1, "Prompt appeared during combat")
f.combat = false
f.Flush()
assert(shown == 1 and NS.Internal.StartupNotices.ShouldDefer("AWP_RECOMMEND_NATIVE_OVERLAY"))
Mouse("OnCancel")
request()
assert(shown == 1 and not dismissed and writes == 0, "Remind Me Later acted or repeated in this session")

StartSession(false)()
Mouse("OnAccept")
f.combat = true
f.Flush()
assert(writes == 0 and enabled and not dismissed and f.message[1]:find("Forever Essentials", 1, true))
f.combat, ignoreSet = false, true
StartSession(false)()
Mouse("OnAccept"); f.Flush()
assert(writes == 1 and enabled and f.message[1]:find("World Map", 1, true), "An ignored setter was reported as success")
ignoreSet = false
StartSession(false)()
Mouse("OnAccept"); f.Flush()
assert(writes == 2 and not enabled and overlay and f.message[1]:find("is off", 1, true))

enabled = true
StartSession(true)()
assert(modal.DialogVisible(popup))
Press("Back")
assert(not modal.GetState() and enabled and not dismissed and writes == 2)
StartSession(true)()
Press("Down"); Press("Select")
assert(not modal.GetState() and enabled and not dismissed and writes == 2)
StartSession(true)()
Press("Select")
assert(not modal.GetState() and writes == 2, "The setting write ran inside the controller dialog")
f.Flush()
assert(writes == 3 and not enabled and overlay and not dismissed)
enabled = true
StartSession(true)()
Press("Down"); Press("Down"); Press("Select")
assert(dismissed and enabled and writes == 3 and not modal.GetState())
StartSession(false)()
assert(not visible[popup], "A new session ignored the account-wide dismissal")
dismissed = false
StartSession(false)()
Mouse("OnAlt")
assert(dismissed and enabled and writes == 3, "Mouse dismissal changed the marker")

print("Ellesmere marker prompt verified for late loading, mouse and controller choices, and combat")
