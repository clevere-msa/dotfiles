require("plugins")

local o = vim.opt

-- o.compatible = true
o.errorbells = true

o.bs = '2'
o.expandtab = true
o.ts = 4
o.shiftwidth = 4
o.textwidth = 105
o.wrap = false
o.autoindent = true
o.smarttab = true

o.autowrite = true

o.hlsearch = true
o.hidden = true

o.fenc = 'utf8'

o.incsearch = true
o.showmatch = true
o.ignorecase = true
o.smartcase = true
o.listchars = 'tab:>-,extends:>,precedes:<,trail:-,eol:$'

o.lazyredraw = true
o.ttyfast = true

o.backup = true
o.backupdir = '~/.vim/backup,/tmp,.'

o.title = true
o.shortmess = 'aTItoO'
o.showmode = true
o.showcmd = true
o.laststatus=2
o.updatetime = 100
o.ruler = true
o.history = 5000

o.updatetime = 100
o.ruler = true
o.history = 500

o.scrolloff = 2
o.sidescrolloff = 5

o.wildmenu = true
o.wildmode = 'longest:full,list:full'

--o.viminfo = '500,f1,:100,/100'

o.modeline = true
o.modelines = 10

o.splitright = true
o.splitbelow = true

-- appearance
o.background = 'dark'
vim.g.airline_theme = 'solarized'
vim.g.airline_solarized_bg = 'dark'
-- vim.g.airline#extensions#ale#enabled = 1

-- o.t_Co = 8
-- o.t_Sb = '^[[4%p1%dm'
-- o.t_Sf = '^[[3%p1%dm'

vim.cmd('syntax enable')
vim.cmd('filetype plugin indent on')

vim.cmd([[
set statusline=[%n]\ %<%f%m%r\ %w\ %y\ \ <%{&fileformat}>%=[%o]\ %l,%c%V\/%L\ \ %P"

" make tab autocomplete :) http://www.vim.org/tips/tip.php?tip_id=102
function! InsertTabWrapper()
    let col = col('.') - 1
    if !col || getline('.')[col - 1] !~ '\k'
        return "\<tab>"
    else
        return "\<c-p>"
    endif
endfunction

inoremap <tab> <c-r>=InsertTabWrapper()<cr>

" Folding stuff
let perl_fold=1
let perl_nofold_packages=1
set fillchars=vert:\|,fold:-

" Toggle fold state between closed and opened.
"
" If there is no fold at current line, just moves forward.
" If it is present, reverse it's state.
fu! ToggleFold()
    if foldlevel('.') == 0
        normal! l
    else
        if foldclosed('.') < 0
            . foldclose
        else
            . foldopen
        endif
    endif
    echo
endf

" Map this function to Space key.
noremap <space> :call ToggleFold()<CR>

nnoremap <F1> :help<Space>
vmap <F1> <C-C><F1>
omap <F1> <C-C><F1>
map! <F1> <C-C><F1>

" Select all.
nnoremap <C-A> ggVG

" Toggle line numbering
map <silent> <F2> :set invnumber<cr>

" Toggle paste mode.
nnoremap \pt :set invpaste paste?<CR>
nmap <F5> \pt
imap <F5> <C-O>\pt
set pastetoggle=<F5>

" Cycle panes, forward and reverse
noremap <silent> <F6> <C-W>w
"noremap <silent> <S-F6> <C-W>W

" New Panes
noremap <silent> <F7> <C-W>v
"noremap <silent> <S-F7> <C-W>s
"nnoremap <C-F7> :vsplit<space>

if !exists("autocmds_loaded")
    let autocmds_loaded = 1

    " Jump to last known position in file.
    autocmd BufReadPost *
                \ if line("'\"") > 0 && line("'\"") <= line("$") |
                \     exe "normal g`\"" |
                \ endif

    " Warn when file has changed externally.
    autocmd FileChangedShell *
                \ echohl WarningMsg |
                \ echo "File has been changed outside of vim." |
                \ echohl None

    if has("autocmd") && exists("+omnifunc")
        autocmd Filetype *
            \   if &omnifunc == "" |
            \           setlocal omnifunc=syntaxcomplete#Complete |
            \   endif
    endif

    autocmd BufRead,BufNewFile *.t,*.pl,*.plx,*.pm,*.cgi command! -range=% -nargs=* Tidy <line1>,<line2>!perltidy -q
    autocmd BufRead,BufNewFile *.t,*.pl,*.plx,*.pm,*.cgi set commentstring=#%s
    autocmd BufRead,BufNewFile *.t,*.pl,*.plx,*.pm,*.cgi noremap <F9>  :Tidy<CR>
    autocmd BufRead,BufNewFile *.t,*.pl,*.plx,*.pm,*.cgi noremap <F10> :compiler perl<CR>
    autocmd BufRead,BufNewFile *.t,*.pl,*.plx,*.pm,*.cgi noremap <F11> :compiler perlcritic<CR>
    autocmd BufRead,BufNewFile *.t,*.pl,*.plx,*.pm,*.cgi noremap <F12> :make<CR>
endif

cmap w!! %!sudo tee > /dev/null %

let g:ale_linters = {
\ 'go': ['gofmt', 'golint', 'go vet', 'gometalinter'],
\ 'perl': ['perl','perlcritic','perltidy']
\}
let g:ale_type_map = {
\    'perl': {'ES': 'WS'}, 
\    'perlcritic': {'ES': 'WS', 'E': 'W'},
\}

noremap ,qq     :%s/(\n\s\+\(qq\?\)\[/(\1[<cr>
noremap ,c      :!perl -Ilib -c %<cr>
noremap ,d      :!perl -Ilib -d %<cr>
noremap ,j      :ls<cr>:e#
noremap ,s      :!subs %<cr>

" automatically source the .vimrc file if I change it
" the bang (!) forces it to overwrite this command rather than stack it
au! BufWritePost .vimrc source %

noremap ,v  :source ~/.vimrc<cr>
noremap ,V  :e ~/.vimrc<cr>

" make sure the backspace key works
if &term=="xterm"
    " this is a "control-v backspace"
    set t_kb=^?
    fixdel
endif
]])

local parser_config = require "nvim-treesitter.parsers".get_parser_configs()
parser_config.perl = {
  install_info = {
    url = 'https://github.com/tree-sitter-perl/tree-sitter-perl',
    revision = 'release',
    files = { "src/parser.c", "src/scanner.c" },
  }
}
