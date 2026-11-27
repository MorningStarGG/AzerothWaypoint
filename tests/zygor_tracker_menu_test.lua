local selected, settingsOpened, closed
local shared = {}
local ns = {
    State = {},
    Internal = { ZygorTrackerViewer = shared, GuideTrackerViewer = { Styles = {} } },
    IsZygorLoaded = function() return true end,
    SelectGuideProvider = function(provider) selected = provider end,
}
AzerothWaypointNS = ns
UIParent = {}
assert(loadfile("interface/menus.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/zygor/viewer/shared.lua"))()
assert(loadfile("integrations/guides/zygor/viewer/tracker_controls.lua"))()
local controls = shared.TrackerControls
local buttons, root = {}, {}
function root:SetTag(tag) self.tag = tag end
function root:CreateTitle(title) self.title = title end
function root:CreateButton(label, fn) buttons[label] = fn end
MenuUtil = {CreateContextMenu = function(_, build) build(nil, root) end}
local activeTab = {guide = {}}
shared.GetZygorGuideTabs = function() return {activeTab}, {}, {ActiveTab = activeTab} end
shared.GetZygorGuideTitle = function() return "Quest route" end
shared.CloseZygorTab = function(tab) closed = tab end
controls.ShowGuideDropdown(UIParent)
assert(root.tag == "MENU_AWP_ZYGOR_GUIDES")
buttons["Make Zygor Active"]()
buttons["Close Current Guide"]()
assert(selected == "zygor" and closed == activeTab)

shared.OpenZygorSettings = function() settingsOpened = true end
controls.OpenZygorViewerSettingsMenu(UIParent)
assert(settingsOpened, "Missing native dropdown API must open Zygor settings")
local menu, host
local zygor = {IsForever = true, db = {profile = {}}}
shared.GetZygor = function() return zygor end
CreateFrame = function(_, _, parent) return {parent = parent} end
UIDropDownFork_SetAnchor = function() end
EasyFork = function(entries, frame) menu, host = entries, frame end
controls.OpenZygorViewerSettingsMenu(UIParent)
assert(host.parent == UIParent)
local labels = {}
for _, item in ipairs(menu) do labels[item.text] = item end
labels["Lock Viewer"].func()
assert(labels["Show Skills"] and labels["Lock Viewer"].checked())
DropDownForkList1 = {dropdown = host, IsShown = function() return true end}
CloseDropDownForks = function() closed = host end
controls.OpenZygorViewerSettingsMenu(UIParent)
assert(closed == host)
