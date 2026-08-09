local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- Animates the fill of the in-world billboard progress bar built by the server
-- (CleanupZoneUI.luau). Kept client-side so the smoothing/pulsing is zero-lag and doesn't depend
-- on server tick rate -- the server only ever sets the "CleanupZoneProgress" (0..1) attribute.
local CleanupProgressBar = {}

local PULSE_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PROGRESS_SMOOTHING_PER_SECOND = 6

function CleanupProgressBar.Start()
	local cleanupZone = Workspace:WaitForChild("CleanupZone")
	local billboard = cleanupZone:WaitForChild("ProgressBillboard")
	local track = billboard:WaitForChild("Container"):WaitForChild("Track")
	local fill = track:WaitForChild("Fill")
	local percentLabel = track:WaitForChild("PercentLabel")

	local baseFillColor = fill.BackgroundColor3
	local pulseColor = Color3.fromRGB(255, 255, 255)

	local displayed = Workspace:GetAttribute("CleanupZoneProgress") or 0
	local target = displayed
	fill.Size = UDim2.new(displayed, 0, 1, 0)
	percentLabel.Text = string.format("%d%%", math.floor(displayed * 100 + 0.5))

	local function pulse()
		local up = TweenService:Create(fill, PULSE_TWEEN_INFO, { BackgroundColor3 = pulseColor })
		local down = TweenService:Create(fill, PULSE_TWEEN_INFO, { BackgroundColor3 = baseFillColor })
		up.Completed:Connect(function()
			down:Play()
		end)
		up:Play()
	end

	Workspace:GetAttributeChangedSignal("CleanupZoneProgress"):Connect(function()
		local newValue = Workspace:GetAttribute("CleanupZoneProgress") or 0
		-- A full-to-empty jump (lap completed and reset) reads as a snap, not a rewind glide.
		if newValue < target - 0.5 then
			displayed = newValue
		end
		target = newValue
		if newValue >= 0.999 then
			pulse()
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		if displayed == target then
			return
		end
		local diff = target - displayed
		if math.abs(diff) < 0.004 then
			displayed = target
		else
			displayed += diff * math.min(dt * PROGRESS_SMOOTHING_PER_SECOND, 1)
		end
		fill.Size = UDim2.new(displayed, 0, 1, 0)
		percentLabel.Text = string.format("%d%%", math.floor(displayed * 100 + 0.5))
	end)
end

return CleanupProgressBar
