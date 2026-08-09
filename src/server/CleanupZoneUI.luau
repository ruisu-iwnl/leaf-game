local Workspace = game:GetService("Workspace")

-- Builds the cleanup zone's floating UI once. Two separate BillboardGuis, since
-- BillboardGui.MaxDistance is one value for the whole gui and each piece wants a different range:
--   - Tutorial: a "come here" beacon, readable from well across the yard.
--   - Progress bar: only meaningful once you're actually standing at the zone, mid-range.
-- The progress bar is sized in pure Offset (pixels), not Scale (studs) -- a fixed on-screen length
-- and thickness that never grows/shrinks with camera distance, by request.
--
-- Text uses a fixed TextSize (not TextScaled) everywhere here: TextScaled shrinks to fit inside
-- its box, and with these labels' boxes sized generously it was rendering much smaller than
-- intended. A fixed size renders at that literal size regardless of box dimensions -- the boxes are
-- all BackgroundTransparency 1 with nothing else nearby, so a bit of overflow past an invisible
-- box edge is harmless.
--
-- LeafSpawner drives the bar via the Workspace "CleanupZoneProgress"/"CleanupZoneCount"
-- attributes; the actual smooth fill animation happens client-side (CleanupProgressBar.luau) so it
-- stays zero-lag regardless of server tick rate.
--
-- Always rebuilt from scratch (old ones destroyed first, never skipped) -- skipping rebuild when
-- one already exists risks leaving a stale/partial instance around (e.g. from a version with a
-- different child layout) that clients would then WaitForChild on forever.
local CleanupZoneUI = {}

function CleanupZoneUI.Start()
	local cleanupZone = Workspace:WaitForChild("CleanupZone")

	for _, name in ipairs({ "TutorialBillboard", "TitleBillboard", "ProgressBillboard" }) do
		local existing = cleanupZone:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	-- Far-range "come here" callout -- big, fun, readable from well across the yard.
	local tutorialBillboard = Instance.new("BillboardGui")
	tutorialBillboard.Name = "TutorialBillboard"
	tutorialBillboard.Size = UDim2.new(14, 0, 1.6, 0)
	tutorialBillboard.StudsOffset = Vector3.new(0, 11.8, 0)
	tutorialBillboard.MaxDistance = 600
	tutorialBillboard.AlwaysOnTop = true
	tutorialBillboard.LightInfluence = 0
	tutorialBillboard.Adornee = cleanupZone

	local tutorial = Instance.new("TextLabel")
	tutorial.Name = "Tutorial"
	tutorial.BackgroundTransparency = 1
	tutorial.Size = UDim2.new(1, 0, 1, 0)
	tutorial.Font = Enum.Font.FredokaOne
	tutorial.Text = "Blow leaves here to clean them up!"
	tutorial.TextScaled = false
	tutorial.TextSize = 38
	tutorial.TextWrapped = false
	tutorial.TextColor3 = Color3.fromRGB(255, 221, 170)
	tutorial.Parent = tutorialBillboard

	local tutorialStroke = Instance.new("UIStroke")
	tutorialStroke.Color = Color3.new(0, 0, 0)
	tutorialStroke.Transparency = 0.35
	tutorialStroke.Thickness = 2.5
	tutorialStroke.Parent = tutorial

	-- Close-range progress bar -- thin, minimal, fixed on-screen length/thickness (Offset/pixel
	-- sized, not Scale/studs) regardless of how close the player is.
	local progressBillboard = Instance.new("BillboardGui")
	progressBillboard.Name = "ProgressBillboard"
	progressBillboard.Size = UDim2.new(0, 300, 0, 74)
	progressBillboard.StudsOffset = Vector3.new(0, 7, 0)
	progressBillboard.MaxDistance = 90
	progressBillboard.AlwaysOnTop = true
	progressBillboard.LightInfluence = 0
	progressBillboard.Adornee = cleanupZone

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 1, 0)
	container.Parent = progressBillboard

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = container

	-- Thin, short pill bar, a slightly shaded (not pure) white track so it still reads as
	-- clean/minimal without blowing out. Scale-sized relative to the (fixed-pixel) container rather
	-- than its own fixed Offset value, so it and the percentage text inside it stay proportionally
	-- contained and never risk clipping at the container's edge.
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.LayoutOrder = 1
	track.Size = UDim2.new(0.85, 0, 0.28, 0)
	track.BackgroundColor3 = Color3.fromRGB(214, 210, 200)
	track.BackgroundTransparency = 0.05
	track.BorderSizePixel = 0
	track.Parent = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = Color3.fromRGB(40, 35, 30)
	trackStroke.Transparency = 0.75
	trackStroke.Thickness = 1
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.new(0, 0, 0.5, 0)
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(110, 220, 150)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	-- Right-aligned inside the track itself (not the fill, since the fill's width changes) --
	-- driven by CleanupProgressBar.luau client-side, off the same smoothed value as the bar itself
	-- so the number and the fill never visibly disagree. Scale-sized relative to the track, so it's
	-- always fully contained within it (and therefore appears/disappears together with the bar,
	-- including when the whole billboard goes out of MaxDistance range) regardless of the exact
	-- pixel resolution the billboard's canvas ends up rendering at.
	local percentLabel = Instance.new("TextLabel")
	percentLabel.Name = "PercentLabel"
	percentLabel.AnchorPoint = Vector2.new(1, 0.5)
	percentLabel.Position = UDim2.new(1, -6, 0.5, 0)
	percentLabel.Size = UDim2.new(0.32, 0, 0.9, 0)
	percentLabel.BackgroundTransparency = 1
	percentLabel.Font = Enum.Font.FredokaOne
	percentLabel.Text = "0%"
	percentLabel.TextScaled = false
	percentLabel.TextSize = 22
	percentLabel.TextWrapped = false
	percentLabel.TextXAlignment = Enum.TextXAlignment.Right
	percentLabel.TextColor3 = Color3.fromRGB(35, 30, 25)
	percentLabel.ZIndex = 2
	percentLabel.Parent = track

	-- A little context for why the bar keeps looping, rather than a one-time goal.
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.LayoutOrder = 2
	hint.BackgroundTransparency = 1
	hint.Size = UDim2.new(1, 0, 0.35, 0)
	hint.Font = Enum.Font.FredokaOne
	hint.Text = "Keep the street clean!"
	hint.TextScaled = false
	hint.TextSize = 22
	hint.TextWrapped = false
	hint.TextColor3 = Color3.fromRGB(230, 224, 214)
	hint.Parent = container

	local hintStroke = Instance.new("UIStroke")
	hintStroke.Color = Color3.new(0, 0, 0)
	hintStroke.Transparency = 0.45
	hintStroke.Thickness = 1.5
	hintStroke.Parent = hint

	tutorialBillboard.Parent = cleanupZone
	progressBillboard.Parent = cleanupZone
end

return CleanupZoneUI
