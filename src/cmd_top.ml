open Builder_utils

let pid_path = "_pipeline/top.pid"

let rec safe_select read write except timeout =
  try Unix.select read write except timeout
  with Unix.Unix_error (Unix.EINTR, _, _) -> safe_select read write except timeout

let rec safe_read fd buf ofs len =
  try Unix.read fd buf ofs len
  with Unix.Unix_error (Unix.EINTR, _, _) -> safe_read fd buf ofs len

let rec safe_waitpid flags pid =
  try Unix.waitpid flags pid
  with Unix.Unix_error (Unix.EINTR, _, _) -> safe_waitpid flags pid

let ansi_reset = "\027[0m"
let ansi_bold = "\027[1m"
let ansi_red = "\027[31m"
let ansi_green = "\027[32m"
let ansi_yellow = "\027[33m"
let ansi_cyan = "\027[36m"
let ansi_gray = "\027[90m"
let ansi_clear = "\027[H\027[J"
let ansi_hide_cursor = "\027[?25l"
let ansi_show_cursor = "\027[?25h"

let rec wait_q_key () =
  match safe_select [Unix.stdin] [] [] 0.5 with
  | [], _, _ -> wait_q_key ()
  | _ ->
      let buf = Bytes.create 1 in
      try
        let n = safe_read Unix.stdin buf 0 1 in
        if n > 0 && Bytes.get buf 0 <> 'q' then wait_q_key ()
      with _ -> ()

let wait_keypress_raw_q () =
  let term_attr = try Some (Unix.tcgetattr Unix.stdin) with _ -> None in
  let restore_term () =
    match term_attr with
    | Some attr -> (try Unix.tcsetattr Unix.stdin Unix.TCSADRAIN attr with _ -> ())
    | None -> ()
  in
  let _old_sigint = Sys.signal Sys.sigint (Sys.Signal_handle (fun _ ->
    Printf.eprintf "%s" ansi_show_cursor;
    restore_term ();
    exit 0
  )) in
  (try
     (match term_attr with
      | Some attr ->
          let raw = { attr with Unix.c_icanon = false; Unix.c_echo = false } in
          Unix.tcsetattr Unix.stdin Unix.TCSADRAIN raw
      | None -> ());
     wait_q_key ()
   with _ -> ());
  restore_term ()

type status_data = {
  sd_done : bool;
  sd_total : int;
  sd_built : int;
  sd_building : int;
  sd_errored : int;
  sd_soft_failed : int;
  sd_warnings : int;
  sd_nodes : (string * string * float * float * string * string list) list;
  sd_error : string option;
}

let read_status_file path =
  try
    if not (Sys.file_exists path) then None
    else
      let json = Yojson.Safe.from_file path in
      let open Yojson.Safe.Util in
      let sd_done = match json |> member "done" with `Bool b -> b | _ -> false in
      let sd_total = match json |> member "total" with `Int i -> i | _ -> 0 in
      let sd_built = match json |> member "built" with `Int i -> i | _ -> 0 in
      let sd_building = match json |> member "building" with `Int i -> i | _ -> 0 in
      let sd_errored = match json |> member "errored" with `Int i -> i | _ -> 0 in
      let sd_soft_failed = match json |> member "soft_failed" with `Int i -> i | _ -> 0 in
      let sd_warnings = match json |> member "warnings" with `Int i -> i | _ -> 0 in
      let sd_error = match json |> member "error" with `String s -> Some s | _ -> None in
      let sd_nodes = match json |> member "nodes" with
        | `Assoc pairs ->
            List.map (fun (name, node_json) ->
              let status = match node_json |> member "status" with `String s -> s | _ -> "Unknown" in
              let duration = match node_json |> member "duration" with `Float f -> f | `Int i -> float_of_int i | _ -> 0.0 in
              let start_time = match node_json |> member "start_time" with `Float f -> f | `Int i -> float_of_int i | _ -> 0.0 in
              let runtime = match node_json |> member "runtime" with `String s -> s | _ -> "" in
              let deps = match node_json |> member "dependencies" with
                | `List items -> List.filter_map (function `String s -> Some s | _ -> None) items
                | _ -> []
              in
              (name, status, duration, start_time, runtime, deps)
            ) pairs
        | _ -> []
      in
      Some { sd_done; sd_total; sd_built; sd_building; sd_errored; sd_soft_failed; sd_warnings; sd_nodes; sd_error }
  with _ -> None

let node_color = function
  | "Completed" -> ansi_green
  | "Completed with warning" -> ansi_yellow
  | "Cached" -> ansi_green
  | "Fetching" -> ansi_cyan
  | "Building" -> ansi_cyan
  | "Pending" -> ansi_gray
  | "Errored" -> ansi_red
  | "SoftFailed" -> ansi_red
  | _ -> ansi_reset

let utf8_len s =
  let len = String.length s in
  let count = ref 0 in
  for i = 0 to len - 1 do
    let b = Char.code (String.get s i) in
    if b < 0x80 || b >= 0xC0 then
      incr count
  done;
  !count

let utf8_sub s w =
  let len = String.length s in
  let count = ref 0 in
  let byte_idx = ref 0 in
  while !byte_idx < len && !count < w do
    let b = Char.code (String.get s !byte_idx) in
    if b < 0x80 || b >= 0xC0 then (
      if !count < w then (
        incr count;
        incr byte_idx;
        while !byte_idx < len && (let b2 = Char.code (String.get s !byte_idx) in b2 >= 0x80 && b2 < 0xC0) do
          incr byte_idx
        done
      )
    ) else (
      incr byte_idx
    )
  done;
  String.sub s 0 !byte_idx

let ellipsize width s =
  if width <= 0 then ""
  else if utf8_len s <= width then s
  else if width = 1 then "…"
  else utf8_sub s (width - 1) ^ "…"

let pad_right width s =
  let clipped = ellipsize width s in
  clipped ^ String.make (max 0 (width - utf8_len clipped)) ' '

let pad_left width s =
  let clipped = ellipsize width s in
  String.make (max 0 (width - utf8_len clipped)) ' ' ^ clipped

let node_icon = function
  | "Completed" -> "✓"
  | "Completed with warning" -> "⚠"
  | "Cached" -> "✓"
  | "Fetching" -> "⇣"
  | "Building" -> "⟳"
  | "Pending" -> "·"
  | "Errored" -> "✗"
  | "SoftFailed" -> "✗"
  | _ -> "?"

let render_tui data =
  let buf = Buffer.create 2048 in
  Buffer.add_string buf ansi_clear;
  Buffer.add_string buf ansi_hide_cursor;

  let now = Unix.localtime (Unix.time ()) in
  Printf.ksprintf (Buffer.add_string buf)
    "%s┌── T Pipeline Monitor %s%02d:%02d:%02d%s                                        ┐\n"
    ansi_bold ansi_reset now.tm_hour now.tm_min now.tm_sec ansi_bold;
  Buffer.add_string buf ansi_reset;

  Printf.ksprintf (Buffer.add_string buf)
    "│ Total: %-4d │ Built: %s%-5d%s │ Building: %s%-5d%s │ Errored: %s%-5d%s │ Warnings: %s%-5d%s │\n"
    data.sd_total
    ansi_green data.sd_built ansi_reset
    ansi_cyan data.sd_building ansi_reset
    ansi_red (data.sd_errored + data.sd_soft_failed) ansi_reset
    ansi_yellow data.sd_warnings ansi_reset;

  Buffer.add_string buf "├────────────────────┬────────────────┬──────────┬──────────┬────────────────────────┤\n";
  Buffer.add_string buf "│ Node               │ Status         │ Duration │ Runtime  │ Dependencies           │\n";
  Buffer.add_string buf "├────────────────────┼────────────────┼──────────┼──────────┼────────────────────────┤\n";

  List.iter (fun (name, status, duration, start_time, runtime, deps) ->
    let color = node_color status in
    let icon = node_icon status in
    let status_str = if status = "SoftFailed" then "Errored" else status in
    let display_status = pad_right 14 (Printf.sprintf "%s %s" icon status_str) in
    let name_cell = pad_right 18 name in
    let duration_str =
      let effective =
        if (status = "Building" || status = "Fetching") && start_time > 0.0 then
          Unix.gettimeofday () -. start_time
        else
          duration
      in
      if effective > 0.0 then Printf.sprintf "%.1fs" effective
      else "—"
    in
    let duration_cell = pad_left 8 duration_str in
    let runtime_cell = pad_right 8 runtime in
    let deps_str = match deps with [] -> "—" | d -> String.concat "," d in
    let deps_cell = pad_right 22 deps_str in
    Printf.ksprintf (Buffer.add_string buf) "│ %s │ %s%s%s │ %s │ %s │ %s │\n"
      name_cell color display_status ansi_reset duration_cell runtime_cell deps_cell
  ) data.sd_nodes;

  Buffer.add_string buf "└────────────────────┴────────────────┴──────────┴──────────┴────────────────────────┘\n";

  if not data.sd_done then begin
    Buffer.add_string buf ansi_gray;
    Buffer.add_string buf "Monitoring (Ctrl-C to quit)\n";
    Buffer.add_string buf ansi_reset
  end else begin
    Buffer.add_string buf ansi_bold;
    (match data.sd_error with
     | Some err ->
         Buffer.add_string buf ansi_red;
         Printf.ksprintf (Buffer.add_string buf) "\nBuild failed: %s\n" err
     | None ->
         if data.sd_errored = 0 && data.sd_soft_failed = 0 then begin
           Buffer.add_string buf ansi_green;
           Buffer.add_string buf "\nBuild completed successfully!\n"
         end else begin
           Buffer.add_string buf ansi_red;
           Buffer.add_string buf "\nBuild completed with errors.\n"
         end);
    Buffer.add_string buf ansi_reset;
    Buffer.add_string buf "Press q to quit.\n"
  end;

  Buffer.output_buffer stdout buf;
  flush stdout

let render_loading () =
  let buf = Buffer.create 1024 in
  Buffer.add_string buf ansi_clear;
  Buffer.add_string buf ansi_hide_cursor;
  let now = Unix.localtime (Unix.time ()) in
  Printf.ksprintf (Buffer.add_string buf)
    "%s┌── T Pipeline Monitor %s%02d:%02d:%02d%s                                        ┐\n"
    ansi_bold ansi_reset now.tm_hour now.tm_min now.tm_sec ansi_bold;
  Buffer.add_string buf ansi_reset;
  Buffer.add_string buf "│ Total: 0    │ Built: 0     │ Building: 0     │ Errored: 0     │ Warnings: 0     │\n";
  Buffer.add_string buf "├────────────────────┬────────────────┬──────────┬──────────┬────────────────────────┤\n";
  Buffer.add_string buf "│ Node               │ Status         │ Duration │ Runtime  │ Dependencies           │\n";
  Buffer.add_string buf "├────────────────────┼────────────────┼──────────┼──────────┼────────────────────────┤\n";
  let name_cell = pad_right 18 "" in
  let display_status = pad_right 14 "Loading..." in
  let duration_cell = pad_left 8 "" in
  let runtime_cell = pad_right 8 "" in
  let deps_cell = pad_right 22 "" in
  Printf.ksprintf (Buffer.add_string buf) "│ %s │ %s%s%s │ %s │ %s │ %s │\n"
    name_cell ansi_cyan display_status ansi_reset duration_cell runtime_cell deps_cell;
  Buffer.add_string buf "└────────────────────┴────────────────┴──────────┴──────────┴────────────────────────┘\n";
  Buffer.add_string buf ansi_gray;
  Buffer.add_string buf "Initializing pipeline build, please wait...\n";
  Buffer.add_string buf ansi_reset;
  Buffer.output_buffer stdout buf;
  flush stdout

let eval_file_and_get_pipeline filename env =
  let ch = open_in filename in
  let content =
    try
      let c = really_input_string ch (in_channel_length ch) in
      close_in ch;
      c
    with exn ->
      close_in ch;
      raise exn
  in
  let lexbuf = Lexing.from_string content in
  lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
  let program = Parser.program Lexer.token lexbuf in
  match Typecheck.validate_program ~mode:Typecheck.Strict program with
  | Error err -> Error (Pretty_print.pretty_print_value (Ast.VError err))
  | Ok () ->
      let (result, env') = Eval.eval_program program env in
      match !Ast.meta_pipeline_flatten_resolver result with
      | Ast.VPipeline p -> Ok p
      | _ ->
          let all_bindings = Ast.Env.bindings env' in
          let pipeline_bindings =
            List.filter_map (fun (name, v) ->
              match !Ast.meta_pipeline_flatten_resolver v with
              | Ast.VPipeline p -> Some (name, p)
              | _ -> None
            ) all_bindings
          in
          (match List.assoc_opt "p" pipeline_bindings, pipeline_bindings with
           | Some p, _ -> Ok p
           | None, [(_, p)] -> Ok p
           | None, [] -> Error "No pipeline value found. Ensure your file defines a pipeline and binds it to `p`."
           | None, bindings ->
               Error (Printf.sprintf "Multiple pipeline bindings found (%s). Bind the desired pipeline to `p`."
                        (String.concat ", " (List.map fst bindings))))

let cmd_top_run filename env =
  ensure_pipeline_dir ();
  let spath = Filename.concat pipeline_dir "build_status.json" in
  (try Sys.remove spath with _ -> ());

  match Unix.fork () with
  | -1 ->
      Printf.eprintf "fork failed\n";
      exit 1
  | 0 ->
      Sys.set_signal Sys.sigint Sys.Signal_default;
      Sys.set_signal Sys.sigterm Sys.Signal_default;
      let devnull = Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
      Unix.dup2 devnull Unix.stdout;
      Unix.dup2 devnull Unix.stderr;
      Unix.close devnull;
      (try
         Packages.ensure_docs_loaded ();
         match eval_file_and_get_pipeline filename env with
         | Error msg ->
             let oc = open_out spath in
             output_string oc (Printf.sprintf "{\"done\": true, \"error\": \"%s\"}\n" (Serialization.json_escape msg));
             close_out oc;
             exit 1
         | Ok p ->
             ignore (Builder.populate_pipeline ~build:true ~status_file:spath p);
             exit 0
       with exn ->
         let err = Printexc.to_string exn in
         (try
            let oc = open_out spath in
            output_string oc (Printf.sprintf "{\"done\": true, \"error\": \"%s\"}\n" (Serialization.json_escape err));
            close_out oc
          with _ -> ());
         exit 1)
  | child_pid ->
      let term_attr = try Some (Unix.tcgetattr Unix.stdin) with _ -> None in
      let restore_term () =
        match term_attr with
        | Some attr -> (try Unix.tcsetattr Unix.stdin Unix.TCSADRAIN attr with _ -> ())
        | None -> ()
      in
      let _old_sigint = Sys.signal Sys.sigint (Sys.Signal_handle (fun _ ->
        Printf.eprintf "%s" ansi_show_cursor;
        restore_term ();
        (try Unix.kill child_pid Sys.sigterm with _ -> ());
        exit 0
      )) in

      let rec loop () =
        match read_status_file spath with
        | Some data when data.sd_done ->
            render_tui data;
            wait_q_key ()
        | Some data ->
            render_tui data;
            let pid, _ = safe_waitpid [Unix.WNOHANG] child_pid in
            if pid = child_pid then (
              match read_status_file spath with
              | Some d -> render_tui d
              | None -> ();
              wait_q_key ()
            ) else (
              Unix.sleep 1;
              loop ()
            )
        | None ->
            render_loading ();
            let pid, _ = safe_waitpid [Unix.WNOHANG] child_pid in
            if pid = child_pid then ()
            else (Unix.sleep 1; loop ())
      in

      (try
         (match term_attr with
          | Some attr ->
              let raw = { attr with Unix.c_icanon = false; Unix.c_echo = false } in
              Unix.tcsetattr Unix.stdin Unix.TCSADRAIN raw
          | None -> ());
         loop ()
       with exn ->
         Printf.eprintf "t top error: %s\n" (Printexc.to_string exn);
         (try Unix.kill child_pid Sys.sigterm with _ -> ())
      );

      let _ = try safe_waitpid [] child_pid with Unix.Unix_error (Unix.ECHILD, _, _) -> (0, Unix.WEXITED 0) in
      (try Sys.remove spath with _ -> ());
      restore_term ();
      Printf.eprintf "%s" ansi_show_cursor

let cmd_top_run_background filename env =
  ensure_pipeline_dir ();
  let spath = Filename.concat pipeline_dir "build_status.json" in
  (try Sys.remove spath with _ -> ());

  match Unix.fork () with
  | -1 ->
      Printf.eprintf "fork failed\n";
      exit 1
  | 0 ->
      Sys.set_signal Sys.sigint Sys.Signal_default;
      Sys.set_signal Sys.sigterm Sys.Signal_default;
      let devnull = Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
      Unix.dup2 devnull Unix.stdout;
      Unix.dup2 devnull Unix.stderr;
      Unix.close devnull;
      at_exit (fun () -> try Sys.remove pid_path with _ -> ());
      (try
         Packages.ensure_docs_loaded ();
         match eval_file_and_get_pipeline filename env with
         | Error msg ->
             let oc = open_out spath in
             output_string oc (Printf.sprintf "{\"done\": true, \"error\": \"%s\"}\n" (Serialization.json_escape msg));
             close_out oc;
             exit 1
         | Ok p ->
             ignore (Builder.populate_pipeline ~build:true ~status_file:spath p);
             exit 0
       with exn ->
         let err = Printexc.to_string exn in
         (try
            let oc = open_out spath in
            output_string oc (Printf.sprintf "{\"done\": true, \"error\": \"%s\"}\n" (Serialization.json_escape err));
            close_out oc
          with _ -> ());
         exit 1)
  | child_pid ->
      (try
         let oc = open_out pid_path in
         output_string oc (string_of_int child_pid ^ "\n");
         close_out oc
       with _ -> ());
      Printf.printf "Build started in background (PID: %d)\n" child_pid;
      flush stdout;
      exit 0

let cmd_top_monitor _env =
  ensure_pipeline_dir ();
  let spath = Filename.concat pipeline_dir "build_status.json" in
  let child_pid =
    try
      let ic = open_in pid_path in
      let line = input_line ic in
      close_in ic;
      Some (int_of_string line)
    with _ -> None
  in
  (match child_pid with
   | Some pid ->
       let alive = (try Unix.kill pid 0; true with _ -> false) in
       if alive then
         Printf.printf "Monitoring build (PID: %d)\n" pid
       else
         Printf.printf "Build process (PID: %d) has exited.\n" pid
   | None ->
       Printf.eprintf "No background build found (no PID file at %s).\n" pid_path;
       (match read_status_file spath with
        | Some data when data.sd_done ->
            render_tui data;
            wait_keypress_raw_q ();
            Printf.eprintf "%s" ansi_show_cursor
        | _ -> ());
       exit 1);
  flush stdout;

  let term_attr = try Some (Unix.tcgetattr Unix.stdin) with _ -> None in
  let restore_term () =
    match term_attr with
    | Some attr -> (try Unix.tcsetattr Unix.stdin Unix.TCSADRAIN attr with _ -> ())
    | None -> ()
  in
  let _old_sigint = Sys.signal Sys.sigint (Sys.Signal_handle (fun _ ->
    Printf.eprintf "%s" ansi_show_cursor;
    restore_term ();
    exit 0
  )) in

  let rec loop () =
    match read_status_file spath with
    | Some data when data.sd_done ->
        render_tui data;
        wait_q_key ()
    | Some data ->
        render_tui data;
        let still_alive = match child_pid with
          | Some pid -> (try Unix.kill pid 0; true with _ -> false)
          | None -> true
        in
        if not still_alive then (
          match read_status_file spath with
          | Some d -> render_tui d
          | None -> ();
          wait_q_key ()
        ) else (
          Unix.sleep 1;
          loop ()
        )
    | None ->
        render_loading ();
        let still_alive = match child_pid with
          | Some pid -> (try Unix.kill pid 0; true with _ -> false)
          | None -> true
        in
        if not still_alive then ()
        else (Unix.sleep 1; loop ())
  in

  (try
     (match term_attr with
      | Some attr ->
          let raw = { attr with Unix.c_icanon = false; Unix.c_echo = false } in
          Unix.tcsetattr Unix.stdin Unix.TCSADRAIN raw
      | None -> ());
     loop ()
   with exn ->
     Printf.eprintf "t top monitor error: %s\n" (Printexc.to_string exn)
  );

  restore_term ();
  Printf.eprintf "%s" ansi_show_cursor

let print_top_help () =
  Printf.printf "Usage:\n";
  Printf.printf "  t top run <file.t>                Build and monitor with live TUI\n";
  Printf.printf "  t top run --background <file.t>   Build in background (no TUI)\n";
  Printf.printf "  t top monitor                     Attach to a background build\n";
  Printf.printf "\n";
  Printf.printf "Monitor shows real-time node status, durations, and build progress.\n"

let cmd_top args env =
  match args with
  | "run" :: "--background" :: filename :: [] ->
      begin
        match Cli_args.validate_path ~kind:Cli_args.File filename with
        | Ok () -> cmd_top_run_background filename env
        | Error msg ->
            Printf.eprintf "Error: %s\n" msg;
            exit 1
      end
  | "run" :: filename :: [] ->
      begin
        match Cli_args.validate_path ~kind:Cli_args.File filename with
        | Ok () -> cmd_top_run filename env
        | Error msg ->
            Printf.eprintf "Error: %s\n" msg;
            exit 1
      end
  | "run" :: _ ->
      Printf.eprintf "Usage: t top run [--background] <file.t>\n";
      exit 1
  | "monitor" :: [] ->
      cmd_top_monitor env
  | ["--help"] | ["-h"] ->
      print_top_help ()
  | _ ->
      print_top_help ()
