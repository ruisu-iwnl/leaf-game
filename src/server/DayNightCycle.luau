local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local DayNightCycle = {}

local START_TIME = 8
local END_TIME = 17
local CYCLE_DURATION_SECONDS = 600 -- one full 8AM -> 5PM sweep, then jumps back to 8AM and repeats

function DayNightCycle.Start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed = (elapsed + dt) % CYCLE_DURATION_SECONDS
		local progress = elapsed / CYCLE_DURATION_SECONDS
		Lighting.ClockTime = START_TIME + (END_TIME - START_TIME) * progress
	end)
end

return DayNightCycle
