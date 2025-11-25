local M = {}

---@param hint lsp.InlayHint
---@param with_padding boolean
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

return M
