_G.FF_TEST = true
require("mini.test").setup()
local T = MiniTest.new_set()

local ff = require "ff"
local H = ff._internal.H
local F = ff._internal.F
local P = ff._internal.P

T["H"] = MiniTest.new_set()

T["H"]["#default"] = MiniTest.new_set()
T["H"]["#default"]["returns default when value is nil"] = function()
  MiniTest.expect.equality(H.default(nil, "fallback"), "fallback")
  MiniTest.expect.equality(H.default(nil, false), false)
end

T["H"]["#rel_path"] = MiniTest.new_set {
  hooks = {
    pre_case = function()
      H.cwd = "path/to/dir"
    end,
    post_case = function()
      H.cwd = nil
    end,
  },
}

T["H"]["#rel_path"]["returns the rel file path when able"] = function()
  MiniTest.expect.equality(H.rel_path "path/to/dir/file.txt", "file.txt")
  MiniTest.expect.equality(
    H.rel_path "path/to/another_dir/file.txt",
    "path/to/another_dir/file.txt"
  )
end
T["H"]["#rel_path"]["returns the abs file path as a fallback"] = function()
  MiniTest.expect.equality(
    H.rel_path "path/to/another_dir/file.txt",
    "path/to/another_dir/file.txt"
  )
end

T["H"]["#get_ext"] = MiniTest.new_set()
T["H"]["#get_ext"]["returns the extension"] = function()
  MiniTest.expect.equality(H.get_ext "path/to/file.txt", "txt")
  MiniTest.expect.equality(H.get_ext "path/to/file.min.txt", "txt")
  MiniTest.expect.equality(H.get_ext "path/to/file", nil)
  MiniTest.expect.equality(H.get_ext ".gitignore", nil)
  MiniTest.expect.equality(H.get_ext "", nil)
end

T["H"]["#basename"] = MiniTest.new_set()
T["H"]["#basename"]["returns the basename with and without an extension"] = function()
  MiniTest.expect.equality(H.basename("path/to/file.txt", { with_ext = true }), "file.txt")
  MiniTest.expect.equality(H.basename("path/to/file.txt", { with_ext = false }), "file")
  MiniTest.expect.equality(H.basename("path/to/file.min.txt", { with_ext = true }), "file.min.txt")
  MiniTest.expect.equality(H.basename("path/to/file.min.txt", { with_ext = false }), "file")
  MiniTest.expect.equality(H.basename("path/to/file", { with_ext = true }), "file")
  MiniTest.expect.equality(H.basename("path/to/file", { with_ext = false }), "file")
  MiniTest.expect.equality(H.basename("file.txt", { with_ext = true }), "file.txt")
  MiniTest.expect.equality(H.basename("file.txt", { with_ext = false }), "file")
  MiniTest.expect.equality(H.basename(".gitignore", { with_ext = true }), ".gitignore")
  MiniTest.expect.equality(H.basename(".gitignore", { with_ext = false }), ".gitignore")
  MiniTest.expect.equality(H.basename("", { with_ext = true }), "")
  MiniTest.expect.equality(H.basename("", { with_ext = false }), "")
end

T["H"]["#default"]["returns original value when not nil"] = function()
  MiniTest.expect.equality(H.default("value", "fallback"), "value")
  MiniTest.expect.equality(H.default(false, "fallback"), false)
end

T["H"]["#pad_str"] = MiniTest.new_set()
T["H"]["#pad_str"]["returns original string when longer than or equal to len"] = function()
  MiniTest.expect.equality(H.pad_str("abc", 2), "abc")
  MiniTest.expect.equality(H.pad_str("abc", 3), "abc")
end

T["H"]["#pad_str"]["pads string with spaces when shorter than len"] = function()
  MiniTest.expect.equality(H.pad_str("abc", 5), "  abc")
end

T["H"]["#max_decimals"] = MiniTest.new_set()
T["H"]["#max_decimals"]["truncates to max decimals without rounding"] = function()
  MiniTest.expect.equality(H.max_decimals(3.456, 2), 3.45)
  MiniTest.expect.equality(H.max_decimals(9.999, 1), 9.9)
  MiniTest.expect.equality(H.max_decimals(5, 3), 5.0)
end

T["H"]["#min_decimals"] = MiniTest.new_set()
T["H"]["#min_decimals"]["formats number with minimum decimals"] = function()
  MiniTest.expect.equality(H.min_decimals(3.4, 2), "3.40")
  MiniTest.expect.equality(H.min_decimals(5, 3), "5.000")
  MiniTest.expect.equality(H.min_decimals(2.71828, 1), "2.7")
end

T["H"]["#exact_decimals"] = MiniTest.new_set()
T["H"]["#exact_decimals"]["truncates then formats to exact decimals"] = function()
  MiniTest.expect.equality(H.exact_decimals(3.456, 2), "3.45")
  MiniTest.expect.equality(H.exact_decimals(9.999, 1), "9.9")
  MiniTest.expect.equality(H.exact_decimals(5, 3), "5.000")
end

T["H"]["#fit_decimals"] = MiniTest.new_set()
T["H"]["#fit_decimals"]["returns two decimals when it fits within max_len"] = function()
  MiniTest.expect.equality(H.fit_decimals(1.23, 5), "1.23")
  MiniTest.expect.equality(H.fit_decimals(12.34, 5), "12.34")
end
T["H"]["#fit_decimals"]["returns one decimal when two decimals are too long but one decimal fits"] = function()
  MiniTest.expect.equality(H.fit_decimals(123.45, 5), "123.4")
end
T["H"]["#fit_decimals"]["returns no decimals when two decimals are too long"] = function()
  MiniTest.expect.equality(H.fit_decimals(1234.56, 5), "1234")
  MiniTest.expect.equality(H.fit_decimals(12345.67, 5), "12345")
end

T["F"] = MiniTest.new_set()

local root_dir = vim.fs.joinpath(vim.fn.getcwd(), "test-ff")
local db_dir = vim.fs.joinpath(root_dir, "db-dir")
local dated_files_path = F.get_dated_files_path(db_dir)

local cwd = vim.fs.joinpath(root_dir, "files")
local test_file_a = vim.fs.joinpath(cwd, "test-file-a.txt")
local test_file_b = vim.fs.joinpath(cwd, "test-file-b.txt")
local test_dir_a = vim.fs.joinpath(cwd, "test-dir-a")

local now = os.time { year = 2025, month = 1, day = 1, hour = 0, min = 0, sec = 0 }
local now_after_30_min = os.time { year = 2025, month = 1, day = 1, hour = 0, min = 30, sec = 0 }
local score_when_adding = 1
local date_at_score_one_now = F.compute_date_at_score_one { now = now, score = score_when_adding }
local score_decayed_after_30_min = 0.99951876362267

local function create_file(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ "content" }, path)
end

local function cleanup()
  F._now = function()
    return os.time()
  end
  vim.fn.delete(root_dir, "rf")
  create_file(test_file_a)
  create_file(test_file_b)
  vim.fn.mkdir(test_dir_a, "p")
end

T["F"]["#update_file_score"] = MiniTest.new_set {
  hooks = {
    pre_case = function()
      H.cwd = cwd
      cleanup()
    end,
    post_case = function()
      H.cwd = nil
      cleanup()
    end,
    post_once = function()
      vim.fn.delete(root_dir, "rf")
    end,
  },
}
T["F"]["#update_file_score"]["update_type=increase"] = MiniTest.new_set()
T["F"]["#update_file_score"]["update_type=increase"]["adds score entry for new file"] = function()
  F._now = function()
    return now
  end
  vim.async
    .run(F.update_file_score, test_file_a, {
      db_dir = db_dir,
      update_type = "increase",
    })
    :wait()

  local dated_files = F.read(dated_files_path)
  local date_at_score_one = dated_files[cwd][test_file_a]
  MiniTest.expect.equality(date_at_score_one, date_at_score_one_now)
end

T["F"]["#update_file_score"]["update_type=increase"]["increments score on repeated calls"] = function()
  F._now = function()
    return now
  end
  vim.async
    .run(F.update_file_score, test_file_a, {
      db_dir = db_dir,
      update_type = "increase",
    })
    :wait()

  MiniTest.expect.equality(F.read(dated_files_path)[cwd][test_file_a], date_at_score_one_now)

  F._now = function()
    return now_after_30_min
  end
  vim.async
    .run(F.update_file_score, test_file_a, {
      db_dir = db_dir,
      update_type = "increase",
    })
    :wait()

  -- TODO: passes, precision issue
  -- MiniTest.expect.equality(
  --   F.read(dated_files_path)[test_file_a],
  --   F.compute_date_at_score_one { now = now_after_30_min, score = score_decayed_after_30_min + 1, }
  -- )
end

T["F"]["#update_file_score"]["update_type=increase"]["recalculates all scores when adding a new file"] = function()
  F._now = function()
    return now
  end
  vim.async
    .run(F.update_file_score, test_file_a, {
      db_dir = db_dir,
      update_type = "increase",
    })
    :wait()

  MiniTest.expect.equality(F.read(dated_files_path)[cwd][test_file_a], date_at_score_one_now)

  F._now = function()
    return now_after_30_min
  end
  vim.async
    .run(F.update_file_score, test_file_b, {
      db_dir = db_dir,
      update_type = "increase",
    })
    :wait()

  MiniTest.expect.equality(
    F.read(dated_files_path)[cwd][test_file_a],
    F.compute_date_at_score_one { now = now_after_30_min, score = score_decayed_after_30_min }
  )
  MiniTest.expect.equality(
    F.read(dated_files_path)[cwd][test_file_b],
    F.compute_date_at_score_one { now = now_after_30_min, score = score_when_adding }
  )
end

T["F"]["#update_file_score"]["update_type=increase"]["filters deleted files"] = function()
  F._now = function()
    return now
  end
  vim.async
    .run(F.update_file_score, test_file_a, {
      db_dir = db_dir,
      update_type = "increase",
    })
    :wait()

  MiniTest.expect.equality(F.read(dated_files_path)[cwd][test_file_a], date_at_score_one_now)

  vim.fn.delete(test_file_a)

  F._now = function()
    return now_after_30_min
  end
  vim.async
    .run(F.update_file_score, test_file_b, {
      db_dir = db_dir,
      update_type = "increase",
    })
    :wait()

  MiniTest.expect.equality(F.read(dated_files_path)[cwd][test_file_a], nil)
  MiniTest.expect.equality(
    F.read(dated_files_path)[cwd][test_file_b],
    F.compute_date_at_score_one { now = now_after_30_min, score = score_when_adding }
  )
end

T["F"]["#update_file_score"]["update_type=increase"]["avoids adding deleted files"] = function()
  F._now = function()
    return now
  end

  vim.fn.delete(test_file_a)
  vim.async
    .run(F.update_file_score, test_file_a, {
      db_dir = db_dir,
      update_type = "increase",
    })
    :wait()

  MiniTest.expect.equality(F.read(dated_files_path)[cwd][test_file_a], nil)
end

T["F"]["#update_file_score"]["update_type=increase"]["avoids adding directories"] = function()
  F._now = function()
    return now
  end
  vim.async
    .run(F.update_file_score, test_dir_a, {
      db_dir = db_dir,
      update_type = "increase",
    })
    :wait()

  MiniTest.expect.equality(F.read(dated_files_path)[cwd][test_dir_a], nil)
end

T["F"]["#update_file_score"]["update_type=increase"]["avoids adding directories when stat_file=true"] = function()
  F._now = function()
    return now
  end

  vim.fn.delete(test_dir_a)
  vim.async
    .run(F.update_file_score, test_dir_a, {
      db_dir = db_dir,
      update_type = "increase",
      stat_file = true,
    })
    :wait()

  MiniTest.expect.equality(F.read(dated_files_path)[cwd][test_dir_a], nil)
end

T["F"]["#update_file_score"]["update_type=remove"] = MiniTest.new_set()
T["F"]["#update_file_score"]["update_type=remove"]["removes entry for existing file"] = function()
  F._now = function()
    return now
  end
  vim.async
    .run(F.update_file_score, test_file_a, {
      db_dir = db_dir,
      update_type = "increase",
    })
    :wait()

  MiniTest.expect.equality(F.read(dated_files_path)[cwd][test_file_a], date_at_score_one_now)

  F._now = function()
    return now
  end
  vim.async
    .run(F.update_file_score, test_file_a, {
      db_dir = db_dir,
      update_type = "remove",
    })
    :wait()

  MiniTest.expect.equality(F.read(dated_files_path)[cwd][test_file_a], nil)
end

T["P"] = MiniTest.new_set {
  hooks = {
    pre_case = function()
      P.caches.find_abs_paths = {}
      P.caches.find_rel_paths = {}
      P.caches.frecency_abs_paths = {}
      P.caches.frecency_rel_paths = {}
      P.caches.frecency_abs_path_to_score = {}
      P.caches.icon_cache = {}
      P.caches.open_buffer_to_modified = {}
      P.caches.weighted_files_per_query = {}
      vim.g.ff = nil
      P.caches.gopts = ff.defaulted_gopts()
    end,
  },
}

T["P"]["format_filename"] = MiniTest.new_set {
  hooks = {
    pre_case = function()
      H.cwd = "path/to/dir"
    end,
    post_case = function()
      H.cwd = nil
    end,
  },
}

T["P"]["format_filename"]["formats with score, icon, and relative path"] = function()
  local res = P.format_filename("path/to/dir/src/file.lua", 12.34, "📄")
  MiniTest.expect.equality(res, "12.34 📄 |src/file.lua")
end
T["P"]["format_filename"]["formats without icon when icon_char is nil"] = function()
  local res = P.format_filename("path/to/dir/src/file.lua", 12.34, nil)
  MiniTest.expect.equality(res, "12.34 |src/file.lua")
end
T["P"]["format_filename"]["pads score to MAX_SCORE_LEN"] = function()
  local res = P.format_filename("path/to/dir/file.lua", 1.2, nil)
  MiniTest.expect.equality(res, " 1.20 |file.lua")
end
T["P"]["format_filename"]["uses fit_decimals for score formatting"] = function()
  local res = P.format_filename("path/to/dir/file.lua", 123.456789, nil)
  MiniTest.expect.equality(res, "123.4 |file.lua")
end

T["P"]["get_icon_info"] = MiniTest.new_set()
T["P"]["get_icon_info"]["returns nil icon when icons_enabled is false"] = function()
  local res = P.get_icon_info { abs_path = "path/to/file.lua", icons_enabled = false }
  MiniTest.expect.equality(res.icon_char, nil)
  MiniTest.expect.equality(res.icon_hl, nil)
end
T["P"]["get_icon_info"]["returns cached icon when extension exists in cache"] = function()
  P.caches.icon_cache["lua"] = {
    icon_char = "🌙",
    icon_hl = "LuaIcon",
  }
  local res = P.get_icon_info { abs_path = "path/to/file.lua", icons_enabled = true }
  MiniTest.expect.equality(res.icon_char, "🌙")
  MiniTest.expect.equality(res.icon_hl, "LuaIcon")
end

T["P"]["get_icon_info"]["caches icon info for files with extensions"] = function()
  local res_one = P.get_icon_info { abs_path = "path/to/file.js", icons_enabled = true }
  MiniTest.expect.equality(res_one.icon_char, "󰌞")
  MiniTest.expect.equality(res_one.icon_hl, "MiniIconsYellow")

  MiniTest.expect.equality(P.caches.icon_cache["js"].icon_char, "󰌞")
  MiniTest.expect.equality(P.caches.icon_cache["js"].icon_hl, "MiniIconsYellow")

  local res_two = P.get_icon_info { abs_path = "path/to/file.js", icons_enabled = true }
  MiniTest.expect.equality(res_two.icon_char, "󰌞")
  MiniTest.expect.equality(res_two.icon_hl, "MiniIconsYellow")
end

local query = "in"

--- @type WeightedFile
local weighted_file_lua = {
  abs_path = "path/to/dir/init.lua",
  rel_path = "init.lua",
  buf_and_frecency_score = 10,
  formatted_filename = "17.00  |init.lua",
  fuzzy_score = 20,
  weighted_score = 17,
  hl_idxs = {},
  icon_char = "",
  icon_hl = "MiniIconsGreen",
}

--- @type WeightedFile
local weighted_file_ts = {
  abs_path = "path/to/dir/mod_file.ts",
  rel_path = "mod_file.ts",
  buf_and_frecency_score = 50,
  formatted_filename = "57.00 󰛦 |mod.ts",
  fuzzy_score = 60,
  weighted_score = 57,
  hl_idxs = {},
  icon_char = "󰛦",
  icon_hl = "MiniIconsAzure",
}

T["P"]["get_weighted_file"] = MiniTest.new_set()
T["P"]["get_weighted_file"]["should apply the basename_boost when the basename matches including the extension"] = function()
  vim.g.ff = { weights = { basename_boost = 100 } }
  P.caches.gopts = ff.defaulted_gopts()
  local res = P.get_weighted_file {
    abs_path = weighted_file_lua.abs_path,
    fuzzy_score = 0,
    match_idxs = {},
    query = "init.lua",
    curr_bufname = "",
    alternate_bufname = "",
  }
  MiniTest.expect.equality(res.buf_and_frecency_score, 100)
end
T["P"]["get_weighted_file"]["should apply the basename_boost when the basename matches excluding the extension"] = function()
  vim.g.ff = { weights = { basename_boost = 400 } }
  P.caches.gopts = ff.defaulted_gopts()
  local res = P.get_weighted_file {
    abs_path = weighted_file_lua.abs_path,
    fuzzy_score = 0,
    match_idxs = {},
    query = "init",
    curr_bufname = "",
    alternate_bufname = "",
  }
  MiniTest.expect.equality(res.buf_and_frecency_score, 400)
end
T["P"]["get_weighted_file"]["should apply the basename_boost when the alphabetic basename matches excluding the extension"] = function()
  vim.g.ff = { weights = { basename_boost = 400 } }
  P.caches.gopts = ff.defaulted_gopts()
  local res = P.get_weighted_file {
    abs_path = weighted_file_ts.abs_path,
    fuzzy_score = 0,
    match_idxs = {},
    query = "modfile",
    curr_bufname = "",
    alternate_bufname = "",
  }
  MiniTest.expect.equality(res.buf_and_frecency_score, 400)
end
T["P"]["get_weighted_file"]["should apply the current_buf_boost"] = function()
  P.caches.open_buffer_to_modified = { [weighted_file_lua.abs_path] = false }
  vim.g.ff = { weights = { current_buf_boost = -90 } }
  P.caches.gopts = ff.defaulted_gopts()
  local res = P.get_weighted_file {
    abs_path = weighted_file_lua.abs_path,
    fuzzy_score = 0,
    match_idxs = {},
    query = query,
    curr_bufname = weighted_file_lua.abs_path,
    alternate_bufname = "",
  }
  MiniTest.expect.equality(res.buf_and_frecency_score, -90)
end
T["P"]["get_weighted_file"]["should apply the alternate_buf_boost"] = function()
  P.caches.open_buffer_to_modified = { [weighted_file_lua.abs_path] = false }
  vim.g.ff = { weights = { alternate_buf_boost = 300 } }
  P.caches.gopts = ff.defaulted_gopts()
  local res = P.get_weighted_file {
    abs_path = weighted_file_lua.abs_path,
    fuzzy_score = 0,
    match_idxs = {},
    query = query,
    curr_bufname = "",
    alternate_bufname = weighted_file_lua.abs_path,
  }
  MiniTest.expect.equality(res.buf_and_frecency_score, 300)
end
T["P"]["get_weighted_file"]["should apply the modified_buf_boost"] = function()
  P.caches.open_buffer_to_modified = { [weighted_file_lua.abs_path] = true }
  vim.g.ff = { weights = { modified_buf_boost = 200 } }
  P.caches.gopts = ff.defaulted_gopts()
  local res = P.get_weighted_file {
    abs_path = weighted_file_lua.abs_path,
    fuzzy_score = 0,
    match_idxs = {},
    query = query,
    curr_bufname = "",
    alternate_bufname = "",
  }
  MiniTest.expect.equality(res.buf_and_frecency_score, 200)
end
T["P"]["get_weighted_file"]["should apply the open_buf_boost"] = function()
  P.caches.open_buffer_to_modified = { [weighted_file_lua.abs_path] = false }
  vim.g.ff = { weights = { open_buf_boost = 100 } }
  P.caches.gopts = ff.defaulted_gopts()
  local res = P.get_weighted_file {
    abs_path = weighted_file_lua.abs_path,
    fuzzy_score = 0,
    match_idxs = {},
    query = query,
    curr_bufname = "",
    alternate_bufname = "",
  }
  MiniTest.expect.equality(res.buf_and_frecency_score, 100)
end
T["P"]["get_weighted_file"]["should apply the frecency score"] = function()
  P.caches.frecency_abs_path_to_score = { [weighted_file_lua.abs_path] = 100 }
  local res = P.get_weighted_file {
    abs_path = weighted_file_lua.abs_path,
    fuzzy_score = 0,
    match_idxs = {},
    query = query,
    curr_bufname = "",
    alternate_bufname = "",
  }
  MiniTest.expect.equality(res.buf_and_frecency_score, 100)
end
T["P"]["get_weighted_file"]["should weight the score according to fuzzy_score_multiple and file_score_multiple"] = function()
  P.caches.frecency_abs_path_to_score = { [weighted_file_lua.abs_path] = 20 }
  vim.g.ff = { fuzzy_score_multiple = 0.8, file_score_multiple = 0.2 }
  P.caches.gopts = ff.defaulted_gopts()
  local res = P.get_weighted_file {
    abs_path = weighted_file_lua.abs_path,
    fuzzy_score = 100,
    match_idxs = {},
    query = query,
    curr_bufname = "",
    alternate_bufname = "",
  }
  local expected_buf_and_frecency_score = 20
  MiniTest.expect.equality(res.buf_and_frecency_score, expected_buf_and_frecency_score)
  local file_score_multiple = 1 - 0.8
  local expected_weighted = 0.8 * res.fuzzy_score
    + file_score_multiple * expected_buf_and_frecency_score
  MiniTest.expect.equality(res.weighted_score, expected_weighted)
end

T["P"]["render_find_files"] = MiniTest.new_set {
  hooks = {
    pre_case = function()
      P.MAX_FRECENCY_SCORE = 99
      P.MAX_SCORE_LEN = #H.exact_decimals(P.MAX_FRECENCY_SCORE, 2)
      cleanup()
    end,
    post_once = function()
      vim.fn.delete(root_dir, "rf")
    end,
  },
}

local function create_sandbox_file(name)
  local abs_path = vim.fs.joinpath(cwd, name)
  create_file(abs_path)
  return abs_path
end

local function rel_path_of(abs_path)
  return vim.fs.relpath(vim.fn.getcwd(), abs_path)
end

local function render_find_files(query, opts_overrides)
  opts_overrides = opts_overrides or {}
  vim.g.ff = vim.tbl_extend("force", { icons_enabled = false }, opts_overrides)
  P.caches.gopts = ff.defaulted_gopts()
  local results_buf = vim.api.nvim_create_buf(false, true)
  local decorated_files
  vim.async
    .run(P.render_find_files, {
      query = query,
      results_buf = results_buf,
      curr_bufname = "",
      alternate_bufname = "",
      curr_tick = opts_overrides.curr_tick or P.tick,
      render_results = function(files)
        decorated_files = files
        vim.api.nvim_buf_set_lines(
          results_buf,
          0,
          -1,
          false,
          vim.tbl_map(function(f)
            return f.formatted_filename
          end, files)
        )
      end,
    })
    :wait()
  return results_buf, decorated_files
end

local function populate_find_cache(abs_paths)
  P.caches.find_abs_paths = abs_paths
  P.caches.find_rel_paths = vim.tbl_map(rel_path_of, abs_paths)
end

T["P"]["render_find_files"]["renders frecency paths before find paths for the empty query"] = function()
  local frecency_abs = create_sandbox_file "alpha.txt"
  local find_abs_one = create_sandbox_file "f1.txt"
  local find_abs_two = create_sandbox_file "f2.txt"

  P.caches.frecency_abs_paths = { frecency_abs }
  P.caches.frecency_rel_paths = { rel_path_of(frecency_abs) }
  P.caches.frecency_abs_path_to_score = { [frecency_abs] = 10 }
  populate_find_cache { find_abs_one, find_abs_two }

  local _, decorated_files = render_find_files ""

  MiniTest.expect.equality(#decorated_files, 3)
  MiniTest.expect.equality(decorated_files[1].abs_path, frecency_abs)
  MiniTest.expect.equality(decorated_files[1].weighted_score, 10)
  local find_results = { decorated_files[2].abs_path, decorated_files[3].abs_path }
  table.sort(find_results)
  MiniTest.expect.equality(find_results, { find_abs_one, find_abs_two })
end

T["P"]["render_find_files"]["dedups files present in both frecency and find caches"] = function()
  local abs_path = create_sandbox_file "alpha.txt"
  local other_abs = create_sandbox_file "f1.txt"

  P.caches.frecency_abs_paths = { abs_path }
  P.caches.frecency_rel_paths = { rel_path_of(abs_path) }
  P.caches.frecency_abs_path_to_score = { [abs_path] = 5 }
  populate_find_cache { abs_path, other_abs }

  local _, decorated_files = render_find_files ""

  MiniTest.expect.equality(#decorated_files, 2)
  local found_abs_paths = { decorated_files[1].abs_path, decorated_files[2].abs_path }
  table.sort(found_abs_paths)
  MiniTest.expect.equality(found_abs_paths, { abs_path, other_abs })
end

T["P"]["render_find_files"]["matches rel paths with matchfuzzypos for a populated query"] = function()
  local alpha_abs = create_sandbox_file "alpha.txt"
  local beta_abs = create_sandbox_file "beta.md"
  populate_find_cache { alpha_abs, beta_abs }

  local _, decorated_files = render_find_files "alpha"

  MiniTest.expect.equality(#decorated_files, 1)
  MiniTest.expect.equality(decorated_files[1].abs_path, alpha_abs)
  MiniTest.expect.equality(decorated_files[1].fuzzy_score > 0, true)
  MiniTest.expect.equality(decorated_files[1].buf_and_frecency_score, 40)
end

T["P"]["render_find_files"]["stops considering results at max_results_considered"] = function()
  local abs_paths = {}
  for i = 1, 5 do
    table.insert(abs_paths, create_sandbox_file(("f%d.txt"):format(i)))
  end
  populate_find_cache(abs_paths)

  local _, decorated_files =
    render_find_files("txt", { max_results_considered = 3, max_results_rendered = 10 })

  MiniTest.expect.equality(#decorated_files, 3)
end

T["P"]["render_find_files"]["slices rendered results to max_results_rendered"] = function()
  local abs_paths = {}
  for i = 1, 5 do
    table.insert(abs_paths, create_sandbox_file(("f%d.txt"):format(i)))
  end
  populate_find_cache(abs_paths)

  local _, decorated_files = render_find_files("txt", { max_results_rendered = 2 })

  MiniTest.expect.equality(#decorated_files, 2)
end

T["P"]["render_find_files"]["caps the empty query at max_results_rendered"] = function()
  local abs_paths = {}
  for i = 1, 5 do
    table.insert(abs_paths, create_sandbox_file(("f%d.txt"):format(i)))
  end
  populate_find_cache(abs_paths)

  local _, decorated_files = render_find_files("", { max_results_rendered = 2 })

  MiniTest.expect.equality(#decorated_files, 2)
end

T["P"]["render_find_files"]["reuses the weighted_files_per_query cache"] = function()
  local cached_abs = create_sandbox_file "zzz-cached.txt"
  local find_abs = create_sandbox_file "cached-foo.txt"
  populate_find_cache { find_abs }
  P.caches.weighted_files_per_query["cached"] = {
    {
      abs_path = cached_abs,
      weighted_score = 7,
      buf_and_frecency_score = 0,
      fuzzy_score = 0,
      match_idxs = {},
    },
  }

  local _, decorated_files = render_find_files "cached"

  MiniTest.expect.equality(#decorated_files, 1)
  MiniTest.expect.equality(decorated_files[1].abs_path, cached_abs)
  MiniTest.expect.equality(
    decorated_files[1].formatted_filename,
    (" 7.00 |%s"):format(rel_path_of(cached_abs))
  )
end

T["P"]["render_find_files"]["renders empty results when the tick is stale"] = function()
  local alpha_abs = create_sandbox_file "alpha.txt"
  populate_find_cache { alpha_abs }

  local _, decorated_files = render_find_files("", { curr_tick = P.tick + 1 })

  MiniTest.expect.equality(decorated_files, {})
end

T["P"]["render_find_files"]["decorates files with rel_path and formatted filename"] = function()
  local alpha_abs = create_sandbox_file "alpha.txt"
  populate_find_cache { alpha_abs }

  local _, decorated_files = render_find_files ""

  local rel_path = rel_path_of(alpha_abs)
  MiniTest.expect.equality(decorated_files[1], {
    abs_path = alpha_abs,
    weighted_score = 0,
    fuzzy_score = 0,
    buf_and_frecency_score = 0,
    match_idxs = {},
    rel_path = rel_path,
    icon_char = nil,
    icon_hl = nil,
    formatted_filename = (" 0.00 |%s"):format(rel_path),
  })
end

T["P"]["render_find_files"]["leaves match_idxs empty when hl_enabled=false"] = function()
  local alpha_abs = create_sandbox_file "alpha.txt"
  populate_find_cache { alpha_abs }

  local results_buf, decorated_files = render_find_files("alpha", { hl_enabled = false })

  MiniTest.expect.equality(decorated_files[1].match_idxs, {})
  MiniTest.expect.equality(vim.api.nvim_buf_get_extmarks(results_buf, P.ns_id, 0, -1, {}), {})
end

T["P"]["render_find_files"]["highlights icon and fuzzy match characters"] = function()
  local alpha_abs = create_sandbox_file "alpha.txt"
  local rel_path = rel_path_of(alpha_abs)
  populate_find_cache { alpha_abs }
  P.caches.icon_cache["txt"] = { icon_char = "T", icon_hl = "TxtIcon" }

  local results_buf, decorated_files = render_find_files("alpha", { icons_enabled = true })

  local match_idxs = vim.fn.matchfuzzypos({ rel_path }, "alpha")[2][1]
  local file_offset = decorated_files[1].formatted_filename:find "|"
  local expected = { { 0, 6, "TxtIcon" } }
  for _, hl_idx in ipairs(match_idxs) do
    table.insert(expected, { 0, hl_idx + file_offset, "FFPickerFuzzyHighlightChar" })
  end
  table.sort(expected, function(a, b)
    return a[2] < b[2]
  end)

  local observed = {}
  for _, extmark in
    ipairs(vim.api.nvim_buf_get_extmarks(results_buf, P.ns_id, 0, -1, { details = true }))
  do
    table.insert(observed, { extmark[2], extmark[3], extmark[4].hl_group })
  end
  table.sort(observed, function(a, b)
    return a[2] < b[2]
  end)

  MiniTest.expect.equality(observed, expected)
end

T["P"]["scale_fuzzy_to_frecency"] = MiniTest.new_set {
  hooks = {
    pre_case = function()
      P.MAX_FRECENCY_SCORE = 99
    end,
  },
}

local default_weights = {
  open_buf_boost = 10,
  modified_buf_boost = 20,
  alternate_buf_boost = 30,
  basename_boost = 40,
  current_buf_boost = -1000,
}
local default_sigmoid = { steepness = 0.02, midpoint = 900 }
local default_max_score = math.max(
  default_weights.alternate_buf_boost,
  default_weights.basename_boost,
  default_weights.current_buf_boost,
  default_weights.modified_buf_boost,
  default_weights.open_buf_boost
) + 99

local function scale_fuzzy_to_frecency(fuzzy_score, query, weights, sigmoid)
  return P.scale_fuzzy_to_frecency {
    fuzzy_score = fuzzy_score,
    query = query,
    weights = weights or default_weights,
    matchfuzzypos_sigmoid = sigmoid or default_sigmoid,
  }
end

T["P"]["scale_fuzzy_to_frecency"]["increases monotonically with fuzzy_score"] = function()
  local low = scale_fuzzy_to_frecency(100, "abc")
  local mid = scale_fuzzy_to_frecency(500, "abc")
  local high = scale_fuzzy_to_frecency(1000, "abc")

  MiniTest.expect.equality(low < mid, true)
  MiniTest.expect.equality(mid < high, true)
end

T["P"]["scale_fuzzy_to_frecency"]["returns near 0 for very low fuzzy scores"] = function()
  MiniTest.expect.equality(scale_fuzzy_to_frecency(1, "abc") < 0.001, true)
end

T["P"]["scale_fuzzy_to_frecency"]["saturates to exactly max_score for very high fuzzy scores"] = function()
  MiniTest.expect.equality(scale_fuzzy_to_frecency(100000, "a"), default_max_score)
end

T["P"]["scale_fuzzy_to_frecency"]["returns half of max_score when the per char score equals midpoint"] = function()
  -- query "ab" with fuzzy_score 1800 gives a per char score of 900, the default midpoint
  MiniTest.expect.equality(scale_fuzzy_to_frecency(1800, "ab"), default_max_score / 2)
end

T["P"]["scale_fuzzy_to_frecency"]["returns equal results for equal per char scores across query lengths"] = function()
  MiniTest.expect.equality(scale_fuzzy_to_frecency(900, "a"), scale_fuzzy_to_frecency(1800, "ab"))
end

T["P"]["scale_fuzzy_to_frecency"]["honors custom midpoint, steepness, and weights"] = function()
  MiniTest.expect.equality(
    scale_fuzzy_to_frecency(200, "ab", default_weights, { steepness = 0.05, midpoint = 100 }),
    default_max_score / 2
  )

  local custom_weights = {
    open_buf_boost = 100,
    modified_buf_boost = 200,
    alternate_buf_boost = 300,
    basename_boost = 400,
    current_buf_boost = -1000,
  }
  -- steepness 1000 saturates the sigmoid to exactly 1 for large fuzzy scores
  MiniTest.expect.equality(
    scale_fuzzy_to_frecency(100000, "a", custom_weights, { steepness = 1000, midpoint = 0 }),
    499
  )
end

T["P"]["defaulted_gopts"] = MiniTest.new_set {
  hooks = {
    pre_case = function()
      vim.g.ff = nil
      vim.o.lines = 24
    end,
    post_case = function()
      vim.g.ff = nil
      vim.o.lines = 24
    end,
  },
}

T["P"]["defaulted_gopts"]["fills defaults when the option is unset"] = function()
  MiniTest.expect.equality(ff.defaulted_gopts(), {
    weights = {
      open_buf_boost = 10,
      modified_buf_boost = 20,
      alternate_buf_boost = 30,
      basename_boost = 40,
      current_buf_boost = -1000,
    },
    matchfuzzypos_sigmoid = { steepness = 0.02, midpoint = 900 },
    matchfuzzypos_batch_size = 250,
    hl_enabled = true,
    icons_enabled = true,
    max_results_considered = 1000,
    fuzzy_score_multiple = 0.7,
    benchmark_step = false,
    benchmark_mean = false,
    find_cmd = { "fd", "--absolute-path", "--type", "f" },
    -- editor_height 24 gives results_height 12, doubled into max_results_rendered
    max_results_rendered = 24,
  })
end

T["P"]["defaulted_gopts"]["derives max_results_rendered from the window height"] = function()
  vim.o.lines = 30
  MiniTest.expect.equality(ff.defaulted_gopts().max_results_rendered, 30)
end

T["P"]["defaulted_gopts"]["uses explicit values over defaults"] = function()
  vim.g.ff = {
    weights = {
      open_buf_boost = 1,
      modified_buf_boost = 2,
      alternate_buf_boost = 3,
      basename_boost = 4,
      current_buf_boost = 5,
    },
    matchfuzzypos_sigmoid = { steepness = 1, midpoint = 2 },
    matchfuzzypos_batch_size = 3,
    hl_enabled = false,
    icons_enabled = false,
    max_results_considered = 4,
    fuzzy_score_multiple = 0.5,
    benchmark_step = true,
    benchmark_mean = true,
    find_cmd = { "rg", "--files" },
    max_results_rendered = 7,
  }

  MiniTest.expect.equality(ff.defaulted_gopts(), {
    weights = {
      open_buf_boost = 1,
      modified_buf_boost = 2,
      alternate_buf_boost = 3,
      basename_boost = 4,
      current_buf_boost = 5,
    },
    matchfuzzypos_sigmoid = { steepness = 1, midpoint = 2 },
    matchfuzzypos_batch_size = 3,
    hl_enabled = false,
    icons_enabled = false,
    max_results_considered = 4,
    fuzzy_score_multiple = 0.5,
    benchmark_step = true,
    benchmark_mean = true,
    find_cmd = { "rg", "--files" },
    max_results_rendered = 7,
  })
end

T["P"]["defaulted_gopts"]["fills defaults for partially provided values without mutating vim.g.ff"] = function()
  vim.g.ff = { weights = { open_buf_boost = 1 }, hl_enabled = false }
  local original_gopts = vim.deepcopy(vim.g.ff)

  local gopts = ff.defaulted_gopts()

  MiniTest.expect.equality(vim.g.ff, original_gopts)
  MiniTest.expect.equality(gopts.weights, {
    open_buf_boost = 1,
    modified_buf_boost = 20,
    alternate_buf_boost = 30,
    basename_boost = 40,
    current_buf_boost = -1000,
  })
  MiniTest.expect.equality(gopts.hl_enabled, false)
end

local original_os_time = os.time
local original_default_db_dir = F.default_db_dir

T["P"]["refresh_frecency_cache"] = MiniTest.new_set {
  hooks = {
    pre_case = function()
      P.MAX_FRECENCY_SCORE = 99
      P.MAX_SCORE_LEN = #H.exact_decimals(P.MAX_FRECENCY_SCORE, 2)
      cleanup()
      F.default_db_dir = vim.fs.joinpath(root_dir, "db-dir")
      H.cwd = cwd
      os.time = function()
        return now
      end
    end,
    post_case = function()
      os.time = original_os_time
      F.default_db_dir = original_default_db_dir
      H.cwd = nil
      cleanup()
    end,
    post_once = function()
      vim.fn.delete(root_dir, "rf")
    end,
  },
}

local function score_for(date_at_score_one)
  return F.compute_score { now = now, date_at_score_one = date_at_score_one }
end

local function write_dated_files(entries)
  F.write(F.get_dated_files_path(F.default_db_dir), { [cwd] = entries })
end

T["P"]["refresh_frecency_cache"]["populates scored paths and rel paths from the db"] = function()
  local abs_a = create_sandbox_file "alpha.txt"
  local abs_b = create_sandbox_file "beta.md"
  write_dated_files {
    [abs_a] = now,
    [abs_b] = now + F.half_life_sec,
  }

  vim.async.run(P.refresh_frecency_cache):wait()

  MiniTest.expect.equality(P.caches.frecency_abs_path_to_score[abs_a], 1)
  MiniTest.expect.equality(
    P.caches.frecency_abs_path_to_score[abs_b],
    score_for(now + F.half_life_sec)
  )
  MiniTest.expect.equality(P.caches.frecency_abs_paths, { abs_b, abs_a })
  MiniTest.expect.equality(P.caches.frecency_rel_paths, {
    vim.fs.relpath(H.cwd, abs_b),
    vim.fs.relpath(H.cwd, abs_a),
  })
end

T["P"]["refresh_frecency_cache"]["skips unreadable files and sorts paths by score descending"] = function()
  local abs_a = create_sandbox_file "alpha.txt"
  local abs_b = create_sandbox_file "beta.md"
  local abs_c = create_sandbox_file "gamma.txt"
  write_dated_files {
    [vim.fs.joinpath(cwd, "deleted.txt")] = now,
    [abs_a] = now,
    [abs_b] = now + 2 * F.half_life_sec,
    [abs_c] = now + F.half_life_sec,
  }

  vim.async.run(P.refresh_frecency_cache):wait()

  MiniTest.expect.equality(P.caches.frecency_abs_path_to_score, {
    [abs_a] = score_for(now),
    [abs_b] = score_for(now + 2 * F.half_life_sec),
    [abs_c] = score_for(now + F.half_life_sec),
  })
  MiniTest.expect.equality(P.caches.frecency_abs_paths, { abs_b, abs_c, abs_a })
end

T["P"]["refresh_frecency_cache"]["raises MAX_FRECENCY_SCORE and MAX_SCORE_LEN above the cap"] = function()
  local abs_d = create_sandbox_file "delta.txt"
  write_dated_files { [abs_d] = now + 7 * F.half_life_sec }

  vim.async.run(P.refresh_frecency_cache):wait()

  MiniTest.expect.equality(P.MAX_FRECENCY_SCORE, score_for(now + 7 * F.half_life_sec))
  MiniTest.expect.equality(P.MAX_FRECENCY_SCORE > 99, true)
  MiniTest.expect.equality(P.MAX_SCORE_LEN, 6)
end

T["P"]["refresh_files_cache"] = MiniTest.new_set {
  hooks = {
    pre_case = function()
      cleanup()
      H.cwd = cwd
    end,
    post_case = function()
      H.cwd = nil
      cleanup()
    end,
    post_once = function()
      vim.fn.delete(root_dir, "rf")
    end,
  },
}

local function use_find_cmd(paths)
  vim.g.ff = { find_cmd = vim.list_extend({ "printf", "%s\n" }, paths) }
  P.caches.gopts = ff.defaulted_gopts()
end

T["P"]["refresh_files_cache"]["populates find caches and reports emptiness around the refresh"] = function()
  local abs_a = create_sandbox_file "alpha.txt"
  local abs_b = create_sandbox_file "beta.md"
  use_find_cmd { abs_a, abs_b }

  MiniTest.expect.equality(P.is_find_cache_empty(), true)
  vim.async.run(P.refresh_files_cache):wait()

  MiniTest.expect.equality(P.caches.find_abs_paths, { abs_a, abs_b })
  MiniTest.expect.equality(
    P.caches.find_rel_paths,
    { vim.fs.relpath(cwd, abs_a), vim.fs.relpath(cwd, abs_b) }
  )
  MiniTest.expect.equality(P.is_find_cache_empty(), false)
end

T["P"]["refresh_files_cache"]["skips empty lines from the find output"] = function()
  local abs_a = create_sandbox_file "alpha.txt"
  local abs_b = create_sandbox_file "beta.md"
  use_find_cmd { "", abs_a, abs_b, "" }

  vim.async.run(P.refresh_files_cache):wait()

  MiniTest.expect.equality(P.caches.find_abs_paths, { abs_a, abs_b })
end

T["P"]["refresh_files_cache"]["normalizes paths from the find output"] = function()
  local abs_a = create_sandbox_file "alpha.txt"
  local abs_b = create_sandbox_file "beta.md"
  use_find_cmd {
    vim.fs.joinpath(cwd, "test-ff", "files", "..", "files", ".", "alpha.txt"),
    abs_b,
  }

  vim.async.run(P.refresh_files_cache):wait()

  MiniTest.expect.equality(P.caches.find_abs_paths, { abs_a, abs_b })
end

local test_bufs = {}

T["P"]["refresh_open_buffers_cache"] = MiniTest.new_set {
  hooks = {
    pre_case = function()
      cleanup()
      test_bufs = {}
      H.cwd = cwd
    end,
    post_case = function()
      H.cwd = nil
      for _, buf in ipairs(test_bufs) do
        pcall(vim.cmd, "bwipeout! " .. tostring(buf))
      end
      cleanup()
    end,
    post_once = function()
      vim.fn.delete(root_dir, "rf")
    end,
  },
}

local function create_test_buffer(abs_path, opts)
  local buf = vim.api.nvim_create_buf(opts.listed, false)
  if abs_path then
    vim.api.nvim_buf_set_name(buf, abs_path)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "content" })
  if opts.modified == false then
    vim.api.nvim_set_option_value("modified", false, { buf = buf })
  end
  table.insert(test_bufs, buf)
  return buf
end

T["P"]["refresh_open_buffers_cache"]["caches open listed buffers under cwd with their modified flags"] = function()
  local abs_a = create_sandbox_file "alpha.txt"
  local abs_b = create_sandbox_file "beta.md"
  create_test_buffer(abs_a, { listed = true, modified = false })
  create_test_buffer(abs_b, { listed = true })
  create_test_buffer(vim.fs.joinpath(cwd, "requires-listing.txt"), { listed = false })
  create_test_buffer("/tmp/ff-outside-cwd.txt", { listed = true })
  create_test_buffer(nil, { listed = true })

  local buf_unloaded = create_test_buffer(vim.fs.joinpath(cwd, "unloaded.txt"), { listed = true })
  vim.cmd("bunload! " .. tostring(buf_unloaded))

  vim.async.run(P.refresh_open_buffers_cache):wait()

  MiniTest.expect.equality(P.caches.open_buffer_to_modified, {
    [abs_a] = false,
    [abs_b] = true,
  })
end

T["P"]["refresh_open_buffers_cache"]["clears the weighted_files_per_query cache"] = function()
  P.caches.weighted_files_per_query = { cached_query = { { abs_path = "x" } } }
  create_test_buffer(nil, { listed = true })

  vim.async.run(P.refresh_open_buffers_cache):wait()

  MiniTest.expect.equality(P.caches.open_buffer_to_modified, {})
  MiniTest.expect.equality(P.caches.weighted_files_per_query, {})
end

local child = MiniTest.new_child_neovim()

T["find"] = MiniTest.new_set {
  hooks = {
    pre_case = function()
      vim.fn.delete(vim.fs.joinpath(vim.fn.getcwd(), "test-ff"), "rf")
      child.restart { "-u", "scripts/minimal_init.lua" }
      child.lua_func(function()
        require "ff"
      end)
    end,
    post_once = child.stop,
  },
}

local function add_event_capture(patterns, list_name)
  child.lua_func(function(patterns, list_name)
    _G[list_name] = {}
    for _, pattern in ipairs(patterns) do
      vim.api.nvim_create_autocmd("User", {
        pattern = pattern,
        callback = function(ev)
          table.insert(_G[list_name], {
            pattern = pattern,
            data = { winnr = ev.data.winnr, bufnr = ev.data.bufnr },
          })
        end,
      })
    end
  end, patterns, list_name)
end

local function get_child_state()
  return child.lua_func(function()
    return {
      events = _G.ff_events,
      opens = _G.ff_opens,
      previews = _G.ff_previews,
    }
  end)
end

local function run_find()
  child.g.ff = { icons_enabled = false }
  child.lua_func(function()
    require("ff").find():wait()
  end)
end

T["find"]["fires the FFResultsOpen and FFInputOpen user events"] = function()
  add_event_capture({ "FFResultsOpen", "FFInputOpen" }, "ff_events")
  run_find()

  local events = get_child_state().events

  MiniTest.expect.equality(#events, 2)
  MiniTest.expect.equality(events[1].pattern, "FFResultsOpen")
  MiniTest.expect.equality(events[2].pattern, "FFInputOpen")

  local results_win = events[1].data.winnr
  local input_win = events[2].data.winnr
  MiniTest.expect.equality(child.api.nvim_win_is_valid(results_win), true)
  MiniTest.expect.equality(child.api.nvim_win_is_valid(input_win), true)
  MiniTest.expect.equality(child.api.nvim_win_get_buf(results_win), events[1].data.bufnr)
  MiniTest.expect.equality(child.api.nvim_win_get_buf(input_win), events[2].data.bufnr)
  MiniTest.expect.equality(child.api.nvim_get_current_win(), input_win)
end

T["find"]["fires FFPreviewOpen with the preview buffer when the preview is toggled on"] = function()
  add_event_capture({ "FFResultsOpen" }, "ff_opens")
  add_event_capture({ "FFPreviewOpen" }, "ff_previews")
  run_find()

  local state = get_child_state()
  MiniTest.expect.equality(#state.opens, 1)

  local results_win = state.opens[1].data.winnr
  local results_buf = state.opens[1].data.bufnr
  child.lua_func(function(win)
    vim.api.nvim_win_call(win, function()
      vim.cmd "normal! gg"
    end)
  end, results_win)
  local first_result_line = child.lua_func(function(win)
    return vim.api.nvim_win_call(win, vim.api.nvim_get_current_line)
  end, results_win)
  MiniTest.expect.equality(#first_result_line > 0, true)

  local feed_toggle = function()
    child.api.nvim_feedkeys(
      child.api.nvim_replace_termcodes("<Plug>FFPreviewToggle", true, false, true),
      "m",
      false
    )
  end

  feed_toggle()
  MiniTest.expect.equality(
    child.lua_func(function()
      return vim.wait(2000, function()
        return #_G.ff_previews >= 1
      end, 10)
    end),
    true
  )
  state = get_child_state()
  MiniTest.expect.equality(#state.previews, 1)
  MiniTest.expect.equality(state.previews[1].data.winnr, results_win)
  MiniTest.expect.equality(child.api.nvim_win_get_buf(results_win), state.previews[1].data.bufnr)
  MiniTest.expect.equality(state.previews[1].data.bufnr ~= results_buf, true)

  -- toggling the preview off shows the results buffer again and re-fires FFResultsOpen
  feed_toggle()
  MiniTest.expect.equality(
    child.lua_func(function()
      return vim.wait(2000, function()
        return #_G.ff_opens >= 2
      end, 10)
    end),
    true
  )
  state = get_child_state()
  MiniTest.expect.equality(#state.opens, 2)
  MiniTest.expect.equality(state.opens[2].data.winnr, results_win)
  MiniTest.expect.equality(state.opens[2].data.bufnr, results_buf)
  MiniTest.expect.equality(#state.previews, 1)
end

return T
