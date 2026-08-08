return {
	Directions = { "NORTH", "SOUTH", "EAST", "WEST" },
	HoldDurationMin = 45,
	HoldDurationMax = 90,

	-- World-space unit vectors per cardinal direction (North = -Z, matching the "Front" convention
	-- used for building signs elsewhere in this project).
	Vectors = {
		NORTH = Vector3.new(0, 0, -1),
		SOUTH = Vector3.new(0, 0, 1),
		EAST = Vector3.new(1, 0, 0),
		WEST = Vector3.new(-1, 0, 0),
	},
}
