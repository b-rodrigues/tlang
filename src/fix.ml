(* src/fix.ml *)
(* Mechanical application of suggested_fix from diagnostics *)

type fix_result = {
  file : string;
  applied : int;
  skipped : int;
  diagnostics : Diagnostics.diagnostic list;
}

let run_check_json file =
  let cmd = Printf.sprintf "t check --json %s" file in
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 1024 in
  (try
     while true do
       Buffer.add_channel buf ic 1024
     done
   with End_of_file -> ());
  let _ = Unix.close_process_in ic in
  Buffer.contents buf

let apply_cast ~file ~line ~column ~cast_to =
  let lines = ref [] in
  let ch = open_in file in
  Fun.protect ~finally:(fun () -> close_in_noerr ch)
    (fun () ->
       let i = ref 1 in
       try
         while true do
           let l = input_line ch in
           if !i = line then
             let indent =
               let rec count s n =
                 if n < String.length s && s.[n] = ' ' then count s (n + 1) else n
               in
               count l 0
             in
             let pad = String.make indent ' ' in
             lines := !lines @ [
               Printf.sprintf "%s|> mutate($%s = as.%s($%s))" pad column cast_to column;
               l;
             ]
           else
             lines := !lines @ [l];
           incr i
         done
       with End_of_file -> ());
  let oc = open_out file in
  Fun.protect ~finally:(fun () -> close_out_noerr oc)
    (fun () ->
       List.iter (fun l -> output_string oc (l ^ "\n")) !lines)

let apply_rename_column ~file ~old_name ~new_name =
  let content =
    let ch = open_in file in
    Fun.protect ~finally:(fun () -> close_in_noerr ch)
      (fun () -> really_input_string ch (in_channel_length ch))
  in
  let re = Str.regexp_string old_name in
  let new_content = Str.global_replace re new_name content in
  if content <> new_content then begin
    let oc = open_out file in
    Fun.protect ~finally:(fun () -> close_out_noerr oc)
      (fun () -> output_string oc new_content)
  end

let apply_fix ~file (fix : Diagnostics.suggested_fix) =
  match fix with
  | Cast { column; cast_to; file = _; line } ->
      (match line with
       | Some l -> apply_cast ~file ~line:l ~column ~cast_to; true
       | None -> false)
  | Rename_column { old_name; new_name; file = _; line = _ } ->
      apply_rename_column ~file ~old_name ~new_name; true
  | Add_node_arg _ -> false
  | Pin_package_version _ -> false
  | NoFix -> false

let opt_string json = match json with `String s -> Some s | `Null -> None | _ -> None
let opt_int json = match json with `Int i -> Some i | `Null -> None | _ -> None

let cmd_fix ?(dry_run = false) file =
  let json_str = run_check_json file in
  let json = Yojson.Safe.from_string json_str in
  let open Yojson.Safe.Util in
  let diagnostics = json |> member "diagnostics" |> to_list in
  let fixes = List.filter_map (fun d ->
    let fix_json = d |> member "suggested_fix" in
    if fix_json = `Null then None
    else
      let fix = Diagnostics.suggested_fix_of_yojson fix_json in
      if fix = Diagnostics.NoFix then None
      else Some (Diagnostics.{
        diag_id = d |> member "id" |> to_string;
        diag_error_class = d |> member "error_class" |> to_string;
        diag_severity = (if d |> member "severity" |> to_string = "error" then Diagnostics.Error else Diagnostics.Warning);
        diag_phase = Diagnostics.Schema;
        diag_node_id = d |> member "node_id" |> opt_string;
        diag_node_lang = None;
        diag_file = d |> member "file" |> opt_string;
        diag_line = d |> member "line" |> opt_int;
        diag_column = d |> member "column" |> opt_int;
        diag_message = d |> member "message" |> to_string;
        diag_caused_by = [];
        diag_suggested_fix = fix;
      })
  ) diagnostics in
  let applied = ref 0 in
  let skipped = ref 0 in
  List.iter (fun (d : Diagnostics.diagnostic) ->
    if dry_run then begin
      Printf.printf "Would apply: %s on %s\n" d.diag_message
        (match d.diag_file with Some f -> f | None -> "<unknown>")
    end else begin
      let file_to_fix = match d.diag_file with
        | Some f -> f
        | None -> file
      in
      if apply_fix ~file:file_to_fix d.diag_suggested_fix then
        incr applied
      else
        incr skipped
    end
  ) fixes;
  { file; applied = !applied; skipped = !skipped; diagnostics = fixes }
