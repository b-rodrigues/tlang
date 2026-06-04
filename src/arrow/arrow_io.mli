(* src/arrow/arrow_io.mli *)

(** Input/Output operations for reading and writing Arrow tables from/to CSV, Parquet, and IPC formats. *)

(** Download a remote URL to a temporary local file.
    
    @param suffix The temporary file suffix extension (defaults to ".csv").
    @param url The remote URL to fetch.
    @return [Ok local_path] if successful, [Error msg] otherwise. *)
val download_url : ?suffix:string -> string -> (string, string) result

(** Read a CSV file or URL into an Arrow table.
    Uses native Arrow CSV reader when available, falls back to pure OCaml. *)
val read_csv : string -> (Arrow_table.t, string) result

(** Write an Arrow table to a CSV file.
    
    @param sep The column separator (defaults to ","). *)
val write_csv : ?sep:string -> Arrow_table.t -> string -> (unit, string) result

(** Read a Parquet file from a local path or URL into an Arrow table. *)
val read_parquet : string -> (Arrow_table.t, string) result

(** Read an Arrow IPC file *)
val read_ipc : string -> (Arrow_table.t, string) result

(** Write an Arrow table to an IPC file *)
val write_ipc : Arrow_table.t -> string -> (unit, string) result

(** Return true if the given string looks like an HTTP/HTTPS URL. *)
val is_url : string -> bool

(** Parse an array of string values into a typed column according to the given Arrow type.
    Used internally by the CSV reader and exposed for testing. *)
val build_column : string array -> Arrow_table.arrow_type -> Arrow_table.column_data
