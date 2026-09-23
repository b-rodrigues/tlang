open Ast

(*
--# Pipeline health table
--#
--# Joins pipeline structure with the latest build log into a single
--# per-node health table. Failed nodes sort first so the root cause is
--# visible without extra calls.
--#
--# Columns:
--# - `name` — node name (String)
--# - `runtime` — e.g. "T", "R", "Python" (String)
--# - `status` — build status from the latest matching log ("Completed",
--#   "Errored", "SoftFailed", "Cached", "Skipped", ...), or NA when the
--#   pipeline has no matching build log yet
--# - `duration` — node build duration in seconds (Float), or NA
--# - `path` — Nix store path of the node output, or NA
--# - `error` — `code: message` for failed nodes (truncated), or NA
--#
--# @name pipeline_status
--# @param pipeline :: Pipeline The pipeline to summarize.
--# @return :: DataFrame One row per node, failed nodes first.
--# @example
--#   pipeline_status(p)
--#   pipeline_status(p) |> filter($status == "Errored")
--# @family pipeline
--# @seealso pipeline_to_frame, build_log, build_log_to_frame
--# @export
*)

type node_health = {
  h_status : string option;
  h_duration : float option;
  h_path : string option;
  h_error : string option;
}

let empty_health = { h_status = None; h_duration = None; h_path = None; h_error = None }

let truncate_error msg =
  let max_len = 200 in
  if String.length msg > max_len then
    String.sub msg 0 (max_len - 3) ^ "..."
  else
    msg

let health_of_log_json node_json =
  let open Yojson.Safe.Util in
  let opt_string key =
    match node_json |> member key with
    | `String s when s <> "" -> Some s
    | _ -> None
  in
  let duration =
    match node_json |> member "duration" with
    | `Float f -> Some f
    | `Int i -> Some (float_of_int i)
    | `String s -> (try Some (float_of_string (String.trim s)) with Failure _ -> None)
    | _ -> None
  in
  let error =
    match opt_string "error_code", opt_string "error_message" with
    | Some code, Some msg -> Some (truncate_error (code ^ ": " ^ msg))
    | Some code, None -> Some code
    | None, Some msg -> Some (truncate_error msg)
    | None, None -> None
  in
  {
    h_status = (match node_json |> member "status" with `String s when s <> "" -> Some s | _ -> None);
    h_duration = duration;
    h_path = opt_string "path";
    h_error = error;
  }

let health_of_latest_log (p : pipeline_result) : (string * node_health) list =
  match Build_log.find_latest_matching_log_path p with
  | None -> []
  | Some log_path ->
      (try
         let json = Yojson.Safe.from_file log_path in
         let open Yojson.Safe.Util in
         let nodes = json |> member "nodes" |> to_list in
         List.filter_map (fun node_json ->
           match node_json |> member "node" with
           | `String name -> Some (name, health_of_log_json node_json)
           | _ -> None
         ) nodes
       with _ -> [])

let is_failed = function
  | Some "Errored" | Some "SoftFailed" -> true
  | _ -> false

let register env =
  Env.add "pipeline_status"
    (make_builtin ~name:"pipeline_status" 1 (fun args _env ->
       match args with
       | [VPipeline p] ->
           let node_names = List.map fst p.p_exprs in
           let health = health_of_latest_log p in
           let health_of name =
             match List.assoc_opt name health with
             | Some h -> h
             | None -> empty_health
           in
           (* Failed nodes first, stable within each group. *)
           let failed, ok =
             List.partition (fun name -> is_failed (health_of name).h_status) node_names
           in
           let ordered = failed @ ok in
           let nrows = List.length ordered in
           let col_string f =
             Array.of_list (List.map (fun name -> f (health_of name)) ordered)
           in
           let col_float f =
             Array.of_list (List.map (fun name -> f (health_of name)) ordered)
           in
           let columns = [
             ("name", Arrow_table.StringColumn
               (Array.of_list (List.map (fun n -> Some n) ordered)));
             ("runtime", Arrow_table.StringColumn
               (Array.of_list (List.map (fun n ->
                  Some (match List.assoc_opt n p.p_runtimes with Some r -> r | None -> "T")) ordered)));
             ("status", Arrow_table.StringColumn (col_string (fun h -> h.h_status)));
             ("duration", Arrow_table.FloatColumn (col_float (fun h -> h.h_duration)));
             ("path", Arrow_table.StringColumn (col_string (fun h -> h.h_path)));
             ("error", Arrow_table.StringColumn (col_string (fun h -> h.h_error)));
           ] in
           let arrow_table = Arrow_table.create columns nrows in
           VDataFrame { arrow_table; group_keys = [] }
       | [other] ->
           Error.type_error
             (Printf.sprintf "Function `pipeline_status` expects a Pipeline, but got %s."
                (Utils.type_name other))
       | _ -> Error.arity_error_named "pipeline_status" 1 (List.length args)
     ))
    env
