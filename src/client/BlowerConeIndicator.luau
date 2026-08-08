local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BlowerConfig = require(ReplicatedStorage.Shared.BlowerConfig)

local BlowerConeIndicator = {}

local TOOL_NAME = "LeafBlower"
local HALF_ANGLE_RAD = math.rad(BlowerConfig.BlowConeAngleDegrees / 2)
local PITCH_DOWN_RAD = math.rad(BlowerConfig.BlowPitchDownDegrees)

-- Rotates around the vertical axis only (X/Z), preserving whatever Y component the vector already
-- has -- so a downward-tilted direction stays tilted the same amount after spreading left/right.
local function rotateY(vector, angleRad)
	local cos = math.cos(angleRad)
	local sin = math.sin(angleRad)
	return Vector3.new(vector.X * cos - vector.Z * sin, vector.Y, vector.X * sin + vector.Z * cos)
end

local function newIndicatorPart(name)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(80, 220, 255)
	part.Transparency = 0.3
	part.Size = Vector3.new(0.2, 0.2, 1)
	return part
end

-- Points a thin part from fromPos to toPos, using CFrame.new(pos, lookAt) so there's no manual
-- rotation-axis math to get wrong.
local function pointRay(part, fromPos, toPos)
	local distance = (toPos - fromPos).Magnitude
	if distance < 0.05 then
		part.Size = Vector3.new(0.2, 0.2, 0.05)
		part.CFrame = CFrame.new(fromPos)
		return
	end
	part.Size = Vector3.new(0.2, 0.2, distance)
	part.CFrame = CFrame.new(fromPos:Lerp(toPos, 0.5), toPos)
end

-- Built and updated entirely client-side (parts created by a LocalScript only render for this
-- client, never replicate), driven by this client's OWN character CFrame every frame -- zero
-- network round-trip, so it tracks the player's aim instantly instead of lagging a tick behind
-- the server's view of their rotation.
local function watchTool(tool)
	local nozzle = tool:WaitForChild("Nozzle")
	local leftRay, rightRay, farRay
	local heartbeatConnection

	local function showIndicator()
		if leftRay then
			return
		end
		leftRay = newIndicatorPart("BlowConeLeft")
		rightRay = newIndicatorPart("BlowConeRight")
		farRay = newIndicatorPart("BlowConeFar")
		leftRay.Parent = Workspace
		rightRay.Parent = Workspace
		farRay.Parent = Workspace
	end

	local function hideIndicator()
		if leftRay then
			leftRay:Destroy()
			rightRay:Destroy()
			farRay:Destroy()
			leftRay, rightRay, farRay = nil, nil, nil
		end
	end

	local function update()
		local character = tool.Parent
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return
		end
		local lookVector = rootPart.CFrame.LookVector
		local direction = Vector3.new(lookVector.X, 0, lookVector.Z)
		if direction.Magnitude <= 0.01 then
			return
		end
		direction = direction.Unit
		-- Tilt the forward direction down by BlowPitchDownDegrees before spreading it left/right,
		-- so the cone visibly aims at the ground instead of staying level with the nozzle.
		local tiltedDirection = direction * math.cos(PITCH_DOWN_RAD) + Vector3.new(0, -1, 0) * math.sin(PITCH_DOWN_RAD)
		local origin = nozzle.Position

		local leftEdge = origin + rotateY(tiltedDirection, HALF_ANGLE_RAD) * BlowerConfig.BlowRange
		local rightEdge = origin + rotateY(tiltedDirection, -HALF_ANGLE_RAD) * BlowerConfig.BlowRange
		pointRay(leftRay, origin, leftEdge)
		pointRay(rightRay, origin, rightEdge)
		pointRay(farRay, leftEdge, rightEdge)
	end

	-- Blowing state is server-authoritative (set via Tool:SetAttribute), replicated automatically.
	local function refresh()
		if tool:GetAttribute("Blowing") then
			showIndicator()
			if not heartbeatConnection then
				heartbeatConnection = RunService.Heartbeat:Connect(update)
			end
		else
			if heartbeatConnection then
				heartbeatConnection:Disconnect()
				heartbeatConnection = nil
			end
			hideIndicator()
		end
	end

	tool:GetAttributeChangedSignal("Blowing"):Connect(refresh)
	refresh()

	tool.AncestryChanged:Connect(function()
		if not tool.Parent then
			if heartbeatConnection then
				heartbeatConnection:Disconnect()
				heartbeatConnection = nil
			end
			hideIndicator()
		end
	end)
end

local function onCharacterAdded(character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			watchTool(child)
		end
	end)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			watchTool(child)
		end
	end
end

function BlowerConeIndicator.Start()
	local player = Players.LocalPlayer

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

return BlowerConeIndicator
