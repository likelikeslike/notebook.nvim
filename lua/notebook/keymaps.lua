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
function M.setup(buf, ns, actions)
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
end

return M
