local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UILayout = require(script.Parent.UILayout)

-- The pre-game title screen. StarterPlayer.CharacterAutoLoads is flipped off at runtime
-- (MainMenuSystem.luau) specifically so a player has no character at all -- and RoundSystem never
-- counts them for anything (OnMainMenu, see RoundSystem.luau's isSittingOutThisRound) -- until
-- they press Play here. This module owns the entire experience up to that click: a live,
-- slowly-turning view of the Lobby, the title/Play button, and the fade that hands off into
-- MainMenuSystem's PlayerReadyToPlay remote.
local MainMenuUI = {}

local LEAF_COLORS = {
	Color3.fromRGB(196, 120, 40),
	Color3.fromRGB(168, 88, 32),
	Color3.fromRGB(204, 156, 38),
	Color3.fromRGB(150, 60, 30),
	Color3.fromRGB(255, 208, 60),
}

local GOLD = Color3.fromRGB(255, 208, 60)
local CREAM = Color3.fromRGB(255, 244, 214)

-- The camera sits fixed at the spawn platform, roughly standing-eye height, and slowly turns in
-- place -- see startOrbit below for why an orbit flown at a guessed radius/height was dropped.
local ORBIT_PERIOD_SECONDS = 70
local LOOK_HEIGHT_OFFSET = 5

local CONFETTI_COUNT = 14
local FADE_SECONDS = 0.6

local function findLobbySpawn()
	local lobby = Workspace:WaitForChild("StartingLobby", 15)
	if not lobby then
		return nil
	end
	return lobby:WaitForChild("SpawnPlatform", 15)
end

function MainMenuUI.Start()
	local player = Players.LocalPlayer

	-- A character already existing (e.g. this code somehow reruns, or CharacterAutoLoads got
	-- flipped back on) means there's no menu to show -- skip entirely rather than yank control of
	-- an already-playing character's camera.
	if player.Character then
		return
	end

	local camera = Workspace.CurrentCamera

	-- Seize the camera before the first frame renders anything else, so there's never a flash of
	-- the default view before the black cover/orbit take over. This is the only part of Start()
	-- that runs synchronously -- everything past it runs inside task.spawn specifically so a
	-- slow/missing Remotes replication can NEVER block the rest of init.client.luau. MainMenuUI is
	-- called first thing there; before this was wrapped, an untimed WaitForChild right here froze
	-- every other client system's Start() call behind it -- not just the menu, the entire game --
	-- the moment Remotes was slow to appear (caught in testing: an "Infinite yield possible"
	-- warning on this exact line, with every other UI system also silently never starting as a
	-- result).
	camera.CameraType = Enum.CameraType.Scriptable

	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui", 15)
		if not playerGui then
			warn("[MainMenuUI] PlayerGui never appeared -- aborting main menu, restoring camera.")
			camera.CameraType = Enum.CameraType.Custom
			return
		end

		local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes", 15)
		if not remotes then
			warn("[MainMenuUI] Remotes folder never appeared -- aborting main menu, restoring camera so the rest of the game isn't stuck behind it.")
			camera.CameraType = Enum.CameraType.Custom
			return
		end
		local readyRemote = remotes:WaitForChild("PlayerReadyToPlay", 15)
		if not readyRemote then
			warn("[MainMenuUI] PlayerReadyToPlay remote never appeared -- aborting main menu, restoring camera so the rest of the game isn't stuck behind it.")
			camera.CameraType = Enum.CameraType.Custom
			return
		end

		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = "MainMenuUI"
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = true
		screenGui.DisplayOrder = UILayout.DisplayOrder.MainMenu

		local blackCover = Instance.new("Frame")
		blackCover.Name = "BlackCover"
		blackCover.Size = UDim2.new(1, 0, 1, 0)
		blackCover.BackgroundColor3 = Color3.new(0, 0, 0)
		blackCover.BackgroundTransparency = 0
		blackCover.BorderSizePixel = 0
		blackCover.ZIndex = 100
		blackCover.Parent = screenGui

		-- Frame.Active defaults to false, so an ordinary (even opaque) Frame does NOT block clicks
		-- to whatever's behind it -- without this, HUD buttons like the Settings gear (TopBar.luau,
		-- its own separate ScreenGui) would still be clickable right through the menu. Active=true
		-- and full-screen, ZIndex sitting between the confetti and the title/button so the Play
		-- button (ZIndex 10) still receives its own clicks.
		local inputBlocker = Instance.new("Frame")
		inputBlocker.Name = "InputBlocker"
		inputBlocker.Size = UDim2.new(1, 0, 1, 0)
		inputBlocker.BackgroundTransparency = 1
		inputBlocker.Active = true
		inputBlocker.ZIndex = 5
		inputBlocker.Parent = screenGui

		-- Falling leaf confetti, behind the text/button, ahead of nothing but the 3D scene.
		local confettiFolder = Instance.new("Frame")
		confettiFolder.Name = "Confetti"
		confettiFolder.Size = UDim2.new(1, 0, 1, 0)
		confettiFolder.BackgroundTransparency = 1
		confettiFolder.ZIndex = 1
		confettiFolder.Parent = screenGui

		for i = 1, CONFETTI_COUNT do
			-- A narrow capsule (fully-rounded short ends) rotated ~diagonally reads as a pointed
			-- leaf/eye shape -- a plain square UICorner'd to a circle just read as a dot.
			local width = math.random(7, 11)
			local height = math.random(14, 20)
			local leaf = Instance.new("Frame")
			leaf.Name = "Leaf" .. i
			leaf.AnchorPoint = Vector2.new(0.5, 0.5)
			leaf.Size = UDim2.new(0, width, 0, height)
			leaf.Position = UDim2.new(math.random(0, 1000) / 1000, 0, -0.1, 0)
			leaf.Rotation = math.random(20, 70)
			leaf.BackgroundColor3 = LEAF_COLORS[math.random(1, #LEAF_COLORS)]
			leaf.BorderSizePixel = 0
			leaf.ZIndex = 1
			leaf.Parent = confettiFolder

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = leaf

			local duration = math.random(90, 160) / 10
			local fallTween = TweenService:Create(leaf, TweenInfo.new(
				duration,
				Enum.EasingStyle.Linear,
				Enum.EasingDirection.In,
				-1,
				false,
				math.random(0, 100) / 10
			), {
				Position = UDim2.new(leaf.Position.X.Scale, 0, 1.1, 0),
				Rotation = leaf.Rotation + (math.random(0, 1) == 0 and 360 or -360),
			})
			fallTween:Play()
		end

		-- Title. A soft drop-shadow copy sits just behind it (same text/font, offset a few pixels,
		-- darker/translucent) for a more polished "game logo" look at this larger size, rather than
		-- just a flat stroke.
		local titleShadow = Instance.new("TextLabel")
		titleShadow.Name = "TitleShadow"
		titleShadow.AnchorPoint = Vector2.new(0.5, 0.5)
		titleShadow.Size = UDim2.new(0.92, 0, 0.22, 0)
		titleShadow.Position = UDim2.new(0.5, 4, 0.26, 6)
		titleShadow.BackgroundTransparency = 1
		titleShadow.Font = Enum.Font.FredokaOne
		titleShadow.Text = "LEAF IT TOGETHER!"
		titleShadow.TextColor3 = Color3.new(0, 0, 0)
		titleShadow.TextScaled = true
		titleShadow.TextTransparency = 1
		titleShadow.ZIndex = 9
		titleShadow.Parent = screenGui

		local titleShadowConstraint = Instance.new("UITextSizeConstraint")
		titleShadowConstraint.MaxTextSize = 108
		titleShadowConstraint.Parent = titleShadow

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.AnchorPoint = Vector2.new(0.5, 0.5)
		title.Size = UDim2.new(0.92, 0, 0.22, 0)
		title.Position = UDim2.new(0.5, 0, 0.26, 0)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne
		title.Text = "LEAF IT TOGETHER!"
		title.TextColor3 = GOLD
		title.TextScaled = true
		title.TextTransparency = 1
		title.TextStrokeTransparency = 0.3
		title.TextStrokeColor3 = Color3.new(0, 0, 0)
		title.ZIndex = 10
		title.Parent = screenGui

		local titleConstraint = Instance.new("UITextSizeConstraint")
		titleConstraint.MaxTextSize = 108
		titleConstraint.Parent = title

		local subtitle = Instance.new("TextLabel")
		subtitle.Name = "Subtitle"
		subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
		subtitle.Size = UDim2.new(0.7, 0, 0.06, 0)
		subtitle.Position = UDim2.new(0.5, 0, 0.42, 0)
		subtitle.BackgroundTransparency = 1
		subtitle.Font = Enum.Font.Gotham
		subtitle.Text = "Blow the leaves. Fill the piles. Relax."
		subtitle.TextColor3 = CREAM
		subtitle.TextScaled = true
		subtitle.TextTransparency = 1
		subtitle.TextStrokeTransparency = 0.5
		subtitle.TextStrokeColor3 = Color3.new(0, 0, 0)
		subtitle.ZIndex = 10
		subtitle.Parent = screenGui

		local subtitleConstraint = Instance.new("UITextSizeConstraint")
		subtitleConstraint.MaxTextSize = 26
		subtitleConstraint.Parent = subtitle

		-- Play button, directly below the title/subtitle rather than pinned to the bottom of the
		-- screen -- keeps it visually grouped with the title as one unit.
		local playButton = Instance.new("TextButton")
		playButton.Name = "PlayButton"
		playButton.AnchorPoint = Vector2.new(0.5, 0)
		playButton.Size = UDim2.new(0, 280, 0, 80)
		playButton.Position = UDim2.new(0.5, 0, 0.56, 0) -- starts lower, slides up into place
		playButton.BackgroundColor3 = GOLD
		playButton.AutoButtonColor = false
		playButton.Font = Enum.Font.FredokaOne
		playButton.Text = "PLAY"
		playButton.TextColor3 = Color3.fromRGB(60, 36, 10)
		playButton.TextScaled = true
		playButton.TextTransparency = 1
		playButton.ZIndex = 10
		playButton.Parent = screenGui

		local buttonConstraint = Instance.new("UITextSizeConstraint")
		buttonConstraint.MaxTextSize = 32
		buttonConstraint.Parent = playButton

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0.5, 0)
		buttonCorner.Parent = playButton

		local buttonStroke = Instance.new("UIStroke")
		buttonStroke.Color = Color3.fromRGB(120, 80, 20)
		buttonStroke.Thickness = 2
		buttonStroke.Transparency = 1
		buttonStroke.Parent = playButton

		local buttonScale = Instance.new("UIScale")
		buttonScale.Scale = 1
		buttonScale.Parent = playButton

		screenGui.Parent = playerGui

		-- Disable every other ScreenGui while the menu is up -- InputBlocker above already stops
		-- clicks reaching them, but they were still visibly rendering (e.g. the Coins/Settings-gear
		-- TopBar, which isn't gated on having a character) underneath the menu's own, non-full-bleed
		-- content. Tracks exactly which ones it disabled (hiddenGuis) so it only re-enables those --
		-- never a ScreenGui that was already off for its own unrelated reason -- and also catches any
		-- ScreenGui built AFTER the menu (other systems' Start() calls haven't all run yet at this
		-- point) via ChildAdded, so nothing can sneak in visible behind it.
		local hiddenGuis = {}
		local function hideGui(gui)
			if gui == screenGui or not gui:IsA("ScreenGui") or not gui.Enabled then
				return
			end
			hiddenGuis[gui] = true
			gui.Enabled = false
		end
		for _, gui in ipairs(playerGui:GetChildren()) do
			hideGui(gui)
		end
		local childAddedConnection = playerGui.ChildAdded:Connect(hideGui)

		-- A live view of the Lobby, anchored right at the spawn platform (eye height) and slowly
		-- turning in place -- like someone standing there taking in the view -- rather than an
		-- orbit flown at a guessed radius/height, which risked drifting past the platform's actual
		-- built geometry into open space (all that's out there is sky, given how hazy Atmosphere is
		-- configured -- see leaf.rbxlx's Lighting.Atmosphere). Anchoring directly on the platform
		-- guarantees whatever's actually built around it (trees, boundary, other players' spawn
		-- area) stays in frame regardless of the Lobby's real scale, which Claude has never seen.
		local orbitConnection
		local function startOrbit(centerPart)
			local eyePosition = centerPart.Position + Vector3.new(0, LOOK_HEIGHT_OFFSET, 0)
			local startTime = os.clock()
			orbitConnection = RunService.RenderStepped:Connect(function()
				local elapsed = os.clock() - startTime
				local angle = (elapsed / ORBIT_PERIOD_SECONDS) * math.pi * 2
				local lookDirection = Vector3.new(math.cos(angle), -0.05, math.sin(angle))
				camera.CFrame = CFrame.new(eyePosition, eyePosition + lookDirection * 40)
			end)
		end

		local function playEntranceAnimation()
			local fadeInfo = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(blackCover, fadeInfo, { BackgroundTransparency = 1 }):Play()

			task.delay(0.3, function()
				TweenService:Create(title, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					TextTransparency = 0,
				}):Play()
				TweenService:Create(titleShadow, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					TextTransparency = 0.55,
				}):Play()
			end)

			task.delay(0.7, function()
				TweenService:Create(subtitle, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					TextTransparency = 0.1,
				}):Play()
			end)

			task.delay(1.0, function()
				TweenService:Create(playButton, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.new(0.5, 0, 0.5, 0),
					TextTransparency = 0,
				}):Play()
				TweenService:Create(buttonStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 0.2,
				}):Play()
			end)
		end

		task.spawn(function()
			local spawnPlatform = findLobbySpawn()
			if not spawnPlatform then
				-- No Lobby found (still safe to proceed) -- just skip the orbit and reveal a plain
				-- black backdrop with the title/button so Play is never unreachable.
				playEntranceAnimation()
				return
			end
			startOrbit(spawnPlatform)
			playEntranceAnimation()
		end)

		local transitioning = false
		local function onPlayPressed()
			if transitioning then
				return
			end
			transitioning = true

			playButton.Active = false

			TweenService:Create(buttonScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Scale = 0.9,
			}):Play()

			local fadeOutInfo = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local fadeOutTween = TweenService:Create(blackCover, fadeOutInfo, { BackgroundTransparency = 0 })
			fadeOutTween:Play()

			fadeOutTween.Completed:Connect(function(playbackState)
				if playbackState ~= Enum.PlaybackState.Completed then
					return
				end

				if orbitConnection then
					orbitConnection:Disconnect()
					orbitConnection = nil
				end

				readyRemote:FireServer()

				if not player.Character then
					player.CharacterAdded:Wait()
				end
				local character = player.Character
				local humanoid = character:WaitForChild("Humanoid", 5)

				camera.CameraType = Enum.CameraType.Custom
				if humanoid then
					camera.CameraSubject = humanoid
				end

				childAddedConnection:Disconnect()
				for gui in pairs(hiddenGuis) do
					if gui.Parent then
						gui.Enabled = true
					end
				end

				screenGui:Destroy()
			end)
		end

		playButton.MouseButton1Click:Connect(onPlayPressed)

		playButton.MouseEnter:Connect(function()
			if transitioning then
				return
			end
			TweenService:Create(buttonScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Scale = 1.08,
			}):Play()
		end)

		playButton.MouseLeave:Connect(function()
			if transitioning then
				return
			end
			TweenService:Create(buttonScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end)
	end)
end

return MainMenuUI
