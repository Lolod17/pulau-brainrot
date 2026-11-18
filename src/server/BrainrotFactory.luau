--!strict

local Cast = require(script.Parent:WaitForChild("Cast"))

type Entry = Cast.Entry

local SIGN_WIDTH = 7
local SIGN_HEIGHT = 3.4
local SIGN_DEPTH = 0.2
local SIGN_GAP = 2

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
	particles.LightEmission = 0.65
	particles.Size = NumberSequence.new(0.55, 1.3)
	particles.Transparency = NumberSequence.new(0.25, 1)
	particles.Lifetime = NumberRange.new(1.2, 1.8)
	particles.Rate = 14
	particles.Speed = NumberRange.new(0.5, 1.3)
	particles.SpreadAngle = Vector2.new(25, 25)
	particles.Parent = attachment

	if entry.id ~= "kraken_emas" then
		return
	end

	particles.Size = NumberSequence.new(1.8, 3.6)
	particles.Rate = 34
	particles.Speed = NumberRange.new(0.8, 1.8)

	local light = Instance.new("PointLight")
	light.Name = "GoldLight"
	light.Color = GOLD
	light.Brightness = 5
	light.Range = 18
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
	trail.Lifetime = 2.6
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 0.85
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
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Width0 = 1.15
	beam.Width1 = 1.15
	beam.Segments = 12
	beam.CurveSize0 = 2.4
	beam.CurveSize1 = -2.4
	beam.Transparency = NumberSequence.new(0.05)
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
	flame.Rate = 28
	flame.Speed = NumberRange.new(2, 4)
	flame.SpreadAngle = Vector2.new(14, 14)
	flame.LightEmission = 1
	flame.EmissionDirection = Enum.NormalId.Top
	flame.Parent = attachment

	local glow = Instance.new("PointLight")
	glow.Name = "FlameLight"
	glow.Color = Color3.fromRGB(255, 140, 40)
	glow.Brightness = 2
	glow.Range = 9
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

	return model
end

function Factory.standOn(model: Model, surface: BasePart)
	local minV = bodyAABB(model)
	local surfaceTop = surface.Position.Y + surface.Size.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, surfaceTop - minV.Y, 0))
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
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end
	local minV, maxV = bodyAABB(model)
	local headTop = head.Position.Y + head.Size.Y / 2
	local delta = Vector3.new(head.Position.X - (minV.X + maxV.X) / 2, (headTop + 0.4) - minV.Y, head.Position.Z - (minV.Z + maxV.Z) / 2)
	model:PivotTo(model:GetPivot() + delta)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = head
	weld.Part1 = anchor
	weld.Parent = anchor
	model.Parent = character
end

function Factory.drop(model: Model)
	local anchor = model.PrimaryPart
	local carry = anchor and anchor:FindFirstChild("CarryWeld")
	if carry then
		carry:Destroy()
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
