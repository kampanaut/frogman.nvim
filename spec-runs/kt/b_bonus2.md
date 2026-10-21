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
