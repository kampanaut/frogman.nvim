-- Test init: used by the test runner and by every child Neovim a test starts.
-- Puts the plugin (the current directory) and mini.test on the runtimepath.
vim.cmd([[let &rtp.=','.getcwd()]])
vim.cmd('set rtp+=deps/mini.test')
require('mini.test').setup()
