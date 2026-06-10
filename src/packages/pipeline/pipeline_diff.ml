open Ast

let string_list xs = VList (List.map (fun s -> (None, VString s)) xs)

let rewired_edges_list rows =
  VList (List.map (fun row -> (None, row)) rows)

let sorted_unique_strings xs =
  List.sort_uniq String.compare xs

let node_names (p : pipeline_result) =
  List.map fst p.p_exprs

let frame_of_pipeline (p : pipeline_result) =
  let node_names = node_names p in
  let depths = Pipeline_to_frame.compute_depths p.p_deps in
  let nrows = List.length node_names in
  let names_arr = Array.of_list node_names in
  let arr_name = Array.init nrows (fun i -> Some names_arr.(i)) in
  let arr_runtime = Array.init nrows (fun i ->
    let n = names_arr.(i) in
    Some (match List.assoc_opt n p.p_runtimes with Some r -> r | None -> "T")) in
  let arr_serializer = Array.init nrows (fun i ->
    let n = names_arr.(i) in
    let e = match List.assoc_opt n p.p_serializers with Some s -> s | None -> Ast.mk_expr (Var "default") in
    Some (Nix_unparse.expr_to_string e)) in
  let arr_deserializer = Array.init nrows (fun i ->
    let n = names_arr.(i) in
    let e = match List.assoc_opt n p.p_deserializers with Some s -> s | None -> Ast.mk_expr (Var "default") in
    Some (Nix_unparse.expr_to_string e)) in
  let arr_noop = Array.init nrows (fun i ->
    let n = names_arr.(i) in
    Some (match List.assoc_opt n p.p_noops with Some b -> b | None -> false)) in
  let arr_deps = Array.init nrows (fun i ->
    let n = names_arr.(i) in
    let deps = match List.assoc_opt n p.p_deps with Some d -> d | None -> [] in
    Some (String.concat ", " deps)) in
  let arr_depth = Array.init nrows (fun i ->
    let n = names_arr.(i) in
    Some (match List.assoc_opt n depths with Some d -> d | None -> 0)) in
  let arr_cmd_type = Array.init nrows (fun i ->
    let n = names_arr.(i) in
    Some (match List.assoc_opt n p.p_scripts with Some (Some _) -> "script" | _ -> "command")) in
  let columns = [
    ("name", Arrow_table.StringColumn arr_name);
    ("runtime", Arrow_table.StringColumn arr_runtime);
    ("serializer", Arrow_table.StringColumn arr_serializer);
    ("deserializer", Arrow_table.StringColumn arr_deserializer);
    ("noop", Arrow_table.BoolColumn arr_noop);
    ("deps", Arrow_table.StringColumn arr_deps);
    ("depth", Arrow_table.IntColumn arr_depth);
    ("command_type", Arrow_table.StringColumn arr_cmd_type);
  ] in
  let arrow_table = Arrow_table.create columns nrows in
  VDataFrame { arrow_table; group_keys = [] }

let node_signature (p : pipeline_result) name =
  let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
  let serializer_expr = match List.assoc_opt name p.p_serializers with Some s -> s | None -> Ast.mk_expr (Var "default") in
  let deserializer_expr = match List.assoc_opt name p.p_deserializers with Some s -> s | None -> Ast.mk_expr (Var "default") in
  let expr_string =
    match List.assoc_opt name p.p_exprs with
    | Some expr -> Nix_unparse.unparse_expr expr
    | None -> ""
  in
  let deps = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
  let explicit_deps =
    match List.assoc_opt name p.p_explicit_deps with
    | Some (Some ds) -> string_list ds
    | Some None | None -> VNA NAGeneric
  in
  VDict [
    ("runtime", VString runtime);
    ("serializer", VString (Nix_unparse.expr_to_string serializer_expr));
    ("deserializer", VString (Nix_unparse.expr_to_string deserializer_expr));
    ("noop", VBool (match List.assoc_opt name p.p_noops with Some b -> b | None -> false));
    ("deps", string_list deps);
    ("command_type", VString (match List.assoc_opt name p.p_scripts with Some (Some _) -> "script" | _ -> "command"));
    ("expr", VString expr_string);
    ("explicit_deps", explicit_deps);
  ]

(*
--# Compare Pipeline Structures
--#
--# Compares two `Pipeline` values and returns a structured diff describing
--# which nodes were added, removed, changed, or rewired.
--#
--# Unlike `node_diff`, which compares node artifacts across builds,
--# `pipeline_diff` compares in-memory pipeline structure.
--#
--# @name pipeline_diff
--# @param p_a :: Pipeline The "before" pipeline.
--# @param p_b :: Pipeline The "after" pipeline.
--# @return :: Dict A structural diff dictionary.
--# @family pipeline
--# @export
*)
let register env =
  Env.add "pipeline_diff"
    (make_builtin ~name:"pipeline_diff" 2 (fun args _env ->
      match args with
      | [VPipeline p_a; VPipeline p_b] ->
          let nodes_a = node_names p_a in
          let nodes_b = node_names p_b in
          let added_nodes = List.filter (fun n -> not (List.mem n nodes_a)) nodes_b in
          let removed_nodes = List.filter (fun n -> not (List.mem n nodes_b)) nodes_a in
          let shared_nodes = List.filter (fun n -> List.mem n nodes_b) nodes_a in
          let changed_nodes =
            List.filter (fun name ->
              not (Diff.values_equal (node_signature p_a name) (node_signature p_b name))
            ) shared_nodes
          in
          let rewired_edges =
            shared_nodes
            |> List.filter_map (fun name ->
              let deps_a = match List.assoc_opt name p_a.p_deps with Some d -> sorted_unique_strings d | None -> [] in
              let deps_b = match List.assoc_opt name p_b.p_deps with Some d -> sorted_unique_strings d | None -> [] in
              if deps_a = deps_b then None
              else Some (VDict [
                ("name", VString name);
                ("was", string_list deps_a);
                ("now", string_list deps_b);
              ]))
          in
          let identical = added_nodes = [] && removed_nodes = [] && changed_nodes = [] && rewired_edges = [] in
          VDict [
            ("kind", VString "pipeline_diff");
            ("identical", VBool identical);
            ("added_nodes", string_list added_nodes);
            ("removed_nodes", string_list removed_nodes);
            ("changed_nodes", string_list changed_nodes);
            ("rewired_edges", rewired_edges_list rewired_edges);
            ("frame_a", frame_of_pipeline p_a);
            ("frame_b", frame_of_pipeline p_b);
          ]
      | [first; second] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_diff` expects two Pipeline values, but got %s and %s."
               (Utils.type_name first) (Utils.type_name second))
      | _ -> Error.arity_error_named "pipeline_diff" 2 (List.length args)
    )) env
