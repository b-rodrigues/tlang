(* colcraft/select.ml *)
(* Reference implementation for the select() verb. *)
(* The actual implementation lives in src/eval.ml as a builtin. *)
(*
 * select(df, "col1", "col2", ...) — select columns by name
 *
 * Design:
 *   - Takes a DataFrame and one or more string column names
 *   - Returns a new DataFrame with only the specified columns
 *   - Preserves column order as specified in arguments
 *   - Preserves group_keys if the grouped columns are still present
 *   - Returns explicit KeyError for missing columns
 *
 * Examples:
 *   df |> select("name", "age")
 *   df |> select("score") |> nrow
 *)
