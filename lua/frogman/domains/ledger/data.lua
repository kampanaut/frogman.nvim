---Ledger domain data structures for steps and moves.
---
---This module holds the steps frogman records and the moves it makes in them. The shapes of
---a step, a move and a row (FrogmanLedgerStep, FrogmanLedgerMove, FrogmanLedgerRow) are
---documented in configs.lua.
---
---@class LedgerData
---@field ring FrogmanLedgerStep[] The last steps kept, oldest first (at most `ledger.ring` of them)
---@field seq integer Number of the last step begun
---@field open FrogmanLedgerStep|nil The open step, where what follows from its trigger lands
---@field scopes FrogmanLedgerStep[] Steps that last only while a call runs, such as a timer's tick
---@field days table<string, FrogmanLedgerStep[]> Day → its steps with moves, oldest first (the trail)
---@field session string|nil The whole editor's session the steps are made under now (nil before the first)
---@field started number When this editor's ledger began, in seconds (older steps on a trail page came from earlier editors)
---@field epoch string This editor's mark, on every step it makes and on the trail pages with them: when its ledger began, and a few digits besides

return {
	ring = {},
	seq = 0,
	open = nil,
	scopes = {},
	days = {},
	session = nil,
	started = nil, -- set with the ledger's clock as the routines load
	epoch = nil, -- set with started
}
