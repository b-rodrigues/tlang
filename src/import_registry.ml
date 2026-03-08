open Ast

module Origin_map = Map.Make (String)

type binding_origin =
  | Builtin
  | ImportedPackage of string

let metadata_key = "__tlang_internal_import_origins__"

let is_internal_key name =
  name = metadata_key

let origin_to_string = function
  | Builtin -> "B"
  | ImportedPackage pkg -> "P" ^ pkg

let origin_of_string s =
  if s = "B" then Some Builtin
  else
    if String.length s > 1 && s.[0] = 'P' then
      Some (ImportedPackage (String.sub s 1 (String.length s - 1)))
    else
      None

let get_origins (env : environment) =
  match Env.find_opt metadata_key env with
  | Some (VDict pairs) ->
      List.fold_left
        (fun acc (name, value) ->
          match value with
          | VString encoded -> (
              match origin_of_string encoded with
              | Some origin -> Origin_map.add name origin acc
              | None -> acc)
          | _ -> acc)
        Origin_map.empty
        pairs
  | _ -> Origin_map.empty

let set_origins (env : environment) origins =
  let encoded =
    Origin_map.bindings origins
    |> List.map (fun (name, origin) -> (name, VString (origin_to_string origin)))
  in
  Env.add metadata_key (VDict encoded) env

let find_origin env name =
  Origin_map.find_opt name (get_origins env)

let set_origin env name origin =
  let origins = get_origins env |> Origin_map.add name origin in
  set_origins env origins

let remove_origin env name =
  let origins = get_origins env |> Origin_map.remove name in
  set_origins env origins

let mark_builtin_bindings env =
  let origins =
    Env.fold
      (fun name _ acc ->
        if name = metadata_key || Origin_map.mem name acc then acc
        else Origin_map.add name Builtin acc)
      env
      (get_origins env)
  in
  set_origins env origins
