-- Options for MiniTest.run(). Which cases run is picked by tag, through CDV_TAGS:
--   char   - intended behaviour that holds today
--   today  - today's behaviour, expected to flip when its fix lands
--   target - decided behaviour, expected to fail until its fix lands
-- A case's tag is the "[char]" / "[today]" / "[target]" in its name.
-- CDV_TAGS defaults to "char,today"; `make test-target` sets it to "target".
-- CDV_FILE, when set, runs only that test file.
local wanted = {}
for tag in (os.getenv('CDV_TAGS') or 'char,today'):gmatch('[^,]+') do
	wanted[vim.trim(tag)] = true
end

local function tag_of(case)
	for _, d in ipairs(case.desc) do
		local tag = tostring(d):match('%[(%a+)%]')
		if tag == 'char' or tag == 'today' or tag == 'target' then
			return tag
		end
	end
	return 'char'
end

local file = os.getenv('CDV_FILE')

return {
	collect = {
		find_files = function()
			if file and file ~= '' then
				return { file }
			end
			return vim.fn.globpath('tests', '**/test_*.lua', true, true)
		end,
		filter_cases = function(case)
			return wanted[tag_of(case)] == true
		end,
	},
}
