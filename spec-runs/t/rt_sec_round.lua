-- Item 1/2: the secondary round trip with <M-f> (pkB_secflip as rows), and the older note it overwrites.
dofile(os.getenv("CDV_SPEC") .. "/t/rt_fmt.lua")
ROW(":e a", E"a") ROW(":e b", E"b") ROW(":e c", E"c")
ROW("<M-f>  (b graduates)", F)
if PART == "older" then
	ROW("<M-f>  (to b; b's note is a)", F)
	ROW("<M-f>  (to c)", F)
	ROW("<M-f>  (back to b)", F)
	ROW("<M-;><M-t>  (on b)", RS)
	ROW("<M-;><M-t>  (again)", RS)
else
	ROW("<M-f>  (to b)", F)
	ROW("<M-f>  (back to c)", F)
	ROW("<M-;><M-t>  (on c)", RS)
end
ROWS_DONE()
