# Question packet RT: the secondary restore's round trip

**Stakes:** whether `<M-;><M-t>` (restore secondary) can crash after an ordinary trip onto the secondary and back, and what it can still bring back after one. Today 147 of 1,500 random 25-key walks hit its "impossible" throw, 161 times in all. With plain `:e` onto the secondary writing `<M-f>`'s notes, as just decided, 179 walks hit it, 204 times.

**How things are cited**
- Code paths are relative to the repo, for example `lua/cavediver/domains/window/routines.lua:738`. `README.md:N`, `DESK.md:N` and `what-is-cavediver.md:N` ("the spec") are the repo files.
- "The author, date time" quotes the author's own answer, in local time, word for word, typos included. "The session, date time" is text the session wrote.
- Runs are named `rt_*`. Each one is a headless scenario at `<sandbox>/t/rt_*.lua`. Today's code runs with `<sandbox>/t/run.sh`; a variant runs with `VARIANT=<sandbox>/variants/<name> <sandbox>/t/runv.sh`. Variants are copies of the plugin under `<sandbox>/variants/`, never the repo. The full list is at the end.
- Rows: one row per action, then the window's triquetra after it, as `⦉ternary⦊ [current] ⟦secondary⟧   dtm{…} dsm{…}`, then any message. Hashes in messages are replaced by the file name. When a run's first rows match the run above it, the block says so and starts where they differ.
- Evidence tags:
  - **[run]**: seen in a run of today's code.
  - **[code]**: read from the code, not run.
  - **[inferred]**: reasoned, not checked.
  - **[sim]**: a run of a variant that stands in for a change that isn't built: a decided one, or one of the options. Each variant is described where it first appears.
- Random walks: 1,500 walks of 25 keys each, seed 7, the same generator and key mix as the earlier Q6 walks (`<sandbox>/../q6/t/errcount.py`), run by `<sandbox>/rt/rt_walk.py` and sorted by `<sandbox>/rt/rt_classify.py`. A walk is a sequence of `:e` on five files, `<M-f>`, `<M-S-f>`, both restores, cycling picks, `<M-;><M-c>` and `<M-;><M-f>`.

---

## Recap, from zero

### 1. What it is

1. **Triquetra.** Each window has three slots: the **current** buffer (the one you're on), the **secondary** (the buffer you parked; `<M-f>` swaps with it) and the **ternary** (your previous buffer; `<M-S-f>` swaps with it) (`what-is-cavediver.md:184-196`).
2. **Partner.** In this packet, a buffer's **partner** is the window's secondary while that buffer is current. `c` with secondary `b` has partner `b`; `<M-f>` makes `b` current with partner `c`.
3. **Note.** A remembered value that a restore brings back. Each window keeps two maps of notes, keyed by buffer (`what-is-cavediver.md:235-247`):
   - **Ternary memory (`dtm`)** holds two kinds of note:
     - a **plain note** `dtm[X]`, written when you leave X by plain navigation (`:e`, the bufferline): X's ternary at that moment (`lua/cavediver/domains/window/hooks.lua:66-68`). Rows print it `x>y`.
     - a **swap note** `dtm[X-swap]`, written when you leave X by a swap or a primary jump (`lua/cavediver/domains/window/routines.lua:107`, `:498`, `:652`). Rows print it `x-swap>y`.
   - **Secondary memory (`dsm`)** holds one kind: `dsm[X]`, X's partner at the moment `<M-f>` swapped X out (`lua/cavediver/domains/window/routines.lua:496`). Two other writers: **graduation** and the restore's flip.
4. **Graduation.** `<M-f>` with an empty secondary moves the ternary T into the secondary and copies T's plain ternary note into its secondary note: `dsm[T] := dtm[T]` (`lua/cavediver/domains/window/routines.lua:482-487`).
5. **Restore.** `<M-;><M-r>` (ternary) and `<M-;><M-t>` (secondary) (`lua/cavediver/domains/window/routines.lua:714-762`). On the current buffer A:
   - It looks up `map[A-swap]` first, and falls back to `map[A]` when that's missing **or equals the ternary**, for both maps (`:718-722`).
   - If the note equals the slot it would restore into, it **throws** "This is impossible. Remembered secondary is the same as current secondary. It should be different for flip flop." (`:737-739`). Rows show it as `ERROR: Remembered secondary is the same as current secondary.`
   - Otherwise it puts the note into the slot and writes the slot's old value back as A's plain note (`:759`), so pressing it again **flip-flops** (P19, `what-is-cavediver.md:71`; T63, `what-is-cavediver.md:1395`).
6. **Round trip.** Going from a buffer onto its secondary and straight back, by any key. The second half is the **toggle back**.
7. **Routes onto the secondary.** Four keys or events land you on the secondary: `<M-f>`, `<M-;><M-f>` when it falls back to `<M-f>`, a cycling pick of the secondary, and plain navigation onto it (`what-is-cavediver.md:584-588`). Today only `<M-f>` and its fallback write a secondary note; plain navigation just swaps (`lua/cavediver/domains/window/hooks.lua:52-54`), and so does a pick (`lua/cavediver/domains/window/routines.lua:113-120`).

### 2. Why it matters

The round trip with `<M-f>`, today **[run `rt_sec_round`]**:

{{B rt_sec_round today}}

- The note `<M-f>` writes always names the partner: `c>b` on the way out.
- Coming straight back makes `b` the secondary again, so the note equals the slot and the restore throws (`lua/cavediver/domains/window/routines.lua:737-739`).

The same with plain `:e`, once plain navigation onto the secondary writes `<M-f>`'s notes, as decided (D8). The variant **decided** adds the two decided, unbuilt changes this packet builds on: Q6's guard on all four routes onto the secondary, and D8's notes on plain `:e` onto the secondary, in `<M-f>`'s order (notes, then the guard, then the swap) **[sim `rt_cand_round_e`]**:

{{B rt_cand_round_e today,rt_base}}

How often, over 1,500 random walks:

| Code | Secondary restore throws | Ternary restore throws |
|---|---|---|
| today | 161, in 147 walks **[run]** | 14 **[run]** |
| Q6's guard on all four routes **[sim]** | 161, in 147 walks | 13 |
| decided: Q6's guard plus D8's notes **[sim]** | 204, in 179 walks | 14 |

The secondary restore throws about ten times as often as the ternary one.

### 3. What's decided

- **Q13: the throw stays.** The author, 2026-10-20 15:51, asked "When the remembered buffer is already the ternary, does restore throw (an assertion; remaining routes get hunted by tests) or show 'No different ternary relationship to restore'?": "Keep the assertion (throw)" (`what-is-cavediver.md:1604-1606`). Every route into the throw is a bug, to be fixed upstream (T154, `what-is-cavediver.md:1508`).
  - The principle behind it, the author, 2026-10-20 11:13: "no, when I say it shouldn't happen, then it shouldn't happen. It's a systemic issue by then." That answer was given to a different question: whether the bufferline's callbacks should return neutral colours instead of throwing when no triquetra exists.
- **Q2: two kinds of ternary note are intended**, and the restore prefers the swap note unless it equals the current ternary (`what-is-cavediver.md:1538-1544`). The author, 2026-10-20 14:26: "Yes, today's is intended", and "I remember it was a way to circumvent around some edge cases you know, because without it would exhibit some unintuitive shits. Now, I forgot." The reasons in section 8 were found by the session's own runs afterwards (the session, 2026-10-20 15:57); the first of them is exactly this packet's problem, on the ternary side. Item 1 below runs it.
- **Q3: graduation's copy stays.** The author, 2026-10-20 14:34: "Yes, the copy is intended", and "It's either you restore a as a ternary or secondary. Maybe that was my intention" (`what-is-cavediver.md:1546-1548`).
- **Q6: a guard runs before the swap on every route onto the secondary**, rewriting the ternary's note to the buffer being left. The author, 2026-10-20 15:35: "Yes, guard before the swap (Recommended)" (`what-is-cavediver.md:1558-1567`).
- **D8: plain navigation onto the secondary records the same notes as `<M-f>`.** Asked "Does plain navigation onto the secondary record the same notes as <M-f>?", the author, 2026-10-20 21:17, typed: "we should solve the round trip as well" (`what-is-cavediver.md:1223-1224`). That's a typed note rather than a pick of the offered option "Same as <M-f> (A)"; the spec reads it as A plus this packet.
- **P14: the secondary is yours; it changes only when you act** (`what-is-cavediver.md:66`).
- **P19 and T63: a restore flip-flops** (`what-is-cavediver.md:71`, `:1395`).
- **Navigation onto the ternary writes no note** (`lua/cavediver/domains/window/hooks.lua:66`), and **navigation clears the left buffer's swap note before writing its plain note** (`hooks.lua:67-68`, commit 6f66e36).

### 4. Other rules involved

- **P13: you can always get back to what once was** (`what-is-cavediver.md:65`), confirmed by the author on 2026-10-20. This is what tells the options apart (section 6).
- **README.md:355:** "Every time you jump to secondary the system also records the current buffers, secondary – just the same as ternary's way but with keys `<m-;><m-t>`".
- **DESK.md:41:** displacement maps are "per-window memory of what a buffer's ternary or secondary was before it got pushed out".
- **Follow along** (`DESK.md:78`, I17 at `what-is-cavediver.md:1046`): maps keep nothing alive. Any new per-buffer store has to follow along too.
- **Asking before widening** (the author's standing rule for changes): D8 named `:e` and the bufferline. The options below write notes on `<M-f>`, its fallback and plain `:e` only, never on cycling picks. Where a pick still reaches the throw, that's reported as its own open point (section 6).

### 5. How they collide

**Item 1: why the ternary side mostly avoids the throw.**

The ternary's own round trip, `<M-S-f>` there and back, then `<M-;><M-r>`. Today, and with a variant where swaps write plain ternary notes, the design Q2 kept the swap notes against (`<sandbox>/variants/plain`) **[run, sim `rt_ter_round`]**:

{{B rt_ter_round today,plain}}

The same after the buffer already holds an older plain note (`c>b`) **[run, sim `rt_ter_round_older`]**:

{{B rt_ter_round_older today,plain}}

And the secondary's version of that: `b` holds an older note `b>a` (from graduation), then a round trip **[run `rt_sec_round_older`]**:

{{B rt_sec_round_older today}}

What the ternary has that the secondary doesn't:
1. **Two kinds of note.** `<M-S-f>` writes only the swap note (`lua/cavediver/domains/window/routines.lua:107`). The plain note is written only by navigation, and never by navigation onto the ternary (`hooks.lua:66`). A round trip's swap note names the partner, which is the ternary again on return, and the restore skips a swap note equal to the ternary (`routines.lua:720`). So the older plain note under it survives and comes back. `<M-f>` writes a single kind (`routines.lua:496`), which the round trip overwrites with the partner.
2. **An arrival check.** When navigation lands on X and X's plain note names the buffer being left, which is about to become X's ternary, navigation rewrites the note ("guard 2", `hooks.lua:71-85`). Nothing checks `dsm` on arrival.
3. **The proof.** Make swaps write plain ternary notes, and the ternary's round trip throws exactly like the secondary's (the runs above). That's the first reason section 8 gives for Q2 (`what-is-cavediver.md:1541`).

"Mostly": the ternary restore still throws in 13–14 of the 1,500 walks. See the bonus.

**Item 2: the routes into the secondary restore's throw.**

Over today's 1,500 walks, each throw sorted by what wrote the stale note and by how the window last arrived on that buffer with that secondary **[run]**:

| Wrote the stale note | Throws |
|---|---|
| `<M-f>` swapping the buffer out | 130 |
| `<M-;><M-f>` falling back to `<M-f>` | 21 |
| graduation's copy (Q3) | 9 |
| the restore's flip | 1 |

| Arrived on the buffer by | Throws |
|---|---|
| `<M-f>` (the toggle back) | 63 |
| plain `:e` onto the secondary | 26 |
| a cycling pick of the secondary | 20 |
| `<M-S-f>`, or `:e` onto the ternary (the buffer left by navigation and came back while its partner stayed) | 24 |
| `<M-;><M-f>` falling back to `<M-f>` | 11 |
| other picks, other navigation, a primary jump | 17 |

Under the decided changes there are 204 throws, and in 57 of them the stale note was written by plain `:e` onto the secondary **[sim]**. One run per route:

R1. `<M-f>` there and back: `rt_sec_round`, above **[run]**.

R2. `<M-f>` out, plain `:e` back. Plain `:e` writes nothing today, so `c`'s note from the way out stays **[run `rt_route_nav_back`]**:

{{B rt_route_nav_back today}}

R3. `<M-f>` out, a cycling pick back **[run `rt_route_pick_back`]**:

{{B rt_route_pick_back today}}

R4. `<M-;><M-f>` with no primary, which falls back to `<M-f>` (`lua/cavediver/domains/window/routines.lua:632-635`) **[run `rt_route_primary`]**:

{{B rt_route_primary today}}

R5. A round trip, then leaving by `:e` and coming back with `<M-S-f>`. The partner never changed **[run `rt_route_ternback`]**:

{{B rt_route_ternback today}}

R6. Graduation's copy names the buffer that later becomes the partner. `d` graduates with the note `d>a`; from `c`, `:e a` then `<M-f>` makes `a` its partner **[run `rt_route_grad`]**:

{{B rt_route_grad today}}

R7. Plain `:e` both ways, under the decided changes: `rt_cand_round_e`, above **[sim]**.

R8. The restore's flip names a buffer that later becomes the partner again (1 walk in 1,500; the shrinker couldn't cut it shorter and keep the restore as the writer). `b`'s restore writes `b>d`; much later a pick of `b` from `d` makes `d` its partner **[run `rt_route_flip`]**:

{{B rt_route_flip today}}

**The collision.**
- One rule underlies every route: a buffer's secondary note becomes useless, and fatal, the moment the buffer sits current with the partner its note names. `<M-f>`'s note is written equal to the partner (R1–R5), and Q3's copy and the restore's flip can come to equal a later partner (R6, R8).
- Q13 rules out fixing it in the restore: the throw stays, so the writes have to change.
- D8 adds a writer, so it adds routes (R7).
- Q3 keeps the copy, so R6 has to be met some other way than dropping the copy.
- P19 and T63 need the flip-flop to keep working, and the case D8 was decided for has to keep working: `d`'s old secondary comes back (`t/b5_A_use.lua`).

### 6. The way out

Change what a swap onto the secondary writes, and check notes on arrival, so that no buffer is ever current with a note that names its partner. Three ideas were up for testing; all three were simulated, plus two refinements the runs called for.

**The variants** (each is the decided variant plus one change, in `<sandbox>/variants/`, built by `<sandbox>/rt/mkvariants.py` and `mkall.py`):

| Name | What it changes | Variant |
|---|---|---|
| TK-as-is | **Two kinds**: `<M-f>` and plain `:e` onto the secondary write a swap note `dsm[A-swap] := S` instead of `dsm[A]`. The restore is unchanged. | `rt_c1` |
| TK | Two kinds, and the restore skips the secondary's swap note when it equals the **secondary** (not the ternary, as `routines.lua:720` does today). | `rt_c1s` |
| SK | **Skip on a toggle back**: don't write `dsm[A] := S` when S's note names A. | `rt_c2a` |
| SC | **Skip and clear**: on a toggle back, also clear S's note. It's navigation's guard 2 condition (`hooks.lua:71`) applied to `dsm`, clearing where guard 2 rewrites. | `rt_c2b` |
| PC | **Partner change**: the swap-out records the partner in its own store; on arrival, S's note is written, as S's previous partner, only when that partner differs from A. | `rt_c3` |
| PCd | PC with the partner kept in `dsm[A-swap]` instead of a new store, plus TK's restore lookup. | `rt_c3k` |
| +G | **The guard**: on a swap onto S from A, clear S's note if it names A (SC's clear, without SC's skip). In these two variants graduation also clears the graduated buffer's swap note (Check 12). | `rt_c1sg` (TK+G), `rt_c3kg` (PCd+G) |
| +W | **Widened**: the same check on every other arrival and every change of the secondary under the current buffer: picks, navigation, `<M-S-f>`, primary jumps, graduation, the ternary restore. Not asked for; run only to measure. | `rt_c1sga`, `rt_c3kga`, `rt_c2bga` |

**Check 1: the round trip with `<M-f>`** **[sim `rt_sec_round`]**:

{{B rt_sec_round rt_base,rt_c1,rt_c1s,rt_c2a,rt_c2b,rt_c3,rt_c3k,rt_c1sg,rt_c3kg}}

**Check 2: the round trip with plain `:e`** **[sim `rt_cand_round_e`]**:

{{B rt_cand_round_e rt_base,rt_c1,rt_c1s,rt_c2a,rt_c2b,rt_c3,rt_c3k,rt_c1sg,rt_c3kg}}

**Check 3: the case that must keep working**, `t/b5_A_use.lua` with a real plain `:e`: `d`'s old secondary `b` comes back, then flip-flops **[run, sim `rt_cand_use`]**:

{{B rt_cand_use rt_base,today,rt_c1,rt_c1s,rt_c2a,rt_c2b,rt_c3,rt_c3k,rt_c1sg,rt_c3kg}}

- TK-as-is loses this case. `d`'s swap note `d-swap>b` names the current **ternary** `b`, and `routines.lua:720` skips a swap note equal to the ternary for both maps, so the restore falls to the empty plain note. TK, which compares with the secondary, restores `b`.
- Every restore here also moves `b` out of the ternary and `e` into it. That's today's rule for a remembered secondary that sits in the ternary (`routines.lua:751-753`), unchanged by any option.

**Check 4: graduation and Q3**: `b` graduates with the note `b>a`; on `b`, `a` comes back as the secondary, then as the ternary **[run, sim `rt_cand_q3`, `rt_cand_q3t`]**:

{{B rt_cand_q3 today,rt_base,rt_c1,rt_c1s,rt_c2a,rt_c2b,rt_c3,rt_c3k,rt_c1sg,rt_c3kg}}

{{B rt_cand_q3t today,rt_base,rt_c1,rt_c1s,rt_c2a,rt_c2b,rt_c3,rt_c3k,rt_c1sg,rt_c3kg}}

- Q3 holds both ways under every option. The ternary restore doesn't flip back here because the ternary was empty and a restore deletes the note when the old slot is empty (`routines.lua:759`, `what-is-cavediver.md:691`); that's today's behaviour, untouched.

**Check 5: R6, graduation's copy** **[run, sim `rt_route_grad`]**:

{{B rt_route_grad today,rt_base,rt_c1s,rt_c2b,rt_c3,rt_c3k,rt_c1sg,rt_c3kg}}

- TK and PC alone leave R6, which is why +G exists. The note `d>a` is moot here (`a` already is the secondary), so clearing it loses nothing.

**Check 6: R5, back through the ternary** **[run, sim `rt_route_ternback`]**:

{{B rt_route_ternback today,rt_base,rt_c1s,rt_c2b,rt_c3,rt_c3k,rt_c1sg,rt_c3kg}}

**Check 11: R2–R4 under the options** **[run, sim `rt_route_nav_back`, `rt_route_pick_back`, `rt_route_primary`]**:

{{B rt_route_nav_back today,rt_base,rt_c2b,rt_c1sg,rt_c3kg}}

{{B rt_route_pick_back today,rt_base,rt_c2b,rt_c1sg,rt_c3kg}}

{{B rt_route_primary today,rt_base,rt_c2b,rt_c1sg,rt_c3kg}}

- Options 1 and 2 close R3 without touching the pick: the stale note is a swap note, and the restore skips a swap note equal to the secondary whatever the route back. Option 3's clear runs only on the swap routes, so the pick back still throws.

**Checks 7–9: P13, what survives a round trip.** A buffer already holds an older note; then a round trip; then the restore. Each check gets that older note from a different writer.

Check 7, the older note from graduation (`b>a`) **[run, sim `rt_sec_round_older`]**:

{{B rt_sec_round_older today,rt_base,rt_c1s,rt_c2a,rt_c2b,rt_c3,rt_c3k,rt_c1sg,rt_c3kg}}

Check 8, the older note from a restore (`b>c`) **[run, sim `rt_keep_restore`]**:

{{B rt_keep_restore today,rt_base,rt_c1s,rt_c2a,rt_c2b,rt_c3,rt_c3k,rt_c1sg,rt_c3kg}}

Check 9, the older note from an earlier partner: `d` remembers `b`, its secondary before `e` **[run, sim `rt_keep_partner`]**:

{{B rt_keep_partner today,rt_base,rt_c1s,rt_c2a,rt_c2b,rt_c3,rt_c3k,rt_c1sg,rt_c3kg}}

**Check 10: Q13 still fires under the new lookup.** TK and PCd change which note the restore reads, which touches the restore itself. With both of `c`'s notes set by hand to its secondary, the restore still throws **[sim `rt_c1_assert`]**:

{{B rt_c1_assert rt_c1s}}

**Check 12: Q3 when the graduating buffer already holds a swap note.** `b` was once swapped out to `d`, so under Options 1 and 2 it carries `b-swap>d`. Its secondary is then closed (`:bdelete` prunes a closed secondary today, I4 at `what-is-cavediver.md:1033`), and `b` graduates with Q3's note `b>c`. TK and PCd show the two options without graduation's clear **[run, sim `rt_q3_oldswap`]**:

{{B rt_q3_oldswap today,rt_base,rt_c2b,rt_c1s,rt_c3k,rt_c1sg,rt_c3kg}}

- Without the clear, Options 1 and 2 bring back `d`, the old partner, instead of Q3's `c`: Option 2 because the restore prefers the old swap note, Option 1 because the promotion also overwrites the copy. Clearing the swap note at graduation restores Q3. The random walks never reach this case (their keys never empty a filled secondary), so the walk counts are the same with and without the clear.

**Check 13: a swap note naming a deleted file.** `b` remembers `f`; `f` is closed and deleted on disk **[run, sim `rt_sec_missing`]**:

{{B rt_sec_missing today,rt_base,rt_c2b,rt_c1sg,rt_c3kg}}

**The walks** (1,500, as above):

| Variant | Secondary restore throws | Ternary restore throws |
|---|---|---|
| decided | 204 | 14 |
| TK-as-is | 211 | 11 |
| TK | 15 (14 from graduation's copy, 1 from a restore's flip) | 13 |
| SK | 139 | 14 |
| SC | 31 (24 through cycling picks) | 14 |
| PC | 22 | 14 |
| PCd | 18 | 14 |
| TK+G | 4 | 13 |
| PCd+G | 7 | 14 |
| TK+G+W | **0** | 13 |
| PCd+G+W | **0** | 14 |
| SC+W | **0** | 14 |

No variant raised any other error in the walks: no other throw, and no hook error (hook errors surface as ERROR-level messages, `lua/cavediver/engine/helpers.lua:36-43`).

What TK+G and PCd+G leave, all through arrivals the options don't touch: cycling picks of the secondary or of another buffer, and plain navigation back to a buffer while the window's secondary happens to equal its old note. The shortest, under PCd+G and TK+G, with W for comparison: `c` graduated with `c>a`; `a` becomes the secondary while `c` isn't current; `:e c` lands on `c` **[sim `rt_resid_nav`]**:

{{B rt_resid_nav rt_c3kg,rt_c1sg,rt_c3kga,rt_c1sga}}

R8 under each option **[sim `rt_route_flip`]**. The stale note `b>d` is written by the restore, and `b` comes back with partner `d` through a pick, which no option guards, so Options 1–3 still throw; W clears the note at the pick.

{{B rt_route_flip today,rt_c1sg,rt_c3kg,rt_c2b,rt_c1sga,rt_c3kga}}

---

## The options

**What every option shares.**
- Q13's throw stays (Check 10). Options 1 and 2 add a skip in front of it; see each option.
- Q6's guard and D8's notes stay as decided; the options change only which secondary note is written and when.
- No option moves a slot, so P14 holds: the secondary still changes only when you act.
- P19 and T63: the flip-flop works under all three (Checks 3, 4, 7–9).
- Q3 holds both ways (Checks 4 and 12).
- Options 1 and 2 close R1–R7. Option 3 closes all of them but R3, the pick back (Check 11). R8, and the throws through picks and other arrivals, stay open until W (below).

**Option 1: PCd+G, a note only when the partner changes, plus the guard. Proposed (Kate).**
- The change: `<M-f>` and plain `:e` onto the secondary record the buffer's partner in its swap key (`dsm[A-swap] := S`). On arrival, S's plain note becomes S's previous partner when that differs from A; if it doesn't, and S's plain note names A, the note is cleared. Graduation clears the graduated buffer's swap note, as navigation clears the left buffer's (`lua/cavediver/domains/window/hooks.lua:67`) and Q9's pick clears the picked buffer's (`what-is-cavediver.md:1584`). The secondary restore skips a swap note equal to the secondary.
- Consequence: no round-trip throw, and every older note tested survives a round trip (Checks 7, 8 and 9). Walks: 204 → 7.
- Changes:
  - The restore's lookup at `lua/cavediver/domains/window/routines.lua:720` compares the secondary map's swap note with the secondary. That's a change inside the restore, not to its throw.
  - The plain note's meaning moves from "the partner when swapped out" (`what-is-cavediver.md:243`, `DESK.md:41`) to "the previous partner, written when the partner changes". README.md:355's "just the same as ternary's way" holds for the two kinds, not for where the plain note comes from: the ternary's comes from navigation.
  - `rename_hash_in_triquetras` renames `-swap` keys only in `dtm` (`lua/cavediver/domains/window/data.lua:137-140`); `dsm`'s would need the same. The maps are saved whole (`lua/cavediver/domains/storage/routines.lua:495-496`), so the swap key persists with no format change **[code]**.
  - PC with its own store (`rt_c3`) gives the same slots and restores as PCd in Checks 1–9 and needs no lookup change (PC+G wasn't run). The new store touches the triquetra constructors (`lua/cavediver/domains/window/data.lua:32-40`, `lua/cavediver/domains/window/routines.lua:799-807`, `lua/cavediver/domains/window/init.lua:51-59`), rename, save and load, and follow-along (I17).
  - The missing-file branch clears only `map[A]` (`lua/cavediver/domains/window/routines.lua:734-736`). With swap keys in `dsm`, a swap note naming a deleted file blocks the secondary restore for good, as it already does for the ternary (`what-is-cavediver.md:1714`, D9). Today the secondary restore clears its one note and moves on (Check 13). The open D9 fix would have to cover `dsm` too.
- Decided rules touched:
  - **Q13, plainly:** the secondary restore gains a skip before the throw: a swap note equal to the secondary is passed over for the plain note. That's Q2's existing ternary rule (`routines.lua:720`) applied to the secondary, and the throw still fires when both notes equal the slot (Check 10). But it is a restore-side skip, not only an upstream fix.
  - Q2 is mirrored for the secondary, not changed. Q3 holds once graduation clears the swap note (Check 12).

**Option 2: TK+G, two kinds like the ternary, plus the guard. Neutral.**
- The change: as Option 1, without the promotion on arrival. The plain note is written only by graduation's copy and the restore's flip. Graduation clears the swap note, as in Option 1.
- Consequence: no round-trip throw, and the closest copy of the ternary's design (README.md:355). A round trip erases the memory of an earlier partner (Check 9), the same way a `<M-S-f>` round trip overwrites a ternary swap note. Walks: 204 → 4.
- Changes: the same lookup change, rename work and missing-file gap as Option 1 (Check 13).
- Decided rules touched: Q13, the same restore-side skip as Option 1 (Check 10). Q3 holds once graduation clears the swap note (Check 12).

**Option 3: SC, one kind of note, and the toggle back clears the stale one. Neutral.**
- The change: keep `dsm[A] := S`, but on a swap from A onto S where S's note names A, clear S's note and don't write A's. That's navigation's guard 2 condition (`lua/cavediver/domains/window/hooks.lua:71-85`) for the secondary map, clearing instead of rewriting, run on `<M-f>`, its fallback and plain `:e`.
- Consequence: the smallest change, with no lookup change and no new key. An older note written by a restore is lost on a round trip (Check 8), and a pick back onto the secondary still throws (R3, Check 11). Walks: 204 → 31, 24 of them through cycling picks.
- Decided rules touched: none. The restore is unchanged, so Q13's throw is reached only through the routes left open. Q3 holds (Checks 4 and 12).

**Tested and dropped:**
- TK-as-is: breaks the case D8 was decided for (Check 3), because `routines.lua:720` compares with the ternary. Walks: 211.
- SK, the literal "skip the write on a toggle back": the round trip still throws (Checks 1 and 2), because the stale note was written on the way out, not on the toggle back. Walks: 139.
- TK, PC and PCd without +G: R6 stays (Check 5).

**Open after any option (ask separately):** the throws that remain all come through arrivals the options don't touch: cycling picks of the secondary or of another buffer, plain navigation back to a buffer, `<M-S-f>`, a primary jump, and graduation or a ternary restore changing the secondary under the current buffer. Running the same check there (W) took every option to 0 in the walks. D8 named only `:e` and the bufferline, so W needs its own answer.

---

## Bonus: the 13 ternary restore throws (labelled as such)

- **Checked first:** the spec's "with Q6's fix … 13 in 1,500" (`what-is-cavediver.md:590`, `:708`, `:1508`, `:1715`) came from a variant with the guard in `reconcile_triquetra` only (`<sandbox>/../q6/variants/C`), which leaves the plain `:e` route without it. With the guard on all four routes it's still 13, the same 13 walks **[sim]**.
- **The shape they share:** each lands on a buffer whose plain ternary note already names the ternary the window will have, through an arrival with no guard 2. A swap onto the secondary, or a pick of an outside buffer, keeps the window's ternary and hands it to the arriving buffer. `<M-S-f>` hands it the buffer just left, which is guard 2's own case, but `<M-S-f>` goes through `reconcile_triquetra` (`lua/cavediver/domains/window/routines.lua:93-135`), which has no guard 2.
- **The test:** a sandbox-only check that drops the arriving buffer's plain ternary note when it names the ternary after the arrival, on every `reconcile_triquetra` arrival and on plain `:e` onto the secondary. It took the ternary throws from 13 to **0** in the same walks, with no new error (variant `rt_tb`, Q6 on all four routes plus the check) **[sim]**. Dropping the note is a blunt stand-in: it fired 313 times and loses those notes. It shows the cause, not a chosen fix.
- **Relation to the options:** it's the same missing arrival check as the secondary's. Option 3 and the guard (+G) apply guard 2 to `dsm`; this applies it to `dtm` on the arrivals guard 2 doesn't cover. No option above changes `dtm`, so none of them fixes these: 13–14 under every variant.

Two of them, shrunk, under Q6 on all four routes and with the check **[run, sim `rt_bonus1`, `rt_bonus2`]**:

{{B rt_bonus1 today,rt_q6,rt_tb}}

- `e` left by navigation with the note `e>c`, then graduated. `<M-f>` brings `e` back while the window's ternary is `c`.

{{B rt_bonus2 today,rt_q6,rt_tb}}

- `d` left with the note `d>a`. Coming back from `a` by `:e d` would have run guard 2 and rewritten it; coming back by `<M-S-f>` doesn't.

---

## The question

How should a swap onto the secondary write its notes so that `<M-;><M-t>` never finds its own secondary: (1) a note only when the partner changes, plus the guard (proposed); (2) two kinds like the ternary, plus the guard; (3) one kind, with the toggle back clearing the stale note?

---

## Runs

| Run | What it shows | Code |
|---|---|---|
| `rt_sec_round` | `<M-f>` round trip, then `<M-;><M-t>` (R1, Check 1) | today, all variants |
| `rt_sec_round_older` | an older graduation note, a round trip, the restore (item 1, Check 7) | today, all variants |
| `rt_ter_round`, `rt_ter_round_older` | the ternary's round trip, with and without an older plain note (item 1) | today, `plain` |
| `rt_route_nav_back`, `rt_route_pick_back`, `rt_route_primary`, `rt_route_ternback`, `rt_route_grad` | routes R2–R6 (Checks 5, 6, 11) | today, all variants |
| `rt_route_flip` | route R8, a 21-key walk replayed (`t/rt_seqrows.lua`) | today, decided, TK, SC, PCd, TK+G, PCd+G, both W |
| `rt_cand_round_e` | plain `:e` round trip (R7, Check 2) | today, all variants |
| `rt_cand_use` | `d`'s old secondary comes back and flip-flops (Check 3) | today, all variants |
| `rt_cand_q3`, `rt_cand_q3t` | Q3 both ways (Check 4) | today, all variants |
| `rt_keep_restore`, `rt_keep_partner` | P13 memory checks (Checks 8, 9) | today, all variants |
| `rt_c1_assert` | Q13's throw under TK's lookup (Check 10) | TK |
| `rt_q3_oldswap` | Q3 with an old swap note on the graduating buffer (Check 12) | today, decided, SC, TK, PCd, TK+G, PCd+G |
| `rt_sec_missing` | a secondary note naming a deleted file (Check 13) | today, decided, SC, TK+G, PCd+G |
| `rt_resid_nav` | a residual route through navigation, shrunk from a walk | PCd+G, TK+G, both W, today |
| `rt_bonus1`, `rt_bonus2` | two ternary throws, shrunk from walks | today, Q6, the bonus check |
| walks | `rt/rt_walk.py 1500 25 7 <variant>`, sorted by `rt/rt_classify.py` | today, Q6 (reconcile only), Q6 on all four routes, decided, every option variant, the bonus check |

Variant names: decided `rt_base`; Q6 alone `rt_q6` (all four routes) and `rt_C` (reconcile only, the earlier walks' variant); TK-as-is `rt_c1`; TK `rt_c1s`; SK `rt_c2a`; SC `rt_c2b`; PC `rt_c3`; PCd `rt_c3k`; TK+G `rt_c1sg`; PCd+G `rt_c3kg`; widened `rt_c1sga`, `rt_c3kga`, `rt_c2bga`; the bonus check `rt_tb`; swaps writing plain ternary notes `plain` (from earlier work).
