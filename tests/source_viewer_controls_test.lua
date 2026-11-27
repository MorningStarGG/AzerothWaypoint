local f = assert(loadfile("tests/daylight_fixture.lua"))()
assert(loadfile("core/core.lua"))()
assert(loadfile("core/scheduling.lua"))()
local NS = AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local host, loaded, enabled = "blizzard", true, true
local registered, created, selection, history = {}, {}, nil, { "g1", "g2" }
local lastAction
local settings = { enabled = true }
NS.GetGuideTrackerViewerProviderSettings = function() return settings end
NS.RegisterGuideTrackerViewerProvider = function(key, value) registered[key] = value end
NS.GetGuideTrackerViewerProvider = function(key) return registered[key] end
Common.Host = { GetHostID = function() return host end }
Common.Controls = { Create = function(module, config) module.controls = config end,
    SetModuleHeader = function() end, Update = function() end,
    SetGuideTitleTooltip = function() end,
    SetBlockHeaderText = function() end, SetStepCheckbox = function() end }
Common.Render = { AddObjective = function() return f.Frame() end, WireTipTooltip = function() end, EnsureBlockHeight = function() end }
Common.HeaderStyle = { CaptureBaseline = function() end, Refresh = function() end }
Common.ModuleFactory = { Create = function(config)
    local module = f.Frame(); module.order = config.uiOrder
    module.blocks={}
    function module:GetBlock(id)
        if not self.blocks[id] then self.blocks[id]=f.Frame() end
        return self.blocks[id]
    end
    function module:LayoutBlock() end
    created[config.providerKey] = module; return module
end }
Common.CreateViewerController = function(config)
    return { Attach = function(self) if config.isEnabled() then self.module = self.module or config.createModule(); self.attached = true end end,
        Detach = function(self) self.attached = false end, IsAttached = function(self) return self.attached end, MarkDirty = function() end }
end
Common.CreateNativeFrameCloak = function() return { Refresh = function() end, IsApplied = function() return false end } end
Common.GetOpenGuides = function() return history end
Common.SetOpenGuides = function(_, value) history = value end
Common.RememberOpenGuide = function() end
Common.GUIDE_TAB_LIMIT = 6
Common.Tabs = { AddMenu = function(key, root)
    root:CreateButton("Switch Guide", function() end)
    root:CreateButton("Open New Guide...", function() return registered[key].controls.newGuide() end)
end }
Common.Actions = { ResolveGuide = function(query) return query end }
Common.GuideActions = { CanHideNative = function() return true end }
local menu, menuEnabled
_G.MenuUtil = { CreateContextMenu = function(_, build)
    menu, menuEnabled = {}, {}
    local root = { CreateTitle = function() end, CreateDivider = function() end }
    function root:CreateButton(label, callback)
        menu[label] = callback
        return { SetEnabled = function(_, enabled) menuEnabled[label] = enabled end }
    end
    build(nil, root)
end }
assert(loadfile("integrations/guides/source_runtime.lua"))()
assert(loadfile("integrations/guides/viewer_source.lua"))()
for _, key in ipairs({ "apr", "wowpro" }) do
    local snapshot = { id = "g1", title = "Guide 1", state = "ready", current = 4, total = 20, epoch = 1,
        steps = { { ownerStepIndex = 4, rows = { { text = "Accept quest", kind = "goal", ownerStepIndex = 4 } } } } }
    local api = { GetSnapshot = function() return snapshot end, Schedule = function() end, Subscribe = function() end,
        RunAction = function(action) lastAction = action; if action == "active" then selection = key end; return true end,
        GetRuntime = function() return { Guides = { g1 = {}, g2 = {} }, GetGuideName = function(_, id) return id end } end }
    local viewer = Common.SourceViewer.Register({ key = key, api = api, addon = key, history = key == "wowpro",
        skipHeader = key == "apr", guideSteps = key == "wowpro",
        isLoaded = function() return loaded and enabled end, frames = function() return {} end })
    for _, id in ipairs({ "blizzard", "kaliel", "ellesmere", "daylight" }) do
        host = id; viewer.Apply()
        assert(viewer.GetStatus().attached and viewer.GetStatus().host == id)
        assert(created[key].order == NS.Constants.GUIDE_PROVIDER_BY_KEY[key].order)
        created[key].controls.onMenu(f.Frame(), "LeftButton")
        assert(menu["Make Active"] and menu["Route This Step"], "Guide dropdown swallowed its action menu")
        assert(selection ~= key, "Displaying a menu changed authority")
        if key == "wowpro" then
            assert(menu["Current Guide Steps"], "WoWPro action menu has no native step list")
            menu["Current Guide Steps"]()
            assert(lastAction == "steps" and selection == nil, "Opening step list changed authority")
            created[key]:OnBlockHeaderClick(f.Frame(), "LeftButton")
            assert(menu["Current Guide Steps"] and not menu["Make Active"], "Guide title menu has no native step list")
            menu["Current Guide Steps"]()
            assert(lastAction == "steps" and selection == nil)
            menu["Open New Guide..."]()
            assert(lastAction == "chooser" and selection == nil, "Guide-title picker bypasses the shared chooser action")
            created[key].controls.onMenu(f.Frame(), "LeftButton")
            menu["Open New Guide..."]()
            assert(lastAction == "chooser" and selection == nil, "Action-menu picker bypasses the shared chooser action")
        else
            assert(not menu["Current Guide Steps"], "WoWPro-specific window leaked into APR menu")
        end
        menu["Make Active"](); assert(selection == key); selection = nil
        created[key]:LayoutContents()
    end
    if key == "wowpro" then
        local state = registered[key].controls.tabState()
        assert(state.slots[1].id == "g2" and state.slots[2].id == "g1", "Recent guides were not newest first")
    end
    loaded = false; viewer.Apply()
    assert(not viewer.GetStatus().attached, "Disabled source retained its module")
    loaded = true; viewer.Apply(); assert(viewer.GetStatus().attached)
end
print("source_viewer_controls_test: passed")
assert(loadfile("integrations/guides/viewer_actions.lua"))()
assert(loadfile("integrations/guides/viewer_quest_details.lua"))()
local detailQuest
C_QuestLog = { GetLogIndexForQuestID = function(id) return id == 42 and 1 or id == 43 and 2 end }
QuestUtil = { OpenQuestDetails = function(id) detailQuest = id end }

local s={id="zone",title="Zone",state="ready",current=1,total=53,displayCurrent=14,epoch=1,
    canChooseTask=true,pinned=false,steps={
        {title="Current",ownerStepIndex=1,taskKey="task",rows={
            {text="Use the totem",kind="goal",questID=42,objectiveKey="task:row:1",actionStepOwner="task"},
        }},
        {title="Upcoming",ownerStepIndex=2,taskKey="next",rows={{text="Turn in",questID=43,kind="goal",hideActions=true}}},
        {title="Future",ownerStepIndex=3,taskKey="future",preview=true,rows={{text="Preview objective",kind="goal",hideActions=true}}},
    }}
local checks=0
local pinKey, lines, headings = nil, {}, {}
Common.Render.AddObjective = function(block, _, row)
    local line = f.Frame()
    Common.QuestDetails.BindRow(line, block, row, "questierouter")
    lines[row.text] = line
    return line
end
Common.Controls.SetBlockHeaderText = function(block, text)
    Common.QuestDetails.Clear(block); headings[#headings + 1] = text
end
Common.Controls.UpdateHeaderActions=function()checks=checks+1 end
local api={GetSnapshot=function()return s end,Schedule=function()end,Subscribe=function()end,
    RunAction=function(action, _, _, requested, _)lastAction,pinKey=action,requested;return true end,GetRuntime=function()return {}end,
    AddTaskMenu=function()end}
api.GetRowActionState=function(d)
    return not f.combat and d.guide==s.id and d.epoch==s.epoch and d.task~="future", "Task changed"
end
api.RunRowAction=function(d) return api.RunAction("pin",d.guide,d.current,d.task,d.epoch) end
local viewer=Common.SourceViewer.Register({key="questierouter",api=api,addon="QuestieRouter",dynamicTasks=true,
    isLoaded=function()return true end,frames=function()return {}end,
    headerActions={left={tooltip="Choose Task",atlas="common-search-magnifyingglass",command="tasks",
        enabled=function(snapshot)return snapshot.canChooseTask and not InCombatLockdown()end,
        menu=function(root)root:CreateButton("Pick task",function()api.RunAction("pin")end)end},
        right={tooltip="Return to Automatic Order",atlas="common-icon-rotateleft",action="automatic",
            enabled=function(snapshot)return snapshot.pinned and not InCombatLockdown()end}}})
for _,id in ipairs({"blizzard","kaliel","ellesmere","daylight"})do
    host=id;viewer.Apply()
    local c=created.questierouter.controls
    assert(not c.hideNavigation and c.previousAtlas=="common-search-magnifyingglass")
    assert(c.nextAtlas=="common-icon-rotateleft" and c.previousEnabled(s) and not c.nextEnabled(s))
    assert(not registered.questierouter.controls.getActionState("automatic"),"Unpinned task advertised Return to Automatic Order")
    assert(registered.questierouter.controls.getActionState("tasks"))
    lastAction=nil;c.onPrevious(f.Frame())
    assert(menu["Pick task"] and lastAction==nil,"Opening task menu changed navigation")
    menu["Pick task"]();assert(lastAction=="pin")
    lastAction=nil;c.onNext(f.Frame());assert(lastAction==nil,"Disabled automatic action executed")
    s.pinned=true;c.onNext(f.Frame());assert(lastAction=="automatic")
    s.pinned=false
    headings = {}
    created.questierouter:LayoutContents()
    assert(table.concat(headings, "|") == "Zone|Current|Upcoming|Preview: Future")
    local taskBlock=created.questierouter.blocks.AwpQuestieRouterStep2
    lastAction=nil
    created.questierouter:OnBlockHeaderClick(taskBlock,"LeftButton")
    assert(lastAction==nil and menuEnabled["Make This Task Active"])
    menu["Make This Task Active"]();assert(lastAction=="pin" and pinKey=="next","Heading selected the current task instead of its owner")
    local objectiveLine = lines["Use the totem"]
    lastAction,pinKey=nil,nil
    objectiveLine:GetScript("OnMouseUp")(objectiveLine, "LeftButton")
    assert(lastAction==nil and menuEnabled["Make This Task Active"], "Opening a task menu changed selection")
    menu["Make This Task Active"]()
    assert(lastAction=="pin" and pinKey=="task", "Task menu did not select the owning native task")
    local upcoming = lines["Turn in"]
    upcoming:GetScript("OnMouseUp")(upcoming, "LeftButton")
    menu["Make This Task Active"]()
    assert(lastAction=="pin" and pinKey=="next")
    lastAction=nil
    local preview=lines["Preview objective"]
    preview:GetScript("OnMouseUp")(preview,"LeftButton")
    assert(not menuEnabled["Make This Task Active"])
    menu["Make This Task Active"]();assert(lastAction==nil,"Preview issued native commands")
    upcoming:GetScript("OnMouseUp")(upcoming,"LeftButton")
    local stale=menu["Make This Task Active"]
    s.epoch=s.epoch+1;stale();assert(lastAction==nil,"Stale task menu selected another task")
end
local qrModule = created.questierouter
host="blizzard"; qrModule:LayoutContents()
local questLine=lines["Turn in"]
questLine:GetScript("OnMouseUp")(questLine,"RightButton")
assert(menu["Open Quest Details"] and menuEnabled["Open Quest Details"], "Right-click omitted quest details")
menu["Open Quest Details"](); assert(detailQuest==43, "Upcoming row opened another task's quest")
local detailMenu=menu["Open Quest Details"]
s.epoch=s.epoch+1;detailQuest=nil;detailMenu();assert(detailQuest==nil,"Stale quest menu survived a source epoch change")
qrModule:LayoutContents()
function qrModule:LayoutBlock() return #headings < 3 end
settings.hideGuideTitle = true
headings, lines = {}, {}
qrModule:LayoutContents()
assert(table.concat(headings, "|") == "Current|Upcoming|Preview: Future")
settings.hideGuideTitle = false
headings, lines = {}, {}
qrModule:LayoutContents()
assert(table.concat(headings, "|") == "Zone|Current|Upcoming" and not lines["Preview objective"])
f.combat=true;lastAction=nil
created.questierouter.controls.onPrevious(f.Frame())
assert(lastAction==nil)
f.Fire("PLAYER_REGEN_DISABLED");assert(checks>0,"Header action state did not refresh on combat entry")
f.combat=false
print("Shared source header actions: menu/dispatch, native defaults, combat events and all hosts passed")

local help
NS.Msg = function(message) help = message end
assert(loadfile("integrations/guides/viewer_actions.lua"))()
Common.Actions.Handle("questierouter", "help")
assert(help:find("tasks | automatic", 1, true) and not help:find("next", 1, true), "QuestieRouter help advertised linear controls")
Common.Actions.Handle("wowpro", "help")
assert(help:find(" | steps | ", 1, true), "WoWPro help omitted the current guide steps")
Common.Actions.Handle("apr", "help")
assert(help:find("picker", 1, true) and not help:find("switch", 1, true), "APR help advertised an unsupported guide switcher")
