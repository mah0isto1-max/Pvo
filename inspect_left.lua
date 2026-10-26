-- Сканирование всех подключенных устройств (со всех сторон и по сети проводных модемов)
term.clear()
term.setCursorPos(1, 1)
print("=== СКАНИРОВАНИЕ ВСЕХ ПОДКЛЮЧЕННЫХ УСТРОЙСТВ ===")

local names = peripheral.getNames()
if #names == 0 then
    print("Не найдено ни одного подключенного устройства.")
    print("Поставьте блок вплотную к компьютеру или")
    print("подключите через Wired Modem (кликните ПКМ по модему).")
    return
end

for i, name in ipairs(names) do
    local pType = peripheral.getType(name)
    local p = peripheral.wrap(name)
    local methods = peripheral.getMethods(name)
    
    print(string.format("[%d] Имя: %s | Тип: %s", i, name, tostring(pType)))
    
    -- Проверка ключевых возможностей
    local features = {}
    if p.getTracks then table.insert(features, "РАДАР (getTracks)") end
    if p.setAngle then table.insert(features, "НАВЕДЕНИЕ (setAngle)") end
    if p.fireOn or p.keepFiring then table.insert(features, "СПУСК (fireOn)") end
    if p.getSpeed then table.insert(features, "КИНЕТИКА (getSpeed)") end
    
    if #features > 0 then
        print("    -> Возможности: " .. table.concat(features, ", "))
    end
end

print("================================================")
