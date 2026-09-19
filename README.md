# sbnc-buffer-slots.nvim

Jump between open file buffers by their slot position. Think of it as 10 quick
"registers" for your buffers — **no manual marking needed**. Buffers are tracked
automatically as you open them, and [bufferline.nvim](https://github.com/akinsho/bufferline.nvim)
(if installed) automatically shows the tabs in slot order, prefixed by slot number.

## Features

- **Automatic tracking** — open buffers are assigned slots `1..10` in the order
  they're opened. Already-open buffers are claimed on startup/reload, so there's
  nothing to add or pin manually.
- **Switch by slot** — jump to the buffer in a slot. Pressing an empty slot
  opens a fresh blank buffer you can `:e <file>` into.
- **Swap slots** — swap the current buffer's slot with another.
- **Next / previous** — step through file buffers.
- **List** — print the current slot assignments.
- **bufferline integration** — tabs sorted + numbered by slot, automatic.

## Requirements

- Neovim `>= 0.9` (uses `vim.api.nvim_set_current_buf`, `vim.schedule`, etc.)

## Installation

**lazy.nvim:**

```lua
{ "joshua-cabantac/sbnc-buffer-slots.nvim", lazy = false },
```

Or straight into your config:

```lua
require("sbnc_buffer_slots")
```

The buffer tracking (autocommands) and slot prefill run automatically on
`require`. **No keymaps are registered by default** — add your own below.

## Provided actions

The plugin exposes these functions (they don't bind any keys):

| Function | Action |
|----------|--------|
| `switch(slot)` | Jump to the buffer in slot 1–10 (empty slot opens a blank buffer) |
| `swap(slot)` | Swap the current buffer's slot with that slot |
| `next()` | Switch to the next file buffer |
| `prev()` | Switch to the previous file buffer |
| `list()` | Show slot assignments |
| `compact()` | Close the gaps between slots (see below) |
| `manager()` | Open the oil-style slot manager (see below) |

## Example configuration (author's bindings)

This is the layout the author uses. Copy it and change the keys to taste — the
actions are fixed, the keys are yours.

```lua
local slots = require("sbnc_buffer_slots")

-- Switch to slot 1..10
for i = 1, 9 do
  vim.keymap.set("n", "<leader>" .. i, function() slots.switch(i) end,
    { desc = "Switch to buffer " .. i })
end
vim.keymap.set("n", "<leader>0", function() slots.switch(10) end,
  { desc = "Switch to buffer 10" })

-- Swap current buffer with slot N: leader + shifted number row.
-- NOTE: assumes a German/QWERTZ layout (! = Shift+1 ... = = Shift+0).
local swap_keys = { ['1'] = '!', ['2'] = '"', ['3'] = '§', ['4'] = '$',
  ['5'] = '%', ['6'] = '&', ['7'] = '/', ['8'] = '(', ['9'] = ')' }
for slot, key in pairs(swap_keys) do
  vim.keymap.set("n", "<leader>" .. key, function() slots.swap(tonumber(slot)) end,
    { desc = "Swap current buffer with slot " .. slot })
end
vim.keymap.set("n", "<leader>=", function() slots.swap(10) end,
  { desc = "Swap current buffer with slot 10" })

-- Next / previous / list / compact / manager
vim.keymap.set("n", "<leader>bn", slots.next, { desc = "Next file buffer" })
vim.keymap.set("n", "<leader>bp", slots.prev, { desc = "Previous file buffer" })
vim.keymap.set("n", "<leader>bl", slots.list, { desc = "List slots" })
vim.keymap.set("n", "<leader>br", slots.compact, { desc = "Compact slots" })
vim.keymap.set("n", "<leader>bo", slots.manager, { desc = "Open slot manager" })
```

### Compacting (`compact()`)

Swapping buffers around leaves gaps: slots `1, 2, 8` with three buffers.
`compact()` closes those gaps — `1, 2, 8` becomes `1, 2, 3` — preserving the
buffers' relative order. Only real file buffers count as content; blank
(unnamed) buffers stay tracked but get pushed to the tail slots so they don't
clutter the front.

### Slot manager (`manager()`)

Opens a bottom split listing one slot per line, oil-style: **the buffer is the
config**. Edit the lines, then write (`:w`) to apply:

- **Reorder lines** to reorder slots
- **Delete a line** to remove that buffer from its slots
- `<CR>` — open the buffer under the cursor
- `x` — close (bdelete) the buffer under the cursor
- `q` — close the manager window

Each line starts with the buffer number so buffers stay identifiable no matter
how you rearrange them.

## How buffers are counted

A buffer is only tracked if it is a real, named file buffer: it has a non-empty
name, is listed, and is not a special buffer (`term://`, scratch, etc.). Empty
`[No Name]` buffers created but never given a file are cleaned up on reload.

## bufferline integration (automatic)

If you use [bufferline.nvim](https://github.com/akinsho/bufferline.nvim), the
plugin integrates with it **automatically** on load — no configuration needed:

- tabs are **ordered by slot number** (slot 1 first), and
- each tab is **prefixed with its slot number** (e.g. `3 main.lua`), and
- swapping slots (`<leader>bsN`) **re-sorts the tabline immediately**.

This works regardless of load order (before or after `bufferline.setup()`) and
preserves the rest of your bufferline options. bufferline is **not** a
dependency — the integration no-ops when it isn't installed.

To opt out:

```lua
require("sbnc_buffer_slots").setup({ bufferline = false })
```

## References

Inside Neovim: `:help lua-guide`, `:help vim.keymap.set()`, `:help api-buffer`.