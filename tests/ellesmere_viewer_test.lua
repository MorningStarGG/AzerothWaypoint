local replaceMethod = dofile("tests/replace_method.lua")
local NativePath = dofile("tests/native_path.lua")
-- Run from the addon root with Lua 5.1. Exercises the real host against the
-- installed Ellesmere renderer, with only WoW frame/game services simulated.
local function expect(value, message) if not value then error(message, 2) end end
local pending, frames, config = {}, {}, { customMaxHeight = 160, customScrollbar = "always" }
local function flush()
    local count = 0
    while #pending > 0 do
        count = count + 1; expect(count < 100, "Unbounded layout scheduling")
        table.remove(pending, 1)()
    end
end
local Frame = {}
Frame.__index = Frame
function Frame:SetParent(parent)
    if self.parent then
        for index, child in ipairs(self.parent.children) do
            if child == self then table.remove(self.parent.children, index); break end
        end
    end
    self.parent = parent
    if parent then parent.children[#parent.children + 1] = self end
end
function Frame:GetParent() return self.parent end
function Frame:GetChildren() return unpack(self.children) end
function Frame:GetNumChildren() return #self.children end
function Frame:GetObjectType() return self.kind end
function Frame:SetWidth(width) self.width = width end
function Frame:SetHeight(height) self.height = height end
function Frame:SetSize(width, height) self:SetWidth(width); self:SetHeight(height) end
function Frame:GetWidth() return self.width or 0 end
function Frame:GetHeight()
    if self.kind == "ScrollFrame" then return math.max(0, self.parent:GetHeight() - 32) end
    return self.height or 0
end
function Frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Frame:ClearAllPoints() self.points = {} end
function Frame:GetPoint(index) return unpack(self.points[index] or {}) end
function Frame:GetNumPoints() return #self.points end
function Frame:SetScript(key, fn) self.scripts[key] = fn end
function Frame:GetScript(key) return self.scripts[key] end
function Frame:HookScript(key, fn)
    local original = self:GetScript(key)
    self:SetScript(key, function(...) if original then original(...) end; fn(...) end)
end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:SetShown(value) if value then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:IsProtected() return self.protected == true end
function Frame:IsMouseOver() return self.hovered == true end
function Frame:SetScrollChild(child) self.scrollChild = child; child:SetParent(self) end
function Frame:GetScrollChild() return self.scrollChild end
function Frame:SetVerticalScroll(value) self.offset = value end
function Frame:GetVerticalScroll() return self.offset or 0 end
function Frame:GetEffectiveScale() return 1 end
function Frame:SetMouseMotionEnabled() end
local function create(kind, name, parent)
    local frame = setmetatable({ kind = kind, children = {}, scripts = {}, points = {}, shown = true }, Frame)
    frame:SetParent(parent)
    if name then frames[name] = frame; _G[name] = frame end
    return frame
end
_G.CreateFrame, _G.UIParent = create, create("Frame")
_G.C_Timer = { After = function(_, callback) pending[#pending + 1] = callback end }
local hooks = 0
_G.hooksecurefunc = function(object, method, callback)
    hooks = hooks + 1
    local original = object[method]
    object[method] = function(...)
        local results = { original(...) }; callback(...); return unpack(results)
    end
end
local cursorY = 100
_G.GetCursorPosition = function() return 0, cursorY end
local selected = true
_G.EllesmereUI = {
    _ModuleNS = { EllesmereUIQuestTracker = { UseCustomTracker = function() return selected end } },
    ReapplyOwnAnchor = function(key) expect(key == "EQT_Tracker", "Moved an unrelated frame") end,
}
local root = create("Frame", "EUI_CustomQuestTracker", UIParent)
root:SetSize(260, 160)
create("Frame", nil, root) -- unanchored non-tracker child
local scroll = create("ScrollFrame", nil, root)
local quest = create("Frame", nil, scroll)
quest:SetSize(238, 80)
quest:SetPoint("TOPLEFT", scroll)
scroll:SetScrollChild(quest)
local bar = create("Frame", nil, root)
bar:SetWidth(3.0000224113464); bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT")
bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT")
local thumb = create("Frame", nil, bar)
thumb:SetHeight(20)
thumb:SetScript("OnMouseDown", function() end)
thumb:SetScript("OnMouseUp", function() end)
local interactionRefreshes, renders = 0, 0
local function nativeWheel(_, delta)
    -- These are intentionally quest-only calculations. The host must preserve
    -- the interaction work but replace their geometry, including empty quests.
    local range = math.max(0, quest:GetHeight() - scroll:GetHeight())
    scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScroll() - delta * 40, range)))
    bar:SetShown(range > 0)
    if range > 0 then
        thumb:SetHeight(40); thumb:ClearAllPoints(); thumb:SetPoint("TOP", bar, "TOP", 0, 0)
    else
        scroll:SetVerticalScroll(0)
    end
    interactionRefreshes = interactionRefreshes + 1
end
scroll:SetScript("OnMouseWheel", nativeWheel)
local originalRootHeight, originalScroll = root.SetHeight, scroll.SetVerticalScroll
local originalBarShown, originalThumbPoint = bar.SetShown, thumb.SetPoint
local nativeRefresh
_G.EllesmereUIQuestTracker = {
    Cfg = function(key) return config[key] end,
    RefreshCustom = function() C_Timer.After(0, function() nativeRefresh(80) end) end,
}
_G.AzerothWaypointNS = { Internal = {} }
assert(loadfile("integrations/guides/viewer_custom_host.lua"))()
assert(loadfile("integrations/guides/viewer_ellesmere.lua"))()
local host = AzerothWaypointNS.Internal.GuideTrackerViewer.EllesmereHost
local target = host.GetContainer()
expect(host.IsSelected(), "Custom host not detected")
selected = false; expect(not host.IsSelected(), "Selected custom host in skin-only mode"); selected = true
local function module(height, order)
    local result = create("Frame", nil, UIParent)
    result.uiOrder, result.fullHeight, result.updates = order, height, 0
    function result:SetContainer(value) self.parentContainer = value; self:SetParent(value) end
    function result:Update()
        self.updates = self.updates + 1
        self.isDirty = false; self:SetHeight(self.fullHeight)
        self:SetShown(self.fullHeight > 0)
        return self.fullHeight
    end
    return result
end
nativeRefresh = function(height)
    renders = renders + 1
    quest:SetWidth(238); quest:SetHeight(math.max(height, 1))
    root:SetHeight(math.min(24 + height + (height > 0 and 8 or 0), 160))
    nativeWheel(scroll, 0)
end
local a, b = module(70, 2), module(50, 2.1)
_G.EUI_CustomQuestTracker = nil
expect(not host:SetModuleContainer(a, target) and scroll:GetScrollChild() == quest,
    "Attachment before Ellesmere initialization modified content")
_G.EUI_CustomQuestTracker = root
expect(host:SetModuleContainer(a, target), "First module did not attach")
expect(host:SetModuleContainer(b, target), "Second module did not attach")
flush()
expect(scroll:GetScrollChild() ~= quest and quest:GetParent() == scroll:GetScrollChild(), "Quest content was not composed")
expect(target:GetParent() == scroll:GetScrollChild(), "Guides are outside the shared scrolling area")
expect(scroll:GetScrollChild():GetHeight() == 212 and root:GetHeight() == 160, "Combined height/max-height incorrect")
expect(a:GetPoint(1) == "TOPLEFT" and b.points[1][5] == -76, "Provider order/placement incorrect")
expect(quest.points[1][5] == -132, "Quest rows were not offset below the guides")
expect(bar:IsShown(), "Combined content did not get a scrollbar")
local oldRenders, oldUpdates = renders, a.updates + b.updates
scroll:GetScript("OnMouseWheel")(scroll, -2)
expect(scroll:GetVerticalScroll() == 80, "Wheel clamped to Ellesmere's smaller quest-only range")
expect(renders == oldRenders and a.updates + b.updates == oldUpdates, "Scrolling rebuilt guide/quest content")
expect(interactionRefreshes >= 2, "Native item-button/click-overlay refresh was bypassed")
local combinedContent, heightWrites = scroll:GetScrollChild(), 0
local originalCombinedHeight = combinedContent.SetHeight
function combinedContent:SetHeight(height)
    heightWrites = heightWrites + 1
    originalCombinedHeight(self, height)
end
local beforeInteractions = interactionRefreshes
for index = 1, 100 do nativeRefresh(80) end
expect(heightWrites == 0 and #pending == 0, "Same-height quest renders touched combined geometry")
expect(interactionRefreshes == beforeInteractions + 100, "Quest renders skipped native interaction updates")
expect(a.updates + b.updates == oldUpdates, "Unchanged native refresh rebuilt guide rows")
expect(scroll:GetVerticalScroll() == 80, "Native refresh reset combined scroll position")
nativeRefresh(0)
expect(heightWrites == 1 and #pending == 0, "A quest-only height change queued a guide layout")
expect(scroll:GetScrollChild():GetHeight() == 132 and scroll:GetVerticalScroll() == 4, "Empty quest list broke guide content or clamping")
quest:SetWidth(230)
expect(#pending == 1, "A real native width change did not request layout")
flush()
expect(a:GetWidth() == 230 and b:GetWidth() == 230, "The guides did not receive the new native width")
quest:SetWidth(238); flush()
a.fullHeight, a.isDirty = 300, true
target:MarkDirty(); flush()
expect(scroll:GetScrollChild():GetHeight() == 362 and root:GetHeight() == 160, "Guide-only overflow incorrect")
scroll:GetScript("OnMouseWheel")(scroll, -2)
expect(scroll:GetVerticalScroll() == 84, "Guide-only scrolling clamped to zero")
thumb:GetScript("OnMouseDown")(thumb)
cursorY = 50; thumb:GetScript("OnUpdate")(thumb)
expect(scroll:GetVerticalScroll() > 80, "Thumb drag did not use combined scroll range")
thumb:GetScript("OnMouseUp")(thumb)
config.customScrollbar = "hidden"; root:GetScript("OnEnter")(root)
expect(not bar:IsShown(), "Ignored Ellesmere hidden-scrollbar setting")
config.customScrollbar = "hover"; root.hovered = true; root:GetScript("OnEnter")(root)
expect(bar:IsShown(), "Hover scrollbar did not appear")
root.hovered = false; root:GetScript("OnLeave")(root)
expect(not bar:IsShown(), "Hover scrollbar did not disappear")
root:Hide(); expect(not target:IsVisible(), "Guide region ignored tracker visibility")
root:Show()
EllesmereUI._unlockActive = true; root:SetHeight(450)
expect(root:GetHeight() == 160, "Unlock preview ignored configured height")
EllesmereUI._unlockActive = false
host.RemoveModule(a); flush()
expect(host:GetContainerForModule(a) == nil and host:GetContainerForModule(b) == target, "Removing one provider detached the other")
expect(root:GetHeight() == 88, "Combined region did not shrink after provider removal")
local hooked = hooks
host.RemoveModule(b); flush()
expect(scroll:GetScrollChild() == quest and quest:GetParent() == scroll, "Did not restore original quest content")
expect(root.SetHeight == originalRootHeight and scroll.SetVerticalScroll == originalScroll, "Did not restore native geometry methods")
expect(bar.SetShown == originalBarShown and thumb.SetPoint == originalThumbPoint, "Did not restore native scrollbar methods")
expect(scroll:GetScript("OnMouseWheel") == nativeWheel, "Did not restore original wheel callback")
expect(not target:IsShown() and host:GetContainerForModule(b) == nil, "Last detach retained visible guide content")
expect(host:SetModuleContainer(a, target), "Reattachment failed"); flush()
expect(hooks == hooked and target:GetParent():IsShown(), "Reattachment duplicated hooks or left content hidden")
-- Detach with a pending callback and immediately reattach: old work is stale.
a.isDirty = true; target:MarkDirty(); host.RemoveModule(a)
host:SetModuleContainer(b, target); flush()
expect(host:GetContainerForModule(a) == nil and host:GetContainerForModule(b) == target, "Stale callback resurrected a detached provider")
host.RemoveModule(b); flush()

-- Later third-party hooks keep their place in the chain. Our retained
-- wrappers must become transparent once this host detaches.
host:SetModuleContainer(a, target); flush()
local savedScroll, savedThumbHeight, savedBarHide = scroll.SetVerticalScroll, thumb.SetHeight, bar.Hide
local laterScroll = function(self, value) return savedScroll(self, value) end
local laterHeight = function(self, value) return savedThumbHeight(self, value) end
local laterHide = function(self) return savedBarHide(self) end
scroll.SetVerticalScroll, thumb.SetHeight, bar.Hide = laterScroll, laterHeight, laterHide
host.RemoveModule(a); flush()
expect(scroll.SetVerticalScroll == laterScroll and thumb.SetHeight == laterHeight and bar.Hide == laterHide,
    "Detach removed another addon's later hook")
scroll:SetVerticalScroll(7); thumb:SetHeight(13); bar:Hide()
expect(scroll:GetVerticalScroll() == 7 and thumb:GetHeight() == 13 and not bar:IsShown(),
    "A retained inactive wrapper still controlled the native tracker")

-- Pools must belong to the guide module/block, never Blizzard's manager.
_G.ObjectiveTrackerManager = {
    AcquireFrame = function() error("Acquired from Blizzard's shared pool") end,
    ReleaseFrame = function() error("Released into Blizzard's shared pool") end,
}
_G.CreateFramePoolCollection = function()
    local pools = {}
    return {
        GetOrCreatePool = function(_, kind, parent, template)
            local pool = pools[template]
            if not pool then
                local free, active = {}, {}
                pool = { Acquire = function()
                    local result = table.remove(free)
                    local isNew = result == nil
                    result = result or create(kind, nil, parent)
                    active[result] = true
                    return result, isNew
                end }
                pool.Release = function(_, result)
                    expect(active[result], "Released an object to the wrong private pool")
                    active[result] = nil; free[#free + 1] = result; result:Hide(); result:ClearAllPoints()
                end
                pools[template] = pool
            end
            return pool
        end,
        Release = function(_, result) pools[result.template]:Release(result) end,
    }
end
host.PrepareModule(a)
a.blockTemplate, a.lineTemplate = "ObjectiveTrackerAnimBlockTemplate", "QuestObjectiveLineTemplate"
a.ContentsFrame = create("Frame", nil, a)
local block = a:AcquireFrame(a.blockTemplate)
block.parentModule, block.usedLines, block.id = a, {}, "step"
function block:GetExistingLine(key) return self.usedLines[key] end
local line = block:GetLine(1)
expect(line.parentBlock == block and line.used and line:GetParent() == block, "Private line initialization differs from native contract")
block:FreeLine(line)
expect(block:GetLine(2) == line and line.objectiveKey == 2, "Private line pool did not reuse its row")
function block:Free() for _, value in pairs(self.usedLines) do self:FreeLine(value) end end
a.usedBlocks = { [a.blockTemplate] = { step = block } }
a.RemoveBlockFromCache = function(_, value, fromFree)
    expect(value == block and fromFree, "Block cache removal contract changed")
end
a.OnFreeBlock = function() end
a:FreeBlock(block)
expect(a.usedBlocks[a.blockTemplate].step == nil and not block:IsShown(), "Private block was not freed")
expect(a:AcquireFrame(a.blockTemplate) == block, "Private module pool did not reuse its block")

-- Normal host selection: custom Ellesmere > Blizzard, KT still preferred.
assert(loadfile("integrations/guides/viewer_host.lua"))()
local sharedHost = AzerothWaypointNS.Internal.GuideTrackerViewer.Host
expect(sharedHost.GetHostID() == "ellesmere" and not sharedHost.IsBlizzardHost(), "Custom host selection failed")
expect(sharedHost.GetManager() == host and sharedHost.GetTrackerFrame() == target, "Selected the wrong manager/container")
local _, _, warning = sharedHost.GetDockingSupportStatus()
expect(not warning, "Custom Ellesmere host inherited Blizzard's native warning")
selected = false
expect(sharedHost.GetHostID() == "blizzard" and sharedHost.IsBlizzardHost(), "Skin-only mode did not retain native docking")
selected = true
_G.KT_ObjectiveTrackerFrame = create("Frame")
expect(sharedHost.GetHostID() == "kaliel" and not sharedHost.IsEllesmereHost(), "Ellesmere stole KT host priority")
_G.KT_ObjectiveTrackerFrame = nil

local originalChildren = replaceMethod(root, "GetChildren", function() error("test frame discovery failure") end)
expect(not sharedHost.TryRegisterOnce(host, b, target)
    and select(3, host.GetStatus()):find("test frame discovery failure"),
    "Registration swallowed its attachment error without retaining diagnostics")
root.GetChildren = originalChildren

-- An unsupported/protected hierarchy must remain completely untouched.
root.protected = true
expect(not host:SetModuleContainer(b, target) and scroll:GetScrollChild() == quest, "Modified a protected tracker")
root.protected = false
bar:ClearAllPoints(); bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT")
expect(not host:SetModuleContainer(b, target) and select(3, host.GetStatus()):find("scrollbar"),
    "Unsupported hierarchy did not expose its attachment failure")
bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT")

-- Run the installed renderer's actual body to catch ordering assumptions.
local addonPath = arg[1] or NativePath("retail", "EllesmereUIQuestTracker")
local file = io.open(addonPath .. "/EllesmereUIQuestTracker_Custom.lua", "r")
if file then
    local source = file:read("*a"); file:close()
    local body = assert(source:match("local function Render%(%)%s*(.-)\nend%s*\n%s*function Queue%(%)"), "Installed Render body changed")
    local function noop() end
    local text = { SetText = noop }
    local sourceHeight, itemViewportHeight, itemScrollOffset = 80, nil, nil
    local environment = setmetatable({
        frame = root, child = quest, Cfg = EllesmereUIQuestTracker.Cfg,
        HideOverlay = noop, HoverWanted = function() return false end,
        wipe = function(value) for key in pairs(value) do value[key] = nil end end,
        prevObj = {}, timerEnd = {}, GetTime = function() return 0 end,
        C_QuestLog = { GetQuestTimers = function() return {} end,
            GetNumQuestLogEntries = function() return 0, 0 end,
            GetMaxNumQuestsCanAccept = function() return 35 end },
        C_TradeSkillUI = { GetRecipesTracked = function() return {} end },
        BuildList = noop, CharDB = function() return { ctCollapsed = {}, ctDoneOpen = {} } end,
        PAD = 8, BAR_GAP = 6, OBJ_IND = 10, HEADER_H = 24, DEF_HEIGHT = 450, DEF_WIDTH = 260,
        UNLOCK_KEY = "EQT_Tracker",
        order = {}, lines = {}, items = {}, ZoneRGB = function() return 1, 1, 1 end,
        AddRecipes = function(y) return y + sourceHeight end,
        header = { count = text, toggle = text },
        UpdateThumb = function() nativeWheel(scroll, 0) end,
        UpdateVisibility = noop, SyncFilterToggle = noop, ArmTick = noop, cdRegistered = false,
        SyncItems = function()
            itemViewportHeight = scroll:GetScrollChild():GetHeight()
            itemScrollOffset = scroll:GetVerticalScroll()
        end,
    }, { __index = _G })
    local chunk = assert(loadstring("return function()\n" .. body .. "\nend", "installed Ellesmere Render"))
    setfenv(chunk, environment)
    local render = chunk()
    host:SetModuleContainer(a, target); flush()
    render(); flush()
    expect(scroll:GetScrollChild():GetHeight() == 386, "Actual renderer lost combined content height")
    scroll:GetScript("OnMouseWheel")(scroll, -3)
    local offset = scroll:GetVerticalScroll()
    render(); flush()
    expect(scroll:GetVerticalScroll() == offset, "Actual renderer reset shared scrolling")
    sourceHeight = 0; render(); flush()
    expect(scroll:GetScrollChild():GetHeight() == 306, "Actual empty renderer discarded guide content")
    expect(itemViewportHeight == 306 and itemScrollOffset == scroll:GetVerticalScroll(),
        "Native item positioning saw stale shared geometry")
    host.RemoveModule(a); flush()
end
print("Ellesmere combined layout, scroll interactions, provider lifecycle and restoration fixtures passed")
