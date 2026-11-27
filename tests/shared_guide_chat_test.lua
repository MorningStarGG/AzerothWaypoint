local messages, timers, config = {}, {}, {}
local NS = { Internal = { GuideTrackerViewer = {} }, State = {}, Constants = {
    WORLD_OVERLAY_COLOR_AUTO = "auto", WORLD_OVERLAY_COLOR_CUSTOM = "custom",
    ZYGOR_STEP_CHAT_STICKY_NONE = "none", ZYGOR_STEP_CHAT_STICKY_TITLES = "titles",
} }
_G.AzerothWaypointNS = NS
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) messages[#messages + 1] = text end }
NS.Msg = function(text) messages[#messages + 1] = text end
NS.GetGuideTrackerViewerProviderSettings = function(key) return config[key] end
NS.GetGuideTrackerViewerSettings = function(key) return config[key] end
NS.GetGuideTrackerViewerProvider = function(key) return { displayName = key } end
NS.IsZygorLoaded = function() return true end
for _, key in ipairs({ "zygor", "dugi", "rxp", "polestar" }) do
    config[key] = { chatStickySummary = "none", chatTextColorMode = "auto", textColorMode = "auto" }
end
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/viewer_styles.lua"))()
assert(loadfile("integrations/guides/viewer_chat.lua"))()
local Common = NS.Internal.GuideTrackerViewer
local snapshot = { title = "Guide", current = 2, total = 4, steps = {
    { ownerStepIndex = 2, rows = { { text = "Current instruction", kind = "tip" } } },
    { sticky = true, title = "Sticky title", rows = { { text = "Sticky instruction", kind = "tip" } } },
} }
for _, key in ipairs({ "dugi", "rxp", "polestar" }) do
    local function output(mode, summary)
        messages = {}; config[key].chatStickySummary = summary
        assert(Common.Chat.Output(key, Common.Chat.FromSnapshot(snapshot), mode))
        return table.concat(messages, "\n")
    end
    local text = output(nil, "none")
    assert(#messages == 2 and not text:find("Sticky", 1, true))
    text = output(nil, "count")
    assert(#messages == 3 and text:find("1 active", 1, true) and not text:find("Sticky title", 1, true))
    text = output(nil, "titles")
    assert(#messages == 4 and text:find("Sticky title", 1, true) and not text:find("Sticky instruction", 1, true))
    text = output("full", "none")
    assert(#messages == 5 and text:find("Sticky instruction", 1, true) and text:find("Current instruction", 1, true))
    text = output("sticky", "none")
    assert(not text:find("Current instruction", 1, true) and text:find("Sticky instruction", 1, true))
end
local goalReads = 0
local function goal(text, action)
    return { action = action, GetText = function() goalReads = goalReads + 1; return text end }
end
local current = { num = 2, goals = { goal("Accept 'Quest'", "accept") } }
local sticky = { num = 1, title = "Journal", goals = { goal("Collect Journal", "collect") } }
local Z = { CurrentGuide = { title = "Guide", steps = { {}, {}, {}, {} } }, CurrentStep = current,
    CurrentStickies = { sticky }, db = { profile = {} } }
NS.ZGV = function() return Z end
NS.GetZygorStepChatSettings = function()
    local c = config.zygor
    return { outputOnChange = c.chatOutputOnChange, stickySummary = c.chatStickySummary,
        textColorMode = c.chatTextColorMode, textCustomColor = c.chatTextCustomColor }
end
assert(loadfile("integrations/guides/zygor/viewer/shared.lua"))()
local M = NS.Internal.ZygorTrackerViewer
config.zygor.chatStickySummary = "titles"
messages = {}; assert(M.OutputCurrentZygorStepToChat())
local expected = {
    "|cff33ff99[AWP]|r |cff33ff99Zygor:|r |cffffd133Guide|r - |cffffffffStep 2/4 (50%)|r",
    "|cff33ff99[AWP]|r |cffffd133Sticky steps: 1 active|r",
    "    - |cff00abffSticky: Journal|r",
    "|cff33ff99[AWP]|r |cffffd133Current step:|r",
    "    |cffffd14dAccept 'Quest'|r",
}
assert(table.concat(messages, "\n") == table.concat(expected, "\n"), table.concat(messages, "\n"))
messages = {}; assert(M.OutputCurrentZygorStepToChat("sticky"))
assert(#messages == 3 and messages[3] == "        |cffabedffCollect Journal|r")
local before = goalReads
M.QueueStepChatOutputOnStepChange()
assert(#timers == 0 and goalReads == before, "Disabled automatic output built a print model")
config.zygor.chatOutputOnChange = true
for _ = 1, 100 do M.QueueStepChatOutputOnStepChange() end
assert(#timers == 1)
timers[1](); assert(goalReads > before)
before = goalReads; M.QueueStepChatOutputOnStepChange(); timers[2]()
assert(goalReads == before, "Unchanged automatic output rebuilt print model")
print("Shared chat modes and exact Zygor formatting/color/order passed")

local skipResult
Z.SkipStep = function() return skipResult end
assert(M.NextZygorStep() == true, "Native void action was rejected")
skipResult = false
assert(M.NextZygorStep() == false)
Z.ClearGuide = function() error("Native failure") end
assert(M.ClearCurrentZygorGuide() == false, "Failed native clear claimed success")
---@type boolean?
local optionsResult = false
Z.OpenOptions = function() return optionsResult end
assert(M.OpenZygorSettings() == false)
optionsResult = nil
assert(M.OpenZygorSettings() == true)
local tab = { RemoveTab = function() error("stale") end }
assert(M.CloseZygorTab(tab) == false)
print("Zygor native void/false/error action results passed")
