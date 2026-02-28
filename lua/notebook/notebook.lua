---@mod notebook.notebook Buffer Loading and Saving
---@brief [[
--- Handles loading .ipynb files into buffers and saving them back.
---@brief ]]

local M = {}

local actions = require("notebook.actions")
local cells = require("notebook.cells")
local ipynb = require("notebook.ipynb")
local keymaps = require("notebook.keymaps")
local render = require("notebook.render")

--- Load an .ipynb file into a buffer
--- @param buf number Buffer handle
function M.load(buf, ns)
    local filename = vim.api.nvim_buf_get_name(buf)
    local notebook = ipynb.load(filename)

    if not notebook then
        vim.notify("Failed to load notebook: " .. filename, vim.log.levels.ERROR)
        return
    end

    vim.b[buf].notebook = notebook
    render.notebook(buf, notebook, ns)

    vim.bo[buf].modified = false
    vim.bo[buf].buftype = "acwrite"

    local win = vim.api.nvim_get_current_win()
    vim.wo[win].conceallevel = 3
    vim.wo[win].concealcursor = "nvic"

    local ft = notebook.metadata.kernelspec and notebook.metadata.kernelspec.language or "python"
    vim.bo[buf].filetype = ft

    keymaps.setup(buf, ns, actions)

    local refresh_timer = vim.uv.new_timer()
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = buf,
        callback = function()
            refresh_timer:stop()
            refresh_timer:start(150, 0, vim.schedule_wrap(function()
                if vim.api.nvim_buf_is_valid(buf) then
                    cells.refresh_cells(buf, ns)
                end
            end))
        end,
    })
end

--- Save buffer contents back to .ipynb file
--- Called by BufWriteCmd autocmd. Reads buffer text, updates notebook cells, serializes to JSON.
--- @param buf number Buffer handle
function M.save(buf)
    local notebook = vim.b[buf].notebook
    if not notebook then
        vim.notify("No notebook data found", vim.log.levels.ERROR)
        return
    end

    local ns = vim.api.nvim_create_namespace("jupyter_notebook")
    notebook = cells.update_from_buffer(buf, notebook, ns)

    local filename = vim.api.nvim_buf_get_name(buf)
    local success = ipynb.save(filename, notebook)

    if success then
        vim.b[buf].notebook = notebook
        vim.bo[buf].modified = false
        vim.notify("Saved: " .. vim.fn.fnamemodify(filename, ":t"), vim.log.levels.INFO)
    else
        vim.notify("Failed to save notebook", vim.log.levels.ERROR)
    end
end

return M
