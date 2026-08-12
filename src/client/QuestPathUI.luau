local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local NPCConfig = require(ReplicatedStorage.Shared.NPCConfig)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)

-- A world-space guiding path from the player to Ruisu-the-guide, shown for a first-time player (or
-- anyone who hasn't finished the Tutorial quest yet -- same thing, see PlayerQuests.luau) so they
-- actually notice the NPC instead of wandering past. Reads the replicated Quest_Tutorial player
-- Attribute directly (PlayerQuests.luau sets it server-side) -- no remote round-trip needed, same
-- pattern RoundUI already uses for IsAFK/InActiveRound.
--
-- Fully reactive to that Attribute in BOTH directions, not just a one-shot "build once, tear down
-- once" -- AdminCommands' :resetquest clears it live (for re-testing the tutorial without a
-- rejoin), and the path needs to reappear the moment that happens, not just disappear the moment
-- the quest completes.
--
-- A persistent Beam is the "line" (follows both endpoints for free -- Attachment0 on the player's
-- current HumanoidRootPart, Attachment1 on the guide rig's root part, no manual per-frame sync
-- needed for either), and a handful of small chevron-shaped Models (two thin Neon bars meeting at a
-- point, see buildArrow/makeChevronBar) loop along that same path on a Heartbeat, giving the
-- "animated arrow" motion the line by itself doesn't have. Deliberately not using a scrolling
-- Beam.Texture for this -- that needs an uploaded arrow-strip image asset, which nothing in this
-- project's toolchain can produce/verify; a chevron built from two plain Parts needs no external
-- asset at all, and actually reads as an arrowhead (unlike a first-pass Part.Shape = Wedge, which is
-- a ramp/doorstop shape from most viewing angles -- replaced after the user flagged it as unclear
-- and floating too high near head height instead of down along the path).
--
-- Only ever visible in the Lobby, never on a round map -- gated on the same replicated
-- `InActiveRound` player Attribute RoundUI/MapProgressUI/RoundResultsUI already trust for "is this
-- player actually on the round map right now" (see RoundSystem.luau's teleportPlayersTo), not just
-- inferred from distance -- that Attribute is the authoritative signal, so this checks it directly
-- rather than relying on the map happening to be RoundConfig.MapAwayOffset (10,000 studs) away as
-- the only thing keeping the two from ever overlapping. MAX_DISTANCE below is kept as a second,
-- redundant guard (also hides it if the player's simply too far from the guide inside the Lobby
-- itself), not the primary mechanism.
--
-- IMPORTANT: Workspace.StreamingEnabled is on project-wide (see CLAUDE.md's Performance notes) --
-- while a player is off doing a round, the Lobby (and the guide rig in it) streams OUT of their
-- client entirely, and streams back in as a BRAND NEW Instance once they return, not the same one.
-- A guideRoot/guideAttachment reference captured once at the start would silently go stale the very
-- first time this happens -- resyncGuideAttachment() below re-validates and, if needed, re-finds the
-- rig and rebuilds just the Attachment every heartbeat (throttled), specifically to survive that.
local QuestPathUI = {}

local TUTORIAL_QUEST_ID = QuestConfig.Tutorial.Id
local GUIDE_NPC = NPCConfig.Guide

local MAX_DISTANCE = 200
local RIG_RESYNC_INTERVAL_SECONDS = 2

local ARROW_COUNT = 15
local ARROW_CYCLE_SECONDS = 8 -- how long one arrow takes to travel the full path (was 2.4 -- too fast)
local ARROW_HOVER_HEIGHT = 0.7 -- just above the ground/leaf litter -- was 3 (roughly head height),
	-- which read as floating disconnected from the path itself rather than a trail leading somewhere
local ARROW_COLOR = Color3.fromRGB(255, 205, 60)

-- Chevron geometry ("local space," as if the model's own pivot sits at world origin facing local
-- -Z -- CFrame.lookAt's convention, matching how this gets oriented every frame below) -- a tip
-- plus two back corners, each pair of points joined by one thin bar, forming a ">" that actually
-- reads as an arrowhead from a normal 3rd-person camera angle. Replaces the previous single
-- Part.Shape = Wedge, which is a ramp/doorstop shape, not an arrow, from most viewing angles.
local ARROW_TIP = Vector3.new(0, 0, -0.55)
local ARROW_BACK_LEFT = Vector3.new(-0.4, 0, 0.35)
local ARROW_BACK_RIGHT = Vector3.new(0.4, 0, 0.35)
local ARROW_BAR_THICKNESS = 0.22
local ARROW_BAR_HEIGHT = 0.16

local BEAM_COLOR = Color3.fromRGB(255, 205, 60)
local BEAM_WIDTH = 0.35

-- Same fallback chain as NPCInteraction/NPCDialogueUI's own local copies -- kept as a small local
-- copy rather than a shared require, per this project's established convention (see
-- NPCDialogueUI.luau's own comment on why).
local function findRigRootPart(rig)
	return rig:FindFirstChild("HumanoidRootPart")
		or rig.PrimaryPart
		or rig:FindFirstChildWhichIsA("BasePart", true)
end

local function findGuideRoot()
	local rig = Workspace:FindFirstChild(GUIDE_NPC.RigName, true) -- recursive, may be nested (see CLAUDE.md)
	return rig and findRigRootPart(rig)
end

local function makeChevronBar(name, p1, p2)
	local bar = Instance.new("Part")
	bar.Name = name
	local length = (p2 - p1).Magnitude
	bar.Size = Vector3.new(ARROW_BAR_THICKNESS, ARROW_BAR_HEIGHT, length)
	bar.CFrame = CFrame.new((p1 + p2) / 2, p2) -- aligns the part's length axis (Z) along p1->p2
	bar.Color = ARROW_COLOR
	bar.Material = Enum.Material.Neon
	bar.Anchored = true
	bar.CanCollide = false
	bar.CanQuery = false
	bar.CanTouch = false
	bar.CastShadow = false
	bar.Transparency = 1
	return bar
end

-- A small invisible Part sitting exactly at local origin, matching the origin the two bars above
-- were authored around -- set as PrimaryPart so Model:PivotTo(cframe) each frame moves/rotates the
-- whole chevron as one rigid unit with the tip always pointing along the target CFrame's LookVector,
-- instead of needing per-bar CFrame math redone every frame.
local function buildArrow(layoutOrder)
	local model = Instance.new("Model")
	model.Name = "GuideArrow" .. layoutOrder

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.1, 0.1, 0.1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.CFrame = CFrame.new(0, 0, 0)
	root.Parent = model
	model.PrimaryPart = root

	local left = makeChevronBar("Left", ARROW_BACK_LEFT, ARROW_TIP)
	left.Parent = model
	local right = makeChevronBar("Right", ARROW_BACK_RIGHT, ARROW_TIP)
	right.Parent = model

	model.Parent = Workspace
	return { model = model, bars = { left, right } }
end

local function isQuestComplete(player)
	return player:GetAttribute("Quest_" .. TUTORIAL_QUEST_ID) == true
end

function QuestPathUI.Start()
	local player = Players.LocalPlayer

	local guideRoot = nil
	local beam = nil
	local playerAttachment = nil
	local guideAttachment = nil
	local arrows = {}
	local heartbeatConn = nil
	local characterConn = nil
	local lastResyncAttempt = 0

	-- Bumped every time teardown() runs -- an in-flight rig-search coroutine captures the value it
	-- started with and checks it hasn't changed before proceeding, so a stale search from a PRIOR
	-- build (e.g. one already superseded by a reset-then-rebuild cycle) can never resurrect itself.
	local generation = 0
	local building = false -- true once a search/build is in progress or complete, for syncState below

	local function hideEverything()
		if beam then
			beam.Enabled = false
		end
		for _, arrow in ipairs(arrows) do
			for _, bar in ipairs(arrow.bars) do
				bar.Transparency = 1
			end
		end
	end

	local function teardown()
		generation += 1
		building = false
		if heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
		if characterConn then
			characterConn:Disconnect()
			characterConn = nil
		end
		if beam then
			beam:Destroy()
			beam = nil
		end
		if playerAttachment then
			playerAttachment:Destroy()
			playerAttachment = nil
		end
		if guideAttachment then
			guideAttachment:Destroy()
			guideAttachment = nil
		end
		for _, arrow in ipairs(arrows) do
			arrow.model:Destroy()
		end
		table.clear(arrows)
	end

	local function attachToCharacter(character)
		local rootPart = character:WaitForChild("HumanoidRootPart", 10)
		if not rootPart or not beam then
			return -- teardown may have already run, or the character never got a root part in time
		end
		if playerAttachment then
			playerAttachment:Destroy()
		end
		playerAttachment = Instance.new("Attachment")
		playerAttachment.Name = "GuidePathPlayerAttachment"
		playerAttachment.Parent = rootPart
		beam.Attachment0 = playerAttachment
	end

	-- Re-validates the guide-side Attachment every RIG_RESYNC_INTERVAL_SECONDS (throttled -- this
	-- runs from the Heartbeat loop, so unconditionally re-finding the rig every frame would be
	-- wasteful). If the rig streamed out and back in as a new Instance since the last check,
	-- guideAttachment.Parent will have gone nil (the old one was destroyed along with the old rig) --
	-- re-find the rig, rebuild just the Attachment, and repoint the still-alive Beam at it. The Beam
	-- itself is deliberately parented to Workspace (not guideRoot) specifically so it survives this
	-- and never needs recreating, only Attachment1 does.
	local function resyncGuideAttachment(now)
		if guideAttachment and guideAttachment.Parent then
			return true
		end
		if now - lastResyncAttempt < RIG_RESYNC_INTERVAL_SECONDS then
			return false
		end
		lastResyncAttempt = now

		local newGuideRoot = findGuideRoot()
		if not newGuideRoot then
			return false
		end

		if guideAttachment then
			guideAttachment:Destroy()
		end
		guideRoot = newGuideRoot
		guideAttachment = Instance.new("Attachment")
		guideAttachment.Name = "GuidePathTargetAttachment"
		guideAttachment.Parent = guideRoot
		beam.Attachment1 = guideAttachment
		return true
	end

	local function buildPathVisuals()
		guideAttachment = Instance.new("Attachment")
		guideAttachment.Name = "GuidePathTargetAttachment"
		guideAttachment.Parent = guideRoot

		beam = Instance.new("Beam")
		beam.Name = "QuestGuideBeam"
		beam.Color = ColorSequence.new(BEAM_COLOR)
		beam.Transparency = NumberSequence.new(0.35, 0.75)
		beam.Width0 = BEAM_WIDTH
		beam.Width1 = BEAM_WIDTH * 0.2
		beam.FaceCamera = true
		beam.LightEmission = 0.6
		beam.Attachment1 = guideAttachment
		beam.Enabled = false
		beam.Parent = Workspace

		for i = 1, ARROW_COUNT do
			table.insert(arrows, buildArrow(i))
		end

		if player.Character then
			attachToCharacter(player.Character)
		end
		characterConn = player.CharacterAdded:Connect(attachToCharacter)

		heartbeatConn = RunService.Heartbeat:Connect(function()
			if player:GetAttribute("InActiveRound") == true then
				hideEverything()
				return
			end

			local now = os.clock()
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			local guideReady = resyncGuideAttachment(now)

			if not rootPart or not playerAttachment or not beam.Attachment0 or not guideReady then
				hideEverything()
				return
			end

			local playerPos = rootPart.Position
			local guidePos = guideRoot.Position
			local distance = (playerPos - guidePos).Magnitude
			-- Also covers the near-zero-distance case (standing right on top of the guide) -- below
			-- this, CFrame.lookAt's direction vector would be too close to zero-length, which errors.
			if distance > MAX_DISTANCE or distance < 0.1 then
				hideEverything()
				return
			end

			beam.Enabled = true

			local direction = guidePos - playerPos
			for i, arrow in ipairs(arrows) do
				local stagger = (i - 1) / ARROW_COUNT
				local t = (now / ARROW_CYCLE_SECONDS + stagger) % 1
				local groundPos = playerPos:Lerp(guidePos, t)
				local pos = groundPos + Vector3.new(0, ARROW_HOVER_HEIGHT, 0)
				arrow.model:PivotTo(CFrame.lookAt(pos, pos + direction))
				-- Fades in/out at the very start/end of each loop instead of popping, and stays
				-- fully opaque (Transparency 0) through the middle stretch of the path.
				local edgeFade = math.clamp(math.min(t / 0.1, (1 - t) / 0.1), 0, 1)
				local transparency = 1 - edgeFade
				for _, bar in ipairs(arrow.bars) do
					bar.Transparency = transparency
				end
			end
		end)
	end

	local function startSearchAndBuild()
		building = true
		local myGeneration = generation

		task.spawn(function()
			local rig = nil
			local warned = false
			local searchStart = os.clock()
			repeat
				if myGeneration ~= generation then
					return -- superseded by a teardown (quest completed, or a fresh reset cycle) since this began
				end
				rig = findGuideRoot()
				if not rig then
					if not warned and os.clock() - searchStart > 30 then
						warned = true
						warn(string.format("[QuestPathUI] no '%s' rig found in Workspace after 30s -- still retrying, but check it's placed and named exactly this", GUIDE_NPC.RigName))
					end
					task.wait(RIG_RESYNC_INTERVAL_SECONDS)
				end
			until rig

			if myGeneration ~= generation then
				return
			end

			guideRoot = rig
			buildPathVisuals()
		end)
	end

	-- The single place that decides "should the path exist right now" -- called once up front and
	-- again every time Quest_Tutorial changes in either direction (completed -> tear down; reset
	-- back to incomplete via :resetquest -> search and build again). `building` guards against
	-- starting a second concurrent search/build if this fires more than once while already active.
	local function syncState()
		if isQuestComplete(player) then
			if building then
				teardown()
			end
		elseif not building then
			startSearchAndBuild()
		end
	end

	player:GetAttributeChangedSignal("Quest_" .. TUTORIAL_QUEST_ID):Connect(syncState)
	syncState()
end

return QuestPathUI
