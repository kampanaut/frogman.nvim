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
