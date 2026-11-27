-- ============================================================
-- Nearby service search
-- ============================================================
--
-- Finds nearby services through the available guide providers and sends the
-- winning result to manual routing. The same search serves the minimap menu
-- and slash command. Each request advances through available providers until
-- it finds a usable result.

local NS = _G.AzerothWaypointNS
local Search = {}
NS.Internal.ServiceSearch = Search

local providers, current, revision = {}, nil, 0
local generation = 0
function Search.Generation() return generation end

function Search.InvalidateCapabilities() generation = generation + 1 end

local definitions = {
    { "repair",         "Repair",              nil,           "repairs|repair vendor" },
    { "innkeeper",      "Innkeeper",           nil,           "inn|innkeepers" },
    { "flightmaster",   "Flight Master",       nil,           "flight master|flightmasters|fp" },
    { "mailbox",        "Mailbox",             nil,           "mail|mailboxes" },
    { "banker",         "Bank",                nil,           "bank|bankers" },
    { "auctioneer",     "Auction House",       nil,           "auction|auction house|ah|auctioneers" },
    { "stable",         "Stable Master",       nil,           "stable master|stablemaster|stable masters|stables" },
    { "barber",         "Barber",              nil,           "barbers|barbershop" },
    { "transmogrifier", "Transmogrifier",      nil,           "mog|tmog|transmog|transmogs|transmogrifiers" },
    { "voidstorage",    "Void Storage",        nil,           "void storage|void" },
    { "battlemaster",   "Battlemaster",        nil,           "battlemaster|battle master" },
    { "vendor",         "Vendor",              "vendors",     "vendors|store" },
    { "food",           "Food and Drink",      "vendors",     "drink|food and drink|food vendor|drink vendor|water" },
    { "poisons",        "Poison Vendor",       "vendors",     "poison|poison vendor" },
    { "reagents",       "Reagent Vendor",      "vendors",     "reagent|reagent vendor" },
    { "general",        "General Goods",       "vendors",     "general goods|goods|supplies" },
    { "arrows",         "Arrows",              "vendors",     "arrow" },
    { "bullets",        "Bullets",             "vendors",     "bullet" },
    { "ranged",         "Bows and Guns",       "vendors",     "bow|bows|gun|guns|bows and guns|crossbow|crossbows" },
    { "trainer",        "Profession Trainer",  "professions", "trainers|profession trainer|profession trainers" },
    { "class",          "Class Trainer",       "classes",     "class trainer|class trainers" },
    { "weapon",         "Weapon Master",       "weapons",     "weapon master|weapon masters|weapon trainer" },
    { "workshop",       "Profession Workshop", "workshops",   "workshops|profession workshop|profession workshops" },
    { "riding",         "Riding Trainer",      "trainers",    "riding trainer|riding trainers" },
    { "pettrainer",     "Hunter Pet Trainer",  "trainers",    "pet trainer|hunter pet trainer|hunter pets trainer" },
    { "portaltrainer",  "Portal Trainer",      "trainers",    "portal trainer|mage portal trainer" },
    { "training",       "Special Trainer",     "trainers" },
}
local groups = {
    { "vendors", "Vendors" }, { "professions", "Profession Trainers" }, { "classes", "Class Trainers" },
    { "weapons", "Weapon Masters" }, { "workshops", "Profession Workshops" }, { "trainers", "Other Trainers" },
}
Search.Professions = {
    alchemy = "Alchemy",
    archaeology = "Archaeology",
    bandages = "Bandages",
    blacksmithing = "Blacksmithing",
    cooking = "Cooking",
    enchanting = "Enchanting",
    engineering = "Engineering",
    ["first aid"] = "First Aid",
    fishing = "Fishing",
    herbalism = "Herbalism",
    inscription = "Inscription",
    jewelcrafting = "Jewelcrafting",
    leatherworking = "Leatherworking",
    mining = "Mining",
    skinning = "Skinning",
    tailoring = "Tailoring"
}
Search.Classes = {
    DRUID = "Druid",
    HUNTER = "Hunter",
    MAGE = "Mage",
    PALADIN = "Paladin",
    PRIEST = "Priest",
    ROGUE = "Rogue",
    SHAMAN = "Shaman",
    WARLOCK = "Warlock",
    WARRIOR = "Warrior",
    DEATHKNIGHT = "Death Knight",
    MONK = "Monk",
    DEMONHUNTER = "Demon Hunter",
    EVOKER = "Evoker"
}
Search.Weapons = {
    [43] = "Swords",
    [55] = "Two-handed swords",
    [44] = "Axes",
    [172] = "Two-handed axes",
    [54] = "Maces",
    [160] = "Two-handed maces",
    [229] = "Polearms",
    [136] = "Staves",
    [173] = "Daggers",
    [473] = "Fist weapons",
    [45] = "Bows",
    [226] = "Crossbows",
    [46] = "Guns",
    [176] = "Thrown"
}
local byService, aliases, subjects = {}, {}, {}

-- ============================================================
-- Service and trainer queries
-- ============================================================

local function Normalize(text)
    if type(text) ~= "string" then return "" end
    return text:lower():gsub("[%-%_]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
end
for index, entry in ipairs(definitions) do
    byService[entry[1]] = { label = entry[2], group = entry[3], order = index }
    aliases[entry[1]] = entry[1]
    for alias in (entry[4] or ""):gmatch("[^|]+") do aliases[alias] = entry[1] end
end
for key, label in pairs(Search.Classes) do subjects[Normalize(label)] = { "class", key } end
for key, label in pairs(Search.Professions) do subjects[Normalize(label)] = { "trainer", key } end
for key, label in pairs(Search.Weapons) do subjects[Normalize(label)] = { "weapon", key } end

function Search.PlayerClass()
    if type(UnitClass) == "function" then
        local _, token = UnitClass("player"); return token
    end
end

function Search.Query(service, subject, label)
    local definition = byService[service]
    if not definition then return end
    local query = { service = service, label = label or definition.label }
    if service == "trainer" or service == "workshop" then
        if subject then
            if not Search.Professions[subject] then return end
            query.profession = subject
            query.label = label or Search.Professions[subject] .. (service == "trainer" and " Trainer" or " Workshop")
        end
    elseif service == "class" then
        subject = subject or Search.PlayerClass()
        if not Search.Classes[subject] then return end
        query.classToken, query.label = subject, label or Search.Classes[subject] .. " Trainer"
    elseif service == "weapon" and subject then
        if not Search.Weapons[subject] then return end
        query.weaponLine, query.label = subject, label or Search.Weapons[subject] .. " Trainer"
    elseif service == "training" then
        if type(subject) ~= "string" or subject == "" then return end
        query.trainingID = subject
    elseif subject then
        return
    end
    return query
end

function Search.Key(query)
    return query.service ..
        ":" .. tostring(query.profession or query.classToken or query.weaponLine or query.trainingID or "")
end

function Search.ResolveQuery(text)
    text = Normalize(text)
    if text == "" or text == "help" or text == "list" then return nil, true end
    local service = aliases[text]
    if service then
        if service == "workshop" then return nil, true end
        return Search.Query(service)
    end
    local profession = text:match("^workshop%s+(.+)$") or text:match("^profession workshops?%s+(.+)$") or
        text:match("^(.+)%s+workshops?$")
    if profession and Search.Professions[profession] then return Search.Query("workshop", profession) end
    local subject = text:match("^trainer%s+(.+)$") or text:match("^profession trainers?%s+(.+)$")
        or text:match("^class trainers?%s+(.+)$") or text:match("^weapon masters?%s+(.+)$")
        or text:match("^weapon trainers?%s+(.+)$") or text:match("^(.+)%s+trainers?$")
    local known = subject and subjects[subject]
    if known then return Search.Query(known[1], known[2]) end
    -- Native special training names can be localized. Resolve the same labels
    -- shown in the catalog without borrowing another service's meaning.
    for _, entry in ipairs(Search.GetCatalog()) do
        for _, candidate in ipairs(entry.children or { entry }) do
            if Normalize(candidate.label) == text then return candidate.query end
        end
    end
    return nil, false, text
end

local capabilityEvents

-- ============================================================
-- Available services and menu entries
-- ============================================================

local function WatchCapabilities()
    if capabilityEvents or type(CreateFrame) ~= "function" then return end
    local events = CreateFrame("Frame")
    capabilityEvents = events
    for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED",
        "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_FACTION" }) do events:RegisterEvent(event) end
    events:SetScript("OnEvent", function(_, event, unit)
        if event ~= "UNIT_FACTION" or unit == "player" then Search.InvalidateCapabilities() end
    end)
end

local catalog, sources = nil, {}
function Search.GetCapabilities(key)
    WatchCapabilities()
    local provider = providers[key]
    if not provider or not provider.GetCapabilities then return end
    local ok, capabilities = pcall(provider.GetCapabilities)
    if ok and type(capabilities) == "table" then return capabilities end
end

-- Providers return immutable, cached capability snapshots. Only identifiers
-- and labels are merged here, finding an NPC is exclusively a clicked action.
function Search.GetCatalog()
    WatchCapabilities()
    local changed, count = catalog == nil, 0
    for _, key in ipairs(NS.GetGuideTrackerViewerOrder()) do
        local provider = providers[key]
        if provider and provider.GetCapabilities then
            local capabilities = Search.GetCapabilities(key)
            if capabilities then
                count = count + 1
                local old = sources[count]
                if not old or old.key ~= key or old.capabilities ~= capabilities then
                    sources[count], changed = { key = key, capabilities = capabilities }, true
                end
            end
        end
    end
    if #sources ~= count then
        changed = true; for i = #sources, count + 1, -1 do sources[i] = nil end
    end
    if not changed then return catalog end
    local entries, pages, seen = {}, {}, {}
    for _, source in ipairs(sources) do
        for _, query in ipairs(source.capabilities) do
            local definition = byService[query.service]
            local key = definition and Search.Key(query)
            if key and not seen[key] then
                seen[key] = true
                local entry = { label = query.label, query = query, order = definition.order }
                if query.service == "vendor" then
                    entry.label = "Any Vendor"
                elseif query.service == "trainer" and not query.profession then
                    entry.label = "Any Profession Trainer"
                elseif query.service == "weapon" and not query.weaponLine then
                    entry.label = "Any Eligible Weapon Master"
                end
                if definition.group then
                    pages[definition.group] = pages[definition.group] or {}
                    table.insert(pages[definition.group], entry)
                else
                    entries[#entries + 1] = entry
                end
            end
        end
    end
    table.sort(entries, function(a, b) return a.order < b.order end)
    for _, group in ipairs(groups) do
        local children = pages[group[1]]
        if children then
            table.sort(children, function(a, b)
                local ag = a.query.service == "vendor" or a.query.service == "trainer" and not a.query.profession
                    or a.query.service == "weapon" and not a.query.weaponLine
                local bg = b.query.service == "vendor" or b.query.service == "trainer" and not b.query.profession
                    or b.query.service == "weapon" and not b.query.weaponLine
                if ag ~= bg then return ag end
                return a.label < b.label
            end)
            entries[#entries + 1] = { label = group[2], children = children }
        end
    end
    catalog = entries
    return catalog
end

function Search.ShowHelp()
    NS.Msg("Usage: /awp search <service> | trainer <profession/class> | workshop <profession> | weapon master <weapon>")
    NS.Msg("Search uses Guide Viewer Order and your selected AWP travel backend. Available searches:")
    local entries = Search.GetCatalog()
    if #entries == 0 then NS.Msg("No supported search provider is ready.") end
    for _, entry in ipairs(entries) do
        if entry.children then
            local labels = {}; for _, child in ipairs(entry.children) do labels[#labels + 1] = child.label end
            NS.Msg(entry.label .. ":", table.concat(labels, ", "))
        else
            NS.Msg(entry.label)
        end
    end
end

local function Message(...)
    if NS.Msg then NS.Msg(...) end
end

function Search.Register(key, provider) providers[key] = provider end

function Search.Revision() return revision end

-- ============================================================
-- Search lifetime and route handoff
-- ============================================================

function Search.Cancel()
    revision = revision + 1
    local request = current
    current = nil
    if request and request.cancel then request.cancel() end
end

local function ValidPoint(point)
    return type(point) == "table" and type(point.mapID) == "number" and point.mapID > 0
        and point.mapID < math.huge and point.mapID == math.floor(point.mapID)
        and type(point.x) == "number" and point.x >= 0 and point.x <= 1
        and type(point.y) == "number" and point.y >= 0 and point.y <= 1
end

-- Both native menus and slash searches publish through the same manual handoff.
-- Lookup never activates a guide or changes the saved travel backend.
function Search.Publish(point)
    if not ValidPoint(point) then return false end
    Search.Cancel()
    local meta = point.meta or {}
    meta.queueSourceType = "transient_source"
    if NS.BuildManualIdentity and NS.BuildRouteMeta then
        meta = NS.BuildRouteMeta(NS.BuildManualIdentity(point.mapID, point.x, point.y), meta)
    end
    return NS.RequestManualRoute(point.mapID, point.x, point.y, point.title, meta) == true
end

function Search.Request(query, providerKey)
    Search.Cancel()
    local order = providerKey and { providerKey } or NS.GetGuideTrackerViewerOrder()
    local request = { index = 0, success = false }
    current = request
    local function advance()
        if current ~= request then return end
        request.index = request.index + 1
        local key = order[request.index]
        if not key then
            current = nil
            Message("No available guide found a nearby", query.label or query.service or "service")
            return
        end
        local provider = providers[key]
        if not provider then return advance() end
        local attempt = {}
        request.attempt = attempt
        local function complete(point, reason)
            if current ~= request or request.attempt ~= attempt or attempt.done then return end
            attempt.done = true
            if request.cancel then
                request.cancel(); request.cancel = nil
            end
            if not ValidPoint(point) then
                if providerKey and type(reason) == "string" then
                    current = nil
                    Message(provider.label .. ":", reason)
                    return
                end
                return advance()
            end
            current = nil
            if Search.Publish(point) then
                request.success = true
                Message("Nearby", query.label or query.service or "service", "found by", provider.label .. ":",
                    point.title)
            else
                Message("Could not route to the nearby", query.label or "service", "found by", provider.label)
            end
        end
        local ok, result, cancel = pcall(provider.Find, query, complete)
        if current ~= request or attempt.done then return end
        if not ok then
            if NS.Debug then NS.Debug("Nearby search failed:", key, result) end
            return complete(nil, "The service search could not read this addon's data.")
        end
        if result ~= "pending" then return complete(result, cancel) end
        request.cancel = cancel
        Message("Searching nearby", query.label or query.service or "service", "with", provider.label)
    end
    advance()
    return current == request or request.success
end
