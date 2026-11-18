--!strict

local ProximityPromptService = game:GetService("ProximityPromptService")

local Config = require(script.Parent:WaitForChild("Config"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local Bases = require(script.Parent:WaitForChild("Bases"))
local Carry = require(script.Parent:WaitForChild("Carry"))
local Lock = require(script.Parent:WaitForChild("Lock"))
local Pedestal = require(script.Parent:WaitForChild("Pedestal"))

local cooldownUntil: { [Player]: number } = {}

local Steal = {}

export type Reason = "ok" | "locked" | "empty" | "carrying" | "owner" | "cooldown" | "missing"

function Steal.reason(thief: Player, baseIndex: number, slotIndex: number, now: number?): Reason
	local record = Bases.getByIndex(baseIndex)
	if not record or not record.owner then
		return "missing"
	end
	if record.owner == thief then
		return "owner"
	end
	local clock = now or os.clock()
	if (cooldownUntil[thief] or 0) > clock then
		return "cooldown"
	end
	if Lock.baseLocked(baseIndex, clock) or Bases.isLocked(record, clock) then
		return "locked"
	end
	local ownerState = PlayerState.get(record.owner)
	if not ownerState or ownerState.slots[slotIndex] == nil then
		return "empty"
	end
	local thiefState = PlayerState.get(thief)
	if not thiefState or thiefState.carrying ~= nil then
		return "carrying"
	end
	return "ok"
end

function Steal.try(thief: Player, baseIndex: number, slotIndex: number, now: number?): (boolean, Reason)
	local why = Steal.reason(thief, baseIndex, slotIndex, now)
	if why ~= "ok" then
		return false, why
	end
	local record = Bases.getByIndex(baseIndex)
	if not record or not record.owner then
		return false, "missing"
	end
	local owner = record.owner
	local ownerState = PlayerState.get(owner)
	if not ownerState then
		return false, "missing"
	end
	local slot = ownerState.slots[slotIndex]
	if not slot then
		return false, "empty"
	end
	local thiefState = PlayerState.get(thief)
	if not thiefState or thiefState.carrying ~= nil then
		return false, "carrying"
	end
	PlayerState.setSlot(owner, slotIndex, nil)
	local visual = Pedestal.visual(baseIndex, slotIndex)
	if visual and visual.model then
		local model = visual.model
		visual.model = nil
		local attached = Carry.attach(thief, slot, model)
		if not attached then
			PlayerState.setSlot(owner, slotIndex, slot)
			visual.model = model
			return false, "carrying"
		end
	else
		local attached = Carry.attach(thief, slot, nil)
		if not attached then
			PlayerState.setSlot(owner, slotIndex, slot)
			return false, "carrying"
		end
	end
	if visual then
		visual.sellPrompt.Enabled = false
		visual.placePrompt.Enabled = true
		visual.sellPrompt.ObjectText = "Empty"
	end
	cooldownUntil[thief] = (now or os.clock()) + Config.stealCooldown
	return true, "ok"
end

function Steal.clear(player: Player)
	cooldownUntil[player] = nil
end

function Steal.init()
	for _, record in Bases.records() do
		for slotIndex, top in record.pedestals do
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "StealPrompt"
			prompt.ActionText = "Steal"
			prompt.ObjectText = "Brainrot"
			prompt.HoldDuration = Config.stealHold
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Parent = top
		end
	end
end

local function slotOf(prompt: ProximityPrompt): (number?, number?)
	local top = prompt.Parent
	if not (top and top:IsA("BasePart")) then
		return nil, nil
	end
	for _, record in Bases.records() do
		for slotIndex, pedestal in record.pedestals do
			if pedestal == top then
				return record.index, slotIndex
			end
		end
	end
	return nil, nil
end

function Steal.bind()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt.Name ~= "StealPrompt" then
			return
		end
		local baseIndex, slotIndex = slotOf(prompt)
		if not baseIndex or not slotIndex then
			return
		end
		Steal.try(player, baseIndex, slotIndex)
	end)
end

return Steal
