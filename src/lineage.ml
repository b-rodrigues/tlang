(* src/lineage.ml *)

(** Pipeline lineage helpers shared by `explain` (t_explain.ml) and
    `t explain --node` (repl.ml), so the two outputs cannot drift. *)

(** Order-preserving de-duplication. Keeps the first occurrence of each
    name, so display order never changes. *)
let dedup names =
  let seen = Hashtbl.create 16 in
  List.filter (fun n ->
    if Hashtbl.mem seen n then false
    else (Hashtbl.replace seen n (); true)
  ) names

(** Transitive closure over a step function (direct neighbors).
    Returns nodes nearest-first (direct neighbors first, in step order),
    de-duplicated, self excluded. The visited set keeps this safe on
    cyclic graphs. *)
let closure step target =
  let seen = Hashtbl.create 16 in
  Hashtbl.replace seen target ();
  let queue = Queue.create () in
  List.iter (fun d ->
    if not (Hashtbl.mem seen d) then
      (Hashtbl.replace seen d (); Queue.add d queue)
  ) (step target);
  let acc = ref [] in
  (try while true do
     let n = Queue.take queue in
     acc := n :: !acc;
     List.iter (fun d ->
       if not (Hashtbl.mem seen d) then
         (Hashtbl.replace seen d (); Queue.add d queue)
     ) (step n)
   done with Queue.Empty -> ());
  List.rev !acc

(** Child adjacency table from a dependency map
    (`[(node, direct_dependencies)]`). Each key maps to its direct
    dependents in dependency-map order, de-duplicated. Nodes without
    dependents are absent; look them up with `Hashtbl.find_opt`. *)
let children_table p_deps =
  let tbl = Hashtbl.create 16 in
  List.iter (fun (n, deps) ->
    List.iter (fun d ->
      let cur = match Hashtbl.find_opt tbl d with
        | Some l -> l
        | None -> []
      in
      Hashtbl.replace tbl d (n :: cur)
    ) deps
  ) p_deps;
  Hashtbl.iter (fun d l ->
    Hashtbl.replace tbl d (dedup (List.rev l))
  ) tbl;
  tbl

(** Direct children of a node via a table built by [children_table]. *)
let direct_children tbl target =
  match Hashtbl.find_opt tbl target with
  | Some l -> l
  | None -> []
