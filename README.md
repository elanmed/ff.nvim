# `ff.nvim`

A small, simple fuzzy finder with intelligent weights.

- **Small**: ~1000 LOC,
- **Simple**: 1 source file, 1 test file
- **Fuzzy**: Uses `fzy-lua-native` to fuzzy match against the current input
- **Intelligent weights**: Sorts the results by weighing:
    - Frecent (frequently + recently opened) files
    - Open buffers
    - Modified buffers
    - The alternate buffer
    - The current buffer
    - The fuzzy score of the filename against the current input

## Example
```lua
local ff = require "ff"
ff.setup {
  -- defaults to:
  refresh_fd_cache = "module-load",
  refresh_frecency_scores_cache = "find-call",
  refresh_open_buffers_cache = "find-call",
  benchmark = false,
  fd_cmd = "fd --absolute-path --hidden --type f --exclude .git",
}

local editor_height = vim.o.lines - 1
local input_height = 1
local border_height = 2
local available_height = editor_height - input_height - (border_height * 3)
local results_preview_height = math.floor(available_height / 2)
local input_row = editor_height
local results_row = input_row - input_height - border_height
local preview_row = results_row - results_preview_height - border_height

vim.keymap.set("n", "<leader>f", function()
  ff.find {
    -- no keymaps are set by default
    keymaps = {
      n = {
        ["<cr>"] = "select",
        ["<c-n>"] = "next",
        ["<c-p>"] = "prev",
        ["<c-c>"] = "close",
        ["<esc>"] = "close",
        ["<c-d>"] = "scroll_preview_down",
        ["<c-u>"] = "scroll_preview_up",

        ["q"] = "close",
      },
      i = {
        ["<cr>"] = "select",
        ["<c-n>"] = "next",
        ["<c-p>"] = "prev",
        ["<c-c>"] = "close",
        ["<esc>"] = "close",
        ["<c-d>"] = "scroll_preview_down",
        ["<c-u>"] = "scroll_preview_up",
      },
    },
    -- defaults:
    weights = {
      open_buf_boost = 10,
      modified_buf_boost = 20,
      alternate_buf_boost = 30,
      current_buf_boost = -1000,
    },
    batch_size = 250,
    icons_enabled = true,
    hi_enabled = true,
    preview_enabled = true,
    max_results = 200,
    fuzzy_score_multiple = 0.7,
    file_score_multiple = 0.3,

    input_win_config = {
      style = "minimal",
      anchor = "SW",
      relative = "editor",
      width = vim.o.columns,
      height = 1,
      row = input_row,
      col = 0,
      border = "rounded",
      title = "Input",
    },
    results_win_config = {
      style = "minimal",
      anchor = "SW",
      relative = "editor",
      width = vim.o.columns,
      height = results_preview_height,
      row = results_row,
      col = 0,
      border = "rounded",
      title = "Results",
      focusable = false,
    },
    preview_win_config = {
      style = "minimal",
      anchor = "SW",
      relative = "editor",
      width = vim.o.columns,
      height = results_preview_height,
      row = preview_row,
      col = 0,
      border = "rounded",
      title = "Preview",
      focusable = false,
    },
    on_picker_open = function(on_picker_open_opts) end
  }
end)
```

## API

### `setup`
```lua 
--- @class SetupOpts
--- @field refresh_fd_cache "module-load"|"find-call"
--- @field refresh_frecency_scores_cache "module-load"|"find-call"
--- @field refresh_open_buffers_cache "module-load"|"find-call"
--- @field benchmark boolean
--- @field fd_cmd string

--- @param opts? SetupOpts
M.setup = function(opts) end
```

### `find`
```lua 
--- @class FindOpts
--- @field keymaps FindKeymapsPerMode
--- @field weights FindWeights
--- @field batch_size number
--- @field icons_enabled boolean
--- @field hi_enabled boolean
--- @field preview_enabled boolean
--- @field max_results number
--- @field fuzzy_score_multiple number
--- @field file_score_multiple number
--- @field input_win_config vim.api.keyset.win_config
--- @field results_win_config vim.api.keyset.win_config
--- @field preview_win_config vim.api.keyset.win_config
--- @field on_picker_open fun(opts:OnPickerOpenOpts):nil

--- @class OnPickerOpenOpts
--- @field results_win number
--- @field results_buf number
--- @field input_win number
--- @field input_buf number
--- @field preview_win number
--- @field preview_buf number

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

## Performance
`ff.nvim` prioritizes performance in a few ways:

- Files are weighted and sorted in batches w/coroutines to avoid blocking the picker UI
- `fd` calls are executed once and cached when the plugin first loads
- Frecency scores are calculated once and cached when the picker is opened - not on every keystroke
- Open buffers are pulled once and cached when the picker is opened
- Icons are cached by extension to avoid calling `mini.icons` when possible
- Results are capped to keep the picker buffer small
- Icons, highlights, and previews can be disabled for especially large codebases

With these optimizations in place, I average around ~50ms per keystroke on a codebase of 30k files. Enable the `benchmark` option to try it for yourself.

## Highlight Groups
- `FFPickerFuzzyHighlightChar`: The chars in a result currently fuzzy matched
  - Defaults to `Search`
- `FFPickerCursorLine`: The current line in the results window
  - Defaults to `CursorLine`

> [!NOTE]
> The default highlight groups are set as a part of the `setup` function. In order to successfully override a highlight group, make sure to set it
after calling`setup`

## Deps
- [fzy-lua-native](https://github.com/romgrk/fzy-lua-native)
- [mini.icons](https://github.com/echasnovski/mini.icons)
- [`fd`](https://github.com/sharkdp/fd)

## TODO
- [ ] Support alternatives to `mini.icons`
- [ ] Support alternatives to `fd`
- [ ] Support Windows

## Features excluded for simplicity
- Multi-select
- Shared options between `setup` and `find`

## Similar plugins
- [smart-open.nvim](https://github.com/danielfalk/smart-open.nvim)
- [fff.nvim](https://github.com/dmtrKovalenko/fff.nvim)
- [snacks.nvim's smart picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md#smart)
