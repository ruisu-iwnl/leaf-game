local TweenService = game:GetService("TweenService")

-- Shared open/close pop-and-fade + button press feedback for every custom modal in this game
-- (Settings, Inventory, the store dialogue, and anything built after) -- one place to tune the
-- feel so the whole game reads as one consistent system instead of each panel inventing its own
-- timing/easing, and so a future panel gets the same polish for free instead of needing it
-- hand-rolled again.
--
-- Scale (not Size) is what actually pops the whole panel -- a UIScale tweened on the panel itself
-- scales every descendant uniformly around the panel's anchor point, with no layout reflow. This
-- project has already burned time on CanvasGroup being unreliable for "fade the whole subtree at
-- once" (see OverheatUI.luau's comment on why it avoids CanvasGroup) -- UIScale doesn't have that
-- problem, it's a much older/simpler primitive, so that's the one used here.
local PanelMotion = {}

local OPEN_TWEEN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PRESS_TWEEN_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_TWEEN_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local POP_START_SCALE = 0.85
local PRESS_SHRINK_RATIO = 0.92

-- Builds a Show()/Hide() controller for one backdrop+panel pair. `restingPanelTransparency` and
-- `restingBackdropTransparency` are whatever those two already sit at normally (read once, up
-- front, since some panels use a semi-transparent background) -- Show()/Hide() animate to/from
-- those instead of assuming fully opaque.
function PanelMotion.new(panel, backdrop)
	local restingPanelTransparency = panel.BackgroundTransparency
	local restingBackdropTransparency = backdrop.BackgroundTransparency

	local scale = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = panel

	local controller = {}
	local currentTweens = {}

	local function play(instance, tweenInfo, goal)
		local tween = TweenService:Create(instance, tweenInfo, goal)
		currentTweens[instance] = tween
		tween:Play()
		return tween
	end

	function controller.Show()
		for instance, tween in pairs(currentTweens) do
			tween:Cancel()
			currentTweens[instance] = nil
		end

		backdrop.Visible = true
		backdrop.BackgroundTransparency = 1
		scale.Scale = POP_START_SCALE
		panel.BackgroundTransparency = 1

		play(backdrop, OPEN_TWEEN_INFO, { BackgroundTransparency = restingBackdropTransparency })
		play(scale, OPEN_TWEEN_INFO, { Scale = 1 })
		play(panel, OPEN_TWEEN_INFO, { BackgroundTransparency = restingPanelTransparency })
	end

	function controller.Hide()
		for instance, tween in pairs(currentTweens) do
			tween:Cancel()
			currentTweens[instance] = nil
		end

		play(backdrop, CLOSE_TWEEN_INFO, { BackgroundTransparency = 1 })
		play(scale, CLOSE_TWEEN_INFO, { Scale = POP_START_SCALE })
		local fadeOut = play(panel, CLOSE_TWEEN_INFO, { BackgroundTransparency = 1 })

		local thisFadeOut = fadeOut
		fadeOut.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed and currentTweens[panel] == thisFadeOut then
				backdrop.Visible = false
			end
		end)
	end

	return controller
end

-- Wires a consistent press-down/release bounce onto any GuiButton -- shrinks slightly the instant
-- it's pressed, pops back with a little overshoot on release, so every clickable thing feels the
-- same. Reads the button's Size fresh on each press (rather than capturing it once up front) so
-- this stays correct even for buttons something else resizes later (e.g. a card that pops in at a
-- different size before ever being pressed).
function PanelMotion.AnimateButton(button)
	button.MouseButton1Down:Connect(function()
		local restingSize = button.Size
		local pressedSize = UDim2.new(
			restingSize.X.Scale, restingSize.X.Offset * PRESS_SHRINK_RATIO,
			restingSize.Y.Scale, restingSize.Y.Offset * PRESS_SHRINK_RATIO
		)
		TweenService:Create(button, PRESS_TWEEN_INFO, { Size = pressedSize }):Play()

		local function release()
			TweenService:Create(button, RELEASE_TWEEN_INFO, { Size = restingSize }):Play()
		end
		button.MouseButton1Up:Once(release)
		button.MouseLeave:Once(release)
	end)
end

return PanelMotion
