local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local PanelMotion = require(script.Parent.PanelMotion)
local UILayout = require(script.Parent.UILayout)

-- Persistent left-center screen HUD showing the current round's map name and cleanup progress.
-- Only appears once the countdown is over (Active/Results) -- not during Loading/Countdown, so it
-- doesn't compete with the map-title flash and numeric countdown for attention -- and pops in/out
-- via the same shared PanelMotion pop+fade every other panel in the game uses, instead of an
-- instant Visible snap.
--
-- Same cream/warm-accent palette as ToastNotificationUI/BadgeNotificationUI (the badge popups), by
-- request, so this reads as the same "kind" of UI as the rest of the game's notifications instead
-- of its own one-off dark HUD look.
--
-- This is the "modularized progress bar" ask: it reads nothing map-specific except two Workspace
-- attributes RoundSystem already sets every round (ActiveMapFolderName, CleanupZoneProgress/Count)
-- plus MapConfig (for the display name) -- no WaitForChild chain into any particular map's
-- Workspace layout at all. Adding a second map to the pool needs zero changes here.
local MapProgressUI = {}

local CARD_COLOR = Color3.fromRGB(253, 250, 244)
local CARD_STROKE = Color3.fromRGB(224, 168, 96)
local TITLE_COLOR = Color3.fromRGB(58, 34, 20)
local DESCRIPTION_COLOR = Color3.fromRGB(130, 104, 84)
local TRACK_COLOR = Color3.fromRGB(224, 218, 206)
local TRACK_STROKE = Color3.fromRGB(40, 35, 30)
local FILL_COLOR = Color3.fromRGB(110, 205, 140)
local COMPLETE_HINT_COLOR = Color3.fromRGB(70, 150, 95)

local PULSE_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PROGRESS_SMOOTHING_PER_SECOND = 6

local DEFAULT_HINT_TEXT = "Keep the street clean!"
local COMPLETE_HINT_TEXT = "MAP COMPLETED! Great job!"

local folderNameToDisplayName = {}
for _, mapEntry in ipairs(MapConfig) do
	folderNameToDisplayName[mapEntry.WorkspaceFolderName] = mapEntry.DisplayName
end

function MapProgressUI.Start()
	task.spawn(function()
		local player = Players.LocalPlayer
		local playerGui = player:WaitForChild("PlayerGui")

		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = "MapProgressUI"
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = true
		screenGui.DisplayOrder = UILayout.DisplayOrder.HUD

		-- Invisible positioner/dimmer PanelMotion animates -- BackgroundTransparency stays 1 always
		-- (this is a HUD element, not a modal, so no screen dimming), only its Visible flag and the
		-- panel's own pop/fade matter. Same backdrop+panel split RoundResultsUI/every other modal in
		-- the game uses, just with an invisible backdrop instead of a dimmed one.
		local backdrop = Instance.new("Frame")
		backdrop.Name = "Backdrop"
		backdrop.Active = false
		backdrop.AnchorPoint = Vector2.new(0, 0.5)
		backdrop.Position = UDim2.new(0, 12, 0.5, 0)
		-- Deliberately small on BOTH ends of the clamp (not just a lower floor under an unchanged
		-- desktop-sized ceiling) -- an earlier pass only added a MinSize floor under the old 260x92
		-- ceiling, but on a real mobile device the scale component still resolved close to that
		-- ceiling, so it barely shrank at all (see the screenshot report this fixes). This is a
		-- genuinely smaller design at every size, roughly a quarter the area of the original,
		-- not just a smaller mobile-only variant of the same design.
		backdrop.Size = UDim2.new(0.22, 0, 0.065, 0)
		backdrop.BackgroundTransparency = 1
		backdrop.Visible = false
		backdrop.Parent = screenGui

		local backdropSizeConstraint = Instance.new("UISizeConstraint")
		backdropSizeConstraint.MinSize = Vector2.new(140, 48)
		backdropSizeConstraint.MaxSize = Vector2.new(188, 58)
		backdropSizeConstraint.Parent = backdrop

		local panel = Instance.new("Frame")
		panel.Name = "Panel"
		panel.Size = UDim2.new(1, 0, 1, 0)
		panel.BackgroundColor3 = CARD_COLOR
		panel.BorderSizePixel = 0
		panel.Parent = backdrop

		local panelCorner = Instance.new("UICorner")
		panelCorner.CornerRadius = UDim.new(0, 9)
		panelCorner.Parent = panel

		local panelStroke = Instance.new("UIStroke")
		panelStroke.Color = CARD_STROKE
		panelStroke.Transparency = 0.2
		panelStroke.Thickness = 1
		panelStroke.Parent = panel

		local mapNameLabel = Instance.new("TextLabel")
		mapNameLabel.Name = "MapName"
		mapNameLabel.Position = UDim2.new(0, 8, 0, 5)
		mapNameLabel.Size = UDim2.new(1, -16, 0, 14)
		mapNameLabel.BackgroundTransparency = 1
		mapNameLabel.Font = Enum.Font.FredokaOne
		mapNameLabel.TextSize = 12
		mapNameLabel.TextXAlignment = Enum.TextXAlignment.Left
		mapNameLabel.TextColor3 = TITLE_COLOR
		mapNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		mapNameLabel.Text = ""
		mapNameLabel.Parent = panel

		-- Thin pill track/fill, percentage right-aligned inside it.
		local track = Instance.new("Frame")
		track.Name = "Track"
		track.Position = UDim2.new(0, 8, 0, 21)
		track.Size = UDim2.new(1, -16, 0, 8)
		track.BackgroundColor3 = TRACK_COLOR
		track.BorderSizePixel = 0
		track.ClipsDescendants = true
		track.Parent = panel

		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(1, 0)
		trackCorner.Parent = track

		local trackStroke = Instance.new("UIStroke")
		trackStroke.Color = TRACK_STROKE
		trackStroke.Transparency = 0.8
		trackStroke.Thickness = 1
		trackStroke.Parent = track

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.AnchorPoint = Vector2.new(0, 0.5)
		fill.Position = UDim2.new(0, 0, 0.5, 0)
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.BackgroundColor3 = FILL_COLOR
		fill.BorderSizePixel = 0
		fill.Parent = track

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = fill

		local percentLabel = Instance.new("TextLabel")
		percentLabel.Name = "PercentLabel"
		percentLabel.AnchorPoint = Vector2.new(1, 0.5)
		percentLabel.Position = UDim2.new(1, -4, 0.5, 0)
		percentLabel.Size = UDim2.new(0, 30, 0.9, 0)
		percentLabel.BackgroundTransparency = 1
		percentLabel.Font = Enum.Font.FredokaOne
		percentLabel.TextSize = 9
		percentLabel.TextXAlignment = Enum.TextXAlignment.Right
		percentLabel.TextColor3 = TITLE_COLOR
		percentLabel.Text = "0%"
		percentLabel.ZIndex = 2
		percentLabel.Parent = track

		local hint = Instance.new("TextLabel")
		hint.Name = "Hint"
		hint.Position = UDim2.new(0, 8, 0, 32)
		hint.Size = UDim2.new(1, -16, 0, 12)
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.FredokaOne
		hint.TextSize = 9
		hint.TextXAlignment = Enum.TextXAlignment.Left
		hint.TextColor3 = DESCRIPTION_COLOR
		hint.TextTruncate = Enum.TextTruncate.AtEnd
		hint.Text = DEFAULT_HINT_TEXT
		hint.Parent = panel

		screenGui.Parent = playerGui

		local motion = PanelMotion.new(panel, backdrop)

		local baseHintColor = hint.TextColor3

		local displayed = 0
		local target = 0
		local attached = false
		local progressConn, heartbeatConn

		local function updateHint(value)
			if value >= 0.999 then
				hint.Text = COMPLETE_HINT_TEXT
				hint.TextColor3 = COMPLETE_HINT_COLOR
			else
				hint.Text = DEFAULT_HINT_TEXT
				hint.TextColor3 = baseHintColor
			end
		end

		local function pulse()
			local up = TweenService:Create(fill, PULSE_TWEEN_INFO, { BackgroundColor3 = Color3.new(1, 1, 1) })
			local down = TweenService:Create(fill, PULSE_TWEEN_INFO, { BackgroundColor3 = FILL_COLOR })
			up.Completed:Connect(function()
				down:Play()
			end)
			up:Play()
		end

		local function refreshMapName()
			local mapFolderName = Workspace:GetAttribute("ActiveMapFolderName")
			mapNameLabel.Text = (mapFolderName and folderNameToDisplayName[mapFolderName]) or ""
		end

		local function teardown()
			if not attached then
				return
			end
			attached = false
			if progressConn then
				progressConn:Disconnect()
				progressConn = nil
			end
			if heartbeatConn then
				heartbeatConn:Disconnect()
				heartbeatConn = nil
			end
			motion.Hide()
		end

		-- Nothing here yields -- unlike the old billboard version, there's no WaitForChild chain
		-- into a specific map's instances, so attach() is fully synchronous and safe to call
		-- repeatedly without a generation-guard.
		local function attach()
			if attached then
				return
			end
			attached = true
			refreshMapName()

			displayed = Workspace:GetAttribute("CleanupZoneProgress") or 0
			target = displayed
			fill.Size = UDim2.new(displayed, 0, 1, 0)
			percentLabel.Text = string.format("%d%%", math.floor(displayed * 100 + 0.5))
			updateHint(displayed)

			motion.Show()

			progressConn = Workspace:GetAttributeChangedSignal("CleanupZoneProgress"):Connect(function()
				local newValue = Workspace:GetAttribute("CleanupZoneProgress") or 0
				-- A full-to-empty jump (lap completed and reset) reads as a snap, not a rewind glide.
				if newValue < target - 0.5 then
					displayed = newValue
				end
				target = newValue
				updateHint(newValue)
				if newValue >= 0.999 then
					pulse()
				end
			end)

			heartbeatConn = RunService.Heartbeat:Connect(function(dt)
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

		-- Gated on InActiveRound (RoundSystem.luau's per-player attribute) -- a player who joined
		-- after this round's players were already teleported onto the map isn't part of it, so
		-- showing them a progress bar for a round they can't see or contribute to would be
		-- misleading. They just don't get this HUD element at all until the next round's teleport
		-- actually includes them.
		local function onRoundStateChanged()
			local roundState = Workspace:GetAttribute("RoundState")
			local inRound = player:GetAttribute("InActiveRound") == true
			if inRound and (roundState == "Active" or roundState == "Results") then
				attach()
			else
				teardown()
			end
		end

		Workspace:GetAttributeChangedSignal("RoundState"):Connect(onRoundStateChanged)
		-- Belt-and-suspenders: ActiveMapFolderName is set in the same server tick as RoundState
		-- flipping to Loading, so this should be redundant in practice, but keeps the label correct
		-- even if the two ever replicate a frame apart.
		Workspace:GetAttributeChangedSignal("ActiveMapFolderName"):Connect(function()
			if attached then
				refreshMapName()
			end
		end)

		-- Covers this script starting mid-round for a player who WAS actually teleported in (e.g. a
		-- client script reconnecting/reloading) -- a genuine mid-round *joiner* correctly stays
		-- torn down here since their InActiveRound is false until the next round's teleport.
		onRoundStateChanged()
	end)
end

return MapProgressUI
