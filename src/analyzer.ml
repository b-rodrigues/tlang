(* src/analyzer.ml *)

open Ast
open Symbol_table
open Semantic_type

type semantic_env = Symbol_table.scope

module Definition_map = Map.Make (String)

type analysis_result = {
  definitions : Ast.source_location Definition_map.t;
}

let rec infer_type scope expr =
  match expr.node with
  | Value v -> 
      (match Symbol_table.value_to_semantic_type v with
       | Some ty -> ty
       | None -> TUnknown)
  | Var name ->
      (match Symbol_table.lookup scope name with
       | Some s -> (match s.typ with Some ty -> ty | None -> TUnknown)
       | None -> TUnknown)

  | Call { fn = { node = Var ("filter" | "select" | "mutate" | "arrange" | "group_by" | "ungroup"); _ }; args = (None, data_expr) :: _; _ } ->
      infer_type scope data_expr
  | Call { fn; _ } ->
      (* Very basic: if we know the function return type, use it *)
      let fn_t = infer_type scope fn in
      (match fn_t with
       | TFunction (_, ret) -> ret
       | _ -> TUnknown)

  | Lambda { params; _ } ->
      let args = List.map (fun name -> (name, TUnknown)) params in
      TFunction (args, TUnknown)
  | ListLit _ -> TUnknown (* Should be TList *)
  | _ -> TUnknown

let add_definition definitions name = function
  | Some loc when not (Definition_map.mem name !definitions) ->
      definitions := Definition_map.add name loc !definitions
  | _ -> ()

let analyze_stmt scope definitions stmt =
  match stmt.node with
  | Assignment { name; expr; _ } ->
      let ty = infer_type scope expr in
      Symbol_table.add scope { name; kind = Variable; typ = Some ty; doc = None };
      add_definition definitions name stmt.loc
  | Reassignment { name; expr } ->
      let ty = infer_type scope expr in
      Symbol_table.add scope { name; kind = Variable; typ = Some ty; doc = None };
      add_definition definitions name stmt.loc

  | _ -> ()

let analyze program scope =
  let definitions = ref Definition_map.empty in
  List.iter (analyze_stmt scope definitions) program;
  { definitions = !definitions }
