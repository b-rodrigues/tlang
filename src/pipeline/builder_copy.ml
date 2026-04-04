(* src/pipeline/builder_copy.ml *)
open Ast
open Builder_utils
open Builder_logs

let pipeline_copy ?(node_name=None) ?(target_dir="pipeline-output") ?(dir_mode="0755") ?(file_mode="0644") () =
  let is_valid_mode mode =
    let len = String.length mode in
    let rec all_octal idx =
      if idx >= len then true
      else
        let c = mode.[idx] in
        c >= '0' && c <= '7' && all_octal (idx + 1)
    in
    (* Accept 4 or 5 chars so common forms like 0755 and 00755 both validate,
       while still restricting input to safe octal chmod modes. *)
    (len = 4 || len = 5) && mode.[0] = '0' && all_octal 1
  in
  if not (is_valid_mode dir_mode && is_valid_mode file_mode) then
    Error.make_error GenericError
      "Invalid file or directory mode: expected octal string like 0755 or 0644."
  else
    let logs = get_logs () in
    match logs with
    | [] -> Error.make_error FileError "No build logs found in `_pipeline/`. Run `populate_pipeline(p, build=true)` first."
    | latest_log :: _ ->
        match read_log (Filename.concat pipeline_dir latest_log) with
        | Error msg -> Error.make_error FileError (Printf.sprintf "Failed to read log `%s`: %s" latest_log msg)
        | Ok entries ->
            let () = if not (Sys.file_exists target_dir) then Unix.mkdir target_dir 0o755 in

            let copy_item src dest =
               let argv = [| "cp"; "-RP"; src; dest |] in
               match run_command_argv_exit argv with
               | Ok code -> code
               | Error _ -> 1
            in

            let apply_perms path =
               (* Use argv-based find+chmod to avoid shell injection via path *)
               ignore (run_command_argv_exit [| "find"; path; "-type"; "d"; "-exec"; "chmod"; dir_mode; "{}"; "+" |]);
               ignore (run_command_argv_exit [| "find"; path; "-type"; "f"; "-exec"; "chmod"; file_mode; "{}"; "+" |])
            in

            let nodes_to_copy = match node_name with
              | None -> entries
              | Some name ->
                  (match List.assoc_opt name entries with
                   | Some cn -> [(name, cn)]
                   | None -> [])
            in

            if nodes_to_copy = [] then
              match node_name with
              | Some name -> Error.make_error KeyError (Printf.sprintf "Node `%s` not found in build log." name)
              | None -> Error.make_error GenericError "No nodes found to copy."
            else
              let errors = ref [] in
              let success_count = ref 0 in
              List.iter (fun (name, cn) ->
                let src_node_dir = Filename.dirname cn.cn_path in
                let dest_node_dir = Filename.concat target_dir name in

                if not (Sys.file_exists src_node_dir) then
                  errors := (Printf.sprintf "Source path `%s` for node `%s` does not exist." src_node_dir name) :: !errors
                else begin
                  if Sys.file_exists dest_node_dir then begin
                    ignore (run_command_argv_exit [| "rm"; "-rf"; dest_node_dir |])
                  end;
                  let exit_code = copy_item src_node_dir dest_node_dir in
                  if exit_code <> 0 then
                    errors := (Printf.sprintf "Failed to copy node `%s` (exit code %d)." name exit_code) :: !errors
                  else begin
                    apply_perms dest_node_dir;
                    incr success_count
                  end
                end
              ) nodes_to_copy;

              if !errors <> [] && !success_count = 0 then
                Error.make_error FileError (String.concat "; " !errors)
              else
                let msg = Printf.sprintf "Successfully copied %d node(s) to `%s`." !success_count target_dir in
                if !errors <> [] then
                  VString (msg ^ " Warning: " ^ (String.concat "; " !errors))
                else
                  VString msg
