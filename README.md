# Frogman

Per-window buffer recall for Neovim: the buffers you're juggling stay within reach, and come back after a restart.

## Contents

- [Why frogman](#why-frogman)
- [Demo](#demo)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [How to use](#how-to-use)
- [Session manager setup](#session-manager-setup)
- [Bufferline setup (nvim-cokeline)](#bufferline-setup-nvim-cokeline)
- [Guides](#guides)
- [Commands](#commands)
- [Lua API](#lua-api)
- [Highlight groups](#highlight-groups)
- [FAQ](#faq)
- [When something shouldn't happen](#when-something-shouldnt-happen)
- [Configuration Defaults](#configuration-defaults)
- [Coming from cavediver](#coming-from-cavediver)
- [License](#license)

Everything here is also in Neovim's help: `:h frogman`.

## Why frogman
So basically, this plugin allows you to manage your buffers with a per-window recall system designed around the human mind's frailty in _working memory_. Let me explain what that is: have you ever felt lost after unconsciously jumping to files trying to get around the codebase just because you forgot to be conscious about it? Like some jumps earlier you should have remembered your current filename, but you were too busy thinking about the problem at hand not the filename itself. And also sometimes you don't want to mess up your current jumping setup, like, at some point you have decided to just swap between files A and B, with A being your current file, and now you have to go to C. In traditional neovim, B would have been forgotten, and now you can only jump between A and C. It's fine if you remember the full filename of B, what if you forgot? And now it gets annoying to try remember it and then it just interrupts your flow, trying to go back to only swap between A and B. 

This is the kind of problem this plugin solves for you. This recall system is known as the **Triquetra System**. The Triquetra System is what mainly drives the recalling of buffers, with less load on your working memory. In a way because of how the triquetra buffers are presented in the UI, this gives you at least a semblance of your current jumping setup. And I have designed this in a way, that you can always restore the secondary buffer and the ternary buffer so you can always get back to what once was. On top of the triquetras there are marks, for the buffers you keep coming back to, and snapshots, to save a window's whole setup and get back to it later. There are other neat features as well, like it remembering all of this across restarts, and keeping a log of every move it makes for you, just read the **How to Use** section below.

## Demo
This is a short demo. It just covers how the triquetra buffers update for all sorts of jumps. The slots update when you enter a buffer, except while cycling.

You can also see that the two windows have their own history. That's `bufferline.history_view = "window"`; by default the bufferline follows every window's visits.

![Image](https://github.com/user-attachments/assets/deb30ab4-d049-437d-bbd5-8dfe5c21bd47)

## Features
- **Triquetra System**: Each window keeps current/secondary/ternary buffer relationships, plus a primary queue
- **Session Persistence**: Buffer relationships survive restarts, with any session manager, in an encrypted file
- **Cycling Mode**: Explore buffers without losing your working context
- **Context Preservation**: Remembers where buffers came from for restoration
- **Marks**: Long-term recall: buffers under keys you pick, per window, tab or session, in an editable pop-up (`:FrogmanMarks`)
- **Snapshots**: Save points of a window's whole setup, to preview and take back later (`:FrogmanSnapshots`)
- **Buffer Lifecycle**: Closed buffers reopen when accessed through relationships
- **Closed Lists**: Every closed buffer, per session, in one editable window (`:FrogmanClosed`)
- **Missing Files**: Files gone from disk are kept, tagged with the branch they went missing from
- **Trail**: A day-by-day log of every move frogman made for you (`:FrogmanTrail`)
- **Visual Feedback**: Color-coded bufferline and winbar show buffer relationships
- **Per-Window Tracking**: Independent buffer relationships for each window

## Requirements

- neovim 0.12+
- nvim-cokeline
- openssl 3 or 4 (system installed, its libcrypto is used for encrypting the session files. Hashing is done with neovim's built-in `vim.fn.sha256`. When frogman can't find it, set `libcrypto_path` to its file. Windows is untested: there, set `libcrypto_path` to the DLL, such as `libcrypto-3-x64.dll`)
- telescope.nvim (used for adding files in the primary buffer pop-up, and for picking a mark's alias and file in the marks pop-up)
- nvim-window-picker (used for picking a window to show a snapshot in when its list's window is gone)
- a session manager (optional, resession.nvim is used in the examples below)

## Installation

This works for all plugin managers.

### lazy.nvim (An example)

```lua
{
    "kampanaut/frogman.nvim",
    config = true,
    dependencies = {
        "willothy/nvim-cokeline",
        "nvim-telescope/telescope.nvim",
        "s1n7ax/nvim-window-picker",
    },
}
```

## Quick start

Install it like above and that's it, `config = true` calls `setup()` with the defaults. Then try this:

1. Open a few files, one after another, and look at the winbar. `⦉N⦊` is the buffer you were on before (the ternary), and `[N]` is the one you're on now.
2. Press `<m-f>`. You don't have a secondary yet, so your previous buffer moves into it, and the winbar shows it as `⟦N⟧`. Press `<m-f>` again and you swap to it, and once more to swap back.
3. Press `<m-S-f>` to swap with the ternary instead.
4. On a buffer you want to keep close, press `<m-;><m-c>` to make it the window's primary. Jump around as much as you like, then `<m-;><m-f>` brings it back.
5. `<m-.>` closes the buffer you're on, and `<m-S-w>` reopens it.

To keep all of this across restarts, hook frogman into your session manager ([Session manager setup](#session-manager-setup)), and set up cokeline to see the visit order ([Bufferline setup](#bufferline-setup-nvim-cokeline)).

## How to use

### The recall tiers

So frogman gives you three ways to hold on to a buffer, and each one is for a different kind of remembering:

- **The triquetra** is what you're juggling right now. It's ephemeral in how you use it, the slots shift as you jump around, but frogman still brings it back after a restart.
- **The primary** is the bridge. It's the one buffer you lift out of the turnover, with its own key, `<m-;><m-f>`, so it doesn't get pushed out while you jump around.
- **Marks** are long-term recall. They're there every time, under keys you pick, for a window, a tab or the whole session.

You can cross the bridge both ways: mark your primary like any other buffer, or press `<m-c>` on a mark in the marks pop-up to make it the primary.

And then there are **snapshots**, which aren't a tier: a snapshot is a save point of a window's whole setup, for when you want to come back to exactly how it was.

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
- You can manage it with a window pop-up, it is editable like any other buffer.
    - Delete-yank and then paste it in another place to reorder...
    - Or just delete, to really remove it.
    - Type up a filereadable filepath and just save.
        - The system validates if it is readable. If it is readable, it registers it.
        - If not, then it asks you first, listing the lines it would leave out. Say yes and the other lines still get saved, say no and you're back in the pop-up with nothing saved.
    - If you press enter while under a line (in normal mode), that line will be put on top which will be promoted as the current primary buffer.
- `<m-;><m-f>` always selects the first element `primary_buffer[1]`
- If you disable primary buffer, `<m-;><m-f>` will just act like `<m-f>`, until you set it to active again. Setting a new primary from the pop-up window (a new first line, saved) sets it active again too.
- You can open the popup floating window with `<m-;>F`

**Notes**

These only works for regular file buffers. The frogman plugin, only tracks regular file buffers. Makes it easy to deal with cross-session persistence. 

A buffer cannot occur more than once among a window's current, secondary and ternary slots. The primary can be any of them.

### Marks

Marks replace harpoon. You mark a buffer under an alias, and then you can jump to it from anywhere with that alias' key.

The prefix is `<m-'>`. With the default aliases, `a s d f u i o p`:
- `<m-'><m-'><m-a>` marks the current buffer under `a`. The winbar tells you what happened for a moment.
- `<m-'><m-a>` jumps to whatever `a` holds. If it's closed, it gets reopened.

Marks live in a scope, and you pick which one with the mode keys:
- `<m-'><m-1>` is window mode, the marks of the window you're in
- `<m-'><m-2>` is tab mode, the marks of the tab
- `<m-'><m-3>` is session mode, the marks of the session

In a tab session's tab, tab mode and session mode are the same thing. The bufferline repaints with the current mode's marks, a marked buffer showing its aliases next to its name, like `api.lua ⟨a,s⟩`.

**The marks pop-up**

`<m-'><m-e>` (or `:FrogmanMarks`) opens the current mode's marks in a pop-up you can edit like any other buffer:

```text
marks · window
❖ main
a -> api.lua
s -> routes/user.lua
d ->
```

- Each `❖` line is a group header, and the first group is the one the keys use. Type a new header to make a group. Delete a header and its marks join the group above, it asks you first.
- Edit a row to change what an alias points to, or press `a` to pick an alias and then a file through telescope.
- `<cr>` jumps to the line's file and closes the pop-up, `gf` jumps and keeps it open, and `<m-c>` makes the line's file the primary of the window you opened the pop-up from.
- `:w` writes, `q` writes and leaves, `:q!` drops your edits. The mode keys work in here too, and the scope you leave keeps your edits as a draft until you write them.
- An alias can only hold one file in a group. If you mark a buffer under an alias that's taken, the pop-up opens on the conflict for you to settle.

When a window or a tab closes, its marks don't just disappear. They go onto its entry in the session file, or if it has none, they get held over as a group of their own in the session's marks, like `❖ held over · window on api.lua · 11-09 14:05`. A held-over group stays until you delete its header, and it only drives the keys once you move it.

If you want a new split to start with a copy of its window's marks, set `marks.split_copies = true`.

### Snapshots

A snapshot is a save point you make on purpose: the window's slots, its notes, its primary queue and the order its bufferline drew. You take one when you have a setup you want to come back to.

- `<m-;><m-s>` takes a snapshot of the window you're in.
- `<m-;>S` (or `:FrogmanSnapshots`) opens the window's snapshot list. Each line shows its time, its triquetra and its order.
- `<cr>` on a line previews it in the window. You see the snapshot's slots and order, you can step through its files with `<m-n>` and `<m-m>`, and nothing gets recorded.
- `<m-v>` takes the snapshot, landing on the buffer you're on.
- Press `<m-;>S` again to open the pop-up, quitting the preview: the window goes back to how it was, and `q` closes the pop-up. Jumping to another window quits it too, and `<m-,>` quits it and jumps to the previous window.

The list is editable too: delete a line and write to delete that snapshot. Each line carries the whole snapshot, so you can yank a line from one window's list and paste it into another window's list to copy it there, or cut and paste to move it. That's how you "duplicate" a window's setup. The lines are encrypted like the session files, so a line opens in the project it came from, and anywhere else it asks you for that directory.

While a snapshot shows, the session can't be saved, so the session manager setup below calls `require('frogman').cancel_preview()` before its saves. A window that closes with no saved entry has its snapshots held over in the session, like its marks.

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

## Session manager setup

You have to add hooks for the session manager, to allow this plugin to have persistence.
This frogman plugin saves the session state in your neovim's `data` directory by default.
It doesn't care which session manager you use, it just needs these to happen:
- `save_session(name)` is called before the editor is torn down
- `load_session(name)` is called after the session manager restored your buffers and windows
- the session you are leaving gets saved before you switch to another one
- for tab sessions, the tab's session gets saved before its tab closes

### resession.nvim

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
            -- a snapshot showing is left first: frogman refuses a save while one shows
            require('frogman').cancel_preview()
            resession.save_all({ notify = false })
        end)

        vim.api.nvim_create_autocmd("TabClosedPre", {
            callback = function()
                local info = resession.get_current_session_info()
                if info and info.tab_scoped and not resession.is_loading() then
                    require('frogman').cancel_preview()
                    resession.save_tab(info.name, { dir = info.dir, notify = false })
                end
            end,
        })
    end,
    dependencies = {
        "kampanaut/frogman.nvim"
    }
},
```

This next part is optional, and only there to save you an annoyance. If you have resession's `autosave` on, every tick that comes while a snapshot shows pops up an error: frogman refuses a save during a preview by raising one, and resession's timer runs the save hooks with nothing catching them. Nothing gets saved and nothing breaks, it's just noise until you leave the preview. To skip it, run the timer yourself and have it pass over the ticks during a preview. `require('frogman').previewing()` tells you whether one shows. resession's autosave also saves as you quit, so that part goes into your own `VimLeavePre`:

```lua
resession.setup({
    autosave = { enabled = false },
    -- your configurations....
})

local autosave = vim.uv.new_timer()
autosave:start(300000, 300000, vim.schedule_wrap(function()
    if not require('frogman').previewing() then
        resession.save_all({ notify = false })
    end
end))

vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
        resession.save_all({ notify = false })
    end,
})
```

### Native sessions (`:mksession`)

`save_session(vim.v.this_session)` on `SessionWritePost`, `load_session(vim.v.this_session)` on `SessionLoadPost`,
and `:mksession!` before you `:source` another one.

### No session manager

Call `save_session()` yourself, like on `VimLeavePre`, and `load_session()` when you want it back.

## Bufferline setup (nvim-cokeline)

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
        "kampanaut/frogman.nvim"
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

## Guides

### Sort the bufferline by each window's own visits

By default the bufferline follows every window's visits. To have each window show its own:

```lua
require('frogman').setup({
    bufferline = { history_view = "window" },
})
```

### Put frogman's winbar into your own

Tell frogman not to write the winbar, and place its segment yourself. `vim.g.statusline_winid` is the window being drawn, so each window gets its own triquetra:

```lua
require('frogman').setup({
    winbar = { own = false },
})

function _G.MyWinbar()
    return "  " .. require('frogman').winbar_segment(vim.g.statusline_winid)
end
vim.o.winbar = "%!v:lua.MyWinbar()"
```

### Copy a window's setup into another window

1. In the window you want to copy, take a snapshot with `<m-;><m-s>`.
2. Open its list with `<m-;>S`, yank the snapshot's line, and leave with `q`.
3. In the other window, open its list with `<m-;>S`, paste the line, and write.
4. `<cr>` on the line shows it, and `<m-v>` takes it.

Cut instead of yank to move the snapshot rather than copy it.

### Use tab sessions with resession

With the hooks from [resession.nvim](#resessionnvim) in place, a tab session is just resession's:

```lua
-- save the tab you're in as its own session
require('resession').save_tab("notes")
-- load it into the tab you're in, the other tabs left as they are
require('resession').load("notes")
```

The tab's closed buffers and its marks are its own from then on, and closing the tab saves it (the `TabClosedPre` part of the setup). If you load the same session into another tab, it moves there, and the tab it left keeps a copy of its list, like `notes_DETACHED`.

### Use your own keys

Set a key to `false` to leave it unmapped, then map the function yourself:

```lua
require('frogman').setup({
    keymaps = { toggle_secondary = false },
})
vim.keymap.set('n', '<leader>s', require('frogman').toggle_secondary, { desc = "Swap with the secondary" })
```

Every key has its function, they're listed in [Lua API](#lua-api).

### Use other mark aliases

The aliases are a table of each alias and its place, one alias to one place. Yours replaces the default table whole:

```lua
require('frogman').setup({
    marks = { aliases = { j = 1, k = 2, l = 3, h = 4 } },
})
```

### Draw with ASCII glyphs

If your font doesn't have the Unicode glyphs frogman's views use:

```lua
require('frogman').setup({
    glyphs = { set = "ascii" },
})
```

You can also swap a single glyph, like `glyphs = { group = "#" }`.

## Commands

| Command | What it does |
|---|---|
| `:FrogmanClosed` | Open the closed lists |
| `:FrogmanMarks` | Open the marks pop-up on the current mode's marks |
| `:FrogmanSnapshots` | Open the window's snapshot list |
| `:FrogmanTrail [name]` | Open the trail, or with a name, that name's whole story across every day |
| `:FrogmanDump <file>` | Open a dump, decrypted, in a window (only from the directory it was written in) |
| `:FrogmanWinbar [on\|off\|toggle]` | Switch the winbar on or off; no argument toggles |
| `:FrogmanBufferline [on\|off\|toggle]` | Switch the bufferline on or off; no argument toggles |
| `:FrogmanIndicators [roles\|marks] [on\|off\|toggle]` | Switch the bufferline's role marks or marks' aliases on or off, both when neither is named |

And for debugging, these print frogman's internal state, which can change between versions: `:FrogmanTriquetra`, `:FrogmanTriquetraVerbose`, `:FrogmanAllTriquetras`, `:FrogmanRegistry`, `:FrogmanHistoryData`, `:FrogmanNavigationData`, `:FrogmanWindowData` and `:FrogmanUIData`.

## Lua API

All of these are fields of `require('frogman')`. `:h frogman-api` has each one in full.

**Setup**
- `setup(opts)`: set frogman up, `opts` over the defaults. Calling it again starts over from the defaults.
- `disable()`: turn frogman off, until `setup()` runs again.
- `config`: the settings in use.

**Sessions**
- `save_session(name, opts)`: save the session; `opts.tab` is a tab session's tabpage.
- `load_session(name, opts)`: load it, after the session manager restored your buffers and windows; `opts.tab` is the tab a tab session fills.
- `cancel_preview()`: leave a snapshot that's showing. A save is refused while one shows.
- `previewing()`: whether a snapshot is showing.

**Keys**, each the function behind its key:
`toggle_secondary()`, `toggle_ternary()`, `jump_to_primary()`, `restore_ternary()`, `restore_secondary()`, `toggle_window()`, `cycle_left()`, `cycle_right()`, `cycle_select()`, `set_primary()`, `toggle_primary()`, `delete_buffer()` (the close key), `reopen_last_closed()`, `open_primary_buffer_history()`, `open_closed_lists()`, `take_snapshot()`, `open_snapshots()`.

**Marks**
- `mark_mode(mode)`: `"window"`, `"tab"` or `"session"`.
- `mark_jump(alias)`, `mark_add(alias)`: jump to a mark, or mark the current buffer.
- `mark_popup()`: open the marks pop-up.

**The trail and dumps**
- `open_trail(name)`: open the trail, on a name's search when given.
- `replay_dump(path)`: replay a dump.

**State**
- `is_cycling()`, `get_storage_state()`, `get_navigation_state()`, `get_history_state()`.
- `get_window_triquetra(winid)`, `get_all_triquetras()`: a window's triquetra, or every window's, their slots holding file handles.
- `get_buffer_history()`: the visit history, by file handle.
- `get_smart_basename(handle)`: a file's shortest name that tells it apart, as the winbar draws it.

**UI**
- `winbar_segment(winid)`: a window's winbar segment, for a winbar of your own.
- `set_cache_from_window_triquetra(winid)`: rebuild a window's display cache.
- `bufferline`: the functions cokeline's setup calls.

**Internals**, for debugging, which can change between versions: `history`, `window`, `navigation`, `storage`, `ui`, `ledger`, `engine`.

## Highlight groups

Frogman sets these from the `colors` option, and again after `:colorscheme`; a group your colorscheme defines stays its own. `:h frogman-highlights` has what each one colours.

- The winbar: `WinbarBase`, `WinbarBufnrCurrent`, `WinbarFilenameCurrent`, `WinbarBufnrSecondary`, `WinbarFilenameSecondary`, `WinbarBufnrTernary`, `WinbarFilenameTernary`, `WinbarBufnrPrimary`, `WinbarBufnrPrimaryDisabled`, `WinbarVisit` and `BothWayNerdArrow`, each with an `NC` twin for a window without focus, but `WinbarBufnrPrimaryDisabled`.
- The trail and the closed lists: `FrogmanTrail*`, like `FrogmanTrailList`, `FrogmanTrailClosed` and `FrogmanTrailWave0` to `FrogmanTrailWave3`.
- The snapshot list's order: `FrogmanOrderPrimary`, `FrogmanOrderSecondary`, `FrogmanOrderCurrent`, `FrogmanOrderTernary`, `FrogmanOrderMarked` and `FrogmanOrderOpen`.

## FAQ

**Some of my buffers don't show in the bufferline.**
Frogman only tracks regular file buffers and No Name buffers. Help, terminals, quickfix lists and the like aren't tracked: a window visiting one keeps its triquetra, and `<m-f>` brings you back.

**My slots didn't come back after a restart.**
Check the session manager's hooks first ([Session manager setup](#session-manager-setup)): `save_session` has to run before the editor is torn down, and `load_session` after the session manager restored your windows. The session files are encrypted with a key from the project's directory, so a session only opens from the directory it was saved in. And if OpenSSL's libcrypto can't be found, the save and the load say so: set `libcrypto_path` to its file.

**A save says it's refused while a snapshot shows.**
That's on purpose: while a snapshot shows, the window isn't really yours yet. Take it with `<m-v>`, or leave it by opening the list again or going to another window. Your session manager's switch should call `require('frogman').cancel_preview()` before it saves, like the setup above does.

**Do I need cokeline, or a session manager?**
No to both, frogman runs without them. Without cokeline you lose the visit order and the role colours in the bufferline, and without a session manager nothing comes back after a restart, unless you call `save_session()` and `load_session()` yourself.

**Where are my sessions, and are they private?**
In `stdpath("data")/frogman/sessions/` by default (`session_dir`), encrypted with AES-256-GCM through OpenSSL's libcrypto, with a key from the project's directory. The dumps under `stdpath("state")/frogman/` are encrypted the same way.

**A window popped up saying something shouldn't happen.**
That's the flight recorder: frogman caught one of its own bugs and wrote its last steps to a file. See [When something shouldn't happen](#when-something-shouldnt-happen) to read it or replay it.

**How do I turn frogman off for a while?**
`require('frogman').disable()`, and `require('frogman').setup()` to turn it back on.

## When something shouldn't happen

Frogman keeps its last steps in memory. When something that shouldn't happen fires (an assertion, a hook failing, a broken rule), it writes them to a file under `stdpath("state")/frogman/` and shows them in a window, and a warning says where the file is. The file is encrypted like the session files, so it only opens from the directory it was written in: `:FrogmanDump <file>`.

To replay one, start Neovim in that directory with frogman set up, open no file and load no session, then run `:lua require('frogman').replay_dump('<file>')`. If your config loads a session when Neovim starts, start it with a minimal init that only sets frogman up instead (`nvim -u minimal.lua`). An editor that replayed a dump doesn't save its session. When it's done, it says what it did in one line, such as `frogman: replayed 12 steps, 5 driven, 5 matching, 0 resynced`: driven steps are your keys and window commands, run again and checked against the dump; matching ones came out the same; a resync is a step the replay first put back where the dump says it began. If it stopped, the line says where and why, and "what fired" is what the dump fired at, reproduced.

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
    marks_popup = {
        height = 0.5, -- can be a ratio or a whole number
        width = 0.6, -- can be a ratio or a whole number
    },
    snapshots_popup = {
        height = 0.4, -- can be a ratio or a whole number
        width = 0.8, -- can be a ratio or a whole number
    },
    -- the trail's header: its tally of the day's moves, its gauge of the days, its fill shaded by depth
    trail = {
        header = { tally = true, gauge = true, shade = true },
    },
    glyphs = {
        set = "unicode", -- "unicode" | "ascii"; a glyph named here, outside the sets, replaces the set's
        unicode = {
            list = "≡", closed = "↓", tag = "⎇", more = "…", group = "❖",
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
            detached_left = "≡", taken = "⊡", committed = "⊞",
        },
        ascii = {
            list = "#", closed = "v", tag = "@", more = "...", group = "*",
            title = "[ trail ]", shade0 = "~", shade1 = ".", shade2 = ":", shade3 = "#", rule = "-",
            bars = "_.-=+*#", now_left = "(", now_right = ")", dot = " - ", older = "<<<", newer = ">>>",
            branch = "|- ", last = "`- ", stem = "|  ", folded = "+", unfolded = "-", arrow = " -> ", ring = ":",
            row_t = { "<", ">" }, row_c = { "[", "]" }, row_s = { "{", "}" }, search = "?", life = "|", none = "-",
            keymap = "K", command = ":", event = "E", timer = "T", load = "L", save = "S", restart = "R", label = "@",
            reopened = "^", forgotten = "0", note_dropped = "x", gone = "X", back = "+", repair = "!", repointed = "~",
            landed = ">", undone = "<", dropped = "/", cleared = "/", rewritten = "*", cancelled = "|", loaded = "L",
            fresh = "L", saved = "S", refreshed = "S", tab_closed = "S", copied = "=", moved = ">", detached = "#",
            detached_left = "#", taken = "o", committed = "O",
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
        marked = {
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
        take_snapshot = "<M-;><M-s>", -- Take a snapshot of the window
        open_snapshots = "<M-;>S", -- Open the window's snapshots

        -- Marks: the prefix, then <M-1>, <M-2> or <M-3> for the window's, the tab's or the session's
        -- marks; then an alias, <M-a>, to jump to its mark; twice, <M-'><M-'><M-a>, to mark the buffer there
        mark_prefix = "<M-'>",
        mark_popup = "<M-e>", -- after the prefix: the marks pop-up
        mark_modes = { window = "<M-1>", tab = "<M-2>", session = "<M-3>" }, -- after the prefix: the marks' modes

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
            add = "a", -- the marks pop-up's: add a mark through the picker, an alias then a file
            make_primary = "<M-c>", -- the marks pop-up's: make the line's file the primary
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
    -- frogman's marks: `aliases`, each mark's key and its index (one alias to one index), and
    -- `default_group`, the name of the group a scope gets at its first mark
    marks = {
        aliases = { a = 1, s = 2, d = 3, f = 4, u = 5, i = 6, o = 7, p = 8 },
        default_group = "main",
        split_copies = false, -- whether a split starts with a copy of its window's marks
    },
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
    - a file is a handle now, a number, where it was a hash: `get_buffer_history()` is keyed by handles, the
      triquetras `get_window_triquetra()` and `get_all_triquetras()` give hold handles in their slots and notes,
      `history.get_closed_buffers()` lists handles, and `get_smart_basename()` takes one;
      `require('frogman').history.get_hash_from_handle(id)` gives a handle's hash

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

    It also gives each tab session's file a name of its own: a tab session and the whole editor's session with one
    name shared a file before. resession's tab sessions are found through its list; `--tab-session <directory>
    [<name>]` names one it doesn't list, and can be given more than once.

    Run it before your first session: a session started first saves a fresh file, and the script won't convert over
    it unless you pass `--replace`. A load that finds an old file tells you the command, with the path for your
    install, the folder and library your setup sets, and, for a tab session's file, the session itself.

## License

MIT, see [LICENSE](LICENSE).
