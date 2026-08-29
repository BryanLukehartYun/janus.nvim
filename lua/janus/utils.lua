local M = {}

local uv = vim.uv or vim.loop

--- Directory to start searching from for the given buffer.
--- Named, normal buffers -> their directory. A normal *unnamed* buffer
--- (fresh `:enew`, the startup buffer) -> the current working directory.
--- Special buffers (`buftype ~= ""`: terminals, help, quickfix, plugin
--- pickers and trees) -> `nil`; the theme should not react to those, so
--- callers skip the sync entirely rather than resolving against cwd (which
--- lags behind `:e` and causes the theme to flip-flop).
---@param bufnr? integer
---@return string|nil
function M.buf_dir(bufnr)
  bufnr = bufnr or 0
  if vim.bo[bufnr].buftype ~= "" then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return uv.cwd()
  end
  return vim.fs.dirname(name)
end

--- Nearest `.janus` file at or above `start_dir`, bounded by $HOME.
---
--- If `root_markers` is given, the search stops at a project boundary: a
--- `.janus` that sits *above* a nearer directory containing a marker
--- (`.git`) is ignored, so a repo nested inside another repo does not
--- inherit the outer repo's theme. A `.janus` at, or below, the nearest
--- marker still governs.
---@param filename string
---@param start_dir string
---@param root_markers? string[]
---@return string|nil  absolute path to the file
function M.find_janus(filename, start_dir, root_markers)
  local home = uv.os_homedir()
  local stop = home and vim.fs.dirname(home) or nil
  local janus = vim.fs.find(filename, {
    upward = true,
    type = "file",
    path = start_dir,
    stop = stop,
    limit = 1,
  })[1]
  if not janus or not root_markers then
    return janus
  end

  local janus_dir = vim.fs.dirname(janus)
  local marker = vim.fs.find(root_markers, { upward = true, path = start_dir, limit = 1 })[1]
  if marker then
    local marker_dir = vim.fs.dirname(marker)
    -- marker_dir strictly below janus_dir => a nearer project root shadows it
    if marker_dir ~= janus_dir and vim.startswith(marker_dir, janus_dir == "/" and "/" or janus_dir .. "/") then
      return nil
    end
  end
  return janus
end

--- Resolve a stable identity ("root key") for the buffer's workspace plus the
--- `.janus` path if one governs it. Used both for change-detection caching and
--- to decide where `:JanusSet` writes.
---
--- root key = dir of the nearest governing `.janus`, else dir of the nearest
--- project marker, else `start_dir`.
---@param filename string
---@param root_markers string[]
---@param start_dir string
---@return string root_key
---@return string|nil janus_path
function M.resolve_root(filename, root_markers, start_dir)
  local janus_path = M.find_janus(filename, start_dir, root_markers)
  if janus_path then
    return vim.fs.dirname(janus_path), janus_path
  end
  local marker = vim.fs.find(root_markers, {
    upward = true,
    path = start_dir,
    limit = 1,
  })[1]
  if marker then
    return vim.fs.dirname(marker), nil
  end
  return start_dir, nil
end

--- Join a dir and a filename (POSIX; Windows is not supported).
---@param dir string
---@param name string
---@return string
function M.join(dir, name)
  return (dir:gsub("/*$", "")) .. "/" .. name
end

return M
