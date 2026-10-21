-- Item 2, today: <M-f> out, plain :e back onto the secondary (no note written today), then the restore.
dofile(os.getenv("CDV_SPEC") .. "/t/rt_fmt.lua")
ROW(":e a", E"a") ROW(":e b", E"b") ROW(":e c", E"c")
ROW("<M-f>  (b graduates)", F)
ROW("<M-f>  (to b)", F)
ROW(":e c  (plain, onto the secondary)", E"c")
ROW("<M-;><M-t>  (on c)", RS)
ROWS_DONE()
