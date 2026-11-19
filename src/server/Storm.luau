-- Storm: owns the periodic storm cycle and the storm/notify remotes that broadcast to clients.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: Storm.secondsUntilNext, Storm.init, Storm.bind, Storm.start, Storm.fireAlert, Storm.notify, Storm.notifyAll, Storm.fireBroadcast
--
-- Module contract (derived from the code below):
-- Owns: the storm timer (first storm after FIRST_STORM seconds, then every INTERVAL seconds),
--   the warning/wave/clear phase broadcasts on the Net.Storm RemoteEvent, the Net.Alert
--   RemoteEvent used for player notifications, the workspace.Shells folder and every Shell
--   part and ProximityPrompt spawned into it, and the Lighting darken/restore tweens.
-- Refuses: to open a shell that is already opened, has left the Shells folder, or is used by a
--   player with no state or one already carrying; to sweep a player whose carried model is
--   held inside their own base or parented under a base (BaseIndex attribute); to fire any
--   remote before init has created it (alert/storm calls are silent no-ops until then).
-- Returns: the Storm table from the module, from Storm.init and from Storm.bind;
--   Storm.secondsUntilNext returns a whole number of seconds; every other public function
--   returns nothing.
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Config = require(script.Parent.Config)
local Cast = require(script.Parent.Cast)
local PlayerState = require(script.Parent.PlayerState)
local Carry = require(script.Parent.Carry)
local Bases = require(script.Parent.Bases)

local Storm = {}

local FIRST_STORM = 120
local INTERVAL = 180
local WARN_TIME = 10
local WAVE_TIME = 8
local SHELL_LIFETIME = 60
local WAVE_HEIGHT = 14
local SHELL_TIERS = {
	near = { "Common", "Uncommon" },
	mid = { "Rare", "Epic" },
	far = { "Legendary", "Mythic", "Ultra Rare" },
}
local NEAR_RADIUS = 120
local MID_RADIUS = 260

local net: Instance? = nil
local stormEvent: RemoteEvent? = nil
local alertEvent: RemoteEvent? = nil
local shellFolder: Folder? = nil
local islandCenter = Vector3.new(0, 0, 0)
local pierCenter = Vector3.new(0, 0, 0)

-- Finds the workspace "Pier" (part, folder or model) and caches its position in pierCenter.
-- Returns nothing; pierCenter is left unchanged when no usable pier is found.
local function resolvePier()
	local pier = workspace:FindFirstChild("Pier", true)
	if pier and pier:IsA("BasePart") then
		pierCenter = pier.Position
		return
	end
	if pier and pier:IsA("Folder") then
		local first = pier:FindFirstChildWhichIsA("BasePart", true)
		if first then
			pierCenter = first.Position
			return
		end
	end
	if pier and pier:IsA("Model") then
		local ok, cf = pcall(function()
			return (pier :: Model):GetPivot()
		end)
		if ok and cf then
			pierCenter = cf.Position
		end
	end
end

-- Converts the cumulative Config.tiers thresholds into a per-rarity probability weight.
-- Returns a map of rarity name to weight (threshold span divided by 1000).
local function rarityWeights(): { [string]: number }
	local weights: { [string]: number } = {}
	local prev = 0
	for _, tier in Config.tiers do
		weights[tier.rarity] = (tier.threshold - prev) / 1000
		prev = tier.threshold
	end
	return weights
end

-- Picks one rarity from the given list using the Config-derived weights.
-- Returns the rolled rarity, the first entry if all weights are zero, or the last as fallback.
local function rollFrom(list: { string }): string
	local weights = rarityWeights()
	local total = 0
	for _, rarity in list do
		total += weights[rarity] or 0
	end
	if total <= 0 then
		return list[1]
	end
	local roll = math.random() * total
	for _, rarity in list do
		roll -= weights[rarity] or 0
		if roll <= 0 then
			return rarity
		end
	end
	return list[#list]
end

-- Collects every Cast entry whose rarity matches the requested rarity.
-- Returns an array of matching entries, empty when none match or Cast.entries is missing.
local function poolFor(rarity: string): { any }
	local pool: { any } = {}
	if typeof(Cast.entries) == "table" then
		for _, entry in Cast.entries do
			if entry.rarity == rarity then
				table.insert(pool, entry)
			end
		end
	end
	return pool
end

-- Measures flat (XZ) distance from the island centre to choose a shell rarity band.
-- Returns the near, mid or far rarity list from SHELL_TIERS.
local function tiersForDistance(position: Vector3): { string }
	local flat = Vector3.new(position.X, 0, position.Z)
	local center = Vector3.new(islandCenter.X, 0, islandCenter.Z)
	local dist = (flat - center).Magnitude
	if dist <= NEAR_RADIUS then
		return SHELL_TIERS.near
	elseif dist <= MID_RADIUS then
		return SHELL_TIERS.mid
	end
	return SHELL_TIERS.far
end

-- Rolls a rarity for the position and picks a random Cast entry of that rarity.
-- Returns the chosen Cast entry, or nil when the rolled rarity has no entries.
local function chooseCharacter(position: Vector3): any?
	local rarity = rollFrom(tiersForDistance(position))
	local pool = poolFor(rarity)
	if #pool == 0 then
		return nil
	end
	return pool[math.random(1, #pool)]
end

-- Spawns a Shell part with an "Open" prompt that attaches a rolled character to the opener.
-- Returns nothing; the shell self-destructs after SHELL_LIFETIME seconds or once opened.
local function spawnShell(position: Vector3)
	local folder = shellFolder
	if not folder then
		return
	end
	local part = Instance.new("Part")
	part.Name = "Shell"
	part.Size = Vector3.new(2.4, 1.6, 2)
	part.Shape = Enum.PartType.Ball
	part.Color = Color3.fromRGB(255, 226, 196)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = CFrame.new(position + Vector3.new(0, 1.2, 0))
	part.Parent = folder

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Shell"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.ActionText = "Open"
	prompt.Parent = part

	local opened = false
	local connection = prompt.Triggered:Connect(function(player)
		if opened or part.Parent ~= folder then
			return
		end
		local state = PlayerState.get(player)
		if not state or state.carrying ~= nil then
			return
		end
		local choice = chooseCharacter(position)
		if not choice then
			return
		end
		local slot = PlayerState.slotFromEntry(choice)
		local model = Carry.attach(player, slot, nil)
		if model then
			opened = true
			if alertEvent then
				alertEvent:FireClient(player, {
					kind = "placed",
					text = "You opened a shell: " .. tostring(choice.name),
					tier = choice.rarity,
					color = choice.aura,
				})
				alertEvent:FireAllClients({
					kind = "shell-opened",
					position = position,
					tier = choice.rarity,
				})
			end
			part:Destroy()
		end
	end)

	task.delay(SHELL_LIFETIME, function()
		if connection then
			connection:Disconnect()
		end
		if prompt.Parent then
			prompt:Destroy()
		end
		if part.Parent then
			part:Destroy()
		end
	end)
end

local stormStartAt: number? = nil
local stormEndAt: number? = nil

-- Stamps the phase name onto the payload and fires it to all clients over the Storm remote.
-- Returns nothing; silently skips the fire when the Storm remote does not exist yet.
local function broadcastPhase(phase: string, payload: { [string]: any }?)
	local data = payload or {}
	data.phase = phase
	if stormEvent then
		stormEvent:FireAllClients(data)
	end
end

-- Reports time until the next storm start, or until the current clear phase ends.
-- Returns whole seconds (never negative), or INTERVAL when no timer is scheduled.
function Storm.secondsUntilNext(): number
	local now = os.clock()
	local target: number? = nil
	if stormStartAt and now < stormStartAt then
		target = stormStartAt
	elseif stormEndAt then
		target = stormEndAt
	end
	if not target then
		return math.floor(INTERVAL)
	end
	return math.max(0, math.ceil(target - now))
end

-- Checks whether the player is protected by their base: locked, or within 40 studs of its centre.
-- Returns true when protected, false when the player has no base or is outside it.
local function inOwnBase(player: Player, position: Vector3): boolean
	local record = Bases.get(player)
	if not record then
		return false
	end
	if record.lockedUntil and record.lockedUntil > os.clock() then
		return true
	end
	local centre = record.centre
	if centre then
		local flat = Vector3.new(position.X, 0, position.Z)
		local origin = Vector3.new(centre.Position.X, 0, centre.Position.Z)
		if (flat - origin).Magnitude <= 40 then
			return true
		end
	end
	return false
end

-- Checks whether a position lies within 48 studs (XZ only) of the cached pier centre.
-- Returns true when on or near the pier, false otherwise.
local function onPier(position: Vector3): boolean
	local distance = Vector3.new(position.X, 0, position.Z) - Vector3.new(pierCenter.X, 0, pierCenter.Z)
	local probe = Vector3.new(distance.X, 0, distance.Z).Magnitude
	return probe <= 48
end

-- Walks up the instance's ancestors looking for one tagged with a BaseIndex attribute.
-- Returns true when the instance sits under a base, false otherwise.
local function underABase(instance: Instance): boolean
	local current: Instance? = instance.Parent
	while current do
		if current:GetAttribute("BaseIndex") ~= nil then
			return true
		end
		current = current.Parent
	end
	return false
end

-- Sweeps exposed players (on the pier, or carrying outside their base) into shells and respawns them.
-- Returns the number of players swept; seeds three pier shells when nobody was swept.
local function sweep()
	resolvePier()
	local swept = 0
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") then
			local position = root.Position
			local state = PlayerState.get(player)
			local inside = inOwnBase(player, position)
			local carrying = state ~= nil and state.carrying ~= nil
			local carried = if carrying then Carry.modelOf(player) else nil
			local carriedInBase = inside and carried ~= nil and carried.Parent ~= nil and carried:IsDescendantOf(character)
			local underBase = carried ~= nil and carried.Parent ~= nil and underABase(carried)
			local outside = not inside
			local onDock = onPier(position)
			if not carriedInBase and not underBase and (onDock or (carrying and outside)) then
				local spot = position
				pcall(function()
					Carry.clear(player)
				end)
				if character.Parent ~= nil then
					character:Destroy()
				end
				spawnShell(spot)
				swept += 1
				if alertEvent then
					alertEvent:FireClient(player, {
						kind = "storm",
						text = "The storm swept you away!",
						color = Color3.fromRGB(120, 190, 255),
					})
				end
				pcall(function()
					player:LoadCharacter()
				end)
			end
		end
		task.wait(0)
	end
	if swept == 0 then
		for i = 1, 3 do
			local offset = Vector3.new((i - 2) * 16, 0, 0)
			spawnShell(pierCenter + offset + Vector3.new(0, 0, -24))
		end
	end
	return swept
end

-- Broadcasts the "wave" phase, waits WAVE_TIME seconds, then runs the player sweep.
-- Returns nothing; the sweep count is discarded.
local function waveSweep()
	broadcastPhase("wave", { toward = "island" })
	task.wait(WAVE_TIME)
	sweep()
end

-- Tweens Lighting to the dim storm palette over the given duration in seconds.
-- Returns nothing; the tween plays asynchronously.
local function darken(duration: number)
	local tween = TweenService:Create(Lighting, TweenInfo.new(duration), {
		Ambient = Color3.fromRGB(64, 70, 86),
		OutdoorAmbient = Color3.fromRGB(70, 78, 96),
		Brightness = 1.4,
	})
	tween:Play()
end

-- Tweens Lighting back to the bright daytime palette over four seconds.
-- Returns nothing; the tween plays asynchronously.
local function restore()
	local tween = TweenService:Create(Lighting, TweenInfo.new(4), {
		Ambient = Color3.fromRGB(158, 184, 204),
		OutdoorAmbient = Color3.fromRGB(168, 194, 214),
		Brightness = 3.2,
	})
	tween:Play()
end

-- Runs one full storm: darken and warn, wait, wave sweep, then broadcast clear and restore light.
-- Returns nothing; yields for roughly WARN_TIME + WAVE_TIME seconds.
local function runStorm()
	darken(WARN_TIME)
	broadcastPhase("warning", { seconds = WARN_TIME })
	Storm.notifyAll("storm-warning", "STORM INBOUND - 10s", Color3.fromRGB(120, 190, 255))
	task.wait(WARN_TIME)
	waveSweep()
	broadcastPhase("clear", { seconds = INTERVAL - WARN_TIME - WAVE_TIME })
	restore()
end

-- Finds or creates the Net folder, Storm/Alert remotes and Shells folder; caches island centre and pier.
-- Returns the Storm module table for chaining.
function Storm.init(anchors: any)
	net = ReplicatedStorage:WaitForChild("Net", 10)
	if not net then
		net = Instance.new("Folder")
		net.Name = "Net"
		net.Parent = ReplicatedStorage
	end
	stormEvent = (net :: Instance):FindFirstChild("Storm") :: RemoteEvent?
	if not stormEvent then
		local event = Instance.new("RemoteEvent")
		event.Name = "Storm"
		event.Parent = net
		stormEvent = event
	end
	alertEvent = (net :: Instance):FindFirstChild("Alert") :: RemoteEvent?
	if not alertEvent then
		local event = Instance.new("RemoteEvent")
		event.Name = "Alert"
		event.Parent = net
		alertEvent = event
	end
	shellFolder = workspace:FindFirstChild("Shells") :: Folder?
	if not shellFolder then
		local folder = Instance.new("Folder")
		folder.Name = "Shells"
		folder.Parent = workspace
		shellFolder = folder
	end
	if anchors and anchors.centre and anchors.centre.Position then
		islandCenter = anchors.centre.Position
	end
	resolvePier()
	return Storm
end

-- No-op bind hook kept for a uniform module lifecycle (init, bind, start).
-- Returns the Storm module table for chaining.
function Storm.bind()
	return Storm
end

-- Starts the endless storm loop in a new thread, tracking start/end times for the countdown.
-- Returns nothing; a failed storm is warned about and the loop continues.
function Storm.start()
	stormStartAt = os.clock() + FIRST_STORM
	task.spawn(function()
		task.wait(FIRST_STORM)
		while true do
			stormStartAt = nil
			local ok, err = pcall(runStorm)
			if not ok then
				warn("[Storm] storm failed: " .. tostring(err))
			end
			stormEndAt = os.clock() + INTERVAL - WARN_TIME - WAVE_TIME
			task.wait(INTERVAL - WARN_TIME - WAVE_TIME)
			stormEndAt = nil
			stormStartAt = os.clock() + INTERVAL
		end
	end)
end

-- Sends a raw alert payload to one player over the Alert remote.
-- Returns nothing; skips silently before init has created the remote.
function Storm.fireAlert(player: Player, data: { [string]: any })
	if alertEvent then
		alertEvent:FireClient(player, data)
	end
end

-- Sends a kind/text/colour notification to one player over the Alert remote.
-- Returns nothing; skips silently before init has created the remote.
function Storm.notify(player: Player, kind: string, text: string, color: Color3?)
	if alertEvent then
		alertEvent:FireClient(player, { kind = kind, text = text, color = color })
	end
end

-- Sends a kind/text/colour notification to every player over the Alert remote.
-- Returns nothing; skips silently before init has created the remote.
function Storm.notifyAll(kind: string, text: string, color: Color3?)
	if alertEvent then
		alertEvent:FireAllClients({ kind = kind, text = text, color = color })
	end
end

-- Sends a raw alert payload to every player over the Alert remote.
-- Returns nothing; skips silently before init has created the remote.
function Storm.fireBroadcast(data: { [string]: any })
	if alertEvent then
		alertEvent:FireAllClients(data)
	end
end

return Storm
-- (recorded build witness)
