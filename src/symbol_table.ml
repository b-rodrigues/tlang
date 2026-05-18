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

(** Create a fresh, empty semantic analysis scope.
    
    @return A new [scope] record with empty symbols, columns, and dataframes maps. *)
let create_scope () = {
  symbols = ref NameMap.empty;
  observed_columns = ref StringSet.empty;
  dataframe_symbols = ref StringSet.empty;
}

(** Create a shallow copy of a semantic analysis scope.
    
    @param scope The scope to duplicate.
    @return A new duplicated [scope] pointing to copies of the original maps. *)
let copy_scope scope = {
  symbols = ref !(scope.symbols);
  observed_columns = ref !(scope.observed_columns);
  dataframe_symbols = ref !(scope.dataframe_symbols);
}

(** Add a symbol to the current scope.
    
    If the symbol is a DataFrame or GroupedDataFrame, it will also be tracked
    in the dataframe symbols list.
    
    @param scope The target scope.
    @param symbol The symbol to add. *)
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

(** Track a column name referenced within the scope.
    
    @param scope The scope to record in.
    @param name The column name to register. *)
let add_observed_column scope name =
  let name = String.trim name in
  if name <> "" then
    scope.observed_columns := StringSet.add name !(scope.observed_columns)

(** Retrieve the list of column names observed within the scope.
    
    @param scope The scope to read.
    @return A string list of column names. *)
let get_observed_columns scope = StringSet.elements !(scope.observed_columns)

(** Get all symbols in the scope that are of DataFrame types.
    
    @param scope The scope to search.
    @return A list of symbols corresponding to active dataframes. *)
let get_dataframes scope =
  StringSet.elements !(scope.dataframe_symbols)
  |> List.filter_map (fun name -> NameMap.find_opt name !(scope.symbols))

(** Lookup a symbol by its name.
    
    @param scope The scope to search.
    @param name The name of the symbol.
    @return [Some symbol] if defined, otherwise [None]. *)
let lookup scope name =
  NameMap.find_opt name !(scope.symbols)

(** Retrieve all symbols defined in the current scope.
    
    @param scope The scope to read.
    @return A list of all symbols in the scope. *)
let all scope =
  NameMap.bindings !(scope.symbols) |> List.map snd

(** Filter symbols in the scope that start with a given prefix.
    
    Used primarily for autocompletion.
    
    @param scope The scope to query.
    @param prefix The prefix string to match against.
    @return A list of symbols starting with [prefix]. *)
let filter_symbols scope prefix =
  NameMap.to_seq_from prefix !(scope.symbols)
  |> Seq.take_while (fun (name, _) -> String.starts_with ~prefix name)
  |> Seq.map snd
  |> List.of_seq

(** Pre-populate a scope with T-Lang keywords.
    
    @param scope The scope to register keywords in. *)
let register_keywords scope =
  let keywords = [
    "if"; "else"; "import"; "function"; "pipeline"; "intent"; 
    "true"; "false"; "null"; "NA"; "in"
  ] in
  List.iter (fun name ->
    add scope { name; kind = Keyword; typ = None; doc = None }
  ) keywords

let builtin_typ_cache = Hashtbl.create 100

(** Infer the semantic type of a runtime AST value.
    
    Utilizes caching for builtins to optimize repeated queries.
    
    @param v The AST value.
    @return [Some semantic_type] representing the value's type structure, or [None]. *)
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

(** Populates the scope symbols by extracting names and values from an evaluation environment.
    
    @param scope The target scope to populate.
    @param env The evaluation environment. *)
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
