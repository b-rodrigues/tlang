open Ast

let is_sep_name = function Some "separator" -> true | _ -> false

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
--#   df = read_csv("data.csv", separator: ";")
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
--#   df = read_csv("data.csv", separator: ";")
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
          (try
            let read_content_from_path p =
              let ch = open_in p in
              let content = really_input_string ch (in_channel_length ch) in
              close_in ch;
              content
            in

            let content = 
              if Arrow_io.is_url path then
                match Arrow_io.download_url path with
                | Ok temp_path ->
                    let c = read_content_from_path temp_path in
                    (try Sys.remove temp_path with _ -> ());
                    c
                | Error msg -> raise (Sys_error msg)
              else
                read_content_from_path path
            in
            parse_csv_string ~sep ~skip_header ~skip_lines ~clean_colnames:do_clean content
          with
          | Sys_error msg -> Error.make_error FileError (Printf.sprintf "File Error: %s." msg))
      | [VNA _] -> Error.type_error "Function `read_csv` expects a String path, got NA."
      | [_] -> Error.type_error "Function `read_csv` expects a String path."
      | _ -> Error.make_error ArityError "Function `read_csv` takes exactly 1 positional argument (path)."
    ))
    env
