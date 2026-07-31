open Ast

(*
--# Convert Pipeline Config to DataFrame
--#
--# Produces a DataFrame with one row per node, showing resolved configuration
--# values and per-field provenance counts.  Extends [pipeline_to_frame] with
--# provenance columns so queries like "which nodes got their serializer from
--# global options?" can be answered directly in T.
--#
--# Columns:
--# - `name`, `runtime`, `depth`, `command_type` — identity (as in pipeline_to_frame)
--# - `serializer`, `deserializer`, `noop`, `shell`, `flake` — resolved values
--# - `prov_serializer`, ..., `prov_flake` — source ("node" / "global" / NA)
--# - `n_deps`, `n_funcs`, `n_incs`, `n_env_vars`, `n_args`, `n_shell_args`
--#   — total counts (non-NA columns)
--# - `n_*_global`, `n_*_node` — provenance counts for each list-type option
--#
--# @name pipeline_config_to_frame
--# @param pipeline :: Pipeline The pipeline to convert.
--# @return :: DataFrame A DataFrame with one row per node and config + provenance columns.
--# @example
--#   pipeline_config_to_frame(p)
--# @family pipeline
--# @seealso pipeline_to_frame, pipeline_node_options
--# @export
*)

let source_to_string = function
  | Source_global -> "global"
  | Source_node -> "node"

let source_to_string_opt = function
  | Some s -> source_to_string s
  | None -> ""

let count_global_node entries =
  let globals, nodes = List.partition (fun (_, s) -> match s with Source_global -> true | _ -> false) entries in
  (List.length entries, List.length globals, List.length nodes)

let register env =
  Env.add "pipeline_config_to_frame"
    (make_builtin ~name:"pipeline_config_to_frame" 1 (fun args _env ->
      match args with
      | [VPipeline p] ->
          let node_names = List.map fst p.p_exprs in
          let depths = Pipeline_to_frame.compute_depths p.p_deps in
          let nrows = List.length node_names in
          let names_arr = Array.of_list node_names in

          let arr_name        = Array.init nrows (fun i -> Some names_arr.(i)) in
          let arr_runtime     = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            Some (match List.assoc_opt n p.p_runtimes with Some r -> r | None -> "T")) in
          let arr_depth       = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            Some (match List.assoc_opt n depths with Some d -> d | None -> 0)) in
          let arr_cmd_type    = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            Some (match List.assoc_opt n p.p_scripts with Some (Some _) -> "script" | _ -> "command")) in

          (* Resolved scalar values *)
          let arr_serializer  = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let e = match List.assoc_opt n p.p_serializers with Some s -> s | None -> mk_expr (Var "default") in
            Some (Nix_unparse.expr_to_string e)) in
          let arr_deserializer = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let e = match List.assoc_opt n p.p_deserializers with Some s -> s | None -> mk_expr (Var "default") in
            Some (Nix_unparse.expr_to_string e)) in
          let arr_noop        = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            Some (match List.assoc_opt n p.p_noops with Some b -> b | None -> false)) in
          let arr_shell       = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            match List.assoc_opt n p.p_shells with Some (Some s) -> Some s | _ -> None) in
          let arr_flake       = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            match List.assoc_opt n p.p_flakes with Some (Some f) -> Some f | _ -> None) in

          (* Provenance: scalar fields *)
          let arr_prov_ser    = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            Some (source_to_string_opt prov.prov_serializer)) in
          let arr_prov_deser  = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            Some (source_to_string_opt prov.prov_deserializer)) in
          let arr_prov_noop   = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            Some (source_to_string_opt prov.prov_noop)) in
          let arr_prov_shell  = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            Some (source_to_string_opt prov.prov_shell)) in
          let arr_prov_flake  = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            Some (source_to_string_opt prov.prov_flake)) in

          (* Deps: total, global, node *)
          let arr_n_deps      = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let deps = match List.assoc_opt n p.p_deps with Some d -> d | None -> [] in
            Some (List.length deps)) in
          let arr_n_deps_g    = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            let (_, g, _) = count_global_node prov.prov_explicit_deps in
            Some g) in
          let arr_n_deps_n    = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            let (_, _, nd) = count_global_node prov.prov_explicit_deps in
            Some nd) in

          (* Functions *)
          let arr_n_funcs     = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let fs = match List.assoc_opt n p.p_functions with Some f -> f | None -> [] in
            Some (List.length fs)) in
          let arr_n_funcs_g   = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            let (_, g, _) = count_global_node prov.prov_functions in
            Some g) in
          let arr_n_funcs_n   = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            let (_, _, nd) = count_global_node prov.prov_functions in
            Some nd) in

          (* Includes *)
          let arr_n_incs      = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let incs = match List.assoc_opt n p.p_includes with Some f -> f | None -> [] in
            Some (List.length incs)) in
          let arr_n_incs_g    = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            let (_, g, _) = count_global_node prov.prov_includes in
            Some g) in
          let arr_n_incs_n    = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            let (_, _, nd) = count_global_node prov.prov_includes in
            Some nd) in

          (* Env vars *)
          let arr_n_env_vars  = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let evs = match List.assoc_opt n p.p_env_vars with Some v -> v | None -> [] in
            Some (List.length evs)) in
          let arr_n_env_vars_g = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            let (_, g, _) = count_global_node prov.prov_env_vars in
            Some g) in
          let arr_n_env_vars_n = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            let (_, _, nd) = count_global_node prov.prov_env_vars in
            Some nd) in

          (* Args *)
          let arr_n_args      = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let rt_args = match List.assoc_opt n p.p_args with Some v -> v | None -> [] in
            Some (List.length rt_args)) in
          let arr_n_args_g    = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            let (_, g, _) = count_global_node prov.prov_args in
            Some g) in
          let arr_n_args_n    = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            let (_, _, nd) = count_global_node prov.prov_args in
            Some nd) in

          (* Shell args *)
          let arr_n_sh_args   = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let sa = match List.assoc_opt n p.p_shell_args with Some v -> v | None -> [] in
            Some (List.length sa)) in
          let arr_n_sh_args_g = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            let (_, g, _) = count_global_node prov.prov_shell_args in
            Some g) in
          let arr_n_sh_args_n = Array.init nrows (fun i ->
            let n = names_arr.(i) in
            let prov = Utils.option_provenance_of p n in
            let (_, _, nd) = count_global_node prov.prov_shell_args in
            Some nd) in

          let columns = [
            ("name",            Arrow_table.StringColumn arr_name);
            ("runtime",         Arrow_table.StringColumn arr_runtime);
            ("depth",           Arrow_table.IntColumn arr_depth);
            ("command_type",    Arrow_table.StringColumn arr_cmd_type);
            ("serializer",      Arrow_table.StringColumn arr_serializer);
            ("deserializer",    Arrow_table.StringColumn arr_deserializer);
            ("noop",            Arrow_table.BoolColumn arr_noop);
            ("shell",           Arrow_table.StringColumn arr_shell);
            ("flake",           Arrow_table.StringColumn arr_flake);
            ("prov_serializer", Arrow_table.StringColumn arr_prov_ser);
            ("prov_deserializer", Arrow_table.StringColumn arr_prov_deser);
            ("prov_noop",       Arrow_table.StringColumn arr_prov_noop);
            ("prov_shell",      Arrow_table.StringColumn arr_prov_shell);
            ("prov_flake",      Arrow_table.StringColumn arr_prov_flake);
            ("n_deps",          Arrow_table.IntColumn arr_n_deps);
            ("n_deps_global",   Arrow_table.IntColumn arr_n_deps_g);
            ("n_deps_node",     Arrow_table.IntColumn arr_n_deps_n);
            ("n_funcs",         Arrow_table.IntColumn arr_n_funcs);
            ("n_funcs_global",  Arrow_table.IntColumn arr_n_funcs_g);
            ("n_funcs_node",    Arrow_table.IntColumn arr_n_funcs_n);
            ("n_incs",          Arrow_table.IntColumn arr_n_incs);
            ("n_incs_global",   Arrow_table.IntColumn arr_n_incs_g);
            ("n_incs_node",     Arrow_table.IntColumn arr_n_incs_n);
            ("n_env_vars",      Arrow_table.IntColumn arr_n_env_vars);
            ("n_env_vars_global", Arrow_table.IntColumn arr_n_env_vars_g);
            ("n_env_vars_node", Arrow_table.IntColumn arr_n_env_vars_n);
            ("n_args",          Arrow_table.IntColumn arr_n_args);
            ("n_args_global",   Arrow_table.IntColumn arr_n_args_g);
            ("n_args_node",     Arrow_table.IntColumn arr_n_args_n);
            ("n_shell_args",    Arrow_table.IntColumn arr_n_sh_args);
            ("n_shell_args_global", Arrow_table.IntColumn arr_n_sh_args_g);
            ("n_shell_args_node", Arrow_table.IntColumn arr_n_sh_args_n);
          ] in
          let arrow_table = Arrow_table.create columns nrows in
          VDataFrame { arrow_table; group_keys = [] }
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_config_to_frame` expects a Pipeline, but got %s."
               (Utils.type_name other))
      | _ -> Error.arity_error_named "pipeline_config_to_frame" 1 (List.length args)
    ))
    env
