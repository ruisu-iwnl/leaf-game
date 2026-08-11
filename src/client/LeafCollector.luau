local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LeafCollector = {}

local RAYCAST_DISTANCE = 300
-- Leaves are thin (0.08 studs tall) flat slabs lying on the ground -- a pixel-perfect raycast
-- against one is genuinely hard to land, especially on mobile touch. If the direct hit isn't a
-- leaf, fall back to "closest leaf near wherever the click/tap actually landed" instead of just
-- giving up, so aiming "at that pile" is forgiving rather than needing exact precision.
local COLLECT_TOLERANCE_RADIUS = 2.5

-- Same InputBegan handler covers both PC (MouseButton1) and Mobile (Touch) -- Roblox delivers tap
-- position through input.Position on both, so there's no separate mobile-only code path needed.
-- gameProcessed guards against this also firing when the tap/click actually hit a GUI button (the
-- sack button, settings gear, etc.) instead of the 3D world.
function LeafCollector.Start()
	-- init.client.luau starts every UI module in one sequential list -- an untimed WaitForChild
	-- here (Remotes, or the Leaves folder LeafSpawner creates once its own now-deferred setup
	-- finishes) could block every module after this one. Deferred + timed, same pattern as the
	-- other fixes this session.
	task.spawn(function()
		local player = Players.LocalPlayer
		local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes", 15)
		if not remotes then
			warn("[LeafCollector] ReplicatedStorage.Shared.Remotes not found after 15s -- leaf collection disabled this session.")
			return
		end
		local collectLeafRemote = remotes:WaitForChild("CollectLeaf", 15)
		local leavesFolder = Workspace:WaitForChild("Leaves", 15)
		if not collectLeafRemote or not leavesFolder then
			warn("[LeafCollector] CollectLeaf remote or Workspace.Leaves not found after 15s -- leaf collection disabled this session.")
			return
		end

		local function findNearbyLeaf(position)
			local overlapParams = OverlapParams.new()
			overlapParams.FilterType = Enum.RaycastFilterType.Include
			overlapParams.FilterDescendantsInstances = { leavesFolder }

			local closest, closestDistance
			for _, part in ipairs(Workspace:GetPartBoundsInRadius(position, COLLECT_TOLERANCE_RADIUS, overlapParams)) do
				if part.Name == "Leaf" then
					local distance = (part.Position - position).Magnitude
					if not closestDistance or distance < closestDistance then
						closest, closestDistance = part, distance
					end
				end
			end
			return closest
		end

		local function tryCollectAt(screenPosition)
			local character = player.Character
			-- Hands-free only: skip the raycast entirely while holding the blower, the sack, or
			-- anything else -- the server enforces this too, this just avoids a pointless remote call.
			if character and character:FindFirstChildOfClass("Tool") then
				return
			end

			local camera = Workspace.CurrentCamera
			if not camera then
				return
			end

			local unitRay = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = { player.Character }

			local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * RAYCAST_DISTANCE, raycastParams)
			if not result then
				return
			end

			if result.Instance and result.Instance.Name == "Leaf" then
				collectLeafRemote:FireServer(result.Instance)
				return
			end

			local nearbyLeaf = findNearbyLeaf(result.Position)
			if nearbyLeaf then
				collectLeafRemote:FireServer(nearbyLeaf)
			end
		end

		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				tryCollectAt(Vector2.new(input.Position.X, input.Position.Y))
			end
		end)
	end)
end

return LeafCollector
