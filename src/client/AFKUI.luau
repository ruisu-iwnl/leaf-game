local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PanelMotion = require(script.Parent.PanelMotion)
local TopBar = require(script.Parent.TopBar)

-- The AFK toggle -- a "Z" icon next to the Settings gear (TopBar.luau builds the shared widget, same
-- reasoning as CoinsUI/SettingsUI sharing that row). Marking yourself AFK pulls you out of
-- RoundSystem's Intermission "is anyone actually here" gate and out of the next round entirely: no
-- map vote, no teleport onto the map, no Countdown freeze, no Results row -- you just stay parked in
-- the Lobby while everyone else plays. See RoundSystem.luau's IsAFK attribute doc comment for the
-- full server-side behavior this drives.
--
-- The server is the sole authority on IsAFK -- this module only ever requests a toggle (SetAFK
-- remote) and then reflects whatever Players.LocalPlayer:GetAttribute("IsAFK") actually ends up as,
-- rather than optimistically flipping the icon locally. A toggle the server rejects (state isn't a
-- Lobby phase) just leaves the attribute unchanged, so the icon naturally stays put instead of
-- needing a separate rollback path.
local AFKUI = {}

local CARD_COLOR = Color3.fromRGB(253, 250, 244)
local CARD_STROKE = Color3.fromRGB(224, 168, 96)
local TITLE_COLOR = Color3.fromRGB(58, 34, 20)

local ON_COLOR = Color3.fromRGB(255, 205, 60)
local OFF_COLOR = Color3.fromRGB(90, 58, 36)
local DISABLED_COLOR = Color3.fromRGB(70, 70, 76)

-- Same "still in the Lobby" phase set RoundSystem.luau's SetAFK handler enforces server-side --
-- duplicated here (not shared via a module) purely for instant click feedback without a round trip;
-- same pattern RoundUI.luau's own RoundState checks already use rather than a shared enum module.
-- Loading is included: the player hasn't actually been teleported anywhere yet during it (the map
-- reveals/builds 10,000 studs away -- see RoundConfig.MapAwayOffset), so they're still standing in
-- the Lobby right up until the real teleport, which is also when RoundSystem's `participants`
-- snapshot is taken.
local LOBBY_STATES = { Intermission = true, MapPick = true, MapTally = true, MapResult = true, Loading = true }

function AFKUI.Start()
	task.spawn(function()
		local player = Players.LocalPlayer
		local playerGui = player:WaitForChild("PlayerGui")

		local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes", 15)
		if not remotes then
			warn("[AFKUI] ReplicatedStorage.Shared.Remotes not found after 15s -- AFK toggle disabled this session.")
			return
		end
		local setAFKRemote = remotes:WaitForChild("SetAFK", 15)
		if not setAFKRemote then
			warn("[AFKUI] SetAFK remote not found after 15s -- AFK toggle disabled this session.")
			return
		end

		local built = TopBar.Build()
		local afkButton = built.afkButton
		local afkIcon = built.afkIcon
		PanelMotion.AnimateButton(afkButton)

		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = "AFKUI"
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = true
		-- Above every other custom panel in the game (StorePanelUI/SettingsUI/InventoryUI/
		-- NPCDialogueUI/RoundUI's own cards all sit at the default 0, RoundResultsUI at 20,
		-- ItemPreviewUI at 40, ToastNotificationUI at 60) so the confirmation toast below is never
		-- hidden behind whatever else happens to be open when the AFK icon is clicked. Only
		-- AdminCommandBar (100, a dev tool) stays above this on purpose.
		screenGui.DisplayOrder = 90

		-- Small confirmation toast -- pops in just under the icon, holds briefly, pops back out.
		-- Anchored top-right rather than the top-center slot every round-state card already uses
		-- (Intermission card, MapPick vote panel, countdown, timer pill) so it can never collide with
		-- any of those, several of which can be on screen at the exact moment this toggle is used.
		local toastBackdrop = Instance.new("Frame")
		toastBackdrop.Name = "ToastBackdrop"
		toastBackdrop.Active = false
		toastBackdrop.AnchorPoint = Vector2.new(1, 0)
		toastBackdrop.Position = UDim2.new(1, -20, 0, 64)
		toastBackdrop.Size = UDim2.new(0, 240, 0, 56)
		toastBackdrop.BackgroundTransparency = 1
		toastBackdrop.Visible = false
		toastBackdrop.ZIndex = 30
		toastBackdrop.Parent = screenGui

		local toastPanel = Instance.new("Frame")
		toastPanel.Name = "Panel"
		toastPanel.Size = UDim2.new(1, 0, 1, 0)
		toastPanel.BackgroundColor3 = CARD_COLOR
		toastPanel.BorderSizePixel = 0
		toastPanel.ZIndex = 30
		toastPanel.Parent = toastBackdrop

		local toastCorner = Instance.new("UICorner")
		toastCorner.CornerRadius = UDim.new(0, 12)
		toastCorner.Parent = toastPanel

		local toastStroke = Instance.new("UIStroke")
		toastStroke.Color = CARD_STROKE
		toastStroke.Transparency = 0.2
		toastStroke.Thickness = 1.5
		toastStroke.Parent = toastPanel

		local toastLabel = Instance.new("TextLabel")
		toastLabel.Name = "Label"
		toastLabel.Size = UDim2.new(1, -20, 1, -16)
		toastLabel.Position = UDim2.new(0, 10, 0, 8)
		toastLabel.BackgroundTransparency = 1
		toastLabel.Font = Enum.Font.FredokaOne
		toastLabel.TextSize = 15
		toastLabel.TextWrapped = true
		toastLabel.TextColor3 = TITLE_COLOR
		toastLabel.Text = ""
		toastLabel.ZIndex = 31
		toastLabel.Parent = toastPanel

		screenGui.Parent = playerGui

		local toastMotion = PanelMotion.new(toastPanel, toastBackdrop)

		-- Token guards a stale deferred Hide() (from an older toast whose hold just elapsed) from
		-- clobbering a newer toast that already started its own Show() -- same pattern as RoundUI's
		-- showFlash.
		local toastToken = 0
		local function showToast(text, holdSeconds)
			toastToken += 1
			local myToken = toastToken
			toastLabel.Text = text
			toastMotion.Show()
			task.delay(holdSeconds, function()
				if myToken == toastToken then
					toastMotion.Hide()
				end
			end)
		end

		local function refreshIcon()
			local roundState = Workspace:GetAttribute("RoundState")
			local isAFK = player:GetAttribute("IsAFK") == true
			local canToggle = LOBBY_STATES[roundState] == true
			if isAFK then
				afkIcon.BackgroundColor3 = ON_COLOR
			elseif canToggle then
				afkIcon.BackgroundColor3 = OFF_COLOR
			else
				afkIcon.BackgroundColor3 = DISABLED_COLOR
			end
		end

		afkButton.MouseButton1Click:Connect(function()
			local roundState = Workspace:GetAttribute("RoundState")
			if not LOBBY_STATES[roundState] then
				showToast("You can only toggle AFK in the Lobby, between rounds.", 2.2)
				return
			end
			local wantsAFK = not (player:GetAttribute("IsAFK") == true)
			setAFKRemote:FireServer(wantsAFK)
		end)

		player:GetAttributeChangedSignal("IsAFK"):Connect(function()
			refreshIcon()
			if player:GetAttribute("IsAFK") == true then
				showToast("You're AFK -- sitting out until you toggle back on.", 2.5)
			else
				showToast("Welcome back! You'll join the next round.", 2)
			end
		end)

		Workspace:GetAttributeChangedSignal("RoundState"):Connect(refreshIcon)
		refreshIcon()
	end)
end

return AFKUI
