open Ast
open Package_types

module String_set = Set.Make (String)

type requirements = {
  r_deps : String_set.t;
  py_deps : String_set.t;
  additional_tools : String_set.t;
  latex_pkgs : String_set.t;
  reasons : String_set.t;
}

type analysis = {
  missing_r_deps : string list;
  missing_py_deps : string list;
  missing_additional_tools : string list;
  missing_latex_pkgs : string list;
  reasons : string list;
}

let empty_requirements = {
  r_deps = String_set.empty;
  py_deps = String_set.empty;
  additional_tools = String_set.empty;
  latex_pkgs = String_set.empty;
  reasons = String_set.empty;
}

let add_list set items =
  List.fold_left (fun acc item -> String_set.add item acc) set items

let with_reason (req: requirements) reason =
  { req with reasons = String_set.add reason req.reasons }

let merge_requirements a b = {
  r_deps = String_set.union a.r_deps b.r_deps;
  py_deps = String_set.union a.py_deps b.py_deps;
  additional_tools = String_set.union a.additional_tools b.additional_tools;
  latex_pkgs = String_set.union a.latex_pkgs b.latex_pkgs;
  reasons = String_set.union a.reasons b.reasons;
}

let normalize_format s =
  let s =
    if String.length s > 0 && s.[0] = '^' then
      String.sub s 1 (String.length s - 1)
    else
      s
  in
  String.lowercase_ascii s

let canonical_feature_name feature =
  match normalize_format feature with
  | "write_parquet" | "read_parquet" | "write_feather" | "read_feather" -> "arrow"
  | other -> other

let rec formats_of_value = function
  | VSerializer s -> [ canonical_feature_name s.s_format ]
  | VString s | VSymbol s -> [ canonical_feature_name s ]
  | VDict pairs ->
      (match List.assoc_opt "format" pairs with
       | Some value -> formats_of_value value
       | None ->
           List.fold_left
             (fun acc (_, value) -> formats_of_value value @ acc)
             [] pairs)
  | VList items ->
      List.fold_left
        (fun acc (_, value) -> formats_of_value value @ acc)
        [] items
  | _ -> []

let rec formats_of_expr expr =
  match expr.node with
  | Value value -> formats_of_value value
  | Var name -> [ canonical_feature_name name ]
  | DictLit pairs ->
      List.fold_left
        (fun acc (_, value) -> formats_of_expr value @ acc)
        [] pairs
  | ListLit items ->
      List.fold_left
        (fun acc (_, value) -> formats_of_expr value @ acc)
        [] items
  | DotAccess _ | RawCode _ -> []
  | _ -> []

let add_feature_requirement ~node_name ~runtime ~feature =
  let feature = canonical_feature_name feature in
  let reason =
    Printf.sprintf "node `%s` uses `%s` with runtime `%s`" node_name feature runtime
  in
  let req = with_reason empty_requirements reason in
  match runtime, feature with
  | "R", "json" ->
      { req with r_deps = add_list req.r_deps [ "jsonlite" ] }
  | "Python", "json" ->
      empty_requirements
  | "R", "csv" ->
      empty_requirements (* base R write.csv/read.csv; no extra packages needed *)
  | "Python", "csv" ->
      { req with py_deps = add_list req.py_deps [ "pandas" ] }
  | "R", "arrow" ->
      { req with r_deps = add_list req.r_deps [ "arrow" ] }
  | "Python", "arrow" ->
      { req with py_deps = add_list req.py_deps [ "pandas"; "pyarrow" ] }
  | "R", "pmml" ->
      {
        req with
        r_deps = add_list req.r_deps [ "XML"; "jsonlite"; "r2pmml" ];
        additional_tools = add_list req.additional_tools [ "jre" ];
      }
  | "Python", "pmml" ->
      {
        req with
        py_deps =
          add_list req.py_deps
            [ "numpy"; "pandas"; "pyarrow"; "scikit-learn"; "scipy"; "sklearn2pmml"; "statsmodels" ];
        additional_tools = add_list req.additional_tools [ "jre"; "jpmml-evaluator" ];
      }
  | "R", "onnx" ->
      { req with r_deps = add_list req.r_deps [ "onnx" ] }
  | "Python", "onnx" ->
      { req with py_deps = add_list req.py_deps [ "onnxruntime"; "skl2onnx" ] }
  | _ ->
      empty_requirements

let add_quarto_requirement ~node_name =
  let req =
    with_reason empty_requirements
      (Printf.sprintf "node `%s` uses runtime `Quarto`" node_name)
  in
  {
    req with
    r_deps = add_list req.r_deps [ "knitr"; "rmarkdown" ];
    py_deps = add_list req.py_deps [ "ipykernel"; "nbclient"; "nbformat"; "pyyaml" ];
    additional_tools = add_list req.additional_tools [ "quarto"; "which" ];
  }

let scan_code_requirements ~node_name ~runtime raw_text =
  let reason = Printf.sprintf "node `%s` usage discovery" node_name in
  let req = with_reason empty_requirements reason in
  match runtime with
  | "R" ->
      let req = { req with r_deps = add_list req.r_deps [ "jsonlite" ] } in
      let has_pkg pkg =
        let re1 = Str.regexp (Printf.sprintf "library([\"']?%s[\"']?)" pkg) in
        let re2 = Str.regexp (Printf.sprintf "require([\"']?%s[\"']?)" pkg) in
        let re3 = Str.regexp (Printf.sprintf "%s::" pkg) in
        (try ignore (Str.search_forward re1 raw_text 0); true with Not_found ->
         try ignore (Str.search_forward re2 raw_text 0); true with Not_found ->
         try ignore (Str.search_forward re3 raw_text 0); true with Not_found -> false)
      in
      if has_pkg "ggplot2" then
        { req with r_deps = add_list req.r_deps [ "ggplot2"; "jsonlite" ] }
      else empty_requirements
  | "Python" ->
      let has_pkg pkg =
        let re1 = Str.regexp (Printf.sprintf "import %s" pkg) in
        let re2 = Str.regexp (Printf.sprintf "from %s" pkg) in
        (try ignore (Str.search_forward re1 raw_text 0); true with Not_found ->
         try ignore (Str.search_forward re2 raw_text 0); true with Not_found -> false)
      in
      if has_pkg "matplotlib" then
        { req with py_deps = add_list req.py_deps [ "matplotlib"; "pandas" ] }
      else if has_pkg "plotnine" then
        { req with py_deps = add_list req.py_deps [ "plotnine"; "pandas" ] }
      else empty_requirements
  | _ -> empty_requirements

let required_for_pipeline (p : Ast.pipeline_result) =
  List.fold_left
    (fun acc (node_name, cmd_expr) ->
      let runtime =
        match List.assoc_opt node_name p.p_runtimes with
        | Some r -> r
        | None -> "T"
      in
      let serializer =
        match List.assoc_opt node_name p.p_serializers with
        | Some expr -> expr
        | None -> Ast.mk_expr (Ast.Var "default")
      in
      let deserializer =
        match List.assoc_opt node_name p.p_deserializers with
        | Some expr -> expr
        | None -> Ast.mk_expr (Ast.Var "default")
      in
      let formats =
        add_list String_set.empty (formats_of_expr serializer @ formats_of_expr deserializer)
      in
      let acc =
        String_set.fold
          (fun feature req ->
            merge_requirements req (add_feature_requirement ~node_name ~runtime ~feature))
          formats acc
      in
      let acc =
        match cmd_expr.node with
        | RawCode { raw_text; _ } ->
            merge_requirements acc (scan_code_requirements ~node_name ~runtime raw_text)
        | _ -> acc
      in
      if runtime = "Quarto" then
        merge_requirements acc (add_quarto_requirement ~node_name)
      else
        acc)
    empty_requirements
    p.p_exprs

let analyze_missing_requirements (p : Ast.pipeline_result) (cfg : project_config) =
  let required = required_for_pipeline p in
  let missing_from required_list existing_list =
    String_set.diff required_list (add_list String_set.empty existing_list)
    |> String_set.elements
  in
  {
    missing_r_deps = missing_from required.r_deps cfg.proj_r_dependencies;
    missing_py_deps = missing_from required.py_deps cfg.proj_py_dependencies;
    missing_additional_tools =
      missing_from required.additional_tools cfg.proj_additional_tools;
    missing_latex_pkgs = missing_from required.latex_pkgs cfg.proj_latex_packages;
    reasons = String_set.elements required.reasons;
  }

let analysis_is_empty analysis =
  analysis.missing_r_deps = []
  && analysis.missing_py_deps = []
  && analysis.missing_additional_tools = []
  && analysis.missing_latex_pkgs = []

let append_missing existing missing =
  let existing_set = add_list String_set.empty existing in
  existing
  @ List.filter (fun item -> not (String_set.mem item existing_set)) missing

let update_config_with_missing_requirements (cfg : project_config) analysis =
  {
    cfg with
    proj_r_dependencies = append_missing cfg.proj_r_dependencies analysis.missing_r_deps;
    proj_py_dependencies = append_missing cfg.proj_py_dependencies analysis.missing_py_deps;
    proj_additional_tools =
      append_missing cfg.proj_additional_tools analysis.missing_additional_tools;
    proj_latex_packages =
      append_missing cfg.proj_latex_packages analysis.missing_latex_pkgs;
  }

let format_package_list packages =
  Printf.sprintf "[%s]"
    (String.concat ", " (List.map (fun pkg -> Printf.sprintf "%S" pkg) packages))

let format_analysis analysis =
  let sections =
    [
      ("[r-dependencies]", analysis.missing_r_deps);
      ("[py-dependencies]", analysis.missing_py_deps);
      ("[additional-tools]", analysis.missing_additional_tools);
      ("[latex]", analysis.missing_latex_pkgs);
    ]
    |> List.filter_map (fun (section, packages) ->
           if packages = [] then None
           else Some (Printf.sprintf "  %s packages += %s" section (format_package_list packages)))
  in
  let reasons =
    if analysis.reasons = [] then
      []
    else
      ("Required because:" :: List.map (fun reason -> "  - " ^ reason) analysis.reasons)
  in
  String.concat "\n"
    ([
       "Pipeline requires explicit dependencies in `tproject.toml` before it can be emitted or built.";
     ]
     @ reasons
     @ [ "Missing entries:" ]
     @ sections)

let is_interactive () =
  try Unix.isatty Unix.stdin && Unix.isatty Unix.stdout with _ -> false

let read_file path =
  try
    let ch = open_in path in
    let content =
      Fun.protect
        ~finally:(fun () -> close_in_noerr ch)
        (fun () -> really_input_string ch (in_channel_length ch))
    in
    Ok content
  with Sys_error msg -> Error (Printf.sprintf "%s (%s)" msg path)

let write_file path content =
  try
    let ch = open_out path in
    Fun.protect
      ~finally:(fun () -> close_out_noerr ch)
      (fun () -> output_string ch content);
    Ok ()
  with Sys_error msg -> Error (Printf.sprintf "%s (%s)" msg path)

let prompt_to_update ~tproject_path analysis =
  Printf.printf "%s\n\nAdd these entries to %s now? [y/N]: %!"
    (format_analysis analysis) tproject_path;
  let answer =
    try read_line () with
    | End_of_file ->
        Printf.printf "\nNo input received; leaving `tproject.toml` unchanged.\n%!";
        ""
  in
  let answer = String.lowercase_ascii (String.trim answer) in
  answer = "y" || answer = "yes"

let env_flag name =
  match Sys.getenv_opt name with
  | Some ("1" | "true" | "TRUE" | "yes" | "YES" | "on" | "ON") -> true
  | _ -> false

let rebuild_message tproject_path =
  Printf.sprintf
    "Updated %s with explicit pipeline dependencies.\nPlease leave the current shell, run `t update`, re-enter with `nix develop`, and then retry building the pipeline."
    tproject_path

let ensure_project_requirements (p : Ast.pipeline_result) =
  let project_root = Builder_utils.get_project_root () in
  let tproject_path = Filename.concat project_root "tproject.toml" in
  let required = required_for_pipeline p in
  let has_any_requirements =
    not (String_set.is_empty required.r_deps)
    || not (String_set.is_empty required.py_deps)
    || not (String_set.is_empty required.additional_tools)
    || not (String_set.is_empty required.latex_pkgs)
  in
  if not has_any_requirements then
    Ok ()
  else if not (Sys.file_exists tproject_path) then
    if env_flag "TLANG_AUTO_ADD_PIPELINE_DEPS" then
      Ok ()
    else
      let analysis =
        {
          missing_r_deps = String_set.elements required.r_deps;
          missing_py_deps = String_set.elements required.py_deps;
          missing_additional_tools = String_set.elements required.additional_tools;
          missing_latex_pkgs = String_set.elements required.latex_pkgs;
          reasons = String_set.elements required.reasons;
        }
      in
      Error
        (Printf.sprintf
           "%s\n\n`tproject.toml` was not found at %s, so T cannot add these dependencies automatically."
           (format_analysis analysis) tproject_path)
  else
    match read_file tproject_path with
    | Error msg -> Error (Printf.sprintf "Cannot read tproject.toml: %s" msg)
    | Ok content ->
        (match Toml_parser.parse_tproject_toml content with
         | Error msg -> Error (Printf.sprintf "Cannot parse tproject.toml: %s" msg)
         | Ok cfg ->
             let analysis = analyze_missing_requirements p cfg in
             if analysis_is_empty analysis then
               Ok ()
             else if env_flag "TLANG_AUTO_ADD_PIPELINE_DEPS" then
               let updated_cfg = update_config_with_missing_requirements cfg analysis in
               let updated_content = Toml_parser.serialize_tproject_toml updated_cfg in
               (match write_file tproject_path updated_content with
                | Error msg -> Error (Printf.sprintf "Failed to update tproject.toml: %s" msg)
                | Ok () -> Error (rebuild_message tproject_path))
             else if not (is_interactive ()) then
               Error
                  (format_analysis analysis
                  ^ "\n\nThis session is non-interactive, so T cannot update `tproject.toml` automatically."
                  ^ "\nSet `TLANG_AUTO_ADD_PIPELINE_DEPS=1` to auto-add the missing entries in CI or other unattended environments.")
             else if not (prompt_to_update ~tproject_path analysis) then
               Error
                  (format_analysis analysis
                  ^ "\n\nUser declined to update `tproject.toml`.")
             else
                let updated_cfg = update_config_with_missing_requirements cfg analysis in
                let updated_content = Toml_parser.serialize_tproject_toml updated_cfg in
                match write_file tproject_path updated_content with
                | Error msg -> Error (Printf.sprintf "Failed to update tproject.toml: %s" msg)
                | Ok () -> Error (rebuild_message tproject_path))
