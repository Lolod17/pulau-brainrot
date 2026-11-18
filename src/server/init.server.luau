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

Players.CharacterAutoLoads = true

local net = Instance.new("Folder")
net.Name = "Net"
net.Parent = ReplicatedStorage

local function remote(name: string): RemoteEvent
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = net
	return event
end

local stateEvent = remote("State")
remote("Notify")

local anchors = World
Bases.init(anchors)
Pedestal.init()
Lock.init()
Steal.init()
Rebirth.init(anchors.rebirth)
Dock.init(anchors, workspace)

Pedestal.bind()
Lock.bind()
Steal.bind()
Rebirth.bind()

local function push(player: Player)
	local payload = PlayerState.serialize(player)
	if payload then
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
	push(player)
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
end

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
Save.bind()

task.spawn(function()
	while true do
		task.wait(Config.statePushRate)
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(push, player)
			if not ok then
				warn("[Server] state push failed: " .. tostring(err))
			end
		end
	end
end)
