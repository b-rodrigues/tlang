open Ast
open Builder_utils

let write_dag (p : Ast.pipeline_result) =
  let nodes_json =
    List.map (fun (name, _) ->
      let deps = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
      let entries = [
        ("node_name", "\"" ^ Serialization.json_escape name ^ "\"");
        ("depends", Serialization.json_list deps)
      ] in
      Serialization.json_dict entries
    ) p.p_exprs
  in
  let dag_json = "[\n" ^ (String.concat ",\n" nodes_json) ^ "\n]" in
  write_file dag_path dag_json
