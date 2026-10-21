# Packet WV: the walks again, under `history_view = "window"`

**Stakes:** every earlier walk ran with the default `history_view = "global"`. The author runs `"window"`. Does "Keep the older one" still give 0 ternary and 0 secondary restore throws under the view the author actually uses? And what happens once the two decided, unbuilt window rules are in: a jump to another window cancels an active cycle, and `<M-f>`'s fill from history asserts?

**Short answer**
- **0/0 holds under the window view.** "Keep the older one" gives 0 ternary and 0 secondary restore throws in every run here: one window and several, both seeds, both views, with and without the two window rules.
- **With one window, the view changes nothing.** All 3,000 walks of each of the three codes are identical step for step under both views. The window view only re-ranks history when you enter another window.
- **With several windows, the rest of KT's clean bill doesn't hold under the window view.** KT also found no other error, no hook failure and no duplicate slot.
  - On its own, "Keep the older one" now gives 1 and 4 "Duplicates detected" throws, 0 and 2 hook failures, and 36 and 60 steps with a duplicate slot.
  - Every one of them comes after a fill from history that put the current buffer into the secondary (route 1 below).
  - With the fill assertion in, they're all gone, and the assertion fires instead.
- **The fill assertion fires, under both views, by two routes.**
  1. **The window view's rebuild ties two buffers (window view only, no cycle needed).**
     - When you enter a window, the window view hands that window's newest buffer the next free access time. The next buffer recorded gets the same time.
     - When the tie breaks the wrong way, the ordered list's first entry isn't the current buffer, and a `<M-f>` that fills from history asserts. Without the assertion, the fill puts the current buffer into the secondary.
  2. **Landing in a window after a cancelled cycle (both views).**
     - If the window you jump into shows the very buffer the cycle had reached, Neovim fires no `BufEnter` there, so nothing records that buffer.
     - It isn't first in the ordered list, and `<M-f>` there asserts.
     - How often depends on whether landing in a window counts as an ordinary entry that records its buffer. The decided wording doesn't say. Three readings were run (section 5).
- **Fill-assertion counts, per 1,500 walks.**

| Walks | Global view, seed 7 | Global view, seed 11 | Window view, seed 7 | Window view, seed 11 |
|---|---|---|---|---|
| Windows only (no cycle left open) | 0 | 0 | 5 (4 walks) | 9 (6 walks) |
| Cycles left open across a jump; the landing never recorded | 35 (33 walks) | 41 (28 walks) | 40 (38 walks) | 52 (35 walks) |
| … the landing recorded when Neovim fires `BufEnter` | 17 (16 walks) | 23 (16 walks) | 23 (22 walks) | 32 (23 walks) |
| … the landing always recorded | 0 | 0 | 1 (1 walk) | 3 (2 walks) |

- **Every assertion is one of those two routes.**
  - The tie accounts for all of them in the windows-only walks.
  - In the walks that leave cycles open, the tie accounts for 7/17, 4/13 and 1/3 of them under the window view (seed 7/seed 11, for the three readings in that order). The landing accounts for the rest.
  - None comes from anything else.

**How things are cited**
- Code paths are relative to the repo, for example `lua/cavediver/domains/history/routines.lua:191`. `what-is-cavediver.md:N` is the spec in the repo.
- `<sandbox>` is the test sandbox. KT and RT are the earlier packets, `<sandbox>/../packets/KT.md` and `<sandbox>/../packets/RT.md`.
- Every run uses either a copy of the plugin under `<sandbox>/variants/` or today's code read in place. Nothing in the repo was changed.
  - **[sim]** marks a run of a variant: a decided change that isn't built yet.
  - **[run]** marks a run of today's code.
  - **[code]** marks a reading of the code, not a run.
  - **[inferred]** marks something reasoned but not run.
- **The view switch.** Each run sets `require("cavediver.configs").bufferline.history_view` right after `setup()`, the way `<sandbox>/t/b7w_dup.lua` does. `setup()` merges into that shared table, and `construct_crux` reads it at call time (`lua/cavediver/domains/history/routines.lua:174`).
  - The view is recorded in every walk step.
  - A probe shows it takes effect: back in win1 after working in win2, the ordered list reads `b,a,d,c` under the window view and `b,d,c,a` under the global view (`<sandbox>/t/wv_probe.lua`).
- **Rows:**
  - One row per action, then the window it ended in (`win1`, `win2`, … in the order the windows were made), then that window's triquetra `⦉ternary⦊ [current] ⟦secondary⟧   dtm{…} dsm{…}`, then any message.
  - `x>y` is x's plain note, and `x-swap>y` is its swap note.
  - Where the cause isn't in the slots, rows also show `ordered …`: the ordered list after the action, with each buffer's access time.
  - `(still cycling)` marks a row that ends with navigation still in `cycling`.
  - «cycle cancelled, its window back on c» marks where the simulated cancel fired. It's a sandbox marker, not a message the plugin shows.
  - `ERROR: WV-fill-assert: …` is the simulated assertion.
- **Random walks:**
  - Each run is 1,500 walks of 25 keys on seeds 7 and 11.
  - The one-window walks use KT's generator, keys and seeds unchanged.
  - The several-window generators are described in sections 3 and 4.
  - Rows and walks both run each action straight after the last, with no wait in between.

---

## 1. What was built

**The runner.**
- `<sandbox>/rt/rt_walk.py` doesn't use `run.sh` or `runv.sh`. It runs each walk through `<sandbox>/rt/rt_runseq.sh` in its own job folder under `<sandbox>/rtjobs/`.
- The WV copies are `<sandbox>/rt/rt_walk_b.py`, `<sandbox>/rt/rt_runseq_b.sh` and `<sandbox>/rt/rt_view_b.lua`.
  - They keep their job folders under `<sandbox>/rtjobs_b/` and write their walks to `<sandbox>/rt/walks_b/`.
  - They take the view as an argument.
  - The one-window generator is RT's, with the same random draws.
- **Check:** the copy's global-view walks equal KT's and RT's walk files step for step: 1,500 of 1,500 walks for every code and seed that has an earlier file. The comparison ignores the file hashes inside messages, because they depend on the job folder.

**The variants** **[sim]**

| Plain name | Variant | What it is |
|---|---|---|
| today's code | (the repo) | unchanged |
| the secondary fix, no ternary rewrite | `rt_c3kga` | KT's base |
| Keep the older one | `kt_rewrite` | the decided variant: both sides, with the kept ternary's own note where the ternary stays put (KT) |
| Keep the older one + the window rules | `kt_rewrite_win` | the variant above, plus the two rules below; the landing is recorded when Neovim fires `BufEnter` |
| … the landing never recorded | `kt_rewrite_win_strict` | the strictest reading of the cancel (section 5) |
| … the landing always recorded | `kt_rewrite_win_land` | the loosest reading of the cancel (section 5) |

**The two window rules, as simulated**
- **A jump to another window cancels an active cycle** (decided at `what-is-cavediver.md:734`, with its planned test at `:1422`):
  - When a `WinEnter` lands in a window other than the one cycling, the cycling window goes back on its start, navigation goes back to `normal` and history is attached. Nothing is recorded for the cycle.
  - It's added in `lua/cavediver/domains/navigation/hooks.lua`, after navigation's own `WinEnter` handler (`:44-48`).
  - **It runs straight away inside the `WinEnter`, not "after the editor settles".** The walks never hand control back to the editor between keys, so a scheduled cancel would never run in them.
  - **Order.**
    - The cycling window is put back on its start first, while history is still detached, so the `BufEnter` this causes records nothing.
    - Then navigation and history switch over without a transition mode, so none of the hooks that record or move slots run. The no-mode hooks that do still run are `attach_history_update`, which does nothing without a mode, and `cleanup_triquetras`.
  - **What that does to the landing.** Neovim follows the `WinEnter` with a `BufEnter` only when the window you land in shows a different buffer from the one you just left. Here that `BufEnter` runs with history already attached, so it records the landing buffer as an ordinary entry. When the landing window shows the very buffer the cycle had reached, no `BufEnter` comes and nothing records it. That's the in-between reading. The other two readings change only this step (section 5).
  - **Check.** The planned test's run passes under both views and all three readings (`<sandbox>/t/wv_jump.lua`, which replays `<sandbox>/t/b7_jump.lua`): win1 shows its start again, navigation is `normal`, history is attached, and the cycled-to buffer isn't recorded. Then `:e d` in win2 moves win2's slots and records `d`.
- **The fill from history asserts** (decided at `what-is-cavediver.md:1239`, with its planned test at `:1423`):
  - With an empty secondary and no ternary, `<M-f>` throws when the ordered list's first entry isn't the window's current buffer.
  - It's added right before the fill at `lua/cavediver/domains/window/routines.lua:488-490`.
  - **Check.** The duplicate this assertion was decided for (`<sandbox>/t/b7_dup.lua`) is gone once the cancel is in, under both views. The fill takes `c`, and the assertion doesn't fire (`<sandbox>/t/wv_dup.lua`).

---

## 2. One window: the numbers, global next to window

Seeds 7 and 11, 1,500 walks of 25 keys each. Each cell gives the global view's number, then the window view's.

| Code | Seed | Ternary throws (walks) | Secondary throws (walks) | Other errors | Hook failures |
|---|---|---|---|---|---|
| Keep the older one | 7 | 0 (0) / 0 (0) | 0 (0) / 0 (0) | 0 / 0 | 0 / 0 |
| Keep the older one | 11 | 0 (0) / 0 (0) | 0 (0) / 0 (0) | 0 / 0 | 0 / 0 |
| the secondary fix, no ternary rewrite | 7 | 14 (14) / 14 (14) | 0 (0) / 0 (0) | 0 / 0 | 0 / 0 |
| the secondary fix, no ternary rewrite | 11 | 13 (12) / 13 (12) | 0 (0) / 0 (0) | 0 / 0 | 0 / 0 |
| today's code | 7 | 14 (14) / 14 (14) | 161 (147) / 161 (147) | 0 / 0 | 0 / 0 |
| today's code | 11 | 12 (11) / 12 (11) | 191 (168) / 191 (168) | 0 / 0 | 0 / 0 |

- **Where the global numbers come from.**
  - Keep the older one and the secondary fix: KT's table, re-run here with identical walks.
  - Today's code, seed 7: RT's table, also re-run here with identical walks.
  - Today's code, seed 11: run here for the first time **[run]**.
- **Every walk is identical under the two views, step for step.** That's 37,500 of 37,500 steps for every code and seed, comparing slots, notes, messages, errors and the ordered list **[run, sim]**.
- **Why [code].** The window view acts only in `construct_crux` (`lua/cavediver/domains/history/routines.lua:165-198`). That runs when you enter a window (`lua/cavediver/domains/history/hooks.lua:59-61`) or close one (`lua/cavediver/domains/window/data.lua:57`). With one window it never re-ranks anything.
- **No fill from history happens in any one-window run** (0 fills in every file). The secondary and the ternary are both empty only at the start, when history holds one buffer. So the fill assertion can't fire there at all.
- **Nothing else changes either.** Duplicate slots and notes naming their own buffer: 0 everywhere. The remaining throws of the secondary fix and of today's code are in the same walks and steps as under the global view, so their routes are the ones in KT section 5 and RT.

---

## 3. Several windows: `:vsplit`, `<C-w>p`, `:close`

**The generator** (`<sandbox>/rt/rt_walk_b.py … mw`):
- RT's 24-key draw pool, plus `:vsplit` twice, `<C-w>p` three times and `:close` once.
- At most 3 windows. `<C-w>p` and `:close` are drawn only when there are 2 or more windows. When `<C-w>p`'s previous window is gone, it moves to the next window instead.
- 84% of walks split at least once, with about 3 window keys per walk.
- **No cycle is ever open at a jump.** The cycling picks (`<M-m>`/`<M-n>` then `<M-v>`) are single keys here, as in RT. So the cancel never fires in these walks, and the three readings of it run the same. Section 4 adds open cycles.

Each cell gives the global view's number, then the window view's. Every run had 0 ternary throws and 0 secondary throws.

| Code | Seed | Fills from history | Fill assertions (walks) | Fills that would assert (walks) | Other errors | Hook failures | Steps with a duplicate slot | Steps with a note naming its own buffer |
|---|---|---|---|---|---|---|---|---|
| Keep the older one | 7 | 623 / 623 | – | 0 / 7 (6) | 0 / 1 | 0 / 0 | 0 / 36 | 0 / 8 |
| Keep the older one | 11 | 586 / 588 | – | 0 / 6 (5) | 0 / 4 | 0 / 2 | 0 / 60 | 0 / 36 |
| Keep the older one + the window rules | 7 | 623 / 623 | 0 / 5 (4) | = the assertions | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| Keep the older one + the window rules | 11 | 586 / 589 | 0 / 9 (6) | = the assertions | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

- **"Fills that would assert"** counts fills whose ordered list, just before the key, didn't start with the window's current buffer. Every one of them put the current buffer into the secondary.
- **Under the global view, the two codes run identically**, step for step, on both seeds.
- **Why the window-view counts differ between the two codes on the same walks.**
  - The tie breaks independently in every run, so the two columns are two draws from the same exposure.
  - Fills with the current buffer tied for first: 9 and 9 on seed 7, and 11 and 13 on seed 11 (the walks drift apart once a tie has broken differently).
  - The tie broke wrong in 7 of 9 and 6 of 11 of them without the assertion, and in 5 of 9 and 9 of 13 with it.
  - Where the two codes' walks first differ, it's only in the order of two tied buffers, apart from the 3 walks where it's the assertion itself (seed 7).
- **Everything else wrong under Keep the older one's window-view runs comes after such a fill, in the same walk.**
  - That covers the "Duplicates detected in triquetra slots" throws (`reconcile_triquetra`, `lua/cavediver/domains/window/routines.lua:115`).
  - It covers the `displacement_mangement` hook failures ("Duplicates detected in current triquetra", `lua/cavediver/domains/window/hooks.lua:64`): the same duplicate, caught by the other hook.
  - It also covers the duplicate slots and the self-naming notes.
  - It held for every walk, on both seeds. Section 5 shows the throw and the hook failure as rows.
- **The assertion stops it at the source.** With the window rules there are no other errors, no hook failures, no duplicates and no self-naming notes.
- Every one of these fills is the tie in section 5, route 1.

---

## 4. Cycles left open across a jump

**The generator** (`… mwy`): the `mw` generator, plus a key that steps the cycle once (`<M-m>` or `<M-n>`) and then presses `<C-w>p` without picking. It was drawn about 1,100 times per seed, in about 700 walks.

Each cell gives the global view's number, then the window view's. Every run had 0 ternary throws and 0 secondary throws.

| Code | Seed | Cancels | Fill assertions (walks) | Fills that would assert (walks) | Other errors | Hook failures | Steps with a duplicate slot | Steps ending still in `cycling` |
|---|---|---|---|---|---|---|---|---|
| Keep the older one | 7 | – | – | 43 (42) / 48 (47) | 57 / 57 | 2 / 4 | 180 / 182 | 4,824 / 4,824 |
| Keep the older one | 11 | – | – | 39 (39) / 50 (50) | 65 / 66 | 1 / 2 | 153 / 210 | 4,876 / 4,876 |
| + window rules, landing never recorded | 7 | 1,091 / 1,091 | 35 (33) / 40 (38) | = the assertions | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| + window rules, landing never recorded | 11 | 1,122 / 1,122 | 41 (28) / 52 (35) | = the assertions | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| + window rules, landing recorded on `BufEnter` | 7 | 1,091 / 1,091 | 17 (16) / 23 (22) | = the assertions | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| + window rules, landing recorded on `BufEnter` | 11 | 1,122 / 1,122 | 23 (16) / 32 (23) | = the assertions | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| + window rules, landing always recorded | 7 | 1,091 / 1,091 | 0 / 1 (1) | = the assertions | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| + window rules, landing always recorded | 11 | 1,122 / 1,122 | 0 / 3 (2) | = the assertions | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

**Without the cancel, this is today's leak across windows** (`what-is-cavediver.md:734`), on top of Keep the older one:
- The cycle stays open in the other window.
- 57 errors (seed 7) and 64 (seed 11) are `<M-;><M-f>` pressed in a window that has no cycle start: "This should not happen. Cycling origins not found for window" (`lua/cavediver/domains/window/routines.lua:617`). The rest are "Duplicates detected in triquetra slots".
- The hook failures are the duplicate checks (`displacement_mangement`, `reconcile_triquetra`). On seed 7 there are also two on a closed window: `winenter_update_history_view` and `update_ui_state`, "Invalid window id".
- Most of the fills that would assert come from the frozen history.

**With the cancel, under all three readings:**
- Every one of those keys cancelled, and no step ends in `cycling` or with history detached.
- The leak's errors, hook failures and duplicates are gone, under both views.
- What's left is the fill assertion, by two routes:

| Reading | Route | Global, seed 7 | Global, seed 11 | Window, seed 7 | Window, seed 11 |
|---|---|---|---|---|---|
| landing never recorded | landing after a cancel (route 2) | 35 | 41 | 33 | 35 |
| landing never recorded | the window view's tie (route 1) | 0 | 0 | 7 | 17 |
| landing recorded on `BufEnter` | landing after a cancel | 17 | 23 | 19 | 19 |
| landing recorded on `BufEnter` | the window view's tie | 0 | 0 | 4 | 13 |
| landing always recorded | landing after a cancel | 0 | 0 | 0 | 0 |
| landing always recorded | the window view's tie | 0 | 0 | 1 | 3 |

---

## 5. The fill assertion's two routes, as rows

### Route 1: the window view's rebuild ties two buffers (window view only)

**The cause [code]**
- **Entering a window rebuilds its history.** On a window entry, `construct_crux` ranks that window's own buffers on top of the global history (`lua/cavediver/domains/history/routines.lua:185-197`).
  - It moves the next index up by n−1 for n buffers (`:191`).
  - Then it gives rank 1, the window's newest buffer, the index itself (`:194`). That's the number the next record will get.
- **The next record takes the same number.** `track_buffer` gives the next buffer recorded `data.history_index` (`:210-212`), so two buffers share the top time.
- **The ordered list sorts on time alone** (`:321-323`). Lua's sort leaves equal entries in no particular order, and here the order changed from one Neovim start to the next.
- **When it's harmless.** If the entry fires a `BufEnter`, the first record is the window's newest buffer itself, and the tie is with itself.
- **When it bites.**
  - The entry fires no `BufEnter` when the window you enter shows the same buffer as the one you left. That happens right after a `:vsplit`, or after `:close`.
  - The next buffer recorded, by `:e`, a swap or a pick, then ties with the window's newest.
- **Why the stale order reaches the fill.** A `:vsplit` records nothing, so the new window inherits the tied order. So does an old window whose two slots are still empty.

**The shortest route.** Window view, with the assertion **[sim]**:
```
:e a                       win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=1
:e b                       win1  ⦉a⦊ [b] ⟦-⟧   dtm{} dsm{}   ordered b=2 a=1
:vsplit                    win2  ⦉-⦊ [b] ⟦-⟧   dtm{} dsm{}   ordered b=2 a=1
<C-w>p                     win1  ⦉a⦊ [b] ⟦-⟧   dtm{} dsm{}   ordered b=2 a=1
:e c                       win1  ⦉b⦊ [c] ⟦-⟧   dtm{b>a} dsm{}   ordered b=4 c=4 a=3
:vsplit                    win3  ⦉-⦊ [c] ⟦-⟧   dtm{} dsm{}   ordered b=4 c=4 a=3
<M-f>                      win3  ⦉-⦊ [c] ⟦-⟧   dtm{} dsm{}   ordered b=4 c=4 a=3  ERROR: WV-fill-assert: ordered[1] b isn't the window's current c
```
Keep the older one without the window rules, window view [sim]: the first 6 rows are the same; from there, carried on to the throw:
```
<M-f>                      win3  ⦉-⦊ [c] ⟦c⟧   dtm{} dsm{}   ordered b=4 c=4 a=3  «Secondary buffer populated from history.»
:e d                       win3  ⦉c⦊ [d] ⟦c⟧   dtm{} dsm{}   ordered d=5 c=4 b=2 a=1
<M-S-f>                    win3  ⦉d⦊ [c] ⟦c⟧   dtm{d-swap>c} dsm{}   ordered d=5 c=4 b=2 a=1  ERROR: Duplicates detected in triquetra slots
```
The same, with `:e e` instead of `<M-S-f>` after `:e d` [sim]: the first 8 rows are the same; from there:
```
:e e                       win3  ⦉c⦊ [d] ⟦c⟧   dtm{} dsm{}   ordered e=6 d=5 c=4 b=2 a=1  «Hook 'displacement_mangement' failed during transition attached->attac»
```
Global view, with the assertion [sim]: the first 4 rows are the same; from there:
```
:e c                       win1  ⦉b⦊ [c] ⟦-⟧   dtm{b>a} dsm{}   ordered c=3 b=2 a=1
:vsplit                    win3  ⦉-⦊ [c] ⟦-⟧   dtm{} dsm{}   ordered c=3 b=2 a=1
<M-f>                      win3  ⦉-⦊ [c] ⟦b⟧   dtm{} dsm{}   ordered c=3 b=2 a=1  «Secondary buffer populated from history.»
```

- **How the access times change.**
  - `<C-w>p` back into win1 shows `b` in both windows, so no `BufEnter` fires.
  - The rebuild gives win1's `b` the time 4 and sets the next index to 4. `:e c` also gets 4.
- **The duplicate's two symptoms.**
  - `:e d` makes `c` both the ternary and the secondary.
  - From there, `<M-S-f>` throws in `reconcile_triquetra`. A plain `:e` fails in the `displacement_mangement` hook, which leaves the slots behind the shown buffer (`e` is shown, `d` is the current slot).
- **The tie breaks either way, from one Neovim start to the next.**
  - Replays of this route broke it wrong 3 times in 5 under today's code **[run]**.
  - The rows above are replays where it broke wrong. When it breaks the other way, the fill takes `b`.
- **Today's code does the same.** Under the window view, on the same route, it puts `c` into its own secondary **[run]**.
- **This is why an earlier run looked clean.**
  - The spec's note on the secondary's first fill says that with the window view, `t/b7w_dup.lua` "happened not to duplicate" (`what-is-cavediver.md:1239`).
  - That run goes through this same tie, at its `<C-w>p, :e c` row.
  - Re-run 8 times on today's code, it duplicated 7 times and didn't once **[run]**.
- **How common the tie is in the walks.** In Keep the older one's several-window walks under the window view:
  - It shows up at some step in about 30% of walks: 453 and 442 of 1,500, at 1,099 and 1,075 steps. The global view has none.
  - Almost every step where the ordered list doesn't start with the current buffer is one of these ties: 383 of 384 and 375 of 381 such steps. The rest come after a duplicate the tie had already caused.
- **The ties reach more than `<M-f>` [code].** The bufferline ranks buffers by the same access times (`lua/cavediver/domains/ui/routines.lua:366-371`, `lua/cavediver/domains/ui/init.lua:169-172`), and cycling steps in the bufferline's order. So tied buffers sit in no fixed order there either.

**Three routes as they came from the walks.** Each was replayed until the tie broke wrong, window view, with the assertion **[sim]**.

The tie made by a swap (seed 7):
```
:e a                       win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=1
<M-S-f>                    win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=1  «No ternary buffer to swap with.»
:e c                       win1  ⦉a⦊ [c] ⟦-⟧   dtm{} dsm{}   ordered c=2 a=1
:e d                       win1  ⦉c⦊ [d] ⟦-⟧   dtm{c>a} dsm{}   ordered d=3 c=2 a=1
<M-f>                      win1  ⦉-⦊ [d] ⟦c⟧   dtm{c>a} dsm{c>a}   ordered d=3 c=2 a=1  «Secondary buffer set to ternary slot. Ternary slot graduated.»
:e d                       win1  ⦉-⦊ [d] ⟦c⟧   dtm{c>a} dsm{c>a}   ordered d=4 c=2 a=1
<M-f>                      win1  ⦉-⦊ [c] ⟦d⟧   dtm{c>a} dsm{c>a d-swap>c}   ordered c=5 d=4 a=1
<M-;><M-f>                 win1  ⦉-⦊ [d] ⟦c⟧   dtm{c>a} dsm{c-swap>d c>a d-swap>c}   ordered d=6 c=5 a=1
:vsplit                    win2  ⦉-⦊ [d] ⟦-⟧   dtm{} dsm{}   ordered d=6 c=5 a=1
<C-w>p                     win1  ⦉-⦊ [d] ⟦c⟧   dtm{c>a} dsm{c-swap>d c>a d-swap>c}   ordered d=6 c=5 a=1
<M-f>                      win1  ⦉-⦊ [c] ⟦d⟧   dtm{c>a} dsm{c-swap>d c>a d-swap>c}   ordered d=9 c=9 a=7
:vsplit                    win3  ⦉-⦊ [c] ⟦-⟧   dtm{} dsm{}   ordered d=9 c=9 a=7
<M-f>                      win3  ⦉-⦊ [c] ⟦-⟧   dtm{} dsm{}   ordered d=9 c=9 a=7  ERROR: WV-fill-assert: ordered[1] d isn't the window's current c
```

The tie made by a cycling pick, with the fill in the old window, which never had a ternary (seed 11):
```
:e a                       win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=1
<M-f>                      win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=1  «Cannot populate secondary slot - insufficent history.»
:vsplit                    win2  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=1
:e e                       win2  ⦉a⦊ [e] ⟦-⟧   dtm{} dsm{}   ordered e=2 a=1
<M-f>                      win2  ⦉-⦊ [e] ⟦a⟧   dtm{} dsm{}   ordered e=2 a=1  «Secondary buffer set to ternary slot. Ternary slot graduated.»
:e e                       win2  ⦉-⦊ [e] ⟦a⟧   dtm{} dsm{}   ordered e=3 a=1
<M-n> <M-v>                win2  ⦉-⦊ [a] ⟦e⟧   dtm{} dsm{}   ordered a=4 e=3  «Checkpoint saved: »
<C-w>p                     win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=4 e=3
<M-m> <M-v>                win1  ⦉-⦊ [e] ⟦-⟧   dtm{} dsm{}   ordered a=5 e=5  «Checkpoint saved: »
<M-f>                      win1  ⦉-⦊ [e] ⟦-⟧   dtm{} dsm{}   ordered a=5 e=5  ERROR: WV-fill-assert: ordered[1] a isn't the window's current e
```

The window entered by `:close` (seed 11):
```
:e a                       win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=1
<M-;><M-c>                 win1  ⦉-⦊ [a] ⟦-⟧  p=[a]on   dtm{} dsm{}   ordered a=1
:e c                       win1  ⦉a⦊ [c] ⟦-⟧  p=[a]on   dtm{} dsm{}   ordered c=2 a=1
<M-S-f>                    win1  ⦉c⦊ [a] ⟦-⟧  p=[a]on   dtm{c-swap>a} dsm{}   ordered a=3 c=2
:vsplit                    win2  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=3 c=2
:close                     win1  ⦉c⦊ [a] ⟦-⟧  p=[a]on   dtm{c-swap>a} dsm{}   ordered a=3 c=2
<M-S-f>                    win1  ⦉a⦊ [c] ⟦-⟧  p=[a]on   dtm{a-swap>c c-swap>a} dsm{}   ordered a=5 c=5
<M-f>                      win1  ⦉-⦊ [c] ⟦a⟧  p=[a]on   dtm{a-swap>c c-swap>a} dsm{}   ordered a=5 c=5  «Secondary buffer set to ternary slot. Ternary slot graduated.»
:vsplit                    win3  ⦉-⦊ [c] ⟦-⟧   dtm{} dsm{}   ordered a=5 c=5
<M-S-f>                    win3  ⦉-⦊ [c] ⟦-⟧   dtm{} dsm{}   ordered a=5 c=5  «No ternary buffer to swap with.»
<M-f>                      win3  ⦉-⦊ [c] ⟦-⟧   dtm{} dsm{}   ordered a=5 c=5  ERROR: WV-fill-assert: ordered[1] a isn't the window's current c
```

- All three fill correctly under the global view.
- Without the assertion, the last row puts the current buffer into the secondary, as in the shortest route.

### Route 2: landing after a cancelled cycle (both views)

**The cause [sim]**
- Win2 cycles from `c` onto `a`, and `<C-w>p` lands in win1, which also shows `a`.
- Neovim fires `BufEnter` on a window change only when the buffer changes, so nothing records the landing.
- The cancel puts win2 back on `c` and records nothing for the cycle.
- So the ordered list still starts with `c`, win2's start, while win1's current buffer is `a`. Shrunk from a walk.

Keep the older one + the window rules, landing recorded on `BufEnter`, global view [sim]:
```
:e a                       win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=1
:vsplit                    win2  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=1
:e c                       win2  ⦉a⦊ [c] ⟦-⟧   dtm{} dsm{}   ordered c=2 a=1
<M-m> <C-w>p               win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered c=2 a=1  «Checkpoint saved: »  «cycle cancelled, its window back on c»
<M-f>                      win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered c=2 a=1  ERROR: WV-fill-assert: ordered[1] c isn't the window's current a
```
Window view [sim]: every row the same. Landing never recorded, either view [sim]: every row the same.

Keep the older one without the window rules, global view [sim]: the first 3 rows are the same; from there:
```
<M-m> <C-w>p               win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered c=2 a=1  «Checkpoint saved: »  (still cycling)
<M-f>                      win1  ⦉-⦊ [a] ⟦a⟧   dtm{} dsm{}   ordered c=2 a=1  «Secondary buffer populated from history.»  (still cycling)
```
- This is the duplicate the fill assertion was decided for, reached through the leak.

Landing always recorded, global view [sim]: the first 3 rows are the same; from there:
```
<M-m> <C-w>p               win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=3 c=2  «Checkpoint saved: »  «cycle cancelled, its window back on c»
<M-f>                      win1  ⦉-⦊ [a] ⟦c⟧   dtm{} dsm{}   ordered a=3 c=2  «Secondary buffer populated from history.»
```
Window view [sim]: every row the same.

**The three readings of "nothing is recorded"** (`what-is-cavediver.md:734`):
- **Landing never recorded** (`kt_rewrite_win_strict`).
  - Nothing is recorded until the jump is over, not even the window you land in.
  - When a landing `BufEnter` follows, history stays detached through it and attaches right after it.
  - This is what a cancel that waits until "after the editor settles" would do **[inferred]**.
  - It gives the most assertions: 35–52 per 1,500 walks.
- **Landing recorded when Neovim fires `BufEnter`** (`kt_rewrite_win`, the runs in sections 3 and 4).
  - The cancel attaches history inside the `WinEnter`, so the landing's own `BufEnter`, when there is one, records the landing like any window entry.
  - Only a landing on the cycled-to buffer goes unrecorded: 17–32 assertions.
- **Landing always recorded** (`kt_rewrite_win_land`).
  - History attaches as an ordinary entry into the window you landed in, recording its buffer.
  - The reconcile that comes with it runs on that window, whose current slot already is that buffer, so no slot moves.
  - It removes every landing assertion. Only the window view's tie is left: 1 and 3.
- **All three** pass the planned test for the cancel: the cycled-to buffer isn't recorded, and win1 is back on its start.

---

## 6. The leak without the cancel, for reference

`<M-;><M-f>` in the window you jumped to, with the cycle still open. This is the most common error in section 4's runs without the cancel (shrunk).

Keep the older one without the window rules, global view [sim]:
```
:e a                       win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
:vsplit                    win2  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
<M-m> <C-w>p               win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}  «Checkpoint saved: »  (still cycling)
<M-;><M-f>                 win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}  ERROR: This should not happen. Cycling origins not found for window: 1000  (still cycling)
```
With the window rules [sim]: the first 2 rows are the same; from there:
```
<M-m> <C-w>p               win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}  «Checkpoint saved: »  «cycle cancelled, its window back on a»
<M-;><M-f>                 win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}  «Cannot populate secondary slot - insufficent history.»
```

---

## 7. What's open

1. **After a jump cancels a cycle, does the window you land in record its buffer, as any other window entry does?**
   - Always recording it closes route 2 under both views.
   - Recording it only when Neovim fires `BufEnter` leaves 17–32 assertions per 1,500 walks that leave cycles open.
   - Never recording it, which is also what "after the editor settles" would do, leaves 35–52.
2. **The window view's tie in `construct_crux`** (`lua/cavediver/domains/history/routines.lua:191`, `:194`).
   - It's a bug in today's code, not in any variant. Under the window view, the next buffer recorded after entering a window can share the top access time with that window's newest buffer.
   - That reaches the fill (route 1), and the order that the bufferline and the cycling keys follow.
   - Under the assertion's stance, route 1 is a route to be fixed upstream. Once route 2 is settled, it's the only route left.

---

## Runs

| Run | What it shows | Code |
|---|---|---|
| walks, one window | `<sandbox>/rt/rt_walk_b.py 1500 25 <seed> <code> <view> single`, seeds 7 and 11, both views | today's code, `rt_c3kga`, `kt_rewrite` |
| walks, several windows | `… mw`, seeds 7 and 11, both views | `kt_rewrite`, `kt_rewrite_win` |
| walks, cycles left open across a jump | `… mwy`, seeds 7 and 11, both views | `kt_rewrite`, `kt_rewrite_win`, `kt_rewrite_win_strict`, `kt_rewrite_win_land` |
| `<sandbox>/t/wv_probe.lua` | the window view takes effect | today's code |
| `<sandbox>/t/wv_jump.lua`, `<sandbox>/t/wv_dup.lua` | the planned tests' runs for the two rules, under either view | `kt_rewrite`, `kt_rewrite_win`, `kt_rewrite_win_strict`, `kt_rewrite_win_land` |
| `<sandbox>/t/wv_tie.lua`, `<sandbox>/t/wv_tie2.lua` | access times through window entries; the tie | today's code, `kt_rewrite_win` |
| `tie_min`, `tie_dup`, `tie_hook`, `r2`, `r3`, `r4` | route 1, as rows | `kt_rewrite`, `kt_rewrite_win` |
| `landing` | route 2, as rows | `kt_rewrite`, `kt_rewrite_win`, `kt_rewrite_win_strict`, `kt_rewrite_win_land` |
| `leakj` | the leak's `<M-;><M-f>` error | `kt_rewrite`, `kt_rewrite_win` |

- **The walk tooling.**
  - `<sandbox>/rt/rt_runseq_b.sh` runs one walk.
  - `<sandbox>/rt/rt_view_b.lua` sets the view.
  - `<sandbox>/rt/rt_seq_b.lua` is RT's `rt_seq.lua` with the view added to each step.
  - `<sandbox>/rt/rt_seq_mw.lua` runs the several-window walks. It records every window's slots and the ordered list's access times.
- **The counts** come from `<sandbox>/rt/wv_table.py`, `<sandbox>/rt/wv_fa_kind.py` (sorting assertions by route), `<sandbox>/rt/wv_downstream.py`, `<sandbox>/rt/wv_find.py` and `<sandbox>/rt/wv_same.py` (step-for-step comparison).
- **Routes** were shrunk with `<sandbox>/rt/wv_shrink.py`.
- **Rows** come from `<sandbox>/t/wv_seqrows.lua` through `<sandbox>/kt/rows_b.sh`, saved in `<sandbox>/kt/rows_b/`. The route 1 rows under the window view are the replays where the tie broke wrong (`*.hit.txt`).
- **Walk files** are `<sandbox>/rt/walks_b/<variant>-<view>-<generator>-1500-25-<seed>.jsonl`.
- **The variants** live in `<sandbox>/variants/`.
  - `kt_rewrite_win` is `kt_rewrite` plus the two rules, marked `WV` in `navigation/hooks.lua` and `window/routines.lua`.
  - `kt_rewrite_win_strict` and `kt_rewrite_win_land` change only how the cancel attaches history.
