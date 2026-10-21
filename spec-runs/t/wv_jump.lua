-- WV: t/b7_jump.lua under the view in $CDV_VIEW.
local v = os.getenv("CDV_VIEW"); if v and v ~= "" then require("cavediver.configs").bufferline.history_view = v end
dofile(os.getenv("CDV_SPEC") .. "/t/b7_jump.lua")
