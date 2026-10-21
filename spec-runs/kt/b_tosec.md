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
