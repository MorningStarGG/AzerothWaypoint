local seen, stored, replay, page, delay
local ns = {
    VERSION = "4.3.0",
    Constants = {STARTUP_HELP_MODE_ACCOUNT = "account", STARTUP_HELP_MODE_CHARACTER = "character",
        STARTUP_HELP_MODE_DISABLED = "off"},
    GetStoredAddonVersion = function() return stored end,
    UpdateStoredAddonVersion = function() stored = "4.3.0" end,
    CompareAddonVersions = function(a,b) return a == b and 0 or -1 end,
    HasSeenOverviewAccountWide = function() return seen end,
    MarkOverviewShownAccountWide = function() seen = true end,
    ConsumePendingOverviewReplayForCurrentCharacter = function()
        local pending = replay
        replay = false
        return pending
    end,
    After = function(seconds, callback) delay = seconds; callback() end,
    Msg = function() end,
    ShowHelp = function(ref) page = ref end,
    ShowWhatsNew = function() page = "whats_new" end,
}
AzerothWaypointNS = ns
assert(loadfile("interface/help_notifications.lua"))()
assert(ns.CheckStartupHelpNotification() == "overview" and seen and page == "overview" and delay == 0.2)
assert(stored == ns.VERSION and ns.CheckStartupHelpNotification() == nil)
stored, replay = "4.2.0", true
assert(ns.CheckStartupHelpNotification() == "overview" and stored == "4.2.0")
assert(ns.CheckStartupHelpNotification() == "whats_new" and page == "whats_new" and stored == ns.VERSION)
ns.GetStartupHelpMode = function() return "off" end
ns.GetStartupWhatsNewMode = function() return "off" end
page, stored = nil, "4.2.0"
assert(ns.CheckStartupHelpNotification() == nil and page == nil and stored == ns.VERSION)
