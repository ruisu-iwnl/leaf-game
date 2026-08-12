local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Two of the Leaf Patron perk's four effects (see PerkConfig.luau) -- the other two (Results row
-- design, exclusive tool skins) live in RoundResultsUI.luau and the CosmeticConfig/PlayerUpgrades
-- pair, respectively. Both effects here are purely cosmetic and entirely client-driven: every
-- client independently watches every OTHER player's replicated Perk_LeafPatron Attribute (Player
-- Attributes replicate to all clients by default, same as every other Perk_*/Upgrade_* flag this
-- game already reads client-side) and builds/tears down the effects locally -- no server round-trip
-- needed once the Attribute itself is set (PlayerUpgrades.GrantPerk/RemovePerk).
--
-- 1. Rainbow overhead nametag -- the default Roblox nameplate above a Humanoid's head has no
--    supported way to recolor, so it's hidden per-humanoid (DisplayDistanceType = None, which
--    replicates and affects every viewer, not just this client) and replaced with a real BillboardGui
--    whose TextColor3 cycles through the color wheel every RAINBOW_CYCLE_SECONDS. Always rainbow --
--    only the footstep trail's color is player-configurable (see below).
-- 2. Neon footstep trail -- a Trail stretched between two Attachments at ankle height on the
--    HumanoidRootPart, enabled only while the character is actually moving, with Lifetime tuned into
--    the requested 5-10s window so a trail segment visibly lingers after the player has moved on.
--    Its color follows the owning player's own VIPTrailColor Attribute (set via SettingsUI.luau's
--    Trail Color picker, server-validated by VIPPreferences.luau) -- "Rainbow" (default) animates
--    the same way the nametag does, or a "#RRGGBB" hex string holds a solid custom color.
--
-- Both effects are gated on the owning player's VIPEffectsEnabled Attribute (SettingsUI.luau's
-- on/off toggle) in addition to Perk_LeafPatron -- a player can own the perk but choose not to show
-- the flair, same as anyone viewing them then sees nothing extra at all.
local VIPEffects = {}

local RAINBOW_CYCLE_SECONDS = 3
local TRAIL_LIFETIME_SECONDS = 8
local DEFAULT_TRAIL_COLOR = Color3.fromRGB(160, 70, 230)

local function parseHexColor(hex)
	if typeof(hex) ~= "string" then
		return nil
	end
	local r = tonumber(hex:sub(2, 3), 16)
	local g = tonumber(hex:sub(4, 5), 16)
	local b = tonumber(hex:sub(6, 7), 16)
	if not (r and g and b) then
		return nil
	end
	return Color3.fromRGB(r, g, b)
end

local function effectsEnabled(player)
	return player:GetAttribute("VIPEffectsEnabled") ~= false
end

local function hideDefaultNameplate(humanoid)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

local function restoreDefaultNameplate(humanoid)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
end

local function buildNameplate(character, player)
	local head = character:WaitForChild("Head", 5)
	if not head or head:FindFirstChild("VIPNameplate") then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VIPNameplate"
	billboard.Adornee = head
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 100
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = player.DisplayName
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.3
	stroke.Thickness = 1.5
	stroke.Parent = label

	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MaxTextSize = 20
	sizeConstraint.Parent = label

	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not billboard.Parent then
			connection:Disconnect()
			return
		end
		local hue = (os.clock() % RAINBOW_CYCLE_SECONDS) / RAINBOW_CYCLE_SECONDS
		label.TextColor3 = Color3.fromHSV(hue, 0.85, 1)
	end)
end

local function buildFootTrail(character, player)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or root:FindFirstChild("VIPFootTrail") then
		return
	end

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "VIPTrailAttachment0"
	attachment0.Position = Vector3.new(-0.6, -2.9, 0)
	attachment0.Parent = root

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "VIPTrailAttachment1"
	attachment1.Position = Vector3.new(0.6, -2.9, 0)
	attachment1.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "VIPFootTrail"
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Lifetime = TRAIL_LIFETIME_SECONDS
	trail.MinLength = 0.05
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Color = ColorSequence.new(DEFAULT_TRAIL_COLOR)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Enabled = false
	trail.Parent = root

	-- Re-reads the color Attribute every frame (cheap -- a single GetAttribute call) rather than
	-- only on change, since "Rainbow" mode needs continuous updates anyway; a custom hex color only
	-- actually reassigns trail.Color when it changes, not every frame.
	local lastColorValue
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not trail.Parent then
			connection:Disconnect()
			return
		end
		trail.Enabled = humanoid.MoveDirection.Magnitude > 0.05

		local colorValue = player:GetAttribute("VIPTrailColor") or "Rainbow"
		if colorValue == "Rainbow" then
			local hue = (os.clock() % RAINBOW_CYCLE_SECONDS) / RAINBOW_CYCLE_SECONDS
			trail.Color = ColorSequence.new(Color3.fromHSV(hue, 0.85, 1))
			lastColorValue = "Rainbow"
		elseif colorValue ~= lastColorValue then
			trail.Color = ColorSequence.new(parseHexColor(colorValue) or DEFAULT_TRAIL_COLOR)
			lastColorValue = colorValue
		end
	end)
end

local function removeVIPEffects(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		restoreDefaultNameplate(humanoid)
	end

	local head = character:FindFirstChild("Head")
	local nameplate = head and head:FindFirstChild("VIPNameplate")
	if nameplate then
		nameplate:Destroy()
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		local trail = root:FindFirstChild("VIPFootTrail")
		if trail then
			trail:Destroy()
		end
		local attachment0 = root:FindFirstChild("VIPTrailAttachment0")
		if attachment0 then
			attachment0:Destroy()
		end
		local attachment1 = root:FindFirstChild("VIPTrailAttachment1")
		if attachment1 then
			attachment1:Destroy()
		end
	end
end

local function applyVIPEffects(player, character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	hideDefaultNameplate(humanoid)
	buildNameplate(character, player)
	buildFootTrail(character, player)
end

local function shouldShowVIPEffects(player)
	return player:GetAttribute("Perk_LeafPatron") == true and effectsEnabled(player)
end

-- Shared by both the initial CharacterAdded and the Perk_LeafPatron/VIPEffectsEnabled Attribute
-- listeners below -- whichever changes, the desired end state is the same "should this character
-- currently have the effects or not" check.
local function refreshVIPEffects(player)
	local character = player.Character
	if not character then
		return
	end
	if shouldShowVIPEffects(player) then
		task.spawn(applyVIPEffects, player, character)
	else
		removeVIPEffects(character)
	end
end

local function onPlayerAdded(player)
	player:GetAttributeChangedSignal("Perk_LeafPatron"):Connect(function()
		refreshVIPEffects(player)
	end)
	player:GetAttributeChangedSignal("VIPEffectsEnabled"):Connect(function()
		refreshVIPEffects(player)
	end)

	player.CharacterAdded:Connect(function()
		refreshVIPEffects(player)
	end)
	if player.Character then
		refreshVIPEffects(player)
	end
end

function VIPEffects.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, existingPlayer in ipairs(Players:GetPlayers()) do
		onPlayerAdded(existingPlayer)
	end
end

return VIPEffects
