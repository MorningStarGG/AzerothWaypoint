local f = assert(loadfile("tests/daylight_fixture.lua"))()
local NS = AzerothWaypointNS
assert(loadfile("core/core.lua"))()
assert(loadfile("integrations/guides/viewer_styles.lua"))()
local settings = { showBanner = false }
NS.GetGuideTrackerViewerProviderSettings = function() return settings end
NS.Internal.StartupNotices = { RegisterArrow = function() return function() end end }
local common = NS.Internal.GuideTrackerViewer
common.Controls = { SetBlockHeaderText = function() end, SetStepCheckbox = function() end }
assert(loadfile("integrations/guides/viewer_render.lua"))()
local config
common.SourceViewer = { Register = function(value) config = value; return { GetStatus = function() end } end }
local q, creations, paints = { Skin = { key = "Mulgore" } }, 0, 0
local prototype = getmetatable(f.Frame()).__index
function prototype:CreateFontString() return f.Frame(self) end
function prototype:SetText(value) self.text = value; self.textWrites = (self.textWrites or 0) + 1 end
function prototype:SetJustifyH() end
function prototype:ClearAllPoints() self.points = {}; self.anchorWrites = (self.anchorWrites or 0) + 1 end
function prototype:SetPoint(point, relative, relativePoint, x, y)
    self.points = self.points or {}; self.points[point] = { relative, relativePoint, x or 0, y or 0 }
    self.anchorWrites = (self.anchorWrites or 0) + 1
end
function prototype:GetWidth()
    if self.allPoints then return self.allPoints:GetWidth() end
    local p = self.points
    local left, right = p and (p.LEFT or p.TOPLEFT), p and (p.RIGHT or p.TOPRIGHT)
    if left and right then
        return right[1]:GetRight() + right[3] - left[1]:GetLeft() - left[3]
    end
    return self.width or 260
end
function prototype:GetLeft()
    if self.allPoints then return self.allPoints:GetLeft() end
    local p = self.points and (self.points.LEFT or self.points.TOPLEFT)
    if p then return p[1]:GetLeft() + p[3] end
    return self.left or self.parent and self.parent:GetLeft() or 0
end
function prototype:GetRight() return self:GetLeft() + self:GetWidth() end
function prototype:OnAddedRegion(region) self.decoration = region end
local originalHide = prototype.Hide
function prototype:Hide()
    local shown = self:IsShown()
    originalHide(self)
    if shown and self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end
end
q.Banner = { Create = function(_, parent, options)
    assert(options.thumb == true, "Banner enabled the native animation loop")
    creations = creations + 1
    local banner = f.Frame(parent)
    function banner:SetZone(zone) self.zone = zone; paints = paints + 1 end
    return banner
end }
NS.Internal.QuestieRouterProvider = { GetRuntime = function() return q end, Subscribe = function() end,
    AddTaskChoices = function(root, snapshot) root.snapshot = snapshot end }
assert(loadfile("integrations/guides/questierouter/viewer.lua"))()
local module, block = f.Frame(), f.Frame()
module.ContentsFrame = f.Frame(module)
module.Header = f.Frame(module); module.Header:SetAllPoints(module)
module.blockOffsetX, module.left = 20, 37
module:SetWidth(280); block:SetWidth(260)
block.offsetX, block.left = 20, 57
local fits = true
function module:GetBlock() return block end
function module:LayoutBlock() return fits end
local snapshot = { state = "ready", title = "Mulgore", total = 53, displayCurrent = 14,
    bannerZone = "Mulgore", decorationSig = "Mulgore:0", canChooseTask = true, pinned = false }
assert(not config.beforeLayout(module, snapshot) and creations == 0)
settings.showBanner = true
assert(config.beforeLayout(module, snapshot))
local banner = module._awpQuestieBanner
assert(banner:GetParent() == module.ContentsFrame and banner.heading.text == "Mulgore")
assert(banner:GetWidth() == module.Header:GetWidth() and banner:GetLeft() == module.Header:GetLeft()
    and banner:GetRight() == module.Header:GetRight(), "Banner inherited asymmetric quest indentation")
assert(banner.points.TOP[1] == block and block.offsetX == 20 and module.blockOffsetX == 20,
    "Full-width decoration changed normal block geometry or lost vertical layout ownership")
assert(banner.caption.text == "14 / 53 quests" and banner.zone == "Mulgore")
assert(block.decoration == banner and not block._awpQuestieBanner, "Decoration did not join the normal block-free lifecycle")
local writes, captionWrites, titleWrites, beforePaints = banner.anchorWrites, banner.caption.textWrites, banner.heading.textWrites, paints
for _ = 1, 200 do config.resetLayout(module, snapshot); assert(config.beforeLayout(module, snapshot)) end
assert(banner.anchorWrites == writes and banner.caption.textWrites == captionWrites and banner.heading.textWrites == titleWrites)
assert(paints == beforePaints, "Unchanged layouts repainted native artwork")
for _, width in ipairs({180, 220, 320, 420}) do
    module:SetWidth(width); block:SetWidth(width - 20)
    banner.scripts.OnSizeChanged(banner)
    assert(banner:GetWidth() == width)
    local n = paints
    config.beforeLayout(module, snapshot)
    assert(paints == n, "Layout repainted a resize twice")
end
snapshot.displayCurrent = 15
config.beforeLayout(module, snapshot)
assert(banner.caption.text == "15 / 53 quests" and paints == beforePaints + 4, "Progress rebuilt unchanged art")
snapshot.bannerZone, snapshot.decorationSig = "Barrens", "Barrens:1"
config.beforeLayout(module, snapshot)
assert(banner.zone == "Barrens" and paints == beforePaints + 5)
snapshot.decorationSig = "Barrens:2"
config.beforeLayout(module, snapshot)
assert(paints == beforePaints + 6, "Native styling change was not repainted")
block = f.Frame(); block:SetWidth(200)
config.beforeLayout(module, snapshot)
assert(creations == 1 and banner:GetParent() == module.ContentsFrame and banner:GetWidth() == module.Header:GetWidth())
block.decoration:Hide() -- Native block release calls Hide on unmanaged added regions.
assert(banner._awpBlock == nil and next(banner.points) == nil, "Released pooled block still anchors the banner")
local recycledPaints = paints
block:SetWidth(170); banner.scripts.OnSizeChanged(banner)
assert(paints == recycledPaints, "Recycled foreign block caused an artwork refresh")
assert(config.beforeLayout(module, snapshot) and banner._awpBlock == block and banner:GetWidth() == module.Header:GetWidth())
assert(banner:GetLeft() == module.Header:GetLeft() and banner:GetRight() == module.Header:GetRight())
fits = false
assert(not config.beforeLayout(module, snapshot) and not banner:IsShown(), "Collapsed/truncated banner remained shown")
fits = true
assert(config.beforeLayout(module, snapshot) and banner:IsShown())
settings.showBanner = false
config.resetLayout(module, snapshot)
assert(not config.beforeLayout(module, snapshot) and not banner:IsShown())
settings.showBanner, settings.hideGuideTitle = true, true
assert(config.beforeLayout(module, snapshot) and banner.heading.text == "")
config.resetLayout(module) -- Detach.
assert(not banner:IsShown())
assert(config.headerActions.left.enabled(snapshot) and not config.headerActions.right.enabled(snapshot))
snapshot.pinned = true
assert(config.headerActions.right.enabled(snapshot))
f.combat = true
assert(not config.headerActions.left.enabled(snapshot) and not config.headerActions.right.enabled(snapshot))
f.combat = false
local root = { CreateTitle = function() end }
config.headerActions.left.menu(root, snapshot)
assert(root.snapshot == snapshot and config.headerActions.right.action == "automatic")
f.flavor = "retail"; config = nil
assert(loadfile("integrations/guides/questierouter/viewer.lua"))()
assert(config == nil, "QuestieRouter Viewer registered on Retail")
print("QuestieRouter Viewer: header-centered banner, cached paints/labels, resizing, native cleanup, collapse and task controls passed")
