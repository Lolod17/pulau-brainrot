-- Hud: owns the client HUD: cash and income readouts, carry panel, status lines, storm banner, and alert cards.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: Hud.build, Hud.update, Hud.tick, Hud.basePosition, Hud.setStorm, Hud.setLock, Hud.alert, Hud.setHint, Hud.start
--!strict

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

local function clock(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local minutes = total // 60
	local secs = total % 60
	return string.format("%d:%02d", minutes, secs)
end

-- === label helper ===
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
	cashPlate.Size = UDim2.new(0, 620, 0, 84)
	cashPlate.Position = UDim2.new(0.5, -310, 1, -196)
	cashPlate.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
	cashPlate.BackgroundTransparency = 0.35
	cashPlate.BorderSizePixel = 0
	cashPlate.Parent = screen
	local plateCorner = Instance.new("UICorner")
	plateCorner.CornerRadius = UDim.new(0, 14)
	plateCorner.Parent = cashPlate

	cashLabel = makeLabel(screen, "Cash", UDim2.new(0, 600, 0, 56), UDim2.new(0.5, -300, 1, -192), 56, Color3.fromRGB(120, 255, 150))
	cashLabel.Font = Enum.Font.GothamBlack
	cashLabel.TextStrokeTransparency = 0.35
	incomeLabel = makeLabel(screen, "Income", UDim2.new(0, 600, 0, 30), UDim2.new(0.5, -300, 1, -132), 24, Color3.fromRGB(110, 240, 140))
	incomeLabel.Font = Enum.Font.GothamBold

	local panel = Instance.new("Frame")
	panel.Name = "Carrying"
	panel.Size = UDim2.new(0, 380, 0, 66)
	panel.Position = UDim2.new(0.5, -190, 1, -268)
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
	info.Size = UDim2.new(0, 360, 0, 84)
	info.Position = UDim2.new(1, -376, 1, -286)
	info.BackgroundTransparency = 1
	info.Parent = screen

	rebirthLabel = makeLabel(info, "Rebirth", UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 0), 20, Color3.fromRGB(255, 210, 120))
	rebirthLabel.TextXAlignment = Enum.TextXAlignment.Right

	stormLabel = makeLabel(info, "Storm", UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 28), 22, Color3.fromRGB(160, 200, 255))
	stormLabel.TextXAlignment = Enum.TextXAlignment.Right

	lockLabel = makeLabel(info, "Lock", UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 56), 20, Color3.fromRGB(255, 170, 170))
	lockLabel.TextXAlignment = Enum.TextXAlignment.Right

	hintLabel = makeLabel(screen, "Hint", UDim2.new(0, 600, 0, 28), UDim2.new(0.5, -300, 1, -230), 20, Color3.fromRGB(236, 240, 250))

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
				lockLabel.Text = "Base locked: " .. tostring(remain) .. "s"
			else
				lockLabel.Text = "Base unlocked"
			end
		else
			lockLabel.Text = "Base unlocked"
		end
	end
end

-- === public api ===
local ticker: RBXScriptConnection? = nil

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

function Hud.basePosition(): Vector3?
	return basePosition
end

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

function Hud.setLock(payload: { [string]: any })
	if payload.locked then
		lockUntil = os.clock() + (tonumber(payload.seconds) or 30)
	else
		lockUntil = nil
	end
end

function Hud.alert(data: { [string]: any })
	pushAlert(data)
end

function Hud.setHint(text: string?)
	if hintLabel then
		hintLabel.Text = text or ""
	end
end

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
