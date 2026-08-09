local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LeafConfig = require(ReplicatedStorage.Shared.LeafConfig)

-- Pure position/orientation math for leaf motion, shared between the server (which decides WHEN
-- and WHERE a leaf's motion happens, and replicates its parameters once) and the client (which
-- renders the motion smoothly every local frame from those parameters, immune to network
-- latency/jitter -- see LeafSpawner.luau's top-of-file note and LeafRenderer.luau).
--
-- Both functions are pure: given a params table plus elapsed seconds, they return a CFrame with
-- no side effects and no randomness, so the server and every client always compute the exact same
-- pose for the same inputs. This is the exact math LeafSpawner.luau used to run every server
-- Heartbeat tick, unchanged -- only WHERE it executes moved.
local LeafMotion = {}

-- `params`: spawnBaseX/Y/Z, baseX/baseZ (landing X/Z -- the blower can redirect this mid-fall,
-- see LeafSpawner.ApplyBlow), restY, duration, swayAmplitude, swayFreqX/Z, phaseX/Z,
-- flutterFreqX/Z, flutterPhaseX/Z, initialYaw, spinSpeed, tumbleAmplitude, tumbleFreq.
--
-- Sway/tumble amplitude fades to exactly 0 as t approaches 1, so the leaf's swept path naturally
-- converges on (baseX, restY, baseZ) with no snap when it lands. The sway/flutter itself orbits a
-- wind anchor that glides from the upwind spawn point to the landing spot (same easing as the
-- vertical fall), so the whole trajectory reads as wind-carried.
function LeafMotion.ComputeFalling(params, elapsed)
	local t = math.clamp(elapsed / params.duration, 0, 1)
	local yEase = t * t * (3 - 2 * t)
	local y = params.spawnY - (params.spawnY - params.restY) * yEase

	local windAnchorX = params.spawnBaseX + (params.baseX - params.spawnBaseX) * yEase
	local windAnchorZ = params.spawnBaseZ + (params.baseZ - params.spawnBaseZ) * yEase

	local driftFactor = 1 - t
	local flutterScale = LeafConfig.FlutterAmplitudeRatio

	local swayX = math.sin(t * params.swayFreqX * math.pi * 2 + params.phaseX)
	local flutterX = math.sin(t * params.flutterFreqX * math.pi * 2 + params.flutterPhaseX) * flutterScale
	local x = windAnchorX + (swayX + flutterX) * params.swayAmplitude * driftFactor

	local swayZ = math.cos(t * params.swayFreqZ * math.pi * 2 + params.phaseZ)
	local flutterZ = math.cos(t * params.flutterFreqZ * math.pi * 2 + params.flutterPhaseZ) * flutterScale
	local z = windAnchorZ + (swayZ + flutterZ) * params.swayAmplitude * driftFactor

	-- Yaw/tumble use raw elapsed (not the clamped t) so spin rate stays constant instead of
	-- slowing down as the fall finishes -- matches the original per-tick behavior exactly.
	local yaw = params.initialYaw + params.spinSpeed * elapsed
	local tumbleX = math.sin(elapsed * params.tumbleFreq * math.pi * 2) * params.tumbleAmplitude * driftFactor
	local tumbleZ = math.cos(elapsed * params.tumbleFreq * math.pi * 2 * 0.7) * params.tumbleAmplitude * driftFactor

	return CFrame.new(x, y, z) * CFrame.Angles(tumbleX, yaw, tumbleZ)
end

-- `params`: startX/Z, targetX/Z, restY, liftHeight, startYaw, targetYaw, tumbleAmplitude,
-- tumbleFreq, perpX/Z, swayAmplitude, swayFreq, swayPhase, flutterFreq, flutterPhase, peakTime,
-- fallExponent, duration.
--
-- Glides from start to target, but not in a straight line: a perpendicular sway (plus a faster
-- flutter layered on top) sweeps it side to side, and the vertical motion is asymmetric -- quick
-- rise to a per-leaf peak, then a slow, lingering drift back down that only settles right at the
-- very end -- rather than a symmetric bounce, so it reads as featherweight and caught in moving
-- air rather than hopping directly from A to B. Everything (sway, flutter, tumble) is scaled by
-- the same envelope, so it's exactly 0 at the start/end -- it still lands precisely on target, flat.
function LeafMotion.ComputeGlide(params, elapsed)
	local t = math.clamp(elapsed / params.duration, 0, 1)
	local ease = t * t * (3 - 2 * t)

	local envelope
	if t <= params.peakTime then
		envelope = math.sin((t / params.peakTime) * math.pi / 2)
	else
		local fallT = (t - params.peakTime) / (1 - params.peakTime)
		envelope = (1 - fallT) ^ params.fallExponent
	end

	-- Driven by real elapsed seconds (not t, which is 0-1 over the whole glide) so the
	-- sway/flutter rate stays consistent regardless of how long any given glide lasts.
	local sway = (math.sin(elapsed * params.swayFreq * math.pi * 2 + params.swayPhase)
		+ math.sin(elapsed * params.flutterFreq * math.pi * 2 + params.flutterPhase) * 0.4) * params.swayAmplitude * envelope

	local x = params.startX + (params.targetX - params.startX) * ease + params.perpX * sway
	local z = params.startZ + (params.targetZ - params.startZ) * ease + params.perpZ * sway

	local verticalFlutter = math.sin(elapsed * params.flutterFreq * math.pi * 2 + params.flutterPhase + 1)
		* params.liftHeight * LeafConfig.GlideVerticalFlutterRatio * envelope
	local y = params.restY + params.liftHeight * envelope + verticalFlutter

	local yaw = params.startYaw + (params.targetYaw - params.startYaw) * ease
	local tumbleX = math.sin(elapsed * params.tumbleFreq * math.pi * 2) * params.tumbleAmplitude * envelope
	local tumbleZ = math.cos(elapsed * params.tumbleFreq * math.pi * 2 * 0.7) * params.tumbleAmplitude * envelope

	return CFrame.new(x, y, z) * CFrame.Angles(tumbleX, yaw, tumbleZ)
end

return LeafMotion
