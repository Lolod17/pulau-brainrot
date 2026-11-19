-- Carry: owns the single brainrot a player holds above their head, its follow loop, and restoring it across respawns.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: Carry.isCarrying, Carry.modelOf, Carry.attach, Carry.release, Carry.takeModel, Carry.clear, Carry.restore, Carry.stop
-- contract:
--   Owns: the player->Model held map and one Heartbeat follow connection (lerps unwelded models to head + Config.carryHeight).
--   attach refuses (returns nil) when the player has no state, is already carrying, has no character, the slot id is not in Cast,
--   or the model has no PrimaryPart (a freshly built model is destroyed; a passed-in model is not).
--   On success it sets PlayerState carrying, welds the model above the character's head via Factory.weldAboveHead, and returns the model.
--   release drops the model, takeModel hands it back (nil if unparented), clear removes it; all three clear PlayerState carrying.
--!strict

local RunService = game:GetService("RunService")

local Config = require(script.Parent:WaitForChild("Config"))
local Cast = require(script.Parent:WaitForChild("Cast"))
local Factory = require(script.Parent:WaitForChild("BrainrotFactory"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))

type Slot = PlayerState.Slot

local held: { [Player]: Model } = {}
local followConn: RBXScriptConnection? = nil

-- Carry module table.
-- Owns: the `held` map (Player -> carried Model) and the single `followConn` Heartbeat
--   connection that lerps unwelded carried models to head + Config.carryHeight.
-- Refuses: attach returns nil when PlayerState.get has no state, state.carrying is already set,
--   player.Character is missing, Cast.getById(slot.id) finds nothing, or the model has no PrimaryPart;
--   restore does nothing when there is no carrying state, a model is already held, or no character.
-- Returns: isCarrying -> boolean; modelOf, attach, release, takeModel -> Model?; clear, restore, stop -> nothing.
local Carry = {}

-- Starts the shared Heartbeat follow loop once, moving unwelded held models above each carrier's head.
-- Returns nothing; exits early if the follow connection already exists.
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

-- Removes every held model that has lost its Parent and clears that player's PlayerState carrying.
-- Returns nothing.
local function dropDetached()
	for player, model in held do
		if not model.Parent then
			held[player] = nil
			PlayerState.setCarrying(player, nil)
		end
	end
end

-- Reports whether the player's PlayerState currently records a carried slot.
-- Returns true if state exists and state.carrying is non-nil, false otherwise.
function Carry.isCarrying(player: Player): boolean
	local state = PlayerState.get(player)
	return state ~= nil and state.carrying ~= nil
end

-- Looks up the Model this module holds for the player.
-- Returns the held Model, or nil if none.
function Carry.modelOf(player: Player): Model?
	return held[player]
end

-- Attaches a slot's brainrot (the passed-in parented model or a freshly built one) above the player's head and records carrying.
-- Returns the attached Model, or nil when refused (no state, already carrying, no character, unknown slot id, no PrimaryPart).
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

-- Forgets the held model, clears PlayerState carrying, and drops the model via Factory.drop if it is still parented.
-- Returns the model that was held (possibly unparented), or nil if none.
function Carry.release(player: Player): Model?
	local model = held[player]
	held[player] = nil
	PlayerState.setCarrying(player, nil)
	if model and model.Parent then
		Factory.drop(model)
	end
	return model
end

-- Forgets the held model and clears PlayerState carrying without dropping or destroying it.
-- Returns the model for the caller to reuse, or nil if none was held or it is unparented.
function Carry.takeModel(player: Player): Model?
	local model = held[player]
	held[player] = nil
	PlayerState.setCarrying(player, nil)
	if model and not model.Parent then
		return nil
	end
	return model
end

-- Forgets the held model, clears PlayerState carrying, and removes the model via Factory.remove inside a pcall.
-- Returns nothing.
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

-- Re-attaches the slot recorded in PlayerState carrying (e.g. after respawn) when no model is held and a character exists.
-- Returns nothing; the result of Carry.attach is discarded.
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

-- Disconnects the Heartbeat follow connection if it is running and clears it.
-- Returns nothing.
function Carry.stop()
	if followConn then
		followConn:Disconnect()
		followConn = nil
	end
end

return Carry
-- (recorded build witness)
