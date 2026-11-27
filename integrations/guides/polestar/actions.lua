-- ============================================================
-- Polestar guide actions
-- ============================================================
--
-- Tracks Polestar's native item and target buttons and supplies their
-- ownership and artwork to the action panel.

local NS = _G.AzerothWaypointNS
if not NS.IsWoWForever() then return end
local A = NS.Internal.GuideTrackerViewer.GuideActions
local API = NS.Internal.PolestarProvider
local P, Source = NS.Internal.PolestarPresentation, NS.Internal.GuideSourceRuntime
local frames, lastFrames, cloakFrames = {}, {}, {}
local placement = Source.CreateObservation()
local subscribedRuntime
local bagObservation, bagRevision = Source.CreateObservation(), 0
local bagLabelRevision, bagLabel
local bagFields = { "bag", "slot", "id", "count", "into", "value", "link" }
local bagKinds = { "spare", "junk" }
local observedModels = setmetatable({}, { __mode = "k" })
local function Buttons(runtime) return runtime and runtime.QoL and runtime.QoL.Buttons end
local function TargetModelLoaded(model)
    local row = model:GetParent()
    if row and row.applied and row.npc and model.drawn == row.npc and A.NeedsModel("polestar") then A.Request("polestar") end
end
local function TargetArt(row)
    local model = row.Model
    if model and type(model.GetDisplayInfo) == "function" then
        if not observedModels[model] and type(model.HasScript) == "function" and model:HasScript("OnModelLoaded") then
            model:HookScript("OnModelLoaded", TargetModelLoaded)
            observedModels[model] = true
        end
        if row.face == "model" and row.npc and model.drawn == row.npc then
            return row.Mark, model:GetDisplayInfo()
        end
    end
    return row.face == "icon" and row.Face or row.Mark
end
local function NativeRevision(button)
    local r = API.GetRuntime()
    local buttons = Buttons(r)
    if not buttons or button ~= buttons.bag then return end
    bagObservation:Begin()
    for _, kind in ipairs(bagKinds) do
        local item = button[kind]
        for _, key in ipairs(bagFields) do bagObservation:Push(item and item[key]) end
    end
    local space = r.QoL and r.QoL.Space
    bagObservation:Push(space and P.Call(space, "Armed"))
    if bagObservation:Finish() then bagRevision = bagRevision + 1 end
    return bagRevision
end
local function Identity()
    local s = API.GetSnapshot()
    local r = API.GetRuntime()
    local p = NS.Internal.PolestarPresentation
    if s and s.state == "ready" and r then
        local guide = p.Call(r.Engine, "GetGuide")
        return guide and guide.id, p.Call(r.Engine, "GetStepIndex")
    end
end
local function ReadFrames(buttons)
    local count = 0
    if buttons then
        if buttons.item then
            count = count + 1; frames[count] = buttons.item
        end
        if buttons.target then
            count = count + 1; frames[count] = buttons.target
        end
        if buttons.bag then
            count = count + 1; frames[count] = buttons.bag
        end
        if buttons.anchor then
            count = count + 1; frames[count] = buttons.anchor
        end
        if buttons.rows then
            for _, row in ipairs(buttons.rows) do
                count = count + 1; frames[count] = row
            end
        end
    end
    for index = count + 1, #frames do frames[index] = nil end
    return frames
end
local function ReadCloakFrames()
    for index = #cloakFrames, 1, -1 do cloakFrames[index] = nil end
    -- Polestar anchors separate UIParent buttons together. Their 3D portraits
    -- are child frames and need their own alpha, even when the row is cloaked.
    for _, root in ipairs(ReadFrames(Buttons(API.GetRuntime()))) do
        A.AppendNativeControls(cloakFrames, root)
    end
    return cloakFrames
end
local function PlacementChanged()
    local collect = A.NeedsModel("polestar")
    if not collect and not NS.GetGuideActionSettings("polestar").hideNative then return end
    local buttons = Buttons(API.GetRuntime())
    local changed = false
    placement:Begin()
    for index, frame in ipairs(ReadFrames(buttons)) do
        if lastFrames[index] ~= frame then lastFrames[index], changed = frame, true end
        if collect and frame ~= buttons.anchor then
            local shown = A.IsNativeVisible(frame)
            placement:Push(shown)
            if shown then
                placement:Push(frame.itemID)
                placement:Push(frame.applied)
                placement:Push(frame.kind)
                placement:Push(frame.face)
                placement:Push(frame.npc)
                placement:Push(frame:GetAttribute("macrotext"))
                placement:Push(frame:GetAttribute("useOnKeyDown"))
                if frame == buttons.bag then placement:Push(NativeRevision(frame)) end
            end
        end
    end
    for index = #lastFrames, #frames + 1, -1 do lastFrames[index], changed = nil, true end
    if placement:Finish() or changed then A.Request("polestar") end
end
A.Register("polestar", {
    stepActions = true,
    placementEvents = true,
    identity = Identity,
    nativeRevision = NativeRevision,
    subscribe = function(refresh)
        API.Subscribe(function(_, changed) if changed then refresh() end end)
    end,
    frames = ReadCloakFrames,
    describe = function()
        local s = API.GetSnapshot(); return s.title, s.current
    end,
    collect = function()
        local guide, index = Identity()
        local builder = A.CreateBuilder("polestar", guide, index)
        local r = API.GetRuntime()
        local buttons = Buttons(r)
        if buttons then
            A.Native(builder, buttons.item, "items", index, "Polestar guide item")
            local targetCategory
            for _, row in ipairs(buttons.rows or {}) do
                if row.applied then
                    local category = row.kind == "mob" and "hostile" or "friendly"
                    if not targetCategory then
                        targetCategory = category
                    elseif targetCategory ~= category then
                        targetCategory = "helpers"; break
                    end
                end
            end
            A.Native(builder, buttons.target, targetCategory or "helpers", index, "Polestar target helper")
            for _, row in ipairs(buttons.rows or {}) do
                if row.applied and A.IsNativeVisible(row) then
                    local icon, portrait = TargetArt(row)
                    A.Native(builder, row, row.kind == "mob" and "hostile" or "friendly", index, "Target " .. row
                    .applied, nil, icon, portrait)
                end
            end
            local bag = buttons.bag
            if bag and (bag.spare or bag.junk) then
                local revision = NativeRevision(bag)
                if bagLabelRevision ~= revision then
                    local item = bag.spare or bag.junk
                    local name = Source.PlainText(item.link) or (item.id and ("item " .. item.id)) or "item"
                    local space = r.QoL and r.QoL.Space
                    local armed = space and P.Call(space, "Armed")
                    bagLabel = bag.spare and ("Equip spare bag: " .. name)
                        or armed and ("Press again to delete: " .. name) or
                        ("Bag space: " .. name .. " (press twice to delete)")
                    bagLabelRevision = revision
                end
                A.Native(builder, bag, "helpers", index, bagLabel)
            end
        end
        return builder:Finish()
    end,
    install = function()
        local r = API.GetRuntime()
        if not r or r == subscribedRuntime then return end
        subscribedRuntime = r
        P.Call(r, "On", "QUEST_BUTTONS_PLACED", PlacementChanged)
        P.Call(r, "On", "QOL_TARGET_MARK_CHANGED", PlacementChanged)
    end,
})
