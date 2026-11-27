-- ============================================================
-- Native guide map waypoints
-- ============================================================
--
-- Coordinates map clicks between the active guide and AWP and releases native
-- waypoints when ownership changes.

local NS = _G.AzerothWaypointNS
if not NS.IsWoWForever() then return end

local Native = {}
NS.Internal.NativeMapWaypoints = Native
local polestar, questie, questieListener, canvas, shiftOwner
local listenerChecked
local retired = {}
local skippedZygorRelease

local function CombatLocked()
    return InCombatLockdown and InCombatLockdown()
end

local function Gesture()
    if not NS.IsRoutingEnabled() or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local scroll = WorldMapFrame.ScrollContainer
    if IsControlKeyDown() or not scroll or not scroll:IsMouseOver() then return end
    local alt, shift = not not IsAltKeyDown(), not not IsShiftKeyDown()
    if alt == shift then return end
    return alt and "alt" or "shift"
end

local function PolestarCanClick(mode)
    if not polestar or not polestar.enabled() then return false end
    local r = polestar.addon
    if r.Nav.HandedOff and r.Nav.HandedOff() then return false end
    if r.Nav.handoff and r.Nav.handoff.Available and r.Nav.handoff.Available() then return false end
    if mode == "shift" then
        local active = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow) or ChatEdit_GetActiveWindow
        if active and active() or r.GamepadUI and r.GamepadUI() then return false end
    end
    return true
end

local function QuestieCanClick()
    return questie and questie.ready == true and questie.charDB and questie.HBD and questie.Waypoints.hooked
end

local function Owner(mode)
    if not mode then return end
    if QuestieCanClick() then
        if questieListener and (mode ~= "shift" or canvas == WorldMapFrame)
            and NS.GetActiveGuideProvider() == "polestar" and PolestarCanClick(mode) then
            return "polestar"
        end
        return "questierouter"
    end
    if PolestarCanClick(mode) then return "polestar" end
end

function Native.PolestarYields()
    local mode = Gesture()
    local owner = mode == "shift" and shiftOwner or Owner(mode)
    return owner == "questierouter" or owner == "zygor"
end

-- Zygor Forever polls mouse release independently of the map canvas. It uses
-- this one-click flag itself when removing a pin to avoid placing another one.
local function SkipZygorRelease(pointer)
    if pointer and pointer.OverlayProvider and not pointer.OverlayProvider.onCanvasClickHandler
        and not pointer.IgnoreThisButtonDown then
        pointer.IgnoreThisButtonDown = true
        skippedZygorRelease = pointer
    end
end

local function IsZygorRemovalClick(pointer)
    if pointer.IgnoreThisButtonDown then return true end -- Zygor already handled mouse-down.
    local scripts = pointer.frame_worldmap_functions
    if not (scripts and scripts.OnClick and GetMouseFoci) then return false end
    for _, frame in ipairs(GetMouseFoci()) do
        if frame:IsObjectType("Button") and not frame:IsForbidden() and frame:GetScript("OnClick") == scripts.OnClick then
            ---@cast frame any
            local point = frame.waypoint
            if point and (point.type == "manual" or point.surrogate_for and point.surrogate_for.type == "manual") then
                return true
            end
        end
    end
    return false
end

-- ============================================================
-- Map click handlers
-- ============================================================

local function CanvasClick(map, button)
    if button ~= "LeftButton" or not QuestieCanClick() or not questieListener then return false end
    local mode = Gesture()
    local owner = shiftOwner
    shiftOwner = nil
    if mode ~= "shift" or owner ~= "polestar" or not PolestarCanClick(mode) then return false end
    local mapID, x, y = map:GetMapID(), map:GetNormalizedCursorPosition()
    if not (mapID and x and y) then return false end
    if issecretvalue and (issecretvalue(mapID) or issecretvalue(x) or issecretvalue(y)) then return false end
    if polestar.addon.Nav.journey.OnMapClick(mapID, x * 100, y * 100) then
        local _, pointer = NS.GetZygorPointer()
        SkipZygorRelease(pointer)
    end
    return true
end

local function InstallCanvas()
    local map = WorldMapFrame
    if not (questieListener and map and map.AddCanvasClickHandler) or canvas == map or CombatLocked() then return end
    if pcall(map.AddCanvasClickHandler, map, CanvasClick, 1001) then canvas = map end
end

local function FindQuestieListener()
    if not GetFramesRegisteredForEvent then return end
    local found
    for _, frame in ipairs({ GetFramesRegisteredForEvent("GLOBAL_MOUSE_DOWN") }) do
        if frame.GetSourceLocation and (not frame.IsForbidden or not frame:IsForbidden())
            and (not frame.IsProtected or not frame:IsProtected()) then
            local ok, location = pcall(frame.GetSourceLocation, frame)
            if ok and type(location) == "string" and not (issecretvalue and issecretvalue(location))
                and location:lower():gsub("\\", "/"):find("questierouter/guide/waypoints.lua", 1, true)
            then
                if found then return end
                found = frame
            end
        end
    end
    return found
end

-- ============================================================
-- Native waypoint ownership
-- ============================================================

local function Current(token)
    local ok, current = pcall(token.current, token.target)
    if ok then return current end
end

local function Release(token)
    local current = Current(token)
    if current == false then return true end
    if current and not CombatLocked() then
        return pcall(token.remove, token.target)
    end
end

function Native.Retire(record, discardQueue)
    local token = record and record._nativeMapWaypoint
    if not token then return end
    record._nativeMapWaypoint = nil
    local queue = NS.RouteQueueInternal
    if discardQueue and queue and record.queueIsTransient and type(record.queueID) == "string" then
        local removed = queue.PopTransientQueue(record.queueID)
        local stack = queue.GetTransientQueueStack()
        if removed and removed.resumeManualQueueID and stack[1] and not stack[1].resumeManualQueueID then
            stack[1].resumeManualQueueID = removed.resumeManualQueueID
        end
        if removed then queue.RefreshQueueUI() end
    end
    if not Release(token) then retired[token] = true end
end

local function Reconcile()
    for token in pairs(retired) do
        if Release(token) then retired[token] = nil end
    end
    local routing = NS.State.routing
    local pending = routing and routing.pendingManualAuthority
    local active = routing and routing.manualAuthority
    local token = pending and pending._nativeMapWaypoint
    if token and Current(token) == false then
        NS.CancelPendingManualRoute("native_waypoint_removed")
        pending = nil
    end
    token = active and active._nativeMapWaypoint
    if token and Current(token) == false then
        NS.ClearManualRoute("native_waypoint_removed",
            pending and { preservePendingManualRoute = true, queueFollowup = false } or nil)
    end
end

local updates = NS.Internal.Scheduling.CreateCoalescer(Reconcile)
function Native.Changed()
    local routing = NS.State.routing
    local active = routing and routing.manualAuthority
    local pending = routing and routing.pendingManualAuthority
    if next(retired) or active and active._nativeMapWaypoint or pending and pending._nativeMapWaypoint then
        updates:Request()
    end
end

function Native.Adopt(source, target, current, remove, mapID, x, y, title)
    local routing = NS.State.routing
    local active, pending = routing and routing.manualAuthority, routing and routing.pendingManualAuthority
    local a, p = active and active._nativeMapWaypoint, pending and pending._nativeMapWaypoint
    if a and a.source == source and a.target == target or p and p.source == source and p.target == target then return true end
    local token = { source = source, target = target, current = current, remove = remove }
    local meta = { sourceAddon = source, queueSourceType = "transient_source" }
    if NS.BuildManualIdentity and NS.BuildRouteMeta then
        meta = NS.BuildRouteMeta(NS.BuildManualIdentity(mapID, x, y), meta)
    end
    return NS.RequestManualRoute(mapID, x, y, title, meta, { nativeMapWaypoint = token, strictRouteSuccess = true })
end

-- ============================================================
-- Provider hooks
-- ============================================================

function Native.InstallPolestar(r, getOption)
    if polestar and polestar.addon == r then return end
    if not (r.Nav and r.Nav.journey and type(r.Nav.journey.OnMapClick) == "function") then return end
    polestar = { addon = r, enabled = function() return getOption("nav.mapPlan") end }
    if type(r.Nav.RegisterModule) == "function" then r.Nav.RegisterModule({ OnTarget = Native.Changed }) end
end

function Native.InstallQuestieRouter(q)
    if not (q.ready and q.Waypoints and type(q.Waypoints.All) == "function" and type(q.Waypoints.First) == "function"
            and type(q.Waypoints.Target) == "function" and type(q.Waypoints.Remove) == "function"
            and type(q.Waypoints.Add) == "function") then
        return
    end
    local waypoints = q.Waypoints
    if questie ~= q then
        questie = q
        questieListener, listenerChecked, shiftOwner = nil, nil, nil
        local function CurrentPoint(point)
            for _, entry in ipairs(waypoints:All()) do if entry == point then return true end end
            return false
        end
        local function RemovePoint(point) waypoints:Remove(point) end
        local add = waypoints.Add
        waypoints.Add = function(self, mapID, x, y, ...)
            if not Gesture() then return add(self, mapID, x, y, ...) end
            local list = self:All()
            local first, second = list[1], list[2]
            -- QuestieRouter names, stores and publishes the point inside Add.
            mapID, x, y = NS.ResolveMapClickDestination(mapID, x, y)
            local result = add(self, mapID, x, y, ...)
            local point = self:First()
            if point and point ~= first and point ~= second then
                local target = self:Target(point)
                Native.Adopt("questierouter", point, CurrentPoint, RemovePoint, point.map, point.x, point.y,
                    target and target.name or "QuestieRouter waypoint")
            end
            return result
        end
        q:On("WAYPOINTS_CHANGED", Native.Changed)
    end
    if not listenerChecked and not CombatLocked() then
        listenerChecked = true
        local listener = FindQuestieListener()
        local original = listener and listener:GetScript("OnEvent")
        if listener and original then
            local function OnEvent(self, event, button, ...)
                if event == "GLOBAL_MOUSE_DOWN" and button == "LeftButton" then
                    -- A quick press can fall between two Zygor polls. Its unconsumed
                    -- skip belongs to the previous press, even if routing is now off.
                    if skippedZygorRelease then
                        skippedZygorRelease.IgnoreThisButtonDown = false
                        skippedZygorRelease = nil
                    end
                    local mode = Gesture()
                    local owner = Owner(mode)
                    shiftOwner = mode == "shift" and owner or nil
                    if shiftOwner then
                        local _, pointer = NS.GetZygorPointer()
                        if pointer and IsZygorRemovalClick(pointer) then
                            shiftOwner = "zygor"
                            return
                        end
                        if owner == "questierouter" and pointer then
                            local points = waypoints:All()
                            local first, second = points[1], points[2]
                            original(self, event, button, ...)
                            -- QuestieRouter keeps at most one Shift and one Alt point.
                            points = waypoints:All()
                            if first ~= points[1] or second ~= points[2] then SkipZygorRelease(pointer) end
                            return
                        end
                    end
                    if owner == "polestar" then return end
                end
                return original(self, event, button, ...)
            end
            if pcall(listener.SetScript, listener, "OnEvent", OnEvent) then questieListener = listener end
        end
    end
    InstallCanvas()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_REGEN_ENABLED" then
        Native.Changed()
        if questie then Native.InstallQuestieRouter(questie) end
    elseif addon == "Blizzard_WorldMap" then
        InstallCanvas()
    end
end)
