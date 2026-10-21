# Question packets A (items 0 to 6)

How to read these:
- Times are the author's local time (UTC+8), taken from the conversation transcript.
- Code paths are relative to the repo. `<sandbox>` is the scratch test directory, and every run went through `<sandbox>/t/run.sh`.
- In slot strings, `c=` is the current slot, `s=` the secondary, `t=` the ternary and `p=[…]on/off` the primary queue and whether it's switched on. `closed=[…]` is the closed stack, oldest first. Files stand in for their hashes, and a `-` means the slot is empty.
- `STATUS:n` means `CURRENT_IMPLEMENTATION_STATUS.md:n`, and `SPEC:n` means `WINDOW_BUFFER_RELATIONSHIP_SPECIFICATION.md:n`.
- Anything marked "proposed (Kate)" is my side's proposal, not a decision.

---

## 0. The README's cokeline sentence

**Stakes.** At 19:16 you approved a sentence saying cycling "goes through cokeline". In the same round you decided cycling should still work without cokeline, which makes that claim false once it's built. That decision also contradicts two lines on the desk that the round didn't show you. Your answers decide two things: which of the two cycling decisions stands, and a README sentence that's true whichever one does.

**Recap from zero.**

1. **What it is.**
   - The README's "nvim-cokeline setup" section (README.md:107) opens with your sentence (README.md:109-111):
     > The cavediver plugin can work without the bufferline, but it would be nice to visualise the
     > visit history of all your browsers in a bufferline, so that you can now how you can end up
     > to your current buffer.
   - Cokeline is nvim-cokeline, the bufferline plugin. Cavediver hands it callbacks (README.md:113-205).
   - Cycling is `<M-n>`/`<M-m>`. Navigation goes into a `cycling` mode where history recording stops. Each press moves focus one buffer along the bufferline by calling cokeline's `by_step("focus", -1/+1)` (`lua/cavediver/domains/navigation/init.lua:52-68`, `lua/cavediver/domains/navigation/routines.lua:22-28`). `<M-v>` picks the shown buffer and goes back to normal (`navigation/init.lua:70-76`).

2. **Why it matters, and what was tested.** `<M-n>` switches the mode first (`navigation/init.lua:52-59`, then the hook at `lua/cavediver/domains/navigation/hooks.lua:12-17`). Only the step itself checks for cokeline (`navigation/routines.lua:16-20`). Run `t/pkA_nocoke.lua`, with cokeline missing:
   ```
   :e a, :e b, :e c: c=c.txt s=- t=b.txt p=[]off  nav=normal hist=attached  shown=c.txt
   <M-n>:            c=c.txt s=- t=b.txt p=[]off  nav=cycling hist=detached  shown=c.txt
     printed: cokeline is not installed. Please install 'willothy/nvim-cokeline' to use this cycle function.
   :e a while stuck: c=c.txt s=- t=b.txt p=[]off  nav=cycling hist=detached  shown=a.txt
     ordered history: c.txt,b.txt,a.txt
   <M-v>:            c=a.txt s=- t=b.txt p=[]off  nav=normal hist=attached  shown=a.txt
   ```
   So today, one `<M-n>` without cokeline leaves you in cycling with history detached until `<M-v>`. In between, `:e a` changes no slot and the history order stays frozen. Apart from that gap, "can work without the bufferline" holds.

3. **What's already decided, in order.**
   - **2026-10-20 11:13.** The question was "Bufferline: callbacks return neutral colours instead of throwing when no triquetra exists; cavediver cycles through its own ordered history itself (cokeline only displays); cokeline components stay as the built-in integration and the :tabmove patch stays a README tip?" You answered: "no, when I say it shouldn't happen, then it shouldn't happen. It's a systemic issue by then. And cokeline is always required, it's what completes the UI experience of cavediver." The desk recorded two things:
     - DESK.md:1385: "**Cokeline is part of cavediver and stays required,** because it's what completes cavediver's UI. Cycling stays on it."
     - Dropped list, DESK.md:1945: "Cavediver cycling through its own history without cokeline, cokeline being optional: cokeline is required."
     - The summary at DESK.md:17 also says "cokeline is required".
   - **19:07.** The question was "Stakes: the cokeline section says cavediver works without the bufferline, which is no longer true. Fix that sentence (and the two typos)?" You answered at 19:10: "I mean it is true in a sense that the cokeline is just representation thing. You can still use cavediver without it, but it reduces experience A LOT. Just maybe mention that instead. Fix typos along the way."
   - **19:12.** The round showed this sentence, with the typos fixed and "end up to" kept:
     > The cavediver plugin can work without the bufferline, but it reduces the experience a lot. Cycling with `<m-n>` and `<m-m>` goes through cokeline, and it's what lets you visualise the visit history of all your buffers, so that you can know how you can end up to your current buffer.

     At 19:16 you gave two answers:
     - "Yes, that sentence", to "Stakes: the README should say what actually breaks without cokeline. Use that sentence?"
     - "Cycle anyway", to "Stakes: without cokeline, one <M-n> silently stops history recording until <M-v>. What should <M-n>/<M-m> do with no cokeline?" That option's description read: "Step through cavediver's own ordered history without cokeline (the order the bufferline would show)."
   - **The spec records 19:16:**
     - what-is-cavediver.md:732 (A12, "Decided (2026-10-20): without cokeline, a step goes through cavediver's own ordered history instead")
     - what-is-cavediver.md:1402 (target test T171)
     - what-is-cavediver.md:1281, which says the sentence is open again
   - **The settled requirements list** keeps "nvim-cokeline" with no "(optional)" (what-is-cavediver.md:1280).

4. **Other things involved.**
   - In the 19:12 round, the option next to "Cycle anyway" was labelled "Change nothing", but its description was a change: "Check for cokeline before entering cycling; give the message and stay in normal mode, history attached." So both options were changes, and one was mislabelled.
   - The 19:12 round didn't show DESK.md:1385 or DESK.md:1945.
   - Your rule for the desk: when a new call contradicts something already settled, and you didn't say which wins, it gets asked rather than guessed.

5. **How they collide.**
   - The approved middle sentence ("Cycling with `<m-n>` and `<m-m>` goes through cokeline") is false without cokeline once the fallback (T171) is built. It's true in every other case.
   - "Cycle anyway" against DESK.md:1385 ("Cycling stays on it") and DESK.md:1945: the two can be read together, with cokeline driving cycling when it's installed and cavediver's own history used only when it's missing. Reading them that way is my inference, though.
     - The 11:13 question bundled "cavediver cycles through its own ordered history itself (cokeline only displays)", meaning always and not as a fallback, with two other changes.
     - Your "no" talks about the callbacks' throw and about cokeline being required. It doesn't mention cycling.
     - So whether 11:13 also rejected a fallback is unclear.

6. **The way out.** Two questions: first the clash, then the sentence.

**Text for the README.**
- **Voice samples.**
  - Your original, README.md:109-111, quoted above. Typos, flagged and not fixed silently: "browsers" (buffers) and "now" (know). "end up to" stays as you wrote it.
  - Your 19:10 words: "it reduces experience A LOT". The approved wording, "it reduces the experience a lot", came from the 19:12 round, and you approved it at 19:16, so it stays.
  - Another sample of how you describe the bufferline, README.md:372: "This is really helpful on trying to know how you ended up with your current buffer".
- **Q2(a), proposed (Kate).** It's the approved sentence with the cycling clause dropped. Only "Cycling with `<m-n>` and `<m-m>` goes through cokeline, and it's what" changes, to "Cokeline is what":
  > The cavediver plugin can work without the bufferline, but it reduces the experience a lot. Cokeline is what lets you visualise the visit history of all your buffers, so that you can know how you can end up to your current buffer.
- **Q2(b), proposed (Kate).** The same, but closer to your original's "in a bufferline":
  > The cavediver plugin can work without the bufferline, but it reduces the experience a lot. It's the bufferline that lets you visualise the visit history of all your buffers, so that you can know how you can end up to your current buffer.
- **The first clause** ("can work without the bufferline") is your own claim, from README.md:109, approved again at 19:10 and 19:16. Today it has the one gap shown in the run, and code from either Q1 answer closes it.

**The questions.**

**Q1. Without cokeline, do `<M-n>`/`<M-m>` fall back to cavediver's own history, given that the desk says cycling stays on cokeline?**
- **(a) Fall back, only when cokeline is missing.** With cokeline installed nothing changes. At the next sync, DESK.md:1385 and DESK.md:1945 get narrowed to say that, and cokeline stays in the requirements list.
- **(b) The desk stands: no fallback.** The 19:16 "Cycle anyway" is withdrawn, along with the spec's decided line and target test for cycling without cokeline (A12, T171; what-is-cavediver.md:732, :1402). What `<M-n>` does without cokeline becomes an open question again.

**Q2. Which sentence goes at README.md:109-111?**
- **(a) Proposed (Kate): "…Cokeline is what lets you visualise…"** It drops the cycling clause. It adds nothing beyond your own first clause and says nothing about how cycling works, so it holds under either Q1 answer.
- **(b) Proposed (Kate): "…It's the bufferline that lets you visualise…"** Same as (a), worded closer to your original.
- **(c) Your own wording.** It gets checked against your Q1 answer before it goes in.

**Why Q1 and Q2 can't clash.** Neither Q2 wording says how cycling works, so both hold under either Q1 answer. "Keep the approved sentence" isn't offered, because it holds only under Q1(b).

**Related, not asked.**
- README.md:382 says "`<m-n>` and `<m-m>` calls cokeline's cycle function". Under Q1(a) that's true only with cokeline installed. No change is proposed here.
- Which build step builds T171 is unverified. The accepted build order (2026-10-20 13:33) lists steps, not T171.

---

## 1. Session-file protection: XOR today, AES-GCM decided

**Stakes.** One comment, the header at `lua/cavediver/init.lua:4`, will still call the session file "XOR-obfuscated" after the encrypted format lands, unless the step that builds the format also changes it. Changed too early, it claims an encryption the file doesn't have yet. Everything else that says XOR either goes with the XOR code or lives in STATUS (packet 6).

**Recap from zero.**

1. **What it is.** The session file is cavediver's own save of slots, history and the closed stack, named after the cwd today. Here's what goes into it:
   - A slot pointing at a buffer that's open at save time is written as its raw 16-character hash.
   - Anything else, meaning closed files and No Name names, is written as the path XOR'd with the cwd and then base64-encoded. No Name text is stored line by line the same way.
   - Code: `lua/cavediver/domains/storage/routines.lua:113-128` (the choice), `:62-111` (the cipher), `:531` and `:550-551` (closed stack and No Name text). Spec: what-is-cavediver.md:1076-1080.
   - "XOR" here means each byte of the path is combined with the matching byte of the cwd, with the cwd repeated as the key (`storage/routines.lua:62-82`).

2. **Why it matters.** Every path in the project starts with the cwd, and the cwd is the key. So the stored value opens with a run of zero bytes, and one guessed filename gives the key back (DESK.md:883, repro at DESK.md:1975). The spec's run s10 shows the closed list coming out as all `A`s (what-is-cavediver.md:1079). I made no new run for this packet.

3. **What's already decided.**
   - Your words:
     - 2026-10-18 23:40: "I guess at this point, we just have to fucking encrypt them Argh!"
     - 23:43, to "What are the stored paths (and No Name content) being protected from?": "the key is the cwd... that's it. cavediver can only decrypt with what cwd it is on. And it's privacy. I just think it's important. It's usage data after all."
     - 23:46: "we use openssl"
   - Your answers on 2026-10-19:
     - 08:22, "Whole file, one call (Recommended)", to "How is the file encrypted?"
     - 08:24, "Migrate once", to "What happens to today's session files (plain JSON with XOR inside, no marker) when the new format lands?"
     - 08:44, "GCM via libcrypto", to "Which encryption?"
     - 13:50, "Both, in the script", to "Does the migration script handle both the new file name and the new format, so cavediver's load only ever reads the new format?"
   - The desk:
     - DESK.md:863: AES-GCM through OpenSSL 3's `libcrypto` over LuaJIT's FFI. The session's directory is the secret, and the reason is privacy.
     - DESK.md:865: "Cavediver's load only ever reads the new format, and the XOR code leaves cavediver (decided 2026-10-19)."
     - DESK.md:1896 drops "XOR with the cwd as the cipher".
     - The spec's decided section has it too (what-is-cavediver.md:1115).
   - The build order. Step 5 is "**The file format:** `libcrypto` encryption, the version header, atomic writes, the main file plus scratch files, and the migration script." That's from my side's breakdown at 2026-10-20 13:25. You accepted the order at 13:33: "Yes, let's build a big fucking test suite, that formalises what is cavediver is, the invariants, the rules, the philosophies, like how you use cavediver. So I guess, this is what we should talk about next: "WHAT IS CAVEDIVER.""

4. **Which texts say XOR.** I grepped every `*.lua` and `*.md` file in the repo.
   - `lua/cavediver/init.lua:4`: "---hash-based buffer tracking, and XOR-obfuscated session persistence." (the module header)
   - `CURRENT_IMPLEMENTATION_STATUS.md:307`: "✅ **XOR obfuscation** for session data (implementation detail)"
   - Docstrings in `storage/routines.lua`, plus the functions they describe:
     - `:58`: "Create a one-pass xor cipher for text encryption."
     - `:61`: "Base64-encoded XOR result"
     - `:85`: "Create a one-pass xor decipher for text decryption."
     - `:86`: "Base64-encoded XOR result"
   - Not in README.md. README.md:47 says openssl is "used for hashing file names and  directories", and the settled replacement for that line is at what-is-cavediver.md:1280. XOR also isn't in WINDOW_BUFFER_RELATIONSHIP_SPECIFICATION.md or CLAUDE.md.
   - DESK.md and what-is-cavediver.md mention XOR only to describe today's code: DESK.md:58, :694, :865, :883; what-is-cavediver.md:74, :1076-1080, :1286, :1707.

5. **How they collide.**
   - The docstrings go with the XOR code (DESK.md:865). STATUS:307 is packet 6.
   - That leaves the header comment as the one text that outlasts the change, and neither the desk nor build step 5 names it.
   - Earlier, the list of items to close (2026-10-20 18:36) put this item under "The README follows the desk", but no README line says XOR.

6. **The way out.** Decide when the header changes and what it says.

**Text for the code.**
- Today, `init.lua:3-4`:
  ```
  ---A state machine-driven buffer management system with triquetra window relationships,
  ---hash-based buffer tracking, and XOR-obfuscated session persistence.
  ```
- **Voice.** `init.lua:1-4` came in the first commit, 3b56177 (2025-07-07), and whether you wrote it is unverified. Its register ("Sophisticated buffer and window management plugin") matches STATUS, which was written for "Future LLMs" (STATUS:661). So the proposal is a one-word swap in plain wording.
- **For context only.** Your own comment on the same feature is a different text, so it isn't used as the sample. `storage/routines.lua:113`: "---This is the main seralisers of the hashes. It adds a layer of privacy kekeburichi laputa." One typo, flagged: "seralisers".

**The question: when does the header at `init.lua:4` stop saying XOR, and what does it say then?**
- **(a) Proposed (Kate): in build step 5, together with the encryption.** It becomes "---hash-based buffer tracking, and encrypted session persistence.", which is true at every point in time.
- **(b) Now, ahead of step 5.** The comment claims encryption until step 5 lands.
- **(c) In step 5, dropping the detail.** It becomes "---hash-based buffer tracking, and session persistence.", which never goes stale on a later format change but says less.

**Related, not asked.** The settled README requirements line (what-is-cavediver.md:1280) says libcrypto "is used for encrypting the session files", which is true only once step 5 lands. Whether README changes wait for the code is unverified:
- My side's 13:25 breakdown put "the README" in step 8.
- The settled note on windows that show something untracked says "The code follows in build step 3" (D26, what-is-cavediver.md:1278), which implies the README goes first.

---

## 2. Closed secondaries and primary entries get dropped instead of reopening

**Stakes.** Close the file in your secondary slot or primary queue, and at the next navigation it vanishes from the window's slots, so `<M-f>` or `<M-;><M-f>` can't bring it back. README.md:15 promises they can. If this is a code bug, the fix is just reading the right slot, and the README stays as it is.

**Recap from zero.**

1. **The terms.**
   - **Triquetra:** each window's slots. The current slot is what the window shows, the secondary is reached with `<M-f>`, and the ternary (the previous current) with `<M-S-f>`. There's also a primary queue, reached with `<M-;><M-f>` (README.md:11, `lua/cavediver/domains/window/data.lua:8-15`).
   - **Closed stack:** files closed with `:bdelete` or `<M-.>`, which `<M-S-w>` reopens. The comment at `lua/cavediver/domains/history/data.lua:14` calls it "Stack of closed buffer filehashes that can be reopened".
   - **Slot pruning:** a pass inside `cleanup_triquetras` that clears slots that look stale (`lua/cavediver/domains/window/routines.lua:333-414`). It runs on every `BufEnter`, `BufDelete`, rename event, cycle start and stop, and load (what-is-cavediver.md:931).

2. **The check, and the run.**
   - The secondary is cleared when its buffer isn't open **and the ternary** isn't on the closed stack (`window/routines.lua:344-345`).
   - Primary entries use the same wrong check (`:400-401`).
   - The ternary's own check reads its own slot (`:371-372`).
   - Run `t/pkA_d13.lua`:
   ```
   1 setup:                                        c=d.txt s=b.txt t=c.txt p=[]off       closed=[]
   1 :bdelete b (the secondary; ternary c open):   c=d.txt s=-     t=c.txt p=[]off       closed=[b.txt]
   2 setup:                                        c=a.txt s=-     t=f.txt p=[e.txt]on   closed=[b.txt]
   2 :bdelete e (the primary; ternary f open):     c=a.txt s=-     t=f.txt p=[]on        closed=[b.txt,e.txt]
   3 setup:                                        c=c.txt s=f.txt t=a.txt p=[]on        closed=[b.txt,e.txt]
   3 :bdelete a (the ternary):                     c=c.txt s=f.txt t=a.txt p=[]on        closed=[b.txt,e.txt,a.txt]
   3 :bdelete f (the secondary; ternary a closed): c=c.txt s=f.txt t=a.txt p=[]on        closed=[b.txt,e.txt,a.txt,f.txt]
   3 <M-f>:                                        c=f.txt s=c.txt t=a.txt p=[]on        closed=[b.txt,e.txt,a.txt]
   4 setup:                                        c=b.txt s=c.txt t=e.txt p=[d.txt]on   closed=[a.txt]
   4 :bdelete e (the ternary):                     c=b.txt s=c.txt t=e.txt p=[d.txt]on   closed=[a.txt,e.txt]
   4 :bdelete d (the primary; ternary e closed):   c=b.txt s=c.txt t=e.txt p=[d.txt]on   closed=[a.txt,e.txt,d.txt]
   4 <M-;><M-f>:                                   c=d.txt s=c.txt t=b.txt p=[d.txt]on   closed=[a.txt,e.txt]
   ```
   - What the run shows:
     - A closed secondary or primary entry is dropped at the next cleanup, unless the ternary happens to be closed too (parts 1 and 2).
     - When it survives, the keys reopen it and take it off the closed stack (parts 3 and 4).

3. **What's already said or decided.**
   - README.md:15: "**Buffer Lifecycle**: Closed buffers reopen when accessed through relationships"
   - The code's own comment, under each of the three checks (`window/routines.lua:346-348`, `:373-375`, `:402-404`): "-- i.e. if the buffer is not registered (typically means that buffer is closed) and / -- it is not registered as closed in the closed buffers list. something is wrong / -- with the triquetra, so we just remove it." The intent it states is to keep a slot whose file is on the closed list.
   - The reopen code already exists for all three: `window/routines.lua:507` (secondary), `:574` (ternary) and `:639` (primary).
   - The desk lists this as a plain fix, DESK.md:1654: "**The staleness checks read the wrong slot:** the secondary check reads `is_filehash_closed(triquetra.ternary_slot)` (`window/routines.lua:345`), and so does the primary check (`:401`). Reproduced." The desk names the bug but doesn't write out the fix. The implied fix is each check reading its own entry.
   - The spec has invariant I4 (what-is-cavediver.md:1033) and target tests T42 (:1352) and T56 (:1371).
   - My side's 13:25 build breakdown puts "the remaining plain fixes" in step 8, and you accepted the order at 13:33.
   - The wrong slot arrived in commit 6e641880 (2025-07-23). There, the secondary and primary checks got the same `is_filehash_closed(triquetra.ternary_slot)` line as the ternary's (`:372`).

4. **Another rule involved.** The same checks also clear a slot whose file is gone from disk (`filereadable == 0`, `window/routines.lua:342`, `:398`). The desk keeps such slots once missing files stay tracked (DESK.md:1163, build step 6). That's a separate change and doesn't affect this answer.

5. **How they collide.** README.md:15 promises reopening, and so do STATUS:37, :136, :194 and :382-392 (packet 6). For secondaries and primary entries, though, the code drops the slot before you can use it.

6. **The way out.** Proposed (Kate): treat it as a code bug.

**The question: is this a code bug, with README.md:15 staying as written?**
- **(a) Yes. Proposed (Kate).** Each check reads its own entry (DESK.md:1654) and README.md:15 stays. The spec's rule that a closed slot keeps its file until it's used stands, and so do its tests for reopening a closed secondary and a closed primary (I4, T42, T56).
- **(b) Not yet.** Show me more first.

---

## 3. A second trigger for the new-file wipe

**Stakes.** The desk's bug entry blames only the 4-second cleanup timer. The faster route is your next `:e` or window switch: a new file you haven't saved loses its text at once. If you had moved to another window, the new file's window also closes, and every later action errors. A test or fix aimed only at the timer would miss this route. The question is whether the desk entry says so.

**Recap from zero.**

1. **The terms.**
   - **New file:** `:e name` for a file that isn't on disk yet.
   - **Wipe:** `:bwipeout!` (`bw!`). It removes the buffer with its text and closes any window showing it.
   - **Why cavediver wipes:** it treats "not on disk" as "deleted on purpose" (DESK.md:1137).

2. **The runs.** Run `t/pkA_d14.lua`. It types three synthetic lines into each new file and prints only counts, never content.
   ```
   T  typed 3 lines in new3:                  valid=true  lines=3 registered=true  shown=new3.txt windows=1
     bw! called from: history/routines.lua:678
   T  after one tick, no keys:                valid=false lines=- registered=false shown=b.txt    windows=1
   E1 typed 3 lines in new1:                  valid=true  lines=3 registered=true  shown=new1.txt windows=1
     bw! called from: window/routines.lua:428
   E1 after :e a:                             valid=false lines=- registered=false shown=a.txt    windows=1
   E2 typed 3 lines in new2 (split):          valid=true  lines=3 registered=true  shown=new2.txt windows=2
     bw! called from: window/routines.lua:428
   E2 after <C-w>p to the other window:       valid=false lines=- registered=false shown=a.txt    windows=1
   E2 split window still valid: false, triquetra kept for it: true
     notifications: 5, first: Hook 'cleanup_triquetras' failed during transition attached->attached: …/window/data.lua:69: Invalid window …
   D  :e d (on disk):                         valid=true  lines=1 registered=true  shown=d.txt    windows=1
     bw! called from: window/routines.lua:428
   D  d removed on disk, then :e a:           valid=false lines=- registered=false shown=a.txt    windows=1
   ```
   - **T** is the trigger the desk names. Staying on the file, the timer wipes it within one tick.
   - **E1:** an `:e` in the same window wipes it straight away, from the current-slot check inside `cleanup_triquetras` (`window/routines.lua:417-449`, the wipe at `:428`).
   - **E2:** moving to another window does the same. The new file's split also closes, its triquetra stays behind for a dead window, and later transitions error with "Invalid window id".
   - **D:** a file deleted on disk is wiped by the same check at the next `:e`.

3. **What's already decided.**
   - The bug entry, DESK.md:1638: "**A new file not yet saved is wiped within one cleanup tick,** text and all, and the window jumps (`history/routines.lua:678`); **so is a file deleted outside nvim,** often the last copy of its content. Reproduced. Fixed by missing-file buffers staying tracked."
   - The fix already covers both triggers:
     - The timer's missing-file wipe is "gone" (DESK.md:1161).
     - Window healing's missing-file wipe (`:417` to `:449`) is "gone" (DESK.md:1166).
     - "Cleanup never touches a buffer or a window; it only repairs cavediver's own data (decided 2026-10-20)" (DESK.md:1155).
   - DESK.md:1636 already records the `:file` route through `:428`, with the same dead-window result.
   - Build step 1 is "**Stop the data loss first.** Remove the missing-file wipes…" (my side's 13:25 breakdown; you accepted the order at 13:33).
   - You, at 2026-10-20 13:33, answering "In your daily use, does a brand-new file you're typing into (`:e newfile.lua`, not saved yet) ever vanish within a few seconds?": "Yes, I just avoid it lol! I just save it right away, because it's my habit, so after that it "never happens""
   - The spec covers part of this:
     - invariant I12 (what-is-cavediver.md:1041)
     - A21 step 5 (:951-954)
     - T109, the `:e` route (:1459)
     - T131, which says no unsaved buffer is ever wiped (:1493)
     - D14 (:1250)
     - The window-switch route isn't a named test.

4. **Another rule involved.** Your desk changes only when you say so ("sync it").

5. **How they collide.** Nothing new needs deciding, because the decided fix already removes `:428`. But the bug entry (DESK.md:1638) and its repro (DESK.md:1999) name only the timer at `history/routines.lua:678`. The window-switch route and its dead window aren't written anywhere on the desk.

6. **The way out.** Add the second trigger at the next sync.

**Text for the desk**, proposed (Kate), in plain wording.
- The DESK.md:1638 entry becomes:
  > - **A new file not yet saved is wiped within one cleanup tick,** text and all, and the window jumps (`history/routines.lua:678`); **so is a file deleted outside nvim,** often the last copy of its content. **Sooner still, the next `BufEnter` anywhere wipes it,** an `:e` in its window or a move to another window, through the current-slot check in `cleanup_triquetras` (`window/routines.lua:428`). The move also closes the new file's window and leaves a triquetra for a dead window, so later transitions error with "Invalid window id". Reproduced. Fixed by missing-file buffers staying tracked and healing's missing-file wipe going.
- The repro at DESK.md:1999 gets one sentence:
  > Or skip the wait: `:e brandnew.lua`, type a line, then `:e keep.lua` or `<C-w>p` to another window; a traced `vim.cmd` shows `bw!` from `window/routines.lua:428`.

**The question: at the next sync, does the desk's new-file bug entry get the second trigger?**
- **(a) Yes, both as proposed.** The entry at DESK.md:1638 and the repro at DESK.md:1999 both change.
- **(b) Yes, the entry only.** The repro stays as it is.
- **(c) No.** DESK.md:1166 already covers the fix, and the entry stays as it is.

---

## 4. `<M-,>` across tabs (the window-jump history)

**Stakes.** Right after you switch tabs, `<M-,>` takes you back to the window you left in the other tab, where Vim's own `<C-w>p` would stay in the tab. The comment says the history is per tab. Depending on your answer, either the comment changes, or `<M-,>` changes to stay inside the tab.

**Recap from zero.**

1. **What it is.**
   - `<M-,>` (`toggle_window`) goes to the window you came from (`lua/cavediver/domains/navigation/routines.lua:44-59`, `lua/cavediver/configs.lua:118`, README.md:311).
   - On every `WinEnter`, cavediver records "came to W from V" in the window-jump history (`navigation/hooks.lua:30-42`, `navigation/routines.lua:38-42`).
   - V is Vim's previous window (`winnr('#')`). When Vim has none, V is `last_valid_window`, the last window that had a triquetra (`navigation/hooks.lua:32-37`, what-is-cavediver.md:283).

2. **The run.** Run `t/pkA_d17.lua`, with tab 1 holding w1 and w2 and tab 2 holding w3 and w4. It's observed headless, and the output is trimmed to the relevant lines.
   ```
   tab1 :vsplit, :e b:      now in w2(tab1)
     seen: WinEnter w3(tab2): winnr('#')=0
   tabnew, :e c:            now in w3(tab2)
   after tabnew:            jump table: w2(tab1)<-w1(tab1) w3(tab2)<-w2(tab1)
   <M-,> in the new tab's first window: now in w2(tab1)
   tab2 :vsplit, :e d:      now in w4(tab2)
     seen: WinEnter w2(tab1): winnr('#')=0
   gt to tab1:              now in w2(tab1)
   after switching to tab1: jump table: w2(tab1)<-w4(tab2) w3(tab2)<-w2(tab1) w4(tab2)<-w3(tab2)
     Vim's own <C-w>p would go to: w1(tab1)
   <M-,> in tab1:           now in w4(tab2)
   <M-,> in tab2:           now in w2(tab1)
   <M-,> again:             now in w4(tab2)
   tabclose tab2:           now in w2(tab1)
   after tabclose:          jump table: w2(tab1)<-w1(tab1) w3(closed)<-w2(tab1) w4(closed)<-w2(tab1)
   ```
   - Inside a tab, `<M-,>` behaves like `<C-w>p`. This run didn't toggle within a tab; the spec's run s07 shows it toggling between two splits (what-is-cavediver.md:842).
   - Entering a tab (`:tabnew`, `gt`) is different. `winnr('#')` reads 0 at `WinEnter`, so the fallback records `last_valid_window` (`navigation/hooks.lua:34-37`). The recorded entries `w3<-w2` and `w2<-w4` show that this is the window you just left in the other tab. My `WinEnter` logger ran after cavediver's hook, so the value it printed for `last_valid_window` was already updated, and I left it out. After that, `<M-,>` toggles across the two tabs.
   - Entries for closed windows stay in the table. `<M-,>` skips them because it checks validity first (`navigation/routines.lua:49-52`).

3. **What's already said or decided.**
   - The comment, `lua/cavediver/domains/navigation/data.lua:9`: "---@field window_jump_history table<WinId, WinId> Per-tab, current window -> previous window mapping"
   - STATUS:111 says "tab-aware previous window tracking", and STATUS:115 gives `data.window_jump_history[tabnr][to_win] = from_win`.
   - The code keeps one flat table (`navigation/data.lua:41`, `navigation/routines.lua:40`).
   - Its history:
     - It was per tab in the first commit, 3b56177 (2025-07-07).
     - Your commit 60540e7 (2025-07-20 21:57) flattened it. Its message: "- the window_history_jump record is now flattened, no longer divided by tabnr."
     - That commit also changed the type at `navigation/data.lua:9` but kept "Per-tab,", and it removed the `TabClosed`/`WinClosed` autocmd that cleared a tab's entries. That removal is why closed windows' entries now stay.
     - STATUS's file date (2025-07-08) is earlier than the flattening.
   - Why you flattened it is unverified. The commit doesn't say.
   - The desk says nothing about `<M-,>` across tabs. Related lines:
     - "A tab is a layout, Vim's model" (DESK.md:300). You, at 2026-10-19 19:13, answering "For cavediver, is a tab a layout (Vim's model) or a buffer group (scope.nvim's model)?": "Layout, Vim's model (Recommended)". This is context and doesn't decide `<M-,>`.
     - A tab-scoped load tears down the current tab only (DESK.md:299), and every domain gets a teardown (DESK.md:612). Nothing says how the jump table is torn down for one tab.
     - `<M-,>`'s minimap skip becomes a configurable list (DESK.md:1413). You answered at 2026-10-20 11:30: "Yes, configurable (Recommended)".
   - In the spec: M10 (what-is-cavediver.md:277-283), A17 (:835-844), D17 (:1257).

4. **Another rule involved.** The same table feeds the UI's fallback when the focused window has no triquetra (`navigation/routines.lua:61-102`).

5. **How they collide.** The comment and STATUS say per tab, while your own commit flattened the table on purpose. The visible effect is that `<M-,>` crosses tabs after a tab switch, and nobody has said whether that's intended.

6. **The way out.** Ask about the behaviour, not the data structure, since the structure is your code to shape.

**Text for the code, under (a).** Proposed (Kate), plain wording: `navigation/data.lua:9` becomes "---@field window_jump_history table<WinId, WinId> Current window -> previous window mapping, one table across all tabs". There's no sample of your own for this comment, so it's plain wording.

**The question: after `gt`, should `<M-,>` take you back to the window you left in the other tab?**
- **(a) Yes, as today.** Only the comment at `navigation/data.lua:9` changes, dropping "Per-tab".
- **(b) No, stay inside the tab like `<C-w>p`.** That's a code change, and how is yours to decide. The UI fallback reads the same table, so the change also decides whether that fallback still crosses tabs.
- **(c) Show me more first.**

---

## 5. File-picker mode is registered and never entered

**Stakes.** Nothing ever enters this navigation mode, yet it sits in the state machine and in an `is_file_picker()` function. Three docs describe it: one says it works, one says it's unused by design, one says it's complete. Your answer decides whether it goes, the way the window machine did, stays as scaffolding, or becomes a feature.

**Recap from zero.**

1. **What it is.**
   - The navigation machine has three states, `normal`, `cycling` and `file_picker` (`lua/cavediver/domains/navigation/states.lua:9-17`, `navigation/sm.lua:22-24`).
   - `file_picker`'s comment reads "File picker mode where explorer controls navigation" (`navigation/states.lua:8`).
   - `is_file_picker()` is at `navigation/init.lua:38-43`.
   - A grep for `file_picker`, `FILE_PICKER` and `is_file_picker` across `lua/` finds only those definitions, plus the annotation at `navigation/init.lua:26`. Nothing calls `to("file_picker")`, and nothing calls `is_file_picker()`.
   - It's unchanged since the first commit, 3b56177.
   - There's no run, because there's nothing to enter.

2. **What the docs say.**
   - SPEC, WINDOW_BUFFER_RELATIONSHIP_SPECIFICATION.md:906-909: "File Picker Mode … Displacement mappings paused / Explorer-driven buffer selection / Automatic return to normal mode after selection".
   - STATUS:103: "File picker mode (scaffolding ready, unused by design)". Its rationale is at STATUS:612-625: "Exclusion is often better than integration."
   - The untracked CLAUDE.md lists it as complete (CLAUDE.md:24, :249, :259).
   - Today, opening a file from oil or telescope is a plain `BufEnter`, which is ordinary navigation (A1, what-is-cavediver.md:460). That's inferred; I ran no explorer.

3. **What's decided nearby.**
   - **The pop-up's `<M-e>` picker** is a different thing (what-is-cavediver.md:885-889; Q11, :1579-1583).
     - Your words, 2026-10-20 15:45: "And I wanna use fzf as a means of adding new files to the pop-up, like save the selection/s in the cursor's line (if empty) or after the cursor's line (if not empty)."
     - 15:46: "why not telescope????" and "I use <M-e>"
     - 15:47: "Yes, telescope default (Recommended)"
     - It inserts paths into the pop-up's buffer, and no window changes buffer, so there's no navigation for a mode to pause. The two share a name only.
   - **Explorers on the desk** are handled by the visiting rule: a window with a triquetra keeps it while it shows something untracked (oil, help, a terminal), and its current slot stays on the file (DESK.md:46, :1095). Buffers are tracked by property, not by plugin name (DESK.md:17, :1405).
   - **A precedent**, which doesn't decide this one: the window domain's machine had four states that nothing drove.
     - At 18:57 you said: "did we use the window SM? I think that's an artifact. Think of it like my inchoate modelling of the whole problem when i was first writing it."
     - At 19:00 you answered "Yes, all three" to removing it (what-is-cavediver.md:1271-1272).

4. **Another rule involved.** None beyond the above.

5. **How they collide.** SPEC describes a working mode, STATUS calls it unused by design, and CLAUDE.md calls it complete. The code registers it and never enters it.

6. **The way out.**

**The question: what happens to the `file_picker` mode?**
- **(a) Remove it. Proposed (Kate).** The state, its constant and `is_file_picker()` go. SPEC:906-909 becomes out of date, and explorers stay covered by the visiting rule.
- **(b) Keep it as unused scaffolding.** A comment says nothing enters it, and SPEC:906-909 is marked as not built.
- **(c) Build it.** Picking from an explorer would stop writing displacement notes, the entries that `<M-;><M-r>` and `<M-;><M-t>` restore from, and would return to normal after the pick. That's a new feature needing a design: which explorers, and how they're detected, given that tracking is by property.

---

## 6. What happens to CURRENT_IMPLEMENTATION_STATUS.md

**Stakes.** The file isn't in git, so deleting it can't be undone, and 21 lines of the spec cite it. Kept as it is, it tells people, and coding agents (it addresses "Future LLMs"), that things work when they don't.

**Recap from zero.**

1. **What it is.**
   - A status report at the repo root, headed "Last Updated: 2025-01-08" and "Production Ready (99% Complete)" (STATUS:1-5).
   - The file's date is 2025-07-08 17:57, and the repo's first commit is 2025-07-07 (3b56177). So the header's date is probably a slip for 2025-07-08 (unverified).
   - It was never tracked:
     - `git log --all -- CURRENT_IMPLEMENTATION_STATUS.md` returns nothing.
     - `git status` shows it as `??`.
     - `git check-ignore` doesn't ignore it.
   - It was written for an LLM (STATUS:661: "Future LLMs: This system is COMPLETE and WORKING…"), so there's no voice of yours in it to match.

2. **What's wrong in it.**

   **Wrong today:**
   - **Storage states.** STATUS:301 leaves out `bare` (`lua/cavediver/domains/storage/states.lua:20`).
   - **The saved window entry.** STATUS:311-321 gives it as `[secondary, primary, ternary]`. The code writes `[current, secondary, primary_queue[], ternary, dtm, dsm]` (`storage/routines.lua:490-497`).
   - **The cleanup report.** STATUS:143-158 shows counts by category. The code notifies a total and lists the paths (`lua/cavediver/domains/history/init.lua:43-72`).
   - **"No missing functions."** STATUS:631-632 claims "ALL FUNCTIONS THAT ARE CALLED EXIST AND WORK", and the same claim appears at :553, :653 and :661. Counterexamples:
     - `get_smart_basename` is nil (`lua/cavediver/init.lua:455`; the spec's run s16).
     - `ui_machines.winbar` doesn't exist (`lua/cavediver/domains/ui/init.lua:99`, `:106`, `:138`).
     - The bufferline and indicator transitions aren't registered (`ui/init.lua:84-121`).
   - **The config example.** STATUS:477-498 shows `auto_save`, `save_interval`, `ui.winbar_enabled`, `cleanup_interval = 300 -- 5 minutes` and `session_dir … "/cavediver_sessions"`. `configs.lua` has none of the first three, and it has `cleanup_interval = 4000` (`lua/cavediver/configs.lua:132`) and `session_dir = … "/cavediver/sessions/"` (`configs.lua:21`).
   - **What a swap writes.** STATUS:419-428 has the swap writing `dsm`/`dtm[old]`. Your answer on swap notes settled that this is out of date (Q2, what-is-cavediver.md:1222).
   - **Reopening.** STATUS:37, :136, :194 and :382-392 say closed buffers are reopened transparently. Closed secondaries and primary entries are pruned first (packet 2).
   - **The jump history.** STATUS:111 and :115 say it's per tab. It has been flat since 60540e7 (packet 4).
   - **The primary.** STATUS:238 gives `primary_buffer = ""`, a single value. The code has a queue, `Filehash[]|nil` (`window/data.lua:12`), and the code's shape was settled (what-is-cavediver.md:1235).
   - **UI machines.** STATUS:256 lists a `winbar` machine, which doesn't exist (above).
   - **A keymap description.** STATUS:462 has `toggle_primary() -- Toggle current buffer as primary`. The settled description is "Switch the primary on or off" (what-is-cavediver.md:1191).
   - **`get_buffer_history()`.** STATUS:471 calls it "ordered". It returns the history view, `history.data.crux` (what-is-cavediver.md:999).
   - **Gone TODOs.** STATUS:572 and :635-647 point at TODOs at `init.lua:149` and `ui/sm.lua:30`. Neither file has a TODO now, and `init.lua:147` calls `history.init_cleanup_timer()`.
   - **Partly out of date.** STATUS:325 and :571 list "[No Name] buffer content restoration after session load" as a TODO. The load does restore closed No Name text into the cache (`storage/routines.lua:586-596`), and a TODO to open those buffers remains at `:574`.
   - **The header date** (STATUS:3; see point 1).

   **True today, wrong once the desk is built:**
   - STATUS:307, XOR (packet 1; DESK.md:863).
   - STATUS:305, the per-cwd key. DESK.md:868 names the file by directory plus session name.
   - STATUS:135 and :264, harpoon as a built-in integration. The desk makes it an optional provider (DESK.md:1403).
   - STATUS:141 and :394-407, exclusion by a `://` name. The desk tracks buffers by property (DESK.md:17, :1405).
   - STATUS:202-229, the wipe on file deletion presented as an achievement. The desk removes it (DESK.md:1165-1166).
   - STATUS:103, `file_picker` "unused by design" (packet 5).

   **Contested, so left out of the list:** STATUS:59-60 and :431-432 say cycling writes no displacement mappings. Whether the slot keys on the cycle's start write displacement entries is still open in the spec (P18 against Q7, what-is-cavediver.md:1711).

3. **What's still only in it.**
   - Performance claims (STATUS:528-546, for example "~32 bytes per tracked buffer" and "microsecond-level"). They're unverified and appear nowhere else.
   - The "exclusion is often better than integration" rationale (STATUS:612-625). It's the only written reason for the never-entered file-picker mode (packet 5).
   - A snapshot of the design on 2025-07-08, for example the per-tab jump history before 60540e7.
   - Covered elsewhere: the debug commands (what-is-cavediver.md:986-995), the bufferline and winbar markers (:374-394), and the registries (M2, :90).

4. **Other things involved.**
   - The spec now holds what STATUS was for, a line-cited account of what the code does today.
   - The untracked CLAUDE.md has its own "Current Implementation Status" sections (CLAUDE.md:138, :247), which overlap. That's related, not asked.

5. **How they collide.** Whichever way STATUS goes, the spec changes:
   - It cites STATUS in its source list (what-is-cavediver.md:15), in P21's sources (:73), at :999, and in D7 (:1219, :1222), D11 (:1230), D21 (:1245), D13 (:1249), D22 (:1253), D17 (:1257), D18 (:1259-1260), D23 (:1262), D24 (:1266), D29 (:1286) and the open list (:1702-1707).
   - Four disagreements come from STATUS, but they don't all go with it:
     - **They close with it:** the cleanup report (D22) and the config example (D24).
     - **Storage documentation (D18) only partly closes.** The code annotation at `storage/routines.lua:12-16` types the primary field `[3]` as `string|vim.NIL` when it's an array, and the untracked CLAUDE.md has the same old three-field shape (what-is-cavediver.md:1260-1261). Both stay.
     - **"No missing functions" (D23):** the disagreement goes, but the gaps stay bugs. `get_smart_basename` is nil (what-is-cavediver.md:450, target test T120 at :1473), and the missing winbar machine and unregistered transitions are on the desk (DESK.md:1665).

6. **The way out.**

**The question: fix STATUS, archive it, or delete it?**
- **(a) Archive it. Proposed (Kate).** It moves unchanged out of the repo root, somewhere you pick, still outside git.
  - The spec stops citing it as a source, and the cleanup-report and config-example disagreements close.
  - The storage-annotation and CLAUDE.md parts stay open, and so do the missing functions, as bugs.
  - Nothing is lost.
- **(b) Delete it.** The spec changes the same way as in (a), and the file is gone for good, since git never had it.
- **(c) Fix it in place.** About 17 places get corrected (the list above), and from then on it has to be kept in step with every build step, alongside the spec.
