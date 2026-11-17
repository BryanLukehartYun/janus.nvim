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
  --- Suppress "loaded X" / "not found" notifications.
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
---@return boolean ok  false only when the colorscheme could not be loaded
local function apply(colorscheme, background)
  local last = state.applied or {}
  if colorscheme == last.colorscheme and background == last.background then
    return true
  end
  local prev_background = vim.o.background
  if background and background ~= prev_background then
    vim.o.background = background
  end
  if colorscheme then
    local ok = pcall(vim.cmd.colorscheme, colorscheme)
    if not ok then
      -- a failed load must not leave a half-applied theme behind
      if vim.o.background ~= prev_background then
        vim.o.background = prev_background
      end
      notify(
        ("colorscheme %q not found; keeping %s"):format(colorscheme, vim.g.colors_name or "default"),
        vim.log.levels.WARN
      )
      return false
    end
    notify("loaded " .. colorscheme)
  end
  state.applied = { colorscheme = colorscheme, background = background or vim.o.background }
  return true
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

  -- Capture the pre-janus theme, but only once a colorscheme actually exists.
  -- If janus's first sync beats the colorscheme plugin, vim.g.colors_name is
  -- nil; recording that as the baseline leaves state.applied.colorscheme nil,
  -- and apply()'s redundancy check then reads any later apply(nil, ...) as a
  -- no-op, so the baseline can never be restored on the way out.
  if not state.baseline and vim.g.colors_name then
    state.baseline = { colorscheme = vim.g.colors_name, background = vim.o.background }
    state.applied = vim.deepcopy(state.baseline)
  end

  local start_dir = opts.dir or utils.buf_dir(0)
  if not start_dir then
    -- special/transient buffer (terminal, help, picker, tree): leave the
    -- theme alone; the next real buffer's BufEnter will re-sync. The one
    -- exception is before any workspace has been resolved (nvim started on a
    -- dashboard or a tree): cwd is the only signal there, and it cannot be
    -- stale yet.
    if state.root ~= nil then
      return
    end
    start_dir = uv.cwd()
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

  local dir = utils.buf_dir(0) or uv.cwd()
  local root, janus_path = utils.resolve_root(M.config.filename, M.config.root_markers, dir)
  local target = janus_path or utils.join(root, M.config.filename)

  -- Apply before writing, so a typo'd colorscheme never reaches disk.
  local _, base_background = revert_target()
  if not apply(colorscheme, background or base_background) then
    return
  end

  local lines = { "# managed by janus.nvim", "colorscheme = " .. colorscheme }
  if background then
    lines[#lines + 1] = "background = " .. background
  end
  local ok = pcall(vim.fn.writefile, lines, target)
  if not ok then
    return notify("failed to write " .. target, vim.log.levels.ERROR)
  end
  notify("wrote " .. target)
  -- pass the dir explicitly: the focused buffer may be a special one
  -- (dashboard, tree), which a plain sync would skip.
  M.sync({ force = true, dir = dir })
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
  local dir = utils.buf_dir(0) or uv.cwd()
  local _, janus_path = utils.resolve_root(M.config.filename, M.config.root_markers, dir)
  if not janus_path then
    return notify("no " .. M.config.filename .. " governs this buffer", vim.log.levels.WARN)
  end
  local ok, err = os.remove(janus_path)
  if not ok then
    return notify("failed to remove " .. janus_path .. ": " .. tostring(err), vim.log.levels.ERROR)
  end
  notify("removed " .. janus_path)
  M.sync({ force = true, dir = dir })
end

-- setup -------------------------------------------------------------------

---@param user_config? JanusConfig
function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_config or {})
  M._did_setup = true
  state.root, state.baseline, state.applied = nil, nil, nil

  local group = vim.api.nvim_create_augroup("janus", { clear = true })
  -- Two things matter for every trigger below:
  --   * `:colorscheme` run from a non-nested autocmd does not fire
  --     `ColorScheme`, so plugins that rebuild their highlights on that event
  --     (file trees, statuslines) would keep the previous theme's colours.
  --   * plugins often set 'buftype' just *after* their buffer is entered; a
  --     sync that runs right at BufEnter sees a normal buffer and resolves it
  --     against cwd. Deferring one tick lets the buffer settle first (and
  --     runs outside the autocmd, so `ColorScheme` fires there too).
  vim.api.nvim_create_autocmd({ "VimEnter", "BufEnter" }, {
    group = group,
    callback = function()
      vim.schedule(M.sync)
    end,
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    nested = true,
    callback = function(ev)
      M.sync({ dir = ev.file or vim.v.event.cwd })
    end,
  })
  -- A `.janus` written by hand usually lands in a root janus has already
  -- resolved, so the root cache would hide it until you left and came back.
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    nested = true,
    callback = function(ev)
      if vim.fs.basename(ev.file) == M.config.filename then
        state.root = nil
        M.sync()
      end
    end,
  })

  if vim.v.vim_did_enter == 1 then
    M.sync({ force = true })
  end
end

return M
