local root = vim.fn.fnamemodify(vim.fn.expand("<sfile>:p"), ":h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(root .. "/tests/fixtures")
vim.opt.swapfile = false
vim.opt.more = false
