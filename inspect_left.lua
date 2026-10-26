-- Скрипт проверки периферии блока слева от компьютера (или с любой стороны)
local side = "left"

if not peripheral.isPresent(side) then
    print("Слева от компьютера НЕТ периферийного блока!")
    return
end

local pType = peripheral.getType(side)
print("---------------------------------")
print("Тип периферии слева: " .. tostring(pType))
print("Доступные методы:")
print("---------------------------------")

local methods = peripheral.getMethods(side)
table.sort(methods)

for i, method in ipairs(methods) do
    print(string.format("%2d. %s()", i, method))
end
print("---------------------------------")
