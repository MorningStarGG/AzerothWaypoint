-- ============================================================
-- Custom tracker layout
-- ============================================================
--
-- Shares scroll bounds, pooled lines and module layout across custom tracker
-- hosts. Each native tracker adapter supplies its own scroll surface and
-- native layout. The shared layout handles guide modules within that viewport.

local NS = _G.AzerothWaypointNS
NS.Internal = NS.Internal or {}
NS.Internal.GuideTrackerViewer = NS.Internal.GuideTrackerViewer or {}
local Common = NS.Internal.GuideTrackerViewer
local Custom = {}
Common.CustomHost = Custom

local scrollOwners = setmetatable({}, { __mode = "k" })
local hookedScroll = setmetatable({}, { __mode = "k" })

function Custom.GetScrollViewport(view)
    local owner = scrollOwners[view]
    if owner and owner.GetViewport then return owner.GetViewport() end
    return view:GetTop(), view:GetBottom()
end

function Custom.GetScrollRange(view)
    local owner = scrollOwners[view]
    return owner and owner.GetRange() or view:GetVerticalScrollRange()
end

function Custom.SetScrollOffset(view, position)
    local owner = scrollOwners[view]
    position = math.max(0, math.min(Custom.GetScrollRange(view), position))
    if owner then
        if position ~= owner.GetOffset() or view:GetVerticalScroll() ~= position then owner.SetOffset(position) end
    elseif position ~= view:GetVerticalScroll() then
        view:SetVerticalScroll(position)
    end
end

-- Native smart navigation calls viewport methods on a secure execution path.
-- Keep those methods/native return values intact: a secure post-hook delegates
-- foreign writes to the logical owner before the scroll call returns. Owner
-- writes set their offset first, so animations do not re-enter the delegate.
function Custom.RegisterScrollOwner(view, owner)
    assert(not view:IsProtected(), "Cannot own a protected tracker viewport")
    assert(not scrollOwners[view], "Tracker viewport already has a scroll owner")
    if not hookedScroll[view] then
        hookedScroll[view] = true
        hooksecurefunc(view, "SetVerticalScroll", function(self, position)
            local current = scrollOwners[self]
            if not current or type(position) ~= "number" or position == current.GetOffset() then return end
            current.SetOffset(math.max(0, math.min(current.GetRange(), position)))
            -- Combat can make the owner refuse a move while secure item
            -- buttons are held. Restore its accepted offset without moving them.
            if scrollOwners[self] == current and self:GetVerticalScroll() ~= current.GetOffset() then
                self:SetVerticalScroll(current.GetOffset())
            end
        end)
    end
    scrollOwners[view] = owner
    return function() if scrollOwners[view] == owner then scrollOwners[view] = nil end end
end

-- ============================================================
-- Block and line pools
-- ============================================================

-- Custom hosts share AWP's pools and module layout, never a native tracker pool.
local function Acquire(parent, template)
    parent._awpViewerPools = parent._awpViewerPools or CreateFramePoolCollection()
    local pool = parent._awpViewerPools:GetOrCreatePool("Frame", parent, template)
    local frame, isNew = pool:Acquire()
    frame.template = template
    return frame, isNew
end

local function GetLine(block, key, template)
    template = template or block.parentModule.lineTemplate
    local line = block:GetExistingLine(key)
    if line and line.template ~= template then
        block:FreeLine(line); line = nil
    end
    if not line then
        line = Acquire(block, template); line:Show()
    end
    block.usedLines[key] = line
    line.objectiveKey, line.parentBlock, line.used = key, block, true
    return line
end

local function FreeLine(block, line)
    block.usedLines[line.objectiveKey] = nil
    block._awpViewerPools:Release(line)
    line:Hide()
    if line.OnFree then line:OnFree(block) end
end

local function AcquireFrame(module, template)
    local frame, isNew = Acquire(module, template)
    frame:SetParent(module.ContentsFrame)
    if template == module.blockTemplate then frame.GetLine, frame.FreeLine = GetLine, FreeLine end
    return frame, isNew
end

local function FreeBlock(module, block)
    module:RemoveBlockFromCache(block, true)
    block:Free()
    module.usedBlocks[block.template][block.id] = nil
    module._awpViewerPools:Release(block)
    module:OnFreeBlock(block)
end

function Custom.PrepareModule(module)
    if not module._awpCustomHostMethods then
        module._awpCustomHostMethods = { acquire = module.AcquireFrame, free = module.FreeBlock }
    end
    module.AcquireFrame, module.FreeBlock = AcquireFrame, FreeBlock
end

local function Order(a, b) return (a.uiOrder or 0) < (b.uiOrder or 0) end
local MODULE_GAP = 6

function Custom.Layout(container, width)
    local changed = container._awpLayoutWidth ~= width
    container._awpLayoutWidth = width
    container:SetWidth(width)
    table.sort(container.modules, Order)
    local actions = Common.GuideActions
    local y, gap = 0, 0
    for index = 1, #container.modules do
        local module = container.modules[index]
        module:SetWidth(width)
        if changed or module.isDirty or module._awpCustomHostHeight == nil then
            local height = module:Update(1000000, false)
            module._awpCustomHostHeight = math.max(0, tonumber(height) or module:GetHeight())
        end
        local height = module._awpCustomHostHeight
        if height > 0 and module:IsShown() then
            y = y + gap
            module:ClearAllPoints()
            module:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -y)
            y = y + height
            local trailingPadding = actions and actions.GetTrailingPadding(module) or 0
            gap = math.max(0, MODULE_GAP - trailingPadding)
        end
    end
    container:SetHeight(math.max(y, 1))
    return y + gap
end

-- ============================================================
-- Module attachment and ordering
-- ============================================================

function Custom.Add(host, container, module)
    if host.moduleToContainerMap[module] == container then return false end
    Custom.PrepareModule(module)
    local original = module._awpCustomHostMethods
    if container.DeferModuleCollapse and type(module.ToggleCollapsed) == "function" then
        original.toggle = module.ToggleCollapsed
        module.ToggleCollapsed = function(self)
            if not container:DeferModuleCollapse(self) then original.toggle(self) end
        end
    end
    host.moduleToContainerMap[module] = container
    container.modules[#container.modules + 1] = module
    module:SetContainer(container)
    module.isDirty = true
    return true
end

function Custom.Remove(host, container, module)
    for index = #container.modules, 1, -1 do
        if container.modules[index] == module then table.remove(container.modules, index) end
    end
    host.moduleToContainerMap[module] = nil
    module.parentContainer, module._awpCustomHostHeight = nil, nil
    module:Hide()
    local original = module._awpCustomHostMethods
    if original then
        module.AcquireFrame, module.FreeBlock = original.acquire, original.free
        if original.toggle then module.ToggleCollapsed = original.toggle end
        module._awpCustomHostMethods = nil
    end
end
