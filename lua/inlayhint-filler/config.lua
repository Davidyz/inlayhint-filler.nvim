local M = {}

---@type InlayHintFiller.Opts
local DEFAULT_OPTS =
  { blacklisted_servers = {}, force = false, eager = false, verbose = false }

local options = vim.deepcopy(DEFAULT_OPTS)

---@param opts InlayHintFiller.Opts|{}
M.setup = function(opts)
  options = vim.tbl_deep_extend("force", options, opts)
end

---@return InlayHintFiller.Opts
M.get_config = function()
  return vim.deepcopy(options)
end

M.notify_opts = { title = "Inlayhint-Filler" }

return M
