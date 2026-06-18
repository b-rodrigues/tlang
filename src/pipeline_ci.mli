(** CI export helpers for T pipelines. *)

val register : Ast.value Ast.Env.t -> Ast.value Ast.Env.t
(** Register [pipeline_ci] in the provided environment. *)
