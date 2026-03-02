---@mod notebook.keymaps Keymap Configuration
---@brief [[
--- Sets up buffer-local keymaps for notebook interaction.
---@brief ]]

local M = {}

M.action_descriptions = {
    next_cell = "Next cell",
    prev_cell = "Previous cell",
    add_cell_below = "Add cell below",
    add_cell_above = "Add cell above",
    delete_cell = "Delete cell",
    toggle_cell_type = "Toggle code/markdown",
    merge_cell_below = "Merge with cell below",
    merge_cell_above = "Merge with cell above",
    toggle_output = "Toggle output",
    clear_cell_output = "Clear current cell output",
    clear_all_outputs = "Clear all cell outputs",
    select_kernel = "Select Python interpreter",
    restart_kernel = "Restart kernel",
    show_variables = "Show variables",
    inspect_variable = "Inspect variable under cursor",
    execute_cell = "Execute current cell",
    execute_all_cells = "Execute all cells",
    execute_cells_below = "Execute cells below",
    execute_cells_above = "Execute cells above",
    interrupt_kernel = "Interrupt kernel",
    move_up = "Move up",
    move_down = "Move down",
    open_below = "Open line below",
    open_above = "Open line above",
    enter_key = "Enter key in insert mode",
    delete_line = "Delete line",
    backspace = "Backspace",
}

local function setup_action_keymap(buf, action_fn, action_name, keys, modes, opts)
    modes = modes or { "n" }
    opts = opts or {}
    local desc = M.action_descriptions[action_name] or action_name
    for _, key in ipairs(keys) do
        vim.keymap.set(modes, key, function()
            action_fn()
        end, vim.tbl_extend("force", { buffer = buf, silent = true, desc = desc }, opts))
    end
end

--- Setup notebook command keymaps (<leader>j* prefix)
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @param actions table Actions module
--- @param config table Plugin configuration
function M.setup(buf, ns, actions, config)
    setup_action_keymap(buf, function()
        actions.next_cell(buf, ns)
    end, "next_cell", { "]c" }, { "n" })

    setup_action_keymap(buf, function()
        actions.prev_cell(buf, ns)
    end, "prev_cell", { "[c" }, { "n" })

    setup_action_keymap(buf, function()
        actions.add_cell_below(buf, ns)
    end, "add_cell_below", { "<leader>ja" }, { "n" })

    setup_action_keymap(buf, function()
        actions.add_cell_above(buf, ns)
    end, "add_cell_above", { "<leader>jA" }, { "n" })

    setup_action_keymap(buf, function()
        actions.delete_cell(buf, ns)
    end, "delete_cell", { "<leader>jd" }, { "n" })

    setup_action_keymap(buf, function()
        actions.toggle_cell_type(buf, ns)
    end, "toggle_cell_type", { "<leader>jt" }, { "n" })

    setup_action_keymap(buf, function()
        actions.merge_cell_below(buf, ns)
    end, "merge_cell_below", { "<leader>jm" }, { "n" })

    setup_action_keymap(buf, function()
        actions.merge_cell_above(buf, ns)
    end, "merge_cell_above", { "<leader>jM" }, { "n" })

    setup_action_keymap(buf, function()
        actions.toggle_output(buf, ns)
    end, "toggle_output", { "<leader>jo" }, { "n" })

    setup_action_keymap(buf, function()
        actions.clear_cell_output(buf, ns)
    end, "clear_cell_output", { "<leader>jc" }, { "n" })

    setup_action_keymap(buf, function()
        actions.clear_all_outputs(buf, ns)
    end, "clear_all_outputs", { "<leader>jC" }, { "n" })

    setup_action_keymap(buf, function()
        actions.select_kernel(buf, config, ns)
    end, "select_kernel", { "<leader>jk" }, { "n" })

    setup_action_keymap(buf, function()
        actions.restart_kernel(buf)
    end, "restart_kernel", { "<leader>jr" }, { "n" })

    setup_action_keymap(buf, function()
        actions.show_variables(buf)
    end, "show_variables", { "<leader>jv" }, { "n" })

    setup_action_keymap(buf, function()
        actions.inspect_variable(buf)
    end, "inspect_variable", { "<leader>jh" }, { "n" })

    setup_action_keymap(buf, function()
        actions.execute_cell(buf, ns, config.python)
    end, "execute_cell", { "<leader>jx" }, { "n" })

    setup_action_keymap(buf, function()
        actions.execute_all_cells(buf, ns, config.python)
    end, "execute_all_cells", { "<leader>jX" }, { "n" })

    setup_action_keymap(buf, function()
        actions.execute_cells_below(buf, ns, config.python)
    end, "execute_cells_below", { "<leader>jb" }, { "n" })

    setup_action_keymap(buf, function()
        actions.execute_cells_above(buf, ns, config.python)
    end, "execute_cells_above", { "<leader>jB" }, { "n" })

    setup_action_keymap(buf, function()
        actions.interrupt_kernel(buf)
    end, "interrupt_kernel", { "<leader>ji" }, { "n" })
end

--- Setup edit restriction keymaps and cursor constraints
--- Prevents editing separator lines and constrains cursor to content.
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @param actions table Actions module
function M.setup_edit_restrictions(buf, ns, actions)
    setup_action_keymap(buf, function()
        actions.move_up(buf, ns)
    end, "move_up", { "k", "<Up>" }, { "n", "v" })

    setup_action_keymap(buf, function()
        actions.move_down(buf, ns)
    end, "move_down", { "j", "<Down>" }, { "n", "v" })

    setup_action_keymap(buf, function()
        actions.open_below(buf, ns)
    end, "open_below", { "o" }, { "n" })

    setup_action_keymap(buf, function()
        actions.enter_key(buf, ns)
    end, "enter_key", { "<CR>" }, { "i" })

    setup_action_keymap(buf, function()
        actions.open_above(buf, ns)
    end, "open_above", { "O" }, { "n" })

    -- Fix which-key's timeout on `dd`, avoid unexpected deletion behavior
    vim.keymap.set("o", "d", function()
        local op = vim.v.operator
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
        if op == "d" then
            vim.schedule(function()
                actions.delete_line(buf, ns)
            end)
        end
    end, { buffer = buf, silent = true })

    -- Deferred <BS> setup: Wait for InsertEnter to avoid conflicts with nvim-autopairs
    vim.api.nvim_create_autocmd("InsertEnter", {
        buffer = buf,
        once = true,
        callback = function()
            vim.schedule(function()
                pcall(vim.keymap.del, "i", "<BS>", { buffer = buf })
                vim.keymap.set("i", "<BS>", function()
                    return actions.backspace(buf, ns)
                end, { buffer = buf, expr = true, replace_keycodes = false, desc = "Backspace (protected)" })
            end)
        end,
    })

    -- Constrain cursor to content lines (prevent landing on separator lines)
    -- This runs on every CursorMoved/CursorMovedI event
    -- Cases handled:
    -- 1. Cursor outside any cell (e.g., after deletion) -> snap to nearest cell
    -- 2. Cursor on separator line (row == cell.start_row) -> move to first content line
    -- The +2 offset accounts for: separator at start_row, first content at start_row+1,
    -- and 1-indexed cursor API vs 0-indexed row numbers
    local cells = require("notebook.cells")
    local constraining = false
    local function constrain_cursor()
        if constraining then return end
        constraining = true

        local line_count = vim.api.nvim_buf_line_count(buf)
        if line_count == 0 then
            constraining = false
            return
        end

        local cursor = vim.api.nvim_win_get_cursor(0)
        local row = cursor[1] - 1
        local cell = cells.get_current(buf, ns)

        if not cell then
            local all_cells = cells.get_all(buf, ns)
            if #all_cells == 0 then
                constraining = false
                return
            end

            local nearest_cell = nil
            local min_dist = math.huge

            for _, c in ipairs(all_cells) do
                local dist_to_start = math.abs(row - c.start_row)
                local dist_to_end = math.abs(row - c.end_row)
                local dist = math.min(dist_to_start, dist_to_end)

                if dist < min_dist then
                    min_dist = dist
                    nearest_cell = c
                end
            end

            if nearest_cell then
                local target_row
                if row < nearest_cell.start_row then
                    target_row = math.min(nearest_cell.start_row + 2, nearest_cell.end_row + 1, line_count)
                else
                    target_row = math.min(nearest_cell.end_row + 1, line_count)
                end
                vim.api.nvim_win_set_cursor(0, { target_row, 0 })
            end
            constraining = false
            return
        end

        if row == cell.start_row then
            local target_row = math.min(cell.start_row + 2, cell.end_row + 1, line_count)
            vim.api.nvim_win_set_cursor(0, { target_row, 0 })
        end
        constraining = false
    end

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        buffer = buf,
        callback = constrain_cursor,
    })

    -- Operator-pending mode mappings for which-key compatibility
    vim.keymap.set("o", "G", function()
        local op = vim.v.operator
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
        vim.schedule(function()
            if op == "y" then
                actions.yank_in_cell(buf, ns, "end")
            elseif op == "d" then
                actions.delete_in_cell(buf, ns, "end")
            end
        end)
    end, { buffer = buf, silent = true })

    vim.keymap.set("o", "gg", function()
        local op = vim.v.operator
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
        vim.schedule(function()
            if op == "y" then
                actions.yank_in_cell(buf, ns, "start")
            elseif op == "d" then
                actions.delete_in_cell(buf, ns, "start")
            end
        end)
    end, { buffer = buf, silent = true })

    vim.keymap.set("v", "G", function()
        local cell = cells.get_current(buf, ns)
        if not cell then return end
        local last_line = vim.api.nvim_buf_get_lines(buf, cell.end_row, cell.end_row + 1, false)[1] or ""
        local end_col = math.max(#last_line - 1, 0)
        vim.api.nvim_win_set_cursor(0, { cell.end_row + 1, end_col })
    end, { buffer = buf, silent = true })

    vim.keymap.set("v", "gg", function()
        local cell = cells.get_current(buf, ns)
        if not cell then return end
        vim.api.nvim_win_set_cursor(0, { cell.start_row + 2, 0 })
    end, { buffer = buf, silent = true })
end

return M
