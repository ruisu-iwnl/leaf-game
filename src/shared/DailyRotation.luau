local DailyQuestConfig = require(script.Parent.DailyQuestConfig)

-- Pure, deterministic "which 3 daily quests are active today" logic -- shared between
-- DailyQuestSystem.luau (server, the authoritative progress tracker) and QuestLogUI.luau (client,
-- just needs to know what to display) so both always agree without a remote round-trip: given the
-- same day number, both sides compute the exact same 3 ids independently.
local DailyRotation = {}

local ROTATION_SIZE = 3

-- Days since the Unix epoch. os.time() is UTC-based on both server and client regardless of local
-- timezone, so this can't disagree between them -- but it IS a single global reset point for every
-- player (UTC midnight), not each player's own local midnight. A known, deliberate simplification
-- for a small game -- a per-region reset isn't worth the complexity it'd add here.
function DailyRotation.GetCurrentDayNumber()
	return math.floor(os.time() / 86400)
end

-- Returns today's ROTATION_SIZE active daily quest ids, cycling through the WHOLE
-- DailyQuestConfig.Order list 3-at-a-time (wrapping around) as the day number advances -- so adding
-- a 13th (or 100th) quest to Order just extends the cycle length; nothing here needs to change.
function DailyRotation.GetTodaysDailyIds(dayNumber)
	dayNumber = dayNumber or DailyRotation.GetCurrentDayNumber()
	local order = DailyQuestConfig.Order
	local total = #order
	if total == 0 then
		return {}
	end

	local startIndex = (dayNumber * ROTATION_SIZE) % total
	local ids = {}
	for i = 0, ROTATION_SIZE - 1 do
		local index = (startIndex + i) % total + 1
		table.insert(ids, order[index])
	end
	return ids
end

-- Seconds remaining until the CURRENT rotation ends and the next day's 3 take over (i.e. until UTC
-- midnight for dayNumber+1) -- QuestLogUI.luau uses this to show a live "Xh Ym left" on each daily
-- row. Pure function of the same os.time()-based day number GetCurrentDayNumber already uses, so it
-- can't disagree with the rotation itself.
function DailyRotation.GetSecondsUntilNextRotation(dayNumber)
	dayNumber = dayNumber or DailyRotation.GetCurrentDayNumber()
	return math.max(0, (dayNumber + 1) * 86400 - os.time())
end

return DailyRotation
