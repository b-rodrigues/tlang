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
--# Vectorized if-else
--#
--# Vectorized conditional selection. Returns values from `true_val` or `false_val`
--# depending on whether `condition` is true or false.
--#
--# @name ifelse
--# @param condition :: Bool | Vector[Bool] The condition to check.
--# @param true_val :: Any | Vector[Any] Value to return if condition is true.
--# @param false_val :: Any | Vector[Any] Value to return if condition is false.
--# @param missing :: Any (Optional) Value to return if condition is NA. Defaults to NA.
--# @return :: Vector[Any] A vector of the same length as `condition`.
--# @example
--#   ifelse(x > 5, "High", "Low")
--#   ifelse(x % 2 == 0, x, 0)
--# @family boolean
--# @export
*)
let ifelse (args : Ast.value list) _env =
  match args with
  | [condition; true_val; false_val] ->
      let missing_val = VNA NAGeneric in (* Default missing *)
      
      (* 1. Determine Output Length from Condition *)
      let len = match condition with
        | VVector arr -> Array.length arr
        | VList l -> List.length l
        | VNDArray { shape; _ } -> Array.fold_left ( * ) 1 shape (* Flat size *)
        | _ -> 1
      in

      (* 2. Helper to get value at index i (with recycling) *)
      let get_at v i =
        match v with
        | VVector arr -> if Array.length arr = 0 then VNull else arr.(i mod Array.length arr)
        | VList l -> 
            let n = List.length l in
            if n = 0 then VNull else snd (List.nth l (i mod n))
        | VNDArray { data; _ } -> 
            let n = Array.length data in
            if n = 0 then VNull else VFloat data.(i mod n)
        | _ -> v (* Scalar repeats *)
      in
      
      (* 3. Determine Common Type for Output *)
      let sample_t = get_at true_val 0 in
      let sample_f = get_at false_val 0 in
      let sample_m = get_at missing_val 0 in
      let target_type = common_type [sample_t; sample_f; sample_m] in

      (* 4. Construct Result Vector *)
      let result = Array.init len (fun i ->
        let cond_v = get_at condition i in
        match cond_v with
        | VBool true -> cast_value target_type (get_at true_val i)
        | VBool false -> cast_value target_type (get_at false_val i)
        | VNA _ -> cast_value target_type (get_at missing_val i)
        | VNull -> cast_value target_type (get_at missing_val i) (* Treat null as missing in logic *)
        | _ -> VError { code = TypeError; message = "Condition must be logical"; context = [] }
      ) in
      
      (* 5. Check for errors in result *)
      (match Array.find_opt Error.is_error_value result with
      | Some err -> err
      | None -> VVector result)

  | [condition; true_val; false_val; missing_val] ->
        (* Explicit missing value support *)
        let len = match condition with
        | VVector arr -> Array.length arr
        | VList l -> List.length l
        | VNDArray { shape; _ } -> Array.fold_left ( * ) 1 shape
        | _ -> 1
        in
        let get_at v i =
          match v with
          | VVector arr -> if Array.length arr = 0 then VNull else arr.(i mod Array.length arr)
          | VList l -> let n = List.length l in if n = 0 then VNull else snd (List.nth l (i mod n))
          | VNDArray { data; _ } -> let n = Array.length data in if n = 0 then VNull else VFloat data.(i mod n)
          | _ -> v
        in
        let sample_t = get_at true_val 0 in
        let sample_f = get_at false_val 0 in
        let sample_m = get_at missing_val 0 in
        let target_type = common_type [sample_t; sample_f; sample_m] in
  
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
        | None -> VVector result)

  | _ -> Error.arity_error ~expected:3 ~received:(List.length args) (* Note: Variadic/Optional args handling is manual here *)


(* --- case_when --- *)

(* ... docs ... *)
let case_when eval_func args env =
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
  | [] -> VVector [||] (* Empty case_when *)
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
     
     (* 5. Construct Result *)
     let result = Array.init len (fun i ->
       (* Find first matching case *)
       let rec find_match cases =
         match cases with
         | [] -> 
             (* No match found, use default *)
             (* Handle recycling for default value *)
             let def = match default_val with 
               | VVector arr -> if Array.length arr = 0 then VNull else arr.(i mod Array.length arr)
               | _ -> default_val 
             in
             def
         | (cond, value) :: rest ->
             (* Get condition value at i *)
             let c = match cond with
               | VVector arr -> if Array.length arr = 0 then VNull else arr.(i mod Array.length arr)
               | VList l -> if List.length l = 0 then VNull else snd (List.nth l (i mod List.length l))
               | _ -> cond
             in
             match c with
             | VBool true ->
                 (* Get result value at i *)
                 let v = match value with
                   | VVector arr -> if Array.length arr = 0 then VNull else arr.(i mod Array.length arr)
                   | VList l -> if List.length l = 0 then VNull else snd (List.nth l (i mod List.length l))
                   | _ -> value
                 in
                 v
             | VBool false -> find_match rest
             | VNA _ -> find_match rest
             | VNull -> find_match rest
             | VError e -> VError e
             | other -> VError { code = TypeError; message = "Condition must be logical, got " ^ Utils.type_name other; context = [] }
       
       in
       let v = find_match evaluated_cases in
       match v with 
       | VError _ -> v 
       | _ -> cast_value target_type v
     ) in
     
      match Array.find_opt Error.is_error_value result with
      | Some err -> err
      | None -> VVector result
