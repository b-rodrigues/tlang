open Ast

(*
--# Generate a sequence of integers
--#
--# Creates a list of integers from start to end, optionally with a step size.
--#
--# @name seq
--# @param start :: Int (Optional) Starting value. Defaults to 1.
--# @param end :: Int (Optional) Ending value. Defaults to start if by is provided.
--# @param by :: Int (Optional) Step size. Defaults to 1 or -1.
--# @return :: List[Int] List of integers.
--# @example
--#   seq(5)
--#   seq(1, 5)
--#   seq(start = 1, end = 10, by = 2)
--#   -- Returns = [1, 3, 5, 7, 9]
--# @family core
--# @export
*)
let register env =
  Env.add "seq"
    (Ast.make_builtin_named ~name:"seq" ~variadic:true 0 (fun named_args _env ->
      let get_named k = List.find_map (fun (nk, v) -> if nk = Some k then Some v else None) named_args in
      let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) named_args in

      let as_int v = 
        match v with 
        | Ast.VInt i -> i 
        | _ -> raise (Failure "Function `seq` arguments must be Int.")
      in

      try
        let start_int, end_int_opt =
          match get_named "start", get_named "end", positional with
          | Some s, Some e, _ -> (as_int s, Some (as_int e))
          | Some s, None, _ -> (as_int s, None)
          | None, Some e, [s] -> (as_int s, Some (as_int e))
          | None, Some e, [] -> (1, Some (as_int e))
          | None, None, [e] -> (1, Some (as_int e))
          | None, None, s::e::_ -> (as_int s, Some (as_int e))
          | None, None, [] -> (1, None)
          | _, _, _ -> (1, None)
        in
        
        let by_int_opt = 
          match get_named "by" with
          | Some b -> Some (as_int b)
          | None -> match positional with
                    | _::_::b::_ -> Some (as_int b)
                    | _ -> None
        in
        
        let by_int = match by_int_opt with
          | Some b -> b
          | None -> match end_int_opt with Some e -> if e < start_int then -1 else 1 | None -> 1
        in
        
        let end_int = match end_int_opt with
          | Some e -> e
          | None -> start_int
        in

        if by_int = 0 then Error.make_error Ast.ValueError "Function `seq` cannot have `by` = 0." else
        let steps = 
          if (end_int > start_int && by_int < 0) || (end_int < start_int && by_int > 0) then 0
          else ((end_int - start_int) / by_int) + 1
        in
        let items = List.init (max 0 steps) (fun i -> (None, Ast.VInt (start_int + i * by_int))) in
        Ast.VList items
      with Failure msg -> Error.type_error msg
    ))
    env
