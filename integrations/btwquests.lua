-- ============================================================
-- BtWQuests integration
-- ============================================================
--
-- Adds BtWQuests quest data and carries the selected quest and point through a
-- TomTom click.

local NS = _G.AzerothWaypointNS
local BtW = { label = "BtWQuests" }
NS.Internal.BtWQuests = BtW
local Data = NS.Internal.QuestData
local hooked = setmetatable({}, { __mode = "k" })
local entityTypes = { npc = "Npc", object = "Object", item = "Item" }

local function Call(owner, method, ...)
    if type(owner) ~= "table" or type(owner[method]) ~= "function" then return end
    local ok, value = pcall(owner[method], owner, ...)
    if ok then return value end
end
local function Database()
    if NS.IsAddonLoaded("BtWQuests") then return rawget(_G, "BtWQuestsDatabase") end
end
function BtW.GetQuestName(id)
    return Call(Call(Database(), "GetQuestByID", id), "GetName")
end

function BtW.GetEntityName(kind, id)
    local method = kind == "Npc" and "GetNPCByID" or kind == "Object" and "GetObjectByID"
    if method then return Call(Call(Database(), method, id), "GetName") end
end

function BtW.GetRoleEntity(id, action)
    if action ~= "accept" then return end
    local database = Database()
    local quest = Call(database, "GetQuestByID", id)
    local source = type(quest) == "table" and quest.source
    if type(source) ~= "table" then return end
    -- GetSource/CreateItem annotates the native source table. Read its
    -- explicit identity instead, chain order and coordinates prove no role.
    local kind, entity = entityTypes[source.type], Data.ID(source.id)
    if not kind or not entity then return end
    if source.restrictions ~= nil then
        local character = Call(rawget(_G, "BtWQuestsCharacters"), "GetPlayer")
        if not character or Call(database, "IsItemValidForCharacter", source, character) ~= true then return end
    end
    return kind, entity
end

Data.Register("btwquests", BtW)

local clickedContext

NS.RegisterExternalWaypointSource("btwquests", {
    displayName = "BtWQuests",
    resolveMetadata = function()
        local context = clickedContext
        clickedContext = nil
        return context or false
    end,
})

-- ============================================================
-- TomTom click handoff
-- ============================================================

-- Inspect only the TomTom caller. A deeper BtWQuests frame can belong to an
-- unrelated addon publishing in response to one of its clicks.
function BtW.IsTomTomPublisher(stack)
    if type(stack) ~= "string" then return false end
    for addonName in stack:lower():gsub("/", "\\"):gmatch("addons\\([^\\%s%]:]+)\\") do
        if addonName ~= "azerothwaypoint" and addonName ~= "tomtom" then
            return addonName == "btwquests"
        end
    end
    return false
end

local function FinishQuestClick(previousContext, ok, ...)
    clickedContext = previousContext
    if not ok then error((...), 0) end
    return ...
end

local function InstallQuestClick()
    local database = rawget(_G, "BtWQuestsDatabase")
    if type(database) ~= "table" or type(database.GetItemType) ~= "function" then return end
    local ok, quest = pcall(database.GetItemType, database, "quest")
    if not ok or type(quest) ~= "table" or type(quest.OnClick) ~= "function"
        or type(quest.GetID) ~= "function" then
        return
    end
    if hooked[quest] then return end
    hooked[quest] = true

    local original = quest.OnClick
    quest.OnClick = function(self, db, item, ...)
        local previousContext = clickedContext
        clickedContext = nil
        -- Default quest rows resolve their own destination. Custom click
        -- actions can publish a point belonging to an entirely different item.
        if self == quest and db == database and type(item) == "table"
            and item.type == "quest" and item.onClick == nil and NS.IsRoutingEnabled() then
            local read, id = pcall(quest.GetID, self, db, item)
            id = read and Data.ID(id) or nil
            if id then
                clickedContext = { questID = id }
                local active = NS.ReadGuideQuestState and NS.ReadGuideQuestState(id)
                if active == false then
                    local kind, entity = BtW.GetRoleEntity(id, "accept")
                    clickedContext.action, clickedContext.entityKind, clickedContext.entityID = "accept", kind, entity
                end
            end
        end
        return FinishQuestClick(previousContext, pcall(original, self, db, item, ...))
    end
end

local function Install()
    if not NS.IsAddonLoaded("BtWQuests") then return end
    InstallQuestClick()
    local database = Database()
    if type(database) ~= "table" or hooked[database] then return end
    hooked[database] = true
    for _, method in ipairs({ "AddData", "AddDataTable", "UpdateDataTable" }) do
        if type(database[method]) == "function" then
            hooksecurefunc(database, method, function(_, dataType)
                if dataType == "quest" or dataType == "npc" or dataType == "object" then Data.RequestRefresh() end
            end)
        end
    end
end
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and (type(addon) ~= "string" or not addon:match("^BtWQuests")) then return end
    Install()
    Data.RequestRefresh()
end)
Install()
