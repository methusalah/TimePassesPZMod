--/reloadlua server/TimePasses_Server.lua
if isClient() then return end

TimePasses = TimePasses or {}
TimePasses.OccupiedPlayers = {}
TimePasses.CommitedPlayers = {}
TimePasses.SleepingPlayers = {}
TimePasses.PausedPlayers = {}

local prevPausedPlayerCount = 0
local prevCommitedPlayerCount = 0

local elapsedTime = 0.0
local timeMultiplier = 1.0
local wasTimeAltered = false
local commandTimer = 1
local messageTimer = 1
local prevTickEndClock = 0;

local function OnClientCommand(module, command, player, args)
    if module ~= "TimePasses" then return end

    local username = player:getUsername()
    if command == "UpdateState" then
        if args.isOccupied then
            TimePasses.OccupiedPlayers[username] = true
        else
            TimePasses.OccupiedPlayers[username] = nil
        end

        if args.isCommited then
            TimePasses.CommitedPlayers[username] = true
        else
            TimePasses.CommitedPlayers[username] = nil
        end

        if args.isSleeping then
            TimePasses.SleepingPlayers[username] = true
        else
            TimePasses.SleepingPlayers[username] = nil
        end
		
        if args.isPaused then
            TimePasses.PausedPlayers[username] = true
        else
            TimePasses.PausedPlayers[username] = nil
        end
	end
end
if TimePasses.OnClientCommand then
    Events.OnClientCommand.Remove(TimePasses.OnClientCommand)
end
Events.OnClientCommand.Add(OnClientCommand)

local function UpdateServerSystemTime()
    local multiplier = getGameTime():getTrueMultiplier()

	local tickEndClock = GameTime.getServerTime()
	GameTime.setServerTimeShift(0)
	local tickStartClock = GameTime.getServerTime()
	local shift = tickEndClock - tickStartClock
	
    if (multiplier == 1) then 
        GameTime.setServerTimeShift(shift)
        prevTickEndClock = tickStartClock
        return
    end

	if (prevTickEndClock == 0) then prevTickEndClock = tickStartClock end
	local realLifeDelta = tickStartClock - prevTickEndClock
	prevTickEndClock = tickStartClock
		

    if (realLifeDelta > 0) then
		local extra = (realLifeDelta * multiplier) - realLifeDelta
        GameTime.setServerTimeShift(shift + extra)
    else
        GameTime.setServerTimeShift(shift)
    end
end

local globalTickCounter = 0
local function UpdateTimeMultiplier()
	globalTickCounter = globalTickCounter + 1
	local debugText = ""

	-- couting players and states
	local playerCount = 0
	local occupiedPlayerCount, commitedPlayerCount, sleepingPlayerCount, pausedPlayerCount = 0, 0, 0, 0

	local isMulti = isClient() or isServer()
	local onlinePlayers = isMulti and getOnlinePlayers() or nil
	local playerCount = onlinePlayers and onlinePlayers:size() or (getPlayer() and 1 or 0)

	local currentOnlineUsernames = {}
	for i = 0, playerCount - 1 do
		local player = isMulti and onlinePlayers:get(i) or getPlayer()
		local username = player:getUsername()
		currentOnlineUsernames[username] = true

		if TimePasses.OccupiedPlayers[username] then occupiedPlayerCount = occupiedPlayerCount + 1 end
		if TimePasses.CommitedPlayers[username] then commitedPlayerCount = commitedPlayerCount + 1 end
		if TimePasses.SleepingPlayers[username] then sleepingPlayerCount = sleepingPlayerCount + 1 end
		if TimePasses.PausedPlayers[username] then pausedPlayerCount = pausedPlayerCount + 1 end
	end

	-- clean dead and offline players
	for username, _ in pairs(TimePasses.OccupiedPlayers) do
		if not currentOnlineUsernames[username] then TimePasses.OccupiedPlayers[username] = nil end
	end
	for username, _ in pairs(TimePasses.SleepingPlayers) do
		if not currentOnlineUsernames[username] then TimePasses.SleepingPlayers[username] = nil end
	end
	for username, _ in pairs(TimePasses.PausedPlayers) do
		if not currentOnlineUsernames[username] then TimePasses.PausedPlayers[username] = nil end
	end
	
	-- sending the paused player count if it changed
	if pausedPlayerCount ~= prevPausedPlayerCount then
		prevPausedPlayerCount = pausedPlayerCount
		sendTimeState(-1, -1, pausedPlayerCount, -1)
	end

	-- sending the commited player count if it changed
	if commitedPlayerCount ~= prevCommitedPlayerCount then
		prevCommitedPlayerCount = commitedPlayerCount
		sendTimeState(-1, -1, -1, commitedPlayerCount)
	end

    local gameTime = GameTime:getInstance()

    -- if there is no player, reset and bail
    if playerCount == 0 then
        if timeMultiplier > 1.0 then
            elapsedTime = 0.0
            timeMultiplier = 1.0
            gameTime:setMultiplier(1.0)
        end
        return
    end

	if pausedPlayerCount >= playerCount then
		-- all players are paused, we pause the game for everyone
        timeMultiplier = 0.000001
		gameTime:setMultiplier(timeMultiplier)
		sendTimeState(0, timeMultiplier, -1, -1)
		commandTimer = 1
		wasTimeAltered = true
    elseif occupiedPlayerCount + sleepingPlayerCount >= playerCount and sleepingPlayerCount < playerCount then
		-- all players are occupied or sleeping, time passes. If all players are sleeping, we don't alter the time
        local deltaSeconds = gameTime:getThirtyFPSMultiplier() / gameTime:getTrueMultiplier() / 30.0
        elapsedTime = elapsedTime + deltaSeconds
		
		timeMultiplier = TimePasses.computeTimeMultiplier(elapsedTime, timeMultiplier, deltaSeconds, gameTime)
		
		-- send data to clients each seconds for them to predict and correct
		commandTimer = commandTimer + deltaSeconds
		if commandTimer >= 0.3 then
			sendTimeState(elapsedTime, timeMultiplier, -1, -1)
			commandTimer = commandTimer - 0.3
		end

		wasTimeAltered = true
    else
		-- not all players are paused, at least one player is not occupied or all players are sleeping, time stops passing
        if wasTimeAltered then
			-- time was either passing or paused, we send normal multiplier to clients
            timeMultiplier = 1.0
            gameTime:setMultiplier(timeMultiplier)
			sendTimeState(0, timeMultiplier, -1, -1)
			commandTimer = 1
        end
        -- Decay of the time passing memory, server only
		-- the memory allows to smooth small interruption and prevent acceleration to going back to zero immediately
        if elapsedTime > 0 then
            local deltaSeconds = gameTime:getThirtyFPSMultiplier() / 30.0
            local decayRate = TimePasses.Config.SECONDS_TO_MAX / TimePasses.Config.MEMORY_DECAY
            
            elapsedTime = math.max(elapsedTime - (deltaSeconds * decayRate), 0)
        end
		wasTimeAltered = false
    end
		
	-- debug text send to clients
	if getDebug() then
		debugText = debugText..string.format(occupiedPlayerCount).."."..string.format(sleepingPlayerCount).."."..string.format(pausedPlayerCount).."/"..string.format(playerCount)
		local deltaSeconds = gameTime:getThirtyFPSMultiplier() / gameTime:getTrueMultiplier() / 30.0
		messageTimer = messageTimer + deltaSeconds
		if messageTimer >= 1 then
			sendMessage("reset")
			sendMessage(debugText)
			messageTimer = messageTimer - 1
		end
	end
end

function sendTimeState(elapsed, mult, pausedCount, commitedCount)
	if isServer() then
		local onlinePlayers = getOnlinePlayers()
		if onlinePlayers then
			for i = 0, onlinePlayers:size() - 1 do
				local p = onlinePlayers:get(i)
				sendServerCommand(p, "TimePasses", "TimeState", { elapsedTime = elapsed, timeMultiplier = mult, pausedCount = pausedCount, commitedCount = commitedCount })
			end
		end
	elseif not isClient() then
		-- single player, we trigger the local event
        triggerEvent("OnServerCommand", "TimePasses", "TimeState", { elapsedTime = elapsed, timeMultiplier = -1, pausedCount = pausedCount, commitedCount = commitedCount })
	end
end

function sendMessage(msg)
	if isServer() then
		local onlinePlayers = getOnlinePlayers()
		if onlinePlayers then
			for i = 0, onlinePlayers:size() - 1 do
				local p = onlinePlayers:get(i)
				sendServerCommand(p, "TimePasses", "Message", { msg = msg })
			end
		end
	end
end

TimePasses.OnTick = function()
	UpdateTimeMultiplier()
	UpdateServerSystemTime()
end
if TimePasses.OnTick then
    Events.OnTick.Remove(TimePasses.OnTick)
end
Events.OnTick.Add(TimePasses.OnTick)