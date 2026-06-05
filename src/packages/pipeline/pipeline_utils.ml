let rec nth_safe n = function
  | h :: _ when n = 0 -> Some h
  | _ :: t -> nth_safe (n - 1) t
  | [] -> None
