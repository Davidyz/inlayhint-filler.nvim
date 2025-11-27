local utils = require("inlayhint-filler.utils")
local lsp = vim.lsp

---@type vim.lsp.util.open_floating_preview.Opts
local preview_opts = {} -- TODO: parametrise this

---Returns a structured representation of the tooltips in the `hint`, if any.
---Returns `nil` when the hint (and its labelparts) doesn't contain any tooltips.
---@param hint lsp.InlayHint
---@param ctx InlayHintFiller.Action.Callback.Context
---@return string[]?
local function make_lines_from_hint(hint, ctx)
  ---@type string[]
  local result = {
    string.format("# %s", require("inlayhint-filler.utils").make_label(hint, false)),
    "",
  }
  local locations = {}

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
          -- NOTE: tooltips have only been tested on hls.
          result[#result + 1] = ""
          if type(_tooltip) == "string" then
            vim.list_extend(
              result,
              { string.format("## `%s`", label.value), "", _tooltip }
            )
          else
            vim.list_extend(
              result,
              vim.split(_tooltip.value, "\n", { trimempty = false })
            )
          end
        end
        if label.location then
          locations[#locations + 1] = { name = label.value, location = label.location }
        end
      end
    )
  end

  if #locations > 0 then
    result[#result + 1] = ""
    result[#result + 1] = "## Locations"
    vim.list_extend(
      result,
      vim
        .iter(locations)
        :map(
          ---@param item {name: string, location: lsp.Location}
          function(item)
            return string.format(
              "- `%s`: %s:%d",
              item.name,
              utils.cleanup_path(
                vim.uri_to_fname(item.location.uri),
                ctx.client.root_dir
              ),
              item.location.range.start.line
            )
          end
        )
        :totable()
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
      local lines_from_hint = make_lines_from_hint(item, _ctx)
      if lines_from_hint then
        count = count + 1
        vim.list_extend(lines, lines_from_hint)
      end
    end
  )

  if count > 0 then
    lsp.util.open_floating_preview(lines, "markdown", preview_opts)
  end
  return count
end

return cb
