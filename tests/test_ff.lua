local T = MiniTest.new_set()
_G.FF_TEST = true

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
  MiniTest.expect.equality(H.rel_path "path/to/another_dir/file.txt", "path/to/another_dir/file.txt")
end
T["H"]["#rel_path"]["returns the abs file path as a fallback"] = function()
  MiniTest.expect.equality(H.rel_path "path/to/another_dir/file.txt", "path/to/another_dir/file.txt")
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
  MiniTest.expect.equality(H.basename("path/to/file.txt", { with_ext = true, }), "file.txt")
  MiniTest.expect.equality(H.basename("path/to/file.txt", { with_ext = false, }), "file")
  MiniTest.expect.equality(H.basename("path/to/file.min.txt", { with_ext = true, }), "file.min.txt")
  MiniTest.expect.equality(H.basename("path/to/file.min.txt", { with_ext = false, }), "file")
  MiniTest.expect.equality(H.basename("path/to/file", { with_ext = true, }), "file")
  MiniTest.expect.equality(H.basename("path/to/file", { with_ext = false, }), "file")
  MiniTest.expect.equality(H.basename("file.txt", { with_ext = true, }), "file.txt")
  MiniTest.expect.equality(H.basename("file.txt", { with_ext = false, }), "file")
  MiniTest.expect.equality(H.basename(".gitignore", { with_ext = true, }), ".gitignore")
  MiniTest.expect.equality(H.basename(".gitignore", { with_ext = false, }), ".gitignore")
  MiniTest.expect.equality(H.basename("", { with_ext = true, }), "")
  MiniTest.expect.equality(H.basename("", { with_ext = false, }), "")
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
local _db_dir = vim.fs.joinpath(root_dir, "db-dir")
local dated_files_path = F.get_dated_files_path(_db_dir)

local cwd = vim.fs.joinpath(root_dir, "files")
local test_file_a = vim.fs.joinpath(cwd, "test-file-a.txt")
local test_file_b = vim.fs.joinpath(cwd, "test-file-b.txt")
local test_dir_a = vim.fs.joinpath(cwd, "test-dir-a")

local now = os.time { year = 2025, month = 1, day = 1, hour = 0, min = 0, sec = 0, }
local now_after_30_min = os.time { year = 2025, month = 1, day = 1, hour = 0, min = 30, sec = 0, }
local score_when_adding = 1
local date_at_score_one_now = F.compute_date_at_score_one { now = now, score = score_when_adding, }
local score_decayed_after_30_min = 0.99951876362267

local function create_file(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ "content", }, path)
end

local function cleanup()
  F._now = function() return os.time() end
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
  F._now = function() return now end
  F.update_file_score(test_file_a, {
    _db_dir = _db_dir,
    update_type = "increase",
  })

  local dated_files = F.read(dated_files_path)
  local date_at_score_one = dated_files[cwd][test_file_a]
  MiniTest.expect.equality(date_at_score_one, date_at_score_one_now)
end

T["F"]["#update_file_score"]["update_type=increase"]["increments score on repeated calls"] = function()
  F._now = function() return now end
  F.update_file_score(test_file_a, {
    _db_dir = _db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(
    F.read(dated_files_path)[cwd][test_file_a],
    date_at_score_one_now
  )

  F._now = function() return now_after_30_min end
  F.update_file_score(test_file_a, {
    _db_dir = _db_dir,
    update_type = "increase",
  })

  -- TODO: passes, precision issue
  -- MiniTest.expect.equality(
  --   F.read(dated_files_path)[test_file_a],
  --   F.compute_date_at_score_one { now = now_after_30_min, score = score_decayed_after_30_min + 1, }
  -- )
end

T["F"]["#update_file_score"]["update_type=increase"]["recalculates all scores when adding a new file"] = function()
  F._now = function() return now end
  F.update_file_score(test_file_a, {
    _db_dir = _db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(
    F.read(dated_files_path)[cwd][test_file_a],
    date_at_score_one_now
  )

  F._now = function() return now_after_30_min end
  F.update_file_score(test_file_b, {
    _db_dir = _db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(
    F.read(dated_files_path)[cwd][test_file_a],
    F.compute_date_at_score_one { now = now_after_30_min, score = score_decayed_after_30_min, }
  )
  MiniTest.expect.equality(
    F.read(dated_files_path)[cwd][test_file_b],
    F.compute_date_at_score_one { now = now_after_30_min, score = score_when_adding, }
  )
end

T["F"]["#update_file_score"]["update_type=increase"]["filters deleted files"] = function()
  F._now = function() return now end
  F.update_file_score(test_file_a, {
    _db_dir = _db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(
    F.read(dated_files_path)[cwd][test_file_a],
    date_at_score_one_now
  )

  vim.fn.delete(test_file_a)

  F._now = function() return now_after_30_min end
  F.update_file_score(test_file_b, {
    _db_dir = _db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(
    F.read(dated_files_path)[cwd][test_file_a],
    nil
  )
  MiniTest.expect.equality(
    F.read(dated_files_path)[cwd][test_file_b],
    F.compute_date_at_score_one { now = now_after_30_min, score = score_when_adding, }
  )
end

T["F"]["#update_file_score"]["update_type=increase"]["avoids adding deleted files"] = function()
  F._now = function() return now end

  vim.fn.delete(test_file_a)
  F.update_file_score(test_file_a, {
    _db_dir = _db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(
    F.read(dated_files_path)[cwd][test_file_a],
    nil
  )
end

T["F"]["#update_file_score"]["update_type=increase"]["avoids adding directories"] = function()
  F._now = function() return now end
  F.update_file_score(test_dir_a, {
    _db_dir = _db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(
    F.read(dated_files_path)[cwd][test_dir_a],
    nil
  )
end

T["F"]["#update_file_score"]["update_type=increase"]["avoids adding directories when stat_file=true"] = function()
  F._now = function() return now end

  vim.fn.delete(test_dir_a)
  F.update_file_score(test_dir_a, {
    _db_dir = _db_dir,
    update_type = "increase",
    stat_file = true,
  })

  MiniTest.expect.equality(
    F.read(dated_files_path)[cwd][test_dir_a],
    nil
  )
end

T["F"]["#update_file_score"]["update_type=remove"] = MiniTest.new_set()
T["F"]["#update_file_score"]["update_type=remove"]["removes entry for existing file"] = function()
  F._now = function() return now end
  F.update_file_score(test_file_a, {
    _db_dir = _db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(F.read(dated_files_path)[cwd][test_file_a], date_at_score_one_now)

  F._now = function() return now end
  F.update_file_score(test_file_a, {
    _db_dir = _db_dir,
    update_type = "remove",
  })

  MiniTest.expect.equality(F.read(dated_files_path)[cwd][test_file_a], nil)
end

T["P"] = MiniTest.new_set {
  hooks = {
    post_case = function()
      P.caches.fd_files = {}
      P.caches.frecency_files = {}
      P.caches.frecency_file_to_score = {}
      P.caches.icon_cache = {}
      P.caches.open_buffer_to_modified = {}
      P.caches.weighted_files_for_empty_query = {}
      P.caches.weighted_files_per_query = {}
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
  local result = P.format_filename("path/to/dir/src/file.lua", 12.34, "📄")
  MiniTest.expect.equality(result, "12.34 📄 |src/file.lua")
end
T["P"]["format_filename"]["formats without icon when icon_char is nil"] = function()
  local result = P.format_filename("path/to/dir/src/file.lua", 12.34, nil)
  MiniTest.expect.equality(result, "12.34 |src/file.lua")
end
T["P"]["format_filename"]["pads score to MAX_SCORE_LEN"] = function()
  local result = P.format_filename("path/to/dir/file.lua", 1.2, nil)
  MiniTest.expect.equality(result, " 1.20 |file.lua")
end
T["P"]["format_filename"]["uses fit_decimals for score formatting"] = function()
  local result = P.format_filename("path/to/dir/file.lua", 123.456789, nil)
  MiniTest.expect.equality(result, "123.4 |file.lua")
end
T["P"]["format_filename"]["handles absolute path when not in cwd"] = function()
  H.cwd = "path/to/another_dir"
  local result = P.format_filename("path/to/dir/file.lua", 12.34, nil)
  MiniTest.expect.equality(result, "12.34 |path/to/dir/file.lua")
end

T["P"]["scale_fzy_to_frecency"] = MiniTest.new_set()
T["P"]["scale_fzy_to_frecency"]["returns MAX_FRECENCY_SCORE for math.huge"] = function()
  local result = P.scale_fzy_to_frecency(math.huge)
  MiniTest.expect.equality(result, P.MAX_FRECENCY_SCORE)
end
T["P"]["scale_fzy_to_frecency"]["returns 0 for -math.huge"] = function()
  local result = P.scale_fzy_to_frecency(-math.huge)
  MiniTest.expect.equality(result, 0)
end
T["P"]["scale_fzy_to_frecency"]["scales positive scores proportionally"] = function()
  local result = P.scale_fzy_to_frecency(20)
  MiniTest.expect.equality(result, 99)
end
T["P"]["scale_fzy_to_frecency"]["scales half max score to half max frecency"] = function()
  local result = P.scale_fzy_to_frecency(10)
  MiniTest.expect.equality(result, 49.5)
end
T["P"]["scale_fzy_to_frecency"]["scales zero score to zero"] = function()
  local result = P.scale_fzy_to_frecency(0)
  MiniTest.expect.equality(result, 0)
end
T["P"]["scale_fzy_to_frecency"]["scales negative scores proportionally"] = function()
  local result = P.scale_fzy_to_frecency(-10)
  MiniTest.expect.equality(result, -49.5)
end
T["P"]["scale_fzy_to_frecency"]["handles scores above MAX_FZY_SCORE"] = function()
  local result = P.scale_fzy_to_frecency(40)
  MiniTest.expect.equality(result, 198)
end
T["P"]["scale_fzy_to_frecency"]["handles fractional scores"] = function()
  local result = P.scale_fzy_to_frecency(5.5)
  MiniTest.expect.equality(result, 27.225)
end

T["P"]["get_icon_info"] = MiniTest.new_set()
T["P"]["get_icon_info"]["returns nil icon when icons_enabled is false"] = function()
  local result = P.get_icon_info {
    icons_enabled = false,
    abs_path = "path/to/file.lua",
  }
  MiniTest.expect.equality(result.icon_char, nil)
  MiniTest.expect.equality(result.icon_hl, nil)
end
T["P"]["get_icon_info"]["returns cached icon when extension exists in cache"] = function()
  P.caches.icon_cache["lua"] = {
    icon_char = "🌙",
    icon_hl = "LuaIcon",
  }

  local result = P.get_icon_info {
    icons_enabled = true,
    abs_path = "path/to/file.lua",
  }

  MiniTest.expect.equality(result.icon_char, "🌙")
  MiniTest.expect.equality(result.icon_hl, "LuaIcon")
end
T["P"]["get_icon_info"]["caches icon info for files with extensions"] = function()
  local result_one = P.get_icon_info {
    icons_enabled = true,
    abs_path = "path/to/file.js",
  }

  MiniTest.expect.equality(result_one.icon_char, "󰌞")
  MiniTest.expect.equality(result_one.icon_hl, "MiniIconsYellow")

  MiniTest.expect.equality(P.caches.icon_cache["js"].icon_char, "󰌞")
  MiniTest.expect.equality(P.caches.icon_cache["js"].icon_hl, "MiniIconsYellow")

  local result_two = P.get_icon_info {
    icons_enabled = true,
    abs_path = "path/to/file.js",
  }
  MiniTest.expect.equality(result_two.icon_char, "󰌞")
  MiniTest.expect.equality(result_two.icon_hl, "MiniIconsYellow")
end

T["P"]["get_weighted_files"] = MiniTest.new_set()
T["P"]["get_weighted_files"]["when the query is cached, it should use the cache"] = function() end
T["P"]["get_weighted_files"]["when the query is not cached, it should update the cache"] = function() end
T["P"]["get_weighted_files"]["should loop through frecent files, then fd files"] = function() end
T["P"]["get_weighted_files"]["should sort the files based on the weighted_score"] = function() end

T["P"]["get_weighted_files"]["get_weighted_file"] = MiniTest.new_set()
T["P"]["get_weighted_files"]["get_weighted_file"]["when the query is empty"] = MiniTest.new_set()
T["P"]["get_weighted_files"]["get_weighted_file"]["when the query is empty"]["when there is a frecency score, it should use it as the weighted_score"] = function() end
T["P"]["get_weighted_files"]["get_weighted_file"]["when the query is empty"]["when there is no frecency score, it should set the weighted_score to 0"] = function() end

T["P"]["get_weighted_files"]["get_weighted_file"]["with no fuzzy match, it should not process the file"] = function() end
T["P"]["get_weighted_files"]["get_weighted_file"]["should apply the basename_boost when the basename matches including the extension"] = function() end
T["P"]["get_weighted_files"]["get_weighted_file"]["should apply the basename_boost when the basename matches excluding the extension"] = function() end
T["P"]["get_weighted_files"]["get_weighted_file"]["should apply the current_buf_boost"] = function() end
T["P"]["get_weighted_files"]["get_weighted_file"]["should apply the alternate_buf_boost"] = function() end
T["P"]["get_weighted_files"]["get_weighted_file"]["should apply the modified_buf_boost"] = function() end
T["P"]["get_weighted_files"]["get_weighted_file"]["should apply the open_buf_boost"] = function() end
T["P"]["get_weighted_files"]["get_weighted_file"]["should apply the frecency score"] = function() end
T["P"]["get_weighted_files"]["get_weighted_file"]["should weight the score according to fuzzy_score_multiple and file_score_multiple"] = function() end

T["P"]["highlight_weighted_files"] = MiniTest.new_set()

return T
