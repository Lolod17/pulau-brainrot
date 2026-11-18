-- init.server: owns server bootstrap: remotes, wiring of every gameplay module, and the player join/leave/state-push loops.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- boot order: require Config, PlayerState, World, Bases, Carry, Dock, Pedestal, Lock, Steal, Rebirth, Save, Storm;
-- boot order: create Net remotes State, Notify, Alert;
-- boot order: init World anchors, Bases, Pedestal, Lock, Steal, Rebirth, Dock, Storm;
-- boot order: bind Pedestal, Lock, Steal, Rebirth;
-- boot order: connect PlayerAdded/PlayerRemoving, spawn onPlayer for present players, then start Pedestal, Lock, Dock, Storm, bind Save.
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script:WaitForChild("Config"))
local PlayerState = require(script:WaitForChild("PlayerState"))
local World = require(script:WaitForChild("World"))
local Bases = require(script:WaitForChild("Bases"))
local Carry = require(script:WaitForChild("Carry"))
local Dock = require(script:WaitForChild("Dock"))
local Pedestal = require(script:WaitForChild("Pedestal"))
local Lock = require(script:WaitForChild("Lock"))
local Steal = require(script:WaitForChild("Steal"))
local Rebirth = require(script:WaitForChild("Rebirth"))
local Save = require(script:WaitForChild("Save"))
local Storm = require(script:WaitForChild("Storm"))

Players.CharacterAutoLoads = true

local net = Instance.new("Folder")
net.Name = "Net"
net.Parent = ReplicatedStorage

-- === remotes ===
local function remote(name: string): RemoteEvent
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = net
	return event
end

local stateEvent = remote("State")
remote("Notify")
local alertEvent = remote("Alert")

-- === module setup ===
local anchors = World
Bases.init(anchors)
Pedestal.init()
Lock.init()
Steal.init()
Rebirth.init(anchors.rebirth)
Dock.init(anchors, workspace)
Storm.init(anchors)

Pedestal.bind()
Lock.bind()
Steal.bind()
Rebirth.bind()

local lastPushedCash: { [Player]: number } = {}

-- === player lifecycle ===
local function push(player: Player, previousCash: number?)
	local payload = PlayerState.serialize(player)
	if payload then
		payload.stormIn = Storm.secondsUntilNext()
		local record = Bases.get(player)
		if record and record.centre then
			payload.basePosition = record.centre.Position
		end
		payload.gain = math.max(0, math.floor((payload.cash or 0) - (previousCash or 0)))
		stateEvent:FireClient(player, payload)
	end
end

local function onPlayer(player: Player)
	local loaded: { [string]: any }? = nil
	local ok, result = pcall(function()
		return Save.load(player)
	end)
	if ok and typeof(result) == "table" then
		loaded = result
	elseif not ok then
		warn("[Save] join load failed, starting fresh: " .. tostring(result))
	end
	PlayerState.create(player, loaded)
	local record = Bases.assign(player)
	if not record then
		warn("[Bases] no free base for " .. player.Name)
	end
	Bases.bindCharacter(player)
	player:LoadCharacter()
	Carry.restore(player)
	Pedestal.sync(player)
	local startState = PlayerState.get(player)
	lastPushedCash[player] = if startState then startState.cash else nil
	push(player)
	Storm.notify(player, "join", "Welcome to Pulau Brainrot")
end

local function onLeave(player: Player)
	local ok, err = pcall(function()
		Save.save(player)
	end)
	if not ok then
		warn("[Save] leave save failed: " .. tostring(err))
	end
	pcall(function()
		Carry.clear(player)
	end)
	pcall(function()
		local state = PlayerState.get(player)
		if state and state.baseIndex then
			Pedestal.clearBase(state.baseIndex)
		end
	end)
	pcall(function()
		Steal.clear(player)
	end)
	pcall(function()
		Bases.release(player)
	end)
	PlayerState.clear(player)
	lastPushedCash[player] = nil
end

-- === player lifecycle ===
Players.PlayerAdded:Connect(function(player)
	local ok, err = pcall(onPlayer, player)
	if not ok then
		warn("[Server] join failed: " .. tostring(err))
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local ok, err = pcall(onLeave, player)
	if not ok then
		warn("[Server] leave failed: " .. tostring(err))
	end
end)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end

Pedestal.start()
Lock.start()
Dock.start()
Storm.start()
Save.bind()

-- === state push loop ===
task.spawn(function()
	while true do
		task.wait(Config.statePushRate)
		for _, player in Players:GetPlayers() do
			local previous = lastPushedCash[player]
			local ok, err = pcall(push, player, previous)
			if not ok then
				warn("[Server] state push failed: " .. tostring(err))
			end
			local record = Bases.get(player)
			local state = PlayerState.get(player)
			if state then
				lastPushedCash[player] = state.cash
			end
			if record then
				local left = math.max(0, record.lockedUntil - os.clock())
				alertEvent:FireClient(player, {
					kind = "lock",
					locked = left > 0,
					seconds = math.ceil(left),
				})
			end
		end
	end
end)
