-- Bases: owns per-player base plots: assignment, ownership boards, teleporting owners to their plot, and the base lock timer.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: Bases.init, Bases.records, Bases.get, Bases.getByIndex, Bases.assign, Bases.release, Bases.teleport, Bases.spawnAt, Bases.bindCharacter, Bases.isLocked, Bases.setLock, Bases.ownerOf
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

function Bases.assign(player: Player): Record?
	local held = byPlayer[player]
	if held then
		return held
	end
	for _, record in records do
		if record.owner == nil then
			record.owner = player
			byPlayer[player] = record
			PlayerState.setBase(player, record.index)
			if record.board then
				record.board.Text = player.Name
			end
			return record
		end
	end
	return nil
end

function Bases.release(player: Player)
	local record = byPlayer[player]
	if not record then
		return
	end
	record.owner = nil
	record.lockedUntil = 0
	byPlayer[player] = nil
	PlayerState.setBase(player, nil)
	if record.board then
		record.board.Text = "Pemilik"
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
		Bases.assign(player)
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
