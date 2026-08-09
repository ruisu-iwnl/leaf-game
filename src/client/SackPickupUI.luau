local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Hides the "Pick Up" ProximityPrompt on every physical Leaf Sack while the local player already
-- has one equipped -- purely a local visual toggle (ProximityPrompt.Enabled set from a client
-- script only affects that client's own view of it), so it doesn't interfere with other players
-- seeing/using the same prompt.
local SackPickupUI = {}

local SACK_TOOL_NAME = "LeafSack"

function SackPickupUI.Start()
	local player = Players.LocalPlayer
	local trackedPrompts = {}

	local function onDescendantAdded(descendant)
		if descendant:IsA("ProximityPrompt") then
			local handle = descendant.Parent
			local tool = handle and handle.Parent
			if tool and tool:IsA("Tool") and tool.Name == SACK_TOOL_NAME then
				trackedPrompts[descendant] = true
			end
		end
	end

	Workspace.DescendantAdded:Connect(onDescendantAdded)
	Workspace.DescendantRemoving:Connect(function(descendant)
		trackedPrompts[descendant] = nil
	end)
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		onDescendantAdded(descendant)
	end

	-- Polled rather than event-driven off equip/unequip signals -- this project has repeatedly hit
	-- unreliable Tool-equip events (see BlowerTool.luau/OverheatUI.luau), so this checks fresh every
	-- frame instead of trusting a ChildAdded/AncestryChanged callback to always fire.
	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local hasSackEquipped = character ~= nil and character:FindFirstChild(SACK_TOOL_NAME) ~= nil

		for prompt in pairs(trackedPrompts) do
			if prompt.Parent then
				prompt.Enabled = not hasSackEquipped
			else
				trackedPrompts[prompt] = nil
			end
		end
	end)
end

return SackPickupUI
