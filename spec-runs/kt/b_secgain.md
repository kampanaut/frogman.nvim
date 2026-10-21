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
