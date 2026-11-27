-- ============================================================
-- Nearby search command
-- ============================================================
--
-- Forwards the search slash command to the shared nearby-service search.

local NS = _G.AzerothWaypointNS
local M = NS.Internal.Interface.commands
local Search = NS.Internal.ServiceSearch

function M.handleSearch(arg)
    local target, wantsHelp, query = Search.ResolveQuery(arg)
    if wantsHelp then return Search.ShowHelp() end
    if not target then
        NS.Msg("Unknown search target:", query or arg)
        return Search.ShowHelp()
    end
    Search.Request(target)
end
