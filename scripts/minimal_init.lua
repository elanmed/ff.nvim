-- https://github.com/nvim-mini/mini.test
vim.cmd [[let &rtp.=','.getcwd()]]

if #vim.api.nvim_list_uis() == 0 then
  vim.cmd "set rtp+=deps/mini.test"
  vim.cmd "set rtp+=deps/mini.icons"
  require("mini.icons").setup()
  require("mini.test").setup()
end
