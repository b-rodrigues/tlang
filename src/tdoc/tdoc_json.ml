(* src/tdoc/tdoc_json.ml *)
(* JSON wrapper using Yojson for robustness *)

type json = Yojson.Safe.t

exception Json_error of string

(** Parse a JSON string into a Safe Yojson data structure.
    
    @param str The JSON-encoded string.
    @return The parsed [Yojson.Safe.t] value.
    @raise Json_error if parsing fails. *)
let from_string str =
  try
    Yojson.Safe.from_string str
  with
  | Yojson.Json_error msg -> raise (Json_error msg)
  | _ -> raise (Json_error "Unknown JSON error")

(** Retrieve a specific object key's member from a JSON object structure.
    
    @param key The object key to find.
    @param json The input JSON element.
    @return [Some json] if found and is an object, [None] otherwise. *)
let member key json =
  match json with
  | `Assoc pairs -> List.assoc_opt key pairs
  | _ -> None

(** Extract a string value from a JSON string element.
    
    @param json The JSON value.
    @return [Some string] if it is a JSON string, otherwise [None]. *)
let to_string json =
  match json with
  | `String s -> Some s
  | _ -> None

(** Extract an integer value from a JSON int element.
    
    @param json The JSON value.
    @return [Some int] if it is a JSON int, otherwise [None]. *)
let to_int json =
  match json with
  | `Int i -> Some i
  | _ -> None

(** Extract a boolean value from a JSON bool element.
    
    @param json The JSON value.
    @return [Some bool] if it is a JSON bool, otherwise [None]. *)
let to_bool json =
  match json with
  | `Bool b -> Some b
  | _ -> None

(** Extract a list of JSON elements from a JSON array element.
    
    @param json The JSON value.
    @return [Some json list] if it is a JSON array, otherwise [None]. *)
let to_list json =
  match json with
  | `List l -> Some l
  | _ -> None

(* Shorthands for matching Yojson variants in other modules *)

(** Safely unpack a JSON bool element, defaulting to false if not a boolean.
    
    @param json The JSON value.
    @return The boolean value. *)
let pattern_match_bool = function
  | `Bool b -> b
  | _ -> false

(** Safely unpack a JSON array element, defaulting to empty list if not an array.
    
    @param json The JSON value.
    @return The list of JSON elements. *)
let pattern_match_array = function
  | `List l -> l
  | _ -> []
