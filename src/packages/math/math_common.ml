open Ast

let named_flag_true flag named_args =
  List.exists
    (fun (name, value) ->
      name = Some flag
      &&
      match value with
      | VBool true -> true
      | _ -> false)
    named_args

let get_bool_flag name default named_args =
  match List.find_opt (fun (n, _) -> n = Some name) named_args with
  | Some (_, VBool b) -> Ok b
  | Some (_, v) ->
      Error
        (Error.type_error
           (Printf.sprintf "Flag `%s` must be Bool, but received %s." name
              (Utils.type_name v)))
  | None -> Ok default

(** Strip selected named arguments and return the remaining positional values
    in their original order. *)
let positional_args_without names named_args =
  List.filter
    (fun (name, _) ->
      match name with
      | Some n -> not (List.mem n names)
      | None -> true)
    named_args
  |> List.map snd

(** Shared numeric-unary mapper for math builtins.
    - [fname] is the user-facing function name for error messages.
    - [expects] describes the accepted input shape in arity/type errors.
    - [na_ignore] preserves NA inputs/slots instead of failing on them.
    - [f] is the numeric transform applied to concrete float values.
    Returns either a transformed scalar/vector/ndarray or a structured error. *)
let map_numeric_unary ~fname ?(expects = "numeric input") ?(na_ignore = false) f =
  function
  | [VInt n] -> VFloat (f (float_of_int n))
  | [VFloat x] -> VFloat (f x)
  | [VVector arr] ->
      let out = Array.make (Array.length arr) (VNA NAGeneric) in
      let err = ref None in
      Array.iteri
        (fun i v ->
          if !err = None then
            match v with
            | VInt n -> out.(i) <- VFloat (f (float_of_int n))
            | VFloat x -> out.(i) <- VFloat (f x)
            | VNA na_t when na_ignore -> out.(i) <- VNA na_t
            | VNA _ -> err := Some (Error.na_value_error fname)
            | _ ->
                err :=
                  Some
                    (Error.type_error
                       (Printf.sprintf "Function `%s` requires numeric values."
                          fname)))
        arr;
      (match !err with Some e -> e | None -> VVector out)
  | [VNDArray arr] -> VNDArray { shape = arr.shape; data = Array.map f arr.data }
  | [VNA na_t] when na_ignore -> VNA na_t
  | [VNA _] -> Error.na_value_error fname
  | [_] -> Error.type_error (Printf.sprintf "Function `%s` expects %s." fname expects)
  | args -> Error.arity_error_named fname 1 (List.length args)

let map_numeric_unary_named ~fname ?expects f named_args =
  match get_bool_flag "na_ignore" false named_args with
  | Error e -> e
  | Ok na_ignore ->
      let args = positional_args_without [ "na_ignore" ] named_args in
      map_numeric_unary ~fname ?expects ~na_ignore f args
