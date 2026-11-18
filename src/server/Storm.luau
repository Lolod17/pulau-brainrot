-- Storm: owns the periodic storm cycle and the storm/notify remotes that broadcast to clients.
-- Server gameplay is authoritative; the client only renders and sends intents.
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

local function rarityWeights(): { [string]: number }
	local weights: { [string]: number } = {}
	local prev = 0
	for _, tier in Config.tiers do
		weights[tier.rarity] = (tier.threshold - prev) / 1000
		prev = tier.threshold
	end
	return weights
end

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

local function chooseCharacter(position: Vector3): any?
	local rarity = rollFrom(tiersForDistance(position))
	local pool = poolFor(rarity)
	if #pool == 0 then
		return nil
	end
	return pool[math.random(1, #pool)]
end

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
		if opened then
			return
		end
		opened = true
		local choice = chooseCharacter(position)
		if choice then
			pcall(function()
				local state = PlayerState.get(player)
				if state and not state.carrying then
					PlayerState.setCarrying(player, PlayerState.slotFromEntry(choice))
					Carry.attach(player, state.carrying :: any)
				end
			end)
			if alertEvent then
				alertEvent:FireClient(player, {
					kind = "placed",
					text = "You opened a shell: " .. tostring(choice.name),
					tier = choice.rarity,
					color = choice.aura,
				})
			end
		end
		local burst = alertEvent
		if burst then
			burst:FireAllClients({
				kind = "shell-opened",
				position = position,
				tier = choice and choice.rarity or "Common",
			})
		end
		part:Destroy()
	end)

	task.delay(SHELL_LIFETIME, function()
		if connection then
			connection:Disconnect()
		end
		if part.Parent then
			part:Destroy()
		end
	end)
end

local stormStartAt: number? = nil
local stormEndAt: number? = nil

local function broadcastPhase(phase: string, payload: { [string]: any }?)
	local data = payload or {}
	data.phase = phase
	if stormEvent then
		stormEvent:FireAllClients(data)
	end
end

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

local function onPier(position: Vector3): boolean
	local distance = Vector3.new(position.X, 0, position.Z) - Vector3.new(pierCenter.X, 0, pierCenter.Z)
	local probe = Vector3.new(distance.X, 0, distance.Z).Magnitude
	return probe <= 48
end

local function sweep()
	resolvePier()
	local swept = 0
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") then
			local position = root.Position
			local state = PlayerState.get(player)
			local carrying = state ~= nil and state.carrying ~= nil
			local outside = not inOwnBase(player, position)
			local onDock = onPier(position)
			if onDock or (carrying and outside) then
				local spot = position
				pcall(function()
					Carry.clear(player)
				end)
				character:Destroy()
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

local function waveSweep()
	broadcastPhase("wave", { toward = "island" })
	task.wait(WAVE_TIME)
	sweep()
end

local function darken(duration: number)
	local tween = TweenService:Create(Lighting, TweenInfo.new(duration), {
		Ambient = Color3.fromRGB(64, 70, 86),
		OutdoorAmbient = Color3.fromRGB(70, 78, 96),
		Brightness = 1.4,
	})
	tween:Play()
end

local function restore()
	local tween = TweenService:Create(Lighting, TweenInfo.new(4), {
		Ambient = Color3.fromRGB(158, 184, 204),
		OutdoorAmbient = Color3.fromRGB(168, 194, 214),
		Brightness = 3.2,
	})
	tween:Play()
end

local function runStorm()
	darken(WARN_TIME)
	broadcastPhase("warning", { seconds = WARN_TIME })
	Storm.notifyAll("storm-warning", "STORM INBOUND - 10s", Color3.fromRGB(120, 190, 255))
	task.wait(WARN_TIME)
	waveSweep()
	broadcastPhase("clear", { seconds = INTERVAL - WARN_TIME - WAVE_TIME })
	restore()
end

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

function Storm.bind()
	return Storm
end

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

function Storm.fireAlert(player: Player, data: { [string]: any })
	if alertEvent then
		alertEvent:FireClient(player, data)
	end
end

function Storm.notify(player: Player, kind: string, text: string, color: Color3?)
	if alertEvent then
		alertEvent:FireClient(player, { kind = kind, text = text, color = color })
	end
end

function Storm.notifyAll(kind: string, text: string, color: Color3?)
	if alertEvent then
		alertEvent:FireAllClients({ kind = kind, text = text, color = color })
	end
end

function Storm.fireBroadcast(data: { [string]: any })
	if alertEvent then
		alertEvent:FireAllClients(data)
	end
end

return Storm
