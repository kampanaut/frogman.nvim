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
| P1 | What's shown on the screen is what cavediver knows, always. | DESK:19, DESK:1781 | Not held. Slots, the registry and the caches are copies updated after the fact, and cleanup changes the screen to fit the model (A21). |
| P2 | The settle rule: act after the editor settles, never inside the event, and look at what's on screen then. | DESK:14, DESK:82, DESK:1783 | Not held. Everything runs inside `BufEnter`/`BufDelete`/`WinEnter`, except healing's switch and the landing after a delete, which wait for `vim.schedule` (`window/routines.lua:411-415`, `:149-220`). |
| P3 | Session-manager agnostic, no adapters. Two exports: the manager restores buffers and layout, then cavediver lays its triquetras over what came back. | DESK:13, DESK:751 | Partly. The two exports exist (`init.lua:374-375`), but the README makes resession a requirement (README:44) and the load matches windows by position (`storage/routines.lua:199-209`). |
| P4 | Cooperate rather than force: wherever cavediver bends the editor or other plugins to its model, that gets fixed. | DESK:21, DESK:2083 | Not held. The save switches oil windows (`storage/routines.lua:500-510`), cleanup's healing can switch windows (A21), cavediver owns the winbar, and plugins are special-cased by name. |
| P5 | Regular files only. Cavediver tracks regular file buffers and No Name buffers, nothing else. | README:366, DESK:37, DESK:2162, `history/routines.lua:41` | Partly. Today's rule is `buftype ""` with no `://` or otter name (`history/routines.lua:276`), with no check that the buffer is listed (M3). |
| P6 | The registry is the authority: hash → buffer and hash → path decide what a hash means. | DESK:1364, `window/hooks.lua:25` | Held as a design. Its gaps are listed under I2. |
| P7 | The user never registers a buffer by hand; registration is automatic. | `window/routines.lua:37` | Held. |
| P8 | Cleanup repairs only cavediver's own data and never touches a buffer or a window. | DESK:19, DESK:1859 | Not held. Cleanup wipes nothing, but its healing can still switch a window to its new current slot (A21). |
| P9 | Missing files aren't forgotten. A pointer to a file gone from disk is kept, and says so when it's used. | DESK:20, DESK:2022 | Partly. A buffer whose file is missing stays tracked, and a slot pointing at an open buffer is kept whatever the disk says (M3, A21). A closed slot or closed entry whose file is gone from disk is dropped (A21, A22). |
| P10 | Follow along: displacement maps and history never keep anything alive. Their entries go once what they point at is no longer known. | DESK:83, DESK:2029 | Not held. The maps are never pruned (M7), and history entries go as soon as the buffer is unregistered. |
| P11 | Errors in the state machine shouldn't happen. An error from `to()` is a loud bug, a bug inside a hook is caught with a stack trace, and the save hook is critical. | DESK:1154-1157 | Partly. Hook errors are caught with the message only (`engine/helpers.lua:36-43`), and the save hook isn't critical. |
| P12 | Nothing runs at `require`. `setup()` creates the autocmds (in one augroup), the commands and the timers, and can be re-run. | DESK:2177 | Not held. Autocmds and user commands are created at require (`init.lua:369` and every `hooks.lua`), with no augroup. |
| P13 | You can always get back to what once was: the secondary and the ternary can always be restored. | README:7; confirmed by the author (2026-10-20) | Partly. The restores work (A11), but a closed slot whose file is gone from disk gets pruned (A21), and some routes make a restore throw instead (A11; the decided fix is "Keep the older one", M7). |
| P14 | The secondary is yours: it changes only when you act. | README:353, SPEC:41, SPEC:299; confirmed by the author (2026-10-20) | Held. Going to the secondary by plain navigation counts as acting, and swaps it (A1). The author's check: `:e b`, `:e c`, `<M-f>` (graduation), `:e d`, then `:e b` gives `{c=b s=d t=c}`. |
| P15 | The ternary is your previous buffer, filled in on every jump that isn't to the secondary, and not on a cycling pick. | README:347; confirmed by the author (2026-10-20) | Held (A1, A13). A pick of an outside buffer leaves the ternary alone and will note the start on the picked buffer instead (Q9). |
| P16 | A buffer is never in more than one of a triquetra's current, secondary and ternary slots. | README:368, SPEC:343; confirmed by the author (2026-10-20) | Asserted, not maintained (I1). The primary isn't one of the three: it may share a slot's buffer (Q16). |
| P17 | Every window is independent: its own triquetra and, optionally, its own visit history. | README:17, README:374; confirmed by the author (2026-10-20) | Held. |
| P18 | Cycling is exploration: stepping with `<M-n>`/`<M-m>` records no visits and writes no displacement entries; `<M-v>` picks. `<M-f>`, `<M-S-f>` and the restores, pressed while the window shows its current slot, do their normal job, notes included, cycling or not. | README:384, SPEC:30-37, SPEC:546; confirmed by the author (2026-10-20); narrowed to the steps by the author (2026-10-20 evening, "Yes, as today") | Held. The current slot stays frozen while cycling (A12, Q1). The pick's own writes (Q6's guard, Q9's note, the stale-note check of "Keep the older one") stay, since `<M-v>` ends the cycle **[run `t/pkB_cycle_keys.lua`]**. |
| P19 | A restore flip-flops instead of being used up, with one remembered entry per buffer for each kind of note, overwritten by the next displacement. | SPEC:523-544, README:349; confirmed by the author (2026-10-20); the "for each kind of note" rewording confirmed by the author (2026-10-21) | Held (A11). The ternary map keeps a plain note and a swap note per buffer, and a restore uses one of them (Q2). Decided (2026-10-20 evening), "Keep the older one": the secondary map keeps the same two kinds, and a note that has gone stale is rewritten to the older one (M7). |
| P20 | Keys are predictable: `<M-S-f>` always does the same swap, and restoring is only ever explicit. | SPEC:512-521; confirmed by the author (2026-10-20) | Held. The swap also writes a `-swap` note, which SPEC:240 rules out; Q2 keeps the note (D7). |
| P21 | Identity comes from the file name: a hash of the name, so relationships survive restarts. | README:12, STATUS:34-40; confirmed by the author (2026-10-20) | Held, but hashing goes through the shell (M1). |
| P22 | Privacy: the session file is usage data and stays protected. | DESK:1541, `init.lua:4`, `storage/routines.lua:113` | Weak. It's XOR with the cwd as the key (S1), which DESK:1561 shows leaks the key. |
| P23 | Drift between cavediver's file and the manager's is designed out, not detected. | DESK:1056 | Not held (S1). |
| P24 | A save is a snapshot and never changes the running state. | DESK:955, DESK:1152 | Not held. A save runs `cleanup_system`, which wipes nothing but can prune the closed stack (A22), and switches oil windows (`storage/routines.lua:692`, `:500`). |
| P25 | Two invariants: a path is never forgotten while anything references its hash, and every triquetra comes with its window's history entry. | DESK:84, DESK:1058-1064, DESK:1126 | Both violated today (I2, I3). |
| P26 | Cokeline is required, as part of the UI. Harpoon is optional, through a provider. | DESK:2126, DESK:2144, README:42-47 | Harpoon is required and loaded without a guard (`history/routines.lua:336`, `ui/routines.lua:339`). |
| P27 | Cavediver reconciles any conflict between its model and the editor, "smartly". The four kinds of conflict decide who wins. | DESK:1781, DESK:1918 | Today that's healing inside cleanup (A21), and the landing after a delete (A19). |

## 2. The model

### M1. Identity and hashing

- A buffer's **name** is `nvim_buf_get_name(buf)`. A buffer with an empty name is called `NONAME_<bufnr>` instead (`history/routines.lua:43-45`, `:283`, `window/routines.lua:276-278`).
- Its **hash** is `string.sub(vim.fn.system('echo "' .. name .. '" | sha256sum'), 1, 16)` (`history/routines.lua:22-29`). For ordinary names that's the first 16 hex characters of sha256(name .. "\n"). It runs the user's shell once per call, and it's called on every `BufEnter` of a registered buffer (`:283`, `:292`). Names containing `"`, `$` or a backslash are mangled by the shell, and every name with a `"` hashes to the shell's error text, so all such files collide (DESK:2131-2140, DESK:2441, reproduced there). **bug (desk)**
- The **session file** is named after the first 32 characters of the same shell sha256 of the cwd, plus `.json`, inside `session_dir` (`storage/routines.lua:613-630`).
- **Decided:** hash with `vim.fn.sha256(name .. "\n")` (DESK:1456, DESK:2131). A No Name id is unique across sessions, built from `os.time()` and `vim.uv.hrtime()` and kept in a buffer variable (DESK:2289-2297). The file is named `sha256(directory .. name)` (DESK:1074).

### M2. The registry

Defined at `history/data.lua:71-78`:

| Table | Maps | Meaning |
|---|---|---|
| `hash_buffer_registry.buffers` | hash → bufnr | what's open now |
| `hash_buffer_registry.hashes` | bufnr → hash | reverse |
| `hash_filepath_registry.filepaths` | hash → path | everything cavediver knows, closed buffers included |
| `hash_filepath_registry.hashes` | path → hash | reverse |

Writers:
- `register_buffer(buf)` (`history/routines.lua:38-69`) writes all four. If the hash is already bound to another buffer, that buffer's reverse entry is dropped, so the newer buffer takes the hash. It throws for `buftype ~= ""` unless the filetype is `image_nvim` (`:40-42`).
- `register_filepath(path)` (`:75-86`) writes only the path pair.
- `unregister_buffer` (`:92-100`) drops the buffer pair and keeps the path.
- `unregister_filepath` (`:104-113`) drops the path pair.

A path is forgotten in three places:
- an "evolved" buffer on re-entry (`:296`, M3)
- a reopened No Name buffer, which takes a new name (`:436`)
- an empty No Name buffer being closed (`:477`)

Each of these can leave a slot holding a hash with no path (I2, DESK:1062).

### M3. Which buffers are tracked

**Today** (`update_buffer_history`, `history/routines.lua:268-303`, called on every `BufEnter` while history is attached):
- **An unregistered buffer** is registered when its `buftype` is `""` and its name contains no `://` and doesn't end in `otter.<ext>` (`:276`). There's no check that it's listed and no check that its file exists. So `:e brandnew.lua`, a file not on disk yet, gets registered **[run s08]**.
- **A registered buffer** being re-entered keeps its registration in two cases (`:282-292`):
  - it's a No Name buffer (`buftype ""`, empty name, loaded)
  - its path isn't a directory, and either its file is readable or it's a plain buffer (`buftype ""`, no `://` in the name). So a file not written yet, or deleted on disk, stays tracked (T14).

  Otherwise it counts as "evolved": a directory, or a buffer that turned into a terminal, an `oil://` listing and the like. It's untracked, unregistered and its path forgotten, and the call returns false (`:293-298`).
- **A `BufWritePost`** on an unregistered buffer runs the same update (`history/hooks.lua:76-88`).
- **The session load** registers every loaded buffer with `buftype ""` or filetype `image_nvim` whose name has no `://` (`storage/routines.lua:163-175`).

**Decided:** a tracked buffer is listed, has `buftype ""` (or `nowrite` on an existing regular file), and has a name that's empty or a plain path. A missing file says nothing about it (DESK:37, DESK:2162). The otter, `image_nvim` and `://` special cases become properties (DESK:2148-2158). Built in step 1: the missing-file sentence.

### M4. History

Fields in `history/data.lua`:
- `history_index` (`:69`): a counter that only goes up.
- `crux_internals.global` (`:61`): hash → time, for every window.
- `crux_internals.window[winid]` (`:60`): hash → time, for the visits recorded in that window.
- `crux` (`:58`): **the view** the bufferline and the close key use.
  - With `bufferline.history_view = "global"` (the default, `configs.lua:22-24`) it's a copy of the global history.
  - With `"window"`, it's that copy with the window's own entries re-ranked above every global entry (`construct_crux`, `history/routines.lua:165-198`).
- `ordered.crux` (`:65`): `{buf, time}` from `crux`, newest first. Hashes with no open buffer are dropped from the list and deleted from `crux` (`history/routines.lua:311-329`).
- `ordered.nonharpooned` (`:66`): the same list without harpooned buffers (`:353-369`). It's computed on every update but nothing reads it except `get_ordered_buffers(false)`. **[code]**

How history is updated:
- `track_buffer(hash)` (`:208-235`) does all of the following:
  - writes `history_index` into `crux` and `global`, then increments it
  - writes into the window history of `find_most_recent_tracked_window()`, which is the last-entered window that has a triquetra, not necessarily the window showing the buffer (DESK:2476) **bug (desk)**
  - removes the hash from the closed stack (`:229-234`)
- Called with a time (session load), `track_buffer` writes `history_index`, not the time, into `global` (`:215`). **bug (desk)**
- `untrack_buffer` (`:241-259`) removes the hash from `crux`, `global` and every window's history, then rebuilds both ordered lists.
- The ordered lists are rebuilt:
  - after a successful track on an update
  - on every delete transition
  - in `untrack_buffer`, `reopen_filehash`, cleanup and repopulate

  `construct_crux` doesn't rebuild them; the `BufEnter` that usually follows a `WinEnter` does **[run s17]**.
- `construct_crux(winid)` returns at once when called for the same window as last time (`:168-172`). In window view it adds n−1 to `history_index` (`:191`). That doesn't make the next visit tie with the window's newest entry: in the author's run, with two windows, going back into window A and running `:e e` gave `e=7 b=6 a=5 d=4 c=3`. The property test T149 checks that the visited buffer is always leftmost (Q4).
- `WinClosed` drops the window's history entry (`history/hooks.lua:131-139`, `window/data.lua:58`).
- A triquetra can exist with no history entry: a `:vsplit` window gets a triquetra on `WinEnter` but no entry until a visit happens in it **[run s16]**. This breaks I3.

Window view, as run in s17: window 1 visits a, b, c, then window 2 (`:vsplit`) visits d and e. In window 2 the order is `e,d,c,b,a`. Back in window 1 it's `c,b,a,e,d`, and after `:e a` there it's `a,c,b,e,d` **[run s17]**.

### M5. Closed stack and No Name content

- `closed_buffers` (`history/data.lua:82`) is an array of hashes, newest last. Entries join it from:
  - `track_closing_filehash` on every delete transition (`history/hooks.lua:53`)
  - `track_closing_filehash_force` when an unloaded path is typed into the primary history window (`window/routines.lua:54`)
  - `load_closed_buffers` (`storage/routines.lua:605`)
- Entries leave it through:
  - `reopen_last_closed` (pops the last one)
  - `track_buffer`
  - `reopen_filehash` (`history/routines.lua:417-422`)
  - the swaps' `remove_from_closed_buffers` (`window/routines.lua:81-88`)
  - `cleanup_system` (A22)

  Nothing deduplicates the stack today, but no route was found that pushes a file twice: every reopen takes the file off, and a closed file keeps its record, so the primary pop-up never pushes it **[run s20]**. Decided (2026-10-20): one copy per pool, newest wins (Q15, I22).
- `noname_content[hash] = {lines, filetype, cursor}` is cached when a **non-empty** No Name buffer is closed (`history/routines.lua:472-487`). An empty one has its path forgotten and isn't pushed (`:476-479`).
- `reopen_filehash(hash)` (`history/routines.lua:411-454`) reopens a closed hash:
  - It looks up the path and removes the newest matching entry from the closed stack.
  - **A No Name hash:**
    - It creates a new listed buffer with the cached lines and filetype.
    - It sets the cached cursor on **the current window**, before the buffer is shown there (DESK:2473). **bug (desk)**
    - It drops the cache and registers the buffer under its new `NONAME_<newbufnr>`. It tracks the buffer and forgets the old path if the name differs.
  - **A file:** if the file is readable it runs `bufadd`, `bufload` and `buflisted = true`, then registers and tracks the buffer.
  - In both cases it then runs `update_buffer_history` and rebuilds the lists, and returns the bufnr. When the file is missing it returns `nil`, and the hash is already off the closed stack, since that step comes first (`:417-422`).
- The display name of a closed slot comes from its path. After a `:bdelete` the unlisted buffer still exists, conflicts with itself in `find_basename_conflicts` (`ui/routines.lua:144-155`), and the winbar shows the **full path** **[run s06, s14]**. **bug (new)**

### M6. The triquetra

One per window, in `window.data.crux[winid]`. Fields (`window/data.lua:8-15`, `:37-45`):

| Field | Type | Meaning |
|---|---|---|
| `current_slot` | hash, required | the tracked buffer the window is on |
| `secondary_slot` | hash or nil | the parked buffer |
| `ternary_slot` | hash or nil | the previous buffer, filled in automatically |
| `primary_buffer` | array of hashes | the primary queue; `[1]` is the primary |
| `primary_enabled` | boolean | whether `[1]` is active |
| `displacement_ternary_map` (dtm) | table | see M7 |
| `displacement_secondary_map` (dsm) | table | see M7 |

**Creation.** `get_window_triquetra(winid)` (`window/data.lua:73-110`) creates the triquetra lazily, holding only the current slot (the window's buffer hash), when:
- the window isn't a float, and
- its buffer is registered.

It's called in these places, so a new split gets its triquetra on the next `WinEnter` or UI tick **[run s07, s16]**:
- by `ensure_curwin_crux` on every history update (`window/hooks.lua:16-22`)
- by `find_most_recent_tracked_window` (`navigation/routines.lua:94`)
- by every slot action
- by the UI's derive path (`ui/routines.lua:248`)

**Removal** goes through `unregister_triquetra` (`window/data.lua:51-67`). It happens:
- on `WinClosed` (`window/hooks.lua:130-135`)
- in the getter, when the window shows a buffer whose hash differs from the current slot, whose `buftype` is non-empty and not `acwrite`, and whose filetype isn't `image_nvim` (`window/data.lua:93-103`) **[run s15]**: `:terminal` in the window drops the triquetra
- in the healing branches of `cleanup_triquetras` (A21)

Removal also does four things:
- drops the window's history entry and UI cache
- re-points `last_valid_window` along the jump chain
- rebuilds the history view
- clears the winbar

Two other writers:
- `set_buffer_relationship` (`window/init.lua:39-62`) is used by the session load. It sets `primary_enabled` to "the queue isn't empty" whatever the saved data said (S1).
- `repopulate_window_relationships` (`window/routines.lua:866-890`) gives every window with a registered buffer a fresh triquetra. It writes a buffer number into `last_valid_window` (`:869`). **bug (desk)**

**Who writes each slot.** Every writer of each slot, so tests can cover them all:

| Slot | Writers |
|---|---|
| current | getter creation, `c := shown` (M6); plain navigation, `c := X` (A1); `<M-f>`, `c := S` (A6); `<M-S-f>`, `c := T` (A7); primary jump, `c := P`, and while cycling `c := start` (A8); cycling pick, `c := X`, `T` or `S` (A13); cleanup re-point, `c := shown`, and its fallback chains ternary → secondary → `primary[1]` → most recent (A21); the landing after a delete, `c :=` the ternary, the secondary, `primary[1]` or the most recent (A19); No Name rename (`rename_hash_in_triquetras`); session load (S1) |
| secondary | `<M-f>`: graduation `s := T`, fill from history `s := ordered[2]`, swap `s := A`, reopen failure `s := nil` (A6); plain navigation to the secondary, `s := A` (A1); cycling pick of the secondary, `s := A` (A13); restore secondary `s := remembered`, and restore ternary when it equals the secondary, `s := old t` (A11); cleanup clears it when pruned, when it equals a re-pointed current, or when it moves up into the current slot (A21); the landing after a delete clears it when it moves up into the current slot (A19); No Name rename; session load |
| ternary | **auto-population**: plain navigation `t := A` (A1), primary jump `t := A` (A8); `<M-S-f>` `t := A` (A7); cycling pick of the ternary `t := A` (A13); graduation `t := nil` (A6); reopen failure `t := nil` (A7); restore ternary `t := remembered`, and restore secondary when it equals the ternary, `t := old s` (A11); cleanup clears it when pruned, when it equals a re-pointed current, or when it moves up into the current slot (A21); the landing after a delete clears it when it moves up into the current slot (A19); No Name rename; session load |
| primary queue | `toggle_primary` on an empty queue (A9); `set_primary` (A10); a popup save replaces it (A18); the primary jump renames a reopened No Name `[1]` (A8); cleanup prunes entries (A21); No Name rename; session load |
| `primary_enabled` | `toggle_primary` (A9); `set_primary` (A10); a popup save sets it to "queue not empty" (A18); session load sets it to "queue not empty" (S1) |

The save's substitution for a No Name current slot (S1, step 3) only changes what's written to the file, not the live triquetra.

### M7. Displacement maps

Each map is keyed by a buffer that was displaced and remembers one slot value for it. dtm also has `-swap` keys. Who writes which key:

| Key | Value | Written by |
|---|---|---|
| `dtm[X]` | X's ternary at the moment X was left by **plain navigation** | `displacement_mangement` (`window/hooks.lua:66-69`), when the ternary exists and the new buffer isn't the ternary; the same write deletes `dtm[X-swap]`. Also the conflict guards (`window/hooks.lua:71-85`, `window/routines.lua:123-131`) and restore (`window/routines.lua:838`). |
| `dtm[X-swap]` | X's ternary at the moment X was left by a **swap or a primary jump** | `<M-f>` (`window/routines.lua:577`, only when a ternary exists); `reconcile_triquetra` when the chosen buffer is the ternary (`:107`), which covers `<M-S-f>` and `<M-v>` on the ternary; `jump_to_primary` (`:731`, which writes nil when there's no ternary). |
| `dsm[X]` | X's secondary at the moment X was swapped out with `<M-f>` | `<M-f>` (`:575`); the ternary-to-secondary graduation copies `dtm[G]` into `dsm[G]` (`:563-564`), which is intended (Q3); restore (`:838`). |

- Nothing writes `-swap` keys into dsm, though restore looks them up (harmless).
- The maps are never pruned. `rename_hash_in_triquetras` (`window/data.lua:118-165`) renames keys and values, and the `-swap` keys only in dtm.
- The two kinds of note are intended (Q2): plain notes `dtm[X]` from navigation, and swap notes `dtm[X-swap]` from swaps and primary jumps. A restore prefers the swap note unless it equals the current ternary (A11). The author confirmed the design but forgot why; the reasons found by runs are under Q2 in section 8.
- **Decided (2026-10-20):** more writes.
  - A cycling pick of an outside buffer X writes the plain note `dtm[X] := start` and clears X's swap note `dtm[X-swap]`, as navigation clears the left buffer's (Q9, A13).
  - On every route onto the secondary, the "avoided conflict" guard rewrites `dtm[T]` to the buffer being left, before the swap (Q6, A6).
  - Plain navigation onto the secondary records the same notes as `<M-f>` (D8, A1).
- **Decided (2026-10-20 evening), "Keep the older one".** The secondary map gets the ternary map's two kinds of note, and whenever a buffer becomes current, any of its notes that has gone stale is rewritten to the older one instead of being left to make a restore throw (A1, A11, I23):

  | Key | Value | Written by |
  |---|---|---|
  | `dsm[X-swap]` (new) | X's secondary at the moment X was left for it | `<M-f>`, its `<M-;><M-f>` fallback, and plain navigation onto the secondary (D8), in place of today's `dsm[A] := S` (A1, A6). Graduation clears the graduated buffer's swap note (A6). |
  | `dsm[X]` (meaning changes) | X's **previous** secondary, no longer the one it had when swapped out | on the same three routes, when X arrives: X's swap note, when that names a buffer other than the one being left; otherwise a plain note naming the buffer being left is cleared (A6). Graduation's copy (Q3) and the restore's flip still write it. The stale-note check rewrites it on other arrivals (A1). |

  - A restore's swap-note fallback compares with the slot it restores into: the ternary for dtm, as today, and the secondary for dsm (A11). Today `window/routines.lua:799` compares with the ternary for both.
  - `rename_hash_in_triquetras` carries dsm's `-swap` keys as it already carries dtm's (`window/data.lua:142-145`), so a renamed buffer keeps both kinds of note on both maps (T192).
  - The missing-file rule (D9) covers both maps, swap keys included (T193).
  - Stored with the rest of each map, so the save file's format doesn't change (`storage/routines.lua:495-496`) **[code]**.

### M8. Primary queue

- `primary_buffer[1]` is the primary and the rest are earlier primaries (README:22). The queue isn't deduplicated against the slots, so the primary can also be the current, secondary or ternary (SPEC:44). That's intended: the primary is mobile (Q16).
- `primary_enabled` decides two things:
  - whether `jump_to_primary` uses the queue (A8)
  - whether the UI paints the primary as active (`ui/routines.lua:309`)
- `<M-;><M-x>` (`toggle_primary`) is its on/off switch, and `<M-;><M-c>` (`set_primary`) makes the current buffer the primary (Q8).
- **Decided (2026-10-20):** a save from the primary queue window switches it on only when the first row changed (Q10, A18).
- Writers:
  - `toggle_primary` (A9)
  - `set_primary` (A10)
  - `update_primary_buffer`, from the popup (A18)
  - `jump_to_primary`, when it renames a No Name `[1]`
  - cleanup pruning (A21)
  - `rename_hash_in_triquetras`

### M9. Cycling

- Cycling is navigation state `cycling` with history `detached`.
- `cycling_origins[winid]` is **the live triquetra table itself**, not a copy. At cycle start its `current_slot` is set to the hash of the window's buffer (`history/routines.lua:377-404`) **[run s03]**. The docstring at `:374` says it stores a deep copy.
- While history is detached:
  - `BufEnter` neither tracks history nor touches slots.
  - The current slot stays the cycle's starting buffer **[run s03]**. That's intended: it stays there until `<M-v>` (Q1).
  - `nondisplacement_management` (`window/hooks.lua:110-123`) never does anything, because a `BufEnter` context carries no `winid`.
- **Decided (2026-10-20 evening):** a `WinEnter` into another window cancels the cycle: the cycling window goes back to its start and nothing is recorded (A12).

### M10. Window-jump history and window tracking

- `navigation.data.window_jump_history[to_win] = from_win` (`navigation/data.lua:41`) is one flat table, though the type comment at `:9` says it's per tab.
  - It's recorded on every `WinEnter` (`navigation/hooks.lua:30-42`). The "from" window is `winnr('#')`, or `last_valid_window` when there's none. It's skipped when that window's filetype is `minimap` (`navigation/routines.lua:31-42`).
  - Entries for closed windows are never removed. **[code]**
- `window.data.current_window`: the last window entered (`window/hooks.lua:125-128`).
- `window.data.last_valid_window`: the last window with a triquetra (`navigation/routines.lua:88-102`, `window/data.lua:60`). Both are set at require time and again by a 200 ms deferred probe (`window/data.lua:167-178`).

### M11. State machines

**Engine semantics** (`engine/state-machine.lua`, `engine/helpers.lua`). These matter for tests.
- `sm:to(next, ctx, mode)`:
  - It deep-copies `ctx`, then sets `ctx.caller` (the machine's name) and `ctx.mode` (`mode` or `"*"`).
  - The transition `current->next` must be registered. It's registered only once some hook has been bound to it with `on()`, so a transition with no hook throws `Transition '…' is not registered` from `to()` itself (`:491-493`).
  - **The new state is set after every hook has run** (`:498-499`), so `sm:state()` inside a hook returns the old state.
- **Pipeline:**
  - Only enabled hooks bound to that exact transition run, sorted by class, lower first.
  - The sort is `table.sort`, which isn't stable for equal classes.
  - General hooks would run before and after; none are registered.
  - The transition is appended to `sm.history`, which grows without limit. The UI loop alone adds about ten entries a second **[run s16]**. That's intended: there's no cap, and the history is there for debugging; nothing in the code reads it (Q21). Measured on 2026-10-20: about 7 entries a second from `ui_loop` while idle (72 in 10 s), and 600,000 entries take about 8 MB, so roughly 8 MB per day the editor stays open.
- **Mode filter** (`helpers.lua:241-281`):
  - `to()` with no mode runs only hooks registered with filter `"*"`.
  - `to(…, m)` runs `"*"` hooks plus those whose filter includes `m`.
- **Errors:** every hook runs inside `pcall`. A failure becomes a `vim.notify` ERROR, "Hook '<name>' failed during transition a->b: …", and the pipeline goes on. The state still changes.
- **Shared modes:** `transition_modes` is a class-level table shared by every machine, so all machines know `cycle`, `winenter`, `delete` and `update` **[run s16]**. That's intended: modes are one vocabulary for orchestrating all machines, and a hook may name any registered mode (Q20). A mode doesn't travel between machines on its own; each `to()` names its own, and today every call passes a mode its target machine registered.
  - **Decided (2026-10-20):** the code says so. The class declares the shared table on purpose, the factory comment (`engine/init.lua:18`, "its own independent state, transitions, hooks, and history") stops implying modes are per machine, and the two checks worded per machine (`helpers.lua:258`, "This state machine doesn't have any transition modes registered", which can't fire with a shared table, and `helpers.lua:276`, "not registered in this state machine") are reworded or dropped.
- **Two engine bugs:** `off()` removes from `self.bindings` by index, and `unregister_hook` calls the class instead of the instance (`state-machine.lua:361`, `:382`). **bug (desk)**

**Machines:**

| Machine | States (initial first) | Transitions in use |
|---|---|---|
| navigation | `normal`, `cycling`, `file_picker` (never entered) | `normal->cycling`, `cycling->cycling` and `cycling->normal` (mode `cycle`); every self-transition (mode `winenter`) |
| history | `attached`, `detached` | self-transitions (`update`/`delete`), `attached->detached`, `detached->attached` |
| window (`window/sm.lua`) | `showing_primary`, `showing_secondary`, `showing_ternary`, `showing_other` | none; never transitions. Decided (2026-10-20): the machine is removed (D25, T170). |
| ui_bufferline | `bufferline_visible`, `bufferline_hidden` | none registered, so `hide_bufferline()`/`show_bufferline()` throw **bug (desk)** |
| ui_indicators | `indicators_on`, `indicators_off` | none registered, so the same throw |
| ui_loop | `self` | `self->self`, which refreshes the UI |
| (ui winbar) | used by `ui/init.lua:99`, `:106`, `:138`, but never created | `hide_winbar()` and `show_winbar()` index nil **bug (desk)** |
| storage | `bare`, `idle`, `saving`, `loading`, `error`, `auto_saving` | `{idle,bare}->saving`, `bare->loading`, `{bare,saving,loading}->{idle,saving}`; `error` and `auto_saving` are never used |

**Hooks**, in the order they run within each transition:

| Machine | Transition | Mode | Class | Hook | What it does |
|---|---|---|---|---|---|
| navigation | normal→cycling | cycle | 1 | `start_cycling` (`navigation/hooks.lua:12`) | history → detached (mode update), then step once |
| navigation | cycling→cycling | cycle | 1 | `keep_cycling` (`:19`) | step once |
| navigation | cycling→normal | cycle | 1 | `stop_cycling` (`:23`) | history → attached with `{buf = picked}` (mode update), then a UI refresh |
| navigation | *→* | winenter | 1 | `winenter_record_window` (`:30`) | records the window jump |
| navigation | *→* | winenter | 2 | `winenter_track_current_window` (`window/hooks.lua:125`) | sets `current_window` |
| navigation | *→* | winenter | 3 | `winenter_update_history_view` (`history/hooks.lua:59`) | `construct_crux(find_most_recent_tracked_window())` |
| navigation | *→* | winenter | 4 | `winenter_update_ui` (`ui/hooks.lua:37`) | UI refresh |
| history | *→* | delete | 0 | `handle_deletion` (`history/hooks.lua:42`) | for a registered buffer: push it on the closed stack, untrack it, unregister it |
| history | *→attached | * | 1 | `attach_history_update` (`:12`) | on update: `update_buffer_history(buf)`, then reorder if it changed, and set `context.history_modified`; on delete: reorder |
| history | *→* | update | 1 | `ensure_curwin_crux` (`window/hooks.lua:16`) | the getter on the current window (creates or drops its triquetra) |
| history | *→* | * | 1.8 | `cleanup_triquetras` (`window/hooks.lua:24`) | A21, on **every** history transition |
| history | attached→detached | * | 2 | `detach_history` (`history/hooks.lua:35`) | saves the cycling origin and notifies "Checkpoint saved" |
| history | attached→attached | update | 2 | `displacement_mangement` (`window/hooks.lua:34`) | A1 |
| history | detached→attached | update | 2 | `reconcile_triquetra` (`window/hooks.lua:97`) | A13 |
| history | detached→detached | update | 2 | `nondisplacement_management` (`window/hooks.lua:110`) | never does anything (M9) |
| history | *→attached | update | 3 | `refresh_ui_attached` (`ui/hooks.lua:24`) | UI refresh if history changed |
| history | detached→detached | update | 3 | `refresh_ui_detached` (`ui/hooks.lua:33`) | UI refresh |
| ui_loop | *→self | * | 1 | `update_ui_state` (`ui/hooks.lua:14`) | `refresh_ui(tracked window)` and `show_ui()` |
| storage | {idle,bare}→saving | * | 1 | `save_history_pre_quit` (`storage/hooks.lua:10`) | `save_history(cwd)` |
| storage | bare→loading | * | 1 | `load_history_pre_start` (`:15`) | `load_history(cwd)` |
| storage | {bare,saving,loading}→{idle,saving} | * | 1 | `back_to_idle` (`:20`) | nothing |

**Triggers.** All are created at require time with no augroup:
- `WinEnter` → a navigation self-transition with mode `winenter` (`navigation/hooks.lua:44-48`).
- `BufEnter` → a history self-transition with `{buf}`, mode `update` (`history/hooks.lua:91-101`), except for Neovim's own pick in a window whose buffer is being deleted (A19).
- `BufDelete` → a history self-transition with `{buf}`, mode `delete`, unless `b:skip_bufdelete` is set (`:64-74`).
- `BufWritePost` → update, for unregistered buffers only (`:76-88`).
- `BufFilePre` → delete, marking a registered buffer with `vim.b.cavediver_renaming`, and `BufFilePost` → update, only for a buffer so marked (`:104-128`, A20).
- `WinClosed` → drop the window's history entry (`history/hooks.lua:131`), drop its triquetra (`window/hooks.lua:130`), and the popup cleanup, which runs `once` (`ui/hooks.lua:113`).
- `BufAdd`, `BufDelete`, `BufFilePost` and `BufWritePost` → clear the display-name cache (`ui/hooks.lua:43`).
- `VimResized` → a debounced UI refresh (`:49`).
- `BufModifiedSet` → a UI refresh (`:55`).
- `FileType cavediver-primary-buffer-history` → the popup's keymaps (`:61`).

**Timers.** These start in `setup()`:
- `cleanup_system` runs every `cleanup_interval` ms, with the first tick at once (`history/init.lua:36-76`).
- The UI refresh runs every `winbar_refresh_interval` ms through a 100 ms debounce (`ui/init.lua:58-72`, `ui/routines.lua:692-707`), which comes to about every 140 ms.

Two one-shot delays also run: 200 ms after require (`window/data.lua:172`), and 210 ms after a load (`history/routines.lua:150`).

### M12. UI

**Winbar.** Written for every triquetra window that passes `is_real_file` (`ui/routines.lua:614-639`, `:651-680`):
- not a float
- `buftype` is `""`, `terminal` or `acwrite`
- loaded
- no `://` in the name unless the buffer is `acwrite`
- filetype not on the exclusion list (`ui/data.lua:127-144`)

The string, as rendered **[run s14]**:

```
────── ⦉T⦊ [C] current-name <arrow-glyph>  ⟦S⟧ secondary-name ─────…
```

- The ternary shows as `⦉N⦊ ` when it's open, or `⦉ <icon> name ⦊ ` when it's closed.
- The current shows as `[N] name`, or `⦉N⦊ name` when it's the primary. A glyph follows when the buffer is modified.
- The secondary shows as arrow, `⟦N⟧ name` (`⦉N⦊` when it's the primary), or arrow, icon, name when it's closed.
- The padding fills the window's width.
- Highlights come from the `focused`, `unfocused` and `topwin_overlapped` themes (`ui/data.lua:72-106`); a top window that overlaps the focused window takes its focus colours (`ui/routines.lua:562-593`).
- The primary is matched by **display name**, not by hash (`ui/routines.lua:428-448`).
- While cycling, the current name uses the base highlight (`:424-426`).
- `zsh:terminal` is rewritten to `terminal:` (`:540`).
- The winbar is set to `""` when the triquetra is dropped (`window/data.lua:65`) or when the current buffer can't be resolved (`ui/routines.lua:472-486`).

**Bufferline.** Cavediver doesn't draw it. It hands cokeline its callbacks (`ui/init.lua:152-575`):
- `bufnr_is_displayed`: the bufferline state is visible and the buffer is in the "recent" set. Today that set is every buffer in the ordered history, because of `math.max(#ordered, 30)` (`ui/routines.lua:374`). That's intended: the bufferline shows every tracked buffer (Q5). **Decided:** `math.max` stays (2026-10-20), and the 30, which means nothing there, goes (2026-10-21).
- `compare_buffers`: by time in the history view, newest first.
- colour callbacks:
  - The text colour goes by the buffer's role, in the order primary, secondary, current, ternary, focused, harpooned, other (`ui/init.lua:241-261`).
  - The background turns the "detached" colour while history is detached (`:266-280`).
- components:
  - `[N]` for the current, `⟦N⟧` for the secondary, `⦉N⦊` for the primary or the ternary.
  - The harpoon mark and `⥤ {n}` label.
  - The index is dimmed when the primary is disabled (`:322-530`).
- `get_buffer_relationships(buf)` throws "A buffer cannot have more than one role" when, for example, the current buffer is also the primary **[run s14]**. **bug (new)**; the README's cokeline setup doesn't call it. **Decided (2026-10-20):** the one-role assertion is fixed or the function removed. Nothing calls it, neither cavediver nor the author's config (Q16).

**Caches:**
- `bufferline_state` is computed by `refresh_ui` for the tracked window (`ui/routines.lua:338-389`), and it requires harpoon.
- `window_display_cache[winid]` is set for every triquetra by `cleanup_triquetras` (`window/routines.lua:530`).
- `display_name_cache` is cleared on `BufAdd`, `BufDelete`, `BufFilePost` and `BufWritePost`.

**Smart basename** (`ui/routines.lua:193-243`):
- the basename, or the shortest path suffix that's unique among buffers with the same basename
- `[No Name]` for an empty name
- `[<buftype>]` for a special buffer
- It throws for a hash with no path.

### M13. Configuration

Defaults are in `configs.lua:20-134`. `setup(user)` deep-merges the user's table into the defaults and throws on a type mismatch (`init.lua:126-140`). `setup()` **with no argument throws** `bad argument #1 to 'pairs'` at `init.lua:127` **[run s13]**. **bug (desk)**

| Key | Default | Used by |
|---|---|---|
| `session_dir` | `stdpath("data") .. "/cavediver/sessions/"` | `storage/routines.lua:624` |
| `bufferline.history_view` | `"global"` | `history/routines.lua:174` |
| `primary_buffer_history_popup.{height,width}` | `0.2`, `0.7` (a ratio when ≤ 1, otherwise cells) | `ui/routines.lua:103-117` |
| `colors.*` | Flexoki-like hex values | highlights `ui/init.lua:33-54`, bufferline callbacks |
| `keymaps.*` | see the action table in section 3 | `init.lua:29-119` |
| `cleanup_interval` | `4000` (milliseconds, though the comment says seconds) | `history/init.lua:39` |
| `winbar_refresh_interval` | `140` ms | `ui/init.lua:67` |

## 3. User actions and editor events

### Coverage

Every default keymap (`configs.lua:106-131`, bound in `init.lua:29-119`) and every export in `init.lua`:

| Export (init.lua) | Default key | Action |
|---|---|---|
| `toggle_secondary` (`:381`) | `<M-f>` | A6 |
| `toggle_ternary` (`:386`) | `<M-S-f>` | A7 |
| `jump_to_primary` (`:391`) | `<M-;><M-f>` | A8 |
| `toggle_primary` (`:417`) | `<M-;><M-x>` | A9 |
| `set_primary` (`:427`) | `<M-;><M-c>` | A10 |
| `restore_ternary` (`:396`) | `<M-;><M-r>` | A11 |
| `restore_secondary` (`:401`) | `<M-;><M-t>` | A11 |
| `cycle_left` / `cycle_right` (`:407`, `:409`) | `<M-n>` / `<M-m>` | A12 |
| `cycle_select` (`:412`) | `<M-v>` | A13 |
| (no cancel) | — | A14 |
| `delete_buffer` (`:422`) | `<M-.>` (`close_buffer`) | A15 |
| `reopen_last_closed` (`:378`) | `<M-S-w>` | A16 |
| `toggle_window` (`:411`) | `<M-,>` | A17 |
| `open_primary_buffer_history` (`:414`) | `<M-;>F` | A18 |
| `save_session` / `load_session` (`:374-375`) | — | S1 |
| `setup` (`:123`) | — | M13, A25 |
| `get_storage_state`, `get_navigation_state`, `get_history_state`, `is_cycling` (`:432-448`) | — | A24 |
| `get_buffer_history`, `get_window_triquetra`, `get_all_triquetras`, `set_cache_from_window_triquetra` (`:450-456`) | — | A24 |
| `get_smart_basename` (`:455`) | — | A24: it's **nil**, because `ui/init.lua` never defines it **[run s16]**. bug (new) |
| `bufferline` (`:458`) and the domain tables `navigation`, `history`, `window`, `ui`, `storage`, `engine` (`:20-25`) | — | M12, A24 |
| user commands `:CavediverHistoryData`, `…NavigationData`, `…WindowData`, `…UIData`, `:CavediverTriquetra`, `:CavediverRegistry`, `:CavediverTriquetraVerbose`, `:CavediverAllTriquetras` (`init.lua:154-366`) | — | A23 |

The editor events: A1 (navigating to a tracked buffer), A2 (a window showing something untracked), A3 (entering a window), A4 (a new split), A5 (closing a window), A19 (any buffer delete), A20 (renames and writes), A21 (`cleanup_triquetras`), A22 (`cleanup_system`).

Most slot actions notify, and the messages are quoted where a test may want to check them. The silent ones are a successful `<M-f>` or `<M-S-f>` swap, the normal path of `jump_to_primary`, `toggle_primary` and `set_primary`. Most slot actions also end with a UI refresh (`loop_sm:to(SELF)`). `jump_to_primary` and the early returns of both swaps don't, and the UI catches up through the `BufEnter` that follows.

---

### A1. Navigating to a tracked buffer (`BufEnter`, history attached)

**Trigger.** `BufEnter` for buffer X in the current window W, whose triquetra is `{c=A s=S t=T}`. The pipeline is history `attached→attached`, mode update (M11):
1. track X (sets `history_modified`)
2. `ensure_curwin_crux`
3. `cleanup_triquetras` (A21)
4. `displacement_mangement`
5. UI refresh

**Today** (`window/hooks.lua:34-95`), when `history_modified` is true and X is registered:

| Case | After | Map writes |
|---|---|---|
| X = A | unchanged | none |
| X = S | `{c=X s=A t=T}` | none |
| X = T | `{c=X s=S t=A}` | none |
| anything else | `{c=X s=S t=A}` | `dtm[A-swap] := nil` and `dtm[A] := T`, only when T exists |

- **"Duplicates detected in current triquetra".** When S and T are both set and equal, the hook throws this before any slot changes (`:59-65`). The error is caught (M11), so **the slots aren't updated at all** and the window shows X while `c` is still A **[run s18]**.
- **The stale-note check in navigation.** When `dtm[X] = A`, so that X's remembered ternary is the buffer being left, `dtm[X]` is rewritten to avoid a cycle, with a WARN (`:71-85`):
  - If T = X: `dtm[X] := dtm[A]`, "…switching with the pre-jump stored ternary."
  - Otherwise: `dtm[X] := T`, "…switching with the pre-jump ternary." **[run s18]**: at b with `t=d` and `dtm{a→b}`, `:e a` gives `{c=a t=b}`, `dtm{a→d, b→d}`.
- The map writes happen only while navigation is `normal`. The slots move in any navigation state (`:58`, `:92-93`). In practice cycling detaches history, so this hook doesn't run while cycling.
- When the update returns false (an untracked buffer, or an "evolved" one, M3), the slots aren't touched. `ensure_curwin_crux` and `cleanup_triquetras` still run (A2, A21).
- Cleanup runs **before** this hook (class 1.8 against 2). When the buffer being left is a missing file, it stays registered and current until this hook moves it to the ternary as usual (M3, A21) **[inferred]**.
- Going to the secondary (`window/hooks.lua:52-54`) has no "avoided conflict" guard, the one `reconcile_triquetra` runs for a cycling pick (A13). So when `dtm[T] = S`, the swap leaves the ternary's note pointing at the new current, and a later `<M-;><M-r>` can throw (A11). **bug (new)** (Q6)

Examples **[run s01, s02]**:
- `{c=a}` `:e b` → `{c=b t=a}`.
- `:e c` → `{c=c t=b}`, `dtm{b→a}`.
- From `{c=d s=b t=c}`, `:e b` (the secondary) → `{c=b s=d t=c}`, with no dsm write. The author's check of P14 gives the same.

**Label:** intended (README:347-349, README:353, SPEC:221-226, P14). The dsm write is skipped when you reach the secondary by plain navigation, while README:355 says "every time you jump to secondary". See D8.

**Decided:** the slotting happens at the end of the tick against the window's own buffer, never the focused one, and a later `buftype` change undoes the arrival (DESK:1788-1789).

**Decided (2026-10-20):** going to the secondary by plain navigation is one of Q6's routes onto the secondary. The guard runs before the swap and rewrites `dtm[T]` to the buffer being left (A6).

**Decided (2026-10-20):** going to the secondary by plain navigation records the same notes as `<M-f>`, so `<M-;><M-t>` works after either route (D8). Paired with T30 (T191).

**Decided (2026-10-20 evening), "Keep the older one": plain navigation onto the secondary** runs in `<M-f>`'s order (A6):
1. the notes: `dsm[A-swap] := S` and, with a ternary, `dtm[A-swap] := T`. S's plain secondary note becomes S's swap note when that names a buffer other than A; otherwise a plain note naming A is cleared (M7).
2. Q6's guard.
3. the swap, `{c=S s=A t=T}`.
4. the stale-note check below: S's plain ternary note, when it names T, which stays put, becomes **the ternary's own note** `dtm[T]`.

Example, the round trip D8 asked to solve **[sim `rt_cand_round_e`, variant `rt_c3kga`; the same under `kt_rewrite_sec`]**: `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` give `⦉c⦊ [d] ⟦b⟧`; `:e b` gives `⦉c⦊ [b] ⟦d⟧` with `dsm{b>a d-swap>b}`; `:e d` gives `⦉c⦊ [d] ⟦b⟧` with `dsm{b-swap>d b>a d-swap>b}`; `<M-;><M-t>` on d says "No secondary relationship found" instead of throwing (T179).

**Decided (2026-10-20 evening), "Keep the older one": the stale-note check in navigation runs on every arrival.** Today it runs only for a buffer reached by plain navigation that isn't the secondary (`window/hooks.lua:71-85`). Under the decision the same check runs whenever a buffer N becomes current, by any key, after the arrival's own writes. N's plain ternary note is checked against the ternary the window has after the arrival, and when it names it, it's rewritten:

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
- Code the change touches, from the variants: `reconcile_triquetra` (`window/routines.lua:93-135`), `jump_to_primary` (`:730-733`), and plain navigation onto the secondary (`window/hooks.lua:52-54`). Navigation's own check stays as it is.

### A2. A window switches to something untracked

Examples: `:terminal` in the window, help or quickfix opened into it, a `nofile` scratch.

**Today.** The next time `get_window_triquetra` runs for that window (A1's `ensure_curwin_crux`, `WinEnter`, a UI tick), the triquetra is **dropped** when all of these hold (`window/data.lua:93-103`):
- the shown buffer's hash isn't the current slot
- its `buftype` is non-empty and not `acwrite`
- its filetype isn't `image_nvim`

Oil (`acwrite`) keeps it. Coming back gives a fresh `{c=X}`: the secondary, ternary, primary queue and maps are all gone.
- **[run s15]** `{c=c s=b}`, `:terminal` → no triquetra. `:e a` → `{c=a}`.

Untracked buffers are never registered, so they never reach a slot. **Label:** intended per README:332, "When a window switches to a non-regular buffer then it will clean the triquetra".

**Decided: the visiting rule** (DESK:51, DESK:1785-1794):
- A window that has a triquetra keeps it while it shows anything untracked. Its current slot stays the file it was last on, and may be a closed buffer.
- Windows born untracked (`:help`, `:copen`, `:split | terminal`) and floats never get a triquetra.
- The winbar shows the visit, e.g. `main.lua ← [help]`.
- `<M-f>` and `<M-S-f>` take you back to the current slot first.

### A3. Entering a window (`WinEnter`)

**Today.** A navigation self-transition with mode `winenter` (M11). It:
1. records `jump[cur] := prev`, where prev is the `winnr('#')` window, or `last_valid_window` when there's none. It skips a prev showing filetype `minimap`, or one that's invalid.
2. sets `current_window := cur`.
3. runs `construct_crux(find_most_recent_tracked_window())`, which may create the window's triquetra (M6).
4. refreshes the UI.

A `BufEnter` usually follows when the window shows a different buffer. A1 then runs for the entered window, and since its shown buffer is its current slot, the slots don't change.

`record_window_jump` reads the "from" window's buffer before checking that the window is valid (`navigation/routines.lua:32`, `:39`). **bug (desk)**

### A4. A new split (`:split`, `:vsplit`, `:new` showing a file)

**Today.**
- A split showing the same buffer fires no `BufEnter`.
- On `WinEnter` the new window gets a fresh `{c=<that buffer>}` (M6). It isn't a copy of the old window's triquetra.
- It has **no history entry** until a visit happens in it **[run s07, s16]**.
- `save_session` then fails at `storage/routines.lua:340` (`next(nil)`) **[run s16]**. **bug (desk)**, I3

**Label:** a minimal start is intended (SPEC:65-76). The missing history entry is a bug.

### A5. Closing a window (`WinClosed`)

**Today:**
- The window's history entry is dropped (`history/hooks.lua:131-139`).
- Its triquetra is dropped (`window/data.lua:51-67`): the UI cache is cleared, `last_valid_window` is moved to the previous window in the jump chain whose buffer is registered, the history view is rebuilt for that window, and the winbar is cleared.
- Entries in the window-jump history that point at the closed window stay (M10). **[run s07]** shows the closed window's data gone.
- The popup's `WinClosed` handler runs `once` with no pattern, so the first window closed in the session uses it up (`ui/hooks.lua:113-131`). **bug (desk)**

### A6. `toggle_secondary`, `<M-f>`

**Today** (`window/routines.lua:541-617`), in window W:

1. **No triquetra:** WARN "Window with unregistered buffer." Nothing else.
2. **W shows something other than its current slot**, while the current slot's buffer is open: switch W back to the current slot's buffer, INFO "Jumped back to windows current buffer.", stop. This is what happens while cycling **[run s04]**.
3. **The secondary is empty.** No buffer switch:
   - With a ternary T: `s := T`, `dsm[T] := dtm[T]`, `t := nil`. INFO "Secondary buffer set to ternary slot. Ternary slot graduated."
   - Otherwise, with at least 2 entries in the ordered history: `s := hash(ordered[2])`. INFO "Secondary buffer populated from history." That entry can be the current buffer when history is stale after a cycle, which puts one buffer in two slots (DESK:2463). **bug (desk)**
   - Otherwise: WARN "Cannot populate secondary slot - insufficent history."
4. **The secondary S is set:**
   - Write `dsm[A] := S`, and `dtm[A-swap] := T` when there's a ternary T.
   - If S's buffer is closed, reopen it (M5).
     - On failure: WARN "Removed secondary file not found in filesystem: <name>", `s := nil`, stop.
     - On success: remove it from the closed stack and INFO "File reopened for secondary slot: …".
   - If S is a No Name hash, rename it everywhere (`rename_hash_in_triquetras`).
   - Then `reconcile_triquetra` swaps A and S: `{c=S s=A t=T}`.
   - Then W switches to S. The following `BufEnter` finds `c` already S and does nothing.

Examples **[run s01]**:

| Step | Before | After |
|---|---|---|
| graduation | `{c=c t=b}`, `dtm{b→a}` | `{c=c s=b}`, `dsm{b→a}`, still showing c |
| swap | `{c=c s=b}` | `{c=b s=c}`, `dsm{c→b}`, showing b |
| swap back | `{c=b s=c}` | `{c=c s=b}`, `dsm{b→c, c→b}` |

**Labels:**
- The graduation and the swap are intended (SPEC:80-112).
- The `dsm` write is intended (README:355).
- The `dtm[A-swap]` write is intended (Q2). SPEC:240, which says a swap creates no mapping, is out of date (D7).
- Copying `dtm[T]` into `dsm[T]` on graduation is intended (Q3). The author's reason: the graduated buffer's predecessor can then come back either as the ternary (`<M-;><M-r>`) or as the secondary (`<M-;><M-t>`).
- In the swap path, `reconcile_triquetra`'s "avoided conflict" guard (`window/routines.lua:122-131`) also runs. Its write is a no-op there, because `c` has already become S, but its WARN still appears whenever `dtm[T] = S` **[run s18]**. **bug (new)** (Q6). The conflict is real and the warning isn't spurious: the guard runs too late to do its job. The author's repro, observed: `:e a`, `:e b`, `:e c`, `:e b`, `<M-f>`, `:e a`, `<M-f>`, `<M-f>` (the warning, no change), `<M-S-f>`, `<M-;><M-r>`, which throws (T150).

**Decided:** while visiting, `<M-f>` takes you back to the current slot first (DESK:1792). Today's step 2 already does that.

**Decided (2026-10-20):** the guard runs **before** the swap on every route onto the secondary, so `dtm[T]` is rewritten to the buffer being left (Q6). The routes:
- `<M-f>` (this action)
- a cycling pick of the secondary (A13)
- `<M-;><M-f>` falling back to `<M-f>` (A8)
- plain navigation onto the secondary (`window/hooks.lua:50-53`, A1), which has no guard today

Setting `proc = true` in the secondary branch alone isn't the fix: it keeps the crash. The guard came in with commit ae209e42 (2025-06-12), inside `if not proc`; `proc` dates from d89061a3 (2025-06-11). Both predate this repository. The fall-through onto the secondary route wasn't deliberate. With the fix, the ten-key repro restores without throwing. Random walks with the fix still hit the ternary restore's throw 13 times in 1,500. Each of those lands on a buffer by an arrival that skips the stale-note check in navigation; "Keep the older one" closes them (A1, A11).

**Decided (2026-10-20 evening), "Keep the older one"** (M7):
- **Step 3, graduation,** also clears the graduated buffer's swap note `dsm[T-swap]`, so Q3's copy is what a later `<M-;><M-t>` finds (T184).
- **Step 4, the notes:** `dsm[A] := S` becomes the swap note `dsm[A-swap] := S`. S's plain note `dsm[S]` becomes S's own swap note when that names a buffer other than A; otherwise a plain note naming A is cleared. `dtm[A-swap] := T` stays.
- **The order on every route onto the secondary** (this key, its `<M-;><M-f>` fallback, plain navigation onto the secondary): the notes, then Q6's guard, then the swap, then the stale-note check, under which S's plain ternary note naming T, which stays put, becomes the ternary's own note `dtm[T]` (A1).
- The swap examples above then read `dsm{b→a, c-swap→b}` and `dsm{b→a, b-swap→c, c-swap→b}`, and `<M-;><M-t>` on c says "No secondary relationship found" instead of throwing as it does today **[sim `rt_sec_round`, variants `rt_c3kga` and `kt_rewrite_sec`]** (T177). One more `<M-f>` back to b, and `<M-;><M-t>` there brings back a, b's secondary from before the round trip (T178).

### A7. `toggle_ternary`, `<M-S-f>`

**Today** (`window/routines.lua:625-678`), in window W with `{c=A s=S t=T}`:

1. **No triquetra:** WARN as in A6. **W not showing its current slot:** jump back, as in A6.
2. **No ternary:** WARN "No ternary buffer to swap with.", stop.
3. **T's buffer is closed:** reopen it. On failure: WARN "Removed ternary file not found in filesystem: …", `t := nil`, stop.
4. Run `rename_hash_in_triquetras(T, hash of the opened buffer)`. That's a no-op unless T was a No Name buffer.
5. `reconcile_triquetra`: `dtm[A-swap] := T`, then swap: `{c=T s=S t=A}`. Switch W to T.

Example **[run s01]**: `{c=d s=b t=c}` → `{c=c s=b t=d}` with `dtm{d-swap→c}`. Again → `{c=d … t=c}`, adding `c-swap→d`.

- If cleanup clears the ternary between steps 3 and 4, step 4 calls the rename with `nil` as the old hash. The first press throws "attempt to concatenate local 'old_hash'" (`window/data.lua:142`); a second press throws "Duplicates detected in triquetra slots" (`window/routines.lua:115`). The desk reproduces it with `:e 1.txt`, `:e 2.txt`, `<M-n>`, `:bdelete`, `<M-S-f>`, `<M-S-f>` (DESK:2469). **bug (desk)**

**Label:** the swap is intended (SPEC:114-135). The `-swap` write is intended (Q2).

**Decided (2026-10-20 evening), "Keep the older one":** after the swap, the stale-note check runs (A1). T's plain ternary note, when it names A, the new ternary, becomes A's own note `dtm[A]`, as navigation's first case does; when A has none, it's dropped (T186). The secondary map's check runs too (M7).

### A8. `jump_to_primary`, `<M-;><M-f>`

**Today** (`window/routines.lua:684-740`), in window W with `{c=A s=S t=T p=[P,…]}`:

1. **No triquetra:** WARN "Window with unregistered buffer."
2. **Cycling.** Switch W to the cycle's starting buffer, set `c := origin` (already true, M9), INFO "Returned to cycling origin buffer: <name>". **Navigation stays `cycling`.** **[run s04]**
3. **Fall back to A6** when the queue is empty, **or `primary_enabled` is false**, or S = P **[run s02]**.
4. **P's buffer is closed:** reopen it.
   - A reopened No Name P replaces `p[1]` with its new hash, in W only.
   - On failure it **throws** `Primary buffer not found in filesystem: <path>`. That's a raw `error()`, so it reaches the user as an E5108.
5. **A ≠ P:** `dtm[A-swap] := T` (nil when there's no ternary), `t := A`, `c := P`. Otherwise INFO "Already in primary buffer, no displacement performed.", and nothing changes.
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

**Decided (2026-10-20 evening), "Keep the older one":** after the shift in step 5, the stale-note check runs (A1). P's plain ternary note, when it names A, the new ternary, becomes T, the pre-jump ternary, as navigation's second case does; when P was the ternary, it becomes `dtm[A]` instead (T187). The secondary map's check runs too (M7). The fallback to `<M-f>` follows A6.

### A9. `toggle_primary`, `<M-;><M-x>`

**Today** (`window/routines.lua:746-759`):
- Empty queue: `p := [A]`.
- Then `primary_enabled := not primary_enabled`.
- Then a UI refresh and `redraw!`.

So:
- the first press on an empty queue makes the current buffer the primary and enables it
- later presses only toggle enabled, whatever buffer you're on
- the queue never changes after that

**[run s02]**: `p=[]off` → `p=[b]on` → `p=[b]off`.

**Label:** intended (Q8). `<M-;><M-x>` is the primary's on/off switch, and seeds the queue only when it's empty. `<M-;><M-c>` (A10) is the key that makes the current buffer the primary.

**Decided (2026-10-20):** only the keymap description changes. "Toggle current buffer as primary" (`init.lua:105`) doesn't describe an on/off switch. The README has the two keys swapped, which is a bug in the README (D1).

**Decided (2026-10-20):** on an empty queue, the key queues the current buffer and switches the primary **on**, whatever the switch said (Q14). Today it flips the switch after queueing, so a queue that emptied while on ends up `p=[A]off`, and a second press is needed **[run s19]**. The state isn't changed: an empty queue may stay switched on (I19).

### A10. `set_primary`, `<M-;><M-c>`

**Today** (`window/routines.lua:765-787`):

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

**Today** (`window/routines.lua:793-864`). The type is ternary or secondary, the slot `cur` is that type's slot, and the map is dtm or dsm. In window W with current A:

1. Look up `remembered := map[A-swap]`. If that's nil or equals the **ternary** slot (for both types), use `map[A]` instead.
2. Then:

| Condition | Effect |
|---|---|
| nil | WARN "No <type> relationship found for restoration. …" |
| no path for it | **throws** "This impossible error should never happen. …" (DESK:2449) **bug (desk)**; D9 decides the fix (below) |
| not a No Name buffer, and its file is unreadable | WARN "Remembered <type> is not found in filesystem anymore.", `map[A] := nil`. `map[A-swap]` isn't cleared, so a stale `-swap` entry keeps being found. **bug (new)**; D9 decides the fix (below) |
| equals `cur` | **throws** "This is impossible. Remembered <type> is the same as current <type>. …" |
| ternary type, equals the secondary | `s := t`, `t := remembered` |
| ternary type, otherwise | `t := remembered` |
| secondary type, equals the ternary | `t := s`, `s := remembered` |
| secondary type, otherwise | `s := remembered` |

3. In the last four rows, `map[A] := cur` afterwards. A nil `cur` deletes the entry. INFO "Restored <type> slot to: <hash> (<name>)".
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
- Throwing when the remembered value equals the slot is intended: the assertion stays (Q13). SPEC:176's message, "No different ternary relationship to restore", is out of date (D9). Every route that still reaches the throw is a bug, to be hunted with tests (T154). Q6's fix closes one route (A6). The 13 ternary throws left in 1,500 walks after it were traced: each lands on a buffer by an arrival that skips the stale-note check in navigation. The secondary restore throws far more often: 161 times in 1,500 walks today, 204 with D8's notes, mostly after a round trip onto the secondary and back **[run, sim; the round-trip research's walks]**.

**Decided (2026-10-20 evening), "Keep the older one".** One rule lies behind every throw found: a buffer becomes current while its note names the buffer already in the slot that note restores into (I23). The fix is the stale-note check on every arrival, on both maps (A1, M7), plus these changes to the restore itself:
- **The swap-note fallback** (step 1) compares with the slot being restored into, not with the ternary for both: `dtm[A-swap]` against the ternary, as today, and `dsm[A-swap]` against the secondary (`window/routines.lua:799`). So after a round trip onto the secondary and back, A's swap note equals the secondary and the restore falls back to A's plain note, A's secondary from before (T180).
- **The ternary restore's exchange** (the row "ternary type, equals the secondary") is followed by the secondary map's check: the current buffer's secondary note, when it names the new secondary, is rewritten to its swap note or dropped **[sim `kt_tosec`, variant `kt_rewrite`]** (I23, T190).
- **The secondary restore's exchange** (the row "secondary type, equals the ternary") got no check in the first tested fix: when the current buffer's ternary note named the old secondary, which the exchange had just moved into the ternary, the next `<M-;><M-r>` threw **[sim, variant `kt_rewrite_sec`]**. **Decided (2026-10-21):** the check runs there too, and the stale note becomes the ternary's own note, dropped when there's nothing older or it would name the current buffer **[sim, variants `ex_a`, `all_fixed`]** (T189, T206).
- Over two sets of 1,500 walks: 0 ternary and 0 secondary throws, no duplicate slot, no other error **[sim, variant `kt_rewrite_sec`]**. Zero in the walks is evidence, not proof; T154 and T190 keep hunting.

**Decided (2026-10-20 evening): a remembered file that's missing** (D9), for both restores and both maps, swap keys included:
- missing from disk with no buffer: skipped and kept. A skipped swap note falls back to the plain note; when that's missing and closed too, the restore says so and changes nothing (T67, T174, T193).
- missing from disk with its buffer open: the restore goes through and flip-flops with it, saying the file isn't on disk (T173).
- a hash with no path: the note is cleared when used, with no throw (T68).

### A12. Cycling: `cycle_left` `<M-n>`, `cycle_right` `<M-m>`

**Today** (`navigation/init.lua:52-68`, `navigation/hooks.lua:12-21`, `navigation/routines.lua:11-29`):

**From `normal`**, navigation goes to `cycling` with `{direction, window = {current_crux = W}}`:
1. History goes `attached→detached`.
2. `cycling_origins[W]` becomes the live triquetra, with `c` set to the shown buffer, and a notify "Checkpoint saved: <current> -> <secondary or Unfilled>" (no level).
3. One step: `cokeline.mappings.by_step("focus", -1)` for left, `+1` for right.

**From `cycling`**, it's one more step.

What a step does and doesn't do:
- It's skipped when there are 1 or fewer buffers in the ordered history. The mode change still happens.
- When cokeline is missing, it `print`s "cokeline is not installed…" and the mode change still happens.
- While cycling, `BufEnter` neither tracks history nor touches slots. **The current slot stays the starting buffer** **[run s03]**.
- The history order stays frozen.
- The bufferline background uses the detached colours, and the winbar's current name loses its highlight.

Which way left and right move depends on cokeline's buffer order: `compare_buffers` puts the newest on the left, so `-1` moves toward newer buffers. The runs here used a stub that steps through cavediver's ordered list, not real cokeline, but the author confirms the direction (Q19): `<M-n>` steps left, toward newer buffers, and `<M-m>` steps right, toward older ones.

**Label:** intended (README:382-384, Q1, Q19). SPEC:194 and SPEC:393, which have the current slot follow the cycle, are out of date (D10).

**Decided (2026-10-20):** only when cokeline is missing, a step goes through cavediver's own ordered history instead (the order the bufferline would show), so `<M-n>`/`<M-m>` still cycle. With cokeline installed nothing changes: cycling stays on cokeline and cokeline stays required. DESK.md:2126 ("Cycling stays on it") and the Dropped line at DESK.md:3146 get narrowed to say so at the next desk sync. Today a missing cokeline leaves navigation in `cycling` with history detached until `<M-v>` **[run s21]** (T171).

**Decided (2026-10-20 evening):** jumping to another window ends the cycle by **cancelling** it: the cycling window returns to its start and nothing is recorded (P18; Q7, picking stays `<M-v>`'s job). Any `WinEnter` into another window counts, floats included (the primary pop-up, a picker's prompt, `:help`). It acts on the cycling window, after the editor settles. The author: "I guess we have to quit cycling mode when we jump windows." Today a cycle leaks across windows: work in the other window isn't recorded and doesn't move its slots, and `<M-v>` pressed there "picks" in that window, dropping its current buffer **[run `t/b7_jump.lua`]** (T175).

**Decided (2026-10-21):** landing in the window you jumped to counts as an ordinary visit and records its buffer, even when Neovim fires no `BufEnter` (the window already shows that buffer). The cancel records nothing for the cycle's steps only. The author: "Yes, record the landing". Without it, `:e a`, `:vsplit`, `:e c`, `<M-m>`, `<C-w>p`, `<M-f>` trips the fill assertion under both views (35-52 per 1,500 multi-window walks; 0-3 with the landing recorded, all from the window-view tie bug in D11) **[sim, 2026-10-21]** (T198).

### A13. `cycle_select`, `<M-v>`

**Today** (`navigation/init.lua:70-76`, `navigation/hooks.lua:23-28`, `window/routines.lua:93-135`).

**From `cycling`**, navigation goes to `normal`, and history `detached→attached` with `{buf = X}`, where X is the shown buffer:
1. X is tracked; the order is now live again.
2. `cleanup_triquetras` runs.
3. `reconcile_triquetra(current window, X)` runs, with `{c=A s=S t=T}`, where A is the cycle's start:

| Case | After | Map writes |
|---|---|---|
| X = A | unchanged | none |
| X = T | `{c=T s=S t=A}` | `dtm[A-swap] := T` |
| X = S | `{c=S s=A t=T}` | none |
| X outside the triquetra | `{c=X s=S t=T}`: **A leaves the triquetra and the ternary stays** | if `dtm[T] = X`, then `dtm[T] := A`, with WARN "Avoided conflict of ternary's remembered relationship becoming current. …" |
| X = T and X = S together | "Duplicates detected in triquetra slots" |

4. The UI refreshes.

Examples **[run s03, s04]**:
- `{c=e s=c t=d}`, cycle to b, `<M-v>` → `{c=b s=c t=d}`.
- Cycle to c (the secondary), `<M-v>` → `{c=c s=b t=d}`.
- Cycle to d (the ternary), `<M-v>` → `{c=d s=c t=e}`, `dtm{e-swap→d}`.

**From `normal`**, `<M-v>` is `normal→normal` with mode `cycle`. No hook matches, so nothing happens **[run s04]**.

**Labels:**
- The ternary not being updated by a pick is intended (README:347, Q9).
- That A, the cycle's start, isn't remembered anywhere when X is outside the triquetra is decided (2026-10-20) to change (Q9).
- In the X = S case, the "avoided conflict" guard runs after the swap, as on `<M-f>`: when `dtm[T] = S` it warns and rewrites nothing (A6) **[code]**. **bug (new)** (Q6)
- SPEC:385-407, which has slot changes during cycling persist with no displacement, is out of date (D10).

**Decided (2026-10-20):**
- A pick of a buffer outside the slots also writes a note on the picked buffer, `dtm[X] := A`, so `<M-;><M-r>` on X brings the start back. The ternary itself stays unchanged, so README:347 holds (Q9, T155).
- The same pick clears the picked buffer's older swap note `dtm[X-swap]`, which would otherwise win the restore and lose the start (the author, 2026-10-20 evening: "Yes, delete it") (Q9, T172).
- A pick of the secondary is one of Q6's routes onto the secondary: the guard runs before the swap and rewrites `dtm[T]` to A (A6).

**Decided (2026-10-20 evening), "Keep the older one":** after a pick, the stale-note check runs as on every arrival (A1). A pick of the ternary rewrites the picked buffer's stale note to `dtm[A]`; a pick of the secondary or of an outside buffer, to the ternary's own note `dtm[T]`. Under Q9's note, an outside buffer's plain note names the start, which is never the ternary, so the check finds nothing stale there. The secondary map's check runs too (M7). A pick writes no secondary notes, as today: D8 named plain navigation and the bufferline, not picks.

### A14. Cancelling a cycle

**Today:** no cancel exists. The closest path:
1. `<M-;><M-f>` while cycling switches back to the starting buffer and stays in `cycling` (A8 step 2).
2. Then `<M-v>` selects it. That's case X = A in A13, which leaves the slots unchanged.

`<M-f>` and `<M-S-f>` while cycling, when the window isn't showing its current slot, also switch back to the start and stay in `cycling` (A6 step 2) **[run s04]**.

When the window already shows the current slot, `<M-S-f>` **does a real ternary swap while still cycling**, `-swap` write included: `{c=c s=b t=d}` → `{c=d s=b t=c}` **[run s04]**.

**Label:** intended (Q7). There's no cancel key: `<M-f>` returns to the start, then `<M-v>` picks it. For the slot keys while cycling, the author pointed to the code ("bro, just take a look, I already dealt with that.", 2026-10-20 15:37), so today's behaviour is the intended one:
- `<M-f>` and `<M-S-f>`, when the window isn't showing its current slot, jump back to it; when it is, they do their normal job.
- `<M-;><M-f>` while cycling always returns to the cycle's start (A8 step 2), whether or not the window is already on it.

SPEC:197-205, which has the slot keys act on the cycled-to buffer, is out of date (D10). SPEC:206-213 describes `<M-;><M-f>` as "return to checkpoint", not as a cancel, which fits.

`<M-;><M-f>` while cycling with the window already on the start announces the origin again and changes nothing (A8 step 2). That's the code's behaviour, which Q7's answer keeps. Confirmed by the author (2026-10-20, late evening), after being recorded from a reading of their words.

**Decided (2026-10-20 evening):** jumping to another window cancels the cycle: the cycling window goes back to its start, and nothing is recorded (A12, T175). There's still no cancel key.

### A15. Closing a buffer, `<M-.>` (`close_buffer`)

**Today** (`history/routines.lua:537-605`), on the buffer B shown in window W:

1. **Refusals**, each with a WARN and no change:
   - B has a name and is modified: "Buffer has unsaved changes". A modified No Name buffer goes through.
   - B is shown in another window: "Can't delete buffer because it's shown in another window."
   - The history view has 1 entry or fewer: "Can't delete buffer because it's the only one left".
2. **Picking where W goes.** Find B's index i in `ordered.crux`, with n entries:
   - If B isn't in it (help, a terminal, any untracked buffer), it **throws** "This is impossible: Current buffer not found in ordered history." at `history/routines.lua:592` (DESK:2465). The author saw it in `:help` and in a `:terminal`. **bug (desk)**
   - `i = 1` with `n ≥ 2` → `ordered[2]`.
   - `i > 1` → `ordered[(i % n) + 1]`, which is the next older entry, wrapping to the newest after the oldest.
3. **Closing.** Switch W to that buffer (A1 runs), then `bw! B`. Its `BufDelete` runs A19, which pushes B on the closed stack and caches its text if it's a No Name buffer.

**[run s05]**:
- At f with order `f,e,d,b,a`: lands on e, `{c=e t=f}`, closed `[c,f]`.
- At e with order `e,f,…`: lands on f.
- In both, the closed buffer stays in the ternary, where `<M-S-f>` reopens it.

**Labels:**
- The landing rule is intended: the code is right and the comment at `:588`, "go to most recent (first in list)", is wrong (DESK:2167, DESK:2478). **bug (desk, comment)**
- The `bw!` is intended today.

**Decided:**
- `:bdelete` for files, so Neovim keeps the buffer's marks. No Name scratches may still be wiped (DESK:2168).
- The close key keeps its own landing rule (DESK:2167).
- The keymap descriptions for `close_buffer` and `open_primary_buffer_history` both read "Toggle current buffer as primary" (`init.lua:111`, `:117`) (D3).

**Decided (2026-10-20): `<M-.>` on an untracked buffer** (Q17):
- **A window with a triquetra that's visiting something untracked** closes the visited buffer and lands on its current slot. That case needs the desk's visiting rule (A2), since today a terminal or help shown in the window drops its triquetra.
- **A window born untracked** (no triquetra, such as a `:help`, `:copen` or terminal split) closes the buffer. Neovim closes that window when other windows exist; when it's the only window, Neovim picks what it shows.
- **A terminal whose job is still running** is refused with a message, as an unsaved file is (step 1).

### A16. `reopen_last_closed`, `<M-S-w>`

**Today** (`history/routines.lua:523-534`):
- With an empty closed stack: WARN "No closed buffers to reopen."
- Otherwise:
  1. Pop the newest hash and `reopen_filehash` it (M5).
  2. On success, switch the current window to it (A1 runs, so the buffer becomes current and the old current moves to the ternary).
  3. When the file is missing, the hash is gone from the stack and **nothing is reported** (DESK:2454). **bug (desk)**
- A reopened No Name buffer comes back under a new hash, and nothing renames slots that pointed at the old one (DESK:2299). **bug (desk)**

**[run s05]**: closed `[c,f]`, at e → shows f, `{c=f t=e}`, closed `[c]`.

**Decided:** a missing file says so when it's used, and its pointer is kept (DESK:2022). A reopened No Name buffer gets a fresh id, and everything that pointed at its old hash is renamed (DESK:2299).

### A17. `toggle_window`, `<M-,>`

**Today** (`navigation/routines.lua:44-59`):
- prev = `jump[current]`.
- If it's valid and not a minimap: record `jump[prev] := current`, then go to prev.
- Otherwise: WARN "No valid previous window to toggle to."

**[run s07]**: it toggles between two splits.

**Label:** intended (README:311). **Decided:** the minimap skip becomes a configurable list, defaulting to `minimap` and `neominimap` (DESK:2156).

### A18. Primary queue window, `<M-;>F` (`open_primary_buffer_history`)

**Today** (`ui/routines.lua:21-137`, `ui/hooks.lua:61-110`, `window/routines.lua:21-77`).

**Opening:**
- With no triquetra: INFO "No triquetra found for current window." With an empty queue: INFO "No primary buffer history available." In both cases there's nothing to edit, so the first entry can't be typed in from here.
- Otherwise:
  - A centred float opens. It holds a **listed** `acwrite` buffer named `cavediver://primary-buffer-queue-history`, with filetype `cavediver-primary-buffer-history`.
  - It lists one line per queue entry. Each line is the entry's display name, or `NONAME_<n>` for a No Name entry.
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
  - Not loaded and unregistered: a `NONAME_` name is rejected. Otherwise the path is registered **and pushed onto the closed stack** (`:54`).
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

### A19. Any buffer delete (`BufDelete`, or `BufFilePre` on a rename)

**Today**, the history self-transition with mode delete:

1. **`handle_deletion`**, when the buffer is registered:
   - `track_closing_filehash`: push it on the closed stack. A No Name buffer with text has its lines, filetype and cursor cached. An empty No Name buffer has its path forgotten and isn't pushed.
   - untrack it, then unregister the buffer. The path stays.
2. **When history is attached:** the ordered lists are rebuilt.
3. **`cleanup_triquetras(buf)`** runs (A21). A window whose current slot was the buffer being deleted, and that still shows it, is left to land once the delete is over (below).

**The landing** (`land_after_delete`, `window/routines.lua:146-221`). It acts once the delete is over (`vim.schedule`), in that window, whichever window has the focus:
- It lands on the first open one of the ternary, the secondary, `primary[1]`, and the open buffers in the bufferline's order (`history.get_ordered_buffers()`, which follows `history_view`), never the buffer being deleted (`:170-199`). That buffer becomes the current slot, and the ternary or secondary it came from is emptied, as healing does; the primary queue stays (T111, T271).
- With nothing to land on, a window showing Neovim's empty buffer keeps it, and it's recorded as the visit (T237). Anything else Neovim showed is replaced by a new empty buffer, made with `nvim_create_buf(true, false)`, since `:enew` would reuse an empty scratch (`:201-219`).
- It does nothing when the window closed or lost its triquetra, when the buffer is still listed and shown (a rename, A20), or when the window moved on since Neovim's pick (`:153-168`).
- Neovim's own pick, the first `BufEnter` in that window once the deleted buffer is unlisted, isn't recorded as a visit: the `BufEnter` hook asks `is_landing_pick` first (`:229-240`, `history/hooks.lua:96-98`). `window.data.landing` holds, per window, the buffer being deleted and that pick (`window/data.lua:22-25`).

Closing a buffer that a slot holds:

| Slot | Effect | Evidence |
|---|---|---|
| ternary | it **stays**, as a closed hash | **[run s06]** |
| primary entry or secondary | it **stays**, as a closed hash, like the ternary: each check reads its own slot or entry (`window/routines.lua:450`, `:506`) | T103, T104. On the wrong-slot check (D13), **[run s05]**: `:bdelete c` with `{c=e s=c t=d}` → `s=-` at once. **[run s06]**: secondary and primary kept while the ternary was closed, pruned as soon as the ternary was reopened. |

**Label:** intended: a closed slot reopens when used (README:15, I4). A closed slot whose file is gone from disk is pruned (A21, P9).

**Decided:** a deleted buffer's window is landed after the delete, in that window, in the order ternary → secondary → primary → most recent, with no extra wipe. When nothing in that order exists, the window keeps Neovim's empty buffer, and `:enew` runs only when Neovim showed something else (DESK:1931). Plain Neovim usually lands the same way (DESK:3252). `<M-.>` keeps its own rule (A15). Built in step 1.

### A20. Renames and writes

**`:saveas`, `:file`, LSP or oil renames.** `BufFilePre` (delete, A19) puts the old hash on the closed stack and unregisters the buffer, marking it with `vim.b.cavediver_renaming` when it was registered (`history/hooks.lua:111`). `BufFilePost` (update) registers the new name only for a buffer so marked (`:122-126`), and cleanup re-points the current slot to it (A21).
- The window keeps showing the renamed buffer, edits included (T106, on the route of DESK:2442-2444): A19's landing finds it still listed and shown and leaves it (`window/routines.lua:157-164`). A new name that isn't on disk yet (`:file new`) is registered like any unregistered buffer (`history/routines.lua:276`, M3), and A21 doesn't check the current slot's file on disk, so it stays tracked, and its window stays open (T284).
- `:saveas` fires the rename events on the extra buffer it makes for the old name too (listed, unloaded). That buffer isn't marked, so it isn't registered until it's entered, like a `:badd` buffer, and the old name stays on the closed stack **[code]**. While the rename is in progress, cleanup finds the window still showing the old name's file, unregistered for the moment, and leaves it alone (A21) **[inferred]**.
- Other slots and maps that hold the old hash keep it, whether or not the old file is still on disk. The decided move (below) has them follow when it isn't (T107).

**`:w name` on a No Name buffer** goes through `BufDelete` and re-creation, which leaves a ghost entry on the closed stack (DESK:2455). **bug (desk)**

**`BufWritePost` on an unregistered buffer** registers it (M3).

**Decided: the disk decides** (DESK:1924):
- If the old name still exists as a file afterwards, the rename is a copy and the old name goes on the closed stack.
- Otherwise it's a move: every reference follows to the new hash, and nothing goes on the stack.

**Decided (2026-10-20 evening), "Keep the older one":** "every reference" includes the secondary map's `-swap` keys, which `rename_hash_in_triquetras` will carry as it carries dtm's (`window/data.lua:142-145`; M7, T192).

### A21. `cleanup_triquetras`: on every history transition

**Today** (`window/routines.lua:247-533`). It runs on every `BufEnter`, `BufDelete`, rename event, cycle start and stop, and load. It also runs from the UI derive path, and from `cleanup_system` when that one removed something. It wipes no buffer. For each triquetra in turn:

1. **The current slot's buffer is not open.**
   - If the window shows some other *registered* buffer, re-point: `c := that`, and clear the secondary or ternary if it equals it. Notifies "Healed the triquetra of window <w> with current slot: <bufnr>", with no level **[run s11]** (`:254-263`).
   - Otherwise:
     - an invalid window → drop the triquetra
     - the window shows the buffer being deleted → it lands once the delete is over (A19, `:287-292`)
     - the window shows a `buftype ""` buffer whose name hashes to the current slot, unregistered for the moment (a rename in progress, a reload without events) → nothing to heal (`:293-297`)
     - the window shows the same file under another `buftype`, or an `acwrite` buffer (`:298-419`):
       - try ternary, then secondary, then `primary[1]`. The first open one becomes `c` and is tracked.
       - when one is found, the window is switched to it on `vim.schedule`, with `nvim_win_set_buf`: this triquetra's own window, whichever window has the focus (T247). A window showing an `acwrite` buffer (oil) isn't switched (`:406-416`).
       - when none is found: drop the triquetra if the slot's path is known, else take the most recent buffer (switched to the same way, and not in an `acwrite` window, `:403`), else `:enew` inside a pcall
     - the window shows something else → drop the triquetra
2. **The secondary.** Cleared when any of these holds (`:438-463`):
   - it has no path
   - it isn't a No Name buffer, it's not open, and its file is unreadable
   - it isn't a No Name buffer, it's not open, and it isn't on the closed stack

   A secondary pointing at an open buffer is kept whatever the disk says, and its buffer stays registered (T239). An open one is cleared only when it has no path, and then its buffer is also unregistered (`:459-461`).
3. **The ternary.** The same rules, reading its own slot (`:465-490`).
4. **Primary entries.** The same rules, each reading its own entry (`:492-519`). The entry is removed from the queue.
5. **The current slot.** When it has no path, its buffer is unregistered (`:522-528`). Its file on disk isn't checked: a new file not written yet, or one deleted on disk, stays current and tracked (M3; T109, T110). The wipe that **[run s08, s09]** traced here is D14's.
6. Refresh the window's UI cache (`:530`).

**Labels:**
- Healing the current slot when the window shows another tracked file is intended (DESK:1929, "re-pointed").
- That the re-point drops the old current from the triquetra is decided (2026-10-20) to change (Q18).
- The switch exists to move a window off a file deleted on purpose, in oil or outside nvim (DESK:1836-1841). The desk reverses it.

**Decided (2026-10-20):** a re-point without an event acts like plain navigation (A1): the old current goes into the ternary (Q18).

**Decided:** cleanup never touches a buffer or a window (DESK:1859-1876):
- A slot pointing at an open buffer is kept, whatever the disk says.
- A missing file stays fully tracked.
- The evolved-window check gives way to the visiting rule.

Built in step 1: the first two points. Cleanup wipes nothing, though healing can still switch a window (item 1 above).

### A22. `cleanup_system`: the timer, before every save, after every load

**Today** (`history/routines.lua:710-807`). The timer runs every `cleanup_interval` ms, 4 s by default, and its first tick is immediate. No pass wipes a buffer. Passes:

1. **Stale registrations:** for each registered buffer that's no longer valid (`:723-742`):
   - When the same file is open as another buffer, found by exact name over `nvim_list_bufs()` (`find_buffer_by_filepath`, `:692-702`, never for a No Name hash), the registration is re-pointed to that buffer, and the hash keeps its history (T113, T273).
   - Otherwise `detach_filehash_from_crux` (`:668-685`) forgets the hash: it removes it from the history view, global and window history, and unregisters the buffer. It touches only cavediver's own data.
2. **History of buffers that aren't valid:** a history entry is kept when its hash has a registered buffer, whatever the disk says (`:744-756`). Otherwise it's detached as above. The report lists detached entries as orphaned files (**[run s08]**: "CAVEDIVER CLEANUP REPORT: … Orphaned files: …/brandnew.txt").
3. **Closed-stack pruning:** remove entries with no path, entries whose file is gone, and entries that are open again. It reads `filepath:match` before the nil check, and removes entries inside an `ipairs` loop (`:761`, `:779`). **bug (desk)**
4. **A triquetra reference count:** reported but never acted on.
5. **When anything was removed:** run A21 on every triquetra and rebuild the ordered lists. A re-point in pass 1 doesn't count **[code]**.

When the total is above 0, it notifies "CAVEDIVER CLEANUP REPORT: …" at INFO.

**Decided:** the 4 s timer stays as a safety net that only repairs cavediver's own data. The stale pass re-points to the file's live buffer, found by exact name, and never wipes. History follows along. Closed entries whose file is missing stay (DESK:1863-1876). Built in step 1: the stale pass's re-point, and no pass wipes. History following along (P10) and keeping closed entries whose file is missing (T114) aren't built.

### A23. Debug commands

Created at require time (`init.lua:154-369`):
- `:CavediverHistoryData`, `:CavediverNavigationData`, `:CavediverWindowData` and `:CavediverUIData` print `vim.inspect` of the domain's data.
- `:CavediverTriquetra` and `:CavediverTriquetraVerbose` print the current window's slots, with names and loaded or closed in the verbose one. `:CavediverTriquetra` also prints the maps.
- `:CavediverRegistry` prints both registries and the closed stack.
- `:CavediverAllTriquetras` prints every triquetra and UI cache.

The `CavediverTriquetra*` commands print `primary_buffer[1]` as "Primary buffer". **Label:** intended (debug only). The descriptions say "curernt" (`init.lua:158`, `:161`).

### A24. Query and utility exports

These take no action. They return live tables, not copies:
- `get_buffer_history()` returns the history view (`history.data.crux`), not an ordered list. STATUS:471 says "ordered".
- `get_window_triquetra(w)` calls the getter, so **it can create or drop a triquetra** (M6).
- `get_all_triquetras()` returns `window.data.crux`.
- `get_*_state()` and `is_cycling()` return the machines' states.
- `set_cache_from_window_triquetra(w)` re-derives one window's UI cache.
- `get_smart_basename` is nil (see Coverage).

### A25. `setup(user)` and what runs at require

**Today:**
- `require('cavediver')` loads every domain. That creates all the autocmds and debug commands, and the 200 ms probe.
- `setup(user)`:
  1. merges the config
  2. defines the highlights
  3. starts the UI timer and the cleanup timer
  4. maps the keys

  Calling it twice starts a second pair of timers and remaps the keys **[inferred]**. `setup()` with no argument throws (M13).
- Until a load or a first `BufEnter`, nothing is registered. The buffer nvim starts on isn't tracked until something enters it.

**Decided:** nothing runs at require. `setup()` creates everything inside one `cavediver` augroup with `clear = true`, and running it again replaces it all. `setup()` with no argument uses the defaults. `disable()` clears the augroup and stops the timers (DESK:2177).

### A26. The flight recorder (decided 2026-10-21, not built)

The author's idea, 2026-10-21: "maybe for debugging purposes, we log the sequence of the winbar rendering, which shows the triquetra, and also other things like the displacement, and other things. this is for only things that _shouldn't_ happen."

**Decided (2026-10-21):**
- It **records all the time** into a small ring of the last N steps (oldest dropped), and **dumps only when something that shouldn't happen fires** ("Yes, ring + dump").
- A step is cavediver's **keymap actions** (`<M-f>`, `<M-S-f>`, the restores, cycling, primary keys, `<M-.>`, `<M-S-w>`) and the **editor events** it reacts to (`BufEnter`, `WinEnter`, `BufDelete`, renames), never raw keystrokes. The author: "i meant the keymaps not keys. and events make sense as well." Each step keeps the window and the result as `⦉ternary⦊ [current] ⟦secondary⟧`, the primary queue and the notes.
- What fires a dump: the restore assertion (`window/routines.lua:737-739`), the fill assertion (D11), "Duplicates detected" (`window/hooks.lua:64`), the highlight callbacks' `error()` (`ui/init.lua:243` and on), "This impossible error should never happen" (`window/routines.lua:733`), and a hook failure (caught with traceback, decided on the desk).
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
| I1 | Within one triquetra, current, secondary and ternary hold three different hashes, or are empty. | **Violated.** Asserted at `window/routines.lua:115` and `window/hooks.lua:64`, but nothing dedupes. Known routes: `<M-f>`'s history fallback picking the current buffer, a rename with a nil hash in `<M-S-f>` (DESK:2469), the save substituting `primary[1]` into a No Name current slot (DESK:2440). Decided: the sources get fixed and the assertion stays (DESK:1939). The primary queue isn't covered: its `[1]` may share a slot's buffer (Q16). |
| I2 | Every hash held anywhere has a path in `hash_filepath_registry`: slots, primary queues, both displacement maps (`-swap` keys included), history, and the closed stack. | **Violated.** Paths are forgotten at `history/routines.lua:296`, `:436` and `:477` while slots or maps still point at them, so a save throws at `storage/routines.lua:122` (DESK:1062). Slots are pruned at the next transition (A21); maps never are. Decided: "a path is never forgotten while anything references its hash" (DESK:84). |
| I3 | Every triquetra has its window's history entry (`crux_internals.window[winid]`). | **Violated** by `:vsplit` **[run s16]**, and the save then throws at `storage/routines.lua:340`. Decided: they're created together (DESK:84). |
| I4 | A slot or primary entry holding a closed hash keeps it until it's used, and using it reopens the buffer. | **Enforced** while the closed file is on disk: each check reads its own slot or entry (`window/routines.lua:450`, `:477`, `:506`; T42, T56, T103, T104). A closed slot whose file is gone from disk is pruned (A21, P9). **[run s05, s06]** recorded the wrong-slot check (D13). README:15 intends it. |
| I5 | The registry is a bijection: `buffers[h] = b` exactly when `hashes[b] = h`, and likewise for paths. | **Enforced** by the writers (M2) **[code]**. A buffer renamed with no events is tracked under a new hash that isn't registered (`history/routines.lua:292`) **[inferred]**. |
| I6 | A registered buffer number is a valid buffer. | **Eventually enforced** by the stale pass of `cleanup_system` (A22), which re-points a registration to the same file's live buffer and wipes nothing. Unlisted buffers and `noautocmd` wipes fire no `BufDelete`, so the registry is stale for up to one tick. Decided: re-point to the live buffer, never wipe (DESK:1863). Built in step 1. |
| I7 | A hash on the closed stack has no open buffer. | **Eventually enforced**: `track_buffer` removes it on a visit (`history/routines.lua:229`), and the cleanup pass does too (A22). |
| I8 | A window's current slot is the hash of the buffer the window shows, except: **(a)** while cycling, when it stays the cycle's start, which is intended (Q1); **(b)** while visiting, under the decided rule. | **Enforced** at every `BufEnter` and re-pointed by cleanup. **Violated** when `displacement_mangement` aborts on duplicates (A1, "Duplicates detected in current triquetra"). |
| I9 | Every triquetra belongs to a valid, non-floating window. | **Enforced** by `WinClosed`, the getter's float check, and cleanup. `:file` onto a name not on disk keeps its window and triquetra (T284, on the route of DESK:2444). |
| I10 | Only tracked buffers are registered (M3). | **Enforced at registration.** A buffer whose `buftype` changes later stays registered until re-entry or cleanup, which is how transient `:copen` and `:terminal` buffers get in (DESK:2453). Decided: the listed-only rule, and undo on `OptionSet` (DESK:1789, DESK:2162). |
| I11 | `ordered.crux` is newest first and holds only open, registered buffers. | **Enforced** at each rebuild (`history/routines.lua:311-329`). It's frozen on purpose while cycling. |
| I12 | Cavediver never wipes or discards a buffer with unsaved changes. | **Enforced** (T109, T131): cleanup wipes nothing (A21, A22), a file not on disk stays tracked (M3), and `:file` and `:saveas` keep their edits (A20, T106). A modified No Name buffer closed with `<M-.>` keeps its text on the closed stack (A15). The wipes recorded by **[run s08, s09]**, DESK:2442 and DESK:2448 are D14's, A20's and A22's routes. Decided: cleanup never touches a buffer, and missing files stay tracked (DESK:1859, DESK:1925). Built in step 1: no wipe, and missing files stay tracked. |
| I13 | Cavediver changes only the window an action is about. | **Violated** by `reopen_filehash`'s cursor, which it sets on the current window (DESK:2473). Healing switches its own window, on `vim.schedule` (`window/routines.lua:411-415`; T247, on the route of DESK:2447), and a deleted buffer's window lands in that window (A19; T111, T132). Decided: the pick after a delete lands in the window that showed the buffer (DESK:1931). Built in step 1. |
| I14 | Every saved file can be written whatever state cavediver's data is in. | **Violated:** `"FUCKING BAD"`, `next(nil)`, a hash with no path (DESK:1058-1064). Decided (DESK:1058). |
| I15 | Hashes are a pure function of the name: the first 16 hex characters of sha256(name .. "\n"). | **Violated** for names with shell metacharacters (DESK:2441). Decided: `vim.fn.sha256` (DESK:2131). |
| I16 | A No Name id is never reused, across sessions too. | **Violated:** bufnr reuse (DESK:2285-2287). Decided (DESK:2289). |
| I17 | Displacement-map and history entries point only at things still known through open buffers, slots, primary queues or the closed stack (follow along). | **Not enforced**: the maps are never pruned. Decided (DESK:2029). |
| I18 | The primary queue has no duplicate entries. | **Enforced** by `set_primary` (`window/routines.lua:776-779`). The popup can introduce duplicates, since `update_primary_buffer` doesn't dedupe **[code]**. |
| I19 | An empty primary queue may be switched on or off; nothing forces it off. `<M-;><M-x>` on an empty queue always queues the current buffer and switches on (A9). | **Holds** for the state: pruning leaves `p=[]on` **[run s06, s19]**, and `jump_to_primary` falls back to `<M-f>` either way. **Violated** for the key: the first press on `p=[]on` gives `p=[A]off` **[run s19]**. decided (2026-10-20) (Q14). |
| I20 | Storage: `load_session` only from `bare`, `save_session` from `bare` or `idle`, and storage is `idle` after either. | **Enforced**: anything else throws from `to()` **[run s10]**. Decided: `idle → bare → loading` (DESK:1284). |
| I21 | A transition always completes: the state changes even when a hook fails. | **Enforced** (`engine/helpers.lua:32-45`). Decided exception: the critical save hook re-throws and leaves storage at `idle` (DESK:1157). |
| I22 | A file appears at most once in a closed pool (today, the one closed stack). Closing a file that's already there moves it to the newest position; a merge of pools keeps only the newer entry. | **Not enforced**, but no route found that breaks it today **[run s20]**. With the desk's per-tab pools and the merge picker, a merge is the route. decided (2026-10-20) (Q15). |
| I23 | No buffer is current while its note names the buffer already in the slot that note restores into. For the current buffer X and each map, the note a restore would read is X's swap note when it's set and isn't the slot's occupant, otherwise X's plain note; that note never names the occupant of the ternary (dtm) or the secondary (dsm). A plain note behind a valid swap note may name it: the restore never reads it. | **Violated** today: every restore throw is this state (A11), 161 secondary and 14 ternary throws in 1,500 walks **[run]**. Decided (2026-10-20 evening), "Keep the older one" (A1, M7, Q13), with the check also at the secondary restore's exchange (decided 2026-10-21): 0 breaks over 900,000 walk steps with every fix in **[sim, variant `all_fixed`]** (T189, T206). Checked by T190. |

## 5. Sessions

### S1. Today

**API.**
- `save_session(cwd)` and `load_session(cwd)` (`storage/init.lua:24-44`). Both throw "CWD is required to save session" when `cwd` is nil.
- The README wires them to resession's `pre_save` and `post_load` with `vim.loop.cwd()` (README:93-99).

**State machine.**
- Save is `→ saving → idle`, from `bare` or `idle`.
- Load is `→ loading → idle`, **only from `bare`**. So any load after the first save or load in a process throws `Transition 'idle->loading' is not registered` from `to()`. It escapes resession's hook, and session switching breaks **[run s10]**, DESK:1254-1260.
- Both hooks run inside `pcall`, so a failure inside a save or load is only a notification, and storage still goes to `idle`. With a read-only session directory, resession's file is written and cavediver's isn't (DESK:2452).

**File.**
- Path: `session_dir/<first 32 hex of the shell sha256 of cwd>.json`. It's plain JSON, created as `{}` first if it's missing.
- Written with `writefile`, which isn't atomic and uses umask permissions (`storage/routines.lua:696-713`).

**Save** (`save_history`, `storage/routines.lua:686-714`):
1. `cleanup_system` runs (A22). It wipes nothing, but it can prune the closed stack (T214).
2. The keys written **[run s10]**:
   - **`buffers`**: `{window = [...], global = crux_internals.global}`. `window` lists the history of each window that has a triquetra and a non-empty history, in `nvim_list_wins()` order, skipping windows whose buffer isn't `""`/`://`/`image_nvim`. A window with a triquetra but no history entry throws `next(nil)` at `:340` **[run s16]**.
   - **`windows`**: one entry per window with a triquetra, in `nvim_list_wins()` order, filtered the same way. Each entry is `[current, secondary, primary_queue[], ternary, dtm, dsm]` (`:490-497`).
     - A slot whose buffer is open is saved as its raw hash.
     - Anything else is saved as the path XOR'd with the cwd and base64-encoded (`obfuscate_filehash_if_needed`, `:117-128`).
     - A hash with neither a buffer nor a path throws.
     - Both maps are written raw, `-swap` keys included.
   - **`closed`**: the closed hashes, as XOR'd paths. Every path inside the cwd begins with a run of zero bytes, so the output is all `A`s in base64 **[run s10]**, DESK:1561.
   - **`noname_content`**: keyed by the XOR'd `NONAME_` name. Each line is XOR'd; filetype and cursor are stored in clear.
   - `primary_enabled` isn't saved.
3. In the saved entry only (the live triquetra is untouched), a current slot holding an open No Name buffer is replaced by `primary[1]`, else the ternary (which is then left out of the entry), else the secondary (likewise), else the string `"FUCKING BAD"`, which throws, so the whole save fails (`:437-453`). The `primary[1]` branch can leave the same file in the secondary as well, which starts the duplicate-slot error after a restart (DESK:2440).
4. **Oil windows** that have a triquetra are switched to their current-slot file under `eventignore=BufEnter,BufLeave` and never switched back (`:500-510`). Autosave does this mid-session.

**Load** (`load_history`, `storage/routines.lua:639-677`):
1. Read and `json_decode` the file, each inside `pcall`. If either fails, or the data lacks `buffers` or `windows`, it's a **silent fresh start**, and the next save overwrites the file (DESK:2458).
2. With data:
   - **`load_buffer_history`** registers every **loaded** buffer with `buftype ""` or `image_nvim` and no `://`. It then runs `track_buffer(hash, time)` for every saved global entry, including entries that aren't open.
   - **`load_closed_buffers`** clears the stack. Each entry is deciphered and registered, and `NONAME_` entries get their content restored. It throws when the content is missing or already present, or when a closed file already has a buffer (`bufexists`). A throw stops the rest of the load (DESK:2471).
   - **`load_window_buffer_relationships`** matches saved entries to the windows whose buffer is `buftype ""` with no `://`, **by position** in `nvim_list_wins()`.
     - A value with an open buffer resolves to its hash.
     - Anything else is deciphered as a path. When the buffer wasn't restored, or was restored unloaded, that gives noise, and the slot comes back empty or the current slot gets healed **[run s11]**, DESK:1379.
     - The No Name current-slot branch never runs, because of a key mismatch (`:244`) **bug (desk)**.
     - `primary_enabled` comes back as "queue not empty" **[run s12]**: `p=[b]off` at save gave `p=[b]on`.
   - **`initialise_crux_internals`** maps the saved window histories onto the same window list by position, then rebuilds the view, now and again after 210 ms. A count mismatch throws `table index is nil` (`history/routines.lua:144`, DESK:1381).
3. Without data: a **fresh start**. Cavediver's state is cleared and every loaded buffer registered (`repopulate_history`), and every window gets `{c=X}` (`repopulate_window_relationships`).
4. Then `cleanup_system` runs, and history → `attached` with the current buffer.

**[run s12]**: the happy path. A file saved with `{c=d s=c t=e p=[b]off}` and `dtm{b→a, c→b, e-swap→d}` came back the same, except `p=[b]on`, with `b`, `c` and `e` loaded and `d` shown.

### S2. Decided (DESK, not implemented)

**Contract and API** (DESK:749-794):
- Cavediver is manager agnostic, with no adapters.
- `save_session(name?, opts?)`, where `opts.tab` marks a tab session, and `load_session(name?)`. Neither takes a directory: cavediver reads it itself, `getcwd(-1, -1)` for the whole editor or the tab's directory for a tab session.
- A written contract says who calls the two functions and when: resession, native `:mksession`, and no manager, with the table at DESK:764-771. It includes saving the outgoing session through the manager before a switch, and saving a tab session on `TabClosedPre`.

**Loading** (DESK:1276-1288, DESK:794, DESK:1161):
- `load_session` from `idle` goes `idle → bare`, where every domain tears down its own state, then `bare → loading` as at startup.
- Repeat calls within one native restore are skipped by a flag that `vim.schedule` re-arms. A later reload is a full load.
- Cavediver reloads by itself after Neovim's `:restart` session, ignoring the flag.
- One post-restore callback replaces the 200 ms and 210 ms delays.

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
  - `cleanup_interval` is 8000 at README:323 and 4000 at `configs.lua:132`. Both comments say "seconds", but the timer is in milliseconds (`history/init.lua:39`).
  - The README leaves out `primary_buffer_history_popup`, the `open_primary_buffer_history` keymap (it mentions `<m-;>F` at README:32) and `colors.cokeline.diagnostics`.
  - README:285 has `is_picking_focus`, which `configs.lua` lacks. Neither colour is used: the picking colours are hard-coded at `ui/init.lua:366-368`, in the old palette (`#a05959`, `#d7d7a5`).
  - How it drifted: the code's palette changed in `778668f` ("chore(config): updated default colors", 2026-01-07) and `cleanup_interval` went from 8000 to 4000 in `59463f2` (2025-07-17); the README's block is from its first draft (2025-07-10).
  - **Settled (2026-10-20):** the README follows the code: its defaults block copies `configs.lua`, including the missing keys, and the `cleanup_interval` comment says milliseconds. The pick letters read their colours from the config, `colors.cokeline.is_picking_close` and a new `is_picking_focus`, instead of the hard-coded pair. The `is_picking_focus` default is the author's to pick (T168).
- **D3. Keymap descriptions.** `close_buffer` (`init.lua:111`) and `open_primary_buffer_history` (`init.lua:117`) are both described as "Toggle current buffer as primary". So is `cycle_select` in its annotation at `configs.lua:10`.
  - **Settled (2026-10-20):** each key gets its own description: `toggle_primary` "Switch the primary on or off" (Q8), `close_buffer` "Close the current buffer", `open_primary_buffer_history` "Open the primary queue". `cycle_select`'s annotation copies the author's own description of that key, "Select cycling buffer and attach history" (`init.lua:86`) (T169). The `cycle_select` annotation copying the author's own description was confirmed by the author (2026-10-20, late evening).
- **D4. Hashing dependency.**
  - Today: README:47 requires `openssl` "for hashing file names and directories", but the code runs `sha256sum` through the shell (`history/routines.lua:24`, `storage/routines.lua:619`).
  - Decided: `vim.fn.sha256` for hashing, and `libcrypto` only for encryption (DESK:1541, DESK:2131).
  - **Settled (2026-10-20):** README:47 says `libcrypto` (OpenSSL 3) is needed to encrypt the session file, and hashing needs nothing extra.

**Primary**

- **D5. A disabled primary.**
  - README:31: `<m-;><m-f>` "won't do anything at all, until you set it to active again", and you can still use the popup while it's disabled.
  - Code: `<M-;><M-f>` falls back to `<M-f>` (`window/routines.lua:711-714`) **[run s02]**, and saving the popup sets `primary_enabled = true` whenever the queue isn't empty (`window/routines.lua:69-73`).
  - **Settled by Q10:** the code wins for the key. With the primary disabled, `<M-;><M-f>` acts like `<M-f>`, and README:31 changes. The popup save follows a new rule: it switches the primary on only when the first row changed, and otherwise keeps the on/off state (A18).
- **D6. A popup save with an invalid path.** README:26-28 says nothing is saved. The code reports the bad lines and saves the valid ones (`window/routines.lua:62-74`).
  - **Settled by Q11:** the code wins, and README:28 changes.
- **D12. Popup close keys.** `q` and `<C-c>` are described as "Close without saving" (`ui/hooks.lua:104-106`), but `close_window` runs `write!` first (`ui/hooks.lua:65`).
  - **Settled by Q12:** the code wins. They save and then close, and their description changes to "Save and close".
- **D19. Primary overlapping a slot.**
  - README:368: "A buffer cannot occur more than once in a window triquetra."
  - SPEC:44 and SPEC:294: the primary is mobile and "can occupy any slot position". The code allows it.
  - `bufferline.get_buffer_relationships` asserts each buffer has one role, so it throws when, for example, current = primary (`ui/init.lua:189-213`) **[run s14]**.
  - So README:368 holds for the three slots only.
  - **Settled by Q16:** the primary is mobile. README:368's "no buffer twice" covers the current, secondary and ternary only. `get_buffer_relationships`' one-role assertion is fixed or removed; nothing calls it.

**Swaps, restores and maps**

- **D7. Do swaps write displacement entries?**
  - SPEC:133 and SPEC:239-244: "Pure swaps never create mappings" (`<M-f>`, `<M-S-f>`).
  - README:355: `<M-f>` records the current buffer's secondary.
  - STATUS:419-428: the secondary swap writes `dsm[old] = secondary` and `dtm[old] = ternary`.
  - Code: `<M-f>` writes `dsm[A]` and `dtm[A-swap]` (`window/routines.lua:575-578`), and `<M-S-f>` writes `dtm[A-swap]` (`window/routines.lua:107`).
  - Four sources, three answers (Q2).
  - **Settled by Q2:** the code wins. Swaps and primary jumps write swap notes `dtm[A-swap]`, and navigation writes plain notes (M7). SPEC:133, SPEC:239-244 and STATUS:419-428 are out of date.
  - **Decided (2026-10-20 evening), "Keep the older one":** `<M-f>`'s secondary note moves into a swap key too, `dsm[A-swap]`, so the secondary map has the same two kinds of note (M7).
- **D8. Reaching the secondary by plain navigation.** README:355 says "every time you jump to secondary" the secondary is recorded. A plain `:e` to the secondary swaps it with no `dsm` write (`window/hooks.lua:52-54`) **[run s01]**.
  - **Settled (2026-10-20):** plain navigation onto the secondary records the same notes as `<M-f>`, so `<M-;><M-t>` works after either route **[run `t/b5_A_use.lua`, `<M-f>` standing in]**. The author, shown the round trip that then throws like `<M-f>`'s own (`t/b5_A_round.lua`, `t/pkB_secflip.lua`): "we should solve the round trip as well." README:355 stays. Confirmed by the author (2026-10-20, late evening), after being recorded from a reading of their words.
  - **Decided (2026-10-20 evening), "Keep the older one":** the round trip is solved on both routes. The note goes into a swap key, `dsm[A-swap]`, and on arrival the buffer's plain note becomes its secondary from before (M7, A1, A6). After a round trip the restore says there's nothing to restore, or brings back the older secondary when there is one, instead of throwing (T177–T180, T191).
- **D9. Restore edge cases.**
  - SPEC:170-178: when the remembered value is missing, invalid or the same as the slot, show "No different ternary relationship to restore". The code throws when it's the same (`window/routines.lua:816-818`) and when it has no path (`:811-812`).
  - SPEC:493-495: an invalid file gives the message. The code warns and clears only `map[A]`, not `map[A-swap]` (`:813-815`).
  - SPEC:700 needs an open buffer for the remembered value; the code needs a path and a readable file.
  - **Partly settled by Q13:** the throw when the remembered value equals the slot stays, as an assertion, and SPEC:176 is out of date. The other three cases (the throw when the remembered value has no path, a desk bug at DESK:2449; the invalid-file case that clears only `map[A]`; SPEC:700's open-buffer requirement) are settled below.
  - **Settled by the desk (2026-10-20 evening):** the no-path throw goes, because a note at an unknown hash is cleared when used (DESK:1936, :1938, :2029, :2449; T68) **[run `t/pkB_d9_nopath.lua`]**. SPEC:700's open-buffer requirement is out of date: a closed hash is kept and reopened when used (DESK:1935, README:15) **[run `t/pkB_d9_closed.lua`]**. What a restore does when the remembered file is missing from disk, **settled (2026-10-20 evening)** in the author's words: "well, if the thing is closed we may skip it. if it's open we can go through and flip-flop with it.." For both restores (one function, `window/routines.lua:713-762`): Confirmed by the author (2026-10-20, late evening), after being recorded from a reading of their words.
    - The remembered file is missing and **closed** (no buffer): it's skipped and kept, as DESK:2022 keeps pointers. A skipped swap note falls back to the plain note. If that's missing and closed too, the restore says so and changes nothing.
    - The remembered file is missing but its **buffer is open**: the restore goes through and flip-flops with it, saying the file isn't on disk.
    - Today it instead deletes the plain note and stops on the swap note forever **[run `t/b6_rows.lua`, `t/b6_open.lua`; the rule in variant `d9U`]** (T67, T173, T174).
    - Under "Keep the older one" the rule covers the secondary map's swap keys too (M7, T193).
- **D11. The secondary's first population.**
  - SPEC:299-300: "No auto-population: Never automatically populated from history." SPEC:92-94, the code and STATUS fill it from history on the first `<M-f>` (`window/routines.lua:567-569`).
  - SPEC:428-447, "Secondary Population Edge Case", puts the current buffer in the secondary (`current: A, secondary: A`), which breaks SPEC's own Rule 1 (SPEC:343) and README:368. The code takes `ordered[2]`.
  - **Settled (2026-10-20 evening):** the fill from history stays (pressing `<M-f>` is acting, P14). The duplicate came from a cycle in another window freezing the history **[run `t/b7_dup.lua`; under `history_view = "window"` the same route duplicated in 7 of 8 re-runs, `t/b7w_dup.lua`: the window view's rebuild ties two buffers and the tie breaks at random, see the bug below]**. The author's fix is at the cause: jumping windows ends the cycle (A12). The fill then **asserts** that the ordered list's first entry is the window's current buffer, so any leftover route throws and gets fixed, the same stance as Q13 (T176).
  - **bug (new), found 2026-10-21:** the window view's rebuild (`history/routines.lua:191`, `:194`, in `construct_crux`) gives a window's newest buffer the next free access time, so the next buffer recorded ties with it. When the window entry fires no `BufEnter` (same buffer in both windows, e.g. right after `:vsplit`, or after `:close`), the tie breaks at random from one Neovim start to the next. Shortest route to the fill assertion: `:e a`, `:e b`, `:vsplit`, `<C-w>p`, `:e c`, `:vsplit`, `<M-f>` **[sim, window view, multi-window walks]** (T197).
  - The fix, as tested in `all_fixed`: `history/routines.lua:191` `data.history_index = data.history_index + #window_buffers - 1` becomes `+ #window_buffers`, and `:194` `data.history_index - rank + 1` becomes `data.history_index - rank`. A window's buffers keep their order, and the next visit always ranks first on its own: no tie in 675,000 several-window steps.
  - **bug (new), not exercised:** the session-load branch of `track_buffer` (`history/routines.lua:214-218`) can hand out an access time that's already in use, the same kind of tie. No walk loads a session.
- **D20. Old model shapes.**
  - SPEC:51-63 has one `displacement_map` and a single `primary_buffer = filename|nil`. The code has two maps with `-swap` keys and a primary queue with `primary_enabled` (`window/data.lua:8-15`).
  - SPEC:686-692 has `jump_to_primary` writing both `dsm[current]` and `dtm[current]`. The code writes only `dtm[current-swap]` (`window/routines.lua:731`).
  - **Settled by Q2, Q3 and Q8:** the code wins, and SPEC's shapes are out of date. Q2 keeps the two kinds of ternary note and the primary jump's swap note, Q3 keeps the separate secondary map, and Q8 keeps the primary queue with its on/off switch.

**Cycling**

- **D10. The current slot during cycling.**
  - SPEC:194 says "only current slot changes". SPEC:385-407 has the current follow the cycle and `<M-f>` swap the cycled buffer with the secondary.
  - README:384 says "no matter how you cycle, the current slot buffer doesn't change". The code agrees **[run s03, s04]**.
  - While cycling, `<M-f>` jumps back to the start (A6 step 2) instead of swapping.
  - **Settled by Q1 and Q7:** the code and README:384 win. The current slot stays on the start until `<M-v>` (Q1), and the slot keys jump back to the current slot when the window isn't showing it (Q7). SPEC:194 and SPEC:385-407 are out of date.
- **D15. A checkpoint copy or a live reference.** `snapshot_origin` says it "stores a deep copy" (`history/routines.lua:374`), but it stores the live triquetra (`:380`) **[run s03]**.
  - **Settled (2026-10-20):** live is intended: the cycle's start is the window's current slot, so `<M-;><M-f>` mid-cycle lands on it even after a swap or a close moved it **[runs `t/pkB_d15_*.lua`]**. Only the docstring at `history/routines.lua:367-370` changes, in plain wording: "Mark the window's triquetra as the cycle's checkpoint. The checkpoint is the window's own triquetra, not a copy, so it always names the window's current slot."
- **D21. File-picker mode.** SPEC:906-909 says displacement is paused and normal mode comes back automatically after a pick. In the code `file_picker` is registered and never entered (`navigation/sm.lua:24`). STATUS:103 calls it "unused by design".
  - **Settled (2026-10-20):** keep it as scaffolding. A comment at `navigation/states.lua:8` says nothing enters it yet, and SPEC:906-909 is marked as not built. Explorers stay under the visiting rule. The pop-up's `<M-e>` picker (Q11) is unrelated; it shares the name only.

**Closed buffers and cleanup**

- **D13. Closed buffers reopening.** README:15 ("Closed buffers reopen when accessed through relationships") and STATUS:37, STATUS:382-392 say a closed slot reopens. The code prunes closed secondaries and primary entries because the check reads the wrong slot (`window/routines.lua:345`, `:401`) **[run s05, s06]**. The desk lists this (DESK:2470).
  - **Settled (2026-10-20):** a code bug. Each staleness check reads its own entry (DESK:2470), as the comment under each check says (`window/routines.lua:346-348`). README:15 stays as written; I4, T42 and T56 stand **[run `t/pkA_d13.lua`]**.
  - Built in step 1: each check reads its own slot or entry (`window/routines.lua:450`, `:477`, `:506`). T42, T56, T103 and T104 pass.
- **D14. A second trigger for the new-file wipe.** The desk's repro stays on the new file and waits, so the cleanup tick wipes it, `bw!` from `history/routines.lua:678` (DESK:2446, DESK:3250). Navigating away instead wipes it sooner, at the **next `BufEnter`**, from `window/routines.lua:428` inside `cleanup_triquetras` (A21 step 5) **[run s09]**. Both triggers exist. DESK:1870 already lists that path (healing's missing-file wipe, `:417-449`) for removal, so the decided fix covers it; the bug entry just names only the timer.
  - **Settled (2026-10-20):** the decided fix already covers both triggers (DESK:1859, :1865, :1870). At the next desk sync, the bug entry (DESK:2446) gains the faster route and the dead window ("Sooner still, the next `BufEnter` anywhere wipes it…"), and its repro (DESK:3250) gains "Or skip the wait…" **[run `t/pkA_d14.lua`]**.
  - Built in step 1: both triggers are gone. No `cleanup_system` pass wipes (A22), and `cleanup_triquetras` doesn't check the current slot's file on disk (A21). T109 and T110 pass.
- **D16. Comment on `<M-.>`.** "go to most recent (first in list)" (`history/routines.lua:588`), while the code goes one step older. Known on the desk, and the code is right (DESK:2478).
  - **Settled (2026-10-20):** the one branch comment becomes `-- Otherwise go to most recent relative to the one deleted (next in list, wraps around)`, built from the author's words, "the most recent is relative to the one deleted". The other branch comment stays.
- **D22. The cleanup report.** STATUS:143-158 shows counts by category. The code notifies the total and lists the paths (`history/init.lua:43-72`).
  - **Settled (2026-10-20):** closed by archiving STATUS.

**Windows and documentation of the data**

- **D17. Window-jump history per tab.** `navigation/data.lua:9` ("Per-tab") and STATUS:115 (`[tabnr][to_win]`) describe a per-tab table. The code uses one flat table (`navigation/data.lua:41`, `navigation/routines.lua:40`).
  - **Settled (2026-10-20):** the flat table is intended. After a tab switch, `<M-,>` takes you back to the window you left in the other tab, as today **[run `t/pkA_d17.lua`]**. The author flattened it in 60540e7 (2025-07-20). Only the comment at `navigation/data.lua:9` changes: "Current window -> previous window mapping, one table across all tabs". STATUS:115 goes with STATUS.
- **D18. Storage documentation.**
  - STATUS:301 leaves out `bare` (`storage/states.lua:20`).
  - STATUS:311-321 gives the saved window entry as `[secondary, primary, ternary]`. The code writes `[current, secondary, primary_queue[], ternary, dtm, dsm]` (`storage/routines.lua:490-497`). The annotation at `storage/routines.lua:12-16` types `[3]` as `string|vim.NIL`, but it's an array.
  - Outside the listed sources, the project `CLAUDE.md` (now `archive/CLAUDE.md`) also has the old three-field shape.
  - **Settled (2026-10-20):** STATUS is archived. The annotation at `storage/routines.lua:12-20` is fixed to the six fields the code writes (current, secondary, the primary queue as a list, ternary, the ternary notes, the secondary notes; `:490-497`), with the example updated, in plain wording. The project `CLAUDE.md` is archived too, at `archive/CLAUDE.md` (it carried the old three-field shape, a code tree with directories that don't exist, and progress figures).
- **D23. "No missing functions".** STATUS:631-632 says every function that's called exists and works. Counterexamples:
  - `get_smart_basename` is nil (`init.lua:455`) **[run s16]**.
  - `ui_machines.winbar` doesn't exist (`ui/init.lua:99`, `:106`, `:138`).
  - The bufferline and indicator transitions aren't registered (`ui/init.lua:84-121`).
  - **Settled (2026-10-20):** the claim is archived with STATUS. The gaps stay bugs: `get_smart_basename` is nil (T120), and the missing winbar machine and bufferline transitions are on the desk (DESK:2482).
- **D24. STATUS's config example.** STATUS:477-498 shows `auto_save`, `save_interval`, `ui.winbar_enabled` and `cleanup_interval = 300 -- 5 minutes`. None of these match `configs.lua`.
  - **Settled (2026-10-20):** closed by archiving STATUS.
- **D25. Small comment slips in the code.**
  - "closed buffer filenames" (`history/data.lua:81`, `history/init.lua:92-94`), where the stack holds hashes.
  - "doesn't create its own state machine" (`window/init.lua:5`), while `window/sm.lua` creates one.
  - `LoopStates` documents `UPDATING "updating"` (`ui/states.lua:18-19`), where the state is `SELF "self"`.
  - The window machine (`window/sm.lua`) has four states (`showing_primary`, `showing_secondary`, `showing_ternary`, `showing_other`), no transitions, and nothing calls `to()` on it; `window/hooks.lua:12` requires it and never uses it. The author calls it an artifact of early modelling.
  - **Settled (2026-10-20):** the closed stack's comments reuse the author's own wording at `history/data.lua:14`, "Stack of closed buffer filehashes that can be reopened"; the loop annotation becomes `---@field SELF "self" Continuous update loop state for UI refresh`. The window machine goes: `window/sm.lua`, the four `SHOWING_*` constants in `window/states.lua`, and their requires (`window/init.lua:7`, `window/hooks.lua:10`, `:12`). The comment at `window/init.lua:4-5` is then true (T170).

**Today against Decided**

The sources differ here until the code catches up with the desk; each entry is settled.
- **D26. Windows showing something untracked.** README:332: the triquetra is cleaned, which matches the code. The desk's visiting rule keeps it (DESK:1785).
  - **Settled (2026-10-20):** the README follows the desk. Only README:332's middle sentence changes, and "tiquetra" is fixed: "When a window switches to a non-regular buffer then it will keep the triquetra associated to that window, and the current slot stays on the file you were on, so `<m-f>` brings you back to it. The winbar shows it like `main.lua ← [help]`." The code follows in build step 3.
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
- T9 [target] A path containing `"`, `$HOME` or a backslash hashes to the first 16 hex characters of `vim.fn.sha256(path .. "\n")`.
- T10 [char] `:e` on an existing file registers it. Help, terminal, `scheme://` and `*/otter.lua` buffers aren't registered.
- T11 [today] An entered No Name buffer is registered as `NONAME_<bufnr>`. Decided: an id unique across sessions (I16).
- T12 [char] Registering a second buffer under the same hash binds the hash to the newer buffer and drops the older one's reverse entry.
- T13 [target] An unlisted `buftype ""` buffer that a plugin creates and enters isn't registered.
- T14 [char] A buffer whose file isn't written yet stays registered after it's left and re-entered.

**History (M4)**
- T15 [char] After visiting a, b, c, `ordered.crux` is `c,b,a`.
- T16 [char] With `history_view = "window"`, the order in window 2 puts window 2's own visits first (the s17 sequence).
- T17 [char] Closing a window removes its `crux_internals.window` entry.
- T18 [target] `:vsplit` creates the new window's history entry along with its triquetra (I3).
- T19 [target] A visit is recorded in the history of the window that shows the buffer, not the focused one (for example, `win_execute` in another window).
- T20 [target] `track_buffer(h, t)` stores `t` in the global history.
- T149 [char] A property test over random visits, with `history_view` set to `"global"` and to `"window"`, across windows: after any visit, the visited buffer is leftmost in the bufferline order (`compare_buffers`). The author's check: two windows, back into window A, `:e e` gave `e=7 b=6 a=5 d=4 c=3` (Q4). Under the window view this half is [target] until the tie fix (T197) lands: today the view's rebuild ties two buffers on a window jump and on `:close` alike (`:e a`, `:e b`, `:vsplit`, `:close`, `:e a` gives a=4 b=4; with the tie fix, a=5 b=4) **[run, 2026-10-21]**.

**Triquetra lifecycle (M6, A2–A5)**
- T21 [char] A first `:e x` in a fresh window gives `{c=x}`.
- T22 [char] `:vsplit` gives the new window a fresh `{c=<shown>}`, not a copy.
- T23 [char] A float never gets a triquetra.
- T24 [char] An `acwrite` buffer shown in the window keeps the triquetra.
- T25 [char] Closing a window drops its triquetra and its UI cache.
- T26 [today] `:terminal` in a window with `{c=c s=b}` drops its triquetra, as README:332 says. Paired with T27.
- T27 [target] The window keeps `{c=c s=b}` while it shows the terminal, and `:e c` returns with its slots intact (the visiting rule).

**Plain navigation (A1)**
- T28 [char] `{c=a}`, `:e b` → `{c=b t=a}`, with no map entries.
- T29 [char] `{c=b t=a}`, `:e c` → `{c=c t=b}`, `dtm{b→a}`.
- T30 [today] Going to the secondary with `:e` swaps current and secondary and writes no map entry, when `dtm[T] ≠ S` (for `dtm[T] = S`, see T151). Paired with T191 (D8).
- T31 [char] Going to the ternary with `:e` swaps current and ternary and doesn't write `dtm[current]`.
- T32 [char] A plain navigation that writes `dtm[A]` also deletes `dtm[A-swap]`.
- T33 [char] With `dtm[X] = A` and the ternary T ≠ X, `:e X` from A rewrites `dtm[X] := T`, with the "pre-jump ternary" warning.
- T34 [char] Navigation with secondary equal to ternary reports "Duplicates detected in current triquetra".
- T35 [char] Entering an untracked buffer that the getter keeps the triquetra for, such as an `acwrite` buffer, leaves the slots alone. For `:terminal` and help shown in the window, see T26 and T27.
- T151 [target] Q6 on plain navigation: `:e a`, `:e b`, `:e c`, `:e b`, `<M-f>`, `:e a`, `<M-f>`, then `:e a` again, which reaches the secondary by plain navigation. The ternary's note is rewritten to the buffer left (`dtm[b] := c`), and `<M-S-f>`, `<M-;><M-r>` then restores without throwing, giving `{c=b s=a t=c}` **[sim, variants `rt_q6` and `kt_rewrite_sec`]**. Today this route has no guard: `dtm[b]` stays `a`, nothing warns, and the restore throws **[sim, today's code]**.
- T191 [target] (D8, "Keep the older one") `<M-f>` and plain navigation onto the secondary write the same notes: from `⦉c⦊ [d] ⟦b⟧`, either one gives `⦉c⦊ [b] ⟦d⟧` with the swap notes `dsm{d-swap>b}` and `dtm{d-swap>c}`, and no plain secondary note for d. Paired with T30 and T39. Plain navigation **[sim `rt_cand_use`, variant `rt_c3kga`]**; `<M-f>` **[code]**, the same notes by the same function in the variant.

**`<M-f>` (A6)**
- T36 [char] `{c=c t=b}`, `dtm{b→a}`, `<M-f>` → `{c=c s=b}`, `dsm{b→a}`. The buffer doesn't change, and the message is "Ternary slot graduated" (Q3).
- T37 [char] With secondary and ternary empty and two buffers in history, `<M-f>` fills the secondary from `ordered[2]` without switching.
- T38 [char] With one buffer in history, `<M-f>` warns "insufficent history".
- T39 [today] `{c=c s=b}`, `<M-f>` → shows b, `{c=b s=c}`, `dsm{c→b}`. Paired with T191, where the note goes into `dsm[c-swap]`.
- T40 [char] With a ternary T, `<M-f>` writes `dtm[A-swap] = T` (Q2).
- T41 [char] When the window shows a buffer other than its current slot, `<M-f>` switches back to it and changes no slot.
- T42 [char] After `:bdelete` of the secondary's buffer and one more `:e`, the secondary still holds the closed hash, and `<M-f>` reopens it and takes it off the closed stack.
- T43 [target] After a cycle, `<M-f>` with secondary and ternary empty never puts the current buffer in the secondary.
- T44 [today] With the secondary closed and its file then deleted on disk, `<M-f>` warns "Removed secondary file not found in filesystem" and empties the slot. Paired with T45. Cleanup prunes a closed secondary whose file is gone at the next history event (A21), so `<M-f>` has to come before any.
- T45 [target] With the secondary's file deleted on disk, the pointer is kept and `<M-f>` says the file is missing (DESK:2022).
- T150 [target] Q6's ten keys, as the author ran them: `:e a`, `:e b`, `:e c`, `:e b`, `<M-f>`, `:e a`, `<M-f>`, `<M-f>`, `<M-S-f>`, `<M-;><M-r>`. The third `<M-f>` rewrites the ternary's note to the buffer it leaves (`dtm[b] := c`), and the restore doesn't throw: it gives `{c=b s=a t=c}` **[sim, variants `rt_q6` and `kt_rewrite_sec`]**. Today the third `<M-f>` warns with no change, and the restore throws "Remembered ternary is the same as current ternary".

**`<M-S-f>` (A7)**
- T46 [char] `{c=d s=b t=c}`, `<M-S-f>` → shows c, `{c=c s=b t=d}`, `dtm{d-swap→c}`.
- T47 [char] With no ternary, it warns "No ternary buffer to swap with." and nothing changes.
- T48 [char] A ternary closed with `<M-.>` is reopened by `<M-S-f>` and taken off the closed stack.
- T49 [target] The desk's sequence (`:e 1.txt`, `:e 2.txt`, `<M-n>`, `:bdelete`, `<M-S-f>`, `<M-S-f>`) throws nothing and leaves no duplicate slot.

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
- T153 [target] Q6 on the fallback: with the primary disabled, `{c=A s=S t=T}` and `dtm[T] = S`, `<M-;><M-f>` acts as `<M-f>` and rewrites `dtm[T]` to A before the swap.

**Primary keys (A9, A10)**
- T59 [char] On an empty queue `toggle_primary` gives `[a]on`; again gives `[a]off`; on another buffer it gives `[a]on` with the queue unchanged (Q8).
- T60 [char] `set_primary` on an empty queue gives `[a]on`; on b it gives `[b,a]on`; on b again it gives `[b,a]off`; on a it gives `[a,b]on`.
- T156 [target] The `toggle_primary` keymap's description no longer reads "Toggle current buffer as primary" (Q8).

**Restores (A11)**
- T61 [char] At b with `{c=b t=d}` and `dtm{b→a}`: restore ternary → `t=a`, `dtm{b→d}`; again → `t=d`, `dtm{b→a}`.
- T62 [char] Restoring a ternary equal to the secondary swaps the secondary and ternary contents.
- T63 [char] Restoring the secondary flip-flops: a second press brings back the secondary the first one replaced, and so on (P19). Each press writes the replaced secondary into the plain note `dsm[A]`, and the first press reads `dsm[A-swap]` when it's set and isn't the secondary, otherwise `dsm[A]`. Today there's no `dsm[A-swap]`, so every press reads `dsm[A]`.
- T64 [char] With no entry, it warns "No ternary relationship found for restoration."
- T65 [char] When `dtm[A-swap]` is set and differs from the ternary, the restore uses it instead of `dtm[A]` (Q2).
- T66 [char] With the maps set so that the remembered value equals the slot, the restore throws "This is impossible. Remembered ternary is the same as current ternary." The assertion stays (Q13).
- T67 [target] (D9) A `-swap` entry pointing at a file that's closed and deleted on disk is skipped and kept: the restore uses the plain note (`a>b` gives `⦉b⦊ [a]`), flip-flops with it, and the `-swap` entry is still there afterwards.
- T173 [target] (D9) A note pointing at a file deleted on disk whose buffer is still open restores it and flip-flops with it (`⦉f⦊ [a]`, then `⦉d⦊ [a]`, then `⦉f⦊ [a]`).
- T174 [target] (D9) When both of a buffer's notes point at closed files deleted on disk, the restore says so, changes no slot, and keeps both notes.
- T68 [target] An unknown hash in a map doesn't make a restore throw.

**"Keep the older one": the restore errors (M7, A1, A6–A8, A11, A13, I23)**

These pin the decision of 2026-10-20 evening. The states are the ones the variants gave; "today" is today's code on the same keys.
- T177 [target] ("Keep the older one") The round trip onto the secondary and back: `:e a`, `:e b`, `:e c`, `<M-f>` (b graduates), `<M-f>` (to b), `<M-f>` (back to c), then `<M-;><M-t>` on c doesn't throw. It says "No secondary relationship found", since c has no secondary from before; the window stays `⦉-⦊ [c] ⟦b⟧` with `dsm{b-swap>c b>a c-swap>b}`. Today it throws "Remembered secondary is the same as current secondary" **[sim `rt_sec_round`, variants `rt_c3kga` and `kt_rewrite_sec`]**.
- T178 [target] ("Keep the older one", Q3) T177's keys, then one more `<M-f>` back to b: `<M-;><M-t>` on b brings back a, b's secondary from before (graduation's copy, Q3): `⦉-⦊ [b] ⟦a⟧`; again, `⦉-⦊ [b] ⟦c⟧` **[sim `rt_sec_round_older`, variant `rt_c3kga`]**.
- T179 [target] (D8) The same round trip by plain navigation: `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e b`, `:e d`, then `<M-;><M-t>` on d says "No secondary relationship found". With D8's notes written the way `<M-f>` writes them today, it throws **[sim `rt_cand_round_e`, variants `rt_base`, `rt_c3kga` and `kt_rewrite_sec`]**. Its message half holds today already, since no notes are written on this route yet, so that sub-case is [char]; the notes half is the target.
- T180 [target] ("Keep the older one") After a round trip, the buffer's older secondary comes back: `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e b`, `:e e`, `<M-f>`, `<M-f>`, `<M-f>` give `⦉b⦊ [d] ⟦e⟧`. d remembers b, its secondary before e: `<M-;><M-t>` on d gives `⦉e⦊ [d] ⟦b⟧` ("Restored secondary slot to … b"), and again `⦉b⦊ [d] ⟦e⟧`. This needs the fallback to compare with the secondary: d's swap note names e, the secondary, so the restore reads d's plain note, b. Today the restore throws **[sim `rt_keep_partner`, variants `rt_c3kga` and `kt_rewrite_sec`]**.
- T181 [target] ("Keep the older one") With nothing older on record, a stale secondary note is dropped: `:e a`, `:e d`, `:e c`, `<M-f>` (d graduates, `dsm{d→a}`), `:e a`, `<M-f>` (to d, whose secondary is now a). d's note naming a is dropped, and `<M-;><M-t>` says "No secondary relationship found". Today it throws **[sim `rt_route_grad`, variants `rt_c3kga` and `kt_rewrite_sec`]**.
- T182 [target] ("Keep the older one") The check on other arrivals, secondary map: `:e a`, `:e c`, `<M-S-f>`, `<M-S-f>`, `:e d`, `<M-f>`, `<M-;><M-f>`, `<M-;><M-r>`, `<M-S-f>`, `<M-;><M-f>`, `:e c`, `<M-;><M-t>` (the primary queue is empty, so `<M-;><M-f>` acts as `<M-f>`). At the last `:e c`, c's plain secondary note names a, the window's secondary, and c has nothing older on record, so the note is dropped and `<M-;><M-t>` says "No secondary relationship found". Today it throws **[sim `rt_resid_nav`, variants `rt_c3kga` and `kt_rewrite_sec`]**.
- T183 [target] ("Keep the older one") A stale secondary note is rewritten to the buffer's swap note when that names another buffer: `:e a`, `:e e`, `<M-f>`, `:e d`, `<M-;><M-f>`, `<M-S-f>`, `<M-;><M-f>`, `<M-f>` give `⦉a⦊ [e] ⟦d⟧`. Cycle to a (the ternary) and `<M-v>`; cycle to d (the secondary) and `<M-v>`: d's note `d>a`, naming the secondary a, becomes d's swap note, `d>e`. Then `<M-f>`, cycle to d and `<M-v>`, and `<M-;><M-t>` gives `⦉a⦊ [d] ⟦e⟧`, again `⦉e⦊ [d] ⟦a⟧`. Where the stale note is dropped instead, both presses say "No secondary relationship found" **[sim `kt_secgain`, variants `kt_rewrite_sec` and `kt_rewrite`]**.
- T184 [target] ("Keep the older one", Q3) With the secondary empty and the ternary b holding an old swap note `dsm[b-swap]` (set it directly: with the decided cleanup, no key seems to empty a secondary once it's set **[inferred]**), `<M-f>` graduates b with `dsm[b] := dtm[b]` and clears `dsm[b-swap]`; `<M-f>` to b then `<M-;><M-t>` brings back `dtm[b]`'s buffer, as Q3 intends **[sim `rt_q3_oldswap`, variant `rt_c3kga`]**.
- T185 [target] ("Keep the older one") Where the ternary stays put, a stale ternary note becomes the ternary's own note: `:e a`, `:e c`, `:e e`, `:e b`, `<M-f>`, `:e c`, `<M-S-f>`, `<M-f>` give `⦉c⦊ [e] ⟦b⟧`, and e's note `e>c`, naming the ternary c, becomes c's own note, `e>a`. `<M-;><M-r>` then gives `⦉a⦊ [e] ⟦b⟧`, and again `⦉c⦊ [e] ⟦b⟧` (flip-flop). Today the restore throws; with navigation's second case taken as worded it still throws; with a drop it says "No ternary relationship found" **[sim `rt_bonus1`, variants `kt_rewrite`, `kt_literal` and `rt_tb`; the same under `kt_rewrite_sec`]**.
- T186 [target] ("Keep the older one") Where the ternary changes, the check acts as navigation's does, and drops when there's nothing older: `:e a`, `:e d`, `:e c`, `<M-;><M-f>` (an empty queue, so d graduates), `<M-f>`, `:e a`, `<M-S-f>` give `⦉a⦊ [d] ⟦c⟧`. d's note `d>a` names the new ternary a, and a has no plain note, so it's dropped: `<M-;><M-r>` says "No ternary relationship found". Today it throws. Coming back by `:e d` instead of `<M-S-f>` gives the same through navigation's own check **[sim `rt_bonus2`, `rt_bonus2_nav`, variant `kt_rewrite`; the same under `kt_rewrite_sec`]**. Its `:e d` route holds today already, through the stale-note check in navigation, so that sub-case is [char]; the `<M-S-f>` route is the target.
- T187 [target] ("Keep the older one") A primary jump uses navigation's second case: `:e a`, `:e b`, `<M-;><M-c>`, `:e e`, `:e a`, `<M-;><M-f>` give `⦉a⦊ [b] ⟦-⟧` with `p=[b]on`, and b's note `b>a`, naming the new ternary a, becomes e, the pre-jump ternary. `<M-;><M-r>` gives `⦉e⦊ [b] ⟦-⟧`, and again `⦉a⦊ [b] ⟦-⟧`. Today the restore throws **[sim, variant `kt_rewrite_sec`]**.
- T188 [target] ("Keep the older one") Where the ternary's own note is the window's secondary, the restore exchanges the ternary and the secondary: `:e a`, `:e b`, `:e e`, `<M-f>`, `<M-f>`, `:e a`, `:e d`, `:e e`, `:e b`, `<M-;><M-t>`, `:e e` give `⦉b⦊ [e] ⟦a⟧` with `dtm{a>b b>a}`. Then `:e a`, plain navigation onto the secondary: Q6's guard rewrites b's note to e, the swap gives `⦉b⦊ [a] ⟦e⟧`, and a's note `a>b`, naming the ternary, becomes the ternary's own note, e, which is the window's secondary. `<M-;><M-r>` gives `⦉e⦊ [a] ⟦b⟧`, and again `⦉b⦊ [a] ⟦e⟧`. This pins the cost that came with "the ternary's own note" (5% of rewrites in the walks). Today the restore throws **[sim, variant `kt_rewrite_sec`]**.
- T189 [target] (Q13) The route the tested fix leaves: `:e a`, `:e b`, `:e c`, `<M-f>`, `<M-f>`, `<M-f>`, `:e a`, `<M-f>` give `⦉c⦊ [b] ⟦a⟧`, with b's ternary note `b>a` and its secondary swap note `b-swap>c`. `<M-;><M-t>` brings back c, which is the ternary, so the two slots exchange: `⦉a⦊ [b] ⟦c⟧`, and b's ternary note now names the ternary. `<M-;><M-r>` must not throw. Today, and under the first tested fix, it throws "Remembered ternary is the same as current ternary" **[sim, variant `kt_rewrite_sec`]**. With the decided check at the exchange, b's note becomes a's own note; a has none, so it's dropped and `<M-;><M-r>` says "No ternary relationship found" **[sim, variant `ex_a`]**.
- T190 [target] I23 as a property test, alongside T154: random walks over `:e` on five files, `<M-f>`, `<M-S-f>`, both restores, cycling picks, `<M-;><M-c>` and `<M-;><M-f>`, in one window and across windows, with `history_view` set to `"global"` and to `"window"`. After every action, for the current buffer and each map, the note a restore would read doesn't name that slot's occupant. In the tested fix's walks it broke at 11 of 75,000 steps, each right after a secondary restore's exchange or carried on from one (T189) **[sim, variant `kt_rewrite_sec`, seeds 7 and 11]**.
- T192 [target] ("Keep the older one") `rename_hash_in_triquetras(old, new)` moves `dsm[old-swap]` to `dsm[new-swap]` and renames values in both maps, as it already does for `dtm[old-swap]` (`window/data.lua:142-145`). Set it up directly, or with a No Name buffer that holds both kinds of secondary note, closed and then reopened by `<M-f>` **[code]**.
- T193 [target] (D9) The missing-file rule on the secondary map: `:e f`, `:e b`, `<M-f>` (f graduates), `<M-f>` (to f), `:e e`, `<M-f>` (to b) give `⦉f⦊ [b] ⟦e⟧` with `dsm{b-swap>f b>f}`. After `:bdelete f` and deleting f.txt on disk, `<M-;><M-t>` on b says the file is missing, changes no slot, and keeps both notes, as T174 does on the ternary map. With today's missing-file branch it clears `b>f` and then stops on `b-swap>f` at every press **[sim `rt_sec_missing`, variant `rt_c3kga`]**.

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
- T196 [char] (P18) While cycling, with the window back on its current slot, `<M-f>` and `<M-;><M-r>` do their normal job, notes included: set up with `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d`, `:e c` (`⦉d⦊ [c] ⟦b⟧`, with b's note `b>a`), then `<M-n>` and a first `<M-f>` that only takes the window back to c, a second `<M-f>` gives `⦉d⦊ [b] ⟦c⟧` with the secondary note `c>b` (the swap note `c-swap>b` once T191 lands), and `<M-;><M-r>` then gives `⦉a⦊ [b] ⟦c⟧`; navigation stays `cycling` throughout **[run `t/pkB_cycle_keys.lua`]**.
- T175 [target] (A12) Cycling in win1, then `<C-w>p` to win2: win1 shows its start again, navigation is `normal`, history is attached, and nothing was recorded for the cycled-to buffer. Then `:e d` in win2 moves win2's slots and records d.
- T176 [target] (D11) With an empty secondary and no ternary, `<M-f>` fills from the ordered list's second entry, and throws if the first entry isn't the window's current buffer.
- T197 [target] (D11) Under `history_view = "window"`, after `:e a`, `:e b`, `:vsplit`, `<C-w>p`, `:e c`, `:vsplit`, the ordered list's first entry is the window's current buffer on every run (no tie), and `<M-f>` doesn't trip the fill assertion.
- T198 [target] (A12) `:e a`, `:vsplit`, `:e c`, `<M-m>`, `<C-w>p`: the cycle in the second window is cancelled (it's back on c), the landing in the first window is recorded (the ordered list starts with a), and `<M-f>` there fills c without tripping the fill assertion.
- T199 [target] (A26) With no assertion, the recorder writes no file and opens no buffer, and the ring never holds more than N steps.
- T200 [target] (A26) When the restore assertion fires, a file appears under `stdpath("state")/cavediver/` and a scratch buffer opens, both holding the last steps as rows: action or event, window, `⦉t⦊ [c] ⟦s⟧` and notes, ending at the failing step.
- T201 [target] (A26) A dumped file replays in the sandbox to the same assertion.
- T202 [target] (A26) A dump starts with a snapshot of the state at the ring's first step; replaying snapshot plus steps reproduces every row.
- T203 [target] (A26) A planted rule break dumps at the next step: with c current in one window and b its ternary, c's ternary note is set to b by hand, and a step in the other window (`:e x`) produces one dump. The break is planted because every real route into one is a route the decided fixes remove; the slot exchange, the first route used here, stops breaking the rule once its fix lands (the author, 2026-10-21: "plant the break instead of %1").
- T204 [target] (A26) A session load and a cleanup re-point appear in the dump as steps tagged `load` and `timer`.
- T205 [target] (A26) A failure that repeats (a highlight callback throwing on every redraw) gives one dump, and the dump window is neither recorded nor tracked: its buffer is `nofile` and unlisted, with no hash, no triquetra and no place in the bufferline, and after a visit to its window, a second, different failure (a hook bound by hand to fail) dumps steps that never name that window or its buffer.
- T333 [target] (A26) A dump opens its scratch buffer only once the editor settles, and names files by alias and basename, never by full path: on T200's route, no buffer is added inside the failing call, the scratch buffer is there once it settles, and neither it nor the file holds the project's directory, while both name `c.txt`. The single assertion helper is checked by what it does: every "shouldn't happen", the hook-failure catch included, dumps (T275).
- T206 [target] (I23) `:e a`, `:e e`, `:e d`, `<M-S-f>`, `:e b`, `:e d`, `<M-n> <M-v>`, `<M-f>`, `:e b`, `<M-f>`, `:e e`, `<M-m> <M-m> <M-v>`, `<M-;><M-t>`: b's stale note becomes e's own note, d; `<M-;><M-r>` gives `⦉d⦊ [b] ⟦a⟧`, and again `⦉e⦊ [b] ⟦a⟧`.
- T171 [target] (A12) With no cokeline installed, `<M-n>` and `<M-m>` step through cavediver's ordered history in the same directions as with cokeline, and `<M-v>` picks as usual. Today the step only prints and navigation stays in `cycling` **[run s21]**.
- T79 [char] Through the real cokeline order, `<M-n>` steps left, toward newer buffers, and `<M-m>` steps right, toward older ones (Q19).
- T152 [target] Q6 on a cycling pick of the secondary: with `{c=A s=S t=T}` and `dtm[T] = S`, cycling to S and pressing `<M-v>` gives `{c=S s=A t=T}` and rewrites `dtm[T]` to A. Today it warns "Avoided conflict…" and `dtm[T]` stays S **[inferred]**.
- T172 [target] (Q9) `:e a`, `:e b`, `<M-S-f>` (b gets `dtm[b-swap]=a`), `:e c`, `:e d`, `:e e`, cycle to b, `<M-v>`: `dtm[b] = e` and no `dtm[b-swap]`; `<M-;><M-r>` gives `t=e`, again `t=d`, again `t=e`.
- T155 [target] `{c=e s=c t=d}` with no `dtm[b-swap]`: cycle to b, `<M-v>` → `{c=b s=c t=d}` and `dtm[b] = e`. Then `<M-;><M-r>` brings the start back: `{c=b s=c t=e}`, with `dtm{b→d}` by the flip-flop (Q9).

**Closing and reopening (A15, A16)**
- T80 [char] With order `f,e,d`, `<M-.>` on f lands on e, pushes f on the closed stack, and leaves f in the ternary as a closed hash.
- T81 [char] On entry i > 1 it lands on i + 1, and on the oldest it lands on the newest.
- T82 [char] It refuses with a modified named buffer, a buffer shown in two windows, or a single entry, each with its warning and nothing changed.
- T83 [target] On a modified No Name buffer it closes it and caches its lines, filetype and cursor. Today the cursor comes back as `{1,0}`: `delete_buffer` switches the window away before the wipe (bug, found 2026-10-21; the author: "Bug: keep the cursor").
- T84 [target] In `:help` it doesn't throw. What it does instead is T164–T167 (Q17).
- T85 [target] `<M-.>` on a file keeps the buffer's marks for when it's reopened (`:bdelete`).
- T86 [char] `<M-S-w>` reopens the newest closed buffer, and it becomes current with the old current in the ternary.
- T87 [char] `<M-S-w>` with an empty stack warns "No closed buffers to reopen."
- T88 [char] A No Name buffer closed with text comes back with the same lines and filetype.
- T89 [target] `<M-S-w>` on a missing file says so and leaves the entry on the stack.
- T90 [target] A reopened No Name buffer gets its cursor in its own window, with no "Invalid cursor line".
- T91 [target] After a No Name buffer is reopened, every slot and map entry that held its old hash holds the new one.
- T162 [target] (Q15) I22: pushing a hash that's already on the closed stack (for example, `track_closing_filehash_force` twice) leaves it on the stack once, as the newest entry. With pools: closing `notes.md` in two tabs' pools and merging both entries leaves one, the newer.
- T164 [target] Q17, a visiting window: in a window with `{c=a s=b}` that's visiting an untracked buffer (a `nofile` scratch, or help shown with `:buffer`), `<M-.>` closes the visited buffer, and the window shows a with `{c=a s=b}` intact. It needs the visiting rule (T27).
- T165 [target] Q17, a window born untracked: `:e a`, `:help`, then `<M-.>` in the help window. The help buffer is closed, Neovim closes the help window, nothing throws, and a's window and triquetra are unchanged.
- T166 [target] Q17, the only window: `:help`, `:only`, `<M-.>`. The help buffer is closed, nothing throws, and the window shows what Neovim picks.
- T167 [target] Q17, a running terminal: `<M-.>` on a `:terminal` whose job is still running refuses with a message, and the terminal stays.

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
- T107 [target] After a rename whose old file no longer exists, every reference to the old hash follows to the new one, and nothing is pushed on the closed stack.
- T108 [char] When a window shows registered buffer X while its current slot's buffer is gone, cleanup sets `c := X`.
- T109 [char] `:e brandnew.txt`, type a line, `:e a.txt`: the brandnew buffer still exists with its text and stays tracked (I12).
- T110 [char] A file deleted on disk while shown stays shown and tracked after a 4.6 s wait.
- T111 [char] `:bdelete` of the shown buffer lands that window, not the focused one, on ternary → secondary → primary → most recent.
- T112 [char] Opening a closed file again with `:e` takes it off the closed stack (`track_buffer`).
- T113 [char] A stale registration with a copy reloaded under `noautocmd` re-points to the copy and wipes nothing.
- T114 [target] A closed entry whose file is gone from disk stays on the stack.
- T163 [target] When cleanup re-points a window's current slot to the registered buffer X the window shows (A21 step 1), with X outside the slots, `{c=A s=S t=T}` becomes `{c=X s=S t=A}`, as plain navigation would. Today it's `{c=X s=S t=T}`. Set it up by showing X without a `BufEnter` (`noautocmd`) after A's buffer is gone (Q18).

**UI (M12)**
- T115 [char] For `{c=e s=c t=d}`, the winbar holds these pieces in order (seen in run s14): `%#WinbarBufnrTernary#⦉<d>⦊ `, then `%#WinbarBufnrCurrent#[<e>] `, then `%#WinbarFilenameCurrent#e.txt`, then `%#WinbarBufnrSecondary#⟦<c>⟧ `, then `%#WinbarFilenameSecondary#c.txt`. `<x>` stands for the buffer number of x.
- T116 [char] A closed ternary is shown as `⦉ … name ⦊` with no buffer number.
- T117 [char] When the current buffer is the primary, it's shown as `⦉N⦊` in `WinbarBufnrPrimary`.
- T118 [target] A slot closed with `:bdelete` shows its basename, not its full path.
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
- T125 [target] `setup()` with no argument works and uses the defaults.
- T126 [target] `require('cavediver')` without `setup()` creates no autocmds.
- T127 [target] Calling `setup()` twice leaves one set of autocmds and timers.

**Invariants**

These are property tests over random action sequences, like the desk's fuzzing:
- T128 [target] I1: no duplicate among a triquetra's current, secondary and ternary.
- T129 [target] I2: every hash referenced anywhere has a path.
- T130 [target] I3: every triquetra has a history entry.
- T131 [char] I12: no buffer with unsaved changes is ever wiped by cavediver. Wrap `vim.cmd` and `nvim_buf_delete`.
- T132 [char] I13: a slot action switches only the target window's buffer.
- T133 [char] I11: `ordered.crux` is sorted, newest first, and holds only registered open buffers after any non-cycling action.
- T154 [target] No restore throws: `<M-;><M-r>` and `<M-;><M-t>` never throw "Remembered … is the same as current …" (Q13). Random walks with Q6's fix still found the ternary restore throwing 13 times in 1,500; those routes were traced to arrivals that skip the stale-note check in navigation, and with "Keep the older one" on both maps the walks found none **[sim, variant `kt_rewrite_sec`]**. One constructed route still throws (T189).
- T157 [target] (Q14) I19, A9: on an empty queue that's switched on, one `<M-;><M-x>` gives `p=[A]on`. Today it gives `p=[A]off` **[run s19]**. The test sets the empty, switched-on state directly: s19's route, deleting the open primary's file on disk, keeps the primary in the queue (A21) **[inferred]**.

**Sessions (S1, S2)**

Every one of these runs in a fresh process (see the appendix).
- T134 [today] `save_session(cwd)` writes the keys `buffers`, `windows`, `closed` and `noname_content`, with `windows[i] = [c, s, p[], t, dtm, dsm]`.
- T135 [char] A round trip with every slot buffer restored and loaded gives back the same slots and maps.
- T136 [target] `primary_enabled = false` survives a round trip.
- T137 [today] `load_session` after a `save_session` in the same process throws "Transition 'idle->loading' is not registered". Paired with T138.
- T138 [target] `load_session` from `idle` tears down and loads.
- T139 [target] A slot whose buffer comes back unloaded (`badd`) keeps its value after load.
- T140 [target] A save with a No Name current slot succeeds and reopens the buffer at load, hidden and modified.
- T141 [target] A save with a `:vsplit` window that has no visits succeeds.
- T142 [target] Two windows, one showing a No Name buffer: after save and load each window gets its own entry.
- T143 [target] A save into a read-only directory throws to the caller.
- T144 [target] A file that fails the integrity check gives the notification and a fresh start.
- T145 [target] Three `load_session` calls in one batch load once.
- T146 [target] A save never wipes a buffer or changes what a window shows, an oil window included. Its no-wipe half holds today and has its own [char] case; the oil half, a save leaving an oil window on its oil buffer, waits for the session core (step 4).
- T147 [char] With no file, a load gives every window `{c=<shown>}` and an empty closed stack.
- T148 [target] After switching sessions, the outgoing No Name text isn't in the incoming file.

**Doc checks**

The settled doc and comment changes, which a test can't hold. Each is checked by reading the file once the change is made.
- README: the two primary keys at README:319-320 the right way round (D1); the defaults block copies `configs.lua`, missing keys included, and `cleanup_interval` says milliseconds (D2); README:31 says a disabled primary makes `<M-;><M-f>` act like `<M-f>` (D5); README:28 says a pop-up save keeps the good lines and reports the bad ones (D6); README:332's middle sentence and "tiquetra" (D26); README:44-47's requirements and the lazy.nvim `dependencies` (D4, D27); README.md:109-111, the cokeline paragraph (D27); README:67-105, "Session manager setup" (D28).
- Keymap and annotation text: `cycle_select`'s annotation at `configs.lua:10` copies "Select cycling buffer and attach history" (D3); the descriptions themselves are T156, T161 and T169.
- Comments and docstrings: the checkpoint docstring at `history/routines.lua:371-374` (D15); the `<M-.>` branch comment at `history/routines.lua:588` (D16); `navigation/data.lua:9`, one jump table across all tabs (D17); the saved-entry annotation at `storage/routines.lua:12-20`, six fields (D18); `navigation/states.lua:8`, nothing enters `file_picker` yet (D21); the closed-stack comments at `history/data.lua:81` and `history/init.lua:92-94`, and the loop state annotation at `ui/states.lua:18-19` (D25); the header at `init.lua:4` and the XOR docstrings at `storage/routines.lua:58`, `:61`, `:85`, `:86`, in build step 5 (D29).
- The engine (Q20): the class declares the shared `transition_modes` table, the factory comment at `engine/init.lua:18` stops implying modes are per machine, and the per-machine wording at `helpers.lua:258` and `:276` is reworded or dropped.
- `ui/routines.lua:374`: the meaningless 30 in `math.max(#ordered, 30)` goes (Q5).
- The old spec: SPEC:906-909 is marked as not built (D21).
- The desk, at its next sync: DESK.md:2126 and the Dropped line at DESK.md:3146 narrowed to the cokeline fallback (A12); the bug entry at DESK.md:2446 and its repro at DESK.md:3250 gain the faster trigger (D14).

**Negative cases (T207–T249)**

Each checks that something doesn't happen, or that a bad or impossible action is refused or handled without harm, and cites the claim it comes from.
- T207 [char] (P5) A `nofile` scratch entered in a tracked window isn't registered (M3). Help, terminal, `scheme://` and otter buffers are T10; the quickfix list, which gets in today, is T217.
- T208 [target] (P10, I17) Notes follow along: `:e a`, `:e b`, `:e c`, `:enew` (an empty No Name N), `:e b`, `:e d` leave N only in the notes (`N>c`, `b>N`). After `:bwipeout` of N, which forgets its path and pushes nothing (M5), no note names N. Today both notes stay (M7: the maps are never pruned).
- T209 [char] (P14) The secondary changes only when you act: from `⦉-⦊ [c] ⟦b⟧` (`:e a`, `:e b`, `:e c`, `<M-f>`), `:e d`, `:e e`, `:e a`, two cycle steps, `<M-;><M-f>` and `<M-v>` on the start, then `:vsplit` and `<C-w>p` back, leave the secondary on b: `⦉e⦊ [a] ⟦b⟧`.
- T210 [char] (P17) Every window is independent: with window 1 on `⦉c⦊ [d] ⟦b⟧` and `p=[d]on`, `:vsplit`, then `:e e`, `:e a`, `<M-f>`, `<M-f>`, `<M-S-f>`, `:e b`, `<M-;><M-c>`, `<M-;><M-r>` in window 2 leave window 1's slots, notes and primary queue as they were, and so does `<C-w>p` back into it.
- T211 [char] (P20) Restoring is only ever explicit: at `⦉-⦊ [c] ⟦d⟧` (`:e a`, `:e b`, `:e c`, `:e d`, `:e c`, `<M-f>`) with c's note `c>b`, a wait leaves the ternary empty, `<M-S-f>` says "No ternary buffer to swap with." and changes nothing, and only `<M-;><M-r>` brings b back: `⦉b⦊ [c] ⟦d⟧`.
- T212 [target] (P22, S2) The session file is written with mode 0600 whatever the umask: `rw-------` with a umask of 022. Today `writefile` follows the umask and gives `rw-r--r--` (S1).
- T213 [char] (P24, M6) A save with a No Name current slot leaves the live triquetra, the notes, the primary queue, the closed stack and the history order as they were: the substitution only changes what's written to the file.
- T214 [target] (P24, A22) A save leaves the closed stack as it was: with b closed and outside the slots, deleting b.txt and saving straight away keeps b on the stack. Today the save's `cleanup_system` drops it (S1 save step 1, A22 step 3).
- T215 [target] (P26) With harpoon not installed, `:e`, `<M-f>`, `<M-S-f>`, `<M-;><M-c>`, `<M-;><M-r>` and the UI ticks raise nothing and report no hook failure. Today every history update fails at `history/routines.lua:336` with "module 'harpoon' not found".
- T216 [target] (I16) A No Name id isn't reused across sessions: two fresh processes that each run `:e a`, `:enew` get the same buffer number and different ids. Today both are `NONAME_<bufnr>`, so the hashes are equal.
- T217 [target] (I10, A1, A2) A buffer that turns into something untracked isn't left registered or in a slot. Two routes: a buffer entered as `buftype ""` and then set to `nofile`, as a plugin's scratch is, followed by `:e b`; and `:copen`, which enters its buffer before it's a quickfix buffer (DESK:2453), so its window gets no triquetra either. Today both stay registered, the first in the ternary and the second as the quickfix window's current slot.
- T218 [target] (I18) A repeated file in the primary queue window is refused loudly: from `[b,a]on`, the lines `a`, `b`, `a` save `[a,b]` and report the repeat at error level, like a typo'd path under Q11's partial save. Today `[a,b,a]`: `update_primary_buffer` doesn't dedupe. Decided 2026-10-21 (the author: "Refuse loudly").
- T219 [char] (I19, Q14) An empty queue that's switched on stays on: from `p=[]on`, `:e c`, `<M-f>`, `<M-;><M-f>`, `:e a`, `<M-S-f>` and the UI ticks leave `p=[]on`.
- T220 [target] (M11, D23) The winbar and indicator toggles work at runtime: `hide_winbar()` empties the winbar and it stays empty through the refresh, `show_winbar()` brings it back, and `hide_indicators()`/`show_indicators()` switch the indicators off and on. Today the winbar machine doesn't exist and the indicator transitions aren't registered, so each throws; nothing calls them, and a `:set winbar=` by hand is written back within a tick (`ui/routines.lua:551`) **[run 2026-10-21]**. Decided 2026-10-21: build them (the author: "Build them"); how they're exposed, key or command, is decided later. The bufferline pair is T123.
- T221 [target] (M11) `unregister_hook(name)` removes that hook from its own machine and nothing else, without throwing, and the name can be bound again. Today it calls the class instead of the instance (`state-machine.lua:382`), throws, and the hook still runs.
- T222 [target] (M1, D4) Hashing a file name runs no shell: `:e a` and `:e b` make no `vim.fn.system`, `io.popen` or `vim.system` call. Today each hash shells out to `sha256sum`.
- T223 [char] (A1, A3) Going back into a window onto its current slot changes nothing: with window 1 on `⦉c⦊ [d] ⟦b⟧` and window 2 on `⦉d⦊ [e] ⟦-⟧`, `<C-w>p` three times leaves both windows' slots and notes as they were (A1's row X = A).
- T224 [char] (A1) A visit made in another window lands in that window, never the focused one: with window 1 focused on `⦉a⦊ [b] ⟦-⟧`, `:edit d.txt` run in window 2 through `win_execute` gives window 2 `⦉c⦊ [d] ⟦-⟧`, and window 1 keeps the focus, its buffer and its slots **[code]**. The history half is T19.
- T225 [char] (A2, M6) Windows born untracked never get a triquetra: a `:help` window and a `:split | terminal` window have none, after UI ticks and a jump out and back in. `:copen` gets one today, through I10's route (T217).
- T226 [char] (A6, A7, A8) With no triquetra (a `:help` window), `<M-f>`, `<M-S-f>` and `<M-;><M-f>` each warn "Window with unregistered buffer.", raise nothing, switch nothing, and leave the other window's slots alone.
- T227 [target] (A7, P9) `<M-S-f>` on a closed ternary whose file is gone from disk says so and keeps the pointer: `:e a`, `:e b`, `:e c`, `:bdelete b.txt`, then b.txt deleted and `<M-S-f>` pressed straight away give a warning, no throw, and `⦉b⦊ [c] ⟦-⟧`. Today "Removed ternary file not found in filesystem" and `t := nil`.
- T228 [char] (A11, D9) A restore switches no buffer and reopens nothing: at `⦉d⦊ [b] ⟦-⟧` with `dtm{b>a}` and a closed with `:bdelete`, `<M-;><M-r>` gives `⦉a⦊ [b] ⟦-⟧`, still showing b, with a unloaded and still on the closed stack; `<M-S-f>` then reopens a and takes it off the stack (a closed hash reopens when used).
- T229 [target] (A12) Any jump into another window cancels the cycle, floats and `:help` included: cycling from c with `⦉b⦊ [c] ⟦-⟧` to b, then a jump into a float, or `:help`, puts the window back on c with navigation `normal`, history attached, and the slots and the history order unchanged. Today the cycle leaks into the new window.
- T230 [char] (A13) A pick writes no secondary notes, as today: from `⦉d⦊ [e] ⟦c⟧`, a pick of b (outside the slots) and then a pick of the ternary leave the secondary map as it was. The pick of the secondary is T73.
- T231 [char] (A14, Q7) `<M-;><M-f>` while cycling with the window already on the start says "Returned to cycling origin buffer" each time and changes nothing: the slots, the notes, the shown buffer and the order stay, and navigation stays `cycling`.
- T232 [target] (A17) `<M-,>` skips a previous window whose filetype is `neominimap`, as it does `minimap` (T94): it warns "No valid previous window to toggle to." and stays.
- T233 [char] (A18) With no triquetra (a `:help` window, while the other window's queue is `[a]on`), `<M-;>F` says "No triquetra found for current window." and opens no window.
- T234 [char] (A18, Q11) The pop-up refuses what cavediver doesn't track and keeps the good lines: from `[b,a]on`, the lines `a`, a blank line, the path of a loaded help file, `NONAME_999` and `b` save `[a,b]on`, with one error naming the help file and `NONAME_999`; the blank line is dropped without a word.
- T235 [target] (A18) A relative path in the primary queue window is resolved against the current directory, as `:e` does: the lines `./b.txt`, `a` save `[b,a]`, with no hole, and the pop-up redraws them as `b.txt`, `a.txt`. Today the line passes validation as typed, then its hash is looked up by the typed string, finds nothing, and leaves slot 1 empty, so the primary is lost and every loop over the queue sees it as empty (`window/routines.lua:74`; DESK:2477) **[run 2026-10-21]**. Decided 2026-10-21 (the author: "I thought we can type relative paths. In fact it's easier to type relative paths right?", then "Resolve it"). The pop-up keeps showing each entry by its shortest unique name, `b.txt`, or `src/b.txt` when another `b.txt` exists (the author, 2026-10-21: "Shortest name (today)").
- T236 [target] (A5) Closing another window first doesn't stop the pop-up's buffer going when the pop-up closes: `:vsplit`, `:close`, then `<M-;>F` and `:close` in the pop-up delete its buffer, as they do when no window was closed first. Today the first close uses up the `once` handler (`ui/hooks.lua:113`). And `<M-;>F` opens the pop-up again afterwards: today the left-over buffer keeps its name, and the next `<M-;>F` fails with "E95: Buffer with this name already exists" (`ui/routines.lua:66`); `q` and `<C-c>` don't hit this, since `close_window` deletes the buffer itself **[run 2026-10-21]**. Kept as a fix test, with the reopen check added (the author, 2026-10-21: "Keep + add reopen").
- T237 [char] (A19) With nothing left to land on, the window keeps Neovim's empty buffer and no `:enew` runs: `:e a`, `:bdelete a.txt` leave the window on the buffer Neovim put there, with no buffer added. It holds today already (found 2026-10-21), so it's [char]: a guard that stays true when the decided code lands.
- T238 [target] (A20) `:w new.txt` on a No Name buffer with text leaves no ghost entry on the closed stack: the old name isn't a file, so it's a move. Today the old `NONAME_` hash is pushed (DESK:2455). Its notes follow too (the decided move, DESK:1924): a No Name buffer whose note says its ternary was a gives `new>a` after `:w new.txt`, with no dangling hash. Today the closed stack gets `NONAME_2`, `<M-S-w>` reopens it as a new No Name buffer holding a second copy of the saved text, and the note dangles as `?274b55>a` **[run 2026-10-21]**. Kept as a fix test, with the notes check added (the author, 2026-10-21: "Keep + notes follow").
- T239 [char] (A21) A slot pointing at an open buffer is kept whatever the disk says: at `⦉c⦊ [d] ⟦b⟧`, deleting b.txt and c.txt (both still open), UI ticks and a `cleanup_system` pass leave the slots and both registrations as they were.
- T240 [target] (A25) `disable()` clears the `cavediver` augroup and stops the timers, and afterwards `:e c` changes no slot and records nothing. Today there's no `disable`.
- T241 [target] (A26) The recorder never records raw keystrokes: text typed in insert mode (`QZQZQZ`) before the restore assertion fires doesn't show up as steps in the dump, whatever its format, file or scratch buffer.
- T242 [target] (bug (new), 2026-10-21) A tracked buffer wiped with `noautocmd` doesn't make the UI loop error: `:e a`, `:e b`, `:e c`, then `noautocmd bwipeout` of c give no hook failure over the next ticks. Today "Invalid buffer id" on every tick (`ui/routines.lua:488`). Wiping the ternary, or a buffer outside the slots, this way gives no error today. **Decided (2026-10-21): the UI repairs it on the spot** (the author: "Keep, UI repairs now"): when a refresh finds a window showing a different buffer from its current slot, it re-points as cleanup would, like navigation (Q18), so within one refresh the window above reads `⦉c⦊ [b] ⟦-⟧` and nothing errors. Today about 13 error notifications arrive over the ~4 s until the cleanup tick repairs it **[run 2026-10-21]**.
- T243 [target] (I23) The check runs wherever a slot changes under the current buffer (decided 2026-10-21), with the stale note planted: at graduation (`⦉b⦊ [c] ⟦-⟧` with `dsm{c>b}`, `<M-f>`), at the history fill (a fresh split on b with `dsm{b>a}`, `<M-f>` fills a), and at a session load (`⦉-⦊ [c] ⟦b⟧` with `dsm{c>b}`, saved and loaded). After each, the current buffer's note doesn't name its slot's occupant, and `<M-;><M-t>` doesn't throw.
- T244 [target] (S2) A load into fewer windows than were saved matches by what they show and drops the unmatched entry, with no error: two windows saved (`⦉c⦊ [d] ⟦-⟧` in the split, `⦉a⦊ [b] ⟦-⟧`) and one restored on b give `⦉a⦊ [b] ⟦-⟧`. Today "table index is nil" (`history/routines.lua:144`).
- T245 [target] (S2) A session file with a newer header gives "made by a newer cavediver" and is left alone: a file starting `CDV9` is unchanged after the load. Today the load is a silent fresh start.
- T246 [char] (S2) A No Name buffer closed with `<M-.>` stays on the closed stack across a save and a load, and `<M-S-w>` then brings its text back. It holds today already (found 2026-10-21), so it's [char]: a guard that stays true when the decided code lands.
- T247 [char] (I13, A21) A cleanup heal in another window doesn't switch the focused window or wipe what that window shows: window 2 on `⦉x⦊ [c] ⟦-⟧` shows an `acwrite` buffer, and `:bdelete c.txt` from window 1 leaves window 1 focused on b and window 2 on its buffer.
- T248 [char] (A12) With no cokeline, a cycle step raises nothing and `<M-v>` still ends the cycle: navigation `normal`, history attached, the slots unchanged **[run s21]**.
- T249 [char] (A1, A11) No note names its own buffer: random walks with T190's mix, in one window and across windows, check after every action that no map holds `X>X` or `X-swap>X`. The decided check drops a stale note when the note it would copy names the current buffer (A11), and runs after Q6's guard so two notes naming each other can't leave one behind (A1). It holds today already (found 2026-10-21), so it's [char]: a guard that stays true when the decided code lands.

**Decided rules not covered elsewhere (T250–T291)**

Each checks a rule the spec states as intended or decided that no earlier test checks, found by an audit of the tests against the spec (2026-10-21), and cites the rule. Where a state is set by hand, the test says so; where it reads a format the spec gives only as an example, it matches loosely.
- T250 [target] (P2, A1) The slotting happens after the event, not inside it: with `⦉-⦊ [a] ⟦-⟧`, a `BufEnter` autocmd of the user's, made after `setup()`, still sees `⦉-⦊ [a] ⟦-⟧` while `:e b` runs, and the window has `⦉a⦊ [b] ⟦-⟧` once the editor settles. Today the slots move inside the event. Its purpose is tested too, as a [char] sub-case that holds today: a buffer that only becomes a terminal or help after its `BufEnter` (`:terminal`, `:help`) is never registered or slotted as a file. The author asked for both checks, 2026-10-21: "Both".
- T251 [target] (P3) The load matches windows by what they show, not by position: two windows saved (`⦉c⦊ [d] ⟦-⟧` in the split, listed first, and `⦉a⦊ [b] ⟦-⟧`) and restored the other way round (the first-listed window on b) give the window on b `⦉a⦊ [b] ⟦-⟧` and the window on d `⦉c⦊ [d] ⟦-⟧`. Today each window takes the entry at its position.
- T252 [target] (P10, I17) History follows along and doesn't let go early: `:e a`, `:e b`, `:e c`, `:bdelete b.txt` leave b on the closed stack, still known, and its global history entry stays. Today the entry goes as soon as b is unregistered. "Known" means cavediver still remembers the file (registered, e.g. on the closed stack), not that it's open; confirmed by the author, 2026-10-21: "Forgotten (as read)". The entry never reaches the bufferline: cokeline draws from listed buffers, and the ordered list skips hashes with no open buffer (`history/routines.lua:313-317`) **[run 2026-10-21]**.
- T253 [target] (P11) A bug inside a hook is caught with a stack trace: a hook that throws is reported as "Hook '<name>' failed…" together with a stack traceback. Today the message has only the error. The traceback is in the notification itself (confirmed by the author, 2026-10-21: "In the notification").
- T254 [target] (P12, A25) Nothing runs at `require`, and `setup()` makes everything inside the `cavediver` augroup: `require('cavediver')` alone creates no `Cavediver*` user command and starts no timer, and every autocmd `setup()` creates is in the `cavediver` augroup, with the commands made. Today the eight commands and the 200 ms probe come at require, and no autocmd has a group.
- T255 [target] (M1) The session file is named `sha256(directory .. "\n" .. name)`: `save_session('work')` writes a file in `session_dir` whose name starts with `vim.fn.sha256(getcwd(-1, -1) .. "\n" .. 'work')`; and a session `a` saved in `/proj` and a nameless save in `/proja` are two files. Without the separator both would hash `"/proja"` and share a file. Decided 2026-10-21 (the author: "With a separator"). Today the name is the shell sha256 of the argument, taken as the directory.
- T256 [target] (M3) A listed `nowrite` buffer on an existing regular file is tracked: after `:e a`, entering such a buffer on c.txt registers it and gives `⦉a⦊ [c] ⟦-⟧`. Today it isn't registered and the window loses its triquetra.
- T257 [char] (M7) The secondary map's swap notes are stored with the rest of the map: at `⦉-⦊ [c] ⟦b⟧` (`:e a`, `:e b`, `:e c`, `<M-f>`) with `b-swap>c` set by hand on dsm, a save and a load in a fresh process give back `dtm{b>a} dsm{b-swap>c b>a}`. It holds today already, so it's [char]: a guard that stays true when the decided code lands.
- T258 [char] (M8, Q16) The primary may share a slot's buffer: with `p=[a]on`, `:e b` puts a in the ternary, `<M-f>` in the secondary and `<M-f>` again in the current slot; the queue stays `[a]on` throughout and over the UI ticks, and nothing reports an error.
- T259 [target] (M7, A6, A8) The `<M-;><M-f>` fallback onto the secondary writes the same notes as `<M-f>`: from `⦉c⦊ [d] ⟦b⟧` with an empty queue, `<M-;><M-f>` gives `⦉c⦊ [b] ⟦d⟧` with `dsm{d-swap>b}`, `dtm{d-swap>c}` and no plain secondary note for d (T191's notes). Today `dsm{d>b}`.
- T260 [target] (A1, A13) The check on a pick of the ternary: T186's keys up to `⦉d⦊ [a] ⟦c⟧` (d's note `d>a`), then cycle to d and `<M-v>`, give `⦉a⦊ [d] ⟦c⟧`; d's note names the new ternary a, which has no plain note, so it's dropped and `<M-;><M-r>` says "No ternary relationship found". Today the note stays and the restore throws.
- T261 [target] (A1, A8) The check on a primary jump onto the ternary: `:e a`, `:e d`, `<M-;><M-c>`, `:e c`, `<M-f>`, `<M-f>`, `:e a` give `⦉d⦊ [a] ⟦c⟧` with `p=[d]on` and d's note `d>a`; `<M-;><M-f>` gives `⦉a⦊ [d] ⟦c⟧`, d's stale note becomes a's own note, none, so it's dropped, and `<M-;><M-r>` says "No ternary relationship found". Today the restore throws.
- T262 [target] (A1, A13) The check on a pick of the secondary: T185's keys up to `⦉c⦊ [b] ⟦e⟧` (e's note `e>c`), then cycle to e and `<M-v>`, give `⦉c⦊ [e] ⟦b⟧`; the ternary c stays put, so e's note becomes c's own note, `e>a`. `<M-;><M-r>` gives `⦉a⦊ [e] ⟦b⟧`, and again `⦉c⦊ [e] ⟦b⟧`. Today the restore throws.
- T263 [target] (A7, A8, M7) The secondary map's check runs on `<M-S-f>` and on a primary jump, with the stale note planted. At `⦉c⦊ [d] ⟦b⟧` with `c>b` set on dsm, `<M-S-f>` gives `⦉d⦊ [c] ⟦b⟧`; with `p=[x]on` and `x>b` set on dsm, `<M-;><M-f>` gives `⦉d⦊ [x] ⟦b⟧`. In both the note names the secondary and there's no swap note, so it's dropped (I23 holds) and `<M-;><M-t>` says "No secondary relationship found". Today the note stays and the restore throws.
- T264 [target] (A11, I23) The ternary restore's exchange is followed by the secondary map's check: at T62's `⦉c⦊ [b] ⟦a⟧` with `b>c` set on dsm, `<M-;><M-r>` exchanges to `⦉a⦊ [b] ⟦c⟧`; b's secondary note now names the secondary, so it's rewritten or dropped (I23 holds), and `<M-;><M-t>` doesn't throw. Today it throws.
- T265 [target] (A11, final section) At the secondary restore's exchange the stale ternary note is dropped when the ternary's own note would name the current buffer: at `⦉c⦊ [d] ⟦b⟧` with `d>c` on dsm and `d>b`, `b>d` on dtm (set by hand), `<M-;><M-t>` exchanges to `⦉b⦊ [d] ⟦c⟧`, d's ternary note is dropped, and `<M-;><M-r>` says "No ternary relationship found". Today the restore throws.
- T266 [target] (A11, D9) A note at a file deleted on disk whose buffer is still open flip-flops and says the file isn't on disk: T173's keys and checks, and each press that brings f back gives a message besides "Restored ternary slot to…". Today the restore stops with "not found in filesystem anymore". The message is locked (the author, 2026-10-21: "(a) one WARN line"): `Restored ternary slot to: <hash> (<name>), not on disk right now` at WARN, and the same with "secondary" for the secondary restore.
- T267 [target] (A11, D9) A note at a hash with no path is cleared when it's used: T68's state, and after `<M-;><M-r>` no note holds the unknown hash. Today the restore throws "This impossible error should never happen".
- T268 [target] (A2) The winbar shows a visit, like `main.lua ← [help]`: help shown in a's own window gives a winbar that reads, with highlights left out, `a.txt`, then `←`, then `[help]`. The spec gives the format only as an example, so the pieces are matched in order. Today the triquetra is dropped and the winbar is empty. The format is locked (the author, 2026-10-21: "(a) within the winbar"): the current slot's piece becomes `[<bufnr>] <name> ← [<type>]`, with the ternary and secondary pieces kept around it; the brackets hold the `buftype` (`help`, `terminal`, `quickfix`), or the filetype when `buftype` is empty (oil shows `[oil]`).
- T269 [target] (A2, A6, A7) While visiting, `<M-f>` and `<M-S-f>` take the window back to its current slot first: at `⦉c⦊ [d] ⟦b⟧`, a `nofile` scratch shown in the window, then either key, gives d again with `⦉c⦊ [d] ⟦b⟧`. Today the visit drops the triquetra and the keys say "Window with unregistered buffer.".
- T270 [target] (A2) While visiting, the current slot may hold a closed buffer: at `⦉-⦊ [c] ⟦b⟧`, `:terminal` in the window, then `:bdelete c.txt`, leave `⦉-⦊ [c] ⟦b⟧` with c on the closed stack. Today the terminal drops the triquetra.
- T271 [char] (A19) A deleted buffer's window lands in the order ternary, secondary, primary, most recent, each on a route where Neovim's own pick (the window's jumplist) differs; Neovim closes every other window showing the buffer, so each is a window on its own, as in T111. Secondary: `:e a`, `:e b`, `:e c`, `<M-f>`, `<M-f>`, `<M-;><M-t>` give `⦉-⦊ [b] ⟦a⟧`, and `:bdelete b.txt` lands on a (Neovim: c). Primary: a split on c with empty slots, left alone by `:only` after the first window visited d and x, with its queue set to `[a]on` by hand, lands on a after `:bdelete c.txt` (Neovim: b). Most recent: the same with an empty queue lands on x (Neovim: b). Nothing to land on: `:e a`, a listed `nofile` scratch, `:bdelete a.txt`: Neovim shows the scratch, something other than its empty buffer, so `:enew` runs and the window shows a new empty buffer. "Most recent" follows `history_view`, as `<M-.>` already does today (the bufferline's order, built from the current view): under the window view it's the window's own history (the author, 2026-10-21: "Follow history_view"). A sub-case checks it under the window view, where the window lands on what it showed rather than on the last file touched elsewhere.
- T272 [char] (A20) The disk decides, the copy half: `:e a`, `:e b`, `:saveas g.txt` leave b.txt on disk, so the rename is a copy and b goes on the closed stack. It holds today already, so it's [char]: a guard that stays true when the decided code lands. What `:saveas` does to the window is T106's.
- T273 [char] (A22) The stale pass keeps the history of the file it re-points: T113's state, and after the pass b's hash is still in the global history.
- T274 [char] (A23) `:CavediverTriquetra` and `:CavediverTriquetraVerbose` print `primary_buffer[1]` as "Primary buffer".
- T275 [target] (A26) Each "shouldn't happen" dumps: the fill assertion (T176's second half), "Duplicates detected" (T34's state), and a hook failure (a hook that throws, bound by hand to the history machine's updates) each leave a new file under `stdpath("state")/cavediver/` (the location T200 uses, decided 2026-10-21).
- T276 [target] (A26) A planted I1 break dumps at the next step: T203's layout, with c's secondary set by hand to b, its ternary, and `:e x` in the other window produces one dump.
- T277 [target] (A26) The error message says where the dump file is: T200's restore assertion, and the error or a message names the new file.
- T278 [target] (A26) Steps are tagged by cause: in T200's dump, the steps from keymaps and from events carry the tags `keymap` and `event` (T204 checks `load` and `timer`).
- T279 [char] (I5) The registry stays a bijection, for buffers and for paths: random walks with T130's mix plus `:enew`, a No Name buffer with text, `<M-.>` and `<M-S-w>`, checked after every action.
- T280 [char] (I6) A buffer wiped without events leaves no stale registration once a cleanup tick has run: `:e a`, `:e b`, `:e c`, `noautocmd bwipeout` of b, then a 4.6 s wait leave every registered buffer number valid.
- T281 [char] (I7) After a cleanup pass, no hash on the closed stack has an open buffer: random walks with T279's mix, a `cleanup_system` pass forced after every action ("eventually enforced").
- T282 [target] (I8) A window's current slot is the hash of the buffer it shows, except in the window a cycle runs in and during a visit: random walks with T128's mix, cycles left open across a window jump included. Today the walks break it through the cycle leak: work in another window while a cycle is open isn't recorded (A12). I8's status also names a second route, "Duplicates detected" leaving the slots behind (A1). The cycling exception covers only the window that's cycling; every other window must match what it shows at every step (confirmed by the author, 2026-10-21: "Only the cycling one").
- T283 [char] (I9) Every triquetra belongs to a valid, non-floating window: random walks with T128's mix plus `:enew`, `<M-.>` and `<M-S-w>`.
- T284 [char] (I9) `:file` onto a name not on disk, in a split, leaves no triquetra for a dead window: `:e a`, `:vsplit`, `:e b`, `:file new.txt`.
- T285 [target] (I14) A save with a slot holding a hash with no path succeeds and reports nothing: at `⦉c⦊ [d] ⟦b⟧`, the secondary set by hand to an unknown hash, then `save_session` in the same call. Today the save hook fails with "This must not be possible…".
- T286 [target] (I21) The critical save hook throws to the caller and storage is `idle` afterwards: T143's read-only session directory. Today the save returns normally.
- T287 [target] (I23, A21, final section) The check runs at a cleanup pass that moved a window's slots: T163's re-point, with d's secondary note set by hand to b, the window's secondary under today's re-point and the decided one alike; once d is current I23 holds and `<M-;><M-t>` doesn't throw. Today the note stays.
- T288 [target] (D11, bug found while porting) Under the window view, `:close` leaves no tie: `:e a`, `:e b`, `:vsplit`, `:close`, `:e a` put a strictly first in the bufferline order. Today a and b tie.
- T289 [target] (D25) The window machine goes: no `window/sm.lua`, no `SHOWING_` constants in `window/states.lua`, and nothing requires `cavediver.domains.window.sm`. A doc check, matched by text.
- T290 [char] (D18, D22, D24) STATUS and the old project `CLAUDE.md` live in `archive/`, and neither is at the repo root. A doc check. It holds today already, so it's [char]: a guard that stays true when the decided code lands.
- T291 [char] (D8, D13) README:15 ("Closed buffers reopen when accessed through relationships") and README:355 ("Every time you jump to secondary…") stay as written. A doc check, matched by text. It holds today already, so it's [char]: a guard that stays true when the decided code lands.

**The session file, S2 (T292–T332)**

Each checks a rule S2 states as decided, or a desk line S2 rests on, that no earlier test checks, found by mapping S2 against the tests (2026-10-21), and cites the rule. Most save in one process and load in a fresh one, passing the cwd as the session's name, so they hold under today's API and the decided one alike. Where S2 leaves a format or a mechanism open, the test matches loosely and says so.
- T292 [target] (S2 Contract and API; DESK:758, DESK:1074) `save_session()` and `load_session()` take no directory: with no argument the save writes a file whose name starts with `sha256(getcwd(-1, -1))`, and `load_session()` in a fresh process brings back `⦉c⦊ [d] ⟦b⟧`. A nameless save is named `sha256(directory)` alone, with no separator (decided 2026-10-21, the author: "directory alone"); the separator is only used with a name. Today the save throws "CWD is required to save session".
- T293 [target] (S2 Contract and API; DESK:758, DESK:1146) A whole-editor save is keyed by the global directory, not by a tab-local `:tcd`: `save_session('work')` from a tab with `:tcd sub` writes a file named after `sha256(getcwd(-1, -1) .. "\n" .. 'work')`, and none after the tab's directory. Today the name is the shell sha256 of `work`.
- T294 [target] (S2 Contract and API, Tab sessions; DESK:949, DESK:1074) A tab session is keyed by its tab's directory: `save_session('t', { tab = … })` from a tab with `:tcd sub` writes a file whose name starts with `sha256(<project>/sub .. "\n" .. 't')`. The spec makes the scope's directory the key and names the file `sha256(directory .. "\n" .. name)` (T255); that the name takes the tab's directory is read from the two together.
- T295 [target] (S2 Loading; DESK:1284) A load from idle goes `idle → bare → loading`: after a save, `load_session` adds `idle->bare` and then `bare->loading` to the storage machine's history. Today it throws "Transition 'idle->loading' is not registered" (T137).
- T296 [target] (S2 Loading; DESK:1282, DESK:1284) Every domain tears its own state down at `idle → bare`: saved at `⦉b⦊ [c] ⟦-⟧`, then `:e d`, `:e x`, `:bdelete d.txt` and a cycle step left open, the window put back on c and a load give `⦉b⦊ [c] ⟦-⟧`, an empty closed stack, navigation `normal`, history attached, and x unregistered.
- T297 [target] (S2 Loading; DESK:1286, DESK:1288) The repeat flag is re-armed by `vim.schedule`: three `load_session` calls in one batch, a 30 ms wait, then a fourth call give two loads, and every call returns normally. With T145, this tells `vim.schedule` apart from a timer and from no flag.
- T298 [target] (S2 Loading; DESK:794) Cavediver loads again by itself after Neovim's `:restart` session, ignoring the flag: two windows saved at `⦉c⦊ [d] ⟦-⟧` and `⦉a⦊ [b] ⟦-⟧`, a startup load, and then the restart session sourced in the same batch give two loads and the saved slots. `:restart` can't run inside a test's child, so the child is started with `__NVIM_STARTREASON=restart` in its environment, an undocumented Neovim 0.12 internal that sets `v:startreason`, and the restart session is a `:mksession!` file named `restart_session_…`. Today there's one load, and the window on b comes back `⦉d⦊ [b] ⟦-⟧`, as in the desk's repro.
- T299 [target] (S2 Loading; DESK:1161) One post-restore callback replaces the 210 ms delay: the load makes no timer, and 30 ms after it `last_valid_window` is the current window and the bufferline order is what it still is 300 ms later. The require-time probe is T254. Today the load makes a timer, and `last_valid_window` is still the old window.
- T300 [target] (S2 Loading; DESK:1286) A later reload brings no No Name text back twice: with a No Name text open in the ternary at save, a load and then a second load leave exactly one buffer holding it.
- T301 [target] (S2 The file; DESK:1554) The main file starts with the clear version header `CDV1`. Today it starts with `{"`.
- T302 [target] (S2 The file; DESK:1541) Nothing in the session files is in clear: with b closed and a No Name text open, no file under `session_dir` parses as JSON or holds the project's directory, a file name or the No Name text. Today the file is JSON.
- T303 [target] (S2 The file; DESK:1541) The file goes through `libcrypto`, not a command: a save, and a load in a fresh process, make no `vim.fn.system`, `io.popen` or `vim.system` call. Today the file's name comes from the shell's `sha256sum`. Hashing on `:e` is T222.
- T304 [target] (S2 The file; DESK:1555) Every write is atomic: a second save puts a new file in place by renaming it over the first (the main file's inode changes), and leaves no other regular file in `session_dir`. Today `writefile` rewrites the same file.
- T305 [target] (S2 The file; DESK:1547, DESK:1555, DESK:1636) One file per No Name text sits in `<main>.d/`, each in mode 0600: a No Name text closed with `<M-.>`, another open, and an empty one shown give exactly two files there, `rw-------` with a umask of 022. The directory is found as the one in `session_dir` whose name ends in `.d`.
- T306 [target] (S2 The file; DESK:1547, DESK:1548) Scratch files are named per version, written only when they change, and swept once nothing references them: a second save with the text unchanged keeps the same file and bytes; after the text changes, the next save leaves one file under a new name.
- T307 [target] (S2 The file; DESK:1548) The main file is the commit point, in two cases put together from the files of two saves (v1, then v2). A crash before the main file lands (the first main file, with both scratch files beside it) loads with the v1 text back and not v2; a crash after it (v1's scratch left beside v2's) is swept by the next save.
- T308 [target] (S2 The file; DESK:1548) A damaged scratch file loses one scratch, not the session: with two open No Name texts saved and one byte flipped in one scratch file, the load gives back `⦉a⦊ [b] ⟦-⟧` and exactly one of the two texts.
- T309 [char] (S2 The file; DESK:1549) No count limit: 150 files closed with `:bdelete` are all on the closed stack after a save and a load in a fresh process. It holds today already, so it's [char]: a guard that stays true when the decided code lands.
- T310 [target] (S2 Checks; DESK:1541, DESK:1683, DESK:1685) A file only decrypts in its own directory: a file saved as `work` in one project, copied to the name `work` takes in a second project (`sha256(directory .. "\n" .. 'work')` with that project's directory), gives "failed its integrity check (edited or corrupted)" there and a fresh start, `⦉-⦊ [b] ⟦-⟧` with an empty closed stack. Matched on "integrity check". The edited byte is T144.
- T311 [target] (S2 Checks; DESK:1683) A cut-off file, the saved file cut to half its length, gives the integrity notification and a fresh start, as T144's edited byte does. Today it's a silent fresh start.
- T312 [target] (S2 Checks; DESK:1682) A file with no header, plain JSON in today's format at the main file's name, gives a message naming the migration script at load. Matched on "migration script". The newer header is T245.
- T313 [target] (S2 Checks; DESK:1689) A reference that resolves to nothing at load is kept, says so when it's used, and works again when its file comes back: saved at `⦉c⦊ [d] ⟦b⟧`, with b.txt deleted and not restored, the load keeps `⦉c⦊ [d] ⟦b⟧`; `<M-f>` gives a message, raises nothing and changes no slot; with b.txt written back, `<M-f>` gives `⦉c⦊ [b] ⟦d⟧`. Today the secondary comes back empty.
- T314 [target] (S2 Contents; DESK:1432, DESK:1436) A restored buffer the file doesn't know waits for `BufEnter`: x, loaded and hidden at the load but never saved, isn't registered by the load, and is once `:e x` enters it. Today the load registers every loaded buffer.
- T315 [target] (S2 Contents; DESK:1440) Windows on the same file keep their saved order, and a window that matches nothing starts fresh: saved as `⦉c⦊ [b] ⟦-⟧` (the split, listed first) and `⦉a⦊ [b] ⟦-⟧`, and restored behind a new first-listed window on e, the windows read `⦉-⦊ [e] ⟦-⟧`, `⦉c⦊ [b] ⟦-⟧` and `⦉a⦊ [b] ⟦-⟧`. Today each window takes the entry at its position.
- T316 [target] (S2 Save-as-closed; DESK:1634, DESK:2299) A No Name buffer reopened at load gets a fresh id, and every reference to its old hash is renamed: a No Name text in the ternary (`:e a`, `:enew` with text, `:e b`) comes back as the ternary under a hash that differs from the saved one, and no slot, queue, note or history entry keeps the old hash. Today the text isn't reopened.
- T317 [char] (S2 Errors and drift; DESK:1070) With two editors on one project, the last writer wins: both save in turn without an error, and a fresh process loads the second one's `⦉c⦊ [d] ⟦-⟧`. It holds today already, so it's [char]: a guard that stays true when the decided code lands.
- T318 [target] (S2 Tab sessions; DESK:949) A tab session's file says its scope, and its load works on the current tab only: a session saved with `{ tab = … }` from a tab at `⦉c⦊ [d] ⟦-⟧`, loaded by name alone into a second tab of a fresh process, gives that tab `⦉c⦊ [d] ⟦-⟧` and leaves the first tab at `⦉x⦊ [t] ⟦-⟧`. Today the first tab gets `⦉c⦊ [d] ⟦-⟧` and the second `⦉-⦊ [d] ⟦-⟧`.
- T319 [target] (S2 Tab sessions; DESK:952) Closes go to the pool of the tab they happen in, and `<M-S-w>` reopens from the current tab's: in T318's state, after `:bdelete x.txt` in the first tab and then `:bdelete c.txt` in the session's tab, `<M-S-w>` in the first tab reopens x and in the session's tab c. Today the first tab gets c.
- T320 [target] (S2 Tab sessions; DESK:951, DESK:954) The session's tab ranks its own visits first, and a buffer belongs to every tab that visited it: in T318's state, `:e a`, `:e b` in the first tab and `:e a` in the session's tab leave a, c and d as the first three in the session tab's bufferline order. Only membership is checked; the spec doesn't fix the order inside the overlay.
- T321 [target] (S2 Tab sessions; DESK:955) Saves are snapshots: in T318's state, with x closed in the first tab, c in the session's tab and e in the first tab, a second apart, a whole-editor `save_session()` leaves the pools apart in memory (`<M-S-w>` in the first tab reopens e, then x), and a fresh process loading that file has one stack merged by close time (`<M-S-w>` reopens e, c, x).
- T322 [target] (S2 Tab sessions; DESK:956) A tab session's tab closed with nothing wired to save it keeps its pool, with no tab, and gives a notice: in T318's state, `:tabclose` on the session's tab, with no `TabClosedPre` hook calling `save_session`, gives a notification; and with c closed in that tab first, `:CavediverClosed` still lists c afterwards. The wording isn't fixed, so any notification that isn't a hook failure counts.
- T323 [target] (S2 Tab sessions, Errors and drift; DESK:957, DESK:1068) A tab-session save refreshes the unnamed session's records and leaves its references: with the whole editor saved by `save_session()` at `⦉x⦊ [t] ⟦-⟧`, the tab session loaded into a second tab, x closed and e visited in the first tab, and the tab session saved, a fresh process's `load_session()` has x on the closed stack and still `⦉x⦊ [t] ⟦-⟧`.
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

The first reason is exactly why the secondary restore throws after a round trip today: `<M-f>` writes a plain secondary note. "Keep the older one" (decided 2026-10-20 evening) gives the secondary map the same two kinds of note (M7).

(M7, A6, A7, A11, D7, D20)

**Q3. Graduation copies the ternary's memory into the secondary map.** When `<M-f>` moves the ternary b into an empty secondary, it also sets `dsm[b] := dtm[b]` (`window/routines.lua:484-485`). Intended, or should the graduation leave dsm alone?

**Answered (2026-10-20):** intended. The author's reason: the graduated buffer's predecessor can then come back either as the ternary (`<M-;><M-r>`) or as the secondary (`<M-;><M-t>`) (M7, A6). Under "Keep the older one", graduation also clears the graduated buffer's secondary swap note, so the copy is what the restore finds (T184).

**Q4. Window-view numbering.** With `history_view = "window"`, entering a window adds n−1 to `history_index`, which looked like it would make the next visit tie with the window's newest entry. Should the counter end one higher?

**Answered (2026-10-20):** replaced by a property test: after any visit, in either `history_view` (`"global"` or `"window"`), across windows, the visited buffer is leftmost in the bufferline order (T149). The suspected tie wasn't reproduced: with two windows, going back into window A and `:e e` gave `e=7 b=6 a=5 d=4 c=3` (M4).

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

**Answered (2026-10-20):** keep the assertion. The restore throws when the remembered value equals the current slot, and the routes that still reach it get hunted by tests (T154). The old spec's message (SPEC:176) is out of date (A11, D9, T66). The routes found so far share one cause, and "Keep the older one" (decided 2026-10-20 evening) is the upstream fix (I23, T177–T190).

**Q14. An empty queue that's still "enabled".** When cleanup prunes every primary entry, `primary_enabled` stays true **[run s06]**. Should an empty queue force it off, as the load already does (`window/init.lua:58`)?

**Answered (2026-10-20):** fix only the key. An empty queue may stay switched on. `<M-;><M-x>` on an empty queue queues the current buffer and switches on, whatever the switch said, so one press does the job (A9, I19, T157).
- Shown **[run s19]**: primary `b`, `b.txt` deleted on disk, `:e d` gives `p=[]on`; the first `<M-;><M-x>` gives `p=[d]off`, the second `p=[d]on`.
- The route through a deleted file goes away once missing files stay tracked (desk). Whatever cleanup still removes from the queue can empty it.

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

**Q18. Re-pointing without an event.** When cleanup finds a window showing a different tracked buffer from its current slot, with no `BufEnter`, it sets `c :=` that buffer and drops the old current from the triquetra. Plain navigation would move the old current to the ternary. Should re-pointing behave like navigation?

**Answered (2026-10-20):** yes. Cleanup's re-point without an event acts like navigation: the old current goes into the ternary (A21, T163).

**Q19. Which way `<M-n>` and `<M-m>` go.** They call cokeline's `by_step("focus", -1)` and `+1`, and the bufferline puts the newest buffer on the left. Is "`<M-n>` toward newer" the intended direction?

**Answered (2026-10-20):** confirmed. `<M-n>` steps left, toward newer buffers; `<M-m>` steps right, toward older ones (A12, T79).

**Q20. Shared transition modes.** The engine keeps transition modes in one table for every machine. A hook on the history machine could name navigation's `winenter` mode without an error. Should modes be per machine?

**Answered (2026-10-20):** shared on purpose. Modes are one vocabulary for orchestrating all machines; a machine seeing a mode another machine registered is intended. The code and comments change to say so: the class declares the shared table, the factory comment is fixed, and the two per-machine checks are reworded or dropped (M11, T6).

**Finding (2026-10-20):** the factory (`engine/init.lua`) gives each machine its own states, transitions, hooks and history, but not `transition_modes`. So all seven machines (six once the window machine goes, D25) share the class's one table (`engine/state-machine.lua:111`), and every machine sees all four modes: `delete`, `update`, `cycle` and `winenter`. This was checked at run time with `rawget`. Today no hook names another machine's mode: hooks from other domains register on the machine that owns the mode, for example `history/hooks.lua:59-61` on the navigation machine.

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
- Call `setup({ session_dir = <scratch>/… })` with a table, because `setup()` with no argument throws.

**Stubs.**
- `package.preload['harpoon'] = function() return { list = function() return { display = function() return {} end } end } end`. The UI's refresh and the ordered list both `require('harpoon')`.
- `package.preload['cokeline.mappings']` needs `by_step(kind, step)`, `is_picking_focus()` and `is_picking_close()`. The runs here moved through cavediver's own ordered list (index 1 = newest), so cycling direction against real cokeline is unverified.

**Things that bite:**
- **Errors are hidden.** Hook errors are caught and only show up through `vim.notify`. Replace `vim.notify` with a collector and check it after every action. An error from `to()` itself, like `idle->loading`, a slot action's `error()`, or the restore's throw, does propagate, so wrap actions in `pcall`.
- **Inside a hook, `sm:state()` is the old state.**
- **Timers only run while the event loop runs.** That covers the cleanup tick (4 s, first tick at once), the UI tick (about 140 ms), the 200 ms probe and the 210 ms rebuild. Use `vim.wait(ms)` to let them run. The slot logic doesn't need the timers. The landing after a delete (A19) and healing's switch (A21) wait for `vim.schedule`, so let the loop run once before checking what a window shows.
- **One save/load cycle per process.** `load_session` works only from `bare`, so it can follow nothing else in the same process. Save in one process and load in the next, keeping the same `XDG_DATA_HOME` and the same cwd, because the file is named after the cwd. To fake a manager restore, use `bufadd` and `bufload` with `buflisted`, plus `noautocmd edit` for the shown file; `noautocmd badd` reproduces the unloaded-buffer case.
- **Fresh windows track nothing.** The first buffer nvim shows isn't registered until something enters it, so start every scenario with `:e a.txt`.
- **Splits don't fire `BufEnter`.** `:vsplit` creates the second window's triquetra on `WinEnter`, but no history entry.
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
- `<M-.>` on a modified No Name buffer caches its lines and filetype but not its cursor: `delete_buffer` switches the window away (`history/routines.lua:597`) before `bw!` (`:601`), so `bufwinid` at `:481` finds no window and `:485` falls back to `{1,0}` (T83, T90).
- `:help`, then `:only` before anything is tracked: the UI loop's hook fails on every tick with "Invalid window id: 1000" (`window/data.lua:74`). It keeps T166 failing even after Q17's fix.
- A tracked buffer wiped with `noautocmd`: the UI loop errors on every tick until the next cleanup tick.
- Under the window view the history rebuild also ties on `:close` (`:e a`, `:e b`, `:vsplit`, `:close`, `:e a` gives a=4 b=4); the tie fix (T197) covers it.

**Still open: two items need the author's answer.**
- **D2:** the default colour of the new `colors.cokeline.is_picking_focus` (T168).
- **Q15, left for the tab-session work:** whether reopening a file from one tab's pool also takes it out of the other pools.
