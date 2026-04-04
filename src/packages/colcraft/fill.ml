open Ast
open Arrow_table

(*
--# Fill missing values
--#
--# Fills missing values in selected columns using the next or previous entry.
--#
--# @name fill
--# @param df :: DataFrame The DataFrame.
--# @param ... :: Symbol Columns to fill (use $col syntax).
--# @param .direction :: String (Optional) Direction in which to fill missing values. 
--#   Options: "down" (default), "up", "downup", "updown".
--# @return :: DataFrame The filled DataFrame.
--# @example
--#   fill(df, $category, .direction = "down")
--# @family colcraft
--# @export
*)
let register env =
  Env.add "fill"
    (make_builtin_named ~name:"fill" ~variadic:true 1 (fun named_args _env ->
      let df_arg = match named_args with
        | (_, VDataFrame df) :: _ -> Some df
        | _ -> None
      in
      
      let get_named k = List.find_map (fun (nk, v) -> if nk = Some k then Some v else None) named_args in
      let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) named_args in
      
      let direction = match get_named ".direction" with
        | Some (VString s) -> s
        | _ -> "down"
      in
      
      let cols_variants = match positional with _::tail -> tail | [] -> [] in
      let cols_to_fill = List.filter_map Utils.extract_column_name cols_variants in

      match df_arg with
      | None -> Error.type_error "Function `fill` expects a DataFrame as first argument."
      | Some df ->
          let valid_directions = ["down"; "up"; "downup"; "updown"] in
          if not (List.mem direction valid_directions) then
            Error.type_error (Printf.sprintf "Function `fill` received invalid `.direction` value: \"%s\". Supported values are: down, up, downup, updown." direction)
          else if cols_to_fill = [] then
            Error.type_error "Function `fill` expects at least one column to fill using $col syntax."
          else
          
          let orig_nrows = Arrow_table.num_rows df.arrow_table in
          let all_cols = Arrow_table.column_names df.arrow_table in
          
          let missing_cols = List.filter (fun c -> not (List.mem c all_cols)) cols_to_fill in
          if missing_cols <> [] then 
            Error.make_error KeyError (Printf.sprintf "Function `fill`: column(s) not found: %s" (String.concat ", " missing_cols))
          else
            
            let fill_col col_name data =
              let new_arr = match data with
                | IntColumn a ->
                    let b = Array.copy a in
                    let last = ref None in
                    if direction = "down" || direction = "downup" then
                      for i = 0 to orig_nrows - 1 do
                        match b.(i) with
                        | Some _ as v -> last := v
                        | None -> b.(i) <- !last
                      done;
                    if direction = "up" || direction = "updown" || (direction = "downup" && Array.exists Option.is_none b) then
                      begin
                        last := None;
                        for i = orig_nrows - 1 downto 0 do
                          match b.(i) with
                          | Some _ as v -> last := v
                          | None -> b.(i) <- !last
                        done;
                        if direction = "updown" then (* if still has NAs, fill down *)
                          begin
                             last := None;
                             for i = 0 to orig_nrows - 1 do
                               match b.(i) with
                               | Some _ as v -> last := v
                               | None -> b.(i) <- !last
                             done
                          end
                      end;
                    IntColumn b
                | FloatColumn a ->
                    let b = Array.copy a in
                    let last = ref None in
                    if direction = "down" || direction = "downup" then
                      for i = 0 to orig_nrows - 1 do
                        match b.(i) with
                        | Some _ as v -> last := v
                        | None -> b.(i) <- !last
                      done;
                    if direction = "up" || direction = "updown" || (direction = "downup" && Array.exists Option.is_none b) then
                      begin
                        last := None;
                        for i = orig_nrows - 1 downto 0 do
                          match b.(i) with
                          | Some _ as v -> last := v
                          | None -> b.(i) <- !last
                        done;
                        if direction = "updown" then
                           begin
                             last := None;
                             for i = 0 to orig_nrows - 1 do
                               match b.(i) with
                               | Some _ as v -> last := v
                               | None -> b.(i) <- !last
                             done
                           end
                      end;
                    FloatColumn b
                | StringColumn a ->
                    let is_missing = function
                      | None -> true
                      | Some "NA" | Some "na" | Some "N/A" -> true
                      | _ -> false
                    in
                    let b = Array.copy a in
                    let last = ref None in
                    if direction = "down" || direction = "downup" then
                      for i = 0 to orig_nrows - 1 do
                        if not (is_missing b.(i)) then last := b.(i)
                        else b.(i) <- !last
                      done;
                    if direction = "up" || direction = "updown" || (direction = "downup" && Array.exists is_missing b) then
                      begin
                        last := None;
                        for i = orig_nrows - 1 downto 0 do
                          if not (is_missing b.(i)) then last := b.(i)
                          else b.(i) <- !last
                        done;
                        if direction = "updown" then
                           begin
                             last := None;
                             for i = 0 to orig_nrows - 1 do
                               if not (is_missing b.(i)) then last := b.(i)
                               else b.(i) <- !last
                             done
                           end
                      end;
                    StringColumn b
                | BoolColumn a ->
                    let b = Array.copy a in
                    let last = ref None in
                    if direction = "down" || direction = "downup" then
                      for i = 0 to orig_nrows - 1 do
                        match b.(i) with
                        | Some _ as v -> last := v
                        | None -> b.(i) <- !last
                      done;
                    if direction = "up" || direction = "updown" || (direction = "downup" && Array.exists Option.is_none b) then
                      begin
                        last := None;
                        for i = orig_nrows - 1 downto 0 do
                          match b.(i) with
                          | Some _ as v -> last := v
                          | None -> b.(i) <- !last
                        done;
                        if direction = "updown" then
                           begin
                             last := None;
                             for i = 0 to orig_nrows - 1 do
                               match b.(i) with
                               | Some _ as v -> last := v
                               | None -> b.(i) <- !last
                             done
                            end
                       end;
                    BoolColumn b
                | DateColumn a ->
                    let b = Array.copy a in
                    let last = ref None in
                    if direction = "down" || direction = "downup" then
                      for i = 0 to orig_nrows - 1 do
                        match b.(i) with
                        | Some _ as v -> last := v
                        | None -> b.(i) <- !last
                      done;
                    if direction = "up" || direction = "updown" || (direction = "downup" && Array.exists Option.is_none b) then
                      begin
                        last := None;
                        for i = orig_nrows - 1 downto 0 do
                          match b.(i) with
                          | Some _ as v -> last := v
                          | None -> b.(i) <- !last
                        done;
                        if direction = "updown" then
                           begin
                             last := None;
                             for i = 0 to orig_nrows - 1 do
                               match b.(i) with
                               | Some _ as v -> last := v
                               | None -> b.(i) <- !last
                             done
                           end
                      end;
                    DateColumn b
                | DatetimeColumn (a, tz) ->
                    let b = Array.copy a in
                    let last = ref None in
                    if direction = "down" || direction = "downup" then
                      for i = 0 to orig_nrows - 1 do
                        match b.(i) with
                        | Some _ as v -> last := v
                        | None -> b.(i) <- !last
                      done;
                    if direction = "up" || direction = "updown" || (direction = "downup" && Array.exists Option.is_none b) then
                      begin
                        last := None;
                        for i = orig_nrows - 1 downto 0 do
                          match b.(i) with
                          | Some _ as v -> last := v
                          | None -> b.(i) <- !last
                        done;
                        if direction = "updown" then
                           begin
                             last := None;
                             for i = 0 to orig_nrows - 1 do
                               match b.(i) with
                               | Some _ as v -> last := v
                               | None -> b.(i) <- !last
                             done
                           end
                      end;
                    DatetimeColumn (b, tz)
                | DictionaryColumn (a, levels, ordered) ->
                    let b = Array.copy a in
                    let last = ref None in
                    if direction = "down" || direction = "downup" then
                      for i = 0 to orig_nrows - 1 do
                        match b.(i) with
                        | Some _ as v -> last := v
                        | None -> b.(i) <- !last
                      done;
                    if direction = "up" || direction = "updown" || (direction = "downup" && Array.exists Option.is_none b) || (direction = "updown" && Array.exists Option.is_none b) then
                      begin
                        last := None;
                        for i = orig_nrows - 1 downto 0 do
                          match b.(i) with
                          | Some _ as v -> last := v
                          | None -> b.(i) <- !last
                        done;
                        if direction = "updown" then
                           begin
                             last := None;
                             for i = 0 to orig_nrows - 1 do
                               match b.(i) with
                               | Some _ as v -> last := v
                               | None -> b.(i) <- !last
                             done
                           end
                      end;
                    DictionaryColumn (b, levels, ordered)
                | NAColumn n -> NAColumn n
                | ListColumn a -> ListColumn a
              in
              (col_name, new_arr)
            in

            let new_columns = List.map (fun col_name ->
              let col_data = match Arrow_table.get_column df.arrow_table col_name with Some d -> d | None -> NAColumn orig_nrows in
              if List.mem col_name cols_to_fill then
                fill_col col_name col_data
              else
                (col_name, col_data)
            ) all_cols in
            
            let new_schema = List.map (fun (n, c) -> (n, Arrow_table.column_type_of c)) new_columns in
            VDataFrame { arrow_table = { schema = new_schema; columns = new_columns; nrows = orig_nrows; native_handle = None } |> Arrow_table.materialize; group_keys = df.group_keys }
    ))
    env
