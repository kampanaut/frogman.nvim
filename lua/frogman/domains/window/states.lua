---Window state constants for per-window buffer relationship tracking.
---
---The window domain manages buffer relationships within individual windows.
---Each window maintains its own triquetra (three-way) buffer relationships
---independent of other windows and global history.
---
---@class WindowStates

local window_states = {}

---@class WindowModule
---@field state WindowStates The window state constants
return window_states
