local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

local CreateFrame = _G.CreateFrame

NS.Internal = NS.Internal or {}
NS.Internal.ZygorTrackerViewer = NS.Internal.ZygorTrackerViewer or {}

local Shared = NS.Internal.ZygorTrackerViewer
local Host = Shared.TrackerHost
local Shim = {}
Shared.TrackerSecretShim = Shim

-- ============================================================
-- Secret-safe shim for Blizzard's objective tracker
-- ============================================================
--
-- Docking a module into Blizzard's ObjectiveTrackerFrame taints its update
-- pass. The container reads uiOrder / hasDisplayPriority off every module in
-- turn, and AWP's module frame carries AWP taint, so the pass is tainted from
-- the moment our entry is read. Nothing an addon can do removes that -- see
-- testing.md for the confirmed chain.
--
-- In 12.1 two Blizzard call sites cannot survive that taint:
--
--   * ShouldShowMawBuffs() reads auras via GetAuraDataByIndex, which raises an
--     error when the auras are secret. It is called from
--     ScenarioObjectiveTracker:LayoutContents -- inside the container's module
--     loop, so the error aborts the loop and every module after the scenario
--     one stops updating -- and again from its UNIT_AURA OnEvent handler.
--   * ScenarioSpellButtonMixin:UpdateCooldown hands secret startTime/duration
--     to CooldownFrame_Set, which compares them.
--
-- Both are wrapped below: run Blizzard's original first, and fall back to a
-- secret-free path only when it actually raises. Behavior is therefore
-- unchanged in every case except a tainted read of a secret value.
--
-- Installed only while the module is attached to Blizzard's tracker. Never
-- under Kaliel's Tracker, which deactivates Blizzard's tracker and ships its
-- own aura-free ShouldShowMawBuffs. Installing unconditionally would taint
-- ShouldShowMawBuffs for players who never enable the Tracker Viewer and cause
-- the very failure this exists to prevent.

local installed = false
local originalShouldShowMawBuffs
local originalUpdateCooldown
local mawBuffsFallbackLatched = false
local watcher

-- ============================================================
-- Shim A - ShouldShowMawBuffs
-- ============================================================

local function SafeShouldShowMawBuffs(...)
    -- Once the aura read has failed, stop paying for a raise-and-catch on every
    -- layout pass. LayoutContents runs on each tracker update, so in sustained
    -- combat that cost is not trivial. The latch clears when combat ends.
    if not mawBuffsFallbackLatched then
        if type(originalShouldShowMawBuffs) ~= "function" then return false end
        local ok, result = pcall(originalShouldShowMawBuffs, ...)
        if ok then return result end
        mawBuffsFallbackLatched = true
    end

    -- Without aura access the zone check is the closest honest answer, and it
    -- is what Kaliel's Tracker substitutes in its own fork.
    local inTower = rawget(_G, "IsInJailersTower")
    if type(inTower) ~= "function" then return false end
    local ok, result = pcall(inTower)
    return ok and result or false
end

-- ============================================================
-- Shim B - ScenarioSpellButtonMixin:UpdateCooldown
-- ============================================================

local function SafeUpdateCooldown(self)
    if type(originalUpdateCooldown) == "function" then
        if pcall(originalUpdateCooldown, self) then return end
    end

    -- CooldownFrame_Set compares start against duration, which is illegal on
    -- secret values from tainted code. Hand them straight to the Cooldown frame
    -- instead. If it rejects secrets too, leave the swirl as it is rather than
    -- letting the error escape into the tracker's layout pass.
    local cooldown = type(self) == "table" and self.Cooldown or nil
    if not cooldown or type(cooldown.SetCooldown) ~= "function" then return end

    local spellID = self.spellID
    if not spellID then return end

    local spellAPI = rawget(_G, "C_Spell")
    if type(spellAPI) ~= "table" or type(spellAPI.GetSpellCooldown) ~= "function" then return end

    local ok, info = pcall(spellAPI.GetSpellCooldown, spellID)
    if not ok or type(info) ~= "table" then return end

    pcall(cooldown.SetCooldown, cooldown, info.startTime, info.duration)
end

-- XML mixins are copied onto each frame at creation, so replacing the mixin
-- table does not reach spell buttons that already exist. Blizzard's own module
-- reload path has the same problem and solves it by re-pushing; do the same for
-- both active and pooled-inactive frames, since Acquire() hands the inactive
-- ones back out unchanged.
local function ForEachScenarioSpellButton(callback)
    local tracker = rawget(_G, "ScenarioObjectiveTracker")
    local pool = type(tracker) == "table" and tracker.spellFramePool or nil
    if type(pool) ~= "table" then return end

    if type(pool.EnumerateActive) == "function" then
        pcall(function()
            for frame in pool:EnumerateActive() do
                local button = type(frame) == "table" and frame.SpellButton or nil
                if button then callback(button) end
            end
        end)
    end

    if type(pool.inactiveObjects) == "table" then
        for _, frame in ipairs(pool.inactiveObjects) do
            local button = type(frame) == "table" and frame.SpellButton or nil
            if button then callback(button) end
        end
    end
end

-- ============================================================
-- Install / Uninstall
-- ============================================================

-- Both targets can appear or be replaced after we install: Blizzard_MawBuffs is
-- a separate load-on-demand addon that defines ShouldShowMawBuffs when it loads,
-- and Blizzard_ObjectiveTracker brings ScenarioSpellButtonMixin with it. Whoever
-- currently owns the value becomes our original, so re-running this chains onto a
-- later definition instead of clobbering it.
local function ApplyHooks()
    local mawBuffs = rawget(_G, "ShouldShowMawBuffs")
    if type(mawBuffs) == "function" and mawBuffs ~= SafeShouldShowMawBuffs then
        originalShouldShowMawBuffs = mawBuffs
        _G.ShouldShowMawBuffs = SafeShouldShowMawBuffs
    end

    local mixin = rawget(_G, "ScenarioSpellButtonMixin")
    if type(mixin) == "table"
        and type(mixin.UpdateCooldown) == "function"
        and mixin.UpdateCooldown ~= SafeUpdateCooldown
    then
        originalUpdateCooldown = mixin.UpdateCooldown
        mixin.UpdateCooldown = SafeUpdateCooldown
        ForEachScenarioSpellButton(function(button)
            button.UpdateCooldown = SafeUpdateCooldown
        end)
    end
end

local function EnsureWatcher()
    if watcher then return end
    watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            -- Auras stop being secret out of combat, so let the real
            -- ShouldShowMawBuffs answer again on the next pass.
            mawBuffsFallbackLatched = false
        elseif installed then
            -- A late-loading addon may have defined either target after we
            -- installed, dropping our wrapper out of the call path.
            ApplyHooks()
        end
    end)
end

function Shim.Install()
    if installed then return false end
    -- KT deactivates Blizzard's tracker and already ships an aura-free
    -- ShouldShowMawBuffs, so there is nothing here to protect.
    if type(Host.IsKTLoaded) == "function" and Host.IsKTLoaded() then return false end

    ApplyHooks()
    EnsureWatcher()
    installed = true
    return true
end

function Shim.Uninstall()
    if not installed then return false end
    installed = false
    mawBuffsFallbackLatched = false

    if type(originalShouldShowMawBuffs) == "function"
        and rawget(_G, "ShouldShowMawBuffs") == SafeShouldShowMawBuffs
    then
        _G.ShouldShowMawBuffs = originalShouldShowMawBuffs
    end
    originalShouldShowMawBuffs = nil

    local mixin = rawget(_G, "ScenarioSpellButtonMixin")
    if type(originalUpdateCooldown) == "function"
        and type(mixin) == "table"
        and mixin.UpdateCooldown == SafeUpdateCooldown
    then
        local restore = originalUpdateCooldown
        mixin.UpdateCooldown = restore
        ForEachScenarioSpellButton(function(button)
            if button.UpdateCooldown == SafeUpdateCooldown then
                button.UpdateCooldown = restore
            end
        end)
    end
    originalUpdateCooldown = nil

    return true
end

function Shim.IsInstalled()
    return installed == true
end

-- Diagnostics: reports whether the shim is live, whether the aura fallback has
-- latched this combat, and whether the globals still point at our wrappers.
function Shim.GetStatus()
    local mixin = rawget(_G, "ScenarioSpellButtonMixin")
    return {
        installed       = installed == true,
        fallbackLatched = mawBuffsFallbackLatched == true,
        mawBuffsHooked  = rawget(_G, "ShouldShowMawBuffs") == SafeShouldShowMawBuffs,
        cooldownHooked  = type(mixin) == "table" and mixin.UpdateCooldown == SafeUpdateCooldown,
    }
end

NS.GetTrackerSecretShimStatus = Shim.GetStatus
