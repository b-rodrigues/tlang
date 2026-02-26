(* src/pipeline/builder_populate.ml *)
open Builder_utils
open Builder_write_dag
open Builder_internal

let populate_pipeline ?(build=false) (p : Ast.pipeline_result) =
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
  let missing_files =
    get_all_files ()
    |> List.filter (fun f -> not (Sys.file_exists f))
  in
  if missing_files <> [] then
    Error (Printf.sprintf "The following required files are missing from the file system: %s" (String.concat ", " missing_files))
  else
  let () =
    List.iter (fun (name, _) ->
      let ser = match List.assoc_opt name p.p_serializers with Some s -> s | None -> Ast.Var "default" in
      let des = match List.assoc_opt name p.p_deserializers with Some s -> s | None -> Ast.Var "default" in
      let funcs = match List.assoc_opt name p.p_functions with Some f -> eval_string_list f | None -> [] in
      let is_builtin = function
        | Ast.Value (Ast.VString ("pmml" | "arrow" | "json"))
        | Ast.Var ("pmml" | "arrow" | "json" | "default") -> true
        | _ -> false
      in
      let is_custom_ser = not (is_builtin ser) in
      let is_custom_des = not (is_builtin des) in
      if (is_custom_ser || is_custom_des) && funcs = [] then
        Printf.eprintf "Warning: Node `%s` uses custom serializer/deserializer but has no functions specified. Ensure it's available in the runtime environment.\n%!" name
    ) p.p_exprs
  in
  ensure_pipeline_dir ();
  match write_dag p with
  | Error msg -> Error ("Failed to write dag.json: " ^ msg)
  | Ok () ->
      let nix_content = Nix_emitter.emit_pipeline p in
      match write_file pipeline_nix_path nix_content with
      | Error msg -> Error ("Failed to write pipeline.nix: " ^ msg)
      | Ok () ->
          if build then build_pipeline_internal p
          else Ok (Printf.sprintf "Pipeline populated in `%s`" pipeline_dir)
