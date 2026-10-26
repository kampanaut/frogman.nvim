# Frogman

## Introduction

So basically, this plugin allows you to manage your buffers with a per-window recall system designed around the human mind's frailty in _working memory_. Let me explain what that is: have you ever felt lost after unconsciously jumping to files trying to get around the codebase just because you forgot to be conscious about it? Like some jumps earlier you should have remembered your current filename, but you were too busy thinking about the problem at hand not the filename itself. And also sometimes you don't want to mess up your current jumping setup, like, at some point you have decided to just swap between files A and B, with A being your current file, and now you have to go to C. In traditional neovim, B would have been forgotten, and now you can only jump between A and C. It's fine if you remember the full filename of B, what if you forgot? And now it gets annoying to try remember it and then it just interrupts your flow, trying to go back to only swap between A and B. 

This is the kind of problem this plugin solves for you. This recall system is known as the **Triquetra System**. The Triquetra System is what mainly drives the recalling of buffers, with less load on your working memory. In a way because of how the triquetra buffers are presented in the UI, this gives you at least a semblance of your current jumping setup. And I have designed this in a way, that you can always restore the secondary buffer and the ternary buffer so you can always get back to what once was. There are other neat features as well, like it remembering all of this across restarts, and keeping a log of every move it makes for you, just read the **How to Use** section below.

### Functions

- **Triquetra System**: Each window keeps current/secondary/ternary buffer relationships, plus a primary queue
- **Session Persistence**: Buffer relationships survive restarts, with any session manager, in an encrypted file
- **Cycling Mode**: Explore buffers without losing your working context
- **Context Preservation**: Remembers where buffers came from for restoration
- **Buffer Lifecycle**: Closed buffers reopen when accessed through relationships
- **Closed Lists**: Every closed buffer, per session, in one editable window (`:FrogmanClosed`)
- **Missing Files**: Files gone from disk are kept, tagged with the branch they went missing from
- **Trail**: A day-by-day log of every move frogman made for you (`:FrogmanTrail`)
- **Visual Feedback**: Color-coded bufferline and winbar show buffer relationships
- **Per-Window Tracking**: Independent buffer relationships for each window

## Demo
This is a short demo. It just covers how the triquetra buffers update for all sorts of jumps. The slots update when you enter a buffer, except while cycling.

You can also see that the two windows have their own history. That's `bufferline.history_view = "window"`; by default the bufferline follows every window's visits.

![Image](https://github.com/user-attachments/assets/deb30ab4-d049-437d-bbd5-8dfe5c21bd47)

## Requirements

- neovim 0.12+
- nvim-cokeline
- openssl 3 or 4 (system installed, its libcrypto is used for encrypting the session files. Hashing is done with neovim's built-in `vim.fn.sha256`. When frogman can't find it, set `libcrypto_path` to its file. Windows is untested: there, set `libcrypto_path` to the DLL, such as `libcrypto-3-x64.dll`)
- harpoon (optional, harpooned buffers are marked in the bufferline; any other marks plugin through `marks_provider`)
- telescope.nvim (optional, used for adding files in the primary buffer pop-up)
- a session manager (optional, resession.nvim is used in the examples below)

## Installation

This works for all plugin managers.

### lazy.nvim (An example)

```lua
{
    "kampanaut/frogman",
    -- dir = "~/Projects/nvim/cavediver",
    config = true,
    dependencies = {
        "willothy/nvim-cokeline",
    },
}
```

### Session manager setup

You have to add hooks for the session manager, to allow this plugin to have persistence.
This frogman plugin saves the session state in your neovim's `data` directory by default.
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
            require('frogman').save_session(name, { tab = target_tabpage })
        end)

        resession.add_hook("post_load", function(name, opts)
            -- a tab session (a load that kept the other tabs) fills only its tab
            require('frogman').load_session(name, { tab = not opts.reset and vim.api.nvim_get_current_tabpage() or nil })
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
        "kampanaut/frogman"
    }
},
```

#### Native sessions (`:mksession`)

`save_session(vim.v.this_session)` on `SessionWritePost`, `load_session(vim.v.this_session)` on `SessionLoadPost`,
and `:mksession!` before you `:source` another one.

#### No session manager

Call `save_session()` yourself, like on `VimLeavePre`, and `load_session()` when you want it back.

### nvim-cokeline setup

The frogman plugin can work without the bufferline, but it reduces the experience a lot. 
Cokeline is what lets you visualise the visit history of all your buffers, so that you can know how you can end up 
to your current buffer.

```lua 
{
    "willothy/nvim-cokeline",
    config = function()
        require('cokeline').setup({
            show_if_buffers_are_at_least = 2,
            fill_hl = 'Normal',
            buffers = {
                -- frogman: only the buffers frogman tracks
                filter_valid = function(buffer)
                    return require('frogman').bufferline.bufnr_is_displayed(buffer.number)
                end,

                filter_visible = false,

                focus_on_delete = 'prev',

                -- frogman: ordered by the visit history
                new_buffers_position = function(buffer_a, buffer_b)
                    local compare = require('frogman').bufferline.compare_buffers(buffer_a.number, buffer_b.number)
                    return compare
                end,

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
            -- frogman: the role colours
            default_hl = {
                bg = function(buffer)
                    return require('frogman').bufferline.get_theme_bg_color(buffer.is_focused)
                end,
                fg = function(buffer)
                    return require('frogman').bufferline.get_theme_fg_color(buffer.number, buffer.is_focused)
                end,
                bold = function(buffer)
                    return require('frogman').bufferline.get_buffer_bold(buffer.number)
                end,
            },
            history = {
                enabled = false,
            },
            tabs = {
                placement = "right",
                -- frogman: the tabs' components
                components = require('frogman').bufferline.cokeline.create_tab_components()
            },
            -- frogman: the role marks, the missing-file tag and the marks
            components = require('frogman').bufferline.cokeline.create_buffer_components()
        })
    end,
    dependencies = {
        "nvim-lua/plenary.nvim", -- Required for v0.4.0+
        "nvim-tree/nvim-web-devicons", -- If you want devicons
        "kampanaut/frogman"
    },
}
```

Optional: cokeline doesn't notice `:tabmove`, so its tabs can show in the old order. This, at the end of cokeline's
`config` function, works around it:

```lua
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
```

## How to use

### Window Triquetras

The frogman plugin tracks windows showing regular file buffers. When a window switches to a non-regular buffer then it will keep the triquetra associated to that window, and the current slot stays on the file you were on, so `<m-f>` brings you back to it. The winbar shows it like `main.lua ← [15 help]`, the visited buffer's number first. Each window has their own triquetra. 

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

You can backtrack your previous primary buffers. Every time you set a new buffer as a primary, it is put in the first of a queue (primary_buffer). The first one is always the primary, the others are the "previous".
- You can manage it with a window pop-up, it is editable like that in harpoon window.
    - Delete-yank and then paste it in another place to reorder...
    - Or just delete, to really remove it.
    - Type up a filereadable filepath and just save.
        - The system validates if it is readable. If it is readable, it registers it.
        - If not, then vim.notify() an error for that line, the other lines still get saved.
    - If you press enter while under a line (in normal mode), that line will be put on top which will be promoted as the current primary buffer.
- `<m-;><m-f>` always selects the first element `primary_buffer[1]`
- If you disable primary buffer, `<m-;><m-f>` will just act like `<m-f>`, until you set it to active again. Setting a new primary from the pop-up window (a new first line, saved) sets it active again too.
- You can open the popup floating window with `<m-;>F`

**Notes**

These only works for regular file buffers. The frogman plugin, only tracks regular file buffers. Makes it easy to deal with cross-session persistence. 

A buffer cannot occur more than once among a window's current, secondary and ternary slots. The primary can be any of them.

### Bufferline

As you can see the buffers shown in the bufferline are color coded for better experience and it is sorted by buffer visits. The most recent appears on the left. This is really helpful on trying to know how you ended up with your current buffer and not solely depending on the `<c-i>` & `<c-o>`. 

There is an option `bufferline.history_view`, and this dictates whether to sort the buffers with the global visit history or the current window's own visit history. 

**bufferline.history_view = "window"**

Window-specific history is really nice on seeing the bufferline not being cluttered with your previous window's series of buffer jumps. 

### Cycling

`<m-n>` and `<m-m>` calls cokeline's cycle function and this makes the whole frogman plugin be put into "cycling" mode. You will see the change of mode with the colors of the triquetra winbar and cokeline bufferline. 

You will notice that no matter how you cycle, the current slot buffer doesn't change. It is because during cycling mode, the frogman plugin has stopped tracking visits. You need to do `<m-v>` to select the buffer you are currently on and quit cycling mode. Jumping to another window cancels the cycle, and the window goes back to the buffer you started from.

### Closing and reopening

`<m-.>` closes the current buffer and takes you to the one you were on before it. `<m-S-w>` reopens the last one you
closed. Each tab session has its own list of closed buffers; `:FrogmanClosed` (or `<m-;>W`) shows all of them in one
window you can edit: reorder the lines, move one under another list's header, delete one, `<CR>` to reopen it.

### Files gone from disk

When a file disappears, after a branch switch for example, frogman keeps it in its slots and lists and tags it with
where you were when it went, like `main.lua ⎇feature`. Using it says it isn't on disk; once the file is back, the tag
goes.

### The trail

`:FrogmanTrail` shows what frogman did for you, a page per day: where a window landed after a delete, a note it
rewrote, a file it closed onto another tab's list. `H` and `L` go to the day before and after, and `s` searches every
day for a file's whole story.

## When something shouldn't happen

Frogman keeps its last steps in memory. When something that shouldn't happen fires (an assertion, a hook failing, a broken rule), it writes them to a file under `stdpath("state")/frogman/` and shows them in a window, and a warning says where the file is. The file is encrypted like the session files, so it only opens from the directory it was written in: `:FrogmanDump <file>`.

To replay one, start Neovim in that directory with frogman set up, open no file and load no session, then run `:lua require('frogman').replay_dump('<file>')`. If your config loads a session when Neovim starts, start it with a minimal init that only sets frogman up instead (`nvim -u minimal.lua`). An editor that replayed a dump doesn't save its session. When it's done, it says what it did in one line, such as `frogman: replayed 12 steps, 5 driven, 5 matching, 0 resynced`: driven steps are your keys and window commands, run again and checked against the dump; matching ones came out the same; a resync is a step the replay first put back where the dump says it began. If it stopped, the line says where and why, and "what fired" is what the dump fired at, reproduced.

## Coming from cavediver

This plugin was called cavediver before. Do these once, in this order, before you start your first session with frogman:

1. Change your config. The old names are gone, with nothing standing in for them:
    - `require('cavediver')` becomes `require('frogman')`, the session manager's hooks included
    - the commands, `:CavediverClosed`, `:CavediverTrail`, `:CavediverWinbar` and the rest, become `:FrogmanClosed`,
      `:FrogmanTrail`, `:FrogmanWinbar` and so on
    - the highlight groups of the trail and the closed lists, `CavediverTrail*`, become `FrogmanTrail*`
    - the filetypes, `cavediver-closed-lists`, `cavediver-primary-buffer-history` and `cavediver-trail`, become
      `frogman-closed-lists`, `frogman-primary-buffer-history` and `frogman-trail`
    - the augroup, `cavediver`, becomes `frogman`

    The options `setup()` takes keep their names.

2. Run the migration script, with none of your config loaded:

    ```sh
    nvim --clean -l <frogman's directory>/scripts/migrate_sessions.lua --dry-run
    nvim --clean -l <frogman's directory>/scripts/migrate_sessions.lua
    ```

    It moves what cavediver saved, the session files in `stdpath("data")/cavediver/sessions/` and the dumps in
    `stdpath("state")/cavediver/`, into frogman's folders, then converts the session files from before encryption. A
    file frogman's folder has already stays where it is, and the script names it. With `--session-dir` naming a folder
    of your own, the session files aren't moved. If your setup sets them, pass `--session-dir`, `--resession-dir` and
    `--libcrypto-path` too.

    Run it before your first session: a session started first saves a fresh file, and the script won't convert over
    it unless you pass `--replace`. A load that finds an old file tells you the command, with the path for your install.

## Configuration Defaults

Every option `setup()` takes, with its default. Pass only what you change.

You can make your own theme as well, make your own color markers for each buffer type.

You can start by just modifying the base colors

<details>
<summary>The defaults</summary>

```lua
local defaults = {
    session_dir = vim.fn.stdpath("data") .. "/frogman/sessions/",
    -- libcrypto_path: OpenSSL's libcrypto, a full path or a name the system finds, tried before
    -- frogman's own list (nil tries the list alone); ~ and $HOME in it are expanded. It's read
    -- the first time it's needed, and again only when no libcrypto loaded and it has changed since
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
    formatters = {}, -- closed_entry, trail_step, trail_move, trail_header: each gives {text, highlight} chunks, or nil for frogman's own
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

        -- Inside frogman's own views
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
            write = "<C-s>", -- the closed lists' and the primary pop-up's: write the edits
        },
    },
    -- the ledger: `ring`, how many of the last steps are kept in memory, and `dump`, whether something
    -- that shouldn't happen writes them to a file under stdpath("state")/frogman/ and a window
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
    -- the winbar: `own`, whether frogman writes it (otherwise `require('frogman').winbar_segment()`
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

</details>
