open Ast

(*
--# Render a plot node and open it locally
--#
--# Builds or reuses an R/Python plot artifact, renders it into `_pipeline/`,
--# and opens the rendered image with the command configured in
--# `tproject.toml` under `[visualization-tool]`.
--#
--# @name show_plot
--# @param plot :: Any A pipeline node, built node, or `read_node()` result for a plot-producing node.
--# @return :: String The local rendered image path.
--# @family core
--# @seealso read_node, build_pipeline
--# @export
*)

let supported_plot_class = function
  | "ggplot" | "matplotlib" | "plotnine" | "seaborn" | "plotly" | "altair" -> true
  | _ -> false

let rendered_plot_filename = "plot.png"
let rendered_plot_width_inches = 8
let rendered_plot_height_inches = 6
let rendered_plot_dpi = 144

type viewer_tool = {
  command : string;
  configured : bool;
}

let runtime_of_plot_class = function
  | "ggplot" -> Some "R"
  | "matplotlib" | "plotnine" | "seaborn" | "plotly" | "altair" -> Some "Python"
  | _ -> None

let is_blank s =
  String.trim s = ""

let contains_whitespace s =
  let rec loop i =
    if i >= String.length s then false
    else
      match s.[i] with
      | ' ' | '\t' | '\n' | '\r' -> true
      | _ -> loop (i + 1)
  in
  loop 0

let read_first_line path =
  try
    let ic = open_in path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () -> Ok (input_line ic |> String.trim))
  with
  | Sys_error msg ->
      Error (Printf.sprintf "show_plot: failed to read `%s`: %s" path msg)
  | End_of_file ->
      Error (Printf.sprintf "show_plot: `%s` is empty." path)

let copy_file src dst =
  try
    let ic = open_in_bin src in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () ->
        let oc = open_out_bin dst in
        Fun.protect
          ~finally:(fun () -> close_out_noerr oc)
          (fun () ->
            let buffer = Bytes.create 8192 in
            let rec loop () =
              let read_count = input ic buffer 0 (Bytes.length buffer) in
              if read_count > 0 then begin
                output oc buffer 0 read_count;
                loop ()
              end
            in
            loop ()));
    Ok ()
  with
  | Sys_error msg ->
      Error
        (Printf.sprintf
           "show_plot: failed to copy `%s` to `%s`: %s"
           src dst msg)

let flush_output_streams () =
  flush stdout;
  flush stderr

let configured_visualization_tool ?project_root () =
  let root =
    match project_root with
    | Some root -> root
    | None -> Builder_utils.get_project_root ()
  in
  let tproject_path = Filename.concat root "tproject.toml" in
  if not (Sys.file_exists tproject_path) then
    Ok None
  else
    try
      let ic = open_in tproject_path in
      let content =
        Fun.protect
          ~finally:(fun () -> close_in_noerr ic)
          (fun () -> really_input_string ic (in_channel_length ic))
      in
      match Toml_parser.parse_tproject_toml content with
      | Ok cfg ->
          let command = String.trim cfg.proj_visualization_tool in
          if command = "" then Ok None
          else if contains_whitespace command then
            Error
              "show_plot: `[visualization-tool].command` must be a single executable name or absolute path without shell arguments."
          else
            Ok (Some command)
      | Error msg -> Error ("show_plot: failed to parse tproject.toml: " ^ msg)
    with Sys_error msg ->
      Error ("show_plot: failed to read tproject.toml: " ^ msg)

let default_visualization_tool () =
  (* Prefer `open` when available (macOS); otherwise fall back to Linux's
     `xdg-open`. *)
  if Builder_utils.command_exists "open" then Some "open"
  else if Builder_utils.command_exists "xdg-open" then Some "xdg-open"
  else None

let visualization_tool ?project_root () =
  match configured_visualization_tool ?project_root () with
  | Error _ as err -> err
  | Ok (Some tool) -> Ok (Some { command = tool; configured = true })
  | Ok None ->
      Ok (Option.map (fun tool -> { command = tool; configured = false }) (default_visualization_tool ()))

let open_rendered_plot viewer path =
  let tool = viewer.command in
  let executable =
    if Filename.is_relative tool then
      if Builder_utils.command_exists tool then Some tool else None
    else if Sys.file_exists tool then Some tool else None
  in
  match executable with
  | None ->
      if viewer.configured then
        Error
          (Printf.sprintf "show_plot: visualization tool `%s` was not found. Update `[visualization-tool].command` or open `%s` manually." tool path)
      else
        Error
          (Printf.sprintf "show_plot: no default visualization tool was found (`open`/`xdg-open`). Configure `[visualization-tool].command` or open `%s` manually." path)
  | Some exec ->
      (try
         let devnull = Unix.openfile "/dev/null" [Unix.O_RDWR] 0 in
         let read_fd, write_fd = Unix.pipe () in
         match Unix.fork () with
         | 0 ->
             Unix.close read_fd;
             ignore (Unix.setsid ());
             (try
                let tool_pid = Unix.create_process exec [| exec; path |] devnull devnull devnull in
                if tool_pid <= 0 then raise (Unix.Unix_error (Unix.ECHILD, "create_process", exec));
                let ok = Bytes.of_string "OK" in
                ignore (Unix.write write_fd ok 0 (Bytes.length ok));
                Unix.close write_fd;
                Unix.close devnull;
                Stdlib.exit 0
              with Unix.Unix_error (child_err, _, _) ->
                let msg = Bytes.of_string (Unix.error_message child_err) in
                ignore (Unix.write write_fd msg 0 (Bytes.length msg));
                Unix.close write_fd;
                Unix.close devnull;
                Stdlib.exit 1)
         | fork_pid ->
             Unix.close write_fd;
             Unix.close devnull;
             let (_, status) = Unix.waitpid [] fork_pid in
             let buffer = Bytes.create 256 in
             let read_count = Unix.read read_fd buffer 0 (Bytes.length buffer) in
             Unix.close read_fd;
             let child_message = Bytes.sub_string buffer 0 read_count in
             (match status with
              | Unix.WEXITED 0 when child_message = "OK" -> Ok ()
              | Unix.WEXITED 0 | Unix.WEXITED _ ->
                  let detail =
                    if child_message = "" then "visualization tool process did not report successful launch"
                    else child_message
                  in
                  Error
                    (Printf.sprintf "show_plot: failed to launch `%s` for `%s`: %s"
                       exec path detail)
              | Unix.WSIGNALED signal | Unix.WSTOPPED signal ->
                  Error
                    (Printf.sprintf "show_plot: failed to launch `%s` for `%s`: process terminated with signal %d"
                       exec path signal))
       with Unix.Unix_error (err, _, _) ->
          Error
            (Printf.sprintf "show_plot: failed to launch `%s` for `%s`: %s"
               exec path (Unix.error_message err)))

let render_script_for_r _artifact_path =
  Printf.sprintf
    {|
plot_obj <- readRDS(Sys.getenv("ARTIFACT_PATH"))
if (!inherits(plot_obj, "ggplot")) {
  stop("show_plot currently supports ggplot objects for R nodes.")
}
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("show_plot requires `ggplot2` in [r-dependencies].packages.")
}
ggplot2::ggsave(
  filename = file.path(Sys.getenv("out"), %S),
  plot = plot_obj,
  width = %d,
  height = %d,
  dpi = %d,
  units = "in"
)
|}
    rendered_plot_filename
    rendered_plot_width_inches
    rendered_plot_height_inches
    rendered_plot_dpi

let render_script_for_python _artifact_path =
  Printf.sprintf
    {|
import os
artifact_path = os.environ["ARTIFACT_PATH"]
output_path = os.path.join(os.environ["out"], %S)

def deserialize(path):
    # Try standard pickle first for maximum compatibility
    try:
        import pickle
        with open(path, "rb") as f:
            return pickle.load(f)
    except Exception:
        pass

    # Try dill next for environments that serialized with dill.
    try:
        import dill
        with open(path, "rb") as f:
            return dill.load(f)
    except Exception:
        pass
    
    # Try cloudpickle as last resort
    import cloudpickle as cp
    with open(path, "rb") as f:
        return cp.load(f)

plot_obj = deserialize(artifact_path)

try:
    import matplotlib
except (ImportError, ModuleNotFoundError) as exc:
    raise ImportError("show_plot requires `matplotlib` in [py-dependencies].packages.") from exc

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.figure import Figure as MatplotlibFigure
from matplotlib.axes import Axes as MatplotlibAxes

try:
    from plotnine.ggplot import ggplot as PlotnineGGPlot
except (ImportError, ModuleNotFoundError):
    PlotnineGGPlot = None

if PlotnineGGPlot is not None and isinstance(plot_obj, PlotnineGGPlot):
    fig = plot_obj.draw()
    fig.savefig(output_path, dpi=%d, bbox_inches="tight")
    plt.close(fig)
# Axes is checked before Figure so single-axes objects render their parent
# figure directly without changing the public show_plot contract.
elif isinstance(plot_obj, MatplotlibAxes):
    plot_obj.figure.savefig(output_path, dpi=%d, bbox_inches="tight")
elif isinstance(plot_obj, MatplotlibFigure):
    plot_obj.savefig(output_path, dpi=%d, bbox_inches="tight")
elif type(plot_obj).__module__.startswith("seaborn"):
    fig = getattr(plot_obj, "fig", getattr(plot_obj, "figure", None))
    if fig:
        fig.savefig(output_path, dpi=%d, bbox_inches="tight")
    else:
        raise TypeError(f"show_plot failed to extract figure from seaborn object of type {type(plot_obj).__name__}")
elif type(plot_obj).__module__.startswith("plotly"):
    try:
        import plotly.io as pio
        # static image export requires 'kaleido'
        pio.write_image(plot_obj, output_path, format="png")
    except Exception as exc:
        raise RuntimeError(f"show_plot: plotly renderer failed. Ensure 'kaleido' is in [py-dependencies].packages. Error: {str(exc)}")
elif type(plot_obj).__module__.startswith("altair"):
    try:
        import vl_convert as vlc
        spec = plot_obj.to_json()
        png_data = vlc.vegalite_to_png(vl_spec=spec)
        with open(output_path, "wb") as f:
            f.write(png_data)
    except Exception as exc:
        try:
             plot_obj.save(output_path)
        except Exception:
             raise RuntimeError(f"show_plot: altair renderer failed. Ensure 'vl-convert-python' or 'altair_saver' is in [py-dependencies].packages. Error: {str(exc)}")
else:
    raise TypeError("show_plot currently supports matplotlib Figure/Axes, plotnine ggplot, seaborn Grid, plotly Figure, and altair Chart objects for Python nodes.")
|}
    rendered_plot_filename
    rendered_plot_dpi
    rendered_plot_dpi
    rendered_plot_dpi
    rendered_plot_dpi

let render_script_for_class class_name artifact_path =
  match runtime_of_plot_class class_name with
  | Some "R" -> Ok (render_script_for_r artifact_path, "render_plot.R", "R")
  | Some "Python" -> Ok (render_script_for_python artifact_path, "render_plot.py", "Python")
  | _ ->
      Error
        (Printf.sprintf "show_plot: unsupported plot class `%s`. Expected ggplot, matplotlib, plotnine, seaborn, plotly, or altair." class_name)

let render_nix_expression ~project_root ~runtime ~script_name ~script_content ~artifact_path =
  let tproject_path = Filename.concat project_root "tproject.toml" in
  Printf.sprintf
    {|
{ system ? builtins.currentSystem }:
let
  flake = builtins.getFlake (toString %S);
  pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
  toml = if builtins.pathExists %S then builtins.fromTOML (builtins.readFile %S) else {};
  rPackagesList = (toml.r-dependencies or {}).packages or [];
  r-env = pkgs.rWrapper.override {
    packages = builtins.map (p: pkgs.rPackages.${p}) rPackagesList;
  };
  pyDeps = toml.py-dependencies or toml.python-dependencies or {};
  pyVersion = pyDeps.version or "python3";
  pyPackagesList = pyDeps.packages or [];
  py-env = pkgs.${pyVersion}.withPackages (ps: builtins.map (p: ps.${p}) pyPackagesList);
  artifact = builtins.path { name = "plot-artifact"; path = %S; };
in
pkgs.stdenv.mkDerivation {
  name = "show-plot-render";
  dontUnpack = true;
  buildInputs = [ %s ];
  MPLCONFIGDIR = ".";
  ARTIFACT_PATH = "${artifact}";
  buildCommand = ''
    mkdir -p "$out"
    export out="$out"
    cat <<'EOF' > "$TMPDIR/%s"
%s
EOF
    %s "$TMPDIR/%s"
  '';
}
|}
    project_root
    tproject_path
    tproject_path
    artifact_path
    (if runtime = "R" then "r-env" else "py-env")
    script_name
    script_content
    (if runtime = "R" then "Rscript" else "python")
    script_name

let computed_node_from_registry node_name =
  let env_name = "T_NODE_" ^ node_name in
  match Sys.getenv_opt env_name with
  | Some node_dir when not (is_blank node_dir) ->
      let artifact_path = Filename.concat node_dir "artifact" in
      let class_path = Filename.concat node_dir "class" in
      (match read_first_line class_path with
       | Error _ as err -> err
       | Ok class_name ->
           if not (Sys.file_exists artifact_path) then
             Error
               (Printf.sprintf "show_plot: artifact `%s` for node `%s` is missing." artifact_path node_name)
           else if not (supported_plot_class class_name) then
             Error
               (Printf.sprintf "show_plot: node `%s` has unsupported plot class `%s`." node_name class_name)
           else
             Ok {
               cn_name = node_name;
               cn_runtime = (match runtime_of_plot_class class_name with Some runtime -> runtime | None -> "unknown");
               cn_path = artifact_path;
               cn_serializer = "default";
               cn_class = class_name;
               cn_dependencies = [];
             })
  | _ ->
      match Builder_logs.get_logs () with
      | [] ->
          Error
            (Printf.sprintf "show_plot: no build logs found for node `%s`. Build the pipeline first or pass an unbuilt rn()/pyn() node." node_name)
      | latest_log :: _ ->
          (match Builder_logs.read_log (Filename.concat Builder_utils.pipeline_dir latest_log) with
           | Error msg ->
               Error
                 (Printf.sprintf "show_plot: failed to read build log `%s`: %s" latest_log msg)
           | Ok entries ->
               (match List.assoc_opt node_name entries with
                | Some cn when supported_plot_class cn.cn_class -> Ok cn
                | Some _ ->
                    Error
                      (Printf.sprintf "show_plot: node `%s` is not a supported plot artifact." node_name)
                | None ->
                    Error
                      (Printf.sprintf "show_plot: node `%s` was not found in `%s`." node_name latest_log)))

let build_ephemeral_plot_node node_name (un : unbuilt_node) =
  let pipeline =
    {
      p_nodes = [ (node_name, VNode un) ];
      p_exprs = [ (node_name, Ast.mk_expr (Value (VNode un))) ];
      p_deps = [ (node_name, []) ];
      p_imports = [];
      p_runtimes = [ (node_name, un.un_runtime) ];
      p_serializers = [ (node_name, un.un_serializer) ];
      p_deserializers = [ (node_name, un.un_deserializer) ];
      p_env_vars = [ (node_name, un.un_env_vars) ];
      p_args = [ (node_name, un.un_args) ];
      p_shells = [ (node_name, un.un_shell) ];
      p_shell_args = [ (node_name, un.un_shell_args) ];
      p_functions = [ (node_name, un.un_functions) ];
      p_includes = [ (node_name, un.un_includes) ];
      p_noops = [ (node_name, un.un_noop) ];
      p_scripts = [ (node_name, un.un_script) ];
      p_explicit_deps = [ (node_name, un.un_dependencies) ];
      p_node_diagnostics = [ (node_name, Utils.empty_node_diagnostics) ];
    }
  in
  match Builder.populate_pipeline ~build:true pipeline with
  | Ok _ -> computed_node_from_registry node_name
  | Error msg -> Error ("show_plot: failed to build plot node in Nix sandbox: " ^ msg)

let resolve_plot_node input_value =
  let temp_name =
    Printf.sprintf "show_plot_%s_%d" (Builder_utils.get_timestamp ()) (Unix.getpid ())
  in
  match input_value with
  | VNode un ->
      if un.un_runtime <> "R" && un.un_runtime <> "Python" then
        Error
          "show_plot: only rn()/pyn() nodes are supported. Pass an R/Python plot node or a built plot node."
      else
        build_ephemeral_plot_node temp_name un
  | VComputedNode cn when cn.cn_path <> "<unbuilt>" && supported_plot_class cn.cn_class ->
      Ok cn
  | VComputedNode _ ->
      Error
        "show_plot: expected a built plot node, an rn()/pyn() node, or a `read_node()` result for a built plot."
  | VNodeResult { v = VComputedNode cn; _ } when cn.cn_path <> "<unbuilt>" && supported_plot_class cn.cn_class ->
      Ok cn
  | VNodeResult { node_name; _ } ->
      computed_node_from_registry node_name
  | _ ->
      Error
        "show_plot: expected a plot node, built plot node, or a `read_node()` result for a built plot."

let render_plot_artifact cn =
  if not (Sys.file_exists cn.cn_path) then
    Error
      (Printf.sprintf "show_plot: artifact `%s` does not exist. Rebuild the plot node first." cn.cn_path)
  else
    match render_script_for_class cn.cn_class cn.cn_path with
    | Error _ as err -> err
    | Ok (script_content, script_name, runtime) ->
        let project_root = Builder_utils.get_project_root () in
        Builder_utils.ensure_pipeline_dir ();
        let render_prefix =
          Printf.sprintf "show_plot_render_%s_%d" (Builder_utils.get_timestamp ()) (Unix.getpid ())
        in
        let nix_path = Filename.concat Builder_utils.pipeline_dir (render_prefix ^ ".nix") in
        let local_plot_path = Filename.concat Builder_utils.pipeline_dir (render_prefix ^ ".png") in
        let nix_content =
          render_nix_expression ~project_root ~runtime ~script_name ~script_content ~artifact_path:cn.cn_path
        in
        match Builder_utils.write_file nix_path nix_content with
        | Error msg ->
            Error
              (Printf.sprintf "show_plot: failed to write `%s`: %s" nix_path msg)
        | Ok () ->
            if not (Builder_utils.command_exists "nix-build") then
              Error "show_plot requires `nix-build` to be available."
            else
              let argv = [| "nix-build"; "--impure"; nix_path; "--no-out-link" |] in
              (match Builder_utils.run_command_argv_capture argv with
               | Error msg ->
                   Error ("show_plot: failed to render plot in Nix sandbox: " ^ msg)
               | Ok out_path ->
                   let rendered_path = Filename.concat out_path rendered_plot_filename in
                   if not (Sys.file_exists rendered_path) then
                     Error
                       (Printf.sprintf "show_plot: render succeeded but `%s` was not produced." rendered_path)
                   else begin
                      (match copy_file rendered_path local_plot_path with
                       | Error _ as err -> err
                       | Ok () ->
                           flush_output_streams ();
                           match visualization_tool ~project_root () with
                           | Error _ as err -> err
                           | Ok None -> Ok local_plot_path
                           | Ok (Some viewer) ->
                               (match open_rendered_plot viewer local_plot_path with
                                | Ok () -> Ok local_plot_path
                                | Error _ as err -> err))
                    end)

let register env =
  let show_plot_fn named_args _env =
    match named_args with
    | [(_, plot)] ->
        (match resolve_plot_node plot with
          | Error msg -> Error.make_error ValueError msg
          | Ok cn ->
              (match render_plot_artifact cn with
               | Ok path ->
                   flush_output_streams ();
                   VString path
               | Error msg -> Error.make_error RuntimeError msg))
    | _ ->
        Error.arity_error_named "show_plot" 1 (List.length named_args)
  in
  Env.add "show_plot"
    (make_builtin_named ~name:"show_plot" ~unwrap:false 1 show_plot_fn)
    env
