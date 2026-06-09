--[[
  ============================================================
  Lychee AI Plugin v4.3
  Heartbeat for plugin connection status
  ============================================================
]]

local API_BASE_URL = "https://lime-ai-tmy2.onrender.com/api/v1"
local PLUGIN_VERSION = "4.3.0"
local POLL_INTERVAL = 3

local HttpService         = game:GetService("HttpService")
local Selection           = game:GetService("Selection")
local ScriptEditorService = game:GetService("ScriptEditorService")
local TweenService        = game:GetService("TweenService")
local RunService          = game:GetService("RunService")

local state = {
	accessToken  = nil,
	refreshToken = nil,
	connected    = false,
	jobCount     = 0,
}

local jobPollingActive = false

local LYCHEE      = Color3.fromRGB(232, 84, 122)
local LYCHEE_GLOW = Color3.fromRGB(200, 60, 100)
local LYCHEE_MID  = Color3.fromRGB(160, 40, 80)
local BG          = Color3.fromRGB(28, 28, 28)
local SURFACE     = Color3.fromRGB(36, 36, 36)
local SURFACE2    = Color3.fromRGB(44, 44, 44)
local BORDER      = Color3.fromRGB(55, 55, 55)
local TEXT        = Color3.fromRGB(230, 230, 230)
local TEXT_DIM    = Color3.fromRGB(150, 150, 150)
local TEXT_FAINT  = Color3.fromRGB(90, 90, 90)
local RED         = Color3.fromRGB(220, 60, 60)
local RED_DOT     = Color3.fromRGB(220, 60, 60)
local GREEN_DOT   = Color3.fromRGB(80, 220, 80)
local BTN_GREY    = Color3.fromRGB(60, 60, 60)

local toolbar   = plugin:CreateToolbar("Lychee AI")
local toggleBtn = toolbar:CreateButton("Lychee AI", "Open Lychee AI", "rbxassetid://6031068426")

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, true, false, 340, 220, 280, 180)
local widget = plugin:CreateDockWidgetPluginGui("LycheeAI_v4", widgetInfo)
widget.Title = "Lychee AI"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

toggleBtn.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	toggleBtn:SetActive(widget.Enabled)
end)

local function corner(p, r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 6); c.Parent=p; return c end
local function stroke(p, col, t) local s=Instance.new("UIStroke"); s.Color=col or BORDER; s.Thickness=t or 1; s.Parent=p; return s end
local function pad(p, a) local u=Instance.new("UIPadding"); u.PaddingLeft=UDim.new(0,a); u.PaddingRight=UDim.new(0,a); u.PaddingTop=UDim.new(0,a); u.PaddingBottom=UDim.new(0,a); u.Parent=p; return u end

local function lbl(parent, txt, size, col, font, xa)
	local l = Instance.new("TextLabel")
	l.Size = size or UDim2.new(1,0,0,20)
	l.BackgroundTransparency = 1
	l.Text = txt or ""
	l.TextColor3 = col or TEXT
	l.Font = font or Enum.Font.Gotham
	l.TextSize = 13
	l.TextXAlignment = xa or Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Parent = parent
	return l
end

local function btn(parent, txt, bg, tc, size)
	local b = Instance.new("TextButton")
	b.Size = size or UDim2.new(0, 90, 0, 28)
	b.BackgroundColor3 = bg or BTN_GREY
	b.Text = txt or "Button"
	b.TextColor3 = tc or TEXT
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Parent = parent
	corner(b, 6)
	b.MouseEnter:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3=bg:Lerp(Color3.new(1,1,1), 0.12)}):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3=bg}):Play()
	end)
	return b
end

-- Lychee logo made from Roblox UI parts
local function makeLycheeLogo(parent, size)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, size, 0, size)
	frame.BackgroundTransparency = 1
	frame.Parent = parent

	local body = Instance.new("Frame")
	body.Size = UDim2.new(0, size, 0, size)
	body.Position = UDim2.new(0, 0, 0, 0)
	body.BackgroundColor3 = LYCHEE
	body.BorderSizePixel = 0
	body.Parent = frame
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0.5, 0)
	bc.Parent = body

	local bumpSize = math.max(3, math.floor(size * 0.12))
	local bumps = {
		{0.25, 0.22}, {0.5, 0.16}, {0.75, 0.22},
		{0.15, 0.5},  {0.85, 0.5},
		{0.25, 0.75}, {0.5, 0.82}, {0.75, 0.75},
		{0.5, 0.5},
	}
	for _, b2 in ipairs(bumps) do
		local bump = Instance.new("Frame")
		bump.Size = UDim2.new(0, bumpSize, 0, bumpSize)
		bump.Position = UDim2.new(0, math.floor(b2[1]*size - bumpSize/2), 0, math.floor(b2[2]*size - bumpSize/2))
		bump.BackgroundColor3 = Color3.fromRGB(180, 50, 90)
		bump.BackgroundTransparency = 0.3
		bump.BorderSizePixel = 0
		bump.Parent = frame
		local bc2 = Instance.new("UICorner"); bc2.CornerRadius = UDim.new(0.5,0); bc2.Parent = bump
	end

	local shine = Instance.new("Frame")
	shine.Size = UDim2.new(0, math.floor(size*0.32), 0, math.floor(size*0.22))
	shine.Position = UDim2.new(0, math.floor(size*0.15), 0, math.floor(size*0.14))
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.5
	shine.BorderSizePixel = 0
	shine.Parent = frame
	local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0.5, 0); sc.Parent = shine

	local stem = Instance.new("Frame")
	stem.Size = UDim2.new(0, 3, 0, math.floor(size*0.22))
	stem.Position = UDim2.new(0, math.floor(size*0.6), 0, -math.floor(size*0.15))
	stem.BackgroundColor3 = Color3.fromRGB(80, 50, 20)
	stem.BorderSizePixel = 0
	stem.Rotation = -20
	stem.Parent = frame
	local stc = Instance.new("UICorner"); stc.CornerRadius = UDim.new(0.5, 0); stc.Parent = stem

	local leaf = Instance.new("Frame")
	leaf.Size = UDim2.new(0, math.floor(size*0.32), 0, math.floor(size*0.14))
	leaf.Position = UDim2.new(0, math.floor(size*0.6), 0, -math.floor(size*0.18))
	leaf.BackgroundColor3 = Color3.fromRGB(40, 130, 30)
	leaf.BorderSizePixel = 0
	leaf.Rotation = -35
	leaf.Parent = frame
	local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(0.5, 0); lc.Parent = leaf

	return frame
end

local function makeRequest(method, endpoint, body, useAuth)
	local headers = { ["Content-Type"] = "application/json" }
	if useAuth and state.accessToken then
		headers["Authorization"] = "Bearer " .. state.accessToken
	end
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = API_BASE_URL .. endpoint, Method = method,
			Headers = headers, Body = body and HttpService:JSONEncode(body) or nil,
		})
	end)
	if not ok then return nil, tostring(response) end
	local decoded; pcall(function() decoded = HttpService:JSONDecode(response.Body) end)
	if not decoded then decoded = { error = response.Body } end
	return decoded, response.StatusCode >= 400 and (decoded.error or "Error") or nil
end

local function apiCall(method, endpoint, body)
	local result, err = makeRequest(method, endpoint, body, true)
	if err and tostring(err):find("401") then
		local r = makeRequest("POST", "/auth/refresh", { refreshToken = state.refreshToken }, false)
		if r and r.accessToken then
			state.accessToken = r.accessToken
			state.refreshToken = r.refreshToken
			plugin:SetSetting("refreshToken", r.refreshToken)
			result, err = makeRequest(method, endpoint, body, true)
		end
	end
	return result, err
end

local function insertCode(code, scriptType, location)
	local starterPlayer = game:GetService("StarterPlayer")
	local services = {
		ServerScriptService     = game:GetService("ServerScriptService"),
		ReplicatedStorage       = game:GetService("ReplicatedStorage"),
		Workspace               = game:GetService("Workspace"),
		StarterGui              = game:GetService("StarterGui"),
		StarterPack             = game:GetService("StarterPack"),
		Lighting                = game:GetService("Lighting"),
		ReplicatedFirst         = game:GetService("ReplicatedFirst"),
		ServerStorage           = game:GetService("ServerStorage"),
		StartPlayerScripts      = starterPlayer:FindFirstChild("StarterPlayerScripts"),
		StarterCharacterScripts = starterPlayer:FindFirstChild("StarterCharacterScripts"),
	}
	local parent = services[location] or game:GetService("ServerScriptService")
	local s
	if scriptType == "LocalScript" then s = Instance.new("LocalScript")
	elseif scriptType == "ModuleScript" then s = Instance.new("ModuleScript")
	else s = Instance.new("Script") end
	s.Source = code
	s.Name = "LycheeAI_Script"
	s.Parent = parent
	Selection:Set({s})
	pcall(function() ScriptEditorService:OpenScriptDocumentAsync(s) end)
	return s
end

local ui = {}

local function processJob(job)
	if not job.code or job.code == "" then return end

	local updated = false
	if job.scriptName then
		for _, obj in ipairs(game:GetDescendants()) do
			if (obj:IsA("Script") or obj:IsA("LocalScript") or obj:IsA("ModuleScript")) and obj.Name == job.scriptName then
				obj.Source = job.code
				Selection:Set({obj})
				pcall(function() ScriptEditorService:OpenScriptDocumentAsync(obj) end)
				updated = true
				print("[Lychee AI] Updated: " .. obj.Name)
				break
			end
		end
	end

	if not updated then
		local s = insertCode(job.code, job.scriptType, job.insertLocation)
		s.Name = job.scriptName or "LycheeAI_Script"
		print("[Lychee AI] Inserted: " .. s.Name .. " -> " .. (job.insertLocation or "ServerScriptService"))
	end

	state.jobCount = state.jobCount + 1
	task.spawn(function() apiCall("POST", "/jobs/" .. job.id .. "/inserted", {}) end)

	if ui.promptsVal then
		ui.promptsVal.Text = tostring(state.jobCount)
	end
	if ui.statusLbl then
		ui.statusLbl.Text = "Done: " .. (job.scriptName or "script") .. " ready!"
		ui.statusLbl.TextColor3 = LYCHEE
		task.delay(4, function()
			if ui.statusLbl then
				ui.statusLbl.Text = "Watching for jobs..."
				ui.statusLbl.TextColor3 = TEXT_FAINT
			end
		end)
	end
end

-- ── HEARTBEAT — tells website the plugin is connected ──
local function sendHeartbeat()
	if not state.accessToken or not state.connected then return end
	pcall(function()
		apiCall("POST", "/plugin/heartbeat", {})
	end)
end

local function pollForJobs()
	if not state.accessToken or not state.connected then return end
	-- Send heartbeat with every poll
	task.spawn(sendHeartbeat)
	local result = apiCall("GET", "/jobs/pending", nil)
	if not result or not result.jobs then return end
	for _, job in ipairs(result.jobs) do
		task.spawn(processJob, job)
	end
end

local function startPolling()
	if jobPollingActive then return end
	jobPollingActive = true
	task.spawn(function()
		while jobPollingActive do
			pcall(pollForJobs)
			task.wait(POLL_INTERVAL)
		end
	end)
end

local function stopPolling()
	jobPollingActive = false
end

local function buildConnectedUI()
	for _, c in ipairs(widget:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end

	local root = Instance.new("Frame")
	root.Size = UDim2.new(1,0,1,0)
	root.BackgroundColor3 = BG
	root.BorderSizePixel = 0
	root.Parent = widget

	local topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1,0,0,44)
	topBar.BackgroundColor3 = SURFACE
	topBar.BorderSizePixel = 0
	topBar.Parent = root
	stroke(topBar, BORDER)

	local logo = makeLycheeLogo(topBar, 28)
	logo.Position = UDim2.new(0, 10, 0.5, -14)

	local ver = lbl(topBar, "v" .. PLUGIN_VERSION, UDim2.new(0, 60, 1, 0), TEXT_FAINT, Enum.Font.Code, Enum.TextXAlignment.Left)
	ver.Position = UDim2.new(0, 46, 0, 0)
	ver.TextSize = 10

	local disconnectBtn = btn(topBar, "Disconnect", BTN_GREY, TEXT, UDim2.new(0, 100, 0, 26))
	disconnectBtn.Position = UDim2.new(1, -206, 0.5, -13)

	local statusBtn = Instance.new("Frame")
	statusBtn.Size = UDim2.new(0, 80, 0, 26)
	statusBtn.Position = UDim2.new(1, -100, 0.5, -13)
	statusBtn.BackgroundColor3 = BTN_GREY
	statusBtn.BorderSizePixel = 0
	statusBtn.Parent = topBar
	corner(statusBtn, 6)
	stroke(statusBtn, BORDER)

	local statusDot = Instance.new("Frame")
	statusDot.Size = UDim2.new(0, 8, 0, 8)
	statusDot.Position = UDim2.new(0, 10, 0.5, -4)
	statusDot.BackgroundColor3 = GREEN_DOT
	statusDot.BorderSizePixel = 0
	statusDot.Parent = statusBtn
	local sdc = Instance.new("UICorner"); sdc.CornerRadius = UDim.new(0.5,0); sdc.Parent = statusDot

	task.spawn(function()
		while state.connected do
			TweenService:Create(statusDot, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {BackgroundTransparency=0.4}):Play()
			task.wait(1.6)
		end
	end)

	local statusTxt = lbl(statusBtn, "Status", UDim2.new(1,-24,1,0), TEXT, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
	statusTxt.Position = UDim2.new(0, 24, 0, 0)
	statusTxt.TextSize = 11

	local infoPanel = Instance.new("Frame")
	infoPanel.Size = UDim2.new(1,-20,0,62)
	infoPanel.Position = UDim2.new(0,10,0,54)
	infoPanel.BackgroundColor3 = SURFACE
	infoPanel.BorderSizePixel = 0
	infoPanel.Parent = root
	corner(infoPanel, 8)
	stroke(infoPanel, BORDER)
	pad(infoPanel, 12)

	local leftCol = Instance.new("Frame")
	leftCol.Size = UDim2.new(0.5,-10,1,0)
	leftCol.BackgroundTransparency = 1
	leftCol.Parent = infoPanel

	local projectLbl = lbl(leftCol, "Project:", UDim2.new(1,0,0,18), TEXT_DIM, Enum.Font.Gotham)
	projectLbl.TextSize = 12

	local projectVal = lbl(leftCol, game.Name or "Untitled", UDim2.new(1,0,0,20), TEXT, Enum.Font.GothamBold)
	projectVal.Position = UDim2.new(0,0,0,18)
	projectVal.TextSize = 13

	local promptsLbl = lbl(leftCol, "Prompts:", UDim2.new(1,0,0,18), TEXT_DIM, Enum.Font.Gotham)
	promptsLbl.Position = UDim2.new(0,0,0,40)
	promptsLbl.TextSize = 12

	local promptsVal = lbl(leftCol, "0", UDim2.new(0,40,0,18), TEXT, Enum.Font.GothamBold)
	promptsVal.Position = UDim2.new(0,60,0,40)
	promptsVal.TextSize = 13
	ui.promptsVal = promptsVal

	local rightLbl = lbl(infoPanel, "Send a web\nmessage...", UDim2.new(0.5,-10,1,0), TEXT_DIM, Enum.Font.Gotham, Enum.TextXAlignment.Right)
	rightLbl.Position = UDim2.new(0.5,0,0,0)
	rightLbl.TextSize = 12

	-- Expand infoPanel to fit status label inside it
	infoPanel.Size = UDim2.new(1,-20,0,82)

	local statusLbl = lbl(infoPanel, "Watching for jobs...", UDim2.new(1,-24,0,14), TEXT_FAINT, Enum.Font.Gotham, Enum.TextXAlignment.Left)
	statusLbl.Position = UDim2.new(0,0,1,-18)
	statusLbl.TextSize = 10
	ui.statusLbl = statusLbl

	local logsBtn = btn(root, "Logs Off", BTN_GREY, TEXT_DIM, UDim2.new(0, 80, 0, 24))
	logsBtn.Position = UDim2.new(1,-90,1,-34)
	logsBtn.TextSize = 11

	disconnectBtn.MouseButton1Click:Connect(function()
		state.connected = false
		state.accessToken = nil
		plugin:SetSetting("refreshToken", "")
		stopPolling()
		buildDisconnectedUI()
	end)

	startPolling()
end

local function buildConnectingUI(email, password)
	for _, c in ipairs(widget:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end

	local root = Instance.new("Frame")
	root.Size = UDim2.new(1,0,1,0)
	root.BackgroundColor3 = BG
	root.BorderSizePixel = 0
	root.Parent = widget

	local topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1,0,0,44)
	topBar.BackgroundColor3 = SURFACE
	topBar.BorderSizePixel = 0
	topBar.Parent = root
	stroke(topBar, BORDER)

	local logo = makeLycheeLogo(topBar, 28)
	logo.Position = UDim2.new(0, 10, 0.5, -14)

	local ver = lbl(topBar, "v" .. PLUGIN_VERSION, UDim2.new(0, 60, 1, 0), TEXT_FAINT, Enum.Font.Code)
	ver.Position = UDim2.new(0, 46, 0, 0)
	ver.TextSize = 10

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(1,-20,0,80)
	panel.Position = UDim2.new(0,10,0,54)
	panel.BackgroundColor3 = SURFACE
	panel.BorderSizePixel = 0
	panel.Parent = root
	corner(panel, 8)
	stroke(panel, BORDER)

	local spinLogo = makeLycheeLogo(panel, 36)
	spinLogo.Position = UDim2.new(0.5,-18,0,10)

	local angle = 0
	local spinConn = RunService.Heartbeat:Connect(function(dt)
		angle = angle + dt * 120
		spinLogo.Rotation = angle
	end)

	local connectingTxt = lbl(panel, "Connecting to your project...", UDim2.new(1,0,0,20), TEXT_DIM, Enum.Font.Gotham, Enum.TextXAlignment.Center)
	connectingTxt.Position = UDim2.new(0,0,0,52)
	connectingTxt.TextSize = 13

	task.spawn(function()
		local result, err

		if email and password then
			result, err = makeRequest("POST", "/auth/login", { email = email, password = password }, false)
		else
			local saved = plugin:GetSetting("refreshToken")
			if saved and saved ~= "" then
				result = makeRequest("POST", "/auth/refresh", { refreshToken = saved }, false)
				if result and result.accessToken then
					err = nil
				else
					result = nil
					err = "Session expired"
				end
			else
				result = nil
				err = "No saved session"
			end
		end

		spinConn:Disconnect()

		if result and result.accessToken then
			state.accessToken = result.accessToken
			state.refreshToken = result.refreshToken
			state.connected = true
			plugin:SetSetting("refreshToken", result.refreshToken)
			buildConnectedUI()
		else
			buildDisconnectedUI(err or "Connection failed")
		end
	end)
end

function buildDisconnectedUI(errorMsg)
	for _, c in ipairs(widget:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end

	local root = Instance.new("Frame")
	root.Size = UDim2.new(1,0,1,0)
	root.BackgroundColor3 = BG
	root.BorderSizePixel = 0
	root.Parent = widget

	local topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1,0,0,44)
	topBar.BackgroundColor3 = SURFACE
	topBar.BorderSizePixel = 0
	topBar.Parent = root
	stroke(topBar, BORDER)

	local logo = makeLycheeLogo(topBar, 28)
	logo.Position = UDim2.new(0, 10, 0.5, -14)

	local ver = lbl(topBar, "v" .. PLUGIN_VERSION, UDim2.new(0, 60, 1, 0), TEXT_FAINT, Enum.Font.Code)
	ver.Position = UDim2.new(0, 46, 0, 0)
	ver.TextSize = 10

	local connectBtn = btn(topBar, "Connect", LYCHEE_GLOW, Color3.fromRGB(40, 10, 20), UDim2.new(0, 90, 0, 28))
	connectBtn.Position = UDim2.new(1, -196, 0.5, -14)
	connectBtn.Font = Enum.Font.GothamBold

	local statusBtn = Instance.new("Frame")
	statusBtn.Size = UDim2.new(0, 80, 0, 26)
	statusBtn.Position = UDim2.new(1, -100, 0.5, -13)
	statusBtn.BackgroundColor3 = BTN_GREY
	statusBtn.BorderSizePixel = 0
	statusBtn.Parent = topBar
	corner(statusBtn, 6)
	stroke(statusBtn, BORDER)

	local statusDot = Instance.new("Frame")
	statusDot.Size = UDim2.new(0, 8, 0, 8)
	statusDot.Position = UDim2.new(0, 10, 0.5, -4)
	statusDot.BackgroundColor3 = RED_DOT
	statusDot.BorderSizePixel = 0
	statusDot.Parent = statusBtn
	local sdc = Instance.new("UICorner"); sdc.CornerRadius = UDim.new(0.5,0); sdc.Parent = statusDot

	local statusTxt = lbl(statusBtn, "Status", UDim2.new(1,-24,1,0), TEXT, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
	statusTxt.Position = UDim2.new(0, 24, 0, 0)
	statusTxt.TextSize = 11

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(1,-20,0,0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Position = UDim2.new(0,10,0,54)
	panel.BackgroundColor3 = SURFACE
	panel.BorderSizePixel = 0
	panel.Parent = root
	corner(panel, 8)
	stroke(panel, BORDER)
	pad(panel, 12)

	local panelList = Instance.new("UIListLayout")
	panelList.FillDirection = Enum.FillDirection.Vertical
	panelList.SortOrder = Enum.SortOrder.LayoutOrder
	panelList.Padding = UDim.new(0, 8)
	panelList.Parent = panel

	local hint = lbl(panel, "Sign in to connect Lychee AI to your Studio", UDim2.new(1,0,0,16), TEXT_DIM, Enum.Font.Gotham, Enum.TextXAlignment.Center)
	hint.TextSize = 12
	hint.LayoutOrder = 1

	local emailWrap = Instance.new("Frame")
	emailWrap.Size = UDim2.new(1,0,0,30)
	emailWrap.BackgroundColor3 = SURFACE2
	emailWrap.BorderSizePixel = 0
	emailWrap.LayoutOrder = 2
	emailWrap.Parent = panel
	corner(emailWrap, 6)
	stroke(emailWrap, BORDER)

	local emailBox = Instance.new("TextBox")
	emailBox.Size = UDim2.new(1,-16,1,0)
	emailBox.Position = UDim2.new(0,8,0,0)
	emailBox.BackgroundTransparency = 1
	emailBox.Text = ""
	emailBox.TextColor3 = TEXT
	emailBox.PlaceholderText = "Email"
	emailBox.PlaceholderColor3 = TEXT_FAINT
	emailBox.Font = Enum.Font.Gotham
	emailBox.TextSize = 13
	emailBox.ClearTextOnFocus = false
	emailBox.BorderSizePixel = 0
	emailBox.TextXAlignment = Enum.TextXAlignment.Left
	emailBox.Parent = emailWrap
	emailBox.Focused:Connect(function() stroke(emailWrap, LYCHEE_MID) end)
	emailBox.FocusLost:Connect(function() stroke(emailWrap, BORDER) end)

	local passWrap = Instance.new("Frame")
	passWrap.Size = UDim2.new(1,0,0,30)
	passWrap.BackgroundColor3 = SURFACE2
	passWrap.BorderSizePixel = 0
	passWrap.LayoutOrder = 3
	passWrap.Parent = panel
	corner(passWrap, 6)
	stroke(passWrap, BORDER)

	local passBox = Instance.new("TextBox")
	passBox.Size = UDim2.new(1,-16,1,0)
	passBox.Position = UDim2.new(0,8,0,0)
	passBox.BackgroundTransparency = 1
	passBox.Text = ""
	passBox.TextColor3 = TEXT
	passBox.PlaceholderText = "Password"
	passBox.PlaceholderColor3 = TEXT_FAINT
	passBox.Font = Enum.Font.Gotham
	passBox.TextSize = 13
	passBox.ClearTextOnFocus = false
	passBox.BorderSizePixel = 0
	passBox.TextXAlignment = Enum.TextXAlignment.Left
	passBox.Parent = passWrap
	passBox.Focused:Connect(function() stroke(passWrap, LYCHEE_MID) end)
	passBox.FocusLost:Connect(function() stroke(passWrap, BORDER) end)

	if errorMsg then
		local errLbl = lbl(panel, "✗ " .. errorMsg, UDim2.new(1,0,0,14), RED, Enum.Font.Gotham, Enum.TextXAlignment.Center)
		errLbl.TextSize = 11
		errLbl.LayoutOrder = 4
	end

	local signupLbl = lbl(panel, "Sign up on our website to get started", UDim2.new(1,0,0,14), TEXT_FAINT, Enum.Font.Gotham, Enum.TextXAlignment.Center)
	signupLbl.TextSize = 10
	signupLbl.LayoutOrder = 5

	local logsBtn = btn(root, "Logs Off", BTN_GREY, TEXT_DIM, UDim2.new(0, 80, 0, 24))
	logsBtn.Position = UDim2.new(1,-90,1,-34)
	logsBtn.TextSize = 11

	local function doConnect()
		local email = emailBox.Text:gsub("%s","")
		local pass = passBox.Text
		if email == "" or pass == "" then
			buildDisconnectedUI("Please enter email and password")
			return
		end
		buildConnectingUI(email, pass)
	end

	connectBtn.MouseButton1Click:Connect(doConnect)
	passBox.FocusLost:Connect(function(enter) if enter then doConnect() end end)
end

local function init()
	local saved = plugin:GetSetting("refreshToken")
	if saved and saved ~= "" then
		buildConnectingUI(nil, nil)
	else
		buildDisconnectedUI()
	end
end

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	if widget.Enabled and #widget:GetChildren() == 0 then init() end
end)

init()

print("[Lychee AI] v" .. PLUGIN_VERSION .. " ready!")
