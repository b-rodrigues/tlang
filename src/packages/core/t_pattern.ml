open Ast

let register env =
  let make_pattern_stub name =
    make_builtin ~name ~variadic:true 0 (fun _args _env ->
      Error.type_error (Printf.sprintf
        "`%s` can only be used as a `pattern=` argument inside `node()`. See `expand_pipeline()` for dynamic branching."
        name))
  in
  let env = Env.add "map_pattern" (make_pattern_stub "map_pattern") env in
  let env = Env.add "cross_pattern" (make_pattern_stub "cross_pattern") env in
  let env = Env.add "slice_pattern" (make_pattern_stub "slice_pattern") env in
  let env = Env.add "head_pattern" (make_pattern_stub "head_pattern") env in
  let env = Env.add "tail_pattern" (make_pattern_stub "tail_pattern") env in
  let env = Env.add "sample_pattern" (make_pattern_stub "sample_pattern") env in
  env
