local settings = { enabled = false, hideNative = false, ktHeaderStyle = {} }
local snapshot = { id = "forever/guide", title = "My guide", current = 5, rawCurrent = 7, epoch = 2,
    total = 20, done = 4, count = 20, state = "ready", tabs = {}, steps = {
        { index = 7, rows = { { text = "Accept 'Journal'", goalIndex = 3, stepIndex = 7, tickable = true,
            status = "incomplete", kind = "goal", action = "accept" } } },
    } }
local captured, actions = {}, {}
local factoryCount, attaches, dirty = 0, 0, 0
local Common = {}
local NS = { Internal = { GuideTrackerViewer = Common }, State = { routing = {} } }
local runtime = { Get = function() return false end }
_G.AzerothWaypointNS = NS
NS.IsWoWForever = function() return true end
_G.UIParent = {}
_G.InCombatLockdown = function() return false end
_G.StaticPopupDialogs = {}
_G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
NS.GetGuideTrackerViewerSettings = function(key) assert(key == "polestar"); return settings end
NS.GetGuideTrackerViewerProviderSettings = NS.GetGuideTrackerViewerSettings
NS.IsRoutingEnabled = function() return true end
NS.GetActiveGuideProvider = function() return "dugi" end
NS.IsPolestarLoaded = function() return true end
NS.RegisterGuideTrackerViewerProvider = function(key, provider) assert(key == "polestar"); captured.provider = provider end
NS.Internal.PolestarProvider = {
    GetRuntime = function() return runtime end,
    GetSnapshot = function() return snapshot end,
    Subscribe = function(fn) captured.listener = fn end,
    Action = function(...) actions[#actions + 1] = { ... }; return true end,
}
NS.Internal.PolestarPresentation = { Call = function() end }
Common.Host = { GetHostID = function() return "ellesmere" end }
Common.CreateNativeFrameCloak = function() return { Apply = function() end, IsApplied = function() return false end } end
Common.ModuleFactory = { Create = function(config)
    assert(config.uiOrder == 2.3 and config.providerKey == "polestar")
    factoryCount = factoryCount + 1
    local f = { blocks = {} }
    function f:GetBlock(key)
        self.blocks[key] = self.blocks[key] or { HeaderText = {}, height = 0 }
        return self.blocks[key]
    end
    function f:LayoutBlock() end
    return f
end }
Common.Controls = {
    Create = function(f, config) f.buttons = config end,
    SetModuleHeader = function(_, key) assert(key == "polestar") end,
    Update = function(_, current, total, percent) assert(current == 5 and total == 20 and percent == 20) end,
    SetBlockHeaderText = function(block, text) block.text = text end,
    SetStepCheckbox = function(block, _, binding) block.checkbox = binding end,
}
Common.Render = {
    EnsureBlockHeight = function(block, minimum) block.height = block.height or minimum end,
    AddObjective = function(block, index, row)
        block.rows = block.rows or {}
        local line = { row = row, scripts = {} }
        function line:SetScript(event, callback) self.scripts[event] = callback end
        function line:EnableMouse(enabled) self.mouseEnabled = enabled end
        block.rows[index] = line; return line
    end,
    WireTipTooltip = function() end,
}
Common.CreateViewerController = function(config)
    local controller = {}
    function controller:Attach() attaches = attaches + 1; captured.module = config.createModule() end
    function controller:Detach() end
    function controller:MarkDirty() dirty = dirty + 1 end
    function controller:IsAttached() return captured.module ~= nil end
    return controller
end
assert(loadfile("integrations/guides/viewer_chat.lua"))()
assert(loadfile("interface/menus.lua"))()
assert(loadfile("interface/startup_notices.lua"))()
assert(loadfile("integrations/guides/polestar/viewer.lua"))()
local registered = assert(captured.provider, "Polestar Viewer missing")
registered.applySettings()
assert(factoryCount == 0, "Viewer enabled by default")
settings.enabled = true
registered.applySettings()
assert(factoryCount == 1, "Enabled Viewer not constructed")
local module = assert(captured.module, "Polestar did not attach its module")
local listener = assert(captured.listener, "Polestar did not subscribe to guide changes")
module:LayoutContents()
local block = module.blocks.AwpPolestarStep1
assert(block.text == "My guide" and block.checkbox.tooltip == "Skip Step", "Header behavior differs from plan")
assert(not block.rows[1].row.checkbox, "Competing per-goal checkbox introduced")
assert(block.rows[1].mouseEnabled, "Goal actions did not enable mouse input")
block.checkbox.onClick()
assert(actions[1][1] == "skip" and actions[1][3] == 7 and actions[1][5] == 2, "Header used display numbering or lost epoch")
module.buttons.onNext()
assert(actions[2][1] == "next", "Next incorrectly completes or skips")
local a, d = attaches, dirty
listener(snapshot, false)
assert(attaches == a and dirty == d, "Unchanged update dirtied or reattached Viewer")
assert(NS.GetPolestarTrackerViewerStatus().host == "ellesmere")
local entries
_G.MenuUtil = { CreateContextMenu = function(_, generator)
    entries = {}
    local root = {}
    function root:CreateTitle() end
    function root:CreateDivider() end
    function root:CreateRadio(label, _, callback) entries[label] = callback; return self end
    function root:CreateButton(label, callback) entries[label] = callback or true; return self end
    generator(nil, root)
end }
-- Shared buttons pass both the anchor and mouse button to callbacks.
module.buttons.onMenu(module, "LeftButton")
assert(type(entries["Make Polestar Active"]) == "function" and entries["Route Selected Goal"]
    and entries["Skip Step"], "Header click was mistaken for the guide-only menu flag")
entries["Make Polestar Active"]()
assert(actions[#actions][1] == "active", "Make Active did not reach the provider action")
module:OnBlockHeaderClick(block, "LeftButton")
assert(entries["Make Polestar Active"] and entries["Open New Guide..."] and not entries["Skip Step"],
    "Guide-title menu omitted Make Active or lost its guide-only layout")
module:OnBlockHeaderClick(block, "RightButton")
assert(entries["Make Polestar Active"] and entries["Skip Step"], "Right-click actions menu was incomplete")
-- The cog uses the actual native handler, anchored to the AWP button. Native
-- menu state/toggling stays native even when its guide window is cloaked.
local anchor, owner, open, renders = {}, nil, false, 0
local shown = true
local guide = { frame = { IsShown = function() return shown end },
    Render = function() renders = renders + 1 end }
local nativeClick = function(button)
    assert(button == anchor, "Native menu anchored to the hidden guide window")
    owner, open = button, not open
end
guide.menuButton = { GetScript = function(_, event) assert(event == "OnClick"); return nativeClick end }
runtime.UI = { GuideFrame = guide }
a = #actions
assert(module.buttons.onSettings(anchor) and owner == anchor and open and renders == 0, "Cog did not open native menu")
module.buttons.onSettings(anchor)
assert(not open and renders == 0 and #actions == a, "Cog lost native toggle behavior or opened options instead")
shown = false
module.buttons.onSettings(anchor)
assert(open and renders == 1 and not shown and #actions == a, "Closed native window was shown or its menu used stale step data")
guide.menuButton.GetScript = function() return function() error("native menu unavailable") end end
module.buttons.onSettings(anchor)
assert(actions[#actions][1] == "settings", "Native menu failure did not preserve access to settings")
guide.menuButton = nil
module.buttons.onSettings(anchor)
assert(actions[#actions][1] == "settings", "Late native initialization left the cog unusable")
guide.menuButton = { GetScript = function() return nativeClick end }
module.buttons.onSettings(anchor)
assert(not open, "Late-ready native menu was not detected")
print("Polestar shared Viewer lifecycle and controls passed")

-- Menu and command closures share live identity resolution, not a stale index.
local tabs = { {guideId="first"}, {guideId="second"}, {guideId="third"} }
runtime.Engine = { GetTabs=function() return tabs end, CloseTab=function(index) table.remove(tabs,index) end }
NS.Internal.PolestarPresentation.Call = function(object, key, ...) return object[key](...) end
NS.Internal.PolestarProvider.Schedule = function() end
snapshot.tabs = { {id="first",title="First"}, {id="second",title="Second"}, {id="third",title="Third"} }
module:OnBlockHeaderClick(block, "LeftButton")
local closeFromMenu = entries.Second
assert(type(closeFromMenu) == "function")
assert(registered.controls.close({id="first"}) == true)
closeFromMenu()
assert(#tabs == 1 and tabs[1].guideId == "third", "Menu closed stale tab index after command close")
assert(registered.controls.close({id="second"}) == false, "Repeated close claimed success")
assert(registered.controls.close({id="third"}) == true and #tabs == 0)
print("Polestar actual command/menu close parity and stale identity rejection passed")

-- The recommendation changes only the explicit follower preference.
_G.AzerothWaypointCharDB = {}
local changed = {}
runtime.Set = function(key, value) changed[key] = value end
runtime.Get = function(key) return key == "nav.arrow" end
_G.StaticPopup_Visible = function() return false end
_G.StaticPopup_Show = function() return true end
NS.MaybeShowPolestarArrowRecommendationPopup()
StaticPopupDialogs.AWP_POLESTAR_ARROW.OnAccept()
assert(changed["nav.arrowToFollower"] == true and changed["nav.arrow"] == nil and changed["nav.useTomTomArrow"] == nil)
assert(AzerothWaypointCharDB.polestarArrowPromptShown)
print("Polestar arrow recommendation preserves native arrow preferences")

-- Hover metadata is separate from authored tips and never acquires the
-- original goal's route/checkoff action on a heading or supporting line.
Common.Render.WireTipTooltip = function(line, title, tips) line.hoverTitle, line.hoverTips = title, tips end
snapshot.steps = { { index=7, rows={
    {text="Lorekeeper",role="heading",kind="tip"},
    {text="Accept quest",kind="goal",stepIndex=7,goalIndex=3,hoverTips={{text="from Lorekeeper"}}},
    {text="Bring the required items",role="support",kind="tip"},
} } }
module:LayoutContents()
block = module.blocks.AwpPolestarStep1
assert(block._awpOwnerStepIndex==7 and not block.rows[1].mouseEnabled and not block.rows[3].mouseEnabled)
assert(block.rows[2].hoverTips==snapshot.steps[1].rows[2].hoverTips and block.rows[2].mouseEnabled)
block.rows[2].scripts.OnMouseUp(block.rows[2],"LeftButton")
assert(actions[#actions][1]=="route" and actions[#actions][3]==7 and actions[#actions][4]==3)
print("Polestar grouped viewer hover and exact goal click ownership passed")
