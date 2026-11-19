-- Hud: owns the client HUD: cash and income readouts, carry panel, status lines, storm banner, and alert cards.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: Hud.build, Hud.update, Hud.tick, Hud.basePosition, Hud.setStorm, Hud.setLock, Hud.alert, Hud.setHint, Hud.start
--!strict
-- ============================================================================
-- Module contract (derived from the code below)
--
-- Owns:
--   * The "PulauHud" ScreenGui under the local player's PlayerGui (one copy;
--     Hud.build destroys any existing "PulauHud" before creating a new one).
--   * Every widget in it: the cash plate and cash label, the income label, the
--     "Carrying" panel (holding and carry income labels), the "Status" frame
--     (rebirth, storm, lock labels), the hint label, the "StormBanner" frame,
--     and the "Alerts" stack of fading alert cards.
--   * Client-side display state only: the storm countdown (nextStormAt,
--     serverStormIn, lastStormText), the lock countdown (lockUntil), the banner
--     hide time (bannerHideAt), the cached cash text (lastCashText), the last
--     base position the server reported (basePosition), and the single
--     RenderStepped connection (ticker).
--
-- Refuses:
--   * Gameplay authority: it never changes cash, carry, rebirths, storms or
--     locks. It only shows what the server sends through Hud.update,
--     Hud.setStorm, Hud.setLock and Hud.alert.
--   * Drawing before Hud.build: Hud.update returns at once when no gui exists,
--     every other writer checks its label is set, and pushAlert returns when
--     there is no alert stack.
--   * Badly typed payload fields: cash, rebirths and seconds go through
--     tonumber with defaults; carrying must be a table, basePosition a
--     Vector3, stormIn a number, and an alert color a Color3, or they are
--     ignored or replaced with a default.
--   * Running two tickers: Hud.start disconnects the old RenderStepped
--     connection before it connects a new one.
--
-- Returns:
--   * The Hud table. Hud.build returns Hud, Hud.basePosition returns the last
--     reported base position (Vector3?), Hud.start returns nil, and every
--     other public function returns nothing.
-- ============================================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Hud = {}

local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local cashLabel: TextLabel? = nil
local cashPlate: Frame? = nil
local incomeLabel: TextLabel? = nil
local carryLabel: TextLabel? = nil
local carryIncomeLabel: TextLabel? = nil
local rebirthLabel: TextLabel? = nil
local stormLabel: TextLabel? = nil
local lockLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local tutorialLabel: TextLabel? = nil
local bannerFrame: Frame? = nil
local bannerLabel: TextLabel? = nil
local alertStack: Frame? = nil
local carryingPanel: Frame? = nil

local nextStormAt: number? = nil
local serverStormIn: number? = nil
local lastStormText = ""
local lockUntil: number? = nil
local bannerHideAt: number? = nil
local lastCashText = ""
local basePosition: Vector3? = nil

-- === formatting ===
-- Formats a number as a whole number with commas every three digits, keeping a leading minus sign.
-- Returns the formatted string, e.g. 1234567.8 becomes "1,234,567" and -1500 becomes "-1,500".
local function comma(value: number): string
	local whole = math.floor(math.abs(value))
	local text = tostring(whole)
	local out = ""
	local count = 0
	for i = #text, 1, -1 do
		out = string.sub(text, i, i) .. out
		count += 1
		if count % 3 == 0 and i > 1 then
			out = "," .. out
		end
	end
	if value < 0 then
		out = "-" .. out
	end
	return out
end

-- Turns a number of seconds into a minutes:seconds clock, with negatives clamped to zero.
-- Returns a string like "3:05"; whole minutes are not wrapped into hours.
local function clock(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local minutes = total // 60
	local secs = total % 60
	return string.format("%d:%02d", minutes, secs)
end

-- === label helper ===
-- Creates a transparent, centred GothamBlack TextLabel with a black stroke and parents it to parent.
-- Returns the new TextLabel so the caller can change alignment, font or text afterwards.
local function makeLabel(parent: Instance, name: string, size: UDim2, position: UDim2, textSize: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextScaled = false
	label.Text = ""
	label.Parent = parent
	return label
end

-- === alert styling ===
local ALERT_STYLE: { [string]: { color: Color3, icon: string } } = {
	stolen = { color = Color3.fromRGB(255, 110, 110), icon = "[THIEF]" },
	stole = { color = Color3.fromRGB(255, 190, 90), icon = "[STEAL]" },
	locked = { color = Color3.fromRGB(150, 220, 255), icon = "[LOCK]" },
	["storm-warning"] = { color = Color3.fromRGB(255, 90, 90), icon = "[STORM]" },
	storm = { color = Color3.fromRGB(120, 190, 255), icon = "[STORM]" },
	rebirth = { color = Color3.fromRGB(255, 210, 120), icon = "[REBIRTH]" },
}

-- === alert stack ===
-- Adds an alert card (icon and colour from ALERT_STYLE by data.kind) to the stack, fading and destroying it after 4 seconds.
-- Returns nothing; it does nothing if Hud.build has not created the alert stack yet.
local function pushAlert(data: { [string]: any })
	local stack = alertStack
	if not stack then
		return
	end
	local kind = tostring(data.kind or "")
	local style = ALERT_STYLE[kind]
	local color = data.color
	if typeof(color) ~= "Color3" then
		color = if style then style.color else Color3.fromRGB(255, 255, 255)
	end
	local icon = if style then style.icon else "[!]"
	local card = Instance.new("TextLabel")
	card.Name = "Alert"
	card.Size = UDim2.fromScale(1, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
	card.BackgroundTransparency = 0.15
	card.TextColor3 = color
	card.TextSize = 22
	card.Font = Enum.Font.GothamBold
	card.TextWrapped = true
	card.TextScaled = false
	card.Text = icon .. " " .. tostring(data.text or "")
	card.LayoutOrder = math.floor((os.clock() * 1000) % 1000000)
	card.Parent = stack

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = card

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card

	task.delay(4, function()
		if not card.Parent then
			return
		end
		local tween = TweenService:Create(card, TweenInfo.new(0.5), { BackgroundTransparency = 1, TextTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		card:Destroy()
	end)
end

-- === public api ===
-- Destroys any old "PulauHud" and builds a fresh ScreenGui with every HUD widget, saving them in module locals.
-- Returns the Hud table so calls can be chained.
function Hud.build()
	local existing = player:FindFirstChild("PlayerGui")
	local container = existing and existing:FindFirstChild("PulauHud")
	if container then
		container:Destroy()
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "PulauHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = screen

	cashPlate = Instance.new("Frame")
	cashPlate.Name = "CashPlate"
	cashPlate.Size = UDim2.new(0, 300, 0, 74)
	cashPlate.Position = UDim2.new(0, 14, 0, 12)
	cashPlate.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
	cashPlate.BackgroundTransparency = 0.3
	cashPlate.BorderSizePixel = 0
	cashPlate.Parent = screen
	local plateCorner = Instance.new("UICorner")
	plateCorner.CornerRadius = UDim.new(0, 12)
	plateCorner.Parent = cashPlate
	local plateStroke = Instance.new("UIStroke")
	plateStroke.Color = Color3.fromRGB(60, 210, 120)
	plateStroke.Thickness = 1.5
	plateStroke.Transparency = 0.55
	plateStroke.Parent = cashPlate

	cashLabel = makeLabel(screen, "Cash", UDim2.new(0, 280, 0, 38), UDim2.new(0, 24, 0, 16), 34, Color3.fromRGB(120, 255, 150))
	cashLabel.Font = Enum.Font.GothamBlack
	cashLabel.TextXAlignment = Enum.TextXAlignment.Left
	cashLabel.TextStrokeTransparency = 0.35
	incomeLabel = makeLabel(screen, "Income", UDim2.new(0, 280, 0, 20), UDim2.new(0, 24, 0, 50), 17, Color3.fromRGB(110, 240, 140))
	incomeLabel.Font = Enum.Font.GothamBold
	incomeLabel.TextXAlignment = Enum.TextXAlignment.Left

	local panel = Instance.new("Frame")
	panel.Name = "Carrying"
	panel.Size = UDim2.new(0, 300, 0, 60)
	panel.Position = UDim2.new(0, 14, 1, -78)
	panel.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	panel.BackgroundTransparency = 0.2
	panel.Visible = false
	panel.Parent = screen
	carryingPanel = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel

	carryLabel = makeLabel(panel, "Holding", UDim2.new(1, -16, 0, 32), UDim2.new(0, 10, 0, 4), 22, Color3.fromRGB(255, 255, 255))
	carryLabel.TextXAlignment = Enum.TextXAlignment.Left
	carryIncomeLabel = makeLabel(panel, "CarryIncome", UDim2.new(1, -16, 0, 24), UDim2.new(0, 10, 0, 36), 18, Color3.fromRGB(120, 255, 150))
	carryIncomeLabel.TextXAlignment = Enum.TextXAlignment.Left

	local info = Instance.new("Frame")
	info.Name = "Status"
	info.Size = UDim2.new(0, 232, 0, 78)
	info.Position = UDim2.new(1, -246, 0, 12)
	info.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
	info.BackgroundTransparency = 0.3
	info.BorderSizePixel = 0
	info.Parent = screen
	local infoCorner = Instance.new("UICorner")
	infoCorner.CornerRadius = UDim.new(0, 12)
	infoCorner.Parent = info
	local infoStroke = Instance.new("UIStroke")
	infoStroke.Color = Color3.fromRGB(120, 160, 220)
	infoStroke.Thickness = 1.5
	infoStroke.Transparency = 0.6
	infoStroke.Parent = info

	rebirthLabel = makeLabel(info, "Rebirth", UDim2.new(1, -20, 0, 22), UDim2.new(0, 10, 0, 6), 16, Color3.fromRGB(255, 210, 120))
	rebirthLabel.TextXAlignment = Enum.TextXAlignment.Right

	stormLabel = makeLabel(info, "Storm", UDim2.new(1, -20, 0, 24), UDim2.new(0, 10, 0, 27), 18, Color3.fromRGB(160, 200, 255))
	stormLabel.TextXAlignment = Enum.TextXAlignment.Right

	lockLabel = makeLabel(info, "Lock", UDim2.new(1, -20, 0, 22), UDim2.new(0, 10, 0, 50), 16, Color3.fromRGB(120, 230, 150))
	lockLabel.TextXAlignment = Enum.TextXAlignment.Right

	hintLabel = makeLabel(screen, "Hint", UDim2.new(0, 620, 0, 26), UDim2.new(0.5, -310, 1, -46), 18, Color3.fromRGB(236, 240, 250))

	local tuto = Instance.new("Frame")
	tuto.Name = "Tutorial"
	tuto.Size = UDim2.new(0, 420, 0, 46)
	tuto.Position = UDim2.new(0.5, -210, 1, -104)
	tuto.BackgroundColor3 = Color3.fromRGB(16, 34, 52)
	tuto.BackgroundTransparency = 0.15
	tuto.BorderSizePixel = 0
	tuto.Visible = false
	tuto.Parent = screen
	local tutoCorner = Instance.new("UICorner")
	tutoCorner.CornerRadius = UDim.new(0, 10)
	tutoCorner.Parent = tuto
	local tutoStroke = Instance.new("UIStroke")
	tutoStroke.Color = Color3.fromRGB(120, 200, 255)
	tutoStroke.Thickness = 1.5
	tutoStroke.Transparency = 0.35
	tutoStroke.Parent = tuto
	tutorialLabel = makeLabel(tuto, "TutorialText", UDim2.new(1, -20, 1, 0), UDim2.new(0, 10, 0, 0), 17, Color3.fromRGB(226, 240, 255))
	tutorialLabel.Font = Enum.Font.GothamBold

	local banner = Instance.new("Frame")
	banner.Name = "StormBanner"
	banner.Size = UDim2.new(0.7, 0, 0, 110)
	banner.Position = UDim2.new(0.15, 0, 0.42, 0)
	banner.BackgroundColor3 = Color3.fromRGB(14, 30, 52)
	banner.BackgroundTransparency = 0.15
	banner.Visible = false
	banner.Parent = screen
	bannerFrame = banner

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 14)
	bannerCorner.Parent = banner

	bannerLabel = makeLabel(banner, "BannerText", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 44, Color3.fromRGB(150, 210, 255))
	bannerLabel.Font = Enum.Font.GothamBlack

	local stack = Instance.new("Frame")
	stack.Name = "Alerts"
	stack.Size = UDim2.new(0, 520, 0, 0)
	stack.Position = UDim2.new(0.5, -260, 0, 90)
	stack.BackgroundTransparency = 1
	stack.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = stack
	alertStack = stack

	return Hud
end

-- === inner updates ===
-- Sets the HUD's UIScale from the camera viewport width (1280px base), clamped between 0.7 and 1.0.
-- Returns nothing; it does nothing if the HUD has not been built.
local function updateScaling()
	local screen = gui
	if not screen then
		return
	end
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local scale = screen:FindFirstChildOfClass("UIScale")
	if scale then
		local factor = math.clamp(viewport.X / 1280, 0.7, 1.0)
		scale.Scale = factor
	end
end

-- === storm text ===
-- Works out the seconds left until the next storm from the local countdown, or else the last server value.
-- Returns "Next storm: --" if unknown, "STORM IN n" for 10 seconds or less, otherwise "Next storm: m:ss".
local function stormText(): string
	local seconds: number? = nil
	if nextStormAt then
		seconds = math.max(0, nextStormAt - os.clock())
	elseif serverStormIn then
		seconds = serverStormIn
	end
	if not seconds then
		return "Next storm: --"
	end
	if seconds <= 10 then
		return "STORM IN " .. tostring(math.max(0, math.ceil(seconds)))
	end
	return "Next storm: " .. clock(seconds)
end

-- === inner updates ===
-- Writes stormText() to the storm label only when it changed, turning it red during the "STORM IN" countdown.
-- Returns nothing; it does nothing if the storm label has not been built.
local function refreshStorm()
	if not stormLabel then
		return
	end
	local text = stormText()
	if text ~= lastStormText then
		lastStormText = text
		stormLabel.Text = text
		if string.find(text, "STORM IN", 1, true) then
			stormLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		else
			stormLabel.TextColor3 = Color3.fromRGB(160, 200, 255)
		end
	end
end

-- === public api ===
-- Renders a server state snapshot: cash, income, carry panel, rebirths, base position, storm countdown and lock text.
-- Returns nothing; it does nothing before Hud.build, and bad or missing fields fall back to defaults or are skipped.
function Hud.update(state: { [string]: any })
	if not gui then
		return
	end
	updateScaling()

	if cashLabel then
		local cash = math.floor(tonumber(state.cash) or 0)
		local text = "$" .. comma(cash)
		if text ~= lastCashText then
			cashLabel.Text = text
			lastCashText = text
		end
	end
	if incomeLabel then
		incomeLabel.Text = "+$" .. comma(state.incomeRate or 0) .. " / sec"
	end
	if carryLabel and carryIncomeLabel and carryingPanel then
		local carrying = state.carrying
		if carrying and typeof(carrying) == "table" then
			carryingPanel.Visible = true
			carryLabel.Text = "Carrying: " .. tostring(carrying.name or "?")
			carryIncomeLabel.Text = "+$" .. comma(carrying.income or 0) .. " / sec"
		else
			carryingPanel.Visible = false
		end
	end
	if rebirthLabel then
		local count = tonumber(state.rebirths) or 0
		local bonus = math.floor(count * 50)
		rebirthLabel.Text = "Rebirths: " .. tostring(count) .. "  (+" .. tostring(bonus) .. "%)"
	end
	if typeof(state.basePosition) == "Vector3" then
		basePosition = state.basePosition
	end
	if typeof(state.stormIn) == "number" then
		nextStormAt = os.clock() + state.stormIn
		serverStormIn = state.stormIn
	end
	refreshStorm()
	if lockLabel then
		if lockUntil then
			local remain = math.max(0, math.ceil(lockUntil - os.clock()))
			if remain > 0 then
				lockLabel.Text = "LOCKED  " .. tostring(remain) .. "s"
				lockLabel.TextColor3 = Color3.fromRGB(255, 96, 96)
			else
				lockLabel.Text = "Base unlocked"
				lockLabel.TextColor3 = Color3.fromRGB(120, 230, 150)
			end
		else
			lockLabel.Text = "Base unlocked"
			lockLabel.TextColor3 = Color3.fromRGB(120, 230, 150)
		end
	end
	if tutorialLabel and tutorialLabel.Parent then
		local frame = tutorialLabel.Parent
		if state.tutorialDone == true then
			frame.Visible = false
		elseif state.carrying then
			frame.Visible = true
			tutorialLabel.Text = "Bawa ke base, tahan [E] di pedestal"
		elseif (state.incomeRate or 0) > 0 then
			frame.Visible = false
		else
			frame.Visible = true
			tutorialLabel.Text = "Ambil brainrot di dermaga (utara pulau)"
		end
	end
end

-- === public api ===
local ticker: RBXScriptConnection? = nil

-- Per-frame step: moves the storm countdown on, hides or recounts the storm banner, and counts down the base lock.
-- Returns nothing; it clears nextStormAt once it is more than 1 second past, and lockUntil once it runs out.
function Hud.tick()
	local now = os.clock()
	if stormLabel and nextStormAt then
		if nextStormAt - now < -1 then
			nextStormAt = nil
		end
		refreshStorm()
	end
	if bannerFrame and bannerLabel and bannerHideAt then
		if bannerFrame.Visible and now >= bannerHideAt then
			bannerFrame.Visible = false
		elseif bannerFrame.Visible then
			local left = math.max(0, math.ceil(bannerHideAt - now))
			if bannerLabel.Text:find("STORM INBOUND") then
				bannerLabel.Text = "STORM INBOUND - " .. tostring(left) .. "s"
			end
		end
	end
	if lockLabel and lockUntil then
		local remain = math.max(0, math.ceil(lockUntil - now))
		if remain <= 0 then
			lockUntil = nil
			lockLabel.Text = "Base unlocked"
		else
			lockLabel.Text = "Base locked: " .. tostring(remain) .. "s"
		end
	end
end

-- Reads the last base position the server sent through Hud.update.
-- Returns that Vector3, or nil if no valid position has arrived yet.
function Hud.basePosition(): Vector3?
	return basePosition
end

-- Handles a storm phase from the server: "warning" starts the countdown banner, "wave" shows the wave banner for 8s, "clear" hides it.
-- Returns nothing; it resets the next-storm countdown (default 10s on warning, 180s on clear) and refreshes the storm label.
function Hud.setStorm(payload: { [string]: any })
	local phase = payload.phase
	if phase == "warning" then
		local seconds = tonumber(payload.seconds) or 10
		nextStormAt = os.clock() + seconds
		serverStormIn = seconds
		if bannerFrame and bannerLabel then
			bannerFrame.Visible = true
			bannerLabel.Text = "STORM INBOUND - " .. tostring(seconds) .. "s"
			bannerHideAt = os.clock() + seconds
		end
	elseif phase == "wave" then
		nextStormAt = nil
		if bannerFrame and bannerLabel then
			bannerFrame.Visible = true
			bannerLabel.Text = "THE WAVE IS HERE"
			bannerHideAt = os.clock() + 8
		end
	elseif phase == "clear" then
		if bannerFrame then
			bannerFrame.Visible = false
		end
		nextStormAt = os.clock() + (tonumber(payload.seconds) or 180)
	end
	refreshStorm()
end

-- Starts the client lock countdown (payload.seconds, default 30) when payload.locked is truthy, otherwise clears it.
-- Returns nothing; the lock label itself is redrawn by Hud.tick and Hud.update.
function Hud.setLock(payload: { [string]: any })
	if payload.locked then
		lockUntil = os.clock() + (tonumber(payload.seconds) or 30)
	else
		lockUntil = nil
	end
end

-- Public entry for server alerts; passes data (kind, text, optional color) on to pushAlert.
-- Returns nothing; the alert is dropped if the HUD has not been built.
function Hud.alert(data: { [string]: any })
	pushAlert(data)
end

-- Sets the hint line under the carry panel to text, or clears it when text is nil.
-- Returns nothing; it does nothing if the hint label has not been built.
function Hud.setHint(text: string?)
	if hintLabel then
		hintLabel.Text = text or ""
	end
end

-- Applies viewport scaling once and connects Hud.tick to RenderStepped, disconnecting any earlier ticker first.
-- Returns nil.
function Hud.start()
	updateScaling()
	if ticker then
		ticker:Disconnect()
	end
	ticker = RunService.RenderStepped:Connect(function()
		Hud.tick()
	end)
	return nil
end

return Hud
-- (recorded build witness)
-- (recorded build witness b)

-- (recorded build witness c)
