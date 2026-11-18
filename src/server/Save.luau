-- Save: owns DataStore persistence of player state on join, leave, and server shutdown.
-- Server gameplay is authoritative; the client only renders and sends intents.
--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Config = require(script.Parent:WaitForChild("Config"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))

local STORE_NAME = "PulauBrainrot_v1"
local KEY_PREFIX = "p_"

local store: any = nil
local storeReady = false

local function getStore(): any
	if storeReady then
		return store
	end
	storeReady = true
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		store = nil
		warn("[Save] DataStore unavailable, session-only data: " .. tostring(result))
	end
	return store
end

local Save = {}

function Save.load(player: Player): { [string]: any }?
	local dataStore = getStore()
	if not dataStore then
		return nil
	end
	local key = KEY_PREFIX .. tostring(player.UserId)
	local ok, result = pcall(function()
		return dataStore:GetAsync(key)
	end)
	if not ok then
		warn("[Save] load failed for " .. tostring(player.UserId) .. ": " .. tostring(result))
		return nil
	end
	if typeof(result) ~= "table" then
		return nil
	end
	return result
end

function Save.save(player: Player): boolean
	local dataStore = getStore()
	if not dataStore then
		return false
	end
	local payload = PlayerState.serialize(player)
	if not payload then
		return false
	end
	payload.version = 1
	local key = KEY_PREFIX .. tostring(player.UserId)
	local ok, err = pcall(function()
		dataStore:SetAsync(key, payload)
	end)
	if not ok then
		warn("[Save] save failed for " .. tostring(player.UserId) .. ": " .. tostring(err))
		return false
	end
	return true
end

function Save.saveAll()
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(function()
			Save.save(player)
		end)
		if not ok then
			warn("[Save] saveAll skipped " .. player.Name .. ": " .. tostring(err))
		end
	end
end

function Save.bind()
	local ok, err = pcall(function()
		game:BindToClose(function()
			Save.saveAll()
		end)
	end)
	if not ok then
		warn("[Save] BindToClose unavailable: " .. tostring(err))
	end
end

function Save.startingCash(): number
	return Config.startingCash
end

return Save
