(* src/tdoc/tdoc_json.ml *)
(* JSON wrapper using Yojson for robustness *)

type json = Yojson.Safe.t

exception Json_error of string

let from_string str =
  try
    Yojson.Safe.from_string str
  with
  | Yojson.Json_error msg -> raise (Json_error msg)
  | _ -> raise (Json_error "Unknown JSON error")

let member key json =
  match json with
  | `Assoc pairs -> List.assoc_opt key pairs
  | _ -> None

let to_string json =
  match json with
  | `String s -> Some s
  | _ -> None

let to_int json =
  match json with
  | `Int i -> Some i
  | _ -> None

let to_bool json =
  match json with
  | `Bool b -> Some b
  | _ -> None

let to_list json =
  match json with
  | `List l -> Some l
  | _ -> None

(* Shorthands for matching Yojson variants in other modules *)
let pattern_match_bool = function
  | `Bool b -> b
  | _ -> false

let pattern_match_array = function
  | `List l -> l
  | _ -> []
