-- ==========================================================
-- Radar Track Diagnostics
-- Lists every single object detected by the radar
-- ==========================================================

local radar = peripheral.find("create_radar:radar_bearing")
           or peripheral.find("create_radar:plane_radar")

if not radar then
    for _, n in ipairs(peripheral.getNames()) do
        local p = peripheral.wrap(n)
        if p and p.getTracks then radar = p; break end
    end
end

if not radar then
    print("[ERROR] Radar not found!")
    return
end

term.clear()
term.setCursorPos(1, 1)
print("=== RADAR TRACK DIAGNOSTIC SCANNER ===")

local tracks = radar.getTracks() or {}
print("Total Tracks Detected: " .. #tracks)
print("--------------------------------------")

if #tracks == 0 then
    print("No tracks detected in radar field of view.")
    print("Make sure radar is spinning and powered!")
    return
end

for i, t in ipairs(tracks) do
    local cat = tostring(t.category or t.trackCategory or "N/A")
    local eType = tostring(t.entityType or t.name or "N/A")
    local p = t.position or {x=0, y=0, z=0}
    local v = t.velocity or {x=0, y=0, z=0}
    local spd = math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) * 20
    
    print(string.format("[%d] ID:%s", i, tostring(t.id):sub(1, 12)))
    print(string.format("    Cat: %s | Type: %s", cat, eType))
    print(string.format("    Pos: [%.0f, %.0f, %.0f] | Spd: %.1fb/s", p.x, p.y, p.z, spd))
    print("--------------------------------------")
end
