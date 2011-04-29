" Language:    OCaml
" Maintainer:  David Baelde        <firstname.name@ens-lyon.org>
"              Mike Leary          <leary@nwlink.com>
"              Markus Mottl        <markus.mottl@gmail.com>
"              Stefano Zacchiroli  <zack@bononia.it>
"              Vincent Aravantinos <firstname.name@imag.fr>
" URL:         http://www.ocaml.info/vim/ftplugin/ocaml.vim
" Last Change: 2010 Jul 10 - Bugfix, thanks to Pat Rondon
"              2008 Jul 17 - Bugfix related to fnameescape (VA)
"              2007 Sep 09 - Added .annot support for ocamlbuild, python not 
"                            needed anymore (VA)
"              2006 May 01 - Added .annot support for file.whateverext (SZ)
"	             2006 Apr 11 - Fixed an initialization bug; fixed ASS abbrev (MM)
"              2005 Oct 13 - removed GPL; better matchit support (MM, SZ)
"
if exists("b:did_ftplugin")
  finish
endif
let b:did_ftplugin=1

" some macro
if exists('*fnameescape')
  function! s:Fnameescape(s)
    return fnameescape(a:s)
  endfun
else
  function! s:Fnameescape(s)
    return escape(a:s," \t\n*?[{`$\\%#'\"|!<")
  endfun
endif

" Error handling -- helps moving where the compiler wants you to go
let s:cposet=&cpoptions
set cpo-=C
setlocal efm=
      \%EFile\ \"%f\"\\,\ line\ %l\\,\ characters\ %c-%*\\d:,
      \%EFile\ \"%f\"\\,\ line\ %l\\,\ character\ %c:%m,
      \%+EReference\ to\ unbound\ regexp\ name\ %m,
      \%Eocamlyacc:\ e\ -\ line\ %l\ of\ \"%f\"\\,\ %m,
      \%Wocamlyacc:\ w\ -\ %m,
      \%-Zmake%.%#,
      \%C%m,
      \%D%*\\a[%*\\d]:\ Entering\ directory\ `%f',
      \%X%*\\a[%*\\d]:\ Leaving\ directory\ `%f',
      \%D%*\\a:\ Entering\ directory\ `%f',
      \%X%*\\a:\ Leaving\ directory\ `%f',
      \%DMaking\ %*\\a\ in\ %f

" Add mappings, unless the user didn't want this.
if !exists("no_plugin_maps") && !exists("no_ocaml_maps")
  " (un)commenting
  if !hasmapto('<Plug>Comment')
    nmap <buffer> <LocalLeader>c <Plug>LUncomOn
    vmap <buffer> <LocalLeader>c <Plug>BUncomOn
    nmap <buffer> <LocalLeader>C <Plug>LUncomOff
    vmap <buffer> <LocalLeader>C <Plug>BUncomOff
  endif

  nnoremap <buffer> <Plug>LUncomOn mz0i(* <ESC>$A *)<ESC>`z
  nnoremap <buffer> <Plug>LUncomOff :s/^(\* \(.*\) \*)/\1/<CR>:noh<CR>
  vnoremap <buffer> <Plug>BUncomOn <ESC>:'<,'><CR>`<O<ESC>0i(*<ESC>`>o<ESC>0i*)<ESC>`<
  vnoremap <buffer> <Plug>BUncomOff <ESC>:'<,'><CR>`<dd`>dd`<

  if !hasmapto('<Plug>Abbrev')
    iabbrev <buffer> ASS (assert (0=1) (* XXX *))
  endif
endif

" Let % jump between structure elements (due to Issac Trotts)
let b:mw = ''
let b:mw = b:mw . ',\<let\>:\<and\>:\(\<in\>\|;;\)'
let b:mw = b:mw . ',\<if\>:\<then\>:\<else\>'
let b:mw = b:mw . ',\<\(for\|while\)\>:\<do\>:\<done\>,'
let b:mw = b:mw . ',\<\(object\|sig\|struct\|begin\)\>:\<end\>'
let b:mw = b:mw . ',\<\(match\|try\)\>:\<with\>'
let b:match_words = b:mw

let b:match_ignorecase=0

" switching between interfaces (.mli) and implementations (.ml)
if !exists("g:did_ocaml_switch")
  let g:did_ocaml_switch = 1
  map <LocalLeader>s :call OCaml_switch(0)<CR>
  map <LocalLeader>S :call OCaml_switch(1)<CR>
  fun OCaml_switch(newwin)
    if (match(bufname(""), "\\.mli$") >= 0)
      let fname = s:Fnameescape(substitute(bufname(""), "\\.mli$", ".ml", ""))
      if (a:newwin == 1)
        exec "new " . fname
      else
        exec "arge " . fname
      endif
    elseif (match(bufname(""), "\\.ml$") >= 0)
      let fname = s:Fnameescape(bufname("")) . "i"
      if (a:newwin == 1)
        exec "new " . fname
      else
        exec "arge " . fname
      endif
    endif
  endfun
endif

" Folding support

" Get the modeline because folding depends on indentation
let s:s = line2byte(line('.'))+col('.')-1
if search('^\s*(\*:o\?caml:')
  let s:modeline = getline(".")
else
  let s:modeline = ""
endif
if s:s > 0
  exe 'goto' s:s
endif

" Get the indentation params
let s:m = matchstr(s:modeline,'default\s*=\s*\d\+')
if s:m != ""
  let s:idef = matchstr(s:m,'\d\+')
elseif exists("g:omlet_indent")
  let s:idef = g:omlet_indent
else
  let s:idef = 2
endif
let s:m = matchstr(s:modeline,'struct\s*=\s*\d\+')
if s:m != ""
  let s:i = matchstr(s:m,'\d\+')
elseif exists("g:omlet_indent_struct")
  let s:i = g:omlet_indent_struct
else
  let s:i = s:idef
endif

" Set the folding method
if exists("g:ocaml_folding")
  setlocal foldmethod=expr
  setlocal foldexpr=OMLetFoldLevel(v:lnum)
endif

" - Only definitions below, executed once -------------------------------------

if exists("*OMLetFoldLevel")
  finish
endif

function s:topindent(lnum)
  let l = a:lnum
  while l > 0
    if getline(l) =~ '\s*\%(\<struct\>\|\<sig\>\|\<object\>\)'
      return indent(l)
    endif
    let l = l-1
  endwhile
  return -s:i
endfunction

function OMLetFoldLevel(l)

  " This is for not merging blank lines around folds to them
  if getline(a:l) !~ '\S'
    return -1
  endif

  " We start folds for modules, classes, and every toplevel definition
  if getline(a:l) =~ '^\s*\%(\<val\>\|\<module\>\|\<class\>\|\<type\>\|\<method\>\|\<initializer\>\|\<inherit\>\|\<exception\>\|\<external\>\)'
    exe 'return ">' (indent(a:l)/s:i)+1 '"'
  endif

  " Toplevel let are detected thanks to the indentation
  if getline(a:l) =~ '^\s*let\>' && indent(a:l) == s:i+s:topindent(a:l)
    exe 'return ">' (indent(a:l)/s:i)+1 '"'
  endif

  " We close fold on end which are associated to struct, sig or object.
  " We use syntax information to do that.
  if getline(a:l) =~ '^\s*end\>' && synIDattr(synID(a:l, indent(a:l)+1, 0), "name") != "ocamlKeyword"
    return (indent(a:l)/s:i)+1
  endif

  " Folds end on ;;
  if getline(a:l) =~ '^\s*;;'
    exe 'return "<' (indent(a:l)/s:i)+1 '"'
  endif

  " Comments around folds aren't merged to them.
  if synIDattr(synID(a:l, indent(a:l)+1, 0), "name") == "ocamlComment"
    return -1
  endif

  return '='
endfunction

" Vim support for OCaml .annot files
"
" Last Change: 2007 Jul 17
" Maintainer:  Vincent Aravantinos <vincent.aravantinos@gmail.com>
" License:     public domain
"
" Originally inspired by 'ocaml-dtypes.vim' by Stefano Zacchiroli.
" The source code is quite radically different for we not use python anymore.
" However this plugin should have the exact same behaviour, that's why the
" following lines are the quite exact copy of Stefano's original plugin :
"
" <<
" Executing Ocaml_print_type(<mode>) function will display in the Vim bottom
" line(s) the type of an ocaml value getting it from the corresponding .annot
" file (if any).  If Vim is in visual mode, <mode> should be "visual" and the
" selected ocaml value correspond to the highlighted text, otherwise (<mode>
" can be anything else) it corresponds to the literal found at the current
" cursor position.
"
" Typing '<LocalLeader>t' (LocalLeader defaults to '\', see :h LocalLeader)
" will cause " Ocaml_print_type function to be invoked with the right 
" argument depending on the current mode (visual or not).
" >>
"
" If you find something not matching this behaviour, please signal it.
"
" Differences are:
"   - no need for python support
"     + plus : more portable
"     + minus: no more lazy parsing, it looks very fast however
"     
"   - ocamlbuild support, ie.
"     + the plugin finds the _build directory and looks for the 
"       corresponding file inside;
"     + if the user decides to change the name of the _build directory thanks
"       to the '-build-dir' option of ocamlbuild, the plugin will manage in
"       most cases to find it out (most cases = if the source file has a unique
"       name among your whole project);
"     + if ocamlbuild is not used, the usual behaviour holds; ie. the .annot
"       file should be in the same directory as the source file;
"     + for vim plugin programmers:
"       the variable 'b:_build_dir' contains the inferred path to the build 
"       directory, even if this one is not named '_build'.
"
" Bonus :
"   - latin1 accents are handled
"   - lists are handled, even on multiple lines, you don't need the visual mode
"     (the cursor must be on the first bracket)
"   - parenthesized expressions, arrays, and structures (ie. '(...)', '[|...|]',
"     and '{...}') are handled the same way

  " Copied from Stefano's original plugin :
  " <<
  "      .annot ocaml file representation
  "
  "      File format (copied verbatim from caml-types.el)
  "
  "      file ::= block *
  "      block ::= position <SP> position <LF> annotation *
  "      position ::= filename <SP> num <SP> num <SP> num
  "      annotation ::= keyword open-paren <LF> <SP> <SP> data <LF> close-paren
  "
  "      <SP> is a space character (ASCII 0x20)
  "      <LF> is a line-feed character (ASCII 0x0A)
  "      num is a sequence of decimal digits
  "      filename is a string with the lexical conventions of O'Caml
  "      open-paren is an open parenthesis (ASCII 0x28)
  "      close-paren is a closed parenthesis (ASCII 0x29)
  "      data is any sequence of characters where <LF> is always followed by
  "           at least two space characters.
  "
  "      - in each block, the two positions are respectively the start and the
  "        end of the range described by the block.
  "      - in a position, the filename is the name of the file, the first num
  "        is the line number, the second num is the offset of the beginning
  "        of the line, the third num is the offset of the position itself.
  "      - the char number within the line is the difference between the third
  "        and second nums.
  "
  "      For the moment, the only possible keyword is \"type\"."
  " >>


" 1. Finding the annotation file even if we use ocamlbuild

    " In:  two strings representing paths
    " Out: one string representing the common prefix between the two paths
  function! s:Find_common_path (p1,p2)
    let temp = a:p2
    while matchstr(a:p1,temp) == ''
      let temp = substitute(temp,'/[^/]*$','','')
    endwhile
    return temp
  endfun

    " After call:
    " - b:annot_file_path : 
    "                       path to the .annot file corresponding to the
    "                       source file (dealing with ocamlbuild stuff)
    " - b:_build_path: 
    "                       path to the build directory even if this one is
    "                       not named '_build'
  function! s:Locate_annotation()
    if !b:annotation_file_located

      silent exe 'cd' s:Fnameescape(expand('%:p:h'))

      let annot_file_name = s:Fnameescape(expand('%:r')).'.annot'

      " 1st case : the annot file is in the same directory as the buffer (no ocamlbuild)
      let b:annot_file_path = findfile(annot_file_name,'.')
      if b:annot_file_path != ''
        let b:annot_file_path = getcwd().'/'.b:annot_file_path
        let b:_build_path = ''
      else
        " 2nd case : the buffer and the _build directory are in the same directory
        "      ..
        "     /  \
        "    /    \
        " _build  .ml
        "
        let b:_build_path = finddir('_build','.')
        if b:_build_path != ''
          let b:_build_path = getcwd().'/'.b:_build_path
          let b:annot_file_path           = findfile(annot_file_name,'_build')
          if b:annot_file_path != ''
            let b:annot_file_path = getcwd().'/'.b:annot_file_path
          endif
        else
          " 3rd case : the _build directory is in a directory higher in the file hierarchy 
          "            (it can't be deeper by ocamlbuild requirements)
          "      ..
          "     /  \
          "    /    \
          " _build  ...
          "           \
          "            \
          "           .ml
          "
          let b:_build_path = finddir('_build',';')
          if b:_build_path != ''
            let project_path                = substitute(b:_build_path,'/_build$','','')
            let path_relative_to_project    = s:Fnameescape(substitute(expand('%:p:h'),project_path.'/','',''))
            let b:annot_file_path           = findfile(annot_file_name,project_path.'/_build/'.path_relative_to_project)
          else
            let b:annot_file_path = findfile(annot_file_name,'**')
            "4th case : what if the user decided to change the name of the _build directory ?
            "           -> we relax the constraints, it should work in most cases
            if b:annot_file_path != ''
              " 4a. we suppose the renamed _build directory is in the current directory
              let b:_build_path = matchstr(b:annot_file_path,'^[^/]*')
              if b:annot_file_path != ''
                let b:annot_file_path = getcwd().'/'.b:annot_file_path
                let b:_build_path     = getcwd().'/'.b:_build_path
              endif
            else
              " 4b. anarchy : the renamed _build directory may be higher in the hierarchy
              " this will work if the file for which we are looking annotations has a unique name in the whole project
              " if this is not the case, it may still work, but no warranty here
              let b:annot_file_path = findfile(annot_file_name,'**;')
              let project_path      = s:Find_common_path(b:annot_file_path,expand('%:p:h'))
              let b:_build_path       = matchstr(b:annot_file_path,project_path.'/[^/]*')
            endif
          endif
        endif
      endif

      if b:annot_file_path == ''
        throw 'E484: no annotation file found'
      endif

      silent exe 'cd' '-'

      let b:annotation_file_located = 1
    endif
  endfun

  " This in order to locate the .annot file only once
  let b:annotation_file_located = 0

" 2. Finding the type information in the annotation file
  
  " a. The annotation file is opened in vim as a buffer that
  " should be (almost) invisible to the user.

      " After call:
      " The current buffer is now the one containing the .annot file.
      " We manage to keep all this hidden to the user's eye.
    function! s:Enter_annotation_buffer()
      let s:current_pos = getpos('.')
      let s:current_hidden = &l:hidden
      set hidden
      let s:current_buf = bufname('%')
      if bufloaded(b:annot_file_path)
        silent exe 'keepj keepalt' 'buffer' s:Fnameescape(b:annot_file_path)
      else
        silent exe 'keepj keepalt' 'view' s:Fnameescape(b:annot_file_path)
      endif
    endfun

      " After call:
      "   The original buffer has been restored in the exact same state as before.
    function! s:Exit_annotation_buffer()
      silent exe 'keepj keepalt' 'buffer' s:Fnameescape(s:current_buf)
      let &l:hidden = s:current_hidden
      call setpos('.',s:current_pos)
    endfun

      " After call:
      "   The annot file is loaded and assigned to a buffer.
      "   This also handles the modification date of the .annot file, eg. after a 
      "   compilation.
    function! s:Load_annotation()
      if bufloaded(b:annot_file_path) && b:annot_file_last_mod < getftime(b:annot_file_path)
        call s:Enter_annotation_buffer()
        silent exe "bunload"
        call s:Exit_annotation_buffer()
      endif
      if !bufloaded(b:annot_file_path)
        call s:Enter_annotation_buffer()
        setlocal nobuflisted
        setlocal bufhidden=hide
        setlocal noswapfile
        setlocal buftype=nowrite
        call s:Exit_annotation_buffer()
        let b:annot_file_last_mod = getftime(b:annot_file_path)
      endif
    endfun
  
  "b. 'search' and 'match' work to find the type information
   
      "In:  - lin1,col1: postion of expression first char
      "     - lin2,col2: postion of expression last char
      "Out: - the pattern to be looked for to find the block
      " Must be called in the source buffer (use of line2byte)
    function! s:Block_pattern(lin1,lin2,col1,col2)
      let start_num1 = a:lin1
      let start_num2 = line2byte(a:lin1) - 1
      let start_num3 = start_num2 + a:col1
      let path       = '"\(\\"\|[^"]\)\+"'
      let start_pos  = path.' '.start_num1.' '.start_num2.' '.start_num3
      let end_num1   = a:lin2
      let end_num2   = line2byte(a:lin2) - 1
      let end_num3   = end_num2 + a:col2
      let end_pos    = path.' '.end_num1.' '.end_num2.' '.end_num3
      return '^'.start_pos.' '.end_pos."$"
      " rq: the '^' here is not totally correct regarding the annot file "grammar"
      " but currently the annotation file respects this, and it's a little bit faster with the '^';
      " can be removed safely.
    endfun

      "In: (the cursor position should be at the start of an annotation)
      "Out: the type information
      " Must be called in the annotation buffer (use of search)
    function! s:Match_data()
      " rq: idem as previously, in the following, the '^' at start of patterns is not necessary
      keepj while search('^type($','ce',line(".")) == 0
        keepj if search('^.\{-}($','e') == 0
          throw "no_annotation"
        endif
        keepj if searchpair('(','',')') == 0
          throw "malformed_annot_file"
        endif
      endwhile
      let begin = line(".") + 1
      keepj if searchpair('(','',')') == 0
        throw "malformed_annot_file"
      endif
      let end = line(".") - 1
      return join(getline(begin,end),"\n")
    endfun
        
      "In:  the pattern to look for in order to match the block
      "Out: the type information (calls s:Match_data)
      " Should be called in the annotation buffer
    function! s:Extract_type_data(block_pattern)
      call s:Enter_annotation_buffer()
      try
        if search(a:block_pattern,'e') == 0
          throw "no_annotation"
        endif
        call cursor(line(".") + 1,1)
        let annotation = s:Match_data()
      finally
        call s:Exit_annotation_buffer()
      endtry
      return annotation
    endfun
  
  "c. link this stuff with what the user wants
  " ie. get the expression selected/under the cursor
    
    let s:ocaml_word_char = '\w|[�-�]|'''

      "In:  the current mode (eg. "visual", "normal", etc.)
      "Out: the borders of the expression we are looking for the type
    function! s:Match_borders(mode)
      if a:mode == "visual"
        let cur = getpos(".")
        normal `<
        let col1 = col(".")
        let lin1 = line(".")
        normal `>
        let col2 = col(".")
        let lin2 = line(".")
        call cursor(cur[1],cur[2])
        return [lin1,lin2,col1-1,col2]
      else
        let cursor_line = line(".")
        let cursor_col  = col(".")
        let line = getline('.')
        if line[cursor_col-1:cursor_col] == '[|'
          let [lin2,col2] = searchpairpos('\[|','','|\]','n')
          return [cursor_line,lin2,cursor_col-1,col2+1]
        elseif     line[cursor_col-1] == '['
          let [lin2,col2] = searchpairpos('\[','','\]','n')
          return [cursor_line,lin2,cursor_col-1,col2]
        elseif line[cursor_col-1] == '('
          let [lin2,col2] = searchpairpos('(','',')','n')
          return [cursor_line,lin2,cursor_col-1,col2]
        elseif line[cursor_col-1] == '{'
          let [lin2,col2] = searchpairpos('{','','}','n')
          return [cursor_line,lin2,cursor_col-1,col2]
        else
          let [lin1,col1] = searchpos('\v%('.s:ocaml_word_char.'|\.)*','ncb')
          let [lin2,col2] = searchpos('\v%('.s:ocaml_word_char.'|\.)*','nce')
          if col1 == 0 || col2 == 0
            throw "no_expression"
          endif
          return [cursor_line,cursor_line,col1-1,col2]
        endif
      endif
    endfun

      "In:  the current mode (eg. "visual", "normal", etc.)
      "Out: the type information (calls s:Extract_type_data)
    function! s:Get_type(mode)
      let [lin1,lin2,col1,col2] = s:Match_borders(a:mode)
      return s:Extract_type_data(s:Block_pattern(lin1,lin2,col1,col2))
    endfun
  
  "d. main
      "In:         the current mode (eg. "visual", "normal", etc.)
      "After call: the type information is displayed
    if !exists("*Ocaml_get_type")
      function Ocaml_get_type(mode)
        call s:Locate_annotation()
        call s:Load_annotation()
        return s:Get_type(a:mode)
      endfun
    endif

    if !exists("*Ocaml_get_type_or_not")
      function Ocaml_get_type_or_not(mode)
        let t=reltime()
        try
          return Ocaml_get_type(a:mode)
        catch
          return ""
        endtry
      endfun
    endif

    if !exists("*Ocaml_print_type")
      function Ocaml_print_type(mode)
        if expand("%:e") == "mli"
          echohl ErrorMsg | echo "No annotations for interface (.mli) files" | echohl None
          return
        endif
        try
          echo Ocaml_get_type(a:mode)
        catch /E484:/
          echohl ErrorMsg | echo "No type annotations (.annot) file found" | echohl None
        catch /no_expression/
          echohl ErrorMsg | echo "No expression found under the cursor" | echohl None
        catch /no_annotation/
          echohl ErrorMsg | echo "No type annotation found for the given text" | echohl None
        catch /malformed_annot_file/
          echohl ErrorMsg | echo "Malformed .annot file" | echohl None
        endtry
      endfun
    endif

" Maps
  map  <silent> <LocalLeader>t :call Ocaml_print_type("normal")<CR>
  vmap <silent> <LocalLeader>t :<C-U>call Ocaml_print_type("visual")<CR>`<

let &cpoptions=s:cposet
unlet s:cposet

" vim:sw=2 fdm=indent
