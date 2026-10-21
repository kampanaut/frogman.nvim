-- Q13 check for C1 [sim]: both of c's notes set to its secondary by hand; the restore must still throw.
dofile(os.getenv("CDV_SPEC") .. "/t/rt_fmt.lua")
local h = function(f) return H.get_hash_from_buffer(vim.fn.bufnr(f .. ".txt")) end
ROW(":e a", E"a") ROW(":e b", E"b") ROW(":e c", E"c")
ROW("<M-f>  (b graduates)", F)
ROW("[sim] set dsm c-swap>b and c>b", function()
	local t = W.data.crux[vim.api.nvim_get_current_win()]
	t.displacement_secondary_map[h"c" .. "-swap"] = h"b"
	t.displacement_secondary_map[h"c"] = h"b"
end)
ROW("<M-;><M-t>  (on c)", RS)
ROWS_DONE()
