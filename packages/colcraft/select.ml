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
 *   - Preserves group_keys only for grouped columns that remain in the selection
 *   - Returns explicit KeyError for missing columns
 *
 * Examples:
 *   df |> select("name", "age")
 *   df |> select("score") |> nrow
 *)
