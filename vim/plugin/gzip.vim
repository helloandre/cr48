" Vim plugin for editing compressed files.
" Maintainer: Bram Moolenaar <Bram@vim.org>
" Last Change: 2009 Jul 01

" Exit quickly when:
" - this plugin was already loaded
" - when 'compatible' is set
" - some autocommands are already taking care of compressed files
if exists("loaded_gzip") || &cp || exists("#BufReadPre#*.gz")
  finish
endif
let loaded_gzip = 1

augroup gzip
  " Remove all gzip autocommands
  au!

  " Enable editing of gzipped files.
  " The functions are defined in autoload/gzip.vim.
  "
  " Set binary mode before reading the file.
  " Use "gzip -d", gunzip isn't always available.
  autocmd BufReadPre,FileReadPre	*.gz,*.bz2,*.Z,*.lzma setlocal bin
  autocmd BufReadPost,FileReadPost	*.gz  call gzip#read("gzip -dn")
  autocmd BufReadPost,FileReadPost	*.bz2 call gzip#read("bzip2 -d")
  autocmd BufReadPost,FileReadPost	*.Z   call gzip#read("uncompress")
  autocmd BufReadPost,FileReadPost	*.lzma call gzip#read("lzma -d")
  autocmd BufWritePost,FileWritePost	*.gz  call gzip#write("gzip")
  autocmd BufWritePost,FileWritePost	*.bz2 call gzip#write("bzip2")
  autocmd BufWritePost,FileWritePost	*.Z   call gzip#write("compress -f")
  autocmd BufWritePost,FileWritePost	*.lzma call gzip#write("lzma -z")
  autocmd FileAppendPre			*.gz  call gzip#appre("gzip -dn")
  autocmd FileAppendPre			*.bz2 call gzip#appre("bzip2 -d")
  autocmd FileAppendPre			*.Z   call gzip#appre("uncompress")
  autocmd FileAppendPre			*.lzma call gzip#appre("lzma -d")
  autocmd FileAppendPost		*.gz  call gzip#write("gzip")
  autocmd FileAppendPost		*.bz2 call gzip#write("bzip2")
  autocmd FileAppendPost		*.Z   call gzip#write("compress -f")
  autocmd FileAppendPost		*.lzma call gzip#write("lzma -z")
augroup END
