local native = dofile("tests/native_path.lua")
local file = assert(io.open(native("forever", "Polestar_Nav/Routing/Path.lua"), "r"))
local source = file:read("*a"); file:close()
-- Execute the installed batch algorithm with bounded search primitives. The
-- fixtures control search outcomes, not the algorithm's nil/false decisions.
local body = assert(source:match("(function Safe%.many%(job%).-\nend)\n\nlocal function runManyReach"),
    "Native batch entry point changed; review the measurement contract")
local expansions, mode = 0, "unjoined"
local safe = {
    setup = function() return nil end,
    segment = function() return nil end,
    refusal = "no safe walking route",
}
safe.find = function(child)
    expansions = expansions + 1
    child.walkChecked, child.yards = true, 84
    if mode == "unjoined" then return child.from.z == nil and 12 or nil end
    if mode == "refused" then return nil end
    return 12
end
local path = {manyCap = 100}
local env = setmetatable({ Safe = safe, Path = path, huge = math.huge,
    Expansions = function() return expansions end, tick = function() end }, {__index = _G})
local chunk = assert(loadstring(body, "@installed-polestar-safe-many"))
setfenv(chunk, env); chunk()
local function run()
    expansions = 0
    local job = {map = 1, from = {x = 0, y = 0, z = 100}, targets = {{x = 1, y = 0}, {x = 2, y = 0}},
        costs = {}, yards = {}, revision = 0}
    local costs = safe.many(job)
    return costs, job
end
local costs, job = run()
assert(job.unjoined and costs[1] == nil and costs[2] == nil,
    "Unjoined target floor no longer leaves estimates unknown")
mode, path.manyCap = "priced", 1
costs, job = run()
assert(job.capped and job.walkChecked and costs[1] == 12 and costs[2] == nil and job.yards[1] == 84,
    "Capped native batch lost its verified prefix/unknown suffix")
mode, path.manyCap = "refused", 100
costs, job = run()
assert(not job.unjoined and not job.capped and costs[1] == false and costs[2] == false and job.walkChecked,
    "Native explicit refusal contract changed")
print("Installed Polestar unjoined/capped/verified-refusal batch contract passed")
