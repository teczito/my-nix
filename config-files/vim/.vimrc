''
set nocompatible
set belloff=all
"set spell
filetype plugin on
" allow backspacing over everything in insert mode
set backspace=indent,eol,start
set history=50 " keep 50 lines of command line history
set ruler " show the cursor position all the time
set showcmd " display incomplete commands
set incsearch " do incremental searching

"set number " line numbers
set cindent
set autoindent
set mouse=a " use mouse in xterm to scroll
set scrolloff=2 " 2 lines before and after the current line when scrolling
set hid " allow switching buffers, which have unsaved changes
set showmatch " showmatch: Show the matching bracket for the last ')'?

"set nowrap " don't wrap by default
syn on
set completeopt=menu,longest,preview
set confirm

"--- Custom settings ---
" CTRL-U in insert mode deletes a lot.  Use CTRL-G u to first break undo,
" so that you can undo CTRL-U after inserting a line break.
inoremap <C-U> <C-G>u<C-U>

" remap the arrow keys
nnoremap <Left> zh
nnoremap <Right> zl
nnoremap <Up> <C-Y>
nnoremap <Down> <C-E>

syntax on
set hlsearch

"do not wrap a search
set nowrapscan

"use smartcase for searching
set ignorecase
set smartcase

set expandtab
set tabstop=2
set softtabstop=2
set shiftwidth=2

command! -nargs=? -range Dec2hex call s:Dec2hex(<line1>, <line2>, '<args>')
function! s:Dec2hex(line1, line2, arg) range
  if empty(a:arg)
    if histget(':', -1) =~# "^'<,'>" && visualmode() !=# 'V'
      let cmd = 's/\%V\<\d\+\>/\=printf("0x%x",submatch(0)+0)/gc'
    else
      let cmd = 's/\<\d\+\>/\=printf("0x%x",submatch(0)+0)/gc'
    endif
    try
      execute a:line1 . ',' . a:line2 . cmd
    catch
      echo 'Error: No decimal number found'
    endtry
  else
    echo printf('%x', a:arg + 0)
  endif
endfunction

command! -nargs=? -range Hex2dec call s:Hex2dec(<line1>, <line2>, '<args>')
function! s:Hex2dec(line1, line2, arg) range
  if empty(a:arg)
    if histget(':', -1) =~# "^'<,'>" && visualmode() !=# 'V'
      let cmd = 's/\%V0x\x\+/\=submatch(0)+0/gc'
    else
      let cmd = 's/0x\x\+/\=submatch(0)+0/gc'
    endif
    try
      execute a:line1 . ',' . a:line2 . cmd
    catch
      echo 'Error: No hex number starting "0x" found'
    endtry
  else
    echo (a:arg =~? '^0x') ? a:arg + 0 : ('0x'.a:arg) + 0
  endif
endfunction
''
