local f = dofile("tests/service_search_fixture.lua")()
local NS, search = f.NS, f.search
UnitClass = function() return "Rogue", "ROGUE" end
f.z.NPCData.raw = { Repair = "1=sH|m1412|x10|y10\n", Vendor = "2=sH|m1412|x20|y20\n",
    TrainerAlchemy = "3=sH|m1412|x30|y30\n", ClassMage = "4=sH|m1412|x40|y40\n",
    ClassDruid = "5=sH|m1412|x50|y50\n", ClassPriest = "" }
local dugiCapabilities = { search.Query("repair"), search.Query("food"), search.Query("trainer", "alchemy"),
    search.Query("class", "ROGUE") }
local observed, available = {}, true
search.Register("dugi", { label = "Dugi", GetCapabilities = function() return available and dugiCapabilities or {} end,
    Find = function(query)
        observed[#observed + 1] = query
        if available and query.service == "repair" then return { mapID = 1412, x = .1, y = .2, title = "Dugi repair" } end
    end })
local function Group(catalog, label)
    for _, item in ipairs(catalog) do if item.label == label then return item end end
end
local function Entry(catalog, service, subject)
    local key = search.Key(assert(search.Query(service, subject)))
    for _, item in ipairs(catalog) do
        if item.children then
            for _, child in ipairs(item.children) do if search.Key(child.query) == key then return child end end
        elseif search.Key(item.query) == key then return item end
    end
end
local catalog = search.GetCatalog()
assert(Entry(catalog, "repair") and Entry(catalog, "food") and Entry(catalog, "vendor"))
assert(Entry(catalog, "class", "MAGE") and Entry(catalog, "class", "DRUID") and Entry(catalog, "class", "ROGUE"))
assert(not Entry(catalog, "class", "PRIEST"), "Empty native category was offered")
assert(not Group(catalog, "Profession Workshops") and not Group(catalog, "Weapon Masters"))
assert(#Group(catalog, "Profession Trainers").children == 1, "Same trainer appeared twice")
local revision = search.Revision()
for _ = 1, 100 do assert(search.GetCatalog() == catalog) end
assert(#f.callbacks == 0 and #f.calls == 0 and #observed == 0 and #f.timers == 0 and search.Revision() == revision,
    "Opening/reusing the catalog performed a search or changed navigation")
assert(not f.worker:GetScript("OnUpdate"))

assert(loadfile("interface/menus.lua"))()
assert(loadfile("integrations/minimap_menu.lua"))()
local model
MenuUtil = { CreateContextMenu = function(owner, build) model = NS.Internal.Menus.Build(owner, build) end }
Menu = nil
local controller = false
InputUtil = { IsGamepadUIEnabled = function() return controller end }
NS.Internal.Controller = { Enabled = function() return false end,
    Modal = { Menu = function(_, tree) model = tree end } }
assert(loadfile("interface/minimap_button.lua"))()
local function Child(parent, label)
    for _, node in ipairs(parent.children) do if node.text == label then return node end end
end
local anchor = {}
NS.ShowMinimapButtonMenu(anchor)
local nearby = assert(Child(model, "Search Nearby"))
local trainers = assert(Child(nearby, "Profession Trainers"))
local alchemy = assert(Child(trainers, "Alchemy Trainer"))
assert(not Child(nearby, "Dugi") and not Child(nearby, "Zygor"))
assert(not Child(nearby, "Profession Workshops"))
f.order[1], f.order[2], f.order[3] = "rxp", "dugi", "zygor"
alchemy.callback()
assert(observed[#observed].profession == "alchemy" and #f.callbacks == 1 and #f.calls == 0)
f.callbacks[1].done("progress")
assert(#f.calls == 0)
f.callbacks[1].done("success", {{type = "end", m = 1412, x = .3, y = .4, title = "3"}})
assert(#f.calls == 1 and f.calls[1].title == "NPC 3")
assert(not observed[#observed].zygorType and not observed[#observed].nativeType)
assert(search.ResolveQuery("trainer mage").classToken == "MAGE")
assert(search.ResolveQuery("druid trainer").classToken == "DRUID")
assert(search.ResolveQuery("weapon master two-handed swords").weaponLine == 55)
assert(search.ResolveQuery("reagent vendor").service == "reagents")
assert(search.ResolveQuery("trainer first-aid").profession == "first aid")
assert(search.ResolveQuery("workshop engineering").profession == "engineering")

controller = true
NS.ShowMinimapButtonMenu(anchor)
nearby = assert(Child(model, "Search Nearby"))
assert(Child(Child(nearby, "Class Trainers"), "Mage Trainer"), "Controller descriptions lost nested services")
local oldRepair = assert(Child(nearby, "Repair"))
available = false
oldRepair.callback()
assert(#f.callbacks == 2, "Retained menu did not recheck the providers at execution")
f.callbacks[2].done("failure")
assert(#f.calls == 1, "Exhausted retained search replaced the route")
f.z.startups = {}
catalog = search.GetCatalog()
assert(#catalog == 0)
NS.ShowMinimapButtonMenu(anchor)
assert(not Child(model, "Search Nearby"), "No-provider menu retained an empty search root")
local classFixture = dofile("tests/service_search_fixture.lua")()
classFixture.order[1], classFixture.order[2] = "dugi", "zygor"
classFixture.z.NPCData.raw.ClassMage = "4=sH|m1412|x40|y40\n"
local requestedClass
classFixture.search.Register("dugi", {label="Dugi",Find=function(query) requestedClass=query.classToken end})
assert(classFixture.search.Request(classFixture.search.Query("class", "MAGE")))
assert(requestedClass=="MAGE" and classFixture.callbacks[1].kind=="ClassMage")
classFixture.callbacks[1].done("success",{{type="end",m=1412,x=.4,y=.4,title="4"}})
assert(classFixture.calls[1].title=="NPC 4", "Class request changed during provider fallback")
print("Merged service catalog, unchanged caching, precise aliases, minimap/controller descriptions and shared fallback passed")
