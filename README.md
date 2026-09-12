# sbnc-buffer-slots.nvim

Jump between open file buffers by their slot position. Think of it as 10 quick
"registers" for your buffers — **no manual marking needed**. Buffers are tracked
automatically as you open them, and the bufferline reflects the slot order.

## Features

- **Automatic tracking** — open buffers are assigned slots `1..10` in the order
  they're opened. Already-open buffers are claimed on startup/reload, so there's
  nothing to add or pin manually.
- **Switch by slot** — jump to the buffer in a slot. Pressing an empty slot
  opens a fresh blank buffer you can `:e <file>` into.
- **Swap slots** — swap the current buffer's slot with another.
- **Next / previous** — step through file buffers.
- **List** — print the current slot assignments.

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

-- Swap current buffer with slot 1..10
for i = 1, 9 do
  vim.keymap.set("n", "<leader>bs" .. i, function() slots.swap(i) end,
    { desc = "Swap current buffer with slot " .. i })
end
vim.keymap.set("n", "<leader>bs0", function() slots.swap(10) end,
  { desc = "Swap current buffer with slot 10" })

-- Next / previous / list
vim.keymap.set("n", "<leader>bn", slots.next, { desc = "Next file buffer" })
vim.keymap.set("n", "<leader>bp", slots.prev, { desc = "Previous file buffer" })
vim.keymap.set("n", "<leader>bl", slots.list, { desc = "List slots" })
```

## How buffers are counted

A buffer is only tracked if it is a real, named file buffer: it has a non-empty
name, is listed, and is not a special buffer (`term://`, scratch, etc.). Empty
`[No Name]` buffers created but never given a file are cleaned up on reload.

## Optional: bufferline integration

If you use [bufferline.nvim](https://github.com/akinsho/bufferline.nvim), tabs
are automatically:

- **ordered by slot number** (slot 1 first), and
- **prefixed with their slot number** (e.g. `3 main.lua`).

This is optional — bufferline is not a dependency. The sort/number hooks are
wired through the exported `compare_slots` and `slot_for`, and degrade
gracefully if bufferline isn't installed.

## References

Inside Neovim: `:help lua-guide`, `:help vim.keymap.set()`, `:help api-buffer`.