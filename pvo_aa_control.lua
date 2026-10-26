-- ===================================================================
-- Minecraft Create: Big Cannons + Create Radar + CC: Tweaked
-- Heavy Anti-Air (PVO) Fire Control System
-- REFINED CBC BALLISTICS (GRAVITY DROP & SPEED COMPENSATION)
-- ===================================================================

local CONFIG = {
    muzzleVelocity = 70.0,    -- CBC projectile speed (blocks/sec), ~3.5 blocks/tick for 3-4 charges
    gravity = 1.25,           -- CBC ballistic gravity drop compensation
    minRange = 20.0,          -- Minimum engagement range (blocks)
    maxRange = 500.0,         -- Maximum radar engagement range (blocks)
    aimTolerance = 1.8,       -- Aim tolerance in degrees before firing
    fireDelay = 0.5,          -- Minimum time between shots (sec)
    iterations = 6,           -- Lead calculation iterations
    
    ignoredTypes = {
        ["bat"] = true, ["cow"] = true, ["pig"] = true, ["sheep"] = true,
        ["chicken"] = true, ["zombie"] = true, ["skeleton"] = true,
        ["spider"] = true, ["item"] = true, ["experience_orb"] = true,
        ["super_glue"] = true, ["honey_glue"] = true, ["corpse"] = true
    }
}

local STATE = {
    lockedId = nil,
    firePermitted = false,
    singleShotQueued = false,
    isAimed = false,
    target = nil,
    lastFireTime = 0
}

local function autoDetectPeripherals()
    local radar, radarName = nil, nil
    local pitchCtrl, pitchName = nil, nil
    local yawCtrl, yawName = nil, nil
    local fireCtrl, fireName = nil, nil

    for _, name in ipairs(peripheral.getNames()) do
        local p = peripheral.wrap(name)
        local pType = tostring(peripheral.getType(name) or ""):lower()
        local nLower = name:lower()

        if not radar and p and p.getTracks then
            radar = p
            radarName = name .. " (" .. pType .. ")"
        end
        if not pitchCtrl and p and p.setAngle and (pType:find("pitch") or nLower:find("pitch")) then
            pitchCtrl = p
            pitchName = name
        end
        if not yawCtrl and p and p.setAngle and (pType:find("yaw") or nLower:find("yaw")) then
            yawCtrl = p
            yawName = name
        end
        if not fireCtrl and p and (p.fireOn or p.keepFiring or pType:find("fire") or nLower:find("fire")) then
            fireCtrl = p
            fireName = name
        end
    end

    return radar, radarName, pitchCtrl, pitchName, yawCtrl, yawName, fireCtrl, fireName
end

local radar, radarName, pitchCtrl, pitchName, yawCtrl, yawName, fireCtrl, fireName = autoDetectPeripherals()

if not radar then
    print("[ERROR] Radar not found on any side or wired network!")
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

local function isTargetValid(track)
    if not track or not track.position then return false end
    local eType = tostring(track.entityType or track.name or ""):lower()
    for ignored, _ in pairs(CONFIG.ignoredTypes) do
        if eType:find(ignored) then return false end
    end
    return true
end

-- Full 6-pass CBC Ballistic Lead & Gravity Drop Calculation
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

    return targetYaw, targetPitch, timeOfFlight, horizontalDist
end

local function drawHUD()
    term.clear()
    term.setCursorPos(1, 1)
    print("================ PVO AIR DEFENSE ================")
    print("Radar: " .. tostring(radarName or "N/A"))
    print("Guns:  Pitch=" .. tostring(pitchName and "OK" or "NO") ..
          " | Yaw=" .. tostring(yawName and "OK" or "NO") ..
          " | Fire=" .. tostring(fireName and "OK" or "NO"))
    print("-------------------------------------------------")
    
    local safetyText = STATE.firePermitted and "[!] FIRE PERMITTED [!]" or "[SAFE] FIRE BLOCKED"
    print("SAFETY STATUS: " .. safetyText)
    print("LOCKED TARGET: " .. tostring(STATE.lockedId or "[NONE - STANDBY]"))
    
    if STATE.target then
        local t = STATE.target
        print(string.format("Dist: %.0fm | Speed: %.1fb/s | ToF: %.2fs", t.dist, t.speed, t.tof))
        print(string.format("Aim Angles -> Yaw: %.1f | Pitch: %.1f", t.yaw, t.pitch))
        local aimStatus = STATE.isAimed and ">> ON TARGET (READY) <<" or ".. AIMING .."
        print("Status: " .. aimStatus)
    else
        print("Standby. Select a valid aircraft or contraption.")
    end
    print("-------------------------------------------------")
    print("CONTROLS:")
    print(" [N] - Next Target    | [U] - Unlock (Standby)")
    print(" [P] - Permit Toggle  | [F / Space] - FIRE 1 SHOT")
    print(" [Q] - Quit Program")
    print("=================================================")
end

local function inputLoop()
    while true do
        local event, key = os.pullEvent("key")
        if key == keys.q then
            print("\nPVO System stopped by operator.")
            return
        elseif key == keys.p then
            STATE.firePermitted = not STATE.firePermitted
        elseif key == keys.u then
            STATE.lockedId = nil
            STATE.target = nil
            if pitchCtrl and pitchCtrl.stopAuto then pitchCtrl.stopAuto() end
            if yawCtrl and yawCtrl.stopAuto then yawCtrl.stopAuto() end
        elseif key == keys.n then
            local tracks = radar.getTracks() or {}
            local candidates = {}
            for _, tr in ipairs(tracks) do
                if isTargetValid(tr) then
                    table.insert(candidates, tr)
                end
            end
            if #candidates > 0 then
                local nextIdx = 1
                for i, c in ipairs(candidates) do
                    if c.id == STATE.lockedId then
                        nextIdx = (i % #candidates) + 1
                        break
                    end
                end
                STATE.lockedId = candidates[nextIdx].id
            else
                STATE.lockedId = nil
            end
        elseif key == keys.f or key == keys.space then
            if STATE.firePermitted then
                STATE.singleShotQueued = true
            else
                print("\n[BLOCKED] Fire not permitted! Press [P] to arm safety.")
                sleep(0.5)
            end
        end
    end
end

local function trackingLoop()
    while true do
        local myPos = (radar.getPosition and radar.getPosition()) or {x = 0, y = 0, z = 0}
        local tracks = radar.getTracks() or {}
        local found = nil

        if STATE.lockedId then
            for _, tr in ipairs(tracks) do
                if tr.id == STATE.lockedId and isTargetValid(tr) then
                    found = tr
                    break
                end
            end
        end

        if found then
            local pos = found.position
            local vel = found.velocity or {x = 0, y = 0, z = 0}
            local vSpeed = vecLength(vel)
            local yaw, pitch, tof, dist = calculateLead(myPos, pos, vel, CONFIG.muzzleVelocity, CONFIG.gravity)

            STATE.target = {
                id = found.id,
                dist = dist,
                speed = vSpeed,
                tof = tof,
                yaw = yaw,
                pitch = pitch
            }

            if yawCtrl and yawCtrl.setAngle then yawCtrl.setAngle(yaw) end
            if pitchCtrl and pitchCtrl.setAngle then pitchCtrl.setAngle(pitch) end

            local curYaw = (yawCtrl and yawCtrl.getAngle and yawCtrl.getAngle()) or yaw
            local curPitch = (pitchCtrl and pitchCtrl.getAngle and pitchCtrl.getAngle()) or pitch

            local yawDiff = math.abs(normalizeAngle(curYaw - yaw))
            local pitchDiff = math.abs(curPitch - pitch)

            STATE.isAimed = (yawDiff <= CONFIG.aimTolerance) and (pitchDiff <= CONFIG.aimTolerance)

            local now = os.epoch("utc") / 1000
            if STATE.singleShotQueued and STATE.firePermitted and (now - STATE.lastFireTime >= CONFIG.fireDelay) then
                if fireCtrl and fireCtrl.fireOn then
                    fireCtrl.fireOn()
                    sleep(0.1)
                    fireCtrl.fireOff()
                else
                    redstone.setOutput("back", true)
                    sleep(0.1)
                    redstone.setOutput("back", false)
                end
                STATE.lastFireTime = now
                STATE.singleShotQueued = false
            end
        else
            STATE.target = nil
            STATE.isAimed = false
            STATE.singleShotQueued = false
        end

        drawHUD()
        sleep(0.1)
    end
end

parallel.waitForAny(trackingLoop, inputLoop)
