local uv = vim.uv or vim.loop

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then
    pass = pass + 1
    print("ok   - " .. name)
  else
    fail = fail + 1
    print("NOT  - " .. name)
  end
end

-- parser ------------------------------------------------------------------
local parser = require("janus.parser")
local p = parser.parse({
  "# comment",
  "",
  "  colorscheme = janustwo  ",
  "background = light",
  "junk = 9",
})
ok(p.colorscheme == "janustwo", "parse: colorscheme")
ok(p.background == "light", "parse: background")
ok(p.junk == nil, "parse: unknown key ignored")
ok(parser.parse({ "background = purple" }).background == nil, "parse: bad background dropped")
ok(select(1, parser.parse_file("/no/such/file")) == nil, "parse_file: missing file -> nil")

-- utils -----------------------------------------------------------------
local utils = require("janus.utils")
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/a/b/c", "p")
vim.fn.writefile({ "colorscheme = janustwo" }, tmp .. "/.janus")
local found = utils.find_janus(".janus", tmp .. "/a/b/c")
ok(found and vim.fs.basename(found) == ".janus", "utils: walks upward to .janus")
ok(found and vim.fn.resolve(vim.fs.dirname(found)) == vim.fn.resolve(tmp), "utils: correct dir")
ok(utils.find_janus(".janus", vim.fn.tempname()) == nil, "utils: none found -> nil")

-- nested repo: an inner .git shadows an outer .janus
local nest = vim.fn.tempname()
vim.fn.mkdir(nest .. "/inner/.git", "p")
vim.fn.mkdir(nest .. "/inner/src", "p")
vim.fn.writefile({ "colorscheme = janustwo" }, nest .. "/.janus")
ok(utils.find_janus(".janus", nest .. "/inner/src") ~= nil, "utils: still finds outer .janus with no markers given")
ok(utils.find_janus(".janus", nest .. "/inner/src", { ".git" }) == nil, "utils: inner .git shadows the outer .janus")
vim.fn.writefile({ "colorscheme = janusone" }, nest .. "/inner/.janus")
ok(
  utils.find_janus(".janus", nest .. "/inner/src", { ".git" }) == nest .. "/inner/.janus",
  "utils: a .janus at the inner root still governs"
)

-- plugin/ auto-init ---------------------------------------------------
-- plugin/janus.lua must auto-init even with no opts/config: on a normal load
-- via its VimEnter autocmd, and -- when a plugin manager sources it lazily
-- after VimEnter has already fired -- immediately, since the `once` autocmd
-- would never run in that case and janus would silently do nothing.
local plugin_file = vim.api.nvim_get_runtime_file("plugin/janus.lua", false)[1]

-- (a) sourced before VimEnter: autocmd is armed, then fires on VimEnter.
vim.g.loaded_janus = nil
vim.cmd.source(plugin_file)
ok(vim.fn.exists("#janus_autoinit#VimEnter") == 1, "auto-init: VimEnter autocmd armed pre-startup")
vim.cmd("doautocmd VimEnter")
ok(require("janus")._did_setup, "auto-init: VimEnter runs setup() with no opts")
ok(vim.fn.exists("#janus#BufEnter") == 1, "auto-init: sync augroup registered")
ok(vim.fn.exists(":JanusSet") == 2, "auto-init: commands registered")

-- (b) sourced after VimEnter (the lazy-load-on-an-event path): init must run
-- inline rather than only arm a `once` autocmd that can never fire again.
-- Headless startup keeps vim.v.vim_did_enter at 0 and a nested nvim under
-- vim.fn.system() hangs, so this can't be exercised live here -- assert the
-- source keeps the vim_did_enter branch instead. The live check is the
-- `{ "BryanLukehartYun/janus.nvim", event = "VeryLazy" }` smoke test.
local src = table.concat(vim.fn.readfile(plugin_file), "\n")
ok(
  src:find("vim%.v%.vim_did_enter == 1", 1) ~= nil and src:find("auto_init%(%)", 1) ~= nil,
  "auto-init: plugin/ initialises inline when vim_did_enter is set"
)

-- integration ---------------------------------------------------------
require("janus").setup({ default_colorscheme = "janusone", silent = true })
ok(vim.fn.exists(":JanusSet") == 2, "command registered")

vim.cmd.edit(tmp .. "/a/b/c/file.txt")
require("janus").sync({ force = true })
ok(vim.g.colors_name == "janustwo", "integration: applies workspace colorscheme")

vim.cmd.edit(vim.fn.tempname() .. ".txt")
require("janus").sync({ force = true })
ok(vim.g.colors_name == "janusone", "integration: restores default outside workspace")

-- :JanusReset ---------------------------------------------------------
vim.cmd.edit(tmp .. "/a/b/c/file.txt")
require("janus").sync({ force = true })
require("janus").cmd_reset()
ok(uv.fs_stat(tmp .. "/.janus") == nil, "JanusReset: file removed")
ok(vim.g.colors_name == "janusone", "JanusReset: default restored")

-- special buffers don't drive sync ----------------------------------
vim.fn.writefile({ "colorscheme = janustwo" }, tmp .. "/.janus")
require("janus").setup({ default_colorscheme = "janusone", silent = true })
vim.cmd.edit(tmp .. "/a/b/c/file.txt")
require("janus").sync({ force = true })
ok(vim.g.colors_name == "janustwo", "special-buf: workspace theme applied")

vim.cmd.enew()
vim.bo.buftype = "nofile"
vim.cmd.colorscheme("janustwo")
require("janus").sync() -- current buffer is special -> must not touch the theme
ok(vim.g.colors_name == "janustwo", "special-buf: scratch buffer leaves theme alone")

-- revert on a plain buffer switch, no force ------------------------
vim.cmd.edit(tmp .. "/a/b/c/file.txt")
require("janus").sync()
ok(vim.g.colors_name == "janustwo", "no-force: re-enter workspace applies theme")
vim.cmd.edit(vim.fn.tempname() .. ".txt")
require("janus").sync()
ok(vim.g.colors_name == "janusone", "no-force: leaving workspace reverts to default")

-- sticky = true: apply on entry, never revert ---------------------
require("janus").setup({ default_colorscheme = "janusone", sticky = true, silent = true })
vim.cmd.edit(tmp .. "/a/b/c/file.txt")
require("janus").sync({ force = true })
ok(vim.g.colors_name == "janustwo", "sticky: workspace theme applied on entry")
vim.cmd.edit(vim.fn.tempname() .. ".txt")
require("janus").sync()
ok(vim.g.colors_name == "janustwo", "sticky: leaving workspace keeps the theme")
vim.cmd.edit(tmp .. "/a/b/c/file.txt") -- back inside; :JanusReset acts on the governing .janus
require("janus").sync()
require("janus").cmd_reset() -- forced restore still works under sticky
ok(vim.g.colors_name == "janusone", "sticky: :JanusReset still restores default")

-- baseline colorscheme captured lazily (no default_colorscheme) ----
vim.fn.writefile({ "colorscheme = janustwo" }, tmp .. "/.janus")
vim.cmd.colorscheme("janusone")
require("janus").setup({ silent = true })
vim.cmd.edit(tmp .. "/a/b/c/file.txt")
require("janus").sync({ force = true })
ok(vim.g.colors_name == "janustwo", "baseline: workspace theme applied")
vim.cmd.edit(vim.fn.tempname() .. ".txt")
require("janus").sync({ force = true })
ok(vim.g.colors_name == "janusone", "baseline: reverts to the colorscheme active at first sync")

-- no colorscheme at first sync: baseline capture must wait for one -------
-- If janus's first sync beats the colorscheme plugin, vim.g.colors_name is
-- nil. janus must not latch that as the baseline (which would wedge apply()
-- on {nil,nil}), and leaving a workspace with nothing to revert to must be
-- a no-op rather than a crash.
vim.fn.writefile({ "colorscheme = janustwo" }, tmp .. "/.janus")
vim.g.colors_name = nil
require("janus").setup({ silent = true })
vim.cmd.edit(tmp .. "/a/b/c/file.txt")
require("janus").sync({ force = true })
ok(vim.g.colors_name == "janustwo", "no-baseline: workspace theme still applies")
vim.cmd.edit(vim.fn.tempname() .. ".txt")
local ok_leave = pcall(function()
  require("janus").sync({ force = true })
end)
ok(ok_leave and vim.g.colors_name == "janustwo", "no-baseline: leaving is a no-op, no error")

-- shim colorscheme: .janus name differs from the resulting colors_name -----
-- `januslight` renders a light variant but reports colors_name = "janusone",
-- like cyberdream-light. Revert must still re-source even though the name
-- janus wants to restore already equals colors_name.
vim.fn.writefile({ "colorscheme = januslight" }, tmp .. "/.janus")
vim.cmd.colorscheme("janusone")
require("janus").setup({ default_colorscheme = "janusone", silent = true })
vim.cmd.edit(tmp .. "/a/b/c/file.txt")
require("janus").sync({ force = true })
ok(vim.g.janus_variant == "light", "shim cs: workspace variant applied")
vim.cmd.edit(vim.fn.tempname() .. ".txt")
require("janus").sync({ force = true })
ok(vim.g.janus_variant == "one", "shim cs: revert re-sources despite unchanged colors_name")

print(("\n%d passed, %d failed"):format(pass, fail))
vim.cmd(fail == 0 and "qa!" or "cq")
