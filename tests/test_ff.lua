local T = MiniTest.new_set()
_G.FF_TEST = true

local ff = require "ff"
local H = ff._internal.H

T["H"] = MiniTest.new_set()

T["H"]["#default"] = MiniTest.new_set()
T["H"]["#default"]["returns default when value is nil"] = function()
  MiniTest.expect.equality(H.default(nil, "fallback"), "fallback")
  MiniTest.expect.equality(H.default(nil, false), false)
end

local vim_uv_cwd = vim.uv.cwd
T["H"]["#get_rel_file"] = MiniTest.new_set {
  hooks = {
    pre_case = function()
      vim.uv.cwd = function() return "path/to/dir" end
    end,
    post_case = function()
      vim.uv.cwd = vim_uv_cwd
    end,
  },
}

T["H"]["#get_rel_file"]["returns the rel file path when able"] = function()
  MiniTest.expect.equality(H.get_rel_file "path/to/dir/file.txt", "file.txt")
  MiniTest.expect.equality(H.get_rel_file "path/to/another_dir/file.txt", "path/to/another_dir/file.txt")
end
T["H"]["#get_rel_file"]["returns the abs file path as a fallback"] = function()
  MiniTest.expect.equality(H.get_rel_file "path/to/another_dir/file.txt", "path/to/another_dir/file.txt")
end

T["H"]["#get_extension"] = MiniTest.new_set()
T["H"]["#get_extension"]["returns the extension"] = function()
  MiniTest.expect.equality(H.get_extension "path/to/file.txt", "txt")
  MiniTest.expect.equality(H.get_extension "path/to/file.min.txt", "txt")
  MiniTest.expect.equality(H.get_extension "path/to/file", nil)
  MiniTest.expect.equality(H.get_extension "", nil)
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

return T
