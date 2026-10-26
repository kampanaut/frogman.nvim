---Storage domain state machine creation and configuration.
---
---This module creates and configures the storage state machine with all
---necessary states and transitions for session persistence operations.
local storageSM

storageSM = require('frogman.engine'):get('storage')

if storageSM ~= nil then
	return storageSM
end

storageSM = require('frogman.engine'):create('storage')

local engine = require('frogman.engine')
local states = require('frogman.domains.storage.states')



-- Register all storage states
storageSM:register_state(states.BARE)
storageSM:register_state(states.IDLE)
storageSM:register_state(states.SAVING)
storageSM:register_state(states.LOADING)
storageSM:register_state(states.ERROR)
storageSM:register_state(states.AUTO_SAVING)

-- Set initial state
storageSM.current_state = states.BARE

return storageSM
