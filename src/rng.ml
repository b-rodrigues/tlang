let state : Random.State.t ref = ref (Random.State.make_self_init ())

let set_seed seed =
  state := Random.State.make [| seed |]

let sample_indices ~total ~k ~replace =
  if (not replace || total <= 0) && k > total then None
  else if k < 0 then None
  else
    let result = Array.init k (fun _ -> 0) in
    if replace then
      for i = 0 to k - 1 do
        result.(i) <- Random.State.int !state total
      done
    else begin
      let pool = Array.init total (fun i -> i) in
      for i = 0 to k - 1 do
        let j = i + Random.State.int !state (total - i) in
        let tmp = pool.(i) in pool.(i) <- pool.(j); pool.(j) <- tmp
      done;
      for i = 0 to k - 1 do
        result.(i) <- pool.(i)
      done
    end;
    Some (Array.to_list result)
