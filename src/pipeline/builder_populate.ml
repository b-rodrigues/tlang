(* src/pipeline/builder_populate.ml *)
open Builder_utils
open Builder_write_dag
open Builder_internal

let populate_pipeline ?(build=false) ?verbose (p : Ast.pipeline_result) =
  let eval_string_list lst =
    lst
    |> List.map (Eval.eval_expr (ref (Ast.Env.empty)))
    |> List.map (function Ast.VString s -> s | _ -> "")
    |> List.filter (fun s -> s <> "")
  in
  let get_all_files () =
    (List.map snd p.p_functions @ List.map snd p.p_includes)
    |> List.concat
    |> eval_string_list
  in
  let script_files =
    List.filter_map (fun (_, s) -> s) p.p_scripts
  in
  let missing_files =
    (get_all_files () @ script_files)
    |> List.filter (fun f -> not (Sys.file_exists f))
  in
  if missing_files <> [] then
    Error (Printf.sprintf "The following required files are missing from the file system: %s" (String.concat ", " missing_files))
  else
  match Pipeline_dependency_requirements.ensure_project_requirements p with
  | Error msg -> Error ("Pipeline dependency check failed: " ^ msg)
  | Ok () ->
  let () =
    List.iter (fun (name, _) ->
      let ser = match List.assoc_opt name p.p_serializers with Some s -> s | None -> Ast.mk_expr (Ast.Var "default") in
      let des = match List.assoc_opt name p.p_deserializers with Some e -> e | None -> Ast.mk_expr (Ast.Var "default") in
      let funcs = match List.assoc_opt name p.p_functions with Some f -> eval_string_list f | None -> [] in
      let rec requires_functions expr =
        match expr.Ast.node with
        | Ast.Value (Ast.VString s) -> not (List.mem s ["pmml"; "arrow"; "json"; "csv"; "default"])
        | Ast.Var _ -> false (* They passed a variable natively, they handle imports *)
        | Ast.DotAccess _ | Ast.RawCode _ -> false
        | Ast.ListLit items -> List.exists (fun (_, e) -> requires_functions e) items
        | Ast.DictLit items -> List.exists (fun (_, e) -> requires_functions e) items
        | _ -> false
      in
      let is_custom_ser = requires_functions ser in
      let is_custom_des = requires_functions des in
      if (is_custom_ser || is_custom_des) && funcs = [] then
        Printf.eprintf "Warning: Node `%s` uses a custom or unknown strategy (not 'default', 'arrow', 'pmml', etc.) but has no supporting `functions` specified.\nIf this is a built-in strategy, check the spelling (strings should be quoted, e.g., \"arrow\").\nIf it is a custom function, ensure it is available in the runtime environment.\n%!" name
    ) p.p_exprs
  in

  (* Ensure nodes with multiple dependencies use a dictionary for their deserializer strategy. *)
  let check_multi_dep_strategies () =
    List.find_map (fun (name, _) ->
      let deps = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
      let des = match List.assoc_opt name p.p_deserializers with Some e -> e | None -> Ast.mk_expr (Ast.Var "default") in
      
      let is_dict_or_list = function
        | Ast.DictLit _ | Ast.ListLit _
        | Ast.Value (Ast.VDict _) | Ast.Value (Ast.VList _) -> true
        | _ -> false
      in
      
      if List.length deps >= 2 && not (is_dict_or_list des.Ast.node) then
        let strategy = Nix_unparse.expr_to_string des in
        if strategy <> "default" then
          Some (Printf.sprintf "Node `%s` has multiple dependencies but uses a single deserializer strategy (\"%s\").\nThis strategy is applied to ALL dependencies, which may cause parse errors if they use different formats (e.g. Arrow vs PMML).\nPlease use a dictionary to specify the deserializer for each dependency, e.g.:\n  deserializer = [ %s: \"...\", %s: \"...\" ]"
                 name strategy (List.hd deps) (List.nth deps 1))
        else None
      else None
    ) p.p_exprs
  in
  
  let check_serializer_coherence () =
    let eval_expr e = Eval.eval_expr (ref Ast.Env.empty) e in
    let get_ser name = 
      match List.assoc_opt name p.p_serializers with
      | Some e -> eval_expr e
      | None -> Ast.(VNA NAGeneric)
    in
    let get_des name = 
      match List.assoc_opt name p.p_deserializers with
      | Some e -> eval_expr e
      | None -> Ast.(VNA NAGeneric)
    in
    let extract_format = function
      | Ast.VSerializer s -> Some s.s_format
      | Ast.VString s | Ast.VSymbol s -> Some (let s = if String.starts_with ~prefix:"^" s then String.sub s 1 (String.length s - 1) else s in String.lowercase_ascii s)
      | Ast.VDict pairs ->
          (match List.assoc_opt "format" pairs with
           | Some (VString s) | Some (VSymbol s) -> Some (String.lowercase_ascii s)
           | _ -> None)
      | _ -> None
    in
    List.find_map (fun (name, _) ->
      let deps = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
      let node_des_val = get_des name in
      List.find_map (fun dep_name ->
        let producer_ser_val = get_ser dep_name in
        let producer_fmt = extract_format producer_ser_val in
        let consumer_fmt =
          match node_des_val with
          | Ast.VDict pairs ->
              (match List.assoc_opt dep_name pairs with
               | Some v -> extract_format v
               | None -> extract_format node_des_val)
          | _ -> extract_format node_des_val
        in
        match producer_fmt, consumer_fmt with
        | Some pf, Some cf when pf <> cf && pf <> "default" && cf <> "default" -> 
            Some (Printf.sprintf "Serializer coherence error: Node `%s` expects format `%s` for dependency `%s`, but `%s` produces format `%s`."
                    name cf dep_name dep_name pf)
        | _ -> None
      ) deps
    ) p.p_exprs
  in

  match check_multi_dep_strategies () with
  | Some err -> Error (err)
  | None ->
  match check_serializer_coherence () with
  | Some err -> Error (err)
  | None ->
  ensure_pipeline_dir ();
  match write_dag p with
  | Error msg -> Error ("Failed to write dag.json: " ^ msg)
  | Ok () ->
      let rel_root = 
        match get_relative_path_to_root () with
        | "." -> ".."
        | r -> "../" ^ r
      in
      let nix_content = Nix_emitter.emit_pipeline ~rel_root p in
      match write_file pipeline_nix_path nix_content with
      | Error msg -> Error ("Failed to write pipeline.nix: " ^ msg)
      | Ok () ->
          if build then build_pipeline_internal ?verbose p
          else Ok (Printf.sprintf "Pipeline populated in `%s`" pipeline_dir)
