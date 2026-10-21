**Every walk set, seed and view.** Every fix is **[sim]**, and today's code is **[run]**. Today's code has no fill assertion, so its column counts the fills that would have thrown ("would").

{{TABLE}}

**Totals:**

{{TOTALS}}

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
