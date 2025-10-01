# `ff.nvim`

A small, fast fuzzy finder with intelligent weights.

- **Small**: ~1200 LOC, 1 source file, 1 test file
- **Fast**: Average ~20ms per keystroke on a codebase of 60k files
- **Fuzzy**: Uses `telescope-fzf-native.nvim` to fuzzy match against the current input
    - Allows matching with the `fzf` search [syntax](https://github.com/junegunn/fzf#search-syntax)
- **Intelligent weights**: Sorts the results by considering:
    - Open buffers
    - Modified buffers
    - The alternate buffer
    - The current buffer
    - The frecency (frequent + recently opened) score of a result
    - The basename of a result (with and without an extension)
    - The fuzzy score of a result

## Performance
`ff.nvim` prioritizes performance in a few ways:

- Files are weighted and sorted in batches w/coroutines to avoid blocking the picker UI
- New searches interrupt ongoing processing for previous searches
- A max of `vim.g.ff.max_results_considered` files with a fuzzy match are processed
    - Frecent files are checked for a fuzzy match first, then files from `fd`
    - For empty inputs, a max of `vim.g.ff.max_results_rendered` files are processed
- Extensive caching:
    - `fd` is executed once and cached when `setup()` is called
    - Frecency scores are calculated once and cached when `find()` is called
    - Info on open buffers are pulled once and cached when `find()` is called
    - Icons are cached by extension to avoid calling `mini.icons` when possible
    - Results are cached for each user input (instant backspace search)
- A max of `vim.g.ff.max_results_rendered` results are rendered in the results window, preventing unecessary highlighting
- Icons and highlights can be disabled for especially large codebases

With these optimizations in place, I average around 20ms per keystroke on a codebase of 60k files. 
Enable the `vim.g.ff.benchmark_step` and `vim.g.ff.benchmark_mean` options to try yourself

## Configuration example
```lua
-- defaults:
vim.g.ff = {
  -- "setup"|"find"
  refresh_files_cache = "setup",
  -- benchmark each keystroke
  benchmark_step = false,
  -- benchmark the mean of all keystrokes in a session
  benchmark_mean = false,
  -- defaults to use `fd`. Replace with `rg`, `find`, or another cli command of your choice
  find_cmd = "fd --absolute-path --type f",
  -- call vim.notify when a file's frecency score is updated
  notify_frecency_update = false
  weights = {
    open_buf_boost = 10,
    modified_buf_boost = 20,
    alternate_buf_boost = 30,
    basename_boost = 40,
    current_buf_boost = -1000,
  },
  -- number | false `false` to disable coroutines
  batch_size = 250,
  icons_enabled = true,
  -- highlighting the fuzzy matched characters and icons
  hl_enabled = true,
  -- how much to weight the fuzzy match score vs the frecency + other weights
  fuzzy_score_multiple = 0.7,
  -- how much to weight the frecency + other weights
  file_score_multiple = 0.3,
  -- a max of `max_results_considered` files with a fuzzy match are sorted
  max_results_considered = 1000,
  -- a max of `max_results_rendered` sorted files are rendered in the results buffer
  max_results_rendered = results_height * 2,
  -- vim.api.keyset.win_config
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
  -- vim.api.keyset.win_config
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
  -- vim.wo
  results_win_opts = {},
  -- vim.wo
  preview_win_opts = {},
  on_picker_open = function(on_picker_open_opts) end
}

local ff = require "ff"
vim.keymap.set("n", "<leader>ff", ff.find, { desc = "Fuzzy find with ff", })

vim.api.nvim_create_autocmd({ "FileType", }, {
  pattern = "ff-picker",
  callback = function()
    vim.keymap.set("i", "<cr>", "<Plug>FFResultSelect", { buffer = true, })
    vim.keymap.set("i", "<c-n>", "<Plug>FFResultNext", { buffer = true, })
    vim.keymap.set("i", "<c-p>", "<Plug>FFResultPrev", { buffer = true, })
    vim.keymap.set("i", "<esc>", "<Plug>FFClose", { buffer = true, })
    vim.keymap.set("i", "<tab>", "<Plug>FFPreviewToggle", { buffer = true, })
    vim.keymap.set("i", "<c-d>", "<Plug>FFPreviewScrollDown", { buffer = true, })
    vim.keymap.set("i", "<c-u>", "<Plug>FFPreviewScrollUp", { buffer = true, })
  end,
})
```

## API

### `setup`

```lua 
require "ff".setup()
```

By default, `setup()` is automatically on startup. This can be disabled by setting `vim.g.ff.auto_setup = false`. Note that if `auto_setup` is disabled,
`setup()` still needs to be called manually.

### `find`
```lua 
require "ff".find()
```

### `refresh_files_cache`
```lua
require "ff".refresh_files_cache()
```

By default, `refresh_files_cache()` is called once when `setup()` is run. When performing actions on the file system, 
it can be helpful to refresh the cache so the picker shows the latest files. This can be done with an autocommand like:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = {
    "MiniFilesActionCreate",
    "MiniFilesActionDelete",
    "MiniFilesActionRename",
    "MiniFilesActionCopy",
    "MiniFilesActionMove",
  },
  callback = function()
    ff.refresh_files_cache()
  end,
})
```

---

## Using another picker as a frontend for `ff.nvim`

To use another picker as a frontend for `ff.nvim`, the following functions may be useful. When calling `find()` directly, there's no need to call any of these.

```lua
vim.g.ff = {
  batch_size = false,
  max_results_rendered = 50,
}

local ff = require "ff"
ff.setup()

vim.keymap.set("n", "<leader>ff", function()
  local curr_bufname = vim.api.nvim_buf_get_name(0)
  local alternate_bufname = vim.api.nvim_buf_get_name(vim.fn.bufnr "#")

  ff.reset_benchmarks()
  ff.refresh_frecency_cache()
  ff.refresh_open_buffers_cache()

  vim.ui.input({ prompt = "ff> ", }, function(query)
    local weighted_files = ff.get_weighted_files {
      query = query or "",
      curr_bufname = curr_bufname,
      alternate_bufname = alternate_bufname,
    }
    local lines = vim.tbl_map(function(weighted_file) return weighted_file.formatted_filename end, weighted_files)

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_open_win(bufnr, true, {
      split = "right",
    })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr, })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr, })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  end)

  ff.print_mean_benchmarks()
end)
```

### `get_weighted_files`
```lua
--- @class WeightedFile
--- @field abs_path string
--- @field rel_path string
--- @field weighted_score number fuzzy_score_multiple * fuzzy_score + file_score_multiple * buf_and_frecency_score
--- @field fuzzy_score number
--- @field buf_and_frecency_score number
--- @field hl_idxs table the indexes of the `rel_path` that are fuzzy matched
--- @field icon_char string
--- @field icon_hl string
--- @field formatted_filename string

--- @class GetWeightedFilesOpts
--- @field query string
--- @field curr_bufname string absolute path of the current buffer
--- @field alternate_bufname string absolute path of the alternate buffer

--- @param opts GetWeightedFilesOpts
--- @return WeightedFile[]
require "ff".get_weighted_files(opts)
```

### `refresh_frecency_cache`
```lua
require "ff".refresh_frecency_cache()
```

### `refresh_open_buffers_cache`
```lua
require "ff".refresh_open_buffers_cache()
```

### `reset_benchmarks`
```lua
require "ff".reset_benchmarks()
```

### `print_mean_benchmarks`
```lua
require "ff".print_mean_benchmarks()
```

## Highlight Groups
- `FFPickerFuzzyHighlightChar`: The chars in a result currently fuzzy matched
  - Defaults to `Search`
- `FFPickerCursorLine`: The current line in the results window
  - Defaults to `CursorLine`

> [!NOTE]
> The default highlight groups are set as a part of the `setup()` function. In order to successfully change a highlight group, make sure to override it
_after_ calling `setup()`. This can be done either by calling `vim.api.nvim_set_hl` in the `after/plugin/` directory or in the `vim.g.ff.on_picker_open` 
function

## Plug remaps

#### `<Plug>FFResultSelect`
- Select a result, close the picker, and edit the selected file

#### `<Plug>FFResultNext`
- Move the cursor to the next result

#### `<Plug>FFResultPrev`
- Move the cursor to the prev result

#### `<Plug>FFClose`
- Close the picker

#### `<Plug>FFPreviewToggle`
- Toggle the preview for the file under the cursor

#### `<Plug>FFPreviewScrollDown`
- Scroll the preview down half a page

#### `<Plug>FFPreviewScrollUp`
- Scroll the preview up half a page

## Deps
- [`telescope-fzf-native.nvim`](https://github.com/nvim-telescope/telescope-fzf-native.nvim)
- [`mini.icons`](https://github.com/echasnovski/mini.icons) or [`nvim-web-devicons`](https://github.com/nvim-tree/nvim-web-devicons)
    - Or `false` passed as `vim.g.ff.icons_enabled`
- [`fd`](https://github.com/sharkdp/fd) 
    - Or a custom cli command passed as `vim.g.ff.find_cmd`

## TODO
- [x] Support Windows (I don't have a Windows machine to test this on, but it should work)

## Features excluded for simplicity
- Multi-select

## Similar plugins
- [smart-open.nvim](https://github.com/danielfalk/smart-open.nvim)
- [fff.nvim](https://github.com/dmtrKovalenko/fff.nvim)
- [snacks.nvim's smart picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md#smart)
