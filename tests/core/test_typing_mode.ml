let parse_program input =
  let lexbuf = Lexing.from_string input in
  Parser.program Lexer.token lexbuf

let run_tests pass_count fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "Typing mode and typed lambda syntax:\n";

  (* Test typed lambda with explicit return type - body must be in braces *)
  test "typed lambda with return annotation parses and runs"
    "add = \\(x: Int, y: Int -> Int) (x + y); add(2, 3)"
    "5";

  (* Test untyped lambda - body can be any expression *)
  test "untyped lambda parses and runs"
    "add = \\(x, y) x + y; add(2, 3)"
    "5";

  (* Runtime type checking for annotated lambdas *)
  test "typed lambda enforces argument types at runtime"
    "f = \\(x: Int -> Int) x; f(1.1)"
    {|Error(TypeError: "Expected Int, got Float")|};

  test "typed lambda enforces return type at runtime"
    "f = \\(x: Int -> Int) 1.1; f(1)"
    {|Error(TypeError: "Function return value expected Int, got Float.")|};

  test "typed lambda allows NA even if type is annotated"
    "f = \\(x: Int -> Int) x; f(NA)"
    "NA";

  test "typed lambda propagates errors instead of masking them"
    "f = \\(x: Int -> Int) x; f(error(\"boom\"))"
    {|Error(GenericError: "boom")|};

  test "generic lambda accepts consistent types"
    "const = \\<T>(x: T, y: T -> T) x; const(1, 2)"
    "1";

  test "generic lambda accepts consistent types either order"
    "const = \\<T>(x: T, y: T -> T) x; const(\"a\", \"b\")"
    {|"a"|};

  test "generic lambda rejects inconsistent types"
    "const = \\<T>(x: T, y: T -> T) x; const(1, \"s\")"
    {|Error(TypeError: "Type variable `T` has inconsistent types: Int vs String")|};

  test "generic lambda rejects inconsistent types reversed"
    "const = \\<T>(x: T, y: T -> T) x; const(\"s\", 1)"
    {|Error(TypeError: "Type variable `T` has inconsistent types: String vs Int")|};

  test "generic lambda lets NA through"
    "const = \\<T>(x: T, y: T -> T) x; const(NA, 1)"
    "NA";

  test "generic lambda ignores leading NA when binding"
    "f3 = \\<T>(x: T, y: T, z: T -> T) x; f3(NA, 1, 2)"
    "NA";

  test "generic lambda still rejects after leading NA"
    "f3 = \\<T>(x: T, y: T, z: T -> T) x; f3(1, NA, \"s\")"
    {|Error(TypeError: "Type variable `T` has inconsistent types: Int vs String")|};

  test "generic lambda keeps Int and Float distinct"
    "const = \\<T>(x: T, y: T -> T) x; const(1, 2.5)"
    {|Error(TypeError: "Type variable `T` has inconsistent types: Int vs Float")|};

  test "single-use type variable never constrains"
    "id = \\<T>(x: T -> T) x; id(1)"
    "1";

  test "generic lambda accepts homogeneous lists"
    "const = \\<T>(x: T, y: T -> T) x; const([1], [2])"
    "[1]";

  test "generic lambda rejects heterogeneous list elements"
    "const = \\<T>(x: T, y: T -> T) x; const([1], [\"a\"])"
    {|Error(TypeError: "Type variable `T` has inconsistent types: List[Int] vs List[String]")|};

  test "generic lambda keeps Int and Float distinct inside lists"
    "const = \\<T>(x: T, y: T -> T) x; const([1], [2.5])"
    {|Error(TypeError: "Type variable `T` has inconsistent types: List[Int] vs List[Float]")|};

  test "generic lambda rejects heterogeneous dict values"
    "h = \\<T>(x: T, y: T -> T) x; h([a: 1], [a: \"s\"])"
    {|Error(TypeError: "Type variable `T` has inconsistent types: Dict[String, Int] vs Dict[String, String]")|};

  test "generic lambda lets NA through inside lists"
    "c2 = \\<T>(x: T, y: T -> T) x; c2([1, NA], [2])"
    "[1, NA]";

  test "generic lambda rejects mixed lists against plain lists"
    "const = \\<T>(x: T, y: T -> T) x; const([1, \"a\"], [2])"
    {|Error(TypeError: "Type variable `T` has inconsistent types: List[Int | String] vs List[Int]")|};

  test "nested type variable unifies inside List"
    "f2 = \\<T>(x: List[T], y: List[T] -> T) x; f2([1], [2])"
    "[1]";

  test "nested type variable rejects mismatch inside List"
    "f2 = \\<T>(x: List[T], y: List[T] -> T) x; f2([1], [\"a\"])"
    {|Error(TypeError: "Type variable `T` has inconsistent types: Int vs String")|};

  test "single nested type variable never constrains"
    "g = \\<T>(x: List[T] -> T) x; g([1, 2])"
    "[1, 2]";

  test "typed lambda allows Int for Float (widening)"
    "f = \\(x: Float -> Float) x; f(1)"
    "1";

  let report name ok =
    if ok then begin
      incr pass_count;
      Printf.printf "  SUCCESS %s\n" name
    end else begin
      incr fail_count;
      Printf.printf "  FAILURE %s\n" name
    end
  in

  (* Shared assertion for diagnostics helpers: exact count, expected
     substring when given, and warning severity throughout. *)
  let assess name diags expect_count expect_sub =
    let n = List.length diags in
    let sub_ok =
      match expect_sub with
      | None -> true
      | Some sub ->
          List.exists (fun d ->
            let msg = d.Diagnostics.diag_message in
            let sl = String.length msg and bl = String.length sub in
            if bl = 0 then true
            else begin
              let rec loop i =
                if i + bl > sl then false
                else if String.sub msg i bl = sub then true
                else loop (i + 1)
              in
              loop 0
            end) diags
    in
    let sev_ok =
      List.for_all (fun d -> d.Diagnostics.diag_severity = Diagnostics.Warning) diags
    in
    report name (n = expect_count && sub_ok && sev_ok)
  in

  let strict_ok =
    match Typecheck.validate_program ~mode:Typecheck.Strict
      (parse_program "id = \\(x: Int -> Int) x") with
    | Ok () -> true
    | Error _ -> false
  in
  report "strict mode accepts annotated top-level lambda" strict_ok;

  let strict_bad =
    match Typecheck.validate_program ~mode:Typecheck.Strict
      (parse_program "id = \\(x) x") with
    | Ok () -> false
    | Error _ -> true
  in
  report "strict mode rejects unannotated top-level lambda" strict_bad;

  (* Test generic parameter validation *)
  let generic_ok =
    match Typecheck.validate_program ~mode:Typecheck.Strict
      (parse_program "id = \\<T>(x: T -> T) x") with
    | Ok () -> true
    | Error _ -> false
  in
  report "strict mode accepts generic lambda with declared type vars" generic_ok;

  let generic_bad =
    match Typecheck.validate_program ~mode:Typecheck.Strict
      (parse_program "id = \\(x: T -> T) x") with
    | Ok () -> false
    | Error _ -> true
  in
  report "strict mode rejects generic lambda without declared type vars" generic_bad;

  (* Generic body check (warn-only): a generic return that never uses its
     params and infers to a fixed type warns; param-using and unknown
     bodies stay silent. Direct calls keep the helper honest. *)
  let check_generic name code expect_count expect_sub =
    let program =
      try parse_program code
      with _ -> []
    in
    let diags =
      try Check_utils.generic_body_diagnostics program "test.t"
      with _ -> []
    in
    assess name diags expect_count expect_sub
  in
  check_generic "generic body with fixed string warns"
    {|id = \<T>(x: T -> T) "oops"|} 1 (Some "declares return `T`");
  check_generic "generic identity stays silent"
    {|id = \<T>(x: T -> T) x|} 0 None;
  check_generic "generic body using param stays silent"
    {|f = \<T>(x: T -> T) x + 1|} 0 None;
  check_generic "non-generic lambda stays silent"
    {|f = \(x: Int -> Int) "oops"|} 0 None;
  check_generic "generic list return with fixed body warns"
    {|f = \<T>(x: T -> List[T]) [1, 2]|} 1 (Some "declares return `List[T]`");
  check_generic "generic list return using param stays silent"
    {|f = \<T>(x: T -> List[T]) [x]|} 0 None;
  check_generic "generic dict return with fixed body warns"
    {|f = \<T>(x: T -> Dict[String, T]) [a: 1]|} 1 (Some "declares return `Dict[String, T]`");
  check_generic "generic dict return using param stays silent"
    {|f = \<T>(x: T -> Dict[String, T]) [a: x]|} 0 None;
  check_generic "generic list return with call body stays silent"
    {|f = \<T>(x: T -> List[T]) foo()|} 0 None;
  check_generic "nested generic return stays silent"
    {|f = \<T>(x: T -> List[T]) x|} 0 None;

  (* Call arity check (warn-only): a non-variadic builtin takes exactly
     its registered arity; a call right of `|>`/`?|>` counts the piped
     value as one more argument. Variadic builtins, unknown names, and
     locally shadowed names stay silent. Direct calls keep the helper
     honest. *)
  let check_arity name code expect_count expect_sub =
    let program =
      try parse_program code
      with _ -> []
    in
    let builtins = Check_utils.builtin_sigs_of_env (Packages.init_env ()) in
    let diags =
      try Check_utils.call_arity_diagnostics ~builtins program "test.t"
      with _ -> []
    in
    assess name diags expect_count expect_sub
  in
  check_arity "arity exact count stays silent"
    {|identical(1, 1)|} 0 None;
  check_arity "arity too few warns"
    {|identical(1)|} 1 (Some "expects 2 argument(s) but received 1");
  check_arity "arity too many warns"
    {|identical(1, 2, 3)|} 1 (Some "expects 2 argument(s) but received 3");
  check_arity "arity none given warns"
    {|type()|} 1 (Some "expects 1 argument(s) but received 0");
  check_arity "arity inside lambda warns"
    {|f = \(x) identical(x)|} 1 (Some "expects 2 argument(s) but received 1");
  check_arity "arity pipe adds one stays silent"
    {|1 |> identical(1)|} 0 None;
  check_arity "arity pipe too many warns"
    {|1 |> identical(1, 2)|} 1 (Some "expects 2 argument(s) but received 3");
  check_arity "arity bare pipe counts one"
    {|1 |> identical|} 1 (Some "expects 2 argument(s) but received 1");
  check_arity "arity shadowed name stays silent"
    {|identical = \(x) x; identical(1)|} 0 None;
  check_arity "arity package alias shadows builtin"
    {|import core [identical = sum]; identical(1)|} 0 None;
  check_arity "arity selective import without alias still checks"
    {|import core [identical]; identical(1)|} 1 (Some "expects 2 argument(s) but received 1");
  (* A file import binding a builtin name shadows it just as well. *)
  let shadow_path = Filename.temp_file "t_shadow_import" ".t" in
  (let oc = open_out shadow_path in
   output_string oc "identical = 1\n";
   close_out oc);
  check_arity "arity file import shadows builtin"
    (Printf.sprintf {|import "%s" [identical]; identical(1)|} shadow_path) 0 None;
  (try Sys.remove shadow_path with _ -> ());
  check_arity "arity variadic stays silent"
    {|sum(1, 2, 3)|} 0 None;
  check_arity "arity unknown function stays silent"
    {|nosuchfn(1, 2, 3)|} 0 None;

  (* Call argument-type check (warn-only): inferred argument types are
     compared against documented parameter types; definite mismatches
     warn. Anything doubtful stays silent. Direct calls keep the
     helper honest. *)
  let sig_builtins =
    let sig_of arity variadic params =
      { Check_utils.bs_arity = arity; Check_utils.bs_variadic = variadic;
        Check_utils.bs_params = params }
    in
    [ ("takes_int", sig_of 1 false ["x", Some "Int"]);
      ("takes_float", sig_of 1 false ["x", Some "Float"]);
      ("takes_df", sig_of 1 false ["data", Some "DataFrame"]);
      ("takes_fn", sig_of 1 false ["fn", Some "Function"]);
      ("takes_col", sig_of 1 false ["col", Some "Column"]);
      ("takes_any", sig_of 1 false ["x", Some "Any"]);
      ("takes_named", sig_of 2 false ["a", Some "Int"; "opt", Some "String"]);
      ("takes_pred", sig_of 2 false ["data", Some "DataFrame"; "predicate", Some "Function"]);
      ("takes_nums", sig_of 1 false ["x", Some "List[Float] | Vector[Float]"]) ]
  in
  let check_sig name code expect_count expect_sub =
    let program =
      try parse_program code
      with _ -> []
    in
    let scope = Symbol_table.create_scope () in
    Symbol_table.register_keywords scope;
    (try ignore (Analyzer.analyze program scope) with _ -> ());
    let diags =
      try Check_utils.call_type_diagnostics ~sigs:sig_builtins
        ~infer:(Analyzer.infer_type scope) program "test.t"
      with _ -> []
    in
    assess name diags expect_count expect_sub
  in
  check_sig "sig exact type stays silent"
    {|takes_int(1)|} 0 None;
  check_sig "sig wrong type warns"
    {|takes_int("s")|} 1 (Some "expects argument `x` to be Int, but it infers to String");
  check_sig "sig int for float stays silent"
    {|takes_float(1)|} 0 None;
  check_sig "sig float for int warns"
    {|takes_int(1.5)|} 1 (Some "to be Int, but it infers to Float");
  check_sig "sig unknown variable stays silent"
    {|takes_int(y)|} 0 None;
  check_sig "sig NA stays silent"
    {|takes_int(NA)|} 0 None;
  check_sig "sig dataframe mismatch warns"
    {|takes_df(1)|} 1 (Some "to be DataFrame, but it infers to Int");
  check_sig "sig function accepts lambda"
    {|takes_fn(\(x) x)|} 0 None;
  check_sig "sig function rejects scalar"
    {|takes_fn(1)|} 1 (Some "to be Function, but it infers to Int");
  check_sig "sig shape word stays silent"
    {|takes_col(1)|} 0 None;
  check_sig "sig any stays silent"
    {|takes_any("s")|} 0 None;
  check_sig "sig named args map by name"
    {|takes_named(1, opt = "a")|} 0 None;
  check_sig "sig named arg mismatch warns"
    {|takes_named(1, opt = 1)|} 1 (Some "expects argument `opt` to be String");
  check_sig "sig arity mismatch skips types"
    {|takes_int()|} 0 None;
  check_sig "sig pipe value checks first position"
    {|"s" |> takes_int|} 1 (Some "to be Int, but it infers to String");
  check_sig "sig pipe value silent when right"
    {|1 |> takes_int|} 0 None;
  check_sig "sig shadowed stays silent"
    {|takes_int = \(x) x; takes_int("s")|} 0 None;
  check_sig "sig unknown function stays silent"
    {|nosuchfn("s")|} 0 None;
  check_sig "sig NSE predicate stays silent"
    {|takes_pred(df, $mpg > 20)|} 0 None;
  check_sig "sig NSE skipped while other arg warns"
    {|takes_pred(1, $mpg > 20)|} 1 (Some "expects argument `data`");
  check_sig "sig named claimed before positional stays silent"
    {|takes_named(a = 1, "x")|} 0 None;
  check_sig "sig positional fills unclaimed parameter"
    {|takes_named(opt = "x", 1)|} 0 None;
  check_sig "sig positional warns against unclaimed parameter"
    {|takes_named(opt = "s", "x")|} 1 (Some "expects argument `a` to be Int, but it infers to String");
  check_sig "sig expected quotes signature verbatim"
    {|takes_nums("s")|} 1 (Some "to be List[Float] | Vector[Float]");

  (* Return-type checks: documented builtin returns flow into inference,
     so annotations and argument checks see through calls. Setup mirrors
     production `t check` (repl.ml): exported --# docs registered from
     src, derived-type cache cleared, scope populated from the live env.
     One setup for the whole block; the registry is restored after. *)
  let with_prod_docs f =
    let snap = Tdoc_registry.snapshot () in
    Fun.protect ~finally:(fun () -> Tdoc_registry.restore snap)
      (fun () ->
        (* Source root is cwd-dependent: `dune exec` from the repo root
           sees `src/`, but `dune runtest` runs with cwd `tests/` (see
           the `../src/repl.exe` probe in test_cli). Try both so the
           setup is hermetic either way instead of silently testing
           nothing. *)
        let roots =
          List.filter (fun d ->
            try Sys.is_directory (Filename.concat d "packages")
            with Sys_error _ -> false
          ) ["src"; "../src"]
        in
        (match roots with
         | [] ->
             (* Failing loudly beats passing vacuously: without the src
                tree every warning-expecting case below degrades to
                silent and the suite would lie green. *)
             report "prod docs setup found src tree" false
         | root :: _ ->
             let rec walk acc dir =
               let entries =
                 try Array.to_list (Sys.readdir dir) |> List.sort String.compare
                 with Sys_error _ -> []
               in
               List.fold_left (fun acc e ->
                 let p = Filename.concat dir e in
                 if (try Sys.is_directory p with Sys_error _ -> false) then walk acc p
                 else if Filename.check_suffix e ".ml" then p :: acc
                 else acc
               ) acc entries
             in
             List.iter (fun file ->
               List.iter (fun (e : Tdoc_types.doc_entry) ->
                 if e.Tdoc_types.is_export then Tdoc_registry.register e
               )
                 (try Tdoc_parser.parse_file file with _ -> [])
             ) (walk [] root));
        Symbol_table.clear_builtin_typ_cache ();
        f ())
  in
  let prod_scope program =
    let scope = Symbol_table.create_scope () in
    Symbol_table.register_keywords scope;
    Symbol_table.populate_from_env scope (Packages.init_env ());
    let analysis = Analyzer.analyze program scope in
    (scope, analysis.Analyzer.stmt_types)
  in
  (* Same construction as production (repl.ml): runtime arity plus the
     documented parameter list per builtin. *)
  let prod_sigs () =
    Check_utils.builtin_sigs_of_env (Packages.init_env ())
  in
  let check_ret name code which expect_count expect_sub =
    let program =
      try parse_program code
      with _ -> []
    in
    let (scope, stmt_types) = prod_scope program in
    let diags =
      try match which with
        | `Annot ->
            Check_utils.annotation_diagnostics program stmt_types "test.t"
        | `Types ->
            Check_utils.call_type_diagnostics ~sigs:(prod_sigs ())
              ~infer:(Analyzer.infer_type scope) program "test.t"
      with _ -> []
    in
    assess name diags expect_count expect_sub
  in
  with_prod_docs (fun () ->
    check_ret "return mismatch warns on annotation"
      {|s: String = nrow(df)|} `Annot 1 (Some "annotated as String, but expression infers to Int");
    (* `ifelse` accepts scalar conditions and returns scalars for them
       (verified at runtime), so neither the argument nor the
       annotation check may warn here. *)
    check_ret "ifelse scalar condition stays silent"
      {|ifelse(true, 1, 2)|} `Types 0 None;
    check_ret "ifelse scalar result matches Int annotation"
      {|r: Int = ifelse(true, 1, 2)|} `Annot 0 None;    check_ret "return match stays silent on annotation"
      {|nn: Int = nrow(df)|} `Annot 0 None;
    check_ret "import keeps builtin return precision"
      {|import core
s2: String = nrow(df)|} `Annot 1 (Some "annotated as String, but expression infers to Int");
    check_ret "undocumented call stays silent on annotation"
      {|s3: String = nosuchfn(1)|} `Annot 0 None;
    check_ret "argument check sees through calls"
      {|str_squish(nrow(df))|} `Types 1 (Some "expects argument `s` to be String, but it infers to Int");
    check_ret "chained calls stay silent when types agree"
      {|str_squish(str_squish("  a  "))|} `Types 0 None;
    check_ret "arity failure skips argument types on real builtins"
      {|str_squish(nrow(df), "extra")|} `Types 0 None;
    check_ret "pipe return warns on annotation"
      {|s: String = df |> nrow|} `Annot 1 (Some "annotated as String, but expression infers to Int");
    check_ret "pipe return match stays silent"
      {|nn: Int = df |> nrow|} `Annot 0 None;
    check_ret "maybe-pipe return warns on annotation"
      {|s: String = df ?|> nrow|} `Annot 1 (Some "annotated as String, but expression infers to Int");
    check_ret "pipe chain sees through calls"
      {|str_squish(df |> nrow)|} `Types 1 (Some "expects argument `s` to be String, but it infers to Int");
    check_ret "bare pipe target stays silent"
      {|s3: String = df |> nosuchfn|} `Annot 0 None;
    check_ret "annotated lambda return warns on annotation"
      {|f = \(x: Int -> Int) x
s: String = f(1)|} `Annot 1 (Some "annotated as String, but expression infers to Int");
    check_ret "annotated param flows into body"
      {|f = \(x: Int) x + 1
s: String = f(1)|} `Annot 1 (Some "annotated as String, but expression infers to Int");
    check_ret "annotated return wins over body"
      {|f = \(x: Int -> String) x
n: Int = f(1)|} `Annot 1 (Some "annotated as Int, but expression infers to String");
    check_ret "unannotated lambda stays silent"
      {|f = \(x) x
s: String = f(1)|} `Annot 0 None;
    check_ret "generic lambda stays silent"
      {|f = \(T)(x: T -> T) x
s: String = f(1)|} `Annot 0 None;
    check_ret "user call sees through annotated return"
      {|f = \(x: Int -> Int) x
str_squish(f(1))|} `Types 1 (Some "expects argument `s` to be String, but it infers to Int");
    check_ret "user call match stays silent"
      {|f = \(x: Int -> String) "hi"
str_squish(f(1))|} `Types 0 None;
    (* Import scoping guard: the analyzer scopes imports from the
       static per-package lists, while `package_info` merges documented
       names. Every documented-only name must need no scope entry
       (live builtin covered by the populated scope, eval special form,
       concept doc, or internal helper) — otherwise `import pkg` would
       scope differently from what the docs promise. The documented set
       is recomputed here from this block's src-derived registry (never
       `package_functions`, which would fire the one-shot documentation
       loader), so this stays hermetic under any suite order. New
       internal --# blocks must either stay @private or join the
       allowlist below. *)
    (let no_scope_needed = [
       (* Eval special forms (see eval.ml): callable, never in the env. *)
       "node"; "pyn"; "rn"; "jln"; "qn"; "shn";
       (* Concept doc, not a callable. *)
       "lens";
       (* Internal OCaml helpers with --# blocks, never callable from T. *)
       "parse_file"; "run_doctor"; "scaffold_package"; "scaffold_project";
       "update_flake_lock"; "build_pipeline_internal";
     ] in
     let env = Packages.init_env () in
     let unaccounted =
       List.filter_map (fun pkg ->
         let static = pkg.Packages.functions in
         let fams = Packages.package_families pkg.Packages.name in
         let documented =
           List.filter_map (fun (e : Tdoc_types.doc_entry) ->
             match e.Tdoc_types.family with
             | Some f when List.mem f fams && e.Tdoc_types.is_export ->
                 Some e.Tdoc_types.name
             | _ -> None
           ) (Tdoc_registry.get_all ())
         in
         let only_doc = List.filter (fun f -> not (List.mem f static)) documented in
         let accounted f = Ast.Env.mem f env || List.mem f no_scope_needed in
         (match List.filter (fun f -> not (accounted f)) only_doc with
          | [] -> None
          | bad -> Some (pkg.Packages.name ^ ": " ^ String.concat "," bad))
       ) Packages.all_packages
     in
     match unaccounted with
     | [] -> report "documented-only names need no import scope" true
     | ms ->
         List.iter (fun m -> Printf.printf "    unaccounted: %s\n" m) ms;
         report "documented-only names need no import scope" false)
  );
  check_arity "arity real builtin too many warns"
    {|str_squish("a", "b")|} 1 (Some "expects 1 argument(s) but received 2");

  (* Typing coverage audit (spec typesystem item 5): what fraction of
     builtins carry precise Tdoc signatures that inference actually uses?
     A builtin counts as fully precise when its return and every parameter
     map to a concrete semantic type (not Any/Unknown). The floor below
     ratchets: it must never drop (new builtins without types do not fail
     it, but removing types does). Re-measure with this same test.
     Floor is 382: whole spaced unions now parse as written, so the two
     honest catch-all tails (`to_factor.x`, `ordered.x`, both `Vector |
     List | Any` against implementations that stringify anything) count
     as imprecise instead of riding on a truncated first member. *)
  let coverage_floor = 444 in
  (* The registry fills from --# source comments (same as `t doc
     --parse`); without it every builtin falls back to all-Any and the
     audit would measure nothing. Skip gracefully outside a checkout. *)
  let snap = Tdoc_registry.snapshot () in
  let (full_n, total_n, ret_n, nodoc_n, imprecise_list) =
    Fun.protect
      ~finally:(fun () -> Tdoc_registry.restore snap)
      (fun () ->
        if Sys.file_exists "src/packages" && Sys.is_directory "src/packages" then begin
          let rec walk acc dir =
            (* Sorted for determinism: see the breakdown walk below. *)
            let entries =
              try Array.to_list (Sys.readdir dir) |> List.sort String.compare
              with Sys_error _ -> []
            in
            List.fold_left (fun acc e ->
              let p = Filename.concat dir e in
              if (try Sys.is_directory p with Sys_error _ -> false) then walk acc p
              else if Filename.check_suffix e ".ml" then p :: acc
              else acc
            ) acc entries
          in
          List.iter (fun f ->
            (* Exported entries only: internal (@private) docs use
               OCaml-side vocabulary and must not shadow builtins in the
               registry (last-write-wins would make counts order-
               dependent). *)
            List.iter (fun (e : Tdoc_types.doc_entry) ->
              if e.Tdoc_types.is_export then Tdoc_registry.register e
            )
              (try Tdoc_parser.parse_file f with _ -> [])
          ) (walk [] "src")
        end else
          Printf.printf "  (no src tree found; coverage audit measures the live registry only)\n";
        let names = ref [] in
        Ast.Env.iter (fun name v ->
          match v with
          | Ast.VBuiltin { b_name = Some n; _ } when n = name -> names := n :: !names
          | _ -> ()) (Packages.init_env ());
        let names = List.sort_uniq String.compare !names in
        let concrete = function Semantic_type.TAny | Semantic_type.TUnknown -> false | _ -> true in
        let typed_info = function
          | Some s -> concrete (Semantic_type.from_string s)
          | None -> false in
        let full = ref 0 and ret = ref 0 and nodoc = ref 0 in
        let imprecise = ref [] in
        List.iter (fun n ->
          match Tdoc_registry.lookup n with
          | None -> incr nodoc
          | Some e ->
              let ps = List.map (fun (p : Tdoc_types.param_doc) -> typed_info p.Tdoc_types.type_info) e.Tdoc_types.params in
              let r = match e.Tdoc_types.return_value with
                | Some r -> typed_info r.Tdoc_types.type_info
                | None -> false in
              if r then incr ret;
              if r && List.for_all (fun x -> x) ps then incr full
              else begin
                let bad_params = List.filter_map (fun (p : Tdoc_types.param_doc) ->
                  match p.Tdoc_types.type_info with
                  | Some s when not (concrete (Semantic_type.from_string s)) -> Some (p.Tdoc_types.name ^ " :: " ^ s)
                  | None -> Some (p.Tdoc_types.name ^ " :: (missing)")
                  | _ -> None
                ) e.Tdoc_types.params in
                let ret_s = match e.Tdoc_types.return_value with
                  | Some rv -> (match rv.Tdoc_types.type_info with Some s -> s | None -> "(missing)")
                  | None -> "(missing)" in
                imprecise := (n, ret_s, bad_params) :: !imprecise
              end
        ) names;
        (!full, List.length names, !ret, !nodoc, List.sort compare !imprecise))
  in
  (if try Sys.getenv "TLANG_TYPING_VERBOSE" = "1" with Not_found -> false then begin
    Printf.printf "  imprecise builtins (%d):\n" (List.length imprecise_list);
    List.iter (fun (n, ret_s, bad) ->
      Printf.printf "    - %s return :: %s%s\n" n ret_s
        (match bad with
         | [] -> ""
         | ps -> " | params: " ^ String.concat ", " ps)
    ) imprecise_list
  end);
  let has_src = Sys.file_exists "src/packages" in
  Printf.printf "  typing coverage: %d/%d fully precise, %d precise returns, %d without docs\n"
    full_n total_n ret_n nodoc_n;
  (* Per-package doc-side breakdown (no behavior change): parses --# blocks
     per file and groups by source directory, so the imprecise remainder has
     a visible work queue. Doc-side counts differ from the registry floor
     above (which counts live builtins); use this only to pick the next
     package batch. *)
  (if has_src then begin
    let pkg_of_path f =
      let prefix_pkg = "src/packages/" in
      let lp = String.length prefix_pkg in
      if String.length f > lp && String.sub f 0 lp = prefix_pkg then begin
        let rest = String.sub f lp (String.length f - lp) in
        (match String.index_opt rest '/' with
         | Some i -> String.sub rest 0 i
         | None -> rest)
      end else begin
        let prefix_src = "src/" in
        let ls = String.length prefix_src in
        if String.length f > ls && String.sub f 0 ls = prefix_src then begin
          let rest = String.sub f ls (String.length f - ls) in
          (match String.index_opt rest '/' with
           | Some i -> String.sub rest 0 i
           | None -> "core")
        end else "other"
      end
    in
    let rec walk acc dir =
      (* Sorted for determinism: duplicate doc names resolve identically
         on every machine (later paths win in registration order). *)
      let entries =
        try Array.to_list (Sys.readdir dir) |> List.sort String.compare
        with Sys_error _ -> []
      in
      List.fold_left (fun acc e ->
        let p = Filename.concat dir e in
        if (try Sys.is_directory p with Sys_error _ -> false) then walk acc p
        else if Filename.check_suffix e ".ml" then p :: acc
        else acc
      ) acc entries
    in
    let concrete = function Semantic_type.TAny | Semantic_type.TUnknown -> false | _ -> true in
    (* Signatures that parse to TUnknown anywhere silently disable checking
       for that position (often a typo like `Flot`). Members matching the
       deliberate pseudo-vocabulary below stay quiet: they carry meaning
       for humans but have no runtime contract (`Column`, `Selection`,
       `Call`, `KeywordArgs`), or are bottom values (`Function`, `Error`,
       `Null`, `NA`, `VError`). Only live builtins are listed: internal
       OCaml docs (scaffold, arrow_io, serialization) use OCaml-side
       vocabulary that is out of scope here — except when they collide
       with a builtin name (`read_csv`/`write_csv` vs arrow_io), which
       stays listed as a known registry-collision follow-up. Everything
       listed is informational, never failed. *)
    let deliberate_member w =
      match w with
      | "function" | "error" | "null" | "na" | "verror" | "column"
      | "selection" | "call" | "keywordargs" | "node" -> true
      | _ -> false
    in
    let rec has_unknown = function
      | Semantic_type.TUnknown -> true
      | Semantic_type.TList t | Semantic_type.TVector t -> has_unknown t
      | Semantic_type.TDict (k, v) -> has_unknown k || has_unknown v
      | Semantic_type.TUnion ts -> List.exists has_unknown ts
      | Semantic_type.TFunction (args, ret) ->
          List.exists (fun (_, t) -> has_unknown t) args || has_unknown ret
      | _ -> false
    in
    let unknowns = ref [] in
    (* Live builtin names: the unknown-signature warning applies to T
       builtin signatures only, not internal OCaml docs. *)
    let builtin_names =
      let acc = ref [] in
      Ast.Env.iter (fun name v ->
        match v with
        | Ast.VBuiltin { b_name = Some n; _ } when n = name -> acc := n :: !acc
        | _ -> ()) (Packages.init_env ());
      !acc
    in
    let entry_full (e : Tdoc_types.doc_entry) =
      let r = match e.Tdoc_types.return_value with
        | Some r -> (match r.Tdoc_types.type_info with Some s -> concrete (Semantic_type.from_string s) | None -> false)
        | None -> false in
      let ps = List.map (fun (p : Tdoc_types.param_doc) ->
        match p.Tdoc_types.type_info with Some s -> concrete (Semantic_type.from_string s) | None -> false
      ) e.Tdoc_types.params in
      r && List.for_all (fun x -> x) ps
    in
    let grouped =
      List.fold_left (fun acc f ->
        let entries = try Tdoc_parser.parse_file f with _ -> [] in
        List.fold_left (fun acc e ->
          let label = pkg_of_path f in
          let full = entry_full e in
          let note_unknown kind = function
            | Some s when e.Tdoc_types.is_export && List.mem e.Tdoc_types.name builtin_names ->
                let members =
                  List.map (fun m -> String.lowercase_ascii (String.trim m))
                    (Semantic_type.split_toplevel_pipe s)
                in
                (* A member that fails to parse disables checking for that
                   position, so it is listed. A union that collapses
                   entirely (`X | Any` absorbs to `Any`) is listed too —
                   otherwise honest catch-all tails would go silent the
                   same way. A documented bare `Any` stays quiet. *)
                let parsed = Semantic_type.from_string s in
                let absorbed =
                  Semantic_type.has_toplevel_pipe s
                  && (match parsed with
                      | Semantic_type.TAny | Semantic_type.TUnknown -> true
                      | _ -> false)
                in
                if absorbed
                   || List.exists (fun m ->
                        not (deliberate_member m)
                        && has_unknown (Semantic_type.from_string m)
                      ) members then
                  unknowns := (e.Tdoc_types.name ^ "." ^ kind ^ " :: " ^ s) :: !unknowns
            | _ -> ()
          in
          (match e.Tdoc_types.return_value with
           | Some r -> note_unknown "return" r.Tdoc_types.type_info
           | None -> ());
          List.iter (fun (p : Tdoc_types.param_doc) ->
            if p.Tdoc_types.name <> "..." then
              note_unknown p.Tdoc_types.name p.Tdoc_types.type_info
          ) e.Tdoc_types.params;
          (match List.assoc_opt label acc with
           | Some (fl, tot) ->
               let acc = List.remove_assoc label acc in
               (label, ((if full then fl + 1 else fl), tot + 1)) :: acc
           | None -> (label, ((if full then 1 else 0), 1)) :: acc)
        ) acc entries
      ) [] (walk [] "src")
    in
    List.iter (fun (label, (fl, tot)) ->
      Printf.printf "    typing coverage [%s]: %d/%d fully precise\n" label fl tot
    ) (List.sort (fun (a, _) (b, _) -> String.compare a b) grouped);
    (match List.sort_uniq String.compare !unknowns with
     | [] -> ()
     | unk ->
         let shown, extra =
           let rec take n acc = function
             | [] -> (List.rev acc, 0)
             | x :: xs -> if n <= 0 then (List.rev acc, 1 + List.length xs) else take (n - 1) (x :: acc) xs
           in
           take 15 [] unk
         in
         List.iter (fun u -> Printf.printf "    typing unknown signature: %s\n" u) shown;
         if extra > 0 then Printf.printf "    ... and %d more unknown signatures\n" extra)
  end);
  (* Outside a checkout the registry is empty and every builtin falls back
     to all-Any, so the floor cannot apply: pass by default there. *)
  report "typing coverage at or above floor" (not has_src || full_n >= coverage_floor);

  print_newline ()
