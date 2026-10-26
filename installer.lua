-- ==========================================================
-- Heavy Anti-Air (PVO) Offline System Installer
-- Downloads 100% autonomous local script from GitHub
-- ==========================================================

local BASE = "https://raw.githubusercontent.com/mah0isto1-max/Pvo/main/"

local FILES = {
    { src = "pvo_aa_control.lua", dst = "startup.lua",  label = "PVO Main Fire Control" },
    { src = "scan_tracks.lua",    dst = "scan.lua",      label = "Radar Diagnostic Scanner" },
}

print("========================================")
print("  PVO Offline System Installer")
print("========================================")

if not http then
    print("[ERROR] HTTP API is disabled!")
    return
end

local ok = true
for _, f in ipairs(FILES) do
    write("Downloading " .. f.label .. "... ")
    local resp = http.get(BASE .. f.src)
    if resp then
        local data = resp.readAll()
        resp.close()
        local file = fs.open(f.dst, "w")
        file.write(data)
        file.close()
        print("[OK] -> " .. f.dst)
    else
        print("[FAIL] " .. f.src)
        ok = false
    end
end

print("========================================")
if ok then
    print("SUCCESS! All files installed.")
    print("")
    print("  startup.lua  -> PVO fire control")
    print("  scan.lua     -> Radar diagnostics")
    print("")
    print("Run 'scan' first to check radar contacts.")
    print("Then reboot to start PVO auto-targeting.")
else
    print("Some files failed. Check internet/HTTP.")
end
print("========================================")
