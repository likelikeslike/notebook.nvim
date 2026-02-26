local M = {}

local notebook = require("notebook.notebook")

function M.setup(opts)
    M.ns = vim.api.nvim_create_namespace("jupyter_notebook")

    local group = vim.api.nvim_create_augroup("JupyterNotebook", { clear = true })

    vim.api.nvim_create_autocmd({ "BufReadCmd" }, {
        group = group,
        pattern = "*.ipynb",
        callback = function(args)
            notebook.load(args.buf)
        end,
    })

    vim.api.nvim_create_autocmd({ "BufWriteCmd" }, {
        group = group,
        pattern = "*.ipynb",
        callback = function(args)
            notebook.save(args.buf)
        end,
    })
end

return M