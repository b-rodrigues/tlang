open Ast

let check_unknown_keys ~known_keys ~fn_name named_args =
  let named_keys = List.filter_map (fun (k, _) -> k) named_args in
  match List.find_opt (fun k -> not (List.mem k known_keys)) named_keys with
  | Some k -> Some (Error.type_error (Printf.sprintf "%s: unknown argument '%s'" fn_name k))
  | None -> None

let check_arity ~max ~fn_name named_args =
  let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
  if positional_count > max then
    Some (Error.make_error ArityError
      (Printf.sprintf "Function `%s` accepts at most %d positional arguments but received %d." fn_name max positional_count))
  else
    None

let parse_build ~fn_name ~pos named_args =
  let (build_provided, build_val) = Pipeline_args.get_arg "build" pos (VBool false) named_args in
  match build_val with
  | VBool b -> Ok b
  | _ when build_provided ->
      Error (Error.type_error (Printf.sprintf "Function `%s` expects `build` to be a Bool." fn_name))
  | _ ->
      Ok false

let parse_verbose ~fn_name ~pos named_args =
  let (verbose_provided, verbose_val) = Pipeline_args.get_arg "verbose" pos (VNA NAGeneric) named_args in
  match verbose_val with
  | VInt i when i >= 0 -> Ok (Some i)
  | VInt _ ->
      Error (Error.value_error (Printf.sprintf "Function `%s` expects `verbose` to be a non-negative Int." fn_name))
  | _ when verbose_provided ->
      Error (Error.type_error (Printf.sprintf "Function `%s` expects `verbose` to be an Int." fn_name))
  | _ ->
      Ok None

let parse_nix_options ~fn_name ~pos named_args =
  let (_, nix_options_val) = Pipeline_args.get_arg "nix_options" pos (VDict []) named_args in
  match nix_options_val with
  | VNA _ -> Ok None
  | VDict pairs ->
      (match Builder_utils.validate_nix_options fn_name pairs with
       | Ok opts -> Ok (Some opts)
       | Error e -> Error e)
  | _ -> Error (Error.type_error (Printf.sprintf "Function `%s` expects `nix_options` to be a Dictionary." fn_name))

let parse_dry_run ~fn_name ~pos named_args =
  let (dry_run_provided, dry_run_val) = Pipeline_args.get_arg "dry_run" pos (VNA NAGeneric) named_args in
  match dry_run_val with
  | VBool b -> Ok (Some b)
  | VNA _ -> Ok None
  | _ when dry_run_provided ->
      Error (Error.type_error (Printf.sprintf "Function `%s` expects `dry_run` to be a Bool." fn_name))
  | _ -> Ok None

let parse_pipeline_name ~fn_name ~pos named_args =
  let (pipeline_name_provided, pipeline_name_val) = Pipeline_args.get_arg "pipeline_name" pos (VNA NAGeneric) named_args in
  match pipeline_name_val with
  | VString s -> Ok (Some s)
  | VSymbol s -> Ok (Some s)
  | VNA _ -> Ok None
  | _ when pipeline_name_provided ->
      Error (Error.type_error (Printf.sprintf "Function `%s` expects `pipeline_name` to be a String." fn_name))
  | _ -> Ok None

let combine_nix_options ?dry_opt nix_options =
  let base_opts =
    match nix_options with
    | Some opts -> opts
    | None -> Builder_utils.default_nix_opts
  in
  match dry_opt with
  | Some d -> Some { base_opts with dry_run = Some d }
  | None -> Some base_opts

type build_stats = {
  built: int;
  cached: int;
  out_path: string;
  soft_failed: int;
}

let extract_build_stats out =
  let built =
    match out with
    | VDict pairs ->
        (match List.assoc_opt "built" pairs with
         | Some (VInt n) -> n
         | _ -> 0)
    | _ -> 0
  in
  let cached =
    match out with
    | VDict pairs ->
        (match List.assoc_opt "cached" pairs with
         | Some (VInt n) -> n
         | _ -> 0)
    | _ -> 0
  in
  let out_path =
    match out with
    | VDict pairs ->
        (match List.assoc_opt "out_path" pairs with
         | Some (VString s) -> s
         | _ -> "")
    | _ -> ""
  in
  let soft_failed =
    match out with
    | VDict pairs ->
        (match List.assoc_opt "soft_failed" pairs with
         | Some (VList items) -> List.length items
         | _ -> 0)
    | _ -> 0
  in
  { built; cached; out_path; soft_failed }

let print_build_success ~pipeline_name ~p_nodes stats =
  let var_name = match pipeline_name with Some n -> n | None -> "p" in
  let first_node =
    match p_nodes with
    | (name, _) :: _ -> name
    | [] -> "my_node"
  in
  if stats.built > 0 then
    if stats.soft_failed > 0 then
      Printf.eprintf "\nPipeline built successfully but with errors\n"
    else
      Printf.eprintf "\nPipeline successfully built!\n";
  Printf.eprintf "  - Pipeline saved in variable '%s'\n" var_name;
  Printf.eprintf "  - To read the contents of node '%s', use: read_node(%s.%s)\n" first_node var_name first_node;
  Printf.eprintf "  - To inspect node metadata, use: inspect_node(%s.%s)\n" var_name first_node;
  Printf.eprintf "  - To view pipeline summary, use: inspect_pipeline(%s)\n\n%!" var_name

let register_build_logs ~p_exprs_keys ~p_nodes ~out_path =
  match Builder.find_log_for_out_path out_path with
  | Some log_path ->
      List.iter (fun exprs ->
        Hashtbl.replace Ast.pipeline_build_logs exprs log_path
      ) p_exprs_keys;
      (match Builder_logs.read_log log_path with
       | Ok entries ->
           let entry_tbl = Hashtbl.create (List.length entries) in
           List.iter (fun (n, cn) -> Hashtbl.replace entry_tbl n cn) entries;
           List.iter (fun exprs ->
             List.iter (fun (name, v) ->
               match v, Hashtbl.find_opt entry_tbl name with
               | VComputedNode cn, Some logged_cn
                   when logged_cn.cn_path <> "" && logged_cn.cn_path <> Ast.unbuilt_path ->
                     if logged_cn.cn_name <> name then
                       Printf.eprintf "[pipeline] warning: log entry name '%s' != node name '%s' (skipping diagnostics update)\n" logged_cn.cn_name name
                     else (
                       let resolved = { cn with
                         cn_path = logged_cn.cn_path;
                         cn_class = logged_cn.cn_class;
                         cn_runtime = logged_cn.cn_runtime;
                         cn_serializer = logged_cn.cn_serializer;
                       } in
                       let diag = Builder.logged_node_diagnostics resolved.cn_name resolved in
                       Ast.set_in_memory_node_value ~p_exprs:exprs ~node_name:name
                         (VNodeResult { v; node_name = name; diagnostics = diag })
                     )
               | _ -> ()
             ) p_nodes
           ) p_exprs_keys
       | Error e ->
           Printf.eprintf "[pipeline] warning: failed to read build log (%s) — in-memory diagnostics may be stale\n" e);
      Some log_path
  | None -> None
