local M = {}

function M.check()
  local mini_icons_ok = pcall(require, "mini.icons")
  if mini_icons_ok then
    vim.health.ok "mini.icons is installed"
  else
    vim.health.error("mini.icons is not installed", {
      "Install mini.icons: https://github.com/echasnovski/mini.icons",
    })
  end

  local fzy_ok = pcall(require, "fzy-lua-native")
  if fzy_ok then
    vim.health.ok "fzy-lua-native is installed"
  else
    vim.health.error("fzy-lua-native is not installed", {
      "Install fzy-lua-native: https://github.com/romgrk/fzy-lua-native",
    })
  end

  if vim.fn.executable "fd" == 1 then
    vim.health.ok "fd is installed"
  else
    vim.health.error("`find` requires fd to be installed", {
      "Install fd: https://github.com/sharkdp/fd",
    })
  end
end

return M
