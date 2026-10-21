-- Item 2: Q3's graduation copy names the buffer that later becomes the partner.
dofile(os.getenv("CDV_SPEC") .. "/t/rt_fmt.lua")
ROW(":e a", E"a") ROW(":e d", E"d") ROW(":e c", E"c")
ROW("<M-f>  (d graduates: dsm d>a)", F)
ROW(":e a", E"a")
ROW("<M-f>  (to d: its partner is a)", F)
ROW("<M-;><M-t>  (on d)", RS)
ROWS_DONE()
