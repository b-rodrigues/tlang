open Ast

(*
--# List Pipeline Nodes
--#
--# Returns a list of node names in the pipeline.
--#
--# @name pipeline_nodes
--# @param p :: Pipeline The pipeline.
--# @return :: List[String] The node names.
--# @family pipeline
--# @seealso pipeline_node, pipeline_deps
--# @export
*)

let rec eval_dep_len env exprs patterns dep_name =
  let from_expr =
    match List.assoc_opt dep_name exprs with
    | Some expr ->
        (try
           match Eval.eval_expr (ref env) expr with
           | VList items -> Some (List.length items)
           | VVector arr -> Some (Array.length arr)
           | VDataFrame df -> Some (Arrow_table.num_rows df.arrow_table)
           | _ -> None
         with _ -> None)
    | None -> None
  in
  match from_expr with
  | Some _ -> from_expr
  | None ->
      (match List.assoc_opt dep_name patterns with
       | Some pattern ->
           (match pattern with
            | PatternMap deps ->
                (match deps with
                 | _ :: _ ->
                     let lens = List.filter_map (eval_dep_len env exprs patterns) deps in
                     (match lens with [] -> None | _ -> Some (List.fold_left min max_int lens))
                 | _ -> None)
            | PatternCross subs ->
                let sub_lengths = List.filter_map (fun sub ->
                  match sub with
                  | PatternMap sub_deps ->
                      let lens = List.filter_map (eval_dep_len env exprs patterns) sub_deps in
                      (match lens with [] -> None | _ -> Some (List.fold_left min max_int lens))
                  | _ -> None
                ) subs in
                if List.length sub_lengths <> List.length subs then None
                else Some (List.fold_left ( * ) 1 sub_lengths)
            | PatternSlice (_, indices) -> Some (List.length indices)
            | PatternHead (d, n) | PatternTail (d, n) | PatternSample (d, n) ->
                (match eval_dep_len env exprs patterns d with
                 | Some len -> Some (min n len)
                 | None -> None))
       | None -> None)

let compute_branch_names env p =
  List.concat_map (fun (name, pattern) ->
    let count_opt = match pattern with
      | PatternMap deps ->
          (match deps with
           | [dep] -> eval_dep_len env p.p_exprs p.p_patterns dep
           | _ -> None)
      | PatternCross subs ->
          let sub_lengths = List.filter_map (fun sub ->
            match sub with
            | PatternMap deps ->
                let lens = List.filter_map (eval_dep_len env p.p_exprs p.p_patterns) deps in
                (match lens with [] -> None | _ -> Some (List.fold_left min max_int lens))
            | _ -> None
          ) subs in
          if List.length sub_lengths <> List.length subs then None
          else Some (List.fold_left ( * ) 1 sub_lengths)
      | PatternSlice (_, indices) -> Some (List.length indices)
      | PatternHead (dep, n) | PatternTail (dep, n) | PatternSample (dep, n) ->
          (match eval_dep_len env p.p_exprs p.p_patterns dep with
           | Some len -> Some (min n len)
           | None -> None)
    in
    match count_opt with
    | Some n when n > 0 -> List.init n (fun i -> name ^ "_branch_" ^ string_of_int (i + 1))
    | _ -> []
  ) p.p_patterns

let register env =
  Env.add "pipeline_nodes"
    (make_builtin ~name:"pipeline_nodes" 1 (fun args env ->
      match args with
      | [VPipeline p] ->
          let base_names = List.map fst p.p_nodes in
          let branch_names = compute_branch_names env p in
          let all_names = base_names @ branch_names in
          VList (List.map (fun name -> (None, VString name)) all_names)
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_nodes` expects a Pipeline, but got %s."
               (Utils.type_name other))
      | _ -> Error.arity_error_named "pipeline_nodes" 1 (List.length args)
    ))
    env
