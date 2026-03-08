let env_flag name =
  match Sys.getenv_opt name with
  | Some ("1" | "true" | "yes" | "on") -> true
  | _ -> false

let require_native_arrow = env_flag "TLANG_REQUIRE_ARROW_NATIVE"

let record_native_requirement_result pass_count fail_count message =
  if require_native_arrow then begin
    incr fail_count;
    Printf.printf "  ✗ %s\n" message
  end else begin
    incr pass_count;
    Printf.printf "  ✓ %s\n" message
  end
