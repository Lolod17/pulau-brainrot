--!strict

local RunService = game:GetService("RunService")

local Cast = require(script.Parent:WaitForChild("Cast"))

type Entry = Cast.Entry

local SIGN_WIDTH = 7
local SIGN_HEIGHT = 3.4
local SIGN_DEPTH = 0.2
local SIGN_GAP = 9

local CHARCOAL = Color3.fromRGB(32, 32, 36)
local PLATE = Color3.fromRGB(14, 14, 18)
local GOLD = Color3.fromRGB(255, 206, 64)
local INCOME = Color3.fromRGB(120, 230, 130)
local NAME_COLOR = Color3.fromRGB(245, 245, 248)

local RARITY_COLOR: { [string]: Color3 } = {
	Common = Color3.fromRGB(206, 210, 218),
	Uncommon = Color3.fromRGB(46, 184, 138),
	Rare = Color3.fromRGB(80, 140, 255),
	Epic = Color3.fromRGB(186, 110, 255),
	Legendary = Color3.fromRGB(255, 150, 48),
	Mythic = Color3.fromRGB(230, 48, 48),
	["Ultra Rare"] = Color3.fromRGB(255, 206, 64),
}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 70)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 220, 110)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(70, 150, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 90, 255)),
})

local function partAABB(piece: BasePart): (Vector3, Vector3)
	local cf = piece.CFrame
	local half = piece.Size / 2
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local corner = cf:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
				minV = Vector3.new(math.min(minV.X, corner.X), math.min(minV.Y, corner.Y), math.min(minV.Z, corner.Z))
				maxV = Vector3.new(math.max(maxV.X, corner.X), math.max(maxV.Y, corner.Y), math.max(maxV.Z, corner.Z))
			end
		end
	end
	return minV, maxV
end

local function bodyAABB(model: Model): (Vector3, Vector3)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "NameSign" then
			local low, high = partAABB(descendant)
			minV = Vector3.new(math.min(minV.X, low.X), math.min(minV.Y, low.Y), math.min(minV.Z, low.Z))
			maxV = Vector3.new(math.max(maxV.X, high.X), math.max(maxV.Y, high.Y), math.max(maxV.Z, high.Z))
		end
	end
	return minV, maxV
end

local function scaleModel(model: Model, scale: number)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Size *= scale
			descendant.CFrame = CFrame.new(descendant.Position * scale) * (descendant.CFrame - descendant.Position)
		end
	end
end

local function addAura(anchor: BasePart, entry: Entry)
	local attachment = Instance.new("Attachment")
	attachment.Name = "AuraAttachment"
	attachment.Parent = anchor

	local particles = Instance.new("ParticleEmitter")
	particles.Name = "Aura"
	particles.Color = ColorSequence.new(entry.aura)
	particles.LightEmission = 0.2
	particles.Size = NumberSequence.new(0.55, 1.3)
	particles.Transparency = NumberSequence.new(0.25, 1)
	particles.Lifetime = NumberRange.new(1.0, 1.4)
	particles.Rate = 10
	particles.Speed = NumberRange.new(0.5, 1.3)
	particles.SpreadAngle = Vector2.new(25, 25)
	particles.Parent = attachment

	if entry.id ~= "kraken_emas" then
		return
	end

	particles.Size = NumberSequence.new(1.8, 3.6)
	particles.Rate = 16
	particles.Speed = NumberRange.new(0.8, 1.8)

	local light = Instance.new("PointLight")
	light.Name = "GoldLight"
	light.Color = GOLD
	light.Brightness = 2
	light.Range = 10
	light.Parent = anchor

	local left = Instance.new("Attachment")
	left.Name = "TrailLeft"
	left.Position = Vector3.new(-0.4, -0.2, 1.5)
	left.Parent = anchor
	local right = Instance.new("Attachment")
	right.Name = "TrailRight"
	right.Position = Vector3.new(-0.4, -0.2, -1.5)
	right.Parent = anchor

	local trail = Instance.new("Trail")
	trail.Name = "RainbowTrail"
	trail.Attachment0 = left
	trail.Attachment1 = right
	trail.Lifetime = 1.6
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 0.4
	trail.LightInfluence = 0
	trail.Color = RAINBOW
	trail.WidthScale = NumberSequence.new(1)
	trail.Transparency = NumberSequence.new(0.05, 1)
	trail.Parent = anchor

	local beam = Instance.new("Beam")
	beam.Name = "RainbowBeam"
	beam.Attachment0 = left
	beam.Attachment1 = right
	beam.Color = RAINBOW
	beam.LightEmission = 0.3
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Width0 = 1.15
	beam.Width1 = 1.15
	beam.Segments = 12
	beam.CurveSize0 = 2.4
	beam.CurveSize1 = -2.4
	beam.Transparency = NumberSequence.new(0.3)
	beam.Parent = anchor
end

local function addFlame(model: Model, anchor: BasePart)
	local hole = model:FindFirstChild("Blowhole")
	local attachment = Instance.new("Attachment")
	attachment.Name = "BlowholeFlame"
	if hole and hole:IsA("BasePart") then
		attachment.Position = anchor.CFrame:PointToObjectSpace(hole.Position + Vector3.new(0, hole.Size.Y / 2, 0))
	else
		attachment.Position = Vector3.new(0, anchor.Size.Y / 2, 0)
	end
	attachment.Parent = anchor

	local flame = Instance.new("ParticleEmitter")
	flame.Name = "Flame"
	flame.Color = ColorSequence.new(Color3.fromRGB(255, 236, 120), Color3.fromRGB(255, 80, 16))
	flame.Size = NumberSequence.new(0.55, 0.08)
	flame.Transparency = NumberSequence.new(0.05, 1)
	flame.Lifetime = NumberRange.new(0.35, 0.7)
	flame.Rate = 16
	flame.Speed = NumberRange.new(2, 4)
	flame.SpreadAngle = Vector2.new(14, 14)
	flame.LightEmission = 0.3
	flame.EmissionDirection = Enum.NormalId.Top
	flame.Parent = attachment

	local glow = Instance.new("PointLight")
	glow.Name = "FlameLight"
	glow.Color = Color3.fromRGB(255, 140, 40)
	glow.Brightness = 1
	glow.Range = 8
	glow.Parent = anchor
end

local function formatIncome(amount: number): string
	local digits = tostring(math.floor(amount))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return grouped
end

local function makeLabel(name: string, text: string, textSize: number, color: Color3, order: number): TextLabel
	local row = Instance.new("TextLabel")
	row.Name = name
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -12, 0, textSize + 8)
	row.Font = Enum.Font.GothamBold
	row.Text = text
	row.TextColor3 = color
	row.TextSize = textSize
	row.TextScaled = false
	row.TextWrapped = false
	row.TextXAlignment = Enum.TextXAlignment.Center
	row.TextYAlignment = Enum.TextYAlignment.Center
	row.LayoutOrder = order
	return row
end

local function buildFace(sign: BasePart, face: Enum.NormalId, entry: Entry)
	local gui = Instance.new("SurfaceGui")
	gui.Name = if face == Enum.NormalId.Front then "Front" else "Back"
	gui.Face = face
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 150
	gui.Parent = sign

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = PLATE
	plate.BorderSizePixel = 0
	plate.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = plate

	local locked = makeLabel("Locked", "LOCKED", 68, Color3.fromRGB(42, 28, 4), 1)
	locked.BackgroundColor3 = GOLD
	locked.BackgroundTransparency = 0
	locked.Visible = false
	locked.Parent = plate

	makeLabel("Name", entry.name, 104, NAME_COLOR, 2).Parent = plate
	makeLabel("Rarity", entry.rarity, 68, RARITY_COLOR[entry.rarity] or NAME_COLOR, 3).Parent = plate
	makeLabel("Income", string.format("+$%s/s", formatIncome(entry.income)), 68, INCOME, 4).Parent = plate
end

local function setLocked(model: Model, locked: boolean)
	model:SetAttribute("Locked", locked)
	local sign = model:FindFirstChild("NameSign")
	if not sign then
		return
	end
	for _, faceName in { "Front", "Back" } do
		local gui = sign:FindFirstChild(faceName)
		local plate = gui and gui:FindFirstChild("Plate")
		local strip = plate and plate:FindFirstChild("Locked")
		if strip and strip:IsA("GuiObject") then
			strip.Visible = locked
		end
	end
end

local function showLocked(model: Model)
	setLocked(model, model:GetAttribute("Locked") == true)
end

local function buildSign(model: Model, entry: Entry, minV: Vector3, maxV: Vector3): BasePart
	local sign = Instance.new("Part")
	sign.Name = "NameSign"
	sign.Size = Vector3.new(SIGN_WIDTH, SIGN_HEIGHT, SIGN_DEPTH)
	sign.Color = CHARCOAL
	sign.Material = Enum.Material.SmoothPlastic
	sign.Anchored = true
	sign.CanCollide = false
	sign.CanQuery = false
	sign.Massless = true
	sign.CastShadow = false
	local centerX = (minV.X + maxV.X) / 2
	local centerZ = (minV.Z + maxV.Z) / 2
	sign.CFrame = CFrame.new(centerX, maxV.Y + SIGN_GAP + SIGN_HEIGHT / 2, centerZ)
	sign.Parent = model

	buildFace(sign, Enum.NormalId.Front, entry)
	buildFace(sign, Enum.NormalId.Back, entry)
	return sign
end

local function weldTo(root: BasePart, other: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = other
	weld.Parent = root
end

local function weldAssembly(model: Model, root: BasePart)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			weldTo(root, descendant)
		end
	end
end

local Factory = {}

local IDLE_BUDGET = 200
local idleList: { Model } = {}

type Anim = {
	parts: { BasePart },
	bases: { CFrame },
	kind: string,
	speed: number,
	amp: number,
	ring: BasePart?,
	ringBase: CFrame?,
	spin: number,
}

type IdleRecord = {
	anim: Anim,
	model: Model,
}

local idleRecords: { [Model]: IdleRecord } = {}
local idleTicker: RBXScriptConnection? = nil

local function makeAnim(kind: string, parts: { BasePart }, speed: number, amp: number): Anim
	local bases: { CFrame } = {}
	for i, part in parts do
		bases[i] = part.CFrame
	end
	return {
		parts = parts,
		bases = bases,
		kind = kind,
		speed = speed,
		amp = amp,
		ring = nil,
		ringBase = nil,
		spin = 0,
	}
end

local function collect(model: Model, names: { string }): { BasePart }
	local found: { BasePart } = {}
	for _, name in names do
		local part = model:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			table.insert(found, part)
		end
	end
	return found
end

local function buildAnim(model: Model, id: string): Anim?
	if id == "ikan_terbang" then
		return makeAnim("fish", collect(model, { "Body", "WingL", "WingR", "WingTipL", "WingTipR" }), 2.2, 1)
	elseif id == "kepiting_disco" then
		local anim = makeAnim("crab", collect(model, { "Body", "ClawL", "ClawR", "PincerLUp", "PincerLLo", "PincerRUp", "PincerRLo" }), 1.6, 1)
		local disco = model:FindFirstChild("DiscoBall")
		if disco and disco:IsA("BasePart") then
			anim.ring = disco
			anim.ringBase = disco.CFrame
			anim.spin = 2.4
		end
		return anim
	elseif id == "penyu_turbo" then
		return makeAnim("turtle", collect(model, { "Body", "FlipperFL", "FlipperFR", "FlipperBL", "FlipperBR" }), 0.9, 1)
	elseif id == "gurita_dj" then
		return makeAnim("octopus", collect(model, { "Body", "Tentacle1", "Tentacle2", "Tentacle3", "Tentacle4", "Tentacle5", "Tentacle6" }), 1.4, 1)
	elseif id == "hiu_bajak_laut" then
		return makeAnim("shark", collect(model, { "Body", "TailTop", "TailBot", "PecL", "PecR" }), 1.8, 1)
	elseif id == "paus_api" then
		return makeAnim("whale", collect(model, { "Body", "FinL", "FinR", "FlukeL", "FlukeR" }), 0.8, 1)
	elseif id == "kraken_emas" then
		local anim = makeAnim(
			"kraken",
			collect(model, {
				"Body",
				"Arm1a", "Arm1b", "Arm2a", "Arm2b", "Arm3a", "Arm3b",
				"Arm4a", "Arm4b", "Arm5a", "Arm5b", "Arm6a", "Arm6b",
			}),
			1.1,
			1
		)
		local crown = model:FindFirstChild("CrownBand")
		if crown and crown:IsA("BasePart") then
			anim.ring = crown
			anim.ringBase = crown.CFrame
			anim.spin = 1.2
		end
		return anim
	end
	return nil
end

local spinAccum: { [Anim]: number } = {}

local function tickSpin(anim: Anim, dt: number): number
	local now = (spinAccum[anim] or 0) + dt * anim.spin
	spinAccum[anim] = now
	return now
end

local function tickAnim(anim: Anim, t: number, dt: number)
	local k = anim.kind
	local parts = anim.parts
	local bases = anim.bases
	local amp = anim.amp
	local s = t * anim.speed
	if k == "fish" then
		local flap = math.sin(s * 2) * 0.32
		local tilt = math.sin(s * 0.7) * 0.14
		for i = 1, #parts do
			local base = bases[i]
			local wobble = flap * amp
			if i == 1 then
				parts[i].CFrame = base * CFrame.Angles(0, 0, tilt)
			else
				parts[i].CFrame = base * CFrame.Angles(wobble * (if i <= 3 then 1 else 1.4), 0, 0) * CFrame.new(0, 0, math.sin(s * 0.7) * 0.02)
			end
		end
	elseif k == "crab" then
		local open = (math.sin(s * 1.5) + 1) * 0.5
		local bob = math.sin(s * 0.6) * 0.06
		for i = 1, #parts do
			local base = bases[i]
			if i == 1 then
				parts[i].CFrame = base * CFrame.new(0, bob, 0)
			elseif i == 2 or i == 3 then
				parts[i].CFrame = base * CFrame.Angles(math.rad(open * 10), 0, math.rad(open * (if i == 2 then 12 else -12)))
			else
				local sign = if string.find(parts[i].Name, "R", 1, true) then -1 else 1
				local vert = if string.find(parts[i].Name, "Up", 1, true) then 1 else -1
				parts[i].CFrame = base * CFrame.Angles(math.rad(vert * open * 18 * sign), 0, 0)
			end
		end
	elseif k == "turtle" then
		local stroke = math.sin(s) * 0.35
		local sway = math.sin(s * 0.4) * 0.05
		for i = 1, #parts do
			local base = bases[i]
			if i == 1 then
				parts[i].CFrame = base * CFrame.Angles(0, sway, 0)
			else
				local side = if string.find(parts[i].Name, "R", 1, true) then -1 else 1
				local vert = if string.find(parts[i].Name, "F", 1, true) then 1 else 0.7
				parts[i].CFrame = base * CFrame.Angles(math.rad(math.sin(s + vert) * 14 * amp), 0, math.rad(stroke * side * 10 * vert))
			end
		end
	elseif k == "octopus" then
		local pulse = math.sin(s * 1.2) * 0.08
		for i = 1, #parts do
			local base = bases[i]
			if i == 1 then
				parts[i].CFrame = base * CFrame.new(0, pulse, 0)
			else
				local wave = math.sin(s * 1.6 + (i - 2) * 0.9) * 0.32
				local side = if (i % 2) == 0 then 1 else -1
				parts[i].CFrame = base * CFrame.Angles(wave * amp, 0, side * wave * 0.5)
			end
		end
	elseif k == "shark" then
		local sway = math.sin(s) * 0.22
		for i = 1, #parts do
			local base = bases[i]
			if i == 1 then
				parts[i].CFrame = base * CFrame.Angles(0, sway * 0.4, 0)
			elseif i <= 3 then
				parts[i].CFrame = base * CFrame.Angles(0, sway * amp, 0)
			else
				parts[i].CFrame = base * CFrame.Angles(math.sin(s + 0.5) * 0.12, sway * 0.5, 0)
			end
		end
	elseif k == "whale" then
		local bob = math.sin(s) * 0.18
		local fan = math.sin(s * 0.8) * 0.22
		for i = 1, #parts do
			local base = bases[i]
			if i == 1 then
				parts[i].CFrame = base * CFrame.new(0, bob, 0) * CFrame.Angles(math.rad(bob * 6), 0, 0)
			elseif i <= 3 then
				parts[i].CFrame = base * CFrame.Angles(0, 0, fan * amp * (if i == 2 then 1 else -1))
			else
				parts[i].CFrame = base * CFrame.Angles(math.rad(math.sin(s * 0.9) * 10), 0, 0)
			end
		end
	elseif k == "kraken" then
		local bob = math.sin(s * 0.5) * 0.1
		for i = 1, #parts do
			local base = bases[i]
			if i == 1 then
				parts[i].CFrame = base * CFrame.new(0, bob, 0)
			else
				local seq = math.sin(s * 1.3 - (i - 2) * 0.55)
				local curl = seq * 0.28 * amp
				parts[i].CFrame = base * CFrame.Angles(curl, seq * 0.12, curl * 0.6) * CFrame.new(0, math.abs(seq) * 0.05, 0)
			end
		end
	end
	if anim.ring and anim.ringBase then
		local angle = tickSpin(anim, dt)
		anim.ring.CFrame = anim.ringBase * CFrame.Angles(0, angle, 0)
	end
end

local spinAccum: { [Anim]: number } = {}
local idleCursor = 1

local function stepIdle(dt: number)
	local budget = IDLE_BUDGET
	local t = os.clock()
	local visited = 0
	local total = #idleList
	if total == 0 then
		return
	end
	if idleCursor > total then
		idleCursor = 1
	end
	while visited < total and budget > 0 do
		local index = idleCursor
		local model = idleList[index]
		local record = idleRecords[model]
		visited += 1
		if record and model.Parent then
			tickAnim(record.anim, t, dt)
			budget -= 1
			idleCursor = index + 1
			if idleCursor > #idleList then
				idleCursor = 1
			end
		else
			if record then
				idleRecords[model] = nil
			end
			local last = #idleList
			if index ~= last then
				idleList[index] = idleList[last]
			else
				idleCursor = 1
			end
			idleList[last] = nil
			if idleCursor > #idleList then
				idleCursor = 1
			end
			total = #idleList
			if total == 0 then
				return
			end
		end
	end
end

local function startIdle()
	if idleTicker then
		return
	end
	idleTicker = RunService.Heartbeat:Connect(stepIdle)
end

function Factory.animate(model: Model)
	if idleRecords[model] then
		return
	end
	local id = model:GetAttribute("BrainrotId")
	if typeof(id) ~= "string" then
		return
	end
	local anim = buildAnim(model, id)
	if not anim then
		return
	end
	idleRecords[model] = { anim = anim, model = model }
	table.insert(idleList, model)
	startIdle()
end

function Factory.freeze(model: Model)
	if not idleRecords[model] then
		return
	end
	idleRecords[model] = nil
end

function Factory.create(entry: Entry, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = entry.name
	model:SetAttribute("BrainrotId", entry.id)
	model:SetAttribute("Rarity", entry.rarity)
	model:SetAttribute("Income", entry.income)
	model:SetAttribute("Locked", false)

	local root: BasePart? = nil
	for _, spec in entry.recipe do
		local piece = Instance.new("Part")
		piece.Name = spec.name
		piece.Shape = spec.shape
		piece.Size = spec.size
		piece.Color = spec.color
		piece.Material = spec.material
		piece.Anchored = true
		piece.CanCollide = false
		piece.CFrame = spec.offset
		piece.Parent = model
		if spec.name == "Body" then
			root = piece
		end
	end
	assert(root, "recipe needs a Body part")

	local minV, maxV = bodyAABB(model)
	local measured = math.max(maxV.Y - minV.Y, 0.001)
	scaleModel(model, entry.height / measured)

	if entry.id == "paus_api" then
		addFlame(model, root)
	end
	addAura(root, entry)

	minV, maxV = bodyAABB(model)
	local sign = buildSign(model, entry, minV, maxV)
	model.PrimaryPart = root

	local centerX = (minV.X + maxV.X) / 2
	local centerZ = (minV.Z + maxV.Z) / 2
	model:PivotTo(model:GetPivot() + Vector3.new(position.X - centerX, position.Y - minV.Y, position.Z - centerZ))

	weldAssembly(model, root)
	sign.Anchored = false
	root.CanCollide = true

	model:GetAttributeChangedSignal("Locked"):Connect(function()
		showLocked(model)
	end)
	setLocked(model, model:GetAttribute("Locked") == true)

	Factory.animate(model)

	return model
end

function Factory.standOn(model: Model, surface: BasePart)
	local minV = bodyAABB(model)
	local surfaceTop = surface.Position.Y + surface.Size.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, surfaceTop - minV.Y, 0))
end

local function addCarryShadow(model: Model)
	local anchor = model.PrimaryPart
	if not anchor then
		return
	end
	local old = model:FindFirstChild("CarryShadow")
	if old then
		old:Destroy()
	end
	local minV, maxV = bodyAABB(model)
	local shadow = Instance.new("Part")
	shadow.Name = "CarryShadow"
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Size = Vector3.new(0.04, math.max(maxV.X - minV.X, 1) * 0.9, math.max(maxV.Z - minV.Z, 1) * 0.9)
	shadow.Color = Color3.fromRGB(0, 0, 0)
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Transparency = 0.42
	shadow.Anchored = false
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	shadow.Massless = true
	shadow.CastShadow = false
	shadow.CFrame = CFrame.new((minV.X + maxV.X) / 2, minV.Y - 0.02, (minV.Z + maxV.Z) / 2) * CFrame.Angles(0, 0, math.rad(90))
	shadow.Parent = model
	weldTo(anchor, shadow)
end

function Factory.weldAboveHead(model: Model, character: Model)
	local head = character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		head = character:FindFirstChild("HumanoidRootPart")
	end
	local anchor = model.PrimaryPart
	if not (head and head:IsA("BasePart")) or not anchor then
		return
	end
	local old = anchor:FindFirstChild("CarryWeld")
	if old then
		old:Destroy()
	end
	local characterHead = character:FindFirstChild("Head") :: BasePart?
	if characterHead then
		local oldMotor = characterHead:FindFirstChild("CarryWeld")
		if oldMotor then
			oldMotor:Destroy()
		end
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end
	local minV, maxV = bodyAABB(model)
	local headTop = head.Position.Y + head.Size.Y / 2
	local delta = Vector3.new(head.Position.X - (minV.X + maxV.X) / 2, (headTop + 2) - minV.Y, head.Position.Z - (minV.Z + maxV.Z) / 2)
	model:PivotTo(model:GetPivot() + delta)
	local carryMotor = Instance.new("Motor6D")
	carryMotor.Name = "CarryWeld"
	carryMotor.Part0 = head
	carryMotor.Part1 = anchor
	carryMotor.C0 = CFrame.new(0, head.Size.Y / 2 + 2, 0) * CFrame.Angles(math.rad(8), 0, 0)
	carryMotor.C1 = CFrame.identity
	carryMotor.Parent = anchor
	model.Parent = character
	addCarryShadow(model)
end

local function stripCarry(model: Model, anchor: BasePart)
	local carry = anchor:FindFirstChild("CarryWeld")
	if carry then
		carry:Destroy()
	end
	local head = anchor.Parent
	if head and head:IsA("BasePart") then
		local leftover = head:FindFirstChild("CarryWeld")
		if leftover then
			leftover:Destroy()
		end
	end
	local shadow = model:FindFirstChild("CarryShadow")
	if shadow then
		shadow:Destroy()
	end
end

function Factory.drop(model: Model)
	local anchor = model.PrimaryPart
	if anchor then
		stripCarry(model, anchor)
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end
	if anchor then
		anchor.CanCollide = true
	end
	model.Parent = workspace
end

function Factory.remove(model: Model)
	Factory.freeze(model)
	model:Destroy()
end

function Factory.rehangSign(model: Model)
	local anchor = model.PrimaryPart
	local brainrotId = model:GetAttribute("BrainrotId")
	local entry = if typeof(brainrotId) == "string" then Cast.getById(brainrotId) else nil
	if not anchor or not entry then
		return
	end
	local existing = model:FindFirstChild("NameSign")
	if existing then
		existing:Destroy()
	end
	for _, child in anchor:GetChildren() do
		if child:IsA("WeldConstraint") and child.Name ~= "CarryWeld" and child.Part1 == nil then
			child:Destroy()
		end
	end
	local minV, maxV = bodyAABB(model)
	local sign = buildSign(model, entry, minV, maxV)
	local rotation = anchor.CFrame - anchor.CFrame.Position
	sign.CFrame = CFrame.new(sign.Position) * rotation
	sign.Anchored = false
	weldTo(anchor, sign)
	setLocked(model, model:GetAttribute("Locked") == true)
end

return Factory
