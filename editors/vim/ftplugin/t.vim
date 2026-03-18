" editors/vim/ftplugin/t.vim
if exists("b:did_ftplugin")
  finish
endif
let b:did_ftplugin = 1

" Command to start REPL
command! -buffer TRepl terminal t repl

" Maps to send code to terminal (requires Vim with terminal support or Neovim)
function! s:SendToT(text)
  let term_bufs = filter(range(1, bufnr('$')), 'getbufvar(v:val, "&buftype") == "terminal"')
  if empty(term_bufs)
    terminal t repl
    let term_bufs = [bufnr('$')]
  endif
  call term_sendkeys(term_bufs[0], a:text . "\n")
endfunction

vnoremap <buffer> <leader>r :<C-u>call <SID>SendToT(getline("'<", "'>"))<CR>
nnoremap <buffer> <leader>r :call <SID>SendToT(getline('.'))<CR>
nnoremap <buffer> <leader>b :call <SID>SendToT(join(getline(1, '$'), "\n"))<CR>

" Omni-completion via the T REPL's :complete command.
" Uses the first running T terminal buffer to query completions.
setlocal omnifunc=TComplete

function! TComplete(findstart, base)
  if a:findstart
    " Locate the start of the word being completed
    let line = getline('.')
    let col = col('.') - 1
    while col > 0 && line[col - 1] =~# '[a-zA-Z0-9_]'
      let col -= 1
    endwhile
    return col
  endif

  " Find a running T terminal buffer
  let term_bufs = filter(range(1, bufnr('$')), 'getbufvar(v:val, "&buftype") == "terminal"')
  if empty(term_bufs)
    return []
  endif
  let term = term_bufs[0]

  " Build prefix: everything on the current line up to the cursor
  let line = getline('.')
  let prefix = line[0 : col('.') - 2]
  if prefix ==# ''
    return []
  endif

  " Send :complete query and capture the result
  call term_sendkeys(term, ":complete " . prefix . "\n")
  " Give the REPL time to respond
  sleep 100m

  let output = term_getline(term, 1, '$')
  let collecting = 0
  let completions = []
  for l in output
    if l =~# ':BEGIN_COMPLETIONS:'
      let collecting = 1
      continue
    endif
    if l =~# ':END_COMPLETIONS:'
      break
    endif
    if collecting && l !=# ''
      call add(completions, l)
    endif
  endfor

  " Filter to matches starting with the base prefix
  return filter(completions, 'v:val =~# "^" . a:base')
