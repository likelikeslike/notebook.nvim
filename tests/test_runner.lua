local M = {}

local passed = 0
local failed = 0
local errors = {}

function M.describe(name, fn)
    print("\n" .. name)
    fn()
end

function M.it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("  [PASS] " .. name)
    else
        failed = failed + 1
        print("  [FAIL] " .. name)
        print("         " .. tostring(err))
        table.insert(errors, { name = name, error = err })
    end
end

function M.eq(expected, actual, msg)
    if expected ~= actual then
        error(
            string.format(
                "%s: expected %s, got %s",
                msg or "assertion failed",
                vim.inspect(expected),
                vim.inspect(actual)
            )
        )
    end
end

function M.neq(a, b, msg)
    if a == b then
        error(string.format("%s: values should not be equal: %s", msg or "assertion failed", vim.inspect(a)))
    end
end

function M.is_true(val, msg)
    if not val then error(msg or "expected true") end
end

function M.is_nil(val, msg)
    if val ~= nil then error(string.format("%s: expected nil, got %s", msg or "assertion failed", vim.inspect(val))) end
end

function M.is_not_nil(val, msg)
    if val == nil then error(msg or "expected non-nil value") end
end

function M.is_function(val, msg)
    if type(val) ~= "function" then
        error(string.format("%s: expected function, got %s", msg or "assertion failed", type(val)))
    end
end

function M.matches(pattern, str, msg)
    if not str:match(pattern) then
        error(string.format("%s: '%s' does not match pattern '%s'", msg or "assertion failed", str, pattern))
    end
end

function M.summary()
    print("\n========================================")
    print(string.format("Passed: %d, Failed: %d", passed, failed))
    if failed > 0 then
        print("\nFailed tests:")
        for _, e in ipairs(errors) do
            print("  - " .. e.name)
        end
        vim.cmd("cq 1")
    else
        print("All tests passed!")
        vim.cmd("q")
    end
end

return M
