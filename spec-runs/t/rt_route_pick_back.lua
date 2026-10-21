-- Item 2, today: <M-f> out, a cycling pick of the secondary back, then the restore.
dofile(os.getenv("CDV_SPEC") .. "/t/rt_fmt.lua")
ROW(":e a", E"a") ROW(":e b", E"b") ROW(":e c", E"c")
ROW("<M-f>  (b graduates)", F)
ROW("<M-f>  (to b)", F)
ROW("<M-m>  (cycle one step)", function() CDV.cycle_right() end)
ROW("<M-v>  (pick c, the secondary)", function() CDV.cycle_select() end)
ROW("<M-;><M-t>  (on c)", RS)
ROWS_DONE()
