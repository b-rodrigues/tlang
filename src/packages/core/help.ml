(* src/packages/core/help.ml *)
open Ast

(*
--# Display documentation for a function
--#
--# Prints the help documentation for the specified function, including
--# signature, parameters, return value, and examples.
--#
--# @name help
--# @param name :: String | Symbol The name of the function to document.
--# @return :: Null
--# @example
--#   help("mean")
--#   help(print)
--# @family core
--# @seealso apropos
--# @export
*)
let rec help_impl args _env =
  match args with
  | [VString name] ->
      (match Tdoc_registry.lookup name with
      | Some doc ->
          let brief = if doc.description_brief <> "" then doc.description_brief else "No description available." in
          let sig_str = Printf.sprintf "%s -> %s" 
            (String.concat ", " (List.map (fun (p : Tdoc_types.param_doc) -> p.name) doc.params))
            (match doc.return_value with Some r -> (match r.type_info with Some t -> t | None -> "Any") | None -> "Any")
          in
          let output = Printf.sprintf "\n  %s\n\n  %s\n  Signature: %s(%s)\n" 
            name brief name sig_str in
          
          let output = output ^ "\n  Parameters:\n" ^ 
            (String.concat "\n" (List.map (fun (p : Tdoc_types.param_doc) -> 
              Printf.sprintf "    - %s%s: %s" 
                p.name 
                (match p.type_info with Some t -> " (" ^ t ^ ")" | None -> "")
                p.description
            ) doc.params)) ^ "\n" in
            
          let output = match doc.return_value with
            | Some r -> output ^ Printf.sprintf "\n  Returns:\n    %s%s\n" 
                (match r.type_info with Some t -> "(" ^ t ^ ") " | None -> "") r.description
            | None -> output
          in

          let output = if doc.examples <> [] then
            output ^ "\n  Examples:\n" ^
            (String.concat "\n" (List.map (fun e -> 
               let lines = String.split_on_char '\n' e in
               String.concat "\n" (List.map (fun l -> "    " ^ l) lines)
            ) doc.examples)) ^ "\n"
          else output in

          print_endline output;
          VNull
      | None ->
          Printf.printf "No documentation found for '%s'.\n" name;
          VNull)
  | [VSymbol name] ->
      (* Support help(mean) as well as help("mean") *)
      help_impl [VString name] _env
  | [VBuiltin _] ->
      (* User passed the function value itself. Ideally we'd need reverse lookup or metadata attached to values. *)
      (* For now, explain we need the name. *)
      Printf.printf "Please provide the function name as a string or symbol, e.g. help(\"mean\") or help(mean).\n";
      VNull
  | _ ->
      Error.type_error "help expects a function name (String or Symbol)."

(*
--# Search for functions by keyword
--#
--# Searches all documented functions for names or descriptions matching the query.
--#
--# @name apropos
--# @param query :: String The keyword to search for.
--# @return :: Null
--# @example
--#   apropos("stat")
--#   -- Finds functions like "fit_stats", "mean", "sd", etc.
--# @family core
--# @seealso help
--# @export
*)
let apropos_impl args _env =
  match args with
  | [VString query] ->
      let all_docs = Tdoc_registry.get_all () in
      
      let query_low = String.lowercase_ascii query in
      let matches = List.filter (fun (doc : Tdoc_types.doc_entry) ->
        let name_low = String.lowercase_ascii doc.name in
        let desc_low = String.lowercase_ascii doc.description_brief in
        
        let contains s1 s2 = 
          try 
            let len1 = String.length s1 in
            let len2 = String.length s2 in
            if len2 > len1 then false else
            let rec loop i =
              if i > len1 - len2 then false
              else if String.sub s1 i len2 = s2 then true
              else loop (i + 1)
            in loop 0
          with _ -> false
        in
        contains name_low query_low || contains desc_low query_low
      ) all_docs in

      if matches = [] then
        Printf.printf "No documents found matching '%s'.\n" query
      else begin
        Printf.printf "Found %d matches:\n" (List.length matches);
        List.iter (fun (doc : Tdoc_types.doc_entry) ->
          Printf.printf "  %-20s %s\n" doc.name doc.description_brief
        ) matches
      end;
      VNull
  | _ ->
      Error.type_error "apropos expects a query string."

let register env =
  let env = Env.add "help" (make_builtin ~name:"help" 1 help_impl) env in
  let env = Env.add "apropos" (make_builtin ~name:"apropos" 1 apropos_impl) env in
  env
