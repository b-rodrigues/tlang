open Ast
open Eval

let run_tests pass_count fail_count failures _eval_string _eval_string_env _test =
  Printf.printf "\nTesting pipeline comment stripping:\n";
  
  let env_init = Packages.init_env () in

  (* Test 1: comment stripping *)
  let code1 = {|
    res = node(command = <{
      # this is a python comment mentioning results
      x = 1
    }>)
    results = node(command = <{
      y = res + 1
    }>)
  |} in
  
  let lexbuf1 = Lexing.from_string code1 in
  let program1 = Parser.program Lexer.token lexbuf1 in
  let (_, env1) = eval_program program1 env_init in
  
  (match Env.find_opt "res" env1 with
  | Some (VNode un) ->
      let deps = match un.un_command.node with RawCode { raw_identifiers; _ } -> raw_identifiers | _ -> [] in
      if List.mem "results" deps then (
        incr fail_count;
        let msg = Printf.sprintf "  ✗ Error: Found 'results' in dependencies despite comment stripping\n" in
        failures := msg :: !failures;
        Printf.printf "%s" msg
      ) else (
        incr pass_count;
        Printf.printf "  ✓ comment stripping: 'results' correctly ignored in comment\n"
      )
  | Some _ ->
      incr fail_count;
      let msg = Printf.sprintf "  ✗ Error: 'res' not bound as a node\n" in
      failures := msg :: !failures;
      Printf.printf "%s" msg
  | None ->
      incr fail_count;
      let msg = Printf.sprintf "  ✗ Error: 'res' not found in environment\n" in
      failures := msg :: !failures;
      Printf.printf "%s" msg);

  (* Test 2: trailing comments and string literals (issue 527 follow-up).
     A bare `foo` in a trailing `#` comment or inside a string must not lex. *)
  let check_ids name text ~present ~absent =
    let ids = Ast.extract_identifiers text in
    let ok =
      List.for_all (fun w -> List.mem w ids) present
      && List.for_all (fun w -> not (List.mem w ids)) absent
    in
    if ok then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      let msg = Printf.sprintf "  ✗ Error: %s (got [%s])\n" name (String.concat "; " ids) in
      failures := msg :: !failures;
      Printf.printf "%s" msg
    end
  in
  check_ids "trailing comment words are ignored"
    "x <- data.frame(x = 1:3)  # independent of the foo node"
    ~present:["x"; "data"; "frame"] ~absent:["foo"; "independent"; "node"];
  check_ids "string literal words are ignored"
    "s <- \"the foo node\"\ny <- 1"
    ~present:["s"; "y"] ~absent:["foo"; "the"; "node"];
  check_ids "hash inside strings does not start a comment"
    "p <- \"R/foo#bar.R\"\nz <- p"
    ~present:["p"; "z"] ~absent:["R"; "foo"; "bar"];
  check_ids "escaped quotes stay inside strings"
    "s <- \"say \\\"hi foo\\\" loudly\"\nok <- 1"
    ~present:["s"; "ok"] ~absent:["foo"; "hi"; "loudly"];
  check_ids "R double negation survives"
    "y <- --x\nz <- y"
    ~present:["y"; "x"; "z"] ~absent:[];
  check_ids "whole-line comments still ignored"
    "# independent of the foo node\nx <- 1"
    ~present:["x"] ~absent:["foo"];
  check_ids "read_node literals are kept (Quarto rewrites them)"
    "```{r}\nread_node(\"data\")\nread_node('other')\n```"
    ~present:["read_node"; "data"; "other"; "r"] ~absent:[];

  (* Test 2b: block-local bindings per runtime. check_bind asserts the exact
     sorted binding set of extract_local_bindings — every unconditional
     binding the scan spots, including ones the dependency filter later
     keeps (read-before, right-hand-side self-reads). check_shadowed below
     asserts the subtracted subset, so the two functions diverge by design
     and each has its own tests. *)
  let check_bind name runtime text expected =
    let got = Ast.extract_local_bindings ~runtime text in
    let ok = got = List.sort_uniq String.compare expected in
    if ok then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      let msg = Printf.sprintf "  ✗ Error: %s (got [%s], want [%s])\n" name
        (String.concat "; " got) (String.concat "; " expected) in
      failures := msg :: !failures;
      Printf.printf "%s" msg
    end
  in
  check_bind "R <- binds" "R" "src <- read_data()\nsrc" ["src"];
  check_bind "R = binds at depth 0" "R" "y = 2\ny" ["y"];
  check_bind "R == is not a binding" "R" "if (x == 1) y" [];
  check_bind "R kwarg keeps working" "R" "f(x = 1)" [];
  check_bind "R multiline kwarg keeps working" "R" "f(a,\n  x = 1)" [];
  check_bind "R < with space is comparison" "R" "ok <- a < -1" ["ok"];
  check_bind "R -> binds" "R" "1 -> z" ["z"];
  check_bind "R for binds" "R" "for (i in 1:3) print(i)" ["i"];
  check_bind "R function body skipped" "R"
    "g <- function(x) { tmp <- x + foo; tmp }\nfoo" ["g"];
  check_bind "R member uses are not bindings" "R" "df$col = 1" [];
  check_bind "Python = binds" "Python" "x = 1\nx" ["x"];
  check_bind "Python kwarg keeps working" "Python" "f(x = 1)" [];
  check_bind "Python == is not a binding" "Python" "if x == 1:\n  y" [];
  check_bind "Python := binds" "Python" "if (y := compute()):\n  y" ["y"];
  check_bind "Python for binds" "Python" "for i in items:\n  i" ["i"];
  check_bind "Python def binds, suite skipped" "Python"
    "def helper():\n    tmp = 1\n    tmp\nhelper" ["helper"];
  check_bind "Python nested def suite skipped" "Python"
    "def outer():\n    def inner():\n        pass\n    x = 1\nx" ["outer"];
  check_bind "Python annotated binds name" "Python" "y: int = 1\ny" ["y"];
  check_bind "Python attribute is not a binding" "Python" "obj.attr = 1" [];
  check_bind "Julia = binds" "Julia" "x = 1\nx" ["x"];
  check_bind "Julia function binds, suite skipped" "Julia"
    "function g(x)\n  tmp = x\n  tmp\nend\ng" ["g"];
  check_bind "Julia for never binds (loop scope)" "Julia"
    "for i in 1:3\n  i\nend\ni" [];
  check_bind "Julia comprehension leaks no frame" "Julia"
    "[x for x in xs if x > 0]\ny = 1\ny" ["y"];
  check_bind "Julia try/catch/finally stays balanced" "Julia"
    "try\n  x = 1\ncatch e\n  y = 2\nfinally\n  z = 3\nend\nw = 4\nw" ["w"];
  check_bind "sh stmt-start binds" "sh" "x=1\necho $x" ["x"];
  check_bind "sh prefix is not a binding" "sh" "FOO=1 cmd\necho $FOO" [];
  check_bind "sh chained assignments bind" "sh" "A=1 B=2\necho $A $B" ["A"; "B"];
  check_bind "sh command substitution binds" "sh" "x=$(date +%s)\necho $x" ["x"];
  check_bind "sh quoted value with command binds nothing" "sh" "FOO=\"a b\" cmd\necho $FOO" [];
  check_bind "sh quoted value alone binds" "sh" "x=\"a b\"\necho $x" ["x"];
  check_bind "sh array assignment binds" "sh" "A=(1 2)\necho $A" ["A"];
  check_bind "sh and-list persists" "sh" "FOO=1 && echo $FOO" ["FOO"];
  check_bind "sh background never persists" "sh" "FOO=1 &\necho $FOO" [];
  check_bind "sh pipe never persists" "sh" "FOO=1 | cat\necho $FOO" [];
  check_bind "sh redirect persists" "sh" "FOO=1 > out.txt\necho $FOO" ["FOO"];
  check_bind "sh fd redirect persists" "sh" "FOO=1 2>err.txt\necho $FOO" ["FOO"];
  check_bind "sh chained prefix binds nothing" "sh" "A=1 B=2 cmd\necho $A" [];
  check_bind "sh export binds" "sh" "export FOO=1\necho $FOO" ["FOO"];
  check_bind "sh export prefix binds nothing" "sh" "export FOO=1 cmd\necho $FOO" [];
  check_bind "sh bare export binds nothing" "sh" "export FOO\necho $FOO" [];
  check_bind "sh brace default assigns conditionally" "sh" "echo ${X:=1}\necho $X" [];
  check_bind "sh or-continuation guards" "sh" "cmd ||\nx=1\necho $x" [];
  check_bind "R or-continuation guards" "R" "cmd() ||\nx <- 1\nx" [];
  check_bind "Julia and-continuation guards" "Julia" "ok(pre) &&\nx = 1\nx" [];
  check_bind "Julia abstract type balances" "Julia"
    "module M\nabstract type T end\nx = 1\nend\nx" ["M"];
  check_bind "Julia abstract type name records" "Julia"
    "abstract type T end\nx = 1\nx" ["T"; "x"];
  check_bind "sh arg is not a binding" "sh" "echo x=1" [];
  check_bind "sh for binds" "sh" "for i in a b; do echo $i; done" ["i"];
  check_bind "sh local never binds" "sh" "f() {\n  local x=1\n  echo $x\n}" [];
  check_bind "other runtimes bind nothing" "Quarto" "x = 1\nx" [];
  check_bind "R branch body is conditional" "R" "if (c) x <- 1\nx" [];
  check_bind "Python branch suite is conditional" "Python" "if c:\n  x = 1\nx" [];

  (* Pure-shadow filter: only names with no read before their binding and
     none inside their own right-hand side subtract. *)
  let check_shadowed name runtime text expected =
    let got = Ast.extract_shadowed_locals ~runtime text in
    let ok = got = List.sort_uniq String.compare expected in
    if ok then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      let msg = Printf.sprintf "  ✗ Error: %s (got [%s], want [%s])\n" name
        (String.concat "; " got) (String.concat "; " expected) in
      failures := msg :: !failures;
      Printf.printf "%s" msg
    end
  in
  check_shadowed "R pure shadow subtracts" "R" "src <- 99; src + 1" ["src"];
  check_shadowed "R transform-in-place keeps edge" "R" "raw <- raw + 1" [];
  check_shadowed "R read-before keeps edge" "R" "print(src); src <- 99" [];
  check_shadowed "R conditional keeps edge" "R" "if (flag) src <- 99; use(src)" [];
  check_shadowed "Julia try keeps edge" "Julia" "try\n  src = 1\nend\nuse(src)" [];
  check_shadowed "Julia finally keeps edge" "Julia" "try\n  1\nfinally\n  src = 2\nend\nuse(src)" [];
  check_shadowed "R multi-line conditional keeps edge" "R" "if (flag) {\n  src <- 99\n}\nuse(src)" [];
  check_shadowed "Python transform-in-place keeps edge" "Python" "df = df.dropna()" [];
  check_shadowed "Python read-before keeps edge" "Python" "print(src)\nsrc = 99" [];
  check_shadowed "Python pure shadow subtracts" "Python" "src = 99\nsrc + 1" ["src"];
  check_shadowed "Python conditional suite keeps edge" "Python" "if flag:\n  src = 99\nuse(src)" [];
  check_shadowed "sh pure shadow subtracts" "sh" "src=99\necho $src" ["src"];
  check_shadowed "sh conditional body keeps edge" "sh" "if true; then src=99; fi\necho $src" [];
  check_shadowed "sh transform-in-place keeps edge" "sh" "x=$x" [];
  check_shadowed "Julia pure shadow subtracts" "Julia" "x = 1\nx + 1" ["x"];
  check_shadowed "Julia transform-in-place keeps edge" "Julia" "x = x + 1" [];

  (* Test 3: pipeline-level repro — bar/baz/qux must not depend on foo. *)
  let code3 = {|
    p = pipeline {
      foo = rn(command = <{ library(arrow); foo <- data.frame(a = 1:3) }>, serializer = ^ipc)
      bar = rn(command = <{ library(arrow); x <- data.frame(x = 1:3)  # independent of the foo node; x }>, serializer = ^ipc)
      baz = rn(command = <{ library(arrow); s <- "the foo node"; data.frame(x = 1:3) }>, serializer = ^ipc)
      qux = rn(command = <{ library(arrow); # independent of the foo node; data.frame(x = 1:3) }>, serializer = ^ipc)
    }
  |} in
  let lexbuf3 = Lexing.from_string code3 in
  let program3 = Parser.program Lexer.token lexbuf3 in
  let (_, env3) = eval_program program3 env_init in
  (match Env.find_opt "p" env3 with
   | Some (VPipeline p) ->
       List.iter (fun name ->
         match List.assoc_opt name p.p_deps with
         | Some [] ->
             incr pass_count;
             Printf.printf "  ✓ pipeline: `%s` has no phantom dependency on `foo`\n" name
         | Some deps ->
             incr fail_count;
             let msg = Printf.sprintf "  ✗ Error: pipeline: `%s` depends on [%s]\n" name (String.concat "; " deps) in
             failures := msg :: !failures;
             Printf.printf "%s" msg
         | None ->
             incr fail_count;
             let msg = Printf.sprintf "  ✗ Error: pipeline: node `%s` missing from deps\n" name in
             failures := msg :: !failures;
             Printf.printf "%s" msg
       ) ["bar"; "baz"; "qux"]
   | Some _ ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ Error: 'p' not bound as a pipeline\n" in
       failures := msg :: !failures;
       Printf.printf "%s" msg
   | None ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ Error: 'p' not found in environment\n" in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  (* Test 4: block-local shadowing drops the edge, real uses keep it.
     A foreign local sharing a sibling name must not wire a phantom edge
     (false-cycle risk); a sibling used as a call keyword argument must
     keep its edge (dropping it would silently under-build). *)
  let check_deps name code node expected =
    let lexbuf = Lexing.from_string code in
    let program = Parser.program Lexer.token lexbuf in
    let (_, env) = eval_program program env_init in
    (match Env.find_opt "p" env with
     | Some (VPipeline p) ->
         (match List.assoc_opt node p.p_deps with
          | Some deps ->
              let ok =
                List.sort_uniq String.compare deps
                = List.sort_uniq String.compare expected in
              if ok then begin
                incr pass_count;
                Printf.printf "  ✓ %s\n" name
              end else begin
                incr fail_count;
                let msg = Printf.sprintf "  ✗ Error: %s (%s deps [%s], want [%s])\n"
                  name node (String.concat "; " deps) (String.concat "; " expected) in
                failures := msg :: !failures;
                Printf.printf "%s" msg
              end
          | None ->
              incr fail_count;
              let msg = Printf.sprintf "  ✗ Error: %s (node `%s` missing from deps)\n" name node in
              failures := msg :: !failures;
              Printf.printf "%s" msg)
     | _ ->
         incr fail_count;
         let msg = Printf.sprintf "  ✗ Error: %s (no pipeline)\n" name in
         failures := msg :: !failures;
         Printf.printf "%s" msg)
  in
  check_deps "R shadowed sibling drops edge"
    {|p = pipeline {
      src = rn(command = <{ 1 }>)
      out = rn(command = <{ src <- 99; src + 1 }>)
    }|} "out" [];
  check_deps "R kwarg use keeps edge"
    {|p = pipeline {
      src = rn(command = <{ 1 }>)
      out = rn(command = <{ f(src) }>)
    }|} "out" ["src"];
  check_deps "Python shadowed sibling drops edge"
    {|p = pipeline {
      src = pyn(command = <{ 1 }>)
      out = pyn(command = <{ src = 99
      src + 1 }>)
    }|} "out" [];
  check_deps "Python kwarg use keeps edge"
    {|p = pipeline {
      src = pyn(command = <{ 1 }>)
      out = pyn(command = <{ f(x = src) }>)
    }|} "out" ["src"];
  check_deps "read_node literal keeps edge despite local of same name"
    {|p = pipeline {
      src = rn(command = <{ 1 }>)
      out = rn(command = <{ src <- 99; read_node("src") }>)
    }|} "out" ["src"];

  (* Test 5: transform-in-place and conditional bindings keep the edge.
     A name read before (or inside the right-hand side of) its own binding
     is a genuine dependency: dropping it would silently under-build. *)
  check_deps "R transform-in-place keeps edge"
    {|p = pipeline {
      raw = rn(command = <{ 1 }>)
      clean = rn(command = <{ raw <- raw[!is.na(raw$x), ]; raw }>)
    }|} "clean" ["raw"];
  check_deps "Python transform-in-place keeps edge"
    {|p = pipeline {
      df = pyn(command = <{ 1 }>)
      out = pyn(command = <{ df = df.dropna(); df }>)
    }|} "out" ["df"];
  check_deps "R read-then-assign keeps edge"
    {|p = pipeline {
      src = rn(command = <{ 1 }>)
      out = rn(command = <{ print(src); src <- 99; src }>)
    }|} "out" ["src"];
  check_deps "R conditional binding keeps edge"
    {|p = pipeline {
      src = rn(command = <{ 1 }>)
      out = rn(command = <{ if (flag) src <- 99; use(src) }>)
    }|} "out" ["src"];
  check_deps "Python conditional binding keeps edge"
    {|p = pipeline {
      src = pyn(command = <{ 1 }>)
      out = pyn(command = <{ if flag: src = 99
      use(src) }>)
    }|} "out" ["src"];
  check_deps "sh quoted interpolation keeps edge"
    {|p = pipeline {
      src = 1
      out = shn(command = <{ echo "$src" }>)
    }|} "out" ["src"];
  check_deps "Julia quoted interpolation keeps edge"
    {|p = pipeline {
      src = 1
      out = jln(command = <{ x = "$src" }>, deserializer = ^json)
    }|} "out" ["src"];
  check_deps "Python f-string interpolation keeps edge"
    {|p = pipeline {
      df = pyn(command = <{ 1 }>)
      out = pyn(command = <{ x = f"{df}" }>)
    }|} "out" ["df"];
  check_deps "Python plain string keeps no edge"
    {|p = pipeline {
      df = pyn(command = <{ 1 }>)
      out = pyn(command = <{ x = "{df}" }>)
    }|} "out" [];
  (* sh string commands carry no RawCode text, so dependency edges from
     sh bodies are out of scope here; sh shadowing is pinned at the
     binding level in Test 2b instead. *)

  print_newline ()
