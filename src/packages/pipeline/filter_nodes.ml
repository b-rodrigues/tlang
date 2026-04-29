open Ast

let node_record name value diagnostics =
  VDict [
    ("name", VString name);
    ("value", value);
    ("diagnostics", Ast.Utils.node_diagnostics_to_value diagnostics);
  ]

let get_node_record p name value =
  let diagnostics =
    match List.assoc_opt name p.p_node_diagnostics with
    | Some diagnostics -> diagnostics
    | None -> Ast.Utils.empty_node_diagnostics
  in
  node_record name value diagnostics

let eval_node_predicate ~eval_call env predicate node =
  match eval_call env predicate [(None, Ast.mk_expr (Value node))] with
  | VBool b -> Ok b
  | VError _ as e -> Error e
  | other ->
      Error
        (Error.type_error
           (Printf.sprintf
              "Function `filter_nodes` predicate must return Bool, got %s."
              (Utils.type_name other)))

(*
--# Filter Readable Pipeline Node Records
--#
--# Returns the node records from `read_pipeline(p).nodes` that satisfy a
--# predicate. Unlike `filter_node`, this is a read-only query helper: it does
--# not return a new Pipeline. Predicates can be written either as explicit
--# functions (for example `\(node) !is_na(node.diagnostics.error)`) or as
--# concise expressions that refer directly to node-record fields such as
--# `name`, `value`, and `diagnostics`.
--#
--# @name filter_nodes
--# @param p :: Pipeline The pipeline to inspect.
--# @param predicate :: Function A predicate over read-pipeline node records.
--# @return :: List A list of node records from `read_pipeline(p).nodes`.
--# @example
--#   filter_nodes(p, !is_na(diagnostics.error))
--#   filter_nodes(p, name == "model")
--#   filter_nodes(p, \(node) node.name == "model")
--# @family pipeline
--# @seealso read_pipeline, filter_node, select_node
--# @export
*)
let filter_nodes_impl ~eval_call args env =
  match args with
  | [VPipeline p; predicate] ->
      let rec aux acc = function
        | [] -> VList (List.rev acc)
        | (name, value) :: rest ->
            let node = get_node_record p name value in
            (match eval_node_predicate ~eval_call env predicate node with
             | Ok true -> aux ((None, node) :: acc) rest
             | Ok false -> aux acc rest
             | Error e -> e)
      in
      aux [] p.p_nodes
  | [_; _] -> Error.type_error "Function `filter_nodes` expects a Pipeline as first argument."
  | _ -> Error.arity_error_named "filter_nodes" 2 (List.length args)

(*
--# Get Errored Pipeline Nodes
--#
--# Returns the read-pipeline node records whose `diagnostics.error` field is
--# not `NA`. This is a convenience wrapper around `filter_nodes`.
--#
--# @name errored_nodes
--# @param p :: Pipeline The pipeline to inspect.
--# @return :: List A list of node records with captured errors.
--# @example
--#   errored_nodes(p)
--# @family pipeline
--# @seealso filter_nodes, read_pipeline
--# @export
*)
let errored_nodes_impl ~eval_call args env =
  let predicate =
    VLambda {
      params = ["node"];
      autoquote_params = [false];
      param_types = [None];
      return_type = None;
      generic_params = [];
      variadic = false;
      body =
        Ast.mk_expr
          (UnOp {
             op = Not;
             operand =
               Ast.mk_expr
                 (Call {
                    fn = Ast.mk_expr (Var "is_na");
                    args = [
                      (None,
                       Ast.mk_expr
                         (DotAccess {
                            target =
                              Ast.mk_expr
                                (DotAccess {
                                   target = Ast.mk_expr (Var "node");
                                   field = "diagnostics";
                                 });
                            field = "error";
                          }));
                    ];
                  });
           });
      env = Some env;
    }
  in
  match args with
  | [pipeline] -> filter_nodes_impl ~eval_call [pipeline; predicate] env
  | _ -> Error.arity_error_named "errored_nodes" 1 (List.length args)

let register ~eval_call env =
  env
  |> Env.add "filter_nodes"
       (make_builtin ~name:"filter_nodes" 2 (fun args env ->
          filter_nodes_impl ~eval_call args env))
  |> Env.add "errored_nodes"
       (make_builtin ~name:"errored_nodes" 1 (fun args env ->
          match args with
          | [VPipeline _] -> errored_nodes_impl ~eval_call args env
          | [_] -> Error.type_error "Function `errored_nodes` expects a Pipeline."
          | _ -> Error.arity_error_named "errored_nodes" 1 (List.length args)))
