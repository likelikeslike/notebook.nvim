local t = require("tests.test_runner")
local utils = require("notebook.utils")

t.describe("utils.generate_cell_id", function()
    t.it("generates unique IDs", function()
        local id1 = utils.generate_cell_id()
        local id2 = utils.generate_cell_id()
        t.neq(id1, id2)
    end)

    t.it("starts with 'cell_' prefix", function()
        local id = utils.generate_cell_id()
        t.matches("^cell_", id)
    end)
end)

t.describe("utils.is_separator", function()
    t.it("matches exactly '# %%'", function()
        t.is_true(utils.is_separator("# %%"))
    end)

    t.it("matches '# %% [markdown]'", function()
        t.is_true(utils.is_separator("# %% [markdown]"))
    end)

    t.it("matches with trailing content after whitespace", function()
        t.is_true(utils.is_separator("# %% foo bar"))
    end)

    t.it("matches tab after marker", function()
        t.is_true(utils.is_separator("# %%\t"))
    end)

    t.it("rejects '# %' (single percent)", function()
        t.is_true(not utils.is_separator("# %"))
    end)

    t.it("rejects three or more percents", function()
        t.is_true(not utils.is_separator("# %%%"))
    end)

    t.it("rejects adjacent text after marker ('# %%bar')", function()
        t.is_true(not utils.is_separator("# %%bar"))
    end)

    t.it("rejects indented marker", function()
        t.is_true(not utils.is_separator("  # %%"))
    end)

    t.it("rejects double-hash", function()
        t.is_true(not utils.is_separator("## %%"))
    end)

    t.it("rejects marker inside string literal", function()
        t.is_true(not utils.is_separator([[print("# %%")]]))
    end)

    t.it("rejects '# ' with extra space before '%%'", function()
        t.is_true(not utils.is_separator("#  %%"))
    end)
end)

t.describe("utils.parse_separator", function()
    t.it("parses code cell", function()
        t.eq("code", utils.parse_separator("# %%"))
    end)

    t.it("parses markdown cell", function()
        t.eq("markdown", utils.parse_separator("# %% [markdown]"))
    end)

    t.it("parses markdown short form", function()
        t.eq("markdown", utils.parse_separator("# %% [md]"))
    end)

    t.it("returns 'code' for legacy 'id:' line", function()
        t.eq("code", utils.parse_separator("# %% id:cell_123_456"))
    end)

    t.it("returns 'markdown' for legacy markdown-with-id line", function()
        t.eq("markdown", utils.parse_separator("# %% [markdown] id:abc123"))
    end)
end)

t.describe("utils.build_separator", function()
    t.it("builds code cell separator", function()
        t.eq("# %%", utils.build_separator("code"))
    end)

    t.it("builds markdown cell separator", function()
        t.eq("# %% [markdown]", utils.build_separator("markdown"))
    end)

    t.it("output never contains 'id:' (Copilot safety invariant)", function()
        local a = utils.build_separator("code")
        local b = utils.build_separator("markdown")
        t.eq(nil, a:match("id:"))
        t.eq(nil, b:match("id:"))
    end)
end)

t.describe("utils.format_elapsed", function()
    t.it("returns empty string for nil", function()
        t.eq("", utils.format_elapsed(nil))
    end)

    t.it("formats sub-second as milliseconds", function()
        local result = utils.format_elapsed(0.234)
        t.matches("234ms", result)
    end)

    t.it("formats seconds with two decimals", function()
        local result = utils.format_elapsed(5.67)
        t.matches("5%.67s", result)
    end)

    t.it("formats minutes and seconds", function()
        local result = utils.format_elapsed(125.3)
        t.matches("2m", result)
    end)
end)
