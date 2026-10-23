# Test review sheet

409 cases in 25 files, generated from `tests/` and `what-is-cavediver.md`. For each case: is the route how you'd really use cavediver, is the expected result what you want, is the tag right?

- **[char]**: intended, and true today. **[today]**: today's behaviour, expected to flip when its fix lands. **[target]**: decided, not built; fails until its fix lands.
- Slots read `⦉ternary⦊ [current] ⟦secondary⟧`. Notes read `dtm{…}` (what `<M-;><M-r>` restores) and `dsm{…}` (what `<M-;><M-t>` restores); `b>a` is b's note, `b-swap>a` its swap note.
- Each line reads steps → what is checked after them. `:e a` opens a.txt; `<M-f>` and the like press the mapped key; other `:` lines are Ex commands. Steps run in the order shown.
- "spec" quotes the spec's entry for the same ID, so you can see the test says what the spec says.

## Look at these first

**State set by hand** (51): T184 (keep_older), T192 (keep_older), T107 (cleanup), T108 (cleanup), T113 (cleanup), T163 (cleanup), T91 (closing), T203 (cycling), T204 (cycling), T205 (cycling), T251 (decisions), T257 (decisions), T263 (decisions), T263 (decisions), T264 (decisions), T265 (decisions), T267 (decisions), T271 (decisions), T271 (decisions), T273 (decisions), T275 (decisions), T276 (decisions), T280 (decisions), T285 (decisions), T287 (decisions), T20 (history), T12 (identity), T157 (invariants), T25 (lifecycle), T34 (navigation), T35 (navigation), T219 (negative), T241 (negative), T242 (negative), T243 (negative), T243 (negative), T243 (negative), T247 (negative), T66 (restores), T68 (restores), T296 (s2), T298 (s2), T299 (s2), T315 (s2), T316 (s2), T351 (s2), T352 (s2), T138 (sessions), T146 (sessions), T147 (sessions), T148 (sessions)

**Random walk** (24): T190 (keep_older), T190 (keep_older), T190 (keep_older), T190 (keep_older), T335 (keep_older), T335 (keep_older), T171 (cycling), T279 (decisions), T281 (decisions), T282 (decisions), T283 (decisions), T149 (history), T149 (history), T128 (invariants), T129 (invariants), T130 (invariants), T131 (invariants), T132 (invariants), T133 (invariants), T334 (invariants), T154 (invariants), T249 (negative), T249 (negative), T299 (s2)

**Routes changed by the porting agents** so a target fails for the right reason:
- T111 (test_cleanup.lua): route changed so it fails for the right reason (the first route passed by luck)
- T128 (test_invariants.lua): walks raised to 100 so the break shows up (about 3% of walks break today)
- T129 (test_invariants.lua): :enew and <M-.> doubled in the walk mix to reach the break more often
- T212 (test_negative.lua): the child's umask forced to 022, so the result doesn't depend on the runner
- T235 (test_negative.lua): the save runs in pcall, since the hole makes the pop-up's redraw throw
- T242 (test_negative.lua): wipes the window's current buffer: the bug only shows for that one
- T247 (test_negative.lua): an acwrite window whose current file is :bdeleted from the focused window, to reach the healing branch
- T146 (test_sessions.lua): the split visits a file first, so the save reaches the oil case

**Doc checks**: everything in `tests/test_docs.lua` (README and comment wording).

## tests/test_keep_older.lua (23 cases: 23 char)

**T177 [char]** the round trip onto the secondary and back: <M-;><M-t> on c says "No secondary relationship found"  
`:e a`, `:e b`, `:e c`, `<M-f>`, `<M-f>`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
`<M-;><M-t> (via clean)` → `eq(K.has(msgs, 'No secondary relationship found'), true)`  
→ `slots = '⦉-⦊ [c] ⟦b⟧'`  
→ `eq(K.dsm(child), 'dsm{b-swap>c b>a c-swap>b}')`  
note: <M-f> (b graduates), <M-f> (to b), <M-f> (back to c).  
spec: ("Keep the older one") The round trip onto the secondary and back: `:e a`, `:e b`, `:e c`, `<M-f>` (b graduates), `<M-f>` (to b), `<M-f>` (back to c), then `<M-;><M-t>` on c doesn't throw. It says "No secondary relationship found", since c has no secondary from before; the window…  
`tests/test_keep_older.lua:29`

**T178 [char]** T177's keys, then <M-f> back to b: <M-;><M-t> on b brings back a, then c  
`:e a`, `:e b`, `:e c`, `<M-f>`, `<M-f>`, `<M-f>`, `<M-;><M-t>`, `<M-f>` → `slots = '⦉-⦊ [b] ⟦c⟧'`  
`<M-;><M-t> (via clean)` → `slots = '⦉-⦊ [b] ⟦a⟧'`  
`<M-;><M-t> (via clean)` → `slots = '⦉-⦊ [b] ⟦c⟧'`  
spec: ("Keep the older one", Q3) T177's keys, then one more `<M-f>` back to b: `<M-;><M-t>` on b brings back a, b's secondary from before (graduation's copy, Q3): `⦉-⦊ [b] ⟦a⟧`; again, `⦉-⦊ [b] ⟦c⟧` **[sim `rt_sec_round_older`, variant `rt_c3kga`]**.  
`tests/test_keep_older.lua:39`

**T179 [char]** the round trip by plain navigation: <M-;><M-t> on d says "No secondary relationship found"  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e b`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
`<M-;><M-t> (via clean)` → `eq(K.has(msgs, 'No secondary relationship found'), true)`  
note: The round trip leaves d no secondary note to restore.  
spec: (D8) The same round trip by plain navigation: `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e b`, `:e d`, then `<M-;><M-t>` on d says "No secondary relationship found". With D8's notes written as a plain note (`dsm[A] := S`, as in `rt_base`), it throws **[sim `rt_cand_round_e`, vari…  
`tests/test_keep_older.lua:53`

**T179 [char]** the round trip by plain navigation writes D8's notes along the way (A1's example)  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
`:e b` → `slots = '⦉c⦊ [b] ⟦d⟧'`  
→ `eq(K.dsm(child), 'dsm{b>a d-swap>b}')`  
`:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq(K.dsm(child), 'dsm{b-swap>d b>a d-swap>b}')`  
spec: (D8) The same round trip by plain navigation: `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e b`, `:e d`, then `<M-;><M-t>` on d says "No secondary relationship found". With D8's notes written as a plain note (`dsm[A] := S`, as in `rt_base`), it throws **[sim `rt_cand_round_e`, vari…  
`tests/test_keep_older.lua:60`

**T180 [char]** after a round trip, the buffer's older secondary comes back  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e b`, `:e e`, `<M-f>`, `<M-f>`, `<M-f>` → `slots = '⦉b⦊ [d] ⟦e⟧'`  
`<M-;><M-t> (via clean)` → `slots = '⦉e⦊ [d] ⟦b⟧'`  
→ `eq(K.has(msgs, 'Restored secondary slot to'), true)`  
→ `eq(K.has(msgs, '(b.txt)'), true)`  
`<M-;><M-t> (via clean)` → `slots = '⦉b⦊ [d] ⟦e⟧'`  
spec: ("Keep the older one") After a round trip, the buffer's older secondary comes back: `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e b`, `:e e`, `<M-f>`, `<M-f>`, `<M-f>` give `⦉b⦊ [d] ⟦e⟧`. d remembers b, its secondary before e: `<M-;><M-t>` on d gives `⦉e⦊ [d] ⟦b⟧` ("Restored secon…  
`tests/test_keep_older.lua:71`

**T181 [char]** with nothing older on record, a stale secondary note is dropped  
`:e a`, `:e d`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦d⟧'`  
→ `eq(K.note(child, 'dsm', 'd'), 'a')`  
`:e a`, `<M-f>` → `slots = '⦉c⦊ [d] ⟦a⟧'`  
→ `eq(K.note(child, 'dsm', 'd'), nil)`  
`<M-;><M-t> (via clean)` → `eq(K.has(msgs, 'No secondary relationship found'), true)`  
note: <M-f> (d graduates, dsm{d→a}), :e a, <M-f> (to d, whose secondary is now a).  
spec: ("Keep the older one") With nothing older on record, a stale secondary note is dropped: `:e a`, `:e d`, `:e c`, `<M-f>` (d graduates, `dsm{d→a}`), `:e a`, `<M-f>` (to d, whose secondary is now a). d's note naming a is dropped, and `<M-;><M-t>` says "No secondary relationship foun…  
`tests/test_keep_older.lua:82`

**T182 [char]** the check on other arrivals, secondary map: at the last :e c the stale note is dropped  
`:e a`, `:e c`, `<M-S-f>`, `<M-S-f>`, `:e d`, `<M-f>`, `<M-;><M-f>`, `<M-;><M-r>`, `<M-S-f>`, `<M-;><M-f>`, `:e c` → `slots = '⦉d⦊ [c] ⟦a⟧'`  
→ `eq(K.note(child, 'dsm', 'c'), nil)`  
`<M-;><M-t> (via clean)` → `eq(K.has(msgs, 'No secondary relationship found'), true)`  
note: The primary queue is empty, so <M-;><M-f> acts as <M-f>.  
spec: ("Keep the older one") The check on other arrivals, secondary map: `:e a`, `:e c`, `<M-S-f>`, `<M-S-f>`, `:e d`, `<M-f>`, `<M-;><M-f>`, `<M-;><M-r>`, `<M-S-f>`, `<M-;><M-f>`, `:e c`, `<M-;><M-t>` (the primary queue is empty, so `<M-;><M-f>` acts as `<M-f>`). At the last `:e c`, c…  
`tests/test_keep_older.lua:94`

**T183 [char]** a stale secondary note is rewritten to the buffer's swap note when that names another buffer  
`:e a`, `:e e`, `<M-f>`, `:e d`, `<M-;><M-f>`, `<M-S-f>`, `<M-;><M-f>`, `<M-f>` → `slots = '⦉a⦊ [e] ⟦d⟧'`  
`<M-v>`, `<M-v>` → `slots = '⦉e⦊ [d] ⟦a⟧'`  
→ `eq(K.note(child, 'dsm', 'd'), 'e')`  
`<M-f>`, `<M-v>`, `<M-;><M-t> (via clean)` → `slots = '⦉a⦊ [d] ⟦e⟧'`  
`<M-;><M-t> (via clean)` → `slots = '⦉e⦊ [d] ⟦a⟧'`  
note: Pick a (the ternary), then d (the secondary). d's note d>a named the secondary a; it becomes d's swap note, e.  
spec: ("Keep the older one") A stale secondary note is rewritten to the buffer's swap note when that names another buffer: `:e a`, `:e e`, `<M-f>`, `:e d`, `<M-;><M-f>`, `<M-S-f>`, `<M-;><M-f>`, `<M-f>` give `⦉a⦊ [e] ⟦d⟧`. Cycle to a (the ternary) and `<M-v>`; cycle to d (the secondary…  
`tests/test_keep_older.lua:106`

**T184 [char]** graduation clears the graduated buffer's old swap note, so <M-;><M-t> brings back dtm[b]'s buffer (Q3) ⚑ state set by hand  
`:e d`, `:e a`, `:e b`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `eq(K.note(child, 'dtm', 'b'), 'a')`  
`<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
→ `eq(K.note(child, 'dsm', 'b'), 'a')`  
→ `eq(K.note(child, 'dsm', 'b-swap'), nil)`  
`<M-f>` → `slots = '⦉-⦊ [b] ⟦c⟧'`  
`<M-;><M-t> (via clean)` → `slots = '⦉-⦊ [b] ⟦a⟧'`  
note: Secondary empty, ternary b with dtm[b] = a; b's old swap note dsm[b-swap] = d is set directly.  
spec: ("Keep the older one", Q3) With the secondary empty and the ternary b holding an old swap note `dsm[b-swap]` (set it directly: with the decided cleanup, no key seems to empty a secondary once it's set **[inferred]**), `<M-f>` graduates b with `dsm[b] := dtm[b]` and clears `dsm[b-…  
`tests/test_keep_older.lua:126`

**T185 [char]** where the ternary stays put, a stale ternary note becomes the ternary's own note  
`:e a`, `:e c`, `:e e`, `:e b`, `<M-f>`, `:e c`, `<M-S-f>`, `<M-f>` → `slots = '⦉c⦊ [e] ⟦b⟧'`  
→ `eq(K.note(child, 'dtm', 'e'), 'a')`  
`<M-;><M-r> (via clean)` → `slots = '⦉a⦊ [e] ⟦b⟧'`  
`<M-;><M-r> (via clean)` → `slots = '⦉c⦊ [e] ⟦b⟧'`  
note: e's note e>c named the ternary c; it becomes c's own note, a.  
spec: ("Keep the older one") Where the ternary stays put, a stale ternary note becomes the ternary's own note: `:e a`, `:e c`, `:e e`, `:e b`, `<M-f>`, `:e c`, `<M-S-f>`, `<M-f>` give `⦉c⦊ [e] ⟦b⟧`, and e's note `e>c`, naming the ternary c, becomes c's own note, `e>a`. `<M-;><M-r>` the…  
`tests/test_keep_older.lua:142`

**T186 [char]** where the ternary changes, a stale note with nothing older is dropped (by <M-S-f>)  
`:e a`, `:e d`, `:e c`, `<M-;><M-f>`, `<M-f>`, `:e a`, `<M-S-f>` → `slots = '⦉a⦊ [d] ⟦c⟧'`  
→ `eq(K.note(child, 'dtm', 'd'), nil)`  
`<M-;><M-r> (via clean)` → `eq(K.has(msgs, 'No ternary relationship found'), true)`  
note: <M-;><M-f> on an empty queue: d graduates.  
spec: ("Keep the older one") Where the ternary changes, the check acts as navigation's does, and drops when there's nothing older: `:e a`, `:e d`, `:e c`, `<M-;><M-f>` (an empty queue, so d graduates), `<M-f>`, `:e a`, `<M-S-f>` give `⦉a⦊ [d] ⟦c⟧`. d's note `d>a` names the new ternary …  
`tests/test_keep_older.lua:153`

**T186 [char]** where the ternary changes, a stale note with nothing older is dropped (by :e d, navigation's own check)  
`:e a`, `:e d`, `:e c`, `<M-;><M-f>`, `<M-f>`, `:e a`, `:e d` → `slots = '⦉a⦊ [d] ⟦c⟧'`  
→ `eq(K.note(child, 'dtm', 'd'), nil)`  
`<M-;><M-r> (via clean)` → `eq(K.has(msgs, 'No ternary relationship found'), true)`  
note: This route goes through navigation's own stale-note check.  
spec: ("Keep the older one") Where the ternary changes, the check acts as navigation's does, and drops when there's nothing older: `:e a`, `:e d`, `:e c`, `<M-;><M-f>` (an empty queue, so d graduates), `<M-f>`, `:e a`, `<M-S-f>` give `⦉a⦊ [d] ⟦c⟧`. d's note `d>a` names the new ternary …  
`tests/test_keep_older.lua:163`

**T187 [char]** a primary jump uses navigation's second case: b's stale note becomes e, the pre-jump ternary  
`:e a`, `:e b`, `<M-;><M-c>`, `:e e`, `:e a`, `<M-;><M-f>` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
→ `primary = '[b]on'`  
→ `eq(K.note(child, 'dtm', 'b'), 'e')`  
`<M-;><M-r> (via clean)` → `slots = '⦉e⦊ [b] ⟦-⟧'`  
`<M-;><M-r> (via clean)` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
spec: ("Keep the older one") A primary jump uses navigation's second case: `:e a`, `:e b`, `<M-;><M-c>`, `:e e`, `:e a`, `<M-;><M-f>` give `⦉a⦊ [b] ⟦-⟧` with `p=[b]on`, and b's note `b>a`, naming the new ternary a, becomes e, the pre-jump ternary. `<M-;><M-r>` gives `⦉e⦊ [b] ⟦-⟧`, and …  
`tests/test_keep_older.lua:171`

**T188 [char]** where the ternary's own note is the window's secondary, the restore exchanges the ternary and the secondary  
`:e a`, `:e b`, `:e e`, `<M-f>`, `<M-f>`, `:e a`, `:e d`, `:e e`, `:e b`, `<M-;><M-t>`, `:e e` → `slots = '⦉b⦊ [e] ⟦a⟧'`  
→ `eq(K.notes_for(child, { 'a', 'b' }):match('^dtm%b{}'), 'dtm{a>b b>a}')`  
`:e a` → `slots = '⦉b⦊ [a] ⟦e⟧'`  
→ `eq(K.note(child, 'dtm', 'b'), 'e')`  
→ `eq(K.note(child, 'dtm', 'a'), 'e')`  
`<M-;><M-r> (via clean)` → `slots = '⦉e⦊ [a] ⟦b⟧'`  
`<M-;><M-r> (via clean)` → `slots = '⦉b⦊ [a] ⟦e⟧'`  
note: Plain navigation onto the secondary: Q6's guard rewrites b's note to e, and a's note a>b, naming the ternary, becomes the ternary's own note, e.  
spec: ("Keep the older one") Where the ternary's own note is the window's secondary, the restore exchanges the ternary and the secondary: `:e a`, `:e b`, `:e e`, `<M-f>`, `<M-f>`, `:e a`, `:e d`, `:e e`, `:e b`, `<M-;><M-t>`, `:e e` give `⦉b⦊ [e] ⟦a⟧` with `dtm{a>b b>a}`. Then `:e a`, …  
`tests/test_keep_older.lua:182`

**T189 [char]** (Q13) the slot exchange: b's stale note is dropped and <M-;><M-r> says "No ternary relationship found"  
`:e a`, `:e b`, `:e c`, `<M-f>`, `<M-f>`, `<M-f>`, `:e a`, `<M-f>` → `slots = '⦉c⦊ [b] ⟦a⟧'`  
→ `eq(K.note(child, 'dtm', 'b'), 'a')`  
→ `eq(K.note(child, 'dsm', 'b-swap'), 'c')`  
`<M-;><M-t> (via clean)` → `slots = '⦉a⦊ [b] ⟦c⟧'`  
`<M-;><M-r> (via clean)` → `eq(K.has(msgs, 'No ternary relationship found'), true)`  
note: c is the ternary, so the two slots exchange.  
spec: (Q13) The route the tested fix leaves: `:e a`, `:e b`, `:e c`, `<M-f>`, `<M-f>`, `<M-f>`, `:e a`, `<M-f>` give `⦉c⦊ [b] ⟦a⟧`, with b's ternary note `b>a` and its secondary swap note `b-swap>c`. `<M-;><M-t>` brings back c, which is the ternary, so the two slots exchange: `⦉a⦊ [b] …  
`tests/test_keep_older.lua:198`

**T190 [char]** I23 over random walks: one window, global view ⚑ random walk  
spec: I23 as a property test, alongside T154: random walks over `:e` on five files, `<M-f>`, `<M-S-f>`, both restores, cycling picks, `<M-;><M-c>` and `<M-;><M-f>`, in one window and across windows, with `history_view` set to `"global"` and to `"window"`. After every action, for the cu…  
`tests/test_keep_older.lua:230`

**T190 [char]** I23 over random walks: one window, window view ⚑ random walk  
spec: I23 as a property test, alongside T154: random walks over `:e` on five files, `<M-f>`, `<M-S-f>`, both restores, cycling picks, `<M-;><M-c>` and `<M-;><M-f>`, in one window and across windows, with `history_view` set to `"global"` and to `"window"`. After every action, for the cu…  
`tests/test_keep_older.lua:231`

**T190 [char]** I23 over random walks: several windows, global view ⚑ random walk  
spec: I23 as a property test, alongside T154: random walks over `:e` on five files, `<M-f>`, `<M-S-f>`, both restores, cycling picks, `<M-;><M-c>` and `<M-;><M-f>`, in one window and across windows, with `history_view` set to `"global"` and to `"window"`. After every action, for the cu…  
`tests/test_keep_older.lua:232`

**T190 [char]** I23 over random walks: several windows, window view ⚑ random walk  
spec: I23 as a property test, alongside T154: random walks over `:e` on five files, `<M-f>`, `<M-S-f>`, both restores, cycling picks, `<M-;><M-c>` and `<M-;><M-f>`, in one window and across windows, with `history_view` set to `"global"` and to `"window"`. After every action, for the cu…  
`tests/test_keep_older.lua:233`

**T335 [char]** no key raises over random walks: one window, both views ⚑ random walk  
spec: (Q13) No key raises over random walks: T190's walks (one window and several, under both views) count every key that throws, and none does. Every route that reaches a throw, an assertion included, is a bug to hunt (Q13). It found `reopen_filehash` failing on a No Name buffer with …  
`tests/test_keep_older.lua:246`

**T335 [char]** no key raises over random walks: several windows, both views ⚑ random walk  
spec: (Q13) No key raises over random walks: T190's walks (one window and several, under both views) count every key that throws, and none does. Every route that reaches a throw, an assertion included, is a bug to hunt (Q13). It found `reopen_filehash` failing on a No Name buffer with …  
`tests/test_keep_older.lua:250`

**T192 [char]** rename_hash_in_triquetras(old, new) moves dsm[old-swap] to dsm[new-swap] and renames values in both maps ⚑ state set by hand  
`:e x`, `:e b`, `:e c`, `:e d`, `:e a` → `notes = 'dtm{a-swap>b c>a} dsm{a-swap>b a>c d>a}'`  
→ `notes = 'dtm{c>x x-swap>b} dsm{d>x x-swap>b x>c}'`  
note: Set up directly: a is renamed to x.  
spec: ("Keep the older one") `rename_hash_in_triquetras(old, new)` moves `dsm[old-swap]` to `dsm[new-swap]` and renames values in both maps, as it already does for `dtm[old-swap]` (`window/data.lua:149-152`). Set it up directly, or with a No Name buffer that holds both kinds of seconda…  
`tests/test_keep_older.lua:255`

**T193 [char]** (D9) the missing-file rule on the secondary map: <M-;><M-t> says the file is missing, changes no slot, keeps both notes  
`:e f`, `:e b`, `<M-f>`, `<M-f>`, `:e e`, `<M-f>` → `slots = '⦉f⦊ [b] ⟦e⟧'`  
→ `eq(K.notes_for(child, { 'b' }):match('dsm%b{}'), 'dsm{b-swap>f b>f}')`  
→ `eq({ ok, err }, { true, nil })`  
→ `eq(K.hook_failures(msgs), {})`  
→ `slots = '⦉f⦊ [b] ⟦e⟧'`  
→ `eq(K.notes_for(child, { 'b' }):match('dsm%b{}'), 'dsm{b-swap>f b>f}')`  
note: <M-f> (f graduates), <M-f> (to f), :e e, <M-f> (to b). :bdelete f, delete f.txt on disk, and press, in one go.  
spec: (D9) The missing-file rule on the secondary map: `:e f`, `:e b`, `<M-f>` (f graduates), `<M-f>` (to f), `:e e`, `<M-f>` (to b) give `⦉f⦊ [b] ⟦e⟧` with `dsm{b-swap>f b>f}`. After `:bdelete f` and deleting f.txt on disk, `<M-;><M-t>` on b says the file is missing, changes no slot, …  
`tests/test_keep_older.lua:274`

## tests/test_cleanup.lua (15 cases: 15 char)

**T102 [char]** :bdelete of the ternary keeps it as a closed hash  
`:e a`, `:e b`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
`:bdelete b.txt` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `closed = 'b'`  
spec: `:bdelete` of the ternary's buffer keeps the ternary as a closed hash.  
`tests/test_cleanup.lua:37`

**T103 [char]** :bdelete of the secondary keeps the secondary (I4)  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
`:bdelete b.txt` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `closed = 'b'`  
spec: `:bdelete` of the secondary's buffer keeps the secondary (I4).  
`tests/test_cleanup.lua:46`

**T104 [char]** :bdelete of a primary entry keeps it in the queue (I4)  
`:e a`, `<M-;><M-c>`, `:e b`, `:e c` → `primary = '[a]on'`  
→ `slots = '⦉b⦊ [c] ⟦-⟧'`  
`:bdelete a.txt` → `primary = '[a]on'`  
spec: `:bdelete` of a primary entry's buffer keeps it in the queue (I4).  
`tests/test_cleanup.lua:55`

**T105 [char]** closing an empty No Name buffer does not push it on the closed stack  
`:e a`, `:enew`, `<M-.>` → `shown = 'a'`  
→ `closed = ''`  
spec: Closing an empty No Name buffer doesn't push it on the closed stack.  
`tests/test_cleanup.lua:64`

**T106 [char]** :file new.lua keeps unsaved edits  
`:e a`, `:file new.lua` → `eq(st.valid, true)`  
→ `eq(st.lines, { 'edited' })`  
spec: `:file new.lua` and `:saveas new.lua` keep unsaved edits.  
`tests/test_cleanup.lua:70`

**T106 [char]** :saveas new.lua keeps unsaved edits  
`:e a`, `:saveas new.lua` → `eq(st.valid, true)`  
→ `eq(st.lines, { 'edited' })`  
→ `eq(child.lua('return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")'), 'new.lua')`  
spec: `:file new.lua` and `:saveas new.lua` keep unsaved edits.  
`tests/test_cleanup.lua:80`

**T107 [char]** a rename whose old file is gone moves every reference and pushes nothing ⚑ state set by hand  
`:e a`, `:e b`, `<M-;><M-c>`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `primary = '[b]on'`  
→ `notes = 'dtm{b>a} dsm{}'`  
→ `slots = '⦉g⦊ [c] ⟦-⟧'`  
→ `primary = '[g]on'`  
→ `notes = 'dtm{g>a} dsm{}'`  
→ `closed = ''`  
note: b is the ternary, the primary and a note's key; it's moved on disk to g.txt and renamed in place, the way LSP and oil renames do (nvim_buf_set_name).  
spec: After a rename whose old file is gone, every reference to the old hash follows to the new one, and nothing is pushed on the closed stack.  
`tests/test_cleanup.lua:93`

**T108 [char]** cleanup re-points the current slot to the registered buffer the window shows ⚑ state set by hand  
`:e a`, `:e b`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
`:noautocmd buffer a.txt`, `:bwipeout c.txt` → `eq(current(), 'a')`  
note: The window is put on a without a BufEnter, then c's buffer goes: cleanup finds the current slot's buffer gone and the window showing a.  
spec: When a window shows registered buffer X while its current slot's buffer is gone, cleanup sets `c := X`.  
`tests/test_cleanup.lua:112`

**T109 [char]** a new unsaved file keeps its buffer, text and tracking after :e a (I12)  
`:edit brandnew.txt`, `:e a` → `eq(buffer_state('brandnew.txt'), { valid = true, lines = { 'hello' }, registered = true, in_history = true })`  
spec: `:e brandnew.txt`, type a line, `:e a.txt`: the brandnew buffer still exists with its text and stays tracked (I12).  
`tests/test_cleanup.lua:121`

**T110 [char]** a file deleted on disk while shown stays shown and tracked after 4.6 s  
`:e a`, `:e b` → `shown = 'b'`  
→ `slots = '⦉a⦊ [b] ⟦-⟧'`  
→ `eq({ st.valid, st.registered, st.in_history }, { true, true, true })`  
spec: A file deleted on disk while shown stays shown and tracked after a 4.6 s wait.  
`tests/test_cleanup.lua:130`

**T111 [char]** :bdelete of the shown buffer lands the window on its ternary ⚑ route changed so it fails for the right reason (the first route passed by luck)  
`:e a`, `:e b`, `:e c`, `:e d`, `:e c`, `<M-;><M-r>` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
`:bdelete c.txt` → `shown = 'b'`  
note: The ternary restore puts b in the ternary while the buffer last left is d, which is where Neovim's own pick (the jumplist) goes. Neovim closes any other window that shows the deleted buffer, so this is the one-window case.  
spec: `:bdelete` of the shown buffer lands that window, not the focused one, on ternary → secondary → primary → most recent.  
`tests/test_cleanup.lua:143`

**T112 [char]** opening a closed file again with :e takes it off the closed stack  
`:e a`, `:e b`, `:e c`, `:bdelete b.txt` → `closed = 'b'`  
`:e b` → `closed = ''`  
spec: Opening a closed file again with `:e` takes it off the closed stack (`track_buffer`).  
`tests/test_cleanup.lua:151`

**T113 [char]** a stale registration re-points to a copy reloaded under noautocmd and wipes nothing ⚑ state set by hand  
`:e a`, `:e b`, `:e c` → `eq(got, { copy_open = true, points_at_copy = true })`  
note: b's buffer is wiped without events and a copy of b.txt loaded the same way, so the registry still holds the old buffer number. Then the timer's pass.  
spec: A stale registration with a copy reloaded under `noautocmd` re-points to the copy and wipes nothing.  
`tests/test_cleanup.lua:162`

**T114 [char]** a closed entry whose file is gone from disk stays on the stack  
`:e a`, `:e b`, `:e c`, `:bdelete b.txt` → `closed = 'b'`  
→ `closed = 'b'`  
spec: A closed entry whose file is gone from disk stays on the stack, after a `cleanup_system` pass (A22).  
`tests/test_cleanup.lua:182`

**T163 [char]** a re-point to the shown buffer moves the old current into the ternary (Q18) ⚑ state set by hand  
`:e d`, `:e b`, `:e c`, `<M-f>`, `:e a` → `slots = '⦉c⦊ [a] ⟦b⟧'`  
`:noautocmd buffer d.txt`, `:bwipeout a.txt` → `slots = '⦉a⦊ [d] ⟦b⟧'`  
note: {c=A s=S t=T} is {c=a s=b t=c}; X is d, outside the slots. The window is put on d without a BufEnter, then a's buffer is wiped (A21 step 1 re-points).  
spec: When cleanup re-points a window's current slot to the registered buffer X the window shows (A21 step 1), with X outside the slots, `{c=A s=S t=T}` becomes `{c=X s=S t=A}`, as plain navigation would. Set it up by showing X without a `BufEnter` (`noautocmd`) after A's buffer is gon…  
`tests/test_cleanup.lua:195`

## tests/test_closing.lua (21 cases: 21 char)

**T80 [char]** <M-.> on the newest lands on the next, closes it, and keeps it in the ternary  
`:e d`, `:e e`, `:e f` → `ordered = 'f,e,d'`  
`<M-.>` → `shown = 'e'`  
→ `closed = 'f'`  
→ `slots = '⦉f⦊ [e] ⟦-⟧'`  
→ `eq(buf_open(f), false)`  
spec: With order `f,e,d`, `<M-.>` on f lands on e, pushes f on the closed stack, and leaves f in the ternary as a closed hash.  
`tests/test_closing.lua:43`

**T336 [char]** (A15, A1) <M-.> lands by navigation, before the close: no healing notice  
`:e a`, `:e b`, `:e c`, `<M-.>` → `slots = '⦉c⦊ [b] ⟦-⟧'`  
→ `eq(healed, false)`  
note: The switch's arrival is slotted before the close, as navigation slots it, so cleanup has nothing to heal and says nothing.  
spec: (A15, A1) `<M-.>` lands by navigation, before the close: `:e a`, `:e b`, `:e c`, `<M-.>` give `⦉c⦊ [b] ⟦-⟧` with no "Healed the triquetra…" notice. The close waits for the editor to settle, after the switch's arrival (A15 step 3). Found by the step 3 spec pass, 2026-10-23: with t…  
`tests/test_closing.lua:56`

**T81 [char]** <M-.> on entry i > 1 lands on entry i + 1  
`:e a`, `:e b`, `:e c`, `:e d`, `:e e`, `:e f` → `ordered = 'f,e,d,c,b,a'`  
`<M-m>` → `shown = 'e'`  
`<M-.>` → `shown = 'd'`  
→ `closed = 'e'`  
note: The window's buffer is entry i > 1 of the ordered list while cycling, which freezes the order.  
spec: On entry i > 1 it lands on i + 1, and on the oldest it lands on the newest.  
`tests/test_closing.lua:70`

**T81 [char]** <M-.> on the oldest entry lands on the newest  
`:e a`, `:e b`, `:e c`, `:e d`, `:e e`, `:e f` → `ordered = 'f,e,d,c,b,a'`  
`<M-n>` → `shown = 'a'`  
`<M-.>` → `shown = 'f'`  
→ `closed = 'a'`  
spec: On entry i > 1 it lands on i + 1, and on the oldest it lands on the newest.  
`tests/test_closing.lua:80`

**T82 [char]** <M-.> refuses a modified named buffer  
`:e a`, `:e b`, `<M-.>` → `eq(Extra.has(child.messages(), 'Buffer has unsaved changes'), true)`  
→ `eq(snapshot(), before)`  
spec: It refuses with a modified named buffer, a buffer shown in two windows, or a single entry, each with its warning and nothing changed.  
`tests/test_closing.lua:90`

**T82 [char]** <M-.> refuses a buffer shown in two windows  
`:e a`, `:e b`, `:vsplit`, `<M-.>` → `eq(Extra.has(child.messages(), "Can't delete buffer because it's shown in another window."), true)`  
→ `eq(snapshot(), before)`  
→ `eq(#child.lua('return vim.api.nvim_list_wins()'), 2)`  
spec: It refuses with a modified named buffer, a buffer shown in two windows, or a single entry, each with its warning and nothing changed.  
`tests/test_closing.lua:101`

**T82 [char]** <M-.> refuses the only entry  
`:e a`, `<M-.>` → `eq(Extra.has(child.messages(), "Can't delete buffer because it's the only one left"), true)`  
→ `eq(snapshot(), before)`  
spec: It refuses with a modified named buffer, a buffer shown in two windows, or a single entry, each with its warning and nothing changed.  
`tests/test_closing.lua:113`

**T83 [char]** <M-.> on a modified No Name buffer closes it and caches its lines, filetype and cursor  
`:e a` → `eq(type(h), 'string')`  
→ `eq(child.lua('return vim.bo.modified'), true)`  
→ `eq(child.lua('return vim.api.nvim_win_get_cursor(0)'), { 2, 1 })`  
`<M-.>` → `eq(child.lua('return vim.api.nvim_buf_is_valid(...)', { buf }), false)`  
→ `eq(child.lua('return require("cavediver.domains.history").data.closed_buffers'), { h })`  
→ `eq(`  
note: delete_buffer keeps the cursor before it switches the window away (history/routines.lua:709), so the cache doesn't fall back to {1,0}.  
spec: On a modified No Name buffer it closes it and caches its lines, filetype and cursor. `delete_buffer` switches the window away before the wipe, so it keeps the cursor on the buffer first (`vim.b[bufnr].cavediver_cursor`), and the cursor doesn't come back as `{1,0}` (bug, found 202…  
`tests/test_closing.lua:124`

**T84 [char]** <M-.> in :help does not throw  
`:e a`, `:e b`, `:help` → `eq(child.lua('return vim.bo.buftype'), 'help')`  
`<M-.>` → `eq({ ok, err }, { true, nil })`  
→ `eq(Extra.at_least(child.messages()), {})`  
spec: In `:help` it doesn't throw. What it does instead is T164–T167 (Q17).  
`tests/test_closing.lua:141`

**T85 [char]** <M-.> on a file keeps its marks for when it is reopened  
`:e a`, `:e b` → `eq(child.lua('return vim.api.nvim_buf_get_mark(0, "k")'), { 1, 0 })`  
`<M-.>` → `shown = 'a'`  
`<M-S-w>` → `shown = 'b'`  
→ `eq(child.lua('return vim.api.nvim_buf_get_mark(0, "k")'), { 1, 0 })`  
spec: `<M-.>` on a file keeps the buffer's marks for when it's reopened (`:bdelete`).  
`tests/test_closing.lua:152`

**T86 [char]** <M-S-w> reopens the newest closed buffer as current, the old current in the ternary  
`:e d`, `:e e`, `:e f`, `<M-.>` → `shown = 'e'`  
→ `closed = 'f'`  
`<M-S-w>` → `shown = 'f'`  
→ `slots = '⦉e⦊ [f] ⟦-⟧'`  
→ `closed = ''`  
spec: `<M-S-w>` reopens the newest closed buffer, and it becomes current with the old current in the ternary.  
`tests/test_closing.lua:163`

**T87 [char]** <M-S-w> with an empty closed stack warns  
`:e a`, `<M-S-w>` → `eq(Extra.has(msgs, 'No closed buffers to reopen.'), true)`  
→ `eq(Extra.at_least(msgs, vim.log.levels.WARN), { 'No closed buffers to reopen.' })`  
→ `shown = 'a'`  
spec: `<M-S-w>` with an empty stack warns "No closed buffers to reopen."  
`tests/test_closing.lua:173`

**T88 [char]** a No Name buffer closed with text comes back with the same lines and filetype  
`:e a`, `<M-.>` → `shown = 'a'`  
`<M-S-w>` → `eq(child.lua('return vim.api.nvim_buf_get_name(0)'), '')`  
→ `eq(child.lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'first line', 'second line' })`  
→ `eq(child.lua('return vim.bo.filetype'), 'markdown')`  
spec: A No Name buffer closed with text comes back with the same lines and filetype.  
`tests/test_closing.lua:183`

**T89 [char]** <M-S-w> on a missing file says so and leaves the entry on the stack  
`:e d`, `:e e`, `:e f`, `<M-.>` → `closed = 'f'`  
`<M-S-w>` → `eq({ ok, err }, { true, nil })`  
→ `eq(said, true)`  
→ `closed = 'f'`  
spec: `<M-S-w>` on a missing file says so and leaves the entry on the stack.  
`tests/test_closing.lua:194`

**T90 [char]** a reopened No Name buffer gets its cursor in its own window  
`:e a`, `<M-.>` → `shown = 'a'`  
`<M-S-w>` → `eq({ ok, err }, { true, nil })`  
→ `eq(Extra.at_least(child.messages()), {})`  
→ `eq(child.lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'one', 'two', 'three' })`  
→ `eq(child.lua('return vim.api.nvim_win_get_cursor(0)'), { 3, 2 })`  
note: Cursor on line 3; a.txt, where <M-.> lands, has one line.  
spec: A reopened No Name buffer gets its cursor in its own window, with no "Invalid cursor line".  
`tests/test_closing.lua:209`

**T91 [char]** after a No Name buffer is reopened, its old hash is renamed everywhere ⚑ state set by hand  
`:e a`, `:e b`, `:e c`, `<M-.>` → `shown = 'c'`  
→ `eq(child.lua('return require("cavediver.domains.window").data.crux[vim.api.nvim_get_current_win()].ternary_slot'), old)`  
→ `eq(child.lua('return require("cavediver.domains.window").data.crux[vim.api.nvim_get_current_win()].displacement_ternary_map[...]', { child.hash_of('b'`  
`<M-S-w>` → `eq(child.lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'scratch text' })`  
→ `eq(new ~= old, true)`  
→ `eq(child.refs(old), {})`  
→ `eq(child.lua('return require("cavediver.domains.window").data.crux[vim.api.nvim_get_current_win()].displacement_ternary_map[...]', { child.hash_of('b'`  
note: b is left while the No Name buffer is its ternary, so dtm[b] names it; then the No Name buffer is closed from c, where it lands in the ternary.  
spec: After a No Name buffer is reopened, every slot and map entry that held its old hash holds the new one.  
`tests/test_closing.lua:223`

**T162 [char]** pushing a hash already on the closed stack keeps one copy, as the newest  
`:e a` → `eq(got, true)`  
→ `closed = 't,x'`  
spec: (Q15) I22: pushing a hash that's already on the closed stack (for example, `track_closing_filehash_force` on x, t, then x again) leaves it on the stack once, as the newest entry: `t,x`. With pools: closing `notes.md` in two tabs' pools and merging both entries leaves one, the new…  
`tests/test_closing.lua:245`

**T164 [char]** <M-.> in a window visiting an untracked buffer closes it and lands on the current slot  
`:e b`, `:e a`, `<M-f>` → `slots = '⦉-⦊ [a] ⟦b⟧'`  
→ `eq(child.lua('return vim.bo.buftype'), 'nofile')`  
`<M-.>` → `eq({ ok, err }, { true, nil })`  
→ `eq(Extra.at_least(child.messages()), {})`  
→ `eq(child.lua('return vim.api.nvim_buf_is_loaded(...)', { scratch }), false)`  
→ `shown = 'a'`  
→ `slots = '⦉-⦊ [a] ⟦b⟧'`  
note: Visit a nofile scratch in the same window.  
spec: Q17, a visiting window: in a window with `{c=a s=b}` that's visiting an untracked buffer (a `nofile` scratch, or help shown with `:buffer`), `<M-.>` closes the visited buffer, and the window shows a with `{c=a s=b}` intact (A2, A15, T27).  
`tests/test_closing.lua:263`

**T165 [char]** <M-.> in a help window closes the help buffer and leaves a alone  
`:e a`, `:help` → `eq(child.lua('return vim.bo.buftype'), 'help')`  
`<M-.>` → `eq({ ok, err }, { true, nil })`  
→ `eq(Extra.at_least(child.messages()), {})`  
→ `eq(child.lua('return vim.api.nvim_buf_is_loaded(...)', { help_buf }), false)`  
→ `eq(child.lua('return vim.api.nvim_list_wins()'), { a_win })`  
→ `shown = 'a'`  
→ `slots = '⦉-⦊ [a] ⟦-⟧'`  
spec: Q17, a window born untracked: `:e a`, `:help`, then `<M-.>` in the help window. The help buffer is closed, Neovim closes the help window, nothing throws, and a's window and triquetra are unchanged.  
`tests/test_closing.lua:283`

**T166 [char]** <M-.> on help in the only window closes the help buffer  
`:help`, `:only` → `eq(child.lua('return vim.bo.buftype'), 'help')`  
`<M-.>` → `eq({ ok, err }, { true, nil })`  
→ `eq(child.lua('return vim.api.nvim_buf_is_loaded(...)', { help_buf }), false)`  
→ `eq(#child.lua('return vim.api.nvim_list_wins()'), 1)`  
→ `eq(Extra.at_least(child.messages()), {})`  
spec: Q17, the only window: `:help`, `:only`, `<M-.>`. The help buffer is closed, nothing throws, and the window shows what Neovim picks.  
`tests/test_closing.lua:300`

**T167 [char]** <M-.> on a running terminal refuses with a message  
`:e a`, `:e b`, `:terminal sleep 1000` → `eq(child.lua('return vim.bo.buftype'), 'terminal')`  
→ `eq(child.lua('return vim.fn.jobwait({ vim.bo.channel }, 0)[1]'), -1)`  
`<M-.>` → `eq({ ok, err }, { true, nil })`  
→ `eq(#Extra.at_least(child.messages(), vim.log.levels.WARN) > 0, true)`  
→ `eq(child.lua('return vim.api.nvim_buf_is_valid(...) and vim.api.nvim_get_current_buf() == ...', { term }), true)`  
spec: Q17, a running terminal: `<M-.>` on a `:terminal` whose job is still running refuses with a message, and the terminal stays.  
`tests/test_closing.lua:314`

## tests/test_cycling.lua (27 cases: 22 char, 5 target)

**T69 [char]** <M-m> from normal starts cycling and leaves the current slot  
`:e a`, `:e b`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
`<M-m>` → `eq(child.state(), CYCLING)`  
→ `eq(Extra.has(child.messages(), 'Checkpoint saved'), true)`  
→ `shown = 'b'`  
→ `slots = '⦉b⦊ [c] ⟦-⟧'`  
spec: `<M-m>` from normal sets navigation `cycling` and history `detached`, notifies "Checkpoint saved", moves the window to another buffer, and leaves `c` unchanged.  
`tests/test_cycling.lua:48`

**T70 [char]** further steps change neither the slots nor the history order  
`:e a`, `:e b`, `:e c`, `<M-m>` → `eq({ child.slots(), child.notes(), child.ordered() }, { slots, notes, ordered })`  
→ `eq(child.state(), CYCLING)`  
spec: Further steps change neither the slots nor the history order.  
`tests/test_cycling.lua:59`

**T71 [char]** with one buffer in history, <M-m> enters cycling without moving  
`:e a`, `<M-m>` → `eq(child.state(), CYCLING)`  
→ `shown = 'a'`  
→ `slots = '⦉-⦊ [a] ⟦-⟧'`  
spec: With one buffer in history, `<M-m>` enters cycling without moving.  
`tests/test_cycling.lua:69`

**T72 [char]** a pick of an outside buffer: the start leaves, the ternary stays  
`<M-n>`, `<M-n>` → `shown = 'b'`  
`<M-v>` → `slots = '⦉d⦊ [b] ⟦c⟧'`  
→ `eq(child.state(), NORMAL)`  
spec: `{c=e s=c t=d}`, cycle to b, `<M-v>` → `{c=b s=c t=d}`. The ternary isn't updated by the pick (Q9); the note it adds is T155.  
`tests/test_cycling.lua:77`

**T73 [char]** a pick of the secondary swaps them, with no map writes  
`<M-m>`, `<M-m>` → `shown = 'c'`  
`<M-v>` → `slots = '⦉d⦊ [c] ⟦e⟧'`  
→ `notes = notes`  
spec: Cycling to the secondary and pressing `<M-v>` swaps them, with no map writes.  
`tests/test_cycling.lua:86`

**T74 [char]** a pick of the ternary swaps them, with the start's swap note  
`<M-m>` → `shown = 'd'`  
`<M-v>` → `slots = '⦉e⦊ [d] ⟦c⟧'`  
→ `eq(child.note('dtm', 'e-swap'), 'd')`  
spec: Cycling to the ternary and pressing `<M-v>` swaps them, with `dtm{start-swap→ternary}`.  
`tests/test_cycling.lua:96`

**T75 [char]** <M-v> on the start changes no slot and ends the cycle  
`<M-m>`, `<M-n>` → `shown = 'e'`  
`<M-v>` → `slots = '⦉d⦊ [e] ⟦c⟧'`  
→ `eq(child.state(), NORMAL)`  
spec: Pressing `<M-v>` on the cycle's start changes no slot; navigation goes back to `normal` and history to `attached`.  
`tests/test_cycling.lua:105`

**T76 [char]** <M-v> in normal mode does nothing  
`<M-v>` → `eq({ child.slots(), child.notes(), child.shown(), child.ordered() }, before)`  
→ `eq(child.state(), NORMAL)`  
spec: `<M-v>` in normal mode does nothing.  
`tests/test_cycling.lua:114`

**T77 [char]** <M-f> while cycled away switches back to the start and stays cycling  
`<M-m>` → `shown = 'd'`  
`<M-f>` → `shown = 'e'`  
→ `slots = '⦉d⦊ [e] ⟦c⟧'`  
→ `eq(child.state(), CYCLING)`  
spec: `<M-f>` while cycled away from the start switches back to the start and stays `cycling` (Q7).  
`tests/test_cycling.lua:124`

**T78 [char]** <M-S-f> while cycling, on the current slot, swaps the ternary and stays cycling  
`<M-m>`, `<M-f>` → `shown = 'e'`  
`<M-S-f>` → `slots = '⦉e⦊ [d] ⟦c⟧'`  
→ `eq(child.note('dtm', 'e-swap'), 'd')`  
→ `shown = 'd'`  
→ `eq(child.state(), CYCLING)`  
note: Cycle away, then <M-f> back onto the current slot.  
spec: `<M-S-f>` while cycling, with the window on its current slot, swaps the ternary and stays `cycling` (Q7).  
`tests/test_cycling.lua:134`

**T195 [char]** the cycle's start is the window's current slot, live  
`<M-n>`, `<M-S-f>` → `shown = 'c'`  
`<M-S-f>` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
`<M-n>` → `eq(child.shown() ~= 'd', true)`  
`<M-;><M-f>` → `shown = 'd'`  
→ `eq(child.state(), CYCLING)`  
spec: (D15) The cycle's start is the window's current slot, live: `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e c` give `⦉d⦊ [c] ⟦b⟧`. `<M-n>`, `<M-S-f>` (back to the start), `<M-S-f>` again (a real swap on the start: `⦉c⦊ [d] ⟦b⟧`), `<M-n>`, then `<M-;><M-f>` returns the window to d, t…  
`tests/test_cycling.lua:146`

**T196 [char]** while cycling, on the current slot, <M-f> and <M-;><M-r> do their normal job  
`<M-n>` → `eq(child.state(), CYCLING)`  
`<M-f>` → `shown = 'c'`  
→ `slots = '⦉d⦊ [c] ⟦b⟧'`  
→ `eq(child.state(), CYCLING)`  
`<M-f>` → `slots = '⦉d⦊ [b] ⟦c⟧'`  
→ `eq(child.note('dsm', 'c-swap'), 'b')`  
→ `eq(child.state(), CYCLING)`  
`<M-;><M-r>` → `slots = '⦉a⦊ [b] ⟦c⟧'`  
… and 1 more  
note: c's secondary note names b: <M-f> writes the swap note (D8, T191).  
spec: (P18) While cycling, with the window back on its current slot, `<M-f>` and `<M-;><M-r>` do their normal job, notes included: set up with `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e c` (`⦉d⦊ [c] ⟦b⟧`, with b's note `b>a`), then `<M-n>` and a first `<M-f>` that only takes the wind…  
`tests/test_cycling.lua:159`

**T175 [char]** jumping to another window cancels the cycle  
`:e a`, `:e b`, `:vsplit`, `:e x`, `:wincmd p`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `slots = '⦉b⦊ [x] ⟦-⟧'`  
→ `ordered = 'c,b,x,a'`  
`<M-n>` → `shown = 'a'`  
`:wincmd p` → `eq(child.win(), win2)`  
→ `shown = 'c'`  
→ `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `eq(child.state(), NORMAL)`  
… and 3 more  
note: win1: ⦉b⦊ [c] ⟦-⟧; win2: ⦉b⦊ [x] ⟦-⟧. Nothing was recorded for a, the cycled-to buffer: it's still the oldest.  
spec: (A12) Cycling in win1, then `<C-w>p` to win2: win1 shows its start again, navigation is `normal`, history is attached, and nothing was recorded for the cycled-to buffer. Then `:e d` in win2 moves win2's slots and records d.  
`tests/test_cycling.lua:177`

**T176 [char]** <M-f> fills an empty secondary from the ordered list, asserting its first entry  
`:e a`, `:e b`, `:vsplit` → `slots = '⦉-⦊ [b] ⟦-⟧'`  
→ `ordered = 'b,a'`  
`<M-f>` → `slots = '⦉-⦊ [b] ⟦a⟧'`  
`:e a`, `:e b`, `:vsplit`, `<M-f> (via _G.CDV_TEST.press)` → `eq(res[1], false)`  
note: A fresh split: an empty secondary and no ternary. Again from a fresh split, with the ordered list's first two entries swapped by hand, so its first entry isn't the window's current buffer.  
spec: (D11) With an empty secondary and no ternary, `<M-f>` fills from the ordered list's second entry, and throws if the first entry isn't the window's current buffer.  
`tests/test_cycling.lua:208`

**T197 [char]** under the window view the ordered list never ties after two splits  
`:e a`, `:e b`, `:vsplit`, `:wincmd p`, `:e c`, `:vsplit`, `<M-f>` → `eq(runs[i], { first_is_shown = true, ok = true, errors = {}, distinct = true })`  
spec: (D11) Under `history_view = "window"`, after `:e a`, `:e b`, `:vsplit`, `<C-w>p`, `:e c`, `:vsplit`, the ordered list's first entry is the window's current buffer on every run (no tie), and `<M-f>` doesn't trip the fill assertion.  
`tests/test_cycling.lua:232`

**T198 [char]** a jump away from a cycle records the landing, and <M-f> there fills  
`:e a`, `:vsplit`, `:e c` → `slots = '⦉a⦊ [c] ⟦-⟧'`  
`<M-m>` → `shown = 'a'`  
`:wincmd p` → `eq(child.win(), win1)`  
→ `shown = 'c'`  
→ `eq(child.state(), NORMAL)`  
→ `eq(child.ordered():match('^[^,]*'), 'a')`  
`<M-f>` → `eq({ ok, err }, { true, nil })`  
→ `slots = '⦉-⦊ [a] ⟦c⟧'`  
note: The cycle in the second window is cancelled. The landing in the first window is recorded.  
spec: (A12) `:e a`, `:vsplit`, `:e c`, `<M-m>`, `<C-w>p`: the cycle in the second window is cancelled (it's back on c), the landing in the first window is recorded (the ordered list starts with a), and `<M-f>` there fills c without tripping the fill assertion.  
`tests/test_cycling.lua:262`

**T206 [char]** the secondary restore's exchange rewrites b's stale note to e's own note  
`:e a`, `:e e`, `:e d`, `<M-S-f>`, `:e b`, `:e d`, `<M-n>`, `<M-v>`, `<M-f>`, `:e b`, `<M-f>`, `:e e`, `<M-m>`, `<M-m>`, `<M-v>` → `slots = '⦉a⦊ [b] ⟦e⟧'`  
`<M-;><M-t>` → `slots = '⦉e⦊ [b] ⟦a⟧'`  
→ `eq(child.note('dtm', 'e'), 'd')`  
→ `eq(child.note('dtm', 'b'), 'd')`  
`<M-;><M-r>` → `eq({ ok, err }, { true, nil })`  
→ `slots = '⦉d⦊ [b] ⟦a⟧'`  
`<M-;><M-r>` → `eq({ ok, err }, { true, nil })`  
→ `slots = '⦉e⦊ [b] ⟦a⟧'`  
spec: (I23) `:e a`, `:e e`, `:e d`, `<M-S-f>`, `:e b`, `:e d`, `<M-n> <M-v>`, `<M-f>`, `:e b`, `<M-f>`, `:e e`, `<M-m> <M-m> <M-v>`, `<M-;><M-t>`: b's stale note becomes e's own note, d; `<M-;><M-r>` gives `⦉d⦊ [b] ⟦a⟧`, and again `⦉e⦊ [b] ⟦a⟧`.  
`tests/test_cycling.lua:286`

**T171 [char]** with no cokeline, <M-n> and <M-m> step through the ordered history as with it ⚑ random walk  
→ `eq(with_cokeline.shown, { 'c', 'b', 'c' })`  
→ `eq(with_cokeline.slots, '⦉d⦊ [c] ⟦-⟧')`  
→ `eq(with_cokeline.state, NORMAL)`  
→ `eq(child.lua('return (pcall(require, "cokeline.mappings"))'), false)`  
→ `eq(cycle_walk(), with_cokeline)`  
note: d,c,b,a: <M-m> twice to b, <M-n> back to c, then <M-v> picks c, the ternary.  
spec: (A12) With no cokeline installed, `<M-n>` and `<M-m>` step through cavediver's ordered history in the same directions as with cokeline, and `<M-v>` picks as usual. **[run s21]** recorded the step only printing, before the fallback, and navigation staying in `cycling`.  
`tests/test_cycling.lua:317`

**T79 [char]** <M-n> steps left, toward newer buffers, and <M-m> right, toward older  
`:e a`, `:e b`, `:e c` → `eq(cmp, { c_before_b = true, b_before_a = true, a_before_c = false })`  
`<M-m>` → `shown = 'b'`  
`<M-m>` → `shown = 'a'`  
`<M-n>` → `shown = 'b'`  
→ `eq(child.lua('return _G.CDV_STEPS'), { 1, 1, -1 })`  
note: Runs against the stub, not the real cokeline: checks the step each key asks cokeline for, and that cavediver's bufferline order puts the newer buffer on the left.  
spec: Through the real cokeline order, `<M-n>` steps left, toward newer buffers, and `<M-m>` steps right, toward older ones (Q19).  
`tests/test_cycling.lua:329`

**T152 [char]** a cycling pick of the secondary rewrites the ternary's note to the start  
`:e a`, `:e b`, `:e c`, `:e b`, `<M-f>`, `:e a`, `<M-f>` → `slots = '⦉b⦊ [c] ⟦a⟧'`  
→ `eq(child.note('dtm', 'b'), 'a')`  
`<M-m>` → `shown = 'a'`  
`<M-v>` → `slots = '⦉b⦊ [a] ⟦c⟧'`  
→ `eq(child.note('dtm', 'b'), 'c')`  
note: {c=c s=a t=b} with dtm[b] = a.  
spec: Q6 on a cycling pick of the secondary: with `{c=A s=S t=T}` and `dtm[T] = S`, cycling to S and pressing `<M-v>` gives `{c=S s=A t=T}` and rewrites `dtm[T]` to A. The guard's warning comes with the rewrite: the conflict is real and the warning isn't spurious (A6). With the guard a…  
`tests/test_cycling.lua:365`

**T172 [char]** a pick of an outside buffer writes its plain note and clears its swap note  
`:e a`, `:e b`, `<M-S-f>` → `eq(child.note('dtm', 'b-swap'), 'a')`  
`:e c`, `:e d`, `:e e` → `slots = '⦉d⦊ [e] ⟦-⟧'`  
`<M-n>` → `shown = 'b'`  
`<M-v>` → `slots = '⦉d⦊ [b] ⟦-⟧'`  
→ `eq(child.note('dtm', 'b'), 'e')`  
→ `eq(child.note('dtm', 'b-swap'), '-')`  
`<M-;><M-r>` → `slots = '⦉e⦊ [b] ⟦-⟧'`  
`<M-;><M-r>` → `slots = '⦉d⦊ [b] ⟦-⟧'`  
… and 1 more  
spec: (Q9) `:e a`, `:e b`, `<M-S-f>` (b gets `dtm[b-swap]=a`), `:e c`, `:e d`, `:e e`, cycle to b, `<M-v>`: `dtm[b] = e` and no `dtm[b-swap]`; `<M-;><M-r>` gives `t=e`, again `t=d`, again `t=e`.  
`tests/test_cycling.lua:378`

**T155 [char]** a pick of an outside buffer notes the start, and <M-;><M-r> brings it back  
→ `eq(child.note('dtm', 'b-swap'), '-')`  
`<M-n>`, `<M-n>` → `shown = 'b'`  
`<M-v>` → `slots = '⦉d⦊ [b] ⟦c⟧'`  
→ `eq(child.note('dtm', 'b'), 'e')`  
`<M-;><M-r>` → `slots = '⦉e⦊ [b] ⟦c⟧'`  
→ `eq(child.note('dtm', 'b'), 'd')`  
spec: `{c=e s=c t=d}` with no `dtm[b-swap]`: cycle to b, `<M-v>` → `{c=b s=c t=d}` and `dtm[b] = e`. Then `<M-;><M-r>` brings the start back: `{c=b s=c t=e}`, with `dtm{b→d}` by the flip-flop (Q9).  
`tests/test_cycling.lua:397`

**T200 [target]** the restore assertion dumps the last steps to a file and a scratch buffer  
`:e a`, `:e b`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
`<M-;><M-t>` → `eq(ok, false)`  
→ `eq(err:find('Remembered secondary is the same as current secondary', 1, true) ~= nil, true)`  
→ `eq(#files > 0, true)`  
→ `eq(row ~= nil, true)`  
→ `eq(found, true)`  
note: A file whose last row is the failing step, on c's slots. A scratch buffer holds the same rows.  
spec: (A26) When the restore assertion fires, a file appears under `stdpath("state")/cavediver/` and a scratch buffer opens, both holding the last steps as rows: action or event, window, `⦉t⦊ [c] ⟦s⟧` and notes, ending at the failing step.  
`tests/test_cycling.lua:450`

**T203 [target]** a planted rule break dumps at the next step ⚑ state set by hand  
`:e a`, `:e b`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
`:vsplit`, `:e d`, `:e e`, `:e x` → `eq(#Extra.new_files(before, child.dumps()), 1)`  
note: A planted stale note, not a real route: every real route into a rule break is one the decided fixes remove, so the recorder is tested on its own. The note is planted in the other window, so the step taken in this window can't repair it first. Plant in the first window: c's ternary note names b, whic  
spec: (A26) A planted rule break dumps at the next step: with c current in one window and b its ternary, c's ternary note is set to b by hand, and a step in the other window (`:e x`) produces one dump. The break is planted because every real route into one is a route the decided fixes …  
`tests/test_cycling.lua:486`

**T204 [target]** a session load and a cleanup re-point appear in the dump, tagged load and timer ⚑ state set by hand  
`:e a`, `:e b`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
→ `eq(other.slots(), '⦉-⦊ [c] ⟦b⟧')`  
→ `eq(other.slots(win2), '⦉c⦊ [x] ⟦-⟧')`  
→ `eq(other.slots(win2):match('%[(.-)%]'), 'c')`  
→ `eq(other.win(), win1)`  
`<M-;><M-t> (via other.step)` → `eq(ok, false)`  
→ `eq(tagged, true)`  
note: Save a session from this child... ...and load it in a second one, with the files open as a session manager would leave them.  
spec: (A26) A session load and a cleanup re-point appear in the dump as steps tagged `load` and `timer`.  
`tests/test_cycling.lua:501`

**T205 [target]** a failure that repeats gives one dump, and the dump window is nofile, unlisted, untracked and unrecorded ⚑ state set by hand  
→ `eq(errs, 10)`  
→ `eq(#Extra.new_files(files_before, child.dumps()), 1)`  
→ `eq(#scratch > 0, true)`  
→ `eq(child.lua('return { vim.bo[...].buftype, vim.bo[...].buflisted }', { b, b }), { 'nofile', false })`  
→ `eq(child.lua('return require("cavediver.domains.history").get_hash_from_buffer(...)', { b }), vim.NIL)`  
→ `eq(child.lua('return require("cavediver.domains.window").data.crux[...] == nil', { w }), true)`  
→ `ordered = ''`  
`:wincmd p`, `:e a`, `:e b` → `eq(#second > 0, true)`  
… and 2 more  
note: Nothing tracked yet, so the bufferline's colour callback throws on every call, as it would on every redraw. Entering the dump window isn't recorded: after a visit there, a second,  
spec: (A26) A failure that repeats (a highlight callback throwing on every redraw) gives one dump, and the dump window is neither recorded nor tracked: its buffer is `nofile` and unlisted, with no hash, no triquetra and no place in the bufferline, and after a visit to its window, a sec…  
`tests/test_cycling.lua:563`

**T333 [target]** a dump opens after the editor settles, and names files by alias and basename, never by full path  
`:e a`, `:e b`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
`<M-;><M-t> (via _G.CDV_TEST.press)` → `eq(during.ok, false)`  
→ `eq(new_items(bufs_before, during.bufs), {})`  
→ `eq(#scratch > 0, true)`  
→ `eq(#files > 0, true)`  
→ `eq(text:find(root, 1, true) == nil, true)`  
→ `eq(text:find('c.txt', 1, true) ~= nil, true)`  
note: T200's route. The scratch buffer isn't opened inside the failing call, only once the editor settles; and files are named by alias and basename, never by their full path, in the file and in the scratch buffer alike.  
spec: (A26) A dump opens its scratch buffer only once the editor settles, and names files by alias and basename, never by full path: on T200's route, no buffer is added inside the failing call, the scratch buffer is there once it settles, and neither it nor the file holds the project's…  
`tests/test_cycling.lua:627`

## tests/test_decisions.lua (52 cases: 45 char, 7 target)

**T250 [char]** (P2, A1) the slotting happens after the event, not inside it  
`:e a`, `:e b` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
→ `eq(child.lua('return _G.CDV_SEEN'), { '⦉-⦊ [a] ⟦-⟧' })`  
note: A BufEnter autocmd of the user's, made after setup(), runs inside the event: under the settle rule cavediver hasn't slotted the arrival yet.  
spec: (P2, A1) The slotting happens after the event, not inside it: with `⦉-⦊ [a] ⟦-⟧`, a `BufEnter` autocmd of the user's, made after `setup()`, still sees `⦉-⦊ [a] ⟦-⟧` while `:e b` runs, and the window has `⦉a⦊ [b] ⟦-⟧` once the editor settles. Its purpose is tested too: a buffer th…  
`tests/test_decisions.lua:48`

**T250 [char]** (P2, A1) a buffer that turns into a terminal or help after its BufEnter is never slotted as a file  
`:e a`, `:e b` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
`:terminal` → `eq(term.bt, 'terminal')`  
→ `eq(child.lua('return require("cavediver.domains.history").get_hash_from_buffer(...) == nil', { term.buf }), true)`  
→ `eq(child.slots():find('NONAME', 1, true), nil)`  
`:buffer b.txt`, `:help` → `eq(help.bt, 'help')`  
→ `eq(child.lua('return require("cavediver.domains.history").get_hash_from_buffer(...) == nil', { help.buf }), true)`  
→ `slots = 'no triquetra'`  
note: T250's purpose: what settling protects. A buffer that only becomes a terminal or help after its BufEnter is never slotted or registered as a file (the author, 2026-10-21: "Both"). The terminal isn't registered and sits in no slot (whether the window keeps its slots while visiting is the visiting rul  
spec: (P2, A1) The slotting happens after the event, not inside it: with `⦉-⦊ [a] ⟦-⟧`, a `BufEnter` autocmd of the user's, made after `setup()`, still sees `⦉-⦊ [a] ⟦-⟧` while `:e b` runs, and the window has `⦉a⦊ [b] ⟦-⟧` once the editor settles. Its purpose is tested too: a buffer th…  
`tests/test_decisions.lua:63`

**T251 [char]** (P3) the load matches windows by what they show, not by position ⚑ state set by hand  
`:e a`, `:e b`, `:vsplit`, `:e c`, `:e d` → `slots = '⦉c⦊ [d] ⟦-⟧'`  
→ `eq(Misc.save(child), { true })`  
`:noautocmd vsplit`, `:noautocmd edit b.txt` → `eq({ child.shown(wins[1]), child.shown(wins[2]) }, { 'b', 'd' })`  
→ `eq(Misc.load(child), { true })`  
→ `eq({ child.slots(wins[1]), child.slots(wins[2]) }, { '⦉a⦊ [b] ⟦-⟧', '⦉c⦊ [d] ⟦-⟧' })`  
note: Saved: the split (listed first) ⦉c⦊ [d], the first window ⦉a⦊ [b]. The manager brings both back the other way round: the first-listed window on b.  
spec: (P3) The load matches windows by what they show, not by position: two windows saved (`⦉c⦊ [d] ⟦-⟧` in the split, listed first, and `⦉a⦊ [b] ⟦-⟧`) and restored the other way round (the first-listed window on b) give the window on b `⦉a⦊ [b] ⟦-⟧` and the window on d `⦉c⦊ [d] ⟦-⟧`.  
`tests/test_decisions.lua:86`

**T252 [char]** (P10, I17) a closed file still on the closed stack keeps its history entry  
`:e a`, `:e b`, `:e c` → `eq(child.lua('return require("cavediver.domains.history").data.crux_internals.global[...] ~= nil', { h }), true)`  
`:bdelete b.txt` → `closed = 'b'`  
→ `eq(child.lua('return require("cavediver.domains.history").data.crux_internals.global[...] ~= nil', { h }), true)`  
note: b is closed and stays known through the closed stack.  
spec: (P10, I17) History follows along and doesn't let go early: `:e a`, `:e b`, `:e c`, `:bdelete b.txt` leave b on the closed stack, still known, and its global history entry stays. Before step 6 the entry went as soon as b was unregistered. "Known" means cavediver still remembers th…  
`tests/test_decisions.lua:108`

**T253 [char]** (P11) a failing hook is reported with a stack trace  
→ `eq(Extra.has(msgs, "Hook 'breaks' failed"), true)`  
→ `eq(traced, true)`  
spec: (P11) A bug inside a hook is caught with a stack trace: a hook that throws is reported as "Hook '<name>' failed…" together with a stack traceback. The traceback is in the notification itself (confirmed by the author, 2026-10-21: "In the notification").  
`tests/test_decisions.lua:118`

**T254 [char]** (P12, A25) require creates no user commands and starts no timers  
→ `eq(got, { commands = {}, timers = 0 })`  
spec: (P12, A25) Nothing runs at `require`, and `setup()` makes everything inside the `cavediver` augroup: `require('cavediver')` alone creates no `Cavediver*` user command and starts no timer, and every autocmd `setup()` creates is in the `cavediver` augroup, with the commands made.  
`tests/test_decisions.lua:137`

**T254 [char]** (P12, A25) setup() puts every autocmd it makes in the cavediver augroup, and makes the commands  
→ `eq(got, { made = true, outside = 0, command = true })`  
spec: (P12, A25) Nothing runs at `require`, and `setup()` makes everything inside the `cavediver` augroup: `require('cavediver')` alone creates no `Cavediver*` user command and starts no timer, and every autocmd `setup()` creates is in the `cavediver` augroup, with the commands made.  
`tests/test_decisions.lua:151`

**T255 [char]** (M1) the session file is named sha256(directory .. "\\n" .. name)  
`:e a`, `:e b` → `eq(got, true)`  
note: Decided 2026-10-21: a separator between directory and name, so "/proj" + "a" and "/proja" + "" can't share a file.  
spec: (M1) The session file is named `sha256(directory .. "\n" .. name)`: `save_session('work')` writes a file in `session_dir` whose name starts with `vim.fn.sha256(getcwd(-1, -1) .. "\n" .. 'work')`; and a session `a` saved in `/proj` and a nameless save in `/proja` are two files. Wi…  
`tests/test_decisions.lua:174`

**T255 [char]** (M1) a session "a" in /proj and a nameless save in /proja are two files  
`:e a` → `eq(got, 2)`  
spec: (M1) The session file is named `sha256(directory .. "\n" .. name)`: `save_session('work')` writes a file in `session_dir` whose name starts with `vim.fn.sha256(getcwd(-1, -1) .. "\n" .. 'work')`; and a session `a` saved in `/proj` and a nameless save in `/proja` are two files. Wi…  
`tests/test_decisions.lua:189`

**T256 [char]** (M3) a listed nowrite buffer on an existing regular file is tracked  
`:e a` → `eq({ child.lua('return vim.bo.buftype'), child.lua('return vim.bo.buflisted') }, { 'nowrite', true })`  
→ `eq(Dec.registered(child), true)`  
→ `slots = '⦉a⦊ [c] ⟦-⟧'`  
note: A listed buffer on c.txt, an existing regular file, with buftype nowrite.  
spec: (M3) A listed `nowrite` buffer on an existing regular file is tracked: after `:e a`, entering such a buffer on c.txt registers it and gives `⦉a⦊ [c] ⟦-⟧`.  
`tests/test_decisions.lua:207`

**T257 [char]** (M7) the secondary map's swap notes are saved and loaded with the rest of the map ⚑ state set by hand  
`:e a`, `:e b`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
→ `eq(notes, 'dtm{b>a} dsm{b-swap>c b>a}')`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `slots = '⦉-⦊ [c] ⟦b⟧'`  
→ `eq(K.notes_for(child, { 'b' }), notes)`  
note: b's secondary swap note is set directly; b isn't the current buffer, so no check at the load touches it.  
spec: (M7) The secondary map's swap notes are stored with the rest of the map: at `⦉-⦊ [c] ⟦b⟧` (`:e a`, `:e b`, `:e c`, `<M-f>`) with `b-swap>c` set by hand on dsm, a save and a load in a fresh process give back `dtm{b>a} dsm{b-swap>c b>a}`. It holds today already, so it's [char]: a g…  
`tests/test_decisions.lua:223`

**T258 [char]** (M8, Q16) the primary may share a slot's buffer: the queue stays and nothing reports an error  
`:e a`, `<M-;><M-c>`, `:e b` → `eq({ child.slots(), child.primary() }, { '⦉a⦊ [b] ⟦-⟧', '[a]on' })`  
`<M-f>` → `eq({ child.slots(), child.primary() }, { '⦉-⦊ [b] ⟦a⟧', '[a]on' })`  
`<M-f>` → `eq({ child.slots(), child.primary() }, { '⦉-⦊ [a] ⟦b⟧', '[a]on' })`  
→ `primary = '[a]on'`  
→ `eq(errors(), {})`  
note: The primary a sits in the ternary, then the secondary, then the current slot.  
spec: (M8, Q16) The primary may share a slot's buffer: with `p=[a]on`, `:e b` puts a in the ternary, `<M-f>` in the secondary and `<M-f>` again in the current slot; the queue stays `[a]on` throughout and over the UI ticks, and nothing reports an error.  
`tests/test_decisions.lua:242`

**T259 [char]** (M7, A6, A8) the <M-;><M-f> fallback onto the secondary writes the swap notes, as <M-f> does  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `eq({ child.slots(), child.primary() }, { '⦉c⦊ [d] ⟦b⟧', '[]off' })`  
`<M-;><M-f>` → `slots = '⦉c⦊ [b] ⟦d⟧'`  
→ `eq({ dsm_d_swap = child.note('dsm', 'd-swap'), dtm_d_swap = child.note('dtm', 'd-swap'), dsm_d = child.note('dsm', 'd') },`  
note: From ⦉c⦊ [d] ⟦b⟧ with an empty queue, <M-;><M-f> acts as <M-f> (T191's notes).  
spec: (M7, A6, A8) The `<M-;><M-f>` fallback onto the secondary writes the same notes as `<M-f>`: from `⦉c⦊ [d] ⟦b⟧` with an empty queue, `<M-;><M-f>` gives `⦉c⦊ [b] ⟦d⟧` with `dsm{d-swap>b}`, `dtm{d-swap>c}` and no plain secondary note for d (T191's notes).  
`tests/test_decisions.lua:257`

**T260 [char]** (A1, A13) a pick of the ternary: its stale note becomes the left buffer's own note, dropped when it has none  
`:e a`, `:e d`, `:e c`, `<M-;><M-f>`, `<M-f>`, `:e a` → `slots = '⦉d⦊ [a] ⟦c⟧'`  
→ `eq(child.note('dtm', 'd'), 'a')`  
`<M-v>` → `slots = '⦉a⦊ [d] ⟦c⟧'`  
→ `eq(child.note('dtm', 'd'), '-')`  
`<M-;><M-r> (via press)` → `eq({ ok, err }, { true, nil })`  
→ `eq(Extra.has(msgs, 'No ternary relationship found'), true)`  
note: T186's keys up to ⦉d⦊ [a] ⟦c⟧, where d's note d>a names a; then a pick of d, the ternary, in place of <M-S-f>.  
spec: (A1, A13) The check on a pick of the ternary: T186's keys up to `⦉d⦊ [a] ⟦c⟧` (d's note `d>a`), then cycle to d and `<M-v>`, give `⦉a⦊ [d] ⟦c⟧`; d's note names the new ternary a, which has no plain note, so it's dropped and `<M-;><M-r>` says "No ternary relationship found".  
`tests/test_decisions.lua:268`

**T261 [char]** (A1, A8) a primary jump onto the ternary: its stale note becomes the left buffer's own note, dropped when it has none  
`:e a`, `:e d`, `<M-;><M-c>`, `:e c`, `<M-f>`, `<M-f>`, `:e a` → `eq({ child.slots(), child.primary() }, { '⦉d⦊ [a] ⟦c⟧', '[d]on' })`  
→ `eq(child.note('dtm', 'd'), 'a')`  
`<M-;><M-f>` → `slots = '⦉a⦊ [d] ⟦c⟧'`  
→ `eq(child.note('dtm', 'd'), '-')`  
`<M-;><M-r> (via press)` → `eq({ ok, err }, { true, nil })`  
→ `eq(Extra.has(msgs, 'No ternary relationship found'), true)`  
note: The same state with d as the primary, reached by a primary jump onto d, the ternary.  
spec: (A1, A8) The check on a primary jump onto the ternary: `:e a`, `:e d`, `<M-;><M-c>`, `:e c`, `<M-f>`, `<M-f>`, `:e a` give `⦉d⦊ [a] ⟦c⟧` with `p=[d]on` and d's note `d>a`; `<M-;><M-f>` gives `⦉a⦊ [d] ⟦c⟧`, d's stale note becomes a's own note, none, so it's dropped, and `<M-;><M-r…  
`tests/test_decisions.lua:282`

**T262 [char]** (A1, A13) a pick of the secondary: a stale ternary note becomes the ternary's own note  
`:e a`, `:e c`, `:e e`, `:e b`, `<M-f>`, `:e c`, `<M-S-f>` → `slots = '⦉c⦊ [b] ⟦e⟧'`  
→ `eq(child.note('dtm', 'e'), 'c')`  
`<M-v>` → `slots = '⦉c⦊ [e] ⟦b⟧'`  
→ `eq(child.note('dtm', 'e'), 'a')`  
`<M-;><M-r>` → `eq({ ok, err }, { true, nil })`  
→ `slots = '⦉a⦊ [e] ⟦b⟧'`  
`<M-;><M-r>` → `slots = '⦉c⦊ [e] ⟦b⟧'`  
note: T185's keys up to ⦉c⦊ [b] ⟦e⟧, where e's note e>c names c; then a pick of e, the secondary, in place of <M-f>. c stays put, so e's note becomes c's own, a.  
spec: (A1, A13) The check on a pick of the secondary: T185's keys up to `⦉c⦊ [b] ⟦e⟧` (e's note `e>c`), then cycle to e and `<M-v>`, give `⦉c⦊ [e] ⟦b⟧`; the ternary c stays put, so e's note becomes c's own note, `e>a`. `<M-;><M-r>` gives `⦉a⦊ [e] ⟦b⟧`, and again `⦉c⦊ [e] ⟦b⟧`.  
`tests/test_decisions.lua:296`

**T263 [char]** (A7, M7) <M-S-f> runs the secondary map's check on the buffer it brings in ⚑ state set by hand  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
`<M-S-f>` → `slots = '⦉d⦊ [c] ⟦b⟧'`  
→ `eq(Neg.i23(child), nil)`  
`<M-;><M-t> (via press)` → `eq({ ok, err }, { true, nil })`  
→ `eq(Extra.has(msgs, 'No secondary relationship found'), true)`  
note: The arriving buffer's plain secondary note names the window's secondary, set by hand; it has no swap note, so the check drops it.  
spec: (A7, A8, M7) The secondary map's check runs on `<M-S-f>` and on a primary jump, with the stale note planted. At `⦉c⦊ [d] ⟦b⟧` with `c>b` set on dsm, `<M-S-f>` gives `⦉d⦊ [c] ⟦b⟧`; with `p=[x]on` and `x>b` set on dsm, `<M-;><M-f>` gives `⦉d⦊ [x] ⟦b⟧`. In both the note names the se…  
`tests/test_decisions.lua:313`

**T263 [char]** (A8, M7) a primary jump runs the secondary map's check on the primary ⚑ state set by hand  
`:e x`, `<M-;><M-c>`, `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `eq({ child.slots(), child.primary() }, { '⦉c⦊ [d] ⟦b⟧', '[x]on' })`  
`<M-;><M-f>` → `slots = '⦉d⦊ [x] ⟦b⟧'`  
→ `eq(Neg.i23(child), nil)`  
`<M-;><M-t> (via press)` → `eq({ ok, err }, { true, nil })`  
→ `eq(Extra.has(msgs, 'No secondary relationship found'), true)`  
spec: (A7, A8, M7) The secondary map's check runs on `<M-S-f>` and on a primary jump, with the stale note planted. At `⦉c⦊ [d] ⟦b⟧` with `c>b` set on dsm, `<M-S-f>` gives `⦉d⦊ [c] ⟦b⟧`; with `p=[x]on` and `x>b` set on dsm, `<M-;><M-f>` gives `⦉d⦊ [x] ⟦b⟧`. In both the note names the se…  
`tests/test_decisions.lua:325`

**T264 [char]** (A11, I23) the ternary restore's exchange is followed by the secondary map's check ⚑ state set by hand  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e a`, `:e b` → `slots = '⦉c⦊ [b] ⟦a⟧'`  
→ `eq(child.note('dtm', 'b'), 'a')`  
`<M-;><M-r>` → `slots = '⦉a⦊ [b] ⟦c⟧'`  
→ `eq(Neg.i23(child), nil)`  
`<M-;><M-t>` → `eq({ ok, err }, { true, nil })`  
note: T62's exchange: b's note b>a names the secondary a, so <M-;><M-r> swaps the ternary c up into the secondary. b's secondary note is set to name c by hand.  
spec: (A11, I23) The ternary restore's exchange is followed by the secondary map's check: at T62's `⦉c⦊ [b] ⟦a⟧` with `b>c` set on dsm, `<M-;><M-r>` exchanges to `⦉a⦊ [b] ⟦c⟧`; b's secondary note now names the secondary, so it's rewritten or dropped (I23 holds), and `<M-;><M-t>` doesn'…  
`tests/test_decisions.lua:341`

**T265 [char]** (A11) at the secondary restore's exchange, a stale ternary note is dropped when the ternary's own note names the current buffer ⚑ state set by hand  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
`<M-;><M-t>` → `slots = '⦉b⦊ [d] ⟦c⟧'`  
→ `eq(child.note('dtm', 'd'), '-')`  
`<M-;><M-r> (via press)` → `eq({ ok, err }, { true, nil })`  
→ `eq(Extra.has(msgs, 'No ternary relationship found'), true)`  
note: At ⦉c⦊ [d] ⟦b⟧, set by hand: d's secondary note names c (the ternary, so the restore exchanges), d's ternary note names b (which the exchange moves into the ternary), and b's own note names d, the current buffer.  
spec: (A11, final section) At the secondary restore's exchange the stale ternary note is dropped when the ternary's own note would name the current buffer: at `⦉c⦊ [d] ⟦b⟧` with `d>c` on dsm and `d>b`, `b>d` on dtm (set by hand), `<M-;><M-t>` exchanges to `⦉b⦊ [d] ⟦c⟧`, d's ternary not…  
`tests/test_decisions.lua:356`

**T266 [char]** (A11, D9) a restore onto an open buffer whose file is gone flip-flops and says the file isn't on disk  
`:e b`, `:e a`, `:e c`, `:e f`, `:e a`, `<M-S-f>`, `:e d`, `:e a` → `slots = '⦉d⦊ [a] ⟦-⟧'`  
→ `eq(K.notes_for(child, { 'a' }), 'dtm{a-swap>f a>b} dsm{}')`  
→ `eq(child.lua([[return vim.fn.bufloaded('f.txt')]]), 1)`  
`<M-;><M-r> (via press)` → `eq({ ok, err }, { true, nil })`  
→ `slots = want`  
→ `eq({ want, said }, { want, true })`  
note: a ends up with the plain note a>b and the swap note a-swap>f, ternary d (T173's state). f.txt is deleted on disk while f's buffer stays open. Each press that brings f back says so, in one WARN line (wording locked 2026-10-21).  
spec: (A11, D9) A note at a file deleted on disk whose buffer is still open flip-flops and says the file isn't on disk: T173's keys and checks, and each press that brings f back gives a message besides "Restored ternary slot to…". The message is locked (the author, 2026-10-21: "(a) one…  
`tests/test_decisions.lua:372`

**T267 [char]** (A11, D9) a note at a hash with no path is cleared when it's used ⚑ state set by hand  
`:e a`, `:e b`, `<M-;><M-r>` → `eq({ ok, err }, { true, nil })`  
→ `eq(child.lua([[`  
spec: (A11, D9) A note at a hash with no path is cleared when it's used: T68's state, and after `<M-;><M-r>` no note holds the unknown hash.  
`tests/test_decisions.lua:396`

**T268 [char]** (A2) the winbar shows the visit, like "a.txt ← [help]"  
`:e a`, `:help`, `:close` → `eq(child.win(), aw)`  
→ `eq(child.lua('return vim.bo.buftype'), 'help')`  
→ `eq(text:match('%[%d+%] a%.txt ← %[help%]') ~= nil, true)`  
note: Help shown in a's own window: a visit. Format locked 2026-10-21: the current slot's piece becomes "[<bufnr>] a.txt ← [help]", the ternary and secondary pieces kept around it; the brackets hold the buftype.  
spec: (A2) The winbar shows a visit, like `main.lua ← [help]`: help shown in a's own window gives a winbar whose current piece reads, with highlights left out, `[<bufnr>] a.txt ← [help]`. The format is locked (the author, 2026-10-21: "(a) within the winbar"): the current slot's piece b…  
`tests/test_decisions.lua:413`

**T269 [char]** (A2, A6, A7) while visiting, <M-f> and <M-S-f> take the window back to its current slot first  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq(child.lua('return vim.bo.buftype'), 'nofile')`  
→ `eq({ key, ok, err }, { key, true, nil })`  
→ `eq({ key, child.shown(), child.slots() }, { key, 'd', '⦉c⦊ [d] ⟦b⟧' })`  
spec: (A2, A6, A7) While visiting, `<M-f>` and `<M-S-f>` take the window back to its current slot first: at `⦉c⦊ [d] ⟦b⟧`, a `nofile` scratch shown in the window, then either key, gives d again with `⦉c⦊ [d] ⟦b⟧`.  
`tests/test_decisions.lua:431`

**T270 [char]** (A2) while visiting, the current slot may hold a closed buffer  
`:e a`, `:e b`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
`:terminal` → `eq(child.lua('return vim.bo.buftype'), 'terminal')`  
`:bdelete c.txt` → `closed = 'c'`  
→ `slots = '⦉-⦊ [c] ⟦b⟧'`  
spec: (A2) While visiting, the current slot may hold a closed buffer: at `⦉-⦊ [c] ⟦b⟧`, `:terminal` in the window, then `:bdelete c.txt`, leave `⦉-⦊ [c] ⟦b⟧` with c on the closed stack.  
`tests/test_decisions.lua:443`

**T271 [char]** (A19) a deleted buffer's window lands on the secondary when there's no ternary  
`:e a`, `:e b`, `:e c`, `<M-f>`, `<M-f>`, `<M-;><M-t>` → `slots = '⦉-⦊ [b] ⟦a⟧'`  
`:bdelete b.txt` → `shown = 'a'`  
note: ⦉-⦊ [b] ⟦a⟧: no ternary. The window came to b from c by <M-f>, so Neovim's own pick is c; the secondary restore then made a the secondary.  
spec: (A19) A deleted buffer's window lands in the order ternary, secondary, primary, most recent, each on a route where Neovim's own pick (the window's jumplist) differs; Neovim closes every other window showing the buffer, so each is a window on its own, as in T111. Secondary: `:e a`…  
`tests/test_decisions.lua:463`

**T271 [char]** (A19) with no ternary or secondary, it lands on the primary ⚑ state set by hand  
→ `primary = '[a]on'`  
`:bdelete c.txt` → `eq({ child.win(), child.shown() }, { w2, 'a' })`  
note: The queue set by hand: [a], switched on.  
spec: (A19) A deleted buffer's window lands in the order ternary, secondary, primary, most recent, each on a route where Neovim's own pick (the window's jumplist) differs; Neovim closes every other window showing the buffer, so each is a window on its own, as in T111. Secondary: `:e a`…  
`tests/test_decisions.lua:492`

**T271 [char]** (A19) with no ternary, secondary or primary, it lands on the most recent buffer  
`:bdelete c.txt` → `eq({ child.win(), child.shown() }, { w2, 'x' })`  
spec: (A19) A deleted buffer's window lands in the order ternary, secondary, primary, most recent, each on a route where Neovim's own pick (the window's jumplist) differs; Neovim closes every other window showing the buffer, so each is a window on its own, as in T111. Secondary: `:e a`…  
`tests/test_decisions.lua:506`

**T271 [char]** (A19) under the window view, "most recent" is the window's own history ⚑ state set by hand  
`:e a`, `:e b`, `:e c`, `:vsplit`, `:keepjumps edit a.txt`, `:keepjumps edit c.txt`, `:wincmd p`, `:e d`, `:e x`, `:wincmd p`, `:only` → `eq({ child.shown(), child.slots(w2) }, { 'c', '⦉-⦊ [c] ⟦-⟧' })`  
`:bdelete c.txt` → `eq({ child.win(), child.shown() }, { w2, 'a' })`  
note: "Most recent" follows history_view (decided 2026-10-21), as <M-.> already does: under the window view it's the window's own history, so the window lands on what it showed, not on x. keepjumps: cavediver records these visits, Neovim's jumplist doesn't, so Neovim's own pick on :bdelete (the jumplist,   
spec: (A19) A deleted buffer's window lands in the order ternary, secondary, primary, most recent, each on a route where Neovim's own pick (the window's jumplist) differs; Neovim closes every other window showing the buffer, so each is a window on its own, as in T111. Secondary: `:e a`…  
`tests/test_decisions.lua:515`

**T271 [char]** (A19) with nothing to land on and Neovim showing something else, the window gets a new empty buffer  
`:e a`, `:bdelete a.txt` → `eq(got, { true, '', '', { '' } })`  
note: Nothing to land on: a is the only tracked file. Neovim's pick is a listed scratch buffer, something other than its empty buffer, so the window gets a new empty buffer.  
spec: (A19) A deleted buffer's window lands in the order ternary, secondary, primary, most recent, each on a route where Neovim's own pick (the window's jumplist) differs; Neovim closes every other window showing the buffer, so each is a window on its own, as in T111. Secondary: `:e a`…  
`tests/test_decisions.lua:545`

**T272 [char]** (A20) a rename whose old file still exists is a copy: the old name goes on the closed stack  
`:e a`, `:e b`, `:saveas g.txt` → `eq(child.lua('return vim.fn.filereadable(_G.CDV_TEST.root .. "/b.txt")'), 1)`  
→ `eq(vim.tbl_contains(vim.split(child.closed(), ','), 'b'), true)`  
note: :saveas writes g.txt and leaves b.txt on disk. What happens to the window afterwards is T106's.  
spec: (A20) The disk decides, the copy half: `:e a`, `:e b`, `:saveas g.txt` leave b.txt on disk, so the rename is a copy and b goes on the closed stack. Built in step 4 (A20). What `:saveas` does to the window is T106's.  
`tests/test_decisions.lua:559`

**T273 [char]** (A22) the stale pass keeps the history of the file it re-points ⚑ state set by hand  
`:e a`, `:e b`, `:e c` → `eq(got, { had = true, kept = true })`  
note: T113's stale registration: b's buffer wiped without events, a copy of b.txt loaded the same way, then the timer's pass.  
spec: (A22) The stale pass keeps the history of the file it re-points: T113's state, and after the pass b's hash is still in the global history.  
`tests/test_decisions.lua:569`

**T274 [char]** (A23) the triquetra commands print primary_buffer[1] as "Primary buffer"  
`:e a`, `<M-;><M-c>`, `:e b` → `eq({ plain:find('Primary buffer:%s+' .. h) ~= nil, verbose:find('Primary buffer:%s+' .. h) ~= nil }, { true, true })`  
spec: (A23) `:CavediverTriquetra` and `:CavediverTriquetraVerbose` print `primary_buffer[1]` as "Primary buffer".  
`tests/test_decisions.lua:589`

**T275 [target]** (A26) the fill assertion dumps  
`:e a`, `:e b`, `:vsplit`, `<M-f> (via _G.CDV_TEST.press)` → `eq(#files > 0, true)`  
note: The ordered list's first two entries swapped by hand, so its first entry isn't the window's current buffer (T176).  
spec: (A26) Each "shouldn't happen" dumps: the fill assertion (T176's second half), "Duplicates detected" (T34's state), and a hook failure (a hook that throws, bound by hand to the history machine's updates) each leave a new file under `stdpath("state")/cavediver/` (the location T200 …  
`tests/test_decisions.lua:608`

**T275 [target]** (A26) "Duplicates detected" dumps ⚑ state set by hand  
`:e a`, `:e b`, `:e c`, `:e d` → `slots = '⦉c⦊ [d] ⟦c⟧'`  
`:e a` → `eq(Extra.has(child.messages(), 'Duplicates detected'), true)`  
→ `eq(#files > 0, true)`  
note: s = t, set directly (T34).  
spec: (A26) Each "shouldn't happen" dumps: the fill assertion (T176's second half), "Duplicates detected" (T34's state), and a hook failure (a hook that throws, bound by hand to the history machine's updates) each leave a new file under `stdpath("state")/cavediver/` (the location T200 …  
`tests/test_decisions.lua:624`

**T275 [target]** (A26) a hook failure dumps  
`:e a`, `:e b` → `eq(Extra.has(child.messages(), "Hook 't275_breaks' failed"), true)`  
→ `eq(#files > 0, true)`  
note: A failing hook bound by hand to the history machine's updates.  
spec: (A26) Each "shouldn't happen" dumps: the fill assertion (T176's second half), "Duplicates detected" (T34's state), and a hook failure (a hook that throws, bound by hand to the history machine's updates) each leave a new file under `stdpath("state")/cavediver/` (the location T200 …  
`tests/test_decisions.lua:641`

**T276 [target]** (A26) a planted I1 break dumps at the next step ⚑ state set by hand  
`:e a`, `:e b`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
`:vsplit`, `:e d`, `:e e` → `slots = '⦉b⦊ [c] ⟦b⟧'`  
`:e x` → `eq(#files, 1)`  
note: T203's layout, with a duplicate planted in the first window instead of a stale note: c's secondary set to b, which is already its ternary.  
spec: (A26) A planted I1 break dumps at the next step: T203's layout, with c's secondary set by hand to b, its ternary, and `:e x` in the other window produces one dump.  
`tests/test_decisions.lua:654`

**T277 [target]** (A26) the error says where the dump file is  
→ `eq(#files > 0, true)`  
→ `eq(named, true)`  
spec: (A26) The error message says where the dump file is: T200's restore assertion, and the error or a message names the new file.  
`tests/test_decisions.lua:681`

**T278 [target]** (A26) steps from keymaps and from events are tagged keymap and event  
→ `eq(#files > 0, true)`  
→ `eq(tagged, true)`  
spec: (A26) Steps are tagged by cause: in T200's dump, the steps from keymaps and from events carry the tags `keymap` and `event` (T204 checks `load` and `timer`).  
`tests/test_decisions.lua:693`

**T279 [char]** (I5) the registry stays a bijection over random walks ⚑ random walk  
spec: (I5) The registry stays a bijection, for buffers and for paths: random walks with T130's mix plus `:enew`, a No Name buffer with text, `<M-.>` and `<M-S-w>`, checked after every action.  
`tests/test_decisions.lua:731`

**T280 [char]** (I6) a buffer wiped without events leaves no stale registration after a cleanup tick ⚑ state set by hand  
`:e a`, `:e b`, `:e c` → `eq(child.lua([[`  
note: b, the ternary, wiped without events: no BufDelete, so the registry is stale until the cleanup tick (4 s, first tick at once).  
spec: (I6) A buffer wiped without events leaves no stale registration once a cleanup tick has run: `:e a`, `:e b`, `:e c`, `noautocmd bwipeout` of b, then a 4.6 s wait leave every registered buffer number valid.  
`tests/test_decisions.lua:737`

**T281 [char]** (I7) after a cleanup pass, no closed hash has an open buffer, over random walks ⚑ random walk  
note: Checked after a cleanup pass forced after every action ("eventually").  
spec: (I7) After a cleanup pass, no hash on the closed stack has an open buffer: random walks with T279's mix, a `cleanup_system` pass forced after every action ("eventually enforced").  
`tests/test_decisions.lua:751`

**T282 [char]** (I8) the current slot is the shown buffer outside cycling and visits, over random walks ⚑ random walk  
note: Cycles left open across a window jump (Y1, Y2), as in T128.  
spec: (I8) A window's current slot is the hash of the buffer it shows, except in the window a cycle runs in and during a visit: random walks with T128's mix, cycles left open across a window jump included. A cycle left open across a window jump is cancelled, so work in the other window…  
`tests/test_decisions.lua:756`

**T283 [char]** (I9) every triquetra belongs to a valid, non-floating window, over random walks ⚑ random walk  
spec: (I9) Every triquetra belongs to a valid, non-floating window: random walks with T128's mix plus `:enew`, `<M-.>` and `<M-S-w>`.  
`tests/test_decisions.lua:760`

**T284 [char]** (I9) :file onto a name not on disk in a split leaves no triquetra for a dead window  
`:e a`, `:vsplit`, `:e b`, `:file new.txt` → `eq(child.lua([[`  
spec: (I9) `:file` onto a name not on disk, in a split, leaves no triquetra for a dead window: `:e a`, `:vsplit`, `:e b`, `:file new.txt`.  
`tests/test_decisions.lua:764`

**T285 [char]** (I14) a save with a slot holding a hash with no path succeeds ⚑ state set by hand  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq(got, { true })`  
→ `eq(errors(), {})`  
note: A secondary set to a hash nothing knows, saved in the same call so no other pass runs first.  
spec: (I14) A save with a slot holding a hash with no path succeeds and reports nothing: at `⦉c⦊ [d] ⟦b⟧`, the secondary set by hand to an unknown hash, then `save_session` in the same call.  
`tests/test_decisions.lua:782`

**T286 [char]** (I21) the critical save hook throws to the caller and leaves storage where it was  
`:e a` → `eq({ got[1], state }, { false, before })`  
note: T143's read-only session directory. The transition is abandoned, so storage stays where it was: idle after a load or a save, bare before either (as here, a fresh process's first save).  
spec: (I21) The critical save hook throws to the caller, and the abandoned transition leaves storage where it was: `idle` after a load or a save, `bare` before either. T143's read-only session directory, saved from a fresh process (so `bare`).  
`tests/test_decisions.lua:798`

**T287 [char]** (I23, A21) a cleanup re-point runs the check on the buffer it makes current ⚑ state set by hand  
`:e d`, `:e b`, `:e c`, `<M-f>`, `:e a` → `slots = '⦉c⦊ [a] ⟦b⟧'`  
`:noautocmd buffer d.txt`, `:bwipeout a.txt` → `eq({ child.slots():match('%[(.-)%]'), child.slots():match('⟦(.-)⟧$') }, { 'd', 'b' })`  
→ `eq(Neg.i23(child), nil)`  
`<M-;><M-t>` → `eq({ ok, err }, { true, nil })`  
note: T163's re-point: the window put on d without a BufEnter, then a's buffer wiped. d's secondary note names b, the window's secondary, set by hand; the secondary stays b either way, so the note is stale once d is current.  
spec: (I23, A21, final section) The check runs at a cleanup pass that moved a window's slots: T163's re-point, with d's secondary note set by hand to b, the window's secondary; once d is current I23 holds and `<M-;><M-t>` doesn't throw.  
`tests/test_decisions.lua:815`

**T288 [char]** (D11) under the window view, :close leaves no tie: :e a after it ranks a first  
`:e a`, `:e b`, `:vsplit`, `:close`, `:e a` → `eq(Dec.leftmost(child), nil)`  
spec: (D11, bug found while porting) Under the window view, `:close` leaves no tie: `:e a`, `:e b`, `:vsplit`, `:close`, `:e a` put a strictly first in the bufferline order.  
`tests/test_decisions.lua:828`

**T289 [target]** (D25) the window machine is gone: its file, its SHOWING_ constants and its require  
→ `eq({`  
spec: (D25) The window machine goes: no `window/sm.lua`, no `SHOWING_` constants in `window/states.lua`, and nothing requires `cavediver.domains.window.sm`. A doc check, matched by text.  
`tests/test_decisions.lua:846`

**T290 [char]** (D18, D22, D24) STATUS and the old project CLAUDE.md live in archive/  
→ `eq({`  
spec: (D18, D22, D24) STATUS and the old project `CLAUDE.md` live in `archive/`, and neither is at the repo root. A doc check. It holds today already, so it's [char]: a guard that stays true when the decided code lands.  
`tests/test_decisions.lua:860`

**T291 [char]** (D8, D13) README:15 and README:355 stay as written  
→ `eq({`  
spec: (D8, D13) README:15 ("Closed buffers reopen when accessed through relationships") and README:355 ("Every time you jump to secondary…") stay as written. A doc check, matched by text. It holds today already, so it's [char]: a guard that stays true when the decided code lands.  
`tests/test_decisions.lua:869`

## tests/test_docs.lua (24 cases: 5 char, 19 target)

**D1 [target]** README has toggle_primary and set_primary the right way round  
→ `eq({ has(r, 'toggle_primary = "<M-;><M-x>"'), has(r, 'set_primary = "<M-;><M-c>"') }, { true, true })`  
`tests/test_docs.lua:47`

**D2 [target]** README's defaults block copies configs.lua, missing keys included  
→ `eq(missing, {})`  
`tests/test_docs.lua:52`

**D2 [target]** README's cleanup_interval says milliseconds  
→ `eq(found, true)`  
`tests/test_docs.lua:71`

**D5 [target]** README says a disabled primary makes <M-;><M-f> act like <M-f>  
→ `eq({ has(r, "won't do anything at all"), says }, { false, true })`  
`tests/test_docs.lua:79`

**D6 [target]** README says a pop-up save keeps the good lines and reports the bad ones  
→ `eq(has(read(README), 'nothing is saved'), false)`  
`tests/test_docs.lua:89`

**D26 [char]** README's triquetra sentence follows the visiting rule, and "tiquetra" is fixed  
→ `eq({ has(r, new), has(r, 'it will clean the triquetra'), has(r, 'tiquetra') }, { true, false, false })`  
`tests/test_docs.lua:93`

**D27 [target]** README's requirements (D4, D27)  
→ `eq(missing, {})`  
`tests/test_docs.lua:101`

**D27 [target]** README's lazy.nvim example depends on cokeline, not harpoon, with no comment  
→ `eq({`  
`tests/test_docs.lua:118`

**D27 [target]** README's cokeline paragraph  
→ `eq({ has(r, new), has(r, 'visit history of all your browsers') }, { true, false })`  
`tests/test_docs.lua:127`

**D28 [target]** README has "Session manager setup" with resession, native sessions and no manager  
→ `eq({`  
`tests/test_docs.lua:135`

**D3 [target]** cycle_select's annotation copies "Select cycling buffer and attach history"  
→ `eq(has(c, '---@field cycle_select string Select cycling buffer and attach history'), true)`  
`tests/test_docs.lua:151`

**D15 [target]** the checkpoint docstring says it is the live triquetra, not a copy  
→ `eq({ has(c, new), has(c, 'Stores a deep copy') }, { true, false })`  
`tests/test_docs.lua:158`

**D16 [target]** the <M-.> branch comment says most recent relative to the one deleted  
→ `eq({`  
`tests/test_docs.lua:165`

**D17 [target]** navigation/data.lua says one jump table across all tabs  
→ `eq({`  
`tests/test_docs.lua:173`

**D18 [char]** the saved window entry annotation has the six fields  
→ `eq({`  
`tests/test_docs.lua:181`

**D21 [target]** navigation/states.lua says nothing enters file_picker yet  
→ `eq({ says, has(line, 'where explorer controls navigation') }, { true, false })`  
`tests/test_docs.lua:191`

**D21 [target]** the old spec marks file-picker mode as not built  
→ `eq(has(s:lower(), 'not built'), true)`  
`tests/test_docs.lua:200`

**D25 [target]** the closed-stack comments say filehashes  
→ `eq({`  
`tests/test_docs.lua:205`

**D25 [target]** the loop state annotation is SELF "self"  
→ `eq({`  
`tests/test_docs.lua:215`

**D29 [char]** init.lua's header says encrypted session persistence, and the XOR docstrings are gone  
→ `eq({`  
`tests/test_docs.lua:223`

**Q20 [target]** the engine says modes are shared by every machine  
→ `eq({`  
`tests/test_docs.lua:235`

**Q5 [target]** the meaningless 30 in math.max(#ordered, 30) is gone  
→ `eq(c:find('math%.max%(%s*#history%.data%.ordered%.crux%s*,%s*30%s*%)') ~= nil, false)`  
`tests/test_docs.lua:254`

**A12 [char]** the desk narrows the cokeline item and its Dropped line to the fallback  
→ `eq({ has(dropped, phrase), n >= 2 }, { true, true })`  
`tests/test_docs.lua:261`

**D14 [char]** the desk's new-file wipe bug and its repro name the faster trigger  
→ `eq({ has(desk, 'Sooner still, the next 'BufEnter' anywhere wipes it'), has(desk, 'Or skip the wait') }, { true, true })`  
`tests/test_docs.lua:269`

## tests/test_engine.lua (7 cases: 6 char, 1 target)

**T1 [char]** to() on a transition with no bound hook throws from to() itself  
→ `eq(got.ok, false)`  
→ `Helpers.expect.no_equality(got.err:find("Transition 'a->b' is not registered", 1, true), nil)`  
→ `Helpers.expect.no_equality(got.err:find('engine/state-machine.lua:', 1, true), nil)`  
→ `eq(got.state, 'a')`  
→ `eq(child.messages(), {})`  
note: a hook on b->a only: a->b stays unregistered  
spec: `to()` on a transition with no bound hook throws from `to()` itself.  
`tests/test_engine.lua:14`

**T2 [char]** a failing hook is reported, later hooks still run, and the state still changes  
→ `eq(got.ran, { 'after' })`  
→ `eq(got.state, 'b')`  
→ `eq(#msgs, 1)`  
→ `eq(msgs[1].level, vim.log.levels.ERROR)`  
→ `Helpers.expect.no_equality(msgs[1].msg:find("Hook 'breaks' failed during transition a->b", 1, true), nil)`  
spec: A hook that errors is reported as "Hook '<name>' failed during transition a->b", the later hooks still run, and the state still changes.  
`tests/test_engine.lua:33`

**T3 [char]** sm:state() inside a hook returns the state being left  
→ `eq(got, { inside = 'a', after = 'b' })`  
spec: `sm:state()` inside a hook returns the state being left.  
`tests/test_engine.lua:54`

**T4 [char]** hooks run in class order; no mode runs only "*" hooks, a mode adds its own  
→ `eq(got.none, { 'star1', 'star3' })`  
→ `eq(got.m1, { 'star1', 'm1_2', 'star3' })`  
→ `eq(got.m2, { 'm2_0', 'star1', 'star3' })`  
note: registered out of class order, with distinct classes  
spec: Hooks run in class order. `to()` without a mode runs only `"*"` hooks; `to(…, m)` also runs hooks filtered to `m`.  
`tests/test_engine.lua:68`

**T5 [target]** off(from, to, name) removes that hook from that transition and nothing else  
→ `eq(got, { 'g:a->b', 'h:b->a' })`  
spec: `off(from, to, name)` removes that hook from that transition and nothing else.  
`tests/test_engine.lua:98`

**T6 [char]** transition modes are shared: a mode registered on one machine works on another (Q20)  
→ `eq(got, { ok_on = true, ok_to = true, ran = { 'named' } })`  
spec: Transition modes are one table shared by every machine: a mode registered on one machine can be named by a hook on any other, and `to(…, m)` on any machine accepts it (Q20).  
`tests/test_engine.lua:117`

**T7 [char]** sm.history keeps every transition: 1,000 transitions, 1,000 entries (Q21)  
→ `eq(got, { n = 1000, all_same = true })`  
spec: `sm.history` keeps every transition: after 1,000 transitions on one machine, its history holds all 1,000 (Q21).  
`tests/test_engine.lua:139`

## tests/test_history.lua (9 cases: 9 char)

**T15 [char]** after visiting a, b, c, ordered.crux is c,b,a  
`:e a`, `:e b`, `:e c` → `ordered = 'c,b,a'`  
spec: After visiting a, b, c, `ordered.crux` is `c,b,a`.  
`tests/test_history.lua:40`

**T16 [char]** with history_view = "window", window 2 ranks its own visits first (s17)  
`:e a`, `:e b`, `:e c`, `:vsplit`, `:e d`, `:e e` → `ordered = 'e,d,c,b,a'`  
→ `ordered = 'c,b,a,e,d'`  
`:e a` → `ordered = 'a,c,b,e,d'`  
note: the rest of run s17 (M4)  
spec: With `history_view = "window"`, the order in window 2 puts window 2's own visits first (the s17 sequence).  
`tests/test_history.lua:45`

**T17 [char]** closing a window removes its crux_internals.window entry  
`:e a`, `:vsplit`, `:e b` → `eq(window_history(w2), { b = true })`  
`:close` → `eq(window_history(w2), nil)`  
spec: Closing a window removes its `crux_internals.window` entry.  
`tests/test_history.lua:60`

**T18 [char]** :vsplit creates the new window's history entry along with its triquetra (I3)  
`:e a`, `:e b`, `:vsplit` → `slots = '⦉-⦊ [b] ⟦-⟧'`  
→ `Helpers.expect.no_equality(window_history(w2), nil)`  
note: Under the default (global) view, as in run s16. The window view would give the new window an empty entry on WinEnter for another reason (construct_crux).  
spec: `:vsplit` creates the new window's history entry along with its triquetra (I3).  
`tests/test_history.lua:73`

**T19 [char]** a visit is recorded in the history of the window that shows the buffer, not the focused one  
`:e a`, `:vsplit`, `:e b` → `eq(X.win(child), w2)`  
→ `shown = 'c'`  
→ `eq({ w1_has_c = (window_history(w1) or {}).c, w2_has_c = (window_history(w2) or {}).c }, { w1_has_c = true })`  
note: :e c runs in w1 while w2 keeps the focus  
spec: A visit is recorded in the history of the window that shows the buffer, not the focused one (for example, `win_execute` in another window).  
`tests/test_history.lua:82`

**T20 [char]** track_buffer(h, t) stores t in the global history ⚑ state set by hand  
`:e a` → `eq(got.stored, 1000)`  
spec: `track_buffer(h, t)` stores `t` in the global history.  
`tests/test_history.lua:96`

**T149 [char]** random visits across windows, global view: the visited buffer is leftmost ⚑ random walk  
→ `eq(walks('global'), nil)`  
spec: A property test over random visits, with `history_view` set to `"global"` and to `"window"`, across windows: after any visit, the visited buffer is leftmost in the bufferline order (`compare_buffers`). The author's check: two windows, back into window A, `:e e` gave `e=7 b=6 a=5 …  
`tests/test_history.lua:152`

**T149 [char]** random visits across windows, window view: the visited buffer is leftmost ⚑ random walk  
→ `eq(walks('window'), nil)`  
note: Under the window view the rebuild gives every buffer its own time (history/routines.lua:271, :274; T197), on a window jump and on :close alike, e.g. after :e a, :e b, :vsplit, :close, :e a, a and b don't share one.  
spec: A property test over random visits, with `history_view` set to `"global"` and to `"window"`, across windows: after any visit, the visited buffer is leftmost in the bufferline order (`compare_buffers`). The author's check: two windows, back into window A, `:e e` gave `e=7 b=6 a=5 …  
`tests/test_history.lua:159`

**T149 [char]** the author's check (Q4): back into window A, :e e gives e=8 b=7 a=5 d=4 c=3  
`:e a`, `:e b`, `:vsplit`, `:e c`, `:e d`, `:e e` → `eq(X.times(child), 'e=8 b=7 a=5 d=4 c=3')`  
→ `eq(X.leftmost(child), nil)`  
note: e=7 b=6 a=5 d=4 c=3 before the tie fix, which gives the window's buffers one more time each on the rebuild: the same order.  
spec: A property test over random visits, with `history_view` set to `"global"` and to `"window"`, across windows: after any visit, the visited buffer is leftmost in the bufferline order (`compare_buffers`). The author's check: two windows, back into window A, `:e e` gave `e=7 b=6 a=5 …  
`tests/test_history.lua:163`

## tests/test_identity.lua (7 cases: 7 char)

**T8 [char]** the hash of a plain path is the first 16 hex characters of sha256(path .. "\\n")  
`:e a` → `eq(got[1], got[2])`  
spec: The hash of a plain path is the first 16 hex characters of `vim.fn.sha256(path .. "\n")`.  
`tests/test_identity.lua:21`

**T9 [char]** a path with ", $HOME or a backslash hashes to sha256(path .. "\\n")  
`:e a` → `eq(got.got, got.want)`  
note: Only hashes come back, keyed by a label, never the paths. The backslash name has two in a row, which the shell's double quotes fold into one.  
spec: A path containing `"`, `$HOME` or a backslash hashes to the first 16 hex characters of `vim.fn.sha256(path .. "\n")`.  
`tests/test_identity.lua:31`

**T10 [char]** :e registers a file; help, terminal, scheme:// and otter's unlisted buffers are not registered  
`:e a`, `:help`, `:close`, `:terminal`, `:e a`, `:edit scheme://some/thing` → `eq(got, { file = true, help = false, terminal = false, scheme = false, otter = false })`  
note: otter makes its buffers with vim.uri_to_bufnr, which leaves them unlisted; listed-only tracking is what keeps them out, not their name.  
spec: `:e` on an existing file registers it. Help, terminal and `scheme://` buffers aren't registered, and neither is otter's: it makes its buffers with `vim.uri_to_bufnr`, which leaves them unlisted, and listed-only tracking keeps them out (M3), not their `otter.*` name. A file you op…  
`tests/test_identity.lua:52`

**T11 [char]** an entered No Name buffer is registered as NONAME_<id>, its id kept on the buffer (I16)  
`:e a`, `:enew` → `eq(got.path, got.want)`  
→ `eq(got.path ~= 'NONAME_' .. child.lua('return vim.api.nvim_get_current_buf()'), true)`  
spec: An entered No Name buffer is registered as `NONAME_<id>`, its id kept on the buffer (I16).  
`tests/test_identity.lua:84`

**T12 [char]** registering a second buffer under the same hash binds it to the newer one ⚑ state set by hand  
`:e a` → `eq(got, { distinct = true, same_hash = true, bound_to_newer = true, newer_reverse = true, older_reverse = 'dropped' })`  
note: Names change with autocmds off, so only register_buffer touches the registry.  
spec: Registering a second buffer under the same hash binds the hash to the newer buffer and drops the older one's reverse entry.  
`tests/test_identity.lua:96`

**T13 [char]** an unlisted buftype "" buffer that a plugin creates and enters is not registered  
`:e a` → `eq(child.lua('return vim.bo.buflisted'), false)`  
→ `eq(child.lua('return vim.bo.buftype'), '')`  
→ `eq(registered(), false)`  
spec: An unlisted `buftype ""` buffer that a plugin creates and enters isn't registered.  
`tests/test_identity.lua:123`

**T14 [char]** a buffer whose file is not written yet stays registered after it is left and re-entered  
`:e a`, `:e brandnew.txt` → `Helpers.expect.no_equality(first.hash, nil)`  
`:e a` → `eq(bound(), first.buf)`  
`:e brandnew.txt` → `eq(child.lua('return vim.api.nvim_get_current_buf()'), first.buf)`  
→ `eq(bound(), first.buf)`  
spec: A buffer whose file isn't written yet stays registered after it's left and re-entered.  
`tests/test_identity.lua:135`

## tests/test_invariants.lua (9 cases: 9 char)

**T128 [char]** I1: no duplicate among a triquetra's current, secondary and ternary ⚑ random walk; walks raised to 100 so the break shows up (about 3% of walks break today)  
note: I1. Route: <M-f>'s history fill while a cycle in another window holds the history (T198), so several windows and cycles left open across a jump. The route is rare, so this one takes 100 walks.  
spec: I1: no duplicate among a triquetra's current, secondary and ternary.  
`tests/test_invariants.lua:50`

**T129 [char]** I2: every hash referenced anywhere has a path ⚑ random walk; :enew and <M-.> doubled in the walk mix to reach the break more often  
note: I2. Routes: an empty No Name buffer closed while notes or slots name it, a reopened No Name buffer. :enew and <M-.> are doubled, so more walks reach it.  
spec: I2: every hash referenced anywhere has a path.  
`tests/test_invariants.lua:56`

**T130 [char]** I3: every triquetra has a history entry ⚑ random walk  
note: I3. Route: :vsplit.  
spec: I3: every triquetra has a history entry.  
`tests/test_invariants.lua:61`

**T131 [char]** I12: no buffer with unsaved changes is wiped by cavediver ⚑ random walk  
note: I12. Route: a new file, not on disk yet, with a typed line. Cavediver's vim.cmd and nvim_buf_delete calls are checked.  
spec: I12: no buffer with unsaved changes is ever wiped by cavediver. Wrap `vim.cmd` and `nvim_buf_delete`.  
`tests/test_invariants.lua:67`

**T132 [char]** I13: a slot action switches only the target window's buffer ⚑ random walk  
note: I13. Routes: files going missing while windows show them, so several windows and files deleted (and written back) on disk.  
spec: I13: a slot action switches only the target window's buffer.  
`tests/test_invariants.lua:73`

**T133 [char]** I11: ordered.crux is newest first and holds only registered open buffers ⚑ random walk  
note: Checked after every action that isn't a cycling key or pick, while navigation is normal (the list is frozen on purpose while cycling).  
spec: I11: `ordered.crux` is sorted, newest first, and holds only registered open buffers after any non-cycling action.  
`tests/test_invariants.lua:79`

**T334 [char]** I14: a save never throws on cavediver's own data, over random walks ⚑ random walk  
note: I14. A save after every action, over the one-window, several-window and closing mixes: the save hook is critical, so any throw on cavediver's own data would reach the session manager's save.  
spec: (I14) A save never throws on cavediver's own data: random walks over the one-window, several-window and closing mixes (`:enew`, `<M-.>`, `<M-S-w>`, a new file with text) call `save_session(cwd)` after every action, and no call throws. The save hook is critical (I21), so a throw w…  
`tests/test_invariants.lua:86`

**T154 [char]** no restore throws "Remembered … is the same as current …" (Q13) ⚑ random walk  
note: The spec's single-window walks.  
spec: No restore throws: `<M-;><M-r>` and `<M-;><M-t>` never throw "Remembered … is the same as current …" (Q13). Random walks with Q6's fix still found the ternary restore throwing 13 times in 1,500; those routes were traced to arrivals that skip the stale-note check in navigation, an…  
`tests/test_invariants.lua:93`

**T157 [char]** I19: <M-;><M-x> on an empty queue that is switched on gives p=[A]on (Q14) ⚑ state set by hand  
`:e a` → `primary = '[]on'`  
`<M-;><M-x>` → `primary = '[a]on'`  
note: The empty, switched-on queue is set directly (a primary file deleted on disk doesn't empty the queue, since missing files stay tracked).  
spec: (Q14) I19, A9: on an empty queue that's switched on, one `<M-;><M-x>` gives `p=[A]on`. **[run s19]** recorded it giving `p=[A]off`, before the fix. The test sets the empty, switched-on state directly: s19's route, deleting the open primary's file on disk, keeps the primary in the…  
`tests/test_invariants.lua:99`

## tests/test_lifecycle.lua (7 cases: 7 char)

**T21 [char]** a first :e x in a fresh window gives {c=x}  
`:e x` → `slots = '⦉-⦊ [x] ⟦-⟧'`  
→ `notes = 'dtm{} dsm{}'`  
→ `primary = '[]off'`  
spec: A first `:e x` in a fresh window gives `{c=x}`.  
`tests/test_lifecycle.lua:31`

**T22 [char]** :vsplit gives the new window a fresh {c=<shown>}, not a copy  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `<M-;><M-c>` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `primary = '[d]on'`  
`:vsplit` → `Helpers.expect.no_equality(w2, w1)`  
→ `slots = '⦉-⦊ [d] ⟦-⟧'`  
→ `notes = 'dtm{} dsm{}'`  
→ `primary = '[]off'`  
→ `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `notes = w1_notes`  
… and 1 more  
note: the old window is untouched  
spec: `:vsplit` gives the new window a fresh `{c=<shown>}`, not a copy.  
`tests/test_lifecycle.lua:38`

**T23 [char]** a float never gets a triquetra  
`:e a`, `:e b` → `slots = 'no triquetra'`  
`:e c` → `eq(child.lua('return vim.api.nvim_get_current_win()'), float)`  
→ `slots = 'no triquetra'`  
note: a visit inside the float doesn't give it one either  
spec: A float never gets a triquetra.  
`tests/test_lifecycle.lua:57`

**T24 [char]** an acwrite buffer shown in the window keeps the triquetra  
`:e a`, `:e b`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
→ `eq(child.lua('return vim.bo.buftype'), 'acwrite')`  
→ `slots = '⦉-⦊ [c] ⟦b⟧'`  
spec: An `acwrite` buffer shown in the window keeps the triquetra.  
`tests/test_lifecycle.lua:72`

**T25 [char]** closing a window drops its triquetra and its UI cache ⚑ state set by hand  
`:e a`, `:vsplit`, `:e b` → `eq(state(), { triquetra = true, ui_cache = true })`  
`:close` → `eq(state(), { triquetra = false, ui_cache = false })`  
spec: Closing a window drops its triquetra and its UI cache.  
`tests/test_lifecycle.lua:80`

**T26 [char]** :terminal in a window with {c=c s=b} keeps its triquetra, and the terminal stays untracked (the visiting rule)  
`:e a`, `:e b`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
`:terminal` → `eq(child.lua('return vim.bo.buftype'), 'terminal')`  
→ `slots = '⦉-⦊ [c] ⟦b⟧'`  
→ `eq(child.lua('return require("cavediver.domains.history").get_hash_from_buffer(vim.api.nvim_get_current_buf()) == nil'), true)`  
spec: `:terminal` in a window with `{c=c s=b}` keeps its triquetra, and the terminal stays untracked (the visiting rule, A2). T27 covers coming back. **[run s15]** recorded the triquetra dropped, before the visiting rule.  
`tests/test_lifecycle.lua:100`

**T27 [char]** the window keeps {c=c s=b} while it shows a terminal, and :e c returns to it intact  
`:e a`, `:e b`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
`:terminal` → `eq(child.lua('return vim.bo.buftype'), 'terminal')`  
→ `slots = '⦉-⦊ [c] ⟦b⟧'`  
`:e c` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
spec: The window keeps `{c=c s=b}` while it shows the terminal, and `:e c` returns with its slots intact (the visiting rule).  
`tests/test_lifecycle.lua:111`

## tests/test_missing.lua (7 cases: 7 char)

**T343 [char]** files that go missing at a branch switch are tagged with the branch being left, shown in the winbar, and cleared when they come back  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:bdelete b.txt`, `:doautocmd FocusGained` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq(tag_of('b'), 'feature')`  
→ `eq(child.lua('return vim.wo.winbar'):find('⎇feature', 1, true) ~= nil, true)`  
→ `eq(tag_of('b'), vim.NIL)`  
→ `eq(child.lua('return vim.wo.winbar'):find('⎇', 1, true), nil)`  
note: b sits closed in the secondary when it goes missing with the switch.  
spec: (M14) Files that go missing at a branch switch are tagged with the branch being left, the winbar shows it, and it clears when they come back: with `.git/HEAD` at `ref: refs/heads/feature` and b closed in the secondary (`⦉c⦊ [d] ⟦b⟧`), b.txt deleted and HEAD set to `ref: refs/head…  
`tests/test_missing.lua:37`

**T344 [char]** with no label, a file that goes missing is tagged with the time  
`:e a`, `:e b`, `:e c`, `:bdelete b.txt` → `eq(type(tag) == 'string' and tag:match('^%d%d:%d%d$') ~= nil, true)`  
spec: (M14) With no label (no `.git` found), a file that goes missing is tagged with the time it went missing, `HH:MM`.  
`tests/test_missing.lua:58`

**T345 [char]** a label provider in config names the label  
`:e a`, `:e b`, `:e c`, `:bdelete b.txt` → `eq(tag_of('b'), 'jj:main')`  
spec: (M14) A label provider in config names the label: with `label_provider` returning `jj:main`, a closed file that goes missing is tagged `jj:main`.  
`tests/test_missing.lua:68`

**T346 [char]** disable() stops the HEAD watch  
`:e a`, `:e b`, `:e c`, `:bdelete b.txt`, `:doautocmd FocusGained` → `eq(tag_of('b'), vim.NIL)`  
spec: (M14, A25) `disable()` stops the watch on `.git/HEAD`: after it, b.txt deleted and HEAD switched tag nothing.  
`tests/test_missing.lua:78`

**T346 [char]** a save after disable() doesn't watch .git/HEAD again  
`:e a`, `:e b`, `:e c`, `:bdelete b.txt`, `:doautocmd FocusGained` → `eq(Misc.save(child), { true })`  
→ `eq(tag_of('b'), vim.NIL)`  
note: A save runs a cleanup pass, which reads the label again; after disable() it doesn't start the watch.  
spec: (M14, A25) `disable()` stops the watch on `.git/HEAD`: after it, b.txt deleted and HEAD switched tag nothing.  
`tests/test_missing.lua:95`

**T347 [char]** the label at a save is the one being left at the next load: a file gone while no editor was open is tagged with the branch the session was saved on  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:bdelete b.txt` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq(tag_of('b'), 'feature')`  
note: The session is saved on feature; HEAD moves to main and b.txt goes while no editor is open, so the next load is the first to see either. after the start: a child's setup writes the project's files again  
spec: (M14, S1) The label at a save is the one being left at the next load: saved with `.git/HEAD` at `ref: refs/heads/feature` and b closed in the secondary (`⦉c⦊ [d] ⟦b⟧`), then, in a fresh process, HEAD set to `ref: refs/heads/main` and b.txt deleted before the load: the load tags b…  
`tests/test_missing.lua:112`

**T348 [char]** a file that was never written isn't tagged; once written and deleted, it is  
`:e a`, `:e brandnew.txt` → `eq({ tag = tag_of('brandnew'), winbar = child.lua('return vim.wo.winbar'):find('⎇', 1, true) ~= nil },`  
`:write` → `eq(type(tag_of('brandnew')), 'string')`  
spec: (M14) A file that was never written isn't tagged, since it never went missing: `:e brandnew.txt` with a line typed, and a cleanup pass, leave it untagged, with no `⎇` in the winbar; once it's written and then deleted on disk, the next pass tags it.  
`tests/test_missing.lua:133`

## tests/test_navigation.lua (11 cases: 11 char)

**T28 [char]** {c=a}, :e b gives {c=b t=a} with no map entries  
`:e a` → `slots = '⦉-⦊ [a] ⟦-⟧'`  
`:e b` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
→ `notes = 'dtm{} dsm{}'`  
spec: `{c=a}`, `:e b` → `{c=b t=a}`, with no map entries.  
`tests/test_navigation.lua:17`

**T29 [char]** {c=b t=a}, :e c gives {c=c t=b} with dtm{b>a}  
`:e a`, `:e b` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
`:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `notes = 'dtm{b>a} dsm{}'`  
spec: `{c=b t=a}`, `:e c` → `{c=c t=b}`, `dtm{b→a}`.  
`tests/test_navigation.lua:25`

**T30 [char]** :e onto the secondary swaps current and secondary and writes the swap notes <M-f> writes (D8)  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq(X.maps(child).dtm.c, nil)`  
`:e b` → `slots = '⦉c⦊ [b] ⟦d⟧'`  
→ `eq(before, 'dtm{b>a} dsm{b>a}')`  
→ `notes = 'dtm{b>a d-swap>c} dsm{b>a d-swap>b}'`  
note: <M-f> graduates b; then :e d gives ⦉c⦊ [d] ⟦b⟧, where dtm[c] is unset (≠ b) d is left by a swap onto the secondary, so it gets swap notes for its secondary and ternary.  
spec: Going to the secondary with `:e` swaps current and secondary and writes the notes `<M-f>` writes, when `dtm[T] ≠ S` (for `dtm[T] = S`, see T151): the buffer left gets `dsm[A-swap] = S` and `dtm[A-swap] = T` (D8, T191). Built in step 3.  
`tests/test_navigation.lua:33`

**T31 [char]** :e onto the ternary swaps current and ternary and does not write dtm[current]  
`:e a`, `:e b`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `notes = 'dtm{b>a} dsm{}'`  
`:e b` → `slots = '⦉c⦊ [b] ⟦-⟧'`  
→ `notes = 'dtm{b>a} dsm{}'`  
spec: Going to the ternary with `:e` swaps current and ternary and doesn't write `dtm[current]`.  
`tests/test_navigation.lua:46`

**T32 [char]** a plain navigation that writes dtm[A] also deletes dtm[A-swap]  
`:e a`, `:e b`, `:e c`, `<M-S-f>`, `<M-S-f>` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `eq(X.maps(child).dtm['c-swap'], 'b')`  
`:e d` → `slots = '⦉c⦊ [d] ⟦-⟧'`  
→ `eq(dtm.c, 'b')`  
→ `eq(dtm['c-swap'], nil)`  
note: two <M-S-f> leave c with a swap note: ⦉b⦊ [c], dtm[c-swap] = b  
spec: A plain navigation that writes `dtm[A]` also deletes `dtm[A-swap]`.  
`tests/test_navigation.lua:55`

**T33 [char]** with dtm[X] = A and the ternary T ≠ X, :e X from A rewrites dtm[X] := T with the "pre-jump ternary" warning  
`:e a`, `:e b`, `:e c`, `:e a` → `slots = '⦉c⦊ [a] ⟦-⟧'`  
→ `eq(X.maps(child).dtm.b, 'a')`  
`:e b` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
→ `eq(X.maps(child).dtm.b, 'c')`  
→ `eq(#warns, 1)`  
→ `eq(warns[1].level, vim.log.levels.WARN)`  
note: :e c from b writes dtm[b] = a; back at a (ternary c), b's note names a, the buffer :e b is about to leave.  
spec: With `dtm[X] = A` and the ternary T ≠ X, `:e X` from A rewrites `dtm[X] := T`, with the "pre-jump ternary" warning.  
`tests/test_navigation.lua:67`

**T34 [char]** navigation with secondary equal to ternary reports "Duplicates detected in current triquetra" ⚑ state set by hand  
`:e a`, `:e b`, `:e c`, `:e d` → `slots = '⦉c⦊ [d] ⟦c⟧'`  
`:e a` → `eq(#errs, 1)`  
→ `eq(errs[1].level, vim.log.levels.ERROR)`  
→ `shown = 'a'`  
→ `slots = '⦉c⦊ [d] ⟦c⟧'`  
note: s = t can't be reached by keys here; set it directly, as run s18 does the hook stops before any slot moves (A1)  
spec: Navigation with secondary equal to ternary reports "Duplicates detected in current triquetra".  
`tests/test_navigation.lua:82`

**T35 [char]** entering an untracked buffer the triquetra is kept for (acwrite) leaves the slots alone ⚑ state set by hand  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq(child.lua('return vim.bo.buftype'), 'acwrite')`  
→ `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `notes = notes`  
spec: Entering an untracked buffer, such as an `acwrite` buffer, leaves the slots alone (A2). For `:terminal` shown in the window, see T26 and T27.  
`tests/test_navigation.lua:97`

**T151 [char]** Q6 on plain navigation: :e onto the secondary rewrites the ternary's note, and the restore then works  
`:e a`, `:e b`, `:e c`, `:e b`, `<M-f>`, `:e a`, `<M-f>` → `slots = '⦉b⦊ [c] ⟦a⟧'`  
→ `eq(X.maps(child).dtm.b, 'a')`  
`:e a` → `slots = '⦉b⦊ [a] ⟦c⟧'`  
→ `eq(X.maps(child).dtm.b, 'c')`  
`<M-S-f>`, `<M-;><M-r>` → `eq({ ok, err }, { true, nil })`  
→ `slots = '⦉c⦊ [b] ⟦a⟧'`  
note: :e a reaches the secondary by plain navigation  
spec: Q6 on plain navigation: `:e a`, `:e b`, `:e c`, `:e b`, `<M-f>`, `:e a`, `<M-f>`, then `:e a` again, which reaches the secondary by plain navigation. The ternary's note is rewritten to the buffer left (`dtm[b] := c`), and `<M-S-f>`, `<M-;><M-r>` then restores without throwing, gi…  
`tests/test_navigation.lua:114`

**T191 [char]** (D8) plain navigation onto the secondary writes the swap notes dsm{d-swap>b} dtm{d-swap>c}, no dsm[d]  
`:e b`  
spec: (D8, "Keep the older one") `<M-f>` and plain navigation onto the secondary write the same notes: from `⦉c⦊ [d] ⟦b⟧`, either one gives `⦉c⦊ [b] ⟦d⟧` with the swap notes `dsm{d-swap>b}` and `dtm{d-swap>c}`, and no plain secondary note for d. T30 and T39 pin the same notes. Plain na…  
`tests/test_navigation.lua:141`

**T191 [char]** (D8) <M-f> onto the secondary writes the swap notes dsm{d-swap>b} dtm{d-swap>c}, no dsm[d]  
`<M-f>`  
spec: (D8, "Keep the older one") `<M-f>` and plain navigation onto the secondary write the same notes: from `⦉c⦊ [d] ⟦b⟧`, either one gives `⦉c⦊ [b] ⟦d⟧` with the swap notes `dsm{d-swap>b}` and `dtm{d-swap>c}`, and no plain secondary note for d. T30 and T39 pin the same notes. Plain na…  
`tests/test_navigation.lua:147`

## tests/test_negative.lua (48 cases: 40 char, 8 target)

**T207 [char]** (P5) a nofile scratch entered in a tracked window is not registered  
`:e a`, `:e b` → `eq(registered(), true)`  
→ `eq(child.lua('return vim.bo.buftype'), 'nofile')`  
→ `eq(registered(), false)`  
spec: (P5) A `nofile` scratch entered in a tracked window isn't registered (M3). Help, terminal, `scheme://` and otter buffers are T10; the quickfix list is T217.  
`tests/test_negative.lua:72`

**T208 [char]** (P10, I17) the notes about an empty No Name buffer go once it is wiped  
`:e a`, `:e b`, `:e c`, `:enew` → `eq(type(h), 'string')`  
`:e b`, `:e d` → `slots = '⦉b⦊ [d] ⟦-⟧'`  
→ `eq(#child.refs(h) > 0, true)`  
→ `closed = ''`  
→ `eq(child.refs(h), {})`  
note: N is an empty No Name buffer that ends up only in the notes: a key (N>c) and a value (b>N). Wiping it pushes nothing (M5); its path stays only because the notes still name it (I2), so once the notes follow along, nothing names it.  
spec: (P10, I17) Notes follow along: `:e a`, `:e b`, `:e c`, `:enew` (an empty No Name N), `:e b`, `:e d` leave N only in the notes (`N>c`, `b>N`). After `:bwipeout` of N, which pushes nothing (M5), no note names N. Before step 6 both notes stayed, since the maps were never pruned, and…  
`tests/test_negative.lua:84`

**T209 [char]** (P14) the secondary changes only when you act: navigation elsewhere, cycle steps, a split and a window jump leave it  
`:e a`, `:e b`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
→ `eq(secondary(), 'b')`  
`<M-m>`, `<M-m>` → `eq(child.state(), CYCLING)`  
→ `eq(secondary(), 'b')`  
`<M-;><M-f>`, `<M-v>` → `eq(child.state(), NORMAL)`  
→ `slots = '⦉e⦊ [a] ⟦b⟧'`  
`:vsplit`, `:wincmd p` → `eq(child.win(), w1)`  
→ `slots = '⦉e⦊ [a] ⟦b⟧'`  
note: Steps only, then back to the start and pick it: no slot moves.  
spec: (P14) The secondary changes only when you act: from `⦉-⦊ [c] ⟦b⟧` (`:e a`, `:e b`, `:e c`, `<M-f>`), `:e d`, `:e e`, `:e a`, two cycle steps, `<M-;><M-f>` and `<M-v>` on the start, then `:vsplit` and `<C-w>p` back, leave the secondary on b: `⦉e⦊ [a] ⟦b⟧`.  
`tests/test_negative.lua:98`

**T210 [char]** (P17) navigation and slot keys in one window leave another window's triquetra alone  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `<M-;><M-c>` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
`:vsplit`, `:e e`, `:e a`, `<M-f>`, `<M-f>`, `<M-S-f>`, `:e b`, `<M-;><M-c>`, `<M-;><M-r>` → `eq({ child.slots(w1), child.notes(w1), child.primary(w1) }, before)`  
`:wincmd p` → `eq(child.win(), w1)`  
→ `eq({ child.slots(w1), child.notes(w1), child.primary(w1) }, before)`  
spec: (P17) Every window is independent: with window 1 on `⦉c⦊ [d] ⟦b⟧` and `p=[d]on`, `:vsplit`, then `:e e`, `:e a`, `<M-f>`, `<M-f>`, `<M-S-f>`, `:e b`, `<M-;><M-c>`, `<M-;><M-r>` in window 2 leave window 1's slots, notes and primary queue as they were, and so does `<C-w>p` back int…  
`tests/test_negative.lua:122`

**T211 [char]** (P20) restoring is only ever explicit: an empty ternary stays empty until <M-;><M-r>  
`:e a`, `:e b`, `:e c`, `:e d`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦d⟧'`  
→ `eq(K.note(child, 'dtm', 'c'), 'b')`  
→ `slots = '⦉-⦊ [c] ⟦d⟧'`  
`<M-S-f>` → `eq(Extra.has(child.messages(), 'No ternary buffer to swap with.'), true)`  
→ `slots = '⦉-⦊ [c] ⟦d⟧'`  
→ `shown = 'c'`  
`<M-;><M-r>` → `slots = '⦉b⦊ [c] ⟦d⟧'`  
note: c's note c>b is on record while c's ternary is empty (graduation took d).  
spec: (P20) Restoring is only ever explicit: at `⦉-⦊ [c] ⟦d⟧` (`:e a`, `:e b`, `:e c`, `:e d`, `:e c`, `<M-f>`) with c's note `c>b`, a wait leaves the ternary empty, `<M-S-f>` says "No ternary buffer to swap with." and changes nothing, and only `<M-;><M-r>` brings b back: `⦉b⦊ [c] ⟦d⟧`…  
`tests/test_negative.lua:140`

**T212 [char]** (P22, S2) the session file is written with mode 0600 ⚑ the child's umask forced to 022, so the result doesn't depend on the runner  
`:e a`, `:e b` → `eq(Misc.save(child), { true })`  
→ `eq(#files, 1)`  
→ `eq(child.lua('return vim.fn.getfperm(...)', { dir .. files[1] }), 'rw-------')`  
note: The usual umask, so a file written with default permissions shows.  
spec: (P22, S2) The session file is written with mode 0600 whatever the umask: `rw-------` with a umask of 022 (S1 File).  
`tests/test_negative.lua:155`

**T213 [char]** (P24, M6) a save with a No Name current slot leaves the live triquetra as it was  
`:e a`, `:e b`, `:enew` → `eq(before.slots:match('^⦉b⦊ %[NONAME_%d+%] ⟦%-⟧$') ~= nil, true)`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Neg.snapshot(child), before)`  
→ `eq(Neg.snapshot(child), before)`  
spec: (P24, M6) A save with a No Name current slot leaves the live triquetra, the notes, the primary queue, the closed stack and the history order as they were: the save writes the slots as they are, the No Name current slot included.  
`tests/test_negative.lua:170`

**T214 [char]** (P24) a save leaves the closed stack as it was, a closed file gone from disk included  
`:e a`, `:e b`, `:e c`, `:e d` → `slots = '⦉c⦊ [d] ⟦-⟧'`  
`:bdelete b.txt` → `closed = 'b'`  
→ `eq(got.ok, true)`  
→ `eq(got.after, got.before)`  
note: b is closed and outside the slots; its file goes, then the save, in one call so no other pass runs in between.  
spec: (P24, A22) A save leaves the closed stack as it was: with b closed and outside the slots, deleting b.txt and saving straight away keeps b on the stack, and the slots, the notes and the history order stay as they were too. Before step 6 the save's `cleanup_system` dropped b, in it…  
`tests/test_negative.lua:184`

**T215 [target]** (P26) with harpoon not installed, navigation, the slot keys and the UI raise nothing  
→ `eq(child.lua('return (pcall(require, "harpoon"))'), false)`  
→ `eq(raised, {})`  
→ `eq(Extra.at_least(child.messages()), {})`  
→ `slots = '⦉d⦊ [c] ⟦b⟧'`  
note: Ex commands raise; keys return ok, err.  
spec: (P26) With harpoon not installed, `:e`, `<M-f>`, `<M-S-f>`, `<M-;><M-c>`, `<M-;><M-r>` and the UI ticks raise nothing and report no hook failure. Today every history update fails at `history/routines.lua:878` with "module 'harpoon' not found".  
`tests/test_negative.lua:202`

**T216 [char]** (I16) a No Name id is not reused across sessions  
`:e a`, `:enew` → `eq(one.buf, two.buf)`  
→ `eq(type(one.hash), 'string')`  
→ `eq(type(two.hash), 'string')`  
note: Two fresh processes, the same steps, so the No Name buffer gets the same buffer number in both.  
spec: (I16) A No Name id isn't reused across sessions: two fresh processes that each run `:e a`, `:enew` get the same buffer number and different ids.  
`tests/test_negative.lua:222`

**T217 [char]** (I10, A1) a buffer whose buftype turns nofile after it is entered is not left registered or in a slot  
`:e a`, `:enew` → `eq(type(h), 'string')`  
`:setlocal buftype=nofile`, `:e b` → `eq(child.lua('return vim.api.nvim_buf_is_valid(...)', { n }), true)`  
→ `eq(registered(n), false)`  
→ `eq(Neg.in_slots(child, h), false)`  
note: A buffer a plugin makes: entered as buftype "", then turned nofile. It has text, so the next :e doesn't reuse it.  
spec: (I10, A1, A2) A buffer that turns into something untracked isn't left registered or in a slot. Two routes: a buffer entered as `buftype ""` and then set to `nofile`, as a plugin's scratch is, followed by `:e b`; and `:copen`, which enters its buffer before it's a quickfix buffer …  
`tests/test_negative.lua:240`

**T217 [char]** (I10, A2) a :copen quickfix buffer is not left registered, and its window gets no triquetra  
`:e a`, `:e b`, `:copen` → `eq(child.lua('return vim.bo.buftype'), 'quickfix')`  
→ `eq(registered(), false)`  
→ `slots = 'no triquetra'`  
note: :copen enters the new quickfix buffer before its buftype is set (DESK:2453).  
spec: (I10, A1, A2) A buffer that turns into something untracked isn't left registered or in a slot. Two routes: a buffer entered as `buftype ""` and then set to `nofile`, as a plugin's scratch is, followed by `:e b`; and `:copen`, which enters its buffer before it's a quickfix buffer …  
`tests/test_negative.lua:255`

**T218 [target]** (I18) a repeated file in the primary queue window is refused with an error, and saved once  
`:write` → `eq(errors >= 1, true)`  
→ `primary = '[a,b]on'`  
note: Decided 2026-10-21: a repeated file is refused loudly, like a typo'd path (Q11's partial save).  
spec: (I18) A repeated file in the primary queue window is refused loudly: from `[b,a]on`, the lines `a`, `b`, `a` save `[a,b]` and report the repeat at error level, like a typo'd path under Q11's partial save. Today `[a,b,a]`: `update_primary_buffer` doesn't dedupe. Decided 2026-10-21…  
`tests/test_negative.lua:266`

**T219 [char]** (I19, Q14) an empty queue that is switched on stays on: navigation, slot keys and UI ticks leave it ⚑ state set by hand  
`:e a`, `:e b` → `primary = '[]on'`  
→ `primary = '[]on'`  
→ `primary = '[]on'`  
spec: (I19, Q14) An empty queue that's switched on stays on: from `p=[]on`, `:e c`, `<M-f>`, `<M-;><M-f>`, `:e a`, `<M-S-f>` and the UI ticks leave `p=[]on`.  
`tests/test_negative.lua:281`

**T220 [target]** (M11, D23) the winbar and indicator toggles work at runtime  
`:e a`, `:e b` → `eq(child.lua('return vim.wo.winbar ~= ""'), true)`  
→ `eq(got, { hide_winbar = true, show_winbar = true, hide_indicators = true, show_indicators = true })`  
→ `eq(child.lua('return vim.wo.winbar'), '')`  
→ `eq(child.lua('return vim.wo.winbar ~= ""'), true)`  
→ `eq(child.lua('return require("cavediver").ui.is_hidden("indicators")'), true)`  
→ `eq(child.lua('return require("cavediver").ui.is_hidden("indicators")'), false)`  
note: Decided 2026-10-21: the toggles are built (how they're exposed, key or command, comes later). Hidden stays hidden through the refresh, and shown comes back.  
spec: (M11, D23) The winbar and indicator toggles work at runtime: `hide_winbar()` empties the winbar and it stays empty through the refresh, `show_winbar()` brings it back, and `hide_indicators()`/`show_indicators()` switch the indicators off and on. Today the winbar machine doesn't e…  
`tests/test_negative.lua:300`

**T221 [target]** (M11) unregister_hook(name) removes that hook from its machine, and nothing else, without throwing  
→ `eq(got, { ok = true, ran = { 'one.g', 'two.h' }, reusable = true })`  
spec: (M11) `unregister_hook(name)` removes that hook from its own machine and nothing else, without throwing, and the name can be bound again. Today it calls the class instead of the instance (`state-machine.lua:382`), throws, and the hook still runs.  
`tests/test_negative.lua:326`

**T222 [char]** (M1, D4) hashing a file name runs no shell  
→ `eq(registered(), true)`  
→ `eq(calls, 0)`  
spec: (M1, D4) Hashing a file name runs no shell: `:e a` and `:e b` make no `vim.fn.system`, `io.popen` or `vim.system` call.  
`tests/test_negative.lua:349`

**T223 [char]** (A1, A3) going back into a window onto its current slot changes no slot and writes no note  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
`:vsplit`, `:e e` → `slots = '⦉d⦊ [e] ⟦-⟧'`  
`:wincmd p` → `eq(child.win(), want)`  
→ `eq({ child.slots(w1), child.notes(w1), child.slots(w2), child.notes(w2) }, before)`  
spec: (A1, A3) Going back into a window onto its current slot changes nothing: with window 1 on `⦉c⦊ [d] ⟦b⟧` and window 2 on `⦉d⦊ [e] ⟦-⟧`, `<C-w>p` three times leaves both windows' slots and notes as they were (A1's row X = A).  
`tests/test_negative.lua:367`

**T224 [char]** (A1) a visit made in another window with win_execute moves that window's slots, not the focused one's  
`:e a`, `:e b`, `:vsplit`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
`:wincmd p` → `eq(child.win(), w1)`  
→ `slots = '⦉a⦊ [b] ⟦-⟧'`  
→ `eq(child.win(), w1)`  
→ `shown = 'b'`  
→ `slots = '⦉a⦊ [b] ⟦-⟧'`  
→ `slots = '⦉c⦊ [d] ⟦-⟧'`  
spec: (A1) A visit made in another window lands in that window, never the focused one: with window 1 focused on `⦉a⦊ [b] ⟦-⟧`, `:edit d.txt` run in window 2 through `win_execute` gives window 2 `⦉c⦊ [d] ⟦-⟧`, and window 1 keeps the focus, its buffer and its slots **[code]**. The histor…  
`tests/test_negative.lua:384`

**T225 [char]** (A2, M6) windows born untracked (:help, :split | terminal) never get a triquetra  
`:e a`, `:e b` → `slots = 'no triquetra'`  
`:wincmd p`, `:wincmd p` → `eq(child.win(), w)`  
→ `slots = 'no triquetra'`  
note: A jump out and back in, and UI ticks.  
spec: (A2, M6) Windows born untracked never get a triquetra: a `:help` window and a `:split | terminal` window have none, after UI ticks and a jump out and back in. A `:copen` window is T217's second route.  
`tests/test_negative.lua:403`

**T226 [char]** (A6, A7, A8) with no triquetra, <M-f>, <M-S-f> and <M-;><M-f> warn "Window with unregistered buffer." and change nothing  
`:e a`, `:e b`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
`:help` → `slots = 'no triquetra'`  
→ `eq({ key, ok, err }, { key, true, nil })`  
→ `eq({ key, Extra.has(child.messages(), 'Window with unregistered buffer.') }, { key, true })`  
→ `eq(child.win(), hw)`  
→ `eq(child.lua('return vim.api.nvim_get_current_buf()'), hb)`  
→ `slots = 'no triquetra'`  
→ `slots = '⦉-⦊ [c] ⟦b⟧'`  
spec: (A6, A7, A8) With no triquetra (a `:help` window), `<M-f>`, `<M-S-f>` and `<M-;><M-f>` each warn "Window with unregistered buffer.", raise nothing, switch nothing, and leave the other window's slots alone.  
`tests/test_negative.lua:425`

**T227 [char]** (A7, P9) <M-S-f> on a closed ternary whose file is gone says so and keeps the pointer  
`:e a`, `:e b`, `:e c`, `:bdelete b.txt` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `closed = 'b'`  
→ `eq({ ok, err }, { true, nil })`  
→ `eq(K.hook_failures(msgs), {})`  
→ `slots = '⦉b⦊ [c] ⟦-⟧'`  
note: b is closed and stays in the ternary (T102); its file is deleted in the same call as the key, before any other pass.  
spec: (A7, P9) `<M-S-f>` on a closed ternary whose file is gone from disk says so and keeps the pointer: `:e a`, `:e b`, `:e c`, `:bdelete b.txt`, then b.txt deleted and `<M-S-f>` pressed straight away give a warning, no throw, and `⦉b⦊ [c] ⟦-⟧`. Before step 6 it said "Removed ternary …  
`tests/test_negative.lua:448`

**T228 [char]** (A11, D9) a restore switches no buffer and reopens nothing: a closed hash waits in the slot until <M-S-f> uses it  
`:e a`, `:e b`, `:e c`, `:e d`, `:e b` → `slots = '⦉d⦊ [b] ⟦-⟧'`  
→ `eq(K.note(child, 'dtm', 'b'), 'a')`  
`:bdelete a.txt` → `closed = 'a'`  
`<M-;><M-r>` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
→ `shown = 'b'`  
→ `eq(child.lua('return vim.fn.bufloaded(_G.CDV_TEST.root .. "/a.txt")'), 0)`  
→ `closed = 'a'`  
→ `slots = '⦉a⦊ [b] ⟦-⟧'`  
… and 3 more  
spec: (A11, D9) A restore switches no buffer and reopens nothing: at `⦉d⦊ [b] ⟦-⟧` with `dtm{b>a}` and a closed with `:bdelete`, `<M-;><M-r>` gives `⦉a⦊ [b] ⟦-⟧`, still showing b, with a unloaded and still on the closed stack; `<M-S-f>` then reopens a and takes it off the stack (a clos…  
`tests/test_negative.lua:463`

**T229 [char]** (A12) a jump into a float cancels the cycle, and nothing is recorded  
spec: (A12) Any jump into another window cancels the cycle, floats and `:help` included: cycling from c with `⦉b⦊ [c] ⟦-⟧` to b, then a jump into a float, or `:help`, puts the window back on c with navigation `normal`, history attached, and the slots and the history order unchanged.  
`tests/test_negative.lua:501`

**T229 [char]** (A12) a jump into :help cancels the cycle, and nothing is recorded  
`:help`  
spec: (A12) Any jump into another window cancels the cycle, floats and `:help` included: cycling from c with `⦉b⦊ [c] ⟦-⟧` to b, then a jump into a float, or `:help`, puts the window back on c with navigation `normal`, history attached, and the slots and the history order unchanged.  
`tests/test_negative.lua:510`

**T230 [char]** (A13) a pick of an outside buffer or of the ternary writes no secondary note  
`<M-n>`, `<M-n>` → `shown = 'b'`  
`<M-v>` → `slots = '⦉d⦊ [b] ⟦c⟧'`  
→ `eq(K.dsm(child), dsm)`  
`<M-v>` → `slots = '⦉b⦊ [d] ⟦c⟧'`  
→ `eq(K.dsm(child), dsm)`  
spec: (A13) A pick writes no secondary notes: from `⦉d⦊ [e] ⟦c⟧`, a pick of b (outside the slots) and then a pick of the ternary leave the secondary map as it was. The pick of the secondary is T73.  
`tests/test_negative.lua:514`

**T231 [char]** (A14, Q7) <M-;><M-f> while cycling on the start announces the origin again and changes nothing  
`<M-m>`, `<M-n>` → `shown = 'e'`  
→ `eq(child.state(), CYCLING)`  
`<M-;><M-f>` → `eq(Extra.has(child.messages(), 'Returned to cycling origin buffer'), true)`  
→ `eq({ child.slots(), child.notes(), child.shown(), child.ordered() }, before)`  
→ `eq(child.state(), CYCLING)`  
spec: (A14, Q7) `<M-;><M-f>` while cycling with the window already on the start says "Returned to cycling origin buffer" each time and changes nothing: the slots, the notes, the shown buffer and the order stay, and navigation stays `cycling`.  
`tests/test_negative.lua:528`

**T232 [target]** (A17) <M-,> skips a previous window whose filetype is neominimap  
`:e a`, `:vsplit`, `:e b`, `<M-,>` → `eq(child.win(), w2)`  
→ `eq(Extra.has(child.messages(), 'No valid previous window to toggle to.'), true)`  
spec: (A17) `<M-,>` skips a previous window whose filetype is `neominimap`, as it does `minimap` (T94): it warns "No valid previous window to toggle to." and stays.  
`tests/test_negative.lua:543`

**T233 [char]** (A18) with no triquetra, <M-;>F says "No triquetra found for current window." and opens no window  
`:e a`, `<M-;><M-c>` → `primary = '[a]on'`  
`:help` → `slots = 'no triquetra'`  
`<M-;>F` → `eq(Extra.has(child.messages(), 'No triquetra found for current window.'), true)`  
→ `eq(child.popup(), nil)`  
→ `eq(child.floats(), {})`  
spec: (A18) With no triquetra (a `:help` window, while the other window's queue is `[a]on`), `<M-;>F` says "No triquetra found for current window." and opens no window.  
`tests/test_negative.lua:556`

**T234 [char]** (A18, Q11) the pop-up rejects an untracked buffer and an unknown No Name, drops a blank line, and keeps the good lines  
`:help` → `eq(child.lua('return vim.fn.filereadable(...)', { help }), 1)`  
`:wincmd p` → `eq(child.win(), w)`  
`:write` → `primary = '[a,b]on'`  
→ `eq(#errors, 1)`  
→ `eq(errors[1]:find(help, 1, true) ~= nil, true)`  
→ `eq(errors[1]:find('NONAME_999', 1, true) ~= nil, true)`  
note: The help file is loaded, readable and untracked; NONAME_999 was never a No Name buffer cavediver knew.  
spec: (A18, Q11) The pop-up refuses what cavediver doesn't track and keeps the good lines: from `[b,a]on`, the lines `a`, a blank line, the path of a loaded help file, `NONAME_999` and `b` save `[a,b]on`, with one error naming the help file and `NONAME_999`; the blank line is dropped w…  
`tests/test_negative.lua:571`

**T235 [target]** (A18) a relative path in the primary queue window is resolved: ./b.txt becomes b, shown as b.txt ⚑ the save runs in pcall, since the hole makes the pop-up's redraw throw  
→ `eq(wrote, true)`  
→ `eq(Neg.queue_holes(child, w), 0)`  
→ `primary = '[b,a]on'`  
→ `eq(child.popup_lines(), { 'b.txt', 'a.txt' })`  
note: Decided 2026-10-21: a relative path is resolved against the current directory, as :e does. The pop-up redraws each entry by its shortest unique name.  
spec: (A18) A relative path in the primary queue window is resolved against the current directory, as `:e` does: the lines `./b.txt`, `a` save `[b,a]`, with no hole, and the pop-up redraws them as `b.txt`, `a.txt`. Today the line passes validation as typed, then its hash is looked up b…  
`tests/test_negative.lua:593`

**T236 [target]** (A5) closing another window first does not stop the pop-up's buffer going when the pop-up closes, and it opens again  
`:e a`, `<M-;><M-c>`, `:vsplit`, `:close` → `eq(child.lua('return vim.bo.filetype'), 'cavediver-primary-buffer-history')`  
`:close` → `eq(child.popup(), nil)`  
→ `eq(child.lua('return vim.api.nvim_buf_is_valid(...)', { buf }), false)`  
`<M-;>F` → `eq({ ok, err }, { true, nil })`  
→ `eq(child.lua('return vim.bo.filetype'), 'cavediver-primary-buffer-history')`  
note: And the pop-up opens again (today: E95, a buffer with this name already exists).  
spec: (A5) Closing another window first doesn't stop the pop-up's buffer going when the pop-up closes: `:vsplit`, `:close`, then `<M-;>F` and `:close` in the pop-up delete its buffer, as they do when no window was closed first. Today the first close uses up the `once` handler (`ui/hook…  
`tests/test_negative.lua:606`

**T237 [char]** (A19) with nothing left to land on, the window keeps Neovim's empty buffer and no :enew runs  
`:e a` → `eq(child.lua('return vim.api.nvim_get_current_buf()'), got.buf)`  
→ `eq(#child.lua('return vim.api.nvim_list_bufs()'), got.n)`  
note: One tracked buffer only, so nothing is left to land on: Neovim puts an empty buffer in the window, read in the same call as the delete. The rest of A19's landing order is T111's.  
spec: (A19) With nothing left to land on, the window keeps Neovim's empty buffer and no `:enew` runs: `:e a`, `:bdelete a.txt` leave the window on the buffer Neovim put there, with no buffer added. A guard on the landing (A19, built in step 1).  
`tests/test_negative.lua:628`

**T238 [char]** (A20) :w name on a No Name buffer is a move: no ghost on the closed stack, and its notes follow  
`:e a`, `:enew`, `:e b`, `:buffer #` → `closed = ''`  
→ `eq(child.notes():find('NONAME_%d+>a') ~= nil, true)`  
`:write new.txt` → `eq(child.lua('return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")'), 'new.txt')`  
→ `closed = ''`  
→ `eq(child.notes():find('new>a', 1, true) ~= nil, true)`  
→ `eq(child.notes():find('?', 1, true), nil)`  
note: The decided move (DESK:1924): no ghost on the closed stack, and the No Name's notes follow to the new name. The No Name buffer now carries a note: its ternary was a.  
spec: (A20) `:w new.txt` on a No Name buffer with text leaves no ghost entry on the closed stack: the old name isn't a file, so it's a move. Its notes follow too (the decided move, DESK:1924): a No Name buffer whose note says its ternary was a gives `new>a` after `:w new.txt`, with no …  
`tests/test_negative.lua:640`

**T239 [char]** (A21) a secondary and a ternary whose files are deleted while their buffers are open stay in their slots  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq({ registered(bufnr('b')), registered(bufnr('c')) }, { true, true })`  
note: b (the secondary) and c (the ternary) are open but hidden; their files go.  
spec: (A21) A slot pointing at an open buffer is kept whatever the disk says: at `⦉c⦊ [d] ⟦b⟧`, deleting b.txt and c.txt (both still open), UI ticks and a `cleanup_system` pass leave the slots and both registrations as they were.  
`tests/test_negative.lua:657`

**T240 [char]** (A25) disable() clears the cavediver augroup and stops the timers, and nothing is tracked after  
`:e a`, `:e b` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
→ `eq(got, { disable = 'function', ok = true, autocmds = 0, timers = 0 })`  
`:e c` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
→ `ordered = 'b,a'`  
spec: (A25) `disable()` clears the `cavediver` augroup and stops the timers, and afterwards `:e c` changes no slot and records nothing.  
`tests/test_negative.lua:668`

**T241 [target]** (A26) the flight recorder records keymap actions and events, never raw keystrokes ⚑ state set by hand  
`:e a`, `:e b`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
`<M-;><M-t>` → `eq(ok, false)`  
→ `eq(#texts > 0, true)`  
→ `eq(text:find('Q.-Z.-Q.-Z.-Q.-Z') == nil, true)`  
note: Text typed in insert mode, then the restore assertion (c's secondary note set to name the secondary by hand, as T200 does). Whatever the dump looks like, the typed keys aren't steps in it.  
spec: (A26) The recorder never records raw keystrokes: text typed in insert mode (`QZQZQZ`) before the restore assertion fires doesn't show up as steps in the dump, whatever its format, file or scratch buffer.  
`tests/test_negative.lua:689`

**T242 [char]** a tracked buffer wiped with noautocmd is repaired within one refresh, with no UI errors ⚑ state set by hand; wipes the window's current buffer: the bug only shows for that one  
`:e a`, `:e b`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `shown = 'b'`  
→ `slots = '⦉c⦊ [b] ⟦-⟧'`  
→ `eq(Extra.at_least(child.messages()), {})`  
note: A bug found while porting: a tracked buffer wiped with noautocmd, here the window's current buffer. Decided 2026-10-21: the UI repairs it on the spot, within one refresh, as cleanup's re-point would (like navigation, Q18): the window shows b, so b is current and c the ternary.  
spec: (bug (new), 2026-10-21) A tracked buffer wiped with `noautocmd` doesn't make the UI loop error: `:e a`, `:e b`, `:e c`, then `noautocmd bwipeout` of c give no hook failure over the next ticks. Without the repair, "Invalid buffer id" comes on every tick (`ui/routines.lua:553`); wi…  
`tests/test_negative.lua:723`

**T243 [char]** (I23) the check runs at graduation: a stale secondary note naming the graduated buffer is dropped ⚑ state set by hand  
`:e a`, `:e b`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
`<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
→ `eq(Neg.i23(child), nil)`  
`<M-;><M-t>` → `eq({ ok, err }, { true, nil })`  
note: The I23 check wherever a slot changes under the current buffer (decided 2026-10-21). Each stale note is planted by hand: no route is known that reaches these states with the other fixes in.  
spec: (I23) The check runs wherever a slot changes under the current buffer (decided 2026-10-21), with the stale note planted: at graduation (`⦉b⦊ [c] ⟦-⟧` with `dsm{c>b}`, `<M-f>`), at the history fill (a fresh split on b with `dsm{b>a}`, `<M-f>` fills a), and at a session load (`⦉-⦊ …  
`tests/test_negative.lua:740`

**T243 [char]** (I23) the check runs at the history fill: a stale secondary note naming the filled buffer is dropped ⚑ state set by hand  
`:e a`, `:e b`, `:vsplit` → `slots = '⦉-⦊ [b] ⟦-⟧'`  
→ `ordered = 'b,a'`  
`<M-f>` → `slots = '⦉-⦊ [b] ⟦a⟧'`  
→ `eq(Neg.i23(child), nil)`  
`<M-;><M-t>` → `eq({ ok, err }, { true, nil })`  
spec: (I23) The check runs wherever a slot changes under the current buffer (decided 2026-10-21), with the stale note planted: at graduation (`⦉b⦊ [c] ⟦-⟧` with `dsm{c>b}`, `<M-f>`), at the history fill (a fresh split on b with `dsm{b>a}`, `<M-f>` fills a), and at a session load (`⦉-⦊ …  
`tests/test_negative.lua:751`

**T243 [char]** (I23) the check runs at a session load: a stale note from the file is dropped ⚑ state set by hand  
`:e a`, `:e b`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
→ `eq(Neg.i23(child), 'dsm')`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `slots = '⦉-⦊ [c] ⟦b⟧'`  
→ `eq(Neg.i23(child), nil)`  
spec: (I23) The check runs wherever a slot changes under the current buffer (decided 2026-10-21), with the stale note planted: at graduation (`⦉b⦊ [c] ⟦-⟧` with `dsm{c>b}`, `<M-f>`), at the history fill (a fresh split on b with `dsm{b>a}`, `<M-f>` fills a), and at a session load (`⦉-⦊ …  
`tests/test_negative.lua:765`

**T244 [char]** (S2) a load into fewer windows matches by what they show and drops the unmatched entry, without an error  
`:e a`, `:e b`, `:vsplit`, `:e c`, `:e d` → `slots = '⦉c⦊ [d] ⟦-⟧'`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq(Misc.errors(child), {})`  
→ `slots = '⦉a⦊ [b] ⟦-⟧'`  
note: Saved: the split (listed first) ⦉c⦊ [d], the first window ⦉a⦊ [b]. The manager brings back one window, on b.  
spec: (S2) A load into fewer windows than were saved matches by what they show and drops the unmatched entry, with no error: two windows saved (`⦉c⦊ [d] ⟦-⟧` in the split, `⦉a⦊ [b] ⟦-⟧`) and one restored on b give `⦉a⦊ [b] ⟦-⟧`.  
`tests/test_negative.lua:786`

**T245 [char]** (S2) a session file with a newer header says it was made by a newer cavediver and is left alone  
`:e a`, `:e b` → `eq(Misc.save(child), { true })`  
→ `eq(#saved, 1)`  
→ `eq(Extra.has(child.messages(), 'newer cavediver'), true)`  
→ `eq(bytes, 'CDV9\nfrom a later version\n')`  
spec: (S2) A session file with a newer header gives "made by a newer cavediver" and is left alone: a file starting `CDV9` is unchanged after the load.  
`tests/test_negative.lua:804`

**T246 [char]** (S2) a No Name buffer closed with <M-.> stays on the closed stack across a save and a load  
`:e a`, `:enew`, `<M-.>` → `shown = 'a'`  
→ `eq(#child.lua('return require("cavediver.domains.history").data.closed_buffers'), 1)`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq(#child.lua('return require("cavediver.domains.history").data.closed_buffers'), 1)`  
`<M-S-w>` → `eq(child.lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'kept text' })`  
note: It held before the encrypted format and holds with it.  
spec: (S2) A No Name buffer closed with `<M-.>` stays on the closed stack across a save and a load, and `<M-S-w>` then brings its text back. It held before save-as-closed was built (found 2026-10-21), and holds with it (step 4) and with the encrypted format, which reads the text from i…  
`tests/test_negative.lua:829`

**T247 [char]** (I13, A21) a cleanup heal in another window does not switch the focused window or wipe what that window shows ⚑ state set by hand; an acwrite window whose current file is :bdeleted from the focused window, to reach the healing branch  
`:e a`, `:e b`, `:vsplit`, `:e x`, `:e c` → `slots = '⦉x⦊ [c] ⟦-⟧'`  
`:wincmd p` → `eq(child.win(), w1)`  
→ `shown = 'b'`  
`:bdelete c.txt` → `eq(child.win(), w1)`  
→ `shown = 'b'`  
→ `eq(child.lua('return vim.api.nvim_win_is_valid(...)', { w2 }), true)`  
→ `eq(child.lua('return vim.api.nvim_win_get_buf(...)', { w2 }), acw)`  
→ `eq(child.lua('return vim.api.nvim_buf_is_valid(...)', { acw }), true)`  
note: The split shows an oil-like buffer (acwrite) and keeps its triquetra; its current slot's file is then closed from the first window, which has the focus (A21's healing branch, DESK:2447).  
spec: (I13, A21) A cleanup heal in another window doesn't switch the focused window or wipe what that window shows: window 2 on `⦉x⦊ [c] ⟦-⟧` shows an `acwrite` buffer, and `:bdelete c.txt` from window 1 leaves window 1 focused on b and window 2 on its buffer.  
`tests/test_negative.lua:853`

**T248 [char]** (A12) with no cokeline, a cycle step raises nothing and <M-v> still ends the cycle  
→ `eq(child.lua('return (pcall(require, "cokeline.mappings"))'), false)`  
`:e a`, `:e b` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
`<M-n>` → `eq({ ok, err }, { true, nil })`  
→ `eq(child.state(), CYCLING)`  
→ `shown = 'a'`  
`<M-v>` → `eq({ ok, err }, { true, nil })`  
→ `eq(child.state(), NORMAL)`  
→ `slots = '⦉b⦊ [a] ⟦-⟧'`  
note: the step goes through cavediver's own order, onto a (T171)  
spec: (A12) With no cokeline, a cycle step raises nothing, steps through cavediver's own order (T171), and `<M-v>` still ends the cycle: navigation `normal`, history attached, and the pick lands where the step went (from `⦉a⦊ [b] ⟦-⟧`, `<M-n>` and `<M-v>` give `⦉b⦊ [a] ⟦-⟧`). **[run s2…  
`tests/test_negative.lua:882`

**T249 [char]** (A1, A11) no note names its own buffer, over random walks: one window ⚑ random walk  
note: It guards the decided check's order: after Q6's guard, never naming the current buffer.  
spec: (A1, A11) No note names its own buffer: random walks with T190's mix, in one window and across windows, check after every action that no map holds `X>X` or `X-swap>X`. The decided check drops a stale note when the note it would copy names the current buffer (A11), and runs after …  
`tests/test_negative.lua:913`

**T249 [char]** (A1, A11) no note names its own buffer, over random walks: several windows ⚑ random walk  
spec: (A1, A11) No note names its own buffer: random walks with T190's mix, in one window and across windows, check after every action that no map holds `X>X` or `X-swap>X`. The decided check drops a stale note when the note it would copy names the current buffer (A11), and runs after …  
`tests/test_negative.lua:914`

## tests/test_primary_jump.lua (10 cases: 10 char)

**T50 [char]** {c=e s=d t=b p=[x]on}, jump shows x, {c=x s=d t=e}, dtm{e-swap→b}  
`:e x`, `<M-;><M-c>`, `:e d`, `:e b`, `<M-f>`, `:e e` → `slots = '⦉b⦊ [e] ⟦d⟧'`  
→ `primary = '[x]on'`  
`<M-;><M-f>` → `shown = 'x'`  
→ `slots = '⦉e⦊ [x] ⟦d⟧'`  
→ `eq(K.note(child, 'dtm', 'e-swap'), 'b')`  
spec: `{c=e s=d t=b p=[x]on}`, jump → shows x, `{c=x s=d t=e}`, `dtm{e-swap→b}`.  
`tests/test_primary_jump.lua:30`

**T51 [char]** when the primary is the ternary, the result equals <M-S-f>'s  
`:e x`, `<M-;><M-x>`, `<M-;><M-x>`, `:e a`, `:e b`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `primary = '[b]on'`  
`<M-;><M-f> (via both)` → `eq(jump, swap)`  
→ `eq(jump[1].slots, '⦉c⦊ [b] ⟦-⟧')`  
spec: When the primary is the ternary, the result equals `<M-S-f>`'s.  
`tests/test_primary_jump.lua:40`

**T52 [char]** on the primary already: "Already in primary buffer, no displacement performed." and no change  
`:e a`, `:e b`, `<M-;><M-c>` → `eq(before[1], '⦉a⦊ [b] ⟦-⟧')`  
`<M-;><M-f>` → `eq(K.has(K.messages(child), 'Already in primary buffer, no displacement performed.'), true)`  
→ `eq({ child.slots(), child.notes(), child.shown(), child.primary() }, before)`  
spec: On the primary already: "Already in primary buffer, no displacement performed." and no change.  
`tests/test_primary_jump.lua:50`

**T53 [char]** with an empty queue it acts as <M-f>  
`<M-;><M-f> (via both)` → `eq(jump, swap)`  
→ `eq(jump[1].slots, '⦉-⦊ [c] ⟦b⟧')`  
→ `eq(jump[2].slots, '⦉-⦊ [b] ⟦c⟧')`  
→ `eq(jump[2].primary, '[]off')`  
note: Graduation, then the swap.  
spec: With an empty queue it acts as `<M-f>`.  
`tests/test_primary_jump.lua:60`

**T54 [char]** with a disabled primary it acts as <M-f>  
`:e x`, `<M-;><M-x>`, `<M-;><M-x>`, `:e a`, `:e b`, `:e c` → `primary = '[x]off'`  
`<M-;><M-f> (via both)` → `eq(jump, swap)`  
→ `eq(jump[1].slots, '⦉-⦊ [c] ⟦b⟧')`  
→ `eq(jump[2].slots, '⦉-⦊ [b] ⟦c⟧')`  
note: x is the primary, switched off, and in no slot.  
spec: With a disabled primary it acts as `<M-f>` (Q10; README:31 changes).  
`tests/test_primary_jump.lua:70`

**T55 [char]** while cycling away from the start, it returns to the start, keeps navigation cycling, and changes no slot  
`:e a`, `:e b`, `:e c`, `<M-n>` → `eq(K.nav(child), 'cycling')`  
→ `eq(slots, '⦉b⦊ [c] ⟦-⟧')`  
`<M-;><M-f>` → `shown = 'c'`  
→ `eq(K.nav(child), 'cycling')`  
→ `slots = slots`  
→ `notes = notes`  
spec: While cycling, with the window cycled away from the start, it returns to the start, keeps navigation `cycling`, and changes no slot (Q7).  
`tests/test_primary_jump.lua:81`

**T56 [char]** with a closed primary, the jump reopens it  
`:e a`, `<M-;><M-c>`, `:e b`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
`:bdelete a.txt`, `<M-;><M-f>` → `shown = 'a'`  
→ `slots = '⦉c⦊ [a] ⟦-⟧'`  
→ `primary = '[a]on'`  
→ `eq(vim.tbl_contains(vim.split(child.closed(), ','), 'a'), false)`  
note: The ternary b stays open; the closed primary stays in the queue (I4).  
spec: With a closed primary, the jump reopens it.  
`tests/test_primary_jump.lua:94`

**T57 [char]** with the primary file deleted on disk, a cleanup pass keeps it in the queue, and the jump says so  
→ `primary = '[a]on'`  
`<M-;><M-f>` → `eq({ ok, err }, { true, nil })`  
→ `eq(K.has(K.messages(child), "isn't on disk right now"), true)`  
→ `eq({ slots = child.slots(), primary = child.primary() }, { slots = '⦉c⦊ [d] ⟦-⟧', primary = '[a]on' })`  
spec: With the primary's file deleted on disk, a cleanup pass keeps it in the queue, and the jump says so: `:e a`, `<M-;><M-c>`, `:e b`, `:e c`, `:e d` give `⦉c⦊ [d] ⟦-⟧` with `p=[a]on`; after `:bdelete c.txt` and `:bdelete a.txt`, a.txt deleted and a `cleanup_system` pass leave `[a]on…  
`tests/test_primary_jump.lua:119`

**T58 [char]** with the primary file deleted on disk, it says so and keeps the pointer  
→ `eq({ ok, err }, { true, nil })`  
→ `eq(K.hook_failures(msgs), {})`  
→ `primary = '[a]on'`  
spec: With the primary's file deleted on disk, it says so and keeps the pointer.  
`tests/test_primary_jump.lua:131`

**T153 [char]** Q6 on the fallback: primary disabled, {c=A s=S t=T}, dtm[T] = S; <M-;><M-f> rewrites dtm[T] to A before the swap  
`:e x`, `<M-;><M-x>`, `<M-;><M-x>` → `primary = '[x]off'`  
`:e a`, `:e b`, `:e c`, `:e b`, `<M-f>`, `:e a`, `<M-f>` → `slots = '⦉b⦊ [c] ⟦a⟧'`  
→ `eq(K.note(child, 'dtm', 'b'), 'a')`  
`<M-;><M-f>` → `slots = '⦉b⦊ [a] ⟦c⟧'`  
→ `eq(K.note(child, 'dtm', 'b'), 'c')`  
note: x is the primary, switched off; then T150's first seven keys give {c=c s=a t=b}, dtm[b] = a.  
spec: Q6 on the fallback: with the primary disabled, `{c=A s=S t=T}` and `dtm[T] = S`, `<M-;><M-f>` acts as `<M-f>` and rewrites `dtm[T]` to A before the swap.  
`tests/test_primary_jump.lua:141`

## tests/test_primary_keys.lua (3 cases: 2 char, 1 target)

**T59 [char]** toggle_primary: empty queue gives [a]on, again [a]off, on another buffer [a]on with the queue unchanged  
`:e a` → `primary = '[]off'`  
`<M-;><M-x>` → `primary = '[a]on'`  
`<M-;><M-x>` → `primary = '[a]off'`  
`:e b`, `<M-;><M-x>` → `primary = '[a]on'`  
spec: On an empty queue `toggle_primary` gives `[a]on`; again gives `[a]off`; on another buffer it gives `[a]on` with the queue unchanged (Q8).  
`tests/test_primary_keys.lua:14`

**T60 [char]** set_primary: empty queue gives [a]on; on b [b,a]on; on b again [b,a]off; on a [a,b]on  
`:e a`, `<M-;><M-c>` → `primary = '[a]on'`  
`:e b`, `<M-;><M-c>` → `primary = '[b,a]on'`  
`<M-;><M-c>` → `primary = '[b,a]off'`  
`:e a`, `<M-;><M-c>` → `primary = '[a,b]on'`  
spec: `set_primary` on an empty queue gives `[a]on`; on b it gives `[b,a]on`; on b again it gives `[b,a]off`; on a it gives `[a,b]on`.  
`tests/test_primary_keys.lua:25`

**T156 [target]** the toggle_primary keymap description no longer reads "Toggle current buffer as primary"  
spec: The `toggle_primary` keymap's description no longer reads "Toggle current buffer as primary" (Q8).  
`tests/test_primary_keys.lua:36`

## tests/test_primary_window.lua (12 cases: 7 char, 4 target, 1 today)

**T95 [char]** with an empty queue no window opens  
`:e a`, `<M-;>F` → `eq(child.floats(), {})`  
→ `eq(child.popup(), nil)`  
→ `eq(Extra.has(child.messages(), 'No primary buffer history available.'), true)`  
spec: With an empty queue, no window opens and the message is "No primary buffer history available."  
`tests/test_primary_window.lua:35`

**T96 [char]** reordering the lines and :w reorders the queue  
→ `eq(child.popup_lines(), { 'b.txt', 'a.txt' })`  
`:write` → `primary = '[a,b]on'`  
spec: Reordering the lines and `:w` reorders the queue.  
`tests/test_primary_window.lua:44`

**T97 [char]** <CR> on line 2 makes that file the primary and closes the window  
`<CR>` → `primary = '[a,b]on'`  
→ `eq(child.popup(), nil)`  
→ `eq(child.floats(), {})`  
→ `eq(child.win(), w)`  
spec: `<CR>` on line 2 makes that file `p[1]` and closes the window.  
`tests/test_primary_window.lua:54`

**T98 [char]** a typed path to an unloaded readable file is registered, queued and pushed on the closed stack  
→ `eq(child.lua('return vim.fn.bufnr(...)', { x_path }), -1)`  
`:write` → `primary = '[b,a,x]on'`  
→ `eq(type(child.hash_of('x')), 'string')`  
→ `closed = 'x'`  
spec: A typed path to an unloaded readable file is registered, queued, and pushed on the closed stack.  
`tests/test_primary_window.lua:66`

**T99 [char]** valid lines are saved and invalid ones reported  
`:write` → `primary = '[a]on'`  
→ `eq(#errors, 1)`  
→ `eq(errors[1]:find('File does not exist: nonexistent.txt', 1, true) ~= nil, true)`  
spec: With a mix of valid and invalid lines, the valid ones are saved and the rest reported (Q11).  
`tests/test_primary_window.lua:79`

**T100 [char]** q saves, then closes the window  
`q` → `primary = '[a,b]on'`  
→ `eq(child.popup(), nil)`  
→ `eq(child.win(), w)`  
spec: `q` and `<C-c>` save, then close the window (Q12).  
`tests/test_primary_window.lua:92`

**T100 [char]** <C-c> saves, then closes the window  
`<C-c>` → `primary = '[a,b]on'`  
→ `eq(child.popup(), nil)`  
→ `eq(child.win(), w)`  
spec: `q` and `<C-c>` save, then close the window (Q12).  
`tests/test_primary_window.lua:103`

**T101 [today]** saving with the first row unchanged re-enables a disabled primary  
`<M-;><M-x>` → `primary = '[b,a]off'`  
`:write` → `primary = '[b]on'`  
spec: Saving with the first row unchanged re-enables a disabled primary. Paired with T158 (Q10).  
`tests/test_primary_window.lua:114`

**T158 [target]** a save switches the primary on only when the first row changed  
`<M-;><M-x>`, `:write` → `eq(got, { reorder_off = '[a,b]on', drop_a_off = '[b]off', drop_a_on = '[b]on' })`  
note: Each bullet starts from a fresh child.  
spec: A save switches the primary on only when the first row changed (Q10). Paired with T101.  
`tests/test_primary_window.lua:125`

**T160 [target]** with no picker, <M-e> gives a message and changes no line  
→ `eq(child.lua('return pcall(require, "telescope")'), false)`  
`<M-e>` → `eq({ ok, err }, { true, nil })`  
→ `eq(#child.messages() > 0, true)`  
→ `eq(child.popup_lines(), { 'b.txt', 'a.txt' })`  
spec: With no picker available, `<M-e>` gives a message and changes no line. `<M-e>` isn't mapped outside the primary queue window (Q11).  
`tests/test_primary_window.lua:145`

**T160 [target]** <M-e> is not mapped outside the primary queue window  
→ `eq(child.lua('return vim.fn.maparg("<M-e>", "n", false, true).buffer'), 1)`  
`q` → `eq(child.lua('return vim.fn.maparg("<M-e>", "n")'), '')`  
note: Mapped in the window... ...and nowhere else.  
spec: With no picker available, `<M-e>` gives a message and changes no line. `<M-e>` isn't mapped outside the primary queue window (Q11).  
`tests/test_primary_window.lua:156`

**T161 [target]** q and <C-c> are described as "Save and close"  
→ `eq(child.lua('return vim.fn.maparg("q", "n", false, true).desc'), 'Save and close')`  
→ `eq(child.lua('return vim.fn.maparg("<C-c>", "n", false, true).desc'), 'Save and close')`  
spec: The window's `q` and `<C-c>` mappings are described as "Save and close" (Q12).  
`tests/test_primary_window.lua:167`

## tests/test_restores.lua (10 cases: 10 char)

**T61 [char]** at b with {c=b t=d} and dtm{b→a}: restore ternary gives t=a, dtm{b→d}; again t=d, dtm{b→a}  
`:e a`, `:e b`, `:e c`, `:e d`, `:e b` → `slots = '⦉d⦊ [b] ⟦-⟧'`  
→ `eq(K.note(child, 'dtm', 'b'), 'a')`  
`<M-;><M-r>` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
→ `eq(K.note(child, 'dtm', 'b'), 'd')`  
`<M-;><M-r>` → `slots = '⦉d⦊ [b] ⟦-⟧'`  
→ `eq(K.note(child, 'dtm', 'b'), 'a')`  
spec: At b with `{c=b t=d}` and `dtm{b→a}`: restore ternary → `t=a`, `dtm{b→d}`; again → `t=d`, `dtm{b→a}`.  
`tests/test_restores.lua:15`

**T62 [char]** restoring a ternary equal to the secondary swaps the secondary and ternary contents  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e a`, `:e b` → `slots = '⦉c⦊ [b] ⟦a⟧'`  
→ `eq(K.note(child, 'dtm', 'b'), 'a')`  
`<M-;><M-r>` → `slots = '⦉a⦊ [b] ⟦c⟧'`  
note: :e b reaches the secondary by plain navigation; b's note b>a names the secondary.  
spec: Restoring a ternary equal to the secondary swaps the secondary and ternary contents.  
`tests/test_restores.lua:27`

**T63 [char]** restoring the secondary flip-flops, each press writing the replaced secondary into dsm[A]  
`:e a`, `:e b`, `:e c`, `<M-f>`, `<M-f>` → `slots = '⦉-⦊ [b] ⟦c⟧'`  
→ `eq(K.note(child, 'dsm', 'b'), 'a')`  
`<M-;><M-t>` → `slots = '⦉-⦊ [b] ⟦a⟧'`  
→ `eq(K.note(child, 'dsm', 'b'), 'c')`  
`<M-;><M-t>` → `slots = '⦉-⦊ [b] ⟦c⟧'`  
→ `eq(K.note(child, 'dsm', 'b'), 'a')`  
`<M-;><M-t>` → `slots = '⦉-⦊ [b] ⟦a⟧'`  
spec: Restoring the secondary flip-flops: a second press brings back the secondary the first one replaced, and so on (P19). Each press writes the replaced secondary into the plain note `dsm[A]`, and the first press reads `dsm[A-swap]` when it's set and isn't the secondary, otherwise `d…  
`tests/test_restores.lua:36`

**T64 [char]** with no entry, it warns "No ternary relationship found for restoration."  
`:e a`, `:e b` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
`<M-;><M-r>` → `eq(K.has(K.messages(child), 'No ternary relationship found for restoration.'), true)`  
→ `slots = '⦉a⦊ [b] ⟦-⟧'`  
spec: With no entry, it warns "No ternary relationship found for restoration."  
`tests/test_restores.lua:50`

**T65 [char]** when dtm[A-swap] is set and differs from the ternary, the restore uses it instead of dtm[A]  
`<M-;><M-r>` → `slots = '⦉f⦊ [a] ⟦-⟧'`  
spec: When `dtm[A-swap]` is set and differs from the ternary, the restore uses it instead of `dtm[A]` (Q2).  
`tests/test_restores.lua:67`

**T66 [char]** with the maps set so the remembered value equals the slot, the restore throws "Remembered ternary is the same as current ternary" ⚑ state set by hand  
`:e a`, `:e b` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
`<M-;><M-r>` → `eq(ok, false)`  
spec: With the maps set so that the remembered value equals the slot, the restore throws "This is impossible. Remembered ternary is the same as current ternary." The assertion stays (Q13).  
`tests/test_restores.lua:73`

**T67 [char]** (D9) a -swap note at a closed file deleted on disk is skipped and kept: the plain note restores and flip-flops  
`:bdelete f.txt`, `<M-;><M-r>` → `slots = '⦉b⦊ [a] ⟦-⟧'`  
`<M-;><M-r>` → `slots = '⦉d⦊ [a] ⟦-⟧'`  
`<M-;><M-r>` → `slots = '⦉b⦊ [a] ⟦-⟧'`  
→ `eq(K.note(child, 'dtm', 'a-swap'), 'f')`  
spec: (D9) A `-swap` entry pointing at a file that's closed and deleted on disk is skipped and kept: the restore uses the plain note (`a>b` gives `⦉b⦊ [a]`), flip-flops with it, and the `-swap` entry is still there afterwards.  
`tests/test_restores.lua:82`

**T173 [char]** (D9) a note at a file deleted on disk whose buffer is still open restores it and flip-flops with it  
→ `eq(child.lua([[return vim.fn.bufloaded('f.txt')]]), 1)`  
`<M-;><M-r>` → `slots = '⦉f⦊ [a] ⟦-⟧'`  
`<M-;><M-r>` → `slots = '⦉d⦊ [a] ⟦-⟧'`  
`<M-;><M-r>` → `slots = '⦉f⦊ [a] ⟦-⟧'`  
spec: (D9) A note pointing at a file deleted on disk whose buffer is still open restores it and flip-flops with it (`⦉f⦊ [a]`, then `⦉d⦊ [a]`, then `⦉f⦊ [a]`).  
`tests/test_restores.lua:96`

**T174 [char]** (D9) when both of a buffer's notes point at closed files deleted on disk, the restore says so, changes no slot, keeps both notes  
`:bdelete f.txt`, `:bdelete b.txt`, `<M-;><M-r>` → `eq({ ok, err }, { true, nil })`  
→ `slots = '⦉d⦊ [a] ⟦-⟧'`  
→ `eq(K.notes_for(child, { 'a' }), 'dtm{a-swap>f a>b} dsm{}')`  
spec: (D9) When both of a buffer's notes point at closed files deleted on disk, the restore says so, changes no slot, and keeps both notes.  
`tests/test_restores.lua:108`

**T68 [char]** an unknown hash in a map doesn't make a restore throw ⚑ state set by hand  
`:e a`, `:e b`, `<M-;><M-r>` → `eq({ ok, err }, { true, nil })`  
→ `eq(K.hook_failures(K.messages(child)), {})`  
note: A hash that no buffer or path has.  
spec: An unknown hash in a map doesn't make a restore throw.  
`tests/test_restores.lua:122`

## tests/test_s2.lua (56 cases: 48 char, 8 target)

**T292 [char]** (S2) save_session() and load_session() take no directory: the file is named after getcwd(-1, -1) and a fresh process loads it  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq(S2.save(child), { true })`  
→ `eq(S2.main_file(s.session_dir, S2.cwd(child)) ~= nil, true)`  
→ `eq(S2.load(child), { true })`  
→ `slots = '⦉c⦊ [d] ⟦b⟧'`  
spec: (S2 Contract and API; DESK:758, DESK:1074) `save_session()` and `load_session()` take no directory: with no argument the save writes a file whose name starts with `sha256(getcwd(-1, -1))`, and `load_session()` in a fresh process brings back `⦉c⦊ [d] ⟦b⟧`. A nameless save is named…  
`tests/test_s2.lua:33`

**T293 [char]** (S2) a whole-editor save is keyed by the global directory, not by a tab-local :tcd  
`:e a`, `:tabnew`, `:tcd sub` → `eq(S2.save(child, 'work'), { true })`  
→ `eq({ global = S2.main_file(dir, global, 'work') ~= nil, tab = S2.main_file(dir, tab, 'work') ~= nil },`  
note: The second tab's local directory is sub/, inside the project.  
spec: (S2 Contract and API; DESK:758, DESK:1146) A whole-editor save is keyed by the global directory, not by a tab-local `:tcd`: `save_session('work')` from a tab with `:tcd sub` writes a file named after `sha256(getcwd(-1, -1) .. "\n" .. 'work')`, and none after the tab's directory.  
`tests/test_s2.lua:49`

**T294 [char]** (S2) a tab session is keyed by its tab's directory  
`:e a`, `:tabnew`, `:tcd sub`, `:edit ../b.txt` → `eq(child.lua('return { pcall(require("cavediver").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'),`  
→ `eq(S2.main_file(session_dir(), tab, 't') ~= nil, true)`  
spec: (S2 Contract and API, Tab sessions; DESK:949, DESK:1074) A tab session is keyed by its tab's directory: `save_session('t', { tab = … })` from a tab with `:tcd sub` writes a file whose name starts with `sha256(<project>/sub .. "\n" .. 't')`. The spec makes the scope's directory th…  
`tests/test_s2.lua:64`

**T295 [char]** (S2) a load from idle goes idle -> bare -> loading  
`:e a`, `:e b` → `eq(Misc.save(child), { true })`  
→ `eq({ idle_bare = bare ~= nil, then_bare_loading = loading ~= nil }, { idle_bare = true, then_bare_loading = true })`  
spec: (S2 Loading; DESK:1284) A load from idle goes `idle → bare → loading`: after a save, `load_session` adds `idle->bare` and then `bare->loading` to the storage machine's history.  
`tests/test_s2.lua:80`

**T296 [char]** (S2) every domain tears its own state down at idle -> bare ⚑ state set by hand  
`:e a`, `:e b`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `eq(Misc.save(child), { true })`  
`:e d`, `:e x`, `:bdelete d.txt`, `<M-m>` → `eq({ closed = child.closed(), states = S2.states(child), x = S2.registered(child, 'x') },`  
`:noautocmd edit c.txt` → `eq(Misc.load(child), { true })`  
→ `eq({ slots = child.slots(), closed = child.closed(), states = S2.states(child), x = S2.registered(child, 'x') },`  
note: After the save the editor moves on: d and x visited, d closed, a cycle left open. The manager's restore puts the window back on c with no events.  
spec: (S2 Loading; DESK:1282, DESK:1284) Every domain tears its own state down at `idle → bare`: saved at `⦉b⦊ [c] ⟦-⟧`, then `:e d`, `:e x`, `:bdelete d.txt` and a cycle step left open, the window put back on c and a load give `⦉b⦊ [c] ⟦-⟧`, an empty closed stack, navigation `normal`,…  
`tests/test_s2.lua:97`

**T297 [char]** (S2) the repeat flag is re-armed by vim.schedule: a call after the batch is a full load  
`:e a`, `:e b` → `eq(Misc.save(child), { true })`  
→ `eq({ oks = oks, loads = S2.loads(child) }, { oks = { true, true, true, true }, loads = 2 })`  
note: Three calls in one batch, then a 30 ms wait (scheduled callbacks run, no timer anywhere near), then a fourth call. With T145 (three calls, one load), two loads in all tells vim.schedule apart from a timer and from no flag.  
spec: (S2 Loading; DESK:1286, DESK:1288) The repeat flag is re-armed by `vim.schedule`: three `load_session` calls in one batch, a 30 ms wait, then a fourth call give two loads, and every call returns normally. With T145, this tells `vim.schedule` apart from a timer and from no flag.  
`tests/test_s2.lua:117`

**T298 [char]** (S2) after Neovim's :restart session, cavediver loads again by itself, ignoring the repeat flag ⚑ state set by hand  
`:e a`, `:e b`, `:vsplit`, `:e c`, `:e d` → `slots = '⦉c⦊ [d] ⟦-⟧'`  
→ `eq(Misc.save(child), { true })`  
→ `eq(child.lua('return vim.v.startreason'), 'restart')`  
`:noautocmd vsplit`, `:noautocmd edit d.txt` → `eq({ loads = S2.loads(child), slots = slots },`  
note: :restart can't run inside a child. The second child is started the way :restart starts its new server (v:startreason "restart", S2.start_restarted), and Neovim's restart session is a real :mksession! file, named the way :restart names it. It's sourced in the same batch as the startup load, as in the  
spec: (S2 Loading; DESK:794) Cavediver loads again by itself after Neovim's `:restart` session, ignoring the flag: two windows saved at `⦉c⦊ [d] ⟦-⟧` and `⦉a⦊ [b] ⟦-⟧`, a startup load, and then the restart session sourced in the same batch give two loads and the saved slots. `:restart`…  
`tests/test_s2.lua:142`

**T299 [char]** (S2) one post-restore callback replaces the load's 210 ms delay ⚑ state set by hand; random walk  
`:e a`, `:e b`, `:vsplit`, `:e c` → `eq(Misc.save(child), { true })`  
`:noautocmd vsplit`, `:noautocmd edit c.txt` → `eq({ new_timers = made, last_valid_window = current, order = order },`  
note: The current window is a split on c, made with no events, so nothing has told cavediver about it before the load. Timer handles are counted: the decided load uses vim.schedule, and a fixed delay needs a timer.  
spec: (S2 Loading; DESK:1161) One post-restore callback replaces the 210 ms delay: the load makes no timer, and 30 ms after it `last_valid_window` is the current window and the bufferline order is what it still is 300 ms later. That `require` starts no probe is T254.  
`tests/test_s2.lua:176`

**T339 [char]** (S2) a reload in the same process keeps the slots of a window showing an open No Name text  
`:e a`, `:e b` → `eq(before:match('^⦉b⦊ %[NONAME_%d+%] ⟦%-⟧$') ~= nil, true)`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq({ slots = child.slots(), holding = S2.holding(child, 'shown text'), errors = Misc.errors(child) },`  
note: The window shows the No Name text when it's saved, and a load follows in the same process, as a native session's reload does: the buffer is still there.  
spec: (S2 Loading, Contents; DESK:1286, DESK:1440) A reload in the same process keeps the slots of a window showing an open No Name buffer, with no error: at `⦉b⦊ [N] ⟦-⟧` with N a No Name text shown in the window, a save and then a load in the same process give `⦉b⦊ [N] ⟦-⟧` again, wi…  
`tests/test_s2.lua:209`

**T339 [char]** (S2) a reload in the same process keeps the slots of a window that isn't focused, on an empty No Name buffer  
`:e a`, `:e b`, `:vsplit`, `:e c`, `:enew` → `eq(before:match('^⦉c⦊ %[NONAME_%d+%] ⟦%-⟧$') ~= nil, true)`  
`:wincmd p` → `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq({ split = child.slots(split), focused = child.slots(), errors = Misc.errors(child) },`  
note: The same with the No Name buffer empty, in a split that isn't focused: an empty one has no text to reopen, so the load knows it by its id alone.  
spec: (S2 Loading, Contents; DESK:1286, DESK:1440) A reload in the same process keeps the slots of a window showing an open No Name buffer, with no error: at `⦉b⦊ [N] ⟦-⟧` with N a No Name text shown in the window, a save and then a load in the same process give `⦉b⦊ [N] ⟦-⟧` again, wi…  
`tests/test_s2.lua:225`

**T300 [char]** (S2) a later reload brings no No Name text back twice  
`:e a`, `:e b` → `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq({ first = first, second = S2.holding(child, 'reload text') }, { first = 1, second = 1 })`  
note: The No Name text is open in the ternary at save, so the first load reopens it.  
spec: (S2 Loading; DESK:1286) A later reload brings no No Name text back twice: with a No Name text open in the ternary at save, a load and then a second load leave exactly one buffer holding it.  
`tests/test_s2.lua:245`

**T301 [char]** (S2) the main file starts with the clear version header CDV1  
`:e a`, `:e b` → `eq(Misc.save(child), { true })`  
→ `eq(file ~= nil, true)`  
→ `eq(S2.read(file):sub(1, 4), 'CDV1')`  
spec: (S2 The file; DESK:1554) The main file starts with the clear version header `CDV1`.  
`tests/test_s2.lua:265`

**T302 [char]** (S2) no session file is JSON or holds the directory, a file name or No Name text in clear  
`:e a`, `:e b`, `:e c`, `:bdelete b.txt`, `:e d` → `eq(Misc.save(child), { true })`  
→ `eq(#files > 0, true)`  
→ `eq(found, {})`  
note: b is closed; a No Name text is open in the ternary.  
spec: (S2 The file; DESK:1541) Nothing in the session files is in clear: with b closed and a No Name text open, no file under `session_dir` parses as JSON or holds the project's directory, a file name or the No Name text.  
`tests/test_s2.lua:275`

**T303 [char]** (S2) a save and a load run no shell command  
`:e a`, `:e b` → `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq({ save = at_save, load = child.lua('return _G.CDV_SHELL') }, { save = 0, load = 0 })`  
spec: (S2 The file; DESK:1541) The file goes through `libcrypto`, not a command: a save, and a load in a fresh process, make no `vim.fn.system`, `io.popen` or `vim.system` call. Hashing on `:e` is T222.  
`tests/test_s2.lua:310`

**T304 [char]** (S2) every write is atomic: a new file is renamed over the old one, and nothing else is left  
`:e a` → `eq(Misc.save(child), { true })`  
→ `eq(file ~= nil, true)`  
`:e b` → `eq(Misc.save(child), { true })`  
→ `eq({ regular_files = #Misc.files_in(dir), same_inode = vim.uv.fs_stat(file).ino == first },`  
spec: (S2 The file; DESK:1555) Every write is atomic: a second save puts a new file in place by renaming it over the first (the main file's inode changes), and leaves no other regular file in `session_dir`.  
`tests/test_s2.lua:326`

**T305 [char]** (S2) one scratch file per No Name text in <main>.d/, each in mode 0600  
`:e a`, `<M-.>` → `shown = 'a'`  
`:enew` → `eq(Misc.save(child), { true })`  
→ `eq(perms, { 'rw-------', 'rw-------' })`  
note: A No Name text closed with <M-.>, another open, and an empty one shown.  
spec: (S2 The file; DESK:1547, DESK:1555, DESK:1636) One file per No Name text sits in `<main>.d/`, each in mode 0600: a No Name text closed with `<M-.>`, another open, and an empty one shown give exactly two files there, `rw-------` with a umask of 022. The directory is found as the o…  
`tests/test_s2.lua:341`

**T306 [char]** (S2) scratch files are named per version, rewritten only when they change, and swept when unreferenced  
`:e a`, `:e b` → `eq(Misc.save(child), { true })`  
→ `eq(#one, 1)`  
→ `eq(Misc.save(child), { true })`  
→ `eq({ files = S2.scratch_files(dir), bytes = S2.read(d .. one[1]) }, { files = one, bytes = bytes })`  
→ `eq(Misc.save(child), { true })`  
→ `eq(#three, 1)`  
note: The No Name text is open in the ternary, the window on b.  
spec: (S2 The file; DESK:1547, DESK:1548) Scratch files are named per version, written only when they change, and swept once nothing references them: a second save with the text unchanged keeps the same file and bytes; after the text changes, the next save leaves one file under a new n…  
`tests/test_s2.lua:359`

**T307 [char]** (S2) the main file is the commit point: a crash before it lands leaves the old session whole  
→ `eq(Misc.load(child), { true })`  
→ `eq({ v1 = S2.holding(child, 'v1 text'), v2 = S2.holding(child, 'v2 text') }, { v1 = 1, v2 = 0 })`  
note: The crash: v2's scratch written, the main file not replaced yet, nothing swept. Put together from the files of the two saves.  
spec: (S2 The file; DESK:1548) The main file is the commit point, in two cases put together from the files of two saves (v1, then v2). A crash before the main file lands (the first main file, with both scratch files beside it) loads with the v1 text back and not v2; a crash after it (v…  
`tests/test_s2.lua:400`

**T307 [char]** (S2) the main file is the commit point: leftovers of a crash after it are swept by the next save  
→ `eq(S2.scratch_files(s.session_dir), both)`  
→ `eq(Misc.save(child), { true })`  
→ `eq(S2.scratch_files(s.session_dir), { v.v2 })`  
note: The crash: the main file landed, the sweep didn't run, so v1's scratch is still there.  
spec: (S2 The file; DESK:1548) The main file is the commit point, in two cases put together from the files of two saves (v1, then v2). A crash before the main file lands (the first main file, with both scratch files beside it) loads with the v1 text back and not v2; a crash after it (v…  
`tests/test_s2.lua:415`

**T308 [char]** (S2) a damaged scratch file loses one scratch, not the session  
`:e a`, `:e b`, `:vsplit`, `:close` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
→ `eq(Misc.save(child), { true })`  
→ `eq(#files, 2)`  
→ `eq(Misc.load(child), { true })`  
→ `eq({ slots = child.slots(), texts_back = S2.holding(child, 'one text') + S2.holding(child, 'two text') },`  
note: Two No Name texts made in a split, which is then closed: both stay open and hidden, and the first window keeps ⦉a⦊ [b].  
spec: (S2 The file; DESK:1548) A damaged scratch file loses one scratch, not the session: with two open No Name texts saved and one byte flipped in one scratch file, the load gives back `⦉a⦊ [b] ⟦-⟧` and exactly one of the two texts.  
`tests/test_s2.lua:428`

**T341 [char]** (S2) a closed No Name text that can't be read at a save leaves the closed stack, and the next load goes through  
`:e a`, `:e b`, `<M-.>` → `eq(child.closed():match('NONAME_') ~= nil, true)`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq(child.closed():match('NONAME_') ~= nil, true)`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq({ errors = Misc.errors(child), noname_closed = child.closed():match('NONAME_') ~= nil },`  
note: A No Name text closed with <M-.> is held unread after a load. The session's files are then removed, so the next save makes a new key and can't read the text: it's lost, and it leaves the closed stack in the file too, so the load after that doesn't stop on a closed No Name entry without its text.  
spec: (S2 The file, Checks; DESK:1548) A closed No Name text that can't be read at a save leaves the closed stack, and the next load goes through: a No Name text closed with `<M-.>` and saved, a fresh process loads it (it's held unread), the session's files are removed, and a save (a n…  
`tests/test_s2.lua:455`

**T309 [char]** (S2) no count limit: 150 closed files all come back  
`:e a` → `eq(closed(), 150)`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq(closed(), 150)`  
note: 150 more files in the project, each opened and closed. It held before the encrypted format and holds with it.  
spec: (S2 The file; DESK:1549) No count limit: 150 files closed with `:bdelete` are all on the closed stack after a save and a load in a fresh process. It held before the encrypted format and holds with it.  
`tests/test_s2.lua:486`

**T310 [char]** (S2) a file only decrypts in its own directory  
`:e a`, `:e b` → `eq(S2.save(child, 'work'), { true })`  
→ `eq(name ~= nil, true)`  
→ `eq(S2.load(child, 'work'), { true })`  
→ `eq({ told = S2.has(child.messages(), 'integrity check'), slots = child.slots(), closed = child.closed() },`  
note: The file saved as `work` in one project is copied to the name the same session takes in a second project (its sha256(directory .. "\n" .. name) prefix changed, the rest of the name kept).  
spec: (S2 Checks; DESK:1541, DESK:1683, DESK:1685) A file only decrypts in its own directory: a file saved as `work` in one project, copied to the name `work` takes in a second project (`sha256(directory .. "\n" .. 'work')` with that project's directory), gives "failed its integrity ch…  
`tests/test_s2.lua:515`

**T311 [char]** (S2) a cut-off file gives the integrity notification and a fresh start  
`:e a`, `:e b` → `eq(Misc.save(child), { true })`  
→ `eq(file ~= nil, true)`  
→ `eq(Misc.load(child), { true })`  
→ `eq({ told = S2.has(child.messages(), 'integrity check'), slots = child.slots(), closed = child.closed() },`  
spec: (S2 Checks; DESK:1683) A cut-off file, the saved file cut to half its length, gives the integrity notification and a fresh start, as T144's edited byte does.  
`tests/test_s2.lua:535`

**T312 [char]** (S2) a file with no header points to the migration script  
`:e a`, `:e b` → `eq(Misc.save(child), { true })`  
→ `eq(file ~= nil, true)`  
→ `eq(S2.has(child.messages(), 'migration script'), true)`  
note: The main file's bytes replaced by a file in the format from before encryption: plain JSON, no header.  
spec: (S2 Checks; DESK:1682) A file with no header, plain JSON in the format from before step 5 at the main file's name, gives a message naming the migration script at load. Matched on "migration script". The newer header is T245.  
`tests/test_s2.lua:556`

**T313 [char]** (S2) a reference that resolves to nothing is kept, says so when used, and works again when its file is back  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `slots = '⦉c⦊ [d] ⟦b⟧'`  
`<M-f>` → `eq({ ok = ok, err = err, told = #child.messages() > 0, slots = child.slots() },`  
`<M-f>` → `slots = '⦉c⦊ [b] ⟦d⟧'`  
note: b.txt is deleted from disk after the save and isn't brought back. after the start: a child's setup writes the project's files again  
spec: (S2 Checks; DESK:1689) A reference that resolves to nothing at load is kept, says so when it's used, and works again when its file comes back: saved at `⦉c⦊ [d] ⟦b⟧`, with b.txt deleted and not restored, the load keeps `⦉c⦊ [d] ⟦b⟧`; `<M-f>` gives a message, raises nothing and ch…  
`tests/test_s2.lua:577`

**T314 [char]** (S2) a restored buffer the file doesn't know waits for BufEnter  
`:e a`, `:e b` → `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
`:e x` → `eq({ at_load = at_load, entered = S2.registered(child, 'x') }, { at_load = false, entered = true })`  
note: x is loaded and hidden when the load runs, and the saved file never knew it.  
spec: (S2 Contents; DESK:1432, DESK:1436) A restored buffer the file doesn't know waits for `BufEnter`: x, loaded and hidden at the load but never saved, isn't registered by the load, and is once `:e x` enters it.  
`tests/test_s2.lua:603`

**T337 [char]** (S2) a reference whose buffer the manager doesn't restore is kept, and reopens when used  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq({ slots = child.slots(), b = S2.registered(child, 'b') }, { slots = '⦉c⦊ [d] ⟦b⟧', b = false })`  
`<M-f>` → `eq({ slots = child.slots(), shown = child.shown() }, { slots = '⦉c⦊ [b] ⟦d⟧', shown = 'b' })`  
note: b.txt stays on disk, but the manager doesn't bring b back. A cleanup pass after the load leaves the reference alone.  
spec: (S2 Contents; DESK:1943) A reference whose buffer the manager doesn't restore is kept, and reopens when used: saved at `⦉c⦊ [d] ⟦b⟧`, a fresh process that restores a, c and d but not b (b.txt stays on disk), loads and runs a `cleanup_system` pass has `⦉c⦊ [d] ⟦b⟧`, with b unregis…  
`tests/test_s2.lua:620`

**T315 [char]** (S2) windows on the same file keep their saved order, and a window that matches nothing starts fresh ⚑ state set by hand  
`:e a`, `:e b`, `:vsplit`, `:e c`, `:e b` → `slots = '⦉c⦊ [b] ⟦-⟧'`  
→ `eq(Misc.save(child), { true })`  
`:noautocmd vsplit`, `:noautocmd vsplit`, `:noautocmd edit e.txt` → `eq({ child.shown(wins[1]), child.shown(wins[2]), child.shown(wins[3]) }, { 'e', 'b', 'b' })`  
→ `eq(Misc.load(child), { true })`  
→ `eq({ child.slots(wins[1]), child.slots(wins[2]), child.slots(wins[3]) },`  
note: Saved: the split (listed first) ⦉c⦊ [b], the first window ⦉a⦊ [b]. The manager brings both back, behind a new first-listed window on e.  
spec: (S2 Contents; DESK:1440) Windows on the same file keep their saved order, and a window that matches nothing starts fresh: saved as `⦉c⦊ [b] ⟦-⟧` (the split, listed first) and `⦉a⦊ [b] ⟦-⟧`, and restored behind a new first-listed window on e, the windows read `⦉-⦊ [e] ⟦-⟧`, `⦉c⦊ […  
`tests/test_s2.lua:639`

**T316 [char]** (S2) a No Name buffer reopened at load gets a fresh id, and every reference to the old one is renamed ⚑ state set by hand  
`:e a`, `:e b` → `eq(type(old), 'string')`  
→ `eq(child.lua('return require("cavediver.domains.window").data.crux[vim.api.nvim_get_current_win()].ternary_slot == ...',`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq(back ~= nil, true)`  
→ `eq(got, { fresh = true, in_ternary = true, stale = {} })`  
note: The No Name text sits in the ternary at save.  
spec: (S2 Save-as-closed; DESK:1634, DESK:2299) A No Name buffer reopened at load gets a fresh id, and every reference to its old hash is renamed: a No Name text in the ternary (`:e a`, `:enew` with text, `:e b`) comes back as the ternary under a hash that differs from the saved one, a…  
`tests/test_s2.lua:663`

**T338 [char]** (S2) the migration script converts an old file found through resession's session list, and a load reads it  
→ `eq({ code = first.code, converted = first.stdout:find('converted 1 session', 1, true) ~= nil },`  
→ `eq({ old = vim.fn.filereadable(old_path), marked = vim.fn.filereadable(old_path .. '.migrated') }, { old = 0, marked = 1 })`  
→ `eq(Misc.load(child), { true })`  
→ `eq({ slots = child.slots(), closed = child.closed() }, { slots = '⦉c⦊ [d] ⟦b⟧', closed = 'b' })`  
→ `eq({ code = second.code, already = second.stdout:find('1 already converted', 1, true) ~= nil },`  
spec: (S2 The file; DESK:1543, DESK:1112-1114) The migration script converts an old file it finds through resession's session list, and a load reads it: an old file made by hand in the format from before encryption (paths XOR'd with the cwd and base64-encoded, raw hashes for open buffe…  
`tests/test_s2.lua:751`

**T342 [char]** (S2) the migration script reports a session saved fresh before it ran, and --replace converts over it  
→ `eq(Misc.load(child), { true })`  
→ `slots = '⦉-⦊ [d] ⟦-⟧'`  
→ `eq(Misc.save(child), { true })`  
→ `eq({ code = first.code, conflict = first.stdout:find('1 with a file in the new format already', 1, true) ~= nil },`  
→ `eq({ code = replaced.code, converted = replaced.stdout:find('converted 1 session', 1, true) ~= nil },`  
→ `eq(Misc.load(child), { true })`  
→ `slots = '⦉c⦊ [d] ⟦b⟧'`  
note: The new code runs a session before the script: its load starts fresh and its save writes a file in the new format. The script doesn't take that for a conversion: it reports the conflict, and --replace converts over it.  
spec: (S2 The file; DESK:1554) The migration script reports a session saved fresh before it ran, and `--replace` converts over it: T338's old file and resession session, then a process on the encrypted format loads (a fresh start, `⦉-⦊ [d] ⟦-⟧`) and saves; the script reports one sessio…  
`tests/test_s2.lua:774`

**T340 [char]** (S2) a load that finds only a file named the old way points to the migration script  
→ `eq(Misc.load(child), { true })`  
→ `eq({ told = S2.has(child.messages(), 'migration script'), slots = child.slots(), left = vim.fn.filereadable(old) },`  
note: Only a file named the old way is there: the first 32 hex characters of sha256(cwd .. "\n"), plus .json, in the format from before encryption.  
spec: (S2 Checks; DESK:1683) A load that finds only a file named the old way points to the migration script: with only `sha256(cwd .. "\n")`'s first 32 hex characters plus `.json` in `session_dir`, the load gives a message naming the migration script, starts fresh (`⦉-⦊ [a] ⟦-⟧`) and l…  
`tests/test_s2.lua:800`

**T317 [char]** (S2) with two editors on one project, the last writer wins  
`:e a`, `:e b` → `eq(Misc.save(child), { true })`  
→ `eq(Misc.save(other), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `slots = '⦉c⦊ [d] ⟦-⟧'`  
note: Two editors on one project and one session directory save in turn. It held before the encrypted format and holds with it.  
spec: (S2 Errors and drift; DESK:1070) With two editors on one project, the last writer wins: both save in turn without an error, and a fresh process loads the second one's `⦉c⦊ [d] ⟦-⟧`. It held before the encrypted format and holds with it.  
`tests/test_s2.lua:820`

**T318 [char]** (S2) a tab session's file says its scope, and its load works on the current tab only  
→ `eq({ session_tab = child.slots(w2), first_tab = child.slots(w1) },`  
spec: (S2 Tab sessions; DESK:949) A tab session's file says its scope, and its load works on the current tab only: a session saved with `{ tab = … }` from a tab at `⦉c⦊ [d] ⟦-⟧`, loaded by name alone into a second tab of a fresh process, gives that tab `⦉c⦊ [d] ⟦-⟧` and leaves the firs…  
`tests/test_s2.lua:852`

**T318 [char]** (S2) a tab session's load from idle works on the current tab only too  
→ `eq(S2.save_tab_session(child, s, 't'), { true })`  
`:e x`, `:e t` → `eq(S2.save(child), { true })`  
→ `eq(S2.load_tab_session(child, 't'), { true })`  
→ `eq({ session_tab = child.slots(w2), first_tab = child.slots(w1) },`  
note: The same, from idle: a whole-editor save in that process first.  
spec: (S2 Tab sessions; DESK:949) A tab session's file says its scope, and its load works on the current tab only: a session saved with `{ tab = … }` from a tab at `⦉c⦊ [d] ⟦-⟧`, loaded by name alone into a second tab of a fresh process, gives that tab `⦉c⦊ [d] ⟦-⟧` and leaves the firs…  
`tests/test_s2.lua:860`

**T319 [char]** (S2) closes go to the pool of the tab they happen in, and <M-S-w> reopens from the current tab's  
`:tabprevious`, `:bdelete x.txt`, `:tabnext`, `:bdelete c.txt`, `:tabprevious`, `<M-S-w>`, `:tabnext`, `<M-S-w>` → `eq({ first_tab = first_tab, session_tab = child.shown(w2) }, { first_tab = 'x', session_tab = 'c' })`  
spec: (S2 Tab sessions; DESK:952) Closes go to the pool of the tab they happen in, and `<M-S-w>` reopens from the current tab's: in T318's state, after `:bdelete x.txt` in the first tab and then `:bdelete c.txt` in the session's tab, `<M-S-w>` in the first tab reopens x and in the sess…  
`tests/test_s2.lua:873`

**T320 [char]** (S2) a tab session's tab ranks its own visits first, a buffer visited from both tabs included  
`:tabprevious`, `:e a`, `:e b`, `:tabnext`, `:e a` → `eq(first, { 'a', 'c', 'd' })`  
note: Only membership is checked: the spec doesn't fix the order inside the overlay.  
spec: (S2 Tab sessions; DESK:951, DESK:954) The session's tab ranks its own visits first, and a buffer belongs to every tab that visited it: in T318's state, `:e a`, `:e b` in the first tab and `:e a` in the session's tab leave a, c and d as the first three in the session tab's bufferl…  
`tests/test_s2.lua:891`

**T321 [char]** (S2) saves are snapshots: a whole-editor save merges the pools by close time in the file only  
`:tabprevious`, `:bdelete x.txt`, `:tabnext`, `:bdelete c.txt`, `:tabprevious`, `:e e`, `:e t`, `:bdelete e.txt` → `eq(S2.save(child), { true })`  
`<M-S-w>` → `eq(S2.load(child), { true })`  
`<M-S-w>` → `eq({ live = live, merged = merged }, { live = { 'e', 'x' }, merged = { 'e', 'c', 'x' } })`  
note: x closed in the first tab, c in the session's tab, then e in the first tab, a second apart so their close times differ whatever the clock's grain. The window goes back to t before e is closed: :bdelete of what the only window of a tab shows closes that tab.  
spec: (S2 Tab sessions; DESK:955) Saves are snapshots: in T318's state, with x closed in the first tab, c in the session's tab and e in the first tab, a second apart, a whole-editor `save_session()` leaves the pools apart in memory (`<M-S-w>` in the first tab reopens e, then x), and a …  
`tests/test_s2.lua:908`

**T322 [char]** (S2) a tab session's tab closed with no save wired gives a notice  
`:tabclose` → `eq(#S2.notices(child.messages()) > 0, true)`  
note: No TabClosedPre hook calls save_session here. The notice's wording isn't fixed, so any notification that isn't a hook failure counts.  
spec: (S2 Tab sessions; DESK:956) A tab session's tab closed with nothing wired to save it keeps its pool, with no tab, and gives a notice: in T318's state, `:tabclose` on the session's tab, with no `TabClosedPre` hook calling `save_session`, gives a notification; and with c closed in … (spec tag: [target])  
`tests/test_s2.lua:942`

**T322 [target]** (S2) a tab session's tab closed with no save wired keeps its pool, still in the picker  
`:bdelete c.txt`, `:tabclose` → `eq(S2.line_of(p.lines, 'c.txt') ~= nil, true)`  
note: c is closed in the session's tab before the tab goes; its pool is kept with no tab, so the picker still lists it.  
spec: (S2 Tab sessions; DESK:956) A tab session's tab closed with nothing wired to save it keeps its pool, with no tab, and gives a notice: in T318's state, `:tabclose` on the session's tab, with no `TabClosedPre` hook calling `save_session`, gives a notification; and with c closed in …  
`tests/test_s2.lua:953`

**T323 [char]** (S2) a tab-session save refreshes the unnamed session's records and leaves its references  
→ `eq(S2.save_tab_session(child, s, 't'), { true })`  
`:e x`, `:e t` → `slots = '⦉x⦊ [t] ⟦-⟧'`  
→ `eq(S2.save(child), { true })`  
→ `eq(S2.load_tab_session(child, 't'), { true })`  
`:tabprevious`, `:bdelete x.txt`, `:e e`, `:tabnext` → `eq(child.lua('return { pcall(require("cavediver").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'),`  
→ `eq(child.lua([[`  
→ `eq(S2.load(child), { true })`  
→ `eq({ closed = child.closed(), slots = child.slots() }, { closed = 'x', slots = '⦉x⦊ [t] ⟦-⟧' })`  
note: The whole editor is saved (the unnamed session) at ⦉x⦊ [t]; then t is loaded into a second tab, x is closed and e visited in the first tab, and t is saved. the whole editor's file, as the load reads it  
spec: (S2 Tab sessions, Errors and drift; DESK:957, DESK:1068) A tab-session save refreshes the unnamed session's records and leaves its references: with the whole editor saved by `save_session()` at `⦉x⦊ [t] ⟦-⟧`, the tab session loaded into a second tab, x closed and e visited in the…  
`tests/test_s2.lua:965`

**T332 [char]** (S2) a tab session's file holds the No Name texts its own tab owns, and not another tab's  
`:e d`, `:tabprevious`, `:e t`, `:tabnext` → `eq(child.lua('return { pcall(require("cavediver").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'),`  
`:e x` → `eq(S2.load_tab_session(child, 't'), { true })`  
→ `eq({ session_text = S2.holding(child, 'session text'), first_text = S2.holding(child, 'first text') },`  
note: In T318's state, a No Name text made in the session's tab and left there (the window goes back to d), and another made in the first tab and left there (back to t). Only the tab session is saved; a fresh process loads it into a second tab.  
spec: (S2 Tab sessions; DESK:951, DESK:954, DESK:1640) A pool holds its own No Name texts: in T318's state, a No Name text left in the session's tab's history and another left in the first tab's, a save of the tab session alone, and a load of it into a second tab of a fresh process bri…  
`tests/test_s2.lua:998`

**T349 [char]** (S2) a close goes back on the pool of every tab that visited the file  
`:e a`, `:e d`, `:tabprevious`, `:bdelete x.txt`, `:e a`, `:bdelete a.txt`, `:tabnext`, `<M-S-w>`, `<M-S-w>` → `eq({ first = first, second = child.shown(w2) }, { first = 'a', second = 'a' })`  
note: a is visited in both tabs and closed in the first; x is visited and closed in the first tab only. The answer to Q15 (2026-10-23): "Both".  
spec: (S2 Tab sessions, Q15) A close goes back on the pool of every tab that visited the file: in T318's state, `:e a` then `:e d` in the session's tab, then `:bdelete x.txt`, `:e a` and `:bdelete a.txt` in the first tab; `<M-S-w>` in the session's tab reopens a, and a second press the…  
`tests/test_s2.lua:1020`

**T350 [char]** (S2) a file reopened from one pool goes back on the pools it came out of when it is closed again  
`:vsplit`, `:e e`, `:close`, `:bdelete e.txt`, `:tabprevious`, `:bdelete x.txt`, `:e e`, `:bdelete e.txt`, `:tabnext`, `<M-S-w>`, `<M-S-w>` → `eq({ first = first, second = child.shown(w2) }, { first = 'e', second = 'e' })`  
note: e is closed into the session's pool from a split that's gone by then, so no window of the session's tab has it in its history; reopened and closed in the first tab, it goes back on the pool it came out of.  
spec: (S2 Tab sessions, Q15) A file reopened from one pool goes back on the pools it came out of when it's closed again: in T318's state, in the session's tab `:vsplit`, `:e e` there, `:close` (the split's history goes with it) and `:bdelete e.txt`, which closes e into the session's po…  
`tests/test_s2.lua:1039`

**T351 [char]** (S2) a tab session's tab closed with its save wired gives no notice ⚑ state set by hand  
`:bdelete c.txt`, `:tabclose`, `<M-S-w>` → `eq({ notices = notices, got = got, reopened = child.shown() }, { notices = {}, got = { true }, reopened = 'c' })`  
note: The contract's TabClosedPre save is wired here. The load afterwards brings d back and not c, as a manager would after c was closed.  
spec: (S2 Tab sessions; DESK:956) A tab session's tab closed with its save wired gives no notice: in T318's state, with a `TabClosedPre` autocmd that saves the tab session (`save_session('t', { tab = … })`), `:bdelete c.txt` in the session's tab, then `:tabclose`, gives no notification…  
`tests/test_s2.lua:1060`

**T352 [char]** (S2) a tab session saved from a tab with a :tcd of its own is found at load in that tab ⚑ state set by hand  
`:tabnew`, `:tcd sub`, `:e ../c.txt`, `:e ../d.txt` → `slots = '⦉c⦊ [d] ⟦-⟧'`  
→ `eq(child.lua('return { pcall(require("cavediver").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'),`  
→ `eq({ got = got, slots = child.slots() }, { got = { true }, slots = '⦉c⦊ [d] ⟦-⟧' })`  
note: The tab's own directory is sub, in the save and in the load, as the manager restores it.  
spec: (S2 Contract and API, Tab sessions; DESK:949) A tab session saved from a tab with a `:tcd` of its own is found at load in that tab: saved as `t` from a tab with `:tcd sub` at `⦉c⦊ [d] ⟦-⟧`, and loaded by name into a new tab of a fresh process whose `:tcd` is `sub` too, as the man…  
`tests/test_s2.lua:1086`

**T353 [char]** (S1) after a load from idle, closes and <M-S-w> use one closed stack  
`:e b`, `:e c` → `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
`:e a`, `:bdelete c.txt`, `<M-S-w>` → `shown = 'c'`  
note: One process: a save, then a load from idle, then a close and a reopen.  
spec: (S1, I22) After a load from idle, closes and `<M-S-w>` use one closed stack: saved at `⦉b⦊ [c] ⟦-⟧`, loaded again in the same process, then `:e a`, `:bdelete c.txt` and `<M-S-w>` reopen c.  
`tests/test_s2.lua:1112`

**T324 [char]** (S2) an oil window comes back as oil, with oil_original_buffer set from its current slot  
`:e a`, `:e b` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq({ got = got, slots = child.slots() },`  
spec: (S2 Oil; DESK:2087, DESK:2093) An oil window comes back as oil, with `vim.w.oil_original_buffer` set from its current slot: a window at `⦉a⦊ [b] ⟦-⟧` showing an oil listing at save, restored on the listing, still shows it after the load, keeps `⦉a⦊ [b] ⟦-⟧`, and has `oil_original…  
`tests/test_s2.lua:1137`

**T325 [target]** (S2) :CavediverClosed opens an editable buffer listing the closed entries, newest first, and no open buffer  
→ `eq({`  
spec: (S2 Closed-stack picker; DESK:2367, DESK:2371, DESK:2374) `:CavediverClosed` opens an editable buffer that lists the closed entries, newest first, and no open buffer: with b and then c closed, the buffer is modifiable, a line naming c.txt sits above one naming b.txt, and no line …  
`tests/test_s2.lua:1184`

**T326 [target]** (S2) a No Name entry shows its first line in quotes, its filetype and its close time  
`:e a`, `<M-.>` → `shown = 'a'`  
→ `eq({ listed = i ~= nil, quoted = line:find('"TODO: fix the', 1, true) ~= nil,`  
note: The format is given as an example (`[No Name] "TODO: fix the…"  lua`), so the pieces are matched on their own; a digit stands for the close time.  
spec: (S2 Closed-stack picker; DESK:2368) A No Name entry shows its first line in quotes, its filetype and its close time: a No Name buffer holding `TODO: fix the thing` with filetype lua, closed with `<M-.>`, is listed on a line holding `[No Name]`, `"TODO: fix the`, `lua` and a digit…  
`tests/test_s2.lua:1198`

**T327 [target]** (S2) reordering the picker's lines and :w reorders the stack  
→ `eq(c ~= nil and b ~= nil, true)`  
`<M-S-w>` → `shown = 'b'`  
spec: (S2 Closed-stack picker; DESK:2371) Reordering the picker's lines reorders the stack: with c on top of b, swapping their lines and `:w` make `<M-S-w>` in the window you came from reopen b.  
`tests/test_s2.lua:1212`

**T328 [target]** (S2) <CR> in the picker reopens the entry under the cursor in the window you came from  
→ `eq(b ~= nil, true)`  
`<CR> (via vim.keycode)` → `eq({ shown = child.shown(p.came_from), closed = child.closed() }, { shown = 'b', closed = 'c' })`  
note: <CR> is typed into the picker, since its own mapping isn't known in advance.  
spec: (S2 Closed-stack picker; DESK:2372) `<CR>` reopens the entry under the cursor in the window you came from: on b's line it puts b in that window and leaves c alone on the stack. `<CR>` is typed with `feedkeys`, since the picker's mapping isn't known in advance.  
`tests/test_s2.lua:1227`

**T329 [target]** (S2) deleting a file's line in the picker and :w discards it  
→ `eq(c ~= nil, true)`  
→ `closed = 'b'`  
spec: (S2 Closed-stack picker; DESK:2370) Deleting a file's line and `:w` discard it: with b and c closed, deleting c's line leaves b alone on the stack.  
`tests/test_s2.lua:1241`

**T330 [target]** (S2) the picker shows each pool as a header with its closed entries under it  
→ `eq(x ~= nil and c ~= nil, true)`  
→ `eq({ first_line_is_header = header(1), header_between_pools = between },`  
note: A header is a line that isn't empty and names neither entry.  
spec: (S2 Closed-stack picker, Tab sessions; DESK:2367) Each pool is a header with its closed entries under it: in T318's state, with x closed in the first tab and c in the session's tab, the picker's first line is a header, and a header sits between the lines naming x and c. A header …  
`tests/test_s2.lua:1266`

**T331 [target]** (S2) pools merge by moving a line under another pool's header  
→ `eq(c ~= nil and S2.line_of(p.lines, 'x.txt') ~= nil, true)`  
`<M-S-w>`, `:tabnext`, `<M-S-w>` → `eq({ first_tab = first_tab, session_tab = child.shown(w2) }, { first_tab = { 'x', 'c' }, session_tab = 'd' })`  
note: c's line is cut from the session's pool and pasted right under x's line.  
spec: (S2 Closed-stack picker, Tab sessions; DESK:2369) Pools merge by moving lines: in T330's state, c's line moved under x's and `:w` make `<M-S-w>` in the first tab reopen x and then c, and leave nothing for `<M-S-w>` in the session's tab.  
`tests/test_s2.lua:1285`

## tests/test_secondary_key.lua (11 cases: 11 char)

**T36 [char]** graduation: {c=c t=b}, dtm{b→a}, <M-f> gives {c=c s=b}, dsm{b→a}, same buffer, "Ternary slot graduated"  
`:e a`, `:e b`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `eq(K.note(child, 'dtm', 'b'), 'a')`  
`<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
→ `eq(K.note(child, 'dsm', 'b'), 'a')`  
→ `shown = 'c'`  
→ `eq(K.has(K.messages(child), 'Ternary slot graduated'), true)`  
spec: `{c=c t=b}`, `dtm{b→a}`, `<M-f>` → `{c=c s=b}`, `dsm{b→a}`. The buffer doesn't change, and the message is "Ternary slot graduated" (Q3).  
`tests/test_secondary_key.lua:14`

**T37 [char]** with secondary and ternary empty and two buffers in history, <M-f> fills the secondary from ordered[2] without switching  
`:e a`, `:e b`, `:vsplit` → `slots = '⦉-⦊ [b] ⟦-⟧'`  
→ `eq(second, 'a')`  
`<M-f>` → `slots = '⦉-⦊ [b] ⟦' .. second .. '⟧'`  
→ `shown = 'b'`  
→ `eq(K.has(K.messages(child), 'Secondary buffer populated from history.'), true)`  
note: A fresh split has an empty triquetra; history holds b, a.  
spec: With secondary and ternary empty and two buffers in history, `<M-f>` fills the secondary from `ordered[2]` without switching.  
`tests/test_secondary_key.lua:26`

**T38 [char]** with one buffer in history, <M-f> warns "insufficent history"  
`:e a`, `<M-f>` → `slots = '⦉-⦊ [a] ⟦-⟧'`  
→ `eq(K.has(K.messages(child), 'insufficent history'), true)`  
spec: With one buffer in history, `<M-f>` warns "insufficent history".  
`tests/test_secondary_key.lua:41`

**T39 [char]** {c=c s=b}, <M-f> shows b, {c=b s=c}, dsm{c-swap→b}  
`:e a`, `:e b`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
`<M-f>` → `shown = 'b'`  
→ `slots = '⦉-⦊ [b] ⟦c⟧'`  
→ `notes = 'dtm{b>a} dsm{b>a c-swap>b}'`  
note: c is left by a swap, so its note is a swap note (T191).  
spec: `{c=c s=b}`, `<M-f>` → shows b, `{c=b s=c}`, `dsm{c-swap→b}`: the note a swap leaves is a swap note (T191). Built in step 3.  
`tests/test_secondary_key.lua:49`

**T40 [char]** with a ternary T, <M-f> writes dtm[A-swap] = T  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
`<M-f>` → `slots = '⦉c⦊ [b] ⟦d⟧'`  
→ `eq(K.note(child, 'dtm', 'd-swap'), 'c')`  
spec: With a ternary T, `<M-f>` writes `dtm[A-swap] = T` (Q2).  
`tests/test_secondary_key.lua:59`

**T41 [char]** when the window shows a buffer other than its current slot, <M-f> switches back to it and changes no slot  
`:e a`, `:e b`, `:e c`, `<M-f>`, `<M-n>` → `eq(slots, '⦉-⦊ [c] ⟦b⟧')`  
`<M-f>` → `shown = 'c'`  
→ `slots = slots`  
→ `notes = notes`  
→ `eq(K.has(K.messages(child), 'Jumped back to windows current buffer.'), true)`  
note: <M-n> starts a cycle and moves the window off its current slot c.  
spec: When the window shows a buffer other than its current slot, `<M-f>` switches back to it and changes no slot.  
`tests/test_secondary_key.lua:67`

**T42 [char]** after :bdelete of the secondary and one more :e, the secondary keeps the closed hash, and <M-f> reopens it  
`:e a`, `:e b`, `:e c`, `<M-f>` → `slots = '⦉-⦊ [c] ⟦b⟧'`  
`:bdelete b.txt`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq(vim.tbl_contains(vim.split(child.closed(), ','), 'b'), true)`  
`<M-f>` → `shown = 'b'`  
→ `slots = '⦉c⦊ [b] ⟦d⟧'`  
→ `eq(vim.tbl_contains(vim.split(child.closed(), ','), 'b'), false)`  
spec: After `:bdelete` of the secondary's buffer and one more `:e`, the secondary still holds the closed hash, and `<M-f>` reopens it and takes it off the closed stack.  
`tests/test_secondary_key.lua:81`

**T43 [char]** after a cycle, <M-f> with secondary and ternary empty never puts the current buffer in the secondary  
`:e a`, `:e b`, `:vsplit`, `:wincmd p`, `:e c`, `<M-n>`, `:wincmd p` → `slots = '⦉-⦊ [b] ⟦-⟧'`  
`<M-f>` → `eq(K.duplicate(child), false)`  
note: The other window cycles (history frozen at c,b,a), then <C-w>p into the fresh split showing b, whose slots are empty (t/pkB_d11_dup.lua).  
spec: After a cycle, `<M-f>` with secondary and ternary empty never puts the current buffer in the secondary.  
`tests/test_secondary_key.lua:95`

**T44 [char]** with the secondary closed and its file deleted, a cleanup pass keeps the slot, and <M-f> says so  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
`:bdelete c.txt`, `:bdelete b.txt` → `eq({ slots = child.slots(), closed = child.closed() }, { slots = '⦉c⦊ [d] ⟦b⟧', closed = 'c,b' })`  
`<M-f>` → `eq({ ok, err }, { true, nil })`  
→ `eq(K.has(K.messages(child), "isn't on disk right now"), true)`  
→ `slots = '⦉c⦊ [d] ⟦b⟧'`  
note: The ternary c is closed too; a closed secondary stays in its slot either way (I4).  
spec: With the secondary closed and its file deleted, a cleanup pass keeps the slot, and `<M-f>` says so: `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` give `⦉c⦊ [d] ⟦b⟧`; after `:bdelete c.txt` and `:bdelete b.txt` (the ternary c is closed too; a closed secondary stays in its slot either wa…  
`tests/test_secondary_key.lua:111`

**T45 [char]** with the secondary file deleted on disk, the pointer is kept and <M-f> says the file is missing  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:bdelete c.txt`, `:bdelete b.txt` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq({ ok, err }, { true, nil })`  
→ `eq(K.hook_failures(msgs), {})`  
→ `slots = '⦉c⦊ [d] ⟦b⟧'`  
spec: With the secondary's file deleted on disk, the pointer is kept and `<M-f>` says the file is missing (DESK:2022).  
`tests/test_secondary_key.lua:130`

**T150 [char]** Q6's ten keys: the third <M-f> rewrites dtm[b] := c, and the restore gives {c=b s=a t=c}  
`:e a`, `:e b`, `:e c`, `:e b`, `<M-f>`, `:e a`, `<M-f>` → `slots = '⦉b⦊ [c] ⟦a⟧'`  
→ `eq(K.note(child, 'dtm', 'b'), 'a')`  
`<M-f>` → `eq(K.note(child, 'dtm', 'b'), 'c')`  
`<M-S-f>`, `<M-;><M-r>` → `eq({ ok, err }, { true, nil })`  
→ `eq(K.hook_failures(K.messages(child)), {})`  
→ `slots = '⦉c⦊ [b] ⟦a⟧'`  
spec: Q6's ten keys, as the author ran them: `:e a`, `:e b`, `:e c`, `:e b`, `<M-f>`, `:e a`, `<M-f>`, `<M-f>`, `<M-S-f>`, `<M-;><M-r>`. The third `<M-f>` rewrites the ternary's note to the buffer it leaves (`dtm[b] := c`), and the restore doesn't throw: it gives `{c=b s=a t=c}` **[sim…  
`tests/test_secondary_key.lua:146`

## tests/test_sessions.lua (16 cases: 16 char)

**T134 [char]** save_session writes paths, outsiders, buffers, windows, closed, closed_times, noname_content, missing, scope; windows[i] = [c, s, p[], t, dtm, dsm, shows, on, history]  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq(Misc.save(child), { true })`  
→ `eq(got, {`  
note: Read the way the load reads it, decrypted: the window entry's slots are hashes, and the paths behind them are in the paths table.  
spec: `save_session(cwd)` writes the keys `paths`, `outsiders`, `buffers`, `windows`, `closed`, `closed_times`, `noname_content`, `missing` and `scope`, `editor` for a whole-editor save, read as the load reads them, decrypted (`read_session`), with `windows[i] = [c, s, p[], t, dtm, dsm…  
`tests/test_sessions.lua:35`

**T135 [char]** a round trip with every slot buffer restored and loaded gives back the slots and maps  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e e` → `eq(slots, '⦉d⦊ [e] ⟦b⟧')`  
→ `eq(notes, 'dtm{b>a d>c} dsm{b>a}')`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `slots = slots`  
→ `notes = notes`  
spec: A round trip with every slot buffer restored and loaded gives back the same slots and maps.  
`tests/test_sessions.lua:73`

**T136 [char]** primary_enabled = false survives a round trip  
`:e a`, `:e b`, `<M-;><M-c>`, `<M-;><M-x>` → `primary = '[b]off'`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `primary = '[b]off'`  
spec: `primary_enabled = false` survives a round trip.  
`tests/test_sessions.lua:90`

**T137 [char]** load_session after save_session in the same process goes through and ends idle  
`:e a` → `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq(child.lua('return require("cavediver.domains.storage").sm:state()'), 'idle')`  
spec: `load_session` after a `save_session` in the same process goes through and ends `idle`.  
`tests/test_sessions.lua:104`

**T138 [char]** load_session from idle tears down and loads ⚑ state set by hand  
`:e a`, `:e b`, `:e c` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `eq(Misc.save(child), { true })`  
`:e d`, `:noautocmd edit c.txt` → `eq({ got[1], child.lua('return require("cavediver").get_storage_state()'), child.slots() },`  
note: After the save the window moves on to d; the manager's restore puts it back on c (noautocmd edit) before the load.  
spec: `load_session` from `idle` tears down and loads.  
`tests/test_sessions.lua:114`

**T139 [char]** a slot whose buffer comes back unloaded keeps its value after load  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `slots = '⦉c⦊ [d] ⟦b⟧'`  
spec: A slot whose buffer comes back unloaded (`badd`) keeps its value after load.  
`tests/test_sessions.lua:127`

**T140 [char]** a save with a No Name current slot succeeds and the load reopens it, hidden and modified  
`:e a`, `:enew` → `eq(Misc.save(child), { true })`  
→ `eq(Misc.errors(child), {})`  
→ `eq(Misc.load(child), { true })`  
→ `eq(got, { found = true, modified = true, hidden = true })`  
spec: A save with a No Name current slot succeeds and reopens the buffer at load, hidden and modified.  
`tests/test_sessions.lua:141`

**T141 [char]** a save with a :vsplit window that has no visits succeeds  
`:e a`, `:vsplit` → `eq(Misc.save(child), { true })`  
→ `eq(Misc.errors(child), {})`  
spec: A save with a `:vsplit` window that has no visits succeeds.  
`tests/test_sessions.lua:166`

**T142 [char]** two windows, one on a No Name buffer: after save and load each window gets its own entry  
`:e a`, `:e b`, `:vsplit`, `:e c`, `:enew` → `slots = '⦉c⦊ [NONAME_' .. child.lua('return vim.b.cavediver_noname') .. '] ⟦-⟧'`  
`:wincmd p` → `slots = '⦉a⦊ [b] ⟦-⟧'`  
→ `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `slots = '⦉a⦊ [b] ⟦-⟧'`  
note: The first window has ⦉a⦊ [b]; the split (listed first) visits c, then a No Name buffer. A session manager brings back only the window showing b.  
spec: Two windows, one showing a No Name buffer: after save and load each window gets its own entry.  
`tests/test_sessions.lua:176`

**T143 [char]** a save into a read-only directory throws to the caller  
`:e a` → `eq(got[1], false)`  
note: The session directory is made read-only before the child starts.  
spec: A save into a read-only directory throws to the caller.  
`tests/test_sessions.lua:194`

**T144 [char]** a file that fails the integrity check gives the notification and a fresh start  
`:e a`, `:e b` → `eq(Misc.save(child), { true })`  
→ `eq(#saved, 1)`  
→ `eq(Misc.load(child), { true })`  
→ `eq({ told, child.slots(), child.closed() }, { true, '⦉-⦊ [b] ⟦-⟧', '' })`  
note: One byte in the middle of the saved file (the one regular file in the session directory) is flipped.  
spec: A file that fails the integrity check gives the notification and a fresh start.  
`tests/test_sessions.lua:206`

**T145 [char]** three load_session calls in one batch load once  
`:e a`, `:e b` → `eq(Misc.save(child), { true })`  
→ `eq(got, { oks = { true, true, true }, loads = 1 })`  
spec: Three `load_session` calls in one batch load once.  
`tests/test_sessions.lua:234`

**T146 [char]** a save never wipes a buffer or changes what a window shows ⚑ the split visits a file first, so the save reaches the oil case  
`:e a`, `:vsplit`, `:e b` → `eq(got, { true })`  
→ `eq(snapshot(), before)`  
note: The window shows b, whose file is deleted on disk just before the save.  
spec: A save never wipes a buffer or changes what a window shows, an oil window included. It has two cases: the no-wipe one, and a save leaving an oil window on its oil buffer, built in step 4 (S1, S2 Oil).  
`tests/test_sessions.lua:271`

**T146 [char]** a save leaves an oil window on its oil buffer ⚑ state set by hand; the split visits a file first, so the save reaches the oil case  
`:e a`, `:e b`, `:vsplit`, `:e c` → `eq(child.lua('return require("cavediver.domains.window").data.crux[vim.api.nvim_get_current_win()] ~= nil'), true)`  
→ `eq(Misc.save(child), { true })`  
→ `eq(snapshot(), before)`  
note: The split visits c, then shows an oil-like buffer (acwrite, oil://) and keeps its triquetra.  
spec: A save never wipes a buffer or changes what a window shows, an oil window included. It has two cases: the no-wipe one, and a save leaving an oil window on its oil buffer, built in step 4 (S1, S2 Oil).  
`tests/test_sessions.lua:286`

**T147 [char]** with no file, a load gives every window {c=<shown>} and an empty closed stack ⚑ state set by hand  
`:noautocmd edit a.txt`, `:noautocmd vsplit`, `:noautocmd edit b.txt` → `eq(Misc.session_files(child), {})`  
→ `eq(Misc.load(child), { true })`  
→ `eq(got, { '⦉-⦊ [a] ⟦-⟧', '⦉-⦊ [b] ⟦-⟧' })`  
→ `closed = ''`  
spec: With no file, a load gives every window `{c=<shown>}` and an empty closed stack.  
`tests/test_sessions.lua:304`

**T148 [char]** after switching sessions, the outgoing No Name text is not in the incoming file ⚑ state set by hand  
`:e a`, `:enew`, `<M-.>` → `shown = 'a'`  
→ `eq(Misc.save(child), { true })`  
`:noautocmd edit ' .. vim.fn.fnameescape(two .. '/a.txt` → `eq(Misc.save(child), { true })`  
→ `eq(Misc.load(child), { true })`  
→ `eq(found, false)`  
note: Project one has a No Name buffer with text, closed with <M-.> (its text is kept for reopening). Then the editor switches to project two: save, cd, the manager's restore, load, and later a save there. Both share one session directory. A fresh child loads project two's file and looks for the text.  
spec: After switching sessions, the outgoing No Name text isn't in the incoming file.  
`tests/test_sessions.lua:325`

## tests/test_setup.lua (3 cases: 3 char)

**T125 [char]** setup() with no argument works and uses the defaults  
→ `eq(got, { ok = true, key = true, history_view = 'global', cleanup_interval = 4000, session_dir = true })`  
spec: `setup()` with no argument works and uses the defaults.  
`tests/test_setup.lua:41`

**T126 [char]** require("cavediver") without setup() creates no autocmds  
→ `eq(got, 0)`  
spec: `require('cavediver')` without `setup()` creates no autocmds.  
`tests/test_setup.lua:57`

**T127 [char]** calling setup() twice leaves one set of autocmds and timers  
→ `eq(counts(), once)`  
spec: Calling `setup()` twice leaves one set of autocmds and timers.  
`tests/test_setup.lua:66`

## tests/test_ternary_key.lua (4 cases: 4 char)

**T46 [char]** {c=d s=b t=c}, <M-S-f> shows c, {c=c s=b t=d}, dtm{d-swap→c}  
`:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` → `slots = '⦉c⦊ [d] ⟦b⟧'`  
`<M-S-f>` → `shown = 'c'`  
→ `slots = '⦉d⦊ [c] ⟦b⟧'`  
→ `eq(K.note(child, 'dtm', 'd-swap'), 'c')`  
spec: `{c=d s=b t=c}`, `<M-S-f>` → shows c, `{c=c s=b t=d}`, `dtm{d-swap→c}`.  
`tests/test_ternary_key.lua:14`

**T47 [char]** with no ternary, it warns "No ternary buffer to swap with." and nothing changes  
`:e a`, `:e b`, `<M-f>` → `eq(before[1], '⦉-⦊ [b] ⟦a⟧')`  
`<M-S-f>` → `eq(K.has(K.messages(child), 'No ternary buffer to swap with.'), true)`  
→ `eq({ child.slots(), child.notes(), child.shown() }, before)`  
spec: With no ternary, it warns "No ternary buffer to swap with." and nothing changes.  
`tests/test_ternary_key.lua:23`

**T48 [char]** a ternary closed with <M-.> is reopened by <M-S-f> and taken off the closed stack  
`:e a`, `:e b`, `:e c`, `<M-.>` → `slots = '⦉c⦊ [b] ⟦-⟧'`  
→ `closed = 'c'`  
`<M-S-f>` → `shown = 'c'`  
→ `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `closed = ''`  
note: <M-.> on c lands on b (ordered[2]); c stays in the ternary, closed.  
spec: A ternary closed with `<M-.>` is reopened by `<M-S-f>` and taken off the closed stack.  
`tests/test_ternary_key.lua:33`

**T49 [char]** the desk's sequence (:e, :e, <M-n>, :bdelete, <M-S-f>, <M-S-f>) throws nothing and leaves no duplicate slot  
`:e a`, `:e b`, `<M-n>`, `:bdelete`, `<M-S-f>` → `eq({ ok, err }, { true, nil })`  
→ `eq(K.hook_failures(K.messages(child)), {})`  
→ `eq(K.duplicate(child), false)`  
note: The desk's 1.txt and 2.txt are a and b here.  
spec: The desk's sequence (`:e 1.txt`, `:e 2.txt`, `<M-n>`, `:bdelete`, `<M-S-f>`, `<M-S-f>`) throws nothing and leaves no duplicate slot. The reopen's `BufEnter` is slotted once the editor settles, so cleanup doesn't clear the ternary before the rename; the rename's missing guard for …  
`tests/test_ternary_key.lua:44`

## tests/test_ui.lua (13 cases: 7 char, 6 target)

**T115 [char]** the winbar holds the slots in order, with their highlights  
`:e c`, `:e d`, `<M-f>`, `:e e` → `slots = '⦉d⦊ [e] ⟦c⟧'`  
→ `eq({ in_order(winbar(), {`  
spec: For `{c=e s=c t=d}`, the winbar holds these pieces in order (seen in run s14): `%#WinbarBufnrTernary#⦉<d>⦊ `, then `%#WinbarBufnrCurrent#[<e>] `, then `%#WinbarFilenameCurrent#e.txt`, then `%#WinbarBufnrSecondary#⟦<c>⟧ `, then `%#WinbarFilenameSecondary#c.txt`. `<x>` stands for t…  
`tests/test_ui.lua:38`

**T116 [char]** a closed ternary shows as ⦉ … name ⦊ with no buffer number  
`:e a`, `:e b`, `:e c`, `<M-.>` → `slots = '⦉c⦊ [b] ⟦-⟧'`  
→ `closed = 'c'`  
→ `eq(inner ~= nil, true)`  
→ `eq(inner:find('c.txt', 1, true) ~= nil, true)`  
→ `eq(inner:find('%d'), nil)`  
note: <M-.> on c lands on b and leaves c in the ternary as a closed hash (T80).  
spec: A closed ternary is shown as `⦉ … name ⦊` with no buffer number.  
`tests/test_ui.lua:52`

**T117 [char]** the current buffer as the primary shows as ⦉N⦊ in WinbarBufnrPrimary  
`:e a`, `<M-;><M-c>` → `primary = '[a]on'`  
→ `eq(in_order(winbar(), { '%#WinbarBufnrPrimary#⦉' .. bufnr('a.txt') .. '⦊ ' }), true)`  
spec: When the current buffer is the primary, it's shown as `⦉N⦊` in `WinbarBufnrPrimary`.  
`tests/test_ui.lua:63`

**T118 [char]** a slot closed with :bdelete shows its basename, not its full path  
`:e a`, `:e b`, `:e c`, `:bdelete b.txt` → `slots = '⦉b⦊ [c] ⟦-⟧'`  
→ `eq(part:find('# b.txt ⦊', 1, true) ~= nil, true)`  
spec: A slot closed with `:bdelete` shows its basename, not its full path.  
`tests/test_ui.lua:69`

**T119 [target]** get_buffer_relationships does not throw when current = primary, or it is gone (Q16)  
`:e a`, `<M-;><M-c>` → `eq(got, { true })`  
spec: `get_buffer_relationships` doesn't throw when current = primary, or it's gone (Q16).  
`tests/test_ui.lua:78`

**T120 [target]** get_smart_basename is a function  
→ `eq(child.lua('return type(require("cavediver").get_smart_basename)'), 'function')`  
spec: `require('cavediver').get_smart_basename` is a function.  
`tests/test_ui.lua:90`

**T121 [char]** compare_buffers ranks by recency; bufnr_is_displayed is true for tracked, false for help  
`:e a`, `:e b` → `eq(got, { true, false })`  
`:help` → `eq(got, { true, false })`  
spec: `compare_buffers(a, b)` is true when a was visited more recently than b; `bufnr_is_displayed` is true for tracked buffers and false for help.  
`tests/test_ui.lua:94`

**T122 [char]** with 40 tracked buffers, bufnr_is_displayed is true for all 40 (Q5)  
→ `eq(got, { 40, 40 })`  
spec: With 40 tracked buffers, `bufnr_is_displayed` is true for all 40 (Q5).  
`tests/test_ui.lua:114`

**T123 [target]** hide_bufferline() and show_bufferline() do not throw  
→ `eq(got, { true, true })`  
spec: `hide_bufferline()` and `show_bufferline()` don't throw.  
`tests/test_ui.lua:134`

**T124 [char]** while cycling, get_theme_bg_color(true) is the detached focused colour  
`:e a`, `:e b`, `<M-m>` → `eq(got, { 'cycling', true })`  
spec: While cycling, `get_theme_bg_color(true)` returns `colors.cokeline.bg.detached.focused`.  
`tests/test_ui.lua:144`

**T170 [target]** the engine has no machine named window (D25)  
→ `eq(got, { 'history', 'navigation', 'storage', 'ui_bufferline', 'ui_indicators', 'ui_loop' })`  
spec: (D25) The engine has no machine named `window`; `require('cavediver.engine'):list()` gives the other six.  
`tests/test_ui.lua:157`

**T169 [target]** the mapped keys have their own descriptions (D3)  
→ `eq(got, {`  
spec: (D3) The `desc` of the mapped keys: `toggle_primary` "Switch the primary on or off", `close_buffer` "Close the current buffer", `open_primary_buffer_history` "Open the primary queue"; no two keys share a description.  
`tests/test_ui.lua:162`

**T168 [target]** the pick letter takes its colour from the config (D2)  
`:e a`, `:e b` → `eq(pick_colours('#111111', '#222222'), { close = '#111111', focus = '#222222' })`  
→ `eq(pick_colours('#333333', '#444444'), { close = '#333333', focus = '#444444' })`  
note: cokeline is stubbed: the picking state comes from _G.CDV_PICK, and the pick letter's component is the one whose text is the letter while picking.  
spec: (D2) While cokeline is picking, the pick letter's colour is `colors.cokeline.is_picking_close` (closing) or `colors.cokeline.is_picking_focus` (focusing) from the config; setting either changes the letter's colour.  
`tests/test_ui.lua:191`

## tests/test_windows.lua (4 cases: 4 char)

**T92 [char]** <M-,> toggles between the last two windows  
`:e a`, `:vsplit`, `:e b` → `eq(w1 ~= w2, true)`  
`<M-,>` → `eq(child.win(), w1)`  
`<M-,>` → `eq(child.win(), w2)`  
`<M-,>` → `eq(child.win(), w1)`  
spec: `<M-,>` toggles between the last two windows.  
`tests/test_windows.lua:16`

**T93 [char]** with no previous window <M-,> warns  
`:e a`, `<M-,>` → `eq(child.win(), w)`  
→ `eq(Extra.has(msgs, 'No valid previous window to toggle to.'), true)`  
spec: With no previous window it warns "No valid previous window to toggle to."  
`tests/test_windows.lua:32`

**T94 [char]** <M-,> skips a previous window whose filetype is minimap  
`:e a`, `:vsplit`, `:e b`, `<M-,>` → `eq(child.win(), w2)`  
→ `eq(Extra.has(child.messages(), 'No valid previous window to toggle to.'), true)`  
note: The window <M-,> would go back to now shows a minimap.  
spec: `<M-,>` skips a previous window whose filetype is `minimap`.  
`tests/test_windows.lua:42`

**T194 [char]** one jump table serves every tab  
`:e a`, `:vsplit`, `:e b`, `:tabnew`, `:e c`, `:vsplit`, `:e d` → `shown = 'd'`  
`:tabnext 1` → `eq(child.win(), tab1_win)`  
`<M-,>` → `eq(child.win(), d_win)`  
→ `eq(child.lua('return vim.fn.tabpagenr()'), 2)`  
`<M-,>` → `eq(child.win(), tab1_win)`  
→ `eq(child.lua('return vim.fn.tabpagenr()'), 1)`  
note: Tab 1: a | b. Tab 2: c | d. <M-,> goes to the window just left, d's window in tab 2. And <M-,> there comes back.  
spec: (D17) One jump table serves every tab: tab 1 with two windows (`:e a`, `:vsplit`, `:e b`), then `:tabnew`, `:e c`, `:vsplit`, `:e d`. Back in tab 1 (`:tabnext 1`), `<M-,>` goes to d's window in tab 2, the window just left, and `<M-,>` there comes back **[run `t/pkA_d17.lua`]**.  
`tests/test_windows.lua:56`

