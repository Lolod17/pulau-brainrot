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
	userId: number,
}

local byPlayer: { [any]: State } = {}

local PlayerState = {}

-- === state lifecycle ===
local function blankSlots(): { Slot? }
	local slots: { Slot? } = {}
	for i = 1, Config.slotCount do
		slots[i] = nil
	end
	return slots
end

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
		userId = if typeof(player) == "Instance" then player.UserId else (player.UserId or 0),
	}
	if loaded then
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

function PlayerState.get(player: any): State?
	return byPlayer[player]
end

-- === cash ===
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
function PlayerState.setBase(player: any, index: number?)
	local state = byPlayer[player]
	if state then
		state.baseIndex = index
	end
end

function PlayerState.setCarrying(player: any, slot: Slot?)
	local state = byPlayer[player]
	if state then
		state.carrying = slot
	end
end

function PlayerState.setSlot(player: any, index: number, slot: Slot?)
	local state = byPlayer[player]
	if state and index >= 1 and index <= Config.slotCount then
		state.slots[index] = slot
	end
end

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
function PlayerState.incomeMultiplier(player: any): number
	local state = byPlayer[player]
	if not state then
		return 1
	end
	return 1 + Config.rebirthIncomeBonus * state.rebirths
end

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
		incomeRate = PlayerState.placedIncome(player) * PlayerState.incomeMultiplier(player),
	}
end

function PlayerState.clear(player: any)
	byPlayer[player] = nil
end

function PlayerState.slotFromEntry(entry: Cast.Entry): Slot
	return {
		id = entry.id,
		name = entry.name,
		income = entry.income,
		price = entry.price,
	}
end

return PlayerState
