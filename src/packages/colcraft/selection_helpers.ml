open Ast

let matcher_of name pred =
  VBuiltin {
    b_name = Some name;
    b_arity = 1;
    b_variadic = false;
    b_func = (fun args _env_ref ->
      match args with
      | [(_, VDataFrame df)] ->
          let names = Arrow_table.column_names df.arrow_table in
          VList (List.filter pred names |> List.map (fun n -> (None, VString n)))
      | [(_, VVector arr)] ->
          (* Also support matching against a vector of names if needed *)
          let names = Array.to_list arr |> List.filter_map (function VString s -> Some s | _ -> None) in
          VList (List.filter pred names |> List.map (fun n -> (None, VString n)))
      | _ -> Error.type_error (Printf.sprintf "Selection helper `%s` expects a DataFrame or Vector of names." name)
    )
  }

let starts_with_impl args env =
  match args with
  | [VString prefix] -> matcher_of "starts_with" (fun n -> String.starts_with ~prefix n)
  | _ when List.length args >= 2 -> String_ops.starts_with_impl args env
  | _ -> Error.arity_error_named "starts_with" ~expected:1 ~received:(List.length args)

let ends_with_impl args env =
  match args with
  | [VString suffix] -> matcher_of "ends_with" (fun n -> String.ends_with ~suffix n)
  | _ when List.length args >= 2 -> String_ops.ends_with_impl args env
  | _ -> Error.arity_error_named "ends_with" ~expected:1 ~received:(List.length args)

let contains_impl args env =
  match args with
  | [VString pattern] -> matcher_of "contains" (fun n -> 
      match Str.search_forward (Str.regexp_string pattern) n 0 with
      | _ -> true
      | exception Not_found -> false)
  | _ when List.length args >= 2 -> String_ops.contains_impl args env
  | _ -> Error.arity_error_named "contains" ~expected:1 ~received:(List.length args)

let everything_impl args _env =
  match args with
  | [] -> matcher_of "everything" (fun _ -> true)
  | _ -> Error.arity_error_named "everything" ~expected:0 ~received:(List.length args)

let register env =
  let env = Env.add "starts_with" (make_builtin ~name:"starts_with" ~variadic:true 1 starts_with_impl) env in
  let env = Env.add "ends_with" (make_builtin ~name:"ends_with" ~variadic:true 1 ends_with_impl) env in
  let env = Env.add "contains" (make_builtin ~name:"contains" ~variadic:true 1 contains_impl) env in
  let env = Env.add "everything" (make_builtin ~name:"everything" 0 everything_impl) env in
  env
