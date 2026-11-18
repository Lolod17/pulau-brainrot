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

local Bases = {}

-- === lookup helpers ===
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

function Bases.records(): { Record }
	return records
end

function Bases.get(player: Player): Record?
	return byPlayer[player]
end

function Bases.getByIndex(index: number): Record?
	return records[index]
end

local function dequeue(player: Player)
	for i = #waiting, 1, -1 do
		if waiting[i] == player then
			table.remove(waiting, i)
		end
	end
end

local function enqueue(player: Player)
	dequeue(player)
	table.insert(waiting, player)
end

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
function Bases.isLocked(record: Record, now: number?): boolean
	return record.lockedUntil > (now or os.clock())
end

function Bases.setLock(record: Record, untilClock: number)
	record.lockedUntil = untilClock
end

function Bases.ownerOf(record: Record): Player?
	return record.owner
end

return Bases
