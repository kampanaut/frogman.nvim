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
