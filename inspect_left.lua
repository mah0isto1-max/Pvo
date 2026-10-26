term.clear()
term.setCursorPos(1, 1)
print("=== PERIPHERALS SCANNER ===")

local names = peripheral.getNames()
if #names == 0 then
    print("No connected peripherals found.")
    print("Connect adjacent or via Wired Modem.")
    return
end

for i, name in ipairs(names) do
    local pType = peripheral.getType(name)
    local p = peripheral.wrap(name)
    
    print(string.format("[%d] Name: %s | Type: %s", i, name, tostring(pType)))
    
    local features = {}
    if p.getTracks then table.insert(features, "RADAR (getTracks)") end
    if p.setAngle then table.insert(features, "AIM (setAngle)") end
    if p.fireOn or p.keepFiring then table.insert(features, "TRIGGER (fireOn)") end
    if p.getSpeed then table.insert(features, "KINETIC (getSpeed)") end
    
    if #features > 0 then
        print("    -> Role: " .. table.concat(features, ", "))
    end
end

print("===========================")
