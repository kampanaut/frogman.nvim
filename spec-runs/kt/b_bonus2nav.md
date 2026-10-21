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
