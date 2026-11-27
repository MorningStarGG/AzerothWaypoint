-- Swap an existing method for one scenario. Return the original for restoration.
return function(owner, name, replacement)
    local original = owner[name]
    assert(type(original) == "function", "Missing fixture method: " .. name)
    assert(type(replacement) == "function", "Expected a function for " .. name)
    owner[name] = replacement
    return original
end
