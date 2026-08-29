local M = {}

--- Parse `.janus` file lines into a config table.
--- Recognizes exactly two keys: `colorscheme` and `background`.
--- Blank lines and lines whose first non-blank char is `#` are ignored.
--- `background` must be "dark" or "light"; any other value is dropped.
--- Never errors -- malformed lines are skipped silently.
---@param lines string[]
---@return { colorscheme?: string, background?: "dark"|"light" }
function M.parse(lines)
  local out = {}
  for _, line in ipairs(lines) do
    local s = vim.trim(line)
    if s ~= "" and s:sub(1, 1) ~= "#" then
      local key, value = s:match("^([%w_]+)%s*=%s*(.-)%s*$")
      if key then
        key = key:lower()
        if key == "colorscheme" and value ~= "" then
          out.colorscheme = value
        elseif key == "background" and (value == "dark" or value == "light") then
          out.background = value
        end
      end
    end
  end
  return out
end

--- Read + parse a file by absolute path.
---@param path string
---@return { colorscheme?: string, background?: string }|nil parsed
---@return string|nil err  set when the file could not be read
function M.parse_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil, "cannot read " .. path
  end
  local content = fd:read("*a") or ""
  fd:close()
  return M.parse(vim.split(content, "\n", { plain = true }))
end

return M
