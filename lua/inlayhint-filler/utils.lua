local M = {}
local fs = vim.fs

---@param hint lsp.InlayHint
---@param with_padding? boolean
---@return string?
function M.make_label(hint, with_padding)
  ---@type string?
  local label
  if type(hint.label) == "string" then
    label = tostring(hint.label)
    if with_padding then
      if hint.paddingLeft then
        label = " " .. label
      end
      if hint.paddingRight then
        label = label .. " "
      end
    end
  elseif vim.islist(hint.label) then
    label = vim
      .iter(hint.label)
      :map(
        ---@param part lsp.InlayHintLabelPart
        function(part)
          return part.value
        end
      )
      :join("")
  end
  return label
end

---@param path string
---@param base string?
---@return string
function M.cleanup_path(path, base)
  path = fs.abspath(path)
  if base then
    base = fs.abspath(base)
    if base:find("/$") == nil then
      base = base .. "/"
    end
  end

  local result

  if base and path:sub(1, base:len()) == base then
    result = path:sub(base:len() + 1)
  else
    local home = vim.env.HOME
    result = (path:gsub("^" .. home, "~"))
  end

  return result
end

return M
