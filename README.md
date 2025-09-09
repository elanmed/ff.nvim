# `ff.nvim`

A small, fast fuzzy finder with intelligent weights.

- **Small**: ~1100 LOC, 1 source file, 1 test file
- **Fast**: Average ~20ms per keystroke on a codebase of 60k files
- **Fuzzy**: Uses `fzy-lua-native` to fuzzy match against the current input
- **Intelligent weights**: Sorts the results by weighing:
    - Frecent (frequently + recently opened) files
    - Open buffers
    - Modified buffers
    - The alternate buffer
    - The current buffer
    - The basename of the result (with and without an extension)
    - The fuzzy score of the result against the current input

## Status
- Works fine, API is not yet stable

## Performance
`ff.nvim` prioritizes performance in a few ways:

- Files are weighted and sorted in batches w/coroutines to avoid blocking the picker UI
- A max of `opts.max_results_considered` files with a fuzzy match are processed
    - Frecent files are checked first for a fuzzy match
    - For empty inputs, a max of `opts.max_results_rendered` files are processed
- Extensive caching:
    - `fd` is executed once and cached when `setup` is called
    - Frecency scores are calculated once and cached when `find` is called - not on every keystroke
    - Info on open buffers are pulled once and cached when `find` is called
    - Icons are cached by extension to avoid calling `mini.icons` when possible
    - Results are cached for each user input
- A max of `opts.max_results_rendered` results are rendered in the results window, preventing unecessary highlighting
- Icons and highlights can be disabled for especially large codebases

With these optimizations in place, I average around 20ms per keystroke on a codebase of 60k files. Enable the `benchmark_step` and `benchmark_mean` options to try yourself

## Configuration example
```lua
local ff = require "ff"
ff.setup {
  -- defaults to:
  refresh_files_cache = "setup",
  benchmark_step = false,
  benchmark_mean = false,
  fd_cmd = "fd --absolute-path --hidden --type f --exclude .git",
}

local editor_height = vim.o.lines - 1
local input_height = 1
local border_height = 2
local available_height = editor_height - input_height - (border_height * 3)
local results_height = math.floor(available_height / 2)
local input_row = editor_height
local results_row = input_row - input_height - border_height

vim.keymap.set("n", "<leader>f", function()
  ff.find {
    -- no keymaps are set by default
    keymaps = {
      i = {
        ["<cr>"] = "select",
        ["<c-n>"] = "next",
        ["<c-p>"] = "prev",
        ["<c-c>"] = "close",
        ["<esc>"] = "close",
      },
      n = {
        ["<cr>"] = "select",
        ["<c-n>"] = "next",
        ["<c-p>"] = "prev",
        ["<c-c>"] = "close",
        ["<esc>"] = "close",
        ["q"] = "close",
      },
    },
    -- defaults:
    weights = {
      open_buf_boost = 10,
      modified_buf_boost = 20,
      alternate_buf_boost = 30,
      basename_boost = 40,
      current_buf_boost = -1000,
    },
    batch_size = 250,
    icons_enabled = true,
    hi_enabled = true,
    fuzzy_score_multiple = 0.7,
    file_score_multiple = 0.3,
    max_results_considered = 1000,
    max_results_rendered = results_height * 2,
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
      height = results_height,
      row = results_row,
      col = 0,
      border = "rounded",
      title = "Results",
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
--- @field refresh_files_cache? "setup"|"find"
--- @field benchmark_step? boolean
--- @field benchmark_mean? boolean
--- @field fd_cmd? string

--- @param opts? SetupOpts
M.setup = function(opts) end
```

### `find`
```lua 
--- @class FindOpts
--- @field keymaps? FindKeymapsPerMode
--- @field weights? FindWeights
--- @field batch_size? number | false `false` to disable coroutines
--- @field hi_enabled? boolean
--- @field icons_enabled? boolean
--- @field fuzzy_score_multiple? number
--- @field file_score_multiple? number
--- @field max_results_considered? number
--- @field max_results_rendered? number
--- @field input_win_config? vim.api.keyset.win_config
--- @field results_win_config? vim.api.keyset.win_config
--- @field on_picker_open? fun(opts:OnPickerOpenOpts):nil

--- @class OnPickerOpenOpts
--- @field results_win number
--- @field results_buf number
--- @field input_win number
--- @field input_buf number

--- @class FindWeights
--- @field open_buf_boost? number
--- @field modified_buf_boost? number
--- @field alternate_buf_boost? number
--- @field current_buf_boost? number
--- @field basename_boost? number

--- @class FindKeymapsPerMode
--- @field i? FindKeymaps
--- @field n? FindKeymaps

--- @class FindKeymaps
--- @field [string] "select"|"next"|"prev"|"close"|function

--- @param opts? FindOpts
M.find = function(opts) end
```

### `refresh_files_cache`
```lua
--- @param fd_cmd string
M.refresh_files_cache = function(fd_cmd) end
```

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
- [ ] Add a small second file for lazier setups

## Features excluded for simplicity
- Multi-select
- Shared options between `setup` and `find`
- A preview window (maybe?)

## Similar plugins
- [smart-open.nvim](https://github.com/danielfalk/smart-open.nvim)
- [fff.nvim](https://github.com/dmtrKovalenko/fff.nvim)
- [snacks.nvim's smart picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md#smart)
