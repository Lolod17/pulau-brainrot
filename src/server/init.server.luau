-- init.server: owns server bootstrap: remotes, wiring of every gameplay module, and the player join/leave/state-push loops.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- boot order: require Config, PlayerState, World, Bases, Carry, Dock, Pedestal, Lock, Steal, Rebirth, Save, Storm;
-- boot order: create Net remotes State, Notify, Alert;
-- boot order: init World anchors, Bases, Pedestal, Lock, Steal, Rebirth, Dock, Storm;
-- boot order: bind Pedestal, Lock, Steal, Rebirth;
-- boot order: connect PlayerAdded/PlayerRemoving, spawn onPlayer for present players, then start Pedestal, Lock, Dock, Storm, bind Save.
--!strict

-- boot order (as this file runs it, top to bottom):
--   1. world: require World, which builds the island once and returns the anchors (pierSpawns, plotCentres, pedestals, rebirth, centre);
--      the same pass requires Config, PlayerState, Bases, Carry, Dock, Pedestal, Lock, Steal, Rebirth, Save and Storm.
--   2. remotes: create ReplicatedStorage.Net with the State, Notify and Alert RemoteEvents.
--   3. bases: Bases.init(anchors) builds the base records on the plot centres.
--   4. pedestal, lock, steal: Pedestal.init, Lock.init, Steal.init set up slots, fences/boards and steal prompts.
--   5. rebirth: Rebirth.init(anchors.rebirth) builds the rebirth sign and prompt.
--   6. dock: Dock.init(anchors, workspace) sets up the pier spawn spots.
--   7. storm: Storm.init(anchors) sets up the storm cycle and notify remotes.
--   8. bind: Pedestal.bind, Lock.bind, Steal.bind, Rebirth.bind hook up the place/sell, lock, steal and rebirth prompts.
--   9. joins and leaves: PlayerAdded queues a serialised join (save: Save.load, PlayerState.create, Bases.assign,
--      Bases.bindCharacter, LoadCharacter, carry: Carry.restore, Pedestal.sync, first push); PlayerRemoving runs Save.save,
--      Carry.clear, Pedestal.clearBase, Steal.clear, Bases.release; players already present are queued too.
--  10. income tick: Pedestal.start starts the income loop (every Config.incomeTickRate seconds).
--  11. Lock.start (lock countdown ticker), Dock.start (restocking), Storm.start (storm cycle), Save.bind (save all on BindToClose).
--  12. state push loop: every Config.statePushRate seconds push each player's state and lock alert.
--
-- module contract (derived from the code below):
--   owns:    the ReplicatedStorage.Net folder and its State, Notify and Alert RemoteEvents; Players.CharacterAutoLoads = true;
--            the lastPushedCash table (per-player cash at the last state push, used for the payload "gain" field);
--            the joinQueue / joinRunning pair that serialises joins one player at a time; the onLeave teardown order;
--            the state push loop that fires State (serialized PlayerState + stormIn, basePosition, gain) and Alert (lock kind).
--   refuses: to finish a join for a player who left during Save.load (player.Parent ~= Players returns early);
--            to run a second join pump while one is running (joinRunning guard); to queue-process players no longer in Players;
--            to give a character, pedestal sync or first push to a player with no free base (warns, restores carry, returns);
--            to let a failed Save.load abort the join (warns and starts fresh with nil data);
--            to let one failing leave step, join or push stop the others (each wrapped in pcall and warned).
--   returns: nothing; this is the server entry Script, not a ModuleScript, so no module table is exported.

-- services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- module requires
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

-- character autoload
Players.CharacterAutoLoads = true

-- Net remotes folder
local net = Instance.new("Folder")
net.Name = "Net"
net.Parent = ReplicatedStorage

-- === remotes ===
-- remote factory
-- remote(name): creates a RemoteEvent with the given name and parents it under ReplicatedStorage.Net.
-- returns: the new RemoteEvent.
local function remote(name: string): RemoteEvent
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = net
	return event
end

-- remote events
local stateEvent = remote("State")
remote("Notify")
local alertEvent = remote("Alert")

-- === module setup ===
-- module init
local anchors = World
Bases.init(anchors)
Pedestal.init()
Lock.init()
Steal.init()
Rebirth.init(anchors.rebirth)
Dock.init(anchors, workspace)
Storm.init(anchors)

-- module prompt binding
Pedestal.bind()
Lock.bind()
Steal.bind()
Rebirth.bind()

-- last pushed cash per player
local lastPushedCash: { [Player]: number } = {}

-- === player lifecycle ===
-- state push to one player
-- push(player, previousCash?): serializes the player's state, adds stormIn, basePosition and gain, and fires State to them.
-- returns: nothing; does nothing when PlayerState.serialize yields no payload.
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

-- join handler
-- onPlayer(player): loads save data, creates state, assigns a base, spawns the character, restores carry, syncs pedestals, pushes and welcomes.
-- returns: nothing; returns early if the player left during load or no free base exists.
local function onPlayer(player: Player)
	local loaded: { [string]: any }? = nil
	local ok, result = pcall(function()
		return Save.load(player)
	end)
	if not ok then
		warn("[Save] join load failed, starting fresh: " .. tostring(result))
	end
	if player.Parent ~= Players then
		return
	end
	if ok and typeof(result) == "table" then
		loaded = result
	end
	PlayerState.create(player, loaded)
	local record = Bases.assign(player)
	if not record then
		warn("[Bases] no free base for " .. player.Name)
		Carry.restore(player)
		return
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

-- join queue state
local joinQueue: { Player } = {}
local joinRunning = false

-- join queue pump
-- pumpJoins(): drains joinQueue one player at a time, running onPlayer under pcall for players still in the game.
-- returns: nothing; exits immediately if a pump is already running.
local function pumpJoins()
	if joinRunning then
		return
	end
	joinRunning = true
	while #joinQueue > 0 do
		local player = table.remove(joinQueue, 1)
		if player.Parent == Players then
			local ok, err = pcall(onPlayer, player)
			if not ok then
				warn("[Server] join failed: " .. tostring(err))
			end
		end
	end
	joinRunning = false
end

-- join enqueue
-- queueJoin(player): appends the player to joinQueue and spawns a pumpJoins task.
-- returns: nothing.
local function queueJoin(player: Player)
	table.insert(joinQueue, player)
	task.spawn(pumpJoins)
end

-- leave handler
-- onLeave(player): saves, then clears carry, the base's pedestals, steal state, the base and player state, each step isolated by pcall.
-- returns: nothing.
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
-- PlayerAdded hook
Players.PlayerAdded:Connect(function(player)
	queueJoin(player)
end)

-- PlayerRemoving hook
Players.PlayerRemoving:Connect(function(player)
	local ok, err = pcall(onLeave, player)
	if not ok then
		warn("[Server] leave failed: " .. tostring(err))
	end
end)

-- queue players already present
for _, player in Players:GetPlayers() do
	queueJoin(player)
end

-- income tick, module loops and save binding
Pedestal.start()
Lock.start()
Dock.start()
Storm.start()
Save.bind()

-- === state push loop ===
-- state push loop
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
