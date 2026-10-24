TimePasses = TimePasses or {}

TimePasses.Config = {
    MAX_SPEED = 40.0,
    SECONDS_TO_MAX = 15.0,
    MEMORY_DECAY = 8.0,
    CATCHUP_SPEED = 20.0
}

TimePasses.computeTimeMultiplier = function(elapsedTime, currentMultiplier, deltaSeconds, gameTime)
    if elapsedTime < 1.0 then 
        return currentMultiplier 
    end
    
    local progress = math.min((elapsedTime - 1) / TimePasses.Config.SECONDS_TO_MAX, 1)
    local easeCurve = progress^2 
    local targetTimeMultiplier = 1.0 + (easeCurve * (TimePasses.Config.MAX_SPEED - 1.0))
    
    -- Catching up linearly
    local newMultiplier = math.min(targetTimeMultiplier, currentMultiplier + (TimePasses.Config.CATCHUP_SPEED * deltaSeconds))
    
	gameTime:setMultiplier(newMultiplier)
    newMultiplier = gameTime:getTrueMultiplier()
    return newMultiplier
end