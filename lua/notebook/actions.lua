---@mod notebook.actions User Action Handlers
---@brief [[
--- Handles all user-facing actions for notebook interaction.
---@brief ]]

local cells = require("notebook.cells")
local kernel = require("notebook.kernel")
local output = require("notebook.output")

local M = {}

local function is_separator(buf, row)
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    return line:match("^# %%") ~= nil
end

--- Move cursor up, respecting cell boundaries (skips separator lines)
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.move_up(buf, ns)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1

    local current_cell, idx = cells.get_current(buf, ns)
    if not current_cell then return end

    if row <= current_cell.start_row + 1 then
        if not idx or idx <= 1 then return end
        local all_cells = cells.get_all(buf, ns)
        local prev_cell = all_cells[idx - 1]
        vim.api.nvim_win_set_cursor(0, { prev_cell.end_row + 1, cursor[2] })
        return
    end

    local prev_row = row - 1
    if is_separator(buf, prev_row) then
        return
    else
        vim.api.nvim_win_set_cursor(0, { prev_row + 1, cursor[2] })
    end
end

--- Move cursor down, respecting cell boundaries (skips separator lines)
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.move_down(buf, ns)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1

    local current_cell = cells.get_current(buf, ns)
    if not current_cell then return end

    if row >= current_cell.end_row then
        cells.goto_next(buf, ns)
        return
    end

    local next_row = row + 1
    if is_separator(buf, next_row) then
        cells.goto_next(buf, ns)
    else
        vim.api.nvim_win_set_cursor(0, { next_row + 1, cursor[2] })
    end
end

--- Open line below cursor (like 'o' in vim), staying within cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.open_below(buf, ns)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local cell = cells.get_current(buf, ns)

    if not cell then return end

    vim.api.nvim_buf_set_lines(buf, row + 1, row + 1, false, { "" })
    cells.refresh_cells(buf, ns)
    local target_row = row + 2
    vim.schedule(function()
        vim.api.nvim_win_set_cursor(0, { target_row, 0 })
        vim.cmd("startinsert")
    end)
end

--- Open line above cursor (like 'O' in vim), staying within cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.open_above(buf, ns)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local cell = cells.get_current(buf, ns)

    if not cell then return end

    local target_row
    if row == cell.start_row then
        vim.api.nvim_buf_set_lines(buf, row + 1, row + 1, false, { "" })
        cells.refresh_cells(buf, ns)
        target_row = row + 2
    else
        vim.api.nvim_buf_set_lines(buf, row, row, false, { "" })
        cells.refresh_cells(buf, ns)
        target_row = row + 1
    end
    vim.schedule(function()
        vim.api.nvim_win_set_cursor(0, { target_row, 0 })
        vim.cmd("startinsert")
    end)
end

--- Handle Enter key in insert mode, creating new line within cell
--- At last line: splits line and moves cursor (extends cell)
--- Otherwise: passes through to default <CR> behavior
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.enter_key(buf, ns)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local col = cursor[2]
    local cell = cells.get_current(buf, ns)

    if not cell then
        local keys = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
        vim.api.nvim_feedkeys(keys, "n", false)
        return
    end

    local at_last_line = row == cell.end_row

    if at_last_line then
        -- Default <CR> would create line outside cell boundary
        local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
        local before = line:sub(1, col)
        local after = line:sub(col + 1)
        vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { before, after })
        cells.refresh_cells(buf, ns)
        vim.schedule(function()
            vim.api.nvim_win_set_cursor(0, { row + 2, 0 })
        end)
    else
        -- Not at last line: use default <CR> behavior
        local keys = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
        vim.api.nvim_feedkeys(keys, "n", false)
    end
end

--- Delete current line (like 'dd'), with cell protection
--- Prevents deleting separator lines and last line of cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.delete_line(buf, ns)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""

    if line:match("^# %%") then
        vim.notify("Cannot delete cell separator. Use :JupyterDeleteCell to delete cell.", vim.log.levels.WARN)
        return
    end

    local cell = cells.get_current(buf, ns)
    if not cell then return end

    local is_only_content_line = (cell.end_row <= cell.start_row + 1)
    local is_at_cell_end = (row == cell.end_row)

    if is_only_content_line then
        vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { "" })
        vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
    else
        vim.api.nvim_buf_set_lines(buf, row, row + 1, false, {})
        if is_at_cell_end then vim.api.nvim_win_set_cursor(0, { row, 0 }) end
    end
    cells.refresh_cells(buf, ns)
end

--- Handle Backspace key (expr mapping), respecting cell boundaries
--- Returns keycode for <BS> behavior (used with expr=true mapping)
--- At cell boundary: returns "" to block deletion of separator
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @return string Keycode to execute
function M.backspace(buf, ns)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local col = cursor[2]

    local cell = cells.get_current(buf, ns)
    if cell and row == (cell.start_row + 1) and col == 0 then return "" end

    -- Handle nvim-autopairs integration if available, to properly trigger autopairs on backspace
    local ok, autopairs = pcall(require, "nvim-autopairs")
    if ok then return autopairs.autopairs_bs() end

    return vim.api.nvim_replace_termcodes("<BS>", true, false, true)
end

--- Delete from cursor to end (dG) / start (dgg) inside cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @param to string "start" or "end" indicating the direction of deletion
--- @param reg string|nil Register to store deleted text (defaults to vim.v.register or unnamed)
function M.delete_in_cell(buf, ns, to, reg)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1

    local cell = cells.get_current(buf, ns)
    if not cell then return end

    if row <= cell.start_row then return end

    local start_row, end_row
    if to == "end" then
        start_row = row -- 1
        end_row = cell.end_row + 1 -- 2
    elseif to == "start" then
        start_row = cell.start_row + 1
        end_row = row + 1
    else
        return
    end

    local deleted = vim.api.nvim_buf_get_lines(buf, start_row, end_row, false)
    reg = reg ~= nil and reg ~= "" and reg or (vim.v.register ~= "" and vim.v.register or '"')
    vim.fn.setreg(reg, table.concat(deleted, "\n"), "l")

    if end_row - start_row == 1 then
        -- Only one line, same as delete_line behavior
        vim.api.nvim_buf_set_lines(buf, start_row, end_row, false, { "" })
        vim.api.nvim_win_set_cursor(0, { start_row + 1, 0 })
    else
        vim.api.nvim_buf_set_lines(buf, start_row, end_row, false, {})
        vim.api.nvim_win_set_cursor(0, { start_row, 0 })
    end

    cells.refresh_cells(buf, ns)
end

--- Yank from cursor to end (yG) / start (ygg) inside cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @param to string "start" or "end" indicating the direction of yanking
--- @param reg string|nil Register to yank into (defaults to vim.v.register or unnamed)
function M.yank_in_cell(buf, ns, to, reg)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1

    local cell = cells.get_current(buf, ns)
    if not cell then return end

    if row <= cell.start_row then return end

    local start_row, end_row
    if to == "end" then
        start_row = row
        end_row = cell.end_row + 1
    elseif to == "start" then
        start_row = cell.start_row + 1
        end_row = row + 1
    else
        return
    end

    local yanked = vim.api.nvim_buf_get_lines(buf, start_row, end_row, false)
    reg = reg ~= nil and reg ~= "" and reg or (vim.v.register ~= "" and vim.v.register or '"')
    vim.fn.setreg(reg, table.concat(yanked, "\n"), "l")

    local bg_ns = vim.api.nvim_create_namespace("jupyter_notebook_bg")
    local saved_marks = {}
    for r = start_row, end_row - 1 do
        local extmarks = vim.api.nvim_buf_get_extmarks(buf, bg_ns, { r, 0 }, { r, -1 }, {})
        for _, mark in ipairs(extmarks) do
            table.insert(saved_marks, mark)
            vim.api.nvim_buf_del_extmark(buf, bg_ns, mark[1])
        end
    end

    -- Fix for yank highlighting
    local yank_ns = vim.api.nvim_create_namespace("notebook_yank_highlight")
    for i, line in ipairs(yanked) do
        local r = start_row + i - 1
        if #line > 0 then
            vim.api.nvim_buf_set_extmark(buf, yank_ns, r, 0, {
                end_col = #line,
                hl_group = "IncSearch",
            })
        end
    end

    vim.defer_fn(function()
        vim.api.nvim_buf_clear_namespace(buf, yank_ns, 0, -1)
        local bg_hl = cell.cell_type == "markdown" and "JupyterNotebookCellBgMarkdown" or "JupyterNotebookCellBg"
        for r = start_row, end_row - 1 do
            vim.api.nvim_buf_set_extmark(buf, bg_ns, r, 0, {
                line_hl_group = bg_hl,
                priority = 1,
            })
        end
    end, 150)

    vim.notify(#yanked .. " line(s) yanked", vim.log.levels.INFO)
end

--- Navigate to next cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.next_cell(buf, ns)
    cells.goto_next(buf, ns)
end

--- Navigate to previous cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.prev_cell(buf, ns)
    cells.goto_prev(buf, ns)
end

--- Add new code cell below current
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.add_cell_below(buf, ns)
    cells.add_below(buf, ns)
end

--- Add new code cell above current
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.add_cell_above(buf, ns)
    cells.add_above(buf, ns)
end

--- Delete current cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.delete_cell(buf, ns)
    cells.delete_current(buf, ns)
end

--- Toggle cell type between code and markdown
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.toggle_cell_type(buf, ns)
    cells.toggle_type(buf, ns)
end

--- Merge current cell with cell below
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.merge_cell_below(buf, ns)
    cells.merge_below(buf, ns)
end

--- Merge current cell with cell above
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.merge_cell_above(buf, ns)
    cells.merge_above(buf, ns)
end

--- Toggle floating output window for current cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.toggle_output(buf, ns)
    output.toggle(buf, ns)
end

--- Clear output for current cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.clear_cell_output(buf, ns)
    output.clear_cell(buf, ns)
end

--- Clear all cell outputs in buffer
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.clear_all_outputs(buf, ns)
    output.clear_all(buf)
end

local function check_jupyter_installed(python_path, callback)
    vim.fn.jobstart({ python_path, "-c", "import jupyter_client" }, {
        on_exit = function(_, exit_code)
            vim.schedule(function()
                callback(exit_code == 0)
            end)
        end,
    })
end

-- Install jupyter_client and ipykernel for the selected Python interpreter
local function install_jupyter(python, callback)
    local install_cmd
    if python.env_type == "uv" and vim.fn.executable("uv") == 1 then
        install_cmd = { "uv", "pip", "install", "--python", python.path, "jupyter_client", "ipykernel" }
    else
        install_cmd = { python.path, "-m", "pip", "install", "jupyter_client", "ipykernel" }
    end

    vim.notify("Installing jupyter_client and ipykernel...", vim.log.levels.INFO)

    local stderr_lines = {}
    vim.fn.jobstart(install_cmd, {
        on_exit = function(_, exit_code)
            vim.schedule(function()
                if exit_code == 0 then
                    vim.notify("Jupyter dependencies installed successfully", vim.log.levels.INFO)
                    callback(true)
                else
                    local msg = "Failed to install Jupyter dependencies"
                    if #stderr_lines > 0 then msg = msg .. "\n" .. table.concat(stderr_lines, "\n") end
                    vim.notify(msg, vim.log.levels.ERROR)
                    callback(false)
                end
            end)
        end,
        on_stderr = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" and not line:match("^%s*$") then table.insert(stderr_lines, line) end
                end
            end
        end,
    })
end

--- Open Python interpreter picker and set as kernel
--- Checks for jupyter_client, offers to install if missing
--- @param buf number Buffer handle
--- @param config table Plugin configuration
--- @param ns number Namespace for extmarks
function M.select_kernel(buf, config, ns)
    local python = require("notebook.python")

    python.pick_python(function(selected_python)
        if not selected_python then return end

        local function setup_kernel()
            config.python = selected_python

            local notebook = vim.b[buf].notebook
            if notebook then
                notebook.metadata.kernelspec = {
                    name = "python3",
                    display_name = "Python 3 (" .. selected_python.path .. ")",
                    language = "python",
                }
                vim.b[buf].notebook = notebook
            end

            kernel.disconnect(buf)
            kernel.connect(buf, selected_python)

            require("notebook.notebook").restart_lsp(buf, ns, config)

            vim.notify("Kernel set to: " .. selected_python.path, vim.log.levels.INFO)
        end

        check_jupyter_installed(selected_python.path, function(installed)
            if installed then
                setup_kernel()
            else
                vim.ui.select({ "Yes", "No" }, {
                    prompt = "jupyter_client not found. Install jupyter_client and ipykernel?",
                }, function(choice)
                    if choice == "Yes" then
                        install_jupyter(selected_python, function(success)
                            if success then setup_kernel() end
                        end)
                    end
                end)
            end
        end)
    end)
end

--- Restart the kernel (clears all state)
--- @param buf number Buffer handle
function M.restart_kernel(buf)
    kernel.restart(buf, function(success)
        if success then
            vim.notify("Kernel restarted", vim.log.levels.INFO)
        else
            vim.notify("Failed to restart kernel", vim.log.levels.ERROR)
        end
    end)
end

--- Show all kernel variables in floating window
--- @param buf number Buffer handle
function M.show_variables(buf)
    if not kernel.is_connected(buf) then
        vim.notify("Kernel not connected", vim.log.levels.WARN)
        return
    end

    kernel.get_variables(buf, function(variables)
        output.show_variables(variables)
    end)
end

--- Inspect variable under cursor (show type/value in hover)
--- @param buf number Buffer handle
function M.inspect_variable(buf)
    if not kernel.is_connected(buf) then
        vim.notify("Kernel not connected", vim.log.levels.WARN)
        return
    end

    local word = vim.fn.expand("<cword>")
    if word == "" then return end
    if not word:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then return end

    kernel.inspect(buf, word, function(info)
        output.show_hover(info)
    end)
end

--- Execute current cell via kernel
--- Auto-connects to kernel if not connected. Displays streaming output
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @param python table? Python interpreter info (path and env_type)
function M.execute_cell(buf, ns, python)
    local cell_info = cells.get_current(buf, ns)
    if not cell_info then
        vim.notify("No cell found at cursor", vim.log.levels.WARN)
        return
    end

    if cell_info.cell_type ~= "code" then
        vim.notify("Cannot execute markdown cell", vim.log.levels.WARN)
        return
    end

    local start_time = vim.uv.hrtime()

    local function on_done(result, was_interrupted, execution_count)
        local elapsed = (vim.uv.hrtime() - start_time) / 1e9
        output.display(buf, cell_info, result, ns, elapsed, was_interrupted, execution_count)
    end

    local function on_output(result)
        local elapsed = (vim.uv.hrtime() - start_time) / 1e9
        output.display(buf, cell_info, result, ns, elapsed)
    end

    local function on_execute_count(count)
        output.update_cell_label(buf, ns, cell_info.cell_id, count)
    end

    if not kernel.is_connected(buf) then
        kernel.connect(buf, python, function()
            kernel.execute(buf, cell_info, on_done, on_output, on_execute_count)
        end)
    else
        kernel.execute(buf, cell_info, on_done, on_output, on_execute_count)
    end
end

--- Execute a filtered range of code cells sequentially
--- Collects code cells matching filter_fn, executes them in order,
--- stops on interrupt, and shows done_msg when complete
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @param python table? Python interpreter info (path and env_type)
--- @param filter_fn function(cell): boolean Predicate to select which cells to execute
--- @param done_msg string Message shown after all cells finish
local function execute_cell_range(buf, ns, python, filter_fn, done_msg)
    local all_cells = cells.get_all(buf, ns)
    local code_cells = {}

    for _, cell in ipairs(all_cells) do
        if cell.cell_type == "code" and filter_fn(cell) then
            local lines = vim.api.nvim_buf_get_lines(buf, cell.start_row + 1, cell.end_row + 1, false)
            cell.source = table.concat(lines, "\n")
            table.insert(code_cells, cell)
        end
    end

    if #code_cells == 0 then
        vim.notify("No code cells to execute", vim.log.levels.WARN)
        return
    end

    local function execute_next(index)
        if index > #code_cells then
            vim.notify(done_msg, vim.log.levels.INFO)
            return
        end

        local cell_info = code_cells[index]
        local start_time = vim.uv.hrtime()

        local function on_done(result, was_interrupted, execution_count)
            local elapsed = (vim.uv.hrtime() - start_time) / 1e9
            output.display(buf, cell_info, result, ns, elapsed, was_interrupted, execution_count)
            if not was_interrupted then execute_next(index + 1) end
        end

        local function on_output(result)
            local elapsed = (vim.uv.hrtime() - start_time) / 1e9
            output.display(buf, cell_info, result, ns, elapsed)
        end

        local function on_execute_count(count)
            output.update_cell_label(buf, ns, cell_info.cell_id, count)
        end

        kernel.execute(buf, cell_info, on_done, on_output, on_execute_count)
    end

    if not kernel.is_connected(buf) then
        kernel.connect(buf, python, function()
            execute_next(1)
        end)
    else
        execute_next(1)
    end
end

--- Execute all code cells sequentially
--- Stops on interrupt. Auto-connects to kernel if needed
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @param python table? Python interpreter info (path and env_type)
function M.execute_all_cells(buf, ns, python)
    execute_cell_range(buf, ns, python, function()
        return true
    end, "All cells executed")
end

--- Execute code cells from current cell to the end
--- Stops on interrupt. Auto-connects to kernel if needed
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @param python table? Python interpreter info (path and env_type)
function M.execute_cells_below(buf, ns, python)
    local current = cells.get_current(buf, ns)
    if not current then
        vim.notify("No cell found at cursor", vim.log.levels.WARN)
        return
    end

    execute_cell_range(buf, ns, python, function(cell)
        return cell.start_row >= current.start_row
    end, "Cells below executed")
end

--- Execute code cells from beginning to current cell (inclusive)
--- Stops on interrupt. Auto-connects to kernel if needed
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @param python table? Python interpreter info (path and env_type)
function M.execute_cells_above(buf, ns, python)
    local current = cells.get_current(buf, ns)
    if not current then
        vim.notify("No cell found at cursor", vim.log.levels.WARN)
        return
    end

    execute_cell_range(buf, ns, python, function(cell)
        return cell.start_row <= current.start_row
    end, "Cells above executed")
end

--- Interrupt running kernel execution
--- @param buf number Buffer handle
function M.interrupt_kernel(buf)
    kernel.interrupt(buf)
end

--- Register all :Jupyter* user commands
--- Commands registered:
--- - :JupyterNextCell - Go to next cell
--- - :JupyterPrevCell - Go to previous cell
--- - :JupyterAddCellBelow - Add cell below
--- - :JupyterAddCellAbove - Add cell above
--- - :JupyterDeleteCell - Delete current cell
--- - :JupyterToggleCellType - Toggle code/markdown
--- - :JupyterMergeCellBelow - Merge with cell below
--- - :JupyterMergeCellAbove - Merge with cell above
--- - :JupyterToggleOutput - Toggle cell output
--- - :JupyterClearOutput - Clear current cell output
--- - :JupyterClearAllOutputs - Clear all cell outputs
--- - :JupyterSelectKernel - Select Python interpreter
--- - :JupyterRestart - Restart kernel
--- - :JupyterVariables - Show variables
--- - :JupyterInspect - Inspect variable under cursor
--- - :JupyterExecuteCell - Execute current cell
--- - :JupyterExecuteAll - Execute all cells
--- - :JupyterExecuteBelow - Execute from current cell to end
--- - :JupyterExecuteAbove - Execute from start to current cell
--- - :JupyterInterrupt - Interrupt kernel
--- @param notebook table Main notebook module with config and ns
function M.setup_commands(notebook)
    local ns = notebook.ns
    local config = notebook.config

    vim.api.nvim_create_user_command("JupyterNextCell", function()
        M.next_cell(vim.api.nvim_get_current_buf(), ns)
    end, { desc = "Go to next Jupyter cell" })

    vim.api.nvim_create_user_command("JupyterPrevCell", function()
        M.prev_cell(vim.api.nvim_get_current_buf(), ns)
    end, { desc = "Go to previous Jupyter cell" })

    vim.api.nvim_create_user_command("JupyterAddCellBelow", function()
        M.add_cell_below(vim.api.nvim_get_current_buf(), ns)
    end, { desc = "Add Jupyter cell below" })

    vim.api.nvim_create_user_command("JupyterAddCellAbove", function()
        M.add_cell_above(vim.api.nvim_get_current_buf(), ns)
    end, { desc = "Add Jupyter cell above" })

    vim.api.nvim_create_user_command("JupyterDeleteCell", function()
        M.delete_cell(vim.api.nvim_get_current_buf(), ns)
    end, { desc = "Delete current Jupyter cell" })

    vim.api.nvim_create_user_command("JupyterToggleCellType", function()
        M.toggle_cell_type(vim.api.nvim_get_current_buf(), ns)
    end, { desc = "Toggle code/markdown" })

    vim.api.nvim_create_user_command("JupyterMergeCellBelow", function()
        M.merge_cell_below(vim.api.nvim_get_current_buf(), ns)
    end, { desc = "Merge with cell below" })

    vim.api.nvim_create_user_command("JupyterMergeCellAbove", function()
        M.merge_cell_above(vim.api.nvim_get_current_buf(), ns)
    end, { desc = "Merge with cell above" })

    vim.api.nvim_create_user_command("JupyterToggleOutput", function()
        M.toggle_output(vim.api.nvim_get_current_buf(), ns)
    end, { desc = "Toggle current cell output" })

    vim.api.nvim_create_user_command("JupyterClearOutput", function()
        M.clear_cell_output(vim.api.nvim_get_current_buf(), ns)
    end, { desc = "Clear current cell output" })

    vim.api.nvim_create_user_command("JupyterClearAllOutputs", function()
        M.clear_all_outputs(vim.api.nvim_get_current_buf(), ns)
    end, { desc = "Clear all cell outputs" })

    vim.api.nvim_create_user_command("JupyterSelectKernel", function()
        M.select_kernel(vim.api.nvim_get_current_buf(), config, ns)
    end, { desc = "Select Python interpreter" })

    vim.api.nvim_create_user_command("JupyterRestart", function()
        M.restart_kernel(vim.api.nvim_get_current_buf())
    end, { desc = "Restart kernel" })

    vim.api.nvim_create_user_command("JupyterVariables", function()
        M.show_variables(vim.api.nvim_get_current_buf())
    end, { desc = "Show variables" })

    vim.api.nvim_create_user_command("JupyterInspect", function()
        M.inspect_variable(vim.api.nvim_get_current_buf())
    end, { desc = "Inspect variable under cursor" })

    vim.api.nvim_create_user_command("JupyterExecuteCell", function()
        M.execute_cell(vim.api.nvim_get_current_buf(), ns, config.python)
    end, { desc = "Execute current cell" })

    vim.api.nvim_create_user_command("JupyterExecuteAll", function()
        M.execute_all_cells(vim.api.nvim_get_current_buf(), ns, config.python)
    end, { desc = "Execute all cells" })

    vim.api.nvim_create_user_command("JupyterExecuteBelow", function()
        M.execute_cells_below(vim.api.nvim_get_current_buf(), ns, config.python)
    end, { desc = "Execute from current cell to end" })

    vim.api.nvim_create_user_command("JupyterExecuteAbove", function()
        M.execute_cells_above(vim.api.nvim_get_current_buf(), ns, config.python)
    end, { desc = "Execute from start to current cell" })

    vim.api.nvim_create_user_command("JupyterInterrupt", function()
        M.interrupt_kernel(vim.api.nvim_get_current_buf())
    end, { desc = "Interrupt kernel" })
end

return M
