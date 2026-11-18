--!strict

local ProximityPromptService = game:GetService("ProximityPromptService")

local Config = require(script.Parent:WaitForChild("Config"))
local Cast = require(script.Parent:WaitForChild("Cast"))
local Factory = require(script.Parent:WaitForChild("BrainrotFactory"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local Carry = require(script.Parent:WaitForChild("Carry"))

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

local Dock = {}

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
