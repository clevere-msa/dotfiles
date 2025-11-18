return {
  {
    "vim-perl/vim-perl",
    ft = "perl", -- file type
    build = "make clean carp dancer highlight-all-pragmas moose test-more try-tiny",
  },
}
