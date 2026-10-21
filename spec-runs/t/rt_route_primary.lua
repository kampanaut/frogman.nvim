-- Item 2, today: <M-;><M-f> with no primary falls back to <M-f>; used as the toggle.
dofile(os.getenv("CDV_SPEC") .. "/t/rt_fmt.lua")
ROW(":e a", E"a") ROW(":e b", E"b") ROW(":e c", E"c")
ROW("<M-;><M-f>  (no primary: b graduates)", J)
ROW("<M-;><M-f>  (to b)", J)
ROW("<M-;><M-f>  (back to c)", J)
ROW("<M-;><M-t>  (on c)", RS)
ROWS_DONE()
