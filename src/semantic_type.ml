(* src/semantic_type.ml *)

type column = {
  name : string;
  col_typ : t;
}

and t =
  | TInt
  | TString
  | TBool
  | TFloat
  | TDataFrame of column list
  | TGroupedDataFrame of column list * string list
  | TFunction of (string * t) list * t
  | TList of t
  | TVector of t
  | TDict of t * t
  | TUnion of t list
  | TCustom of string
  | TAny
  | TUnknown

(** Convert a semantic type to its string representation.

    @param t The semantic type to convert.
    @return A string representation of the semantic type (e.g. "int", "grouped_dataframe[...]"). *)
let rec to_string = function
  | TInt -> "int"
  | TString -> "string"
  | TBool -> "bool"
  | TFloat -> "float"
  | TDataFrame cols ->
      let col_names = List.map (fun c -> c.name) cols in
      "to_dataframe[" ^ String.concat ", " col_names ^ "]"
  | TGroupedDataFrame (cols, groups) ->
      let col_names = List.map (fun c -> c.name) cols in
      "grouped_dataframe[" ^ String.concat ", " col_names ^ " | groups: " ^ String.concat ", " groups ^ "]"
  | TFunction (args, ret) ->
      let arg_strs = List.map (fun (name, typ) -> name ^ ": " ^ to_string typ) args in
      "Function(" ^ String.concat ", " arg_strs ^ " -> " ^ to_string ret ^ ")"
  | TList TAny -> "list"
  | TList t -> "list[" ^ to_string t ^ "]"
  | TVector TAny -> "vector"
  | TVector t -> "vector[" ^ to_string t ^ "]"
  | TDict (TString, TAny) -> "dict"
  | TDict (k, v) -> "dict[" ^ to_string k ^ ", " ^ to_string v ^ "]"
  | TUnion ts -> String.concat " | " (List.map to_string ts)
  | TCustom s -> s
  | TAny -> "any"
  | TUnknown -> "unknown"

(** Split on top-level commas (bracket depth 0). *)
let split_toplevel_comma str =
  let n = String.length str in
  let rec loop acc depth start i =
    if i >= n then List.rev (String.sub str start (i - start) :: acc)
    else
      match str.[i] with
      | '(' | '[' | '{' -> loop acc (depth + 1) start (i + 1)
      | ')' | ']' | '}' -> loop acc (depth - 1) start (i + 1)
      | ',' when depth = 0 ->
          loop (String.sub str start (i - start) :: acc) depth (i + 1) (i + 1)
      | _ -> loop acc depth start (i + 1)
  in
  List.map String.trim (loop [] 0 0 0)

(** Split on top-level pipes (bracket depth 0). *)
let split_toplevel_pipe str =
  let n = String.length str in
  let rec loop acc depth start i =
    if i >= n then List.rev (String.sub str start (i - start) :: acc)
    else
      match str.[i] with
      | '(' | '[' | '{' -> loop acc (depth + 1) start (i + 1)
      | ')' | ']' | '}' -> loop acc (depth - 1) start (i + 1)
      | '|' when depth = 0 ->
          loop (String.sub str start (i - start) :: acc) depth (i + 1) (i + 1)
      | _ -> loop acc depth start (i + 1)
  in
  List.map String.trim (loop [] 0 0 0)

(** Parse a semantic type from its string representation.

    @param str The string representation of the type to parse.
    @return The corresponding semantic type [t], defaulting to [TAny] or [TUnknown] on mismatch. *)
let rec from_string str =
  let str = String.lowercase_ascii (String.trim str) in
  match str with
  | "int" | "integer" -> TInt
  | "string" | "text" -> TString
  | "bool" | "boolean" | "logical" -> TBool
  | "float" | "double" | "number" | "numeric" -> TFloat
  | "to_dataframe" | "table" | "dataframe" -> TDataFrame []
  | "any" | "value" | "all" | "mixed" | "..." -> TAny
  (* Nominal domain types, canonicalized to the annotation spelling
     (annotations preserve case, so `Model` must stay `Model`). These only
     ever match themselves (or Any), so they add precision without new
     mismatch classes: a misspelled name simply never matches a real
     annotation. Deliberately excluded: Function (arity lives in
     TFunction), Error/VError/Null (descriptive positions, not
     contracts), NA (bottom rules own it). *)
  | "pipeline" -> TCustom "Pipeline"
  | "metapipeline" -> TCustom "MetaPipeline"
  | "model" -> TCustom "Model"
  | "ndarray" -> TCustom "NDArray"
  | "symbol" -> TCustom "Symbol"
  | "date" -> TCustom "Date"
  | "datetime" -> TCustom "Datetime"
  | "formula" -> TCustom "Formula"
  | "lens" -> TCustom "Lens"
  | "strategy" -> TCustom "Strategy"
  | "factor" -> TCustom "Factor"
  | "noderesult" -> TCustom "NodeResult"
  | "record" -> TCustom "Record"
  | "intent" -> TCustom "Intent"
  | "quosure" -> TCustom "Quosure"
  | "expr" -> TCustom "Expr"
  | "buildlog" -> TCustom "BuildLog"
  | "expect" -> TCustom "Expect"
  | "computednode" -> TCustom "ComputedNode"
  | "nodedef" -> TCustom "NodeDef"
  | "period" -> TCustom "Period"
  | "duration" -> TCustom "Duration"
  | "interval" -> TCustom "Interval"
  | "list" -> TList TAny
  | "vector" -> TVector TAny
  | "dict" -> TDict (TString, TAny)
  | _ ->
      if has_toplevel_pipe str then
        (* Unions stay precise member-wise. Empty segments are dropped; a
           single surviving member needs no union; an Any member absorbs
           the whole union (it matches everything anyway). Members keep
           declaration order (deduped) so messages read naturally. *)
        let members =
          split_toplevel_pipe str
          |> List.filter (fun s -> s <> "")
          |> List.map from_string
          |> List.fold_left (fun acc m -> if List.mem m acc then acc else acc @ [m]) []
        in
        (match members with
         | [] -> TAny
         | [m] -> m
         | ms when List.exists (( = ) TAny) ms -> TAny
         | ms -> TUnion ms)
      else
        (match parse_bracketed str with
         | Some ("list", inner) -> TList (from_string inner)
         | Some ("vector", inner) -> TVector (from_string inner)
         | Some ("dict", inner) ->
             (match split_toplevel_comma inner with
              | [k; v] -> TDict (from_string k, from_string v)
              (* Bare `Dict[X]`: keys are always strings (VDict pairs in
                 ast.ml), so only the value type is given. *)
              | [v] -> TDict (TString, from_string v)
              | _ -> TAny)
         | Some _ | None ->
             if String.starts_with ~prefix:"vector" str
                || String.starts_with ~prefix:"list" str then TAny
             else TUnknown)

and has_toplevel_pipe str =
  let n = String.length str in
  let rec loop depth i =
    if i >= n then false
    else
      match str.[i] with
      | '(' | '[' | '{' -> loop (depth + 1) (i + 1)
      | ')' | ']' | '}' -> loop (depth - 1) (i + 1)
      | '|' when depth = 0 -> true
      | _ -> loop depth (i + 1)
  in
  loop 0 0

and parse_bracketed str =
  let n = String.length str in
  let rec find_open i =
    if i >= n then None
    else if str.[i] = '[' then Some i
    else if str.[i] = '(' || str.[i] = ')' || str.[i] = ']' then None
    else find_open (i + 1)
  in
  match find_open 0 with
  | None -> None
  | Some o ->
      let name = String.trim (String.sub str 0 o) in
      let rec balanced i d =
        if i >= n then false
        else if str.[i] = '[' then balanced (i + 1) (d + 1)
        else if str.[i] = ']' then (d = 1 && i = n - 1) || balanced (i + 1) (d - 1)
        else balanced (i + 1) d
      in
      if n > 0 && str.[n - 1] = ']' && balanced (o + 1) 1 then
        Some (name, String.sub str (o + 1) (n - o - 2))
      else None

(** Convert a semantic type to an AST type for comparison with annotations.

    @param t The semantic type to convert.
    @return The corresponding AST type [Ast.typ]. *)
let rec to_ast_typ (t : t) : Ast.typ =
  let of_opt = function TAny | TUnknown -> None | t -> Some (to_ast_typ t) in
  match t with
  | TInt -> Ast.TInt
  | TString -> Ast.TString
  | TBool -> Ast.TBool
  | TFloat -> Ast.TFloat
  | TDataFrame _ -> Ast.TDataFrame None
  | TGroupedDataFrame _ -> Ast.TDataFrame None
  | TFunction (args, ret) ->
      let param_types = List.map (fun (_, t) -> to_ast_typ t) args in
      Ast.TArrow (param_types, to_ast_typ ret)
  | TList t -> Ast.TList (of_opt t)
  | TVector t -> Ast.TList (of_opt t)
  | TDict (k, v) -> Ast.TDict (of_opt k, of_opt v)
  | TUnion ts -> Ast.TUnion (List.map to_ast_typ ts)
  | TCustom s -> Ast.TCustom s
  | TAny -> Ast.TCustom "Any"
  | TUnknown -> Ast.TUnknown
