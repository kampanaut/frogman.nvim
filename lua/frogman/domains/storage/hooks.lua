---Storage domain hooks for coordinating session persistence.
---
---This module contains hooks that extend other domains' state machines
---to trigger auto-save functionality when important state changes occur.

local routines = require('frogman.domains.storage.routines')
local states = require('frogman.domains.storage.states')
local storageSM = require('frogman.domains.storage.sm')

storageSM:on("{idle,bare}", states.SAVING, "save_history_pre_quit", function(context, _, _)
	-- Trigger auto-save when entering SAVING state
	routines.save_history(context.directory, context.name, context.tab)
end, 1, true)

-- the save is critical: if it fails (a full disk, a directory that can't be written), the error
-- reaches the session manager's hook, so the manager doesn't save either and both files stay in step.
storageSM:make_hook_critical("save_history_pre_quit")

storageSM:on("{bare,idle}", states.LOADING, "load_history_pre_start", function(context, _, _)
	-- Load history when entering LOADING state
	routines.load_history(context.directory, context.name)
end, 1, true)

storageSM:on("{bare,saving,loading}", "{idle,saving}", "back_to_idle", function(_, _, _) end, 1, true)


