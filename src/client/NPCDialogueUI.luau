local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local PanelMotion = require(script.Parent.PanelMotion)

-- Shared dialogue box for every NPC in the game -- a Persona/Yakuza-style box anchored to the
-- bottom-center of the screen, a live portrait of the NPC's own rig on the left (angled + framed
-- exactly one deliberately-tuned way, see buildPortraitInto), name + typewriter text on the right,
-- and a row of choice buttons in the bottom-right corner.
--
-- Built ONCE and reused for every NPC -- an NPC-specific module (e.g. StoreDialogueUI.luau) never
-- builds any UI itself; it just calls NPCDialogueUI.Register(npcId, config) once at startup with
-- its own question/choices/click behavior. The server-side interaction (see NPCInteraction.luau)
-- fires ONE shared OpenNPCDialogue remote with just the npcId string -- the lookup happens
-- entirely client-side, so nothing but a plain string ever needs to cross the network. Every
-- design choice (box size, colors, portrait angle/zoom, typing speed, button animation) lives in
-- this ONE file, so changing it changes it for every NPC using this system.
local NPCDialogueUI = {}

local PANEL_COLOR = Color3.fromRGB(58, 34, 20)
local PANEL_TRANSPARENCY = 0.05
local STROKE_COLOR = Color3.fromRGB(210, 150, 80)
local ACCENT_COLOR = Color3.fromRGB(255, 205, 60)
local DEFAULT_CHOICE_COLOR = Color3.fromRGB(90, 58, 36)
local PORTRAIT_BACKGROUND = Color3.fromRGB(40, 25, 15)

local BOX_WIDTH = 640
local BOX_HEIGHT = 170
-- Width scales with the screen (clamped below) so this shrinks to fit smaller/mobile screens
-- instead of overflowing off the sides; height stays fixed since the content inside doesn't need
-- to grow, it just wraps narrower.
local BOX_WIDTH_SCALE = 0.85
local BOX_MIN_SIZE = Vector2.new(320, BOX_HEIGHT)
local BOX_MAX_SIZE = Vector2.new(BOX_WIDTH, BOX_HEIGHT)
local BOX_BOTTOM_MARGIN = 130 -- clears the bottom-right hotbar comfortably regardless of screen width
local PADDING = 20
local PORTRAIT_SIZE = 130

local TYPEWRITER_CHAR_INTERVAL = 0.018 -- ~one character per frame -- fast, but still reads as typed

-- Tuned once against a real rig (Ruisu) and locked in here -- a 3/4 angle (not a literal side
-- view, which shows almost no face on a flat-faced Roblox head) turned toward camera-right, framed
-- tight on just the head (accessories like hats extend past the bare Head part's own size, hence
-- the extra distance padding rather than sizing purely off that). Every NPC using this system gets
-- the exact same treatment automatically.
local PORTRAIT_YAW_DEGREES = -35
local PORTRAIT_FOV = 50
local PORTRAIT_DISTANCE_MULTIPLIER = 1.3
local PORTRAIT_DISTANCE_BASE = 1.4

-- A little past NPCInteraction's own ProximityPrompt activation distance (10 studs) -- so walking
-- away closes the dialogue only once you're genuinely out of conversation range, not right at the
-- exact boundary where the prompt itself is also flickering in and out.
local AUTO_CLOSE_DISTANCE = 14

-- Same fallback chain as NPCInteraction.luau's own findRootPart -- kept as a small local copy
-- rather than a shared require, since ServerScriptService modules never replicate to the client
-- to begin with.
local function findRigRootPart(rig)
	return rig:FindFirstChild("HumanoidRootPart")
		or rig.PrimaryPart
		or rig:FindFirstChildWhichIsA("BasePart", true)
end

-- npcId -> { rigName, displayName, question, choices = { { text, color?, textColor?, accent?,
-- onClick? }, ... } } -- filled in by NPC-specific modules via Register, read back out when the
-- OpenNPCDialogue remote fires with that npcId.
local registry = {}

function NPCDialogueUI.Register(npcId, config)
	registry[npcId] = config
end

-- Clones whatever's actually placed as `rigName` in Workspace and frames the fixed, tuned camera
-- on it (see the constants above). Scripts are stripped and parts anchored so nothing in the
-- clone ever moves or runs logic of its own -- it's a purely static display model. Skips the
-- rebuild entirely if this viewport is already showing this same rig (repeat opens of the same
-- NPC's dialogue, back to back, don't re-clone/re-frame anything).
local function buildPortraitInto(viewport, rigName)
	for _, child in ipairs(viewport:GetChildren()) do
		if child:IsA("Model") then
			child:Destroy()
		end
	end

	local rig = Workspace:FindFirstChild(rigName)
	if not rig then
		return
	end

	local clone = rig:Clone()
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
		end
	end
	clone.Parent = viewport

	local camera = viewport.CurrentCamera
	local ok = pcall(function()
		local head = clone:FindFirstChild("Head", true)
		local lookAt, faceDirection, headHeight

		if head then
			-- Close to dead center of the head -- this is meant to fill the frame with just the
			-- head, not leave room for shoulders/torso below it.
			lookAt = head.Position - Vector3.new(0, head.Size.Y * 0.05, 0)
			faceDirection = head.CFrame.LookVector
			headHeight = head.Size.Y
		else
			local pivot = clone:GetPivot()
			local extents = clone:GetExtentsSize()
			lookAt = pivot.Position + Vector3.new(0, extents.Y * 0.38, 0)
			faceDirection = pivot.LookVector
			headHeight = extents.Y * 0.2
		end

		local rotation = CFrame.Angles(0, math.rad(PORTRAIT_YAW_DEGREES), 0)
		local viewDirection = rotation:VectorToWorldSpace(faceDirection)

		camera.FieldOfView = PORTRAIT_FOV
		local distance = math.max(headHeight, 1) * PORTRAIT_DISTANCE_MULTIPLIER + PORTRAIT_DISTANCE_BASE
		camera.CFrame = CFrame.new(lookAt + viewDirection * distance, lookAt)
	end)
	if not ok then
		warn(string.format("[NPCDialogueUI] couldn't frame a portrait camera on %s", rigName))
	end
end

local function buildChoiceButton(parent, text, color, textColor, layoutOrder)
	local button = Instance.new("TextButton")
	button.Name = "Choice" .. layoutOrder
	button.LayoutOrder = layoutOrder
	button.Size = UDim2.new(0, 96, 0, 34)
	button.BackgroundColor3 = color
	button.AutoButtonColor = false
	button.Font = Enum.Font.FredokaOne
	button.Text = text
	button.TextSize = 17
	button.TextColor3 = textColor
	button.BorderSizePixel = 0
	button.ZIndex = 12
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	PanelMotion.AnimateButton(button)

	return button
end

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "NPCDialogueUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	-- Purely a visual dimmer + input blocker for the 3D world behind it -- NOT a button, same
	-- reasoning as SettingsUI/InventoryUI's backdrops (click passthrough turned out unreliable for
	-- nested buttons -- closing is handled by an explicit bounds check instead, see Start below).
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Active = true
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.55
	backdrop.Visible = false
	backdrop.ZIndex = 10
	backdrop.Parent = screenGui

	local box = Instance.new("Frame")
	box.Name = "DialogueBox"
	box.Active = true
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.new(0.5, 0, 1, -BOX_BOTTOM_MARGIN)
	box.Size = UDim2.new(BOX_WIDTH_SCALE, 0, 0, BOX_HEIGHT)
	box.BackgroundColor3 = PANEL_COLOR
	box.BackgroundTransparency = PANEL_TRANSPARENCY
	box.BorderSizePixel = 0
	box.ZIndex = 11
	box.Parent = backdrop

	local boxSizeConstraint = Instance.new("UISizeConstraint")
	boxSizeConstraint.MinSize = BOX_MIN_SIZE
	boxSizeConstraint.MaxSize = BOX_MAX_SIZE
	boxSizeConstraint.Parent = box

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 18)
	boxCorner.Parent = box

	local boxStroke = Instance.new("UIStroke")
	boxStroke.Color = STROKE_COLOR
	boxStroke.Transparency = 0.3
	boxStroke.Thickness = 1.5
	boxStroke.Parent = box

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Portrait"
	viewport.Position = UDim2.new(0, PADDING, 0, PADDING)
	viewport.Size = UDim2.new(0, PORTRAIT_SIZE, 0, PORTRAIT_SIZE)
	viewport.BackgroundColor3 = PORTRAIT_BACKGROUND
	viewport.BorderSizePixel = 0
	viewport.ZIndex = 12
	viewport.Parent = box

	local portraitCorner = Instance.new("UICorner")
	portraitCorner.CornerRadius = UDim.new(0, 14)
	portraitCorner.Parent = viewport

	local portraitStroke = Instance.new("UIStroke")
	portraitStroke.Color = STROKE_COLOR
	portraitStroke.Transparency = 0.25
	portraitStroke.Thickness = 1.5
	portraitStroke.Parent = viewport

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local textLeft = PADDING + PORTRAIT_SIZE + 18
	local textArea = Instance.new("Frame")
	textArea.Name = "TextArea"
	textArea.BackgroundTransparency = 1
	textArea.Position = UDim2.new(0, textLeft, 0, PADDING)
	textArea.Size = UDim2.new(1, -textLeft - PADDING, 0, PORTRAIT_SIZE)
	textArea.ZIndex = 12
	textArea.Parent = box

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 26)
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextSize = 22
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = ACCENT_COLOR
	nameLabel.ZIndex = 12
	nameLabel.Parent = textArea

	local questionLabel = Instance.new("TextLabel")
	questionLabel.Name = "Question"
	questionLabel.BackgroundTransparency = 1
	questionLabel.Position = UDim2.new(0, 0, 0, 32)
	questionLabel.Size = UDim2.new(1, 0, 0, 60)
	questionLabel.Font = Enum.Font.FredokaOne
	questionLabel.TextSize = 19
	questionLabel.TextWrapped = true
	questionLabel.TextXAlignment = Enum.TextXAlignment.Left
	questionLabel.TextYAlignment = Enum.TextYAlignment.Top
	questionLabel.TextColor3 = Color3.new(1, 1, 1)
	questionLabel.ZIndex = 12
	questionLabel.Parent = textArea

	-- AutomaticSize since the number of choice buttons can vary by NPC -- grows leftward from the
	-- right edge (HorizontalAlignment.Right below) as more get added, same reasoning as HotbarUI's
	-- own auto-sizing row.
	local buttonRow = Instance.new("Frame")
	buttonRow.Name = "Buttons"
	buttonRow.AnchorPoint = Vector2.new(1, 1)
	buttonRow.BackgroundTransparency = 1
	buttonRow.Position = UDim2.new(1, -PADDING, 1, -16)
	buttonRow.AutomaticSize = Enum.AutomaticSize.X
	buttonRow.Size = UDim2.new(0, 0, 0, 34)
	buttonRow.ZIndex = 12
	buttonRow.Parent = box

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	buttonLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	buttonLayout.Padding = UDim.new(0, 10)
	buttonLayout.Parent = buttonRow

	screenGui.Parent = playerGui
	return backdrop, box, viewport, nameLabel, questionLabel, buttonRow
end

function NPCDialogueUI.Start()
	local player = Players.LocalPlayer
	local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes")
	local openNPCDialogueRemote = remotes:WaitForChild("OpenNPCDialogue")

	local backdrop, box, viewport, nameLabel, questionLabel, buttonRow = buildUI()
	local motion = PanelMotion.new(box, backdrop)

	local currentPortraitRig = nil
	local outsideClickConn = nil
	local proximityConn = nil
	local typewriterGeneration = 0
	local choiceButtons = {}

	-- Guarded with a generation counter -- a stale in-progress typewriter (e.g. still typing the
	-- question when a choice gets clicked, or the dialogue reopens mid-type) supersedes itself
	-- cleanly instead of two loops fighting over the same label's Text.
	local function typeText(fullText)
		typewriterGeneration += 1
		local thisGeneration = typewriterGeneration
		questionLabel.Text = ""
		task.spawn(function()
			for i = 1, #fullText do
				if thisGeneration ~= typewriterGeneration then
					return
				end
				questionLabel.Text = string.sub(fullText, 1, i)
				task.wait(TYPEWRITER_CHAR_INTERVAL)
			end
		end)
	end

	local function pointInside(guiObject, screenPos)
		local topLeft = guiObject.AbsolutePosition
		local size = guiObject.AbsoluteSize
		return screenPos.X >= topLeft.X and screenPos.X <= topLeft.X + size.X
			and screenPos.Y >= topLeft.Y and screenPos.Y <= topLeft.Y + size.Y
	end

	local function closeDialogue()
		motion.Hide()
		if outsideClickConn then
			outsideClickConn:Disconnect()
			outsideClickConn = nil
		end
		if proximityConn then
			proximityConn:Disconnect()
			proximityConn = nil
		end
	end

	-- Exposed for an NPC's own onClick handler that wants to hand off to something else (e.g. Ruisu's
	-- Yes choice closing the dialogue and opening the store panel) without waiting on the
	-- backdrop-close animation to finish first.
	function NPCDialogueUI.Close()
		closeDialogue()
	end

	-- Exposed for an NPC's own onClick handler to reuse the "acknowledge, then close" pattern
	-- (e.g. a placeholder "not ready yet" message) instead of reimplementing typing/closing itself.
	function NPCDialogueUI.SayAndClose(text, duration)
		typeText(text)
		buttonRow.Visible = false
		task.delay(duration, closeDialogue)
	end

	local function showDialogue(config)
		if config.rigName ~= currentPortraitRig then
			currentPortraitRig = config.rigName
			buildPortraitInto(viewport, config.rigName)
		end

		nameLabel.Text = config.displayName or config.rigName or ""
		typeText(config.question or "")

		for _, button in ipairs(choiceButtons) do
			button:Destroy()
		end
		table.clear(choiceButtons)

		for i, choice in ipairs(config.choices or {}) do
			local color = choice.color or (choice.accent and ACCENT_COLOR or DEFAULT_CHOICE_COLOR)
			local textColor = choice.textColor or (choice.accent and PANEL_COLOR or Color3.new(1, 1, 1))
			local button = buildChoiceButton(buttonRow, choice.text or "", color, textColor, i)
			button.MouseButton1Click:Connect(function()
				if choice.onClick then
					choice.onClick()
				else
					closeDialogue()
				end
			end)
			table.insert(choiceButtons, button)
		end
		buttonRow.Visible = true

		motion.Show()

		-- Explicit screen-bounds check instead of click passthrough -- see the Backdrop comment
		-- in buildUI for why.
		if not outsideClickConn then
			outsideClickConn = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				if not pointInside(box, input.Position) then
					closeDialogue()
				end
			end)
		end

		-- Auto-closes if the player walks far enough away from the NPC mid-conversation, same
		-- spirit as the ProximityPrompt that opened this in the first place no longer being in
		-- range. Re-set up fresh each time (rather than left running once) since a different NPC
		-- -- at a different position -- might be the one talking next time.
		if proximityConn then
			proximityConn:Disconnect()
			proximityConn = nil
		end
		local rig = Workspace:FindFirstChild(config.rigName)
		local rigRoot = rig and findRigRootPart(rig)
		if rigRoot then
			proximityConn = RunService.Heartbeat:Connect(function()
				local character = player.Character
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")
				if not rootPart or (rootPart.Position - rigRoot.Position).Magnitude > AUTO_CLOSE_DISTANCE then
					closeDialogue()
				end
			end)
		end
	end

	-- Exposed for client-triggered dialogues that don't go through a server prompt/registry entry
	-- (e.g. a purchase confirm or a "thanks!" line fired from StorePanelUI while already talking to
	-- Ruisu) -- same config shape as Register, shown immediately rather than looked up by npcId.
	function NPCDialogueUI.Show(config)
		showDialogue(config)
	end

	openNPCDialogueRemote.OnClientEvent:Connect(function(npcId)
		local config = registry[npcId]
		if not config then
			warn(string.format("[NPCDialogueUI] no dialogue registered for '%s'", tostring(npcId)))
			return
		end
		showDialogue(config)
	end)
end

return NPCDialogueUI
