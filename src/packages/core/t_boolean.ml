(* src/packages/core/t_boolean.ml *)
(* Vectorized boolean operations for T language *)

open Ast

(* --- Helper Functions --- *)

(** Helper: Determine the common type for a list of values.
    Promotes Int -> Float.
    Returns the type name ("Int", "Float", "String", etc.) *)
let common_type values =
  let types = List.map Utils.type_name values in
  let distinctive_types = List.sort_uniq String.compare types in
  if List.mem "String" distinctive_types then "String"
  else if List.mem "Float" distinctive_types then "Float"
  else if List.mem "Int" distinctive_types then "Int"
  else if List.mem "Bool" distinctive_types then "Bool"
  else match distinctive_types with
       | [] -> "Null" (* Should not happen for non-empty lists *)
       | [t] -> t
       | _ -> "Generic" (* Fallback *)

(** Helper: Cast a value to a target type.
    Note: This is a loose cast for `ifelse`/`case_when`. *)
let cast_value target_type v =
  match target_type, v with
  | _, VNA _ -> v (* Preserve NA *)
  | _, VNull -> v
  | "String", VString _ -> v
  | "String", _ -> VString (Utils.value_to_raw_string v)
  | "Float", VFloat _ -> v
  | "Float", VInt i -> VFloat (float_of_int i)
  | "Float", VBool b -> VFloat (if b then 1.0 else 0.0)
  | "Int", VInt _ -> v
  | "Int", VBool b -> VInt (if b then 1 else 0)
  | "Bool", VBool _ -> v
  | "Bool", VInt i -> VBool (i <> 0)
  | "Bool", VFloat f -> VBool (f <> 0.0)
  | _ -> v (* Return as is if cast not supported or unnecessary *)

(* --- ifelse --- *)

(*
--# Vectorized If-Else
--#
--# Evaluates a condition and returns values from `true_val` or `false_val` depending on the condition.
--# Supports missing value handling via the `missing` argument.
--#
--# @name ifelse
--# @param condition :: Vector[Bool] The logical condition to evaluate.
--# @param true_val :: Any Expected return value when condition is true.
--# @param false_val :: Any Expected return value when condition is false.
--# @param missing :: Any (Optional) Value to return when condition is NA.
--# @param out_type :: String (Optional) Explicit output type casting.
--# @return :: Vector A vector of the resulting values.
--# @example
--#   ifelse([true, false, NA], "Yes", "No", missing: "Unknown")
--# @family core
--# @export
*)
let normalize_type_name = function
  | "int" | "integer" | "Int" | "Integer" -> Some "Int"
  | "float" | "double" | "numeric" | "Float" | "Double" | "Numeric" -> Some "Float"
  | "string" | "str" | "character" | "String" | "Str" | "Character" -> Some "String"
  | "bool" | "boolean" | "logical" | "Bool" | "Boolean" | "Logical" -> Some "Bool"
  | _ -> None


let ifelse (named_args : (string option * Ast.value) list) _env =
  let positional_args = List.filter_map (function None, v -> Some v | _ -> None) named_args in
  let named_value name =
    List.find_opt (fun (n, _) -> n = Some name) named_args |> Option.map snd
  in
  let unexpected_named =
    List.filter_map (function
      | Some "missing", _ | Some "out_type", _ | None, _ -> None
      | Some name, _ -> Some name
    ) named_args
  in
  match unexpected_named with
  | name :: _ -> Error.type_error (Printf.sprintf "ifelse: unexpected named argument `%s`." name)
  | [] ->
      (match positional_args with
      | condition :: true_val :: false_val :: extras ->
          let parsed_extras =
            match extras with
            | [] -> Ok (None, None)
            | [missing] -> Ok (Some missing, None)
            | [missing; out_type] -> Ok (Some missing, Some out_type)
            | _ ->
                let received = List.length positional_args in
                Error (Error.type_error (Printf.sprintf "ifelse: expected at most 5 positional args, got %d" received))
          in
          (match parsed_extras with
          | Error err -> err
          | Ok (positional_missing, positional_out_type) ->
              (match positional_out_type, named_value "out_type" with
              | Some _, Some _ -> Error.type_error "ifelse: `out_type` was provided both positionally and by name."
              | _ ->
                  (match positional_missing, named_value "missing" with
                  | Some _, Some _ -> Error.type_error "ifelse: `missing` was provided both positionally and by name."
                  | _ ->
                      let missing_val =
                        match positional_missing with
                        | Some v -> v
                        | None -> (match named_value "missing" with Some v -> v | None -> VNA NAGeneric)
                      in
                      let out_type_arg = match positional_out_type with Some v -> Some v | None -> named_value "out_type" in

                      let len = match condition with
                        | VVector arr -> Array.length arr
                        | VList l -> List.length l
                        | VNDArray { shape; _ } -> Array.fold_left ( * ) 1 shape
                        | _ -> 1
                      in

                      let get_at v i =
                        match v with
                        | VVector arr ->
                            let n = Array.length arr in
                            if n = 0 then VNull else arr.(i mod n)
                        | VList l ->
                            let arr = Array.of_list (List.map snd l) in
                            let n = Array.length arr in
                            if n = 0 then VNull else arr.(i mod n)
                        | VNDArray { data; _ } ->
                            let n = Array.length data in
                            if n = 0 then VNull else VFloat data.(i mod n)
                        | _ -> v
                      in

                      let inferred_target_type =
                        let sample_t = get_at true_val 0 in
                        let sample_f = get_at false_val 0 in
                        let sample_m = get_at missing_val 0 in
                        common_type [sample_t; sample_f; sample_m]
                      in
                      let target_type_or_err =
                        match out_type_arg with
                        | None -> Ok inferred_target_type
                        | Some (VString s) ->
                            (match normalize_type_name s with
                            | Some t -> Ok t
                            | None -> Error (Error.type_error "ifelse: `out_type` must be one of Int, Float, String, or Bool."))
                        | Some _ -> Error (Error.type_error "ifelse: `out_type` must be a string.")
                      in
                      match target_type_or_err with
                      | Error err -> err
                      | Ok target_type ->
                          let result = Array.init len (fun i ->
                            let cond_v = get_at condition i in
                            match cond_v with
                            | VBool true -> cast_value target_type (get_at true_val i)
                            | VBool false -> cast_value target_type (get_at false_val i)
                            | VNA _ -> cast_value target_type (get_at missing_val i)
                            | VNull -> cast_value target_type (get_at missing_val i)
                            | _ -> VError { code = TypeError; message = "Condition must be logical"; context = [] }
                          ) in
                          (match Array.find_opt Error.is_error_value result with
                          | Some err -> err
                          | None when len = 1 -> result.(0)
                          | None -> VVector result))))
      | _ -> Error.arity_error_named "ifelse" ~expected:3 ~received:(List.length positional_args))


(*
--# Vectorized Case-When
--#
--# Evaluates multiple conditions and returns the corresponding value for the first true condition.
--# Similar to SQL's CASE WHEN. Conditions are provided as formulas `condition ~ value`.
--#
--# @name case_when
--# @param .default :: Any (Optional) Default value if no condition is met.
--# @param ... :: Formula Conditions and their corresponding return values.
--# @return :: Vector A vector of the resulting values.
--# @family core
--# @export
*)
let casewhen eval_func args env =
  (* 1. Parse Arguments: Separate formulas and options (.default) *)
  let rec parse_args formulas default_val inputs =
    match inputs with
    | [] -> (List.rev formulas, default_val)
    | (Some ".default", v) :: rest -> parse_args formulas v rest
    | (None, VFormula f) :: rest -> parse_args (f :: formulas) default_val rest
    | (None, VError e) :: _ -> ([], VError e) (* Propagate error *)
    (* Handle case where .default is passed positionally at the end? No, consistent with R usually named or implicit *)
    | (None, v) :: _ -> 
         (* Could be a Formula that didn't evaluate to VFormula? No, parser handles ~ -> VFormula *)
         (* Or maybe a type error *)
         ([], Error.make_error TypeError (Printf.sprintf "Expected formula (cond ~ value), got %s" (Utils.type_name v)))
    | _ :: rest -> parse_args formulas default_val rest (* Skip unknown named args for now *)

  in
  
  let (formulas, default_val) = parse_args [] (VNA NAGeneric) args in
  
  match formulas with
  | [] -> VVector [||] (* Empty casewhen *)
  | _ ->
     (* 2. Evaluate Formulas in the Environment *)
     (* We need to evaluate LHS (cond) and RHS (value) for each formula.
        Note: The arguments to case_when are already evaluated by eval_call before reaching here,
        BUT VFormula captures the raw expressions. Wait... eval_binop for Formula returns VFormula 
        with raw_lhs and raw_rhs. So we need to evaluate them here. 
        Wait, standard function call evaluates args. usage: case_when(x > 1 ~ "A").
        x > 1 evaluates to a Vector[Bool]. "A" evaluates to "A".
        Wait, `~` is a binary operator. 
        If `x > 1` evaluates to `[true, false]`, then `[true, false] ~ "A"` ? 
        Does `~` evaluate its operands?
        In `eval.ml`, `match op with Formula -> ... raw_lhs = left; raw_rhs = right`.
        It does NOT evaluate operands. It captures expressions.
        So we need to evaluate them here in the `env`.
     *)
     
     let eval_formula f =
       let cond = eval_func env f.raw_lhs in
       let value = eval_func env f.raw_rhs in
       (cond, value)
     in
     
     let evaluated_cases = List.map eval_formula formulas in
     
     (* 3. Determine Output Length *)
     (* Length is determined by the max length of any condition *)
     let len = List.fold_left (fun max_len (cond, _) ->
       let l = match cond with
         | VVector arr -> Array.length arr
         | VList l -> List.length l
         | VNDArray { shape; _ } -> Array.fold_left ( * ) 1 shape
         | _ -> 1
       in
       max l max_len
     ) 1 evaluated_cases in
     
     (* 4. Determine Common Type *)
     let potential_values = (List.map snd evaluated_cases) @ [default_val] in
     (* We need to peek into vectors if they are vectors *)
     let get_rep_value v = 
       match v with 
       | VVector arr -> if Array.length arr > 0 then arr.(0) else VNull
       | VList l -> if List.length l > 0 then snd (List.nth l 0) else VNull
       | _ -> v 
     in
     let rep_values = List.map get_rep_value potential_values in
     let target_type = common_type rep_values in
     
     (* Pre-convert VLists to arrays for efficient indexing *)
     let make_indexable v =
       match v with
       | VList l -> 
           let arr = Array.of_list (List.map snd l) in
           let n = Array.length arr in
           (`Array arr, n)
       | VVector arr -> (`Vector arr, Array.length arr)
       | _ -> (`Scalar v, 1)
     in
     
     let indexed_cases = List.map (fun (cond, value) ->
       (make_indexable cond, make_indexable value)
     ) evaluated_cases in
     
     let indexed_default = make_indexable default_val in
     
     (* 5. Construct Result *)
     let result = Array.init len (fun i ->
       (* Find first matching case *)
       let rec find_match cases =
         match cases with
         | [] -> 
             (* No match found, use default *)
             (* Handle recycling for default value *)
             let def = match indexed_default with
               | (`Array arr, n) -> if n = 0 then VNull else arr.(i mod n)
               | (`Vector arr, n) -> if n = 0 then VNull else arr.(i mod n)
               | (`Scalar v, _) -> v
             in
             def
         | ((cond_idx, cond_len), (value_idx, value_len)) :: rest ->
             (* Get condition value at i *)
             let c = match cond_idx with
               | `Array arr -> if cond_len = 0 then VNull else arr.(i mod cond_len)
               | `Vector arr -> if cond_len = 0 then VNull else arr.(i mod cond_len)
               | `Scalar v -> v
             in
             match c with
             | VBool true ->
                 (* Get result value at i *)
                 let v = match value_idx with
                   | `Array arr -> if value_len = 0 then VNull else arr.(i mod value_len)
                   | `Vector arr -> if value_len = 0 then VNull else arr.(i mod value_len)
                   | `Scalar v -> v
                 in
                 v
             | VBool false -> find_match rest
             | VNA _ -> find_match rest
             | VNull -> find_match rest
             | VError e -> VError e
             | other -> VError { code = TypeError; message = "Condition must be logical, got " ^ Utils.type_name other; context = [] }
       
       in
       let v = find_match indexed_cases in
       match v with 
       | VError _ -> v 
       | _ -> cast_value target_type v
     ) in
     
      match Array.find_opt Error.is_error_value result with
      | Some err -> err
      | None -> VVector result
