-- Dock: owns the pier spawn spots, timed restocking of docked brainrot, rare spawn announcements, and the take prompt.
-- Server gameplay is authoritative; the client only renders and sends intents.
--!strict

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(script.Parent:WaitForChild("Config"))
local Cast = require(script.Parent:WaitForChild("Cast"))
local Factory = require(script.Parent:WaitForChild("BrainrotFactory"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local Carry = require(script.Parent:WaitForChild("Carry"))

local RARE_OR_BETTER: { [string]: boolean } = {
	Epic = true,
	Legendary = true,
	Mythic = true,
	["Ultra Rare"] = true,
}

local RARITY_COLOR: { [string]: Color3 } = {
	Epic = Color3.fromRGB(186, 110, 255),
	Legendary = Color3.fromRGB(255, 150, 48),
	Mythic = Color3.fromRGB(230, 48, 48),
	["Ultra Rare"] = Color3.fromRGB(255, 206, 64),
}

local GOLD = Color3.fromRGB(255, 206, 64)

export type Anchors = {
	pierSpawns: { BasePart },
	plotCentres: { BasePart },
	pedestals: { { BasePart } },
	rebirth: BasePart,
	centre: BasePart,
}

type Spot = {
	part: BasePart,
	pier: number,
	index: number,
	model: Model?,
}

local spots: { Spot } = {}
local running = false
local folder: Folder? = nil
local alertRemote: RemoteEvent? = nil

local Dock = {}

-- === rare announcements ===
local function alertEvent(): RemoteEvent?
	if alertRemote then
		return alertRemote
	end
	local net = ReplicatedStorage:FindFirstChild("Net")
	if not net then
		return nil
	end
	alertRemote = net:FindFirstChild("Alert") :: RemoteEvent?
	if not alertRemote then
		local event = Instance.new("RemoteEvent")
		event.Name = "Alert"
		event.Parent = net
		alertRemote = event
	end
	return alertRemote
end

local function announce(model: Model, entry: Cast.Entry)
	alertRemote = alertEvent()
	local remote = alertRemote
	if not remote then
		return
	end
	local color = RARITY_COLOR[entry.rarity] or GOLD
	local isUltra = entry.rarity == "Ultra Rare"
	remote:FireAllClients({
		kind = if isUltra then "rare-ultra" else "rare",
		text = string.format("%s  -  %s", entry.name, entry.rarity),
		color = color,
		rarity = entry.rarity,
		name = entry.name,
		flash = isUltra,
	})
	if model.PrimaryPart then
		remote:FireAllClients({
			kind = "rare-burst",
			position = model.PrimaryPart.Position,
			color = color,
			flash = isUltra,
		})
	end
end

local function flourish(model: Model, entry: Cast.Entry)
	alertEvent()
	local color = RARITY_COLOR[entry.rarity] or GOLD
	local root = model.PrimaryPart
	if not root then
		announce(model, entry)
		return
	end

	local anchorPart = Instance.new("Part")
	anchorPart.Name = "RareFlourish"
	anchorPart.Size = Vector3.new(0.4, 0.4, 0.4)
	anchorPart.Transparency = 1
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	anchorPart.CFrame = CFrame.new(root.Position + Vector3.new(0, 1, 0))
	anchorPart.Parent = folder or workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "RareRise"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.1),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.9, 1.4)
	emitter.Speed = NumberRange.new(14, 24)
	emitter.SpreadAngle = Vector2.new(6, 6)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Rate = 0
	emitter.Parent = anchorPart
	emitter:Emit(70)

	local light = Instance.new("PointLight")
	light.Name = "RareFlash"
	light.Color = color
	light.Brightness = 6
	light.Range = 22
	light.Parent = anchorPart

	Debris:AddItem(anchorPart, 1.8)
	task.delay(0.25, function()
		if light.Parent then
			local tween = game:GetService("TweenService"):Create(light, TweenInfo.new(1.4), { Brightness = 0 })
			tween:Play()
		end
	end)

	announce(model, entry)
end

-- === dock spots ===
local function makePrompt(host: BasePart): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TakePrompt"
	prompt.ActionText = "Take"
	prompt.ObjectText = host.Parent and host.Parent.Name or "Brainrot"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = host
	return prompt
end

-- === dock spots ===
local function layoutSpots(anchors: Anchors)
	table.clear(spots)
	for pierIndex, spawn in anchors.pierSpawns do
		local origin = spawn.Position
		for i = 1, math.ceil(Config.dockSpawnCap / math.max(#anchors.pierSpawns, 1)) + 1 do
			local along = (i - 1) * 8
			local marker = Instance.new("Part")
			marker.Name = "DockSpot"
			marker.Size = Vector3.new(3, 0.2, 3)
			marker.Anchored = true
			marker.CanCollide = false
			marker.Transparency = 1
			marker.CFrame = CFrame.new(origin + Vector3.new(0, 0.2, -along))
			marker.Parent = spawn.Parent
			table.insert(spots, {
				part = marker,
				pier = pierIndex,
				index = i,
				model = nil,
			})
		end
	end
end

-- === public api ===
function Dock.standing(): number
	local n = 0
	for _, spot in spots do
		if spot.model and spot.model.Parent then
			n += 1
		else
			spot.model = nil
		end
	end
	return n
end

function Dock.freeSpot(): Spot?
	for _, spot in spots do
		if spot.model == nil or spot.model.Parent == nil then
			spot.model = nil
			return spot
		end
	end
	return nil
end

function Dock.spawnOne(rng: Random?): Model?
	if Dock.standing() >= Config.dockSpawnCap then
		return nil
	end
	local spot = Dock.freeSpot()
	if not spot or not folder then
		return nil
	end
	local entry = Cast.roll(rng)
	local model = Factory.create(entry, spot.part.Position + Vector3.new(0, 1, 0))
	model.Parent = folder
	Factory.standOn(model, spot.part)
	model:SetAttribute("Docked", true)
	local root = model.PrimaryPart
	if root then
		root.Anchored = true
		makePrompt(root)
	end
	spot.model = model
	if RARE_OR_BETTER[entry.rarity] then
		flourish(model, entry)
	end
	return model
end

function Dock.stock(rng: Random?)
	local guard = 0
	while Dock.standing() < Config.dockSpawnCap and guard < Config.dockSpawnCap do
		guard += 1
		if not Dock.spawnOne(rng) then
			break
		end
	end
end

local function onTake(prompt: ProximityPrompt, player: Player)
	if prompt.Name ~= "TakePrompt" then
		return
	end
	local root = prompt.Parent
	if not (root and root:IsA("BasePart")) then
		return
	end
	local model = root:FindFirstAncestorOfClass("Model")
	if not model or model:GetAttribute("Docked") ~= true then
		return
	end
	local state = PlayerState.get(player)
	if not state then
		return
	end
	if state.carrying ~= nil then
		return
	end
	local id = model:GetAttribute("BrainrotId")
	if typeof(id) ~= "string" then
		return
	end
	local entry = Cast.getById(id)
	if not entry then
		return
	end
	for _, spot in spots do
		if spot.model == model then
			spot.model = nil
		end
	end
	model:SetAttribute("Docked", false)
	prompt:Destroy()
	local attached = Carry.attach(player, PlayerState.slotFromEntry(entry), model)
	if not attached then
		model:SetAttribute("Docked", true)
		if root.Parent then
			makePrompt(root)
		end
	end
end

function Dock.init(anchors: Anchors, parent: Instance?)
	folder = Instance.new("Folder")
	folder.Name = "Docked"
	folder.Parent = parent or workspace
	layoutSpots(anchors)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt.Name == "TakePrompt" then
			onTake(prompt, player)
		end
	end)
end

function Dock.start()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while running do
			local ok, err = pcall(function()
				Dock.stock(nil)
			end)
			if not ok then
				warn("[Dock] spawn failed: " .. tostring(err))
			end
			task.wait(Config.dockSpawnInterval)
		end
	end)
end

function Dock.stop()
	running = false
end

function Dock.spots(): { Spot }
	return spots
end

return Dock
