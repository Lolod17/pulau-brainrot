-- World: owns generating the island map once at startup and returning the anchors other modules wire to.
-- Server gameplay is authoritative; the client only renders and sends intents.
-- Public API: World (build() returns the anchors table: pierSpawns, plotCentres, pedestals, rebirth, centre)
-- island layout
--   eight plot centres (y = PLOT_Y = 2.2, PLOT = 34 studs square), from build():
--     west, x = -118: Base1 z = -8, Base2 z = 34, Base3 z = 76, Base4 z = 118
--     east, x =  118: Base5 z = -8, Base6 z = 34, Base7 z = 76, Base8 z = 118
--   pedestal grid: 3 columns x 2 rows per base, spacing GAP = 7 studs both ways,
--     in hut space at x = col * 7 (col -1..1), z = -12.2 - row * 7 (row 0..1)
--   pier spawn x: -16 (PierSpawn1) and 16 (PierSpawn2), pad at z = PIER_Z - 16 = -19
--   island radius: no radius constant exists; the land is irregular overlapping slabs.
--     Outermost sand slab centres: SpitWestTip (-198, 92), SpitSouthTip (48, 204),
--     ShelfE (150, 14), ShelfNE (140, -48). Sea plane is 980 x 980 centred on (0, 40).
--   plot size: PLOT = 34 x 34 studs (0.8 thick); pedestals built: 8 bases x 6 = 48 in total
--   sea and land are anchored parts (create sets Anchored = true); applyLighting moves Baseplate to y = -30
--!strict

local Lighting = game:GetService("Lighting")

type Anchors = {
	pierSpawns: { BasePart },
	plotCentres: { BasePart },
	pedestals: { { BasePart } },
	rebirth: BasePart,
	centre: BasePart,
}

local WALK_Y = 3
local BEACH_Y = 2
local SHORE_Y = 1
local GRASS_Y = 2.5
local PLOT_Y = 2.2
local SEA_Y = 0
local SEABED_Y = -2
local PIER_WIDTH = 12
local PIER_LENGTH = 90
local PIER_Z = -3
local PLOT = 34
local GAP = 7

local SAND = Color3.fromRGB(232, 206, 150)
local SAND_DARK = Color3.fromRGB(198, 164, 108)
local SAND_WET = Color3.fromRGB(176, 146, 98)
local GRASS = Color3.fromRGB(86, 168, 72)
local GRASS_DARK = Color3.fromRGB(58, 128, 52)
local WOOD = Color3.fromRGB(150, 98, 52)
local WOOD_DARK = Color3.fromRGB(102, 64, 34)
local WOOD_LIGHT = Color3.fromRGB(190, 136, 76)
local PLANKS = Color3.fromRGB(204, 158, 96)
local STRAW = Color3.fromRGB(216, 178, 72)
local STRAW_DARK = Color3.fromRGB(176, 136, 46)
local BAMBOO = Color3.fromRGB(124, 166, 62)
local BAMBOO_DARK = Color3.fromRGB(78, 114, 40)
local STONE = Color3.fromRGB(164, 158, 148)
local STONE_DARK = Color3.fromRGB(108, 102, 96)
local ROCK = Color3.fromRGB(140, 132, 122)
local ROCK_DARK = Color3.fromRGB(92, 86, 80)
local SEA = Color3.fromRGB(42, 186, 196)
local SEABED = Color3.fromRGB(18, 72, 82)
local SHALLOW = Color3.fromRGB(186, 154, 96)
local PINK = Color3.fromRGB(240, 118, 146)
local ORANGE = Color3.fromRGB(240, 148, 68)
local TEAL = Color3.fromRGB(64, 196, 174)
local LEAF = Color3.fromRGB(48, 142, 58)
local LEAF_LIT = Color3.fromRGB(122, 192, 74)
local TRUNK = Color3.fromRGB(134, 88, 48)
local TRUNK_DARK = Color3.fromRGB(102, 66, 36)
local FLOWER_PINK = Color3.fromRGB(236, 104, 140)
local FLOWER_YELLOW = Color3.fromRGB(244, 202, 68)
local FLOWER_RED = Color3.fromRGB(208, 60, 66)
local ROPE = Color3.fromRGB(176, 142, 96)
local LAMP = Color3.fromRGB(255, 214, 132)
local WHITE = Color3.fromRGB(244, 240, 230)
local RED = Color3.fromRGB(196, 62, 60)
local GOLD = Color3.fromRGB(255, 196, 64)
-- One accent colour per base so the eight plots read as distinct places from the air.
local ACCENT = {
	Color3.fromRGB(255, 120, 90),
	Color3.fromRGB(255, 190, 70),
	Color3.fromRGB(150, 220, 110),
	Color3.fromRGB(90, 200, 200),
	Color3.fromRGB(110, 160, 255),
	Color3.fromRGB(180, 140, 255),
	Color3.fromRGB(255, 130, 200),
	Color3.fromRGB(205, 205, 212),
}
local BLUE = Color3.fromRGB(58, 128, 204)
local BUOY = Color3.fromRGB(230, 92, 60)
local INK = Color3.fromRGB(62, 36, 18)

local decorCount = 0

-- === geometry helpers ===
-- Builds one anchored, smooth-surfaced Part from the given name, size, CFrame, colour, material and options, optionally tagged Decor.
-- Returns the new Part (and bumps decorCount when decorated).
local function create(
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	shape: Enum.PartType?,
	transparency: number?,
	canCollide: boolean?,
	decorated: boolean?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Shape = shape or Enum.PartType.Block
	p.Transparency = transparency or 0
	p.CanCollide = if canCollide == nil then true else canCollide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	if decorated then
		p:SetAttribute("Decor", true)
		decorCount += 1
	end
	return p
end

-- Builds a structural (non-decor) Part by forwarding to create with decorated = false.
-- Returns the new Part.
local function part(
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	shape: Enum.PartType?,
	transparency: number?,
	canCollide: boolean?
): Part
	return create(name, size, cf, color, material, parent, shape, transparency, canCollide, false)
end

-- Builds a decorative Part by forwarding to create with decorated = true, so it gets the Decor attribute.
-- Returns the new Part.
local function decor(
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	shape: Enum.PartType?,
	transparency: number?,
	canCollide: boolean?
): Part
	return create(name, size, cf, color, material, parent, shape, transparency, canCollide, true)
end

-- Builds a CFrame at center rolled 90 degrees on Z so a cylinder's length axis points straight up.
-- Returns that CFrame.
local function upright(center: Vector3): CFrame
	return CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
end

-- Builds a CFrame at the midpoint of a and b that lays a cylinder's length axis along a to b (upright when degenerate or vertical).
-- Returns that CFrame.
local function span(a: Vector3, b: Vector3): CFrame
	local delta = b - a
	local mid = (a + b) / 2
	local length = delta.Magnitude
	if length < 1e-4 then
		return upright(mid)
	end
	if math.abs(delta.Unit:Dot(Vector3.new(0, 1, 0))) > 0.999 then
		return upright(mid)
	end
	return CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0)
end

-- Builds a cylinder Part stretched between points a and b with the given diameter, as decor or structure.
-- Returns the new Part.
local function cyl(
	name: string,
	a: Vector3,
	b: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	decorated: boolean,
	canCollide: boolean?
): Part
	local builder = if decorated then decor else part
	return builder(name, Vector3.new((b - a).Magnitude, diameter, diameter), span(a, b), color, material, parent, Enum.PartType.Cylinder, nil, canCollide)
end

-- Builds a vertical cylinder Part of the given height and diameter centred on center, as decor or structure.
-- Returns the new Part.
local function vcyl(
	name: string,
	center: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	decorated: boolean,
	canCollide: boolean?
): Part
	local builder = if decorated then decor else part
	return builder(name, Vector3.new(height, diameter, diameter), upright(center), color, material, parent, Enum.PartType.Cylinder, nil, canCollide)
end

-- === decoration helpers ===
-- Builds a SurfaceGui with a scaled OwnerName TextLabel on the board's front face showing text.
-- Returns nothing.
local function write(board: BasePart, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "OwnerName"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = INK
	label.TextScaled = true
	label.Parent = gui
end

-- Builds a PointLight of the given colour and range parented to host.
-- Returns nothing.
local function glow(host: BasePart, color: Color3, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 1
	light.Parent = host
end

-- === lighting ===
-- Builds the island lighting: sets Lighting properties, replaces sky and post effects, flags LightingOk, drops the Baseplate.
-- Returns nothing.
local function applyLighting()
	Lighting.ClockTime = 14.2
	Lighting.Brightness = 3.2
	Lighting.Ambient = Color3.fromRGB(158, 184, 204)
	Lighting.OutdoorAmbient = Color3.fromRGB(168, 194, 214)
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.ShadowSoftness = 0.25
	Lighting.ExposureCompensation = 0.1
	Lighting.GlobalShadows = true
	Lighting.FogStart = 520
	Lighting.FogEnd = 1100
	Lighting.FogColor = Color3.fromRGB(186, 216, 232)

	local effectClasses = { "Atmosphere", "BloomEffect", "ColorCorrectionEffect", "SunRaysEffect", "DepthOfFieldEffect" }
	for _, child in Lighting:GetChildren() do
		if child:IsA("Sky") then
			child:Destroy()
		else
			for _, className in effectClasses do
				if child:IsA(className) then
					child:Destroy()
					break
				end
			end
		end
	end

	pcall(function()
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.2
		atmosphere.Offset = 0.12
		atmosphere.Haze = 1.3
		atmosphere.Glare = 0.15
		atmosphere.Color = Color3.fromRGB(176, 208, 228)
		atmosphere.Decay = Color3.fromRGB(214, 196, 158)
		atmosphere.Parent = Lighting
	end)
	pcall(function()
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.15
		bloom.Size = 12
		bloom.Parent = Lighting
	end)
	pcall(function()
		local colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Saturation = 0.12
		colorCorrection.Contrast = 0.05
		colorCorrection.Brightness = 0.02
		colorCorrection.TintColor = Color3.fromRGB(255, 246, 232)
		colorCorrection.Parent = Lighting
	end)
	pcall(function()
		local sunRays = Instance.new("SunRaysEffect")
		sunRays.Intensity = 0.06
		sunRays.Spread = 0.8
		sunRays.Parent = Lighting
	end)
	pcall(function()
		local depthOfField = Instance.new("DepthOfFieldEffect")
		depthOfField.FarIntensity = 0.1
		depthOfField.FocusDistance = 60
		depthOfField.InFocusRadius = 200
		depthOfField.Parent = Lighting
	end)

	local counts = {
		Atmosphere = 0,
		BloomEffect = 0,
		ColorCorrectionEffect = 0,
		SunRaysEffect = 0,
		DepthOfFieldEffect = 0,
	}
	for _, child in Lighting:GetChildren() do
		local className = child.ClassName
		if counts[className] ~= nil then
			counts[className] += 1
		end
	end
	local lightingOk = counts.Atmosphere >= 1
		and counts.BloomEffect >= 1
		and counts.ColorCorrectionEffect >= 1
		and counts.SunRaysEffect >= 1
		and counts.DepthOfFieldEffect >= 1
	workspace:SetAttribute("LightingOk", lightingOk)

	Lighting.Brightness = 3.6

	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.CFrame = CFrame.new(0, -30, 0)
	end
end

-- === land ===
-- Builds a block Part from name, size and CFrame, as decor or structure.
-- Returns nothing.
local function slab(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance, decorated: boolean?)
	local builder = if decorated then decor else part
	builder(name, size, cf, color, material, parent, Enum.PartType.Block)
end

-- Builds a sand block whose top sits at y, centred on x/z and turned by yaw degrees.
-- Returns nothing.
local function beachSlab(name: string, size: Vector3, x: number, z: number, y: number, yaw: number, parent: Instance, color: Color3?)
	part(name, size, CFrame.new(x, y - size.Y / 2, z) * CFrame.Angles(0, math.rad(yaw), 0), color or SAND, Enum.Material.Sand, parent)
end

-- Builds a grass block whose top sits at y, centred on x/z and turned by yaw degrees.
-- Returns nothing.
local function grassSlab(name: string, size: Vector3, x: number, z: number, y: number, yaw: number, parent: Instance, color: Color3?)
	part(name, size, CFrame.new(x, y - size.Y / 2, z) * CFrame.Angles(0, math.rad(yaw), 0), color or GRASS, Enum.Material.Grass, parent)
end

-- Builds a wedge Part from name, size and CFrame, as decor or structure.
-- Returns nothing.
local function wedge(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance, decorated: boolean?)
	local builder = if decorated then decor else part
	builder(name, size, cf, color, material, parent, Enum.PartType.Wedge)
end

-- === land ===
-- Builds three stepped grass mounds (west, east, south), four shrinking tiers each.
-- Returns nothing.
local function buildMounds(parent: Instance)
	local mounds = {
		{ "MoundWest", -64, 44, 5.2, 12 },
		{ "MoundEast", 76, 60, 4.2, -8 },
		{ "MoundSouth", 46, 98, 6.4, 20 },
	}
	local feet = {
		Vector3.new(16, 12),
		Vector3.new(11, 8.5),
		Vector3.new(7, 5.2),
		Vector3.new(3.8, 2.8),
	}
	for _, spec in mounds do
		local name, x, z, tall, yaw = spec[1], spec[2], spec[3], spec[4], spec[5]
		local risen = 0
		for i, foot in feet do
			local h = tall / 4
			risen += h
			local top = GRASS_Y + risen
			local thick = h + 0.2
			part(
				name,
				Vector3.new(foot.X, thick, foot.Y),
				CFrame.new(x, top - thick / 2, z) * CFrame.Angles(0, math.rad(yaw + i * 11), 0),
				if i % 2 == 0 then GRASS_DARK else GRASS,
				Enum.Material.Grass,
				parent
			)
		end
	end
end

-- === land ===
-- Builds the north east rock outcrop and the five stone climbing steps that lead up it.
-- Returns nothing.
local function buildHeadland(parent: Instance)
	local rocks = {
		{ "OutcropBase", Vector3.new(16, 4.0, 13), 138, -48, 2.6, 8 },
		{ "OutcropMid", Vector3.new(11, 3.0, 9), 138, -47, 5.4, -6 },
		{ "OutcropHigh", Vector3.new(7.5, 2.4, 6), 137, -46, 7.6, 12 },
		{ "OutcropCap", Vector3.new(4.6, 2.0, 3.8), 136, -46, 9.6, -4 },
	}
	for _, spec in rocks do
		local name, size, x, z, y, yaw = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6]
		part(name, size, CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0), ROCK, Enum.Material.Rock, parent)
	end
	local steps = {
		{ 90, -24, 2.8 },
		{ 102, -36, 4.4 },
		{ 114, -46, 6.0 },
		{ 126, -50, 7.6 },
		{ 136, -46, 9.2 },
	}
	for i, spec in steps do
		local x, z, top = spec[1], spec[2], spec[3]
		local bottom = 1.4
		local h = top - bottom
		part(
			"Climb",
			Vector3.new(4.4, h, 3.6),
			CFrame.new(x, (top + bottom) / 2, z) * CFrame.Angles(0, math.rad((i - 1) * 16), 0),
			STONE,
			Enum.Material.Slate,
			parent
		)
	end
end

-- === coast ===
-- Builds the seabed, sandbar, deep shelf and the translucent non-colliding sea plane.
-- Returns nothing.
local function buildSea(parent: Instance)
	part("Seabed", Vector3.new(980, 6, 980), CFrame.new(0, SEABED_Y - 3, 40), SEABED, Enum.Material.Sand, parent)
	part("Sandbar", Vector3.new(520, 1.2, 360), CFrame.new(0, SEABED_Y + 0.4, 30), SHALLOW, Enum.Material.Sand, parent)
	part("ShelfDeep", Vector3.new(300, 0.6, 200), CFrame.new(10, SEABED_Y + 0.9, 40), Color3.fromRGB(48, 132, 128), Enum.Material.Sand, parent)
	local sea = part("Sea", Vector3.new(980, 1, 980), CFrame.new(0, SEA_Y, 40), SEA, Enum.Material.Glass, parent, nil, 0.32, false)
	sea.CanCollide = false
end

-- === coast ===
-- Builds the sand ring, grass plateau, beach slopes, plaza, rebirth pad and island centre marker, plus mounds and headland.
-- Returns the Rebirth part and the IslandCentre part.
local function buildLand(parent: Instance): (BasePart, BasePart)
	-- organic sand ring: overlapping rotated slabs, y rises from the water inland
	local sandRing = {
		{ "SandCore", Vector3.new(250, 1.4, 150), 0, 62, 2.2, 0, SAND },
		{ "SandNorth", Vector3.new(120, 1.1, 70), -10, 8, 1.6, 6, SAND },
		{ "SandNorthL", Vector3.new(70, 1.0, 46), -70, 6, 1.35, -12, SAND },
		{ "SandNorthR", Vector3.new(64, 1.0, 40), 62, 10, 1.4, 14, SAND },
		{ "SandSouth", Vector3.new(170, 1.2, 70), 4, 128, 1.9, -4, SAND },
		{ "SandSouthL", Vector3.new(80, 1.0, 48), -78, 122, 1.5, 8, SAND_DARK },
		{ "SandSouthR", Vector3.new(78, 1.0, 50), 86, 120, 1.55, -10, SAND },
		{ "SandWest", Vector3.new(70, 1.2, 130), -108, 60, 1.7, 3, SAND },
		{ "SandEast", Vector3.new(68, 1.2, 120), 112, 58, 1.75, -5, SAND },
		{ "SandWestLow", Vector3.new(46, 0.8, 90), -138, 48, 1.15, 7, SAND_WET },
		{ "SandEastLow", Vector3.new(42, 0.8, 80), 142, 46, 1.15, -8, SAND_WET },
		{ "SandSouthLow", Vector3.new(110, 0.8, 36), 6, 158, 1.1, 5, SAND_WET },
		{ "CoveWest", Vector3.new(40, 0.7, 28), -96, 18, 1.05, 22, SAND_WET },
		{ "CoveEast", Vector3.new(36, 0.7, 26), 100, 16, 1.05, -18, SAND_WET },
		{ "CoveSouth", Vector3.new(48, 0.7, 22), -20, 148, 1.05, 12, SAND_WET },
		{ "SpitWest", Vector3.new(54, 0.9, 18), -168, 78, 1.25, 18, SAND },
		{ "SpitWestTip", Vector3.new(28, 0.7, 14), -198, 92, 1.05, 28, SAND_WET },
		{ "SpitSouth", Vector3.new(22, 0.9, 46), 36, 176, 1.2, -14, SAND },
		{ "SpitSouthTip", Vector3.new(16, 0.7, 24), 48, 204, 1.05, -6, SAND_WET },
		{ "HeadlandNeck", Vector3.new(46, 1.3, 34), 96, -18, 1.9, 24, SAND_DARK },
		{ "HeadlandCap", Vector3.new(34, 1.1, 28), 122, -36, 1.55, 16, SAND },
		{ "ShelfW", Vector3.new(70, 0.5, 40), -150, 20, 0.85, 10, Color3.fromRGB(120, 196, 186) },
		{ "ShelfE", Vector3.new(60, 0.5, 36), 150, 14, 0.85, -12, Color3.fromRGB(120, 196, 186) },
		{ "ShelfS", Vector3.new(90, 0.5, 30), 10, 186, 0.8, 4, Color3.fromRGB(132, 204, 190) },
		{ "ShelfNE", Vector3.new(40, 0.5, 24), 140, -48, 0.8, 20, Color3.fromRGB(110, 188, 180) },
	}
	for _, spec in sandRing do
		local name, size, x, z, y, yaw, color = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6], spec[7]
		local mat = if color == Color3.fromRGB(120, 196, 186) or color == Color3.fromRGB(132, 204, 190) or color == Color3.fromRGB(110, 188, 180)
			then Enum.Material.Sand
			else Enum.Material.Sand
		part(name, size, CFrame.new(x, y - size.Y / 2, z) * CFrame.Angles(0, math.rad(yaw), 0), color, mat, parent)
	end

	-- raised grass plateau: overlapping slabs, two lobes and a notch, never a rectangle
	local grass = {
		{ "GrassCore", Vector3.new(118, 1.1, 86), -8, 78, 2.7, 3, GRASS },
		{ "GrassN", Vector3.new(90, 0.9, 40), -6, 28, 2.55, 4, GRASS },
		{ "GrassS", Vector3.new(110, 0.9, 36), 2, 112, 2.55, -3, GRASS_DARK },
		{ "GrassW", Vector3.new(36, 0.9, 80), -78, 66, 2.5, 6, GRASS },
		{ "GrassE", Vector3.new(34, 0.9, 74), 80, 62, 2.5, -5, GRASS_DARK },
		{ "GrassBiteW", Vector3.new(28, 0.7, 24), -96, 40, 2.35, 16, GRASS },
		{ "GrassBiteE", Vector3.new(26, 0.7, 22), 98, 36, 2.35, -14, GRASS_DARK },
		{ "GrassBiteS", Vector3.new(40, 0.7, 18), -30, 128, 2.3, 8, GRASS },
		{ "GrassKnob", Vector3.new(22, 0.8, 20), 54, 108, 2.6, 12, GRASS_DARK },
		{ "LobeWest", Vector3.new(22, 0.8, 30), -150, 112, 2.45, 16, GRASS },
		{ "LobeWestCap", Vector3.new(14, 0.7, 16), -162, 124, 2.35, 24, GRASS_DARK },
		{ "LobeNorth", Vector3.new(30, 0.9, 20), 58, -18, 2.5, -10, GRASS },
		{ "LobeNorthCap", Vector3.new(16, 0.7, 12), 70, -28, 2.35, -18, GRASS_DARK },
		{ "EdgeNW", Vector3.new(30, 0.8, 20), -60, 18, 2.45, 22, GRASS },
		{ "EdgeNE", Vector3.new(26, 0.8, 18), 58, 14, 2.45, -18, GRASS_DARK },
		{ "EdgeSW", Vector3.new(34, 0.8, 18), -72, 124, 2.4, 14, GRASS },
		{ "EdgeSE", Vector3.new(28, 0.8, 16), 74, 118, 2.4, -16, GRASS_DARK },
		{ "WanderN", Vector3.new(20, 0.7, 14), -28, 14, 2.35, 30, GRASS },
		{ "WanderS", Vector3.new(18, 0.7, 12), 18, 132, 2.3, -24, GRASS_DARK },
	}
	for _, spec in grass do
		local name, size, x, z, y, yaw, color = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6], spec[7]
		part(name, size, CFrame.new(x, y - size.Y / 2, z) * CFrame.Angles(0, math.rad(yaw), 0), color, Enum.Material.Grass, parent)
	end

	-- sloping beach wedges so the shore is never a wall
	local slopes = {
		{ "SlopeW1", Vector3.new(50, 1.1, 16), -120, 50, 1.55, -86 },
		{ "SlopeW2", Vector3.new(40, 0.9, 14), -132, 90, 1.4, -78 },
		{ "SlopeE1", Vector3.new(48, 1.1, 16), 124, 48, 1.55, 84 },
		{ "SlopeE2", Vector3.new(36, 0.9, 14), 136, 86, 1.4, 96 },
		{ "SlopeS1", Vector3.new(70, 1.0, 16), -20, 140, 1.5, 176 },
		{ "SlopeS2", Vector3.new(60, 0.9, 14), 40, 142, 1.45, 188 },
		{ "SlopeN1", Vector3.new(40, 0.9, 14), -40, 14, 1.4, 8 },
		{ "SlopeN2", Vector3.new(36, 0.9, 12), 40, 16, 1.4, -6 },
		{ "SlopeSpitW", Vector3.new(30, 0.7, 10), -176, 70, 1.2, -70 },
		{ "SlopeSpitS", Vector3.new(18, 0.7, 12), 30, 168, 1.15, 160 },
	}
	for _, spec in slopes do
		local name, size, x, z, y, yaw = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6]
		part(name, size, CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0), SAND, Enum.Material.Sand, parent, Enum.PartType.Wedge)
	end

	local plaza = part("Plaza", Vector3.new(52, 1, 40), CFrame.new(0, WALK_Y - 0.5, 22), STONE, Enum.Material.Cobblestone, parent)
	part("PlazaStepN", Vector3.new(24, 0.5, 4), CFrame.new(0, GRASS_Y + 0.1, 1), STONE_DARK, Enum.Material.Slate, parent)
	part("PlazaStepS", Vector3.new(30, 0.5, 4), CFrame.new(0, GRASS_Y + 0.1, 43), STONE_DARK, Enum.Material.Slate, parent)
	part("PlazaStepW", Vector3.new(4, 0.5, 28), CFrame.new(-28, GRASS_Y + 0.1, 22), STONE_DARK, Enum.Material.Slate, parent)
	part("PlazaStepE", Vector3.new(4, 0.5, 28), CFrame.new(28, GRASS_Y + 0.1, 22), STONE_DARK, Enum.Material.Slate, parent)
	for i = -2, 2 do
		part("PlazaTile", Vector3.new(6, 0.12, 6), CFrame.new(i * 8, WALK_Y + 0.06, 18), Color3.fromRGB(188, 182, 172), Enum.Material.Cobblestone, parent)
	end

	local rebirth = part("Rebirth", Vector3.new(8, 0.2, 8), CFrame.new(0, WALK_Y + 0.1, 32), Color3.fromRGB(255, 208, 102), Enum.Material.Neon, parent)
	local centre = part("IslandCentre", Vector3.new(6, 0.2, 6), CFrame.new(0, GRASS_Y + 0.1, 78), Color3.fromRGB(236, 232, 224), Enum.Material.Marble, parent, nil, nil, false)
	part("CentreRing", Vector3.new(9, 0.15, 9), CFrame.new(0, GRASS_Y + 0.05, 78), STONE_DARK, Enum.Material.Slate, parent)
	buildMounds(parent)
	buildHeadland(parent)
	return rebirth, centre
end

local PATH = Color3.fromRGB(214, 186, 132)
local PATH_EDGE = Color3.fromRGB(186, 156, 104)

-- === paths ===
-- Builds one sandy path slab just below grass level at x/z, turned by yaw degrees.
-- Returns nothing.
local function pathSlab(name: string, size: Vector3, x: number, z: number, yaw: number, parent: Instance)
	part(name, size, CFrame.new(x, GRASS_Y - 0.05, z) * CFrame.Angles(0, math.rad(yaw), 0), PATH, Enum.Material.Sand, parent)
end

-- === paths ===
-- Builds one decorative slate pebble at the given point, scaled by scale.
-- Returns nothing.
local function pebble(at: Vector3, parent: Instance, scale: number)
	decor("Pebble", Vector3.new(0.7, 0.35, 0.55) * scale, CFrame.new(at + Vector3.new(0, 0.12, 0)), STONE, Enum.Material.Slate, parent, Enum.PartType.Ball, nil, false)
end

-- Builds one small decorative shell in the given colour at the given point.
-- Returns nothing.
local function shellEdge(at: Vector3, parent: Instance, color: Color3)
	decor("PathShell", Vector3.new(0.55, 0.28, 0.7), CFrame.new(at + Vector3.new(0, 0.1, 0)), color, Enum.Material.SmoothPlastic, parent, Enum.PartType.Ball, nil, false)
end

-- === paths ===
-- Builds the Paths model: spine, cross paths, lanes to the bases, beach paths and pebble/shell crumbs.
-- Returns nothing.
local function buildPaths(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Paths"
	model.Parent = parent
	-- plaza to each base gate. gates face inward, so the path ends just outside the fence
	local gates = {
		{ -96, -8, 0 },
		{ -96, 34, 0 },
		{ -96, 76, 0 },
		{ -96, 118, 0 },
		{ 96, -8, 0 },
		{ 96, 34, 0 },
		{ 96, 76, 0 },
		{ 96, 118, 0 },
	}
	pathSlab("Spine", Vector3.new(8, 0.18, 130), 0, 78, 0, model)
	pathSlab("CrossN", Vector3.new(150, 0.18, 7), 0, 22, 0, model)
	pathSlab("CrossS", Vector3.new(150, 0.18, 7), 0, 118, 2, model)
	pathSlab("WestLane", Vector3.new(7, 0.18, 140), -96, 55, 1, model)
	pathSlab("EastLane", Vector3.new(7, 0.18, 140), 96, 55, -1, model)
	pathSlab("ToWestN", Vector3.new(40, 0.16, 6), -48, -8, 4, model)
	pathSlab("ToWestS", Vector3.new(36, 0.16, 6), -50, 76, -3, model)
	pathSlab("ToEastN", Vector3.new(40, 0.16, 6), 48, -8, -4, model)
	pathSlab("ToEastS", Vector3.new(36, 0.16, 6), 50, 76, 3, model)
	pathSlab("BeachW", Vector3.new(6, 0.16, 90), -130, 70, 8, model)
	pathSlab("BeachE", Vector3.new(6, 0.16, 80), 132, 66, -7, model)
	pathSlab("BeachS", Vector3.new(100, 0.16, 6), 0, 146, 3, model)
	pathSlab("SpurPlaza", Vector3.new(10, 0.16, 18), 0, 50, 0, model)

	local crumbs = {
		Vector3.new(-100, GRASS_Y, -4),
		Vector3.new(-92, GRASS_Y, 30),
		Vector3.new(-100, GRASS_Y, 70),
		Vector3.new(-92, GRASS_Y, 114),
		Vector3.new(100, GRASS_Y, -4),
		Vector3.new(92, GRASS_Y, 30),
		Vector3.new(100, GRASS_Y, 70),
		Vector3.new(92, GRASS_Y, 114),
		Vector3.new(-40, GRASS_Y, 24),
		Vector3.new(40, GRASS_Y, 20),
		Vector3.new(-20, GRASS_Y, 80),
		Vector3.new(24, GRASS_Y, 116),
		Vector3.new(-126, BEACH_Y, 40),
		Vector3.new(-134, BEACH_Y, 96),
		Vector3.new(128, BEACH_Y, 36),
		Vector3.new(136, BEACH_Y, 90),
		Vector3.new(-30, BEACH_Y, 148),
		Vector3.new(34, BEACH_Y, 144),
	}
	for i, at in crumbs do
		pebble(at, model, 1.1 + (i % 3) * 0.25)
		if i % 2 == 0 then
			shellEdge(at + Vector3.new(1.4, 0, 0.6), model, if i % 4 == 0 then WHITE else PINK)
		end
	end
end

-- === struct ===
-- Builds one pier model at originX: planks, posts, crossbeams, ropes, lamps and an invisible spawn pad.
-- Returns the spawn pad part named spawnName.
local function buildPier(originX: number, spawnName: string, parent: Instance): BasePart
	local model = Instance.new("Model")
	model.Name = spawnName
	model.Parent = parent

	local planks = 18
	local plankLen = PIER_LENGTH / planks
	for i = 0, planks - 1 do
		local z = PIER_Z - plankLen / 2 - i * plankLen
		local shade = if i % 2 == 0 then PLANKS else WOOD_LIGHT
		part("Plank", Vector3.new(PIER_WIDTH, 0.4, plankLen + 0.02), CFrame.new(originX, WALK_Y - 0.2, z), shade, Enum.Material.WoodPlanks, model)
	end

	local posts = 7
	for i = 0, posts - 1 do
		local z = PIER_Z - 5 - i * (PIER_LENGTH - 10) / (posts - 1)
		for _, side in { -1, 1 } do
			local x = originX + side * (PIER_WIDTH / 2 + 0.85)
			vcyl("Post", Vector3.new(x, 1.1, z), 6.6, 0.7, WOOD_DARK, Enum.Material.Wood, model, false)
			part("Cap", Vector3.new(1.1, 0.25, 1.1), CFrame.new(x, 4.5, z), WOOD, Enum.Material.Wood, model)
		end
		cyl(
			"Crossbeam",
			Vector3.new(originX - PIER_WIDTH / 2 - 0.85, 0.9, z),
			Vector3.new(originX + PIER_WIDTH / 2 + 0.85, 0.9, z),
			0.5,
			WOOD_DARK,
			Enum.Material.Wood,
			model,
			false
		)
	end

	for _, side in { -1, 1 } do
		local x = originX + side * (PIER_WIDTH / 2 + 0.85)
		for i = 0, 5 do
			local z0 = PIER_Z - 5 - i * 14
			cyl("Rope", Vector3.new(x, 4.05, z0), Vector3.new(x, 4.05, z0 - 14), 0.2, ROPE, Enum.Material.Fabric, model, false, false)
			cyl("RopeLow", Vector3.new(x, 3.45, z0), Vector3.new(x, 3.45, z0 - 14), 0.16, ROPE, Enum.Material.Fabric, model, false, false)
		end
	end

	for i = 0, 3 do
		local z = PIER_Z - 14 - i * 20
		for _, side in { -1, 1 } do
			local x = originX + side * (PIER_WIDTH / 2 + 1.7)
			vcyl("LampPost", Vector3.new(x, 2.2, z), 4.4, 0.3, WOOD_DARK, Enum.Material.Wood, model, false)
			local lamp = part("Lamp", Vector3.new(0.9, 0.9, 0.9), CFrame.new(x, 4.6, z), LAMP, Enum.Material.Neon, model, Enum.PartType.Ball, nil, false)
			glow(lamp, LAMP, 14)
		end
	end

	return part(spawnName, Vector3.new(4, 0.15, 4), CFrame.new(originX, WALK_Y + 0.05, PIER_Z - 16), PLANKS, Enum.Material.Wood, model, nil, 1, false)
end

-- === struct ===
-- Builds the WelcomeSign model on the plaza with the title and subtitle boards.
-- Returns nothing.
local function buildSign(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "WelcomeSign"
	model.Parent = parent
	local z = 12
	vcyl("PostL", Vector3.new(-8, 6.4, z), 6.8, 0.7, WOOD_DARK, Enum.Material.Wood, model, false)
	vcyl("PostR", Vector3.new(8, 6.4, z), 6.8, 0.7, WOOD_DARK, Enum.Material.Wood, model, false)
	local title = part(
		"Title",
		Vector3.new(16, 3.4, 0.4),
		CFrame.lookAt(Vector3.new(0, 8.2, z), Vector3.new(0, 8.2, z - 1)),
		WOOD,
		Enum.Material.Wood,
		model
	)
	write(title, "PULAU BRAINROT")
	local sub = part(
		"Subtitle",
		Vector3.new(14, 1.3, 0.35),
		CFrame.lookAt(Vector3.new(0, 5.6, z), Vector3.new(0, 5.6, z - 1)),
		WOOD_LIGHT,
		Enum.Material.Wood,
		model
	)
	write(sub, "brainrots walk the pier")
	vcyl("SubPostL", Vector3.new(-6.2, 4.4, z), 2.8, 0.5, WOOD_DARK, Enum.Material.Wood, model, false)
	vcyl("SubPostR", Vector3.new(6.2, 4.4, z), 2.8, 0.5, WOOD_DARK, Enum.Material.Wood, model, false)
	part("Trim", Vector3.new(16.6, 0.3, 0.55), CFrame.new(0, 10.05, z), STRAW, Enum.Material.Wood, model)
end


-- === bases ===
-- Builds one pedestal model (drum, neck, neon ring, neon top) at the given world point.
-- Returns the PedestalTop part.
local function buildPedestal(world: Vector3, parent: Instance, index: number): BasePart
	local model = Instance.new("Model")
	model.Name = "Pedestal" .. tostring(index)
	model.Parent = parent
	local x, z = world.X, world.Z
	vcyl("Drum", Vector3.new(x, PLOT_Y + 0.22, z), 0.44, 2.5, STONE, Enum.Material.Cobblestone, model, false)
	vcyl("Neck", Vector3.new(x, PLOT_Y + 0.55, z), 0.28, 1.4, STONE_DARK, Enum.Material.Slate, model, false)
	vcyl("Ring", Vector3.new(x, WALK_Y - 0.22, z), 0.14, 2.35, Color3.fromRGB(116, 220, 196), Enum.Material.Neon, model, false, false)
	local top = part("PedestalTop", Vector3.new(0.2, 2.2, 2.2), upright(Vector3.new(x, WALK_Y - 0.1, z)), Color3.fromRGB(170, 232, 214), Enum.Material.Neon, model, Enum.PartType.Cylinder)
	return top
end

-- === bases ===
-- Builds the bamboo fence around a plot, with a gated gap on the side facing points to.
-- Returns nothing.
local function buildFence(centre: Vector3, facing: Vector3, parent: Instance)
	local right = Vector3.new(-facing.Z, 0, facing.X)
	local half = PLOT / 2
	local function edge(from: Vector3, to: Vector3, gate: boolean)
		local steps = 8
		for i = 0, steps do
			local t = i / steps
			local skipped = gate and t > 0.28 and t < 0.72
			if not skipped then
				local at = from:Lerp(to, t)
				vcyl("FencePost", Vector3.new(at.X, PLOT_Y + 1.4, at.Z), 2.8, 0.36, BAMBOO_DARK, Enum.Material.Wood, parent, false)
			end
		end
		local function rail(a: Vector3, b: Vector3, height: number)
			cyl("Rail", Vector3.new(a.X, PLOT_Y + height, a.Z), Vector3.new(b.X, PLOT_Y + height, b.Z), 0.18, BAMBOO, Enum.Material.Wood, parent, false, false)
		end
		if gate then
			local left = from:Lerp(to, 0.28)
			local rightEnd = from:Lerp(to, 0.72)
			rail(from, left, 1)
			rail(from, left, 2.1)
			rail(rightEnd, to, 1)
			rail(rightEnd, to, 2.1)
			local mid = from:Lerp(to, 0.5)
			local along = (to - from).Unit
			for _, hand in { -1, 1 } do
				local at = mid + along * (hand * 1.7)
				part(
					"Gate",
					Vector3.new(2.6, 2.4, 0.16),
					CFrame.lookAt(Vector3.new(at.X, PLOT_Y + 1.2, at.Z), Vector3.new(at.X, PLOT_Y + 1.2, at.Z) + facing),
					BAMBOO,
					Enum.Material.Wood,
					parent,
					nil,
					nil,
					false
				)
			end
		else
			rail(from, to, 1)
			rail(from, to, 2.1)
		end
	end
	local c1 = centre + (-facing - right) * half
	local c2 = centre + (-facing + right) * half
	local c3 = centre + (facing + right) * half
	local c4 = centre + (facing - right) * half
	edge(c1, c2, false)
	edge(c2, c3, false)
	edge(c3, c4, true)
	edge(c4, c1, false)
end

-- === bases ===
-- Builds one base: plot, centre marker, stilt hut, name board, six pedestals and fence.
-- Returns the PlotCentre marker, the six pedestal tops, and the hut roof peak point.
local function buildBase(index: number, centre: Vector3, facing: Vector3, parent: Instance): (BasePart, { BasePart }, Vector3)
	local model = Instance.new("Model")
	model.Name = "Base" .. tostring(index)
	model.Parent = parent
	local plot = part("Plot", Vector3.new(PLOT, 0.8, PLOT), CFrame.new(centre.X, PLOT_Y - 0.4, centre.Z), SAND, Enum.Material.Sand, model)
	local marker = part("PlotCentre", Vector3.new(2, 0.15, 2), CFrame.new(centre.X, PLOT_Y + 0.05, centre.Z), SAND_DARK, Enum.Material.Sand, model, nil, 1, false)

	local hut = centre - facing * 8
	local hutCF = CFrame.lookAt(Vector3.new(hut.X, PLOT_Y, hut.Z), Vector3.new(hut.X, PLOT_Y, hut.Z) + facing)
	for _, corner in { Vector3.new(-4, 0, -3), Vector3.new(4, 0, -3), Vector3.new(-4, 0, 3), Vector3.new(4, 0, 3) } do
		local foot = hutCF:PointToWorldSpace(corner)
		vcyl("Stilt", Vector3.new(foot.X, PLOT_Y + 1.3, foot.Z), 2.6, 0.5, WOOD_DARK, Enum.Material.Wood, model, false)
	end
	part("HutFloor", Vector3.new(9, 0.3, 7), hutCF * CFrame.new(0, 2.75, 0), PLANKS, Enum.Material.WoodPlanks, model)
	part("WallBack", Vector3.new(9, 3.2, 0.3), hutCF * CFrame.new(0, 4.5, 3.3), WOOD, Enum.Material.Wood, model)
	part("WallL", Vector3.new(0.3, 3.2, 7), hutCF * CFrame.new(-4.35, 4.5, 0), WOOD, Enum.Material.Wood, model)
	part("WallR", Vector3.new(0.3, 3.2, 7), hutCF * CFrame.new(4.35, 4.5, 0), WOOD, Enum.Material.Wood, model)
	part("WallFrontL", Vector3.new(2.8, 3.2, 0.3), hutCF * CFrame.new(-3.05, 4.5, -3.3), WOOD_LIGHT, Enum.Material.Wood, model)
	part("WallFrontR", Vector3.new(2.8, 3.2, 0.3), hutCF * CFrame.new(3.05, 4.5, -3.3), WOOD_LIGHT, Enum.Material.Wood, model)
	part("Lintel", Vector3.new(3.2, 0.9, 0.3), hutCF * CFrame.new(0, 5.65, -3.3), WOOD_DARK, Enum.Material.Wood, model)
	part("RoofL", Vector3.new(5.4, 0.28, 8), hutCF * CFrame.new(-2.05, 6.9, 0) * CFrame.Angles(0, 0, math.rad(28)), STRAW, Enum.Material.Grass, model)
	part("RoofR", Vector3.new(5.4, 0.28, 8), hutCF * CFrame.new(2.05, 6.9, 0) * CFrame.Angles(0, 0, math.rad(-28)), STRAW_DARK, Enum.Material.Grass, model)
	part("Ridge", Vector3.new(0.5, 0.35, 8.2), hutCF * CFrame.new(0, 7.9, 0), WOOD_DARK, Enum.Material.Wood, model)

	local boardPos = hutCF:PointToWorldSpace(Vector3.new(0, 6.5, -4.05))
	local board = part("NameBoard", Vector3.new(6, 1.15, 0.22), CFrame.lookAt(boardPos, boardPos + facing), WOOD_LIGHT, Enum.Material.Wood, model)
	write(board, "Pemilik")

	local accent = ACCENT[((index - 1) % #ACCENT) + 1]
	part("AccentBand", Vector3.new(9.6, 0.5, 0.5), hutCF * CFrame.new(0, 3.1, -3.45), accent, Enum.Material.SmoothPlastic, model)
	part("AccentRidge", Vector3.new(0.9, 0.55, 8.3), hutCF * CFrame.new(0, 8.1, 0), accent, Enum.Material.SmoothPlastic, model)
	part("AccentPost", Vector3.new(0.45, 3.0, 0.45), hutCF * CFrame.new(-4.4, 4.4, -3.4), accent, Enum.Material.SmoothPlastic, model)
	part("AccentPost", Vector3.new(0.45, 3.0, 0.45), hutCF * CFrame.new(4.4, 4.4, -3.4), accent, Enum.Material.SmoothPlastic, model)
	local flagAt = hutCF * CFrame.new(0, 9.6, 0)
	part("AccentPole", Vector3.new(0.2, 4.2, 0.2), flagAt * CFrame.new(0, 1.4, 0), WOOD_DARK, Enum.Material.Wood, model)
	part("AccentFlag", Vector3.new(2.4, 1.5, 0.12), flagAt * CFrame.new(1.2, 3.0, 0), accent, Enum.Material.Fabric, model)
	local platePos = hutCF:PointToWorldSpace(Vector3.new(0, 3.1, -4.25))
	local plate = part("BaseNumber", Vector3.new(2.8, 1.3, 0.16), CFrame.lookAt(platePos, platePos + facing), accent, Enum.Material.SmoothPlastic, model)
	write(plate, "#" .. tostring(index))

	local tops: { BasePart } = {}
	local n = 0
	for row = 0, 1 do
		for col = -1, 1 do
			n += 1
			local at = hutCF:PointToWorldSpace(Vector3.new(col * GAP, 0, -12.2 - row * GAP))
			table.insert(tops, buildPedestal(at, model, n))
		end
	end

	buildFence(centre, facing, model)
	local peak = hutCF:PointToWorldSpace(Vector3.new(0, 8.3, 0))
	return marker, tops, peak
end


-- === vegetation ===
-- Builds a decorative palm model: leaning three-segment trunk, six leaves, two coconuts.
-- Returns nothing.
local function buildPalm(ground: Vector3, lean: Vector3, parent: Instance, scale: number)
	local model = Instance.new("Model")
	model.Name = "Palm"
	model.Parent = parent
	local base = ground + Vector3.new(0, 0.2, 0)
	local crown = base + Vector3.new(lean.X, 13 * scale, lean.Z)
	for i = 1, 3 do
		local a = base:Lerp(crown, (i - 1) / 3)
		local b = base:Lerp(crown, i / 3)
		cyl("Trunk", a, b, (1.6 - i * 0.25) * scale, if i % 2 == 0 then TRUNK_DARK else TRUNK, Enum.Material.Wood, model, true)
	end
	for i = 1, 6 do
		local angle = math.rad((i - 1) * 60 + 12)
		local dir = Vector3.new(math.cos(angle) * 1.15, -0.42, math.sin(angle) * 1.15)
		local length = 7.4 * scale
		local mid = crown + dir.Unit * (length * 0.46)
		decor("Leaf", Vector3.new(1.7 * scale, 0.28 * scale, length), CFrame.lookAt(mid, mid + dir), if i % 2 == 0 then LEAF else LEAF_LIT, Enum.Material.Grass, model, nil, nil, false)
	end
	for i = 1, 2 do
		local angle = math.rad(20 + i * 140)
		decor("Coconut", Vector3.new(0.85, 0.85, 0.85) * scale, CFrame.new(crown + Vector3.new(math.cos(angle) * 0.55, -0.7 * scale, math.sin(angle) * 0.55)), Color3.fromRGB(90, 56, 30), Enum.Material.SmoothPlastic, model, Enum.PartType.Ball, nil, false)
	end
end

-- Builds a decorative bush model of three mounds with five white blooms.
-- Returns nothing.
local function buildBush(ground: Vector3, color: Color3, parent: Instance, wide: number)
	local model = Instance.new("Model")
	model.Name = "Bush"
	model.Parent = parent
	decor("Mound", Vector3.new(wide, 2.4, wide * 0.85), CFrame.new(ground + Vector3.new(0, 1.05, 0)), color, Enum.Material.Grass, model, Enum.PartType.Ball)
	decor("MoundSide", Vector3.new(wide * 0.62, 1.7, wide * 0.55), CFrame.new(ground + Vector3.new(wide * 0.28, 0.75, 0.2)), color:Lerp(LEAF, 0.35), Enum.Material.Grass, model, Enum.PartType.Ball)
	decor("MoundBack", Vector3.new(wide * 0.5, 1.5, wide * 0.48), CFrame.new(ground + Vector3.new(-wide * 0.2, 0.85, -0.15)), color:Lerp(LEAF_LIT, 0.25), Enum.Material.Grass, model, Enum.PartType.Ball)
	for i = 1, 5 do
		local angle = math.rad((i - 1) * 72 + 18)
		decor("Bloom", Vector3.new(0.7, 0.7, 0.7), CFrame.new(ground + Vector3.new(math.cos(angle) * wide * 0.28, 2.0, math.sin(angle) * wide * 0.2)), WHITE, Enum.Material.SmoothPlastic, model, Enum.PartType.Ball, nil, false)
	end
end

-- Builds a decorative fern model of six fronds turned by yaw.
-- Returns nothing.
local function buildFern(ground: Vector3, parent: Instance, yaw: number)
	local model = Instance.new("Model")
	model.Name = "Fern"
	model.Parent = parent
	for i = 1, 6 do
		local angle = yaw + math.rad((i - 1) * 60)
		local dir = Vector3.new(math.cos(angle), 0.55, math.sin(angle))
		local mid = ground + Vector3.new(0, 0.7, 0) + dir.Unit * 1.6
		decor("Frond", Vector3.new(1.15, 0.22, 3.4), CFrame.lookAt(mid, mid + dir), LEAF, Enum.Material.Grass, model, nil, nil, false)
	end
end

-- Builds a decorative banana plant model with two stalks, six blades and two bunches.
-- Returns nothing.
local function buildBanana(ground: Vector3, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "BananaPlant"
	model.Parent = parent
	vcyl("Stalk", ground + Vector3.new(0, 3.2, 0), 6.4, 0.85, Color3.fromRGB(74, 128, 46), Enum.Material.Grass, model, true)
	vcyl("Stalk2", ground + Vector3.new(0.35, 2.6, 0.2), 5.2, 0.55, Color3.fromRGB(96, 150, 58), Enum.Material.Grass, model, true)
	for i = 1, 6 do
		local angle = math.rad((i - 1) * 60 + 14)
		local dir = Vector3.new(math.cos(angle), 0.7, math.sin(angle))
		local mid = ground + Vector3.new(0, 6.1, 0) + dir.Unit * 2.6
		decor("Blade", Vector3.new(1.9, 0.22, 5.6), CFrame.lookAt(mid, mid + dir), if i % 2 == 0 then LEAF_LIT else LEAF, Enum.Material.Grass, model, nil, nil, false)
	end
	decor("Bunch", Vector3.new(1.1, 1.6, 0.8), CFrame.new(ground + Vector3.new(0.45, 4.1, 0.3)), Color3.fromRGB(236, 204, 60), Enum.Material.SmoothPlastic, model)
	decor("Bunch2", Vector3.new(0.7, 1.1, 0.55), CFrame.new(ground + Vector3.new(-0.2, 3.6, -0.15)), Color3.fromRGB(214, 176, 40), Enum.Material.SmoothPlastic, model)
end

-- Builds a decorative rock model of three boulders, scaled and tinted.
-- Returns nothing.
local function buildRock(ground: Vector3, scale: number, parent: Instance, color: Color3?)
	local tint = color or ROCK
	local model = Instance.new("Model")
	model.Name = "Rock"
	model.Parent = parent
	local h = 2.2 * scale
	decor("Boulder", Vector3.new(3.2 * scale, h, 2.6 * scale), CFrame.new(ground + Vector3.new(0, h / 2 - 0.15 * scale, 0)), tint, Enum.Material.Slate, model, Enum.PartType.Ball)
	local h2 = 1.4 * scale
	decor("BoulderSide", Vector3.new(1.9 * scale, h2, 1.6 * scale), CFrame.new(ground + Vector3.new(1.1 * scale, h2 / 2 - 0.1 * scale, 0.4 * scale)), tint:Lerp(ROCK_DARK, 0.45), Enum.Material.Slate, model, Enum.PartType.Ball)
	decor("BoulderBack", Vector3.new(1.5 * scale, h2 * 0.8, 1.3 * scale), CFrame.new(ground + Vector3.new(-0.8 * scale, h2 * 0.35, -0.5 * scale)), tint:Lerp(STONE, 0.3), Enum.Material.Rock, model, Enum.PartType.Ball)
end

-- Builds a decorative mushroom (stem and cap) in the given colour and scale.
-- Returns nothing.
local function buildMushroom(ground: Vector3, parent: Instance, color: Color3, scale: number)
	vcyl("Stem", ground + Vector3.new(0, 0.7 * scale, 0), 1.4 * scale, 0.45 * scale, Color3.fromRGB(236, 220, 190), Enum.Material.SmoothPlastic, parent, true)
	decor("Cap", Vector3.new(1.5 * scale, 0.55 * scale, 1.5 * scale), CFrame.new(ground + Vector3.new(0, 1.45 * scale, 0)), color, Enum.Material.SmoothPlastic, parent, Enum.PartType.Ball, nil, false)
end

-- Builds a decorative fallen log with a cut end and a moss strip, turned by yaw.
-- Returns nothing.
local function buildLog(ground: Vector3, yaw: number, parent: Instance)
	local cf = CFrame.new(ground + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, yaw, math.rad(8))
	local a = cf:PointToWorldSpace(Vector3.new(-3.2, 0, 0))
	local b = cf:PointToWorldSpace(Vector3.new(3.2, 0, 0))
	cyl("FallenLog", a, b, 1.5, TRUNK_DARK, Enum.Material.Wood, parent, true)
	decor("LogEnd", Vector3.new(0.3, 1.35, 1.35), cf * CFrame.new(3.3, 0, 0), Color3.fromRGB(186, 150, 96), Enum.Material.Wood, parent, Enum.PartType.Cylinder, nil, false)
	decor("Moss", Vector3.new(3.4, 0.35, 1.1), cf * CFrame.new(0.2, 0.55, 0), LEAF, Enum.Material.Grass, parent, nil, nil, false)
end


-- === props ===
-- Builds a decorative wooden crate with a band, of side size (default 2.2).
-- Returns nothing.
local function crate(at: Vector3, yaw: number, parent: Instance, size: number?)
	local s = size or 2.2
	decor("Crate", Vector3.new(s, s, s), CFrame.new(at + Vector3.new(0, s / 2, 0)) * CFrame.Angles(0, yaw, 0), WOOD, Enum.Material.WoodPlanks, parent)
	decor("CrateBand", Vector3.new(s + 0.08, 0.16, s + 0.08), CFrame.new(at + Vector3.new(0, s * 0.72, 0)) * CFrame.Angles(0, yaw, 0), WOOD_DARK, Enum.Material.Wood, parent)
end

-- Builds a decorative barrel with two metal hoops.
-- Returns nothing.
local function barrel(at: Vector3, parent: Instance)
	vcyl("Barrel", at + Vector3.new(0, 1.05, 0), 2.1, 1.7, Color3.fromRGB(120, 72, 38), Enum.Material.Wood, parent, true)
	vcyl("Hoop", at + Vector3.new(0, 0.55, 0), 0.12, 1.82, Color3.fromRGB(70, 70, 74), Enum.Material.Metal, parent, true, false)
	vcyl("HoopTop", at + Vector3.new(0, 1.55, 0), 0.12, 1.82, Color3.fromRGB(70, 70, 74), Enum.Material.Metal, parent, true, false)
end

-- Builds a decorative rope coil around a wooden core.
-- Returns nothing.
local function coil(at: Vector3, parent: Instance)
	vcyl("RopeCoil", at + Vector3.new(0, 0.28, 0), 0.55, 2.1, ROPE, Enum.Material.Fabric, parent, true, false)
	vcyl("RopeCore", at + Vector3.new(0, 0.32, 0), 0.6, 0.8, WOOD_DARK, Enum.Material.Wood, parent, true, false)
end

-- Builds a decorative fishing net hung between two bamboo posts.
-- Returns nothing.
local function hungNet(at: Vector3, yaw: number, parent: Instance)
	local cf = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
	local left = cf.Position + cf.RightVector * -1.8
	local right = cf.Position + cf.RightVector * 1.8
	vcyl("NetPost", left + Vector3.new(0, 1.8, 0), 3.6, 0.32, BAMBOO_DARK, Enum.Material.Wood, parent, true)
	vcyl("NetPost", right + Vector3.new(0, 1.8, 0), 3.6, 0.32, BAMBOO_DARK, Enum.Material.Wood, parent, true)
	cyl("NetBar", left + Vector3.new(0, 3.5, 0), right + Vector3.new(0, 3.5, 0), 0.26, BAMBOO, Enum.Material.Wood, parent, true, false)
	decor("Net", Vector3.new(3.4, 3.0, 0.12), cf * CFrame.new(0, 1.9, 0), Color3.fromRGB(214, 204, 176), Enum.Material.Fabric, parent, nil, 0.22, false)
end

-- Builds a decorative beached boat with hull, sides, bow, seat and two oars.
-- Returns nothing.
local function beachedBoat(at: Vector3, yaw: number, parent: Instance)
	local cf = CFrame.new(at + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, yaw, math.rad(4))
	decor("Hull", Vector3.new(2.4, 1.1, 6.4), cf, WOOD, Enum.Material.Wood, parent)
	decor("HullSideL", Vector3.new(0.25, 1.5, 5.6), cf * CFrame.new(-1.2, 0.55, 0), WOOD_DARK, Enum.Material.Wood, parent)
	decor("HullSideR", Vector3.new(0.25, 1.5, 5.6), cf * CFrame.new(1.2, 0.55, 0), WOOD_DARK, Enum.Material.Wood, parent)
	decor("Bow", Vector3.new(2.2, 0.9, 1.6), cf * CFrame.new(0, 0.15, -3.6) * CFrame.Angles(math.rad(-18), 0, 0), WOOD_LIGHT, Enum.Material.Wood, parent, Enum.PartType.Wedge)
	decor("Seat", Vector3.new(2.0, 0.18, 1.1), cf * CFrame.new(0, 0.7, 0.4), PLANKS, Enum.Material.WoodPlanks, parent)
	local oarA = cf:PointToWorldSpace(Vector3.new(1.5, 1.1, -0.6))
	local oarB = cf:PointToWorldSpace(Vector3.new(3.2, 0.4, 1.4))
	cyl("Oar", oarA, oarB, 0.18, WOOD_LIGHT, Enum.Material.Wood, parent, true, false)
	decor("OarBlade", Vector3.new(0.55, 0.1, 0.9), CFrame.new(oarB), SAND_DARK, Enum.Material.Wood, parent, nil, nil, false)
	local oarC = cf:PointToWorldSpace(Vector3.new(-1.4, 1.0, 0.8))
	local oarD = cf:PointToWorldSpace(Vector3.new(-3.0, 0.35, -0.6))
	cyl("Oar2", oarC, oarD, 0.18, WOOD_LIGHT, Enum.Material.Wood, parent, true, false)
end

-- === props ===
-- Builds a FishingCorner model of crates, barrels, a coil, a net and a beached boat.
-- Returns nothing.
local function buildFishingCorner(origin: Vector3, yaw: number, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "FishingCorner"
	model.Parent = parent
	local cf = CFrame.new(origin) * CFrame.Angles(0, yaw, 0)
	local function w(offset: Vector3): Vector3
		return cf:PointToWorldSpace(offset)
	end
	crate(w(Vector3.new(-3.2, 0, 1.4)), yaw + 0.2, model, 2.4)
	crate(w(Vector3.new(-3.6, 0, 3.8)), yaw + 0.6, model, 2.0)
	crate(w(Vector3.new(-3.3, 2.2, 2.5)), yaw + 0.35, model, 1.7)
	barrel(w(Vector3.new(2.6, 0, 2.2)), model)
	barrel(w(Vector3.new(4.2, 0, 3.6)), model)
	coil(w(Vector3.new(0.4, 0, 3.2)), model)
	hungNet(w(Vector3.new(-1.2, 0, -1.6)), yaw + 0.4, model)
	beachedBoat(w(Vector3.new(3.4, 0, -2.4)), yaw - 0.5, model)
end

-- === props ===
-- Builds the FruitStall model near the plaza with awning, fruit, crates and a buah sign.
-- Returns nothing.
local function buildFruitStall(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "FruitStall"
	model.Parent = parent
	local at = Vector3.new(22, GRASS_Y, 8)
	decor("Counter", Vector3.new(7.2, 2.2, 2.4), CFrame.new(at + Vector3.new(0, 1.1, 0)), WOOD, Enum.Material.Wood, model)
	decor("CounterTop", Vector3.new(7.4, 0.2, 2.6), CFrame.new(at + Vector3.new(0, 2.25, 0)), PLANKS, Enum.Material.WoodPlanks, model)
	vcyl("PostL", at + Vector3.new(-3.3, 2.6, -1.0), 5.2, 0.4, WOOD_DARK, Enum.Material.Wood, model, true)
	vcyl("PostR", at + Vector3.new(3.3, 2.6, -1.0), 5.2, 0.4, WOOD_DARK, Enum.Material.Wood, model, true)
	vcyl("PostBL", at + Vector3.new(-3.3, 2.4, 1.0), 4.8, 0.36, WOOD_DARK, Enum.Material.Wood, model, true)
	vcyl("PostBR", at + Vector3.new(3.3, 2.4, 1.0), 4.8, 0.36, WOOD_DARK, Enum.Material.Wood, model, true)
	decor("AwningA", Vector3.new(3.8, 0.18, 4.2), CFrame.new(at + Vector3.new(-1.8, 5.15, 0)) * CFrame.Angles(math.rad(8), 0, 0), RED, Enum.Material.Fabric, model)
	decor("AwningB", Vector3.new(3.8, 0.18, 4.2), CFrame.new(at + Vector3.new(1.8, 5.15, 0)) * CFrame.Angles(math.rad(8), 0, 0), WHITE, Enum.Material.Fabric, model)
	decor("AwningTrim", Vector3.new(7.8, 0.22, 0.3), CFrame.new(at + Vector3.new(0, 5.0, -2.0)), RED, Enum.Material.Fabric, model)
	crate(at + Vector3.new(-4.6, 0, 1.6), 0.3, model, 1.8)
	crate(at + Vector3.new(4.8, 0, 1.4), -0.2, model, 2.0)
	local fruits = {
		{ Vector3.new(-2.2, 2.6, 0.2), FLOWER_RED, 0.7 },
		{ Vector3.new(-1.4, 2.55, -0.3), FLOWER_YELLOW, 0.62 },
		{ Vector3.new(-0.4, 2.6, 0.15), ORANGE, 0.75 },
		{ Vector3.new(0.6, 2.55, -0.2), PINK, 0.6 },
		{ Vector3.new(1.5, 2.6, 0.25), TEAL, 0.68 },
		{ Vector3.new(2.3, 2.55, -0.1), FLOWER_RED, 0.64 },
	}
	for _, spec in fruits do
		decor("Fruit", Vector3.new(spec[3], spec[3], spec[3]), CFrame.new(at + spec[1]), spec[2], Enum.Material.SmoothPlastic, model, Enum.PartType.Ball, nil, false)
	end
	local sign = decor("StallSign", Vector3.new(3.4, 1.15, 0.18), CFrame.lookAt(at + Vector3.new(0, 3.5, -1.35), at + Vector3.new(0, 3.5, -3)), WOOD_LIGHT, Enum.Material.Wood, model)
	write(sign, "buah")
end

-- Builds a decorative beach umbrella with a pole, six panels and a cap.
-- Returns nothing.
local function umbrella(at: Vector3, color: Color3, parent: Instance)
	vcyl("UmbrellaPole", at + Vector3.new(0, 2.6, 0), 5.2, 0.28, WHITE, Enum.Material.SmoothPlastic, parent, true)
	for i = 1, 6 do
		local angle = math.rad((i - 1) * 60)
		local dir = Vector3.new(math.cos(angle), -0.28, math.sin(angle))
		local mid = at + Vector3.new(0, 5.3, 0) + dir.Unit * 1.9
		decor("UmbrellaPanel", Vector3.new(1.7, 0.14, 2.3), CFrame.lookAt(mid, mid + dir), color, Enum.Material.Fabric, parent, nil, nil, false)
	end
	decor("UmbrellaCap", Vector3.new(0.6, 0.35, 0.6), CFrame.new(at + Vector3.new(0, 5.55, 0)), color, Enum.Material.SmoothPlastic, parent, Enum.PartType.Ball, nil, false)
end

-- Builds a decorative beach towel with a white stripe.
-- Returns nothing.
local function towel(at: Vector3, yaw: number, color: Color3, parent: Instance)
	decor("Towel", Vector3.new(3.2, 0.1, 5.4), CFrame.new(at + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, yaw, 0), color, Enum.Material.Fabric, parent, nil, nil, false)
	decor("TowelStripe", Vector3.new(3.2, 0.12, 0.55), CFrame.new(at + Vector3.new(0, 0.08, 0.6)) * CFrame.Angles(0, yaw, 0), WHITE, Enum.Material.Fabric, parent, nil, nil, false)
end

-- === beach life ===
-- Builds the BeachClub model on the west spit: umbrellas, towels, lifeguard chair, ball, hut.
-- Returns nothing.
local function buildBeachClub(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "BeachClub"
	model.Parent = parent
	local origin = Vector3.new(-168, BEACH_Y, 78)
	umbrella(origin + Vector3.new(-4, 0, 2), RED, model)
	umbrella(origin + Vector3.new(3, 0, -1), Color3.fromRGB(244, 174, 60), model)
	umbrella(origin + Vector3.new(8, 0, 4), TEAL, model)
	towel(origin + Vector3.new(-3.5, 0, 6), 0.3, RED, model)
	towel(origin + Vector3.new(3.5, 0, 5), -0.4, BLUE, model)
	towel(origin + Vector3.new(7, 0, 8), 0.15, WHITE, model)
	local chair = origin + Vector3.new(-8, 0, -2)
	vcyl("ChairPostL", chair + Vector3.new(-1.2, 2.6, 0), 5.2, 0.36, WOOD, Enum.Material.Wood, model, true)
	vcyl("ChairPostR", chair + Vector3.new(1.2, 2.6, 0), 5.2, 0.36, WOOD, Enum.Material.Wood, model, true)
	decor("ChairSeat", Vector3.new(3.2, 0.24, 2.2), CFrame.new(chair + Vector3.new(0, 4.5, 0.3)), WOOD_LIGHT, Enum.Material.WoodPlanks, model)
	decor("ChairBack", Vector3.new(3.2, 1.3, 0.2), CFrame.new(chair + Vector3.new(0, 5.1, -0.7)), RED, Enum.Material.Fabric, model)
	decor("ChairShade", Vector3.new(3.8, 0.16, 3.4), CFrame.new(chair + Vector3.new(0, 6.6, 0.2)), WHITE, Enum.Material.Fabric, model)
	decor("ChairStep", Vector3.new(1.6, 0.9, 1.1), CFrame.new(chair + Vector3.new(0, 0.45, 1.6)), WOOD, Enum.Material.Wood, model)
	decor("BeachBall", Vector3.new(1.5, 1.5, 1.5), CFrame.new(origin + Vector3.new(1, 0.75, 3)), WHITE, Enum.Material.SmoothPlastic, model, Enum.PartType.Ball, nil, false)
	decor("BeachBallBand", Vector3.new(1.55, 0.35, 1.55), CFrame.new(origin + Vector3.new(1, 0.75, 3)), RED, Enum.Material.SmoothPlastic, model, nil, nil, false)
	local hut = origin + Vector3.new(12, 0, -3)
	decor("HutFloor", Vector3.new(5.5, 0.3, 4.2), CFrame.new(hut + Vector3.new(0, 0.2, 0)), PLANKS, Enum.Material.WoodPlanks, model)
	decor("HutWallL", Vector3.new(0.28, 3.6, 4.2), CFrame.new(hut + Vector3.new(-2.6, 2.0, 0)), WOOD, Enum.Material.Wood, model)
	decor("HutWallR", Vector3.new(0.28, 3.6, 4.2), CFrame.new(hut + Vector3.new(2.6, 2.0, 0)), WOOD, Enum.Material.Wood, model)
	decor("HutWallBack", Vector3.new(5.5, 3.6, 0.28), CFrame.new(hut + Vector3.new(0, 2.0, 2.0)), WOOD_DARK, Enum.Material.Wood, model)
	decor("HutRoof", Vector3.new(6.2, 0.24, 5.0), CFrame.new(hut + Vector3.new(0, 3.95, 0)) * CFrame.Angles(math.rad(-8), 0, 0), STRAW, Enum.Material.Grass, model)
	vcyl("HutPost", hut + Vector3.new(-2.4, 1.8, -1.9), 3.6, 0.32, WOOD_DARK, Enum.Material.Wood, model, true)
	vcyl("HutPost2", hut + Vector3.new(2.4, 1.8, -1.9), 3.6, 0.32, WOOD_DARK, Enum.Material.Wood, model, true)
end

-- === beach life ===
-- Builds one decorative tide pool (rock rim and glass water).
-- Returns nothing.
local function tidePool(at: Vector3, parent: Instance)
	decor("PoolRim", Vector3.new(4.2, 0.5, 3.4), CFrame.new(at + Vector3.new(0, 0.15, 0)), ROCK, Enum.Material.Slate, parent, Enum.PartType.Cylinder)
	decor("PoolWater", Vector3.new(3.2, 0.25, 2.5), CFrame.new(at + Vector3.new(0, 0.28, 0)), SEA, Enum.Material.Glass, parent, Enum.PartType.Cylinder, 0.35, false)
end

-- Builds one decorative five-armed starfish.
-- Returns nothing.
local function starfishBig(ground: Vector3, parent: Instance)
	for i = 1, 5 do
		local angle = math.rad((i - 1) * 72)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		decor("Arm", Vector3.new(0.55, 0.16, 1.5), CFrame.lookAt(ground + Vector3.new(0, 0.1, 0) + dir * 0.6, ground + dir), ORANGE, Enum.Material.SmoothPlastic, parent, nil, nil, false)
	end
	decor("StarHeart", Vector3.new(0.7, 0.2, 0.7), CFrame.new(ground + Vector3.new(0, 0.12, 0)), ORANGE, Enum.Material.SmoothPlastic, parent, Enum.PartType.Ball, nil, false)
end

-- === beach life ===
-- Builds the TidePools model on the south shore: pools, rocks, corals, starfish, shells.
-- Returns nothing.
local function buildTidePools(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "TidePools"
	model.Parent = parent
	local origin = Vector3.new(70, SHORE_Y, 150)
	tidePool(origin, model)
	tidePool(origin + Vector3.new(5.5, 0, 2.4), model)
	tidePool(origin + Vector3.new(-3.2, 0, 3.6), model)
	buildRock(origin + Vector3.new(-2, -0.2, -2), 1.3, model, ROCK)
	buildRock(origin + Vector3.new(6, -0.1, -1), 0.9, model, ROCK_DARK)
	buildRock(origin + Vector3.new(2, -0.15, 5), 1.1, model, STONE)
	local corals = {
		{ origin + Vector3.new(1.2, 0, 0.4), PINK },
		{ origin + Vector3.new(5.8, 0, 2.6), ORANGE },
		{ origin + Vector3.new(-2.6, 0, 3.8), TEAL },
		{ origin + Vector3.new(3.4, 0, -1.5), FLOWER_RED },
	}
	for _, spec in corals do
		local root = spec[1]
		decor("CoralHead", Vector3.new(1.6, 1.5, 1.6), CFrame.new(root + Vector3.new(0, 0.7, 0)), spec[2], Enum.Material.Sand, model, Enum.PartType.Ball, nil, false)
		cyl("CoralBranch", root + Vector3.new(0.1, 0.2, 0), root + Vector3.new(0.5, 1.8, 0.2), 0.4, spec[2], Enum.Material.Sand, model, true, false)
	end
	starfishBig(origin + Vector3.new(-5, 0.05, 1), model)
	starfishBig(origin + Vector3.new(8, 0.05, 1.5), model)
	decor("BigShell", Vector3.new(1.1, 0.5, 1.4), CFrame.new(origin + Vector3.new(2.2, 0.25, 4.2)), WHITE, Enum.Material.SmoothPlastic, model, Enum.PartType.Ball, nil, false)
	decor("BigShell2", Vector3.new(0.9, 0.45, 1.2), CFrame.new(origin + Vector3.new(-4.2, 0.22, -0.6)), PINK, Enum.Material.SmoothPlastic, model, Enum.PartType.Ball, nil, false)
	decor("BigShell3", Vector3.new(0.8, 0.4, 1.05), CFrame.new(origin + Vector3.new(7.2, 0.2, 4)), SAND_DARK, Enum.Material.SmoothPlastic, model, Enum.PartType.Ball, nil, false)
end

-- === landmarks ===
-- Builds the JungleCorner model of bananas, ferns, bushes, a log, mushrooms and a rock.
-- Returns nothing.
local function buildJungle(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "JungleCorner"
	model.Parent = parent
	local origin = Vector3.new(-55, GRASS_Y, 100)
	buildBanana(origin + Vector3.new(-4, 0, -2), model)
	buildBanana(origin + Vector3.new(3, 0, 1), model)
	buildBanana(origin + Vector3.new(-1, 0, 5), model)
	buildFern(origin + Vector3.new(5, 0, -3), model, 0.4)
	buildFern(origin + Vector3.new(-6, 0, 3), model, 1.2)
	buildFern(origin + Vector3.new(2, 0, 6), model, 2.1)
	buildBush(origin + Vector3.new(-2, 0, -6), FLOWER_PINK, model, 4.2)
	buildBush(origin + Vector3.new(6, 0, 4), FLOWER_YELLOW, model, 3.6)
	buildBush(origin + Vector3.new(-7, 0, 6), FLOWER_RED, model, 3.8)
	buildLog(origin + Vector3.new(1, 0, -1), 0.6, model)
	buildMushroom(origin + Vector3.new(3.2, 0, -2.4), model, FLOWER_RED, 1.3)
	buildMushroom(origin + Vector3.new(4.4, 0, -1.2), model, WHITE, 0.9)
	buildMushroom(origin + Vector3.new(-3.5, 0, 2.2), model, ORANGE, 1.1)
	buildRock(origin + Vector3.new(7, 0, -1), 0.8, model, ROCK)
end

-- Builds the Lookout model on the headland: deck on stilts, rails, telescope, rocks.
-- Returns nothing.
local function buildLookout(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Lookout"
	model.Parent = parent
	local origin = Vector3.new(118, 3.2, -34)
	decor("Deck", Vector3.new(8, 0.4, 6), CFrame.new(origin + Vector3.new(0, 2.4, 0)), PLANKS, Enum.Material.WoodPlanks, model)
	for _, corner in { Vector3.new(-3.4, 0, -2.4), Vector3.new(3.4, 0, -2.4), Vector3.new(-3.4, 0, 2.4), Vector3.new(3.4, 0, 2.4) } do
		vcyl("Stilt", origin + corner + Vector3.new(0, 1.0, 0), 2.6, 0.45, WOOD_DARK, Enum.Material.Wood, model, true)
	end
	local railY = origin.Y + 3.5
	local function rail(a: Vector3, b: Vector3)
		cyl("Rail", a, b, 0.22, BAMBOO, Enum.Material.Wood, model, true, false)
	end
	local corners = {
		origin + Vector3.new(-3.6, 3.5, -2.6),
		origin + Vector3.new(3.6, 3.5, -2.6),
		origin + Vector3.new(3.6, 3.5, 2.6),
		origin + Vector3.new(-3.6, 3.5, 1.0),
	}
	for i = 1, #corners - 1 do
		rail(corners[i], corners[i + 1])
		local mid = (corners[i] + corners[i + 1]) / 2
		vcyl("RailPost", Vector3.new(corners[i].X, origin.Y + 3.0, corners[i].Z), 1.6, 0.28, BAMBOO_DARK, Enum.Material.Wood, model, true)
	end
	vcyl("ScopeStand", origin + Vector3.new(0.4, 3.3, -0.4), 1.8, 0.4, WOOD_DARK, Enum.Material.Wood, model, true)
	decor("Scope", Vector3.new(0.45, 0.45, 1.6), CFrame.new(origin + Vector3.new(0.4, 4.35, -0.8)) * CFrame.Angles(math.rad(-12), 0.3, 0), Color3.fromRGB(70, 74, 82), Enum.Material.Metal, model, Enum.PartType.Cylinder, nil, false)
	decor("ScopeEye", Vector3.new(0.55, 0.55, 0.3), CFrame.new(origin + Vector3.new(0.2, 4.45, -0.05)), Color3.fromRGB(40, 44, 52), Enum.Material.Metal, model, Enum.PartType.Cylinder, nil, false)
	buildRock(origin + Vector3.new(-5, -1.6, 1), 1.6, model, ROCK_DARK)
	buildRock(origin + Vector3.new(4, -1.8, -2), 1.3, model, ROCK)
	buildRock(origin + Vector3.new(1, -2.0, 4), 1.8, model, STONE)
	buildRock(origin + Vector3.new(-2, -2.2, -4), 2.0, model, ROCK_DARK)
end

-- Builds the Shrine model by the plaza with altar, roof, lamps, bushes and an offering.
-- Returns nothing.
local function buildShrine(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Shrine"
	model.Parent = parent
	local at = Vector3.new(-18, GRASS_Y, 6)
	decor("Plinth", Vector3.new(4.2, 1.1, 3.2), CFrame.new(at + Vector3.new(0, 0.55, 0)), STONE, Enum.Material.Slate, model)
	decor("Altar", Vector3.new(2.2, 1.6, 1.6), CFrame.new(at + Vector3.new(0, 1.7, 0)), STONE_DARK, Enum.Material.Cobblestone, model)
	decor("RoofL", Vector3.new(2.6, 0.2, 2.4), CFrame.new(at + Vector3.new(-0.9, 3.3, 0)) * CFrame.Angles(0, 0, math.rad(24)), STRAW, Enum.Material.Grass, model)
	decor("RoofR", Vector3.new(2.6, 0.2, 2.4), CFrame.new(at + Vector3.new(0.9, 3.3, 0)) * CFrame.Angles(0, 0, math.rad(-24)), STRAW_DARK, Enum.Material.Grass, model)
	local lampL = decor("ShrineLamp", Vector3.new(0.7, 0.9, 0.7), CFrame.new(at + Vector3.new(-1.5, 1.5, 1.2)), LAMP, Enum.Material.Neon, model, nil, nil, false)
	local lampR = decor("ShrineLamp", Vector3.new(0.7, 0.9, 0.7), CFrame.new(at + Vector3.new(1.5, 1.5, 1.2)), LAMP, Enum.Material.Neon, model, nil, nil, false)
	glow(lampL, LAMP, 12)
	glow(lampR, LAMP, 12)
	buildBush(at + Vector3.new(-2.6, 0, -0.4), FLOWER_PINK, model, 2.4)
	buildBush(at + Vector3.new(2.8, 0, 0.2), FLOWER_YELLOW, model, 2.2)
	decor("Offer", Vector3.new(0.55, 0.55, 0.55), CFrame.new(at + Vector3.new(0, 2.7, 0.2)), FLOWER_RED, Enum.Material.SmoothPlastic, model, Enum.PartType.Ball, nil, false)
end

-- === harbour ===
-- Builds a decorative dinghy with a mooring rope.
-- Returns nothing.
local function dinghy(at: Vector3, yaw: number, parent: Instance)
	local cf = CFrame.new(at) * CFrame.Angles(0, yaw, math.rad(3))
	decor("DinghyHull", Vector3.new(2.2, 0.9, 5.2), cf, WOOD_LIGHT, Enum.Material.Wood, parent)
	decor("DinghyL", Vector3.new(0.2, 1.1, 4.6), cf * CFrame.new(-1.05, 0.45, 0), WOOD, Enum.Material.Wood, parent)
	decor("DinghyR", Vector3.new(0.2, 1.1, 4.6), cf * CFrame.new(1.05, 0.45, 0), WOOD, Enum.Material.Wood, parent)
	decor("DinghyBow", Vector3.new(2.0, 0.7, 1.3), cf * CFrame.new(0, 0.1, -2.9) * CFrame.Angles(math.rad(-16), 0, 0), WOOD, Enum.Material.Wood, parent, Enum.PartType.Wedge)
	local cleat = cf:PointToWorldSpace(Vector3.new(0, 0.6, 2.2))
	cyl("Mooring", cleat, Vector3.new(cleat.X, SHORE_Y - 0.4, cleat.Z + 1.5), 0.14, ROPE, Enum.Material.Fabric, parent, true, false)
end

-- === harbour ===
-- Builds the BoatDock model on the east shore: planks, piles, two dinghies, a lamp.
-- Returns nothing.
local function buildBoatDock(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "BoatDock"
	model.Parent = parent
	local origin = Vector3.new(150, BEACH_Y, 30)
	for i = 0, 5 do
		decor("DockPlank", Vector3.new(5.5, 0.28, 1.5), CFrame.new(origin + Vector3.new(i * 1.55, 0.9, -i * 2.2)), if i % 2 == 0 then PLANKS else WOOD_LIGHT, Enum.Material.WoodPlanks, model)
	end
	for _, p in { Vector3.new(0, 0, 0), Vector3.new(3, 0, -4.2), Vector3.new(6.2, 0, -8.6), Vector3.new(1.6, 0, -1.2), Vector3.new(4.6, 0, -6.4) } do
		vcyl("DockPile", origin + p + Vector3.new(2.4, 0.2, 0.6), 2.4, 0.4, WOOD_DARK, Enum.Material.Wood, model, true)
		vcyl("DockPile2", origin + p + Vector3.new(-2.4, 0.2, -0.4), 2.4, 0.4, WOOD_DARK, Enum.Material.Wood, model, true)
	end
	dinghy(origin + Vector3.new(2, 0.55, 3.5), 0.7, model)
	dinghy(origin + Vector3.new(7, 0.5, -2), 0.55, model)
	local lamp = decor("DockLamp", Vector3.new(0.8, 1.0, 0.8), CFrame.new(origin + Vector3.new(8.2, 2.6, -9.4)), LAMP, Enum.Material.Neon, model, nil, nil, false)
	glow(lamp, LAMP, 14)
end

-- Builds one decorative glowing buoy with a band and a tether to the seabed.
-- Returns nothing.
local function buildBuoy(position: Vector3, parent: Instance)
	local body = decor("Float", Vector3.new(1.8, 1.8, 1.8), CFrame.new(position), BUOY, Enum.Material.SmoothPlastic, parent, Enum.PartType.Ball, nil, false)
	vcyl("Band", position, 0.32, 1.9, WHITE, Enum.Material.SmoothPlastic, parent, true, false)
	cyl("Tether", position + Vector3.new(0, -0.7, 0), Vector3.new(position.X, SEABED_Y, position.Z), 0.14, ROPE, Enum.Material.Fabric, parent, true, false)
	glow(body, BUOY, 10)
end

-- Builds a sagging neon string light between a and b with a bulb at the dip.
-- Returns nothing.
local function buildWire(a: Vector3, b: Vector3, parent: Instance)
	local mid = (a + b) / 2 + Vector3.new(0, -1.6, 0)
	cyl("StringLight", a, mid, 0.14, LAMP, Enum.Material.Neon, parent, true, false)
	cyl("StringLight", mid, b, 0.14, LAMP, Enum.Material.Neon, parent, true, false)
	decor("Bulb", Vector3.new(0.35, 0.35, 0.35), CFrame.new(mid), LAMP, Enum.Material.Neon, parent, Enum.PartType.Ball, nil, false)
end

-- Builds one decorative lantern post with a glowing lantern.
-- Returns nothing.
local function buildLanternPost(ground: Vector3, parent: Instance)
	vcyl("Pole", ground + Vector3.new(0, 3.0, 0), 6.0, 0.42, WOOD_DARK, Enum.Material.Wood, parent, true)
	decor("Cross", Vector3.new(1.6, 0.2, 0.2), CFrame.new(ground + Vector3.new(0, 5.7, 0)), WOOD, Enum.Material.Wood, parent)
	local lamp = decor("Lantern", Vector3.new(1.05, 1.35, 1.05), CFrame.new(ground + Vector3.new(0, 6.3, 0)), LAMP, Enum.Material.Neon, parent, nil, nil, false)
	glow(lamp, LAMP, 18)
end

-- === scatter ===
-- Builds the scattered palms, flowering bushes and shoreline rocks.
-- Returns nothing.
local function scatterGreens(parent: Instance)
	local spots = {
		{ Vector3.new(-30, GRASS_Y, 48), 1.0, Vector3.new(-0.6, 0, 0.4) },
		{ Vector3.new(28, GRASS_Y, 52), 1.05, Vector3.new(0.8, 0, -0.3) },
		{ Vector3.new(-8, GRASS_Y, 96), 0.95, Vector3.new(0.4, 0, 1.0) },
		{ Vector3.new(18, GRASS_Y, 108), 1.1, Vector3.new(-0.7, 0, 0.5) },
		{ Vector3.new(-78, GRASS_Y, 20), 0.9, Vector3.new(-1.0, 0, 0.2) },
		{ Vector3.new(82, GRASS_Y, 24), 0.95, Vector3.new(1.1, 0, 0.3) },
		{ Vector3.new(-140, BEACH_Y, 40), 0.85, Vector3.new(-0.8, 0, 0.6) },
		{ Vector3.new(40, BEACH_Y, 168), 0.9, Vector3.new(0.3, 0, -1.0) },
	}
	for _, spec in spots do
		buildPalm(spec[1], spec[3], parent, spec[2])
	end
	local bushes = {
		{ Vector3.new(-40, GRASS_Y, 36), FLOWER_PINK, 3.4 },
		{ Vector3.new(36, GRASS_Y, 40), FLOWER_YELLOW, 3.2 },
		{ Vector3.new(8, GRASS_Y, 120), FLOWER_RED, 3.6 },
	}
	for _, spec in bushes do
		buildBush(spec[1], spec[2], parent, spec[3])
	end
	buildRock(Vector3.new(-150, SHORE_Y, 20), 1.8, parent, ROCK)
	buildRock(Vector3.new(-160, SHORE_Y, 110), 1.5, parent, ROCK_DARK)
	buildRock(Vector3.new(160, SHORE_Y, 80), 1.6, parent, ROCK)
	buildRock(Vector3.new(20, SHORE_Y, 200), 1.4, parent, STONE)
	buildRock(Vector3.new(140, SHORE_Y, -55), 2.2, parent, ROCK_DARK)
	buildRock(Vector3.new(100, SHORE_Y, -50), 1.7, parent, ROCK)
end

-- === market and grove ===
-- Builds one decorative market stall with awning and lantern, turned by yaw.
-- Returns nothing.
local function stall(at: Vector3, yaw: number, color: Color3, parent: Instance)
	local cf = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
	decor("StallCounter", Vector3.new(4.4, 2.0, 2.2), cf * CFrame.new(0, 1.0, 0), WOOD, Enum.Material.Wood, parent)
	decor("StallTop", Vector3.new(4.6, 0.18, 2.4), cf * CFrame.new(0, 2.05, 0), PLANKS, Enum.Material.WoodPlanks, parent)
	vcyl("StallPost", cf:PointToWorldSpace(Vector3.new(-2.0, 2.4, -0.9)), 4.8, 0.32, WOOD_DARK, Enum.Material.Wood, parent, true)
	vcyl("StallPost", cf:PointToWorldSpace(Vector3.new(2.0, 2.4, -0.9)), 4.8, 0.32, WOOD_DARK, Enum.Material.Wood, parent, true)
	decor("Awning", Vector3.new(2.4, 0.16, 3.2), cf * CFrame.new(-1.1, 4.7, 0) * CFrame.Angles(math.rad(10), 0, 0), color, Enum.Material.Fabric, parent)
	decor("Awning", Vector3.new(2.4, 0.16, 3.2), cf * CFrame.new(1.1, 4.7, 0) * CFrame.Angles(math.rad(10), 0, 0), WHITE, Enum.Material.Fabric, parent)
	local lamp = decor("StallLantern", Vector3.new(0.7, 0.9, 0.7), cf * CFrame.new(0, 3.6, -1.0), LAMP, Enum.Material.Neon, parent, nil, nil, false)
	glow(lamp, LAMP, 10)
end

-- Builds the MarketLane model of four stalls, each with a crate.
-- Returns nothing.
local function buildMarketLane(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "MarketLane"
	model.Parent = parent
	local spots = {
		{ Vector3.new(-34, GRASS_Y, 30), 0.15, RED },
		{ Vector3.new(-48, GRASS_Y, 32), -0.1, TEAL },
		{ Vector3.new(-62, GRASS_Y, 30), 0.2, ORANGE },
		{ Vector3.new(-76, GRASS_Y, 32), -0.05, BLUE },
	}
	for _, spec in spots do
		stall(spec[1], spec[2], spec[3], model)
		crate(spec[1] + Vector3.new(0, 0, 3.2), spec[2], model, 1.6)
	end
end

-- === market and grove ===
-- Builds a decorative campfire with a glowing flame and four log seats.
-- Returns nothing.
local function campfire(at: Vector3, parent: Instance)
	decor("FireRing", Vector3.new(3.4, 0.5, 3.4), CFrame.new(at + Vector3.new(0, 0.2, 0)), ROCK, Enum.Material.Slate, parent, Enum.PartType.Cylinder)
	local flame = decor("Flame", Vector3.new(1.1, 1.6, 1.1), CFrame.new(at + Vector3.new(0, 1.0, 0)), ORANGE, Enum.Material.Neon, parent, Enum.PartType.Ball, nil, false)
	glow(flame, ORANGE, 14)
	for i = 1, 4 do
		local angle = math.rad((i - 1) * 90 + 20)
		local seat = at + Vector3.new(math.cos(angle) * 4.2, 0, math.sin(angle) * 4.2)
		cyl("LogSeat", seat + Vector3.new(-1.1, 0.45, 0), seat + Vector3.new(1.1, 0.45, 0), 0.7, TRUNK_DARK, Enum.Material.Wood, parent, true)
	end
end

-- === market and grove ===
-- Builds the PalmGrove model of six palms around a campfire.
-- Returns nothing.
local function buildPalmGrove(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "PalmGrove"
	model.Parent = parent
	local origin = Vector3.new(52, GRASS_Y, 96)
	local palms = {
		Vector3.new(-6, 0, -3),
		Vector3.new(-2, 0, 4),
		Vector3.new(3, 0, -4),
		Vector3.new(6, 0, 2),
		Vector3.new(1, 0, 6),
		Vector3.new(-5, 0, 6),
	}
	for i, offset in palms do
		buildPalm(origin + offset, Vector3.new((i % 2) * 0.6 - 0.3, 0, 0.4), model, 0.85)
	end
	campfire(origin, model)
end

-- === water and coast ===
-- Builds one decorative lily pad with a pink bloom.
-- Returns nothing.
local function lily(at: Vector3, parent: Instance)
	decor("Lily", Vector3.new(1.6, 0.12, 1.6), CFrame.new(at + Vector3.new(0, 0.1, 0)), LEAF, Enum.Material.Grass, parent, Enum.PartType.Cylinder, nil, false)
	decor("LilyBloom", Vector3.new(0.6, 0.3, 0.6), CFrame.new(at + Vector3.new(0, 0.28, 0)), PINK, Enum.Material.SmoothPlastic, parent, Enum.PartType.Ball, nil, false)
end

-- Builds the Pond model with rim, water, lilies, reeds and a footbridge.
-- Returns nothing.
local function buildPond(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Pond"
	model.Parent = parent
	local at = Vector3.new(-40, GRASS_Y, 98)
	decor("PondRim", Vector3.new(16, 0.8, 14), CFrame.new(at + Vector3.new(0, 0.15, 0)), STONE, Enum.Material.Slate, model, Enum.PartType.Cylinder)
	decor("PondWater", Vector3.new(13, 0.3, 11), CFrame.new(at + Vector3.new(0, 0.35, 0)), SEA, Enum.Material.Glass, model, Enum.PartType.Cylinder, 0.3, false)
	lily(at + Vector3.new(-2.4, 0, 1.2), model)
	lily(at + Vector3.new(2.6, 0, -1.4), model)
	lily(at + Vector3.new(0.4, 0, 2.8), model)
	for i = 1, 5 do
		local angle = math.rad((i - 1) * 28 - 40)
		local root = at + Vector3.new(math.cos(angle) * 6.2, 0, math.sin(angle) * 5.4)
		decor("Reed", Vector3.new(0.3, 2.6, 0.3), CFrame.new(root + Vector3.new(0, 1.4, 0)), BAMBOO, Enum.Material.Grass, model, nil, nil, false)
	end
	local deck = at + Vector3.new(9, 0.6, 0)
	decor("Footbridge", Vector3.new(3.2, 0.3, 8), CFrame.new(deck), PLANKS, Enum.Material.WoodPlanks, model)
	vcyl("BridgePile", deck + Vector3.new(-1.2, -0.5, -3), 1.6, 0.4, WOOD_DARK, Enum.Material.Wood, model, true)
	vcyl("BridgePile", deck + Vector3.new(1.2, -0.5, 3), 1.6, 0.4, WOOD_DARK, Enum.Material.Wood, model, true)
end

-- === water and coast ===
-- Builds one decorative flower bed of five flowers on soil, turned by yaw.
-- Returns nothing.
local function flowerBed(at: Vector3, yaw: number, color: Color3, parent: Instance)
	local cf = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
	decor("BedSoil", Vector3.new(6, 0.4, 2.2), cf * CFrame.new(0, 0.15, 0), SAND_DARK, Enum.Material.Ground, parent)
	for i = -2, 2 do
		decor("Flower", Vector3.new(0.7, 1.1, 0.7), cf * CFrame.new(i * 1.1, 0.7, 0), color, Enum.Material.Grass, parent, Enum.PartType.Ball, nil, false)
	end
end

-- Builds the FlowerBeds model of five beds along the spine.
-- Returns nothing.
local function buildFlowerBeds(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "FlowerBeds"
	model.Parent = parent
	local beds = {
		{ Vector3.new(-18, GRASS_Y, 60), 0.1, FLOWER_PINK },
		{ Vector3.new(18, GRASS_Y, 64), -0.1, FLOWER_YELLOW },
		{ Vector3.new(-18, GRASS_Y, 88), 0.05, FLOWER_RED },
		{ Vector3.new(20, GRASS_Y, 92), 0.12, FLOWER_PINK },
		{ Vector3.new(-30, GRASS_Y, 40), 0.2, FLOWER_YELLOW },
	}
	for _, spec in beds do
		flowerBed(spec[1], spec[2], spec[3], model)
	end
end

-- === water and coast ===
-- Builds one decorative strip of surf foam, turned by yaw.
-- Returns nothing.
local function foam(at: Vector3, yaw: number, parent: Instance)
	decor("Foam", Vector3.new(7, 0.16, 1.4), CFrame.new(at) * CFrame.Angles(0, yaw, 0), WHITE, Enum.Material.SmoothPlastic, parent, nil, 0.15, false)
end

-- Builds one decorative piece of driftwood, turned by yaw.
-- Returns nothing.
local function driftwood(at: Vector3, yaw: number, parent: Instance)
	local cf = CFrame.new(at + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, yaw, math.rad(6))
	local a = cf:PointToWorldSpace(Vector3.new(-1.6, 0, 0))
	local b = cf:PointToWorldSpace(Vector3.new(1.6, 0, 0))
	cyl("Driftwood", a, b, 0.55, TRUNK, Enum.Material.Wood, parent, true, false)
end

-- Builds one decorative beach shell in the given colour.
-- Returns nothing.
local function shell(at: Vector3, color: Color3, parent: Instance)
	decor("Shell", Vector3.new(0.9, 0.4, 1.2), CFrame.new(at + Vector3.new(0, 0.15, 0)), color, Enum.Material.SmoothPlastic, parent, Enum.PartType.Ball, nil, false)
end

-- Builds a small decorative jetty of four planks and two piles, turned by yaw.
-- Returns nothing.
local function jetty(origin: Vector3, yaw: number, parent: Instance)
	local cf = CFrame.new(origin) * CFrame.Angles(0, yaw, 0)
	for i = 0, 3 do
		decor("JettyPlank", Vector3.new(3.4, 0.24, 1.6), cf * CFrame.new(0, 0.7, -i * 1.7), if i % 2 == 0 then PLANKS else WOOD_LIGHT, Enum.Material.WoodPlanks, parent)
	end
	vcyl("JettyPile", cf:PointToWorldSpace(Vector3.new(-1.4, 0.2, -0.6)), 1.8, 0.34, WOOD_DARK, Enum.Material.Wood, parent, true)
	vcyl("JettyPile", cf:PointToWorldSpace(Vector3.new(1.4, 0.2, -4.6)), 1.8, 0.34, WOOD_DARK, Enum.Material.Wood, parent, true)
end

-- Builds a decorative rowboat with a painter rope, turned by yaw.
-- Returns nothing.
local function rowboat(at: Vector3, yaw: number, parent: Instance)
	local cf = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
	decor("Rowboat", Vector3.new(2.0, 0.8, 4.6), cf, WOOD, Enum.Material.Wood, parent)
	decor("RowboatSide", Vector3.new(0.18, 1.0, 4.0), cf * CFrame.new(-0.95, 0.4, 0), WOOD_DARK, Enum.Material.Wood, parent)
	decor("RowboatSide", Vector3.new(0.18, 1.0, 4.0), cf * CFrame.new(0.95, 0.4, 0), WOOD_DARK, Enum.Material.Wood, parent)
	local cleat = cf:PointToWorldSpace(Vector3.new(0, 0.5, 2.0))
	cyl("Painter", cleat, cleat + Vector3.new(1.4, -0.6, 1.2), 0.12, ROPE, Enum.Material.Fabric, parent, true, false)
end

-- Builds one decorative coral head in the given colour.
-- Returns nothing.
local function coralHead(at: Vector3, color: Color3, parent: Instance)
	decor("Coral", Vector3.new(2.2, 1.6, 2.2), CFrame.new(at + Vector3.new(0, 0.5, 0)), color, Enum.Material.Sand, parent, Enum.PartType.Ball, nil, false)
end

-- Builds the Coast model: rocks, foam, driftwood, shells, jetties, a rowboat and corals.
-- Returns nothing.
local function buildCoast(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Coast"
	model.Parent = parent
	local rocks = {
		Vector3.new(-150, SHORE_Y, 36),
		Vector3.new(154, SHORE_Y, 40),
		Vector3.new(50, SHORE_Y, 172),
	}
	for i, at in rocks do
		buildRock(at, 1.1 + (i % 3) * 0.2, model, if i % 2 == 0 then ROCK else ROCK_DARK)
	end
	local foamLine = {
		{ Vector3.new(-134, 0.4, 44), 0.2 },
		{ Vector3.new(-138, 0.4, 88), -0.1 },
		{ Vector3.new(140, 0.4, 48), 0.15 },
		{ Vector3.new(136, 0.4, 94), -0.2 },
		{ Vector3.new(-24, 0.4, 160), 1.4 },
		{ Vector3.new(30, 0.4, 162), 1.6 },
	}
	for _, spec in foamLine do
		foam(spec[1], spec[2], model)
	end
	driftwood(Vector3.new(-128, BEACH_Y, 52), 0.6, model)
	driftwood(Vector3.new(132, BEACH_Y, 58), -0.4, model)
	driftwood(Vector3.new(8, BEACH_Y, 154), 1.2, model)
	shell(Vector3.new(-124, BEACH_Y, 60), WHITE, model)
	shell(Vector3.new(128, BEACH_Y, 70), PINK, model)
	shell(Vector3.new(-16, BEACH_Y, 150), SAND_DARK, model)
	shell(Vector3.new(22, BEACH_Y, 152), WHITE, model)
	jetty(Vector3.new(-150, BEACH_Y, 60), 1.2, model)
	jetty(Vector3.new(156, BEACH_Y, 64), -1.1, model)
	rowboat(Vector3.new(-142, 0.6, 66), 1.0, model)
	coralHead(Vector3.new(-156, -0.6, 28), PINK, model)
	coralHead(Vector3.new(158, -0.6, 26), ORANGE, model)
	coralHead(Vector3.new(6, -0.6, 178), TEAL, model)
	coralHead(Vector3.new(-60, -0.5, 164), FLOWER_RED, model)
end

-- === plaza ===
-- Builds a decorative stone planter with soil and a small palm.
-- Returns nothing.
local function planter(at: Vector3, parent: Instance)
	vcyl("Planter", at + Vector3.new(0, 0.7, 0), 1.4, 2.6, STONE, Enum.Material.Slate, parent, true)
	vcyl("Soil", at + Vector3.new(0, 1.35, 0), 0.3, 2.2, SAND_DARK, Enum.Material.Ground, parent, true, false)
	buildPalm(at, Vector3.new(0.2, 0, 0.2), parent, 0.55)
end

-- === plaza ===
-- Builds the Totem model: the island's landmark, a carved tiki totem on the plaza with a glowing gem crown.
-- Returns nothing.
local function buildTotem(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Totem"
	model.Parent = parent
	local base = Vector3.new(0, WALK_Y, 22)
	decor("TotemBase", Vector3.new(14, 1.2, 14), CFrame.new(base + Vector3.new(0, 0.6, 0)), STONE_DARK, Enum.Material.Slate, model, Enum.PartType.Cylinder)
	decor("TotemTier1", Vector3.new(7, 6, 7), CFrame.new(base + Vector3.new(0, 4.2, 0)), WOOD_DARK, Enum.Material.Wood, model)
	decor("TotemTier2", Vector3.new(6, 5, 6), CFrame.new(base + Vector3.new(0, 9.8, 0)), WOOD, Enum.Material.Wood, model)
	decor("TotemTier3", Vector3.new(5, 4.5, 5), CFrame.new(base + Vector3.new(0, 14.6, 0)), WOOD_DARK, Enum.Material.Wood, model)
	decor("TotemBand1", Vector3.new(7.8, 0.8, 7.8), CFrame.new(base + Vector3.new(0, 7.4, 0)), STONE, Enum.Material.Slate, model)
	decor("TotemBand2", Vector3.new(6.8, 0.8, 6.8), CFrame.new(base + Vector3.new(0, 12.5, 0)), STONE, Enum.Material.Slate, model)
	decor("TotemBrow", Vector3.new(7.4, 0.8, 0.9), CFrame.new(base + Vector3.new(0, 6.4, -3.4)), STONE_DARK, Enum.Material.Slate, model)
	decor("TotemMouth", Vector3.new(3.4, 0.9, 0.6), CFrame.new(base + Vector3.new(0, 2.6, -3.5)), Color3.fromRGB(24, 20, 18), Enum.Material.Slate, model)
	for _, sx in ipairs({ -1, 1 }) do
		local eye = decor("TotemEye", Vector3.new(1.1, 1.1, 0.7), CFrame.new(base + Vector3.new(sx * 1.9, 5.4, -3.5)), LAMP, Enum.Material.Neon, model)
		glow(eye, Color3.fromRGB(255, 220, 120), 8)
	end
	for _, sx in ipairs({ -1, 1 }) do
		decor("TotemFin", Vector3.new(0.7, 3.4, 3.4), CFrame.new(base + Vector3.new(sx * 4.2, 9.8, 0)), RED, Enum.Material.Fabric, model)
	end
	local gem = decor("TotemGem", Vector3.new(2.6, 2.6, 2.6), CFrame.new(base + Vector3.new(0, 18.4, 0)), GOLD, Enum.Material.Neon, model)
	glow(gem, GOLD, 22)
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 34
	light.Brightness = 2.4
	light.Parent = gem
	for _, corner in ipairs({ Vector3.new(-7.5, 0, -7.5), Vector3.new(7.5, 0, -7.5), Vector3.new(-7.5, 0, 7.5), Vector3.new(7.5, 0, 7.5) }) do
		local at = base + corner
		vcyl("TotemTorch", at + Vector3.new(0, 3.0, 0), 6.0, 0.34, WOOD_DARK, Enum.Material.Wood, model, true)
		local flame = decor("TotemFlame", Vector3.new(1.2, 1.6, 1.2), CFrame.new(at + Vector3.new(0, 6.4, 0)), Color3.fromRGB(255, 150, 60), Enum.Material.Neon, model)
		glow(flame, Color3.fromRGB(255, 150, 60), 14)
	end
end

-- Builds the PlazaDress model: paving, rebirth step, planters, light posts, string lights, sign border and flag.
-- Returns nothing.
local function buildPlazaDress(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "PlazaDress"
	model.Parent = parent
	for col = -2, 2 do
		for row = -1, 1 do
			local tone = if (col + row) % 2 == 0 then STONE else Color3.fromRGB(196, 188, 174)
			decor("PlazaStone", Vector3.new(7.4, 0.16, 6.4), CFrame.new(col * 8, WALK_Y + 0.12, 22 + row * 8), tone, Enum.Material.Cobblestone, model, nil, nil, false)
		end
	end
	decor("RebirthStep", Vector3.new(12, 0.4, 12), CFrame.new(0, WALK_Y + 0.25, 32), STONE_DARK, Enum.Material.Slate, model, Enum.PartType.Cylinder)
	planter(Vector3.new(-20, WALK_Y, 8), model)
	planter(Vector3.new(20, WALK_Y, 8), model)
	planter(Vector3.new(-20, WALK_Y, 36), model)
	local posts = { Vector3.new(-24, WALK_Y, 4), Vector3.new(24, WALK_Y, 4), Vector3.new(-24, WALK_Y, 40), Vector3.new(24, WALK_Y, 40) }
	for _, at in posts do
		vcyl("LightPost", at + Vector3.new(0, 3.2, 0), 6.4, 0.4, WOOD_DARK, Enum.Material.Wood, model, true)
	end
	buildWire(posts[1] + Vector3.new(0, 6.4, 0), posts[2] + Vector3.new(0, 6.4, 0), model)
	buildWire(posts[3] + Vector3.new(0, 6.4, 0), posts[4] + Vector3.new(0, 6.4, 0), model)
	local z = 12
	decor("SignBorder", Vector3.new(18.4, 4.2, 0.3), CFrame.new(0, 8.2, z + 0.45), WOOD_DARK, Enum.Material.Wood, model)
	local lampL = decor("SignLamp", Vector3.new(0.8, 1.0, 0.8), CFrame.new(-9.2, 8.4, z), LAMP, Enum.Material.Neon, model, nil, nil, false)
	local lampR = decor("SignLamp", Vector3.new(0.8, 1.0, 0.8), CFrame.new(9.2, 8.4, z), LAMP, Enum.Material.Neon, model, nil, nil, false)
	glow(lampL, LAMP, 12)
	glow(lampR, LAMP, 12)
	vcyl("FlagPole", Vector3.new(0, 12.4, z), 4.0, 0.28, WOOD, Enum.Material.Wood, model, true)
	decor("Flag", Vector3.new(2.4, 1.4, 0.12), CFrame.new(1.4, 13.6, z), RED, Enum.Material.Fabric, model, nil, nil, false)
	buildTotem(parent)
end

-- === composition ===
-- Builds all scenery under parent and strings hut lights between the base roof peaks in peaks.
-- Returns nothing.
local function buildScenery(parent: Instance, peaks: { Vector3 })
	buildFishingCorner(Vector3.new(-34, BEACH_Y, -6), 0.4, parent)
	buildFishingCorner(Vector3.new(34, BEACH_Y, -4), -0.35, parent)
	buildFruitStall(parent)
	buildBeachClub(parent)
	buildTidePools(parent)
	buildJungle(parent)
	buildLookout(parent)
	buildShrine(parent)
	buildBoatDock(parent)
	scatterGreens(parent)
	local lights = Instance.new("Model")
	lights.Name = "LanternPosts"
	lights.Parent = parent
	local posts = {
		Vector3.new(-40, GRASS_Y, 22),
		Vector3.new(40, GRASS_Y, 22),
		Vector3.new(0, GRASS_Y, 56),
		Vector3.new(-30, GRASS_Y, 78),
		Vector3.new(30, GRASS_Y, 78),
		Vector3.new(0, GRASS_Y, 104),
		Vector3.new(-60, GRASS_Y, 118),
		Vector3.new(60, GRASS_Y, 118),
		Vector3.new(-122, BEACH_Y, 74),
		Vector3.new(122, BEACH_Y, 70),
		Vector3.new(0, BEACH_Y, 146),
	}
	for _, at in posts do
		buildLanternPost(at, lights)
	end
	local buoys = {
		Vector3.new(-40, 0.6, -55),
		Vector3.new(48, 0.55, -60),
		Vector3.new(-190, 0.6, 70),
		Vector3.new(175, 0.55, 20),
		Vector3.new(60, 0.5, 210),
	}
	local buoyModel = Instance.new("Model")
	buoyModel.Name = "Buoys"
	buoyModel.Parent = parent
	for _, at in buoys do
		buildBuoy(at, buoyModel)
	end
	local wires = Instance.new("Model")
	wires.Name = "HutLights"
	wires.Parent = parent
	for base = 1, 3 do
		buildWire(peaks[base] + Vector3.new(0, 0.4, 3), peaks[base + 1] + Vector3.new(0, 0.4, -3), wires)
	end
	for base = 5, 7 do
		buildWire(peaks[base] + Vector3.new(0, 0.4, 3), peaks[base + 1] + Vector3.new(0, 0.4, -3), wires)
	end
	buildWire(Vector3.new(-168, BEACH_Y + 6, 80), Vector3.new(-156, BEACH_Y + 5.6, 75), wires)
	buildWire(Vector3.new(18, GRASS_Y + 6.2, 8), Vector3.new(26, GRASS_Y + 6.2, 8), wires)
	buildMarketLane(parent)
	buildPalmGrove(parent)
	buildPond(parent)
	buildFlowerBeds(parent)
	buildCoast(parent)
	buildPlazaDress(parent)
end

-- === composition ===
-- Builds the whole island under workspace.Pulau: lighting, sea, land, paths, piers, eight bases, scenery.
-- Returns the Anchors table (pierSpawns, plotCentres, pedestals, rebirth, centre).
local function build(): Anchors
	applyLighting()

	local root = Instance.new("Folder")
	root.Name = "Pulau"
	root.Parent = workspace

	local sea = Instance.new("Model")
	sea.Name = "Sea"
	sea.Parent = root
	buildSea(sea)

	local land = Instance.new("Model")
	land.Name = "Land"
	land.Parent = root
	local rebirth, centre = buildLand(land)
	buildPaths(land)

	local piers = Instance.new("Model")
	piers.Name = "Piers"
	piers.Parent = root
	local pierSpawns = {
		buildPier(-16, "PierSpawn1", piers),
		buildPier(16, "PierSpawn2", piers),
	}
	buildSign(piers)

	local bases = Instance.new("Model")
	bases.Name = "Bases"
	bases.Parent = root
	local plotCentres: { BasePart } = {}
	local pedestals: { { BasePart } } = {}
	local peaks: { Vector3 } = {}
	local zs = { -8, 34, 76, 118 }
	for side = -1, 1, 2 do
		for slot, z in zs do
			local at = Vector3.new(side * 118, PLOT_Y, z)
			local facing = Vector3.new(side, 0, 0)
			local index = (if side < 0 then 0 else 4) + slot
			local plot, tops, peak = buildBase(index, at, facing, bases)
			table.insert(plotCentres, plot)
			table.insert(pedestals, tops)
			table.insert(peaks, peak)
		end
	end

	local scenery = Instance.new("Model")
	scenery.Name = "Scenery"
	scenery.Parent = root
	buildScenery(scenery, peaks)

	root:SetAttribute("DecorParts", decorCount)
	return {
		pierSpawns = pierSpawns,
		plotCentres = plotCentres,
		pedestals = pedestals,
		rebirth = rebirth,
		centre = centre,
	}
end

return build()
