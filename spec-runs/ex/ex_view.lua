-- WV: set the history view from $CDV_VIEW right after setup(), the way t/b7w_dup.lua does.
local v = os.getenv("CDV_VIEW")
if v and v ~= "" then require("cavediver.configs").bufferline.history_view = v end
