# Packet KT: "Keep the older one", tested on the ternary side

**Stakes:** The decision "Keep the older one" says: on every arrival, on both sides, a stale note is **rewritten** to the buffer from before, the way the stale-note check in navigation does it, not dropped. This packet tests the ternary half before it counts as settled. Does it take the leftover `<M-;><M-r>` throws to zero? What does the restore bring back instead? What does the rewrite cost? It also tests the secondary half on the arrivals that the secondary fix doesn't cover (section 6).

**Short answer**
- **As worded, the ternary half has a gap.** On arrivals that keep the ternary, navigation's second case ("the pre-jump ternary") names the same buffer the stale note already names, so the rewrite changes nothing. These are `<M-f>`, its `<M-;><M-f>` fallback, plain `:e` onto the secondary, and picks of the secondary or of an outside buffer. Taken literally, the throws go from 14 to 11 on seed 7 and from 13 to 8 on seed 11.
- **With one reading made explicit, it holds.** Where the ternary stays put, the older one is read as the kept ternary's own plain note. Everywhere else, navigation's two cases apply as worded. When there is a ternary, that is what navigation's two cases already amount to: the plain note of the buffer the stale note named (section 1). This reading is the session's, and it needs the author's yes. With it, there are 0 ternary throws and 0 secondary throws on both seeds. Nothing else changes for the worse either: no other error, no hook failure, no duplicate slot, and no note naming its own buffer. Where the drop said "No ternary relationship found", the restore now brings a buffer back.
- **What it costs.**
  - 302 of 714 firings (42%) find no older note, so they end up as drops anyway.
  - 39 (5%) rewrite the note to the window's own secondary. The restore then just exchanges the ternary and the secondary. On the way, the current buffer can lose its secondary note, which dropping would have kept (section 4).
- **The secondary half barely matters as built.** The only older partner on record is the buffer's own swap note, and the restore already reads that first. A rewrite was possible in 122 of 497 firings, and it changed one restore in 3,000 walks (section 6).

**How things are cited**
- Code paths are relative to the repo, for example `lua/cavediver/domains/window/routines.lua:738`. `<sandbox>` is the test sandbox. RT is the earlier packet, `<sandbox>/../packets/RT.md`.
- Every run here uses a variant, a copy of the plugin under `<sandbox>/variants/`, never the repo. So every result is **[sim]**. Readings of the code are **[code]**.
- Rows:
  - One row per action, then the window's triquetra after it, as `⦉ternary⦊ [current] ⟦secondary⟧   dtm{…} dsm{…}`, then any message.
  - `x>y` is x's plain note; `x-swap>y` is x's swap note.
  - «rewrite: …» and «drop: …» mark where the tested change fired. It is a sandbox-only counter, not a message the plugin would show.
  - When a block's first rows match the block above it, it says so and starts where they differ.
- Random walks:
  - 1,500 walks of 25 keys each, with the same generator, key mix and tooling as RT (`<sandbox>/rt/rt_walk.py 1500 25 <seed>`), run on seeds 7 and 11.
  - A walk mixes `:e` on five files, `<M-f>`, `<M-S-f>`, both restores, cycling picks (`<M-m>`/`<M-n>` then `<M-v>`), `<M-;><M-c>` and `<M-;><M-f>`.

---

## 1. What was built

**The base** is RT's `variants/rt_c3kga`, which adds two things to today's code:
- the "partner change" fix for the secondary, with its check on every arrival;
- the decided changes RT built on: the conflict check («Avoided conflict…») on all four routes onto the secondary, and plain `:e` onto the secondary writing `<M-f>`'s notes.

Its every-arrival check **drops** a stale secondary note. It took the secondary throws to 0 and left 14 ternary throws (seed 7).

**The stale-note check in navigation**, today (`lua/cavediver/domains/window/hooks.lua:71-85`) **[code]**:
- **When it fires.** You arrive at N by plain navigation from A, and N's plain ternary note names A, which is about to become the ternary.
- **What it writes.** It rewrites N's note to `dtm[A]` ("the pre-jump stored ternary") if N was the ternary. Otherwise it writes T, the pre-jump ternary.
- **When there is a ternary, both cases are the same rule.** In the second case, navigation has just written `dtm[A] := T` (`hooks.lua:66-68`). So in both cases N's note becomes **A's own plain note**: the note of the buffer that the stale note named. One step further back.
- With no ternary, the second case writes nothing and the note is dropped.

**The arrivals that skip it, and what `kt_rewrite` writes there.** N's plain note is checked against the ternary the window will have after the arrival:

| Arrival | Ternary after | When N's note names it, N's note becomes |
|---|---|---|
| `<M-S-f>`; a pick of the ternary; a primary jump onto the ternary | A, the buffer left | `dtm[A]`: navigation's first case, as worded |
| a primary jump onto any other buffer | A | T, the pre-jump ternary: navigation's second case, as worded. This can differ from A's plain note, because the jump writes A's swap note (`routines.lua:652`), not its plain note. |
| `<M-f>`; its `<M-;><M-f>` fallback; plain `:e` onto the secondary; a pick of the secondary; a pick of an outside buffer | T, unchanged | `dtm[T]`, the kept ternary's own plain note. Navigation's second case as worded would write T again, the stale value. |

- **The same condition.** It checks only the plain note `dtm[N]`, not the swap key, against the buffer that will be N's ternary after the arrival.
- **The same order.** It runs after the arrival's own writes, as navigation's does, and so after the conflict check («Avoided conflict…», `routines.lua:123-131`), which rewrites the ternary's own note when that note names the arriving buffer.
  - Reading the ternary's note before that check would give `dtm[N] := N` for two buffers whose notes name each other **[inferred]**.
- **Never twice.** It never runs on navigation's own branch. In the walks, no step fired it twice, and no step fired it together with navigation's own check **[sim]**.
  - `<M-f>`, `<M-S-f>` and primary jumps set the slots before switching the buffer, so navigation's hook finds nothing to do **[code]**.
  - Picks return through `reconcile_triquetra`'s own hook, not navigation's.
  - Plain `:e` onto the secondary runs in the hook's other branch (`hooks.lua:52-54`), where navigation's check doesn't run **[code]**.
- **No message.** It is counted, never shown to the user.

**The variants**

| Variant | What it is |
|---|---|
| `rt_c3kga` | RT's base, above. No ternary rewrite. |
| `rt_tb` | RT's drop: drops the stale note on `reconcile_triquetra` arrivals and on plain `:e` onto the secondary. It's built on a different base, with neither the secondary fix nor `<M-f>`'s notes on plain `:e`, so its secondary throws are not a cost of dropping. It never covers primary jumps: `jump_to_primary` sets the current slot before it calls `reconcile_triquetra`, which then does nothing (`routines.lua:651-659`) **[code]**. |
| `kt_literal` | `rt_c3kga` plus the rewrite, with navigation's two cases taken as worded. |
| `kt_rewrite` | `rt_c3kga` plus the rewrite as in the table: "Keep the older one", ternary half. |
| `kt_drop` | `rt_c3kga` plus the same call sites, dropping instead of rewriting. This is the drop on the same base, so the two can be compared step by step on the same walks. |
| `kt_rewrite_sec` | `kt_rewrite` plus the secondary half (section 6). |

---

## 2. The numbers

Seeds 7 and 11, 1,500 walks each **[sim]**. "Fired" counts how many times the variant's check found a stale note.

| Variant | Seed | Ternary throws (walks) | Secondary throws (walks) | Other errors, hook failures | Ternary check fired | → a buffer | → the secondary | → nothing | → unchanged | Secondary check: rewrite / drop |
|---|---|---|---|---|---|---|---|---|---|---|
| `rt_c3kga` | 7 | 14 (14) | 0 (0) | 0 | – | – | – | – | – | not counted (drops) |
| `rt_c3kga` | 11 | 13 (12) | 0 (0) | 0 | – | – | – | – | – | not counted (drops) |
| `rt_tb` | 7 | 0 (0) | 161 (147) | 0 | 313 (drops) | – | – | – | – | – |
| `rt_tb` | 11 | 0 (0) | 191 (168) | 0 | 345 (drops) | – | – | – | – | – |
| `kt_literal` | 7 | 11 (11) | 0 (0) | 0 | 404 | 34 | 4 | 30 | 336 | not counted (drops) |
| `kt_literal` | 11 | 8 (8) | 0 (0) | 0 | 436 | 43 | 10 | 27 | 356 | not counted (drops) |
| `kt_rewrite` | 7 | 0 (0) | 0 (0) | 0 | 340 | 163 | 13 | 164 | 0 | not counted (drops) |
| `kt_rewrite` | 11 | 0 (0) | 0 (0) | 0 | 374 | 210 | 26 | 138 | 0 | not counted (drops) |
| `kt_drop` | 7 | 0 (0) | 0 (0) | 0 | 334 (drops) | – | – | 334 | – | not counted (drops) |
| `kt_drop` | 11 | 0 (0) | 0 (0) | 0 | 364 (drops) | – | – | 364 | – | not counted (drops) |
| `kt_rewrite_sec` | 7 | 0 (0) | 0 (0) | 0 | 341 | 163 | 13 | 165 | 0 | 60 / 182 |
| `kt_rewrite_sec` | 11 | 0 (0) | 0 (0) | 0 | 374 | 210 | 26 | 138 | 0 | 62 / 193 |

- Duplicate slots and notes naming their own buffer: 0 in every row. Every step of every walk was scanned.
- In `rt_c3kga`, `kt_literal`, `kt_rewrite` and `kt_drop`, the secondary check drops without being counted. `kt_rewrite_sec` counts it.
- `rt_tb`'s secondary throws come from its base (section 1).
- **The literal reading.** `kt_literal`'s "unchanged" firings are the arrivals that keep the ternary. There the rewrite writes back the stale value, and every throw that remains comes through one of them (section 5).
- **The 0 is not specific to seed 7.** Seed 11 also gives 0, over 374 firings.

Where `kt_rewrite` fired, both seeds together **[sim]**:

| Arrival | Rule | → a buffer | → the secondary | → nothing | Total |
|---|---|---|---|---|---|
| `<M-f>` | the kept ternary's own note | 119 | 8 | 96 | 223 |
| pick of an outside buffer | the kept ternary's own note | 71 | 15 | 72 | 158 |
| plain `:e` onto the secondary | the kept ternary's own note | 71 | 4 | 49 | 124 |
| `<M-S-f>` | navigation's first case | 22 | 9 | 26 | 57 |
| pick of the secondary | the kept ternary's own note | 27 | 1 | 26 | 54 |
| `<M-;><M-f>` falling back to `<M-f>` | the kept ternary's own note | 21 | 1 | 16 | 38 |
| primary jump | navigation's second case | 27 | 0 | 8 | 35 |
| pick of the ternary | navigation's first case | 15 | 1 | 9 | 25 |
| **all** | | **373** | **39** | **302** | **714** |

- No firing went to the arriving buffer itself.
- For scale: in the same walks, the stale-note check in navigation fired 357 and 332 times.

**Against the drop, on the same walks** (`kt_rewrite` vs `kt_drop`, both seeds; every `<M-;><M-r>` whose result differs) **[sim]**:

| `kt_rewrite` | `kt_drop` | Count |
|---|---|---|
| restores a buffer that was in none of the slots | "No ternary relationship found" | 21 |
| restores the window's secondary, exchanging the two slots | "No ternary relationship found" | 3 |
| restores one buffer | restores another (the walks had already diverged) | 1 |
| no restore, or a throw | restores | 0 |

---

## 3. RT's two routes, replayed

**Route 1** (`rt_bonus1`): `e` was left by navigation with the note `e>c`, then graduated. `<M-f>` brings `e` back while `c` stays the ternary **[sim]**:

secondary fix, no ternary rewrite [sim]:
```
:e a                               ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
:e c                               ⦉a⦊ [c] ⟦-⟧   dtm{} dsm{}
:e e                               ⦉c⦊ [e] ⟦-⟧   dtm{c>a} dsm{}
:e b                               ⦉e⦊ [b] ⟦-⟧   dtm{c>a e>c} dsm{}
<M-f>                              ⦉-⦊ [b] ⟦e⟧   dtm{c>a e>c} dsm{e>c}  «…graduated.»
:e c                               ⦉b⦊ [c] ⟦e⟧   dtm{c>a e>c} dsm{e>c}
<M-S-f>                            ⦉c⦊ [b] ⟦e⟧   dtm{c-swap>b c>a e>c} dsm{e>c}
<M-f>                              ⦉c⦊ [e] ⟦b⟧   dtm{b-swap>c c-swap>b c>a e>c} dsm{b-swap>e e>c}
<M-;><M-r>                         ⦉c⦊ [e] ⟦b⟧   dtm{b-swap>c c-swap>b c>a e>c} dsm{b-swap>e e>c}  ERROR: Remembered ternary is the same as current ternary.
```
RT's drop [sim]: the first 7 rows are the same as secondary fix, no ternary rewrite [sim]; from there:
```
<M-f>                              ⦉c⦊ [e] ⟦b⟧   dtm{b-swap>c c-swap>b c>a} dsm{b>e e>c}  «drop: note dropped»
<M-;><M-r>                         ⦉c⦊ [e] ⟦b⟧   dtm{b-swap>c c-swap>b c>a} dsm{b>e e>c}  «No ternary relationship found…»
```
rewrite as worded [sim]: the first 7 rows are the same as secondary fix, no ternary rewrite [sim]; from there:
```
<M-f>                              ⦉c⦊ [e] ⟦b⟧   dtm{b-swap>c c-swap>b c>a e>c} dsm{b-swap>e e>c}  «rewrite: e>c kept as is»
<M-;><M-r>                         ⦉c⦊ [e] ⟦b⟧   dtm{b-swap>c c-swap>b c>a e>c} dsm{b-swap>e e>c}  ERROR: Remembered ternary is the same as current ternary.
```
Keep the older one [sim]: the first 7 rows are the same as secondary fix, no ternary rewrite [sim]; from there:
```
<M-f>                              ⦉c⦊ [e] ⟦b⟧   dtm{b-swap>c c-swap>b c>a e>a} dsm{b-swap>e e>c}  «rewrite: e>c becomes e>a»
<M-;><M-r>                         ⦉a⦊ [e] ⟦b⟧   dtm{b-swap>c c-swap>b c>a e>c} dsm{b-swap>e e>c}  «Restored ternary slot to a»
```

- **What it brings back:** `a`, the kept ternary `c`'s own note, one step further back. Pressing it again brings `c` back (flip-flop):
```
<M-;><M-r>                         ⦉c⦊ [e] ⟦b⟧   dtm{b-swap>c c-swap>b c>a e>a} dsm{b-swap>e e>c}  «Restored ternary slot to c»
```
- **Compared with the drop:** `rt_tb` drops the note and says "No ternary relationship found".
- `rt_tb`'s `dsm` differs from the others because of its base (section 1). The ternary notes, `dtm`, are the ones that matter here.
- **Taken as worded,** the rewrite writes `e>c` back, and the throw stays.

**Route 2** (`rt_bonus2`): `d` was left with the note `d>a`, then came back by `<M-S-f>` from `a` **[sim]**:

secondary fix, no ternary rewrite [sim]:
```
:e a                               ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
:e d                               ⦉a⦊ [d] ⟦-⟧   dtm{} dsm{}
:e c                               ⦉d⦊ [c] ⟦-⟧   dtm{d>a} dsm{}
<M-;><M-f>                         ⦉-⦊ [c] ⟦d⟧   dtm{d>a} dsm{d>a}  «…graduated.»
<M-f>                              ⦉-⦊ [d] ⟦c⟧   dtm{d>a} dsm{c-swap>d d>a}
:e a                               ⦉d⦊ [a] ⟦c⟧   dtm{d>a} dsm{c-swap>d d>a}
<M-S-f>                            ⦉a⦊ [d] ⟦c⟧   dtm{a-swap>d d>a} dsm{c-swap>d d>a}
<M-;><M-r>                         ⦉a⦊ [d] ⟦c⟧   dtm{a-swap>d d>a} dsm{c-swap>d d>a}  ERROR: Remembered ternary is the same as current ternary.
```
RT's drop [sim]: the first 4 rows are the same as secondary fix, no ternary rewrite [sim]; from there:
```
<M-f>                              ⦉-⦊ [d] ⟦c⟧   dtm{d>a} dsm{c>d d>a}
:e a                               ⦉d⦊ [a] ⟦c⟧   dtm{d>a} dsm{c>d d>a}
<M-S-f>                            ⦉a⦊ [d] ⟦c⟧   dtm{a-swap>d} dsm{c>d d>a}  «drop: note dropped»
<M-;><M-r>                         ⦉a⦊ [d] ⟦c⟧   dtm{a-swap>d} dsm{c>d d>a}  «No ternary relationship found…»
```
Keep the older one [sim]: the first 6 rows are the same as secondary fix, no ternary rewrite [sim]; from there:
```
<M-S-f>                            ⦉a⦊ [d] ⟦c⟧   dtm{a-swap>d} dsm{c-swap>d d>a}  «rewrite: d>a, no older note, so dropped»
<M-;><M-r>                         ⦉a⦊ [d] ⟦c⟧   dtm{a-swap>d} dsm{c-swap>d d>a}  «No ternary relationship found…»
```

- **What it brings back:** nothing, the same as the drop. Navigation's first case copies `a`'s own plain note, and `a` has none.
- **Navigation does the same here.** Coming back by `:e d` instead of `<M-S-f>` gives the same result, through the stale-note check in navigation itself, which no variant changes:

secondary fix, no ternary rewrite [sim]:
```
:e a                               ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
:e d                               ⦉a⦊ [d] ⟦-⟧   dtm{} dsm{}
:e c                               ⦉d⦊ [c] ⟦-⟧   dtm{d>a} dsm{}
<M-;><M-f>                         ⦉-⦊ [c] ⟦d⟧   dtm{d>a} dsm{d>a}  «…graduated.»
<M-f>                              ⦉-⦊ [d] ⟦c⟧   dtm{d>a} dsm{c-swap>d d>a}
:e a                               ⦉d⦊ [a] ⟦c⟧   dtm{d>a} dsm{c-swap>d d>a}
:e d                               ⦉a⦊ [d] ⟦c⟧   dtm{} dsm{c-swap>d d>a}  «The stored ternary of the new buffer is already the ternary…»
<M-;><M-r>                         ⦉a⦊ [d] ⟦c⟧   dtm{} dsm{c-swap>d d>a}  «No ternary relationship found…»
```

**A third route, through a pick of an outside buffer** (`kt_pickout`, shrunk from a walk). This is where the rewrite and the drop differ most often in the walks **[sim]**:

secondary fix, no ternary rewrite [sim]:
```
:e a                               ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
:e e                               ⦉a⦊ [e] ⟦-⟧   dtm{} dsm{}
:e c                               ⦉e⦊ [c] ⟦-⟧   dtm{e>a} dsm{}
<M-n> <M-v>                        ⦉e⦊ [a] ⟦-⟧   dtm{e>c} dsm{}  «Avoided conflict…»
<M-f>                              ⦉-⦊ [a] ⟦e⟧   dtm{e>c} dsm{e>c}  «…graduated.»
:e c                               ⦉a⦊ [c] ⟦e⟧   dtm{e>c} dsm{e>c}
<M-m> <M-v>                        ⦉c⦊ [a] ⟦e⟧   dtm{c-swap>a e>c} dsm{e>c}
<M-m> <M-v>                        ⦉a⦊ [c] ⟦e⟧   dtm{a-swap>c c-swap>a e>c} dsm{e>c}
:e e                               ⦉a⦊ [e] ⟦c⟧   dtm{a-swap>c c-swap>a e>c} dsm{c-swap>e}
<M-m> <M-v>                        ⦉a⦊ [c] ⟦e⟧   dtm{a-swap>c c-swap>a e>c} dsm{c-swap>e}
:e b                               ⦉c⦊ [b] ⟦e⟧   dtm{a-swap>c c>a e>c} dsm{c-swap>e}
<M-f>                              ⦉c⦊ [e] ⟦b⟧   dtm{a-swap>c b-swap>c c>a e>c} dsm{b-swap>e c-swap>e}
<M-;><M-r>                         ⦉c⦊ [e] ⟦b⟧   dtm{a-swap>c b-swap>c c>a e>c} dsm{b-swap>e c-swap>e}  ERROR: Remembered ternary is the same as current ternary.
<M-;><M-r>                         ⦉c⦊ [e] ⟦b⟧   dtm{a-swap>c b-swap>c c>a e>c} dsm{b-swap>e c-swap>e}  ERROR: Remembered ternary is the same as current ternary.
```
rewrite as worded [sim]: the first 11 rows are the same as secondary fix, no ternary rewrite [sim]; from there:
```
<M-f>                              ⦉c⦊ [e] ⟦b⟧   dtm{a-swap>c b-swap>c c>a e>c} dsm{b-swap>e c-swap>e}  «rewrite: e>c kept as is»
<M-;><M-r>                         ⦉c⦊ [e] ⟦b⟧   dtm{a-swap>c b-swap>c c>a e>c} dsm{b-swap>e c-swap>e}  ERROR: Remembered ternary is the same as current ternary.
<M-;><M-r>                         ⦉c⦊ [e] ⟦b⟧   dtm{a-swap>c b-swap>c c>a e>c} dsm{b-swap>e c-swap>e}  ERROR: Remembered ternary is the same as current ternary.
```
drop, same base [sim]: the first 11 rows are the same as secondary fix, no ternary rewrite [sim]; from there:
```
<M-f>                              ⦉c⦊ [e] ⟦b⟧   dtm{a-swap>c b-swap>c c>a} dsm{b-swap>e c-swap>e}  «drop: e>c»
<M-;><M-r>                         ⦉c⦊ [e] ⟦b⟧   dtm{a-swap>c b-swap>c c>a} dsm{b-swap>e c-swap>e}  «No ternary relationship found…»
<M-;><M-r>                         ⦉c⦊ [e] ⟦b⟧   dtm{a-swap>c b-swap>c c>a} dsm{b-swap>e c-swap>e}  «No ternary relationship found…»
```
Keep the older one [sim]: the first 11 rows are the same as secondary fix, no ternary rewrite [sim]; from there:
```
<M-f>                              ⦉c⦊ [e] ⟦b⟧   dtm{a-swap>c b-swap>c c>a e>a} dsm{b-swap>e c-swap>e}  «rewrite: e>c becomes e>a»
<M-;><M-r>                         ⦉a⦊ [e] ⟦b⟧   dtm{a-swap>c b-swap>c c>a e>c} dsm{b-swap>e c-swap>e}  «Restored ternary slot to a»
<M-;><M-r>                         ⦉c⦊ [e] ⟦b⟧   dtm{a-swap>c b-swap>c c>a e>a} dsm{b-swap>e c-swap>e}  «Restored ternary slot to c»
```

---

## 4. What the rewrite costs

**1. Rewrites that end up as drops.**
- 302 of 714 firings (42%) find no older note: the plain note they would copy doesn't exist.
- That equals dropping, so it's no loss compared with the drop. But it does mean "Keep the older one" works as a drop almost half the time.

**2. Rewrites to the window's secondary.** This is the case where the rewrite is less useful than dropping.
- 39 of 714 firings (5%): the older note names the buffer sitting in the secondary.
- `<M-;><M-r>` then exchanges the ternary and the secondary (`routines.lua:743-745`, today's code). It brings in nothing that wasn't one key away, and it moves your secondary.
- Then the variant's secondary check drops the current buffer's secondary note, because that note now names the new secondary. Pressing `<M-;><M-r>` again swaps the slots back, but the note is gone. The drop changes nothing and keeps it.
- In the walks, 3 restores exchanged the two slots where the drop found nothing (section 2). The route, shrunk from a walk (`kt_tosec`) **[sim]**:

drop, same base [sim]:
```
:e a                               ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
:e e                               ⦉a⦊ [e] ⟦-⟧   dtm{} dsm{}
:e b                               ⦉e⦊ [b] ⟦-⟧   dtm{e>a} dsm{}
:e c                               ⦉b⦊ [c] ⟦-⟧   dtm{b>e e>a} dsm{}
<M-f>                              ⦉-⦊ [c] ⟦b⟧   dtm{b>e e>a} dsm{b>e}  «…graduated.»
<M-m> <M-m> <M-v>                  ⦉-⦊ [e] ⟦b⟧   dtm{b>e e>a} dsm{b>e}
:e a                               ⦉e⦊ [a] ⟦b⟧   dtm{b>e e>a} dsm{b>e}
<M-f>                              ⦉e⦊ [b] ⟦a⟧   dtm{a-swap>e e>a} dsm{a-swap>b b>e}  «drop: b>e»
<M-;><M-r>                         ⦉e⦊ [b] ⟦a⟧   dtm{a-swap>e e>a} dsm{a-swap>b b>e}  «No ternary relationship found…»
<M-;><M-r>                         ⦉e⦊ [b] ⟦a⟧   dtm{a-swap>e e>a} dsm{a-swap>b b>e}  «No ternary relationship found…»
```
Keep the older one [sim]: the first 7 rows are the same as drop, same base [sim]; from there:
```
<M-f>                              ⦉e⦊ [b] ⟦a⟧   dtm{a-swap>e b>a e>a} dsm{a-swap>b b>e}  «rewrite: b>e becomes b>a»
<M-;><M-r>                         ⦉a⦊ [b] ⟦e⟧   dtm{a-swap>e b>e e>a} dsm{a-swap>b}  «Restored ternary slot to a»
<M-;><M-r>                         ⦉e⦊ [b] ⟦a⟧   dtm{a-swap>e b>a e>a} dsm{a-swap>b}  «Restored ternary slot to e»
```

- `b>a`: `e`'s note is `e>a`, and `a` is the buffer `<M-f>` just left, now the secondary.
- After the two restores, `b`'s secondary note `b>e` is gone. Under the drop it survives.
- **P14 ("the secondary is yours; it changes only when you act").** It still holds, since the restore is an act. But you pressed "restore ternary" and got your secondary changed.

**3. Duplicate slots and notes naming their own buffer.**
- None, on either seed, in any variant. Every step was scanned for current = ternary, current = secondary, ternary = secondary, and for a note naming its own buffer.
- **Where one could come from in principle:** navigation's first case copies the left buffer's note. If that note names the arriving buffer, the copy names the arriving buffer itself, and a restore would put it in the ternary while it's current.
- That exposure is navigation's own, not new. No walk produced it under `rt_c3kga` either.

**4. Where the older note comes from.**
- On arrivals that keep the ternary, N inherits the kept ternary's memory, a buffer N may never have had as its own ternary. Route 1's `a` is an example.
- Navigation's first case already does this today with the left buffer's note, so it's not new behaviour, only new places.

---

## 5. Remaining throw routes

- **Under `kt_rewrite`: none, on either seed.**
- **Under the literal reading (`kt_literal`): 11 and 8**, all through arrivals that keep the ternary. In each one, the stale note names the ternary, and the literal second case writes it back:

| Arrival | Seed 7 | Seed 11 |
|---|---|---|
| `<M-f>` | 3 | 1 |
| `<M-;><M-f>` falling back to `<M-f>` | 1 | 0 |
| plain `:e` onto the secondary | 3 | 1 |
| a pick of the secondary | 1 | 1 |
| a pick of an outside buffer | 3 | 5 |

- Route 1 (section 3) and the pick route (section 3, the "rewrite as worded" block) are two of them, as rows.
- The throws that reached `rt_c3kga` through `<M-S-f>` and picks of the ternary are gone under both readings. Those arrivals make the left buffer the ternary, so the worded cases apply there.

---

## 6. The secondary half (`kt_rewrite_sec`)

**The change.** The base's every-arrival check drops x's plain secondary note when it names the window's secondary. `kt_rewrite_sec` rewrites it instead, to the older partner when one is known, and drops it only otherwise. It does this on the same other arrivals as the base: picks, `<M-S-f>`, plain `:e` back to a buffer, primary jumps, graduation, and the ternary restore. The older partner is x's swap note `dsm[x-swap]`, when that differs from the secondary.

**What "the buffer from before" can and can't mean here** **[code]**
- **Arrivals (picks, `<M-S-f>`, plain `:e`, primary jumps).**
  - The secondary doesn't change. What's stale is the arriving buffer's own note.
  - The only older partner on record is x's swap note: x's partner the last time `<M-f>` took it out.
  - Navigation leaves no secondary note, so a buffer left by `:e` has nothing older.
- **Graduation.** The secondary slot was empty before, so there is nothing older.
- **The ternary restore exchanging the two slots.**
  - The slot's previous occupant is known, but it has just moved into the ternary. Pointing the note at it would only undo the restore's move.
  - That candidate was there in 53 firings. It was logged and not used.
- **The catch.**
  - The restore reads the swap note first. It falls back to the plain note only when the swap note is missing or equals the secondary (`routines.lua:718-722`, with RT's change comparing against the secondary).
  - Those are exactly the cases where no older partner is known. So a rewrite is possible only when the restore wouldn't read the plain note anyway.
  - It matters only if the swap note later changes to the secondary or gets cleared.

**How often, both seeds** **[sim]:**
- 497 firings: 122 rewrites (25%) and 375 forced drops.
- Of the drops, 256 had a swap note equal to the secondary and 119 had no swap note.

| Arrival | Rewrite | Drop |
|---|---|---|
| `<M-S-f>` | 18 | 86 |
| plain `:e` to another buffer | 15 | 76 |
| pick of the secondary | 48 | 36 |
| plain `:e` onto the ternary | 21 | 54 |
| `<M-;><M-r>` exchanging the ternary with the secondary | 2 | 51 |
| pick of the ternary | 10 | 33 |
| pick of an outside buffer | 7 | 32 |
| primary jump | 1 | 5 |
| graduation (`<M-f>` or `<M-;><M-f>` on an empty secondary) | 0 | 2 |
| **all** | **122** | **375** |

**What it changed.**
- Against `kt_rewrite`, on the same 3,000 walks: the notes diverged in 119 walks, and **one** `<M-;><M-t>` came out different. 0 throws either way.
- That route, shrunk (`kt_secgain`) **[sim]**:

Keep the older one [sim]:
```
:e a                               ⦉-⦊ [a] ⟦-⟧   dtm{} dsm{}
:e e                               ⦉a⦊ [e] ⟦-⟧   dtm{} dsm{}
<M-f>                              ⦉-⦊ [e] ⟦a⟧   dtm{} dsm{}  «…graduated.»
:e d                               ⦉e⦊ [d] ⟦a⟧   dtm{} dsm{}
<M-;><M-f>                         ⦉e⦊ [a] ⟦d⟧   dtm{d-swap>e} dsm{d-swap>a}
<M-S-f>                            ⦉a⦊ [e] ⟦d⟧   dtm{a-swap>e d-swap>e} dsm{d-swap>a}
<M-;><M-f>                         ⦉a⦊ [d] ⟦e⟧   dtm{a-swap>e d-swap>e e-swap>a} dsm{d-swap>a d>a e-swap>d}
<M-f>                              ⦉a⦊ [e] ⟦d⟧   dtm{a-swap>e d-swap>a e-swap>a} dsm{d-swap>e d>a e-swap>d}
<M-m> <M-m> <M-v>                  ⦉e⦊ [a] ⟦d⟧   dtm{a-swap>e d-swap>a e-swap>a} dsm{d-swap>e d>a e-swap>d}
<M-m> <M-m> <M-v>                  ⦉e⦊ [d] ⟦a⟧   dtm{a-swap>e d-swap>a e-swap>a} dsm{d-swap>e e-swap>d}
<M-f>                              ⦉e⦊ [a] ⟦d⟧   dtm{a-swap>e d-swap>e e-swap>a} dsm{d-swap>a e-swap>d}
<M-m> <M-v>                        ⦉e⦊ [d] ⟦a⟧   dtm{a-swap>e d-swap>e e-swap>a} dsm{d-swap>a e-swap>d}
<M-;><M-t>                         ⦉e⦊ [d] ⟦a⟧   dtm{a-swap>e d-swap>e e-swap>a} dsm{d-swap>a e-swap>d}  «No secondary relationship found…»
<M-;><M-t>                         ⦉e⦊ [d] ⟦a⟧   dtm{a-swap>e d-swap>e e-swap>a} dsm{d-swap>a e-swap>d}  «No secondary relationship found…»
```
Keep the older one, both sides [sim]: the first 9 rows are the same as Keep the older one [sim]; from there:
```
<M-m> <M-m> <M-v>                  ⦉e⦊ [d] ⟦a⟧   dtm{a-swap>e d-swap>a e-swap>a} dsm{d-swap>e d>e e-swap>d}  «secondary note d>a becomes d>e»
<M-f>                              ⦉e⦊ [a] ⟦d⟧   dtm{a-swap>e d-swap>e e-swap>a} dsm{d-swap>a d>e e-swap>d}
<M-m> <M-v>                        ⦉e⦊ [d] ⟦a⟧   dtm{a-swap>e d-swap>e e-swap>a} dsm{d-swap>a d>e e-swap>d}
<M-;><M-t>                         ⦉a⦊ [d] ⟦e⟧   dtm{a-swap>e d-swap>e e-swap>a} dsm{d-swap>a d>a e-swap>d}  «Restored secondary slot to e»
<M-;><M-t>                         ⦉e⦊ [d] ⟦a⟧   dtm{a-swap>e d-swap>e e-swap>a} dsm{d-swap>a d>e e-swap>d}  «Restored secondary slot to a»
```

- **Row 10.** The pick of the secondary `d` finds `d>a` naming the secondary `a`, and rewrites it to `d`'s swap note, `e`. The swap note `d-swap>e` was still valid then, so a restore at that point would have read it anyway.
- **What made it reachable.** `<M-f>` to `a` and the pick back to `d` overwrote the swap note with the current secondary (`d-swap>a`). Only then does the restore fall back to `d>e`.
- **What it brings back:** `e`, which was sitting in the ternary. So it's an exchange of the two slots, not a buffer from outside.
- No route was found where the secondary rewrite brings back a buffer from outside the slots that the drop loses.

---

## 7. What code the rewrite touched (in the variants, by repo line)

**Ternary half (`kt_rewrite`).** A new helper, `kt_ter_rewrite`, near the top of `lua/cavediver/domains/window/routines.lua` (variant only), called from three places:

| Function | Repo lines | What was added |
|---|---|---|
| `reconcile_triquetra` | `routines.lua:93-135` | Records the left buffer, the ternary and the secondary on entering the slot-change block (`:104`). Calls the rewrite at the end of that block, after the slot change and the conflict check (between `:133` and `:134`). Covers `<M-S-f>`, `<M-f>` and its `<M-;><M-f>` fallback, and cycling picks. |
| `jump_to_primary` | `routines.lua:651-654` | Records the left buffer and the ternary before the slot shift; calls the rewrite after it (after `:654`). Its own `reconcile_triquetra` call (`:659`) finds the current slot already set and does nothing. |
| the `displacement_mangement` hook, branch for plain navigation onto the secondary | `lua/cavediver/domains/window/hooks.lua:52-54` | Records before; calls the rewrite after the swap (after `:54`). The stale-note check in navigation sits in the other branch (`hooks.lua:55-94`, check at `:71-85`) and is untouched. |

**Secondary half (`kt_rewrite_sec`).** Changes only the base's check, `rt_sec_check` (variant only): rewrite to the swap note when it's older, else drop. Its call sites by repo line:
- `reconcile_triquetra` on entry (`routines.lua:104`);
- graduation, after the ternary is cleared (`routines.lua:486`);
- `jump_to_primary` after the slot shift (`:654`);
- the ternary restore's exchange with the secondary (`routines.lua:743-745`);
- navigation's branch end (`hooks.lua:93`).

---

## Runs

| Run | What it shows | Variants |
|---|---|---|
| `rt_bonus1`, `rt_bonus1_again` | RT's route 1, and the restore pressed twice | `rt_c3kga`, `rt_tb`, `kt_literal`, `kt_rewrite`, `kt_rewrite_sec` |
| `rt_bonus2`, `rt_bonus2_nav` | RT's route 2, and the same with `:e d` instead of `<M-S-f>` | `rt_c3kga`, `rt_tb`, `kt_literal`, `kt_rewrite` |
| `kt_pickout` | a pick of an outside buffer, then `<M-f>` | `rt_c3kga`, `kt_literal`, `kt_drop`, `kt_rewrite` |
| `kt_tosec` | a rewrite naming the secondary, then the restore pressed twice | `rt_c3kga`, `kt_drop`, `kt_rewrite` |
| `kt_secgain` | the one restore the secondary half changed | `kt_rewrite`, `kt_rewrite_sec` |
| walks | `rt/rt_walk.py 1500 25 7` and `… 11` | all six |

- Rows come from `t/rt_seqrows.lua` through `kt/rows.sh`, saved in `<sandbox>/kt/rows/`.
- The variants are built by `<sandbox>/kt/mkkt.py`.
- Numbers come from `kt/kt_table.py`, `kt/kt_bykind.py`, `kt/kt_stats.py` and `kt/kt_diff.py`, plus `rt/rt_classify.py` for the throw classes.
- Routes were shrunk with `rt/rt_shrink.py` and `kt/kt_shrink.py`.
- The walk files are `<sandbox>/rt/walks/<variant>-1500-25-<seed>.jsonl`. For `rt_c3kga` and `rt_tb`, seed 7 is RT's own run, reused.
