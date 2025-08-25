# `ff.nvim`

A small, simple fuzzy finder with intelligent weights.

Sorts the results by weighing:
- The fuzzy score of the current input
- Frecent (frequently + recently opened) files
- Open buffers
- Modified buffers
- The alternate buffer
- The current buffer

## Example
```lua
local ff = require "ff"
ff.setup {
  -- defaults to:
  refresh_fd_cache = "module-load",
  refresh_frecency_scores_cache = "find-call",
  refresh_open_buffers_cache = "find-call"
}

vim.keymap.set("n", "<leader>f", function()
  ff.find {
    -- no keymaps are set by default
    keymaps = {
      n = {
        ["<cr>"] = "select",
        ["<c-n>"] = "next",
        ["<c-p>"] = "prev",
        ["<c-c>"] = "close",

        ["<leader>q"] = "close",
        ["<esc>"] = "close",
      },
      i = {
        ["<cr>"] = "select",
        ["<c-n>"] = "next",
        ["<c-p>"] = "prev",
        ["<c-c>"] = "close",
      },
    },
    -- defaults to:
    weights = {
      open_buf_boost = 10,
      modified_buf_boost = 20,
      alternate_buf_boost = 30,
      current_buf_boost = -1000,
    }
    -- defaults to:
    batch_size = 250,
    -- defaults to:
    icons_enabled = true,
    -- defaults to:
    hl_enabled = true,
  }
end)
```

## API

### `setup`
```lua 
--- @class FFSetupOpts
--- @field refresh_fd_cache "module-load"|"find-call"
--- @field refresh_frecency_scores_cache "module-load"|"find-call"
--- @field refresh_open_buffers_cache "module-load"|"find-call"

--- @param opts? FFSetupOpts
M.setup = function(opts) end
```

### `find`
```lua 
--- @class FindOpts
--- @field keymaps FindKeymapsPerMode
--- @field weights FindWeights
--- @field batch_size number
--- @field icons_enabled boolean
--- @field hl_enabled boolean

--- @class FindWeights
--- @field open_buf_boost number
--- @field modified_buf_boost number
--- @field alternate_buf_boost number
--- @field current_buf_boost number

--- @class FindKeymapsPerMode
--- @field i FindKeymaps
--- @field n FindKeymaps

--- @class FindKeymaps
--- @field [string] "select"|"next"|"prev"|"close"|function

--- @param opts? FindOpts
M.find = function(opts) end
```

## Deps
- [fzy-lua-native](https://github.com/romgrk/fzy-lua-native)
- [mini.icons](https://github.com/echasnovski/mini.icons)
- [`fd`](https://github.com/sharkdp/fd)

## TODO
- [x] Modularize within single file
- [ ] Configuration options
    - [x] Remaps (multiple per action?)
    - [x] Weights
    - [ ] Horizontal, vertical
- [ ] Enable global search
- [x] Remove dep on `fzf-lua-frecency`
- [ ] Support `nvim-web-devicons`
- [ ] Support a floating buffer?
- [ ] Support alternatives to `fd`
- [ ] Support Windows
- [ ] Healthcheck
- [x] Set up autocommand
- [ ] Remove `|`

## Features excluded for simplicity
- Multi-select

## Similar plugins
- [smart-open.nvim](https://github.com/danielfalk/smart-open.nvim)
- [fff.nvim](https://github.com/dmtrKovalenko/fff.nvim)
- [snacks.nvim's smart picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md#smart)
