-- Fx: owns client-side visual feedback: money bursts and floating gains, rare cards, storm flashes, and screen shake.
-- Server gameplay is authoritative; the client only renders and sends intents.
--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Fx = {}

local player = Players.LocalPlayer
local flash: Frame? = nil
local shake = 0
local renderConn: any = nil
local baseCFrame: CFrame? = nil

local AURA_DEFAULT = Color3.fromRGB(255, 190, 90)
local WAVE_BLUE = Color3.fromRGB(110, 180, 255)
local GOLD = Color3.fromRGB(255, 210, 70)

local lastGainShownAt: { [Player]: number } = {}
local billboards: { [Player]: BillboardGui } = {}
local rareCards: { Frame } = {}
local MAX_RARE_CARDS = 2

-- === screen flash ===
local function camera(): Camera?
	local current = workspace.CurrentCamera
	if current then
		return current
	end
	return nil
end

-- === screen flash ===
local function makeFlash()
	local container = player:FindFirstChild("PlayerGui")
	if not container then
		return nil
	end
	local screen = container:FindFirstChild("PulauFx") :: ScreenGui?
	if not screen then
		screen = Instance.new("ScreenGui")
		screen.Name = "PulauFx"
		screen.ResetOnSpawn = false
		screen.IgnoreGuiInset = true
		screen.DisplayOrder = 50
		screen.Parent = container
	end
	local frame = screen:FindFirstChild("Flash") :: Frame?
	if not frame then
		local built = Instance.new("Frame")
		built.Name = "Flash"
		built.Size = UDim2.fromScale(1, 1)
		built.BackgroundColor3 = WAVE_BLUE
		built.BackgroundTransparency = 1
		built.BorderSizePixel = 0
		built.ZIndex = 10
		built.Parent = screen
		frame = built
	end
	flash = frame
	return frame
end

local function effectsFolder(): Instance
	local existing = workspace:FindFirstChild("ClientFx")
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientFx"
	folder.Parent = workspace
	return folder
end

-- === world effects ===
local function burst(position: Vector3, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Name = "FxBurst"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = effectsFolder()

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.3
	emitter.LightInfluence = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(10, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Parent = anchor

	emitter:Emit(14)
	task.delay(1.6, function()
		anchor:Destroy()
	end)
end

-- === money feedback ===
local function billboardFor(targetPlayer: Player): BillboardGui?
	local character = targetPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local existing = billboards[targetPlayer]
	if existing and existing.Parent then
		return existing
	end
	local holder = Instance.new("Part")
	holder.Name = "MoneyHolder"
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CFrame = CFrame.new(root.Position + Vector3.new(0, 4, 0))
	holder.Parent = effectsFolder()
	local gui = Instance.new("BillboardGui")
	gui.Name = "MoneyFloat"
	gui.Size = UDim2.fromOffset(160, 40)
	gui.StudsOffset = Vector3.new(0, 0, 0)
	gui.AlwaysOnTop = true
	gui.Parent = holder
	billboards[targetPlayer] = gui
	return gui
end

local function floatGain(targetPlayer: Player, amount: number)
	local now = os.clock()
	if (lastGainShownAt[targetPlayer] or 0) + 1 > now then
		return
	end
	lastGainShownAt[targetPlayer] = now
	local gui = billboardFor(targetPlayer)
	if not gui then
		return
	end
	local label = Instance.new("TextLabel")
	label.Name = "Gain"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 26
	label.TextColor3 = GOLD
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(60, 40, 0)
	label.Text = "+$" .. tostring(math.floor(amount))
	label.Position = UDim2.fromOffset(0, 0)
	label.Parent = gui
	local rise = TweenService:Create(label, TweenInfo.new(1.4), {
		Position = UDim2.fromOffset(0, -40),
		TextTransparency = 1,
	})
	local fade = TweenService:Create(label, TweenInfo.new(0.6), { TextStrokeTransparency = 1 })
	rise:Play()
	fade:Play()
	task.delay(2, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

-- === camera shake ===
local function screenShake(strength: number, duration: number)
	shake = math.max(shake, strength)
	task.delay(duration, function()
		shake = math.max(0, shake - strength)
	end)
end

-- === public api ===
function Fx.build()
	makeFlash()
	if not renderConn then
		renderConn = RunService.RenderStepped:Connect(function()
			local cam = camera()
			if not cam then
				return
			end
			if shake > 0 then
				if not baseCFrame then
					baseCFrame = cam.CFrame
				end
				local t = os.clock() * 30
				local jitter = Vector3.new(
					math.noise(t, 0) * shake * 0.04,
					math.noise(0, t) * shake * 0.04,
					0
				)
				cam.CFrame = baseCFrame * CFrame.new(jitter)
			elseif baseCFrame then
				cam.CFrame = baseCFrame
				baseCFrame = nil
			end
		end)
	end
	return Fx
end

function Fx.money(gain: number, basePosition: Vector3?)
	if typeof(gain) ~= "number" or gain <= 0 then
		return
	end
	local spot = basePosition
	if not spot then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			spot = root.Position + Vector3.new(0, 2, 0)
		end
	end
	if spot then
		burst(spot, GOLD)
	end
	floatGain(player, gain)
end

-- === rare cards ===
local function goldFlash()
	local frame = makeFlash()
	if not frame then
		return
	end
	frame.BackgroundColor3 = GOLD
	frame.BackgroundTransparency = 0.1
	local tween = TweenService:Create(frame, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
	tween:Play()
	task.delay(0.7, function()
		if frame.Parent then
			frame.BackgroundColor3 = WAVE_BLUE
		end
	end)
end

local function pruneRareCards()
	local kept: { Frame } = {}
	for _, card in rareCards do
		if card.Parent then
			table.insert(kept, card)
		end
	end
	rareCards = kept
	while #rareCards >= MAX_RARE_CARDS do
		local oldest = table.remove(rareCards, 1)
		if oldest and oldest.Parent then
			oldest:Destroy()
		end
	end
end

local function rareCard(data: { [string]: any })
	local container = player:FindFirstChild("PlayerGui")
	if not container then
		return
	end
	local screen = container:FindFirstChild("PulauFx") :: ScreenGui?
	if not screen then
		screen = makeFlash() and (container:FindFirstChild("PulauFx") :: ScreenGui?)
	end
	if not screen then
		return
	end
	pruneRareCards()
	local isUltra = data.rarity == "Ultra Rare" or data.flash == true
	local color = data.color
	if typeof(color) ~= "Color3" then
		color = GOLD
	end
	local card = Instance.new("TextLabel")
	card.Name = "RareCard"
	card.Size = UDim2.new(0, 460, 0, if isUltra then 78 else 62)
	card.Position = UDim2.new(0.5, -230, 0, 26 + #rareCards * 74)
	card.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
	card.BackgroundTransparency = 0.12
	card.BorderSizePixel = 0
	card.Font = if isUltra then Enum.Font.GothamBlack else Enum.Font.GothamBold
	card.TextSize = if isUltra then 28 else 22
	card.TextColor3 = color
	card.Text = if isUltra
		then "*** ULTRA RARE: " .. tostring(data.name or data.text or "") .. " ***"
		else "RARE SPAWN: " .. tostring(data.name or data.text or "")
	card.TextStrokeTransparency = 0.4
	card.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	card.TextWrapped = true
	card.Parent = screen
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card
	table.insert(rareCards, card)
	if isUltra then
		goldFlash()
		screenShake(10, 0.6)
	end
	task.delay(1.8, function()
		if card.Parent then
			local tween = TweenService:Create(card, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			card:Destroy()
		end
	end)
end

-- === public api ===
function Fx.event(data: { [string]: any })
	local kind = data.kind
	if kind == "cash" then
		local spot = data.position
		if typeof(spot) ~= "Vector3" then
			spot = nil
		end
		Fx.money(tonumber(data.amount) or 0, spot)
		return
	end
	if kind == "rare" or kind == "rare-ultra" then
		rareCard(data)
		return
	end
	if kind == "wave" or kind == "storm" then
		local frame = makeFlash()
		if frame then
			frame.BackgroundTransparency = 0.7
			local tween = TweenService:Create(frame, TweenInfo.new(0.8), { BackgroundTransparency = 1 })
			tween:Play()
		end
		screenShake(8, 0.6)
	end
	local position = data.position
	if typeof(position) == "Vector3" then
		local color = data.color
		if typeof(color) ~= "Color3" then
			color = AURA_DEFAULT
		end
		burst(position, color)
	end
	if kind == "character" then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			burst(root.Position, (data.color :: Color3?) or AURA_DEFAULT)
		end
	end
end

return Fx
