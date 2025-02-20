local function assert_scenario(scenario)
    if scenario.initial_buffer then
        vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.fn.split(scenario.initial_buffer, '\n'))
    end
    if scenario.setup then scenario.setup() end
    if scenario.feedkeys then
        for _, raw_keys in ipairs(scenario.feedkeys) do
            local keys = vim.api.nvim_replace_termcodes(raw_keys, true, false, true)
            vim.api.nvim_feedkeys(keys, 'xmt', true)
        end
    end
    if scenario.interlude then scenario.interlude() end
    if scenario.assert then scenario.assert() end
    if scenario.expected_buffer then
        local current_buffer = vim.fn.join(vim.api.nvim_buf_get_lines(0, 0, -1, true), '\n')
        assert.are.equal(current_buffer, scenario.expected_buffer)
    end
end

local function assert_equal_tables(tbl1, tbl2)
    assert(vim.deep_equal(tbl1, tbl2), string.format("%s ~= %s", vim.inspect(tbl1), vim.inspect(tbl2)))
end

local function unload_neoclip()
    for pkg, _ in pairs(package.loaded) do
        if vim.fn.match(pkg, 'neoclip') ~= -1 then
            package.loaded[pkg] = nil
        end
    end
end

describe("neoclip", function()
    after_each(function()
        require('neoclip.storage').clear()
        vim.api.nvim_buf_set_lines(0, 0, -1, true, {})
    end)
    it("storage", function()
        assert_scenario{
            setup = function()
                require('neoclip').setup()
            end,
            initial_buffer = [[
some line
another line
multiple lines
multiple lines
multiple lines
multiple lines
some chars
a block
a block
]],
            feedkeys = {
                "jyy",
                "jyy",
                "jV3jy",
                "4jv$y",
                "j<C-v>j$",

            },
            assert = function()
                assert_equal_tables(
                    {
                        {
                            contents = {"a block", ""},
                            filetype = "",
                            regtype = "c"
                        },
                        {
                            contents = {"multiple lines", "multiple lines", "multiple lines", "some chars"},
                            filetype = "",
                            regtype = "l"
                        },
                        {
                            contents = {"multiple lines"},
                            filetype = "",
                            regtype = "l"
                        },
                        {
                            contents = {"another line"},
                            filetype = "",
                            regtype = "l"
                        },
                    },
                    require('neoclip.storage').get().yanks
                )
            end,
        }
    end)
    it("storage max", function()
        assert_scenario{
            initial_buffer = [[some line]],
            setup = function()
                require('neoclip').setup({
                    history = 2,
                })
            end,
            feedkeys = {
                "yy",
                "yy",
                "yy",
                "yy",
            },
            assert = function()
                assert_equal_tables(
                    {
                        {
                            contents = {"some line"},
                            filetype = "",
                            regtype = "l"
                        },
                        {
                            contents = {"some line"},
                            filetype = "",
                            regtype = "l"
                        },
                    },
                    require('neoclip.storage').get().yanks
                )
            end,
        }
    end)
    it("persistent history", function()
        assert_scenario{
            initial_buffer = [[some line]],
            setup = function()
                require('neoclip').setup({
                    enable_persistent_history = true,
                    db_path = '/tmp/nvim/databases/neoclip.sqlite3',
                })
                vim.fn.system('rm /tmp/nvim/databases/neoclip.sqlite3')
            end,
            feedkeys = {"yy"},
            interlude = function()
                -- emulate closing and starting neovim
                vim.cmd('doautocmd VimLeavePre')
                unload_neoclip()
                require('neoclip.settings').get().enable_persistent_history = true
                require('neoclip.settings').get().db_path = '/tmp/nvim/databases/neoclip.sqlite3'
            end,
            assert = function()
                assert_equal_tables(
                    {
                        {
                            contents = {"some line"},
                            filetype = "",
                            regtype = "l"
                        },
                    },
                    require('neoclip.storage').get().yanks
                )
                assert(vim.fn.filereadable('/tmp/nvim/databases/neoclip.sqlite3'))
            end,
        }
    end)
    it("persistant history", function()
        assert_scenario{
            initial_buffer = [[some line]],
            setup = function()
                require('neoclip').setup({
                    enable_persistant_history = true,
                })
            end,
            assert = function()
                assert.are.equal(require('neoclip.settings').get().enable_persistent_history, true)
            end,
        }
    end)
    it("filter (whitespace)", function()
        assert_scenario{
            initial_buffer = '\nsome line\n\n\t\n',
            setup = function()
                local function is_whitespace(line)
                    return vim.fn.match(line, [[^\s*$]]) ~= -1
                end

                local function all(tbl, check)
                    for _, entry in ipairs(tbl) do
                        if not check(entry) then
                            return false
                        end
                    end
                    return true
                end

                require('neoclip').setup({
                    filter = function(data)
                        return not all(data.event.regcontents, is_whitespace)
                    end,
                })
            end,
            feedkeys = {
                "yy",
                "jyy",
                "jyy",
                "jyy",
            },
            assert = function()
                assert_equal_tables(
                    {
                        {
                            contents = {"some line"},
                            filetype = "",
                            regtype = "l"
                        },
                    },
                    require('neoclip.storage').get().yanks
                )
            end,
        }
    end)
    it("macro", function()
        assert_scenario{
            setup = function()
                require('neoclip').setup()
            end,
            feedkeys = {
                "qq",
                "yy",
                "q",
            },
            assert = function()
                assert_equal_tables(
                    {
                        {
                            contents = {"yy"},
                            regtype = "c"
                        },
                    },
                    require('neoclip.storage').get().macros
                )
            end,
        }
    end)
    it("macro disabled", function()
        assert_scenario{
            setup = function()
                require('neoclip').setup({
                    enable_macro_history = false,
                })
            end,
            feedkeys = {
                "qq",
                "yy",
                "q",
            },
            assert = function()
                io.stdout:write(vim.cmd('autocmd RecordingLeave'))
                assert.are.equal(vim.fn.getreg('q'), 'yy')
                assert_equal_tables(
                    {},
                    require('neoclip.storage').get().macros
                )
            end,
        }
    end)
    -- TODO why doesn't this work?
--     it("telescope", function()
--         assert_scenario{
--             initial_buffer = [[some line
-- another line]],
--             feedkeys = {
--                 "yy",
--                 "jyy",
--                 [[:lua require('telescope').extensions.neoclip.neoclip()<CR>some<CR>]],
--                 "p",
--             },
--             assert = function()
--                 assert.are.equal(vim.fn.getreg('"'), 'some line\n')
--             end,
--             expected_buffer = [[some line
-- another line
-- some line]],
--         }
--     end)
end)
