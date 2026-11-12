---What setup() leaves for the rest of frogman to read: whether frogman is on, and the keys it mapped
---in normal mode, with what each one held before setup() took it.
---
---setup() and disable() are its only writers. The health check reads it.

local M = {}

---Whether frogman is on: nil until setup() first runs, true after it, false after disable().
---@type boolean|nil
M.on = nil

---Frogman's own mappings: each key as the config spells it, and the function mapped to it, so the
---next setup() takes off those that are still frogman's.
---@type table<string, function>
M.mapped = {}

---What each key held before setup() took it, by the key as the config spells it. A key frogman
---still holds keeps what it took at the first setup() that mapped it.
---@type table<string, string>
M.took = {}

---Each key the last setup() mapped, in the order it mapped them, with what it does and, for a main
---key, its name in the config; a marks' key has none.
---@type {lhs: string, desc: string, name: string|nil}[]
M.keys = {}

---Get the normal mode mapping a key has outside any buffer.
---
---Read from the global mappings, since a buffer's own mapping of the same key stands in front of it
---in `maparg()`.
---
---@param lhs string The key, as a mapping spells it
---@return table|nil mapping The mapping, as `nvim_get_keymap()` gives it, or nil when there's none
function M.global_mapping(lhs)
	local code = vim.keycode(lhs)
	for _, mapping in ipairs(vim.api.nvim_get_keymap('n')) do
		if mapping.lhsraw == code or mapping.lhsrawalt == code then
			return mapping
		end
	end
end

---Say what a mapping does, for a message: its description, or else what it runs.
---
---@param mapping table A mapping, as `nvim_get_keymap()` gives it
---@return string what Its description, its right-hand side, or "a Lua function"
function M.describe(mapping)
	if type(mapping.desc) == "string" and mapping.desc ~= "" then
		return mapping.desc
	end
	if type(mapping.rhs) == "string" and mapping.rhs ~= "" then
		return mapping.rhs
	end
	return "a Lua function"
end

return M
