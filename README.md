# Cavediver

## Introduction

This is a **navigation context manager system**. Let me explain what that is: have you ever felt lost after unconsciously jumping to files trying to get around the codebase just because you forgot to be conscious about it? Like some jumps earlier you should have remembered your current filename, but you were too busy thinking about the problem at hand not the filename itself. And also sometimes you don't want to mess up your current jumping setup, like, at some point you have decided to just swap between files A and B, with A being your current file, and now you have to go to C. In traditional neovim, B would have been forgotten, and now you can only jump between A and C. It's fine if you remember the full filename of B, what if you forgot? And now it gets annoying to try remember it and then it just interrupts your flow, trying to go back to only swap between A and B. 

This is the kind of problem this plugin solves for you. We introduce mainly **Triquetra buffer system**. This is the novel part of the project. In a way because of how the triquetra buffers are presented in the UI, this gives you at least a semblance of your current jumping setup. And I have designed this in a way, that you can always restore the secondary buffer and the ternary buffer so you can always get back to what once was. There are other neat features as well, just read the **How to Use** section below.

### Functions

- **Triquetra Buffer System**: Each window maintains current/secondary/ternary buffer relationships with a primary buffer
- **Session Persistence**: Buffer relationships survive restarts through hash-based file identification  
- **Cycling Mode**: Explore buffers without losing your working context
- **Context Preservation**: Remembers where buffers came from for restoration
- **Buffer Lifecycle**: Closed buffers reopen when accessed through relationships
- **Visual Feedback**: Color-coded bufferline and winbar show buffer relationships
- **Per-Window Tracking**: Independent buffer relationships for each window

## New Feature

1. **Multi-version primary buffer**
    You can backtrack now your previous primary buffer. Every time you set a new buffer as a primary, it is put in the first of a queue (primary_buffers). The first one is always the primary, the others are the "previous".
    - You can now then manage it with a window pop-up, it is editable like that in harpoon window. 
        - Delete-yank and then paste it in another place to reorder... 
        - Or just delete, to really remove it.
        - Type up a filereadable filepath and just save.
            - The system validates if it is readable. If it is readable, it registers it.
            - If not, then vim.notify() an error for that line, the other lines still get saved.
        - If you press enter while under a line (in normal mode), that line will be put on top which will be promoted as the current primary buffer.
    - The default keybind `<m-;><m-f>` will now just always select the first element `primary_buffers[1]`
    - If you disable primary buffer, you can still use the pop-up window to set a primary buffer from the queue, but `<m-;><m-f>` will just act like `<m-f>`, until you set it to active again..
    - You can open the popup floating window with `<m-;>F`


## Demo
This is a short demo. It just covers how the triquetra buffers update for all sorts of jumps. The system automatically handles all cases, to make jumps and backtracking consistent. This buffers update only updates at BufEnter and non-cycling mode.

You can also see that the two windows have their own history. You can turn this off. 

![Image](https://github.com/user-attachments/assets/deb30ab4-d049-437d-bbd5-8dfe5c21bd47)

## Requirements

- neovim 0.12+
- nvim-cokeline
- openssl 3 or 4 (system installed, its libcrypto is used for encrypting the session files. Hashing is done with neovim's built-in `vim.fn.sha256`. When cavediver can't find it, set `libcrypto_path` to its file. Windows is untested: there, set `libcrypto_path` to the DLL, such as `libcrypto-3-x64.dll`)
- harpoon (optional, harpooned buffers are marked in the bufferline)
- telescope.nvim (optional, used for adding files in the primary buffer pop-up)
- a session manager (optional, resession.nvim is used in the examples below)

## Installation

This works for all plugin managers.

### lazy.nvim (An example)

```lua
{
    "kampanaut/cavediver",
    -- dir = "~/Projects/nvim/cavediver",
    config = true,
        dependencies = {
            "willothy/nvim-cokeline",
        }
}
```

### Session manager setup

You have to add hooks for the session manager, to allow this plugin to have persistence.
This cavediver plugin saves the session state in your neovim's `data` directory by default.
It doesn't care which session manager you use, it just needs these to happen:
- `save_session(name)` is called before the editor is torn down
- `load_session(name)` is called after the session manager restored your buffers and windows
- the session you are leaving gets saved before you switch to another one
- for tab sessions, the tab's session gets saved before its tab closes

#### resession.nvim

```lua
{
    "stevearc/resession.nvim",
    lazy = false,
    config = function()
        local resession = require("resession")
        resession.setup( {
            buf_filter = function(bufnr)
                local buftype = vim.bo[bufnr].buftype
                if vim.bo[bufnr].filetype == "image_nvim" or vim.bo[bufnr].filetype == "oil" then -- if you incorporated oil.nvim for example.
                    return true
                elseif buftype ~= "" then
                    return false
                elseif vim.api.nvim_get_option_value("buflisted", { buf = bufnr }) == false then
                    return false
                else
                    return resession.default_buf_filter(bufnr)
                end
            end,
            -- your configurations....
        })
        resession.add_hook("pre_save", function(name, opts, target_tabpage)
            require('cavediver').save_session(name, { tab = target_tabpage })
        end)

        resession.add_hook("post_load", function(name, opts)
            -- a tab session (a load that kept the other tabs) fills only its tab
            require('cavediver').load_session(name, { tab = not opts.reset and vim.api.nvim_get_current_tabpage() or nil })
        end)

        resession.add_hook("pre_load", function()
            resession.save_all({ notify = false })
        end)

        vim.api.nvim_create_autocmd("TabClosedPre", {
            callback = function()
                local info = resession.get_current_session_info()
                if info and info.tab_scoped and not resession.is_loading() then
                    resession.save_tab(info.name, { dir = info.dir, notify = false })
                end
            end,
        })
    end,
    dependencies = {
        "kampanaut/cavediver"
    }
},
```

#### Native sessions (`:mksession`)

`save_session(vim.v.this_session)` on `SessionWritePost`, `load_session(vim.v.this_session)` on `SessionLoadPost`,
and `:mksession!` before you `:source` another one.

#### No session manager

Call `save_session()` yourself, like on `VimLeavePre`, and `load_session()` when you want it back.

### nvim-cokeline setup

The cavediver plugin can work without the bufferline, but it reduces the experience a lot. 
Cokeline is what lets you visualise the visit history of all your buffers, so that you can know how you can end up 
to your current buffer.

```lua 
{
    "willothy/nvim-cokeline",
    config = function()
        -- update_bufferline_state()

        require('cokeline').setup({
            show_if_buffers_are_at_least = 2,
            fill_hl = 'Normal',
            buffers = {
                -- A function to filter out unwanted buffers. Takes a buffer table as a
                -- parameter (see the following section for more infos) and has to return
                -- either `true` or `false`.
                -- default: `false`.
                ---@type false | fun(buf: Buffer):boolean
                filter_valid = function(buffer)
                    return require('cavediver').bufferline.bufnr_is_displayed(buffer.number)
                end,

                -- A looser version of `filter_valid`, use this function if you still
                -- want the `cokeline-{switch,focus}-{prev,next}` mappings to work for
                -- these buffers without displaying them in your bufferline.
                -- default: `false`.
                ---@type false | fun(buf: Buffer):boolean
                filter_visible = false,

                -- Which buffer to focus when a buffer is deleted, `prev` focuses the
                -- buffer to the left of the deleted one while `next` focuses the one the
                -- right.
                -- default: 'next'.
                focus_on_delete = 'prev',

                -- If set to `last` new buffers are added to the end of the bufferline,
                -- if `next` they are added next to the current buffer.
                -- if set to `directory` buffers are sorted by their full path.
                -- if set to `number` buffers are sorted by bufnr, as in default Neovim
                -- default: 'last'.
                ---@type 'last' | 'next' | 'directory' | 'number' | fun(a: Buffer, b: Buffer):boolean
                new_buffers_position = function(buffer_a, buffer_b)
                    local compare = require('cavediver').bufferline.compare_buffers(buffer_a.number, buffer_b.number)
                    return compare
                end,

                -- If true, right clicking a buffer will close it
                -- The close button will still work normally
                -- Default: true
                ---@type boolean
                delete_on_right_click = true,
            },
            mappings = {
                disable_mouse = false,
                cycle_prev_next = true
            },
            pick = {
                use_filename = false,
                letters = "jfkdlsa;bvncmurieowpqyt"
            },
            default_hl = {
                bg = function(buffer)
                    return require('cavediver').bufferline.get_theme_bg_color(buffer.is_focused)
                end,
                fg = function(buffer)
                    return require('cavediver').bufferline.get_theme_fg_color(buffer.number, buffer.is_focused)
                end,
                bold = function(buffer)
                    return require('cavediver').bufferline.get_buffer_bold(buffer.number)
                end,
            },
            history = {
                enabled = false,
            },
            tabs = {
                placement = "right",
                components = require('cavediver').bufferline.cokeline.create_tab_components()
                
            },
            components = require('cavediver').bufferline.cokeline.create_buffer_components()
        })

        -- :tabmove fires no autocmd and cokeline only refetches tabs when the count
        -- changes, so refetch on render whenever the cached order drifts from the real one
        local cokeline_tabs = require('cokeline.tabs')
        local get_tabs = cokeline_tabs.get_tabs
        cokeline_tabs.get_tabs = function()
            local cached = get_tabs()
            for i, tabnr in ipairs(vim.api.nvim_list_tabpages()) do
                if cached[i] == nil or cached[i].number ~= tabnr then
                    cokeline_tabs.fetch_tabs()
                    return require('cokeline.state').tab_cache
                end
            end
            return cached
        end
    end
    dependencies = {
        "nvim-lua/plenary.nvim", -- Required for v0.4.0+
        "nvim-tree/nvim-web-devicons", -- If you want devicons
        "stevearc/resession.nvim", -- Optional, for persistent history
        "kampanaut/cavediver"
    },
}
```

## Configuration Defaults

You can make your own theme as well, make your own color markers for each buffer type.

You can start by just modifying the base colors

```lua
local defaults = {
    session_dir = vim.fn.stdpath("data") .. "/cavediver/sessions/",
    -- libcrypto_path: OpenSSL's libcrypto, a full path or a name the system finds, tried before
    -- cavediver's own list (nil tries the list alone); read once, the first time it's needed
    bufferline = {
        history_view = "global" -- "global" | "window"
    },
    primary_buffer_history_popup = {
        height = 0.2, -- can be a ratio or a whole number
        width = 0.7, -- can be a ratio or a whole number
    },
    closed_lists_popup = {
        height = 0.5, -- can be a ratio or a whole number
        width = 0.7, -- can be a ratio or a whole number
    },
    trail_popup = {
        height = 0.8, -- can be a ratio or a whole number
        width = 0.8, -- can be a ratio or a whole number
    },
    -- the trail's header: its tally of the day's moves, its gauge of the days, its fill shaded by depth
    trail = {
        header = { tally = true, gauge = true, shade = true },
    },
    glyphs = {
        set = "unicode", -- "unicode" | "ascii"; a glyph named here, outside the sets, replaces the set's
        unicode = {
            list = "≡", closed = "↓", tag = "⎇", more = "…",
            -- the trail's: its title, fills by depth (and unshaded), gauge, marks, branches, folds, arrows, and a
            -- search's mark and life line
            title = "⦉ trail ⦊", shade0 = "≋", shade1 = "░", shade2 = "▒", shade3 = "▓", rule = "─",
            bars = "▁▂▃▄▅▆▇█", now_left = "❬", now_right = "❭", dot = " · ", older = "<<<", newer = ">>>",
            branch = "├ ", last = "└ ", stem = "│ ", folded = "▸", unfolded = "▾", arrow = " → ", ring = "┊",
            row_t = { "⦉", "⦊" }, row_c = { "[", "]" }, row_s = { "⟦", "⟧" }, search = "⌕", life = "┃", none = "—",
            -- what set a step off
            keymap = "⌨", command = "⌨", event = "⚡", timer = "⏲", load = "◆", save = "◇", restart = "↻", label = "⎇",
            -- a move's family
            reopened = "↑", forgotten = "∅", note_dropped = "⌫", gone = "✗", back = "✓", repair = "⚒", repointed = "⟲",
            landed = "⤳", undone = "↶", dropped = "⊘", cleared = "⊘", rewritten = "✎", cancelled = "⇤", loaded = "◆",
            fresh = "◆", saved = "◇", refreshed = "◇", tab_closed = "◇", copied = "⧉", moved = "⇢", detached = "≡",
            detached_left = "≡",
        },
        ascii = {
            list = "#", closed = "v", tag = "@", more = "...",
            title = "[ trail ]", shade0 = "~", shade1 = ".", shade2 = ":", shade3 = "#", rule = "-",
            bars = "_.-=+*#", now_left = "(", now_right = ")", dot = " - ", older = "<<<", newer = ">>>",
            branch = "|- ", last = "`- ", stem = "|  ", folded = "+", unfolded = "-", arrow = " -> ", ring = ":",
            row_t = { "<", ">" }, row_c = { "[", "]" }, row_s = { "{", "}" }, search = "?", life = "|", none = "-",
            keymap = "K", command = ":", event = "E", timer = "T", load = "L", save = "S", restart = "R", label = "@",
            reopened = "^", forgotten = "0", note_dropped = "x", gone = "X", back = "+", repair = "!", repointed = "~",
            landed = ">", undone = "<", dropped = "/", cleared = "/", rewritten = "*", cancelled = "|", loaded = "L",
            fresh = "L", saved = "S", refreshed = "S", tab_closed = "S", copied = "=", moved = ">", detached = "#",
            detached_left = "#",
        },
    },
    formatters = {}, -- closed_entry, trail_step, trail_move, trail_header: each gives {text, highlight} chunks, or nil for cavediver's own
    colors = {
        base = {
            focused = {
                fg = "#B7B5AC", -- base-300
                bg = "#151515", -- your bg
            },
            unfocused = {
                fg = "#575653", -- base-700
                bg = "#151515"
            },
        },
        current = {
            focused = {
                filename = "#879A39", -- green-400
                bufnr = "#879A39",
            },
            unfocused = {
                filename = "#575653",
                bufnr = "#575653",
            }
        },
        secondary = {
            focused = {
                filename = "#879A39",
                bufnr = "#DA702C" -- orange-400
            },
            unfocused = {
                filename = "#575653",
                bufnr = "#575653",
            },
        },
        ternary = {
            focused = {
                filename = "#9F9D96", -- base-400
                bufnr = "#9F9D96"
            },
            unfocused = {
                filename = "#575653",
                bufnr = "#575653",
            },
        },
        primary = {
            active = "#FFAF00",
            inactive = "#575653",
            unfocused = "#575653"
        },
        harpooned = {
            unfocused = {
                fg = "#8B7EC8", -- purple-400
            }
        },
        both_way_arrow = {
            focused = "#4385BE", -- blue-400
            unfocused = "#4385BE"
        },
        trail = {
            list = "#8B7EC8", -- purple-400
            closed = "#DA702C", -- orange-400
            time = "#878580", -- base-500
            tag = "#6F6E69", -- base-600
            dim = "#575653", -- base-700
            -- the trail's own
            wave = { "#4385BE", "#205EA6", "#1A4F8C", "#163B66" }, -- the fill: today, a week, a month, older
            title = "#879A39", -- green-400
            date = "#B7B5AC", -- base-300
            depth = "#DA702C", -- orange-400
            count = "#878580", -- base-500
            gauge = "#4385BE", -- blue-400
            gauge_now = "#FFAF00",
            key_on = "#8B7EC8", -- purple-400
            key_off = "#575653", -- base-700
            gutter = "#575653", -- base-700
            trigger = "#878580", -- base-500
            name = "#B7B5AC", -- base-300
            words = "#878580", -- base-500
            ring = "#6F6E69", -- base-600
            fold = "#8B7EC8", -- purple-400
            reopened = "#879A39", -- green-400
            forgot = "#6F6E69", -- base-600
            gone = "#D14D41", -- red-400
            back = "#879A39", -- green-400
            repair = "#D0A215", -- yellow-400
            slot = "#3AA99F", -- cyan-400
            note = "#CE5D97", -- magenta-400
            cycle = "#4385BE", -- blue-400
            session = "#4385BE", -- blue-400
            rename = "#4385BE", -- blue-400
            row_t = "#9F9D96", -- base-400
            row_c = "#879A39", -- green-400
            row_s = "#DA702C", -- orange-400
            -- a search's life line: the name open, closed, gone from disk
            life_open = "#879A39", -- green-400
            life_closed = "#DA702C", -- orange-400
            life_gone = "#D14D41", -- red-400
        },
        -- a window with no current slot: its visit alone
        visit_bar = {
            focused = "#3AA99F", -- cyan-400
            unfocused = "#575653", -- base-700
        },
        cokeline = {
            is_picking_close = "#D14D41", -- red-400
            is_picking_focus = "#4385BE", -- blue-400
            active = "#FFAF00",
            bg = {
                detached = {
                    focused = "#282726", -- base-900
                    unfocused = "#100F0F", -- black
                },
                attached = "#151515"
            },
            fg = {
                focused = "#878580", -- base-500
                unfocused = "#6F6E69" -- base-600
            },
            diagnostics = {
                error = "#D14D41", -- red-400
                warning = "#D0A215", -- yellow-400
                info = "#3AA99F", -- cyan-400
                hint = "#879A39" -- green-400
            }
        }
    },
    keymaps = {
        -- Buffer lifecycle
        reopen_last_closed = "<M-S-w>",

        -- Core triquetra operations
        toggle_secondary = "<M-f>", -- Current ↔ Secondary toggle
        toggle_ternary = "<M-S-f>", -- Current ↔ Ternary toggle
        jump_to_primary = "<M-;><M-f>", -- Bring primary to current
        restore_ternary = "<M-;><M-r>", -- Restore ternary relationship
        restore_secondary = "<M-;><M-t>", -- Restore secondary relationship

        -- Window navigation
        toggle_window = "<M-,>", -- Toggle between current and previous window

        -- Cycling mode navigation
        cycle_left = "<M-n>", -- During cycling mode
        cycle_right = "<M-m>", -- During cycling mode
        cycle_select = "<M-v>", -- Quit cycling mode and attach history with cycling buffer

        -- Primary buffer management
        toggle_primary = "<M-;><M-x>", -- Toggle current buffer as primary
        set_primary = "<M-;><M-c>",
        close_buffer = "<M-.>",

        open_primary_buffer_history = "<M-;>F", -- Open primary buffer history
        open_closed_lists = "<M-;>W", -- Open the closed lists

        -- Inside cavediver's own views
        views = {
            leave = "q",
            leave_too = "<C-c>",
            act = "<CR>",
            act_and_stay = "gf",
            fold = "za",
            previous_section = "H",
            next_section = "L",
            pick = "<M-e>", -- the primary pop-up's: add files through the picker
            search = "s", -- the trail's: search every page for a name
            search_word = "*", -- the trail's: search for the name under the cursor
        },
    },
    -- the ledger: `ring`, how many of the last steps are kept in memory, and `dump`, whether something
    -- that shouldn't happen writes them to a file under stdpath("state")/cavediver/ and a window
    ledger = {
        ring = 1000,
        dump = true,
    },
    -- label_provider: where you are, for tagging files that go missing: nil reads .git/HEAD, a
    -- function returning a string gives the label, false turns labels off (the tag is then the time).
    -- primary_picker: the primary pop-up's file picker, a function given a callback it calls with the
    -- picked files' paths: nil uses telescope's find_files when telescope is installed.
    -- marks_provider: the marked files, for the bufferline's marks: nil reads harpoon's list when it's
    -- installed, a function returning their paths in order gives them, false marks nothing.
    -- the winbar: `own`, whether cavediver writes it (otherwise `require('cavediver').winbar_segment()`
    -- gives its segment to place yourself); `skip_filetypes`, windows of these filetypes get none
    winbar = {
        own = true,
        skip_filetypes = {
            "neo-tree-popup",
            "neo-tree",
            "notify",
            "neominimap",
            "Avante",
            "AvanteInput",
            "dropbar_menu",
            "dropbar_menu_fzf",
            "DressingInput",
            "cmp_docs",
            "cmp_menu",
            "noice",
            "prompt",
            "TelescopePrompt",
            "blink_menu",
            "blink_docs",
        },
    },
    -- <M-,> (toggle_window) skips a previous window of these filetypes
    toggle_window = {
        skip_filetypes = { "minimap", "neominimap" },
    },
    cleanup_interval = 4000,              -- milliseconds
    winbar_refresh_interval = 140         -- milliseconds
}
```

## How to use

### Window Triquetras

The cavediver plugin tracks windows showing regular file buffers. When a window switches to a non-regular buffer then it will keep the triquetra associated to that window, and the current slot stays on the file you were on, so `<m-f>` brings you back to it. The winbar shows it like `main.lua ← [help]`. Each window has their own triquetra. 

A window triquetra is a data structure that stores the window's triquetra slots: current buffer, ternary buffer, secondary buffer, and primary buffer. Each type of slot has their own means of updating themselves.

Winbar UI:
```text
⦉32⦊ [7] history/init.lua    ⟦9⟧ window/routines.lua
```

- `⦉32⦊` is the ternary buffer's buffer number.
- `[7] history/init.lua` is the current buffer.
- `⟦9⟧ window/routines.lua` is the secondary buffer.

**Ternary slot**

The ternary slot updates every time you jump to a new buffer. The current buffer you had will now become the ternary buffer when you jump to a new buffer that is not the secondary buffer. And the new buffer will become the current buffer. It's your previous buffer, basically. But it won't get updated when you select a buffer during cycling mode, via `<m-v>`.

Everytime you jump, if there is a ternary buffer, the system records your current buffer's ternary buffer, before the current buffer is replaced. So when you go back to that current buffer and want to bring back what was once before, you can do it with `<m-;><m-r>`.

**Secondary slot**

The secondary slot only updates when you say so. This is your stow slot. If you have a buffer you want to keep before jumping, this is your way. To jump to the secondary buffer, simply press `<m-f>`. The current buffer will become the secondary buffer.

Every time you jump to secondary the system also records the current buffers, secondary – just the same as ternary's way but with keys `<m-;><m-t>`

**Primary Slot**

The primary buffer is the window's "mark."
So if you have a buffer of interest that you don't want to lose your hands on, then simply make it a primary buffer, so that no matter how much you kept jumping, you can bring it back to your reach with `<m-;><m-f>`

Also take a look at the **New feature** section above as I had extended this feature as well.

**Notes**

These only works for regular file buffers. The cavediver plugin, only tracks regular file buffers. Makes it easy to deal with cross-session persistence. 

A buffer cannot occur more than once in a window triquetra.

## Bufferline

As you can see the buffers shown in the bufferline are color coded for better experience and it is sorted by buffer visits. The most recent appears on the left. This is really helpful on trying to know how you ended up with your current buffer and not solely depending on the `<c-i>` & `<c-o>`. 

There is an option `bufferline.history_view`, and this dictates whether to sort the buffers with the global visit history or the current window's own visit history. 

**bufferline.history_view = "window"**

Window-specific history is a recent addition and is really nice on seeing the bufferline not being cluttered with your previous window's series of buffer jumps. 

### Cycling

`<m-n>` and `<m-m>` calls cokeline's cycle function and this makes the whole cavediver plugin be put into "cycling" mode. You will see the change of mode with the colors of the triquetra winbar and cokeline bufferline. 

You will notice that no matter how you cycle, the current slot buffer doesn't change. It is because during cycling mode, the cavediver plugin has stopped tracking visits. You need to do `<m-v>` to select the buffer you are currently and quit cycling mode. 

## When something shouldn't happen

Cavediver keeps its last steps in memory. When something that shouldn't happen fires (an assertion, a hook failing, a broken rule), it writes them to a file under `stdpath("state")/cavediver/` and shows them in a window, and a warning says where the file is. The file is encrypted like the session files, so it only opens from the directory it was written in: `:CavediverDump <file>`.

To replay one, start Neovim in that directory with cavediver set up, open no file and load no session, then run `:lua require('cavediver').replay_dump('<file>')`. If your config loads a session when Neovim starts, start it with a minimal init that only sets cavediver up instead (`nvim -u minimal.lua`). An editor that replayed a dump doesn't save its session.
