(* src/arrow/arrow_io.ml *)
(* Arrow-backed CSV reading with column-level type inference.            *)
(* When Arrow C GLib is available (Arrow_ffi.arrow_available = true),   *)
(* uses GArrowCSVReader for native Arrow CSV parsing via FFI.            *)
(* Falls back to pure OCaml CSV parsing otherwise.                       *)

(* ===================================================================== *)
(* Pure OCaml CSV Parsing (Fallback)                                     *)
(* ===================================================================== *)

(** Split a CSV line into fields, handling quoted fields *)
let parse_csv_line (line : string) : string list =
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
      end else if c = ',' then begin
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

(** Split a string into lines, handling \r\n and \n *)
let split_lines (s : string) : string list =
  let lines = String.split_on_char '\n' s in
  List.map (fun line ->
    if String.length line > 0 && line.[String.length line - 1] = '\r' then
      String.sub line 0 (String.length line - 1)
    else
      line
  ) lines

(** Check if a string is a null/NA value *)
let is_na_string (s : string) : bool =
  let trimmed = String.trim s in
  trimmed = "" || trimmed = "NA" || trimmed = "na" || trimmed = "N/A"

(** Column type inference — determines the best Arrow type for a column *)
let infer_column_type (values : string list) : Arrow_table.arrow_type =
  let non_na = List.filter (fun s -> not (is_na_string s)) values in
  if non_na = [] then Arrow_table.ArrowNull
  else
    let all_int = List.for_all (fun s ->
      match int_of_string_opt (String.trim s) with Some _ -> true | None -> false
    ) non_na in
    if all_int then Arrow_table.ArrowInt64
    else
      let all_float = List.for_all (fun s ->
        match float_of_string_opt (String.trim s) with Some _ -> true | None -> false
      ) non_na in
      if all_float then Arrow_table.ArrowFloat64
      else
        let all_bool = List.for_all (fun s ->
          match String.lowercase_ascii (String.trim s) with
          | "true" | "false" -> true | _ -> false
        ) non_na in
        if all_bool then Arrow_table.ArrowBoolean
        else Arrow_table.ArrowString

(** Build a typed Arrow column from raw strings *)
let build_column (values : string array) (col_type : Arrow_table.arrow_type) : Arrow_table.column_data =
  match col_type with
  | Arrow_table.ArrowInt64 ->
      Arrow_table.IntColumn (Array.map (fun s ->
        if is_na_string s then None
        else Some (int_of_string (String.trim s))
      ) values)
  | Arrow_table.ArrowFloat64 ->
      Arrow_table.FloatColumn (Array.map (fun s ->
        if is_na_string s then None
        else Some (float_of_string (String.trim s))
      ) values)
  | Arrow_table.ArrowBoolean ->
      Arrow_table.BoolColumn (Array.map (fun s ->
        if is_na_string s then None
        else Some (String.lowercase_ascii (String.trim s) = "true")
      ) values)
  | Arrow_table.ArrowString ->
      Arrow_table.StringColumn (Array.map (fun s ->
        if is_na_string s then None
        else Some (String.trim s)
      ) values)
  | Arrow_table.ArrowNull ->
      Arrow_table.NullColumn (Array.length values)

(** Parse a CSV string into an Arrow table (pure OCaml fallback) *)
let parse_csv_string (content : string) : (Arrow_table.t, string) result =
  let lines = split_lines content in
  let lines = List.filter (fun l -> String.trim l <> "") lines in
  match lines with
  | [] -> Ok Arrow_table.empty
  | header_line :: data_lines ->
      let headers = parse_csv_line header_line in
      let ncols = List.length headers in
      let data_rows = List.map parse_csv_line data_lines in
      let valid_rows = List.filter (fun row -> List.length row = ncols) data_rows in
      let nrows = List.length valid_rows in
      if nrows = 0 && List.length data_rows > 0 then
        Error (Printf.sprintf
          "CSV Error: Row column counts do not match header (expected %d columns)" ncols)
      else
        let rows_arr = Array.of_list valid_rows in
        (* Extract raw string values per column *)
        let raw_columns = List.mapi (fun col_idx name ->
          let col_values = Array.init nrows (fun row_idx ->
            List.nth rows_arr.(row_idx) col_idx
          ) in
          (name, col_values)
        ) headers in
        (* Infer types and build typed columns *)
        let columns = List.map (fun (name, raw_vals) ->
          let col_type = infer_column_type (Array.to_list raw_vals) in
          (name, build_column raw_vals col_type)
        ) raw_columns in
        Ok (Arrow_table.create columns nrows)

(* ===================================================================== *)
(* Native Arrow CSV Reading (via FFI)                                    *)
(* ===================================================================== *)

(** Read a CSV file using the native Arrow C GLib CSV reader.
    Returns Ok(Arrow_table.t) with a native_handle, or Error if reading fails. *)
let read_csv_native (path : string) : (Arrow_table.t, string) result =
  match Arrow_ffi.arrow_read_csv path with
  | None -> Error ("Arrow CSV read failed: " ^ path)
  | Some ptr ->
      let schema_pairs = Arrow_ffi.arrow_table_get_schema ptr in
      let nrows = Arrow_ffi.arrow_table_num_rows ptr in
      let schema = List.map (fun (name, type_tag) ->
        (name, Arrow_table.arrow_type_of_tag type_tag)
      ) schema_pairs in
      Ok (Arrow_table.create_from_native ptr schema nrows)

(* ===================================================================== *)
(* Public API                                                            *)
(* ===================================================================== *)

(** Read a CSV file into an Arrow table.
    Uses native Arrow CSV reader when available, falls back to pure OCaml. *)
let rec read_csv (path : string) : (Arrow_table.t, string) result =
  if Arrow_ffi.arrow_available then
    (* Try native Arrow CSV reader first *)
    match read_csv_native path with
    | Ok _ as result -> result
    | Error _native_err ->
        (* Native Arrow reader failed — fall back to pure OCaml parser.
           This can happen if the file format is not supported by Arrow's
           CSV reader or if the native library encounters an error. *)
        read_csv_fallback path
  else
    read_csv_fallback path

(** Pure OCaml CSV reading fallback *)
and read_csv_fallback (path : string) : (Arrow_table.t, string) result =
  try
    let ch = open_in path in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    parse_csv_string content
  with
  | Sys_error msg -> Error ("File Error: " ^ msg)

(* ===================================================================== *)
(* CSV Writing                                                           *)
(* ===================================================================== *)

(** Convert a column value to CSV field string *)
let value_to_csv_field ~sep = function
  | Ast.VInt n -> string_of_int n
  | Ast.VFloat f -> string_of_float f
  | Ast.VBool b -> if b then "true" else "false"
  | Ast.VString s -> 
      (* Quote strings if they contain the separator, quotes, or newlines *)
      let has_sep = String.length sep > 0 && String.contains s sep.[0] in
      if has_sep || String.contains s '"' || String.contains s '\n' then
        "\"" ^ String.concat "\"\"" (String.split_on_char '"' s) ^ "\""
      else s
  | Ast.VNA _ -> "NA"
  | Ast.VNull -> ""
  | _ -> ""

(** Write an Arrow table to a CSV file *)
let write_csv ?(sep=",") (table : Arrow_table.t) (path : string) : (unit, string) result =
  try
    let ch = open_out path in
    let col_names = Arrow_table.column_names table in
    let nrows = Arrow_table.num_rows table in
    
    (* Write header *)
    output_string ch (String.concat sep col_names);
    output_char ch '\n';
    
    (* Write data rows *)
    let value_columns = Arrow_bridge.table_to_value_columns table in
    for row_idx = 0 to nrows - 1 do
      let row_values = List.map (fun (_name, col_data) ->
        value_to_csv_field ~sep col_data.(row_idx)
      ) value_columns in
      output_string ch (String.concat sep row_values);
      output_char ch '\n'
    done;
    
    close_out ch;
    Ok ()
  with
  | Sys_error msg -> Error ("File Error: " ^ msg)
