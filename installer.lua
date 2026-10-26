local BASE_URL = "https://raw.githubusercontent.com/mah0isto1-max/Pvo/main/"

local files = {
    ["pvo_aa_control.lua"] = "startup.lua",
    ["inspect_left.lua"]   = "inspect.lua"
}

print("========================================")
print("  Downloading AA System from GitHub...")
print("========================================")

if not http then
    print("[ERROR] HTTP API is disabled on server!")
    print("Enable http_enable = true in config.")
    return
end

for remoteFile, localFile in pairs(files) do
    local url = BASE_URL .. remoteFile
    write("Downloading " .. remoteFile .. " -> " .. localFile .. "... ")
    
    local response = http.get(url)
    if response then
        local content = response.readAll()
        response.close()
        
        local f = fs.open(localFile, "w")
        f.write(content)
        f.close()
        print("[OK]")
    else
        print("[FAIL]")
    end
end

print("========================================")
print("Installation completed successfully!")
print("Main script saved as: startup.lua")
print("Run 'startup' to start the AA system.")
print("Run 'inspect' to scan connected blocks.")
print("========================================")
