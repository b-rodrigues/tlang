(* tests/pipeline/test_nix_emit.ml *)
(* Tests for Nix emission utilities: resolve_flake_path, sanitize_flake_path,
   and word-boundary-aware variable replacement. *)

let run_tests pass_count fail_count failures _eval_string _eval_string_env _test =
  Printf.printf "\nTesting Nix emission utilities:\n";

  let check name actual expected =
    if actual = expected then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      let msg = Printf.sprintf "  ✗ %s\n    Expected: %s\n    Got:      %s\n" name expected actual in
      failures := msg :: !failures;
      Printf.printf "%s" msg
    end
  in

  (* --- resolve_flake_path --- *)
  Printf.printf "  resolve_flake_path:\n";

  check "github: passthrough"
    (Nix_emit_pipeline.resolve_flake_path "github:b-rodrigues/tlang")
    "github:b-rodrigues/tlang";

  check "gitlab: passthrough"
    (Nix_emit_pipeline.resolve_flake_path "gitlab:owner/repo")
    "gitlab:owner/repo";

  check "absolute path: passthrough"
    (Nix_emit_pipeline.resolve_flake_path "path:/absolute/path")
    "path:/absolute/path";

  let cwd = Sys.getcwd () in

  check "relative path: resolved"
    (Nix_emit_pipeline.resolve_flake_path "path:../relative")
    ("path:" ^ cwd ^ "/../relative");

  check "dot-relative path: resolved"
    (Nix_emit_pipeline.resolve_flake_path "path:./local")
    ("path:" ^ cwd ^ "/./local");

  (* --- sanitize_flake_path --- *)
  Printf.printf "  sanitize_flake_path:\n";

  let sanitized = Nix_emit_pipeline.sanitize_flake_path "github:b-rodrigues/tlang" in
  let all_valid = String.to_seq sanitized |> Seq.for_all (fun c ->
    (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '_'
  ) in
  check "github: produces valid identifier"
    (string_of_bool all_valid) "true";

  check "empty string: returns custom"
    (Nix_emit_pipeline.sanitize_flake_path "") "custom";

  let sanitized2 = Nix_emit_pipeline.sanitize_flake_path "path:../test_flake" in
  check "result is lowercase"
    (String.lowercase_ascii sanitized2) sanitized2;

  (* --- Word-boundary-aware replacement ---
     Replicate the replacement logic from nix_emit_node.ml to verify
     it correctly handles word boundaries. *)
  Printf.printf "  word-boundary replacement:\n";

  let replace_var_wb prefix v input =
    let len_v = String.length v in
    let len = String.length input in
    let is_id_char c =
      (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
      || (c >= '0' && c <= '9') || c = '_' || c = '-'
    in
    let buf = Buffer.create len in
    let i = ref 0 in
    while !i < len do
      if !i + len_v <= len && String.sub input !i len_v = v then
        let preceded = !i > 0 && is_id_char input.[!i - 1] in
        let followed = !i + len_v < len && is_id_char input.[!i + len_v] in
        if preceded || followed then begin
          Buffer.add_char buf input.[!i];
          i := !i + 1
        end else begin
          Buffer.add_string buf (prefix ^ v);
          i := !i + len_v
        end
      else begin
        Buffer.add_char buf input.[!i];
        i := !i + 1
      end
    done;
    Buffer.contents buf
  in

  let prefix = "env_foo." in

  check "pkgs.bash -> prefixed"
    (replace_var_wb prefix "pkgs" "pkgs.bash")
    "env_foo.pkgs.bash";

  check "rPackages -> unchanged"
    (replace_var_wb prefix "pkgs" "rPackages")
    "rPackages";

  check "tlangPkgSet -> unchanged"
    (replace_var_wb prefix "pkgs" "tlangPkgSet")
    "tlangPkgSet";

  check "tBin -> prefixed"
    (replace_var_wb prefix "tBin" "tBin")
    "env_foo.tBin";

  check "projectTBin -> unchanged"
    (replace_var_wb prefix "tBin" "projectTBin")
    "projectTBin";

  check "${pkgs.gcc} -> prefixed inside interpolation"
    (replace_var_wb prefix "pkgs" "${pkgs.gcc}")
    "${env_foo.pkgs.gcc}";

  check "stdenv.mkDerivation -> prefixed"
    (replace_var_wb prefix "stdenv" "stdenv.mkDerivation")
    "env_foo.stdenv.mkDerivation";

  check "multiple pkgs occurrences"
    (replace_var_wb prefix "pkgs" "pkgs.bash and ${pkgs.gcc}")
    "env_foo.pkgs.bash and ${env_foo.pkgs.gcc}";

  print_newline ()
