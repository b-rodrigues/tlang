(* tests/test_lineage.ml *)
(* Unit tests for Lineage: transitive closures over dependency maps,
   including diamond de-duplication and cyclic maps. *)

let run_tests pass_count fail_count _failures _eval_string _eval_string_env _test =
  Printf.printf "Lineage:\n";
  let check name condition =
    if condition then begin
      incr pass_count;
      Printf.printf "  SUCCESS %s\n" name
    end else begin
      incr fail_count;
      Printf.printf "  FAILURE %s\n" name
    end
  in
  let chain = function
    | "c" -> ["b"] | "b" -> ["a"] | _ -> []
  in
  check "closure linear chain nearest-first"
    (Lineage.closure chain "c" = ["b"; "a"]);
  check "closure root is empty"
    (Lineage.closure chain "a" = []);
  check "closure unknown node is empty"
    (Lineage.closure chain "z" = []);
  let diamond = function
    | "d" -> ["b"; "c"] | "b" -> ["a"] | "c" -> ["a"] | _ -> []
  in
  check "closure diamond dedupes shared ancestor"
    (Lineage.closure diamond "d" = ["b"; "c"; "a"]);
  check "closure self dependency excluded"
    (Lineage.closure (function "a" -> ["a"; "b"] | "b" -> [] | _ -> []) "a" = ["b"]);
  check "closure cyclic map terminates"
    (Lineage.closure (function "a" -> ["b"] | "b" -> ["a"] | _ -> []) "a" = ["b"]);
  check "closure duplicate direct deps deduped"
    (Lineage.closure (function "z" -> ["x"; "x"] | _ -> []) "z" = ["x"]);
  check "dedup keeps first-occurrence order"
    (Lineage.dedup ["b"; "a"; "b"; "c"; "a"] = ["b"; "a"; "c"]);
  let tbl = Lineage.children_table ["a", []; "b", ["a"]; "c", ["a"; "b"]] in
  check "children table preserves map order"
    (Lineage.direct_children tbl "a" = ["b"; "c"]);
  check "children table missing node is empty"
    (Lineage.direct_children tbl "c" = []);
  check "children table dedupes"
    (let tbl2 = Lineage.children_table ["d", ["a"; "a"]] in
     Lineage.direct_children tbl2 "a" = ["d"]);
  let idx = Lineage.index ["a", []; "b", ["a"]; "c", ["a"; "b"]; "d", ["b"; "c"]] in
  check "index parents follow map order deduped"
    (Lineage.parents_of idx "c" = ["a"; "b"]);
  check "index parents of root is empty"
    (Lineage.parents_of idx "a" = []);
  check "index parents of unknown is empty"
    (Lineage.parents_of idx "z" = []);
  check "index children follow map order deduped"
    (Lineage.children_of idx "a" = ["b"; "c"]);
  check "index children of leaf is empty"
    (Lineage.children_of idx "d" = []);
  check "index closure over parents reaches root"
    (Lineage.closure (Lineage.parents_of idx) "d" = ["b"; "c"; "a"]);
  check "index closure over children reaches leaf"
    (Lineage.closure (Lineage.children_of idx) "a" = ["b"; "c"; "d"]);
  print_newline ()
