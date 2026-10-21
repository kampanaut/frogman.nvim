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
