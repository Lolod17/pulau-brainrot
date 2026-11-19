-- Dock: owns the pier spawn spots, timed restocking of docked brainrot, rare spawn announcements, and the take prompt.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: Dock.standing, Dock.freeSpot, Dock.spawnOne, Dock.stock, Dock.init, Dock.start, Dock.stop, Dock.spots
-- contract
-- Owns: the pier spots and the docked brainrot on them, restocked up to Config.dockSpawnCap every Config.dockSpawnInterval seconds.
-- Refuses: spawning past the cap or without a free spot; refuses a take when the player already carries something or the model is not docked.
-- Never: spawns more than the cap per restock pass, hands out an unknown brainrot id, or loses a docked model when Carry.attach fails.
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
	Common = Color3.fromRGB(198, 204, 214),
	Uncommon = Color3.fromRGB(64, 200, 140),
	Rare = Color3.fromRGB(64, 150, 255),
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

-- === module table: Dock ===
-- Owns: the `spots` list (one invisible DockSpot marker per position along each pier, with its docked Model),
--   the "Docked" folder, the `running` restock loop flag, the cached Net.Alert RemoteEvent, and every
--   "TakePrompt" ProximityPrompt it puts on a docked brainrot's root part.
-- Refuses: Dock.spawnOne when Dock.standing() >= Config.dockSpawnCap, when no spot is free, or before Dock.init
--   has created the folder; Dock.start when the loop is already running; a take (onTake) when the prompt is not
--   "TakePrompt", its parent is not a BasePart, the model is not Docked, the player has no PlayerState, the
--   player is already carrying something, or the BrainrotId attribute is not a string or not known to Cast.getById.
-- Returns: the Dock table with standing (number), freeSpot (Spot?), spawnOne (Model?), stock, init, start,
--   stop (nothing) and spots (the live spots table, not a copy).
local Dock = {}

-- === rare announcements ===
-- Finds or creates the Net.Alert remote and caches it.
-- Returns: the Alert RemoteEvent, or nil if the Net folder is missing.
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

-- Tells every client about a rare spawn, plus a burst at its position when it has a root.
-- Returns: nothing.
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

-- Plays a short particle and light flourish over a rare spawn, then announces it.
-- Returns: nothing.
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
-- Adds a floating name and rarity plate above a docked brainrot so players can read the tier from the pier.
-- Returns: the new BillboardGui.
local function makeTierLabel(host: BasePart, entry: Cast.Entry): BillboardGui
	local accent = RARITY_COLOR[entry.rarity] or Color3.fromRGB(198, 204, 214)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TierLabel"
	billboard.Size = UDim2.new(0, 108, 0, 34)
	local stagger = (math.floor(math.abs(host.Position.X) * 3) % 3) * 1.4
	billboard.StudsOffsetWorldSpace = Vector3.new(0, (entry.height or 4) + 2.0 + stagger, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 78
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Adornee = host
	billboard.Parent = host

	local plate = Instance.new("Frame")
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
	plate.BackgroundTransparency = 0.22
	plate.BorderSizePixel = 0
	plate.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = plate
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = 1.6
	stroke.Transparency = 0.15
	stroke.Parent = plate

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -8, 0, 20)
	title.Position = UDim2.new(0, 4, 0, 2)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = false
	title.TextSize = 15
	title.TextColor3 = Color3.fromRGB(244, 246, 252)
	title.TextStrokeTransparency = 0.4
	title.Text = entry.name
	title.Parent = plate

	local tier = Instance.new("TextLabel")
	tier.Size = UDim2.new(1, -8, 0, 16)
	tier.Position = UDim2.new(0, 4, 0, 21)
	tier.BackgroundTransparency = 1
	tier.Font = Enum.Font.GothamBold
	tier.TextSize = 13
	tier.TextColor3 = accent
	tier.TextStrokeTransparency = 0.5
	tier.Text = string.upper(entry.rarity)
	tier.Parent = plate

	return billboard
end

-- Adds an instant "Take" prompt to a docked brainrot's root part.
-- Returns: the new ProximityPrompt.
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
-- Rebuilds the spot list with invisible markers spaced 8 studs apart along each pier.
-- Returns: nothing.
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
-- Counts docked brainrot still in the world, clearing spots whose model is gone.
-- Returns: the number of occupied spots.
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

-- Finds the first spot with no live model, clearing its stale reference.
-- Returns: that Spot, or nil if every spot is taken.
function Dock.freeSpot(): Spot?
	for _, spot in spots do
		if spot.model == nil or spot.model.Parent == nil then
			spot.model = nil
			return spot
		end
	end
	return nil
end

-- Rolls and docks one brainrot on a free spot with a take prompt, flourishing rare ones.
-- Returns: the new Model, or nil if at the cap, no spot is free, or not initialised.
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
		makeTierLabel(root, entry)
	end
	spot.model = model
	if RARE_OR_BETTER[entry.rarity] then
		flourish(model, entry)
	end
	return model
end

-- Spawns brainrot until the dock reaches Config.dockSpawnCap, at most that many attempts.
-- Returns: nothing.
function Dock.stock(rng: Random?)
	local guard = 0
	while Dock.standing() < Config.dockSpawnCap and guard < Config.dockSpawnCap do
		guard += 1
		if not Dock.spawnOne(rng) then
			break
		end
	end
end

-- Handles a take: refuses if the player already carries something, else attaches the brainrot and restores the dock on failure.
-- Returns: nothing.
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
	local slot = PlayerState.slotFromEntry(entry)
	local attached = Carry.attach(player, slot, nil)
	if not attached then
		model:SetAttribute("Docked", true)
		for _, spot in spots do
			if spot.part == root.Parent then
				spot.model = model
				break
			end
		end
		if root.Parent then
			makePrompt(root)
		end
		return
	end
	if model.Parent and model ~= Carry.modelOf(player) then
		Factory.remove(model)
	end
end

-- Creates the Docked folder, lays out the pier spots and connects take prompts.
-- Returns: nothing.
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

-- Starts the restock loop, running Dock.stock every Config.dockSpawnInterval seconds (once only).
-- Returns: nothing.
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

-- Signals the restock loop to stop after its current wait.
-- Returns: nothing.
function Dock.stop()
	running = false
end

-- Exposes the live spot list.
-- Returns: the spots table itself (not a copy).
function Dock.spots(): { Spot }
	return spots
end

return Dock
