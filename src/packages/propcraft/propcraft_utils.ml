open Ast

let fmt v = "`" ^ Utils.value_to_string v ^ "`"

(** Extract the generator kind tag from a generator spec value. *)
let spec_gen = function
  | VDict pairs ->
      (match List.assoc_opt "gen" pairs with
       | Some (VString g) -> Some g
       | _ -> None)
  | _ -> None

(** Extract a named field from a generator spec value. *)
let field name = function
  | VDict pairs -> List.assoc_opt name pairs
  | _ -> None

let int_field name spec =
  match field name spec with
  | Some (VInt i) -> Some i
  | _ -> None

let to_float = function
  | VFloat f -> Some f
  | VInt i -> Some (float_of_int i)
  | _ -> None

let float_field name spec =
  match field name spec with
  | Some v -> to_float v
  | None -> None

let bool_field name spec =
  match field name spec with
  | Some (VBool b) -> Some b
  | _ -> None

(** Pick the typed NA that matches a generator's value type. Used for
    NA injection inside [prop_gen_df]. *)
let rec na_for_spec spec =
  match spec_gen spec with
  | Some ("int" | "int_range") -> NAInt
  | Some "float_range" -> NAFloat
  | Some "bool" -> NABool
  | Some "string" -> NAString
  | Some ("map" | "such_that" | "resize") ->
      (match field "source" spec with
       | Some src -> na_for_spec src
       | None -> NAGeneric)
  | _ -> NAGeneric

(** Extract a list of strings from a "chars"-style field. Accepts a
    VString (each character is a candidate) or a List/Vector of
    VStrings. Returns None if any element is not a VString. *)
let string_list_field name spec =
  match field name spec with
  | Some (VString s) ->
      Some (String.to_seq s |> List.of_seq |> List.map (String.make 1))
  | Some (VList items) ->
      let rec go acc = function
        | [] -> Some (List.rev acc)
        | (_, VString c) :: rest -> go (c :: acc) rest
        | _ :: _ -> None
      in
      go [] items
  | Some (VVector arr) ->
      let rec go i acc =
        if i >= Array.length arr then Some (List.rev acc)
        else
          match arr.(i) with
          | VString c -> go (i + 1) (c :: acc)
          | _ -> None
      in
      go 0 []
  | _ -> None

let render_dataframe arrow_table group_keys =
  let nrows = Arrow_table.num_rows arrow_table in
  let ncols = Arrow_table.num_columns arrow_table in
  let value_columns = Arrow_bridge.table_to_value_columns arrow_table in
  let buf = Buffer.create 256 in
  Printf.bprintf buf "DataFrame(%d rows x %d cols)" nrows ncols;
  List.iter
    (fun (name, col) ->
      let col_type =
        let found = ref None in
        let i = ref 0 in
        while !found = None && !i < Array.length col do
          (match col.(!i) with
           | VNA _ -> ()
           | v -> found := Some (Utils.type_name v));
          incr i
        done;
        match !found with Some t -> t | None -> "NA"
      in
      let truncate s =
        if String.length s > 22 then String.sub s 0 19 ^ "..." else s
      in
      let shown = min 8 (Array.length col) in
      let examples = List.init shown (fun i -> truncate (Utils.value_to_string col.(i))) in
      let suffix = if Array.length col > shown then ", ..." else "" in
      Printf.bprintf buf "\n  $%-10s <%s> %s%s" name col_type
        (String.concat ", " examples) suffix)
    value_columns;
  if group_keys <> [] then
    Printf.bprintf buf "\n  grouped by [%s]" (String.concat ", " group_keys);
  Buffer.contents buf

(** Render a value for a counterexample message. DataFrames get a
    glimpse-style summary; other values use the default printer. *)
let render_value v =
  match v with
  | VDataFrame { arrow_table; group_keys } ->
      render_dataframe arrow_table group_keys
  | VVector arr ->
      let items = Array.to_list arr |> List.map Utils.value_to_string in
      "Vector[" ^ String.concat ", " items ^ "]"
  | VList items ->
      let item_to_string = function
        | (Some name, x) -> name ^ ": " ^ Utils.value_to_string x
        | (None, x) -> Utils.value_to_string x
      in
      "[" ^ (items |> List.map item_to_string |> String.concat ", ") ^ "]"
  | VDict pairs ->
      let pair_to_string (k, x) = "`" ^ k ^ "`: " ^ Utils.value_to_string x in
      "{" ^ (pairs |> List.map pair_to_string |> String.concat ", ") ^ "}"
  | other -> Utils.value_to_string other
