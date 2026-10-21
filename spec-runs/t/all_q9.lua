-- ALL: T172's route on a variant that writes the Q9 pick note itself (no simulated write). $ALL_TOGGLE=1 adds the <M-S-f> round trip.
MODE = "today"
TOGGLE = os.getenv("ALL_TOGGLE") == "1"
dofile(os.getenv("CDV_SPEC") .. "/t/pkB_q9_common.lua")
