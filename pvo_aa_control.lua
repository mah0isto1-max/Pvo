-- ==========================================================
-- Heavy Anti-Air AA System (Create Big Cannons + Radar)
-- Auto lead calculation & proximity detonation support
-- ==========================================================

local CONFIG = {
    muzzleVelocity = 60.0,    -- Projectile speed (blocks/sec)
    gravity = 1.0,            -- Ballistic gravity drop compensation
    minRange = 20.0,          -- Min range deadzone (blocks)
    maxRange = 500.0,         -- Max detection & engagement range (blocks)
    aimTolerance = 1.8,       -- Aim tolerance in degrees before firing
    fireDelay = 0.5,          -- Delay between shots (seconds)
    iterations = 5,           -- Lead calculation iterations
}

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

        -- 1. Radar (any device with getTracks)
        if not radar and p and p.getTracks then
            radar = p
            radarName = name .. " (" .. pType .. ")"
        end

        -- 2. Pitch controller (elevation)
        if not pitchCtrl and p and p.setAngle and (pType:find("pitch") or nLower:find("pitch")) then
            pitchCtrl = p
            pitchName = name
        end

        -- 3. Yaw controller (azimuth rotation)
        if not yawCtrl and p and p.setAngle and (pType:find("yaw") or nLower:find("yaw")) then
            yawCtrl = p
            yawName = name
        end

        -- 4. Fire controller (trigger)
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
print("=== PVO AA AIR DEFENSE CONTROL ===")
print("Radar: " .. tostring(radarName or "[NOT FOUND]"))
print("Pitch: " .. tostring(pitchName or "[NOT FOUND]"))
print("Yaw:   " .. tostring(yawName or "[NOT FOUND]"))
print("Fire:  " .. tostring(fireName or "[NOT FOUND]"))
print("==================================")

if not radar then
    print("[ERROR] Radar not detected!")
    print("Place radar adjacent or connect via Wired Modem.")
    return
end

if not (pitchCtrl and yawCtrl) then
    print("[WARN] Pitch/Yaw controller not found.")
    print("Mount Auto Pitch and Auto Yaw controllers.")
    return
end

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

local function mainLoop()
    local lastFireTime = 0
    print("[STATUS] Air Defense active. Scanning sky...")

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
                print(string.format("[FIRE] Target: %s | Dist: %.0fm | Y: %.1f | P: %.1f",
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
