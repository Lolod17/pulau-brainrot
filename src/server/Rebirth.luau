--!strict

local ProximityPromptService = game:GetService("ProximityPromptService")

local Config = require(script.Parent:WaitForChild("Config"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local Bases = require(script.Parent:WaitForChild("Bases"))
local Pedestal = require(script.Parent:WaitForChild("Pedestal"))
local Carry = require(script.Parent:WaitForChild("Carry"))

local Rebirth = {}

function Rebirth.cost(rebirths: number): number
	return Config.rebirthBaseCost * (Config.rebirthGrowth ^ rebirths)
end

function Rebirth.costFor(player: Player): number
	local state = PlayerState.get(player)
	local rebirths = if state then state.rebirths else 0
	return Rebirth.cost(rebirths)
end

function Rebirth.multiplier(rebirths: number): number
	return 1 + Config.rebirthIncomeBonus * rebirths
end

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
	return true
end

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
