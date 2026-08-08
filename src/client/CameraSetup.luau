local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlayerConfig = require(ReplicatedStorage.Shared.PlayerConfig)

local CameraSetup = {}

-- FieldOfView lives on the Camera instance, which is local to this client (not something the
-- server can set for us), and Roblox can swap in a new Camera on respawn, so this re-applies
-- whenever CurrentCamera changes rather than only once.
local function applyFieldOfView()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.FieldOfView = PlayerConfig.FieldOfView
	end
end

-- The default camera scripts read CameraMin/MaxZoomDistance locally on this client; setting it
-- only from the server can lose a race against those scripts initializing, so set it here too.
local function applyZoomRange()
	local player = Players.LocalPlayer
	player.CameraMinZoomDistance = PlayerConfig.CameraMinZoomDistance
	player.CameraMaxZoomDistance = PlayerConfig.CameraMaxZoomDistance
end

function CameraSetup.Start()
	applyZoomRange()
	applyFieldOfView()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(applyFieldOfView)
end

return CameraSetup
