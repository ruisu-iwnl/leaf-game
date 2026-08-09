local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LeafMotion = require(ReplicatedStorage.Shared.LeafMotion)

-- Renders leaf fall/glide motion entirely client-side, from motion PARAMETERS the server
-- replicates once per motion (see LeafSpawner.luau) instead of streaming CFrame every server
-- tick. This is what actually fixes leaves looking laggy/choppy at higher ping: the server
-- deciding WHEN/WHERE a leaf moves only has to reach this client once per motion; the smoothness
-- of the motion itself comes from this script's own local Heartbeat, timed against
-- Workspace:GetServerTimeNow() (a clock kept in sync with the server), so it's not dependent on
-- how often new data happens to arrive over the network. A client joining or catching up mid-flight
-- computes the CORRECT current pose immediately from elapsed time, rather than replaying from the
-- start -- there's no "catch-up" animation glitch.
local LeafRenderer = {}

-- Only leaves currently mid-motion are tracked here -- most leaves spend most of their time at
-- rest, and those cost nothing per frame (this project's original design intent, preserved).
local function readFallParams(leaf)
	return {
		spawnBaseX = leaf:GetAttribute("FallSpawnX"),
		spawnY = leaf:GetAttribute("FallSpawnY"),
		spawnBaseZ = leaf:GetAttribute("FallSpawnZ"),
		baseX = leaf:GetAttribute("FallTargetX"),
		baseZ = leaf:GetAttribute("FallTargetZ"),
		restY = leaf:GetAttribute("FallRestY"),
		swayAmplitude = leaf:GetAttribute("FallSwayAmplitude"),
		swayFreqX = leaf:GetAttribute("FallSwayFreqX"),
		swayFreqZ = leaf:GetAttribute("FallSwayFreqZ"),
		phaseX = leaf:GetAttribute("FallPhaseX"),
		phaseZ = leaf:GetAttribute("FallPhaseZ"),
		flutterFreqX = leaf:GetAttribute("FallFlutterFreqX"),
		flutterFreqZ = leaf:GetAttribute("FallFlutterFreqZ"),
		flutterPhaseX = leaf:GetAttribute("FallFlutterPhaseX"),
		flutterPhaseZ = leaf:GetAttribute("FallFlutterPhaseZ"),
		initialYaw = leaf:GetAttribute("FallInitialYaw"),
		spinSpeed = leaf:GetAttribute("FallSpinSpeed"),
		tumbleAmplitude = leaf:GetAttribute("FallTumbleAmplitude"),
		tumbleFreq = leaf:GetAttribute("FallTumbleFreq"),
		duration = leaf:GetAttribute("MotionDuration"),
	}
end

local function readGlideParams(leaf)
	return {
		startX = leaf:GetAttribute("GlideStartX"),
		startZ = leaf:GetAttribute("GlideStartZ"),
		restY = leaf:GetAttribute("GlideRestY"),
		targetX = leaf:GetAttribute("GlideTargetX"),
		targetZ = leaf:GetAttribute("GlideTargetZ"),
		startYaw = leaf:GetAttribute("GlideStartYaw"),
		targetYaw = leaf:GetAttribute("GlideTargetYaw"),
		liftHeight = leaf:GetAttribute("GlideLiftHeight"),
		tumbleAmplitude = leaf:GetAttribute("GlideTumbleAmplitude"),
		tumbleFreq = leaf:GetAttribute("GlideTumbleFreq"),
		perpX = leaf:GetAttribute("GlidePerpX"),
		perpZ = leaf:GetAttribute("GlidePerpZ"),
		swayAmplitude = leaf:GetAttribute("GlideSwayAmplitude"),
		swayFreq = leaf:GetAttribute("GlideSwayFreq"),
		swayPhase = leaf:GetAttribute("GlideSwayPhase"),
		flutterFreq = leaf:GetAttribute("GlideFlutterFreq"),
		flutterPhase = leaf:GetAttribute("GlideFlutterPhase"),
		peakTime = leaf:GetAttribute("GlidePeakTime"),
		fallExponent = leaf:GetAttribute("GlideFallExponent"),
		duration = leaf:GetAttribute("MotionDuration"),
	}
end

function LeafRenderer.Start()
	local active = {} -- leaf -> true, only currently-animating leaves
	local watched = setmetatable({}, { __mode = "k" }) -- leaf -> true, already has a listener

	local function activate(leaf)
		active[leaf] = true
	end

	local function watchLeaf(leaf)
		if watched[leaf] then
			return
		end
		watched[leaf] = true

		-- MotionStart is always the LAST attribute LeafSpawner sets for a given motion, so by the
		-- time this fires every other attribute for that motion is already in place.
		leaf:GetAttributeChangedSignal("MotionStart"):Connect(function()
			activate(leaf)
		end)

		-- Covers this script starting (or a player joining) after a leaf's motion already began --
		-- MotionStart being set at all means it might still be mid-flight.
		if leaf:GetAttribute("MotionStart") then
			activate(leaf)
		end
	end

	local function onDescendantAdded(descendant)
		if descendant:IsA("BasePart") and descendant.Name == "Leaf" then
			watchLeaf(descendant)
		end
	end

	local function onDescendantRemoving(descendant)
		active[descendant] = nil
	end

	local leavesFolder = Workspace:WaitForChild("Leaves")
	leavesFolder.DescendantAdded:Connect(onDescendantAdded)
	leavesFolder.DescendantRemoving:Connect(onDescendantRemoving)
	for _, descendant in ipairs(leavesFolder:GetDescendants()) do
		onDescendantAdded(descendant)
	end

	RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for leaf in pairs(active) do
			if not leaf.Parent then
				active[leaf] = nil
				continue
			end

			local kind = leaf:GetAttribute("MotionKind")
			local startTime = leaf:GetAttribute("MotionStart")
			local duration = leaf:GetAttribute("MotionDuration")
			if not kind or not startTime or not duration or duration <= 0 then
				active[leaf] = nil
				continue
			end

			local elapsed = now - startTime
			local finished = elapsed >= duration
			if finished then
				elapsed = duration
			end

			local cframe
			if kind == "Fall" then
				cframe = LeafMotion.ComputeFalling(readFallParams(leaf), elapsed)
			elseif kind == "Glide" then
				cframe = LeafMotion.ComputeGlide(readGlideParams(leaf), elapsed)
			end

			if cframe then
				leaf.CFrame = cframe
			end

			if finished then
				active[leaf] = nil
			end
		end
	end)
end

return LeafRenderer
