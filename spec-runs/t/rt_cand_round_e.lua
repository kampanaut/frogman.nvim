-- Candidates: the plain :e round trip (D8 writes <M-f>'s notes on plain navigation onto the secondary).
dofile(os.getenv("CDV_SPEC") .. "/t/rt_fmt.lua")
ROW(":e a", E"a") ROW(":e b", E"b") ROW(":e c", E"c")
ROW("<M-f>  (b graduates)", F)
ROW(":e d", E"d")
ROW(":e b  (plain, onto the secondary)", E"b")
ROW(":e d  (plain, onto the secondary)", E"d")
ROW("<M-;><M-t>  (on d)", RS)
ROWS_DONE()
