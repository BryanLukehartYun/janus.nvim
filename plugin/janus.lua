if vim.g.loaded_janus then
  return
end
vim.g.loaded_janus = true

-- Auto-init with defaults if the user never calls setup(), so declarative
-- `.janus` switching works out of the box. An explicit setup() still wins
-- (it re-clears the augroup).
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local janus = require("janus")
    if not janus._did_setup then
      janus.setup({})
    end
  end,
})

local function complete_set(arglead, cmdline, _)
  local parts = vim.split(cmdline, "%s+", { trimempty = false })
  -- parts[1] == "JanusSet"; parts[2] == colorscheme; parts[3] == background
  local n = #parts
  if n >= 4 then
    return {}
  end
  if n == 3 then
    return vim.tbl_filter(function(v)
      return vim.startswith(v, arglead)
    end, { "dark", "light" })
  end
  return vim.fn.getcompletion(arglead, "color")
end

vim.api.nvim_create_user_command("JanusSet", function(o)
  require("janus").cmd_set(o.fargs)
end, {
  nargs = "+",
  complete = complete_set,
  desc = "Write .janus for the current workspace and apply it",
})

vim.api.nvim_create_user_command("JanusGet", function()
  require("janus").cmd_get()
end, { desc = "Show the janus config resolved for the current buffer" })

vim.api.nvim_create_user_command("JanusReset", function()
  require("janus").cmd_reset()
end, { desc = "Delete the workspace .janus and restore the default colorscheme" })
