---Ledger domain data: the steps cavediver records, and the moves it makes in them. The shapes,
---CavediverLedgerStep, CavediverLedgerMove and CavediverLedgerRow, are documented in configs.lua.
---
---@class LedgerData
---@field ring CavediverLedgerStep[] The last steps kept, oldest first, at most `ledger.ring` of them
---@field seq integer The number of the last step begun
---@field open CavediverLedgerStep|nil The step still open: what follows from its trigger lands on it
---@field scopes CavediverLedgerStep[] Steps that last only while a call runs, a timer's tick
---@field days table<string, CavediverLedgerStep[]> The trail: each day's steps that made moves, oldest first
---@field started number When this editor's ledger began, in seconds: a page keeps what editors before it wrote

return {
	ring = {},
	seq = 0,
	open = nil,
	scopes = {},
	days = {},
	started = (function()
		local seconds, microseconds = vim.uv.gettimeofday()
		return seconds + microseconds / 1e6
	end)(),
}
