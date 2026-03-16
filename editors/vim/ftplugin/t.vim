" editors/vim/ftplugin/t.vim
if exists("b:did_ftplugin")
  finish
endif
let b:did_ftplugin = 1

" Command to start REPL
command! -buffer TRepl terminal t

" Maps to send code to terminal (requires Vim with terminal support or Neovim)
function! s:SendToT(text)
  let term_bufs = filter(range(1, bufnr('$')), 'getbufvar(v:val, "&buftype") == "terminal"')
  if empty(term_bufs)
    terminal t
    let term_bufs = [bufnr('$')]
  endif
  call term_sendkeys(term_bufs[0], a:text . "\n")
endfunction

vnoremap <buffer> <leader>r :<C-u>call <SID>SendToT(getline("'<", "'>"))<CR>
nnoremap <buffer> <leader>r :call <SID>SendToT(getline('.'))<CR>
nnoremap <buffer> <leader>b :call <SID>SendToT(join(getline(1, '$'), "\n"))<CR>
