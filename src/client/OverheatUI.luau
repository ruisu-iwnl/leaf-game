local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local OverheatUI = {}

local TOOL_NAME = "LeafBlower"

local COLOR_COOL = Color3.fromRGB(120, 210, 255)
local COLOR_HOT = Color3.fromRGB(255, 120, 40)
local COLOR_OVERHEATED = Color3.fromRGB(255, 70, 60)

local FADE_TIME = 0.25
local FILL_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PULSE_TWEEN_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

-- A CanvasGroup wraps the label + track + fill so the whole widget can fade in/out with a single
-- GroupTransparency tween instead of coordinating three separate transparency tweens.
local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "OverheatUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	-- Sits above Roblox's default bottom-center hotbar rather than on top of it.
	local container = Instance.new("CanvasGroup")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -96)
	container.Size = UDim2.new(0, 200, 0, 10)
	container.BackgroundTransparency = 1
	container.GroupTransparency = 1
	container.Parent = screenGui

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0, 0)
	track.Size = UDim2.new(1, 0, 0, 5)
	track.BackgroundColor3 = Color3.new(1, 1, 1)
	track.BackgroundTransparency = 0.85
	track.BorderSizePixel = 0
	track.Parent = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0)
	fill.Position = UDim2.new(0, 0, 0, 0)
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = COLOR_COOL
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	screenGui.Parent = playerGui

	return container, track, fill
end

function OverheatUI.Start()
	local player = Players.LocalPlayer
	local container, track, fill = buildUI()

	local currentTool = nil
	local connections = {}
	local pulseTween = nil
	local equipped = false

	local function setPulsing(active)
		if active then
			if pulseTween then
				return
			end
			pulseTween = TweenService:Create(fill, PULSE_TWEEN_INFO, { BackgroundTransparency = 0.55 })
			pulseTween:Play()
		elseif pulseTween then
			pulseTween:Cancel()
			pulseTween = nil
			fill.BackgroundTransparency = 0
		end
	end

	local function refresh()
		local heatFraction = math.clamp(currentTool and currentTool:GetAttribute("HeatFraction") or 0, 0, 1)
		local overheated = currentTool and currentTool:GetAttribute("Overheated") or false

		TweenService:Create(fill, FILL_TWEEN_INFO, {
			Size = UDim2.new(heatFraction, 0, 1, 0),
			BackgroundColor3 = overheated and COLOR_OVERHEATED or COLOR_COOL:Lerp(COLOR_HOT, heatFraction),
		}):Play()

		setPulsing(overheated)
	end

	local function setEquipped(isEquipped)
		if equipped == isEquipped then
			return
		end
		equipped = isEquipped
		TweenService:Create(container, TweenInfo.new(FADE_TIME), {
			GroupTransparency = equipped and 0 or 1,
		}):Play()
	end

	local function unbindTool()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		connections = {}
		currentTool = nil
		setPulsing(false)
		setEquipped(false)
	end

	local function bindTool(tool)
		if currentTool == tool then
			return
		end
		unbindTool()
		currentTool = tool
		table.insert(connections, tool:GetAttributeChangedSignal("HeatFraction"):Connect(refresh))
		table.insert(connections, tool:GetAttributeChangedSignal("Overheated"):Connect(refresh))
		table.insert(connections, tool.AncestryChanged:Connect(function()
			if not tool:IsDescendantOf(workspace) then
				unbindTool()
			end
		end))
		refresh()
		setEquipped(true)
	end

	local function onCharacterAdded(character)
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and child.Name == TOOL_NAME then
				bindTool(child)
			end
		end
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and child.Name == TOOL_NAME then
				bindTool(child)
			end
		end)
		character.ChildRemoved:Connect(function(child)
			if child == currentTool then
				unbindTool()
			end
		end)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

return OverheatUI
