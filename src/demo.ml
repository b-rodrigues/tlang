(* src/demo.ml *)
(* Interactive CLI demo for the T language *)

open Ast

(* Raised instead of calling `exit` so test runners can catch a demo
   failure as a normal exception. The `t demo` entry point in repl.ml
   converts it back to exit code 1. *)
exception Demo_failed of string

let color_reset = "\027[0m"
let color_bold = "\027[1m"
let color_cyan = "\027[1;36m"
let color_green = "\027[1;32m"
let color_yellow = "\027[1;33m"
let color_blue = "\027[1;34m"
let color_magenta = "\027[1;35m"
let color_gray = "\027[90m"

let clear_screen ~headless =
  if not headless then begin
    Printf.printf "\027[H\027[2J";
    flush stdout
  end

let wait_step ~headless prompt_msg =
  if headless then ()
  else begin
    Printf.printf "\n%s%s%s " color_cyan prompt_msg color_reset;
    flush stdout;
    let line = try read_line () with End_of_file -> "q" in
    if String.trim line = "q" || String.trim line = ":q" then begin
      Printf.printf "\n%sExiting demo. Have fun with T!%s\n\n" color_gray color_reset;
      exit 0
    end;
    clear_screen ~headless
  end

let banner title =
  let width = max 2 (68 - String.length title) in
  Printf.printf "%s%s── %s %s%s\n\n" color_bold color_blue title (String.make width '-') color_reset

let print_code code =
  Printf.printf "%s%s%s\n" color_yellow code color_reset

let print_val v =
  match v with
  | VDataFrame _ | VPipeline _ | VDict _ ->
      Printf.printf "%s\n" (Pretty_print.pretty_print_value v)
  | _ ->
      Printf.printf "%s\n" (Utils.value_to_string v)

let eval_snippet env code =
  let (v, env') = Check_utils.parse_and_eval ~failfast:false Typecheck.Strict env code in
  match v with
  | VError _ ->
      Printf.eprintf "\n%sError during demo evaluation:%s %s\n" color_magenta color_reset (Utils.value_to_string v);
      raise (Demo_failed (Utils.value_to_string v))
  | _ -> (v, env')

let run ?(headless = false) ?start_repl env =
  clear_screen ~headless;
  banner "T Interactive Demo: Reproducible Pipelines in Action";
  Printf.printf "Welcome to the T interactive demo! We will demonstrate:\n";
  Printf.printf "  1. Defining a pipeline DAG as a first-class program value\n";
  Printf.printf "  2. Inspecting the DAG structure with pipeline_nodes & pipeline_deps\n";
  Printf.printf "  3. Building the pipeline hermetically into the Nix store\n";
  Printf.printf "  4. Inspecting in-memory artifacts via Apache Arrow IPC\n";
  Printf.printf "  5. Growing the pipeline & observing content-addressed Nix caching\n";
  Printf.printf "  6. First-class errors & polyglot soft-failures (no pipeline aborts)\n";
  Printf.printf "  7. Interactive REPL handoff\n\n";
  Printf.printf "%sNote: This demo uses pure T nodes for quick demonstration, but pipelines\nwork identically across Python (`pyn`), R (`rn`), and Julia (`jln`) runtimes.%s\n" color_gray color_reset;

  wait_step ~headless "[Press Enter to see the initial pipeline...]";

  (* --- Step 1: Initial Pipeline --- *)
  banner "Step 1: The Pipeline as a First-Class Value";
  Printf.printf "In T, pipelines are typed, immutable values defined directly in code:\n\n";

  let initial_code =
    "p = pipeline {\n" ^
    "  raw = node(\n" ^
    "    command = [\n" ^
    "      [time: 1, signal: 0.1, group: \"A\"],\n" ^
    "      [time: 2, signal: 0.8, group: \"B\"]\n" ^
    "    ] |> to_dataframe,\n" ^
    "    serializer = ^ipc\n" ^
    "  )\n" ^
    "}"
  in
  print_code initial_code;
  Printf.printf "\nNotice:\n";
  Printf.printf "  • Pipeline is bound to variable `p`; node `raw` outputs an Arrow DataFrame.\n";
  Printf.printf "  • Serialized via Apache Arrow IPC (`^ipc`); foreign nodes (jln, pyn, rn) share this syntax.\n";

  let (_, env) = eval_snippet env initial_code in

  wait_step ~headless "[Press Enter to inspect the pipeline DAG...]";

  (* --- Step 2: Inspecting the Pipeline --- *)
  banner "Step 2: Inspecting the Pipeline DAG";
  Printf.printf "Pipelines are fully introspectable program values.\n\n";
  Printf.printf "Active nodes (%spipeline_nodes(p)%s):\n" color_bold color_reset;
  let (nodes_val, env) = eval_snippet env "pipeline_nodes(p)" in
  print_val nodes_val;

  Printf.printf "\nGraph edges (%spipeline_deps(p)%s):\n" color_bold color_reset;
  let (deps1_val, env) = eval_snippet env "pipeline_deps(p)" in
  print_val deps1_val;

  Printf.printf "\nNode `raw` has no dependencies. (Tip: %sexplain(p)%s views full AST & diagnostics)\n" color_bold color_reset;

  wait_step ~headless "[Press Enter to build pipeline (runs pure Nix derivations)...]";

  (* --- Step 3: Building the Pipeline --- *)
  banner "Step 3: Building the Pipeline into the Nix Store";
  Printf.printf "Now we build the pipeline with %sbuild_pipeline(p)%s:\n" color_bold color_reset;
  Printf.printf "%s⚡ Building pipeline into /nix/store... Please wait while Nix evaluates derivations.%s\n\n" color_yellow color_reset;
  flush stdout;

  let (_, env) = eval_snippet env "build_pipeline(p)" in

  Printf.printf "\n%s✔ Build completed! Artifacts are safely locked in /nix/store.%s\n" color_green color_reset;

  wait_step ~headless "[Press Enter to inspect the generated artifact...]";

  (* --- Step 4: Inspecting Artifacts --- *)
  banner "Step 4: Inspecting Artifacts in Memory";
  Printf.printf "Read artifact into memory via Arrow IPC with %sread_node(p.raw)%s:\n\n" color_bold color_reset;
  let (df_val, env) = eval_snippet env "read_node(p.raw)" in
  print_val df_val;

  Printf.printf "\nInspect Nix store metadata with %sinspect_node(p.raw)%s:\n\n" color_bold color_reset;
  let (inspect_val, env) = eval_snippet env "inspect_node(p.raw)" in
  print_val inspect_val;

  Printf.printf "Zero manual I/O: no read.csv or data-formatting glue code required.\n";

  wait_step ~headless "[Press Enter to grow the pipeline and observe Nix caching...]";

  (* --- Step 5: Growing the Pipeline & Nix Caching --- *)
  banner "Step 5: Growing the Pipeline & Content Caching";
  Printf.printf "Extend `p` with a downstream `filtered` node consuming `raw`:\n\n";

  let grown_code =
    "p := pipeline {\n" ^
    "  raw = node(\n" ^
    "    command = [ [time: 1, signal: 0.1, group: \"A\"], [time: 2, signal: 0.8, group: \"B\"] ] |> to_dataframe,\n" ^
    "    serializer = ^ipc\n" ^
    "  )\n" ^
    "  filtered = node(\n" ^
    "    command = raw |> filter($signal > 0.5),\n" ^
    "    deserializer = [raw: ^ipc],\n" ^
    "    serializer = ^ipc\n" ^
    "  )\n" ^
    "}"
  in
  print_code grown_code;

  let (_, env) = eval_snippet env grown_code in

  Printf.printf "\nNow we re-run %sbuild_pipeline(p)%s:\n" color_bold color_reset;
  Printf.printf "%s⚡ Building pipeline into /nix/store... Checking cache hashes.%s\n\n" color_yellow color_reset;
  flush stdout;

  let (_, env) = eval_snippet env "build_pipeline(p)" in

  Printf.printf "\n%sCaching in action:%s Node `raw` was %s(cached)%s. Only `filtered` was computed!\n"
    color_bold color_reset color_green color_reset;

  wait_step ~headless "[Press Enter to see first-class error handling in pipelines...]";

  (* --- Step 6: First-Class Errors & Polyglot Soft-Failures --- *)
  banner "Step 6: First-Class Errors & Polyglot Soft-Failures";
  Printf.printf "In T, errors don't crash pipelines. Let's add a failing node `anomaly`:\n\n";

  let error_code =
    "p := pipeline {\n" ^
    "  raw = node(\n" ^
    "    command = [ [time: 1, signal: 0.1, group: \"A\"], [time: 2, signal: 0.8, group: \"B\"] ] |> to_dataframe,\n" ^
    "    serializer = ^ipc\n" ^
    "  )\n" ^
    "  filtered = node(\n" ^
    "    command = raw |> filter($signal > 0.5),\n" ^
    "    deserializer = [raw: ^ipc],\n" ^
    "    serializer = ^ipc\n" ^
    "  )\n" ^
    "  anomaly = node(\n" ^
    "    command = error(\"Threshold exceeded: signal > 0.5 detected\")\n" ^
    "  )\n" ^
    "}"
  in
  print_code error_code;

  let (_, env) = eval_snippet env error_code in

  Printf.printf "\nRebuilding pipeline with %sbuild_pipeline(p)%s:\n" color_bold color_reset;
  Printf.printf "%s⚡ Building pipeline into /nix/store... Capturing errors at sandbox boundary.%s\n\n" color_yellow color_reset;
  flush stdout;

  let (_, env) = eval_snippet env "build_pipeline(p)" in

  Printf.printf "\n%sPolyglot Resilience:%s\n" color_bold color_reset;
  Printf.printf "  • The pipeline build finished without crashing! Independent nodes succeeded.\n";
  Printf.printf "  • Uncaught errors in Python (raise), R (stop), Julia (error), or T are captured\n";
  Printf.printf "    as first-class `VError` artifacts and inspectable via %sread_node(p.anomaly)%s.\n" color_bold color_reset;

  wait_step ~headless "[Press Enter to drop into the interactive REPL...]";

  (* --- Step 7: REPL Handoff --- *)
  banner "Step 7: Interactive Exploration";
  Printf.printf "The demo is complete! All computed pipeline states are retained in memory.\n\n";
  Printf.printf "Try exploring in the REPL:\n";
  Printf.printf "  %sexplain(p)%s               -- View full pipeline tree & diagnostics\n" color_bold color_reset;
  Printf.printf "  %spipeline_nodes(p)%s        -- List active node names\n" color_bold color_reset;
  Printf.printf "  %sread_node(p.raw)%s         -- Read raw Arrow dataset\n" color_bold color_reset;
  Printf.printf "  %sread_node(p.filtered)%s    -- Read filtered Arrow dataset\n" color_bold color_reset;
  Printf.printf "  %sread_node(p.anomaly)%s     -- Read the captured error value\n" color_bold color_reset;
  Printf.printf "  %s:quit%s                    -- Exit the REPL\n\n" color_bold color_reset;

  match start_repl with
  | Some repl_fn when not headless ->
      repl_fn env
  | _ ->
      Printf.printf "%sDemo finished successfully.%s\n\n" color_green color_reset
