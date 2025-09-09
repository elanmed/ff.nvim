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

--- @param abs_file string
H.rel_file = function(abs_file)
  --- @type string
  if not vim.startswith(abs_file, H.cwd) then return abs_file end
  return abs_file:sub(#H.cwd + 2)
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

--- @param filename string
H.get_ext = function(filename)
  local last_dot_pos = filename:find "%.[^.]*$"
  if last_dot_pos and last_dot_pos > 1 then
    return filename:sub(last_dot_pos + 1)
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

--- @param msg string
--- @param ... any
H.notify_error = function(msg, ...)
  local formatted = msg:format(...)
  vim.notify(formatted, vim.log.levels.ERROR)
end

--- @param abs_file string
H.readable = function(abs_file)
  local stat_result = vim.uv.fs_stat(abs_file)
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
    H.notify_error "[ff.nvim]: vim.fn.mkdir returned vimscript_false"
    return
  end

  local file = io.open(path, "w")
  if file == nil then
    H.notify_error "[ff.nvim]: io.open failed to open the file created with vim.fn.mkdir"
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

--- @param filename string
--- @param opts UpdateFileScoreOpts
F.update_file_score = function(filename, opts)
  local now = F._now()

  opts._db_dir = H.default(opts._db_dir, F.default_db_dir)
  local dated_files_path = F.get_dated_files_path(opts._db_dir)
  local dated_files = F.read(dated_files_path)
  if not dated_files[H.cwd] then
    dated_files[H.cwd] = {}
  end

  local updated_date_at_score_one = (function()
    if opts.update_type == "increase" then
      if not H.readable(filename) then
        return nil
      end

      local score = 0
      local date_at_score_one = dated_files[H.cwd][filename]
      if date_at_score_one then
        score = F.compute_score { now = now, date_at_score_one = date_at_score_one, }
      end
      local updated_score = score + 1

      return F.compute_date_at_score_one { now = now, score = updated_score, }
    end

    return nil
  end)()

  dated_files[H.cwd][filename] = updated_date_at_score_one

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
  if not file then return end
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

L.benchmark_step_heading = L.create_benchmark_heading(function() return L.SHOULD_LOG_STEP end)
L.benchmark_mean_heading = L.create_benchmark_heading(function() return L.SHOULD_LOG_MEAN end)

--- @param get_flag function
L.create_benchmark_closing = function(get_flag)
  return function()
    if not get_flag() then return end
    L.log_line "end"
  end
end

L.benchmark_step_closing = L.create_benchmark_closing(function() return L.SHOULD_LOG_STEP end)
L.benchmark_mean_closing = L.create_benchmark_closing(function() return L.SHOULD_LOG_MEAN end)

L.benchmark_step_interrupted = function()
  if not L.SHOULD_LOG_STEP then return end
  L.log_content "INTERRUPTED"
end

--- @type table<string, number>
L.ongoing_benchmarks = {}

--- @type table<string, number[]>
L.collected_benchmarks = {}

--- @param type "start"|"end"
--- @param label string
--- @param opts? {record_mean: boolean}
L.benchmark_step = function(type, label, opts)
  opts = H.default(opts, {})
  opts.record_mean = H.default(opts.record_mean, true)
  if type == "start" then
    L.ongoing_benchmarks[label] = os.clock()
  else
    local end_time = os.clock()
    local start_time = L.ongoing_benchmarks[label]

    local elapsed_ms = (end_time - start_time) * 1000
    local formatted_ms = H.pad_str(H.exact_decimals(elapsed_ms, 3), 8)

    if L.SHOULD_LOG_MEAN and opts.record_mean then
      if not L.collected_benchmarks[label] then
        L.collected_benchmarks[label] = {}
      end
      table.insert(L.collected_benchmarks[label], elapsed_ms)
    end

    if L.SHOULD_LOG_STEP then
      local content = ("% sms : %s"):format(formatted_ms, label)
      L.log("│" .. content .. (" "):rep(L.LOG_LEN - #content - 2) .. "│")
    end
  end
end

L.benchmark_mean = function()
  if not L.SHOULD_LOG_MEAN then return end

  for label, benchmarks in pairs(L.collected_benchmarks) do
    local sum = 0
    for _, bench in ipairs(benchmarks) do
      sum = sum + bench
    end
    local mean = sum / #benchmarks
    local formatted_mean = H.pad_str(H.exact_decimals(mean, 3), 8)
    L.log_content(("%s ms : %s"):format(formatted_mean, label))
  end
end

-- ======================================================
-- == Picker ============================================
-- ======================================================

local P = {}

P.tick = 0
P.ns_id = vim.api.nvim_create_namespace "FFPicker"

-- [-math.huge, math.huge]
-- just below math.huge is approx the length of the string
-- just above -math.huge is approx 0
P.MAX_FZY_SCORE = 20 -- approx the longest reasonable query
P.MAX_FRECENCY_SCORE = 99 -- approx the largest reasonable frecency score
P.MAX_SCORE_LEN = #H.exact_decimals(P.MAX_FRECENCY_SCORE, 2)

--- @param abs_file string
--- @param score number
--- @param icon_char string|nil
P.format_filename = function(abs_file, score, icon_char)
  local formatted_score = H.pad_str(
    H.fit_decimals(score, P.MAX_SCORE_LEN),
    P.MAX_SCORE_LEN
  )
  local formatted_icon_char = icon_char and icon_char .. " " or ""
  local rel_file = H.rel_file(abs_file)
  return ("%s %s|%s"):format(
    formatted_score,
    formatted_icon_char,
    rel_file
  )
end

--- @param fzy_score number
P.scale_fzy_to_frecency = function(fzy_score)
  if fzy_score == math.huge then return P.MAX_FRECENCY_SCORE end
  if fzy_score == -math.huge then return 0 end
  return (fzy_score) / (P.MAX_FZY_SCORE) * P.MAX_FRECENCY_SCORE
end

P.caches = {
  --- @type string[]
  fd_files = {},

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

P.default_fd_cmd = "fd --absolute-path --hidden --type f --exclude node_modules --exclude .git --exclude dist"

--- @param fd_cmd string
P.refresh_files_cache = function(fd_cmd)
  P.caches.fd_files = {}

  L.benchmark_step_heading "Refresh files cache"
  L.benchmark_step("start", "Refresh fd cache")
  local fd_cmd_tbl = vim.split(fd_cmd, " ")
  vim.system(fd_cmd_tbl, { text = true, }, function(obj)
    local lines = vim.split(obj.stdout, "\n")
    for _, abs_file in ipairs(lines) do
      if #abs_file == 0 then goto continue end
      table.insert(P.caches.fd_files, vim.fs.normalize(abs_file))

      ::continue::
    end
    L.benchmark_step("end", "Refresh fd cache", { record_mean = false, })
    L.benchmark_step_closing()
  end)
end

P.refresh_frecency_cache = function()
  L.benchmark_step_heading "Refresh frecency cache"
  P.caches.frecency_files = {}
  P.caches.frecency_file_to_score = {}

  L.benchmark_step("start", "Frecency dated_files fs read")
  local dated_files_path = F.get_dated_files_path()
  local dated_files = F.read(dated_files_path)
  if not dated_files[H.cwd] then
    dated_files[H.cwd] = {}
  end
  L.benchmark_step("end", "Frecency dated_files fs read", { record_mean = false, })

  local now = os.time()
  L.benchmark_step("start", "Calculate frecency_file_to_score")
  for abs_file, date_at_score_one in pairs(dated_files[H.cwd]) do
    if not H.readable(abs_file) then goto continue end
    local score = F.compute_score { now = now, date_at_score_one = date_at_score_one, }
    P.caches.frecency_file_to_score[abs_file] = score
    table.insert(P.caches.frecency_files, abs_file)

    ::continue::
  end
  L.benchmark_step("end", "Calculate frecency_file_to_score", { record_mean = false, })
  L.benchmark_step_closing()
end

P.refresh_open_buffers_cache = function()
  P.caches.open_buffer_to_modified = {}

  L.benchmark_step_heading "Refresh open buffers cache"
  L.benchmark_step("start", "open_buffer_to_modified loop")
  for _, bufnr in pairs(vim.api.nvim_list_bufs()) do
    if not vim.api.nvim_buf_is_loaded(bufnr) then goto continue end
    if not vim.api.nvim_get_option_value("buflisted", { buf = bufnr, }) then goto continue end
    local buf_name = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
    if buf_name == "" then goto continue end
    if not vim.startswith(buf_name, H.cwd) then goto continue end

    local modified = vim.api.nvim_get_option_value("modified", { buf = bufnr, })
    P.caches.open_buffer_to_modified[buf_name] = modified

    ::continue::
  end
  L.benchmark_step("end", "open_buffer_to_modified loop", { record_mean = false, })
  L.benchmark_step_closing()
end

--- @class WeightedFile
--- @field abs_file string
--- @field rel_file string
--- @field weighted_score number
--- @field fzy_score number
--- @field buf_and_frecency_score number
--- @field hl_idxs table
--- @field icon_char string
--- @field icon_hl string
--- @field formatted_filename string

--- @class GetIconInfoOpts
--- @field icons_enabled boolean
--- @field abs_file string
--- @param opts GetIconInfoOpts
P.get_icon_info = function(opts)
  local mini_icons = require "mini.icons"
  if not opts.icons_enabled then
    return {
      icon_char = nil,
      icon_hl = nil,
    }
  end

  local ext = H.get_ext(opts.abs_file)
  if ext and P.caches.icon_cache[ext] then
    return {
      icon_char = P.caches.icon_cache[ext].icon_char,
      icon_hl = P.caches.icon_cache[ext].icon_hl,
    }
  end

  local _, icon_char_res, icon_hl_res = pcall(mini_icons.get, "file", opts.abs_file)
  local icon_info = {
    icon_char = icon_char_res or "?",
    icon_hl = icon_hl_res or nil,
  }
  if ext then
    P.caches.icon_cache[ext] = { icon_char = icon_info.icon_char, icon_hl = icon_info.icon_hl, }
  end
  return icon_info
end

--- @class GetWeightedFilesOpts
--- @field query string
--- @field curr_bufname string
--- @field alt_bufname string
--- @field weights FindWeights
--- @field icons_enabled boolean
--- @field hi_enabled boolean
--- @field fuzzy_score_multiple number
--- @field file_score_multiple number
--- @field max_results_considered number
--- @field max_results_rendered number
--- @field batch_size number
--- @param opts GetWeightedFilesOpts
P.get_weighted_files = function(opts)
  if P.caches.weighted_files_per_query[opts.query] then
    return P.caches.weighted_files_per_query[opts.query]
  end

  local fzy = require "fzy-lua-native"

  --- @type WeightedFile[]
  local weighted_files_for_query = {}

  --- @param abs_file string
  local function get_weighted_file(abs_file)
    local rel_file = H.rel_file(abs_file)
    if #opts.query == 0 then
      local icon_info = P.get_icon_info { abs_file = abs_file, icons_enabled = opts.icons_enabled, }

      local frecency_score = 0
      if P.caches.frecency_file_to_score[abs_file] ~= nil then
        frecency_score = P.caches.frecency_file_to_score[abs_file]
      end
      return {
        abs_file = abs_file,
        rel_file = rel_file,
        weighted_score = frecency_score,
        buf_and_frecency_score = 0,
        fzy_score = 0,
        hl_idxs = {},
        icon_hl = icon_info.icon_hl,
        icon_char = icon_info.icon_char,
        formatted_filename = P.format_filename(abs_file, frecency_score, icon_info.icon_char),
      }
    end

    if not fzy.has_match(opts.query, rel_file) then
      return nil
    end

    local buf_score = 0
    local basename_with_ext = H.basename(abs_file, { with_ext = true, })
    local basename_without_ext = H.basename(abs_file, { with_ext = false, })

    if opts.query == basename_with_ext or opts.query == basename_without_ext then
      buf_score = opts.weights.basename_boost
    elseif P.caches.open_buffer_to_modified[abs_file] ~= nil then
      local modified = P.caches.open_buffer_to_modified[abs_file]

      if abs_file == opts.curr_bufname then
        buf_score = opts.weights.current_buf_boost
      elseif abs_file == opts.alt_bufname then
        buf_score = opts.weights.alternate_buf_boost
      elseif modified then
        buf_score = opts.weights.modified_buf_boost
      else
        buf_score = opts.weights.open_buf_boost
      end
    end

    local buf_and_frecency_score = buf_score
    if P.caches.frecency_file_to_score[abs_file] ~= nil then
      buf_and_frecency_score = buf_and_frecency_score + P.caches.frecency_file_to_score[abs_file]
    end

    local fzy_score = fzy.score(opts.query, rel_file)
    local scaled_fzy_score = P.scale_fzy_to_frecency(fzy_score)
    local weighted_score =
        opts.fuzzy_score_multiple * scaled_fzy_score +
        opts.file_score_multiple * buf_and_frecency_score

    local icon_info = P.get_icon_info { abs_file = abs_file, icons_enabled = opts.icons_enabled, }
    local hl_idxs = {}
    if opts.hi_enabled then
      hl_idxs = fzy.positions(opts.query, rel_file)
    end

    return {
      abs_file = abs_file,
      rel_file = rel_file,
      weighted_score = weighted_score,
      fzy_score = scaled_fzy_score,
      buf_and_frecency_score = buf_and_frecency_score,
      hl_idxs = hl_idxs,
      icon_hl = icon_info.icon_hl,
      icon_char = icon_info.icon_char,
      formatted_filename = P.format_filename(abs_file, weighted_score, icon_info.icon_char),
    }
  end

  local max_results = (function()
    if opts.query == "" then
      return opts.max_results_rendered
    end
    return opts.max_results_considered
  end)()

  L.benchmark_step("start", "Populate weighted files with frecency")
  for idx, abs_file in pairs(P.caches.frecency_files) do
    if #weighted_files_for_query >= max_results then break end

    local weighted_file = get_weighted_file(abs_file)
    if weighted_file then
      table.insert(weighted_files_for_query, weighted_file)
    end

    if idx % opts.batch_size == 0 then
      coroutine.yield()
    end
  end
  L.benchmark_step("end", "Populate weighted files with frecency")

  L.benchmark_step("start", "Populate weighted files with fd")
  for idx, abs_file in ipairs(P.caches.fd_files) do
    if #weighted_files_for_query >= max_results then break end
    if P.caches.frecency_file_to_score[abs_file] ~= nil then
      goto continue
    end

    local weighted_file = get_weighted_file(abs_file)
    if weighted_file then
      table.insert(weighted_files_for_query, weighted_file)
    end

    if idx % opts.batch_size == 0 then
      coroutine.yield()
    end

    ::continue::
  end
  L.benchmark_step("end", "Populate weighted files with fd")

  L.benchmark_step("start", "Sort weighted files")
  table.sort(weighted_files_for_query, function(a, b)
    return a.weighted_score > b.weighted_score
  end)
  L.benchmark_step("end", "Sort weighted files")

  P.caches.weighted_files_per_query[opts.query] = weighted_files_for_query
  return weighted_files_for_query
end

--- @class HighlightWeightedFilesOpts
--- @field weighted_files WeightedFile[]
--- @field max_results_rendered number
--- @field results_buf number
--- @field batch_size number
--- @param opts HighlightWeightedFilesOpts
P.highlight_weighted_files = function(opts)
  local formatted_score_last_idx = #H.pad_str(
    H.fit_decimals(P.MAX_FRECENCY_SCORE, P.MAX_SCORE_LEN),
    P.MAX_SCORE_LEN
  )
  local icon_char_idx = formatted_score_last_idx + 2

  L.benchmark_step("start", "Highlight results")
  for idx, weighted_file in ipairs(opts.weighted_files) do
    if idx > opts.max_results_rendered then break end
    local row_0_indexed = idx - 1

    if weighted_file.icon_hl then
      local icon_hl_col_1_indexed = icon_char_idx
      local icon_hl_col_0_indexed = icon_hl_col_1_indexed - 1

      vim.hl.range(
        opts.results_buf,
        P.ns_id,
        weighted_file.icon_hl,
        { row_0_indexed, icon_hl_col_0_indexed, },
        { row_0_indexed, icon_hl_col_0_indexed + 1, }
      )
    end

    local file_offset = weighted_file.formatted_filename:find "|"
    for _, hl_idx in ipairs(weighted_file.hl_idxs) do
      local file_char_hl_col_0_indexed = hl_idx + file_offset - 1

      vim.hl.range(
        opts.results_buf,
        P.ns_id,
        "FFPickerFuzzyHighlightChar",
        { row_0_indexed, file_char_hl_col_0_indexed, },
        { row_0_indexed, file_char_hl_col_0_indexed + 1, }
      )
    end

    if idx % opts.batch_size == 0 then
      coroutine.yield()
    end
  end
  L.benchmark_step("end", "Highlight results")
end

--- @class GetFindFilesOpts
--- @field query string
--- @field results_buf number
--- @field curr_bufname string
--- @field alt_bufname string
--- @field curr_tick number
--- @field render_results fun(weighted_files:WeightedFile[]):nil
--- @field weights FindWeights
--- @field batch_size number
--- @field hi_enabled boolean
--- @field icons_enabled boolean
--- @field fuzzy_score_multiple number
--- @field file_score_multiple number
--- @field max_results_considered number
--- @field max_results_rendered number

--- @param opts GetFindFilesOpts
P.get_find_files = function(opts)
  vim.api.nvim_buf_clear_namespace(opts.results_buf, P.ns_id, 0, -1)

  opts.query = opts.query:gsub("%s+", "") -- fzy doesn't ignore spaces
  L.benchmark_step_heading(("query: '%s'"):format(opts.query))
  L.benchmark_step("start", "Entire script")

  local process_files = coroutine.create(function()
    local weighted_files = P.get_weighted_files {
      alt_bufname = opts.alt_bufname,
      batch_size = opts.batch_size,
      curr_bufname = opts.curr_bufname,
      file_score_multiple = opts.file_score_multiple,
      fuzzy_score_multiple = opts.fuzzy_score_multiple,
      hi_enabled = opts.hi_enabled,
      icons_enabled = opts.icons_enabled,
      max_results_considered = opts.max_results_considered,
      max_results_rendered = opts.max_results_rendered,
      query = opts.query,
      weights = opts.weights,
    }

    if P.tick ~= opts.curr_tick then
      L.benchmark_step_interrupted()
      L.benchmark_step_closing()
      return
    end
    L.benchmark_step("start", "Render results")
    opts.render_results(weighted_files)
    L.benchmark_step("end", "Render results")

    if not opts.hi_enabled then
      L.benchmark_step("end", "Entire script")
      L.benchmark_step_closing()
      return
    end

    P.highlight_weighted_files {
      batch_size = opts.batch_size,
      max_results_rendered = opts.max_results_rendered,
      results_buf = opts.results_buf,
      weighted_files = weighted_files,
    }

    L.benchmark_step("end", "Entire script")
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

  continue_processing()
end

--- @class SetupOpts
--- @field refresh_files_cache? "setup"|"find"
--- @field benchmark_step? boolean
--- @field benchmark_mean? boolean
--- @field fd_cmd? string
--- @field icons_enabled? boolean

P.setup_opts = {}
P.setup_called = false

--- @param opts? SetupOpts
M.setup = function(opts)
  if P.setup_called then return end
  P.setup_called = true

  opts = H.default(opts, {})
  opts.benchmark_step = H.default(opts.benchmark_step, false)
  L.SHOULD_LOG_STEP = opts.benchmark_step

  opts.benchmark_mean = H.default(opts.benchmark_mean, false)
  L.SHOULD_LOG_MEAN = opts.benchmark_mean

  opts.fd_cmd = H.default(opts.fd_cmd, P.default_fd_cmd)
  opts.refresh_files_cache = H.default(opts.refresh_files_cache, "setup")
  P.setup_opts = opts

  if opts.refresh_files_cache == "setup" then
    P.refresh_files_cache(opts.fd_cmd)
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
      local abs_file = vim.fs.normalize(vim.api.nvim_buf_get_name(ev.buf))
      if abs_file == "" then return end
      if last_updated_abs_file == abs_file then return end

      timer_id = vim.fn.timer_start(1000, function()
        last_updated_abs_file = abs_file

        F.update_file_score(vim.fs.normalize(abs_file), { update_type = "increase", })
        if not P.caches.frecency_file_to_score[abs_file] then
          P.refresh_files_cache(opts.fd_cmd)
        end
      end)
    end,
  })
  vim.api.nvim_set_hl(0, "FFPickerFuzzyHighlightChar", { link = "Search", })
  vim.api.nvim_set_hl(0, "FFPickerCursorLine", { link = "CursorLine", })
end

--- @param fd_cmd? string
M.refresh_files_cache = function(fd_cmd)
  if not P.setup_called then
    H.notify_error "[ff.nvim]: `setup` must be called before `refresh_files_cache`"
  end
  fd_cmd = H.default(fd_cmd, P.setup_opts.fd_cmd)
  P.refresh_files_cache(fd_cmd)
end

--- @class FindOpts
--- @field keymaps? FindKeymapsPerMode
--- @field weights? FindWeights
--- @field batch_size? number
--- @field hi_enabled? boolean
--- @field icons_enabled? boolean
--- @field max_results_considered? number
--- @field max_results_rendered? number
--- @field fuzzy_score_multiple? number
--- @field file_score_multiple? number
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
P.find = function(opts)
  if not P.setup_called then
    H.notify_error "[ff.nvim]: `setup` must be called before `find`"
    return
  end
  H.cwd = vim.uv.cwd()
  L.ongoing_benchmarks = {}
  L.collected_benchmarks = {}
  P.caches.weighted_files_per_query = {}

  opts = H.default(opts, {})
  opts.keymaps = H.default(opts.keymaps, {})
  opts.keymaps.i = H.default(opts.keymaps.i, {})
  opts.keymaps.n = H.default(opts.keymaps.n, {})

  opts.weights = H.default(opts.weights, {})
  opts.weights.open_buf_boost = H.default(opts.weights.open_buf_boost, 10)
  opts.weights.modified_buf_boost = H.default(opts.weights.modified_buf_boost, 20)
  opts.weights.alternate_buf_boost = H.default(opts.weights.alternate_buf_boost, 30)
  opts.weights.basename_boost = H.default(opts.weights.basename_boost, 40)
  opts.weights.current_buf_boost = H.default(opts.weights.current_buf_boost, -1000)

  opts.batch_size = H.default(opts.batch_size, 250)
  opts.hi_enabled = H.default(opts.hi_enabled, true)
  opts.icons_enabled = H.default(opts.icons_enabled, true)
  opts.max_results_considered = H.default(opts.max_results_considered, 1000)
  opts.fuzzy_score_multiple = H.default(opts.fuzzy_score_multiple, 0.7)
  opts.file_score_multiple = H.default(opts.file_score_multiple, 0.3)
  opts.on_picker_open = H.default(opts.on_picker_open, function() end)

  local editor_height = vim.o.lines - 1
  local input_height = 1
  local border_height = 2
  local available_height = editor_height - input_height - (border_height * 3)
  local results_height = math.floor(available_height / 2)
  local input_row = editor_height
  local results_row = input_row - input_height - border_height

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

  local _, curr_bufname = pcall(vim.api.nvim_buf_get_name, 0)
  local _, alt_bufname = pcall(vim.api.nvim_buf_get_name, vim.fn.bufnr "#")
  curr_bufname = curr_bufname and vim.fs.normalize(curr_bufname) or ""
  alt_bufname = alt_bufname and vim.fs.normalize(alt_bufname) or ""

  local results_buf = vim.api.nvim_create_buf(false, true)
  local results_win = vim.api.nvim_open_win(results_buf, false, opts.results_win_config)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = results_buf, })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = results_buf, })
  vim.api.nvim_set_option_value("cursorline", true, { win = results_win, })

  local input_buf = vim.api.nvim_create_buf(false, true)
  local input_win = vim.api.nvim_open_win(input_buf, false, opts.input_win_config)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = input_buf, })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = input_buf, })
  vim.api.nvim_set_current_win(input_win)

  opts.on_picker_open {
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
      alt_bufname = alt_bufname,
      curr_tick = P.tick,
      weights = opts.weights,
      batch_size = opts.batch_size,
      hi_enabled = opts.hi_enabled,
      icons_enabled = opts.icons_enabled,
      fuzzy_score_multiple = opts.fuzzy_score_multiple,
      file_score_multiple = opts.file_score_multiple,
      max_results_considered = opts.max_results_considered,
      max_results_rendered = opts.max_results_rendered,
      render_results = function(weighted_files)
        local formatted_filenames = {}
        for idx, weighted_file in ipairs(weighted_files) do
          if idx >= opts.max_results_considered then break end
          table.insert(formatted_filenames, weighted_file.formatted_filename)
        end
        vim.api.nvim_buf_set_lines(results_buf, 0, -1, false, formatted_filenames)
      end,
    }
  end

  vim.schedule(
    function()
      if P.setup_opts.refresh_files_cache == "find" then
        P.refresh_files_cache(P.setup_opts.fd_cmd)
      end
      P.refresh_open_buffers_cache()
      P.refresh_frecency_cache()

      get_find_files_with_query ""
    end
  )

  local function close()
    vim.api.nvim_buf_clear_namespace(results_buf, P.ns_id, 0, -1)
    L.benchmark_mean_heading "Mean benchmarks"
    L.benchmark_mean()
    L.benchmark_mean_closing()

    vim.api.nvim_win_close(input_win, true)
    vim.api.nvim_win_close(results_win, true)
    vim.cmd "stopinsert"
  end

  local keymap_fns = {
    select = function()
      vim.api.nvim_set_current_win(results_win)
      local result = vim.api.nvim_get_current_line()
      if #result == 0 then return end
      close()
      vim.cmd("edit " .. vim.split(result, "|")[2])
    end,
    next = function()
      vim.api.nvim_win_call(results_win, function()
        if vim.api.nvim_win_get_cursor(results_win)[1] == vim.api.nvim_buf_line_count(results_buf) then
          vim.cmd "normal! gg"
        else
          vim.cmd "normal! j"
        end
        vim.cmd "redraw"
      end)
    end,
    prev = function()
      vim.api.nvim_win_call(results_win, function()
        if vim.api.nvim_win_get_cursor(results_win)[1] == 1 then
          vim.cmd "normal! G"
        else
          vim.cmd "normal! k"
        end
        vim.cmd "redraw"
      end)
    end,
    close = close,
  }

  for mode, keymaps in pairs(opts.keymaps) do
    for key, map in pairs(keymaps) do
      vim.keymap.set(mode, key, function()
        if type(map) == "string" then
          keymap_fns[map]()
        else
          map()
        end
      end, { buffer = input_buf, })
    end
  end

  vim.api.nvim_set_option_value("winhighlight", "CursorLine:FFPickerCursorLine", { win = results_win, })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", }, {
    group = vim.api.nvim_create_augroup("FFPicker", { clear = true, }),
    buffer = input_buf,
    callback = function()
      P.tick = P.tick + 1
      vim.schedule(function()
        get_find_files_with_query(vim.api.nvim_get_current_line())
      end)
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

M.find = P.find
return M
