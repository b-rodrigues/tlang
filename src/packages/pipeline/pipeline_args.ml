let get_arg name pos default named_args =
  match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
  | Some v -> (true, v)
  | None ->
      let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
      match Pipeline_utils.nth_safe (pos - 1) positionals with
      | Some v -> (true, v)
      | None -> (false, default)
