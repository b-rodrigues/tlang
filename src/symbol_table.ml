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

type scope = {
  symbols : symbol NameMap.t ref;
  observed_columns : string list ref;
}

let create_scope () = {
  symbols = ref NameMap.empty;
  observed_columns = ref [];
}

let copy_scope scope = {
  symbols = ref !(scope.symbols);
  observed_columns = ref !(scope.observed_columns);
}

let add scope symbol =
  scope.symbols := NameMap.add symbol.name symbol !(scope.symbols)

let add_observed_column scope name =
  let name = String.trim name in
  if name <> "" && not (List.mem name !(scope.observed_columns)) then
    scope.observed_columns := name :: !(scope.observed_columns)

let get_observed_columns scope = !(scope.observed_columns)

let lookup scope name =
  NameMap.find_opt name !(scope.symbols)

let all scope =
  NameMap.bindings !(scope.symbols) |> List.map snd

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
      let cols = List.map (fun name -> Semantic_type.{ name; col_typ = Semantic_type.TUnknown }) col_names in
      if group_keys = [] then Some (Semantic_type.TDataFrame cols)
      else Some (Semantic_type.TGroupedDataFrame (cols, group_keys))
  | Ast.VLambda { params; _ } ->
      let args = List.map (fun name -> (name, Semantic_type.TUnknown)) params in
      Some (Semantic_type.TFunction (args, Semantic_type.TUnknown))
  | Ast.VBuiltin { b_name; b_arity; b_variadic; _ } ->
      let args, ret = 
        match b_name with
        | Some name -> (
            match Tdoc_registry.lookup name with
            | Some entry -> 
                let args = List.map (fun (p : Tdoc_types.param_doc) -> 
                  (p.name, p.type_info |> Option.map Semantic_type.from_string |> Option.value ~default:Semantic_type.TAny)
                ) entry.params in
                let ret = entry.Tdoc_types.return_value 
                          |> Option.map (fun (r : Tdoc_types.return_doc) -> r.type_info |> Option.map Semantic_type.from_string |> Option.value ~default:Semantic_type.TAny)
                          |> Option.value ~default:Semantic_type.TAny
                in
                args, ret
            | None ->
                let args = 
                  if b_variadic then [("...", Semantic_type.TAny)]
                  else List.init b_arity (fun i -> ("arg" ^ string_of_int (i + 1), Semantic_type.TAny))
                in
                args, Semantic_type.TAny
          )
        | None ->
            let args = 
              if b_variadic then [("...", Semantic_type.TAny)]
              else List.init b_arity (fun i -> ("arg" ^ string_of_int (i + 1), Semantic_type.TAny))
            in
            args, Semantic_type.TAny
      in
      Some (Semantic_type.TFunction (args, ret))
  | _ -> Some Semantic_type.TUnknown

let populate_from_env scope env =
  Ast.Env.iter (fun name value ->
    let kind = match value with
      | Ast.VBuiltin _ | Ast.VLambda _ -> Function
      | _ -> Variable
    in
    add scope { name; kind; typ = value_to_semantic_type value; doc = None }
  ) env
