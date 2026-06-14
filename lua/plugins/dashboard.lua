return {
  "folke/snacks.nvim",
  opts = {
    dashboard = {
      preset = {
        header = [[

  ███╗   ██╗██╗   ██╗██╗███╗   ███╗
  ████╗  ██║██║   ██║██║████╗ ████║
  ██╔██╗ ██║██║   ██║██║██╔████╔██║
  ██║╚██╗██║╚██╗ ██╔╝██║██║╚██╔╝██║
  ██║ ╚████║ ╚████╔╝ ██║██║ ╚═╝ ██║
  ╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚═╝     ╚═╝

  ── "I'm going to have to science the heck out of this." ──
                                          — Mark Watney, probably
]],
        keys = {
          { icon = " ",  key = "f", desc = "Find File",        action = ":lua Snacks.picker.files()" },
          { icon = " ",  key = "n", desc = "New File",          action = ":ene | startinsert" },
          { icon = " ",  key = "g", desc = "Live Grep",         action = ":lua Snacks.picker.grep()" },
          { icon = " ",  key = "r", desc = "Recent Files",      action = ":lua Snacks.picker.recent()" },
          { icon = "󰊢 ",  key = "G", desc = "Lazygit",           action = ":lua Snacks.lazygit()" },
          { icon = " ",  key = "e", desc = "Explorer",          action = ":lua Snacks.explorer()" },
          { icon = "󰔫 ",  key = "d", desc = "Docs",               action = ":DevdocsPicker" },
          { icon = " ",  key = "s", desc = "Restore Session",   section = "session" },
          { icon = " ",  key = "c", desc = "Config",            action = ":lua Snacks.picker.files({ cwd = vim.fn.stdpath('config') })" },
          { icon = "󰒲 ",  key = "L", desc = "Lazy Plugins",     action = ":Lazy" },
          { icon = " ",  key = "q", desc = "Quit",             action = ":qa" },
        },
      },
    },
  },
}
