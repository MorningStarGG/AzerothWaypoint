local fixture = dofile("tests/guide_parity/fixture.lua")
local adapters = dofile("tests/guide_parity/native_adapters.lua")
local native = dofile("tests/guide_parity/native_function.lua")
for _, client in ipairs({ "retail", "forever" }) do
    local scenario = { current = 1, stop = { kind = "objective",
        objective = { text = "Douse the Bookshelf Fire", action = "complete" },
        quests = { { id = 33813, name = "A Burning Library", state = "active" } } } }
    local f = fixture.setup(client, scenario)
    adapters.rxp(f, scenario, client)
    local r, api = f.native.runtime, f.NS.Internal.RXPProvider
    local names = { [100] = "the Draenei Bucket", [101] = "Frost Channel" }
    r.GetItemName, r.GetSpellInfo = function(id) return names[id] end, function(id) return names[id] end
    r.functions, r.icons = {}, { gossip = "" }
    C_GossipInfo.GetOptions = function() return {} end
    local env = { addon = r, L = function(text) return text end }
    native(client, "RXPGuides/functions.lua", "addon.functions.use", env)
    native(client, "RXPGuides/functions.lua", "addon.functions.gossipoption", env)
    local step = r.currentGuide.steps[1]
    local point, objective = step.elements[1], step.elements[2]
    local function output(title, subtitle)
        api.Schedule("QUEST_LOG_UPDATE"); f.flush()
        local target = assert(f.NS.GetGuideTargetProvider("rxp").extractTarget())
        local shown, queue = fixture.publish(f, target)
        assert(shown.overlayTitle == title and shown.pinpointSubtext == subtitle,
            "Native helper pair: " .. tostring(shown.overlayTitle) .. " / " .. tostring(shown.pinpointSubtext))
        assert(queue.mirrorTitle == title and queue.pinpointSubtext == subtitle)
        assert(shown.semanticQuestID == 33813 and target.x == f.x and target.y == f.y, "Helper stole destination ownership")
        return target
    end
    for _, tag in ipairs({ "use", "usespell" }) do
        local id = tag == "use" and 100 or 101
        local helper = r.functions.use("Fixture", nil, tostring(id))
        assert(helper.textOnly and helper.activeItems[id] ~= nil)
        helper.tag, helper.step = tag, step
        step.elements = { point, helper, objective }
        local title = tag == "use" and "Use the Draenei Bucket" or "Cast Frost Channel"
        output("Douse the Bookshelf Fire", title)
        -- Explicit native parent ownership must produce the same pair.
        point.parent = objective
        output("Douse the Bookshelf Fire", title)
        point.parent = nil
        -- A second waypoint ends the association, even at identical coordinates.
        local other = { tag = "goto", zone = f.map, x = 55, y = 55, textOnly = true, arrow = true, step = step }
        step.elements = { point, objective, other, helper }
        output("Douse the Bookshelf Fire", nil)
    end
    local helper = r.functions.use("Fixture", nil, "100")
    helper.tag, helper.step = "use", step
    step.elements = { point, helper, objective }
    names[100] = nil
    output("Douse the Bookshelf Fire", nil)
    names[100] = "the Draenei Bucket"
    f.frame.Fire("GET_ITEM_INFO_RECEIVED", 100, true); f.flush()
    output("Douse the Bookshelf Fire", "Use the Draenei Bucket")
    local choice = r.functions.gossipoption("Fixture", 'Select "I need an illusion."', "601")
    assert(choice.gossipId == 601 and choice.text == 'Select "I need an illusion."')
    choice.tag, choice.step = "gossipoption", step
    step.elements = { point, choice, objective }
    point.parent = objective
    output("Douse the Bookshelf Fire", 'Select "I need an illusion."')
    print(client .. " native RXP use/spell/gossip fields, scoped ownership and late-name invalidation passed")
end
