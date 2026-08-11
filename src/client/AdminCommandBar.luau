local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- A tiny self-contained command bar for dev/testing commands (":addmoney me 100"), bypassing
-- Roblox's chat entirely -- this place's chat pipeline wasn't reliably delivering messages to the
-- server, so this owns both ends (client input -> RemoteEvent -> server) instead of depending on
-- a system that couldn't be debugged further from here. The server (AdminCommands.luau) is what
-- actually enforces who's allowed to run commands; this bar is just an input box, harmless if a
-- non-admin opens it.
local AdminCommandBar = {}

local TOGGLE_KEY = Enum.KeyCode.Backquote

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AdminCommandBar"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 100

	local box = Instance.new("TextBox")
	box.Name = "CommandBox"
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.new(0.5, 0, 1, -12)
	box.Size = UDim2.new(0, 460, 0, 36)
	box.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	box.BackgroundTransparency = 0.1
	box.TextColor3 = Color3.new(1, 1, 1)
	box.PlaceholderText = "Admin command, e.g. :addmoney me 100"
	box.PlaceholderColor3 = Color3.fromRGB(170, 170, 170)
	box.Font = Enum.Font.FredokaOne
	box.TextSize = 18
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	box.Text = ""
	box.Visible = false
	box.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = box

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.7
	stroke.Thickness = 1
	stroke.Parent = box

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = box

	screenGui.Parent = playerGui
	return box
end

-- init.client.luau starts every UI module in one sequential list -- this used to WaitForChild the
-- remotes directly in Start() with no timeout, which meant if Remotes was ever slow to replicate
-- (e.g. a heavier place taking longer to load), this dev-only command bar silently blocked every
-- module listed after it (HotbarUI, CoinsUI, PlayerListUI, LeafRenderer, the store, all of it)
-- from ever starting. Deferred to its own thread so a slow/missing remote only breaks this bar.
function AdminCommandBar.Start()
	task.spawn(function()
		local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes", 30)
		local adminCommandRemote = remotes and remotes:WaitForChild("AdminCommand", 30)
		if not adminCommandRemote then
			warn("[AdminCommandBar] AdminCommand remote never appeared -- command bar disabled")
			return
		end

		local box = buildUI()

		local function show()
			box.Visible = true
			box.Text = ""
			box:CaptureFocus()
		end

		local function hide()
			box.Visible = false
			box:ReleaseFocus()
		end

		-- gameProcessedEvent is true while the box itself has focus (the keystroke's going into the
		-- textbox, not to us), so this only ever fires the toggle when the bar is closed/unfocused.
		UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
			if gameProcessedEvent then
				return
			end
			if input.KeyCode == TOGGLE_KEY and not box.Visible then
				show()
			end
		end)

		box.FocusLost:Connect(function(enterPressed)
			if enterPressed and #box.Text > 0 then
				adminCommandRemote:FireServer(box.Text)
			end
			hide()
		end)
	end)
end

return AdminCommandBar
