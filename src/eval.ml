(* src/eval.ml *)

open Ast

exception RuntimeError of string

(* Environment: maps symbols to values *)
module Env = struct
  type t = (symbol, value) Hashtbl.t

  let empty () = Hashtbl.create 32
  let copy env = Hashtbl.copy env

  let get env key =
    try Hashtbl.find env key
    with Not_found -> VError ("Unbound variable: " ^ key)

  let set env key value =
    Hashtbl.replace env key value

  let of_bindings bindings =
    let env = empty () in
    List.iter (fun (k, v) -> set env k v) bindings;
    env
end

let global_env : Env.t = Env.empty ()

(* Unwrap errors, propagating exceptions *)
let unwrap = function
  | VError msg -> raise (RuntimeError msg)
  | v -> v

(* Built-in printers registry *)
module Print_builtin = struct
  let printers : (string * (value -> bool)) list ref = ref []

  let register ~tag f =
    printers := (tag, f) :: !printers

  let dispatch v =
    let handled =
      List.exists (fun (_, f) -> f v) !printers
    in
    if not handled then Printf.printf "<unhandled value>\n"
end

(* Pretty-printing for tables *)
let () =
  Print_builtin.register ~tag:"table" (function
    | VTable columns ->
        let col_names = List.map fst columns in
        let rows =
          let col_lists = List.map snd columns in
          let row_count =
            match col_lists with
            | [] -> 0
            | vs :: _ -> List.length (match vs with VList xs -> xs | _ -> [])
          in
          let get_col_row cidx ridx =
            match List.nth col_lists cidx with
            | VList xs -> (try List.nth xs (ridx - 1) with _ -> VNull)  (* 1-indexed *)
            | _ -> VNull
          in
          let rec build_rows r =
            if r > row_count then []
            else
              (List.init (List.length col_lists) (fun c -> get_col_row c r))
              :: build_rows (r + 1)
          in
          build_rows 1
        in
        (* Print header *)
        Printf.printf "| %s |\n" (String.concat " | " col_names);
        Printf.printf "|%s|\n"
          (String.concat "" (List.map (fun _ -> "------|") col_names));
        (* Print rows *)
        List.iter (fun row ->
          Printf.printf "| %s |\n"
            (String.concat " | " (List.map
              (function
                | VString s -> s
                | VInt i -> string_of_int i
                | VFloat f -> string_of_float f
                | VNull -> ""
                | VBool b -> string_of_bool b
                | _ -> "<complex>"
              ) row))
        ) rows;
        true
    | _ -> false
  )

(* Apply a function value to arguments *)
let rec apply fn_val args env =
  match fn_val with
  | VLambda { params; body } ->
      if List.length params <> List.length args then
        VError "Incorrect number of arguments"
      else
        let local_env = Env.copy env in
        List.iter2 (Env.set local_env) params args;
        eval local_env body
  | VBuiltin f -> f args
  | _ -> VError "Not a function"

(* 1-indexed access for VList and VTable *)
let get_nth lst idx =
  if idx < 1 || idx > List.length lst then
    VError ("Index out of bounds (1-indexed): " ^ string_of_int idx)
  else
    List.nth lst (idx - 1)

(* Add similar 1-indexed access logic for any other built-in or helper function that works with user-supplied indices *)
