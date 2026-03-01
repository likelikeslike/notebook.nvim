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
    toggle_cell_type = "Toggle cell type",
    merge_cell_below = "Merge with cell below",
    merge_cell_above = "Merge with cell above",
    toggle_output = "Toggle output",
    clear_cell_output = "Clear cell output",
    clear_all_outputs = "Clear all outputs",
    select_kernel = "Select Python interpreter",
    restart_kernel = "Restart kernel",
    show_variables = "Show variables",
    inspect_variable = "Inspect variable",
    execute_cell = "Execute cell",
    execute_all_cells = "Execute all cells",
    execute_cells_below = "Execute cells below",
    execute_cells_above = "Execute cells above",
    interrupt_kernel = "Interrupt kernel",
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
        actions.select_kernel(buf, config)
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

return M
