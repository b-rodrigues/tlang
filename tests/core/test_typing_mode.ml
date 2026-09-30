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

  test "typed lambda allows Int for Float (widening)"
    "f = \\(x: Float -> Float) x; f(1)"
    "1";

  let report name ok =
    if ok then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      Printf.printf "  ✗ %s\n" name
    end
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

  (* Typing coverage audit (spec typesystem item 5): what fraction of
     builtins carry precise Tdoc signatures that inference actually uses?
     A builtin counts as fully precise when its return and every parameter
     map to a concrete semantic type (not Any/Unknown). The floor below
     ratchets: it must never drop (new builtins without types do not fail
     it, but removing types does). Re-measure with this same test. *)
  let coverage_floor = 372 in
  (* The registry fills from --# source comments (same as `t doc
     --parse`); without it every builtin falls back to all-Any and the
     audit would measure nothing. Skip gracefully outside a checkout. *)
  let snap = Tdoc_registry.snapshot () in
  let (full_n, total_n, ret_n, nodoc_n) =
    Fun.protect
      ~finally:(fun () -> Tdoc_registry.restore snap)
      (fun () ->
        if Sys.file_exists "src/packages" && Sys.is_directory "src/packages" then begin
          let rec walk acc dir =
            let entries = try Sys.readdir dir with Sys_error _ -> [||] in
            Array.fold_left (fun acc e ->
              let p = Filename.concat dir e in
              if (try Sys.is_directory p with Sys_error _ -> false) then walk acc p
              else if Filename.check_suffix e ".ml" then p :: acc
              else acc
            ) acc entries
          in
          List.iter (fun f ->
            List.iter Tdoc_registry.register
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
        ) names;
        (!full, List.length names, !ret, !nodoc))
  in
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
      let entries = try Sys.readdir dir with Sys_error _ -> [||] in
      Array.fold_left (fun acc e ->
        let p = Filename.concat dir e in
        if (try Sys.is_directory p with Sys_error _ -> false) then walk acc p
        else if Filename.check_suffix e ".ml" then p :: acc
        else acc
      ) acc entries
    in
    let concrete = function Semantic_type.TAny | Semantic_type.TUnknown -> false | _ -> true in
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
    ) (List.sort (fun (a, _) (b, _) -> String.compare a b) grouped)
  end);
  (* Outside a checkout the registry is empty and every builtin falls back
     to all-Any, so the floor cannot apply: pass by default there. *)
  report "typing coverage at or above floor" (not has_src || full_n >= coverage_floor);

  print_newline ()
