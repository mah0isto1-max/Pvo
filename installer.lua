-- ==========================================================
-- Автоматический загрузчик и обновлятор ПВО с GitHub
-- Репозиторий: https://github.com/mah0isto1-max/Pvo
-- ==========================================================

local BASE_URL = "https://raw.githubusercontent.com/mah0isto1-max/Pvo/main/"

local files = {
    ["pvo_aa_control.lua"] = "startup.lua",      -- Сохраняем как startup.lua для автозапуска при включении
    ["inspect_left.lua"]   = "inspect.lua"       -- Утилита проверки периферии
}

print("========================================")
print("  Загрузка системы ПВО с GitHub...")
print("========================================")

if not http then
    print("[ОШИБКА] В конфигурации сервера/мода отключен HTTP API!")
    print("Включите http_enable = true в computercraft-server.toml")
    return
end

for remoteFile, localFile in pairs(files) do
    local url = BASE_URL .. remoteFile
    write("Скачивание " .. remoteFile .. " -> " .. localFile .. "... ")
    
    local response = http.get(url)
    if response then
        local content = response.readAll()
        response.close()
        
        local f = fs.open(localFile, "w")
        f.write(content)
        f.close()
        print("[OK]")
    else
        print("[ОШИБКА]")
    end
end

print("========================================")
print("Установка завершена успешно!")
print("Главный скрипт сохранен как: startup.lua")
print("Для немедленного запуска введите: startup")
print("========================================")
