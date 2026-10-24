if isServer() then return end

TimePasses = TimePasses or {}
TimePasses.PrevHealth = 100.0 

local pausedPlayerCount = 0
TimePasses.pauseAnimTimer = 0.0

local commitedPlayerCount = 0
TimePasses.waitAnimTimer = 0.0

local interruptionMessage = ""
local wasOccupied = false
local wasCommited = false
local wasAsleep = false
local wasPaused = false

local isInterrupted = false
local animTimer = 0.0
local serverMsg = ""

TimePasses.isPaused = false
TimePasses.isWaiting = false

local predictedElapsedTime = 0.0
local predictedTimeMultiplier = 1.0

local function IsFireOrZombieNearby(player, distanceCell)
    local cell = player:getCell()
    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ())
    
    for x = px - distanceCell, px + distanceCell do
        for y = py - distanceCell, py + distanceCell do
            local square = cell:getGridSquare(x, y, pz)
            if square then
                local movingObjects = square:getMovingObjects()
                for i = 0, movingObjects:size() - 1 do
                    local obj = movingObjects:get(i)
                    if instanceof(obj, "IsoZombie") and not obj:isDead() then
                        if IsoUtils.DistanceToSquared(player:getX(), player:getY(), obj:getX(), obj:getY()) <= (distanceCell * distanceCell) then
                            interruptionMessage = "Zombie"
                            return true
                        end
                    end
                end
            end
            for z = pz - distanceCell, pz + distanceCell do
                square = cell:getGridSquare(x, y, z)
                if square and square:haveFire() then
                    interruptionMessage = "Fire"
                    return true
                end
            end
        end
    end
    return false
end

local function IsNoxiousSmell(player)
    local smellLevel = player:getMoodles():getMoodleLevel(MoodleType.NOXIOUS_SMELL)
    if smellLevel >= 3 then 
        interruptionMessage = "Noxious smell"
        return true
    end
    return false
end

local function IsHealthDropping(player)
    local bodyDamage = player:getBodyDamage()
    if bodyDamage:getNumPartsBleeding() > 0 then
        interruptionMessage = "Bleeding"
        return true
    end

    local currentHealth = bodyDamage:getOverallBodyHealth()
    local isDropping = false
    if TimePasses.PrevHealth and currentHealth < 60 and currentHealth < (TimePasses.PrevHealth - 0.001) then
        interruptionMessage = "Losing health"
        isDropping = true
    end
    TimePasses.PrevHealth = currentHealth
    return isDropping
end

local safetyCheckTimer = 0
local function TimeCanPass(player)
    safetyCheckTimer = safetyCheckTimer + 1
    if safetyCheckTimer >= 15 then
        safetyCheckTimer = 0
        if IsHealthDropping(player) then return false end
        if IsNoxiousSmell(player) then return false end
        if IsFireOrZombieNearby(player, 10) then return false end
    end
    return true
end

local autoWalkGraceTicks = 0
local function IsAutoPathfinding(player)
    return player:getPathFindBehavior2():isMovingUsingPathFind()
end

TimePasses.OnTick = function()
    local player = getPlayer()
    if not player then return end

	-- reset and bail if player is dead
	-- but we let others accelerated by pretending the player is sleeping
	if player:isDead() then
        if wasOccupied or wasAsleep or wasPaused then
            wasOccupied = false
            wasAsleep = false
			wasPaused = false
            SendState(false, false, true, false)
        end
        return
    end
	
	local gameTime = GameTime:getInstance()
    local deltaSeconds = gameTime:getThirtyFPSMultiplier() / gameTime:getTrueMultiplier() / 30.0

    local isPlayerControl = player:isJustMoved() and not IsAutoPathfinding(player) or player:isAiming()

    -- stop pause and waiting if the player moves or aims
    if isPlayerControl then
        TimePasses.SetControlState("PLAY")
    end

	-- anim time for pause button
    local pauseAskedByUs = TimePasses.isPaused and gameTime:getTrueMultiplier() >= 1
    local pauseAskedByOthers = not TimePasses.isPaused and pausedPlayerCount > 0
	if pauseAskedByUs or pauseAskedByOthers then
		-- we ask for pause but the game is not paused, or someone asks for pause but we don't : we animate the pause button
		TimePasses.pauseAnimTimer = TimePasses.pauseAnimTimer + deltaSeconds
		if TimePasses.pauseAnimTimer >= 1.0 then
			TimePasses.pauseAnimTimer = TimePasses.pauseAnimTimer - 1.0
		end
	else
		TimePasses.pauseAnimTimer = 0
	end

	-- anim timer for "..."
    animTimer = animTimer + deltaSeconds
    if animTimer >= 1.0 then
        animTimer = animTimer - 1.0
    end

	-- check if time can pass
    local actionQueue = ISTimedActionQueue.getTimedActionQueue(player)
	local isBusy = TimePasses.isWaiting or (actionQueue and actionQueue.queue and #actionQueue.queue > 0)

    local isOccupied = false
    local isCommited = false

	if not isBusy then
		isInterrupted = false
		interruptionMessage = ""

        if commitedPlayerCount > 0 then
            -- other players are comited to a long task, we animate the wait button
		    TimePasses.waitAnimTimer = TimePasses.waitAnimTimer + deltaSeconds
		    if TimePasses.waitAnimTimer >= 1.0 then
			    TimePasses.waitAnimTimer = TimePasses.waitAnimTimer - 1.0
		    else
		        TimePasses.waitAnimTimer = 0
            end
        end
    elseif not isInterrupted then
		-- is busy and is not interrupted
        local uiSpeedState = UIManager.getSpeedControls():getCurrentGameSpeed()
        if uiSpeedState ~= 1 then
		    -- player or the game chose a special speed
			TimePasses.isWaiting = false
            interruptionMessage = "Manual speed"
		elseif isPlayerControl then
		    -- player moves or aims manually
			TimePasses.isWaiting = false
            interruptionMessage = "Manual control"
        elseif not TimeCanPass(player) then
		    -- time cannot pass due to a hazard
            isInterrupted = true
            UIManager.getSpeedControls():SetCurrentGameSpeed(1)
        else
		    -- time can pass
            isOccupied = true
			if interruptionMessage ~= "..." then
				animTimer = 0
			end
            interruptionMessage = "..."
			
			-- client predictions
			if predictedElapsedTime > 0 and isClient() then
				predictedElapsedTime = predictedElapsedTime + deltaSeconds
				predictedTimeMultiplier = TimePasses.computeTimeMultiplier(predictedElapsedTime, predictedTimeMultiplier, deltaSeconds, gameTime)
			end

            -- check if we are commited to a long task
            local busyDuration = 0
            local numActions = #actionQueue.queue
            local maxIterations = math.min(numActions, 100) -- we iterate on the 100 first actions maximum for perf reasons

            for i = 1, maxIterations do
                local action = actionQueue.queue[i]
                local maxTime = action.maxTime or 0
                if i == 1 then
                    -- we subscrat the time already spent in the current action
                    maxTime = maxTime - (action.currentTime or 0)
                end
                if maxTime == -1 then
                    -- actions without a duration are usually short (animations), we set them to 1 second
                    maxTime = 1 * 30
                end
                busyDuration = busyDuration + maxTime

                if busyDuration / 30 > 20 then
                    isCommited = true
                    break
                end
            end
        end
    end

	-- send command to server
	local isAsleep = player:isAsleep();
    if isOccupied ~= wasOccupied or isCommited ~= wasCommited or isAsleep ~= wasAsleep or TimePasses.isPaused ~= wasPaused then
		SendState(isOccupied, isCommited, isAsleep, TimePasses.isPaused)
		wasOccupied = isOccupied
		wasCommited = isCommited
		wasAsleep = isAsleep
		wasPaused = TimePasses.isPaused
    end
	
end
if TimePasses.OnTick then
    Events.OnTick.Remove(TimePasses.OnTick)
end
Events.OnTick.Add(TimePasses.OnTick)

TimePasses.OnServerCommand = function (module, command, args)
    if module ~= "TimePasses" then return end

    if command == "TimeState" then
		if args.elapsedTime ~= -1 then
			predictedElapsedTime = args.elapsedTime
		end
		if args.timeMultiplier ~= -1 then
			predictedTimeMultiplier = args.timeMultiplier
			getGameTime():setMultiplier(predictedTimeMultiplier)
		end
        if args.pauseCount ~= -1 then
		    pausedPlayerCount = args.pausedCount
        end
        if args.commitedCount ~= -1 then
		    commitedPlayerCount = args.commitedCount
        end
    end
	
	if command == "Message" then
		if args.msg == "reset" then
			serverMsg = ""
		else
			serverMsg = serverMsg..args.msg
		end
	end
end
if TimePasses.OnServerCommand then
    Events.OnServerCommand.Remove(TimePasses.OnServerCommand)
end
Events.OnServerCommand.Add(TimePasses.OnServerCommand)

TimePasses.OnPostUIDraw = function()
    local currentTimeMultiplier = getGameTime():getTrueMultiplier()
    local text = ""
    
    if predictedElapsedTime > 0 and currentTimeMultiplier > 1.0 then 
        local progress = (currentTimeMultiplier - 1.0) / (40.0 - 1.0)
        if progress > 1.0 then progress = 1.0 end
        local numChevrons = math.max(1, math.ceil(progress * 15))
        text = string.rep(">", numChevrons) --.. string.format(" (%.1fx)", currentTimeMultiplier)
    elseif interruptionMessage ~= "" then
        text = interruptionMessage
	end

	-- suspension points animation
    if text == "..." then
        local phase = math.floor(animTimer * 4)
        if phase == 0 then text = ""
        elseif phase == 1 then text = "."
        elseif phase == 2 then text = ".."
        elseif phase == 3 then text = "..."
        end
    end
	
	text = text.."\n"..serverMsg

    text = text.."\nmove ".. tostring(getPlayer():isJustMoved())
    text = text.."\naim  ".. tostring(getPlayer():isAiming())
    text = text.."\npath ".. tostring(getPlayer():getPathFindBehavior2():isMovingUsingPathFind())

	
    local speedControls = UIManager.getSpeedControls()
    if not speedControls then return end

    local x
    local pauseButton = speedControls:getControls():get(0)
    if pauseButton then
        x = pauseButton:getAbsoluteX()
    else
        x = speedControls:getAbsoluteX()
    end
    
    local y = speedControls:getY() + speedControls:getHeight()

    getTextManager():DrawString(UIFont.Small, x, y, text, 0.8, 0.8, 0.8, 1.0)
end
if TimePasses.OnPostUIDraw then
    Events.OnPostUIDraw.Remove(TimePasses.OnPostUIDraw)
end
Events.OnPostUIDraw.Add(TimePasses.OnPostUIDraw)

TimePasses.OnKeyPressed = function(key)
    -- if solo mode then bail
    if not isClient() then return end

    if key == getCore():getKey("Main Menu") then
        -- in MP, we stop the pause if the player opens their Menu
        -- because this is not a real pause but a very slow speed that mess up with the UI
        if TimePasses.isPaused then
            TimePasses.SetControlState("PLAY")
        end
    elseif key == getCore():getKey("Pause") then
        TimePasses.SetControlState("PAUSE")
    elseif key == getCore():getKey("Normal Speed") then
        TimePasses.SetControlState("PLAY")
    elseif key == getCore():getKey("Fast Forward x1") or
           key == getCore():getKey("Fast Forward x2") or
           key == getCore():getKey("Fast Forward x3") then
        TimePasses.SetControlState("WAIT")
    end
end
if TimePasses.OnKeyPressed then
    Events.OnKeyPressed.Remove(TimePasses.OnKeyPressed)
end
Events.OnKeyPressed.Add(TimePasses.OnKeyPressed);

function SendState(occ, commited, asleep, paused)
	sendClientCommand(getPlayer(), "TimePasses", "UpdateState", {isOccupied = occ, isCommited = commited, isSleeping = asleep, isPaused = paused})
end

function TimePasses.SetControlState(state)
    if state == "PAUSE" then
        TimePasses.isPaused = not TimePasses.isPaused
        TimePasses.isWaiting = false
    elseif state == "PLAY" then
        TimePasses.isPaused = false
        TimePasses.isWaiting = false
    elseif state == "WAIT" then
        TimePasses.isPaused = false
        TimePasses.isWaiting = true
    end
end
