let starts_with_function args =
  match args with
  | [VString prefix] -> StartsWith prefix
  | _ -> VError "starts_with expects a string argument"
