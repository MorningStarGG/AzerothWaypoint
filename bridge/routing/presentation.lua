local NS = _G.AzerothWaypointNS
local state = NS.State

-- ============================================================
-- Presentation resolver
-- ============================================================
--
-- AWP's pushed snapshot must satisfy the existing native overlay and
-- diagnostics consumers. This keeps the push-driven model and
-- uses richer content snapshot fields they already understand.


local _contentSigParts = {}

local function TrimString(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return nil end
    return value
end

local function NormalizeCompareText(value)
    value = TrimString(value)
    if not value then return nil end
    value = value:lower()
    value = value:gsub("%s+", " ")
    return value
end

local function IsSameDisplayText(a, b)
    local left = NormalizeCompareText(a)
    local right = NormalizeCompareText(b)
    return left ~= nil and right ~= nil and left == right
end

local function NormalizeSourceAddon(sourceAddon)
    sourceAddon = TrimString(sourceAddon)
    if not sourceAddon then return nil end
    local externalSource = type(NS.NormalizeExternalWaypointSource) == "function"
        and NS.NormalizeExternalWaypointSource(sourceAddon)
        or nil
    if externalSource then
        return externalSource
    end
    return sourceAddon
end

local function ResolveGuideProvider(authority)
    if type(authority) == "table" then
        local provider = TrimString(authority.guideProvider)
            or TrimString(authority.provider)
        if provider then
            return provider
        end
    end

    local routing = state.routing or {}
    local activeProvider = type(NS.GetActiveGuideProvider) == "function" and TrimString(NS.GetActiveGuideProvider()) or
        nil
    if activeProvider then
        return activeProvider
    end
    local guideQueue = NS.RouteQueueInternal.GetActiveGuideQueue()
    return guideQueue and TrimString(guideQueue.provider) or nil
end

-- ============================================================
-- Carrier titles and semantic icons
-- ============================================================

local function ResolveSemanticTravelType(action)
    if type(action) ~= "table" then
        return nil
    end
    if action.semanticKind == "portal"
        or action.semanticKind == "hearth"
        or action.semanticKind == "taxi"
        or action.semanticKind == "travel"
    then
        return action.semanticKind
    end
    if action.semanticKind == "spell"
        or action.semanticKind == "item"
        or action.semanticKind == "toy"
        or action.semanticKind == "macro"
    then
        return "travel"
    end
    return nil
end

local function ResolveCarrierTitle(action, carrier, authorityTitle)
    if type(action) == "table" and TrimString(action.name) then
        return TrimString(action.name)
    end
    if type(carrier) == "table" and TrimString(carrier.title) then
        return TrimString(carrier.title)
    end
    if TrimString(authorityTitle) then
        return TrimString(authorityTitle)
    end
    return "AWP Route"
end

local function ResolveOverlayTitle(action, carrier, authorityTitle, routeLegKind)
    if routeLegKind == "carrier" then
        return ResolveCarrierTitle(action, carrier, authorityTitle)
    end
    if type(action) == "table" and TrimString(action.destinationName) then
        return TrimString(action.destinationName)
    end
    if type(carrier) == "table"
        and carrier.routeLegKind == "carrier"
        and TrimString(carrier.title)
    then
        return TrimString(carrier.title)
    end
    if TrimString(authorityTitle) then
        return TrimString(authorityTitle)
    end
    if type(carrier) == "table" and TrimString(carrier.title) then
        return TrimString(carrier.title)
    end
    return nil
end

local function ResolveOverlaySubtext(action, overlayTitle, routeLegKind)
    if type(action) ~= "table" then
        return nil
    end

    if routeLegKind == "carrier" then
        local destinationName = TrimString(action.destinationName)
        if destinationName and not IsSameDisplayText(destinationName, overlayTitle) then
            return destinationName
        end
        return nil
    end

    local actionName = TrimString(action.name)
    if actionName
        and action.destinationName ~= nil
        and not IsSameDisplayText(actionName, overlayTitle)
    then
        return actionName
    end
    return nil
end

local function ResolveInstanceTravelIconOverride(liveTravelType, routeTravelType)
    if liveTravelType ~= "portal" then
        return liveTravelType
    end

    if NS.IsInstanceRouteTravelType(routeTravelType) then
        return routeTravelType
    end

    return liveTravelType
end

local function NormalizeRouteTravelType(routeTravelType, routeLegKind, plannerLegKind)
    return NS.ResolveCarrierTravelType(TrimString(routeTravelType), routeLegKind, TrimString(plannerLegKind))
end

local function ResolvePresentationIconHint(targetKind, snapshot, liveTravelType, liveTravelConfidence, searchKind,
                                           manualQuestID, mapPinInfo)
    if targetKind == "manual" then
        if type(manualQuestID) == "number" and manualQuestID > 0 then
            return "quest", manualQuestID
        end
        if type(mapPinInfo) == "table" and mapPinInfo.kind == "taxi_node" then
            return "taxi", nil
        end
        if type(mapPinInfo) == "table" and mapPinInfo.kind == "area_poi" then
            if type(NS.ResolveAreaPoiTravelType) == "function" then
                local travelType = NS.ResolveAreaPoiTravelType(
                    mapPinInfo.mapID,
                    mapPinInfo.x,
                    mapPinInfo.y,
                    mapPinInfo.mapPinID
                )
                if type(travelType) == "string" then
                    return travelType, nil
                end
            end
            return "area_poi", nil
        end
        if type(mapPinInfo) == "table" and mapPinInfo.kind == "dig_site" then
            return "dig_site", nil
        end
        if type(mapPinInfo) == "table" and mapPinInfo.kind == "housing_plot" then
            local ownerType = mapPinInfo.ownerType
            if ownerType == 3 then return "housing_plot_own", nil end
            if ownerType == 0 then return "housing_plot_unoccupied", nil end
            return "housing_plot_occupied", nil
        end
        return (type(searchKind) == "string" and searchKind or "manual"), nil
    end

    if targetKind == "corpse" then
        return "corpse", nil
    end

    if type(snapshot) ~= "table" then
        return nil, nil
    end

    local isCarrierTravelPresentation = targetKind == "route" or snapshot.routeLegKind == "carrier"
    local resolvedLiveTravelType = liveTravelConfidence == "high"
        and type(liveTravelType) == "string"
        and liveTravelType
        or nil
    local routeTravelType = type(snapshot.routeTravelType) == "string"
        and snapshot.routeTravelType
        or nil
    if isCarrierTravelPresentation then
        resolvedLiveTravelType = ResolveInstanceTravelIconOverride(resolvedLiveTravelType, routeTravelType)
        if type(resolvedLiveTravelType) == "string" then
            return resolvedLiveTravelType, nil
        end
    end

    local semanticQuestID = type(snapshot.semanticQuestID) == "number"
        and snapshot.semanticQuestID > 0
        and snapshot.semanticQuestID
        or nil
    if snapshot.semanticKind == "quest" and (semanticQuestID or snapshot.iconHintKind == "quest") then
        return "quest", semanticQuestID
    end

    local semanticTravelType = type(snapshot.semanticTravelType) == "string" and snapshot.semanticTravelType or nil
    if semanticTravelType then
        return semanticTravelType, nil
    end

    if targetKind == "guide" then
        return "guide", nil
    end

    return nil, nil
end

-- ============================================================
-- Snapshot fields and signatures
-- ============================================================

local function ResolveSnapshotContentSig(snapshot)
    _contentSigParts[1] = tostring(snapshot.guideRoutePresentation == true)
    _contentSigParts[2] = tostring(snapshot.liveTravelType or "")
    _contentSigParts[3] = tostring(snapshot.routeGoalMapID or "")
    _contentSigParts[4] = tostring(snapshot.routeLegKind or "")
    _contentSigParts[5] = tostring(snapshot.routeTravelType or "")
    _contentSigParts[6] = tostring(snapshot.sourceAddon or "")
    _contentSigParts[7] = tostring(snapshot.searchKind or "")
    _contentSigParts[8] = tostring(snapshot.manualQuestID or "")
    _contentSigParts[9] = tostring(snapshot.mapPinKind or "")
    _contentSigParts[10] = tostring(snapshot.mapPinID or "")
    _contentSigParts[11] = tostring(snapshot.semanticKind or "")
    _contentSigParts[12] = tostring(snapshot.semanticQuestID or "")
    _contentSigParts[13] = tostring(snapshot.semanticTravelType or "")
    _contentSigParts[14] = tostring(snapshot.pinpointSubtext or snapshot.overlaySubtext or "")
    _contentSigParts[15] = tostring(snapshot.guideProvider or "")
    _contentSigParts[16] = tostring(snapshot.sourceAddonIconKey or "")
    _contentSigParts[17] = tostring(snapshot.iconHintKind or "")
    _contentSigParts[18] = tostring(snapshot.iconHintQuestID or "")
    _contentSigParts[19] = tostring(snapshot.iconHintAtlas or "")
    _contentSigParts[20] = tostring(snapshot.iconHintTextureIndex or "")
    return table.concat(_contentSigParts, "\031", 1, 20)
end

local function FillMapPinFields(snapshot, mapPinInfo)
    if type(mapPinInfo) ~= "table" then
        return
    end

    snapshot.mapPinKind = TrimString(mapPinInfo.kind)
    snapshot.mapPinType = type(mapPinInfo.mapPinType) == "number" and mapPinInfo.mapPinType or nil
    snapshot.mapPinID = type(mapPinInfo.mapPinID) == "number" and mapPinInfo.mapPinID or nil
    snapshot.iconHintAtlas = TrimString(mapPinInfo.atlas)
    snapshot.iconHintRawAtlas = TrimString(mapPinInfo.rawAtlas)
    snapshot.iconHintTextureIndex = type(mapPinInfo.textureIndex) == "number"
        and mapPinInfo.textureIndex > 0
        and mapPinInfo.textureIndex
        or nil
    snapshot.mapPinDescription = TrimString(mapPinInfo.description)
    snapshot.mapPinIsCurrentEvent = mapPinInfo.isCurrentEvent == true or nil
    snapshot.mapPinTooltipWidgetSet = type(mapPinInfo.tooltipWidgetSet) == "number"
        and mapPinInfo.tooltipWidgetSet
        or nil
end

local function ComputeOverlaySig(carrierSig, snapshot)
    local baseSig = carrierSig
    if type(baseSig) ~= "string" then
        return nil
    end
    return table.concat({
        baseSig,
        snapshot.contentSig,
        tostring(snapshot.mirrorTitle or snapshot.overlayTitle or ""),
        tostring(snapshot.overlaySubtext or ""),
    }, "\031", 1, 4)
end

local function ResolveGuideRouteSnapshot(authority, carrier, targetKind, routeLegKind, routeTravelType, rawArrowTitle)
    if type(carrier) ~= "table" or carrier.source ~= "guide" then
        return nil
    end
    local target = type(authority) == "table" and authority.target or nil
    local mapID = type(carrier.finalMapID) == "number" and carrier.finalMapID or target and target.mapID
    local x = type(carrier.finalX) == "number" and carrier.finalX or target and target.x
    local y = type(carrier.finalY) == "number" and carrier.finalY or target and target.y
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return nil
    end

    local provider = ResolveGuideProvider(authority)
    if provider ~= "zygor" or type(NS.ResolveGuideContentSnapshot) ~= "function" then
        local authoritySemanticQuestID = type(authority) == "table" and rawget(authority, "semanticQuestID") or nil
        local authorityIconHintQuestID = type(authority) == "table" and rawget(authority, "iconHintQuestID") or nil
        local targetSemanticQuestID = target and rawget(target, "semanticQuestID") or nil
        local targetIconHintQuestID = target and rawget(target, "iconHintQuestID") or nil
        local title = TrimString(target and target.title)
            or TrimString(authority and authority.title)
            or TrimString(rawArrowTitle)
            or TrimString(target and target.rawTitle)
            or "Guide step"
        local subtext = TrimString(authority and authority.subtext) or TrimString(target and target.subtext)
        local subtextReason = subtext and "instruction" or nil
        local common = NS.Internal.GuidePresentation
        if common and (routeLegKind == "destination" or routeLegKind == nil and targetKind ~= "route") then
            subtext, subtextReason = common.DestinationSubtext(subtext, x, y)
        end
        local adapter = type(NS.GetGuideTargetProvider) == "function" and NS.GetGuideTargetProvider(provider)
        if adapter and adapter.structuredPresentation then
            local semantics = common.BuildSemanticInfo(
                TrimString(authority and authority.semanticKind) or TrimString(target and target.semanticKind),
                TrimString(authority and authority.semanticTravelType) or
                TrimString(target and target.semanticTravelType),
                authoritySemanticQuestID or targetSemanticQuestID)
            local snapshot = common.BuildSnapshot(carrier.title or rawArrowTitle, title, subtext,
                provider, subtextReason, nil, nil, semantics)
            snapshot.guideProvider = provider
            snapshot.iconHintKind = TrimString(authority and authority.iconHintKind) or
                TrimString(target and target.iconHintKind)
            snapshot.iconHintQuestID = authorityIconHintQuestID or targetIconHintQuestID
            common.ApplyRoutePolicy(snapshot, {
                kind = targetKind, legKind = routeLegKind, routeTravelType = routeTravelType,
            })
            if snapshot.routePresentationAllowed == false then return nil end
            return snapshot
        end
        return {
            mirrorTitle = title,
            overlayTitle = title,
            overlaySubtext = subtext,
            pinpointSubtext = subtext,
            guideProvider = provider,
            semanticKind = TrimString(authority and authority.semanticKind) or TrimString(target and target.semanticKind),
            semanticQuestID = type(authoritySemanticQuestID) == "number" and authoritySemanticQuestID
                or type(targetSemanticQuestID) == "number" and targetSemanticQuestID
                or nil,
            semanticTravelType = TrimString(authority and authority.semanticTravelType) or
                TrimString(target and target.semanticTravelType),
            iconHintKind = TrimString(authority and authority.iconHintKind) or TrimString(target and target.iconHintKind),
            iconHintQuestID = type(authorityIconHintQuestID) == "number" and authorityIconHintQuestID
                or type(targetIconHintQuestID) == "number" and targetIconHintQuestID
                or nil,
            routePresentationAllowed = true,
            contentSig = table.concat({
                tostring(provider or "guide"),
                tostring(mapID),
                tostring(type(x) == "number" and string.format("%.5f", x) or "-"),
                tostring(type(y) == "number" and string.format("%.5f", y) or "-"),
                tostring(title),
                tostring(subtext or ""),
            }, "\031", 1, 6),
        }
    end

    local snapshot = NS.ResolveGuideContentSnapshot({
        rawArrowTitle = rawArrowTitle,
        mapID = mapID,
        x = x,
        y = y,
        sig = carrier.sig,
        kind = targetKind,
        legKind = routeLegKind,
        routeTravelType = routeTravelType,
        source = type(authority) == "table" and authority.guideSource
            or target and target.source
            or carrier.source,
    })
    if type(snapshot) ~= "table" then return nil end
    if snapshot.routePresentationAllowed == false then return nil, snapshot end
    return snapshot, snapshot
end

-- ============================================================
-- Active route presentation
-- ============================================================

function NS.ResolvePresentation(carrier)
    local routing = state.routing or {}
    carrier = carrier or routing.carrierState
    local action = routing.specialActionState
    local authority = carrier and carrier.authority
        or carrier and carrier.source == "manual" and routing.manualAuthority
        or
        carrier and carrier.source == "guide" and
        (type(NS.GetActiveGuideRouteState) == "function" and NS.GetActiveGuideRouteState() or routing.guideRouteState)
        or nil

    if not carrier or not authority then
        return { guideRoutePresentation = false }
    end

    -- The overlay may retain this snapshot after another route is resolved.
    local snapshot = {}
    local targetKind = carrier.kind or (carrier.source == "guide" and "guide" or "manual")
    local routeLegKind = carrier.routeLegKind
    local routeTravelType = NormalizeRouteTravelType(carrier.routeTravelType, routeLegKind, carrier.plannerLegKind)
    local authorityTitle = authority.title or (authority.target and authority.target.title) or nil
    local manualQuestID = carrier.source == "manual" and authority.manualQuestID or nil
    local searchKind = carrier.source == "manual" and authority.searchKind or nil
    local mapPinInfo = carrier.source == "manual" and authority.mapPinInfo or nil
    local semanticTravelType = ResolveSemanticTravelType(action)
    local isCarrierTravelPresentation = targetKind == "route" or routeLegKind == "carrier"
    local liveTravelType = semanticTravelType or (isCarrierTravelPresentation and routeTravelType or nil)
    local liveTravelConfidence = liveTravelType and "high" or nil
    local guideSnapshot, walkingContext = ResolveGuideRouteSnapshot(
        authority,
        carrier,
        targetKind,
        routeLegKind,
        routeTravelType,
        TrimString(authority.rawTitle) or TrimString(carrier.title) or TrimString(authorityTitle)
    )

    snapshot.carrierTitle = ResolveCarrierTitle(action, carrier, authorityTitle)
    snapshot.overlayTitle = ResolveOverlayTitle(action, carrier, authorityTitle, routeLegKind)
    snapshot.overlaySubtext = ResolveOverlaySubtext(action, snapshot.overlayTitle, routeLegKind)
    if guideSnapshot then
        local guideSubtext = TrimString(guideSnapshot.pinpointSubtext)
        if routeLegKind == "carrier" then
            if NS.IsInstanceRouteTravelType(routeTravelType) and guideSubtext then
                snapshot.overlaySubtext = guideSubtext
            end
        else
            snapshot.overlayTitle = TrimString(guideSnapshot.mirrorTitle) or snapshot.overlayTitle
            snapshot.overlaySubtext = guideSubtext or snapshot.overlaySubtext
        end
    end
    snapshot.pinpointSubtext = snapshot.overlaySubtext
    local walking = authority.currentLeg and authority.currentLeg.walkingDescription
        and NS.Internal.RouteWalkingPresentation.Resolve(authority, authority.currentLeg, walkingContext or guideSnapshot)
    if walking then
        snapshot.carrierTitle, snapshot.overlayTitle = walking.title, walking.title
        snapshot.overlaySubtext, snapshot.pinpointSubtext = walking.subtext, walking.subtext
    end
    if manualQuestID and not isCarrierTravelPresentation and NS.ResolveQuestPresentation then
        local quest = NS.ResolveQuestPresentation(manualQuestID, authorityTitle, authority)
        if quest then
            snapshot.overlayTitle = quest.title or snapshot.overlayTitle
            snapshot.overlaySubtext, snapshot.pinpointSubtext = quest.subtext, quest.subtext
        end
    end
    snapshot.specialAction = action
    snapshot.carrierSig = carrier.sig
    snapshot.sourceAddon = NormalizeSourceAddon(authority.sourceAddon)
    snapshot.sourceAddonIconKey = TrimString(authority.sourceAddonIconKey)
    snapshot.guideProvider = carrier.source == "guide" and ResolveGuideProvider(authority) or nil
    snapshot.searchKind = type(searchKind) == "string" and searchKind or nil
    snapshot.manualQuestID = type(manualQuestID) == "number" and manualQuestID > 0 and manualQuestID or nil
    snapshot.guideRoutePresentation = carrier.source == "guide"
    snapshot.liveTravelType = liveTravelConfidence == "high" and liveTravelType or nil
    snapshot.routeGoalMapID = carrier.finalMapID
    snapshot.routeLegKind = routeLegKind
    snapshot.routeTravelType = routeTravelType
    snapshot.semanticKind = type(action) == "table" and action.semanticKind
        or targetKind == "corpse" and "corpse"
        or snapshot.manualQuestID and "quest"
        or nil
    snapshot.semanticQuestID = snapshot.manualQuestID
    snapshot.semanticTravelType = semanticTravelType
    if guideSnapshot then
        snapshot.semanticKind = TrimString(guideSnapshot.semanticKind) or snapshot.semanticKind
        snapshot.iconHintKind = guideSnapshot.iconHintKind
        snapshot.semanticQuestID = type(guideSnapshot.semanticQuestID) == "number"
            and guideSnapshot.semanticQuestID > 0
            and guideSnapshot.semanticQuestID
            or snapshot.semanticQuestID
        snapshot.semanticTravelType = TrimString(guideSnapshot.semanticTravelType)
            or snapshot.semanticTravelType
    end
    if carrier.source == "guide" and routeLegKind == "carrier" and liveTravelType
        and not NS.IsInstanceRouteTravelType(liveTravelType)
    then
        snapshot.semanticKind = "travel"
        snapshot.semanticQuestID = nil
        snapshot.semanticTravelType = liveTravelType
    end
    snapshot.mirrorTitle = snapshot.overlayTitle
    snapshot.carrierTitle = snapshot.overlayTitle or snapshot.carrierTitle

    FillMapPinFields(snapshot, mapPinInfo)

    snapshot.iconHintKind, snapshot.iconHintQuestID = ResolvePresentationIconHint(
        targetKind,
        snapshot,
        snapshot.liveTravelType,
        liveTravelConfidence,
        snapshot.searchKind,
        snapshot.manualQuestID,
        mapPinInfo
    )
    snapshot.iconHint = snapshot.iconHintKind
    snapshot.contentSig = ResolveSnapshotContentSig(snapshot)
    snapshot.overlaySig = ComputeOverlaySig(carrier.sig, snapshot)
    return snapshot
end
