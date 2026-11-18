-- Steal: owns stealing brainrot from another player's pedestal, including cooldowns, validity checks, and notices.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: Steal.reason, Steal.try, Steal.clear, Steal.init, Steal.bind
-- contract:
--   Owns: per-thief cooldownUntil clock and the "StealPrompt" ProximityPrompts on every pedestal top.
--   Validates, in order: "missing" (no record or no owner), "owner" (thief owns the base), "cooldown", "locked" (Lock.baseLocked or
--   Bases.isLocked), "empty" (owner state missing or slot nil), "carrying" (thief state missing or already carrying; also when Carry.attach fails).
--   Returns: reason -> Reason; try -> (true, "ok") after moving the slot to the thief and notifying both, else (false, reason).
--   Note: try starts the thief's Config.stealCooldown before validating, so a refused attempt also starts the cooldown.
--!strict

local ProximityPromptService = game:GetService("ProximityPromptService")

local Config = require(script.Parent:WaitForChild("Config"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local Bases = require(script.Parent:WaitForChild("Bases"))
local Carry = require(script.Parent:WaitForChild("Carry"))
local Lock = require(script.Parent:WaitForChild("Lock"))
local Pedestal = require(script.Parent:WaitForChild("Pedestal"))
local Storm = require(script.Parent:WaitForChild("Storm"))

local cooldownUntil: { [Player]: number } = {}

-- Steal module table.
-- Owns: the cooldownUntil map (thief -> os.clock() deadline, set by try, cleared by clear) and the
--   "StealPrompt" ProximityPrompt that init parents to every pedestal top in Bases.records().
-- Refuses: "missing" (no base record, no owner, or owner state gone), "owner" (thief owns the base),
--   "cooldown" (cooldownUntil[thief] > clock), "locked" (Lock.baseLocked or Bases.isLocked),
--   "empty" (owner slot nil), "carrying" (thief state missing, already carrying, or Carry.attach failed).
-- Returns: reason -> Reason; try -> (boolean, Reason), (true, "ok") only after the slot moves to the thief;
--   clear, init and bind return nothing; bind routes PromptTriggered on "StealPrompt" into Steal.try.
local Steal = {}

export type Reason = "ok" | "locked" | "empty" | "carrying" | "owner" | "cooldown" | "missing"

-- Checks, without changing state, whether thief may steal slotIndex from base baseIndex at now (or os.clock()).
-- Returns a Reason: "ok" when allowed, else the first failing check ("missing", "owner", "cooldown", "locked", "empty", "carrying").
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

-- Starts the thief's cooldown, validates, then moves the owner's slot and pedestal model onto the thief and notifies both players.
-- Returns (true, "ok") on success, or (false, reason) with the owner's slot and model restored if Carry.attach fails.
function Steal.try(thief: Player, baseIndex: number, slotIndex: number, now: number?): (boolean, Reason)
	local clock = now or os.clock()
	cooldownUntil[thief] = clock + Config.stealCooldown
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
	Storm.notify(owner, "stolen", tostring(thief.Name) .. " stole " .. tostring(slot.name) .. " from your base!", Color3.fromRGB(255, 110, 110))
	Storm.notify(thief, "stole", "You stole " .. tostring(slot.name) .. " from " .. tostring(owner.Name) .. "'s base!", Color3.fromRGB(255, 190, 90))
	return true, "ok"
end

-- Forgets the player's steal cooldown (e.g. when they leave).
-- Returns nothing.
function Steal.clear(player: Player)
	cooldownUntil[player] = nil
end

-- Creates a "StealPrompt" ProximityPrompt (hold Config.stealHold, range 10, no line of sight) on every pedestal top of every base.
-- Returns nothing.
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

-- Finds which base and pedestal slot a prompt belongs to by matching its parent BasePart against every base's pedestals.
-- Returns (baseIndex, slotIndex), or (nil, nil) if the parent is not a BasePart or matches no pedestal.
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

-- Connects ProximityPromptService.PromptTriggered so a triggered "StealPrompt" resolves its slot and calls Steal.try for the player.
-- Returns nothing.
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
