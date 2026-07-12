(* src/pipeline/builder_diff.ml *)
(* Content-addressed output diffing: compares two builds and reports per-node changes.
   Uses per-node Nix content hashes stored in build logs for fast comparison without
   loading artifacts. Implements §3.3 of the path-to-0.54.1 spec. *)

open Ast
open Builder_utils

type node_status =
  | Unchanged of { hash : string }
  | Changed of { hash_a : string; hash_b : string }
  | Added of { hash : string }
  | Removed of { hash : string }
  | Errored of { error_class : string }

type node_diff_entry = {
  nde_name : string;
  nde_status : node_status;
  nde_class_a : string;
  nde_class_b : string;
}

type build_info = {
  bi_log_file : string;
  bi_timestamp : string;
  bi_hash : string;
}

type diff_result = {
  dr_build_a : build_info;
  dr_build_b : build_info;
  dr_nodes : node_diff_entry list;
  dr_total : int;
  dr_unchanged : int;
  dr_changed : int;
  dr_added : int;
  dr_removed : int;
}

let find_two_matching_logs (p : pipeline_result) =
  let logs = Builder_logs.get_logs () in
  let try_log log_file =
    let full_path = Filename.concat pipeline_dir log_file in
    match Builder_logs.read_log full_path with
    | Ok entries when Builder_read_node.pipeline_matches_logged_entries p entries -> Some full_path
    | _ -> None
  in
  let matching = List.filter_map try_log logs in
  match matching with
  | a :: b :: _ -> Some (b, a)
  | _ -> None

let load_log_with_hashes path =
  match Builder_logs.read_log_with_hashes path with
  | Ok (entries, timestamp, top_hash) ->
      let node_map = Hashtbl.create (List.length entries) in
      List.iter (fun (name, cn, node_hash) ->
        Hashtbl.replace node_map name (cn, node_hash)
      ) entries;
      let info = {
        bi_log_file = Filename.basename path;
        bi_timestamp = timestamp;
        bi_hash = top_hash;
      } in
      Ok (info, node_map)
  | Error msg -> Error msg

let compute_diff log_a_path log_b_path =
  match load_log_with_hashes log_a_path, load_log_with_hashes log_b_path with
  | Error e, _ | _, Error e -> Error e
  | Ok (info_a, nodes_a), Ok (info_b, nodes_b) ->
      let names_a = Hashtbl.fold (fun k _ acc -> k :: acc) nodes_a [] |> List.sort String.compare in
      let names_b = Hashtbl.fold (fun k _ acc -> k :: acc) nodes_b [] |> List.sort String.compare in
      let all_names = List.sort String.compare (List.sort_uniq String.compare (names_a @ names_b)) in
      let entries = List.filter_map (fun name ->
        let in_a = Hashtbl.find_opt nodes_a name in
        let in_b = Hashtbl.find_opt nodes_b name in
        match in_a, in_b with
        | Some (cn_a, hash_a), Some (cn_b, hash_b) ->
            let class_a = cn_a.Ast.cn_class in
            let class_b = cn_b.Ast.cn_class in
            if hash_a = hash_b && hash_a <> "" then
              Some { nde_name = name; nde_status = Unchanged { hash = hash_a };
                     nde_class_a = class_a; nde_class_b = class_b }
            else if hash_a = "" || hash_b = "" then
              Some { nde_name = name; nde_status = Changed { hash_a; hash_b };
                     nde_class_a = class_a; nde_class_b = class_b }
            else
              Some { nde_name = name; nde_status = Changed { hash_a; hash_b };
                     nde_class_a = class_a; nde_class_b = class_b }
        | Some (cn_a, hash_a), None ->
            Some { nde_name = name; nde_status = Removed { hash = hash_a };
                   nde_class_a = cn_a.Ast.cn_class; nde_class_b = "" }
        | None, Some (cn_b, hash_b) ->
            Some { nde_name = name; nde_status = Added { hash = hash_b };
                   nde_class_a = ""; nde_class_b = cn_b.Ast.cn_class }
        | None, None -> None
      ) all_names in
      let counts = List.fold_left (fun (u, c, a, r) e ->
        match e.nde_status with
        | Unchanged _ -> (u + 1, c, a, r)
        | Changed _ -> (u, c + 1, a, r)
        | Added _ -> (u, c, a + 1, r)
        | Removed _ -> (u, c, a, r + 1)
        | Errored _ -> (u, c + 1, a, r)
      ) (0, 0, 0, 0) entries in
      let total = List.length entries in
      Ok {
        dr_build_a = info_a;
        dr_build_b = info_b;
        dr_nodes = entries;
        dr_total = total;
        dr_unchanged = (fun (u, _, _, _) -> u) counts;
        dr_changed = (fun (_, c, _, _) -> c) counts;
        dr_added = (fun (_, _, a, _) -> a) counts;
        dr_removed = (fun (_, _, _, r) -> r) counts;
      }

let node_status_to_string = function
  | Unchanged _ -> "unchanged"
  | Changed _ -> "changed"
  | Added _ -> "added"
  | Removed _ -> "removed"
  | Errored _ -> "errored"

let print_diff_result (r : diff_result) =
  Printf.printf "\nBuild A: %s (%s)\n" r.dr_build_a.bi_log_file r.dr_build_a.bi_timestamp;
  Printf.printf "Build B: %s (%s)\n\n" r.dr_build_b.bi_log_file r.dr_build_b.bi_timestamp;
  Printf.printf "%-20s %-12s %s\n" "Node" "Status" "Detail";
  Printf.printf "%-20s %-12s %s\n" (String.make 20 '-') (String.make 12 '-') (String.make 30 '-');
  List.iter (fun e ->
    let detail = match e.nde_status with
      | Unchanged _ -> ""
      | Changed { hash_a; hash_b } ->
          if hash_a = "" || hash_b = "" then "output hash differs"
          else Printf.sprintf "hash %s -> %s" (String.sub hash_a 0 (min 7 (String.length hash_a)))
                                         (String.sub hash_b 0 (min 7 (String.length hash_b)))
      | Added _ -> "new node"
      | Removed _ -> "removed"
      | Errored _ -> "errored"
    in
    Printf.printf "%-20s %-12s %s\n" e.nde_name (node_status_to_string e.nde_status) detail
  ) r.dr_nodes;
  Printf.printf "\nSummary: %d nodes, %d unchanged, %d changed, %d added, %d removed\n"
    r.dr_total r.dr_unchanged r.dr_changed r.dr_added r.dr_removed

let diff_result_to_yojson (r : diff_result) =
  let node_to_yojson e =
    let status_str = node_status_to_string e.nde_status in
    let base = [
      ("name", `String e.nde_name);
      ("status", `String status_str);
    ] in
    let with_detail = match e.nde_status with
      | Unchanged { hash } -> base @ [("hash", `String hash)]
      | Changed { hash_a; hash_b } -> base @ [("hash_a", `String hash_a); ("hash_b", `String hash_b)]
      | Added { hash } -> base @ [("hash", `String hash)]
      | Removed { hash } -> base @ [("hash", `String hash)]
      | Errored { error_class } -> base @ [("error_class", `String error_class)]
    in
    `Assoc with_detail
  in
  `Assoc [
    ("schema_version", `String "1");
    ("status", `String "ok");
    ("phase", `String "diff");
    ("build_a", `Assoc [
      ("log", `String r.dr_build_a.bi_log_file);
      ("timestamp", `String r.dr_build_a.bi_timestamp);
      ("hash", `String r.dr_build_a.bi_hash);
    ]);
    ("build_b", `Assoc [
      ("log", `String r.dr_build_b.bi_log_file);
      ("timestamp", `String r.dr_build_b.bi_timestamp);
      ("hash", `String r.dr_build_b.bi_hash);
    ]);
    ("summary", `Assoc [
      ("total", `Int r.dr_total);
      ("unchanged", `Int r.dr_unchanged);
      ("changed", `Int r.dr_changed);
      ("added", `Int r.dr_added);
      ("removed", `Int r.dr_removed);
    ]);
    ("nodes", `List (List.map node_to_yojson r.dr_nodes));
  ]
