local M = {}

-- ======================================================
-- == Misc helpers ======================================
-- ======================================================

local H = {}
H.cwd = vim.uv.cwd()

--- @generic T
--- @param val T | nil
--- @param default_val T
--- @return T
H.default = function(val, default_val)
  if val == nil then
    return default_val
  end
  return val
end

--- @param abs_path string
H.rel_path = function(abs_path)
  --- @type string
  if not vim.startswith(abs_path, H.cwd) then return abs_path end
  return abs_path:sub(#H.cwd + 2)
end

--- @param path string
--- @param opts { with_ext: boolean }
H.basename = function(path, opts)
  --- @type string
  local basename = vim.fs.basename(path)
  if opts.with_ext then return basename end

  local first_dot_pos = basename:find "%."
  if first_dot_pos and first_dot_pos > 1 then
    return basename:sub(1, first_dot_pos - 1)
  end
  return basename
end

--- @param abs_path string
H.get_ext = function(abs_path)
  local last_dot_pos = abs_path:find "%.[^.]*$"
  if last_dot_pos and last_dot_pos > 1 then
    return abs_path:sub(last_dot_pos + 1)
  end
  return nil
end

--- @param str string
--- @param len number
H.pad_str = function(str, len)
  if #str >= len then
    return tostring(str)
  end
  local num_spaces = len - #str
  return string.rep(" ", num_spaces) .. str
end

--- @param num number
--- @param decimals number
H.max_decimals = function(num, decimals)
  local factor = 10 ^ decimals
  return math.floor(num * factor) / factor
end

--- @param num number
--- @param decimals number
H.min_decimals = function(num, decimals)
  return string.format("%." .. tostring(decimals) .. "f", num)
end

--- @param num number
--- @param decimals number
H.exact_decimals = function(num, decimals)
  return H.min_decimals(H.max_decimals(num, decimals), decimals)
end

--- @param num number
--- @param max_len number
H.fit_decimals = function(num, max_len)
  local two_decimals = H.exact_decimals(num, 2)

  if #two_decimals <= max_len then
    return two_decimals
  end

  local one_decimal = H.exact_decimals(num, 1)
  if #one_decimal <= max_len then
    return one_decimal
  end

  local no_decimals = H.exact_decimals(num, 0)
  return no_decimals
end

H.vimscript_true = 1
H.vimscript_false = 0

--- @param abs_path string
H.readable = function(abs_path)
  local stat_result = vim.uv.fs_stat(abs_path)
  return stat_result ~= nil and stat_result.type == "file"
end

-- ======================================================
-- == Frecency ==========================================
-- ======================================================

local F = {}
F.default_db_dir = vim.fs.joinpath(vim.fn.stdpath "data", "ff")

--- @param db_dir? string
F.get_dated_files_path = function(db_dir)
  db_dir = H.default(db_dir, F.default_db_dir)
  return vim.fs.joinpath(db_dir, "dated-files.json")
end

--- @param path string
F.read = function(path)
  local file = io.open(path, "r")
  if file == nil then
    return {}
  end

  local encoded_data = file:read "*a"
  file:close()

  local decoded_data = vim.json.decode(encoded_data)
  return decoded_data
end

--- @param path string
--- @param data table
--- @return nil
F.write = function(path, data)
  local path_dir = vim.fs.dirname(path)
  local mkdir_res = vim.fn.mkdir(path_dir, "p")
  if mkdir_res == H.vimscript_false then
    vim.notify("[ff.nvim]: vim.fn.mkdir returned vimscript_false", vim.log.levels.ERROR)
    return
  end

  local file = io.open(path, "w")
  if file == nil then
    vim.notify("[ff.nvim]: io.open failed to open the file created with vim.fn.mkdir", vim.log.levels.ERROR)
    return
  end

  local encoded_data = vim.json.encode(data)
  file:write(encoded_data)
  file:close()
end

F.half_life_sec = 30 * 24 * 60 * 60
F.decay_rate = math.log(2) / F.half_life_sec

F._now = function()
  return os.time()
end

--- @class ComputeScore
--- @field date_at_score_one number an os.time date. the date in seconds when the score decays to 1
--- @field now number an os.time date

--- @param opts ComputeScore
F.compute_score = function(opts)
  return math.exp(F.decay_rate * (opts.date_at_score_one - opts.now))
end

--- @class ComputeDateAtScoreOne
--- @field score number
--- @field now number an os.time date

--- @param opts ComputeDateAtScoreOne
F.compute_date_at_score_one = function(opts)
  return opts.now + math.log(opts.score) / F.decay_rate
end

--- @class UpdateFileScoreOpts
--- @field update_type "increase" | "remove"
--- @field _db_dir? string

--- @param abs_path string
--- @param opts UpdateFileScoreOpts
F.update_file_score = function(abs_path, opts)
  local now = F._now()

  opts._db_dir = H.default(opts._db_dir, F.default_db_dir)
  local dated_files_path = F.get_dated_files_path(opts._db_dir)
  local dated_files = F.read(dated_files_path)
  if dated_files[H.cwd] == nil then
    dated_files[H.cwd] = {}
  end

  local updated_date_at_score_one = (function()
    if opts.update_type == "increase" then
      if not H.readable(abs_path) then
        return nil
      end

      local score = 0
      local date_at_score_one = dated_files[H.cwd][abs_path]
      if date_at_score_one then
        score = F.compute_score { now = now, date_at_score_one = date_at_score_one, }
      end
      local updated_score = score + 1

      return F.compute_date_at_score_one { now = now, score = updated_score, }
    end

    return nil
  end)()

  dated_files[H.cwd][abs_path] = updated_date_at_score_one

  local readable_dated_files_cwd = {}
  for dated_file, date_at_score_one in pairs(dated_files[H.cwd]) do
    if H.readable(dated_file) then
      readable_dated_files_cwd[dated_file] = date_at_score_one
    end
  end

  dated_files[H.cwd] = readable_dated_files_cwd
  F.write(dated_files_path, dated_files)
end

-- ======================================================
-- == Benchmarking ======================================
-- ======================================================

local L = {}

--- @param content string
L.log = function(content)
  local file = io.open("ff.log", "a")
  if file == nil then
    vim.notify("[ff.nvim]: opening `ff.log` failed", vim.log.levels.ERROR)
    return
  end
  file:write(content .. "\n")
  file:close()
end

L.LOG_LEN = 100

--- @param content string
L.log_content = function(content)
  L.log("│" .. content .. (" "):rep(L.LOG_LEN - #content - 2) .. "│")
end

--- @param type "start"|"middle"|"end"
L.log_line = function(type)
  local content = ("─"):rep(L.LOG_LEN - 2)
  if type == "start" then
    L.log("┌" .. content .. (" "):rep(L.LOG_LEN - #content) .. "┐")
  elseif type == "middle" then
    L.log("├" .. content .. (" "):rep(L.LOG_LEN - #content) .. "┤")
  elseif type == "end" then
    L.log("└" .. content .. (" "):rep(L.LOG_LEN - #content) .. "┘")
  end
end

L.should_log_step = function()
  local opts = H.default(vim.g.ff, {})
  return H.default(opts.benchmark_step, false)
end

L.should_log_mean = function()
  local opts = H.default(vim.g.ff, {})
  return H.default(opts.benchmark_mean, false)
end


--- @param get_flag function
L.create_benchmark_heading = function(get_flag)
  --- @param content string
  return function(content)
    if not get_flag() then return end
    L.log_line "start"
    L.log_content(content)
    L.log_line "middle"
  end
end

L.benchmark_step_heading = L.create_benchmark_heading(L.should_log_step)
L.benchmark_mean_heading = L.create_benchmark_heading(L.should_log_mean)

--- @param get_flag function
L.create_benchmark_closing = function(get_flag)
  return function()
    if not get_flag() then return end
    L.log_line "end"
  end
end

L.benchmark_step_closing = L.create_benchmark_closing(L.should_log_step)
L.benchmark_mean_closing = L.create_benchmark_closing(L.should_log_mean)

L.benchmark_step_interrupted = function()
  if not L.should_log_step() then return end
  L.log_content "INTERRUPTED"
end

--- @type table<string, number>
L.ongoing_benchmarks = {}

--- @type table<string, number[]>
L.benchmarks_for_mean = {}

--- @param type "start"|"end"
--- @param label string
--- @param opts? {record_mean: boolean, print_step: boolean}
L.benchmark_step = function(type, label, opts)
  opts = H.default(opts, {})
  opts.record_mean = H.default(opts.record_mean, true)
  opts.print_step = H.default(opts.print_step, true)

  if type == "start" then
    L.ongoing_benchmarks[label] = os.clock()
  else
    local end_time = os.clock()
    local start_time = L.ongoing_benchmarks[label]

    local elapsed_ms = (end_time - start_time) * 1000
    local formatted_ms = H.pad_str(H.exact_decimals(elapsed_ms, 3), 8)

    if L.should_log_mean() and opts.record_mean then
      if L.benchmarks_for_mean[label] == nil then
        L.benchmarks_for_mean[label] = {}
      end
      table.insert(L.benchmarks_for_mean[label], elapsed_ms)
    end

    if L.should_log_step() and opts.print_step then
      local content = ("% sms : %s"):format(formatted_ms, label)
      L.log("│" .. content .. (" "):rep(L.LOG_LEN - #content - 2) .. "│")
    end
  end
end

-- ======================================================
-- == Picker ============================================
-- ======================================================

local P = {}

P.tick = 0
P.preview_active = false
P.ns_id = vim.api.nvim_create_namespace "FFPicker"

P.MAX_FRECENCY_SCORE = 99 -- approx the largest reasonable frecency score
P.MAX_SCORE_LEN = #H.exact_decimals(P.MAX_FRECENCY_SCORE, 2)

--- @class FFOpts
--- @field weights? Weights
--- @field batch_size? number | false
--- @field hl_enabled? boolean
--- @field icons_enabled? boolean
--- @field max_results_considered? number
--- @field max_results_rendered? number
--- @field fuzzy_score_multiple? number
--- @field file_score_multiple? number
--- @field input_win_config? vim.api.keyset.win_config
--- @field results_win_config? vim.api.keyset.win_config
--- @field results_win_opts? vim.wo
--- @field preview_win_opts? vim.wo
--- @field on_picker_open? fun(opts:OnPickerOpenOpts):nil
--- @field refresh_files_cache? "setup"|"find"
--- @field benchmark_step? boolean
--- @field benchmark_mean? boolean
--- @field find_cmd? string
--- @field notify_frecency_update? boolean

--- @class OnPickerOpenOpts
--- @field results_win number
--- @field results_buf number
--- @field input_win number
--- @field input_buf number

--- @class Weights
--- @field open_buf_boost? number
--- @field modified_buf_boost? number
--- @field alternate_buf_boost? number
--- @field current_buf_boost? number
--- @field basename_boost? number

--- @return FFOpts
P.defaulted_gopts = function()
  L.benchmark_step("start", "defaulted_gopts")

  local opts = H.default(vim.g.ff, {})
  opts = vim.deepcopy(opts)

  opts.weights = H.default(opts.weights, {})
  opts.weights.open_buf_boost = H.default(opts.weights.open_buf_boost, 10)
  opts.weights.modified_buf_boost = H.default(opts.weights.modified_buf_boost, 20)
  opts.weights.alternate_buf_boost = H.default(opts.weights.alternate_buf_boost, 30)
  opts.weights.basename_boost = H.default(opts.weights.basename_boost, 40)
  opts.weights.current_buf_boost = H.default(opts.weights.current_buf_boost, -1000)

  opts.batch_size = H.default(opts.batch_size, 250)
  opts.hl_enabled = H.default(opts.hl_enabled, true)
  opts.icons_enabled = H.default(opts.icons_enabled, true)
  opts.max_results_considered = H.default(opts.max_results_considered, 1000)
  opts.fuzzy_score_multiple = H.default(opts.fuzzy_score_multiple, 0.7)
  opts.file_score_multiple = H.default(opts.file_score_multiple, 0.3)
  opts.on_picker_open = H.default(opts.on_picker_open, function() end)

  opts.results_win_opts = H.default(opts.results_win_opts, {})
  opts.preview_win_opts = H.default(opts.preview_win_opts, {})

  local editor_height = vim.o.lines
  local input_height = 1
  local border_height = 1
  local results_height = math.floor(editor_height / 2)
  local input_row = editor_height
  local results_row = input_row - input_height - (border_height * 2) - 1

  opts.max_results_rendered = H.default(opts.max_results_rendered, results_height * 2)
  opts.input_win_config = H.default(opts.input_win_config, {
    style = "minimal",
    anchor = "SW",
    relative = "editor",
    width = vim.o.columns,
    height = 1,
    row = input_row,
    col = 0,
    border = "rounded",
    title = "Input",
  })
  opts.results_win_config = H.default(opts.results_win_config, {
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
  })

  opts.benchmark_step = H.default(opts.benchmark_step, false)
  opts.benchmark_mean = H.default(opts.benchmark_mean, false)
  opts.find_cmd = H.default(opts.find_cmd, "fd --absolute-path --type f")
  opts.refresh_files_cache = H.default(opts.refresh_files_cache, "setup")
  opts.notify_frecency_update = H.default(opts.notify_frecency_update, false)

  L.benchmark_step("end", "defaulted_gopts", { print_step = false, })
  return opts
end

--- @param abs_path string
--- @param score number
--- @param icon_char string|nil
P.format_filename = function(abs_path, score, icon_char)
  local formatted_score = H.pad_str(
    H.fit_decimals(score, P.MAX_SCORE_LEN),
    P.MAX_SCORE_LEN
  )
  local formatted_icon_char = icon_char and icon_char .. " " or ""
  local rel_path = H.rel_path(abs_path)
  return ("%s %s|%s"):format(
    formatted_score,
    formatted_icon_char,
    rel_path
  )
end

--- @param fuzzy_score number
--- @param query string
P.scale_fzf_to_frecency = function(fuzzy_score, query)
  local max_fzf_score = 8 + 24 * #query
  return fuzzy_score / max_fzf_score * P.MAX_FRECENCY_SCORE
end

P.caches = {
  --- @type string[]
  find_files = {},

  --- @type string[]
  frecency_files = {},

  --- @type table<string, number>
  frecency_file_to_score = {},

  --- @type table<string, {icon_char: string, icon_hl: string|nil}>
  icon_cache = {},

  --- @type table<string, boolean>
  open_buffer_to_modified = {},

  --- @type table<string, WeightedFile[]>
  weighted_files_per_query = {},
}

P.refresh_files_cache = function()
  L.benchmark_step_heading "refresh_files_cache"
  L.benchmark_step("start", "refresh_files_cache (entire function)")
  local gopts = P.defaulted_gopts()
  local find_cmd_tbl = vim.split(gopts.find_cmd, " ")
  vim.system(find_cmd_tbl, { text = true, }, function(obj)
    P.caches.find_files = {}
    local lines = vim.split(obj.stdout, "\n")
    for _, abs_path in ipairs(lines) do
      L.benchmark_step("start", "refresh_files_cache (loop iteration)")
      if #abs_path == 0 then goto continue end
      table.insert(P.caches.find_files, vim.fs.normalize(abs_path))

      ::continue::
      L.benchmark_step("end", "refresh_files_cache (loop iteration)", { print_step = false, })
    end
    L.benchmark_step("end", "refresh_files_cache (entire function)", { record_mean = false, })
    L.benchmark_step_closing()
  end)
end

M.refresh_frecency_cache = function()
  L.benchmark_step_heading "refresh_frecency_cache"
  P.caches.frecency_files = {}
  P.caches.frecency_file_to_score = {}

  L.benchmark_step("start", "dated_files file read")
  local dated_files_path = F.get_dated_files_path()
  local dated_files = F.read(dated_files_path)
  if dated_files[H.cwd] == nil then
    dated_files[H.cwd] = {}
  end
  L.benchmark_step("end", "dated_files file read", { record_mean = false, })

  local now = os.time()
  L.benchmark_step("start", "Calculate frecency_file_to_score (entire loop)")
  for abs_path, date_at_score_one in pairs(dated_files[H.cwd]) do
    local score
    L.benchmark_step("start", "Calculate frecency_file_to_score (loop iteration)")

    if not H.readable(abs_path) then goto continue end
    score = F.compute_score { now = now, date_at_score_one = date_at_score_one, }
    P.caches.frecency_file_to_score[abs_path] = score
    table.insert(P.caches.frecency_files, abs_path)

    ::continue::
    L.benchmark_step("end", "Calculate frecency_file_to_score (loop iteration)", { print_step = false, })
  end
  L.benchmark_step("end", "Calculate frecency_file_to_score (entire loop)", { record_mean = false, })
  L.benchmark_step_closing()
end

M.refresh_open_buffers_cache = function()
  P.caches.weighted_files_per_query = {}
  P.caches.open_buffer_to_modified = {}

  L.benchmark_step_heading "refresh_open_buffers_cache"
  L.benchmark_step("start", "Calculate open_buffer_to_modified (entire loop)")
  for _, bufnr in pairs(vim.api.nvim_list_bufs()) do
    local buf_name = nil
    local modified = nil
    L.benchmark_step("start", "Calculate open_buffer_to_modified (loop iteration)")

    if not vim.api.nvim_buf_is_loaded(bufnr) then goto continue end
    if not vim.api.nvim_get_option_value("buflisted", { buf = bufnr, }) then goto continue end
    buf_name = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
    if buf_name == "" then goto continue end
    if not vim.startswith(buf_name, H.cwd) then goto continue end

    modified = vim.api.nvim_get_option_value("modified", { buf = bufnr, })
    P.caches.open_buffer_to_modified[buf_name] = modified

    ::continue::
    L.benchmark_step("end", "Calculate open_buffer_to_modified (loop iteration)", { print_step = false, })
  end
  L.benchmark_step("end", "Calculate open_buffer_to_modified (entire loop)", { record_mean = false, })
  L.benchmark_step_closing()
end

--- @class WeightedFile
--- @field abs_path string
--- @field rel_path string
--- @field weighted_score number
--- @field fuzzy_score number
--- @field buf_and_frecency_score number
--- @field hl_idxs table
--- @field icon_char string
--- @field icon_hl string
--- @field formatted_filename string

--- @class GetIconInfoOpts
--- @field abs_path string
--- @field icons_enabled boolean
--- @param opts GetIconInfoOpts
P.get_icon_info = function(opts)
  if not opts.icons_enabled then
    return {
      icon_char = nil,
      icon_hl = nil,
    }
  end

  local ext = H.get_ext(opts.abs_path)
  if ext and P.caches.icon_cache[ext] then
    return {
      icon_char = P.caches.icon_cache[ext].icon_char,
      icon_hl = P.caches.icon_cache[ext].icon_hl,
    }
  end

  local icon_library = (function()
    local devicons_ok, devicons = pcall(require, "nvim-web-devicons")
    if devicons_ok then return devicons end

    local mini_icons_ok, mini_icons = pcall(require, "mini.icons")
    if mini_icons_ok then
      return {
        get_icon = function(path)
          return mini_icons.get("file", path)
        end,
      }
    end

    return nil
  end)()

  if icon_library == nil then
    return {
      icon_char = "?",
      icon_hl = nil,
    }
  end

  local icon_char, icon_hl = icon_library.get_icon(opts.abs_path)
  if ext then
    P.caches.icon_cache[ext] = { icon_char = icon_char, icon_hl = icon_hl, }
  end

  return {
    icon_char = icon_char,
    icon_hl = icon_hl,
  }
end

--- @class GetWeightedFilesOpts
--- @field query string
--- @field curr_bufname string
--- @field alternate_bufname string
--- @param opts GetWeightedFilesOpts
M.get_weighted_files = function(opts)
  L.benchmark_step_heading(("Get weighted files for query: '%s'"):format(opts.query))
  H.cwd = vim.uv.cwd()

  local gopts = P.defaulted_gopts()

  if P.caches.weighted_files_per_query[opts.query] then
    return P.caches.weighted_files_per_query[opts.query]
  end

  local fzf = require "fzf_lib"
  local slab = fzf.allocate_slab()

  --- @type WeightedFile[]
  local weighted_files_for_query = {}

  --- @param abs_path string
  local function get_weighted_file(abs_path, slab_arg)
    local rel_path = H.rel_path(abs_path)
    if #opts.query == 0 then
      local icon_info = P.get_icon_info { abs_path = abs_path, icons_enabled = gopts.icons_enabled, }

      local frecency_score = 0
      if P.caches.frecency_file_to_score[abs_path] ~= nil then
        frecency_score = P.caches.frecency_file_to_score[abs_path]
      end
      return {
        abs_path = abs_path,
        rel_path = rel_path,
        weighted_score = frecency_score,
        buf_and_frecency_score = 0,
        fuzzy_score = 0,
        hl_idxs = {},
        icon_hl = icon_info.icon_hl,
        icon_char = icon_info.icon_char,
        formatted_filename = P.format_filename(abs_path, frecency_score, icon_info.icon_char),
      }
    end

    L.benchmark_step("start", "get_weighted_file: fzf.parse_pattern and fzf.get_score")
    local smart_case_mode = 0
    local pattern_obj = fzf.parse_pattern(opts.query, smart_case_mode)
    local fzf_score = fzf.get_score(rel_path, pattern_obj, slab_arg)
    L.benchmark_step("end", "get_weighted_file: fzf.parse_pattern and fzf.get_score", { print_step = false, })

    if fzf_score == 0 then
      fzf.free_pattern(pattern_obj)
      return nil
    end

    local buf_score = 0
    local basename_with_ext = H.basename(abs_path, { with_ext = true, })
    local basename_without_ext = H.basename(abs_path, { with_ext = false, })

    if opts.query == basename_with_ext or opts.query == basename_without_ext then
      buf_score = gopts.weights.basename_boost
    elseif P.caches.open_buffer_to_modified[abs_path] ~= nil then
      local modified = P.caches.open_buffer_to_modified[abs_path]

      if abs_path == opts.curr_bufname then
        buf_score = gopts.weights.current_buf_boost
      elseif abs_path == opts.alternate_bufname then
        buf_score = gopts.weights.alternate_buf_boost
      elseif modified then
        buf_score = gopts.weights.modified_buf_boost
      else
        buf_score = gopts.weights.open_buf_boost
      end
    end

    local buf_and_frecency_score = buf_score
    if P.caches.frecency_file_to_score[abs_path] ~= nil then
      buf_and_frecency_score = buf_and_frecency_score + P.caches.frecency_file_to_score[abs_path]
    end

    local scaled_fzf_score = P.scale_fzf_to_frecency(fzf_score, opts.query)
    local weighted_score =
        gopts.fuzzy_score_multiple * scaled_fzf_score +
        gopts.file_score_multiple * buf_and_frecency_score

    L.benchmark_step("start", "get_weighted_file: get_icon_info (populated query)")
    local icon_info = P.get_icon_info { abs_path = abs_path, icons_enabled = gopts.icons_enabled, }
    L.benchmark_step("end", "get_weighted_file: get_icon_info (populated query)", { print_step = false, })
    local hl_idxs = {}
    if gopts.hl_enabled then
      local pos = fzf.get_pos(rel_path, pattern_obj, slab_arg)
      if pos then hl_idxs = pos end
    end

    fzf.free_pattern(pattern_obj)
    return {
      abs_path = abs_path,
      rel_path = rel_path,
      weighted_score = weighted_score,
      fuzzy_score = scaled_fzf_score,
      buf_and_frecency_score = buf_and_frecency_score,
      hl_idxs = hl_idxs,
      icon_hl = icon_info.icon_hl,
      icon_char = icon_info.icon_char,
      formatted_filename = P.format_filename(abs_path, weighted_score, icon_info.icon_char),
    }
  end

  local max_results = (function()
    if opts.query == "" then
      return gopts.max_results_rendered
    end
    return gopts.max_results_considered
  end)()

  L.benchmark_step("start", "Populate weighted files with frecency (entire loop)")
  for idx, abs_path in pairs(P.caches.frecency_files) do
    if #weighted_files_for_query >= max_results then break end

    L.benchmark_step("start", "Populate weighted files with frecency (loop iteration)")
    local weighted_file = get_weighted_file(abs_path, slab)
    if weighted_file then
      table.insert(weighted_files_for_query, weighted_file)
    end
    L.benchmark_step("end", "Populate weighted files with frecency (loop iteration)", { print_step = false, })

    if gopts.batch_size and idx % gopts.batch_size == 0 then
      coroutine.yield()
    end
  end
  L.benchmark_step("end", "Populate weighted files with frecency (entire loop)")

  L.benchmark_step("start", "Populate weighted files with fd (entire loop)")
  for idx, abs_path in ipairs(P.caches.find_files) do
    if #weighted_files_for_query >= max_results then break end
    if P.caches.frecency_file_to_score[abs_path] ~= nil then
      goto continue
    end

    L.benchmark_step("start", "Populate weighted files with fd (loop iteration)")
    local weighted_file = get_weighted_file(abs_path, slab)
    L.benchmark_step("end", "Populate weighted files with fd (loop iteration)", { print_step = false, })
    if weighted_file then
      table.insert(weighted_files_for_query, weighted_file)
    end

    if gopts.batch_size and idx % gopts.batch_size == 0 then
      coroutine.yield()
    end

    ::continue::
  end
  L.benchmark_step("end", "Populate weighted files with fd (entire loop)")

  fzf.free_slab(slab)

  L.benchmark_step("start", "Sort weighted files")
  table.sort(weighted_files_for_query, function(a, b)
    return a.weighted_score > b.weighted_score
  end)
  L.benchmark_step("end", "Sort weighted files")
  L.benchmark_step_closing()

  P.caches.weighted_files_per_query[opts.query] = weighted_files_for_query
  return weighted_files_for_query
end

--- @class HighlightWeightedFilesOpts
--- @field weighted_files WeightedFile[]
--- @field results_buf number
--- @param opts HighlightWeightedFilesOpts
P.highlight_weighted_files = function(opts)
  local gopts = P.defaulted_gopts()
  local formatted_score_last_idx = #H.pad_str(
    H.fit_decimals(P.MAX_FRECENCY_SCORE, P.MAX_SCORE_LEN),
    P.MAX_SCORE_LEN
  )
  local icon_char_idx = formatted_score_last_idx + 2

  L.benchmark_step("start", "Highlight results")
  for idx, weighted_file in ipairs(opts.weighted_files) do
    if idx > gopts.max_results_rendered then break end
    local row_0_indexed = idx - 1

    if weighted_file.icon_hl then
      local icon_hl_col_1_indexed = icon_char_idx
      local icon_hl_col_0_indexed = icon_hl_col_1_indexed - 1

      L.benchmark_step("start", "highlight_weighted_files icon vim.hl.range")
      vim.hl.range(
        opts.results_buf,
        P.ns_id,
        weighted_file.icon_hl,
        { row_0_indexed, icon_hl_col_0_indexed, },
        { row_0_indexed, icon_hl_col_0_indexed + 1, }
      )
      L.benchmark_step("end", "highlight_weighted_files icon vim.hl.range", { print_step = false, })
    end

    local file_offset = weighted_file.formatted_filename:find "|"
    L.benchmark_step("start", "highlight_weighted_files highlight hl_idxs (entire loop)")
    for _, hl_idx in ipairs(weighted_file.hl_idxs) do
      local file_char_hl_col_0_indexed = hl_idx + file_offset - 1

      L.benchmark_step("start", "highlight_weighted_files highlight hl_idxs (loop iteration)")
      vim.hl.range(
        opts.results_buf,
        P.ns_id,
        "FFPickerFuzzyHighlightChar",
        { row_0_indexed, file_char_hl_col_0_indexed, },
        { row_0_indexed, file_char_hl_col_0_indexed + 1, }
      )
      L.benchmark_step("end", "highlight_weighted_files highlight hl_idxs (loop iteration)", { print_step = false, })
    end
    L.benchmark_step("end", "highlight_weighted_files highlight hl_idxs (entire loop)", { print_step = false, })

    if gopts.batch_size and idx % gopts.batch_size == 0 then
      coroutine.yield()
    end
  end
  L.benchmark_step("end", "Highlight results")
end

--- @class GetFindFilesOpts
--- @field query string
--- @field results_buf number
--- @field curr_bufname string
--- @field alternate_bufname string
--- @field curr_tick number
--- @field render_results fun(weighted_files:WeightedFile[]):nil

--- @param opts GetFindFilesOpts
P.get_find_files = function(opts)
  L.benchmark_step("start", "Total per keystroke")

  local gopts = P.defaulted_gopts()
  local process_files = coroutine.create(function()
    local weighted_files = M.get_weighted_files {
      query = opts.query,
      curr_bufname = opts.curr_bufname,
      alternate_bufname = opts.alternate_bufname,
    }

    if P.tick ~= opts.curr_tick then
      L.benchmark_step_interrupted()
      L.benchmark_step_closing()
      return
    end

    L.benchmark_step_heading "Process weighted files"

    L.benchmark_step("start", "Render results")
    opts.render_results(weighted_files)
    L.benchmark_step("end", "Render results")

    if not gopts.hl_enabled then
      L.benchmark_step("end", "Total per keystroke")
      L.benchmark_step_closing()
      return
    end

    vim.api.nvim_buf_clear_namespace(opts.results_buf, P.ns_id, 0, -1)
    P.highlight_weighted_files { weighted_files = weighted_files, results_buf = opts.results_buf, }

    L.benchmark_step("end", "Total per keystroke")
    L.benchmark_step_closing()
  end)

  local function continue_processing()
    if P.tick ~= opts.curr_tick then
      L.benchmark_step_interrupted()
      L.benchmark_step_closing()
      return
    end
    coroutine.resume(process_files)

    if coroutine.status(process_files) == "suspended" then
      vim.schedule(continue_processing)
    end
  end

  vim.schedule(continue_processing)
end

--- @param win number
P.save_minimal_opts = function(win)
  -- :help nvim_open_win
  local minimal_opts_to_save = {
    "number", "relativenumber", "cursorline", "cursorcolumn",
    "foldcolumn", "spell", "list", "signcolumn", "colorcolumn",
    "statuscolumn", "fillchars", "winhighlight",
  }

  local saved_minimal_opts = {}
  for _, opt in ipairs(minimal_opts_to_save) do
    saved_minimal_opts[opt] = vim.api.nvim_get_option_value(opt, { win = win, })
  end

  return saved_minimal_opts
end

--- @param win number
--- @param opts vim.wo
P.set_opts = function(win, opts)
  for opt, value in pairs(opts) do
    vim.api.nvim_set_option_value(opt, value, { win = win, })
  end
end

P.setup_called = false

M.setup = function()
  if P.setup_called then return end
  P.setup_called = true

  local gopts = P.defaulted_gopts()

  if gopts.refresh_files_cache == "setup" then
    P.refresh_files_cache()
  end

  local timer_id = nil
  local last_updated_abs_file = nil
  vim.api.nvim_create_autocmd({ "BufWinEnter", }, {
    group = vim.api.nvim_create_augroup("FFSetup", { clear = true, }),
    callback = function(ev)
      if timer_id then
        vim.fn.timer_stop(timer_id)
      end

      local current_win = vim.api.nvim_get_current_win()
      local is_buf_normal = vim.api.nvim_win_get_config(current_win).relative == ""
      if not is_buf_normal then return end
      local abs_path = vim.fs.normalize(vim.api.nvim_buf_get_name(ev.buf))
      local rel_path = vim.fs.relpath(H.cwd, abs_path)
      if abs_path == "" then return end
      if last_updated_abs_file == abs_path then return end

      timer_id = vim.fn.timer_start(1000, function()
        last_updated_abs_file = abs_path

        if gopts.notify_frecency_update then
          vim.notify(("[ff.nvim] frecency score updated for %s"):format(rel_path), vim.log.levels.INFO)
        end
        F.update_file_score(abs_path, { update_type = "increase", })
        if P.caches.frecency_file_to_score[abs_path] == nil then
          P.refresh_files_cache()
        end
      end)
    end,
  })
  vim.api.nvim_set_hl(0, "FFPickerFuzzyHighlightChar", { link = "Search", })
  vim.api.nvim_set_hl(0, "FFPickerCursorLine", { link = "CursorLine", })
end

M.refresh_files_cache = function()
  if not P.setup_called then
    vim.notify("[ff.nvim]: `setup` must be called before `refresh_files_cache`", vim.log.levels.ERROR)
  end
  P.refresh_files_cache()
end

M.reset_benchmarks = function()
  L.ongoing_benchmarks = {}
  L.benchmarks_for_mean = {}
end

M.print_mean_benchmarks = function()
  L.benchmark_mean_heading "Mean benchmarks"

  if not L.should_log_mean() then return end
  for label, benchmarks in pairs(L.benchmarks_for_mean) do
    local sum = 0
    for _, bench in ipairs(benchmarks) do
      sum = sum + bench
    end
    local mean = sum / #benchmarks
    local formatted_mean = H.pad_str(H.exact_decimals(mean, 3), 8)
    L.log_content(("%s ms : %s"):format(formatted_mean, label))
  end

  L.benchmark_mean_closing()
end

M.find = function()
  if not P.setup_called then
    vim.notify("[ff.nvim]: `setup` must be called before `find`", vim.log.levels.ERROR)
    return
  end
  M.reset_benchmarks()
  P.preview_active = false

  local gopts = P.defaulted_gopts()

  local cursorline_opts = {
    cursorline = true,
    winhighlight = "CursorLine:FFPickerCursorLine",
  }

  local curr_bufname_ok, curr_bufname_res = pcall(vim.api.nvim_buf_get_name, 0)
  local alt_bufname_ok, alt_bufname_res = pcall(vim.api.nvim_buf_get_name, vim.fn.bufnr "#")
  local curr_bufname = curr_bufname_ok and curr_bufname_res or ""
  local alternate_bufname = alt_bufname_ok and alt_bufname_res or ""

  local preview_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = preview_buf, })

  local results_buf = vim.api.nvim_create_buf(false, true)
  local results_win = vim.api.nvim_open_win(results_buf, false, gopts.results_win_config)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = results_buf, })
  local minimal_opts = P.save_minimal_opts(results_win)

  local function set_results_win_opts()
    P.set_opts(results_win, minimal_opts)
    P.set_opts(results_win, cursorline_opts)
    P.set_opts(results_win, gopts.results_win_opts)
  end

  local function set_preview_win_opts()
    P.set_opts(results_win, minimal_opts)
    P.set_opts(results_win, gopts.preview_win_opts)
  end

  set_results_win_opts()

  local input_buf = vim.api.nvim_create_buf(false, true)
  local input_win = vim.api.nvim_open_win(input_buf, false, gopts.input_win_config)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = input_buf, })
  vim.api.nvim_set_current_win(input_win)

  gopts.on_picker_open {
    input_buf = input_buf,
    input_win = input_win,
    results_buf = results_buf,
    results_win = results_win,
  }

  vim.cmd "startinsert"

  --- @param query string
  local function get_find_files_with_query(query)
    P.get_find_files {
      query = query,
      results_buf = results_buf,
      curr_bufname = curr_bufname,
      alternate_bufname = alternate_bufname,
      curr_tick = P.tick,
      render_results = function(weighted_files)
        local formatted_filenames = {}
        for idx, weighted_file in ipairs(weighted_files) do
          if idx >= gopts.max_results_rendered then break end
          table.insert(formatted_filenames, weighted_file.formatted_filename)
        end
        vim.api.nvim_buf_set_lines(results_buf, 0, -1, false, formatted_filenames)
      end,
    }
  end

  vim.schedule(
    function()
      if gopts.refresh_files_cache == "find" then
        P.refresh_files_cache()
      end
      M.refresh_open_buffers_cache()
      M.refresh_frecency_cache()

      get_find_files_with_query ""
    end
  )

  local function close()
    vim.api.nvim_buf_clear_namespace(results_buf, P.ns_id, 0, -1)
    vim.api.nvim_win_close(input_win, true)
    vim.api.nvim_win_close(results_win, true)
    M.print_mean_benchmarks()
    vim.cmd "stopinsert"
  end

  local keymap_fns = {
    ResultSelect = function()
      if P.preview_active then return end

      vim.api.nvim_set_current_win(results_win)
      local result = vim.api.nvim_get_current_line()
      if #result == 0 then return end
      close()
      vim.cmd("edit " .. vim.split(result, "|")[2])
    end,
    ResultNext = function()
      if P.preview_active then return end

      vim.api.nvim_win_call(results_win, function()
        if vim.api.nvim_win_get_cursor(results_win)[1] == vim.api.nvim_buf_line_count(results_buf) then
          vim.cmd "normal! gg"
        else
          vim.cmd "normal! j"
        end
        vim.cmd "redraw"
      end)
    end,
    ResultPrev = function()
      if P.preview_active then return end

      vim.api.nvim_win_call(results_win, function()
        if vim.api.nvim_win_get_cursor(results_win)[1] == 1 then
          vim.cmd "normal! G"
        else
          vim.cmd "normal! k"
        end
        vim.cmd "redraw"
      end)
    end,
    Close = close,
    PreviewToggle = function()
      if P.preview_active then
        P.preview_active = not P.preview_active
        vim.api.nvim_win_set_buf(results_win, results_buf)
        set_results_win_opts()
        return
      end

      P.preview_active = not P.preview_active
      local result
      vim.api.nvim_win_call(results_win, function()
        result = vim.api.nvim_get_current_line()
      end)
      if #result == 0 then return end

      vim.api.nvim_win_set_buf(results_win, preview_buf)
      set_preview_win_opts()

      local abs_path = vim.split(result, "|")[2]
      local lines = vim.fn.readfile(abs_path, "", 100)
      vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)

      local filetype = vim.filetype.match { filename = abs_path, }
      if filetype == nil then return end

      local lang_ok, lang = pcall(vim.treesitter.language.get_lang, filetype)
      if not lang_ok then return end

      pcall(vim.treesitter.start, preview_buf, lang)
    end,
    PreviewScrollDown = function()
      if not P.preview_active then return end
      vim.api.nvim_win_call(results_win, function()
        vim.cmd 'execute "normal! \\<C-d>"'
      end)
    end,
    PreviewScrollUp = function()
      if not P.preview_active then return end
      vim.api.nvim_win_call(results_win, function()
        vim.cmd 'execute "normal! \\<C-u>"'
      end)
    end,
  }

  for action, fn in pairs(keymap_fns) do
    vim.keymap.set({ "i", "n", }, "<Plug>FF" .. action, fn, {
      buffer = input_buf,
      desc = "FF: " .. action,
    })
  end
  vim.api.nvim_set_option_value("filetype", "ff-picker", { buf = input_buf, })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", }, {
    group = vim.api.nvim_create_augroup("FFPicker", { clear = true, }),
    buffer = input_buf,
    callback = function()
      P.tick = P.tick + 1
      if P.preview_active then keymap_fns["PreviewToggle"]() end
      get_find_files_with_query(vim.api.nvim_get_current_line())
    end,
  })
end

if _G.FF_TEST then
  M._internal = {
    H = H,
    F = F,
    L = L,
    P = P,
  }
end

return M
