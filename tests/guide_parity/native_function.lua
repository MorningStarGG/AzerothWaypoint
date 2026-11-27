-- Execute an installed method without starting its addon's UI. A closing
-- `end` at the declaration's indentation is the boundary in these sources.
-- Failure to find it, or a changed dependency, fails the native contract test.
local path = dofile("tests/native_path.lua")
return function(client, file, method, env, occurrence)
    local input = assert(io.open(path(client, file), "rb"))
    local source = input:read("*a"):gsub("\r\n", "\n"); input:close()
    local escaped = method:gsub("([^%w])", "%%%1")
    local first, finishDeclaration, indent, from = nil, nil, nil, 1
    for _ = 1, occurrence or 1 do
        first, finishDeclaration, indent = ("\n" .. source):find("\n([ \t]*)function " .. escaped .. "%(", from)
        assert(first, "Missing native declaration " .. method)
        from = finishDeclaration + 1
    end
    assert(first, "Missing native declaration " .. method)
    -- Account for the leading newline used to also match line 1.
    local finish = assert(source:find("\n" .. indent .. "end", first, true), "Missing end of " .. method)
    local chunk = assert(loadstring(source:sub(first, finish + #indent + 3), "@" .. path(client, file)))
    setfenv(chunk, setmetatable(env, { __index = _G }))()
end
