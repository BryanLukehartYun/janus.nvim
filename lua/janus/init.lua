local parser = require("janus.parser")
local utils = require("janus.utils")

local uv = vim.uv or vim.loop

local M = {}

---@class JanusConfig
local defaults = {
  --- Name of the per-project file.
  filename = ".janus",
  --- Colorscheme to restore outside any `.janus` workspace.
  --- nil => the colorscheme active the first time janus runs this session.
  default_colorscheme = nil,
  --- Background to restore outside any workspace.
  --- nil => 'background' as it stood the first time janus runs this session.
  default_background = nil,
  --- When true, janus applies a `.janus` theme whenever it finds one but
  --- never reverts on leaving -- the last theme "sticks" until a different
  --- `.janus` or a manual `:colorscheme` / `:JanusReset` changes it.
  sticky = false,
  --- Directory markers used to identify a project root when no `.janus`
  --- exists (only affects caching + where :JanusSet writes).
  root_markers = { ".git" },
  --- Suppress "loaded X" / "not found" / "unknown key" notifications.
  silent = false,
}

M.config = vim.deepcopy(defaults)
M._did_setup = false

-- session state:
--   root     - last resolved workspace root, for change detection
--   baseline - the pre-janus theme, captured lazily on the first sync so it
--              survives a colorscheme plugin that loads after janus
--   applied  - the colorscheme/background pair janus last handed to the
--              editor, so it knows when a real change is needed (see apply())
local state = { root = nil, baseline = nil, applied = nil }

local function notify(msg, level)
  if M.config.silent then
    return
  end
  vim.notify("[janus] " .. msg, level or vim.log.levels.INFO)
end

--- (Re)apply a colorscheme + 'background' pair.
---
--- The redundancy check compares against what janus *itself* last applied,
--- not `vim.g.colors_name`: a colorscheme may report a name that differs
--- from the one you load (`cyberdream-light` sets `colors_name = cyberdream`),
--- and a light<->dark switch on the *same* name still needs a full reload to
--- re-render. `M.sync`'s root cache already prevents calls within a
--- workspace, so this only fires on a genuine workspace change.
---@param colorscheme string|nil
---@param background string|nil
local function apply(colorscheme, background)
  local last = state.applied or {}
  if colorscheme == last.colorscheme and background == last.background then
    return
  end
  if background then
    vim.o.background = background
  end
  if colorscheme then
    local ok = pcall(vim.cmd.colorscheme, colorscheme)
    if not ok then
      notify(
        ("colorscheme %q not found; keeping %s"):format(colorscheme, vim.g.colors_name or "default"),
        vim.log.levels.WARN
      )
      return
    end
    notify("loaded " .. colorscheme)
  end
  state.applied = { colorscheme = colorscheme, background = background or vim.o.background }
end

--- The theme janus restores outside any workspace: an explicit config value,
--- else the colorscheme/background that was active the first time janus ran.
---@return string|nil colorscheme
---@return string|nil background
local function revert_target()
  local base = state.baseline or {}
  return M.config.default_colorscheme or base.colorscheme, M.config.default_background or base.background
end

--- Resolve what the current buffer's workspace wants and apply it, unless the
--- workspace root is unchanged since the last call.
---@param opts? { force?: boolean, dir?: string }
function M.sync(opts)
  opts = opts or {}

  if not state.baseline then
    state.baseline = { colorscheme = vim.g.colors_name, background = vim.o.background }
    state.applied = { colorscheme = vim.g.colors_name, background = vim.o.background }
  end

  local start_dir = opts.dir or utils.buf_dir(0)
  if not start_dir then
    -- special/transient buffer (terminal, help, picker, tree): leave the
    -- theme alone; the next real buffer's BufEnter will re-sync.
    return
  end
  local root, janus_path = utils.resolve_root(M.config.filename, M.config.root_markers, start_dir)

  if not opts.force and root == state.root then
    return
  end
  state.root = root

  if not janus_path and M.config.sticky and not opts.force then
    -- sticky mode: never revert on a plain buffer switch; the current theme
    -- carries over. An explicit force (:JanusReset) still restores.
    return
  end

  local cs, bg = revert_target()
  if janus_path then
    local parsed = parser.parse_file(janus_path) or {}
    cs = parsed.colorscheme or cs
    bg = parsed.background or bg
  end
  apply(cs, bg)
end

--- Resolved config for the current buffer, for :JanusGet.
---@return { root: string, source: string, colorscheme: string?, background: string?, sticky: boolean }
function M.inspect()
  local root, janus_path = utils.resolve_root(M.config.filename, M.config.root_markers, utils.buf_dir(0) or uv.cwd())
  local cs, bg = revert_target()
  local source = "default"
  if janus_path then
    local parsed = parser.parse_file(janus_path) or {}
    cs, bg = parsed.colorscheme or cs, parsed.background or bg
    source = janus_path
  end
  return { root = root, source = source, colorscheme = cs, background = bg, sticky = M.config.sticky }
end

-- command backends (called from plugin/janus.lua) ---------------------------

---@param fargs string[]
function M.cmd_set(fargs)
  local colorscheme, background = fargs[1], fargs[2]
  if not colorscheme then
    return notify("usage: JanusSet <colorscheme> [dark|light]", vim.log.levels.ERROR)
  end
  if background and background ~= "dark" and background ~= "light" then
    return notify("background must be 'dark' or 'light'", vim.log.levels.ERROR)
  end

  local root, janus_path = utils.resolve_root(M.config.filename, M.config.root_markers, utils.buf_dir(0) or uv.cwd())
  local target = janus_path or utils.join(root, M.config.filename)

  local lines = { "# managed by janus.nvim", "colorscheme = " .. colorscheme }
  if background then
    lines[#lines + 1] = "background = " .. background
  end
  local ok = pcall(vim.fn.writefile, lines, target)
  if not ok then
    return notify("failed to write " .. target, vim.log.levels.ERROR)
  end
  notify("wrote " .. target)
  state.root = nil
  M.sync({ force = true })
end

function M.cmd_get()
  local r = M.inspect()
  -- always prints, even when silent
  vim.notify(([[[janus]
  root:        %s
  source:      %s
  colorscheme: %s
  background:  %s
  sticky:      %s]]):format(r.root, r.source, r.colorscheme or "-", r.background or "-", tostring(r.sticky)))
end

function M.cmd_reset()
  local _, janus_path = utils.resolve_root(M.config.filename, M.config.root_markers, utils.buf_dir(0) or uv.cwd())
  if not janus_path then
    return notify("no " .. M.config.filename .. " governs this buffer", vim.log.levels.WARN)
  end
  local ok, err = os.remove(janus_path)
  if not ok then
    return notify("failed to remove " .. janus_path .. ": " .. tostring(err), vim.log.levels.ERROR)
  end
  notify("removed " .. janus_path)
  state.root = nil
  M.sync({ force = true })
end

-- setup -------------------------------------------------------------------

---@param user_config? JanusConfig
function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_config or {})
  M._did_setup = true
  state.root, state.baseline, state.applied = nil, nil, nil

  local group = vim.api.nvim_create_augroup("janus", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "BufEnter" }, {
    group = group,
    callback = function()
      M.sync()
    end,
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function(ev)
      M.sync({ dir = ev.file or vim.v.event.cwd })
    end,
  })

  if vim.v.vim_did_enter == 1 then
    M.sync({ force = true })
  end
end

return M
