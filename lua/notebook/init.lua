local M = {}

local notebook = require("notebook.notebook")

local function setup_highlights()
    vim.api.nvim_set_hl(0, "JupyterNotebookCellBg", { link = "CursorLine" })
    vim.api.nvim_set_hl(0, "JupyterNotebookCellBgMarkdown", { link = "ColorColumn" })
    vim.api.nvim_set_hl(0, "JupyterNotebookCellLabel", { link = "Comment" })
    vim.api.nvim_set_hl(0, "JupyterNotebookCellLabelMarkdown", { link = "Special" })
    vim.api.nvim_set_hl(0, "JupyterNotebookOutputBorder", { link = "FloatBorder" })
    vim.api.nvim_set_hl(0, "JupyterNotebookOutput", { link = "Normal" })
    vim.api.nvim_set_hl(0, "JupyterNotebookOutputResult", { link = "String" })
    vim.api.nvim_set_hl(0, "JupyterNotebookOutputError", { link = "DiagnosticError" })
end

function M.setup(opts)
    M.ns = vim.api.nvim_create_namespace("jupyter_notebook")

    setup_highlights()

    local group = vim.api.nvim_create_augroup("JupyterNotebook", { clear = true })

    vim.api.nvim_create_autocmd({ "BufReadCmd" }, {
        group = group,
        pattern = "*.ipynb",
        callback = function(args)
            notebook.load(args.buf, M.ns)
        end,
    })

    vim.api.nvim_create_autocmd({ "BufWriteCmd" }, {
        group = group,
        pattern = "*.ipynb",
        callback = function(args)
            notebook.save(args.buf)
        end,
    })

    vim.api.nvim_create_autocmd({ "BufUnload" }, {
        group = group,
        pattern = "*.ipynb",
        callback = function(args)
            require("notebook.image").clear_buffer(args.buf)
        end,
    })
end

return M
