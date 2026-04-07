(* src/packages/stats/t_native_scoring.ml *)
open Ast

let onnx_string_list_of_value value =
  match value with
  | VList items ->
      let rec collect acc = function
        | [] -> Ok (List.rev acc)
        | (_, VString s) :: rest -> collect (s :: acc) rest
        | _ :: _ ->
            Error (Error.type_error "Function `predict` expects ONNX model `features` to be a list of strings.")
      in
      collect [] items
  | _ ->
      Error (Error.type_error "Function `predict` expects ONNX model `features` to be a list of strings.")

let onnx_feature_columns pairs numeric_cols =
  match List.assoc_opt "features" pairs with
  | Some feature_value -> onnx_string_list_of_value feature_value
  | None ->
      (match List.assoc_opt "metadata" pairs with
       | Some (VDict meta_pairs) ->
           (match List.assoc_opt "feature_names" meta_pairs with
            | Some (VString s) -> Ok (String.split_on_char ',' s |> List.map String.trim)
            | _ -> Ok numeric_cols)
       | _ -> Ok numeric_cols)

type tree_predicate =
  | PredTrue
  | PredFalse
  | PredSimple of { field: string; op: string; value: string option }
  | PredSimpleSet of { field: string; op: string; values: string list }
  | PredCompound of { op: string; predicates: tree_predicate list }

type tree_score =
  | ScoreFloat of float
  | ScoreString of string

type tree_node = {
  predicate: tree_predicate;
  score: tree_score option;
  children: tree_node list;
}

type tree_model = {
  function_name: string;
  root: tree_node;
}

type forest_model = {
  function_name: string;
  method_: string;
  trees: tree_model list;
}

type boosted_ensemble = {
  function_name: string;
  target: string option;
  classes: string list;
  models: (float * float * forest_model) list; (* rescale_constant, rescale_factor, forest *)
}

type row_value =
  | RowFloat of float
  | RowString of string
  | RowMissing

let value_list = function
  | VList items -> List.map (fun (_, v) -> v) items
  | _ -> []

let get_string_field name pairs =
  match List.assoc_opt name pairs with
  | Some (VString s) -> Ok s
  | Some _ -> Error (Printf.sprintf "Expected `%s` to be a String in tree model." name)
  | None -> Error (Printf.sprintf "Missing `%s` in tree model." name)

let get_optional_string_field name pairs =
  match List.assoc_opt name pairs with
  | Some (VString s) -> Some s
  | _ -> None

let get_dict_field name pairs =
  match List.assoc_opt name pairs with
  | Some (VDict d) -> Ok d
  | Some _ -> Error (Printf.sprintf "Expected `%s` to be a Dict in tree model." name)
  | None -> Error (Printf.sprintf "Missing `%s` in tree model." name)

let rec predicate_of_value v =
  match v with
  | VDict pairs ->
      (match get_string_field "type" pairs with
       | Error msg -> Error msg
       | Ok "true" -> Ok PredTrue
       | Ok "false" -> Ok PredFalse
       | Ok "simple" ->
           (match get_string_field "field" pairs, get_string_field "op" pairs with
            | Ok field, Ok op ->
                let value = get_optional_string_field "value" pairs in
                Ok (PredSimple { field; op; value })
            | Error msg, _ | _, Error msg -> Error msg)
       | Ok "set" ->
           (match get_string_field "field" pairs, get_string_field "op" pairs with
            | Ok field, Ok op ->
                let values =
                  match List.assoc_opt "values" pairs with
                  | Some vlist ->
                      value_list vlist
                      |> List.filter_map (function VString s -> Some s | _ -> None)
                  | None -> []
                in
                Ok (PredSimpleSet { field; op; values })
            | Error msg, _ | _, Error msg -> Error msg)
       | Ok "compound" ->
           (match get_string_field "op" pairs with
            | Error msg -> Error msg
            | Ok op ->
              (match List.assoc_opt "predicates" pairs with
               | None -> Error "Missing `predicates` in compound predicate."
               | Some vlist ->
                let preds = value_list vlist in
                let rec collect acc = function
                  | [] -> Ok (List.rev acc)
                  | p :: rest ->
                      (match predicate_of_value p with
                       | Ok pred -> collect (pred :: acc) rest
                       | Error msg -> Error msg)
                in
                (match collect [] preds with
                 | Ok preds -> Ok (PredCompound { op; predicates = preds })
                 | Error msg -> Error msg)))
       | Ok other -> Error (Printf.sprintf "Unknown predicate type `%s`." other))
  | _ -> Error "Expected predicate to be a Dict."

let rec node_of_value v =
  match v with
  | VDict pairs ->
      (match List.assoc_opt "predicate" pairs, List.assoc_opt "children" pairs with
       | Some pred_val, Some children_val ->
           (match predicate_of_value pred_val with
            | Error msg -> Error msg
            | Ok predicate ->
                let score =
                  match List.assoc_opt "score" pairs with
                  | Some (VFloat f) -> Some (ScoreFloat f)
                  | Some (VString s) -> Some (ScoreString s)
                  | _ -> None
                in
                let children = value_list children_val in
                let rec collect acc = function
                  | [] -> Ok (List.rev acc)
                  | c :: rest ->
                      (match node_of_value c with
                       | Ok node -> collect (node :: acc) rest
                       | Error msg -> Error msg)
                in
                (match collect [] children with
                 | Ok children -> Ok { predicate; score; children }
                 | Error msg -> Error msg))
       | None, _ -> Error "Missing `predicate` in tree node."
       | _, None -> Error "Missing `children` in tree node.")
  | _ -> Error "Expected tree node to be a Dict."

let tree_of_value v =
  match v with
  | VDict pairs ->
      (match get_string_field "function_name" pairs, get_dict_field "root" pairs with
       | Ok function_name, Ok root_dict ->
           (match node_of_value (VDict root_dict) with
            | Ok root -> Ok { function_name; root }
            | Error msg -> Error msg)
       | Error msg, _ | _, Error msg -> Error msg)
  | _ -> Error "Expected tree model to be a Dict."

let forest_of_value v =
  match v with
  | VDict pairs ->
      (match get_string_field "function_name" pairs, get_string_field "method" pairs with
       | Ok function_name, Ok method_ ->
           (match List.assoc_opt "trees" pairs with
            | Some vlist ->
                let trees_val = value_list vlist in
                let rec collect acc = function
                  | [] -> Ok (List.rev acc)
                  | t :: rest ->
                      (match tree_of_value t with
                       | Ok tree -> collect (tree :: acc) rest
                       | Error msg -> Error msg)
                in
                (match collect [] trees_val with
                 | Ok trees -> Ok { function_name; method_; trees }
                 | Error msg -> Error msg)
            | None -> Error "Missing `trees` in forest model.")
       | Error msg, _ | _, Error msg -> Error msg)
  | _ -> Error "Expected forest model to be a Dict."

let boosted_model_of_value v =
  match v with
  | VDict pairs ->
      (match get_string_field "function_name" pairs with
       | Ok function_name ->
           let target = get_optional_string_field "target" pairs in
           let classes =
             match List.assoc_opt "classes" pairs with
             | Some vlist ->
                 value_list vlist
                 |> List.filter_map (function VString s -> Some s | _ -> None)
             | None -> []
           in
           (match List.assoc_opt "models" pairs with
            | Some vlist ->
                let models_val = value_list vlist in
                let rec collect acc = function
                  | [] -> Ok (List.rev acc)
                  | VDict p :: rest ->
                      (match List.assoc_opt "rescale_constant" p,
                              List.assoc_opt "rescale_factor" p,
                              List.assoc_opt "forest" p with
                       | Some (VFloat rc), Some (VFloat rf), Some f_val ->
                           (match forest_of_value f_val with
                            | Ok forest -> collect ((rc, rf, forest) :: acc) rest
                            | Error msg -> Error msg)
                       | _ -> Error "Invalid boosted ensemble model segment.")
                  | _ :: rest -> collect acc rest
                in
                (match collect [] models_val with
                 | Ok models -> Ok { function_name; target; classes; models }
                 | Error msg -> Error msg)
            | None -> Error "Missing `models` in boosted ensemble model.")
       | Error msg -> Error msg)
  | _ -> Error "Expected boosted ensemble model to be a Dict."

let resolve_field_eval df field =
  match Arrow_table.column_type df.arrow_table field with
  | Some (Arrow_table.ArrowFloat64 | Arrow_table.ArrowInt64) ->
      let col = Arrow_table.get_float_column df.arrow_table field in
      Ok (fun i -> match col.(i) with Some f -> RowFloat f | None -> RowMissing)
  | Some Arrow_table.ArrowString ->
      let col = Arrow_table.get_string_column df.arrow_table field in
      Ok (fun i -> match col.(i) with Some s -> RowString s | None -> RowMissing)
  | Some Arrow_table.ArrowBoolean ->
      let col = Arrow_table.get_bool_column df.arrow_table field in
      Ok (fun i -> match col.(i) with Some b -> RowFloat (if b then 1.0 else 0.0) | None -> RowMissing)
  | None -> Error (Printf.sprintf "Field `%s` not found in DataFrame." field)
  | _ -> Error (Printf.sprintf "Field `%s` has unsupported type for native scoring." field)

let rec node_fields node =
  let here =
    match node.predicate with
    | PredSimple { field; _ } | PredSimpleSet { field; _ } -> [field]
    | PredCompound { predicates; _ } ->
        let rec collect_p = function
          | [] -> []
          | PredSimple { field; _ } :: rest | PredSimpleSet { field; _ } :: rest -> field :: collect_p rest
          | PredCompound { predicates; _ } :: rest -> collect_p predicates @ collect_p rest
          | _ :: rest -> collect_p rest
        in
        collect_p predicates
    | _ -> []
  in
  here @ List.concat (List.map node_fields node.children)

let unique_fields fields =
  let rec loop acc = function
    | [] -> List.rev acc
    | f :: rest -> if List.mem f acc then loop acc rest else loop (f :: acc) rest
  in
  loop [] fields

let eval_predicate evals pred row_idx =
  match pred with
  | PredTrue -> Some true
  | PredFalse -> Some false
  | PredSimple { field; op; value } ->
      (match Hashtbl.find evals field row_idx with
       | RowFloat f ->
           (match value with
            | Some v ->
                let f_val = float_of_string v in
                (match op with
                 | "lessThan" -> Some (f < f_val)
                 | "lessOrEqual" -> Some (f <= f_val)
                 | "greaterThan" -> Some (f > f_val)
                 | "greaterOrEqual" -> Some (f >= f_val)
                 | "equal" -> Some (f = f_val)
                 | "notEqual" -> Some (f <> f_val)
                 | _ -> None)
            | None -> None)
       | RowString s ->
           (match value with
            | Some v ->
                (match op with
                 | "equal" -> Some (s = v)
                 | "notEqual" -> Some (s <> v)
                 | _ -> None)
            | None -> None)
       | RowMissing -> None)
  | PredSimpleSet { field; op; values } ->
      (match Hashtbl.find evals field row_idx with
       | RowString s ->
           let found = List.mem s values in
           (match op with
            | "isIn" -> Some found
            | "isNotIn" -> Some (not found)
            | _ -> None)
       | RowFloat f ->
           let s = string_of_float f in
           let found = List.mem s values in
           (match op with
            | "isIn" -> Some found
            | "isNotIn" -> Some (not found)
            | _ -> None)
       | RowMissing -> None)
  | PredCompound { op; predicates } ->
      let results = List.filter_map (fun p -> eval_predicate evals p row_idx) predicates in
      match op with
      | "and" ->
          if List.length results < List.length predicates then Some false
          else Some (List.for_all (fun x -> x) results)
      | "or" -> Some (List.exists (fun x -> x) results)
      | "xor" ->
          let count = List.length (List.filter (fun x -> x) results) in
          Some (count mod 2 = 1)
      | "surrogate" ->
          (match results with
           | r :: _ -> Some r
           | [] -> None)
      | _ -> None

let rec eval_tree evals node row_idx =
  match node.children with
  | [] -> node.score
  | children ->
      let rec pick = function
        | [] -> None
        | child :: rest ->
            (match eval_predicate evals child.predicate row_idx with
             | Some true ->
                 (match eval_tree evals child row_idx with
                  | Some s -> Some s
                  | None -> child.score)
             | Some false | None -> pick rest)
      in
      (match pick children with
       | Some s -> Some s
       | None -> node.score)

let predict_tree_model df model =
  match model with
  | VDict pairs ->
      (match List.assoc_opt "tree" pairs with
       | Some tree_val ->
           (match tree_of_value tree_val with
            | Error msg -> Error.make_error TypeError msg
            | Ok tree ->
                let fields = unique_fields (node_fields tree.root) in
                let evals = Hashtbl.create (List.length fields) in
                let rec add_evals = function
                  | [] -> Ok ()
                  | field :: rest ->
                      (match resolve_field_eval df field with
                       | Ok eval -> Hashtbl.add evals field eval; add_evals rest
                       | Error msg -> Error msg)
                in
                (match add_evals fields with
                 | Error msg -> Error.make_error KeyError msg
                 | Ok () ->
                     let nrows = Arrow_table.num_rows df.arrow_table in
                     let out = Array.make nrows (VNA NAGeneric) in
                     for i = 0 to nrows - 1 do
                       match tree.function_name with
                       | "regression" ->
                           (match eval_tree evals tree.root i with
                            | Some (ScoreFloat f) -> out.(i) <- VFloat f
                            | Some (ScoreString s) ->
                                (match float_of_string_opt s with
                                 | Some f -> out.(i) <- VFloat f
                                 | None -> out.(i) <- VNA NAFloat)
                            | None -> out.(i) <- VNA NAFloat)
                       | _ ->
                           (match eval_tree evals tree.root i with
                            | Some (ScoreString s) -> out.(i) <- VString s
                            | Some (ScoreFloat f) -> out.(i) <- VString (string_of_float f)
                            | None -> out.(i) <- VNA NAString)
                     done;
                     VVector out))
       | None -> Error.type_error "Function `predict` expects a tree model with a `tree` field.")
  | _ -> Error.type_error "Function `predict` expects a tree model Dict."

let predict_forest_model df model =
  match model with
  | VDict pairs ->
      (match List.assoc_opt "forest" pairs with
       | Some forest_val ->
           (match forest_of_value forest_val with
            | Error msg -> Error.make_error TypeError msg
            | Ok forest ->
                let fields =
                  forest.trees
                  |> List.map (fun t -> node_fields t.root)
                  |> List.concat
                  |> unique_fields
                in
                let evals = Hashtbl.create (List.length fields) in
                let rec add_evals = function
                  | [] -> Ok ()
                  | field :: rest ->
                      (match resolve_field_eval df field with
                       | Ok eval -> Hashtbl.add evals field eval; add_evals rest
                       | Error msg -> Error msg)
                in
                (match add_evals fields with
                 | Error msg -> Error.make_error KeyError msg
                 | Ok () ->
                     let nrows = Arrow_table.num_rows df.arrow_table in
                     let out = Array.make nrows (VNA NAGeneric) in
                     for i = 0 to nrows - 1 do
                       let scores =
                         forest.trees
                         |> List.filter_map (fun t -> eval_tree evals t.root i)
                       in
                       if scores = [] then
                         (match forest.function_name with
                          | "regression" -> out.(i) <- VNA NAFloat
                          | _ -> out.(i) <- VNA NAString)
                       else
                         match forest.function_name with
                         | "regression" ->
                             let floats =
                               scores
                               |> List.filter_map (function ScoreFloat f -> Some f | _ -> None)
                             in
                             if floats = [] then out.(i) <- VNA NAFloat
                             else
                               let sum = List.fold_left ( +. ) 0.0 floats in
                               out.(i) <- VFloat (sum /. float_of_int (List.length floats))
                         | _ ->
                             let counts = Hashtbl.create 8 in
                             List.iter (function
                               | ScoreString s ->
                                   let prev = match Hashtbl.find_opt counts s with Some v -> v | None -> 0 in
                                   Hashtbl.replace counts s (prev + 1)
                               | ScoreFloat f ->
                                   let key = string_of_float f in
                                   let prev = match Hashtbl.find_opt counts key with Some v -> v | None -> 0 in
                                   Hashtbl.replace counts key (prev + 1)
                             ) scores;
                             let best =
                               Hashtbl.fold (fun k v acc ->
                                 match acc with
                                 | None -> Some (k, v)
                                 | Some (_, best_v) when v > best_v -> Some (k, v)
                                 | Some _ -> acc
                               ) counts None
                             in
                             (match best with
                              | Some (label, _) -> out.(i) <- VString label
                              | None -> out.(i) <- VNA NAString)
                     done;
                     VVector out))
       | None -> Error.type_error "Function `predict` expects a forest model with a `forest` field.")
  | _ -> Error.type_error "Function `predict` expects a forest model Dict."

let score_to_class classes scores =
  let class_val idx =
    match List.nth_opt classes idx with
    | Some label ->
        (match int_of_string_opt label with
         | Some i -> VInt i
         | None ->
             (match float_of_string_opt label with
              | Some f -> VFloat f
              | None -> VString label))
    | None -> VNA NAString
  in
  if List.length classes = 2 then
    match scores with
    | s :: _ ->
        let prob = 1.0 /. (1.0 +. exp(-. s)) in
        if prob >= 0.5 then class_val 1 else class_val 0
    | [] -> VNA NAString
  else
    let rec loop best_idx best_val i = function
      | [] -> best_idx
      | v :: rest ->
          if v > best_val then loop i v (i + 1) rest
          else loop best_idx best_val (i + 1) rest
    in
    match scores with
    | [] -> VNA NAString
    | s :: rest ->
        let max_idx = loop 0 s 1 rest in
        class_val max_idx

let predict_boosted_model df model =
  match model with
  | VDict pairs ->
      (match List.assoc_opt "boosted_model" pairs with
       | Some ensemble_val ->
           (match boosted_model_of_value ensemble_val with
            | Error msg -> Error.make_error TypeError msg
            | Ok ensemble ->
                let fields =
                  ensemble.models
                  |> List.map (fun (_, _, forest) ->
                    forest.trees |> List.map (fun t -> node_fields t.root) |> List.concat)
                  |> List.concat
                  |> unique_fields
                in
                let evals = Hashtbl.create (List.length fields) in
                let rec add_evals = function
                  | [] -> Ok ()
                  | field :: rest ->
                      (match resolve_field_eval df field with
                       | Ok eval -> Hashtbl.add evals field eval; add_evals rest
                       | Error msg -> Error msg)
                in
                (match add_evals fields with
                 | Error msg -> Error.make_error KeyError msg
                 | Ok () ->
                     let nrows = Arrow_table.num_rows df.arrow_table in
                     let out = Array.make nrows (VNA NAGeneric) in
                     for i = 0 to nrows - 1 do
                       let scores =
                         ensemble.models
                         |> List.map (fun (rc, rf, forest) ->
                           let forest_scores =
                             forest.trees
                             |> List.filter_map (fun t -> eval_tree evals t.root i)
                             |> List.filter_map (function ScoreFloat f -> Some f | _ -> None)
                           in
                           let sum = List.fold_left ( +. ) 0.0 forest_scores in
                           rc +. rf *. sum
                         )
                       in
                       match ensemble.function_name with
                       | "classification" ->
                           if List.length ensemble.classes = 2 then
                             (match scores with
                              | s :: _ ->
                                  let prob = 1.0 /. (1.0 +. exp(-. s)) in
                                  out.(i) <- VFloat prob
                              | [] -> out.(i) <- VNA NAFloat)
                           else if List.length scores = 1 then
                             out.(i) <- score_to_class ensemble.classes scores
                           else
                             out.(i) <- score_to_class ensemble.classes scores
                       | _ ->
                           (match scores with
                            | s :: _ when not (Float.is_nan s) -> out.(i) <- VFloat s
                            | _ -> out.(i) <- VNA NAFloat)
                     done;
                     VVector out))
       | None -> Error.type_error "Function `predict` expects a boosted model (xgboost/lightgbm) with `boosted_model`.")
  | _ -> Error.type_error "Function `predict` expects a boosted model Dict."

let predict_onnx_model df model =
  match model with
   | VDict pairs ->
       (match List.assoc_opt "path" pairs with
        | Some (VString path) ->
            (try
              let session = Onnx_ffi.get_session path in
              let colnames = Arrow_table.column_names df.arrow_table in
              let numeric_cols =
                List.filter (fun n ->
                  match Arrow_table.column_type df.arrow_table n with
                  | Some (ArrowInt64 | ArrowFloat64) -> true
                  | _ -> false) colnames
              in
              let nrows = Arrow_table.num_rows df.arrow_table in
              (match onnx_feature_columns pairs numeric_cols with
                 | Error err -> err
                 | Ok feature_cols ->
                      let ncols = List.length feature_cols in
                      if ncols = 0 then
                        Error.make_error ValueError "DataFrame has no numeric columns for ONNX prediction."
                      else
                        let invalid_col =
                          List.find_opt
                            (fun cname ->
                              match Arrow_table.column_type df.arrow_table cname with
                              | Some (ArrowInt64 | ArrowFloat64) -> false
                              | _ -> true)
                            feature_cols
                        in
                        match invalid_col with
                        | Some cname ->
                            Error.make_error ValueError
                              ("Column `" ^ cname ^ "` required for ONNX prediction is missing or not numeric.")
                        | None ->
                            let expected_width = Onnx_ffi.session_input_width session in
                            if expected_width > 0 && expected_width <> ncols then
                              Error.make_error ValueError
                                (Printf.sprintf
                                   "Function `predict` expected %d numeric feature columns for this ONNX model but received %d."
                                   expected_width ncols)
                            else
                              let data = Array.make_matrix nrows ncols 0.0 in
                              let has_missing = ref false in
                              List.iteri (fun j cname ->
                                if not !has_missing then begin
                                  let col = Arrow_table.get_float_column df.arrow_table cname in
                                  for i = 0 to nrows - 1 do
                                    if not !has_missing then
                                      match col.(i) with
                                      | Some f -> data.(i).(j) <- f
                                      | None -> has_missing := true
                                  done
                                end
                              ) feature_cols;
                              if !has_missing then
                                Error.make_error ValueError
                                  "DataFrame contains missing values in numeric columns required for ONNX prediction."
                              else
                                let res = Onnx_ffi.session_run_multi session 
                                    [| (match List.assoc_opt "inputs" pairs with
                                        | Some (VList ((_, VString name) :: _)) -> name
                                        | _ -> "input") |]
                                    [| data |] 
                                    [| (match List.assoc_opt "outputs" pairs with
                                        | Some (VList ((_, VString name) :: _)) -> name
                                        | _ -> "output") |] in
                                VVector (Array.map (fun f -> VFloat f) res.(0)))
            with Failure msg -> Error.make_error RuntimeError msg)
        | _ -> Error.type_error "Function `predict` expects an ONNX model with a `path` field.")
   | _ -> Error.type_error "Function `predict` expects an ONNX model Dict."

let predict_linear_model df pairs =
  let coeffs = match List.assoc_opt "coefficients" pairs with
    | Some (VDict c) -> c
    | _ -> []
  in
  let intercept =
    match List.assoc_opt "intercept" pairs with
    | Some (VFloat f) -> f
    | Some (VDict [("(Intercept)", VFloat f)]) -> f
    | _ -> 0.0
  in
  let nrows = Arrow_table.num_rows df.arrow_table in
  let out = Array.make nrows (VFloat intercept) in
  List.iter (fun (name, val_) ->
    if name <> "(Intercept)" then
      match val_ with
      | VFloat weight ->
          (match Arrow_table.get_float_column df.arrow_table name with
           | col ->
               for i = 0 to nrows - 1 do
                 match col.(i) with
                 | Some f -> out.(i) <- VFloat ((match out.(i) with VFloat v -> v | _ -> 0.0) +. (f *. weight))
                 | None -> out.(i) <- VNA NAFloat
               done)
      | _ -> ()
  ) coeffs;
  VVector out
