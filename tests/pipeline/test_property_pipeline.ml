(* Dogfooding: structural invariants of pipeline DAG introspection. Since
   `pipeline { ... }` blocks are source-only (there is no programmatic
   data->pipeline constructor), the DAGs are generated on the OCaml side: a
   seeded RNG picks node names (declaration order is a random permutation of a
   fixed pool so name-order != declaration-order), and node `i` depends on a
   random subset of previously declared nodes, so acyclicity is guaranteed by
   construction. The pipeline source is rendered as `n = <sum of dep names>`
   and evaluated via eval_string_env. The following invariants are checked
   against OCaml-computed expectations:
     - pipeline_nodes lists all nodes in declaration order
     - pipeline_edges reports (dep, node) pairs: nodes in declaration order,
       deps name-sorted within each node (the pipeline normalizes dependency
       order — verified empirically)
     - pipeline_roots / pipeline_leaves in declaration order
     - pipeline_depth equals the longest chain (roots are 0)
     - pipeline_cycles and pipeline_validate are empty for every DAG
     - pipeline_to_frame has one row per node with matching depth and deps
       (comma-space separated, name-sorted) columns
     - explain(p).node_count matches
     - pipeline_deps(p)[name] matches the name-sorted dependency list
   Static topologies (chain, diamond, star, two chains, deep chain, single
   node) pin down exact renderings. Regression tests cover the `get(p,
   "missing")` KeyError fix: a missing node raises (instead of silently
   returning NA) while a 3-arg default still applies, and an NA-valued node
   does not trigger the error because existence is decided by the declared
   node names, not the resolved value. *)

let quote s = Printf.sprintf "\"%s\"" s

let list_str xs =
  "[" ^ String.concat ", " (List.map quote xs) ^ "]"

let edges_str edges =
  "[" ^ String.concat ", " (List.map (fun (a, b) -> Printf.sprintf "[\"%s\", \"%s\"]" a b) edges) ^ "]"

let int_vec xs = "Vector[" ^ String.concat ", " (List.map string_of_int xs) ^ "]"

let str_vec xs = "Vector[" ^ String.concat ", " (List.map quote xs) ^ "]"

let name_pool = [| "a"; "b"; "c"; "d"; "e"; "f"; "g"; "h" |]

let shuffle_array rng a =
  let n = Array.length a in
  for i = n - 1 downto 1 do
    let j = Random.State.int rng (i + 1) in
    let t = a.(i) in
    a.(i) <- a.(j);
    a.(j) <- t
  done

let shuffle_list rng xs =
  let a = Array.of_list xs in
  shuffle_array rng a;
  Array.to_list a

type dag = {
  names : string array;
  deps_idx : int list array;
}

let gen_dag rng k =
  let pool = Array.copy name_pool in
  shuffle_array rng pool;
  let names = Array.sub pool 0 k in
  let deps_idx =
    Array.init k (fun i ->
      if i = 0 then []
      else
        let cands = List.init i (fun j -> j) in
        let chosen = List.filter (fun _ -> Random.State.float rng 1.0 < 0.5) cands in
        shuffle_list rng chosen)
  in
  { names; deps_idx }

let dep_names dag i =
  List.map (fun j -> dag.names.(j)) dag.deps_idx.(i)
  |> List.sort_uniq compare

let edges dag k =
  List.concat
    (List.init k (fun i ->
       List.map (fun d -> (d, dag.names.(i))) (dep_names dag i)))

let roots dag k =
  List.filter (fun i -> dag.deps_idx.(i) = []) (List.init k (fun x -> x))
  |> List.map (fun i -> dag.names.(i))

let leaves dag k =
  List.filter (fun i ->
    not (List.exists (fun j -> List.mem i dag.deps_idx.(j)) (List.init k (fun x -> x))))
    (List.init k (fun x -> x))
  |> List.map (fun i -> dag.names.(i))

let depths dag k =
  let d = Array.make k 0 in
  for i = 0 to k - 1 do
    d.(i) <-
      if dag.deps_idx.(i) = [] then 0
      else 1 + List.fold_left (fun acc j -> max acc d.(j)) 0 dag.deps_idx.(i)
  done;
  Array.to_list d

let render_source dag k =
  let body =
    List.init k (fun i ->
      let expr =
        if dag.deps_idx.(i) = [] then "0"
        else String.concat " + " (List.map (fun j -> dag.names.(j)) dag.deps_idx.(i))
      in
      Printf.sprintf "%s = %s" dag.names.(i) expr)
  in
  "pipeline { " ^ String.concat "; " body ^ " }"

let assert_dag env label test_env dag k =
  let names = Array.to_list dag.names in
  let ds = depths dag k in
  let max_depth = List.fold_left max 0 ds in
  let es = edges dag k in
  let rs = roots dag k in
  let ls = leaves dag k in
  let dep_lists = List.init k (fun i -> dep_names dag i) in
  let deps_col = List.map (String.concat ", ") dep_lists in
  test_env env (Printf.sprintf "%s: pipeline_nodes lists nodes in declaration order" label)
    "pipeline_nodes(p)" (list_str names);
  test_env env (Printf.sprintf "%s: pipeline_edges count" label)
    "length(pipeline_edges(p))" (string_of_int (List.length es));
  test_env env (Printf.sprintf "%s: pipeline_edges name-sorted and declaration-ordered" label)
    "pipeline_edges(p)" (edges_str es);
  test_env env (Printf.sprintf "%s: pipeline_depth equals longest chain" label)
    "pipeline_depth(p)" (string_of_int max_depth);
  test_env env (Printf.sprintf "%s: pipeline_roots in declaration order" label)
    "pipeline_roots(p)" (list_str rs);
  test_env env (Printf.sprintf "%s: pipeline_leaves in declaration order" label)
    "pipeline_leaves(p)" (list_str ls);
  test_env env (Printf.sprintf "%s: pipeline_cycles empty" label)
    "length(pipeline_cycles(p))" "0";
  test_env env (Printf.sprintf "%s: pipeline_validate passes" label)
    "length(pipeline_validate(p))" "0";
  test_env env (Printf.sprintf "%s: pipeline_to_frame one row per node" label)
    "nrow(pipeline_to_frame(p))" (string_of_int k);
  test_env env (Printf.sprintf "%s: pipeline_to_frame depth column" label)
    "pipeline_to_frame(p) |> pull($depth)" (int_vec ds);
  test_env env (Printf.sprintf "%s: pipeline_to_frame deps column" label)
    "pipeline_to_frame(p) |> pull($deps)" (str_vec deps_col);
  test_env env (Printf.sprintf "%s: explain(p).node_count matches" label)
    "explain(p).node_count" (string_of_int k);
  List.iteri (fun i dns ->
    test_env env (Printf.sprintf "%s: pipeline_deps[%s] name-sorted" label dag.names.(i))
      (Printf.sprintf "identical(get(pipeline_deps(p), \"%s\"), [%s])"
         dag.names.(i) (String.concat ", " (List.map quote dns)))
      "true")
    dep_lists

let with_p src expr = "p = " ^ src ^ "; " ^ expr

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — pipeline:\n";
  let env = Packages.init_env () in

  (* Stale build logs from previous runs (e.g. a real `dune runtest` build)
     hydrate nodes by name match, so a `get(p, "a")` assertion could resolve
     to a built artifact instead of a computed_node. Remove them first, as
     Test_pipeline does. *)
  (try
     if Sys.file_exists "_pipeline" && Sys.is_directory "_pipeline" then begin
       Sys.readdir "_pipeline"
       |> Array.iter (fun f ->
         if String.length f >= 10 && String.sub f 0 10 = "build_log_" then
           Sys.remove (Filename.concat "_pipeline" f))
     end
   with _ -> ());

  Printf.printf "  Generative DAG invariants:\n";
  List.iter (fun seed ->
    let rng = Random.State.make [| seed |] in
    for d = 1 to 10 do
      let k = 1 + Random.State.int rng 6 in
      let dag = gen_dag rng k in
      let label = Printf.sprintf "seed %d dag %d (k=%d)" seed d k in
      let (_, env) = eval_string_env ("p = " ^ render_source dag k) env in
      assert_dag env label test_env dag k
    done)
    [ 1; 7; 42 ];

  Printf.printf "  Static pipeline topologies:\n";
  let chain = "pipeline { a = 0; b = a + 1; c = b + 1; d = c + 1 }" in
  let diamond = "pipeline { a = 0; b = a + 1; c = a + 1; d = b + c }" in
  let star = "pipeline { a = 0; b = a + 1; c = a + 1; d = a + 1 }" in
  let two_chains = "pipeline { a = 0; b = a + 1; x = 0; y = x + 1 }" in
  let deep_chain = "pipeline { a = 0; b = a + 1; c = b + 1; d = c + 1; e = d + 1; f = e + 1 }" in
  let single = "pipeline { a = 0 }" in
  test_env env "chain: edges"
    (with_p chain "pipeline_edges(p)") {|[["a", "b"], ["b", "c"], ["c", "d"]]|};
  test_env env "chain: roots" (with_p chain "pipeline_roots(p)") {|["a"]|};
  test_env env "chain: leaves" (with_p chain "pipeline_leaves(p)") {|["d"]|};
  test_env env "chain: depth" (with_p chain "pipeline_depth(p)") "3";
  test_env env "chain: deps column"
    (with_p chain "pipeline_to_frame(p) |> pull($deps)") {|Vector["", "a", "b", "c"]|};
  test_env env "chain: assert returns pipeline unchanged"
    (with_p chain "pipeline_assert(p) == p") "true";
  test_env env "diamond: edges"
    (with_p diamond "pipeline_edges(p)") {|[["a", "b"], ["a", "c"], ["b", "d"], ["c", "d"]]|};
  test_env env "diamond: roots" (with_p diamond "pipeline_roots(p)") {|["a"]|};
  test_env env "diamond: leaves" (with_p diamond "pipeline_leaves(p)") {|["d"]|};
  test_env env "diamond: depth" (with_p diamond "pipeline_depth(p)") "2";
  test_env env "star: edges"
    (with_p star "pipeline_edges(p)") {|[["a", "b"], ["a", "c"], ["a", "d"]]|};
  test_env env "star: depth" (with_p star "pipeline_depth(p)") "1";
  test_env env "two chains: edges"
    (with_p two_chains "pipeline_edges(p)") {|[["a", "b"], ["x", "y"]]|};
  test_env env "two chains: roots" (with_p two_chains "pipeline_roots(p)") {|["a", "x"]|};
  test_env env "two chains: leaves" (with_p two_chains "pipeline_leaves(p)") {|["b", "y"]|};
  test_env env "two chains: depth" (with_p two_chains "pipeline_depth(p)") "1";
  test_env env "deep chain: depth" (with_p deep_chain "pipeline_depth(p)") "5";
  test_env env "deep chain: edge count" (with_p deep_chain "length(pipeline_edges(p))") "5";
  test_env env "single node: edges" (with_p single "pipeline_edges(p)") "[]";
  test_env env "single node: root is leaf" (with_p single "pipeline_roots(p)") {|["a"]|};
  test_env env "single node: leaves" (with_p single "pipeline_leaves(p)") {|["a"]|};
  test_env env "single node: depth" (with_p single "pipeline_depth(p)") "0";

  Printf.printf "  get(p, ...) missing-node regression:\n";
  test_env env "get(p, missing) raises KeyError instead of silent NA"
    {|p = pipeline { a = 0; b = a + 1 }; get(p, "missing")|}
    {|Error(KeyError: "Node `missing` not found in Pipeline.")|};
  test_env env "get(p, missing) reports KeyError code"
    {|p = pipeline { a = 0; b = a + 1 }; error_code(get(p, "missing")) == "KeyError"|}
    "true";
  test_env env "get(p, to_symbol(missing)) raises KeyError"
    {|p = pipeline { a = 0; b = a + 1 }; get(p, to_symbol("missing"))|}
    {|Error(KeyError: "Node `missing` not found in Pipeline.")|};
  test_env env "get(p, existing node) returns node value"
    {|p = pipeline { a = 0; b = a + 1 }; get(p, "b")|}
    "computed_node";
  test_env env "get(p, existing node, default) returns node value not default"
    {|p = pipeline { a = 0; b = a + 1 }; get(p, "b", "fallback")|}
    "computed_node";
  test_env env "get(p, missing, string default) returns default"
    {|p = pipeline { a = 0; b = a + 1 }; get(p, "missing", "fallback")|}
    "fallback";
  test_env env "get(p, missing, int default) returns default"
    {|p = pipeline { a = 0; b = a + 1 }; get(p, "missing", 99)|}
    "99";
  test_env env "get(p, missing, symbol default) returns default"
    {|p = pipeline { a = 0 }; get(p, to_symbol("zz"), "dflt")|}
    "dflt";
  test_env env "get(p, NA-valued node) does not raise (existence-based guard)"
    {|p = pipeline { x = NA }; get(p, "x")|}
    "computed_node";
  test_env env "get(p, 42) raises TypeError for unsupported selector"
    {|p = pipeline { a = 0 }; get(p, 42)|}
    {|Error(TypeError: "Function `get` does not support (Pipeline, Int) retrieval. Supported forms: (collection, Int), (Dict, String), (Pipeline, String), (data, Lens), (NA, default), (Error, default).")|};
  test_env env "pipeline_node(p, missing) raises KeyError"
    {|p = pipeline { a = 0 }; pipeline_node(p, "missing")|}
    {|Error(KeyError: "Node `missing` not found in Pipeline.")|};
  test_env env "pipeline_node(p, existing node) returns node value"
    {|p = pipeline { a = 0; b = a + 1 }; pipeline_node(p, "b")|}
    "computed_node";

  Printf.printf "  get(p, $symbol) dollar-prefix normalization:\n";
  test_env env "get(p, $a) retrieves node a (dict-style $ stripping)"
    {|p = pipeline { a = 0; b = a + 1 }; get(p, $a)|}
    "computed_node";
  test_env env "get(p, $b, 99) returns node b, not the default"
    {|p = pipeline { a = 0; b = a + 1 }; get(p, $b, 99)|}
    "computed_node";
  test_env env "get(p, $missing) raises KeyError with clean node name"
    {|p = pipeline { a = 0; b = a + 1 }; get(p, $missing)|}
    {|Error(KeyError: "Node `missing` not found in Pipeline.")|};
  test_env env "get(p, $missing, string default) returns default"
    {|p = pipeline { a = 0; b = a + 1 }; get(p, $missing, "dflt")|}
    "dflt";
  test_env env "get(p, $a) agrees with get(p, \"a\")"
    {|p = pipeline { a = 0; b = a + 1 }; identical(get(p, $a), get(p, "a"))|}
    "true";
  test_env env "get(p, \"$a\") string form also strips the dollar prefix"
    {|p = pipeline { a = 0; b = a + 1 }; identical(get(p, "$a"), get(p, "a"))|}
    "true";
  test_env env "get(p, \"$missing\") string form raises clean KeyError"
    {|p = pipeline { a = 0; b = a + 1 }; get(p, "$missing")|}
    {|Error(KeyError: "Node `missing` not found in Pipeline.")|};
  (* The 3-arg form has no existence guard (missing -> NA -> default is its
     documented safe-retrieval semantics). This passes only because declared
     nodes are returned wrapped in a computed_node, never a bare VNA at the
     get() level. If pipeline_get_node_value ever unwraps scalar NA nodes to a
     bare VNA, this expectation would silently flip to "dflt" with no guard in
     the 3-arg code path — the 2-arg p_exprs check does not protect it. *)
  test_env env "get(p, NA-valued node, default) returns node wrapper, not default"
    {|p = pipeline { x = NA }; get(p, "x", "dflt")|}
    "computed_node";

  Printf.printf "\n"
