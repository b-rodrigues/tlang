open Ast

let rec nth_safe n = function
  | h :: _ when n = 0 -> Some h
  | _ :: t -> nth_safe (n - 1) t
  | [] -> None

let resolve_pipeline_name env (p : pipeline_result) : string option =
  Env.fold (fun k val_v acc ->
    match acc with
    | Some _ -> acc
    | None ->
        match val_v with
        | VPipeline p' when p'.p_exprs = p.p_exprs -> Some k
        | VMetaPipeline _ ->
            (match Pipeline_composition.flatten_meta val_v with
             | VPipeline flat_p when flat_p.p_exprs = p.p_exprs -> Some k
             | _ -> None)
        | _ -> None
  ) env None
