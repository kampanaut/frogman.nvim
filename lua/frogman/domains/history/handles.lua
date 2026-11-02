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
---@field holders table<string, true> The places holding it now (place → true)

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
---What each place holds (place → handle → true): a window's slot, an open buffer, a list
---@type table<string, table<FileHandle, true>>
local places = {}
---Where a handle let go for a moved file went (handle number → the moved file's handle number)
---@type table<integer, integer>
local forwards = {}

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
	handle.holders = {}
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

---Put a handle in a place.
---
---@param handle FileHandle
---@param place string
---@return nil
local function add(handle, place)
	handle.holders[place] = true
	places[place] = places[place] or {}
	places[place][handle] = true
end

---The handles that lost their last holder in this batch, waiting for its let-go (handle → true)
---@type table<FileHandle, true>
local unheld = {}

---Let a handle that lost its last holder go once the editor settles.
---
---Never mid-batch: a file let go and held again by the same batch, as a swap's two writes can, is
---held when its turn comes, and stays. One turn takes every handle the batch let go, and when any is
---still held by nothing then, follow-along forgets them in one pass.
---
---@param handle FileHandle
---@return nil
local function let_go_when_settled(handle)
	local queued = next(unheld) ~= nil
	unheld[handle] = true
	if queued then
		return
	end
	require('frogman.settle').later("let go", function()
		local waiting = unheld
		unheld = {}
		M.forget_unheld(waiting)
	end)
end

---Forget the handles that nothing holds, of those given.
---
---Follow-along drops the notes and history entries naming them and forgets their paths. One that
---nothing weak names either has its path forgotten after it, and the trail says so as it does for
---the rest.
---
---@param waiting table<FileHandle, true> The handles to look at
---@return nil
function M.forget_unheld(waiting)
	local routines = require('frogman.domains.history.routines')
	local any = false
	for handle, _ in pairs(waiting) do
		if not handle.unregistered and next(handle.holders) == nil then
			any = true
		end
	end
	if not any then
		return
	end
	routines.follow_along()
	local ledger = require('frogman.domains.ledger')
	for handle, _ in pairs(waiting) do
		local filepath = data.hash_filepath_registry.filepaths[handle.hash]
		if not handle.unregistered and next(handle.holders) == nil and filepath then
			local name = ledger.name_of(handle.hash)
			routines.unregister_filepath(filepath)
			if data.hash_filepath_registry.filepaths[handle.hash] == nil then
				ledger.move("forgotten", { subject = handle.hash, name = name, notes = 0, words = "nothing holds it any more" })
			end
		end
	end
end

---Take a handle out of a place.
---
---A handle left with no place holding it is let go once the editor settles.
---
---@param handle FileHandle
---@param place string
---@param quiet boolean|nil Whether it's being let go already, so nothing is queued
---@return nil
local function remove(handle, place, quiet)
	handle.holders[place] = nil
	if places[place] then
		places[place][handle] = nil
		if next(places[place]) == nil then
			places[place] = nil
		end
	end
	if not quiet and next(handle.holders) == nil then
		let_go_when_settled(handle)
	end
end

---Set what a place holds.
---
---A strong holder calls it at the write that changes what it holds: the handles it held and no
---longer holds leave it, and the new ones join it. A hash with no handle holds nothing.
---
---@param place string The holder's place, like "win:1000:ternary" or "pool:editor"
---@param hashes table<any, Filehash> The hashes it holds now (a list, or any table of them)
---@return nil
function M.hold(place, hashes)
	local now = {}
	for _, hash in pairs(hashes) do
		local handle = by_hash[hash]
		if handle then
			now[handle] = true
		end
	end
	for handle, _ in pairs(places[place] or {}) do
		if not now[handle] then
			remove(handle, place)
		end
	end
	for handle, _ in pairs(now) do
		add(handle, place)
	end
end

---Add one file to what a place holds.
---
---@param place string
---@param hash Filehash
---@return nil
function M.take(place, hash)
	local handle = by_hash[hash]
	if handle then
		add(handle, place)
	end
end

---Take one file out of what a place holds.
---
---@param place string
---@param hash Filehash
---@return nil
function M.leave(place, hash)
	local handle = by_hash[hash]
	if handle then
		remove(handle, place)
	end
end

---Let a place go, and everything it held.
---
---@param place string
---@return nil
function M.drop_place(place)
	for handle, _ in pairs(places[place] or {}) do
		remove(handle, place)
	end
	places[place] = nil
end

---Get the hashes a place holds.
---
---@param place string
---@return Filehash[] hashes The hashes, sorted
function M.held_by(place)
	local out = {}
	for handle, _ in pairs(places[place] or {}) do
		table.insert(out, handle.hash)
	end
	table.sort(out)
	return out
end

---Get the places holding a file.
---
---@param hash Filehash
---@return string[] places The places, sorted
function M.holders(hash)
	local handle = by_hash[hash]
	local out = handle and vim.tbl_keys(handle.holders) or {}
	table.sort(out)
	return out
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
---A hash with no handle gets one, open. A closed handle moves to open, and an open one stays. The
---open buffer holds it.
---
---@param hash Filehash
---@return FileHandle handle The file's handle
function M.opened(hash)
	local handle = by_hash[hash]
	if handle == nil then
		handle = mint(hash, states.OPEN)
	elseif handle:state() == states.CLOSED then
		move(handle, states.OPEN)
	end
	add(handle, "buffer")
	return handle
end

---Mark a file's handle closed, its hash no longer registered to a buffer.
---
---@param hash Filehash|nil
---@return nil
function M.closed(hash)
	local handle = M.of_hash(hash)
	if handle == nil then
		return
	end
	remove(handle, "buffer")
	if handle:state() == states.OPEN then
		move(handle, states.CLOSED)
	end
end

---Give a file's handle the hash of its new name.
---
---Used when a file takes a new hash: a rename that was a move, or a No Name text reopened under a
---new id. A live handle the new hash had is let go, since the moved file wins, and the places that
---held it hold the moved file now. When a buffer is registered under the new hash already, the
---handle is open.
---
---@param old_hash Filehash The hash it had
---@param new_hash Filehash The hash it takes
---@return nil
function M.renamed(old_hash, new_hash)
	local handle = by_hash[old_hash]
	if handle == nil or old_hash == new_hash then
		return
	end
	local other = by_hash[new_hash]
	if other then
		for place, _ in pairs(other.holders) do
			add(handle, place)
		end
		M.let_go(new_hash)
		forwards[other.id] = handle.id -- what held the other file holds the moved one now
	end
	by_hash[old_hash], by_hash[new_hash] = nil, handle
	move(handle, handle:state(), { hash = new_hash }, states.mode.RENAME)
	if data.hash_buffer_registry.buffers[new_hash] then
		M.opened(new_hash)
	end
end

---Follow a handle's number to the handle that took its file's name, when it was let go for a moved file.
---
---@param id integer
---@return integer id The live handle's number, or the one given when nothing took its place
function M.resolve(id)
	local seen = 0
	while forwards[id] and seen < 64 do
		id, seen = forwards[id], seen + 1
	end
	return id
end

---Check if a file is held by anything besides the windows' slots: an open buffer, a list or a mark.
---
---@param hash Filehash|nil
---@return boolean held
function M.held_beyond_windows(hash)
	local handle = M.of_hash(hash)
	for place, _ in pairs(handle and handle.holders or {}) do
		if not place:match("^win:") then
			return true
		end
	end
	return false
end

---Check if a file is closed and kept: no buffer, and something besides the windows' slots holds it, a
---list or a mark, so a slot keeps it and using it reopens it.
---
---@param hash Filehash|nil
---@return boolean kept
function M.kept_closed(hash)
	local handle = M.of_hash(hash)
	return handle ~= nil and handle:state() == states.CLOSED and M.held_beyond_windows(hash)
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
	for place, _ in pairs(handle.holders) do
		remove(handle, place, true)
	end
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
	live, by_hash, places, unheld = {}, {}, {}, {}
end

return M
