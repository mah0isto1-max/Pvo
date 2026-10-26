-- ===================================================================
-- Heavy Anti-Air (PVO) Fire Control System
-- 100% LOCAL & AUTONOMOUS (NO WEBSITE / NO EXTERNAL SERVER)
-- TARGETS: ONLY PHYSICAL CONTRAPTIONS & SABLE/VS SHIPS
-- ===================================================================

local CONFIG = {
    muzzleVelocity = 70.0,    -- CBC projectile speed (blocks/sec)
    gravity = 1.25,           -- CBC ballistic gravity drop compensation
    minRange = 15.0,          -- Minimum engagement range (blocks)
    maxRange = 600.0,         -- Maximum radar engagement range (blocks)
    aimTolerance = 1.6,       -- Aim tolerance in degrees before firing
    fireDelay = 0.5,          -- Minimum delay between shots (sec)
    iterations = 6,           -- Iterative lead calculation passes

    -- STRICT FILTER: TARGET ONLY PHYSICAL CONTRAPTIONS AND SABLE SHIPS
    allowedCategories = {
        ["CONTRAPTION"] = true,
        ["SABLE"]       = true,
        ["contraption"] = true,
        ["sable"]       = true
    }
}

-- Operator State
local STATE = {
    targetId = nil,           -- Selected physical target ID
    target = nil,             -- Track info table
    fireMode = "MANUAL",      -- "MANUAL" (requires keypress) or "AUTO" (fires when aimed)
    firePermitted = false,    -- Safety toggle: true = safety OFF, false = safety ON
    singleShot = false,       -- Queued shot on demand
    isAimed = false,          -- Gun is on calculated lead position
    lastFireTime = 0
}

-- ---- Multi-Peripheral & Gun Radar Detection ----
local function findPeripherals()
    local gunRadar, radarName = nil, nil
    local pitchCtrl, pitchName = nil, nil
    local yawCtrl, yawName = nil, nil
    local fireCtrl, fireName = nil, nil

    for _, name in ipairs(peripheral.getNames()) do
        local p = peripheral.wrap(name)
        local pType = tostring(peripheral.getType(name) or ""):lower()
        local nLower = name:lower()

        -- Gun Radar: any radar peripheral on network or local side
        if not gunRadar and p and p.getTracks then
            gunRadar = p
            radarName = name .. " (" .. pType .. ")"
        end

        -- Auto Pitch Controller (elevation)
        if not pitchCtrl and p and p.setAngle and (pType:find("pitch") or nLower:find("pitch")) then
            pitchCtrl = p
            pitchName = name
        end

        -- Auto Yaw Controller (rotation)
        if not yawCtrl and p and p.setAngle and (pType:find("yaw") or nLower:find("yaw")) then
            yawCtrl = p
            yawName = name
        end

        -- Fire Controller (trigger)
        if not fireCtrl and p and (p.fireOn or p.keepFiring or pType:find("fire") or nLower:find("fire")) then
            fireCtrl = p
            fireName = name
        end
    end

    return gunRadar, radarName, pitchCtrl, pitchName, yawCtrl, yawName, fireCtrl, fireName
end

local radar, radarName, pitchCtrl, pitchName, yawCtrl, yawName, fireCtrl, fireName = findPeripherals()

if not radar then
    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print(" [ERROR] Gun Radar not detected!")
    print(" Connect radar directly or via Wired Modem.")
    print("========================================")
    return
end

-- Math helpers
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

-- Filter check: MUST BE CONTRAPTION OR SABLE SHIP ONLY
local function isPhysicalObject(track)
    if not track or not track.position then return false end
    local cat = tostring(track.category or track.trackCategory or "")
    
    -- Check category whitelist
    if not CONFIG.allowedCategories[cat] then
        -- Also check entityType / name for contraption / ship
        local eType = tostring(track.entityType or track.name or ""):lower()
        if not (eType:find("contraption") or eType:find("sable") or eType:find("ship")) then
            return false
        end
    end

    -- Ignore glue / corpses
    local name = tostring(track.name or track.entityType or ""):lower()
    if name:find("glue") or name:find("corpse") then return false end

    return true
end

-- CBC Ballistic Calculation: 6-pass lead prediction + gravity drop
local function calculateCBCLead(gunPos, targetPos, targetVel, muzzleVel, gravity)
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

    -- Gravity compensation: aim higher by 0.5 * g * t^2
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

-- Draw Terminal Status Display
local function drawUI(gunPos, validCount)
    term.clear()
    term.setCursorPos(1, 1)
    print("========== PVO HEAVY AIR DEFENSE (OFFLINE) ==========")
    print(string.format("Gun Pos: [%.0f, %.0f, %.0f] | Range: %.0fm", gunPos.x, gunPos.y, gunPos.z, CONFIG.maxRange))
    print(string.format("Modules: Pitch=%s | Yaw=%s | Fire=%s",
        pitchName and "OK" or "NO", yawName and "OK" or "NO", fireName and "OK" or "NO"))
    print("Filter:  PHYSICAL CONTRAPTIONS & SABLE SHIPS ONLY")
    print("-----------------------------------------------------")

    local safetyStr = STATE.firePermitted and "[!] FIRE PERMITTED (ARMED) [!]" or "[SAFE] FIRE BLOCKED (SAFETY ON)"
    print("SAFETY:  " .. safetyStr)
    print("MODE:    " .. STATE.fireMode .. " | Targets in Sky: " .. validCount)
    print("-----------------------------------------------------")

    if STATE.target then
        local t = STATE.target
        print("TARGET:  " .. tostring(t.name) .. " [" .. tostring(t.id) .. "]")
        print(string.format("Pos:     X:%.0f Y:%.0f Z:%.0f", t.pos.x, t.pos.y, t.pos.z))
        print(string.format("Flight:  Dist:%.0fm | Speed:%.1fb/s | ToF:%.2fs", t.dist, t.speed, t.tof))
        print(string.format("Aim:     Yaw:%.1f deg | Pitch:%.1f deg", t.yaw, t.pitch))
        local aimStr = STATE.isAimed and ">> AIMED ON TARGET (READY) <<" or ".. SLEWING TO LEAD POINT .."
        print("Status:  " .. aimStr)
    else
        print("TARGET:  [NO PHYSICAL TARGETS - STANDBY]")
        print("Gun standing by in neutral azimuth.")
    end

    print("-----------------------------------------------------")
    print("CONTROLS:")
    print(" [P] - Permit / Safety Toggle   [A] - Toggle AUTO / MANUAL")
    print(" [N] - Next Physical Target     [U] - Unlock Target")
    print(" [F / Space] - FIRE ONE SHOT (Requires Permit)")
    print(" [Q] - Stop Program")
    print("=====================================================")
end

-- Keyboard input thread
local function inputLoop()
    while true do
        local event, key = os.pullEvent("key")
        if key == keys.q then
            print("\nPVO Air Defense shut down by operator.")
            if pitchCtrl and pitchCtrl.stopAuto then pitchCtrl.stopAuto() end
            if yawCtrl and yawCtrl.stopAuto then yawCtrl.stopAuto() end
            return
        elseif key == keys.p then
            STATE.firePermitted = not STATE.firePermitted
        elseif key == keys.a then
            STATE.fireMode = (STATE.fireMode == "MANUAL") and "AUTO" or "MANUAL"
        elseif key == keys.u then
            STATE.targetId = nil
            STATE.target = nil
            if pitchCtrl and pitchCtrl.stopAuto then pitchCtrl.stopAuto() end
            if yawCtrl and yawCtrl.stopAuto then yawCtrl.stopAuto() end
        elseif key == keys.n then
            local tracks = radar.getTracks() or {}
            local candidates = {}
            for _, tr in ipairs(tracks) do
                if isPhysicalObject(tr) then
                    table.insert(candidates, tr)
                end
            end
            if #candidates > 0 then
                local nextIdx = 1
                for i, c in ipairs(candidates) do
                    if c.id == STATE.targetId then
                        nextIdx = (i % #candidates) + 1
                        break
                    end
                end
                STATE.targetId = candidates[nextIdx].id
            else
                STATE.targetId = nil
            end
        elseif key == keys.f or key == keys.space then
            if STATE.firePermitted then
                STATE.singleShot = true
            else
                -- Visual warning
                STATE.singleShot = false
            end
        end
    end
end

-- Fire Control and Ballistic Lead Thread
local function trackingLoop()
    while true do
        local gunPos = (radar.getPosition and radar.getPosition()) or {x = 0, y = 70, z = 0}
        local tracks = radar.getTracks() or {}
        local validTargets = {}
        local currentTarget = nil

        -- 1. Scan and filter ONLY physical contraptions & Sable ships
        for _, tr in ipairs(tracks) do
            if isPhysicalObject(tr) then
                local p = tr.position
                local d = vecLength(vecSub(p, gunPos))
                if d >= CONFIG.minRange and d <= CONFIG.maxRange then
                    table.insert(validTargets, tr)
                end
            end
        end

        -- 2. Target acquisition: lock selected ID or auto-acquire nearest physical object
        if STATE.targetId then
            for _, tr in ipairs(validTargets) do
                if tr.id == STATE.targetId then
                    currentTarget = tr
                    break
                end
            end
        end

        if not currentTarget and #validTargets > 0 then
            -- Auto-select nearest physical object
            local bestDist = CONFIG.maxRange + 1
            for _, tr in ipairs(validTargets) do
                local d = vecLength(vecSub(tr.position, gunPos))
                if d < bestDist then
                    bestDist = d
                    currentTarget = tr
                    STATE.targetId = tr.id
                end
            end
        elseif not currentTarget then
            STATE.targetId = nil
        end

        -- 3. Ballistic Tracking & Lead Calculation
        if currentTarget then
            local pos = currentTarget.position
            local vel = currentTarget.velocity or {x = 0, y = 0, z = 0}
            local vSpeed = vecLength(vel)
            local yaw, pitch, tof, dist = calculateCBCLead(gunPos, pos, vel, CONFIG.muzzleVelocity, CONFIG.gravity)

            STATE.target = {
                id = currentTarget.id,
                name = tostring(currentTarget.name or currentTarget.entityType or currentTarget.category or "Physical Contraption"),
                pos = pos,
                dist = dist,
                speed = vSpeed,
                tof = tof,
                yaw = yaw,
                pitch = pitch
            }

            -- Direct gun motors
            if yawCtrl and yawCtrl.setAngle then yawCtrl.setAngle(yaw) end
            if pitchCtrl and pitchCtrl.setAngle then pitchCtrl.setAngle(pitch) end

            local curYaw = (yawCtrl and yawCtrl.getAngle and yawCtrl.getAngle()) or yaw
            local curPitch = (pitchCtrl and pitchCtrl.getAngle and pitchCtrl.getAngle()) or pitch

            local yawDiff = math.abs(normalizeAngle(curYaw - yaw))
            local pitchDiff = math.abs(curPitch - pitch)

            STATE.isAimed = (yawDiff <= CONFIG.aimTolerance) and (pitchDiff <= CONFIG.aimTolerance)

            -- 4. Firing Logic: ONLY BY PERMISSION
            local now = os.epoch("utc") / 1000
            local shouldFire = false

            if STATE.firePermitted and (now - STATE.lastFireTime >= CONFIG.fireDelay) then
                if STATE.singleShot then
                    shouldFire = true
                    STATE.singleShot = false
                elseif STATE.fireMode == "AUTO" and STATE.isAimed then
                    shouldFire = true
                end
            else
                STATE.singleShot = false
            end

            if shouldFire then
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
            end
        else
            STATE.target = nil
            STATE.isAimed = false
            STATE.singleShot = false
        end

        drawUI(gunPos, #validTargets)
        sleep(0.05) -- 20 Hz update
    end
end

parallel.waitForAny(trackingLoop, inputLoop)
