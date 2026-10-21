# Packet EX: "Keep the older one" where a slot changes under the current buffer

**Stakes:** I23 says no buffer is current while the note a restore would read names the buffer already in that slot. The tested fix ("Keep the older one", built as `kt_rewrite_sec`) runs the stale-note check whenever a buffer becomes current. It still broke I23 at 11 of 75,000 walk steps, and T189's ten keys still throw. Every break came at or after `<M-;><M-t>`'s exchange, where a slot changes under the current buffer and no buffer becomes current. This packet:
- finds every such place;
- runs the check at all of them;
- measures three answers to the one open question: what a stale **ternary** note becomes at `<M-;><M-t>`'s exchange.

## The whole fix

**"Keep the older one", completed.** The stale-note check runs on both maps:
1. whenever a buffer becomes current, by any key, the way the stale-note check in navigation does it, as decided ("the ternary's own note" where the ternary stays put);
2. **and wherever a slot changes under the current buffer:**
   - after both restores, after the restore's own write (`lua/cavediver/domains/window/routines.lua:759`);
   - after graduation (`:482-487`);
   - after the history fill of an empty secondary (`:488-490`);
   - after a cleanup pass that moved a window's current buffer or slots (`:142-454`).

The secondary map uses the decided rule everywhere: the current buffer's swap note when that names another buffer, otherwise dropped.

**With that, I23 held at every step in every window that never held a duplicate slot, under each of the three answers [sim]:**
- **The main walks: 0 violations and 0 restore throws** in 225,000 distinct steps per variant.
  - Seeds 7 and 11, 1,500 walks of 25 keys each.
  - One window: the same walks under either `history_view`, since with one window the two views give identical walks, step for step.
  - Several windows: under `"global"` and under `"window"`.
- **A restore-heavy key mix: 0 violations and 0 throws** in 75,000 more steps.
- **In the global view** (main and restore-heavy walks): 0 other errors, 0 hook failures, 0 duplicate slots and 0 notes naming their own buffer.
- **For comparison, on the same main walks:**
  - today's code breaks I23 at 21,548 steps (current window) and throws 804 times (46 ternary, 758 secondary);
  - the tested fix breaks it at 15 steps, plus 33 in the restore-heavy mix, where it throws 5 times.
- **The exception: a window already holding a duplicate slot.**
  - Under the window view, `<M-f>` or `<M-;><M-f>` filling an empty secondary in a new window sometimes takes the current buffer itself: 7 of 12 runs of one 8-key route, under (b) and (c) alike.
  - From then on, a note can name the slot's occupant and a restore can throw, under every variant and today's code (route in section 5).
  - It broke I23 in none of the main window-view walks for (a), (b) or (c), and in 1 to 3 steps per variant in the 150,000 steps of walks that leave a cycle open across a window jump (section 6).
  - Its fix is decided and separate: D11's fill assertion (T176), and A12 for the open cycle.

**Only one place matters in practice.** In every walk, the new check fired only at `<M-;><M-t>`'s exchange, on the ternary map.
- It never fired after `<M-;><M-r>`, after a restore without an exchange, at graduation, at the history fill or after a cleanup.
- That matches the reading of the code in section 1: those places either can't leave a stale ternary note, or the walks never reach them.
- The cleanup and the history fill are covered for completeness **[code]**. The walks never delete a file.

## The open question: what the stale ternary note becomes at `<M-;><M-t>`'s exchange

At that exchange, the old secondary moves into the ternary. When the current buffer's ternary note names it, the note becomes one of:
- **(a) the ternary's own note:** the new ternary's plain note, the same rule as "where the ternary stays put";
- **(b) the buffer that just left the ternary:** now the secondary;
- **(c) dropped.**

**Branch test.** For every firing in the deterministic walks (global view: one window, several windows, and the restore-heavy mix), the walk was replayed up to `<M-;><M-t>`, then `<M-;><M-r>`, `<M-;><M-r>`, `<M-;><M-t>` were pressed under each variant **[sim]**.
- There were 60 firings.
- In 24 of them, the current buffer has a valid swap note, and the restore reads that, not the stale plain note. All variants behave the same there.
- **The other 36 are the real I23 breaks:**

| | First `<M-;><M-r>` | Second `<M-;><M-r>` | Then `<M-;><M-t>` |
|---|---|---|---|
| tested fix (`kt_rewrite_sec`) | throws: 36 | throws: 36 | flip-flops (exchanges the slots back): 36 |
| **(a) the ternary's own note** | "No ternary relationship found": 28; **restores a buffer from outside the slots: 6**; exchanges with the secondary: 2 | the same, flip-flopping | flip-flops: 34; "No secondary relationship found": 2 (the two exchanges, as in (b)) |
| **(b) the buffer that just left the ternary** | **exchanges with the secondary, undoing `<M-;><M-t>`: 36** | exchanges again: 36 | **"No secondary relationship found": 35**; flip-flops: 1 |
| **(c) dropped** | "No ternary relationship found": 36 | the same | flip-flops: 36 |

- **(a)** gives a restore something in 6 of 36 (17%), the ternary's own note one step back. In 2 of 36 it names the window's secondary and acts like (b).
  - **It needs a guard.** The new ternary's own note can name the current buffer itself. Copied over, that would be a note naming its own buffer, and the next `<M-;><M-r>` would put the current buffer into the ternary.
  - The guard drops it instead. That happened 3 times in the 60 firings, and the route is in section 5.
  - In the other 28, there is no older note or the guard dropped it, and (a) acts like the drop.
  - The decided arrival rule ("the ternary's own note" where the ternary stays put) copies the same kind of note, so it could hit the same case **[inferred]**. KT saw no firing go to the arriving buffer itself.
- **(b)** turns `<M-;><M-r>` into an undo of `<M-;><M-t>`.
  - Pressed again, it redoes it. On the way, the tested fix's secondary check drops the current buffer's secondary note, because that note now names the new secondary. That's the cost KT found where the ternary's own note names the secondary (T188), now on every firing.
  - Then `<M-;><M-t>` finds nothing: 35 of 36. Under (a) and (c), that `<M-;><M-t>` still flip-flops.
- **(c)** never brings anything back and costs nothing else.
- **One cost is shared by all three.** The check compares the plain note, so it also rewrites or drops the 24 plain notes that sit behind a valid swap note, which I23 allows. Those notes matter only once the swap note is cleared or comes to equal the ternary.

**In ordinary walks** (same keys, same seeds, the pairs replayed step by step against (c)) **[sim]**:
- With the normal key mix, no `<M-;><M-r>` or `<M-;><M-t>` came out different between the three. Firings are rare (19 in 6,000 deterministic walks), and no walk pressed a restore that read the rewritten note.
- With the restore-heavy mix (seed 7; seed 11 had none), with the same slots before the key:
  - (a) restored an outside buffer once and exchanged once where (c) said "No ternary relationship found";
  - (b) exchanged 5 times where (c) said "No ternary relationship found";
  - the tested fix threw 5 times there.

**The same question on the secondary side.** The mirror case is a stale secondary note at `<M-;><M-r>`'s exchange. It's already decided (its swap note when that's older, otherwise dropped), and all three variants keep that rule.
- In the same deterministic walks it fired 183 times: **175 drops, 8 rewrites**.
- The rewrite rarely applies because of KT's catch: an older swap note is one the restore would read first anyway.
- **So the decided rule at the mirror exchange is, in practice, (c).** The (b)-style candidate there, the buffer that just left the secondary, is the one KT logged and didn't use: "pointing the note at it would only undo the restore's move."
- (a) is instead the ternary side's own rule for arrivals that keep the ternary.

---

**How things are cited**
- Code paths are relative to the repo, for example `lua/cavediver/domains/window/routines.lua:759`. `<sandbox>` is the test sandbox. KT and RT are the earlier packets, `<sandbox>/../packets/KT.md` and `RT.md`.
- Every walk and row here runs a copy of the plugin, never the repo itself:
  - today's code runs from the repo as it is, through `t/run.sh`, and is **[run]**;
  - a variant is a copy under `<sandbox>/variants/`, runs through `VARIANT=… t/runv.sh`, and is **[sim]**;
  - readings of the code are **[code]**.
- Rows:
  - One row per action, then the window's triquetra after it, as `⦉ternary⦊ [current] ⟦secondary⟧   dtm{…} dsm{…}`, then any message. `x>y` is x's plain note; `x-swap>y` is x's swap note.
  - «ternary note b>a becomes b>c», «… dropped» and «secondary note … becomes …» mark where a check fired. They are sandbox-only markers, not messages the plugin would show.
  - Cycling's «Checkpoint saved» message is left out. Long messages are shortened with «…».
  - When a block's first rows match the block above it, it says so and starts where they differ.
- Walks:
  - 1,500 walks of 25 keys each, seeds 7 and 11, with the same generator and key mix as KT and RT. A walk mixes `:e` on five files, `<M-f>`, `<M-S-f>`, both restores, cycling picks (`<M-m>`/`<M-n>` then `<M-v>`), `<M-;><M-c>` and `<M-;><M-f>`.
  - **Several windows** (`mw`): the generator another agent left at `<sandbox>/rt/rt_walk_b.py` (23:45) adds `:vsplit` (at most 3 windows), `<C-w>p` and `:close`. 48% of steps had 2 or 3 windows.
  - **Restore-heavy** (`rheavy`, supplementary): the same keys with three more of each restore, so `<M-;><M-r>` and `<M-;><M-t>` are each 4 in 30 instead of 1 in 24. Global view, one window.
  - The history view is set right after `setup()`, as in `t/b7w_dup.lua`.
  - I23 is checked after every step, for the current window and for every window, with the decided lookup: the swap note when it's set and isn't the slot's occupant, otherwise the plain note.
- **Runners.** Rows run through `t/run.sh` and `t/runv.sh`. Walks need a separate sandbox per job to run in parallel, so `<sandbox>/ex/` holds copies of the walk generator, its runner and its per-step scripts, with their own job directory, `<sandbox>/exjobs/`. None of the `_b` runners, `run_b` or `xdg_b` was used.
- **The copies were checked against the originals:** the tested fix's seed-7 walks, regenerated with the copies, match the spec pass's walks step for step, with the same 3 violations.

---

## 1. Where a slot changes under the current buffer

A slot changes while the current buffer stays, or a buffer becomes current without the check running. Paths are in `lua/cavediver/domains/window/routines.lua` unless named otherwise **[code]**.

**Can break I23, and the tested fix doesn't check them:**

| Place | Lines | What changes | Which map can go stale |
|---|---|---|---|
| `<M-;><M-t>`'s exchange: the restored buffer was in the ternary | `:751-754`, then `:759` | The old secondary moves into the ternary, and the old ternary into the secondary. | **The ternary map.** The current buffer's ternary note can name the old secondary (T189). The secondary map can't go stale: `:759` writes the current buffer's secondary note to the old secondary, which isn't the new one. |
| The history fill of an empty secondary (`<M-f>` or the `<M-;><M-f>` fallback, with no ternary either) | `:488-490` | The secondary takes the second most recent buffer. | The secondary map, in principle. The current buffer would need a secondary note while both slots are empty, and only a cleanup empties both. A new window starts with no notes (`lua/cavediver/domains/window/data.lua:27-41`). |
| Cleanup, the heal: the current slot's buffer is gone, and the window's buffer takes its place | `:151-158` | A buffer becomes current. A slot holding it is emptied, and the other slot stays. | Either map, in principle. |
| Cleanup, the re-points: the current buffer was deleted or its file is gone | `:193-196`, `:203-206`, `:213-214`, `:259-263`, `:431-448` | A buffer becomes current: the ternary, else the secondary, else the primary, else the most recent. Taking the ternary empties it, but the secondary stays. | The secondary map, in principle: the new current buffer's secondary note naming the secondary. |
| Session load | `lua/cavediver/domains/storage/routines.lua:257-299`, through `lua/cavediver/domains/window/init.lua:51-58` | The whole triquetra is replaced. The current slot falls back to the window's buffer when the saved one can't be restored (`storage/routines.lua:257`). | Either map, on that fallback only. Otherwise it restores a saved state as it was. Not built into the variants. |

**Can break I23, and the tested fix already checks them (the secondary map only):**

| Place | Lines | What changes | Checked in `kt_rewrite_sec` |
|---|---|---|---|
| `<M-;><M-r>`'s exchange: the restored buffer was in the secondary | `:743-745`, then `:759` | The old ternary moves into the secondary. | The secondary map, yes: the current buffer's secondary note, when it names the new secondary, becomes its swap note or is dropped. The ternary map can't go stale here: `:759` writes the current buffer's ternary note to the old ternary. |
| Graduation (`<M-f>` or the `<M-;><M-f>` fallback, with an empty secondary) | `:482-487` | The ternary moves into the secondary, and the ternary empties. | The secondary map, yes. The ternary map can't go stale: the ternary is empty. |

**Can't break I23:**

| Place | Lines | Why |
|---|---|---|
| The restores without an exchange | `:747`, `:755`, then `:759` | Only the restored slot changes, and `:759` writes that map's note to the slot's old occupant. The other slot doesn't move. |
| `<M-;><M-c>` (`set_primary`) and `<M-;><M-x>` (`toggle_primary`) | `:686-708`, `:667-680` | Only the primary queue and its switch change. No slot moves. |
| The pop-up save (`update_primary_buffer`) | `:21-77` | Only the primary queue and its switch change. |
| Cleanup emptying a slot whose file is gone | `:353-358`, `:380-385` | An empty slot can't be named. |
| A swap onto a slot whose file is gone | `:509-513`, `:576-579` | The slot empties. |
| `rename_hash_in_triquetras` | `lua/cavediver/domains/window/data.lua:113-160`, called at `:529`, `:590` | It renames a hash in the slots and the notes alike, so what named the occupant before still does, and nothing else starts to. This isn't a slot change, but it's related: it doesn't carry dsm's swap keys (`data.lua:137-140`), which is already decided (T192). |
| A new window (`:vsplit`) | `lua/cavediver/domains/window/data.lua:27-41`, via `:68-73` | It gets a fresh triquetra with no notes. |

- **The walks agree.** In every walk file of every variant, the ternary map's new check fired only at `<M-;><M-t>`'s exchange (286 firings over 42 walk files). The secondary map's new calls never fired. The tested fix's own secondary check at `<M-;><M-r>`'s exchange and at graduation fired as before.
- **Cleanup, probed [run].**
  - Two routes deleted the current buffer's file (in the sandbox's run copy only) and ran a cleanup pass (`<sandbox>/t/ex_cleanup.lua`).
  - Both times, wiping the buffer switched the window to another buffer, and the pass ended with both slots empty, so nothing could be stale.
  - The re-points that keep a slot weren't reached by a route. They stay **[code]**.

---

## 2. What was built

Three copies of the tested fix, one per answer, built by `<sandbox>/ex/mkex.py`. Each adds one sandbox-only helper to `lua/cavediver/domains/window/routines.lua`, which runs both maps' checks on the window's current buffer x:
- **Ternary map.** When x's plain ternary note names the ternary, it's rewritten by the variant's rule:

| Variant | The stale ternary note becomes |
|---|---|
| `ex_a` | (a) the new ternary's own plain note |
| `ex_b` | (b) the buffer that just left the ternary. At `<M-;><M-t>`'s exchange that is the old ternary, now the secondary. |
| `ex_c` | (c) nothing: dropped |

  - In every variant, a result naming x itself or the ternary is dropped instead (the guard). Only (a) can hit it.
  - Like KT's check, it compares x's plain note, not the swap key. A plain note behind a valid swap note gets rewritten too. The restore doesn't read it until the swap note is cleared or comes to equal the ternary.
- **Secondary map:** the tested fix's own check, unchanged: the swap note when it's older, otherwise dropped.

Where it's called, by repo line:

| Place | Repo lines | Call |
|---|---|---|
| both restores, every branch that restores | after `:759` | after the restore's own write. It passes the buffer that left the ternary, for (b). |
| graduation | after `:486` | after the tested fix's own secondary check |
| the history fill | after `:489` | |
| cleanup | after the loop (`:453`) | only for windows whose current buffer, secondary or ternary the pass changed. When the pass changed the current buffer, that's an arrival, so the ternary map uses the decided arrival rule, "the ternary's own note", in all three. |

- Session load isn't built (not exercised).
- Every firing is counted through a sandbox-only message, never shown to the user.

---

## 3. The numbers

I23 at the current window (with several windows: current window / any window), then restore throws (ternary / secondary). Seeds 7 and 11 together, 75,000 steps per cell **[run]** for today, **[sim]** otherwise. The two one-window columns are the same walks, identical step for step:

| Variant | One window, global | One window, window view | Several windows, global | Several windows, window view | Restore-heavy, one window, global |
|---|---|---|---|---|---|
| today | 10,336 · 26 / 352 | 10,336 · 26 / 352 | 5,594 / 7,964 · 10 / 204 | 5,618 / 7,991 · 10 / 202 | not run |
| `kt_rewrite_sec` | 11 · 0 / 0 | 11 · 0 / 0 | 2 / 2 · 0 / 0 | 2 / 2 · 0 / 0 | 33 · 5 / 0 |
| `ex_a` | **0** · 0 / 0 | **0** · 0 / 0 | **0 / 0** · 0 / 0 | **0 / 0** · 0 / 0 | **0** · 0 / 0 |
| `ex_b` | **0** · 0 / 0 | **0** · 0 / 0 | **0 / 0** · 0 / 0 | **0 / 0** · 0 / 0 | **0** · 0 / 0 |
| `ex_c` | **0** · 0 / 0 | **0** · 0 / 0 | **0 / 0** · 0 / 0 | **0 / 0** · 0 / 0 | **0** · 0 / 0 |

- **Every one of the tested fix's violations starts at `<M-;><M-t>`'s exchange.** Where one is counted again at a later step, it's the same violation, carried along by keys that move no slot: a throwing `<M-;><M-r>`, or `<M-;><M-c>`.
- **With one window, the two views give identical walks.** Every step matches, for all five, on both seeds, once the hashes in messages are masked (they depend on the job's path). The view only matters with several windows.
- **Firings of the new check, global view, deterministic walks:**

| Variant | One window | Several windows | Restore-heavy |
|---|---|---|---|
| `ex_a` | 14: nothing 8, outside 3, the secondary 2, guard 1 | 5: nothing 4, outside 1 | 41: nothing 29, outside 9, the secondary 1, guard 2 |
| `ex_b` | 14 | 6 | 46 |
| `ex_c` | 14 | 5 | 41 |

  - (b) fires more often because its walks diverge after the first firing. The (b) exchange keeps the old slots in play.
  - These counts include firings behind a valid swap note. Section 4's 36 are the ones the restore would read.

**Other errors, hook failures, duplicates:**
- **Global view, main and restore-heavy walks:** 0 other errors, 0 hook failures, 0 duplicate slots and 0 notes naming their own buffer, for all five variants. The open-cycle walks are in section 6.
- **Window view with several windows**, seeds 7 and 11 together:

| Variant | Other errors | Hook failures | Duplicate slots / self-naming notes |
|---|---|---|---|
| today | 4 | 0 | 110 |
| `kt_rewrite_sec` | 4 | 2 | 135 |
| `ex_a` | 3 | 0 | 62 |
| `ex_b` | 5 | 2 | 145 |
| `ex_c` | 5 | 2 | 122 |

- **They aren't this fix's.**
  - In every window, the first duplicate comes at the history fill: `<M-f>` or `<M-;><M-f>` fills an empty secondary in a new window, and the window view's order puts the current buffer second. Every later one in that window follows from it. That is the fill duplicate D11 settles with an assertion (T176).
  - The errors are "Duplicates detected in triquetra slots" (`routines.lua:115`), and the hook failures are the same throw inside the `displacement_mangement` hook (`lua/cavediver/domains/window/hooks.lua:64`). Both come after a duplicate.
- **They don't compare across variants.** Under the window view with several windows, runs aren't repeatable. Another agent is studying the window view's ties (`<sandbox>/t/wv_tie.lua`), which are the likely cause **[inferred]**.
  - The tested fix and (c) never fired the new check there, yet their walks differ in 277 of 1,500 (seed 7). The same 8 keys give the duplicate in some runs and not in others, even in the same sandbox (section 5).
  - In the global view the same pair differs in 0.
  - So the counts above vary from run to run. I23 was 0 in every one of them for (a), (b) and (c).

---

## 4. What the stale note becomes, against the drop

The branch test in "The open question", per set **[sim]**:

| Set | Firings | Behind a valid swap note | Read by the restore |
|---|---|---|---|
| one window, global, seeds 7 + 11 | 14 | 4 | 10 |
| several windows, global, seeds 7 + 11 | 5 | 3 | 2 |
| restore-heavy, seeds 7 + 11 | 41 | 17 | 24 |
| **all** | **60** | **24** | **36** |

The first `<M-;><M-r>` after each of the 36, paired with (c):

| Variant | Brings back a buffer from outside the slots | Exchanges with the secondary | "No ternary relationship found" | Throws |
|---|---|---|---|---|
| (a) `ex_a` | 6 | 2 | 28 | 0 |
| (b) `ex_b` | 0 | 36 | 0 | 0 |
| (c) `ex_c` | 0 | 0 | 36 | 0 |
| tested fix | 0 | 0 | 0 | 36 |

- For the 24 behind a valid swap note, all four give the same: the restore reads the swap note. That brings back an outside buffer 12 times and exchanges 12 times.
- Ordinary walks, step by step against (c): see "The open question". Only the restore-heavy mix showed a difference: 2 for (a), 5 for (b).

---

## 5. Rows

### The ten-key route (T189)

today [run]:
```
:e a                               ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
:e b                               ⦉a⦊ [b] ⟦-⟧   dtm{} dsm{}
:e c                               ⦉b⦊ [c] ⟦-⟧   dtm{b>a} dsm{}
<M-f>  (b graduates)               ⦉-⦊ [c] ⟦b⟧   dtm{b>a} dsm{b>a}  «…graduated.»
<M-f>                              ⦉-⦊ [b] ⟦c⟧   dtm{b>a} dsm{b>a c>b}
<M-f>                              ⦉-⦊ [c] ⟦b⟧   dtm{b>a} dsm{b>c c>b}
:e a                               ⦉c⦊ [a] ⟦b⟧   dtm{b>a} dsm{b>c c>b}
<M-f>                              ⦉c⦊ [b] ⟦a⟧   dtm{a-swap>c b>a} dsm{a>b b>c c>b}
<M-;><M-t>                         ⦉a⦊ [b] ⟦c⟧   dtm{a-swap>c b>a} dsm{a>b b>a c>b}  «Restored secondary slot to c»
<M-;><M-r>                         ⦉a⦊ [b] ⟦c⟧   dtm{a-swap>c b>a} dsm{a>b b>a c>b}  ERROR: Remembered ternary is the same as current ternary.
```

the tested fix, `kt_rewrite_sec` [sim]:
```
:e a                               ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
:e b                               ⦉a⦊ [b] ⟦-⟧   dtm{} dsm{}
:e c                               ⦉b⦊ [c] ⟦-⟧   dtm{b>a} dsm{}
<M-f>  (b graduates)               ⦉-⦊ [c] ⟦b⟧   dtm{b>a} dsm{b>a}  «…graduated.»
<M-f>                              ⦉-⦊ [b] ⟦c⟧   dtm{b>a} dsm{b>a c-swap>b}
<M-f>                              ⦉-⦊ [c] ⟦b⟧   dtm{b>a} dsm{b-swap>c b>a c-swap>b}
:e a                               ⦉c⦊ [a] ⟦b⟧   dtm{b>a} dsm{b-swap>c b>a c-swap>b}
<M-f>                              ⦉c⦊ [b] ⟦a⟧   dtm{a-swap>c b>a} dsm{a-swap>b b-swap>c b>c c-swap>b}
<M-;><M-t>                         ⦉a⦊ [b] ⟦c⟧   dtm{a-swap>c b>a} dsm{a-swap>b b-swap>c b>a c-swap>b}  «Restored secondary slot to c»
<M-;><M-r>                         ⦉a⦊ [b] ⟦c⟧   dtm{a-swap>c b>a} dsm{a-swap>b b-swap>c b>a c-swap>b}  ERROR: Remembered ternary is the same as current ternary.
-- two more keys:
<M-;><M-r>                         ⦉a⦊ [b] ⟦c⟧   dtm{a-swap>c b>a} dsm{a-swap>b b-swap>c b>a c-swap>b}  ERROR: Remembered ternary is the same as current ternary.
<M-;><M-t>                         ⦉c⦊ [b] ⟦a⟧   dtm{a-swap>c b>a} dsm{a-swap>b b-swap>c b>c c-swap>b}  «Restored secondary slot to a»
```

(a) the ternary's own note, `ex_a` [sim]. The first 8 rows are the same as the tested fix; from there:
```
<M-;><M-t>                         ⦉a⦊ [b] ⟦c⟧   dtm{a-swap>c} dsm{a-swap>b b-swap>c b>a c-swap>b}  «Restored secondary slot to c» «ternary note b>a dropped»
<M-;><M-r>                         ⦉a⦊ [b] ⟦c⟧   dtm{a-swap>c} dsm{a-swap>b b-swap>c b>a c-swap>b}  «No ternary relationship found…»
-- two more keys:
<M-;><M-r>                         ⦉a⦊ [b] ⟦c⟧   dtm{a-swap>c} dsm{a-swap>b b-swap>c b>a c-swap>b}  «No ternary relationship found…»
<M-;><M-t>                         ⦉c⦊ [b] ⟦a⟧   dtm{a-swap>c} dsm{a-swap>b b-swap>c b>c c-swap>b}  «Restored secondary slot to a»
```
- The new ternary `a` has no plain note (only `a-swap>c`), so (a) has nothing older and drops, the same as (c).

(b) the buffer that just left the ternary, `ex_b` [sim]. The first 8 rows are the same as the tested fix; from there:
```
<M-;><M-t>                         ⦉a⦊ [b] ⟦c⟧   dtm{a-swap>c b>c} dsm{a-swap>b b-swap>c b>a c-swap>b}  «Restored secondary slot to c» «ternary note b>a becomes b>c»
<M-;><M-r>                         ⦉c⦊ [b] ⟦a⟧   dtm{a-swap>c b>a} dsm{a-swap>b b-swap>c b>c c-swap>b}  «secondary note b>a becomes b>c» «Restored ternary slot to c»
-- two more keys:
<M-;><M-r>                         ⦉a⦊ [b] ⟦c⟧   dtm{a-swap>c b>c} dsm{a-swap>b b-swap>c c-swap>b}  «secondary note b>c dropped» «Restored ternary slot to a»
<M-;><M-t>                         ⦉a⦊ [b] ⟦c⟧   dtm{a-swap>c b>c} dsm{a-swap>b b-swap>c c-swap>b}  «No secondary relationship found…»
```
- `<M-;><M-r>` puts back exactly the state from before `<M-;><M-t>`, notes included.
- The second `<M-;><M-r>` redoes the exchange. The secondary check finds `b>c` naming the new secondary, and `b`'s swap note is `c` too, so it drops it. `<M-;><M-t>` is left with nothing.

(c) dropped, `ex_c` [sim]: the same rows as (a) here.

### (a) bringing back a buffer from outside the slots

Shrunk from a restore-heavy walk. The first 12 rows are the same under all four **[sim]**:
```
:e a                               ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
:e e                               ⦉a⦊ [e] ⟦-⟧   dtm{} dsm{}
:e d                               ⦉e⦊ [d] ⟦-⟧   dtm{e>a} dsm{}
<M-S-f>                            ⦉d⦊ [e] ⟦-⟧   dtm{d-swap>e e>a} dsm{}
:e b                               ⦉e⦊ [b] ⟦-⟧   dtm{d-swap>e e>d} dsm{}
:e d                               ⦉b⦊ [d] ⟦-⟧   dtm{b>e d-swap>e e>d} dsm{}
<M-n> <M-v>                        ⦉b⦊ [a] ⟦-⟧   dtm{b>e d-swap>e e>d} dsm{}
<M-f>                              ⦉-⦊ [a] ⟦b⟧   dtm{b>e d-swap>e e>d} dsm{b>e}  «…graduated.»
:e b                               ⦉-⦊ [b] ⟦a⟧   dtm{b>e d-swap>e e>d} dsm{a-swap>b b>e}
<M-f>                              ⦉-⦊ [a] ⟦b⟧   dtm{b>e d-swap>e e>d} dsm{a-swap>b b-swap>a b>e}
:e e                               ⦉a⦊ [e] ⟦b⟧   dtm{b>e d-swap>e e>d} dsm{a-swap>b b-swap>a b>e}
<M-m> <M-m> <M-v>                  ⦉a⦊ [b] ⟦e⟧   dtm{b>e d-swap>e e>d} dsm{a-swap>b b-swap>a b>a}  «secondary note b>e becomes b>a»
```
the tested fix [sim]:
```
<M-;><M-t>                         ⦉e⦊ [b] ⟦a⟧   dtm{b>e d-swap>e e>d} dsm{a-swap>b b-swap>a b>e}  «Restored secondary slot to a»
<M-;><M-r>                         ⦉e⦊ [b] ⟦a⟧   dtm{b>e d-swap>e e>d} dsm{a-swap>b b-swap>a b>e}  ERROR: Remembered ternary is the same as current ternary.
<M-;><M-r>                         ⦉e⦊ [b] ⟦a⟧   dtm{b>e d-swap>e e>d} dsm{a-swap>b b-swap>a b>e}  ERROR: Remembered ternary is the same as current ternary.
<M-;><M-t>                         ⦉a⦊ [b] ⟦e⟧   dtm{b>e d-swap>e e>d} dsm{a-swap>b b-swap>a b>a}  «Restored secondary slot to e»
```
(a) [sim]:
```
<M-;><M-t>                         ⦉e⦊ [b] ⟦a⟧   dtm{b>d d-swap>e e>d} dsm{a-swap>b b-swap>a b>e}  «Restored secondary slot to a» «ternary note b>e becomes b>d»
<M-;><M-r>                         ⦉d⦊ [b] ⟦a⟧   dtm{b>e d-swap>e e>d} dsm{a-swap>b b-swap>a b>e}  «Restored ternary slot to d»
<M-;><M-r>                         ⦉e⦊ [b] ⟦a⟧   dtm{b>d d-swap>e e>d} dsm{a-swap>b b-swap>a b>e}  «Restored ternary slot to e»
<M-;><M-t>                         ⦉a⦊ [b] ⟦e⟧   dtm{b>d d-swap>e e>d} dsm{a-swap>b b-swap>a b>a}  «Restored secondary slot to e»
```
(b) [sim]:
```
<M-;><M-t>                         ⦉e⦊ [b] ⟦a⟧   dtm{b>a d-swap>e e>d} dsm{a-swap>b b-swap>a b>e}  «Restored secondary slot to a» «ternary note b>e becomes b>a»
<M-;><M-r>                         ⦉a⦊ [b] ⟦e⟧   dtm{b>e d-swap>e e>d} dsm{a-swap>b b-swap>a b>a}  «secondary note b>e becomes b>a» «Restored ternary slot to a»
<M-;><M-r>                         ⦉e⦊ [b] ⟦a⟧   dtm{b>a d-swap>e e>d} dsm{a-swap>b b-swap>a}  «secondary note b>a dropped» «Restored ternary slot to e»
<M-;><M-t>                         ⦉e⦊ [b] ⟦a⟧   dtm{b>a d-swap>e e>d} dsm{a-swap>b b-swap>a}  «No secondary relationship found…»
```
(c) [sim]:
```
<M-;><M-t>                         ⦉e⦊ [b] ⟦a⟧   dtm{d-swap>e e>d} dsm{a-swap>b b-swap>a b>e}  «Restored secondary slot to a» «ternary note b>e dropped»
<M-;><M-r>                         ⦉e⦊ [b] ⟦a⟧   dtm{d-swap>e e>d} dsm{a-swap>b b-swap>a b>e}  «No ternary relationship found…»
<M-;><M-r>                         ⦉e⦊ [b] ⟦a⟧   dtm{d-swap>e e>d} dsm{a-swap>b b-swap>a b>e}  «No ternary relationship found…»
<M-;><M-t>                         ⦉a⦊ [b] ⟦e⟧   dtm{d-swap>e e>d} dsm{a-swap>b b-swap>a b>a}  «Restored secondary slot to e»
```
- **(a):** `b`'s note `b>e` goes stale when `e` moves into the ternary. It becomes `e`'s own note, `d`, the buffer `e` had in its ternary when you left it. `<M-;><M-r>` brings back `d` from outside the slots, and again flips back to `e`.

### (a)'s guard

Shrunk from a walk (19 keys; the shrinker removes one key at a time and found no shorter). The first 18 rows are the same under all four **[sim]**:
```
:e a                               ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
:e b                               ⦉a⦊ [b] ⟦-⟧   dtm{} dsm{}
<M-S-f>                            ⦉b⦊ [a] ⟦-⟧   dtm{b-swap>a} dsm{}
:e d                               ⦉a⦊ [d] ⟦-⟧   dtm{a>b b-swap>a} dsm{}
<M-m> <M-m> <M-v>                  ⦉a⦊ [b] ⟦-⟧   dtm{a>d b-swap>a} dsm{}  «Avoided conflict…»
<M-S-f>                            ⦉b⦊ [a] ⟦-⟧   dtm{a>d b-swap>a} dsm{}
<M-f>                              ⦉-⦊ [a] ⟦b⟧   dtm{a>d b-swap>a} dsm{}  «…graduated.»
:e e                               ⦉a⦊ [e] ⟦b⟧   dtm{a>d b-swap>a} dsm{}
:e d                               ⦉e⦊ [d] ⟦b⟧   dtm{a>d b-swap>a e>a} dsm{}
<M-m> <M-m> <M-v>                  ⦉e⦊ [a] ⟦b⟧   dtm{a>d b-swap>a e>d} dsm{}  «Avoided conflict…»
<M-;><M-c>                         ⦉e⦊ [a] ⟦b⟧  p=[a]on   dtm{a>d b-swap>a e>d} dsm{}
:e b                               ⦉e⦊ [b] ⟦a⟧  p=[a]on   dtm{a-swap>e a>d b-swap>a e>d} dsm{a-swap>b}
:e a                               ⦉e⦊ [a] ⟦b⟧  p=[a]on   dtm{a-swap>e a>d b-swap>e e>d} dsm{a-swap>b b-swap>a}
:e e                               ⦉a⦊ [e] ⟦b⟧  p=[a]on   dtm{a-swap>e a>d b-swap>e e>d} dsm{a-swap>b b-swap>a}
<M-n> <M-v>                        ⦉a⦊ [d] ⟦b⟧  p=[a]on   dtm{a-swap>e a>e b-swap>e e>d} dsm{a-swap>b b-swap>a}  «Avoided conflict…»
:e e                               ⦉d⦊ [e] ⟦b⟧  p=[a]on   dtm{a-swap>e a>e b-swap>e d>a e>a} dsm{a-swap>b b-swap>a}  «The stored ternary of the new buffer is already the ternary…»
<M-f>                              ⦉d⦊ [b] ⟦e⟧  p=[a]on   dtm{a-swap>e a>e b-swap>e d>a e-swap>d e>a} dsm{a-swap>b b-swap>a b>a e-swap>b}
<M-;><M-f>                         ⦉b⦊ [a] ⟦e⟧  p=[a]on   dtm{a-swap>e a>e b-swap>d d>a e-swap>d e>a} dsm{a-swap>b b-swap>a b>a e-swap>b}
```
the tested fix [sim]:
```
<M-;><M-t>                         ⦉e⦊ [a] ⟦b⟧  p=[a]on   dtm{a-swap>e a>e b-swap>d d>a e-swap>d e>a} dsm{a-swap>b a>e b-swap>a b>a e-swap>b}  «Restored secondary slot to b»
<M-;><M-r>                         ⦉e⦊ [a] ⟦b⟧  p=[a]on   dtm{a-swap>e a>e b-swap>d d>a e-swap>d e>a} dsm{a-swap>b a>e b-swap>a b>a e-swap>b}  ERROR: Remembered ternary is the same as current ternary.
```
(a) [sim]:
```
<M-;><M-t>                         ⦉e⦊ [a] ⟦b⟧  p=[a]on   dtm{a-swap>e b-swap>d d>a e-swap>d e>a} dsm{a-swap>b a>e b-swap>a b>a e-swap>b}  «Restored secondary slot to b» «ternary note a>e dropped (it would name a itself)»
<M-;><M-r>                         ⦉e⦊ [a] ⟦b⟧  p=[a]on   dtm{a-swap>e b-swap>d d>a e-swap>d e>a} dsm{a-swap>b a>e b-swap>a b>a e-swap>b}  «No ternary relationship found…»
```
(b) [sim]:
```
<M-;><M-t>                         ⦉e⦊ [a] ⟦b⟧  p=[a]on   dtm{a-swap>e a>b b-swap>d d>a e-swap>d e>a} dsm{a-swap>b a>e b-swap>a b>a e-swap>b}  «Restored secondary slot to b» «ternary note a>e becomes a>b»
<M-;><M-r>                         ⦉b⦊ [a] ⟦e⟧  p=[a]on   dtm{a-swap>e a>e b-swap>d d>a e-swap>d e>a} dsm{a-swap>b a>b b-swap>a b>a e-swap>b}  «secondary note a>e becomes a>b» «Restored ternary slot to b»
```
(c) [sim]:
```
<M-;><M-t>                         ⦉e⦊ [a] ⟦b⟧  p=[a]on   dtm{a-swap>e b-swap>d d>a e-swap>d e>a} dsm{a-swap>b a>e b-swap>a b>a e-swap>b}  «Restored secondary slot to b» «ternary note a>e dropped»
<M-;><M-r>                         ⦉e⦊ [a] ⟦b⟧  p=[a]on   dtm{a-swap>e b-swap>d d>a e-swap>d e>a} dsm{a-swap>b a>e b-swap>a b>a e-swap>b}  «No ternary relationship found…»
```
- After `<M-;><M-t>`, `a`'s note `a>e` names the new ternary `e`. `e`'s own note is `e>a`, so (a) taken literally writes `a>a`. The next `<M-;><M-r>` would then put `a` into the ternary while `a` is current. The guard drops it instead, which makes (a) a drop here.

### Remaining I23 violation routes

**In a window that never held a duplicate slot: none under (a), (b) or (c),** in 300,000 distinct steps each (main and restore-heavy walks), nor in the open-cycle walks **[sim]**. Under the tested fix, every violation starts at `<M-;><M-t>`'s exchange; the ten-key route and the two above are examples.

**After the history fill duplicates the current buffer**, every variant can break I23, (c) included. With several windows under the window view, `<M-f>` in a new window fills the secondary from the history. In some runs it takes the current buffer itself. Run with `t/runv.sh`, `EX_VIEW=window` and `t/ex_seqrows.lua`, its first 8 keys hit the duplicate in 7 of 12 runs: 4 of 6 under (c) and 3 of 6 under (b). Rows from one run that hit it, (c) **[sim]**:
```
:e a                               ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
:e d                               ⦉a⦊ [d] ⟦-⟧   dtm{} dsm{}
<M-f>                              ⦉-⦊ [d] ⟦a⟧   dtm{} dsm{}  «…graduated.»
:vsplit                            win2 ⦉-⦊ [d] ⟦-⟧   dtm{} dsm{}
<C-w>p                             win1 ⦉-⦊ [d] ⟦a⟧   dtm{} dsm{}
<M-f>                              win1 ⦉-⦊ [a] ⟦d⟧   dtm{} dsm{d-swap>a}
:vsplit                            win3 ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
<M-f>                              win3 ⦉-⦊ [a] ⟦a⟧   dtm{} dsm{}  «Secondary buffer populated from history.»
<M-f>                              win3 ⦉-⦊ [a] ⟦a⟧   dtm{} dsm{a-swap>a}
:e b                               win3 ⦉a⦊ [b] ⟦a⟧   dtm{} dsm{a-swap>a}
<M-f>                              win3 ⦉b⦊ [a] ⟦a⟧   dtm{b-swap>a} dsm{a-swap>a a>a b-swap>a}  ERROR: Duplicates detected in triquetra slots
<M-;><M-t>                         win3 ⦉b⦊ [a] ⟦a⟧   dtm{b-swap>a} dsm{a-swap>a a>a b-swap>a}  ERROR: Remembered secondary is the same as current secondary.
```
- Row 8: the fill puts `a`, the current buffer, into the secondary. In the other runs it takes `d`, and nothing goes wrong.
- After that, `<M-f>` swaps `a` with itself and writes `a-swap>a`. From `b`, `<M-f>` lands on `a` with `a` still in the secondary, and the notes name their own buffer (`a>a`), so the restore throws.
- None of this goes through a place in section 1. At row 8 the ordered list's first entry isn't the current buffer (walk 737 records `d, a`), so D11's decided fill assertion (T176) would throw there instead of filling.
- The walks that hit this: walk 737 of the open-cycle set (seed 11, window view; it has no open cycle) and walk 389 (through an open cycle, B7's route). Both are in `<sandbox>/ex/walks/*-window-mwy-1500-25-11.jsonl`, and the replays are in `<sandbox>/ex/rows/mwy389.*.txt` and `mwy737.*.txt`. This shorter route was cut down from walk 737 by hand and with `ex/ex_shrink.py … dupcs`.

---

## 6. Several windows with a cycle left open

The third generator in `rt/rt_walk_b.py` adds "cycle one step, then `<C-w>p`": a cycle left open across a window jump. The decided cancel (A12, P18) isn't built, so this mostly tests that bug. Same seeds, both views, 150,000 steps per variant **[sim]**:

| Variant | I23, any window: global view | I23, any window: window view | Of those, in a window that never had a duplicate slot | Restore throws (ternary / secondary) | Firings at `<M-;><M-t>`'s exchange |
|---|---|---|---|---|---|
| today | 7,302 | 7,329 | – | 10 / 355 | – |
| `kt_rewrite_sec` | 10 (ternary) | 12 (10 ternary, 2 secondary) | 20 | 0 / 1 | – |
| `ex_a` | **0** | 1 (secondary) | **0** | 0 / 0 | 14: nothing 14 |
| `ex_b` | **0** | 3 (secondary) | **0** | 0 / 1 | 14: the secondary 14 |
| `ex_c` | **0** | 1 (secondary) | **0** | 0 / 0 | 14: nothing 14 |

- **Every break left under (a), (b) or (c) is in a window that already had a duplicate slot.** In each, `<M-f>` or `<M-;><M-f>` filled an empty secondary from the history with the current buffer itself (`⦉-⦊ [e] ⟦e⟧`). Once the current buffer is also the secondary, its own secondary note can name the secondary.
  - In walk 389 of seed 11 (window view), a cycle left open in another window froze the history first. That's B7's route, which A12 (jumping windows ends the cycle) and D11's fill assertion (T176) settle.
  - Walk 737 has no open cycle. In a new window under the window view, the ordered list read `d, a` while `a` was current, so the fill took `a`.
- **In windows that never had a duplicate slot, (a), (b) and (c) give 0 I23 breaks in every set**, the open-cycle walks included. The tested fix gives 20 there, every one starting at `<M-;><M-t>`'s exchange.
- **Other errors and hook failures are the open cycle's, the same in every variant and in today's code:**
  - 247 or 248 per variant, mostly "Cycling origins not found" from `<M-;><M-f>` while the cycle belongs to another window (`routines.lua:617`);
  - "Invalid window id" from a window closed mid-cycle (`lua/cavediver/domains/window/data.lua:69`);
  - and the duplicates' own throws.

---

## Runs

| Run | What it shows | Variants |
|---|---|---|
| `t/i23_route.lua`, `t/ex_route.lua` (`EX_MORE="R S"` for the two extra keys) | the ten-key route | today, `kt_rewrite_sec`, `ex_a`, `ex_b`, `ex_c` |
| `t/ex_seqrows.lua` with `CDV_SEQ="ea ee ed G eb ed X2 F eb F ee X3 S R R S"` | (a) bringing back a buffer from outside | `kt_rewrite_sec`, `ex_a`, `ex_b`, `ex_c` |
| `t/ex_seqrows.lua` with `CDV_SEQ="ea eb G ed X3 G F ee ed X3 P eb ea ee X2 ee F J S R"` | (a)'s guard | `kt_rewrite_sec`, `ex_a`, `ex_b`, `ex_c` |
| `t/ex_cleanup.lua` (`EX_SEQ` sets the keys before the deletion) | the cleanup probe | today, `kt_rewrite_sec`, `ex_a` |
| walks: `ex/ex_walk.py 1500 25 <seed> <variants> <view> <single\|mw\|mwy>`, `ex/ex_walk_rh.py … rheavy` | the numbers | all five |

- Rows are saved in `<sandbox>/ex/rows/`. Walk files are `<sandbox>/ex/walks/<variant>-<view>-<gen>-1500-25-<seed>.jsonl`.
- The tools:
  - `ex/ex_scan.py`: I23, throws, errors, duplicates and firings, adapted from `<sandbox>/../inv_scan.py` and `kt/kt_stats.py`;
  - `ex/ex_table.py`: the tables;
  - `ex/ex_pair.py`: the walks against (c), step by step;
  - `ex/ex_branch.py`: the branch test, with its output in `ex/branch_all.txt`;
  - `ex/ex_sameview.py`: global view against window view;
  - `ex/ex_shrink.py`: route shrinking.
- The variants are built by `ex/mkex.py` from `variants/kt_rewrite_sec`.
