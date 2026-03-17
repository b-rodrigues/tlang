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
module StringSet = Set.Make(String)

type scope = {
  symbols : symbol NameMap.t ref;
  observed_columns : StringSet.t ref;
  dataframe_symbols : StringSet.t ref;
}

let create_scope () = {
  symbols = ref NameMap.empty;
  observed_columns = ref StringSet.empty;
  dataframe_symbols = ref StringSet.empty;
}

let copy_scope scope = {
  symbols = ref !(scope.symbols);
  observed_columns = ref !(scope.observed_columns);
  dataframe_symbols = ref !(scope.dataframe_symbols);
}

let add scope symbol =
  scope.symbols := NameMap.add symbol.name symbol !(scope.symbols);
  match symbol.typ with
  | Some (Semantic_type.TDataFrame _)
  | Some (Semantic_type.TGroupedDataFrame _) ->
      if not (StringSet.mem symbol.name !(scope.dataframe_symbols)) then
        scope.dataframe_symbols := StringSet.add symbol.name !(scope.dataframe_symbols)
  | _ -> 
      if StringSet.mem symbol.name !(scope.dataframe_symbols) then
        scope.dataframe_symbols := StringSet.remove symbol.name !(scope.dataframe_symbols)

let add_observed_column scope name =
  let name = String.trim name in
  if name <> "" then
    scope.observed_columns := StringSet.add name !(scope.observed_columns)

let get_observed_columns scope = StringSet.elements !(scope.observed_columns)

let get_dataframes scope =
  StringSet.elements !(scope.dataframe_symbols)
  |> List.filter_map (fun name -> NameMap.find_opt name !(scope.symbols))

let lookup scope name =
  NameMap.find_opt name !(scope.symbols)

let all scope =
  NameMap.bindings !(scope.symbols) |> List.map snd

let filter_symbols scope prefix =
  NameMap.to_seq_from prefix !(scope.symbols)
  |> Seq.take_while (fun (name, _) -> String.starts_with ~prefix name)
  |> Seq.map snd
  |> List.of_seq

let register_keywords scope =
  let keywords = [
    "if"; "else"; "import"; "function"; "pipeline"; "intent"; 
    "true"; "false"; "null"; "NA"; "in"
  ] in
  List.iter (fun name ->
    add scope { name; kind = Keyword; typ = None; doc = None }
  ) keywords

let builtin_typ_cache = Hashtbl.create 100

let value_to_semantic_type v =
  match v with
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
      let cache_key = match b_name with Some n -> n | None -> "arity:" ^ string_of_int b_arity ^ (if b_variadic then "+" else "") in
      (match Hashtbl.find_opt builtin_typ_cache cache_key with
       | Some t -> Some t
       | None ->
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
          let res = Semantic_type.TFunction (args, ret) in
          Hashtbl.add builtin_typ_cache cache_key res;
          Some res)
  | _ -> Some Semantic_type.TUnknown

let populate_from_env scope env =
  let (new_symbols, new_dfs) = Ast.Env.fold (fun name value (acc_s, acc_d) ->
    let kind = match value with
      | Ast.VBuiltin _ | Ast.VLambda _ -> Function
      | _ -> Variable
    in
    let typ = value_to_semantic_type value in
    let symbol = { name; kind; typ; doc = None } in
    let acc_s' = NameMap.add name symbol acc_s in
    let acc_d' = match typ with
      | Some (Semantic_type.TDataFrame _)
      | Some (Semantic_type.TGroupedDataFrame _) ->
          StringSet.add name acc_d
      | _ -> 
          if StringSet.mem name acc_d then StringSet.remove name acc_d else acc_d
    in
    (acc_s', acc_d')
  ) env (!(scope.symbols), !(scope.dataframe_symbols)) in
  scope.symbols := new_symbols;
  scope.dataframe_symbols := new_dfs
