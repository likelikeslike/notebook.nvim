---@mod notebook.nvim Jupyter Notebook Integration for Neovim
---@brief [[
--- notebook.nvim provides native editing of Jupyter notebooks (.ipynb files) in Neovim.
---
--- Data Flow:
--- 1. BufReadCmd: ipynb JSON → notebook.load() → text buffer with # %% separators
--- 2. Execution: buffer text → kernel.execute() → streaming output → output.display()
--- 3. BufWriteCmd: buffer text → cells.update_from_buffer() → ipynb JSON → file
---@brief ]]

local M = {}

--- @class NotebookConfig
--- @field python table|nil Override Python interpreter, normally handled by select_kernel action or :JupyterSelectKernel
--- @field keys table Custom keymaps
--- @field lsp table LSP server configurations per filetype, normally for "python" only
--- @field diagnostics table|nil vim.diagnostic.config() options
--- @field yank_highlight boolean Highlight yanked text (default: true)
--- @field highlights table|nil Custom highlight group definitions
--- @field max_output_lines number Max virtual text lines for output (default: 20)

--- Default configuration options
--- @type NotebookConfig
M.config = {
    python = nil,
    lsp = {},
    diagnostics = nil,
    yank_highlight = true,
    keys = {},
    highlights = nil,
    max_output_lines = 20,
}

local notebook = require("notebook.notebook")

--- Initialize highlight groups for notebook UI elements
--- @param hl table User-provided highlight overrides
local function setup_highlights(hl)
    vim.api.nvim_set_hl(0, "JupyterNotebookCellBg", hl.cell_bg or { link = "CursorLine" })
    vim.api.nvim_set_hl(0, "JupyterNotebookCellBgMarkdown", hl.cell_bg_markdown or { link = "ColorColumn" })
    vim.api.nvim_set_hl(0, "JupyterNotebookCellLabel", hl.cell_label or { link = "Comment" })
    vim.api.nvim_set_hl(0, "JupyterNotebookCellLabelMarkdown", hl.cell_label_markdown or { link = "Special" })
    vim.api.nvim_set_hl(0, "JupyterNotebookOutputBorder", hl.output_border or { link = "FloatBorder" })
    vim.api.nvim_set_hl(0, "JupyterNotebookOutput", hl.output or { link = "Normal" })
    vim.api.nvim_set_hl(0, "JupyterNotebookOutputResult", hl.output_result or { link = "String" })
    vim.api.nvim_set_hl(0, "JupyterNotebookOutputError", hl.output_error or { link = "DiagnosticError" })
end

--- Initialize the plugin with user configuration
--- Sets up autocmds for .ipynb file handling:
--- - BufReadCmd: Parse JSON and render as text with cell separators
--- - BufWriteCmd: Convert buffer back to JSON and save
--- - BufUnload: Cleanup kernel connection and images
--- @param opts table|nil Configuration options (merged with defaults)
function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})
    M.ns = vim.api.nvim_create_namespace("jupyter_notebook")

    setup_highlights(M.config.highlights or {})

    local group = vim.api.nvim_create_augroup("JupyterNotebook", { clear = true })

    vim.api.nvim_create_autocmd({ "BufReadCmd" }, {
        group = group,
        pattern = "*.ipynb",
        callback = function(args)
            notebook.load(args.buf, M.ns, M.config)
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
            require("notebook.kernel").disconnect(args.buf)
            require("notebook.image").clear_buffer(args.buf)
        end,
    })

    require("notebook.actions").setup_commands(M)
end

return M
