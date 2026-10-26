-- Test init: used by the test runner and by every child Neovim a test starts.
-- Puts the plugin (the current directory) and mini.test on the runtimepath.

-- Only inside the sandbox `make test` makes: CDV_TEST_SANDBOX names its folder, and every XDG
-- folder sits inside it, so no case reads or writes the user's own. Anything else stops here,
-- before a file is touched.
local sandbox = vim.env.CDV_TEST_SANDBOX
local outside = sandbox == nil or sandbox == ""
for _, name in ipairs({ "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME" }) do
	local dir = vim.env[name]
	if outside or dir == nil or dir:sub(1, #sandbox + 1) ~= sandbox .. "/" then
		outside = true
	end
end
if outside then
	io.stderr:write("cavediver's tests run inside the sandbox `make test` makes (CDV_TEST_SANDBOX and the XDG folders in it): run them with make test.\n")
	vim.o.shadafile = "NONE"
	vim.cmd("cquit 2")
end

vim.cmd([[let &rtp.=','.getcwd()]])
vim.cmd('set rtp+=deps/mini.test')
require('mini.test').setup()
