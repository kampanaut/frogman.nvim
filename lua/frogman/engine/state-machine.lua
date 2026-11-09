local helper = require('frogman.engine.helpers')

---State machine implementation for managing states, transitions, and hooks.
---
---This class provides a complete state machine system with:
---- State registration and validation
---- Transition control with wildcard support
---- Hook system for transition callbacks
---- General hooks for all transitions
---- Transition history tracking
---
---@class StateMachine
---@field name string The name of the StateMachine
---@field current_state stateName The current active state
---@field states stateRegistry Registry of registered states with enable/disable status
---@field transitions transitionRegistry Registry of transitions with enable/disable status
---@field bindings transitionBindingsRegistry Maps transition patterns to hook arrays
---@field hooks tHooksRegistry Registry of all transition-specific hooks by name
---@field general_hooks gHooksRegistry Array of hooks that run on all transitions
---@field history transitionName[] History of executed transitions
---@field members table<stateName, table<iStateMachine, true>> The instances in each state, the machine's own included, kept weakly
---@field labeler (fun(instance: iStateMachine): string)|nil Names an instance in messages
---@field own {transitions: table<transitionName, false>, hooks: table<string, false>} The built-in instance's own switches
---@field pending table[] Transitions asked for inside the running one's hooks, waiting for it to finish
---@field running transitionName|nil The transition the machine is in the middle of
---@field depth integer How deep the running transition is in transitions asked for inside hooks
local StateMachine = {
	-- The starting state of the StateMachine
	---@type stateName
	current_state = "",

	-- We record the states to validate upcoming transitions
	-- `["<state>"] = true | false.`
	-- `true` if it is turned on, `false` otherwise.
	---@type stateRegistry
	states = {},

	-- the transitions are written with `<previous>-><next>`
	-- `["<transition>"] = true | false`
	-- `true` if it is turned on, `false` otherwise.
	---@type transitionRegistry
	transitions = {},

	-- (transitionPattern <-> tHook) pair.
	-- ```lua
	-- ["<previous>-><next>"] = {
	--	{
	--     class = 2,
	--     enabled = true,
	--     name = "some_hook",
	--     function = function()...end
	--	},
	-- },
	-- ["*->tracking"] = {
	--	{
	--     class = 1,
	--     enabled = true,
	--     name = "some_hook_2",
	--     function = function()...end
	--	},
	-- },
	-- ["tracking->*"] = {
	--	{
	--     class = 2,
	--     enabled = true,
	--     name = "some_hook_4",
	--     function = function()...end
	--	},
	--	{...}
	-- },
	-- ```
	-- Can support wildcards as well, e.g. `*->tracking` or `tracking->*`
	---@type transitionBindingsRegistry
	bindings = {},

	-- ```lua
	-- {
	--	["<name1>"] = {
	--		class = 2,
	--		enabled = true,
	--		name = "<name1>",
	--		function = function()...end
	--	},
	--	["<name2>"] = {
	--		class = 1,
	--		enabled = true,
	--		name = "<name2>",
	--		function = function()...end
	--	}
	-- }
	-- ```
	-- Registry of all transition-specific hooks.
	---@type tHooksRegistry
	hooks = {},

	-- ```lua
	-- {
	--	{
	--		class = 4,
	--		enabled = true,
	--		name = "general_hook",
	--		function = function()...and
	--	}
	-- }
	-- ```
	-- Just like `StateMachine.hooks` but goes for all transitions.
	-- Formally it's for transition pattern like this, `*->*`. It executes before or after the
	-- the normal hooks.
	---@type gHooksRegistry
	general_hooks = {},

	-- The history of `transitions`.
	---@type transitionName[]
	history = {},

	-- The transition modes: one table shared by every machine, on purpose, so a hook may name a mode
	-- another machine registered.
	---@type table<transitionMode, boolean>
	transition_modes = {}
}

---A machine instance: a current state, a history and switches of its own, moved by its model.
---
---A machine made by the factory is a model with one built-in instance, the machine itself. A model
---makes more with `instantiate`, each sharing its states, transitions and hooks.
---
---@class iStateMachine
---@field model mStateMachine The model that moves this instance
---@field current_state stateName The instance's current state
---@field history string[] The transitions the instance made, a nested one with its parent after it
---@field own {transitions: table<transitionName, false>, hooks: table<string, false>} The instance's own switches
---@field pending table[] Transitions asked for inside the running one's hooks, waiting for it to finish
---@field running transitionName|nil The transition the instance is in the middle of
---@field depth integer How deep the running transition is in transitions asked for inside hooks
---@field unregistered boolean|nil Whether the instance was unregistered

---A machine model: the states, transitions, hooks and switches its instances share.
---
---@class mStateMachine: StateMachine
---@field members table<stateName, table<iStateMachine, true>> The instances in each state, kept weakly
---@field labeler (fun(instance: iStateMachine): string)|nil Names an instance in messages

---How deep transitions asked for inside hooks may go before it's taken for a loop.
local MAX_DEPTH = 16

local MachineInstance = {}
local instance_mt = { __index = MachineInstance }

---Make an empty set of instances, which doesn't keep them alive.
---@return table<iStateMachine, true> set
local function weak_set()
	return setmetatable({}, { __mode = "k" })
end

local label_of = helper.label_of

---Move an instance to a state, keeping its model's sets of who's in each state.
---@param model StateMachine|mStateMachine The model keeping the sets of who's in each state
---@param instance iStateMachine|StateMachine The instance to move
---@param state stateName The state to move it to
---@return nil
local function place(model, instance, state)
	local before = model.members[instance.current_state]
	if before then
		before[instance] = nil
	end
	model.members[state] = model.members[state] or weak_set()
	model.members[state][instance] = true
	instance.current_state = state
end

---Run a transition on an instance of a model.
---
---A transition asked for inside the running one's hooks waits, and runs once it's done, from the
---state it ended in, its history entry naming the one it was asked for in. When the running
---transition is abandoned, what it asked for goes with it, and when an asked one fails, so do the
---ones asked after it.
---
---@param model StateMachine|mStateMachine The model whose transitions and hooks run
---@param instance iStateMachine|StateMachine The instance being moved
---@param next_state stateName The state to transition to
---@param context_arg transitionContextArg? Optional mutable data passed to all hooks. `caller` is reserved.
---@param mode transitionMode? The mode whose hooks run besides the "*" ones, nil for none
---@param parent transitionName? The transition it was asked for in
---@param depth integer? How deep it is in transitions asked for inside hooks
---@return nil
local function transition(model, instance, next_state, context_arg, mode, parent, depth)
	helper.validate_state_name_param(next_state, "next_state")
	helper.validate_param(context_arg, "context", "table", true)
	helper.validate_mode_pattern(mode, model)
	if instance.unregistered then
		error("Cannot transition " .. label_of(model, instance) .. ": its instance is unregistered", 3)
	end
	if not model:is_state_registered(next_state) then
		error("Cannot transition to unregistered state: " .. next_state, 3) -- the caller's line
	end
	if instance.running then
		-- inside its own hooks: it runs once the running transition is done
		table.insert(instance.pending, {
			next_state = next_state, context = context_arg, mode = mode,
			parent = instance.running, depth = instance.depth + 1,
		})
		return
	end
	depth = depth or 0
	if depth > MAX_DEPTH then
		instance.pending = {}
		error("Transitions asked for inside hooks went past a depth of " .. MAX_DEPTH .. ", at " .. parent ..
			" of " .. label_of(model, instance))
	end

	local context = vim.deepcopy(context_arg or {})
	---@cast context transitionContext
	context.caller = model.name
	context.mode = mode or "*" -- this is not run all hooks, but only run hooks that aren't registered with a mode.

	local from_state = instance.current_state
	---@type transitionName
	local transition_name = from_state .. "->" .. next_state
	-- Check if transition is enabled
	if model.transitions[transition_name] == nil then
		error("Transition '" .. transition_name .. "' is not registered")
	end
	if model.transitions[transition_name] == false or instance.own.transitions[transition_name] == false then
		error("Transition '" .. transition_name .. "' is disabled")
	end

	instance.running, instance.depth = transition_name, depth
	local entry = parent and (transition_name .. " <- " .. parent) or transition_name
	local ok, err = pcall(helper.execute_transition, from_state, next_state, context.mode, context, model, instance, entry)
	instance.running = nil
	if not ok then
		instance.pending = {}
		error(err, 0)
	end
	if instance.unregistered then
		-- unregistered inside its own hooks: it stays out of its model's sets, and what it asked for goes
		instance.pending = {}
		return
	end
	place(model, instance, next_state)

	while #instance.pending > 0 do
		local asked = table.remove(instance.pending, 1)
		local done, failed = pcall(transition, model, instance, asked.next_state, asked.context, asked.mode,
			asked.parent, asked.depth)
		if not done then
			-- a nested ask that fails drops the asks queued after it, so none runs in a later, unrelated to()
			instance.pending = {}
			error(failed, 0)
		end
	end
end

---Set an instance's state with no transition run, recorded in its history as forced.
---@param model StateMachine|mStateMachine The model whose sets of who's in each state it keeps
---@param instance iStateMachine|StateMachine The instance being set
---@param state stateName A registered state
---@return nil
local function force(model, instance, state)
	helper.validate_state_name_param(state, "state")
	if not model:is_state_registered(state) then
		error("Cannot force an unregistered state: " .. state, 3)
	end
	-- a machine the factory makes starts on an empty table, no state, so its first entry names none
	local from = type(instance.current_state) == "string" and instance.current_state or ""
	table.insert(instance.history, from .. "->" .. state .. " (forced)")
	place(model, instance, state)
end

---Switch one of an instance's own transitions off, or back to its model's.
---@param model StateMachine|mStateMachine The instance's model, whose transitions the pattern names
---@param instance iStateMachine|StateMachine The instance whose own switches change
---@param from_state stateName Source state (supports wildcards "*")
---@param to_state stateName Destination state (supports wildcards "*")
---@param off boolean Whether to switch it off
---@return nil
local function switch_own_transitions(model, instance, from_state, to_state, off)
	for _, transition_name in ipairs(helper.parse_transition_pattern(from_state .. "->" .. to_state, model)) do
		if off then
			instance.own.transitions[transition_name] = false
		else
			instance.own.transitions[transition_name] = nil
		end
	end
end

---Get the instance's current state.
---@return stateName current_state The name of the instance's current state
function MachineInstance:state()
	return self.current_state
end

---Transition the instance to a new state, running its model's hooks.
---@param next_state stateName The state to transition to
---@param context_arg transitionContextArg? Optional mutable data passed to all hooks. `caller` is reserved.
---@param mode transitionMode? The mode whose hooks run besides the "*" ones, nil for none
---@return nil
function MachineInstance:to(next_state, context_arg, mode)
	transition(self.model, self, next_state, context_arg, mode)
end

---Set the instance's state with no transition run.
---
---The hooks don't run, and the history records the move as forced. It's for putting a state in
---place, as a teardown or a replay does, never for moving through one.
---
---@param state stateName A registered state
---@return nil
function MachineInstance:force_state(state)
	force(self.model, self, state)
end

---Unregister the instance from its model.
---
---It leaves its model's sets of who's in each state, and its history goes. A transition asked of it
---afterwards is an error.
---
---@return nil
function MachineInstance:unregister()
	local members = self.model.members[self.current_state]
	if members then
		members[self] = nil
	end
	self.history = {}
	self.unregistered = true
end

---Switch transitions off for this instance alone.
---@param from_state stateName Source state (supports wildcards "*")
---@param to_state stateName Destination state (supports wildcards "*")
---@return nil
function MachineInstance:disable_transition(from_state, to_state)
	switch_own_transitions(self.model, self, from_state, to_state, true)
end

---Give this instance its model's transitions back, where it switched them off.
---@param from_state stateName Source state (supports wildcards "*")
---@param to_state stateName Destination state (supports wildcards "*")
---@return nil
function MachineInstance:enable_transition(from_state, to_state)
	switch_own_transitions(self.model, self, from_state, to_state, false)
end

---Switch a hook off for this instance alone.
---@param name string Name of the hook
---@return nil
function MachineInstance:disable_hook(name)
	self.own.hooks[name] = false
end

---Give this instance its model's hook back, where it switched it off.
---@param name string Name of the hook
---@return nil
function MachineInstance:enable_hook(name)
	self.own.hooks[name] = nil
end


---Get the current active state.
---@return stateName current_state The name of the currently active state
function StateMachine:state()
	return self.current_state
end

---Register a new state in the state machine.
---
---States must be registered before they can be used in transitions.
---State names cannot be "*" (reserved for wildcards) or contain "->" (reserved for transitions).
---
---@param state_name stateName The name of the state to register
---@return nil
function StateMachine:register_state(state_name)
	helper.validate_state_name_param(state_name, "state_name")
	if self:is_state_name_valid(state_name) then
		if self.states[state_name] then
			error("State '" .. state_name .. "' is already registered")
		end
		self.states[state_name] = true
	end
end

---Register a new mode for transitions. Modes are optional tags that can be used to filter hooks.
---By default there are no modes, but you can register any number of them at any time as well, since
---hooks store by string patterns. But make sure those pattern contain only registered modes.
---@param mode transitionMode The name of the mode to register
---@return nil
function StateMachine:register_mode(mode)
	self.transition_modes[mode] = true
end

---Unregister a state and cascade delete all related transitions.
---
---Removes the state and automatically cleans up all transitions and bindings
---that reference this state (both as source and destination). It refuses while
---an instance is in the state.
---
---@param state_name stateName The name of the existing state to remove
---@return nil
function StateMachine:unregister_state(state_name)
	helper.validate_state_name_param(state_name, "state_name")
	-- an instance still in it would be left in a state nothing knows: making sure none is is the caller's job
	if self.members and self.members[state_name] and next(self.members[state_name]) ~= nil then
		error("Cannot unregister state '" .. state_name .. "': instances are in it", 2) -- the caller's line
	end
	if self.states[state_name] then
		for transition_name, _ in pairs(self.transitions) do
			local previous, next = helper.parse_transition_name(transition_name)

			if previous == state_name then
				self.transitions[transition_name] = nil
			elseif next == state_name then
				self.transitions[transition_name] = nil
			end
		end

		for transition_pattern, _ in pairs(self.bindings) do
			local previous, next = helper.parse_transition_name(transition_pattern)

			if previous == state_name then
				self.bindings[transition_pattern] = nil
			elseif next == state_name then
				self.bindings[transition_pattern] = nil
			end
		end

		self.states[state_name] = nil
	end
end

---Validate if a state name follows the required naming rules.
---
---State names must not be "*" (reserved for wildcards) and cannot contain "->"
---(reserved for transition delimiter). This is called internally during state registration.
---
---@param state_name stateName The name of the state to validate
---@return true is_valid Always returns true if validation passes, otherwise throws error
function StateMachine:is_state_name_valid(state_name)
	helper.validate_state_name_param(state_name, "state_name")
	if state_name == "*" then
		error("Cannot register \"*\" as a state name — reserved for wildcards")
	end
	if string.find(state_name, "->") then
		error("State name cannot contain '->' - reserved for transition delimiter")
	end
	return true
end

---Check if a state is registered in the state machine.
---
---Returns true if the state has been registered using register_state(),
---regardless of whether it's currently enabled or disabled.
---
---@param state_name stateName The name of the state to check
---@return boolean is_registered True if the state is registered, false otherwise
function StateMachine:is_state_registered(state_name)
	helper.validate_state_name_param(state_name, "state_name")
	if self.states[state_name] == nil then
		return false
	else
		return true
	end
end

---Check if a state is currently enabled.
---
---States can be enabled or disabled after registration. Only enabled states
---can be used as destinations in transitions. This checks both registration
---and enabled status.
---
---@param state_name stateName The name of the state to check
---@return boolean is_enabled True if the state is registered and enabled, false otherwise
function StateMachine:is_state_enabled(state_name)
	helper.validate_state_name_param(state_name, "state_name")
	if not (self.states[state_name] ~= nil and self:is_state_name_valid(state_name)) then
		return false
	else
		return self.states[state_name] == true
	end
end

---Register a hook to execute during state transitions.
---
---Hooks are functions that execute when transitioning between states. If the transition
---doesn't exist, it will be created automatically (if both states are registered).
---Hook names must be unique across the state machine.
---
---@param from_state stateName Source state for the transition (supports wildcards "*")
---@param to_state stateName Destination state for the transition (supports wildcards "*")
---@param name string Unique name for this hook
---@param func hookFunction? Hook function to execute (required for new hooks)
---@param priority number? Priority class for execution order, lower = higher priority (required for new hooks)
---@param enabled boolean? Whether the hook is initially enabled (required for new hooks)
---@param mode_filter transitionModePattern? Optional pattern to filter which modes this hook applies to
---@return boolean success True if hook was registered successfully
function StateMachine:on(from_state, to_state, name, func, priority, enabled, mode_filter)
	-- Validate required parameters
	helper.validate_state_name_param(from_state, "from_state")
	helper.validate_state_name_param(to_state, "to_state")
	helper.validate_param(name, "name", "string", false)
	if name == "" then
		error("Parameter 'name' cannot be empty string")
	end
	-- Validate optional parameters
	helper.validate_param(func, "func", "function", true)
	helper.validate_param(priority, "priority", "number", true)
	helper.validate_param(enabled, "enabled", "boolean", true)
	helper.validate_mode_pattern(mode_filter, self)
	if priority and type(priority) ~= "number" then
		error("Parameter 'priority' must be a number, got " .. type(priority))
	end

	---@type transitionPattern
	local transition_pattern = from_state .. "->" .. to_state

	---@type transitionName[]
	local transition_names = helper.parse_transition_pattern(transition_pattern, self)

	---@type tHook
	local hook
	if self.hooks[name] then
		hook = self.hooks[name]
		if priority then
			hook.class = priority
		end
		if enabled ~= nil then
			hook.enabled = enabled
		end
		if func then
			hook.func = func
		end
		if mode_filter then
			hook.mode_filter = mode_filter
		else
			hook.mode_filter = "*"
		end
	else
		-- For new hooks, all parameters are required
		if not (func and priority and enabled ~= nil) then
			error("For new hooks, 'func', 'priority', 'enabled', and 'mode_filter' parameters are required")
		end

		mode_filter = mode_filter or "*"
		hook = {
			name = name,
			class = priority,
			enabled = enabled,
			func = func,
			mode_filter = mode_filter
		}
	end

	-- loop over the transition names and assign the hook
	for _, transition_name in ipairs(transition_names) do
		from_state, to_state = helper.parse_transition_name(transition_name)
		if self.transitions[transition_name] == nil then
			if
				self:is_state_name_valid(from_state) and self:is_state_name_valid(to_state) and
				self:is_state_registered(from_state) and self:is_state_registered(to_state)
			then
				self.transitions[transition_name] = true
			else
				error("Cannot register hook for invalid transition state endpoints: " .. transition_name)
			end
		end

		if self.bindings[transition_name] == nil then
			self.bindings[transition_name] = {}
		end

		if not vim.tbl_contains(self.bindings[transition_name], hook) then
			table.insert(self.bindings[transition_name], hook)
		end
	end

	if self.hooks[hook.name] == nil then
		self.hooks[hook.name] = hook
	end
	return true
end

---Remove a hook from specific transitions.
---
---Removes the hook from the specified transition pattern but keeps the hook
---registered in the state machine. The hook can still be attached to other transitions.
---Use unregister_hook() to completely remove a hook from the state machine.
---
---@param from_state stateName Source state for the transition (supports wildcards "*")
---@param to_state stateName Destination state for the transition (supports wildcards "*")
---@param name string Name of the hook to remove from these transitions
---@return nil
function StateMachine:off(from_state, to_state, name)
	if self.hooks[name] == nil then
		error("Cannot remove hook with name '" .. name .. "': not found", 2) -- the caller's line
	end

	---@type transitionPattern
	local transition_pattern = from_state .. "->" .. to_state

	---@type transitionName[]
	local transition_names = helper.parse_transition_pattern(transition_pattern, self)

	-- we are going to loop over the transition_names, and and remove the hooks that has name same as the argument name.
	for _, transition_name in ipairs(transition_names) do
		if self.bindings[transition_name] == nil then
			goto continue
		end

		-- backwards, so a removal doesn't skip the hook after it
		local bound = self.bindings[transition_name]
		for i = #bound, 1, -1 do
			if bound[i].name == name then
				table.remove(bound, i)
			end
		end

		::continue::
	end
end

---Completely remove a hook from the state machine.
---
---Removes the hook from all transitions and unregisters it from the state machine.
---After calling this method, the hook name becomes available for reuse.
---This is equivalent to calling off("*", "*", hook_name) and then removing the hook registration.
---
---@param hook_name string Name of the hook to completely remove
---@return nil
function StateMachine:unregister_hook(hook_name)
	if self.hooks[hook_name] == nil then
		error("hook '" .. hook_name .. "' is not registered")
	end

	self:off("*", "*", hook_name)

	self.hooks[hook_name] = nil
end

---Enable a hook to execute during transitions.
---
---Enables a previously registered hook that may have been disabled.
---The hook will start executing during its registered transitions.
---
---@param name string Name of the hook to enable
---@return nil
function StateMachine:enable_hook(name)
	helper.validate_param(name, "name", "string", false)
	if self.hooks[name] == nil then
		error("Cannot enable hook: '" .. name .. "': not found", 2) -- the caller's line
	end

	self.hooks[name].enabled = true
end

---Make a hook critical, so its failure reaches the caller.
---
---A critical hook's error isn't caught and notified as other hooks' errors are. The transition
---is abandoned, the machine stays in the state it was in, and the error reaches whoever called
---`to()`.
---
---@param name string Name of the hook to make critical
---@return nil
function StateMachine:make_hook_critical(name)
	helper.validate_param(name, "name", "string", false)
	if self.hooks[name] == nil then
		error("Cannot make hook critical: '" .. name .. "': not found", 2) -- the caller's line
	end

	self.hooks[name].critical = true
end

---Disable a hook from executing during transitions.
---
---Disables a previously registered hook without removing it from the state machine.
---The hook will stop executing but remains registered and can be re-enabled later.
---
---@param name string Name of the hook to disable
---@return nil
function StateMachine:disable_hook(name)
	helper.validate_param(name, "name", "string", false)
	if self.hooks[name] == nil then
		error("Cannot disable hook: '" .. name .. "': not found", 2) -- the caller's line
	end

	self.hooks[name].enabled = false
end

---Enable transitions to allow state changes.
---
---Enables previously registered transitions that may have been disabled.
---Supports wildcards for enabling multiple transitions at once.
---Only enabled transitions can be executed via the to() method.
---
---@param from_state stateName Source state for transitions to enable (supports wildcards "*")
---@param to_state stateName Destination state for transitions to enable (supports wildcards "*")
---@return nil
function StateMachine:enable_transition(from_state, to_state)
	---@type transitionPattern
	local transition_pattern = from_state .. "->" .. to_state

	---@type transitionName[]
	local transition_names = helper.parse_transition_pattern(transition_pattern, self)

	for _, transition_name in ipairs(transition_names) do
		if self.transitions[transition_name] ~= nil then
			self.transitions[transition_name] = true
		end
	end
end

---Disable transitions to prevent state changes.
---
---Disables previously registered transitions without removing them.
---Supports wildcards for disabling multiple transitions at once.
---Disabled transitions cannot be executed via the to() method.
---
---@param from_state stateName Source state for transitions to disable (supports wildcards "*")
---@param to_state stateName Destination state for transitions to disable (supports wildcards "*")
---@return nil
function StateMachine:disable_transition(from_state, to_state)
	---@type transitionPattern
	local transition_pattern = from_state .. "->" .. to_state

	---@type transitionName[]
	local transition_names = helper.parse_transition_pattern(transition_pattern, self)

	for _, transition_name in ipairs(transition_names) do
		if self.transitions[transition_name] then
			self.transitions[transition_name] = false
		end
	end
end

---Transition the state machine to a new state.
---
---Executes all registered hooks for the transition in priority order.
---The transition must be registered and enabled. Context data is passed
---through all hooks in the execution pipeline.
---
---@param next_state stateName The state to transition to
---@param context_arg transitionContextArg? Optional mutable data passed to all hooks. `caller` is reserved.
---@param mode transitionMode?
---@return nil
function StateMachine:to(next_state, context_arg, mode)
	-- the machine is its own built-in instance
	transition(self, self, next_state, context_arg, mode)
end

---Set the machine's state with no transition run.
---
---The hooks don't run, and the history records the move as forced. It's for putting a state in
---place, as a teardown, a replay or the machine's first state does, never for moving through one.
---
---@param state stateName A registered state
---@return nil
function StateMachine:force_state(state)
	force(self, self, state)
end

---Make an instance of this machine in its first state.
---
---The instance shares the machine's states, transitions and hooks, and has a state, a history and
---switches of its own. It isn't in the factory's list of machines.
---
---@param first_state stateName A registered state for the instance to start in
---@return iStateMachine instance The new instance
function StateMachine:instantiate(first_state)
	helper.validate_state_name_param(first_state, "first_state")
	if not self:is_state_registered(first_state) then
		error("Cannot make an instance in unregistered state: " .. first_state, 2) -- the caller's line
	end
	local instance = setmetatable({
		model = self,
		history = {},
		own = { transitions = {}, hooks = {} },
		pending = {},
		depth = 0,
	}, instance_mt)
	place(self, instance, first_state)
	return instance
end

---Set the function that names an instance of this machine in its messages.
---
---It's called with the instance whenever a message has to say which one: a failing hook's
---notification, and the engine's own errors. With none, an instance goes by the machine's name.
---
---@param labeler fun(instance: iStateMachine): string The function naming an instance
---@return nil
function StateMachine:set_labeler(labeler)
	helper.validate_param(labeler, "labeler", "function", false)
	self.labeler = labeler
end

return StateMachine
