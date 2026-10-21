-- Item 1: the ternary-side round trip, <M-S-f> twice then <M-;><M-r>; PART older: c holds an older plain note first.
dofile(os.getenv("CDV_SPEC") .. "/t/rt_fmt.lua")
ROW(":e a", E"a") ROW(":e b", E"b") ROW(":e c", E"c")
if PART == "older" then
	ROW(":e d  (c's plain note: b)", E"d")
	ROW(":e c  (onto the ternary: no note)", E"c")
end
ROW("<M-S-f>", G)
ROW("<M-S-f>  (back)", G)
ROW("<M-;><M-r>", RT)
ROW("<M-;><M-r>  (again)", RT)
ROWS_DONE()
