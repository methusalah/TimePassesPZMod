-- only draw the panel if we are client, and not for server nor solo
if not isClient() then return end

require "ISUI/ISPanel"
require "ISUI/ISButton"

TimePassesPanel = ISPanel:derive("TimePassesPanel")

function TimePassesPanel:initialise()
    ISPanel.initialise(self)
    self.textures = {
        pauseOn   = Texture.getSharedTexture("media/ui/speedControls/Pause_On.png"),
        pauseOff  = Texture.getSharedTexture("media/ui/speedControls/Pause_Off.png"),
        playOn    = Texture.getSharedTexture("media/ui/speedControls/Play_On.png"),
        playOff   = Texture.getSharedTexture("media/ui/speedControls/Play_Off.png"),
        waitOn    = Texture.getSharedTexture("media/ui/speedControls/Wait_On.png"),
        waitOff   = Texture.getSharedTexture("media/ui/speedControls/Wait_Off.png")
    }
    self:create()
end

function TimePassesPanel:create()
	self.backgroundColor = {r=0, g=0, b=0, a=0}
    self.borderColor = {r=0, g=0, b=0, a=0}
    
	local btnSize = 32 

    -- Pause button
    self.pauseBtn = ISButton:new(0, 0, btnSize, btnSize, "", self, self.onBtnClick)
    self.pauseBtn.internal = "PAUSE"
    self.pauseBtn:setDisplayBackground(true)
	self.pauseBtn.backgroundColor = {r=0, g=0, b=0, a=0.5}
    self.pauseBtn.borderColor = {r=0, g=0, b=0, a=0}
    self:addChild(self.pauseBtn)

    -- Play button
    self.playBtn = ISButton:new(btnSize, 0, btnSize, btnSize, "", self, self.onBtnClick)
    self.playBtn.internal = "PLAY"
    self.playBtn:setDisplayBackground(true)
	self.playBtn.backgroundColor = {r=0, g=0, b=0, a=0.5}
    self.playBtn.borderColor = {r=0, g=0, b=0, a=0}
    self:addChild(self.playBtn)

    -- Wait button
    self.waitBtn = ISButton:new(btnSize * 2, 0, btnSize, btnSize, "", self, self.onBtnClick)
    self.waitBtn.internal = "WAIT"
    self.waitBtn:setDisplayBackground(true)
	self.waitBtn.backgroundColor = {r=0, g=0, b=0, a=0.5}
    self.waitBtn.borderColor = {r=0, g=0, b=0, a=0}
    self:addChild(self.waitBtn)
end

function TimePassesPanel:onBtnClick(button)
    if TimePasses and TimePasses.SetControlState then
        TimePasses.SetControlState(button.internal)
    end
end

function TimePassesPanel:update()
    if not TimePasses then return end

    local pauseTex = TimePasses.isPaused and self.textures.pauseOn or self.textures.pauseOff
   
    local isPlayActive = (not TimePasses.isPaused and not TimePasses.isWaiting)
    local playTex = isPlayActive and self.textures.playOn or self.textures.playOff
    
    local waitTex = TimePasses.isWaiting and self.textures.waitOn or self.textures.waitOff

    -- apply image
    self.pauseBtn:setImage(pauseTex)
    self.playBtn:setImage(playTex)
    self.waitBtn:setImage(waitTex)

    -- follow speed controls UI as much as possible
    local speedControls = UIManager.getSpeedControls()
    if speedControls then
        local x = speedControls:getAbsoluteX()
        local y = speedControls:getY() 
        
		local spacing = 2
        local btnSize = speedControls:getHeight()
		
		-- we try to refer to the pause button if it exists
        local pauseButton = speedControls:getControls():get(0)
        if pauseButton then
            x = pauseButton:getAbsoluteX()
            btnSize = pauseButton:getHeight() 
        end
		
		local imageSize = btnSize - 6

        -- adjust panel position and size
        self:setX(x)
        self:setY(y)
        self:setWidth((btnSize+2) * 3)
        self:setHeight(btnSize)

        -- adjust buttons position and size
        self.pauseBtn:setX(0)
        self.pauseBtn:setWidth(btnSize)
        self.pauseBtn:setHeight(btnSize)
		self.pauseBtn:forceImageSize(imageSize, imageSize)

        self.playBtn:setX(btnSize + spacing)
        self.playBtn:setWidth(btnSize)
        self.playBtn:setHeight(btnSize)
		--self.playBtn:forceImageSize(imageSize, imageSize)

        self.waitBtn:setX((btnSize + spacing) * 2)
        self.waitBtn:setWidth(btnSize)
        self.waitBtn:setHeight(btnSize)
		self.waitBtn:forceImageSize(imageSize, imageSize)
		
		-- pause button animation
		local pulsation = 0
		if TimePasses.pauseAnimTimer > 0 then
			pulsation = 1 - (math.abs((TimePasses.pauseAnimTimer or 0) - 0.5) * 2)
		end
        self.pauseBtn:forceImageSize(imageSize + 10 * pulsation, imageSize + 10 * pulsation)

		-- wait button animation
		pulsation = 0
		if TimePasses.waitAnimTimer > 0 then
			pulsation = 1 - (math.abs((TimePasses.waitAnimTimer or 0) - 0.5) * 2)
		end
        self.waitBtn:forceImageSize(imageSize + 10 * pulsation, imageSize + 10 * pulsation)
    end
end

local function SetupTimePassesPanel()
    if isServer() then return end 

    if TimePassesUI then
        TimePassesUI:removeFromUIManager()
    end

    TimePassesUI = TimePassesPanel:new(0, 0, 96, 32)
    TimePassesUI:initialise()
    TimePassesUI:addToUIManager()
end

Events.OnCreateUI.Add(SetupTimePassesPanel)