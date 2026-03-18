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
" Adjust g:t_completion_timeout_ms for slower/faster machines (default: 200).
setlocal omnifunc=<SID>TComplete

if !exists('g:t_completion_timeout_ms')
  let g:t_completion_timeout_ms = 200
endif

function! s:TComplete(findstart, base)
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
  if col('.') <= 1
    return []
  endif
  let line = getline('.')
  let prefix = line[0 : col('.') - 2]
  if prefix ==# ''
    return []
  endif

  " Record terminal scrollback length before sending the query so we only
  " scan newly appended output, avoiding stale matches and O(scrollback) rescans.
  let baseline = term_getline(term, '.', '$')
  let baseline_len = len(baseline)

  " Send :complete query and poll for the response markers
  call term_sendkeys(term, ":complete " . prefix . "\n")

  let elapsed = 0
  let step = 50
  let completions = []
  while elapsed < g:t_completion_timeout_ms
    exe 'sleep ' . step . 'm'
    let elapsed += step
    " Only read lines appended after the baseline
    let all_lines = term_getline(term, '.', '$')
    let new_lines = all_lines[baseline_len :]
    let found_end = 0
    let collecting = 0
    let completions = []
    for l in new_lines
      if l =~# ':BEGIN_COMPLETIONS:'
        let collecting = 1
        continue
      endif
      if l =~# ':END_COMPLETIONS:'
        let found_end = 1
        break
      endif
      if collecting && l !=# ''
        call add(completions, l)
      endif
    endfor
    if found_end
      break
    endif
  endwhile

  " Filter to matches starting with the base prefix
  return filter(completions, 'v:val =~# "^" . a:base')
