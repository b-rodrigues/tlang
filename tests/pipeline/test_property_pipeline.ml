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
    DAG mutation ops on the same generative DAGs:
      - upstream_of / downstream_of / subgraph keep exactly the reachable
        node sets (declaration order), upstream results validate cleanly, and
        subgraph results stay acyclic
      - swap preserves nodes/edges/deps; rewire remaps a dependency (using the
        [old: new] dict form, which works — the documented `list(...)` form is
        broken, see report); prune removes exactly the leaves and validates
      - pipeline_config_to_frame has one row per node and agrees with
        pipeline_to_frame on name and depth, with an n_deps column
    Set ops and composition on generated pipeline pairs:
      - intersect / difference / patch preserve first-pipeline declaration
        order; union merges disjoint pipelines (p then q); chain wires p2 onto
        p1's outputs; parallel merges disjoint pipelines
    Static topologies (chain, diamond, star, two chains, deep chain, single
    node) pin down exact renderings. Regression tests cover the `get(p,
    "missing")` KeyError fix: a missing node raises (instead of silently
    returning NA) while a 3-arg default still applies, and an NA-valued node
    does not trigger the error because existence is decided by the declared
    node names, not the resolved value. The same `$`-prefix normalization as
    `get` is pinned for `pipeline_node`. *)

let quote s = Printf.sprintf "\"%s\"" s

let list_str xs =
  "[" ^ String.concat ", " (List.map quote xs) ^ "]"

let edges_str edges =
  "[" ^ String.concat ", " (List.map (fun (a, b) -> Printf.sprintf "[\"%s\", \"%s\"]" a b) edges) ^ "]"

let int_vec xs = "Vector[" ^ String.concat ", " (List.map string_of_int xs) ^ "]"

let str_vec xs = "Vector[" ^ String.concat ", " (List.map quote xs) ^ "]"

let name_pool = [| "a"; "b"; "c"; "d"; "e"; "f"; "g"; "h" |]

(* Overlapping and disjoint pools for set-op / composition tests. pool_b
   overlaps pool_a in [e; f; g; h]; pool_c is fully disjoint from pool_a.
   `n` is deliberately excluded from pool_c: `n` is a reserved builtin
   (the `n` package), so a pipeline block `{ z = n + 1 }` does not infer
   `n` as a dependency reference. *)
let pool_b = [| "e"; "f"; "g"; "h"; "i"; "j"; "k"; "l" |]
let pool_c = [| "i"; "j"; "k"; "l"; "m"; "o"; "p"; "q" |]

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

let gen_dag_from rng pool k =
  let pool = Array.copy pool in
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

let gen_dag rng k = gen_dag_from rng name_pool k

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

(* ── DAG reachability (mirrors pipeline_dag_ops.ancestors / descendants) ── *)

let ancestors_idx dag i =
  let seen = Hashtbl.create 8 in
  let rec visit j =
    if not (Hashtbl.mem seen j) then begin
      Hashtbl.add seen j ();
      List.iter visit dag.deps_idx.(j)
    end
  in
  visit i;
  Hashtbl.fold (fun j () acc -> j :: acc) seen []

let descendants_idx dag k i =
  let seen = Hashtbl.create 8 in
  let all = List.init k (fun x -> x) in
  let rec visit j =
    if not (Hashtbl.mem seen j) then begin
      Hashtbl.add seen j ();
      List.iter (fun m -> if List.mem j dag.deps_idx.(m) then visit m) all
    end
  in
  visit i;
  Hashtbl.fold (fun j () acc -> j :: acc) seen []

(* Node names of the given index set, in declaration order. *)
let names_decl dag idxs =
  let ns = List.map (fun j -> dag.names.(j)) idxs in
  List.filter (fun n -> List.mem n ns) (Array.to_list dag.names)

let leaves_idx dag k =
  List.filter (fun i -> not (List.exists (fun j -> List.mem i dag.deps_idx.(j)) (List.init k (fun x -> x))))
    (List.init k (fun x -> x))

let union_nodes names_a names_b =
  names_a @ List.filter (fun n -> not (List.mem n names_a)) names_b

(* ── DAG mutation ops ──────────────────────────────────────────────── *)

let assert_dag_ops env label test_env dag k =
  List.iter (fun i ->
    let n = dag.names.(i) in
    let ups = names_decl dag (ancestors_idx dag i) in
    let downs = names_decl dag (descendants_idx dag k i) in
    let subg = names_decl dag (List.sort_uniq compare (ancestors_idx dag i @ descendants_idx dag k i)) in
    test_env env (Printf.sprintf "%s: upstream_of(%s) node set" label n)
      (Printf.sprintf {|pipeline_nodes(upstream_of(p, "%s"))|} n) (list_str ups);
    test_env env (Printf.sprintf "%s: upstream_of(%s) validates cleanly" label n)
      (Printf.sprintf {|length(pipeline_validate(upstream_of(p, "%s")))|} n) "0";
    test_env env (Printf.sprintf "%s: downstream_of(%s) node set" label n)
      (Printf.sprintf {|pipeline_nodes(downstream_of(p, "%s"))|} n) (list_str downs);
    test_env env (Printf.sprintf "%s: subgraph(%s) node set" label n)
      (Printf.sprintf {|pipeline_nodes(subgraph(p, "%s"))|} n) (list_str subg);
    test_env env (Printf.sprintf "%s: subgraph(%s) acyclic" label n)
      (Printf.sprintf {|length(pipeline_cycles(subgraph(p, "%s")))|} n) "0")
    (List.init k (fun x -> x))

let assert_swap_rewire_prune env label test_env dag k =
  let names = Array.to_list dag.names in
  List.iter (fun i ->
    let n = dag.names.(i) in
    let deps = dep_names dag i in
    let swap_expr =
      Printf.sprintf {|swap(p, "%s", node(command = <{ 99 }>, runtime = T))|} n in
    test_env env (Printf.sprintf "%s: swap(%s) keeps nodes" label n)
      (Printf.sprintf "pipeline_nodes(%s)" swap_expr) (list_str names);
    test_env env (Printf.sprintf "%s: swap(%s) keeps edges" label n)
      (Printf.sprintf {|identical(pipeline_edges(%s), pipeline_edges(p))|} swap_expr) "true";
    test_env env (Printf.sprintf "%s: swap(%s) keeps deps of %s" label n n)
      (Printf.sprintf {|identical(get(pipeline_deps(%s), "%s"), get(pipeline_deps(p), "%s"))|}
         swap_expr n n)
      "true";
    if deps <> [] then begin
      (* Rewire the first dependency to a safe target: a node that is neither
         the node itself nor a descendant (would create a cycle), and not the
         dependency being replaced. *)
      let descendants_i = descendants_idx dag k i in
      let cands =
        List.filter (fun j ->
          j <> i && not (List.mem j descendants_i)
          && not (List.exists (fun d -> dag.names.(j) = d) deps))
          (List.init k (fun x -> x))
      in
      match deps, cands with
      | old :: _, cand :: _ ->
          let target = dag.names.(cand) in
          let expected = List.map (fun d -> if d = old then target else d) deps in
          let rewire_expr =
            Printf.sprintf {|rewire(p, "%s", replace = [%s: "%s"])|} n old target in
          test_env env (Printf.sprintf "%s: rewire(%s) replaces %s with %s" label n old target)
            (Printf.sprintf {|identical(get(pipeline_deps(%s), "%s"), [%s])|}
               rewire_expr n (String.concat ", " (List.map quote expected)))
            "true";
          test_env env (Printf.sprintf "%s: rewire(%s) leaves result acyclic" label n)
            (Printf.sprintf {|length(pipeline_cycles(%s))|} rewire_expr) "0"
      | _ -> ()
    end)
    (List.init k (fun x -> x));
  (* prune removes exactly the leaves; `p` is already bound in the env *)
  let leaves = names_decl dag (leaves_idx dag k) in
  let keep = List.filter (fun n -> not (List.mem n leaves)) names in
  test_env env (Printf.sprintf "%s: prune keeps non-leaves" label)
    "pipeline_nodes(prune(p))" (list_str keep);
  test_env env (Printf.sprintf "%s: prune result validates cleanly" label)
    "length(pipeline_validate(prune(p)))" "0"

let assert_config_to_frame env label test_env dag k =
  let ds = depths dag k in
  let n_deps = List.map (fun i -> List.length (dep_names dag i)) (List.init k (fun x -> x)) in
  test_env env (Printf.sprintf "%s: config_to_frame one row per node" label)
    "nrow(pipeline_config_to_frame(p))" (string_of_int k);
  test_env env (Printf.sprintf "%s: config_to_frame name column" label)
    "pipeline_config_to_frame(p) |> pull($name)" (str_vec (Array.to_list dag.names));
  test_env env (Printf.sprintf "%s: config_to_frame depth matches pipeline_to_frame" label)
    {|identical(pipeline_config_to_frame(p) |> pull($depth), pipeline_to_frame(p) |> pull($depth))|}
    "true";
  test_env env (Printf.sprintf "%s: config_to_frame depth column" label)
    "pipeline_config_to_frame(p) |> pull($depth)" (int_vec ds);
  test_env env (Printf.sprintf "%s: config_to_frame n_deps column" label)
    "pipeline_config_to_frame(p) |> pull($n_deps)" (int_vec n_deps);
  test_env env (Printf.sprintf "%s: config_to_frame name equals pipeline_to_frame name" label)
    {|identical(pipeline_config_to_frame(p) |> pull($name), pipeline_to_frame(p) |> pull($name))|}
    "true"

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
      assert_dag env label test_env dag k;
      assert_dag_ops env label test_env dag k;
      assert_swap_rewire_prune env label test_env dag k;
      assert_config_to_frame env label test_env dag k
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

  Printf.printf "  Generative set ops (intersect/difference/patch, overlapping pools):\n";
  List.iter (fun seed ->
    let rng = Random.State.make [| seed |] in
    for d = 1 to 10 do
      let kA = 1 + Random.State.int rng 5 in
      let kB = 1 + Random.State.int rng 5 in
      let dagA = gen_dag_from rng name_pool kA in
      let dagB = gen_dag_from rng pool_b kB in
      let namesA = Array.to_list dagA.names in
      let namesB = Array.to_list dagB.names in
      let label = Printf.sprintf "seed %d set %d" seed d in
      let (_, env) =
        eval_string_env
          ("p = " ^ render_source dagA kA ^ "; q = " ^ render_source dagB kB) env in
      test_env env (Printf.sprintf "%s: intersect keeps shared names in p's order" label)
        "pipeline_nodes(intersect(p, q))"
        (list_str (List.filter (fun n -> List.mem n namesB) namesA));
      test_env env (Printf.sprintf "%s: difference keeps p-only names in p's order" label)
        "pipeline_nodes(difference(p, q))"
        (list_str (List.filter (fun n -> not (List.mem n namesB)) namesA));
      test_env env (Printf.sprintf "%s: patch overlays q onto p" label)
        "pipeline_nodes(patch(p, q))"
        (list_str (union_nodes (List.filter (fun n -> not (List.mem n namesB)) namesA)
                     (List.filter (fun n -> List.mem n namesA) namesB)))
    done)
    [ 1; 7; 42 ];

  Printf.printf "  Generative set ops (union, disjoint pools):\n";
  List.iter (fun seed ->
    let rng = Random.State.make [| seed |] in
    for d = 1 to 10 do
      let kA = 1 + Random.State.int rng 5 in
      let kB = 1 + Random.State.int rng 5 in
      let dagA = gen_dag_from rng name_pool kA in
      let dagC = gen_dag_from rng pool_c kB in
      let namesA = Array.to_list dagA.names in
      let namesC = Array.to_list dagC.names in
      let label = Printf.sprintf "seed %d union %d" seed d in
      let (_, env) =
        eval_string_env
          ("p = " ^ render_source dagA kA ^ "; q = " ^ render_source dagC kB) env in
      test_env env (Printf.sprintf "%s: union merges disjoint pipelines (p then q)" label)
        "pipeline_nodes(p |> union(q))" (list_str (namesA @ namesC));
      test_env env (Printf.sprintf "%s: union edge count is the sum" label)
        "length(pipeline_edges(p |> union(q)))"
        (string_of_int (List.length (edges dagA kA) + List.length (edges dagC kB)));
      test_env env (Printf.sprintf "%s: union result is acyclic" label)
        "length(pipeline_cycles(p |> union(q)))" "0"
    done)
    [ 1; 7; 42 ];

  Printf.printf "  Generative composition (chain / parallel):\n";
  List.iter (fun seed ->
    let rng = Random.State.make [| seed |] in
    for d = 1 to 10 do
      let kA = 1 + Random.State.int rng 5 in
      let dagA = gen_dag_from rng pool_c kA in
      let dagB = gen_dag_from rng name_pool kA in
      let namesA = Array.to_list dagA.names in
      let namesB = Array.to_list dagB.names in
      let last = dagA.names.(kA - 1) in
      let label = Printf.sprintf "seed %d chain %d" seed d in
      let (_, env) =
        eval_string_env
          ("pa = " ^ render_source dagA kA ^ "; pb = pipeline { z = " ^ last ^ " + 1 }") env in
      test_env env (Printf.sprintf "%s: chain merges p2 wired to p1" label)
        "pipeline_nodes(pa |> chain(pb))"
        (list_str (namesA @ [ "z" ]));
      test_env env (Printf.sprintf "%s: chain edge count" label)
        "length(pipeline_edges(pa |> chain(pb)))"
        (string_of_int (List.length (edges dagA kA) + 1));
      test_env env (Printf.sprintf "%s: chain result is acyclic" label)
        "length(pipeline_cycles(pa |> chain(pb)))" "0";
      let (_, env) =
        eval_string_env
          ("p = " ^ render_source dagA kA ^ "; q = " ^ render_source dagB kA) env in
      test_env env (Printf.sprintf "%s: parallel merges disjoint pipelines" label)
        "pipeline_nodes(p |> parallel(q))" (list_str (namesA @ namesB));
      test_env env (Printf.sprintf "%s: parallel edge count is the sum" label)
        "length(pipeline_edges(p |> parallel(q)))"
        (string_of_int (List.length (edges dagA kA) + List.length (edges dagB kA)))
    done)
    [ 1; 7; 42 ];

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
  test_env env "pipeline_node(p, $a) retrieves node a (parity with get)"
    {|p = pipeline { a = 0; b = a + 1 }; pipeline_node(p, $a)|}
    "computed_node";
  test_env env "pipeline_node(p, \"$a\") string form strips the dollar prefix"
    {|p = pipeline { a = 0; b = a + 1 }; pipeline_node(p, "$a")|}
    "computed_node";
  test_env env "pipeline_node(p, $a) agrees with pipeline_node(p, \"a\")"
    {|p = pipeline { a = 0; b = a + 1 }; identical(pipeline_node(p, $a), pipeline_node(p, "a"))|}
    "true";
  test_env env "pipeline_node(p, $missing) raises clean KeyError"
    {|p = pipeline { a = 0; b = a + 1 }; pipeline_node(p, $missing)|}
    {|Error(KeyError: "Node `missing` not found in Pipeline.")|};
  test_env env "pipeline_node(p, \"$missing\") string form raises clean KeyError"
    {|p = pipeline { a = 0; b = a + 1 }; pipeline_node(p, "$missing")|}
    {|Error(KeyError: "Node `missing` not found in Pipeline.")|};
  test_env env "pipeline_node(p, NA-valued node) does not raise (wrapper, not bare VNA)"
    {|p = pipeline { x = NA }; pipeline_node(p, "x")|}
    "computed_node";
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
