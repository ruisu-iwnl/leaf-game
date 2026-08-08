return {
	-- Slower, relaxed pace to match a leaf-cleaning game rather than default Roblox brisk-walk speed.
	WalkSpeed = 12,
	DisableJump = false,

	-- Locked third-person range: can't zoom into first person or pull far out.
	CameraMinZoomDistance = 6,
	CameraMaxZoomDistance = 9,
	-- Shifts the camera off-center for a modern over-the-shoulder look instead of dead-center behind the head.
	CameraOffset = Vector3.new(1.5, 0, 0),
	FieldOfView = 70,
}
