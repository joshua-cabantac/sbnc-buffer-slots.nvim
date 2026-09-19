local M = {}

local function is_file_buffer(buf)
	return vim.api.nvim_buf_get_name(buf) ~= "" and vim.bo[buf].buflisted and vim.bo[buf].buftype == ""
end

local function insert_buffer(buffer)
	-- only track real, named file buffers (skip [No Name], term://, scratch)
	if not is_file_buffer(buffer) then
		return
	end
	for index, value in ipairs(M.opened) do
		if value == buffer then -- already tracked, don't duplicate
			return
		elseif value == -1 then
			M.opened[index] = buffer
			break
		end
	end
end

local function delete_buffer(buffer)
	-- BufDelete fires when a buffer becomes unlisted too — and at that moment a
	-- really-closed buffer is not yet invalid/unloaded. Defer the check until
	-- after the event: a real close is then invalid/unloaded, while a mere
	-- listing toggle leaves the buffer alive and loaded.
	vim.schedule(function()
		if vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_buf_is_loaded(buffer) then
			return
		end
		for index, value in ipairs(M.opened) do
			if value == buffer then
				M.opened[index] = -1
				break
			end
		end
	end)
end

-- True if a buffer is an unnamed, unmodified, textless [No Name] buffer.
local function is_empty_unnamed(buf)
	if vim.api.nvim_buf_get_name(buf) ~= "" then
		return false
	end
	if vim.bo[buf].modified then
		return false -- never discard unsaved work
	end
	for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		if line ~= "" then
			return false
		end
	end
	return true
end

-- Remove leftover blank [No Name] buffers (e.g. ones created by pressing an
-- empty slot but never given a file). Never touches the current buffer.
local function cleanup_empty_unnamed()
	local cur = vim.api.nvim_get_current_buf()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if buf ~= cur and vim.api.nvim_buf_is_valid(buf) and is_empty_unnamed(buf) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
end

function M.main()
	M.opened = { -1, -1, -1, -1, -1, -1, -1, -1, -1, -1 }
	cleanup_empty_unnamed()

	-- Assign slots to file buffers already open when the plugin (re)loads.
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		insert_buffer(buf)
	end

	vim.api.nvim_create_autocmd({ "BufNewFile", "BufReadPost" }, {
		callback = function(args)
			insert_buffer(args.buf)
		end,
	})
	vim.api.nvim_create_autocmd("BufDelete", {
		callback = function(args)
			delete_buffer(args.buf)
		end,
	})

	-- Auto-integrate with bufferline.nvim (no-op if it isn't installed).
	M.integrate_bufferline()
end

local function switch_buffer(slot)
	local bufnr = M.opened[slot]
	if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_set_current_buf(bufnr)
		return
	end

	-- Empty or invalid slot: create a new blank (unnamed) listed buffer and bind
	-- it to this slot. The user can then ':e somefile' to load a real file into it,
	-- which stays in this slot thanks to the dedup in insert_buffer().
	local newbuf = vim.api.nvim_create_buf(true, false) -- listed, blank, unnamed
	M.opened[slot] = newbuf
	vim.api.nvim_set_current_buf(newbuf)
end

-- Which slot currently holds the given buffer? Returns slot 1..10 or nil.
local function slot_of(buffer)
	for index, value in ipairs(M.opened) do
		if value == buffer then
			return index
		end
	end
	return nil
end

-- Swap the buffer assignments of two slots.
local function swap_slots(a, b)
	if a == b then
		return
	end
	M.opened[a], M.opened[b] = M.opened[b], M.opened[a]
end

-- Ask any subscribed UI (e.g. bufferline) to re-read the new slot order.
-- IMPORTANT: we clear bufferline's custom_sort (a frozen snapshot) rather than
-- calling bufferline.sort_by(), because sort_by() freezes the order via
-- state.custom_sort and then bufferline permanently IGNORES our live
-- compare_slots comparator. Clearing it makes bufferline fall back to
-- options.sort_by (i.e. M.compare_slots) on every re-render.
local function refresh_subscribers()
	local ok, bstate = pcall(require, "bufferline.state")
	if ok then
		bstate.set({ custom_sort = vim.NIL })
	end
	vim.cmd.redrawtabline()
end

-- Close the gaps between slots: move every tracked file buffer into the lowest
-- slot numbers, preserving their relative order. Blank (unnamed) buffers are
-- ignored — they don't count as content — and are pushed to the tail slots so
-- they stay tracked but out of the way. Example: buffers in slots 1, 2, 8
-- become 1, 2, 3.
local function compact_slots()
	local named, blanks, seen = {}, {}, {}
	for _, bufnr in ipairs(M.opened) do
		if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) and not seen[bufnr] then
			seen[bufnr] = true
			if is_file_buffer(bufnr) then
				table.insert(named, bufnr)
			else
				table.insert(blanks, bufnr)
			end
		end
	end
	local next_slot = 1
	for _, bufnr in ipairs(named) do
		M.opened[next_slot] = bufnr
		next_slot = next_slot + 1
	end
	for _, bufnr in ipairs(blanks) do
		M.opened[next_slot] = bufnr
		next_slot = next_slot + 1
	end
	while next_slot <= #M.opened do
		M.opened[next_slot] = -1
		next_slot = next_slot + 1
	end
	refresh_subscribers()
end

-- Swap the current buffer's slot with the target slot. If the current buffer
-- is not tracked yet, place it into the target slot instead.
local function swap_current_with(slot)
	local cur = vim.api.nvim_get_current_buf()
	local from = slot_of(cur)
	if from then
		swap_slots(from, slot)
	else
		M.opened[slot] = cur
	end
	refresh_subscribers()
end

-- ---------------------------------------------------------------
-- Slot manager: an oil-like scratch buffer whose lines ARE the slots.
-- Reorder lines to reorder slots, delete a line to drop that buffer from
-- its slot, write (:w) to apply. <CR> opens the buffer under the cursor,
-- x closes (bdelete) the buffer under the cursor, q closes the window.
-- ---------------------------------------------------------------
local manager_bufnr = nil

local function manager_render(buf)
	local lines = {}
	for slot, bufnr in ipairs(M.opened) do
		if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
			-- leading token is the bufnr so the buffer stays identifiable even if
			-- the user reorders lines
			lines[#lines + 1] = string.format("%d %s", bufnr, vim.api.nvim_buf_get_name(bufnr))
		end
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

--- Parse the edited manager lines and apply as the new slot order.
local function manager_apply(buf)
	local seen, order = {}, {}
	for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		local bufnr = tonumber(line:match("^%s*(%d+)"))
		if bufnr and not seen[bufnr] and vim.api.nvim_buf_is_valid(bufnr) then
			seen[bufnr] = true
			order[#order + 1] = bufnr
		end
	end
	local next_slot = 1
	for _, bufnr in ipairs(order) do
		if next_slot > #M.opened then break end
		M.opened[next_slot] = bufnr
		next_slot = next_slot + 1
	end
	while next_slot <= #M.opened do
		M.opened[next_slot] = -1
		next_slot = next_slot + 1
	end
	refresh_subscribers()
end

local function manager_open_target()
	local bufnr = tonumber(vim.fn.expand("<cword>"))
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_set_current_buf(bufnr)
	end
end

local function manager_close_buffer()
	local bufnr = tonumber(vim.fn.expand("<cword>"))
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_delete(bufnr, { force = true })
		manager_render(vim.api.nvim_get_current_buf())
	end
end

--- Open the oil-like slot manager in a floating window.
function M.manager()
	if not (manager_bufnr and vim.api.nvim_buf_is_valid(manager_bufnr)) then
		manager_bufnr = vim.api.nvim_create_buf(false, true)
		vim.bo[manager_bufnr].buftype = "acwrite" -- writes trigger BufWriteCmd
		vim.api.nvim_buf_set_name(manager_bufnr, "sbnc://slots")

		vim.api.nvim_create_autocmd("BufWriteCmd", {
			buffer = manager_bufnr,
			callback = function(args)
				manager_apply(args.buf)
				vim.bo[args.buf].modified = false
			end,
		})
		vim.keymap.set("n", "<CR>", manager_open_target, { buffer = manager_bufnr, desc = "Open buffer under cursor" })
		vim.keymap.set("n", "x", manager_close_buffer, { buffer = manager_bufnr, desc = "Close (bdelete) buffer under cursor" })
		vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = manager_bufnr, desc = "Close manager" })
	end
	manager_render(manager_bufnr)
	vim.bo[manager_bufnr].modified = false

	local tracked = 0
	for _, bufnr in ipairs(M.opened) do
		if bufnr ~= -1 then tracked = tracked + 1 end
	end
	vim.cmd(string.format("botright %dsplit sbnc://slots", math.max(3, tracked)))
	-- NOTE: the manager buffer is already unlisted (nvim_create_buf(false, true)).
	-- Do NOT touch buflisted here: toggling it fires BufDelete, which our slot
	-- autocmd would misinterpret as the buffer being closed.
end

local function get_file_buffers()
	local buffers = {}

	for i, buf in ipairs(vim.api.nvim_list_bufs()) do
		if is_file_buffer(buf) then
			table.insert(buffers, buf)
		end
	end
	table.sort(buffers)

	return buffers
end

local function show_buffers()
	vim.print(M.opened)
end

local function switch(buffer)
	local buffers = get_file_buffers()
	vim.api.nvim_set_current_buf(buffers[buffer])
end

-- Move to the next/previous file buffer (by buffer number). Wraps around.
local function step_buffer(step)
	local buffers = get_file_buffers()
	if #buffers == 0 then
		return
	end
	local cur = vim.api.nvim_get_current_buf()
	local idx = 1
	for i, buf in ipairs(buffers) do
		if buf == cur then
			idx = i
			break
		end
	end
	-- Move in direction, wrapping at both ends.
	local n = #buffers
	local next = ((idx - 1 + step) % n) + 1
	vim.api.nvim_set_current_buf(buffers[next])
end

--- Public API: action functions. No keymaps are registered by default.
-- Register your own keys, e.g.:
--   vim.keymap.set("n", "<leader>1", function() require("buffer_slots").switch(1) end)

--- Switch to the buffer in `slot` (1..10). Empty/invalid slots open a new blank
--- buffer bound to that slot.
---@param slot integer
function M.switch(slot)
	switch_buffer(slot)
end

--- Swap the current buffer's slot with `slot` (1..10).
---@param slot integer
function M.swap(slot)
	swap_current_with(slot)
end

--- Switch to the next file buffer (wraps around).
function M.next()
	step_buffer(1)
end

--- Switch to the previous file buffer (wraps around).
function M.prev()
	step_buffer(-1)
end

--- Print the current slot assignments.
function M.list()
	show_buffers()
end

--- Close the gaps: reflow tracked buffers into slots 1..n in their current
--- order. Only real file buffers count; blank (unnamed) buffers are pushed to
--- the tail so they stay tracked. E.g. slots with buffers at 1, 2, 8 become
--- 1, 2, 3.
function M.compact()
	compact_slots()
end

--- Automatically integrate with bufferline.nvim if it is installed: tabs are
--- sorted by slot number and prefixed with it. Works regardless of load order
--- because it wraps bufferline.setup() so the hooks merge into any setup() call,
--- and re-applies them if bufferline was already configured before this ran.
--- No-ops when bufferline is not installed.
function M.integrate_bufferline()
	local ok, bufferline = pcall(require, "bufferline")
	if not ok or type(bufferline.setup) ~= "function" then
		return false
	end
	if bufferline.__sbnc_hooks then
		return true -- already integrated
	end

	local hooks = {
		sort_by = function(a, b)
			return M.compare_slots(a.id, b.id)
		end,
		name_formatter = function(buf)
			local slot = M.slot_for(buf.bufnr)
			return slot and (slot .. " " .. buf.name) or buf.name
		end,
	}

	local orig_setup = bufferline.setup
	bufferline.setup = function(conf)
		conf = vim.tbl_deep_extend("force", conf or {}, { options = hooks })
		return orig_setup(conf)
	end
	bufferline.__sbnc_hooks = true

	-- bufferline already set up before we loaded: re-apply with the user's own
	-- config merged in so the hooks take effect now, not just on a later setup().
	local active = vim.o.tabline and vim.o.tabline:find("nvim_bufferline", 1, true)
	if active then
		local ok_cfg, bconfig = pcall(require, "bufferline.config")
		local user = ok_cfg and bconfig.get() and bconfig.get().user
		orig_setup(vim.tbl_deep_extend("force", user or {}, { options = hooks }))
	end
	return true
end

--- Optional setup. Currently only controls the bufferline integration.
--- Call `require("sbnc_buffer_slots").setup({ bufferline = false })` to opt out.
---@param opts { bufferline: boolean? }?
function M.setup(opts)
	opts = opts or {}
	if opts.bufferline ~= false then
		M.integrate_bufferline()
	end
end

M.main()

--- Comparator for bufferline: order buffers by their slot position (1..10).
--- Buffers not in any slot sort after all slotted ones, ordered by bufnr.
---@param bufnr_a integer
---@param bufnr_b integer
---@return boolean true if bufnr_a should appear before bufnr_b
function M.compare_slots(bufnr_a, bufnr_b)
	local sa = slot_of(bufnr_a)
	local sb = slot_of(bufnr_b)
	if sa and sb then
		return sa < sb
	end
	if sa then
		return true -- a is in a slot, b is not
	end
	if sb then
		return false
	end
	return bufnr_a < bufnr_b
end

--- Return the slot number (1..10) holding a buffer, or nil if not tracked.
---@param bufnr integer
---@return integer? slot
function M.slot_for(bufnr)
	return slot_of(bufnr)
end

return M
