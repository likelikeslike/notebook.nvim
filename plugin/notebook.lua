vim.api.nvim_create_user_command("NotebookSetup", function()
    require("notebook").setup()
end, { desc = "Setup Jupyter Notebook plugin with default options" })