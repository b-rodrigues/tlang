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
