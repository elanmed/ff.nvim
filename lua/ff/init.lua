local M = {}

-- ======================================================
-- == Misc helpers ======================================
-- ======================================================

local H = {}

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
H.get_rel_file = function(abs_file)
  --- @type string
  local cwd = vim.uv.cwd()
  if not vim.startswith(abs_file, cwd) then return abs_file end
  return abs_file:sub(#cwd + 2)
end

--- @param path string
--- @param opts { with_ext: boolean }
H.basename = function(path, opts)
  if path == "" then return path end
  local basename = path:match "([^/\\]+)$"
  if opts.with_ext then return basename end

  local first_dot_pos = basename:find "%."
  if first_dot_pos then
    return basename:sub(1, first_dot_pos - 1)
  end
  return basename
end

--- @param filename string
H.get_ext = function(filename)
  local last_dot_pos = filename:find "%.[^.]+$"
  if last_dot_pos then
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
  return string.format("%." .. decimals .. "f", num)
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

--- @param file string
H.pcall_edit = function(file)
  pcall(vim.cmd, "edit " .. file)
end

H.vimscript_true = 1
H.vimscript_false = 0

-- ======================================================
-- == Notify ============================================
-- ======================================================

local N = {}


--- @param msg string
N.notify_error = function(msg)
  vim.notify(msg, vim.log.levels.ERROR)
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
  -- io.open won't throw
  local file = io.open(path, "r")
  if file == nil then
    return {}
  end

  -- file:read won't throw
  local encoded_data = file:read "*a"
  file:close()

  -- vim.json.decode will throw
  local decode_ok, decoded_data = pcall(vim.json.decode, encoded_data)
  if not decode_ok then
    N.notify_error "[ff.nvim]: vim.json.decode threw"
    return {}
  end
  return decoded_data
end

--- @param path string
--- @param data table
--- @return nil
F.write = function(path, data)
  -- vim.fn.mkdir won't throw
  local path_dir = vim.fs.dirname(path)
  local mkdir_res = vim.fn.mkdir(path_dir, "p")
  if mkdir_res == H.vimscript_false then
    N.notify_error "[ff.nvim]: vim.fn.mkdir returned vimscript_false"
    return
  end

  -- io.open won't throw
  local file = io.open(path, "w")
  if file == nil then
    N.notify_error "[ff.nvim]: io.open failed to open the file created with vim.fn.mkdir"
    return
  end

  -- vim.json.encode will throw
  local encode_ok, encoded_data = pcall(vim.json.encode, data)
  if encode_ok then
    file:write(encoded_data)
  else
    N.notify_error "[ff.nvim]: vim.json.encode threw"
  end

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
  local cwd = vim.uv.cwd()
  local now = F._now()

  opts._db_dir = H.default(opts._db_dir, F.default_db_dir)
  local dated_files_path = F.get_dated_files_path(opts._db_dir)
  local dated_files = F.read(dated_files_path)
  if not dated_files[cwd] then
    dated_files[cwd] = {}
  end

  local updated_date_at_score_one = (function()
    if opts.update_type == "increase" then
      local stat_result = vim.uv.fs_stat(filename)
      local readable = stat_result ~= nil and stat_result.type == "file"
      if not readable then
        return nil
      end

      local score = 0
      local date_at_score_one = dated_files[cwd][filename]
      if date_at_score_one then
        score = F.compute_score { now = now, date_at_score_one = date_at_score_one, }
      end
      local updated_score = score + 1

      return F.compute_date_at_score_one { now = now, score = updated_score, }
    end

    return nil
  end)()

  dated_files[cwd][filename] = updated_date_at_score_one
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
  file:write(content)
  file:write "\n"
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
    L.log("┌" .. content .. (" "):rep(L.LOG_LEN - #content - 2) .. "┐")
  elseif type == "middle" then
    L.log("├" .. content .. (" "):rep(L.LOG_LEN - #content - 2) .. "┤")
  elseif type == "end" then
    L.log("└" .. content .. (" "):rep(L.LOG_LEN - #content - 2) .. "┘")
  end
end

--- @param content string
L.benchmark_step_heading = function(content)
  if not L.SHOULD_LOG_STEP then return end
  L.log_line "start"
  L.log_content(content)
  L.log_line "middle"
end

L.benchmark_step_closing = function()
  if not L.SHOULD_LOG_STEP then return end
  L.log_line "end"
end

--- @param content string
L.benchmark_mean_heading = function(content)
  if not L.SHOULD_LOG_MEAN then return end
  L.log_line "start"
  L.log_content(content)
  L.log_line "middle"
end

L.benchmark_mean_closing = function()
  if not L.SHOULD_LOG_MEAN then return end
  L.log_line "end"
end

--- @type table<string, number>
L.ongoing_benchmarks = {}

--- @type table<string, number[]>
L.collected_benchmarks = {}

--- @param type "start"|"end"
--- @param label string
L.benchmark_step = function(type, label)
  if type == "start" then
    L.ongoing_benchmarks[label] = os.clock()
  else
    local end_time = os.clock()
    local start_time = L.ongoing_benchmarks[label]
    local elapsed_ms = (end_time - start_time) * 1000
    local formatted_ms = H.pad_str(H.exact_decimals(elapsed_ms, 3), 8)

    if L.SHOULD_LOG_MEAN then
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
-- just below math.huge is aprox the length of the string
-- just above -math.huge is aprox 0
P.MAX_FZY_SCORE = 20
P.MAX_FRECENCY_SCORE = 99
P.MAX_SCORE_LEN = #H.exact_decimals(P.MAX_FRECENCY_SCORE, 2)

--- @param rel_file string
--- @param score number
--- @param icon_char string|nil
P.format_filename = function(rel_file, score, icon_char)
  local formatted_score = H.pad_str(
    H.fit_decimals(score or 0, P.MAX_SCORE_LEN),
    P.MAX_SCORE_LEN
  )
  local formatted = ("%s %s%s"):format(
    formatted_score,
    icon_char and icon_char .. " " or "",
    rel_file
  )
  return formatted
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

  --- @type table<string, number>
  frecency_file_to_score = {},

  --- @type table<string, {icon_char: string, icon_hl: string|nil}>
  icon_cache = {},

  --- @type table<string, number>
  open_buffer_to_score = {},
}

P.default_fd_cmd = "fd --absolute-path --hidden --type f --exclude node_modules --exclude .git --exclude dist"

--- @param fd_cmd string
P.populate_fd_cache = function(fd_cmd)
  L.benchmark_step("start", "fd")
  local fd_handle = io.popen(fd_cmd)
  if not fd_handle then
    error "[smart.lua] fd failed!"
    return
  end

  for abs_file in fd_handle:lines() do
    table.insert(P.caches.fd_files, abs_file)
  end
  fd_handle:close()
  L.benchmark_step("end", "fd")
end

P.populate_frecency_scores_cache = function()
  L.benchmark_step("start", "Frecency dated_files fs read")
  local dated_files_path = F.get_dated_files_path()
  local dated_files = F.read(dated_files_path)
  L.benchmark_step("end", "Frecency dated_files fs read")

  local now = os.time()
  local cwd = vim.uv.cwd()
  L.benchmark_step("start", "Calculate frecency_file_to_score")
  for abs_file, date_at_score_one in ipairs(dated_files[cwd]) do
    local score = F.compute_score { now = now, date_at_score_one = date_at_score_one, }
    P.caches.frecency_file_to_score[abs_file] = score
  end
  L.benchmark_step("end", "Calculate frecency_file_to_score")
end

P.populate_open_buffers_cache = function()
  L.benchmark_step("start", "open_buffer_to_score loop")
  local cwd = vim.uv.cwd()
  for _, bufnr in pairs(vim.api.nvim_list_bufs()) do
    if not vim.api.nvim_buf_is_loaded(bufnr) then goto continue end
    if not vim.api.nvim_get_option_value("buflisted", { buf = bufnr, }) then goto continue end
    local buf_name = vim.api.nvim_buf_get_name(bufnr)
    if buf_name == nil then goto continue end
    if buf_name == "" then goto continue end
    if not vim.startswith(buf_name, cwd) then goto continue end

    P.caches.open_buffer_to_score[buf_name] = 0

    ::continue::
  end
  L.benchmark_step("end", "open_buffer_to_score loop")
end

--- @class GetSmartFilesOpts
--- @field query string
--- @field results_buf number
--- @field curr_bufname string
--- @field alt_bufname string
--- @field curr_tick number
--- @field callback function
--- @field weights FindWeights
--- @field batch_size number
--- @field icons_enabled boolean
--- @field hi_enabled boolean
--- @field max_results number
--- @field min_matched_chars number
--- @field fuzzy_score_multiple number
--- @field file_score_multiple number

--- @param opts GetSmartFilesOpts
P.get_find_files = function(opts)
  local fzy = require "fzy-lua-native"
  opts.query = opts.query:gsub("%s+", "") -- fzy doesn't ignore spaces
  L.benchmark_step_heading(("query: '%s'"):format(opts.query))
  L.benchmark_step("start", "Entire script")

  --- @class AnnotatedFile
  --- @field file string
  --- @field score number
  --- @field hl_idxs table
  --- @field icon_char string
  --- @field icon_hl string

  --- @type AnnotatedFile[]
  local weighted_files = {}

  local process_files = coroutine.create(function()
    -- TODO: change type, only need file and score
    --- @type AnnotatedFile[]
    local fuzzy_files = {}
    L.benchmark_step("start", "Calculate fuzzy_files with fd")
    for idx, abs_file in ipairs(P.caches.fd_files) do
      if opts.query == "" then
        if idx <= opts.max_results then
          table.insert(fuzzy_files, {
            file = abs_file,
            score = 0,
            hl_idxs = {},
            icon_char = nil,
            icon_hl = nil,
          })
        end
      else
        local rel_file = H.get_rel_file(abs_file)
        if fzy.has_match(opts.query, rel_file) then
          local fzy_score = fzy.score(opts.query, rel_file)

          if fzy_score >= opts.min_matched_chars then
            local scaled_fzy_score = P.scale_fzy_to_frecency(fzy_score)
            local hl_idxs = {}
            if opts.hi_enabled then
              hl_idxs = fzy.positions(opts.query, rel_file)
            end

            table.insert(fuzzy_files,
              {
                file = abs_file,
                score = scaled_fzy_score,
                hl_idxs = hl_idxs,
                icon_char = nil,
                icon_hl = nil,
              })
          end
        end
      end

      if idx % opts.batch_size == 0 then
        coroutine.yield()
      end

      ::continue::
    end
    L.benchmark_step("end", "Calculate fuzzy_files with fd")

    local mini_icons = require "mini.icons"
    L.benchmark_step("start", "Calculate weighted_files")
    for idx, fuzzy_entry in ipairs(fuzzy_files) do
      local buf_score = 0

      local abs_file = fuzzy_entry.file
      local basename_with_ext = H.basename(abs_file, { with_ext = true, })
      local basename_without_ext = H.basename(abs_file, { with_ext = false, })

      if opts.query == basename_with_ext or opts.query == basename_without_ext then
        buf_score = opts.weights.basename_boost
      elseif P.caches.open_buffer_to_score[abs_file] ~= nil then
        local bufnr = vim.fn.bufnr(abs_file)
        local modified = vim.api.nvim_get_option_value("modified", { buf = bufnr, })

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

      local frecency_and_buf_score = buf_score
      if P.caches.frecency_file_to_score[abs_file] ~= nil then
        frecency_and_buf_score = frecency_and_buf_score + P.caches.frecency_file_to_score[abs_file]
      end

      local weighted_score =
          opts.fuzzy_score_multiple * fuzzy_entry.score +
          opts.file_score_multiple * frecency_and_buf_score

      local rel_file = H.get_rel_file(abs_file)
      local icon_char = nil
      local icon_hl = nil

      local ext = H.get_ext(rel_file)
      if opts.icons_enabled then
        if P.caches.icon_cache[ext] then
          icon_char = P.caches.icon_cache[ext].icon_char
          icon_hl = P.caches.icon_cache[ext].icon_hl
        else
          local _, icon_char_res, icon_hl_res = pcall(mini_icons.get, "file", rel_file)
          icon_char = icon_char_res or "?"
          icon_hl = icon_hl_res or nil
          if ext then
            P.caches.icon_cache[ext] = { icon_char = icon_char_res or "?", icon_hl = icon_hl, }
          end
        end
      end

      table.insert(
        weighted_files,
        {
          file = rel_file,
          score = weighted_score,
          hl_idxs = fuzzy_entry.hl_idxs,
          icon_hl = icon_hl,
          icon_char = icon_char,
        }
      )

      if idx % opts.batch_size == 0 then
        coroutine.yield()
      end
    end
    L.benchmark_step("end", "Calculate weighted_files")

    L.benchmark_step("start", "Sort weighted_files")
    table.sort(weighted_files, function(a, b)
      return a.score > b.score
    end)
    L.benchmark_step("end", "Sort weighted_files")

    L.benchmark_step("start", "Format weighted_files")
    --- @type string[]
    local formatted_files = {}
    for idx, weighted_entry in ipairs(weighted_files) do
      if idx > opts.max_results then break end

      local formatted = P.format_filename(weighted_entry.file, weighted_entry.score, weighted_entry.icon_char)
      table.insert(formatted_files, formatted)
      if idx % opts.batch_size == 0 then
        coroutine.yield()
      end
    end
    L.benchmark_step("end", "Format weighted_files")

    L.benchmark_step("start", "Callback")
    opts.callback(formatted_files)
    L.benchmark_step("end", "Callback")

    if not opts.hi_enabled then
      L.benchmark_step("end", "Entire script")
      L.benchmark_step_closing()
      return
    end

    local formatted_score_last_idx = #H.pad_str(
      H.fit_decimals(P.MAX_FRECENCY_SCORE, P.MAX_SCORE_LEN),
      P.MAX_SCORE_LEN
    )
    local icon_char_idx = formatted_score_last_idx + 2

    L.benchmark_step("start", "Highlight loop")
    for idx, formatted_file in ipairs(formatted_files) do
      local row_0_indexed = idx - 1

      if weighted_files[idx].icon_hl then
        local icon_hl_col_1_indexed = icon_char_idx
        local icon_hl_col_0_indexed = icon_hl_col_1_indexed - 1

        vim.hl.range(
          opts.results_buf,
          P.ns_id,
          weighted_files[idx].icon_hl,
          { row_0_indexed, icon_hl_col_0_indexed, },
          { row_0_indexed, icon_hl_col_0_indexed + 1, }
        )
      end

      local file_offset = #formatted_file - formatted_file:reverse():find " " + 1
      for _, hl_idx in ipairs(weighted_files[idx].hl_idxs) do
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
    L.benchmark_step("end", "Highlight loop")
    L.benchmark_step("end", "Entire script")
    L.benchmark_step_closing()
  end)

  local function continue_processing()
    if P.tick ~= opts.curr_tick then return end
    coroutine.resume(process_files)

    if coroutine.status(process_files) == "suspended" then
      vim.schedule(continue_processing)
    end
  end

  continue_processing()
end

--- @class SetupOpts
--- @field refresh_fd_cache? "module-load"|"find-call"
--- @field refresh_frecency_scores_cache? "module-load"|"find-call"
--- @field refresh_open_buffers_cache? "module-load"|"find-call"
--- @field benchmark_step? boolean
--- @field benchmark_mean? boolean
--- @field fd_cmd? string

P.setup_opts = {}
P.setup_opts_defaults = {
  refresh_fd_cache = "module-load",
  refresh_frecency_scores_cache = "find-call",
  refresh_open_buffers_cache = "find-call",
}

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
  opts.refresh_fd_cache = H.default(
    opts.refresh_fd_cache,
    P.setup_opts_defaults.refresh_fd_cache
  )
  opts.refresh_frecency_scores_cache = H.default(
    opts.refresh_frecency_scores_cache,
    P.setup_opts_defaults.refresh_frecency_scores_cache
  )
  opts.refresh_open_buffers_cache = H.default(
    opts.refresh_open_buffers_cache,
    P.setup_opts_defaults.refresh_open_buffers_cache
  )
  P.setup_opts = opts

  L.benchmark_step_heading "Populate file-level caches"
  if opts.refresh_fd_cache == "module-load" then
    P.populate_fd_cache(opts.fd_cmd)
  end
  if opts.refresh_frecency_scores_cache == "module-load" then
    P.populate_frecency_scores_cache()
  end
  if opts.refresh_open_buffers_cache == "module-load" then
    P.populate_open_buffers_cache()
  end
  L.benchmark_step_closing()

  vim.api.nvim_create_autocmd({ "BufWinEnter", }, {
    group = vim.api.nvim_create_augroup("FF", { clear = true, }),
    callback = function(ev)
      local current_win = vim.api.nvim_get_current_win()
      -- :h nvim_win_get_config({window}) "relative is empty for normal buffers"
      if vim.api.nvim_win_get_config(current_win).relative == "" then
        -- `nvim_buf_get_name` for unnamed buffers is an empty string
        local bname = vim.api.nvim_buf_get_name(ev.buf)
        if #bname > 0 then F.update_file_score(bname, { update_type = "increase", }) end
      end
    end,
  })
  vim.api.nvim_set_hl(0, "FFPickerFuzzyHighlightChar", { link = "Search", })
  vim.api.nvim_set_hl(0, "FFPickerCursorLine", { link = "CursorLine", })
end

--- @param fd_cmd? string
M.refresh_fd_cache = function(fd_cmd)
  if not P.setup_called then
    N.notify_error "[ff.nvim]: `setup` must be called before `refresh_fd_cache`"
  end
  fd_cmd = H.default(fd_cmd, P.setup_opts.fd_cmd)
  P.populate_fd_cache(fd_cmd)
end

--- @class FindOpts
--- @field keymaps? FindKeymapsPerMode
--- @field weights? FindWeights
--- @field batch_size? number
--- @field icons_enabled? boolean
--- @field hi_enabled? boolean
--- @field max_results? number
--- @field min_matched_chars? number
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
    N.notify_error "[ff.nvim]: `setup` must be called before `find`"
    return
  end
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
  opts.icons_enabled = H.default(opts.icons_enabled, true)
  opts.hi_enabled = H.default(opts.hi_enabled, true)
  opts.max_results = H.default(opts.max_results, 200)
  opts.min_matched_chars = H.default(opts.min_matched_chars, 2)
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

  --- @param formatted_result string
  local function parse_result(formatted_result)
    return vim.split(vim.trim(formatted_result), "%s+")[opts.icons_enabled and 3 or 2]
  end

  --- @param query string
  local function get_find_files_with_query(query)
    P.get_find_files {
      query = query,
      results_buf = results_buf,
      curr_bufname = curr_bufname or "",
      alt_bufname = alt_bufname or "",
      curr_tick = P.tick,
      weights = opts.weights,
      batch_size = opts.batch_size,
      hi_enabled = opts.hi_enabled,
      icons_enabled = opts.icons_enabled,
      max_results = opts.max_results,
      min_matched_chars = opts.min_matched_chars,
      fuzzy_score_multiple = opts.fuzzy_score_multiple,
      file_score_multiple = opts.file_score_multiple,
      callback = function(results)
        vim.api.nvim_buf_set_lines(results_buf, 0, -1, false, results)
      end,
    }
  end

  vim.schedule(
    function()
      L.benchmark_step_heading "Populate function-level caches"
      if P.setup_opts.refresh_fd_cache == "find-call" then
        P.populate_fd_cache(P.setup_opts.fd_cmd)
      end
      if P.setup_opts.refresh_frecency_scores_cache == "find-call" then
        P.populate_frecency_scores_cache()
      end
      if P.setup_opts.refresh_open_buffers_cache == "find-call" then
        P.populate_open_buffers_cache()
      end
      L.benchmark_step_closing()

      get_find_files_with_query ""
    end
  )

  local function close()
    L.benchmark_mean_heading "Mean benchmarks"
    L.benchmark_mean()
    L.benchmark_mean_closing()
    L.ongoing_benchmarks = {}
    L.collected_benchmarks = {}

    vim.api.nvim_win_close(input_win, true)
    vim.api.nvim_win_close(results_win, true)
    vim.cmd "stopinsert"
  end

  local current_line = 1
  local keymap_fns = {
    select = function()
      vim.api.nvim_set_current_win(results_win)
      local result = vim.api.nvim_get_current_line()
      close()
      H.pcall_edit(parse_result(result))
    end,
    next = function()
      vim.api.nvim_win_call(results_win, function()
        if current_line == vim.api.nvim_buf_line_count(results_buf) then
          current_line = 1
          vim.cmd "normal! gg"
        else
          current_line = current_line + 1
          vim.cmd "normal! j"
        end
        vim.hl.range(results_buf, P.ns_id, "Search",
          { current_line, vim.o.columns, },
          { current_line, vim.o.columns, },
          { inclusive = true, }
        )
      end)
    end,
    prev = function()
      vim.api.nvim_win_call(results_win, function()
        if current_line == 1 then
          current_line = vim.api.nvim_buf_line_count(results_buf)
          vim.cmd "normal! G"
        else
          current_line = current_line - 1
          vim.cmd "normal! k"
        end
        vim.hl.range(results_buf, P.ns_id, "Search",
          { current_line, vim.o.columns, },
          { current_line, vim.o.columns, },
          { inclusive = true, }
        )
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
    group = vim.api.nvim_create_augroup("ff", { clear = true, }),
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
    N = N,
    F = F,
    L = L,
    P = P,
  }
end

M.find = P.find
return M
