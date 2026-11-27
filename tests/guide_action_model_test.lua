local f = assert(loadfile("tests/daylight_fixture.lua"))()
assert(loadfile("core/core.lua"))()
assert(loadfile("core/quest_data.lua"))()
assert(loadfile("core/quest_text.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("interface/appearance/controller.lua"))()
assert(loadfile("interface/appearance/visuals.lua"))()
local NS = AzerothWaypointNS
local Frame = getmetatable(f.Frame())
function Frame:GetAttribute(key) return self.attributes and self.attributes[key] end
function Frame:SetAttribute(key, value)
    assert(not self.secure or not f.combat, "Protected binding changed during combat")
    self.attributes = self.attributes or {}; self.attributes[key] = value
    self.attributeWrites = (self.attributeWrites or 0) + 1
end
function Frame:GetScript(key) return self.scripts and self.scripts[key] end
function Frame:CreateTexture() return f.Frame(self) end
function Frame:CreateFontString() return f.Frame(self) end
function Frame:SetTexture(value) self.texture, self.atlas = value, nil end
function Frame:GetTexture() return self.texture end
function Frame:SetHighlightTexture() end
function Frame:SetText(value) self.text = value end
function Frame:SetWordWrap(value) self.wrap = value end
function Frame:CanWordWrap() return self.wrap == true end
function Frame:SetMaxLines(value) self.maxLines = value end
function Frame:GetMaxLines() return self.maxLines or 2 end
function Frame:RegisterForClicks() end
function Frame:SetBackdrop() end
function Frame:SetBackdropColor() end
function Frame:SetBackdropBorderColor() end
function Frame:SetMovable() end
function Frame:SetClampedToScreen() end
function Frame:RegisterForDrag() end
function Frame:StartMoving() end
function Frame:StopMovingOrSizing() end
function Frame:ClearAllPoints() self.points, self.point = nil, nil end
function Frame:SetPoint(point, ...)
    self.points = self.points or {}
    self.point = { point, ... }
    for index, previous in ipairs(self.points) do
        if previous[1] == point then self.points[index] = self.point; return end
    end
    self.points[#self.points + 1] = self.point
end
function Frame:GetNumPoints() return self.points and #self.points or 0 end
function Frame:GetPoint(index) return unpack(self.points and self.points[index or 1] or {}) end
function Frame:Click(button, down) self.clicks = self.clicks or {}; self.clicks[#self.clicks + 1] = { button, down } end
local create = CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
    local frame = create(kind, name, parent, template)
    frame.secure, frame.template = template == "SecureActionButtonTemplate", template
    if template == "SecureActionButtonTemplate" or template == "InsecureActionButtonTemplate" then
        frame:SetScript("OnClick", function() end)
    end
    return frame
end
local Common = { }
NS.Internal.GuideTrackerViewer = Common
Common.CreateNativeFrameCloak = function(config)
    return { Refresh = function(self) self.frames, self.wanted = config.resolve() end }
end
local settings = { apr = { enabled = true, inline = true, types = {} }, wowpro = { enabled = false, types = {} } }
NS.GetGuideActionSettings = function(key) return settings[key] or { types = {} } end
NS.GetGuideTrackerViewerProviderSettings = function() return {visibleTasks = 1} end
NS.ApplyGuideTrackerViewerSettings = function() end
local layouts = 0
NS.RefreshGuideTrackerViewerProvider = function() layouts = layouts + 1 end
NS.SetGuideActionSetting = function(key, option, value) settings[key][option] = value end
assert(loadfile("integrations/guides/presentation.lua"))()
assert(loadfile("integrations/guides/quest_selection.lua"))()
assert(loadfile("integrations/guides/source_runtime.lua"))()
assert(loadfile("integrations/guides/guide_actions.lua"))()
local A = Common.GuideActions
local guide, step, item, unsupported = "guide", 5, 123, false
local extraItems = 0
local native = f.Frame(); native:Show(); native:SetAttribute("type", "macro"); native:SetAttribute("macrotext", "/native procedure")
native:SetScript("PostClick", function() end)
local collectorRuns = 0
A.Register("apr", {
    identity = function() return guide, step end,
    collect = function()
        collectorRuns = collectorRuns + 1
        local b = A.CreateBuilder("apr", guide, step)
        b:Emit("item", "items", item, "Use item", 111, step)
        b:Emit("native", "helpers", nil, "Native helper", 222, step, native, unsupported)
        for n = 1, extraItems do b:Emit("item", "items", 100 + n, "Use item", 111, step) end
        return b:Finish()
    end,
    frames = function() return { native } end,
})
A.Request("apr"); f.Flush()
local model, panel = A.models.apr, A.panels.apr
assert(#model.actions == 2 and panel:IsShown() and panel.standard[1]:GetAttribute("item") == "item:123")
assert(panel.standard[1].template == "SecureActionButtonTemplate" and panel.standard[2].secure)
assert(A.CanHideNative("apr", true))
for _ = 1, 100 do A.Request("apr") end
f.Flush()
assert(collectorRuns == 2 and A.models.apr == model and A.counters.reused == 1, "Unchanged burst rebuilt its model")
assert(not A.InvokeNative("apr", model.actions[2], "RightButton", false), "Protected native handler was called from Lua")
local macro = panel.standard[2]
assert(macro:GetAttribute("type") == "macro" and macro:GetAttribute("macrotext") == "/native procedure")
local templateClick = macro:GetScript("OnClick")
assert(templateClick, "Secure template handler was removed")
macro:GetScript("PreClick")(macro, "LeftButton", false)
macro:GetScript("PostClick")(macro, "LeftButton", false)
assert(macro:GetScript("OnClick") == templateClick and native.clicks == nil)
local function AnchorOffset(button) return select(4, button:GetPoint()) end
assert(panel.handle and panel:GetWidth() < 180 and panel:GetWidth() >= panel.title:GetUnboundedStringWidth() + 16,
    "Panel width did not fit its title")
assert(AnchorOffset(panel.buttons[1]) == -16 and AnchorOffset(panel.buttons[2]) == 16, "Panel icons were not centered")
assert(panel:GetHeight() - panel.handle:GetHeight() - panel.buttons[1]:GetHeight() == 8, "Panel lost its bottom padding")
panel.handle:GetScript("OnDragStart")(panel.handle)
panel.handle:GetScript("OnDragStop")(panel.handle)
assert(settings.apr.position and settings.apr.position.point == "CENTER")
native:SetAttribute("macrotext", "/different binding")
assert(not A.InvokeNative("apr", model.actions[2], "LeftButton", false), "A stale native callback ran")
f.Flush(); model = A.models.apr
f.combat = true
local writes = panel.standard[1].attributeWrites
item, step = 456, 6
A.Request("apr"); f.Flush()
assert(A.models.apr ~= model and model.actions[1].payload == 123, "Prepared model mutated")
assert(panel.standard[1]:GetAttribute("item") == "item:123" and panel.standard[1].attributeWrites == writes)
assert(panel._awpPending and panel.title.text:find("Step 5 *", 1, true), "Pending label lost original ownership")
assert(not A.InvokeNative("apr", model.actions[2], "LeftButton", false), "Native helper ran in combat")
f.combat = false
f.Fire("PLAYER_REGEN_ENABLED"); f.Flush()
assert(panel.standard[1]:GetAttribute("item") == "item:456" and not panel._awpPending)
assert(not A.InvokeNative("apr", model.actions[2], "LeftButton", false), "Old owner survived step change")
local styled = {}
NS.Internal.Appearance.StyleButton = function(button, surface, facet, nativeArt) styled[button] = { surface, facet, nativeArt } end
local line = f.Frame(); line:SetSize(180, 18)
line.Text = f.Frame(line); line.Text:SetWidth(180); line.Text:SetPoint("TOPLEFT", line, "TOPLEFT", 8, 0)
line.Text.GetStringHeight = function(self)
    local anchor, _, _, inset = self:GetPoint(2)
    return anchor == "RIGHT" and inset and inset <= -48 and 36 or 18
end
local module = {}
local rowBlock = { height = 18 }
A.BeginLayout(module); A.BindRow(line, "apr", 6, module, rowBlock)
assert(#line._awpInlineActions.buttons == 2 and line:GetHeight() == 36 and rowBlock.height == 36,
    "Inline reservation did not remeasure the wrapped row")
assert(line._awpInlineActions.buttons[1]:GetWidth() == 24 and styled[line._awpInlineActions.buttons[1]][2] == "actions")
assert(line.Text:CanWordWrap() and line.Text:GetMaxLines() == 0, "Action row could not wrap to fit")
assert(line._awpInlineActions.standard[1].template == "InsecureActionButtonTemplate")
local second = f.Frame(); second.Text = f.Frame(second)
A.BindRow(second, "apr", 6, module)
assert(not second._awpInlineActions, "Action set duplicated on every goal in one step")
A.ReleaseRow(line)
assert(line.Text:GetWidth() == 180 and not line._awpInlineActions.buttons[1]:IsShown())
assert(line.Text:GetNumPoints() == 1 and not line.Text:CanWordWrap() and line.Text:GetMaxLines() == 2)

local anchored = f.Frame(); anchored:SetSize(240, 18)
anchored.Text = f.Frame(anchored)
anchored.Text:SetPoint("TOP", anchored, "TOP", 0, 0)
anchored.Text:SetPoint("LEFT", anchored, "LEFT", 12, 0)
anchored.Text:SetPoint("RIGHT", anchored, "RIGHT", 0, 0)
A.BeginLayout(module); A.BindRow(anchored, "apr", 6, module, { height = 18 })
local _, _, _, reserved = anchored.Text:GetPoint(3)
local insideButton = anchored._awpInlineActions.buttons[2]
assert(reserved == AnchorOffset(insideButton) - insideButton:GetWidth() and anchored.Text:GetNumPoints() == 3,
    "Host text anchors conflicted with the inline reservation")
A.ReleaseRow(anchored)
local _, _, _, restored = anchored.Text:GetPoint(3)
assert(restored == 0 and anchored.Text:GetWidth() == 0, "A pooled row kept the reserved width after release")

local narrow = f.Frame(); narrow:SetSize(45, 18)
narrow.Text = f.Frame(narrow); narrow.Text:SetWidth(41); narrow.Text:SetPoint("LEFT", narrow, "LEFT", 4, 0)
local narrowBlock = { height = 18 }
A.BeginLayout(module); A.BindRow(narrow, "apr", 6, module, narrowBlock)
local _, _, _, x, y = narrow._awpInlineActions.buttons[2]:GetPoint()
assert(x == 0 and y == -50 and narrowBlock.height == -y + narrow._awpInlineActions.buttons[2]:GetHeight() and narrow.Text:GetWidth() == 41,
    "Buttons on a narrow row did not move below the text and wrap")
A.ReleaseRow(narrow)

settings.polestar = { inline = true, types = {} }
A.Register("polestar", { stepActions = true })
A.models.polestar = A.models.apr
local stepModule = { _awpGuideProvider = "polestar" }
local stepBlock = { height = 40 }
function stepBlock:AddObjective(id, text, _, _, _, _, _, height)
    assert(id == "AwpGuideStepActions" and text == "")
    self.strip = f.Frame()
    self.strip:SetSize(self.rowWidth or 180, height)
    self.strip.Dash = f.Frame(self.strip)
    self.height = self.height + height
    return self.strip
end
A.BeginLayout(stepModule); A.BindRow(second, "polestar", 6, stepModule, stepBlock)
assert(not second._awpInlineActions, "Step-level group bound to an unrelated goal")
A.LayoutStepStrip(stepModule, stepBlock)
assert(stepBlock.height == 40 + stepBlock.strip:GetHeight() and not stepBlock.strip.Dash:IsShown()
    and #stepBlock.strip._awpInlineActions.buttons == 2
    and AnchorOffset(stepBlock.strip._awpInlineActions.buttons[1]) == -14
    and AnchorOffset(stepBlock.strip._awpInlineActions.buttons[2]) == 14
    and styled[stepBlock.strip._awpInlineActions.buttons[1]][1] == "guide.polestar")
A.ReleaseRow(stepBlock.strip)

local hostWidth = 290
stepModule.GetWidth = function() return hostWidth end
stepModule.blockOffsetX = 20
stepBlock.parentModule, stepBlock.rightEdgeOffset, stepBlock.rowWidth = stepModule, -10, 24
local firstAction, secondAction = unpack(A.models.polestar.actions)
A.models.polestar = { actions = { firstAction, secondAction, { kind = "item", payload = 90, category = "items", owner = 6 } } }
A.BeginLayout(stepModule); A.BindRow(second, "polestar", 6, stepModule, stepBlock)
A.LayoutStepStrip(stepModule, stepBlock)
local actionButtons = stepBlock.strip._awpInlineActions.buttons
assert(#actionButtons == 3 and stepBlock.strip:GetHeight() == actionButtons[1]:GetHeight()
    and AnchorOffset(actionButtons[1]) == -28 and AnchorOffset(actionButtons[3]) == 28,
    "A stale narrow row broke a grouped strip with room for all three actions")
A.ReleaseRow(stepBlock.strip)

hostWidth, stepBlock.rowWidth = 80, 290
A.BeginLayout(stepModule); A.BindRow(second, "polestar", 6, stepModule, stepBlock)
A.LayoutStepStrip(stepModule, stepBlock)
local bottomButton = stepBlock.strip._awpInlineActions.buttons[3]
local _, _, _, _, offsetY = bottomButton:GetPoint()
assert(stepBlock.strip:GetHeight() == bottomButton:GetHeight() - offsetY and offsetY < 0 and AnchorOffset(bottomButton) == 0,
    "A stale wide row prevented wrapping in a genuinely narrow host")
A.ReleaseRow(stepBlock.strip)
stepBlock.parentModule, stepBlock.rowWidth = nil, nil
hostWidth = 290

settings.polestar.groupPosition = "above"
Common.Host = { IsKTLoaded = function() return false end }
Common.Styles = {
    GetProviderKey = function(region) return region._awpGuideProvider or region.parentModule._awpGuideProvider end,
    GetTrackerColorStyle = function() return { r = 1, g = 1, b = 1 } end,
}
Common.Controls = { SetStepCheckbox = function() end }
NS.Internal.Appearance.Text = function() end
assert(loadfile("integrations/guides/viewer_render.lua"))()
stepModule.lineSpacing = 4
local leadingBlock = { parentModule = stepModule, _awpHiddenGuideTitle = true, height = 0, rows = {} }
function leadingBlock:AddObjective(id, text, _, _, _, _, _, height)
    local row = f.Frame()
    row:SetSize(180, height or 18)
    row.Text = row:CreateFontString()
    row.Text:SetText(text)
    row:SetPoint("TOPLEFT", self.rows[#self.rows] or self, "BOTTOMLEFT", 0, -4)
    self.rows[#self.rows + 1] = row
    self.height = self.height + row:GetHeight() + 4
    return row
end
A.BeginLayout(stepModule)
local firstObjective = Common.Render.AddObjective(leadingBlock, 1, { text = "Polestar objective", stepIndex = 6 })
local strip = leadingBlock.rows[1]
local _, anchor = firstObjective:GetPoint()
assert(#leadingBlock.rows == 2 and anchor == strip
    and leadingBlock.height == strip:GetHeight() + firstObjective:GetHeight() + stepModule.lineSpacing,
    "Leading grouped strip overlapped the first objective when the guide title was hidden")
A.LayoutStepStrip(stepModule, leadingBlock)
assert(#leadingBlock.rows == 2, "Above-objectives strip was added again below the objectives")
A.ReleaseRow(strip)

-- Group headings keep the step strip's single owner. They cannot claim a
-- goal button, and an above-objectives strip cannot collide with the heading.
for _, position in ipairs({"above", "below"}) do
    settings.polestar.groupPosition = position
    local grouped = { parentModule = stepModule, _awpOwnerStepIndex = 6,
        _awpHiddenGuideTitle = true, height = 0, rows = {}, AddObjective = leadingBlock.AddObjective }
    A.BeginLayout(stepModule)
    local heading = Common.Render.AddObjective(grouped, 1, { text = "NPC", kind = "tip", role = "heading" })
    local objective = Common.Render.AddObjective(grouped, 2, { text = "Quest", kind = "goal", stepIndex = 6 })
    Common.Render.AddObjective(grouped, 3, { text = "Instructions", kind = "tip", role = "support" })
    A.LayoutStepStrip(stepModule, grouped)
    local count, actionLine = 0, nil
    for _, row in ipairs(grouped.rows) do
        if row._awpInlineActions then count, actionLine = count + 1, row end
    end
    assert(count == 1 and actionLine ~= heading and actionLine ~= objective,
        "Decorative rows absorbed or duplicated step actions")
    assert(grouped._awpFirstObjective == objective)
    assert(grouped.rows[position == "above" and 1 or #grouped.rows] == actionLine)
    A.ReleaseRow(actionLine)
end

settings.zygor = { inline = true, types = {} }
A.Register("zygor", { stepActions = true })
local mixedModule = { _awpGuideProvider = "zygor" }
local framedAction = { kind = "item", payload = 456, category = "items", owner = "goal:6:2", icon = 555, framedIcon = true }
local groupedAction = { kind = "item", payload = 457, category = "items", owner = 6, icon = 556 }
A.models.zygor = { actions = { framedAction, groupedAction } }
A.BeginLayout(mixedModule)
A.BindRow(second, "zygor", "goal:6:1", mixedModule, stepBlock, 6)
assert(not second._awpInlineActions, "Zygor action was placed beside the wrong objective")
A.BindRow(line, "zygor", "goal:6:2", mixedModule, stepBlock, 6)
local framedButton = line._awpInlineActions.buttons[1]
assert(framedButton._awpAction == framedAction and styled[framedButton][3] == true
    and not framedButton._awpNativeButtonRegions[1]:IsShown())
A.LayoutStepStrip(mixedModule, stepBlock)
assert(#stepBlock.strip._awpInlineActions.buttons == 1
    and stepBlock.strip._awpInlineActions.buttons[1]._awpAction == groupedAction)
mixedModule.lastBlock = stepBlock
assert(A.GetTrailingPadding(mixedModule) == stepBlock.strip:GetHeight() - stepBlock.strip._awpInlineActions.buttons[1]:GetHeight(),
    "A trailing action strip did not report its bottom padding")
mixedModule.lastBlock = leadingBlock
assert(A.GetTrailingPadding(mixedModule) == 0, "An earlier action strip reduced the final gap")
mixedModule.lastBlock = stepBlock
A.ReleaseRow(stepBlock.strip)
assert(A.GetTrailingPadding(mixedModule) == 0, "A pooled action row retained its trailing padding")
local ordinaryAction = { kind = "item", payload = 456, category = "items", owner = "goal:6:2", icon = 557 }
A.models.zygor = { actions = { ordinaryAction } }
A.BeginLayout(mixedModule)
A.BindRow(line, "zygor", "goal:6:2", mixedModule, stepBlock, 6)
assert(line._awpInlineActions.buttons[1] == framedButton and not styled[framedButton][3]
    and framedButton._awpNativeButtonRegions[1]:IsShown(), "Reused button kept the framed-art override")
A.ReleaseRow(line)

A.BeginLayout(module); A.BindRow(line, "apr", 6, module)
f.combat = true; A.ReleaseRow(line); A.BindRow(line, "apr", 6, module)
assert(not line._awpInlineActions.buttons[1]:IsShown(), "Inline actions remained active in combat")
f.combat = false
unsupported = true; A.Request("apr"); f.Flush()
assert(not A.CanHideNative("apr", true), "Unsupported required helper was hidden")
settings.apr.types.items = false
A.Request("apr", true); f.Flush()
assert(not panel.standard[1]:IsShown() and not settings.wowpro.types.items, "Filter leaked to another provider")
assert(A.CreateBuilder("apr", guide, step) == A.CreateBuilder("apr", guide, step), "Builder was allocated on every observation")
unsupported = false; settings.apr.types.items = true; settings.apr.enabled = false
A.Request("apr", true); f.Flush()
assert(not A.CanHideNative("apr", true), "Merely enabling inline mode claimed coverage without rendered controls")
A.BeginLayout(module); A.BindRow(line, "apr", 6, module)
assert(A.CanHideNative("apr", true), "Rendered inline controls were not counted")
A.ReleaseRow(line)
assert(not A.CanHideNative("apr", true), "Hidden/disabled Viewer left native controls hidden")
local cropped = { icon = "sheet", iconCoords = { .1, .2, .1, .4, .3, .2, .3, .4 }, kind = "item", payload = 456 }
local portrait = { icon = "crosshair", portrait = 987, kind = "item", payload = 456 }
_G.SetPortraitTextureFromCreatureDisplayID = function(texture, displayID) texture:SetTexture("portrait:" .. displayID) end
for _, button in ipairs({ panel.standard[1], line._awpInlineActions.standard[1] }) do
    A.Bind(button, "apr", cropped, true)
    assert(button.icon.texture == "sheet" and button.icon.coords[8] == .4)
    A.Bind(button, "apr", portrait, true)
    assert(button.icon.texture == "portrait:987" and #button.icon.coords == 4 and button.icon.coords[4] == 1)
    A.Bind(button, "apr", { iconAtlas = "guide-atlas", kind = "item", payload = 456 }, true)
    assert(button.icon.atlas == "guide-atlas")
    A.Bind(button, "apr", { icon = 222, kind = "item", payload = 456 }, true)
    assert(not button.icon.atlas and button.icon.texture == 222, "A pooled action kept previous artwork")
end
settings.apr.enabled, extraItems = true, 5
A.Request("apr", true); f.Flush()
assert(#panel.buttons == 7 and AnchorOffset(panel.buttons[1]) == -80 and AnchorOffset(panel.buttons[6]) == 80
    and AnchorOffset(panel.buttons[7]) == 0, "A partial final panel row was not independently centered")
extraItems = 0
A.Request("apr", true); f.Flush()
local panelWidth, panelHeight = panel:GetWidth(), panel:GetHeight()
f.combat = true
panel.title.size = 25
A.RefreshPanelSizes()
assert(panel:GetWidth() == panelWidth and panel:GetHeight() == panelHeight, "Panel changed size during combat")
f.combat = false
NS.Internal.Appearance.RequestRefresh(); f.Flush()
assert(panel:GetWidth() > panelWidth and panel:GetHeight() > panelHeight, "Panel did not fit its new title font")
panel:Hide()
assert(not A.CanHideNative("apr"), "A configured panel covered actions before it was shown")
settings.apr.enabled, settings.apr.inline, settings.apr.hideNative = false, false, true
local beforeCollect, beforeLayout = collectorRuns, layouts
A.Request("apr", true); f.Flush()
local nativeCloak = A.providers.apr.cloak
assert(nativeCloak.wanted and nativeCloak.frames[1] == native and A.CanHideNative("apr"))
assert(collectorRuns == beforeCollect and layouts == beforeLayout + 1, "Turning off inline actions failed to clear the layout")
unsupported, step = true, 7
settings.apr.types.helpers = false
A.Request("apr", true); f.Flush()
A.EndLayout("apr")
assert(nativeCloak.wanted and collectorRuns == beforeCollect and layouts == beforeLayout + 1,
    "Hide-only updates collected a model, redrew guides, or restored the native controls")
settings.apr.hideNative = false
A.Request("apr", true); f.Flush()
assert(not nativeCloak.wanted and not A.CanHideNative("apr"), "Whole-frame coverage bypass survived the explicit hide setting")
-- Use the real QuestieRouter snapshot and action collector with the shared
-- objective renderer, including the item and quest from the Forever report.
local winterhoof = {kind = "objective", questIds = {754},
    lines = {{text = "Cleanse the Winterhoof Water Well"}},
    point = {uiMapId = 1412, x = .53, y = .66}}
local mulgore = {key = "mulgore", quests = {754}}
local qr = {
    ready = true,
    db = {enabled = true},
    Planner = {
        GetGuide = function() return mulgore end,
        PinStep = function() end, UnpinStep = function() end, SetGuide = function() end,
        plan = {guide = mulgore, steps = {winterhoof}},
    },
    Bridge = {QuestieDB = {QueryQuestSingle = function(questID, field)
        assert(questID == 754)
        if field == "sourceItemId" then return 5411 end
        if field == "requiredSourceItems" then return {9001} end
    end}},
    On = function() end,
}
local qrItems, qrTargets = f.Frame(), f.Frame()
qr.ActiveFrames = {items = qrItems, targets = qrTargets}
local function QRItem(id)
    local button = f.Frame(qrItems)
    button.itemId = id
    button:SetAttribute("type1", "item")
    button:SetAttribute("item1", "item:" .. id)
    return button
end
local extraItem = QRItem(9001)
extraItem:Hide()
qrItems.buttons = {QRItem(5411), QRItem(5415), extraItem}
local qrTarget = f.Frame(qrTargets)
qrTarget.entry = {kind = "friendly"}
qrTarget:SetAttribute("type1", "macro")
qrTarget:SetAttribute("macrotext1", "/targetexact Guide NPC")
qrTargets.buttons = {qrTarget}
_G.QuestieRouter = qr
NS.IsAddonLoaded = function() return true end
NS.RegisterExternalWaypointSource = function() end
NS.RegisterGuideTargetProvider = function() end
settings.questierouter = {inline = true, groupPosition = "below", types = {friendly = false}}
for _, file in ipairs({"runtime", "questierouter_presentation", "questierouter_provider", "actions"}) do
    assert(loadfile("integrations/guides/questierouter/" .. file .. ".lua"))()
end
local qrAPI = NS.Internal.QuestieRouterProvider
local qrModule = f.Frame()
qrModule._awpGuideProvider = "questierouter"
qrModule:SetWidth(280)
local function DrawWinterhoof()
    local snapshot = qrAPI.RefreshNow()
    A.Request("questierouter", true)
    f.Flush()
    local block = {parentModule = qrModule, rows = {}, height = 0, AddObjective = leadingBlock.AddObjective}
    A.BeginLayout(qrModule)
    for index, row in ipairs(snapshot.steps[1].rows) do Common.Render.AddObjective(block, index, row) end
    A.LayoutStepStrip(qrModule, block)
    return block.rows
end
local qrRows = DrawWinterhoof()
assert(#qrRows == 1 and qrRows[1].Text:GetText() == winterhoof.lines[1].text)
local inlineTotem = qrRows[1]._awpInlineActions.buttons[1]
local point, anchoredTo = inlineTotem:GetPoint()
assert(point == "TOPRIGHT" and anchoredTo == qrRows[1] and inlineTotem._awpAction.payload == 5411,
    "Lone Winterhoof item did not anchor beside its objective")
assert(A.models.questierouter.actions[2].payload == 5415 and not A.models.questierouter.actions[2].owner,
    "The unrelated item entered the tracker")

settings.questierouter.types.friendly = true
qrRows = DrawWinterhoof()
assert(#qrRows == 2 and qrRows[1].Text:GetText() == winterhoof.lines[1].text
    and #qrRows[2]._awpInlineActions.buttons == 2, "Two eligible actions did not group below the objective")
settings.questierouter.types.friendly = false
settings.questierouter.groupPosition = "above"
extraItem:Show()
qrRows = DrawWinterhoof()
assert(#qrRows == 2 and #qrRows[1]._awpInlineActions.buttons == 2
    and qrRows[2].Text:GetText() == winterhoof.lines[1].text, "Multiple items ignored the above-objectives setting")

extraItem:Hide()
winterhoof.lines[2] = {text = "Another unfinished objective for the same quest"}
settings.questierouter.groupPosition = "below"
qrRows = DrawWinterhoof()
assert(#qrRows == 3 and #qrRows[3]._awpInlineActions.buttons == 1,
    "An item with multiple possible rows was attached to one arbitrarily")
winterhoof.lines[2].done = true
qrRows = DrawWinterhoof()
assert(#qrRows == 2 and qrRows[1]._awpInlineActions.buttons[1]:GetPoint() == "TOPRIGHT",
    "A completed objective blocked the remaining objective's item")
winterhoof.description = "Use the totem at the well.\n\nReturn to the village afterward."
qrRows = DrawWinterhoof()
assert(qrRows[1].Text:GetText() == winterhoof.description and not qrRows[1]._awpInlineActions)
assert(qrRows[2]._awpInlineActions.buttons[1]:GetPoint() == "TOPRIGHT",
    "A description row displaced the current objective's item")
print("guide_action_model_test: passed")
