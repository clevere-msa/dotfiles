return {
  -- Configure LSP servers without Mason.
  -- Servers must be installed on the system and available on $PATH.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Perl
        perlnavigator = {},

        -- Lua
        lua_ls = {},

        -- Bash
        bashls = {},

        -- C / C++ (also used for Pro*C via filetype mapping in `config/autocmds.lua`)
        clangd = {},

        -- Python
        pyright = {},
      },
    },
  },
}

