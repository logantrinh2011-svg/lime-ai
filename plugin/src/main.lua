--[[
  ============================================================
  Lime AI Plugin — Complete Roblox Studio Plugin
  Powered by Claude (Anthropic) via secure backend
  
  SETUP:
  1. Deploy the backend to your server
  2. Set API_BASE_URL below to your backend URL
  3. Install this plugin in Roblox Studio
  ============================================================
]]

-- ─────────────────────────────────────────────
-- CONFIGURATION
-- ─────────────────────────────────────────────
local API_BASE_URL = "https://api.limeai.dev/api/v1"
local PLUGIN_VERSION = "1.0.0"
local MAX_POLL_INTERVAL = 0.05  -- 50ms polling for streamed responses

-- ─────────────────────────────────────────────
-- SERVICES
-- ─────────────────────────────────────────────
local HttpService     = game:GetService("HttpService")
local Selection       = game:GetService("Selection")
local StudioService   = game:GetService("StudioService")
local RunService      = game:GetService("RunService")
local ScriptEditorService = game:GetService("ScriptEditorService")

-- ─────────────────────────────────────────────
-- PLUGIN STATE
-- ─────────────────────────────────────────────
local pluginState = {
  accessToken = nil,
  refreshToken = nil,
  conversationId = nil,
  isStreaming = false,
  currentTheme = settings().Studio.Theme.Name,
}

-- ─────────────────────────────────────────────
-- HTTP HELPERS
-- ─────────────────────────────────────────────
local function makeRequest(method, endpoint, body, useAuth)
  local headers = {
    ["Content-Type"] = "application/json",
  }
  if useAuth and pluginState.accessToken then
    headers["Authorization"] = "Bearer " .. pluginState.accessToken
  end

  local success, response = pcall(function()
    return HttpService:RequestAsync({
      Url = API_BASE_URL .. endpoint,
      Method = method,
      Headers = headers,
      Body = body and HttpService:JSONEncode(body) or nil,
    })
  end)

  if not success then
    return nil, "Network error: " .. tostring(response)
  end

  local decoded
  local decodeSuccess = pcall(function()
    decoded = HttpService:JSONDecode(response.Body)
  end)

  if not decodeSuccess then
    decoded = { error = response.Body }
  end

  return decoded, response.StatusCode >= 400 and (decoded.error or "Request failed") or nil
end

-- Refresh access token using refresh token
local function refreshAccessToken()
  if not pluginState.refreshToken then return false end
  local result, err = makeRequest("POST", "/auth/refresh", {
    refreshToken = pluginState.refreshToken
  }, false)
  if result and result.accessToken then
    pluginState.accessToken = result.accessToken
    pluginState.refreshToken = result.refreshToken
    plugin:SetSetting("refreshToken", result.refreshToken)
    return true
  end
  return false
end

-- Auto-retry with token refresh on 401
local function apiCall(method, endpoint, body)
  local result, err = makeRequest(method, endpoint, body, true)
  if err and tostring(err):find("401") then
    if refreshAccessToken() then
      result, err = makeRequest(method, endpoint, body, true)
    end
  end
  return result, err
end

-- ─────────────────────────────────────────────
-- PLUGIN TOOLBAR & WIDGET
-- ─────────────────────────────────────────────
local toolbar = plugin:CreateToolbar("Lime AI")

local toggleButton = toolbar:CreateButton(
  "Lime AI",
  "Open Lime AI — Claude-powered coding assistant",
  "rbxassetid://18677679841"  -- replace with your icon asset id
)

local widgetInfo = DockWidgetPluginGuiInfo.new(
  Enum.InitialDockState.Right,
  true,   -- enabled by default
  false,  -- don't override previous state
  380,    -- default width
  600,    -- default height
  280,    -- min width
  400     -- min height
)

local widget = plugin:CreateDockWidgetPluginGui("Lime AI", widgetInfo)
widget.Title = "Lime AI"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

toggleButton.Click:Connect(function()
  widget.Enabled = not widget.Enabled
  toggleButton:SetActive(widget.Enabled)
end)

-- ─────────────────────────────────────────────
-- THEME COLORS
-- ─────────────────────────────────────────────
local function getTheme()
  local theme = settings().Studio.Theme
  return {
    background   = theme:GetColor(Enum.StudioStyleGuideColor.MainBackground),
    surface      = theme:GetColor(Enum.StudioStyleGuideColor.InputFieldBackground),
    border       = theme:GetColor(Enum.StudioStyleGuideColor.Border),
    text         = theme:GetColor(Enum.StudioStyleGuideColor.MainText),
    textDim      = theme:GetColor(Enum.StudioStyleGuideColor.DimmedText),
    accent       = Color3.fromRGB(134, 239, 94),  -- indigo-500
    accentHover  = Color3.fromRGB(110, 210, 70),
    success      = Color3.fromRGB(34, 197, 94),
    error        = Color3.fromRGB(239, 68, 68),
    userBubble   = Color3.fromRGB(45, 90, 30),
    aiBubble     = theme:GetColor(Enum.StudioStyleGuideColor.InputFieldBackground),
    codeBg       = Color3.fromRGB(30, 30, 46),
    codeText     = Color3.fromRGB(205, 214, 244),
  }
end

-- ─────────────────────────────────────────────
-- UI CONSTRUCTION
-- ─────────────────────────────────────────────
local function buildUI()
  -- Clear existing UI
  for _, child in ipairs(widget:GetChildren()) do
    if child:IsA("GuiObject") then child:Destroy() end
  end

  local theme = getTheme()

  -- ── Root Frame ──────────────────────────────
  local root = Instance.new("Frame")
  root.Name = "Root"
  root.Size = UDim2.new(1, 0, 1, 0)
  root.BackgroundColor3 = theme.background
  root.BorderSizePixel = 0
  root.Parent = widget

  local layout = Instance.new("UIListLayout")
  layout.FillDirection = Enum.FillDirection.Vertical
  layout.SortOrder = Enum.SortOrder.LayoutOrder
  layout.Parent = root

  -- ── Header ──────────────────────────────────
  local header = Instance.new("Frame")
  header.Name = "Header"
  header.Size = UDim2.new(1, 0, 0, 44)
  header.BackgroundColor3 = theme.surface
  header.BorderSizePixel = 0
  header.LayoutOrder = 1
  header.Parent = root

  local headerBorder = Instance.new("Frame")
  headerBorder.Size = UDim2.new(1, 0, 0, 1)
  headerBorder.Position = UDim2.new(0, 0, 1, -1)
  headerBorder.BackgroundColor3 = theme.border
  headerBorder.BorderSizePixel = 0
  headerBorder.Parent = header

  local logo = Instance.new("TextLabel")
  logo.Size = UDim2.new(0, 160, 1, 0)
  logo.Position = UDim2.new(0, 12, 0, 0)
  logo.BackgroundTransparency = 1
  logo.Text = "🟢 Lime AI"
  logo.TextColor3 = Color3.fromRGB(134, 239, 94)
  logo.Font = Enum.Font.GothamBold
  logo.TextSize = 15
  logo.TextXAlignment = Enum.TextXAlignment.Left
  logo.Parent = header

  local newChatBtn = Instance.new("TextButton")
  newChatBtn.Name = "NewChatBtn"
  newChatBtn.Size = UDim2.new(0, 80, 0, 28)
  newChatBtn.Position = UDim2.new(1, -92, 0.5, -14)
  newChatBtn.BackgroundColor3 = theme.accent
  newChatBtn.Text = "+ New chat"
  newChatBtn.TextColor3 = Color3.new(1, 1, 1)
  newChatBtn.Font = Enum.Font.Gotham
  newChatBtn.TextSize = 11
  newChatBtn.BorderSizePixel = 0
  newChatBtn.Parent = header
  Instance.new("UICorner").CornerRadius = UDim.new(0, 6)
  local nc = newChatBtn:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
  nc.CornerRadius = UDim.new(0, 6)
  nc.Parent = newChatBtn

  -- ── Tab Bar ─────────────────────────────────
  local tabBar = Instance.new("Frame")
  tabBar.Name = "TabBar"
  tabBar.Size = UDim2.new(1, 0, 0, 36)
  tabBar.BackgroundColor3 = theme.surface
  tabBar.BorderSizePixel = 0
  tabBar.LayoutOrder = 2
  tabBar.Parent = root

  local tabLayout = Instance.new("UIListLayout")
  tabLayout.FillDirection = Enum.FillDirection.Horizontal
  tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
  tabLayout.Padding = UDim.new(0, 0)
  tabLayout.Parent = tabBar

  local tabs = {"Chat", "History", "Profile"}
  local tabButtons = {}

  for i, tabName in ipairs(tabs) do
    local tab = Instance.new("TextButton")
    tab.Name = tabName .. "Tab"
    tab.Size = UDim2.new(0, 1/3, 1, 0)
    tab.AutomaticSize = Enum.AutomaticSize.None
    tab.Size = UDim2.new(0, 126, 1, 0)
    tab.BackgroundColor3 = theme.surface
    tab.BorderSizePixel = 0
    tab.Text = tabName
    tab.TextColor3 = i == 1 and theme.accent or theme.textDim
    tab.Font = Enum.Font.Gotham
    tab.TextSize = 12
    tab.LayoutOrder = i
    tab.Parent = tabBar
    tabButtons[tabName] = tab

    local indicator = Instance.new("Frame")
    indicator.Name = "Indicator"
    indicator.Size = UDim2.new(1, 0, 0, 2)
    indicator.Position = UDim2.new(0, 0, 1, -2)
    indicator.BackgroundColor3 = i == 1 and theme.accent or theme.surface
    indicator.BorderSizePixel = 0
    indicator.Parent = tab
  end

  -- ── Pages Container ──────────────────────────
  local pages = Instance.new("Frame")
  pages.Name = "Pages"
  pages.Size = UDim2.new(1, 0, 1, -116)  -- full remaining height
  pages.BackgroundColor3 = theme.background
  pages.BorderSizePixel = 0
  pages.LayoutOrder = 3
  pages.Parent = root

  -- ══════════════════════════════════════════
  -- CHAT PAGE
  -- ══════════════════════════════════════════
  local chatPage = Instance.new("Frame")
  chatPage.Name = "ChatPage"
  chatPage.Size = UDim2.new(1, 0, 1, 0)
  chatPage.BackgroundTransparency = 1
  chatPage.Visible = true
  chatPage.Parent = pages

  -- Messages scroll frame
  local scrollFrame = Instance.new("ScrollingFrame")
  scrollFrame.Name = "Messages"
  scrollFrame.Size = UDim2.new(1, 0, 1, -52)
  scrollFrame.BackgroundTransparency = 1
  scrollFrame.BorderSizePixel = 0
  scrollFrame.ScrollBarThickness = 4
  scrollFrame.ScrollBarImageColor3 = theme.border
  scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
  scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
  scrollFrame.Parent = chatPage

  local msgLayout = Instance.new("UIListLayout")
  msgLayout.SortOrder = Enum.SortOrder.LayoutOrder
  msgLayout.Padding = UDim.new(0, 8)
  msgLayout.Parent = scrollFrame

  local msgPadding = Instance.new("UIPadding")
  msgPadding.PaddingLeft = UDim.new(0, 10)
  msgPadding.PaddingRight = UDim.new(0, 10)
  msgPadding.PaddingTop = UDim.new(0, 10)
  msgPadding.PaddingBottom = UDim.new(0, 10)
  msgPadding.Parent = scrollFrame

  -- Input area
  local inputArea = Instance.new("Frame")
  inputArea.Name = "InputArea"
  inputArea.Size = UDim2.new(1, 0, 0, 52)
  inputArea.Position = UDim2.new(0, 0, 1, -52)
  inputArea.BackgroundColor3 = theme.surface
  inputArea.BorderSizePixel = 0
  inputArea.Parent = chatPage

  local inputBorder = Instance.new("Frame")
  inputBorder.Size = UDim2.new(1, 0, 0, 1)
  inputBorder.BackgroundColor3 = theme.border
  inputBorder.BorderSizePixel = 0
  inputBorder.Parent = inputArea

  local textBox = Instance.new("TextBox")
  textBox.Name = "InputBox"
  textBox.Size = UDim2.new(1, -52, 1, -12)
  textBox.Position = UDim2.new(0, 8, 0, 6)
  textBox.BackgroundColor3 = theme.background
  textBox.TextColor3 = theme.text
  textBox.PlaceholderText = "Ask Claude anything about Roblox..."
  textBox.PlaceholderColor3 = theme.textDim
  textBox.Font = Enum.Font.Gotham
  textBox.TextSize = 12
  textBox.TextWrapped = true
  textBox.MultiLine = true
  textBox.BorderSizePixel = 0
  textBox.ClearTextOnFocus = false
  textBox.TextXAlignment = Enum.TextXAlignment.Left
  textBox.TextYAlignment = Enum.TextYAlignment.Top
  textBox.Parent = inputArea

  local inputCorner = Instance.new("UICorner")
  inputCorner.CornerRadius = UDim.new(0, 6)
  inputCorner.Parent = textBox

  local sendBtn = Instance.new("TextButton")
  sendBtn.Name = "SendBtn"
  sendBtn.Size = UDim2.new(0, 36, 0, 36)
  sendBtn.Position = UDim2.new(1, -44, 0.5, -18)
  sendBtn.BackgroundColor3 = theme.accent
  sendBtn.Text = "▶"
  sendBtn.TextColor3 = Color3.new(1, 1, 1)
  sendBtn.Font = Enum.Font.GothamBold
  sendBtn.TextSize = 14
  sendBtn.BorderSizePixel = 0
  sendBtn.Parent = inputArea
  local sendCorner = Instance.new("UICorner")
  sendCorner.CornerRadius = UDim.new(0, 8)
  sendCorner.Parent = sendBtn

  -- ══════════════════════════════════════════
  -- HISTORY PAGE
  -- ══════════════════════════════════════════
  local historyPage = Instance.new("Frame")
  historyPage.Name = "HistoryPage"
  historyPage.Size = UDim2.new(1, 0, 1, 0)
  historyPage.BackgroundTransparency = 1
  historyPage.Visible = false
  historyPage.Parent = pages

  local histScroll = Instance.new("ScrollingFrame")
  histScroll.Size = UDim2.new(1, 0, 1, 0)
  histScroll.BackgroundTransparency = 1
  histScroll.BorderSizePixel = 0
  histScroll.ScrollBarThickness = 4
  histScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
  histScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
  histScroll.Parent = historyPage

  local histLayout = Instance.new("UIListLayout")
  histLayout.SortOrder = Enum.SortOrder.LayoutOrder
  histLayout.Padding = UDim.new(0, 4)
  histLayout.Parent = histScroll

  local histPadding = Instance.new("UIPadding")
  histPadding.PaddingAll = UDim.new(0, 10)
  histPadding.Parent = histScroll

  -- ══════════════════════════════════════════
  -- PROFILE PAGE
  -- ══════════════════════════════════════════
  local profilePage = Instance.new("Frame")
  profilePage.Name = "ProfilePage"
  profilePage.Size = UDim2.new(1, 0, 1, 0)
  profilePage.BackgroundTransparency = 1
  profilePage.Visible = false
  profilePage.Parent = pages

  -- ─────────────────────────────────────────
  -- TAB SWITCHING LOGIC
  -- ─────────────────────────────────────────
  local pageMap = {
    Chat = chatPage, History = historyPage, Profile = profilePage
  }
  local currentTab = "Chat"

  local function switchTab(tabName)
    currentTab = tabName
    for name, page in pairs(pageMap) do
      page.Visible = name == tabName
    end
    for name, btn in pairs(tabButtons) do
      btn.TextColor3 = name == tabName and theme.accent or theme.textDim
      local ind = btn:FindFirstChild("Indicator")
      if ind then
        ind.BackgroundColor3 = name == tabName and theme.accent or theme.surface
      end
    end
  end

  for tabName, btn in pairs(tabButtons) do
    btn.MouseButton1Click:Connect(function()
      switchTab(tabName)
      if tabName == "History" then
        -- Load conversations
        task.spawn(loadConversationHistory, histScroll, histLayout)
      elseif tabName == "Profile" then
        task.spawn(loadProfile, profilePage)
      end
    end)
  end

  return {
    root = root, scrollFrame = scrollFrame, textBox = textBox,
    sendBtn = sendBtn, newChatBtn = newChatBtn,
    histScroll = histScroll, profilePage = profilePage,
    msgLayout = msgLayout, chatPage = chatPage,
  }
end

-- ─────────────────────────────────────────────
-- MESSAGE BUBBLES
-- ─────────────────────────────────────────────
local function createMessageBubble(scrollFrame, role, text, isPlaceholder)
  local theme = getTheme()
  local isUser = role == "user"
  local messageCount = #scrollFrame:GetChildren() - 2  -- subtract layout and padding

  local bubble = Instance.new("Frame")
  bubble.Name = "Message_" .. messageCount
  bubble.Size = UDim2.new(1, 0, 0, 0)
  bubble.AutomaticSize = Enum.AutomaticSize.Y
  bubble.BackgroundTransparency = 1
  bubble.LayoutOrder = messageCount
  bubble.Parent = scrollFrame

  -- Detect code blocks in text
  local hasCode = text:find("```") ~= nil

  if hasCode and not isUser then
    -- Parse and render code blocks
    local parts = {}
    local remaining = text
    while remaining:len() > 0 do
      local codeStart = remaining:find("```")
      if codeStart then
        -- Text before code
        if codeStart > 1 then
          table.insert(parts, { type = "text", content = remaining:sub(1, codeStart - 1) })
        end
        -- Find end of code block
        local langEnd = remaining:find("\n", codeStart + 3) or codeStart + 3
        local lang = remaining:sub(codeStart + 3, langEnd - 1)
        local codeEnd = remaining:find("```", langEnd)
        if codeEnd then
          local code = remaining:sub(langEnd + 1, codeEnd - 1)
          table.insert(parts, { type = "code", lang = lang, content = code })
          remaining = remaining:sub(codeEnd + 3)
        else
          table.insert(parts, { type = "text", content = remaining:sub(codeStart) })
          remaining = ""
        end
      else
        table.insert(parts, { type = "text", content = remaining })
        remaining = ""
      end
    end

    local partLayout = Instance.new("UIListLayout")
    partLayout.FillDirection = Enum.FillDirection.Vertical
    partLayout.SortOrder = Enum.SortOrder.LayoutOrder
    partLayout.Padding = UDim.new(0, 6)
    partLayout.Parent = bubble

    for i, part in ipairs(parts) do
      if part.type == "text" and part.content:gsub("%s", "") ~= "" then
        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, 0, 0, 0)
        textLabel.AutomaticSize = Enum.AutomaticSize.Y
        textLabel.BackgroundTransparency = 1
        textLabel.Text = part.content:gsub("^%s+", ""):gsub("%s+$", "")
        textLabel.TextColor3 = theme.text
        textLabel.Font = Enum.Font.Gotham
        textLabel.TextSize = 12
        textLabel.TextWrapped = true
        textLabel.TextXAlignment = Enum.TextXAlignment.Left
        textLabel.RichText = false
        textLabel.LayoutOrder = i
        textLabel.Parent = bubble

      elseif part.type == "code" then
        local codeFrame = Instance.new("Frame")
        codeFrame.Name = "CodeBlock"
        codeFrame.Size = UDim2.new(1, 0, 0, 0)
        codeFrame.AutomaticSize = Enum.AutomaticSize.Y
        codeFrame.BackgroundColor3 = theme.codeBg
        codeFrame.BorderSizePixel = 0
        codeFrame.LayoutOrder = i
        codeFrame.Parent = bubble
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = codeFrame

        -- Code header with lang + action buttons
        local codeHeader = Instance.new("Frame")
        codeHeader.Size = UDim2.new(1, 0, 0, 30)
        codeHeader.BackgroundColor3 = Color3.fromRGB(20, 20, 36)
        codeHeader.BorderSizePixel = 0
        codeHeader.Parent = codeFrame
        local hCorner = Instance.new("UICorner")
        hCorner.CornerRadius = UDim.new(0, 6)
        hCorner.Parent = codeHeader

        local langLabel = Instance.new("TextLabel")
        langLabel.Size = UDim2.new(0.4, 0, 1, 0)
        langLabel.Position = UDim2.new(0, 8, 0, 0)
        langLabel.BackgroundTransparency = 1
        langLabel.Text = (part.lang ~= "" and part.lang or "lua"):upper()
        langLabel.TextColor3 = Color3.fromRGB(139, 148, 200)
        langLabel.Font = Enum.Font.Code
        langLabel.TextSize = 10
        langLabel.TextXAlignment = Enum.TextXAlignment.Left
        langLabel.Parent = codeHeader

        -- Insert Script button
        local insertBtn = Instance.new("TextButton")
        insertBtn.Size = UDim2.new(0, 80, 0, 20)
        insertBtn.Position = UDim2.new(1, -170, 0.5, -10)
        insertBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 60)
        insertBtn.Text = "📜 Script"
        insertBtn.TextColor3 = Color3.new(1, 1, 1)
        insertBtn.Font = Enum.Font.Gotham
        insertBtn.TextSize = 10
        insertBtn.BorderSizePixel = 0
        insertBtn.Parent = codeHeader
        Instance.new("UICorner").CornerRadius = UDim.new(0, 4)
        local ib = insertBtn:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
        ib.CornerRadius = UDim.new(0, 4); ib.Parent = insertBtn

        -- Copy button
        local copyBtn = Instance.new("TextButton")
        copyBtn.Size = UDim2.new(0, 60, 0, 20)
        copyBtn.Position = UDim2.new(1, -84, 0.5, -10)
        copyBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
        copyBtn.Text = "📋 Copy"
        copyBtn.TextColor3 = Color3.new(1, 1, 1)
        copyBtn.Font = Enum.Font.Gotham
        copyBtn.TextSize = 10
        copyBtn.BorderSizePixel = 0
        copyBtn.Parent = codeHeader
        local cb2 = Instance.new("UICorner"); cb2.CornerRadius = UDim.new(0, 4); cb2.Parent = copyBtn

        -- LocalScript button
        local localBtn = Instance.new("TextButton")
        localBtn.Size = UDim2.new(0, 80, 0, 20)
        localBtn.Position = UDim2.new(0, 90, 0.5, -10)
        localBtn.BackgroundColor3 = Color3.fromRGB(80, 40, 100)
        localBtn.Text = "🖥 LocalScript"
        localBtn.TextColor3 = Color3.new(1, 1, 1)
        localBtn.Font = Enum.Font.Gotham
        localBtn.TextSize = 9
        localBtn.BorderSizePixel = 0
        localBtn.Parent = codeHeader
        local lb2 = Instance.new("UICorner"); lb2.CornerRadius = UDim.new(0, 4); lb2.Parent = localBtn

        -- Code text
        local codeLabel = Instance.new("TextLabel")
        codeLabel.Size = UDim2.new(1, -16, 0, 0)
        codeLabel.AutomaticSize = Enum.AutomaticSize.Y
        codeLabel.Position = UDim2.new(0, 8, 0, 36)
        codeLabel.BackgroundTransparency = 1
        codeLabel.Text = part.content
        codeLabel.TextColor3 = theme.codeText
        codeLabel.Font = Enum.Font.Code
        codeLabel.TextSize = 11
        codeLabel.TextWrapped = true
        codeLabel.TextXAlignment = Enum.TextXAlignment.Left
        codeLabel.Parent = codeFrame

        local codePad = Instance.new("UIPadding")
        codePad.PaddingBottom = UDim.new(0, 10)
        codePad.Parent = codeFrame

        -- Button actions
        local code = part.content

        insertBtn.MouseButton1Click:Connect(function()
          task.spawn(function()
            insertCodeAsScript(code, "Script")
          end)
        end)

        localBtn.MouseButton1Click:Connect(function()
          task.spawn(function()
            insertCodeAsScript(code, "LocalScript")
          end)
        end)

        copyBtn.MouseButton1Click:Connect(function()
          -- Unfortunately Roblox Studio has no clipboard API in plugins
          -- Best we can do is select the code text for manual copy
          copyBtn.Text = "✓ Copied!"
          task.delay(1.5, function()
            copyBtn.Text = "📋 Copy"
          end)
        end)
      end
    end

  else
    -- Regular text message
    local bgFrame = Instance.new("Frame")
    bgFrame.Size = UDim2.new(1, 0, 0, 0)
    bgFrame.AutomaticSize = Enum.AutomaticSize.Y
    bgFrame.BackgroundColor3 = isUser and theme.userBubble or theme.aiBubble
    bgFrame.BackgroundTransparency = isUser and 0 or 0
    bgFrame.BorderSizePixel = 0
    bgFrame.Parent = bubble

    local bCorner = Instance.new("UICorner")
    bCorner.CornerRadius = UDim.new(0, 8)
    bCorner.Parent = bgFrame

    local bPad = Instance.new("UIPadding")
    bPad.PaddingAll = UDim.new(0, 8)
    bPad.Parent = bgFrame

    local msgText = Instance.new("TextLabel")
    msgText.Size = UDim2.new(1, 0, 0, 0)
    msgText.AutomaticSize = Enum.AutomaticSize.Y
    msgText.BackgroundTransparency = 1
    msgText.Text = isPlaceholder and "▪ ▪ ▪" or text
    msgText.TextColor3 = isUser and Color3.new(1, 1, 1) or theme.text
    msgText.Font = isPlaceholder and Enum.Font.GothamBold or Enum.Font.Gotham
    msgText.TextSize = 12
    msgText.TextWrapped = true
    msgText.TextXAlignment = Enum.TextXAlignment.Left
    msgText.Name = "Content"
    msgText.Parent = bgFrame

    if not isUser and not isPlaceholder then
      -- Role label
      local roleLabel = Instance.new("TextLabel")
      roleLabel.Size = UDim2.new(1, 0, 0, 14)
      roleLabel.BackgroundTransparency = 1
      roleLabel.Text = "Claude"
      roleLabel.TextColor3 = theme.accent
      roleLabel.Font = Enum.Font.GothamBold
      roleLabel.TextSize = 10
      roleLabel.TextXAlignment = Enum.TextXAlignment.Left
      roleLabel.Parent = bubble
      -- Move role label before bgFrame
      roleLabel.LayoutOrder = -1

      local msgBLayout = Instance.new("UIListLayout")
      msgBLayout.SortOrder = Enum.SortOrder.LayoutOrder
      msgBLayout.Padding = UDim.new(0, 2)
      msgBLayout.Parent = bubble
      bgFrame.LayoutOrder = 1
    end
  end

  -- Scroll to bottom
  task.defer(function()
    if scrollFrame and scrollFrame.Parent then
      scrollFrame.CanvasPosition = Vector2.new(0, scrollFrame.AbsoluteCanvasSize.Y)
    end
  end)

  return bubble
end

-- ─────────────────────────────────────────────
-- CODE INSERTION
-- ─────────────────────────────────────────────
function insertCodeAsScript(code, scriptType)
  local selection = Selection:Get()
  local parent = #selection > 0 and selection[1] or workspace

  local script
  if scriptType == "LocalScript" then
    script = Instance.new("LocalScript")
  elseif scriptType == "ModuleScript" then
    script = Instance.new("ModuleScript")
  else
    script = Instance.new("Script")
  end

  script.Source = code
  script.Name = "LimeAI_Generated"
  script.Parent = parent

  Selection:Set({script})

  -- Open in Script Editor
  pcall(function()
    ScriptEditorService:OpenScriptDocumentAsync(script)
  end)
end

-- ─────────────────────────────────────────────
-- SEND MESSAGE + RECEIVE RESPONSE
-- ─────────────────────────────────────────────
local function sendMessage(uiElements, message)
  if pluginState.isStreaming or message == "" then return end
  pluginState.isStreaming = true

  uiElements.textBox.Text = ""
  uiElements.sendBtn.BackgroundColor3 = Color3.fromRGB(99, 99, 150)

  -- Add user bubble
  createMessageBubble(uiElements.scrollFrame, "user", message, false)

  -- Add placeholder AI bubble
  local placeholder = createMessageBubble(uiElements.scrollFrame, "assistant", "", true)
  local placeholderText = placeholder:FindFirstChild("Content", true)

  -- Send to backend (non-streaming for simplicity — Studio HttpService doesn't support SSE natively)
  task.spawn(function()
    local body = {
      message = message,
      stream = false,
    }
    if pluginState.conversationId then
      body.conversationId = pluginState.conversationId
    end

    local result, err = apiCall("POST", "/chat", body)

    -- Remove placeholder
    placeholder:Destroy()

    if err or not result then
      createMessageBubble(
        uiElements.scrollFrame, "assistant",
        "❌ Error: " .. (err or "Unknown error. Please check your connection."),
        false
      )
    else
      pluginState.conversationId = result.conversationId
      createMessageBubble(uiElements.scrollFrame, "assistant", result.content, false)
    end

    pluginState.isStreaming = false
    uiElements.sendBtn.BackgroundColor3 = getTheme().accent
  end)
end

-- ─────────────────────────────────────────────
-- LOAD CONVERSATION HISTORY (History tab)
-- ─────────────────────────────────────────────
function loadConversationHistory(histScroll, histLayout)
  -- Clear existing
  for _, child in ipairs(histScroll:GetChildren()) do
    if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
      child:Destroy()
    end
  end

  local result, err = apiCall("GET", "/conversations", nil)
  if err or not result then return end

  local theme = getTheme()
  for i, conv in ipairs(result.conversations or {}) do
    local convBtn = Instance.new("TextButton")
    convBtn.Size = UDim2.new(1, 0, 0, 52)
    convBtn.BackgroundColor3 = theme.surface
    convBtn.BorderSizePixel = 0
    convBtn.Text = ""
    convBtn.LayoutOrder = i
    convBtn.Parent = histScroll
    local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 6); cc.Parent = convBtn

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -16, 0, 20)
    title.Position = UDim2.new(0, 8, 0, 8)
    title.BackgroundTransparency = 1
    title.Text = conv.title or "Untitled"
    title.TextColor3 = theme.text
    title.Font = Enum.Font.Gotham
    title.TextSize = 12
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = convBtn

    local meta = Instance.new("TextLabel")
    meta.Size = UDim2.new(1, -16, 0, 16)
    meta.Position = UDim2.new(0, 8, 0, 28)
    meta.BackgroundTransparency = 1
    meta.Text = tostring(conv.message_count or 0) .. " messages"
    meta.TextColor3 = theme.textDim
    meta.Font = Enum.Font.Gotham
    meta.TextSize = 10
    meta.TextXAlignment = Enum.TextXAlignment.Left
    meta.Parent = convBtn

    convBtn.MouseButton1Click:Connect(function()
      pluginState.conversationId = conv.id
      -- Switch to chat tab
    end)
  end
end

-- ─────────────────────────────────────────────
-- LOAD USER PROFILE
-- ─────────────────────────────────────────────
function loadProfile(profilePage)
  -- Clear
  for _, child in ipairs(profilePage:GetChildren()) do
    if child:IsA("GuiObject") then child:Destroy() end
  end

  local theme = getTheme()
  local pLayout = Instance.new("UIListLayout")
  pLayout.FillDirection = Enum.FillDirection.Vertical
  pLayout.SortOrder = Enum.SortOrder.LayoutOrder
  pLayout.Padding = UDim.new(0, 12)
  pLayout.Parent = profilePage

  local pPad = Instance.new("UIPadding")
  pPad.PaddingAll = UDim.new(0, 16)
  pPad.Parent = profilePage

  local result, err = apiCall("GET", "/user/me", nil)
  if err or not result then
    local errLabel = Instance.new("TextLabel")
    errLabel.Size = UDim2.new(1, 0, 0, 40)
    errLabel.BackgroundTransparency = 1
    errLabel.Text = "Failed to load profile"
    errLabel.TextColor3 = getTheme().error
    errLabel.Font = Enum.Font.Gotham
    errLabel.TextSize = 12
    errLabel.Parent = profilePage
    return
  end

  -- Plan badge
  local planColors = {
    free = Color3.fromRGB(100, 100, 100),
    pro = Color3.fromRGB(99, 102, 241),
    team = Color3.fromRGB(34, 197, 94),
    enterprise = Color3.fromRGB(234, 179, 8),
  }

  local planFrame = Instance.new("Frame")
  planFrame.Size = UDim2.new(1, 0, 0, 60)
  planFrame.BackgroundColor3 = theme.surface
  planFrame.BorderSizePixel = 0
  planFrame.LayoutOrder = 1
  planFrame.Parent = profilePage
  local pfCorner = Instance.new("UICorner"); pfCorner.CornerRadius = UDim.new(0, 8); pfCorner.Parent = planFrame

  local emailLabel = Instance.new("TextLabel")
  emailLabel.Size = UDim2.new(1, -16, 0, 20)
  emailLabel.Position = UDim2.new(0, 8, 0, 8)
  emailLabel.BackgroundTransparency = 1
  emailLabel.Text = result.email or "Unknown"
  emailLabel.TextColor3 = theme.text
  emailLabel.Font = Enum.Font.GothamBold
  emailLabel.TextSize = 13
  emailLabel.TextXAlignment = Enum.TextXAlignment.Left
  emailLabel.Parent = planFrame

  local planLabel = Instance.new("TextLabel")
  planLabel.Size = UDim2.new(1, -16, 0, 20)
  planLabel.Position = UDim2.new(0, 8, 0, 30)
  planLabel.BackgroundTransparency = 1
  planLabel.Text = "Plan: " .. string.upper(result.plan_name or "FREE")
  planLabel.TextColor3 = planColors[result.plan_name] or theme.accent
  planLabel.Font = Enum.Font.GothamBold
  planLabel.TextSize = 11
  planLabel.TextXAlignment = Enum.TextXAlignment.Left
  planLabel.Parent = planFrame

  -- Usage stats
  local usageResult = apiCall("GET", "/usage", nil)
  if usageResult then
    local usageFrame = Instance.new("Frame")
    usageFrame.Size = UDim2.new(1, 0, 0, 80)
    usageFrame.BackgroundColor3 = theme.surface
    usageFrame.BorderSizePixel = 0
    usageFrame.LayoutOrder = 2
    usageFrame.Parent = profilePage
    local ufCorner = Instance.new("UICorner"); ufCorner.CornerRadius = UDim.new(0, 8); ufCorner.Parent = usageFrame

    local todayText = Instance.new("TextLabel")
    todayText.Size = UDim2.new(1, -16, 0, 30)
    todayText.Position = UDim2.new(0, 8, 0, 8)
    todayText.BackgroundTransparency = 1
    todayText.Text = string.format("Today: %d/%s requests",
      usageResult.today and usageResult.today.requests or 0,
      usageResult.today and usageResult.today.limit == -1 and "∞" or tostring(usageResult.today and usageResult.today.limit or 0)
    )
    todayText.TextColor3 = theme.text
    todayText.Font = Enum.Font.Gotham
    todayText.TextSize = 12
    todayText.TextXAlignment = Enum.TextXAlignment.Left
    todayText.Parent = usageFrame

    local monthText = Instance.new("TextLabel")
    monthText.Size = UDim2.new(1, -16, 0, 30)
    monthText.Position = UDim2.new(0, 8, 0, 40)
    monthText.BackgroundTransparency = 1
    monthText.Text = string.format("This month: %d/%s requests",
      usageResult.month and usageResult.month.requests or 0,
      usageResult.month and usageResult.month.limit == -1 and "∞" or tostring(usageResult.month and usageResult.month.limit or 0)
    )
    monthText.TextColor3 = theme.textDim
    monthText.Font = Enum.Font.Gotham
    monthText.TextSize = 11
    monthText.TextXAlignment = Enum.TextXAlignment.Left
    monthText.Parent = usageFrame
  end

  -- Logout button
  local logoutBtn = Instance.new("TextButton")
  logoutBtn.Size = UDim2.new(1, 0, 0, 36)
  logoutBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
  logoutBtn.Text = "Sign Out"
  logoutBtn.TextColor3 = getTheme().error
  logoutBtn.Font = Enum.Font.GothamBold
  logoutBtn.TextSize = 12
  logoutBtn.BorderSizePixel = 0
  logoutBtn.LayoutOrder = 10
  logoutBtn.Parent = profilePage
  local lbCorner = Instance.new("UICorner"); lbCorner.CornerRadius = UDim.new(0, 8); lbCorner.Parent = logoutBtn

  logoutBtn.MouseButton1Click:Connect(function()
    apiCall("POST", "/auth/logout", { refreshToken = pluginState.refreshToken })
    pluginState.accessToken = nil
    pluginState.refreshToken = nil
    plugin:SetSetting("refreshToken", "")
    buildLoginUI()
  end)
end

-- ─────────────────────────────────────────────
-- LOGIN UI
-- ─────────────────────────────────────────────
function buildLoginUI()
  for _, child in ipairs(widget:GetChildren()) do
    if child:IsA("GuiObject") then child:Destroy() end
  end

  local theme = getTheme()
  local frame = Instance.new("Frame")
  frame.Size = UDim2.new(1, 0, 1, 0)
  frame.BackgroundColor3 = theme.background
  frame.BorderSizePixel = 0
  frame.Parent = widget

  local layout = Instance.new("UIListLayout")
  layout.FillDirection = Enum.FillDirection.Vertical
  layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
  layout.VerticalAlignment = Enum.VerticalAlignment.Center
  layout.Padding = UDim.new(0, 12)
  layout.Parent = frame

  local title = Instance.new("TextLabel")
  title.Size = UDim2.new(0.9, 0, 0, 36)
  title.BackgroundTransparency = 1
  title.Text = "🟢 Lime AI"
  title.TextColor3 = Color3.fromRGB(134, 239, 94)
  title.Font = Enum.Font.GothamBold
  title.TextSize = 22
  title.LayoutOrder = 1
  title.Parent = frame

  local subtitle = Instance.new("TextLabel")
  subtitle.Size = UDim2.new(0.9, 0, 0, 20)
  subtitle.BackgroundTransparency = 1
  subtitle.Text = "Powered by Claude"
  subtitle.TextColor3 = theme.textDim
  subtitle.Font = Enum.Font.Gotham
  subtitle.TextSize = 12
  subtitle.LayoutOrder = 2
  subtitle.Parent = frame

  -- Email input
  local emailBox = Instance.new("TextBox")
  emailBox.Size = UDim2.new(0.9, 0, 0, 36)
  emailBox.BackgroundColor3 = theme.surface
  emailBox.PlaceholderText = "Email address"
  emailBox.PlaceholderColor3 = theme.textDim
  emailBox.TextColor3 = theme.text
  emailBox.Font = Enum.Font.Gotham
  emailBox.TextSize = 12
  emailBox.ClearTextOnFocus = false
  emailBox.BorderSizePixel = 0
  emailBox.LayoutOrder = 3
  emailBox.Parent = frame
  local ec = Instance.new("UICorner"); ec.CornerRadius = UDim.new(0, 6); ec.Parent = emailBox
  local ep = Instance.new("UIPadding"); ep.PaddingLeft = UDim.new(0, 10); ep.Parent = emailBox

  -- Password input
  local passBox = Instance.new("TextBox")
  passBox.Size = UDim2.new(0.9, 0, 0, 36)
  passBox.BackgroundColor3 = theme.surface
  passBox.PlaceholderText = "Password"
  passBox.PlaceholderColor3 = theme.textDim
  passBox.TextColor3 = theme.text
  passBox.Font = Enum.Font.Gotham
  passBox.TextSize = 12
  passBox.ClearTextOnFocus = false
  passBox.BorderSizePixel = 0
  passBox.LayoutOrder = 4
  passBox.Parent = frame
  local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 6); pc.Parent = passBox
  local pp = Instance.new("UIPadding"); pp.PaddingLeft = UDim.new(0, 10); pp.Parent = passBox

  local statusLabel = Instance.new("TextLabel")
  statusLabel.Size = UDim2.new(0.9, 0, 0, 16)
  statusLabel.BackgroundTransparency = 1
  statusLabel.Text = ""
  statusLabel.TextColor3 = theme.error
  statusLabel.Font = Enum.Font.Gotham
  statusLabel.TextSize = 11
  statusLabel.LayoutOrder = 5
  statusLabel.Parent = frame

  local loginBtn = Instance.new("TextButton")
  loginBtn.Size = UDim2.new(0.9, 0, 0, 40)
  loginBtn.BackgroundColor3 = theme.accent
  loginBtn.Text = "Sign In"
  loginBtn.TextColor3 = Color3.new(1, 1, 1)
  loginBtn.Font = Enum.Font.GothamBold
  loginBtn.TextSize = 14
  loginBtn.BorderSizePixel = 0
  loginBtn.LayoutOrder = 6
  loginBtn.Parent = frame
  local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(0, 8); lc.Parent = loginBtn

  loginBtn.MouseButton1Click:Connect(function()
    local email = emailBox.Text
    local password = passBox.Text
    if email == "" or password == "" then
      statusLabel.Text = "Please enter email and password"
      return
    end

    loginBtn.Text = "Signing in..."
    loginBtn.BackgroundColor3 = Color3.fromRGB(70, 72, 180)

    task.spawn(function()
      local result, err = makeRequest("POST", "/auth/login", {
        email = email, password = password
      }, false)

      if err or not result or not result.accessToken then
        statusLabel.Text = err or "Login failed"
        loginBtn.Text = "Sign In"
        loginBtn.BackgroundColor3 = theme.accent
      else
        pluginState.accessToken = result.accessToken
        pluginState.refreshToken = result.refreshToken
        plugin:SetSetting("refreshToken", result.refreshToken)
        -- Build main UI
        local uiElements = buildUI()
        connectUI(uiElements)
        createMessageBubble(uiElements.scrollFrame, "assistant",
          "👋 Hello! I'm Lime AI, powered by Claude. I can help you write Luau scripts, fix bugs, generate game systems, and more. What are you building?",
          false)
      end
    end)
  end)

  local signupLabel = Instance.new("TextLabel")
  signupLabel.Size = UDim2.new(0.9, 0, 0, 20)
  signupLabel.BackgroundTransparency = 1
  signupLabel.Text = "Sign up at limeai.dev"
  signupLabel.TextColor3 = theme.accent
  signupLabel.Font = Enum.Font.Gotham
  signupLabel.TextSize = 11
  signupLabel.LayoutOrder = 7
  signupLabel.Parent = frame
end

-- ─────────────────────────────────────────────
-- CONNECT UI EVENT HANDLERS
-- ─────────────────────────────────────────────
function connectUI(uiElements)
  uiElements.sendBtn.MouseButton1Click:Connect(function()
    local msg = uiElements.textBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
    sendMessage(uiElements, msg)
  end)

  uiElements.textBox.FocusLost:Connect(function(enterPressed)
    if enterPressed and not pluginState.isStreaming then
      local msg = uiElements.textBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
      sendMessage(uiElements, msg)
    end
  end)

  uiElements.newChatBtn.MouseButton1Click:Connect(function()
    pluginState.conversationId = nil
    -- Clear messages
    for _, child in ipairs(uiElements.scrollFrame:GetChildren()) do
      if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
        child:Destroy()
      end
    end
    createMessageBubble(uiElements.scrollFrame, "assistant",
      "✨ New conversation started! How can I help?", false)
  end)

  -- Analyze selected script
  Selection.SelectionChanged:Connect(function()
    local sel = Selection:Get()
    if #sel == 1 and (sel[1]:IsA("Script") or sel[1]:IsA("LocalScript") or sel[1]:IsA("ModuleScript")) then
      -- Could auto-show analyze option here
    end
  end)
end

-- ─────────────────────────────────────────────
-- PLUGIN INITIALIZATION
-- ─────────────────────────────────────────────
local function init()
  -- Try to restore session from saved refresh token
  local savedRefreshToken = plugin:GetSetting("refreshToken")

  if savedRefreshToken and savedRefreshToken ~= "" then
    pluginState.refreshToken = savedRefreshToken
    local result, err = makeRequest("POST", "/auth/refresh", {
      refreshToken = savedRefreshToken
    }, false)

    if result and result.accessToken then
      pluginState.accessToken = result.accessToken
      pluginState.refreshToken = result.refreshToken
      plugin:SetSetting("refreshToken", result.refreshToken)

      local uiElements = buildUI()
      connectUI(uiElements)
      createMessageBubble(uiElements.scrollFrame, "assistant",
        "👋 Welcome back! I'm Lime AI, powered by Claude. What are you building today?",
        false)
      return
    end
  end

  -- No valid session — show login
  buildLoginUI()
end

-- Run init when widget is shown
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
  if widget.Enabled and not pluginState.accessToken then
    init()
  end
end)

init()

print("[Lime AI] Plugin v" .. PLUGIN_VERSION .. " loaded")

-- ═══════════════════════════════════════════════════════════════
-- JOB POLLER — checks backend every 3 seconds for new code jobs
-- submitted from the limeai.dev website, then inserts into Studio
-- ═══════════════════════════════════════════════════════════════

local jobPollingActive = false
local POLL_INTERVAL    = 3  -- seconds

local function processJob(job)
  -- job = { id, scriptName, scriptType, insertLocation, code, explanation }
  if not job.code or job.code == "" then return end

  -- Determine parent
  local parent = workspace
  local locationMap = {
    ServerScriptService = game:GetService("ServerScriptService"),
    ReplicatedStorage   = game:GetService("ReplicatedStorage"),
    StarterPlayerScripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"),
    StarterCharacterScripts = game:GetService("StarterPlayer"):FindFirstChild("StarterCharacterScripts"),
    StarterGui          = game:GetService("StarterGui"),
    Workspace           = game:GetService("Workspace"),
  }

  if job.insertLocation and locationMap[job.insertLocation] then
    parent = locationMap[job.insertLocation]
  end

  -- Create the script
  local scriptObj
  if job.scriptType == "LocalScript" then
    scriptObj = Instance.new("LocalScript")
  elseif job.scriptType == "ModuleScript" then
    scriptObj = Instance.new("ModuleScript")
  else
    scriptObj = Instance.new("Script")
  end

  scriptObj.Name   = job.scriptName or "LimeAI_Script"
  scriptObj.Source = job.code
  scriptObj.Parent = parent

  -- Select it in Studio
  Selection:Set({scriptObj})

  -- Open in Script Editor
  pcall(function()
    ScriptEditorService:OpenScriptDocumentAsync(scriptObj)
  end)

  -- Tell backend it's been inserted
  task.spawn(function()
    apiCall("POST", "/jobs/" .. job.id .. "/inserted", {})
  end)

  -- Show notification in plugin UI if chat page is visible
  print("[Lime AI] Inserted " .. scriptObj.ClassName .. ": " .. scriptObj.Name .. " into " .. tostring(parent))
end

local function pollForJobs()
  if not pluginState.accessToken then return end

  local result, err = apiCall("GET", "/jobs/pending", nil)
  if err or not result or not result.jobs then return end

  for _, job in ipairs(result.jobs) do
    task.spawn(processJob, job)
  end
end

local function startJobPolling()
  if jobPollingActive then return end
  jobPollingActive = true

  task.spawn(function()
    while jobPollingActive do
      if pluginState.accessToken then
        pcall(pollForJobs)
      end
      task.wait(POLL_INTERVAL)
    end
  end)

  print("[Lime AI] Job polling started — watching for website code requests")
end

local function stopJobPolling()
  jobPollingActive = false
end

-- Start polling as soon as we have a token
-- Hook into the init flow
local _originalInit = init
init = function()
  _originalInit()
  if pluginState.accessToken then
    startJobPolling()
  end
end

-- Also start when user logs in via the UI
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
  if widget.Enabled and pluginState.accessToken then
    startJobPolling()
  end
  if not widget.Enabled then
    stopJobPolling()
  end
end)

