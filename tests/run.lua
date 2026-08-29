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
