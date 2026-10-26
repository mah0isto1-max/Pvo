-- ===================================================================
-- Minecraft Create: Big Cannons + Create Radar + CC: Tweaked
-- Автоматическая система наведения крупнокалиберного ПВО орудия
-- ===================================================================

-- --- Настройки баллистики ---
local CONFIG = {
    muzzleVelocity = 60.0,    -- Начальная скорость снаряда (блоков/сек)
    gravity = 1.0,            -- Гравитационная поправка CBC снаряда
    minRange = 20.0,          -- Минимальная дистанция огня (блоков)
    maxRange = 500.0,         -- Максимальная дистанция обнаружения/огня (блоков)
    aimTolerance = 1.8,       -- Допустимая погрешность наведения в градусах
    fireDelay = 0.5,          -- Задержка между выстрелами (сек)
    iterations = 5,           -- Количество итераций упреждения для точного расчета
}

-- Умный автоматический поиск периферии в ЛЮБОМ месте (с любой стороны или по кабелю модема)
local function autoDetectPeripherals()
    local radar, radarName = nil, nil
    local pitchCtrl, pitchName = nil, nil
    local yawCtrl, yawName = nil, nil
    local fireCtrl, fireName = nil, nil

    local allNames = peripheral.getNames()

    for _, name in ipairs(allNames) do
        local p = peripheral.wrap(name)
        local pType = tostring(peripheral.getType(name) or ""):lower()
        local nLower = name:lower()

        -- 1. Радар: любой блок с функцией getTracks (независимо от положения и названия)
        if not radar and p and p.getTracks then
            radar = p
            radarName = name .. " (" .. pType .. ")"
        end

        -- 2. Контроллер вертикали (Pitch)
        if not pitchCtrl and p and p.setAngle and (pType:find("pitch") or nLower:find("pitch")) then
            pitchCtrl = p
            pitchName = name
        end

        -- 3. Контроллер горизонтали (Yaw)
        if not yawCtrl and p and p.setAngle and (pType:find("yaw") or nLower:find("yaw")) then
            yawCtrl = p
            yawName = name
        end

        -- 4. Контроллер огня (Fire)
        if not fireCtrl and p and (p.fireOn or p.keepFiring or pType:find("fire") or nLower:find("fire")) then
            fireCtrl = p
            fireName = name
        end
    end

    return radar, radarName, pitchCtrl, pitchName, yawCtrl, yawName, fireCtrl, fireName
end

local radar, radarName, pitchCtrl, pitchName, yawCtrl, yawName, fireCtrl, fireName = autoDetectPeripherals()

term.clear()
term.setCursorPos(1, 1)
print("=== СИСТЕМА УПРАВЛЕНИЯ ПВО (CBC + RADAR) ===")
print("Радар:       " .. tostring(radarName or "[НЕ НАЙДЕН]"))
print("Pitch (Верт):" .. tostring(pitchName or "[НЕ НАЙДЕН]"))
print("Yaw (Гориз): " .. tostring(yawName or "[НЕ НАЙДЕН]"))
print("Спуск (Огонь):" .. tostring(fireName or "[НЕ НАЙДЕН]"))
print("============================================")

if not radar then
    print("[!] Радар не обнаружен!")
    print("Радар можно ставить с ЛЮБОЙ стороны или")
    print("подключить проводом через Wired Modem (ПКМ).")
    return
end

if not (pitchCtrl and yawCtrl) then
    print("[!] Контроллеры Pitch/Yaw не найдены.")
    print("Подключите Auto Pitch и Auto Yaw Controller.")
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

        predictedPos.x = targetPos.x + targetVel.x * timeOfFlight
        predictedPos.y = targetPos.y + targetVel.y * timeOfFlight
        predictedPos.z = targetPos.z + targetVel.z * timeOfFlight
    end

    local dropCompensation = 0.5 * gravity * (timeOfFlight * timeOfFlight)
    local aimTarget = {
        x = predictedPos.x,
        y = predictedPos.y + dropCompensation,
        z = predictedPos.z
    }

    local toTarget = vecSub(aimTarget, gunPos)
    local horizontalDist = math.sqrt(toTarget.x * toTarget.x + toTarget.z * toTarget.z)

    local targetYaw = math.deg(math.atan2(-toTarget.x, toTarget.z))
    local targetPitch = math.deg(math.atan2(toTarget.y, horizontalDist))

    return targetYaw, targetPitch, timeOfFlight, aimTarget
end

-- Основной цикл сопровождения и ведения огня
local function mainLoop()
    local lastFireTime = 0
    print("[СТАТУС] ПВО в боевом дежурстве...")

    while true do
        local myPos = (radar.getPosition and radar.getPosition()) or {x = 0, y = 0, z = 0}
        local tracks = radar.getTracks() or {}
        local bestTarget = nil
        local closestDist = CONFIG.maxRange + 1

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

            yawCtrl.setAngle(yaw)
            pitchCtrl.setAngle(pitch)

            local currentYaw = (yawCtrl.getAngle and yawCtrl.getAngle()) or yaw
            local currentPitch = (pitchCtrl.getAngle and pitchCtrl.getAngle()) or pitch

            local yawDiff = math.abs(normalizeAngle(currentYaw - yaw))
            local pitchDiff = math.abs(currentPitch - pitch)

            local isAimed = (yawDiff <= CONFIG.aimTolerance) and (pitchDiff <= CONFIG.aimTolerance)
            local now = os.epoch("utc") / 1000

            if isAimed and fireCtrl and (now - lastFireTime >= CONFIG.fireDelay) then
                print(string.format("[ЗАЛП] Цель: %s | Дист: %.0fm | Yaw: %.1f | Pitch: %.1f",
                    tostring(bestTarget.id), closestDist, yaw, pitch))
                fireCtrl.fireOn()
                sleep(0.1)
                fireCtrl.fireOff()
                lastFireTime = now
            end
        end

        sleep(0.05)
    end
end

mainLoop()
