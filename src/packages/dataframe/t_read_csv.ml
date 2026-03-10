open Ast

let is_sep_name = function Some "separator" | Some "sep" -> true | _ -> false
(* Use the Arrow-native reader only for meaningfully large default CSV loads,
   where avoiding full OCaml string materialization noticeably improves runtime
   and memory usage (the NYC taxi benchmark case). *)
let arrow_fast_path_min_bytes = 256 * 1024

let starts_with prefix s =
  let len_p = String.length prefix in
  let len_s = String.length s in
  len_s >= len_p && String.sub s 0 len_p = prefix

let ensure_trailing_period msg =
  let len = String.length msg in
  if len > 0 && msg.[len - 1] = '.'
  then msg
  else msg ^ "."

let error_of_read_csv_message msg =
  if starts_with "CSV Error:" msg then
    Error.value_error msg
  else
    let msg = ensure_trailing_period msg in
    let msg =
      if starts_with "File Error: " msg then msg
      else "File Error: " ^ msg
    in
    Error.make_error FileError msg

(** Use the Arrow-native CSV reader only for large local CSV files loaded with
    the default comma-separated semantics. Option-heavy calls keep using the
    existing parser so public read_csv behavior remains unchanged. *)
let should_use_arrow_fast_path path ~sep ~skip_header ~skip_lines ~clean_colnames =
  sep = ','
  && not skip_header
  && skip_lines = 0
  && not clean_colnames
  && not (Arrow_io.is_url path)
  &&
  (* Never surface filesystem issues from the eligibility check itself;
     fall back to the existing parser and let it report user-facing errors. *)
  try
    let stat = Unix.stat path in
    stat.Unix.st_size >= arrow_fast_path_min_bytes
  with Unix.Unix_error _ -> false

(*
--# Read CSV file
--#
--# Reads a CSV file into a DataFrame.
--#
--# @name read_csv
--# @param path :: String Path or URL to the CSV file.
--# @param separator :: String (Optional) Field separator (default ",").
--# @param skip_header :: Bool (Optional) Skip proper header parsing? (default false).
--# @param skip_lines :: Int (Optional) Number of lines to skip at start.
--# @param clean_colnames :: Bool (Optional) Clean column names? (default false).
--# @return :: DataFrame The loaded data.
--# @example
--#   df = read_csv("data.csv")
--#   df = read_csv("data.csv", separator = ";")
--# @family dataframe
--# @seealso write_csv
--# @export
*)
(* --- Phase 2: Arrow-Backed CSV Parser --- *)

(** Split a CSV line into fields, handling quoted fields *)
let parse_csv_line ?(sep=',') (line : string) : string list =
  let len = String.length line in
  let buf = Buffer.create 64 in
  let fields = ref [] in
  let i = ref 0 in
  let in_quotes = ref false in
  while !i < len do
    let c = line.[!i] in
    if !in_quotes then begin
      if c = '"' then begin
        if !i + 1 < len && line.[!i + 1] = '"' then begin
          Buffer.add_char buf '"';
          i := !i + 2
        end else begin
          in_quotes := false;
          i := !i + 1
        end
      end else begin
        Buffer.add_char buf c;
        i := !i + 1
      end
    end else begin
      if c = '"' then begin
        in_quotes := true;
        i := !i + 1
      end else if c = sep then begin
        fields := Buffer.contents buf :: !fields;
        Buffer.clear buf;
        i := !i + 1
      end else begin
        Buffer.add_char buf c;
        i := !i + 1
      end
    end
  done;
  fields := Buffer.contents buf :: !fields;
  List.rev !fields

(** Try to parse a string as a typed value (Int, Float, Bool, NA, or String) *)
let parse_csv_value (s : string) : value =
  let trimmed = String.trim s in
  if trimmed = "" || trimmed = "NA" || trimmed = "na" || trimmed = "N/A" then
    VNA NAGeneric
  else
    match int_of_string_opt trimmed with
    | Some n -> VInt n
    | None ->
      match float_of_string_opt trimmed with
      | Some f -> VFloat f
      | None ->
        match String.lowercase_ascii trimmed with
        | "true" -> VBool true
        | "false" -> VBool false
        | _ -> VString trimmed

(** Split a string into lines, handling \r\n and \n *)
let split_lines (s : string) : string list =
  let lines = String.split_on_char '\n' s in
  List.map (fun line ->
    if String.length line > 0 && line.[String.length line - 1] = '\r' then
      String.sub line 0 (String.length line - 1)
    else
      line
  ) lines

(** Parse a CSV string into an Arrow-backed DataFrame *)
let parse_csv_string ?(sep=',') ?(skip_header=false) ?(skip_lines=0) ?(clean_colnames=false) (content : string) : value =
  let lines = split_lines content in
  (* Remove trailing empty lines *)
  let lines = List.filter (fun l -> String.trim l <> "") lines in
  (* Skip the first N lines *)
  let rec drop n lst = if n <= 0 then lst else match lst with [] -> [] | _ :: rest -> drop (n - 1) rest in
  let lines = drop skip_lines lines in
  match lines with
  | [] -> VDataFrame { arrow_table = Arrow_table.empty; group_keys = [] }
  | first_line :: rest_lines ->
      let headers, data_lines =
        if skip_header then
          (* No header row: generate column names V1, V2, ... *)
          let ncols = List.length (parse_csv_line ~sep first_line) in
          let headers = List.init ncols (fun i -> Printf.sprintf "V%d" (i + 1)) in
          (headers, lines)
        else
          (parse_csv_line ~sep first_line, rest_lines)
      in
      (* Apply column name cleaning if requested *)
      let headers =
        if clean_colnames then Clean_colnames.clean_names headers
        else headers
      in
      let ncols = List.length headers in
      let data_rows = List.map (parse_csv_line ~sep) data_lines in
      (* Validate column count consistency *)
      let valid_rows = List.filter (fun row -> List.length row = ncols) data_rows in
      let nrows = List.length valid_rows in
      if nrows = 0 && List.length data_rows > 0 then
        Ast.make_error Ast.ValueError
          (Printf.sprintf "CSV Error: Row column counts do not match header (expected %d columns)" ncols)
      else
        (* Convert rows to array for O(1) access *)
        let rows_arr = Array.of_list valid_rows in
        (* Build column arrays using per-cell type inference for backward compatibility *)
        let value_columns = List.mapi (fun col_idx name ->
          let col_data = Array.init nrows (fun row_idx ->
            let row = rows_arr.(row_idx) in
            parse_csv_value (List.nth row col_idx)
          ) in
          (name, col_data)
        ) headers in
        (* Convert to Arrow table via bridge *)
        let arrow_table = Arrow_bridge.table_from_value_columns value_columns nrows in
       VDataFrame { arrow_table; group_keys = [] }

(** Parse a CSV path with the existing pure-OCaml read_csv behavior, including
    URL download support and structured user-facing error values. *)
let parse_csv_path ?(sep=',') ?(skip_header=false) ?(skip_lines=0) ?(clean_colnames=false) path =
  try
    let read_content_from_path p =
      let ch = open_in p in
      let content = really_input_string ch (in_channel_length ch) in
      close_in ch;
      content
    in
    let content_result =
      if Arrow_io.is_url path then
        match Arrow_io.download_url path with
        | Ok temp_path ->
            let c = read_content_from_path temp_path in
            (try Sys.remove temp_path with _ -> ());
            Ok c
        | Error msg -> Error (error_of_read_csv_message msg)
      else
        Ok (read_content_from_path path)
    in
    match content_result with
    | Ok content -> parse_csv_string ~sep ~skip_header ~skip_lines ~clean_colnames content
    | Error err -> err
  with
  | Sys_error msg -> error_of_read_csv_message msg


(*
--# Read CSV file
--#
--# Reads a CSV file into a DataFrame.
--#
--# @name read_csv
--# @param path :: String Path or URL to the CSV file.
--# @param separator :: String (Optional) Field separator (default ",").
--# @param skip_header :: Bool (Optional) Skip proper header parsing? (default false).
--# @param skip_lines :: Int (Optional) Number of lines to skip at start.
--# @param clean_colnames :: Bool (Optional) Clean column names? (default false).
--# @return :: DataFrame The loaded data.
--# @example
--#   df = read_csv("data.csv")
--#   df = read_csv("data.csv", separator = ";")
--# @family dataframe
--# @seealso write_csv
--# @export
*)
let register env =
  Env.add "read_csv"
    (make_builtin_named ~name:"read_csv" ~variadic:true 1 (fun named_args _env ->
      (* Validate sep/separator parameter if provided *)
      let bad_sep = List.exists (fun (name, v) ->
        match name, v with
        | n, VString s when is_sep_name n -> String.length s <> 1
        | n, _ when is_sep_name n -> true
        | _ -> false
      ) named_args in
      if bad_sep then
        Error.type_error "Function `read_csv` separator must be a single character string."
      else
      (* Extract named arguments *)
      let sep = List.fold_left (fun acc (name, v) ->
        match name, v with
        | n, VString s when is_sep_name n -> s.[0]
        | _ -> acc
      ) ',' named_args in
      let skip_header = List.exists (fun (name, v) ->
        name = Some "skip_header" && (match v with VBool true -> true | _ -> false)
      ) named_args in
      let skip_lines = List.fold_left (fun acc (name, v) ->
        match name, v with
        | Some "skip_lines", VInt n when n >= 0 -> n
        | _ -> acc
      ) 0 named_args in
      let do_clean = List.exists (fun (name, v) ->
        name = Some "clean_colnames" && (match v with VBool true -> true | _ -> false)
      ) named_args in
      (* Extract positional arguments *)
      let args = List.filter (fun (name, _) ->
        not (is_sep_name name) && name <> Some "skip_header"
        && name <> Some "skip_lines" && name <> Some "clean_colnames"
      ) named_args |> List.map snd in
      match args with
      | [VString path] ->
          if should_use_arrow_fast_path path ~sep ~skip_header ~skip_lines ~clean_colnames:do_clean then
            match Arrow_io.read_csv path with
            | Ok arrow_table -> VDataFrame { arrow_table; group_keys = [] }
            | Error msg -> error_of_read_csv_message msg
          else
            parse_csv_path ~sep ~skip_header ~skip_lines ~clean_colnames:do_clean path
      | [VNA _] -> Error.type_error "Function `read_csv` expects a String path, got NA."
      | [_] -> Error.type_error "Function `read_csv` expects a String path."
      | _ -> Error.make_error ArityError "Function `read_csv` takes exactly 1 positional argument (path)."
    ))
    env
