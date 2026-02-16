open Ast

let register env =
  (*
  --# Create a DataFrame
  --#
  --# Constructs a DataFrame from a list of dictionaries (rows).
  --#
  --# @name dataframe
  --# @param rows :: List[Dict] The data rows.
  --# @return :: DataFrame The created DataFrame.
  --# @example
  --#   df = dataframe([
  --#     {"a": 1, "b": 2},
  --#     {"a": 3, "b": 4}
  --#   ])
  --# @family dataframe
  --# @seealso read_csv
  --# @export
  *)
  let env = Env.add "dataframe"
    (make_builtin ~name:"dataframe" 1 (fun args _env ->
      match args with
      | [VList rows] ->
          (match rows with
           | [] -> VDataFrame { arrow_table = Arrow_table.empty; group_keys = [] }
           | (_first_row_name, first_row_val) :: _ ->
               (* Inspect first row to determine columns *)
               (match first_row_val with
                | VDict pairs ->
                    let headers = List.map fst pairs in
                    let _ncols = List.length headers in
                    let nrows = List.length rows in
                    
                    (* Extract data for each column from VDict rows *)
                    let columns = List.map (fun col_name ->
                      let col_values = Array.init nrows (fun i ->
                        let (_, row_val) = List.nth rows i in
                        match row_val with
                        | VDict row_pairs ->
                            (match List.assoc_opt col_name row_pairs with
                             | Some v -> v
                             | None -> VNA NAGeneric) (* Missing key = NA *)
                        | _ -> VNA NAGeneric (* Invalid row structure handling *)
                      ) in
                      (col_name, col_values)
                    ) headers in

                    (* Create Arrow table using bridge *)
                    let arrow_table = Arrow_bridge.table_from_value_columns columns nrows in
                    VDataFrame { arrow_table; group_keys = [] }

                | VList pairs ->
                    let headers = List.filter_map (fun (k, _) -> k) pairs in
                    let _ncols = List.length headers in
                    let nrows = List.length rows in
                    
                    (* Extract data for each column from VList rows *)
                    let columns = List.map (fun col_name ->
                      let col_values = Array.init nrows (fun i ->
                        let (_, row_val) = List.nth rows i in
                        match row_val with
                        | VList row_pairs ->
                            (* For VList, find the item with the matching name *)
                            (match List.find_opt (fun (n, _) -> n = Some col_name) row_pairs with
                             | Some (_, v) -> v
                             | None -> VNA NAGeneric)
                        | _ -> VNA NAGeneric (* Invalid row structure handling *)
                      ) in
                      (col_name, col_values)
                    ) headers in

                    (* Create Arrow table using bridge *)
                    let arrow_table = Arrow_bridge.table_from_value_columns columns nrows in
                    VDataFrame { arrow_table; group_keys = [] }
                
                | _ -> Error.type_error (Printf.sprintf "Function `dataframe` expects a list of Dicts (rows). First row is: %s" (Ast.Utils.value_to_string first_row_val))))
                
      | _ -> Error.type_error (Printf.sprintf "Function `dataframe` expects a single argument (List of Dicts). Received: %s" (String.concat ", " (List.map Ast.Utils.value_to_string args)))
    )) env in
  (*
  --# Extract column as vector
  --#
  --# Extracts a single column from a DataFrame as a Vector.
  --#
  --# @name pull
  --# @param df :: DataFrame The input DataFrame.
  --# @param col :: String The column name.
  --# @return :: Vector The column data.
  --# @example
  --#   pull(mtcars, "mpg")
  --# @family dataframe
  --# @seealso select
  --# @export
  *)
  let env = Env.add "pull"
      (make_builtin ~name:"pull" 2 (fun args _env ->
        match args with
        | [VDataFrame df; VString col_name] ->
            (match Arrow_table.get_column df.arrow_table col_name with
             | None -> Error.make_error KeyError (Printf.sprintf "Column `%s` not found in DataFrame." col_name)
             | Some col ->
                 match col with
                 | Arrow_table.FloatColumn data ->
                     VVector (Array.map (function Some f -> VFloat f | None -> VNA NAGeneric) data)
                 | Arrow_table.IntColumn data ->
                     VVector (Array.map (function Some i -> VInt i | None -> VNA NAGeneric) data)
                 | Arrow_table.StringColumn data ->
                     VVector (Array.map (function Some s -> VString s | None -> VNA NAGeneric) data)
                 | Arrow_table.BoolColumn data ->
                     VVector (Array.map (function Some b -> VBool b | None -> VNA NAGeneric) data)
                 | Arrow_table.NullColumn n ->
                     VVector (Array.make n (VNA NAGeneric)))
        | _ -> Error.type_error "pull expects (DataFrame, column_name)."
      )) env in
  (*
  --# Convert to NDArray
  --#
  --# Converts numeric columns of a DataFrame to a matrix (NDArray).
  --#
  --# @name to_array
  --# @param df :: DataFrame The input DataFrame.
  --# @param cols :: List[String] (Optional) Columns to include. Defaults to all numeric.
  --# @return :: NDArray A 2D array of the data.
  --# @example
  --#   mat = to_array(mtcars)
  --# @family dataframe
  --# @seealso dataframe
  --# @export
  *)
  let env = Env.add "to_array"
      (make_builtin ~name:"to_array" ~variadic:true 1 (fun args _env ->
        match args with
        | [VDataFrame df] ->
             (* Auto-select all numeric columns *)
             let col_names = List.filter (fun name ->
               match Arrow_table.get_column df.arrow_table name with
               | Some (Arrow_table.FloatColumn _) 
               | Some (Arrow_table.IntColumn _) -> true
               | _ -> false
             ) (Arrow_table.column_names df.arrow_table) in
             
             if col_names = [] then
               Error.value_error "to_matrix: DataFrame has no numeric columns."
             else
               let nrows = Arrow_table.num_rows df.arrow_table in
               let ncols = List.length col_names in
               let data = Array.make (nrows * ncols) 0.0 in
               
               let rec process_columns idx = function
                 | [] -> Ok ()
                 | name :: rest ->
                     match Arrow_owl_bridge.numeric_column_to_owl df.arrow_table name with
                     | None -> Error (Error.type_error (Printf.sprintf "Column `%s` is not numeric or contains NAs." name))
                     | Some view ->
                         for i = 0 to nrows - 1 do
                           data.(i * ncols + idx) <- view.arr.(i)
                         done;
                         process_columns (idx + 1) rest
               in
               (match try process_columns 0 col_names with Invalid_argument _ -> Error (Error.type_error "Invalid column list") with
                | Ok () -> VNDArray { shape = [|nrows; ncols|]; data }
                | Error e -> e)

        | [VDataFrame df; VList cols] ->
            let col_names = List.map (function 
              | (_, VString s) -> s 
              | _ -> raise (Invalid_argument "Column names must be strings")
            ) cols in
            let nrows = Arrow_table.num_rows df.arrow_table in
            let ncols = List.length col_names in
            let data = Array.make (nrows * ncols) 0.0 in
            
            let rec process_columns idx = function
              | [] -> Ok ()
              | name :: rest ->
                  match Arrow_owl_bridge.numeric_column_to_owl df.arrow_table name with
                  | None -> Error (Error.type_error (Printf.sprintf "Column `%s` is not numeric or contains NAs." name))
                  | Some view ->
                      for i = 0 to nrows - 1 do
                        data.(i * ncols + idx) <- view.arr.(i)
                      done;
                      process_columns (idx + 1) rest
            in
            
            (match try process_columns 0 col_names with Invalid_argument _ -> Error (Error.type_error "Invalid column list") with
             | Ok () -> VNDArray { shape = [|nrows; ncols|]; data }
             | Error e -> e)
             
        | _ -> Error.type_error "to_array expects (DataFrame, [column_names])."
      )) env in
  env
