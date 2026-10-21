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
