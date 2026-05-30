open Ast

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
    "if isinteractive()\n\
     const _tlang_pkg_id = Base.PkgId(Base.UUID(\"44cfe95a-1eb2-52ea-b672-e2afdf69b78f\"), \"Pkg\")\n\
     const _tlang_real_pkg = Base.require(_tlang_pkg_id)\n\
     const _tlang_repl_id = Base.PkgId(Base.UUID(\"3fa0cd96-eef1-5676-8a61-b3b8758bbffb\"), \"REPL\")\n\
     const _tlang_repl = Base.require(_tlang_repl_id)\n\
     function _tlang_install_packages_hook(pkgs::Vector{Symbol})\n\
     \  pkg_str = join(string.(pkgs), \", \")\n\
     \  println(\" │ Packages [\", pkg_str, \"] not found, but packages named [\", pkg_str, \"] are available from\")\n\
     \  println(\" │ a registry.\")\n\
     \  println(\" │ Install packages?\")\n\
     \  println(\" │   (project) pkg> add \", pkg_str)\n\
     \  print(\" └ (y/n) [y]: \")\n\
     \  flush(stdout)\n\
     \  response = lowercase(strip(readline(stdin)))\n\
     \  if response == \"\" || response == \"y\" || response == \"yes\"\n\
     \    println(\"\\nDon't use interactive package installation in this T Julia debug subshell.\")\n\
     \    println(\"Declare packages in tproject.toml, run `t update`, and re-enter `nix develop`.\\n\")\n\
     \  else\n\
     \    println(\"Cancelled.\")\n\
     \  end\n\
     \  return false\n\
     end\n\
     pushfirst!(_tlang_repl.install_packages_hooks, _tlang_install_packages_hook)\n";
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
     end\n\
     const Pkg = _TlangGuardPkg\n\
     Base.loaded_modules[_tlang_pkg_id] = _TlangGuardPkg\n\
     atreplinit() do repl\n\
       @async begin\n\
         sleep(0.1)\n\
         if isdefined(repl, :interface)\n\
           repl.interface.modes[1].prompt = \"jl> \"\n\
         end\n\
       end\n\
     end\n\
     end # if isinteractive()\n"
    (debug_subshell_guard_message "Julia" "Pkg.add()")
    (debug_subshell_guard_message "Julia" "Pkg.rm()")
    (debug_subshell_guard_message "Julia" "Pkg.update()")
    (debug_subshell_guard_message "Julia" "Pkg.develop()");
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
        if List.length positionals >= pos then List.nth positionals (pos - 1)
        else default
  in

  let read_fn named_args _env =

    match extract_arg "node" 1 ((VNA NAGeneric)) named_args with
    | VComputedNode cn ->
        let which_log_provided =
          match extract_arg "which_log" 2 (VNA NAGeneric) named_args with
          | VString _ -> true
          | _ -> false
        in
        if not which_log_provided && Hashtbl.mem Ast.in_memory_node_values cn.cn_name then
          Hashtbl.find Ast.in_memory_node_values cn.cn_name
        else
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
            else Ok (!Ast.computed_node_resolver cn)
          in
          (match cn_or_err with
           | Error err -> err
           | Ok cn ->
               if cn.cn_path = "<unbuilt>" && not which_log_provided then
                 (match Hashtbl.find_opt Ast.in_memory_node_values cn.cn_name with
                  | Some v -> v
                  | None ->
                      Error.make_error FileError (Printf.sprintf "read_node: Failed to deserialize T node `%s`: Sys_error(\"<unbuilt>: No such file or directory\")" cn.cn_name))
               else
                 let raw_val = Builder.logged_node_value cn.cn_name cn in
                 Builder.wrap_with_diagnostics cn.cn_name cn raw_val)
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
