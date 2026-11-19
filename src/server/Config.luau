-- Config: owns the shared gameplay tuning numbers every other server module reads.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: Config (the table's fields: startingCash, incomeTickRate, sellFraction, lockDuration, rebirthBaseCost, rebirthGrowth, rebirthIncomeBonus, cashAfterRebirth, dockSpawnCap, dockSpawnInterval, stealHold, stealCooldown, statePushRate, slotCount, baseCount, carryHeight, tiers)
-- contract:
--   Owns: one static table, no functions, no validation; returns the table as-is.
--   Tunables: startingCash 200, incomeTickRate 0.25, sellFraction 0.5, lockDuration 30, rebirthBaseCost 100000, rebirthGrowth 2,
--   rebirthIncomeBonus 0.5, cashAfterRebirth 100, dockSpawnCap 6, dockSpawnInterval 8, stealHold 2.5, stealCooldown 4, statePushRate 0.25,
--   slotCount 6, baseCount 8, carryHeight 4; tiers (rarity/threshold): Common 450, Uncommon 700, Rare 880, Epic 960, Legendary 988, Mythic 998, Ultra Rare 1000.
-- module block:
--   Owns: the single literal Config table (sixteen scalar tunables plus the ordered tiers list of seven rarity/threshold pairs).
--   Refuses: any behaviour at all; it requires no other module, defines no functions, holds no runtime state,
--   does not validate, clamp or freeze its values, and does not touch players, instances or the client.
--   Returns: the Config table itself (a plain mutable table shared by reference with every requiring module).
--   Functions: none at top level, so there are no per-function comments to add; tiers are ordered by ascending threshold.
--!strict

local Config = {
	startingCash = 200,
	incomeTickRate = 0.25,
	sellFraction = 0.5,
	lockDuration = 30,
	rebirthBaseCost = 100000,
	rebirthGrowth = 2,
	rebirthIncomeBonus = 0.5,
	cashAfterRebirth = 100,
	dockSpawnCap = 6,
	dockSpawnInterval = 8,
	stealHold = 2.5,
	stealCooldown = 4,
	statePushRate = 0.25,
	slotCount = 6,
	baseCount = 8,
	carryHeight = 4,
	tiers = {
		{ rarity = "Common", threshold = 450 },
		{ rarity = "Uncommon", threshold = 700 },
		{ rarity = "Rare", threshold = 880 },
		{ rarity = "Epic", threshold = 960 },
		{ rarity = "Legendary", threshold = 988 },
		{ rarity = "Mythic", threshold = 998 },
		{ rarity = "Ultra Rare", threshold = 1000 },
	},
}

return Config
-- (recorded build witness)
