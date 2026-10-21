-- Candidates: graduation and Q3, the graduated buffer's predecessor a back as the secondary, then as the ternary.
dofile(os.getenv("CDV_SPEC") .. "/t/rt_fmt.lua")
ROW(":e a", E"a") ROW(":e b", E"b") ROW(":e c", E"c")
ROW("<M-f>  (b graduates: dsm b>a)", F)
ROW("<M-f>  (to b)", F)
if PART == "ternary" then
	ROW("<M-;><M-r>  (on b: a as the ternary)", RT)
	ROW("<M-;><M-r>  (again)", RT)
else
	ROW("<M-;><M-t>  (on b: a as the secondary)", RS)
	ROW("<M-;><M-t>  (again)", RS)
end
ROWS_DONE()
