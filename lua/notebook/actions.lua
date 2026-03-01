---@mod notebook.actions User Action Handlers
---@brief [[
--- Handles all user-facing actions for notebook interaction.
---@brief ]]

local cells = require("notebook.cells")
local kernel = require("notebook.kernel")
local output = require("notebook.output")

local M = {}

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

    vim.fn.jobstart(install_cmd, {
        on_exit = function(_, exit_code)
            vim.schedule(function()
                if exit_code == 0 then
                    vim.notify("Jupyter dependencies installed successfully", vim.log.levels.INFO)
                    callback(true)
                else
                    vim.notify("Failed to install Jupyter dependencies", vim.log.levels.ERROR)
                    callback(false)
                end
            end)
        end,
        on_stderr = function(_, data)
            if data and #data > 0 and data[1] ~= "" then
                vim.schedule(function()
                    for _, line in ipairs(data) do
                        if line ~= "" and not line:match("^%s*$") then vim.notify(line, vim.log.levels.WARN) end
                    end
                end)
            end
        end,
    })
end

--- Open Python interpreter picker and set as kernel
--- Checks for jupyter_client, offers to install if missing
--- @param buf number Buffer handle
function M.select_kernel(buf)
    local python = require("notebook.python")

    python.pick_python(function(python)
        if not python then return end

        local function setup_kernel()
            local notebook = vim.b[buf].notebook
            if notebook then
                notebook.metadata.kernelspec = {
                    name = "python3",
                    display_name = "Python 3 (" .. python.path .. ")",
                    language = "python",
                }
                vim.b[buf].notebook = notebook
            end

            kernel.disconnect(buf)
            kernel.connect(buf, python)

            vim.notify("Kernel set to: " .. python.path, vim.log.levels.INFO)
        end

        check_jupyter_installed(python.path, function(installed)
            if installed then
                setup_kernel()
            else
                vim.ui.select({ "Yes", "No" }, {
                    prompt = "jupyter_client not found. Install jupyter_client and ipykernel?",
                }, function(choice)
                    if choice == "Yes" then
                        install_jupyter(python, function(success)
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

return M
