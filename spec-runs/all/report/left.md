**None.** No step of any walk with every fix in breaks I23 or I1, trips the fill assertion, throws, or fails a hook, under either view. So there are no rows to show.

**What the walks don't reach**, so it isn't covered here:
- **Deleting a file, and so the cleanup pass's re-points.** The stale-note check runs after the cleanup pass (section 1), but the walks never delete a file. The earlier cleanup probe found the pass ending with both slots empty (`<sandbox>/../packets/EX.md`, section 1) **[run]**.
- **Session load.** The slot-change check isn't built there, as in the base. Neither is the remaining tie in `track_buffer`'s session-load branch (`lua/cavediver/domains/history/routines.lua:214-218`, section 1) **[code]**.
- **The cancel runs straight away inside the `WinEnter`**, not "after the editor settles". A scheduled cancel would never run in walks that don't yield to the editor, so that timing isn't tested.
- **Floats and pickers** (the primary pop-up, `:help`) as the window jumped to. The walks only jump between split windows.
