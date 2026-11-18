--!strict

local ProximityPromptService = game:GetService("ProximityPromptService")

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
}

local visuals: { Visual } = {}
local ticking = false

local Pedestal = {}

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
		refresh(visual)
		return
	end
	local entry = Cast.getById(slot.id)
	if not entry then
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
