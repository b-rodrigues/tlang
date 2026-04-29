(shell_command_block
  (shell_content) @injection.content
  (#set! injection.language "bash"))

; Named-argument injections — rn(command = <{ ... }>)
(call_expression
  function: (identifier) @_callee
  arguments: (argument_list
    (named_argument
      value: (raw_code_block (raw_code_content) @injection.content)))
  (#eq? @_callee "rn")
  (#set! injection.language "r"))

(call_expression
  function: (identifier) @_callee
  arguments: (argument_list
    (named_argument
      value: (raw_code_block (raw_code_content) @injection.content)))
  (#eq? @_callee "pyn")
  (#set! injection.language "python"))

(call_expression
  function: (identifier) @_callee
  arguments: (argument_list
    (named_argument
      value: (raw_code_block (raw_code_content) @injection.content)))
  (#eq? @_callee "shn")
  (#set! injection.language "bash"))

; Positional-argument injections — rn(<{ ... }>)
(call_expression
  function: (identifier) @_callee
  arguments: (argument_list
    (raw_code_block (raw_code_content) @injection.content))
  (#eq? @_callee "rn")
  (#set! injection.language "r"))

(call_expression
  function: (identifier) @_callee
  arguments: (argument_list
    (raw_code_block (raw_code_content) @injection.content))
  (#eq? @_callee "pyn")
  (#set! injection.language "python"))

(call_expression
  function: (identifier) @_callee
  arguments: (argument_list
    (raw_code_block (raw_code_content) @injection.content))
  (#eq? @_callee "shn")
  (#set! injection.language "bash"))

