open Ast

let rec nth_safe n = function
  | h :: _ when n = 0 -> Some h
  | _ :: t -> nth_safe (n - 1) t
  | [] -> None

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
--*)
let register env =
  let get_arg name pos default named_args =
    match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
    | Some v -> (true, v)
    | None ->
        let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
        match nth_safe (pos - 1) positionals with
        | Some v -> (true, v)
        | None -> (false, default)
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
                    let arr_node = Array.of_list (List.map (fun n -> Some n) node_names) in

                    let is_safe_to_delete store_path =
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

                    let entries_result =
                      List.fold_left (fun acc name ->
                        match acc with
                        | Error _ -> acc
                        | Ok entries ->
                            match Builder_utils.eval_node_store_path name with
                            | Error err -> Error err
                            | Ok store_path ->
                                let safe = is_safe_to_delete store_path in
                                let deleted =
                                  if dry_run then safe
                                  else if safe then
                                    match Builder_utils.run_command_argv_exit [| "nix-store"; "--delete"; store_path |] with
                                    | Ok 0 -> true | _ -> false
                                  else false
                                in
                                Ok ((Some store_path, Some deleted) :: entries)
                      ) (Ok []) node_names
                    in

                    match entries_result with
                    | Error err -> err
                    | Ok entries ->
                        let entries = List.rev entries in
                        let arr_store_path = Array.of_list (List.map fst entries) in
                        let arr_deleted = Array.of_list (List.map snd entries) in
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
  let env = Env.add "pipeline_gc" (make_builtin_named ~name:"pipeline_gc" ~variadic:true 1 gc_fn) env in
(*
--# Run System Garbage Collection
--#
--# Runs the global Nix garbage collector (nix-store --gc) to delete any unreferenced,
--# stale, or unused paths from the local Nix store.
--#
--# @name t_gc
--# @return :: String A status message summarizing the deleted store paths.
--# @example
--#   t_gc()
--# @family pipeline
--# @export
*)
  let t_gc_fn named_args _env =
    let named_keys = List.filter_map (fun (k, _) -> k) named_args in
    let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
    match List.find_opt (fun k -> not (List.mem k [])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "t_gc: unknown argument '%s'" k)
    | None when positional_count > 0 ->
        Error.make_error ArityError
          (Printf.sprintf "Function `t_gc` accepts at most 0 positional arguments but received %d." positional_count)
    | None ->
        if not (Builder_utils.command_exists "nix-store") then
          Error.make_error ShellError "Nix store commands are not available on this system."
        else
          let argv = [| "nix-store"; "--gc" |] in
          match Builder_utils.run_command_argv_capture argv with
          | Ok output ->
              let trimmed = String.trim output in
              if trimmed = "" then
                VString "Garbage collection completed. No unused store paths were deleted."
              else
                VString ("Garbage collection completed:\n" ^ trimmed)
          | Error msg ->
              Error.make_error ShellError ("Failed to run nix-store --gc: " ^ msg)
  in
  Env.add "t_gc" (make_builtin_named ~name:"t_gc" ~variadic:true 0 t_gc_fn) env
