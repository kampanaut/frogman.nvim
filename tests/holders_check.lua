-- The handles' holders check (M2 Holders), run inside a case's child: the handles that have a
-- holder are exactly what frogman calls known, once nothing waits to settle no live handle is held by
-- nothing, and each place holds what its own writes say, a window's slots and queue, a list's closed
-- files, a mark's file, a snapshot's files and the registered buffers. Both child.settle under FRG_CHECK_HOLDERS (tests/helpers.lua) and the walks'
-- HOLDERS check (tests/helpers_decisions.lua) run this one copy, which the child finds on its
-- runtimepath.
--
-- Returns a function of `name`, which names a handle in a message (its number itself when there's none),
-- giving the first drift it finds, or nil.
return function(name)
	if not package.loaded['frogman.domains.history'] then
		return nil
	end
	local H = require('frogman.domains.history')
	if not H.handles or not H.handles.holders then
		return nil
	end
	name = name or tostring
	local known, held = H.routines.known_handles(), {}
	for id, h in pairs(H.handles.live()) do
		if next(h.holders) then held[id] = true end
	end
	for id in pairs(known) do
		if not held[id] and H.handles.get(id) then
			return string.format('%s is known, and its handle has no holder', name(id))
		end
	end
	for id in pairs(held) do
		if not known[id] then
			return string.format('%s has a holder (%s), and is not known', name(id), table.concat(H.handles.holders(id), ', '))
		end
	end
	-- once nothing waits to settle, a handle no holder holds has been let go (DESK.md:649): a let-go is
	-- the one way a file is forgotten, so a live handle held by nothing is a route that never queued it
	local settle = package.loaded['frogman.settle']
	if not (settle and #settle.pending() > 0) then
		for id, h in pairs(H.handles.live()) do
			if next(h.holders) == nil then
				return string.format('%s is held by nothing, and its handle lives on', name(id))
			end
		end
	end
	local W = require('frogman.domains.window')
	local function same(place, ids)
		local want, seen = {}, {}
		for _, h in pairs(ids) do
			if H.handles.get(h) then want[h] = true end
		end
		for _, h in ipairs(H.handles.held_by(place)) do
			if not want[h] then return place .. ' holds ' .. h .. ', which it does not' end
			seen[h] = true
		end
		for h in pairs(want) do
			if not seen[h] then return place .. ' misses ' .. h end
		end
	end
	for winid, t in pairs(W.data.crux) do
		local p = 'win:' .. winid .. ':'
		local bad = same(p .. 'current', { t.current_slot }) or same(p .. 'secondary', { t.secondary_slot })
			or same(p .. 'ternary', { t.ternary_slot }) or same(p .. 'primary', t.primary_buffer or {})
		if bad then return bad end
	end
	for _, pool in pairs(H.routines.pools()) do
		local bad = same(pool:place(), pool.closed)
		if bad then return bad end
	end
	-- each mark's place holds its file (M15)
	local Mk = package.loaded['frogman.domains.marks']
	for kind, scopes in pairs(Mk and Mk.data.scopes or {}) do
		for id, scope in pairs(scopes) do
			for position, group in ipairs(scope.groups) do
				for alias, hid in pairs(group.marks) do
					local handle = H.handles.get(H.handles.resolve(hid))
					local bad = same('mark:' .. kind .. ':' .. tostring(id) .. ':' .. position .. ':' .. alias, { handle and handle.id })
					if bad then return bad end
				end
			end
		end
	end
	-- each snapshot's place holds its slots', its queue's and its order's files, a window's, a held-over
	-- one's or one waiting to be held over (M16)
	local Sn = package.loaded['frogman.domains.snapshots']
	local lists = {}
	for _, field in ipairs({ 'by_window', 'held' }) do
		for _, snaps in pairs(Sn and Sn.data[field] or {}) do table.insert(lists, snaps) end
	end
	for _, entry in ipairs(Sn and Sn.data.pending or {}) do table.insert(lists, entry.snapshots) end
	for _, snaps in ipairs(lists) do
		for _, sn in ipairs(snaps) do
			local ids = {}
			for _, id in ipairs(vim.list_extend({ sn.current, sn.secondary or false, sn.ternary or false }, vim.list_extend(vim.deepcopy(sn.queue), sn.order))) do
				local h = id and H.handles.get(H.handles.resolve(id))
				if h then table.insert(ids, h.id) end
			end
			local bad = same('snap:' .. sn.id, ids)
			if bad then return bad end
		end
	end
	local bufs = {}
	for h in pairs(H.data.hash_buffer_registry.buffers) do table.insert(bufs, H.get_handle_from_hash(h)) end
	return same('buffer', bufs)
end
