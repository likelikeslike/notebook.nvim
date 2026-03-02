if vim.g.loaded_notebook then
    return
end
vim.g.loaded_notebook = true

vim.api.nvim_create_user_command("NotebookSetup", function()
    require("notebook").setup()
end, { desc = "Setup Jupyter Notebook plugin with default options" })