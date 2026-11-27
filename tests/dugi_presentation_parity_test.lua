local replaceMethod = dofile("tests/replace_method.lua")
_G.InCombatLockdown = function() return false end
local function expect(value, message) if not value then error(message, 2) end end
local versions = { { flavor = "retail", version = "12.60" }, { flavor = "forever", version = "1.085" } }
for _, client in ipairs(versions) do
    local itemNames = { [100] = "Hieron's Journal", [101] = "Revealing Lens" }
    local providers = {}
    local final, reads, sourceReads = nil, 0, 0
    local NS = { Constants = {}, Internal = {}, State = {} }
    _G.AzerothWaypointNS = NS
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("core/map_coordinates.lua"))()
assert(loadfile("core/util.lua"))()
assert(loadfile("core/instance_entrances.lua"))()
    assert(loadfile("core/quest_data.lua"))()
assert(loadfile("core/quest_text.lua"))()
    NS.GetDB = function() return {} end
    NS.RegisterGuideTargetProvider = function(key, value) providers[key] = value end
    NS.GetGuideTrackerViewerProviderSettings = function() return { enabled = true } end
    _G.C_Item = { GetItemNameByID = function(id) return itemNames[id] end }
    _G.C_QuestLog = {
        GetTitleForQuestID = function(id) return id == 900 and "Truth of the Past" or nil end,
        GetQuestObjectives = function() return { { text = "Rescue the prisoners" } } end,
    }
    _G.CurrentTitle = "Parity " .. client.flavor
    _G.DugisGuideUser = { CurrentQuestIndex = 1 }
    local dugi = { actions = {}, quests1 = {}, quests1L = {}, quests2 = {}, tags = {}, qid = {},
        states = {}, values = {}, descriptions = {}, guides = {}, GuideMapID = 2405 }
    _G.DugisGuideViewer = dugi
    dugi.ReturnTag = function(self, tag, index)
        local values = self.values[index] or {}
        local value = values[tag]
        if type(value) == "table" then return unpack(value) end
        return value
    end
    dugi.GetQuestState = function(self, index) return self.states[index] or "U" end
    dugi.GetQuestDescription = function(self, index) reads = reads + 1; return self.descriptions[index] end
    dugi.GetQuestStepText = function(self, index) return self.quests2[index] end
    dugi.GetLocalizedNPC = function(self, id)
        return id == 200 and "Leona Darkstrider" or id == 256285 and "Allari the Souleater" or nil
    end
    -- Dugi calls TranslateText before assigning tags/quests2, removing the
    -- author's location braces even on enUS. Its parsed rows are not raw rows.
    dugi.TranslateText = function(self, text) return (text:gsub("{(.-)}", "%1")) end
    dugi.getCoords = function(self, index)
        local coords = {}
        for x, y in (self.quests2[index] or ""):gmatch("%(([%d.]+),%s*([%d.]+)%)") do
            coords[#coords + 1] = { tonumber(x), tonumber(y) }
        end
        return coords
    end
    dugi.DugisArrow = { getFinalWaypoint = function() return final end }
    assert(loadfile("integrations/guides/presentation.lua"))()
    assert(loadfile("integrations/guides/dugi/dugi_presentation.lua"))()
    assert(loadfile("core/service_search.lua"))()
    assert(loadfile("integrations/guides/dugi/dugi_provider.lua"))()
    local adapter = assert(providers.dugi, "Dugi provider missing")
    local P = NS.Internal.DugiPresentation
    local authoredRows = {}
    local function step(index, action, title, note, values, description, questID)
        authoredRows[index] = action .. " " .. title .. " |N|" .. note .. "|"
        local source = table.concat(authoredRows, "\n")
        dugi.guides[_G.CurrentTitle] = function() sourceReads = sourceReads + 1; return source end
        dugi.actions[index], dugi.quests1[index], dugi.quests1L[index] = action, title, title
        dugi.quests2[index] = dugi:TranslateText(note)
        dugi.tags[index] = "|N|" .. dugi:TranslateText(note) .. "|"
        dugi.values[index], dugi.descriptions[index], dugi.qid[index] = values or {}, description, questID
        dugi.values[index].Z = dugi.values[index].Z or 2405
        P.Invalidate()
        return P.ResolveStep(dugi, index)
    end
    local collect = step(1, "N", "(item:100)", "Collect (item:100) in {The Howling Ridge} (51.22, 72.88)",
        { T = true }, "Collect [Hieron's Journal]", 901)
    expect(collect.title == "Collect [Hieron's Journal]" and collect.subtext == nil and #collect.rows == 1,
        "Reported Journal repetition survived on " .. client.flavor)
    expect(collect.semantic == "collect" and collect.questID == 901, "Collect action lost its quest association")
    local before = reads
    expect(P.ResolveStep(dugi, 1) == collect and reads == before, "Unchanged presentation was rebuilt")
    final = { map = 2405, x = 51.22, y = 72.88, guideIndex = 1, questId = 999,
        desc = "Stale formatted waypoint text", isRouteDestination = true }
    local target = NS.Internal.DugiProvider.ExtractTarget()
    expect(target.title == collect.title and target.subtext == nil and target.semanticQuestID == 901,
        "Waypoint description or foreign quest ID bypassed resolved presentation")
    expect(math.abs(target.x - 0.5122) < 0.000001 and math.abs(target.y - 0.7288) < 0.000001,
        "Exact destination changed during presentation resolution")
    local count = step(2, "N", "(item:100)", "Collect 12 (item:100) in {The Howling Ridge} (51.22, 72.88)",
        { L = { 100, 12 } }, "Collect [Hieron's Journal]", 901)
    expect(count.title == "Collect 12 [Hieron's Journal]" and not count.subtext, "Quantity was lost or repeated")
    local mixed = step(3, "N", "(item:100)", "Kill (npc:200) and collect (item:100) in {The Howling Ridge}",
        { NPC = 200, T = true }, "Collect [Hieron's Journal]", 901)
    expect(mixed.semantic == "collect" and mixed.subtext:find("Kill Leona", 1, true), "Enemy-drop instructions were lost")
    local accept = step(4, "A", "Truth of the Past", "(npc:200) in {The Howling Ridge} (51.22, 72.88)",
        { NPC = 200 }, "Accept 'Truth of the Past' (Leona Darkstrider)", 900)
    expect(accept.title == "Accept 'Truth of the Past'" and accept.subtext == "Talk to Leona Darkstrider",
        "Accept quest/context separation regressed")
    local allari = step(5, "T", "Truth of the Past",
        "(npc:256285) in {Kil'jaeden's Terrace} (52.88, 14.19)", { NPC = 256285 },
        "Turn in 'Truth of the Past' (Allari the Souleater)", 900)
    expect(allari.facts.location == "Kil'jaeden's Terrace" and allari.subtext == "Talk to Allari the Souleater",
        "Reported Allari location remained in parsed, brace-free Dugi text")
    local sourceBefore = sourceReads
    P.Invalidate()
    P.ResolveStep(dugi, 5)
    expect(sourceReads == sourceBefore, "A presentation refresh rescanned unchanged authored guide data")
    local objectives = C_QuestLog.GetQuestObjectives
    C_QuestLog.GetQuestObjectives = function() return { { text = "0/1 Vision beheld" } } end
    local vision = step(5, "N", "Vision beheld",
        "Watch the scene on the platform in {Kil'jaeden's Terrace} (52.74, 14.41)", { QIDP = 1, Z = 882 }, nil, 92507)
    expect(vision.title == "0/1 Vision beheld" and vision.subtext == "Watch the scene on the platform"
        and vision.rows[2].text == vision.subtext and vision.snapshot.pinpointSubtext == vision.subtext,
        "Reported Vision step retained its location suffix or lost the platform instruction")
    expect(vision.fullNote:find("Kil'jaeden's Terrace", 1, true), "Authored location disappeared from the full-note tooltip")
    local visionTarget = NS.Internal.DugiProvider.ExtractTarget({ stepIndex = 5, explicit = true })
    expect(visionTarget.title == vision.title and visionTarget.subtext == vision.subtext
        and visionTarget.mapID == 882 and visionTarget.semanticQuestID == 92507
        and math.abs(visionTarget.x - 0.5274) < 0.000001,
        "Concise Vision presentation changed destination/quest ownership or did not reach the published target")
    C_QuestLog.GetQuestObjectives = objectives
    local object = step(5, "N", "Ancient Lockbox",
        "Click Ancient Lockbox on the upper shelf in {Kil'jaeden's Terrace} (52.74, 14.41)", { OBJ = 300 })
    expect(object.title == "Click Ancient Lockbox" and object.subtext == "On the upper shelf",
        "Object detail retained its region or lost the shelf instruction")
    local objectRepeat = step(5, "N", "Ancient Lockbox",
        "Click Ancient Lockbox in {Kil'jaeden's Terrace} (52.74, 14.41)", { OBJ = 300 })
    expect(not objectRepeat.subtext and #objectRepeat.rows == 1, "Object action/location repetition survived")
    local objectTitle = step(5, "N", "Ancient Lockbox in Kil'jaeden's Terrace",
        "Click Ancient Lockbox in {Kil'jaeden's Terrace} (52.74, 14.41)", {})
    expect(objectTitle.title == "Click Ancient Lockbox" and not objectTitle.subtext,
        "The known location survived in an object title")
    local itemDetail = step(5, "N", "(item:100)",
        "Kill (npc:200) and collect (item:100) in {The Howling Ridge}", { NPC = 200, T = true }, "Collect [Hieron's Journal]")
    expect(itemDetail.subtext == "Kill Leona Darkstrider and collect [Hieron's Journal]",
        "Loot detail retained its location or lost the enemy/drop instruction")
    local unknownLocation = step(5, "N", "Vision beheld", "Watch the scene on the platform in an unfamiliar location.", {})
    expect(unknownLocation.subtext == "Watch the scene on the platform in an unfamiliar location",
        "An unverified in-phrase was removed")
    local conditional = step(5, "N", "Wait for the guard",
        "Remain in {Kil'jaeden's Terrace} until the guard arrives.", {})
    expect(conditional.subtext == "Remain in Kil'jaeden's Terrace until the guard arrives",
        "Location trimming deleted a condition after the location")
    local localized = step(5, "T", "Une quÃƒÂªte (partie deux)", "Choose the second dialogue option (upper floor).",
        {}, "Rendre 'Une quÃƒÂªte (partie deux)'", 902)
    expect(localized.title == "Rendre 'Une quÃƒÂªte (partie deux)'" and localized.subtext:find("(upper floor)", 1, true),
        "Localized action or meaningful parentheses were lost")
    local use = step(6, "N", "(item:101)", "Use (item:101) to reveal the hidden door.", { U = 101 }, "[Revealing Lens]", 901)
    expect(use.semantic == "use" and use.title == "Use [Revealing Lens]" and use.subtext == "To reveal the hidden door",
        "Item-use procedure was not separated from its action")
    local talk = step(7, "N", "(npc:200)", "Speak to (npc:200) in {The Howling Ridge}", { NPC = 200, S = true })
    expect(talk.title == "Talk to Leona Darkstrider" and not talk.subtext, "Talk alias repeated its action/location")
    local click = step(8, "N", "Ancient Lockbox", "Click Ancient Lockbox (upper shelf).", { OBJ = 300 })
    expect(click.semantic == "click" and click.subtext == "(upper shelf)", "Click instructions were lost")
    local objective = step(9, "C", "Missing prisoners", "Rescue the prisoners", { QIDP = 1 }, "Complete 'Missing prisoners'", 903)
    expect(objective.title == "Rescue the prisoners" and not objective.subtext, "Objective index was ignored")
    for _, entry in ipairs({
        { "K", "kill", "Enemy", "Kill Enemy" }, { "B", "buy", "Supplies", "Buy Supplies" },
        { "R", "goto", "Village", "Travel to Village" }, { "F", "fly", "Village", "Fly to Village" },
        { "H", "hearth", "Home", "Hearth to Home" }, { "h", "home", "Home", "Set Hearth at Home" },
        { "f", "fpath", "Village", "Get flight path Village" },
    }) do
        local result = step(10, entry[1], entry[3], entry[4], {}, entry[4], 901)
        expect(result.semantic == entry[2] and not result.subtext, "Action matrix failed for " .. entry[1])
        if entry[1] == "R" or entry[1] == "F" then
            expect(result.semanticKind == "travel", "Quest association overrode explicit travel")
        end
    end
    local boat = step(11, "R", "Village", "Take the boat from the eastern dock.", {}, "Travel to Village", 901)
    expect(boat.semanticKind == "travel" and boat.subtext:find("eastern dock", 1, true), "Transport boarding instruction was lost")
    local portal = step(11, "R", "The Howling Ridge",
        "Use the portal to travel to {The Howling Ridge} (53.24, 13.44)", { Z = 882 }, "Travel to The Howling Ridge", 92507)
    expect(portal.title == "Travel to The Howling Ridge" and portal.subtext == "Use the portal"
        and portal.rows[2].text == "Use the portal" and portal.snapshot.pinpointSubtext == "Use the portal"
        and portal.semanticTravelType == "portal", "Reported portal note repeated its destination or lost its travel method")
    local portalTarget = NS.Internal.DugiProvider.ExtractTarget({ stepIndex = 11, explicit = true })
    expect(portalTarget.subtext == "Use the portal" and portalTarget.mapID == 882
        and math.abs(portalTarget.x - 0.5324) < 0.000001 and math.abs(portalTarget.y - 0.1344) < 0.000001,
        "Travel wording cleanup changed the portal's source coordinates")
    local namedPortal = step(11, "R", "Village", "Click the Illidari Gateway to travel to {Village}.", {})
    expect(namedPortal.subtext == "Click the Illidari Gateway", "Named travel interaction was lost")
    local boatDestination = step(11, "R", "Village", "Take the boat from the eastern dock to {Village}.", {})
    expect(boatDestination.subtext == "Take the boat from the eastern dock", "Boarding location was removed with the repeated destination")
    local alternativeTravel = step(11, "R", "Village", "Use the portal or your hearthstone to travel to {Village}.", {})
    expect(alternativeTravel.subtext == "Use the portal or your hearthstone", "Travel alternatives were removed")
    local conditionalTravel = step(11, "R", "Village", "Use the portal to travel to {Village} after speaking to the guard.", {})
    expect(conditionalTravel.subtext == "Use the portal to travel to Village after speaking to the guard",
        "Travel cleanup removed a condition")
    local otherDestination = step(11, "R", "Village", "Use the portal to travel to {Another Village}.", {})
    expect(otherDestination.subtext == "Use the portal to travel to Another Village", "An unrelated destination was removed")
    local waiting = step(11, "R", "Village", "Wait for the guard to travel to {Village}.", {})
    expect(waiting.subtext == "Wait for the guard to travel to Village", "An instruction about someone else's travel was truncated")
    for number = 1, 3 do
        local notes = {}
        for i = 1, number do notes[i] = "Instruction " .. i end
        local result = step(12, "N", "Read the instructions", table.concat(notes, "\n\n"), {})
        if number < 3 then expect(#result.rows == number + 1, "One/two tips were not inline")
        else expect(#result.rows == 1 and #result.rows[1].tips == 3 and result.rows[1].text:find("(3 tips)", 1, true), "Three tips were not grouped") end
    end
    local wrap = step(13, "N", "Read the instructions", "A long instruction\ncontinues on another authored line.", {})
    expect(#wrap.rows == 2, "A line break incorrectly became multiple paragraphs")
    local location = step(14, "N", "Read the instructions", "In {The Howling Ridge} (51.22, 72.88)", {})
    expect(not location.subtext, "Location-only detail was not omitted")
    -- Color/link markup inside |N| must not truncate its raw location metadata.
    local coloredNote = "Collect |cffffffff[Hieron's Journal]|r in {The Howling Ridge} (51.22, 72.88)"
    step(14, "N", "(item:100)", coloredNote, { T = true }, "Collect [Hieron's Journal]")
    dugi.quests2[14] = "Collect [Hieron's Journal] in The Howling Ridge"
    local colored = P.ResolveStep(dugi, 14)
    expect(colored.facts.location == "The Howling Ridge" and not colored.subtext,
        "Inline markup truncated location metadata and leaked a location-only second line")
    local translate = dugi.TranslateText
    replaceMethod(dugi, "TranslateText", function(self, text)
        return (translate(self, text):gsub("The Howling Ridge", "La Crete Hurlante"))
    end)
    local translated = step(14, "N", "(item:100)",
        "Collect (item:100) in {The Howling Ridge} (51.22, 72.88)", { T = true }, "Collect [Hieron's Journal]")
    expect(translated.facts.location == "La Crete Hurlante" and not translated.subtext,
        "Translated authored location did not match the parsed note")
    dugi.TranslateText = translate
    local readable = step(14, "N", "Read the instructions", "Remain in {The Howling Ridge} until the guard arrives.", {})
    expect(readable.subtext == "Remain in The Howling Ridge until the guard arrives",
        "An instruction mentioning a known location was incorrectly removed")
    local unavailableFactory = dugi.guides[_G.CurrentTitle]
    dugi.guides[_G.CurrentTitle] = nil
    P.Invalidate()
    expect(P.ResolveStep(dugi, 14).subtext == readable.subtext, "Missing authored source discarded uncertain instructions")
    dugi.guides[_G.CurrentTitle] = unavailableFactory
    _G.C_Spell = { GetSpellName = function() return "Disguise" end }
    _G.C_Map = { GetMapInfo = function() return { name = "The Howling Ridge" } end }
    local spell = step(14, "N", "(spell:123)", "Use (spell:123) at the upper door.", {})
    expect(spell.semantic == "use" and spell.title == "Use Disguise"
        and spell.subtext == "At the upper door", "Spell tokens lost their use action or procedure")
    local mapNote = step(14, "N", "(item:100)", "In (map:2405)", { T = true }, "Collect [Hieron's Journal]")
    expect(not mapNote.subtext, "Resolved map-token location leaked a location-only detail")
    local unknown = step(15, "N", "(item:777)", "Use the item after speaking to the guard.", { U = 777 })
    expect(unknown.title == "Use the item after speaking to the guard." and not unknown.subtext,
        "Missing item data invented a subject or lost its authored instructions")
    itemNames[777] = "Newly Loaded Item"
    P.Invalidate()
    expect(P.ResolveStep(dugi, 15).title == "Use [Newly Loaded Item]", "Data-ready invalidation did not refresh item identity")

    -- Relevant native waypoint ownership must carry its own text and quest ID.
    dugi.IterateRelevantSteps = function(_, previous)
        if not previous then return 1 elseif previous == 1 then return 4 end
    end
    final = { map = 2405, x = 60, y = 70, guideIndex = 4, questId = 900, isRouteDestination = true }
    target = NS.Internal.DugiProvider.ExtractTarget()
    expect(target.dugiStepIndex == 4 and target.title == accept.title and target.semanticQuestID == 900,
        "Relevant waypoint used another step's presentation")
    target = NS.Internal.DugiProvider.ExtractTarget({ stepIndex = 1, explicit = true })
    expect(target.dugiStepIndex == 1 and target.title == collect.title, "Explicit click lost destination ownership")
    dugi.states[4] = "C"
    target = NS.Internal.DugiProvider.ExtractTarget()
    expect(target.dugiStepIndex == 1, "Completed native waypoint stole navigation")
    dugi.states[4] = "X"
    target = NS.Internal.DugiProvider.ExtractTarget()
    expect(target.dugiStepIndex == 1, "Skipped native waypoint stole navigation")
    final.guideIndex = 15
    target = NS.Internal.DugiProvider.ExtractTarget()
    expect(target.dugiStepIndex == 1, "Unrelated waypoint stole navigation")
    final.guideIndex, final.isRouteWaypoint, final.isRouteDestination = 1, true, false
    target = NS.Internal.DugiProvider.ExtractTarget()
    expect(target.dugiDestinationSource == "coordinates" and target.dugiDestinationFallbackReason == "gps_intermediate",
        "GPS intermediate was accepted or its fallback reason was lost")

    -- Follow the real provider -> guide projection -> final presentation path.
    dugi.IterateRelevantSteps = nil
    dugi.states[1] = "U"
    final = nil
    target = NS.Internal.DugiProvider.ExtractTarget()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("bridge/routing/guide.lua"))()
    NS.RegisterGuideTargetProvider("dugi", adapter)
    NS.RegisterGuideTargetProvider("zygor", { isLoaded = function() return true end })
    NS.State.routing = { activeGuideProvider = "zygor", guideRouteStates = {} }
    local projection
    NS.SyncGuideQueueProjection = function(record) projection = record end
    NS.UpdateGuideTarget("dugi", target, false)
    expect(projection.title == collect.title and projection.subtext == nil,
        "Guide queue projection reintroduced duplicate context")
    NS.State.routing.activeGuideProvider = "dugi"
    local record = NS.GetActiveGuideRouteState()
    NS.State.routing.carrierState = {
        source = "guide", kind = "guide", routeLegKind = "destination", title = target.title,
        sig = "fixture", finalMapID = target.mapID, finalX = target.x, finalY = target.y,
    }
    assert(loadfile("bridge/routing/presentation.lua"))()
    local displayed = NS.ResolvePresentation()
    expect(displayed.carrierTitle == collect.title and displayed.overlayTitle == collect.title
        and displayed.pinpointSubtext == nil, "Arrow/plaque disagreed with the normalized collect step")
    record.subtext, record.target.subtext = "Open the journal on the upper shelf", "Open the journal on the upper shelf"
    local carrier = NS.State.routing.carrierState
    carrier.kind, carrier.routeLegKind, carrier.routeTravelType, carrier.title = "route", "carrier", "travel", "Take the boat to Village"
    displayed = NS.ResolvePresentation()
    expect(displayed.overlayTitle == "Take the boat to Village" and displayed.pinpointSubtext == nil,
        "Carrier leg inherited final collect instructions")
    carrier.kind, carrier.routeLegKind, carrier.routeTravelType = "guide", "destination", nil
    displayed = NS.ResolvePresentation()
    expect(displayed.overlayTitle == collect.title and displayed.pinpointSubtext == "Open the journal on the upper shelf",
        "Final destination did not restore objective context")

    -- Render the actual Dugi module twice: its layout must consume prepared
    -- facts without rescanning Dugi or generating another description.
    NS.Constants.WORLD_OVERLAY_COLOR_AUTO = "auto"
    NS.Constants.WORLD_OVERLAY_COLOR_CUSTOM = "custom"
    NS.Constants.ZYGOR_STEP_CHAT_STICKY_NONE = "none"
    NS.Constants.ZYGOR_STEP_CHAT_STICKY_COUNT = "count"
    NS.Constants.ZYGOR_STEP_CHAT_STICKY_TITLES = "titles"
    local viewer, frame, watcher, progressDisplay
    NS.GetGuideTrackerViewerSettings = function() return { enabled = true, textColorMode = "auto" } end
    NS.RegisterGuideTrackerViewerProvider = function(_, provider) viewer = provider end
    local container, manager = {}, { GetContainerForModule = function() return nil end }
    local lines = {}
    local block = { height = 20, AddObjective = function(self, index, text)
        local line = { Text = { SetTextColor = function() end }, SetScript = function() end, EnableMouse = function() end }
        lines[index] = { text = text, line = line }
        return line
    end }
    NS.Internal.GuideTrackerViewer = {
        Host = {
            IsBlizzardHost = function() return true end, GetHostID = function() return "blizzard" end,
            GetTrackerFrame = function() return container end, GetManager = function() return manager end,
            IsKTLoaded = function() return false end, TryRegisterOnce = function() return true end,
            IsActuallyRegistered = function() return true end,
        },
        Controls = {
            Create = function() end, Update = function(_, current, total, percent)
                progressDisplay = { current = current, total = total, percent = percent }
            end, SetModuleHeader = function() end,
            SetBlockHeaderText = function() end,
            SetStepCheckbox = function(line, _, binding) line.binding = binding end,
        },
        ModuleFactory = { Create = function()
            frame = { GetBlock = function() return block end, LayoutBlock = function() end,
                MarkDirty = function(self) self.dirty = (self.dirty or 0) + 1 end,
                Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end }
            return frame
        end },
    }
    assert(loadfile("integrations/guides/viewer_styles.lua"))()
    assert(loadfile("integrations/guides/viewer_render.lua"))()
    local viewerHooks = {}
    _G.hooksecurefunc = function(object, method, callback)
        viewerHooks[object] = viewerHooks[object] or {}
        local previous = viewerHooks[object][method]
        viewerHooks[object][method] = function(...)
            if previous then previous(...) end
            callback(...)
        end
    end
    _G.C_Timer = { After = function(_, fn) fn() end }
    _G.CreateFrame = function()
        watcher = { RegisterEvent = function() end, UnregisterEvent = function() end,
            SetScript = function(self, _, callback) self.callback = callback end }
        return watcher
    end
    dugi.firstGuideLoaded = true
    dugi.SetViewTabTitle, dugi.SetPercentComplete = function() end, function() end
    dugi.Modules = { Guides = { percentComplete = 10 } }
    dugi.GetLastUsedStepIndex = function() return 450 end
    assert(loadfile("integrations/guides/viewer_controller.lua"))()
assert(loadfile("integrations/guides/viewer_chat.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/viewer_native.lua"))()
assert(loadfile("tests/guide_tabs_fixture.lua"))()
assert(loadfile("integrations/guides/dugi/tabs.lua"))()
assert(loadfile("integrations/guides/dugi/viewer.lua"))()
    watcher.callback(watcher, "PLAYER_LOGIN")
    expect(frame ~= nil, "Dugi module did not attach")
    before = reads
    frame:LayoutContents()
    frame:LayoutContents()
    expect(reads == before, "Viewer layout reread Dugi presentation")
    expect(lines[1].text == collect.title and lines[2] == nil and block.binding and not lines[1].line.binding,
        "Viewer reintroduced a repeated detail or lost the action checkbox")
    local dirty = frame.dirty
    viewer.applySettings()
    expect(frame.dirty > dirty and reads == before, "Appearance settings did not refresh the attached Viewer cheaply")
    _G.DugisGuideViewer = nil
    viewer.applySettings()
    frame:LayoutContents()
    expect(not frame.shown and not frame.hasContents and not viewer.isAttached(), "Missing Dugi left its module visible")
    _G.DugisGuideViewer = dugi
    viewer.applySettings()
    expect(frame.shown and viewer.isAttached(), "Dugi did not reattach after availability returned")
    local floating, hidden = true, false
    local native = { alpha = 0.7, mouse = true, clamped = true, points = { { "CENTER", nil, "CENTER", 12, -8 } } }
    function native:GetAlpha() return self.alpha end
    function native:IsMouseEnabled() return self.mouse end
    function native:IsClampedToScreen() return self.clamped end
    function native:GetNumPoints() return #self.points end
    function native:GetPoint(index) return unpack(self.points[index]) end
    function native:ClearAllPoints() self.points = {} end
    function native:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function native:SetAlpha(value) self.alpha = value end
    function native:EnableMouse(value) self.mouse = value end
    function native:SetClampedToScreen(value) self.clamped = value end
    function native:HookScript(_, handler) self.onShow = handler end
    _G.DugisSmallFrameContainer = native
    dugi.IsSmallFrameFloating = function() return floating end
    local chat = false
    replaceMethod(NS, "GetGuideTrackerViewerSettings", function()
        return { enabled = true, textColorMode = "auto", hideDugiFrame = hidden, chatOutputOnChange = chat }
    end)
    hidden = true
    viewer.applySettings()
    expect(native.alpha == 0.01 and not native.mouse and not native.clamped, "Floating Dugi frame was not cloaked")
    floating = false
    viewer.applySettings()
    expect(native.alpha == 0.7 and native.mouse and native.clamped and native.points[1][4] == 12,
        "Switching to anchored mode did not restore the captured native appearance")
    floating = true
    viewer.applySettings()
    hidden = false
    viewer.applySettings()
    expect(native.alpha == 0.7 and native.points[1][5] == -8, "Disabling native hiding failed exact restoration")
    local messages = {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) messages[#messages + 1] = text end }
    NS.Msg = function(text) messages[#messages + 1] = text end
    local stickyMode = "none"
    replaceMethod(NS, "GetGuideTrackerViewerProviderSettings", function()
        return { enabled = true, chatTextColorMode = "custom", chatTextCustomColor = { r = 0, g = 1, b = 0 },
            chatStickySummary = stickyMode }
    end)
    chat = true
    viewer.refresh("step")
    expect(messages[#messages]:find("|cff00ff00Collect [Hieron's Journal]|r", 1, true),
        "Dugi chat did not render normalized rows in its independent custom color")
    local messageCount = #messages
    viewer.applySettings()
    viewer.refresh("step")
    expect(#messages == messageCount, "Appearance refresh repeated chat output for an unchanged step")
    dugi.Modules.StickyFrame = { StickyQuests = { 4 } }
    stickyMode, _G.DugisGuideUser.CurrentQuestIndex = "count", 2
    viewer.refresh("step")
    local countFound, titleFound = false, false
    for i = messageCount + 1, #messages do
        countFound = countFound or messages[i]:find("Sticky steps: 1 active", 1, true)
        titleFound = titleFound or messages[i]:find("Accept 'Truth of the Past'", 1, true)
    end
    expect(countFound and not titleFound, "Dugi count-only sticky summary printed the wrong content")
    messageCount = #messages
    stickyMode, _G.DugisGuideUser.CurrentQuestIndex = "titles", 3
    viewer.refresh("step")
    titleFound = false
    for i = messageCount + 1, #messages do titleFound = titleFound or messages[i]:find("Accept 'Truth of the Past'", 1, true) end
    expect(titleFound, "Dugi sticky-title mode omitted the native sticky step")
    stickyMode, _G.DugisGuideUser.CurrentQuestIndex = "none", 1
    dugi.Modules.StickyFrame = nil
    _G.DEFAULT_CHAT_FRAME = nil
    chat = false
    local scheduleProvider = NS.ScheduleGuideProviderEvaluation
    NS.ScheduleGuideProviderEvaluation = function() end
    local originalGuide = _G.CurrentTitle
    _G.CurrentTitle = "Delayed Guide Load"
    viewerHooks[dugi].SetViewTabTitle()
    frame:LayoutContents()
    expect(progressDisplay.total == 0 and progressDisplay.current == nil,
        "Guide switch displayed stale completion or enabled navigation before native restoration")
    dugi.actions[22], dugi.quests1[22], dugi.quests1L[22], dugi.quests2[22] = "N", "Restored Step", "Restored Step", "Continue here"
    _G.DugisGuideUser.CurrentQuestIndex = 22
    dugi.Modules.Guides.percentComplete = 42
    viewerHooks[dugi].SetPercentComplete()
    frame:LayoutContents()
    expect(progressDisplay.current == 22 and progressDisplay.total == 450 and progressDisplay.percent == 42,
        "Delayed native progress restoration did not update cached Viewer rows and percentage")
    _G.CurrentTitle, _G.DugisGuideUser.CurrentQuestIndex = originalGuide, 1
    viewerHooks[dugi].SetPercentComplete()
    NS.ScheduleGuideProviderEvaluation = scheduleProvider

    -- A late item-name update changes labels, not destination identity.
    local record = NS.GetActiveGuideRouteState()
    record.legs = { { routeLegKind = "destination", mapID = target.mapID, x = target.x, y = target.y } }
    local plans = 0
    NS.RouteViaBackend = function() plans = plans + 1; return true end
    itemNames[100] = "Localized Journal"
    dugi.descriptions[1] = "Collect [Localized Journal]"
    P.Invalidate()
    local renamed = NS.Internal.DugiProvider.ExtractTarget()
    NS.UpdateGuideTarget("dugi", renamed, false, { presentationRefresh = true })
    expect(plans == 0 and NS.GetActiveGuideRouteState().title == "Collect [Localized Journal]",
        "A data-ready text refresh caused pathfinding or failed to update labels")
    _G.CurrentTitle = "Replacement Guide"
    local replacement = NS.Internal.DugiProvider.ExtractTarget()
    NS.UpdateGuideTarget("dugi", replacement, false)
    expect(plans == 1, "A new guide at the same coordinates reused another guide's step identity")
    local nativeHooks, received = {}, {}
    replaceMethod(_G, "hooksecurefunc", function(object, method, callback)
        nativeHooks[object] = nativeHooks[object] or {}
        nativeHooks[object][method] = callback
    end)
    replaceMethod(dugi, "SetViewTabTitle", function() end)
    dugi.DugisArrow.WaypointsChanged = function() end
    adapter.installHooks(function(reason, opts) received[#received + 1] = { reason, opts } end)
    nativeHooks[dugi].SetViewTabTitle()
    expect(received[#received][2] == nil, "Dugi's repeated title refresh could steal authority")
    dugi.firstGuideLoaded = false
    _G.CurrentTitle = "Restored Guide"
    nativeHooks[dugi].SetViewTabTitle()
    expect(received[#received][2] == nil, "Dugi's startup restoration could steal authority")
    dugi.firstGuideLoaded = true
    _G.CurrentTitle = "Another Guide"
    nativeHooks[dugi].SetViewTabTitle()
    expect(received[#received][2].allowProviderSwitch, "A genuine Dugi guide selection lost activation")
    final = { map = 999, x = 10, y = 20, guideIndex = 1, isRouteDestination = true }
    local fresh = NS.Internal.DugiProvider.ExtractTarget()
    expect(fresh.mapID == 2405 and fresh.dugiDestinationSource == "coordinates", "Old-guide native waypoint survived guide replacement")
    nativeHooks[dugi.DugisArrow].WaypointsChanged()
    fresh = NS.Internal.DugiProvider.ExtractTarget()
    expect(fresh.mapID == 999, "Fresh associated native final waypoint was not restored")
    print("Dugi presentation parity passed: " .. client.flavor .. " " .. client.version)
end
