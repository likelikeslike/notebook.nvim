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
--- @param ns number Namespace for extmarks
--- @param config table Plugin configuration
function M.load(buf, ns, config)
    local filename = vim.api.nvim_buf_get_name(buf)
    local notebook = ipynb.load(filename)

    if not notebook then
        vim.notify("Failed to load notebook: " .. filename, vim.log.levels.ERROR)
        return
    end

    vim.b[buf].notebook = notebook
    local cell_ranges = render.notebook(buf, notebook, ns)

    vim.bo[buf].modified = false
    vim.bo[buf].buftype = "acwrite"

    local win = vim.api.nvim_get_current_win()
    vim.wo[win].conceallevel = 3
    vim.wo[win].concealcursor = "nvic"

    local ft = notebook.metadata.kernelspec and notebook.metadata.kernelspec.language or "python"
    vim.bo[buf].filetype = ft
    vim.treesitter.start(buf, ft)
    render.setup_markdown_highlight(buf, cell_ranges)
    M.setup_lsp(buf, ns, ft, config)

    keymaps.setup(buf, ns, actions, config)
    keymaps.setup_edit_restrictions(buf, ns, actions, config)

    local refresh_timer = vim.uv.new_timer()
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = buf,
        callback = function()
            refresh_timer:stop()
            refresh_timer:start(
                150,
                0,
                vim.schedule_wrap(function()
                    if vim.api.nvim_buf_is_valid(buf) then cells.refresh_cells(buf, ns) end
                end)
            )
        end,
    })

    if config.yank_highlight then M.setup_yank_highlight(buf, ns) end
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

--- Inject config.python.path into LSP server settings for known servers
--- @param lsp_opts table LSP config passed to vim.lsp.start
--- @param python_path string Python interpreter path
local function inject_python_path(lsp_opts, python_path)
    local name = lsp_opts.name or ""
    if name:match("pyright") then
        lsp_opts.settings = vim.tbl_deep_extend("force", lsp_opts.settings or {}, {
            python = { pythonPath = python_path },
        })
    elseif name == "ruff" then
        lsp_opts.settings = vim.tbl_deep_extend("force", lsp_opts.settings or {}, {
            interpreter = { python_path },
        })
    end
end

--- Setup LSP servers for the buffer based on filetype
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @param ft string Filetype (usually "python")
--- @param config table Plugin configuration
function M.setup_lsp(buf, ns, ft, config)
    local lsp_configs = config.lsp[ft]
    if not lsp_configs then return end

    vim.defer_fn(function()
        for _, lsp_config in ipairs(lsp_configs) do
            local keys = lsp_config.keys
            local lsp_opts = vim.tbl_extend("force", lsp_config, { keys = nil })
            if config.python then inject_python_path(lsp_opts, config.python.path) end
            vim.lsp.start(lsp_opts, { bufnr = buf })

            if keys then
                for _, keymap in ipairs(keys) do
                    local mode = keymap.mode or "n"
                    local lhs = keymap[1]
                    local rhs = keymap[2]
                    local opts = { buffer = buf, desc = keymap.desc }
                    vim.keymap.set(mode, lhs, rhs, opts)
                end
            end
        end
        vim.diagnostic.enable(true, { bufnr = buf })
        vim.schedule(function()
            if config.diagnostics then vim.diagnostic.config(config.diagnostics) end
        end)

        M.setup_diagnostic_filter(buf, ns)
    end, 50)
end

--- Restart LSP servers for the buffer with current config
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @param config table Plugin configuration
function M.restart_lsp(buf, ns, config)
    local clients = vim.lsp.get_clients({ bufnr = buf })
    for _, client in ipairs(clients) do
        client:stop()
    end

    local notebook = vim.b[buf].notebook
    local ft = notebook.metadata.kernelspec and notebook.metadata.kernelspec.language or "python"

    vim.defer_fn(function()
        M.setup_lsp(buf, ns, ft, config)
    end, 200)
end

local diagnostic_handlers_wrapped = false

--- Install global diagnostic handler wrappers that filter markdown cell diagnostics
--- Wraps built-in handlers once. Each handler checks if the buffer
--- is a notebook buffer and filters diagnostics before rendering
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.setup_diagnostic_filter(buf, ns)
    vim.b[buf].notebook_diag_ns = ns

    if diagnostic_handlers_wrapped then return end
    diagnostic_handlers_wrapped = true

    local handler_names = { "virtual_text", "signs", "underline" }

    for _, name in ipairs(handler_names) do
        local orig = vim.diagnostic.handlers[name]
        if not orig then goto continue end

        vim.diagnostic.handlers[name] = {
            show = function(namespace, bufnr, diagnostics, opts)
                local diag_ns = vim.b[bufnr] and vim.b[bufnr].notebook_diag_ns
                if diag_ns then diagnostics = cells.filter_markdown_diagnostics(diagnostics, bufnr, diag_ns) end
                orig.show(namespace, bufnr, diagnostics, opts)
            end,
            hide = orig.hide,
        }

        ::continue::
    end
end

--- Setup yank highlighting that respects cell background colors
--- Temporarily removes bg extmarks during highlight, then restores them
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.setup_yank_highlight(buf, ns)
    local bg_ns = vim.api.nvim_create_namespace("jupyter_notebook_bg")

    vim.api.nvim_create_autocmd("TextYankPost", {
        buffer = buf,
        callback = function()
            local start_row = vim.api.nvim_buf_get_mark(buf, "[")[1] - 1
            local end_row = vim.api.nvim_buf_get_mark(buf, "]")[1] - 1

            for row = start_row, end_row do
                local extmarks = vim.api.nvim_buf_get_extmarks(buf, bg_ns, { row, 0 }, { row, -1 }, {})
                for _, mark in ipairs(extmarks) do
                    vim.api.nvim_buf_del_extmark(buf, bg_ns, mark[1])
                end
            end

            vim.hl.on_yank({ timeout = 150 })

            local all_cells = cells.get_all(buf, ns)
            vim.defer_fn(function()
                if not vim.api.nvim_buf_is_valid(buf) then return end
                for _, cell in ipairs(all_cells) do
                    local bg_hl = cell.cell_type == "markdown" and "JupyterNotebookCellBgMarkdown"
                        or "JupyterNotebookCellBg"
                    for line_row = math.max(cell.start_row, start_row), math.min(cell.end_row, end_row) do
                        vim.api.nvim_buf_set_extmark(buf, bg_ns, line_row, 0, {
                            line_hl_group = bg_hl,
                            priority = 1,
                        })
                    end
                end
            end, 160)
        end,
    })
end

return M
