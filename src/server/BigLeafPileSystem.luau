local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BigLeafPileConfig = require(ReplicatedStorage.Shared.BigLeafPileConfig)
local LeafConfig = require(ReplicatedStorage.Shared.LeafConfig)
local LeafSpawner = require(script.Parent.LeafSpawner)

-- Big Leaf Piles: a handful of stationary, tall mounds spawned each round (5-10, see
-- BigLeafPileConfig) that take repeated Blower hits to "kill" -- killing one pays every player who
-- damaged it a batch of bonus leaves (real deliveries, via LeafSpawner.DeliverToZone, so they count
-- toward the round's own Goal too), silently, no notification. A self-contained module: RoundSystem
-- calls StartYardRound/StopYardRound the same way it already does for LeafSpawner/SackSystem, and
-- BlowerTool calls ApplyBlow once per blow tick the same way it already does for LeafSpawner.
local BigLeafPileSystem = {}

local pilesFolder

local spawnArea, cleanupZone
local groundTop = 0
local yardAvoidRegions = {}
local roundActive = false

-- pile Model -> { Health, MaxHealth, X, Z, Participants (set of Player -> true), Billboard, Fill }
local activePiles = {}

-- Single reused Part+ParticleEmitters for the kill burst (repositioned per use, same "one shared
-- VFX source" pattern LeafSpawner's own playConsumeVFX already established), plus tuning for the
-- fly-apart-and-fade dissolve every leaf in a killed pile plays before the model is actually
-- destroyed -- see killPile/animateAndDestroy below.
local burstVFXPart, burstEmitter, burstFlashEmitter

local KILL_ANIM_DURATION = 0.45
local KILL_ANIM_OUTWARD_STUDS = 3.5
local KILL_ANIM_RISE_STUDS = 2.5

-- Same small-local-copy pattern LeafSpawner/SackSystem already each use for their own spatial
-- checks, rather than reaching into another module's internals.
local function isInAvoidRegion(x, z)
	if not spawnArea then
		return false
	end
	local originX, originZ = spawnArea.Position.X, spawnArea.Position.Z
	for _, region in pairs(yardAvoidRegions) do
		local halfX = region.Size.X / 2
		local halfZ = region.Size.Z / 2
		local centerX = originX + region.Center.X
		local centerZ = originZ + region.Center.Z
		if x >= centerX - halfX and x <= centerX + halfX
			and z >= centerZ - halfZ and z <= centerZ + halfZ then
			return true
		end
	end
	return false
end

local function isInCleanupZone(x, z)
	if not cleanupZone then
		return false
	end
	local halfX = cleanupZone.Size.X / 2
	local halfZ = cleanupZone.Size.Z / 2
	local center = cleanupZone.Position
	return x >= center.X - halfX and x <= center.X + halfX
		and z >= center.Z - halfZ and z <= center.Z + halfZ
end

local function isFarEnoughFromOtherPiles(x, z)
	for _, state in pairs(activePiles) do
		local dx, dz = x - state.X, z - state.Z
		if math.sqrt(dx * dx + dz * dz) < BigLeafPileConfig.MinSpacing then
			return false
		end
	end
	return true
end

local function randomPilePosition()
	local center = spawnArea.Position
	local size = spawnArea.Size

	for _ = 1, 20 do
		local x = center.X + (math.random() - 0.5) * size.X
		local z = center.Z + (math.random() - 0.5) * size.Z
		if not isInAvoidRegion(x, z) and not isInCleanupZone(x, z) and isFarEnoughFromOtherPiles(x, z) then
			return x, z
		end
	end
	-- Couldn't find a clear spot after 20 tries (a very cluttered map) -- caller just spawns one
	-- fewer pile rather than risking an overlapping/inside-geometry placement.
	return nil, nil
end

local function pickColor()
	return LeafConfig.Colors[math.random(1, #LeafConfig.Colors)]
end

-- Densely scatters BigLeafPileConfig.LeafCount individual flat Leaf-shaped parts (same
-- LeafConfig.LeafSize/Colors every other leaf in the game already uses) through a dome-shaped
-- volume -- widest at the base, rounding to a point at the apex, like a real heap -- rather than
-- building one smooth solid shape, so this actually reads as a pile of real leaves up close.
-- Height sampling is biased toward the base (y^2.4) so the pile is dense/solid at the bottom and
-- tapers to a light cap at the top, the way a real pile settles under its own weight. Each leaf
-- gets a random yaw plus a small random pitch/roll jitter (bigger for leaves landing further out
-- toward the loose surface, smaller for ones compressed near the core) so it doesn't read as a
-- perfectly flat stack -- deliberately RANDOM jitter rather than a computed "lean away from
-- center" tilt, since a wrong sign/axis on a directional tilt would look visibly broken and this
-- can't be visually verified before the user tests it in Studio (see CLAUDE.md's own note on past
-- rotation-axis bugs); symmetric random jitter has no "backwards" failure mode.
-- Returns the model plus the health-bar Frame/BillboardGui so the caller can track/update them.
local function buildPileModel(x, z)
	local model = Instance.new("Model")
	model.Name = "BigLeafPile"

	local height = BigLeafPileConfig.PileHeight
	local baseRadius = BigLeafPileConfig.PileBaseRadius
	local leafSize = LeafConfig.LeafSize

	for _ = 1, BigLeafPileConfig.LeafCount do
		local y = height * (math.random() ^ 2.4)
		local radiusAtY = baseRadius * math.sqrt(math.max(0, 1 - (y / height) ^ 2))
		-- sqrt(random()) samples uniformly by AREA within the disc at this height, not just by
		-- radius, so leaves don't over-cluster toward the center of each height slice.
		local r = radiusAtY * math.sqrt(math.random())
		local angle = math.random() * math.pi * 2
		local leafX = x + math.cos(angle) * r
		local leafZ = z + math.sin(angle) * r
		local leafY = groundTop + y

		local edgeFraction = radiusAtY > 0.05 and math.clamp(r / radiusAtY, 0, 1) or 0
		local jitterMax = math.rad(15 + edgeFraction * 45)
		local pitchJitter = (math.random() - 0.5) * 2 * jitterMax
		local rollJitter = (math.random() - 0.5) * 2 * jitterMax
		local yaw = math.random() * math.pi * 2

		local leaf = Instance.new("Part")
		leaf.Name = "Leaf"
		leaf.Size = leafSize
		leaf.Color = pickColor()
		leaf.Material = Enum.Material.Grass
		leaf.Anchored = true
		leaf.CanCollide = false
		leaf.CanQuery = false
		leaf.CastShadow = false
		leaf.TopSurface = Enum.SurfaceType.Smooth
		leaf.BottomSurface = Enum.SurfaceType.Smooth
		leaf.CFrame = CFrame.new(leafX, leafY, leafZ)
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(pitchJitter, 0, rollJitter)
		leaf.Parent = model
	end

	-- A thinning halo of loose leaves scattered on the ground just outside the mound's own base
	-- (flat, yaw-only rotation -- the exact same convention LeafSpawner's own ordinary ground-leaf
	-- clusters already use, see its spawnGroundCluster) so the pile doesn't have an unnaturally
	-- clean edge where it meets the grass. Skips any spot inside an AvoidRegion/the CleanupZone,
	-- same guard the pile's own placement already respects.
	for _ = 1, BigLeafPileConfig.GroundScatterCount do
		local angle = math.random() * math.pi * 2
		local extra = BigLeafPileConfig.GroundScatterExtraRadius * (math.random() ^ 1.6)
		local r = baseRadius + extra
		local leafX = x + math.cos(angle) * r
		local leafZ = z + math.sin(angle) * r

		if not isInAvoidRegion(leafX, leafZ) and not isInCleanupZone(leafX, leafZ) then
			local yaw = math.random() * math.pi * 2
			local leaf = Instance.new("Part")
			leaf.Name = "ScatterLeaf"
			leaf.Size = leafSize
			leaf.Color = pickColor()
			leaf.Material = Enum.Material.Grass
			leaf.Anchored = true
			leaf.CanCollide = false
			leaf.CanQuery = false
			leaf.CastShadow = false
			leaf.TopSurface = Enum.SurfaceType.Smooth
			leaf.BottomSurface = Enum.SurfaceType.Smooth
			leaf.CFrame = CFrame.new(leafX, groundTop + leafSize.Y / 2, leafZ) * CFrame.Angles(0, yaw, 0)
			leaf.Parent = model
		end
	end

	-- Small invisible anchor at the pile's true center/apex -- not one of the randomly-scattered
	-- leaves, so the health bar always hovers at a consistent spot regardless of which leaf happened
	-- to land highest (same "dedicated anchor part" pattern LeafSpawner's own consumeVFXPart uses).
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.new(0.2, 0.2, 0.2)
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CastShadow = false
	core.Position = Vector3.new(x, groundTop + height, z)
	core.Parent = model
	model.PrimaryPart = core

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Adornee = core
	billboard.Size = UDim2.fromOffset(BigLeafPileConfig.BarWidth, BigLeafPileConfig.BarHeight)
	billboard.StudsOffset = Vector3.new(0, 1.1, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = BigLeafPileConfig.BarMaxDistance
	billboard.Enabled = false
	billboard.Parent = core

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 1, 0)
	track.BackgroundColor3 = BigLeafPileConfig.TrackColor
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = billboard

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = BigLeafPileConfig.TrackStroke
	trackStroke.Transparency = 0.6
	trackStroke.Thickness = 1
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = BigLeafPileConfig.FillColor
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	model.Parent = pilesFolder

	return model, billboard, fill
end

-- Built once (see BigLeafPileSystem.Start) -- a bright gold/leaf-colored outward sparkle burst plus
-- a quick white flash underneath, same two-layer "sparkles + flash" shape LeafSpawner's own
-- playConsumeVFX already uses for an ordinary delivery, just bigger/wider (a full 180-degree burst,
-- not a directional spray) since a pile kill is a much bigger moment than one leaf landing.
local function createBurstVFX()
	burstVFXPart = Instance.new("Part")
	burstVFXPart.Name = "BigLeafPileBurstVFX"
	burstVFXPart.Anchored = true
	burstVFXPart.CanCollide = false
	burstVFXPart.CanQuery = false
	burstVFXPart.CastShadow = false
	burstVFXPart.Transparency = 1
	burstVFXPart.Size = Vector3.new(0.2, 0.2, 0.2)
	burstVFXPart.Parent = pilesFolder

	burstEmitter = Instance.new("ParticleEmitter")
	burstEmitter.Name = "LeafBurst"
	burstEmitter.Enabled = false
	burstEmitter.Rate = 0
	burstEmitter.Lifetime = NumberRange.new(0.35, 0.6)
	burstEmitter.Speed = NumberRange.new(14, 24)
	burstEmitter.SpreadAngle = Vector2.new(180, 180)
	burstEmitter.Acceleration = Vector3.new(0, -22, 0)
	burstEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.6, 0.8),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	burstEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.75, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	burstEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 221, 130)),
		ColorSequenceKeypoint.new(1, LeafConfig.Colors[1]),
	})
	burstEmitter.LightEmission = 0.6
	burstEmitter.Parent = burstVFXPart

	burstFlashEmitter = Instance.new("ParticleEmitter")
	burstFlashEmitter.Name = "BurstFlash"
	burstFlashEmitter.Enabled = false
	burstFlashEmitter.Rate = 0
	burstFlashEmitter.Lifetime = NumberRange.new(0.2, 0.2)
	burstFlashEmitter.Speed = NumberRange.new(0, 0)
	burstFlashEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.2),
		NumberSequenceKeypoint.new(1, 4.5),
	})
	burstFlashEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	burstFlashEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 244, 214))
	burstFlashEmitter.LightEmission = 1
	burstFlashEmitter.LightInfluence = 0
	burstFlashEmitter.Parent = burstVFXPart
end

local function playKillBurst(position)
	if not burstVFXPart then
		return
	end
	burstVFXPart.CFrame = CFrame.new(position)
	burstEmitter:Emit(40)
	burstFlashEmitter:Emit(1)
end

-- Every leaf part in a just-killed pile drifts outward/up while fading out, instead of the whole
-- model just vanishing -- one shared Heartbeat connection drives every leaf in this one pile
-- together (not a separate TweenService tween per leaf, which for ~300 parts is real per-Tween
-- Instance overhead for a one-shot effect that only needs a single driving loop). Only touches
-- Position/Transparency, never rotation -- see buildPileModel's own comment on deliberately
-- avoiding computed directional rotation math that can't be visually verified before a real Studio
-- test; a position-only drift has the same "no wrong-axis failure mode" safety.
local function animateAndDestroy(model, corePosition)
	local leafInfos = {}
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "Core" then
			local away = Vector3.new(part.Position.X - corePosition.X, 0, part.Position.Z - corePosition.Z)
			if away.Magnitude < 0.05 then
				away = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
			end
			table.insert(leafInfos, {
				Part = part,
				StartPosition = part.Position,
				AwayDirection = away.Unit,
			})
		end
	end

	local elapsed = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local t = math.clamp(elapsed / KILL_ANIM_DURATION, 0, 1)
		local eased = 1 - (1 - t) * (1 - t) -- ease-out, so the burst is fast at first and settles near the end
		for _, info in ipairs(leafInfos) do
			local rise = KILL_ANIM_RISE_STUDS * eased * (1 - eased * 0.5)
			local offset = info.AwayDirection * (KILL_ANIM_OUTWARD_STUDS * eased) + Vector3.new(0, rise, 0)
			info.Part.Position = info.StartPosition + offset
			info.Part.Transparency = eased
		end
		if t >= 1 then
			connection:Disconnect()
			model:Destroy()
		end
	end)
end

-- Pays every player who landed at least one damaging hit -- still-connected check mirrors
-- RoundSystem's own `participant.Parent == Players` idiom. Position passed to DeliverToZone is the
-- pile's own spot, so LeafSpawner's own small per-delivery sparkle (one per participant) reads as
-- coming from right where it died, layered under this module's own bigger burst.
local function killPile(model, state)
	activePiles[model] = nil
	local position = Vector3.new(state.X, state.GroundY, state.Z)
	for participant in pairs(state.Participants) do
		if participant.Parent == Players then
			LeafSpawner.DeliverToZone(BigLeafPileConfig.BonusLeavesPerParticipant, position, participant)
		end
	end
	state.Billboard.Enabled = false
	playKillBurst(position + Vector3.new(0, BigLeafPileConfig.PileHeight * 0.5, 0))
	animateAndDestroy(model, position)
end

local function applyDamage(model, state, player)
	state.Participants[player] = true
	state.Health = math.max(0, state.Health - BigLeafPileConfig.DamagePerBlowTick)
	if not state.Billboard.Enabled then
		state.Billboard.Enabled = true
	end
	state.Fill.Size = UDim2.new(state.Health / state.MaxHealth, 0, 1, 0)
	if state.Health <= 0 then
		killPile(model, state)
	end
end

-- Called by BlowerTool on the exact same per-tick loop it already calls LeafSpawner.ApplyBlow from
-- -- same cone-test shape (angle + range + a small unconditional close radius), just against each
-- pile's own stored X/Z instead of leaf positions. `blowConfig` is the player's effective config
-- (Wide/Long Nozzle upgrades already folded in), so reach scales with upgrades even though
-- BigLeafPileConfig.DamagePerBlowTick itself never does (see that config's own comment).
function BigLeafPileSystem.ApplyBlow(player, origin, direction, blowConfig)
	if not roundActive or not player then
		return
	end

	local cosHalfAngle = math.cos(math.rad(blowConfig.BlowConeAngleDegrees / 2))
	local range = blowConfig.BlowRange

	for model, state in pairs(activePiles) do
		local toX = state.X - origin.X
		local toZ = state.Z - origin.Z
		local distance = math.sqrt(toX * toX + toZ * toZ)
		if distance <= range then
			local dot = distance > 0.05 and (toX * direction.X + toZ * direction.Z) / distance or 1
			if distance <= blowConfig.BlowCloseRadius or dot >= cosHalfAngle then
				applyDamage(model, state, player)
			end
		end
	end
end

-- Called by RoundSystem right after LeafSpawner/SackSystem's own StartYardRound, once the map is
-- revealed and translated into position -- mapEntry is optional (only its AvoidRegions are read) so
-- this stays usable even if a caller only has the folder.
function BigLeafPileSystem.StartYardRound(map1, mapEntry)
	if not map1 then
		warn("[BigLeafPileSystem] StartYardRound called without a map folder -- RoundSystem should pass one in.")
		return
	end

	spawnArea = map1:WaitForChild("LeafSpawnArea")
	cleanupZone = map1:WaitForChild("CleanupZone")
	local ground = map1:WaitForChild("Ground")
	groundTop = ground.Position.Y + ground.Size.Y / 2
	yardAvoidRegions = (mapEntry and mapEntry.AvoidRegions) or {}

	roundActive = true
	activePiles = {}

	local count = math.random(BigLeafPileConfig.MinCountPerRound, BigLeafPileConfig.MaxCountPerRound)
	for _ = 1, count do
		local x, z = randomPilePosition()
		if x then
			local model, billboard, fill = buildPileModel(x, z)
			activePiles[model] = {
				Health = BigLeafPileConfig.HealthMax,
				MaxHealth = BigLeafPileConfig.HealthMax,
				X = x,
				Z = z,
				GroundY = groundTop,
				Participants = {},
				Billboard = billboard,
				Fill = fill,
			}
		end
	end
end

-- Testing hook for the ":killpile" admin command (Claude has no way to press Play/blow one for
-- real) -- force-kills whichever active pile is closest to the given player's character, crediting
-- them (and only them) with the normal kill reward through the exact same killPile path a real kill
-- uses. Returns false if there's no active round or no pile currently alive to kill.
function BigLeafPileSystem.AdminKillNearest(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not roundActive or not rootPart then
		return false
	end

	local position = rootPart.Position
	local nearestModel, nearestState, nearestDistance
	for model, state in pairs(activePiles) do
		local dx, dz = state.X - position.X, state.Z - position.Z
		local distance = math.sqrt(dx * dx + dz * dz)
		if not nearestDistance or distance < nearestDistance then
			nearestModel, nearestState, nearestDistance = model, state, distance
		end
	end

	if not nearestModel then
		return false
	end

	nearestState.Participants[player] = true
	killPile(nearestModel, nearestState)
	return true
end

-- Called by RoundSystem when a round ends (goal met, timer expired, or nobody actually showed up),
-- before it hides the map again -- destroys every still-alive pile with no reward (matches
-- LeafSpawner.StopYardRound discarding leftover leaves the same way).
function BigLeafPileSystem.StopYardRound()
	roundActive = false
	for model in pairs(activePiles) do
		model:Destroy()
	end
	activePiles = {}
	spawnArea = nil
	cleanupZone = nil
	yardAvoidRegions = {}
end

function BigLeafPileSystem.Start()
	pilesFolder = Instance.new("Folder")
	pilesFolder.Name = "BigLeafPiles"
	pilesFolder.Parent = Workspace

	createBurstVFX()
end

return BigLeafPileSystem
