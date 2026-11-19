-- Rebirth: owns rebirth costs, the rebirth prompt and sign, and the reset that spends cash for an income multiplier.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: Rebirth.cost, Rebirth.costFor, Rebirth.multiplier, Rebirth.try, Rebirth.init, Rebirth.bind
-- contract:
--   Cost: Config.rebirthBaseCost * (Config.rebirthGrowth ^ rebirths), i.e. 100000 * 2^rebirths. Multiplier: 1 + Config.rebirthIncomeBonus * rebirths, i.e. 1 + 0.5 * rebirths.
--   try validates the player has state, cash >= cost and PlayerState.spendCash succeeds; returns false otherwise.
--   On success it clears the carry, slots and base pedestals, adds one rebirth, sets cash to Config.cashAfterRebirth, notifies, and returns true.
--   bind only calls try for a "RebirthPrompt" trigger by a player who holds a base.
-- module block:
--   Owns: the rebirth cost curve, the income multiplier curve, the "RebirthPrompt" ProximityPrompt and "RebirthSign"
--     BillboardGui on the plaza spot, and the rebirth reset (carry, slots, base pedestals, rebirth count, cash).
--   Refuses: a rebirth for a player with no PlayerState, cash below the cost, or a failed PlayerState.spendCash;
--     prompt triggers whose prompt is not named "RebirthPrompt"; triggers from a player with no Bases record.
--   Returns: the Rebirth table; cost/costFor/multiplier return numbers, try returns a boolean, init and bind return nothing.
--!strict

local ProximityPromptService = game:GetService("ProximityPromptService")

local Config = require(script.Parent:WaitForChild("Config"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local Bases = require(script.Parent:WaitForChild("Bases"))
local Pedestal = require(script.Parent:WaitForChild("Pedestal"))
local Carry = require(script.Parent:WaitForChild("Carry"))
local Storm = require(script.Parent:WaitForChild("Storm"))

local Rebirth = {}

-- Computes the cash price of the next rebirth for a given rebirth count from Config base cost and growth.
-- Returns a number: Config.rebirthBaseCost * Config.rebirthGrowth ^ rebirths.
function Rebirth.cost(rebirths: number): number
	return Config.rebirthBaseCost * (Config.rebirthGrowth ^ rebirths)
end

-- Looks up the player's current rebirth count (0 when they have no state) and prices their next rebirth.
-- Returns a number: Rebirth.cost of that rebirth count.
function Rebirth.costFor(player: Player): number
	local state = PlayerState.get(player)
	local rebirths = if state then state.rebirths else 0
	return Rebirth.cost(rebirths)
end

-- Computes the income multiplier granted by a given rebirth count using Config.rebirthIncomeBonus.
-- Returns a number: 1 + Config.rebirthIncomeBonus * rebirths.
function Rebirth.multiplier(rebirths: number): number
	return 1 + Config.rebirthIncomeBonus * rebirths
end

-- Attempts a rebirth: spends the price, clears carry, slots and base pedestals, bumps rebirths, resets cash, notifies.
-- Returns a boolean: true on success, false if the player has no state, too little cash, or spendCash fails.
function Rebirth.try(player: Player): boolean
	local state = PlayerState.get(player)
	if not state then
		return false
	end
	local price = Rebirth.cost(state.rebirths)
	if state.cash < price then
		return false
	end
	if not PlayerState.spendCash(player, price) then
		return false
	end
	local baseIndex = state.baseIndex
	Carry.clear(player)
	PlayerState.clearSlots(player)
	if baseIndex then
		Pedestal.clearBase(baseIndex)
	end
	state.rebirths += 1
	state.cash = Config.cashAfterRebirth
	Storm.notify(player, "rebirth", "Rebirth complete! Now x" .. string.format("%.1f", Rebirth.multiplier(state.rebirths)) .. " income", Color3.fromRGB(255, 210, 120))
	return true
end

-- Builds the "RebirthPrompt" ProximityPrompt and the "RebirthSign" BillboardGui with its "Cost" label on the given spot.
-- Returns nothing; the created instances are parented to spot.
function Rebirth.init(spot: BasePart)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RebirthPrompt"
	prompt.ActionText = "Rebirth"
	prompt.ObjectText = "Plaza"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = spot

	local gui = Instance.new("BillboardGui")
	gui.Name = "RebirthSign"
	gui.Size = UDim2.fromOffset(220, 70)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = spot
	local label = Instance.new("TextLabel")
	label.Name = "Cost"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 208, 102)
	label.Text = "REBIRTH"
	label.Parent = gui
end

-- Connects PromptTriggered so a "RebirthPrompt" trigger by a player holding a base calls Rebirth.try.
-- Returns nothing; other prompts and players without a Bases record are ignored.
function Rebirth.bind()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt.Name ~= "RebirthPrompt" then
			return
		end
		local record = Bases.get(player)
		if not record then
			return
		end
		Rebirth.try(player)
	end)
end

return Rebirth
-- (recorded build witness)
