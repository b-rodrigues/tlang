" Vim syntax file for the T Programming Language
" Language: T

if exists("b:current_syntax")
  finish
endif

" Keywords
syn keyword tKeyword if else import function pipeline intent true false null NA in

" Built-in Functions & Common Verbs
syn keyword tBuiltin read_csv filter mutate summarize select arrange group_by node rn pyn build_pipeline print mean sqrt predict t_read_pmml 
syn keyword tBuiltin glimpse nrow ncol colnames clean_colnames head tail join split slice arrange group_by

" Comments
syn match tComment "--.*$"

" Numbers
syn match tNumber "\d\+\(\.\d*\)\?"

" Strings
syn region tString start='"' end='"' skip='\\"'
syn region tString start="'" end="'" skip="\\'"

" NSE Column References ($foo)
syn match tColumn "\$[a-zA-Z_][a-zA-Z0-9_]*"

" Backtick identifiers
syn region tBacktick start="`" end="`"

" Foreign Language Blocks (e.g., R/Python/Shell)
syn region tForeignBlock start="<{" end="}>" contains=tForeignContent
syn match tForeignContent ".*" contained
syn match tForeignDelimiter "<{" contained
syn match tForeignDelimiter "}>" contained

syn region tShellBlock start="?<{" end="}>" contains=tShellContent
syn match tShellContent ".*" contained
syn match tShellDelimiter "?<{" contained
syn match tShellDelimiter "}>" contained

" Operators
syn match tOperator "|>"
syn match tOperator "?|>"
syn match tOperator ":="
syn match tOperator "->"
syn match tOperator "!!"
syn match tOperator "!!!"
syn match tOperator "=="
syn match tOperator "!="
syn match tOperator ">="
syn match tOperator "<="
syn match tOperator "\.\(+\|-\|*\|\/\|==\|!=\|<\|>\|<=\|>=\|&\||\|%\)"

" Highlighting Links
hi def link tKeyword Keyword
hi def link tBuiltin Function
hi def link tComment Comment
hi def link tNumber Number
hi def link tString String
hi def link tColumn Identifier
hi def link tBacktick Identifier
hi def link tForeignBlock Special
hi def link tForeignDelimiter Special
hi def link tShellBlock Special
hi def link tShellDelimiter Special
hi def link tOperator Operator

let b:current_syntax = "t"
