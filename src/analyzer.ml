(* src/analyzer.ml *)

open Ast
open Symbol_table
open Semantic_type

type semantic_env = Symbol_table.scope

let rec infer_type scope expr =
  match expr with
  | Value v -> 
      (match Symbol_table.value_to_semantic_type v with
       | Some ty -> ty
       | None -> TUnknown)
  | Var name ->
      (match Symbol_table.lookup scope name with
       | Some s -> (match s.typ with Some ty -> ty | None -> TUnknown)
       | None -> TUnknown)

  | Call { fn = Var ("filter" | "select" | "mutate" | "arrange" | "group_by" | "ungroup"); args = (None, data_expr) :: _; _ } ->
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

let analyze_stmt scope stmt =
  match stmt with
  | Assignment { name; expr; _ } ->
      let ty = infer_type scope expr in
      Symbol_table.add scope { name; kind = Variable; typ = Some ty; doc = None }
  | Reassignment { name; expr } ->
      let ty = infer_type scope expr in
      Symbol_table.add scope { name; kind = Variable; typ = Some ty; doc = None }

  | _ -> ()

let analyze program scope =
  List.iter (analyze_stmt scope) program
