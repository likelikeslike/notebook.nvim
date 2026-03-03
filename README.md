# notebook.nvim

A Neovim plugin for editing Jupyter notebooks (`.ipynb` files) natively.

Notebooks render as plain text buffers with `# %%` cell separators. Execute code cells against a real Jupyter kernel, see streaming output as virtual text, and display inline images -- all without leaving Neovim.

## Features

- **Native `.ipynb` editing** -- open, edit, and save notebooks as structured cell buffers
- **Markdown highlighting** -- markdown cells render with native treesitter highlighting, identical to editing a `.md` file
- **Jupyter kernel execution** -- run code cells with real-time streaming output
- **Cell management** -- add, delete, merge, reorder, and toggle code/markdown cells
- **Inline image display** -- render PNG outputs in terminal via [image.nvim](https://github.com/3rd/image.nvim)
- **LSP integration** -- pyright/basedpyright/ruff with automatic Python path injection and markdown cell diagnostic filtering
- **Variable inspector** -- view all kernel variables or hover-inspect the symbol under cursor
- **Output control** -- truncated virtual text with configurable max lines; full output in floating windows
- **Python interpreter picker** -- discovers venvs, conda, pyenv, uv, and system interpreters
- **Yank highlighting** -- respects cell background colors

## Demos

![long output](demo/long_output.gif)

![image output](demo/image_output.gif)

![stream output](demo/stream_output.gif)

![variables](demo/variables.gif)

## Requirements

**Required:**
- Neovim >= 0.10
- Python 3 interpreter
- `jupyter_client` and `ipykernel` packages (auto-install offered on first kernel selection)

**Optional:**
- [image.nvim](https://github.com/3rd/image.nvim) for inline PNG rendering
- ImageMagick (`identify` command) for image sizing
- Terminal with image protocol support (kitty, iTerm2, Sixel)

## Installation

### lazy.nvim

Minimal:

```lua
{
    "likelikeslike/notebook.nvim",
    event = "BufReadCmd *.ipynb",
    config = function()
        require("notebook").setup()
    end,
}
```

With image support and LSP (recommended):

```lua
{
    "likelikeslike/notebook.nvim",
    event = "BufReadCmd *.ipynb",
    dependencies = {
        { "mason-org/mason.nvim" },
        {
            "3rd/image.nvim",
            event = "BufReadCmd *.ipynb",
            build = false,
            opts = {
                backend = "kitty",
                processor = "magick_cli",
                integrations = {},
            },
        },
    },
    config = function()
        require("notebook").setup({
            keys = {
                -- Remap j/k if you use Colemak or other layouts
                -- ["i"] = "move_up",
                -- ["k"] = "move_down",
            },
            diagnostics = {
                underline = true,
                update_in_insert = false,
                virtual_text = {
                    spacing = 4,
                    source = "if_many",
                    prefix = "●",
                },
                severity_sort = true,
                signs = {
                    text = {
                        [vim.diagnostic.severity.ERROR] = " ",
                        [vim.diagnostic.severity.WARN] = " ",
                        [vim.diagnostic.severity.HINT] = " ",
                        [vim.diagnostic.severity.INFO] = " ",
                    },
                },
                severity_sort = true,
            },
            lsp = {
                python = {
                    {
                        name = "basedpyright",
                        -- or use (vim.fn.stdpath("data") .. "/mason/bin/basedpyright-langserver") if you don't wnat Mason to be loaded
                        cmd = { vim.fn.exepath("basedpyright-langserver"), "--stdio" },
                        settings = {
                            basedpyright = {
                                analysis = {
                                    typeCheckingMode = "basic",
                                    autoSearchPaths = true,
                                    useLibraryCodeForTypes = true,
                                    diagnosticMode = "openFilesOnly",
                                },
                            },
                        },
                    },
                    {
                        name = "ruff",
                        cmd = { vim.fn.exepath("ruff"), "server" },
                        -- or use (vim.fn.stdpath("data") .. "/mason/bin/ruff") if you don't wnat Mason to be loaded
                        cmd_env = { RUFF_TRACE = "messages" },
                        init_options = {
                            settings = { logLevel = "error" },
                        },
                        keys = {
                            {
                                "<leader>co",
                                function()
                                    vim.lsp.buf.code_action({
                                        apply = true,
                                        context = { only = { "source.organizeImports" }, diagnostics = {} },
                                    })
                                end,
                                desc = "Organize Imports",
                            },
                            {
                                "<leader>cf",
                                function()
                                    vim.lsp.buf.code_action({
                                        apply = true,
                                        context = { only = { "source.fixAll" }, diagnostics = {} },
                                    })
                                end,
                                desc = "Fix All",
                            },
                        },
                    },
                },
            },
        })
    end,
}
```

## Configuration

All options with defaults:

```lua
require("notebook").setup({
    python = nil,             -- Python interpreter; set via :JupyterSelectKernel
    max_output_lines = 20,    -- Virtual text lines before truncation
    yank_highlight = true,    -- Yank highlight respects cell backgrounds
    keys = {},                -- Keymap overrides: { ["<key>"] = "action_name" }
    highlights = nil,         -- Highlight overrides (see Highlights section)
    diagnostics = nil,        -- vim.diagnostic.config() options
    lsp = {},                 -- LSP servers per filetype (see installation example above)
})
```

See the [lazy.nvim setup example](#lazynvim) above for a complete production
config with basedpyright, ruff, image.nvim, and diagnostics.

## Keymaps

All keymaps are buffer-local to `.ipynb` buffers. Override any default via the `keys` config.

### Navigation

| Keymap | Action | Description |
|--------|--------|-------------|
| `]c` | `next_cell` | Go to next cell |
| `[c` | `prev_cell` | Go to previous cell |
| `j` / `<Down>` | `move_down` | Move down (respects cell boundaries) |
| `k` / `<Up>` | `move_up` | Move up (respects cell boundaries) |

### Cell Management

| Keymap | Action | Description |
|--------|--------|-------------|
| `<leader>ja` | `add_cell_below` | Add code cell below |
| `<leader>jA` | `add_cell_above` | Add code cell above |
| `<leader>jd` | `delete_cell` | Delete current cell |
| `<leader>jt` | `toggle_cell_type` | Toggle code/markdown |
| `<leader>jm` | `merge_cell_below` | Merge with cell below |
| `<leader>jM` | `merge_cell_above` | Merge with cell above |

### Execution

| Keymap | Action | Description |
|--------|--------|-------------|
| `<leader>jx` | `execute_cell` | Execute current cell |
| `<leader>jX` | `execute_all_cells` | Execute all cells |
| `<leader>jb` | `execute_cells_below` | Execute from current cell to end |
| `<leader>jB` | `execute_cells_above` | Execute from start to current cell |
| `<leader>ji` | `interrupt_kernel` | Interrupt running execution |

### Kernel

| Keymap | Action | Description |
|--------|--------|-------------|
| `<leader>jk` | `select_kernel` | Select Python interpreter |
| `<leader>jr` | `restart_kernel` | Restart kernel |
| `<leader>jv` | `show_variables` | Show kernel variables |
| `<leader>jh` | `inspect_variable` | Inspect variable under cursor |

### Output

| Keymap | Action | Description |
|--------|--------|-------------|
| `<leader>jo` | `toggle_output` | Toggle floating output window |
| `<leader>jc` | `clear_cell_output` | Clear current cell output |
| `<leader>jC` | `clear_all_outputs` | Clear all cell outputs |

### Editing

| Keymap | Action | Description |
|--------|--------|-------------|
| `o` | `open_below` | Open line below (within cell) |
| `O` | `open_above` | Open line above (within cell) |
| `dd` | `delete_line` | Delete line (protected from separators) |
| `<BS>` | `backspace` | Backspace (protected at cell boundary) |
| `<CR>` | `enter_key` | Enter in insert mode (extends cell) |

`dG`, `dgg`, `yG`, `ygg`, `G` (visual), `gg` (visual) are all scoped to current cell boundaries.

## Commands

| Command | Description |
|---------|-------------|
| `:JupyterSelectKernel` | Select Python interpreter (discovers venvs, conda, pyenv, uv, system) |
| `:JupyterExecuteCell` | Execute current cell (auto-connects kernel) |
| `:JupyterExecuteAll` | Execute all cells sequentially |
| `:JupyterExecuteBelow` | Execute from current cell to end |
| `:JupyterExecuteAbove` | Execute from start to current cell |
| `:JupyterInterrupt` | Interrupt running execution |
| `:JupyterRestart` | Restart kernel (clears state) |
| `:JupyterVariables` | Show kernel variables in floating window |
| `:JupyterInspect` | Inspect variable under cursor |
| `:JupyterToggleOutput` | Toggle floating output window with images |
| `:JupyterClearOutput` | Clear current cell output |
| `:JupyterClearAllOutputs` | Clear all outputs |
| `:JupyterAddCellBelow` | Add code cell below |
| `:JupyterAddCellAbove` | Add code cell above |
| `:JupyterDeleteCell` | Delete current cell |
| `:JupyterToggleCellType` | Toggle code/markdown |
| `:JupyterMergeCellBelow` | Merge with cell below |
| `:JupyterMergeCellAbove` | Merge with cell above |
| `:JupyterNextCell` | Go to next cell |
| `:JupyterPrevCell` | Go to previous cell |

## Highlights

| Group | Default Link | Description |
|-------|-------------|-------------|
| `JupyterNotebookCellBg` | `CursorLine` | Code cell background |
| `JupyterNotebookCellBgMarkdown` | `ColorColumn` | Markdown cell background |
| `JupyterNotebookCellLabel` | `Comment` | Code cell label (In [n]) |
| `JupyterNotebookCellLabelMarkdown` | `Special` | Markdown cell label |
| `JupyterNotebookOutputBorder` | `FloatBorder` | Output box border |
| `JupyterNotebookOutput` | `Normal` | Output text |
| `JupyterNotebookOutputResult` | `String` | Execute result text |
| `JupyterNotebookOutputError` | `DiagnosticError` | Error output text |

Override via the `highlights` config:

```lua
require("notebook").setup({
    highlights = {
        cell_bg = { link = "CursorLine" },
        cell_bg_markdown = { bg = "#24283b" },
        cell_label = { fg = "#565f89", italic = true },
        output_border = { link = "FloatBorder" },
        output_error = { fg = "#db4b4b", bold = true },
    },
})
```

## License

MIT
