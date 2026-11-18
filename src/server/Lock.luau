-- Lock: owns base locking: fence solidity, the lock countdown board, and the lock prompt and ticker.
-- Server gameplay is authoritative; the client only renders and sends intents.
--!strict

local ProximityPromptService = game:GetService("ProximityPromptService")

local Config = require(script.Parent:WaitForChild("Config"))
local Bases = require(script.Parent:WaitForChild("Bases"))
local Storm = require(script.Parent:WaitForChild("Storm"))

local boards: { [number]: TextLabel } = {}
local watching = false

local Lock = {}

-- === fence and board ===
local function fenceParts(model: Instance): { BasePart }
	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local name = descendant.Name
			if name == "FencePost" or name == "Rail" or name == "Gate" then
				table.insert(parts, descendant)
			end
		end
	end
	return parts
end

local function applySolid(record: any, solid: boolean)
	local model = record.model
	if not model then
		return
	end
	for _, part in fenceParts(model) do
		if solid then
			part.CanCollide = true
			part:SetAttribute("LockSolid", true)
		else
			if part:GetAttribute("LockSolid") == true then
				part.CanCollide = part.Name == "FencePost"
				part:SetAttribute("LockSolid", nil)
			end
		end
	end
end

local function ensureBoard(record: any): TextLabel?
	local existing = boards[record.index]
	if existing and existing.Parent then
		return existing
	end
	local model = record.model
	if not model then
		return nil
	end
	local host = model:FindFirstChild("NameBoard", true)
	if not (host and host:IsA("BasePart")) then
		host = record.centre
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "LockCountdown"
	gui.Size = UDim2.fromOffset(160, 40)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.Parent = host
	local label = Instance.new("TextLabel")
	label.Name = "Count"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 220, 90)
	label.Text = ""
	label.Parent = gui
	boards[record.index] = label
	return label
end

-- === public api ===
function Lock.isLocked(player: Player, now: number?): boolean
	local record = Bases.get(player)
	if not record then
		return false
	end
	return Bases.isLocked(record, now)
end

function Lock.baseLocked(baseIndex: number, now: number?): boolean
	local record = Bases.getByIndex(baseIndex)
	if not record then
		return false
	end
	return Bases.isLocked(record, now)
end

function Lock.remaining(baseIndex: number, now: number?): number
	local record = Bases.getByIndex(baseIndex)
	if not record then
		return 0
	end
	return math.max(0, record.lockedUntil - (now or os.clock()))
end

function Lock.lock(player: Player, now: number?): boolean
	local record = Bases.get(player)
	if not record or record.owner ~= player then
		return false
	end
	local clock = now or os.clock()
	if Bases.isLocked(record, clock) then
		return false
	end
	Bases.setLock(record, clock + Config.lockDuration)
	applySolid(record, true)
	local label = ensureBoard(record)
	if label then
		local gui = label.Parent
		if gui and gui:IsA("BillboardGui") then
			gui.Enabled = true
		end
		label.Text = tostring(Config.lockDuration)
	end
	Storm.notify(player, "locked", "Base locked for " .. tostring(Config.lockDuration) .. "s", Color3.fromRGB(150, 220, 255))
	return true
end

function Lock.unlock(baseIndex: number)
	local record = Bases.getByIndex(baseIndex)
	if not record then
		return
	end
	Bases.setLock(record, 0)
	applySolid(record, false)
	local label = boards[baseIndex]
	if label then
		label.Text = ""
		local gui = label.Parent
		if gui and gui:IsA("BillboardGui") then
			gui.Enabled = false
		end
	end
end

function Lock.tick(now: number?)
	local clock = now or os.clock()
	for _, record in Bases.records() do
		if record.lockedUntil > 0 then
			local left = record.lockedUntil - clock
			if left <= 0 then
				Lock.unlock(record.index)
			else
				local label = boards[record.index]
				if label then
					label.Text = string.format("%d", math.ceil(left))
				end
			end
		end
	end
end

function Lock.init()
	for _, record in Bases.records() do
		local model = record.model
		if not model then
			continue
		end
		local host = model:FindFirstChild("PlotCentre", true)
		if not (host and host:IsA("BasePart")) then
			host = record.centre
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "LockPrompt"
		prompt.ActionText = "Lock"
		prompt.ObjectText = "Base"
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Parent = host
		ensureBoard(record)
	end
end

function Lock.bind()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt.Name ~= "LockPrompt" then
			return
		end
		local record = Bases.get(player)
		if not record then
			return
		end
		local host = prompt.Parent
		if host ~= record.centre and not (record.model and host and host:IsDescendantOf(record.model)) then
			return
		end
		Lock.lock(player)
	end)
end

function Lock.start()
	if watching then
		return
	end
	watching = true
	task.spawn(function()
		while watching do
			local ok, err = pcall(Lock.tick)
			if not ok then
				warn("[Lock] tick failed: " .. tostring(err))
			end
			task.wait(0.25)
		end
	end)
end

function Lock.stop()
	watching = false
end

function Lock.canPass(player: Player, baseIndex: number): boolean
	local record = Bases.getByIndex(baseIndex)
	if not record then
		return true
	end
	if not Bases.isLocked(record) then
		return true
	end
	return record.owner == player
end

return Lock
