local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")
local Workspace = game:GetService("Workspace")

local BlowerConfig = require(ReplicatedStorage.Shared.BlowerConfig)
local LeafSpawner = require(script.Parent.LeafSpawner)

local BlowerTool = {}

local TOOL_NAME = "LeafBlower"
local BACKPACK_NAME = "BlowerBackpack"

local function weldTo(part0, part1)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part1
end

local function newPart(name, size, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	-- DiamondPlate gives a raised grid-bump texture -- the closest built-in Roblox material to a
	-- grippy textured plastic surface, without needing a custom texture asset.
	part.Material = material or Enum.Material.DiamondPlate
	part.CanCollide = false
	part.CastShadow = false
	part.Massless = true
	return part
end

-- Builds the one-and-only tool template. Roblox clones this into every player's Backpack
-- automatically (that's what StarterPack does), so this only ever needs to be built once.
local function buildTool()
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local handle = newPart("Handle", BlowerConfig.BodySize, BlowerConfig.BodyColor)
	handle.Parent = tool

	local accent = newPart("Accent", BlowerConfig.AccentSize, BlowerConfig.GripColor)
	accent.CFrame = handle.CFrame * CFrame.new(0, 0, 0.4)
	accent.Parent = tool
	weldTo(handle, accent)

	local grip = newPart("Grip", BlowerConfig.GripSize, BlowerConfig.GripColor)
	grip.CFrame = handle.CFrame * CFrame.new(0, -0.7, 0.4)
	grip.Parent = tool
	weldTo(handle, grip)

	local gripHoseAttachment = Instance.new("Attachment")
	gripHoseAttachment.Name = "HoseAttachment"
	gripHoseAttachment.Position = Vector3.new(0, -BlowerConfig.GripSize.Y / 2, 0)
	gripHoseAttachment.Parent = grip

	local nozzle = newPart("Nozzle", BlowerConfig.NozzleSize, BlowerConfig.NozzleColor)
	nozzle.CFrame = handle.CFrame * CFrame.new(0, 0, -BlowerConfig.BodySize.Z / 2 - BlowerConfig.NozzleSize.Z / 2)
	nozzle.Parent = tool
	weldTo(handle, nozzle)

	-- Rotated -90 degrees on X so the attachment's emission axis (local +Y) points along the
	-- nozzle's local -Z (forward, matching this project's "front = -Z" convention everywhere else).
	-- The extra -BlowPitchDownDegrees tilts that forward direction down toward the ground.
	local emitAttachment = Instance.new("Attachment")
	emitAttachment.Name = "WindEmitAttachment"
	emitAttachment.CFrame = CFrame.new(0, 0, -BlowerConfig.NozzleSize.Z / 2)
		* CFrame.Angles(math.rad(-90 - BlowerConfig.BlowPitchDownDegrees), 0, 0)
	emitAttachment.Parent = nozzle

	local windEmitter = Instance.new("ParticleEmitter")
	windEmitter.Name = "WindEmitter"
	windEmitter.Enabled = false
	windEmitter.Rate = BlowerConfig.ParticleRate
	windEmitter.Lifetime = NumberRange.new(BlowerConfig.ParticleLifetimeMin, BlowerConfig.ParticleLifetimeMax)
	windEmitter.Speed = NumberRange.new(BlowerConfig.ParticleSpeedMin, BlowerConfig.ParticleSpeedMax)
	windEmitter.SpreadAngle = Vector2.new(BlowerConfig.ConeAngleDegrees, BlowerConfig.ConeAngleDegrees)
	windEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 1.1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	windEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	windEmitter.Color = ColorSequence.new(Color3.fromRGB(240, 240, 235))
	windEmitter.LightEmission = 0.1
	windEmitter.Parent = emitAttachment

	return tool
end

-- Worn on the back: a main tank, a rounded motor unit on top, a dark base trim, vents, an
-- indicator light, a pull-start handle, and a small exhaust nub -- same color scheme as the
-- handheld part. Always present once the character spawns (not tied to whether the tool is
-- currently equipped). Uses WaitForChild (not FindFirstChild) for the torso since R15 body parts
-- can still be streaming in when CharacterAdded first fires -- an immediate lookup losing that
-- race was why the backpack sometimes silently never got created.
local function attachBackpack(character)
	if character:FindFirstChild(BACKPACK_NAME) then
		return
	end

	-- R6 rigs build "Torso" immediately; R15 (the default) can still be streaming "UpperTorso" in,
	-- so check the instant one first and only wait on the one that's actually likely to be missing.
	local torso = character:FindFirstChild("Torso") or character:WaitForChild("UpperTorso", 5)
	if not torso then
		return
	end

	local tankSize = BlowerConfig.BackpackTankSize
	local backOffset = tankSize.Z / 2 + 0.15

	local pack = newPart(BACKPACK_NAME, tankSize, BlowerConfig.BodyColor)
	pack.CFrame = torso.CFrame * CFrame.new(0, 0.1, backOffset)
	pack.Parent = character
	weldTo(torso, pack)

	local trim = newPart("BackpackTrim", BlowerConfig.BackpackTrimSize, BlowerConfig.GripColor)
	trim.CFrame = torso.CFrame * CFrame.new(0, 0.1 - tankSize.Y / 2, backOffset)
	trim.Parent = character
	weldTo(torso, trim)

	local motorSize = BlowerConfig.BackpackMotorSize
	local motor = newPart("BackpackMotor", motorSize, BlowerConfig.GripColor)
	motor.Shape = Enum.PartType.Ball
	motor.CFrame = torso.CFrame * CFrame.new(0, 0.1 + tankSize.Y / 2 + motorSize.Y / 2 - 0.35, backOffset)
	motor.Parent = character
	weldTo(torso, motor)

	local pullHandleSize = BlowerConfig.PullHandleSize
	local pullHandle = newPart("BackpackPullHandle", pullHandleSize, BlowerConfig.NozzleColor)
	pullHandle.Shape = Enum.PartType.Ball
	pullHandle.CFrame = torso.CFrame * CFrame.new(0.3, 0.1 + tankSize.Y / 2 + 0.05, backOffset - motorSize.Z / 2)
	pullHandle.Parent = character
	weldTo(torso, pullHandle)

	local exhaustSize = BlowerConfig.BackpackExhaustSize
	local exhaust = newPart("BackpackExhaust", exhaustSize, BlowerConfig.NozzleColor)
	exhaust.CFrame = torso.CFrame * CFrame.new(0.5, 0.1 + tankSize.Y / 2 - 0.2, backOffset - exhaustSize.Z / 2)
	exhaust.Parent = character
	weldTo(torso, exhaust)

	local ventSize = BlowerConfig.BackpackVentSize
	local leftVent = newPart("BackpackVentLeft", ventSize, BlowerConfig.GripColor)
	leftVent.CFrame = torso.CFrame * CFrame.new(tankSize.X / 2 - 0.02, 0.1, backOffset - tankSize.Z / 2 + 0.05)
	leftVent.Parent = character
	weldTo(torso, leftVent)

	local rightVent = newPart("BackpackVentRight", ventSize, BlowerConfig.GripColor)
	rightVent.CFrame = torso.CFrame * CFrame.new(-(tankSize.X / 2 - 0.02), 0.1, backOffset - tankSize.Z / 2 + 0.05)
	rightVent.Parent = character
	weldTo(torso, rightVent)

	-- Outer (away-from-character) face of the tank, near the top-right corner, proud of the
	-- surface by a hair to avoid z-fighting. Was previously placed on the INNER face (facing the
	-- character's back), which made it completely hidden -- that was the bug.
	local light = newPart("BackpackLight", BlowerConfig.BackpackLightSize, BlowerConfig.LightColorOff, Enum.Material.Neon)
	light.CFrame = torso.CFrame * CFrame.new(tankSize.X / 2 - 0.15, 0.1 + tankSize.Y / 2 - 0.2, backOffset + tankSize.Z / 2 + 0.02)
	light.Parent = character
	weldTo(torso, light)

	-- Where the hose visually connects, on the outer (visible) top face of the tank. Position here
	-- is local to `pack` itself (not torso) since this Attachment is parented to pack directly --
	-- unlike the CFrame-based parts above, backOffset must NOT be added again here.
	local packHoseAttachment = Instance.new("Attachment")
	packHoseAttachment.Name = "HoseAttachment"
	packHoseAttachment.Position = Vector3.new(0, tankSize.Y / 2 - 0.15, tankSize.Z / 2)
	packHoseAttachment.Parent = pack

	local leftStrap = newPart("BackpackStrapLeft", BlowerConfig.StrapSize, BlowerConfig.GripColor, Enum.Material.Fabric)
	leftStrap.CFrame = torso.CFrame * CFrame.new(0.5, 0.3, -0.1)
	leftStrap.Parent = character
	weldTo(torso, leftStrap)

	local rightStrap = newPart("BackpackStrapRight", BlowerConfig.StrapSize, BlowerConfig.GripColor, Enum.Material.Fabric)
	rightStrap.CFrame = torso.CFrame * CFrame.new(-0.5, 0.3, -0.1)
	rightStrap.Parent = character
	weldTo(torso, rightStrap)
end

local function isEquippedByPlayer(tool)
	local character = tool.Parent
	return character ~= nil and character:FindFirstChildOfClass("Humanoid") ~= nil
end

-- Direction comes from the character's HumanoidRootPart (always reliably horizontal) rather than
-- the tool's own CFrame, since Roblox's default tool grip orientation isn't something this
-- project can predict/verify. Returns nil, nil if there's no valid aim right now.
local function getAimOriginDirection(tool, nozzle)
	local character = tool.Parent
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil, nil
	end
	local lookVector = rootPart.CFrame.LookVector
	local direction = Vector3.new(lookVector.X, 0, lookVector.Z)
	if direction.Magnitude <= 0.01 then
		return nil, nil
	end
	return nozzle.Position, direction.Unit
end

-- BackpackLight is parented directly to the character (a sibling of the "BlowerBackpack" tank
-- part, like all the other backpack decoration pieces), not nested inside it -- looking for it
-- inside `pack` was the actual bug (pack was found fine; the light lookup just had the wrong parent).
local function setIndicatorLight(character, isOn)
	local light = character and character:FindFirstChild("BackpackLight")
	if light then
		light.Color = isOn and BlowerConfig.LightColorOn or BlowerConfig.LightColorOff
	elseif character then
		-- Might still be mid-attachBackpack; wait briefly rather than silently giving up, so a
		-- fast click right after spawn doesn't leave the light stuck.
		task.spawn(function()
			local waitedLight = character:WaitForChild("BackpackLight", 3)
			if waitedLight then
				waitedLight.Color = isOn and BlowerConfig.LightColorOn or BlowerConfig.LightColorOff
			end
		end)
	end
end

-- Watches one specific tool INSTANCE for the rest of its life. A Backpack is not a Workspace
-- descendant, so this only ever gets called once the tool is actually equipped (parented into a
-- Character, which is in Workspace) -- see the DescendantAdded hookup below. From then on,
-- AncestryChanged reliably fires on every future equip/unequip of this same instance, sidestepping
-- the Backpack/PlayerAdded/ChildAdded chain that turned out to not be firing reliably.
--
-- Blowing is now a click-to-toggle (not automatic on equip, and not hold-to-activate): click once
-- to start, click again to stop. The backpack's status light also reflects this (red/green).
-- The cone indicator itself moved to a client-side script (BlowerConeIndicator) so it updates with
-- zero network lag -- driving it here on the server meant its position was always a bit behind the
-- player's actual input, since the server only sees their aim after it replicates.
local function watchTool(tool)
	local nozzle = tool:WaitForChild("Nozzle")
	local windEmitAttachment = nozzle:WaitForChild("WindEmitAttachment")
	local windEmitter = windEmitAttachment:WaitForChild("WindEmitter")
	local grip = tool:WaitForChild("Grip")
	local gripHoseAttachment = grip:WaitForChild("HoseAttachment")

	local blowing = false
	local toggledOn = false
	local hose
	-- Captured while still equipped: AncestryChanged fires AFTER tool.Parent has already changed,
	-- so reading tool.Parent inside that handler would give the Backpack, not the Character, and
	-- the light could never be reset back to red on unequip.
	local equippedCharacter = tool.Parent

	-- Present whenever equipped, independent of the blowing toggle (a real hose stays attached
	-- either way). Retries briefly if the backpack accessory hasn't finished attaching yet.
	local function createHose()
		if hose then
			return
		end
		local character = tool.Parent
		local pack = character and character:FindFirstChild(BACKPACK_NAME)
		local packHoseAttachment = pack and pack:FindFirstChild("HoseAttachment")
		if not packHoseAttachment then
			if character then
				task.delay(0.2, function()
					if not hose and isEquippedByPlayer(tool) then
						createHose()
					end
				end)
			end
			return
		end

		local newHose = Instance.new("Beam")
		newHose.Name = "Hose"
		newHose.Attachment0 = gripHoseAttachment
		newHose.Attachment1 = packHoseAttachment
		newHose.Width0 = BlowerConfig.HoseWidth
		newHose.Width1 = BlowerConfig.HoseWidth
		newHose.Color = ColorSequence.new(BlowerConfig.HoseColor)
		-- Same sign on both ends -- opposite signs make an S-curve, not a coil.
		newHose.CurveSize0 = BlowerConfig.HoseCurveSize
		newHose.CurveSize1 = BlowerConfig.HoseCurveSize
		newHose.FaceCamera = true
		newHose.Parent = gripHoseAttachment
		hose = newHose
	end

	local function destroyHose()
		if hose then
			hose:Destroy()
			hose = nil
		end
	end

	local function runBlowLoop()
		while blowing do
			local origin, direction = getAimOriginDirection(tool, nozzle)
			if origin then
				LeafSpawner.ApplyBlow(origin, direction, BlowerConfig)
			end
			task.wait(BlowerConfig.BlowInterval)
		end
	end

	local function startBlowing()
		if blowing then
			return
		end
		windEmitter.Enabled = true
		blowing = true
		tool:SetAttribute("Blowing", true)
		setIndicatorLight(equippedCharacter, true)
		task.spawn(runBlowLoop)
	end

	local function stopBlowing()
		if not blowing then
			return
		end
		windEmitter.Enabled = false
		blowing = false
		tool:SetAttribute("Blowing", false)
		setIndicatorLight(equippedCharacter, false)
	end

	tool.Activated:Connect(function()
		toggledOn = not toggledOn
		if toggledOn then
			startBlowing()
		else
			stopBlowing()
		end
	end)

	tool.AncestryChanged:Connect(function()
		if isEquippedByPlayer(tool) then
			equippedCharacter = tool.Parent
			createHose()
		else
			toggledOn = false
			stopBlowing()
			destroyHose()
		end
	end)

	createHose()
end

local watchedTools = setmetatable({}, { __mode = "k" })

local function onWorkspaceDescendantAdded(descendant)
	if descendant:IsA("Tool") and descendant.Name == TOOL_NAME and not watchedTools[descendant] then
		watchedTools[descendant] = true
		watchTool(descendant)
	end
end

local function onCharacterAdded(character)
	attachBackpack(character)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

function BlowerTool.Start()
	if not StarterPack:FindFirstChild(TOOL_NAME) then
		buildTool().Parent = StarterPack
	end

	Workspace.DescendantAdded:Connect(onWorkspaceDescendantAdded)
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		onWorkspaceDescendantAdded(descendant)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return BlowerTool
