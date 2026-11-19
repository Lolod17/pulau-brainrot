-- Lock: owns base locking: fence solidity, the lock countdown board, and the lock prompt and ticker.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: Lock.isLocked, Lock.baseLocked, Lock.remaining, Lock.lock, Lock.unlock, Lock.tick, Lock.init, Lock.bind, Lock.start, Lock.stop, Lock.canPass
-- contract
-- Owns: each base's lock window (Config.lockDuration, thirty seconds), fence collision while locked, and the countdown boards.
-- Refuses: locking a base the player does not own or one already locked; refuses passage (theft) to anyone but the owner while locked.
-- Never: blocks the owner (canPass always lets the owner through), extends a running lock, or locks a base on a non-owner's request.
--!strict

local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local Config = require(script.Parent:WaitForChild("Config"))
local Bases = require(script.Parent:WaitForChild("Bases"))
local Storm = require(script.Parent:WaitForChild("Storm"))

local boards: { [number]: TextLabel } = {}
local watching = false

-- === module table ===
-- Owns: each base's lock window, written through Bases.setLock (clock + Config.lockDuration, cleared with 0);
--   fence collision on FencePost/Rail/Gate parts, tagged with the LockSolid attribute by applySolid;
--   the LockCountdown billboards kept in `boards`; the LockPrompt proximity prompts placed by Lock.init;
--   and the single tick loop guarded by `watching` (Lock.start / Lock.stop).
-- Refuses: Lock.lock when the player has no base, is not record.owner, or the base is already locked;
--   LockPrompt triggers from a prompt that is not on the triggering player's own base (Lock.bind);
--   passage via Lock.canPass to anyone but record.owner while the base is locked.
-- Returns: this Lock table (isLocked, baseLocked, remaining, lock, unlock, tick, init, bind, start, stop, canPass).
local Lock = {}

-- === fence and board ===
-- Collects the fence posts, rails and gate parts under a base model.
-- Returns: a list of those BaseParts (empty if none).
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

-- Builds (once) and returns the four decorative neon beams that mark a locked base.
-- Returns: the list of beams, empty when the base has no plot part.
local gateBars: { [number]: { BasePart } } = {}
local lockSigns: { [number]: BillboardGui } = {}

local function ensureGate(record: any): { BasePart }
	local cached = gateBars[record.index]
	if cached and cached[1] and cached[1].Parent then
		return cached
	end
	local model = record.model
	local plot = model and model:FindFirstChild("Plot")
	if not plot then
		return {}
	end
	local size = plot.Size
	local centre = plot.Position
	local bars = {}
	local function beam(name: string, beamSize: Vector3, offset: Vector3)
		local beamPart = Instance.new("Part")
		beamPart.Name = name
		beamPart.Size = beamSize
		beamPart.CFrame = CFrame.new(centre + offset)
		beamPart.Anchored = true
		beamPart.CanCollide = false
		beamPart.CanQuery = false
		beamPart.CanTouch = false
		beamPart.Material = Enum.Material.Neon
		beamPart.Color = Color3.fromRGB(255, 92, 92)
		beamPart.Transparency = 1
		beamPart.Parent = model
		table.insert(bars, beamPart)
	end
	beam("GateBarN", Vector3.new(size.X, 0.7, 0.7), Vector3.new(0, 6, -size.Z / 2))
	beam("GateBarS", Vector3.new(size.X, 0.7, 0.7), Vector3.new(0, 6, size.Z / 2))
	beam("GateBarW", Vector3.new(0.7, 0.7, size.Z), Vector3.new(-size.X / 2, 6, 0))
	beam("GateBarE", Vector3.new(0.7, 0.7, size.Z), Vector3.new(size.X / 2, 6, 0))
	for _, corner in ipairs({ Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) }) do
		beam("GatePost", Vector3.new(0.7, 7.5, 0.7), Vector3.new(corner.X * size.X / 2, 4.2, corner.Z * size.Z / 2))
	end
	gateBars[record.index] = bars
	local sign = Instance.new("BillboardGui")
	sign.Name = "LockSign"
	sign.Size = UDim2.new(0, 150, 0, 40)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 12, 0)
	sign.AlwaysOnTop = false
	sign.MaxDistance = 160
	sign.LightInfluence = 0
	sign.Adornee = plot
	sign.Enabled = false
	sign.Parent = model
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(28, 8, 8)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = sign
	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 8)
	frameCorner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 92, 92)
	stroke.Thickness = 2
	stroke.Parent = frame
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextSize = 22
	text.TextColor3 = Color3.fromRGB(255, 120, 120)
	text.TextStrokeTransparency = 0.3
	text.Text = "LOCKED"
	text.Parent = frame
	lockSigns[record.index] = sign
	return bars
end

-- Fades the lock beams in or out. Purely visual: solidity stays with applySolid.
-- Returns: nothing.
local function animateGate(record: any, solid: boolean)
	for _, beamPart in ensureGate(record) do
		local goal = solid and 0.0 or 1
		TweenService:Create(beamPart, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = goal }):Play()
	end
	local sign = lockSigns[record.index]
	if sign then
		sign.Enabled = solid
	end
end

-- Makes a base's fence solid while locked, or restores the parts it had made solid.
-- Returns: nothing.
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
	animateGate(record, solid)
end

-- Finds or builds the hidden countdown billboard for a base.
-- Returns: the countdown TextLabel, or nil when the base has no model.
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
-- Checks whether the player's own base is currently locked.
-- Returns: true if locked, false if unlocked or the player has no base.
function Lock.isLocked(player: Player, now: number?): boolean
	local record = Bases.get(player)
	if not record then
		return false
	end
	return Bases.isLocked(record, now)
end

-- Checks whether the base at the given index is currently locked.
-- Returns: true if locked, false if not locked or the index is unknown.
function Lock.baseLocked(baseIndex: number, now: number?): boolean
	local record = Bases.getByIndex(baseIndex)
	if not record then
		return false
	end
	return Bases.isLocked(record, now)
end

-- Works out how long the base at the given index stays locked.
-- Returns: seconds left, never below zero (zero for an unknown index).
function Lock.remaining(baseIndex: number, now: number?): number
	local record = Bases.getByIndex(baseIndex)
	if not record then
		return 0
	end
	return math.max(0, record.lockedUntil - (now or os.clock()))
end

-- Locks the player's own base for Config.lockDuration, solidifies the fence and shows the countdown.
-- Returns: true if the lock started, false if not the owner or already locked.
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

-- Clears the lock on the base at the given index, relaxes the fence and hides the countdown.
-- Returns: nothing.
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

-- Updates every locked base's countdown and unlocks any whose time has run out.
-- Returns: nothing.
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

-- Places a lock prompt and countdown board on every base that has a model.
-- Returns: nothing.
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

-- Connects lock prompts so a player can only lock from a prompt on their own base.
-- Returns: nothing.
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

-- Starts the background loop that runs Lock.tick every quarter second (once only).
-- Returns: nothing.
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

-- Signals the background tick loop to stop after its current pass.
-- Returns: nothing.
function Lock.stop()
	watching = false
end

-- Decides whether a player may pass into the base at the given index.
-- Returns: true if unlocked, unknown, or the player is the owner; false for anyone else while locked.
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
-- (recorded build witness)
-- (recorded build witness b)
