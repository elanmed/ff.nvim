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

--- @param file string
H.get_extension = function(file)
  local dot_pos = file:find "%.[^.]+$"

  if dot_pos then
    return file:sub(dot_pos + 1)
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

H.vimscript_true = 1
H.vimscript_false = 0

-- ======================================================
-- == Notify ============================================
-- ======================================================

local N = {}

--- @param level vim.log.levels
--- @param msg string
--- @param ... any
N._notify = function(level, msg, ...)
  msg = msg or ""
  msg = "[fzf-lua-frecency]: " .. msg

  local rest = ...
  vim.notify(msg:format(rest), level)
end

--- @param msg string
--- @param ... any
N.notify_error = function(msg, ...)
  N._notify(vim.log.levels.ERROR, msg, ...)
end

--- @param msg string
--- @param ... any
N.notify_debug = function(msg, ...)
  N._notify(vim.log.levels.DEBUG, msg, ...)
end

-- ======================================================
-- == Frecency ==========================================
-- ======================================================

local F = {}
F.default_db_dir = vim.fs.joinpath(vim.fn.stdpath "data", "ff")

--- @param db_dir? string
F.get_sorted_files_path = function(db_dir)
  db_dir = H.default(db_dir, F.default_db_dir)
  return vim.fs.joinpath(db_dir, "sorted-files.txt")
end

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
    N.notify_error("ERROR: vim.json.decode threw: %s", decoded_data)
    return {}
  end
  return decoded_data
end

--- @class WriteOpts
--- @field path string
--- @field data table | string | number
--- @field encode boolean

--- @param opts WriteOpts
--- @return nil
F.write = function(opts)
  -- vim.fn.mkdir won't throw
  local path_dir = vim.fs.dirname(opts.path)
  local mkdir_res = vim.fn.mkdir(path_dir, "p")
  if mkdir_res == H.vimscript_false then
    N.notify_error "ERROR: vim.fn.mkdir returned vimscript_false"
    return
  end

  -- io.open won't throw
  local file = io.open(opts.path, "w")
  if file == nil then
    N.notify_error("ERROR: io.open failed to open the file created with vim.fn.mkdir at path: %s", opts.path)
    return
  end

  if opts.encode then
    -- vim.json.encode will throw
    local encode_ok, encoded_data = pcall(vim.json.encode, opts.data)
    if encode_ok then
      file:write(encoded_data)
    else
      N.notify_error("ERROR: vim.json.encode threw: %s", encoded_data)
    end
  else
    file:write(opts.data)
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

--- @class ScoredFile
--- @field score number
--- @field filename string

--- @class UpdateFileScoreOpts
--- @field update_type "increase" | "remove"
--- @field db_dir? string

--- @param filename string
--- @param opts UpdateFileScoreOpts
F.update_file_score = function(filename, opts)
  local now = F._now()

  local db_dir = H.default(opts.db_dir, F.default_db_dir)
  local sorted_files_path = F.get_sorted_files_path(db_dir)
  local dated_files_path = F.get_dated_files_path(db_dir)
  local dated_files = F.read(dated_files_path)

  local updated_date_at_score_one = (function()
    if opts.update_type == "increase" then
      local stat_result = vim.uv.fs_stat(filename)
      local readable = stat_result ~= nil and stat_result.type == "file"
      if not readable then
        return nil
      end

      local score = 0
      local date_at_score_one = dated_files[filename]
      if date_at_score_one then
        score = F.compute_score { now = now, date_at_score_one = date_at_score_one, }
      end
      local updated_score = score + 1

      return F.compute_date_at_score_one { now = now, score = updated_score, }
    end

    return nil
  end)()

  dated_files[filename] = updated_date_at_score_one
  F.write { path = dated_files_path, data = dated_files, encode = true, }

  --- @type ScoredFile[]
  local scored_files = {}
  local updated_dated_files = {}
  for dated_file_entry, date_at_one_point_entry in pairs(dated_files) do
    local recomputed_score = F.compute_score { now = now, date_at_score_one = date_at_one_point_entry, }

    local stat_result = vim.uv.fs_stat(dated_file_entry)
    local readable = stat_result ~= nil and stat_result.type == "file"
    if readable then
      table.insert(scored_files, { filename = dated_file_entry, score = recomputed_score, })
      updated_dated_files[dated_file_entry] = date_at_one_point_entry
    end
  end

  F.write {
    data = updated_dated_files,
    path = dated_files_path,
    encode = true,
  }

  table.sort(scored_files, function(a, b)
    return a.score > b.score
  end)

  local scored_files_list = {}
  for _, scored_file in pairs(scored_files) do
    table.insert(scored_files_list, scored_file.filename)
  end
  local sorted_files_str = table.concat(scored_files_list, "\n")
  if #sorted_files_str > 0 then
    sorted_files_str = sorted_files_str .. "\n"
  end

  F.write {
    path = sorted_files_path,
    data = sorted_files_str,
    encode = false,
  }
end

-- ======================================================
-- == Bencharking =======================================
-- ======================================================

local L = {}
local LOG = true

--- @param content string
L.log = function(content)
  local file = io.open("log.txt", "a")
  if not file then return end
  file:write(content)
  file:write "\n"
  file:close()
end

L.LOG_LEN = 50

--- @param type "start"|"middle"|"end"
L.benchmark_line = function(type)
  if not LOG then return end

  if type == "start" then
    L.log("┌" .. ("─"):rep(L.LOG_LEN - 2) .. "┐")
  elseif type == "middle" then
    L.log("├" .. ("─"):rep(L.LOG_LEN - 2) .. "┤")
  else
    L.log("└" .. ("─"):rep(L.LOG_LEN - 2) .. "┘")
  end
end


--- @param content string
L.benchmark_start = function(content)
  if not LOG then return end

  L.benchmark_line "start"
  L.log("│" .. content .. (" "):rep(L.LOG_LEN - #content - 2) .. "│")
  L.benchmark_line "middle"
end

L.ongoing_benchmarks = {}
--- @param type "start"|"end"
--- @param label string
L.benchmark = function(type, label)
  if not LOG then return end

  if type == "start" then
    L.ongoing_benchmarks[label] = os.clock()
  else
    local end_time = os.clock()
    local start_time = L.ongoing_benchmarks[label]
    local elapsed_ms = (end_time - start_time) * 1000
    local content = ("%.3f : %s"):format(elapsed_ms, label)
    L.log("│" .. content .. (" "):rep(L.LOG_LEN - #content - 2) .. "│")
  end
end

-- ======================================================
-- == Picker =======================================
-- ======================================================

local tick = 0

local mini_icons = require "mini.icons"
local fzy = require "fzy-lua-native"
local ns_id = vim.api.nvim_create_namespace "SmartHighlight"

local P = {}

P.weights = {
  OPEN_BUF_BOOST = 10,
  CHANGED_BUF_BOOST = 20,
  ALT_BUF_BOOST = 30,
  CURR_BUF_BOOST = -1000,
}

local ICONS_ENABLED = true
local HL_ENABLED = true
P.BATCH_SIZE = 250

-- [-math.huge, math.huge]
-- just below math.huge is aprox the length of the string
-- just above -math.huge is aprox 0
P.MAX_FZY_SCORE = 20
P.MAX_FRECENCY_SCORE = 99

P.max_score_len = #H.exact_decimals(P.MAX_FRECENCY_SCORE, 2)
P.icon_char_idx = (function()
  local formatted_score_last_idx = #H.pad_str(
    H.fit_decimals(P.MAX_FRECENCY_SCORE, P.max_score_len),
    P.max_score_len
  )
  return formatted_score_last_idx + 2
end)()

--- @param rel_file string
--- @param score number
--- @param icon string
P.format_filename = function(rel_file, score, icon)
  local formatted_score = H.pad_str(
    H.fit_decimals(score or 0, P.max_score_len),
    P.max_score_len
  )
  local formatted = ("%s %s|%s"):format(formatted_score, icon, rel_file)
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

  --- @type string[]
  frecency_files = {},

  --- @type table<string, number>
  frecency_file_to_score = {},

  --- @type table<string, {icon_char: string, icon_hl: string|nil}>
  icon_cache = {},

  --- @type table<string, number>
  open_buffer_to_score = {},
}

P.populate_fd_cache = function()
  L.benchmark("start", "fd")
  local fd_cmd = "fd --absolute-path --hidden --type f --exclude node_modules --exclude .git --exclude dist"
  local fd_handle = io.popen(fd_cmd)
  if not fd_handle then
    error "[smart.lua] fd failed!"
    return
  end

  for abs_file in fd_handle:lines() do
    table.insert(P.caches.fd_files, abs_file)
  end
  fd_handle:close()
  L.benchmark("end", "fd")
end

P.populate_frecency_files_cwd_cache = function()
  --- @type string
  local cwd = vim.uv.cwd()
  local sorted_files_path = F.get_sorted_files_path()

  L.benchmark("start", "sorted_files_path fs read")
  if vim.fn.filereadable(sorted_files_path) == H.vimscript_false then
    return
  end

  for abs_file in io.lines(sorted_files_path) do
    if not vim.startswith(abs_file, cwd) then goto continue end
    if vim.fn.filereadable(abs_file) == H.vimscript_false then goto continue end

    table.insert(P.caches.frecency_files, abs_file)

    ::continue::
  end
  L.benchmark("end", "sorted_files_path fs read")
end

P.populate_frecency_scores_cache = function()
  L.benchmark("start", "dated_files fs read")
  local dated_files_path = F.get_dated_files_path()
  local dated_files = F.read(dated_files_path)
  L.benchmark("end", "dated_files fs read")

  local now = os.time()
  L.benchmark("start", "calculate frecency_file_to_score")
  for _, abs_file in ipairs(P.caches.frecency_files) do
    local date_at_score_one = dated_files[abs_file]
    local score = F.compute_score { now = now, date_at_score_one = date_at_score_one, }
    P.caches.frecency_file_to_score[abs_file] = score
  end
  L.benchmark("end", "calculate frecency_file_to_score")
end

P.populate_open_buffers_cache = function()
  L.benchmark("start", "open_buffer_to_score loop")
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
  L.benchmark("end", "open_buffer_to_score loop")
end

--- @class GetSmartFilesOpts
--- @field query string
--- @field results_buf number
--- @field curr_bufname string
--- @field alt_bufname string
--- @field curr_tick number

--- @param opts GetSmartFilesOpts
--- @param callback function
P.get_smart_files = function(opts, callback)
  local query = opts.query:gsub("%s+", "") -- fzy doesn't ignore spaces
  L.benchmark_start(("query: '%s'"):format(query))
  L.benchmark("start", "entire script")

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
    L.benchmark("start", "calculate fuzzy_files")
    for idx, abs_file in ipairs(P.caches.fd_files) do
      if query == "" then
        table.insert(fuzzy_files, {
          file = abs_file,
          score = 0,
          hl_idxs = {},
          icon_char = "",
          icon_hl = nil,
        })
      else
        local rel_file = H.get_rel_file(abs_file)
        if fzy.has_match(query, rel_file) then
          local fzy_score = fzy.score(query, rel_file)
          local scaled_fzy_score = P.scale_fzy_to_frecency(fzy_score)
          local hl_idxs = {}
          if HL_ENABLED then
            hl_idxs = fzy.positions(query, rel_file)
          end

          table.insert(fuzzy_files,
            {
              file = abs_file,
              score = scaled_fzy_score,
              hl_idxs = hl_idxs,
              icon_char = "",
              icon_hl = nil,
            })
        end
      end

      if idx % P.BATCH_SIZE == 0 then
        coroutine.yield()
      end
    end
    L.benchmark("end", "calculate fuzzy_files")

    L.benchmark("start", "calculate weighted_files")
    for idx, fuzzy_entry in ipairs(fuzzy_files) do
      local buf_score = 0

      local abs_file = fuzzy_entry.file

      if P.caches.open_buffer_to_score[abs_file] ~= nil then
        local bufnr = vim.fn.bufnr(abs_file)
        local modified = vim.api.nvim_get_option_value("modified", { buf = bufnr, })

        if abs_file == opts.curr_bufname then
          buf_score = P.weights.CURR_BUF_BOOST
        elseif abs_file == opts.alt_bufname then
          buf_score = P.weights.ALT_BUF_BOOST
        elseif modified then
          buf_score = P.weights.CHANGED_BUF_BOOST
        else
          buf_score = P.weights.OPEN_BUF_BOOST
        end
      end

      local frecency_and_buf_score = buf_score
      if P.caches.frecency_file_to_score[abs_file] ~= nil then
        frecency_and_buf_score = frecency_and_buf_score + P.caches.frecency_file_to_score[abs_file]
      end

      local weighted_score = 0.7 * fuzzy_entry.score + 0.3 * frecency_and_buf_score

      local rel_file = H.get_rel_file(abs_file)
      local icon_char = ""
      local icon_hl = nil

      local ext = H.get_extension(rel_file)
      if ICONS_ENABLED then
        if P.caches.icon_cache[ext] then
          icon_char = P.caches.icon_cache[ext].icon_char .. " "
          icon_hl = P.caches.icon_cache[ext].icon_hl
        else
          local _, icon_char_res, icon_hl_res = pcall(mini_icons.get, "file", rel_file)
          icon_char = (icon_char_res or "?") .. " "
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

      if idx % P.BATCH_SIZE == 0 then
        coroutine.yield()
      end
    end
    L.benchmark("end", "calculate weighted_files")

    L.benchmark("start", "sort weighted_files")
    table.sort(weighted_files, function(a, b)
      return a.score > b.score
    end)
    L.benchmark("end", "sort weighted_files")

    L.benchmark("start", "format weighted_files")
    --- @type string[]
    local formatted_files = {}
    for idx, weighted_entry in ipairs(weighted_files) do
      if idx > 200 then break end

      local formatted = P.format_filename(weighted_entry.file, weighted_entry.score, weighted_entry.icon_char)
      table.insert(formatted_files, formatted)
      if idx % P.BATCH_SIZE == 0 then
        coroutine.yield()
      end
    end
    L.benchmark("end", "format weighted_files")

    L.benchmark("start", "callback")
    callback(formatted_files)
    L.benchmark("end", "callback")

    if not HL_ENABLED then
      L.benchmark("end", "entire script")
      L.benchmark_line "end"
      return
    end

    L.benchmark("start", "highlight loop")
    for idx, formatted_file in ipairs(formatted_files) do
      local row_0_indexed = idx - 1

      if weighted_files[idx].icon_hl then
        local icon_hl_col_1_indexed = P.icon_char_idx
        local icon_hl_col_0_indexed = icon_hl_col_1_indexed - 1

        vim.hl.range(
          opts.results_buf,
          ns_id,
          weighted_files[idx].icon_hl,
          { row_0_indexed, icon_hl_col_0_indexed, },
          { row_0_indexed, icon_hl_col_0_indexed + 1, }
        )
      end

      local file_offset = string.find(formatted_file, "|")
      for _, hl_idx in ipairs(weighted_files[idx].hl_idxs) do
        local file_char_hl_col_0_indexed = hl_idx + file_offset - 1

        vim.hl.range(
          opts.results_buf,
          ns_id,
          "SmartFilesFuzzyHighlightIdx",
          { row_0_indexed, file_char_hl_col_0_indexed, },
          { row_0_indexed, file_char_hl_col_0_indexed + 1, }
        )
      end

      if idx % P.BATCH_SIZE == 0 then
        coroutine.yield()
      end
    end
    L.benchmark("end", "highlight loop")
    L.benchmark("end", "entire script")
    L.benchmark_line "end"
  end)

  local function continue_processing()
    if tick ~= opts.curr_tick then return end
    coroutine.resume(process_files)

    if coroutine.status(process_files) == "suspended" then
      vim.schedule(continue_processing)
    end
  end

  continue_processing()
end

--- @class FFSetupOpts
--- @field refresh_fd_cache "module-load"|"find-call"
--- @field refresh_frecency_scores_cache "module-load"|"find-call"
--- @field refresh_open_buffers_cache "module-load"|"find-call"

F.setup_opts = {}
F.setup_opts_defaults = {
  refresh_fd_cache = "module-load",
  refresh_frecency_scores_cache = "find-call",
  refresh_open_buffers_cache = "find-call",
}

F.setup_called = false

--- @param opts? FFSetupOpts
M.setup = function(opts)
  if F.setup_called then return end
  F.setup_called = true

  opts = H.default(opts, {})
  opts.refresh_fd_cache = H.default(
    opts.refresh_fd_cache,
    F.setup_opts_defaults.refresh_fd_cache
  )
  opts.refresh_frecency_scores_cache = H.default(
    opts.refresh_frecency_scores_cache,
    F.setup_opts_defaults.refresh_frecency_scores_cache
  )
  opts.refresh_open_buffers_cache = H.default(
    opts.refresh_open_buffers_cache,
    F.setup_opts_defaults.refresh_open_buffers_cache
  )
  F.setup_opts = opts

  L.benchmark_start "Populate file-level caches"
  if opts.refresh_fd_cache == "module-load" then
    P.populate_fd_cache()
    P.populate_frecency_files_cwd_cache()
  end
  if opts.refresh_frecency_scores_cache == "module-load" then
    P.populate_frecency_scores_cache()
  end
  if opts.refresh_open_buffers_cache == "module-load" then
    P.populate_open_buffers_cache()
  end
  L.benchmark_line "end"

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
end

L.benchmark_start "Populate file-level caches"
P.populate_fd_cache()
P.populate_frecency_files_cwd_cache()
L.benchmark_line "end"

--- @class FFFindOpts
--- @field keymaps FFFindKeymaps

--- @class FFFindKeymaps
--- @field i FFFindKeymap
--- @field n FFFindKeymap

--- @class FFFindKeymap
--- @field [string] "select"|"next"|"prev"|"close"|function

--- @param opts? FFFindOpts
P.find = function(opts)
  if not F.setup_called then
    error "[ff.nvim] `setup` must be called before `find`!"
  end
  opts = H.default(opts, {})
  opts.keymaps = H.default(opts.keymaps, {})
  opts.keymaps.i = H.default(opts.keymaps.i, {})
  opts.keymaps.n = H.default(opts.keymaps.n, {})

  local _, curr_bufname = pcall(vim.api.nvim_buf_get_name, 0)
  local _, alt_bufname = pcall(vim.api.nvim_buf_get_name, vim.fn.bufnr "#")

  vim.cmd "new"
  local results_buf = vim.api.nvim_get_current_buf()
  local results_win = vim.api.nvim_get_current_win()
  vim.bo.buftype = "nofile"
  vim.bo.buflisted = false
  vim.api.nvim_buf_set_name(results_buf, "Results")

  vim.cmd "new"
  vim.cmd "resize 1"
  local input_buf = vim.api.nvim_get_current_buf()
  local input_win = vim.api.nvim_get_current_win()
  vim.bo.buftype = "nofile"
  vim.bo.buflisted = false
  vim.api.nvim_buf_set_name(input_buf, "Input")

  vim.cmd "startinsert"

  vim.schedule(
    function()
      L.benchmark_start "Populate function-level caches"
      if F.setup_opts.refresh_fd_cache == "find-call" then
        P.populate_fd_cache()
        P.populate_frecency_files_cwd_cache()
      end
      if F.setup_opts.refresh_frecency_scores_cache == "find-call" then
        P.populate_frecency_scores_cache()
      end
      if F.setup_opts.refresh_open_buffers_cache == "find-call" then
        P.populate_open_buffers_cache()
      end
      L.benchmark_line "end"

      P.get_smart_files({
        query = "",
        results_buf = results_buf,
        curr_bufname = curr_bufname or "",
        alt_bufname = alt_bufname or "",
        curr_tick = tick,
      }, function(results)
        vim.api.nvim_buf_set_lines(results_buf, 0, -1, false, results)
      end)
    end
  )

  local function close()
    local force = true
    vim.api.nvim_buf_delete(input_buf, { force = force, })
    vim.api.nvim_buf_delete(results_buf, { force = force, })
  end

  local keymap_fns = {
    select = function()
      vim.api.nvim_set_current_win(results_win)
      local entry = vim.api.nvim_get_current_line()
      local file = vim.split(entry, "|")[2]

      close()
      vim.cmd("edit " .. file)
      vim.cmd "stopinsert"
    end,
    next = function()
      vim.api.nvim_set_current_win(results_win)
      vim.cmd "normal! j"
      vim.api.nvim_set_current_win(input_win)
    end,
    prev = function()
      vim.api.nvim_set_current_win(results_win)
      vim.cmd "normal! k"
      vim.api.nvim_set_current_win(input_win)
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

  vim.api.nvim_set_option_value("winhighlight", "CursorLine:SmartFilesResultsCursor", { win = results_win, })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", }, {
    buffer = input_buf,
    callback = function()
      tick = tick + 1
      vim.schedule(function()
        local query = vim.api.nvim_get_current_line()
        P.get_smart_files({
          query = query,
          results_buf = results_buf,
          curr_bufname = curr_bufname or "",
          alt_bufname = alt_bufname or "",
          curr_tick = tick,
        }, function(results)
          vim.api.nvim_buf_set_lines(results_buf, 0, -1, false, results)
        end)
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
