local Lighting = game:GetService("Lighting")

-- Purely a local rendering preference: nothing here is replicated or written back to the server,
-- so each player can toggle their own Fast Mode independently.
local PerformanceMode = {}

local enabled = false
local resolved = false
local bloom
local sunRays
local atmosphere

-- Resolved lazily (on first actual toggle, not at module load) with WaitForChild rather than
-- FindFirstChild, since FindFirstChild could lose a race against these still replicating in and
-- silently cache nil forever. Cached afterward (not re-looked-up) so Atmosphere survives being
-- unparented while Fast Mode is on -- FindFirstChild would fail to find it again to restore it.
local function resolveEffects()
	if resolved then
		return
	end
	resolved = true
	bloom = Lighting:WaitForChild("Bloom", 5)
	sunRays = Lighting:WaitForChild("SunRays", 5)
	atmosphere = Lighting:WaitForChild("Atmosphere", 5)
end

function PerformanceMode.SetEnabled(isEnabled)
	resolveEffects()
	enabled = isEnabled

	-- Note: Lighting.Technology can't be set by developer scripts at all (Roblox restricts it to
	-- internal engine scripts), so GlobalShadows + disabling the post-effects is what Fast Mode has.
	Lighting.GlobalShadows = not isEnabled

	if bloom then
		bloom.Enabled = not isEnabled
	end
	if sunRays then
		sunRays.Enabled = not isEnabled
	end
	if atmosphere then
		atmosphere.Parent = isEnabled and nil or Lighting
	end
end

function PerformanceMode.IsEnabled()
	return enabled
end

return PerformanceMode
