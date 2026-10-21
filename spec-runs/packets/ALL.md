# Every decided fix together, under both history views

**Stakes:** the fixes decided tonight were each tested in a separate copy of the plugin. This puts all of them into one copy and walks it under `history_view = "global"` and `"window"`, against today's code on the same walks. If anything still breaks I23, puts one buffer in two slots, throws, or trips the fill assertion, it shows up here.

**Is everything at zero? Yes.** With every fix in, 900,000 walk steps under both views give 0 I23 breaks, 0 I1 breaks, 0 fill assertions, 0 restore throws, 0 "Duplicates detected", and no other error or hook failure. The window-view runs now repeat exactly.

**Short answer**
- **Every fix together: all zero, under both views [sim].** The walks ran 900,000 steps: four walk sets, three seeds and two views, at 37,500 steps each. They gave:
  - 0 I23 breaks, at the current window and at any window;
  - 0 I1 breaks;
  - 0 fill assertions;
  - 0 ternary and 0 secondary restore throws;
  - 0 "Duplicates detected";
  - no other error and no hook failure.
- **The fixes were exercised, not idle.** In those walks:
  - 7,152 fills from history, each with the ordered list starting on the window's current buffer;
  - 6,638 window-jump cancels, with no step left mid-cycle;
  - 28,874 pick notes;
  - 230 firings of the stale-note check where a slot changes under the current buffer.
- **Today's code, same walks [run]:**
  - 86,286 I23 breaks at the current window (99,612 at any window);
  - 768 steps with one buffer in two slots at the current window (1,214 in any window);
  - 314 fills that would trip the assertion;
  - 370 ternary and 4,833 secondary restore throws;
  - 37 "Duplicates detected", 380 other errors and 4 hook failures.
- **Repeatable now [sim].** Two window-view sets with several windows were run three times each. With every fix, the three runs are identical step for step, and they stay identical when the file paths, and so the file hashes, change. Today's code gives different walks from run to run, in 253 to 330 of the 1,500. Each of those first differs in the ordered list alone, at a step where two buffers share an access time.
- **With one window the view changes nothing**, for either code: the global and window walks are identical step for step.

**How things are cited**
- Code paths are relative to the repo, for example `lua/cavediver/domains/history/routines.lua:191`. Line numbers are today's lines in the repo. Where a fix adds code, "after `:N`" means the new code goes right after repo line N.
- `<sandbox>` is the test sandbox. The earlier packets are in `<sandbox>/../packets/`.
- Nothing in the repo was changed. Every run uses a copy:
  - **[sim]**: the copy with every fix in, at `<sandbox>/variants/all_fixed`;
  - **[run]**: today's code, read in place from the repo;
  - **[code]**: a reading of the code, not a run.
- **Rows**, as in the earlier packets (`<sandbox>/t/fmt.lua`):
  - one row per action, then the window it ended in (`win1`, `win2`, … in the order the windows were made), then that window's triquetra `⦉ternary⦊ [current] ⟦secondary⟧   dtm{…} dsm{…}`, then any message;
  - `x>y` is x's plain note, `x-swap>y` its swap note;
  - `ordered …` is the ordered list after the action, with each buffer's access time;
  - «cycle cancelled, its window back on c» marks where the window-jump cancel ran. It's a sandbox marker, not a message the plugin shows.
- **The walks:** 1,500 walks of 25 keys per set, seeds 7, 11 and 13, each under both views.
  - **One window:** `:e` on five files, `<M-f>`, `<M-S-f>`, both restores, cycling picks (`<M-m>`/`<M-n>` then `<M-v>`), `<M-;><M-c>` and `<M-;><M-f>`. The same generator and key mix as every earlier packet.
  - **Several windows:** the same keys plus `:vsplit` (at most 3 windows), `<C-w>p` and `:close`, from `<sandbox>/rt/rt_walk_b.py`.
  - **Cycles left open across a jump:** the several-window walks plus "step the cycle once, then `<C-w>p`" without picking, from the same generator.
  - **Restore-heavy:** the one-window keys with three more of each restore, so `<M-;><M-r>` and `<M-;><M-t>` are each 4 in 30 instead of 1 in 24.
  - Seeds 7 and 11 give the same walks as the earlier packets. Seed 13 is new.
- **What's counted, after every step:**
  - **I23:** for a window's current buffer and each map, the note a restore would read (the swap note when it's set and isn't the slot's occupant, otherwise the plain note) names that slot's occupant. Counted once per map and step, as in the earlier packets: at the current window, and over every window.
  - **I1:** one buffer in two slots (current and secondary, current and ternary, or secondary and ternary). Counted as steps with one: at the current window, and in any window.
  - **Fill assertions:** `<M-f>` or the `<M-;><M-f>` fallback filling an empty secondary from history while the ordered list's first entry isn't the window's current buffer. With the fixes in, that throws. Today's code has no assertion, so its column counts the fills that would have thrown: the same test on the ordered list just before the key.
  - **Restore throws:** "Remembered ternary/secondary is the same as current …".
  - **"Duplicates detected":** thrown by `reconcile_triquetra` (`lua/cavediver/domains/window/routines.lua:115`) or caught as a hook failure (`displacement_mangement`, `lua/cavediver/domains/window/hooks.lua:64`).
  - **Other errors** and **other hook failures:** anything else thrown by a key, or any other "Hook '…' failed" message.

---

## 1. What was built: the code each fix touched

Every fix sits in one copy, built from the copy of "Keep the older one" that ran the slot-change checks with "the ternary's own note" at the slot exchange. All lines are repo lines.

**1. "Keep the older one", with the check wherever a slot changes under the current buffer.** This was already in the base. Every place it touches:

| Where | Repo lines | What the copy does there |
|---|---|---|
| plain navigation onto the secondary (`displacement_mangement`) | after `lua/cavediver/domains/window/hooks.lua:52` | Before the swap, it writes the same notes `<M-f>` writes (D8). It also runs the ternary guard (Q6's guard) when the ternary's note names the arriving buffer. |
| the same | after `window/hooks.lua:54` | After the swap: the stale-note check on the ternary map, with "the ternary's own note", since the ternary stays put. |
| plain navigation elsewhere | after `window/hooks.lua:93` | The stale-note check on the secondary map. The ternary map is the stale-note check in navigation, as today (`window/hooks.lua:71-85`). |
| helpers | after `lua/cavediver/domains/window/routines.lua:14` | The two maps' checks, and the secondary notes `<M-f>` writes. Both are sandbox-only functions. |
| a cycling pick (`reconcile_triquetra`) | after `window/routines.lua:104`, `:116`, `:119`, `:133` | The secondary map's check on the picked buffer comes first. Q6's guard runs before the swap with the secondary, and that swap marks the pick as done, so the outside-buffer branch doesn't also run. The ternary map's check comes last: `dtm[A]` for a pick of the ternary, the ternary's own note for any other pick. |
| the cleanup pass | after `window/routines.lua:143` and `:453` | It remembers every window's slots before the pass. After the pass it runs both checks in each window the pass moved. The ternary map's check uses "the ternary's own note". |
| graduation (`<M-f>` with an empty secondary) | after `window/routines.lua:485` and `:486` | It clears the graduated buffer's secondary swap note, then runs both checks. |
| the history fill | after `window/routines.lua:489` | Both checks, after the fill. |
| `<M-f>`'s notes | `window/routines.lua:496-499`, replaced | The current buffer's secondary swap note names the secondary. The arriving buffer's plain note becomes its previous partner when that's another buffer, and is cleared when it names the current buffer. The ternary swap note is written as before. |
| `<M-;><M-f>` to the primary | after `window/routines.lua:651` and `:654` | Both checks on the primary's arrival. |
| the restores | `window/routines.lua:720`, changed | The swap note is skipped when it equals the restored slot's own occupant. Today's code compares it with the ternary for both restores. |
| the same | after `window/routines.lua:740`, `:745`, `:759` | At `<M-;><M-r>`'s exchange, the secondary map's check runs. After the restore's own write, both checks run. At `<M-;><M-t>`'s exchange (the slot exchange), the current buffer's stale ternary note becomes the ternary's own note. If that would name the current buffer or the ternary itself, it's dropped instead. |

**2. The window-jump cancel, with the landing recorded.**

| Where | Repo lines | What the copy does there |
|---|---|---|
| navigation's hooks | after `lua/cavediver/domains/navigation/hooks.lua:48` | A hook on `normal`→`cycling` notes which window is cycling. A new `WinEnter` handler acts when you land in another window while a cycle is open: (1) it puts the cycling window back on its start while history is still detached, so the `BufEnter` this causes records nothing; (2) it sets navigation to `normal`; (3) it attaches history as an ordinary entry into the window you landed in, so that window's buffer is recorded even when Neovim fires no `BufEnter`. |
| the landing's reconcile | `window/routines.lua:93-135`, through the hook at `window/hooks.lua:97` | The attach in (3) runs `reconcile_triquetra` on the window you landed in. Its current slot is already that buffer, so no slot moves. A sandbox marker checks this, and it fired 0 times in the walks. |

- The cancel runs straight away inside the `WinEnter`. The decision says "after the editor settles", but the walks never hand control back to the editor between keys, so a scheduled cancel would never run in them.

**3. The fill assertion.**

| Where | Repo lines | What the copy does there |
|---|---|---|
| the history fill | after `window/routines.lua:488`, before the fill at `:489` | With an empty secondary and no ternary, `<M-f>` (and the `<M-;><M-f>` fallback, which goes the same way) throws when the ordered list's first entry isn't the window's current buffer. |

**4. The window-view tie, fixed.** Two lines in `construct_crux`:

| Repo line | Today | In the copy |
|---|---|---|
| `lua/cavediver/domains/history/routines.lua:191` | `data.history_index = data.history_index + #window_buffers - 1` | `data.history_index = data.history_index + #window_buffers` |
| `lua/cavediver/domains/history/routines.lua:194` | `global_copy[buffer.hash] = data.history_index - rank + 1` | `global_copy[buffer.hash] = data.history_index - rank` |

- A window with n buffers, entered when the next free time is i, still gives its buffers the times i to i+n−1, newest highest, so no buffer moves in the order. **[code]**
- What changes is the next free time: i+n instead of i+n−1. The next buffer recorded now ranks strictly first instead of sharing the newest buffer's time.
- `track_buffer` hands out each index once (`:210-212`), so no two buffers share a time.
- One tie is left in the code, and the walks don't reach it: `track_buffer`'s session-load branch (`:214-218`) stores the current index as the global time without moving it when the saved time is older, so the next buffer recorded shares that time. The walks never load a session, and this wasn't changed. **[code]**

**5. The Q9 pick note.** It wasn't in the base.

| Where | Repo lines | What the copy does there |
|---|---|---|
| a cycling pick of a buffer outside the slots | after `window/routines.lua:132`, in `reconcile_triquetra`'s outside-buffer branch | `dtm[picked] := start` (the current slot before the pick), and `dtm[picked-swap]` is cleared. It isn't written by the cancel's attach in fix 2. The ternary map's check that follows (after `:133`) never finds this note stale, because the start is never the ternary. |

---

## 2. Checks before the walks

Each one replays a planned test or a route from the earlier packets on the copy with every fix **[sim]**.

| Check | Planned test | Global view | Window view |
|---|---|---|---|
| The ten-key route: `<M-;><M-r>` after `<M-;><M-t>`'s exchange | T189 | passes: the stale note `b>a` is dropped at the slot exchange, and `<M-;><M-r>` finds nothing instead of throwing (the rows are the same as the base's) | the same walk |
| A jump cancels the cycle | T175 | passes: win1 is back on its start `c`, navigation is `normal`, the cycled-to buffer isn't recorded, and `:e d` in win2 moves win2's slots | passes |
| The fill's duplicate route, through a cycle left open | T176 | passes: the cancel puts win1 back, and the fill takes `c` without asserting | passes |
| The tie's shortest route | T197 | (no tie in this view) | passes in 5 of 5 replays, identical rows each time |
| Landing after a cancel | T198 | passes: the landing records `a`, and the fill takes `c` | passes |
| The pick note, against an older swap note | T172, T155 | passes: `dtm[b] = e` and no `b-swap` after the pick; `<M-;><M-r>` brings back `e`, then `d`, then `e` | the same walk |
| The same, after a `<M-S-f>` round trip | – | passes: `<M-;><M-r>` still brings back `e` | the same walk |
| The window view still re-ranks | (`t/wv_probe.lua`) | `b,d,c,a` back in win1 | `b,a,d,c` back in win1, as before the fix |

**The tie's shortest route (T197), window view, all five replays the same [sim]:**
```
:e a                       win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=1
:e b                       win1  ⦉a⦊ [b] ⟦-⟧   dtm{} dsm{}   ordered b=2 a=1
:vsplit                    win2  ⦉-⦊ [b] ⟦-⟧   dtm{} dsm{}   ordered b=2 a=1
<C-w>p                     win1  ⦉a⦊ [b] ⟦-⟧   dtm{} dsm{}   ordered b=2 a=1
:e c                       win1  ⦉b⦊ [c] ⟦-⟧   dtm{b>a} dsm{}   ordered c=5 b=4 a=3
:vsplit                    win3  ⦉-⦊ [c] ⟦-⟧   dtm{} dsm{}   ordered c=5 b=4 a=3
<M-f>                      win3  ⦉-⦊ [c] ⟦b⟧   dtm{} dsm{}   ordered c=5 b=4 a=3  «Secondary buffer populated from history.»
```
- Entering win1 with `<C-w>p` fires no `BufEnter`. The rebuild gives win1's `a` and `b` the times 3 and 4, and the next free time becomes 5. `:e c` gets 5, so it's first on its own.
- Today's code gives `b` and `c` the same time 4 at that row (`ordered b=4 c=4 a=3`). Its replays broke the tie the wrong way 3 times in 5, and those put `c` into its own secondary (`<sandbox>/../packets/WV.md`, section 5) **[run]**.

**Landing after a cancel (T198), window view [sim]** (the global view is the same, with `a=3`):
```
:e a                       win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=1
:vsplit                    win2  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=1
:e c                       win2  ⦉a⦊ [c] ⟦-⟧   dtm{} dsm{}   ordered c=2 a=1
<M-m> <C-w>p               win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}   ordered a=4 c=2  «Checkpoint saved: »  «cycle cancelled, its window back on c»
<M-f>                      win1  ⦉-⦊ [a] ⟦c⟧   dtm{} dsm{}   ordered a=4 c=2  «Secondary buffer populated from history.»
```

**The pick note (T172), global view.** With every fix [sim]:
```
:e a                       win1  ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
:e b                       win1  ⦉a⦊ [b] ⟦-⟧   dtm{} dsm{}
<M-S-f>                    win1  ⦉b⦊ [a] ⟦-⟧   dtm{b-swap>a} dsm{}
:e c                       win1  ⦉a⦊ [c] ⟦-⟧   dtm{a>b b-swap>a} dsm{}
:e d                       win1  ⦉c⦊ [d] ⟦-⟧   dtm{a>b b-swap>a c>a} dsm{}
:e e                       win1  ⦉d⦊ [e] ⟦-⟧   dtm{a>b b-swap>a c>a d>c} dsm{}
<M-n> <M-v>                win1  ⦉d⦊ [b] ⟦-⟧   dtm{a>b b>e c>a d>c} dsm{}  «Checkpoint saved: »  «pick note b>e»
<M-;><M-r>                 win1  ⦉e⦊ [b] ⟦-⟧   dtm{a>b b>d c>a d>c} dsm{}  «Restored ternary slot to: (e.txt)»
<M-;><M-r>                 win1  ⦉d⦊ [b] ⟦-⟧   dtm{a>b b>e c>a d>c} dsm{}  «Restored ternary slot to: (d.txt)»
```
Today's code [run]: the first 6 rows are the same; from there:
```
<M-n> <M-v>                win1  ⦉d⦊ [b] ⟦-⟧   dtm{a>b b-swap>a c>a d>c} dsm{}  «Checkpoint saved: »
<M-;><M-r>                 win1  ⦉a⦊ [b] ⟦-⟧   dtm{a>b b-swap>a b>d c>a d>c} dsm{}  «Restored ternary slot to: (a.txt)»
<M-;><M-r>                 win1  ⦉d⦊ [b] ⟦-⟧   dtm{a>b b-swap>a b>a c>a d>c} dsm{}  «Restored ternary slot to: (d.txt)»
```
- «pick note b>e» is a sandbox marker for where the pick note was written.
- Today's code never brings `e` back.

---

## 3. The numbers

**Every walk set, seed and view.** Every fix is **[sim]**, and today's code is **[run]**. Today's code has no fill assertion, so its column counts the fills that would have thrown ("would").

| Walk set | Seed | View | Code | I23: current window / any window | I1: current window / any window | Fill assertions | Restore throws (ternary / secondary) | "Duplicates detected" | Other errors | Hook failures |
|---|---|---|---|---|---|---|---|---|---|---|
| one window | 7 | global | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| one window | 7 | global | today | 5,150 / 5,150 | 0 / 0 | – (would: 0) | 14 / 161 | 0 | 0 | 0 |
| one window | 7 | window | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| one window | 7 | window | today | 5,150 / 5,150 | 0 / 0 | – (would: 0) | 14 / 161 | 0 | 0 | 0 |
| one window | 11 | global | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| one window | 11 | global | today | 5,186 / 5,186 | 0 / 0 | – (would: 0) | 12 / 191 | 0 | 0 | 0 |
| one window | 11 | window | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| one window | 11 | window | today | 5,186 / 5,186 | 0 / 0 | – (would: 0) | 12 / 191 | 0 | 0 | 0 |
| one window | 13 | global | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| one window | 13 | global | today | 5,159 / 5,159 | 0 / 0 | – (would: 0) | 11 / 193 | 0 | 0 | 0 |
| one window | 13 | window | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| one window | 13 | window | today | 5,159 / 5,159 | 0 / 0 | – (would: 0) | 11 / 193 | 0 | 0 | 0 |
| several windows | 7 | global | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| several windows | 7 | global | today | 2,849 / 3,889 | 0 / 0 | – (would: 0) | 3 / 104 | 0 | 0 | 0 |
| several windows | 7 | window | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| several windows | 7 | window | today | 2,854 / 3,890 | 15 / 25 | – (would: 5) | 3 / 105 | 1 | 0 | 0 |
| several windows | 11 | global | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| several windows | 11 | global | today | 2,745 / 4,075 | 0 / 0 | – (would: 0) | 7 / 100 | 0 | 0 | 0 |
| several windows | 11 | window | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| several windows | 11 | window | today | 2,756 / 4,081 | 40 / 60 | – (would: 7) | 7 / 99 | 6 | 0 | 0 |
| several windows | 13 | global | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| several windows | 13 | global | today | 2,693 / 3,876 | 0 / 0 | – (would: 0) | 3 / 86 | 0 | 0 | 0 |
| several windows | 13 | window | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| several windows | 13 | window | today | 2,706 / 3,886 | 5 / 7 | – (would: 3) | 3 / 86 | 0 | 0 | 0 |
| cycles left open across a jump | 7 | global | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| cycles left open across a jump | 7 | global | today | 2,502 / 3,576 | 97 / 173 | – (would: 43) | 3 / 86 | 0 | 57 | 2 |
| cycles left open across a jump | 7 | window | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| cycles left open across a jump | 7 | window | today | 2,500 / 3,576 | 105 / 179 | – (would: 49) | 2 / 85 | 3 | 57 | 2 |
| cycles left open across a jump | 11 | global | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| cycles left open across a jump | 11 | global | today | 2,632 / 3,726 | 75 / 153 | – (would: 39) | 2 / 92 | 2 | 64 | 0 |
| cycles left open across a jump | 11 | window | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| cycles left open across a jump | 11 | window | today | 2,634 / 3,731 | 112 / 193 | – (would: 50) | 1 / 92 | 5 | 64 | 0 |
| cycles left open across a jump | 13 | global | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| cycles left open across a jump | 13 | global | today | 2,547 / 3,497 | 143 / 183 | – (would: 55) | 4 / 75 | 7 | 69 | 0 |
| cycles left open across a jump | 13 | window | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| cycles left open across a jump | 13 | window | today | 2,560 / 3,501 | 176 / 241 | – (would: 63) | 6 / 75 | 13 | 69 | 0 |
| restore-heavy | 7 | global | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| restore-heavy | 7 | global | today | 3,856 / 3,856 | 0 / 0 | – (would: 0) | 45 / 433 | 0 | 0 | 0 |
| restore-heavy | 7 | window | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| restore-heavy | 7 | window | today | 3,856 / 3,856 | 0 / 0 | – (would: 0) | 45 / 433 | 0 | 0 | 0 |
| restore-heavy | 11 | global | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| restore-heavy | 11 | global | today | 3,810 / 3,810 | 0 / 0 | – (would: 0) | 39 / 414 | 0 | 0 | 0 |
| restore-heavy | 11 | window | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| restore-heavy | 11 | window | today | 3,810 / 3,810 | 0 / 0 | – (would: 0) | 39 / 414 | 0 | 0 | 0 |
| restore-heavy | 13 | global | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| restore-heavy | 13 | global | today | 3,993 / 3,993 | 0 / 0 | – (would: 0) | 42 / 482 | 0 | 0 | 0 |
| restore-heavy | 13 | window | every fix | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| restore-heavy | 13 | window | today | 3,993 / 3,993 | 0 / 0 | – (would: 0) | 42 / 482 | 0 | 0 | 0 |

**Totals:**

| Code | View | Steps | I23: current / any | I1: current / any | Fill assertions | Restore throws (ternary / secondary) | "Duplicates detected" | Other errors | Hook failures | Run failures |
|---|---|---|---|---|---|---|---|---|---|---|
| every fix | global | 450,000 | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 | 0 |
| every fix | window | 450,000 | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 | 0 |
| every fix | both views | 900,000 | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 | 0 |
| today | global | 450,000 | 43,122 / 49,793 | 315 / 509 | – (would: 137) | 185 / 2,417 | 9 | 190 | 2 | 0 |
| today | window | 450,000 | 43,164 / 49,819 | 453 / 705 | – (would: 177) | 185 / 2,416 | 28 | 190 | 2 | 0 |
| today | both views | 900,000 | 86,286 / 99,612 | 768 / 1,214 | – (would: 314) | 370 / 4,833 | 37 | 380 | 4 | 0 |

**What the fixes did in these walks** (three seeds and both views together) **[sim]**:

| Walk set | Fills from history (all passed the assertion) | Window-jump cancels | Pick notes | Stale-note check fired where a slot changes under the current buffer |
|---|---|---|---|---|
| one window | 0 | 0 | 7,260 | 54 |
| several windows | 3,560 | 0 | 8,326 | 30 |
| cycles left open across a jump | 3,592 | 6,638 | 8,140 | 22 |
| restore-heavy | 0 | 0 | 5,148 | 124 |
| **all** | **7,152** | **6,638** | **28,874** | **230** |

- **The fill assertion's zero isn't vacuous.** The assertion never fired. Separately, the scan's own test on the ordered list before each fill (the "would" count) gives 0 in all 7,152 of these fills, and catches 314 in today's code.
- **No fill from history happens with one window**, as in the earlier packets. The secondary and the ternary are both empty only at the start, when history holds one buffer. So the assertion is tested by the several-window sets.
- **No cancel leaves a slot behind.** The landing's reconcile moved no slot in any of the 6,638 cancels: the sandbox marker for that fired 0 times. So no cancel ever reached the outside-buffer branch, and the guard that keeps the pick note off the cancel's attach was never needed in these walks. No step ends with navigation still `cycling`. Today's code ends 29,146 steps still cycling.
- **No two buffers share an access time** in any several-window step with every fix: 0 of 675,000 steps, the repeats included. Today's code under the window view has a repeated time in 7,821 of 225,000 such steps.
- **The window view is in effect.** With several windows, it changes some window's slots or notes in 103 to 149 of every 1,500 walks against the global view. With one window it changes nothing.

---

## 4. Repeatability

**With the tie fixed, the runs repeat exactly.** The window view, seed 7, several windows and cycles left open, each run three times **[sim, run]**:

| Set | Runs compared | Every fix: walks that differ | Today's code: walks that differ |
|---|---|---|---|
| several windows | 1st and 2nd | **0** of 1,500 | 272 |
| several windows | 1st and 3rd | **0** | 283 |
| several windows | 2nd and 3rd | **0** | 253 |
| cycles left open across a jump | 1st and 2nd | **0** | 318 |
| cycles left open across a jump | 1st and 3rd | **0** | 316 |
| cycles left open across a jump | 2nd and 3rd | **0** | 330 |
| several windows, other file paths | 1st and a 4th | **0** | – |
| cycles left open across a jump, other file paths | 1st and a 4th | **0** | – |

- **"Differ"** means any field of any step: the slots and notes of every window, the shown buffer, navigation and history states, the ordered list with its access times, messages and errors. File hashes inside messages are masked.
- **Every run kept the same file paths, so the same file hashes**, except the "other file paths" runs, which moved every walk to another folder. Those still match step for step, so no walk here depends on the order Lua happens to visit the hashes in.
- **Today's code drifts.**
  - In every walk where two of its runs differ, they first differ in the ordered list alone, at a step where two buffers share an access time. That held for 1,772 of 1,772, over all six pairs of runs.
  - Its counts drift with it. On the several-window set: steps with a buffer in two slots in any window, 25, 32 and 7; fills that would assert, 5, 7 and 3.
- **What this settles:** the earlier window-view counts that wouldn't repeat came from the tie. With the tie fixed, a window-view walk is a fixed function of its keys.

---

## 5. Against today's code

Three seeds and both views together, 225,000 steps per cell. Every fix is **[sim]**, and today's code is **[run]**:

| Walk set | Code | I23: current / any window | I1: current / any window | Fill assertions | Restore throws (ternary / secondary) | "Duplicates detected" | Other errors | Hook failures |
|---|---|---|---|---|---|---|---|---|
| one window | every fix | **0 / 0** | **0 / 0** | **0** | **0 / 0** | **0** | **0** | **0** |
| one window | today | 30,990 / 30,990 | 0 / 0 | would: 0 | 74 / 1,090 | 0 | 0 | 0 |
| several windows | every fix | **0 / 0** | **0 / 0** | **0** | **0 / 0** | **0** | **0** | **0** |
| several windows | today | 16,603 / 23,697 | 60 / 92 | would: 15 | 26 / 580 | 7 | 0 | 0 |
| cycles left open across a jump | every fix | **0 / 0** | **0 / 0** | **0** | **0 / 0** | **0** | **0** | **0** |
| cycles left open across a jump | today | 15,375 / 21,607 | 708 / 1,122 | would: 299 | 18 / 505 | 30 | 380 | 4 |
| restore-heavy | every fix | **0 / 0** | **0 / 0** | **0** | **0 / 0** | **0** | **0** | **0** |
| restore-heavy | today | 23,318 / 23,318 | 0 / 0 | would: 0 | 252 / 2,658 | 0 | 0 | 0 |

**What today's code breaks on, by kind.** The routes are the earlier packets'.
- **I23 and the restore throws:** a note left naming the slot's occupant, by every route in the earlier packets.
- **I1, "Duplicates detected" and the fills that would assert:**
  - Under the window view with several windows: the tie. Under the global view with several windows, today's code has none.
  - With cycles left open: the cycle leaking across windows, under both views.
  - "Duplicates detected" breaks down as:
    - 21 hook failures in `displacement_mangement` (`lua/cavediver/domains/window/hooks.lua:64`);
    - 14 throws from `reconcile_triquetra` (`lua/cavediver/domains/window/routines.lua:115`);
    - 2 failures of the same throw, caught in a hook.
- **The 380 other errors:** all are "This should not happen. Cycling origins not found for window" (`lua/cavediver/domains/window/routines.lua:617`), from `<M-;><M-f>` pressed in a window that isn't the one cycling.
- **The 4 hook failures:** all come from one walk (seed 7), 2 under each view. Its last key, `:close`, fails `winenter_update_history_view` and `update_ui_state` with "Invalid window id" (`lua/cavediver/domains/window/data.lua:69`). Earlier in that walk, a cycle was left open across a jump, and a `:vsplit` and a pick followed while it was open. With every fix, the same walk cancels that cycle and has no failure.

**Today's walks match the earlier packets' walk files step for step** wherever the two overlap under the global view: one window, several windows and cycles left open, seeds 7 and 11, 9,000 of 9,000 walks. So do the counts:
- several windows, seeds 7 and 11: I23 5,594 at the current window and 7,964 at any window, with 10 ternary and 204 secondary throws, as in `<sandbox>/../packets/EX.md`, section 3;
- one window, seed 7: 14 ternary and 161 secondary throws, as in `<sandbox>/../packets/WV.md`, section 2.

---

## 6. Breaks and throws left

**None.** No step of any walk with every fix in breaks I23 or I1, trips the fill assertion, throws, or fails a hook, under either view. So there are no rows to show.

**What the walks don't reach**, so it isn't covered here:
- **Deleting a file, and so the cleanup pass's re-points.** The stale-note check runs after the cleanup pass (section 1), but the walks never delete a file. The earlier cleanup probe found the pass ending with both slots empty (`<sandbox>/../packets/EX.md`, section 1) **[run]**.
- **Session load.** The slot-change check isn't built there, as in the base. Neither is the remaining tie in `track_buffer`'s session-load branch (`lua/cavediver/domains/history/routines.lua:214-218`, section 1) **[code]**.
- **The cancel runs straight away inside the `WinEnter`**, not "after the editor settles". A scheduled cancel would never run in walks that don't yield to the editor, so that timing isn't tested.
- **Floats and pickers** (the primary pop-up, `:help`) as the window jumped to. The walks only jump between split windows.

**Is everything at zero? Yes.** With every fix in, 900,000 walk steps under both views give 0 I23 breaks, 0 I1 breaks, 0 fill assertions, 0 restore throws, 0 "Duplicates detected", and no other error or hook failure. The window-view runs now repeat exactly.

---

## Runs

| Run | What it shows | Code |
|---|---|---|
| `<sandbox>/all/all_walk.py 1500 25 <seed> all_fixed,today <view> <single\|mw\|mwy\|rheavy>`, through `<sandbox>/all/run_matrix.sh` | the numbers, seeds 7, 11 and 13, both views | every fix, today's code |
| the same with `ALL_TAG=.r2` and `.r3`, seed 7, window view, `mw` and `mwy` | repeatability | every fix, today's code |
| the same with `ALL_TAG=.p2 ALL_JOBPFX=other-path-` (other job folders, so other file hashes) | repeatability across file paths | every fix |
| `t/ex_route.lua` with `EX_MORE="R S"` | the ten-key route (T189) | every fix |
| `t/wv_jump.lua`, `t/wv_dup.lua`, `CDV_VIEW=global` and `window` | T175, T176 | every fix |
| `t/wv_seqrows.lua` with `CDV_SEQ="ea eb SP WP ec SP F"`, `CDV_VIEW=window`, `CDV_TIMES=1`, 5 times | the tie's shortest route (T197) | every fix |
| `t/wv_seqrows.lua` with `CDV_SEQ="ea SP ec Y1 F"`, both views, `CDV_TIMES=1` | landing after a cancel (T198) | every fix |
| `t/all_q9.lua` (`ALL_TOGGLE=1` for the round trip); `t/wv_seqrows.lua` with `CDV_SEQ="ea eb G ec ed ee X2 R R"` | the pick note (T172, T155) | every fix, today's code |
| `t/wv_probe.lua`, both views | the window view still re-ranks | every fix |

- `t/…` runs go through `<sandbox>/t/runv.sh` with `VARIANT=<sandbox>/variants/all_fixed`, or `<sandbox>/t/run.sh` for today's code.
- **The walk tooling** is in `<sandbox>/all/`:
  - `all_walk.py` is the earlier packets' generator, unchanged, with every walk set in one script. Seeds 7 and 11 draw the same walks as before.
  - Each walk runs in its own job folder, `<sandbox>/alljobs/<code>-<view>-<set>-<seed>-<walk>`. A re-run uses the same paths, and so the same file hashes.
  - `all_runseq.sh` runs one walk, through the earlier per-step scripts `<sandbox>/ex/ex_seq.lua` (one window) and `<sandbox>/ex/ex_seq_mw.lua` (several windows).
  - `all_scan.py` does the counts, reusing the earlier scan's I23 lookup (`<sandbox>/ex/ex_scan.py`).
  - `all_table.py` builds the tables.
  - `all_cmp.py` does the step-for-step comparisons.
- **The tooling was checked against the earlier runs.** Under the global view, today's code matches the earlier packets' walk files step for step in every set they share: one window, several windows and cycles left open, seeds 7 and 11, 9,000 of 9,000 walks.
- **Walk files:** `<sandbox>/all/walks/<code>-<view>-<set>-1500-25-<seed>[.r2|.r3|.p2].jsonl`, where `<code>` is `all_fixed` or `today`, and `<set>` is `single`, `mw`, `mwy` or `rheavy`.
