local Players = game:GetService("Players")

-- This game has no jump-dependent mechanics, and Roblox's default touch jump button sits
-- bottom-right -- the same corner HotbarUI's tool slots live in -- so on mobile it visually
-- overlaps them. Simplest fix is hiding it outright rather than trying to reposition Roblox's own
-- TouchGui.
--
-- Fully event-driven (ChildAdded + Visible watchers) rather than a one-shot hide on startup: the
-- TouchGui/TouchControlFrame/JumpButton chain can be built (or rebuilt, or re-shown by Roblox's own
-- control scripts on respawn/control-scheme changes) at any point after this script starts, and a
-- single WaitForChild-then-hide would silently stop working the moment any of that happens again.
local MobileControls = {}

local function keepHidden(jumpButton)
	jumpButton.Visible = false
	jumpButton:GetPropertyChangedSignal("Visible"):Connect(function()
		if jumpButton.Visible then
			jumpButton.Visible = false
		end
	end)
end

local function watchTouchFrame(touchFrame)
	local jumpButton = touchFrame:FindFirstChild("JumpButton")
	if jumpButton then
		keepHidden(jumpButton)
	end
	touchFrame.ChildAdded:Connect(function(child)
		if child.Name == "JumpButton" then
			keepHidden(child)
		end
	end)
end

local function watchTouchGui(touchGui)
	local touchFrame = touchGui:FindFirstChild("TouchControlFrame")
	if touchFrame then
		watchTouchFrame(touchFrame)
	end
	touchGui.ChildAdded:Connect(function(child)
		if child.Name == "TouchControlFrame" then
			watchTouchFrame(child)
		end
	end)
end

function MobileControls.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local existingTouchGui = playerGui:FindFirstChild("TouchGui")
	if existingTouchGui then
		watchTouchGui(existingTouchGui)
	end
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "TouchGui" then
			watchTouchGui(child)
		end
	end)
end

return MobileControls
