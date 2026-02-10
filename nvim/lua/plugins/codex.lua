return {
  "johnseth97/codex.nvim",
  cmd = { "Codex", "CodexToggle" }, -- lazy-load on command
  keys = {
    { "<leader>cc", function() require("codex").toggle() end, desc = "Toggle Codex", mode = { "n", "t" } },
  },
  opts = {
    border = "rounded",
    width = 0.8,
    height = 0.8,
    panel = false,      -- false=floating, true=side panel
    use_buffer = false, -- keep it as a terminal buffer
    model = nil,        -- optional
    autoinstall = false, -- you already installed `codex` via npm
  },
}

