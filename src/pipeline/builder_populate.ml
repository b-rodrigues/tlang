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

  let check_package_dependencies () =
    let root = get_project_root () in
    let toml_path = Filename.concat root "tproject.toml" in
    if not (Sys.file_exists toml_path) then None
    else
      let content =
        let ch = open_in toml_path in
        let s = really_input_string ch (in_channel_length ch) in
        close_in ch;
        s
      in
      match Toml_parser.parse_tproject_toml content with
      | Error _ -> None (* Ignore malformed TOML for now, let other checks handle it *)
      | Ok cfg ->
          let eval_expr e = Eval.eval_expr (ref Ast.Env.empty) e in
          let extract_format = function
            | Ast.VSerializer s -> Some s.s_format
            | Ast.VString s | Ast.VSymbol s -> Some (let s = if String.starts_with ~prefix:"^" s then String.sub s 1 (String.length s - 1) else s in String.lowercase_ascii s)
            | Ast.VDict pairs -> (match List.assoc_opt "format" pairs with Some (VString s) | Some (VSymbol s) -> Some (String.lowercase_ascii s) | _ -> None)
            | _ -> None
          in
          let missing = ref [] in
          let add_missing node_name runtime lang_target pkg =
            let pkgs = match lang_target with "R" -> cfg.proj_r_dependencies | "Python" -> cfg.proj_py_dependencies | _ -> [] in
            let is_missing = not (List.exists (fun p -> String.lowercase_ascii p = String.lowercase_ascii pkg) pkgs) in
            if is_missing then
              missing := (node_name, runtime, lang_target, pkg) :: !missing
          in
          List.iter (fun (name, _) ->
            let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
            let ser_val = match List.assoc_opt name p.p_serializers with Some e -> eval_expr e | None -> Ast.(VNA NAGeneric) in
            let des_val = match List.assoc_opt name p.p_deserializers with Some e -> eval_expr e | None -> Ast.(VNA NAGeneric) in
            let ser_fmt = extract_format ser_val in
            let des_fmts = match des_val with
              | Ast.VDict pairs -> List.filter_map (fun (k, v) -> match extract_format v with Some f -> Some (k,f) | None -> None) pairs
              | _ -> (match extract_format des_val with Some f -> [("", f)] | None -> [])
            in
            let formats = (match ser_fmt with Some f -> [f] | None -> []) @ (List.map snd des_fmts) in
            List.iter (fun fmt ->
              match runtime with
              | "R" ->
                  if fmt = "arrow" then add_missing name runtime "R" "arrow";
                  if fmt = "pmml" then (add_missing name runtime "R" "pmml"; add_missing name runtime "R" "XML");
                  if fmt = "json" then add_missing name runtime "R" "jsonlite";
                  if fmt = "csv" then add_missing name runtime "R" "dplyr"; (* Encouraged *)
                  if fmt = "onnx" then add_missing name runtime "R" "onnx"
              | "Python" ->
                  if fmt = "arrow" then (add_missing name runtime "Python" "pyarrow"; add_missing name runtime "Python" "pandas");
                  if fmt = "pmml" then (add_missing name runtime "Python" "pypmml"; add_missing name runtime "Python" "sklearn2pmml");
                  if fmt = "onnx" then (add_missing name runtime "Python" "onnx"; add_missing name runtime "Python" "onnxruntime")
              | _ -> ()
            ) formats
          ) p.p_exprs;
          if !missing = [] then None
          else
            let grouped = List.fold_left (fun acc (name, _runtime, lang, pkg) ->
              let key = (lang, pkg) in
              if List.mem_assoc key acc then
                let (nodes, p) = List.assoc key acc in
                (if List.mem name nodes then acc else (key, (name :: nodes, p)) :: List.remove_assoc key acc)
              else (key, ([name], pkg)) :: acc
            ) [] !missing in
            let msg = Buffer.create 256 in
            Buffer.add_string msg "Dependency Check Failure: Missing required packages in tproject.toml for used serializers/deserializers:\n\n";
            List.iter (fun ((lang, _), (nodes, pkg)) ->
              Printf.bprintf msg "  - [%s] Add `%s` for node%s: %s\n"
                lang pkg (if List.length nodes > 1 then "s" else "") (String.concat ", " (List.rev nodes))
            ) grouped;
            Buffer.add_string msg "\nUpdate your tproject.toml and run `t init --update` to fetch the new dependencies.";
            Some (Buffer.contents msg)
  in

  let skip_check =
    match Sys.getenv_opt "TLANG_SKIP_PKG_CHECK" with
    | Some "1" | Some "true" -> true
    | _ -> false
  in

  match (if skip_check then None else check_package_dependencies ()) with
  | Some err -> Error (err)
  | None ->
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
      let rel_root = get_relative_path_to_root () in
      let nix_content = Nix_emitter.emit_pipeline ~rel_root p in
      match write_file pipeline_nix_path nix_content with
      | Error msg -> Error ("Failed to write pipeline.nix: " ^ msg)
      | Ok () ->
          if build then build_pipeline_internal ?verbose p
          else Ok (Printf.sprintf "Pipeline populated in `%s`" pipeline_dir)
