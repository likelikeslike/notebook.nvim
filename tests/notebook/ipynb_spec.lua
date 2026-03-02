local t = require("tests.test_runner")
local ipynb = require("notebook.ipynb")

t.describe("ipynb.load", function()
    t.it("returns default notebook for non-existent file", function()
        local nb = ipynb.load("/nonexistent/path/test.ipynb")
        t.is_not_nil(nb)
        t.is_not_nil(nb.cells)
        t.eq(4, nb.nbformat)
    end)
end)

t.describe("ipynb.source_to_lines", function()
    t.it("converts string source to lines", function()
        local lines = ipynb.source_to_lines("line1\nline2\nline3")
        t.eq(3, #lines)
        t.eq("line1", lines[1])
        t.eq("line2", lines[2])
        t.eq("line3", lines[3])
    end)

    t.it("converts table source to lines", function()
        local lines = ipynb.source_to_lines({ "line1\n", "line2\n", "line3" })
        t.eq(3, #lines)
    end)

    t.it("handles nil source", function()
        local lines = ipynb.source_to_lines(nil)
        t.eq(0, #lines)
    end)
end)

t.describe("ipynb.lines_to_source", function()
    t.it("converts lines to source array", function()
        local source = ipynb.lines_to_source({ "line1", "line2", "line3" })
        t.eq(3, #source)
        t.eq("line1\n", source[1])
        t.eq("line2\n", source[2])
        t.eq("line3", source[3])
    end)

    t.it("handles empty lines", function()
        local source = ipynb.lines_to_source({})
        t.eq(0, #source)
    end)
end)

t.describe("ipynb.save", function()
    t.it("writes valid JSON that can be reloaded", function()
        local tmp = vim.fn.tempname() .. ".ipynb"
        local notebook = {
            cells = {
                {
                    cell_type = "code",
                    metadata = {},
                    source = { "print('hello')\n" },
                    outputs = {},
                },
            },
            metadata = {
                kernelspec = { name = "python3", display_name = "Python 3", language = "python" },
                language_info = { name = "python", version = "3.11" },
            },
            nbformat = 4,
            nbformat_minor = 5,
        }

        local ok = ipynb.save(tmp, notebook)
        t.is_true(ok)

        local reloaded = ipynb.load(tmp)
        t.is_not_nil(reloaded)
        t.eq(4, reloaded.nbformat)
        t.eq(1, #reloaded.cells)
        t.eq("code", reloaded.cells[1].cell_type)

        vim.fn.delete(tmp)
    end)

    t.it("produces indented JSON", function()
        local tmp = vim.fn.tempname() .. ".ipynb"
        local notebook = {
            cells = {},
            metadata = { kernelspec = { name = "python3" } },
            nbformat = 4,
            nbformat_minor = 5,
        }

        ipynb.save(tmp, notebook)

        local file = io.open(tmp, "r")
        local content = file:read("*all")
        file:close()
        t.is_true(content:match("\n") ~= nil)
        t.is_true(content:match("^ ") ~= nil or content:match("\n ") ~= nil)

        vim.fn.delete(tmp)
    end)

    t.it("returns false for invalid path", function()
        local ok = ipynb.save("/nonexistent/dir/test.ipynb", { cells = {}, metadata = {}, nbformat = 4 })
        t.is_true(not ok)
    end)
end)
