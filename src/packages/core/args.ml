open Ast

(*
--# Get function arguments and their types
--#
--# Returns a dictionary where keys are parameter names and values are their types.
--# Supports both user-defined lambdas and builtin functions.
--#
--# @name args
--# @param fn :: Function The function to inspect.
--# @return :: Dict A dictionary of name: Type.
--# @example
--#   args(sqrt)
--#   -- Returns: {x: "Number | Vector | NDArray"}
--#
--#   f = \(x: Int, y: Float -> Int) x + y
--#   args(f)
--#   -- Returns: {x: "Int", y: "Float"}
--# @family core
--# @export
*)
let register env =
  Env.add "args"
    (make_builtin ~name:"args" 1 (fun args _env ->
      match args with
      | [VLambda l] ->
          let pairs = List.map2 (fun name typ_opt ->
            let typ_str = match typ_opt with
              | Some t -> Utils.typ_to_string t
              | None -> "Any"
            in
            (name, VString typ_str)
          ) l.params l.param_types in
          VDict pairs
      | [VBuiltin b] ->
          (match b.b_name with
          | Some name ->
              (match Tdoc_registry.lookup name with
              | Some entry ->
                  let pairs = List.map (fun (p : Tdoc_types.param_doc) ->
                    let t = match p.type_info with Some t -> t | None -> "Any" in
                    (p.name, VString t)
                  ) entry.params in
                  VDict pairs
              | None ->
                  (* Fallback if not documented: generate generic names *)
                  let pairs = List.init b.b_arity (fun i ->
                      ("arg" ^ string_of_int (i + 1), VString "Any")
                  ) in
                  VDict pairs)
          | None ->
              (* Builtin without name - generic fallback *)
              let pairs = List.init b.b_arity (fun i ->
                  ("arg" ^ string_of_int (i + 1), VString "Any")
              ) in
              VDict pairs)
      | [v] -> Error.type_error (Printf.sprintf "args() expects a Function, got %s" (Utils.type_name v))
      | _ -> Error.arity_error_named "args" ~expected:1 ~received:(List.length args)
    ))
    env
