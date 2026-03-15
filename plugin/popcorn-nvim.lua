vim.api.nvim_create_user_command('Popcorn', require('popcorn-nvim').execute, { force = true })

-- vim: set et ft=lua sts=2 sw=2 ts=2 :
