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

  local fzf_ok = pcall(require, "fzf_lib")
  if fzf_ok then
    vim.health.ok "telescope-fzf-native is installed"
  else
    vim.health.error("telescope-fzf-native is not installed", {
      "Install telescope-fzf-native: https://github.com/nvim-telescope/telescope-fzf-native.nvim",
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
