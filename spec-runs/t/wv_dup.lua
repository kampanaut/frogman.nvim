-- WV: t/b7_dup.lua (PART dup of t/b7_rows.lua) under the view in $CDV_VIEW.
local v = os.getenv("CDV_VIEW"); if v and v ~= "" then require("cavediver.configs").bufferline.history_view = v end
PART = "dup"
dofile(os.getenv("CDV_SPEC") .. "/t/b7_rows.lua")
