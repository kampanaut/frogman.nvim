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
