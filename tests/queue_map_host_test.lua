local frames, timers = {}, {}
local Methods = {}
local function NoOp() end

function Methods:Fire(event, ...)
    if self.scripts[event] then self.scripts[event](self, ...) end
    for _, hook in ipairs(self.hooks[event] or {}) do hook(self, ...) end
end

function Methods:SetScript(event, callback) self.scripts[event] = callback end
function Methods:HookScript(event, callback)
    local list = self.hooks[event] or {}
    list[#list + 1] = callback
    self.hooks[event] = list
end

function Methods:SetShown(shown)
    if self.shown == shown then return end
    self.shown = shown
    self:Fire(shown and "OnShow" or "OnHide")
end

function Methods:Show() self:SetShown(true) end
function Methods:Hide() self:SetShown(false) end
function Methods:IsShown() return self.shown end
function Methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Methods:GetParent() return self.parent end
function Methods:SetParent(parent) self.parent = parent end
function Methods:GetChildren()
    self.childReads = (self.childReads or 0) + 1
    local children = {}
    for _, frame in ipairs(frames) do
        if frame.parent == self then children[#children + 1] = frame end
    end
    return unpack(children)
end

function Methods:ClearAllPoints() self.point, self.allPoints = nil, nil end
function Methods:GetNumPoints() return self.point and 1 or 0 end
function Methods:GetPoint() return unpack(self.point or {}) end
function Methods:SetPoint(point, relative, target, x, y)
    self.pointWrites = (self.pointWrites or 0) + 1
    self.point = { point, relative, target, x, y }
    if point == "TOPLEFT" and target == "TOPLEFT" then
        local units = relative:GetEffectiveScale() / self:GetEffectiveScale()
        self.left = relative:GetLeft() * units + (x or 0)
        self.top = relative:GetTop() * units + (y or 0)
    end
end

function Methods:SetAllPoints(relative) self.allPoints = relative end
function Methods:SetAlpha(alpha) self.alpha = alpha end
function Methods:GetAlpha() return self.alpha end
function Methods:GetEffectiveAlpha() return self.alpha * (self.parent and self.parent:GetEffectiveAlpha() or 1) end
function Methods:SetScale(scale) self.scale = scale end
function Methods:GetScale() return self.scale end
function Methods:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
function Methods:GetFrameStrata() return self.strata end
function Methods:SetFrameStrata(strata) self.strata = strata end
function Methods:GetFrameLevel() return self.level end
function Methods:SetFrameLevel(level) self.level = level end
function Methods:GetLeft() return self.left end
function Methods:GetRight() return self.left + self.width end
function Methods:GetTop()
    if self.unreadable then error("restricted geometry") end
    return self.top
end
function Methods:GetBottom() return self.top - self.height end
function Methods:GetWidth() return self.allPoints and self.allPoints:GetWidth() or self.width end
function Methods:GetHeight() return self.allPoints and self.allPoints:GetHeight() or self.height end
function Methods:SetWidth(width) self.width = width end
function Methods:SetSize(width, height)
    if self.width == width and self.height == height then return end
    self.width, self.height = width, height
    for _, frame in ipairs(frames) do
        if frame.allPoints == self and frame.scripts.OnSizeChanged then frame:Fire("OnSizeChanged", width, height) end
    end
end
function Methods:SetText(text) self.text = text end
function Methods:SetClampedToScreen(clamped) self.clamped = clamped end
function Methods:IsClampedToScreen() return self.clamped == true end
function Methods:IsForbidden() return self.forbidden == true end
function Methods:EnableMouse(enabled) self.mouse = enabled end
function Methods:StartMoving() self.moving = true end
function Methods:StopMovingOrSizing() self.moving = false end

for _, method in ipairs({ "SetAtlas", "SetJustifyH", "SetBlendMode", "SetEnabled", "RegisterEvent", "RegisterForDrag", "SetMovable" }) do
    Methods[method] = NoOp
end

local function NewRegion(parent)
    return setmetatable({
        parent = parent, shown = true, scripts = {}, hooks = {}, left = 0, top = 0,
        width = 55, height = 55, scale = 1, alpha = 1, strata = "HIGH", level = 5,
    }, { __index = Methods })
end

Methods.CreateTexture, Methods.CreateFontString = NewRegion, NewRegion
function CreateFrame(_, name, parent, template)
    assert(template ~= "QuestLogBorderFrameTemplate" or QuestMapFrame, "Quest-log art was requested before the map was loaded")
    local frame = NewRegion(parent)
    if template == "LargeSideTabButtonTemplate" then frame.Icon = NewRegion(frame) end
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end

function Mixin(target, source)
    for key, value in pairs(source) do target[key] = value end
    return target
end

function CreateFromMixins(source) return Mixin({}, source) end
SidePanelTabButtonMixin = {
    OnMouseDown = NoOp, OnMouseUp = NoOp, OnEnter = NoOp,
    SetChecked = function(frame, checked) frame.checked = checked end,
}

C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local function Flush()
    while #timers > 0 do table.remove(timers, 1)() end
end

local listeners = {}
EventRegistry = {}
function EventRegistry:RegisterCallback(event, callback) listeners[event] = callback end
QuestLogDisplayMode = { Quests = 0, Events = 1 }

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(2200, 1000)
UIParent.top = 1000
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame.left, WorldMapFrame.top = 480, 850
WorldMapFrame:SetSize(980, 700)
WorldMapFrame.ScrollContainer = CreateFrame("Frame", nil, WorldMapFrame)
WorldMapFrame.ScrollContainer.left, WorldMapFrame.ScrollContainer.top = 480, 815
WorldMapFrame.ScrollContainer:SetSize(650, 650)
WorldMapFrame.IsMaximized = function(frame) return frame.maximized end
QuestMapFrame = CreateFrame("Frame", "QuestMapFrame", WorldMapFrame)
QuestMapFrame.left, QuestMapFrame.top = 1130, 816
QuestMapFrame:SetSize(330, 650)
QuestMapFrame.ContentsAnchor = CreateFrame("Frame", nil, QuestMapFrame)
local displayChanges = 0
function QuestMapFrame:SetDisplayMode(mode)
    displayChanges = displayChanges + 1
    listeners["QuestLog.SetDisplayMode"](nil, mode)
end

local forever, callbacks = false, {}
local selection = "queue-1"
local queue = { id = selection, label = "Example Queue" }
AzerothWaypointNS = {
    State = {},
    Internal = { Daylight = { GetAPI = function()
        return { On = function(event, callback)
            if event == "SettingChanged" then
                assert(not callbacks.settingChanged)
                callbacks.settingChanged = callback
            else
                assert(event == "Login")
            end
            return {}
        end }
    end } },
    IsWoWForever = function() return forever end,
    After = C_Timer.After,
    GetQueuePanelSelection = function() return selection end,
    SetQueuePanelSelection = function(key) selection = key end,
    Msg = error,
}

assert(loadfile("core/scheduling.lua"))()
assert(loadfile("interface/queue/state.lua"))()
assert(loadfile("interface/queue/map_host.lua"))()
assert(loadfile("interface/queue/widgets.lua"))()
local NS = AzerothWaypointNS
local M = NS.Internal.QueueUI
local ui = M.ui
M.CreateListPage = function(content)
    content.listPage = CreateFrame("Frame", nil, content)
    M.CreateInsetBorder(content.listPage)
end
M.CreateDetailPage = function(content)
    content.detailPage = CreateFrame("Frame", nil, content)
    content.backButton = CreateFrame("Button", nil, content)
end
M.ResolveSelectedQueue = function() return queue, "manual" end
M.FindQueueByKey = function(_, key) return key == queue.id and queue or nil end
local ReflowFooterButtons = M.ReflowFooterButtons
M.ReflowFooterButtons = function() return 0 end
M.StyleQueueButton = NoOp
for _, name in ipairs({ "PruneBulkSelections", "BuildQueueRows", "RenderListPage", "RenderDetailPage", "BuildDetailRows",
    "UpdateBulkDeleteButton", "SetContentPageBounds", "OpenImportWindow", "IsManualQueueActive" }) do
    M[name] = NoOp
end
assert(loadfile("interface/queue/panel.lua"))()
local initializer = frames[#frames]
initializer:Fire("OnEvent", "PLAYER_LOGIN")
assert(ui.tab:GetParent() == QuestMapFrame and ui.content:GetParent() == QuestMapFrame)
assert(not ui.companion, "Stock clients must not create companion controls")

local tab, content = ui.tab, ui.content
tab:Fire("OnMouseUp", "LeftButton", true)
Flush()
assert(content:IsShown() and tab.checked and displayChanges == 2)
QuestMapFrame:SetDisplayMode(QuestLogDisplayMode.Events)
assert(not content:IsShown() and not tab.checked)

forever = true
local journal = CreateFrame("Frame", "DaylightUIQuestJournal", QuestMapFrame)
local function Veil(alpha)
    for _, frame in ipairs({ QuestMapFrame:GetChildren() }) do
        if frame ~= journal then frame:SetAlpha(alpha) end
    end
end
Veil(0)
assert(tab:GetEffectiveAlpha() == 0 and content:GetEffectiveAlpha() == 0)
initializer:Fire("OnEvent", "ADDON_LOADED", "DaylightUI_Quests")
Flush()
assert(tab:GetParent() == WorldMapFrame and tab:GetEffectiveAlpha() == 1)
assert(content:GetParent() == ui.companion and content:GetEffectiveAlpha() == 1)
assert(tab.point[2] == WorldMapFrame, "The queue tab must not anchor to another addon's tab")

local changesBeforeOpening = displayChanges
tab:Fire("OnMouseUp", "RightButton", true)
assert(not content:IsShown())
tab:Fire("OnMouseUp", "LeftButton", true)
Flush()
assert(content:IsShown() and tab.checked and content.closeButton:IsShown())
assert(ui.companion:GetLeft() > tab:GetRight() and journal:IsVisible())
assert(not content.questsButton:IsShown() and not content.dragHandle:IsShown())
assert(displayChanges == changesBeforeOpening, "The companion host must not switch quest log modes")
content.closeButton:Fire("OnClick")
assert(not content:IsShown() and journal:IsShown())

-- The minimap menu and slash commands share this entry point and forceQuestLog flag.
function ToggleWorldMap()
    WorldMapFrame:Show()
    listeners.WorldMapOnShow()
end
WorldMapFrame:Hide()
NS.ShowQueuePanel({ forceQuestLog = true })
Flush()
assert(WorldMapFrame:IsVisible() and content:IsVisible() and displayChanges == changesBeforeOpening)
assert(ui.tab == tab and ui.content == content)
M.SetViewMode("detail")
M.Refresh()
assert(content.detailPage:IsShown() and content.closeButton:IsShown())

local spoken = CreateFrame("Frame", "SpokenPlacesPanel", WorldMapFrame)
spoken.left, spoken.top = 1525, 850
spoken:SetSize(440, 700)
initializer:Fire("OnEvent", "ADDON_LOADED", "Spoken_Places")
WorldMapFrame:Fire("OnSizeChanged")
assert(#timers == 1, "Layout bursts must coalesce")
Flush()
assert(ui.companion:GetRight() < WorldMapFrame:GetLeft(), "An open Place Story panel must stay clear of the queue")

spoken:Hide()
Flush()
assert(ui.companion:GetLeft() > tab:GetRight())
WorldMapFrame:SetScale(1.1)
WorldMapFrame:Fire("OnSizeChanged")
Flush()
assert(ui.companion:GetLeft() > tab:GetRight() * tab:GetEffectiveScale(), "The dock must account for the map scale")
WorldMapFrame:SetScale(1)

-- Mapzeroth builds its panel on demand and can change docks while it is shown.
function hooksecurefunc(object, method, callback)
    local original = object[method]
    object[method] = function(...)
        original(...)
        callback(...)
    end
end
local nativePanel = {}
local function GetMapzerothFrame()
    return rawget(_G, "MapzerothRebuildPanel")
end
function nativePanel:Reanchor()
    local frame = assert(GetMapzerothFrame())
    frame.left, frame.top = tab:GetRight() + 2, WorldMapFrame:GetTop()
end
function nativePanel:SetDocked(docked)
    local frame = GetMapzerothFrame()
    if not frame then
        frame = CreateFrame("Frame", "MapzerothRebuildPanel", WorldMapFrame)
        frame:SetSize(330, 500)
    end
    frame:SetParent(docked and WorldMapFrame or UIParent)
    if docked then self:Reanchor() end
end
function nativePanel:ApplyScale(scale)
    local frame = assert(GetMapzerothFrame())
    frame:SetScale(scale)
    frame.left = (tab:GetRight() + 2) / scale
    frame.top = WorldMapFrame:GetTop() / scale
end
MapzerothAddon = { Panel = nativePanel }
UIParent:SetSize(2650, 1000)
initializer:Fire("OnEvent", "ADDON_LOADED", "Mapzeroth")
Flush()
nativePanel:SetDocked(true)
assert(#timers == 1, "The native dock notifications should coalesce")
Flush()
local mapzerothFrame = assert(GetMapzerothFrame())
assert(ui.companion:GetLeft() > mapzerothFrame:GetRight(), "Both panels claimed the same dock")
assert(ui.companion.point[2] == WorldMapFrame, "The two companions must not anchor to each other")

-- Right placement can hit a second panel after clearing the first.
spoken.left = mapzerothFrame:GetRight() - 10
spoken:SetSize(200, 700)
spoken:Show()
Flush()
assert(ui.companion:GetLeft() > spoken:GetRight())
spoken:Hide()
Flush()

nativePanel:SetDocked(false)
Flush()
assert(ui.companion:GetLeft() < mapzerothFrame:GetRight(), "A popped-out window displaced the queue")
nativePanel:SetDocked(true)
Flush()
assert(ui.companion:GetLeft() > mapzerothFrame:GetRight(), "Redocking did not update the open queue")
mapzerothFrame:Hide()
Flush()
assert(ui.companion:GetLeft() < mapzerothFrame:GetRight(), "A hidden panel still occupied its dock")
mapzerothFrame:Show()
mapzerothFrame:SetSize(350, 500)
mapzerothFrame:Fire("OnSizeChanged")
Flush()
assert(ui.companion:GetLeft() > mapzerothFrame:GetRight())

nativePanel:ApplyScale(1.2)
Flush()
assert(ui.companion:GetLeft() > mapzerothFrame:GetRight() * mapzerothFrame:GetEffectiveScale())
nativePanel:ApplyScale(1)
Flush()

UIParent:SetSize(2100, 1000)
initializer:Fire("OnEvent", "DISPLAY_SIZE_CHANGED")
Flush()
assert(ui.companion:GetRight() < WorldMapFrame:GetLeft(), "Tight space did not use the left dock")

WorldMapFrame.maximized = true
mapzerothFrame.left = 870
mapzerothFrame:Fire("OnSizeChanged")
Flush()
assert(ui.companion:GetParent() == UIParent and ui.companion:GetRight() < mapzerothFrame:GetLeft(),
    "The floating queue did not clear Mapzeroth inside the map")
mapzerothFrame:Hide()
UIParent:SetSize(2200, 1000)
Flush()

WorldMapFrame.maximized = true
WorldMapFrame:SetSize(1720, 700)
WorldMapFrame:Fire("OnSizeChanged")
Flush()
assert(ui.companion:GetParent() == UIParent and ui.companion.clamped)
assert(content.dragHandle:IsShown() and tab:GetRight() <= UIParent:GetRight())
assert(ui.companion:GetRight() <= QuestMapFrame:GetLeft())
content.dragHandle:Fire("OnDragStart")
assert(ui.companion.moving)
WorldMapFrame:Hide()
assert(not content:IsShown() and not ui.companion.moving)
WorldMapFrame:Show()
listeners.WorldMapOnShow()
Flush()
assert(not content:IsShown() and tab:IsVisible())

tab:Fire("OnMouseUp", "LeftButton", true)
Flush()
journal:Hide()
Veil(1)
assert(callbacks.settingChanged, "Missing journal settings listener")("Quests", "journal")
Flush()
assert(tab:GetParent() == QuestMapFrame and content:GetParent() == QuestMapFrame)
assert(tab:GetEffectiveAlpha() == 1 and content:GetEffectiveAlpha() == 1)
assert(content.allPoints == QuestMapFrame.ContentsAnchor and content.detailPage:IsShown())
assert(selection == queue.id and not content.closeButton:IsShown())

-- GW2_UI styling choices cannot move the queue. Only an installed map skin
-- opts either client into the companion layout.
GW2_ADDON = {}
WorldMapFrame.maximized = false
WorldMapFrame:SetSize(980, 700)
for _, isForever in ipairs({false, true}) do
    forever = isForever
    WorldMapFrame.gwBodyEdge = nil
    assert(not M.MapHost.UsesCompanion(WorldMapFrame, QuestMapFrame))
    WorldMapFrame.gwBodyEdge = WorldMapFrame:CreateTexture()
    listeners.WorldMapOnShow()
    Flush()
    assert(tab:GetParent() == WorldMapFrame and content:GetParent() == ui.companion)
    local modeCount = displayChanges
    tab:Fire("OnMouseUp", "LeftButton", true)
    Flush()
    assert(not content:IsShown() and not tab.checked)
    NS.ShowQueuePanel({ forceQuestLog = true })
    Flush()
    M.SetViewMode("detail")
    M.Refresh()
    assert(content.detailPage:IsVisible() and content.closeButton:IsVisible())
    assert(ui.companion:GetLeft() > QuestMapFrame:GetRight() and displayChanges == modeCount)
    UIParent:SetSize(2650, 1000)
    nativePanel:Reanchor()
    mapzerothFrame:Show()
    Flush()
    assert(ui.companion:GetLeft() > mapzerothFrame:GetRight(), "The GW2 map queue overlapped Mapzeroth")
    mapzerothFrame:Hide()
    Flush()
    UIParent:SetSize(1480, 1000)
    WorldMapFrame.left = 45
    WorldMapFrame:SetSize(1415, 700)
    WorldMapFrame.ScrollContainer.left = 45
    WorldMapFrame.ScrollContainer:SetSize(1415, 650)
    initializer:Fire("OnEvent", "DISPLAY_SIZE_CHANGED")
    Flush()
    assert(ui.companion:GetParent() == UIParent and ui.companion:GetRight() <= QuestMapFrame:GetLeft())
    assert(content.closeButton:IsVisible() and tab:GetRight() <= QuestMapFrame:GetLeft())
    UIParent:SetSize(2200, 1000)
    WorldMapFrame.left, WorldMapFrame.ScrollContainer.left = 480, 480
    WorldMapFrame:SetSize(980, 700)
    WorldMapFrame.ScrollContainer:SetSize(650, 650)
    initializer:Fire("OnEvent", "DISPLAY_SIZE_CHANGED")
    Flush()
    content.closeButton:Fire("OnClick")
    QuestMapFrame:Hide()
    Flush()
    tab:Fire("OnMouseUp", "LeftButton", true)
    Flush()
    assert(tab:IsVisible() and content:IsVisible() and displayChanges == modeCount)
    WorldMapFrame:Hide()
    assert(not content:IsShown())
    WorldMapFrame:Show()
    QuestMapFrame:Show()
    WorldMapFrame.gwBodyEdge = nil
    listeners.WorldMapOnShow()
    Flush()
    assert(content:GetParent() == QuestMapFrame)
    tab:Fire("OnMouseUp", "LeftButton", true)
    Flush()
end

-- Native controller UI is a Forever-only host change. World Map events only enqueue work.
local gamepad = true
InputUtil = { IsGamepadUIEnabled = function() return gamepad end }
forever = false
assert(not M.MapHost.UsesDetachedControls())
forever = true
local controllerDisplayChanges = displayChanges
local wasOpen = content:IsShown()
initializer:Fire("OnEvent", "CVAR_UPDATE", "InputDeviceInterfaceStyle")
assert(tab:GetParent() == QuestMapFrame)
Flush()
assert(tab:GetParent() == UIParent and ui.companion:GetParent() == UIParent)
assert(content:GetParent() == ui.companion and tab:IsShown() and content:IsShown() == wasOpen)
if wasOpen then content.closeButton:Fire("OnClick") end
local observer = frames[#frames]
assert(observer.scripts.OnUpdate and observer:IsShown())
local function UpdateObserver(elapsed)
    if observer:IsShown() then observer:Fire("OnUpdate", elapsed) end
    Flush()
end

local defaultTop = tab:GetTop()
local edgeX, mapTop = WorldMapFrame:GetRight(), WorldMapFrame:GetTop()
WorldMapFrame.BorderFrame = CreateFrame("Frame", nil, WorldMapFrame)
local function Neighbor(parent, anchor, left, top, width, height)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", left - anchor:GetLeft(), top - anchor:GetTop())
    frame:SetSize(width, height)
    return frame
end
Neighbor(UIParent, UIParent, edgeX, mapTop, 250, 700)
Neighbor(UIParent, tab, edgeX, mapTop, 250, 700)
local forbidden = Neighbor(UIParent, WorldMapFrame, edgeX, mapTop, 250, 700)
forbidden.forbidden = true
local unreadable = Neighbor(UIParent, WorldMapFrame, edgeX, mapTop, 250, 700)
unreadable.unreadable = true
local tooltip = Neighbor(UIParent, WorldMapFrame, edgeX, mapTop, 250, 700)
tooltip.strata = "TOOLTIP"
local reads, writes = UIParent.childReads, tab.pointWrites
for _ = 1, 3 do UpdateObserver(0.25) end
assert(UIParent.childReads == reads and tab.pointWrites == writes)
UpdateObserver(0.25)
assert(UIParent.childReads == reads + 1 and tab:GetTop() == defaultTop and tab.pointWrites == writes,
    "Unrelated, dependent and unreadable windows must not change the tab layout")

local attached = Neighbor(QuestMapFrame, QuestMapFrame, edgeX, defaultTop, 45, 50)
local spokenTab = Neighbor(UIParent, WorldMapFrame.BorderFrame, edgeX + 5, defaultTop - 55, 63, 55)
local unknownTab = Neighbor(UIParent, spokenTab, edgeX + 2, defaultTop - 115, 57, 40)
local glow = Neighbor(WorldMapFrame.BorderFrame, WorldMapFrame, WorldMapFrame:GetLeft() - 20,
    mapTop + 24, WorldMapFrame:GetWidth() + 34, WorldMapFrame:GetHeight() + 38)
WorldMapFrame.BorderFrame.FrameGlow = glow
local surround = Neighbor(UIParent, WorldMapFrame, WorldMapFrame:GetLeft() - 6,
    mapTop + 6, WorldMapFrame:GetWidth() + 12, WorldMapFrame:GetHeight() + 12)
glow:Hide()
surround:Hide()
listeners.WorldMapMaximized()
assert(tab:GetTop() == defaultTop)
Flush()
assert(tab:GetTop() < unknownTab:GetBottom() and tab.point[2] == WorldMapFrame)
assert(next(spokenTab.hooks) == nil and next(unknownTab.hooks) == nil)
local dockedWrites = tab.pointWrites
for _, focused in ipairs({ true, false, true }) do
    glow:SetShown(focused)
    surround:SetShown(focused)
    UpdateObserver(0.25)
    assert(tab:IsShown() and tab.pointWrites == dockedWrites, "Map focus art displaced the Queues tab")
end
glow:Hide()
surround:Hide()
attached:Hide()
UpdateObserver(0.25)
assert(tab:GetTop() == defaultTop, "The hidden first tab still occupied its slot")
spokenTab:Hide()
UpdateObserver(0.25)
assert(tab:GetTop() == defaultTop, "A hidden neighbor still occupied its tab slot")
local lateTab = Neighbor(UIParent, WorldMapFrame, edgeX, defaultTop, 55, 55)
for _ = 1, 4 do UpdateObserver(0.25) end
assert(tab:GetTop() < lateTab:GetBottom(), "A newly created top-level tab was missed")
unknownTab:Hide()
lateTab:Hide()

UIParent:SetSize(2650, 1000)
spoken:SetParent(UIParent)
spoken:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", edgeX + 60 - WorldMapFrame:GetLeft(), 0)
spoken:SetSize(280, 700)
spoken:Show()
mapzerothFrame:SetParent(UIParent)
mapzerothFrame:SetPoint("TOPLEFT", spoken, "TOPLEFT", spoken:GetWidth() + 8, 0)
mapzerothFrame:SetSize(310, 580)
mapzerothFrame:Show()
initializer:Fire("OnEvent", "ADDON_LOADED", "Mapzeroth")
Flush()
local drawCount, measuredWidth = 0, 0
M.RenderListPage = function()
    drawCount = drawCount + 1
    measuredWidth = M.GetScrollContentWidth(M.ui.content)
end
M.ReflowFooterButtons = ReflowFooterButtons
M.SetViewMode("list")
ui.companion:SetSize(0, 0)
tab:Fire("OnMouseUp", "LeftButton", true)
assert(ui.companion:GetLeft() > mapzerothFrame:GetRight() and ui.companion.point[2] == WorldMapFrame)
assert(drawCount == 0, "A newly opened detached panel rendered before its bounds settled")
Flush()
assert(drawCount == 1 and measuredWidth == 330, "The first list render used the wrong panel width")
local _, _, _, _, importY = content.importButton:GetPoint()
local _, _, _, _, exportY = content.exportButton:GetPoint()
assert(importY == exportY, "The first detached footer laid out its buttons on separate rows")
QuestMapFrame:SetSize(380, 650)
UpdateObserver(0.25)
assert(drawCount == 2 and measuredWidth == 380, "A visible panel resize left the list at its old width")
UpdateObserver(0.25)
assert(drawCount == 2, "An unchanged panel re-rendered during periodic map layout")
QuestMapFrame:SetSize(330, 650)
UpdateObserver(0.25)
mapzerothFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", mapzerothFrame:GetLeft(), mapzerothFrame:GetTop() - UIParent:GetTop())
for _ = 1, 4 do UpdateObserver(0.25) end
assert(ui.companion:GetLeft() > spoken:GetRight() and ui.companion:GetLeft() < mapzerothFrame:GetRight(),
    "The popup still reserved a map dock after detaching")
spoken:Hide()
WorldMapFrame:SetScale(1.1)
UpdateObserver(0.25)
assert(tab:GetScale() == 1.1 and ui.companion:GetLeft() > tab:GetRight() * tab:GetEffectiveScale())
WorldMapFrame:SetScale(1)
WorldMapFrame:SetAlpha(0.5)
UpdateObserver(0.01)
assert(tab:GetAlpha() == 0.5 and ui.companion:GetAlpha() == 0.5)
WorldMapFrame:SetAlpha(1)

UIParent:SetSize(1480, 1000)
WorldMapFrame.left, WorldMapFrame.ScrollContainer.left = 30, 30
WorldMapFrame:SetSize(1430, 700)
WorldMapFrame.ScrollContainer:SetSize(1100, 650)
initializer:Fire("OnEvent", "DISPLAY_SIZE_CHANGED")
Flush()
assert(tab:IsShown() and tab:GetRight() <= QuestMapFrame:GetLeft() and content.dragHandle:IsShown())
assert(ui.companion.clamped and ui.companion.point[2] == UIParent)
-- This genuine dock occupies the last usable column, inside the map canvas.
local crowded = Neighbor(UIParent, WorldMapFrame, QuestMapFrame:GetLeft() - 120, mapTop, 120, 700)
listeners.WorldMapMaximized()
Flush()
assert(not tab:IsShown() and content:IsShown() and ui.companion.clamped)
crowded:Hide()

WorldMapFrame:Hide()
listeners.WorldMapOnHide()
WorldMapFrame:Show()
listeners.WorldMapOnShow()
Flush()
assert(tab:IsShown() and not content:IsShown(), "A reopened map inherited the previous queue session")
tab:Fire("OnMouseUp", "LeftButton", true)

WorldMapFrame:Hide()
listeners.WorldMapOnHide()
assert(ui.active, "Controller registry callbacks must defer frame changes")
Flush()
assert(not tab:IsShown() and not content:IsShown() and not observer:IsShown())
reads = UIParent.childReads
UpdateObserver(2)
assert(UIParent.childReads == reads, "The closed map was still being scanned")
assert(NS.ShowQueuePanel({ forceQuestLog = true }))
assert(not WorldMapFrame:IsShown() and content:IsVisible() and ui.companion:GetAlpha() == 1)
assert(ui.companion.point[2] == UIParent and ui.companion.clamped and not observer:IsShown())
WorldMapFrame:Show()
listeners.WorldMapOnShow()
Flush()
assert(tab:IsVisible() and content:IsVisible() and observer:IsShown())
assert(displayChanges == controllerDisplayChanges, "Controller queues touched native quest log modes")

WorldMapFrame:SetScale(1.1)
UpdateObserver(0.25)
gamepad = false
initializer:Fire("OnEvent", "CVAR_UPDATE", "INPUTDEVICEINTERFACESTYLE")
Flush()
assert(tab:GetParent() == QuestMapFrame and content:GetParent() == QuestMapFrame)
assert(tab:GetScale() == 1 and content:IsShown() and not observer:IsShown())

-- A cold controller session can open from the minimap before the World Map's addon is loaded.
local oldSides = SidePanelTabButtonMixin
WorldMapFrame:Hide()
for _, name in ipairs({ "WorldMapFrame", "QuestMapFrame", "SidePanelTabButtonMixin", "InputUtil" }) do
    rawset(_G, name, nil)
end
GetCVar = function(name) return name == "InputDeviceInterfaceStyle" and "1" or "0" end
local mapLoads = 0
C_AddOns = { LoadAddOn = function() mapLoads = mapLoads + 1 end }
NS.After = C_Timer.After
M.ui = nil
assert(loadfile("interface/queue/state.lua"))()
assert(loadfile("interface/queue/map_host.lua"))()
assert(loadfile("interface/queue/widgets.lua"))()
M.StyleQueueButton = NoOp
assert(loadfile("interface/queue/panel.lua"))()
initializer = frames[#frames]
initializer:Fire("OnEvent", "PLAYER_LOGIN")
Flush()
assert(not M.ui.content)
local beforeStandalone = drawCount
assert(NS.ShowQueuePanel({ forceQuestLog = true }))
assert(mapLoads == 0 and not M.ui.tab and M.ui.content:IsVisible() and M.ui.companion:GetParent() == UIParent)
Flush()
assert(drawCount == beforeStandalone + 1 and measuredWidth == 400, "Standalone opening rendered before sizing")
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame.left, WorldMapFrame.top = 250, 850
WorldMapFrame:SetSize(550, 600)
SidePanelTabButtonMixin = oldSides
local freshNeighbor = Neighbor(UIParent, WorldMapFrame, 800, 790, 55, 55)
local mapzerothShowHooks = #mapzerothFrame.hooks.OnShow
initializer:Fire("OnEvent", "ADDON_LOADED", "Blizzard_WorldMap")
listeners.WorldMapOnShow()
assert(not M.ui.tab)
Flush()
assert(M.ui.tab:GetParent() == UIParent and M.ui.tab:GetTop() < freshNeighbor:GetBottom())
assert(M.ui.content:IsVisible() and M.ui.tab.checked)
QuestMapFrame = CreateFrame("Frame", "QuestMapFrame", WorldMapFrame)
QuestMapFrame.left, QuestMapFrame.top = 570, 820
QuestMapFrame:SetSize(230, 520)
QuestMapFrame.ContentsAnchor = CreateFrame("Frame", nil, QuestMapFrame)
listeners["QuestLog.SetDisplayMode"]()
Flush()
assert(next(WorldMapFrame.hooks) == nil and next(QuestMapFrame.hooks) == nil)
assert(next(QuestMapFrame.ContentsAnchor.hooks) == nil and next(freshNeighbor.hooks) == nil)
assert(#mapzerothFrame.hooks.OnShow == mapzerothShowHooks)

print("queue map host tests passed")
