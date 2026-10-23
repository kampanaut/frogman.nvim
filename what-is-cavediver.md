# What is cavediver

First draft, 2026-10-20. A behavioural specification of cavediver, written so that an automated test suite can be built from it. Corrections go section by section.

## 0. How to read this

**The answers of 2026-10-20 are folded in.** The author answered all 21 questions in section 8 and confirmed principles P13–P21. Each question is closed in section 8, and the actions, invariants, disagreements and tests it touched are relabelled. What they settled beyond the questions is summarised at the very end, after the appendix, together with the few items that still need the author.

**Today and Decided.** "Today" is what the code in `lua/cavediver/` does now; `domains/prediction/` is left out. "Decided" is a design decision on the desk (`DESK.md`) that isn't implemented yet. "Decided (2026-10-20)" and "Decided (2026-10-20 evening)" are decisions from the author's answers that aren't implemented yet. When today and a decision differ for one action, they sit side by side under that action. A decision followed by "Built in step N." is in the code today, built by that build step; when only part of it is built, the line names the part.

**Sources and how they're cited.**
- Code paths are relative to `lua/cavediver/`. `domains/` is dropped, so `window/routines.lua:462` means `lua/cavediver/domains/window/routines.lua:462`. `init.lua`, `configs.lua` and `engine/…` are at the top of `lua/cavediver/`.
- `README:n` is `README.md`.
- `SPEC:n` is `WINDOW_BUFFER_RELATIONSHIP_SPECIFICATION.md`.
- `STATUS:n` is `archive/CURRENT_IMPLEMENTATION_STATUS.md`. It was archived on 2026-10-20 (the author: "archive it bro."), moved unchanged out of the repo root and still outside git. It's no longer a source of intent; STATUS citations below describe that archived file.
- `DESK:n` is `DESK.md`.

**Where the runs live.** The scenarios cited as `[run t/…]`, the variants cited as `[sim …]` and the random-walk scripts are in `spec-runs/` at the repo root, untracked, with a README. `spec-runs/setup.sh <dir>` builds a working sandbox outside the repo and rebuilds every variant from its patch; `variants/all_fixed.patch` has every fix decided on 2026-10-20 and 2026-10-21.

**How each claim is known.**
- **[run]**: confirmed in headless nvim. The scenario is named in the appendix.
- **[code]**: read from the code and not run.
- **[inferred]**: a conclusion drawn from the code that wasn't checked directly.
- **[desk]**: taken from the desk, including its own reproductions.
- **[sim]**: a headless run of a variant, a copy of the plugin with an unbuilt change in it, standing in for a decided change or an option. The variant is named, and so is the run when it has a scenario of its own; otherwise the key sequence given next to the claim is the record.

**What each behaviour is labelled.**
- **intended**: the code agrees with the author's answers, the README or the desk, or, where all are silent, with the old spec (SPEC). An answer that confirms it is cited as (Qn).
- **decided (2026-10-20)**: the author settled the behaviour in the answers of 2026-10-20, and the code has to change to match. A **Decided (2026-10-20):** line under the action says how.
- **bug (desk)**: the desk already lists it under "Bugs found along the way" (DESK:2428).
- **bug (new)**: a defect the desk doesn't list.
- **unclear → Qn**: the intent can't be told from the sources. It becomes question Qn in section 8. After 2026-10-20 none are left.

**IDs.** These IDs stay stable while the draft is corrected:
- P: principles
- M: model
- A: actions and events
- I: invariants
- S: sessions
- D: disagreements
- T: tests
- Q: questions

**Notation for a triquetra.** Files stand in for their hashes.
- `{c=A s=B t=C p=[P,Q]on}` means current A, secondary B, ternary C, primary queue P then Q, and `primary_enabled` true. A `-` means the slot is empty.
- `dtm{A→C, A-swap→C}` is the ternary displacement map.
- `dsm{A→B}` is the secondary displacement map. Under "Keep the older one" it has `-swap` keys too: `dsm{A→B, A-swap→B}` (M7).
- Example: `{c=a}` then `:e b` gives `{c=b t=a}`.
- The same triquetra can be written the way the winbar shows it: `⦉t⦊ [c] ⟦s⟧`, ternary, current, secondary, with `-` for an empty slot. In that form `x>y` is x's plain note and `x-swap>y` its swap note. Example: `⦉a⦊ [b] ⟦-⟧` is `{c=b t=a}`.

## 1. Philosophy and principles

One line each, with its source and how today's code stands against it. P13–P21 are confirmed by the author (2026-10-20); the others came from the desk and stand as they were.

| ID | Principle | Source | Today |
|---|---|---|---|
| P1 | What's shown on the screen is what cavediver knows, always. | DESK:19, DESK:1781 | Partly. Slots, the registry and the caches are copies, brought up to date once the editor settles after an arrival, a window entry, a rename or a write (P2). Cleanup fits the model to the screen and never changes the screen (A21). A delete's own bookkeeping still updates the copies inside the event (P2). |
| P2 | The settle rule: act after the editor settles, never inside the event, and look at what's on screen then. | DESK:14, DESK:82, DESK:1783 | Partly. An arrival (`BufEnter`) and a window entry (`WinEnter`) wait for `vim.schedule` and look at the screen then. The arrival is slotted inside its own window, and only while that window still shows the buffer and no session has loaded since (`history/hooks.lua:173-194`). The entry is taken in only while the focus is still there, with the window it came from read at the event (`navigation/hooks.lua:102-115`). The landing after a delete, the cancel of a cycle on a window jump, the undo on `OptionSet` and the close key's delete wait too (`window/routines.lua:344-419`, `navigation/hooks.lua:50-75`, `window/hooks.lua:175-192`, `history/routines.lua:798-811`). Renames and writes wait too: `BufFilePre` only records the old hash, the rename is decided once the editor settles, and so is `BufWritePost`'s update (`history/hooks.lua:140-160`, `:199-231`; A20, T107, T238). `BufDelete`'s own bookkeeping still acts inside the event, since the buffer is gone afterwards (A19). With typeahead (a macro, a mapping that switches buffers several times, `:bufdo`), only what each window shows once the editor settles is slotted and recorded (A1). |
| P3 | Session-manager agnostic, no adapters. Two exports: the manager restores buffers and layout, then cavediver lays its triquetras over what came back. | DESK:13, DESK:751 | Partly. The two exports exist (`init.lua:391-392`) and take the session's name, not a directory: cavediver reads the directory itself (S1). A load works after a save or a load in the same process, a native restore's repeated calls load once, and Neovim's `:restart` session is followed by a load of cavediver's own (S1). The load lays the triquetras over what came back: it matches windows by what they show, and a restored buffer the file doesn't know waits for its `BufEnter` (`storage/routines.lua:194-219`, `:246-341`; S1). But the README makes resession a requirement (README:44). |
| P4 | Cooperate rather than force: wherever cavediver bends the editor or other plugins to its model, that gets fixed. | DESK:21, DESK:2083 | Not held. The save switches oil windows (`storage/routines.lua:488-498`), cavediver owns the winbar, and plugins are special-cased by name. Cleanup switches no window (A21). |
| P5 | Regular files only. Cavediver tracks regular file buffers and No Name buffers, nothing else. | README:366, DESK:37, DESK:2162, `history/routines.lua:80` | Partly. Today's rule is a listed buffer with no `://` in its name, and `buftype ""` or `nowrite` on an existing regular file (`history/routines.lua:356`, M3). A registered buffer whose `buftype` changes so that it's no longer trackable has its arrival undone and is unregistered once the editor settles (I10). |
| P6 | The registry is the authority: hash → buffer and hash → path decide what a hash means. | DESK:1364, `window/hooks.lua:41` | Held as a design. Its gaps are listed under I2. |
| P7 | The user never registers a buffer by hand; registration is automatic. | `window/routines.lua:199` | Held. |
| P8 | Cleanup repairs only cavediver's own data and never touches a buffer or a window. | DESK:19, DESK:1859 | Held. Cleanup wipes no buffer and switches no window: its healing changes only the slots, and a window it can't heal loses its triquetra rather than being given a buffer (A21). |
| P9 | Missing files aren't forgotten. A pointer to a file gone from disk is kept, and says so when it's used. | DESK:20, DESK:2022 | Partly. A buffer whose file is missing stays tracked, and a slot pointing at an open buffer is kept whatever the disk says (M3, A21). A restore keeps a note whose closed file is gone from disk, and says so (A11). A closed slot or closed entry whose file is gone from disk is dropped (A21, A22). |
| P10 | Follow along: displacement maps and history never keep anything alive. Their entries go once what they point at is no longer known. | DESK:83, DESK:2029 | Not held. The maps are never pruned, apart from a restore clearing a note at a hash with no path when it uses it (M7), and history entries go as soon as the buffer is unregistered. |
| P11 | Errors in the state machine shouldn't happen. An error from `to()` is a loud bug, a bug inside a hook is caught with a stack trace, and the save hook is critical. | DESK:1154-1157 | Held. Hook errors are caught with a stack trace (`engine/helpers.lua:36-45`), and the save hook is critical (`storage/hooks.lua:17`, I21). |
| P12 | Nothing runs at `require`. `setup()` creates the autocmds (in one augroup), the commands and the timers, and can be re-run. | DESK:2177 | Held. `require` creates no autocmd, command or timer. `setup()` creates the autocmds in the `cavediver` augroup, the commands and the timers, and running it again replaces the autocmds, commands and timers (`init.lua:127-163`, A25). |
| P13 | You can always get back to what once was: the secondary and the ternary can always be restored. | README:7; confirmed by the author (2026-10-20) | Partly. The restores work (A11), and "Keep the older one" keeps every note a restore reads from naming the slot's own occupant, so no route found makes a restore throw (M7, I23, T154). A closed slot whose file is gone from disk still gets pruned (A21). |
| P14 | The secondary is yours: it changes only when you act. | README:353, SPEC:41, SPEC:299; confirmed by the author (2026-10-20) | Held. Going to the secondary by plain navigation counts as acting, and swaps it (A1). The author's check: `:e b`, `:e c`, `<M-f>` (graduation), `:e d`, then `:e b` gives `{c=b s=d t=c}`. |
| P15 | The ternary is your previous buffer, filled in on every jump that isn't to the secondary, and not on a cycling pick. | README:347; confirmed by the author (2026-10-20) | Held (A1, A13). A pick of an outside buffer leaves the ternary alone and notes the start on the picked buffer instead (Q9). |
| P16 | A buffer is never in more than one of a triquetra's current, secondary and ternary slots. | README:368, SPEC:343; confirmed by the author (2026-10-20) | Asserted, not maintained (I1). The primary isn't one of the three: it may share a slot's buffer (Q16). |
| P17 | Every window is independent: its own triquetra and, optionally, its own visit history. | README:17, README:374; confirmed by the author (2026-10-20) | Held. |
| P18 | Cycling is exploration: stepping with `<M-n>`/`<M-m>` records no visits and writes no displacement entries; `<M-v>` picks. `<M-f>`, `<M-S-f>` and the restores, pressed while the window shows its current slot, do their normal job, notes included, cycling or not. | README:384, SPEC:30-37, SPEC:546; confirmed by the author (2026-10-20); narrowed to the steps by the author (2026-10-20 evening, "Yes, as today") | Held. The current slot stays frozen while cycling (A12, Q1). The pick's own writes (Q6's guard, Q9's note, the stale-note check of "Keep the older one") stay, since `<M-v>` ends the cycle **[run `t/pkB_cycle_keys.lua`]**. |
| P19 | A restore flip-flops instead of being used up, with one remembered entry per buffer for each kind of note, overwritten by the next displacement. | SPEC:523-544, README:349; confirmed by the author (2026-10-20); the "for each kind of note" rewording confirmed by the author (2026-10-21) | Held (A11). Both maps keep a plain note and a swap note per buffer, and a restore uses one of them (Q2, M7). A note that has gone stale is rewritten to the older one ("Keep the older one", decided 2026-10-20 evening, built in step 3; M7). |
| P20 | Keys are predictable: `<M-S-f>` always does the same swap, and restoring is only ever explicit. | SPEC:512-521; confirmed by the author (2026-10-20) | Held. The swap also writes a `-swap` note, which SPEC:240 rules out; Q2 keeps the note (D7). |
| P21 | Identity comes from the file name: a hash of the name, so relationships survive restarts. | README:12, STATUS:34-40; confirmed by the author (2026-10-20) | Held. Hashing is `vim.fn.sha256`, with no shell (M1). |
| P22 | Privacy: the session file is usage data and stays protected. | DESK:1541, `init.lua:4` | Weak. It's XOR with the session's directory as the key (S1), which DESK:1561 shows leaks the key. |
| P23 | Drift between cavediver's file and the manager's is designed out, not detected. | DESK:1056 | Not held (S1). |
| P24 | A save is a snapshot and never changes the running state. | DESK:955, DESK:1152 | Not held. A save runs `cleanup_system`, which wipes nothing but can prune the closed stack (A22), and switches oil windows (`storage/routines.lua:741`, `:488`). |
| P25 | Two invariants: a path is never forgotten while anything references its hash, and every triquetra comes with its window's history entry. | DESK:84, DESK:1058-1064, DESK:1126 | Held. A path is kept while anything references its hash (I2), and every triquetra comes with its window's history entry, wherever it's made (I3). |
| P26 | Cokeline is required, as part of the UI. Harpoon is optional, through a provider. | DESK:2126, DESK:2144, README:42-47 | Harpoon is required and loaded without a guard (`history/routines.lua:416`, `ui/routines.lua:370`). |
| P27 | Cavediver reconciles any conflict between its model and the editor, "smartly". The four kinds of conflict decide who wins. | DESK:1781, DESK:1918 | Today that's healing inside cleanup (A21), the landing after a delete (A19), the visiting rule (A2), and undoing an arrival whose buffer turns untracked (I10). |

## 2. The model

### M1. Identity and hashing

- A buffer's **name** is `nvim_buf_get_name(buf)`. A buffer with an empty name is called `NONAME_<id>` instead (`noname_name`, `history/routines.lua:20-25`). The id is `os.time()` followed by `vim.uv.hrtime()`, digits only. It's made the first time the buffer is named and kept on the buffer, in `vim.b[buf].cavediver_noname`, so the buffer keeps its name and a later session's buffer with the same number gets another (I16, T11, T216). It's used at registration, on every update and in cleanup's heal (`:82-84`, `:363`, `window/routines.lua:486-488`). A session file from before the `paths` table, the kind that holds `NONAME_<bufnr>` names, isn't read: its load is a fresh start (S1) **[code]**.
- Its **hash** is `string.sub(vim.fn.sha256(name .. "\n"), 1, 16)` (`history/routines.lua:34-42`): the first 16 hex characters of sha256(name .. "\n"), which is what `echo "<name>" | sha256sum` gives for an ordinary name, so saved hashes still match. No shell runs (T222). It's called for every `BufEnter` of a registered buffer, once it settles (`:363`, `:372`). A name containing `"`, `$` or a backslash hashes like any other (T9): the collisions reproduced at DESK:2131-2140 and DESK:2441 are the shell's.
- The **session file** is named `vim.fn.sha256(directory .. "\n" .. name)`, all 64 hex characters, plus `.json`, inside `session_dir` (`storage/routines.lua:640-655`; T255). `directory` is the session's directory, which cavediver reads itself, and `name` is the name given to `save_session` or `load_session` (S1). A nameless save is named `vim.fn.sha256(directory)` alone, with no separator (T292). A file named after the first 32 hex characters of `sha256(cwd .. "\n")` isn't read: its load is a fresh start, and the save writes a new file beside it **[code]**. The migration script that renames such files isn't built (S2 The file).
- **Decided:** hash with `vim.fn.sha256(name .. "\n")` (DESK:1456, DESK:2131). A No Name id is unique across sessions, built from `os.time()` and `vim.uv.hrtime()` and kept in a buffer variable (DESK:2289-2297). The file is named `sha256(directory .. "\n" .. name)`, or `sha256(directory)` for a nameless save (DESK:1074). Built in step 2: the hashing, which the session file's name uses too. Built in step 4: the No Name id (T11, T216), and the file's name, `sha256(directory .. "\n" .. name)`, or `sha256(directory)` for a nameless save, with the directory read by cavediver (T255, T292–T294).

### M2. The registry

Defined at `history/data.lua:71-78`:

| Table | Maps | Meaning |
|---|---|---|
| `hash_buffer_registry.buffers` | hash → bufnr | what's open now |
| `hash_buffer_registry.hashes` | bufnr → hash | reverse |
| `hash_filepath_registry.filepaths` | hash → path | everything cavediver knows, closed buffers included |
| `hash_filepath_registry.hashes` | path → hash | reverse |

Writers:
- `register_buffer(buf)` (`history/routines.lua:77-108`) writes all four. If the hash is already bound to another buffer, that buffer's reverse entry is dropped, so the newer buffer takes the hash. It throws for `buftype ~= ""` unless the buffer is `nowrite` on an existing regular file (`is_nowrite_file`, `:79-81`).
- `register_filepath(path)` (`:114-125`) writes only the path pair.
- `unregister_buffer` (`:131-139`) drops the buffer pair and keeps the path.
- `unregister_filepath` (`:181-191`) drops the path pair, unless anything still references the hash: the history (view, global or a window's), the closed stack, a slot, a primary queue, or either displacement map, keys (`-swap` included) and values (`is_filehash_referenced`, `:146-176`). A referenced path stays (`:185`).
- `settle_rename` drops the buffer pair of a renamed buffer that settles as a move, before the buffer is registered under its new name (`history/routines.lua:610-612`, A20).
- At a load from idle, the history domain's teardown empties all four (`teardown`, `history/routines.lua:1027-1038`, S1).

A path is forgotten in four places, each through `unregister_filepath`, so only once nothing references its hash:
- an "evolved" buffer on re-entry (`:376`, M3)
- a reopened No Name buffer, which takes a new name (`:534`)
- an empty No Name buffer being closed (`:650`), whose own history entries go first (`:648`), and which leaves every secondary, ternary and primary queue (`window.data.forget_hash_in_slots`, `:649`)
- a rename that settles as a move, once every reference has followed to the new hash (`history/hooks.lua:104-106`, A20)

None of these leaves a slot or a note holding a hash with no path (I2, T129).

### M3. Which buffers are tracked

**Today** (`update_buffer_history`, `history/routines.lua:348-383`, called for every `BufEnter` once the editor settles, while history is attached, A1):
- **An unregistered buffer** is registered when `is_trackable` holds (`:356`, `:63-68`): it's listed, its name contains no `://`, and its `buftype` is `""` or it's `nowrite` on a readable file that isn't a directory (`is_nowrite_file`, `:49-55`). An unlisted buffer, such as otter's or a plugin's scratch, isn't registered (T10, T13). There's no check that its file exists. So `:e brandnew.lua`, a file not on disk yet, gets registered **[run s08]**.
- **A registered buffer** being re-entered keeps its registration in two cases (`:362-372`):
  - it's a No Name buffer (`buftype ""`, empty name, loaded)
  - its path isn't a directory, and either its file is readable or it's a plain buffer (`buftype ""`, no `://` in the name). So a file not written yet, or deleted on disk, stays tracked (T14).

  Otherwise it counts as "evolved": a directory, or a buffer that turned into a terminal, an `oil://` listing and the like. It's untracked and unregistered, its path is forgotten unless something still references its hash (M2), and the call returns false (`:373-378`).
- **A `BufWritePost`** on an unregistered buffer runs the same update once the write settles (`history/hooks.lua:140-160`).
- **A rename** registers the buffer under its new name once it settles, whatever the history state, when the new name is trackable (`history/hooks.lua:95-97`, A20).
- **An `OptionSet` of `buftype`** on a registered buffer that's no longer trackable undoes its arrival once the editor settles, and unregisters it (`window/hooks.lua:175-192`, I10, T217).
- **The session load** registers every restored buffer, loaded or not, whose name hashes to a path in the session file's `paths`, outsiders left out, and that `is_trackable` holds for (`storage/routines.lua:204-214`; T139). A restored buffer the file doesn't know isn't registered: it waits for its `BufEnter` (S1, T314).

**Decided:** a tracked buffer is listed, has `buftype ""` (or `nowrite` on an existing regular file), and has a name that's empty or a plain path. A missing file says nothing about it (DESK:37, DESK:2162). The otter, `image_nvim` and `://` special cases become properties (DESK:2148-2158). Built in step 1: the missing-file sentence. Built in step 2: the first sentence for registration on `BufEnter` (`is_trackable`), and `nowrite` in place of the `image_nvim` check in `register_buffer` and the getter; otter's buffers stay out because they're unlisted. Built in step 4: the session load registers through `is_trackable` too, and the save keeps every window that has a triquetra, with no filter on what it shows (S1). The UI still checks `image_nvim` by name (M12).

### M4. History

Fields in `history/data.lua`:
- `history_index` (`:69`): a counter that only goes up.
- `crux_internals.global` (`:61`): hash → time, for every window.
- `crux_internals.window[winid]` (`:60`): hash → time, for the visits recorded in that window.
- `crux` (`:58`): **the view** the bufferline and the close key use.
  - With `bufferline.history_view = "global"` (the default, `configs.lua:22-24`) it's a copy of the global history.
  - With `"window"`, it's that copy with the window's own entries re-ranked above every global entry (`construct_crux`, `history/routines.lua:239-274`).
- `ordered.crux` (`:65`): `{buf, time}` from `crux`, newest first. Hashes with no open buffer are dropped from the list and deleted from `crux` (`history/routines.lua:391-409`).
- `ordered.nonharpooned` (`:66`): the same list without harpooned buffers (`:433-449`). It's computed on every update but nothing reads it except `get_ordered_buffers(false)`. **[code]**

How history is updated:
- `track_buffer(hash)` (`:284-315`) does all of the following:
  - writes `history_index` into `crux` and `global`, then increments it
  - writes into the window history of the current window when the getter gives it a triquetra (M6). That's the window the visit happens in, since an arrival runs inside its own window (`nvim_win_call`, A1). Otherwise it writes into the history of `find_most_recent_tracked_window()`, the last-entered window that has a triquetra (`history/routines.lua:297-301`; DESK:2476, T19).
  - removes the hash from the closed stack (`:309-314`)
- Called with a time (session load), `track_buffer` writes that time into `crux` and `global`, and moves `history_index` past it (`:289-295`, T20). The window history still gets `history_index - 1` (`:306`). A load that goes through replaces both histories afterwards: `initialise_crux_internals` resets the window histories, puts back each matched window's own by window id, and puts the saved global history in place (`:214-220`; S1) **[code]**.
- `untrack_buffer` (`:321-339`) removes the hash from `crux`, `global` and every window's history, then rebuilds both ordered lists.
- `rename_hash_in_history(old, new)` (`:559-570`) moves a hash's entries in `crux`, `global` and every window's history to a new hash. An entry the new hash has already, being newer, stays. A reopened No Name buffer and a rename that settles as a move use it (M5, A20).
- The ordered lists are rebuilt:
  - after a successful track on an update
  - on every delete transition
  - in `untrack_buffer`, `reopen_filehash`, cleanup and repopulate
  - once a load settles, for the focused window (`after_restore`, S1)

  `construct_crux` doesn't rebuild them; the `BufEnter` that usually follows a `WinEnter` does **[run s17]**.
- `construct_crux(winid)` returns at once when called for the same window as last time (`:242-246`). In window view it gives the window's n buffers the n fresh times and adds n to `history_index` (`:265-271`), so the next visit ranks strictly first and never ties with the window's newest entry (D11, T197, T288). In the author's run, with two windows, going back into window A and running `:e e` gave `e=7 b=6 a=5 d=4 c=3` (Q4); with the tie fix the same run gives `e=8 b=7 a=5 d=4 c=3`, the same order. The property test T149 checks that the visited buffer is always leftmost (Q4).
- `WinClosed` drops the window's history entry (`history/hooks.lua:234-243`, `window/data.lua:65`).
- A triquetra the getter makes comes with its window's history entry: `register_triquetra` creates an empty one when there's none (`window/data.lua:42`), so a `:vsplit` window has one once its `WinEnter` settles (I3, T18). **[run s16]** recorded the split with none.
- At a load from idle, the history domain's teardown empties the view, both histories and the ordered lists, and sets `history_index` back to 1 (`history/routines.lua:1027-1038`, S1).

Window view, as run in s17: window 1 visits a, b, c, then window 2 (`:vsplit`) visits d and e. In window 2 the order is `e,d,c,b,a`. Back in window 1 it's `c,b,a,e,d`, and after `:e a` there it's `a,c,b,e,d` **[run s17]**.

### M5. Closed stack and No Name content

- `closed_buffers` (`history/data.lua:82`) is an array of hashes, newest last. Entries join it from:
  - `track_closing_filehash` on every delete transition, a rename that settles as a copy included (`history/hooks.lua:53`, A20)
  - `track_closing_filehash_force` when an unloaded path is typed into the primary history window (`window/routines.lua:216`)
  - `load_closed_buffers`, which clears the stack and rebuilds it from the file's saved hashes, leaving off one whose buffer the session manager brought back (`storage/routines.lua:596-634`, S1)
  - the session load, for a file in a matched window's slot or primary queue whose buffer the session manager didn't bring back, under the saved entries, as the oldest (`close_if_not_restored`, `storage/routines.lua:225-235`; S1, T337)
  - the stale pass of `cleanup_system`, for a file whose buffer went without events (`history/routines.lua:948-951`, A22)
- Entries leave it through:
  - `reopen_last_closed` (pops the last one)
  - `track_buffer`
  - `reopen_filehash` (`history/routines.lua:497-502`)
  - the swaps' `remove_from_closed_buffers` (`window/routines.lua:243-250`)
  - `cleanup_system` (A22)
  - a rename that settles as a move, which takes every copy of the old hash off (`history/routines.lua:604-608`, A20)
  - the history domain's teardown at a load from idle, which empties it (S1)

  Nothing deduplicates the stack today, but no route was found that pushes a file twice: every reopen takes the file off, and a closed file keeps its record, so the primary pop-up never pushes it **[run s20]**. Decided (2026-10-20): one copy per pool, newest wins (Q15, I22).
- `noname_content[hash] = {lines, filetype, cursor}` is cached when a **non-empty** No Name buffer is closed (`history/routines.lua:643-661`). The cursor is the one in the window showing it, or, when none does, the one `<M-.>` kept before switching the window away (`vim.b[bufnr].cavediver_cursor`, `:659`, T83). An empty one is untracked, taken out of every secondary, ternary and primary queue (`window.data.forget_hash_in_slots`), then has its path forgotten unless a current slot or a note still references it, and isn't pushed (`:647-652`). A rename that settles as a move drops the old hash's text, which is in its file then (`:609`, A20), and the teardown at a load from idle drops them all (S1).
- `reopen_filehash(hash)` (`history/routines.lua:491-552`) reopens a closed hash:
  - It looks up the path and removes the newest matching entry from the closed stack.
  - **A No Name hash:**
    - With nothing cached, it returns `nil` (`:506-508`).
    - It creates a new listed buffer with the cached lines and filetype.
    - It sets the cached cursor in the window that shows the buffer, once one does: a one-shot `BufWinEnter` on that buffer sets it there (`:514-522`, T90).
    - It drops the cache, registers the buffer under a fresh `NONAME_<id>` (M1) and tracks it. Everything that named the old hash follows to the new one (`:524-532`, T91): every window's slots, primary queue and notes (`rename_hash_in_triquetras`), and the history (`rename_hash_in_history`, M4). Then the old path is forgotten, unless something still references it (`:533-535`, M2).
  - **A file:** if the file is readable it runs `bufadd`, sets `buflisted` before `bufload` (whose `BufEnter` only tracks listed buffers), then registers and tracks the buffer.
  - In both cases it then runs `update_buffer_history` and rebuilds the lists, and returns the bufnr. When the file is missing it returns `nil`, and the hash is already off the closed stack, since that step comes first (`:497-502`).
- The display name of a closed slot comes from its path. After a `:bdelete` the unlisted buffer still exists; `find_basename_conflicts` skips the file's own path, so the buffer isn't a clash with itself, and the winbar shows the basename (`ui/routines.lua:144-157`, T118). **[run s06, s14]** recorded the full path before the fix.

### M6. The triquetra

One per window, in `window.data.crux[winid]`. Fields (`window/data.lua:8-15`, `:43-51`):

| Field | Type | Meaning |
|---|---|---|
| `current_slot` | hash, required | the tracked buffer the window is on |
| `secondary_slot` | hash or nil | the parked buffer |
| `ternary_slot` | hash or nil | the previous buffer, filled in automatically |
| `primary_buffer` | array of hashes | the primary queue; `[1]` is the primary |
| `primary_enabled` | boolean | whether `[1]` is active |
| `displacement_ternary_map` (dtm) | table | see M7 |
| `displacement_secondary_map` (dsm) | table | see M7 |

**Creation.** `get_window_triquetra(winid)` (`window/data.lua:80-97`) creates the triquetra lazily, holding only the current slot (the window's buffer hash), together with the window's history entry when there's none (`register_triquetra`, `window/data.lua:42`, I3), when:
- the window isn't a float, and
- its buffer is registered.

It returns nil for a window that's no longer valid (`window/data.lua:81-83`). It never drops a triquetra: a window keeps its own while it shows something untracked (A2). Every caller but the session load runs once the editor settles (an arrival, a window entry, a key, a UI tick), so a window born untracked (`:help`, `:copen`, `:split | terminal`) already shows what it was born with when the getter first sees it, and never gets one (A2, T225, T217). The session load runs inside the manager's hook, and there too the getter gives a triquetra only to a window whose buffer is registered (S1).

It's called in these places, so a new split gets its triquetra once its `WinEnter` settles, or at the next UI tick **[run s07, s16]**:
- by `ensure_curwin_crux` on every history update (`window/hooks.lua:32-38`)
- by `track_buffer`, on the current window (`history/routines.lua:299`, M4)
- by `find_most_recent_tracked_window` (`navigation/routines.lua:108`)
- by every slot action
- by the UI's derive path (`ui/routines.lua:251`)
- by the session load, for a window that matches no saved entry (`storage/routines.lua:268`, S1)

**Removal** goes through `unregister_triquetra` (`window/data.lua:57-74`). It happens:
- on `WinClosed` (`window/hooks.lua:167-173`)
- in `cleanup_triquetras`, for a window it can't heal, and for a visiting window whose current slot names nothing open or closed (A21)
- in `undo_arrival`, for a window whose current slot turns untracked with nothing to take its place (I10)

The getter never removes one (A2). **[run s15]** recorded `:terminal` in the window dropping the triquetra, before the visiting rule.

Removal also does four things:
- drops the window's history entry, its arrival (below) and its UI cache
- re-points `last_valid_window` along the jump chain
- rebuilds the history view
- clears the winbar

A load from idle drops every triquetra at once, outside `unregister_triquetra`: the window domain's teardown clears their winbars, empties `window.data.crux`, `landing` and `arrivals`, and sets `current_window` and `last_valid_window` to the current window (`window/hooks.lua:19-30`, S1).

Two other writers:
- `set_buffer_relationship` (`window/init.lua:40-64`) is used by the session load. It takes `primary_enabled` from the saved entry (`:60`; S1, T136). It writes the triquetra directly, not through `register_triquetra`, and gives the window its history entry itself (`:52`, I3) **[code]**.
- `repopulate_window_relationships` (`window/routines.lua:1093-1117`) gives every window with a registered buffer a fresh triquetra, also written directly, not through `register_triquetra` **[code]**. It writes a buffer number into `last_valid_window` (`:1096`). **bug (desk)**

**Arrivals.** `window.data.arrivals[winid]` (`window/data.lua:27-30`) holds the window's last arrival, for I10's undo: the arriving hash, a copy of the triquetra just before it (`remember_arrival`) and a copy just after it (`seal_arrival`) (`window/routines.lua:114-128`). `displacement_mangement` and `reconcile_triquetra` write it whenever the buffer arriving isn't already current (`window/hooks.lua:66-68`, `:124`; `window/routines.lua:268`, `:328`).

**Who writes each slot.** Every writer of each slot, so tests can cover them all:

| Slot | Writers |
|---|---|
| current | getter creation, `c := shown` (M6); plain navigation, `c := X` (A1); `<M-f>`, `c := S` (A6); `<M-S-f>`, `c := T` (A7); primary jump, `c := P`, and while cycling `c := start` (A8); cycling pick, `c := X`, `T` or `S` (A13); cleanup re-point, `c := shown`, and its fallback chains ternary → secondary → `primary[1]` → most recent (A21); the landing after a delete, `c :=` the ternary, the secondary, `primary[1]` or the most recent (A19); `undo_arrival`, `c :=` the current from before the arrival, or the ternary, the secondary or `primary[1]` (I10); a rename (`rename_hash_in_triquetras`): a reopened No Name buffer (M5) or a rename that settles as a move (A20); session load (S1) |
| secondary | `<M-f>`: graduation `s := T`, fill from history `s := ordered[2]`, swap `s := A`, reopen failure `s := nil` (A6); plain navigation to the secondary, `s := A` (A1); cycling pick of the secondary, `s := A` (A13); restore secondary `s := remembered`, and restore ternary when it equals the secondary, `s := old t` (A11); cleanup's re-point when the window shows the secondary, `s := old c` (Q18), and cleanup clears it when pruned or when it moves up into the current slot (A21); the landing after a delete clears it when it moves up into the current slot (A19); `undo_arrival` puts back the one from before the arrival, or clears it when it moves up into the current slot, and the untracked buffer leaves it (I10); an empty No Name buffer closed leaves it (M5); a rename (M5, A20); session load |
| ternary | **auto-population**: plain navigation `t := A` (A1), primary jump `t := A` (A8); `<M-S-f>` `t := A` (A7); cycling pick of the ternary `t := A` (A13); graduation `t := nil` (A6); reopen failure `t := nil` (A7); restore ternary `t := remembered`, and restore secondary when it equals the ternary, `t := old s` (A11); cleanup's re-point, `t := old c` (Q18), and cleanup clears it when pruned or when it moves up into the current slot (A21); the landing after a delete clears it when it moves up into the current slot (A19); `undo_arrival` puts back the one from before the arrival, or clears it when it moves up into the current slot, and the untracked buffer leaves it (I10); an empty No Name buffer closed leaves it (M5); a rename (M5, A20); session load |
| primary queue | `toggle_primary` on an empty queue (A9); `set_primary` (A10); a popup save replaces it (A18); the primary jump renames a reopened No Name `[1]` (A8); cleanup prunes entries (A21); `undo_arrival` puts back the one from before the arrival, and the untracked buffer leaves it (I10); an empty No Name buffer closed leaves it (M5); a rename (M5, A20); session load |
| `primary_enabled` | `toggle_primary` (A9); `set_primary` (A10); a popup save sets it to "queue not empty" (A18); `undo_arrival` puts back the one from before the arrival (I10); session load takes it from the file (S1) |

The save's substitution for a No Name current slot (S1, step 3) only changes what's written to the file, not the live triquetra.

### M7. Displacement maps

Each map is keyed by a buffer that was displaced and remembers one slot value for it. Both maps also have `-swap` keys. Who writes which key:

| Key | Value | Written by |
|---|---|---|
| `dtm[X]` | X's ternary at the moment X was left by **plain navigation** | `displacement_mangement` (`window/hooks.lua:94-97`), when the ternary exists and the new buffer isn't the ternary; the same write deletes `dtm[X-swap]`. A cycling pick of an outside buffer X writes `dtm[X] := start` (`window/routines.lua:316-319`, Q9). Cleanup's re-point writes it the same way, when the old current X goes into a ternary other than the buffer the window shows, and deletes `dtm[X-swap]` (`:467-470`, Q18). Also Q6's guard, which rewrites `dtm[T]` to the buffer being left on every route onto the secondary (`window/hooks.lua:76-79`, `window/routines.lua:287-296`), the guard on a pick of an outside buffer (`:304-312`), the stale-note checks (`window/hooks.lua:99-113`; `keep_older_ternary_note` and `check_notes_under_current`, `window/routines.lua:29-44`, `:93-107`), and restore (`:1063`). |
| `dtm[X-swap]` | X's ternary at the moment X was left by a **swap or a primary jump** | every swap onto the secondary, `<M-f>`, its `<M-;><M-f>` fallback, plain navigation onto the secondary and cleanup's re-point onto a shown secondary (`write_secondary_swap_notes`, `window/routines.lua:82-84`, only when a ternary exists; the re-point at `:464`, Q18); `reconcile_triquetra` when the chosen buffer is the ternary (`:277`), which covers `<M-S-f>` and `<M-v>` on the ternary; `jump_to_primary` (`:928`, which writes nil when there's no ternary). A cycling pick of an outside buffer X deletes it (`:318`, Q9). |
| `dsm[X]` | X's **previous** secondary: the one it had before the secondary it was last left for | on every swap onto the secondary, the secondary's own swap note becomes its plain note when it names a buffer other than the one being left, and otherwise a plain note naming the buffer being left is cleared (`write_secondary_swap_notes`, `:75-81`); the ternary-to-secondary graduation copies `dtm[G]` into `dsm[G]` (`:751-752`), which is intended (Q3); restore (`:1063`); the stale-note check rewrites it to the swap note or drops it (`keep_older_secondary_note`, `:53-64`, A1). |
| `dsm[X-swap]` | X's secondary at the moment X was left for it | every swap onto the secondary: `<M-f>`, its `<M-;><M-f>` fallback, plain navigation onto the secondary (`write_secondary_swap_notes`, `:76`, D8) and cleanup's re-point onto a shown secondary (`:464`, Q18). Graduation clears the graduated buffer's (`:753`). |

- The maps are never pruned, except that a restore clears a note at a hash with no path when it uses it (A11). `rename_hash_in_triquetras` (`window/data.lua:125-177`) renames keys and values, the `-swap` keys of both maps included (`:149-152`, `:159-163`). `undo_arrival` puts back both maps as they were before an arrival it undoes (I10).
- The two kinds of note are intended (Q2): plain notes `dtm[X]` from navigation, and swap notes `dtm[X-swap]` from swaps and primary jumps. A restore prefers the swap note unless it names the occupant of the slot it restores into, the ternary for dtm and the secondary for dsm (A11). The author confirmed the design but forgot why; the reasons found by runs are under Q2 in section 8.
- **Decided (2026-10-20):** more writes.
  - A cycling pick of an outside buffer X writes the plain note `dtm[X] := start` and clears X's swap note `dtm[X-swap]`, as navigation clears the left buffer's (Q9, A13).
  - On every route onto the secondary, the "avoided conflict" guard rewrites `dtm[T]` to the buffer being left, before the swap (Q6, A6).
  - Plain navigation onto the secondary records the same notes as `<M-f>` (D8, A1).
  - Built in step 3.
- **Decided (2026-10-20 evening), "Keep the older one".** The secondary map gets the ternary map's two kinds of note, and whenever a buffer becomes current, any of its notes that has gone stale is rewritten to the older one instead of being left to make a restore throw (A1, A11, I23):

  | Key | Value | Written by |
  |---|---|---|
  | `dsm[X-swap]` (new) | X's secondary at the moment X was left for it | `<M-f>`, its `<M-;><M-f>` fallback, and plain navigation onto the secondary (D8), in place of the plain note `dsm[A] := S` (A1, A6). Graduation clears the graduated buffer's swap note (A6). |
  | `dsm[X]` (meaning changes) | X's **previous** secondary, no longer the one it had when swapped out | on the same three routes, when X arrives: X's swap note, when that names a buffer other than the one being left; otherwise a plain note naming the buffer being left is cleared (A6). Graduation's copy (Q3) and the restore's flip still write it. The stale-note check rewrites it on other arrivals (A1). |

  - A restore's swap-note fallback compares with the slot it restores into: the ternary for dtm, as today, and the secondary for dsm (A11; `window/routines.lua:1017-1023`).
  - `rename_hash_in_triquetras` carries dsm's `-swap` keys as it already carries dtm's (`window/data.lua:149-152`), so a renamed buffer keeps both kinds of note on both maps (T192).
  - The missing-file rule (D9) covers both maps, swap keys included (T193).
  - Stored with the rest of each map, so the save file's format doesn't change (`storage/routines.lua:511-512`) **[code]**.
  - Built in step 3: the notes (`write_secondary_swap_notes`, `window/routines.lua:72-85`), the check on every arrival (`keep_older_ternary_note`, `keep_older_secondary_note`, `:29-64`) and wherever a slot changes under the current buffer (`check_notes_under_current`, `:93-107`), the fallback, the renames, and D9 on both maps.

### M8. Primary queue

- `primary_buffer[1]` is the primary and the rest are earlier primaries (README:22). The queue isn't deduplicated against the slots, so the primary can also be the current, secondary or ternary (SPEC:44). That's intended: the primary is mobile (Q16).
- `primary_enabled` decides two things:
  - whether `jump_to_primary` uses the queue (A8)
  - whether the UI paints the primary as active (`ui/routines.lua:339`)
- `<M-;><M-x>` (`toggle_primary`) is its on/off switch, and `<M-;><M-c>` (`set_primary`) makes the current buffer the primary (Q8).
- **Decided (2026-10-20):** a save from the primary queue window switches it on only when the first row changed (Q10, A18).
- Writers:
  - `toggle_primary` (A9)
  - `set_primary` (A10)
  - `update_primary_buffer`, from the popup (A18)
  - `jump_to_primary`, when it renames a No Name `[1]`
  - cleanup pruning (A21)
  - an empty No Name buffer closed, which leaves every queue (M5)
  - `rename_hash_in_triquetras`

### M9. Cycling

- Cycling is navigation state `cycling` with history `detached`.
- `cycling_origins[winid]` is **the live triquetra table itself**, not a copy. At cycle start its `current_slot` is set to the hash of the window's buffer (`history/routines.lua:457-484`) **[run s03]**. The docstring at `:454` says it stores a deep copy.
- `navigation.data.cycling_window` is the window a cycle runs in: `start_cycling` records it and `stop_cycling` clears it (`navigation/data.lua:10`, `:43`, `navigation/hooks.lua:26`, `:38`), and so does the navigation domain's teardown at a load from idle (`:18`, S1).
- While history is detached:
  - `BufEnter` neither tracks history nor touches slots.
  - The current slot stays the cycle's starting buffer **[run s03]**. That's intended: it stays there until `<M-v>` (Q1).
  - `nondisplacement_management` (`window/hooks.lua:140-153`) never does anything, because a `BufEnter` context carries no `winid`.
- A load from idle ends a cycle left open: the teardowns set navigation to `normal` and history to `attached` directly, with no transition, so no hook runs and nothing is picked (S1, T296).
- **Decided (2026-10-20 evening):** a `WinEnter` into another window cancels the cycle: the cycling window goes back to its start and nothing is recorded (A12). Built in step 3.

### M10. Window-jump history and window tracking

- `navigation.data.window_jump_history[to_win] = from_win` (`navigation/data.lua:42`) is one flat table, though the type comment at `:9` says it's per tab.
  - It's recorded once each `WinEnter` settles, unless the focus has moved on by then (`navigation/hooks.lua:78-90`, `:99-117`). The "from" window is `winnr('#')`, or `last_valid_window` when there's none, read at the event and passed on as `previous_win`. It's skipped when that window's filetype is `minimap` (`navigation/routines.lua:45-56`).
  - Entries for closed windows stay until a load from idle, where the navigation domain's teardown empties the table (`navigation/hooks.lua:19`, S1) **[code]**.
- `window.data.current_window`: the last window entered (`window/hooks.lua:155-158`).
- `window.data.last_valid_window`: the last window with a triquetra (`navigation/routines.lua:102-116`, `window/data.lua:67`). Both are set to the current window at require time (`window/data.lua:179-182`) and at a load from idle, by the window domain's teardown (`window/hooks.lua:28-29`). Once a load settles, the focused window becomes both when it has a triquetra (`after_restore`, `storage/routines.lua:716-725`; S1, T299). `find_most_recent_tracked_window` returns it only while that window is valid, and the getter gives no triquetra for a window that's gone (`navigation/routines.lua:106-112`, `window/data.lua:81-83`).

### M11. State machines

**Engine semantics** (`engine/state-machine.lua`, `engine/helpers.lua`). These matter for tests.
- `sm:to(next, ctx, mode)`:
  - It deep-copies `ctx`, then sets `ctx.caller` (the machine's name) and `ctx.mode` (`mode` or `"*"`).
  - The transition `current->next` must be registered. It's registered only once some hook has been bound to it with `on()`, so a transition with no hook throws `Transition '…' is not registered` from `to()` itself (`:505-507`).
  - **The new state is set after every hook has run** (`:512-513`), so `sm:state()` inside a hook returns the old state. A critical hook's failure abandons the transition before that, so the state stays (Errors, below).
- **Pipeline:**
  - Only enabled hooks bound to that exact transition run, sorted by class, lower first.
  - The sort is `table.sort`, which isn't stable for equal classes.
  - General hooks would run before and after; none are registered.
  - The transition is appended to `sm.history`, which grows without limit. The UI loop alone adds about ten entries a second **[run s16]**. That's intended: there's no cap, and the history is there for debugging; nothing in the code reads it (Q21). Measured on 2026-10-20: about 7 entries a second from `ui_loop` while idle (72 in 10 s), and 600,000 entries take about 8 MB, so roughly 8 MB per day the editor stays open.
- **Mode filter** (`helpers.lua:243-283`):
  - `to()` with no mode runs only hooks registered with filter `"*"`.
  - `to(…, m)` runs `"*"` hooks plus those whose filter includes `m`.
- **Errors:** every hook runs inside `xpcall` with `debug.traceback` (`helpers.lua:36-45`). A failure becomes a `vim.notify` ERROR, "Hook '<name>' failed during transition a->b: …" followed by the stack traceback, and the pipeline goes on. The state still changes.
  - A hook marked with `make_hook_critical(name)` (`state-machine.lua:408-415`) isn't notified: its error, the same message and traceback, is re-thrown with `error(message, 0)` to whoever called `to()`. The rest of the pipeline doesn't run and the new state isn't set, so the machine stays where it was; the transition is already in `sm.history`. The only critical hook is storage's save hook (`storage/hooks.lua:17`).
- **Shared modes:** `transition_modes` is a class-level table shared by every machine, so all machines know `cycle`, `winenter`, `delete` and `update` **[run s16]**. That's intended: modes are one vocabulary for orchestrating all machines, and a hook may name any registered mode (Q20). A mode doesn't travel between machines on its own; each `to()` names its own, and today every call passes a mode its target machine registered.
  - **Decided (2026-10-20):** the code says so. The class declares the shared table on purpose, the factory comment (`engine/init.lua:18`, "its own independent state, transitions, hooks, and history") stops implying modes are per machine, and the two checks worded per machine (`helpers.lua:258`, "This state machine doesn't have any transition modes registered", which can't fire with a shared table, and `helpers.lua:276`, "not registered in this state machine") are reworded or dropped.
- **Two engine bugs:** `off()` removes from `self.bindings` by index, and `unregister_hook` calls the class instead of the instance (`state-machine.lua:361`, `:382`). **bug (desk)**

**Machines:**

| Machine | States (initial first) | Transitions in use |
|---|---|---|
| navigation | `normal`, `cycling`, `file_picker` (never entered) | `normal->cycling`, `cycling->cycling` and `cycling->normal` (mode `cycle`); every self-transition (mode `winenter`); `cycling->normal` with no mode, from the window-jump cancel, which runs no hook (A12) |
| history | `attached`, `detached` | self-transitions (`update`/`delete`), `attached->detached`, `detached->attached` |
| window (`window/sm.lua`) | `showing_primary`, `showing_secondary`, `showing_ternary`, `showing_other` | none; never transitions. Decided (2026-10-20): the machine is removed (D25, T170). |
| ui_bufferline | `bufferline_visible`, `bufferline_hidden` | none registered, so `hide_bufferline()`/`show_bufferline()` throw **bug (desk)** |
| ui_indicators | `indicators_on`, `indicators_off` | none registered, so the same throw |
| ui_loop | `self` | `self->self`, which refreshes the UI |
| (ui winbar) | used by `ui/init.lua:112`, `:119`, `:151`, but never created | `hide_winbar()` and `show_winbar()` index nil **bug (desk)** |
| storage | `bare`, `idle`, `saving`, `loading`, `error`, `auto_saving` | `{idle,bare}->saving`, `idle->bare`, `bare->loading`, `{bare,saving,loading}->{idle,saving}`; `error` and `auto_saving` are never used |

At a load from idle, the history and navigation teardowns set their machines' states directly, to `attached` and `normal`, with no transition, so no hook of those machines runs (S1).

**Hooks**, in the order they run within each transition:

| Machine | Transition | Mode | Class | Hook | What it does |
|---|---|---|---|---|---|
| navigation | normal→cycling | cycle | 1 | `start_cycling` (`navigation/hooks.lua:22`) | history → detached (mode update), records `cycling_window`, then step once |
| navigation | cycling→cycling | cycle | 1 | `keep_cycling` (`:30`) | step once |
| navigation | cycling→normal | cycle | 1 | `stop_cycling` (`:34`) | history → attached with `{buf = picked, pick = true}` (mode update), clears `cycling_window`, then a UI refresh |
| navigation | *→* | winenter | 1 | `winenter_record_window` (`:78`) | records the window jump, from `previous_win`, read at the event |
| navigation | *→* | winenter | 2 | `winenter_track_current_window` (`window/hooks.lua:155`) | sets `current_window` |
| navigation | cycling→cycling | winenter | 2 | `cancel_cycle_on_window_jump` (`navigation/hooks.lua:45`) | in a window other than the cycling one, once the editor settles: the cycling window back to its start, navigation → normal with no mode, history → attached with the buffer of the jumped-to window's current slot (mode update), then, when the window shows another buffer, attached→attached with it (plain navigation, A1), a UI refresh (A12) |
| navigation | *→* | winenter | 3 | `winenter_update_history_view` (`history/hooks.lua:67`) | `construct_crux(find_most_recent_tracked_window())` |
| navigation | *→* | winenter | 4 | `winenter_update_ui` (`ui/hooks.lua:52`) | UI refresh |
| history | *→* | delete | 0 | `handle_deletion` (`history/hooks.lua:42`) | for a registered buffer: push it on the closed stack, untrack it, unregister it |
| history | *→attached | * | 1 | `attach_history_update` (`:12`) | on update: `update_buffer_history(buf)`, then reorder if it changed, and set `context.history_modified`; on delete: reorder |
| history | *→* | update | 1 | `ensure_curwin_crux` (`window/hooks.lua:32`) | the getter on the current window (creates its triquetra when there's none) |
| history | *→* | * | 1.8 | `cleanup_triquetras` (`window/hooks.lua:40`) | A21, on **every** history transition |
| history | attached→detached | * | 2 | `detach_history` (`history/hooks.lua:35`) | saves the cycling origin and notifies "Checkpoint saved" |
| history | attached→attached | update | 2 | `displacement_mangement` (`window/hooks.lua:50`) | A1, and it remembers the arrival (M6) |
| history | detached→attached | update | 2 | `reconcile_triquetra` (`window/hooks.lua:127`) | A13, and it remembers the arrival (M6) |
| history | detached→detached | update | 2 | `nondisplacement_management` (`window/hooks.lua:140`) | never does anything (M9) |
| history | *→attached | update | 3 | `refresh_ui_attached` (`ui/hooks.lua:39`) | UI refresh if history changed |
| history | detached→detached | update | 3 | `refresh_ui_detached` (`ui/hooks.lua:48`) | UI refresh |
| ui_loop | *→self | * | 1 | `update_ui_state` (`ui/hooks.lua:29`) | `refresh_ui(tracked window)` and `show_ui()` |
| storage | {idle,bare}→saving | * | 1 | `save_history_pre_quit` (`storage/hooks.lua:10`) | `save_history(directory, name)`, the session's directory and name from the context; critical (`:17`), so a failure throws to the caller |
| storage | bare→loading | * | 1 | `load_history_pre_start` (`:19`) | `load_history(directory, name)` |
| storage | {bare,saving,loading}→{idle,saving} | * | 1 | `back_to_idle` (`:24`) | nothing |
| storage | idle→bare | * | 1 | `navigation_teardown` (`navigation/hooks.lua:16`) | navigation → normal, set directly; clears `cycling_window` and the window-jump table |
| storage | idle→bare | * | 2 | `window_teardown` (`window/hooks.lua:19`) | clears the winbars, drops every triquetra, empties `landing` and `arrivals`, sets `current_window` and `last_valid_window` to the current window |
| storage | idle→bare | * | 3 | `history_teardown` (`history/hooks.lua:62`) | `teardown()` (S1), then history → attached, set directly |
| storage | idle→bare | * | 4 | `ui_teardown` (`ui/hooks.lua:17`) | clears the window display caches, the display-name cache and the bufferline state, in place |

**Triggers.** All are created by `setup()`, in the `cavediver` augroup, through each domain's `init_autocmds(group)` (`init.lua:149-154`):
- `WinEnter` → a navigation self-transition with mode `winenter`, once the editor settles, carrying the window the jump came from as `previous_win`, read at the event; skipped when the focus has moved on by then (`navigation/hooks.lua:99-117`).
- `BufEnter` → a history self-transition with `{buf}`, mode `update`, once the editor settles and inside the event's window (`nvim_win_call`); skipped when the window or the buffer is gone or the window shows something else by then, when history was detached at the event (a cycle's step) and isn't any more, and when a session loaded since the event (`history/hooks.lua:163-196`, A1, S1). Neovim's own pick in a window whose buffer is being deleted is left out at the event (A19).
- `BufDelete` → a history self-transition with `{buf}`, mode `delete`, unless `b:skip_bufdelete` is set. A registered No Name buffer is noted first, with its history, for a write under a name in the same batch (`:117-138`, A20).
- `BufWritePost` → once the write settles, the rename of a No Name buffer written under a name, claimed at the event, or else an update for an unregistered buffer (`:140-160`, A20).
- `BufFilePre` → records a registered buffer's old hash, and `BufFilePost` → settles the rename once the editor settles (`:199-231`, A20).
- `WinClosed` → drop the window's history entry (`history/hooks.lua:234`), drop its triquetra (`window/hooks.lua:167`), and the popup cleanup, which runs `once` (`ui/hooks.lua:139`).
- `OptionSet` for `buftype` → once the editor settles, a registered buffer that's no longer trackable has its arrival undone (`window/hooks.lua:175-192`, I10).
- `BufAdd`, `BufDelete`, `BufFilePost` and `BufWritePost` → clear the display-name cache (`ui/hooks.lua:65`).
- `VimResized` → a debounced UI refresh (`:72`).
- `BufModifiedSet` → a UI refresh (`:79`).
- `FileType cavediver-primary-buffer-history` → the popup's keymaps (`:86`).
- `SourcePost` on a `restart_session_*` file while `v:startreason` is `restart` → the last load of this startup runs again once the editor settles, ignoring the repeat flag (`storage/init.lua:73-92`, S1).

The popup's own `BufDelete` and `BufWriteCmd` are buffer-local, made each time it opens, outside the group (`ui/routines.lua:70-81`, `:83`). So is the one-shot `BufWinEnter` that gives a reopened No Name buffer its cursor (`history/routines.lua:516-522`, M5).

**Timers.** These start in `setup()`. Each keeps its handle, so running `setup()` again stops it before starting it, and `disable()` stops both (`history/init.lua:40-46`, `ui/init.lua:60-66`):
- `cleanup_system` runs every `cleanup_interval` ms, with the first tick at once (`history/init.lua:50-91`).
- The UI refresh runs every `winbar_refresh_interval` ms through a 100 ms debounce (`ui/init.lua:70-85`, `ui/routines.lua:752-767`), which comes to about every 140 ms.

Neither `setup()` nor a load starts a one-shot delay: what a load leaves for later runs once the restore's batch is over, on `vim.schedule` (`after_restore`, S1).

### M12. UI

**Winbar.** Written for every triquetra window that passes `is_real_file` or `is_visiting` (`ui/routines.lua:711-740`). `is_real_file` (`:661-686`) holds when:
- not a float
- `buftype` is `""`, `terminal` or `acwrite`
- loaded
- no `://` in the name unless the buffer is `acwrite`
- filetype not on the exclusion list (`ui/data.lua:129-146`)

`is_visiting` (`ui/routines.lua:694-699`) holds when the shown buffer isn't registered, it's loaded, the window isn't a float, and the filetype isn't on the exclusion list.

The string, as rendered **[run s14]**:

```
────── ⦉T⦊ [C] current-name <arrow-glyph>  ⟦S⟧ secondary-name ─────…
```

- The ternary shows as `⦉N⦊ ` when it's open, or `⦉ <icon> name ⦊ ` when it's closed.
- The current shows as `[N] name`, or `⦉N⦊ name` when it's the primary. A glyph follows when the buffer is modified.
- While visiting, the current piece reads `[N] name ← [<type>]`. `<type>` is the shown buffer's `buftype`, or its filetype when the `buftype` is `""` or `acwrite`, so oil shows `[oil]` (`ui/routines.lua:322-330`, `:503-506`; T268). A closed current slot, allowed only while visiting, shows the closed icon where the number goes: `[<icon>] name ← [<type>]` (`:508-516`, T270).
- The secondary shows as arrow, `⟦N⟧ name` (`⦉N⦊` when it's the primary), or arrow, icon, name when it's closed.
- The padding fills the window's width.
- Highlights come from the `focused`, `unfocused` and `topwin_overlapped` themes (`ui/data.lua:74-108`); a top window that overlaps the focused window takes its focus colours (`ui/routines.lua:609-640`).
- The primary is matched by **display name**, not by hash (`ui/routines.lua:459-479`).
- While cycling, the current name uses the base highlight (`:455-457`).
- `zsh:terminal` is rewritten to `terminal:` (`:587`).
- The winbar is set to `""` when the triquetra is dropped (`window/data.lua:72`) or when the current buffer can't be resolved (`ui/routines.lua:518-532`).

**Bufferline.** Cavediver doesn't draw it. It hands cokeline its callbacks (`ui/init.lua:165-588`):
- `bufnr_is_displayed`: the bufferline state is visible and the buffer is in the "recent" set. Today that set is every buffer in the ordered history, because of `math.max(#ordered, 30)` (`ui/routines.lua:405`). That's intended: the bufferline shows every tracked buffer (Q5). **Decided:** `math.max` stays (2026-10-20), and the 30, which means nothing there, goes (2026-10-21).
- `compare_buffers`: by time in the history view, newest first.
- colour callbacks:
  - The text colour goes by the buffer's role, in the order primary, secondary, current, ternary, focused, harpooned, other (`ui/init.lua:254-274`).
  - The background turns the "detached" colour while history is detached (`:279-293`).
- components:
  - `[N]` for the current, `⟦N⟧` for the secondary, `⦉N⦊` for the primary or the ternary.
  - The harpoon mark and `⥤ {n}` label.
  - The index is dimmed when the primary is disabled (`:335-543`).
- `get_buffer_relationships(buf)` throws "A buffer cannot have more than one role" when, for example, the current buffer is also the primary **[run s14]**. **bug (new)**; the README's cokeline setup doesn't call it. **Decided (2026-10-20):** the one-role assertion is fixed or the function removed. Nothing calls it, neither cavediver nor the author's config (Q16).

**Caches:**
- `bufferline_state` is computed by `refresh_ui` for the tracked window (`ui/routines.lua:369-420`), and it requires harpoon.
- `window_display_cache[winid]` is set for every triquetra by `cleanup_triquetras` (`window/routines.lua:701`). Deriving it first checks the window's slots: when any slot's registered buffer is no longer valid (wiped without events), it runs `cleanup_system` at once, so the registry and the window are repaired within one refresh (`ui/routines.lua:255-272`, A22, T242). The cache also holds `deleted_slots.current` and `visiting`, the shown buffer's type while visiting (`ui/data.lua:23`, `:40`). A current slot with no open buffer sends the derive path to cleanup, unless it's a closed slot while visiting. It retries once, counted by a parameter, and when the slot still has no open buffer it raises "Impossible state: current_bufnr is nil …" (`ui/routines.lua:341-350`).
- `display_name_cache` is cleared on `BufAdd`, `BufDelete`, `BufFilePost` and `BufWritePost`.
- At a load from idle, the UI domain's teardown clears `window_display_cache`, `display_name_cache` and `bufferline_state` in place (`ui/hooks.lua:17-27`, S1).

**Smart basename** (`ui/routines.lua:195-245`):
- the basename, or the shortest path suffix that's unique among buffers with the same basename; a closed file's own unlisted buffer doesn't count (T118)
- `[No Name]` for an empty name
- `[<buftype>]` for a special buffer
- It throws for a hash with no path.

### M13. Configuration

Defaults are in `configs.lua:20-134`. `setup(user)` deep-merges the user's table into the defaults and throws on a type mismatch (`init.lua:130-144`). `setup()` with no argument merges an empty table, so it uses the defaults (`user_config or {}`, `:144`; T125). **[run s13]** recorded it throwing `bad argument #1 to 'pairs'` without the `or {}`.

| Key | Default | Used by |
|---|---|---|
| `session_dir` | `stdpath("data") .. "/cavediver/sessions/"` | `storage/routines.lua:649` |
| `bufferline.history_view` | `"global"` | `history/routines.lua:248` |
| `primary_buffer_history_popup.{height,width}` | `0.2`, `0.7` (a ratio when ≤ 1, otherwise cells) | `ui/routines.lua:103-117` |
| `colors.*` | Flexoki-like hex values | highlights `ui/init.lua:33-54`, bufferline callbacks |
| `keymaps.*` | see the action table in section 3 | `init.lua:29-119` |
| `cleanup_interval` | `4000` (milliseconds, though the comment says seconds) | `history/init.lua:54` |
| `winbar_refresh_interval` | `140` ms | `ui/init.lua:80` |

## 3. User actions and editor events

### Coverage

Every default keymap (`configs.lua:106-131`, bound in `init.lua:29-119`) and every export in `init.lua`:

| Export (init.lua) | Default key | Action |
|---|---|---|
| `toggle_secondary` (`:398`) | `<M-f>` | A6 |
| `toggle_ternary` (`:403`) | `<M-S-f>` | A7 |
| `jump_to_primary` (`:408`) | `<M-;><M-f>` | A8 |
| `toggle_primary` (`:434`) | `<M-;><M-x>` | A9 |
| `set_primary` (`:444`) | `<M-;><M-c>` | A10 |
| `restore_ternary` (`:413`) | `<M-;><M-r>` | A11 |
| `restore_secondary` (`:418`) | `<M-;><M-t>` | A11 |
| `cycle_left` / `cycle_right` (`:424`, `:426`) | `<M-n>` / `<M-m>` | A12 |
| `cycle_select` (`:429`) | `<M-v>` | A13 |
| (no cancel) | — | A14 |
| `delete_buffer` (`:439`) | `<M-.>` (`close_buffer`) | A15 |
| `reopen_last_closed` (`:395`) | `<M-S-w>` | A16 |
| `toggle_window` (`:428`) | `<M-,>` | A17 |
| `open_primary_buffer_history` (`:431`) | `<M-;>F` | A18 |
| `save_session` / `load_session` (`:391-392`) | — | S1 |
| `setup` (`:127`), `disable` (`:382`) | — | M13, A25 |
| `get_storage_state`, `get_navigation_state`, `get_history_state`, `is_cycling` (`:449-465`) | — | A24 |
| `get_buffer_history`, `get_window_triquetra`, `get_all_triquetras`, `set_cache_from_window_triquetra` (`:467-473`) | — | A24 |
| `get_smart_basename` (`:472`) | — | A24: it's **nil**, because `ui/init.lua` never defines it **[run s16]**. bug (new) |
| `bufferline` (`:475`) and the domain tables `navigation`, `history`, `window`, `ui`, `storage`, `engine` (`:20-25`) | — | M12, A24 |
| user commands `:CavediverHistoryData`, `…NavigationData`, `…WindowData`, `…UIData`, `:CavediverTriquetra`, `:CavediverRegistry`, `:CavediverTriquetraVerbose`, `:CavediverAllTriquetras` (`init.lua:166-377`) | — | A23 |

The editor events: A1 (navigating to a tracked buffer), A2 (a window showing something untracked), A3 (entering a window), A4 (a new split), A5 (closing a window), A19 (any buffer delete), A20 (renames and writes), A21 (`cleanup_triquetras`), A22 (`cleanup_system`).

Most slot actions notify, and the messages are quoted where a test may want to check them. The silent ones are a successful `<M-f>` or `<M-S-f>` swap, the normal path of `jump_to_primary`, `toggle_primary` and `set_primary`. Most slot actions also end with a UI refresh (`loop_sm:to(SELF)`). `jump_to_primary` and the early returns of both swaps don't, and the UI catches up through the `BufEnter` that follows.

---

### A1. Navigating to a tracked buffer (`BufEnter`, history attached)

**Trigger.** `BufEnter` for buffer X in window W, whose triquetra is `{c=A s=S t=T}`. Once the editor settles, and only if W still shows X, the pipeline runs inside W (`nvim_win_call`), so W is the current window for every hook, whichever window has the focus (`history/hooks.lua:173-194`; T224, T250). An arrival queued before a session load is dropped when it settles: the restore's own events are noise the load replaces (`:176`, `:188-190`; S1). It's history `attached→attached`, mode update (M11):
1. track X (sets `history_modified`)
2. `ensure_curwin_crux`
3. `cleanup_triquetras` (A21)
4. `displacement_mangement`
5. UI refresh

**Today** (`window/hooks.lua:50-125`), when `history_modified` is true and X is registered:

| Case | After | Map writes |
|---|---|---|
| X = A | unchanged | none |
| X = S | `{c=X s=A t=T}` | the notes `<M-f>` writes, `dsm[A-swap] := S` and, with a ternary, `dtm[A-swap] := T` (D8, M7); Q6's guard before the swap |
| X = T | `{c=X s=S t=A}` | none |
| anything else | `{c=X s=S t=A}` | `dtm[A-swap] := nil` and `dtm[A] := T`, only when T exists |

Every case but X = A then runs the stale-note checks below.

- **"Duplicates detected in current triquetra".** When S and T are both set and equal, the hook throws this before any slot changes (`:87-93`). The error is caught (M11), so **the slots aren't updated at all** and the window shows X while `c` is still A **[run s18]**.
- **The stale-note check in navigation.** When `dtm[X] = A`, so that X's remembered ternary is the buffer being left, `dtm[X]` is rewritten to avoid a cycle, with a WARN (`:99-113`):
  - If T = X: `dtm[X] := dtm[A]`, "…switching with the pre-jump stored ternary."
  - Otherwise: `dtm[X] := T`, "…switching with the pre-jump ternary." **[run s18]**: at b with `t=d` and `dtm{a→b}`, `:e a` gives `{c=a t=b}`, `dtm{a→d, b→d}`.
- The map writes of the other cases happen only while navigation is `normal`. The slots move, and the route onto the secondary writes its notes, in any navigation state (`:86`, `:120-121`). In practice cycling detaches history, so this hook doesn't run while cycling.
- When the update returns false (an untracked buffer, or an "evolved" one, M3), the slots aren't touched. `ensure_curwin_crux` and `cleanup_triquetras` still run (A2, A21).
- Cleanup runs **before** this hook (class 1.8 against 2). When the buffer being left is a missing file, it stays registered and current until this hook moves it to the ternary as usual (M3, A21) **[inferred]**.
- **The secondary map's check.** On the X = T and last rows, once the slots move, X's plain secondary note, when it names the window's secondary, becomes X's swap note when that names another buffer, and is dropped otherwise (`keep_older_secondary_note`, `:122`; M7).
- **Going to the secondary** (`window/hooks.lua:71-82`) runs in `<M-f>`'s order: the notes (`write_secondary_swap_notes`, M7); Q6's guard, which rewrites `dtm[T]` to A when it names S, with the WARN "Avoided conflict of ternary's remembered relationship becoming current." (shorter than `reconcile_triquetra`'s, A13); the swap; then the ternary map's stale-note check, under which S's plain ternary note naming T, which stays put, becomes the ternary's own note `dtm[T]` (`keep_older_ternary_note`, `:82`; Q6, D8).

Examples **[run s01, s02]**:
- `{c=a}` `:e b` → `{c=b t=a}`.
- `:e c` → `{c=c t=b}`, `dtm{b→a}`.
- From `{c=d s=b t=c}`, `:e b` (the secondary) → `{c=b s=d t=c}`, with `<M-f>`'s notes `dsm{d-swap→b}` and `dtm{d-swap→c}` (T30); **[run s01]** recorded no dsm write, before D8's notes. The author's check of P14 gives the same slots.

**Label:** intended (README:347-349, README:353, SPEC:221-226, P14). Reaching the secondary by plain navigation writes the same notes as `<M-f>`, as README:355 says, "every time you jump to secondary" (D8).

**Decided:** the slotting happens at the end of the tick against the window's own buffer, never the focused one, and a later `buftype` change undoes the arrival (DESK:1788-1789). Built in step 3: the slotting once the editor settles, inside the event's window (`nvim_win_call`), skipped when the window shows something else by then (P2; T19, T224, T250), and the undo on `OptionSet` (I10, T217). Since arrivals are judged once the editor settles, with typeahead (a macro, a mapping that switches buffers several times, `:bufdo`) only what each window shows then is slotted and recorded: the buffers passed on the way are neither visited nor noted.

**Decided (2026-10-20):** going to the secondary by plain navigation is one of Q6's routes onto the secondary. The guard runs before the swap and rewrites `dtm[T]` to the buffer being left (A6). Built in step 3.

**Decided (2026-10-20):** going to the secondary by plain navigation records the same notes as `<M-f>`, so `<M-;><M-t>` works after either route (D8). Paired with T30 (T191). Built in step 3.

**Decided (2026-10-20 evening), "Keep the older one": plain navigation onto the secondary** runs in `<M-f>`'s order (A6):
1. the notes: `dsm[A-swap] := S` and, with a ternary, `dtm[A-swap] := T`. S's plain secondary note becomes S's swap note when that names a buffer other than A; otherwise a plain note naming A is cleared (M7).
2. Q6's guard.
3. the swap, `{c=S s=A t=T}`.
4. the stale-note check below: S's plain ternary note, when it names T, which stays put, becomes **the ternary's own note** `dtm[T]`.

Example, the round trip D8 asked to solve **[sim `rt_cand_round_e`, variant `rt_c3kga`; the same under `kt_rewrite_sec`]**: `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` give `⦉c⦊ [d] ⟦b⟧`; `:e b` gives `⦉c⦊ [b] ⟦d⟧` with `dsm{b>a d-swap>b}`; `:e d` gives `⦉c⦊ [d] ⟦b⟧` with `dsm{b-swap>d b>a d-swap>b}`; `<M-;><M-t>` on d says "No secondary relationship found" instead of throwing (T179).

Built in step 3.

**Decided (2026-10-20 evening), "Keep the older one": the stale-note check in navigation runs on every arrival.** Navigation's own check (`window/hooks.lua:99-113`) covers a buffer reached by plain navigation that isn't the secondary. Under the decision the same check runs whenever a buffer N becomes current, by any key, after the arrival's own writes. N's plain ternary note is checked against the ternary the window has after the arrival, and when it names it, it's rewritten:

| Arrival | Ternary after it | N's stale note becomes |
|---|---|---|
| plain navigation to a buffer that isn't the secondary | A, the buffer left | as today: `dtm[A]` when N was the ternary, otherwise T, the pre-jump ternary |
| `<M-S-f>`; a cycling pick of the ternary; a primary jump onto the ternary | A | `dtm[A]`, the left buffer's own note, as navigation's first case does (T186) |
| a primary jump onto any other buffer | A | T, the pre-jump ternary, as navigation's second case does (T187) |
| `<M-f>` and its `<M-;><M-f>` fallback; plain navigation onto the secondary; a cycling pick of the secondary or of an outside buffer | T, which stays put | `dtm[T]`, **the ternary's own note**. Navigation's second case would write T back, the stale value (the author: "Yes, the ternary's own note") (T185) |

- When the note it would copy doesn't exist, the stale note is dropped. In the walks, 42% of rewrites found nothing older **[sim, variant `kt_rewrite`]**.
- It runs after Q6's guard. Read before it, two buffers whose notes name each other would leave a note naming its own buffer **[inferred]**.
- Where the ternary's own note is the window's secondary, the next `<M-;><M-r>` exchanges the ternary and the secondary (5% of rewrites in the walks; T188).
- The secondary map gets the same check. The current buffer's plain secondary note, when it names the window's secondary, is rewritten to the buffer's swap note when that's set and names another buffer, and dropped otherwise (M7). In the walks a rewrite was possible 122 times in 497 and changed one restore in 3,000 walks **[sim, variant `kt_rewrite_sec`]** (T181–T183).
- In the tested fix, the secondary map's check also ran where the secondary changes under the current buffer, at graduation and at the ternary restore's exchange. At the secondary restore's exchange, the ternary map's check runs too: a stale ternary note becomes the ternary's own note, dropped when there's nothing older or it would name the current buffer (decided 2026-10-21; A11, T189, T206).
- Code the change touches, from the variants: `reconcile_triquetra` (`window/routines.lua:256-330`), `jump_to_primary` (`:926-930`), and plain navigation onto the secondary (`window/hooks.lua:71-82`). Navigation's own check stays as it is.
- Built in step 3: the check on every arrival, on both maps (`keep_older_ternary_note`, `keep_older_secondary_note`, `window/routines.lua:29-64`), and wherever a slot changes under the current buffer (`check_notes_under_current`, `:93-107`): after either restore's change, graduation, the history fill, a cleanup pass that moved a window's slots, and a session load.

### A2. A window switches to something untracked

Examples: `:terminal` in the window, help or quickfix opened into it, a `nofile` scratch.

**Today.** The window is visiting: it keeps its triquetra while it shows anything untracked. The getter never drops a triquetra (`window/data.lua:80-97`), and the shown buffer is never registered, so it never reaches a slot (M3, T26). The current slot stays the file the window was last on, and may be a closed buffer, which cleanup keeps while the window shows something unregistered (A21, T270). Coming back to the current slot finds the slots, the primary queue and the maps as they were (T27).
- A window born untracked (`:help`, `:copen`, `:split | terminal`) never gets a triquetra, and neither does a float: the getter only runs once the editor settles, when the window already shows what it was born with (M6, T225, T217).
- The winbar shows the visit in the current piece, `[N] a.txt ← [help]` (M12, T268).
- `<M-f>` and `<M-S-f>` take the window back to its current slot first, reopening a closed one (A6, A7, T269). `<M-.>` closes the visited buffer and lands on the current slot (A15, T164).
- A buffer that turns untracked after it arrived (a plugin's scratch set to `nofile`) has its arrival undone, and the window is visiting it from then on (I10, T217).
- Cleanup drops a visiting window's triquetra only when its current slot names nothing open or closed (A21).
- **[run s15]** recorded `{c=c s=b}`, `:terminal` → no triquetra, then `:e a` → `{c=a}`, before the visiting rule.

**Label:** intended (DESK:1785-1794). README:332 says the triquetra is kept and the winbar shows the visit (D26).

**Decided: the visiting rule** (DESK:51, DESK:1785-1794):
- A window that has a triquetra keeps it while it shows anything untracked. Its current slot stays the file it was last on, and may be a closed buffer.
- Windows born untracked (`:help`, `:copen`, `:split | terminal`) and floats never get a triquetra.
- The winbar shows the visit, e.g. `main.lua ← [help]`.
- `<M-f>` and `<M-S-f>` take you back to the current slot first.

Built in step 3.

### A3. Entering a window (`WinEnter`)

**Today.** Once the editor settles, and only while the focus is still on the window, a navigation self-transition with mode `winenter` (M11, `navigation/hooks.lua:99-117`). A `WinEnter` whose focus has moved on by then does nothing: the later `WinEnter` takes over. It:
1. records `jump[cur] := prev`, where prev is the `winnr('#')` window read at the event, or `last_valid_window` when there's none. It skips a prev showing filetype `minimap`, or one that's invalid.
2. sets `current_window := cur`.
3. runs `construct_crux(find_most_recent_tracked_window())`, which may create the window's triquetra (M6).
4. refreshes the UI.

While cycling, entering a window other than the cycling one also cancels the cycle once the editor settles (A12).

A `BufEnter` usually follows when the window shows a different buffer. A1 then runs for the entered window, and since its shown buffer is its current slot, the slots don't change.

`record_window_jump` reads the "from" window's buffer before checking that the window is valid (`navigation/routines.lua:46`, `:53`). **bug (desk)**

### A4. A new split (`:split`, `:vsplit`, `:new` showing a file)

**Today.**
- A split showing the same buffer fires no `BufEnter`.
- Once its `WinEnter` settles, the new window gets a fresh `{c=<that buffer>}` (M6). It isn't a copy of the old window's triquetra.
- Its history entry comes with the triquetra, empty until a visit happens in it (`window/data.lua:42`; I3, T18). **[run s07, s16]** recorded it with none.
- `save_session` then writes the window's empty history into its entry and goes through (T141). **[run s16]** recorded it failing on `next(nil)` without the entry.

**Label:** a minimal start is intended (SPEC:65-76), and so is the history entry that comes with it (I3).

### A5. Closing a window (`WinClosed`)

**Today:**
- The window's history entry is dropped (`history/hooks.lua:234-243`).
- Its triquetra is dropped (`window/data.lua:57-74`): the UI cache is cleared, `last_valid_window` is moved to the previous window in the jump chain whose buffer is registered, the history view is rebuilt for that window, and the winbar is cleared.
- Entries in the window-jump history that point at the closed window stay (M10). **[run s07]** shows the closed window's data gone.
- The popup's `WinClosed` handler runs `once` with no pattern, so the first window closed after `setup()` uses it up (`ui/hooks.lua:139-158`). **bug (desk)**

### A6. `toggle_secondary`, `<M-f>`

**Today** (`window/routines.lua:725-809`), in window W:

1. **No triquetra:** WARN "Window with unregistered buffer." Nothing else.
2. **W shows something other than its current slot**, while the current slot's buffer is open, or while W is visiting (it shows an unregistered buffer) with its current slot closed, which is then reopened (`window/routines.lua:733-737`, M5): switch W back to the current slot's buffer, INFO "Jumped back to windows current buffer.", stop. This is what happens while cycling **[run s04]**, and while visiting (A2, T269).
3. **The secondary is empty.** No buffer switch:
   - With a ternary T: `s := T`, `dsm[T] := dtm[T]`, `dsm[T-swap] := nil`, `t := nil`, then the check where a slot changes under the current buffer (A1). INFO "Secondary buffer set to ternary slot. Ternary slot graduated."
   - Otherwise, with at least 2 entries in the ordered history, it asserts that the first entry is the window's current buffer, and throws "This is impossible. The most recent buffer in the history must be the window's current buffer." when it isn't (`window/routines.lua:758-761`, D11). Then `s := hash(ordered[2])` and the same check. INFO "Secondary buffer populated from history." The assertion guards the routes where a stale history put the current buffer second and one buffer in two slots (DESK:2463); the window-jump cancel (A12) and the tie fix (D11) close them (T43, T176).
   - Otherwise: WARN "Cannot populate secondary slot - insufficent history."
4. **The secondary S is set:**
   - Write the swap notes (`write_secondary_swap_notes`, `window/routines.lua:72-85`): `dsm[A-swap] := S`; S's own swap note becomes its plain note `dsm[S]` when it names a buffer other than A, and otherwise a plain note `dsm[S]` naming A is cleared; and `dtm[A-swap] := T` when there's a ternary T (M7).
   - If S's buffer is closed, reopen it (M5).
     - On failure: WARN "Removed secondary file not found in filesystem: <name>", `s := nil`, stop.
     - On success: remove it from the closed stack and INFO "File reopened for secondary slot: …".
   - If S is a No Name hash, rename it everywhere (`rename_hash_in_triquetras`). The reopen has done that already, so this renames nothing (M5) **[code]**.
   - Then `reconcile_triquetra` runs Q6's guard, swaps A and S, `{c=S s=A t=T}`, and runs the stale-note checks (A13).
   - Then W switches to S. The following `BufEnter` finds `c` already S and does nothing.

Examples (the slots **[run s01]**; the notes T39's and T177's):

| Step | Before | After |
|---|---|---|
| graduation | `{c=c t=b}`, `dtm{b→a}` | `{c=c s=b}`, `dsm{b→a}`, still showing c |
| swap | `{c=c s=b}` | `{c=b s=c}`, `dsm{b→a, c-swap→b}`, showing b |
| swap back | `{c=b s=c}` | `{c=c s=b}`, `dsm{b→a, b-swap→c, c-swap→b}` |

**[run s01]** recorded the plain notes `dsm{c→b}` and `dsm{b→c, c→b}`, before "Keep the older one".

**Labels:**
- The graduation and the swap are intended (SPEC:80-112).
- The `dsm` write is intended (README:355).
- The `dtm[A-swap]` write is intended (Q2). SPEC:240, which says a swap creates no mapping, is out of date (D7).
- Copying `dtm[T]` into `dsm[T]` on graduation is intended (Q3). The author's reason: the graduated buffer's predecessor can then come back either as the ternary (`<M-;><M-r>`) or as the secondary (`<M-;><M-t>`).
- In the swap path, `reconcile_triquetra`'s "avoided conflict" guard runs before the swap (`window/routines.lua:287-296`), so when `dtm[T] = S` it rewrites `dtm[T]` to A, with its WARN (Q6). The conflict is real and the warning isn't spurious. **[run s18]** recorded the guard running after the swap, where its write was a no-op and only the WARN appeared. The author's repro, observed before the fix: `:e a`, `:e b`, `:e c`, `:e b`, `<M-f>`, `:e a`, `<M-f>`, `<M-f>` (the warning, no change), `<M-S-f>`, `<M-;><M-r>`, which throws (T150).

**Decided:** while visiting, `<M-f>` takes you back to the current slot first (DESK:1792). Step 2 does that. Built in step 3: the jump back reopens a closed current slot (A2).

**Decided (2026-10-20):** the guard runs **before** the swap on every route onto the secondary, so `dtm[T]` is rewritten to the buffer being left (Q6). The routes:
- `<M-f>` (this action)
- a cycling pick of the secondary (A13)
- `<M-;><M-f>` falling back to `<M-f>` (A8)
- plain navigation onto the secondary (`window/hooks.lua:69-82`, A1)

Setting `proc = true` in the secondary branch alone isn't the fix: it keeps the crash. The guard came in with commit ae209e42 (2025-06-12), inside `if not proc`; `proc` dates from d89061a3 (2025-06-11). Both predate this repository. The fall-through onto the secondary route wasn't deliberate. With the fix, the ten-key repro restores without throwing. Random walks with the fix still hit the ternary restore's throw 13 times in 1,500. Each of those lands on a buffer by an arrival that skips the stale-note check in navigation; "Keep the older one" closes them (A1, A11).

Built in step 3: the guard before the swap on all four routes (`window/routines.lua:287-296`, `window/hooks.lua:76-79`), with `proc` set in the secondary branch (`window/routines.lua:300`).

**Decided (2026-10-20 evening), "Keep the older one"** (M7):
- **Step 3, graduation,** also clears the graduated buffer's swap note `dsm[T-swap]`, so Q3's copy is what a later `<M-;><M-t>` finds (T184).
- **Step 4, the notes:** `dsm[A] := S` becomes the swap note `dsm[A-swap] := S`. S's plain note `dsm[S]` becomes S's own swap note when that names a buffer other than A; otherwise a plain note naming A is cleared. `dtm[A-swap] := T` stays.
- **The order on every route onto the secondary** (this key, its `<M-;><M-f>` fallback, plain navigation onto the secondary): the notes, then Q6's guard, then the swap, then the stale-note check, under which S's plain ternary note naming T, which stays put, becomes the ternary's own note `dtm[T]` (A1).
- The swap examples above then read `dsm{b→a, c-swap→b}` and `dsm{b→a, b-swap→c, c-swap→b}`, and `<M-;><M-t>` on c says "No secondary relationship found" instead of throwing **[sim `rt_sec_round`, variants `rt_c3kga` and `kt_rewrite_sec`]** (T177). One more `<M-f>` back to b, and `<M-;><M-t>` there brings back a, b's secondary from before the round trip (T178).
- Built in step 3.

### A7. `toggle_ternary`, `<M-S-f>`

**Today** (`window/routines.lua:817-874`), in window W with `{c=A s=S t=T}`:

1. **No triquetra:** WARN as in A6. **W not showing its current slot:** jump back, as in A6, reopening a closed current slot while visiting (`:825-829`).
2. **No ternary:** WARN "No ternary buffer to swap with.", stop.
3. **T's buffer is closed:** reopen it. On failure: WARN "Removed ternary file not found in filesystem: …", `t := nil`, stop.
4. Run `rename_hash_in_triquetras(T, hash of the opened buffer)`. That's a no-op: a reopened No Name T has its new hash everywhere already, this slot included (M5) **[code]**.
5. `reconcile_triquetra`: the secondary map's check on T, `dtm[A-swap] := T`, the swap, `{c=T s=S t=A}`, then the ternary map's check, under which T's plain note naming A becomes `dtm[A]`, or is dropped (A13). Switch W to T.

Example **[run s01]**: `{c=d s=b t=c}` → `{c=c s=b t=d}` with `dtm{d-swap→c}`. Again → `{c=d … t=c}`, adding `c-swap→d`.

- Step 4 has no guard for a nil old hash: if the ternary were cleared between steps 3 and 4, the rename would throw "attempt to concatenate local 'old_hash'" (`window/data.lua:149`). **bug (desk)** The desk's route to it, `:e 1.txt`, `:e 2.txt`, `<M-n>`, `:bdelete`, `<M-S-f>`, `<M-S-f>` (DESK:2469), goes through without a throw or a duplicate slot: the reopen's `BufEnter` is slotted only once the editor settles, so no cleanup runs between the reopen and the rename (T49). **[desk]** recorded that route throwing on the first press, and "Duplicates detected in triquetra slots" (`window/routines.lua:285`) on the second.

**Label:** the swap is intended (SPEC:114-135). The `-swap` write is intended (Q2).

**Decided (2026-10-20 evening), "Keep the older one":** after the swap, the stale-note check runs (A1). T's plain ternary note, when it names A, the new ternary, becomes A's own note `dtm[A]`, as navigation's first case does; when A has none, it's dropped (T186). The secondary map's check runs too (M7). Built in step 3.

### A8. `jump_to_primary`, `<M-;><M-f>`

**Today** (`window/routines.lua:880-939`), in window W with `{c=A s=S t=T p=[P,…]}`:

1. **No triquetra:** WARN "Window with unregistered buffer."
2. **Cycling.** Switch W to the cycle's starting buffer, set `c := origin` (already true, M9), INFO "Returned to cycling origin buffer: <name>". **Navigation stays `cycling`.** **[run s04]**
3. **Fall back to A6** when the queue is empty, **or `primary_enabled` is false**, or S = P **[run s02]**.
4. **P's buffer is closed:** reopen it.
   - A reopened No Name P comes back under a new hash, which the reopen writes wherever the old one was, every window's queue included (M5). The jump then writes it into `p[1]` again, in W only **[code]**.
   - On failure it **throws** `Primary buffer not found in filesystem: <path>`. That's a raw `error()`, so it reaches the user as an E5108.
5. **A ≠ P:** `dtm[A-swap] := T` (nil when there's no ternary), `t := A`, `c := P`, then the stale-note checks: the secondary map's on P, and the ternary map's, under which P's plain note naming A becomes T, or `dtm[A]` when P was the ternary (`window/routines.lua:931-932`). Otherwise INFO "Already in primary buffer, no displacement performed.", and nothing changes.
6. Then reconcile (a no-op here) and switch W to P.

Examples **[run s02]**:
- `{c=e s=d t=b p=[b]on}` → `{c=b s=d t=e}`, `dtm{e-swap→b}`. When P was the ternary, this is the same as `<M-S-f>`.
- On P already: nothing changes.
- `p=[b]off`: it acted as `<M-f>` and graduated the ternary.

**Labels:**
- Bringing P to current with A moving to the ternary is intended (SPEC:137-157, README:360).
- Falling back when the queue is empty is intended (SPEC:143).
- Falling back when the primary is **disabled** is intended (Q10). README:31, which says the key does nothing then, changes (D5).
- The cycling branch is intended (SPEC:206-209).
- That the branch doesn't leave cycling is intended (Q7): there's no cancel key, and `<M-v>` picks the start (A14).
- The fallback to `<M-f>` is one of Q6's routes onto the secondary, so it gets A6's decided guard.

**Decided (2026-10-20 evening), "Keep the older one":** after the shift in step 5, the stale-note check runs (A1). P's plain ternary note, when it names A, the new ternary, becomes T, the pre-jump ternary, as navigation's second case does; when P was the ternary, it becomes `dtm[A]` instead (T187). The secondary map's check runs too (M7). The fallback to `<M-f>` follows A6. Built in step 3.

### A9. `toggle_primary`, `<M-;><M-x>`

**Today** (`window/routines.lua:945-961`):
- Empty queue: `p := [A]` and `primary_enabled := true`, whatever the switch said (Q14).
- Otherwise: `primary_enabled := not primary_enabled`.
- Then a UI refresh and `redraw!`.

So:
- the first press on an empty queue makes the current buffer the primary and enables it, even when the empty queue was switched on
- later presses only toggle enabled, whatever buffer you're on
- the queue never changes after that

**[run s02]**: `p=[]off` → `p=[b]on` → `p=[b]off`.

**Label:** intended (Q8). `<M-;><M-x>` is the primary's on/off switch, and seeds the queue only when it's empty. `<M-;><M-c>` (A10) is the key that makes the current buffer the primary.

**Decided (2026-10-20):** only the keymap description changes. "Toggle current buffer as primary" (`init.lua:105`) doesn't describe an on/off switch. The README has the two keys swapped, which is a bug in the README (D1).

**Decided (2026-10-20):** on an empty queue, the key queues the current buffer and switches the primary **on**, whatever the switch said (Q14). **[run s19]** recorded the key flipping the switch after queueing, so a queue that emptied while on ended up `p=[A]off` and needed a second press. The state isn't changed: an empty queue may stay switched on (I19). Built in step 3 (T157).

### A10. `set_primary`, `<M-;><M-c>`

**Today** (`window/routines.lua:967-989`):

| Queue state | Effect |
|---|---|
| empty | `p := [A]`, enabled |
| `p[1] ≠ A` | remove A from the queue if it's there, put A at the front, enable |
| `p[1] = A` | toggle enabled |

Then a UI refresh and `redraw!`.

**[run s02]**:
- `p=[b]off`, on b → `p=[b]on`.
- On e → `p=[e,b]on`.
- Again on e → `p=[e,b]off`.

**Label:** intended (README:22, Q8).

### A11. Restoring from the displacement maps: `restore_ternary` `<M-;><M-r>`, `restore_secondary` `<M-;><M-t>`

**Today** (`window/routines.lua:995-1091`). The type is ternary or secondary, the slot `cur` is that type's slot, and the map is dtm or dsm. In window W with current A:

1. Look up `remembered := map[A-swap]`. If that's nil, equals `cur`, the occupant of the slot being restored into, or is a closed buffer whose file is missing from disk, use `map[A]` instead (`:1015-1023`). Before that, a note at a hash with no path, `map[A-swap]` or `map[A]`, is cleared, so it reads as nil (`:999-1004`, D9).
2. Then:

| Condition | Effect |
|---|---|
| nil | WARN "No <type> relationship found for restoration. …" |
| a closed buffer (no open buffer, not a No Name) whose file is missing from disk | WARN "Remembered <type> isn't on disk right now: <name>. Nothing changed.", and nothing changes: both notes stay (D9) |
| equals `cur` | **throws** "This is impossible. Remembered <type> is the same as current <type>. …" |
| ternary type, equals the secondary | `s := t`, `t := remembered` |
| ternary type, otherwise | `t := remembered` |
| secondary type, equals the ternary | `t := s`, `s := remembered` |
| secondary type, otherwise | `s := remembered` |

3. In the last four rows, `map[A] := cur` afterwards. A nil `cur` deletes the entry. INFO "Restored <type> slot to: <hash> (<name>)"; when the restored buffer is open but its file isn't on disk, the same line at WARN with ", not on disk right now" added (D9). Then the check where a slot changes under the current buffer runs (`check_notes_under_current`, `:1065`, A1).
4. No buffer is switched, and closed hashes aren't reopened.

The flip-flop **[run s02]**:
- At b with `{c=b t=d}` and `dtm{b→a}`, restore → `t=a`, `dtm{b→d}`.
- Restore again → `t=d`, `dtm{b→a}`.

**[run s02]** also shows the swap record winning:
- From `{c=e … t=b}` jump to primary b: `dtm{e-swap→b}`.
- `<M-S-f>` back to e.
- Restore at e finds `e-swap→b`, the current ternary, so it falls back to `dtm[e]`, which is nil: "No ternary relationship found".

**Labels:**
- The flip-flop is intended (SPEC:159-186, SPEC:249-273, README:349, README:355).
- The `-swap` preference is intended (Q2): the author confirmed it and said they'd forgotten why. Both alternatives were then tried on scratch variants, by the session, not the author:
  - If swaps wrote plain notes, toggling with `<M-S-f>` would overwrite the note with the toggle partner, and the next restore would throw "Remembered ternary is the same as current ternary".
  - If swaps wrote nothing, a restore after a primary jump and back would give an older buffer instead of the one you had right before the jump.
- Throwing when the remembered value equals the slot is intended: the assertion stays (Q13). SPEC:176's message, "No different ternary relationship to restore", is out of date (D9). Every route that still reaches the throw is a bug, to be hunted with tests (T154). Q6's fix closes one route (A6). The 13 ternary throws left in 1,500 walks after it were traced: each landed on a buffer by an arrival that skipped the stale-note check in navigation. **[run, sim; the round-trip research's walks]** recorded the secondary restore throwing far more often before "Keep the older one": 161 times in 1,500 walks, 204 with D8's notes as plain notes, mostly after a round trip onto the secondary and back. With "Keep the older one" built, T154, T190 and T335 find no throw.

**Decided (2026-10-20 evening), "Keep the older one".** One rule lies behind every throw found: a buffer becomes current while its note names the buffer already in the slot that note restores into (I23). The fix is the stale-note check on every arrival, on both maps (A1, M7), plus these changes to the restore itself:
- **The swap-note fallback** (step 1) compares with the slot being restored into, not with the ternary for both: `dtm[A-swap]` against the ternary, as today, and `dsm[A-swap]` against the secondary (`window/routines.lua:1017-1023`). So after a round trip onto the secondary and back, A's swap note equals the secondary and the restore falls back to A's plain note, A's secondary from before (T180).
- **The ternary restore's exchange** (the row "ternary type, equals the secondary") is followed by the secondary map's check: the current buffer's secondary note, when it names the new secondary, is rewritten to its swap note or dropped **[sim `kt_tosec`, variant `kt_rewrite`]** (I23, T190).
- **The secondary restore's exchange** (the row "secondary type, equals the ternary") got no check in the first tested fix: when the current buffer's ternary note named the old secondary, which the exchange had just moved into the ternary, the next `<M-;><M-r>` threw **[sim, variant `kt_rewrite_sec`]**. **Decided (2026-10-21):** the check runs there too, and the stale note becomes the ternary's own note, dropped when there's nothing older or it would name the current buffer **[sim, variants `ex_a`, `all_fixed`]** (T189, T206).
- Over two sets of 1,500 walks: 0 ternary and 0 secondary throws, no duplicate slot, no other error **[sim, variant `kt_rewrite_sec`]**. Zero in the walks is evidence, not proof; T154 and T190 keep hunting.
- Built in step 3: the fallback (`window/routines.lua:1017-1023`), and the check after every restore, exchanges included (`:1065`).

**Decided (2026-10-20 evening): a remembered file that's missing** (D9), for both restores and both maps, swap keys included:
- missing from disk with no buffer: skipped and kept. A skipped swap note falls back to the plain note; when that's missing and closed too, the restore says so and changes nothing (T67, T174, T193).
- missing from disk with its buffer open: the restore goes through and flip-flops with it, saying the file isn't on disk (T173).
- a hash with no path: the note is cleared when used, with no throw (T68).
- Built in step 3 (`window/routines.lua:999-1062`).

### A12. Cycling: `cycle_left` `<M-n>`, `cycle_right` `<M-m>`

**Today** (`navigation/init.lua:52-68`, `navigation/hooks.lua:22-32`, `navigation/routines.lua:11-43`):

**From `normal`**, navigation goes to `cycling` with `{direction, window = {current_crux = W}}`:
1. History goes `attached→detached`.
2. `cycling_origins[W]` becomes the live triquetra, with `c` set to the shown buffer, and a notify "Checkpoint saved: <current> -> <secondary or Unfilled>" (no level).
3. `cycling_window := W` (M9).
4. One step: `cokeline.mappings.by_step("focus", -1)` for left, `+1` for right.

**From `cycling`**, it's one more step.

What a step does and doesn't do:
- It's skipped when there are 1 or fewer buffers in the ordered history. The mode change still happens.
- When cokeline is missing, it steps through cavediver's own ordered history (`history.get_ordered_buffers()`, the order the bufferline would show, which follows `history_view`) in the same directions, wrapping around at either end (`navigation/routines.lua:16-34`, T171).
- While cycling, `BufEnter` neither tracks history nor touches slots. **The current slot stays the starting buffer** **[run s03]**.
- The history order stays frozen.
- The bufferline background uses the detached colours, and the winbar's current name loses its highlight.

**A jump to another window** (`cancel_cycle_on_window_jump`, `navigation/hooks.lua:45-76`). A `WinEnter` into any window other than the cycling one, floats included, cancels the cycle once the editor settles (`vim.schedule`), unless a pick or another cancel got there first:
- The cycling window goes back to its start, its current slot read live (D15). That switch fires a `BufEnter` while history is still detached, and its arrival is dropped when it settles, since the cancel has attached history by then: nothing is recorded for it (`history/hooks.lua:175`, `:185-187`).
- Navigation goes to `normal` with no mode, so no hook runs and nothing is picked.
- History attaches with the buffer of the jumped-to window's current slot, so no slot moves and that buffer is recorded as an ordinary visit, even when Neovim fired no `BufEnter` there. When the window shows another buffer, an ordinary update for it follows, `attached→attached`, which acts as plain navigation: the old current goes into the ternary (A1; T175, T198, T229). Nothing is recorded for the cycle's steps.

Which way left and right move depends on cokeline's buffer order: `compare_buffers` puts the newest on the left, so `-1` moves toward newer buffers. The runs here used a stub that steps through cavediver's ordered list, not real cokeline, but the author confirms the direction (Q19): `<M-n>` steps left, toward newer buffers, and `<M-m>` steps right, toward older ones.

**Label:** intended (README:382-384, Q1, Q19). SPEC:194 and SPEC:393, which have the current slot follow the cycle, are out of date (D10).

**Decided (2026-10-20):** only when cokeline is missing, a step goes through cavediver's own ordered history instead (the order the bufferline would show), so `<M-n>`/`<M-m>` still cycle. With cokeline installed nothing changes: cycling stays on cokeline and cokeline stays required. DESK.md:2126 ("Cycling stays on it") and the Dropped line at DESK.md:3146 get narrowed to say so at the next desk sync. **[run s21]** recorded the step only printing, before the fallback (T171, T248). Built in step 3.

**Decided (2026-10-20 evening):** jumping to another window ends the cycle by **cancelling** it: the cycling window returns to its start and nothing is recorded (P18; Q7, picking stays `<M-v>`'s job). Any `WinEnter` into another window counts, floats included (the primary pop-up, a picker's prompt, `:help`). It acts on the cycling window, after the editor settles. The author: "I guess we have to quit cycling mode when we jump windows." **[run `t/b7_jump.lua`]** recorded a cycle leaking across windows before the cancel: work in the other window wasn't recorded and didn't move its slots, and `<M-v>` pressed there "picked" in that window, dropping its current buffer (T175). Built in step 3, on `vim.schedule`, with the start read live from the cycling window's current slot (D15).

**Decided (2026-10-21):** landing in the window you jumped to counts as an ordinary visit and records its buffer, even when Neovim fires no `BufEnter` (the window already shows that buffer). The cancel records nothing for the cycle's steps only. The author: "Yes, record the landing". Without it, `:e a`, `:vsplit`, `:e c`, `<M-m>`, `<C-w>p`, `<M-f>` trips the fill assertion under both views (35-52 per 1,500 multi-window walks; 0-3 with the landing recorded, all from the window-view tie bug in D11) **[sim, 2026-10-21]** (T198). Built in step 3: the cancel attaches history on the jumped-to window's current slot, then records what the window shows by plain navigation when that's another buffer.

### A13. `cycle_select`, `<M-v>`

**Today** (`navigation/init.lua:70-76`, `navigation/hooks.lua:34-40`, `window/routines.lua:256-330`).

**From `cycling`**, navigation goes to `normal`, and history `detached→attached` with `{buf = X, pick = true}`, where X is the shown buffer:
1. X is tracked; the order is now live again.
2. `cleanup_triquetras` runs.
3. `reconcile_triquetra(current window, X, pick)` runs, with `{c=A s=S t=T}`, where A is the cycle's start:

| Case | After | Map writes |
|---|---|---|
| X = A | unchanged | none |
| X = T | `{c=T s=S t=A}` | `dtm[A-swap] := T` |
| X = S | `{c=S s=A t=T}` | Q6's guard, before the swap: if `dtm[T] = S`, then `dtm[T] := A`, with WARN "Avoided conflict of ternary's remembered relationship becoming current. …" |
| X outside the triquetra | `{c=X s=S t=T}`: **A leaves the triquetra and the ternary stays** | if `dtm[T] = X`, then `dtm[T] := A`, with the same WARN; on a pick, Q9's note `dtm[X] := A`, and `dtm[X-swap]` is deleted (`window/routines.lua:316-319`) |
| X = T and X = S together | "Duplicates detected in triquetra slots" |

Every case but X = A also runs the stale-note checks: the secondary map's on X before the slots move, and the ternary map's after (`window/routines.lua:270-274`, `:321-327`; A1). Q9's note is written only on a pick, with `pick = true` from `stop_cycling`; the window-jump cancel reaches `reconcile_triquetra` too, with no pick (A12).

4. The UI refreshes.

Examples **[run s03, s04]**:
- `{c=e s=c t=d}`, cycle to b, `<M-v>` → `{c=b s=c t=d}`, with Q9's note `dtm{b→e}` (T155).
- Cycle to c (the secondary), `<M-v>` → `{c=c s=b t=d}`.
- Cycle to d (the ternary), `<M-v>` → `{c=d s=c t=e}`, `dtm{e-swap→d}`.

**From `normal`**, `<M-v>` is `normal→normal` with mode `cycle`. No hook matches, so nothing happens **[run s04]**.

**Labels:**
- The ternary not being updated by a pick is intended (README:347, Q9).
- When X is outside the triquetra, A, the cycle's start, is remembered on X: decided (2026-10-20) (Q9).
- In the X = S case, the "avoided conflict" guard runs before the swap, as on `<M-f>` (Q6, A6).
- SPEC:385-407, which has slot changes during cycling persist with no displacement, is out of date (D10).

**Decided (2026-10-20):**
- A pick of a buffer outside the slots also writes a note on the picked buffer, `dtm[X] := A`, so `<M-;><M-r>` on X brings the start back. The ternary itself stays unchanged, so README:347 holds (Q9, T155).
- The same pick clears the picked buffer's older swap note `dtm[X-swap]`, which would otherwise win the restore and lose the start (the author, 2026-10-20 evening: "Yes, delete it") (Q9, T172).
- A pick of the secondary is one of Q6's routes onto the secondary: the guard runs before the swap and rewrites `dtm[T]` to A (A6).
- Built in step 3.

**Decided (2026-10-20 evening), "Keep the older one":** after a pick, the stale-note check runs as on every arrival (A1). A pick of the ternary rewrites the picked buffer's stale note to `dtm[A]`; a pick of the secondary or of an outside buffer, to the ternary's own note `dtm[T]`. Under Q9's note, an outside buffer's plain note names the start, which is never the ternary, so the check finds nothing stale there. The secondary map's check runs too (M7). A pick writes no secondary notes, as today: D8 named plain navigation and the bufferline, not picks. Built in step 3.

### A14. Cancelling a cycle

**Today:** there's no cancel key. A jump to another window cancels the cycle (A12). Within the window, the closest path:
1. `<M-;><M-f>` while cycling switches back to the starting buffer and stays in `cycling` (A8 step 2).
2. Then `<M-v>` selects it. That's case X = A in A13, which leaves the slots unchanged.

`<M-f>` and `<M-S-f>` while cycling, when the window isn't showing its current slot, also switch back to the start and stay in `cycling` (A6 step 2) **[run s04]**.

When the window already shows the current slot, `<M-S-f>` **does a real ternary swap while still cycling**, `-swap` write included: `{c=c s=b t=d}` → `{c=d s=b t=c}` **[run s04]**.

**Label:** intended (Q7). There's no cancel key: `<M-f>` returns to the start, then `<M-v>` picks it. For the slot keys while cycling, the author pointed to the code ("bro, just take a look, I already dealt with that.", 2026-10-20 15:37), so today's behaviour is the intended one:
- `<M-f>` and `<M-S-f>`, when the window isn't showing its current slot, jump back to it; when it is, they do their normal job.
- `<M-;><M-f>` while cycling always returns to the cycle's start (A8 step 2), whether or not the window is already on it.

SPEC:197-205, which has the slot keys act on the cycled-to buffer, is out of date (D10). SPEC:206-213 describes `<M-;><M-f>` as "return to checkpoint", not as a cancel, which fits.

`<M-;><M-f>` while cycling with the window already on the start announces the origin again and changes nothing (A8 step 2). That's the code's behaviour, which Q7's answer keeps. Confirmed by the author (2026-10-20, late evening), after being recorded from a reading of their words.

**Decided (2026-10-20 evening):** jumping to another window cancels the cycle: the cycling window goes back to its start, and nothing is recorded (A12, T175). There's still no cancel key. Built in step 3.

### A15. Closing a buffer, `<M-.>` (`close_buffer`)

**Today** (`history/routines.lua:711-815`), on the buffer B shown in window W.

**A buffer cavediver doesn't track** (help, quickfix, a terminal, a plugin's scratch, an `acwrite` buffer such as oil's) is closed as it is, before any of the steps below (`:714-735`, Q17):
- A terminal whose job is still running is refused with WARN "Terminal job is still running", and nothing changes.
- A modified buffer whose `buftype` is `acwrite` or `""`, oil's with pending edits for one, is refused with WARN "Buffer has unsaved changes", as a file is in step 1, and nothing changes (`:720-724`, I12).
- A window with a triquetra, which is visiting the buffer, goes back to its current slot first, reopening it when it's closed (`:727-732`, T164).
- Then the buffer is deleted with `nvim_buf_delete(…, { force = true })`. Neovim closes a window born on it when other windows exist, and picks what an only window shows (T84, T165–T167).

For a tracked buffer:

1. **Refusals**, each with a WARN and no change:
   - B has a name and is modified: "Buffer has unsaved changes". A modified No Name buffer goes through.
   - B is shown in another window: "Can't delete buffer because it's shown in another window."
   - The history view has 1 entry or fewer: "Can't delete buffer because it's the only one left".
2. **Picking where W goes.** Find B's index i in `ordered.crux`, with n entries:
   - If B isn't in it, it **throws** "This is impossible: Current buffer not found in ordered history." at `history/routines.lua:789`. Untracked buffers, where the author saw it (`:help`, a `:terminal`; DESK:2465), are closed before the steps, so they don't get here.
   - `i = 1` with `n ≥ 2` → `ordered[2]`.
   - `i > 1` → `ordered[(i % n) + 1]`, which is the next older entry, wrapping to the newest after the oldest.
3. **Closing.** Keep W's cursor on B (`vim.b[B].cavediver_cursor`, for a No Name buffer's cache, T83), switch W to that buffer, then, once the editor settles, delete B: `:bdelete` for a file, so Neovim keeps its marks, and `bw!` for a No Name buffer, whose text is cached (`:793-811`, T85). The switch's arrival is queued first, so it settles first and A1 moves W's slots before the delete; the delete's cleanup then finds nothing to heal and says nothing (P2, T336). Its `BufDelete` runs A19, which pushes B on the closed stack and caches its text if it's a No Name buffer. The delete is dropped when a session loaded in between (`:801-805`, S1).

**[run s05]**:
- At f with order `f,e,d,b,a`: lands on e, `{c=e t=f}`, closed `[c,f]`.
- At e with order `e,f,…`: lands on f.
- In both, the closed buffer stays in the ternary, where `<M-S-f>` reopens it.

**Labels:**
- The landing rule is intended: the code is right and the comment at `:785`, "go to most recent (first in list)", is wrong (DESK:2167, DESK:2478). **bug (desk, comment)**
- `:bdelete` for files and `bw!` for No Name buffers is the decided split (below).

**Decided:**
- `:bdelete` for files, so Neovim keeps the buffer's marks. No Name scratches may still be wiped (DESK:2168).
- The close key keeps its own landing rule (DESK:2167).
- The keymap descriptions for `close_buffer` and `open_primary_buffer_history` both read "Toggle current buffer as primary" (`init.lua:111`, `:117`) (D3).

Built in step 3: the first point (T85).

**Decided (2026-10-20): `<M-.>` on an untracked buffer** (Q17):
- **A window with a triquetra that's visiting something untracked** closes the visited buffer and lands on its current slot (A2).
- **A window born untracked** (no triquetra, such as a `:help`, `:copen` or terminal split) closes the buffer. Neovim closes that window when other windows exist; when it's the only window, Neovim picks what it shows.
- **A terminal whose job is still running** is refused with a message, as an unsaved file is (step 1).
- Built in step 3 (`history/routines.lua:714-735`): all three (T84, T164–T167). A visiting window goes back to its current slot before the close, reopening a closed one.

### A16. `reopen_last_closed`, `<M-S-w>`

**Today** (`history/routines.lua:697-708`):
- With an empty closed stack: WARN "No closed buffers to reopen."
- Otherwise:
  1. Pop the newest hash and `reopen_filehash` it (M5).
  2. On success, switch the current window to it (A1 runs, so the buffer becomes current and the old current moves to the ternary).
  3. When the file is missing, the hash is gone from the stack and **nothing is reported** (DESK:2454). **bug (desk)**
- A reopened No Name buffer comes back under a fresh id, and every slot, primary queue entry, note and history entry that held its old hash holds the new one (M5, T91). Its cursor goes back in the window that shows it (T90).

**[run s05]**: closed `[c,f]`, at e → shows f, `{c=f t=e}`, closed `[c]`.

**Decided:** a missing file says so when it's used, and its pointer is kept (DESK:2022). A reopened No Name buffer gets a fresh id, and everything that pointed at its old hash is renamed (DESK:2299). Built in step 4: the fresh id and the rename (T90, T91). A missing file saying so isn't built (T89).

### A17. `toggle_window`, `<M-,>`

**Today** (`navigation/routines.lua:58-73`):
- prev = `jump[current]`.
- If it's valid and not a minimap: record `jump[prev] := current`, then go to prev.
- Otherwise: WARN "No valid previous window to toggle to."

**[run s07]**: it toggles between two splits.

**Label:** intended (README:311). **Decided:** the minimap skip becomes a configurable list, defaulting to `minimap` and `neominimap` (DESK:2156).

### A18. Primary queue window, `<M-;>F` (`open_primary_buffer_history`)

**Today** (`ui/routines.lua:21-137`, `ui/hooks.lua:86-136`, `window/routines.lua:183-239`).

**Opening:**
- With no triquetra: INFO "No triquetra found for current window." With an empty queue: INFO "No primary buffer history available." In both cases there's nothing to edit, so the first entry can't be typed in from here.
- Otherwise:
  - A centred float opens. It holds a **listed** `acwrite` buffer named `cavediver://primary-buffer-queue-history`, with filetype `cavediver-primary-buffer-history`.
  - It lists one line per queue entry. Each line is the entry's display name, or `NONAME_<id>` for a No Name entry.
  - The size comes from `primary_buffer_history_popup`.

**Keys in the float:**

| Key | Effect |
|---|---|
| `:w`, `<C-s>` | `BufWriteCmd` (below) |
| `q`, `<C-c>` | `write!`, then close the float, then delete the buffer 100 ms later. They **save**, which is intended (Q12); their description, "Close without saving", is what's wrong (D12). |
| `<CR>` | move the line under the cursor to the top, then the same as `q` (so it saves) |

**Saving** (`BufWriteCmd`, only when the buffer is modified):
- Blank lines are dropped.
- Each line is trimmed and mapped back from display name to path, or kept as typed.
- Then `update_primary_buffer(lines, W)`, which checks each path:
  - Blank: skipped.
  - Missing on disk, and not `NONAME_`: rejected, "File does not exist".
  - Loaded but untracked: rejected.
  - Not loaded and unregistered: a `NONAME_` name is rejected. Otherwise the path is registered **and pushed onto the closed stack** (`:216`).
  - Errors are collected into one ERROR notification, and **the valid lines are saved anyway**.
  - `primary_enabled := #valid > 0`, so saving **re-enables a disabled primary** (D5). The queue becomes the hashes of the valid paths.
  - A relative path that's loaded under its absolute name gives `nil` there, so the queue gets a hole (DESK:2477). **bug (desk)**

**Labels:**
- Editing, reordering, deleting and promoting with `<CR>` are intended (README:21-32).
- The partial save is intended (Q11): the good lines are saved and the bad ones reported. README:28, which says nothing is saved, changes (D6).
- Re-enabling the primary on every save is decided (2026-10-20) to change (Q10).

**Decided (2026-10-20):**
- **The on/off state** (Q10). A save switches the primary on only when the first row changed in the new queue. Otherwise the queue is saved and the on/off state stays as it was.
- **`q` and `<C-c>`** keep saving and then closing. Their description changes from "Close without saving" to "Save and close" (Q12).
- **A file picker** (Q11), a new feature:
  - `<M-e>` in normal mode, mapped in that buffer only and configurable, opens a file picker through a provider.
  - The default provider is telescope's `find_files` with multi-select, when telescope is installed.
  - The selected file or files go on the cursor's line if it's empty, otherwise after it. Then `:w` validates them as usual.
  - With no picker, `<M-e>` gives a message.

### A19. Any buffer delete (`BufDelete`, or a rename that settles as a copy)

**Today**, the history self-transition with mode delete. It runs on `BufDelete`, and on a renamed buffer's old name when the rename settles as a copy (A20):

1. **`handle_deletion`**, when the buffer is registered:
   - `track_closing_filehash`: push it on the closed stack. A No Name buffer with text has its lines, filetype and cursor cached. An empty No Name buffer is untracked and taken out of every secondary, ternary and primary queue, has its path forgotten unless a current slot or a note still references it (M2, M5), and isn't pushed.
   - untrack it, then unregister the buffer. The path stays.
2. **When history is attached:** the ordered lists are rebuilt.
3. **`cleanup_triquetras(buf)`** runs (A21). A window whose current slot was the buffer being deleted, and that still shows it, is left to land once the delete is over (below).

**The landing** (`land_after_delete`, `window/routines.lua:341-420`). It acts once the delete is over (`vim.schedule`), in that window, whichever window has the focus:
- It lands on the first open one of the ternary, the secondary, `primary[1]`, and the open buffers in the bufferline's order (`history.get_ordered_buffers()`, which follows `history_view`), never the buffer being deleted (`:365-394`). That buffer becomes the current slot, and the ternary or secondary it came from is emptied, as healing does; the primary queue stays (T111, T271). Then the check where a slot changes under the current buffer runs, before the window is switched (`:396-398`, A1, I23).
- With nothing to land on, a window showing Neovim's empty buffer keeps it, and it's recorded as the visit (T237). Anything else Neovim showed is replaced by a new empty buffer, made with `nvim_create_buf(true, false)`, since `:enew` would reuse an empty scratch (`:400-418`).
- It does nothing when the window closed or lost its triquetra, when the buffer is still listed and shown (a rename, A20), or when the window moved on since Neovim's pick (`:348-363`).
- Neovim's own pick, the first `BufEnter` in that window once the deleted buffer is unlisted, isn't recorded as a visit: the `BufEnter` hook asks `is_landing_pick` first, at the event (`:428-439`, `history/hooks.lua:169-172`). `window.data.landing` holds, per window, the buffer being deleted and that pick (`window/data.lua:22-25`).

Closing a buffer that a slot holds:

| Slot | Effect | Evidence |
|---|---|---|
| ternary | it **stays**, as a closed hash | **[run s06]** |
| primary entry or secondary | it **stays**, as a closed hash, like the ternary: each check reads its own slot or entry (`window/routines.lua:621`, `:677`) | T103, T104. On the wrong-slot check (D13), **[run s05]**: `:bdelete c` with `{c=e s=c t=d}` → `s=-` at once. **[run s06]**: secondary and primary kept while the ternary was closed, pruned as soon as the ternary was reopened. |

**Label:** intended: a closed slot reopens when used (README:15, I4). A closed slot whose file is gone from disk is pruned (A21, P9).

**Decided:** a deleted buffer's window is landed after the delete, in that window, in the order ternary → secondary → primary → most recent, with no extra wipe. When nothing in that order exists, the window keeps Neovim's empty buffer, and `:enew` runs only when Neovim showed something else (DESK:1931). Plain Neovim usually lands the same way (DESK:3252). `<M-.>` keeps its own rule (A15). Built in step 1.

### A20. Renames and writes

**`:saveas`, `:file`, LSP or oil renames.** `BufFilePre` only records a registered buffer's old hash (`history/hooks.lua:199-212`). The old name stays registered to the buffer until the rename settles, so nothing prunes what a move carries over. `BufFilePost` settles it once the editor settles (`:215-231`, `settle_rename` at `:86-107`, `history/routines.lua:594-625`), and the disk decides:
- **A copy:** the old name is still a file (`:saveas`, or `:file` from a file on disk). The old name is closed as a delete closes it, through the delete transition (A19): it goes on the closed stack, untracked and unregistered, and slots elsewhere keep it and reopen it when used (T272).
- **A move:** the old name isn't a file, or never was (a No Name buffer), and the new name is trackable (M3). The buffer's registration, every slot, primary queue entry and note (`rename_hash_in_triquetras`) and its history (`rename_hash_in_history`, M4) follow to the new hash, and every copy of the old hash leaves the closed stack, with its No Name text (T107).
- A new name that isn't trackable, such as a `://` name, is closed like a copy, whatever the disk says **[code]**.

Then the buffer is registered under its new name, whatever the history state, and when a window shows it, it's taken in as an arrival in that window (`history/hooks.lua:95-103`, A1). On a copy, cleanup then re-points the window's current slot to it (A21). After a move, the old path is forgotten once nothing references it (`:104-106`, M2).
- The window keeps showing the renamed buffer, edits included (T106, on the route of DESK:2442-2444): A19's landing finds it still listed and shown and leaves it (`window/routines.lua:352-359`). A new name that isn't on disk yet (`:file new`) is registered when the rename settles (`history/hooks.lua:95-97`, M3), and A21 doesn't check the current slot's file on disk, so it stays tracked, and its window stays open (T284).
- `:saveas` fires the rename events on the extra buffer it makes for the old name too (listed, unloaded). That buffer isn't registered, so `BufFilePre` records nothing for it, and it stays unregistered until it's entered, like a `:badd` buffer **[code]**. While a rename is in progress, the old name stays registered to the buffer, so cleanup has nothing to heal **[inferred]**.

**`:w name` on a No Name buffer.** Neovim deletes the buffer and makes the same buffer number again under the name. `BufDelete` of a registered No Name buffer notes it with its history, which the delete then untracks (`history/hooks.lua:125-134`), and the delete runs as any delete does (A19). `BufWritePost` claims the note at the event and settles it as a move once the write settles (`:143-150`): the old `NONAME_` name never was a file. Its history comes back under the new name and its notes follow, with no ghost left on the closed stack (T238). A note no write claims is dropped once the batch settles, so `:e` reusing an empty unnamed buffer stays plain navigation. An empty No Name buffer's delete may have forgotten its path already (M5); its write then settles as neither a copy nor a move, and the buffer is just registered under its new name **[code]**.

**`BufWritePost` on an unregistered buffer** registers it once the write settles (M3).

**Decided: the disk decides** (DESK:1924):
- If the old name still exists as a file afterwards, the rename is a copy and the old name goes on the closed stack.
- Otherwise it's a move: every reference follows to the new hash, and nothing goes on the stack.

Built in step 4 (T107, T238, T272).

**Decided:** the settle rule covers renames too (DESK:1783). Built in step 4: a rename is decided once it settles, and `BufWritePost`'s update waits too (P2). `BufDelete`'s own bookkeeping still acts inside the event, since the buffer is gone afterwards.

**Decided (2026-10-20 evening), "Keep the older one":** "every reference" includes the secondary map's `-swap` keys, which `rename_hash_in_triquetras` will carry as it carries dtm's (`window/data.lua:149-152`; M7, T192). Built in step 3 (`window/data.lua:159-163`).

### A21. `cleanup_triquetras`: on every history transition

**Today** (`window/routines.lua:446-717`). It runs on every history transition: every arrival once it settles, and every `BufDelete`, rename once it settles, cycle start and stop, and load. It also runs from the UI derive path, and from `cleanup_system` when that one removed something. It wipes no buffer and switches no window: it changes only cavediver's data (P8). For each triquetra in turn:

1. **The current slot's buffer is not open.**
   - If the window shows some other *registered* buffer, re-point like navigation, notes included (Q18): when it's the secondary, the swap notes go first (`write_secondary_swap_notes`, M7) and the old current trades places with it, `s := old c`; otherwise, with a ternary T other than the shown buffer, `dtm[old c-swap] := nil` and `dtm[old c] := T`, and the old current goes into the ternary, `t := old c`; then `c := that`. Notifies "Healed the triquetra of window <w> with current slot: <bufnr>", with no level **[run s11]** (`:457-473`).
   - Otherwise:
     - an invalid window → drop the triquetra
     - the window shows the buffer being deleted → it lands once the delete is over (A19, `:497-502`)
     - the window shows a `buftype ""` buffer whose name hashes to the current slot, unregistered for the moment (a reload without events) → nothing to heal (`:503-507`)
     - the current slot is on the closed stack → it's kept: the window is visiting, and that's the file it was last on (`:508-512`; A2, T270)
     - the window shows the same file under another `buftype`, or an `acwrite` buffer such as oil's (`:513-589`):
       - try ternary, then secondary, then `primary[1]`. The first open one becomes `c` and is tracked. The window keeps showing what it shows (`:539-544`, T247).
       - when none is found: drop the triquetra if the slot's path is known, else take the most recent buffer, else drop the triquetra (`:547-589`)
     - the window is visiting anything else, and its current slot names nothing open or closed → drop the triquetra (`:590-604`)
2. **The secondary.** Cleared when any of these holds (`:609-634`):
   - it has no path
   - it isn't a No Name buffer, it's not open, and its file is unreadable
   - it isn't a No Name buffer, it's not open, and it isn't on the closed stack

   A secondary pointing at an open buffer is kept whatever the disk says, and its buffer stays registered (T239). An open one is cleared only when it has no path, and then its buffer is also unregistered (`:630-632`).
3. **The ternary.** The same rules, reading its own slot (`:636-661`).
4. **Primary entries.** The same rules, each reading its own entry (`:663-690`). The entry is removed from the queue.
5. **The current slot.** When it has no path, its buffer is unregistered (`:693-699`). Its file on disk isn't checked: a new file not written yet, or one deleted on disk, stays current and tracked (M3; T109, T110). The wipe that **[run s08, s09]** traced here is D14's.
6. Refresh the window's UI cache (`:701`).
7. **After the pass**, every window whose current, secondary or ternary slot the pass moved gets the check where a slot changes under the current buffer (`:704-716`, A1, T287).

**Labels:**
- Healing the current slot when the window shows another tracked file is intended (DESK:1929, "re-pointed").
- The re-point moving the old current into the ternary, or trading it with the secondary, is decided (2026-10-20) (Q18).
- Healing leaves the window alone, as decided (DESK:1859-1876). For a file deleted on purpose, in oil or outside nvim (DESK:1836-1841), the window keeps showing what it shows and its current slot moves on.

**Decided (2026-10-20):** a re-point without an event acts like plain navigation (A1): the old current goes into the ternary (Q18). Built in step 3: the re-point acts like navigation, notes included: `dtm[old] := T`, clearing `dtm[old-swap]`, when the old current goes into the ternary, and D8's swap notes on a trade with a shown secondary (T163). The check after the pass rewrites a stale note (T287).

**Decided:** cleanup never touches a buffer or a window (DESK:1859-1876):
- A slot pointing at an open buffer is kept, whatever the disk says.
- A missing file stays fully tracked.
- The evolved-window check gives way to the visiting rule.

Built in step 1: the first two points, and cleanup wipes nothing. Built in step 3: the rest. Healing switches no window and runs no `:enew`; a closed current slot stays while visiting, and a visiting window loses its triquetra only when its current slot names nothing open or closed (item 1).

### A22. `cleanup_system`: the timer, before every save, after every load

**Today** (`history/routines.lua:920-1021`). The timer runs every `cleanup_interval` ms, 4 s by default, and its first tick is immediate. It also runs at once from the UI refresh when a slot's registered buffer is no longer valid (M12, T242). No pass wipes a buffer. Passes:

1. **Stale registrations:** for each registered buffer that's no longer valid (`:933-956`):
   - When the same file is open as another buffer, found by exact name over `nvim_list_bufs()` (`find_buffer_by_filepath`, `:902-912`, never for a No Name hash), the registration is re-pointed to that buffer, and the hash keeps its history (T113, T273).
   - Otherwise a file, not a No Name buffer, goes on the closed stack like any other close, so slots keep it and reopen it (`:948-951`, I4, T242). Then `detach_filehash_from_crux` (`:878-895`) forgets the hash: it removes it from the history view, global and window history, and unregisters the buffer. It touches only cavediver's own data.
2. **History of buffers that aren't valid:** a history entry is kept when its hash has a registered buffer, whatever the disk says (`:958-970`). Otherwise it's detached as above. The report lists detached entries as orphaned files (**[run s08]**: "CAVEDIVER CLEANUP REPORT: … Orphaned files: …/brandnew.txt").
3. **Closed-stack pruning:** remove entries with no path, entries whose file is gone, and entries that are open again. It reads `filepath:match` before the nil check, and removes entries inside an `ipairs` loop (`:975`, `:993`). **bug (desk)**
4. **A triquetra reference count:** reported but never acted on.
5. **When anything was removed:** run A21 on every triquetra and rebuild the ordered lists. A re-point in pass 1 doesn't count **[code]**.

When the total is above 0, it notifies "CAVEDIVER CLEANUP REPORT: …" at INFO.

**Decided:** the 4 s timer stays as a safety net that only repairs cavediver's own data. The stale pass re-points to the file's live buffer, found by exact name, and never wipes. History follows along. Closed entries whose file is missing stay (DESK:1863-1876). Built in step 1: the stale pass's re-point, and no pass wipes. History following along (P10) and keeping closed entries whose file is missing (T114) aren't built.

### A23. Debug commands

Created by `setup()`, and made again when it runs again (`init.lua:159`, `:166-378`):
- `:CavediverHistoryData`, `:CavediverNavigationData`, `:CavediverWindowData` and `:CavediverUIData` print `vim.inspect` of the domain's data.
- `:CavediverTriquetra` and `:CavediverTriquetraVerbose` print the current window's slots, with names and loaded or closed in the verbose one. `:CavediverTriquetra` also prints the maps.
- `:CavediverRegistry` prints both registries and the closed stack.
- `:CavediverAllTriquetras` prints every triquetra and UI cache.

The `CavediverTriquetra*` commands print `primary_buffer[1]` as "Primary buffer". **Label:** intended (debug only). The descriptions say "curernt" (`init.lua:170`, `:173`).

### A24. Query and utility exports

These take no action. They return live tables, not copies:
- `get_buffer_history()` returns the history view (`history.data.crux`), not an ordered list. STATUS:471 says "ordered".
- `get_window_triquetra(w)` calls the getter, so **it can create a triquetra** (M6).
- `get_all_triquetras()` returns `window.data.crux`.
- `get_*_state()` and `is_cycling()` return the machines' states.
- `set_cache_from_window_triquetra(w)` re-derives one window's UI cache.
- `get_smart_basename` is nil (see Coverage).

### A25. `setup(user)` and what runs at require

**Today:**
- `require('cavediver')` loads every domain. That registers the state-machine hooks and sets `current_window` and `last_valid_window` to the current window (M10); it creates no autocmd, command or timer (T126, T254).
- `setup(user)` (`init.lua:127-163`):
  1. merges the config; with no argument it uses the defaults (M13)
  2. creates the `cavediver` augroup with `clear = true`, and each domain's autocmds in it, the storage domain's `SourcePost` included (`init_autocmds`, `:149-154`; S1)
  3. defines the highlights
  4. starts the UI timer and the cleanup timer
  5. creates the debug commands (A23)
  6. maps the keys

  Calling it again replaces the autocmds, the commands and the timers, leaving one of each (T127), and maps the keys again. The popup's buffer-local autocmds, made when it opens, and a reopened No Name buffer's one-shot `BufWinEnter` aren't in the group (M11).
- `disable()` (`init.lua:382-386`) clears the augroup and stops both timers, so nothing is tracked or refreshed until `setup()` runs again (T240). The keymaps and the debug commands stay **[code]**.
- Until a load or a first `BufEnter`, nothing is registered. The buffer nvim starts on isn't tracked until something enters it.

**Decided:** nothing runs at require. `setup()` creates everything inside one `cavediver` augroup with `clear = true`, and running it again replaces it all. `setup()` with no argument uses the defaults. `disable()` clears the augroup and stops the timers (DESK:2177). Built in step 2.

### A26. The flight recorder (decided 2026-10-21, not built)

The author's idea, 2026-10-21: "maybe for debugging purposes, we log the sequence of the winbar rendering, which shows the triquetra, and also other things like the displacement, and other things. this is for only things that _shouldn't_ happen."

**Decided (2026-10-21):**
- It **records all the time** into a small ring of the last N steps (oldest dropped), and **dumps only when something that shouldn't happen fires** ("Yes, ring + dump").
- A step is cavediver's **keymap actions** (`<M-f>`, `<M-S-f>`, the restores, cycling, primary keys, `<M-.>`, `<M-S-w>`) and the **editor events** it reacts to (`BufEnter`, `WinEnter`, `BufDelete`, renames), never raw keystrokes. The author: "i meant the keymaps not keys. and events make sense as well." Each step keeps the window and the result as `⦉ternary⦊ [current] ⟦secondary⟧`, the primary queue and the notes.
- What fires a dump: the restore assertion (`window/routines.lua:1036-1038`), the fill assertion (D11), "Duplicates detected" (`window/hooks.lua:92`), the highlight callbacks' `error()` (`ui/init.lua:243` and on), "This impossible error should never happen" (the restore's no-path throw; D9 removed it in step 3, so there's nothing to fire), and a hook failure (caught with traceback, decided on the desk).
- The dump goes to **both** a file (under `stdpath("state")/cavediver/`, decided 2026-10-21: "Yes, state dir"), in the sandbox's row format so it replays as a scenario, and a scratch buffer opened on the spot ("Both"). The error message says where the file is.
- **It dumps at the first break of I1 or I23**, checked after every step, not only when an assertion fires ("Yes, first rule break", 2026-10-21). The slot exchange shows why: the rule broke when `<M-;><M-t>` swapped the slots under the current buffer, but nothing threw until a later `<M-;><M-r>`, by which time the cause could have left the ring. Assertions still dump too.
- **It records cavediver's own model changes as steps**, tagged by cause: keymap, event, timer (the cleanup re-points), load (a session load, with its notes from the file), `:restart`. Session loads are marked, so a stale note that arrived from the saved file shows it has no cause inside the session ("Yes, tag by cause", 2026-10-21).
- **Decided (2026-10-21), needed for the replay (T201):** the dump opens with a snapshot of the state at its first step: every window's slots, primary queues and on/off, both note maps with swap notes, global and per-window history with access times, the closed stack, navigation and history states with cycling origins, `history_view`, and which files exist. The file has a machine-readable part (snapshot plus steps) that replays, and the rows for reading.
- **Decided (2026-10-21; proposed by Kate, taken by the author: "Drop the 30, One dump per failure, Dump window untracked, The other three"):** one dump per distinct failure (the highlight callbacks run every 140 ms); the scratch buffer opens after the editor settles; the dump window is `nofile`, unlisted, and invisible to the model; one assertion helper that every "shouldn't happen" goes through, with the engine's hook-failure catch hooked in; file names written as aliases (f1, f2…) with basenames.
- Not decided yet: N, the ring's length.

## 4. Invariants

Each is a statement a test can check after any action. Status:
- **enforced**: held by the code today.
- **violated**: broken today, with the bug cited.
- **decided**: set by the desk and not built yet.

| ID | Invariant | Status |
|---|---|---|
| I1 | Within one triquetra, current, secondary and ternary hold three different hashes, or are empty. | **Violated.** Asserted at `window/routines.lua:285` and `window/hooks.lua:92`, but nothing dedupes. Known routes: the save substituting `primary[1]` into a No Name current slot (DESK:2440). `<M-S-f>`'s rename has no guard for a nil hash, though the desk's route to it (DESK:2469) throws nothing and leaves no duplicate (A7, T49). `<M-f>`'s history fallback asserts that the ordered list's first entry is the current buffer, and the window-jump cancel and the tie fix close the routes where it wasn't (A6, D11; T43, T176). T128's walks find no duplicate. Decided: the sources get fixed and the assertion stays (DESK:1939). The primary queue isn't covered: its `[1]` may share a slot's buffer (Q16). |
| I2 | Every hash held anywhere has a path in `hash_filepath_registry`: slots, primary queues, both displacement maps (`-swap` keys included), history, and the closed stack. | **Enforced** where a path is forgotten (T129): the four places (`history/routines.lua:376`, `:534` and `:650`, and `history/hooks.lua:104-106` after a move; M2) go through `unregister_filepath`, which keeps the path while `is_filehash_referenced` finds the hash in the history, the closed stack, a slot, a primary queue or either map (`history/routines.lua:146-176`, `:185`). The fresh-start load clears the whole path registry and registers the loaded buffers again (`repopulate_history`, `:1040-1058`), and a load from idle clears it first (`teardown`, `:1027-1038`; S1) **[code]**. A load with a file registers every path the file holds before anything else, and the file holds every path the registry knew at the save, so a reference whose buffer didn't come back still has its path (`storage/routines.lua:200-202`, S1) **[code]**. Decided: "a path is never forgotten while anything references its hash" (DESK:84). Built in step 2. |
| I3 | Every triquetra has its window's history entry (`crux_internals.window[winid]`). | **Enforced** wherever a triquetra is made: `history.routines.ensure_window_entry` (`history/routines.lua:195`) runs from `register_triquetra` (`window/data.lua:42`, the getter's), the load's `set_buffer_relationship` (`window/init.lua:52`) and the fresh start's `repopulate_window_relationships` (`window/routines.lua:1105`), and the load's `initialise_crux_internals`, which resets the per-window entries and puts back each matched window's own, gives every triquetra one afterwards (`history/routines.lua:221-224`). So a `:vsplit` window has one at once (T18, T130) and the save goes through (T141). **[run s16]** recorded the split with none, and the save throwing on `next(nil)`. Decided: they're created together (DESK:84). Built in step 2. |
| I4 | A slot or primary entry holding a closed hash keeps it until it's used, and using it reopens the buffer. | **Enforced** while the closed file is on disk: each check reads its own slot or entry (`window/routines.lua:621`, `:648`, `:677`; T42, T56, T103, T104). A closed slot whose file is gone from disk is pruned (A21, P9). **[run s05, s06]** recorded the wrong-slot check (D13). A file whose buffer went without events goes on the closed stack at the stale pass, so its slots keep it too (A22, T242), and so does a file a session load finds in a slot with no buffer brought back (S1, T337). README:15 intends it. |
| I5 | The registry is a bijection: `buffers[h] = b` exactly when `hashes[b] = h`, and likewise for paths. | **Enforced** by the writers (M2) **[code]**. A buffer renamed with no events is tracked under a new hash that isn't registered (`history/routines.lua:372`) **[inferred]**. |
| I6 | A registered buffer number is a valid buffer. | **Eventually enforced** by the stale pass of `cleanup_system` (A22), which re-points a registration to the same file's live buffer and wipes nothing. Unlisted buffers and `noautocmd` wipes fire no `BufDelete`, so the registry is stale for up to one tick, or one UI refresh when a slot holds the buffer (M12, T242). Decided: re-point to the live buffer, never wipe (DESK:1863). Built in step 1. |
| I7 | A hash on the closed stack has no open buffer. | **Eventually enforced**: `track_buffer` removes it on a visit (`history/routines.lua:309`), and the cleanup pass does too (A22). |
| I8 | A window's current slot is the hash of the buffer the window shows, except: **(a)** while cycling, when it stays the cycle's start, which is intended (Q1); **(b)** while visiting, when it stays the file the window was last on (A2). | **Enforced** once every arrival settles, and re-pointed by cleanup. A cycle left open across a window jump is cancelled, so the other window's visits are recorded (A12, T282). **Violated** when `displacement_mangement` aborts on duplicates (A1, "Duplicates detected in current triquetra"). |
| I9 | Every triquetra belongs to a valid, non-floating window. | **Enforced** by `WinClosed`, the getter's float check, and cleanup. `:file` onto a name not on disk keeps its window and triquetra (T284, on the route of DESK:2444). |
| I10 | Only tracked buffers are registered (M3). | **Enforced at registration and on `OptionSet`.** Arrivals are judged once the editor settles, so a buffer entered before it becomes a terminal or a quickfix list (`:terminal`, `:copen`, DESK:2453) is never registered (T217, T250). A registered buffer whose `buftype` changes so that it's no longer trackable has its arrival undone once the editor settles (`undo_arrival`, `window/routines.lua:136-175`; `window/hooks.lua:175-192`). A window it just arrived in, whose triquetra hasn't changed since, gets back the triquetra from before the arrival (M6). Any other window whose current slot it is takes the next slot in line, ternary → secondary → `primary[1]`, or loses its triquetra. Then the buffer leaves every secondary, ternary and primary queue (`forget_hash_in_slots`), and it's untracked and unregistered, its path kept while anything references it (M2, T217). Decided: the listed-only rule, and undo on `OptionSet` (DESK:1789, DESK:2162). Built in step 2: the listed-only rule (M3). Built in step 3: the undo on `OptionSet`, and arrivals judged once the editor settles. |
| I11 | `ordered.crux` is newest first and holds only open, registered buffers. | **Enforced** at each rebuild (`history/routines.lua:391-409`). It's frozen on purpose while cycling. |
| I12 | Cavediver never wipes or discards a buffer with unsaved changes. | **Enforced** (T109, T131): cleanup wipes nothing (A21, A22), a file not on disk stays tracked (M3), and `:file` and `:saveas` keep their edits (A20, T106). A modified No Name buffer closed with `<M-.>` keeps its text on the closed stack (A15). `<M-.>` on an untracked buffer refuses a modified one whose `buftype` is `acwrite` or `""`, oil's with pending edits for one, as it refuses a modified file (A15, Q17). The wipes recorded by **[run s08, s09]**, DESK:2442 and DESK:2448 are D14's, A20's and A22's routes. Decided: cleanup never touches a buffer, and missing files stay tracked (DESK:1859, DESK:1925). Built in step 1: no wipe, and missing files stay tracked. |
| I13 | Cavediver changes only the window an action is about. | **Holds** on every route found. A reopened No Name buffer's cursor goes back in the window that shows it (M5, T90); DESK:2473 recorded it set on the current window, before step 4. Healing switches no window (A21; T247, on the route of DESK:2447), and a deleted buffer's window lands in that window (A19; T111, T132). The window-jump cancel switches the cycling window, the one the cycle is about, back to its start (A12). Decided: the pick after a delete lands in the window that showed the buffer (DESK:1931). Built in step 1. |
| I14 | Every saved file can be written whatever state cavediver's data is in. | **Enforced** for the three routes DESK:1058-1064 found: a No Name current slot with nothing to stand in for it is saved as `null`; a hash the path registry doesn't know is dropped, so a slot holding one is saved as `null` and the primary queue, the closed stack and No Name texts skip it (S1; `storage/routines.lua:127-141`; T285); and every triquetra has its history entry (I3), with the save reading a missing one as empty (`storage/routines.lua:515`; T141). Decided (DESK:1058). Built in step 2. |
| I15 | Hashes are a pure function of the name: the first 16 hex characters of sha256(name .. "\n"). | **Enforced** (T8, T9): hashing is `vim.fn.sha256(name .. "\n")` with no shell (`history/routines.lua:34-42`), so names with `"`, `$` or a backslash hash like any other. The collisions at DESK:2441 are the shell's. Decided: `vim.fn.sha256` (DESK:2131). Built in step 2. |
| I16 | A No Name id is never reused, across sessions too. | **Enforced** (T11, T216): a No Name buffer is named by an id made from `os.time()` and `vim.uv.hrtime()` and kept on the buffer (`vim.b.cavediver_noname`, `history/routines.lua:20-25`; M1), not by its number, so a later session's buffer with the same number gets another. A reopened No Name buffer gets a fresh id (M5). Decided (DESK:2289), against bufnr reuse (DESK:2285-2287). Built in step 4. |
| I17 | Displacement-map and history entries point only at things still known through open buffers, slots, primary queues or the closed stack (follow along). | **Not enforced**: the maps are never pruned, apart from a restore clearing a note at a hash with no path when it uses it (A11). Decided (DESK:2029). |
| I18 | The primary queue has no duplicate entries. | **Enforced** by `set_primary` (`window/routines.lua:978-981`). The popup can introduce duplicates, since `update_primary_buffer` doesn't dedupe **[code]**. |
| I19 | An empty primary queue may be switched on or off; nothing forces it off. `<M-;><M-x>` on an empty queue always queues the current buffer and switches on (A9). | **Holds**: pruning leaves `p=[]on` **[run s06, s19]**, `jump_to_primary` falls back to `<M-f>` either way, and the first press on `p=[]on` gives `p=[A]on` (A9, T157). **[run s19]** recorded `p=[A]off` before the fix. Decided (2026-10-20) (Q14); built in step 3. |
| I20 | Storage: `load_session` and `save_session` work from `bare` or `idle`, a load from `idle` going through `bare` first, and storage is `idle` after either. | **Enforced** (T137, T138, T295). A save whose hook fails leaves storage where it was (I21). **[run s10]** recorded a load after a save throwing `Transition 'idle->loading' is not registered` from `to()`, before the teardown. Decided: `idle → bare → loading` (DESK:1284). Built in step 4. |
| I21 | A transition always completes: the state changes even when a hook fails. | **Enforced** for every hook but the critical save hook (`engine/helpers.lua:32-47`). That one re-throws to `save_session`'s caller, abandoning the transition, so storage stays where it was: `idle` after a load or a save, `bare` before either (`storage/hooks.lua:17`; T143, T286). Decided exception: the critical save hook re-throws and leaves storage at `idle` (DESK:1157). Built in step 2: storage stays where it was, which is `bare` when nothing was loaded or saved before (T286). |
| I22 | A file appears at most once in a closed pool (today, the one closed stack). Closing a file that's already there moves it to the newest position; a merge of pools keeps only the newer entry. | **Not enforced**, but no route found that breaks it today **[run s20]**. With the desk's per-tab pools and the merge picker, a merge is the route. decided (2026-10-20) (Q15). |
| I23 | No buffer is current while its note names the buffer already in the slot that note restores into. For the current buffer X and each map, the note a restore would read is X's swap note when it's set and isn't the slot's occupant, otherwise X's plain note; that note never names the occupant of the ternary (dtm) or the secondary (dsm). A plain note behind a valid swap note may name it: the restore never reads it. | **Enforced** where the check runs, on every arrival and wherever a slot changes under the current buffer (A1, M7): T190's walks find no break, in one window and several, under both views. Every restore throw is this state (A11); **[run]** recorded 161 secondary and 14 ternary throws in 1,500 walks without the check. The landing after a delete runs the check too (A19), though no walk deletes files. Decided (2026-10-20 evening), "Keep the older one" (A1, M7, Q13), with the check also at the secondary restore's exchange (decided 2026-10-21): 0 breaks over 900,000 walk steps with every fix in **[sim, variant `all_fixed`]** (T189, T206). Built in step 3. Checked by T190. |

## 5. Sessions

### S1. Today

**API.**
- `save_session(name?, opts?)` and `load_session(name?)` (`storage/init.lua:26-33`, `:62-67`). Neither takes a directory, and either can be called with no argument: `name` is the session's name, and nil makes a nameless session.
- Cavediver reads the session's directory itself. The save reads the global directory, `vim.fn.getcwd(-1, -1)`, for the whole editor, or the tab's, `vim.fn.getcwd(-1, <tab number>)`, when `opts.tab` gives a tabpage (`storage/init.lua:27-30`; T292, T293, T294). The load always reads `getcwd(-1, -1)` (`:41`). So a tab session saved from a tab with a `:tcd` of its own isn't found at load: the load reads the global directory's file of that name, or starts fresh when there's none. From a tab with no `:tcd`, the directory is the global one and the file is found **[code]**. Finding a tab session's file at load waits for tab sessions (S2; T318).
- Both hand the storage machine `{ name = name, directory = directory }` as the transition's context, and its hooks pass the two on to `save_history` and `load_history` (M11).
- The README wires them to resession's `pre_save` and `post_load` with `vim.loop.cwd()` (README:93-99), so the cwd is passed as the session's name.

**State machine.**
- Save is `→ saving → idle`, from `bare` or `idle`.
- Load is `→ loading → idle` from `bare`, and `idle → bare → loading → idle` from `idle` (`load`, `storage/init.lua:40-55`; T137, T138, T295). **[run s10]** recorded a load after a save in the same process throwing `Transition 'idle->loading' is not registered` from `to()`, which escaped resession's hook and broke session switching (DESK:1254-1260), before the teardown.
- **The teardown.** At `idle → bare` every domain tears its own state down, in a hook of its own on the storage machine, so the load starts from nothing, as at startup:
  1. navigation: its state set to `normal` directly, `cycling_window` cleared, the window-jump table emptied (`navigation/hooks.lua:16-20`)
  2. window: the winbars cleared, every triquetra dropped, `landing` and `arrivals` emptied, and `current_window` and `last_valid_window` set to the current window (`window/hooks.lua:19-30`)
  3. history: `teardown()` empties the view, both histories, the ordered lists, both registries, the closed stack, the No Name texts and the cycling origins, and sets `history_index` to 1; then the history state is set to `attached` directly (`history/hooks.lua:62-65`, `history/routines.lua:1027-1038`)
  4. ui: the window display caches, the display-name cache and the bufferline state cleared in place (`ui/hooks.lua:17-27`)

  No transition sets the two states, so no hook runs for them, and a cycle left open ends with nothing picked (M9). The outgoing No Name texts go with the teardown, so a session switch doesn't carry them into the incoming file (T148). What the load restores is the same as at startup (below), and a buffer the file doesn't know waits for its `BufEnter` (T296, T314).
- **The repeat flag.** A load sets `storage.data.loading_batch` and schedules its clearing with `vim.schedule`. `load_session` skips a call while it's set: a native restore calls it once per loaded buffer, and only the first loads. A call after the batch is a full load (`storage/init.lua:42-49`, `:63-65`; T145, T297).
- **Once the restore settles,** the same `vim.schedule` runs `after_restore`: when the focused window has a triquetra, it becomes `last_valid_window` and `current_window`, and its history view and both ordered lists are built (`storage/routines.lua:716-725`; T299). No timer runs.
- **After `:restart`.** Neovim's `:restart` restores its own session after the startup's and rebuilds the windows. The storage domain's `SourcePost` autocmd, made by `setup()`, sees a `restart_session_*` file while `v:startreason` is `restart`, and runs the last load of this startup again, under the same name, once the editor settles, ignoring the repeat flag (`storage/init.lua:73-92`; T298). The name is kept in `storage.data.last_loaded` as `{ name = … }`, with no name for a nameless load, so a nameless load is run again too (`storage/data.lua:61`, `storage/init.lua:43`).
- **The load counter.** Each load bumps `history.data.loads` (`storage/routines.lua:672`). A `BufEnter` arrival queued before it, and the close key's deferred delete, drop themselves when they settle: the restore's own events are noise the load replaces (`history/hooks.lua:188-190`, `history/routines.lua:801-805`; A1, A15).
- The load hook runs inside `xpcall`, so a failure inside a load is only a notification, with its stack trace, and storage still goes to `idle`. The save hook is critical: a failure inside a save throws to `save_session`'s caller, and storage stays where it was, `idle` after a load or a save and `bare` before either (M11, I21; T286). So with a read-only session directory, the save throws (T143); DESK:2452 is the record of that failure as a notification only, resession's file written and cavediver's not.

**File.**
- Path: `session_dir/<sha256(directory .. "\n" .. name)>.json`, or `session_dir/<sha256(directory)>.json` for a nameless save, all 64 hex characters, with the directory read as above (`storage/routines.lua:640-655`; M1, T255, T292). It's plain JSON, created as `{}` first if it's missing. A file named after the first 32 hex characters of `sha256(cwd .. "\n")` isn't read (M1).
- Written with `writefile`, which isn't atomic and uses umask permissions (`storage/routines.lua:745-766`).

**Save** (`save_history`, `storage/routines.lua:735-767`):
1. `cleanup_system` runs (A22). It wipes nothing, but it can prune the closed stack (T214).
2. The keys written (T134). Hashes are saved raw. A slot, a queue entry, a closed entry or a No Name text whose hash the path registry doesn't know is left out (`known`, `:127-141`; I14); the maps and the global history are written as they are.
   - **`paths`**: hash → path for every path the path registry knows, open and closed buffers and `NONAME_` names alike, plus the outsiders, each XOR'd with the session's directory and base64-encoded (`serialise_paths`, `:531-543`). Every path inside the session's directory begins with a run of zero bytes once XOR'd, so its value opens with a run of `A`s in base64, DESK:1561; **[run s10]** recorded it in `closed`, which held XOR'd paths then.
   - **`outsiders`**: the hashes in `paths` that are outsiders, untracked buffers that windows with a triquetra show, such as an oil listing or a help file, each hashed by its name (`shown_by`, `:149-160`). They're recorded so the load can match those windows, and kept out of the registry (`:755`).
   - **`buffers`**: `{ global = crux_internals.global }`, the global access history (`:361-365`). Each window's own history goes in its window entry.
   - **`windows`**: one entry per window that has a triquetra, visiting windows included, in `nvim_list_wins()` order, tab order then window order (`serialise_window_relationships`, `:375-521`). Each entry is `[current, secondary, primary_queue[], ternary, dtm, dsm, shows, primary_enabled, history]` (`:506-516`), with `null` for an empty slot, so it has no holes:
     - The slots and the queue hold raw hashes. A slot whose hash the path registry doesn't know is saved as `null` with no error (T285), and the queue skips such a hash (`:466-470`).
     - Both maps are written raw, `-swap` keys included.
     - `[7]`, **shows**, is what the window shows once the save is done: its buffer's hash when the buffer is registered, otherwise the hash of its buffer's name, an outsider; `null` for an untracked buffer with no name (`:500-504`).
     - `[8]` is `primary_enabled` (T136), and `[9]` is the window's own access history, read as empty when it has none (`:515`); every triquetra has one anyway (I3). **[run s16]** recorded a `:vsplit` window with no history entry making the save throw `next(nil)`, before I3.
   - **`closed`**: the closed hashes (`:551-559`).
   - **`noname_content`**: keyed by the No Name buffer's hash (`:568-584`). Each line is XOR'd; filetype and cursor are stored in clear.
3. In the saved entry only (the live triquetra is untouched), a current slot holding an open No Name buffer is replaced by `primary[1]`, else the ternary (which is then left out of the entry), else the secondary (likewise), else nothing: the slot is saved as `null`, and the load takes the hash of what the window shows (`:431-447`, `:289`). The `primary[1]` branch can leave the same file in the secondary as well, which starts the duplicate-slot error after a restart (DESK:2440).
4. **Oil windows** that have a triquetra are switched to their current-slot file under `eventignore=BufEnter,BufLeave` and never switched back (`:488-498`). The switch comes before `[7]` is read, so a switched window is saved as showing that file. Autosave does this mid-session.

**Load** (`load_history`, `storage/routines.lua:665-710`):
1. Read and `json_decode` the file, each inside `pcall`. If either fails, or the data lacks `paths`, `buffers` or `windows`, it's a **silent fresh start**, and the next save overwrites the file (`:674-686`, DESK:2458). A file saved before the `paths` table is one of these (M1).
2. With data:
   - **`load_paths`** deciphers `paths`, leaving the outsiders out (`:169-181`).
   - **`load_buffer_history`** registers every path the file knows as a path, so a reference whose buffer isn't restored still resolves to its file (I2). Then it registers every restored buffer whose name hashes to one of those paths and that `is_trackable` holds for, loaded or not: a `badd` buffer counts (M3, T139). A buffer the file doesn't know isn't registered, and waits for its `BufEnter` (T296, T314). Then it runs `track_buffer(hash, time)` for every saved global entry, including entries that aren't open (`:194-219`, M4).
   - **`load_closed_buffers`** clears the stack and rebuilds it from the saved hashes. An entry whose buffer the session manager brought back is registered by then, so it's left off the stack (`:612-614`); DESK:2471 recorded `bufexists` throwing on such an entry and stopping the load, before it was left off. `NONAME_` entries get their text deciphered. It throws on a hash with no path, or on a No Name entry whose text is missing or already there, and a throw stops the rest of the load (`:596-634`).
   - **`load_window_buffer_relationships`** matches saved entries to windows **by what they show** (`:246-341`):
     - The entries are grouped by `[7]`, in saved order. Each window but a float, in `nvim_list_wins()` order, takes the first unused entry whose `[7]` is what it shows: its registered buffer's hash, or else the hash of its buffer's name (`shown_by`). So windows on the same file keep their saved order (T315), and a window on an outsider finds its entry by the outsider's hash. Floats never take an entry.
     - An entry that matches no window is dropped (T142, T244, T251). A window that matches nothing is left to the getter: it keeps the triquetra it has, which only a load from `bare` can leave it, since a load from `idle` tears every triquetra down first (T318); otherwise it gets a fresh `{c=<shown>}` when what it shows is registered, and waits when it isn't (M6, T315).
     - A matched entry's current slot is `[1]`, or the hash of the window's registered buffer when `[1]` is `null`; with neither, the window is skipped. `set_buffer_relationship` takes the slots, the queue, both maps and `primary_enabled` from the entry (`window/init.lua:60`; T136), and the window's own history comes from `[9]`.
     - **A reference the manager didn't bring back is closed** (`close_if_not_restored`, `storage/routines.lua:225-235`): a file, not a No Name buffer, in a matched entry's current, secondary or ternary slot or primary queue, with a path and no registered buffer and not already closed, goes on the closed stack under the saved entries, as the oldest. The slot keeps it and reopens it when used, and cleanup and the UI treat it as any closed slot (I4, T337). A file deleted on disk is still pruned from there by cleanup's missing-file rule (A21, T313).
   - **`initialise_crux_internals`** resets the window histories, puts each matched window's own in place by window id, gives every other triquetra an empty one, and puts the saved global history in place, then rebuilds the view for `last_valid_window` (`history/routines.lua:213-230`). The window the restore leaves focused gets its view once the restore settles (`after_restore`, above).
   - Then every triquetra gets the check where a slot changes under the current buffer: the notes come from the file, so a loaded slot can leave a note naming it (`storage/routines.lua:696-699`, A1, T243).
3. Without data: a **fresh start**. Cavediver's state is cleared and every loaded buffer registered (`repopulate_history`), and every window gets `{c=X}` (`repopulate_window_relationships`).
4. Then `cleanup_system` runs, and history → `attached` with the current buffer.

**[run s11]** recorded a load with unloaded buffers losing slots, before the `paths` table: a value with no restored buffer was deciphered as a path and gave noise, so the slot came back empty or the current slot got healed (DESK:1379; T139). DESK:1381 recorded windows matched by position, shifted when the save and the load counted windows differently, and `initialise_crux_internals` throwing `table index is nil` on a count mismatch, before the matching by what windows show (T142, T244).

**[run s12]**, the happy path: a file saved with `{c=d s=c t=e p=[b]off}` and `dtm{b→a, c→b, e-swap→d}` came back the same, with `b`, `c` and `e` loaded and `d` shown, except that it recorded `p=[b]off` coming back `p=[b]on`, before `[8]` (T136).

### S2. Decided (DESK)

Built: the API, the file's name, the loading and the contents, in step 4, and part of the errors, in step 2. Not built: the written contract, the rest of the file, save-as-closed, the checks, tab sessions, oil and the closed-stack picker.

**Contract and API** (DESK:749-794):
- Cavediver is manager agnostic, with no adapters.
- `save_session(name?, opts?)`, where `opts.tab` marks a tab session, and `load_session(name?)`. Neither takes a directory: cavediver reads it itself, `getcwd(-1, -1)` for the whole editor or the tab's directory for a tab session.
- A written contract says who calls the two functions and when: resession, native `:mksession`, and no manager, with the table at DESK:764-771. It includes saving the outgoing session through the manager before a switch, and saving a tab session on `TabClosedPre`.

Built in step 4: the API and the file's name (S1; T255, T292–T294). Neither function takes a directory: cavediver reads it, `getcwd(-1, -1)` for the whole editor or the tab's for `opts.tab`, and the file is named `sha256(directory .. "\n" .. name)`, or `sha256(directory)` for a nameless save. The load reads only the global directory; finding a tab session's file at load waits for tab sessions (T318). The written contract, in the README, isn't built.

**Loading** (DESK:1276-1288, DESK:794, DESK:1161):
- `load_session` from `idle` goes `idle → bare`, where every domain tears down its own state, then `bare → loading` as at startup.
- Repeat calls within one native restore are skipped by a flag that `vim.schedule` re-arms. A later reload is a full load.
- Cavediver reloads by itself after Neovim's `:restart` session, ignoring the flag.
- One post-restore callback replaces the 200 ms and 210 ms delays.

Built in step 4: all four (S1; T138, T145, T295–T299). The load leaves a restored buffer the file doesn't know for its `BufEnter`, through the `paths` table (Contents, below; T314).

**The file** (DESK:1539-1628):
- AES-256-GCM through OpenSSL 3's `libcrypto` over FFI.
- PBKDF2 with 200,000 rounds and a random salt; the key is the scope's directory.
- A clear `CDV1` version header covered by the tag.
- A main file named `sha256(directory .. "\n" .. name)` (the separator decided 2026-10-21, T255), plus one hashed file per No Name text in `<main>.d/`. The scratch files are written first, the main file last as the commit point, and unreferenced scratches are swept.
- Atomic writes in mode 0600. No count limit. A migration script converts old files once.

**Contents** (DESK:1428-1456):
- References are saved as hashes and resolved at runtime.
- A `paths` table holds hash → path for everything the registry knows, plus **outsiders**: untracked buffers that windows showed, like `oil:///…`.
- Each window entry records `shows`.
- At load, each restored buffer's name is hashed:
  - a registry entry is registered, loaded or not
  - an outsider only helps match windows
  - no match waits for `BufEnter`
- Windows are matched by what they show, keeping order for the same file. An unmatched entry is dropped; an unmatched window starts fresh.

Built in step 4 (S1; T134, T139, T142, T244, T251, T314, T315): references saved as raw hashes and looked up at runtime, with the `paths` table and the outsiders; each window entry records `shows`, and windows are matched by it; each entry also saves `primary_enabled` (T136). A reference whose buffer didn't come back is closed at load, so its slot keeps it and reopens it when used (T337). Keeping a reference to a file gone from disk waits for step 6 (Checks, below; T313).

**Save-as-closed** (DESK:1630-1640):
- Open, non-empty No Name buffers are saved like closed ones.
- At load they're reopened in the background, marked modified, hidden, under a fresh id, and every reference to them is renamed.
- No Name buffers closed with `<M-.>` stay on the stack.

**Checks** (DESK:1672-1689):

| The file | The load |
|---|---|
| missing | a fresh start |
| has a newer header | "made by a newer cavediver", and the file is left alone |
| has no header | "run the migration script" |
| fails the GCM check | "failed its integrity check (edited or corrupted)", then a fresh start |

A reference that resolves to nothing is kept and says so when it's used.

**Errors and drift** (DESK:1054-1076, DESK:1154-1157):
- The save hook is critical: an environment failure throws into the manager's hook, so neither file is saved.
- Cavediver's own data can't make the save fail (I2, I3, I14).
- References are saved only together with the manager; records may be refreshed on their own.
- With two instances, the last writer wins.

Built in step 2: the first point as far as cavediver goes, the save hook throwing to `save_session`'s caller (I21), and the second point for the triquetras the getter makes (I3, I14).

**Tab sessions** (DESK:938-966):
- The scope is written into the file.
- There's one **pool** per session: its closed stack, No Name texts, and a visit overlay ranked above the global history.
- Closes go to the pool of the current tab, and `<M-S-w>` reopens from it.
- A buffer belongs to every tab that visited it.
- Saves are snapshots: a whole-editor save merges the pools by close time in the file only.
- A closed tab is saved through the manager, or kept with no tab and a notice.
- The unnamed session's records are refreshed at tab-session saves.

**Oil** (DESK:2085-2095): oil windows come back as oil, and cavediver sets `vim.w.oil_original_buffer` from the triquetra's current slot.

**Closed-stack picker** (DESK:2353-2376): `:CavediverClosed`, plus a keymap, is an editable buffer.
- Each pool is a header, and its closed entries are listed under it.
- A No Name entry shows as `[No Name] "first line…" filetype`, with its close time.
- Pools merge by cutting and pasting lines.
- Discarding a No Name entry asks for confirmation.
- Reordering lines reorders the stack, and `<CR>` reopens the entry.

## 6. Disagreements between the sources

Each entry gives both sides. When the desk has decided something, that's the intended behaviour, and the code is just today's state. The entries are grouped by topic, so the numbers, which section 3 refers to, aren't in order.

An entry marked **settled by Qn** was settled by the answers of 2026-10-20, and gives the outcome. An entry marked **Settled (2026-10-20)** was settled by the author directly, while going through the open list.

**Fixes and the author's voice** (the author, 2026-10-20: "write it the way I write it", then "only try write in my voice if you have samples right away"). A doc or string fix is written in the author's voice only when a sample of the author's own writing for that text is at hand, and the sample is shown next to the fix. Without one, the fix is in plain wording.

**Keys and configuration**

- **D1. `toggle_primary` and `set_primary` keys swapped.** `configs.lua:126-127` binds `toggle_primary = "<M-;><M-x>"` and `set_primary = "<M-;><M-c>"`. README:319-320 has them the other way round. SPEC:292 says the primary is set with `<M-;><M-x>`. The desk lists this as the README being out of date (DESK:2489).
  - **Settled by Q8:** the code wins. The README has the two keys swapped, a bug, so README:319-320 changes; SPEC:292 is out of date. Only `toggle_primary`'s keymap description changes in the code (A9).
- **D2. README's defaults block vs `configs.lua`.**
  - The colours differ (README:228-298 against `configs.lua:29-105`).
  - `cleanup_interval` is 8000 at README:323 and 4000 at `configs.lua:132`. Both comments say "seconds", but the timer is in milliseconds (`history/init.lua:54`).
  - The README leaves out `primary_buffer_history_popup`, the `open_primary_buffer_history` keymap (it mentions `<m-;>F` at README:32) and `colors.cokeline.diagnostics`.
  - README:285 has `is_picking_focus`, which `configs.lua` lacks. Neither colour is used: the picking colours are hard-coded at `ui/init.lua:379-381`, in the old palette (`#a05959`, `#d7d7a5`).
  - How it drifted: the code's palette changed in `778668f` ("chore(config): updated default colors", 2026-01-07) and `cleanup_interval` went from 8000 to 4000 in `59463f2` (2025-07-17); the README's block is from its first draft (2025-07-10).
  - **Settled (2026-10-20):** the README follows the code: its defaults block copies `configs.lua`, including the missing keys, and the `cleanup_interval` comment says milliseconds. The pick letters read their colours from the config, `colors.cokeline.is_picking_close` and a new `is_picking_focus`, instead of the hard-coded pair. The `is_picking_focus` default is the author's to pick (T168).
- **D3. Keymap descriptions.** `close_buffer` (`init.lua:111`) and `open_primary_buffer_history` (`init.lua:117`) are both described as "Toggle current buffer as primary". So is `cycle_select` in its annotation at `configs.lua:10`.
  - **Settled (2026-10-20):** each key gets its own description: `toggle_primary` "Switch the primary on or off" (Q8), `close_buffer` "Close the current buffer", `open_primary_buffer_history` "Open the primary queue". `cycle_select`'s annotation copies the author's own description of that key, "Select cycling buffer and attach history" (`init.lua:86`) (T169). The `cycle_select` annotation copying the author's own description was confirmed by the author (2026-10-20, late evening).
- **D4. Hashing dependency.**
  - Today: README:47 requires `openssl` "for hashing file names and directories", but the code hashes with `vim.fn.sha256`, with no shell and no openssl (`history/routines.lua:37`, `storage/routines.lua:631`).
  - Decided: `vim.fn.sha256` for hashing, and `libcrypto` only for encryption (DESK:1541, DESK:2131).
  - **Settled (2026-10-20):** README:47 says `libcrypto` (OpenSSL 3) is needed to encrypt the session file, and hashing needs nothing extra.
  - Built in step 2: hashing with `vim.fn.sha256`, for file names and the session file's name (M1). `libcrypto` comes with the encryption (S2), and README:47 isn't changed yet.

**Primary**

- **D5. A disabled primary.**
  - README:31: `<m-;><m-f>` "won't do anything at all, until you set it to active again", and you can still use the popup while it's disabled.
  - Code: `<M-;><M-f>` falls back to `<M-f>` (`window/routines.lua:907-910`) **[run s02]**, and saving the popup sets `primary_enabled = true` whenever the queue isn't empty (`window/routines.lua:231-235`).
  - **Settled by Q10:** the code wins for the key. With the primary disabled, `<M-;><M-f>` acts like `<M-f>`, and README:31 changes. The popup save follows a new rule: it switches the primary on only when the first row changed, and otherwise keeps the on/off state (A18).
- **D6. A popup save with an invalid path.** README:26-28 says nothing is saved. The code reports the bad lines and saves the valid ones (`window/routines.lua:224-236`).
  - **Settled by Q11:** the code wins, and README:28 changes.
- **D12. Popup close keys.** `q` and `<C-c>` are described as "Close without saving" (`ui/hooks.lua:130-132`), but `close_window` runs `write!` first (`ui/hooks.lua:91`).
  - **Settled by Q12:** the code wins. They save and then close, and their description changes to "Save and close".
- **D19. Primary overlapping a slot.**
  - README:368: "A buffer cannot occur more than once in a window triquetra."
  - SPEC:44 and SPEC:294: the primary is mobile and "can occupy any slot position". The code allows it.
  - `bufferline.get_buffer_relationships` asserts each buffer has one role, so it throws when, for example, current = primary (`ui/init.lua:202-226`) **[run s14]**.
  - So README:368 holds for the three slots only.
  - **Settled by Q16:** the primary is mobile. README:368's "no buffer twice" covers the current, secondary and ternary only. `get_buffer_relationships`' one-role assertion is fixed or removed; nothing calls it.

**Swaps, restores and maps**

- **D7. Do swaps write displacement entries?**
  - SPEC:133 and SPEC:239-244: "Pure swaps never create mappings" (`<M-f>`, `<M-S-f>`).
  - README:355: `<M-f>` records the current buffer's secondary.
  - STATUS:419-428: the secondary swap writes `dsm[old] = secondary` and `dtm[old] = ternary`.
  - Code: `<M-f>` writes `dsm[A]` and `dtm[A-swap]` (`window/routines.lua:575-578`), and `<M-S-f>` writes `dtm[A-swap]` (`window/routines.lua:277`).
  - Four sources, three answers (Q2).
  - **Settled by Q2:** the code wins. Swaps and primary jumps write swap notes `dtm[A-swap]`, and navigation writes plain notes (M7). SPEC:133, SPEC:239-244 and STATUS:419-428 are out of date.
  - **Decided (2026-10-20 evening), "Keep the older one":** `<M-f>`'s secondary note moves into a swap key too, `dsm[A-swap]`, so the secondary map has the same two kinds of note (M7). Built in step 3.
- **D8. Reaching the secondary by plain navigation.** README:355 says "every time you jump to secondary" the secondary is recorded. A plain `:e` to the secondary swaps it with no `dsm` write (`window/hooks.lua:71-82`) **[run s01]**.
  - **Settled (2026-10-20):** plain navigation onto the secondary records the same notes as `<M-f>`, so `<M-;><M-t>` works after either route **[run `t/b5_A_use.lua`, `<M-f>` standing in]**. The author, shown the round trip that then throws like `<M-f>`'s own (`t/b5_A_round.lua`, `t/pkB_secflip.lua`): "we should solve the round trip as well." README:355 stays. Confirmed by the author (2026-10-20, late evening), after being recorded from a reading of their words.
  - **Decided (2026-10-20 evening), "Keep the older one":** the round trip is solved on both routes. The note goes into a swap key, `dsm[A-swap]`, and on arrival the buffer's plain note becomes its secondary from before (M7, A1, A6). After a round trip the restore says there's nothing to restore, or brings back the older secondary when there is one, instead of throwing (T177–T180, T191).
  - Built in step 3: both routes write the notes through one function (`write_secondary_swap_notes`, `window/routines.lua:72-85`; T30, T191), and the round trip on either route says there's nothing to restore or brings back the older secondary (T177–T180).
- **D9. Restore edge cases.**
  - SPEC:170-178: when the remembered value is missing, invalid or the same as the slot, show "No different ternary relationship to restore". The code throws when it's the same (`window/routines.lua:1036-1038`) and when it has no path (`:811-812`).
  - SPEC:493-495: an invalid file gives the message. The code warns and clears only `map[A]`, not `map[A-swap]` (`:813-815`).
  - SPEC:700 needs an open buffer for the remembered value; the code needs a path and a readable file.
  - **Partly settled by Q13:** the throw when the remembered value equals the slot stays, as an assertion, and SPEC:176 is out of date. The other three cases (the throw when the remembered value has no path, a desk bug at DESK:2449; the invalid-file case that clears only `map[A]`; SPEC:700's open-buffer requirement) are settled below.
  - **Settled by the desk (2026-10-20 evening):** the no-path throw goes, because a note at an unknown hash is cleared when used (DESK:1936, :1938, :2029, :2449; T68) **[run `t/pkB_d9_nopath.lua`]**. SPEC:700's open-buffer requirement is out of date: a closed hash is kept and reopened when used (DESK:1935, README:15) **[run `t/pkB_d9_closed.lua`]**. What a restore does when the remembered file is missing from disk, **settled (2026-10-20 evening)** in the author's words: "well, if the thing is closed we may skip it. if it's open we can go through and flip-flop with it.." For both restores (one function, `window/routines.lua:713-762`): Confirmed by the author (2026-10-20, late evening), after being recorded from a reading of their words.
    - The remembered file is missing and **closed** (no buffer): it's skipped and kept, as DESK:2022 keeps pointers. A skipped swap note falls back to the plain note. If that's missing and closed too, the restore says so and changes nothing.
    - The remembered file is missing but its **buffer is open**: the restore goes through and flip-flops with it, saying the file isn't on disk.
    - Without the rule, the restore deletes the plain note and stops on the swap note forever **[run `t/b6_rows.lua`, `t/b6_open.lua`; the rule in variant `d9U`]** (T67, T173, T174).
    - Under "Keep the older one" the rule covers the secondary map's swap keys too (M7, T193).
  - Built in step 3, on both maps, swap keys included (`window/routines.lua:999-1062`; T67, T68, T173, T174, T193, T266, T267).
- **D11. The secondary's first population.**
  - SPEC:299-300: "No auto-population: Never automatically populated from history." SPEC:92-94, the code and STATUS fill it from history on the first `<M-f>` (`window/routines.lua:757-764`).
  - SPEC:428-447, "Secondary Population Edge Case", puts the current buffer in the secondary (`current: A, secondary: A`), which breaks SPEC's own Rule 1 (SPEC:343) and README:368. The code takes `ordered[2]`.
  - **Settled (2026-10-20 evening):** the fill from history stays (pressing `<M-f>` is acting, P14). The duplicate came from a cycle in another window freezing the history **[run `t/b7_dup.lua`; under `history_view = "window"` the same route duplicated in 7 of 8 re-runs, `t/b7w_dup.lua`: the window view's rebuild ties two buffers and the tie breaks at random, see the bug below]**. The author's fix is at the cause: jumping windows ends the cycle (A12). The fill then **asserts** that the ordered list's first entry is the window's current buffer, so any leftover route throws and gets fixed, the same stance as Q13 (T176).
  - **bug (new), found 2026-10-21:** the window view's rebuild (`history/routines.lua:257`, `:260`, in `construct_crux`) gives a window's newest buffer the next free access time, so the next buffer recorded ties with it. When the window entry fires no `BufEnter` (same buffer in both windows, e.g. right after `:vsplit`, or after `:close`), the tie breaks at random from one Neovim start to the next. Shortest route to the fill assertion: `:e a`, `:e b`, `:vsplit`, `<C-w>p`, `:e c`, `:vsplit`, `<M-f>` **[sim, window view, multi-window walks]** (T197).
  - The fix, as tested in `all_fixed`: `history/routines.lua:191` `data.history_index = data.history_index + #window_buffers - 1` becomes `+ #window_buffers`, and `:194` `data.history_index - rank + 1` becomes `data.history_index - rank`. A window's buffers keep their order, and the next visit always ranks first on its own: no tie in 675,000 several-window steps.
  - **bug (new), not exercised:** the session-load branch of `track_buffer` (`history/routines.lua:294-298`) can hand out an access time that's already in use, the same kind of tie. No walk loads a session.
  - Built in step 3: the fill's assertion (`window/routines.lua:758-761`, T176), the window-jump cancel with the landing recorded (A12, T198), and the tie fix (`history/routines.lua:279`, `:282`; T197, T288). Built in step 4: the session-load branch of `track_buffer` stores the saved time in the global history (`:301-307`, T20). What a load that goes through ends with doesn't depend on it: `initialise_crux_internals` then resets the window histories and puts the saved global history in place (`:216`, `:232`). Only a load that a throw stops before that keeps the branch's writes, and its window-history write still takes `history_index - 1`, which can tie (`:318`) **[code]**.
- **D20. Old model shapes.**
  - SPEC:51-63 has one `displacement_map` and a single `primary_buffer = filename|nil`. The code has two maps with `-swap` keys and a primary queue with `primary_enabled` (`window/data.lua:8-15`).
  - SPEC:686-692 has `jump_to_primary` writing both `dsm[current]` and `dtm[current]`. The code writes only `dtm[current-swap]` (`window/routines.lua:928`).
  - **Settled by Q2, Q3 and Q8:** the code wins, and SPEC's shapes are out of date. Q2 keeps the two kinds of ternary note and the primary jump's swap note, Q3 keeps the separate secondary map, and Q8 keeps the primary queue with its on/off switch.

**Cycling**

- **D10. The current slot during cycling.**
  - SPEC:194 says "only current slot changes". SPEC:385-407 has the current follow the cycle and `<M-f>` swap the cycled buffer with the secondary.
  - README:384 says "no matter how you cycle, the current slot buffer doesn't change". The code agrees **[run s03, s04]**.
  - While cycling, `<M-f>` jumps back to the start (A6 step 2) instead of swapping.
  - **Settled by Q1 and Q7:** the code and README:384 win. The current slot stays on the start until `<M-v>` (Q1), and the slot keys jump back to the current slot when the window isn't showing it (Q7). SPEC:194 and SPEC:385-407 are out of date.
- **D15. A checkpoint copy or a live reference.** `snapshot_origin` says it "stores a deep copy" (`history/routines.lua:466`), but it stores the live triquetra (`:472`) **[run s03]**.
  - **Settled (2026-10-20):** live is intended: the cycle's start is the window's current slot, so `<M-;><M-f>` mid-cycle lands on it even after a swap or a close moved it **[runs `t/pkB_d15_*.lua`]**. Only the docstring at `history/routines.lua:367-370` changes, in plain wording: "Mark the window's triquetra as the cycle's checkpoint. The checkpoint is the window's own triquetra, not a copy, so it always names the window's current slot."
  - The window-jump cancel returns the cycling window to this live start (A12).
- **D21. File-picker mode.** SPEC:906-909 says displacement is paused and normal mode comes back automatically after a pick. In the code `file_picker` is registered and never entered (`navigation/sm.lua:24`). STATUS:103 calls it "unused by design".
  - **Settled (2026-10-20):** keep it as scaffolding. A comment at `navigation/states.lua:8` says nothing enters it yet, and SPEC:906-909 is marked as not built. Explorers stay under the visiting rule. The pop-up's `<M-e>` picker (Q11) is unrelated; it shares the name only.

**Closed buffers and cleanup**

- **D13. Closed buffers reopening.** README:15 ("Closed buffers reopen when accessed through relationships") and STATUS:37, STATUS:382-392 say a closed slot reopens. The code prunes closed secondaries and primary entries because the check reads the wrong slot (`window/routines.lua:345`, `:401`) **[run s05, s06]**. The desk lists this (DESK:2470).
  - **Settled (2026-10-20):** a code bug. Each staleness check reads its own entry (DESK:2470), as the comment under each check says (`window/routines.lua:346-348`). README:15 stays as written; I4, T42 and T56 stand **[run `t/pkA_d13.lua`]**.
  - Built in step 1: each check reads its own slot or entry (`window/routines.lua:621`, `:648`, `:677`). T42, T56, T103 and T104 pass.
  - A file whose buffer went without events (a `noautocmd` wipe) goes on the closed stack at the stale pass, so its slots keep it too (A22, I4, T242).
- **D14. A second trigger for the new-file wipe.** The desk's repro stays on the new file and waits, so the cleanup tick wipes it, `bw!` from `history/routines.lua:678` (DESK:2446, DESK:3250). Navigating away instead wipes it sooner, at the **next `BufEnter`**, from `window/routines.lua:428` inside `cleanup_triquetras` (A21 step 5) **[run s09]**. Both triggers exist. DESK:1870 already lists that path (healing's missing-file wipe, `:417-449`) for removal, so the decided fix covers it; the bug entry just names only the timer.
  - **Settled (2026-10-20):** the decided fix already covers both triggers (DESK:1859, :1865, :1870). At the next desk sync, the bug entry (DESK:2446) gains the faster route and the dead window ("Sooner still, the next `BufEnter` anywhere wipes it…"), and its repro (DESK:3250) gains "Or skip the wait…" **[run `t/pkA_d14.lua`]**.
  - Built in step 1: both triggers are gone. No `cleanup_system` pass wipes (A22), and `cleanup_triquetras` doesn't check the current slot's file on disk (A21). T109 and T110 pass.
- **D16. Comment on `<M-.>`.** "go to most recent (first in list)" (`history/routines.lua:797`), while the code goes one step older. Known on the desk, and the code is right (DESK:2478).
  - **Settled (2026-10-20):** the one branch comment becomes `-- Otherwise go to most recent relative to the one deleted (next in list, wraps around)`, built from the author's words, "the most recent is relative to the one deleted". The other branch comment stays.
- **D22. The cleanup report.** STATUS:143-158 shows counts by category. The code notifies the total and lists the paths (`history/init.lua:58-87`).
  - **Settled (2026-10-20):** closed by archiving STATUS.

**Windows and documentation of the data**

- **D17. Window-jump history per tab.** `navigation/data.lua:9` ("Per-tab") and STATUS:115 (`[tabnr][to_win]`) describe a per-tab table. The code uses one flat table (`navigation/data.lua:42`, `navigation/routines.lua:54`).
  - **Settled (2026-10-20):** the flat table is intended. After a tab switch, `<M-,>` takes you back to the window you left in the other tab, as today **[run `t/pkA_d17.lua`]**. The author flattened it in 60540e7 (2025-07-20). Only the comment at `navigation/data.lua:9` changes: "Current window -> previous window mapping, one table across all tabs". STATUS:115 goes with STATUS.
- **D18. Storage documentation.**
  - STATUS:301 leaves out `bare` (`storage/states.lua:20`).
  - STATUS:311-321 gives the saved window entry as `[secondary, primary, ternary]`. The code writes `[current, secondary, primary_queue[], ternary, dtm, dsm]` (`storage/routines.lua:496-503`). The annotation at `storage/routines.lua:12-16` types `[3]` as `string|vim.NIL`, but it's an array.
  - Outside the listed sources, the project `CLAUDE.md` (now `archive/CLAUDE.md`) also has the old three-field shape.
  - **Settled (2026-10-20):** STATUS is archived. The annotation at `storage/routines.lua:12-20` is fixed to the six fields the code writes (current, secondary, the primary queue as a list, ternary, the ternary notes, the secondary notes; `:490-497`), with the example updated, in plain wording. The project `CLAUDE.md` is archived too, at `archive/CLAUDE.md` (it carried the old three-field shape, a code tree with directories that don't exist, and progress figures).
  - Built in step 4: the annotation lists the nine fields the entry has, the six above plus what the window shows, whether the primary is on and the window's own history, in plain wording, and the example has all nine (`storage/routines.lua:12-25`; S1, T134).
- **D23. "No missing functions".** STATUS:631-632 says every function that's called exists and works. Counterexamples:
  - `get_smart_basename` is nil (`init.lua:472`) **[run s16]**.
  - `ui_machines.winbar` doesn't exist (`ui/init.lua:112`, `:119`, `:151`).
  - The bufferline and indicator transitions aren't registered (`ui/init.lua:97-134`).
  - **Settled (2026-10-20):** the claim is archived with STATUS. The gaps stay bugs: `get_smart_basename` is nil (T120), and the missing winbar machine and bufferline transitions are on the desk (DESK:2482).
- **D24. STATUS's config example.** STATUS:477-498 shows `auto_save`, `save_interval`, `ui.winbar_enabled` and `cleanup_interval = 300 -- 5 minutes`. None of these match `configs.lua`.
  - **Settled (2026-10-20):** closed by archiving STATUS.
- **D25. Small comment slips in the code.**
  - "closed buffer filenames" (`history/data.lua:81`, `history/init.lua:107-109`), where the stack holds hashes.
  - "doesn't create its own state machine" (`window/init.lua:5`), while `window/sm.lua` creates one.
  - `LoopStates` documents `UPDATING "updating"` (`ui/states.lua:18-19`), where the state is `SELF "self"`.
  - The window machine (`window/sm.lua`) has four states (`showing_primary`, `showing_secondary`, `showing_ternary`, `showing_other`), no transitions, and nothing calls `to()` on it; `window/hooks.lua:12` requires it and never uses it. The author calls it an artifact of early modelling.
  - **Settled (2026-10-20):** the closed stack's comments reuse the author's own wording at `history/data.lua:14`, "Stack of closed buffer filehashes that can be reopened"; the loop annotation becomes `---@field SELF "self" Continuous update loop state for UI refresh`. The window machine goes: `window/sm.lua`, the four `SHOWING_*` constants in `window/states.lua`, and their requires (`window/init.lua:7`, `window/hooks.lua:10`, `:12`). The comment at `window/init.lua:4-5` is then true (T170).

**Today against Decided**

The sources differ here until the code catches up with the desk; each entry is settled.
- **D26. Windows showing something untracked.** README:332: the triquetra is cleaned, which matches the code. The desk's visiting rule keeps it (DESK:1785).
  - **Settled (2026-10-20):** the README follows the desk. Only README:332's middle sentence changes, and "tiquetra" is fixed: "When a window switches to a non-regular buffer then it will keep the triquetra associated to that window, and the current slot stays on the file you were on, so `<m-f>` brings you back to it. The winbar shows it like `main.lua ← [help]`." Built in step 3: README:332 reads so, and the code follows the visiting rule (A2).
- **D27. Requirements.** README:44-47 requires resession, cokeline, harpoon and openssl. The desk keeps cokeline required, makes harpoon optional, takes no session-manager dependency, and uses `libcrypto` (DESK:751, DESK:760, DESK:2126, DESK:2144).
  - **Settled (2026-10-20):** README:44-47 becomes: "neovim 0.12+"; "nvim-cokeline"; "openssl 3 (system installed, its libcrypto is used for encrypting the session files. Hashing is done with neovim's built-in `vim.fn.sha256`)"; "harpoon (optional, harpooned buffers are marked in the bufferline)"; "telescope.nvim (optional, used for adding files in the primary buffer pop-up)"; "a session manager (optional, resession.nvim is used in the examples below)". The lazy.nvim example's `dependencies` follows: cokeline in, harpoon out, and its comment goes.
  - The README's cokeline section ("The cavediver plugin can work without the bufferline…") was approved as: "The cavediver plugin can work without the bufferline, but it reduces the experience a lot. Cycling with `<m-n>` and `<m-m>` goes through cokeline, and it's what lets you visualise the visit history of all your buffers, so that you can know how you can end up to your current buffer." (typos "browsers" and "now" fixed). Its middle sentence no longer holds after A12's decision that cycling falls back without cokeline. **Settled (2026-10-20):** README.md:109-111 becomes "The cavediver plugin can work without the bufferline, but it reduces the experience a lot. Cokeline is what lets you visualise the visit history of all your buffers, so that you can know how you can end up to your current buffer."
- **D28. Session wiring.**
  - README:93-99 passes `vim.loop.cwd()` and wires only `pre_save` and `post_load`.
  - The desk passes the session name and the tab, reads the directory inside cavediver, and adds `pre_load` and `TabClosedPre` (DESK:758, DESK:775-792).
  - **Settled (2026-10-20):** README:67-105 becomes "Session manager setup". It keeps the author's two opening lines, then says what has to happen (`save_session(name)` before the editor is torn down, `load_session(name)` after the manager's restore, the outgoing session saved before a switch, a tab session saved before its tab closes), then the wiring for resession (the author's `buf_filter` kept, the four hooks from DESK:775-792), native sessions (`SessionWritePost`/`SessionLoadPost` with `vim.v.this_session`, and `:mksession!` before `:source`ing another) and no manager (`save_session()` on `VimLeavePre`, `load_session()` by hand).
- **D29. Session-file protection.** "XOR-obfuscated session persistence" (`init.lua:4`, STATUS:307) against AES-GCM (DESK:1541).
  - **Settled (2026-10-20):** the XOR docstrings (`storage/routines.lua:58`, `:61`, `:85`, `:86`) leave with the XOR code (DESK:1543). The header at `init.lua:4` changes in build step 5, together with the encryption, to "---hash-based buffer tracking, and encrypted session persistence." STATUS:307 goes with STATUS. No README line says XOR.

## 7. Candidate tests

Each test is tagged:
- **[char]**: a characterisation test of intended behaviour. It should pass today.
- **[target]**: the behaviour the bug fix or the desk wants. It fails today.
- **[today]**: pins today's behaviour where the desk has decided to change it. It passes today and is expected to flip when its paired [target] lands.
- **[Qn]**: on hold until question n is answered. After 2026-10-20 none are left. A test that an answer settled cites it as (Qn) instead.

The setups use `a.txt` … `f.txt` in a sandbox directory. T149 onwards came with the answers of 2026-10-20, and T177 onwards with the evening's decisions, most of them "Keep the older one", which has its own group. Each sits in its topic's group, so the numbers aren't in order. Expected values marked **[inferred]** were traced from the code and not run; values marked **[sim]** come from a variant, so the decided code should give them.

**Engine (M11)**
- T1 [char] `to()` on a transition with no bound hook throws from `to()` itself.
- T2 [char] A hook that errors is reported as "Hook '<name>' failed during transition a->b", the later hooks still run, and the state still changes.
- T3 [char] `sm:state()` inside a hook returns the state being left.
- T4 [char] Hooks run in class order. `to()` without a mode runs only `"*"` hooks; `to(…, m)` also runs hooks filtered to `m`.
- T5 [target] `off(from, to, name)` removes that hook from that transition and nothing else.
- T6 [char] Transition modes are one table shared by every machine: a mode registered on one machine can be named by a hook on any other, and `to(…, m)` on any machine accepts it (Q20).
- T7 [char] `sm.history` keeps every transition: after 1,000 transitions on one machine, its history holds all 1,000 (Q21).

**Identity, registry and tracking (M1–M3)**
- T8 [char] The hash of a plain path is the first 16 hex characters of `vim.fn.sha256(path .. "\n")`.
- T9 [char] A path containing `"`, `$HOME` or a backslash hashes to the first 16 hex characters of `vim.fn.sha256(path .. "\n")`.
- T10 [char] `:e` on an existing file registers it. Help, terminal and `scheme://` buffers aren't registered, and neither is otter's: it makes its buffers with `vim.uri_to_bufnr`, which leaves them unlisted, and listed-only tracking keeps them out (M3), not their `otter.*` name. A file you open yourself named `otter.lua` is tracked like any other.
- T11 [char] An entered No Name buffer is registered as `NONAME_<id>`, its id kept on the buffer (I16).
- T12 [char] Registering a second buffer under the same hash binds the hash to the newer buffer and drops the older one's reverse entry.
- T13 [char] An unlisted `buftype ""` buffer that a plugin creates and enters isn't registered.
- T14 [char] A buffer whose file isn't written yet stays registered after it's left and re-entered.

**History (M4)**
- T15 [char] After visiting a, b, c, `ordered.crux` is `c,b,a`.
- T16 [char] With `history_view = "window"`, the order in window 2 puts window 2's own visits first (the s17 sequence).
- T17 [char] Closing a window removes its `crux_internals.window` entry.
- T18 [char] `:vsplit` creates the new window's history entry along with its triquetra (I3).
- T19 [char] A visit is recorded in the history of the window that shows the buffer, not the focused one (for example, `win_execute` in another window).
- T20 [char] `track_buffer(h, t)` stores `t` in the global history.
- T149 [char] A property test over random visits, with `history_view` set to `"global"` and to `"window"`, across windows: after any visit, the visited buffer is leftmost in the bufferline order (`compare_buffers`). The author's check: two windows, back into window A, `:e e` gave `e=7 b=6 a=5 d=4 c=3` (Q4); with the tie fix the window view's rebuild gives its buffers one more time each, so it reads `e=8 b=7 a=5 d=4 c=3`, the same order. Under the window view it holds through the tie fix (T197). **[run, 2026-10-21]** recorded the view's rebuild without it tying two buffers on a window jump and on `:close` alike: `:e a`, `:e b`, `:vsplit`, `:close`, `:e a` gave a=4 b=4, and with the tie fix a=5 b=4 (T288).

**Triquetra lifecycle (M6, A2–A5)**
- T21 [char] A first `:e x` in a fresh window gives `{c=x}`.
- T22 [char] `:vsplit` gives the new window a fresh `{c=<shown>}`, not a copy.
- T23 [char] A float never gets a triquetra.
- T24 [char] An `acwrite` buffer shown in the window keeps the triquetra.
- T25 [char] Closing a window drops its triquetra and its UI cache.
- T26 [char] `:terminal` in a window with `{c=c s=b}` keeps its triquetra, and the terminal stays untracked (the visiting rule, A2). T27 covers coming back. **[run s15]** recorded the triquetra dropped, before the visiting rule.
- T27 [char] The window keeps `{c=c s=b}` while it shows the terminal, and `:e c` returns with its slots intact (the visiting rule).

**Plain navigation (A1)**
- T28 [char] `{c=a}`, `:e b` → `{c=b t=a}`, with no map entries.
- T29 [char] `{c=b t=a}`, `:e c` → `{c=c t=b}`, `dtm{b→a}`.
- T30 [char] Going to the secondary with `:e` swaps current and secondary and writes the notes `<M-f>` writes, when `dtm[T] ≠ S` (for `dtm[T] = S`, see T151): the buffer left gets `dsm[A-swap] = S` and `dtm[A-swap] = T` (D8, T191). Built in step 3.
- T31 [char] Going to the ternary with `:e` swaps current and ternary and doesn't write `dtm[current]`.
- T32 [char] A plain navigation that writes `dtm[A]` also deletes `dtm[A-swap]`.
- T33 [char] With `dtm[X] = A` and the ternary T ≠ X, `:e X` from A rewrites `dtm[X] := T`, with the "pre-jump ternary" warning.
- T34 [char] Navigation with secondary equal to ternary reports "Duplicates detected in current triquetra".
- T35 [char] Entering an untracked buffer, such as an `acwrite` buffer, leaves the slots alone (A2). For `:terminal` shown in the window, see T26 and T27.
- T151 [char] Q6 on plain navigation: `:e a`, `:e b`, `:e c`, `:e b`, `<M-f>`, `:e a`, `<M-f>`, then `:e a` again, which reaches the secondary by plain navigation. The ternary's note is rewritten to the buffer left (`dtm[b] := c`), and `<M-S-f>`, `<M-;><M-r>` then restores without throwing, giving `{c=b s=a t=c}` **[sim, variants `rt_q6` and `kt_rewrite_sec`]**. **[sim, the code before step 3]** recorded this route with no guard: `dtm[b]` stayed `a`, nothing warned, and the restore threw.
- T191 [char] (D8, "Keep the older one") `<M-f>` and plain navigation onto the secondary write the same notes: from `⦉c⦊ [d] ⟦b⟧`, either one gives `⦉c⦊ [b] ⟦d⟧` with the swap notes `dsm{d-swap>b}` and `dtm{d-swap>c}`, and no plain secondary note for d. T30 and T39 pin the same notes. Plain navigation **[sim `rt_cand_use`, variant `rt_c3kga`]**; `<M-f>` **[code]**, the same notes by the same function in the variant.

**`<M-f>` (A6)**
- T36 [char] `{c=c t=b}`, `dtm{b→a}`, `<M-f>` → `{c=c s=b}`, `dsm{b→a}`. The buffer doesn't change, and the message is "Ternary slot graduated" (Q3).
- T37 [char] With secondary and ternary empty and two buffers in history, `<M-f>` fills the secondary from `ordered[2]` without switching.
- T38 [char] With one buffer in history, `<M-f>` warns "insufficent history".
- T39 [char] `{c=c s=b}`, `<M-f>` → shows b, `{c=b s=c}`, `dsm{c-swap→b}`: the note a swap leaves is a swap note (T191). Built in step 3.
- T40 [char] With a ternary T, `<M-f>` writes `dtm[A-swap] = T` (Q2).
- T41 [char] When the window shows a buffer other than its current slot, `<M-f>` switches back to it and changes no slot.
- T42 [char] After `:bdelete` of the secondary's buffer and one more `:e`, the secondary still holds the closed hash, and `<M-f>` reopens it and takes it off the closed stack.
- T43 [char] After a cycle, `<M-f>` with secondary and ternary empty never puts the current buffer in the secondary.
- T44 [today] With the secondary closed and its file then deleted on disk, `<M-f>` warns "Removed secondary file not found in filesystem" and empties the slot. Paired with T45. Cleanup prunes a closed secondary whose file is gone at the next history event (A21), so `<M-f>` has to come before any.
- T45 [target] With the secondary's file deleted on disk, the pointer is kept and `<M-f>` says the file is missing (DESK:2022).
- T150 [char] Q6's ten keys, as the author ran them: `:e a`, `:e b`, `:e c`, `:e b`, `<M-f>`, `:e a`, `<M-f>`, `<M-f>`, `<M-S-f>`, `<M-;><M-r>`. The third `<M-f>` rewrites the ternary's note to the buffer it leaves (`dtm[b] := c`), and the restore doesn't throw: it gives `{c=b s=a t=c}` **[sim, variants `rt_q6` and `kt_rewrite_sec`]**.

**`<M-S-f>` (A7)**
- T46 [char] `{c=d s=b t=c}`, `<M-S-f>` → shows c, `{c=c s=b t=d}`, `dtm{d-swap→c}`.
- T47 [char] With no ternary, it warns "No ternary buffer to swap with." and nothing changes.
- T48 [char] A ternary closed with `<M-.>` is reopened by `<M-S-f>` and taken off the closed stack.
- T49 [char] The desk's sequence (`:e 1.txt`, `:e 2.txt`, `<M-n>`, `:bdelete`, `<M-S-f>`, `<M-S-f>`) throws nothing and leaves no duplicate slot. The reopen's `BufEnter` is slotted once the editor settles, so cleanup doesn't clear the ternary before the rename; the rename's missing guard for a nil hash is A7's bug.

**`<M-;><M-f>` (A8)**
- T50 [char] `{c=e s=d t=b p=[x]on}`, jump → shows x, `{c=x s=d t=e}`, `dtm{e-swap→b}`.
- T51 [char] When the primary is the ternary, the result equals `<M-S-f>`'s.
- T52 [char] On the primary already: "Already in primary buffer, no displacement performed." and no change.
- T53 [char] With an empty queue it acts as `<M-f>`.
- T54 [char] With a disabled primary it acts as `<M-f>` (Q10; README:31 changes).
- T55 [char] While cycling, with the window cycled away from the start, it returns to the start, keeps navigation `cycling`, and changes no slot (Q7).
- T56 [char] With a closed primary, the jump reopens it.
- T57 [today] With the primary's file deleted on disk, it throws "Primary buffer not found in filesystem". Paired with T58.
- T58 [target] With the primary's file deleted on disk, it says so and keeps the pointer.
- T153 [char] Q6 on the fallback: with the primary disabled, `{c=A s=S t=T}` and `dtm[T] = S`, `<M-;><M-f>` acts as `<M-f>` and rewrites `dtm[T]` to A before the swap.

**Primary keys (A9, A10)**
- T59 [char] On an empty queue `toggle_primary` gives `[a]on`; again gives `[a]off`; on another buffer it gives `[a]on` with the queue unchanged (Q8).
- T60 [char] `set_primary` on an empty queue gives `[a]on`; on b it gives `[b,a]on`; on b again it gives `[b,a]off`; on a it gives `[a,b]on`.
- T156 [target] The `toggle_primary` keymap's description no longer reads "Toggle current buffer as primary" (Q8).

**Restores (A11)**
- T61 [char] At b with `{c=b t=d}` and `dtm{b→a}`: restore ternary → `t=a`, `dtm{b→d}`; again → `t=d`, `dtm{b→a}`.
- T62 [char] Restoring a ternary equal to the secondary swaps the secondary and ternary contents.
- T63 [char] Restoring the secondary flip-flops: a second press brings back the secondary the first one replaced, and so on (P19). Each press writes the replaced secondary into the plain note `dsm[A]`, and the first press reads `dsm[A-swap]` when it's set and isn't the secondary, otherwise `dsm[A]`.
- T64 [char] With no entry, it warns "No ternary relationship found for restoration."
- T65 [char] When `dtm[A-swap]` is set and differs from the ternary, the restore uses it instead of `dtm[A]` (Q2).
- T66 [char] With the maps set so that the remembered value equals the slot, the restore throws "This is impossible. Remembered ternary is the same as current ternary." The assertion stays (Q13).
- T67 [char] (D9) A `-swap` entry pointing at a file that's closed and deleted on disk is skipped and kept: the restore uses the plain note (`a>b` gives `⦉b⦊ [a]`), flip-flops with it, and the `-swap` entry is still there afterwards.
- T173 [char] (D9) A note pointing at a file deleted on disk whose buffer is still open restores it and flip-flops with it (`⦉f⦊ [a]`, then `⦉d⦊ [a]`, then `⦉f⦊ [a]`).
- T174 [char] (D9) When both of a buffer's notes point at closed files deleted on disk, the restore says so, changes no slot, and keeps both notes.
- T68 [char] An unknown hash in a map doesn't make a restore throw.

**"Keep the older one": the restore errors (M7, A1, A6–A8, A11, A13, I23)**

These pin the decision of 2026-10-20 evening. The states are the ones the variants gave.
- T177 [char] ("Keep the older one") The round trip onto the secondary and back: `:e a`, `:e b`, `:e c`, `<M-f>` (b graduates), `<M-f>` (to b), `<M-f>` (back to c), then `<M-;><M-t>` on c doesn't throw. It says "No secondary relationship found", since c has no secondary from before; the window stays `⦉-⦊ [c] ⟦b⟧` with `dsm{b-swap>c b>a c-swap>b}` **[sim `rt_sec_round`, variants `rt_c3kga` and `kt_rewrite_sec`]**.
- T178 [char] ("Keep the older one", Q3) T177's keys, then one more `<M-f>` back to b: `<M-;><M-t>` on b brings back a, b's secondary from before (graduation's copy, Q3): `⦉-⦊ [b] ⟦a⟧`; again, `⦉-⦊ [b] ⟦c⟧` **[sim `rt_sec_round_older`, variant `rt_c3kga`]**.
- T179 [char] (D8) The same round trip by plain navigation: `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e b`, `:e d`, then `<M-;><M-t>` on d says "No secondary relationship found". With D8's notes written as a plain note (`dsm[A] := S`, as in `rt_base`), it throws **[sim `rt_cand_round_e`, variants `rt_base`, `rt_c3kga` and `kt_rewrite_sec`]**. The notes along the way are A1's round-trip example.
- T180 [char] ("Keep the older one") After a round trip, the buffer's older secondary comes back: `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e b`, `:e e`, `<M-f>`, `<M-f>`, `<M-f>` give `⦉b⦊ [d] ⟦e⟧`. d remembers b, its secondary before e: `<M-;><M-t>` on d gives `⦉e⦊ [d] ⟦b⟧` ("Restored secondary slot to … b"), and again `⦉b⦊ [d] ⟦e⟧`. This needs the fallback to compare with the secondary: d's swap note names e, the secondary, so the restore reads d's plain note, b **[sim `rt_keep_partner`, variants `rt_c3kga` and `kt_rewrite_sec`]**.
- T181 [char] ("Keep the older one") With nothing older on record, a stale secondary note is dropped: `:e a`, `:e d`, `:e c`, `<M-f>` (d graduates, `dsm{d→a}`), `:e a`, `<M-f>` (to d, whose secondary is now a). d's note naming a is dropped, and `<M-;><M-t>` says "No secondary relationship found" **[sim `rt_route_grad`, variants `rt_c3kga` and `kt_rewrite_sec`]**.
- T182 [char] ("Keep the older one") The check on other arrivals, secondary map: `:e a`, `:e c`, `<M-S-f>`, `<M-S-f>`, `:e d`, `<M-f>`, `<M-;><M-f>`, `<M-;><M-r>`, `<M-S-f>`, `<M-;><M-f>`, `:e c`, `<M-;><M-t>` (the primary queue is empty, so `<M-;><M-f>` acts as `<M-f>`). At the last `:e c`, c's plain secondary note names a, the window's secondary, and c has nothing older on record, so the note is dropped and `<M-;><M-t>` says "No secondary relationship found" **[sim `rt_resid_nav`, variants `rt_c3kga` and `kt_rewrite_sec`]**.
- T183 [char] ("Keep the older one") A stale secondary note is rewritten to the buffer's swap note when that names another buffer: `:e a`, `:e e`, `<M-f>`, `:e d`, `<M-;><M-f>`, `<M-S-f>`, `<M-;><M-f>`, `<M-f>` give `⦉a⦊ [e] ⟦d⟧`. Cycle to a (the ternary) and `<M-v>`; cycle to d (the secondary) and `<M-v>`: d's note `d>a`, naming the secondary a, becomes d's swap note, `d>e`. Then `<M-f>`, cycle to d and `<M-v>`, and `<M-;><M-t>` gives `⦉a⦊ [d] ⟦e⟧`, again `⦉e⦊ [d] ⟦a⟧`. Where the stale note is dropped instead, both presses say "No secondary relationship found" **[sim `kt_secgain`, variants `kt_rewrite_sec` and `kt_rewrite`]**.
- T184 [char] ("Keep the older one", Q3) With the secondary empty and the ternary b holding an old swap note `dsm[b-swap]` (set it directly: with the decided cleanup, no key seems to empty a secondary once it's set **[inferred]**), `<M-f>` graduates b with `dsm[b] := dtm[b]` and clears `dsm[b-swap]`; `<M-f>` to b then `<M-;><M-t>` brings back `dtm[b]`'s buffer, as Q3 intends **[sim `rt_q3_oldswap`, variant `rt_c3kga`]**.
- T185 [char] ("Keep the older one") Where the ternary stays put, a stale ternary note becomes the ternary's own note: `:e a`, `:e c`, `:e e`, `:e b`, `<M-f>`, `:e c`, `<M-S-f>`, `<M-f>` give `⦉c⦊ [e] ⟦b⟧`, and e's note `e>c`, naming the ternary c, becomes c's own note, `e>a`. `<M-;><M-r>` then gives `⦉a⦊ [e] ⟦b⟧`, and again `⦉c⦊ [e] ⟦b⟧` (flip-flop). Without the check the restore throws; with navigation's second case taken as worded it still throws; with a drop it says "No ternary relationship found" **[sim `rt_bonus1`, variants `kt_rewrite`, `kt_literal` and `rt_tb`; the same under `kt_rewrite_sec`]**.
- T186 [char] ("Keep the older one") Where the ternary changes, the check acts as navigation's does, and drops when there's nothing older: `:e a`, `:e d`, `:e c`, `<M-;><M-f>` (an empty queue, so d graduates), `<M-f>`, `:e a`, `<M-S-f>` give `⦉a⦊ [d] ⟦c⟧`. d's note `d>a` names the new ternary a, and a has no plain note, so it's dropped: `<M-;><M-r>` says "No ternary relationship found". Coming back by `:e d` instead of `<M-S-f>` gives the same through navigation's own check **[sim `rt_bonus2`, `rt_bonus2_nav`, variant `kt_rewrite`; the same under `kt_rewrite_sec`]**.
- T187 [char] ("Keep the older one") A primary jump uses navigation's second case: `:e a`, `:e b`, `<M-;><M-c>`, `:e e`, `:e a`, `<M-;><M-f>` give `⦉a⦊ [b] ⟦-⟧` with `p=[b]on`, and b's note `b>a`, naming the new ternary a, becomes e, the pre-jump ternary. `<M-;><M-r>` gives `⦉e⦊ [b] ⟦-⟧`, and again `⦉a⦊ [b] ⟦-⟧` **[sim, variant `kt_rewrite_sec`]**.
- T188 [char] ("Keep the older one") Where the ternary's own note is the window's secondary, the restore exchanges the ternary and the secondary: `:e a`, `:e b`, `:e e`, `<M-f>`, `<M-f>`, `:e a`, `:e d`, `:e e`, `:e b`, `<M-;><M-t>`, `:e e` give `⦉b⦊ [e] ⟦a⟧` with `dtm{a>b b>a}`. Then `:e a`, plain navigation onto the secondary: Q6's guard rewrites b's note to e, the swap gives `⦉b⦊ [a] ⟦e⟧`, and a's note `a>b`, naming the ternary, becomes the ternary's own note, e, which is the window's secondary. `<M-;><M-r>` gives `⦉e⦊ [a] ⟦b⟧`, and again `⦉b⦊ [a] ⟦e⟧`. This pins the cost that came with "the ternary's own note" (5% of rewrites in the walks) **[sim, variant `kt_rewrite_sec`]**.
- T189 [char] (Q13) The route the tested fix leaves: `:e a`, `:e b`, `:e c`, `<M-f>`, `<M-f>`, `<M-f>`, `:e a`, `<M-f>` give `⦉c⦊ [b] ⟦a⟧`, with b's ternary note `b>a` and its secondary swap note `b-swap>c`. `<M-;><M-t>` brings back c, which is the ternary, so the two slots exchange: `⦉a⦊ [b] ⟦c⟧`, and b's ternary note now names the ternary. `<M-;><M-r>` must not throw. Under the first tested fix it throws "Remembered ternary is the same as current ternary" **[sim, variant `kt_rewrite_sec`]**. With the decided check at the exchange, b's note becomes a's own note; a has none, so it's dropped and `<M-;><M-r>` says "No ternary relationship found" **[sim, variant `ex_a`]**.
- T190 [char] I23 as a property test, alongside T154: random walks over `:e` on five files, `<M-f>`, `<M-S-f>`, both restores, cycling picks, `<M-;><M-c>` and `<M-;><M-f>`, in one window and across windows, with `history_view` set to `"global"` and to `"window"`. After every action, for the current buffer and each map, the note a restore would read doesn't name that slot's occupant. In the tested fix's walks it broke at 11 of 75,000 steps, each right after a secondary restore's exchange or carried on from one (T189) **[sim, variant `kt_rewrite_sec`, seeds 7 and 11]**.
- T192 [char] ("Keep the older one") `rename_hash_in_triquetras(old, new)` moves `dsm[old-swap]` to `dsm[new-swap]` and renames values in both maps, as it already does for `dtm[old-swap]` (`window/data.lua:149-152`). Set it up directly, or with a No Name buffer that holds both kinds of secondary note, closed and then reopened by `<M-f>` **[code]**.
- T193 [char] (D9) The missing-file rule on the secondary map: `:e f`, `:e b`, `<M-f>` (f graduates), `<M-f>` (to f), `:e e`, `<M-f>` (to b) give `⦉f⦊ [b] ⟦e⟧` with `dsm{b-swap>f b>f}`. After `:bdelete f` and deleting f.txt on disk, `<M-;><M-t>` on b says the file is missing, changes no slot, and keeps both notes, as T174 does on the ternary map. With the missing-file branch D9 replaces, it clears `b>f` and then stops on `b-swap>f` at every press **[sim `rt_sec_missing`, variant `rt_c3kga`]**.

**Cycling (A12–A14)**
- T69 [char] `<M-m>` from normal sets navigation `cycling` and history `detached`, notifies "Checkpoint saved", moves the window to another buffer, and leaves `c` unchanged.
- T70 [char] Further steps change neither the slots nor the history order.
- T71 [char] With one buffer in history, `<M-m>` enters cycling without moving.
- T72 [char] `{c=e s=c t=d}`, cycle to b, `<M-v>` → `{c=b s=c t=d}`. The ternary isn't updated by the pick (Q9); the note it adds is T155.
- T73 [char] Cycling to the secondary and pressing `<M-v>` swaps them, with no map writes.
- T74 [char] Cycling to the ternary and pressing `<M-v>` swaps them, with `dtm{start-swap→ternary}`.
- T75 [char] Pressing `<M-v>` on the cycle's start changes no slot; navigation goes back to `normal` and history to `attached`.
- T76 [char] `<M-v>` in normal mode does nothing.
- T77 [char] `<M-f>` while cycled away from the start switches back to the start and stays `cycling` (Q7).
- T78 [char] `<M-S-f>` while cycling, with the window on its current slot, swaps the ternary and stays `cycling` (Q7).
- T195 [char] (D15) The cycle's start is the window's current slot, live: `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e c` give `⦉d⦊ [c] ⟦b⟧`. `<M-n>`, `<M-S-f>` (back to the start), `<M-S-f>` again (a real swap on the start: `⦉c⦊ [d] ⟦b⟧`), `<M-n>`, then `<M-;><M-f>` returns the window to d, the current slot, not c; navigation stays `cycling` **[run `t/pkB_d15_swap_live.lua`]**.
- T196 [char] (P18) While cycling, with the window back on its current slot, `<M-f>` and `<M-;><M-r>` do their normal job, notes included: set up with `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e c` (`⦉d⦊ [c] ⟦b⟧`, with b's note `b>a`), then `<M-n>` and a first `<M-f>` that only takes the window back to c, a second `<M-f>` gives `⦉d⦊ [b] ⟦c⟧` with the secondary swap note `c-swap>b` (T191; the run below recorded the plain note `c>b`, before it), and `<M-;><M-r>` then gives `⦉a⦊ [b] ⟦c⟧`; navigation stays `cycling` throughout **[run `t/pkB_cycle_keys.lua`]**.
- T175 [char] (A12) Cycling in win1, then `<C-w>p` to win2: win1 shows its start again, navigation is `normal`, history is attached, and nothing was recorded for the cycled-to buffer. Then `:e d` in win2 moves win2's slots and records d.
- T176 [char] (D11) With an empty secondary and no ternary, `<M-f>` fills from the ordered list's second entry, and throws if the first entry isn't the window's current buffer.
- T197 [char] (D11) Under `history_view = "window"`, after `:e a`, `:e b`, `:vsplit`, `<C-w>p`, `:e c`, `:vsplit`, the ordered list's first entry is the window's current buffer on every run (no tie), and `<M-f>` doesn't trip the fill assertion.
- T198 [char] (A12) `:e a`, `:vsplit`, `:e c`, `<M-m>`, `<C-w>p`: the cycle in the second window is cancelled (it's back on c), the landing in the first window is recorded (the ordered list starts with a), and `<M-f>` there fills c without tripping the fill assertion.
- T199 [target] (A26) With no assertion, the recorder writes no file and opens no buffer, and the ring never holds more than N steps.
- T200 [target] (A26) When the restore assertion fires, a file appears under `stdpath("state")/cavediver/` and a scratch buffer opens, both holding the last steps as rows: action or event, window, `⦉t⦊ [c] ⟦s⟧` and notes, ending at the failing step.
- T201 [target] (A26) A dumped file replays in the sandbox to the same assertion.
- T202 [target] (A26) A dump starts with a snapshot of the state at the ring's first step; replaying snapshot plus steps reproduces every row.
- T203 [target] (A26) A planted rule break dumps at the next step: with c current in one window and b its ternary, c's ternary note is set to b by hand, and a step in the other window (`:e x`) produces one dump. The break is planted because every real route into one is a route the decided fixes remove; the slot exchange, the first route used here, stops breaking the rule once its fix lands (the author, 2026-10-21: "plant the break instead of %1").
- T204 [target] (A26) A session load and a cleanup re-point appear in the dump as steps tagged `load` and `timer`.
- T205 [target] (A26) A failure that repeats (a highlight callback throwing on every redraw) gives one dump, and the dump window is neither recorded nor tracked: its buffer is `nofile` and unlisted, with no hash, no triquetra and no place in the bufferline, and after a visit to its window, a second, different failure (a hook bound by hand to fail) dumps steps that never name that window or its buffer.
- T333 [target] (A26) A dump opens its scratch buffer only once the editor settles, and names files by alias and basename, never by full path: on T200's route, no buffer is added inside the failing call, the scratch buffer is there once it settles, and neither it nor the file holds the project's directory, while both name `c.txt`. The single assertion helper is checked by what it does: every "shouldn't happen", the hook-failure catch included, dumps (T275).
- T206 [char] (I23) `:e a`, `:e e`, `:e d`, `<M-S-f>`, `:e b`, `:e d`, `<M-n> <M-v>`, `<M-f>`, `:e b`, `<M-f>`, `:e e`, `<M-m> <M-m> <M-v>`, `<M-;><M-t>`: b's stale note becomes e's own note, d; `<M-;><M-r>` gives `⦉d⦊ [b] ⟦a⟧`, and again `⦉e⦊ [b] ⟦a⟧`.
- T171 [char] (A12) With no cokeline installed, `<M-n>` and `<M-m>` step through cavediver's ordered history in the same directions as with cokeline, and `<M-v>` picks as usual. **[run s21]** recorded the step only printing, before the fallback, and navigation staying in `cycling`.
- T79 [char] Through the real cokeline order, `<M-n>` steps left, toward newer buffers, and `<M-m>` steps right, toward older ones (Q19).
- T152 [char] Q6 on a cycling pick of the secondary: with `{c=A s=S t=T}` and `dtm[T] = S`, cycling to S and pressing `<M-v>` gives `{c=S s=A t=T}` and rewrites `dtm[T]` to A. The guard's warning comes with the rewrite: the conflict is real and the warning isn't spurious (A6). With the guard after the swap, it warns "Avoided conflict…" and `dtm[T]` stays S **[inferred]**.
- T172 [char] (Q9) `:e a`, `:e b`, `<M-S-f>` (b gets `dtm[b-swap]=a`), `:e c`, `:e d`, `:e e`, cycle to b, `<M-v>`: `dtm[b] = e` and no `dtm[b-swap]`; `<M-;><M-r>` gives `t=e`, again `t=d`, again `t=e`.
- T155 [char] `{c=e s=c t=d}` with no `dtm[b-swap]`: cycle to b, `<M-v>` → `{c=b s=c t=d}` and `dtm[b] = e`. Then `<M-;><M-r>` brings the start back: `{c=b s=c t=e}`, with `dtm{b→d}` by the flip-flop (Q9).

**Closing and reopening (A15, A16)**
- T80 [char] With order `f,e,d`, `<M-.>` on f lands on e, pushes f on the closed stack, and leaves f in the ternary as a closed hash.
- T81 [char] On entry i > 1 it lands on i + 1, and on the oldest it lands on the newest.
- T82 [char] It refuses with a modified named buffer, a buffer shown in two windows, or a single entry, each with its warning and nothing changed.
- T83 [char] On a modified No Name buffer it closes it and caches its lines, filetype and cursor. `delete_buffer` switches the window away before the wipe, so it keeps the cursor on the buffer first (`vim.b[bufnr].cavediver_cursor`), and the cursor doesn't come back as `{1,0}` (bug, found 2026-10-21; the author: "Bug: keep the cursor").
- T84 [char] In `:help` it doesn't throw. What it does instead is T164–T167 (Q17).
- T85 [char] `<M-.>` on a file keeps the buffer's marks for when it's reopened (`:bdelete`).
- T86 [char] `<M-S-w>` reopens the newest closed buffer, and it becomes current with the old current in the ternary.
- T87 [char] `<M-S-w>` with an empty stack warns "No closed buffers to reopen."
- T88 [char] A No Name buffer closed with text comes back with the same lines and filetype.
- T89 [target] `<M-S-w>` on a missing file says so and leaves the entry on the stack.
- T90 [char] A reopened No Name buffer gets its cursor in its own window, with no "Invalid cursor line".
- T91 [char] After a No Name buffer is reopened, every slot and map entry that held its old hash holds the new one.
- T162 [target] (Q15) I22: pushing a hash that's already on the closed stack (for example, `track_closing_filehash_force` twice) leaves it on the stack once, as the newest entry. With pools: closing `notes.md` in two tabs' pools and merging both entries leaves one, the newer.
- T164 [char] Q17, a visiting window: in a window with `{c=a s=b}` that's visiting an untracked buffer (a `nofile` scratch, or help shown with `:buffer`), `<M-.>` closes the visited buffer, and the window shows a with `{c=a s=b}` intact (A2, A15, T27).
- T165 [char] Q17, a window born untracked: `:e a`, `:help`, then `<M-.>` in the help window. The help buffer is closed, Neovim closes the help window, nothing throws, and a's window and triquetra are unchanged.
- T166 [char] Q17, the only window: `:help`, `:only`, `<M-.>`. The help buffer is closed, nothing throws, and the window shows what Neovim picks.
- T167 [char] Q17, a running terminal: `<M-.>` on a `:terminal` whose job is still running refuses with a message, and the terminal stays.
- T336 [char] (A15, A1) `<M-.>` lands by navigation, before the close: `:e a`, `:e b`, `:e c`, `<M-.>` give `⦉c⦊ [b] ⟦-⟧` with no "Healed the triquetra…" notice. The close waits for the editor to settle, after the switch's arrival (A15 step 3). Found by the step 3 spec pass, 2026-10-23: with the arrival settled and the delete not, the delete's cleanup re-pointed the window with that notice on every close.

**Windows (A3, A17)**
- T92 [char] `<M-,>` toggles between the last two windows.
- T93 [char] With no previous window it warns "No valid previous window to toggle to."
- T94 [char] `<M-,>` skips a previous window whose filetype is `minimap`.
- T194 [char] (D17) One jump table serves every tab: tab 1 with two windows (`:e a`, `:vsplit`, `:e b`), then `:tabnew`, `:e c`, `:vsplit`, `:e d`. Back in tab 1 (`:tabnext 1`), `<M-,>` goes to d's window in tab 2, the window just left, and `<M-,>` there comes back **[run `t/pkA_d17.lua`]**.

**Primary queue window (A18)**
- T95 [char] With an empty queue, no window opens and the message is "No primary buffer history available."
- T96 [char] Reordering the lines and `:w` reorders the queue.
- T97 [char] `<CR>` on line 2 makes that file `p[1]` and closes the window.
- T98 [char] A typed path to an unloaded readable file is registered, queued, and pushed on the closed stack.
- T99 [char] With a mix of valid and invalid lines, the valid ones are saved and the rest reported (Q11).
- T100 [char] `q` and `<C-c>` save, then close the window (Q12).
- T101 [today] Saving with the first row unchanged re-enables a disabled primary. Paired with T158 (Q10).
- T158 [target] A save switches the primary on only when the first row changed (Q10). Paired with T101.
  - `p=[b,a]off`, reorder the lines to `a`, `b`, `:w` → `p=[a,b]on`.
  - `p=[b,a]off`, delete the `a` line, `:w` → `p=[b]off`.
  - `p=[b,a]on`, delete the `a` line, `:w` → `p=[b]on`.
- T159 [target] `<M-e>` in the primary queue window, with the picker provider stubbed (Q11):
  - One file picked, the cursor on an empty line: the path fills that line.
  - One file picked, the cursor on a non-empty line: the path goes on a new line after it, and the existing line is unchanged.
  - Two files picked: both paths appear, and no non-empty line changes.
  - Nothing is saved until `:w`, which validates the lines as usual.
- T160 [target] With no picker available, `<M-e>` gives a message and changes no line. `<M-e>` isn't mapped outside the primary queue window (Q11).
- T161 [target] The window's `q` and `<C-c>` mappings are described as "Save and close" (Q12).

**Deletes, renames and cleanup (A19–A22)**
- T102 [char] `:bdelete` of the ternary's buffer keeps the ternary as a closed hash.
- T103 [char] `:bdelete` of the secondary's buffer keeps the secondary (I4).
- T104 [char] `:bdelete` of a primary entry's buffer keeps it in the queue (I4).
- T105 [char] Closing an empty No Name buffer doesn't push it on the closed stack.
- T106 [char] `:file new.lua` and `:saveas new.lua` keep unsaved edits.
- T107 [char] After a rename whose old file is gone, every reference to the old hash follows to the new one, and nothing is pushed on the closed stack.
- T108 [char] When a window shows registered buffer X while its current slot's buffer is gone, cleanup sets `c := X`.
- T109 [char] `:e brandnew.txt`, type a line, `:e a.txt`: the brandnew buffer still exists with its text and stays tracked (I12).
- T110 [char] A file deleted on disk while shown stays shown and tracked after a 4.6 s wait.
- T111 [char] `:bdelete` of the shown buffer lands that window, not the focused one, on ternary → secondary → primary → most recent.
- T112 [char] Opening a closed file again with `:e` takes it off the closed stack (`track_buffer`).
- T113 [char] A stale registration with a copy reloaded under `noautocmd` re-points to the copy and wipes nothing.
- T114 [target] A closed entry whose file is gone from disk stays on the stack.
- T163 [char] When cleanup re-points a window's current slot to the registered buffer X the window shows (A21 step 1), with X outside the slots, `{c=A s=S t=T}` becomes `{c=X s=S t=A}`, as plain navigation would. Set it up by showing X without a `BufEnter` (`noautocmd`) after A's buffer is gone (Q18).

**UI (M12)**
- T115 [char] For `{c=e s=c t=d}`, the winbar holds these pieces in order (seen in run s14): `%#WinbarBufnrTernary#⦉<d>⦊ `, then `%#WinbarBufnrCurrent#[<e>] `, then `%#WinbarFilenameCurrent#e.txt`, then `%#WinbarBufnrSecondary#⟦<c>⟧ `, then `%#WinbarFilenameSecondary#c.txt`. `<x>` stands for the buffer number of x.
- T116 [char] A closed ternary is shown as `⦉ … name ⦊` with no buffer number.
- T117 [char] When the current buffer is the primary, it's shown as `⦉N⦊` in `WinbarBufnrPrimary`.
- T118 [char] A slot closed with `:bdelete` shows its basename, not its full path.
- T119 [target] `get_buffer_relationships` doesn't throw when current = primary, or it's gone (Q16).
- T120 [target] `require('cavediver').get_smart_basename` is a function.
- T121 [char] `compare_buffers(a, b)` is true when a was visited more recently than b; `bufnr_is_displayed` is true for tracked buffers and false for help.
- T122 [char] With 40 tracked buffers, `bufnr_is_displayed` is true for all 40 (Q5).
- T123 [target] `hide_bufferline()` and `show_bufferline()` don't throw.
- T124 [char] While cycling, `get_theme_bg_color(true)` returns `colors.cokeline.bg.detached.focused`.
- T170 [target] (D25) The engine has no machine named `window`; `require('cavediver.engine'):list()` gives the other six.
- T169 [target] (D3) The `desc` of the mapped keys: `toggle_primary` "Switch the primary on or off", `close_buffer` "Close the current buffer", `open_primary_buffer_history` "Open the primary queue"; no two keys share a description.
- T168 [target] (D2) While cokeline is picking, the pick letter's colour is `colors.cokeline.is_picking_close` (closing) or `colors.cokeline.is_picking_focus` (focusing) from the config; setting either changes the letter's colour.

**Setup (A25)**
- T125 [char] `setup()` with no argument works and uses the defaults.
- T126 [char] `require('cavediver')` without `setup()` creates no autocmds.
- T127 [char] Calling `setup()` twice leaves one set of autocmds and timers.

**Invariants**

These are property tests over random action sequences, like the desk's fuzzing:
- T128 [char] I1: no duplicate among a triquetra's current, secondary and ternary.
- T129 [char] I2: every hash referenced anywhere has a path.
- T130 [char] I3: every triquetra has a history entry.
- T131 [char] I12: no buffer with unsaved changes is ever wiped by cavediver. Wrap `vim.cmd` and `nvim_buf_delete`.
- T132 [char] I13: a slot action switches only the target window's buffer.
- T133 [char] I11: `ordered.crux` is sorted, newest first, and holds only registered open buffers after any non-cycling action.
- T334 [char] (I14) A save never throws on cavediver's own data: random walks over the one-window, several-window and closing mixes (`:enew`, `<M-.>`, `<M-S-w>`, a new file with text) call `save_session(cwd)` after every action, and no call throws. The save hook is critical (I21), so a throw would reach the session manager's save. A read-only session directory, an environment failure, does throw, which shows the check catches one.
- T335 [char] (Q13) No key raises over random walks: T190's walks (one window and several, under both views) count every key that throws, and none does. Every route that reaches a throw, an assertion included, is a bug to hunt (Q13). It found `reopen_filehash` failing on a No Name buffer with nothing cached, an empty start buffer closed while a slot held it, which an empty No Name close now takes out of the slots (M5).
- T154 [char] No restore throws: `<M-;><M-r>` and `<M-;><M-t>` never throw "Remembered … is the same as current …" (Q13). Random walks with Q6's fix still found the ternary restore throwing 13 times in 1,500; those routes were traced to arrivals that skip the stale-note check in navigation, and with "Keep the older one" on both maps the walks found none **[sim, variant `kt_rewrite_sec`]**. One constructed route threw under that fix, and the check at the exchange closes it (T189).
- T157 [char] (Q14) I19, A9: on an empty queue that's switched on, one `<M-;><M-x>` gives `p=[A]on`. **[run s19]** recorded it giving `p=[A]off`, before the fix. The test sets the empty, switched-on state directly: s19's route, deleting the open primary's file on disk, keeps the primary in the queue (A21) **[inferred]**.

**Sessions (S1, S2)**

Every one of these runs in a fresh process (see the appendix).
- T134 [char] `save_session(cwd)` writes the keys `paths`, `outsiders`, `buffers`, `windows`, `closed` and `noname_content`, with `windows[i] = [c, s, p[], t, dtm, dsm, shows, on, history]`: nine fields, `[7]` the hash of the buffer the window shows, `[8]` false with the primary off, `[9]` a table, and the shown file's path in `paths`, not in clear (S1).
- T135 [char] A round trip with every slot buffer restored and loaded gives back the same slots and maps.
- T136 [char] `primary_enabled = false` survives a round trip.
- T137 [char] `load_session` after a `save_session` in the same process goes through and ends `idle`.
- T138 [char] `load_session` from `idle` tears down and loads.
- T139 [char] A slot whose buffer comes back unloaded (`badd`) keeps its value after load.
- T140 [target] A save with a No Name current slot succeeds and reopens the buffer at load, hidden and modified.
- T141 [char] A save with a `:vsplit` window that has no visits succeeds.
- T142 [char] Two windows, one showing a No Name buffer: after save and load each window gets its own entry.
- T143 [char] A save into a read-only directory throws to the caller.
- T144 [target] A file that fails the integrity check gives the notification and a fresh start.
- T145 [char] Three `load_session` calls in one batch load once.
- T146 [target] A save never wipes a buffer or changes what a window shows, an oil window included. Its no-wipe half holds today and has its own [char] case; the oil half, a save leaving an oil window on its oil buffer, waits for the saved format's work (oil coming back as oil, S2).
- T147 [char] With no file, a load gives every window `{c=<shown>}` and an empty closed stack.
- T148 [char] After switching sessions, the outgoing No Name text isn't in the incoming file.

**Doc checks**

The settled doc and comment changes, which a test can't hold. Each is checked by reading the file once the change is made.
- README: the two primary keys at README:319-320 the right way round (D1); the defaults block copies `configs.lua`, missing keys included, and `cleanup_interval` says milliseconds (D2); README:31 says a disabled primary makes `<M-;><M-f>` act like `<M-f>` (D5); README:28 says a pop-up save keeps the good lines and reports the bad ones (D6); README:332's middle sentence and "tiquetra" (D26); README:44-47's requirements and the lazy.nvim `dependencies` (D4, D27); README.md:109-111, the cokeline paragraph (D27); README:67-105, "Session manager setup" (D28).
- Keymap and annotation text: `cycle_select`'s annotation at `configs.lua:10` copies "Select cycling buffer and attach history" (D3); the descriptions themselves are T156, T161 and T169.
- Comments and docstrings: the checkpoint docstring at `history/routines.lua:451-454` (D15); the `<M-.>` branch comment at `history/routines.lua:785` (D16); `navigation/data.lua:9`, one jump table across all tabs (D17); the saved-entry annotation at `storage/routines.lua:12-25`, nine fields (D18); `navigation/states.lua:8`, nothing enters `file_picker` yet (D21); the closed-stack comments at `history/data.lua:81` and `history/init.lua:107-109`, and the loop state annotation at `ui/states.lua:18-19` (D25); the header at `init.lua:4` and the XOR docstrings at `storage/routines.lua:68`, `:71`, `:95`, `:96`, in build step 5 (D29).
- The engine (Q20): the class declares the shared `transition_modes` table, the factory comment at `engine/init.lua:18` stops implying modes are per machine, and the per-machine wording at `helpers.lua:260` and `:278` is reworded or dropped.
- `ui/routines.lua:405`: the meaningless 30 in `math.max(#ordered, 30)` goes (Q5).
- The old spec: SPEC:906-909 is marked as not built (D21).
- The desk, at its next sync: DESK.md:2126 and the Dropped line at DESK.md:3146 narrowed to the cokeline fallback (A12); the bug entry at DESK.md:2446 and its repro at DESK.md:3250 gain the faster trigger (D14).

**Negative cases (T207–T249)**

Each checks that something doesn't happen, or that a bad or impossible action is refused or handled without harm, and cites the claim it comes from.
- T207 [char] (P5) A `nofile` scratch entered in a tracked window isn't registered (M3). Help, terminal, `scheme://` and otter buffers are T10; the quickfix list is T217.
- T208 [target] (P10, I17) Notes follow along: `:e a`, `:e b`, `:e c`, `:enew` (an empty No Name N), `:e b`, `:e d` leave N only in the notes (`N>c`, `b>N`). After `:bwipeout` of N, which pushes nothing (M5), no note names N. Today both notes stay (M7: the maps are never pruned), and they keep N's path (I2).
- T209 [char] (P14) The secondary changes only when you act: from `⦉-⦊ [c] ⟦b⟧` (`:e a`, `:e b`, `:e c`, `<M-f>`), `:e d`, `:e e`, `:e a`, two cycle steps, `<M-;><M-f>` and `<M-v>` on the start, then `:vsplit` and `<C-w>p` back, leave the secondary on b: `⦉e⦊ [a] ⟦b⟧`.
- T210 [char] (P17) Every window is independent: with window 1 on `⦉c⦊ [d] ⟦b⟧` and `p=[d]on`, `:vsplit`, then `:e e`, `:e a`, `<M-f>`, `<M-f>`, `<M-S-f>`, `:e b`, `<M-;><M-c>`, `<M-;><M-r>` in window 2 leave window 1's slots, notes and primary queue as they were, and so does `<C-w>p` back into it.
- T211 [char] (P20) Restoring is only ever explicit: at `⦉-⦊ [c] ⟦d⟧` (`:e a`, `:e b`, `:e c`, `:e d`, `:e c`, `<M-f>`) with c's note `c>b`, a wait leaves the ternary empty, `<M-S-f>` says "No ternary buffer to swap with." and changes nothing, and only `<M-;><M-r>` brings b back: `⦉b⦊ [c] ⟦d⟧`.
- T212 [target] (P22, S2) The session file is written with mode 0600 whatever the umask: `rw-------` with a umask of 022. Today `writefile` follows the umask and gives `rw-r--r--` (S1).
- T213 [char] (P24, M6) A save with a No Name current slot leaves the live triquetra, the notes, the primary queue, the closed stack and the history order as they were: the substitution only changes what's written to the file.
- T214 [target] (P24, A22) A save leaves the closed stack as it was: with b closed and outside the slots, deleting b.txt and saving straight away keeps b on the stack. Today the save's `cleanup_system` drops it (S1 save step 1, A22 step 3).
- T215 [target] (P26) With harpoon not installed, `:e`, `<M-f>`, `<M-S-f>`, `<M-;><M-c>`, `<M-;><M-r>` and the UI ticks raise nothing and report no hook failure. Today every history update fails at `history/routines.lua:416` with "module 'harpoon' not found".
- T216 [char] (I16) A No Name id isn't reused across sessions: two fresh processes that each run `:e a`, `:enew` get the same buffer number and different ids.
- T217 [char] (I10, A1, A2) A buffer that turns into something untracked isn't left registered or in a slot. Two routes: a buffer entered as `buftype ""` and then set to `nofile`, as a plugin's scratch is, followed by `:e b`; and `:copen`, which enters its buffer before it's a quickfix buffer (DESK:2453), so its window gets no triquetra either. The first route has its arrival undone on `OptionSet`; the second is judged once the editor settles, when the buffer is already a quickfix list (I10).
- T218 [target] (I18) A repeated file in the primary queue window is refused loudly: from `[b,a]on`, the lines `a`, `b`, `a` save `[a,b]` and report the repeat at error level, like a typo'd path under Q11's partial save. Today `[a,b,a]`: `update_primary_buffer` doesn't dedupe. Decided 2026-10-21 (the author: "Refuse loudly").
- T219 [char] (I19, Q14) An empty queue that's switched on stays on: from `p=[]on`, `:e c`, `<M-f>`, `<M-;><M-f>`, `:e a`, `<M-S-f>` and the UI ticks leave `p=[]on`.
- T220 [target] (M11, D23) The winbar and indicator toggles work at runtime: `hide_winbar()` empties the winbar and it stays empty through the refresh, `show_winbar()` brings it back, and `hide_indicators()`/`show_indicators()` switch the indicators off and on. Today the winbar machine doesn't exist and the indicator transitions aren't registered, so each throws; nothing calls them, and a `:set winbar=` by hand is written back within a tick (`ui/routines.lua:598`) **[run 2026-10-21]**. Decided 2026-10-21: build them (the author: "Build them"); how they're exposed, key or command, is decided later. The bufferline pair is T123.
- T221 [target] (M11) `unregister_hook(name)` removes that hook from its own machine and nothing else, without throwing, and the name can be bound again. Today it calls the class instead of the instance (`state-machine.lua:382`), throws, and the hook still runs.
- T222 [char] (M1, D4) Hashing a file name runs no shell: `:e a` and `:e b` make no `vim.fn.system`, `io.popen` or `vim.system` call.
- T223 [char] (A1, A3) Going back into a window onto its current slot changes nothing: with window 1 on `⦉c⦊ [d] ⟦b⟧` and window 2 on `⦉d⦊ [e] ⟦-⟧`, `<C-w>p` three times leaves both windows' slots and notes as they were (A1's row X = A).
- T224 [char] (A1) A visit made in another window lands in that window, never the focused one: with window 1 focused on `⦉a⦊ [b] ⟦-⟧`, `:edit d.txt` run in window 2 through `win_execute` gives window 2 `⦉c⦊ [d] ⟦-⟧`, and window 1 keeps the focus, its buffer and its slots **[code]**. The history half is T19.
- T225 [char] (A2, M6) Windows born untracked never get a triquetra: a `:help` window and a `:split | terminal` window have none, after UI ticks and a jump out and back in. A `:copen` window is T217's second route.
- T226 [char] (A6, A7, A8) With no triquetra (a `:help` window), `<M-f>`, `<M-S-f>` and `<M-;><M-f>` each warn "Window with unregistered buffer.", raise nothing, switch nothing, and leave the other window's slots alone.
- T227 [target] (A7, P9) `<M-S-f>` on a closed ternary whose file is gone from disk says so and keeps the pointer: `:e a`, `:e b`, `:e c`, `:bdelete b.txt`, then b.txt deleted and `<M-S-f>` pressed straight away give a warning, no throw, and `⦉b⦊ [c] ⟦-⟧`. Today "Removed ternary file not found in filesystem" and `t := nil`.
- T228 [char] (A11, D9) A restore switches no buffer and reopens nothing: at `⦉d⦊ [b] ⟦-⟧` with `dtm{b>a}` and a closed with `:bdelete`, `<M-;><M-r>` gives `⦉a⦊ [b] ⟦-⟧`, still showing b, with a unloaded and still on the closed stack; `<M-S-f>` then reopens a and takes it off the stack (a closed hash reopens when used).
- T229 [char] (A12) Any jump into another window cancels the cycle, floats and `:help` included: cycling from c with `⦉b⦊ [c] ⟦-⟧` to b, then a jump into a float, or `:help`, puts the window back on c with navigation `normal`, history attached, and the slots and the history order unchanged.
- T230 [char] (A13) A pick writes no secondary notes: from `⦉d⦊ [e] ⟦c⟧`, a pick of b (outside the slots) and then a pick of the ternary leave the secondary map as it was. The pick of the secondary is T73.
- T231 [char] (A14, Q7) `<M-;><M-f>` while cycling with the window already on the start says "Returned to cycling origin buffer" each time and changes nothing: the slots, the notes, the shown buffer and the order stay, and navigation stays `cycling`.
- T232 [target] (A17) `<M-,>` skips a previous window whose filetype is `neominimap`, as it does `minimap` (T94): it warns "No valid previous window to toggle to." and stays.
- T233 [char] (A18) With no triquetra (a `:help` window, while the other window's queue is `[a]on`), `<M-;>F` says "No triquetra found for current window." and opens no window.
- T234 [char] (A18, Q11) The pop-up refuses what cavediver doesn't track and keeps the good lines: from `[b,a]on`, the lines `a`, a blank line, the path of a loaded help file, `NONAME_999` and `b` save `[a,b]on`, with one error naming the help file and `NONAME_999`; the blank line is dropped without a word.
- T235 [target] (A18) A relative path in the primary queue window is resolved against the current directory, as `:e` does: the lines `./b.txt`, `a` save `[b,a]`, with no hole, and the pop-up redraws them as `b.txt`, `a.txt`. Today the line passes validation as typed, then its hash is looked up by the typed string, finds nothing, and leaves slot 1 empty, so the primary is lost and every loop over the queue sees it as empty (`window/routines.lua:236`; DESK:2477) **[run 2026-10-21]**. Decided 2026-10-21 (the author: "I thought we can type relative paths. In fact it's easier to type relative paths right?", then "Resolve it"). The pop-up keeps showing each entry by its shortest unique name, `b.txt`, or `src/b.txt` when another `b.txt` exists (the author, 2026-10-21: "Shortest name (today)").
- T236 [target] (A5) Closing another window first doesn't stop the pop-up's buffer going when the pop-up closes: `:vsplit`, `:close`, then `<M-;>F` and `:close` in the pop-up delete its buffer, as they do when no window was closed first. Today the first close uses up the `once` handler (`ui/hooks.lua:139`). And `<M-;>F` opens the pop-up again afterwards: today the left-over buffer keeps its name, and the next `<M-;>F` fails with "E95: Buffer with this name already exists" (`ui/routines.lua:66`); `q` and `<C-c>` don't hit this, since `close_window` deletes the buffer itself **[run 2026-10-21]**. Kept as a fix test, with the reopen check added (the author, 2026-10-21: "Keep + add reopen").
- T237 [char] (A19) With nothing left to land on, the window keeps Neovim's empty buffer and no `:enew` runs: `:e a`, `:bdelete a.txt` leave the window on the buffer Neovim put there, with no buffer added. A guard on the landing (A19, built in step 1).
- T238 [char] (A20) `:w new.txt` on a No Name buffer with text leaves no ghost entry on the closed stack: the old name isn't a file, so it's a move. Its notes follow too (the decided move, DESK:1924): a No Name buffer whose note says its ternary was a gives `new>a` after `:w new.txt`, with no dangling hash. **[run 2026-10-21]** recorded the ghost before the rename policy (DESK:2455): the closed stack got `NONAME_2`, `<M-S-w>` reopened it as a new No Name buffer holding a second copy of the saved text, and the note dangled as `?274b55>a`. Kept as a fix test, with the notes check added (the author, 2026-10-21: "Keep + notes follow").
- T239 [char] (A21) A slot pointing at an open buffer is kept whatever the disk says: at `⦉c⦊ [d] ⟦b⟧`, deleting b.txt and c.txt (both still open), UI ticks and a `cleanup_system` pass leave the slots and both registrations as they were.
- T240 [char] (A25) `disable()` clears the `cavediver` augroup and stops the timers, and afterwards `:e c` changes no slot and records nothing.
- T241 [target] (A26) The recorder never records raw keystrokes: text typed in insert mode (`QZQZQZ`) before the restore assertion fires doesn't show up as steps in the dump, whatever its format, file or scratch buffer.
- T242 [char] (bug (new), 2026-10-21) A tracked buffer wiped with `noautocmd` doesn't make the UI loop error: `:e a`, `:e b`, `:e c`, then `noautocmd bwipeout` of c give no hook failure over the next ticks. Without the repair, "Invalid buffer id" comes on every tick (`ui/routines.lua:534`); wiping the ternary, or a buffer outside the slots, this way gives no error. **Decided (2026-10-21): the UI repairs it on the spot** (the author: "Keep, UI repairs now"): when a refresh finds a window showing a different buffer from its current slot, it re-points as cleanup would, like navigation (Q18), so within one refresh the window above reads `⦉c⦊ [b] ⟦-⟧` and nothing errors. Built in step 3: when any slot's registered buffer is no longer valid, the refresh runs `cleanup_system` at once (`ui/routines.lua:255-272`); its stale pass forgets the dead number, and the heal re-points the window like navigation. **[run 2026-10-21]** recorded about 13 error notifications over the ~4 s until the cleanup tick repaired it, before the repair.
- T243 [char] (I23) The check runs wherever a slot changes under the current buffer (decided 2026-10-21), with the stale note planted: at graduation (`⦉b⦊ [c] ⟦-⟧` with `dsm{c>b}`, `<M-f>`), at the history fill (a fresh split on b with `dsm{b>a}`, `<M-f>` fills a), and at a session load (`⦉-⦊ [c] ⟦b⟧` with `dsm{c>b}`, saved and loaded). After each, the current buffer's note doesn't name its slot's occupant, and `<M-;><M-t>` doesn't throw.
- T244 [char] (S2) A load into fewer windows than were saved matches by what they show and drops the unmatched entry, with no error: two windows saved (`⦉c⦊ [d] ⟦-⟧` in the split, `⦉a⦊ [b] ⟦-⟧`) and one restored on b give `⦉a⦊ [b] ⟦-⟧`.
- T245 [target] (S2) A session file with a newer header gives "made by a newer cavediver" and is left alone: a file starting `CDV9` is unchanged after the load. Today the load is a silent fresh start.
- T246 [char] (S2) A No Name buffer closed with `<M-.>` stays on the closed stack across a save and a load, and `<M-S-w>` then brings its text back. It holds today already (found 2026-10-21), so it's [char]: a guard that stays true when the decided code lands.
- T247 [char] (I13, A21) A cleanup heal in another window doesn't switch the focused window or wipe what that window shows: window 2 on `⦉x⦊ [c] ⟦-⟧` shows an `acwrite` buffer, and `:bdelete c.txt` from window 1 leaves window 1 focused on b and window 2 on its buffer.
- T248 [char] (A12) With no cokeline, a cycle step raises nothing, steps through cavediver's own order (T171), and `<M-v>` still ends the cycle: navigation `normal`, history attached, and the pick lands where the step went (from `⦉a⦊ [b] ⟦-⟧`, `<M-n>` and `<M-v>` give `⦉b⦊ [a] ⟦-⟧`). **[run s21]** recorded the step doing nothing, before the fallback.
- T249 [char] (A1, A11) No note names its own buffer: random walks with T190's mix, in one window and across windows, check after every action that no map holds `X>X` or `X-swap>X`. The decided check drops a stale note when the note it would copy names the current buffer (A11), and runs after Q6's guard so two notes naming each other can't leave one behind (A1). A guard on the check (built in step 3).

**Decided rules not covered elsewhere (T250–T291)**

Each checks a rule the spec states as intended or decided that no earlier test checks, found by an audit of the tests against the spec (2026-10-21), and cites the rule. Where a state is set by hand, the test says so; where it reads a format the spec gives only as an example, it matches loosely.
- T250 [char] (P2, A1) The slotting happens after the event, not inside it: with `⦉-⦊ [a] ⟦-⟧`, a `BufEnter` autocmd of the user's, made after `setup()`, still sees `⦉-⦊ [a] ⟦-⟧` while `:e b` runs, and the window has `⦉a⦊ [b] ⟦-⟧` once the editor settles. Its purpose is tested too: a buffer that only becomes a terminal or help after its `BufEnter` (`:terminal`, `:help`) is never registered or slotted as a file. The author asked for both checks, 2026-10-21: "Both".
- T251 [char] (P3) The load matches windows by what they show, not by position: two windows saved (`⦉c⦊ [d] ⟦-⟧` in the split, listed first, and `⦉a⦊ [b] ⟦-⟧`) and restored the other way round (the first-listed window on b) give the window on b `⦉a⦊ [b] ⟦-⟧` and the window on d `⦉c⦊ [d] ⟦-⟧`.
- T252 [target] (P10, I17) History follows along and doesn't let go early: `:e a`, `:e b`, `:e c`, `:bdelete b.txt` leave b on the closed stack, still known, and its global history entry stays. Today the entry goes as soon as b is unregistered. "Known" means cavediver still remembers the file (registered, e.g. on the closed stack), not that it's open; confirmed by the author, 2026-10-21: "Forgotten (as read)". The entry never reaches the bufferline: cokeline draws from listed buffers, and the ordered list skips hashes with no open buffer (`history/routines.lua:393-397`) **[run 2026-10-21]**.
- T253 [char] (P11) A bug inside a hook is caught with a stack trace: a hook that throws is reported as "Hook '<name>' failed…" together with a stack traceback. The traceback is in the notification itself (confirmed by the author, 2026-10-21: "In the notification").
- T254 [char] (P12, A25) Nothing runs at `require`, and `setup()` makes everything inside the `cavediver` augroup: `require('cavediver')` alone creates no `Cavediver*` user command and starts no timer, and every autocmd `setup()` creates is in the `cavediver` augroup, with the commands made.
- T255 [char] (M1) The session file is named `sha256(directory .. "\n" .. name)`: `save_session('work')` writes a file in `session_dir` whose name starts with `vim.fn.sha256(getcwd(-1, -1) .. "\n" .. 'work')`; and a session `a` saved in `/proj` and a nameless save in `/proja` are two files. Without the separator both would hash `"/proja"` and share a file. Decided 2026-10-21 (the author: "With a separator").
- T256 [char] (M3) A listed `nowrite` buffer on an existing regular file is tracked: after `:e a`, entering such a buffer on c.txt registers it and gives `⦉a⦊ [c] ⟦-⟧`.
- T257 [char] (M7) The secondary map's swap notes are stored with the rest of the map: at `⦉-⦊ [c] ⟦b⟧` (`:e a`, `:e b`, `:e c`, `<M-f>`) with `b-swap>c` set by hand on dsm, a save and a load in a fresh process give back `dtm{b>a} dsm{b-swap>c b>a}`. It holds today already, so it's [char]: a guard that stays true when the decided code lands.
- T258 [char] (M8, Q16) The primary may share a slot's buffer: with `p=[a]on`, `:e b` puts a in the ternary, `<M-f>` in the secondary and `<M-f>` again in the current slot; the queue stays `[a]on` throughout and over the UI ticks, and nothing reports an error.
- T259 [char] (M7, A6, A8) The `<M-;><M-f>` fallback onto the secondary writes the same notes as `<M-f>`: from `⦉c⦊ [d] ⟦b⟧` with an empty queue, `<M-;><M-f>` gives `⦉c⦊ [b] ⟦d⟧` with `dsm{d-swap>b}`, `dtm{d-swap>c}` and no plain secondary note for d (T191's notes).
- T260 [char] (A1, A13) The check on a pick of the ternary: T186's keys up to `⦉d⦊ [a] ⟦c⟧` (d's note `d>a`), then cycle to d and `<M-v>`, give `⦉a⦊ [d] ⟦c⟧`; d's note names the new ternary a, which has no plain note, so it's dropped and `<M-;><M-r>` says "No ternary relationship found".
- T261 [char] (A1, A8) The check on a primary jump onto the ternary: `:e a`, `:e d`, `<M-;><M-c>`, `:e c`, `<M-f>`, `<M-f>`, `:e a` give `⦉d⦊ [a] ⟦c⟧` with `p=[d]on` and d's note `d>a`; `<M-;><M-f>` gives `⦉a⦊ [d] ⟦c⟧`, d's stale note becomes a's own note, none, so it's dropped, and `<M-;><M-r>` says "No ternary relationship found".
- T262 [char] (A1, A13) The check on a pick of the secondary: T185's keys up to `⦉c⦊ [b] ⟦e⟧` (e's note `e>c`), then cycle to e and `<M-v>`, give `⦉c⦊ [e] ⟦b⟧`; the ternary c stays put, so e's note becomes c's own note, `e>a`. `<M-;><M-r>` gives `⦉a⦊ [e] ⟦b⟧`, and again `⦉c⦊ [e] ⟦b⟧`.
- T263 [char] (A7, A8, M7) The secondary map's check runs on `<M-S-f>` and on a primary jump, with the stale note planted. At `⦉c⦊ [d] ⟦b⟧` with `c>b` set on dsm, `<M-S-f>` gives `⦉d⦊ [c] ⟦b⟧`; with `p=[x]on` and `x>b` set on dsm, `<M-;><M-f>` gives `⦉d⦊ [x] ⟦b⟧`. In both the note names the secondary and there's no swap note, so it's dropped (I23 holds) and `<M-;><M-t>` says "No secondary relationship found".
- T264 [char] (A11, I23) The ternary restore's exchange is followed by the secondary map's check: at T62's `⦉c⦊ [b] ⟦a⟧` with `b>c` set on dsm, `<M-;><M-r>` exchanges to `⦉a⦊ [b] ⟦c⟧`; b's secondary note now names the secondary, so it's rewritten or dropped (I23 holds), and `<M-;><M-t>` doesn't throw.
- T265 [char] (A11, final section) At the secondary restore's exchange the stale ternary note is dropped when the ternary's own note would name the current buffer: at `⦉c⦊ [d] ⟦b⟧` with `d>c` on dsm and `d>b`, `b>d` on dtm (set by hand), `<M-;><M-t>` exchanges to `⦉b⦊ [d] ⟦c⟧`, d's ternary note is dropped, and `<M-;><M-r>` says "No ternary relationship found".
- T266 [char] (A11, D9) A note at a file deleted on disk whose buffer is still open flip-flops and says the file isn't on disk: T173's keys and checks, and each press that brings f back gives a message besides "Restored ternary slot to…". The message is locked (the author, 2026-10-21: "(a) one WARN line"): `Restored ternary slot to: <hash> (<name>), not on disk right now` at WARN, and the same with "secondary" for the secondary restore.
- T267 [char] (A11, D9) A note at a hash with no path is cleared when it's used: T68's state, and after `<M-;><M-r>` no note holds the unknown hash.
- T268 [char] (A2) The winbar shows a visit, like `main.lua ← [help]`: help shown in a's own window gives a winbar whose current piece reads, with highlights left out, `[<bufnr>] a.txt ← [help]`. The format is locked (the author, 2026-10-21: "(a) within the winbar"): the current slot's piece becomes `[<bufnr>] <name> ← [<type>]`, with the ternary and secondary pieces kept around it; the brackets hold the `buftype` (`help`, `terminal`, `quickfix`), or the filetype when the `buftype` is empty or `acwrite`, so oil shows `[oil]` (M12).
- T269 [char] (A2, A6, A7) While visiting, `<M-f>` and `<M-S-f>` take the window back to its current slot first: at `⦉c⦊ [d] ⟦b⟧`, a `nofile` scratch shown in the window, then either key, gives d again with `⦉c⦊ [d] ⟦b⟧`.
- T270 [char] (A2) While visiting, the current slot may hold a closed buffer: at `⦉-⦊ [c] ⟦b⟧`, `:terminal` in the window, then `:bdelete c.txt`, leave `⦉-⦊ [c] ⟦b⟧` with c on the closed stack.
- T271 [char] (A19) A deleted buffer's window lands in the order ternary, secondary, primary, most recent, each on a route where Neovim's own pick (the window's jumplist) differs; Neovim closes every other window showing the buffer, so each is a window on its own, as in T111. Secondary: `:e a`, `:e b`, `:e c`, `<M-f>`, `<M-f>`, `<M-;><M-t>` give `⦉-⦊ [b] ⟦a⟧`, and `:bdelete b.txt` lands on a (Neovim: c). Primary: a split on c with empty slots, left alone by `:only` after the first window visited d and x, with its queue set to `[a]on` by hand, lands on a after `:bdelete c.txt` (Neovim: b). Most recent: the same with an empty queue lands on x (Neovim: b). Nothing to land on: `:e a`, a listed `nofile` scratch, `:bdelete a.txt`: Neovim shows the scratch, something other than its empty buffer, so `:enew` runs and the window shows a new empty buffer. "Most recent" follows `history_view`, as `<M-.>` does (the bufferline's order, built from the current view): under the window view it's the window's own history (the author, 2026-10-21: "Follow history_view"). A sub-case checks it under the window view, where the window lands on what it showed rather than on the last file touched elsewhere.
- T272 [char] (A20) The disk decides, the copy half: `:e a`, `:e b`, `:saveas g.txt` leave b.txt on disk, so the rename is a copy and b goes on the closed stack. Built in step 4 (A20). What `:saveas` does to the window is T106's.
- T273 [char] (A22) The stale pass keeps the history of the file it re-points: T113's state, and after the pass b's hash is still in the global history.
- T274 [char] (A23) `:CavediverTriquetra` and `:CavediverTriquetraVerbose` print `primary_buffer[1]` as "Primary buffer".
- T275 [target] (A26) Each "shouldn't happen" dumps: the fill assertion (T176's second half), "Duplicates detected" (T34's state), and a hook failure (a hook that throws, bound by hand to the history machine's updates) each leave a new file under `stdpath("state")/cavediver/` (the location T200 uses, decided 2026-10-21).
- T276 [target] (A26) A planted I1 break dumps at the next step: T203's layout, with c's secondary set by hand to b, its ternary, and `:e x` in the other window produces one dump.
- T277 [target] (A26) The error message says where the dump file is: T200's restore assertion, and the error or a message names the new file.
- T278 [target] (A26) Steps are tagged by cause: in T200's dump, the steps from keymaps and from events carry the tags `keymap` and `event` (T204 checks `load` and `timer`).
- T279 [char] (I5) The registry stays a bijection, for buffers and for paths: random walks with T130's mix plus `:enew`, a No Name buffer with text, `<M-.>` and `<M-S-w>`, checked after every action.
- T280 [char] (I6) A buffer wiped without events leaves no stale registration once a cleanup tick has run: `:e a`, `:e b`, `:e c`, `noautocmd bwipeout` of b, then a 4.6 s wait leave every registered buffer number valid.
- T281 [char] (I7) After a cleanup pass, no hash on the closed stack has an open buffer: random walks with T279's mix, a `cleanup_system` pass forced after every action ("eventually enforced").
- T282 [char] (I8) A window's current slot is the hash of the buffer it shows, except in the window a cycle runs in and during a visit: random walks with T128's mix, cycles left open across a window jump included. A cycle left open across a window jump is cancelled, so work in the other window is recorded (A12). I8's status also names a second route, "Duplicates detected" leaving the slots behind (A1). The cycling exception covers only the window that's cycling; every other window must match what it shows at every step (confirmed by the author, 2026-10-21: "Only the cycling one").
- T283 [char] (I9) Every triquetra belongs to a valid, non-floating window: random walks with T128's mix plus `:enew`, `<M-.>` and `<M-S-w>`.
- T284 [char] (I9) `:file` onto a name not on disk, in a split, leaves no triquetra for a dead window: `:e a`, `:vsplit`, `:e b`, `:file new.txt`.
- T285 [char] (I14) A save with a slot holding a hash with no path succeeds and reports nothing: at `⦉c⦊ [d] ⟦b⟧`, the secondary set by hand to an unknown hash, then `save_session` in the same call.
- T286 [char] (I21) The critical save hook throws to the caller, and the abandoned transition leaves storage where it was: `idle` after a load or a save, `bare` before either. T143's read-only session directory, saved from a fresh process (so `bare`).
- T287 [char] (I23, A21, final section) The check runs at a cleanup pass that moved a window's slots: T163's re-point, with d's secondary note set by hand to b, the window's secondary; once d is current I23 holds and `<M-;><M-t>` doesn't throw.
- T288 [char] (D11, bug found while porting) Under the window view, `:close` leaves no tie: `:e a`, `:e b`, `:vsplit`, `:close`, `:e a` put a strictly first in the bufferline order.
- T289 [target] (D25) The window machine goes: no `window/sm.lua`, no `SHOWING_` constants in `window/states.lua`, and nothing requires `cavediver.domains.window.sm`. A doc check, matched by text.
- T290 [char] (D18, D22, D24) STATUS and the old project `CLAUDE.md` live in `archive/`, and neither is at the repo root. A doc check. It holds today already, so it's [char]: a guard that stays true when the decided code lands.
- T291 [char] (D8, D13) README:15 ("Closed buffers reopen when accessed through relationships") and README:355 ("Every time you jump to secondary…") stay as written. A doc check, matched by text. It holds today already, so it's [char]: a guard that stays true when the decided code lands.

**The session file, S2 (T292–T332, T337)**

Each checks a rule S2 states as decided, or a desk line S2 rests on, that no earlier test checks, found by mapping S2 against the tests (2026-10-21), and cites the rule. Most save in one process and load in a fresh one, passing the cwd as the session's name, as the README's wiring does (S1). Where S2 leaves a format or a mechanism open, the test matches loosely and says so.
- T292 [char] (S2 Contract and API; DESK:758, DESK:1074) `save_session()` and `load_session()` take no directory: with no argument the save writes a file whose name starts with `sha256(getcwd(-1, -1))`, and `load_session()` in a fresh process brings back `⦉c⦊ [d] ⟦b⟧`. A nameless save is named `sha256(directory)` alone, with no separator (decided 2026-10-21, the author: "directory alone"); the separator is only used with a name.
- T293 [char] (S2 Contract and API; DESK:758, DESK:1146) A whole-editor save is keyed by the global directory, not by a tab-local `:tcd`: `save_session('work')` from a tab with `:tcd sub` writes a file named after `sha256(getcwd(-1, -1) .. "\n" .. 'work')`, and none after the tab's directory.
- T294 [char] (S2 Contract and API, Tab sessions; DESK:949, DESK:1074) A tab session is keyed by its tab's directory: `save_session('t', { tab = … })` from a tab with `:tcd sub` writes a file whose name starts with `sha256(<project>/sub .. "\n" .. 't')`. The spec makes the scope's directory the key and names the file `sha256(directory .. "\n" .. name)` (T255); that the name takes the tab's directory is read from the two together.
- T295 [char] (S2 Loading; DESK:1284) A load from idle goes `idle → bare → loading`: after a save, `load_session` adds `idle->bare` and then `bare->loading` to the storage machine's history.
- T296 [char] (S2 Loading; DESK:1282, DESK:1284) Every domain tears its own state down at `idle → bare`: saved at `⦉b⦊ [c] ⟦-⟧`, then `:e d`, `:e x`, `:bdelete d.txt` and a cycle step left open, the window put back on c and a load give `⦉b⦊ [c] ⟦-⟧`, an empty closed stack, navigation `normal`, history attached, and x unregistered (T314).
- T297 [char] (S2 Loading; DESK:1286, DESK:1288) The repeat flag is re-armed by `vim.schedule`: three `load_session` calls in one batch, a 30 ms wait, then a fourth call give two loads, and every call returns normally. With T145, this tells `vim.schedule` apart from a timer and from no flag.
- T298 [char] (S2 Loading; DESK:794) Cavediver loads again by itself after Neovim's `:restart` session, ignoring the flag: two windows saved at `⦉c⦊ [d] ⟦-⟧` and `⦉a⦊ [b] ⟦-⟧`, a startup load, and then the restart session sourced in the same batch give two loads and the saved slots. `:restart` can't run inside a test's child, so the child is started with `__NVIM_STARTREASON=restart` in its environment, an undocumented Neovim 0.12 internal that sets `v:startreason`, and the restart session is a `:mksession!` file named `restart_session_…`. **[desk]** recorded the scramble in tmux, without the reload: the restart session's window came back with the wrong ternary.
- T299 [char] (S2 Loading; DESK:1161) One post-restore callback replaces the 210 ms delay: the load makes no timer, and 30 ms after it `last_valid_window` is the current window and the bufferline order is what it still is 300 ms later. That `require` starts no probe is T254.
- T300 [target] (S2 Loading; DESK:1286) A later reload brings no No Name text back twice: with a No Name text open in the ternary at save, a load and then a second load leave exactly one buffer holding it.
- T301 [target] (S2 The file; DESK:1554) The main file starts with the clear version header `CDV1`. Today it starts with `{"`.
- T302 [target] (S2 The file; DESK:1541) Nothing in the session files is in clear: with b closed and a No Name text open, no file under `session_dir` parses as JSON or holds the project's directory, a file name or the No Name text. Today the file is JSON.
- T303 [char] (S2 The file; DESK:1541) The file goes through `libcrypto`, not a command: a save, and a load in a fresh process, make no `vim.fn.system`, `io.popen` or `vim.system` call. Hashing on `:e` is T222.
- T304 [target] (S2 The file; DESK:1555) Every write is atomic: a second save puts a new file in place by renaming it over the first (the main file's inode changes), and leaves no other regular file in `session_dir`. Today `writefile` rewrites the same file.
- T305 [target] (S2 The file; DESK:1547, DESK:1555, DESK:1636) One file per No Name text sits in `<main>.d/`, each in mode 0600: a No Name text closed with `<M-.>`, another open, and an empty one shown give exactly two files there, `rw-------` with a umask of 022. The directory is found as the one in `session_dir` whose name ends in `.d`.
- T306 [target] (S2 The file; DESK:1547, DESK:1548) Scratch files are named per version, written only when they change, and swept once nothing references them: a second save with the text unchanged keeps the same file and bytes; after the text changes, the next save leaves one file under a new name.
- T307 [target] (S2 The file; DESK:1548) The main file is the commit point, in two cases put together from the files of two saves (v1, then v2). A crash before the main file lands (the first main file, with both scratch files beside it) loads with the v1 text back and not v2; a crash after it (v1's scratch left beside v2's) is swept by the next save.
- T308 [target] (S2 The file; DESK:1548) A damaged scratch file loses one scratch, not the session: with two open No Name texts saved and one byte flipped in one scratch file, the load gives back `⦉a⦊ [b] ⟦-⟧` and exactly one of the two texts.
- T309 [char] (S2 The file; DESK:1549) No count limit: 150 files closed with `:bdelete` are all on the closed stack after a save and a load in a fresh process. It holds today already, so it's [char]: a guard that stays true when the decided code lands.
- T310 [target] (S2 Checks; DESK:1541, DESK:1683, DESK:1685) A file only decrypts in its own directory: a file saved as `work` in one project, copied to the name `work` takes in a second project (`sha256(directory .. "\n" .. 'work')` with that project's directory), gives "failed its integrity check (edited or corrupted)" there and a fresh start, `⦉-⦊ [b] ⟦-⟧` with an empty closed stack. Matched on "integrity check". The edited byte is T144.
- T311 [target] (S2 Checks; DESK:1683) A cut-off file, the saved file cut to half its length, gives the integrity notification and a fresh start, as T144's edited byte does. Today it's a silent fresh start.
- T312 [target] (S2 Checks; DESK:1682) A file with no header, plain JSON in today's format at the main file's name, gives a message naming the migration script at load. Matched on "migration script". The newer header is T245.
- T313 [target] (S2 Checks; DESK:1689) A reference that resolves to nothing at load is kept, says so when it's used, and works again when its file comes back: saved at `⦉c⦊ [d] ⟦b⟧`, with b.txt deleted and not restored, the load keeps `⦉c⦊ [d] ⟦b⟧`; `<M-f>` gives a message, raises nothing and changes no slot; with b.txt written back, `<M-f>` gives `⦉c⦊ [b] ⟦d⟧`. Today the secondary comes back empty: the load closes b as it does in T337, and cleanup prunes a closed slot whose file is gone from disk (A21).
- T314 [char] (S2 Contents; DESK:1432, DESK:1436) A restored buffer the file doesn't know waits for `BufEnter`: x, loaded and hidden at the load but never saved, isn't registered by the load, and is once `:e x` enters it.
- T337 [char] (S2 Contents; DESK:1943) A reference whose buffer the manager doesn't restore is kept, and reopens when used: saved at `⦉c⦊ [d] ⟦b⟧`, a fresh process that restores a, c and d but not b (b.txt stays on disk), loads and runs a `cleanup_system` pass has `⦉c⦊ [d] ⟦b⟧`, with b unregistered; `<M-f>` then gives `⦉c⦊ [b] ⟦d⟧`, showing b. The load puts b on the closed stack, so cleanup keeps the slot as any closed slot (S1, A21). Added with step 4's `paths` table, 2026-10-23.
- T315 [char] (S2 Contents; DESK:1440) Windows on the same file keep their saved order, and a window that matches nothing starts fresh: saved as `⦉c⦊ [b] ⟦-⟧` (the split, listed first) and `⦉a⦊ [b] ⟦-⟧`, and restored behind a new first-listed window on e, the windows read `⦉-⦊ [e] ⟦-⟧`, `⦉c⦊ [b] ⟦-⟧` and `⦉a⦊ [b] ⟦-⟧`.
- T316 [target] (S2 Save-as-closed; DESK:1634, DESK:2299) A No Name buffer reopened at load gets a fresh id, and every reference to its old hash is renamed: a No Name text in the ternary (`:e a`, `:enew` with text, `:e b`) comes back as the ternary under a hash that differs from the saved one, and no slot, queue, note or history entry keeps the old hash. Today the text isn't reopened.
- T317 [char] (S2 Errors and drift; DESK:1070) With two editors on one project, the last writer wins: both save in turn without an error, and a fresh process loads the second one's `⦉c⦊ [d] ⟦-⟧`. It holds today already, so it's [char]: a guard that stays true when the decided code lands.
- T318 [target] (S2 Tab sessions; DESK:949) A tab session's file says its scope, and its load works on the current tab only: a session saved with `{ tab = … }` from a tab at `⦉c⦊ [d] ⟦-⟧`, loaded by name alone into a second tab of a fresh process, gives that tab `⦉c⦊ [d] ⟦-⟧` and leaves the first tab at `⦉x⦊ [t] ⟦-⟧`. Today it passes by another route: its load runs from `bare` in a fresh process, so nothing is torn down, and the first tab's window on t matches no entry and keeps its triquetra (S1). The file still says no scope, and a load from `idle` tears every tab down first. The check can't tell the two routes apart, which step 7 has to fix.
- T319 [target] (S2 Tab sessions; DESK:952) Closes go to the pool of the tab they happen in, and `<M-S-w>` reopens from the current tab's: in T318's state, after `:bdelete x.txt` in the first tab and then `:bdelete c.txt` in the session's tab, `<M-S-w>` in the first tab reopens x and in the session's tab c. Today the first tab gets c.
- T320 [target] (S2 Tab sessions; DESK:951, DESK:954) The session's tab ranks its own visits first, and a buffer belongs to every tab that visited it: in T318's state, `:e a`, `:e b` in the first tab and `:e a` in the session's tab leave a, c and d as the first three in the session tab's bufferline order. Only membership is checked; the spec doesn't fix the order inside the overlay.
- T321 [target] (S2 Tab sessions; DESK:955) Saves are snapshots: in T318's state, with x closed in the first tab, c in the session's tab and e in the first tab, a second apart, a whole-editor `save_session()` leaves the pools apart in memory (`<M-S-w>` in the first tab reopens e, then x), and a fresh process loading that file has one stack merged by close time (`<M-S-w>` reopens e, c, x).
- T322 [target] (S2 Tab sessions; DESK:956) A tab session's tab closed with nothing wired to save it keeps its pool, with no tab, and gives a notice: in T318's state, `:tabclose` on the session's tab, with no `TabClosedPre` hook calling `save_session`, gives a notification; and with c closed in that tab first, `:CavediverClosed` still lists c afterwards. The wording isn't fixed, so any notification that isn't a hook failure counts.
- T323 [target] (S2 Tab sessions, Errors and drift; DESK:957, DESK:1068) A tab-session save refreshes the unnamed session's records and leaves its references: with the whole editor saved by `save_session()` at `⦉x⦊ [t] ⟦-⟧`, the tab session loaded into a second tab, x closed and e visited in the first tab, and the tab session saved, a fresh process's `load_session()` has x on the closed stack and still `⦉x⦊ [t] ⟦-⟧`. Today it passes by another route: x, closed in the first tab, isn't restored in the fresh process, and the load closes a reference the manager didn't bring back (T337); the unnamed session's records aren't refreshed. The check can't tell the two routes apart, which step 7 has to fix.
- T332 [target] (S2 Tab sessions; DESK:951, DESK:954, DESK:1640) A pool holds its own No Name texts: in T318's state, a No Name text left in the session's tab's history and another left in the first tab's, a save of the tab session alone, and a load of it into a second tab of a fresh process bring back the session tab's text and not the first tab's. Today open No Name texts aren't saved.
- T324 [target] (S2 Oil; DESK:2087, DESK:2093) An oil window comes back as oil, with `vim.w.oil_original_buffer` set from its current slot: a window at `⦉a⦊ [b] ⟦-⟧` showing an oil listing at save, restored on the listing, still shows it after the load, keeps `⦉a⦊ [b] ⟦-⟧`, and has `oil_original_buffer` set to b's buffer, with the oil buffer itself unregistered. Oil is stood in for by an `acwrite` buffer named `oil://<project>/`. Today the window gets no triquetra.
- T325 [target] (S2 Closed-stack picker; DESK:2367, DESK:2371, DESK:2374) `:CavediverClosed` opens an editable buffer that lists the closed entries, newest first, and no open buffer: with b and then c closed, the buffer is modifiable, a line naming c.txt sits above one naming b.txt, and no line names a.txt or d.txt. Entries are found by the file name they hold, since the spec gives no format for them. Today there's no such command.
- T326 [target] (S2 Closed-stack picker; DESK:2368) A No Name entry shows its first line in quotes, its filetype and its close time: a No Name buffer holding `TODO: fix the thing` with filetype lua, closed with `<M-.>`, is listed on a line holding `[No Name]`, `"TODO: fix the`, `lua` and a digit. The format is an example, so the pieces are matched on their own.
- T327 [target] (S2 Closed-stack picker; DESK:2371) Reordering the picker's lines reorders the stack: with c on top of b, swapping their lines and `:w` make `<M-S-w>` in the window you came from reopen b.
- T328 [target] (S2 Closed-stack picker; DESK:2372) `<CR>` reopens the entry under the cursor in the window you came from: on b's line it puts b in that window and leaves c alone on the stack. `<CR>` is typed with `feedkeys`, since the picker's mapping isn't known in advance.
- T329 [target] (S2 Closed-stack picker; DESK:2370) Deleting a file's line and `:w` discard it: with b and c closed, deleting c's line leaves b alone on the stack.
- T330 [target] (S2 Closed-stack picker, Tab sessions; DESK:2367) Each pool is a header with its closed entries under it: in T318's state, with x closed in the first tab and c in the session's tab, the picker's first line is a header, and a header sits between the lines naming x and c. A header is any non-empty line that names neither entry.
- T331 [target] (S2 Closed-stack picker, Tab sessions; DESK:2369) Pools merge by moving lines: in T330's state, c's line moved under x's and `:w` make `<M-S-w>` in the first tab reopen x and then c, and leave nothing for `<M-S-w>` in the session's tab.

## 8. Questions for the author

The author answered all of these on 2026-10-20. Each entry keeps its question short, gives the answer under **Answered (2026-10-20):**, with the reason where the author gave one, and points to the entries it changed.

**Q1. The current slot during cycling.** Today the current slot stays on the buffer you started cycling from until `<M-v>` **[run s03]**, as README:384 says. The old spec has it follow the cycle (SPEC:194, SPEC:393). Is "frozen until the pick" intended?

**Answered (2026-10-20):** yes. While cycling, the current slot stays on the starting buffer until `<M-v>`. The old spec is out of date (M9, A12, D10).

**Q2. What the `-swap` keys are for.** Swaps and primary jumps record the ternary under `A-swap`, plain navigation records it under `A`, and a restore prefers the `-swap` record unless it equals the current ternary. The old spec says swaps write nothing (SPEC:240), and STATUS says they write the plain key. Which is intended?

**Answered (2026-10-20):** today's two kinds of note are intended: plain notes `dtm[X]` from navigation, and swap notes `dtm[X-swap]` from swaps and primary jumps. A restore prefers the swap note unless it equals the current ternary. The author, 2026-10-20 14:26: "Yes, today's is intended", and "I remember it was a way to circumvent around some edge cases you know, because without it would exhibit some unintuitive shits. Now, I forgot." The reasons below weren't the author's; they were found afterwards by runs on scratch variants:
- If swaps wrote plain notes, toggling with `<M-S-f>` would overwrite the note with the toggle partner, and the next restore would throw "Remembered ternary is the same as current ternary".
- If swaps wrote nothing, after a primary jump and coming back, a restore would give an older buffer instead of the one you had right before the jump.

The first reason is exactly why the secondary restore throws after a round trip when `<M-f>` writes a plain secondary note. "Keep the older one" (decided 2026-10-20 evening, built in step 3) gives the secondary map the same two kinds of note (M7).

(M7, A6, A7, A11, D7, D20)

**Q3. Graduation copies the ternary's memory into the secondary map.** When `<M-f>` moves the ternary b into an empty secondary, it also sets `dsm[b] := dtm[b]` (`window/routines.lua:484-485`). Intended, or should the graduation leave dsm alone?

**Answered (2026-10-20):** intended. The author's reason: the graduated buffer's predecessor can then come back either as the ternary (`<M-;><M-r>`) or as the secondary (`<M-;><M-t>`) (M7, A6). Under "Keep the older one", graduation also clears the graduated buffer's secondary swap note, so the copy is what the restore finds (T184). Built in step 3.

**Q4. Window-view numbering.** With `history_view = "window"`, entering a window adds n−1 to `history_index`, which looked like it would make the next visit tie with the window's newest entry. Should the counter end one higher?

**Answered (2026-10-20):** replaced by a property test: after any visit, in either `history_view` (`"global"` or `"window"`), across windows, the visited buffer is leftmost in the bufferline order (T149). The suspected tie wasn't reproduced: with two windows, going back into window A and `:e e` gave `e=7 b=6 a=5 d=4 c=3` (M4).

The tie fix of D11 (step 3) makes the counter end one higher; the author's check then reads `e=8 b=7 a=5 d=4 c=3`, the same order (T149, T197, T288).

**Q5. How many buffers the bufferline shows.** The "recent" set is built over `math.max(#ordered, 30)` entries (`ui/routines.lua:374`), so every tracked buffer is shown. A cap at 30, or everything?

**Answered (2026-10-20):** the bufferline shows every tracked buffer. `math.max` stays, and the 30, which means nothing there, goes (the 30 decided 2026-10-21; M12, T122).

**Q6. The "avoided conflict" warning on `<M-f>`.** On the `<M-f>` path, `reconcile_triquetra`'s guard runs after the swap, so its rewrite is a no-op, but it still warns **[run s18]**. Should the guard run only for a cycling pick of an outside buffer?

**Answered (2026-10-20):** no. The conflict is real and the warning isn't spurious.
- The fix: on **every** route onto the secondary, run the guard **before** the swap, so `dtm[T]` is rewritten to the buffer being left. The routes are `<M-f>`, a cycling pick of the secondary, `<M-;><M-f>` falling back to `<M-f>`, and plain navigation onto the secondary (`window/hooks.lua:50-53`), which has no guard today.
- Setting `proc = true` alone keeps the crash.
- The repro, observed: `:e a`, `:e b`, `:e c`, `:e b`, `<M-f>`, `:e a`, `<M-f>`, `<M-f>` (the warning, no change), `<M-S-f>`, `<M-;><M-r>`. It throws today and restores fine with the fix.
- History: the guard was added in ae209e42 (2025-06-12) inside `if not proc`, and `proc` dates from d89061a3 (2025-06-11). The fall-through wasn't deliberate.
- After the fix, random walks still showed 13 ternary-restore throws in 1,500. They were traced to arrivals that skip the stale-note check in navigation, and "Keep the older one" closes them (A1, A11, Q13).

(A1, A6, A8, A13, T150–T153)

Built in step 3: the guard before the swap on all four routes (A6).

**Q7. Cancelling a cycle, and slot keys while cycling.** There's no cancel key. `<M-;><M-f>` returns to the start but stays in cycling mode, `<M-f>` does the same when you've cycled away, and `<M-S-f>` on the start does a real ternary swap while still cycling **[run s04]**. Should there be a cancel, and what should the slot keys do while cycling?

**Answered (2026-10-20 15:37):** on a cancel: "no, <M-v> is for that, after your press <M-f> to go back to the starting buffer." On the slot keys while cycling: "bro, just take a look, I already dealt with that.", so the code is intended (A14):
- `<M-f>` and `<M-S-f>`, when the window isn't showing its current slot, jump back to it; when it is, they do their normal job.
- `<M-;><M-f>` while cycling always returns to the cycle's start (A8 step 2), even when the window is already on it.

(A8, A14, D10, T55, T77, T78.) `<M-;><M-f>` pressed while cycling with the window already on the start announces the origin again and changes nothing: that's the code's behaviour, which this answer keeps (A14). A jump to another window, decided on 2026-10-20 evening, cancels the cycle (A12).

**Q8. `toggle_primary` on a non-empty queue.** On an empty queue, `<M-;><M-x>` makes the current buffer the primary. After that it only flips enabled, even on another buffer: at c with `p=[b]off` it gives `p=[b]on`, not `[c,b]`. Is that intended?

**Answered (2026-10-20):** the split is intended. `<M-;><M-x>` (`toggle_primary`) is the on/off switch, and seeds the queue only when it's empty. `<M-;><M-c>` (`set_primary`) makes the current buffer the primary. Only the keymap description, "Toggle current buffer as primary" (`init.lua:105`), changes. The README has the two keys swapped, which is a bug (M8, A9, A10, D1, T156).

**Q9. A cycling pick of an outside buffer.** Cycling from e with `{c=e s=c t=d}` and picking b gives `{c=b s=c t=d}`: e leaves the triquetra and isn't recorded anywhere **[run s04]**. Is losing e intended, or should it be remembered?

**Answered (2026-10-20):** remembered. The pick also writes a note on the picked buffer, `dtm[picked] := start`, so `<M-;><M-r>` on it brings the start back. The ternary itself stays unchanged, so README:347 holds (M7, A13, T155).
- **And it clears the picked buffer's older swap note** (the author, 2026-10-20 evening: "Yes, delete it"), as navigation already does for the buffer it leaves (`window/hooks.lua:67-68`, added in 6f66e36, 2025-07-12, "fix(displacement_management): added line to clear swap displacement on normal displacement."). Without it, an older `dtm[b-swap]` wins the restore and the start is lost **[runs `t/pkB_q9_*.lua`, the pick's note simulated]** (T172).

Built in step 3: the note and the cleared swap note, on a pick only (A13).

**Q10. A disabled primary.** README:31 says `<M-;><M-f>` does nothing while the primary is disabled. The code acts like `<M-f>` instead, and saving the primary window re-enables the primary. Which should hold?

**Answered (2026-10-20):** with the primary disabled, `<M-;><M-f>` acts like `<M-f>`. The code wins and README:31 changes. Saving the primary pop-up switches the primary on **only when the first row changed** in the new queue. Otherwise the queue is saved and the on/off state stays as it was (M8, A8, A18, D5, T54, T101, T158).

**Q11. Saving the primary window with a bad line.** With two valid paths and one missing file, today the two are saved and the third is reported; README:28 says nothing is saved. All or nothing, or partial?

**Answered (2026-10-20):** a partial save: the good lines are saved and the bad ones reported. README:28 changes. A new feature comes with it:
- In the pop-up, `<M-e>` (normal mode, that buffer only, configurable) opens a file picker through a provider.
- The default is telescope's `find_files` with multi-select, when telescope is installed.
- The selection or selections go on the cursor's line if it's empty, otherwise after it. Then `:w` validates as usual.
- With no picker, a message.

(A18, D6, T99, T159, T160)

**Q12. `q` and `<C-c>` in the primary window.** Both are described as "Close without saving", but they write first. Should they discard the edits?

**Answered (2026-10-20):** no. They save and then close, as today. Their labels change from "Close without saving" to "Save and close" (A18, D12, T100, T161).

**Q13. A restore that finds the slot's own value.** If the remembered value equals the current slot, the code throws "This is impossible…"; SPEC:176 shows "No different ternary relationship to restore". Throw or notify?

**Answered (2026-10-20):** keep the assertion. The restore throws when the remembered value equals the current slot, and the routes that still reach it get hunted by tests (T154). The old spec's message (SPEC:176) is out of date (A11, D9, T66). The routes found so far share one cause, and "Keep the older one" (decided 2026-10-20 evening) is the upstream fix (I23, T177–T190). Built in step 3: with it, T154, T190 and T335 find no route to the throw.

**Q14. An empty queue that's still "enabled".** When cleanup prunes every primary entry, `primary_enabled` stays true **[run s06]**. Should an empty queue force it off, as the load already does (`window/init.lua:58`)?

**Answered (2026-10-20):** fix only the key. An empty queue may stay switched on. `<M-;><M-x>` on an empty queue queues the current buffer and switches on, whatever the switch said, so one press does the job (A9, I19, T157).
- Shown **[run s19]**: primary `b`, `b.txt` deleted on disk, `:e d` gives `p=[]on`; the first `<M-;><M-x>` gives `p=[d]off`, the second `p=[d]on`.
- The route through a deleted file goes away once missing files stay tracked (desk). Whatever cleanup still removes from the queue can empty it.

Built in step 3 (A9, T157).

**Q15. Duplicates on the closed stack.** Nothing stops one hash appearing twice, and a reopen removes only the newest copy. Should the stack be deduplicated, keeping the newest?

**Answered (2026-10-20):** one copy per pool, newest wins. A re-close moves the file to the newest position, and a merge of pools keeps only the newer entry (M5, I22, T162).
- No route makes a duplicate today **[run s20]**: closing, reopening by hand and closing again; `<M-S-w>` then closing again; renames; closing while cycling. The question's original example, the primary pop-up pushing a path that's already closed, can't happen: a closed path keeps its record, and the pop-up only pushes paths with no record (`window/routines.lua:44-55`).
- The route that makes it real is the desk's per-tab pools: the same file closed in two tabs, then both entries merged through the picker.
- Left for the tab-session work: whether reopening a file from one tab's pool also takes it out of the other pools.

**Q16. Can the primary also sit in a slot?** SPEC:44 calls the primary mobile, and the code allows it. README:368 says a buffer can't occur twice in a triquetra, and `get_buffer_relationships` asserts one role per buffer, so it throws when current = primary. Is README:368 about the three slots only?

**Answered (2026-10-20):** yes. The primary is mobile, as the author intends, and README:368's "no buffer twice" covers the current, secondary and ternary only. `bufferline.get_buffer_relationships`' one-role assertion is fixed or removed. Nothing calls it, neither cavediver nor the author's config (M8, M12, I1, D19, T119).

**Q17. `<M-.>` on an untracked buffer.** In `:help`, `<M-.>` throws, because help isn't in the history (desk bug). What should it do?

**Answered (2026-10-20):** today it throws at `history/routines.lua:588`, observed in `:help` and in a `:terminal`. Decided:
- In a window with a triquetra that's visiting something untracked, close the visited buffer and land the window on its current slot.
- In a window born untracked (no triquetra, such as a `:help`, `:copen` or terminal split), close the buffer. Neovim closes that window when others exist; if it's the only window, Neovim picks what's shown.
- A terminal whose job is still running is refused with a message, as an unsaved file is.

(A15, T84, T164–T167)

Built in step 3: all three (A15, T84, T164–T167).

**Q18. Re-pointing without an event.** When cleanup finds a window showing a different tracked buffer from its current slot, with no `BufEnter`, it sets `c :=` that buffer and drops the old current from the triquetra. Plain navigation would move the old current to the ternary. Should re-pointing behave like navigation?

**Answered (2026-10-20):** yes. Cleanup's re-point without an event acts like navigation: the old current goes into the ternary (A21, T163). Built in step 3: the re-point acts like navigation, notes included, the trade with a shown secondary too (A21).

**Q19. Which way `<M-n>` and `<M-m>` go.** They call cokeline's `by_step("focus", -1)` and `+1`, and the bufferline puts the newest buffer on the left. Is "`<M-n>` toward newer" the intended direction?

**Answered (2026-10-20):** confirmed. `<M-n>` steps left, toward newer buffers; `<M-m>` steps right, toward older ones (A12, T79).

**Q20. Shared transition modes.** The engine keeps transition modes in one table for every machine. A hook on the history machine could name navigation's `winenter` mode without an error. Should modes be per machine?

**Answered (2026-10-20):** shared on purpose. Modes are one vocabulary for orchestrating all machines; a machine seeing a mode another machine registered is intended. The code and comments change to say so: the class declares the shared table, the factory comment is fixed, and the two per-machine checks are reworded or dropped (M11, T6).

**Finding (2026-10-20):** the factory (`engine/init.lua`) gives each machine its own states, transitions, hooks and history, but not `transition_modes`. So all seven machines (six once the window machine goes, D25) share the class's one table (`engine/state-machine.lua:111`), and every machine sees all four modes: `delete`, `update`, `cycle` and `winenter`. This was checked at run time with `rawget`. Today no hook names another machine's mode: hooks from other domains register on the machine that owns the mode, for example `history/hooks.lua:67-69` on the navigation machine.

**Q21. Engine transition history.** Every machine appends each transition to `sm.history` forever, and the UI loop alone adds several a second. Should it be capped?

**Answered (2026-10-20):** no cap. Each machine's transition history keeps growing for as long as the editor runs. In the author's words: "Nah. Let it run!"
- The measured cost: the `ui_loop` machine adds about 7 entries a second while idle (72 in 10 s), and 600,000 entries take about 8 MB. That's roughly 8 MB per day the editor stays open.
- Nothing in the code reads `sm.history`; it's there for debugging.

(M11, T7)

## Appendix: test harness notes

How the runs in this draft were done, and what a test suite has to account for.

**Sandbox.**
- Run `nvim --headless --clean` with the `XDG_*` variables pointed at a scratch folder, the plugin prepended to `runtimepath`, and the cwd a scratch copy of a few files.
- Check that `stdpath("data")` and the cwd are inside scratch before acting.
- Call `setup({ session_dir = <scratch>/… })` before acting: nothing is tracked until `setup()` creates the autocmds (A25).

**Stubs.**
- `package.preload['harpoon'] = function() return { list = function() return { display = function() return {} end } end } end`. The UI's refresh and the ordered list both `require('harpoon')`.
- `package.preload['cokeline.mappings']` needs `by_step(kind, step)`, `is_picking_focus()` and `is_picking_close()`. The runs here moved through cavediver's own ordered list (index 1 = newest), so cycling direction against real cokeline is unverified. With no stub at all, a step goes through cavediver's own ordered list too (A12).

**Things that bite:**
- **Errors are hidden.** Hook errors are caught and only show up through `vim.notify`, with a stack trace. Replace `vim.notify` with a collector and check it after every action. An error from `to()` itself, like `hide_bufferline()`'s unregistered transition, a slot action's `error()`, the restore's throw, or a failure of the critical save hook, does propagate, so wrap actions in `pcall`.
- **Inside a hook, `sm:state()` is the old state.**
- **Timers only run while the event loop runs.** That covers the cleanup tick (4 s, first tick at once) and the UI tick (about 140 ms). Use `vim.wait(ms)` to let them run. The slot logic doesn't need the timers.
- **Arrivals and window entries settle first.** Every `BufEnter` arrival and every `WinEnter` waits for `vim.schedule` (P2), and so do the landing after a delete (A19), the cancel of a cycle on a window jump (A12), the undo on `OptionSet` (I10), a rename and a write (A20), and a load's follow-up and its `:restart` reload (S1). Some are nested: a `WinEnter` while cycling settles, then schedules the cancel, whose switch back fires a `BufEnter` that settles in turn. So let the loop run (`vim.wait`) before checking slots, history, what a window shows or which state navigation is in.
- **Only what a window shows once it settles is slotted.** Arrivals made inside one call or one batch of keys (a macro, a mapping that switches buffers several times, `:bufdo`, a loop of `:edit`) are judged once the editor settles, so only what each window shows then is slotted and recorded (A1). The setups that open files in a loop wait 10 ms after each one (T9, T122, T309), and `K.walk` waits 10 ms after each action and each cycle step (T190, T335), as typing does.
- **Loads in one process.** A load after a save or a load in the same process tears down first and goes through (S1). Calls to `load_session` in one batch load once, so let the loop run between two loads that should both happen (T297). A case about what comes back in a new editor saves in one process and loads in the next, keeping the same `XDG_DATA_HOME` and the same cwd, because the file is named after the session's directory, the global cwd for a whole-editor session, and the session's name; the cases pass the cwd as the name. To fake a manager restore, use `bufadd` and `bufload` with `buflisted`, plus `noautocmd edit` for the shown file; `noautocmd badd` reproduces the unloaded-buffer case.
- **Fresh windows track nothing.** The first buffer nvim shows isn't registered until something enters it, so start every scenario with `:e a.txt`.
- **Splits don't fire `BufEnter`.** `:vsplit` creates the second window's triquetra, with an empty history entry, once its `WinEnter` settles.
- **Use files that exist on disk**, unless the case is about a missing one. A buffer whose file is missing stays tracked (M3), but a closed slot or closed entry whose file is gone is pruned at the next pass (A21, A22).

**Scenarios behind the [run] marks.**

| Run | What it covers | Where |
|---|---|---|
| s01 | navigation, `<M-f>` graduation and swaps, `<M-S-f>`, restores with no entry, `:e` to the secondary | A1, A6, A7 |
| s02 | the ternary flip-flop, `toggle_primary`, `set_primary`, `jump_to_primary` (enabled, disabled, already on it), restore after a primary round trip | A8–A11 |
| s03 | cycling: the frozen current slot, the live origin table, a pick of the ternary | A12, A13 |
| s04 | a pick of an outside buffer and of the secondary, slot keys while cycling, `<M-v>` in normal mode | A13, A14 |
| s05 | `:bdelete` of the secondary (pruned), `<M-.>` landing, `<M-S-w>` | A15, A16, A19 |
| s06 | closed ternary kept; closed secondary and primary kept only while the ternary is closed | A19, A21 |
| s07 | `:vsplit`, `:e` in the split, the jump history, `<M-,>`, help, closing a window | A3–A5, A17 |
| s08, s09 | a new unsaved file wiped at the next `:e`, with a trace to `window/routines.lua:428` | A21, D14 |
| s10, s11, s12 | the save file's format, the `idle->loading` throw, a load with unloaded buffers (slots lost), a happy-path load (`primary_enabled` flips on) | S1 |
| s13 | `setup()` with no argument | A25 |
| s14 | winbar strings, `get_buffer_relationships` | M12 |
| s15 | `:terminal` in a tracked window drops its triquetra | A2 |
| s16 | `get_smart_basename` is nil; `:vsplit` without a history entry makes the save fail; shared modes; engine history growth | M11, A4, A24 |
| s17 | `history_view = "window"` ordering | M4 |
| s18 | A1's "Duplicates detected in current triquetra" throw and the stale-note check in navigation, and the "avoided conflict" warning on `<M-f>` | A1, A6, Q6 |
| s19 | a primary queue emptied by pruning while switched on, then `<M-;><M-x>` twice (`t/q14_empty.lua`) | A9, I19, Q14 |
| s21 | slot keys, the primary and `<M-n>` with cokeline missing (`t/nocokeline.lua`) | A12, D27 |
| s20 | (`t/q15_dups.lua`) routes that might push a file twice onto the closed stack: close, reopen by hand, close again; `<M-S-w>` then close again; `:saveas` and `:file` renames; `:bdelete` while cycling | M5, I22, Q15 |

**Variants behind the [sim] marks.** Each is a copy of the plugin with one change. Runs and variants named `rt_*` come from the research of 2026-10-20 evening into the secondary restore's round trip, and those named `kt_*` from the research into "Keep the older one" for the ternary map.

| Variant | What it adds to today's code |
|---|---|
| `rt_q6` | Q6's guard, before the swap, on all four routes onto the secondary |
| `rt_base` | `rt_q6`, plus D8's notes on plain navigation onto the secondary, written the way `<M-f>` writes them today |
| `rt_c3kga` | `rt_base` with "Keep the older one" on the secondary map: the swap key, the plain note becoming the previous secondary on arrival, graduation clearing the swap key, the fallback comparing with the secondary, and a stale secondary note dropped on every other arrival |
| `rt_tb` | a drop of the stale ternary note on `reconcile_triquetra`'s arrivals and on plain navigation onto the secondary, on a base with Q6's guard and without the secondary changes |
| `kt_rewrite` | `rt_c3kga` plus the stale-note check on every arrival for the ternary map, with the ternary's own note where the ternary stays put |
| `kt_literal` | the same, with navigation's second case taken word for word |
| `kt_drop` | the same call sites, dropping instead of rewriting |
| `kt_rewrite_sec` | `kt_rewrite` plus the secondary map's rewrite to the swap note on other arrivals: the decided fix as tested |
| `d9U` | D9's missing-file rule |

The walks: 1,500 walks of 25 keys, in one window, with `history_view = "global"`, on seeds 7 and 11. None of the variants has Q9's pick note, A12's window-jump cancel or D11's fill assertion.

## What the answers of 2026-10-20 settled

The answers settled D1, D5, D6, D7, D10, D12, D19 and D20, and part of D9. The author settled D2, D3, D4, D8, D9 (the rest), D11, D13, D14, D15, D16, D17, D21, D25, D26, D27, D28 and D29 directly, and D18, D22, D23 and D24 by archiving STATUS (and CLAUDE.md, for D18).

All 21 questions are answered.

The last item settled, now carried by the body: M7 (the notes), A1 (the check on every arrival), A6–A8, A11 and A13 (each key), I23 (the rule) and T177–T193 (its tests).
- **The restore errors: decided (2026-10-20 evening), "Keep the older one"; settled on both sides.** One rule behind every restore throw (the round-trip research, 2026-10-20): a buffer becomes current while its note names the buffer already in that slot. The fix is a check whenever a buffer becomes current, by any key, on both maps. A stale note is **rewritten to the buffer from before**, the way the stale-note check in navigation already does on `:e` (`window/hooks.lua:71-85`, 8d278d1). It's dropped only when nothing older is on record.
  - **Decided (2026-10-21): the check also runs wherever a slot changes under the current buffer**, not only when a buffer becomes current: after either restore's slot exchange (`window/routines.lua:743-759`), graduation (`:482-487`), the history fill of an empty secondary (`:488-490`), a cleanup pass that moved a window's slots (`:142-454`), and a session load (`storage/routines.lua:257-299`). At the slot exchange a stale ternary note becomes **the ternary's own note** (the author: "The ternary's own note"), falling back to dropped when there's nothing older or when it would name the current buffer. Tested: I23 broke 0 times and no restore threw, over seeds 7 and 11, one window and several, both views, and a restore-heavy mix. Today the same walks break I23 about 10,000 times. The only exception is the window-view tie bug (D11, T197), which hit every variant and today's code alike **[sim, variant `ex_a`]** (T189, T206).
  - **Every fix together (2026-10-21).** Keep the older one with the check wherever a slot changes, the window-jump cancel with the landing recorded, the fill assertion, the window-view tie fixed, and the Q9 pick note, all in one copy of the plugin (variant `all_fixed`): 0 I23 breaks, 0 I1 breaks, 0 fill assertions, 0 restore throws, 0 "Duplicates detected", and no other error or hook failure. That's over 900,000 walk steps: one window, several windows, cycles left open across a jump, and a restore-heavy mix, on seeds 7, 11 and 13, under both views. On the same walks today's code breaks I23 86,286 times and throws 5,203 times, plus 380 "Cycling origins not found" and 4 "Invalid window id" hook failures, all from cycles left open across a jump. The window-view runs now repeat exactly **[sim, `all_fixed`]**.
  - **Not reached by the walks:** deleting files (so the cleanup pass's re-points), loading a session, jumping into floats or pickers, and the window-jump cancel's timing. The walks ran the cancel straight away inside `WinEnter`, never after the editor settles as decided. T154 and the flight recorder (A26) cover what random walks don't.
  - Secondary side: each buffer gets a second note (a swap key in `dsm`) so "before" is known; graduation clears it; the restore's swap-note fallback compares with the slot it restores into (`window/routines.lua:720` compares with the ternary for both today); renames carry `dsm` swap keys (`window/data.lua:137-140`); the missing-file rule (D9) covers `dsm`. Tested in random walks: 204 throws with tonight's decisions → 0 **[sim, variant `rt_c3kga`]**.
  - Secondary side, as tested: on a round trip the older buffer is on record (the swap note) and comes back. On other arrivals there's almost never anything older on record, so the stale note is dropped (122 rewrites, 375 drops, one restore changed in 3,000 walks) **[sim, variant `kt_rewrite_sec`]**.
  - Ternary side, **decided (2026-10-20 evening)**: the same check runs on the arrivals that skip the stale-note check in navigation today (`<M-S-f>`, `<M-f>` and its fallback, plain `:e` onto the secondary, cycling picks, primary jumps). Where the ternary changes, it rewrites as navigation's check does. Where the ternary **stays put**, "the pre-jump ternary" is the very buffer the stale note names, so the stale note is rewritten to **the ternary's own note** instead. The author: "Yes, the ternary's own note". Taken word for word, navigation's two cases leave 11 and 8 throws (`kt_literal`).
  - Tested over two sets of 1,500 walks (seeds 7 and 11): **0 ternary and 0 secondary throws**, no duplicate slot, no other error **[sim, variant `kt_rewrite`]**. The same under `history_view = "window"`: single-window walks run step for step as under the global view, since the window view only re-ranks history on entering another window **[sim, 2026-10-21]**. Against dropping on the same walks: 21 restores bring back a buffer from outside the slots where a drop finds nothing. 42% of rewrites find no older note and act as drops. 5% point at the window's secondary, so that restore just exchanges the ternary and the secondary, and the buffer's secondary note is dropped on the way (`kt_tosec`). Zero in random walks is evidence, not proof: T189 is a route the walks missed, and T154 and T190 keep hunting.
  - Code the change touches (from the variants): `reconcile_triquetra` (`window/routines.lua:93-135`), `jump_to_primary` (`:651-654`), and plain navigation onto the secondary (`window/hooks.lua:52-54`). Navigation's own check (`hooks.lua:71-85`) stays as it is.
  - What the evidence covers: every walk was 25 keys in one window, with `history_view = "global"`, and no variant had Q9's pick note, A12's window-jump cancel or D11's fill assertion, so the walks' picks of outside buffers wrote no note. The routes in T177–T193 were run on the variants each test names; their key sequences are their record.

**Bugs found while porting the tests (2026-10-21)**, recorded as bug (new):
- `<M-.>` on a modified No Name buffer caches its lines and filetype but not its cursor: `delete_buffer` switches the window away (`history/routines.lua:664`) before `bw!` (`:668`), so `bufwinid` at `:548` finds no window and `:552` falls back to `{1,0}` (T83, T90). Fixed in step 3: `delete_buffer` keeps the cursor on the buffer before switching away (T83).
- `:help`, then `:only` before anything is tracked: the UI loop's hook fails on every tick with "Invalid window id: 1000" (`window/data.lua:78`). It keeps T166 failing even after Q17's fix. Fixed in step 3: the getter returns nil for a window that's gone, and `find_most_recent_tracked_window` doesn't return a closed `last_valid_window` (T166).
- A tracked buffer wiped with `noautocmd`: the UI loop errors on every tick until the next cleanup tick. Fixed in step 3: the UI refresh repairs it on the spot (T242).
- Under the window view the history rebuild also ties on `:close` (`:e a`, `:e b`, `:vsplit`, `:close`, `:e a` gives a=4 b=4); the tie fix (T197) covers it. Fixed in step 3, with the tie fix (T288).

**Still open: two items need the author's answer.**
- **D2:** the default colour of the new `colors.cokeline.is_picking_focus` (T168).
- **Q15, left for the tab-session work:** whether reopening a file from one tab's pool also takes it out of the other pools.
