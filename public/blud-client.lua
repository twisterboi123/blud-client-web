local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

local player = Players.LocalPlayer

----------------------------------------------------------------
-- THEME (matches the Blud Client site: near-black + blue hover)
----------------------------------------------------------------
local theme = {
	bgMain       = Color3.fromRGB(8, 8, 10),     -- window background
	bgSidebar    = Color3.fromRGB(13, 13, 16),   -- sidebar background
	bgSurface2   = Color3.fromRGB(16, 16, 20),   -- default button / input surface
	border       = Color3.fromRGB(34, 34, 40),   -- default hairline border
	borderHover  = Color3.fromRGB(91, 147, 255), -- blue border on hover
	blue         = Color3.fromRGB(43, 107, 255), -- accent blue
	blueBright   = Color3.fromRGB(91, 147, 255), -- lighter blue (hover/press)
	blueRow      = Color3.fromRGB(24, 48, 102),  -- muted blue for list-row hover
	textPrimary  = Color3.fromRGB(255, 255, 255),
	textMuted    = Color3.fromRGB(150, 150, 158),
	success      = Color3.fromRGB(70, 200, 120),
	danger       = Color3.fromRGB(150, 45, 45),
	dangerBright = Color3.fromRGB(190, 60, 60),
}

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------
local settings = {
	highlightColor = Color3.fromRGB(255, 0, 0),
	outlineColor = Color3.fromRGB(0, 0, 0),
	flySpeed = 50,
	speedMultiplier = 2,
	followDistance = 5
}

----------------------------------------------------------------
-- KEY SYSTEM CONFIG
-- Uses secure backend validation (keys are never exposed publicly)
----------------------------------------------------------------
local keySystem = {
	validationUrl  = "https://www.bludclient.site/validate-key", -- backend validation endpoint
	getKeyUrl      = "https://www.bludclient.site/", -- page to get a key
	saveKeyLocally = false,               -- remembers a valid key between sessions (needs writefile/readfile/isfile)
	saveFile       = "BludClientKey.txt"
}

----------------------------------------------------------------
-- STATE VARIABLES
----------------------------------------------------------------
local highlightEnabled = false
local flying = false
local speedBoostEnabled = false
local following = false
local currentFollowTarget = nil
local followConnection = nil

local bodyVelocity, bodyGyro, flyConnection
local keys = {w=false, a=false, s=false, d=false, space=false, shift=false}
local originalWalkSpeed = 16

----------------------------------------------------------------
-- HIGHLIGHT FUNCTIONS
----------------------------------------------------------------
local function applyHighlight(character)
	if not character then return end
	local existing = character:FindFirstChild("Highlight")
	if existing then existing:Destroy() end

	local highlight = Instance.new("Highlight")
	highlight.FillColor = settings.highlightColor
	highlight.OutlineColor = settings.outlineColor
	highlight.FillTransparency = 0.5
	highlight.Parent = character
end

local function removeHighlight(character)
	if not character then return end
	local existing = character:FindFirstChild("Highlight")
	if existing then existing:Destroy() end
end

local function refreshAllHighlights()
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			if highlightEnabled then
				applyHighlight(p.Character)
			else
				removeHighlight(p.Character)
			end
		end
	end
end

local function toggleHighlights()
	highlightEnabled = not highlightEnabled
	refreshAllHighlights()
end

Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(character)
		if highlightEnabled then
			applyHighlight(character)
		end
	end)
end)

for _, p in ipairs(Players:GetPlayers()) do
	p.CharacterAdded:Connect(function(character)
		if highlightEnabled then
			applyHighlight(character)
		end
	end)
end

----------------------------------------------------------------
-- FLY FUNCTIONS
----------------------------------------------------------------
local function startFly()
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end

	flying = true
	humanoid.PlatformStand = true

	bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bodyVelocity.Velocity = Vector3.new(0, 0, 0)
	bodyVelocity.Parent = hrp

	bodyGyro = Instance.new("BodyGyro")
	bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
	bodyGyro.P = 3000
	bodyGyro.Parent = hrp

	flyConnection = RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		local moveVector = Vector3.new(0, 0, 0)

		if keys.w then moveVector += camera.CFrame.LookVector end
		if keys.s then moveVector -= camera.CFrame.LookVector end
		if keys.a then moveVector -= camera.CFrame.RightVector end
		if keys.d then moveVector += camera.CFrame.RightVector end
		if keys.space then moveVector += Vector3.new(0, 1, 0) end
		if keys.shift then moveVector -= Vector3.new(0, 1, 0) end

		if moveVector.Magnitude > 0 then
			moveVector = moveVector.Unit * settings.flySpeed
		end

		bodyVelocity.Velocity = moveVector
		bodyGyro.CFrame = camera.CFrame
	end)
end

local function stopFly()
	flying = false
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.PlatformStand = false end
	end
	if bodyVelocity then bodyVelocity:Destroy() end
	if bodyGyro then bodyGyro:Destroy() end
	if flyConnection then flyConnection:Disconnect() end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.W then keys.w = true end
	if input.KeyCode == Enum.KeyCode.A then keys.a = true end
	if input.KeyCode == Enum.KeyCode.S then keys.s = true end
	if input.KeyCode == Enum.KeyCode.D then keys.d = true end
	if input.KeyCode == Enum.KeyCode.Space then keys.space = true end
	if input.KeyCode == Enum.KeyCode.LeftShift then keys.shift = true end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.W then keys.w = false end
	if input.KeyCode == Enum.KeyCode.A then keys.a = false end
	if input.KeyCode == Enum.KeyCode.S then keys.s = false end
	if input.KeyCode == Enum.KeyCode.D then keys.d = false end
	if input.KeyCode == Enum.KeyCode.Space then keys.space = false end
	if input.KeyCode == Enum.KeyCode.LeftShift then keys.shift = false end
end)

----------------------------------------------------------------
-- SPEED BOOST FUNCTIONS
----------------------------------------------------------------
local function toggleSpeedBoost()
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	speedBoostEnabled = not speedBoostEnabled

	if speedBoostEnabled then
		originalWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = originalWalkSpeed * settings.speedMultiplier
	else
		humanoid.WalkSpeed = originalWalkSpeed
	end
end

player.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid")
	if speedBoostEnabled then
		originalWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = originalWalkSpeed * settings.speedMultiplier
	end
end)

----------------------------------------------------------------
-- TELEPORT FUNCTIONS
----------------------------------------------------------------
local function teleportToPlayer(targetPlayer)
	if not targetPlayer then return end
	if targetPlayer == player then return end

	local myCharacter = player.Character
	local targetCharacter = targetPlayer.Character

	if not myCharacter or not targetCharacter then return end

	local myHRP = myCharacter:FindFirstChild("HumanoidRootPart")
	local targetHRP = targetCharacter:FindFirstChild("HumanoidRootPart")

	if not myHRP or not targetHRP then return end

	myHRP.CFrame = targetHRP.CFrame + Vector3.new(0, 3, 0)
end

----------------------------------------------------------------
-- FOLLOW FUNCTIONS
----------------------------------------------------------------
local function stopFollowing()
	following = false
	currentFollowTarget = nil
	if followConnection then
		followConnection:Disconnect()
		followConnection = nil
	end
end

local function startFollowing(targetPlayer)
	if not targetPlayer or targetPlayer == player then return end

	stopFollowing()
	currentFollowTarget = targetPlayer
	following = true

	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentJumpDistance = 10,
		AgentMaxSlope = 45
	})

	followConnection = RunService.Heartbeat:Connect(function()
		if not following or not currentFollowTarget then return end

		local myChar = player.Character
		local targetChar = currentFollowTarget.Character
		if not myChar or not targetChar then
			stopFollowing()
			return
		end

		local myHRP = myChar:FindFirstChild("HumanoidRootPart")
		local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
		local humanoid = myChar:FindFirstChildOfClass("Humanoid")
		if not myHRP or not targetHRP or not humanoid then return end

		local distance = (myHRP.Position - targetHRP.Position).Magnitude
		if distance <= settings.followDistance then
			humanoid:MoveTo(myHRP.Position)
			return
		end

		local success = pcall(function()
			path:ComputeAsync(myHRP.Position, targetHRP.Position)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			for i, waypoint in ipairs(waypoints) do
				if not following or currentFollowTarget ~= targetPlayer then break end
				if not player.Character then break end

				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				local hum = player.Character:FindFirstChildOfClass("Humanoid")
				if not hrp or not hum then break end

				local targetCharCheck = currentFollowTarget.Character
				if targetCharCheck then
					local targetHRPCheck = targetCharCheck:FindFirstChild("HumanoidRootPart")
					if targetHRPCheck then
						local dist = (hrp.Position - targetHRPCheck.Position).Magnitude
						if dist <= settings.followDistance then
							hum:MoveTo(hrp.Position)
							break
						end
					end
				end

				hum:MoveTo(waypoint.Position)

				if waypoint.Action == Enum.PathWaypointAction.Jump then
					hum:ChangeState(Enum.HumanoidStateType.Jumping)
				end

				hum.MoveToFinished:Wait()
			end
		end
	end)
end

----------------------------------------------------------------
-- HTTP REQUEST BYPASS
-- HttpService:HttpGet only works if the *game* has HttpEnabled turned on,
-- and some games turn it off specifically to block scripts like this one.
-- Executors expose their own request function that talks to the outside
-- world directly rather than going through Roblox's HttpService, so we
-- prefer that and only fall back to HttpService if nothing else exists.
----------------------------------------------------------------
local function httpRequest(method, url, body)
	local requestFunc = (syn and syn.request)
		or http_request
		or (fluxus and fluxus.request)
		or request
		or (http and http.request)

	if requestFunc then
		local ok, result = pcall(function()
			local payload = {
				Url = url,
				Method = method,
				Headers = { ["Content-Type"] = "application/json" }
			}
			if body then
				payload.Body = body
			end
			local res = requestFunc(payload)
			return res.Body or res.body
		end)
		if ok and result then
			return result
		end
	end

	-- Fallback to HttpService
	if method == "POST" then
		local ok, result = pcall(function()
			return game:HttpPost(url, body or "", Enum.HttpContentType.ApplicationJson)
		end)
		if ok then return result end
	else
		local ok, result = pcall(function()
			return game:HttpGet(url)
		end)
		if ok then return result end
	end

	return nil
end

----------------------------------------------------------------
-- KEY VERIFICATION (now uses secure backend)
----------------------------------------------------------------
local function verifyKey(keyText)
	if not keyText or keyText:gsub("%s", "") == "" then
		return false, "Enter a key first"
	end

	local payload = game:GetService("HttpService"):JSONEncode({ key = keyText })
	local raw = httpRequest("POST", keySystem.validationUrl, payload)
	
	if not raw then
		return false, "Could not reach key server"
	end

	local ok, decoded = pcall(function()
		return game:GetService("HttpService"):JSONDecode(raw)
	end)
	
	if not ok or not decoded then
		return false, "Invalid response from server"
	end

	if decoded.valid then
		return true
	else
		return false, "Invalid key"
	end
end

----------------------------------------------------------------
-- SHARED UI HELPERS
----------------------------------------------------------------
local function makeDraggable(dragHandle, target)
	local dragging = false
	local dragInput, dragStart, startPos

	dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = target.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	dragHandle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

local function createStyledButton(text, parent)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 45)
	button.BackgroundColor3 = theme.bgSurface2
	button.Text = text
	button.TextColor3 = theme.textPrimary
	button.TextScaled = true
	button.Font = Enum.Font.GothamMedium
	button.AutoButtonColor = false
	button.ZIndex = 2
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = theme.border
	stroke.Thickness = 1
	stroke.Parent = button

	local defaultColor = theme.bgSurface2
	local hoverColor = theme.blue
	local clickColor = theme.blueBright

	local function tweenColor(color, duration)
		TweenService:Create(button, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			BackgroundColor3 = color
		}):Play()
	end

	local function tweenStroke(color, duration)
		TweenService:Create(stroke, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Color = color
		}):Play()
	end

	local function tweenSize(size, duration)
		TweenService:Create(button, TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = size
		}):Play()
	end

	button.MouseEnter:Connect(function()
		tweenColor(hoverColor, 0.15)
		tweenStroke(theme.borderHover, 0.15)
	end)
	button.MouseLeave:Connect(function()
		tweenColor(defaultColor, 0.15)
		tweenStroke(theme.border, 0.15)
	end)
	button.MouseButton1Down:Connect(function()
		tweenColor(clickColor, 0.1)
		tweenSize(UDim2.new(1, -6, 0, 42), 0.1)
	end)
	button.MouseButton1Up:Connect(function()
		tweenColor(hoverColor, 0.15)
		tweenSize(UDim2.new(1, 0, 0, 45), 0.15)
	end)

	return button
end

----------------------------------------------------------------
-- KEY SYSTEM GUI
----------------------------------------------------------------
local keyGui, keyInput, statusLabel, submitBtn, getKeyBtn

local function destroyKeyGui()
	if keyGui then
		keyGui:Destroy()
		keyGui = nil
	end
end

local function setKeyStatus(text, color)
	if not statusLabel then return end
	statusLabel.Text = text
	statusLabel.TextColor3 = color or theme.textMuted
end

local function buildKeyGui()
	keyGui = Instance.new("ScreenGui")
	keyGui.Name = "BludKeyGui"
	keyGui.ResetOnSpawn = false
	keyGui.Parent = player:WaitForChild("PlayerGui")

	local keyFrame = Instance.new("Frame")
	keyFrame.Name = "KeyFrame"
	keyFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	keyFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	keyFrame.Size = UDim2.new(0, 340, 0, 250)
	keyFrame.BackgroundColor3 = theme.bgMain
	keyFrame.BorderSizePixel = 0
	keyFrame.ZIndex = 2
	keyFrame.Parent = keyGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = keyFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = theme.border
	stroke.Thickness = 1.5
	stroke.Parent = keyFrame

	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 40)
	titleBar.BackgroundTransparency = 1
	titleBar.ZIndex = 3
	titleBar.Parent = keyFrame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 24)
	title.Position = UDim2.new(0, 10, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = "Blud Client"
	title.TextColor3 = theme.textPrimary
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	title.Parent = titleBar

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -20, 0, 18)
	subtitle.Position = UDim2.new(0, 10, 0, 44)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Enter a key to continue"
	subtitle.TextColor3 = theme.textMuted
	subtitle.TextScaled = true
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.ZIndex = 2
	subtitle.Parent = keyFrame

	keyInput = Instance.new("TextBox")
	keyInput.Size = UDim2.new(1, -40, 0, 42)
	keyInput.Position = UDim2.new(0, 20, 0, 74)
	keyInput.BackgroundColor3 = theme.bgSurface2
	keyInput.PlaceholderText = "Enter key here..."
	keyInput.Text = ""
	keyInput.TextColor3 = theme.textPrimary
	keyInput.PlaceholderColor3 = theme.textMuted
	keyInput.TextScaled = true
	keyInput.Font = Enum.Font.Gotham
	keyInput.ClearTextOnFocus = false
	keyInput.ZIndex = 2
	keyInput.Parent = keyFrame

	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 8)
	inputCorner.Parent = keyInput

	local inputStroke = Instance.new("UIStroke")
	inputStroke.Color = theme.border
	inputStroke.Thickness = 1
	inputStroke.Parent = keyInput

	keyInput.Focused:Connect(function()
		TweenService:Create(inputStroke, TweenInfo.new(0.15), {Color = theme.borderHover}):Play()
	end)
	keyInput.FocusLost:Connect(function()
		TweenService:Create(inputStroke, TweenInfo.new(0.15), {Color = theme.border}):Play()
	end)

	statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -40, 0, 18)
	statusLabel.Position = UDim2.new(0, 20, 0, 120)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = ""
	statusLabel.TextColor3 = theme.textMuted
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.ZIndex = 2
	statusLabel.Parent = keyFrame

	local buttonRow = Instance.new("Frame")
	buttonRow.Size = UDim2.new(1, -40, 0, 42)
	buttonRow.Position = UDim2.new(0, 20, 0, 148)
	buttonRow.BackgroundTransparency = 1
	buttonRow.ZIndex = 2
	buttonRow.Parent = keyFrame

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.Parent = buttonRow

	getKeyBtn = createStyledButton("Get Key", buttonRow)
	getKeyBtn.Size = UDim2.new(0.5, -5, 1, 0)

	submitBtn = createStyledButton("Submit", buttonRow)
	submitBtn.Size = UDim2.new(0.5, -5, 1, 0)

	local footNote = Instance.new("TextLabel")
	footNote.Size = UDim2.new(1, -40, 0, 30)
	footNote.Position = UDim2.new(0, 20, 0, 204)
	footNote.BackgroundTransparency = 1
	footNote.Text = "Get Key copies the key page link to your clipboard"
	footNote.TextColor3 = theme.textMuted
	footNote.TextTransparency = 0.25
	footNote.TextWrapped = true
	footNote.TextScaled = true
	footNote.Font = Enum.Font.Gotham
	footNote.ZIndex = 2
	footNote.Parent = keyFrame

	makeDraggable(titleBar, keyFrame)

	getKeyBtn.MouseButton1Click:Connect(function()
		local url = keySystem.getKeyUrl
		local copied = false
		if setclipboard then
			copied = pcall(setclipboard, url)
		end
		if copied then
			setKeyStatus("Link copied — paste it in your browser", theme.textMuted)
		else
			setKeyStatus("Visit: " .. url, theme.textMuted)
		end
	end)

	submitBtn.MouseButton1Click:Connect(function()
		local enteredKey = keyInput.Text

		setKeyStatus("Checking key...", theme.textMuted)
		submitBtn.Text = "Checking..."

		task.spawn(function()
			local valid, err = verifyKey(enteredKey)

			if valid then
				setKeyStatus("Key accepted!", theme.success)
				if keySystem.saveKeyLocally and writefile then
					pcall(writefile, keySystem.saveFile, enteredKey)
				end
				task.wait(0.4)
				destroyKeyGui()
				buildMainClient()
			else
				submitBtn.Text = "Submit"
				setKeyStatus(err or "Invalid key", theme.dangerBright)
			end
		end)
	end)
end

----------------------------------------------------------------
-- MAIN CLIENT (built only after a valid key is entered)
----------------------------------------------------------------
function buildMainClient()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BludClientGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player:WaitForChild("PlayerGui")

	----------------------------------------------------------------
	-- MAIN FRAME
	----------------------------------------------------------------
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 400, 0, 320)
	mainFrame.Position = UDim2.new(0, 20, 0, 20)
	mainFrame.BackgroundColor3 = theme.bgMain
	mainFrame.BorderSizePixel = 0
	mainFrame.ZIndex = 2
	mainFrame.Parent = screenGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 12)
	mainCorner.Parent = mainFrame

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = theme.border
	mainStroke.Thickness = 1.5
	mainStroke.Parent = mainFrame

	-- Title Bar (Full width, on top)
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 40)
	titleBar.BackgroundTransparency = 1
	titleBar.ZIndex = 10
	titleBar.Parent = mainFrame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -80, 1, 0)
	title.Position = UDim2.new(0, 10, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "Blud Client"
	title.TextColor3 = theme.textPrimary
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Font = Enum.Font.GothamBold
	title.ZIndex = 10
	title.Parent = titleBar

	local minimizeButton = Instance.new("TextButton")
	minimizeButton.Size = UDim2.new(0, 24, 0, 24)
	minimizeButton.Position = UDim2.new(1, -32, 0, 8)
	minimizeButton.BackgroundColor3 = theme.bgSurface2
	minimizeButton.Text = "-"
	minimizeButton.TextColor3 = theme.textPrimary
	minimizeButton.TextScaled = true
	minimizeButton.Font = Enum.Font.GothamBold
	minimizeButton.AutoButtonColor = false
	minimizeButton.ZIndex = 10
	minimizeButton.Parent = titleBar

	local minimizeCorner = Instance.new("UICorner")
	minimizeCorner.CornerRadius = UDim.new(0, 6)
	minimizeCorner.Parent = minimizeButton

	minimizeButton.MouseEnter:Connect(function()
		TweenService:Create(minimizeButton, TweenInfo.new(0.15), {BackgroundColor3 = theme.blue}):Play()
	end)
	minimizeButton.MouseLeave:Connect(function()
		TweenService:Create(minimizeButton, TweenInfo.new(0.15), {BackgroundColor3 = theme.bgSurface2}):Play()
	end)

	-- Sidebar (Below title bar)
	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.Size = UDim2.new(0, 100, 1, -40)
	sidebar.Position = UDim2.new(0, 0, 0, 40)
	sidebar.BackgroundColor3 = theme.bgSidebar
	sidebar.BorderSizePixel = 0
	sidebar.ZIndex = 3
	sidebar.Parent = mainFrame

	local sidebarCorner = Instance.new("UICorner")
	sidebarCorner.CornerRadius = UDim.new(0, 0, 0, 12)
	sidebarCorner.Parent = sidebar

	local sidebarLayout = Instance.new("UIListLayout")
	sidebarLayout.Padding = UDim.new(0, 5)
	sidebarLayout.Parent = sidebar

	-- Content Area
	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, -110, 1, -50)
	contentFrame.Position = UDim2.new(0, 105, 0, 45)
	contentFrame.BackgroundTransparency = 1
	contentFrame.ZIndex = 2
	contentFrame.Parent = mainFrame

	-- Category title
	local categoryTitle = Instance.new("TextLabel")
	categoryTitle.Size = UDim2.new(1, 0, 0, 30)
	categoryTitle.BackgroundTransparency = 1
	categoryTitle.Text = "Movement"
	categoryTitle.TextColor3 = theme.textPrimary
	categoryTitle.TextScaled = true
	categoryTitle.Font = Enum.Font.GothamBold
	categoryTitle.TextXAlignment = Enum.TextXAlignment.Left
	categoryTitle.ZIndex = 2
	categoryTitle.Parent = contentFrame

	-- Buttons container
	local buttonsContainer = Instance.new("Frame")
	buttonsContainer.Size = UDim2.new(1, 0, 1, -35)
	buttonsContainer.Position = UDim2.new(0, 0, 0, 35)
	buttonsContainer.BackgroundTransparency = 1
	buttonsContainer.ZIndex = 2
	buttonsContainer.Parent = contentFrame

	local buttonsLayout = Instance.new("UIListLayout")
	buttonsLayout.Padding = UDim.new(0, 10)
	buttonsLayout.Parent = buttonsContainer

	local categoryButtons = {}

	local function createCategoryButton(text)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -10, 0, 35)
		btn.Position = UDim2.new(0, 5, 0, 0)
		btn.BackgroundColor3 = theme.bgSurface2
		btn.Text = text
		btn.TextColor3 = theme.textPrimary
		btn.TextScaled = true
		btn.Font = Enum.Font.GothamMedium
		btn.AutoButtonColor = false
		btn.ZIndex = 3
		btn.Parent = sidebar

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = btn

		table.insert(categoryButtons, btn)

		return btn
	end

	----------------------------------------------------------------
	-- CATEGORY BUTTONS
	----------------------------------------------------------------
	local movementBtn = createCategoryButton("Movement")
	local visualsBtn = createCategoryButton("Visuals")
	local playerBtn = createCategoryButton("Player")

	----------------------------------------------------------------
	-- BUTTON CREATION PER CATEGORY
	----------------------------------------------------------------
	local function clearButtons()
		for _, child in ipairs(buttonsContainer:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
	end

	local function updateCategoryColors(activeBtn)
		for _, btn in ipairs(categoryButtons) do
			if btn == activeBtn then
				TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = theme.blue}):Play()
			else
				TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = theme.bgSurface2}):Play()
			end
		end
	end

	-- Movement buttons
	local function createMovementButtons()
		clearButtons()
		categoryTitle.Text = "Movement"

		local flyBtn = createStyledButton("Fly: " .. (flying and "ON" or "OFF"), buttonsContainer)
		flyBtn.MouseButton1Click:Connect(function()
			if flying then
				stopFly()
				flyBtn.Text = "Fly: OFF"
			else
				startFly()
				flyBtn.Text = "Fly: ON"
			end
		end)

		local speedBtn = createStyledButton("Speed: " .. (speedBoostEnabled and "ON" or "OFF"), buttonsContainer)
		speedBtn.MouseButton1Click:Connect(function()
			toggleSpeedBoost()
			speedBtn.Text = "Speed: " .. (speedBoostEnabled and "ON" or "OFF")
		end)

		-- Right click handlers
		flyBtn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				openSettingsPopup(flyPopup, flyBtn)
			end
		end)

		speedBtn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				openSettingsPopup(speedPopup, speedBtn)
			end
		end)
	end

	-- Visuals buttons
	local function createVisualsButtons()
		clearButtons()
		categoryTitle.Text = "Visuals"

		local highlightBtn = createStyledButton("Highlight: " .. (highlightEnabled and "ON" or "OFF"), buttonsContainer)
		highlightBtn.MouseButton1Click:Connect(function()
			toggleHighlights()
			highlightBtn.Text = "Highlight: " .. (highlightEnabled and "ON" or "OFF")
		end)

		highlightBtn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				openSettingsPopup(highlightPopup, highlightBtn)
			end
		end)
	end

	-- Player buttons
	local function createPlayerButtons()
		clearButtons()
		categoryTitle.Text = "Player"

		local teleportBtn = createStyledButton("Teleport", buttonsContainer)
		teleportBtn.MouseButton1Click:Connect(function()
			openSelector("Teleport")
		end)

		local followBtnText = "Follow"
		if following and currentFollowTarget then
			followBtnText = "Following: " .. currentFollowTarget.Name
		end

		local followBtn = createStyledButton(followBtnText, buttonsContainer)
		followBtn.MouseButton1Click:Connect(function()
			openSelector("Follow")
		end)

		followBtn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				openSettingsPopup(followPopup, followBtn)
			end
		end)
	end

	----------------------------------------------------------------
	-- CATEGORY SWITCHING
	----------------------------------------------------------------
	movementBtn.MouseButton1Click:Connect(function()
		updateCategoryColors(movementBtn)
		createMovementButtons()
	end)

	visualsBtn.MouseButton1Click:Connect(function()
		updateCategoryColors(visualsBtn)
		createVisualsButtons()
	end)

	playerBtn.MouseButton1Click:Connect(function()
		updateCategoryColors(playerBtn)
		createPlayerButtons()
	end)

	-- Show Movement by default
	updateCategoryColors(movementBtn)
	createMovementButtons()

	----------------------------------------------------------------
	-- MINIMIZE LOGIC
	----------------------------------------------------------------
	local minimized = false
	local expandedSize = UDim2.new(0, 400, 0, 320)
	local minimizedSize = UDim2.new(0, 220, 0, 40)

	minimizeButton.MouseButton1Click:Connect(function()
		minimized = not minimized
		sidebar.Visible = not minimized
		contentFrame.Visible = not minimized
		minimizeButton.Text = minimized and "+" or "-"
		TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = minimized and minimizedSize or expandedSize
		}):Play()
	end)

	makeDraggable(titleBar, mainFrame)

	----------------------------------------------------------------
	-- PLAYER SELECTOR POPUP
	----------------------------------------------------------------
	local selectedPlayer = nil
	local currentMode = nil

	local selectorPopup = Instance.new("Frame")
	selectorPopup.Name = "SelectorPopup"
	selectorPopup.Size = UDim2.new(0, 280, 0, 360)
	selectorPopup.BackgroundColor3 = theme.bgMain
	selectorPopup.BorderSizePixel = 0
	selectorPopup.Visible = false
	selectorPopup.ZIndex = 10
	selectorPopup.Parent = screenGui

	local selectorCorner = Instance.new("UICorner")
	selectorCorner.CornerRadius = UDim.new(0, 12)
	selectorCorner.Parent = selectorPopup

	local selectorStroke = Instance.new("UIStroke")
	selectorStroke.Color = theme.border
	selectorStroke.Thickness = 1.5
	selectorStroke.Parent = selectorPopup

	-- Title Bar
	local selectorTitleBar = Instance.new("Frame")
	selectorTitleBar.Size = UDim2.new(1, 0, 0, 34)
	selectorTitleBar.BackgroundTransparency = 1
	selectorTitleBar.ZIndex = 10
	selectorTitleBar.Parent = selectorPopup

	local selectorTitleLabel = Instance.new("TextLabel")
	selectorTitleLabel.Size = UDim2.new(1, -40, 1, 0)
	selectorTitleLabel.Position = UDim2.new(0, 10, 0, 0)
	selectorTitleLabel.BackgroundTransparency = 1
	selectorTitleLabel.Text = "Select Player"
	selectorTitleLabel.TextColor3 = theme.textPrimary
	selectorTitleLabel.TextScaled = true
	selectorTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	selectorTitleLabel.Font = Enum.Font.GothamBold
	selectorTitleLabel.ZIndex = 10
	selectorTitleLabel.Parent = selectorTitleBar

	local selectorCloseButton = Instance.new("TextButton")
	selectorCloseButton.Size = UDim2.new(0, 22, 0, 22)
	selectorCloseButton.Position = UDim2.new(1, -30, 0, 6)
	selectorCloseButton.BackgroundColor3 = theme.bgSurface2
	selectorCloseButton.Text = "X"
	selectorCloseButton.TextColor3 = theme.textPrimary
	selectorCloseButton.TextScaled = true
	selectorCloseButton.Font = Enum.Font.GothamBold
	selectorCloseButton.AutoButtonColor = false
	selectorCloseButton.ZIndex = 10
	selectorCloseButton.Parent = selectorTitleBar

	local selectorCloseCorner = Instance.new("UICorner")
	selectorCloseCorner.CornerRadius = UDim.new(0, 6)
	selectorCloseCorner.Parent = selectorCloseButton

	selectorCloseButton.MouseEnter:Connect(function()
		TweenService:Create(selectorCloseButton, TweenInfo.new(0.15), {BackgroundColor3 = theme.danger}):Play()
	end)
	selectorCloseButton.MouseLeave:Connect(function()
		TweenService:Create(selectorCloseButton, TweenInfo.new(0.15), {BackgroundColor3 = theme.bgSurface2}):Play()
	end)
	selectorCloseButton.MouseButton1Click:Connect(function()
		selectorPopup.Visible = false
	end)

	-- Divider
	local selectorDivider = Instance.new("Frame")
	selectorDivider.Size = UDim2.new(1, -20, 0, 1)
	selectorDivider.Position = UDim2.new(0, 10, 0, 34)
	selectorDivider.BackgroundColor3 = theme.border
	selectorDivider.BorderSizePixel = 0
	selectorDivider.ZIndex = 10
	selectorDivider.Parent = selectorPopup

	-- Selected Label
	local selectedLabel = Instance.new("TextLabel")
	selectedLabel.Size = UDim2.new(1, -20, 0, 25)
	selectedLabel.Position = UDim2.new(0, 10, 0, 42)
	selectedLabel.BackgroundTransparency = 1
	selectedLabel.Text = "Selected: None"
	selectedLabel.TextColor3 = theme.textMuted
	selectedLabel.TextScaled = true
	selectedLabel.Font = Enum.Font.Gotham
	selectedLabel.TextXAlignment = Enum.TextXAlignment.Left
	selectedLabel.ZIndex = 10
	selectedLabel.Parent = selectorPopup

	-- Scrolling Frame
	local selectorScroll = Instance.new("ScrollingFrame")
	selectorScroll.Size = UDim2.new(1, -20, 0, 220)
	selectorScroll.Position = UDim2.new(0, 10, 0, 72)
	selectorScroll.BackgroundColor3 = theme.bgSidebar
	selectorScroll.BorderSizePixel = 0
	selectorScroll.ScrollBarThickness = 6
	selectorScroll.ScrollBarImageColor3 = theme.blue
	selectorScroll.ZIndex = 10
	selectorScroll.Parent = selectorPopup

	local selectorScrollCorner = Instance.new("UICorner")
	selectorScrollCorner.CornerRadius = UDim.new(0, 8)
	selectorScrollCorner.Parent = selectorScroll

	local selectorListLayout = Instance.new("UIListLayout")
	selectorListLayout.Padding = UDim.new(0, 4)
	selectorListLayout.Parent = selectorScroll

	-- Confirm Button
	local confirmButton = Instance.new("TextButton")
	confirmButton.Size = UDim2.new(1, -20, 0, 40)
	confirmButton.Position = UDim2.new(0, 10, 0, 300)
	confirmButton.BackgroundColor3 = theme.blue
	confirmButton.Text = "Confirm"
	confirmButton.TextColor3 = theme.textPrimary
	confirmButton.TextScaled = true
	confirmButton.Font = Enum.Font.GothamBold
	confirmButton.AutoButtonColor = false
	confirmButton.ZIndex = 10
	confirmButton.Parent = selectorPopup

	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = UDim.new(0, 8)
	confirmCorner.Parent = confirmButton

	local confirmStroke = Instance.new("UIStroke")
	confirmStroke.Color = theme.borderHover
	confirmStroke.Thickness = 1
	confirmStroke.Parent = confirmButton

	confirmButton.MouseEnter:Connect(function()
		TweenService:Create(confirmButton, TweenInfo.new(0.15), {BackgroundColor3 = theme.blueBright}):Play()
	end)
	confirmButton.MouseLeave:Connect(function()
		TweenService:Create(confirmButton, TweenInfo.new(0.15), {BackgroundColor3 = theme.blue}):Play()
	end)

	confirmButton.MouseButton1Click:Connect(function()
		if selectedPlayer then
			if currentMode == "Teleport" then
				teleportToPlayer(selectedPlayer)
			elseif currentMode == "Follow" then
				startFollowing(selectedPlayer)
				createPlayerButtons() -- Refresh to show "Following: Name"
			end
			selectorPopup.Visible = false
		else
			selectedLabel.Text = "Selected: Please select a player!"
			selectedLabel.TextColor3 = theme.dangerBright
			task.delay(1.5, function()
				selectedLabel.Text = "Selected: " .. (selectedPlayer and selectedPlayer.Name or "None")
				selectedLabel.TextColor3 = theme.textMuted
			end)
		end
	end)

	-- Stop Follow Button
	local stopFollowButton = Instance.new("TextButton")
	stopFollowButton.Size = UDim2.new(1, -20, 0, 35)
	stopFollowButton.Position = UDim2.new(0, 10, 0, 260)
	stopFollowButton.BackgroundColor3 = theme.danger
	stopFollowButton.Text = "Stop Following"
	stopFollowButton.TextColor3 = theme.textPrimary
	stopFollowButton.TextScaled = true
	stopFollowButton.Font = Enum.Font.GothamBold
	stopFollowButton.AutoButtonColor = false
	stopFollowButton.ZIndex = 10
	stopFollowButton.Visible = false
	stopFollowButton.Parent = selectorPopup

	local stopFollowCorner = Instance.new("UICorner")
	stopFollowCorner.CornerRadius = UDim.new(0, 8)
	stopFollowCorner.Parent = stopFollowButton

	stopFollowButton.MouseEnter:Connect(function()
		TweenService:Create(stopFollowButton, TweenInfo.new(0.15), {BackgroundColor3 = theme.dangerBright}):Play()
	end)
	stopFollowButton.MouseLeave:Connect(function()
		TweenService:Create(stopFollowButton, TweenInfo.new(0.15), {BackgroundColor3 = theme.danger}):Play()
	end)

	stopFollowButton.MouseButton1Click:Connect(function()
		stopFollowing()
		createPlayerButtons() -- Refresh button text
		stopFollowButton.Visible = false
		confirmButton.Visible = true
		selectorPopup.Visible = false
	end)

	makeDraggable(selectorTitleBar, selectorPopup)

	----------------------------------------------------------------
	-- PLAYER LIST FUNCTIONS
	----------------------------------------------------------------
	local playerButtons = {}

	local function createPlayerListButton(targetPlayer)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -8, 0, 32)
		btn.Position = UDim2.new(0, 4, 0, 0)
		btn.BackgroundColor3 = theme.bgSurface2
		btn.Text = targetPlayer.Name
		btn.TextColor3 = theme.textPrimary
		btn.TextScaled = true
		btn.Font = Enum.Font.Gotham
		btn.AutoButtonColor = false
		btn.ZIndex = 10
		btn.Parent = selectorScroll

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn

		btn.MouseEnter:Connect(function()
			if selectedPlayer ~= targetPlayer then
				TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = theme.blueRow}):Play()
			end
		end)
		btn.MouseLeave:Connect(function()
			if selectedPlayer ~= targetPlayer then
				TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = theme.bgSurface2}):Play()
			end
		end)
		btn.MouseButton1Click:Connect(function()
			for _, button in pairs(playerButtons) do
				TweenService:Create(button, TweenInfo.new(0.1), {BackgroundColor3 = theme.bgSurface2}):Play()
			end
			selectedPlayer = targetPlayer
			selectedLabel.Text = "Selected: " .. targetPlayer.Name
			TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = theme.blue}):Play()
		end)

		playerButtons[targetPlayer] = btn
		return btn
	end

	local function refreshPlayerList()
		for _, btn in pairs(playerButtons) do
			btn:Destroy()
		end
		playerButtons = {}
		selectedPlayer = nil
		selectedLabel.Text = "Selected: None"

		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				createPlayerListButton(p)
			end
		end

		task.wait()
		selectorScroll.CanvasSize = UDim2.new(0, 0, 0, selectorListLayout.AbsoluteContentSize.Y + 8)
	end

	function openSelector(mode)
		currentMode = mode
		selectorTitleLabel.Text = mode .. " - Select Player"
		selectedLabel.Text = "Selected: None"

		if mode == "Follow" and following then
			confirmButton.Visible = false
			stopFollowButton.Visible = true
		else
			confirmButton.Visible = true
			stopFollowButton.Visible = false
		end

		selectorPopup.Visible = true
		refreshPlayerList()
	end

	Players.PlayerAdded:Connect(function()
		if selectorPopup.Visible then
			refreshPlayerList()
		end
	end)

	Players.PlayerRemoving:Connect(function(leftPlayer)
		if playerButtons[leftPlayer] then
			playerButtons[leftPlayer]:Destroy()
			playerButtons[leftPlayer] = nil
		end
		if selectedPlayer == leftPlayer then
			selectedPlayer = nil
			selectedLabel.Text = "Selected: None"
		end
		if selectorPopup.Visible then
			task.wait()
			selectorScroll.CanvasSize = UDim2.new(0, 0, 0, selectorListLayout.AbsoluteContentSize.Y + 8)
		end
	end)

	----------------------------------------------------------------
	-- SETTINGS POPUPS
	----------------------------------------------------------------
	local function createSettingsPopup(popupTitle, rows)
		local popup = Instance.new("Frame")
		popup.Name = popupTitle .. "Popup"
		popup.Size = UDim2.new(0, 200, 0, 40 + (#rows * 45) + 10)
		popup.BackgroundColor3 = theme.bgMain
		popup.BorderSizePixel = 0
		popup.Visible = false
		popup.ZIndex = 5
		popup.Parent = screenGui

		local popupCorner = Instance.new("UICorner")
		popupCorner.CornerRadius = UDim.new(0, 12)
		popupCorner.Parent = popup

		local popupStroke = Instance.new("UIStroke")
		popupStroke.Color = theme.border
		popupStroke.Thickness = 1.5
		popupStroke.Parent = popup

		local popupTitleBar = Instance.new("Frame")
		popupTitleBar.Size = UDim2.new(1, 0, 0, 34)
		popupTitleBar.BackgroundTransparency = 1
		popupTitleBar.ZIndex = 5
		popupTitleBar.Parent = popup

		local popupTitleLabel = Instance.new("TextLabel")
		popupTitleLabel.Size = UDim2.new(1, -40, 1, 0)
		popupTitleLabel.Position = UDim2.new(0, 10, 0, 0)
		popupTitleLabel.BackgroundTransparency = 1
		popupTitleLabel.Text = popupTitle
		popupTitleLabel.TextColor3 = theme.textPrimary
		popupTitleLabel.TextScaled = true
		popupTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
		popupTitleLabel.Font = Enum.Font.GothamBold
		popupTitleLabel.ZIndex = 5
		popupTitleLabel.Parent = popupTitleBar

		local closeButton = Instance.new("TextButton")
		closeButton.Size = UDim2.new(0, 22, 0, 22)
		closeButton.Position = UDim2.new(1, -30, 0, 6)
		closeButton.BackgroundColor3 = theme.bgSurface2
		closeButton.Text = "X"
		closeButton.TextColor3 = theme.textPrimary
		closeButton.TextScaled = true
		closeButton.Font = Enum.Font.GothamBold
		closeButton.AutoButtonColor = false
		closeButton.ZIndex = 5
		closeButton.Parent = popupTitleBar

		local closeCorner = Instance.new("UICorner")
		closeCorner.CornerRadius = UDim.new(0, 6)
		closeCorner.Parent = closeButton

		closeButton.MouseEnter:Connect(function()
			TweenService:Create(closeButton, TweenInfo.new(0.15), {BackgroundColor3 = theme.danger}):Play()
		end)
		closeButton.MouseLeave:Connect(function()
			TweenService:Create(closeButton, TweenInfo.new(0.15), {BackgroundColor3 = theme.bgSurface2}):Play()
		end)
		closeButton.MouseButton1Click:Connect(function()
			popup.Visible = false
		end)

		local popupDivider = Instance.new("Frame")
		popupDivider.Size = UDim2.new(1, -20, 0, 1)
		popupDivider.Position = UDim2.new(0, 10, 0, 34)
		popupDivider.BackgroundColor3 = theme.border
		popupDivider.BorderSizePixel = 0
		popupDivider.ZIndex = 5
		popupDivider.Parent = popup

		local popupContent = Instance.new("Frame")
		popupContent.Size = UDim2.new(1, -20, 1, -44)
		popupContent.Position = UDim2.new(0, 10, 0, 40)
		popupContent.BackgroundTransparency = 1
		popupContent.ZIndex = 5
		popupContent.Parent = popup

		local popupLayout = Instance.new("UIListLayout")
		popupLayout.Padding = UDim.new(0, 8)
		popupLayout.Parent = popupContent

		for i, rowData in ipairs(rows) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 36)
			row.LayoutOrder = i
			row.BackgroundTransparency = 1
			row.ZIndex = 5
			row.Parent = popupContent

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(0.55, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.Text = rowData.label
			label.TextColor3 = theme.textMuted
			label.TextScaled = true
			label.Font = Enum.Font.Gotham
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.ZIndex = 5
			label.Parent = row

			local box = Instance.new("TextBox")
			box.Size = UDim2.new(0.45, -5, 1, -6)
			box.Position = UDim2.new(0.55, 5, 0, 3)
			box.BackgroundColor3 = theme.bgSurface2
			box.Text = tostring(rowData.default)
			box.TextColor3 = theme.textPrimary
			box.TextScaled = true
			box.Font = Enum.Font.Gotham
			box.ClearTextOnFocus = false
			box.ZIndex = 5
			box.Parent = row

			local boxCorner = Instance.new("UICorner")
			boxCorner.CornerRadius = UDim.new(0, 6)
			boxCorner.Parent = box

			local boxStroke = Instance.new("UIStroke")
			boxStroke.Color = theme.border
			boxStroke.Thickness = 1
			boxStroke.Parent = box

			box.Focused:Connect(function()
				TweenService:Create(boxStroke, TweenInfo.new(0.15), {Color = theme.borderHover}):Play()
			end)

			box.FocusLost:Connect(function()
				TweenService:Create(boxStroke, TweenInfo.new(0.15), {Color = theme.border}):Play()
				local num = tonumber(box.Text)
				if num then
					num = math.clamp(num, rowData.min or 0, rowData.max or 10000)
					box.Text = tostring(num)
					rowData.callback(num)
				else
					box.Text = tostring(rowData.default)
				end
			end)
		end

		makeDraggable(popupTitleBar, popup)

		return popup
	end

	-- Settings Popups
	flyPopup = createSettingsPopup("Fly Settings", {
		{
			label = "Fly Speed",
			default = settings.flySpeed,
			min = 1, max = 500,
			callback = function(val)
				settings.flySpeed = val
			end
		}
	})

	speedPopup = createSettingsPopup("Speed Settings", {
		{
			label = "Multiplier",
			default = settings.speedMultiplier,
			min = 1, max = 100,
			callback = function(val)
				settings.speedMultiplier = val
				if speedBoostEnabled then
					local character = player.Character
					if character then
						local humanoid = character:FindFirstChildOfClass("Humanoid")
						if humanoid then
							humanoid.WalkSpeed = originalWalkSpeed * settings.speedMultiplier
						end
					end
				end
			end
		}
	})

	followPopup = createSettingsPopup("Follow Settings", {
		{
			label = "Distance",
			default = settings.followDistance,
			min = 1, max = 50,
			callback = function(val)
				settings.followDistance = val
			end
		}
	})

	highlightPopup = createSettingsPopup("Highlight Settings", {
		{
			label = "Fill R",
			default = math.floor(settings.highlightColor.R * 255),
			min = 0, max = 255,
			callback = function(val)
				settings.highlightColor = Color3.fromRGB(val, settings.highlightColor.G * 255, settings.highlightColor.B * 255)
				if highlightEnabled then refreshAllHighlights() end
			end
		},
		{
			label = "Fill G",
			default = math.floor(settings.highlightColor.G * 255),
			min = 0, max = 255,
			callback = function(val)
				settings.highlightColor = Color3.fromRGB(settings.highlightColor.R * 255, val, settings.highlightColor.B * 255)
				if highlightEnabled then refreshAllHighlights() end
			end
		},
		{
			label = "Fill B",
			default = math.floor(settings.highlightColor.B * 255),
			min = 0, max = 255,
			callback = function(val)
				settings.highlightColor = Color3.fromRGB(settings.highlightColor.R * 255, settings.highlightColor.G * 255, val)
				if highlightEnabled then refreshAllHighlights() end
			end
		},
		{
			label = "Outline R",
			default = math.floor(settings.outlineColor.R * 255),
			min = 0, max = 255,
			callback = function(val)
				settings.outlineColor = Color3.fromRGB(val, settings.outlineColor.G * 255, settings.outlineColor.B * 255)
				if highlightEnabled then refreshAllHighlights() end
			end
		},
		{
			label = "Outline G",
			default = math.floor(settings.outlineColor.G * 255),
			min = 0, max = 255,
			callback = function(val)
				settings.outlineColor = Color3.fromRGB(settings.outlineColor.R * 255, val, settings.outlineColor.B * 255)
				if highlightEnabled then refreshAllHighlights() end
			end
		},
		{
			label = "Outline B",
			default = math.floor(settings.outlineColor.B * 255),
			min = 0, max = 255,
			callback = function(val)
				settings.outlineColor = Color3.fromRGB(settings.outlineColor.R * 255, settings.outlineColor.G * 255, val)
				if highlightEnabled then refreshAllHighlights() end
			end
		}
	})

	function openSettingsPopup(popup, button)
		local absPos = mainFrame.AbsolutePosition
		popup.Position = UDim2.new(0, absPos.X + 410, 0, absPos.Y + button.AbsolutePosition.Y - mainFrame.AbsolutePosition.Y + 50)

		highlightPopup.Visible = false
		flyPopup.Visible = false
		speedPopup.Visible = false
		followPopup.Visible = false

		popup.Visible = true
	end
end

----------------------------------------------------------------
-- BOOT
----------------------------------------------------------------
local function tryAutoLogin()
	if not (keySystem.saveKeyLocally and isfile and readfile) then return false end

	local ok, exists = pcall(isfile, keySystem.saveFile)
	if not ok or not exists then return false end

	local ok2, saved = pcall(readfile, keySystem.saveFile)
	if not ok2 or not saved or saved == "" then return false end

	return (verifyKey(saved))
end

task.spawn(function()
	if tryAutoLogin() then
		buildMainClient()
	else
		buildKeyGui()
	end
end)
