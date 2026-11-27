local f = assert(loadfile("tests/daylight_fixture.lua"))()
assert(loadfile("core/core.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/source_runtime.lua"))()
local NS = AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
Common.CreateNativeFrameCloak = function() return { Refresh = function() end } end
NS.GetGuideActionSettings = function() return { types = {} } end
NS.GetGuideTrackerViewerProviderSettings = function() return {} end
assert(loadfile("integrations/guides/guide_actions.lua"))()
local A = Common.GuideActions
local function Button(attributes)
    local button = { attributes = attributes, scripts = {}, shown = true }
    function button:GetAttribute(key) return self.attributes[key] end
    function button:GetScript(key) return self.scripts[key] end
    function button:IsShown() return self.shown end
    function button:GetNormalTexture() return nil end
    return button
end
local function API(native, snapshot)
    return { GetRuntime = function() return native end, GetSnapshot = function() return snapshot end, Subscribe = function() end }
end
local function Art(file, coords)
    return {
        GetTexture = function() return file end,
        GetTexCoord = function() return unpack(coords or {}) end,
    }
end
_G.C_Item = { GetItemNameByID = function() return "Item" end, GetItemIconByID = function() return 123 end }
local spellLookups = 0
_G.C_Spell = { GetSpellInfo = function() spellLookups = spellLookups + 1; return { name = "Spell", iconID = 234 } end }
local zButton = Button({ itemid = 42, macrotext1 = "#showtooltip Item\n/use item:42", type = "macro" })
_G.ZGV = { CurrentGuide = { title = "z" }, CurrentStepNum = 5, ActionBar = { Buttons = { zButton } } }
assert(loadfile("integrations/guides/zygor/actions.lua"))()
local model = A.providers.zygor.collect(); A.models.zygor = model
assert(model.actions[1].kind == "item" and model.actions[1].payload == 42 and model.actions[1].category == "items")
zButton.attributes["shift-macrotext1"] = "/native alternate"
model = A.providers.zygor.collect()
assert(model.actions[1].kind == "native", "Zygor alternate procedure was discarded")
assert(model.actions[1].tooltipKind == "item" and model.actions[1].tooltipID == 42,
    "A native macro lost its explicit tooltip identity")
local zTalk = Button({ type = "macro", macrotext1 = "/cleartarget\n/target Mull Thunderhorn\n/tm 1" })
local zOverlay = { button = zTalk, icon = Art("zygor-sheet", { .1, .2, .1, .4, .3, .2, .3, .4 }),
    tooltip = "Talk to Mull Thunderhorn" }
local zActive = { [zOverlay] = true }
local talkGoal = { action = "talk", num = 2, npcid = 2981, npc = "Mull Thunderhorn" }
ZGV.CurrentStep = { goals = { { action = "accept", num = 1, npc = "Mull Thunderhorn" }, talkGoal } }
ZGV.L = { ["stepgoal_talk to"] = "Talk to %s" }
ZGV.Localizers = { GetTranslatedNPC = function(_, _, name) return name end }
ZGV.IconSets = { ActionBarIcons = { file = "zygor-sheet" } }
ZGV.ActionBar.Buttons = { zTalk }
ZGV.ActionBar.ButtonOverlayPool = { EnumerateActive = function() return next, zActive end }
model = A.providers.zygor.collect(); A.models.zygor = model
local zAction = model.actions[1]
assert(zAction.kind == "native" and zAction.label == "Talk to Mull Thunderhorn")
assert(zAction.framedIcon and zAction.owner == A.providers.zygor.goalOwner(talkGoal, 5)
    and zAction.category == "friendly", "Existing Zygor NPC action did not retain its frame or specific goal")
assert(zAction.icon == "zygor-sheet" and zAction.iconCoords[3] == .1 and zAction.iconCoords[8] == .4)
assert(A.providers.zygor.collect() == model, "Unchanged Zygor artwork rebuilt its action")
zOverlay.icon = Art("zygor-sheet", { .3, .2, .3, .4, .5, .2, .5, .4 })
local zChanged = A.providers.zygor.collect()
assert(zChanged ~= model and zChanged.actions[1].iconCoords[1] == .3 and zAction.iconCoords[1] == .1,
    "Pooled Zygor artwork changed the prepared action or missed a crop-only update")
ZGV.CurrentStep.goals[3] = { action = "talk", num = 3, npcid = 2981, npc = "Mull Thunderhorn" }
assert(A.providers.zygor.collect().actions[1].owner == 5, "An ambiguous Zygor target was assigned to an arbitrary goal")
zActive[zOverlay] = nil
local released = A.providers.zygor.collect().actions[1]
assert(not released.icon and not released.framedIcon, "Released Zygor artwork was carried into a new observation")
local dItem = Button({ ["type*"] = "item", ["item*"] = "item:42", ["shift-type*"] = "dugisHandler" })
local dTarget = Button({ type = "macro", macrotext = "/native target procedure" })
_G.DugisGuideViewer = { Modules = { Target = { Frame = dTarget, lastSetQuestIndex = 5 } } }
_G.DugisItemButton = dItem; _G.DugisGuideUser = { CurrentQuestIndex = 5 }; _G.CurrentTitle = "d"
NS.IsDugiLoaded = function() return true end
NS.Internal.DugiPresentation = { ResolveStep = function() return { action = "kill" } end }
assert(loadfile("integrations/guides/dugi/actions.lua"))()
model = A.providers.dugi.collect()
assert(model.actions[1].category == "items" and model.actions[1].kind == "native", "Dugi wildcard/modifier binding was misclassified")
assert(model.actions[1].tooltipKind == "item" and model.actions[1].tooltipID == 42)
assert(model.actions[2].category == "hostile" and model.actions[2].owner == 5)
local rSpell = Button({ type1 = "spell", spell = "Spell" }); rSpell.itemId, rSpell.spell, rSpell.name = 17, true, "Spell"
local rTarget = Button({ type = "macro", macrotext = "/cleartarget\n/targetexact Person" }); rTarget.targetData = { name = "Person" }
local rEnemy = Button({ type = "macro", macrotext = "/cleartarget\n/targetexact Enemy\n/tm ~8" }); rEnemy.targetData = { name = "Enemy" }
rTarget.icon = Art(345)
local rxp = { currentGuide = { group = "g", name = "r" }, GetGuideProgress = function() return 5 end,
    activeItemFrame = { buttonList = { rSpell } }, targeting = { activeTargetFrame = { friendlyTargetButtons = { rTarget }, enemyTargetButtons = { rEnemy } } } }
NS.Internal.RXPProvider = API(rxp, { id = "g||r", current = 5, state = "ready" })
NS.Internal.RXPPresentation = { Call = function(object, method) return object[method]() end }
assert(loadfile("integrations/guides/rxp/actions.lua"))()
model = A.providers.rxp.collect()
local before = spellLookups
A.models.rxp = model
local reused = A.providers.rxp.collect()
assert(reused == model and spellLookups == before, "Unchanged native observations repeated spell metadata lookups")
assert(model.actions[1].kind == "spell" and model.actions[1].payload == 17)
assert(model.actions[1].tooltipKind == "spell" and model.actions[1].tooltipID == 17)
assert(model.actions[2].kind == "target" and model.actions[2].payload == "Person")
assert(model.actions[2].icon == 345)
assert(model.actions[3].kind == "native" and model.actions[3].category == "hostile" and model.actions[3].label == "Target Enemy",
    "RXP marking was replaced by a plain target or lost its target name")
rTarget.IsVisible = function() return false end
assert(#A.providers.rxp.collect().actions == 2, "RXP exposed an individually shown button inside a hidden native frame")
local aItem = Button({ type1 = "item", item = "item:42" }); aItem.attribute = "item"
local aTarget = Button({ type1 = "macro", macrotext = "/native APR targeting" })
local questHost = { key = "123-1" }; aTarget.questHost = questHost
local apr = { ActiveRoute = "a", PlayerID = "player", currentStep = { questsList = { ["123-1"] = { IconButton = aItem } } },
    RaidIconButtons = { buttons = { aTarget } } }
_G.APRData = { player = { a = 5 } }
NS.Internal.APRProvider = API(apr, { state = "ready", current = 5 })
assert(loadfile("integrations/guides/apr/actions.lua"))()
model = A.providers.apr.collect()
assert(#model.actions == 2 and model.actions[1].kind == "item" and model.actions[1].owner == "123-1")
assert(model.actions[2].native == aTarget and model.actions[2].owner == "123-1", "APR's current target rail was missed")
local wItem = Button({ type1 = "item", item1 = "item:42" })
local wTrash = Button({ type1 = "click1" }); wTrash.scripts.OnClick = function() end
local wOverlay = Button({ type1 = "click1" })
local wPet = Button({ type = "SwitchPet" }); wPet.SwitchPet = function() end
local wTargetArt = Button({})
local wTarget = Button({ type = "macro", macrotext = "/native targeting" })
local wJumpArt = Button({ type = "jump" }); wJumpArt.scripts.OnClick = function() end
local wJump = Button({ type = "click" })
local wow = { ActiveStep = 5, rows = { { index = 5, itembuttonSecured = wItem },
    { index = 6, itembutton = wTrash, itembuttonSecured = wOverlay }, { index = 7, itembuttonSecured = wPet },
    { index = 8, targetbutton = wTargetArt, targetbuttonSecured = wTarget, targeticon = Art(456),
        jumpbutton = wJumpArt, jumpbuttonSecured = wJump, jumpicon = Art(457) } }, use = { [6] = "*13" } }
_G.WoWProDB = { char = { currentguide = "w" } }
NS.Internal.WoWProProvider = API(wow, { state = "ready", id = "w", current = 5 })
assert(loadfile("integrations/guides/wowpro/actions.lua"))()
model = A.providers.wowpro.collect()
assert(model.actions[1].kind == "item" and model.actions[1].payload == 42)
assert(model.actions[2].native == wTrash and model.actions[2].category == "cleanup", "Cleanup bypassed native confirmation callback")
assert(model.actions[3].category == "pets" and model.actions[3].kind == "native")
assert(model.actions[4].native == wTarget and model.actions[4].icon == 456, "WoWPro lost the visible artwork of the target overlay")
assert(model.actions[5].native == wJumpArt and model.actions[5].icon == 457, "WoWPro guide jump skipped the visible callback")
local pItem = Button({ type = "item", item = "item:42" })
local pTarget = Button({ type = "macro", macrotext = "/native mixed targets" })
local pRow = Button({ type = "macro", macrotext = "/native row targeting" }); pRow.applied, pRow.kind = "Mob", "mob"
pRow.npc, pRow.face, pRow.Mark = 901, "model", Art("polestar-crosshair")
pRow.Model = { drawn = 901, GetDisplayInfo = function() return 902 end }
local polestar = { Engine = { GetGuide = function() return { id = "p" } end, GetStepIndex = function() return 5 end },
    QoL = { Buttons = { item = pItem, target = pTarget, rows = { pRow } } } }
NS.Internal.PolestarProvider = API(polestar, { state = "ready", id = "p", current = 4, rawCurrent = 5 })
NS.Internal.PolestarPresentation = { Call = function(object, method) return object[method]() end }
assert(loadfile("integrations/guides/polestar/actions.lua"))()
model = A.providers.polestar.collect()
assert(model.step == 5 and model.actions[2].category == "hostile" and model.actions[3].native == pRow)
assert(model.actions[3].portrait == 902 and model.actions[3].icon == "polestar-crosshair")
pRow.Model.drawn = 903
assert(not A.providers.polestar.collect().actions[3].portrait, "Polestar displayed a portrait belonging to a previous target")
local qTarget = Button({ type1 = "macro", macrotext1 = "/native QR target" })
qTarget.targetName, qTarget.entry, qTarget.icon = "Person", { kind = "friendly" }, Art(567)
local function QRItem(id)
    local button = Button({ type1 = "item", item1 = "item:" .. id })
    button.itemId = id
    return button
end
local qSourceItem, qRequiredItem, qNextItem, qUnassociatedItem = QRItem(42), QRItem(43), QRItem(44), QRItem(45)
local qItems, qTargets = f.Frame(), f.Frame()
qItems.buttons, qTargets.buttons = { qSourceItem, qRequiredItem, qNextItem, qUnassociatedItem }, { qTarget }
local qTask = { kind = "objective", questIds = { 10, 20 } }
local qNextTask = { kind = "objective", questIds = { 30 } }
local qPlan = { guide = { key = "q" }, steps = { qTask, qNextTask } }
local queryFailed = false
local questFields = {
    [10] = { sourceItemId = 42 },
    [20] = { requiredSourceItems = { 43 } },
    [30] = { requiredSourceItems = 44 },
}
local qr = { ActiveFrames = { items = qItems, targets = qTargets }, Planner = { plan = qPlan },
    Bridge = { QuestieDB = { QueryQuestSingle = function(questID, field)
        if queryFailed then error("QuestieDB is not ready") end
        return questFields[questID][field]
    end } } }
assert(loadfile("integrations/guides/questierouter/questierouter_presentation.lua"))()
local taskKey = NS.Internal.QuestieRouterPresentation.TaskKey
local qSnapshot = { state = "ready", id = "q", current = 5, taskKey = taskKey(qTask), taskQuestIDs = qTask.questIds }
NS.Internal.QuestieRouterProvider = API(qr, qSnapshot)
NS.Internal.QuestieRouterProvider.TaskKey = taskKey
assert(loadfile("integrations/guides/questierouter/actions.lua"))()
local collectQR = A.providers.questierouter.collect
model = collectQR()
assert(model.step == 5 and model.actions[5].owner == qSnapshot.taskKey and model.actions[5].icon == 567,
    "QuestieRouter's target owner did not match its Viewer task row")
assert(model.actions[1].kind == "item" and model.actions[1].payload == 42 and model.actions[1].owner == qSnapshot.taskKey,
    "QuestieRouter's source item did not retain its item binding and task owner")
assert(model.actions[2].owner == qSnapshot.taskKey, "A required item for another quest in the task was omitted")
assert(not model.actions[3].owner and not model.actions[4].owner, "Unrelated or unassociated items were assigned to the task")
A.models.questierouter = model
assert(collectQR() == model, "Unchanged QuestieRouter items rebuilt the action model")

qr.ActiveFrames.queued = true
assert(collectQR().actions[1].owner == qSnapshot.taskKey, "A queued redraw for the same task hid its item")
qPlan.steps[1] = qNextTask
model = collectQR()
assert(not model.actions[1].owner and not model.actions[3].owner and not model.actions[5].owner,
    "Old snapshot claimed the native action buttons after the plan changed")
qSnapshot.current, qSnapshot.taskKey, qSnapshot.taskQuestIDs = 6, taskKey(qNextTask), qNextTask.questIds
qr.ActiveFrames.queued, qr.ActiveFrames.pending = nil, true
model = collectQR()
assert(not model.actions[3].owner and not model.actions[5].owner, "A task switch reused buttons before the native redraw")
qr.ActiveFrames.pending = nil
model = collectQR()
assert(not model.actions[1].owner and model.actions[3].owner == qSnapshot.taskKey,
    "The new task lost its scalar required item or inherited the previous quest item")

queryFailed = true
model = collectQR()
assert(#model.actions == 5 and not model.actions[3].owner, "Unavailable quest data lost panel actions or retained an old match")
queryFailed = false
assert(collectQR().actions[3].owner == qSnapshot.taskKey, "Recovered quest data did not restore the item owner")
f.flavor = "retail"; A.providers.polestar = nil
assert(loadfile("integrations/guides/polestar/actions.lua"))()
assert(not A.providers.polestar, "Forever-only actions registered on Retail")
print("guide_action_collectors_test: passed")
