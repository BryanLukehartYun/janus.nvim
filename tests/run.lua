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
-- It must be deferred one tick (vim.schedule), not run inline: the manager
-- calls the user's setup(opts) right after sourcing, and that has to win.
ok(
  src:find("vim%.v%.vim_did_enter == 1", 1) ~= nil and src:find("vim%.schedule%(auto_init%)", 1) ~= nil,
  "auto-init: plugin/ initialises (deferred) when vim_did_enter is set"
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

-- ======================================================================
-- Regressions driven through the real autocmds (not direct sync() calls).
-- The BufEnter sync is deferred one tick, so `settle()` pumps the loop.
-- ======================================================================
local janus = require("janus")
local function settle()
  vim.wait(20)
end
local ws = vim.fn.tempname()
for _, d in ipairs({ "A/.git", "A/src", "B/.git", "C/.git" }) do
  vim.fn.mkdir(ws .. "/" .. d, "p")
end
vim.fn.writefile({ "colorscheme = janustwo" }, ws .. "/A/.janus")
local function fresh(opts)
  settle()
  vim.cmd("silent! %bwipeout!")
  vim.cmd.colorscheme("janusone")
  janus.setup(vim.tbl_extend("force", { silent = true }, opts or {}))
end

-- parser: quoted values
ok(parser.parse({ 'colorscheme = "janustwo"' }).colorscheme == "janustwo", "parse: double-quoted value")
ok(parser.parse({ "background = 'light'" }).background == "light", "parse: single-quoted value")

-- ColorScheme must fire when janus switches from its own autocmds, or other
-- plugins (file trees, statuslines) keep the previous theme's highlights.
fresh()
local fired = 0
local cs_au = vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    fired = fired + 1
  end,
})
vim.cmd.edit(ws .. "/B/g.lua")
settle()
fired = 0
vim.cmd.edit(ws .. "/A/src/f.lua")
settle()
ok(vim.g.colors_name == "janustwo", "autocmd: BufEnter applies the workspace theme")
ok(fired == 1, "autocmd: ColorScheme fires on apply")
fired = 0
vim.cmd.edit(ws .. "/B/g.lua")
settle()
ok(vim.g.colors_name == "janusone" and fired == 1, "autocmd: ColorScheme fires on revert")
vim.api.nvim_del_autocmd(cs_au)

-- A plugin buffer that sets 'buftype' right after being entered (file trees)
-- must not be resolved against cwd.
fresh()
vim.cmd.cd(ws .. "/B")
vim.cmd.edit(ws .. "/A/src/f.lua")
settle()
vim.cmd("vsplit | enew")
vim.api.nvim_buf_set_name(0, "janus-fake-tree [1]")
vim.bo.buftype = "nofile"
settle()
ok(vim.g.colors_name == "janustwo", "late buftype: tree-like buffer does not flip the theme")
vim.cmd("only")

-- Directory buffers (`nvim some/dir`) resolve to the directory itself.
fresh()
vim.cmd.edit(ws .. "/A")
ok(
  vim.fn.resolve(utils.buf_dir(0)) == vim.fn.resolve(ws .. "/A"),
  "dir buffer: buf_dir is the directory, not its parent"
)
settle()
ok(vim.g.colors_name == "janustwo", "dir buffer: workspace theme applied")

-- Started on a special buffer (dashboard): cwd decides until a root is known.
settle()
vim.cmd("silent! %bwipeout!")
vim.cmd.colorscheme("janusone")
vim.api.nvim_create_augroup("janus", { clear = true }) -- so the cd below is not a DirChanged sync
vim.cmd.cd(ws .. "/A")
vim.bo.buftype = "nofile"
janus.setup({ silent = true })
janus.sync()
ok(vim.g.colors_name == "janustwo", "dashboard start: cwd's workspace theme applied")
vim.cmd.cd(ws .. "/B")
vim.cmd.colorscheme("janustwo")
janus.sync()
ok(vim.g.colors_name == "janustwo", "dashboard start: later special-buffer syncs stay inert")

-- :JanusSet / :JanusReset from a special buffer act on cwd and take effect.
fresh()
vim.cmd.edit(ws .. "/B/g.lua")
settle()
vim.cmd.cd(ws .. "/C")
vim.cmd.enew()
vim.bo.buftype = "nofile"
settle()
janus.cmd_set({ "janustwo" })
ok(uv.fs_stat(ws .. "/C/.janus") ~= nil, "JanusSet (special buf): file written at cwd's root")
ok(vim.g.colors_name == "janustwo", "JanusSet (special buf): theme applied")
janus.cmd_reset()
ok(
  uv.fs_stat(ws .. "/C/.janus") == nil and vim.g.colors_name == "janusone",
  "JanusReset (special buf): removed + reverted"
)

-- :JanusSet with an unknown colorscheme writes nothing and changes nothing.
fresh()
vim.cmd.edit(ws .. "/B/g.lua")
settle()
vim.o.background = "dark"
janus.cmd_set({ "no_such_scheme_xyz", "light" })
ok(uv.fs_stat(ws .. "/B/.janus") == nil, "JanusSet typo: nothing written")
ok(vim.g.colors_name == "janusone" and vim.o.background == "dark", "JanusSet typo: theme and background untouched")

-- A hand-written .janus in an already-resolved root applies on save.
fresh()
vim.cmd.edit(ws .. "/B/g.lua")
settle()
vim.cmd.edit(ws .. "/B/.janus")
settle()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "colorscheme = janustwo" })
vim.cmd("silent write")
ok(vim.g.colors_name == "janustwo", "hand-written .janus: applied on write")
vim.fn.delete(ws .. "/B/.janus")

print(("\n%d passed, %d failed"):format(pass, fail))
vim.cmd(fail == 0 and "qa!" or "cq")
