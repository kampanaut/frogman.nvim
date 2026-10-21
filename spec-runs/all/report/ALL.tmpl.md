# Every decided fix together, under both history views

**Stakes:** the fixes decided tonight were each tested in a separate copy of the plugin. This puts all of them into one copy and walks it under `history_view = "global"` and `"window"`, against today's code on the same walks. If anything still breaks I23, puts one buffer in two slots, throws, or trips the fill assertion, it shows up here.

{{ONELINE}}

**Short answer**
{{SHORT}}

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

{{CODE}}

---

## 2. Checks before the walks

Each one replays a planned test or a route from the earlier packets on the copy with every fix **[sim]**.

{{CHECKS}}

---

## 3. The numbers

{{NUMBERS}}

---

## 4. Repeatability

{{REPEAT}}

---

## 5. Against today's code

{{TODAY}}

---

## 6. Breaks and throws left

{{LEFT}}

---

## Runs

{{RUNS}}
