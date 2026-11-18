--!strict

local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent:WaitForChild("Config"))
local Cast = require(script.Parent:WaitForChild("Cast"))
local Factory = require(script.Parent:WaitForChild("BrainrotFactory"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local Carry = require(script.Parent:WaitForChild("Carry"))
local Bases = require(script.Parent:WaitForChild("Bases"))

type Slot = PlayerState.Slot

type Visual = {
	baseIndex: number,
	slotIndex: number,
	top: BasePart,
	model: Model?,
	placePrompt: ProximityPrompt,
	sellPrompt: ProximityPrompt,
	showcase: Model?,
}

local RARITY_TIER: { [string]: number } = {
	Rare = 1,
	Epic = 2,
	Legendary = 3,
	Mythic = 4,
	["Ultra Rare"] = 5,
}

local RARITY_COLOR: { [string]: Color3 } = {
	Rare = Color3.fromRGB(80, 140, 255),
	Epic = Color3.fromRGB(186, 110, 255),
	Legendary = Color3.fromRGB(255, 150, 48),
	Mythic = Color3.fromRGB(230, 48, 48),
	["Ultra Rare"] = Color3.fromRGB(255, 206, 64),
}

local GOLD = Color3.fromRGB(255, 206, 64)

type Ring = {
	part: BasePart,
	spin: number,
}

local showcases: { Model } = {}
local rings: { [Model]: { Ring } } = {}
local showcaseTicker: RBXScriptConnection? = nil
local showcaseClock = 0

local visuals: { Visual } = {}
local ticking = false

local Pedestal = {}

local function startShowcaseTicker()
	if showcaseTicker then
		return
	end
	showcaseTicker = RunService.Heartbeat:Connect(function(dt)
		if #showcases == 0 then
			return
		end
		showcaseClock += dt
		for i = #showcases, 1, -1 do
			local effect = showcases[i]
			if not effect.Parent then
				table.remove(showcases, i)
				continue
			end
			local list = rings[effect]
			if list then
				for _, ring in list do
					if ring.part.Parent then
						local base = ring.part:GetAttribute("BasePosition")
						if typeof(base) == "Vector3" then
							ring.part.CFrame = CFrame.new(base) * CFrame.Angles(0, showcaseClock * ring.spin, 0)
						end
					end
				end
			end
		end
	end)
end

local function makeRing(effect: Model, top: BasePart, radius: number, height: number, color: Color3, spin: number)
	local ring = Instance.new("Part")
	ring.Name = "ShowcaseRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.06, radius * 2, radius * 2)
	ring.Color = color
	ring.Material = Enum.Material.SmoothPlastic
	ring.Transparency = 0.65
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	local base = top.Position + Vector3.new(0, height, 0)
	ring.CFrame = CFrame.new(base) * CFrame.Angles(0, 0, math.rad(90))
	ring:SetAttribute("BasePosition", base)
	ring.Parent = effect
	return { part = ring, spin = spin }
end

local EMITTER_BUDGET = 1

local function makeEmitter(parent: BasePart, name: string, color: Color3, rate: number, rising: boolean): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.2
	emitter.LightInfluence = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.8, 1.2)
	emitter.Rate = rate
	if rising then
		emitter.Speed = NumberRange.new(2.5, 4.5)
		emitter.SpreadAngle = Vector2.new(8, 8)
		emitter.EmissionDirection = Enum.NormalId.Top
	else
		emitter.Speed = NumberRange.new(0.4, 1.2)
		emitter.SpreadAngle = Vector2.new(30, 30)
		emitter.EmissionDirection = Enum.NormalId.Top
	end
	emitter.Parent = parent
	return emitter
end

local function clearShowcase(visual: Visual)
	if not visual.showcase then
		return
	end
	rings[visual.showcase] = nil
	for i = #showcases, 1, -1 do
		if showcases[i] == visual.showcase then
			table.remove(showcases, i)
		end
	end
	visual.showcase:Destroy()
	visual.showcase = nil
end

local function buildShowcase(visual: Visual, entry: Cast.Entry)
	clearShowcase(visual)
	local tier = RARITY_TIER[entry.rarity]
	if not tier then
		return
	end
	local color = RARITY_COLOR[entry.rarity] or entry.aura
	local effect = Instance.new("Model")
	effect.Name = "Showcase"
	effect.Parent = visual.top.Parent
	visual.showcase = effect
	local list: { Ring } = {}
	table.insert(list, makeRing(effect, visual.top, 4.2, 0.4, color, 0.8))
	if tier >= 2 then
		table.insert(list, makeRing(effect, visual.top, 3.2, 0.9, color, -1.2))
	end
	rings[effect] = list

	local anchor = Instance.new("Part")
	anchor.Name = "ShowcaseAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(visual.top.Position + Vector3.new(0, 1, 0))
	anchor.Parent = effect

	local emitterCount = 0
	if tier >= 3 and emitterCount < EMITTER_BUDGET then
		makeEmitter(anchor, "RisingMotes", color, 12, true)
		emitterCount += 1
	end
	if tier >= 5 and emitterCount < EMITTER_BUDGET then
		makeEmitter(anchor, "GoldSparkle", GOLD, 14, true)
		emitterCount += 1
	end

	if tier >= 5 then
		local shaft = Instance.new("Part")
		shaft.Name = "LightShaft"
		shaft.Shape = Enum.PartType.Cylinder
		shaft.Size = Vector3.new(9, 2.2, 2.2)
		shaft.Color = GOLD
		shaft.Material = Enum.Material.SmoothPlastic
		shaft.Transparency = 0.8
		shaft.Anchored = true
		shaft.CanCollide = false
		shaft.CanQuery = false
		shaft.CanTouch = false
		shaft.CastShadow = false
		shaft.CFrame = CFrame.new(visual.top.Position + Vector3.new(0, 5.5, 0))
		shaft.Parent = effect
	end

	table.insert(showcases, effect)
	startShowcaseTicker()
end

local function promptOn(host: BasePart, name: string, action: string, objectText: string, hold: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = objectText
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = host
	return prompt
end

local function refresh(visual: Visual)
	local record = Bases.getByIndex(visual.baseIndex)
	local owner = record and record.owner
	local state = owner and PlayerState.get(owner)
	local slot = state and state.slots[visual.slotIndex]
	visual.sellPrompt.Enabled = slot ~= nil
	visual.placePrompt.Enabled = true
	if slot then
		visual.sellPrompt.ObjectText = slot.name
		visual.placePrompt.Enabled = false
	else
		visual.sellPrompt.ObjectText = "Empty"
	end
end

local function showSlot(visual: Visual, slot: Slot?)
	if visual.model then
		Factory.remove(visual.model)
		visual.model = nil
	end
	if not slot then
		clearShowcase(visual)
		refresh(visual)
		return
	end
	local entry = Cast.getById(slot.id)
	if not entry then
		clearShowcase(visual)
		refresh(visual)
		return
	end
	local model = Factory.create(entry, visual.top.Position + Vector3.new(0, 2, 0))
	model.Parent = visual.top.Parent
	Factory.standOn(model, visual.top)
	local root = model.PrimaryPart
	if root then
		root.Anchored = true
	end
	model:SetAttribute("Placed", true)
	model:SetAttribute("BaseIndex", visual.baseIndex)
	model:SetAttribute("SlotIndex", visual.slotIndex)
	visual.model = model
	buildShowcase(visual, entry)
	refresh(visual)
end

function Pedestal.init()
	table.clear(visuals)
	for _, record in Bases.records() do
		for slotIndex, top in record.pedestals do
			local visual: Visual = {
				baseIndex = record.index,
				slotIndex = slotIndex,
				top = top,
				model = nil,
				placePrompt = promptOn(top, "PlacePrompt", "Place", "Pedestal", 0),
				sellPrompt = promptOn(top, "SellPrompt", "Sell", "Empty", 0.4),
				showcase = nil,
			}
			visual.sellPrompt.Enabled = false
			table.insert(visuals, visual)
		end
	end
end

function Pedestal.visual(baseIndex: number, slotIndex: number): Visual?
	for _, visual in visuals do
		if visual.baseIndex == baseIndex and visual.slotIndex == slotIndex then
			return visual
		end
	end
	return nil
end

function Pedestal.sync(player: Player)
	local state = PlayerState.get(player)
	if not state or not state.baseIndex then
		return
	end
	for slotIndex = 1, Config.slotCount do
		local visual = Pedestal.visual(state.baseIndex, slotIndex)
		if visual then
			showSlot(visual, state.slots[slotIndex])
		end
	end
end

function Pedestal.clearBase(baseIndex: number)
	for slotIndex = 1, Config.slotCount do
		local visual = Pedestal.visual(baseIndex, slotIndex)
		if visual then
			showSlot(visual, nil)
		end
	end
end

local function place(player: Player, visual: Visual): boolean
	local record = Bases.getByIndex(visual.baseIndex)
	if not record or record.owner ~= player then
		return false
	end
	local state = PlayerState.get(player)
	if not state or not state.carrying then
		return false
	end
	if state.slots[visual.slotIndex] ~= nil then
		return false
	end
	local slot = state.carrying
	local model = Carry.takeModel(player)
	PlayerState.setSlot(player, visual.slotIndex, slot)
	if model then
		Factory.remove(model)
	end
	showSlot(visual, slot)
	return true
end

local function sell(player: Player, visual: Visual): number
	local record = Bases.getByIndex(visual.baseIndex)
	if not record or record.owner ~= player then
		return 0
	end
	local state = PlayerState.get(player)
	if not state then
		return 0
	end
	local slot = state.slots[visual.slotIndex]
	if not slot then
		return 0
	end
	local payout = math.floor(slot.price * Config.sellFraction)
	PlayerState.setSlot(player, visual.slotIndex, nil)
	PlayerState.addCash(player, payout)
	showSlot(visual, nil)
	return payout
end

function Pedestal.tryPlace(player: Player, baseIndex: number, slotIndex: number): boolean
	local visual = Pedestal.visual(baseIndex, slotIndex)
	if not visual then
		return false
	end
	return place(player, visual)
end

function Pedestal.trySell(player: Player, baseIndex: number, slotIndex: number): number
	local visual = Pedestal.visual(baseIndex, slotIndex)
	if not visual then
		return 0
	end
	return sell(player, visual)
end

function Pedestal.tickIncome()
	local Players = game:GetService("Players")
	for _, player in Players:GetPlayers() do
		local state = PlayerState.get(player)
		if state then
			local gain = PlayerState.placedIncome(player) * PlayerState.incomeMultiplier(player) * Config.incomeTickRate
			if gain > 0 then
				PlayerState.addCash(player, gain)
			end
		end
	end
end

function Pedestal.bind()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local top = prompt.Parent
		if not (top and top:IsA("BasePart")) then
			return
		end
		local visual: Visual? = nil
		for _, candidate in visuals do
			if candidate.top == top then
				visual = candidate
				break
			end
		end
		if not visual then
			return
		end
		if prompt.Name == "PlacePrompt" then
			place(player, visual)
		elseif prompt.Name == "SellPrompt" then
			sell(player, visual)
		end
	end)
end

function Pedestal.start()
	if ticking then
		return
	end
	ticking = true
	task.spawn(function()
		while ticking do
			local ok, err = pcall(Pedestal.tickIncome)
			if not ok then
				warn("[Pedestal] income tick failed: " .. tostring(err))
			end
			task.wait(Config.incomeTickRate)
		end
	end)
end

function Pedestal.stop()
	ticking = false
end

return Pedestal
