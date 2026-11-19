-- Bases: owns per-player base plots: assignment, ownership boards, teleporting owners to their plot, and the base lock timer.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: Bases.init, Bases.records, Bases.get, Bases.getByIndex, Bases.assign, Bases.release, Bases.teleport, Bases.spawnAt, Bases.bindCharacter, Bases.isLocked, Bases.setLock, Bases.ownerOf
-- contract:
--   Owns: min(#plotCentres, Config.baseCount) base records, the player->record map, and a FIFO waiting queue.
--   Assign: returns the player's existing record, else the first record with no owner (sets owner, PlayerState.setBase, board = player.Name);
--   if none is free the player is enqueued and nil is returned. Release: clears owner and PlayerState base, calls Lock.unlock,
--   resets board to "Pemilik", then pops the queue until a still-present unassigned player is assigned and spawned there.
--   Validates: teleport needs a record, a character and a BasePart HumanoidRootPart; isLocked returns lockedUntil > (now or os.clock()).
--!strict

local Players = game:GetService("Players")

local Config = require(script.Parent:WaitForChild("Config"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))

export type Anchors = {
	pierSpawns: { BasePart },
	plotCentres: { BasePart },
	pedestals: { { BasePart } },
	rebirth: BasePart,
	centre: BasePart,
}

type Record = {
	index: number,
	centre: BasePart,
	pedestals: { BasePart },
	model: Instance?,
	owner: Player?,
	board: TextLabel?,
	lockedUntil: number,
}

local records: { Record } = {}
local byPlayer: { [Player]: Record } = {}
local waiting: { Player } = {}

-- Bases module table.
-- Owns: the `records` array (one Record per plot, built by Bases.init from anchors.plotCentres capped at
--   Config.baseCount), the `byPlayer` Player->Record map, the `waiting` FIFO queue of players with no free
--   plot, each record's `owner`, `board` text ("Pemilik" or the owner's Name) and `lockedUntil` clock.
-- Refuses: assign gives no record when every plot has an owner (the player is enqueued instead); release of
--   a player without a record only dequeues them; teleport does nothing without a record, a character or a
--   BasePart HumanoidRootPart; spawnAt does nothing without a character or when assign fails; queued players
--   who left (Parent ~= Players) or already hold a record are skipped; bindCharacter skips players who left.
-- Returns: Bases itself; records/get/getByIndex/assign return Record (or nil), isLocked a boolean, ownerOf
--   a Player or nil; init, release, teleport, spawnAt, bindCharacter and setLock return nothing.
local Bases = {}

-- === lookup helpers ===
-- Finds the OwnerName TextLabel inside the plot model's NameBoard/SignGui for a plot centre.
-- Returns the TextLabel, or nil when the centre has no parent model or the board/label is missing.
local function findBoard(centre: BasePart): TextLabel?
	local model = centre.Parent
	if not model then
		return nil
	end
	local board = model:FindFirstChild("NameBoard", true)
	if not board then
		return nil
	end
	local gui = board:FindFirstChild("SignGui")
	local label = gui and gui:FindFirstChild("OwnerName")
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

-- === base assignment ===
-- Clears all state and builds one unowned, unlocked record per plot centre (capped at Config.baseCount), resetting boards to "Pemilik".
-- Returns nothing.
function Bases.init(anchors: Anchors)
	table.clear(records)
	table.clear(byPlayer)
	table.clear(waiting)
	local count = math.min(#anchors.plotCentres, Config.baseCount)
	for i = 1, count do
		local centre = anchors.plotCentres[i]
		records[i] = {
			index = i,
			centre = centre,
			pedestals = anchors.pedestals[i] or {},
			model = centre.Parent,
			owner = nil,
			board = findBoard(centre),
			lockedUntil = 0,
		}
		if records[i].board then
			records[i].board.Text = "Pemilik"
		end
	end
end

-- Exposes the internal array of all base records.
-- Returns the live `records` table (not a copy).
function Bases.records(): { Record }
	return records
end

-- Looks up the base record held by a player.
-- Returns the player's Record, or nil if they hold none.
function Bases.get(player: Player): Record?
	return byPlayer[player]
end

-- Looks up a base record by its plot index.
-- Returns the Record at that index, or nil if out of range.
function Bases.getByIndex(index: number): Record?
	return records[index]
end

-- Removes every occurrence of a player from the waiting queue.
-- Returns nothing.
local function dequeue(player: Player)
	for i = #waiting, 1, -1 do
		if waiting[i] == player then
			table.remove(waiting, i)
		end
	end
end

-- Appends a player to the end of the waiting queue, removing any earlier entry first so they appear once.
-- Returns nothing.
local function enqueue(player: Player)
	dequeue(player)
	table.insert(waiting, player)
end

-- Gives the player their held record, or claims the first unowned record (sets owner, PlayerState base, board name), else enqueues them.
-- Returns the player's Record, or nil when no plot is free and they were queued.
function Bases.assign(player: Player): Record?
	local held = byPlayer[player]
	if held then
		return held
	end
	for _, record in records do
		if record.owner == nil then
			record.owner = player
			byPlayer[player] = record
			dequeue(player)
			PlayerState.setBase(player, record.index)
			if record.board then
				record.board.Text = player.Name
			end
			return record
		end
	end
	enqueue(player)
	return nil
end

-- Frees the player's plot (owner, PlayerState base, Lock.unlock, board reset) then hands it to the first still-present unassigned queued player.
-- Returns nothing; a player without a record is only removed from the queue.
function Bases.release(player: Player)
	local record = byPlayer[player]
	if not record then
		dequeue(player)
		return
	end
	record.owner = nil
	byPlayer[player] = nil
	PlayerState.setBase(player, nil)
	local Lock = require(script.Parent:WaitForChild("Lock"))
	Lock.unlock(record.index)
	if record.board then
		record.board.Text = "Pemilik"
	end
	while #waiting > 0 do
		local nextPlayer = table.remove(waiting, 1)
		if nextPlayer.Parent == Players and not byPlayer[nextPlayer] then
			if Bases.assign(nextPlayer) then
				Bases.spawnAt(nextPlayer)
				break
			end
		end
	end
end

-- === character spawn ===
-- Pivots the player's character to 4 studs above the top of their plot centre.
-- Returns nothing; does nothing without a record, a character or a BasePart HumanoidRootPart.
function Bases.teleport(player: Player)
	local record = byPlayer[player]
	local character = player.Character
	if not record or not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local centre = record.centre
	local goal = centre.CFrame + Vector3.new(0, centre.Size.Y / 2 + 4, 0)
	character:PivotTo(goal)
end

-- Ensures the player has a base (assigning one if needed) and teleports their character to it.
-- Returns nothing; stops early without a character or when no base can be assigned.
function Bases.spawnAt(player: Player)
	local character = player.Character
	if not character then
		return
	end
	if not byPlayer[player] then
		if not Bases.assign(player) then
			return
		end
	end
	Bases.teleport(player)
end

-- === character spawn ===
-- Connects CharacterAdded so each new character is deferred-spawned at the player's base while they remain in Players.
-- Returns nothing.
function Bases.bindCharacter(player: Player)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			if player.Parent == Players then
				Bases.spawnAt(player)
			end
		end)
	end)
end

-- === lock state ===
-- Checks whether a base's lock is still active against `now` (defaults to os.clock()).
-- Returns true when record.lockedUntil is later than now, else false.
function Bases.isLocked(record: Record, now: number?): boolean
	return record.lockedUntil > (now or os.clock())
end

-- Sets the clock time until which the base stays locked.
-- Returns nothing.
function Bases.setLock(record: Record, untilClock: number)
	record.lockedUntil = untilClock
end

-- Reads the current owner of a base record.
-- Returns the owning Player, or nil when the plot is free.
function Bases.ownerOf(record: Record): Player?
	return record.owner
end

return Bases
-- (recorded build witness)
-- (recorded build witness b)

-- (recorded build witness c)
