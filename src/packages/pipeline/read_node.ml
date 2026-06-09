open Ast
open Pipeline_utils

type python_debug_guards = {
  root_dir : string;
  bin_dir : string;
  python_dir : string;
}

let debug_subshell_guard_message runtime command =
  Printf.sprintf
    "Don't use %s in this T %s debug subshell. Declare packages in tproject.toml, run `t update`, and re-enter `nix develop`."
    command runtime

let write_text_file path content =
  let ch = open_out path in
  output_string ch content;
  close_out ch

let python_package_manager_shim_names =
  [ "pip"; "pip3"; "uv"; "poetry"; "conda"; "mamba"; "micromamba"; "easy_install" ]

let r_debug_startup_content () =
  String.concat "\n"
    [
      "options(prompt='r> ', continue='r+ ')";
      Printf.sprintf
        "install.packages <- function(...) stop(%S, call. = FALSE)"
        (debug_subshell_guard_message "R" "install.packages()");
      Printf.sprintf
        "update.packages <- function(...) stop(%S, call. = FALSE)"
        (debug_subshell_guard_message "R" "update.packages()");
      Printf.sprintf
        "remove.packages <- function(...) stop(%S, call. = FALSE)"
        (debug_subshell_guard_message "R" "remove.packages()");
    ]

let julia_debug_startup_content julia_package_path =
  let buf = Buffer.create 512 in
  Buffer.add_string buf
    {|const _tlang_pkg_id = Base.PkgId(Base.UUID("44cfe95a-1eb2-52ea-b672-e2afdf69b78f"), "Pkg")
     const _tlang_real_pkg = Base.require(_tlang_pkg_id)
|};
  (match julia_package_path with
   | Some path ->
       Printf.bprintf buf
         "const _tlang_project = %S\n\
          try\n\
          \  _tlang_real_pkg.activate(; temp=true, io=devnull)\n\
          \  _tlang_real_pkg.develop(path=_tlang_project, io=devnull)\n\
          \  _tlang_real_pkg.instantiate(io=devnull)\n\
          catch err\n\
          \  @warn \"Failed to prepare repo-local Julia tlang package for debug_node\" exception=(err, catch_backtrace())\n\
          end\n"
         path
   | None -> ());
  Printf.bprintf buf
    "module _TlangGuardPkg\n\
     import Main: _tlang_real_pkg\n\
     export add, rm, update, develop\n\
     add(args...; kwargs...) = error(%S)\n\
     rm(args...; kwargs...) = error(%S)\n\
     update(args...; kwargs...) = error(%S)\n\
     develop(args...; kwargs...) = error(%S)\n\
     # Delegate read-only Pkg operations to the real Pkg module\n\
     const _real = _tlang_real_pkg\n\
     status(args...; kwargs...) = _real.status(args...; kwargs...)\n\
     dependencies(args...; kwargs...) = _real.dependencies(args...; kwargs...)\n\
     instantiate(args...; kwargs...) = _real.instantiate(args...; kwargs...)\n\
     activate(args...; kwargs...) = _real.activate(args...; kwargs...)\n\
     project(args...; kwargs...) = _real.project(args...; kwargs...)\n\
     compat(args...; kwargs...) = _real.compat(args...; kwargs...)\n\
     end\n"
    (debug_subshell_guard_message "Julia" "Pkg.add()")
    (debug_subshell_guard_message "Julia" "Pkg.rm()")
    (debug_subshell_guard_message "Julia" "Pkg.update()")
    (debug_subshell_guard_message "Julia" "Pkg.develop()");
  Buffer.add_string buf
    {|if isinteractive()
     const _tlang_repl_id = Base.PkgId(Base.UUID("3fa0cd96-eef1-5676-8a61-b3b8758bbffb"), "REPL")
     try
       _tlang_repl = Base.require(_tlang_repl_id)
       function _tlang_install_packages_hook(pkgs::Vector{Symbol})
         pkg_str = join(string.(pkgs), ", ")
         println(" │ Packages [", pkg_str, "] not found, but packages named [", pkg_str, "] are available from")
         println(" │ a registry.")
         println(" │ Install packages?")
         println(" │   (project) pkg> add ", pkg_str)
         print(" └ (y/n) [y]: ")
         flush(stdout)
         response = lowercase(strip(readline(stdin)))
         if response == "" || response == "y" || response == "yes"
           println("\nDon't use interactive package installation in this T Julia debug subshell.")
           println("Declare packages in tproject.toml, run `t update`, and re-enter `nix develop`.\n")
         else
           println("Cancelled.")
         end
         return false
       end
       pushfirst!(_tlang_repl.install_packages_hooks, _tlang_install_packages_hook)
       
       # Replace Pkg in loaded_modules with the guard
       Base.loaded_modules[_tlang_pkg_id] = _TlangGuardPkg
     catch err
       # Suppress any startup errors so Julia doesn't fail to launch
     end
     atreplinit() do repl
       @async begin
         sleep(0.1)
         if isdefined(repl, :interface)
           repl.interface.modes[1].prompt = "jl> "
         end
       end
     end
     using Pkg
     end # if isinteractive()
|};
  Buffer.contents buf

let python_guard_shim_script tool =
  Printf.sprintf "#!/usr/bin/env sh\nprintf '%%s\\n' %S >&2\nexit 1\n"
    (debug_subshell_guard_message "Python" (tool ^ " install"))

let python_pip_guard_module_content () =
  Printf.sprintf
    "raise SystemExit(%S)\n"
    (debug_subshell_guard_message "Python" "python -m pip")

let prepare_python_debug_guards base_dir =
  let root_dir = Filename.concat base_dir ".t_debug_guard" in
  let bin_dir = Filename.concat root_dir "bin" in
  let python_dir = Filename.concat root_dir "python" in
  if not (Sys.file_exists root_dir) then Unix.mkdir root_dir 0o755;
  if not (Sys.file_exists bin_dir) then Unix.mkdir bin_dir 0o755;
  if not (Sys.file_exists python_dir) then Unix.mkdir python_dir 0o755;
  List.iter
    (fun tool ->
      let path = Filename.concat bin_dir tool in
      write_text_file path (python_guard_shim_script tool);
      Unix.chmod path 0o755)
    python_package_manager_shim_names;
  write_text_file (Filename.concat python_dir "pip.py") (python_pip_guard_module_content ());
  { root_dir; bin_dir; python_dir }

let rec remove_path_recursively path =
  if Sys.file_exists path then
    if Sys.is_directory path then (
      Sys.readdir path
      |> Array.iter (fun entry -> remove_path_recursively (Filename.concat path entry));
      Unix.rmdir path
    ) else Sys.remove path

let make_subprocess_env overrides =
  let tbl = Hashtbl.create 32 in
  Array.iter
    (fun entry ->
      match String.index_opt entry '=' with
      | None -> ()
      | Some idx ->
          (* Split on the first '=' so values keep any additional '=' bytes. *)
          let key = String.sub entry 0 idx in
          let value = String.sub entry (idx + 1) (String.length entry - idx - 1) in
          Hashtbl.replace tbl key value)
    (Unix.environment ());
  List.iter (fun (key, value) -> Hashtbl.replace tbl key value) overrides;
  Hashtbl.fold (fun key value acc -> (key ^ "=" ^ value) :: acc) tbl []
  |> List.sort String.compare |> Array.of_list

let run_shell_command_with_env shell_cmd overrides =
  let envp = make_subprocess_env overrides in
  let pid =
    Unix.create_process_env "/bin/sh" [| "/bin/sh"; "-c"; shell_cmd |] envp
      Unix.stdin Unix.stdout Unix.stderr
  in
  snd (Unix.waitpid [] pid)

(* 
--# Read Pipeline Node Artifact
--#
--# Reads and returns the contents of a ComputedNode. For in-memory pipelines,
--# returns the dynamically computed value directly from the registry. For built
--# pipelines, reads the materialized artifact from the latest (or specified) 
--# build log.
--# Use `which_log` to read from a specific historical build ("time travel").
--#
--# @name read_node
--# @param node :: ComputedNode The ComputedNode object to read (e.g. `p.node_name`).
--# @param which_log :: String (Optional) A regex pattern to match a specific build log filename.
--# @return :: Any The deserialized artifact value, or the in-memory value.
--# @family pipeline
--# @seealso read_pipeline, build_pipeline, inspect_pipeline
--# @export
*)
let register env =
  (* Helper to extract an argument from a named/positional list.
     @param name The name of the argument (for named calls).
     @param pos The 1-indexed position of the argument (for positional calls).
     @param default Fallback value if the argument is missing. *)
  let extract_arg name pos default args =
    match List.assoc_opt (Some name) args with
    | Some v -> v
    | None ->
        let positionals = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
        match nth_safe (pos - 1) positionals with
        | Some v -> v
        | None -> default
  in

  let run_interactive_subshell ?env cn =
    let cn = !Ast.computed_node_resolver cn in
    let runtime = String.lowercase_ascii cn.cn_runtime in
    if runtime <> "python" && runtime <> "r" && runtime <> "julia" then
      Error.value_error (Printf.sprintf "debug_node: only R, Python, and Julia nodes are supported for interactive debugging. Node '%s' has unsupported runtime '%s'." cn.cn_name cn.cn_runtime)
    else (
      let dependencies =
        if cn.cn_dependencies = [] then
          (match Builder.latest_logged_computed_node cn.cn_name with
           | Some logged -> logged.cn_dependencies
           | None -> [])
        else cn.cn_dependencies
      in

      (* Find custom node env vars in evaluated pipelines *)
      let node_env_vars =
        match env with
        | None -> []
        | Some e ->
            let bindings = Ast.Env.bindings e in
            let rec find_in_pipelines = function
              | [] -> []
              | (_, Ast.VPipeline p) :: rest ->
                  (match List.assoc_opt cn.cn_name p.p_env_vars with
                   | Some vars -> vars
                   | None -> find_in_pipelines rest)
              | _ :: rest -> find_in_pipelines rest
            in
            find_in_pipelines bindings
      in

      (* Gather custom environment variables for the subshell *)
      let printed_env_vars = ref [] in
      let subshell_env_overrides = ref [] in
      List.iter (fun (name, v) ->
        let v_str =
          match v with
          | Ast.VString s -> s
          | Ast.VInt n -> string_of_int n
          | Ast.VFloat f -> string_of_float f
          | Ast.VBool b -> string_of_bool b
          | _ -> Pretty_print.pretty_print_value v
        in
        subshell_env_overrides := (name, v_str) :: !subshell_env_overrides;
        printed_env_vars := (name, v_str) :: !printed_env_vars
      ) node_env_vars;

      (* Gather upstream dependency information but do NOT set env vars *)
      let resolved_deps = ref [] in
      List.iter (fun dep_name ->
        match Builder.latest_logged_computed_node dep_name with
        | Some dep_cn ->
            if dep_cn.cn_path <> "" && dep_cn.cn_path <> "<unbuilt>" then (
              let store_dir = Filename.dirname dep_cn.cn_path in
              resolved_deps := (dep_name, store_dir, dep_cn.cn_serializer) :: !resolved_deps
            )
        | None -> ()
      ) dependencies;

      Printf.printf "==================================================\n%!";
      Printf.printf "Debugging Node: %s (Runtime: %s)\n%!" cn.cn_name cn.cn_runtime;
      Printf.printf "==================================================\n%!";
      if !printed_env_vars <> [] then (
        Printf.printf "Environment variables set for custom node configuration:\n%!";
        List.iter (fun (name, value) ->
          Printf.printf "  - %s = %s\n%!" name value
        ) !printed_env_vars;
        Printf.printf "\n%!"
      );
      if !resolved_deps <> [] then (
        Printf.printf "Upstream dependencies:\n%!";
        List.iter (fun (name, path, _serializer) ->
          Printf.printf "  - %s (Path: %s)\n%!" name path
        ) !resolved_deps;
        Printf.printf "\n%!"
      );

      let julia_package_path =
        match Diff.detect_repo_root () with
        | Some root ->
            let path = Filename.concat (Filename.concat root "jl-package") "Project.toml" in
            if Sys.file_exists path then Some (Filename.dirname path) else None
        | None -> None
      in
      let cleanup_paths = ref [] in
      let shell_cmd =
        let clean_deps = List.map (fun (name, _, _) -> name) !resolved_deps in
        let csv_deps = List.filter_map (fun (name, _, ser) ->
          if String.lowercase_ascii ser = "csv" then Some name else None) !resolved_deps in
        match String.lowercase_ascii cn.cn_runtime with
        | "python" ->
            Printf.printf "Starting interactive Python REPL...\n%!";
            Printf.printf "Tip: Load upstream dependencies in Python using:\n%!";
            Printf.printf "  import tlang\n%!";
            List.iter (fun dep ->
              Printf.printf "  %s = tlang.read_node(\"%s\")\n%!" dep dep
            ) clean_deps;
            if clean_deps = [] then
              Printf.printf "  # No upstream dependencies. You can import tlang: import tlang\n%!";

            (* Write temporary startup file to customize python prompt *)
            let startup_path = Filename.concat (Sys.getcwd ()) ".t_debug_startup.py" in
            let guard_root = Filename.concat (Sys.getcwd ()) ".t_debug_guard" in
            (try
               let guards = prepare_python_debug_guards (Sys.getcwd ()) in
               write_text_file startup_path "import sys\nsys.ps1 = 'py> '\nsys.ps2 = 'py... '\n";
               cleanup_paths := startup_path :: guards.root_dir :: !cleanup_paths;
               let existing_path = try Sys.getenv "PATH" with Not_found -> "" in
               let existing_pythonpath = try Sys.getenv "PYTHONPATH" with Not_found -> "" in
               let pythonpath =
                 if existing_pythonpath = "" then guards.python_dir
                 else guards.python_dir ^ ":" ^ existing_pythonpath
               in
               subshell_env_overrides :=
                 ("PYTHONSTARTUP", startup_path)
                 :: ("PATH", guards.bin_dir ^ ":" ^ existing_path)
                 :: ("PYTHONPATH", pythonpath)
                 :: !subshell_env_overrides
             with _ ->
               (try remove_path_recursively startup_path with _ -> ());
               (try remove_path_recursively guard_root with _ -> ()));

            "python -i"
        | "r" ->
            Printf.printf "Starting interactive R REPL...\n%!";
            Printf.printf "Tip: Load upstream dependencies in R using:\n%!";
            Printf.printf "  library(tlang)\n%!";
            List.iter (fun dep ->
              Printf.printf "  %s <- read_node(\"%s\")\n%!" dep dep
            ) clean_deps;
            if clean_deps = [] then
              Printf.printf "  # No upstream dependencies. You can load tlang: library(tlang)\n%!";

            (* Write temporary startup file to customize R prompt *)
            (try
               let startup_path = Filename.concat (Sys.getcwd ()) ".t_debug_startup.R" in
               write_text_file startup_path (r_debug_startup_content ());
               cleanup_paths := startup_path :: !cleanup_paths;
               subshell_env_overrides :=
                 ("R_PROFILE_USER", startup_path) :: !subshell_env_overrides
             with _ -> ());

            "R --no-save --quiet"
        | "julia" ->
            Printf.printf "Starting interactive Julia REPL...\n%!";
            Printf.printf "Tip: Load upstream dependencies in Julia using:\n%!";
            Printf.printf "  using tlang\n%!";
            if csv_deps <> [] then
              Printf.printf "  using CSV, DataFrames  # required for CSV nodes\n%!";
            List.iter (fun dep ->
              Printf.printf "  %s = read_node(\"%s\")\n%!" dep dep
            ) clean_deps;
            if clean_deps = [] then
             Printf.printf "  # No upstream dependencies. You can load tlang: using tlang\n%!";

            (* Write temporary startup file to customize Julia prompt *)
            let startup_path = Filename.concat (Sys.getcwd ()) ".t_debug_startup.jl" in
            let startup_ready =
              try
                write_text_file startup_path (julia_debug_startup_content julia_package_path);
                cleanup_paths := startup_path :: !cleanup_paths;
                true
              with _ ->
                (try remove_path_recursively startup_path with _ -> ());
                false
            in
            if startup_ready then
              Printf.sprintf "julia -i -e %S" (Printf.sprintf "include(%S)" startup_path)
            else "julia -i"
        | _ ->
            Printf.printf "Starting interactive bash subshell...\n%!";
            "bash"
      in
      Printf.printf "Press Ctrl+D or exit to return to T REPL.\n";
      Printf.printf "==================================================\n\n%!";
      flush stdout;
      let status = run_shell_command_with_env shell_cmd !subshell_env_overrides in

      (* Clean up temporary startup files *)
      List.iter (fun path -> try remove_path_recursively path with _ -> ()) !cleanup_paths;

      Printf.printf "\n==================================================\n%!";
      Printf.printf "Exited subshell (status: %s). Returning to T REPL.\n%!"
        (match status with
         | Unix.WEXITED n -> Printf.sprintf "exit %d" n
         | Unix.WSIGNALED n -> Printf.sprintf "signaled %d" n
         | Unix.WSTOPPED n -> Printf.sprintf "stopped %d" n);
      Printf.printf "==================================================\n%!";
      flush stdout;
      VNA NAGeneric
    )
  in

(*
--# Interactively Debug a Pipeline Node
--#
--# Spawns an interactive debug subshell (Python, R, or Julia REPL) for the specified
--# ComputedNode. The REPL is pre-configured with the node's environment variables and
--# package environment, and displays instructions for loading upstream dependency artifacts.
--#
--# @name debug_node
--# @param node :: ComputedNode The ComputedNode object to debug (e.g. `p.node_name`).
--# @return :: NA (Generates an interactive console session).
--# @example
--#   debug_node(p.etl_clean)
--# @family pipeline
--# @export
*)
  let debug_fn named_args env =
    match extract_arg "node" 1 (VNA NAGeneric) named_args with
    | VComputedNode cn ->
        run_interactive_subshell ~env cn
    | _ -> Error.type_error "debug_node: expected a ComputedNode."
  in

  let read_fn named_args _env =

    match extract_arg "node" 1 ((VNA NAGeneric)) named_args with
    | VComputedNode cn ->
        let which_log_provided =
          match extract_arg "which_log" 2 (VNA NAGeneric) named_args with
          | VString _ -> true
          | _ -> false
        in
        begin
          let resolved_cn = !Ast.computed_node_resolver cn in
          let is_built = resolved_cn.cn_path <> "" && resolved_cn.cn_path <> "<unbuilt>" in
          let is_in_memory_placeholder v =
            match v with
            | VNodeResult { v = VComputedNode inner; _ } -> inner.cn_path = "" || inner.cn_path = "<unbuilt>"
            | _ -> false
          in
          match Ast.get_in_memory_node_value_for_cn cn with
          | Some v when not which_log_provided && not is_built && not (is_in_memory_placeholder v) -> v
          | _ ->
            let cn_or_err =
              if which_log_provided then
                let log_name = match extract_arg "which_log" 2 (VNA NAGeneric) named_args with VString s -> s | _ -> "" in
                (match Builder.latest_logged_computed_node ~log_name_pattern:log_name cn.cn_name with
                 | Some logged_cn ->
                     let cn_path = if cn.cn_path = "<unbuilt>" || cn.cn_path = "" then logged_cn.cn_path else cn.cn_path in
                     let cn_class = if cn.cn_class = "Unknown" then logged_cn.cn_class else cn.cn_class in
                     let cn_runtime = if cn.cn_runtime = "T" || cn.cn_runtime = "" then logged_cn.cn_runtime else cn.cn_runtime in
                     let cn_serializer = if cn.cn_serializer = "default" || cn.cn_serializer = "" then logged_cn.cn_serializer else cn.cn_serializer in
                     Ok { cn with cn_path; cn_class; cn_runtime; cn_serializer }
                 | None ->
                     Error (Error.make_error KeyError (Printf.sprintf "Node `%s` not found in BuildLog." cn.cn_name)))
              else Ok resolved_cn
            in
            (match cn_or_err with
             | Error err -> err
             | Ok cn ->
                  if cn.cn_path = "<unbuilt>" && not which_log_provided then
                    (match Ast.get_in_memory_node_value_for_cn cn with
                     | Some v when not (is_in_memory_placeholder v) -> v
                     | _ ->
                         Error.make_error FileError (Printf.sprintf "read_node: Failed to deserialize T node `%s`: Sys_error(\"<unbuilt>: No such file or directory\")" cn.cn_name))
                  else
                    let raw_val = Builder.logged_node_value cn.cn_name cn in
                    match Ast.get_in_memory_node_value_for_cn cn with
                    | Some (VNodeResult { diagnostics = d; _ }) ->
                        let build_diag = Builder.logged_node_diagnostics ~value:raw_val cn.cn_name cn in
                        let merged = {
                          d with
                          nd_error = build_diag.nd_error;
                          nd_recovered = build_diag.nd_recovered;
                        } in
                        VNodeResult { v = raw_val; node_name = cn.cn_name; diagnostics = merged }
                    | _ ->
                        Builder.wrap_with_diagnostics cn.cn_name cn raw_val)
        end
    | VString _ ->
        Error.type_error "read_node: expected a ComputedNode for argument 'node', but got String. Use read_node(p.node_name) instead."
    | VSymbol name as other ->
        let node_name =
          if String.length name > 6 && String.sub name 0 6 = "<noop:" then
            let len = String.length name in
            Some (String.sub name 6 (len - 7))
          else None
        in
        (match node_name with
         | Some real_name ->
             Error.type_error (Printf.sprintf "read_node: cannot read node `%s` because it was skipped (noop=true) or was a downstream dependency of a skipped node." real_name)
         | None ->
             Error.type_error (Printf.sprintf "read_node: expected a ComputedNode for argument 'node', but got %s." (Utils.type_name other)))
    | VPipeline _ ->
        Error.type_error "read_node: expected a ComputedNode for argument 'node', but got Pipeline. Use read_node(p.node_name) instead."
    | VNA _ -> Error.make_error ValueError "read_node: requires a ComputedNode object."
    | other ->
        Error.type_error (Printf.sprintf "read_node: expected a ComputedNode for argument 'node', but got %s." (Utils.type_name other))
  in

(*
--# Read Pipeline Metadata
--#
--# Returns a dictionary describing a materialized in-memory pipeline,
--# including per-node diagnostics and the aggregated diagnostics summary.
--#
--# @name read_pipeline
--# @param p :: Pipeline The pipeline to inspect.
--# @return :: Dict A dictionary with node metadata and diagnostics.
--# @family pipeline
--# @seealso read_node, explain
--# @export
*)
  let read_pipeline_fn named_args _env =
    match extract_arg "p" 1 (VNA NAGeneric) named_args with
    | VPipeline p ->
        let pipeline_nodes =
          Builder.merge_pipeline_nodes_with_latest_log p
        in
        let pipeline_diagnostics =
          Builder.merge_pipeline_node_diagnostics_with_latest_log p
        in
        let nodes =
          VList
            (List.map (fun (name, value) ->
                let diagnostics =
                  match List.assoc_opt name pipeline_diagnostics with
                  | Some diagnostics -> diagnostics
                  | None -> Ast.Utils.empty_node_diagnostics
                in
                (None, VDict [
                  ("name", VString name);
                  ("value", value);
                  ("diagnostics", Ast.Utils.node_diagnostics_to_value diagnostics);
                ]))
              pipeline_nodes)
        in
        VDict [
          ("nodes", nodes);
          ("diagnostics", Ast.Utils.pipeline_diagnostics_to_value pipeline_diagnostics);
        ]
    | _ -> Error.type_error "read_pipeline: expected a Pipeline."
  in

(*
--# Inspect Pipeline Node Metadata
--#
--# Returns a dictionary with metadata about a computed node, including its
--# name, runtime, artifact path, serializer, class, and dependencies.
--#
--# @name inspect_node
--# @param node :: ComputedNode A computed node value (e.g. from a built pipeline).
--# @return :: Dict A dictionary with keys = name, runtime, path, serializer, class, dependencies.
--# @family pipeline
--# @seealso read_node, rebuild_node
--# @export
*)
  let inspect_fn named_args _env =
    match extract_arg "node" 1 (VNA NAGeneric) named_args with
    | VComputedNode cn ->
        let cn = !Ast.computed_node_resolver cn in
        VDict [
          ("name", VString cn.cn_name);
          ("runtime", VString cn.cn_runtime);
          ("path", VString cn.cn_path);
          ("serializer", VString cn.cn_serializer);
          ("class", VString cn.cn_class);
          ("dependencies", VList (List.map (fun d -> (None, VString d)) cn.cn_dependencies))
        ]
    | VError err ->
        let node_name =
          match List.assoc_opt "node_name" err.context with
          | Some (VString name) -> Some name
          | _ -> None
        in
        (match node_name with
         | Some name ->
             Error.type_error (Printf.sprintf "inspect_node: expected a ComputedNode, but got an Error because node `%s` failed. To inspect its error, query its properties (e.g. `node.error_msg` or `node.error`) or use `read_node(p, \"%s\")`." name name)
         | None ->
             Error.type_error "inspect_node: expected a ComputedNode, but got an Error value. If this is a failing pipeline node, use its error properties or read_node() to inspect it.")
    | VSymbol name as other ->
        let node_name =
          if String.length name > 6 && String.sub name 0 6 = "<noop:" then
            let len = String.length name in
            Some (String.sub name 6 (len - 7))
          else None
        in
        (match node_name with
         | Some real_name ->
             Error.type_error (Printf.sprintf "inspect_node: expected a ComputedNode, but node `%s` was skipped (noop=true) or was a downstream dependency of a skipped node, so no output was generated." real_name)
         | None ->
             Error.type_error (Printf.sprintf "inspect_node: expected a ComputedNode, but got %s." (Utils.type_name other)))
    | other ->
        Error.type_error (Printf.sprintf "inspect_node: expected a ComputedNode, but got %s." (Utils.type_name other))
  in

(*
--# Rebuild a Pipeline Node
--#
--# Rebuilds a single node from the pipeline Nix expression and returns an
--# updated ComputedNode with the new artifact path.
--#
--# @name rebuild_node
--# @param node :: ComputedNode A computed node value to rebuild.
--# @return :: ComputedNode An updated ComputedNode pointing to the rebuilt artifact.
--# @family pipeline
--# @seealso read_node, inspect_node
--# @export
*)
  let rebuild_fn named_args _env =
    match extract_arg "node" 1 (VNA NAGeneric) named_args with
    | VComputedNode cn ->
        let quoted_name = Filename.quote cn.cn_name in
        let cmd = Printf.sprintf "nix-build --impure _pipeline/pipeline.nix -A %s --no-out-link 2>&1" quoted_name in
        (match Builder_utils.run_command_capture cmd with
         | Ok (Unix.WEXITED 0, output) ->
             let store_path = String.trim output in
             let new_path = Filename.concat (Filename.concat store_path cn.cn_name) "artifact" in
             VComputedNode { cn with cn_path = new_path }
         | Ok (_, output) -> Error.make_error GenericError (Printf.sprintf "rebuild_node failed: %s" output)
         | Error msg -> Error.make_error GenericError (Printf.sprintf "Failed to run nix-build: %s" msg))
    | _ -> Error.type_error "rebuild_node: expected a ComputedNode."
  in

  let _ = 
    Ast.node_resolver := (fun name ->
      match Builder.read_node name with
      | VError _ -> None
      | v -> Some v);
    Ast.computed_node_resolver := (fun cn ->
      match Builder.latest_logged_computed_node cn.cn_name with
      | Some logged_cn ->
          let cn_class =
            if cn.cn_class = "Unknown" || cn.cn_class = "" then logged_cn.cn_class else cn.cn_class
          in
          let cn_path =
            if logged_cn.cn_path = "" then ""
            else if cn.cn_path = "<unbuilt>" || cn.cn_path = ""
            then logged_cn.cn_path
            else cn.cn_path
          in
          let cn_runtime =
            if cn.cn_runtime = "T" || cn.cn_runtime = ""
            then logged_cn.cn_runtime
            else cn.cn_runtime
          in
          let cn_serializer =
            if cn.cn_serializer = "default" || cn.cn_serializer = ""
            then logged_cn.cn_serializer
            else cn.cn_serializer
          in
          { cn with cn_path; cn_class; cn_runtime; cn_serializer }
      | None -> cn)
  in

(*
--# Suppress Diagnostics for a Node
--#
--# Silences all captured warnings for the current node in the console summary.
--# Warnings remain accessible programmatically via `read_node()` or `read_pipeline()`.
--# Use this to reduce noise from known warnings during data processing (e.g., NAs in filter).
--#
--# @name suppress_warnings
--# @param value :: Any The value or expression to wrap. Usually call it at the end of a node definition.
--# @return :: Any The original value, signaling the evaluator to suppress diagnostic output.
--# @family pipeline
--# @export
*)
  let suppress_warnings_fn args _env =
    match args with
    | [VNodeResult nr] ->
        VNodeResult { nr with diagnostics = { nr.diagnostics with nd_warnings_suppressed = true } }
    | [v] -> 
        Eval.request_warning_suppression ();
        v
    | _ -> Error.arity_error_named "suppress_warnings" 1 (List.length args)
  in

  env
  |> Env.add "read_node" (make_builtin_named ~name:"read_node" ~variadic:true 1 read_fn)
  |> Env.add "read_pipeline" (make_builtin_named ~name:"read_pipeline" ~variadic:true 1 read_pipeline_fn)
  |> Env.add "inspect_node" (make_builtin_named ~name:"inspect_node" ~unwrap:false ~variadic:true 1 inspect_fn)
  |> Env.add "rebuild_node" (make_builtin_named ~name:"rebuild_node" ~unwrap:false ~variadic:true 1 rebuild_fn)
  |> Env.add "suppress_warnings" (make_builtin ~name:"suppress_warnings" ~unwrap:false 1 suppress_warnings_fn)
  |> Env.add "debug_node" (make_builtin_named ~name:"debug_node" ~unwrap:false ~variadic:true 1 debug_fn)
