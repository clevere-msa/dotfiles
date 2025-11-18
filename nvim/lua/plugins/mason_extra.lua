return {
  -- Extend the default mason.nvim configuration
  "williamboman/mason.nvim",
  opts = function(_, opts)
    if type(opts.ensure_installed) == "table" then
      -- Add "perl-language-server" to the list of language servers Mason will install
      vim.list_extend(opts.ensure_installed, { "perlnavigator" })
    end
  end,
}
