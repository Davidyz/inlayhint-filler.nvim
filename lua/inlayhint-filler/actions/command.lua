local config = require("inlayhint-filler.config")
local utils = require("inlayhint-filler.utils")
---@type InlayHintFiller.Action.Callback
local cb = function(hints, ctx)
  local count = 0

  ---@alias (private) cmd_item {hint: lsp.InlayHint, label: lsp.InlayHintLabelPart}

  ---@type {hint: lsp.InlayHint, label: lsp.InlayHintLabelPart}[]
  local commands = {}
  vim.iter(hints):each(
    ---@param hint lsp.InlayHint
    function(hint)
      if type(hint.label) == "table" and #hint.label > 0 then
        local has_cmd = 0
        vim.iter(hint.label):each(
          ---@param part lsp.InlayHintLabelPart
          function(part)
            if part.command ~= nil then
              has_cmd = 1
              commands[#commands + 1] = { hint = hint, label = part }
            end
          end
        )
        count = count + has_cmd
      end
    end
  )

  if count == 0 then
    return 0
  end

  utils.select1(
    vim
      .iter(commands)
      :map(
        ---@param item cmd_item
        function(item)
          return string.format(
            "%s: %s",
            item.label.command.title,
            item.label.command.tooltip or item.label.command.command
          )
        end
      )
      :totable(),
    { prompt = "Command to execute" },
    function(_, idx)
      if idx then
        local command = assert(commands[idx].label.command)
        ctx.client:request(
          "workspace/executeCommand",
          { command = command.command, arguments = command.arguments },
          function(err, result, _, _)
            if err and not vim.tbl_isempty(err) then
              return vim.schedule(function()
                vim.notify(err.message, vim.log.levels.ERROR, config.notify_opts)
              end)
            end
            if result and not vim.tbl_isempty(result) then
              return vim.schedule(function()
                vim.notify(vim.inspect(result), vim.log.levels.INFO, config.notify_opts)
              end)
            end
          end,
          ctx.bufnr
        )
      end
    end
  )

  return count
end

return cb
