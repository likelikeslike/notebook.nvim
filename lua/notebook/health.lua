---@mod notebook.health Health Check
---@brief [[
--- Health check for :checkhealth notebook
---
--- Checks:
--- - Neovim version >= 0.10.0
--- - notebook.nvim setup() called
--- - Treesitter parsers for markdown highlighting (optional)
--- - image.nvim availability (optional)
--- - LSP servers configured (optional)
--- - Python interpreter and packages
---@brief ]]

local M = {}

local health = vim.health

--- Run health checks (:checkhealth notebook)
function M.check()
    health.start("notebook.nvim")

    if vim.fn.has("nvim-0.10") == 1 then
        health.ok("Neovim >= 0.10.0")
    else
        health.error("Neovim >= 0.10.0 required", {
            "Update Neovim to version 0.10.0 or later",
        })
    end

    local notebook = require("notebook")
    if notebook.ns then
        health.ok("notebook.nvim is set up")
    else
        health.warn("notebook.nvim setup() not called", {
            "Call require('notebook').setup() in your config",
        })
    end

    local parsers = { "python", "markdown", "markdown_inline" }
    for _, lang in ipairs(parsers) do
        local ok = pcall(vim.treesitter.language.add, lang)
        if ok then
            health.ok("Treesitter parser: " .. lang)
        else
            health.warn("Treesitter parser not found: " .. lang, {
                lang == "python" and "Required for code cell highlighting" or "Required for markdown cell highlighting",
                "Install with :TSInstall " .. lang,
            })
        end
    end

    local has_image, _ = pcall(require, "image")
    if has_image then
        health.ok("image.nvim available (optional)")
    else
        health.warn("image.nvim not installed (optional, for image output)")
    end

    local config = notebook.config or {}
    if config.lsp and next(config.lsp) then
        local lsp_list = {}
        for _, servers in pairs(config.lsp) do
            for _, server in ipairs(servers) do
                table.insert(lsp_list, server.name or "unnamed")
            end
        end
        health.ok("LSP servers configured: " .. table.concat(lsp_list, ", "))
    else
        health.warn("No LSP servers configured (optional)")
    end

    local python = config.python and config.python.path
    if not python or python == "" then
        health.warn("No Python interpreter selected", {
            "Select one with :JupyterSelectKernel",
        })
    else
        if vim.fn.executable(python) == 1 then
            health.ok("Python interpreter: " .. python)
            vim.fn.system({ python, "-c", "import jupyter_client" })
            if vim.v.shell_error == 0 then
                health.ok("jupyter_client available")
            else
                health.error("jupyter_client not installed", {
                    "Install with: " .. python .. " -m pip install jupyter_client",
                })
            end
            vim.fn.system({ python, "-c", "import ipykernel" })
            if vim.v.shell_error == 0 then
                health.ok("ipykernel available")
            else
                health.error("ipykernel not installed", {
                    "Install with: " .. python .. " -m pip install ipykernel",
                })
            end
        else
            health.error("Configured Python not found: " .. python)
        end
    end
end

return M
