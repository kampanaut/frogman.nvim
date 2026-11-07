---History domain handles.
---
---A handle is an opaque key for a file the path registry knows, made at runtime and never saved.
---It follows the file through renames, so whatever holds it keeps holding the same file. Each
---handle is an instance of the handle machine, open while its file has a buffer and closed
---otherwise. Everything that refers to a file holds its handle's number: a rename changes the hash
---behind the number, and nothing that holds it is rewritten. The registry's own functions, which
---map names to hashes, keep the handles in step with it.

local data = require("frogman.domains.history.data")

---@alias HandleId integer A handle's number, what every consumer holds for a file

---@class FileHandle: iStateMachine A file's handle
---@field id HandleId The handle's number, counted up and never given again
---@field hash Filehash The hash of the file's name, which a rename changes
---@field gone boolean Whether the file is gone from disk (it has a tag)
---@field tag string|nil Where you were when the file went missing, or the time, while it's gone
---@field unwritten Bufnr|true|nil Whether the file was never written, by the buffer that marked it or a session file
---@field text NoNameBufferContent|table|nil A No Name text closed, its lines, or how to read them from its file
---@field copy_of HandleId|nil The number of the handle it was copied from, for the trail
---@field holders table<string, true> The places holding it now (place → true)

---@class HandleModes
---@field RENAME "rename" The file took a new hash: a move, or a No Name text reopened
---@field VANISH "vanish" The file went from disk
---@field RETURN "return" The file is back on disk
---@field COPY "copy" The handle is a copy's, linked to the file it was copied from
---@field FORGET "forget" The handle is let go, just before it's unregistered
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
		COPY = "copy",
		FORGET = "forget",
	},
}

---@class HandleContext What a handle's transition carries, for the hooks that react on it
---@field was? Filehash The hash the handle had before the transition (filled in by the move)
---@field hash? Filehash The hash it has after it (the move fills in the one it has when none is given)
---@field gone? boolean Whether its file is gone from disk after it (the move fills it in when it doesn't change)
---@field tag string|nil Its tag after it, while its file is gone
---@field quiet boolean|nil Whether the trail leaves it out
---@field load boolean|nil Whether a load makes it, which the trail leaves out but for a No Name text reopened under a new id and a file taken off a closed list
---@field lists string[]|nil A close's lists, by name, or a repair's
---@field left string[]|nil The lists a reopen took the file off, by name (the closed lists' hook fills it)
---@field others string[]|nil Of `lists` or `left`, those other than the current tab's
---@field new boolean|nil Whether a reopened file was never written, so it opens as a new one
---@field reopen boolean|nil Whether a reopen asked for, by a key or a list, which the trail records even off no list
---@field from Filehash|nil The hash a No Name text had before its reopen
---@field kind "move"|"reopen"|"load"|nil What a rename was: a move, a No Name text's reopen, or a load's
---@field other HandleId|nil The handle a move onto a held name lets go
---@field repair string|nil What a cleanup's repair found, which the trail says in place of a close
---@field notes integer|nil How many notes about a forgotten file went with it
---@field words string|nil What a move or a copy says in the trail
---@field cleared table[]|nil The snapshots a move left holding one file twice, and the slot each let go

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
---whether its file is gone from disk, with its tag while it's gone.
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
		handle.tag = context.gone and context.tag or nil
	end
end

local engine = require('frogman.engine')
local model = engine:get("handle")
if model == nil then
	model = engine:create("handle")
	model:register_state(states.OPEN)
	model:register_state(states.CLOSED)
	for _, mode in pairs(states.mode) do
		model:register_mode(mode)
	end
	local in_place = "{" .. table.concat({ states.mode.RENAME, states.mode.VANISH, states.mode.RETURN, states.mode.COPY,
		states.mode.FORGET }, ",") .. "}"
	model:on(states.OPEN, states.CLOSED, "keep_fields_on_close", keep_fields, 1, true)
	model:on(states.CLOSED, states.OPEN, "keep_fields_on_open", keep_fields, 1, true)
	model:on(states.OPEN, states.OPEN, "keep_fields_while_open", keep_fields, 1, true, in_place)
	model:on(states.CLOSED, states.CLOSED, "keep_fields_while_closed", keep_fields, 1, true, in_place)
	-- a handle goes by its file's unique name in messages, as the winbar names it; one with no path any
	-- more, let go, by its name's last part or its hash
	model:set_labeler(function(handle)
		local ok, name = pcall(function() return require('frogman.domains.ui').routines.get_smart_basename(handle.id) end)
		if ok and type(name) == "string" then
			return name
		end
		local filepath = data.hash_filepath_registry.filepaths[handle.hash]
		return filepath and vim.fs.basename(filepath) or handle.hash
	end)
end
M.model = model

---Make a handle for a hash that has none.
---
---It starts with no tag: a file is tagged gone by a check of the disk, or by a load putting back
---the tags it saved.
---
---@param hash Filehash The hash of the file's name
---@param state "open"|"closed" The state it starts in
---@return FileHandle handle The new handle
local function mint(hash, state)
	local handle = model:instantiate(state)
	---@cast handle FileHandle
	handle.id, handle.hash, handle.gone = next_id, hash, false
	handle.holders = {}
	next_id = next_id + 1
	live[handle.id], by_hash[hash] = handle, handle
	return handle
end

---Move a handle, its hash and gone flag carried in the transition's context.
---
---The context also carries the hash the handle had before, and whatever the caller knows of what
---happened, for the hooks that react on the transition (see `HandleContext`).
---
---@param handle FileHandle The handle to move
---@param state "open"|"closed" The state it goes to
---@param context HandleContext|table|nil What changes with it (hash, gone, tag), and what happened
---@param mode string|nil The transition's mode
---@return nil
local function move(handle, state, context, mode)
	context = context or {}
	context.was = handle.hash
	context.hash = context.hash or handle.hash
	if context.gone == nil then
		context.gone, context.tag = handle.gone, handle.tag
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
---nothing weak names either has its path forgotten after it, its let-go a move in the trail as every
---let-go is.
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
	for handle, _ in pairs(waiting) do
		local filepath = data.hash_filepath_registry.filepaths[handle.hash]
		if not handle.unregistered and next(handle.holders) == nil and filepath then
			routines.unregister_filepath(filepath)
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
---longer holds leave it, and the new ones join it. A number whose handle was let go holds nothing.
---
---@param place string The holder's place, like "win:1000:ternary" or "pool:editor"
---@param ids table<any, HandleId> The handles it holds now (a list, or any table of them)
---@return nil
function M.hold(place, ids)
	local now = {}
	for _, id in pairs(ids) do
		local handle = live[id]
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
---@param place string The holder's place
---@param id HandleId The file's handle
---@return nil
function M.take(place, id)
	local handle = live[id]
	if handle then
		add(handle, place)
	end
end

---Take one file out of what a place holds.
---
---@param place string The holder's place
---@param id HandleId The file's handle
---@return nil
function M.leave(place, id)
	local handle = live[id]
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

---Get the handles a place holds.
---
---@param place string The holder's place
---@return HandleId[] ids The handles' numbers, sorted
function M.held_by(place)
	local out = {}
	for handle, _ in pairs(places[place] or {}) do
		table.insert(out, handle.id)
	end
	table.sort(out)
	return out
end

---Get the places holding a file.
---
---@param id HandleId|nil The file's handle
---@return string[] places The places, sorted
function M.holders(id)
	local handle = id and live[id]
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
	if by_hash[hash] then
		return by_hash[hash]
	end
	local handle = mint(hash, states.CLOSED)
	-- a path no holder takes is forgotten once the editor settles, as one that loses its last holder is
	let_go_when_settled(handle)
	return handle
end

---Mark a file's handle open, its hash now registered to a buffer.
---
---A hash with no handle gets one, open. A closed handle moves to open, and an open one stays. The
---open buffer holds it.
---
---@param hash Filehash The hash the buffer is registered under
---@param context HandleContext|nil What the reopen is, when it is one: asked for, a load's, a text's
---@return FileHandle handle The file's handle
function M.opened(hash, context)
	local handle = by_hash[hash]
	if handle == nil then
		handle = mint(hash, states.OPEN)
	elseif handle:state() == states.CLOSED then
		move(handle, states.OPEN, context)
	end
	add(handle, "buffer")
	return handle
end

---Mark a file's handle closed, its hash no longer registered to a buffer.
---
---@param hash Filehash|nil The hash the buffer was registered under; nil closes nothing
---@param context HandleContext|nil What the close is: the lists it went on, a repair's words, or quiet
---@return nil
function M.closed(hash, context)
	local handle = M.of_hash(hash)
	if handle == nil then
		return
	end
	remove(handle, "buffer")
	if handle:state() == states.OPEN then
		move(handle, states.CLOSED, context)
	end
end

---Give a file's handle the hash of its new name.
---
---Used when a file takes a new hash: a rename that was a move, or a No Name text reopened under a
---new id. A live handle the new hash had is let go, quietly, since the moved file wins and takes its
---name, and the places that held it hold the moved file now; the rename's hooks hand it the rest
---(`context.other`). When a buffer is registered under the new hash already, the handle is open.
---
---@param old_hash Filehash The hash it had
---@param new_hash Filehash The hash it takes
---@param context HandleContext|nil What the rename is (`kind`) and what the trail says of it
---@return nil
function M.renamed(old_hash, new_hash, context)
	local handle = by_hash[old_hash]
	if handle == nil or old_hash == new_hash then
		return
	end
	context = context or {}
	local other = by_hash[new_hash]
	if other then
		for place, _ in pairs(other.holders) do
			add(handle, place)
		end
		M.let_go(new_hash, { quiet = true }) -- its name is the moved file's now, which the trail follows
		forwards[other.id] = handle.id -- what held the other file holds the moved one now
		context.other = other.id
	end
	by_hash[old_hash], by_hash[new_hash] = nil, handle
	context.hash = new_hash
	move(handle, handle:state(), context, states.mode.RENAME)
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

---Get the live handle a handle number leads to, following its moves.
---
---@param id integer The handle's number, as a mark or a snapshot keeps it
---@return FileHandle|nil handle The live handle, or nil when none is
function M.follow(id)
	return M.get(M.resolve(id))
end

---Check if a file is held by anything besides the windows' slots: an open buffer, a list or a mark.
---
---@param id HandleId|nil The file's handle
---@return boolean held
function M.held_beyond_windows(id)
	return M.held_beyond(id, { win = true })
end

---The kinds of place a file is held by for the windows, the lists and the open buffers, the rest being
---what keeps a file for itself: a mark, a snapshot, a group waiting to be held over
---@type table<string, true>
M.WINDOWS_AND_LISTS = { win = true, pool = true, buffer = true }

---Check if a file is held by a place of a kind not given: a place's kind is its name's part before the
---first colon, `win`, `pool`, `mark`, `snap`, or `buffer` for the open buffer.
---
---@param id HandleId|nil The file's handle
---@param kinds table<string, true> The kinds that don't count
---@return boolean held
function M.held_beyond(id, kinds)
	local handle = id and live[id]
	for place, _ in pairs(handle and handle.holders or {}) do
		if not kinds[place:match("^[^:]+")] then
			return true
		end
	end
	return false
end

---Check if a file is closed and kept: no buffer, and something besides the windows' slots holds it, a
---list or a mark, so a slot keeps it and using it reopens it.
---
---@param id HandleId|nil The file's handle
---@return boolean kept
function M.kept_closed(id)
	local handle = id and live[id]
	return handle ~= nil and handle:state() == states.CLOSED and M.held_beyond_windows(id)
end

---Link a copy's handle to the handle of the file it was copied from.
---
---The copy's handle moves with the mode `copy`, its `copy_of` set, which what reacts on the copy reads,
---the trail's hook writing the source's hash beside the copy's.
---
---@param new_hash Filehash The copy's hash
---@param old_hash Filehash The hash of the file it was copied from
---@param context HandleContext|nil What the trail says of the copy (`words`)
---@return nil
function M.copied(new_hash, old_hash, context)
	local copy, source = by_hash[new_hash], by_hash[old_hash]
	if copy and source and copy ~= source then
		copy.copy_of = source.id
		move(copy, copy:state(), context, states.mode.COPY)
	end
end

---Tag a file as gone from disk, or clear its tag.
---
---The tag is the handle's own, so its gone flag is true exactly while it has one, and a move keeps
---it. Putting it on moves the handle with the mode `vanish`, clearing it with `return`; a tag
---changed while the file stays gone is kept the same way.
---
---@param id HandleId|nil The file's handle
---@param tag string|nil Where you were when the file went missing, or the time (nil = it's back)
---@param context HandleContext|nil A load's or a replay's, which the trail leaves out
---@return nil
function M.set_tag(id, tag, context)
	local handle = id and live[id]
	if handle == nil or handle.tag == tag then
		return
	end
	context = context or {}
	context.gone, context.tag = tag ~= nil, tag
	move(handle, handle:state(), context, tag and states.mode.VANISH or states.mode.RETURN)
end

---Let a file's handle go.
---
---Called once the path registry is about to forget the file. The handle moves with the mode `forget`,
---while its path is still known, so what reacts on it can name it; then its instance is unregistered,
---and its number isn't given again.
---
---@param hash Filehash The hash of the file being forgotten
---@param context HandleContext|nil Why it goes: a load's teardown, quiet, and the notes that went with it
---@return nil
function M.let_go(hash, context)
	local handle = by_hash[hash]
	if handle == nil then
		return
	end
	move(handle, handle:state(), context, states.mode.FORGET)
	by_hash[hash], live[handle.id] = nil, nil
	for place, _ in pairs(handle.holders) do
		remove(handle, place, true)
	end
	handle:unregister()
end

---Let every handle go, as a teardown starts from nothing.
---
---Each goes through its `forget`, a load's in its context, so the trail leaves them out. The count
---isn't reset, so a handle made afterwards is numbered above every one before.
---
---@return nil
function M.reset()
	for _, handle in pairs(live) do
		move(handle, handle:state(), { load = true }, states.mode.FORGET)
		handle:unregister()
	end
	live, by_hash, places, unheld, forwards = {}, {}, {}, {}, {}
end

return M
