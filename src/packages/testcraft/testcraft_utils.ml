open Ast

let fmt v = "`" ^ Utils.value_to_string v ^ "`"

(* Extract a list of strings from a VList or VVector. Returns None if
   any element is not a VString. *)
let extract_string_list = function
  | VList items ->
      let rec go acc = function
        | [] -> Some (List.rev acc)
        | (_, VString s) :: rest -> go (s :: acc) rest
        | (_, _) :: _ -> None
      in
      go [] items
  | VVector arr ->
      let rec go i acc =
        if i >= Array.length arr then Some (List.rev acc)
        else match arr.(i) with
          | VString s -> go (i + 1) (s :: acc)
          | _ -> None
      in
      go 0 []
  | VString s -> Some [s]
  | _ -> None

let list_of_strings_to_string items =
  "[" ^ String.concat ", " (List.map (fun s -> "\"" ^ s ^ "\"") items) ^ "]"
