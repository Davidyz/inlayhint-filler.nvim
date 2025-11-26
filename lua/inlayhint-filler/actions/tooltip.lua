local api = vim.api
local fn = vim.fn
local utils = require("inlayhint-filler.utils")

---@param lines string[]
---@return { bufnr: integer, winid: integer }
local function open_float(lines)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  return {
    bufnr = buf,
    winid = api.nvim_open_win(buf, false, { relative = "cursor" }),
  }
end

---Returns a structured representation of the tooltips in the `hint`, if any.
---Returns `nil` when the hint (and its labelparts) doesn't contain any tooltips.
---@param hint lsp.InlayHint
---@return string[]?
local function make_lines_from_hint(hint)
  ---@type string[]
  local result = {
    string.format("# %s", utils.make_label(hint, false)),
    "",
  }

  if hint.tooltip then
    if type(hint.tooltip) == "string" then
      vim.list_extend(result, { hint.tooltip })
    else
      vim.list_extend(
        result,
        vim.split(hint.tooltip.value, "\n", { trimempty = false })
      )
    end
  end

  if type(hint.label) and #hint.label > 0 then
    vim.iter(hint.label):each(
      ---@param label lsp.InlayHintLabelPart
      function(label)
        local _tooltip = label.tooltip
        if _tooltip then
          result[#result + 1] = ""
          if type(_tooltip) == "string" then
            vim.list_extend(
              result,
              { string.format("## %s", label.value), "", _tooltip }
            )
          else
            vim.list_extend(
              result,
              vim.split(_tooltip.value, "\n", { trimempty = false })
            )
          end
        end
      end
    )
  end

  if #result > 2 then
    return result
  end
end

---@type InlayHintFiller.Action.Callback
local function cb(_hints, _ctx)
  ---@type string[]
  local lines = {}
  local count = 0

  vim.iter(_hints):each(
    ---@param item lsp.InlayHint
    function(item)
      local lines_from_hint = make_lines_from_hint(item)
      if lines_from_hint then
        count = count + 1
        vim.list_extend(lines, lines_from_hint)
      end
    end
  )

  if count > 0 then
    open_float(lines)
  end
  return count
end

return cb
