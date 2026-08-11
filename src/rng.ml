let state : Random.State.t ref = ref (Random.State.make_self_init ())

let set_seed seed =
  state := Random.State.make [| seed |]

let with_seed seed f =
  let saved = Random.State.copy !state in
  set_seed seed;
  match f () with
  | v ->
      state := saved;
      v
  | exception e ->
      state := saved;
      raise e

let uniform_bool () =
  Random.State.bool !state

(* Uniform int64 in [min, max], inclusive. Handles the full 2^64 span via
   two 32-bit halves with rejection when the range exceeds 2^63 - 1 (only
   reachable for pathological full-int64 ranges). *)
let uniform_int64_range ~min ~max =
  if max <= min then min
  else
    let span = Int64.sub max min in
    if span >= Int64.zero && Int64.succ span > Int64.zero then
      Int64.add min (Random.State.int64 !state (Int64.succ span))
    else
      let rec go () =
        let half () = Random.State.int64 !state 0x1_0000_0000L in
        let offset = Int64.logor (Int64.shift_left (half ()) 32) (half ()) in
        if Int64.unsigned_compare offset (Int64.succ span) < 0 then offset
        else go ()
      in
      Int64.add min (go ())

let uniform_int_range ~min ~max =
  if max <= min then min
  else
    let span = max - min in
    if span > 0 && span < (1 lsl 30) - 1 then
      min + Random.State.int !state (span + 1)
    else
      (* Wide (or overflowing) span: Random.State.int only accepts bounds
         below 2^30, so delegate to the int64 implementation, which uses
         rejection sampling. The conversion is lossless for native ints. *)
      Int64.to_int (uniform_int64_range ~min:(Int64.of_int min) ~max:(Int64.of_int max))

let uniform_float_range ~min ~max =
  if max <= min then min
  else min +. Random.State.float !state (max -. min)

let uniform_pick (items : 'a array) : 'a option =
  if Array.length items = 0 then None
  else Some items.(Random.State.int !state (Array.length items))

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
