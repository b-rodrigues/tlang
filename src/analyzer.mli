(* src/analyzer.mli *)

type semantic_env = Symbol_table.scope

module Definition_map : Map.S with type key = String.t

type analysis_result = {
  definitions : Ast.source_location Definition_map.t;
}

val infer_type : Symbol_table.scope -> Ast.expr -> Semantic_type.t

val analyze_stmt : Symbol_table.scope -> Ast.source_location Definition_map.t ref -> Ast.stmt -> unit

val analyze : Ast.stmt list -> Symbol_table.scope -> analysis_result
