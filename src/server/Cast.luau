-- Cast: owns the brainrot catalogue: part recipes per species, rarity weights, and roll/lookup helpers.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: Cast.entries, Cast.byId, Cast.byName, Cast.roll, Cast.getById, Cast.getByName
--!strict

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Ultra Rare"

export type PartSpec = {
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material,
}

export type Entry = {
	id: string,
	name: string,
	rarity: Rarity,
	price: number,
	income: number,
	threshold: number,
	aura: Color3,
	height: number,
	recipe: { PartSpec },
}

local BLOCK = Enum.PartType.Block
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local WEDGE = Enum.PartType.Wedge

local PLASTIC = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon

-- === part builders ===
-- part: packs name, shape, size, offset, color and optional material into one recipe record.
-- Returns a PartSpec table; material defaults to SmoothPlastic when omitted.
local function part(
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?
): PartSpec
	return {
		name = name,
		shape = shape,
		size = size,
		offset = offset,
		color = color,
		material = material or PLASTIC,
	}
end

-- facing: builds an offset placed at pos whose front (LookVector) points along direction.
-- Returns a CFrame from CFrame.lookAt(pos, pos + direction).
local function facing(pos: Vector3, direction: Vector3): CFrame
	return CFrame.lookAt(pos, pos + direction)
end

-- along: builds an offset at pos whose X axis runs along direction (for cylinder length), using a stable up hint.
-- Returns a CFrame from CFrame.fromMatrix with the unit direction as its right vector.
local function along(pos: Vector3, direction: Vector3): CFrame
	local axis = direction.Unit
	local hint = if math.abs(axis.Y) > 0.85 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	return CFrame.fromMatrix(pos, axis, axis:Cross(hint).Unit)
end

local SILVER = Color3.fromRGB(214, 220, 230)
local SKY = Color3.fromRGB(126, 198, 242)
local DEEP_SKY = Color3.fromRGB(42, 128, 198)
local CRAB = Color3.fromRGB(214, 52, 60)
local CRAB_DARK = Color3.fromRGB(148, 28, 38)
local GREEN = Color3.fromRGB(52, 148, 72)
local SHELL = Color3.fromRGB(124, 84, 46)
local OCTO = Color3.fromRGB(154, 66, 214)
local OCTO_DARK = Color3.fromRGB(108, 40, 164)
local SHARK = Color3.fromRGB(148, 154, 164)
local BELLY = Color3.fromRGB(230, 232, 236)
local WHALE = Color3.fromRGB(42, 58, 92)
local FLAME = Color3.fromRGB(255, 132, 28)
local GOLD = Color3.fromRGB(255, 204, 60)
local GOLD_DEEP = Color3.fromRGB(212, 152, 24)
local BLACK = Color3.fromRGB(22, 22, 26)
local WHITE = Color3.fromRGB(245, 245, 248)

-- === catalogue ===
-- tier table
-- name            rarity       price   income/s  threshold
-- Ikan Terbang    Common          50         5        450
-- Kepiting Disco  Uncommon       150        15        700
-- Penyu Turbo     Rare           400        40        880
-- Gurita DJ       Epic          1000       100        960
-- Hiu Bajak Laut  Legendary     3000       300        988
-- Paus Api        Mythic       12000      1200        998
-- Kraken Emas     Ultra Rare   50000     10000       1000
local ENTRIES: { Entry } = {
	{
		id = "ikan_terbang",
		name = "Ikan Terbang",
		rarity = "Common",
		price = 50,
		income = 5,
		threshold = 450,
		aura = Color3.fromRGB(206, 210, 218),
		height = 4,
		recipe = {
			part("Body", BALL, Vector3.new(3.6, 1.15, 1.05), CFrame.new(0, 2, 0), SILVER),
			part("Belly", BALL, Vector3.new(2.7, 0.62, 0.82), CFrame.new(0.15, 1.72, 0), WHITE),
			part("Snout", WEDGE, Vector3.new(0.72, 0.5, 1.15), facing(Vector3.new(2.15, 2.02, 0), Vector3.new(1, 0.05, 0)), SKY),
			part("WingL", WEDGE, Vector3.new(1.45, 0.12, 2.5), facing(Vector3.new(-0.15, 2.08, 1.55), Vector3.new(-0.1, 0.08, 1)), DEEP_SKY),
			part("WingR", WEDGE, Vector3.new(1.45, 0.12, 2.5), facing(Vector3.new(-0.15, 2.08, -1.55), Vector3.new(-0.1, 0.08, -1)), DEEP_SKY),
			part("WingTipL", WEDGE, Vector3.new(0.85, 0.1, 1.35), facing(Vector3.new(-0.45, 2.22, 3.15), Vector3.new(-0.25, 0.12, 1)), SKY),
			part("WingTipR", WEDGE, Vector3.new(0.85, 0.1, 1.35), facing(Vector3.new(-0.45, 2.22, -3.15), Vector3.new(-0.25, 0.12, -1)), SKY),
			part("TailTop", WEDGE, Vector3.new(0.85, 0.12, 1.25), facing(Vector3.new(-2.35, 2.35, 0), Vector3.new(-1, 0.75, 0)), DEEP_SKY),
			part("TailBot", WEDGE, Vector3.new(0.8, 0.12, 1.15), facing(Vector3.new(-2.3, 1.6, 0), Vector3.new(-1, -0.6, 0)), DEEP_SKY),
			part("Dorsal", WEDGE, Vector3.new(0.14, 0.55, 0.95), facing(Vector3.new(-0.25, 2.85, 0), Vector3.new(-0.15, 1, 0)), SKY),
			part("EyeL", BALL, Vector3.new(0.24, 0.24, 0.24), CFrame.new(1.25, 2.18, 0.38), BLACK),
			part("EyeR", BALL, Vector3.new(0.24, 0.24, 0.24), CFrame.new(1.25, 2.18, -0.38), BLACK),
		},
	},
	{
		id = "kepiting_disco",
		name = "Kepiting Disco",
		rarity = "Uncommon",
		price = 150,
		income = 15,
		threshold = 700,
		aura = Color3.fromRGB(46, 184, 138),
		height = 4,
		recipe = {
			part("Body", BALL, Vector3.new(2.5, 1.25, 2.7), CFrame.new(0, 1.35, 0), CRAB),
			part("Underside", BALL, Vector3.new(2.05, 0.6, 2.15), CFrame.new(0, 0.95, 0), Color3.fromRGB(245, 214, 186)),
			part("ClawL", BALL, Vector3.new(1.0, 0.82, 0.72), CFrame.new(1.15, 2.15, 1.2), CRAB_DARK),
			part("PincerLUp", WEDGE, Vector3.new(0.34, 0.22, 0.75), facing(Vector3.new(1.7, 2.6, 1.4), Vector3.new(0.5, 0.85, 0.25)), CRAB),
			part("PincerLLo", WEDGE, Vector3.new(0.34, 0.22, 0.7), facing(Vector3.new(1.65, 1.9, 1.35), Vector3.new(0.7, -0.15, 0.2)), CRAB),
			part("ClawR", BALL, Vector3.new(1.0, 0.82, 0.72), CFrame.new(1.15, 2.15, -1.2), CRAB_DARK),
			part("PincerRUp", WEDGE, Vector3.new(0.34, 0.22, 0.75), facing(Vector3.new(1.7, 2.6, -1.4), Vector3.new(0.5, 0.85, -0.25)), CRAB),
			part("PincerRLo", WEDGE, Vector3.new(0.34, 0.22, 0.7), facing(Vector3.new(1.65, 1.9, -1.35), Vector3.new(0.7, -0.15, -0.2)), CRAB),
			part("Leg1", CYL, Vector3.new(1.25, 0.2, 0.2), along(Vector3.new(0.15, 0.6, 1.35), Vector3.new(0.15, -0.7, 1)), CRAB_DARK),
			part("Leg2", CYL, Vector3.new(1.2, 0.2, 0.2), along(Vector3.new(-0.55, 0.58, 1.2), Vector3.new(-0.2, -0.65, 1)), CRAB_DARK),
			part("Leg3", CYL, Vector3.new(1.25, 0.2, 0.2), along(Vector3.new(0.15, 0.6, -1.35), Vector3.new(0.15, -0.7, -1)), CRAB_DARK),
			part("Leg4", CYL, Vector3.new(1.2, 0.2, 0.2), along(Vector3.new(-0.55, 0.58, -1.2), Vector3.new(-0.2, -0.65, -1)), CRAB_DARK),
			part("StalkL", CYL, Vector3.new(0.5, 0.12, 0.12), along(Vector3.new(0.85, 2.05, 0.32), Vector3.new(0.15, 1, 0.1)), BLACK),
			part("StalkR", CYL, Vector3.new(0.5, 0.12, 0.12), along(Vector3.new(0.85, 2.05, -0.32), Vector3.new(0.15, 1, -0.1)), BLACK),
			part("EyeL", BALL, Vector3.new(0.28, 0.28, 0.28), CFrame.new(1.0, 2.3, 0.4), BLACK),
			part("EyeR", BALL, Vector3.new(0.28, 0.28, 0.28), CFrame.new(1.0, 2.3, -0.4), BLACK),
			part("Pole", CYL, Vector3.new(1.35, 0.1, 0.1), along(Vector3.new(0, 2.3, 0), Vector3.new(0, 1, 0)), Color3.fromRGB(70, 70, 78), METAL),
			part("DiscoBall", BALL, Vector3.new(0.95, 0.95, 0.95), CFrame.new(0, 3.2, 0), Color3.fromRGB(232, 234, 240), METAL),
			part("Mirror1", BLOCK, Vector3.new(0.2, 0.2, 0.06), CFrame.new(0.05, 3.62, 0.28), Color3.fromRGB(255, 70, 90), NEON),
			part("Mirror2", BLOCK, Vector3.new(0.18, 0.18, 0.06), CFrame.new(-0.22, 3.5, 0.32), Color3.fromRGB(80, 200, 255), NEON),
			part("Mirror3", BLOCK, Vector3.new(0.18, 0.06, 0.18), CFrame.new(0.32, 3.45, 0.05), Color3.fromRGB(255, 230, 70), NEON),
			part("Tile1", BLOCK, Vector3.new(0.24, 0.24, 0.06), CFrame.new(0.15, 1.75, 1.28), Color3.fromRGB(255, 230, 60), NEON),
			part("Tile2", BLOCK, Vector3.new(0.22, 0.22, 0.06), CFrame.new(-0.4, 1.85, 1.18), Color3.fromRGB(255, 90, 170), NEON),
			part("Tile3", BLOCK, Vector3.new(0.22, 0.06, 0.22), CFrame.new(1.18, 1.6, 0.25), Color3.fromRGB(120, 255, 150), NEON),
			part("Tile4", BLOCK, Vector3.new(0.2, 0.2, 0.06), CFrame.new(-0.1, 1.55, -1.3), Color3.fromRGB(80, 160, 255), NEON),
		},
	},
	{
		id = "penyu_turbo",
		name = "Penyu Turbo",
		rarity = "Rare",
		price = 400,
		income = 40,
		threshold = 880,
		aura = Color3.fromRGB(32, 74, 214),
		height = 4,
		recipe = {
			part("Body", BALL, Vector3.new(2.3, 0.85, 2.5), CFrame.new(0, 1.0, 0), GREEN),
			part("Shell", BALL, Vector3.new(2.6, 1.4, 2.7), CFrame.new(0, 1.5, 0), SHELL),
			part("ShellCap", BALL, Vector3.new(1.7, 0.75, 1.8), CFrame.new(0, 2.05, 0), Color3.fromRGB(92, 62, 34)),
			part("Head", BALL, Vector3.new(0.9, 0.72, 0.82), CFrame.new(1.5, 1.2, 0), GREEN),
			part("Beak", WEDGE, Vector3.new(0.4, 0.28, 0.48), facing(Vector3.new(1.95, 1.12, 0), Vector3.new(1, -0.1, 0)), Color3.fromRGB(230, 190, 70)),
			part("FlipperFL", WEDGE, Vector3.new(0.72, 0.16, 1.65), facing(Vector3.new(0.9, 0.72, 1.25), Vector3.new(0.45, -0.1, 1)), Color3.fromRGB(36, 118, 58)),
			part("FlipperFR", WEDGE, Vector3.new(0.72, 0.16, 1.65), facing(Vector3.new(0.9, 0.72, -1.25), Vector3.new(0.45, -0.1, -1)), Color3.fromRGB(36, 118, 58)),
			part("FlipperBL", WEDGE, Vector3.new(0.6, 0.14, 1.25), facing(Vector3.new(-0.95, 0.68, 1.05), Vector3.new(-0.35, -0.1, 1)), Color3.fromRGB(36, 118, 58)),
			part("FlipperBR", WEDGE, Vector3.new(0.6, 0.14, 1.25), facing(Vector3.new(-0.95, 0.68, -1.05), Vector3.new(-0.35, -0.1, -1)), Color3.fromRGB(36, 118, 58)),
			part("StripeL", BLOCK, Vector3.new(2.35, 0.1, 0.26), CFrame.new(0, 2.28, 0.32), Color3.fromRGB(255, 236, 50), NEON),
			part("StripeR", BLOCK, Vector3.new(2.35, 0.1, 0.26), CFrame.new(0, 2.28, -0.32), Color3.fromRGB(255, 54, 54), NEON),
			part("Scute1", BLOCK, Vector3.new(0.55, 0.14, 0.55), CFrame.new(0.5, 2.05, 0.6), Color3.fromRGB(156, 112, 62)),
			part("Scute2", BLOCK, Vector3.new(0.5, 0.14, 0.5), CFrame.new(-0.45, 2.12, 0.55), Color3.fromRGB(168, 124, 70)),
			part("Scute3", BLOCK, Vector3.new(0.55, 0.14, 0.55), CFrame.new(-0.4, 2.08, -0.55), Color3.fromRGB(150, 106, 58)),
			part("Scute4", BLOCK, Vector3.new(0.48, 0.14, 0.48), CFrame.new(0.45, 2.02, -0.6), Color3.fromRGB(172, 128, 74)),
			part("EyeL", BALL, Vector3.new(0.16, 0.16, 0.16), CFrame.new(1.78, 1.4, 0.26), BLACK),
			part("EyeR", BALL, Vector3.new(0.16, 0.16, 0.16), CFrame.new(1.78, 1.4, -0.26), BLACK),
		},
	},
	{
		id = "gurita_dj",
		name = "Gurita DJ",
		rarity = "Epic",
		price = 1000,
		income = 100,
		threshold = 960,
		aura = Color3.fromRGB(168, 84, 255),
		height = 4,
		recipe = {
			part("Body", BALL, Vector3.new(2.35, 2.15, 2.2), CFrame.new(0, 2.55, 0), OCTO),
			part("Brow", BALL, Vector3.new(1.9, 0.7, 1.95), CFrame.new(0.1, 3.15, 0), OCTO_DARK),
			part("Tentacle1", CYL, Vector3.new(1.9, 0.36, 0.36), along(Vector3.new(0.35, 1.15, 0.85), Vector3.new(0.25, -1, 0.7)), OCTO),
			part("Tentacle2", CYL, Vector3.new(2.0, 0.34, 0.34), along(Vector3.new(-0.15, 1.05, 1.05), Vector3.new(-0.15, -1, 0.85)), OCTO_DARK),
			part("Tentacle3", CYL, Vector3.new(1.85, 0.32, 0.32), along(Vector3.new(-0.7, 1.1, 0.25), Vector3.new(-0.7, -1, 0.15)), OCTO),
			part("Tentacle4", CYL, Vector3.new(1.9, 0.36, 0.36), along(Vector3.new(0.35, 1.15, -0.85), Vector3.new(0.25, -1, -0.7)), OCTO),
			part("Tentacle5", CYL, Vector3.new(2.0, 0.34, 0.34), along(Vector3.new(-0.15, 1.05, -1.05), Vector3.new(-0.15, -1, -0.85)), OCTO_DARK),
			part("Tentacle6", CYL, Vector3.new(1.85, 0.32, 0.32), along(Vector3.new(-0.7, 1.1, -0.25), Vector3.new(-0.7, -1, -0.15)), OCTO),
			part("Arm", CYL, Vector3.new(1.45, 0.32, 0.32), along(Vector3.new(1.05, 2.85, 0.95), Vector3.new(0.7, 0.55, 0.45)), OCTO),
			part("Mixer", BLOCK, Vector3.new(0.72, 0.4, 0.52), CFrame.new(1.75, 3.4, 1.25), Color3.fromRGB(32, 32, 38)),
			part("Knob1", BALL, Vector3.new(0.18, 0.18, 0.18), CFrame.new(1.85, 3.64, 1.38), Color3.fromRGB(255, 80, 120), NEON),
			part("Knob2", BALL, Vector3.new(0.18, 0.18, 0.18), CFrame.new(1.62, 3.62, 1.1), Color3.fromRGB(80, 220, 255), NEON),
			part("Phones", BLOCK, Vector3.new(0.28, 0.28, 2.55), CFrame.new(0, 3.45, 0), BLACK),
			part("CupL", BALL, Vector3.new(0.55, 0.7, 0.7), CFrame.new(0.05, 3.2, 1.15), BLACK),
			part("CupR", BALL, Vector3.new(0.55, 0.7, 0.7), CFrame.new(0.05, 3.2, -1.15), BLACK),
			part("PadL", BALL, Vector3.new(0.28, 0.4, 0.4), CFrame.new(0.12, 3.2, 1.15), Color3.fromRGB(255, 70, 130), NEON),
			part("PadR", BALL, Vector3.new(0.28, 0.4, 0.4), CFrame.new(0.12, 3.2, -1.15), Color3.fromRGB(80, 210, 255), NEON),
			part("EyeL", BALL, Vector3.new(0.42, 0.42, 0.42), CFrame.new(0.95, 2.6, 0.42), WHITE),
			part("PupilL", BALL, Vector3.new(0.2, 0.2, 0.2), CFrame.new(1.12, 2.6, 0.48), BLACK),
			part("EyeR", BALL, Vector3.new(0.42, 0.42, 0.42), CFrame.new(0.95, 2.6, -0.42), WHITE),
			part("PupilR", BALL, Vector3.new(0.2, 0.2, 0.2), CFrame.new(1.12, 2.6, -0.48), BLACK),
		},
	},
	{
		id = "hiu_bajak_laut",
		name = "Hiu Bajak Laut",
		rarity = "Legendary",
		price = 3000,
		income = 300,
		threshold = 988,
		aura = Color3.fromRGB(255, 140, 32),
		height = 4,
		recipe = {
			part("Body", BALL, Vector3.new(4.3, 1.45, 1.4), CFrame.new(0, 1.7, 0), SHARK),
			part("Belly", BALL, Vector3.new(3.1, 0.75, 1.1), CFrame.new(0.15, 1.38, 0), BELLY),
			part("Snout", WEDGE, Vector3.new(0.95, 0.7, 1.25), facing(Vector3.new(2.45, 1.65, 0), Vector3.new(1, -0.05, 0)), SHARK),
			part("Dorsal", WEDGE, Vector3.new(0.16, 0.7, 1.35), facing(Vector3.new(-0.25, 2.7, 0), Vector3.new(-0.2, 1, 0)), Color3.fromRGB(118, 124, 134)),
			part("TailTop", WEDGE, Vector3.new(0.7, 0.16, 1.35), facing(Vector3.new(-2.55, 2.2, 0), Vector3.new(-0.8, 0.9, 0)), SHARK),
			part("TailBot", WEDGE, Vector3.new(0.55, 0.14, 0.9), facing(Vector3.new(-2.4, 1.2, 0), Vector3.new(-0.7, -0.55, 0)), SHARK),
			part("PecL", WEDGE, Vector3.new(0.55, 0.14, 1.25), facing(Vector3.new(0.55, 1.4, 0.95), Vector3.new(0.2, -0.25, 1)), SHARK),
			part("PecR", WEDGE, Vector3.new(0.55, 0.14, 1.25), facing(Vector3.new(0.55, 1.4, -0.95), Vector3.new(0.2, -0.25, -1)), SHARK),
			part("Jaw", BLOCK, Vector3.new(1.15, 0.4, 0.95), CFrame.new(1.45, 1.22, 0), BELLY),
			part("Tooth1", WEDGE, Vector3.new(0.14, 0.3, 0.16), facing(Vector3.new(2.05, 1.12, 0.28), Vector3.new(0.1, -1, 0)), WHITE),
			part("Tooth2", WEDGE, Vector3.new(0.14, 0.3, 0.16), facing(Vector3.new(2.08, 1.12, 0.08), Vector3.new(0.1, -1, 0)), WHITE),
			part("Tooth3", WEDGE, Vector3.new(0.14, 0.3, 0.16), facing(Vector3.new(2.08, 1.12, -0.12), Vector3.new(0.1, -1, 0)), WHITE),
			part("Tooth4", WEDGE, Vector3.new(0.14, 0.3, 0.16), facing(Vector3.new(2.05, 1.12, -0.32), Vector3.new(0.1, -1, 0)), WHITE),
			part("HatBrim", CYL, Vector3.new(0.14, 1.85, 1.85), along(Vector3.new(-0.05, 2.7, 0), Vector3.new(0, 1, 0)), BLACK),
			part("HatCrown", BLOCK, Vector3.new(0.85, 0.72, 0.85), CFrame.new(-0.1, 3.1, 0), BLACK),
			part("HatPoint", WEDGE, Vector3.new(0.55, 0.4, 0.7), facing(Vector3.new(0.4, 3.25, 0), Vector3.new(1, 0.25, 0)), BLACK),
			part("BrimL", WEDGE, Vector3.new(0.55, 0.12, 0.7), facing(Vector3.new(-0.15, 2.78, 0.95), Vector3.new(0.1, 0.05, 1)), BLACK),
			part("BrimR", WEDGE, Vector3.new(0.55, 0.12, 0.7), facing(Vector3.new(-0.15, 2.78, -0.95), Vector3.new(0.1, 0.05, -1)), BLACK),
			part("HatBand", BLOCK, Vector3.new(0.9, 0.16, 0.92), CFrame.new(-0.08, 2.82, 0), Color3.fromRGB(190, 40, 48)),
			part("Patch", BLOCK, Vector3.new(0.1, 0.38, 0.48), CFrame.new(1.4, 1.95, -0.58), BLACK),
			part("Strap", BLOCK, Vector3.new(0.08, 0.1, 1.25), CFrame.new(1.15, 2.05, 0) * CFrame.Angles(0, 0, math.rad(10)), BLACK),
			part("Eye", BALL, Vector3.new(0.28, 0.28, 0.28), CFrame.new(1.45, 1.95, 0.55), BLACK),
		},
	},
	{
		id = "paus_api",
		name = "Paus Api",
		rarity = "Mythic",
		price = 12000,
		income = 1200,
		threshold = 998,
		aura = Color3.fromRGB(176, 16, 24),
		height = 4,
		recipe = {
			part("Body", BALL, Vector3.new(4.8, 2.15, 2.15), CFrame.new(0, 1.85, 0), WHALE),
			part("Belly", BALL, Vector3.new(3.5, 1.15, 1.75), CFrame.new(0.2, 1.4, 0), Color3.fromRGB(214, 206, 190)),
			part("Back", BLOCK, Vector3.new(2.5, 0.32, 1.15), CFrame.new(-0.15, 2.9, 0), FLAME, NEON),
			part("Head", BALL, Vector3.new(1.7, 1.55, 1.75), CFrame.new(2.05, 1.8, 0), Color3.fromRGB(34, 48, 78)),
			part("FlukeL", WEDGE, Vector3.new(1.15, 0.28, 1.7), facing(Vector3.new(-2.7, 1.8, 1.15), Vector3.new(-0.35, 0.1, 1)), WHALE),
			part("FlukeR", WEDGE, Vector3.new(1.15, 0.28, 1.7), facing(Vector3.new(-2.7, 1.8, -1.15), Vector3.new(-0.35, 0.1, -1)), WHALE),
			part("FinL", WEDGE, Vector3.new(0.7, 0.22, 1.65), facing(Vector3.new(0.35, 1.45, 1.35), Vector3.new(0.15, -0.15, 1)), FLAME, NEON),
			part("FinR", WEDGE, Vector3.new(0.7, 0.22, 1.65), facing(Vector3.new(0.35, 1.45, -1.35), Vector3.new(0.15, -0.15, -1)), FLAME, NEON),
			part("Blowhole", CYL, Vector3.new(0.28, 0.4, 0.4), along(Vector3.new(0.75, 2.95, 0), Vector3.new(0, 1, 0)), BLACK),
			part("Flame1", WEDGE, Vector3.new(0.28, 0.45, 0.55), facing(Vector3.new(0.75, 3.35, 0), Vector3.new(0.05, 1, 0)), Color3.fromRGB(255, 220, 80), NEON),
			part("Flame2", WEDGE, Vector3.new(0.22, 0.4, 0.42), facing(Vector3.new(0.62, 3.55, 0.12), Vector3.new(-0.1, 1, 0.15)), FLAME, NEON),
			part("Flame3", WEDGE, Vector3.new(0.2, 0.38, 0.36), facing(Vector3.new(0.88, 3.5, -0.1), Vector3.new(0.15, 1, -0.1)), Color3.fromRGB(255, 70, 20), NEON),
			part("EyeL", BALL, Vector3.new(0.26, 0.26, 0.26), CFrame.new(2.4, 2.05, 0.58), Color3.fromRGB(255, 244, 220)),
			part("EyeR", BALL, Vector3.new(0.26, 0.26, 0.26), CFrame.new(2.4, 2.05, -0.58), Color3.fromRGB(255, 244, 220)),
		},
	},
	{
		id = "kraken_emas",
		name = "Kraken Emas",
		rarity = "Ultra Rare",
		price = 50000,
		income = 10000,
		threshold = 1000,
		aura = Color3.fromRGB(255, 206, 64),
		height = 6,
		recipe = {
			part("Body", BALL, Vector3.new(3.5, 2.7, 3.3), CFrame.new(0, 4.15, 0), GOLD, METAL),
			part("Brow", BALL, Vector3.new(2.9, 1.05, 2.9), CFrame.new(0.15, 4.9, 0), GOLD_DEEP, METAL),
			part("CrownBand", CYL, Vector3.new(0.32, 2.5, 2.5), along(Vector3.new(0, 5.65, 0), Vector3.new(0, 1, 0)), GOLD, NEON),
			part("CrownPoint1", WEDGE, Vector3.new(0.42, 0.55, 0.95), facing(Vector3.new(0.95, 6.2, 0), Vector3.new(0.15, 1, 0)), GOLD, NEON),
			part("CrownPoint2", WEDGE, Vector3.new(0.42, 0.55, 0.95), facing(Vector3.new(-0.45, 6.2, 0.8), Vector3.new(-0.1, 1, 0.12)), GOLD, NEON),
			part("CrownPoint3", WEDGE, Vector3.new(0.42, 0.55, 0.95), facing(Vector3.new(-0.45, 6.2, -0.8), Vector3.new(-0.1, 1, -0.12)), GOLD, NEON),
			part("Jewel1", BALL, Vector3.new(0.36, 0.36, 0.36), CFrame.new(0.85, 5.7, 0), Color3.fromRGB(255, 50, 80), NEON),
			part("Jewel2", BALL, Vector3.new(0.32, 0.32, 0.32), CFrame.new(-0.35, 5.75, 0.78), Color3.fromRGB(70, 160, 255), NEON),
			part("Jewel3", BALL, Vector3.new(0.32, 0.32, 0.32), CFrame.new(-0.35, 5.75, -0.78), Color3.fromRGB(110, 255, 150), NEON),
			part("Arm1a", CYL, Vector3.new(2.3, 0.62, 0.62), along(Vector3.new(1.15, 3.15, 1.05), Vector3.new(0.9, -0.55, 0.7)), GOLD, METAL),
			part("Arm1b", CYL, Vector3.new(2.0, 0.46, 0.46), along(Vector3.new(2.5, 1.95, 2.05), Vector3.new(0.55, -1.1, 0.45)), GOLD_DEEP, METAL),
			part("Arm2a", CYL, Vector3.new(2.4, 0.66, 0.66), along(Vector3.new(0.15, 2.95, 1.55), Vector3.new(0.1, -0.7, 1)), GOLD_DEEP, METAL),
			part("Arm2b", CYL, Vector3.new(2.05, 0.48, 0.48), along(Vector3.new(0.45, 1.7, 2.85), Vector3.new(0.25, -1.05, 0.7)), GOLD, METAL),
			part("Arm3a", CYL, Vector3.new(2.2, 0.56, 0.56), along(Vector3.new(-1.15, 3.05, 0.95), Vector3.new(-0.95, -0.5, 0.55)), GOLD, METAL),
			part("Arm3b", CYL, Vector3.new(1.95, 0.44, 0.44), along(Vector3.new(-2.45, 1.9, 1.7), Vector3.new(-0.6, -1.1, 0.35)), GOLD_DEEP, METAL),
			part("Arm4a", CYL, Vector3.new(2.3, 0.62, 0.62), along(Vector3.new(1.15, 3.15, -1.05), Vector3.new(0.9, -0.55, -0.7)), GOLD, METAL),
			part("Arm4b", CYL, Vector3.new(2.0, 0.46, 0.46), along(Vector3.new(2.5, 1.95, -2.05), Vector3.new(0.55, -1.1, -0.45)), GOLD_DEEP, METAL),
			part("Arm5a", CYL, Vector3.new(2.4, 0.66, 0.66), along(Vector3.new(0.15, 2.95, -1.55), Vector3.new(0.1, -0.7, -1)), GOLD_DEEP, METAL),
			part("Arm5b", CYL, Vector3.new(2.05, 0.48, 0.48), along(Vector3.new(0.45, 1.7, -2.85), Vector3.new(0.25, -1.05, -0.7)), GOLD, METAL),
			part("Arm6a", CYL, Vector3.new(2.2, 0.56, 0.56), along(Vector3.new(-1.15, 3.05, -0.95), Vector3.new(-0.95, -0.5, -0.55)), GOLD, METAL),
			part("Arm6b", CYL, Vector3.new(1.95, 0.44, 0.44), along(Vector3.new(-2.45, 1.9, -1.7), Vector3.new(-0.6, -1.1, -0.35)), GOLD_DEEP, METAL),
			part("Sucker1", BALL, Vector3.new(0.26, 0.26, 0.26), CFrame.new(1.5, 2.7, 1.4), Color3.fromRGB(120, 72, 22)),
			part("Sucker2", BALL, Vector3.new(0.22, 0.22, 0.22), CFrame.new(2.7, 1.55, 2.2), Color3.fromRGB(120, 72, 22)),
			part("Sucker3", BALL, Vector3.new(0.26, 0.26, 0.26), CFrame.new(0.3, 2.45, 2.15), Color3.fromRGB(120, 72, 22)),
			part("Sucker4", BALL, Vector3.new(0.22, 0.22, 0.22), CFrame.new(0.7, 1.35, 3.05), Color3.fromRGB(120, 72, 22)),
			part("Sucker5", BALL, Vector3.new(0.24, 0.24, 0.24), CFrame.new(-1.6, 2.6, 1.25), Color3.fromRGB(120, 72, 22)),
			part("Sucker6", BALL, Vector3.new(0.22, 0.22, 0.22), CFrame.new(-2.6, 1.5, 1.85), Color3.fromRGB(120, 72, 22)),
			part("Sucker7", BALL, Vector3.new(0.26, 0.26, 0.26), CFrame.new(1.5, 2.7, -1.4), Color3.fromRGB(120, 72, 22)),
			part("Sucker8", BALL, Vector3.new(0.22, 0.22, 0.22), CFrame.new(2.7, 1.55, -2.2), Color3.fromRGB(120, 72, 22)),
			part("Sucker9", BALL, Vector3.new(0.26, 0.26, 0.26), CFrame.new(0.3, 2.45, -2.15), Color3.fromRGB(120, 72, 22)),
			part("Sucker10", BALL, Vector3.new(0.22, 0.22, 0.22), CFrame.new(0.7, 1.35, -3.05), Color3.fromRGB(120, 72, 22)),
			part("Sucker11", BALL, Vector3.new(0.24, 0.24, 0.24), CFrame.new(-1.6, 2.6, -1.25), Color3.fromRGB(120, 72, 22)),
			part("Sucker12", BALL, Vector3.new(0.22, 0.22, 0.22), CFrame.new(-2.6, 1.5, -1.85), Color3.fromRGB(120, 72, 22)),
			part("EyeL", BALL, Vector3.new(0.58, 0.58, 0.58), CFrame.new(1.4, 4.25, 0.72), Color3.fromRGB(255, 248, 220), NEON),
			part("PupilL", BALL, Vector3.new(0.26, 0.26, 0.26), CFrame.new(1.66, 4.25, 0.84), BLACK),
			part("EyeR", BALL, Vector3.new(0.58, 0.58, 0.58), CFrame.new(1.4, 4.25, -0.72), Color3.fromRGB(255, 248, 220), NEON),
			part("PupilR", BALL, Vector3.new(0.26, 0.26, 0.26), CFrame.new(1.66, 4.25, -0.84), BLACK),
			part("Beak", WEDGE, Vector3.new(0.5, 0.55, 0.55), facing(Vector3.new(1.75, 3.6, 0), Vector3.new(1, -0.15, 0)), Color3.fromRGB(96, 62, 24)),
		},
	},
}

local idLookup: { [string]: Entry } = {}
local nameLookup: { [string]: Entry } = {}
for _, entry in ENTRIES do
	idLookup[entry.id] = entry
	nameLookup[entry.name] = entry
end

-- === module table ===
-- Owns: the static ENTRIES catalogue (seven species with id, name, rarity, price, income,
--   roll threshold, aura colour, height and part recipe) plus the idLookup / nameLookup
--   indexes built from it once at load time.
-- Refuses: building any Instance (recipes are plain PartSpec data for other modules to
--   assemble), mutating or adding entries at runtime (no setter exists), and resolving
--   unknown ids or names (getById / getByName return nil instead of guessing).
-- Returns: the Cast table exposing entries, byId, byName, and the roll / getById /
--   getByName functions defined below.
local Cast = {
	entries = ENTRIES,
	byId = idLookup,
	byName = nameLookup,
}

-- === public api ===
-- roll: draws n in 1..1000 and returns the first entry (in table order) whose threshold >= n,
-- so Common 1-450, Uncommon 451-700, Rare 701-880, Epic 881-960, Legendary 961-988, Mythic 989-998, Ultra Rare 999-1000.
-- Cast.roll: picks one catalogue species by weighted rarity, using the given Random or math.random.
-- Returns an Entry; falls back to the last entry (Kraken Emas) if no threshold matches.
function Cast.roll(rng: Random?): Entry
	local n = if rng then rng:NextInteger(1, 1000) else math.random(1, 1000)
	for _, entry in ENTRIES do
		if n <= entry.threshold then
			return entry
		end
	end
	return ENTRIES[#ENTRIES]
end

-- Cast.getById: looks up a catalogue species by its snake_case id (e.g. "paus_api").
-- Returns the matching Entry, or nil when the id is unknown.
function Cast.getById(id: string): Entry?
	return idLookup[id]
end

-- Cast.getByName: looks up a catalogue species by its display name (e.g. "Paus Api").
-- Returns the matching Entry, or nil when the name is unknown.
function Cast.getByName(name: string): Entry?
	return nameLookup[name]
end

return Cast
-- (recorded build witness)
