(* src/packages/stats/compare.ml *)
open Ast

(** compare(models) — aligns and compares multiple models in a wide DataFrame. *)
(*
--# Compare Models
--#
--# Align multiple model coefficient tables into a single wide DataFrame for comparison.
--#
--# @name compare
--# @param ... :: Variadic Models or a List of models to compare.
--# @return :: DataFrame A wide DataFrame with aligned terms and suffixed columns.
--# @example
--#   m1 = lm(mpg ~ wt, data = mtcars)
--#   m2 = lm(mpg ~ wt + hp, data = mtcars)
--#   compare(m1, m2)
--# @family stats
--# @export
*)
let register env =
  Env.add "compare"
    (make_builtin ~name:"compare" ~variadic:true 0 (fun args _env ->
      let models = match args with
        | [VList items] -> List.map snd items
        | _ -> args
      in
      let rec collect_models acc = function
        | [] -> Ok (List.rev acc)
        | VDict p :: rest -> collect_models (p :: acc) rest
        | VError e :: _ -> Error (VError e)
        | _ :: rest -> collect_models acc rest
      in
      
      let parsed_models = collect_models [] models in
      
      match parsed_models with
      | Error e -> e
      | Ok valid_models ->
        if List.length valid_models = 0 then
          Error.type_error "Function `compare` expects one or more model Dicts."
        else
          try
          (* 1. Extract tidy DFs and names *)
          let model_infos = List.mapi (fun i m ->
            let name = match List.assoc_opt "name" m with
              | Some (VString s) -> s
              | _ -> string_of_int (i + 1)
            in
            let tidy = match List.assoc_opt "_tidy_df" m with
              | Some (VDataFrame df) -> df
              | _ -> raise (Failure (Printf.sprintf "Model %s has no tidy coefficient table." name))
            in
            (name, tidy)
          ) valid_models in
          
          (* 2. Collect union of terms, preserving order *)
          let seen_terms = Hashtbl.create 16 in
          let all_terms = ref [] in
          List.iter (fun (_, tidy) ->
            let terms = Arrow_table.get_string_column tidy.arrow_table "term" in
            Array.iter (function 
              | Some t -> if not (Hashtbl.mem seen_terms t) then begin
                  Hashtbl.add seen_terms t ();
                  all_terms := t :: !all_terms
                end
              | None -> ()) terms
          ) model_infos;
          let union_terms = Array.of_list (List.rev !all_terms) in
          let n_union = Array.length union_terms in
          
          (* 3. build columns for each model *)
          let build_model_columns (name, tidy) =
            let model_terms = Arrow_table.get_string_column tidy.arrow_table "term" in
            let estimates   = Arrow_table.get_float_column  tidy.arrow_table "estimate" in
            let std_errors  = Arrow_table.get_float_column  tidy.arrow_table "std_error" in
            let statistics  = Arrow_table.get_float_column  tidy.arrow_table "statistic" in
            let p_values    = Arrow_table.get_float_column  tidy.arrow_table "p_value" in
            
            let term_map = Hashtbl.create (Array.length model_terms) in
            Array.iteri (fun i t_opt ->
              match t_opt with
              | Some t -> Hashtbl.add term_map t i
              | None -> ()
            ) model_terms;
            
            let align_col src_col =
              Array.init n_union (fun i ->
                let t = union_terms.(i) in
                match Hashtbl.find_opt term_map t with
                | Some idx -> src_col.(idx)
                | None -> None
              )
            in
            
            [
              ("estimate_" ^ name,  Arrow_table.FloatColumn (align_col estimates));
              ("std_error_" ^ name, Arrow_table.FloatColumn (align_col std_errors));
              ("statistic_" ^ name, Arrow_table.FloatColumn (align_col statistics));
              ("p_value_"   ^ name, Arrow_table.FloatColumn (align_col p_values));
            ]
          in
          
          let term_col = ("term", Arrow_table.StringColumn (Array.map (fun t -> Some t) union_terms)) in
          let other_cols = List.concat (List.map build_model_columns model_infos) in
          let table = Arrow_table.create (term_col :: other_cols) n_union in
          VDataFrame { arrow_table = table; group_keys = [] }
          
        with Failure msg -> Error.type_error msg
    )) env
