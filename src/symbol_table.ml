(* src/symbol_table.ml *)

type kind =
  | Variable
  | Function
  | Package
  | Column
  | Keyword

type symbol = {
  name : string;
  kind : kind;
  typ  : Semantic_type.t option;
  doc  : string option;
}

module NameMap = Map.Make(String)

type scope = symbol NameMap.t ref

let create_scope () = ref NameMap.empty

let add scope symbol =
  scope := NameMap.add symbol.name symbol !scope

let lookup scope name =
  NameMap.find_opt name !scope

let all scope =
  NameMap.bindings !scope |> List.map snd

let register_keywords scope =
  let keywords = [
    "if"; "else"; "import"; "function"; "pipeline"; "intent"; 
    "true"; "false"; "null"; "NA"; "in"
  ] in
  List.iter (fun name ->
    add scope { name; kind = Keyword; typ = None; doc = None }
  ) keywords

let value_to_semantic_type = function
  | Ast.VInt _ -> Some Semantic_type.TInt
  | Ast.VFloat _ -> Some Semantic_type.TFloat
  | Ast.VBool _ -> Some Semantic_type.TBool
  | Ast.VString _ -> Some Semantic_type.TString
  | Ast.VDataFrame { arrow_table; group_keys } ->
      let col_names = Arrow_table.column_names arrow_table in
      let cols = List.map (fun name -> { Semantic_type.name; col_typ = Semantic_type.TUnknown }) col_names in
      if group_keys = [] then Some (Semantic_type.TDataFrame cols)
      else Some (Semantic_type.TGroupedDataFrame (cols, group_keys))
  | Ast.VLambda { params; _ } ->
      let args = List.map (fun name -> (name, Semantic_type.TUnknown)) params in
      Some (Semantic_type.TFunction (args, Semantic_type.TUnknown))
  | Ast.VBuiltin { b_name = _; b_arity; b_variadic; _ } ->
      (* Builtins don't always have parameter names in the AST value, but we can try to guess or use ... *)
      let args = 
        if b_variadic then [("...", Semantic_type.TUnknown)]
        else List.init b_arity (fun i -> ("arg" ^ string_of_int (i + 1), Semantic_type.TUnknown))
      in
      Some (Semantic_type.TFunction (args, Semantic_type.TUnknown))
  | _ -> Some Semantic_type.TUnknown

let populate_from_env scope env =
  Ast.Env.iter (fun name value ->
    let kind = match value with
      | Ast.VBuiltin _ | Ast.VLambda _ -> Function
      | _ -> Variable
    in
    add scope { name; kind; typ = value_to_semantic_type value; doc = None }
  ) env

