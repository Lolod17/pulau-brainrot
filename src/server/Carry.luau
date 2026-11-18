-- Carry: owns the single brainrot a player holds above their head, its follow loop, and restoring it across respawns.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: Carry.isCarrying, Carry.modelOf, Carry.attach, Carry.release, Carry.takeModel, Carry.clear, Carry.restore, Carry.stop
--!strict

local RunService = game:GetService("RunService")

local Config = require(script.Parent:WaitForChild("Config"))
local Cast = require(script.Parent:WaitForChild("Cast"))
local Factory = require(script.Parent:WaitForChild("BrainrotFactory"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))

type Slot = PlayerState.Slot

local held: { [Player]: Model } = {}
local followConn: RBXScriptConnection? = nil

local Carry = {}

local function ensureFollow()
	if followConn then
		return
	end
	followConn = RunService.Heartbeat:Connect(function()
		for player, model in held do
			local character = player.Character
			local anchor = model.PrimaryPart
			if not character or not anchor or not anchor.Parent or not model.Parent then
				continue
			end
			local head = character:FindFirstChild("Head")
			if not (head and head:IsA("BasePart")) then
				head = character:FindFirstChild("HumanoidRootPart")
			end
			if not (head and head:IsA("BasePart")) then
				continue
			end
			if anchor:FindFirstChild("CarryWeld") then
				continue
			end
			local goal = head.CFrame * CFrame.new(0, head.Size.Y / 2 + Config.carryHeight, 0)
			local alpha = math.clamp(0.35, 0, 1)
			anchor.CFrame = anchor.CFrame:Lerp(goal, alpha)
		end
		dropDetached()
	end)
end

local function dropDetached()
	for player, model in held do
		if not model.Parent then
			held[player] = nil
			PlayerState.setCarrying(player, nil)
		end
	end
end

function Carry.isCarrying(player: Player): boolean
	local state = PlayerState.get(player)
	return state ~= nil and state.carrying ~= nil
end

function Carry.modelOf(player: Player): Model?
	return held[player]
end

function Carry.attach(player: Player, slot: Slot, existing: Model?): Model?
	local state = PlayerState.get(player)
	if not state then
		return nil
	end
	if state.carrying ~= nil then
		return nil
	end
	local character = player.Character
	if not character then
		return nil
	end
	local entry = Cast.getById(slot.id)
	if not entry then
		return nil
	end
	if existing and not existing.Parent then
		existing = nil
	end
	local model = existing
	if not model then
		local root = character:FindFirstChild("HumanoidRootPart")
		local at = if root and root:IsA("BasePart") then root.Position + Vector3.new(0, 6, 0) else Vector3.new(0, 8, 0)
		model = Factory.create(entry, at)
	end
	if not model.PrimaryPart then
		if not existing then
			model:Destroy()
		end
		return nil
	end
	PlayerState.setCarrying(player, {
		id = entry.id,
		name = entry.name,
		income = entry.income,
		price = entry.price,
	})
	held[player] = model
	Factory.weldAboveHead(model, character)
	ensureFollow()
	return model
end

function Carry.release(player: Player): Model?
	local model = held[player]
	held[player] = nil
	PlayerState.setCarrying(player, nil)
	if model and model.Parent then
		Factory.drop(model)
	end
	return model
end

function Carry.takeModel(player: Player): Model?
	local model = held[player]
	held[player] = nil
	PlayerState.setCarrying(player, nil)
	if model and not model.Parent then
		return nil
	end
	return model
end

function Carry.clear(player: Player)
	local model = held[player]
	held[player] = nil
	PlayerState.setCarrying(player, nil)
	if model then
		pcall(function()
			Factory.remove(model)
		end)
	end
end

function Carry.restore(player: Player)
	local state = PlayerState.get(player)
	if not state or not state.carrying or held[player] then
		return
	end
	if not player.Character then
		return
	end
	Carry.attach(player, state.carrying, nil)
end

function Carry.stop()
	if followConn then
		followConn:Disconnect()
		followConn = nil
	end
end

return Carry
