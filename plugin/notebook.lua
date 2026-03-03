if vim.g.loaded_notebook then
    return
end
vim.g.loaded_notebook = true

-- Generate helptags if missing
local doc_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h") .. "/doc"
local tags_path = doc_path .. "/tags"
if vim.fn.filereadable(tags_path) == 0 and vim.fn.isdirectory(doc_path) == 1 then
    vim.cmd("silent! helptags " .. vim.fn.fnameescape(doc_path))
end

vim.api.nvim_create_user_command("NotebookSetup", function()
    require("notebook").setup()
end, { desc = "Setup Jupyter Notebook plugin with default options" })
