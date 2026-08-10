local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RakeConfig = require(ReplicatedStorage.Shared.RakeConfig)

-- Visual-only cone showing the Rake's actual reach (cone angle + range) so its trajectory is
-- visible before committing to a click -- same neon-ray approach as BlowerConeIndicator, but
-- visible for the tool's whole life while equipped (not gated on an "active" attribute): a Rake
-- use is a single click, not something held down, so there's no separate "in use" window to gate
-- on -- the player needs to see the cone in order to aim the click in the first place.
local RakeConeIndicator = {}

local TOOL_NAME = "LeafRake"
local HALF_ANGLE_RAD = math.rad(RakeConfig.RakeConeAngleDegrees / 2)

-- Rotates around the vertical axis only (X/Z), preserving whatever Y component the vector already
-- has.
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
	-- Warm amber/gold -- distinct from the Blower's cyan cone, and matches this tool's "gathering
	-- leaves" feel better than a cold color would.
	part.Color = Color3.fromRGB(230, 170, 70)
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
-- network round-trip, same reasoning as BlowerConeIndicator.
local function watchTool(tool)
	local leftRay, rightRay, farRay
	local heartbeatConnection

	local function showIndicator()
		if leftRay then
			return
		end
		leftRay = newIndicatorPart("RakeConeLeft")
		rightRay = newIndicatorPart("RakeConeRight")
		farRay = newIndicatorPart("RakeConeFar")
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
		-- Origin is the PLAYER's own position (not a tool part) -- matches RakeTool's
		-- getAimOriginDirection, since that's also what leaves actually get pulled toward.
		local origin = rootPart.Position

		local leftEdge = origin + rotateY(direction, HALF_ANGLE_RAD) * RakeConfig.RakeRange
		local rightEdge = origin + rotateY(direction, -HALF_ANGLE_RAD) * RakeConfig.RakeRange
		pointRay(leftRay, origin, leftEdge)
		pointRay(rightRay, origin, rightEdge)
		pointRay(farRay, leftEdge, rightEdge)
	end

	local function refresh()
		if tool.Parent and tool.Parent:FindFirstChildOfClass("Humanoid") then
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

	tool.AncestryChanged:Connect(refresh)
	refresh()
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

function RakeConeIndicator.Start()
	local player = Players.LocalPlayer

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

return RakeConeIndicator
