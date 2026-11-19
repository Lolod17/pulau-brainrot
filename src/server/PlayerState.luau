-- PlayerState: owns the authoritative per-player state record: cash, rebirths, slots, carrying, and (de)serialization.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: PlayerState.create, PlayerState.get, PlayerState.addCash, PlayerState.spendCash, PlayerState.setBase, PlayerState.setCarrying, PlayerState.setSlot, PlayerState.clearSlots, PlayerState.incomeMultiplier, PlayerState.placedIncome, PlayerState.serialize, PlayerState.clear, PlayerState.slotFromEntry
-- contract:
--   Owns: one State per player keyed by player, with fields cash, rebirths, baseIndex, slots (Config.slotCount entries), carrying, userId.
--   Validates: loaded cash/rebirths must be numbers (floored, clamped >= 0); loaded slot/carrying ids must resolve via Cast.getById;
--   spendCash refuses negative cost or insufficient cash; setSlot ignores indexes outside 1..Config.slotCount; addCash clamps cash at 0.
--   Returns: create -> State (existing one if present); spendCash -> boolean; addCash -> new cash (0 if no state);
--   incomeMultiplier -> 1 + rebirthIncomeBonus * rebirths; serialize -> plain table (empty slots/carrying as false, baseIndex 0 if nil) or nil.
--!strict

local Config = require(script.Parent:WaitForChild("Config"))
local Cast = require(script.Parent:WaitForChild("Cast"))

export type Slot = {
	id: string,
	name: string,
	income: number,
	price: number,
}

export type State = {
	cash: number,
	rebirths: number,
	baseIndex: number?,
	slots: { Slot? },
	carrying: Slot?,
	tutorialDone: boolean,
	userId: number,
}

local byPlayer: { [any]: State } = {}

-- PlayerState module table.
-- Owns: the private byPlayer map holding one State per player (cash, rebirths, baseIndex, slots, carrying, userId).
-- Refuses: a second create for the same player (returns the existing State); loaded cash/rebirths that are not numbers;
--   loaded slot/carrying ids that Cast.getById cannot resolve; spendCash with a negative cost or more than the player holds;
--   setSlot indexes outside 1..Config.slotCount; cash going below 0 in addCash; every mutator is a no-op when no State exists.
-- Returns: State from create/get, new cash from addCash, boolean from spendCash, numbers from incomeMultiplier/placedIncome,
--   a plain save table (with incomeRate) or nil from serialize, and a fresh Slot from slotFromEntry.
local PlayerState = {}

-- === state lifecycle ===
-- Builds an empty slot list sized to Config.slotCount with every entry nil.
-- Returns: a fresh { Slot? } table with no occupied slots.
local function blankSlots(): { Slot? }
	local slots: { Slot? } = {}
	for i = 1, Config.slotCount do
		slots[i] = nil
	end
	return slots
end

-- Creates the player's State from defaults, overlaying validated cash, rebirths, carrying and slots from a loaded save.
-- Returns: the new State, or the already existing State if the player has one.
function PlayerState.create(player: any, loaded: { [string]: any }?): State
	local existing = byPlayer[player]
	if existing then
		return existing
	end
	local state: State = {
		cash = Config.startingCash,
		rebirths = 0,
		baseIndex = nil,
		slots = blankSlots(),
		carrying = nil,
		tutorialDone = false,
		userId = if typeof(player) == "Instance" then player.UserId else (player.UserId or 0),
	}
	if loaded then
		if loaded.tutorialDone == true then
			state.tutorialDone = true
		end
		if typeof(loaded.cash) == "number" then
			state.cash = math.max(0, math.floor(loaded.cash))
		end
		if typeof(loaded.rebirths) == "number" then
			state.rebirths = math.max(0, math.floor(loaded.rebirths))
		end
		if typeof(loaded.carrying) == "table" then
			local entry = Cast.getById(loaded.carrying.id)
			if entry then
				state.carrying = {
					id = entry.id,
					name = entry.name,
					income = entry.income,
					price = entry.price,
				}
			end
		end
		if typeof(loaded.slots) == "table" then
			for i = 1, Config.slotCount do
				local raw = loaded.slots[i]
				if typeof(raw) == "table" and typeof(raw.id) == "string" then
					local entry = Cast.getById(raw.id)
					if entry then
						state.slots[i] = {
							id = entry.id,
							name = entry.name,
							income = entry.income,
							price = entry.price,
						}
					end
				end
			end
		end
	end
	byPlayer[player] = state
	return state
end

-- Looks up the player's current State.
-- Returns: the State, or nil if the player has none.
function PlayerState.get(player: any): State?
	return byPlayer[player]
end

-- === cash ===
-- Adds the floored amount to the player's cash, clamping the result at 0.
-- Returns: the player's new cash, or 0 if the player has no State.
function PlayerState.addCash(player: any, amount: number): number
	local state = byPlayer[player]
	if not state then
		return 0
	end
	state.cash += math.floor(amount)
	if state.cash < 0 then
		state.cash = 0
	end
	return state.cash
end

-- Deducts the floored amount from cash if the player has a State, the cost is non-negative and affordable.
-- Returns: true if the cash was spent, false otherwise.
function PlayerState.spendCash(player: any, amount: number): boolean
	local state = byPlayer[player]
	local cost = math.floor(amount)
	if not state or cost < 0 or state.cash < cost then
		return false
	end
	state.cash -= cost
	return true
end

-- === base and slots ===
-- Sets (or clears with nil) the player's base index when the player has a State.
-- Returns: nothing.
function PlayerState.setBase(player: any, index: number?)
	local state = byPlayer[player]
	if state then
		state.baseIndex = index
	end
end

-- Sets (or clears with nil) the slot the player is carrying when the player has a State.
-- Returns: nothing.
function PlayerState.setCarrying(player: any, slot: Slot?)
	local state = byPlayer[player]
	if state then
		state.carrying = slot
	end
end

-- Puts a slot (or nil) at index when the player has a State and index is within 1..Config.slotCount.
-- Returns: nothing.
function PlayerState.setSlot(player: any, index: number, slot: Slot?)
	local state = byPlayer[player]
	if state and index >= 1 and index <= Config.slotCount then
		state.slots[index] = slot
	end
end

-- Empties every slot from 1 to Config.slotCount when the player has a State.
-- Returns: nothing.
function PlayerState.clearSlots(player: any)
	local state = byPlayer[player]
	if not state then
		return
	end
	for i = 1, Config.slotCount do
		state.slots[i] = nil
	end
end

-- === derived values ===
-- Computes the rebirth income multiplier from Config.rebirthIncomeBonus and the player's rebirths.
-- Returns: 1 + rebirthIncomeBonus * rebirths, or 1 if the player has no State.
function PlayerState.incomeMultiplier(player: any): number
	local state = byPlayer[player]
	if not state then
		return 1
	end
	return 1 + Config.rebirthIncomeBonus * state.rebirths
end

-- Sums the base income of every occupied slot.
-- Returns: the total placed income, or 0 if the player has no State.
function PlayerState.placedIncome(player: any): number
	local state = byPlayer[player]
	if not state then
		return 0
	end
	local sum = 0
	for i = 1, Config.slotCount do
		local slot = state.slots[i]
		if slot then
			sum += slot.income
		end
	end
	return sum
end

-- === serialization ===
-- Copies the player's State into a plain save table with empty slots/carrying as false and baseIndex 0 when nil.
-- Returns: the table (cash, rebirths, baseIndex, slots, carrying, incomeRate), or nil if the player has no State.
function PlayerState.serialize(player: any): { [string]: any }?
	local state = byPlayer[player]
	if not state then
		return nil
	end
	local slots = {}
	for i = 1, Config.slotCount do
		local slot = state.slots[i]
		if slot then
			slots[i] = {
				id = slot.id,
				name = slot.name,
				income = slot.income,
				price = slot.price,
			}
		else
			slots[i] = false
		end
	end
	local carrying: any = false
	if state.carrying then
		carrying = {
			id = state.carrying.id,
			name = state.carrying.name,
			income = state.carrying.income,
			price = state.carrying.price,
		}
	end
	return {
		cash = state.cash,
		rebirths = state.rebirths,
		baseIndex = state.baseIndex or 0,
		slots = slots,
		carrying = carrying,
		tutorialDone = state.tutorialDone == true,
		incomeRate = PlayerState.placedIncome(player) * PlayerState.incomeMultiplier(player),
	}
end

-- Drops the player's State from the byPlayer map.
-- Returns: nothing.
function PlayerState.clear(player: any)
	byPlayer[player] = nil
end

-- Builds a Slot from a Cast entry's id, name, income and price.
-- Returns: a new Slot table.
function PlayerState.slotFromEntry(entry: Cast.Entry): Slot
	return {
		id = entry.id,
		name = entry.name,
		income = entry.income,
		price = entry.price,
	}
end

-- Marks the first-run tutorial as completed for this player so the hints stop appearing.
-- Returns: true when the flag changed from false to true.
function PlayerState.markTutorial(player: any): boolean
	local state = byPlayer[player]
	if not state or state.tutorialDone then
		return false
	end
	state.tutorialDone = true
	return true
end

return PlayerState
-- (recorded build witness)
