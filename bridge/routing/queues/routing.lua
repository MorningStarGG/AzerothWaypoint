-- ============================================================
-- Queue routing and arrival
-- ============================================================
--
-- Turns queue selections into route requests and chooses the next destination
-- after arrival or corpse recovery.

local NS = _G.AzerothWaypointNS
local state = NS.State
local Queue = NS.RouteQueueInternal
if type(Queue) ~= "table" then
    Queue = {}
    NS.RouteQueueInternal = Queue
end
function Queue.GetQueueRouteItem(queue, itemIndex)
    if type(queue) ~= "table" or type(queue.items) ~= "table" then
        return nil, nil
    end
    itemIndex = tonumber(itemIndex) or tonumber(queue.activeItemIndex) or 1
    local item = queue.items[itemIndex]
    if type(item) ~= "table" then
        return nil, nil
    end
    return item, itemIndex
end

function Queue.BuildRouteRequestForQueue(queue, itemIndex)
    local item
    item, itemIndex = Queue.GetQueueRouteItem(queue, itemIndex)
    if type(item) ~= "table" then
        return nil
    end
    return {
        mapID = item.mapID,
        x = item.x,
        y = item.y,
        title = item.title,
        meta = Queue.BuildRouteMetaForQueueItem(item),
        queueContext = Queue.BuildQueueContext(queue, itemIndex),
    }
end

function Queue.BuildRouteRequestFromQueueID(queueID, itemIndex)
    local queue = Queue.GetQueueByID(queueID)
    if type(queue) ~= "table" then
        return nil
    end
    return Queue.BuildRouteRequestForQueue(queue, itemIndex)
end

local questContextFields = { "questID", "action", "entityKind", "entityID", "objectiveIndex", "objectiveType" }
local function SameQuestContext(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for _, key in ipairs(questContextFields) do if a[key] ~= b[key] then return false end end
    return true
end
local function ApplyClickedQuestContext(meta, clickedMeta)
    -- Reusing a saved stop keeps its identity/position, but a fresh click
    -- owns its quest role. Callers persist this only with the accepted plan.
    local identity = clickedMeta.identity
    if identity and identity.kind == "external_tomtom" and clickedMeta.sourceAddon == meta.sourceAddon
        and clickedMeta.manualQuestID == meta.manualQuestID
        and not SameQuestContext(clickedMeta.questContext, meta.questContext) then
        meta.questContext = clickedMeta.questContext
        return true
    end
    return false
end

function Queue.RouteQueueRequest(request, clickedMeta)
    if type(request) ~= "table" or type(NS.RouteViaBackend) ~= "function" then
        return false
    end
    if clickedMeta and request.meta then
        local override = NS.GetRouteBackendOverride(clickedMeta)
        local replaceContext = ApplyClickedQuestContext(request.meta, clickedMeta)
        if override ~= NS.GetRouteBackendOverride(request.meta) or replaceContext then
            local context = request.queueContext
            local queue = Queue.GetQueueByID(context.queueID)
            local item = Queue.GetQueueRouteItem(queue, context.queueItemIndex)
            if not item then return false end
            request.meta.backendOverride = override
            local commit = request.queueTransaction.commit
            request.queueTransaction.commit = function(record)
                -- Change a reused stop only after its replacement plan succeeds.
                local current = Queue.GetQueueByID(context.queueID)
                if Queue.GetQueueRouteItem(current, context.queueItemIndex) ~= item or commit(record) == false then
                    return false
                end
                item.meta.backendOverride = override
                if replaceContext then item.meta.questContext = request.meta.questContext end
            end
        end
    end
    return NS.RouteViaBackend(request.mapID, request.x, request.y, request.title, request.meta, {
        authority = "manual",
        queueContext = request.queueContext,
        queueTransaction = request.queueTransaction,
        strictRouteSuccess = true,
    })
end

-- ============================================================
-- Destination queue selection
-- ============================================================

function Queue.EnsureDestinationQueue(queue)
    if type(queue) ~= "table" then
        return nil
    end
    if queue.kind == "destination_queue" then
        return queue
    end
    queue.kind = "destination_queue"
    queue.readOnly = false
    return queue
end

function Queue.GetActiveNonTransientManualQueue()
    local manualQueues = Queue.GetManualQueueState()
    local queueID = manualQueues.activeQueueID
    if type(queueID) ~= "string" then
        return nil
    end
    return manualQueues.byID[queueID]
end

function Queue.GetCurrentNonTransientManualQueue()
    local record = type(NS.GetManualAuthority) == "function" and NS.GetManualAuthority() or nil
    local queueID = type(record) == "table" and record.queueID or nil
    local queue = type(queueID) == "string" and Queue.GetManualQueueByID(queueID) or nil
    if type(queue) == "table" then
        return queue
    end
    return Queue.GetActiveNonTransientManualQueue()
end

function Queue.FindSingleDestinationManualQueue(mapID, x, y, title, ignoredQueueID, meta)
    local manualQueues = Queue.GetManualQueueState()
    for index = 1, #manualQueues.order do
        local queueID = manualQueues.order[index]
        local queue = manualQueues.byID[queueID]
        if queueID ~= ignoredQueueID
            and type(queue) == "table"
            and type(queue.items) == "table"
            and #queue.items == 1
            and Queue.QueueItemMatchesDestination(queue.items[1], mapID, x, y, title, meta)
        then
            return queue, 1
        end
    end
    return nil
end

function Queue.ActivateAndRouteQueue(queue, itemIndex, clickedMeta)
    if type(queue) ~= "table" then
        return false
    end
    itemIndex = tonumber(itemIndex) or tonumber(queue.activeItemIndex) or 1
    local context = Queue.BuildQueueContext(queue, itemIndex)
    local transaction = Queue.CreateQueueTransaction("activate_queue", context, function()
        queue.activeItemIndex = itemIndex
        if queue.sourceType ~= "transient_source" then
            Queue.GetManualQueueState().activeQueueID = queue.id
        end
    end)
    local request = Queue.BuildRouteRequestForQueue(queue, itemIndex)
    if type(request) ~= "table" then
        return false
    end
    request.queueContext = context
    request.queueTransaction = transaction
    return Queue.RouteQueueRequest(request, clickedMeta)
end

function Queue.RouteSingleDestinationQueue(mapID, x, y, title, meta, sourceType, ignoredQueueID)
    local existingQueue, existingIndex = Queue.FindSingleDestinationManualQueue(mapID, x, y, title, ignoredQueueID, meta)
    if type(existingQueue) == "table" then
        return Queue.ActivateAndRouteQueue(existingQueue, existingIndex, meta)
    end

    local queue = Queue.CreateSingleDestinationQueue(mapID, x, y, title, meta, sourceType)
    local context = Queue.BuildQueueContext(queue, 1)
    local transaction = Queue.CreateQueueTransaction("add_queue", context, function()
        Queue.AddManualQueue(queue, true)
    end)
    local request = Queue.BuildRouteRequestForQueue(queue, 1)
    if type(request) ~= "table" then
        return false
    end
    request.queueContext = context
    request.queueTransaction = transaction
    return Queue.RouteQueueRequest(request)
end

function Queue.RouteQueueByID(queueID, itemIndex)
    local queue = Queue.GetQueueByID(queueID)
    if type(queue) ~= "table" then
        return false
    end
    itemIndex = tonumber(itemIndex) or queue.activeItemIndex or 1
    local context = Queue.BuildQueueContext(queue, itemIndex)
    local transaction = Queue.CreateQueueTransaction("activate_queue", context, function()
        queue.activeItemIndex = itemIndex
        if queue.sourceType ~= "transient_source" then
            Queue.GetManualQueueState().activeQueueID = queue.id
        end
    end)
    local request = Queue.BuildRouteRequestForQueue(queue, itemIndex)
    if type(request) ~= "table" then
        return false
    end
    request.queueContext = context
    request.queueTransaction = transaction
    return Queue.RouteQueueRequest(request)
end

-- ============================================================
-- Manual click policy and imports
-- ============================================================

function Queue.HandleManualClickMode(mode, mapID, x, y, title, meta, sourceType)
    sourceType = sourceType or "manual_click"
    local activeQueue = Queue.GetCurrentNonTransientManualQueue()

    if mode == "replace" and type(activeQueue) == "table" then
        local itemCount = #activeQueue.items
        local preserve = NS.IsManualQueuePreservationEnabled()
            and (activeQueue.sourceType == "imported" or itemCount > 1)
        local existingIndex = Queue.FindQueueItemByDestination(activeQueue, mapID, x, y, title, meta)
        if existingIndex and (preserve or itemCount == 1) then
            return Queue.ActivateAndRouteQueue(activeQueue, existingIndex, meta)
        end
        if preserve then
            return Queue.RouteSingleDestinationQueue(mapID, x, y, title, meta, sourceType)
        end
        local existingQueue, duplicateIndex = Queue.FindSingleDestinationManualQueue(mapID, x, y, title, activeQueue.id,
            meta)
        if type(existingQueue) == "table" then
            local context = Queue.BuildQueueContext(existingQueue, duplicateIndex)
            local transaction = Queue.CreateQueueTransaction("replace_with_existing_queue", context, function()
                Queue.DeleteManualQueue(activeQueue.id)
                existingQueue.activeItemIndex = duplicateIndex or existingQueue.activeItemIndex or 1
                Queue.GetManualQueueState().activeQueueID = existingQueue.id
            end)
            local request = Queue.BuildRouteRequestForQueue(existingQueue, duplicateIndex)
            if type(request) ~= "table" then
                return false
            end
            request.queueContext = context
            request.queueTransaction = transaction
            return Queue.RouteQueueRequest(request, meta)
        end

        local replacementQueue = Queue.CreateSingleDestinationQueue(mapID, x, y, title, meta, sourceType)
        local context = Queue.BuildQueueContext(replacementQueue, 1)
        local transaction = Queue.CreateQueueTransaction("replace_queue", context, function()
            Queue.DeleteManualQueue(activeQueue.id)
            Queue.AddManualQueue(replacementQueue, true)
        end)
        local request = Queue.BuildRouteRequestForQueue(replacementQueue, 1)
        if type(request) ~= "table" then
            return false
        end
        request.queueContext = context
        request.queueTransaction = transaction
        return Queue.RouteQueueRequest(request)
    elseif mode == "append" and type(activeQueue) == "table" then
        local existingIndex, existingItem = Queue.FindQueueItemByDestination(activeQueue, mapID, x, y, title, meta)
        local override = NS.GetRouteBackendOverride(meta)
        local function AppendOrUpdateStop(item)
            if item then
                item.meta.backendOverride = override
            else
                activeQueue.items[#activeQueue.items + 1] = Queue.BuildQueueItem(mapID, x, y, title, meta, sourceType)
            end
        end
        local record = type(NS.GetManualAuthority) == "function" and NS.GetManualAuthority() or nil
        if type(record) == "table" and record.queueID == activeQueue.id then
            if existingIndex and existingIndex == (record.queueItemIndex or activeQueue.activeItemIndex)
                and record.backendOverride ~= override
            then
                return Queue.ActivateAndRouteQueue(activeQueue, existingIndex, meta)
            end
            Queue.EnsureDestinationQueue(activeQueue)
            AppendOrUpdateStop(existingItem)
            record.queueKind = activeQueue.kind
            Queue.PersistManualQueues()
            Queue.RefreshQueueUI()
            if type(NS.RecomputeCarrier) == "function" then
                NS.RecomputeCarrier()
            end
            return true
        end

        local routeIndex = tonumber(activeQueue.activeItemIndex) or 1
        local context = Queue.BuildQueueContext(activeQueue, routeIndex)
        context.queueKind = "destination_queue"
        local transaction = Queue.CreateQueueTransaction("append_queue", context, function()
            Queue.EnsureDestinationQueue(activeQueue)
            local _, item = Queue.FindQueueItemByDestination(activeQueue, mapID, x, y, title, meta)
            AppendOrUpdateStop(item)
            activeQueue.activeItemIndex = routeIndex
            Queue.GetManualQueueState().activeQueueID = activeQueue.id
        end)
        local request = Queue.BuildRouteRequestForQueue(activeQueue, routeIndex)
        if type(request) ~= "table" then
            return false
        end
        request.queueContext = context
        request.queueTransaction = transaction
        return Queue.RouteQueueRequest(request, existingIndex == routeIndex and meta or nil)
    end

    return Queue.RouteSingleDestinationQueue(mapID, x, y, title, meta, sourceType)
end

function NS.RouteImportedWaypointBatch(entries)
    if type(entries) ~= "table" or type(entries[1]) ~= "table" then
        return false
    end
    local queue = Queue.CreateDestinationQueue(entries, "imported", entries[1].title)
    if #queue.items == 0 then
        return false
    end
    if #queue.items == 1 then
        local item = queue.items[1]
        local existingQueue, existingIndex = Queue.FindSingleDestinationManualQueue(item.mapID, item.x, item.y,
            item.title, nil, item.meta)
        if type(existingQueue) == "table" then
            return Queue.ActivateAndRouteQueue(existingQueue, existingIndex)
        end
    end
    -- Import the destinations before activation. The planner can wait, fail,
    -- or be superseded while the imported queue remains available.
    Queue.AddManualQueue(queue, false)
    Queue.ActivateAndRouteQueue(queue, 1)
    return true
end

function NS.PrepareManualQueueRouteRequest(mapID, x, y, title, meta, opts)
    state.routing.queueAfterCorpse = nil
    Queue.EnsureQueueState()
    if type(opts) == "table" and type(opts.queueContext) == "table" then
        return opts.queueContext, meta, opts.queueTransaction
    end

    local normalizedMeta = Queue.NormalizeQueueItemMeta(meta, mapID, x, y)
    local sourceType = Queue.InferQueueSourceType(normalizedMeta)

    if sourceType == "transient_source" then
        local sourceAddon = Queue.NormalizeSourceAddon(type(normalizedMeta) == "table" and normalizedMeta.sourceAddon or
            nil)
        local queue = Queue.CreateRouteQueue(mapID, x, y, title, normalizedMeta, "transient_source")
        queue.label = Queue.BuildQueueLabel("route", "transient_source", title or sourceAddon or "Transient Route",
            queue.id)
        queue.sourceAddon = sourceAddon
        local context = Queue.BuildQueueContext(queue, 1)
        local transaction = Queue.CreateQueueTransaction("push_transient_queue", context, function()
            Queue.PushTransientQueue(queue)
        end)
        return context, Queue.BuildRouteMetaForQueueItem(queue.items[1]), transaction
    end

    if type(opts) == "table" and type(opts.clickContext) == "table" then
        sourceType = "manual_click"
    end

    local existingQueue, existingIndex = Queue.FindSingleDestinationManualQueue(mapID, x, y, title, nil, normalizedMeta)
    if type(existingQueue) == "table" then
        existingIndex = existingIndex or existingQueue.activeItemIndex or 1
        local item = existingQueue.items[existingIndex]
        local override = NS.GetRouteBackendOverride(normalizedMeta)
        if override and not NS.RouteIdentitiesMatch(normalizedMeta.identity, item.meta and item.meta.identity) then
            existingQueue = nil
        end
    end
    if existingQueue then
        local item = existingQueue.items[existingIndex]
        local reusedMeta = Queue.BuildRouteMetaForQueueItem(item)
        local replaceContext = ApplyClickedQuestContext(reusedMeta, normalizedMeta)
        local override = NS.GetRouteBackendOverride(normalizedMeta)
        if override then reusedMeta.backendOverride = override end
        local context = Queue.BuildQueueContext(existingQueue, existingIndex)
        local transaction = Queue.CreateQueueTransaction("activate_existing_queue", context, function()
            if Queue.GetManualQueueByID(existingQueue.id) ~= existingQueue or existingQueue.items[existingIndex] ~= item then
                return false
            end
            if override then item.meta.backendOverride = override end
            if replaceContext then item.meta.questContext = reusedMeta.questContext end
            existingQueue.activeItemIndex = existingIndex
            Queue.GetManualQueueState().activeQueueID = existingQueue.id
        end)
        return context, reusedMeta, transaction
    end

    local queue = Queue.CreateSingleItemQueue(mapID, x, y, title, normalizedMeta, sourceType)
    local context = Queue.BuildQueueContext(queue, 1)
    local transaction = Queue.CreateQueueTransaction("add_manual_queue", context, function()
        Queue.AddManualQueue(queue, true)
    end)
    return context, Queue.BuildRouteMetaForQueueItem(queue.items[1]), transaction
end

-- ============================================================
-- Arrival and queue follow-up
-- ============================================================

function NS.GetManualQueueArrivalTarget(record)
    if type(record) ~= "table" or type(record.queueID) ~= "string" then
        return nil
    end
    local queue = Queue.GetQueueByID(record.queueID)
    if type(queue) ~= "table" or queue.kind ~= "destination_queue" then
        return nil
    end
    local itemIndex, item = Queue.FindQueueItemIndexForRecord(queue, record, record.queueItemIndex)
    if itemIndex then
        local changed = tonumber(record.queueItemIndex) ~= itemIndex
            or tonumber(queue.activeItemIndex) ~= itemIndex
        record.queueItemIndex = itemIndex
        queue.activeItemIndex = itemIndex
        if changed then
            Queue.PersistManualAuthorityIfAvailable()
            Queue.PersistManualQueues()
            Queue.RefreshQueueUI()
        end
    end
    if type(item) ~= "table" then
        return nil
    end
    return item
end

function NS.RouteQueueByID(queueID, itemIndex)
    return Queue.RouteQueueByID(queueID, itemIndex)
end

function NS.SetActiveManualQueue(queueID)
    local queue = Queue.GetManualQueueByID(queueID)
    if type(queue) ~= "table" then
        return false
    end
    return Queue.RouteQueueByID(queueID, queue.activeItemIndex or 1)
end

function NS.StopUsingManualQueue(queueID)
    local queue = Queue.GetManualQueueByID(queueID)
    if type(queue) ~= "table" then
        return false
    end

    local manualQueues = Queue.GetManualQueueState()
    local record = type(NS.GetManualAuthority) == "function" and NS.GetManualAuthority() or nil
    local isActiveRoute = type(record) == "table" and record.queueID == queueID
    local changed = manualQueues.activeQueueID == queueID

    if changed then
        manualQueues.activeQueueID = nil
        Queue.PersistManualQueues()
    end
    if type(NS.SetActiveRouteSource) == "function" then
        NS.SetActiveRouteSource("guide")
    end

    local clearedRoute = false
    if isActiveRoute then
        if type(NS.ClearManualRoute) == "function" then
            clearedRoute = NS.ClearManualRoute("queue_stop", {
                preserveManualQueue = true,
                queueFollowup = false,
            }) == true
        elseif type(NS.ClearManualAuthority) == "function" then
            NS.ClearManualAuthority("queue_stop")
            clearedRoute = true
        end
    elseif changed and type(NS.RecomputeCarrier) == "function" then
        NS.RecomputeCarrier()
    end

    Queue.RefreshQueueUI()
    return changed or clearedRoute
end

function Queue.BuildDestinationQueueFollowupRequest(queue, itemIndex)
    if type(queue) ~= "table" or type(queue.items) ~= "table" then
        return nil
    end
    itemIndex = tonumber(itemIndex) or tonumber(queue.activeItemIndex) or 1
    local itemCount = #queue.items
    if itemCount <= 1 then
        return nil
    end

    local nextOldIndex = itemIndex < itemCount and itemIndex + 1 or 1
    local nextNewIndex = itemIndex < itemCount and itemIndex or 1
    local currentItem, nextItem = queue.items[itemIndex], queue.items[nextOldIndex]
    if type(currentItem) ~= "table" or type(nextItem) ~= "table" then
        return nil
    end

    local context = Queue.BuildQueueContext(queue, nextNewIndex)
    local transaction = Queue.CreateQueueTransaction("advance_destination_queue", context, function(record)
        if Queue.GetManualQueueByID(queue.id) ~= queue then return false end
        -- A queue can be edited while the next route is being planned.
        local reached, nextIndex
        for index, item in ipairs(queue.items) do
            if item == currentItem then reached = index end
            if item == nextItem then nextIndex = index end
            if reached and nextIndex then break end
        end
        if not nextIndex then return false end
        if reached then
            table.remove(queue.items, reached)
            if reached < nextIndex then nextIndex = nextIndex - 1 end
        end
        record.queueItemIndex = nextIndex
        queue.activeItemIndex = nextIndex
        Queue.GetManualQueueState().activeQueueID = queue.id
    end)
    transaction.reachedItem = currentItem

    return {
        mapID = nextItem.mapID,
        x = nextItem.x,
        y = nextItem.y,
        title = nextItem.title,
        meta = Queue.BuildRouteMetaForQueueItem(nextItem),
        queueContext = context,
        queueTransaction = transaction,
    }
end

function NS.ResolveManualQueueFollowup(record)
    if type(record) ~= "table" or type(record.queueID) ~= "string" then
        return nil
    end

    local queueID = record.queueID
    local queue = Queue.GetQueueByID(queueID)
    if type(queue) ~= "table" then
        return nil
    end

    if queue.sourceType == "transient_source" then
        Queue.PopTransientQueue(queueID)
        local stack = Queue.GetTransientQueueStack()
        local previous = stack[#stack] or Queue.GetManualQueueByID(queue.resumeManualQueueID)
        if previous and record.identity and record.identity.destinationKind == "corpse"
            and UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
            state.routing.queueAfterCorpse = previous
            return nil
        end
        return Queue.BuildRouteRequestForQueue(previous)
    end

    if queue.kind == "destination_queue" then
        local itemIndex = Queue.FindQueueItemIndexForRecord(queue, record, record.queueItemIndex)
        if not itemIndex then
            return nil
        end
        local request = Queue.BuildDestinationQueueFollowupRequest(queue, itemIndex)
        if request then
            return request
        end
        Queue.RemoveQueueItemAt(queue, itemIndex)
        return nil
    end

    Queue.DeleteManualQueue(queueID)
    return nil
end

function NS.ResumeQueueAfterCorpse()
    local routing = state.routing
    local previous = routing.queueAfterCorpse
    if not previous or UnitIsDeadOrGhost("player") then return end
    routing.queueAfterCorpse = nil
    local stack = Queue.GetTransientQueueStack()
    if (stack[#stack] or Queue.GetActiveNonTransientManualQueue()) == previous
        and not routing.manualAuthority and not routing.pendingManualAuthority and NS.IsRoutingEnabled() then
        Queue.RouteQueueRequest(Queue.BuildRouteRequestForQueue(previous))
    end
end
