-- ===================================================================
-- Minecraft Create: Big Cannons + Create Radar + CC: Tweaked
-- Автоматическая система наведения крупнокалиберного ПВО орудия
-- ===================================================================

local RADAR_NAMES = {"plane_radar", "radar_bearing"}
local PITCH_NAME = "pitch_controller"
local YAW_NAME = "yaw_controller"
local FIRE_NAME = "fire_controller"

-- --- Настройки баллистики ---
local CONFIG = {
    muzzleVelocity = 60.0,    -- Начальная скорость снаряда (блоков/сек), зависит от числа пороховых зарядов и длины ствола
    gravity = 1.0,            -- Гравитационная поправка CBC снаряда (блоков/сек^2, ~0.05 b/t^2 = 20 b/s^2 при отсутствии сопротивления)
    minRange = 25.0,          -- Минимальная дистанция огня (блоков)
    maxRange = 450.0,         -- Максимальная дистанция огня (блоков)
    aimTolerance = 1.5,       -- Допустимая погрешность наведения в градусах перед выстрелом
    fireDelay = 0.5,          -- Задержка между проверками выстрела (сек)
    iterations = 5,           -- Количество итераций упреждения для точного расчета времени подлета
    targetCategories = {      -- Приоритет категорий целей (самолеты, дирижабли, мобы)
        ["contraption"] = true,
        ["entity"] = true,
        ["player"] = true
    }
}

-- Поиск подключенных периферийных блоков
local function findPeripheral(typeNames)
    if type(typeNames) == "string" then typeNames = {typeNames} end
    for _, name in ipairs(peripheral.getNames()) do
        local pType = peripheral.getType(name)
        for _, want in ipairs(typeNames) do
            if pType == want or string.find(pType, want) then
                return peripheral.wrap(name), name
            end
        end
    end
    return nil, nil
end

local radar, radarName = findPeripheral(RADAR_NAMES)
local pitchCtrl, pitchName = findPeripheral(PITCH_NAME)
local yawCtrl, yawName = findPeripheral(YAW_NAME)
local fireCtrl, fireName = findPeripheral(FIRE_NAME)

print("--- Инициализация систем ПВО ---")
print("Радар: " .. tostring(radarName or "НЕ НАЙДЕН"))
print("Контроллер вертикали (Pitch): " .. tostring(pitchName or "НЕ НАЙДЕН"))
print("Контроллер горизонтали (Yaw): " .. tostring(yawName or "НЕ НАЙДЕН"))
print("Контроллер огня (Fire): " .. tostring(fireName or "НЕ НАЙДЕН"))

if not (radar and pitchCtrl and yawCtrl) then
    print("[ОШИБКА] Не все блоки подключены через модемы/кабель CC:Tweaked!")
    return
end

-- Вспомогательные векторные операции
local function vecSub(a, b)
    return {x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}
end

local function vecLength(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function normalizeAngle(deg)
    while deg > 180 do deg = deg - 360 end
    while deg < -180 do deg = deg + 360 end
    return deg
end

-- Расчет баллистического упреждения (Lead & Drop)
local function calculateLead(gunPos, targetPos, targetVel, muzzleVel, gravity)
    local predictedPos = {x = targetPos.x, y = targetPos.y, z = targetPos.z}
    local timeOfFlight = 0

    for _ = 1, CONFIG.iterations do
        local rel = vecSub(predictedPos, gunPos)
        local dist = vecLength(rel)
        timeOfFlight = dist / muzzleVel

        -- Новая предсказанная позиция с учетом вектора скорости цели
        predictedPos.x = targetPos.x + targetVel.x * timeOfFlight
        predictedPos.y = targetPos.y + targetVel.y * timeOfFlight
        predictedPos.z = targetPos.z + targetVel.z * timeOfFlight
    end

    -- Расчет вертикальной поправки на падение снаряда (гравитация)
    local dropCompensation = 0.5 * gravity * (timeOfFlight * timeOfFlight)
    local aimTarget = {
        x = predictedPos.x,
        y = predictedPos.y + dropCompensation,
        z = predictedPos.z
    }

    local toTarget = vecSub(aimTarget, gunPos)
    local horizontalDist = math.sqrt(toTarget.x * toTarget.x + toTarget.z * toTarget.z)

    -- Расчет углов наведения (в градусах)
    -- В Minecraft/Create координаты: X - восток, Z - юг
    local targetYaw = math.deg(math.atan2(-toTarget.x, toTarget.z))
    local targetPitch = math.deg(math.atan2(toTarget.y, horizontalDist))

    return targetYaw, targetPitch, timeOfFlight, aimTarget
end

-- Основной цикл сопровождения и поражения
local function mainLoop()
    local lastFireTime = 0

    while true do
        local myPos = radar.getPosition()
        local tracks = radar.getTracks() or {}
        local bestTarget = nil
        local closestDist = CONFIG.maxRange + 1

        -- Фильтрация и выбор ближайшей подходящей воздушной цели
        for _, track in ipairs(tracks) do
            local pos = track.position
            local vel = track.velocity or {x = 0, y = 0, z = 0}
            local dist = vecLength(vecSub(pos, myPos))

            if dist >= CONFIG.minRange and dist <= CONFIG.maxRange then
                if dist < closestDist then
                    closestDist = dist
                    bestTarget = {
                        id = track.id,
                        pos = pos,
                        vel = vel
                    }
                end
            end
        end

        if bestTarget then
            local yaw, pitch, tof, aimTarget = calculateLead(
                myPos,
                bestTarget.pos,
                bestTarget.vel,
                CONFIG.muzzleVelocity,
                CONFIG.gravity
            )

            -- Передаем углы в сервоприводы / контроллеры Create Radar
            yawCtrl.setAngle(yaw)
            pitchCtrl.setAngle(pitch)

            local currentYaw = yawCtrl.getAngle() or yaw
            local currentPitch = pitchCtrl.getAngle() or pitch

            local yawDiff = math.abs(normalizeAngle(currentYaw - yaw))
            local pitchDiff = math.abs(currentPitch - pitch)

            -- Готовность к залпу: орудие доведено в расчетную точку упреждения
            local isAimed = (yawDiff <= CONFIG.aimTolerance) and (pitchDiff <= CONFIG.aimTolerance)
            local now = os.epoch("utc") / 1000

            if isAimed and fireCtrl and (now - lastFireTime >= CONFIG.fireDelay) then
                print(string.format("[ОГОНЬ] Цель %s | Дист: %.1fм | Упреждение: Yaw=%.1f Pitch=%.1f ToF=%.2fс",
                    tostring(bestTarget.id), closestDist, yaw, pitch, tof))
                fireCtrl.fireOn()
                sleep(0.1)
                fireCtrl.fireOff()
                lastFireTime = now
            end
        else
            -- Целей нет: плавное дежурное положение
            sleep(0.5)
        end

        sleep(0.05) -- Обновление каждый тик (20 Hz)
    end
end

mainLoop()
