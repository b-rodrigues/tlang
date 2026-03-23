open Ast

(*
--# Trace Pipeline Nodes
--#
--# Prints a visual dependency tree of the pipeline nodes.
--#
--# @name trace_nodes
--# @param p :: Pipeline The pipeline to inspect.
--# @param name :: String (Optional) A specific node's name to trace.
--# @param transitive :: Bool (Optional) If true, mark transitive dependencies with '*'.
--# @return :: Null Returns invisibly. Prints to the console.
--# @example
--#   p = pipeline { x = 1; y = x + 1 }
--#   trace_nodes(p)
--#   trace_nodes(p, "y")
--# @family pipeline
--# @export
*)
let register env =
  let trace_fn named_args _env =
    let get_arg arg_name pos default =
      match List.find_opt (fun (k, _) -> k = Some arg_name) named_args with
      | Some (_, v) -> (true, v)
      | None ->
          let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
          if List.length positionals >= pos then (true, List.nth positionals (pos - 1))
          else (false, default)
    in
    match get_arg "p" 1 VNull with
    | (_, VPipeline p) ->
        let (_, target_val) = get_arg "name" 2 VNull in
        let (_, trans_val) = get_arg "transitive" 3 (VBool true) in
        
        let target_res = match target_val with 
          | VString s -> Ok (Some s) 
          | VNull -> Ok None 
          | v -> Error (Error.type_error (Printf.sprintf "Function `trace_nodes` expects a String for 'name', got %s." (Utils.type_name v))) 
        in
        let trans_res = match trans_val with 
          | VBool b -> Ok b 
          | VNull -> Ok true 
          | v -> Error (Error.type_error (Printf.sprintf "Function `trace_nodes` expects a Bool for 'transitive', got %s." (Utils.type_name v))) 
        in
        
        begin match target_res, trans_res with
        | Error e, _ | _, Error e -> e
        | Ok target, Ok transitive ->
          let deps_map = p.p_deps in
        let all_names = List.map fst deps_map in
        
        (* Reverse map: child -> list of parents that depend on child *)
        let reverse_map =
          let tbl = Hashtbl.create (List.length all_names) in
          List.iter (fun n -> Hashtbl.add tbl n []) all_names;
          List.iter (fun (src, deps) ->
            List.iter (fun dep ->
              let curr = try Hashtbl.find tbl dep with Not_found -> [] in
              Hashtbl.replace tbl dep (src :: curr)
            ) deps
          ) deps_map;
          tbl
        in

        let get_sinks () =
          List.filter (fun n ->
            let rev = try Hashtbl.find reverse_map n with Not_found -> [] in
            List.length rev = 0
          ) all_names
        in

        let trace_forest roots =
          let visited = Hashtbl.create 10 in
          let rec rec_print node depth =
            let indent = String.make (depth * 2) ' ' in
            let star = if transitive && depth >= 2 then "*" else "" in
            Printf.printf "%s- %s%s\n" indent node star;
            if not (Hashtbl.mem visited node) then begin
              Hashtbl.add visited node true;
              let children = match List.assoc_opt node deps_map with Some d -> d | None -> [] in
              List.iter (fun c -> rec_print c (depth + 1)) children
            end
          in
          List.iter (fun r -> rec_print r 0) roots
        in

        let trace_single node =
          Printf.printf "==== Lineage for: %s ====\n" node;
          Printf.printf "Dependencies (ancestors):\n";
          let visited = Hashtbl.create 10 in
          let rec rec_dep n depth =
            let parents = match List.assoc_opt n deps_map with Some d -> d | None -> [] in
            if parents = [] then begin
              if depth = 0 then Printf.printf "  - <none>\n"
            end else begin
              List.iter (fun p ->
                let indent = String.make ((depth + 1) * 2) ' ' in
                let star = if transitive && depth >= 1 then "*" else "" in
                Printf.printf "%s- %s%s\n" indent p star;
                if not (Hashtbl.mem visited p) then begin
                  Hashtbl.add visited p true;
                  rec_dep p (depth + 1)
                end
              ) parents
            end
          in
          rec_dep node 0;

          Printf.printf "\nReverse dependencies (children):\n";
          Hashtbl.clear visited;
          let rec rec_rev n depth =
            let kids = try Hashtbl.find reverse_map n with Not_found -> [] in
            if kids = [] then begin
              if depth = 0 then Printf.printf "  - <none>\n"
            end else begin
              List.iter (fun k ->
                let indent = String.make ((depth + 1) * 2) ' ' in
                let star = if transitive && depth >= 1 then "*" else "" in
                Printf.printf "%s- %s%s\n" indent k star;
                if not (Hashtbl.mem visited k) then begin
                  Hashtbl.add visited k true;
                  rec_rev k (depth + 1)
                end
              ) kids
            end
          in
          rec_rev node 0
        in

        begin match target with
        | None ->
            Printf.printf "==== Pipeline dependency tree (outputs → inputs) ====\n";
            let sinks = get_sinks () in
            trace_forest (if sinks = [] then all_names else sinks);
            if transitive then Printf.printf "\nNote: '*' marks transitive dependencies (depth >= 2).\n\n"
        | Some node ->
            if not (List.mem node all_names) then
              Printf.eprintf "Derivation '%s' not found in pipeline.\n" node
            else begin
              trace_single node;
              if transitive then Printf.printf "\nNote: '*' marks transitive dependencies (depth >= 2).\n\n"
            end
        end;
        flush stdout;
        VNull
        end
    | _ -> Error.type_error "Function `trace_nodes` expects a Pipeline as its first argument."
  in
  Env.add "trace_nodes" (make_builtin_named ~name:"trace_nodes" ~variadic:true 1 trace_fn) env
