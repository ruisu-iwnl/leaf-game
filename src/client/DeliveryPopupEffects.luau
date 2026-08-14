local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- Client-side half of the "+N" floating Coins popup (see LeafSpawner.luau's ShowDeliveryPopup,
-- server, for the other half). `amount` is real Coins actually earned -- already includes
-- upgrades/perks/golden-leaf bonuses AND DeliveryStreakSystem's streak multiplier, computed once
-- in init.server.luau's OnLeafDelivered listener -- not a raw leaf count. `color` tints the "+N"
-- to match the player's current streak tier (DeliveryStreakConfig.luau); `milestone` (optional,
-- e.g. "Amazing!") is a punchier flair label shown once, the instant a delivery pushes the streak
-- into a new tier. Fires at wherever the delivery happened (a blown-in leaf's landing spot, a
-- sack drop-off, a killed Big Leaf Pile) -- only the delivering player gets the event, so this
-- never has to reconcile multiple players' numbers popping at once. Same "server fires one
-- lightweight event, client plays it entirely locally" shape as BigLeafPileEffects.luau.
local DeliveryPopupEffects = {}

local POPUP_DURATION_SECONDS = 0.9
local RISE_STUDS = 3.5
local HORIZONTAL_JITTER_STUDS = 1.5
local FADE_DURATION_SECONDS = POPUP_DURATION_SECONDS * 0.5
local FADE_DELAY_SECONDS = POPUP_DURATION_SECONDS - FADE_DURATION_SECONDS
local DEFAULT_COLOR = Color3.fromRGB(255, 214, 89)

local function showPopup(amount, position, color, milestone)
	if not position or type(amount) ~= "number" or amount <= 0 then
		return
	end
	color = color or DEFAULT_COLOR

	-- Small random jitter so a rapid stream of single-leaf pops (a sustained blow into the zone)
	-- doesn't render as one number stacked on top of itself.
	local jitter = Vector3.new((math.random() - 0.5) * HORIZONTAL_JITTER_STUDS * 2, 0, (math.random() - 0.5) * HORIZONTAL_JITTER_STUDS * 2)

	local part = Instance.new("Part")
	part.Name = "DeliveryPopup"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(position + jitter + Vector3.new(0, 3, 0))
	part.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Popup"
	billboard.Adornee = part
	billboard.Size = UDim2.new(0, 100, 0, milestone and 56 or 36)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 150
	billboard.Parent = part

	-- Stacks the milestone flair (if any) above the Coins number and centers the group
	-- vertically, so a plain delivery (one label) and a milestone one (two) both read correctly.
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = billboard

	local fadeTweenInfo = TweenInfo.new(FADE_DURATION_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, FADE_DELAY_SECONDS)

	if milestone then
		local milestoneLabel = Instance.new("TextLabel")
		milestoneLabel.Name = "Milestone"
		milestoneLabel.LayoutOrder = 1
		milestoneLabel.BackgroundTransparency = 1
		milestoneLabel.Size = UDim2.new(1, 0, 0, 18)
		milestoneLabel.Font = Enum.Font.FredokaOne
		milestoneLabel.TextScaled = true
		milestoneLabel.Text = milestone
		milestoneLabel.TextColor3 = color
		milestoneLabel.Parent = billboard

		local milestoneStroke = Instance.new("UIStroke")
		milestoneStroke.Color = Color3.new(0, 0, 0)
		milestoneStroke.Transparency = 0.1
		milestoneStroke.Thickness = 1.5
		milestoneStroke.Parent = milestoneLabel

		local milestoneSizeConstraint = Instance.new("UITextSizeConstraint")
		milestoneSizeConstraint.MaxTextSize = 18
		milestoneSizeConstraint.MinTextSize = 10
		milestoneSizeConstraint.Parent = milestoneLabel

		-- Punchy scale-in (overshoot then settle) so the milestone moment reads as a bigger deal
		-- than an ordinary Coins popup, rather than just being extra text in the same style.
		local scale = Instance.new("UIScale")
		scale.Scale = 0.3
		scale.Parent = milestoneLabel
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

		TweenService:Create(milestoneLabel, fadeTweenInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(milestoneStroke, fadeTweenInfo, { Transparency = 1 }):Play()
	end

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.LayoutOrder = 2
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 32)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "+" .. tostring(amount)
	label.TextColor3 = color
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.2
	stroke.Thickness = 1.5
	stroke.Parent = label

	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MaxTextSize = 22
	sizeConstraint.MinTextSize = 11
	sizeConstraint.Parent = label

	TweenService:Create(part, TweenInfo.new(POPUP_DURATION_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = part.CFrame + Vector3.new(0, RISE_STUDS, 0),
	}):Play()

	TweenService:Create(label, fadeTweenInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fadeTweenInfo, { Transparency = 1 }):Play()

	task.delay(POPUP_DURATION_SECONDS, function()
		part:Destroy()
	end)
end

function DeliveryPopupEffects.Start()
	task.spawn(function()
		local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes", 15)
		if not remotes then
			warn("[DeliveryPopupEffects] ReplicatedStorage.Shared.Remotes not found after 15s -- delivery popups disabled this session.")
			return
		end
		local remote = remotes:WaitForChild("LeafDeliveryPopup", 15)
		if not remote then
			warn("[DeliveryPopupEffects] LeafDeliveryPopup remote not found after 15s -- delivery popups disabled this session.")
			return
		end
		remote.OnClientEvent:Connect(showPopup)
	end)
end

return DeliveryPopupEffects
