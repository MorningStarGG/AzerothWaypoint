local path = dofile("tests/native_path.lua")

local function Run(flavor)
    local f = assert(loadfile("tests/controller_fixture.lua"))()
    f.flavor = flavor
    local common, pad = f.NS.Internal.GuideTrackerViewer, f.Pad
    assert(loadfile("core/scheduling.lua"))()
    assert(loadfile("integrations/guides/viewer_custom_host.lua"))()
    local custom = common.CustomHost
    local frame = getmetatable(UIParent)
    function frame:GetPoint() if self.point then return unpack(self.point) end end
    function frame:GetDebugName() return self.name or "native-section" end
    PixelUtil = {GetNearestPixelSize = function(value) return math.floor(value + 0.5) end}
    local queued = {}
    GW2_ADDON = {settings = {objectives = {enabled = true}}, QuestTrackerScrollableContainer = {},
        QuestTrackerFixedContainer = {}, ObjectiveTrackerContainer = {},
        CombatQueue = {Queue = function(_, key, callback, args) queued[key] = {callback, args} end},
        LoadObjectivesTracker = function() end, ApplyObjectivesTrackerModuleOrder = function() end,
        GetObjectivesFirstObjectiveOffset = function() return 0 end}
    local gw = GW2_ADDON

    -- Execute the installed owner's private scroll path, sticky headers,
    -- indicator, mouse wheel, geometry and secure-item combat queue on BOTH
    -- clients. The fixture supplies frame geometry, not a replacement owner.
    local input = assert(io.open(path(flavor, "GW2_UI/Games/Shared/Objectives/ObjectivesTracker.lua")))
    local source = input:read("*a"); input:close()
    local first = assert(source:find("local function ToPixels(", 1, true))
    local last = assert(source:find("local function DisableBlizzardsObjevtiveTracker(", first, true))
    local wheel = assert(source:find("function GwObjectivesTrackerMixin:CreateTrackerScrollFrame(", last, true))
    local wheelEnd = assert(source:find("function GwObjectivesTrackerMixin:CreateTrackerContainer(", wheel, true))
    local chunk = assert(loadstring(source:sub(first, last - 1) .. source:sub(wheel, wheelEnd - 1)))
    local env = setmetatable({GW = gw}, {__index = _G})
    setfenv(chunk, env); chunk()
    local root = CreateFrame("Frame", "GwQuestTracker", UIParent)
    root:SetSize(268, 400); root.y = 800
    for name, method in pairs(env.GwObjectivesTrackerMixin) do root[name] = method end
    local view = root:CreateTrackerScrollFrame("GwQuestTrackerScroll", 360)
    root.ScrollFrame = view
    view.range = 9000 -- engine range may include content outside the clipped owner viewport
    local child = CreateFrame("Frame", nil, view); view.Child = child; view:SetScrollChild(child)
    local fixed = CreateFrame("Frame", nil, root); fixed:SetHeight(40)
    gw.QuestTrackerFixedContainer[1] = fixed
    function child:GetTop() return root:GetTop() - fixed:GetHeight() - view.gwStickyInset + view:GetVerticalScroll() end
    -- Deliberately expose a larger frame rect than the owner's visible area.
    -- Focus reveal must ask GW's viewport helper rather than this rectangle.
    function view:GetTop() return root:GetTop() end
    function view:GetBottom() return -5000 end
    local function Section(height, headerHeight)
        local section = CreateFrame("Frame", nil, child); section:SetHeight(height)
        section.blocks, section.numQuests = {}, 0
        section.header = CreateFrame("Frame", nil, section); section.header:SetHeight(headerHeight)
        function section:GetTop()
            local top = child:GetTop()
            for _, other in ipairs(gw.QuestTrackerScrollableContainer) do
                if other == self then return top end
                top = top - other:GetHeight()
            end
        end
        table.insert(gw.QuestTrackerScrollableContainer, section)
        return section
    end
    local firstSection, secondSection = Section(500, 30), Section(400, 20)
    for _, key in ipairs({"Dungeon", "Zone", "Campaign", "Bonus"}) do gw.ObjectiveTrackerContainer[key] = {blocks = {}} end
    gw.ObjectiveTrackerContainer.Quests = firstSection
    input = assert(io.open(path(flavor, "GW2_UI/Games/Shared/Mixin/GwObjectivesBlockMixin.lua")))
    source = input:read("*a"); input:close()
    first = assert(source:find("function GwObjectivesBlockTemplateMixin:UpdateObjectiveActionButtonPosition()", 1, true))
    GwObjectivesBlockTemplateMixin = {}
    chunk = assert(loadstring(source:sub(first)))
    setfenv(chunk, setmetatable({GW = gw}, {__index = _G})); chunk()
    local block = CreateFrame("Frame", nil, firstSection)
    block.hasItem, block.fromContainerTopHeight = true, 200
    block.actionButton = CreateFrame("Button", nil, root, "SecureActionButtonTemplate")
    block.actionButton:SetHeight(28)
    local itemWrites = 0
    local setItemPoint = block.actionButton.SetPoint
    function block.actionButton:SetPoint(...)
        assert(not f.combat, "secure item moved during combat")
        itemWrites = itemWrites + 1; setItemPoint(self, ...)
    end
    block.UpdateObjectiveActionButtonPosition = GwObjectivesBlockTemplateMixin.UpdateObjectiveActionButtonPosition
    firstSection.blocks[1], firstSection.numQuests = block, 1

    assert(loadfile("integrations/guides/viewer_gw2ui.lua"))()
    local host = common.GW2UIHost
    local container = host.GetContainer()
    local module = CreateFrame("Frame", nil, container)
    local guideUpdates = 0
    module.Update = function(self) guideUpdates = guideUpdates + 1; self.isDirty = false; return 80 end
    assert(host:SetModuleContainer(module, container)); f.Flush()
    local layouts, originalRange = host.counters.layouts, view.GetVerticalScrollRange
    assert(view.maxScroll == container:GetHeight() + 900 - 360)
    custom.SetScrollOffset(view, 150)
    assert(view.gwScroll == 150 and view.gwStickyInset == 30 and view:GetVerticalScroll() == 180)
    assert(firstSection.header.gwStuck and firstSection.header:GetParent() == root)
    local _, _, _, _, itemY = block.actionButton:GetPoint()
    assert(itemY == -(container:GetHeight() + 200 + 40 - 150), "native item ignored the logical scroll")
    root:LayoutChanged()
    assert(view.gwScroll == 150 and view:GetVerticalScroll() == 180, "layout reset the controller's scroll")
    local top, bottom = custom.GetScrollViewport(view)
    assert(top == 930 and bottom == 600, "fixed or stuck header leaked into the visible area")
    assert(view.gwScrollTrack:IsShown() and view.gwScrollTrack.thumb.point, "native indicator was not updated")

    -- Native right-stick frame writes use physical offsets. Convert the old
    -- inset once; the native owner can select a different sticky header.
    view:SetVerticalScroll(220)
    assert(view.gwScroll == 190 and view:GetVerticalScroll() == 220)
    view:SetVerticalScroll(640)
    assert(view.gwScroll == 610 and view.gwStickyInset == 20 and view:GetVerticalScroll() == 630)
    assert(not firstSection.header.gwStuck and firstSection.header:GetParent() == firstSection)
    assert(secondSection.header.gwStuck)
    local beforeItems = itemWrites
    gw.ScrollObjectivesTrackerToContainer(firstSection)
    assert(view.gwScroll == container:GetHeight() and itemWrites == beforeItems + 1, "native writes re-entered the owner")
    view:GetScript("OnMouseWheel")(view, -1)
    assert(view.gwScroll > container:GetHeight(), "mouse wheel stopped using the native owner")
    view:SetVerticalScroll(99999)
    assert(view.gwScroll == view.maxScroll and view:GetVerticalScroll() == custom.GetScrollRange(view))
    view:SetVerticalScroll(-500)
    assert(view.gwScroll == 0 and view.gwStickyInset == 0 and view:GetVerticalScroll() == 0)

    local row = CreateFrame("Frame", nil, module); row:SetHeight(20)
    function row:GetTop() return 500 + view.gwScroll end
    function row:GetBottom() return self:GetTop() - self:GetHeight() end
    pad.RegisterWindow(module, {manual = true, tracker = true})
    pad.Reveal(row, module)
    assert(view.gwScroll == 120 and view:GetVerticalScroll() == 150, "focus reveal used the unbounded frame rectangle")
    local updatesBeforeIdle = guideUpdates
    for _ = 1, 20 do custom.SetScrollOffset(view, view:GetVerticalScroll()) end
    f.Flush()
    assert(guideUpdates == updatesBeforeIdle and host.counters.layouts == layouts, "scrolling rebuilt guide layouts")

    f.combat = true; beforeItems = itemWrites
    view:SetVerticalScroll(280)
    assert(view.gwScroll == 250 and itemWrites == beforeItems and next(queued), "native combat queue was bypassed")
    f.combat = false
    for key, call in pairs(queued) do queued[key] = nil; call[1](unpack(call[2])) end
    assert(itemWrites == beforeItems + 1)
    firstSection:SetHeight(10); secondSection:SetHeight(10)
    root:LayoutChanged()
    assert(view.maxScroll == 0 and view.gwScroll == 0 and view:GetVerticalScroll() == 0)
    view:SetVerticalScroll(500)
    assert(view:GetVerticalScroll() == 0, "a fitting list scrolled into empty space")
    host.GetContainer():RemoveModule(module); f.Flush()
    local setter = view.SetVerticalScroll
    assert(view.GetVerticalScrollRange == originalRange and view:GetVerticalScrollRange() == 9000)
    assert(custom.GetScrollViewport(view) == view:GetTop(), "detached viewport retained GW ownership")
    view:SetVerticalScroll(7); assert(view:GetVerticalScroll() == 7 and view.gwScroll == 0)
    assert(host:SetModuleContainer(module, container)); f.Flush()
    local count = 0
    for _, hook in ipairs(f.nativeHooks) do if hook.target == view and hook.method == "SetVerticalScroll" then count = count + 1 end end
    assert(count == 1 and view.SetVerticalScroll == setter, "reattachment added another scroll hook")
    container:RemoveModule(module); f.Flush()
    view.IsProtected = function() return true end
    local ready, reason = host.GetAvailability()
    assert(not ready and reason:find("incompatible", 1, true), "protected viewport accepted")
end

Run("forever")
Run("retail")
print("Installed GW2 owners: controller scroll, sticky headers, viewport, items, combat, mouse wheel, idle and detach passed")
