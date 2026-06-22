open Ast

(*
--# Inspect Pipeline Schema (Static)
--#
--# Returns a DataFrame outlining the static compile-time configuration of the pipeline.
--#
--# @name inspect_pipeline
--# @param p :: Pipeline The pipeline to inspect statically.
--# @return :: DataFrame A DataFrame with columns = node, runtime, serializer, dependencies, has_script.
--# @family pipeline
--# @export
*)
let register env =
  let extract_arg name pos default args =
    match List.assoc_opt (Some name) args with
    | Some v -> v
    | None ->
        let positionals = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
        if List.length positionals >= pos then List.nth positionals (pos - 1)
        else default
  in
  let inspect_fn named_args env =
    let p_val =
      match extract_arg "p" 1 (VNA NAGeneric) named_args with
      | VNA _ ->
          (* Fallback: scan environment for a pipeline *)
          (match Env.fold (fun _k val_v acc ->
             match val_v with
             | VPipeline _ as vp -> Some vp
             | _ -> acc
           ) env None with
           | Some vp -> vp
           | None -> VNA NAGeneric)
      | other -> other
    in
    match p_val with
    | VPipeline p ->
        let base_entries = List.map (fun (name, _) ->
          let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "Unknown" in
          let serializer_str = match List.assoc_opt name p.p_serializers with
            | Some expr -> Nix_unparse.unparse_expr expr | None -> "Unknown"
          in
          let deps_str = match List.assoc_opt name p.p_deps with Some ds -> String.concat ", " ds | None -> "" in
          let has_sc = match List.assoc_opt name p.p_scripts with Some (Some _) -> true | _ -> false in
          (name, runtime, serializer_str, deps_str, has_sc)
        ) p.p_nodes in
        let eval_dep_len_expr expr =
          try
            match Eval.eval_expr (ref env) expr with
            | VList items -> Some (List.length items)
            | VVector arr -> Some (Array.length arr)
            | VDataFrame df -> Some (Arrow_table.num_rows df.arrow_table)
            | _ -> None
          with _ -> None
        in
        let eval_dep_len dep =
          match List.assoc_opt dep p.p_exprs with
          | Some expr -> eval_dep_len_expr expr
          | None -> None
        in
        let branch_entries = List.concat_map (fun (name, pattern) ->
          let count_opt = match pattern with
            | PatternMap deps ->
                (match deps with [dep] -> eval_dep_len dep | _ -> None)
            | PatternCross subs ->
                let sub_lengths = List.filter_map (fun sub ->
                  match sub with
                  | PatternMap deps ->
                      let lens = List.filter_map eval_dep_len deps in
                      (match lens with [] -> None | _ -> Some (List.fold_left min max_int lens))
                  | _ -> None
                ) subs in
                if List.length sub_lengths <> List.length subs then None
                else Some (List.fold_left ( * ) 1 sub_lengths)
            | PatternSlice (_, indices) -> Some (List.length indices)
            | PatternHead (dep, n) | PatternTail (dep, n) | PatternSample (dep, n) ->
                (match eval_dep_len dep with Some len -> Some (min n len) | None -> None)
          in
          let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "Unknown" in
          let serializer_str = match List.assoc_opt name p.p_serializers with
            | Some expr -> Nix_unparse.unparse_expr expr | None -> "Unknown"
          in
          let deps_str = match List.assoc_opt name p.p_deps with Some ds -> String.concat ", " ds | None -> "" in
          match count_opt with
          | Some n when n > 0 ->
              List.init n (fun i ->
                let branch_name = name ^ "_branch_" ^ string_of_int (i + 1) in
                (branch_name, runtime, serializer_str, deps_str, false))
          | _ -> []
        ) p.p_patterns in
        let all_entries = base_entries @ branch_entries in
        let nrows = List.length all_entries in
        let entries_arr = Array.of_list all_entries in
        let arr_nodes = Array.init nrows (fun i -> let (name, _, _, _, _) = entries_arr.(i) in Some name) in
        let arr_runtimes = Array.init nrows (fun i -> let (_, r, _, _, _) = entries_arr.(i) in Some r) in
        let arr_serializers = Array.init nrows (fun i -> let (_, _, s, _, _) = entries_arr.(i) in Some s) in
        let arr_dependencies = Array.init nrows (fun i -> let (_, _, _, d, _) = entries_arr.(i) in Some d) in
        let arr_has_script = Array.init nrows (fun i -> let (_, _, _, _, h) = entries_arr.(i) in Some h) in
        let columns = [
          ("node", Arrow_table.StringColumn arr_nodes);
          ("runtime", Arrow_table.StringColumn arr_runtimes);
          ("serializer", Arrow_table.StringColumn arr_serializers);
          ("dependencies", Arrow_table.StringColumn arr_dependencies);
          ("has_script", Arrow_table.BoolColumn arr_has_script);
        ] in
        let arrow_table = Arrow_table.create columns nrows in
        VDataFrame { arrow_table; group_keys = [] }
    | other ->
        Error.type_error (Printf.sprintf "inspect_pipeline: expected a Pipeline, but got %s." (Utils.type_name other))
  in
  let env = Env.add "inspect_pipeline" (make_builtin_named ~name:"inspect_pipeline" ~variadic:true 1 inspect_fn) env in

  (*
  --# Inspect Pipeline Logs (Dynamic)
  --#
  --# Reads the latest (or specified) build log and returns a DataFrame showing the pipeline status.
  --#
  --# @name inspect_log
  --# @param which_log :: String (Optional) A regex pattern to match a specific build log filename.
  --# @return :: DataFrame A DataFrame with columns = derivation, build_success, path, output.
  --# @family pipeline
  --# @export
  *)
  let inspect_log_fn named_args _env =
    let first_arg = extract_arg "p" 1 (VNA NAGeneric) named_args in
    let (_p_opt, which_log_arg) =
      match first_arg with
      | VPipeline p -> (Some p, extract_arg "which_log" 2 (VNA NAGeneric) named_args)
      | _other -> (None, extract_arg "which_log" 1 (VNA NAGeneric) named_args)
    in
    match which_log_arg with
    | VNA _ ->
        Builder.inspect_pipeline ()
    | VString s ->
        Builder.inspect_pipeline ~which_log:s ()
    | other ->
        Error.type_error
          (Printf.sprintf "inspect_log: expected String or NA for argument 'which_log', but got %s."
             (Utils.type_name other))
  in
  let env = Env.add "inspect_log" (make_builtin_named ~name:"inspect_log" ~variadic:true 0 inspect_log_fn) env in

  (*
  --# List Pipeline Logs
  --#
  --# Lists all available build logs in the `_pipeline/` directory.
  --#
  --# @name list_logs
  --# @return :: DataFrame A DataFrame of build log files with their modification times and sizes.
  --# @family pipeline
  --# @export
  *)
  let env = Env.add "list_logs" (make_builtin ~name:"list_logs" 0 (fun _args _env -> Builder.list_logs ())) env in
  
  (*
  --# Read Node Build Log
  --#
  --# Fetches the Nix build log for a specific node from the last build attempt.
  --#
  --# @name read_log
  --# @param node_name :: String The name of the node to inspect.
  --# @return :: String The build log content.
  --# @family pipeline
  --# @export
  *)
  let env = Env.add "read_log" (make_builtin ~name:"read_log" 1 (fun args _env -> 
    match args with
    | [VString s] | [VSymbol s] -> Builder.read_node_log s
    | other :: _ ->
        Error.type_error
          (Printf.sprintf "read_log: expected a String or Symbol node name, but got %s."
             (Utils.type_name other))
    | _ ->
        Error.type_error "read_log: expected a String or Symbol node name."
  )) env in
  env
