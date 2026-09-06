# buffer-slots.nvim

Jump between open file buffers by their slot position. Think of it as 10 quick
"registers" for your buffers — **no manual marking needed**. Buffers are tracked
automatically as you open them, and the bufferline reflects the slot order.

## Features

- **Automatic tracking** — open buffers are assigned slots `1..10` in the order
  they're opened. Already-open buffers are claimed on startup/reload, so there's
  nothing to add or pin manually.
- **Switch by slot** — `<leader>1`..`<leader>9` and `<leader>0` jump to the
  buffer in that slot. Pressing an empty slot opens a fresh blank buffer you can
  `:e <file>` into.
- **Swap slots** — `<leader>bs<number>` swaps the current buffer's slot with the
  target slot.
- **Next / previous** — `<leader>bn` / `<leader>bp` step through file buffers.
- **List** — `<leader>bl` prints the current slot assignments.

## Requirements

- Neovim `>= 0.9` (uses `vim.api.nvim_set_current_buf`, `vim.schedule`, etc.)

## Installation

**lazy.nvim:**

```lua
{ "yourname/buffer-slots.nvim", config = function() require("buffer_slots").setup() end }
```

Or straight into your config:

```lua
require("buffer_slots").setup()
```

Calling `setup()` registers the keymaps. The autocommands (buffer tracking)
and slot prefill run automatically on `require` — there is no separate init to
call.

## Keybindings

| Key | Action |
|-----|--------|
| `<leader>1`..`<leader>9`, `<leader>0` | Switch to the buffer in slot 1–10 |
| `<leader>bs1`..`<leader>bs9`, `<leader>bs0` | Swap current buffer with that slot |
| `<leader>bn` | Next file buffer |
| `<leader>bp` | Previous file buffer |
| `<leader>bl` | Show slot assignments |

> `<leader>` defaults to Space in this config.

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
wired through `require("buffer_slots")`'s exported `compare_slots` and
`slot_for`, and degrade gracefully if bufferline isn't installed.

## Development

The entry point is `lua/buffer_slots/init.lua`. After editing, restart Neovim to
reload, or run:

```vim
:lua package.loaded['buffer_slots'] = nil; require('buffer_slots').setup()
```

## References

Inside Neovim: `:help lua-guide`, `:help vim.keymap.set()`, `:help api-buffer`.