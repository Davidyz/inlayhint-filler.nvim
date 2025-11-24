local lsp = vim.lsp
local apply_text_edits = vim.schedule_wrap(lsp.util.apply_text_edits)
local notify = vim.schedule_wrap(vim.notify)
local config = require("inlayhint-filler.config")

---@param hint lsp.InlayHint
---@param ctx InlayHintFiller.Callback.Context
---@return lsp.TextEdit[]
local function get_edits(hint, ctx)
  local options = config.get_config()
  local force = options.force

  if hint.textEdits and #hint.textEdits > 0 then
    return hint.textEdits
  end

  if type(force) == "function" then
    force = force({ bufnr = ctx.bufnr, hint = hint }) ---@cast force -function
  end
  local log_level = vim.log.levels.ERROR
  if force then
    log_level = vim.log.levels.WARN
  end
  notify(
    "Failed to extract text edits from the provided inlayhint"
      .. (
        config.get_config().verbose
          and string.format(":\n```lua\n%s```", vim.inspect(hint))
        or "."
      ),
    log_level,
    config.notify_opts
  )
  if force then
    ---@type string?
    local new_text
    if type(hint.label) == "string" then
      new_text = string.format(
        "%s%s%s",
        hint.paddingLeft and " " or "",
        hint.label,
        hint.paddingRight and " " or ""
      )
    else
      new_text = vim
        .iter(hint.label)
        :map(
          ---@param item lsp.InlayHintLabelPart
          function(item)
            return item.value
          end
        )
        :join("")
    end
    return {
      range = { start = hint.position, ["end"] = hint.position },
      newText = new_text,
    }
  else
    return {}
  end
end

---@type InlayHintFiller.Callback
local cb = function(hints, ctx)
  local count = 0
  if #hints == 0 then
    return count
  end
  apply_text_edits(
    vim
      .iter(hints)
      :map(
        ---@param item lsp.InlayHint
        function(item)
          local edits = get_edits(item, ctx)
          count = count + #edits
          return edits
        end
      )
      :flatten(1)
      :totable(),
    ctx.bufnr,
    ctx.client.offset_encoding
  )
  return count
end

return cb
