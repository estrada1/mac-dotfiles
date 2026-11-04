-- clipboard: always yank/paste via system clipboard.
-- On local sessions (Wayland / macOS) the native provider (wl-clipboard / pbcopy) is used.
-- Over SSH, use OSC 52 so yanks travel to the local machine's clipboard through the terminal.
-- tmux is configured with `set-clipboard on`, so OSC 52 passes through transparently.
vim.opt.clipboard = 'unnamedplus'

-- Let Neovim set the terminal title (e.g. "nvim foo.py") so tools like
-- workstyle can identify Neovim windows inside Alacritty.
vim.opt.title = true

if vim.env.SSH_TTY then
  local osc52 = require('vim.ui.clipboard.osc52')
  vim.g.clipboard = {
    name  = 'OSC 52',
    copy  = { ['+'] = osc52.copy('+'), ['*'] = osc52.copy('*') },
    paste = { ['+'] = osc52.paste('+'), ['*'] = osc52.paste('*') },
  }
end

-- Auto-center specific files with NoNeckPain.
vim.api.nvim_create_autocmd("BufReadPost", {
  pattern = { "*/todo/todo.md" },
  callback = function()
    vim.schedule(function() vim.cmd("NoNeckPain") end)
  end,
})


