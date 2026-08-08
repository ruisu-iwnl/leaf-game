local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerConfig = require(ReplicatedStorage.Shared.PlayerConfig)

local PlayerSetup = {}

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.WalkSpeed = PlayerConfig.WalkSpeed
	humanoid.CameraOffset = PlayerConfig.CameraOffset

	if PlayerConfig.DisableJump then
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end
end

local function onPlayerAdded(player)
	-- Player-level camera zoom range persists across respawns, so this only needs to be set once.
	player.CameraMinZoomDistance = PlayerConfig.CameraMinZoomDistance
	player.CameraMaxZoomDistance = PlayerConfig.CameraMaxZoomDistance

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

function PlayerSetup.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return PlayerSetup
