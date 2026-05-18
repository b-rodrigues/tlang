open Ast

(** Extract a boolean flag from named arguments list.
    
    @param name The name of the flag to find.
    @param default The fallback value if not found.
    @param named_args The list of arguments.
    @return [Ok bool] or a type error if the flag is present but not boolean. *)
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
    in their original order.
    
    @param names The list of named argument keys to filter out.
    @param named_args The original list of named arguments.
    @return A list of remaining positional/unnamed argument values. *)
let positional_args_without names named_args =
  List.filter
    (fun (name, _) ->
      match name with
      | Some n -> not (List.mem n names)
      | None -> true)
    named_args
  |> List.map snd

(** Safely extract an optional named argument.
    
    Returns [None] if the argument is omitted or holds an NA value.
    
    @param name The argument key.
    @param named_args The arguments list.
    @return [Some value] if present and not NA, otherwise [None]. *)
let optional_named_arg name named_args =
  match List.find_opt (fun (n, _) -> n = Some name) named_args with
  | Some (_, VNA _) | None -> None
  | Some (_, v) -> Some v

(** Shared numeric-unary mapper for math builtins.
    
    Applies a float transformation recursively to inputs. Supports scalars, vectors, 
    and NDArrays. Optionally handles NA imputation or propagation.
    
    @param fname The function name for error context.
    @param expects Input type expectation for type check errors.
    @param na_ignore If [true], NA elements are ignored/passed through; otherwise, they raise NA errors.
    @param f The mathematical transform to execute.
    @param args The parameter values list.
    @return A scalar VFloat, VVector of floats, VNDArray of floats, or a structured error value. *)
let map_numeric_unary ~fname ?(expects = "numeric input") ?(na_ignore = false) f =
  function
  | [VInt n] -> VFloat (f (float_of_int n))
  | [VFloat x] -> VFloat (f x)
  | [VVector arr] ->
      let out = Array.make (Array.length arr) (VNA NAGeneric) in
      let type_err = ref None in
      let na_count = ref 0 in
      Array.iteri
        (fun i v ->
          match v with
          | VInt n -> if !type_err = None && (!na_count = 0 || na_ignore) then out.(i) <- VFloat (f (float_of_int n))
          | VFloat x -> if !type_err = None && (!na_count = 0 || na_ignore) then out.(i) <- VFloat (f x)
          | VNA na_t ->
              na_count := !na_count + 1;
              if na_ignore then out.(i) <- VNA na_t
          | _ ->
              if !type_err = None then
                type_err := Some (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." fname))
        ) arr;
      (match !type_err with
       | Some e -> e
       | None when !na_count > 0 && not na_ignore -> Error.na_value_error ~na_count:!na_count fname
       | None -> VVector out)
  | [VNDArray arr] -> VNDArray { shape = arr.shape; data = Array.map f arr.data }
  | [VNA na_t] when na_ignore -> VNA na_t
  | [VNA _] -> Error.na_value_error fname
  | [_] -> Error.type_error (Printf.sprintf "Function `%s` expects %s." fname expects)
  | args -> Error.arity_error_named fname 1 (List.length args)

(** Helper to map numeric-unary operations containing potential named flags like `na_ignore`.
    
    @param fname The function name for error context.
    @param expects Input shape expectations.
    @param f The mathematical transform.
    @param named_args The list of arguments.
    @return A T-Lang value containing the result or error. *)
let map_numeric_unary_named ~fname ?expects f named_args =
  match get_bool_flag "na_ignore" false named_args with
  | Error e -> e
  | Ok na_ignore ->
      let args = positional_args_without [ "na_ignore" ] named_args in
      map_numeric_unary ~fname ?expects ~na_ignore f args
