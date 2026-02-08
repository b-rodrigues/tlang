(* src/arrow/arrow_io.ml *)
(* Arrow-backed CSV reading with column-level type inference.            *)
(* Replaces the simple per-cell type inference in the alpha evaluator.   *)
(* When Arrow C GLib is available, this will delegate to                 *)
(* GArrowCSVReader for native Arrow CSV parsing.                         *)

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

(** Parse a CSV string into an Arrow table *)
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

(** Read a CSV file into an Arrow table *)
let read_csv (path : string) : (Arrow_table.t, string) result =
  try
    let ch = open_in path in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    parse_csv_string content
  with
  | Sys_error msg -> Error ("File Error: " ^ msg)
