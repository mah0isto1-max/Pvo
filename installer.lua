-- ==========================================================
-- Heavy Anti-Air (PVO) Offline System Installer
-- Downloads 100% autonomous local script from GitHub
-- ==========================================================

local URL = "https://raw.githubusercontent.com/mah0isto1-max/Pvo/main/pvo_aa_control.lua"

print("========================================")
print("  Downloading PVO System (Offline)...")
print("========================================")

if not http then
    print("[ERROR] HTTP API is disabled in config!")
    return
end

write("Downloading pvo_aa_control.lua -> startup.lua... ")
local response = http.get(URL)

if response then
    local content = response.readAll()
    response.close()

    local f = fs.open("startup.lua", "w")
    f.write(content)
    f.close()
    print("[OK]")

    print("========================================")
    print("SUCCESS! System installed as startup.lua")
    print("Filter: Only physical contraptions/ships")
    print("Run 'startup' or reboot to start PVO.")
    print("========================================")
else
    print("[FAIL] Could not connect to GitHub.")
end
