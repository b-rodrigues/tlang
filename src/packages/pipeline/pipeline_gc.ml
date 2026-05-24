open Ast

(*
--# Garbage Collect Pipeline Nodes
--#
--# Calls nix-store --delete on the store paths of a pipeline's nodes.
--#
--# @name pipeline_gc
--# @param p :: Pipeline The pipeline to clean up.
--# @param dry_run :: Bool (Optional) If `true`, only lists what would be deleted without executing the deletion. Defaults to `false`.
--# @return :: DataFrame A DataFrame with columns `node` (String), `store_path` (String), and `deleted` (Bool).
--# @example
--#   pipeline_gc(p, dry_run=true)
--# @family pipeline
--# @export
*)
let register env =
  let get_arg name pos default named_args =
    match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
    | Some v -> (true, v)
    | None ->
        let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
        if List.length positionals >= pos then (true, List.nth positionals (pos - 1))
        else (false, default)
  in
  let gc_fn named_args _env =
    let named_keys = List.filter_map (fun (k, _) -> k) named_args in
    let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
    match List.find_opt (fun k -> not (List.mem k ["p"; "dry_run"])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "pipeline_gc: unknown argument '%s'" k)
    | None when positional_count > 2 ->
        Error.make_error ArityError
          (Printf.sprintf "Function `pipeline_gc` accepts at most 2 positional arguments but received %d." positional_count)
    | None ->
      match get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
          let (_, dry_run_val) = get_arg "dry_run" 2 (VBool false) named_args in
          (match dry_run_val with
           | VBool dry_run ->
               (match Builder.populate_pipeline ~build:false p with
                | Error msg -> Error.make_error StructuralError msg
                | Ok _ ->
                    let node_names = List.map fst p.p_nodes in
                    let nrows = List.length node_names in
                    let arr_node = Array.init nrows (fun i -> Some (List.nth node_names i)) in
                    let arr_deleted = Array.make nrows (Some false) in
                    let arr_store_path = Array.make nrows None in

                    let err_opt = ref None in
                    List.iteri (fun i name ->
                      if !err_opt = None then (
                        match Builder_utils.eval_node_store_path name with
                        | Error err -> err_opt := Some err
                        | Ok store_path ->
                            arr_store_path.(i) <- Some store_path;
                            if dry_run then (
                              let would_del =
                                if not (Sys.file_exists store_path) then false
                                else
                                  let roots_argv = [| "nix-store"; "--query"; "--roots"; store_path |] in
                                  match Builder_utils.run_command_argv_capture roots_argv with
                                  | Error _ -> false
                                  | Ok roots_out ->
                                      if String.trim roots_out <> "" then false
                                      else
                                        let refs_argv = [| "nix-store"; "--query"; "--referrers"; store_path |] in
                                        match Builder_utils.run_command_argv_capture refs_argv with
                                        | Error _ -> false
                                        | Ok refs_out ->
                                            let lines =
                                              String.split_on_char '\n' refs_out
                                              |> List.map String.trim
                                              |> List.filter (fun s -> s <> "" && s <> store_path)
                                            in
                                            List.length lines = 0
                              in
                              arr_deleted.(i) <- Some would_del
                            ) else (
                              let check_argv = [| "nix-store"; "--delete"; store_path |] in
                              let deleted =
                                match Builder_utils.run_command_argv_exit check_argv with
                                | Ok 0 -> true
                                | _ -> false
                              in
                              arr_deleted.(i) <- Some deleted
                            )
                      )
                    ) node_names;

                    match !err_opt with
                    | Some err -> err
                    | None ->
                        let columns = [
                          ("node",       Arrow_table.StringColumn arr_node);
                          ("store_path", Arrow_table.StringColumn arr_store_path);
                          ("deleted",    Arrow_table.BoolColumn arr_deleted);
                        ] in
                        let arrow_table = Arrow_table.create columns nrows in
                        VDataFrame { arrow_table; group_keys = [] })
           | _ -> Error.type_error "Function `pipeline_gc` expects `dry_run` to be a Bool.")
      | _ -> Error.type_error "Function `pipeline_gc` expects a Pipeline."
  in
  Env.add "pipeline_gc" (make_builtin_named ~name:"pipeline_gc" ~variadic:true 1 gc_fn) env
