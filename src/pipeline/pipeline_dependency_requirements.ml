open Ast
open Package_types

module String_set = Set.Make (String)

type requirements = {
  r_deps : String_set.t;
  py_deps : String_set.t;
  julia_deps : String_set.t;
  additional_tools : String_set.t;
  latex_pkgs : String_set.t;
  reasons : String_set.t;
}

type analysis = {
  missing_r_deps : string list;
  missing_py_deps : string list;
  missing_julia_deps : string list;
  missing_additional_tools : string list;
  missing_latex_pkgs : string list;
  reasons : string list;
}

let empty_requirements = {
  r_deps = String_set.empty;
  py_deps = String_set.empty;
  julia_deps = String_set.empty;
  additional_tools = String_set.empty;
  latex_pkgs = String_set.empty;
  reasons = String_set.empty;
}

let add_list set items =
  List.fold_left (fun acc item -> String_set.add item acc) set items

let with_reason (req: requirements) reason =
  { req with reasons = String_set.add reason req.reasons }

let merge_requirements a b = {
  r_deps = String_set.union a.r_deps b.r_deps;
  py_deps = String_set.union a.py_deps b.py_deps;
  julia_deps = String_set.union a.julia_deps b.julia_deps;
  additional_tools = String_set.union a.additional_tools b.additional_tools;
  latex_pkgs = String_set.union a.latex_pkgs b.latex_pkgs;
  reasons = String_set.union a.reasons b.reasons;
}

let normalize_format s =
  let s =
    if String.length s > 0 && s.[0] = '^' then
      String.sub s 1 (String.length s - 1)
    else
      s
  in
  String.lowercase_ascii s

let canonical_feature_name feature =
  match normalize_format feature with
  | "write_parquet" | "read_parquet" | "write_feather" | "read_feather" -> "arrow"
  | other -> other

let rec formats_of_value = function
  | VSerializer s -> [ canonical_feature_name s.s_format ]
  | VString s | VSymbol s -> [ canonical_feature_name s ]
  | VDict pairs ->
      (match List.assoc_opt "format" pairs with
       | Some value -> formats_of_value value
       | None ->
           List.fold_left
             (fun acc (_, value) -> formats_of_value value @ acc)
             [] pairs)
  | VList items ->
      List.fold_left
        (fun acc (_, value) -> formats_of_value value @ acc)
        [] items
  | _ -> []

let rec formats_of_expr expr =
  match expr.node with
  | Value value -> formats_of_value value
  | Var name -> [ canonical_feature_name name ]
  | DictLit pairs ->
      List.fold_left
        (fun acc (_, value) -> formats_of_expr value @ acc)
        [] pairs
  | ListLit items ->
      List.fold_left
        (fun acc (_, value) -> formats_of_expr value @ acc)
        [] items
  | DotAccess _ | RawCode _ -> []
  | _ -> []

let add_feature_requirement ~node_name ~runtime ~feature =
  let feature = canonical_feature_name feature in
  let reason =
    Printf.sprintf "node `%s` uses `%s` with runtime `%s`" node_name feature runtime
  in
  let req = with_reason empty_requirements reason in
  match runtime, feature with
  | "R", "json" ->
      { req with r_deps = add_list req.r_deps [ "jsonlite" ] }
  | "Python", "json" ->
      empty_requirements
  | "R", "csv" ->
      empty_requirements (* base R write.csv/read.csv; no extra packages needed *)
  | "Python", "csv" ->
      { req with py_deps = add_list req.py_deps [ "pandas" ] }
  | "R", "ipc" ->
      { req with r_deps = add_list req.r_deps [ "arrow" ] }
  | "Python", "ipc" ->
      { req with py_deps = add_list req.py_deps [ "pandas"; "pyarrow" ] }
  | "R", "parquet" ->
      { req with r_deps = add_list req.r_deps [ "arrow" ] }
  | "Python", "parquet" ->
      { req with py_deps = add_list req.py_deps [ "pandas"; "pyarrow" ] }
  | "R", "pmml" ->
      {
        req with
        r_deps = add_list req.r_deps [ "XML"; "jsonlite"; "r2pmml" ];
        additional_tools = add_list req.additional_tools [ "jre" ];
      }
  | "Python", "pmml" ->
      {
        req with
        py_deps =
          add_list req.py_deps
            [ "numpy"; "pandas"; "pyarrow"; "scikit-learn"; "scipy"; "sklearn2pmml"; "statsmodels" ];
        additional_tools = add_list req.additional_tools [ "jre"; "jpmml-evaluator" ];
      }
  | "R", "onnx" ->
      { req with r_deps = add_list req.r_deps [ "onnx" ] }
  | "Python", "onnx" ->
      { req with py_deps = add_list req.py_deps [ "onnxruntime"; "skl2onnx" ] }
  | "Julia", "onnx" ->
      { req with julia_deps = add_list req.julia_deps [ "ONNXRunTime"; "ONNX" ] }
  | "Julia", "json" ->
      { req with julia_deps = add_list req.julia_deps [ "JSON" ] }
  | "Julia", "csv" ->
      { req with julia_deps = add_list req.julia_deps [ "CSV"; "DataFrames" ] }
  | "Julia", "ipc" ->
      { req with julia_deps = add_list req.julia_deps [ "Arrow"; "DataFrames" ] }
  | "Julia", "parquet" ->
      { req with julia_deps = add_list req.julia_deps [ "Parquet2"; "DataFrames" ] }
  | _ ->
      empty_requirements

let add_quarto_requirement ~node_name =
  let req =
    with_reason empty_requirements
      (Printf.sprintf "node `%s` uses runtime `Quarto`" node_name)
  in
  {
    req with
    r_deps = add_list req.r_deps [ "knitr"; "rmarkdown" ];
    py_deps = add_list req.py_deps [ "ipykernel"; "nbclient"; "nbformat"; "pyyaml" ];
    additional_tools = add_list req.additional_tools [ "quarto"; "which" ];
  }

(** Code mask for R text: `true` for code, `false` for string literals and
    `#` comments (newlines stay code). Roxygen collection must run on the
    original text; `library`-family and `pkg::` scans run on the original
    text too but keep only matches whose package-name span is all code.
    Limits: backtick names count as code. R 4 raw strings count as code.
    Backslash escapes inside strings are honored. *)
let r_code_mask (text : string) : bool array =
  let len = String.length text in
  let mask = Array.make len true in
  let rec scan i in_single in_double =
    if i >= len then ()
    else
      let c = text.[i] in
      if in_single then
        match c with
        | '\n' -> scan (i + 1) false false
        | '\\' ->
            mask.(i) <- false;
            if i + 1 < len then begin
              if text.[i + 1] <> '\n' then mask.(i + 1) <- false;
              scan (i + 2) true false
            end else scan (i + 1) true false
        | '\'' -> mask.(i) <- false; scan (i + 1) false false
        | _ -> mask.(i) <- false; scan (i + 1) true false
      else if in_double then
        match c with
        | '\n' -> scan (i + 1) false false
        | '\\' ->
            mask.(i) <- false;
            if i + 1 < len then begin
              if text.[i + 1] <> '\n' then mask.(i + 1) <- false;
              scan (i + 2) false true
            end else scan (i + 1) false true
        | '"' -> mask.(i) <- false; scan (i + 1) false false
        | _ -> mask.(i) <- false; scan (i + 1) false true
      else
        match c with
        | '\'' -> mask.(i) <- false; scan (i + 1) true false
        | '"' -> mask.(i) <- false; scan (i + 1) false true
        | '#' ->
            let j = ref i in
            while !j < len && text.[!j] <> '\n' do
              mask.(!j) <- false;
              incr j
            done;
            scan !j false false
        | _ -> scan (i + 1) false false
  in
  scan 0 false false;
  mask

(** Render cleaned R text: non-code characters become spaces, newlines kept.
    Test and debug helper built on [r_code_mask]. *)
let strip_r_strings_and_comments (text : string) : string =
  let mask = r_code_mask text in
  String.mapi (fun i c -> if mask.(i) then c else if c = '\n' then '\n' else ' ') text

(** A regex package-name span counts only when fully on code. *)
let span_is_code mask lo hi =
  let ok = ref true in
  let i = ref lo in
  while !ok && !i < hi do
    if !i < 0 || !i >= Array.length mask || not mask.(!i) then ok := false;
    incr i
  done;
  !ok && hi > lo

let scan_code_requirements ~node_name ~runtime raw_text =
  let reason = Printf.sprintf "node `%s` usage discovery" node_name in
  let req = with_reason empty_requirements reason in
  match runtime with
  | "R" ->
      (* Generic R package discovery: roxygen `@import`/`@importFrom`
         (incl. Classes/Methods variants) tags, `library()`/`require()`/
         `requireNamespace()`/`loadNamespace()` calls, and `pkg::`
         qualifiers — for any package name, not just a hardcoded list.
         Base packages and the `tlang` companion are excluded. Roxygen is
         read from the original text; call matches count when the call
         sits on code, `::` matches when the package-name span sits on
         code (no strings, no `#` comments). Installation still flows through
         tproject.toml, so every hit surfaces in the prompt/auto-add UX.
         User code keeps attaching libraries itself. *)
      let is_pkg_char = function
        | 'A'..'Z' | 'a'..'z' | '0'..'9' | '.' -> true
        | _ -> false
      in
      let valid_pkg s =
        let n = String.length s in
        n > 0 && s.[0] <> '.' &&
        String.for_all is_pkg_char s
      in
      let add_pkg acc pkg =
        (* Exclude base R packages (always available) and the `tlang`
           companion package (provided via `tlang-r`, not nixpkgs). *)
        if valid_pkg pkg && not (Renv_resolver.is_base_r_package pkg)
           && pkg <> "tlang"
           && not (String_set.mem pkg acc)
        then String_set.add pkg acc
        else acc
      in
      (* Roxygen tags are line-based: `#' @import pkg...`,
         `#' @importFrom pkg fn...` — the package is the first token. *)
      let from_roxygen acc =
        List.fold_left (fun acc line ->
          let t = String.trim line in
          let body =
            if String.length t >= 2 && String.sub t 0 2 = "#'" then
              String.trim (String.sub t 2 (String.length t - 2))
            else if String.length t >= 1 && t.[0] = '#' then
              String.trim (String.sub t 1 (String.length t - 1))
            else ""
          in
          if body = "" || body.[0] <> '@' then acc
          else
            let tag_end =
              try String.index body ' ' with Not_found ->
              try String.index body '\t' with Not_found -> String.length body
            in
            let tag = String.sub body 0 tag_end in
            let is_import_tag =
              tag = "@import" || tag = "@importFrom"
              || tag = "@importClassesFrom" || tag = "@importMethodsFrom"
            in
            if not is_import_tag then acc
            else
              let rest = String.trim (String.sub body tag_end (String.length body - tag_end)) in
              if tag = "@import" then
                (* `@import` may list several packages. *)
                let parts = String.split_on_char ' ' rest
                  |> List.concat_map (String.split_on_char '\t')
                  |> List.concat_map (String.split_on_char ',') in
                List.fold_left (fun acc part ->
                  let part = String.trim part in
                  if part = "" then acc else add_pkg acc part
                ) acc parts
              else begin
                (* `@importFrom` (and Classes/Methods variants) name a
                   single package followed by imported symbols. *)
                let pkg_end =
                  let i = ref 0 in
                  while !i < String.length rest && is_pkg_char rest.[!i] do incr i done;
                  !i
                in
                if pkg_end = 0 then acc
                else add_pkg acc (String.sub rest 0 pkg_end)
              end
        ) acc (String.split_on_char '\n' raw_text)
      in
      (* library-family calls, quoted or not: `library`, `require`,
         `requireNamespace`, `loadNamespace`. Longest names come first so
         the `require` prefix never shadows `requireNamespace`.
         Whitespace classes use a real TAB character: inside OCaml {| |}
         strings a backslash is literal, and Str reads \t as a plain t,
         so [ \t] there would swallow package initials. Plain
         double-quoted patterns keep \t a genuine tab. Two patterns
         (quoted/unquoted), earliest wins. Runs on the original text; a
         match counts only when the call itself sits on code. Quoted
         package names live inside string literals by design, so the
         name span is not checked — the call-site check alone rejects
         calls written inside strings or `#` comments. *)
      let from_library_calls mask code acc =
        let re_plain = Str.regexp "\\(requireNamespace\\|loadNamespace\\|library\\|require\\)[ \t]*([ \t]*\\([A-Za-z0-9.]+\\)" in
        let re_quoted = Str.regexp "\\(requireNamespace\\|loadNamespace\\|library\\|require\\)[ \t]*([ \t]*[\"']\\([A-Za-z0-9.]+\\)" in
        let at re pos =
          try Some (Str.search_forward re code pos) with Not_found -> None
        in
        let rec loop acc pos =
          let pick =
            match at re_plain pos, at re_quoted pos with
            | None, None -> None
            | Some p1, Some p2 -> Some (if p1 <= p2 then (re_plain, p1) else (re_quoted, p2))
            | Some p, None -> Some (re_plain, p)
            | None, Some p -> Some (re_quoted, p)
          in
          match pick with
          | None -> acc
          | Some (re, p) ->
              let _ = Str.search_forward re code p in
              let acc =
                if span_is_code mask p (p + 1) then
                  let pkg =
                    try Str.matched_group 2 code with Not_found | Invalid_argument _ -> ""
                  in
                  add_pkg acc pkg
                else acc
              in
              loop acc (Str.match_end ())
        in
        loop acc 0
      in
      (* `pkg::fun` qualifiers (also matches `:::`). Runs on the original
         text; only matches with the name span on code count. *)
      let from_namespaced mask code acc =
        let re = Str.regexp {|\([A-Za-z0-9.]+\)::|} in
        let rec loop acc pos =
          match (try Some (Str.search_forward re code pos) with Not_found -> None) with
          | None -> acc
          | Some _ ->
              let acc =
                (match (try Some (Str.group_beginning 1, Str.group_end 1) with Not_found | Invalid_argument _ -> None) with
                 | Some (lo, hi) when span_is_code mask lo hi ->
                     let pkg =
                       try Str.matched_group 1 code with Not_found | Invalid_argument _ -> ""
                     in
                     add_pkg acc pkg
                 | _ -> acc)
              in
              loop acc (Str.match_end ())
        in
        loop acc 0
      in
      let mask = r_code_mask raw_text in
      let found =
        from_namespaced mask raw_text (from_library_calls mask raw_text (from_roxygen String_set.empty))
      in
      { req with r_deps = String_set.union req.r_deps found }
  | "Python" ->
      let has_pkg pkg =
        let re1 = Str.regexp (Printf.sprintf "import %s" pkg) in
        let re2 = Str.regexp (Printf.sprintf "from %s" pkg) in
        (try ignore (Str.search_forward re1 raw_text 0); true with Not_found ->
         try ignore (Str.search_forward re2 raw_text 0); true with Not_found -> false)
      in
      let req =
        if has_pkg "matplotlib" then
          { req with py_deps = add_list req.py_deps [ "matplotlib"; "cloudpickle" ] }
        else
          req
      in
      let req =
        if has_pkg "seaborn" then
          { req with py_deps = add_list req.py_deps [ "seaborn"; "matplotlib"; "cloudpickle" ] }
        else
          req
      in
      let req =
        if has_pkg "plotnine" then
          { req with py_deps = add_list req.py_deps [ "plotnine"; "pandas"; "cloudpickle" ] }
        else
          req
      in
      let req =
        if has_pkg "plotly" then
          { req with py_deps = add_list req.py_deps [ "plotly"; "kaleido"; "cloudpickle" ] }
        else
          req
      in
      let req =
        if has_pkg "altair" then
          { req with py_deps = add_list req.py_deps [ "altair"; "vl-convert-python"; "cloudpickle" ] }
        else
          req
      in
      if String_set.is_empty req.py_deps then empty_requirements else req
  | "Julia" ->
      let has_pkg pkg =
        let re1 = Str.regexp (Printf.sprintf "using %s" pkg) in
        let re2 = Str.regexp (Printf.sprintf "import %s" pkg) in
        (try ignore (Str.search_forward re1 raw_text 0); true with Not_found ->
         try ignore (Str.search_forward re2 raw_text 0); true with Not_found -> false)
      in
      let req = if has_pkg "JSON" then { req with julia_deps = add_list req.julia_deps [ "JSON" ] } else req in
      let req = if has_pkg "CSV" then { req with julia_deps = add_list req.julia_deps [ "CSV" ] } else req in
       let req = if has_pkg "DataFrames" then { req with julia_deps = add_list req.julia_deps [ "DataFrames" ] } else req in
       let req = if has_pkg "Arrow" then { req with julia_deps = add_list req.julia_deps [ "Arrow" ] } else req in
       let req = if has_pkg "GLM" then { req with julia_deps = add_list req.julia_deps [ "GLM" ] } else req in
       let req = if has_pkg "Distributions" then { req with julia_deps = add_list req.julia_deps [ "Distributions" ] } else req in
       let req = if has_pkg "TidierPlots" then { req with julia_deps = add_list req.julia_deps [ "TidierPlots" ] } else req in
       let req = if has_pkg "Plots" then { req with julia_deps = add_list req.julia_deps [ "Plots" ] } else req in
       let req = if has_pkg "Makie" then { req with julia_deps = add_list req.julia_deps [ "Makie" ] } else req in
       let req = if has_pkg "CairoMakie" then { req with julia_deps = add_list req.julia_deps [ "CairoMakie" ] } else req in
       let req = if has_pkg "ONNXRunTime" then { req with julia_deps = add_list req.julia_deps [ "ONNXRunTime" ] } else req in
       let req = if has_pkg "ONNX" then { req with julia_deps = add_list req.julia_deps [ "ONNX" ] } else req in
       req
  | _ -> empty_requirements

let required_for_pipeline (p : Ast.pipeline_result) =
  List.fold_left
    (fun acc (node_name, cmd_expr) ->
      let runtime =
        match List.assoc_opt node_name p.p_runtimes with
        | Some r -> r
        | None -> "T"
      in
      let serializer =
        match List.assoc_opt node_name p.p_serializers with
        | Some expr -> expr
        | None -> Ast.mk_expr (Ast.Var "default")
      in
      let deserializer =
        match List.assoc_opt node_name p.p_deserializers with
        | Some expr -> expr
        | None -> Ast.mk_expr (Ast.Var "default")
      in
      let formats =
        add_list String_set.empty (formats_of_expr serializer @ formats_of_expr deserializer)
      in
      let acc =
        String_set.fold
          (fun feature req ->
            merge_requirements req (add_feature_requirement ~node_name ~runtime ~feature))
          formats acc
      in
      let acc =
        match cmd_expr.node with
        | RawCode { raw_text; _ } ->
            merge_requirements acc (scan_code_requirements ~node_name ~runtime raw_text)
        | _ -> acc
      in
      let acc =
        if runtime = "Quarto" then
          merge_requirements acc (add_quarto_requirement ~node_name)
        else if runtime = "R" then
          merge_requirements acc { empty_requirements with r_deps = add_list String_set.empty [ "jsonlite" ] }
        else if runtime = "Julia" then
          merge_requirements acc { empty_requirements with julia_deps = add_list String_set.empty [ "JSON" ] }
        else acc
      in
      acc)
    empty_requirements
    p.p_exprs

let required_serializer_packages (p : Ast.pipeline_result) : string list * string list =
  let req = required_for_pipeline p in
  (String_set.elements req.r_deps, String_set.elements req.py_deps)

let analyze_missing_requirements (p : Ast.pipeline_result) (cfg : project_config) =
  let required = required_for_pipeline p in
  let missing_from required_list existing_list =
    String_set.diff required_list (add_list String_set.empty existing_list)
    |> String_set.elements
  in
  let r_git_names = List.map (fun (g : Package_types.r_git_dependency) -> g.rgd_name) cfg.proj_r_git_dependencies in
  let existing_r = cfg.proj_r_dependencies @ r_git_names in
  {
    missing_r_deps = missing_from required.r_deps existing_r;
    missing_py_deps =
      if cfg.proj_py_resolver = "uv" then []
      else missing_from required.py_deps cfg.proj_py_dependencies;
    missing_julia_deps = missing_from required.julia_deps cfg.proj_julia_dependencies;
    missing_additional_tools =
      missing_from required.additional_tools cfg.proj_additional_tools;
    missing_latex_pkgs = missing_from required.latex_pkgs cfg.proj_latex_packages;
    reasons = String_set.elements required.reasons;
  }

let analysis_is_empty analysis =
  analysis.missing_r_deps = []
  && analysis.missing_py_deps = []
  && analysis.missing_julia_deps = []
  && analysis.missing_additional_tools = []
  && analysis.missing_latex_pkgs = []

let append_missing existing missing =
  let existing_set = add_list String_set.empty existing in
  existing
  @ List.filter (fun item -> not (String_set.mem item existing_set)) missing

let update_config_with_missing_requirements (cfg : project_config) analysis =
  {
    cfg with
    proj_r_dependencies = append_missing cfg.proj_r_dependencies analysis.missing_r_deps;
    proj_py_dependencies = append_missing cfg.proj_py_dependencies analysis.missing_py_deps;
    proj_julia_dependencies = append_missing cfg.proj_julia_dependencies analysis.missing_julia_deps;
    proj_additional_tools =
      append_missing cfg.proj_additional_tools analysis.missing_additional_tools;
    proj_latex_packages =
      append_missing cfg.proj_latex_packages analysis.missing_latex_pkgs;
  }

let format_package_list packages =
  Printf.sprintf "[%s]"
    (String.concat ", " (List.map (fun pkg -> Printf.sprintf "%S" pkg) packages))

let format_analysis analysis =
  let sections =
    [
      ("[r-dependencies]", analysis.missing_r_deps);
      ("[py-dependencies]", analysis.missing_py_deps);
      ("[jl-dependencies]", analysis.missing_julia_deps);
      ("[additional-tools]", analysis.missing_additional_tools);
      ("[latex]", analysis.missing_latex_pkgs);
    ]
    |> List.filter_map (fun (section, packages) ->
           if packages = [] then None
           else Some (Printf.sprintf "  %s packages += %s" section (format_package_list packages)))
  in
  let reasons =
    if analysis.reasons = [] then
      []
    else
      ("Required because:" :: List.map (fun reason -> "  - " ^ reason) analysis.reasons)
  in
  String.concat "\n"
    ([
       "Pipeline requires explicit dependencies in `tproject.toml` before it can be emitted or built.";
     ]
     @ reasons
     @ [ "Missing entries:" ]
     @ sections)

let is_interactive () =
  try Unix.isatty Unix.stdin && Unix.isatty Unix.stdout with _ -> false

let read_line_from_channel ch =
  try Some (input_line ch) with End_of_file -> None

let read_prompt_answer ?(tty_path="/dev/tty") ?(isatty=is_interactive) () =
  if isatty () then
    try
      let ch = open_in tty_path in
      Fun.protect
        ~finally:(fun () -> close_in_noerr ch)
        (fun () -> read_line_from_channel ch)
    with Sys_error _ -> read_line_from_channel stdin
  else
    read_line_from_channel stdin

let answer_is_yes answer =
  let normalized = String.lowercase_ascii (String.trim answer) in
  normalized = "y" || normalized = "yes"

let read_file path =
  try
    let ch = open_in path in
    let content =
      Fun.protect
        ~finally:(fun () -> close_in_noerr ch)
        (fun () -> really_input_string ch (in_channel_length ch))
    in
    Ok content
  with Sys_error msg -> Error (Printf.sprintf "%s (%s)" msg path)

let write_file path content =
  try
    let ch = open_out path in
    Fun.protect
      ~finally:(fun () -> close_out_noerr ch)
      (fun () -> output_string ch content);
    Ok ()
  with Sys_error msg -> Error (Printf.sprintf "%s (%s)" msg path)


let prompt_to_update ~tproject_path analysis =
  Printf.printf "%s\n\nAdd these entries to %s now? [y/N]: %!"
    (format_analysis analysis) tproject_path;
  match read_prompt_answer () with
  | Some answer -> answer_is_yes answer
  | None ->
        Printf.printf "\nNo input received; leaving `tproject.toml` unchanged.\n%!";
        false

let env_flag name =
  match Sys.getenv_opt name with
  | Some ("1" | "true" | "TRUE" | "yes" | "YES" | "on" | "ON") -> true
  | _ -> false

let rebuild_message tproject_path =
  Printf.sprintf
    "Updated %s with explicit pipeline dependencies.\nPlease leave the current shell, run `t update`, re-enter with `nix develop`, and then retry building the pipeline."
    tproject_path

let ensure_project_requirements (p : Ast.pipeline_result) =
  let project_root = Builder_utils.get_project_root () in
  let tproject_path = Filename.concat project_root "tproject.toml" in
  let required = required_for_pipeline p in
  let has_any_requirements =
    not (String_set.is_empty required.r_deps)
    || not (String_set.is_empty required.py_deps)
    || not (String_set.is_empty required.julia_deps)
    || not (String_set.is_empty required.additional_tools)
    || not (String_set.is_empty required.latex_pkgs)
  in
  if not has_any_requirements then
    Ok ()
  else if not (Sys.file_exists tproject_path) then
    if env_flag "TLANG_AUTO_ADD_PIPELINE_DEPS" then
      Ok ()
    else
      let analysis =
        {
          missing_r_deps = String_set.elements required.r_deps;
          missing_py_deps = String_set.elements required.py_deps;
          missing_julia_deps = String_set.elements required.julia_deps;
          missing_additional_tools = String_set.elements required.additional_tools;
          missing_latex_pkgs = String_set.elements required.latex_pkgs;
          reasons = String_set.elements required.reasons;
        }
      in
      Error
        (Printf.sprintf
           "%s\n\n`tproject.toml` was not found at %s, so T cannot add these dependencies automatically."
           (format_analysis analysis) tproject_path)
  else
    match read_file tproject_path with
    | Error msg -> Error (Printf.sprintf "Cannot read tproject.toml: %s" msg)
    | Ok content ->
        (match Toml_parser.parse_tproject_toml ~root_dir:project_root content with
         | Error msg -> Error (Printf.sprintf "Cannot parse tproject.toml: %s" msg)
         | Ok cfg ->
              let cfg =
                if cfg.proj_r_resolver = "renv" then
                  match Renv_resolver.split_packages ~project_root with
                  | Ok (renv_cran, renv_git) ->
                    { cfg with
                      proj_r_dependencies = cfg.proj_r_dependencies @ renv_cran;
                      proj_r_git_dependencies = cfg.proj_r_git_dependencies @ renv_git;
                    }
                  | Error _ -> cfg
                else cfg
              in
             let analysis = analyze_missing_requirements p cfg in
             if analysis_is_empty analysis then
               Ok ()
             else if env_flag "TLANG_AUTO_ADD_PIPELINE_DEPS" then
               let updated_cfg = update_config_with_missing_requirements cfg analysis in
               let updated_content = Toml_parser.serialize_tproject_toml updated_cfg in
               (match write_file tproject_path updated_content with
                | Error msg -> Error (Printf.sprintf "Failed to update tproject.toml: %s" msg)
                | Ok () -> Error (rebuild_message tproject_path))
             else if not (is_interactive ()) then
               Error
                  (format_analysis analysis
                  ^ "\n\nThis session is non-interactive, so T cannot update `tproject.toml` automatically."
                  ^ "\nSet `TLANG_AUTO_ADD_PIPELINE_DEPS=1` to auto-add the missing entries in CI or other unattended environments.")
             else if not (prompt_to_update ~tproject_path analysis) then
               Error
                  (format_analysis analysis
                  ^ "\n\nUser declined to update `tproject.toml`.")
             else
                let updated_cfg = update_config_with_missing_requirements cfg analysis in
                let updated_content = Toml_parser.serialize_tproject_toml updated_cfg in
                match write_file tproject_path updated_content with
                | Error msg -> Error (Printf.sprintf "Failed to update tproject.toml: %s" msg)
                | Ok () -> Error (rebuild_message tproject_path))
