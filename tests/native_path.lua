-- The default layout works when AWP lives in the Retail AddOns folder.
-- A development checkout can point at either installation independently.
return function(client, relative)
    if os.getenv("AWP_TEST_SUITE") == "standalone" then
        os.exit(77)
    end
    local root = os.getenv("AWP_" .. client:upper() .. "_ADDONS")
    if not root or root == "" then
        root = "../../../../_" .. client .. "_/Interface/AddOns"
    end
    return root .. "/" .. relative
end
