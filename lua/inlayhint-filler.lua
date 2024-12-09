M = {}

---@class InlayHintFillerOpts
---@field bufnr integer
---@field client_id integer|nil

---@type InlayHintFillerOpts
local DEFAULT_OPTS = { bufnr = 0, client_id = nil }

---@param hint_item lsp.InlayHint
---@param original_line string
---@return string
local function make_new_line(hint_item, original_line)
	local hint_text = hint_item.label[1].value
	local hint_col = hint_item.position.character
	if hint_item.paddingLeft then
		hint_text = " " .. hint_text
	end
	if hint_item.paddingRight then
		hint_text = hint_text .. " "
	end
	return original_line:sub(1, hint_col) .. hint_text .. original_line:sub(hint_col + 1)
end

---@param hint_item lsp.InlayHint
---@param opts InlayHintFillerOpts
---@param row integer
---@param col integer
local function insert_hint_item(hint_item, opts, row, col)
	if opts.client_id == nil or opts.client_id == hint_item.client_id then
		local hint_col = hint_item.position.character
		local hint_row = hint_item.position.line
		if hint_row == row and math.abs(hint_col - col) <= 1 then
			if #hint_item.label > 1 then
				vim.notify(
					"More than one labels are collected. Defaulting to the first one.",
					vim.log.levels.WARN,
					{ title = "InlayHint-Filler" }
				)
			end
			vim.api.nvim_set_current_line(make_new_line(hint_item, vim.api.nvim_get_current_line()))
		end
	end
end

---@param opts InlayHintFillerOpts
M.fill = function(opts)
	opts = vim.tbl_deep_extend("keep", opts or {}, DEFAULT_OPTS)
	local hints = vim.lsp.inlay_hint.get({ bufnr = opts.bufnr })
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local row = cursor_pos[1] - 1
	local col = cursor_pos[2]
	if hints ~= nil and #hints >= 1 then
		for _, hint_item in pairs(hints) do
			insert_hint_item(hint_item.inlay_hint, opts, row, col)
		end
	end
end

return M
