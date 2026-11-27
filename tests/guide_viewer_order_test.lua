local f = assert(loadfile("tests/daylight_fixture.lua"))()
for _, file in ipairs({"core/core", "core/routing_backends", "core/db_defaults", "core/db", "core/guide_settings",
    "integrations/guides/viewer_custom_host", "interface/options/canvas_widgets"}) do
    assert(loadfile(file .. ".lua"))()
end
local NS = AzerothWaypointNS
local providers = NS.Constants.GUIDE_PROVIDER_BY_KEY
AzerothWaypointDB = {routingBackend="direct"}
local db = NS.ApplyDBDefaults()
local Common = NS.Internal.GuideTrackerViewer
local nativeSettings = NS.Internal.CopyProfileSettings(db)
assert(not nativeSettings.guideTrackerViewerOrder)
assert(NS.GetGuideTrackerViewerOrder()[1] == "zygor")
db.guideTrackerViewerOrder = {[1]="questierouter", [2]="questierouter", [3]="retired", [5]="dugi"}
local copied = assert(NS.Internal.CopyProfileSettings(db, true)).guideTrackerViewerOrder
assert(#copied == 7 and table.concat(copied, ",") == "questierouter,dugi,zygor,rxp,polestar,apr,wowpro")
copied[1] = "apr"
assert(NS.GetGuideTrackerViewerOrder()[1] == "questierouter", "Profile copy shared the stored order table")

local Frame = getmetatable(f.Frame())
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:RegisterForDrag() end
function Frame:GetEffectiveScale() return 2 end
function Frame:SetJustifyV() end

local custom = f.Frame()
local zygor, questie, polestar = f.Frame(custom), f.Frame(custom), f.Frame(custom)
zygor._awpGuideProvider, questie._awpGuideProvider, polestar._awpGuideProvider = "zygor", "questierouter", "polestar"
zygor.uiOrder, questie.uiOrder = providers.zygor.order, providers.questierouter.order
zygor.isCollapsed = true
local builds, layouts = 0, 0
for _, module in ipairs({zygor, questie}) do
    function module:Update() builds = builds + 1; return 40 end
end
custom.modules = {zygor, questie}
function custom:MarkDirty()
    layouts = layouts + 1
    Common.CustomHost.Layout(self, 280)
end
local selected = true
Common.DaylightHost = {IsSelected=function() return selected end, GetContainer=function() return custom end}
assert(loadfile("integrations/guides/viewer_host.lua"))()
local host = Common.Host
custom:MarkDirty()
assert(NS.SetGuideTrackerViewerOrder({"polestar", "questierouter", "zygor"}))
assert(custom.modules[1] == questie and custom.modules[2] == zygor and zygor.isCollapsed)
assert(builds == 2 and layouts == 2, "Custom host rebuilt or reattached Viewer rows while reordering")
assert(NS.SetGuideTrackerViewerOrder({"polestar", "questierouter", "zygor"}) and layouts == 2)
assert(NS.GetGuideTrackerViewerOrder()[1] == "polestar", "A disabled provider lost its place")

selected = false
local native = f.Frame()
local unrelated = {uiOrder=4}
native.modules = {unrelated}
function native:MarkDirty()
    assert(not f.combat, "Native tracker reordered in combat")
    if self.needsSorting then
        table.sort(self.modules, function(a, b) return a.uiOrder < b.uiOrder end)
        self.needsSorting = nil
    end
end
local attached = {}
local manager = {}
function manager:GetContainerForModule(module) return attached[module] end
function manager:SetModuleContainer(module, destination)
    attached[module] = destination
    destination.modules[#destination.modules + 1] = module
    destination.needsSorting = true
    destination:MarkDirty()
end
ObjectiveTrackerFrame, ObjectiveTrackerManager = native, manager
for _, module in ipairs({zygor, polestar, questie}) do assert(host.TryRegisterOnce(manager, module, native)) end
assert(native.modules[1] == polestar and native.modules[2] == questie and native.modules[3] == zygor)
f.combat = true
NS.SetGuideTrackerViewerOrder({"questierouter", "zygor", "polestar"})
NS.SetGuideTrackerViewerOrder({"zygor", "polestar", "questierouter"})
assert(native.modules[1] == polestar and polestar.uiOrder == 2)
f.combat = false
f.Fire("PLAYER_REGEN_ENABLED")
assert(native.modules[1] == zygor and native.modules[2] == polestar and native.modules[3] == questie)
assert(native.modules[4] == unrelated and unrelated.uiOrder == 4 and attached[zygor] == native and zygor.isCollapsed)
NS.SetGuideTrackerViewerOrder(NS.GetDefaultGuideTrackerViewerOrder())
assert(not db.guideTrackerViewerOrder and zygor.uiOrder == providers.zygor.order
    and questie.uiOrder == providers.questierouter.order and polestar.uiOrder == providers.polestar.order)

local viewport = f.Frame()
local page = f.Frame(viewport)
local viewportBottom = 0
function viewport:GetTop() return 300 end
function viewport:GetBottom() return viewportBottom end
local cursorY, scaledX, scaledY = 0, 200, 250
GetCursorPosition = function() return scaledX, scaledY end
local widgets = NS.Internal.Interface.canvas.CreateWidgets({
    CreateFrame=CreateFrame, GetScrollChild=function() return page end, GetCursorY=function() return cursorY end,
    SetCursorY=function(value) cursorY = value end, PAD=16, COLOR_TEXT_DIM={1,1,1,1}, HideTip=function() end,
})
local list = widgets.AddReorderList("Guide Viewer Order", NS.GetGuideTrackerViewerOrder, NS.SetGuideTrackerViewerOrder,
    NS.GetDefaultGuideTrackerViewerOrder, function(key) return key end)
function list:GetRect() return 50, 50, 200, self:GetHeight() end
local rows = {}
local reset
for _, frame in ipairs(f.frames) do
    if frame:GetParent() == list and frame:GetScript("OnDragStart") then rows[#rows + 1] = frame end
    if frame:GetParent() == page and frame:GetScript("OnClick") then reset = frame end
end
assert(#rows == 7 and reset and not reset:IsShown())
rows[1]:GetScript("OnDragStart")()
list:GetScript("OnUpdate")()
assert(not db.guideTrackerViewerOrder, "Dragging saved the order before release")
rows[1]:GetScript("OnDragStop")()
assert(NS.GetGuideTrackerViewerOrder()[4] == "zygor" and rows[4].label:GetText() == "zygor" and reset:IsShown())
assert(not list:GetScript("OnUpdate"))

viewportBottom = 150
rows[4]:GetScript("OnDragStart")()
rows[4]:GetScript("OnDragStop")()
assert(NS.GetGuideTrackerViewerOrder()[4] == "zygor", "Drop through the clipped region changed the order")
viewportBottom, scaledY = 0, 420
rows[4]:GetScript("OnDragStart")()
list:GetScript("OnHide")()
rows[4]:GetScript("OnDragStop")()
assert(NS.GetGuideTrackerViewerOrder()[4] == "zygor" and not list:GetScript("OnUpdate"))
reset:GetScript("OnClick")()
assert(NS.GetGuideTrackerViewerOrder()[1] == "zygor" and not reset:IsShown())

local kaliel = f.Frame()
kaliel.init, kaliel.modules, kaliel.MarkDirty = true, {unrelated}, native.MarkDirty
KT_ObjectiveTrackerFrame = kaliel
for _, module in ipairs({zygor, polestar, questie}) do
    assert(host.TryRegisterOnce(host.GetManager(), module, kaliel))
end
NS.SetGuideTrackerViewerOrder({"questierouter", "polestar", "zygor"})
assert(kaliel.modules[1] == questie and kaliel.modules[2] == polestar and kaliel.modules[3] == zygor)
assert(kaliel.modules[4] == unrelated and zygor.isCollapsed)
print("Guide Viewer order: profile normalization, in-place sorting, native and Kaliel refresh, combat deferral, drag and reset passed")
