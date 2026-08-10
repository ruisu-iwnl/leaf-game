local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ItemPreviewBuilder = require(game:GetService("ReplicatedStorage").Shared.ItemPreviewBuilder)
local PanelMotion = require(script.Parent.PanelMotion)

-- Store item preview: clicking an unowned cosmetic in StorePanelUI opens this instead of going
-- straight to a text-only buy confirm -- a slowly-rotating 3D ViewportFrame model of the actual
-- item (built by ItemPreviewBuilder, shared so both this and the real tools agree on what things
-- look like), its name/description/price, and BUY/CANCEL. BUY performs the purchase directly and
-- hands off to Ruisu's dialogue box for the "thank you"/failure message (same as before); CANCEL
-- (or clicking outside) just backs out to the store panel with nothing spent.
local ItemPreviewUI = {}

local PANEL_COLOR = Color3.fromRGB(58, 34, 20)
local PANEL_TRANSPARENCY = 0.05
local STROKE_COLOR = Color3.fromRGB(210, 150, 80)
local ACCENT_COLOR = Color3.fromRGB(255, 205, 60)
local DESCRIPTION_COLOR = Color3.fromRGB(225, 205, 180)
local BADGE_OUTLINE = Color3.fromRGB(255, 238, 210)
local VIEWPORT_BACKGROUND = Color3.fromRGB(40, 25, 15)
local CANCEL_COLOR = Color3.fromRGB(90, 58, 36)

local PANEL_WIDTH_SCALE = 0.34
local PANEL_MIN_SIZE = Vector2.new(300, 460)
local PANEL_MAX_SIZE = Vector2.new(420, 460)
local PADDING = 20
local VIEWPORT_HEIGHT = 200

-- Orbit camera, not a spinning model -- avoids needing a PrimaryPart pivot dance, just recomputes
-- the camera's position around a fixed look-at point every frame.
local ORBIT_SPEED = math.rad(26) -- radians/sec
local ORBIT_PITCH = math.rad(20)
local ORBIT_DISTANCE_MULTIPLIER = 1.7
local ORBIT_DISTANCE_BASE = 2
local PREVIEW_FOV = 50

local function buildCoinIcon(parent, size)
	local icon = Instance.new("Frame")
	icon.Name = "CoinIcon"
	icon.Size = UDim2.new(0, size, 0, size)
	icon.BackgroundColor3 = ACCENT_COLOR
	icon.BorderSizePixel = 0
	icon.ZIndex = 13
	icon.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = icon

	local stroke = Instance.new("UIStroke")
	stroke.Color = BADGE_OUTLINE
	stroke.Transparency = 0.15
	stroke.Thickness = 2
	stroke.Parent = icon

	return icon
end

local function buildButton(parent, text, color, textColor, layoutOrder)
	local button = Instance.new("TextButton")
	button.Name = text .. "Button"
	button.LayoutOrder = layoutOrder
	button.Size = UDim2.new(0.48, 0, 0, 40)
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
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = button

	PanelMotion.AnimateButton(button)

	return button
end

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ItemPreviewUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	-- ScreenGui.ZIndexBehavior actually defaults to Global, NOT Sibling -- under Global, every
	-- descendant in the whole ScreenGui is ranked on one flat ZIndex regardless of parent/child
	-- nesting. That's what caused the washed-out look: nameLabel/descriptionLabel/priceHolder/
	-- buttonRow (ZIndex 12) were rendering BEHIND backdrop (ZIndex 20) despite being nested three
	-- levels inside it, while only viewport (ZIndex 22) happened to be numbered high enough to
	-- escape it. Sibling mode makes a child always render above its own parent regardless of the
	-- numbers involved, which is what every ZIndex value in this file already assumed.
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Higher than StorePanelUI/NPCDialogueUI/SettingsUI/InventoryUI (all default DisplayOrder 0) --
	-- previewCosmetic() closes the store panel and opens this one back-to-back, so the store's own
	-- panel can still be mid fade-out (0.15s) the instant this shows; this guarantees this panel
	-- always wins that race regardless of which ScreenGui the engine happens to composite later.
	screenGui.DisplayOrder = 40
	screenGui.Parent = playerGui

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Active = true
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.55
	backdrop.Visible = false
	backdrop.ZIndex = 20
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Active = true
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(PANEL_WIDTH_SCALE, 0, 0, PANEL_MIN_SIZE.Y)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = PANEL_TRANSPARENCY
	panel.BorderSizePixel = 0
	panel.ZIndex = 21
	panel.Parent = backdrop

	local panelSizeConstraint = Instance.new("UISizeConstraint")
	panelSizeConstraint.MinSize = PANEL_MIN_SIZE
	panelSizeConstraint.MaxSize = PANEL_MAX_SIZE
	panelSizeConstraint.Parent = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = STROKE_COLOR
	panelStroke.Transparency = 0.35
	panelStroke.Thickness = 1.5
	panelStroke.Parent = panel

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.Position = UDim2.new(0, PADDING, 0, PADDING)
	viewport.Size = UDim2.new(1, -PADDING * 2, 0, VIEWPORT_HEIGHT)
	viewport.BackgroundColor3 = VIEWPORT_BACKGROUND
	viewport.BorderSizePixel = 0
	viewport.ZIndex = 22
	viewport.Parent = panel

	local viewportCorner = Instance.new("UICorner")
	viewportCorner.CornerRadius = UDim.new(0, 14)
	viewportCorner.Parent = viewport

	local viewportStroke = Instance.new("UIStroke")
	viewportStroke.Color = STROKE_COLOR
	viewportStroke.Transparency = 0.25
	viewportStroke.Thickness = 1.5
	viewportStroke.Parent = viewport

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	camera.FieldOfView = PREVIEW_FOV
	viewport.CurrentCamera = camera

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Position = UDim2.new(0, PADDING, 0, PADDING + VIEWPORT_HEIGHT + 12)
	nameLabel.Size = UDim2.new(1, -PADDING * 2, 0, 26)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextSize = 20
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.ZIndex = 12
	nameLabel.Parent = panel

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "Description"
	descriptionLabel.Position = UDim2.new(0, PADDING, 0, PADDING + VIEWPORT_HEIGHT + 40)
	descriptionLabel.Size = UDim2.new(1, -PADDING * 2, 0, 44)
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Font = Enum.Font.FredokaOne
	descriptionLabel.TextSize = 14
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
	descriptionLabel.TextColor3 = DESCRIPTION_COLOR
	descriptionLabel.ZIndex = 12
	descriptionLabel.Parent = panel

	local priceHolder = Instance.new("Frame")
	priceHolder.Name = "Price"
	priceHolder.Position = UDim2.new(0, PADDING, 0, PADDING + VIEWPORT_HEIGHT + 88)
	priceHolder.Size = UDim2.new(0, 100, 0, 26)
	priceHolder.BackgroundTransparency = 1
	priceHolder.ZIndex = 12
	priceHolder.Parent = panel

	local priceLayout = Instance.new("UIListLayout")
	priceLayout.FillDirection = Enum.FillDirection.Horizontal
	priceLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	priceLayout.Padding = UDim.new(0, 6)
	priceLayout.Parent = priceHolder

	local coinIconHolder = Instance.new("Frame")
	coinIconHolder.Name = "CoinIconHolder"
	coinIconHolder.LayoutOrder = 1
	coinIconHolder.Size = UDim2.new(0, 22, 0, 22)
	coinIconHolder.BackgroundTransparency = 1
	coinIconHolder.ZIndex = 12
	coinIconHolder.Parent = priceHolder
	buildCoinIcon(coinIconHolder, 22)

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Amount"
	priceLabel.LayoutOrder = 2
	priceLabel.Size = UDim2.new(0, 0, 1, 0)
	priceLabel.AutomaticSize = Enum.AutomaticSize.X
	priceLabel.BackgroundTransparency = 1
	priceLabel.Font = Enum.Font.FredokaOne
	priceLabel.TextSize = 18
	priceLabel.TextColor3 = Color3.new(1, 1, 1)
	priceLabel.ZIndex = 12
	priceLabel.Parent = priceHolder

	local buttonRow = Instance.new("Frame")
	buttonRow.Name = "Buttons"
	buttonRow.AnchorPoint = Vector2.new(0.5, 1)
	buttonRow.Position = UDim2.new(0.5, 0, 1, -PADDING)
	buttonRow.Size = UDim2.new(1, -PADDING * 2, 0, 40)
	buttonRow.BackgroundTransparency = 1
	buttonRow.ZIndex = 12
	buttonRow.Parent = panel

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	buttonLayout.Padding = UDim.new(0, 12)
	buttonLayout.Parent = buttonRow

	local cancelButton = buildButton(buttonRow, "Cancel", CANCEL_COLOR, Color3.new(1, 1, 1), 1)
	local buyButton = buildButton(buttonRow, "Buy", ACCENT_COLOR, PANEL_COLOR, 2)

	return backdrop, panel, viewport, camera, nameLabel, descriptionLabel, priceLabel, buyButton, cancelButton
end

function ItemPreviewUI.Start()
	local backdrop, panel, viewport, camera, nameLabel, descriptionLabel, priceLabel, buyButton, cancelButton = buildUI()
	local motion = PanelMotion.new(panel, backdrop)

	local currentModel = nil
	local rotationConn = nil
	local outsideClickConn = nil
	local pendingOnBuy = nil
	local pendingOnCancel = nil

	local function pointInside(guiObject, screenPos)
		local topLeft = guiObject.AbsolutePosition
		local size = guiObject.AbsoluteSize
		return screenPos.X >= topLeft.X and screenPos.X <= topLeft.X + size.X
			and screenPos.Y >= topLeft.Y and screenPos.Y <= topLeft.Y + size.Y
	end

	local function close()
		motion.Hide()
		if rotationConn then
			rotationConn:Disconnect()
			rotationConn = nil
		end
		if outsideClickConn then
			outsideClickConn:Disconnect()
			outsideClickConn = nil
		end
		if currentModel then
			currentModel:Destroy()
			currentModel = nil
		end
	end

	function ItemPreviewUI.Close()
		close()
	end

	-- config: { toolName, colors, name, description, price, onBuy, onCancel }. onBuy/onCancel are
	-- both called AFTER this panel has already closed itself, mirroring how NPCDialogueUI's own
	-- choice callbacks work -- callers never need to remember to close this themselves.
	function ItemPreviewUI.Show(config)
		pendingOnBuy = config.onBuy
		pendingOnCancel = config.onCancel

		local model = ItemPreviewBuilder.Build(config.toolName, config.colors)
		if model then
			model.Parent = viewport
			currentModel = model

			local ok, boundsCFrame, boundsSize = pcall(function()
				return model:GetBoundingBox()
			end)
			if ok then
				local center = boundsCFrame.Position
				local orbitRadius = math.max(boundsSize.Magnitude, 1) * ORBIT_DISTANCE_MULTIPLIER + ORBIT_DISTANCE_BASE
				local horizontalRadius = orbitRadius * math.cos(ORBIT_PITCH)
				local height = orbitRadius * math.sin(ORBIT_PITCH)

				local angle = 0
				rotationConn = RunService.RenderStepped:Connect(function(dt)
					angle += ORBIT_SPEED * dt
					local offset = Vector3.new(math.cos(angle) * horizontalRadius, height, math.sin(angle) * horizontalRadius)
					camera.CFrame = CFrame.new(center + offset, center)
				end)
			end
		end

		nameLabel.Text = config.name or ""
		descriptionLabel.Text = config.description or ""
		priceLabel.Text = tostring(math.floor(config.price or 0))

		motion.Show()

		-- Explicit screen-bounds check instead of click passthrough -- same reasoning as
		-- NPCDialogueUI/StorePanelUI's own backdrops.
		if not outsideClickConn then
			outsideClickConn = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				if not pointInside(panel, input.Position) then
					local onCancel = pendingOnCancel
					close()
					if onCancel then
						onCancel()
					end
				end
			end)
		end
	end

	buyButton.MouseButton1Click:Connect(function()
		local onBuy = pendingOnBuy
		close()
		if onBuy then
			onBuy()
		end
	end)

	cancelButton.MouseButton1Click:Connect(function()
		local onCancel = pendingOnCancel
		close()
		if onCancel then
			onCancel()
		end
	end)
end

return ItemPreviewUI
