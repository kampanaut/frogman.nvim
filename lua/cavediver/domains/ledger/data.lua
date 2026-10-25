---Ledger domain data structures for steps and moves.
---
---This module holds the steps cavediver records and the moves it makes in them. The shapes of
---a step, a move and a row (CavediverLedgerStep, CavediverLedgerMove, CavediverLedgerRow) are
---documented in configs.lua.
---
---@class LedgerData
---@field ring CavediverLedgerStep[] The last steps kept, oldest first (at most `ledger.ring` of them)
---@field seq integer Number of the last step begun
---@field open CavediverLedgerStep|nil The open step, where what follows from its trigger lands
---@field scopes CavediverLedgerStep[] Steps that last only while a call runs, such as a timer's tick
---@field days table<string, CavediverLedgerStep[]> Day → its steps with moves, oldest first (the trail)
---@field session string|nil The whole editor's session the steps are made under now (nil before the first)
---@field started number When this editor's ledger began, in seconds (older steps on a trail page came from earlier editors)

return {
	ring = {},
	seq = 0,
	open = nil,
	scopes = {},
	days = {},
	session = nil,
	started = (function()
		local seconds, microseconds = vim.uv.gettimeofday()
		return seconds + microseconds / 1e6
	end)(),
}
