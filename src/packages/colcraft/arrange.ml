open Ast

let register ~make_builtin ~make_error env =
  Env.add "arrange"
    (make_builtin ~variadic:true 2 (fun args _env ->
      match args with
      | [VDataFrame df; VString col_name] | [VDataFrame df; VString col_name; VString "asc"] ->
          (match List.assoc_opt col_name df.columns with
           | None -> make_error KeyError (Printf.sprintf "Column '%s' not found in DataFrame" col_name)
           | Some col ->
             let indices = Array.init df.nrows (fun i -> i) in
             let compare_values a b =
               match (a, b) with
               | (VInt x, VInt y) -> compare x y
               | (VFloat x, VFloat y) -> compare x y
               | (VString x, VString y) -> String.compare x y
               | (VBool x, VBool y) -> compare x y
               | (VNA _, _) -> 1
               | (_, VNA _) -> -1
               | _ -> 0
             in
             Array.sort (fun i j -> compare_values col.(i) col.(j)) indices;
             let new_columns = List.map (fun (name, c) ->
               (name, Array.init df.nrows (fun k -> c.(indices.(k))))
             ) df.columns in
             VDataFrame { columns = new_columns; nrows = df.nrows; group_keys = df.group_keys })
      | [VDataFrame df; VString col_name; VString "desc"] ->
          (match List.assoc_opt col_name df.columns with
           | None -> make_error KeyError (Printf.sprintf "Column '%s' not found in DataFrame" col_name)
           | Some col ->
             let indices = Array.init df.nrows (fun i -> i) in
             let compare_values a b =
               match (a, b) with
               | (VInt x, VInt y) -> compare y x
               | (VFloat x, VFloat y) -> compare y x
               | (VString x, VString y) -> String.compare y x
               | (VBool x, VBool y) -> compare y x
               | (VNA _, _) -> 1
               | (_, VNA _) -> -1
               | _ -> 0
             in
             Array.sort (fun i j -> compare_values col.(i) col.(j)) indices;
             let new_columns = List.map (fun (name, c) ->
               (name, Array.init df.nrows (fun k -> c.(indices.(k))))
             ) df.columns in
             VDataFrame { columns = new_columns; nrows = df.nrows; group_keys = df.group_keys })
      | [VDataFrame _; VString _; VString dir] ->
          make_error ValueError (Printf.sprintf "arrange() direction must be \"asc\" or \"desc\", got \"%s\"" dir)
      | [VDataFrame _; _] | [VDataFrame _; _; _] ->
          make_error TypeError "arrange() expects a string column name"
      | [_; _] | [_; _; _] -> make_error TypeError "arrange() expects a DataFrame as first argument"
      | _ -> make_error ArityError "arrange() takes 2 or 3 arguments"
    ))
    env
