---History domain handles.
---
---A handle is an opaque key for a file the path registry knows, made at runtime and never saved.
---It follows the file through renames, so whatever holds it keeps holding the same file. Each
---handle is an instance of the handle machine, open while its file has a buffer and closed
---otherwise. The hash API stays in front for now: the registry's own functions keep the handles in
---step with it, and nothing reads a handle yet.

local data = require("frogman.domains.history.data")

---@class FileHandle: iStateMachine A file's handle
---@field id integer The handle's number, counted up and never given again
---@field hash Filehash The hash of the file's name, which a rename changes
---@field gone boolean Whether the file is gone from disk (it has a tag)
---@field copy_of integer|nil The number of the handle it was copied from, for the trail

---@class HandleModes
---@field RENAME "rename" The file took a new hash: a move, or a No Name text reopened
---@field VANISH "vanish" The file went from disk
---@field RETURN "return" The file is back on disk
---
---@class HandleStates
---@field OPEN "open" The file has a buffer
---@field CLOSED "closed" The file has no buffer
---@field mode HandleModes
local states = {
	OPEN = "open",
	CLOSED = "closed",
	mode = {
		RENAME = "rename",
		VANISH = "vanish",
		RETURN = "return",
	},
}

local M = {}

M.states = states

---The handles that live (handle number → handle)
---@type table<integer, FileHandle>
local live = {}
---The handle of each hash (file hash → handle)
---@type table<Filehash, FileHandle>
local by_hash = {}
---The next handle's number: it only goes up, a teardown included
---@type integer
local next_id = 1

---Keep a handle's fields from its transition's context.
---
---The context carries the hash the handle has after the transition, which a rename changes, and
---whether its file is gone from disk.
---
---@param context table The transition's context
---@param handle FileHandle The handle moved
---@return nil
local function keep_fields(context, handle)
	if context.hash then
		handle.hash = context.hash
	end
	if context.gone ~= nil then
		handle.gone = context.gone
	end
end

local engine = require('frogman.engine')
local model = engine:get("handle")
if model == nil then
	model = engine:create("handle")
	model:register_state(states.OPEN)
	model:register_state(states.CLOSED)
	model:register_mode(states.mode.RENAME)
	model:register_mode(states.mode.VANISH)
	model:register_mode(states.mode.RETURN)
	local in_place = "{" .. states.mode.RENAME .. "," .. states.mode.VANISH .. "," .. states.mode.RETURN .. "}"
	model:on(states.OPEN, states.CLOSED, "keep_fields_on_close", keep_fields, 1, true)
	model:on(states.CLOSED, states.OPEN, "keep_fields_on_open", keep_fields, 1, true)
	model:on(states.OPEN, states.OPEN, "keep_fields_while_open", keep_fields, 1, true, in_place)
	model:on(states.CLOSED, states.CLOSED, "keep_fields_while_closed", keep_fields, 1, true, in_place)
	-- a handle goes by its file's name in messages
	model:set_labeler(function(handle)
		local filepath = data.hash_filepath_registry.filepaths[handle.hash]
		return filepath and vim.fs.basename(filepath) or handle.hash
	end)
end
M.model = model

---Make a handle for a hash that has none.
---
---@param hash Filehash
---@param state "open"|"closed" The state it starts in
---@return FileHandle handle The new handle
local function mint(hash, state)
	local handle = model:instantiate(state)
	---@cast handle FileHandle
	handle.id, handle.hash, handle.gone = next_id, hash, data.missing[hash] ~= nil
	next_id = next_id + 1
	live[handle.id], by_hash[hash] = handle, handle
	return handle
end

---Move a handle, its hash and gone flag carried in the transition's context.
---
---@param handle FileHandle
---@param state "open"|"closed" The state it goes to
---@param context table|nil What changes with it (hash, gone)
---@param mode string|nil The transition's mode
---@return nil
local function move(handle, state, context, mode)
	context = context or {}
	context.hash = context.hash or handle.hash
	if context.gone == nil then
		context.gone = handle.gone
	end
	handle:to(state, context, mode)
end

---Get a file's handle by its hash.
---
---@param hash Filehash|nil
---@return FileHandle|nil handle The live handle for the hash, or nil if there's none
function M.of_hash(hash)
	if hash == nil then
		return nil
	end
	return by_hash[hash]
end

---Get a live handle by its number.
---
---@param id integer
---@return FileHandle|nil handle The handle, or nil once it's let go
function M.get(id)
	return live[id]
end

---Get every live handle.
---
---@return table<integer, FileHandle> handles Handle number → handle
function M.live()
	return live
end

---Make sure a file the path registry knows has its handle.
---
---Called when a path is registered. A hash with no handle gets one, closed, since no buffer is
---registered for it yet.
---
---@param hash Filehash
---@return FileHandle handle The file's handle
function M.known(hash)
	return by_hash[hash] or mint(hash, states.CLOSED)
end

---Mark a file's handle open, its hash now registered to a buffer.
---
---A hash with no handle gets one, open. A closed handle moves to open, and an open one stays.
---
---@param hash Filehash
---@return FileHandle handle The file's handle
function M.opened(hash)
	local handle = by_hash[hash]
	if handle == nil then
		return mint(hash, states.OPEN)
	end
	if handle:state() == states.CLOSED then
		move(handle, states.OPEN)
	end
	return handle
end

---Mark a file's handle closed, its hash no longer registered to a buffer.
---
---@param hash Filehash|nil
---@return nil
function M.closed(hash)
	local handle = M.of_hash(hash)
	if handle and handle:state() == states.OPEN then
		move(handle, states.CLOSED)
	end
end

---Give a file's handle the hash of its new name.
---
---Used when a file takes a new hash: a rename that was a move, or a No Name text reopened under a
---new id. A live handle the new hash had is let go, since the moved file wins. When a buffer is
---registered under the new hash already, the handle is open.
---
---@param old_hash Filehash The hash it had
---@param new_hash Filehash The hash it takes
---@return nil
function M.renamed(old_hash, new_hash)
	local handle = by_hash[old_hash]
	if handle == nil or old_hash == new_hash then
		return
	end
	if by_hash[new_hash] then
		M.let_go(new_hash)
	end
	by_hash[old_hash], by_hash[new_hash] = nil, handle
	move(handle, handle:state(), { hash = new_hash }, states.mode.RENAME)
	if data.hash_buffer_registry.buffers[new_hash] then
		M.opened(new_hash)
	end
end

---Link a copy's handle to the handle of the file it was copied from.
---
---@param new_hash Filehash The copy's hash
---@param old_hash Filehash The hash of the file it was copied from
---@return nil
function M.copied(new_hash, old_hash)
	local copy, source = by_hash[new_hash], by_hash[old_hash]
	if copy and source and copy ~= source then
		copy.copy_of = source.id
	end
end

---Mark whether a file is gone from disk.
---
---Called wherever its tag is put on or cleared, so a handle's gone flag is true exactly while its
---file has a tag.
---
---@param hash Filehash
---@param gone boolean Whether it's gone
---@return nil
function M.set_gone(hash, gone)
	local handle = by_hash[hash]
	if handle and handle.gone ~= gone then
		move(handle, handle:state(), { gone = gone }, gone and states.mode.VANISH or states.mode.RETURN)
	end
end

---Set every handle's gone flag from the tags, after the tags were put in place all at once.
---
---@return nil
function M.follow_tags()
	for _, handle in pairs(live) do
		M.set_gone(handle.hash, data.missing[handle.hash] ~= nil)
	end
end

---Let a file's handle go.
---
---Called once the path registry forgets the file. Its instance is unregistered, and its number
---isn't given again.
---
---@param hash Filehash
---@return nil
function M.let_go(hash)
	local handle = by_hash[hash]
	if handle == nil then
		return
	end
	by_hash[hash], live[handle.id] = nil, nil
	handle:unregister()
end

---Let every handle go, as a teardown starts from nothing.
---
---The count isn't reset, so a handle made afterwards is numbered above every one before.
---
---@return nil
function M.reset()
	for _, handle in pairs(live) do
		handle:unregister()
	end
	live, by_hash = {}, {}
end

return M
