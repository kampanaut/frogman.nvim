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
