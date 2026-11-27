local function Run(flavor)
    local fixture = assert(loadfile("tests/daylight_fixture.lua"))()
    fixture.flavor = flavor
    local ns = AzerothWaypointNS
    local common = ns.Internal.GuideTrackerViewer
    local frameMethods = getmetatable(UIParent)
    frameMethods.GetPoint = function(self) if self.point then return self.point[1], self.point[2], self.point[3], self.point[4] or 0, self.point[5] or 0 end end
    _G.GwQuestTracker, _G.KT_ObjectiveTrackerFrame = nil, nil
    _G.hooksecurefunc = function(object, key, hook)
        local original = object[key]
        object[key] = function(...) original(...); hook(...) end
    end

    local root = fixture.Frame(UIParent)
    root:SetWidth(268)
    local child = fixture.Frame(root)
    root.ScrollFrame = fixture.Frame(root)
    root.ScrollFrame.Child = child
    root.ScrollFrame.gwScroll, root.ScrollFrame.gwStickyInset, root.ScrollFrame.maxScroll = 0, 0, 0
    local first, second = fixture.Frame(child), fixture.Frame(child)
    first:SetHeight(75); second:SetHeight(65)
    local native = { first, second }
    local total, layoutCalls, adjustCalls = 0, 0, 0
    function root:LayoutChanged()
        assert(not fixture.combat)
        layoutCalls = layoutCalls + 1
        total = 0
        for _, section in ipairs(native) do total = total + section:GetHeight() end
    end
    function root:AdjustItemButtonPositions() assert(not fixture.combat); adjustCalls = adjustCalls + 1 end
    local gw = { QuestTrackerScrollableContainer = native, settings = { objectives = { enabled = true } },
        LoadObjectivesTracker = function() end, ScrollObjectivesTrackerToContainer = function() end,
        GetObjectivesScrollViewport = function() return 0, root:GetHeight() end }
    function gw.ApplyObjectivesTrackerModuleOrder()
        table.sort(native, function(a, b)
            local function Rank(section) return section == second and 1 or section == first and 2 or 3 end
            return Rank(a) < Rank(b)
        end)
        for index, section in ipairs(native) do
            section:ClearAllPoints()
            section:SetPoint("TOPRIGHT", native[index - 1] or child, index == 1 and "TOPRIGHT" or "BOTTOMRIGHT")
        end
        root:LayoutChanged()
    end
    _G.GW2_ADDON = gw
    assert(loadfile("core/scheduling.lua"))()
    assert(loadfile("integrations/guides/viewer_custom_host.lua"))()
    assert(loadfile("integrations/guides/viewer_gw2ui.lua"))()
    assert(loadfile("integrations/guides/viewer_host.lua"))()
    local host, manager = common.Host, common.GW2UIHost
    assert(host.GetHostID() == "gw2ui")
    local ready, _, waiting = host.GetAttachmentAvailability()
    assert(not ready and waiting)
    root.ScrollFrame.GetScrollChild = function(self) return self.Child end
    _G.GwQuestTracker = root
    fixture.Fire("PLAYER_LOGIN"); fixture.Flush()
    assert(host.GetAttachmentAvailability() and not host.IsBlizzardHost())
    assert(host.GetManager() == manager and select(3, host.GetDockingSupportStatus()) == false)
    assert(ns.GetObjectiveTrackerVisibilityStatus().frame == root)
    _G.KT_ObjectiveTrackerFrame = fixture.Frame()
    assert(host.GetHostID() == "kaliel")
    _G.KT_ObjectiveTrackerFrame = nil

    local function Module(order, height)
        local module = fixture.Frame()
        module.uiOrder = order
        module.Update = function(self)
            assert(not fixture.combat)
            self.isDirty = false
            return self.collapsed and 24 or height
        end
        module.ToggleCollapsed = function(self)
            self.collapsed = not self.collapsed
            self.isDirty = true
            self.parentContainer:MarkDirty()
        end
        return module
    end
    local container = host.GetTrackerFrame()
    local guide, secondGuide = Module(2, 100), Module(2.1, 60)
    assert(host.TryRegisterOnce(manager, secondGuide, container))
    assert(host.TryRegisterOnce(manager, guide, container))
    for _ = 1, 100 do container:MarkDirty() end
    fixture.Flush()
    assert(native[1] == container and native[2] == first and native[3] == second)
    assert(container:GetWidth() == 268 and total == 312)
    assert(container.modules[1] == guide and container.modules[2] == secondGuide)
    assert(manager.counters.layouts == 1 and adjustCalls == 1)
    container:SetCollapsed(true, "autoCollapse")
    assert(not guide.collapsed and not secondGuide.collapsed)

    gw.ApplyObjectivesTrackerModuleOrder()
    fixture.Flush()
    assert(native[1] == container and native[2] == second and native[3] == first)
    assert(select(2, second:GetPoint()) == container)
    assert(manager.counters.layouts == 1, "Native reorder unnecessarily rebuilt guide rows")

    fixture.combat = true
    guide:ToggleCollapsed()
    root:SetWidth(310)
    root:GetScript("OnSizeChanged")(root, 310)
    fixture.Flush()
    assert(not guide.collapsed and container:GetWidth() == 268 and total == 312)
    fixture.combat = false
    fixture.Fire("PLAYER_REGEN_ENABLED"); fixture.Flush()
    assert(guide.collapsed and not secondGuide.collapsed and container:GetWidth() == 310 and total == 236)
    assert(manager.counters.layouts == 2)
    local before = layoutCalls
    fixture.Fire("PLAYER_REGEN_ENABLED"); fixture.Flush()
    assert(layoutCalls == before, "Idle combat boundaries relaid out the host")

    container:RemoveModule(guide)
    fixture.Flush()
    assert(native[1] == container and total == 206 and not guide:IsShown())
    container:RemoveModule(secondGuide)
    fixture.Flush()
    assert(native[1] == second and native[2] == first and #native == 2 and total == 140)
    assert(select(2, second:GetPoint()) == child and not container:IsShown())
    assert(container:GetParent() == UIParent and manager:GetContainerForModule(secondGuide) == nil)
    assert(manager.GetStatus() == "ready")
    _G.GwQuestTracker = nil
    assert(host.GetHostID() == "blizzard", "A disabled GW2_UI tracker blocked Blizzard")
    _G.GwQuestTracker = fixture.Frame(UIParent)
    assert(host.GetHostID() == "gw2ui" and not host.GetAttachmentAvailability(), "An incompatible active GW2_UI tracker fell through to Blizzard")
end

Run("retail")
Run("forever")
print("GW2_UI tracker host: startup, host precedence, shared scroll height, order, combat, collapse and teardown passed")
