local M = {}

function M.check()
  local opts = vim.g.ff or {}
  if opts.icons_enabled then
    local mini_icons_ok = pcall(require, "mini.icons")
    local devicons_ok = pcall(require, "nvim-web-devicons")

    if not devicons_ok and not mini_icons_ok then
      vim.health.error("vim.g.ff.icons_enabled=true, but no icon library is installed", {
        "Install mini.icons: https://github.com/echasnovski/mini.icons",
        "Install nvim-web-devicons: https://github.com/nvim-tree/nvim-web-devicons",
      })
    end
  else
    vim.health.ok "vim.g.ff.icons_enabled=false, no icon library is required"
  end

  if opts.find_cmd == nil then
    if vim.fn.executable "fd" == 1 then
      vim.health.ok "fd is installed"
    else
      vim.health.error("vim.g.ff.find_cmd is not set, but the default executable fd is not installed", {
        "Install fd: https://github.com/sharkdp/fd",
      })
    end
  else
    vim.health.ok "vim.g.ff.find_cmd is set, the default executable fd is not required"
  end
end

return M
