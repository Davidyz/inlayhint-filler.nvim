local lsp = vim.lsp
local fn = vim.fn
local utils = require("inlayhint-filler.utils")
local show_document = vim.schedule_wrap(lsp.util.show_document) -- TODO: parametrise this
local lsp_jump_opts = { focus = true, reuse_win = false } -- TODO: parametrise this

---@class (private) LocationItem
---@field hint_name string
---@field hint_position lsp.Position
---@field label_name string
---@field location lsp.Location

---@type InlayHintFiller.Action.Callback
local cb = function(hints, ctx)
  local count = 0

  ---@type LocationItem[]
  local locations = {}

  vim.iter(hints):each(
    ---@param item lsp.InlayHint
    function(item)
      if type(item.label) == "table" and #item.label > 0 then
        local hint_name = assert(utils.make_label(item, false))
        vim.iter(item.label):each(
          ---@param label lsp.InlayHintLabelPart
          function(label)
            if label.location then
              ---@type LocationItem
              locations[#locations + 1] = {
                hint_name = hint_name,
                hint_position = item.position,
                label_name = label.value,
                location = label.location,
              }
            end
          end
        )
        count = count + 1
      end
    end
  )

  if vim.tbl_isempty(locations) then
    return 0
  end

  if #locations == 1 then
    show_document(locations[1].location, ctx.client.offset_encoding, lsp_jump_opts)
  else
    local root_dir = ctx.client.root_dir
    if root_dir then
      root_dir = vim.fs.abspath(root_dir)
    end
    vim.ui.select(
      vim
        .iter(locations)
        :map(
          ---@param loc LocationItem
          function(loc)
            return string.format(
              "%s\t%s:%d",
              loc.label_name,
              utils.cleanup_path(vim.uri_to_fname(loc.location.uri), root_dir),
              loc.location.range.start.line
            )
          end
        )
        :totable(),
      { prompt = "Location to jump to" },
      function(_item, idx)
        if idx then
          show_document(
            locations[idx].location,
            ctx.client.offset_encoding,
            lsp_jump_opts
          )
        end
      end
    )
  end

  return count
end

return cb
