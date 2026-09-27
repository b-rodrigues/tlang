(* src/demo.ml *)
(* Interactive CLI demo for the T language *)

open Ast

let color_reset = "\027[0m"
let color_bold = "\027[1m"
let color_cyan = "\027[1;36m"
let color_green = "\027[1;32m"
let color_yellow = "\027[1;33m"
let color_blue = "\027[1;34m"
let color_magenta = "\027[1;35m"
let color_gray = "\027[90m"

let wait_step ~headless prompt_msg =
  if headless then ()
  else begin
    Printf.printf "\n%s%s%s " color_cyan prompt_msg color_reset;
    flush stdout;
    let line = try read_line () with End_of_file -> "q" in
    if String.trim line = "q" || String.trim line = ":q" then begin
      Printf.printf "\n%sExiting demo. Have fun with T!%s\n\n" color_gray color_reset;
      exit 0
    end
  end

let banner title =
  Printf.printf "\n%s%s======================================================================%s\n" color_bold color_blue color_reset;
  Printf.printf "%s%s  %s%s\n" color_bold color_blue title color_reset;
  Printf.printf "%s%s======================================================================%s\n\n" color_bold color_blue color_reset

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
      exit 1
  | _ -> (v, env')

let run ?(headless = false) ?start_repl env =
  banner "T Interactive Demo: Reproducible Pipelines in Action";
  Printf.printf "Welcome to the T interactive demo!\n";
  Printf.printf "In this walkthrough, we will demonstrate:\n";
  Printf.printf "  1. Defining a computation graph (pipeline) as a first-class program value\n";
  Printf.printf "  2. Inspecting the pipeline DAG (nodes, dependencies, structure)\n";
  Printf.printf "  3. Building the pipeline into content-addressed Nix store artifacts\n";
  Printf.printf "  4. Inspecting artifacts in-memory via Apache Arrow IPC\n";
  Printf.printf "  5. Growing the pipeline by adding a downstream transformation node\n";
  Printf.printf "  6. Observing content-addressed caching (zero wasted recomputation)\n";
  Printf.printf "  7. Dropping directly into the live interactive REPL\n";

  wait_step ~headless "[Press Enter to see the initial pipeline...]";

  (* --- Step 1: Initial Pipeline --- *)
  banner "Step 1: The Pipeline as a First-Class Value";
  Printf.printf "In T, pipelines are not external configuration files (like Makefiles or YAML).\n";
  Printf.printf "They are typed, immutable program structures defined directly in the language.\n\n";

  let initial_code =
    "p = pipeline {\n" ^
    "  raw = node(\n" ^
    "    command = [\n" ^
    "      [time: 1, signal: 0.098, group: \"A\"],\n" ^
    "      [time: 2, signal: 0.235, group: \"A\"],\n" ^
    "      [time: 3, signal: 0.541, group: \"B\"],\n" ^
    "      [time: 4, signal: 0.812, group: \"B\"]\n" ^
    "    ] |> to_dataframe,\n" ^
    "    serializer = ^ipc\n" ^
    "  )\n" ^
    "}"
  in
  print_code initial_code;
  Printf.printf "\nNotice:\n";
  Printf.printf "  • The pipeline is bound to the regular variable `p`.\n";
  Printf.printf "  • Node `raw` builds a DataFrame and serializes it using Apache Arrow IPC (`^ipc`).\n";
  Printf.printf "  • Foreign nodes (`jln`, `pyn`, `rn`) share this exact same syntax.\n";

  let (_, env) = eval_snippet env initial_code in

  wait_step ~headless "[Press Enter to inspect the pipeline DAG...]";

  (* --- Step 2: Inspecting the Pipeline --- *)
  banner "Step 2: Inspecting the Pipeline DAG";
  Printf.printf "Because pipelines are first-class values, they are completely introspectable.\n";
  Printf.printf "Let's inspect the active nodes with %spipeline_nodes(p)%s:\n\n" color_bold color_reset;

  let (nodes_val, env) = eval_snippet env "pipeline_nodes(p)" in
  print_val nodes_val;

  Printf.printf "\nNow let's inspect the full graph tree with %sexplain(p)%s:\n\n" color_bold color_reset;
  let (explain_val, env) = eval_snippet env "explain(p)" in
  print_val explain_val;

  Printf.printf "Notice that `raw` has output_kind 'ComputedNode' with 0 errors and empty dependencies.\n";

  wait_step ~headless "[Press Enter to build the pipeline into the Nix store...]";

  (* --- Step 3: Building the Pipeline --- *)
  banner "Step 3: Building the Pipeline into the Nix Store";
  Printf.printf "Now we build the pipeline with %sbuild_pipeline(p)%s:\n\n" color_bold color_reset;

  let (_, env) = eval_snippet env "build_pipeline(p)" in

  Printf.printf "\n%s✔ Build completed! Output artifacts are stored in the content-addressed Nix store.%s\n" color_green color_reset;

  wait_step ~headless "[Press Enter to inspect the generated artifact...]";

  (* --- Step 4: Inspecting Artifacts --- *)
  banner "Step 4: Inspecting Artifacts in Memory";
  Printf.printf "We can read any node's artifact directly into the T environment using %sread_node(p.raw)%s.\n" color_bold color_reset;
  Printf.printf "T automatically uses the node's serializer (^ipc) to load the Apache Arrow table:\n\n";

  let (df_val, env) = eval_snippet env "read_node(p.raw)" in
  print_val df_val;

  Printf.printf "\nWe can also inspect the node's content-addressed Nix store path with %sinspect_node(p.raw)%s:\n\n" color_bold color_reset;
  let (inspect_val, env) = eval_snippet env "inspect_node(p.raw)" in
  print_val inspect_val;

  Printf.printf "Zero manual I/O: no read.csv or to_csv glue code was written.\n";

  wait_step ~headless "[Press Enter to grow the pipeline by adding a downstream node...]";

  (* --- Step 5: Growing the Pipeline --- *)
  banner "Step 5: Growing the Pipeline";
  Printf.printf "Real-world analyses evolve continuously. In T, pipelines can be extended naturally.\n";
  Printf.printf "Let's add a downstream node `filtered` that consumes `raw`, filters for signal > 0.2,\n";
  Printf.printf "and adds an `active` boolean column:\n\n";

  let grown_code =
    "p := pipeline {\n" ^
    "  raw = node(\n" ^
    "    command = [\n" ^
    "      [time: 1, signal: 0.098, group: \"A\"],\n" ^
    "      [time: 2, signal: 0.235, group: \"A\"],\n" ^
    "      [time: 3, signal: 0.541, group: \"B\"],\n" ^
    "      [time: 4, signal: 0.812, group: \"B\"]\n" ^
    "    ] |> to_dataframe,\n" ^
    "    serializer = ^ipc\n" ^
    "  )\n\n" ^
    "  filtered = node(\n" ^
    "    command = raw |> filter($signal > 0.2) |> mutate($active = true),\n" ^
    "    deserializer = [raw: ^ipc],\n" ^
    "    serializer = ^ipc\n" ^
    "  )\n" ^
    "}"
  in
  print_code grown_code;

  let (_, env) = eval_snippet env grown_code in

  Printf.printf "\nLet's verify the updated dependency structure with %spipeline_deps(p)%s:\n\n" color_bold color_reset;
  let (deps_val, env) = eval_snippet env "pipeline_deps(p)" in
  print_val deps_val;

  wait_step ~headless "[Press Enter to build the extended pipeline and observe Nix caching...]";

  (* --- Step 6: Content-Addressed Caching --- *)
  banner "Step 6: Content-Addressed Caching in Action";
  Printf.printf "Now we re-run %sbuild_pipeline(p)%s on our grown pipeline:\n\n" color_bold color_reset;

  let (_, env) = eval_snippet env "build_pipeline(p)" in

  Printf.printf "\n%sPay close attention to the build summary above:%s\n" color_bold color_reset;
  Printf.printf "  • %s(cached: raw)%s — Node `raw` was NOT recomputed! T recognized that its code\n" color_green color_reset;
  Printf.printf "    and inputs did not change, resolving the artifact from the Nix store instantly.\n";
  Printf.printf "  • Only the newly added node %sfiltered%s was built.\n" color_bold color_reset;
  Printf.printf "This caching applies equally across Julia simulations, Python ML models, and R reports.\n";

  wait_step ~headless "[Press Enter to inspect the new filtered artifact...]";

  (* --- Step 7: Inspecting the New Artifact --- *)
  banner "Step 7: Inspecting the New Artifact";
  Printf.printf "Let's inspect the output of the new node with %sread_node(p.filtered)%s:\n\n" color_bold color_reset;

  let (filtered_df, env) = eval_snippet env "read_node(p.filtered)" in
  print_val filtered_df;

  Printf.printf "\nAnd verify that both nodes are active with %spipeline_nodes(p)%s:\n\n" color_bold color_reset;
  let (nodes2_val, env) = eval_snippet env "pipeline_nodes(p)" in
  print_val nodes2_val;

  wait_step ~headless "[Press Enter to drop into the interactive REPL...]";

  (* --- Step 8: REPL Handoff --- *)
  banner "Step 8: Interactive Exploration";
  Printf.printf "The demo is complete! All computed pipeline states are retained in memory.\n\n";
  Printf.printf "Try exploring in the REPL:\n";
  Printf.printf "  %sexplain(p)%s               -- View full pipeline tree\n" color_bold color_reset;
  Printf.printf "  %spipeline_nodes(p)%s        -- List node names\n" color_bold color_reset;
  Printf.printf "  %sread_node(p.raw)%s         -- Read raw dataset\n" color_bold color_reset;
  Printf.printf "  %sread_node(p.filtered)%s    -- Read filtered dataset\n" color_bold color_reset;
  Printf.printf "  %s:quit%s                    -- Exit the REPL\n\n" color_bold color_reset;

  match start_repl with
  | Some repl_fn when not headless ->
      repl_fn env
  | _ ->
      Printf.printf "%sDemo finished successfully.%s\n\n" color_green color_reset
