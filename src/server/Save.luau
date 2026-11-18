-- Save: owns DataStore persistence of player state on join, leave, and server shutdown.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: Save.load, Save.save, Save.saveAll, Save.bind, Save.startingCash
-- contract:
--   Owns: the lazily fetched "PulauBrainrot_v1" DataStore (looked up once), keys "p_" .. UserId.
--   pcall wrapped: GetDataStore (failure -> warn, store nil, session-only), GetAsync (failure -> warn, load returns nil),
--   SetAsync (failure -> warn, save returns false), each Save.save inside saveAll (failure -> warn, skip player), BindToClose (failure -> warn).
--   Validates: load returns the stored value only if it is a table; save needs a store and a PlayerState.serialize payload, stamps version = 1.
--   Returns: load -> table or nil; save -> boolean; startingCash -> Config.startingCash.
--   Refuses: retrying GetDataStore after the first attempt (storeReady latches even on failure); loading non-table
--   stored values (returns nil); saving with no store or no serialize payload (returns false); letting any DataStore
--   or BindToClose error escape to the caller (all are pcall wrapped and warned).
--   Does not own: the shape of player data (PlayerState.serialize builds it) or the starting cash value (Config owns it).
--   saveAll and bind return nothing; getStore is private and returns the cached store or nil.
--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Config = require(script.Parent:WaitForChild("Config"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))

local STORE_NAME = "PulauBrainrot_v1"
local KEY_PREFIX = "p_"

local store: any = nil
local storeReady = false

-- getStore: fetches the "PulauBrainrot_v1" DataStore once under pcall, warning and caching nil on failure.
-- Returns the cached DataStore, or nil when DataStoreService is unavailable (session-only data).
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

-- Save.load: reads the player's "p_" .. UserId record via a pcall wrapped GetAsync, warning on failure.
-- Returns the stored table, or nil when there is no store, the read fails, or the value is not a table.
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

-- Save.save: serializes the player via PlayerState, stamps version = 1, and writes it with a pcall wrapped SetAsync.
-- Returns true on a successful write; false when there is no store, no payload, or SetAsync fails.
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

-- Save.saveAll: calls Save.save for every connected player, each under pcall so one error skips only that player.
-- Returns nothing; per-player save results are discarded and errors are only warned.
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

-- Save.bind: registers Save.saveAll as a game:BindToClose handler, warning if registration is unavailable.
-- Returns nothing.
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

-- Save.startingCash: exposes the configured starting cash for new or unsaved players.
-- Returns Config.startingCash as a number.
function Save.startingCash(): number
	return Config.startingCash
end

return Save
