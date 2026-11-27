local Common = {}
local forever, combat, loaded = false, false, true
local queue, frames = {}, {}
C_Timer = { After = function(_, callback) queue[#queue + 1] = callback end,
    NewTicker = function() error("Questie attachment should be event driven") end }
local function RunTimers()
    local passes = 0
    while #queue > 0 do
        local pending = queue
        queue = {}
        for _, callback in ipairs(pending) do callback() end
        passes = passes + 1
        assert(passes < 8, "Questie layout scheduled itself repeatedly")
    end
end

local function AssertUnlocked() assert(not combat, "Frame changed in combat") end
local methods = {}
function methods:RegisterEvent(event) self.events[event] = true end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:GetScript(name) return self.scripts[name] end
function methods:HookScript(name, fn)
    local original = self.scripts[name]
    self.scripts[name] = function(...)
        if original then original(...) end
        fn(...)
    end
end
function methods:SetParent(parent) AssertUnlocked(); self.parent = parent end
function methods:GetParent() return self.parent end
function methods:SetPoint(...) AssertUnlocked(); self.point = {...} end
function methods:ClearAllPoints() AssertUnlocked(); self.point = nil end
function methods:GetNumPoints() return self.point and 1 or 0 end
function methods:GetPoint(index)
    if self.point and (index == nil or index == 1) then return unpack(self.point) end
end
function methods:SetWidth(width) AssertUnlocked(); self.width = width end
function methods:GetWidth() return self.width end
function methods:SetHeight(height) AssertUnlocked(); self.height = height end
function methods:GetHeight() return self.height end
function methods:Show()
    AssertUnlocked()
    if self.shown then return end
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide() AssertUnlocked(); self.shown = false end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:GetScrollChild() return self.child end
function methods:GetVerticalScrollRange() return math.max(0, self.child:GetHeight() - self.parent:GetHeight()) end
function methods:GetVerticalScroll() return self.offset end
function methods:SetVerticalScroll(offset)
    AssertUnlocked()
    self.offset = offset
    if self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self, offset) end
end
function methods:UpdateScrollChildRect()
    self:SetVerticalScroll(math.min(self.offset, self:GetVerticalScrollRange()))
end
function methods:EnableMouseWheel(enabled) self.wheel = enabled end
function methods:IsMouseWheelEnabled() return self.wheel end
function CreateFrame(_, name, parent)
    local frame = setmetatable({ events = {}, scripts = {}, shown = true, width = 25, height = 25,
        parent = parent, offset = 0, wheel = false }, { __index = methods })
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end
local function Fire(event, argument)
    for _, frame in ipairs(frames) do
        if frame.events[event] then frame.scripts.OnEvent(frame, event, argument) end
    end
end
function hooksecurefunc(owner, method, callback)
    local original = owner[method]
    owner[method] = function(...) original(...); callback(...) end
end
function InCombatLockdown() return combat end
function GetScreenHeight() return 1000 end
function GetScreenWidth() return 1000 end

local modules = {}
AzerothWaypointNS = { Internal = { GuideTrackerViewer = Common, QuestieData = {
    GetLoadedModule = function(name) return modules[name] end,
} }, IsWoWForever = function() return forever end,
    IsAddonLoaded = function(name) return loaded and name == "Questie" end, After = C_Timer.After,
    Msg = function() error("Unexpected tracker warning") end,
    MaybeShowNativeTrackerWarningPopup = function() error("Native docking used for Questie") end }

assert(loadfile("integrations/guides/viewer_questie.lua"))()
assert(not Common.QuestieHost.IsSelected() and #frames == 0, "Retail installed a Questie host")
forever = true
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/viewer_custom_host.lua"))()
assert(loadfile("integrations/guides/viewer_questie.lua"))()
local ready
local profile = { trackerEnabled = true, TrackerHeight = 160, trackerHeightRatio = 0.35,
    trackerFontSizeZone = 12, trackerWidthRatio = 0.3, TrackerWidth = 0 }
local char = { isTrackerExpanded = true }
Questie = { db = { profile = profile, char = char }, API = { RegisterOnReady = function(callback) ready = callback end } }

local hostSelections = {}
Common.EllesmereHost = { IsSelected = function() return hostSelections.ellesmere end }
Common.DaylightHost = { IsSelected = function() return hostSelections.daylight end, RegisterReadyCallback = function() end }
assert(loadfile("integrations/guides/viewer_host.lua"))()
assert(loadfile("integrations/guides/viewer_controller.lua"))()
local Host = Common.Host
assert(Host.GetHostID() == "questie" and not Host.IsBlizzardHost())
hostSelections.daylight, hostSelections.ellesmere = true, true
assert(Host.GetHostID() == "ellesmere")
KT_ObjectiveTrackerFrame = {}
assert(Host.GetHostID() == "kaliel")
KT_ObjectiveTrackerFrame, hostSelections.ellesmere = nil, false
assert(Host.GetHostID() == "daylight")
hostSelections.daylight = false
loaded = false
assert(Host.IsBlizzardHost(), "An absent Questie tracker claimed the host")
loaded = true

UIParent = CreateFrame("Frame")
local root = CreateFrame("Frame", "Questie_BaseFrame", UIParent)
local header = CreateFrame("Frame", "Questie_HeaderFrame", root)
local viewport = CreateFrame("Frame", "TrackedQuests", root)
local scroll = CreateFrame("ScrollFrame", nil, viewport)
local child = CreateFrame("Frame", nil, scroll)
scroll.child, viewport.ScrollChildFrame, viewport.ScrollFrame = child, child, scroll
header:SetHeight(20); header:SetWidth(100)
local first = CreateFrame("Button", nil, child)
local second = CreateFrame("Button", nil, child)
first:SetPoint("TOPLEFT", child, "TOPLEFT", 10, 0)
second:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, 0)
first:Hide(); second:Hide()
local hasRows, content = false, 0
local function Width(width)
    root:SetWidth(width); viewport:SetWidth(width); child:SetWidth(width)
end
local tracker = { started = true }
function tracker:UpdateHeight()
    if not char.isTrackerExpanded then
        local compact=header:GetHeight()+profile.trackerFontSizeZone+3
        child:SetHeight(compact);viewport:SetHeight(compact);root:SetHeight(compact);return
    end
    if not hasRows then return end -- Questie 12.12.0's empty-pool early return.
    local outer = math.min(content + 40, profile.TrackerHeight)
    child:SetHeight(content); viewport:SetHeight(outer - 40); root:SetHeight(outer)
    scroll:UpdateScrollChildRect()
end
function tracker:UpdateFormatting()
    if hasRows then self:UpdateHeight() end
end
function tracker:Toggle()
    profile.trackerEnabled = not profile.trackerEnabled
end
modules.QuestieTracker, modules.TrackerBaseFrame = tracker, {}
modules.TrackerLinePool = { GetFirstLine = function() return first end,
    GetCurrentLine = function() return hasRows and second or nil end }
local function RowOffset() return select(5, first:GetPoint(1)) end

local layoutCalls, enabled = 0, true
local nativeAcquire = function() end
local function NewViewer(order, height)
    return Common.CreateViewerController({ providerKey = "fixture" .. order, isEnabled = function() return enabled end,
        createModule = function()
            local module = CreateFrame("Frame")
            module.uiOrder, module.hasContents, module.AcquireFrame = order, true, nativeAcquire
            function module:SetContainer(parent) self.parentContainer = parent; self:SetParent(parent) end
            function module:MarkDirty() self.isDirty = true; self.parentContainer:MarkDirty() end
            function module:Update()
                layoutCalls = layoutCalls + 1
                self.isDirty = false
                return self.collapsed and 16 or height
            end
            function module:ToggleCollapsed()
                AssertUnlocked()
                self.collapsed = not self.collapsed
                self:MarkDirty()
            end
            return module
        end })
end

local zygor, dugi = NewViewer(2, 40), NewViewer(2.1, 25)
Fire("ADDON_LOADED", "Questie")
for _ = 1, 16 do
    local attached, pending = zygor:Attach()
    assert(not attached and pending, "Questie's startup wait was reported as a docking failure")
end
assert(not dugi:Attach())
RunTimers()
assert(not zygor.module and ready, "Questie readiness was bypassed")
Questie.API.isReady = true
ready()
RunTimers()
local container = zygor.container
assert(zygor:IsAttached() and dugi:IsAttached() and dugi.container == container and container:GetParent() == child)
assert(scroll:GetScrollChild() == child and first:GetParent() == child)
assert(child:GetWidth() == 240 and RowOffset() == -77 and child:GetHeight() == 77 and root:GetHeight() == 117,
    "A fresh empty tracker could not display both Viewers")
for _ = 1, 4 do tracker:UpdateHeight() end
RunTimers()
zygor:Detach();dugi:Detach();RunTimers()
assert(child:GetHeight()==25 and root:GetHeight()==25,"Empty native height passes captured AWP's augmented height")
zygor:Attach();dugi:Attach();RunTimers()
assert(child:GetHeight()==77 and root:GetHeight()==117,"Empty reattachment compounded guide heights")
char.isTrackerExpanded=false
tracker:UpdateHeight();RunTimers()
zygor:Detach();dugi:Detach();RunTimers()
local compact=header:GetHeight()+profile.trackerFontSizeZone+3
assert(child:GetHeight()==compact and root:GetHeight()==compact,"Empty collapsed native height was overwritten during detach")
char.isTrackerExpanded=true
zygor:Attach();dugi:Attach();RunTimers()
local _, anchor = second:GetPoint(1)
assert(anchor == first, "Questie's row chain was modified")
assert(AzerothWaypointNS.GetObjectiveTrackerVisibilityStatus().id == "questie")

hasRows, content = true, 180
Width(180); first:Show(); second:Show()
tracker:UpdateFormatting()
RunTimers()
assert(child:GetWidth() == 180 and child:GetHeight() == 257 and viewport:GetHeight() == 120)
assert(scroll:GetVerticalScrollRange() == 137)
scroll:GetScript("OnMouseWheel")(scroll, -3)
assert(scroll:GetVerticalScroll() == 120)
local calls = layoutCalls
for _ = 1, 12 do tracker:UpdateFormatting() end
RunTimers()
assert(layoutCalls == calls and RowOffset() == -77 and child:GetHeight() == 257, "Native passes dirtied or compounded guide layout")
assert(scroll:GetVerticalScroll() == 120, "A native height pass lost the combined scroll position")

combat = true
zygor.module:ToggleCollapsed()
dugi:Detach()
RunTimers()
assert(not zygor.module.collapsed and #container.modules == 2 and RowOffset() == -77)
combat = false
Fire("PLAYER_REGEN_ENABLED")
RunTimers()
assert(zygor.module.collapsed and #container.modules == 1 and RowOffset() == -22)
assert(dugi.module.AcquireFrame == nativeAcquire, "Detached module retained the custom host's pool methods")

char.isTrackerExpanded = false
viewport:Hide()
assert(not container:IsVisible(), "Questie's collapse was bypassed")
char.isTrackerExpanded = true
viewport:Show()
tracker:UpdateFormatting()
RunTimers()
assert(container:IsVisible() and RowOffset() == -22 and child:GetHeight() == 202)

local originalWheel = function() end
zygor:Detach()
RunTimers()
assert(RowOffset() == 0 and child:GetHeight() == 180 and viewport:GetHeight() == 120 and root:GetHeight() == 160)
assert(not scroll:GetScript("OnMouseWheel") and not scroll:IsMouseWheelEnabled(), "Fallback wheel input outlived the Viewer")
scroll:SetScript("OnMouseWheel", originalWheel)
zygor:Attach()
RunTimers()
assert(scroll:GetScript("OnMouseWheel") == originalWheel, "Existing scroll input was replaced")

first:SetPoint("TOPLEFT", child, "TOPLEFT", 14, 4)
zygor:MarkDirty()
RunTimers()
local _, reason = Host.GetAttachmentAvailability()
assert(reason:match("layout changed") and not zygor:IsAttached() and not container:IsVisible())
assert(RowOffset() == 4 and child:GetHeight() == 180, "Failing closed overwrote a foreign layout change")
zygor:Detach()
tracker:Toggle()
RunTimers()
assert(Host.IsBlizzardHost(), "Disabled Questie tracker retained host selection")
print("Questie Viewer host: readiness, host priority, shared scrolling, empty tracker, combat deferral, restore and contract rejection passed")
