local NS = _G.AzerothWaypointNS

local state = NS.State

state.combatVisibility = state.combatVisibility or {
    combatEventActive = false,
    tomTomCloaked = false,
    tomTomRefreshHooked = false,
}

local guard = state.combatVisibility

local function IsInCombat()
    if guard.combatEventActive == true then
        return true
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() == true then
        return true
    end
    return type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") == true
end

local function ShouldHideTomTomNow()
    return IsInCombat()
        and type(NS.ShouldHideTomTomInCombat) == "function"
        and NS.ShouldHideTomTomInCombat() == true
end

local function ShouldHideWorldOverlayNow()
    return IsInCombat()
        and type(NS.ShouldHideWorldOverlayInCombat) == "function"
        and NS.ShouldHideWorldOverlayInCombat() == true
end

local function GetTomTom()
    if type(NS.GetTomTom) == "function" then
        return NS.GetTomTom()
    end
    return _G["TomTom"]
end

local function GetTomTomArrow()
    if type(NS.GetTomTomArrow) == "function" then
        return NS.GetTomTomArrow()
    end
    local tomtom = GetTomTom()
    return tomtom and tomtom.wayframe or nil
end

local function CloakTomTomArrow()
    local arrow = GetTomTomArrow()
    if type(arrow) ~= "table" then
        return
    end
    if type(arrow.SetAlpha) == "function" then
        arrow:SetAlpha(0)
    end
    if type(arrow.EnableMouse) == "function"
        and (not InCombatLockdown()
            or not (type(arrow.IsProtected) == "function" and arrow:IsProtected()))
    then
        arrow:EnableMouse(false)
    end
    guard.tomTomCloaked = true
end

local function RestoreTomTomArrow()
    if not guard.tomTomCloaked then
        return
    end
    if IsInCombat() then
        return
    end

    guard.tomTomCloaked = false

    local tomtom = GetTomTom()
    if tomtom and type(tomtom.ShowHideCrazyArrow) == "function" then
        tomtom:ShowHideCrazyArrow()
        return
    end

    local arrow = GetTomTomArrow()
    if type(arrow) ~= "table" then
        return
    end
    if type(arrow.SetAlpha) == "function" then
        arrow:SetAlpha(1)
    end
    if type(arrow.EnableMouse) == "function" then
        arrow:EnableMouse(true)
    end
end

local function ApplyTomTomCombatCloak()
    if ShouldHideTomTomNow() then
        CloakTomTomArrow()
    else
        RestoreTomTomArrow()
    end
end

local function HookTomTomCombatCloak()
    if guard.tomTomRefreshHooked then
        return
    end

    local tomtom = GetTomTom()
    if not tomtom or type(tomtom.ShowHideCrazyArrow) ~= "function" or type(hooksecurefunc) ~= "function" then
        return
    end

    guard.tomTomRefreshHooked = true
    hooksecurefunc(tomtom, "ShowHideCrazyArrow", function()
        if ShouldHideTomTomNow() then
            CloakTomTomArrow()
        end
    end)
end

local function ApplyTomTomGuard()
    HookTomTomCombatCloak()
    local hidden = ShouldHideTomTomNow()
    ApplyTomTomCombatCloak()
    if type(NS.ApplySpecialActionCombatVisibility) == "function" then
        NS.ApplySpecialActionCombatVisibility(hidden)
    end
end

function NS.IsTomTomCombatHidden()
    return ShouldHideTomTomNow()
end

function NS.IsWorldOverlayCombatHidden()
    return ShouldHideWorldOverlayNow()
end

function NS.SetCombatVisibilityEventActive(active)
    guard.combatEventActive = active and true or false
end

function NS.ApplyCombatVisibilityGuard()
    ApplyTomTomGuard()
    if type(NS.RefreshWorldOverlay) == "function" then
        NS.RefreshWorldOverlay()
    end
end
