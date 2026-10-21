# Question packets B: cycling, notes and restores

Seven packets. Each one has the stakes, a recap built from zero, any text that would go into the author's files, and then the question.

**How things are cited**
- Code paths are relative to the repo, for example `lua/cavediver/domains/window/routines.lua:115`.
- `README.md:N`, `DESK.md:N`, `what-is-cavediver.md:N`, `WINDOW_BUFFER_RELATIONSHIP_SPECIFICATION.md:N` ("SPEC") and `CURRENT_IMPLEMENTATION_STATUS.md:N` ("STATUS") are the repo files.
- "The author, date time" quotes the author's own answer or message, in local time, word for word, typos included.
- "The session, date time" is a message the session put to the author.
- Runs are named `pkB_*`. Each one is a headless scenario at `<sandbox>/t/pkB_*.lua`, run with `<sandbox>/t/run_b.sh`. The full list is at the end.
- Evidence tags:
  - **[run]**: seen in a run.
  - **[code]**: read from the code, not run.
  - **[inferred]**: reasoned from the code, not checked.
  - **[sim]**: a run in which the scenario itself stands in for a change that isn't built, either a decided one or one of the options. The scenario says exactly what it simulates.

**Shared terms** (used by every packet)
- **Triquetra:** a window's slots. Current `c` is the buffer the window is on. Secondary `s` is the buffer you parked. Ternary `t` is your previous buffer. The primary queue is `p`. Notation: `c=a s=b t=c`.
- **Note:** a remembered value that a restore brings back.
- **Ternary memory (`dtm`):** each buffer's remembered ternary, which `<M-;><M-r>` restores. It holds two kinds of note:
  - **Plain note** `dtm[X]`: written when you leave X by plain navigation such as `:e`.
  - **Swap note** `dtm[X-swap]`: written when you leave X by a swap (`<M-f>`, `<M-S-f>`) or a primary jump.
  - Runs print a plain note as `x.txt>y.txt` and a swap note as `x.txt-swap>y.txt`.
- **Secondary memory (`dsm`):** each buffer's remembered secondary, which `<M-;><M-t>` restores. Today it's written by `<M-f>`'s swap, by graduation, and by the secondary restore's flip-flop (`what-is-cavediver.md:243`).
- **Restore:** `<M-;><M-r>` and `<M-;><M-t>`. A restore swaps the slot with the note and writes the slot's old value back as the plain note, so pressing it twice flip-flops (P19, `what-is-cavediver.md:71`). The ternary restore uses the swap note first, unless the swap note equals the current ternary; then it uses the plain note (`lua/cavediver/domains/window/routines.lua:718-722`).
- **Cycling:**
  - `<M-n>` and `<M-m>` step through buffers. While you step, history is detached and the current slot stays on the buffer you started from.
  - `<M-v>` picks the shown buffer and ends the cycle (Q1, `what-is-cavediver.md:1522-1524`).
  - The buffer you started from is **the start**, also called the checkpoint. The code calls it the cycling origin.
- **Q6's guard** (the secondary-landing fix): when a key lands you on the secondary, it rewrites the ternary's note to the buffer you're leaving, before the swap. Without it, a later `<M-;><M-r>` throws. The author decided it runs before the swap on every route onto the secondary (Q6, `what-is-cavediver.md:1549`). Today it runs after the swap, where its rewrite does nothing (`what-is-cavediver.md:580`), and plain `:e` onto the secondary has no guard at all (`lua/cavediver/domains/window/hooks.lua:52-54`). Its warning reads "Avoided conflict…".
- **IDs.** All of these live in `what-is-cavediver.md` and are glossed where they're used:
  - Pn is a principle, An an action, In an invariant, Dn a disagreement and Tn a planned test.
  - Qn is the author's answer n of 2026-10-20 (section 8).

## Order to ask, and dependencies

1. **Item 1 first.**
   - Item 1 covers `<M-f>`, `<M-S-f>` and the restores only. `<M-;><M-f>` is item 2's question, so the two can't clash.
   - Item 2's option B makes a primary jump while cycling, and a primary jump writes a swap note. Under B, that note follows item 1's answer: written under item 1 A, not written under item 1 B.
   - Both of item 1's options leave the pick's own writes (Q9's note included) alone. That way no answer to item 1 can undo Q9 or item 3.
2. **Item 4 before item 2.**
   - Item 2 asks what `<M-;><M-f>` does "on the start". Item 4 decides what "the start" is: today it's the window's current slot, and with a copy it would be the buffer the cycle began on.
3. **Item 2** after 1 and 4.
4. **Item 3** any time after item 1. It doesn't depend on item 2.
   - One small link to item 4: Q9's note names "the start". Today that's the buffer that leaves the slots at the pick. Under item 4's option B, the original start and that buffer could differ. The note should still name the buffer that leaves.
5. **Items 5, 6 and 7** are independent of the others and of each other.

---

## 1. P18 against Q7: does a slot key on the cycle's start write its notes?

**Stakes:** this decides whether the same keys give the same restore inside and outside a cycle, and which of the spec's lines changes, the principle or the code. Today a swap on the start writes the same notes as anywhere else. If P18 holds literally, `<M-;><M-r>` later brings back an older buffer (run below).

**Recap**

1. **What it is.**
   - P18 is a principle in the spec: "Cycling is exploration: no visits are recorded and no displacement entries are written while cycling; `<M-v>` picks." (`what-is-cavediver.md:70`). A "displacement entry" is a note.
   - In this packet a **slot key** is `<M-f>` (swap with the secondary), `<M-S-f>` (swap with the ternary) or a restore. `<M-;><M-f>` (jump to the primary) has its own branch while cycling and is item 2.
   - While cycling, a slot key does one of two things:
     - If the window shows a buffer that isn't its current slot, `<M-f>` and `<M-S-f>` only jump back to the current slot (`lua/cavediver/domains/window/routines.lua:474-478`, `:558-562`).
     - If the window shows the start, they do a real swap.
2. **Why it matters, and what was tested.** Run pkB_cycle_keys: the start is `c`, the primary is `e`, and the keys are pressed with navigation in `cycling`.
   ```
   setup: shown=c.txt c=c.txt s=b.txt t=d.txt p=[e.txt]on dtm={a.txt>e.txt,b.txt>a.txt} dsm={b.txt>a.txt} nav=normal
   <M-S-f> (on the start): shown=d.txt c=d.txt s=b.txt t=c.txt ... dtm={a.txt>e.txt,b.txt>a.txt,c.txt-swap>d.txt} ... nav=cycling
   <M-S-f> (on the start again): shown=c.txt c=c.txt s=b.txt t=d.txt ... dtm={...,c.txt-swap>d.txt,d.txt-swap>c.txt} ... nav=cycling
   <M-f> (on the start): shown=b.txt c=b.txt s=c.txt t=d.txt ... dsm={b.txt>a.txt,c.txt>b.txt} nav=cycling
   <M-;><M-r>: shown=b.txt c=b.txt s=c.txt t=a.txt ... dtm={a.txt>e.txt,b.txt>d.txt,...} ... nav=cycling
     navigation state read inside the pick's reconcile_triquetra: cycling
   ```
   - While cycling, `<M-S-f>` wrote two swap notes, `<M-f>` wrote a secondary note, and the restore rewrote b's plain note **[run]**.
   - `<M-f>` also writes the swap note `dtm[c-swap] := d` (`lua/cavediver/domains/window/routines.lua:497-499`). The run can't show it, because the same value was already there **[code]**.
   - **The pick writes too.** `<M-v>` attaches history from inside navigation's `cycling→normal` hook (`lua/cavediver/domains/navigation/hooks.lua:23-28`), so navigation still reads `cycling` while the pick writes its notes **[run]**. Those writes are:
     - the swap note when you pick the ternary (`lua/cavediver/domains/window/routines.lua:107`)
     - Q6's guard
     - Q9's note
3. **What's already decided.**
   - **P18, as put to the author.**
     - The session, 2026-10-20 14:05, in a table: "Cycling is exploration: no visits recorded, no displacement written; the current slot stays put until `<M-v>` picks".
     - The session, 2026-10-20 14:11, with an example that only steps (`<M-n>` to `b`, "the slots still say "on e" and nothing is recorded").
     - The session, 2026-10-20 14:17, restating: "**P18:** cycling is exploration: nothing is recorded until `<M-v>` picks. The open details are Q1 and Q9."
     - The author, 2026-10-20 14:17: "Yes, all eight".
     - Which of the wordings that yes covers isn't stated. Slot keys pressed mid-cycle weren't part of any of the three messages.
   - **Q7.** The question put to the author was "Stakes: whether a slot key mid-cycle can quietly change your slots. What do <M-f>, <M-S-f> and <M-;><M-f> do while cycling?", with three options. The first was "Cancel the cycle, nothing else (Recommended)", described as "Always: back to the start, out of cycling; no swap even when you're showing the start. Predictable (P20)." The author, 2026-10-20 15:37: "bro, just take a look, I already dealt with that." The author picked none of the three. My reading: "no swap even when you're showing the start" is turned down, and the code is what they pointed at. Map writes weren't mentioned.
   - **Q2.** The author, 2026-10-20 14:26: "Yes, today's is intended", that is, both kinds of note. They added: "I remember it was a way to circumvent around some edge cases you know, because without it would exhibit some unintuitive shits. Now, I forgot. That swap thing is kinda very abstract and a year of not thinking about makes me forget what it really solves."
   - **Q9.** The author, 2026-10-20 15:40: "Leave a note (restore brings it back)". That note is written by the pick.
4. **Where P18 comes from.**
   - README.md:384: "no matter how you cycle, the current slot buffer doesn't change. It is because during cycling mode, the cavediver plugin has stopped tracking visits." That's about visits and the current slot only.
   - SPEC:32-37: "Direct slot manipulation without creating displacement mappings". SPEC:413: "All keymap operations work but don't trigger displacement". SPEC:553-557: "No displacement mappings created or consumed during cycling". **The old spec did mean the slot keys too.**
     - But in the old spec the slot keys acted on the cycled-to buffer (SPEC:197-205, SPEC:385-407), which the settled disagreement on the current slot while cycling (D10) calls out of date (`what-is-cavediver.md:1243`).
     - SPEC:211-213 also has a restore "work normally" mid-cycle, which consumes a note.
   - DESK.md:42: "**Cycling**: the mode (`<M-n>`, `<M-m>`) for stepping through buffers without touching the triquetra; `<M-v>` picks one."
   - STATUS:59 and STATUS:432: "Pure slot operations ... (no displacement mappings)".
   - The settled disagreement on swap notes (D7) calls SPEC:239-244 out of date (`what-is-cavediver.md:1222`). That range also holds SPEC:242 and SPEC:244, which are about cycling ("Any operations during cycling/detached mode"). So the files now say SPEC:244 is out of date while P18 cites the same idea from SPEC:30-37 and SPEC:546.
5. **How they collide.** Read literally, P18 forbids what the code does and what the author kept at Q7: a real swap on the start, notes included. Read as "the steps only", P18 and the code agree.
   - **What a "no notes while cycling" rule would change.** Runs pkB_p18_normal, pkB_p18_today and pkB_p18_suppress press the same keys: start at `c=c t=d`, `<M-S-f>`, `:e e`, `:e c`, `<M-;><M-r>`. The difference is where the swap happens: outside a cycle, on the start of a cycle today, or on the start of a cycle with that swap's notes undone.
   ```
   normal:   <M-;><M-r> on c: c=c.txt s=- t=d.txt ...
   today:    <M-;><M-r> on c: c=c.txt s=- t=d.txt ...
   suppress: <M-;><M-r> on c: c=c.txt s=- t=b.txt ...   (an older buffer)
   ```
   - With the notes undone, the same swap gives a different restore, depending on whether you were cycling **[sim]**. This is the effect the author's Q2 reason describes for swaps that write nothing (`what-is-cavediver.md:1530`).
6. **The way out.**
   - **A, proposed (Kate):** P18 covers the cycle's steps only (`<M-n>`/`<M-m>`). A slot key pressed while the window shows its current slot does its normal job, notes included, cycling or not. That's today's code.
   - **B:** while cycling, a slot key's swap happens but writes no notes. That narrows the answer on swap notes (Q2): swaps would write them only outside a cycle. It also needs two exceptions:
     - Q6's guard has to keep running when a key lands on the secondary, or the restore throw it prevents comes back mid-cycle **[inferred]**.
     - A restore needs its own rule: blocked mid-cycle, or still writing its flip-flop note. Without its write, the flip-flop (P19) breaks **[inferred]**.
   - **Either way:** the pick's writes stay, because `<M-v>` ends the cycle. Those are the swap note when you pick the ternary, Q6's guard and Q9's note.

**Text for the author's files.** If A, P18's row in `what-is-cavediver.md:70` changes. This is plain wording: the row has no sample of the author's own writing.
> Cycling is exploration: stepping with `<M-n>`/`<M-m>` records no visits and writes no displacement entries; `<M-v>` picks. `<M-f>`, `<M-S-f>` and the restores, pressed while the window shows its current slot, do their normal job, notes included, cycling or not.

**The question:** when you press `<M-f>`, `<M-S-f>` or a restore on the cycle's start, does it write its notes just as it would outside a cycle?
- **A. Yes, "no notes while cycling" is about the steps (today), proposed (Kate):** the same keys always leave the same notes. The principle's wording changes, and the code doesn't.
- **B. No notes while cycling:** the swap still happens, but a restore later can bring back an older buffer (run above). The secondary-landing fix needs an exception, and restores need a rule of their own.

---

## 2. `<M-;><M-f>` on the start while cycling

**Stakes:** whether `<M-;><M-f>` mid-cycle can ever take you to your primary, or always just brings you back to the start. The spec's Q7 entry currently says something the author never said.

**Recap**

1. **What it is.**
   - `<M-;><M-f>` jumps to the primary. Its normal job, from `c=A t=T`:
     - The primary P becomes the current, and A becomes the ternary.
     - It writes the swap note `dtm[A-swap] := T` (`lua/cavediver/domains/window/routines.lua:651-654`).
   - While cycling, it always runs a separate branch instead (`lua/cavediver/domains/window/routines.lua:612-631`):
     - It switches to the start, sets the current slot to it, and says "Returned to cycling origin buffer: …".
     - It stays in cycling.
2. **Why it matters, and what was tested.** Run pkB_cycle_keys, with the primary `e`:
   ```
   <M-n> (cycled away): shown=e.txt c=c.txt s=b.txt t=d.txt p=[e.txt]on ... nav=cycling
     [notify 2] Returned to cycling origin buffer: c.txt
   <M-;><M-f> (away: back to the start): shown=c.txt c=c.txt s=b.txt t=d.txt ... nav=cycling
     [notify 2] Returned to cycling origin buffer: c.txt
   <M-;><M-f> (on the start): shown=c.txt c=c.txt s=b.txt t=d.txt ... nav=cycling
   ...
   <M-;><M-f> (normal mode): shown=e.txt c=e.txt s=c.txt t=b.txt ... dtm={...,b.txt-swap>a.txt,...}
   ```
   On the start it repeats the message and changes nothing. Outside a cycle it jumps to the primary and writes a swap note **[run]**.
3. **What's already decided.**
   - The author's Q7 words, 2026-10-20 15:37.
     - To the cancel question: "no, <M-v> is for that, after your press <M-f> to go back to the starting buffer."
     - To "What do <M-f>, <M-S-f> and <M-;><M-f> do while cycling?": "bro, just take a look, I already dealt with that." The question had offered three options:
       - "Cancel the cycle, nothing else (Recommended)": "Always: back to the start, out of cycling; no swap even when you're showing the start. Predictable (P20)."
       - "Pick, then act": "The old spec: treat the shown buffer as picked, then do the swap or jump from there."
       - "Do nothing while cycling": "Slot keys are blocked until you pick or cancel."
   - **The spec's "rule" is the session's summary of the code, not the author's words.**
     - `what-is-cavediver.md:1559-1561` and `:780-783` say: "When the window isn't showing its current slot, `<M-f>` and `<M-S-f>` jump back to it, and `<M-;><M-f>` returns to the cycling origin. When it is showing it, they do their normal job, cycling or not."
     - The session wrote that after reading the code, right after the answer. No later answer in the transcript touches Q7. The 15:56 question that approved folding the answers into the file ("Go ahead: fold all the answers into what-is-cavediver.md …") didn't show this wording.
     - It's accurate for `<M-f>` and `<M-S-f>`. For `<M-;><M-f>` it isn't: the code's cycling branch runs whether or not the window is on the start.
   - The spec's own section on `<M-;><M-f>` (A8) already labels that branch intended: "The cycling branch is intended (SPEC:206-209)" (`what-is-cavediver.md:630`). SPEC:206-209 reads: "Always returns to cycling start point (checkpoint buffer)" and "Ignores primary buffer logic, always goes to checkpoint". SPEC:421 says the same.
4. **Other rules involved.**
   - Q10: with the primary disabled, `<M-;><M-f>` acts like `<M-f>` (`what-is-cavediver.md:1575`).
   - Q6: that fallback is a route onto the secondary, so it gets the guard.
   - Item 4 decides what "the start" is.
5. **How they collide.** "Read literally, Q7's rule has it jump to the primary" reads the session's summary literally. The author's literal words point at the code, and the code, SPEC:206-209 and the spec's own label on that branch all say "always back to the start".
6. **The way out.**
   - **A, proposed (Kate):** keep today. While cycling, `<M-;><M-f>` always returns to the start, and on the start it says so and changes nothing. Only the spec's summary is corrected. This is the literal reading of the author's Q7 words, and it matches SPEC:206-209.
   - **B:** on the start, it does its normal job: a primary jump while still cycling. That writes a swap note (unless item 1 is answered B), acts like `<M-f>` when the primary is off (Q10), and takes Q6's guard on that fallback. It changes the code the author pointed at for Q7.

**Text for the author's files.** None for README or code. If A, the Q7 summary at `what-is-cavediver.md:1559-1561` and `:780-783` is corrected, in plain wording:
> When the window isn't showing its current slot, `<M-f>` and `<M-S-f>` jump back to it; when it is, they do their normal job, cycling or not. While cycling, `<M-;><M-f>` always returns to the cycle's start, and on the start it only says so.

**The question:** while cycling, with the window already on the start, what does `<M-;><M-f>` do?
- **A. Return to the start, always (today), proposed (Kate):** it never jumps to the primary mid-cycle. Only the spec's summary of Q7 changes.
- **B. Its normal job:** it jumps to the primary while still cycling, writing a swap note and falling back to `<M-f>` when the primary is off. The code changes.

---

## 3. Q9's note against an older swap note

**Stakes:** Q9 promised that after picking an outside buffer in a cycle, `<M-;><M-r>` brings the start back. If the picked buffer was ever left by a swap, an older note wins and the start is lost for good. It's lost after the first restore.

**Recap**

1. **What it is.** A cycling pick of a buffer outside the slots ("outside" meaning it isn't current, secondary or ternary) replaces the current slot. The start leaves the triquetra, and today it isn't remembered (`what-is-cavediver.md:748`).
2. **Why it matters, and what was tested.**
   - **Setup:** `:e a`, `:e b`, then `<M-S-f>`, so b is left by a swap and gets `dtm[b-swap] := a`. Then `:e c`, `:e d`, `:e e`, `<M-n>` to b, `<M-v>`.
   - **The runs:** run pkB_q9_today is the code as it is. Run pkB_q9_note simulates Q9's write `dtm[b] := e` right after the pick. Run pkB_q9_note_clear does the same and also clears `dtm[b-swap]`.
   ```
   pick:  c=b.txt s=- t=d.txt  dtm={...,b.txt-swap>a.txt,...}
   today:      <M-;><M-r> → t=a.txt   again → t=d.txt
   note:       after pick dtm has b.txt-swap>a.txt, b.txt>e.txt
               <M-;><M-r> → t=a.txt, dtm b.txt>d.txt   again → t=d.txt, dtm b.txt>a.txt
   note_clear: after pick dtm has b.txt>e.txt (no b.txt-swap)
               <M-;><M-r> → t=e.txt, dtm b.txt>d.txt   again → t=d.txt, dtm b.txt>e.txt
   ```
   - With the note alone, the restore uses the older swap note, so the ternary becomes a. The restore's flip-flop write then overwrites the plain note `e` with `d`, and e can't come back by any restore **[sim]**.
   - With the swap note cleared, e comes back and flip-flops with d **[sim]**.
3. **What's already decided.**
   - The author, 2026-10-20 15:40, chose "Leave a note (restore brings it back)", whose description read: "The pick records 'b's previous was e' in b's ternary memory; the ternary itself stays as the README says; <M-;><M-r> on b brings e back."
   - That text doesn't say whether the note is a plain note or a swap note. "Plain note `dtm[X] := start`" is the spec's rendering (`what-is-cavediver.md:249`, `:767`, `:1571`).
   - The planned test for the pick's note (T155) is scoped to "with no `dtm[b-swap]`" (`what-is-cavediver.md:1405`).
4. **Other rules involved.**
   - **Plain navigation (A1):** its note write clears that same buffer's swap note first (`lua/cavediver/domains/window/hooks.lua:66-69`).
   - **Other plain-note writers don't clear the swap note:**
     - the navigation guard that rewrites the arrived buffer's note when it names the buffer being left ("guard 2", `lua/cavediver/domains/window/hooks.lua:71-85`)
     - Q6's guard (`lua/cavediver/domains/window/routines.lua:123-124`)
     - the restore's flip-flop write (`lua/cavediver/domains/window/routines.lua:759`)
   - So the code has no general rule here.
   - **The answer on swap notes (Q2):** the restore prefers the swap note (`lua/cavediver/domains/window/routines.lua:718-722`).
5. **How they collide.** Q9's promise holds only when the picked buffer has no swap note, or its swap note equals the current ternary.
6. **The way out.**
   - **A, proposed (Kate):** the pick's note also clears the picked buffer's swap note, as plain navigation's write does for its own buffer.
   - **B:** the pick writes a swap note instead (`dtm[b-swap] := e`). Right after the pick it behaves the same (run pkB_q9_swapnote: e, then d) **[sim]**. A `<M-S-f>` round trip then overwrites it, and the start is lost. Runs pkB_q9_swapnote_toggle and pkB_q9_note_clear_toggle, after the pick, press `<M-S-f>` `<M-S-f>` `<M-;><M-r>`:
     ```
     note_clear + toggle: <M-;><M-r> on b → t=e.txt
     swapnote + toggle:   [notify 3] No ternary relationship found for restoration. ...
     ```
     So B keeps Q9's promise only until you toggle **[sim]**.

**The question:** when a pick leaves its note on the picked buffer, does it also clear that buffer's older swap note, so the restore brings the start back as your answer on cycling picks promised?
- **A. Yes, clear it, proposed (Kate):** the start comes back after the pick, and still after a `<M-S-f>` round trip (run). The older swap note is gone. Leaving b by navigation later replaces the note, as it replaces any note.
- **B. Write the note as a swap note instead:** the start comes back right after the pick, but a `<M-S-f>` round trip erases it (run).

---

## 4. D15. The cycle's checkpoint: a copy or a live reference?

**Stakes:** whether `<M-;><M-f>` mid-cycle goes to the window's current slot (which a swap or a close can move during the cycle) or to the buffer the cycle began on. With a copy, today's code puts one buffer in two slots or throws.

**Recap**

1. **What it is.**
   - When a cycle starts, `snapshot_origin` stores the checkpoint (`lua/cavediver/domains/history/routines.lua:373-400`).
     - Its docstring says it "Captures the current window's triquetra state for restoration after cycling" and "Stores a deep copy of the window relationships for later restoration" (`:369-370`).
     - But it stores the window's live triquetra (`:376`), then sets that table's current slot to the shown buffer (`:392`) **[code]**.
   - Only `<M-;><M-f>`'s cycling branch reads it (`lua/cavediver/domains/window/routines.lua:612-631`, via `lua/cavediver/domains/history/init.lua:134-136`). Nothing restores from it after cycling **[code]**.
   - It's never cleared after the pick, only by `repopulate_history` (`lua/cavediver/domains/history/routines.lua:792`) **[code]**.
   - It has been the live table since the repo's first commit (fa2c1b2, 2025-07-07, by `git log -S`).
   - STATUS:140 also says "Cycling origin snapshots for restoration after cycling".
2. **Why it matters, and what was tested.**
   - The difference only shows when the current slot changes during a cycle and you then press `<M-;><M-f>`.
   - The "copy" runs simulate a copy by replacing the checkpoint with `vim.deepcopy` of itself right after the cycle starts **[sim]**. Start: `c=c s=b t=d`.
   - **Swap on the start, then away and `<M-;><M-f>`** (runs pkB_d15_swap_live and pkB_d15_swap_copy):
   ```
   live: origin: d.txt (live table)
         <M-;><M-f>: shown=d.txt c=d.txt s=b.txt t=c.txt ...
   copy: origin: c.txt (copy)
         <M-;><M-f>: shown=c.txt c=c.txt s=b.txt t=c.txt ...   (c in two slots)
         <M-S-f>:    shown=c.txt c=c.txt s=b.txt t=c.txt ...   (nothing happens)
         <M-v>:      shown=c.txt c=c.txt s=b.txt t=c.txt ... nav=normal
   ```
   - **`:bdelete` of the start mid-cycle, then `<M-;><M-f>`** (runs pkB_d15_close_live and pkB_d15_close_copy):
   ```
   live: [notify nil] Healed the triquetra of window 1000 with current slot: 1
         :bdelete c (the start): shown=a.txt c=a.txt s=b.txt t=d.txt ... nav=cycling
         origin: a.txt (live table)
         [notify 2] Returned to cycling origin buffer: a.txt
         <M-;><M-f>: shown=a.txt c=a.txt s=b.txt t=d.txt ... nav=cycling
   copy: :bdelete c (the start): shown=a.txt c=a.txt s=b.txt t=d.txt ... nav=cycling
         origin: c.txt (copy)
         <M-;><M-f> ERROR: .../window/routines.lua:623: This should not happen. Origin buffer not found for current slot: <hash>
   ```
   - The live table follows the slot. A copy points `<M-;><M-f>` at a buffer that's now the ternary (a duplicate, which breaks "no buffer in two slots": P16 at `what-is-cavediver.md:68` and I1 at `:1030`), or at a closed buffer (a throw) **[sim]**.
3. **What's already decided.**
   - **Q1:** "Frozen until <M-v> (Recommended)" (the author, 2026-10-20 14:19). The current slot stays on the start until the pick.
   - **Q7:** a swap on the start is kept (item 1, recap 3).
   - `what-is-cavediver.md:271` already describes the live table as today's behaviour.
4. **Other rules involved.** The author on comments, 2026-10-20 18:50: "make it general, remember timeless, no specific cases mentioned." That applies to any new docstring.
5. **How they collide.** The docstring says copy, and the code says live. My reading of Q1 and Q7 together is that "the start" is the current slot, since the current slot stays on the start and a swap on the start is allowed. That's what the live table gives. A copy would also need rules for a start that moved into another slot or got closed.
6. **The way out.**
   - **A, proposed (Kate):** live is intended, and the docstring changes. `<M-;><M-f>` mid-cycle goes to the current slot. The stored table then adds nothing over the triquetra itself; dropping it is an implementation detail, not part of the question.
   - **B:** a copy, so `<M-;><M-f>` returns to the buffer the cycle began on. It then needs rules for when that buffer has become the ternary or the secondary, or has been closed.

**Text for the author's files.** If A, the docstring at `lua/cavediver/domains/history/routines.lua:367-370` changes, in plain wording. No sample of the author's own writing for this docstring is at hand: the text came in with the repo's first commit, and who wrote it is unverified.
```lua
---Mark the window's triquetra as the cycle's checkpoint.
---
---The checkpoint is the window's own triquetra, not a copy, so it always
---names the window's current slot.
```

**The question:** what is the cycle's start: the window's current slot (which a swap or a close during the cycle can move), or the buffer the cycle began on?
- **A. The current slot (live, today), proposed (Kate):** `<M-;><M-f>` mid-cycle always lands on the current slot. Only the docstring changes.
- **B. The buffer the cycle began on (a copy):** `<M-;><M-f>` goes back there, and it needs new rules for a start that has moved into another slot or been closed. Today's code makes a duplicate or throws in those cases (run).

---

## 5. D8. Reaching the secondary by plain navigation

**Stakes:** whether `<M-;><M-t>` can bring back a buffer's old secondary when you reached the secondary with `:e` or the bufferline instead of `<M-f>`. Also whether README.md:355 stays as written.

**Recap**

1. **What it is.**
   - P14 is a principle: "The secondary is yours: it changes only when you act". Going to the secondary's file any way counts as acting, and swaps current and secondary (`what-is-cavediver.md:66`). The author, 2026-10-20 14:17: "oh okay. yeah P14 is correct."
   - Plain `:e` onto the secondary swaps the slots (`lua/cavediver/domains/window/hooks.lua:52-54`) and writes no note.
   - `<M-f>` writes two notes before its swap:
     - `dsm[A] := S` (`lua/cavediver/domains/window/routines.lua:496`)
     - `dtm[A-swap] := T` when there's a ternary (`:497-499`)
2. **Why it matters, and what was tested.**
   - The "write" runs simulate `<M-f>`'s secondary note on the plain route **[sim]**.
   - **Run pkB_d8_use:** from `c=d s=b t=c`, `:e b`, `:e e`, `<M-f>` back to d (now `s=e`), then `<M-;><M-t>` on d.
   ```
   today: [notify 3] No secondary relationship found for restoration. ...
          <M-;><M-t> on d: c=d.txt s=e.txt t=b.txt ...
   write: [notify 2] Restored secondary slot to: ... (b.txt)
          <M-;><M-t> on d: c=d.txt s=b.txt t=e.txt ... dsm={...,d.txt>e.txt,...}
   ```
   - **Run pkB_d8_round:** `:e b`, then `:e d`, back by the same route, then `<M-;><M-t>` on d.
   ```
   today: [notify 3] No secondary relationship found for restoration. ...
   write: <M-;><M-t> ERROR: .../window/routines.lua:738: This is impossible. Remembered secondary is the same as current secondary. It should be different for flip flop.
   ```
   - **The same throw is reachable today with `<M-f>` alone** (run pkB_secflip):
   ```
   :e a, :e b, :e c, <M-f> (graduation): c=c.txt s=b.txt t=- ... dsm={b.txt>a.txt}
   <M-f>: c=b.txt s=c.txt ... dsm={b.txt>a.txt,c.txt>b.txt}
   <M-f>: c=c.txt s=b.txt ... dsm={b.txt>c.txt,c.txt>b.txt}
   <M-;><M-t> ERROR: .../window/routines.lua:738: This is impossible. Remembered secondary is the same as current secondary. ...
   ```
   - So writing on the plain route gains the restore in the first case. It also adds a second way into a throw that `<M-f>` already reaches today **[run]**.
   - That throw needs a fix of its own whatever the answer here, because T154 says neither restore ever throws (`what-is-cavediver.md:1496`). It also makes the planned test T63 ("Restoring the secondary flip-flops between `dsm[A]` and the current secondary", `what-is-cavediver.md:1384`) false in the "swap back" example state of the spec's `<M-f>` section (A6), `dsm{b→c, c→b}`. It isn't asked here.
3. **What's already decided.**
   - **Q6:** the author, 2026-10-20 15:35: "Yes, guard before the swap (Recommended)". The question named "plain :e onto it" as one of the routes, so the guard runs on this route too.
   - **Q3:** graduation copies the ternary note into the secondary note. The author, 2026-10-20 14:34: "It's either you restore a as a ternary or secondary. Maybe that was my intention".
   - **Q13:** the author, 2026-10-20 15:51: "Keep the assertion (throw)". Any route that reaches the throw is a bug, to be hunted by the planned test T154.
4. **Other rules involved.**
   - README.md:353: "To jump to the secondary buffer, simply press `<m-f>`."
   - README.md:355: "Every time you jump to secondary the system also records the current buffers, secondary – just the same as ternary's way but with keys `<m-;><m-t>`".
   - The README's own wording of "jump to secondary" is the `<m-f>` key.
5. **How they collide.**
   - P14 and Q6 treat every route onto the secondary as the same act. The notes are the one difference left.
   - README.md:355 reads as either "every route" or "every `<m-f>`".
6. **The way out.**
   - **A, proposed (Kate):** plain navigation onto the secondary writes whatever `<M-f>` writes, so arriving there is one act however you get there, as P14 and Q6 already have it. README.md:355 holds as written.
   - **B:** plain navigation onto the secondary writes nothing. README.md:355 names the key.

**Text for the author's files.**
- If A: none.
- If B: README.md:355, in the author's voice. The sample is the line itself (README.md:355) plus README.md:353's "simply press `<m-f>`". Only "with `<m-f>`" is added:
> Every time you jump to secondary with `<m-f>` the system also records the current buffers, secondary – just the same as ternary's way but with keys `<m-;><m-t>`

**The question:** when you reach the secondary with plain navigation, does it record the same notes as `<M-f>`?
- **A. The same as `<M-f>`, proposed (Kate):** `<M-;><M-t>` works after either route, and README.md:355 stays. It also inherits the secondary-restore throw that `<M-f>` has today, until that's fixed.
- **B. Nothing:** only `<M-f>` records, and README.md:355 gains "with `<m-f>`".

---

## 6. D9, the rest. Restore edge cases

Three separate parts. Two are already settled by the desk, so only the missing-file part has a question.

### 6a. A remembered value with no path: settled by the desk

**Stakes:** a restore crashes on a note whose file the plugin has forgotten.

**Recap**

1. **What it is.** "No path" means a note names a buffer whose file name cavediver has forgotten. The restore throws "This impossible error should never happen. Remembered … is not registered in history." (`lua/cavediver/domains/window/routines.lua:732-733`).
2. **What was tested.** Run pkB_d9_nopath: `:e a`, `:enew` with a line typed in, `:e b`, `:e c` (so b's plain note names the No Name buffer). Then the No Name buffer is emptied and closed, and an empty No Name's path is forgotten on close (`lua/cavediver/domains/history/routines.lua:473`). Then `:e b` and `<M-;><M-r>`.
   ```
   N emptied, :bdelete N: ... dtm={?274b55>a.txt,b.txt>?274b55} ...
     path of N still registered: false
   <M-;><M-r> ERROR: .../window/routines.lua:733: This impossible error should never happen. Remembered ternary is not registered in history.
   ```
3. **Decided.**
   - "At an unknown hash: cleared when used" (DESK.md:1228).
   - "At a gone hash in a displacement map or history: follows along" (DESK.md:1230).
   - "Following along also ends the stale-displacement throw" (DESK.md:1309), and the bug entry says "Fixed by following along" (DESK.md:1641).
   - A planned test (T68, a target) already encodes it: "An unknown hash in a map doesn't make a restore throw." (`what-is-cavediver.md:1389`).
   - Q13's assertion is a different case: the remembered value equals the slot.
4. **No question.** D9's "no path" part closes as settled by the desk.

### 6b. A remembered file that's gone from disk: the open part

**Stakes:** today a restore that finds a missing file destroys a good note and keeps the bad one, so the same warning comes back on every press.

**Recap**

1. **What it is.** When the note's file can't be read, the restore warns "Remembered … is not found in filesystem anymore." and clears the buffer's plain note only (`lua/cavediver/domains/window/routines.lua:734-736`). That happens even when it was the swap note that pointed at the missing file.
2. **What was tested.** Run pkB_d9_missing:
   - a's plain note is b, and its swap note is f.
   - f is closed and `f.txt` is deleted on disk. A closed file keeps its path (the closed-stack prune doesn't forget it, `lua/cavediver/domains/history/routines.lua:733-757`).
   ```
   :e d, :e a: c=a.txt s=- t=d.txt ... dtm={a.txt-swap>f.txt,a.txt>b.txt,...}
   :bdelete f, f.txt deleted on disk: ... closed=[f.txt]
     [notify 3] Remembered ternary is not found in filesystem anymore.
   <M-;><M-r> on a: c=a.txt s=- t=d.txt ... dtm={a.txt-swap>f.txt,c.txt>a.txt,...}
     [notify 3] Remembered ternary is not found in filesystem anymore.
   <M-;><M-r> on a again: (unchanged)
   ```
   The good note `a→b` is gone, the swap note `a-swap→f` stays, and every restore stops on it **[run]**.
3. **Decided.**
   - "At a closed file gone from disk: kept, says so when used, works again when it comes back" (DESK.md:1229).
   - "**Pointers to a file that's gone from disk are kept** (decided 2026-10-20). Using one (`<M-S-f>`, `<M-S-w>`, `<CR>` in the picker) says the file isn't on disk right now and leaves the pointer alone, because it may come back" (DESK.md:1302).
   - The desk's memory includes "displacement maps" (DESK.md:1300).
   - **So today's clearing goes against the desk, and nothing gets cleared.**
4. **Other rules involved.**
   - A planned test (T67, a target): "With a `-swap` entry pointing at a deleted file, a second restore doesn't hit the same entry again." (`what-is-cavediver.md:1388`).
   - The flip-flop (P19), and "You can always get back to what once was" (P13, `what-is-cavediver.md:65`).
5. **How they collide.** The desk keeps the note. What it doesn't say is what a restore does with a note it keeps.
6. **The way out.**
   - **A, proposed (Kate): the restore goes through.**
     - It moves the missing file into the slot, writes its flip-flop note, and says the file isn't on disk right now. Then `<M-S-f>` onto it says so too and leaves the pointer alone (DESK.md:1302, decided, not built).
     - The next restore skips the swap note, because it now equals the ternary, and flips back (`lua/cavediver/domains/window/routines.lua:718-722`) **[inferred]**. So the planned test T67 holds as written.
   - **B: the restore refuses.**
     - It says the file isn't on disk right now and changes nothing.
     - A swap note pointing at the missing file then hides the plain note behind it until the file returns, because the restore always looks at the swap note first **[inferred]**.
     - The planned test T67 needs rewording.

**The question:** when a restore's remembered file is missing from disk, does the restore still swap it into the slot (saying so), or refuse and change nothing?
- **A. Go through and say so, proposed (Kate):** the flip-flop keeps working, and the missing file sits in the slot until it comes back.
- **B. Refuse and say so:** nothing moves, and the buffer's other note stays unreachable while the file is missing. The planned test for a missing file's swap note changes.

### 6c. SPEC:700's "open buffer" requirement: settled by the desk

**Stakes:** none for the code. It only decides whether SPEC:700 is out of date.

**Recap**

1. **What it is.**
   - SPEC:700 restores only when the remembered buffer is open (`history.get_buffer_from_hash(remembered) ~= nil`), and SPEC:706-707 throws otherwise.
   - Today's code needs a path and a readable file, and it doesn't reopen anything (`lua/cavediver/domains/window/routines.lua:724-736`).
2. **What was tested.** Run pkB_d9_closed: `:e a`, `:e b`, `:e c`, `:e b`, `:bdelete a`, `<M-;><M-r>`, `<M-S-f>`.
   ```
   :bdelete a: c=b.txt s=- t=c.txt ... closed=[a.txt]
   <M-;><M-r> on b: c=b.txt s=- t=a.txt ... closed=[a.txt]
     [notify 2] File reopened for ternary slot: <sandbox>/run_b/a.txt - old: d9cc9ee9ec361dcc
   <M-S-f>: shown=a.txt c=a.txt s=- t=b.txt ... closed=[]
   ```
   A closed buffer comes back into the slot, and it reopens when used **[run]**.
3. **Decided.**
   - "At a closed hash: kept, reopened when used." (DESK.md:1227).
   - README.md:15: "Closed buffers reopen when accessed through relationships".
   - P13: "You can always get back to what once was" (`what-is-cavediver.md:65`).
4. **No question.** SPEC:700 is out of date.

---

## 7. D11. The secondary's first fill

**Stakes:** whether the first `<M-f>` in a window with nothing to graduate parks a buffer from history (today it can park the current buffer itself, so one buffer sits in two slots) or refuses.

**Recap**

1. **What it is.** With the secondary empty, `<M-f>` doesn't jump (`lua/cavediver/domains/window/routines.lua:480-493`). It does one of three things:
   - With a ternary, it moves the ternary into the secondary ("graduation").
   - Otherwise, with two or more entries in the history list, it takes the second-newest entry.
   - Otherwise it warns.
2. **What was tested.**
   - **Run pkB_d11_fill:**
   ```
     [notify 3] Cannot populate secondary slot - insufficent history.
   :e a, <M-f>  (one buffer in history): win1 ... c=a.txt s=- t=- ...
   :vsplit (fresh window): win2 shown=b.txt c=b.txt s=- t=- ... ordered=b.txt,a.txt
     [notify 2] Secondary buffer populated from history.
   <M-f> in the fresh window: win2 shown=b.txt c=b.txt s=a.txt t=- ...
   <M-f> again: win2 shown=a.txt c=a.txt s=b.txt t=- ... dsm={b.txt>a.txt}
   ```
   - **Run pkB_d11_dup:** a fresh split, entered while the other window is cycling, so the history list is frozen.
   ```
   <C-w>p (to the fresh window): win2 shown=b.txt c=b.txt s=- t=- nav=cycling ordered=c.txt,b.txt,a.txt
     [notify 2] Secondary buffer populated from history.
   <M-f>: win2 shown=b.txt c=b.txt s=b.txt t=- nav=cycling ...
   <M-f> again: win2 shown=b.txt c=b.txt s=b.txt t=- ... dsm={b.txt>b.txt} nav=cycling
   ```
   - The second-newest entry is the current buffer, so b is current and secondary at once **[run]**. DESK.md:1653 reports the same fault "while history is stale after a cycle" without spelling out its route. This run is one route.
3. **What's already decided.**
   - **P14** ("The secondary is yours: it changes only when you act", `what-is-cavediver.md:66`) and **P16** ("A buffer is never in more than one of a triquetra's current, secondary and ternary slots", `:68`) are confirmed (the author, 2026-10-20 14:17: "Yes, all eight").
   - Pressing `<M-f>` is acting, so the fill doesn't break P14.
   - DESK.md:1653 files the duplicate under "Plain fixes". That treats it as a bug. It doesn't decide whether the fill itself stays.
4. **Other rules involved.**
   - The old spec says both things. SPEC:92-94 and SPEC:111 fill "From history" on the first `<M-f>`. SPEC:299-300 says "Only populated when user first uses `<M-f>`" and "No auto-population: Never automatically populated from history". SPEC:300 can be read as "never without the key", which agrees with the code, or "never from history", which doesn't.
   - SPEC:428-447 ("Secondary Population Edge Case") puts the current buffer in the secondary (`current: A, secondary: A`). That breaks SPEC's own Rule 1 (SPEC:343) and P16, so it's out of date and not an option here.
5. **How they collide.** The code fills from the second-newest history entry without checking it against the current slot, which breaks P16 when the history is stale.
6. **The way out.**
   - **A, proposed (Kate):** keep the fill, taking the newest history entry that isn't the window's current buffer. The duplicate route closes, and SPEC:300 is read as "never without the key".
   - **B:** no fill from history. With nothing to graduate, `<M-f>` says so and changes nothing (SPEC:300 read strictly).

**Text for the author's files.**
- If A: none. The message "Secondary buffer populated from history." (`lua/cavediver/domains/window/routines.lua:490`) stays.
- If B: a new message is needed. The nearest sample in the code is "Cannot populate secondary slot - insufficent history." (`lua/cavediver/domains/window/routines.lua:492`), but who wrote that string is unverified, so plain wording: "Cannot populate secondary slot: no ternary to graduate."

**The question:** with an empty secondary and no ternary, what does the first `<M-f>` do?
- **A. Fill from history, skipping the current buffer, proposed (Kate):** the first press still parks a buffer, and never the one you're on.
- **B. Nothing to park:** `<M-f>` only parks a graduated ternary, and otherwise says so.

---

## Runs

All runs are headless, in `<sandbox>/run_b`, with `<sandbox>/t/run_b.sh <sandbox>/t/<file>`. Shared scenario files (`*_common.lua`) are loaded by the small per-mode files.

| Run | What it shows | Item |
|---|---|---|
| pkB_cycle_keys (first version) | Superseded: its setup made the primary the ternary. It showed the same writes while cycling. | 1, 2 |
| pkB_cycle_keys | slot keys and a restore write notes while cycling; `<M-;><M-f>` on the start repeats its message; navigation reads `cycling` during the pick | 1, 2 |
| pkB_p18_normal, pkB_p18_today, pkB_p18_suppress (with pkB_p18_common) | the same swap outside a cycle, on the start, and on the start with its notes undone [sim] | 1 |
| pkB_q9_today, pkB_q9_note, pkB_q9_note_clear (with pkB_q9_common) | Q9's note against an older swap note [sim] | 3 |
| pkB_q9_swapnote, pkB_q9_note_clear (rerun) | the note written as a swap note [sim] | 3 |
| pkB_q9_note_clear_toggle, pkB_q9_swapnote_toggle | the same two after a `<M-S-f>` round trip [sim] | 3 |
| pkB_d15_swap_live, pkB_d15_swap_copy, pkB_d15_close_live, pkB_d15_close_copy (with pkB_d15_common) | the checkpoint as a live table and as a copy [sim] | 4 |
| pkB_d8_use_today, pkB_d8_use_write, pkB_d8_round_today, pkB_d8_round_write (with pkB_d8_common) | plain navigation onto the secondary, with and without `<M-f>`'s secondary note [sim] | 5 |
| pkB_secflip | `<M-f>`, `<M-f>`, `<M-;><M-t>` throws today | 5 |
| pkB_d9_nopath (first version) | Failed setup: the empty No Name buffer was reused by `:e b`. | 6a |
| pkB_d9_nopath | the no-path throw | 6a |
| pkB_d9_missing | a swap note to a missing file destroys the plain note | 6b |
| pkB_d9_closed | a closed buffer restores and reopens on use | 6c |
| pkB_d11_fill | the first `<M-f>`: warning, fill from history, then a swap | 7 |
| pkB_d11_dup | the fill picks the current buffer while history is frozen | 7 |

`pkB_q9_common.lua` was extended after its first three runs, adding the swap-note mode and the toggle. The earlier modes' code paths didn't change.
