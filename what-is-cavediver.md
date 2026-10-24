# What is cavediver

First draft, 2026-10-20. A behavioural specification of cavediver, written so that an automated test suite can be built from it. Corrections go section by section.

## 0. How to read this

**The answers of 2026-10-20 are folded in.** The author answered all 21 questions in section 8 and confirmed principles P13–P21. Each question is closed in section 8, and the actions, invariants, disagreements and tests it touched are relabelled. What they settled beyond the questions is summarised at the very end, after the appendix, together with the few items that still need the author.

**Today and Decided.** "Today" is what the code in `lua/cavediver/` does now; `domains/prediction/` is left out. "Decided" is a design decision on the desk (`DESK.md`) that isn't implemented yet. "Decided (2026-10-20)" and "Decided (2026-10-20 evening)" are decisions from the author's answers that aren't implemented yet. When today and a decision differ for one action, they sit side by side under that action. A decision followed by "Built in step N." is in the code today, built by that build step; when only part of it is built, the line names the part.

**Sources and how they're cited.**
- Code paths are relative to `lua/cavediver/`. `domains/` is dropped, so `window/routines.lua:516` means `lua/cavediver/domains/window/routines.lua:462`. `init.lua`, `configs.lua` and `engine/…` are at the top of `lua/cavediver/`.
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
| P2 | The settle rule: act after the editor settles, never inside the event, and look at what's on screen then. | DESK:14, DESK:82, DESK:1783 | Partly. An arrival (`BufEnter`) and a window entry (`WinEnter`) wait for `vim.schedule` and look at the screen then. The arrival is slotted inside its own window, and only while that window still shows the buffer and no session has loaded since (`history/hooks.lua:223-244`). The entry is taken in only while the focus is still there, with the window it came from read at the event (`navigation/hooks.lua:82-95`). The landing after a delete, the cancel of a cycle on a window jump, the undo on `OptionSet` and the close key's delete wait too (`window/routines.lua:404-487`, `navigation/hooks.lua:50-52`, `window/hooks.lua:179-196`, `history/routines.lua:1531-1544`). Renames and writes wait too: `BufFilePre` only records the old hash, the rename is decided once the editor settles, and so is `BufWritePost`'s update (`history/hooks.lua:190-210`, `:249-281`; A20, T107, T238). `BufDelete`'s own bookkeeping still acts inside the event, since the buffer is gone afterwards (A19). With typeahead (a macro, a mapping that switches buffers several times, `:bufdo`), only what each window shows once the editor settles is slotted and recorded (A1), unless one of cavediver's keys comes between: a key first runs the settle work still queued, so it acts as if typed by hand (M11 Settle work). |
| P3 | Session-manager agnostic, no adapters. Two exports: the manager restores buffers and layout, then cavediver lays its triquetras over what came back. | DESK:13, DESK:751 | Held. The two exports exist (`init.lua:478-479`) and take the session's name, not a directory: cavediver reads the directory itself (S1). A load works after a save or a load in the same process, a native restore's repeated calls load once, and Neovim's `:restart` session is followed by a load of cavediver's own (S1). The load lays the triquetras over what came back: it matches windows by what they show, and a restored buffer the file doesn't know waits for its `BufEnter` (`storage/routines.lua:214-237`, `:284-394`; S1). A tab session's file lays them over the current tab's windows only, and tears nothing down (S1 Load). The README lists a session manager as optional (README:49), and its "Session manager setup" says what the wiring has to do, then gives it for resession, native sessions and no manager (README:68-136). |
| P4 | Cooperate rather than force: wherever cavediver bends the editor or other plugins to its model, that gets fixed. | DESK:21, DESK:2083 | Not held. Cavediver owns the winbar, and plugins are special-cased by name. The save leaves every window on what it shows, so the session manager saves an oil window as it is, and a load sets oil's `vim.w.oil_original_buffer` on an oil window to its current slot's buffer (`storage/routines.lua:376-382`, S1). Cleanup switches no window (A21). |
| P5 | Regular files only. Cavediver tracks regular file buffers and No Name buffers, nothing else. | README:553, DESK:37, DESK:2162, `history/routines.lua:85` | Partly. Today's rule is a listed buffer with no `://` in its name, and `buftype ""` or `nowrite` on an existing regular file (`history/routines.lua:1025`, M3). A registered buffer whose `buftype` changes so that it's no longer trackable has its arrival undone and is unregistered once the editor settles (I10). |
| P6 | The registry is the authority: hash → buffer and hash → path decide what a hash means. | DESK:1364, `window/hooks.lua:38` | Held as a design. Its gaps are listed under I2. |
| P7 | The user never registers a buffer by hand; registration is automatic. | `window/routines.lua:239` | Held. |
| P8 | Cleanup repairs only cavediver's own data and never touches a buffer or a window. | DESK:19, DESK:1859 | Held. Cleanup wipes no buffer and switches no window: its healing changes only the slots, and a window it can't heal loses its triquetra rather than being given a buffer (A21). |
| P9 | Missing files aren't forgotten. A pointer to a file gone from disk is kept, and says so when it's used. | DESK:20, DESK:2022 | Held. A buffer whose file is missing stays tracked, and a slot pointing at an open buffer is kept whatever the disk says (M3, A21). A closed slot, primary queue entry or closed-stack entry whose file is gone from disk stays too (A21, A22), a queue entry through the pop-up's save too (A18, T454), and using it says so and changes nothing: the slot keys (A6–A8; T44, T45, T57, T58, T227) and `<M-S-w>` (A16, T89). A restore keeps a note whose closed file is gone from disk, and says so (A11), and a session load keeps a reference whose file is gone (S1, T313). So does `<M-.>` in a window visiting something untracked, whose closed current slot is gone from disk: it closes the visited buffer and says the window can't go back (A15) **[code]**. A file gone from disk is tagged with where you were when it went missing, shown dimmed in the winbar and the bufferline, and the tag clears once the file is back (M14, T343). |
| P10 | Follow along: displacement maps and history never keep anything alive. Their entries go once what they point at is no longer known. | DESK:83, DESK:2029 | Held, as of the next cleanup pass. Every `cleanup_system` pass (every tick, save and load) and the close of an empty No Name buffer drop the notes and history entries whose hash is no longer known, then forget those hashes' paths (`follow_along`; M7, A22, I17, T208). A closed file stays known through the closed stack, so it keeps its history (M4, T252). A restore also clears a note at a hash with no path when it uses it (A11). |
| P11 | Errors in the state machine shouldn't happen. An error from `to()` is a loud bug, a bug inside a hook is caught with a stack trace, and the save hook is critical. | DESK:1154-1157 | Held. Hook errors are caught with a stack trace (`engine/helpers.lua:41-53`), and dumped (A26), and the save hook is critical (`storage/hooks.lua:17`, I21). |
| P12 | Nothing runs at `require`. `setup()` creates the autocmds (in one augroup), the commands and the timers, and can be re-run. | DESK:2177 | Held. `require` creates no autocmd, command or timer. `setup()` creates the autocmds in the `cavediver` augroup, the commands and the timers, and running it again replaces the autocmds, commands and timers (`init.lua:168-241`, A25). |
| P13 | You can always get back to what once was: the secondary and the ternary can always be restored. | README:7; confirmed by the author (2026-10-20) | Held. The restores work (A11), and "Keep the older one" keeps every note a restore reads from naming the slot's own occupant, so no route found makes a restore throw (M7, I23, T154). A closed slot whose file is gone from disk stays (A21, P9). A note goes only once nothing knows its buffer, and a closed file stays known through the closed stack (P10). |
| P14 | The secondary is yours: it changes only when you act. | README:540, SPEC:41, SPEC:299; confirmed by the author (2026-10-20) | Held. Going to the secondary by plain navigation counts as acting, and swaps it (A1). The author's check: `:e b`, `:e c`, `<M-f>` (graduation), `:e d`, then `:e b` gives `{c=b s=d t=c}`. |
| P15 | The ternary is your previous buffer, filled in on every jump that isn't to the secondary, and not on a cycling pick. | README:534; confirmed by the author (2026-10-20) | Held (A1, A13). A pick of an outside buffer leaves the ternary alone and notes the start on the picked buffer instead (Q9). |
| P16 | A buffer is never in more than one of a triquetra's current, secondary and ternary slots. | README:555, SPEC:343; confirmed by the author (2026-10-20) | Asserted, not maintained (I1). The primary isn't one of the three: it may share a slot's buffer (Q16). |
| P17 | Every window is independent: its own triquetra and, optionally, its own visit history. | README:17, README:561; confirmed by the author (2026-10-20) | Held. |
| P18 | Cycling is exploration: stepping with `<M-n>`/`<M-m>` records no visits and writes no displacement entries; `<M-v>` picks. `<M-f>`, `<M-S-f>` and the restores, pressed while the window shows its current slot, do their normal job, notes included, cycling or not. | README:571, SPEC:30-37, SPEC:546; confirmed by the author (2026-10-20); narrowed to the steps by the author (2026-10-20 evening, "Yes, as today") | Held. The current slot stays frozen while cycling (A12, Q1). The pick's own writes (Q6's guard, Q9's note, the stale-note check of "Keep the older one") stay, since `<M-v>` ends the cycle **[run `t/pkB_cycle_keys.lua`]**. |
| P19 | A restore flip-flops instead of being used up, with one remembered entry per buffer for each kind of note, overwritten by the next displacement. | SPEC:523-544, README:536; confirmed by the author (2026-10-20); the "for each kind of note" rewording confirmed by the author (2026-10-21) | Held (A11). Both maps keep a plain note and a swap note per buffer, and a restore uses one of them (Q2, M7). A note that has gone stale is rewritten to the older one ("Keep the older one", decided 2026-10-20 evening, built in step 3; M7). |
| P20 | Keys are predictable: `<M-S-f>` always does the same swap, and restoring is only ever explicit. | SPEC:512-521; confirmed by the author (2026-10-20) | Held. The swap also writes a `-swap` note, which SPEC:240 rules out; Q2 keeps the note (D7). |
| P21 | Identity comes from the file name: a hash of the name, so relationships survive restarts. | README:12, STATUS:34-40; confirmed by the author (2026-10-20) | Held. Hashing is `vim.fn.sha256`, with no shell (M1). |
| P22 | Privacy: the session file is usage data and stays protected. | DESK:1541, `init.lua:4` | Held. The session files are encrypted with AES-256-GCM, under a key stretched from the session's directory (S1): none holds the directory, a file name or a No Name text in clear (T302), a file only decrypts in its own directory (T310), and every file is written in mode 0600 (T212, T305). The flight recorder's dumps are sealed the same way, being usage data too (A26, T460). The key's only secret is the directory's path, as decided (S2 The file). |
| P23 | Drift between cavediver's file and the manager's is designed out, not detected. | DESK:1056 | Partly. References are written only when the manager saves. A session's records, its closed list, close times and No Name texts, cavediver writes into its file itself whenever they'd otherwise be lost: as they change, on the next tick and again a second later; as the editor quits; as a tab session's tab closes; and, for the unnamed session, at a tab-session save. Each write leaves the references as the manager last saved them (S1 Records; T322, T323, T358, T359). It never makes a file. On a change and at quit it writes only while storage is idle and the editor is still where the session would be saved from, and a whole-editor load drops a write still pending (T360–T362). A tab close's write waits a tick, so a manager's switch, whose teardown closes tabs with events on and ends with a whole-editor load, drops it with the rest, and a quit in the same batch writes it (T358, T365). Not held: what changed after the last write and before a crash is lost, a second's worth at most; with two editors on one session each writes its records over the other's; and a session whose records can't be written keeps them in memory, with a warning (S1 Records, S2 Errors and drift). |
| P24 | A save is a snapshot and never changes the running state. | DESK:955, DESK:1152 | Not held. A save runs `cleanup_system` (`storage/routines.lua:2255`, A22), which wipes nothing and keeps a closed file gone from disk on the closed stack (T214), but its passes still mend at the save what the next tick would: a buffer gone without events is closed, notes and history that no longer follow along go, and a file gone from disk is tagged (M14). It leaves every window on what it shows, an oil window included (S1, T146). A whole-editor save merges the pools in the file only: in memory they stay apart (T321); the detached lists it writes apart (T380). A save also records what it saved: a whole-editor save becomes the editor's session and ends the unnamed one, so the whole editor's records cover every pool again, and a tab-session save puts the tab in its session's pool, whose visits start from the tab's windows' histories at its first save, marks the pool saved, and takes the unnamed session when no tab session has started yet; a tab-session save pushes any other tab in its session out into a detached list (T378); a tab-session save that takes its tab into a session it wasn't in carries the closed files the tab's slots hold onto that session's list, and closes the session it leaves when no other tab is in it, which then goes (T366, T368); either clears its session's mark of records waiting to be written (S1 Save). The records cavediver writes on its own leave the running state as it is: they read the pools and the texts, and write the file (S1 Records). |
| P25 | Two invariants: a path is never forgotten while anything references its hash, and every triquetra comes with its window's history entry. | DESK:84, DESK:1058-1064, DESK:1126 | Held. A path is kept while anything references its hash (I2), and every triquetra comes with its window's history entry, wherever it's made (I3). |
| P26 | Cokeline is required, as part of the UI. Harpoon is optional, through a provider. | DESK:2126, DESK:2144, README:42-49 | Held. Cokeline is required. Marked buffers come from `marks_provider`, and with none set, from harpoon's list when harpoon is installed (`marked_paths`, `history/routines.lua:1087-1107`; M12, T215, T450). |
| P27 | Cavediver reconciles any conflict between its model and the editor, "smartly". The four kinds of conflict decide who wins. | DESK:1781, DESK:1918 | Today that's healing inside cleanup (A21), the landing after a delete (A19), the visiting rule (A2), and undoing an arrival whose buffer turns untracked (I10). |

## 2. The model

### M1. Identity and hashing

- A buffer's **name** is `nvim_buf_get_name(buf)`. A buffer with an empty name is called `NONAME_<id>` instead (`noname_name`, `history/routines.lua:22-27`). The id is `os.time()` followed by `vim.uv.hrtime()`, digits only: the clock is written with `%.0f`, since `tostring` writes it in scientific notation once it passes 1e14 ns, about 28 hours after boot, which **[run 2026-10-23]** recorded as an id like `…1.0097070567542e+14` shown cut at its `.` (T142). It's made the first time the buffer is named and kept on the buffer, in `vim.b[buf].cavediver_noname`, so the buffer keeps its name and a later session's buffer with the same number gets another (I16, T11, T216). It's used at registration, on every update and in cleanup's heal (`:87-89`, `:1032`, `window/routines.lua:557-559`). A session file from before the `paths` table, the kind that holds `NONAME_<bufnr>` names, isn't read: its load is a fresh start (S1) **[code]**.
- Its **hash** is `string.sub(vim.fn.sha256(name .. "\n"), 1, 16)` (`history/routines.lua:36-44`): the first 16 hex characters of sha256(name .. "\n"), which is what `echo "<name>" | sha256sum` gives for an ordinary name, so saved hashes still match. No shell runs (T222). It's called for every `BufEnter` of a registered buffer, once it settles (`:1032`, `:1041`). A name containing `"`, `$` or a backslash hashes like any other (T9): the collisions reproduced at DESK:2131-2140 and DESK:2441 are the shell's.
- The **session file** is named `vim.fn.sha256(directory .. "\n" .. name)`, all 64 hex characters and nothing after them, inside `session_dir` (`storage/routines.lua:867-882`; T255). `directory` is the session's directory, which cavediver reads itself, and `name` is the name given to `save_session` or `load_session` (S1). A nameless save is named `vim.fn.sha256(directory)` alone, with no separator (T292). The session's No Name texts are in files of their own, in a directory named after the file with `.d` added (S1 File). A file under an older name isn't read: one named after the first 32 hex characters of `sha256(cwd .. "\n")`, from before step 4, or one whose name ends in the `.json` it had before step 5. The load finds no file under the new name, so it's a fresh start; when a file named the first way is there for the session's directory, it says to run the migration script (S1 Load, T340). The save writes a new file beside the old one **[code]**. The migration script, `scripts/migrate_sessions.lua`, converts files named the first way (S2 The file, T338).
- **Decided:** hash with `vim.fn.sha256(name .. "\n")` (DESK:1456, DESK:2131). A No Name id is unique across sessions, built from `os.time()` and `vim.uv.hrtime()` and kept in a buffer variable (DESK:2289-2297). The file is named `sha256(directory .. "\n" .. name)`, or `sha256(directory)` for a nameless save (DESK:1074). Built in step 2: the hashing, which the session file's name uses too. Built in step 4: the No Name id (T11, T216), and the file's name, `sha256(directory .. "\n" .. name)`, or `sha256(directory)` for a nameless save, with the directory read by cavediver (T255, T292–T294).

### M2. The registry

Defined at `history/data.lua:82-89`:

| Table | Maps | Meaning |
|---|---|---|
| `hash_buffer_registry.buffers` | hash → bufnr | what's open now |
| `hash_buffer_registry.hashes` | bufnr → hash | reverse |
| `hash_filepath_registry.filepaths` | hash → path | everything cavediver knows, closed buffers included |
| `hash_filepath_registry.hashes` | path → hash | reverse |

Writers:
- `register_buffer(buf)` (`history/routines.lua:82-113`) writes all four. If the hash is already bound to another buffer, that buffer's reverse entry is dropped, so the newer buffer takes the hash. It throws for `buftype ~= ""` unless the buffer is `nowrite` on an existing regular file (`is_nowrite_file`, `:84-86`).
- `register_filepath(path)` (`:119-130`) writes only the path pair.
- `unregister_buffer` (`:136-144`) drops the buffer pair and keeps the path.
- `unregister_filepath` (`:829-839`) drops the path pair, unless anything still references the hash: the history (view, global or a window's), a pool's visits or closed stack, a slot, a primary queue, or either displacement map, keys (`-swap` included) and values (`is_filehash_referenced`, `:153-185`, the pools at `:162-166`). A referenced path stays (`:833`).
- `settle_rename` drops the buffer pair of a renamed buffer that settles as a move, before the buffer is registered under its new name (`history/routines.lua:1316-1318`, A20).
- At a whole-editor load from idle, the history domain's teardown empties all four (`teardown`, `history/routines.lua:1796-1812`, S1). A tab session's load tears nothing down (S1 Load).

A path is forgotten in six places, each through `unregister_filepath`, so only once nothing references its hash:
- an "evolved" buffer on re-entry (`:1045`, M3)
- a closed No Name buffer reopened, which takes a new name (`:1232`)
- an empty No Name buffer being closed (`:1357-1358`): its own history entries go first (`:1354`), it leaves every secondary, ternary and primary queue (`window.data.forget_hash_in_slots`, `:1355`) and its buffer is unregistered (`:1356`), and then follow along drops the notes about it, so its path goes unless a current slot still holds it (M5, T208)
- follow along (`follow_along`, `:766-821`), for each hash that's no longer known once its notes and history entries are gone (M7, I17). It runs from every `cleanup_system` pass and when an empty No Name buffer is closed (A22)
- a rename that settles as a move, once every reference has followed to the new hash (`history/hooks.lua:129-131`, A20)
- a No Name buffer that was open at the save, reopened by a session load under a new name, once every reference has followed to the new hash (`storage/routines.lua:780`, M5, S1). One that's already back under its own id keeps its hash, and nothing is forgotten.

None of these leaves a slot or a note holding a hash with no path (I2, T129).

### M3. Which buffers are tracked

**Today** (`update_buffer_history`, `history/routines.lua:1017-1052`, called for every `BufEnter` once the editor settles, while history is attached, A1):
- **An unregistered buffer** is registered when `is_trackable` holds (`:1025`, `:68-73`): it's listed, its name contains no `://`, and its `buftype` is `""` or it's `nowrite` on a readable file that isn't a directory (`is_nowrite_file`, `:52-58`). An unlisted buffer, such as otter's or a plugin's scratch, isn't registered (T10, T13). There's no check that its file exists. So `:e brandnew.lua`, a file not on disk yet, gets registered **[run s08]**.
- **A registered buffer** being re-entered keeps its registration in two cases (`:1031-1041`):
  - it's a No Name buffer (`buftype ""`, empty name, loaded)
  - its path isn't a directory, and either its file is readable or it's a plain buffer (`buftype ""`, no `://` in the name). So a file not written yet, or deleted on disk, stays tracked (T14).

  Otherwise it counts as "evolved": a directory, or a buffer that turned into a terminal, an `oil://` listing and the like. It's untracked and unregistered, its path is forgotten unless something still references its hash (M2), and the call returns false (`:1042-1047`).
- **A `BufWritePost`** on an unregistered buffer runs the same update once the write settles (`history/hooks.lua:190-210`).
- **A rename** registers the buffer under its new name once it settles, whatever the history state, when the new name is trackable (`history/hooks.lua:120-122`, A20).
- **An `OptionSet` of `buftype`** on a registered buffer that's no longer trackable undoes its arrival once the editor settles, and unregisters it (`window/hooks.lua:179-196`, I10, T217).
- **The session load** registers every restored buffer, loaded or not, whose name hashes to a path in the session file's `paths`, outsiders left out, and that `is_trackable` holds for (`storage/routines.lua:219-232`; T139). A restored buffer the file doesn't know isn't registered: it waits for its `BufEnter` (S1, T314).

**Decided:** a tracked buffer is listed, has `buftype ""` (or `nowrite` on an existing regular file), and has a name that's empty or a plain path. A missing file says nothing about it (DESK:37, DESK:2162). The otter, `image_nvim` and `://` special cases become properties (DESK:2148-2158). Built in step 1: the missing-file sentence. Built in step 2: the first sentence for registration on `BufEnter` (`is_trackable`), and `nowrite` in place of the `image_nvim` check in `register_buffer` and the getter; otter's buffers stay out because they're unlisted. Built in step 4: the session load registers through `is_trackable` too, and the save keeps every window that has a triquetra, with no filter on what it shows (S1). The UI still checks `image_nvim` by name (M12).

### M4. History

Fields in `history/data.lua`:
- `history_index` (`:80`): a counter that only goes up.
- `crux_internals.global` (`:72`): hash → time, for every window.
- `crux_internals.window[winid]` (`:71`): hash → time, for the visits recorded in that window.
- `crux` (`:69`): **the view** the bufferline and the close key use.
  - With `bufferline.history_view = "global"` (the default, `configs.lua:107-109`) it's a copy of the global history.
  - With `"window"`, it's that copy with the window's own entries re-ranked above every global entry (`construct_crux`, `history/routines.lua:891-940`).
  - In a tab session's tab, under either view, the session's own visits (its pool's `visits`, below) are re-ranked above every global entry first (`:900-912`). So in the window view the window's own entries come first, then the session's, then the rest (S2 Tab sessions, T320).
- `ordered.crux` (`history/data.lua:76`): `{buf, time}` from `crux`, newest first. Hashes with no open buffer are dropped from the list and deleted from `crux` (`history/routines.lua:1060-1078`).
- `ordered.nonharpooned` (`history/data.lua:77`): the same list without harpooned buffers (`history/routines.lua:1130-1146`). It's computed on every update but nothing reads it except `get_ordered_buffers(false)`. **[code]**
- `pools[id].visits` (`history/data.lua:23`): hash → time, a tab session's own visits, the overlay its tab ranks above the global history (M5). The editor's pool has a `visits` table too, and nothing writes it.

How history is updated:
- `track_buffer(hash)` (`history/routines.lua:950-983`) does all of the following:
  - writes `history_index` into `crux` and `global`, then increments it
  - writes into the window history of the current window when the getter gives it a triquetra (M6). That's the window the visit happens in, since an arrival runs inside its own window (`nvim_win_call`, A1). Otherwise it writes into the history of `find_most_recent_tracked_window()`, the last-entered window that has a triquetra (`history/routines.lua:963-967`; DESK:2476, T19).
  - takes the hash off every pool's closed stack, and each pool it came off is remembered for its next close (`open_out_of_pools`, `:976`; M5)
  - when that window's tab, or the current tab when there's no such window, is in a tab session, writes the same time into the session's pool's `visits` and stamps the pool's `changed_at`, which writes no records (`:977-982`, M5). A call with a time, as a load makes, doesn't.
- Called with a time (session load), `track_buffer` writes that time into `crux` and `global`, and moves `history_index` past it (`:955-961`, T20). The window history still gets `history_index - 1` (`:972`). A load that goes through replaces both histories afterwards: `initialise_crux_internals` resets the window histories, puts back each matched window's own by window id, and puts the saved global history in place (`:866-872`; S1) **[code]**. A tab session's load tracks no saved entry: its file's history becomes its pool's `visits` (S1 Load).
- `untrack_buffer` (`:989-1007`) removes the hash from `crux`, `global` and every window's history, then rebuilds both ordered lists.
- A closed file keeps its history. The delete untracks only an empty No Name buffer, which isn't pushed; a buffer it pushes on the closed stack stays known, so its entries in `global` and the window histories stay (A19, T252), and so do those of a file whose buffer went without events, which the stale pass closes (A22). The view loses it whenever the ordered lists are rebuilt, since they leave out hashes with no open buffer, so it never reaches the bufferline.
- History follows along: an entry, in the view, `global`, a window's history or a pool's visits, goes once its hash is no longer known through an open buffer, a slot, a primary queue or the closed stack, at the next `cleanup_system` pass or when an empty No Name buffer is closed (`follow_along`, `history/routines.lua:766-821`, the pools' visits at `:792-794`; P10, I17, A22).
- `rename_hash_in_history(old, new)` (`:1261-1275`) moves a hash's entries in `crux`, `global`, every window's history and every pool's visits to a new hash. An entry the new hash has already, being newer, stays. A reopened No Name buffer and a rename that settles as a move use it (M5, A20).
- The ordered lists are rebuilt:
  - after a successful track on an update
  - on every delete transition
  - in `untrack_buffer`, `reopen_filehash`, cleanup and repopulate
  - once a load settles, for the focused window (`after_restore`, S1)

  `construct_crux` doesn't rebuild them; the `BufEnter` that usually follows a `WinEnter` does **[run s17]**.
- `construct_crux(winid)` returns at once when called for the same window as last time (`:894-898`). In window view it gives the window's n buffers the n fresh times and adds n to `history_index` (`:931-937`), so the next visit ranks strictly first and never ties with the window's newest entry (D11, T197, T288). In the author's run, with two windows, going back into window A and running `:e e` gave `e=7 b=6 a=5 d=4 c=3` (Q4); with the tie fix the same run gives `e=8 b=7 a=5 d=4 c=3`, the same order. The property test T149 checks that the visited buffer is always leftmost (Q4).
- `WinClosed` drops the window's history entry (`history/hooks.lua:284-293`, `window/data.lua:65`).
- A triquetra the getter makes comes with its window's history entry: `register_triquetra` creates an empty one when there's none (`window/data.lua:42`), so a `:vsplit` window has one once its `WinEnter` settles (I3, T18). **[run s16]** recorded the split with none.
- At a whole-editor load from idle, the history domain's teardown empties the view, both histories and the ordered lists, and sets `history_index` back to 1 (`history/routines.lua:1796-1812`, S1).

Window view, as run in s17: window 1 visits a, b, c, then window 2 (`:vsplit`) visits d and e. In window 2 the order is `e,d,c,b,a`. Back in window 1 it's `c,b,a,e,d`, and after `:e a` there it's `a,c,b,e,d` **[run s17]**.

### M5. Closed stack and No Name content

- **Pools.** Each session has a pool of its own (`Pool`, `history/data.lua:17-26`): its closed stack, `closed`, an array of hashes, newest last, each hash on it once; `times`, hash → when each entry was closed, in seconds to the microsecond (`vim.uv.gettimeofday`); `visits`, its own visits (M4); `tabs`, the tabs it's loaded in; and `saved_at` and `changed_at`, `vim.uv.hrtime()` stamps of its last save and its last change. `pools[id]` holds them (`:107`), and `tab_pools[tabpage]` names the pool of each tab in a tab session (`:109`).
  - The editor's pool, id `""`, is the pool of every tab in no tab session. Its `closed` is `closed_buffers` (`:93`), the same table: when something gives `closed_buffers` a new table, the next look at the pools makes the editor's pool again around it, with no close times (`editor_pool`, `history/routines.lua:231-238`). So after a load from idle, closes and `<M-S-w>` use the one table (T353).
  - A tab session's pool is keyed `name .. "\n" .. directory` (`pool_id`, `:299-301`). It's made the first time it's needed, at the tab's first save as that session, at the session's load, or at a load with the hint and no file (S1 Load), and the tab joins it, leaving the pool it was in (`join_pool`, `:350-364`; S1). A pool its last tab leaves this way, for another session's, is closed as at a tab close (below): at a load into that tab, which drops the tab's triquetras first (`join_for_load`, `storage/routines.lua:1169-1183`), and at a save of that tab as the other session (T366). A save of a tab under a session it wasn't in, whichever list it leaves, first carries the closed files the tab's slots hold onto the new session's pool, under its own entries, with their close times; the list it leaves keeps its copy while a tab is still in it (`storage/routines.lua:2276-2293`, `carry_closed` at `history/routines.lua:519-526`; T366, T368). The author, 2026-10-23: "when you do save_as, you are saving whatever you have right now in another name", then "Carry a copy" for a tab in no session and for a session still open in another tab.
  - **A detached pool** (`new_detached_pool`, `storage/routines.lua:1008-1012`) is a tab's own list once the session it was in has moved to another tab. A session is in one tab at a time, the tab the last load or save named, and each other tab in its pool leaves it for a detached pool of its own: a copy of the session's list, close times and visits, named after the session, `t_DETACHED`, then `t_DETACHED_2` and on, counting the names in memory and in the whole editor's file (`push_out`, `detached_label`, `:1034-1072`; T369, T378, T383). It has no file of its own: it's the whole editor's, written into the whole editor's file apart from its closed list (S1 Save, S1 Records), and a change to it marks the whole editor's records changed (`:2166`). Its tab is like a session's tab: closes go on it, and `<M-S-w>` there reads it (T379). Left with no tab, by a tab close, a load into its tab or a save of its tab as a session, it goes into the whole editor's file and leaves memory, except when t itself is loaded back into its tab, where it waits for the closed lists that open then (case 8, S2 Closed-stack picker); with no whole-editor file to go into, it stays in memory with no tab, with a WARN, "cavediver: <label>'s tab is gone, and its closed files couldn't be written into the whole editor's session file (<why>); they stay, with no tab, in :CavediverClosed." (`close_now`, `:2095-2112`; T381, T382). The author, 2026-10-23: "One tab, with carry", "A DETACHED list", "File only, piling up". The trail gets each detached list made, back with its tab, left or merged (A27, T419).
  - A pool's records, its closed stack and its close times, change when a push puts an entry on it, or an entry is opened again or discarded off it, the cleanup pass's removals included. Each of these sets `changed_at` and tells the storage domain, which writes the records of the pool's session (`changed`, `history/routines.lua:253-258`, called at `:393`, `:471`, `:502` and `:1738`; S1 Records). A visit made in its tab, `close_if_not_restored`'s insert and its session's load set `changed_at` alone (`:981`; `storage/routines.lua:262`, `:1275`). A save of its session sets `saved_at` (S1 Save). Nothing reads either stamp **[code]**.
  - "On the closed stack" and "closed", with no pool named, mean on any pool's stack: `is_filehash_closed`, `known_filehashes`, `is_filehash_referenced` and the UI's closed check look at every pool (`history/routines.lua:1393-1404`, `:209-213`, `:162-166`; `ui/routines.lua:1027`). `<M-S-w>` reads the pool of the tab you're in (A16).
  - `came_from[hash]` (`history/data.lua:111`) holds the pools a file came off when it was opened again, for its next close. A close uses it and clears it. It isn't saved, so it doesn't outlive the editor **[code]**.
- **A close** (`close_into_pools`, `history/routines.lua:429-454`) goes on the pool of the tab it's closed in (T319), on every pool it came off when it was opened again (`came_from`; a pool that's gone is skipped), and on the pool of every tab that visited it, whose windows show it or have it in their history (`tabs_that_visited`, `:402-417`). The last two are Q15's answer of 2026-10-23 (T349, T350). In each pool it's the newest entry, stamped with the close's time: every push takes any copy off that pool first, so a file closed again moves to the newest position, one copy per pool (`push_closed`, `:385-394`; I22, T162). The trail gets each close, with the lists it went on, and a close onto lists other than the tab's is said too (A27, T400). The closes:
  - `track_closing_filehash` on every delete transition, a rename that settles as a copy included (`history/hooks.lua:53`, `history/routines.lua:1371`; A20)
  - the stale pass of `cleanup_system`, for a file whose buffer went without events, unless it's on a pool already (`history/routines.lua:1691-1702`, A22)
- **Other writers of a pool's stack:**
  - `track_closing_filehash_force` when an unloaded path is typed into the primary history window (`window/routines.lua:256`): it goes on the current tab's pool alone, the newest there (`history/routines.lua:1386`)
  - `load_closed_buffers`, which empties the pool the load fills, the editor's for a whole-editor file and the tab session's for a tab file, and rebuilds it from the file's saved hashes and close times, leaving off one whose buffer the session manager brought back (`storage/routines.lua:803-857`, S1). For a tab session already open in a tab, or kept with no tab, it empties nothing: what's in memory stays, and the file's entries the pool doesn't hold go under it, as the oldest, in the file's order (`:804-805`, `:827-829`, `:847-849`; S1 Load, T357)
  - the session load, for a file in a matched window's slot or primary queue whose buffer the session manager didn't bring back and that the pool the load fills doesn't hold, under the saved entries, as the oldest, with no close time (`close_if_not_restored`, `storage/routines.lua:251-269`; S1, T337)
- **Opening again** (`open_out_of_pools`, `history/routines.lua:464-488`). A file open again is closed nowhere: it leaves every pool, and each pool it left goes into its `came_from` (I7). The trail gets the reopen, with the lists it left, and one off lists other than the tab's is said too (A27, T401). It's run by:
  - `reopen_filehash` (`:1196`), which `<M-S-w>` runs on the newest entry of the current tab's pool (A16). A file gone from disk isn't reopened, and keeps its place (below).
  - `track_buffer` (`:976`, M4)
  - the swaps' `remove_from_closed_buffers` (`window/routines.lua:284-286`)

  `cleanup_system`'s closed-stack pass does the same itself for an entry that's open again, on each pool that holds it: it takes the entry and its close time off, puts the pool in its `came_from`, and marks the pool changed (`history/routines.lua:1720-1746`, A22).
- **Leaving with nothing remembered** (`discard_from_pools`, `:496-507`): the hash leaves every pool, and its `came_from` goes. A rename that settles as a move uses it (`:1314`, A20). `cleanup_system`'s closed-stack pass drops an entry with no path from each pool, remembering nothing (A22). A closed file gone from disk stays (T114).
- **Teardown.** At a whole-editor load from idle and at a fresh start, the editor's pool is all that's left, empty: every tab session's pool goes, and `tab_pools` and `came_from` are emptied (`reset_pools`, `history/routines.lua:317-322`, run from `teardown` at `:1810` and `repopulate_history` at `:1824`; S1).
- **A tab session's tab closed** (`TabClosed`, `storage/init.lua:140-158`; M11): the tab leaves its pool. A pool left with no tab has its session's records written into its file on the next tick, its closed stack, close times and No Name texts, and then it's dropped, whether or not the session was saved since (`close_tab_pool` and `close_now`, `storage/routines.lua:2226-2234`, `:2090-2126`; S1 Records; T322, T351). A whole-editor load in the same batch drops that write, and its teardown the pool, so a manager's switch, which closes tabs inside its teardown and ends with the load, writes none of the teardown into the session (T365); a quit in the same batch writes it (T358). When they can't be written, because the session has no file yet or its file can't be read or written, the pool is kept with no tab, and a WARN says "cavediver: <name>'s tab closed, and its closed files couldn't be written (<why>); they stay, with no tab, in :CavediverClosed.", where `<name>` is the session's name, or its directory's last part for a nameless one, and `<why>` is "it has no session file yet" or what went wrong (T356). A kept pool's entries stay closed, so slots keep them; no tab's `<M-S-w>` reads that pool, and the closed lists (`:CavediverClosed`) show it with "no tab", to merge or discard from (S2 Closed-stack picker). A load of that session into a tab takes the kept pool back as it is, and the file only fills in (S1 Load) **[code]**.

  Before step 6 nothing deduplicated the stack, and **[run s20]** found no route that pushed a file twice: every reopen takes the file off, and a closed file keeps its record, so the primary pop-up never pushes it. Decided (2026-10-20): one copy per pool, newest wins (Q15, I22). Built in step 6: one copy on the single closed stack, newest wins (T162). Built in step 7: one copy per pool, newest wins, and a whole-editor save's merge of the pools in its file keeps one copy of a file, the newer (S1 Save, T321). The picker's merge keeps one copy, the newer, too (S2 Closed-stack picker, T371).
- `noname_content[hash] = {lines, filetype, cursor}` is cached when a **non-empty** No Name buffer is closed (`history/routines.lua:1349-1369`). The cursor is the one in the window showing it, or, when none does, the one `<M-.>` kept before switching the window away (`vim.b[bufnr].cavediver_cursor`, `:1367`, T83). An empty one is untracked, taken out of every secondary, ternary and primary queue (`window.data.forget_hash_in_slots`) and unregistered; then follow along drops the notes about it, and its path is forgotten unless a current slot still holds it; it isn't pushed (`:1353-1360`, M2, T208). A rename that settles as a move drops the old hash's text, which is in its file then (`:1315`, A20), and the teardown at a whole-editor load from idle drops them all (S1). The cache is one table for every pool. A pool owns the closed texts its stack holds, and the open ones its tabs visited; the editor's pool owns the open ones no tab session's tab visited (S1 Save).
- A closed No Name text that a session load puts back on the closed stack isn't read at the load. Its entry holds the name and path of the text's own file, the session's key and a reader, `{scratch, source, key, read}`, and the text is read from its file only when it's reopened, or when the closed lists draw its first line, which keeps it read unless its file fails its check (S2 Closed-stack picker; `load_closed_buffers`, `storage/routines.lua:830-846`; `reopen_filehash`, below; S1 Load). A save, and a records write too, keeps the file of an entry still unread without reading it, unless the entry came from another session's file or under another key, when the text is read and written again, and kept read from then on (T473), or its file is gone, when the text is lost and its hash leaves `closed` in the file (S1 Save, S1 Records). With two editors on one session, the last writer wins (T317), and a closed text one of them reopened and saved is gone from the other's next save or records write: its file was swept.
- `reopen_filehash(hash)` (`history/routines.lua:1187-1250`) reopens a closed hash:
  - It looks up the path. A file, not a No Name hash, that isn't readable returns `nil` there and then: a file gone from disk keeps its place on the closed stack, since it may come back (`:1192-1194`; P9, T89).
  - Otherwise it takes the hash off every pool, remembering them for its next close (`open_out_of_pools`, `:1196`).
  - **A No Name hash:**
    - A text a load left unread is read from its file first (`:1200-1202`). When the file is missing or fails its check, the reader gives the WARN "cavediver: a No Name text's file failed its integrity check (edited or corrupted), so that text is lost." and nothing, so the text counts as nothing cached.
    - With nothing cached, it returns `nil` (`:1203-1205`), already off every pool.
    - It creates a new listed buffer with the cached lines and filetype.
    - It sets the cached cursor in the window that shows the buffer, once one does: a one-shot `BufWinEnter` on that buffer sets it there (`:1211-1219`, T90).
    - It drops the cache, registers the buffer under a fresh `NONAME_<id>` (M1) and tracks it. Everything that named the old hash follows to the new one (`:1221-1230`, T91): every window's slots, primary queue and notes (`rename_hash_in_triquetras`), the history, the pools' visits included (`rename_hash_in_history`, M4), and its `came_from` (`:1229`). Then the old path is forgotten, unless something still references it (`:1231-1233`, M2).
  - **A file:** if the file is readable it runs `bufadd`, sets `buflisted` before `bufload` (whose `BufEnter` only tracks listed buffers), then registers and tracks the buffer.
  - In both cases it then runs `update_buffer_history` and rebuilds the lists, and returns the bufnr.
- **An open No Name buffer at a save** is saved like a closed one, when it isn't empty: its text, filetype and cursor go into a file of their own, as a closed text's do; the main file's `noname_content` names that file and marks it `reopen`; and its hash isn't put in `closed` (S1 Save). A session load brings each one back at once, in the background, reading its text from its file (`reopen_noname_buffers`, `storage/routines.lua:750-785`; S1 Load, T140, T316):
  - It's a new listed buffer with the saved lines and filetype, shown in no window, and modified, since setting its lines marks it. Its cursor goes back in the window that shows it, once one does, through a one-shot `BufWinEnter`, as with `reopen_filehash`, and `vim.b.cavediver_reopened` holds the hash it was saved under.
  - It's registered under a fresh `NONAME_<id>` (M1), and every slot, queue entry, note and history entry that named the saved hash follows to the new one; then the saved path is forgotten, unless something still references it (M2). No visit is recorded: the history keeps the saved time, under the new hash.
  - It goes neither into the cache above nor on the closed stack: only the `closed` entries go through `load_closed_buffers`.
  - An unnamed buffer that's already that text is taken as it is, registered under its own hash, with the references following to it: one reopened by an earlier load, whose `cavediver_reopened` is the saved hash, or one still open since a save in the same process, whose own id hashes to it So a second load in one process brings no text back twice (T300). Its file isn't read.
  - A text whose file is missing or fails its check is skipped, with the WARN above: that text is lost, and the rest of the session isn't (T308).
- The display name of a closed slot comes from its path. After a `:bdelete` the unlisted buffer still exists; `find_basename_conflicts` skips the file's own path, so the buffer isn't a clash with itself, and the winbar shows the basename (`ui/routines.lua:872-885`, T118). **[run s06, s14]** recorded the full path before the fix.

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
- by `ensure_curwin_crux` on every history update (`window/hooks.lua:29-35`)
- by `track_buffer`, on the current window (`history/routines.lua:965`, M4)
- by `find_most_recent_tracked_window` (`navigation/routines.lua:108`)
- by every slot action
- by the UI's derive path (`ui/routines.lua:986`)
- by the session load, for a window that matches no saved entry (`storage/routines.lua:313`, S1), and, at a load with the hint and no file, for each of the tab's windows (`:1212`, S1 Load)

**Removal** goes through `unregister_triquetra` (`window/data.lua:57-74`). It happens:
- on `WinClosed` (`window/hooks.lua:171-177`)
- in `cleanup_triquetras`, for a window it can't heal, and for a visiting window whose current slot names nothing open or closed (A21)
- in `undo_arrival`, for a window whose current slot turns untracked with nothing to take its place (I10)

The getter never removes one (A2). **[run s15]** recorded `:terminal` in the window dropping the triquetra, before the visiting rule.

Removal also does four things:
- drops the window's history entry, its arrival (below) and its UI cache
- re-points `last_valid_window` along the jump chain
- rebuilds the history view
- clears the winbar

A whole-editor load from idle drops every triquetra at once, outside `unregister_triquetra`: the window domain's teardown clears their winbars, empties `window.data.crux`, `landing` and `arrivals`, and sets `current_window` and `last_valid_window` to the current window (`window/hooks.lua:16-27`, S1). A tab session's load drops only the current tab's triquetras, each through `unregister_triquetra`, before that tab's windows take the file's entries (`storage/routines.lua:1233-1237`, S1 Load), and so does a load with the hint and no file, before the tab starts fresh (`:1196-1200`).

Two other writers:
- `set_buffer_relationship` (`window/init.lua:39-63`) is used by the session load. It takes `primary_enabled` from the saved entry (`:59`; S1, T136). It writes the triquetra directly, not through `register_triquetra`, and gives the window its history entry itself (`:51`, I3) **[code]**.
- `repopulate_window_relationships` (`window/routines.lua:1205-1229`) gives every window with a registered buffer a fresh triquetra, also written directly, not through `register_triquetra` **[code]**. It writes a buffer number into `last_valid_window` (`:1208`). **bug (desk)**

**Arrivals.** `window.data.arrivals[winid]` (`window/data.lua:27-30`) holds the window's last arrival, for I10's undo: the arriving hash, a copy of the triquetra just before it (`remember_arrival`) and a copy just after it (`seal_arrival`) (`window/routines.lua:131-147`). `displacement_mangement` and `reconcile_triquetra` write it whenever the buffer arriving isn't already current (`window/hooks.lua:63-65`, `:125`; `window/routines.lua:326`, `:388`).

**Who writes each slot.** Every writer of each slot, so tests can cover them all:

| Slot | Writers |
|---|---|
| current | getter creation, `c := shown` (M6); plain navigation, `c := X` (A1); `<M-f>`, `c := S` (A6); `<M-S-f>`, `c := T` (A7); primary jump, `c := P`, and while cycling `c := start` (A8); cycling pick, `c := X`, `T` or `S` (A13); cleanup re-point, `c := shown`, and its fallback chains ternary → secondary → `primary[1]` → most recent (A21); the landing after a delete, `c :=` the ternary, the secondary, `primary[1]` or the most recent (A19); `undo_arrival`, `c :=` the current from before the arrival, or the ternary, the secondary or `primary[1]` (I10); a rename (`rename_hash_in_triquetras`): a reopened No Name buffer (M5) or a rename that settles as a move (A20); session load (S1) |
| secondary | `<M-f>`: graduation `s := T`, fill from history `s := ordered[2]`, swap `s := A`, reopen failure on a No Name whose text is lost `s := nil` (A6); plain navigation to the secondary, `s := A` (A1); cycling pick of the secondary, `s := A` (A13); restore secondary `s := remembered`, and restore ternary when it equals the secondary, `s := old t` (A11); cleanup's re-point when the window shows the secondary, `s := old c` (Q18), and cleanup clears it when pruned or when it moves up into the current slot (A21); the landing after a delete clears it when it moves up into the current slot (A19); `undo_arrival` puts back the one from before the arrival, or clears it when it moves up into the current slot, and the untracked buffer leaves it (I10); an empty No Name buffer closed leaves it (M5); a rename (M5, A20); session load |
| ternary | **auto-population**: plain navigation `t := A` (A1), primary jump `t := A` (A8); `<M-S-f>` `t := A` (A7); cycling pick of the ternary `t := A` (A13); graduation `t := nil` (A6); reopen failure on a No Name whose text is lost `t := nil` (A7); restore ternary `t := remembered`, and restore secondary when it equals the ternary, `t := old s` (A11); cleanup's re-point, `t := old c` (Q18), and cleanup clears it when pruned or when it moves up into the current slot (A21); the landing after a delete clears it when it moves up into the current slot (A19); `undo_arrival` puts back the one from before the arrival, or clears it when it moves up into the current slot, and the untracked buffer leaves it (I10); an empty No Name buffer closed leaves it (M5); a rename (M5, A20); session load |
| primary queue | `toggle_primary` on an empty queue (A9); `set_primary` (A10); a popup save replaces it (A18); the primary jump renames a reopened No Name `[1]` (A8); cleanup prunes entries (A21); `undo_arrival` puts back the one from before the arrival, and the untracked buffer leaves it (I10); an empty No Name buffer closed leaves it (M5); a rename (M5, A20); session load |
| `primary_enabled` | `toggle_primary` (A9); `set_primary` (A10); a popup save sets it to "queue not empty" (A18); `undo_arrival` puts back the one from before the arrival (I10); session load takes it from the file (S1) |

The save writes each slot to the file as it is, a No Name current slot included (S1 Save, T213).

### M7. Displacement maps

Each map is keyed by a buffer that was displaced and remembers one slot value for it. Both maps also have `-swap` keys. Who writes which key:

| Key | Value | Written by |
|---|---|---|
| `dtm[X]` | X's ternary at the moment X was left by **plain navigation** | `displacement_mangement` (`window/hooks.lua:92-95`), when the ternary exists and the new buffer isn't the ternary; the same write deletes `dtm[X-swap]`. A cycling pick of an outside buffer X writes `dtm[X] := start` (`window/routines.lua:376-379`, Q9). Cleanup's re-point writes it the same way, when the old current X goes into a ternary other than the buffer the window shows, and deletes `dtm[X-swap]` (`:538-541`, Q18). Also Q6's guard, which rewrites `dtm[T]` to the buffer being left on every route onto the secondary (`window/hooks.lua:73-77`, `window/routines.lua:345-355`), the guard on a pick of an outside buffer (`:363-372`), the stale-note checks (`window/hooks.lua:97-114`; `keep_older_ternary_note` and `check_notes_under_current`, `window/routines.lua:32-48`, `:106-121`), and restore (`:1175`). |
| `dtm[X-swap]` | X's ternary at the moment X was left by a **swap or a primary jump** | every swap onto the secondary, `<M-f>`, its `<M-;><M-f>` fallback, plain navigation onto the secondary and cleanup's re-point onto a shown secondary (`write_secondary_swap_notes`, `window/routines.lua:92-94`, only when a ternary exists; the re-point at `:535`, Q18); `reconcile_triquetra` when the chosen buffer is the ternary (`:335`), which covers `<M-S-f>` and `<M-v>` on the ternary; `jump_to_primary` (`:1037`, which writes nil when there's no ternary). A cycling pick of an outside buffer X deletes it (`:378`, Q9). |
| `dsm[X]` | X's **previous** secondary: the one it had before the secondary it was last left for | on every swap onto the secondary, the secondary's own swap note becomes its plain note when it names a buffer other than the one being left, and otherwise a plain note naming the buffer being left is cleared (`write_secondary_swap_notes`, `:85-91`); the ternary-to-secondary graduation copies `dtm[G]` into `dsm[G]` (`:839-840`), which is intended (Q3); restore (`:1175`); the stale-note check rewrites it to the swap note or drops it (`keep_older_secondary_note`, `:59-71`, A1). |
| `dsm[X-swap]` | X's secondary at the moment X was left for it | every swap onto the secondary: `<M-f>`, its `<M-;><M-f>` fallback, plain navigation onto the secondary (`write_secondary_swap_notes`, `:86`, D8) and cleanup's re-point onto a shown secondary (`:535`, Q18). Graduation clears the graduated buffer's (`:841`). |

- The maps follow along: a note goes once its key, `-swap` keys included, or its value names a hash no longer known through an open buffer, a slot, a primary queue or the closed stack, at the next `cleanup_system` pass or when an empty No Name buffer is closed (`follow_along`, `history/routines.lua:766-821`; P10, I17, T208). A restore also clears a note at a hash with no path when it uses it (A11). `rename_hash_in_triquetras` (`window/data.lua:127-179`) renames keys and values, the `-swap` keys of both maps included (`:151-154`, `:161-165`). `undo_arrival` puts back both maps as they were before an arrival it undoes (I10). The trail gets each note cavediver rewrites or drops by itself, and each file follow along forgets with the notes that went (A27, T407–T410).
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

  - A restore's swap-note fallback compares with the slot it restores into: the ternary for dtm, as today, and the secondary for dsm (A11; `window/routines.lua:1129-1135`).
  - `rename_hash_in_triquetras` carries dsm's `-swap` keys as it already carries dtm's (`window/data.lua:151-154`), so a renamed buffer keeps both kinds of note on both maps (T192).
  - The missing-file rule (D9) covers both maps, swap keys included (T193).
  - Stored with the rest of each map, so the save file's format doesn't change (`storage/routines.lua:535-536`) **[code]**.
  - Built in step 3: the notes (`write_secondary_swap_notes`, `window/routines.lua:82-95`), the check on every arrival (`keep_older_ternary_note`, `keep_older_secondary_note`, `:32-71`) and wherever a slot changes under the current buffer (`check_notes_under_current`, `:106-121`), the fallback, the renames, and D9 on both maps.

### M8. Primary queue

- `primary_buffer[1]` is the primary and the rest are earlier primaries (README:22). The queue isn't deduplicated against the slots, so the primary can also be the current, secondary or ternary (SPEC:44). That's intended: the primary is mobile (Q16).
- `primary_enabled` decides two things:
  - whether `jump_to_primary` uses the queue (A8)
  - whether the UI paints the primary as active (`ui/routines.lua:1080`)
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
- `cycling_origins[winid]` is **the live triquetra table itself**, not a copy. At cycle start its `current_slot` is set to the hash of the window's buffer (`history/routines.lua:1153-1180`) **[run s03]**, as its docstring says (`:1148-1149`, D15).
- `navigation.data.cycling_window` is the window a cycle runs in: `start_cycling` records it and `stop_cycling` clears it (`navigation/data.lua:10`, `:43`, `navigation/hooks.lua:26`, `:38`), and so does the navigation domain's teardown at a whole-editor load from idle (`:18`, S1).
- While history is detached:
  - `BufEnter` neither tracks history nor touches slots.
  - The current slot stays the cycle's starting buffer **[run s03]**. That's intended: it stays there until `<M-v>` (Q1).
  - `nondisplacement_management` (`window/hooks.lua:141-154`) never does anything, because a `BufEnter` context carries no `winid`.
- A whole-editor load from idle ends a cycle left open: the teardowns set navigation to `normal` and history to `attached` directly, with no transition, so no hook runs and nothing is picked (S1, T296).
- **Decided (2026-10-20 evening):** a `WinEnter` into another window cancels the cycle: the cycling window goes back to its start and nothing is recorded (A12). Built in step 3.

### M10. Window-jump history and window tracking

- `navigation.data.window_jump_history[to_win] = from_win` (`navigation/data.lua:42`) is one flat table, across all tabs, as its type comment at `:9` says (D17).
  - It's recorded once each `WinEnter` settles, unless the focus has moved on by then (`navigation/hooks.lua:55-67`, `:79-97`). The "from" window is `winnr('#')`, or `last_valid_window` when there's none, read at the event and passed on as `previous_win`. It's skipped when that window's filetype is `minimap` (`navigation/routines.lua:45-56`).
  - Entries for closed windows stay until a whole-editor load from idle, where the navigation domain's teardown empties the table (`navigation/hooks.lua:19`, S1) **[code]**.
- `window.data.current_window`: the last window entered (`window/hooks.lua:156-159`).
- `window.data.last_valid_window`: the last window with a triquetra (`navigation/routines.lua:102-116`, `window/data.lua:67`). Both are set to the current window at require time (`window/data.lua:181-184`) and at a whole-editor load from idle, by the window domain's teardown (`window/hooks.lua:25-26`). Once a load settles, the focused window becomes both when it has a triquetra (`after_restore`, `storage/routines.lua:1429-1438`; S1, T299). `find_most_recent_tracked_window` returns it only while that window is valid, and the getter gives no triquetra for a window that's gone (`navigation/routines.lua:106-112`, `window/data.lua:81-83`).

### M11. State machines

**Engine semantics** (`engine/state-machine.lua`, `engine/helpers.lua`). These matter for tests.
- `sm:to(next, ctx, mode)`:
  - It deep-copies `ctx`, then sets `ctx.caller` (the machine's name) and `ctx.mode` (`mode` or `"*"`).
  - The transition `current->next` must be registered. It's registered once some hook has been bound to it with `on()`, and stays registered when `off` removes its last hook, so a transition no hook was ever bound to throws `Transition '…' is not registered` from `to()` itself (`state-machine.lua:512-514`).
  - **The new state is set after every hook has run** (`state-machine.lua:519-520`), so `sm:state()` inside a hook returns the old state. A critical hook's failure abandons the transition before that, so the state stays (Errors, below).
- **Pipeline:**
  - Only enabled hooks bound to that exact transition run, sorted by class, lower first.
  - The sort is `table.sort`, which isn't stable for equal classes.
  - General hooks would run before and after; none are registered.
  - The transition is appended to `sm.history`, which grows without limit. The UI loop alone adds about ten entries a second **[run s16]**. That's intended: there's no cap, and the history is there for debugging; nothing in the code reads it (Q21). Measured on 2026-10-20: about 7 entries a second from `ui_loop` while idle (72 in 10 s), and 600,000 entries take about 8 MB, so roughly 8 MB per day the editor stays open.
- **Mode filter** (`helpers.lua:251-291`):
  - `to()` with no mode runs only hooks registered with filter `"*"`.
  - `to(…, m)` runs `"*"` hooks plus those whose filter includes `m`.
- **Errors:** every hook runs inside `xpcall` with `debug.traceback` (`helpers.lua:41-53`). A failure becomes a `vim.notify` ERROR, "Hook '<name>' failed during transition a->b: …" followed by the stack traceback, and the pipeline goes on. The state still changes. The failure is also handed to `on_failure` when it's set (`helpers.lua:50-52`), the flight recorder's dump, which writes it once (A26).
  - A hook marked with `make_hook_critical(name)` (`state-machine.lua:415-422`) isn't notified: its error, the same message and traceback, is re-thrown with `error(message, 0)` to whoever called `to()`. The rest of the pipeline doesn't run and the new state isn't set, so the machine stays where it was; the transition is already in `sm.history`. The only critical hook is storage's save hook (`storage/hooks.lua:17`).
- **Shared modes:** `transition_modes` is a class-level table shared by every machine, so all machines know `cycle`, `winenter`, `delete` and `update` **[run s16]**. That's intended: modes are one vocabulary for orchestrating all machines, and a hook may name any registered mode (Q20). A mode doesn't travel between machines on its own; each `to()` names its own, and today every call passes a mode its target machine registered.
  - **Decided (2026-10-20):** the code says so. The class declares the shared table on purpose, the factory comment (`engine/init.lua:18`, "its own independent state, transitions, hooks, and history") stops implying modes are per machine, and the two checks worded per machine (`helpers.lua:266`, "This state machine doesn't have any transition modes registered", which can't fire with a shared table, and `helpers.lua:284`, "not registered in this state machine") are reworded or dropped. Built in step 8: the class declares the shared table, the factory comment says the modes are one table shared by every machine (`engine/state-machine.lua:110-113`, `engine/init.lua:18-19`), and the two checks read "No transition modes are registered yet." and "Transition mode '<mode>' is not registered." (`engine/helpers.lua:268`, `engine/helpers.lua:286`).
- **Removing a hook.** `off(from, to, name)` removes the hook from each matching transition's own list, walking it from the end so a removal skips nothing (`state-machine.lua:361-367`; T5). `unregister_hook(name)` removes it from its own machine, every transition included, and frees the name (`:386`; T221). DESK:2483 recorded `off()` removing from `self.bindings` by index and `unregister_hook` calling the class instead of the instance, before step 8.

**Machines:**

| Machine | States (initial first) | Transitions in use |
|---|---|---|
| navigation | `normal`, `cycling`, `file_picker` (never entered) | `normal->cycling`, `cycling->cycling` and `cycling->normal` (mode `cycle`); every self-transition (mode `winenter`); `cycling->normal` with no mode, from the window-jump cancel, which runs no hook (A12) |
| history | `attached`, `detached` | self-transitions (`update`/`delete`), `attached->detached`, `detached->attached` |
| ui_bufferline | `bufferline_visible`, `bufferline_hidden` | every transition, self-transitions included, each drawing the UI and the tabline again once its new state is set (`ui/hooks.lua:29-37`, M12) |
| ui_indicators | `indicators_on`, `indicators_off` | the same |
| ui_loop | `self` | `self->self`, which refreshes the UI |
| ui_winbar | `winbar_active`, `winbar_minimal` (`ui/sm.lua:12`, `:26-28`) | the same |
| storage | `bare`, `idle`, `saving`, `loading`, `error`, `auto_saving` | `{idle,bare}->saving`, `idle->bare`, `{bare,idle}->loading`, `{bare,saving,loading}->{idle,saving}`; `idle->loading` is taken only by a tab session's load: a tab session's file, or a load with the hint and no usable file (S1); `error` and `auto_saving` are never used |

At a whole-editor load from idle, the history and navigation teardowns set their machines' states directly, to `attached` and `normal`, with no transition, so no hook of those machines runs (S1).

**Hooks**, in the order they run within each transition:

| Machine | Transition | Mode | Class | Hook | What it does |
|---|---|---|---|---|---|
| navigation | normal→cycling | cycle | 1 | `start_cycling` (`navigation/hooks.lua:22`) | history → detached (mode update), records `cycling_window`, then step once |
| navigation | cycling→cycling | cycle | 1 | `keep_cycling` (`:30`) | step once |
| navigation | cycling→normal | cycle | 1 | `stop_cycling` (`:34`) | history → attached with `{buf = picked, pick = true}` (mode update), clears `cycling_window`, then a UI refresh |
| navigation | *→* | winenter | 1 | `winenter_record_window` (`:55`) | records the window jump, from `previous_win`, read at the event |
| navigation | *→* | winenter | 2 | `winenter_track_current_window` (`window/hooks.lua:156`) | sets `current_window` |
| navigation | cycling→cycling | winenter | 2 | `cancel_cycle_on_window_jump` (`navigation/hooks.lua:45`) | in a window other than the cycling one, once the editor settles: the cycling window back to its start, navigation → normal with no mode, history → attached with the buffer of the jumped-to window's current slot (mode update), then, when the window shows another buffer, attached→attached with it (plain navigation, A1), a UI refresh, and the INFO line, all in `cancel_cycle` (`navigation/routines.lua:128-168`; A12) |
| navigation | *→* | winenter | 3 | `winenter_update_history_view` (`history/hooks.lua:73`) | `construct_crux(find_most_recent_tracked_window())` |
| navigation | *→* | winenter | 4 | `winenter_update_ui` (`ui/hooks.lua:62`) | UI refresh |
| history | *→* | delete | 0 | `handle_deletion` (`history/hooks.lua:42`) | for a registered buffer: close it into its pools (M5) and unregister it, keeping its history; an empty No Name buffer isn't pushed, and is untracked and unregistered (A19) |
| history | *→attached | * | 1 | `attach_history_update` (`:12`) | on update: `update_buffer_history(buf)`, then reorder if it changed, and set `context.history_modified`; on delete: reorder |
| history | *→* | update | 1 | `ensure_curwin_crux` (`window/hooks.lua:29`) | the getter on the current window (creates its triquetra when there's none) |
| history | *→* | * | 1.8 | `cleanup_triquetras` (`window/hooks.lua:37`) | A21, on **every** history transition |
| history | attached→detached | * | 2 | `detach_history` (`history/hooks.lua:35`) | saves the cycling origin and notifies "Checkpoint saved" |
| history | attached→attached | update | 2 | `displacement_mangement` (`window/hooks.lua:47`) | A1, and it remembers the arrival (M6) |
| history | detached→attached | update | 2 | `reconcile_triquetra` (`window/hooks.lua:128`) | A13, and it remembers the arrival (M6) |
| history | detached→detached | update | 2 | `nondisplacement_management` (`window/hooks.lua:141`) | never does anything (M9) |
| history | *→attached | update | 3 | `refresh_ui_attached` (`ui/hooks.lua:49`) | UI refresh if history changed |
| history | detached→detached | update | 3 | `refresh_ui_detached` (`ui/hooks.lua:58`) | UI refresh |
| ui_loop | *→self | * | 1 | `update_ui_state` (`ui/hooks.lua:39`) | `refresh_ui(tracked window)` and `show_ui()` |
| storage | {idle,bare}→saving | * | 1 | `save_history_pre_quit` (`storage/hooks.lua:10`) | `save_history(directory, name, tab)`, the session's directory, name and tab from the context; critical (`:17`), so a failure throws to the caller |
| storage | {bare,idle}→loading | * | 1 | `load_history_pre_start` (`:19`) | `load_history(directory, name)` |
| storage | {bare,saving,loading}→{idle,saving} | * | 1 | `back_to_idle` (`:24`) | nothing |
| storage | idle→bare | * | 1 | `navigation_teardown` (`navigation/hooks.lua:16`) | navigation → normal, set directly; clears `cycling_window` and the window-jump table |
| storage | idle→bare | * | 2 | `window_teardown` (`window/hooks.lua:16`) | clears the winbars, drops every triquetra, empties `landing` and `arrivals`, sets `current_window` and `last_valid_window` to the current window |
| storage | idle→bare | * | 3 | `history_teardown` (`history/hooks.lua:68`) | `teardown()` (S1), then history → attached, set directly |
| storage | idle→bare | * | 4 | `ui_teardown` (`ui/hooks.lua:17`) | clears the window display caches, the display-name cache and the bufferline state, in place |

**Triggers.** All are created by `setup()`, in the `cavediver` augroup, through each domain's `init_autocmds(group)` (`init.lua:192-198`):
- The ledger's, made first, so a step has begun before the other domains act on the same event (`ledger/init.lua:57-121`, A27): `CmdlineLeave` for a `:` line entered, not aborted → a step under its text; `BufEnter`, `BufDelete`, `BufWritePost`, `BufFilePost`, `WinEnter`, `OptionSet` of `buftype` and `TabClosed` → an event, a step of its own, or listed under the step still open; none about the flight recorder's dump, its buffer or its window (A26).
- `WinEnter` → a navigation self-transition with mode `winenter`, once the editor settles, carrying the window the jump came from as `previous_win`, read at the event; skipped when the focus has moved on by then (`navigation/hooks.lua:79-97`).
- `BufEnter` → a history self-transition with `{buf}`, mode `update`, once the editor settles and inside the event's window (`nvim_win_call`); skipped when the window or the buffer is gone or the window shows something else by then, when history was detached at the event (a cycle's step) and isn't any more, and when a session loaded since the event (`history/hooks.lua:213-246`, A1, S1). Neovim's own pick in a window whose buffer is being deleted is left out at the event (A19).
- `BufDelete` → a history self-transition with `{buf}`, mode `delete`, unless `b:skip_bufdelete` is set. A registered No Name buffer is noted first, with its history, for a write under a name in the same batch (`:167-188`, A20).
- `BufWritePost` → once the write settles, the rename of a No Name buffer written under a name, claimed at the event, or else an update for an unregistered buffer (`:190-210`, A20).
- `BufFilePre` → records a registered buffer's old hash, and `BufFilePost` → settles the rename once the editor settles (`:249-281`, A20).
- `FocusGained`, `ShellCmdPost`, `TermLeave` and `DirChanged`, the settle points → the label is read again, and every known file is checked against the disk and tagged with the label when it's gone (`refresh_label`, then `mark_missing` unless a change of label just checked every file; `history/hooks.lua:146-154`, M14).
- `BufNewFile` → the file is marked as never written, so it isn't tagged as gone (`history/hooks.lua:156-164`, M14).
- `WinClosed` → drop the window's history entry (`history/hooks.lua:284`), drop its triquetra (`window/hooks.lua:171`), and the popup cleanup, which runs `once` (`ui/hooks.lua:197`).
- `OptionSet` for `buftype` → once the editor settles, a registered buffer that's no longer trackable has its arrival undone (`window/hooks.lua:179-196`, I10).
- `BufAdd`, `BufDelete`, `BufFilePost` and `BufWritePost` → clear the display-name cache (`ui/hooks.lua:78`).
- `VimResized` → a debounced UI refresh (`:85`).
- `BufModifiedSet` → a UI refresh (`:92`).
- `FileType cavediver-primary-buffer-history` → the popup's keymaps (`:99`).
- `FileType cavediver-closed-lists` → the closed lists' keys, from `keymaps.views` (`ui/hooks.lua:163-194`, S2 Closed-stack picker).
- `SourcePost` on a `restart_session_*` file while `v:startreason` is `restart` → the last load of this startup runs again once the editor settles, ignoring the repeat flag, and with the hint when that load had it, naming the tab that's current then (`storage/init.lua:121-138`, S1).
- `TabClosed` → each tab that's gone leaves its tab session's pool; a pool left with no tab has its session's records written into its file on the next tick and is dropped, or is kept with no tab and a WARN when they can't be written; a detached pool goes into the whole editor's file instead (M5) (`close_tab_pool`; `storage/init.lua:140-158`; M5, S1 Records).
- `VimLeavePre` → every known session's records are written at once, changed or not (`storage/init.lua:162-167`, S1 Records).
- `TextChanged` and `TextChangedI` on a registered No Name buffer → every pool's session is marked changed, so the text is written with its records (`storage/init.lua:168-178`, S1 Records).

The popup's own `BufDelete` and `BufWriteCmd` are buffer-local, made each time it opens, outside the group (`ui/routines.lua:198-209`, `:211`). So are the closed lists' `BufWriteCmd`, `TextChanged`, `TextChangedI` and `BufWipeout` (`ui/routines.lua:804-832`). So is the one-shot `BufWinEnter` that gives a reopened No Name buffer its cursor (`history/routines.lua:1213-1219`, and `storage/routines.lua:766-772` for one reopened at a load; M5).

The watch on git's HEAD, an `fs_event` on the git directory, isn't an autocmd: with no `label_provider`, `refresh_label` arms it the first time it runs after `setup()`, and `disable()` stops it until `setup()` runs again (`history/routines.lua:709-727`, `:738-742`; M14, A25).

**Timers.** These start in `setup()`. Each keeps its handle, so running `setup()` again stops it before starting it, and `disable()` stops both (`history/init.lua:40-46`, `ui/init.lua:92-98`):
- `cleanup_system` runs every `cleanup_interval` ms, with the first tick at once (`history/init.lua:54-63`). The timer calls it as `cleanup_system(true)`, as a step of the ledger's own, so each repair is a move in the trail and nothing is said (`history/init.lua:60`; A22, A27, M14). Its check of the disk takes the files a slice at a time.
- The UI refresh runs every `winbar_refresh_interval` ms through a 100 ms debounce (`ui/init.lua:105-120`, `ui/routines.lua:1593-1608`), which comes to about every 140 ms.

One more timer doesn't start in `setup()`: the records' timer, a one-shot of a second, started by the first change to a session's records and again by the first change after it has run out. When it runs out, the changes made during that second are written. A load on the whole editor's route and `disable()` stop it (`records_changed`, `storage/routines.lua:2160-2184`; `drop_pending_records`, `:2193-2200`; S1 Records).

Neither `setup()` nor a load starts a one-shot delay of its own: what a load leaves for later runs once the restore's batch is over, as settle work (`after_restore`, S1, and below); the repeat flag's clearing stays a plain `vim.schedule`, since running it early would let a native restore load twice.

**Settle work** (decided 2026-10-24; the author: "why don't we do a lock? and if it's locked we queue. When we schedule something, we do some locking.", then "Drain it, then act", "is the queue general? we should design it general. who knows maybe we will add new things in the future..", and "Yes, cancel under the jump"). What cavediver puts off until the editor settles and that changes what it knows about the editor goes through one queue, `lua/cavediver/settle.lua`; while anything is queued, cavediver isn't settled:
- `settle.later(name, fn)` queues `fn` under a name and schedules it to run by itself once the editor settles; whichever runs it first, a drain or its schedule, the other finds it done.
- `settle.drain()` runs everything queued, oldest first, work queued meanwhile included; an item that throws is reported as a scheduled one is, and the rest still run. It does nothing inside a key or a running item.
- `settle.guard(fn)`, for a key: drain, then the key's job, with no drain starting until it's done, so a key's own queued work keeps its order (the close key's delete after its switch's arrival, T336).
- `settle.pending()`: the names still queued, which a dump lists (A26).
- In it: an arrival, a write and a rename settling, a No Name buffer's note dropped, a window entry and the cycle's cancel it queues, the `buftype` undo, the landing after a delete, the close key's delete, and a load's follow-up. Out of it, plain `vim.schedule`: the ledger holding a step open, the dump's window and notices, the UI's redraws, the records' writes, the load's repeat flag, and `:restart`'s reload.
- Every key goes through it: cavediver's mappings drain before their step begins, so drained work lands on the step it belongs to, as typed by hand, and each key's export goes through `guard`, so a user's own mapping calling the exports does too (A12). Mine: the closed lists' and the trail's keys that begin a step do the same.
- Built in step 8 (T461, T464–T467): `settle.lua`, `later`, `drain`, `guard` and `pending` (`settle.lua:55-61`, `:69-76`, `:86-95`, `:100-106`), each item run once (`run`, `:26-45`); the ten sites (`history/hooks.lua:181`, `:196`, `:227`, `:277`; `navigation/hooks.lua:50`, `:90`; `window/hooks.lua:186`; `window/routines.lua:404`; `history/routines.lua:1535`; `storage/init.lua:76`); the mappings' `begin_key` (`init.lua:37-40`), the exports' block (`init.lua:543-556`), and the closed lists' and the trail's keys (`ui/hooks.lua:175`, `ui/trail.lua:936`).

### M12. UI

**Winbar.** Written for every triquetra window that passes `is_real_file` or `is_visiting` (`ui/routines.lua:1551-1581`). `is_real_file` (`:1448-1473`) holds when:
- not a float
- `buftype` is `""`, `terminal` or `acwrite`
- loaded
- no `://` in the name unless the buffer is `acwrite`
- filetype not on the skip list, config's `winbar.skip_filetypes` (`ui/data.lua:225-227`, M13)

`is_visiting` (`ui/routines.lua:1484-1489`) holds when the shown buffer isn't registered, it's loaded, the window isn't a float, and the filetype isn't on the exclusion list.

The string, as rendered **[run s14]**:

```
────── ⦉T⦊ [C] current-name <arrow-glyph>  ⟦S⟧ secondary-name ─────…
```

- The ternary shows as `⦉N⦊ ` when it's open, or `⦉ <icon> name ⦊ ` when it's closed.
- The current shows as `[N] name`, or `⦉N⦊ name` when it's the primary. A glyph follows when the buffer is modified.
- While visiting, the current piece reads `[N] name ← [<id> <type>]`: `<id>` is the shown buffer's number, and `<type>` its `buftype`, or its filetype when the `buftype` is `""` or `acwrite`, so oil shows `[<id> oil]`; a terminal's is `terminal: <command>`, the command's first word's last part, taken from its `term://…//<pid>:<cmd>` name (`visit_label`, `ui/routines.lua:28-38`, `:1061`; T268). A closed current slot, allowed only while visiting, shows the closed icon where the number goes: `[<icon>] name ← [<type>]` (`:1293-1302`, T270).
- The secondary shows as arrow, `⟦N⟧ name` (`⦉N⦊` when it's the primary), or arrow, icon, name when it's closed.
- A slot whose file is gone from disk has its tag right after its piece, dimmed: `%#Comment#⎇<tag> ` after the ternary piece, after the current piece and after the secondary piece (`missing_tag`, `ui/routines.lua:1259-1266`, called at `:1285`, `:1300`, `:1339` and `:1371`; M14, T343). While visiting, the current slot's tag comes after the visit, not after the name: `[N] name ← [<type>] ⎇<tag>`. The tags come from the window's UI cache (Caches, below).
- The padding fills the window's width.
- Highlights come from the `focused`, `unfocused` and `topwin_overlapped` themes (`ui/data.lua:74-108`); a top window that overlaps the focused window takes its focus colours (`ui/routines.lua:1396-1427`).
- The primary is matched by **display name**, not by hash (`ui/routines.lua:1233-1253`).
- While cycling, the current name uses the base highlight (`:1229-1231`).
- The winbar is set to `""` when the triquetra is dropped (`window/data.lua:72`) or when the current buffer can't be resolved (`ui/routines.lua:1304-1318`).

**Bufferline.** Cavediver doesn't draw it. It hands cokeline its callbacks (`ui/init.lua:224-655`):
- `bufnr_is_displayed`: the bufferline state is visible and the buffer is in the "recent" set. That set is every buffer in the ordered history, `math.max(#ordered)` (`ui/routines.lua:1145`): the bufferline shows every tracked buffer (Q5). **Decided:** `math.max` stays (2026-10-20), and the 30, which meant nothing there, goes (2026-10-21). Built in step 8.
- `compare_buffers`: by time in the history view, newest first.
- colour callbacks:
  - The text colour goes by the buffer's role, in the order primary, secondary, current, ternary, focused, harpooned, other (`ui/init.lua:308-328`).
  - The background turns the "detached" colour while history is detached (`:333-347`).
- components:
  - `[N]` for the current, `⟦N⟧` for the secondary, `⦉N⦊` for the primary or the ternary.
  - The harpoon mark and `⥤ {n}` label.
  - The index is dimmed when the primary is disabled (`:389-610`).
  - `⎇<tag> ` after the file name, in the `Comment` colour, for a buffer whose file is gone from disk (`missing`, `:418-426`, placed at `:602`; M14).
- `get_buffer_relationships(buf)` gives the buffer's roles in the current window. The primary is mobile, so it may be any slot's buffer too, and only the current, secondary and ternary are one role each: two of those throw "A buffer cannot have more than one role" (`ui/init.lua:249-288`, `:266`; T119). Nothing calls it, neither cavediver nor the author's config. **[run s14]** recorded it throwing when the current buffer was also the primary, before step 8. **Decided (2026-10-20):** the one-role assertion is fixed or the function removed (Q16). Built in step 8: fixed.

**Caches:**
- `bufferline_state` is computed by `refresh_ui` for the tracked window (`ui/routines.lua:1110-1160`), and it requires harpoon.
- `window_display_cache[winid]` is set for every triquetra by `cleanup_triquetras` (`window/routines.lua:770`). Deriving it first checks the window's slots: when any slot's registered buffer is no longer valid (wiped without events), it runs `cleanup_system` at once, as the cleanup's step in the ledger (A27), so the registry and the window are repaired within one refresh (`ui/routines.lua:990-1007`, A22, T242). The cache also holds `deleted_slots.current`; `visiting`, the shown buffer's type while visiting (`ui/data.lua:23`, `:40`); and `missing`, each slot's tag as `{current, secondary, ternary}`, read from the history domain's tags at each derive (`ui/routines.lua:1072-1077`, M14). A current slot with no open buffer sends the derive path to cleanup, unless it's a closed slot while visiting. It retries once, counted by a parameter, and when the slot still has no open buffer it raises "Impossible state: current_bufnr is nil …" (`ui/routines.lua:1082-1091`).
- `display_name_cache` is cleared on `BufAdd`, `BufDelete`, `BufFilePost` and `BufWritePost`.
- At a whole-editor load from idle, the UI domain's teardown clears `window_display_cache`, `display_name_cache` and `bufferline_state` in place (`ui/hooks.lua:17-27`, S1).

**Decided, and the UI's lists (DESK:2113-2119, DESK:2144, DESK:2148-2158; 2026-10-20, 2026-10-21, 2026-10-24), built in step 8 but where a point says otherwise:**
- **The winbar is cavediver's by default, and also offered as a component** (decided 2026-10-20): a setting stops cavediver writing any window's winbar, at the refresh, when a triquetra goes, when the current buffer can't be resolved and at a load's teardown, and a function returns a window's triquetra segment for heirline, lualine's winbar or dropbar to place (T447). Mine: the setting is `winbar.own`, `true` by default, and the function `require('cavediver').winbar_segment(winid?)`, the current window's when none is given: the segment without the rule and the padding around it, in statusline format, `%#Group#` highlights included, or `""` while the winbar is hidden or the window has none.
- **The winbar's filetype skip list is configurable**, today's names its default (decided 2026-10-20; T448). Mine: `winbar.skip_filetypes`.
- **The toggles get built** (decided 2026-10-21): `hide_winbar()` and `show_winbar()`, `hide_indicators()` and `show_indicators()`, and `hide_bufferline()` and `show_bufferline()` switch them at runtime, and a hidden winbar stays empty through the refresh (T220, T123). They're reached by three commands, `:CavediverWinbar`, `:CavediverIndicators` and `:CavediverBufferline`, each taking `on`, `off` or `toggle`, with no keymap entries (the author, 2026-10-24: "Commands only", "The three commands; no keymap entries."; T446). Mine: a command with no argument toggles; the winbar's machine is `ui_winbar`, as the UI's states module and `hide_winbar` already name it; a hidden bufferline displays no buffer; and the indicators are the bufferline's marks, the only things the code's history ever called indicators (the archived STATUS's "triquetra role indicators" and "Harpoon indicators with position numbers"), shown by default.
  - **Decided (2026-10-24), indicators by kind** (the author: "Role marks only", then "It should be granular at least", then "Per kind of mark"): two kinds, each switched on its own: `roles`, the role marks `[N]`, `⟦N⟧` and `⦉N⦊`, and `harpoon`, a marked buffer's mark and its `⥤ {n}` label. `:CavediverIndicators roles off` hides the role marks and keeps the marks of marked buffers, `:CavediverIndicators harpoon off` the other way round, and with no kind both (T456). Mine: `hide_indicators(kind?)` and `show_indicators(kind?)`, and `is_hidden("indicators", kind?)`, every kind when none is named; the machine is `off` once every kind is hidden. Built in step 8 (`set_indicators`, `ui/init.lua:165-173`; `is_hidden`, `:203-215`; the index, `:457-458`; the file name's label, `:520`; the commands' kinds, `init.lua:212-234`).
- **The pick letter's colours come from the config**, `colors.cokeline.is_picking_close` and a new `is_picking_focus`, `#4385BE` by default (D2; T168).
- **Marked buffers come from an optional provider** (decided 2026-10-20; T215, T450): with none set, the marks are harpoon's list when `pcall(require, "harpoon")` works, and nothing otherwise. Mine: `marks_provider`, a function returning the marked files' paths in order, each relative to the current directory or absolute; `false` marks nothing.
- **The primary's set and toggle redraw** the status lines and the tabline, `redrawstatus!` and `redrawtabline`, in place of `redraw!`, which repaints the whole screen (DESK:2119, DESK:2487; T451). Mine: the tabline too, since cokeline draws the primary's colour there.
- Built in step 8: every winbar write goes through one place, which writes nothing when `winbar.own` is false and an empty winbar while it's hidden, and keeps each window's segment either way (`put_winbar`, `ui/routines.lua:1193-1199`, called at `:1316` and `:1382`; `remove_winbar_string`, `:1386-1391`); `winbar_segment` reads it (`ui/routines.lua:1207-1213`, `init.lua:581`). The skip list is the config's (`ui/data.lua:225-227`, `configs.lua:332-355`). The toggles: the winbar's machine (`ui/sm.lua:12`, `:26-28`), every transition of the three drawing the UI and the tabline again once its state is set (`ui/hooks.lua:29-37`), the commands (`init.lua:212-234`), the index's role marks and the file name's label off while their kind is (`ui/init.lua:457-458`, `:520`). The pick colours (`ui/init.lua:443`, `:445`; `configs.lua:260`). The marks (`marked_paths`, `history/routines.lua:1087-1107`, read by the bufferline's refresh and the history's unmarked list). The redraws (`window/routines.lua:1069-1070`, `:1098-1099`). A list in the user's config replaces the default list whole, so a skip list can drop a default name (`init.lua:175-176`, M13).
- **`zsh:terminal`**: DESK:2486's fix takes the command from any `term://…//<pid>:<cmd>` name, for the winbar's `zsh:terminal` → `terminal:` rewrite, which went in step 8. Under the visiting rule no terminal's name reaches the winbar: a tracked window showing a terminal reads `[N] b.txt ← [terminal]`, the visit's locked format (T268), so the rewrite never matches **[run 2026-10-24]**. **Decided (2026-10-24):** the command moves into the visit (the author: "Show the command"), and the rewrite goes (below).
- **The visit names what's visited** (decided 2026-10-24): the visited buffer's id leads the visit's brackets, on every visit, and a terminal shows its command, taken from any `term://…//<pid>:<cmd>` name: `[N] b.txt ← [14 terminal: zsh]`, `← [15 help]`, `← [16 oil]` (the author: "Show the command", note "we can also put the buffer ID as well!", then "Every visit" and "Yes, inside"; T268). Mine: the command is its first word's last part, `/bin/zsh -l` reading `zsh`. Built in step 8 (`visit_label`, `ui/routines.lua:28-38`), and the rewrite is gone.
- **A window with no current slot gets the visit alone** (decided 2026-10-24): a window born untracked, a `:help` split, `:copen`, a terminal split, gets a winbar of what it shows, `[<id> <type>]`, centred, in a colour of its own, `colors.visit_bar`, and only where its winbar is empty or one cavediver wrote, never over another plugin's (the author: "The visit alone", note "We center it, and different coloring these time? What do you think?", then "Centred, its own colour"; T457). Mine: the colour has a focused and an unfocused shade, as every winbar follows focus; floats, the command-line window (a window Neovim types `command` or `autocmd`), the skip list's filetypes, `winbar.own = false` and a hidden winbar draw none, and a bar cavediver wrote goes once its window stops qualifying, unless something else wrote over it. Built in step 8 (`update_visit_bars`, `ui/routines.lua:1512-1549`, run after the slot winbars at `:1580`; `WinbarVisit` and `WinbarVisitNC`, `ui/init.lua:37-38`; `colors.visit_bar`, `configs.lua:254-257`).
- **The colour callbacks on a dashboard start** (DESK:2498, to verify): called directly with nothing tracked, `get_theme_fg_color`, `get_theme_bg_color` and `get_buffer_bold` raise their assertion, "This should not happen: No current triquetra found.", as designed. Through cokeline they aren't reached with the README's setup, whose `filter_valid` is `bufnr_is_displayed`: on a start in a `nofile` dashboard, and with a file then entered in a float, it's false for every buffer, so cokeline draws none and calls none of them **[run 2026-10-24]**. A setup that draws every tracked buffer would reach them in the float's case, where a buffer is tracked and no window has a triquetra. Not reproduced, and the assertion stays.

**Smart basename** (`ui/routines.lua:923-973`):
- the basename, or the shortest path suffix that's unique among buffers with the same basename; a closed file's own unlisted buffer doesn't count (T118)
- `[No Name]` for an empty name
- `[<buftype>]` for a special buffer
- It throws for a hash with no path.

### M13. Configuration

Defaults are in `configs.lua:105-363`. `setup(user)` deep-merges the user's table into the defaults, a list replacing the default list whole (`init.lua:175-176`, mine, step 8), and throws on a type mismatch (`init.lua:171-187`). `setup()` with no argument merges an empty table, so it uses the defaults (`user_config or {}`, `:187`; T125). **[run s13]** recorded it throwing `bad argument #1 to 'pairs'` without the `or {}`.

| Key | Default | Used by |
|---|---|---|
| `session_dir` | `stdpath("data") .. "/cavediver/sessions/"` | `storage/routines.lua:876` |
| `bufferline.history_view` | `"global"` | `history/routines.lua:914` |
| `primary_buffer_history_popup.{height,width}` | `0.2`, `0.7` (a ratio when ≤ 1, otherwise cells) | `ui/routines.lua:232-246` |
| `colors.*` | Flexoki-like hex values; `colors.trail`, the closed lists' and the trail's, its fill shaded in `wave` (today, a week, a month, older), and a search's life line in `life_open`, `life_closed` and `life_gone`; `colors.cokeline.is_picking_close` and `is_picking_focus`, the pick letters', the second `#4385BE`; `colors.visit_bar`, the visit-alone winbar's, focused and unfocused | highlights `ui/init.lua:33-86`, bufferline callbacks |
| `keymaps.*` | see the action table in section 3; `keymaps.views`, the keys inside cavediver's own views, `leave_too` (`<C-c>`, mine) leaving as `leave` does (S2 Closed-stack picker, A27), and the trail's `search` (`s`) and `search_word` (`*`) (A27) | `init.lua:44-155` |
| `winbar.own`, `winbar.skip_filetypes` | `true`; today's sixteen filetypes, neo-tree's, notify's, dropbar's and the rest | `ui/routines.lua:1193-1199`, `ui/data.lua:225-227` (M12) |
| `toggle_window.skip_filetypes` | `{ "minimap", "neominimap" }` | `navigation/routines.lua:49` (A17) |
| `marks_provider` | none: only a comment, and nil means harpoon's list when it's installed. A function gives the marked files' paths in order; `false` marks nothing | `history/routines.lua:1087-1107` (M12) |
| `label_provider` | none: there's no default entry, only a comment (`configs.lua:328-329`), and nil means the label is git's, read from `.git/HEAD`. A function is called for the label, which is its string result; `false` turns labels off, so a tag is the time | `history/routines.lua:578-587`, `:738-742` (M14) |
| `closed_lists_popup.{height,width}` | `0.5`, `0.7` (a ratio when ≤ 1, otherwise cells) | `ui/routines.lua:834-836` |
| `trail_popup.{height,width}` | `0.8`, `0.8` (a ratio when ≤ 1, otherwise cells) | `ui/trail.lua:885-961` (A27) |
| `trail.header` | `{ tally = true, gauge = true, shade = true }`: the trail's header pieces, each on or off | `ui/trail.lua:241-316` (A27) |
| `glyphs` | `set = "unicode"`, and the two sets themselves, `unicode` and `ascii`, every glyph and bracket pair, a glyph changed inside its set, `glyphs = { unicode = { row_t = { "<", ">" } } }` (the author, 2026-10-24: "Yes, this layout", after "put the brackets, "<" and ">", in as well in configs.lua"; T458). `set` picks one, and a glyph named at the top, outside the sets, replaces the set's: the closed lists' (`list`, `closed`, `tag`, `more`) and the trail's (its title, fills, gauge, branches, folds, a step's cause by name, a move's kind by name, a search's mark `search` and its life line `life`) | `configs.lua:126-156`, `ui/routines.lua:287-296` |
| `formatters` | `{}`: `closed_entry`, a function of the closed entry and the glyphs, gives the virtual text after an entry; `trail_step`, `trail_move` and `trail_header` give the trail's lines (A27). Each gives `{text, highlight}` chunks, or nothing for cavediver's own | `ui/routines.lua:407`, `ui/trail.lua:281`, `ui/trail.lua:423`, `ui/trail.lua:499` |
| `cleanup_interval` | `4000` milliseconds | `history/init.lua:58` |
| `winbar_refresh_interval` | `140` ms | `ui/init.lua:115` |
| `ledger.ring` | `1000`: how many of the last steps the ring keeps | `ledger/routines.lua:255` (A27) |
| `ledger.dump` | `true`: whether something that shouldn't happen writes its last steps to a file and a window; `false` records the ring and dumps nothing | `ledger/dump.lua:79-81` (A26) |

### M14. Missing files tagged

**Today.** The tags are `history.data.missing`, hash → tag, the files never written are `history.data.unwritten`, and the label recorded is `history.data.last_label` (`history/data.lua:98-104`).
- **What's checked** (`mark_missing`, `history/routines.lua:604-670`). Only files cavediver knows, those of open buffers, slots, primary queue entries and the closed stack (`known_filehashes`), and never a `NONAME_` name. A file that isn't readable is tagged, unless it's tagged already: with the label the check is given, or with the time as `HH:MM` when there's none (`:607-626`; T343, T344). A file that was never written isn't tagged, since it didn't go missing: a file Neovim opens as a new one (`BufNewFile`, as `:e brandnew.txt` does) is marked unwritten, and so is a name a rename gives that isn't on disk (`history/hooks.lua:156-164`, `:101-104`); a check that finds it readable clears the mark, and once it's on disk it's tagged like any file when it goes (T348). A readable file's tag is cleared (T343), and so are the tag and the mark of a hash no longer known (`history/routines.lua:660-669`) **[code]**.
- **The label** (`current_label`, `history/routines.lua:578-587`) follows `label_provider` (M13). With none, it's git's (`git_label`, `:559-570`): `.git` is found upward from `getcwd(-1, -1)`, and a `.git` file's `gitdir:`, as a worktree has, is followed (`git_dir`, `:534-551`) **[code]**; then HEAD is read as a file, with no git binary. `ref: refs/heads/<b>` gives `<b>` (T343); another `ref:` gives the ref, and a detached HEAD its first 7 hex characters **[code]**. With no `.git` found, there's no label (T344). A function is called inside a `pcall`, and its string result is the label (T345); anything else is no label. `false` means no label.
- **The label being left** (`refresh_label`, `history/routines.lua:737-755`). It reads the label again. The first label it sees only starts the record. After that, when the label changed, every known file is checked, and the ones gone are tagged with the label being left, the one recorded before; then the label just read is recorded (T343). Every other check tags with the label recorded at the time, which is where you are: a file deleted on disk with no change of label is tagged with the label you're on. Files that go missing together get the same tag; nothing else records a batch.
- **When it runs.**
  - The watch. With no `label_provider`, `refresh_label` watches the git directory, not HEAD itself, since git writes HEAD to another file and renames that over it. It's armed the first time `refresh_label` runs after `setup()`, which is usually the cleanup timer's first tick, at once. An `fs_event` filtered to the file name `HEAD` runs `refresh_label` once the editor settles (`watch_head`, `history/routines.lua:709-727`; T343). The watch moves when `refresh_label` finds another git directory from the global cwd **[code]**. `disable()` stops it, and nothing arms it again until `setup()` runs again, a save's or a load's pass included (`enable_head_watch`, `:694-699`; A25, T346). With a `label_provider` set, there's no watch, and one already running stops (`:738-742`) **[code]**.
  - The settle points, `FocusGained`, `ShellCmdPost`, `TermLeave` and `DirChanged`, run `refresh_label` and then check every known file, unless a change of label just did, whatever the provider, git's included (`history/hooks.lua:146-154`, M11). `FocusGained` is run by the cases (T343); the other three are **[code]**.
  - Every `cleanup_system` pass does the same, after follow along (`history/routines.lua:1761-1763`, A22). A timer tick checks the open buffers and every slot and primary queue entry each time, and the rest 500 at a time, going round a snapshot of the path registry's keys (`:627-654`) **[code]**. A save, a load and the UI's on-the-spot repair check every known file.
- **Shown** dimmed, `⎇<tag>`, after its slot's piece in the winbar, and after the file name in the bufferline, which shows open buffers only (M12, T343). The trail gets each tag and each tag cleared, and a change of label is a step of its own, the tags it finds under it (A27, T418).
- **Sessions.** The save writes the tags, `missing`, the label recorded, `label`, when there is one, and the files never written, `unwritten`, when there are any. The load puts them back, so the first pass after it tags what's gone with the label the session was saved on (S1 Save and Load, T347). A whole-editor load from idle forgets them first (S1). A tab session's file holds only the tags and the marks of the files it references; its load adds its tags, keeping a tag already there, and its marks, and leaves the label recorded as it is (S1 Load).

**Decided (2026-10-20; DESK:2024-2027):** files that go missing together are marked as a batch, tagged with where you were when they went missing, through a VCS-agnostic core and a label provider in config. The built-in provider reads `.git/HEAD` with no git binary, watches it, follows worktrees and gives a short hash on a detached HEAD; another VCS plugs in its own; with no label, the tag is the time. Cavediver remembers the last label it saw and tags each batch with the label being left; for a provider it can't watch, it refreshes the label at settle points (focus gained, a shell command finishing, leaving a terminal). The tag shows dimmed in the winbar, the bufferline and the picker, `new_api.lua ⎇feature`, and clears when the file comes back. It means "went missing when leaving `feature`", not "exists on `feature`". Built in step 6: the tags, with the time when there's no label; the label provider, git's by default, with its watch on HEAD; the settle points; and the tag in the winbar and the bufferline (T343–T347). Built in step 7: the tag in the picker (S2 Closed-stack picker, T373).

Cases: T343–T348.

## 3. User actions and editor events

### Coverage

Every default keymap (`configs.lua:281-321`, bound in `init.lua:44-155`) and every export in `init.lua`:

| Export (init.lua) | Default key | Action |
|---|---|---|
| `toggle_secondary` (`:485`) | `<M-f>` | A6 |
| `toggle_ternary` (`:490`) | `<M-S-f>` | A7 |
| `jump_to_primary` (`:495`) | `<M-;><M-f>` | A8 |
| `toggle_primary` (`:528`) | `<M-;><M-x>` | A9 |
| `set_primary` (`:538`) | `<M-;><M-c>` | A10 |
| `restore_ternary` (`:500`) | `<M-;><M-r>` | A11 |
| `restore_secondary` (`:505`) | `<M-;><M-t>` | A11 |
| `cycle_left` / `cycle_right` (`:511`, `:513`) | `<M-n>` / `<M-m>` | A12 |
| `cycle_select` (`:516`) | `<M-v>` | A13 |
| (no cancel) | — | A14 |
| `delete_buffer` (`:533`) | `<M-.>` (`close_buffer`) | A15 |
| `reopen_last_closed` (`:482`) | `<M-S-w>` | A16 |
| `toggle_window` (`:515`) | `<M-,>` | A17 |
| `open_primary_buffer_history` (`:518`) | `<M-;>F` | A18 |
| `open_closed_lists` (`:519`) | `<M-;>W` | S2 Closed-stack picker |
| `ledger` (`:27`): `steps()`, the ring, and `trail(day)`, a day's steps that made moves | — | A27 |
| `open_trail(name?)` (`:523`) | — | A27, `:CavediverTrail [name]`, a name opening on its life line |
| `replay_dump(path)` (`:520`) | — | A26, a dump replayed into a fresh editor in its project |
| `save_session` / `load_session` (`:478-479`) | — | S1 |
| `setup` (`:168`), `disable` (`:467`) | — | M13, A25 |
| `get_storage_state`, `get_navigation_state`, `get_history_state`, `is_cycling` (`:557-573`) | — | A24 |
| `get_buffer_history`, `get_window_triquetra`, `get_all_triquetras`, `set_cache_from_window_triquetra` (`:575-582`) | — | A24 |
| `get_smart_basename` (`:580`) | — | A24: the UI's own (`ui/routines.lua:923`, T120). **[run s16]** recorded it nil, before step 8 |
| `bufferline` (`:627`) and the domain tables `navigation`, `history`, `window`, `ui`, `storage`, `engine` (`:113-118`) | — | M12, A24 |
| user commands `:CavediverHistoryData`, `…NavigationData`, `…WindowData`, `…UIData`, `:CavediverTriquetra`, `:CavediverRegistry`, `:CavediverTriquetraVerbose`, `:CavediverAllTriquetras` (`init.lua:244-458`) | — | A23 |

The editor events: A1 (navigating to a tracked buffer), A2 (a window showing something untracked), A3 (entering a window), A4 (a new split), A5 (closing a window), A19 (any buffer delete), A20 (renames and writes), A21 (`cleanup_triquetras`), A22 (`cleanup_system`), and M14 (the settle points and the watch on git's HEAD).

Most slot actions notify, and the messages are quoted where a test may want to check them. The silent ones are a successful `<M-f>` or `<M-S-f>` swap, the normal path of `jump_to_primary`, `toggle_primary` and `set_primary`. Most slot actions also end with a UI refresh (`loop_sm:to(SELF)`). `jump_to_primary` and the early returns of both swaps don't, and the UI catches up through the `BufEnter` that follows.

---

### A1. Navigating to a tracked buffer (`BufEnter`, history attached)

**Trigger.** `BufEnter` for buffer X in window W, whose triquetra is `{c=A s=S t=T}`. Once the editor settles, and only if W still shows X, the pipeline runs inside W (`nvim_win_call`), so W is the current window for every hook, whichever window has the focus (`history/hooks.lua:223-244`; T224, T250). An arrival queued before a session load is dropped when it settles: the restore's own events are noise the load replaces (`:226`, `:238-240`; S1). It's history `attached→attached`, mode update (M11):
1. track X (sets `history_modified`)
2. `ensure_curwin_crux`
3. `cleanup_triquetras` (A21)
4. `displacement_mangement`
5. UI refresh

**Today** (`window/hooks.lua:47-126`), when `history_modified` is true and X is registered:

| Case | After | Map writes |
|---|---|---|
| X = A | unchanged | none |
| X = S | `{c=X s=A t=T}` | the notes `<M-f>` writes, `dsm[A-swap] := S` and, with a ternary, `dtm[A-swap] := T` (D8, M7); Q6's guard before the swap |
| X = T | `{c=X s=S t=A}` | none |
| anything else | `{c=X s=S t=A}` | `dtm[A-swap] := nil` and `dtm[A] := T`, only when T exists |

Every case but X = A then runs the stale-note checks below.

- **"Duplicates detected in current triquetra".** When S and T are both set and equal, the hook throws this before any slot changes (`:85-91`). The error is caught (M11), so **the slots aren't updated at all** and the window shows X while `c` is still A **[run s18]**.
- **The stale-note check in navigation.** When `dtm[X] = A`, so that X's remembered ternary is the buffer being left, `dtm[X]` is rewritten to avoid a cycle, with a WARN (`:97-114`):
  - If T = X: `dtm[X] := dtm[A]`, "…switching with the pre-jump stored ternary."
  - Otherwise: `dtm[X] := T`, "…switching with the pre-jump ternary." **[run s18]**: at b with `t=d` and `dtm{a→b}`, `:e a` gives `{c=a t=b}`, `dtm{a→d, b→d}`.
- The map writes of the other cases happen only while navigation is `normal`. The slots move, and the route onto the secondary writes its notes, in any navigation state (`:84`, `:121-122`). In practice cycling detaches history, so this hook doesn't run while cycling.
- When the update returns false (an untracked buffer, or an "evolved" one, M3), the slots aren't touched. `ensure_curwin_crux` and `cleanup_triquetras` still run (A2, A21).
- Cleanup runs **before** this hook (class 1.8 against 2). When the buffer being left is a missing file, it stays registered and current until this hook moves it to the ternary as usual (M3, A21) **[inferred]**.
- **The secondary map's check.** On the X = T and last rows, once the slots move, X's plain secondary note, when it names the window's secondary, becomes X's swap note when that names another buffer, and is dropped otherwise (`keep_older_secondary_note`, `:123`; M7).
- **Going to the secondary** (`window/hooks.lua:68-80`) runs in `<M-f>`'s order: the notes (`write_secondary_swap_notes`, M7); Q6's guard, which rewrites `dtm[T]` to A when it names S, with the WARN "Avoided conflict of ternary's remembered relationship becoming current." (shorter than `reconcile_triquetra`'s, A13); the swap; then the ternary map's stale-note check, under which S's plain ternary note naming T, which stays put, becomes the ternary's own note `dtm[T]` (`keep_older_ternary_note`, `:80`; Q6, D8).

Examples **[run s01, s02]**:
- `{c=a}` `:e b` → `{c=b t=a}`.
- `:e c` → `{c=c t=b}`, `dtm{b→a}`.
- From `{c=d s=b t=c}`, `:e b` (the secondary) → `{c=b s=d t=c}`, with `<M-f>`'s notes `dsm{d-swap→b}` and `dtm{d-swap→c}` (T30); **[run s01]** recorded no dsm write, before D8's notes. The author's check of P14 gives the same slots.

**Label:** intended (README:534-536, README:540, SPEC:221-226, P14). Reaching the secondary by plain navigation writes the same notes as `<M-f>`, as README:542 says, "every time you jump to secondary" (D8).

**Decided:** the slotting happens at the end of the tick against the window's own buffer, never the focused one, and a later `buftype` change undoes the arrival (DESK:1788-1789). Built in step 3: the slotting once the editor settles, inside the event's window (`nvim_win_call`), skipped when the window shows something else by then (P2; T19, T224, T250), and the undo on `OptionSet` (I10, T217). Since arrivals are judged once the editor settles, with typeahead (a macro, a mapping that switches buffers several times, `:bufdo`) only what each window shows then is slotted and recorded: the buffers passed on the way are neither visited nor noted. One of cavediver's keys in the batch is the exception: it runs the arrivals still queued first (M11 Settle work), so `:e b.txt<CR><M-f>` in a macro takes b in and then acts on it, as typed by hand (T465).

**Decided (2026-10-20):** going to the secondary by plain navigation is one of Q6's routes onto the secondary. The guard runs before the swap and rewrites `dtm[T]` to the buffer being left (A6). Built in step 3.

**Decided (2026-10-20):** going to the secondary by plain navigation records the same notes as `<M-f>`, so `<M-;><M-t>` works after either route (D8). Paired with T30 (T191). Built in step 3.

**Decided (2026-10-20 evening), "Keep the older one": plain navigation onto the secondary** runs in `<M-f>`'s order (A6):
1. the notes: `dsm[A-swap] := S` and, with a ternary, `dtm[A-swap] := T`. S's plain secondary note becomes S's swap note when that names a buffer other than A; otherwise a plain note naming A is cleared (M7).
2. Q6's guard.
3. the swap, `{c=S s=A t=T}`.
4. the stale-note check below: S's plain ternary note, when it names T, which stays put, becomes **the ternary's own note** `dtm[T]`.

Example, the round trip D8 asked to solve **[sim `rt_cand_round_e`, variant `rt_c3kga`; the same under `kt_rewrite_sec`]**: `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` give `⦉c⦊ [d] ⟦b⟧`; `:e b` gives `⦉c⦊ [b] ⟦d⟧` with `dsm{b>a d-swap>b}`; `:e d` gives `⦉c⦊ [d] ⟦b⟧` with `dsm{b-swap>d b>a d-swap>b}`; `<M-;><M-t>` on d says "No secondary relationship found" instead of throwing (T179).

Built in step 3.

**Decided (2026-10-20 evening), "Keep the older one": the stale-note check in navigation runs on every arrival.** Navigation's own check (`window/hooks.lua:97-114`) covers a buffer reached by plain navigation that isn't the secondary. Under the decision the same check runs whenever a buffer N becomes current, by any key, after the arrival's own writes. N's plain ternary note is checked against the ternary the window has after the arrival, and when it names it, it's rewritten:

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
- Code the change touches, from the variants: `reconcile_triquetra` (`window/routines.lua:314-390`), `jump_to_primary` (`:1035-1039`), and plain navigation onto the secondary (`window/hooks.lua:68-80`). Navigation's own check stays as it is.
- Built in step 3: the check on every arrival, on both maps (`keep_older_ternary_note`, `keep_older_secondary_note`, `window/routines.lua:32-71`), and wherever a slot changes under the current buffer (`check_notes_under_current`, `:106-121`): after either restore's change, graduation, the history fill, a cleanup pass that moved a window's slots, and a session load.

### A2. A window switches to something untracked

Examples: `:terminal` in the window, help or quickfix opened into it, a `nofile` scratch.

**Today.** The window is visiting: it keeps its triquetra while it shows anything untracked. The getter never drops a triquetra (`window/data.lua:80-97`), and the shown buffer is never registered, so it never reaches a slot (M3, T26). The current slot stays the file the window was last on, and may be a closed buffer, which cleanup keeps while the window shows something unregistered (A21, T270). Coming back to the current slot finds the slots, the primary queue and the maps as they were (T27).
- A window born untracked (`:help`, `:copen`, `:split | terminal`) never gets a triquetra, and neither does a float: the getter only runs once the editor settles, when the window already shows what it was born with (M6, T225, T217).
- The winbar shows the visit in the current piece, `[N] a.txt ← [<id> help]`, and a window born untracked shows its visit alone (M12, T268, T457).
- `<M-f>` and `<M-S-f>` take the window back to its current slot first, reopening a closed one (A6, A7, T269). `<M-.>` closes the visited buffer and lands on the current slot (A15, T164).
- A buffer that turns untracked after it arrived (a plugin's scratch set to `nofile`) has its arrival undone, and the window is visiting it from then on (I10, T217).
- Cleanup drops a visiting window's triquetra only when its current slot names nothing open or closed (A21).
- **[run s15]** recorded `{c=c s=b}`, `:terminal` → no triquetra, then `:e a` → `{c=a}`, before the visiting rule.

**Label:** intended (DESK:1785-1794). README:519 says the triquetra is kept and the winbar shows the visit (D26).

**Decided: the visiting rule** (DESK:51, DESK:1785-1794):
- A window that has a triquetra keeps it while it shows anything untracked. Its current slot stays the file it was last on, and may be a closed buffer.
- Windows born untracked (`:help`, `:copen`, `:split | terminal`) and floats never get a triquetra.
- The winbar shows the visit, e.g. `main.lua ← [help]`.
- `<M-f>` and `<M-S-f>` take you back to the current slot first.

Built in step 3.

### A3. Entering a window (`WinEnter`)

**Today.** Once the editor settles, and only while the focus is still on the window, a navigation self-transition with mode `winenter` (M11, `navigation/hooks.lua:79-97`). A `WinEnter` whose focus has moved on by then does nothing: the later `WinEnter` takes over. It:
1. records `jump[cur] := prev`, where prev is the `winnr('#')` window read at the event, or `last_valid_window` when there's none. It skips a prev showing filetype `minimap`, or one that's invalid.
2. sets `current_window := cur`.
3. runs `construct_crux(find_most_recent_tracked_window())`, which may create the window's triquetra (M6).
4. refreshes the UI.

While cycling, entering a window other than the cycling one also cancels the cycle once the editor settles (A12).

A `BufEnter` usually follows when the window shows a different buffer. A1 then runs for the entered window, and since its shown buffer is its current slot, the slots don't change.

`record_window_jump` checks that the "from" window is still there before reading its buffer, so a window gone by the time the entry settles, as the command-line window is once you leave it, is no jump to record (`navigation/routines.lua:53`; T459). **[run 2026-10-24]** recorded the `winenter_record_window` hook failing there with "Invalid window id", the order the other way round (DESK:2472), before step 8.

### A4. A new split (`:split`, `:vsplit`, `:new` showing a file)

**Today.**
- A split showing the same buffer fires no `BufEnter`.
- Once its `WinEnter` settles, the new window gets a fresh `{c=<that buffer>}` (M6). It isn't a copy of the old window's triquetra.
- Its history entry comes with the triquetra, empty until a visit happens in it (`window/data.lua:42`; I3, T18). **[run s07, s16]** recorded it with none.
- `save_session` then writes the window's empty history into its entry and goes through (T141). **[run s16]** recorded it failing on `next(nil)` without the entry.

**Label:** a minimal start is intended (SPEC:65-76), and so is the history entry that comes with it (I3).

### A5. Closing a window (`WinClosed`)

**Today:**
- The window's history entry is dropped (`history/hooks.lua:284-293`).
- Its triquetra is dropped (`window/data.lua:57-74`): the UI cache is cleared, `last_valid_window` is moved to the previous window in the jump chain whose buffer is registered, the history view is rebuilt for that window, and the winbar is cleared.
- Entries in the window-jump history that point at the closed window stay (M10). **[run s07]** shows the closed window's data gone.
- The popup's `WinClosed` handler deletes the pop-up's buffer when its window closes, whichever window closed before (`ui/hooks.lua:196-215`, A18, T236). DESK:2479 recorded it as `once`, used up by the first window closed after `setup()`, before step 8.

### A6. `toggle_secondary`, `<M-f>`

**Today** (`window/routines.lua:809-901`), in window W:

1. **No triquetra:** WARN "Window with unregistered buffer." Nothing else.
2. **W shows something other than its current slot**, while the current slot's buffer is open, or while W is visiting (it shows an unregistered buffer) with its current slot closed, which is then reopened (`window/routines.lua:817-825`, M5): switch W back to the current slot's buffer, INFO "Jumped back to windows current buffer.", stop. This is what happens while cycling **[run s04]**, and while visiting (A2, T269). A closed current slot whose file is gone from disk isn't reopened: WARN "<name> isn't on disk right now; the current slot keeps it.", and nothing changes (`:820-823`, P9).
3. **The secondary is empty.** No buffer switch:
   - With a ternary T: `s := T`, `dsm[T] := dtm[T]`, `dsm[T-swap] := nil`, `t := nil`, then the check where a slot changes under the current buffer (A1). INFO "Secondary buffer set to ternary slot. Ternary slot graduated."
   - Otherwise, with at least 2 entries in the ordered history, it asserts that the first entry is the window's current buffer, and throws "This is impossible. The most recent buffer in the history must be the window's current buffer." when it isn't (`window/routines.lua:846-849`, D11). Then `s := hash(ordered[2])` and the same check. INFO "Secondary buffer populated from history." The assertion guards the routes where a stale history put the current buffer second and one buffer in two slots (DESK:2463); the window-jump cancel (A12) and the tie fix (D11) close them (T43, T176).
   - Otherwise: WARN "Cannot populate secondary slot - insufficent history."
4. **The secondary S is set:**
   - When S's buffer is closed and its file is gone from disk: WARN "<name> isn't on disk right now; the secondary slot keeps it.", and stop, before any note is written and with nothing moved (`:857-860`, P9; T44, T45).
   - Write the swap notes (`write_secondary_swap_notes`, `window/routines.lua:82-95`): `dsm[A-swap] := S`; S's own swap note becomes its plain note `dsm[S]` when it names a buffer other than A, and otherwise a plain note `dsm[S]` naming A is cleared; and `dtm[A-swap] := T` when there's a ternary T (M7).
   - If S's buffer is closed, reopen it (M5).
     - On failure, which leaves a No Name S whose text is lost: WARN "Removed secondary file not found in filesystem: <name>", `s := nil`, stop.
     - On success: take it off every pool (`remove_from_closed_buffers`, M5; the reopen has done that already) and INFO "File reopened for secondary slot: …".
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
- The `dsm` write is intended (README:542).
- The `dtm[A-swap]` write is intended (Q2). SPEC:240, which says a swap creates no mapping, is out of date (D7).
- Copying `dtm[T]` into `dsm[T]` on graduation is intended (Q3). The author's reason: the graduated buffer's predecessor can then come back either as the ternary (`<M-;><M-r>`) or as the secondary (`<M-;><M-t>`).
- In the swap path, `reconcile_triquetra`'s "avoided conflict" guard runs before the swap (`window/routines.lua:345-355`), so when `dtm[T] = S` it rewrites `dtm[T]` to A, with its WARN (Q6). The conflict is real and the warning isn't spurious. **[run s18]** recorded the guard running after the swap, where its write was a no-op and only the WARN appeared. The author's repro, observed before the fix: `:e a`, `:e b`, `:e c`, `:e b`, `<M-f>`, `:e a`, `<M-f>`, `<M-f>` (the warning, no change), `<M-S-f>`, `<M-;><M-r>`, which throws (T150).

**Decided:** while visiting, `<M-f>` takes you back to the current slot first (DESK:1792). Step 2 does that. Built in step 3: the jump back reopens a closed current slot (A2).

**Decided (2026-10-20):** the guard runs **before** the swap on every route onto the secondary, so `dtm[T]` is rewritten to the buffer being left (Q6). The routes:
- `<M-f>` (this action)
- a cycling pick of the secondary (A13)
- `<M-;><M-f>` falling back to `<M-f>` (A8)
- plain navigation onto the secondary (`window/hooks.lua:66-80`, A1)

Setting `proc = true` in the secondary branch alone isn't the fix: it keeps the crash. The guard came in with commit ae209e42 (2025-06-12), inside `if not proc`; `proc` dates from d89061a3 (2025-06-11). Both predate this repository. The fall-through onto the secondary route wasn't deliberate. With the fix, the ten-key repro restores without throwing. Random walks with the fix still hit the ternary restore's throw 13 times in 1,500. Each of those lands on a buffer by an arrival that skips the stale-note check in navigation; "Keep the older one" closes them (A1, A11).

Built in step 3: the guard before the swap on all four routes (`window/routines.lua:345-355`, `window/hooks.lua:73-77`), with `proc` set in the secondary branch (`window/routines.lua:359`).

**Decided (2026-10-20 evening), "Keep the older one"** (M7):
- **Step 3, graduation,** also clears the graduated buffer's swap note `dsm[T-swap]`, so Q3's copy is what a later `<M-;><M-t>` finds (T184).
- **Step 4, the notes:** `dsm[A] := S` becomes the swap note `dsm[A-swap] := S`. S's plain note `dsm[S]` becomes S's own swap note when that names a buffer other than A; otherwise a plain note naming A is cleared. `dtm[A-swap] := T` stays.
- **The order on every route onto the secondary** (this key, its `<M-;><M-f>` fallback, plain navigation onto the secondary): the notes, then Q6's guard, then the swap, then the stale-note check, under which S's plain ternary note naming T, which stays put, becomes the ternary's own note `dtm[T]` (A1).
- The swap examples above then read `dsm{b→a, c-swap→b}` and `dsm{b→a, b-swap→c, c-swap→b}`, and `<M-;><M-t>` on c says "No secondary relationship found" instead of throwing **[sim `rt_sec_round`, variants `rt_c3kga` and `kt_rewrite_sec`]** (T177). One more `<M-f>` back to b, and `<M-;><M-t>` there brings back a, b's secondary from before the round trip (T178).
- Built in step 3.

### A7. `toggle_ternary`, `<M-S-f>`

**Today** (`window/routines.lua:909-974`), in window W with `{c=A s=S t=T}`:

1. **No triquetra:** WARN as in A6. **W not showing its current slot:** jump back, as in A6: a closed current slot is reopened while visiting, or, when its file is gone from disk, the key says so and changes nothing (`:917-925`).
2. **No ternary:** WARN "No ternary buffer to swap with.", stop.
3. **T's buffer is closed:** when its file is gone from disk, WARN "<name> isn't on disk right now; the ternary slot keeps it.", and stop, with nothing moved (`:940-943`, P9, T227). Otherwise reopen it. On failure, which leaves a No Name T whose text is lost: WARN "Removed ternary file not found in filesystem: …", `t := nil`, stop.
4. Run `rename_hash_in_triquetras(T, hash of the opened buffer)`. That's a no-op: a reopened No Name T has its new hash everywhere already, this slot included (M5) **[code]**.
5. `reconcile_triquetra`: the secondary map's check on T, `dtm[A-swap] := T`, the swap, `{c=T s=S t=A}`, then the ternary map's check, under which T's plain note naming A becomes `dtm[A]`, or is dropped (A13). Switch W to T.

Example **[run s01]**: `{c=d s=b t=c}` → `{c=c s=b t=d}` with `dtm{d-swap→c}`. Again → `{c=d … t=c}`, adding `c-swap→d`.

- Step 4 has no guard for a nil old hash: if the ternary were cleared between steps 3 and 4, the rename would throw "attempt to concatenate local 'old_hash'" (`window/data.lua:151`). **bug (desk)** The desk's route to it, `:e 1.txt`, `:e 2.txt`, `<M-n>`, `:bdelete`, `<M-S-f>`, `<M-S-f>` (DESK:2469), goes through without a throw or a duplicate slot: the reopen's `BufEnter` is slotted only once the editor settles, so no cleanup runs between the reopen and the rename (T49). **[desk]** recorded that route throwing on the first press, and "Duplicates detected in triquetra slots" (`window/routines.lua:343`) on the second.

**Label:** the swap is intended (SPEC:114-135). The `-swap` write is intended (Q2).

**Decided (2026-10-20 evening), "Keep the older one":** after the swap, the stale-note check runs (A1). T's plain ternary note, when it names A, the new ternary, becomes A's own note `dtm[A]`, as navigation's first case does; when A has none, it's dropped (T186). The secondary map's check runs too (M7). Built in step 3.

### A8. `jump_to_primary`, `<M-;><M-f>`

**Today** (`window/routines.lua:980-1048`), in window W with `{c=A s=S t=T p=[P,…]}`:

1. **No triquetra:** WARN "Window with unregistered buffer."
2. **Cycling.** Switch W to the cycle's starting buffer, set `c := origin` (already true, M9), INFO "Returned to cycling origin buffer: <name>". **Navigation stays `cycling`.** **[run s04]**
3. **Fall back to A6** when the queue is empty, **or `primary_enabled` is false**, or S = P **[run s02]**.
4. **P's buffer is closed:** when its file is gone from disk, WARN "<name> isn't on disk right now; the primary queue keeps it.", and stop, with nothing moved (`window/routines.lua:1012-1015`, P9; T57, T58). Otherwise reopen it.
   - A reopened No Name P comes back under a new hash, which the reopen writes wherever the old one was, every window's queue included (M5). The jump then writes it into `p[1]` again, in W only **[code]**.
   - On failure, which leaves a No Name P whose text is lost, it warns "Removed primary file not found in filesystem: <name>", takes P off the queue and stops, as the secondary and the ternary clear their slot in the same case (`:1023-1030`) **[code]**.
5. **A ≠ P:** `dtm[A-swap] := T` (nil when there's no ternary), `t := A`, `c := P`, then the stale-note checks: the secondary map's on P, and the ternary map's, under which P's plain note naming A becomes T, or `dtm[A]` when P was the ternary (`window/routines.lua:1040-1041`). Otherwise INFO "Already in primary buffer, no displacement performed.", and nothing changes.
6. Then reconcile (a no-op here) and switch W to P.

Examples **[run s02]**:
- `{c=e s=d t=b p=[b]on}` → `{c=b s=d t=e}`, `dtm{e-swap→b}`. When P was the ternary, this is the same as `<M-S-f>`.
- On P already: nothing changes.
- `p=[b]off`: it acted as `<M-f>` and graduated the ternary.

**Labels:**
- Bringing P to current with A moving to the ternary is intended (SPEC:137-157, README:547).
- Falling back when the queue is empty is intended (SPEC:143).
- Falling back when the primary is **disabled** is intended (Q10). README:31 says it acts like `<m-f>` then (D5).
- The cycling branch is intended (SPEC:206-209).
- That the branch doesn't leave cycling is intended (Q7): there's no cancel key, and `<M-v>` picks the start (A14).
- The fallback to `<M-f>` is one of Q6's routes onto the secondary, so it gets A6's decided guard.

**Decided (2026-10-20 evening), "Keep the older one":** after the shift in step 5, the stale-note check runs (A1). P's plain ternary note, when it names A, the new ternary, becomes T, the pre-jump ternary, as navigation's second case does; when P was the ternary, it becomes `dtm[A]` instead (T187). The secondary map's check runs too (M7). The fallback to `<M-f>` follows A6. Built in step 3.

### A9. `toggle_primary`, `<M-;><M-x>`

**Today** (`window/routines.lua:1054-1071`):
- Empty queue: `p := [A]` and `primary_enabled := true`, whatever the switch said (Q14).
- Otherwise: `primary_enabled := not primary_enabled`.
- Then a UI refresh, `redrawstatus!` and `redrawtabline` (T451).

So:
- the first press on an empty queue makes the current buffer the primary and enables it, even when the empty queue was switched on
- later presses only toggle enabled, whatever buffer you're on
- the queue never changes after that

**[run s02]**: `p=[]off` → `p=[b]on` → `p=[b]off`.

**Label:** intended (Q8). `<M-;><M-x>` is the primary's on/off switch, and seeds the queue only when it's empty. `<M-;><M-c>` (A10) is the key that makes the current buffer the primary.

**Decided (2026-10-20):** only the keymap description changes. "Toggle current buffer as primary" didn't describe an on/off switch. The README has the two keys swapped, which is a bug in the README (D1). Built in step 8: the description reads "Switch the primary on or off" (`init.lua:132`, T156).

**Decided (2026-10-20):** on an empty queue, the key queues the current buffer and switches the primary **on**, whatever the switch said (Q14). **[run s19]** recorded the key flipping the switch after queueing, so a queue that emptied while on ended up `p=[A]off` and needed a second press. The state isn't changed: an empty queue may stay switched on (I19). Built in step 3 (T157).

### A10. `set_primary`, `<M-;><M-c>`

**Today** (`window/routines.lua:1077-1100`):

| Queue state | Effect |
|---|---|
| empty | `p := [A]`, enabled |
| `p[1] ≠ A` | remove A from the queue if it's there, put A at the front, enable |
| `p[1] = A` | toggle enabled |

Then a UI refresh, `redrawstatus!` and `redrawtabline` (T451).

**[run s02]**:
- `p=[b]off`, on b → `p=[b]on`.
- On e → `p=[e,b]on`.
- Again on e → `p=[e,b]off`.

**Label:** intended (README:22, Q8).

### A11. Restoring from the displacement maps: `restore_ternary` `<M-;><M-r>`, `restore_secondary` `<M-;><M-t>`

**Today** (`window/routines.lua:1106-1203`). The type is ternary or secondary, the slot `cur` is that type's slot, and the map is dtm or dsm. In window W with current A:

1. Look up `remembered := map[A-swap]`. If that's nil, equals `cur`, the occupant of the slot being restored into, or is a closed buffer whose file is missing from disk, use `map[A]` instead (`:1127-1135`). Before that, a note at a hash with no path, `map[A-swap]` or `map[A]`, is cleared, so it reads as nil (`:1110-1116`, D9).
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

3. In the last four rows, `map[A] := cur` afterwards. A nil `cur` deletes the entry. INFO "Restored <type> slot to: <hash> (<name>)"; when the restored buffer is open but its file isn't on disk, the same line at WARN with ", not on disk right now" added (D9). Then the check where a slot changes under the current buffer runs (`check_notes_under_current`, `:1177`, A1).
4. No buffer is switched, and closed hashes aren't reopened.

The flip-flop **[run s02]**:
- At b with `{c=b t=d}` and `dtm{b→a}`, restore → `t=a`, `dtm{b→d}`.
- Restore again → `t=d`, `dtm{b→a}`.

**[run s02]** also shows the swap record winning:
- From `{c=e … t=b}` jump to primary b: `dtm{e-swap→b}`.
- `<M-S-f>` back to e.
- Restore at e finds `e-swap→b`, the current ternary, so it falls back to `dtm[e]`, which is nil: "No ternary relationship found".

**Labels:**
- The flip-flop is intended (SPEC:159-186, SPEC:249-273, README:536, README:542).
- The `-swap` preference is intended (Q2): the author confirmed it and said they'd forgotten why. Both alternatives were then tried on scratch variants, by the session, not the author:
  - If swaps wrote plain notes, toggling with `<M-S-f>` would overwrite the note with the toggle partner, and the next restore would throw "Remembered ternary is the same as current ternary".
  - If swaps wrote nothing, a restore after a primary jump and back would give an older buffer instead of the one you had right before the jump.
- Throwing when the remembered value equals the slot is intended: the assertion stays (Q13). SPEC:176's message, "No different ternary relationship to restore", is out of date (D9). Every route that still reaches the throw is a bug, to be hunted with tests (T154). Q6's fix closes one route (A6). The 13 ternary throws left in 1,500 walks after it were traced: each landed on a buffer by an arrival that skipped the stale-note check in navigation. **[run, sim; the round-trip research's walks]** recorded the secondary restore throwing far more often before "Keep the older one": 161 times in 1,500 walks, 204 with D8's notes as plain notes, mostly after a round trip onto the secondary and back. With "Keep the older one" built, T154, T190 and T335 find no throw.

**Decided (2026-10-20 evening), "Keep the older one".** One rule lies behind every throw found: a buffer becomes current while its note names the buffer already in the slot that note restores into (I23). The fix is the stale-note check on every arrival, on both maps (A1, M7), plus these changes to the restore itself:
- **The swap-note fallback** (step 1) compares with the slot being restored into, not with the ternary for both: `dtm[A-swap]` against the ternary, as today, and `dsm[A-swap]` against the secondary (`window/routines.lua:1129-1135`). So after a round trip onto the secondary and back, A's swap note equals the secondary and the restore falls back to A's plain note, A's secondary from before (T180).
- **The ternary restore's exchange** (the row "ternary type, equals the secondary") is followed by the secondary map's check: the current buffer's secondary note, when it names the new secondary, is rewritten to its swap note or dropped **[sim `kt_tosec`, variant `kt_rewrite`]** (I23, T190).
- **The secondary restore's exchange** (the row "secondary type, equals the ternary") got no check in the first tested fix: when the current buffer's ternary note named the old secondary, which the exchange had just moved into the ternary, the next `<M-;><M-r>` threw **[sim, variant `kt_rewrite_sec`]**. **Decided (2026-10-21):** the check runs there too, and the stale note becomes the ternary's own note, dropped when there's nothing older or it would name the current buffer **[sim, variants `ex_a`, `all_fixed`]** (T189, T206).
- Over two sets of 1,500 walks: 0 ternary and 0 secondary throws, no duplicate slot, no other error **[sim, variant `kt_rewrite_sec`]**. Zero in the walks is evidence, not proof; T154 and T190 keep hunting.
- Built in step 3: the fallback (`window/routines.lua:1129-1135`), and the check after every restore, exchanges included (`:1177`).

**Decided (2026-10-20 evening): a remembered file that's missing** (D9), for both restores and both maps, swap keys included:
- missing from disk with no buffer: skipped and kept. A skipped swap note falls back to the plain note; when that's missing and closed too, the restore says so and changes nothing (T67, T174, T193).
- missing from disk with its buffer open: the restore goes through and flip-flops with it, saying the file isn't on disk (T173).
- a hash with no path: the note is cleared when used, with no throw (T68).
- Built in step 3 (`window/routines.lua:1110-1174`).

### A12. Cycling: `cycle_left` `<M-n>`, `cycle_right` `<M-m>`

**Today** (`navigation/init.lua:67-83`, `navigation/hooks.lua:22-32`, `navigation/routines.lua:11-43`):

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

**A jump to another window** (`cancel_cycle_on_window_jump`, `navigation/hooks.lua:45-53`; `cancel_cycle`, `navigation/routines.lua:128-168`). A `WinEnter` into any window other than the cycling one, floats included, cancels the cycle once the editor settles (`vim.schedule`), unless a pick or another cancel got there first:
- The cycling window goes back to its start, its current slot read live (D15). That switch fires a `BufEnter` while history is still detached, and its arrival is dropped when it settles, since the cancel has attached history by then: nothing is recorded for it (`history/hooks.lua:225`, `:235-237`).
- Navigation goes to `normal` with no mode, so no hook runs and nothing is picked. The trail gets the cancel, on the jump's step (A27, T411).
- History attaches with the buffer of the jumped-to window's current slot, so no slot moves and that buffer is recorded as an ordinary visit, even when Neovim fired no `BufEnter` there. When the window shows another buffer, an ordinary update for it follows, `attached→attached`, which acts as plain navigation: the old current goes into the ternary (A1; T175, T198, T229). Nothing is recorded for the cycle's steps.
- **Decided (2026-10-24), a key that comes first** (the author: "Cancel first, then act", once the cause was put: one cycling state for the whole editor, one start per window, and a cancel that waits for the editor to settle). Keys arriving in one batch, from a macro, a mapping or a paste, can reach the window jumped to before the cancel has run. A cavediver key that finds a cycle running in another window runs the cancel at once, then does its own job, as if the editor had settled between the two; the cancel waiting then finds the cycle over and does nothing (T461). Mine: a user's own mapping that calls cavediver's exports, `vim.cmd.wincmd('w')` then `require('cavediver').jump_to_primary()`, is the same case, so the cancel sits in the exports (T463). The window jump's cancel is settle work, so a key runs it by draining the queue (M11 Settle work), and it lands under the window jump's step, as typed by hand (the author, 2026-10-24: "Yes, cancel under the jump"); `cancel_cycle_elsewhere` (`navigation/init.lua:46-51`) stays after the drain, for a cycle whose window jump queued nothing, as `noautocmd wincmd w` leaves one. Built in step 8, through the settle queue (M11 Settle work; T461, T463). **[run 2026-10-24]** recorded `<C-w>w<M-;><M-f>` in one batch throwing "This should not happen. Cycling origins not found for window: …" in the window jumped to, since `jump_to_primary` reads the cycling state and then that window's start, which it has none of; and `<M-v>`, `<M-n>`, `<M-m>`, `<M-f>` and `<M-S-f>` acting there as if it were the cycling window, before the key ran the cancel.
- **Decided (2026-10-24), it says so** (the author: "INFO, both routes"): every cancel, a jump's or a key's, says "Cycling cancelled. Window <n> returned to cycling origin buffer: <name>" at INFO, built on the author's own "Returned to cycling origin buffer: <name>" (A8 step 2) (T462). Built in step 8 (`navigation/routines.lua:150-155`); with the window or its start gone, it says "Cycling cancelled." alone (mine).

Which way left and right move depends on cokeline's buffer order: `compare_buffers` puts the newest on the left, so `-1` moves toward newer buffers. The runs here used a stub that steps through cavediver's ordered list, not real cokeline, but the author confirms the direction (Q19): `<M-n>` steps left, toward newer buffers, and `<M-m>` steps right, toward older ones.

**Label:** intended (README:569-571, Q1, Q19). SPEC:194 and SPEC:393, which have the current slot follow the cycle, are out of date (D10).

**Decided (2026-10-20):** only when cokeline is missing, a step goes through cavediver's own ordered history instead (the order the bufferline would show), so `<M-n>`/`<M-m>` still cycle. With cokeline installed nothing changes: cycling stays on cokeline and cokeline stays required. DESK.md:2126 ("Cycling stays on it") and the Dropped line at DESK.md:3146 get narrowed to say so at the next desk sync. **[run s21]** recorded the step only printing, before the fallback (T171, T248). Built in step 3.

**Decided (2026-10-20 evening):** jumping to another window ends the cycle by **cancelling** it: the cycling window returns to its start and nothing is recorded (P18; Q7, picking stays `<M-v>`'s job). Any `WinEnter` into another window counts, floats included (the primary pop-up, a picker's prompt, `:help`). It acts on the cycling window, after the editor settles. The author: "I guess we have to quit cycling mode when we jump windows." **[run `t/b7_jump.lua`]** recorded a cycle leaking across windows before the cancel: work in the other window wasn't recorded and didn't move its slots, and `<M-v>` pressed there "picked" in that window, dropping its current buffer (T175). Built in step 3, on `vim.schedule`, with the start read live from the cycling window's current slot (D15).

**Decided (2026-10-21):** landing in the window you jumped to counts as an ordinary visit and records its buffer, even when Neovim fires no `BufEnter` (the window already shows that buffer). The cancel records nothing for the cycle's steps only. The author: "Yes, record the landing". Without it, `:e a`, `:vsplit`, `:e c`, `<M-m>`, `<C-w>p`, `<M-f>` trips the fill assertion under both views (35-52 per 1,500 multi-window walks; 0-3 with the landing recorded, all from the window-view tie bug in D11) **[sim, 2026-10-21]** (T198). Built in step 3: the cancel attaches history on the jumped-to window's current slot, then records what the window shows by plain navigation when that's another buffer.

### A13. `cycle_select`, `<M-v>`

**Today** (`navigation/init.lua:85-91`, `navigation/hooks.lua:34-40`, `window/routines.lua:314-390`).

**From `cycling`**, navigation goes to `normal`, and history `detached→attached` with `{buf = X, pick = true}`, where X is the shown buffer:
1. X is tracked; the order is now live again.
2. `cleanup_triquetras` runs.
3. `reconcile_triquetra(current window, X, pick)` runs, with `{c=A s=S t=T}`, where A is the cycle's start:

| Case | After | Map writes |
|---|---|---|
| X = A | unchanged | none |
| X = T | `{c=T s=S t=A}` | `dtm[A-swap] := T` |
| X = S | `{c=S s=A t=T}` | Q6's guard, before the swap: if `dtm[T] = S`, then `dtm[T] := A`, with WARN "Avoided conflict of ternary's remembered relationship becoming current. …" |
| X outside the triquetra | `{c=X s=S t=T}`: **A leaves the triquetra and the ternary stays** | if `dtm[T] = X`, then `dtm[T] := A`, with the same WARN; on a pick, Q9's note `dtm[X] := A`, and `dtm[X-swap]` is deleted (`window/routines.lua:376-379`) |
| X = T and X = S together | "Duplicates detected in triquetra slots" |

Every case but X = A also runs the stale-note checks: the secondary map's on X before the slots move, and the ternary map's after (`window/routines.lua:328-332`, `:381-387`; A1). Q9's note is written only on a pick, with `pick = true` from `stop_cycling`; the window-jump cancel reaches `reconcile_triquetra` too, with no pick (A12).

4. The UI refreshes.

Examples **[run s03, s04]**:
- `{c=e s=c t=d}`, cycle to b, `<M-v>` → `{c=b s=c t=d}`, with Q9's note `dtm{b→e}` (T155).
- Cycle to c (the secondary), `<M-v>` → `{c=c s=b t=d}`.
- Cycle to d (the ternary), `<M-v>` → `{c=d s=c t=e}`, `dtm{e-swap→d}`.

**From `normal`**, `<M-v>` is `normal→normal` with mode `cycle`. No hook matches, so nothing happens **[run s04]**.

**Labels:**
- The ternary not being updated by a pick is intended (README:534, Q9).
- When X is outside the triquetra, A, the cycle's start, is remembered on X: decided (2026-10-20) (Q9).
- In the X = S case, the "avoided conflict" guard runs before the swap, as on `<M-f>` (Q6, A6).
- SPEC:385-407, which has slot changes during cycling persist with no displacement, is out of date (D10).

**Decided (2026-10-20):**
- A pick of a buffer outside the slots also writes a note on the picked buffer, `dtm[X] := A`, so `<M-;><M-r>` on X brings the start back. The ternary itself stays unchanged, so README:534 holds (Q9, T155).
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

**Today** (`history/routines.lua:1441-1548`), on the buffer B shown in window W.

**A buffer cavediver doesn't track** (help, quickfix, a terminal, a plugin's scratch, an `acwrite` buffer such as oil's) is closed as it is, before any of the steps below (`:1444-1468`, Q17):
- A terminal whose job is still running is refused with WARN "Terminal job is still running", and nothing changes.
- A modified buffer whose `buftype` is `acwrite` or `""`, oil's with pending edits for one, is refused with WARN "Buffer has unsaved changes", as a file is in step 1, and nothing changes (`:1450-1454`, I12).
- A window with a triquetra, which is visiting the buffer, goes back to its current slot first, reopening it when it's closed (`:1457-1465`, T164). When that closed slot's file is gone from disk, nothing is reopened: a WARN says "<name> isn't on disk right now, so the window can't go back to it.", and the visited buffer is closed (`:1462-1464`, P9) **[code]**.
- Then the buffer is deleted with `nvim_buf_delete(…, { force = true })`. Neovim closes a window born on it when other windows exist, and picks what an only window shows (T84, T165–T167).

For a tracked buffer:

1. **Refusals**, each with a WARN and no change:
   - B has a name and is modified: "Buffer has unsaved changes". A modified No Name buffer goes through.
   - B is shown in another window: "Can't delete buffer because it's shown in another window."
   - The history view has 1 entry or fewer: "Can't delete buffer because it's the only one left".
2. **Picking where W goes.** Find B's index i in `ordered.crux`, with n entries:
   - If B isn't in it, it **throws** "This is impossible: Current buffer not found in ordered history." at `history/routines.lua:1522`. Untracked buffers, where the author saw it (`:help`, a `:terminal`; DESK:2465), are closed before the steps, so they don't get here.
   - `i = 1` with `n ≥ 2` → `ordered[2]`.
   - `i > 1` → `ordered[(i % n) + 1]`, which is the next older entry, wrapping to the newest after the oldest.
3. **Closing.** Keep W's cursor on B (`vim.b[B].cavediver_cursor`, for a No Name buffer's cache, T83), switch W to that buffer, then, once the editor settles, delete B: `:bdelete` for a file, so Neovim keeps its marks, and `bw!` for a No Name buffer, whose text is cached (`:1526-1544`, T85). The switch's arrival is queued first, so it settles first and A1 moves W's slots before the delete; the delete's cleanup then finds nothing to heal and says nothing (P2, T336). Its `BufDelete` runs A19, which closes B into its pools (M5) and caches its text if it's a No Name buffer. The delete is dropped when a session loaded in between (`:1534-1538`, S1).

**[run s05]**:
- At f with order `f,e,d,b,a`: lands on e, `{c=e t=f}`, closed `[c,f]`.
- At e with order `e,f,…`: lands on f.
- In both, the closed buffer stays in the ternary, where `<M-S-f>` reopens it.

**Labels:**
- The landing rule is intended: the code is right, and its comment at `:1518` says so, "Otherwise go to most recent relative to the one deleted (next in list, wraps around)" (D16, built in step 8). DESK:2478 recorded the comment as "go to most recent (first in list)", before step 8.
- `:bdelete` for files and `bw!` for No Name buffers is the decided split (below).

**Decided:**
- `:bdelete` for files, so Neovim keeps the buffer's marks. No Name scratches may still be wiped (DESK:2168).
- The close key keeps its own landing rule (DESK:2167).
- Each key has its own description: `close_buffer` "Close the current buffer" and `open_primary_buffer_history` "Open the primary queue" (`init.lua:139`, `:146`; D3, T169). Built in step 8; both read "Toggle current buffer as primary" before it.

Built in step 3: the first point (T85).

**Decided (2026-10-20): `<M-.>` on an untracked buffer** (Q17):
- **A window with a triquetra that's visiting something untracked** closes the visited buffer and lands on its current slot (A2).
- **A window born untracked** (no triquetra, such as a `:help`, `:copen` or terminal split) closes the buffer. Neovim closes that window when other windows exist; when it's the only window, Neovim picks what it shows.
- **A terminal whose job is still running** is refused with a message, as an unsaved file is (step 1).
- Built in step 3 (`history/routines.lua:1444-1468`): all three (T84, T164–T167). A visiting window goes back to its current slot before the close, reopening a closed one.

### A16. `reopen_last_closed`, `<M-S-w>`

**Today** (`history/routines.lua:1410-1438`), on the closed stack of the pool of the tab you're in: its tab session's, or the editor's when it's in none (`:1411`; M5, T319):
- With an empty stack there: WARN "No closed buffers to reopen.", unless other lists hold closed files: then the WARN says "No closed buffers to reopen in this tab." and, under it, "1 is on another tab's list: :CavediverClosed" or "<n> are on other tabs' lists: :CavediverClosed", `<n>` counting each file once, the lists in memory and those in the whole editor's file alone (`:1412-1428`, `file_only_closed`; A27, T399).
- Otherwise:
  1. Take its newest hash, leaving it there, and `reopen_filehash` it (M5), which takes it off every pool unless its file is gone from disk.
  2. On success, switch the current window to it (A1 runs, so the buffer becomes current and the old current moves to the ternary).
  3. When the file is gone from disk: WARN "<name> isn't on disk right now; it stays on the closed stack.", and the entry stays, still the newest (`:1434-1437`, P9, T89). DESK:2454 recorded the hash gone from the stack with nothing reported, before step 6.
  4. A No Name text a load left unread is read from its file now (M5). When its file is missing or fails its check, the reader's WARN "…so that text is lost." is all that's said, and the hash is gone from every pool: a No Name entry comes off before its text is read (M5).
- A reopened No Name buffer comes back under a fresh id, and every slot, primary queue entry, note and history entry that held its old hash holds the new one (M5, T91). Its cursor goes back in the window that shows it (T90).

**[run s05]**: closed `[c,f]`, at e → shows f, `{c=f t=e}`, closed `[c]`.

**Decided:** a missing file says so when it's used, and its pointer is kept (DESK:2022). A reopened No Name buffer gets a fresh id, and everything that pointed at its old hash is renamed (DESK:2299). Built in step 4: the fresh id and the rename (T90, T91). Built in step 6: a missing file says so when it's used, and its pointer is kept: on the closed stack (T89, T114), in the slots and the primary queue (A6–A8; T44, T45, T57, T58, T227), and across a session load (S1, T313).

**Decided (2026-10-23):** on an empty list, `<M-S-w>` says this tab's list is empty, how many closed files the other lists hold, and that `:CavediverClosed` shows them (the author: "Empty pool on <M-S-w>"); a reopen that takes the file off other lists names them in an INFO line (A27). Built in step 8 (T399, T401).

**Decided (2026-10-24), its condition and words:** the new message only while another list holds closed buffers, "No closed buffers to reopen." otherwise (the author: "Only then (as built)"), worded as one family with that sentence (the author: "Yours, then "in this tab""): "No closed buffers to reopen in this tab." and, under it, "1 is on another tab's list: :CavediverClosed", or "<n> are on other tabs' lists: :CavediverClosed" (T399). Built in step 8 (`history/routines.lua:1422-1423`).

### A17. `toggle_window`, `<M-,>`

**Today** (`navigation/routines.lua:58-73`):
- prev = `jump[current]`.
- If it's valid and not a minimap: record `jump[prev] := current`, then go to prev.
- Otherwise: WARN "No valid previous window to toggle to."

**[run s07]**: it toggles between two splits.

**Label:** intended (README:442). **Decided:** the minimap skip becomes a configurable list, defaulting to `minimap` and `neominimap` (DESK:2156). Mine: `toggle_window.skip_filetypes` (T232, T449). Built in step 8 (`navigation/routines.lua:49`, `configs.lua:357-360`).

### A18. Primary queue window, `<M-;>F` (`open_primary_buffer_history`)

**Today** (`ui/routines.lua:114-266`, `ui/hooks.lua:99-160`, `window/routines.lua:211-280`).

**Opening:**
- With no triquetra: INFO "No triquetra found for current window." With an empty queue: INFO "No primary buffer history available." In both cases there's nothing to edit, so the first entry can't be typed in from here.
- Otherwise:
  - A centred float opens. It holds a **listed** `acwrite` buffer named `cavediver://primary-buffer-queue-history`, with filetype `cavediver-primary-buffer-history`.
  - It lists one line per queue entry. Each line is the entry's display name, or `NONAME_<id>` for a No Name entry.
  - The size comes from `primary_buffer_history_popup`.
  - It speaks the trail's language as virtual text, so each line stays the entry's name alone (`decorate`, `ui/routines.lua:160`; T452): after the first line, the primary's switch, `primary · on` or `primary · off`; before an entry whose file is closed, the closed glyph; after an entry whose file is gone from disk, its tag. It's drawn again at every edit and after a write.
  - Its buffer goes with its window, however the window closes: `WinClosed` deletes it (`ui/hooks.lua:196-215`; T236). DESK:2479 recorded the handler as `once`, used up by the first window closed after `setup()`, so a pop-up closed with `:close` after another window closed left its buffer, and the next `<M-;>F` failed with E95, before step 8.

**Keys in the float**, from `keymaps.views` but `<C-s>` (`ui/hooks.lua:149-158`; T453):

| Key | Effect |
|---|---|
| `:w`, `<C-s>` | `BufWriteCmd` (below) |
| `leave` and `leave_too`, `q` and `<C-c>` | `write!`, then close the float, then delete the buffer 100 ms later. They **save**, which is intended (Q12), and they're described as "Save and close" (D12, T161). |
| `act`, `<CR>` | move the line under the cursor to the top, then the same as `q` (so it saves) |
| `act_and_stay`, `gf` | move the line under the cursor to the top and save, staying in the float |
| `pick`, `<M-e>` | add files through the picker (`M.pick_into_primary_popup`, `ui/routines.lua:91-111`): on the cursor's line when it's empty, otherwise after it, each relative to the current directory; nothing is saved until `:w`. The picker is `primary_picker`, or telescope's `find_files` when telescope is installed (`primary_picker`, `ui/routines.lua:50-82`; the telescope route **[code]**); with neither, a WARN, "cavediver: no file picker: install telescope.nvim, or set primary_picker in the config.", and no line changes (T159, T160) |

**Saving** (`BufWriteCmd`, only when the buffer is modified):
- Blank lines are dropped.
- Each line is trimmed and mapped back from display name to path, or kept as typed.
- Then `update_primary_buffer(lines, W)` (`window/routines.lua:211-280`), which checks each path, made absolute first as `:e` takes it, a `NONAME_` name left as it is (`:228`; T235):
  - Blank: skipped.
  - A file already on an earlier line: rejected, "Repeated" (`:233`; I18, T218).
  - Missing on disk, not `NONAME_`, and not already in the window's queue: rejected, "File does not exist". An entry already queued whose file is gone from disk stays, as P9 keeps it (T454).
  - Loaded but untracked: rejected.
  - Not loaded and unregistered: a `NONAME_` name is rejected. Otherwise the path is registered **and pushed onto the closed stack** of the current tab's pool (`window/routines.lua:256`, M5).
  - Errors are collected into one ERROR notification, naming each line as it was typed, and **the valid lines are saved anyway**.
  - The primary switches on only when the first row changed; otherwise it stays as it was, and a queue left empty keeps its switch (`:274`; Q10, T158, T101). The queue becomes the hashes of the valid paths.
  - Then the pop-up redraws each entry by its shortest unique name (T235). DESK:2477 recorded a relative path leaving a hole in the queue, and every save re-enabling a disabled primary, before step 8.

**Labels:**
- Editing, reordering, deleting and promoting with `<CR>` are intended (README:21-32).
- The partial save is intended (Q11): the good lines are saved and the bad ones reported. README:28 says the other lines still get saved (D6).
- Re-enabling the primary only when the first row changed is decided (2026-10-20) (Q10).

**Decided (2026-10-20):**
- **The on/off state** (Q10). A save switches the primary on only when the first row changed in the new queue. Otherwise the queue is saved and the on/off state stays as it was. Built in step 8 (T158, T101); mine: a queue a save empties keeps its switch, as I19 lets an empty queue stay on.
- **`q` and `<C-c>`** keep saving and then closing. Their description changes from "Close without saving" to "Save and close" (Q12). Built in step 8 (T161).
- **A file picker** (Q11), a new feature:
  - `<M-e>` in normal mode, mapped in that buffer only and configurable, opens a file picker through a provider.
  - The default provider is telescope's `find_files` with multi-select, when telescope is installed.
  - The selected file or files go on the cursor's line if it's empty, otherwise after it. Then `:w` validates them as usual.
  - With no picker, `<M-e>` gives a message.
  - Built in step 8 (T159, T160). Mine, its interface (the author, 2026-10-24: "Yes, you settle them"): `primary_picker`, a function given a callback, which opens a picker and calls the callback with the picked files' paths; with none set, telescope's `find_files` when `pcall(require, "telescope.builtin")` works, its selection, or the entry under the cursor, the files picked **[code]**: telescope isn't installed where the cases run. The key is `keymaps.views.pick`, `<M-e>`. A path goes in relative to the current directory, as typed paths are resolved (T235).
- **The trail's language** (2026-10-23): the pop-up is redesigned in step 8 to speak it, as the closed lists do, its decoration in virtual text and the lines you edit plain (the author: "In step 8 (Recommended)"; A27, S2 Closed-stack picker).
  - Mine, how: the lines stay the entries' names alone, and the decoration is virtual text, drawn again at every edit and after `:w`: after the first line, the primary's switch, `primary · on` or `primary · off`; before an entry whose file is closed, the closed glyph; after an entry whose file is gone from disk, its tag. The keys are `keymaps.views`': `leave` and `leave_too` save and close, `act` makes the line under the cursor the primary and closes, as `<CR>` does, and `act_and_stay` does the same and stays; `<C-s>` still saves (T452, T453). Built in step 8.

### A19. Any buffer delete (`BufDelete`, or a rename that settles as a copy)

**Today**, the history self-transition with mode delete. It runs on `BufDelete`, and on a renamed buffer's old name when the rename settles as a copy (A20):

1. **`handle_deletion`**, when the buffer is registered:
   - `track_closing_filehash`: close it into its pools, each taking any copy of it off first (`close_into_pools`, M5; I22). A No Name buffer with text has its lines, filetype and cursor cached. An empty No Name buffer is untracked, taken out of every secondary, ternary and primary queue and unregistered; then follow along drops the notes about it, and its path is forgotten unless a current slot still holds it (M2, M5, T208). It isn't pushed.
   - A buffer it pushed is unregistered, and keeps its path and its history: the closed stack keeps it known (M4, T252). Both ordered lists are rebuilt, so it leaves the bufferline (`history/hooks.lua:53-57`). An empty No Name buffer, which it doesn't push, is untracked and unregistered (`:58-61`).
2. **When history is attached:** the ordered lists are rebuilt.
3. **`cleanup_triquetras(buf)`** runs (A21). A window whose current slot was the buffer being deleted, and that still shows it, is left to land once the delete is over (below).

**The landing** (`land_after_delete`, `window/routines.lua:401-488`). It acts once the delete is over (`vim.schedule`), in that window, whichever window has the focus: The trail gets the landing, with the slot it came from (A27, T404).
- It lands on the first open one of the ternary, the secondary, `primary[1]`, and the open buffers in the bufferline's order (`history.get_ordered_buffers()`, which follows `history_view`), never the buffer being deleted (`:425-459`). That buffer becomes the current slot, and the ternary or secondary it came from is emptied, as healing does; the primary queue stays (T111, T271). Then the check where a slot changes under the current buffer runs, before the window is switched (`:461-466`, A1, I23).
- With nothing to land on, a window showing Neovim's empty buffer keeps it, and it's recorded as the visit (T237). Anything else Neovim showed is replaced by a new empty buffer, made with `nvim_create_buf(true, false)`, since `:enew` would reuse an empty scratch (`:468-486`).
- It does nothing when the window closed or lost its triquetra, when the buffer is still listed and shown (a rename, A20), or when the window moved on since Neovim's pick (`:408-423`).
- Neovim's own pick, the first `BufEnter` in that window once the deleted buffer is unlisted, isn't recorded as a visit: the `BufEnter` hook asks `is_landing_pick` first, at the event (`:497-508`, `history/hooks.lua:219-222`). `window.data.landing` holds, per window, the buffer being deleted and that pick (`window/data.lua:22-25`).

Closing a buffer that a slot holds:

| Slot | Effect | Evidence |
|---|---|---|
| ternary | it **stays**, as a closed hash | **[run s06]** |
| primary entry or secondary | it **stays**, as a closed hash, like the ternary: each check reads its own slot or entry (`window/routines.lua:692`, `:746`) | T103, T104. On the wrong-slot check (D13), **[run s05]**: `:bdelete c` with `{c=e s=c t=d}` → `s=-` at once. **[run s06]**: secondary and primary kept while the ternary was closed, pruned as soon as the ternary was reopened. |

**Label:** intended: a closed slot reopens when used (README:15, I4). A closed slot whose file is gone from disk stays too, and using it says so (A6–A8, P9).

**Decided:** a deleted buffer's window is landed after the delete, in that window, in the order ternary → secondary → primary → most recent, with no extra wipe. When nothing in that order exists, the window keeps Neovim's empty buffer, and `:enew` runs only when Neovim showed something else (DESK:1931). Plain Neovim usually lands the same way (DESK:3252). `<M-.>` keeps its own rule (A15). Built in step 1.

### A20. Renames and writes

**`:saveas`, `:file`, LSP or oil renames.** `BufFilePre` only records a registered buffer's old hash (`history/hooks.lua:249-262`). The old name stays registered to the buffer until the rename settles, so nothing prunes what a move carries over. `BufFilePost` settles it once the editor settles (`:265-281`, `settle_rename` at `:97-132`, `history/routines.lua:1304-1331`), and the disk decides:
- **A copy:** the old name is still a file (`:saveas`, or `:file` from a file on disk). The old name is closed as a delete closes it, through the delete transition (A19): it's closed into its pools and unregistered, keeping its history, and slots elsewhere keep it and reopen it when used (T272).
- **A move:** the old name isn't a file, or never was (a No Name buffer), and the new name is trackable (M3). The buffer's registration, every slot, primary queue entry and note (`rename_hash_in_triquetras`) and its history (`rename_hash_in_history`, M4) follow to the new hash, and the old hash leaves every pool, with nothing remembered, and its No Name text goes (`discard_from_pools`, M5; T107).
- A new name that isn't trackable, such as a `://` name, is closed like a copy, whatever the disk says **[code]**.

Then the buffer is registered under its new name, whatever the history state, and when a window shows it, it's taken in as an arrival in that window (`history/hooks.lua:120-128`, A1). On a copy, cleanup then re-points the window's current slot to it (A21). After a move, the old path is forgotten once nothing references it (`:129-131`, M2).
- The window keeps showing the renamed buffer, edits included (T106, on the route of DESK:2442-2444): A19's landing finds it still listed and shown and leaves it (`window/routines.lua:412-419`). A new name that isn't on disk yet (`:file new`) is registered when the rename settles (`history/hooks.lua:120-122`, M3), and A21 doesn't check the current slot's file on disk, so it stays tracked, and its window stays open (T284).
- `:saveas` fires the rename events on the extra buffer it makes for the old name too (listed, unloaded). That buffer isn't registered, so `BufFilePre` records nothing for it, and it stays unregistered until it's entered, like a `:badd` buffer **[code]**. While a rename is in progress, the old name stays registered to the buffer, so cleanup has nothing to heal **[inferred]**.

**`:w name` on a No Name buffer.** Neovim deletes the buffer and makes the same buffer number again under the name. `BufDelete` of a registered No Name buffer notes it with its history (`history/hooks.lua:175-184`), and the delete runs as any delete does (A19): one with text goes on the closed stack, its text cached and its history kept, and an empty one is untracked. `BufWritePost` claims the note at the event and settles it as a move once the write settles (`:193-200`): the old `NONAME_` name never was a file. Its history comes back under the new name and its notes follow, with no ghost left on the closed stack (T238). A note no write claims is dropped once the batch settles, so `:e` reusing an empty unnamed buffer stays plain navigation. An empty No Name buffer's delete may have forgotten its path already (M5); its write then settles as neither a copy nor a move, and the buffer is just registered under its new name **[code]**.

**`BufWritePost` on an unregistered buffer** registers it once the write settles (M3).

**Decided: the disk decides** (DESK:1924):
- If the old name still exists as a file afterwards, the rename is a copy and the old name goes on the closed stack.
- Otherwise it's a move: every reference follows to the new hash, and nothing goes on the stack.

Built in step 4 (T107, T238, T272). The trail gets the copy or the move (A27, T417).

**Decided:** the settle rule covers renames too (DESK:1783). Built in step 4: a rename is decided once it settles, and `BufWritePost`'s update waits too (P2). `BufDelete`'s own bookkeeping still acts inside the event, since the buffer is gone afterwards.

**Decided (2026-10-20 evening), "Keep the older one":** "every reference" includes the secondary map's `-swap` keys, which `rename_hash_in_triquetras` will carry as it carries dtm's (`window/data.lua:151-154`; M7, T192). Built in step 3 (`window/data.lua:161-165`).

### A21. `cleanup_triquetras`: on every history transition

**Today** (`window/routines.lua:515-801`). It runs on every history transition: every arrival once it settles, and every `BufDelete`, rename once it settles, cycle start and stop, and load. It also runs from the UI derive path, and from `cleanup_system` when its stale pass forgot a buffer or a global history entry was no longer known (A22). It wipes no buffer and switches no window: it changes only cavediver's data (P8). What it changes in a window goes into the trail: a current slot repointed, a slot or a queue entry cleared, a triquetra dropped (A27, T403, T406). For each triquetra in turn:

1. **The current slot's buffer is not open.**
   - If the window shows some other *registered* buffer, re-point like navigation, notes included (Q18): when it's the secondary, the swap notes go first (`write_secondary_swap_notes`, M7) and the old current trades places with it, `s := old c`; otherwise, with a ternary T other than the shown buffer, `dtm[old c-swap] := nil` and `dtm[old c] := T`, and the old current goes into the ternary, `t := old c`; then `c := that`. Notifies "Healed the triquetra of window <w> with current slot: <bufnr>", with no level **[run s11]** (`:528-544`).
   - Otherwise:
     - an invalid window → drop the triquetra
     - the window shows the buffer being deleted → it lands once the delete is over (A19, `:568-573`)
     - the window shows a `buftype ""` buffer whose name hashes to the current slot, unregistered for the moment (a reload without events) → nothing to heal (`:574-578`)
     - the current slot is on the closed stack → it's kept: the window is visiting, and that's the file it was last on (`:579-583`; A2, T270)
     - the window shows the same file under another `buftype`, or an `acwrite` buffer such as oil's (`:584-661`):
       - try ternary, then secondary, then `primary[1]`. The first open one becomes `c` and is tracked. The window keeps showing what it shows (`:611-616`, T247).
       - when none is found: drop the triquetra if the slot's path is known, else take the most recent buffer, else drop the triquetra (`:619-661`)
     - the window is visiting anything else, and its current slot names nothing open or closed → drop the triquetra (`:662-676`)
2. **The secondary.** Cleared when either of these holds (`:681-705`):
   - it has no path
   - it isn't a No Name buffer, it's not open, and it isn't on the closed stack

   A secondary pointing at an open buffer is kept whatever the disk says, and its buffer stays registered (T239). So is a closed one: a file gone from disk stays while it's on the closed stack, and using it says so (A6, P9; T44). An open one is cleared only when it has no path, and then its buffer is also unregistered (`:701-703`).
3. **The ternary.** The same rules, reading its own slot (`:707-731`; T227).
4. **Primary entries.** The same rules, each reading its own entry (`:733-759`; T57). The entry is removed from the queue.
5. **The current slot.** When it has no path, its buffer is unregistered (`:762-768`). Its file on disk isn't checked: a new file not written yet, or one deleted on disk, stays current and tracked (M3; T109, T110). The wipe that **[run s08, s09]** traced here is D14's.
6. Refresh the window's UI cache (`:770`).
7. **After the pass**, every window whose current, secondary or ternary slot the pass moved gets the check where a slot changes under the current buffer (`:788-800`, A1, T287).

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

**Today** (`history/routines.lua:1659-1788`). The timer runs every `cleanup_interval` ms, 4 s by default, and its first tick is immediate; it calls `cleanup_system(true)`, which only changes how many files pass 4 checks (M11). It also runs at once from the UI refresh when a slot's registered buffer is no longer valid (M12, T242). No pass wipes a buffer. Passes:

1. **Stale registrations:** for each registered buffer that's no longer valid (`:1673-1716`):
   - When the same file is open as another buffer, found by exact name over `nvim_list_bufs()` (`find_buffer_by_filepath`, `:1640-1650`, never for a No Name hash), the registration is re-pointed to that buffer, and the hash keeps its history (T113, T273).
   - Otherwise a file, not a No Name buffer, is closed into its pools like any other close, unless it's on a pool already, so slots keep it and reopen it (`close_into_pools`, M5; I4, T242). Only its buffer is forgotten: closed, it stays known, so its history stays (`:1691-1707`, M4).
   - A No Name buffer goes through `detach_filehash_from_crux` (`:1614-1631`, `:1711`): it removes the hash from the history view, global and window history, and unregisters the buffer; follow along then forgets its path unless a slot still holds it (pass 3). It touches only cavediver's own data.
2. **The closed stacks:** on every pool, remove entries with no path, and entries that are open again, whose pool goes into their `came_from` (`:1718-1746`, M5). Each removal marks its pool changed, so its session's records are written (`:1738`, S1 Records). A closed file gone from disk stays: it may come back (P9; T114, T214). The pass walks each stack from the newest down and checks for a path before reading it. DESK:2480 recorded the pass reading `filepath:match` before the nil check and removing entries inside an `ipairs` loop, before step 6.
3. **Follow along** (`:1748-1758`, `follow_along` at `:766-821`): a hash is known while an open buffer, a slot, a primary queue or the closed stack holds it (`is_filehash_known`, `:194-223`). The notes whose key, `-swap` keys included, or value isn't known go from both maps of every triquetra, and the entries whose hash isn't known go from the history view, the global history, every window's and every pool's visits. Then each such hash's path goes through `unregister_filepath`, so it stays while anything still references it (M2, I2). A registered buffer stays whatever the disk says. The report lists the global history entries that were no longer known as orphaned files, by hash once their path is forgotten **[code]** (**[run s08]**: "CAVEDIVER CLEANUP REPORT: … Orphaned files: …/brandnew.txt").
4. **Files gone from disk** (`:1761-1763`, M14): `refresh_label`, then, unless a change of label just checked every known file, `mark_missing` with the label recorded. On a timer tick the check takes the open buffers and every slot and primary queue entry each time, and the rest of the known files 500 at a time (`:627-654`) **[code]**. A save, a load and the UI's on-the-spot repair call `cleanup_system` with no argument, and check every known file. A file gone is tagged and one that's back has its tag cleared; nothing else changes. The tags add nothing to the report's total, so this pass never makes it notify **[code]**.
5. **A triquetra reference count:** reported but never acted on.
6. **When the stale pass forgot a buffer, or a global history entry was no longer known:** run A21 on every triquetra and rebuild the ordered lists. A re-point in the stale pass doesn't count, and neither does a closed entry the second pass removes **[code]**.

Each repair is a move in the trail, and nothing is said: the timer runs it as a step of the ledger's own, and so does the UI's on-the-spot repair (`history/init.lua:60`, `ui/routines.lua:1000`; A27, T398). A registration re-pointed, a file whose buffer vanished, closed onto its lists, a No Name buffer that vanished, and an entry the closed-stack pass takes off each leave one (`history/routines.lua:1687`, `:1703`, `:1709`, `:1729`), and so does each file follow along forgets (`history/routines.lua:812`). The report is still returned. **[run s08]** recorded the timer notifying "CAVEDIVER CLEANUP REPORT: …" at INFO whenever the total was above 0, before step 8.

**Decided:** the 4 s timer stays as a safety net that only repairs cavediver's own data. The stale pass re-points to the file's live buffer, found by exact name, and never wipes. History follows along. Closed entries whose file is missing stay (DESK:1863-1876). Built in step 1: the stale pass's re-point, and no pass wipes. Built in step 6: history follows along, and the notes with it (P10, I17; T208, T252), and closed entries whose file is missing stay (T114, T214).

**Decided (2026-10-23):** the timer's report stops notifying, and each repair goes into the trail in plain words (the author: "Into the trail (Recommended)"; A27). Built in step 8 (T398).

### A23. Debug commands

Created by `setup()`, and made again when it runs again (`init.lua:205`, `:244-459`):
- `:CavediverHistoryData`, `:CavediverNavigationData`, `:CavediverWindowData` and `:CavediverUIData` print `vim.inspect` of the domain's data.
- `:CavediverTriquetra` and `:CavediverTriquetraVerbose` print the current window's slots, with names and loaded or closed in the verbose one. `:CavediverTriquetra` also prints the maps.
- `:CavediverRegistry` prints both registries and every pool's closed stack, each under its session's name, the editor's as "(the editor's)" (`init.lua:313-320`).
- `:CavediverAllTriquetras` prints every triquetra and UI cache.

`:CavediverClosed`, made by `setup()` beside them, isn't a debug command: it opens the closed lists (`init.lua:206-208`, S2 Closed-stack picker). Nor is `:CavediverDump <file>`, which opens a flight recorder's dump (A26), nor `:CavediverTrail`, made beside it, which opens the trail, or with a name that name's life line (`init.lua:235-237`, A27), nor `:CavediverWinbar`, `:CavediverIndicators` and `:CavediverBufferline`, the toggles, each taking `on`, `off` or `toggle` (`init.lua:212-234`, M12).

The `CavediverTriquetra*` commands print `primary_buffer[1]` as "Primary buffer". **Label:** intended (debug only). The descriptions say "curernt" (`init.lua:248`, `:251`).

### A24. Query and utility exports

These take no action. They return live tables, not copies:
- `get_buffer_history()` returns the history view (`history.data.crux`), not an ordered list. STATUS:471 says "ordered".
- `get_window_triquetra(w)` calls the getter, so **it can create a triquetra** (M6).
- `get_all_triquetras()` returns `window.data.crux`.
- `get_*_state()` and `is_cycling()` return the machines' states.
- `set_cache_from_window_triquetra(w)` re-derives one window's UI cache.
- `get_smart_basename(filehash)` is the UI's, a buffer's shortest unique name (M12, T120).

### A25. `setup(user)` and what runs at require

**Today:**
- `require('cavediver')` loads every domain. That registers the state-machine hooks and sets `current_window` and `last_valid_window` to the current window (M10); it creates no autocmd, command or timer (T126, T254).
- `setup(user)` (`init.lua:168-241`):
  1. merges the config; with no argument it uses the defaults (M13)
  2. creates the `cavediver` augroup with `clear = true`, and each domain's autocmds in it, the ledger's first (A27), the storage domain's `SourcePost`, `TabClosed`, `VimLeavePre`, `TextChanged` and `TextChangedI` included (`init_autocmds`, `:192-198`; S1), and turns on the records cavediver writes itself (`write_records_on(true)`, `storage/init.lua:179`; S1 Records)
  3. defines the highlights
  4. starts the UI timer and the cleanup timer, and lets git's HEAD be watched (M14)
  5. creates the debug commands (A23)
  6. maps the keys

  Calling it again replaces the autocmds, the commands and the timers, leaving one of each (T127), and maps the keys again. The popup's buffer-local autocmds, made when it opens, and a reopened No Name buffer's one-shot `BufWinEnter` aren't in the group (M11).
- `disable()` (`init.lua:467-473`) clears the augroup and stops both timers, so nothing is tracked or refreshed until `setup()` runs again (T240). It also stops the watch on git's HEAD (`enable_head_watch(false)`, `:471`; M14, T346), and the records cavediver writes itself: a write still pending is dropped, a tab close's included, a change tells nothing, and with the augroup cleared no tab close or quit writes either, until `setup()` runs again (`write_records_on(false)`, `:472`; S1 Records, T364). The keymaps and the debug commands stay **[code]**. A save or a load after it still runs `cleanup_system`, which reads the label and checks the files, but doesn't watch HEAD (A22, M14, T346); a tab-session save still refreshes the unnamed session's records, as part of the save (S1 Save) **[code]**.
- Until a load or a first `BufEnter`, nothing is registered. The buffer nvim starts on isn't tracked until something enters it.

**Decided:** nothing runs at require. `setup()` creates everything inside one `cavediver` augroup with `clear = true`, and running it again replaces it all. `setup()` with no argument uses the defaults. `disable()` clears the augroup and stops the timers (DESK:2177). Built in step 2. Built in step 7: `setup()` turns the records cavediver writes itself on, and `disable()` turns them off (S1 Records, T364).

### A26. The flight recorder (decided 2026-10-21; built in step 8)

The author's idea, 2026-10-21: "maybe for debugging purposes, we log the sequence of the winbar rendering, which shows the triquetra, and also other things like the displacement, and other things. this is for only things that _shouldn't_ happen."

**Decided (2026-10-21):**
- It **records all the time** into a small ring of the last N steps (oldest dropped), and **dumps only when something that shouldn't happen fires** ("Yes, ring + dump").
- A step is cavediver's **keymap actions** (`<M-f>`, `<M-S-f>`, the restores, cycling, primary keys, `<M-.>`, `<M-S-w>`) and the **editor events** it reacts to (`BufEnter`, `WinEnter`, `BufDelete`, renames), never raw keystrokes. The author: "i meant the keymaps not keys. and events make sense as well." Each step keeps the window and the result as `⦉ternary⦊ [current] ⟦secondary⟧`, the primary queue and the notes.
- What fires a dump: the restore assertion (`window/routines.lua:1148-1150`), the fill assertion (D11), "Duplicates detected" (`window/hooks.lua:90`), the highlight callbacks' `error()` (`ui/init.lua:297` and on), "This impossible error should never happen" (the restore's no-path throw; D9 removed it in step 3, so there's nothing to fire), and a hook failure (caught with traceback, decided on the desk).
- The dump goes to **both** a file (under `stdpath("state")/cavediver/`, decided 2026-10-21: "Yes, state dir"), in the sandbox's row format so it replays as a scenario, and a scratch buffer opened on the spot ("Both"). The error message says where the file is.
- **It dumps at the first break of I1 or I23**, checked after every step, not only when an assertion fires ("Yes, first rule break", 2026-10-21). The slot exchange shows why: the rule broke when `<M-;><M-t>` swapped the slots under the current buffer, but nothing threw until a later `<M-;><M-r>`, by which time the cause could have left the ring. Assertions still dump too.
- **It records cavediver's own model changes as steps**, tagged by cause: keymap, event, timer (the cleanup re-points), load (a session load, with its notes from the file), `:restart`. Session loads are marked, so a stale note that arrived from the saved file shows it has no cause inside the session ("Yes, tag by cause", 2026-10-21).
- **Decided (2026-10-21), needed for the replay (T201):** the dump opens with a snapshot of the state at its first step: every window's slots, primary queues and on/off, both note maps with swap notes, global and per-window history with access times, the closed stack, navigation and history states with cycling origins, `history_view`, and which files exist. The file has a machine-readable part (snapshot plus steps) that replays, and the rows for reading.
- **Decided (2026-10-21; proposed by Kate, taken by the author: "Drop the 30, One dump per failure, Dump window untracked, The other three"):** one dump per distinct failure (the highlight callbacks run every 140 ms); the scratch buffer opens after the editor settles; the dump window is `nofile`, unlisted, and invisible to the model; one assertion helper that every "shouldn't happen" goes through, with the engine's hook-failure catch hooked in; ~~file names written as aliases (f1, f2…) with basenames~~, replaced 2026-10-24 once the dump was sealed: it holds things as they are (the author: "wait, why is it still bare? You can just put the thing now"; What's in it, below).
- N, the ring's length, is `ledger.ring`, 1,000 by default (decided 2026-10-23, the author: "Configurable, 1,000"). The ring is one view of the ledger (A27), which adds two causes of mine, a save and a change of label, and takes a command typed on the command line as a keymap action, by its text. Built in step 8: the ring (A27; T392, T199), the dump, the I1/I23 checks and the replay, as below.

**Mine, how the dump is built** (the author, 2026-10-24, of the open format and the picker's interface: "Yes, you settle them"). Built in step 8 (`ledger/dump.lua`, `ledger/replay.lua`; T200–T205, T241, T275–T278, T333, T468, T469):
- **One helper.** Every "shouldn't happen" calls `require('cavediver.domains.ledger').never(message)` (`ledger/init.lua:36-39`), which dumps once per distinct message and then raises `error(message, 2)`, so the text and the place the error names are what `error()` gave at that site (T34, T66, T176 read them). The sites are every `error()` raised for a state only a cavediver bug can reach, 37 of them: the restore's, the fill's, both "Duplicates detected", the colour callbacks' "No current triquetra found", the one-role check, the derive path's "current_bufnr is nil" and its two "This is unexpected", the UI cache's missing triquetra, the cycle's origins, the ternary that must have a buffer, the close key's "not found in ordered history", the history's "not registered", the closes of a hash with no path or no buffer, the registry's two guards, the hooks' checks of their context, the reconcile's and the cleanup's own checks, and the storage's five. The ones a user's input or the world can reach stay plain `error()`s: a write that fails, a newer file, the cwd, a timer that can't start, cokeline missing, `get_smart_basename` given a bad argument, and the pop-up's save once its window has no triquetra. No caller catches one of them as an ordinary branch.
- **Hook failures.** The engine's catch for a hook that isn't critical hands the hook's name and error to `on_failure` when it's set (`engine/helpers.lua:6`, `:50-52`); the ledger sets it in `setup()` (`ledger/init.lua:58-60`), so the engine knows nothing of the ledger. The dump writes it once per distinct hook and error, unless it's a message `never` already dumped (`hook_failed`, `ledger/dump.lua:514-523`). Whatever its cause: a load that fails for an environment reason, libcrypto missing, dumps too, since the catch can't tell a bug from the world. The critical save hook's failures reach the manager and don't dump: an environment failure there isn't a bug.
- **The rules.** I1 and I23 are checked over every triquetra at a step's close, when the step held open its full four settles (`close`, `ledger/routines.lua:281-300`; `closed`, `ledger/dump.lua:533-556`): a step a new trigger closed early may have follow-ups still to land, as under a macro or a mapping that switches buffers several times. A break is dumped only when it's still there once the editor settles after. Each distinct break, its rule, window, file and map, dumps once. A step that dumped already, by an assertion or a hook failure, marks the breaks it left as dumped, since its own dump shows them: T200's route dumps once, for the restore's assertion, and not again for the stale note planted before it.
- **What a dump holds.** The steps since a checkpoint: a snapshot of the state is taken as a step begins once the ring has kept 50 steps since the last one, and the last two are kept, so a dump starts from the older one, 50 to 100 kept steps back, the snapshot the decided "snapshot at its first step" is (`began`, `ledger/dump.lua:133-147`). A step the ring didn't keep, a timer's tick that did nothing, isn't counted, so an idle editor doesn't push the steps worth seeing out. The snapshot holds every triquetra, its slots, queue, switch and both maps; the global and per-window history with their times and `history_index`; every list's closed files and times; the tags of files gone from disk; navigation's and history's states and the cycle's start; `history_view`; and which files exist. The step the failure fired in is the last row, its row as the failure found it. Under the heading, the settle work still queued when it fired, by name, `pending: arrival b.txt` (`ledger/dump.lua:317-321`; M11 Settle work, T467).
- **What's in it.** The file is sealed (below), so it holds things as they are (the author, 2026-10-24, once it was sealed: "wait, why is it still bare? You can just put the thing now"): each file by its hash and its full path, listed once, a No Name buffer by its `NONAME_` name; each list by its session's name and directory, `editor` for the whole editor's; the tags of files gone from disk with their labels; windows by their numbers and their ids; each step's trigger as the ledger recorded it, a command line's paths cut to their last part as the ledger cuts them (A27); what fired, and a hook's traceback, as they came. No Name texts aren't in it: a dump records rows and notes, never a buffer's text (T333). Before 2026-10-24 the file was plain, and everything went by alias, paths, hashes, session names and labels left out.
- **The file.** `stdpath("state")/cavediver/dump-<date>-<time>-<n>.txt`, `<n>` the first number no file of that second has, since another editor may have written one, written atomically in mode 0600, its directory 0700. **Decided (2026-10-24), sealed** (the author, asked "is the dump encrypted?" and shown it wasn't: "Sealed, like the session", with the note "does this slow down things a lot?", then, with the cost put, nothing while you edit, about 30 ms on an editor's first dump and under 1 ms after: "Sealed (your pick)"). The reason is the session file's: a dump is usage data (the author: "the reason why it's sealed because you are saving usage."; DESK:1541). Mine, how: `CDV1`, a salt, then the text sealed with AES-256-GCM under a key stretched from the global directory as a session's is, the additional data `CDV1`, the salt and `dump`; the salt is one per editor and its key is kept once it's made, so only an editor's first dump stretches it (`write`, `ledger/dump.lua:376-385`). A dump opens only from the directory it was written in. Inside it: a heading with what fired and when, the files by hash and full path, one row per step (its time, cause, trigger, window, its row before → after as the trail writes rows, and the current file's notes), the row it fired at marked, and a `replay:` part holding the snapshot and the steps as JSON. Once the editor settles, a WARN says "cavediver: something that shouldn't happen did (<what>); its last steps are in <path>."; the error keeps its own text (`fire`, `ledger/dump.lua:398-444`; T277).
- **Reading one later.** `:CavediverDump <file>` (`init.lua:209-211`; `open` and `read`, `ledger/dump.lua:481-492`, `:454-472`) opens a dump, from the directory it was written in, in the same kind of float, entered, its `replay:` part included; anywhere else, or edited, it says the dump doesn't open there and opens nothing (T460). When the file can't be written, libcrypto missing for one, the window still shows the rows, and the WARN says the file wasn't written.
- **The window.** Once the editor settles, a float, not entered, on a `nofile`, unlisted buffer that goes with its window, named `cavediver://` and the file's name, holding the rows; `q` closes it (`show`, `ledger/dump.lua:341-365`). No step is begun about it: an event in a window showing it begins none, nor does a command line typed there (`ledger/init.lua:45-47`; T205).
- **The replay** (T201, T202, T468, T469), mine in how. `require('cavediver').replay_dump(path)` replays a dump into a fresh editor started in the dump's own project, the directory it opens from, and refuses an editor that tracks anything already, but empty No Name buffers: a config that calls `setup()` at startup takes in the empty buffer Neovim starts on, and the replay forgets it, and any like it, before it plants (T471). It plants the snapshot: as many windows as it holds, matched by number to the tab's windows in order, each on the buffer it showed; the files, opened, or closed onto the editor's list when that list held them, with their close times; every triquetra; the global and per-window history and `history_index`; the tags; `history_view`; and a cycle running, with its window and start. Then it takes the steps in order, each in its window, by number, once the settle queue has run (M11): a keymap step is driven through its mapping when its key is one of cavediver's own keymaps (a view's key, or anything the editor maps that cavediver doesn't, is planted) **[code]**, and a command step through the command, when the command moves windows or buffers only (`:edit`, `:buffer`, `:bdelete`, `:bwipeout`, `:split`, `:vsplit`, `:close`, `:only`, `:enew`, `:wincmd`) and runs nothing else: it's run as parsed, with no `|` after it and no file expansion, and one chained with `|`, given a `+cmd`, or naming a file with a backtick is planted (T470); every other step, an event's, a timer's, a load's, a save's, `:restart`'s, a label's, and any other command, `:lua` and `:w` included, has its recorded row planted instead of being run, so a replay writes no file and runs no code of the dump's. After each driven step its window's row is compared with the recorded one. It returns the steps taken, the driven ones and how many matched, each mismatch, and the error a driven step raised, and says so in one INFO line. A row records what its window shows (`shows`, the hash of the window's buffer) for this, and keeping a step ignores it (A27).
  - A replay's editor isn't a session: once a dump is replayed, `save_session` throws "cavediver: this editor replayed a dump, so its state isn't a session, and it isn't saved.", which stops a session manager's save too (I21), and cavediver writes no records (S1 Records) (T468).
  - A dump whose windows span more than one tab isn't replayed: a WARN says "cavediver: this dump spans more than one tab, which a replay doesn't recreate." and nothing is planted (T469).
  - Mine: every list's closed files go on the editor's list, a replay having no tab sessions; a dump that can't be read, an editor that tracks anything but empty No Name buffers, and one where cavediver isn't set up (its keymaps not mapped) are refused, each with a WARN saying why. A fresh editor means Neovim started in the project with cavediver set up and no session loaded; the README says how, and how to start one when a config loads a session at startup (README:573-577).
  - Built in step 8 (`run`, `ledger/replay.lua:324-408`; the snapshot, `:258-312`; the planting, `:169-246`; the commands driven, `:12-15` and `:25-38`; the keys driven, `:46-53`; the editor's start buffer taken as fresh and forgotten, `:59-106` (T471); the save refused, `storage/init.lua:29-32`; the export, `init.lua:520-522`; `shows`, `ledger/routines.lua:81-82`, left out of keeping a step by `same_row`, `:144-154`).
- Configurable (mine): `ledger.dump`, `true` (`configs.lua:326`); `false` records the ring and dumps nothing.


### A27. The ledger and the trail (decided 2026-10-23; built in step 8)

The author asked for messages "so that me and the users don't get confused or left wondering how this happened", ticked all four offered, and then shaped the fourth, the trail, over a round of questions (2026-10-23, BUILD_LEDGER from 19:03 to 20:08; the mock the author approved, "LGTM", is the reference for its look). Where a line quotes an option the author ticked, the quote is the option's own text.

**The line** (mine, put to the author with the four options): speak up when the result differs from what the key made you expect, or when something you can see changes without you asking; the rest stays quiet, in the trail.

**One ledger, two views** (the author: "Yes, one ledger (Recommended)": one recording point and one record shape, the trail its first view, the ring the second). Cavediver records into one place:
- A **step** is what set things off (the author: "Triggers first", "Each block starts with what set it off (⌨ ⚡ ⏲ ◆ ↻ ⎇), cavediver's moves hanging under it"): a keymap action `⌨`, an editor event cavediver reacts to `⚡`, the cleanup timer `⏲`, a session load `◆`, `:restart`'s reload `↻`, or a change of label `⎇`. Mine: a save is a step too, `◇`, and a command typed on the command line is a `⌨` step under its text (`:bdelete c.txt`): the line as entered, never the keys that typed it (A26). A step holds its time, its cause, its trigger as written, its window, that window's row before and after with its primary queue and notes, as A26 keeps them, and the moves it made.
- A **move** is something cavediver did in a step that the trail shows: its own decisions (where a window landed, a note rewritten, a file taken off other lists) and the bookkeeping the key's own result left (the file a close put on the tab's list). Each has its family and glyph, its subject (a file, a list, a window), its words, and, where it has them, the lists it names, a row before → after and the items folded under it.
- **The ring** keeps the last N steps in memory (`ledger.ring`, the name mine, 1,000 by default; the author: "Configurable, 1,000"). The author put the ring in step 8; mine: it's built with the ledger, recording only, and its dump and the I1/I23 checks are A26's.
- **The trail** keeps the steps that made moves, by day, across restarts.
- Mine, for the build: the record shape, steps and moves, is documented with the configuration and kept stable, since the formatters (Configurable, below) read it.

**What's recorded** (the author: "Slots, Notes, Cycling, Sessions and renames", on top of the closed lists, the repairs, the disk's tags and tab sessions):
- closed lists: a close, onto the tab's list and onto any other; a reopen and the lists it took the file off; a file forgotten by follow along. Mine: a detached list made or left, since detached lists were decided after this round;
- the disk: a file tagged as gone, and back;
- repairs: the cleanup's stale pass (a registration re-pointed, a vanished buffer closed), the closed-stack pass, orphaned history. The cleanup report stops notifying, and each repair goes into the trail in plain words (the author: "Into the trail (Recommended)");
- slots: the cleanup's re-point, the landing after a delete, an arrival undone, a slot cleared, a triquetra dropped;
- notes: "Keep the older one"'s rewrites, Q6's guard, navigation's own check, follow along's drops. Mine: a note a restore clears because nothing names its hash;
- cycling: the cancel on a window jump;
- sessions: what a load matched, dropped, closed and reopened. Mine: a save, the unnamed session's refresh, the `:restart` reload, a tab session's tab closed;
- renames: a copy or a move. Mine: a No Name buffer written under a name.

The author's three pop-ups, "Healed the triquetra…", "Avoided conflict…" and "…switching with the pre-jump ternary.", stay, and each also leaves a move (the author: "Pop-up and trail").

**Three messages** (the author ticked them, 2026-10-23):
- "Empty pool on <M-S-w>": "Instead of "No closed buffers to reopen.", say this tab's pool is empty, how many closed files other tabs have, and point to :CavediverClosed." Mine, confirmed by the author (2026-10-24: "Only then (as built)"): only while other lists hold closed files; with none, "No closed buffers to reopen." stays as it is (T87). It's a WARN, as that message is. Its words, the author's pick: A16.
- "Close into other pools": "When a close also lands in other tabs' pools (your "Both"), name them in one INFO line: "a.txt closed here and in notes"."
- "Reopen out of pools": "When a reopen takes a file off other tabs' pools, name them in one INFO line."

**The trail kept** (the author: "Keep it across restarts"; its length "unlimited, we load by sliding window, we have a binding in the buffer that goes to the "next page" and "previous page""; a page is "One day": "A page per day with moves in it; next/previous steps a day; a busy day is a long page"):
- Mine, my take the author's answers built on: each page is its own sealed file in `<main>.d/`, named through the session's key after its date, and the main file lists the pages by date. A load reads no page; a page is read when it's shown or searched.
- The pages ride with the records (S1 Records): today's page is written whenever the session's records are, and at the saves (the author's "Yes, all three moments" took the pages along).
- Mine: the whole editor's session file keeps the moves of the tabs it covers, every tab, or, while it's the unnamed session, the tabs in no tab session (S1 Records); a tab session's file keeps the moves that name its list or happened in its tab.
- Built in step 8 (T420–T424), mine in how: a page holds the day's steps with moves, each with its time, cause, trigger, its tab's list as it began, its names, its events and its moves; it's named `sha256(<the key in hex> .. "\ntrail\n" .. <date>)` with `.trail` added, so it's told apart from a text's file, and sealed with the session's key, `CDV1` and the date as its additional data (`page_name`, `read_page`, `storage/routines.lua:1585-1613`). Each write of the main file, a save's or the records', writes the pages for the days the ledger holds steps of that session, the step still open included: the steps editors before this one wrote that day, read once from the page on disk, then this editor's; a day with no new step or move isn't written again, and earlier days stay listed (`write_trail_pages`, `storage/routines.lua:1668-1714`; `steps_kept`, `:1624-1648`). A page that fails its check reads as nothing, and the next write of its day keeps only this editor's steps. `trail_days` and `read_trail` read them (`storage/routines.lua:1720-1740`). A save's own "saved" move lands after its commit, so the next write carries it. A page that can't be written at a save leaves the pages the file had, with a WARN said once, "cavediver: the trail's page couldn't be written (<error>); the session is saved without it." With two editors on one session, each writes its day's page over the other's: what the other wrote after this one started is lost, as with the records (S1 Records).

**`:CavediverTrail`** (the author: "Its own command (Recommended)": ":CavediverTrail opens a scratch buffer, untracked, newest last"), a `nofile` buffer on today's page:
- **The header, "the dive"** (the author's notes: "put everything in the center. put something like <<< H and L >>> at the sides. add some neat colors if you can, and add the index of the day, like relative, 0 at today. Put the gauge and entry count together as well."): a fill shaded by how far down the day is, `≋` today, `░` within a week, `▒` within a month, `▓` older; in the middle `⦉ trail ⦊`, the date, "today" or "n days down", counted in calendar days, the number of moves and the day's tally by family; the seabed gauge, one bar per page, the shown page marked `❬ ❭`; `<<< H` and `L >>>` at the sides, dim where there's no page to go to. Mine: a narrow window drops the tally first, then the gauge.
- **The lines:** each step that made moves is a line, newest last: its time, its cause's glyph and its trigger first; its moves hang under it on branches, each its family's glyph, its subject and its words, with a slot move's row before → after under it. Families by colour: closed `↓`, reopened `↑`, forgotten `∅`, gone `✗`, back `✓`, repair `⚒`, slots `⟲ ⤳ ↶ ⊘`, notes `✎ ⌫`, cycling `⇤`, sessions `◆ ◇`, renames `⇢ ⧉`. The author: "Brightness by surprise": "Choices you can see in full colour; bookkeeping dim." In the approved mock, a close onto the tab's own list, under the key that closed the file, is dim. "Repetition folds": "More than three of a kind under one trigger fold to a count with ▸, opened with za."
- **Keys**, the one grammar (the author: "Adopt it (Recommended)"): `H` and `L` the older and the newer page (the author: "H and L", "Left is back in time; H older, L newer"), a page being a day with moves; `s` searches every page for a name (the author: "s (Recommended)", "Across every page": "A search (e.g. :CavediverTrail a.txt) reads the pages one by one and lists every move that names it, newest first"), and `:CavediverTrail <name>` searches the same way; a search reads as the name's life line, a gutter bar coloured by its state at each line (the author: "Yes, the life line": "One bar per searched name, coloured open / closed / gone between its moves"); `<CR>` on a result opens its day there, and `q` goes back. The search option said newest first and the approved mock's life line ran oldest first; **settled (2026-10-24): oldest first** (the author: "Oldest first (as built)"). **Decided (2026-10-24), a window's search:** the moves cavediver made to a window, landings, repoints, cancels, undos and drops, followed by its id, so within one editor, since a window's id is new after a restart (the author: "Moves about it"); `*` on a window's move does the same (T455). Mine: `:CavediverTrail win <N>` names window N of the tab the trail is opened from, `:CavediverTrail win` that window itself, and a name of that form is always a window, never a file's basename. Built in step 8 (`ui/trail.lua:949-960`, `*` at `:797`; T455). `za` opens a step into the ring's steps since the trail's line before (the author: "za (Recommended)", "since the line before, not capped. maybe default it is cap, but we can "read more" with a keymap.", "Expand in search too"); mine: 20 at a time, the "… n earlier steps" line opening 20 more with `za` too. `gf` on a name acts on it, a file opened, a `≡list` shown in the closed lists, a window gone to; `*` searches the name under the cursor (the author: "Live names"); `q` and `<C-c>` leave. A line from before a restart doesn't expand: the ring is in memory alone.
- Built in step 8, the day view (T425–T434), mine in how: `:CavediverTrail` opens a float (`trail_popup`, 0.8 by 0.8, a ratio or cells) on a `nofile`, unlisted scratch buffer that goes with its window, filetype `cavediver-trail`, which nothing tracks, on today's page or the newest day with moves; the trail shown is the tab's, its tab session's or else the whole editor's, read by the rule its pages are written by (`open`, `ui/trail.lua:885-961`; `trail_session`, `trail_reader`, `storage/routines.lua:2378-2445`). The session's main file is read once as the view opens, and a page only when it's shown, each once while the view is open: the gauge counts only the days it draws (T433). Each line is drawn from the records, and a map of what each stands for is what the keys read (`draw`, `ui/trail.lua:630-670`). The header as above (`header`, `ui/trail.lua:241-316`): the tally counts the day's moves by family, a glyph for each; the gauge shows up to 15 days around the one shown, newest on the right, since the pages have no limit (mine); a window too narrow for all of it drops the tally, then the gauge. A step's line, its moves on branches, a slot move's row under it, the bookkeeping kind dim, more than three of a kind folded to a count that `za` opens, a fold being that day's and that step's own (`day_lines`, `ui/trail.lua:409-517`; T434). `H` and `L` go to the older and the newer day, and `q` and `<C-c>` leave, `<C-c>` as `keymaps.views.leave_too` (mine), which the closed lists take too.
- Built in step 8, the rest of the keys (T435–T445), mine in how. `za` on a step the ring holds, marked `▸` at its right, opens the ring's steps since the trail's line before it, the nearest 20 first, each with its time to the second, its trigger, its window, and its row before → after when that changed, or else its events; a line "… n earlier steps (za for 20 more)" opens 20 more, and `za` on the step closes them (`ring_lines`, `ui/trail.lua:372-402`; `day_lines`, `ui/trail.lua:409-517`; `M.fold`, `ui/trail.lua:720-738`). A search's result opens the same way, the ring's steps since its day's line before its step, under the step's first result, and stays open on its day too (T443). A step is in the ring when the ring holds that very record, so a line from a page, written by an editor before this one, has no `▸` and opens nothing (T437). `s` asks for a name through `vim.ui.input`, `*` takes what's under the cursor, and `:CavediverTrail <name>` opens on a name: each reads every page, one at a time, and lists the moves about it, oldest first, the approved mock's order, a line each: the day where it changes, the time, the bar, the step's cause and trigger, the move's glyph and words (`find`, `search_lines`, `ui/trail.lua:528-622`; `M.search`, `M.ask`, `M.search_word`, `ui/trail.lua:764-799`). A typed name takes every move whose subject goes by that name; `*` on a file follows that file by its hash, so two files of one name aren't mixed, and on anything else takes its name (T444). A No Name text's line starts over when the text is reopened, since it comes back under a new hash (M5). The bar is coloured by the state after each move: closed after a close, a copy (its old name), or a repair that kept the file on its lists; open after a reopen, or a repair that took an entry off its list because the file is open again (a move whose result isn't its kind's carries `state`); gone after a tag; and after the file's back, what it was before it went (T445). The header reads `<<< q`, `⌕ <name> · n moves over m days` and `<CR> >>>`. `<CR>` on a result opens its day with the cursor on its step, and `q` goes back from a search to the day it came from (`M.act`, `M.back`, `ui/trail.lua:842-876`). `gf` acts on the piece of the line under the cursor, or the line's name when the cursor is on no such piece: a file is opened in the window the trail came from, the trail staying open; a `≡list`, or the list a detached list's move or a tab session's tab closing is about, is shown in the closed lists, the cursor on its header when it's a list in memory; a window is gone to (`target_of`, `ui/trail.lua:324-334`; `M.act_and_stay`, `ui/trail.lua:808-835`). The list a move is about **[code]**. `gf` begins a keymap step, since it can change the editor; the view's other keys only move the view, and begin none. Each piece of a line that stands for something keeps it in the line's map with its columns, which is what `gf` and `*` read (`draw`, `ui/trail.lua:630-670`). The formatters, `formatters.trail_step(step, glyphs)`, `formatters.trail_move(move, glyphs, step)` and `formatters.trail_header(header, glyphs)`, each give a line as `{text, highlight}` chunks, and one that gives nothing leaves cavediver's own (`ui/trail.lua:423`, `ui/trail.lua:499`, `ui/trail.lua:281`; T442). A move folded under a count is drawn as cavediver draws it.

**Configurable** (the author ticked "Colours", "Glyphs, with an ASCII set", "Header pieces" and "Layout and wording"): the colours (`colors.trail`); the glyphs (`glyphs`: `"unicode"` by default, `"ascii"`, or one's own); the header's pieces, the tally, the gauge and the depth shading, each on or off; the keys (`keymaps.views`, the author: "Make them configurable"); and, mine for the build, formatter functions for a step's line, a move's line and the header, each given the record and giving text with highlights, cavediver's own the defaults.

**The primary pop-up** speaks the same language, in step 8, with its decided changes (the author: "In step 8 (Recommended)"; A18).

**Built in step 8, the ledger and its moves** (`domains/ledger/`; T392–T419, T199). How it's built is mine:
- **Where a step begins:** at what set it off. Each mapping begins its step on its own first line (`init.lua:50-151`), and so do the closed lists' keys (`ui/hooks.lua:176`); a command line entered, `CmdlineLeave` for `:` and not aborted, begins one under its text; an event cavediver reacts to, `BufEnter`, `BufDelete`, `BufWritePost`, `BufFilePost`, `WinEnter`, `OptionSet` of `buftype` or `TabClosed`, begins one (`ledger/init.lua:57-121`); so do a save and a load, under the last part of the session's name, never a whole path (`storage/init.lua:40`, `storage/init.lua:88`). The ledger's autocmds are made first in `setup()` (`init.lua:193`), so a step has begun before the other domains act on the same event. A command line is kept as it was entered, but for a path typed in it, a word that starts with `/`, `~` or `.` or names a file or a directory, which is kept as its last part (`ledger/init.lua:73-77`; T396).
- **How long it's open:** four settles (`hold_open`, `ledger/routines.lua:309-320`), so what cavediver does on `vim.schedule` after the trigger lands on it: the close key's delete and the arrival it waits for are two settles deep (T394), a window jump's cancel three (T411). An event while a step is open is listed under it and begins none, unless that step is a save or a load: a session manager saves the outgoing session and tears it down in the same call, and the teardown is a step of its own (`begin`, `ledger/routines.lua:333-346`; T402). The next trigger closes it early.
- **A cleanup tick** is a step of its own while it runs, cause `timer`, trigger `cleanup` (`within`, `ledger/routines.lua:358-372`; `history/init.lua:60`), and so is the UI's on-the-spot repair (`ui/routines.lua:1000`).
- **A session's own steps:** a tab session's save and load are steps of its own list, kept in its file, and a tab-session save's refresh of the whole editor's records is a save step of its own, kept in the whole editor's (`storage/init.lua:40-43`, `storage/init.lua:88-91`; `refresh_unnamed`, `storage/routines.lua:1828-1849`; T414, T424).
- **What's kept:** a step is kept in the ring when it's a keymap, load or save step, when its window's row changed, when it made a move, or when a whole-editor load tore it down (`close`, `ledger/routines.lua:281-300`), and the ring keeps the last `ledger.ring` (`keep`, `ledger/routines.lua:247-269`). A step with moves goes into its day's trail, in memory until the pages are built. A move made with no step open begins an event step, trigger `—` (`current`, `ledger/routines.lua:380-389`). Records hold hashes: a row is the slots, the primary queue and its switch, both note maps, and what its window shows (`shows`, which keeping a step leaves out; A26's replay plants it), and a step keeps each file's name as it captured it (`row_of`, `ledger/routines.lua:68-104`).
- **The messages:** a close onto lists other than the tab's, and a reopen off them, queue one on their step (`close_into_pools`, `open_out_of_pools`, `history/routines.lua:429-454`, `history/routines.lua:464-488`); a step says what it queued as it closes, one line for each kind, and only a keymap, command or event step says anything (`say`, `ledger/routines.lua:210-238`). A whole-editor load drops the moves and the messages of the step still open, the session manager's teardown, and keeps the step marked `torn`, before its own step begins (`drop_batch`, `ledger/routines.lua:495-503`; `storage/init.lua:86`). `<M-S-w>` on an empty list counts the distinct closed files on the other lists, those in memory and those in the whole editor's file alone, and says "No closed buffers to reopen." when there are none (`history/routines.lua:1410-1438`; `file_only_closed`, `storage/routines.lua:1925-1949`).
- **What's recorded:** each move names its subject, a file by its hash, a list or a window, with the name it had then. Closed lists: closes and reopens, with the lists they touched, the bookkeeping kind dim; follow along's forgotten files, with the notes about them that went (`follow_along`, `history/routines.lua:766-821`); detached lists made, back with their tabs at a load, left into the whole editor's file or kept, merged and gone (`push_out`, `close_now`, `settle_merging`, `storage/routines.lua:1061-1072`, `storage/routines.lua:2090-2126`, `storage/routines.lua:1994-2010`). Repairs: the cleanup's (a registration re-pointed, a file whose buffer vanished closed onto its lists, a No Name buffer vanished, an entry the closed-stack pass takes off; `cleanup_system`, `history/routines.lua:1659-1788`). Slots: what the cleanup's pass did to each window, from rows taken as it starts, a current slot `repointed`, a slot or a queue entry `cleared`, or the triquetra `dropped` (`cleanup_triquetras`, `window/routines.lua:515-801`); the landing after a delete, with the slot it came from (`land_after_delete`, `window/routines.lua:401-488`); an arrival undone, or its triquetra dropped (`undo_arrival`, `window/routines.lua:158-203`). Notes: each note cavediver rewrote or dropped by itself, by keep the older one, by Q6's guard, by navigation's own check, or by a restore clearing a note at a hash with no path (`note`, `ledger/routines.lua:442-449`). Cycling: the cancel on a window jump (`navigation/routines.lua:144`). Sessions: a load's windows matched, started fresh and entries dropped, its fresh start and why, the references it closed and the No Name texts it reopened (`load_history`, `storage/routines.lua:1287-1421`); a save; the whole editor's records refreshed (`refresh_unnamed`, `storage/routines.lua:1828-1849`); a tab session's tab closed, its records written or kept; `:restart`'s reload, a step of its own, begun by its load after the batch's drop (`storage/init.lua:88`, `storage/init.lua:135`). Renames: a copy, or a move, a No Name buffer written under a name included (`history/hooks.lua:110`, `history/hooks.lua:113`). The disk: a file gone, with its tag, and back (`mark_missing`, `history/routines.lua:604-670`); a change of label is a step of its own, the files it finds gone under it (`refresh_label`, `history/routines.lua:737-755`). The author's three pop-ups each leave their move: the re-point, Q6's guard and navigation's check.


## 4. Invariants

Each is a statement a test can check after any action. Status:
- **enforced**: held by the code today.
- **violated**: broken today, with the bug cited.
- **decided**: set by the desk and not built yet.

| ID | Invariant | Status |
|---|---|---|
| I1 | Within one triquetra, current, secondary and ternary hold three different hashes, or are empty. | **Not enforced**, but no route found that breaks it. Asserted at `window/routines.lua:343` and `window/hooks.lua:90`, but nothing dedupes. The save writes each slot as it is (S1); DESK:2440 recorded it putting `primary[1]` into a No Name current slot while the secondary held the same file, a duplicate after a restart, before step 4. `<M-S-f>`'s rename has no guard for a nil hash, though the desk's route to it (DESK:2469) throws nothing and leaves no duplicate (A7, T49). `<M-f>`'s history fallback asserts that the ordered list's first entry is the current buffer, and the window-jump cancel and the tie fix close the routes where it wasn't (A6, D11; T43, T176). T128's walks find no duplicate. Decided: the sources get fixed and the assertion stays (DESK:1939). The primary queue isn't covered: its `[1]` may share a slot's buffer (Q16). The flight recorder checks it at every step's close and dumps a break (A26, T276). |
| I2 | Every hash held anywhere has a path in `hash_filepath_registry`: slots, primary queues, both displacement maps (`-swap` keys included), history, the pools' visits, and the closed stack. | **Enforced** where a path is forgotten (T129): the six places (`history/routines.lua:1045`, `:1232`, `:1357-1358`, follow along's `:808`, `history/hooks.lua:129-131` after a move, and `storage/routines.lua:780` after a load's reopen; M2) go through `unregister_filepath`, which keeps the path while `is_filehash_referenced` finds the hash in the history, a pool's visits or closed stack, a slot, a primary queue or either map (`history/routines.lua:153-185`, `:833`). Follow along drops a hash's notes and history entries before it asks, so they don't keep its path once the hash is no longer known (I17). The fresh-start load clears the whole path registry and registers the loaded buffers again (`repopulate_history`, `:1814-1833`), and a whole-editor load from idle clears it first (`teardown`, `:1796-1812`; S1) **[code]**. A load with a file registers every path the file holds before anything else, and the file holds every path the registry knew at the save, or, for a tab session's file, every path its own references need, so a reference whose buffer didn't come back still has its path (`storage/routines.lua:215-217`, S1) **[code]**. Decided: "a path is never forgotten while anything references its hash" (DESK:84). Built in step 2. |
| I3 | Every triquetra has its window's history entry (`crux_internals.window[winid]`). | **Enforced** wherever a triquetra is made: `history.routines.ensure_window_entry` (`history/routines.lua:847`) runs from `register_triquetra` (`window/data.lua:42`, the getter's), the load's `set_buffer_relationship` (`window/init.lua:51`) and the fresh start's `repopulate_window_relationships` (`window/routines.lua:1217`), and the load's `initialise_crux_internals`, which resets the per-window entries and puts back each matched window's own, gives every triquetra one afterwards (`history/routines.lua:873-876`). A tab session's load puts each matched window's own in place and gives every other triquetra of its tab one (`storage/routines.lua:1260-1267`). So a `:vsplit` window has one at once (T18, T130) and the save goes through (T141). **[run s16]** recorded the split with none, and the save throwing on `next(nil)`. Decided: they're created together (DESK:84). Built in step 2. |
| I4 | A slot or primary entry holding a closed hash keeps it until it's used, and using it reopens the buffer. | **Enforced**: each check reads its own slot or entry (`window/routines.lua:692`, `:718`, `:746`; T42, T56, T103, T104). A closed slot whose file is gone from disk is kept too, and using it says the file isn't on disk instead of reopening it (A6–A8, P9; T44, T57, T227). **[run s05, s06]** recorded the wrong-slot check (D13). A file whose buffer went without events goes on the closed stack at the stale pass, so its slots keep it too (A22, T242), and so does a file a session load finds in a slot with no buffer brought back (S1, T337). README:15 intends it. |
| I5 | The registry is a bijection: `buffers[h] = b` exactly when `hashes[b] = h`, and likewise for paths. | **Enforced** by the writers (M2) **[code]**. A buffer renamed with no events is tracked under a new hash that isn't registered (`history/routines.lua:1041`) **[inferred]**. |
| I6 | A registered buffer number is a valid buffer. | **Eventually enforced** by the stale pass of `cleanup_system` (A22), which re-points a registration to the same file's live buffer and wipes nothing. Unlisted buffers and `noautocmd` wipes fire no `BufDelete`, so the registry is stale for up to one tick, or one UI refresh when a slot holds the buffer (M12, T242). Decided: re-point to the live buffer, never wipe (DESK:1863). Built in step 1. |
| I7 | A hash on the closed stack has no open buffer. | **Eventually enforced**, on every pool: a file open again leaves every pool, as Q15's answer of 2026-10-23 says (`open_out_of_pools`, `history/routines.lua:464-488`; M5, T350). `track_buffer` takes it off on a visit (`:976`), and so do a reopen and the swaps; the cleanup pass takes off an entry that's open again, on each pool (A22). |
| I8 | A window's current slot is the hash of the buffer the window shows, except: **(a)** while cycling, when it stays the cycle's start, which is intended (Q1); **(b)** while visiting, when it stays the file the window was last on (A2). | **Enforced** once every arrival settles, and re-pointed by cleanup. A cycle left open across a window jump is cancelled, so the other window's visits are recorded (A12, T282). **Violated** when `displacement_mangement` aborts on duplicates (A1, "Duplicates detected in current triquetra"). |
| I9 | Every triquetra belongs to a valid, non-floating window. | **Enforced** by `WinClosed`, the getter's float check, and cleanup. `:file` onto a name not on disk keeps its window and triquetra (T284, on the route of DESK:2444). |
| I10 | Only tracked buffers are registered (M3). | **Enforced at registration and on `OptionSet`.** Arrivals are judged once the editor settles, so a buffer entered before it becomes a terminal or a quickfix list (`:terminal`, `:copen`, DESK:2453) is never registered (T217, T250). A registered buffer whose `buftype` changes so that it's no longer trackable has its arrival undone once the editor settles (`undo_arrival`, `window/routines.lua:158-203`; `window/hooks.lua:179-196`). A window it just arrived in, whose triquetra hasn't changed since, gets back the triquetra from before the arrival (M6). Any other window whose current slot it is takes the next slot in line, ternary → secondary → `primary[1]`, or loses its triquetra. Then the buffer leaves every secondary, ternary and primary queue (`forget_hash_in_slots`), and it's untracked and unregistered, its path kept while anything references it (M2, T217). The trail gets the undo (A27, T405). Decided: the listed-only rule, and undo on `OptionSet` (DESK:1789, DESK:2162). Built in step 2: the listed-only rule (M3). Built in step 3: the undo on `OptionSet`, and arrivals judged once the editor settles. |
| I11 | `ordered.crux` is newest first and holds only open, registered buffers. | **Enforced** at each rebuild (`history/routines.lua:1060-1078`). It's frozen on purpose while cycling. |
| I12 | Cavediver never wipes or discards a buffer with unsaved changes. | **Enforced** (T109, T131): cleanup wipes nothing (A21, A22), a file not on disk stays tracked (M3), and `:file` and `:saveas` keep their edits (A20, T106). A modified No Name buffer closed with `<M-.>` keeps its text on the closed stack (A15). `<M-.>` on an untracked buffer refuses a modified one whose `buftype` is `acwrite` or `""`, oil's with pending edits for one, as it refuses a modified file (A15, Q17). The wipes recorded by **[run s08, s09]**, DESK:2442 and DESK:2448 are D14's, A20's and A22's routes. Decided: cleanup never touches a buffer, and missing files stay tracked (DESK:1859, DESK:1925). Built in step 1: no wipe, and missing files stay tracked. |
| I13 | Cavediver changes only the window an action is about. | **Holds** on every route found. A reopened No Name buffer's cursor goes back in the window that shows it (M5, T90); DESK:2473 recorded it set on the current window, before step 4. Healing switches no window (A21; T247, on the route of DESK:2447), and a deleted buffer's window lands in that window (A19; T111, T132). The window-jump cancel switches the cycling window, the one the cycle is about, back to its start (A12). Decided: the pick after a delete lands in the window that showed the buffer (DESK:1931). Built in step 1. |
| I14 | Every saved file can be written whatever state cavediver's data is in. | **Enforced** for the three routes DESK:1058-1064 found: a No Name current slot is saved as its own hash, like any slot, with its text in `noname_content` when it isn't empty (S1, T140); a hash the path registry doesn't know is dropped, so a slot holding one is saved as `null` and the primary queue, the closed stack and No Name texts skip it (S1; `storage/routines.lua:144-158`; T285); and every triquetra has its history entry (I3), with the save reading a missing one as empty (`storage/routines.lua:539`; T141). Decided (DESK:1058). Built in step 2, and the No Name current slot's route in step 4, with save-as-closed (S2). |
| I15 | Hashes are a pure function of the name: the first 16 hex characters of sha256(name .. "\n"). | **Enforced** (T8, T9): hashing is `vim.fn.sha256(name .. "\n")` with no shell (`history/routines.lua:36-44`), so names with `"`, `$` or a backslash hash like any other. The collisions at DESK:2441 are the shell's. Decided: `vim.fn.sha256` (DESK:2131). Built in step 2. |
| I16 | A No Name id is never reused, across sessions too. | **Enforced** (T11, T216): a No Name buffer is named by an id made from `os.time()` and `vim.uv.hrtime()` and kept on the buffer (`vim.b.cavediver_noname`, `history/routines.lua:22-27`; M1), not by its number, so a later session's buffer with the same number gets another. A reopened No Name buffer gets a fresh id, a closed one and one reopened at a load alike (M5, T316). Decided (DESK:2289), against bufnr reuse (DESK:2285-2287). Built in step 4. |
| I17 | Displacement-map and history entries point only at things still known through open buffers, slots, primary queues or the closed stack (follow along). | **Eventually enforced** by follow along: every `cleanup_system` pass (every tick, save and load) and the close of an empty No Name buffer drop the notes, `-swap` keys included, whose key or value isn't known through those four, and the history entries, in the view, the global history, every window's and every pool's visits, whose hash isn't, then forget those hashes' paths (`follow_along`, `history/routines.lua:766-821`; `is_filehash_known`, `:194-223`; T208). A closed file keeps its history while it's on the closed stack (T252). Between passes a note can name a hash that's no longer known; a restore clears a note at a hash with no path when it uses it (A11). Decided (DESK:2029). Built in step 6. |
| I18 | The primary queue has no duplicate entries. | **Enforced** by `set_primary` (`window/routines.lua:1088-1091`) and by the popup's save, which refuses a repeated file loudly (`window/routines.lua:233`, A18, T218). |
| I19 | An empty primary queue may be switched on or off; nothing forces it off. `<M-;><M-x>` on an empty queue always queues the current buffer and switches on (A9). | **Holds**: pruning leaves `p=[]on` **[run s06, s19]**, `jump_to_primary` falls back to `<M-f>` either way, and the first press on `p=[]on` gives `p=[A]on` (A9, T157). **[run s19]** recorded `p=[A]off` before the fix. Decided (2026-10-20) (Q14); built in step 3. |
| I20 | Storage: `load_session` and `save_session` work from `bare` or `idle`, a load from `idle` going through `bare` first, and storage is `idle` after either. | **Enforced** for a whole-editor file (T137, T138, T295). A tab session's file loads from `idle` straight to `loading`, with nothing torn down, since its load works on the current tab alone, and so does a load with the hint and no usable file (S1 State machine, S2 Tab sessions; T318, T354). A save whose hook fails leaves storage where it was (I21). **[run s10]** recorded a load after a save throwing `Transition 'idle->loading' is not registered` from `to()`, before the teardown. Decided: `idle → bare → loading` (DESK:1284). Built in step 4. |
| I21 | A transition always completes: the state changes even when a hook fails. | **Enforced** for every hook but the critical save hook (`engine/helpers.lua:37-55`). That one re-throws to `save_session`'s caller, abandoning the transition, so storage stays where it was: `idle` after a load or a save, `bare` before either (`storage/hooks.lua:17`; T143, T286). Decided exception: the critical save hook re-throws and leaves storage at `idle` (DESK:1157). Built in step 2: storage stays where it was, which is `bare` when nothing was loaded or saved before (T286). |
| I22 | A file appears at most once in a closed pool. Closing a file that's already there moves it to the newest position; a merge of pools keeps only the newer entry. | **Enforced** on every pool: every push takes any copy off that pool first, so a file closed again moves to the newest position there (`push_closed`, `history/routines.lua:385-394`; T162, T349, T350), the stale pass pushes only a hash that's on no pool, `close_if_not_restored` only one the pool the load fills doesn't hold, and a load into a pool already open adds only the file's entries the pool doesn't hold (`storage/routines.lua:827-829`; A22, S1). A whole-editor save's merge of the pools in its file keeps one copy of a file, the newer (`serialise_closed_buffers`, `storage/routines.lua:574-610`; T321). **[run s20]** found no route that broke it before step 6. The picker's merge keeps the newer copy too (T371), and a `:w` there with no edits changes no list (T372). decided (2026-10-20) (Q15). Built in step 6: one copy on the single stack, newest wins. Built in step 7: one copy per pool, and the save's merge in the file. |
| I23 | No buffer is current while its note names the buffer already in the slot that note restores into. For the current buffer X and each map, the note a restore would read is X's swap note when it's set and isn't the slot's occupant, otherwise X's plain note; that note never names the occupant of the ternary (dtm) or the secondary (dsm). A plain note behind a valid swap note may name it: the restore never reads it. | **Enforced** where the check runs, on every arrival and wherever a slot changes under the current buffer (A1, M7): T190's walks find no break, in one window and several, under both views. Every restore throw is this state (A11); **[run]** recorded 161 secondary and 14 ternary throws in 1,500 walks without the check. The landing after a delete runs the check too (A19), though no walk deletes files. Decided (2026-10-20 evening), "Keep the older one" (A1, M7, Q13), with the check also at the secondary restore's exchange (decided 2026-10-21): 0 breaks over 900,000 walk steps with every fix in **[sim, variant `all_fixed`]** (T189, T206). Built in step 3. Checked by T190, and by the flight recorder at every step's close, which dumps a break (A26, T203). |

## 5. Sessions

### S1. Today

**API.**
- `save_session(name?, opts?)` and `load_session(name?, opts?)` (`storage/init.lua:28-46`, `:107-112`). Neither takes a directory, and either can be called with no argument: `name` is the session's name, and nil makes a nameless session. `opts.tab`, a tabpage, marks a tab session: for the save, the tab it saves; for the load, the hint that it's a tab session, for when its file can't say so (State machine, below).
- Cavediver reads the session's directory itself. The save reads the global directory, `vim.fn.getcwd(-1, -1)`, for the whole editor, or the tab's, `vim.fn.getcwd(-1, <tab number>)`, when `opts.tab` gives a tabpage (`storage/init.lua:33-36`; T292, T293, T294). The load reads the tab's directory too when `opts.tab` gives one (`:60-61`). The load works on that tab, wherever the focus is: a tab session's file loads into it, and with no file it's the tab that starts fresh (Load, below; T367). Without the hint, the load reads the global directory, unless the tab you're in has a directory of its own (`haslocaldir(-1, 0)`) holding a file under the session's name: then it reads that one (`:62-64`). So a tab session saved from a tab with a `:tcd` of its own is found at load in a tab with the same `:tcd`, as the manager restores a tab's directory (T352), and one saved from a tab with no `:tcd` of its own is found in the global directory **[code]**.
- Both hand the storage machine `{ name = name, directory = directory }` as the transition's context, the save with `tab = opts.tab` added (`:37-44`), and its hooks pass them on to `save_history` and `load_history` (M11). The load's hint goes to `load_history` with the read the load made first (`prepare_load`, State machine, below).
- The README wires them to resession's `pre_save` and `post_load` with the session's name, the save passing the tab resession names and the load the current tab when resession kept the other tabs, a tab session's load; and it saves every open session through resession's `save_all` in `pre_load`, and a tab session through `save_tab` on `TabClosedPre` unless resession is loading (README:101-121; S2 Contract and API).

**State machine.**
- Save is `→ saving → idle`, from `bare` or `idle`.
- Load is `→ loading → idle` from `bare`, and `idle → bare → loading → idle` from `idle` (`load`, `storage/init.lua:58-97`; T137, T138, T295). **[run s10]** recorded a load after a save in the same process throwing `Transition 'idle->loading' is not registered` from `to()`, which escaped resession's hook and broke session switching (DESK:1254-1260), before the teardown.
- **A tab session's route.** The file is read before the machine moves (`prepare_load`, `storage/routines.lua:967-974`), since its scope decides the route: a tab session's file goes `idle → loading → idle`, with no teardown, so a load from `idle` works on one tab as a load from `bare` does (`storage/init.lua:79-96`; T318). A usable file's scope wins over the hint: a whole-editor file loaded with `opts.tab` takes the whole editor's route (T355). A file that's missing, can't be read, or lacks `paths`, `buffers` or `windows` gives no scope, and then the hint decides: with it, the load takes the tab route, and only the hint's tab starts fresh (Load step 3, T354); without it, the load takes the whole editor's route and starts the whole editor fresh **[code]**.
- **A write still pending is dropped** when the load takes the whole editor's route, before the machine moves: by the time the manager calls `load_session`, its restore has torn the outgoing session down, events on, so the closes waiting to be written are the teardown's (`drop_pending_records`, `storage/init.lua:82-87`; Records, below; T360). The tab route keeps them **[code]**.
- **The teardown.** At `idle → bare` every domain tears its own state down, in a hook of its own on the storage machine, so the load starts from nothing, as at startup:
  1. navigation: its state set to `normal` directly, `cycling_window` cleared, the window-jump table emptied (`navigation/hooks.lua:16-20`)
  2. window: the winbars cleared, every triquetra dropped, `landing` and `arrivals` emptied, and `current_window` and `last_valid_window` set to the current window (`window/hooks.lua:16-27`)
  3. history: `teardown()` empties the view, both histories, the ordered lists, both registries, the closed stack, the No Name texts, the cycling origins, every tab session's pool, `tab_pools` and `came_from` (`reset_pools`, M5), the tags of files gone from disk and the marks of files never written, sets `history_index` to 1, and forgets the label recorded, so the next one seen only starts the record, unless the file gives one (Load, below; M14); then the history state is set to `attached` directly (`history/hooks.lua:68-71`, `history/routines.lua:1796-1812`)
  4. ui: the window display caches, the display-name cache and the bufferline state cleared in place (`ui/hooks.lua:17-27`)

  No transition sets the two states, so no hook runs for them, and a cycle left open ends with nothing picked (M9). The outgoing No Name texts go with the teardown, so a session switch doesn't carry them into the incoming file (T148). What the load restores is the same as at startup (below), and a buffer the file doesn't know waits for its `BufEnter` (T296, T314).
- **The repeat flag.** A load sets `storage.data.loading_batch` and schedules its clearing with `vim.schedule`. `load_session` skips a call while it's set: a native restore calls it once per loaded buffer, and only the first loads. A call after the batch is a full load (`storage/init.lua:68-78`, `:108-110`; T145, T297).
- **Once the restore settles,** the same `vim.schedule` runs `after_restore`: when the focused window has a triquetra, it becomes `last_valid_window` and `current_window`, and its history view and both ordered lists are built (`storage/routines.lua:1429-1438`; T299). No timer runs.
- **After `:restart`.** Neovim's `:restart` restores its own session after the startup's and rebuilds the windows. The storage domain's `SourcePost` autocmd, made by `setup()`, sees a `restart_session_*` file while `v:startreason` is `restart`, and runs the last load of this startup again, under the same name, once the editor settles, ignoring the repeat flag (`storage/init.lua:121-138`; T298). The name is kept in `storage.data.last_loaded` as `{ name = …, tab = … }`, with no name for a nameless load, so a nameless load is run again too, and `tab` true when the load had the hint (`storage/data.lua:61`, `storage/init.lua:69`). Only that last load runs again: when it was a tab session's, the rerun loads it into the tab that's current then, with the hint, naming that tab, when the load had it (`:134-136`), and the whole editor's session isn't loaded again **[code]**. The rerun is a step of its own in the ledger, and its load adds none (A27, T415).
- **The load counter.** Each load bumps `history.data.loads` (`storage/routines.lua:1294`). A `BufEnter` arrival queued before it, and the close key's deferred delete, drop themselves when they settle: the restore's own events are noise the load replaces (`history/hooks.lua:238-240`, `history/routines.lua:1534-1538`; A1, A15).
- The load hook runs inside `xpcall`, so a failure inside a load is only a notification, with its stack trace, and storage still goes to `idle`. The save hook is critical: a failure inside a save throws to `save_session`'s caller, and storage stays where it was, `idle` after a load or a save and `bare` before either (M11, I21; T286). So with a read-only session directory, the save throws (T143); DESK:2452 is the record of that failure as a notification only, resession's file written and cavediver's not.

**File.**
- Path: `session_dir/<sha256(directory .. "\n" .. name)>`, or `session_dir/<sha256(directory)>` for a nameless save, all 64 hex characters and nothing after them, with the directory read as above (`get_session_filepath`, `storage/routines.lua:867-882`; M1, T255, T292). `session_dir` itself is made with a plain `mkdir`, as the umask allows (`:879`). A file under an older name, 32 hex characters or ending in `.json`, isn't read (M1).
- **The main file** is the clear header `CDV1`, a 16-byte salt, and the session's data as JSON, sealed with AES-256-GCM: a fresh random 12-byte nonce, the ciphertext and a 16-byte tag (`seal`, `storage/crypto.lua:108-130`; `storage/routines.lua:1484`; T301). The header and the salt are the sealed data's additional data, so the tag covers them too. Nothing else is in clear: the paths, the file names and the No Name texts are all inside (T302). The JSON is `vim.json`'s, which takes any bytes, so a path or a text that isn't UTF-8 is saved like any other.
- **Its scope.** The data says whose session it is: `scope` is `"editor"` for a whole-editor save and `"tab"` for a tab session's, whose file holds that tab's windows and its pool alone (Save, below; T318). A load goes by it (Load, below). A file with no `scope`, saved before step 7 or written by the migration script, loads as a whole editor's **[code]**.
- **The key** is stretched from the session's directory and the file's salt with PBKDF2-HMAC-SHA256, 200,000 rounds, 32 bytes (`derive_key`, `storage/crypto.lua:90-97`), so a file only decrypts in its own directory (T310). The salt is kept from one save to the next (Save step 2). Each key is stretched once: it's kept in memory by its directory and salt the first time a load, a save or a records write needs it, and every later read or write with that directory and salt takes it from there (`key_for`, `storage/routines.lua:884-902`; T363). Kept by the salt, a file another editor's save gave a new salt gets a key of its own, never the old one. A key goes once no open session uses it: after a load, after a save and when a tab session's pool goes, the last key of each known session's file is kept, and the rest go (`forget_closed_keys`, `:2045-2063`) **[code]**.
- **One file per No Name text**, in `<main>.d/`, the main file's path with `.d` added, made in mode 0700 when a text is written there (`storage/routines.lua:706`; T305). Each holds its text's JSON, `{ lines, filetype, cursor }`, its keys always in that order, so a text is the same JSON in every editor, sealed with the session's key, with `CDV1` and the text's hash as the additional data and no clear header (`:701-707`). It's named `sha256(<the key in hex> .. "\n" .. <the hash> .. "\n" .. <the JSON>)`, so the name changes with the text, an unchanged text keeps its file and its bytes, in any editor, and the name gives nothing of the text away (`scratch_name`, `:112-114`; T306, T472). The main file's `noname_content` names each text's file.
- **The trail's pages** (A27): one file per day with moves, in `<main>.d/` beside the texts' files, named through the key after its date and ending in `.trail`, sealed with the session's key, with `CDV1` and the date as the additional data; the main file's `trail` names them by date (`page_name`, `read_page`, `storage/routines.lua:1585-1613`).
- **Every write is atomic** (`write_atomic`, `:81-100`; T304). The bytes go to a temporary file beside the target, `<path>.tmp<n>`, opened with mode 0600; they're synced with `fsync`, the mode is set to 0600 again, and the temporary file is renamed over the target. A crash leaves the old file or the new one, never half of one. When a step fails, the temporary file is removed and the save throws "Failed to write session data to file: <path> (<error>)". So every file is `rw-------` whatever the umask (T212, T305).
- **The encryption is OpenSSL 3's `libcrypto`**, called through LuaJIT's FFI, so no command runs (T303). It's loaded the first time it's needed, as `crypto`, `libcrypto.so.3` or `libcrypto.3.dylib` (`storage/crypto.lua:53-67`), and each FFI declaration is made on its own, so one another plugin made already doesn't stop the rest (`:22-43`). A missing library throws "cavediver: OpenSSL 3's libcrypto was not found; it encrypts the session files.", an environment failure. Every save needs it, so the save throws (I21); a load needs it only for a file that starts with `CDV1`, and there it's a failure inside the load (above). The tag is copied into its buffer by its length (`storage/crypto.lua:152-154`). **[run 2026-10-24]** recorded the copy made from a Lua string initializer before it, which wrote the string's terminating zero one byte past the 16-byte buffer at every decrypt, from step 5 on: at every load, and from the records written on time on, at every records write, so at every close. The suites didn't crash on it; T334's walks did, a segfault every time, once every whole-editor save decrypted too, for the detached lists. T334 is the guard.

**Save** (`save_history`, `storage/routines.lua:2249-2368`). The steps are a whole-editor save's; a tab session's differs where it says, and in what follows step 5:
1. `cleanup_system` runs (A22). It wipes nothing, and a closed file gone from disk stays on the closed stack (T214); what its passes mend, a tick would mend too (P24). It checks every known file against the disk, where a tick checks a slice, so the tags it saves are up to date (M14).
2. **The key and its salt** (`session_key`, `:1450-1460`). The salt is read from the main file already there, so the key stays the same from one save to the next, and a text that didn't change keeps its file. With no main file, or one that doesn't start with `CDV1` followed by a whole salt, the salt is a new random one. A main file whose header is `CDV` and a digit other than `CDV1`, made by a newer cavediver, isn't overwritten: the save throws "cavediver: this session's file was made by a newer cavediver, so it isn't overwritten: <path>" (`:1452-1454`). The save hook is critical, so while that file is there every save of the session throws, the session manager's included (I21).
3. The keys written (T134), gathered in this order: `windows`, which collects the outsiders as it goes; the No Name texts, whose files are written then (step 4); `closed` and `closed_times`; then `scope`, `paths`, `outsiders`, `buffers`, `missing`, `label` and `unwritten`. Hashes are saved raw. A slot, a queue entry, a closed entry or a No Name text whose hash the path registry doesn't know is left out (`known`, `:144-158`; I14); the maps and the global history are written as they are.
   - **`scope`**: `"editor"`, or `"tab"` for a tab session (`:2319`; File, above).
   - **`detached`**, in a whole-editor file: the detached lists, apart from `closed`, each `{ label, of, closed, closed_times, windows }`: every detached pool in memory, its `windows` the indices of its tab's entries in `windows`; and every list the file held alone, carried over with no windows, its texts' files and its entries' paths kept (`detached_lists`, `carry_detached`, `:1085-1156`, written at `:2300-2315`; T380, T381). A file-only list never finds a tab again: the windows it had pointed into an older `windows`. The key is there only when there are some.
   - **`paths`**: hash → path for every path the path registry knows, open and closed buffers and `NONAME_` names alike, plus the outsiders (`serialise_paths`, `:555-561`). The paths are in clear inside the JSON, since the whole file is encrypted.
   - **`outsiders`**: the hashes in `paths` that are outsiders, untracked buffers that windows with a triquetra show, such as an oil listing or a help file, each hashed by its name (`shown_by`, `:168-179`). They're recorded so the load can match those windows, and kept out of the registry (`:2322`).
   - **`buffers`**: `{ global = crux_internals.global }`, the global access history (`:414-418`); for a tab session, `{ global = <its pool's visits> }` (`:2323`; M4). Each window's own history goes in its window entry.
   - **`windows`**: one entry per window that has a triquetra, visiting windows included, in `nvim_list_wins()` order, tab order then window order; for a tab session, that tab's windows alone, in its own order (`serialise_window_relationships`, `:432-546`, the tab at `:455`). Each entry is `[current, secondary, primary_queue[], ternary, dtm, dsm, shows, primary_enabled, history]` (`:530-540`), with `null` for an empty slot, so it has no holes:
     - The slots and the queue hold the live triquetra's raw hashes, as they are: a current slot holding an open No Name buffer is saved as its own hash, like any slot, and its text goes into a file of its own (below; T213). A slot whose hash the path registry doesn't know is saved as `null` with no error (T285), and the queue skips such a hash (`:502-506`).
     - Both maps are written raw, `-swap` keys included.
     - `[7]`, **shows**, is what the window shows: its buffer's hash when the buffer is registered, otherwise the hash of its buffer's name, an outsider; `null` for an untracked buffer with no name (`:524-528`). The save leaves every window on what it shows, so `[7]` is what the session manager saves too: an oil window is saved as showing its oil buffer, an outsider (T146).
     - `[8]` is `primary_enabled` (T136), and `[9]` is the window's own access history, read as empty when it has none (`:539`); every triquetra has one anyway (I3). **[run s16]** recorded a `:vsplit` window with no history entry making the save throw `next(nil)`, before I3.
   - **`closed`**: the closed hashes, newest last (`serialise_closed_buffers`, `:574-610`). A whole-editor save merges every pool, the editor's first, by close time: each pool keeps its own order, the pool whose next entry was closed earliest goes next, the editor's pool first on a tie, and an entry with no close time, as `close_if_not_restored` leaves one, counts as the oldest. A file on several pools keeps one copy, its newest close's (I22, T321). A tab session's save writes its own pool's stack. The pools in memory stay as they are (P24).
   - **`closed_times`**: hash → when each `closed` entry was closed, in seconds to the microsecond, where it has one (`:607`, `:2326`).
   - **`noname_content`**: each No Name text's file, keyed by the buffer's hash: `{ scratch = <the file's name>, reopen = true }` for an open text, and no `reopen` for a closed one (`:710-713`). The texts are gathered by `serialise_noname_content` (`:624-670`): each closed one the path registry knows (M5), and every registered, loaded No Name buffer that isn't empty, with its lines, its filetype, the cursor of a window showing it, in any tab, or `{1, 0}` when none does, marked `reopen` (`:653-668`; T474). An open one's hash isn't put in `closed`, and an empty one is skipped, as closing skips it. For a tab session, only its pool's texts: the closed ones its stack holds, and the open ones a window of its tabs shows or has in its history (`owned`, `:625-645`, `:649`; T332). The editor's pool's are the closed ones on its stack and the open ones no tab session's tab visited.
   - **`missing`**: the tags of files gone from disk, hash → tag, as they are (`:2328`; M14).
   - **`label`**: the label recorded at the save, which is the label being left at the next load. The key is there only when there's a label (`:2329`; M14, T347).
   - **`unwritten`**: the hashes of files never written, which aren't tagged when they aren't on disk. The key is there only when there are some (`:2330`; M14, T348).
   - **`trail`**: the trail's pages, date → file name, when there are some: the days the ledger holds steps of this session written now, earlier days kept from the old main file (`write_trail_pages`, written at `storage/routines.lua:2339`, guarded so a page that can't be written doesn't stop the save; A27).
4. **The texts' files** are written before the main file (`write_noname_texts`, `:684-716`). Each text's JSON gives its file's name (File, above), and the file is written only when no file of that name exists, so an unchanged text keeps its file and its bytes (`:701-708`; T306). A closed text a load left unread keeps its file without being read, unless it came from another session's file or under another key, when it's read and written again here and kept read from then on, so it no longer needs the file it came from (T473), or its file is gone, swept by another editor's save, when nothing is left to keep (`:690-699`).
5. **The commit** (`commit_session`, `:1475-1500`). A closed No Name buffer whose text couldn't be kept leaves `closed` too, so no load meets a closed No Name entry without its text, and the same goes for each detached list (`:1476-1483`). The main file is written last, `CDV1`, the salt and the sealed JSON (`:1484`), and it's the commit point: until it lands, the main file on disk is the old one and every text file it names is still there, so a crash before it leaves the old session whole (T307). Then the sweep: every file in `<main>.d/` that the new main file doesn't name is removed, and so is every `<main>.tmp*` file in the session directory (`:1486-1499`), so what a crash after the commit leaves is swept by the next save (T307).

`write_session(directory, name, storage, texts)` (`:2457-2463`) runs steps 2, 4 and 5 for data in the saved shape: `storage` holds `paths`, `outsiders`, `buffers`, `windows` and `closed`, as a save writes them, and `texts` the No Name texts, with `reopen` marking the open ones. The migration script writes the files it converts with it (S2 The file, T338), with no `missing`, no `label`, no `scope` and no `closed_times`: a load of such a file puts back no tags and no label, loads it as a whole editor's, and gives its closed entries no close time (Load, below).

After its commit, a whole-editor save records its session as the editor's session, `storage.data.editor_session`: the last whole-editor load or save, which the unnamed session is taken from (below). It ends the unnamed session, so the whole editor's records cover every tab again until a tab session is saved or loaded after it, and clears the whole editor's mark of records waiting to be written (`storage/routines.lua:2363-2365`, `storage/data.lua:70`; Records, below). The save is a step of its own in the ledger, holding its "saved" move, and a tab-session save's refresh of the whole editor's records a "refreshed" one (A27, T414).

**A tab session's save** (`tab` given):
- Before anything is gathered, the tab joins its session's pool, made when there's none yet (`join_pool`, M5), and any other tab in that pool is pushed out into a detached list (`storage/routines.lua:2275`, M5; T378). When the tab wasn't in that pool and the pool has no visits yet, as at its first save, the pool's visits start from the tab's windows' histories, each file at its newest time (`storage/routines.lua:2260-2271`). When no tab session has started yet, the unnamed session is taken: the editor's session becomes `storage.data.unnamed` (`:2272-2274`, `storage/data.lua:74`). When the tab wasn't in the session's pool, the save carries the closed files the tab's slots hold, its windows' current, secondary and ternary slots and primary queues, from the list it leaves onto the session's pool, under its own entries, with their close times; the list it leaves keeps its copy. When that list is a tab session's and no other tab is in it, the session it leaves is closed as at a tab close (Records, below): its records go into its file, and its pool goes (`storage/routines.lua:2276-2293`, `carry_closed` at `history/routines.lua:519-526`; T366, T368). The author, 2026-10-23: "Carry slot entries", "when you do save_as, you are saving whatever you have right now in another name", and "Carry a copy" for a tab in no session and for a session still open in another tab.
- The keys hold that tab and its pool alone (step 3), and `narrow` cuts `paths`, `outsiders`, `missing` and `unwritten` down to the hashes the file references: its windows' slots, queues, both maps, histories and what they show, its closed entries, its visits and its texts, a `-swap` key counting as its buffer (`narrow`, `storage/routines.lua:1524-1573`). `label` is written as it is.
- Once the main file is committed, the pool is marked saved (`saved_at`), the tab session's mark of records waiting to be written is cleared, and the unnamed session's records are refreshed in its file (`:2358-2361`).

**The unnamed session's refresh** (`refresh_unnamed`, `:1828-1849`; T323). It writes the unnamed session's records into its file, as cavediver writes any session's (`write_records`, Records, below): its `closed` and `closed_times` from the editor's pool, and its `noname_content` from the editor's pool's texts. Everything else stays as the session manager last saved it.
- It never makes the file: with no file there, it does nothing.
- A file it can't read, one with a newer header, one in the old format, one that fails its check or a tab session's, isn't touched; a failure while writing it doesn't throw, whatever failed: the texts' files or the main file. Either way a WARN says "cavediver: the whole editor's session file wasn't refreshed with its closed files and No Name texts, since <problem>", where `<problem>` is "it couldn't be read (<why>): <path>" or "it couldn't be written: <error>", and the tab session's save, whose own file is written by then, goes through (`:1846-1848`). It's said at every such save **[code]**.

**Records** (`storage/routines.lua:1742-2234`). Besides the session manager's saves, cavediver writes each session's records into its file itself, whenever they'd otherwise be lost: its closed list, its close times and its No Name texts. Its references, the windows, the history, the outsiders, the tags, the label and the marks, stay as the session manager last saved them (S2 Errors and drift).
- **A write** (`write_records`, `:1755-1818`) reads the session's main file, under that session's own directory and key. It replaces the file's `closed` and `closed_times` with the session's pools merged by close time, as a whole-editor save merges them (Save step 3), and its `noname_content` with the session's texts, written into its `.d/` as a save writes them (Save step 4), and adds to its `paths` the paths those need. Today's trail page rides along, written before the commit (`storage/routines.lua:1809`; A27). Then it commits the file as a save does, the sweep included (Save step 5). It runs no `cleanup_system`, and leaves the running state as it is **[code]**.
  - It never makes a file: with no file there, it writes nothing (`:1757-1760`; T361). It reads the file once, so the salt and the key come from the same bytes (`:1762`), and checks the file is still there just before it commits, so a file removed meanwhile isn't made again (`:1804-1808`) **[code]**.
  - It takes the session's kept key, by directory and salt, so a write on every change doesn't stretch the key again (`key_for`, `:884-902`; File, above; T363).
  - A file it can't read, one with a newer header, one in the old format, one that fails its check, or one whose scope isn't the session's, isn't touched (`:1762-1765`). A failure while writing is caught, and the write counts as not done (`:1767-1816`) **[code]**.
- **What each session covers** (`known_sessions`, `:2014-2023`):
  - The whole editor's session, `editor_session`, covers every tab, so every pool, the editor's first, and every No Name text, open or closed, until a tab session is saved or loaded after the whole editor's last save or load: at a tab's save as one, at a tab session's load, or at a load with the hint and no file. From then on, the whole editor's session is the unnamed one, `unnamed`, which covers the tabs in no tab session: the editor's pool and its texts (M5). A whole-editor save or load ends the unnamed session (Save, above; Load step 2; T321, T323).
  - The detached lists ride with the whole editor's session, whichever it is, written apart in its file (`whole_editor_session`, `:1866-1874`; M5). The closed lists' edits to a list in the file alone go in the same write, as changes to that list (`write_records`' `changes`, `:1755-1818`).
  - Each tab session, kept with no tab or not, covers its own pool and its texts.
  - A session that has no file, as before its first save, gets no records.
- **When.**
  - **On every change.** A change to a pool's records (M5) marks its session changed, and so does an edit to a registered No Name buffer, `TextChanged` or `TextChangedI`, which marks every pool's session changed (M11). The first change while the records' timer isn't running is written on the next tick, through `vim.schedule`, and starts that timer, a one-shot of a second; the changes made while it runs are written when it runs out (`records_changed`, `:2160-2184`; T296, T359). Each write takes every session marked changed (`M.write_records`, `:2136-2150`).
  - **At quit.** `VimLeavePre` writes every known session's records at once, changed or not (`storage/init.lua:162-167`; T358). A process that's killed fires no `VimLeavePre`: what it changed after its last write is lost, a second's worth at most **[inferred]** (T359).
  - **As a tab session's last tab closes**, or leaves it for another session (M5), its records are written on the next tick, and then its pool is dropped (`close_tab_pool` and `close_now`, `storage/routines.lua:2226-2234`, `:2090-2126`; M5, T322, T366). The write waits for the tick because a manager's switch closes tabs inside its teardown, events on, and ends with the load: a whole-editor load in the same batch drops it (below; T365). A quit in the same batch, before the tick, writes it (`:2140-2144`; T358). A pool a tab came back to by then, or that a load tore down, is left alone. When they can't be written, because the session has no file yet or its file can't be read or written, the pool is kept with no tab, with a WARN (M5, T356). The trail gets the close, its records written or kept (A27, T416).
  - **At a tab-session save**, the unnamed session's (the refresh, above).
- **The guards.** On a change and at quit, nothing is written unless the writing is on, which `setup()` turns on and `disable()` off (`write_records_on`, `:2210-2216`; A25, T364), and storage is `idle` (`:2137`). A session is written only while the editor is still where it would be saved from: the global directory, for the whole editor's; one of its tabs' directories, for a tab session (`still_there`, `:2033-2043`; T362). So a switch whose load isn't wired leaves the old session's file alone, and so does a pool kept with no tab. A tab close's write isn't held by the directory: its session has no tab left to be in; a load in the same batch drops it instead (above) **[code]**.
- **A load on the whole editor's route drops a write still pending:** the marks are cleared, the timer stops, the tab closes waiting for their tick are forgotten, and a write already scheduled finds the generation moved on and does nothing (`drop_pending_records`, `:2193-2200`; State machine, above; T360). A save clears its own session's mark (Save, above).
- **When a write fails,** the session stays marked, so the next change or the quit tries it again. A WARN says "cavediver: <name>'s closed files and No Name texts weren't written, since <problem>", `<name>` being the session's name or its directory's last part, once per session and problem (`write_now`, `:2071-2080`). A file that isn't there says nothing. A tab close's WARN and the refresh's are said every time **[code]**.
- **[run 2026-10-23]** recorded a switch's teardown written into an open tab session's file, before a tab close's write waited for its tick: `:e a`, `:e b`, `save_session('main')`, `:tabnew`, `:e c`, `:e d`, `save_session('t', { tab = … })`, back to the first tab, then resession's order by hand (a scratch buffer in the window, every listed buffer deleted, `tabonly`) left `t`'s file with `c` on its closed list, where it was empty, before any load ran: deleting d closed `t`'s tab, and its records were written right then. resession's own `close_everything` deletes every listed buffer, then runs `tabonly`. T365 runs that route through to the load.
- With two editors on one session, each writes its records over the other's, at every change **[inferred]** (S2 Errors and drift).

**Load** (`load_history`, `storage/routines.lua:1287-1421`):
1. **The main file is read** (`read_session_file`, `:920-941`), by `load` before the storage machine moves (`prepare_load`, `:967-974`; State machine, above). `load_history` takes that read, and the hint with it, when it's for the same directory and name, and reads the file again otherwise, with no hint (`:1296-1304`). The key comes from the session's directory and the file's salt, the key kept for them when there is one (`:933-934`; File, above). Besides a usable file there are four outcomes, each a fresh start: of the tab you're in alone with the hint, of the whole editor without it (step 3).
   - **Missing:** a fresh start. When `session_dir` holds a file named the way files were before sessions had names, the first 32 hex characters of `sha256(directory .. "\n")` plus `.json`, a WARN says to run the migration script, "cavediver: this session has a file from before encryption. Run the migration script, scripts/migrate_sessions.lua, to convert it; the session starts fresh.", and the file is left as it is (`storage/routines.lua:1311-1313`, T340). Otherwise there's no message.
   - **A header `CDV` and a digit other than `CDV1`**, made by a newer cavediver: WARN "cavediver: this session's file was made by a newer cavediver. It's left alone, and the session starts fresh." The file isn't touched, and no save overwrites it (Save step 2; T245).
   - **A file starting with `{`**, after any blank space, the plain JSON of the format from before step 5: WARN "cavediver: this session's file is in the format from before encryption. Run the migration script, scripts/migrate_sessions.lua, to convert it; the session starts fresh." (T312).
   - **Anything else**, a tag that fails, or decrypted JSON that doesn't parse: WARN "cavediver: this session's file failed its integrity check (edited or corrupted). The session starts fresh, and the next save replaces the file." An edited byte, a cut-off file and a file from another directory, whose key differs, all end here (T144, T310, T311). The tag is checked before any decrypted byte is used (`open`, `storage/crypto.lua:141-171`).

   Decrypted data that lacks `paths`, `buffers` or `windows` is a fresh start too, with no message (`storage/routines.lua:1315-1317`). `read_session(directory, name)` returns the data decrypted, as the load reads it (`:949-952`; T134).
2. With data from a whole-editor file, any `scope` but `"tab"`, the editor's pool is the one the load fills, and the session becomes the editor's session, with no unnamed one (`:1358-1359`; Save, above):
   - **`load_paths`** reads `paths`, leaving the outsiders out (`:188-200`).
   - **`load_buffer_history`** registers every path the file knows as a path, so a reference whose buffer isn't restored still resolves to its file (I2). Then it registers every restored buffer whose name hashes to one of those paths and that `is_trackable` holds for, loaded or not: a `badd` buffer counts (M3, T139). A buffer the file doesn't know isn't registered, and waits for its `BufEnter` (T296, T314). A No Name buffer still open from before the load, as in a reload in the same process, is known by its id (`:220-223`, T339). Then it runs `track_buffer(hash, time)` for every saved global entry, including entries that aren't open (`:214-237`, M4).
   - **`load_closed_buffers`** empties the editor's pool and rebuilds its stack from the saved hashes, each with its close time from `closed_times` when the file has one (`:851-853`; M5). An entry whose buffer the session manager brought back is registered by then, so it's left off the stack (`:824-826`); DESK:2471 recorded `bufexists` throwing on such an entry and stopping the load, before it was left off. A `NONAME_` entry's text isn't read: its entry in the No Name cache holds the name and path of its file, the key and a reader, and the text is read only when it's reopened or the closed lists draw it (`:830-846`; M5). It throws on a hash with no path, or on a No Name entry with no file named for it or already in the cache, and a throw stops the rest of the load (`:803-857`).
   - **`load_window_buffer_relationships`** matches saved entries to windows **by what they show** (`:284-394`):
     - The entries are grouped by `[7]`, in saved order. Each window but a float, in `nvim_list_wins()` order, takes the first unused entry whose `[7]` is what it shows: its registered buffer's hash, or else the hash of its buffer's name (`shown_by`, `storage/routines.lua:168-179`). A No Name text an earlier load reopened, with no save since, is matched by the hash it came back from, which the file still knows it by (`:304-310`). So a reload in the same process keeps the slots of a window showing an open No Name text, empty or not (T339). So windows on the same file keep their saved order (T315), and a window on an outsider finds its entry by the outsider's hash. Floats never take an entry.
     - An entry that matches no window is dropped (T142, T244, T251). A window that matches nothing is left to the getter: it keeps the triquetra it has, which only a load from `bare` can leave it, since a load from `idle` tears every triquetra down first; otherwise it gets a fresh `{c=<shown>}` when what it shows is registered, and waits when it isn't (M6, T315).
     - A matched entry's current slot is `[1]`, or the hash of the window's registered buffer when `[1]` is `null` (`:334`); with neither, the window is skipped. `set_buffer_relationship` takes the slots, the queue, both maps and `primary_enabled` from the entry (`window/init.lua:59`; T136), and the window's own history comes from `[9]`. When the window shows an oil buffer (filetype `oil`) and its current slot's buffer is registered, `vim.w.oil_original_buffer` is set to that buffer, so oil's `q` (`oil.close`) goes back to the window's current slot; the oil buffer itself stays unregistered, an outsider (`storage/routines.lua:376-382`; T324). The matched windows' display caches are derived only after the No Name texts are reopened (below, `storage/routines.lua:1398-1402`), so every slot's buffer is back by then.
     - **A reference the manager didn't bring back is closed** (`close_if_not_restored`, `storage/routines.lua:251-269`): a file, not a No Name buffer, in a matched entry's current, secondary or ternary slot or primary queue, with a path and no registered buffer, that the pool the load fills doesn't hold already, goes on that pool's stack under the saved entries, as the oldest, with no close time (M5). The slot keeps it and reopens it when used, and cleanup and the UI treat it as any closed slot (I4, T337). A file deleted on disk is kept the same way: using the slot says the file isn't on disk, and it works again once the file is back (A6, P9, T313).
   - **`initialise_crux_internals`** resets the window histories, puts each matched window's own in place by window id, gives every other triquetra an empty one, and puts the saved global history in place, then rebuilds the view for `last_valid_window` (`history/routines.lua:865-882`). The window the restore leaves focused gets its view once the restore settles (`after_restore`, above).
   - **The detached lists** come back with their tabs: each whose `windows` name an entry a window took joins that window's tab as a detached pool, its closed No Name texts held unread like any closed text's; the rest stay in the file alone (`:1465-1480`; T380).
   - **`reopen_noname_buffers`** brings back every `noname_content` entry marked `reopen` whose hash has a path, in the background (`storage/routines.lua:750-785`, `:1387`; M5, T140, T316). Its text is read from its file then (`scratch_reader`, `:125-136`). A file that's missing or fails its check is skipped with the WARN "cavediver: a No Name text's file failed its integrity check (edited or corrupted), so that text is lost.": that text is lost, and the rest of the session isn't (`:755-758`; T308). Each text read is a new listed buffer holding its lines, with the saved filetype, shown in no window, and modified, since setting its lines marks it (`:760-762`). `vim.b.cavediver_reopened` holds the saved hash (`:763`), and a one-shot `BufWinEnter` puts the saved cursor back in the window that shows the buffer, once one does (`:766-772`). It's registered under a fresh `NONAME_<id>` (M1); every slot, queue entry and note (`rename_hash_in_triquetras`) and every history entry (`rename_hash_in_history`, M4) that named the saved hash follows to the new one, and the saved path is forgotten unless something still references it (`:774-781`, M2). No visit is recorded: the history keeps the saved time, under the new hash.
     - **A No Name buffer that's already back** is taken as it is, and its file isn't read (`noname_already_back`, `:724-737`): an unnamed buffer whose `vim.b.cavediver_reopened` is the entry's hash, reopened by an earlier load, or whose own No Name id hashes to it, open since a save in the same process. It's registered under its own hash, and when that differs from the saved one, the references follow to it as above. So a second load in one process brings no text back twice (T300).
   - **The tags and the label** come back once the No Name texts are reopened, before the display caches are derived: every saved tag is put back, and so is every saved mark of a file never written, and when `label` is a string, it becomes the label recorded, as one already seen (`storage/routines.lua:1388-1397`; M14). So the `cleanup_system` pass of step 4 reads the label again and, when it changed since the save, tags what's gone with the label the session was saved on (T347). Without a `label`, the label recorded before the load stays: after a whole-editor load from idle, whose teardown forgot it, there's none, and the first label seen only starts the record.
   - Then every triquetra gets the check where a slot changes under the current buffer: the notes come from the file, so a loaded slot can leave a note naming it (`storage/routines.lua:1403-1406`, A1, T243).

   **With data from a tab session's file**, `scope` `"tab"`, the load works on one tab, the hint's or the one you're in, and nothing else changes (`load_tab_session`, `storage/routines.lua:1232-1277`; T318):
   - The tab's triquetras are dropped, each through `unregister_triquetra` (`:1233-1237`, M6).
   - When no tab session has started yet, the unnamed session is taken from the editor's session (`:1238-1240`; Save, above), and the tab joins the session's pool, made when there's none yet (`:1243`, M5); the session it was in, when no tab is left in it, is closed as at a tab close (`join_for_load`, `:1169-1183`; M5, Records).
   - `load_buffer_history` registers the file's paths and the restored buffers it knows, as above, and tracks no saved entry, so the global history isn't written (`:1246`).
   - The file's history becomes the pool's visits, re-based to -1 and below, so every visit made from then on ranks above them (`:1247-1257`; M4, T320).
   - `load_closed_buffers` empties the pool's stack and rebuilds it from the file's, with the close times (`:1258`; M5). A closed No Name entry's reader replaces any the cache holds for that hash, where a whole-editor load throws (`:831`) **[code]**.
   - **A session already open**, in another tab, or kept with no tab after its records couldn't be written (M5), moves to the tab it's loaded into, and the tab it was in leaves it for a detached list (`:1244`, M5; T369). It is newer in memory than in its file, so its pool stays as it is: it keeps its visits, and `load_closed_buffers` empties nothing. The file's closed entries the pool doesn't hold go under its own, as the oldest, in the file's order, with their close times; one the pool holds, or whose buffer is open, is skipped; and a closed No Name text the cache holds keeps its cached text (`:1241-1242`, `:1247`; `:804-805`, `:827-829`, `:843`, `:847-853`; T357). So a second tab loading a session open in a tab shares its list.
   - The windows are matched among the tab's own, as above, and a reference the manager didn't bring back is closed into this pool (`:1259`). Each matched window's history is put in place, and every other triquetra of the tab gets an empty one (`:1260-1267`). The global history and every other tab stay as they are.
   - The No Name texts marked `reopen` come back as above (`:1268`; T332).
   - The file's tags are added, a tag already there kept, and so are its marks of files never written; the label recorded stays as it is (`:1269-1274`; M14).
   - The pool's `changed_at` is set and its `saved_at` cleared (`:1275`), which nothing reads (M5) **[code]**.
   - Then the matched windows' display caches are derived, and each gets the check where a slot changes under the current buffer (`:1351-1355`, A1).
3. Without data: a **fresh start**.
   - **With the hint**, only the hint's tab starts fresh, and nothing else changes (`start_tab_fresh`, `storage/routines.lua:1195-1215`, run at `:1345-1346`; T354): the tab's triquetras are dropped, each through `unregister_triquetra`; when no tab session has started yet, the unnamed session is taken from the editor's session; the tab joins the session's pool, made when there's none yet, the session it was in closed as above, and any other tab in it pushed out into a detached list (M5); and each of the tab's windows but a float that shows a trackable buffer takes it in, inside that window, as an arrival does, so it's registered and visited, and the window gets `{c=<shown>}` (M3, M4, M6). The session doesn't become the editor's session, and the other tabs and the closed lists stay as they are (T354). A file that couldn't be read gives its WARN as above, with "the session starts fresh" meaning this tab **[code]**.
   - **Without it**, cavediver's state is cleared, the pools going back to the editor's alone (M5), every loaded buffer is registered (`repopulate_history`), and every window gets `{c=X}` (`repopulate_window_relationships`). The session becomes the editor's session, with no unnamed one (`storage/routines.lua:1408-1409`). A missing or unreadable file gives no scope, so without the hint this is the whole editor's fresh start whatever the name was saved as **[code]**.
4. Then `cleanup_system` runs, and history → `attached` with the current buffer. The load is a step of its own in the ledger, holding what it matched, closed and reopened, or its fresh start and why (A27, T412, T413).

**[run s11]** recorded a load with unloaded buffers losing slots, before the `paths` table: a value with no restored buffer was deciphered as a path and gave noise, so the slot came back empty or the current slot got healed (DESK:1379; T139). DESK:1381 recorded windows matched by position, shifted when the save and the load counted windows differently, and `initialise_crux_internals` throwing `table index is nil` on a count mismatch, before the matching by what windows show (T142, T244).

DESK:1561 and **[run s10]** recorded the XOR the file used before step 5 giving the directory away: with the session's directory as the key, every path inside it began with a run of zero bytes once XOR'd, so its base64 value opened with a run of `A`s (s10 saw it in `closed`, which held XOR'd paths then).

**[run s12]**, the happy path: a file saved with `{c=d s=c t=e p=[b]off}` and `dtm{b→a, c→b, e-swap→d}` came back the same, with `b`, `c` and `e` loaded and `d` shown, except that it recorded `p=[b]off` coming back `p=[b]on`, before `[8]` (T136).

### S2. Decided (DESK)

Built: the API, the file's name, the loading, the contents, save-as-closed and oil, in step 4; the file, the checks and the migration script, in step 5; keeping a reference that resolves to nothing, in step 6; tab sessions, the load's hint and the records cavediver writes itself, in step 7, but for the parts named under them; and part of the errors, in step 2. Built in step 7: the closed-stack picker (Closed-stack picker, below). Built in step 8: the written contract, in the README. Not built: those parts of tab sessions.

**Contract and API** (DESK:749-794):
- Cavediver is manager agnostic, with no adapters.
- `save_session(name?, opts?)`, where `opts.tab` marks a tab session, and `load_session(name?)`. Neither takes a directory: cavediver reads it itself, `getcwd(-1, -1)` for the whole editor or the tab's directory for a tab session.
- A written contract says who calls the two functions and when: resession, native `:mksession`, and no manager, with the table at DESK:764-771. It includes saving the outgoing session through the manager before a switch, and saving a tab session on `TabClosedPre`.
- **Decided (2026-10-23), "A hint in the call"** (the author's answer to a load whose file is missing, which had no scope to go by): `load_session(name, { tab = tabpage })`, as `save_session` has. When there's a usable file, the file's scope wins. With the hint and no usable file, only that tab starts fresh, and nothing else is torn down. The README's wiring gains the argument.

Built in step 4: the API and the file's name (S1; T255, T292–T294). Neither function takes a directory: cavediver reads it, `getcwd(-1, -1)` for the whole editor or the tab's for `opts.tab`, and the file is named `sha256(directory .. "\n" .. name)`, or `sha256(directory)` for a nameless save. Built in step 7: the load finds a tab session's file in the tab's own directory, when the tab you're in has one and a file of that name is there, and in the global directory otherwise (S1 API, T352). Built in step 7, the hint: `load_session(name?, opts?)` with `opts.tab`; a usable file's scope wins (T355), and with the hint and no usable file only the hint's tab starts fresh, nothing else torn down, and the session isn't taken as the whole editor's (S1 State machine and Load; T354). The tab's directory is read from the tabpage the hint names, and the load works on that tab, wherever the focus is (T367). A `:restart` rerun keeps the hint (S1 State machine). Built in step 8: the written contract, the README's "Session manager setup" (README:68-136; D28), whose resession wiring passes the hint (S1 API).

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

Built in step 5 (S1 File and Save; T212, T301–T308, T310): AES-256-GCM through `libcrypto` over LuaJIT's FFI; PBKDF2-HMAC-SHA256 with 200,000 rounds, from the session's directory and a random salt, which is kept from one save to the next, so the key stays the same; the clear `CDV1` header, covered by the tag with the salt; the main file named `sha256(directory .. "\n" .. name)` with nothing after it, and one file per No Name text in `<main>.d/`, named through the key after its text and written only when it changes; the texts first, the main file last as the commit point, then the sweep of every file it doesn't name; every write atomic, in mode 0600. No count limit holds (T309).

Built in step 5, the migration script (`scripts/migrate_sessions.lua`; T338, T340): it's run once as `nvim --clean -l scripts/migrate_sessions.lua [--resession-dir <dir>] [--session-dir <path>] [--dry-run] [--replace]`, so none of the user's config runs, and before the first session on the encrypted format. It finds each old file through resession's session list (the author, 2026-10-23: "resession's session list (Recommended)"): every session file in `stdpath("data")/<dir>/` (`session` unless another is passed) names its cwd; the session's directory is that cwd, the tab's for a tab session, and its name is the saved cwd whose form with `/` and `:` made `_` is the session file's name, as resession names its files; a session whose name can't be told that way is reported and left. Its old file is the first 32 hex characters of `sha256(cwd .. "\n")` plus `.json`. Each one found is written again in the encrypted format through `write_session`, under `sha256(directory .. "\n" .. name)`, the name the session manager passes (the author, 2026-10-23: "whatever the session manager produces"). Hashes are worked out again with `vim.fn.sha256`: an old raw hash resolves through the buffers resession saved and the paths the old file kept, and one nothing names, like a deciphered value that isn't a path, is dropped and counted. A window entry gets `[7]` from its old current slot, `[8]` from "queue not empty" (what the old load did) and `[9]` from the old window history only when the old file's window histories line up with its windows. Each old file it converts is kept, renamed with `.migrated` added, which is the script's record of what it has converted, so a second run changes nothing and a load no longer points to it. A session whose old file isn't marked but that has a file in the new format already, saved before the script ran (a fresh start, since the load found no new file), is reported by its session file's name and left, and `--replace` converts over it, its own No Name text files going with it (T342). `--dry-run` writes and renames nothing. It reports counts. A load that finds only a file named the old way says to run it (the author, 2026-10-23: "Point to the script (Recommended)"; S1 Load).

**Decided (2026-10-23), "Keep them":** each session's key is kept in memory while the session is open, so writing its records doesn't stretch it again. Built in step 7: kept by directory and salt, so a file another editor gave a new salt never gets the old key (S1 File, T363). A key goes once no open session uses it, after a load, a save, or a tab session's pool gone (S1 File) **[code]**.

**Contents** (DESK:1428-1456):
- References are saved as hashes and resolved at runtime.
- A `paths` table holds hash → path for everything the registry knows, plus **outsiders**: untracked buffers that windows showed, like `oil:///…`.
- Each window entry records `shows`.
- At load, each restored buffer's name is hashed:
  - a registry entry is registered, loaded or not
  - an outsider only helps match windows
  - no match waits for `BufEnter`
- Windows are matched by what they show, keeping order for the same file. An unmatched entry is dropped; an unmatched window starts fresh.

Built in step 4 (S1; T134, T139, T142, T244, T251, T314, T315): references saved as raw hashes and looked up at runtime, with the `paths` table and the outsiders; each window entry records `shows`, and windows are matched by it; each entry also saves `primary_enabled` (T136). A reference whose buffer didn't come back is closed at load, so its slot keeps it and reopens it when used (T337). Built in step 6: a reference to a file gone from disk is kept the same way, as a closed reference, and its slot says so when it's used (Checks, below; T313).

**Save-as-closed** (DESK:1630-1640):
- Open, non-empty No Name buffers are saved like closed ones.
- At load they're reopened in the background, marked modified, hidden, under a fresh id, and every reference to them is renamed.
- No Name buffers closed with `<M-.>` stay on the stack.

Built in step 4: the first two (S1, M5; T140, T300, T316). The save writes an open, non-empty No Name buffer's text as it writes a closed one's, marked `reopen` in `noname_content`, and keeps its hash out of `closed`; a No Name current slot is saved as its own hash, like any slot (T213). At load each one comes back as a listed buffer, hidden and modified, under a fresh id, with every slot, queue entry, note and history entry that named it renamed, and with no visit recorded; one that's already back in the editor is taken as it is. The third holds too: a No Name text closed with `<M-.>` stays on the closed stack across a save and a load (T246). Built in step 5: each text in a file of its own in `<main>.d/` (The file, above; T305), and a closed text read from its file only when it's reopened or the closed lists draw it (M5). Built in step 7: each pool's own texts, so a tab session's files hold its texts and not another tab's (S1 Save, T332).

**Checks** (DESK:1672-1689):

| The file | The load |
|---|---|
| missing | a fresh start |
| has a newer header | "made by a newer cavediver", and the file is left alone |
| has no header | "run the migration script" |
| fails the GCM check | "failed its integrity check (edited or corrupted)", then a fresh start |

A reference that resolves to nothing is kept and says so when it's used.

Built in step 5 (S1 Load; T144, T245, T310–T312, T340): the four rows, with the messages in S1 Load; a load that finds no file under the new name but one named the old way says to run the migration script. A file with no header gets the migration script's message when it's JSON, starting with `{`, and the integrity message otherwise. A save doesn't overwrite a file made by a newer cavediver either: it throws (S1 Save). A No Name text's file that fails its check loses that text alone (T308). Built in step 6: a reference that resolves to nothing is kept, says so when it's used, and works again once its file is back (T313).

**Errors and drift** (DESK:1054-1076, DESK:1154-1157):
- The save hook is critical: an environment failure throws into the manager's hook, so neither file is saved.
- Cavediver's own data can't make the save fail (I2, I3, I14).
- References are saved only together with the manager; records may be refreshed on their own.
- With two instances, the last writer wins.
- **Decided (2026-10-23), records written whenever they'd otherwise be lost** (the author: "Yes, all three moments", then "Crashes too" and "On every change"): cavediver writes every known session's records, its closed lists, close times and No Name texts, as a tab session's tab closes, as the editor quits, before a load tears the old state down, and on every change. It never makes a session's file and never writes references, which stay with the manager.

Built in step 2: the first point as far as cavediver goes, the save hook throwing to `save_session`'s caller (I21), and the second point for the triquetras the getter makes (I3, I14). Built in step 7: the third point for the unnamed session, whose records, its closed stack and its No Name texts, a tab-session save refreshes in its file, leaving its references (S1 Save, T323). Built in step 7, records on time: the third point for every session cavediver knows, written as a tab session's tab closes, at quit, and on every change: on the next tick when the records' timer of a second isn't running, and again when it runs out; never into a new file, never touching references, and on a change or at quit only while storage is idle and the editor is still where the session would be saved from (S1 Records; T296, T322, T358, T359, T361, T362). The moment before a load tears the old state down is built the other way round: by the time `load_session` runs, the manager's restore has torn the outgoing session down, events on, so a load on the whole editor's route drops a write still pending instead of writing it (S1 State machine, T360). A tab close's write waits a tick, so a manager's switch, whose teardown closes tabs before the load it ends with, drops it with the rest, and a quit in the same batch writes it (S1 Records; T358, T365). The decision has the trail's pages ride along; the trail isn't built. With two editors on one session, the last writer wins at the saves (T317); each one also writes its records over the other's at every change **[inferred]**.

**Tab sessions** (DESK:938-966):
- The scope is written into the file.
- There's one **pool** per session: its closed stack, No Name texts, and a visit overlay ranked above the global history.
- Closes go to the pool of the current tab, and `<M-S-w>` reopens from it.
- A buffer belongs to every tab that visited it.
- Saves are snapshots: a whole-editor save merges the pools by close time in the file only. The detached lists are the one exception to that merge ("Subsume, merge by close time", 2026-10-19): they exist in no file of their own, so the whole editor's file holds them apart (the author, 2026-10-23: "it will be saved on editor's cavediver file").
- A closed tab is saved through the manager. ~~Otherwise it's kept with no tab and a notice.~~ Decided 2026-10-19 (the author: "Save via manager, fallback (a) (Recommended)", and "And we make a notice everytime that fallback occurs."; DESK:1022, DESK:1024); replaced by the author's answer of 2026-10-23, "this shouldn't happen at all", then "Yes, that's it": as a tab session's tab closes, cavediver writes the session's records into its file itself, its closed list and No Name texts, and the list goes. Only a write that fails, or a session with no file, keeps the list, with a warning.
- ~~A second tab loading a session that's already open shares its list: what's in memory stays, and the file only fills in.~~ Decided 2026-10-23, with the tab close; replaced the same day by the author's answers "One tab, with carry" and "A DETACHED list", asked what's general across managers: a tab session is in one tab at a time, and the last load or save naming a tab for it decides which, as resession's `load` and `save_tab` do (`remove_tabpage_session`). The tab it was in keeps a detached list of its own, `t_DETACHED` for a session t, a copy of the session's list, saved in the whole editor's file and matched back to its tab at load. The author: "we hold a DETACHED pool, and it will be saved on editor's cavediver file, and it will forever accumulate I guess. t_DETACHED, notes_DETACHED, things like that. It is matched by the tab resession file as well." A detached list left with no tab, its tab closed, saved or loaded as another session, or not brought back by a load, is written into the whole editor's file and dropped from memory; the file keeps every such list, and the picker reaches them (the author, 2026-10-23: "File only, piling up", "Yes, that's it"); with no whole-editor file to write it into, it stays in memory with no tab, with a warning. When t is loaded into the tab that holds `t_DETACHED`, the picker opens at once to merge, showing every list as it always does, with the cursor on `t_DETACHED`'s (the author: "Every list"); t loaded into any other tab opens nothing (the author, 2026-10-24: "Only its t_DETACHED tab", and "to make the user aware that they ressurected some cabal and cavediver needs an input for such demonic spawn").
- The unnamed session's records are refreshed at tab-session saves.

Built in step 7 (S1, M4, M5; T318–T321, T323, T332, T349–T353): the scope, in the file, with a tab session's file loading into one tab alone, the hint's or the one you're in, from `idle` as from `bare`, and found in that tab's own directory when it has one; one pool per session, with its closed stack and close times, its No Name texts and its visits, which its tab ranks above the global history under either view; a close going on the pool of the tab it happens in, on the pools the file came off when it was opened again and on the pool of every tab that visited it (Q15), a file open again leaving every pool, and `<M-S-w>` reopening from the current tab's pool; a whole-editor save merging the pools by close time in the file only, one copy of a file, the newer; and a tab-session save refreshing the unnamed session's closed stack and No Name texts in its file, leaving its references. Built in step 7, records on time: a tab session's tab closed writes the session's records into its file and drops its pool, whether or not the session was saved since, and keeps the pool with no tab, with a WARN, only when they can't be written or the session has no file (M5, S1 Records; T322, T351, T356); a second tab loading a session already open in a tab, or kept with no tab, shares its list, what's in memory staying and the file filling in under it (S1 Load, T357), which the one-tab rule replaces (above); and a tab that leaves a session for another, by a load into it or a save of it as the other, closes the session it leaves when no tab is left in it, as a tab close does, and a save of a tab under a session it wasn't in carries the closed files the tab's slots hold onto that session's list, the list it leaves keeping its copy (the author, 2026-10-23: "Carry slot entries", then "Carry a copy" twice; M5, S1 Save; T366, T368).

Built in step 7, one tab at a time and the detached lists: a load into a tab, or a save of a tab, as a session open in another tab pushes that other tab out into a detached list, a copy of the session's list, named `t_DETACHED`, `t_DETACHED_2` and on; the whole editor's file holds them apart from its closed list, and a whole-editor load brings each back to its tab through its windows; one left with no tab goes into the whole editor's file alone, or, with no whole-editor file, stays in memory with a warning (M5, S1 Save, Load and Records; T369, T378–T383). Built in step 7 too: the picker reaching the lists in the whole editor's file alone, and case 8's picker, with the cascade (Closed-stack picker, below; T384–T389). `:restart`'s reload runs the last load alone, so after a tab session's load it loads that tab session, and the whole editor's session isn't loaded again (S1 State machine). A load whose file is missing or can't be read, without the hint, has no scope to go by, so it's the whole editor's fresh start, a tab session's name included, and that name becomes the editor's session (S1 Load step 3); the README's resession wiring passes the hint for a tab session's load (Contract and API, above). And `came_from` isn't saved: in a later editor, a file closed again goes on the pool of the tab it's closed in and on its visitors' pools, not on the ones it came off in the editor before (M5).

**Oil** (DESK:2085-2095): oil windows come back as oil, and cavediver sets `vim.w.oil_original_buffer` from the triquetra's current slot.

Built in step 4 (S1; T146, T324): the save leaves an oil window on its oil buffer, so the session manager saves it as it is, and `[7]` records the oil buffer as an outsider. At load the window finds its entry by the outsider's hash and keeps its triquetra, and when its current slot's buffer is registered, cavediver sets `vim.w.oil_original_buffer` to that buffer, so oil's `q` (`oil.close`) goes back to it. The oil buffer itself stays unregistered.

**Closed-stack picker** (DESK:2353-2376): `:CavediverClosed`, plus a keymap, is an editable buffer.
- Each pool is a header, and its closed entries are listed under it.
- A No Name entry shows as `[No Name] "first line…" filetype`, with its close time.
- Pools merge by cutting and pasting lines.
- Discarding a No Name entry asks for confirmation.
- Reordering lines reorders the stack, and `<CR>` reopens the entry.
- **Decided (2026-10-23), in the trail's language** (the author: "Yes, in the language (Recommended)", and "Same keys everywhere"): the decoration, each entry's closed glyph, its close time, a No Name entry's filetype, a missing file's tag and each list's tabs, is virtual text, so the lines you edit stay plain: a list's header (`≡editor`, `≡t`) and an entry's name (its path, or `[No Name] "first line…"`). The pieces T326 checks are matched on the line as it shows, its text and the virtual text drawn on it.
- **Decided (2026-10-23), one key grammar** (the author: "Adopt it (Recommended)"), the same keys as the trail's and the primary pop-up's: `q` leaves, writing first; `<CR>`, the main action, reopens the entry in the window you came from and leaves, since `gf` is the one that stays (both read from Q12's "Save and close" and "Same keys everywhere", and confirmed by the author, 2026-10-24: "Both right"); `gf` acts and stays, reopening it with the picker still open; `za` folds a list under its header; `H` and `L` go to the previous and the next list; `:w` writes. Each key has a name in `configs.lua` (the author: "Make them configurable").
- **Decided (2026-10-23), a configurable design** (the author ticked "Colours", "Glyphs, with an ASCII set", "Header pieces" and "Layout and wording"): the colours (`colors.trail`), the glyphs (`glyphs.set`, `"unicode"` by default or `"ascii"`, and any glyph of one's own by its name, such as `glyphs = { closed = "v" }`), and the layout and wording through formatter functions. The keys sit in `keymaps.views` (`leave`, `act`, `act_and_stay`, `fold`, `previous_section`, `next_section`), shared by every view.
- The keymap is `open_closed_lists`, `<M-;>W` by default (DESK:2374, left to me).

Built in step 7, the closed lists (7b; `ui/routines.lua:268-865`; T325–T331, T370–T377). `:CavediverClosed` and `<M-;>W` open a float on an `acwrite` buffer named `cavediver://closed-lists`, unlisted, that goes with its window (`bufhidden = wipe`), however the window closes, so nothing is left to clash with the next one (`show_closed_lists`, `:786-865`). It's opened from the window you're in, or from the last tracked window when you're in a float.
- **What it draws** (`draw_closed_lists`, `:445-521`): the editor's list first, then the tab sessions' lists with a tab, then any with none. Each list is a header line, the list glyph and the list's name, `editor` or its session's, with its directory's last part when two sessions share a name, and its entries under it, newest first: a file by its path from the cwd, a No Name text as `[No Name] "first line"`, cut at 24 characters (`closed_entry_name`, `:320-348`). Two entries whose lines would read the same are numbered `#2`, `#3`. A text held unread from a session file is read to show its first line, and kept read **[code]**.
- **The decoration** is virtual text, drawn again at every edit (`decorate_closed_lists`, `:401-435`): after a header, its tabs (`tab 1`, `tabs 1, 3`, `no tab`); before an entry, the closed glyph; after it, the formatter's text, by default a No Name text's filetype, the close time, `HH:MM` today and the day and date otherwise, and a missing file's tag (`closed_entry_text`, `:382-392`; T326, T373). The time drawn under a list is that list's own for the file, or, on a line moved in from another list, the newest close time any list had for it (`closed_entry_time`, `:360-372`).
- **`:w`** (`write_closed_lists`, `:537-648`): each header's lines become its list, newest first, and a line under another header moves the file there (T327, T331). A file twice under one header is kept once, at the newest close time any list had for it (T371); a file once under the list that held it keeps that list's own time, so a `:w` with no edits changes nothing (T372). A deleted line discards the file from that list (T329). A No Name text left on no list is asked about first, "Discard these No Name texts? They exist nowhere else.", and "Keep" writes nothing (T376); one discarded leaves the No Name cache. A line that names no list or entry, a typed header included, refuses the whole write with an ERROR naming it (T377). A file closed onto a list after the window opened stays on it, as the newest, and a list a load tore down meanwhile is left alone **[code]**. A list that changed marks its session changed, so its records are written (`pool_changed`, `history/routines.lua:259`; S1 Records).
- **Keys** (`keymaps.views`, set on the buffer's FileType, `ui/hooks.lua:163-194`; T370): `q`, and `<C-c>` as `keymaps.views.leave_too` (mine), writes when the lines were edited, then leaves, and stays open when the write is refused (`leave_closed_lists`, `ui/routines.lua:666-671`); `<CR>` writes when edited, reopens the entry in the window the lists were opened from, and leaves, and `gf` does the same and stays, the lists drawn again (`reopen_from_closed_lists`, `:683-746`; T328). A file gone from disk isn't reopened, and says so. `za` folds a list under its header (`closed_lists_fold`, `:770-776`); `H` and `L` go to the previous and the next header (`closed_lists_section`, `:752-763`).
- **The detached lists** show like any list: one in memory under its name, with its tab or "no tab", and one in the whole editor's file alone after the lists in memory, its header marked "in the file" (`file_only_lists`, `storage/routines.lua:1885-1918`; T388). An edit to a list in the file alone is written back into the file, and a list it leaves empty goes from it (`write_file_only_lists`, `:1978-1984`). A line moved out of it onto a list in memory brings its path, and a No Name text's file, held unread, with it (`adopt_file_entry`, `:1958-1971`; T389), and an entry reopened from it leaves the list as the file holds it then, an edit just written included (`reopen_from_closed_lists`, `ui/routines.lua:683-746`; T390). An edit to it that can't be written into the file says so, "cavediver: the closed lists' edits to the lists in the whole editor's file alone weren't written, since <why>; they're still on screen.", and the window keeps the edit, unwritten (T391).
- **Case 8** (the author, 2026-10-24: "Only its t_DETACHED tab", "Every list"): t loaded into the tab that holds a detached list of t opens the closed lists once the load settles, on every list, the cursor on that list's header (`join_for_load`, `storage/routines.lua:1169-1183`; T384). The list waits in memory, with no tab, while the window is open; when the last such window goes, it goes into the whole editor's file, or, emptied by a merge, from memory and from the file (`settle_merging`, `:1994-2010`; T385, T386). t loaded into any other tab opens nothing (T387). In the same load, the tab t was in is pushed out as any other (T384).
- **Configurable:** `glyphs`, the unicode set `≡ ↓ ⎇ …` or the ascii set `# v @ ...`, each glyph overridable by name (`M.glyphs`, `:174-182`; T374); `colors.trail` (`ui/init.lua:63-86`); `closed_lists_popup`, its size; and `formatters.closed_entry`, a function of the entry and the glyphs giving the text after it, the entry's shape documented in `configs.lua` (`CavediverClosedEntry`).

The trail's formatters and its header's pieces are A27's.

## 6. Disagreements between the sources

Each entry gives both sides. When the desk has decided something, that's the intended behaviour, and the code is just today's state. The entries are grouped by topic, so the numbers, which section 3 refers to, aren't in order.

An entry marked **settled by Qn** was settled by the answers of 2026-10-20, and gives the outcome. An entry marked **Settled (2026-10-20)** was settled by the author directly, while going through the open list.

**Fixes and the author's voice** (the author, 2026-10-20: "write it the way I write it", then "only try write in my voice if you have samples right away"). A doc or string fix is written in the author's voice only when a sample of the author's own writing for that text is at hand, and the sample is shown next to the fix. Without one, the fix is in plain wording.

**Keys and configuration**

- **D1. `toggle_primary` and `set_primary` keys swapped.** `configs.lua:126-127` binds `toggle_primary = "<M-;><M-x>"` and `set_primary = "<M-;><M-c>"`. README:319-320 has them the other way round. SPEC:292 says the primary is set with `<M-;><M-x>`. The desk lists this as the README being out of date (DESK:2489).
  - **Settled by Q8:** the code wins. The README has the two keys swapped, a bug, so README:319-320 changes; SPEC:292 is out of date. Only `toggle_primary`'s keymap description changes in the code (A9).
  - Built in step 8: the README's defaults block has them the right way round (README:450-451). Its comment on `toggle_primary`, copied from `configs.lua:301` as D2 copies the block, still reads "Toggle current buffer as primary"; no decision names that comment **[code]**.
- **D2. README's defaults block vs `configs.lua`.**
  - The colours differ (README:228-298 against `configs.lua:29-105`).
  - `cleanup_interval` is 8000 at README:323 and 4000 at `configs.lua:132`. Both comments say "seconds", but the timer is in milliseconds (`history/init.lua:54`).
  - The README leaves out `primary_buffer_history_popup`, the `open_primary_buffer_history` keymap (it mentions `<m-;>F` at README:32) and `colors.cokeline.diagnostics`.
  - README:285 has `is_picking_focus`, which `configs.lua` lacks. Neither colour is used: the picking colours are hard-coded at `ui/init.lua:379-381`, in the old palette (`#a05959`, `#d7d7a5`).
  - How it drifted: the code's palette changed in `778668f` ("chore(config): updated default colors", 2026-01-07) and `cleanup_interval` went from 8000 to 4000 in `59463f2` (2025-07-17); the README's block is from its first draft (2025-07-10).
  - **Settled (2026-10-20):** the README follows the code: its defaults block copies `configs.lua`, including the missing keys, and the `cleanup_interval` comment says milliseconds. The pick letters read their colours from the config, `colors.cokeline.is_picking_close` and a new `is_picking_focus`, instead of the hard-coded pair. The `is_picking_focus` default is blue, `#4385BE` (the author, 2026-10-24: "Blue #4385BE"; T168).
  - Built in step 8: the pick letters' colours from the config (`ui/init.lua:443`, `:445`) and `is_picking_focus`'s default (`configs.lua:260`; T168). Built in step 8, the docs: the README's defaults block copies `configs.lua`'s (README:253-513), and `cleanup_interval`'s comment says milliseconds there and in `configs.lua:361`.
- **D3. Keymap descriptions.** `close_buffer` (`init.lua:111`) and `open_primary_buffer_history` (`init.lua:117`) are both described as "Toggle current buffer as primary". So is `cycle_select` in its annotation at `configs.lua:10`.
  - **Settled (2026-10-20):** each key gets its own description: `toggle_primary` "Switch the primary on or off" (Q8), `close_buffer` "Close the current buffer", `open_primary_buffer_history` "Open the primary queue". `cycle_select`'s annotation copies the author's own description of that key, "Select cycling buffer and attach history" (`init.lua:86`) (T169). The `cycle_select` annotation copying the author's own description was confirmed by the author (2026-10-20, late evening).
  - Built in step 8: the three descriptions and the annotation (`init.lua:132`, `:139`, `:146`, `configs.lua:10`; T156, T169).
- **D4. Hashing dependency.**
  - Today: README:47 requires `openssl` "for hashing file names and directories", but the code hashes with `vim.fn.sha256`, with no shell and no openssl (`history/routines.lua:37`, `storage/routines.lua:631`).
  - Decided: `vim.fn.sha256` for hashing, and `libcrypto` only for encryption (DESK:1541, DESK:2131).
  - **Settled (2026-10-20):** README:47 says `libcrypto` (OpenSSL 3) is needed to encrypt the session file, and hashing needs nothing extra.
  - Built in step 2: hashing with `vim.fn.sha256`, for file names and the session file's name (M1). `libcrypto` comes with the encryption (S2). Built in step 8: the README's requirements say so (README:46).

**Primary**

- **D5. A disabled primary.**
  - README:31: `<m-;><m-f>` "won't do anything at all, until you set it to active again", and you can still use the popup while it's disabled.
  - Code: `<M-;><M-f>` falls back to `<M-f>` (`window/routines.lua:907-910`) **[run s02]**, and saving the popup sets `primary_enabled = true` whenever the queue isn't empty (`window/routines.lua:231-235`).
  - **Settled by Q10:** the code wins for the key. With the primary disabled, `<M-;><M-f>` acts like `<M-f>`, and README:31 changes. The popup save follows a new rule: it switches the primary on only when the first row changed, and otherwise keeps the on/off state (A18).
  - Built in step 8: the pop-up's save switches the primary on only when the first row changed (`window/routines.lua:274`, T158), and README:31 says `<m-;><m-f>` acts like `<m-f>` while the primary is disabled.
- **D6. A popup save with an invalid path.** README:26-28 says nothing is saved. The code reports the bad lines and saves the valid ones (`window/routines.lua:224-236`).
  - **Settled by Q11:** the code wins, and README:28 changes.
  - Built in step 8: README:28 says the bad line is reported and the other lines still get saved.
- **D12. Popup close keys.** `q` and `<C-c>` are described as "Close without saving" (`ui/hooks.lua:130-132`), but `close_window` runs `write!` first (`ui/hooks.lua:91`).
  - **Settled by Q12:** the code wins. They save and then close, and their description changes to "Save and close".
  - Built in step 8 (`ui/hooks.lua:142-145`, T161).
- **D19. Primary overlapping a slot.**
  - README:368: "A buffer cannot occur more than once in a window triquetra."
  - SPEC:44 and SPEC:294: the primary is mobile and "can occupy any slot position". The code allows it.
  - `bufferline.get_buffer_relationships` asserts each buffer has one role, so it throws when, for example, current = primary (`ui/init.lua:202-226`) **[run s14]**.
  - So README:368 holds for the three slots only.
  - **Settled by Q16:** the primary is mobile. README:368's "no buffer twice" covers the current, secondary and ternary only. `get_buffer_relationships`' one-role assertion is fixed or removed; nothing calls it.
  - Built in step 8: the assertion fixed, covering the current, secondary and ternary alone (`ui/init.lua:266`, T119).

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
  - Built in step 3: both routes write the notes through one function (`write_secondary_swap_notes`, `window/routines.lua:79-93`; T30, T191), and the round trip on either route says there's nothing to restore or brings back the older secondary (T177–T180).
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
  - Built in step 3, on both maps, swap keys included (`window/routines.lua:1035-1100`; T67, T68, T173, T174, T193, T266, T267).
- **D11. The secondary's first population.**
  - SPEC:299-300: "No auto-population: Never automatically populated from history." SPEC:92-94, the code and STATUS fill it from history on the first `<M-f>` (`window/routines.lua:757-764`).
  - SPEC:428-447, "Secondary Population Edge Case", puts the current buffer in the secondary (`current: A, secondary: A`), which breaks SPEC's own Rule 1 (SPEC:343) and README:368. The code takes `ordered[2]`.
  - **Settled (2026-10-20 evening):** the fill from history stays (pressing `<M-f>` is acting, P14). The duplicate came from a cycle in another window freezing the history **[run `t/b7_dup.lua`; under `history_view = "window"` the same route duplicated in 7 of 8 re-runs, `t/b7w_dup.lua`: the window view's rebuild ties two buffers and the tie breaks at random, see the bug below]**. The author's fix is at the cause: jumping windows ends the cycle (A12). The fill then **asserts** that the ordered list's first entry is the window's current buffer, so any leftover route throws and gets fixed, the same stance as Q13 (T176).
  - **bug (new), found 2026-10-21:** the window view's rebuild (`history/routines.lua:257`, `:260`, in `construct_crux`) gives a window's newest buffer the next free access time, so the next buffer recorded ties with it. When the window entry fires no `BufEnter` (same buffer in both windows, e.g. right after `:vsplit`, or after `:close`), the tie breaks at random from one Neovim start to the next. Shortest route to the fill assertion: `:e a`, `:e b`, `:vsplit`, `<C-w>p`, `:e c`, `:vsplit`, `<M-f>` **[sim, window view, multi-window walks]** (T197).
  - The fix, as tested in `all_fixed`: `history/routines.lua:191` `data.history_index = data.history_index + #window_buffers - 1` becomes `+ #window_buffers`, and `:194` `data.history_index - rank + 1` becomes `data.history_index - rank`. A window's buffers keep their order, and the next visit always ranks first on its own: no tie in 675,000 several-window steps.
  - **bug (new), not exercised:** the session-load branch of `track_buffer` (`history/routines.lua:294-298`) can hand out an access time that's already in use, the same kind of tie. No walk loads a session.
  - Built in step 3: the fill's assertion (`window/routines.lua:846-849`, T176), the window-jump cancel with the landing recorded (A12, T198), and the tie fix (`history/routines.lua:933`, `:936`; T197, T288). Built in step 4: the session-load branch of `track_buffer` stores the saved time in the global history (`:955-961`, T20). What a load that goes through ends with doesn't depend on it: `initialise_crux_internals` then resets the window histories and puts the saved global history in place (`:866`, `:872`). Only a load that a throw stops before that keeps the branch's writes, and its window-history write still takes `history_index - 1`, which can tie (`:972`) **[code]**.
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
  - Built in step 8: the docstring (`history/routines.lua:1148-1149`).
  - The window-jump cancel returns the cycling window to this live start (A12).
- **D21. File-picker mode.** SPEC:906-909 says displacement is paused and normal mode comes back automatically after a pick. In the code `file_picker` is registered and never entered (`navigation/sm.lua:24`). STATUS:103 calls it "unused by design".
  - **Settled (2026-10-20):** keep it as scaffolding. A comment at `navigation/states.lua:8` says nothing enters it yet, and SPEC:906-909 is marked as not built. Explorers stay under the visiting rule. The pop-up's `<M-e>` picker (Q11) is unrelated; it shares the name only.
  - Built in step 8: the comment (`navigation/states.lua:8`), and the old spec's mark, SPEC:907, "**Not built:** nothing enters this mode yet; it's registered and kept as scaffolding".

**Closed buffers and cleanup**

- **D13. Closed buffers reopening.** README:15 ("Closed buffers reopen when accessed through relationships") and STATUS:37, STATUS:382-392 say a closed slot reopens. The code prunes closed secondaries and primary entries because the check reads the wrong slot (`window/routines.lua:345`, `:401`) **[run s05, s06]**. The desk lists this (DESK:2470).
  - **Settled (2026-10-20):** a code bug. Each staleness check reads its own entry (DESK:2470), as the comment under each check says (`window/routines.lua:346-348`). README:15 stays as written; I4, T42 and T56 stand **[run `t/pkA_d13.lua`]**.
  - Built in step 1: each check reads its own slot or entry (`window/routines.lua:657`, `:684`, `:713`). T42, T56, T103 and T104 pass.
  - A file whose buffer went without events (a `noautocmd` wipe) goes on the closed stack at the stale pass, so its slots keep it too (A22, I4, T242).
- **D14. A second trigger for the new-file wipe.** The desk's repro stays on the new file and waits, so the cleanup tick wipes it, `bw!` from `history/routines.lua:678` (DESK:2446, DESK:3250). Navigating away instead wipes it sooner, at the **next `BufEnter`**, from `window/routines.lua:428` inside `cleanup_triquetras` (A21 step 5) **[run s09]**. Both triggers exist. DESK:1870 already lists that path (healing's missing-file wipe, `:417-449`) for removal, so the decided fix covers it; the bug entry just names only the timer.
  - **Settled (2026-10-20):** the decided fix already covers both triggers (DESK:1859, :1865, :1870). At the next desk sync, the bug entry (DESK:2446) gains the faster route and the dead window ("Sooner still, the next `BufEnter` anywhere wipes it…"), and its repro (DESK:3250) gains "Or skip the wait…" **[run `t/pkA_d14.lua`]**.
  - Built in step 1: both triggers are gone. No `cleanup_system` pass wipes (A22), and `cleanup_triquetras` doesn't check the current slot's file on disk (A21). T109 and T110 pass.
- **D16. Comment on `<M-.>`.** "go to most recent (first in list)" (`history/routines.lua:797`), while the code goes one step older. Known on the desk, and the code is right (DESK:2478).
  - **Settled (2026-10-20):** the one branch comment becomes `-- Otherwise go to most recent relative to the one deleted (next in list, wraps around)`, built from the author's words, "the most recent is relative to the one deleted". The other branch comment stays.
  - Built in step 8 (`history/routines.lua:1518`).
- **D22. The cleanup report.** STATUS:143-158 shows counts by category. The code notifies the total and lists the paths (`history/init.lua:58-87`).
  - **Settled (2026-10-20):** closed by archiving STATUS.

**Windows and documentation of the data**

- **D17. Window-jump history per tab.** `navigation/data.lua:9` ("Per-tab") and STATUS:115 (`[tabnr][to_win]`) describe a per-tab table. The code uses one flat table (`navigation/data.lua:42`, `navigation/routines.lua:54`).
  - **Settled (2026-10-20):** the flat table is intended. After a tab switch, `<M-,>` takes you back to the window you left in the other tab, as today **[run `t/pkA_d17.lua`]**. The author flattened it in 60540e7 (2025-07-20). Only the comment at `navigation/data.lua:9` changes: "Current window -> previous window mapping, one table across all tabs". STATUS:115 goes with STATUS.
  - Built in step 8: the comment (`navigation/data.lua:9`).
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
  - Built in step 8: `get_smart_basename` is the UI's (T120).
  - Built in step 8: the winbar's machine and the bufferline's and the indicators' transitions (`ui/sm.lua:12`, `ui/hooks.lua:29-37`; T220, T123).
- **D24. STATUS's config example.** STATUS:477-498 shows `auto_save`, `save_interval`, `ui.winbar_enabled` and `cleanup_interval = 300 -- 5 minutes`. None of these match `configs.lua`.
  - **Settled (2026-10-20):** closed by archiving STATUS.
- **D25. Small comment slips in the code.**
  - "closed buffer filenames" (`history/data.lua:81`, `history/init.lua:107-109`), where the stack holds hashes.
  - "doesn't create its own state machine" (`window/init.lua:5`), while `window/sm.lua` creates one.
  - `LoopStates` documents `UPDATING "updating"` (`ui/states.lua:18-19`), where the state is `SELF "self"`.
  - The window machine (`window/sm.lua`) has four states (`showing_primary`, `showing_secondary`, `showing_ternary`, `showing_other`), no transitions, and nothing calls `to()` on it; `window/hooks.lua:12` requires it and never uses it. The author calls it an artifact of early modelling.
  - **Settled (2026-10-20):** the closed stack's comments reuse the author's own wording at `history/data.lua:14`, "Stack of closed buffer filehashes that can be reopened"; the loop annotation becomes `---@field SELF "self" Continuous update loop state for UI refresh`. The window machine goes: `window/sm.lua`, the four `SHOWING_*` constants in `window/states.lua`, and their requires (`window/init.lua:7`, `window/hooks.lua:10`, `:12`). The comment at `window/init.lua:4-5` is then true (T170).
  - Built in step 8: the closed stack's comments (`history/data.lua:92`, `history/init.lua:79-83`), the loop annotation (`ui/states.lua:19`), and the window machine gone, its file, its constants and their requires, so `window/init.lua:4-5` is true (T170, T289).

**Today against Decided**

The sources differ here until the code catches up with the desk; each entry is settled.
- **D26. Windows showing something untracked.** README:332: the triquetra is cleaned, which matches the code. The desk's visiting rule keeps it (DESK:1785).
  - **Settled (2026-10-20):** the README follows the desk. Only README:332's middle sentence changes, and "tiquetra" is fixed: "When a window switches to a non-regular buffer then it will keep the triquetra associated to that window, and the current slot stays on the file you were on, so `<m-f>` brings you back to it. The winbar shows it like `main.lua ← [help]`." Built in step 3: README:332 reads so, and the code follows the visiting rule (A2); it's README:519 now.
- **D27. Requirements.** README:44-47 requires resession, cokeline, harpoon and openssl. The desk keeps cokeline required, makes harpoon optional, takes no session-manager dependency, and uses `libcrypto` (DESK:751, DESK:760, DESK:2126, DESK:2144).
  - **Settled (2026-10-20):** README:44-47 becomes: "neovim 0.12+"; "nvim-cokeline"; "openssl 3 (system installed, its libcrypto is used for encrypting the session files. Hashing is done with neovim's built-in `vim.fn.sha256`)"; "harpoon (optional, harpooned buffers are marked in the bufferline)"; "telescope.nvim (optional, used for adding files in the primary buffer pop-up)"; "a session manager (optional, resession.nvim is used in the examples below)". The lazy.nvim example's `dependencies` follows: cokeline in, harpoon out, and its comment goes.
  - The README's cokeline section ("The cavediver plugin can work without the bufferline…") was approved as: "The cavediver plugin can work without the bufferline, but it reduces the experience a lot. Cycling with `<m-n>` and `<m-m>` goes through cokeline, and it's what lets you visualise the visit history of all your buffers, so that you can know how you can end up to your current buffer." (typos "browsers" and "now" fixed). Its middle sentence no longer holds after A12's decision that cycling falls back without cokeline. **Settled (2026-10-20):** README.md:109-111 becomes "The cavediver plugin can work without the bufferline, but it reduces the experience a lot. Cokeline is what lets you visualise the visit history of all your buffers, so that you can know how you can end up to your current buffer."
  - Built in step 8: the requirements as settled (README:42-49), the lazy.nvim example's `dependencies` holding `nvim-cokeline` alone, its comment gone, and its `config = true` given the comma it lacked (README:55-66), and the cokeline paragraph (README:140-142).
- **D28. Session wiring.**
  - README:93-99 passes `vim.loop.cwd()` and wires only `pre_save` and `post_load`.
  - The desk passes the session name and the tab, reads the directory inside cavediver, and adds `pre_load` and `TabClosedPre` (DESK:758, DESK:775-792).
  - **Settled (2026-10-20):** README:67-105 becomes "Session manager setup". It keeps the author's two opening lines, then says what has to happen (`save_session(name)` before the editor is torn down, `load_session(name)` after the manager's restore, the outgoing session saved before a switch, a tab session saved before its tab closes), then the wiring for resession (the author's `buf_filter` kept, the four hooks from DESK:775-792), native sessions (`SessionWritePost`/`SessionLoadPost` with `vim.v.this_session`, and `:mksession!` before `:source`ing another) and no manager (`save_session()` on `VimLeavePre`, `load_session()` by hand).
  - **Decided (2026-10-24), the resession hooks fixed** (the author: "yes", to putting the fixed lines in). Two of the hooks shown on 2026-10-20 rested on wrong assumptions about resession, mine. The outgoing save, `resession.save(name)`, was taken to save a tab session as one; it saves every tab as one whole-editor session and detaches every tab session (`resession/init.lua:302-327`). `TabClosedPre` was taken to fire only for a tab you close; a switch's teardown deletes every buffer and then runs `:tabonly`, events on, so it fires for each tab session's tab with its files already gone. **[run 2026-10-24]**, `main` (a, b) and a tab session `t` (c, d) in a second tab, then `resession.load('main')`: from t's tab, t's resession file became a two-tab whole-editor session, and cavediver's t file whole-editor with it; from the other tab, t's file kept d.txt alone, and cavediver's had no windows and c.txt on its closed list, a close of the teardown's. So `pre_load` calls `resession.save_all({ notify = false })`, which saves each open session as what it is, and `TabClosedPre` skips the save while `resession.is_loading()`, passing the session's `dir`; `post_load` passes the tab when resession kept the other tabs (`not opts.reset`), the hint of 2026-10-23. Run the same way, with the README's own block loaded and its `config()` run, t came through both switches unchanged, and t loaded again into a new tab gave it `⦉c⦊ [d] ⟦-⟧`. DESK:784-791, and the resession cell of the outgoing save's row at DESK:768, carry the 2026-10-20 hooks until the next sync.
  - Built in step 8 (README:68-136): the section, the author's two opening lines as approved ("a hook" become "hooks"), the four things that have to happen, the resession block with the author's `buf_filter` and the fixed hooks (README:101-121), and the native and no-manager lines.
- **D29. Session-file protection.** "XOR-obfuscated session persistence" (`init.lua:4`, STATUS:307) against AES-GCM (DESK:1541).
  - **Settled (2026-10-20):** the XOR docstrings (`storage/routines.lua:58`, `:61`, `:85`, `:86`) leave with the XOR code (DESK:1543). The header at `init.lua:4` changes in build step 5, together with the encryption, to "---hash-based buffer tracking, and encrypted session persistence." STATUS:307 goes with STATUS. No README line says XOR.
  - Built in step 5: the XOR code and its docstrings are gone from `storage/routines.lua`, and `init.lua:4` reads "---hash-based buffer tracking, and encrypted session persistence." (S1 File).

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
- T5 [char] `off(from, to, name)` removes that hook from that transition and nothing else.
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
- T44 [char] With the secondary closed and its file deleted, a cleanup pass keeps the slot, and `<M-f>` says so: `:e a`, `:e b`, `:e c`, `<M-f>`, `:e d` give `⦉c⦊ [d] ⟦b⟧`; after `:bdelete c.txt` and `:bdelete b.txt` (the ternary c is closed too; a closed secondary stays in its slot either way, I4), b.txt deleted and a `cleanup_system` pass leave `⦉c⦊ [d] ⟦b⟧` with `c,b` on the closed stack. `<M-f>` then raises nothing, says "isn't on disk right now", and changes no slot (A6, A21). Before step 6 it was [today]: `<M-f>`, pressed before any pass, warned "Removed secondary file not found in filesystem" and emptied the slot; a pass that came first pruned the slot.
- T45 [char] With the secondary's file deleted on disk, the pointer is kept and `<M-f>` says the file is missing (DESK:2022).
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
- T54 [char] With a disabled primary it acts as `<M-f>` (Q10; README:31 says so).
- T55 [char] While cycling, with the window cycled away from the start, it returns to the start, keeps navigation `cycling`, and changes no slot (Q7).
- T56 [char] With a closed primary, the jump reopens it.
- T57 [char] With the primary's file deleted on disk, a cleanup pass keeps it in the queue, and the jump says so: `:e a`, `<M-;><M-c>`, `:e b`, `:e c`, `:e d` give `⦉c⦊ [d] ⟦-⟧` with `p=[a]on`; after `:bdelete c.txt` and `:bdelete a.txt`, a.txt deleted and a `cleanup_system` pass leave `[a]on`. `<M-;><M-f>` then raises nothing, says "isn't on disk right now", and leaves `⦉c⦊ [d] ⟦-⟧` and `[a]on` (A8, A21). Before step 6 it was [today]: the jump threw "Primary buffer not found in filesystem".
- T58 [char] With the primary's file deleted on disk, it says so and keeps the pointer.
- T153 [char] Q6 on the fallback: with the primary disabled, `{c=A s=S t=T}` and `dtm[T] = S`, `<M-;><M-f>` acts as `<M-f>` and rewrites `dtm[T]` to A before the swap.

**Primary keys (A9, A10)**
- T59 [char] On an empty queue `toggle_primary` gives `[a]on`; again gives `[a]off`; on another buffer it gives `[a]on` with the queue unchanged (Q8).
- T60 [char] `set_primary` on an empty queue gives `[a]on`; on b it gives `[b,a]on`; on b again it gives `[b,a]off`; on a it gives `[a,b]on`.
- T156 [char] The `toggle_primary` keymap's description no longer reads "Toggle current buffer as primary" (Q8).

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
- T192 [char] ("Keep the older one") `rename_hash_in_triquetras(old, new)` moves `dsm[old-swap]` to `dsm[new-swap]` and renames values in both maps, as it already does for `dtm[old-swap]` (`window/data.lua:151-154`). Set it up directly, or with a No Name buffer that holds both kinds of secondary note, closed and then reopened by `<M-f>` **[code]**.
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
- T199 [char] (A26) With no assertion, the recorder writes no file and opens no buffer, and the ring never holds more than N steps.
- T200 [char] (A26) When the restore assertion fires, a file appears under `stdpath("state")/cavediver/` and a scratch buffer opens, both holding the last steps as rows: action or event, window, `⦉t⦊ [c] ⟦s⟧` and notes, ending at the failing step.
- T201 [char] (A26) A dumped file replays to the same assertion: on T200's route in a project kept across editors, with the stale note planted by a typed `:lua` line, the dump replayed in a fresh editor in that project raises "Remembered secondary is the same as current secondary" at `<M-;><M-t>`, its rows up to there matching, and the `:lua` line's code never runs: its recorded row is planted instead.
- T202 [char] (A26) A dump starts with a snapshot of the state at its first step, and replaying snapshot plus steps reproduces every driven step's row: `:e a`, `:e b`, `:e c`, then 110 `<M-S-f>`, so the dump starts from a snapshot that holds them (A26 What a dump holds), then a planted `never`; the replay in a fresh editor in that project drives every `<M-S-f>` the dump holds, and each one's row matches.
- T468 [char] (A26) A replay's editor isn't saved: after T201's replay, `save_session()` throws the replay's message and writes no session file.
- T470 [char] (A26) A replay runs no code a command line chains or carries: a dump holding `:e b.txt | lua _G.CDV_PLANTED = true` and `:e +lua\ _G.CDV_PLANTED=true c.txt`, typed in the editor that made it, replayed in a fresh editor in its project, leaves `CDV_PLANTED` unset there, both steps' rows planted.
- T471 [char] (A26) A replay goes into an editor that has taken in the empty buffer it started on, as one whose config calls `setup()` at startup has: T468's dump, a fresh editor in its project whose empty start buffer is entered once cavediver is set up, so it's registered and its window has `⦉-⦊ [[No Name]] ⟦-⟧`, and the replay goes through, with no WARN, the start buffer forgotten and the window on a. **[run 2026-10-24]** recorded `nvim -u minimal.lua` in a terminal, its init calling `setup()`, refused with "this one tracks buffers already", before the replay forgot it.
- T469 [char] (A26) A dump that spans more than one tab isn't replayed: a dump made with a second tab open, replayed, gives the WARN and leaves the fresh editor as it was.
- T203 [char] (A26) A planted rule break dumps at the next step: with c current in one window and b its ternary, c's ternary note is set to b by hand, and a step in the other window (`:e x`) produces one dump. The break is planted because every real route into one is a route the decided fixes remove; the slot exchange, the first route used here, stops breaking the rule once its fix lands (the author, 2026-10-21: "plant the break instead of %1").
- T204 [char] (A26) A session load and a cleanup re-point appear in the dump as steps tagged `load` and `timer`.
- T205 [char] (A26) A failure that repeats (a highlight callback throwing on every redraw) gives one dump, and the dump window is neither recorded nor tracked: its buffer is `nofile` and unlisted, with no hash, no triquetra and no place in the bufferline, and after a visit to its window, a second, different failure (a hook bound by hand to fail) dumps steps that never name that window or its buffer.
- T333 [char] (A26) A dump opens its scratch buffer only once the editor settles, and names files by their paths: on T200's route, no buffer is added inside the failing call, the scratch buffer is there once it settles, and both it and the file name `c.txt` by its full path, and give its hash. The single assertion helper is checked by what it does: every "shouldn't happen", the hook-failure catch included, dumps (T275). And a hook failure's dump, with a tab session named by the cwd, as native and README wiring name them, holds the hook's name and the session's name. Before 2026-10-24 it checked the other way round, the project's directory and `$HOME` kept out, while the file was plain.
- T460 [char] (A26) A dump is sealed: on T200's route the file starts with `CDV1` and holds none of its text in clear (no `c.txt`, no `<M-;><M-t>`, no `cavediver:`); `:CavediverDump <file>` opens it in a buffer holding the failing row and the `replay:` part; after `:cd sub`, the same command says it doesn't open there and opens nothing.
- T461 [char] (A12) A key that comes before the cancel runs it first: `:e a`, `<M-;><M-c>`, `:e b` give `⦉a⦊ [b] ⟦-⟧` with `p=[a]on`; `:vsplit`, `:e c` give the split `⦉b⦊ [c] ⟦-⟧`; `<M-m>` there, then `<C-w>w<M-;><M-f>` in one batch: nothing throws and nothing dumps, the split shows c again with navigation `normal`, the INFO names the split's window and c.txt, once, the cancel is a move on the window jump's step, as typed by hand, and the other window is `⦉b⦊ [a] ⟦-⟧`; with `'splitright'` off, as the harness runs, and on, since window numbers depend on it (the author: "check the neovim configuration on which cursor the window ends up on after vsplit").
- T463 [char] (A12) An export called from a user's mapping runs the cancel first too: T461's setup, then `vim.cmd.wincmd('w')` and `require('cavediver').jump_to_primary()` in one function: nothing throws and nothing dumps, the split shows c again, and the other window is `⦉b⦊ [a] ⟦-⟧`.
- T464 [char] (M11, A12) A cycle started before its window's arrival has settled starts from it: from a fresh editor, `<M-m><M-m><M-v>:e b.txt<CR><M-m>` in one batch gives no hook failure and no dump, navigation `cycling`, and the window's current slot b. **[run 2026-10-24]** recorded, before the settle queue, cleanup dropping the triquetra in the cycle's own transition (the empty start buffer gone, b not yet taken in) and `snapshot_origin` indexing nil.
- T465 [char] (A1, M11) A key in a macro acts on the buffer the macro just opened: from `⦉a⦊ [c] ⟦-⟧`, `:e b.txt<CR><M-f>` in one batch shows b with `⦉-⦊ [b] ⟦c⟧`, as typed by hand. **[run 2026-10-24]** recorded it ending on c, `⦉a⦊ [c] ⟦-⟧`, "Jumped back to windows current buffer.", b never recorded.
- T466 [char] (M11) The batch keeps its order: from `⦉a⦊ [c] ⟦e⟧`, `:e b.txt<CR><M-f>:e d.txt<CR>` in one batch gives `⦉e⦊ [d] ⟦b⟧`, as typed by hand.
- T467 [char] (A26, M11) A dump lists the settle work still queued: `:edit b.txt` and a planted `never` in one call give a dump whose heading names `arrival b.txt` as pending.
- T462 [char] (A12) A jump's cancel says so: T461's setup, `<M-m>` in the split, then `<C-w>w` alone, settled, gives one INFO, "Cycling cancelled. Window 1 returned to cycling origin buffer: c.txt", the split being window 1 with `'splitright'` off, as the harness runs.
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
- T89 [char] `<M-S-w>` on a missing file says so and leaves the entry on the stack.
- T90 [char] A reopened No Name buffer gets its cursor in its own window, with no "Invalid cursor line".
- T91 [char] After a No Name buffer is reopened, every slot and map entry that held its old hash holds the new one.
- T162 [char] (Q15) I22: pushing a hash that's already on the closed stack (for example, `track_closing_filehash_force` on x, t, then x again) leaves it on the stack once, as the newest entry: `t,x`. With pools: closing `notes.md` in two tabs' pools and merging both entries leaves one, the newer; the whole-editor save's merge in the file keeps one copy, the newer (T321), and so does the picker's (T371); this test covers the single stack.
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
- T101 [char] Saving with the first row unchanged leaves a disabled primary off: from `[b,a]off`, the line `b` alone saves `[b]off` (Q10). Paired with T158; before step 8 it pinned the re-enable, `[b]on`, as [today].
- T158 [char] A save switches the primary on only when the first row changed (Q10). Paired with T101.
  - `p=[b,a]off`, reorder the lines to `a`, `b`, `:w` → `p=[a,b]on`.
  - `p=[b,a]off`, delete the `a` line, `:w` → `p=[b]off`.
  - `p=[b,a]on`, delete the `a` line, `:w` → `p=[b]on`.
- T159 [char] `<M-e>` in the primary queue window, with the picker provider stubbed (Q11):
  - One file picked, the cursor on an empty line: the path fills that line.
  - One file picked, the cursor on a non-empty line: the path goes on a new line after it, and the existing line is unchanged.
  - Two files picked: both paths appear, and no non-empty line changes.
  - Nothing is saved until `:w`, which validates the lines as usual.
- T160 [char] With no picker available, `<M-e>` gives a message and changes no line. `<M-e>` isn't mapped outside the primary queue window (Q11).
- T161 [char] The window's `q` and `<C-c>` mappings are described as "Save and close" (Q12).
- T452 [char] (A18, A27) The pop-up in the trail's language: from `[b,a]on` with a closed and b.txt gone from disk and tagged, the lines are `b.txt` and `a.txt` alone; the first line's virtual text holds `primary · on`, b's line its tag, and a's line the closed glyph; after `<M-;><M-x>` and opening it again, `primary · off`; with `glyphs = { set = "ascii" }`, nothing drawn is outside ASCII.
- T453 [char] (A18) The pop-up's keys are `keymaps.views`': with `keymaps.views.leave = "Q"`, `Q` saves and closes the pop-up, c.txt added there saved as `[b,a,c]on`; `gf` on a.txt's line, from `[b,a,c]on`, makes a the primary, `[a,b,c]on`, and the pop-up stays open, its lines `a.txt`, `b.txt`, `c.txt`.
- T454 [char] (A18, P9) A save keeps a queue entry whose file is gone from disk: from `[b,a]on` with b.txt deleted, the lines `a.txt`, `b.txt` and `:w` save `[a,b]on` with no error; a new line naming no file is still refused (T99).
- T455 [char] (A27) A window's search follows the window: on T411's route, the cancel is a move about the window that cycled, window 2; `:CavediverTrail win 2`, opened from the split, lists it, "1 move over 1 day", and `*` on its line gives the same; `:CavediverTrail win 9`, no such window, says so and searches nothing.
- T456 [char] (M12) The indicators by kind: with b marked by `marks_provider` and current, `:CavediverIndicators roles off` draws b's index as its mark alone, `harpoon off` as `[N]` with no mark and its name with no `⥤ {1}`, and `off` with neither; `on` brings both back.
- T457 [char] (M12) A window with no current slot shows its visit alone: a `:help` split's winbar is centred and holds `[<help's bufnr> help]` in `WinbarVisit`, unfocused `WinbarVisitNC`; a split whose winbar was set by hand keeps it; the help split, its filetype turned `neo-tree`, a skip-list name, loses its bar; with `winbar.own = false` none is drawn.
- T458 [char] (M13) The glyph sets are in the config, and a pair is changed there: `glyphs.unicode.row_t` is `{ "⦉", "⦊" }` and `glyphs.ascii.row_t` `{ "<", ">" }`; with `glyphs = { unicode = { row_t = { "<", ">" } } }`, the trail draws a ternary as `<b>`; `glyphs = { closed = "v" }` still replaces the set's `↓`.
- T459 [char] (A3, M12) The command-line window is neither a visit nor a jump to record: `:e a`, `:e b`, `q:` and `<C-c>` give no hook failure, and the command-line window, while open, has no winbar of cavediver's.

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
- T114 [char] A closed entry whose file is gone from disk stays on the stack, after a `cleanup_system` pass (A22).
- T163 [char] When cleanup re-points a window's current slot to the registered buffer X the window shows (A21 step 1), with X outside the slots, `{c=A s=S t=T}` becomes `{c=X s=S t=A}`, as plain navigation would. Set it up by showing X without a `BufEnter` (`noautocmd`) after A's buffer is gone (Q18).

**Missing files tagged (M14)**

Added with step 6, 2026-10-23, from the desk's decision (DESK:2024-2027), which no earlier case covered. The project gets a planted `.git/HEAD`; no git binary runs.
- T343 [char] (M14) Files that go missing at a branch switch are tagged with the branch being left, the winbar shows it, and it clears when they come back: with `.git/HEAD` at `ref: refs/heads/feature` and b closed in the secondary (`⦉c⦊ [d] ⟦b⟧`), b.txt deleted and HEAD set to `ref: refs/heads/main` tag b `feature`, and the window's winbar holds `⎇feature`; with b.txt written back, a cleanup pass clears the tag and the winbar has no `⎇`.
- T344 [char] (M14) With no label (no `.git` found), a file that goes missing is tagged with the time it went missing, `HH:MM`.
- T345 [char] (M14) A label provider in config names the label: with `label_provider` returning `jj:main`, a closed file that goes missing is tagged `jj:main`.
- T346 [char] (M14, A25) `disable()` stops the watch on `.git/HEAD`: after it, b.txt deleted and HEAD switched tag nothing.
- T346 [char] (M14, A25) A save after `disable()` doesn't watch `.git/HEAD` again: after `disable()`, a `save_session`, then b.txt deleted and HEAD switched, tag nothing.
- T347 [char] (M14, S1) The label at a save is the one being left at the next load: saved with `.git/HEAD` at `ref: refs/heads/feature` and b closed in the secondary (`⦉c⦊ [d] ⟦b⟧`), then, in a fresh process, HEAD set to `ref: refs/heads/main` and b.txt deleted before the load: the load tags b `feature`, the branch the session was saved on, not `main`.
- T348 [char] (M14) A file that was never written isn't tagged, since it never went missing: `:e brandnew.txt` with a line typed, and a cleanup pass, leave it untagged, with no `⎇` in the winbar; once it's written and then deleted on disk, the next pass tags it.

**UI (M12)**
- T115 [char] For `{c=e s=c t=d}`, the winbar holds these pieces in order (seen in run s14): `%#WinbarBufnrTernary#⦉<d>⦊ `, then `%#WinbarBufnrCurrent#[<e>] `, then `%#WinbarFilenameCurrent#e.txt`, then `%#WinbarBufnrSecondary#⟦<c>⟧ `, then `%#WinbarFilenameSecondary#c.txt`. `<x>` stands for the buffer number of x.
- T116 [char] A closed ternary is shown as `⦉ … name ⦊` with no buffer number.
- T117 [char] When the current buffer is the primary, it's shown as `⦉N⦊` in `WinbarBufnrPrimary`.
- T118 [char] A slot closed with `:bdelete` shows its basename, not its full path.
- T119 [char] `get_buffer_relationships` doesn't throw when current = primary, or it's gone (Q16).
- T120 [char] `require('cavediver').get_smart_basename` is a function.
- T121 [char] `compare_buffers(a, b)` is true when a was visited more recently than b; `bufnr_is_displayed` is true for tracked buffers and false for help.
- T122 [char] With 40 tracked buffers, `bufnr_is_displayed` is true for all 40 (Q5).
- T123 [char] `hide_bufferline()` and `show_bufferline()` don't throw.
- T124 [char] While cycling, `get_theme_bg_color(true)` returns `colors.cokeline.bg.detached.focused`.
- T170 [char] (D25) The engine has no machine named `window`; `require('cavediver.engine'):list()` gives `history`, `navigation`, `storage`, `ui_bufferline`, `ui_indicators`, `ui_loop` and `ui_winbar`, the winbar's own, which the toggles build (M12).
- T169 [char] (D3) The `desc` of the mapped keys: `toggle_primary` "Switch the primary on or off", `close_buffer` "Close the current buffer", `open_primary_buffer_history` "Open the primary queue"; no two keys share a description.
- T168 [char] (D2) While cokeline is picking, the pick letter's colour is `colors.cokeline.is_picking_close` (closing) or `colors.cokeline.is_picking_focus` (focusing) from the config; setting either changes the letter's colour. By default `is_picking_focus` is `#4385BE` (the author, 2026-10-24: "Blue #4385BE").
- T446 [char] (M12) The toggles' commands: `:CavediverWinbar off` empties the winbar and it stays empty through the refresh, `on` brings it back, and `toggle` with no argument flips it; `:CavediverIndicators off` takes the role marks off the bufferline's index, and `on` puts them back; `:CavediverBufferline off` displays no buffer, and `on` displays them again; and no keymap entry names any of them.
- T447 [char] (M12) With `winbar = { own = false }`, cavediver writes no winbar: a winbar set by hand on a tracked window at `⦉a⦊ [b] ⟦-⟧` stays through the refresh, a save, and a load from idle, whose teardown clears winbars otherwise; and `require('cavediver').winbar_segment()` gives the window's segment, holding b's `[<bufnr>]` and `b.txt` and no rule.
- T448 [char] (M12) The winbar's skip list is configurable: with `winbar = { skip_filetypes = { 'skipme' } }`, a tracked window whose buffer's filetype is `skipme` gets no winbar; with the defaults, it gets one.
- T449 [char] (A17) `<M-,>`'s skip list is configurable: with `toggle_window = { skip_filetypes = { 'mything' } }`, `<M-,>` skips a previous window whose filetype is `mything`, and goes to one whose filetype is `minimap`.
- T450 [char] (M12, P26) Marked buffers come from the provider: with `marks_provider` returning b.txt's path, b is marked in the bufferline (`is_harpooned`) with its index 1, and a and c aren't; with `marks_provider = false`, nothing is marked though harpoon's stub lists b.
- T451 [char] (A9, A10) `<M-;><M-x>` and `<M-;><M-c>` run no `redraw!`: they redraw the status lines and the tabline.

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
- T134 [char] `save_session(cwd)` writes the keys `paths`, `outsiders`, `buffers`, `windows`, `closed`, `closed_times`, `noname_content`, `missing` and `scope`, `editor` for a whole-editor save, read as the load reads them, decrypted (`read_session`), with `windows[i] = [c, s, p[], t, dtm, dsm, shows, on, history]`: nine fields, `[7]` the hash of the buffer the window shows, `[8]` false with the primary off, `[9]` a table, and the shown file's path in `paths` (S1). That the file holds nothing in clear is T302.
- T135 [char] A round trip with every slot buffer restored and loaded gives back the same slots and maps.
- T136 [char] `primary_enabled = false` survives a round trip.
- T137 [char] `load_session` after a `save_session` in the same process goes through and ends `idle`.
- T138 [char] `load_session` from `idle` tears down and loads.
- T139 [char] A slot whose buffer comes back unloaded (`badd`) keeps its value after load.
- T140 [char] A save with a No Name current slot succeeds and reopens the buffer at load, hidden and modified.
- T141 [char] A save with a `:vsplit` window that has no visits succeeds.
- T142 [char] Two windows, one showing a No Name buffer: after save and load each window gets its own entry.
- T143 [char] A save into a read-only directory throws to the caller.
- T144 [char] A file that fails the integrity check gives the notification and a fresh start.
- T145 [char] Three `load_session` calls in one batch load once.
- T146 [char] A save never wipes a buffer or changes what a window shows, an oil window included. It has two cases: the no-wipe one, and a save leaving an oil window on its oil buffer, built in step 4 (S1, S2 Oil).
- T147 [char] With no file, a load gives every window `{c=<shown>}` and an empty closed stack.
- T148 [char] After switching sessions, the outgoing No Name text isn't in the incoming file.

**Doc checks**

The settled doc and comment changes, which a test can't hold. Each is checked by reading the file once the change is made.
- README: the two primary keys at README:450-451 the right way round (D1); the defaults block copies `configs.lua`, missing keys included, and `cleanup_interval` says milliseconds (D2); README:31 says a disabled primary makes `<M-;><M-f>` act like `<M-f>` (D5); README:28 says a pop-up save keeps the good lines and reports the bad ones (D6); README:519's middle sentence and "tiquetra" (D26); README:42-49's requirements and the lazy.nvim `dependencies` (D4, D27); README:140-142, the cokeline paragraph (D27); README:68-136, "Session manager setup" (D28).
- Keymap and annotation text: `cycle_select`'s annotation at `configs.lua:10` copies "Select cycling buffer and attach history" (D3); the descriptions themselves are T156, T161 and T169.
- Comments and docstrings: the checkpoint docstring at `history/routines.lua:1148-1149` (D15); the `<M-.>` branch comment at `history/routines.lua:1518` (D16); `navigation/data.lua:9`, one jump table across all tabs (D17); the saved-entry annotation at `storage/routines.lua:12-25`, nine fields (D18); `navigation/states.lua:8`, nothing enters `file_picker` yet (D21); the closed-stack comments at `history/data.lua:92` and `history/init.lua:79-83`, and the loop state annotation at `ui/states.lua:18-19` (D25); the header at `init.lua:4`, "encrypted session persistence", and no XOR docstring left in `storage/routines.lua` (D29).
- The engine (Q20): the class declares the shared `transition_modes` table, the factory comment at `engine/init.lua:18` stops implying modes are per machine, and the per-machine wording at `helpers.lua:268` and `:286` is reworded or dropped.
- `ui/routines.lua:1145`: the meaningless 30 in `math.max(#ordered, 30)` goes (Q5).
- The old spec: SPEC:906-910 is marked as not built (D21).
- The desk, at its next sync: DESK.md:2126 and the Dropped line at DESK.md:3146 narrowed to the cokeline fallback (A12); the bug entry at DESK.md:2446 and its repro at DESK.md:3250 gain the faster trigger (D14).

**Negative cases (T207–T249)**

Each checks that something doesn't happen, or that a bad or impossible action is refused or handled without harm, and cites the claim it comes from.
- T207 [char] (P5) A `nofile` scratch entered in a tracked window isn't registered (M3). Help, terminal, `scheme://` and otter buffers are T10; the quickfix list is T217.
- T208 [char] (P10, I17) Notes follow along: `:e a`, `:e b`, `:e c`, `:enew` (an empty No Name N), `:e b`, `:e d` leave N only in the notes (`N>c`, `b>N`). After `:bwipeout` of N, which pushes nothing (M5), no note names N. Before step 6 both notes stayed, since the maps were never pruned, and kept N's path (I2).
- T209 [char] (P14) The secondary changes only when you act: from `⦉-⦊ [c] ⟦b⟧` (`:e a`, `:e b`, `:e c`, `<M-f>`), `:e d`, `:e e`, `:e a`, two cycle steps, `<M-;><M-f>` and `<M-v>` on the start, then `:vsplit` and `<C-w>p` back, leave the secondary on b: `⦉e⦊ [a] ⟦b⟧`.
- T210 [char] (P17) Every window is independent: with window 1 on `⦉c⦊ [d] ⟦b⟧` and `p=[d]on`, `:vsplit`, then `:e e`, `:e a`, `<M-f>`, `<M-f>`, `<M-S-f>`, `:e b`, `<M-;><M-c>`, `<M-;><M-r>` in window 2 leave window 1's slots, notes and primary queue as they were, and so does `<C-w>p` back into it.
- T211 [char] (P20) Restoring is only ever explicit: at `⦉-⦊ [c] ⟦d⟧` (`:e a`, `:e b`, `:e c`, `:e d`, `:e c`, `<M-f>`) with c's note `c>b`, a wait leaves the ternary empty, `<M-S-f>` says "No ternary buffer to swap with." and changes nothing, and only `<M-;><M-r>` brings b back: `⦉b⦊ [c] ⟦d⟧`.
- T212 [char] (P22, S2) The session file is written with mode 0600 whatever the umask: `rw-------` with a umask of 022 (S1 File).
- T213 [char] (P24, M6) A save with a No Name current slot leaves the live triquetra, the notes, the primary queue, the closed stack and the history order as they were: the save writes the slots as they are, the No Name current slot included.
- T214 [char] (P24, A22) A save leaves the closed stack as it was: with b closed and outside the slots, deleting b.txt and saving straight away keeps b on the stack, and the slots, the notes and the history order stay as they were too. Before step 6 the save's `cleanup_system` dropped b, in its closed-stack pass (S1 Save step 1, A22).
- T215 [char] (P26) With harpoon not installed, `:e`, `<M-f>`, `<M-S-f>`, `<M-;><M-c>`, `<M-;><M-r>` and the UI ticks raise nothing and report no hook failure. Before step 8 every history update failed with "module 'harpoon' not found": harpoon was required with no guard.
- T216 [char] (I16) A No Name id isn't reused across sessions: two fresh processes that each run `:e a`, `:enew` get the same buffer number and different ids.
- T217 [char] (I10, A1, A2) A buffer that turns into something untracked isn't left registered or in a slot. Two routes: a buffer entered as `buftype ""` and then set to `nofile`, as a plugin's scratch is, followed by `:e b`; and `:copen`, which enters its buffer before it's a quickfix buffer (DESK:2453), so its window gets no triquetra either. The first route has its arrival undone on `OptionSet`; the second is judged once the editor settles, when the buffer is already a quickfix list (I10).
- T218 [char] (I18) A repeated file in the primary queue window is refused loudly: from `[b,a]on`, the lines `a`, `b`, `a` save `[a,b]` and report the repeat at error level, like a typo'd path under Q11's partial save. Today `[a,b,a]`: `update_primary_buffer` doesn't dedupe. Decided 2026-10-21 (the author: "Refuse loudly").
- T219 [char] (I19, Q14) An empty queue that's switched on stays on: from `p=[]on`, `:e c`, `<M-f>`, `<M-;><M-f>`, `:e a`, `<M-S-f>` and the UI ticks leave `p=[]on`.
- T220 [char] (M11, D23) The winbar and indicator toggles work at runtime: `hide_winbar()` empties the winbar and it stays empty through the refresh, `show_winbar()` brings it back, and `hide_indicators()`/`show_indicators()` switch the indicators off and on. **[run 2026-10-21]** recorded each throwing before step 8, the winbar machine missing and the indicator transitions unregistered. Decided 2026-10-21: build them (the author: "Build them"); they're reached by commands only, with no keymap entries (the author, 2026-10-24: "Commands only"). The bufferline pair is T123.
- T221 [char] (M11) `unregister_hook(name)` removes that hook from its own machine and nothing else, without throwing, and the name can be bound again. Before step 8 it called the class instead of the instance, threw, and the hook still ran (DESK:2483).
- T222 [char] (M1, D4) Hashing a file name runs no shell: `:e a` and `:e b` make no `vim.fn.system`, `io.popen` or `vim.system` call.
- T223 [char] (A1, A3) Going back into a window onto its current slot changes nothing: with window 1 on `⦉c⦊ [d] ⟦b⟧` and window 2 on `⦉d⦊ [e] ⟦-⟧`, `<C-w>p` three times leaves both windows' slots and notes as they were (A1's row X = A).
- T224 [char] (A1) A visit made in another window lands in that window, never the focused one: with window 1 focused on `⦉a⦊ [b] ⟦-⟧`, `:edit d.txt` run in window 2 through `win_execute` gives window 2 `⦉c⦊ [d] ⟦-⟧`, and window 1 keeps the focus, its buffer and its slots **[code]**. The history half is T19.
- T225 [char] (A2, M6) Windows born untracked never get a triquetra: a `:help` window and a `:split | terminal` window have none, after UI ticks and a jump out and back in. A `:copen` window is T217's second route.
- T226 [char] (A6, A7, A8) With no triquetra (a `:help` window), `<M-f>`, `<M-S-f>` and `<M-;><M-f>` each warn "Window with unregistered buffer.", raise nothing, switch nothing, and leave the other window's slots alone.
- T227 [char] (A7, P9) `<M-S-f>` on a closed ternary whose file is gone from disk says so and keeps the pointer: `:e a`, `:e b`, `:e c`, `:bdelete b.txt`, then b.txt deleted and `<M-S-f>` pressed straight away give a warning, no throw, and `⦉b⦊ [c] ⟦-⟧`. Before step 6 it said "Removed ternary file not found in filesystem" and set `t := nil`.
- T228 [char] (A11, D9) A restore switches no buffer and reopens nothing: at `⦉d⦊ [b] ⟦-⟧` with `dtm{b>a}` and a closed with `:bdelete`, `<M-;><M-r>` gives `⦉a⦊ [b] ⟦-⟧`, still showing b, with a unloaded and still on the closed stack; `<M-S-f>` then reopens a and takes it off the stack (a closed hash reopens when used).
- T229 [char] (A12) Any jump into another window cancels the cycle, floats and `:help` included: cycling from c with `⦉b⦊ [c] ⟦-⟧` to b, then a jump into a float, or `:help`, puts the window back on c with navigation `normal`, history attached, and the slots and the history order unchanged.
- T230 [char] (A13) A pick writes no secondary notes: from `⦉d⦊ [e] ⟦c⟧`, a pick of b (outside the slots) and then a pick of the ternary leave the secondary map as it was. The pick of the secondary is T73.
- T231 [char] (A14, Q7) `<M-;><M-f>` while cycling with the window already on the start says "Returned to cycling origin buffer" each time and changes nothing: the slots, the notes, the shown buffer and the order stay, and navigation stays `cycling`.
- T232 [char] (A17) `<M-,>` skips a previous window whose filetype is `neominimap`, as it does `minimap` (T94): it warns "No valid previous window to toggle to." and stays.
- T233 [char] (A18) With no triquetra (a `:help` window, while the other window's queue is `[a]on`), `<M-;>F` says "No triquetra found for current window." and opens no window.
- T234 [char] (A18, Q11) The pop-up refuses what cavediver doesn't track and keeps the good lines: from `[b,a]on`, the lines `a`, a blank line, the path of a loaded help file, `NONAME_999` and `b` save `[a,b]on`, with one error naming the help file and `NONAME_999`; the blank line is dropped without a word.
- T235 [char] (A18) A relative path in the primary queue window is resolved against the current directory, as `:e` does: the lines `./b.txt`, `a` save `[b,a]`, with no hole, and the pop-up redraws them as `b.txt`, `a.txt`. Today the line passes validation as typed, then its hash is looked up by the typed string, finds nothing, and leaves slot 1 empty, so the primary is lost and every loop over the queue sees it as empty (`window/routines.lua:277`; DESK:2477) **[run 2026-10-21]**. Decided 2026-10-21 (the author: "I thought we can type relative paths. In fact it's easier to type relative paths right?", then "Resolve it"). The pop-up keeps showing each entry by its shortest unique name, `b.txt`, or `src/b.txt` when another `b.txt` exists (the author, 2026-10-21: "Shortest name (today)").
- T236 [char] (A5) Closing another window first doesn't stop the pop-up's buffer going when the pop-up closes: `:vsplit`, `:close`, then `<M-;>F` and `:close` in the pop-up delete its buffer, as they do when no window was closed first. Today the first close uses up the `once` handler (`ui/hooks.lua:197`). And `<M-;>F` opens the pop-up again afterwards: today the left-over buffer keeps its name, and the next `<M-;>F` fails with "E95: Buffer with this name already exists" (`ui/routines.lua:188`); `q` and `<C-c>` don't hit this, since `close_window` deletes the buffer itself **[run 2026-10-21]**. Kept as a fix test, with the reopen check added (the author, 2026-10-21: "Keep + add reopen").
- T237 [char] (A19) With nothing left to land on, the window keeps Neovim's empty buffer and no `:enew` runs: `:e a`, `:bdelete a.txt` leave the window on the buffer Neovim put there, with no buffer added. A guard on the landing (A19, built in step 1).
- T238 [char] (A20) `:w new.txt` on a No Name buffer with text leaves no ghost entry on the closed stack: the old name isn't a file, so it's a move. Its notes follow too (the decided move, DESK:1924): a No Name buffer whose note says its ternary was a gives `new>a` after `:w new.txt`, with no dangling hash. **[run 2026-10-21]** recorded the ghost before the rename policy (DESK:2455): the closed stack got `NONAME_2`, `<M-S-w>` reopened it as a new No Name buffer holding a second copy of the saved text, and the note dangled as `?274b55>a`. Kept as a fix test, with the notes check added (the author, 2026-10-21: "Keep + notes follow").
- T239 [char] (A21) A slot pointing at an open buffer is kept whatever the disk says: at `⦉c⦊ [d] ⟦b⟧`, deleting b.txt and c.txt (both still open), UI ticks and a `cleanup_system` pass leave the slots and both registrations as they were.
- T240 [char] (A25) `disable()` clears the `cavediver` augroup and stops the timers, and afterwards `:e c` changes no slot and records nothing.
- T241 [char] (A26) The recorder never records raw keystrokes: text typed in insert mode (`QZQZQZ`) before the restore assertion fires doesn't show up as steps in the dump, whatever its format, file or scratch buffer.
- T242 [char] (bug (new), 2026-10-21) A tracked buffer wiped with `noautocmd` doesn't make the UI loop error: `:e a`, `:e b`, `:e c`, then `noautocmd bwipeout` of c give no hook failure over the next ticks. Without the repair, "Invalid buffer id" comes on every tick (`ui/routines.lua:1320`); wiping the ternary, or a buffer outside the slots, this way gives no error. **Decided (2026-10-21): the UI repairs it on the spot** (the author: "Keep, UI repairs now"): when a refresh finds a window showing a different buffer from its current slot, it re-points as cleanup would, like navigation (Q18), so within one refresh the window above reads `⦉c⦊ [b] ⟦-⟧` and nothing errors. Built in step 3: when any slot's registered buffer is no longer valid, the refresh runs `cleanup_system` at once (`ui/routines.lua:990-1007`); its stale pass forgets the dead number, and the heal re-points the window like navigation. **[run 2026-10-21]** recorded about 13 error notifications over the ~4 s until the cleanup tick repaired it, before the repair.
- T243 [char] (I23) The check runs wherever a slot changes under the current buffer (decided 2026-10-21), with the stale note planted: at graduation (`⦉b⦊ [c] ⟦-⟧` with `dsm{c>b}`, `<M-f>`), at the history fill (a fresh split on b with `dsm{b>a}`, `<M-f>` fills a), and at a session load (`⦉-⦊ [c] ⟦b⟧` with `dsm{c>b}`, saved and loaded). After each, the current buffer's note doesn't name its slot's occupant, and `<M-;><M-t>` doesn't throw.
- T244 [char] (S2) A load into fewer windows than were saved matches by what they show and drops the unmatched entry, with no error: two windows saved (`⦉c⦊ [d] ⟦-⟧` in the split, `⦉a⦊ [b] ⟦-⟧`) and one restored on b give `⦉a⦊ [b] ⟦-⟧`.
- T245 [char] (S2) A session file with a newer header gives "made by a newer cavediver" and is left alone: a file starting `CDV9` is unchanged after the load.
- T246 [char] (S2) A No Name buffer closed with `<M-.>` stays on the closed stack across a save and a load, and `<M-S-w>` then brings its text back. It held before save-as-closed was built (found 2026-10-21), and holds with it (step 4) and with the encrypted format, which reads the text from its own file only when it's reopened or the closed lists draw it (step 5).
- T247 [char] (I13, A21) A cleanup heal in another window doesn't switch the focused window or wipe what that window shows: window 2 on `⦉x⦊ [c] ⟦-⟧` shows an `acwrite` buffer, and `:bdelete c.txt` from window 1 leaves window 1 focused on b and window 2 on its buffer.
- T248 [char] (A12) With no cokeline, a cycle step raises nothing, steps through cavediver's own order (T171), and `<M-v>` still ends the cycle: navigation `normal`, history attached, and the pick lands where the step went (from `⦉a⦊ [b] ⟦-⟧`, `<M-n>` and `<M-v>` give `⦉b⦊ [a] ⟦-⟧`). **[run s21]** recorded the step doing nothing, before the fallback.
- T249 [char] (A1, A11) No note names its own buffer: random walks with T190's mix, in one window and across windows, check after every action that no map holds `X>X` or `X-swap>X`. The decided check drops a stale note when the note it would copy names the current buffer (A11), and runs after Q6's guard so two notes naming each other can't leave one behind (A1). A guard on the check (built in step 3).

**Decided rules not covered elsewhere (T250–T291)**

Each checks a rule the spec states as intended or decided that no earlier test checks, found by an audit of the tests against the spec (2026-10-21), and cites the rule. Where a state is set by hand, the test says so; where it reads a format the spec gives only as an example, it matches loosely.
- T250 [char] (P2, A1) The slotting happens after the event, not inside it: with `⦉-⦊ [a] ⟦-⟧`, a `BufEnter` autocmd of the user's, made after `setup()`, still sees `⦉-⦊ [a] ⟦-⟧` while `:e b` runs, and the window has `⦉a⦊ [b] ⟦-⟧` once the editor settles. Its purpose is tested too: a buffer that only becomes a terminal or help after its `BufEnter` (`:terminal`, `:help`) is never registered or slotted as a file. The author asked for both checks, 2026-10-21: "Both".
- T251 [char] (P3) The load matches windows by what they show, not by position: two windows saved (`⦉c⦊ [d] ⟦-⟧` in the split, listed first, and `⦉a⦊ [b] ⟦-⟧`) and restored the other way round (the first-listed window on b) give the window on b `⦉a⦊ [b] ⟦-⟧` and the window on d `⦉c⦊ [d] ⟦-⟧`.
- T252 [char] (P10, I17) History follows along and doesn't let go early: `:e a`, `:e b`, `:e c`, `:bdelete b.txt` leave b on the closed stack, still known, and its global history entry stays. Before step 6 the entry went as soon as b was unregistered. "Known" means cavediver still remembers the file (registered, e.g. on the closed stack), not that it's open; confirmed by the author, 2026-10-21: "Forgotten (as read)". The entry never reaches the bufferline: cokeline draws from listed buffers, and the ordered list skips hashes with no open buffer (`history/routines.lua:1062-1066`) **[run 2026-10-21]**.
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
- T268 [char] (A2) The winbar shows a visit, like `main.lua ← [<id> help]`: help shown in a's own window gives a winbar whose current piece reads, with highlights left out, `[<bufnr>] a.txt ← [<help's bufnr> help]`, and a terminal there `← [<its bufnr> terminal: <its command>]` (2026-10-24, the author's id and command). The format is locked (the author, 2026-10-21: "(a) within the winbar"): the current slot's piece becomes `[<bufnr>] <name> ← [<type>]`, with the ternary and secondary pieces kept around it; the brackets hold the `buftype` (`help`, `terminal`, `quickfix`), or the filetype when the `buftype` is empty or `acwrite`, so oil shows `[oil]` (M12).
- T269 [char] (A2, A6, A7) While visiting, `<M-f>` and `<M-S-f>` take the window back to its current slot first: at `⦉c⦊ [d] ⟦b⟧`, a `nofile` scratch shown in the window, then either key, gives d again with `⦉c⦊ [d] ⟦b⟧`.
- T270 [char] (A2) While visiting, the current slot may hold a closed buffer: at `⦉-⦊ [c] ⟦b⟧`, `:terminal` in the window, then `:bdelete c.txt`, leave `⦉-⦊ [c] ⟦b⟧` with c on the closed stack.
- T271 [char] (A19) A deleted buffer's window lands in the order ternary, secondary, primary, most recent, each on a route where Neovim's own pick (the window's jumplist) differs; Neovim closes every other window showing the buffer, so each is a window on its own, as in T111. Secondary: `:e a`, `:e b`, `:e c`, `<M-f>`, `<M-f>`, `<M-;><M-t>` give `⦉-⦊ [b] ⟦a⟧`, and `:bdelete b.txt` lands on a (Neovim: c). Primary: a split on c with empty slots, left alone by `:only` after the first window visited d and x, with its queue set to `[a]on` by hand, lands on a after `:bdelete c.txt` (Neovim: b). Most recent: the same with an empty queue lands on x (Neovim: b). Nothing to land on: `:e a`, a listed `nofile` scratch, `:bdelete a.txt`: Neovim shows the scratch, something other than its empty buffer, so `:enew` runs and the window shows a new empty buffer. "Most recent" follows `history_view`, as `<M-.>` does (the bufferline's order, built from the current view): under the window view it's the window's own history (the author, 2026-10-21: "Follow history_view"). A sub-case checks it under the window view, where the window lands on what it showed rather than on the last file touched elsewhere.
- T272 [char] (A20) The disk decides, the copy half: `:e a`, `:e b`, `:saveas g.txt` leave b.txt on disk, so the rename is a copy and b goes on the closed stack. Built in step 4 (A20). What `:saveas` does to the window is T106's.
- T273 [char] (A22) The stale pass keeps the history of the file it re-points: T113's state, and after the pass b's hash is still in the global history.
- T274 [char] (A23) `:CavediverTriquetra` and `:CavediverTriquetraVerbose` print `primary_buffer[1]` as "Primary buffer".
- T275 [char] (A26) Each "shouldn't happen" dumps: the fill assertion (T176's second half), "Duplicates detected" (T34's state), and a hook failure (a hook that throws, bound by hand to the history machine's updates) each leave a new file under `stdpath("state")/cavediver/` (the location T200 uses, decided 2026-10-21).
- T276 [char] (A26) A planted I1 break dumps at the next step: T203's layout, with c's secondary set by hand to b, its ternary, and `:e x` in the other window produces one dump.
- T277 [char] (A26) The error message says where the dump file is: T200's restore assertion, and the error or a message names the new file.
- T278 [char] (A26) Steps are tagged by cause: in T200's dump, the steps from keymaps and from events carry the tags `keymap` and `event` (T204 checks `load` and `timer`).
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
- T289 [char] (D25) The window machine goes: no `window/sm.lua`, no `SHOWING_` constants in `window/states.lua`, and nothing requires `cavediver.domains.window.sm`. A doc check, matched by text.
- T290 [char] (D18, D22, D24) STATUS and the old project `CLAUDE.md` live in `archive/`, and neither is at the repo root. A doc check. It holds today already, so it's [char]: a guard that stays true when the decided code lands.
- T291 [char] (D8, D13) README:15 ("Closed buffers reopen when accessed through relationships") and README:542 ("Every time you jump to secondary…") stay as written. A doc check, matched by text. It holds today already, so it's [char]: a guard that stays true when the decided code lands.

**The session file, S2 (T292–T332, T337–T342, T349–T391)**

Each checks a rule S2 states as decided, or a desk line S2 rests on, that no earlier test checks, found by mapping S2 against the tests (2026-10-21), and cites the rule. Most save in one process and load in a fresh one, passing the cwd as the session's name, as the README's wiring does (S1). Where S2 leaves a format or a mechanism open, the test matches loosely and says so.
- T292 [char] (S2 Contract and API; DESK:758, DESK:1074) `save_session()` and `load_session()` take no directory: with no argument the save writes a file whose name starts with `sha256(getcwd(-1, -1))`, and `load_session()` in a fresh process brings back `⦉c⦊ [d] ⟦b⟧`. A nameless save is named `sha256(directory)` alone, with no separator (decided 2026-10-21, the author: "directory alone"); the separator is only used with a name.
- T293 [char] (S2 Contract and API; DESK:758, DESK:1146) A whole-editor save is keyed by the global directory, not by a tab-local `:tcd`: `save_session('work')` from a tab with `:tcd sub` writes a file named after `sha256(getcwd(-1, -1) .. "\n" .. 'work')`, and none after the tab's directory.
- T294 [char] (S2 Contract and API, Tab sessions; DESK:949, DESK:1074) A tab session is keyed by its tab's directory: `save_session('t', { tab = … })` from a tab with `:tcd sub` writes a file whose name starts with `sha256(<project>/sub .. "\n" .. 't')`. The spec makes the scope's directory the key and names the file `sha256(directory .. "\n" .. name)` (T255); that the name takes the tab's directory is read from the two together.
- T295 [char] (S2 Loading; DESK:1284) A load from idle goes `idle → bare → loading`: after a save, `load_session` adds `idle->bare` and then `bare->loading` to the storage machine's history.
- T296 [char] (S2 Loading; DESK:1282, DESK:1284) Every domain tears its own state down at `idle → bare`: saved at `⦉b⦊ [c] ⟦-⟧`, then `:e d`, `:e x`, `:bdelete d.txt` and a cycle step left open, the window put back on c and a load give `⦉b⦊ [c] ⟦-⟧`, a closed stack holding d once, from the file, since d's close was written into it as it happened (records on every change), navigation `normal`, history attached, and x unregistered (T314). Before records were written on every change, the stack came back empty.
- T297 [char] (S2 Loading; DESK:1286, DESK:1288) The repeat flag is re-armed by `vim.schedule`: three `load_session` calls in one batch, a 30 ms wait, then a fourth call give two loads, and every call returns normally. With T145, this tells `vim.schedule` apart from a timer and from no flag.
- T298 [char] (S2 Loading; DESK:794) Cavediver loads again by itself after Neovim's `:restart` session, ignoring the flag: two windows saved at `⦉c⦊ [d] ⟦-⟧` and `⦉a⦊ [b] ⟦-⟧`, a startup load, and then the restart session sourced in the same batch give two loads and the saved slots. `:restart` can't run inside a test's child, so the child is started with `__NVIM_STARTREASON=restart` in its environment, an undocumented Neovim 0.12 internal that sets `v:startreason`, and the restart session is a `:mksession!` file named `restart_session_…`. **[desk]** recorded the scramble in tmux, without the reload: the restart session's window came back with the wrong ternary.
- T299 [char] (S2 Loading; DESK:1161) One post-restore callback replaces the 210 ms delay: the load makes no timer, and 30 ms after it `last_valid_window` is the current window and the bufferline order is what it still is 300 ms later. That `require` starts no probe is T254.
- T300 [char] (S2 Loading; DESK:1286) A later reload brings no No Name text back twice: with a No Name text open in the ternary at save, a load and then a second load leave exactly one buffer holding it.
- T339 [char] (S2 Loading, Contents; DESK:1286, DESK:1440) A reload in the same process keeps the slots of a window showing an open No Name buffer, with no error: at `⦉b⦊ [N] ⟦-⟧` with N a No Name text shown in the window, a save and then a load in the same process give `⦉b⦊ [N] ⟦-⟧` again, with one buffer holding the text; and a split that isn't focused, at `⦉c⦊ [N] ⟦-⟧` with N an empty No Name buffer, keeps its slots, and so does the focused window. The load knows a No Name buffer still open by its id, and derives the windows' display caches only once the texts are reopened (S1 Load). Added with save-as-closed, 2026-10-23: **[run 2026-10-23]** recorded the ternary lost, `⦉-⦊ [N] ⟦-⟧`, and then, with the window matched before N was registered, the load stopping on "Impossible state: current_bufnr is nil" and the focused window losing its ternary.
- T301 [char] (S2 The file; DESK:1554) The main file starts with the clear version header `CDV1`.
- T302 [char] (S2 The file; DESK:1541) Nothing in the session files is in clear: with b closed and a No Name text open, no file under `session_dir` parses as JSON or holds the project's directory, a file name or the No Name text.
- T303 [char] (S2 The file; DESK:1541) The file goes through `libcrypto`, not a command: a save, and a load in a fresh process, make no `vim.fn.system`, `io.popen` or `vim.system` call. Hashing on `:e` is T222.
- T304 [char] (S2 The file; DESK:1555) Every write is atomic: a second save puts a new file in place by renaming it over the first (the main file's inode changes), and leaves no other regular file in `session_dir`.
- T305 [char] (S2 The file; DESK:1547, DESK:1555, DESK:1636) One file per No Name text sits in `<main>.d/`, besides the trail's pages, which end in `.trail` (A27), each in mode 0600: a No Name text closed with `<M-.>`, another open, and an empty one shown give exactly two files there, `rw-------` with a umask of 022. The directory is found as the one in `session_dir` whose name ends in `.d`.
- T306 [char] (S2 The file; DESK:1547, DESK:1548) Scratch files are named per version, written only when they change, and swept once nothing references them: a second save with the text unchanged keeps the same file and bytes; after the text changes, the next save leaves one file under a new name.
- T307 [char] (S2 The file; DESK:1548) The main file is the commit point, in two cases put together from the files of two saves (v1, then v2). A crash before the main file lands (the first main file, with both scratch files beside it) loads with the v1 text back and not v2; a crash after it (v1's scratch left beside v2's) is swept by the next save. The process is killed before the first case's files are put together, as a crash fires no `VimLeavePre`: a quit writes its records, and would write them over the files (found with the records writing, 2026-10-23).
- T308 [char] (S2 The file; DESK:1548) A damaged scratch file loses one scratch, not the session: with two open No Name texts saved and one byte flipped in one scratch file, the load gives back `⦉a⦊ [b] ⟦-⟧` and exactly one of the two texts.
- T341 [char] (S2 The file, Checks; DESK:1548) A closed No Name text that can't be read at a save leaves the closed stack, and the next load goes through: a No Name text closed with `<M-.>` and saved, a fresh process loads it (it's held unread), the session's files are removed, and a save (a new salt, so a new key) can't read it; a third process loads with no error and no No Name entry on the closed stack. Added with step 5, 2026-10-23: **[run 2026-10-23]** recorded, without the filter in `commit_session`, the third load stopping on "This is impossible. Noname content must be created for this closed No Name buffer."
- T472 [char] (S2 The file; DESK:1547) An unchanged No Name text keeps its file in every editor: a No Name text closed with `<M-.>` is saved, then five fresh editors each load the session, draw the closed lists, which reads the text, and save with the text unchanged, and the session's one text file keeps its name throughout. An open text comes back under a fresh id at each load (M5), so its file's name changes with its hash.
- T473 [char] (S2 The file, Contents; DESK:1548) A closed No Name text read from another session's file is kept when that file goes: a text closed with `<M-.>` and saved under A, held unread in a fresh editor that loads A and saves B, then A's files removed; B's next save says nothing of an integrity check, and a fresh editor loading B reopens the text with `<M-S-w>`.
- T474 [char] (S2 Save-as-closed) An open No Name text shown only in another tab keeps its cursor: a text of three lines in a second tab, its cursor on line 3, column 2, saved from the first tab; a fresh editor's load reopens it, and shown in a window it has its cursor there.
- T338 [char] (S2 The file; DESK:1543, DESK:1112-1114) The migration script converts an old file it finds through resession's session list, and a load reads it: an old file made by hand in the format from before encryption (paths XOR'd with the cwd and base64-encoded, raw hashes for open buffers, the six-field window entry, b closed) and a resession session made by hand for the project, in the test run's own data directory; `nvim --clean -l scripts/migrate_sessions.lua` reports one session converted; a fresh process that restores a, c and d and loads by the session's name gets `⦉c⦊ [d] ⟦b⟧` with b on the closed stack; the old file is kept as `<old>.json.migrated`, and a second run reports it already converted. Added with the script, 2026-10-23.
- T340 [char] (S2 Checks; DESK:1683) A load that finds only a file named the old way points to the migration script: with only `sha256(cwd .. "\n")`'s first 32 hex characters plus `.json` in `session_dir`, the load gives a message naming the migration script, starts fresh (`⦉-⦊ [a] ⟦-⟧`) and leaves the old file where it is. The author, 2026-10-23: "Point to the script (Recommended)". Added with the script, 2026-10-23.
- T342 [char] (S2 The file; DESK:1554) The migration script reports a session saved fresh before it ran, and `--replace` converts over it: T338's old file and resession session, then a process on the encrypted format loads (a fresh start, `⦉-⦊ [d] ⟦-⟧`) and saves; the script reports one session with a file in the new format already and converts nothing; with `--replace` it converts it, and a fresh process loads `⦉c⦊ [d] ⟦b⟧`. Added with the script, 2026-10-23: **[run 2026-10-23]** recorded the script, before the `.migrated` marker, counting that session as already converted and leaving it unconverted.
- T309 [char] (S2 The file; DESK:1549) No count limit: 150 files closed with `:bdelete` are all on the closed stack after a save and a load in a fresh process. It held before the encrypted format and holds with it.
- T310 [char] (S2 Checks; DESK:1541, DESK:1683, DESK:1685) A file only decrypts in its own directory: a file saved as `work` in one project, copied to the name `work` takes in a second project (`sha256(directory .. "\n" .. 'work')` with that project's directory), gives "failed its integrity check (edited or corrupted)" there and a fresh start, `⦉-⦊ [b] ⟦-⟧` with an empty closed stack. Matched on "integrity check". The edited byte is T144.
- T311 [char] (S2 Checks; DESK:1683) A cut-off file, the saved file cut to half its length, gives the integrity notification and a fresh start, as T144's edited byte does.
- T312 [char] (S2 Checks; DESK:1682) A file with no header, plain JSON in the format from before step 5 at the main file's name, gives a message naming the migration script at load. Matched on "migration script". The newer header is T245.
- T313 [char] (S2 Checks; DESK:1689) A reference that resolves to nothing at load is kept, says so when it's used, and works again when its file comes back: saved at `⦉c⦊ [d] ⟦b⟧`, with b.txt deleted and not restored, the load keeps `⦉c⦊ [d] ⟦b⟧`; `<M-f>` gives a message, raises nothing and changes no slot; with b.txt written back, `<M-f>` gives `⦉c⦊ [b] ⟦d⟧`. The load closes b as it does in T337, and cleanup keeps the closed slot whatever the disk says (A21). Before step 6 the secondary came back empty: cleanup pruned a closed slot whose file was gone from disk. Found with step 6, a bug in the test itself: it deleted b.txt before the second start, but each start of the test's child writes the project's files again, so b.txt was back by the load. It's deleted after the start.
- T314 [char] (S2 Contents; DESK:1432, DESK:1436) A restored buffer the file doesn't know waits for `BufEnter`: x, loaded and hidden at the load but never saved, isn't registered by the load, and is once `:e x` enters it.
- T337 [char] (S2 Contents; DESK:1943) A reference whose buffer the manager doesn't restore is kept, and reopens when used: saved at `⦉c⦊ [d] ⟦b⟧`, a fresh process that restores a, c and d but not b (b.txt stays on disk), loads and runs a `cleanup_system` pass has `⦉c⦊ [d] ⟦b⟧`, with b unregistered; `<M-f>` then gives `⦉c⦊ [b] ⟦d⟧`, showing b. The load puts b on the closed stack, so cleanup keeps the slot as any closed slot (S1, A21). Added with step 4's `paths` table, 2026-10-23.
- T315 [char] (S2 Contents; DESK:1440) Windows on the same file keep their saved order, and a window that matches nothing starts fresh: saved as `⦉c⦊ [b] ⟦-⟧` (the split, listed first) and `⦉a⦊ [b] ⟦-⟧`, and restored behind a new first-listed window on e, the windows read `⦉-⦊ [e] ⟦-⟧`, `⦉c⦊ [b] ⟦-⟧` and `⦉a⦊ [b] ⟦-⟧`.
- T316 [char] (S2 Save-as-closed; DESK:1634, DESK:2299) A No Name buffer reopened at load gets a fresh id, and every reference to its old hash is renamed: a No Name text in the ternary (`:e a`, `:enew` with text, `:e b`) comes back as the ternary under a hash that differs from the saved one, and no slot, queue, note or history entry keeps the old hash.
- T317 [char] (S2 Errors and drift; DESK:1070) With two editors on one project, the last writer wins: both save in turn without an error, and a fresh process loads the second one's `⦉c⦊ [d] ⟦-⟧`. It held before the encrypted format and holds with it.
- T318 [char] (S2 Tab sessions; DESK:949) A tab session's file says its scope, and its load works on the current tab only: a session saved with `{ tab = … }` from a tab at `⦉c⦊ [d] ⟦-⟧`, loaded by name alone into a second tab of a fresh process, gives that tab `⦉c⦊ [d] ⟦-⟧` and leaves the first tab at `⦉x⦊ [t] ⟦-⟧`; and so does the same load from `idle`, after a whole-editor save in that process. Before step 7 only the load from `bare` held, by another route: nothing is torn down in a fresh process, and the first tab's window on t matched no entry and kept its triquetra; a load from `idle` tore every tab down first.
- T319 [char] (S2 Tab sessions; DESK:952) Closes go to the pool of the tab they happen in, and `<M-S-w>` reopens from the current tab's: in T318's state, after `:bdelete x.txt` in the first tab and then `:bdelete c.txt` in the session's tab, `<M-S-w>` in the first tab reopens x and in the session's tab c. Before step 7 the first tab got c.
- T320 [char] (S2 Tab sessions; DESK:951, DESK:954) The session's tab ranks its own visits first, and a buffer belongs to every tab that visited it: in T318's state, `:e a`, `:e b` in the first tab and `:e a` in the session's tab leave a, c and d as the first three in the session tab's bufferline order. Only membership is checked; the spec doesn't fix the order inside the overlay.
- T321 [char] (S2 Tab sessions; DESK:955) Saves are snapshots: in T318's state, with x closed in the first tab, c in the session's tab and e in the first tab, a second apart, a whole-editor `save_session()` writes the lists into its file merged by close time, oldest first, x, c, e, and leaves them apart in memory (`<M-S-w>` in the first tab reopens e, then x); with e and x open again, the file follows, so a fresh process loading it has c alone on its list. Found with step 7, a bug in the test itself: it closed e while the first tab's only window showed it, and `:bdelete` of what a tab's only window shows closes that tab, so the window the presses were read from was gone. The window goes back to t before e is closed.
- T322 [char] (S2 Tab sessions; DESK:956, the author's 2026-10-23 answer) A tab session's tab closed with nothing wired to save it writes the session's records itself, and nothing is kept without a tab: in T318's state, `:bdelete c.txt` in the session's tab, then `:tabclose` with no `TabClosedPre` hook calling `save_session`, gives no notice, and the tab session loaded into a new tab afterwards, with d restored and c not, has c on its list (`<M-S-w>` there reopens c). Decided 2026-10-19 as a list kept with no tab and a notice each time; the author, 2026-10-23: "this shouldn't happen at all", then "Yes, that's it" to cavediver writing the records as the tab closes.
- T323 [char] (S2 Tab sessions, Errors and drift; DESK:957, DESK:1068) A tab-session save refreshes the unnamed session's records and leaves its references: with the whole editor saved by `save_session()` at `⦉x⦊ [t] ⟦-⟧`, the tab session loaded into a second tab, x closed and e visited in the first tab, and the tab session saved, the whole editor's file holds x on its closed stack, and a fresh process's `load_session()` has x on the closed stack and still `⦉x⦊ [t] ⟦-⟧`. Before step 7 the fresh load passed by another route, x not being restored and so closed by the load (T337), while the whole editor's file didn't have x: its records weren't refreshed.
- T332 [char] (S2 Tab sessions; DESK:951, DESK:954, DESK:1640) A pool holds its own No Name texts: in T318's state, a No Name text left in the session's tab's history and another left in the first tab's, a save of the tab session alone, and a load of it into a second tab of a fresh process bring back the session tab's text and not the first tab's. Before step 7 a save wrote every open, non-empty No Name text, whatever tab it was in, so the tab session's file held both.
- T349 [char] (S2 Tab sessions, Q15) A close goes back on the pool of every tab that visited the file: in T318's state, `:e a` then `:e d` in the session's tab, then `:bdelete x.txt`, `:e a` and `:bdelete a.txt` in the first tab; `<M-S-w>` in the session's tab reopens a, and a second press there finds nothing more: x, visited and closed in the first tab only, is on the first tab's pool alone. Answered by the author, 2026-10-23: "Both".
- T350 [char] (S2 Tab sessions, Q15) A file reopened from one pool goes back on the pools it came out of when it's closed again: in T318's state, in the session's tab `:vsplit`, `:e e` there, `:close` (the split's history goes with it) and `:bdelete e.txt`, which closes e into the session's pool; then `:bdelete x.txt`, `:e e` and `:bdelete e.txt` in the first tab; `<M-S-w>` in the session's tab reopens e, and a second press there finds nothing more (x is on the first tab's pool alone). No window of the session's tab has e in its history, so only the pool it came out of brings it back.
- T351 [char] (S2 Tab sessions; DESK:956) A tab session's tab closed with its save wired gives no notice: in T318's state, with a `TabClosedPre` autocmd that saves the tab session (`save_session('t', { tab = … })`), `:bdelete c.txt` in the session's tab, then `:tabclose`, gives no notification, and the tab session loaded into a new tab afterwards, with d restored and c not, has c on its pool (`<M-S-w>` there reopens c). The wired save and cavediver's own write as the tab closes give no notice together.
- T352 [char] (S2 Contract and API, Tab sessions; DESK:949) A tab session saved from a tab with a `:tcd` of its own is found at load in that tab: saved as `t` from a tab with `:tcd sub` at `⦉c⦊ [d] ⟦-⟧`, and loaded by name into a new tab of a fresh process whose `:tcd` is `sub` too, as the manager restores a tab's directory, that tab gets `⦉c⦊ [d] ⟦-⟧`.
- T353 [char] (S1, I22) After a load from idle, closes and `<M-S-w>` use one closed stack: saved at `⦉b⦊ [c] ⟦-⟧`, loaded again in the same process, then `:e a`, `:bdelete c.txt` and `<M-S-w>` reopen c.
- T354 [char] (S2 Contract and API; the author's 2026-10-23 answer, "A hint in the call") A tab session with no cavediver file, loaded with the hint, starts only its tab fresh: in T318's first tab at `⦉x⦊ [t] ⟦-⟧`, after a whole-editor save in that process, a session `u` that has no file, loaded into a second tab with `load_session('u', { tab = … })`, gives that tab `⦉-⦊ [d] ⟦-⟧`, leaves the first tab at `⦉x⦊ [t] ⟦-⟧` and its closed list as it was, and isn't taken as the whole editor's session: the next tab-session save gives no warning.
- T355 [char] (S2 Contract and API) A file's scope wins over the hint: a whole-editor file loaded with `{ tab = … }` loads as a whole-editor session. The hint is read (T354, T367), and the file's scope wins over it.
- T356 [char] (S2 Tab sessions, Checks) When a tab session's records can't be written as its tab closes, its list is kept with no tab and a warning says so: T322's route with the session directory read-only. It's the failure path of T322's write; T322 tells it apart from 2bc6330's interim, under which every unsaved tab close kept its list with a warning.
- T357 [char] (S2 Tab sessions; DESK:954) A session loaded into another tab while it's open takes its list along, what's in memory and the file filling in under it: with `t` loaded in a second tab, e visited and closed there (e isn't in `t`'s saved slots), and `t` loaded into a third tab with d restored, `<M-S-w>` there reopens e. Written as "shares its list" while two tabs could share a session; under one tab at a time (T369) the list goes with the session to the third tab, and the check holds as it was.
- T358 [char] (S2 Errors and drift; the author's 2026-10-23 answer, "Yes, all three moments") Quitting writes every known session's records: the whole editor saved at `⦉x⦊ [t] ⟦-⟧`, the tab session loaded into a second tab and its tab closed, then in the first tab a No Name buffer holding `note`; a quit with no session saved, and a fresh process's `load_session()` reopens the No Name text; and a tab session's tab closed in the same batch as the quit, before its write's tick comes, has its records written by the quit: in T318's state, `:e e`, `:e d` in the session's tab, then `:bdelete e.txt`, `:tabclose`, the quit's `VimLeavePre` and the process killed, all in one call, and the tab session loaded into a new tab of a fresh process has e on its list (e isn't in its saved slots, so only its list brings e back).
- T359 [char] (S2 Errors and drift; the author's 2026-10-23 answer, "On every change") A crash loses no close: after a whole-editor save, `:bdelete b.txt`, a second's wait, and the process killed (no `VimLeavePre`), a fresh process's load has b on its closed list.
- T360 [char] (S2 Errors and drift) A load cancels a write still pending: a close, then at once a load from idle of another session (the manager's teardown closing the outgoing buffers), and the outgoing session's file has the close and none of the teardown's.
- T361 [char] (S2 Errors and drift) Records never make a file: closes in a session that was never saved leave `session_dir` without a session file. Records are written on every change (T359), and the write never makes a file.
- T362 [char] (S2 Errors and drift) Records aren't written into a session the editor has moved away from: after a save in one project, the global directory changed to another with no load, a close there leaves the first project's file as it was. It's the records writing's `still_there` guard.
- T363 [char] (S2 The file) A session's key is kept by its directory and salt: another process saves the session again (a new salt after a fresh start), then this process closes a file; the next load in a fresh process goes through, with that close.
- T364 [char] (S2 Errors and drift, A25) `disable()` stops the writes: after `disable()`, a close leaves the session's file as it was: the write the close set off never lands.
- T365 [char] (S2 Errors and drift, Tab sessions) A whole-editor switch keeps the manager's teardown out of an open tab session's file: with `t` open in a second tab, the manager's switch, all in one go (every buffer deleted with events on, the other tabs closed, then a load of another session), leaves `t`'s file with none of the teardown's closes.
- T366 [char] (S2 Tab sessions; the author's 2026-10-23 answer, "Carry slot entries") A tab saved as another session writes the session it leaves, lets its list go when no tab is left in it, and carries the closed files its slots hold: in T318's state, `:bdelete c.txt` in the session's tab (`⦉c⦊ [d] ⟦-⟧`, c closed in the ternary), then `save_session('u', { tab = … })` from that tab and a cleanup pass leave `⦉c⦊ [d] ⟦-⟧`, c on u's list and no list with no tab; and `t` loaded into a new tab afterwards, with d restored and c not, has c on its list. The author: "when you do save_as, you are saving whatever you have right now in another name. You have c as a ternary, so save that as well under the banner of u as well."
- T367 [char] (S2 Contract and API) The hint's tab is the tab the load works on, wherever the focus is: from the first tab at `⦉x⦊ [t] ⟦-⟧`, after a whole-editor save, `load_session('u', { tab = <a second tab> })` with no file starts that tab fresh, `⦉-⦊ [d] ⟦-⟧`, and `load_session('t', { tab = <a third tab> })` gives that tab t's `⦉c⦊ [d] ⟦-⟧`; the first tab keeps `⦉x⦊ [t] ⟦-⟧` and its closed list throughout.
- T368 [char] (S2 Tab sessions; the author's 2026-10-23 answers, "Carry a copy" twice) A tab saved under a session it wasn't in carries the closed files its slots hold onto that session's list, and the list it leaves keeps its copy while a tab is still in it. Case A, a tab in no session saved as one for the first time: `:e a`, `:e b`, `:e c`, `:bdelete b.txt` (`⦉b⦊ [c] ⟦-⟧`, b closed on the editor's list), then `save_session('notes', { tab = … })`: notes' list and the editor's list both hold b, and `<M-S-w>` there reopens b. Case B, a tab whose session another tab took: in T318's state, `t` loaded into a third tab too, so the second tab holds `t_DETACHED` (T369), `:bdelete c.txt` in the second, then `save_session('u', { tab = … })` from it: u's list and t's, in the third tab, both hold c, the detached list, left with no tab and with no whole-editor file to go into, stays in memory with no tab (T382), and `<M-S-w>` in the second tab reopens c. The author's case-B answer, "Carry a copy" for a tab saved as a new session while its old one is open in another tab, has no route of its own since a session is in one tab at a time (T369); this is the route its setup takes now.
- T369 [char] (S2 Tab sessions; the author's 2026-10-23 answers, "One tab, with carry" and "A DETACHED list") A tab session is in one tab at a time, and the tab it leaves keeps a detached list of its own: in T318's state, `:e x`, `:e c`, `:e d` and then `:bdelete x.txt` and `:bdelete c.txt` in the session's tab (`⦉c⦊ [d] ⟦-⟧`, t's list x, c), then `t` loaded into a third tab with d restored: the second tab's list is `t_DETACHED`, holding x and c, and the third tab's is t's, holding x and c.
- T378 [char] (S2 Tab sessions; the one-tab rule, as resession's `save_tab` does) A save of a tab as a session that's open in another tab takes it from that tab: in T318's state, a third tab saved as `t` (`save_session('t', { tab = … })`) leaves the second tab's list `t_DETACHED`, holding what t's held.
- T379 [char] (S2 Tab sessions) A detached tab is a tab like a session's: in T369's state, `:e e`, `:e d` and `:bdelete e.txt` in the second tab put e on `t_DETACHED` and not on t's list, and `<M-S-w>` there reopens e.
- T380 [char] (S2 Tab sessions, S1 Save and Load; the author: "it will be saved on editor's cavediver file", "It is matched by the tab resession file as well") A whole-editor save writes a detached list apart from the closed list, and a whole-editor load brings it back to its tab: in T379's state with e closed again, `save_session()`, then a fresh process restoring the three tabs as they were and loading the whole editor: the file's `closed` doesn't hold e and its `detached` does, and the second tab's list is `t_DETACHED`, where `<M-S-w>` reopens e.
- T381 [char] (S2 Tab sessions; the author: "File only, piling up") A detached list left with no tab goes into the whole editor's file and leaves memory, and stays there: in T379's state with e closed again and a whole-editor save before it, `:tabclose` of the second tab leaves no `t_DETACHED` in memory and the whole editor's file holding it with e and e's path; a later whole-editor save keeps it there, with no windows.
- T382 [char] (S2 Tab sessions) With no whole-editor file, a detached list left with no tab stays in memory with no tab, and a warning says so: T379's state, where no whole-editor save ran, and `:tabclose` of the second tab.
- T383 [char] (S2 Tab sessions) A second detach of a session is numbered: in T369's state, `t` loaded into a fourth tab leaves the third tab's list `t_DETACHED_2`.
- T384 [char] (S2 Tab sessions, Closed-stack picker; the author's case 8: "Only its t_DETACHED tab", "Every list", "Pushed out, as the rules say") t loaded back into the tab that holds `t_DETACHED` opens the closed lists at once: in T369's state, `t` loaded into the second tab opens them once the load settles, every list shown and the cursor on `≡t_DETACHED`; the second tab's list is t's, and the third tab, which t left, holds `t_DETACHED_2`.
- T385 [char] (S2 Tab sessions, Closed-stack picker) Merging in case 8's picker ends the detached list: from T384's picker, with a whole-editor save before the load, `t_DETACHED`'s lines moved under `≡t`, `:w` and `q` leave no `t_DETACHED` in memory or in the whole editor's file.
- T386 [char] (S2 Tab sessions, Closed-stack picker; the author: "File only, piling up") Leaving case 8's picker with `t_DETACHED` as it was sends it into the whole editor's file: T385's route without the merge, `q` at once, and `t_DETACHED` is out of memory and in the file.
- T387 [char] (S2 Tab sessions; the author: "Only its t_DETACHED tab") t loaded into any other tab opens nothing: in T369's state, `t` loaded into a fourth tab opens no closed lists. It holds before case 8's picker is built too; it's the guard that the picker opens for the detached tab alone.
- T388 [char] (S2 Closed-stack picker; the author: "File only, piling up", "the picker reaches them") A list in the whole editor's file alone shows in the picker, its header marked "in the file", and is edited there: in T381's state, the picker shows `≡t_DETACHED` with e's line and "in the file"; e's line deleted and `:w` leave the file with no `t_DETACHED`.
- T389 [char] (S2 Closed-stack picker) A line moved out of a list in the file alone lands on the list it's moved under: in T381's state, e's line moved under `≡editor` and `:w` leave the file with no `t_DETACHED`, and `<M-S-w>` in the first tab reopens e.
- T390 [char] (S2 Closed-stack picker) An edit to a list in the file alone survives `<CR>` on another of its entries: with `t_DETACHED` in the file alone holding e and b, b's line deleted and `<CR>` on e's line, unsaved, write the edit first, reopen e and leave the file with no `t_DETACHED`: b doesn't come back.
- T391 [char] (S2 Closed-stack picker, Errors and drift) An edit to a list in the file alone that can't be written says so and stays on screen: in T381's state with the session directory read-only, e's line deleted and `:w` give a warning, and the closed lists' buffer stays modified.
- T324 [char] (S2 Oil; DESK:2087, DESK:2093) An oil window comes back as oil, with `vim.w.oil_original_buffer` set from its current slot: a window at `⦉a⦊ [b] ⟦-⟧` showing an oil listing at save, restored on the listing, still shows it after the load, keeps `⦉a⦊ [b] ⟦-⟧`, and has `oil_original_buffer` set to b's buffer, with the oil buffer itself unregistered. Oil is stood in for by an `acwrite` buffer named `oil://<project>/`, with filetype `oil`. Built in step 4; while the save still switched oil windows to their current slot, the window came back with no triquetra.
- T325 [char] (S2 Closed-stack picker; DESK:2367, DESK:2371, DESK:2374) `:CavediverClosed` opens an editable buffer that lists the closed entries, newest first, and no open buffer: with b and then c closed, the buffer is modifiable, a line naming c.txt sits above one naming b.txt, and no line names a.txt or d.txt. Entries are found by the file name they hold, since the spec gives no format for them. Built in step 7 (7b).
- T326 [char] (S2 Closed-stack picker; DESK:2368) A No Name entry shows its first line in quotes, its filetype and its close time: a No Name buffer holding `TODO: fix the thing` with filetype lua, closed with `<M-.>`, is listed on a line holding `[No Name]`, `"TODO: fix the`, `lua` and a digit, as it shows: its text and the virtual text drawn on it (the decoration is virtual text, decided 2026-10-23). The format is an example, so the pieces are matched on their own.
- T327 [char] (S2 Closed-stack picker; DESK:2371) Reordering the picker's lines reorders the stack: with c on top of b, swapping their lines and `:w` make `<M-S-w>` in the window you came from reopen b.
- T328 [char] (S2 Closed-stack picker; DESK:2372) `<CR>` reopens the entry under the cursor in the window you came from: on b's line it puts b in that window and leaves c alone on the stack. `<CR>` is typed with `feedkeys`, since the picker's mapping isn't known in advance.
- T329 [char] (S2 Closed-stack picker; DESK:2370) Deleting a file's line and `:w` discard it: with b and c closed, deleting c's line leaves b alone on the stack.
- T330 [char] (S2 Closed-stack picker, Tab sessions; DESK:2367) Each pool is a header with its closed entries under it: in T318's state, with x closed in the first tab and c in the session's tab, the picker's first line is a header, and a header sits between the lines naming x and c. A header is any non-empty line that names neither entry.
- T331 [char] (S2 Closed-stack picker, Tab sessions; DESK:2369) Pools merge by moving lines: in T330's state, c's line moved under x's and `:w` make `<M-S-w>` in the first tab reopen x and then c, and leave nothing for `<M-S-w>` in the session's tab.
- T370 [char] (S2 Closed-stack picker; the author's 2026-10-23 key grammar) The picker's keys: with b and c closed, `gf` on b's line reopens b in the window you came from and leaves the picker open, with c still listed; `za` on a header folds its list; `L` and `H` go to the next and the previous header; `q` writes and leaves.
- T371 [char] (S2 Closed-stack picker, I22; T162's pool half) The picker's merge keeps one copy, the newer: in T330's state, with x also on the session's list, its close time there set by hand a minute after the first tab's, the session's x line moved under the first tab's header, beside that list's own x line, and `:w`, leave the first tab's list with x once, at the newer close time, and the session's list without x.
- T372 [char] (S2 Closed-stack picker, I22) A `:w` with no edits changes nothing: in T330's state, with x on both lists at different close times (set by hand), `:w` with the lines as drawn leaves every list's entries and close times as they were.
- T373 [char] (S2 Closed-stack picker, M14) The picker shows a missing file's tag: b closed and tagged `feature` (`history.data.missing`, set by hand), b's line shows `⎇feature`.
- T374 [char] (S2 Closed-stack picker; the author's "Glyphs, with an ASCII set") With `glyphs = { set = "ascii" }` in the config, the picker draws no glyph outside ASCII: its lines and its virtual text are ASCII alone.
- T375 [char] (S2 Closed-stack picker; DESK:2374) The keymap: `<M-;>W` opens the picker, as `:CavediverClosed` does, and `keymaps.open_closed_lists` names it.
- T376 [char] (S2 Closed-stack picker; DESK:2370) Discarding a No Name entry asks first: a No Name text closed with `<M-.>`, its line deleted and `:w` with the question answered "Keep" leaves it on the list; answered "Discard", it's gone, text and all.
- T377 [char] (S2 Closed-stack picker; DESK:2373) A typed header that names no list refuses the write: with b and c closed, a line `≡nowhere` added and `:w` give an error naming it, and every list stays as it was.

**The ledger (A27, A26; T392–T445)**

Added with the ledger, 2026-10-24, from A27, and built in step 8 with it: T392–T402 with its first piece, T403–T419 with its moves, T420–T424 with the trail's pages, T425–T434 with its day view, T435–T445 with `za` into the ring, the search, `*`, `gf` and the formatters. The records are read through `require('cavediver').ledger`: `steps()`, the ring, oldest first, and `trail()`, today's steps that made moves. A row is written `⦉t⦊ [c] ⟦s⟧` with each file's name as the step captured it.
- T392 [char] (A27, A26) The ring keeps the last N steps, N from `ledger.ring`, 1,000 by default: with `ledger = { ring = 5 }`, `:e a`, `:e b` and eight `<M-f>` leave five steps, the last five `<M-f>` steps, oldest first.
- T393 [char] (A27) A keymap step holds its cause, its trigger, its window, and the window's rows before and after with the primary queue and notes: `:e a`, `:e b`, `:e c`, `<M-f>` give a last step with cause `keymap`, trigger `<M-f>`, that window, `⦉b.txt⦊ [c.txt] ⟦-⟧` with b's ternary note naming a before, and `⦉-⦊ [c.txt] ⟦b.txt⟧` with b's secondary note naming a after (graduation's copy, Q3).
- T394 [char] (A27) A key's follow-ups land on its step: `:e a`, `:e b`, `:e c`, then `<M-.>` give one step, `<M-.>`, holding the move "closed" on c.txt, onto `editor`, dim (bookkeeping), with the events it set off, `BufEnter b.txt` and `BufDelete c.txt`, listed under it; neither event begins a step of its own, though the delete waits for the editor to settle (A15).
- T395 [char] (A27) An event with no step open begins its own: after T394's keys and a settle, `:e d` gives a new step, cause `event`, trigger `BufEnter d.txt`, `⦉c.txt⦊ [b.txt] ⟦-⟧` before and `⦉b.txt⦊ [d.txt] ⟦-⟧` after.
- T396 [char] (A27) A command typed on the command line is a keymap step under its text, never its keys: `:e a`, `:e b`, `:e c`, then `:bdelete c.txt` typed and entered give a step with cause `command` and trigger `:bdelete c.txt`, holding c's close first, then the window's landing.
- T396 [char] (A27) A path typed on the command line is kept as its last part: `:e <project>/b.txt` typed and entered gives the trigger `:e b.txt`, and no step holds the whole path.
- T397 [char] (A27) A step that changes no row and makes no move isn't kept: with the cleanup timer at 100 ms, `:e a`, `:e b`, then half a second of ticks with nothing to repair, and `:help` opened and closed, add no step to the ring.
- T398 [char] (A27, A22) The cleanup says nothing, and its repair is a move: `:e a`, `:e b`, `:e c`, then b's buffer wiped with `noautocmd`, and the next tick or refresh: no "CAVEDIVER CLEANUP REPORT" notification, and a step with cause `timer`, trigger `cleanup`, holds a "repair" move on b.txt naming `editor`, the list it's kept on.
- T399 [char] (A27, A16) `<M-S-w>` on an empty list while other lists hold closed files says so: in T318's state, `:bdelete c.txt` in the session's tab, then `<M-S-w>` in the first tab, whose list is empty, give one WARN, "No closed buffers to reopen in this tab." with "1 is on another tab's list: :CavediverClosed" under it; with a.txt and b.txt closed there too, "3 are on other tabs' lists: :CavediverClosed". With no closed file on any list, the message is T87's.
- T400 [char] (A27) A close that also lands on another list says so, once the batch settles: in T318's state, `:e a`, `:e d` in the session's tab, then `:e a` and `:bdelete a.txt` in the first tab give one INFO, "a.txt closed here and in t" (the wording mine), and a "closed" move on a.txt naming `editor` and `t`, not dim.
- T401 [char] (A27) A reopen that takes the file off another list says so: T400's state, then `<M-S-w>` in the first tab reopens a, and one INFO says "a.txt reopened and taken off t" (the wording mine); a "reopened" move on a.txt names `editor` and `t`.
- T402 [char] (A27) A whole-editor load drops what its batch did: in T400's state before the close, with the whole editor saved, `:bdelete a.txt` and `load_session()` in one call give no "closed here" message, and no step in the trail but the load's holds a close of a.txt: the load closes it as a reference the session manager didn't bring back (T337, T412), which is its own move. The load's step, cause `load`, says nothing either.
- T402 [char] (A27) The outgoing save before a switch keeps the teardown out of its step: in T402's state, `save_session()`, `:bdelete a.txt` and `load_session()` in one call, as resession's `pre_load` save runs right before its teardown, give a save step with no event under it, and a step of its own for `BufDelete a.txt`, marked `torn`, with no move, and the trail holding no close of a.txt but the load's.
- T403 [char] (A27, A21) Cleanup's re-point is a move, and its pop-up stays: T163's route (`:e d`, `:e b`, `:e c`, `<M-f>`, `:e a`, then d shown without events and `:bwipeout a.txt`) gives "Healed the triquetra…" and, on the step `BufDelete a.txt`, a "repointed" move on the window, `⦉c.txt⦊ [a.txt] ⟦b.txt⟧ → ⦉a.txt⦊ [d.txt] ⟦b.txt⟧`.
- T404 [char] (A27, A19) The landing after a delete is a move on the delete's step: T111's route (`⦉b⦊ [c] ⟦-⟧`) and `:bdelete c.txt` give, on the step `BufDelete c.txt`, the "closed" move on c.txt and then a "landed" move on the window, from the ternary, `⦉b.txt⦊ [c.txt] ⟦-⟧ → ⦉-⦊ [b.txt] ⟦-⟧`.
- T405 [char] (A27, I10) An arrival undone is a move: T217's first route (`:e a`, `:enew` with text, `setlocal buftype=nofile`) gives, on the step `OptionSet buftype`, an "undone" move on the window, `⦉a.txt⦊ [[No Name]] ⟦-⟧ → ⦉-⦊ [a.txt] ⟦-⟧`.
- T406 [char] (A27, A21) A triquetra dropped is a move: `:e a`, `:enew`, a `nofile` scratch shown in the window, which is then visiting it with the empty No Name buffer as its current slot, and that buffer wiped give a "dropped" move on the window, which has no triquetra after.
- T407 [char] (A27, M7) "Keep the older one"'s rewrite is a move: T185's keys give, on the last `<M-f>`, a "rewritten" move on e.txt, its ternary note `e.txt>c.txt → e.txt>a.txt`.
- T408 [char] (A27, Q6) Q6's guard is a move, and its pop-up stays: T150's keys give "Avoided conflict…" and, on the third `<M-f>`, a "rewritten" move on b.txt by the guard, `b.txt>a.txt → b.txt>c.txt`.
- T409 [char] (A27, A1) Navigation's own check is a move, and its pop-up stays: T33's keys give "…switching with the pre-jump ternary." and, on the step `BufEnter b.txt`, a "rewritten" move on b.txt by navigation, `b.txt>a.txt → b.txt>c.txt`.
- T410 [char] (A27, P10) A file forgotten by follow along is a move, with the notes that went: T208's route gives, on the wipe's step, a "forgotten" move on the No Name buffer, 2 notes dropped.
- T411 [char] (A27, A12) The cancel on a window jump is a move on the jump's step: T175's route gives, on the step `WinEnter win 1` (the split, left of the window that cycled), a "cancelled" move on the window that cycled, back on c.txt.
- T412 [char] (A27, S1) A load's moves: T337's route gives a load step holding a "loaded" move, 1 window matched, and a "closed" move on b.txt, not restored.
- T413 [char] (A27, S1) A load with no file is a fresh start, a move on its step: `load_session('nothing')` gives a load step holding a "fresh" move.
- T414 [char] (A27, S1) A tab-session save's moves: T323's route gives, on the save step `t`, a "saved" move, and, on a save step of its own for the whole editor's session, its "refreshed" move.
- T415 [char] (A27, S1) `:restart`'s reload is a step of its own: T298's route gives a step with cause `restart`, and no load step after it; the step before it, the restart session's own events, sourced with events on, is torn down by that reload, with no move left.
- T416 [char] (A27, S1 Records) A tab session's tab closed is a move: T322's route gives, after `:tabclose`, a "tab closed" move on t, its records written and its list let go.
- T417 [char] (A27, A20) Renames are moves: `:e a`, `:e b`, `:saveas g.txt` give a "copied" move on b.txt; T238's route gives a "moved" move on the No Name buffer, written as new.txt.
- T418 [char] (A27, M14) A change of label is a step, and tags are moves: T343's route gives a step with cause `label`, trigger `feature → main`, holding a "gone" move on b.txt tagged feature; and once b.txt is back, a "back" move on it.
- T419 [char] (A27, M5) Detached lists are moves: T381's route gives, on the load into the third tab, a "detached" move on t_DETACHED, and, on the second tab's close, a "detached left" move on it, into the whole editor's file.
- T420 [char] (A27) A save writes today's page: after `:e a`, `:e b`, `:e c`, `<M-.>` and `save_session()`, the main file lists today's date under `trail`, the page is a file of its own in `<main>.d/` that holds no file name in clear, and a fresh process reads it back (`read_trail`) with the step `<M-.>` and its "closed" move on c.txt.
- T421 [char] (A27, S1 Records) Today's page rides with the records: after a save, `:bdelete b.txt` and a second's wait, with no save, the page holds b's close.
- T422 [char] (A27) A load reads no page: with today's page's file corrupted, a load in a fresh process goes through with no warning, and the page reads as nothing.
- T423 [char] (A27) Pages outlive the editor that wrote them: a first editor's move and save, then a second editor's move and save on the same session, leave today's page with both steps, the first editor's first; a page of an earlier day, from a step the first editor kept on 2026-10-20, stays listed after the second's save.
- T424 [char] (A27) Each file keeps its own moves: in T318's state with the whole editor saved before t was loaded, `:bdelete x.txt` in the first tab and `:bdelete c.txt` in t's, and a second's wait: t's page holds c's close and not x's, and the whole editor's page, the unnamed session's, x's and not c's; and t's own save, made in the editor before, and its load are in t's page and not the whole editor's.
- T425 [char] (A27) `:CavediverTrail` opens the trail, untracked, on today's page: after `:e a`, `:e b`, `:e c`, `<M-.>`, it opens a float on a `nofile`, unlisted buffer that goes with its window, filetype `cavediver-trail`, with no hash and no triquetra, and the window it came from keeps its slots; the first line, the header, holds `⦉ trail ⦊`, "today" and the number of moves; a line holds the step's time, the keymap's glyph and `<M-.>`, and the line under it the "closed" move on c.txt with `≡editor`.
- T426 [char] (A27) `H` and `L` go to the older and the newer page: with a step kept three days ago, `H` shows that day, "3 days down", with `<<< H` dim, since there's no older page, and `L` shows today again.
- T427 [char] (A27) Brightness by surprise: in T400's state, the close onto t's list too is drawn in the closed family's colour, and T394's close onto the tab's own list dim.
- T428 [char] (A27) More than three of a kind under one step fold to a count: `:bdelete a.txt b.txt c.txt d.txt` gives one line, "4 closed", with `▸`, and `za` there opens the four names under it; three closes under one step don't fold.
- T429 [char] (A27) A narrow window drops the tally first, then the gauge: the header holds both at 120 columns, the gauge alone at 73, neither at 50.
- T430 [char] (A27) The header's pieces can be turned off: with `trail = { header = { tally = false, gauge = false, shade = false } }`, the header holds no tally, no gauge and no shaded fill.
- T431 [char] (A27) With `glyphs = { set = "ascii" }`, the trail draws no character outside ASCII.
- T432 [char] (A27) `q` and `<C-c>` leave: either closes the float, its buffer goes, and the focus is back in the window the trail was opened from.
- T433 [char] (A27) Opening the trail reads only what it shows: with steps kept on 20 earlier days and the session saved, a fresh process opening the trail reads at most 15 pages, the gauge's days around the one shown.
- T434 [char] (A27) A fold opened on one day stays that day's: a fold opened today, then `H` to an older day with a fold at the same place, shows that one closed, `▸`.
- T435 [char] (A27) `za` on a step opens the ring's steps since the trail's line before: after `:e a`, `:e b`, `:e c`, `<M-f>` and `<M-.>`, the `<M-.>` line shows `▸`, and `za` there opens the steps before it, the `<M-f>` among them with its row, `⦉b⦊ [c] ⟦-⟧ → ⦉-⦊ [c] ⟦b⟧`; `za` again closes them.
- T436 [char] (A27) The ring's steps open 20 at a time: with 25 steps since the trail's line before, `za` opens the 20 nearest and a line "… 5 earlier steps", and `za` on that line opens the other 5.
- T437 [char] (A27) A line from before this editor doesn't expand: a step an earlier editor wrote into today's page, its seq the same as one in this editor's ring, shows no `▸`, and `za` on it opens nothing, while this editor's own line beside it does show `▸`.
- T438 [char] (A27) A search is a name's life line across every page: with c.txt closed three days ago and again today, `s` and `c.txt` give a header holding `c.txt` and "2 moves over 2 days", and a line for each, oldest first, its gutter bar in the closed state's colour; `:CavediverTrail c.txt` opens the same. Oldest first is the approved mock's order, which the author picked over the ticked option's newest first (2026-10-24: "Oldest first (as built)").
- T439 [char] (A27) `<CR>` on a result opens its day with the cursor on its step, and `q` in a search goes back to the day it came from.
- T440 [char] (A27) `*` searches the name under the cursor: on c.txt's close, `*` gives c.txt's life line.
- T441 [char] (A27) `gf` acts on the name under the cursor and stays: on c.txt's close it opens c.txt in the window the trail came from, the trail still open; on `≡t` in a close onto t's list it opens the closed lists on t; on a move about a window, T411's cancel, it goes to the window that cycled. (A landing after `:bdelete` can't stand in: with another window open, `:bdelete` closes the window that showed the buffer, so nothing lands.)
- T442 [char] (A27) The formatters replace a line's look: `formatters.trail_move`, given the move, the glyphs and the step, gives a move's line; `formatters.trail_step` a step's; `formatters.trail_header` the header's; a formatter that gives nothing leaves cavediver's own.
- T443 [char] (A27) `za` opens a step in a search too (the author: "Expand in search too"): with c.txt closed three days ago and, after `:e a`, `:e b`, `:e c` and `<M-f>`, again today, the search for c.txt shows `▸` on today's result and not on the older one, and `za` on today's opens the ring's steps its day's line opens, the `<M-f>` among them with its row, `⦉b⦊ [c] ⟦-⟧ → ⦉-⦊ [c] ⟦b⟧`; `<CR>` there opens today's page with the `<M-.>` line open, `▾`, and the `<M-f>` under it.
- T444 [char] (A27) `*` on a file follows that file, and a typed name every file of that name: with `sub/c.txt` closed and then c.txt, both drawn `c.txt`, `*` on c.txt's close gives "1 move over 1 day", and `s` with `c.txt` "2 moves over 1 day".
- T445 [char] (A27) A close by a rename or a repair turns the life line closed: T417's `:saveas g.txt` gives b.txt's result a bar in the closed state's colour, and so does T398's repair, b.txt kept on the editor's list.

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

**Answered (2026-10-23), for the tab-session work:** yes, and closing it puts it back. A file reopened from one pool leaves every pool, so an open file is closed nowhere (I7). When it's closed again it goes back "not only on the tab i close it in, but on the other pool as well": on the pool of the tab it's closed in, on every pool it came out of when it was reopened, and on the pool of every tab that visited it, whose windows show it or have it in their history (the author: "Both"). It lands as the newest entry in each (I22).

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
- **Arrivals and window entries settle first.** Every `BufEnter` arrival and every `WinEnter` waits for `vim.schedule` (P2), and so do the landing after a delete (A19), the cancel of a cycle on a window jump (A12), the undo on `OptionSet` (I10), a rename and a write (A20), a load's follow-up and its `:restart` reload (S1), and the watch on git's HEAD (M14). Some are nested: a `WinEnter` while cycling settles, then schedules the cancel, whose switch back fires a `BufEnter` that settles in turn. So let the loop run (`vim.wait`) before checking slots, history, what a window shows or which state navigation is in.
- **Only what a window shows once it settles is slotted.** Arrivals made inside one call or one batch of keys (a macro, a mapping that switches buffers several times, `:bufdo`, a loop of `:edit`) are judged once the editor settles, so only what each window shows then is slotted and recorded (A1). A cavediver key in the batch, a press through `_G.CDV_TEST.press` included, first runs the settle work still queued (M11 Settle work).
- **Walks fail on a dump.** Every random walk (T128–T133, T149, T190, T249, T279–T283, T335) fails when it wrote a dump, naming what fired, read in the walk's own project before the next walk starts (the author, 2026-10-24: "Chase it now, walks fail on dumps"). **[run 2026-10-24]** recorded T249's walks, which press keys back to back with nothing settling and count no errors, dumping two routes silently: (a) and (b), A12. The setups that open files in a loop wait 10 ms after each one (T9, T122, T309), and `K.walk` waits 10 ms after each action and each cycle step (T190, T335), as typing does.
- **Loads in one process.** A load after a save or a load in the same process tears down first and goes through, unless it's a tab session's file, which loads into the current tab with nothing torn down (S1). Calls to `load_session` in one batch load once, so let the loop run between two loads that should both happen (T297, T300, T339). A case about what comes back in a new editor saves in one process and loads in the next, keeping the same `XDG_DATA_HOME` and the same cwd, because the file is named after the session's directory, the global cwd for a whole-editor session, and the session's name; the cases pass the cwd as the name. To fake a manager restore, use `bufadd` and `bufload` with `buflisted`, plus `noautocmd edit` for the shown file; `noautocmd badd` reproduces the unloaded-buffer case.
- **A child's stop is a quit, and a change is written a tick later.** mini.test's `child.stop` uses `:cquit`, which fires `VimLeavePre`, so every restart of a test's child writes its sessions' records (S1 Records); a crash is a kill, which fires none (T307, T359). A change's records are written on the next tick and again when its second runs out, so a case that reads a session's file after a change lets the loop run first.
- **The label comes from the nearest `.git` upward** from the cwd (M14). A sandbox with a `.git` above it takes that repository's branch as its label, so its tags aren't the time. T343, T346 and T347 plant a `.git/HEAD` in the project, and T344 needs none to be found.
- **Fresh windows track nothing.** The first buffer nvim shows isn't registered until something enters it, so start every scenario with `:e a.txt`.
- **Splits don't fire `BufEnter`.** `:vsplit` creates the second window's triquetra, with an empty history entry, once its `WinEnter` settles.
- **Use files that exist on disk**, unless the case is about a missing one. A buffer whose file is missing stays tracked (M3), and a closed slot or closed entry whose file is gone stays too, but using it says the file isn't on disk instead of reopening it (A6–A8, A16).

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

**Nothing is left open for the author here.** D2's colour was answered on 2026-10-24: blue, `#4385BE`.
