(* src/package_manager/provenance.ml *)
(* Offline, deterministic reproducibility & audit bundle generator for T
   projects. Reads local tproject.toml, flake.lock, _pipeline/ build logs +
   foreign_meta sidecars, and intent { ... } blocks to emit RO-Crate 1.1
   JSON-LD, CycloneDX 1.5 SBOM JSON, or T-native provenance JSON. *)

type flake_input = {
  fi_name : string;
  fi_type : string option;
  fi_owner : string option;
  fi_repo : string option;
  fi_url : string option;
  fi_path : string option;
  fi_rev : string option;
  fi_nar_hash : string option;
  fi_last_modified : int option;
}

type node_record = {
  nr_name : string;
  nr_runtime : string;
  nr_serializer : string;
  nr_status : string;
  nr_path : string option;
  nr_deps : string list;
  nr_script : string option;
  nr_script_hash : string option;
  nr_duration : float option;
  nr_foreign_meta : Yojson.Safe.t option;
}

type intent_record = {
  ir_file : string;
  ir_fields : (string * string) list;
}

type project_info = {
  pi_name : string;
  pi_version : string;
  pi_description : string;
  pi_license : string;
  pi_r_pkgs : string list;
  pi_py_pkgs : string list;
  pi_jl_pkgs : string list;
  pi_tools : string list;
}

(* Pure OCaml Base64 decoder -> lowercase hex for CycloneDX SHA-256 hashes. *)
let b64_val = function
  | 'A'..'Z' as c -> Some (Char.code c - Char.code 'A')
  | 'a'..'z' as c -> Some (Char.code c - Char.code 'a' + 26)
  | '0'..'9' as c -> Some (Char.code c - Char.code '0' + 52)
  | '+' -> Some 62
  | '/' -> Some 63
  | _ -> None

let sri_sha256_to_hex sri =
  let prefix = "sha256-" in
  if not (String.starts_with ~prefix sri) then None
  else
    let b64 = String.sub sri (String.length prefix) (String.length sri - String.length prefix) in
    let n = String.length b64 in
    if n = 0 || n mod 4 <> 0 then None
    else
      let buf = Buffer.create ((n / 4) * 3) in
      let ok = ref true in
      let i = ref 0 in
      while !i < n && !ok do
        let c0 = b64.[!i] and c1 = b64.[!i + 1]
        and c2 = b64.[!i + 2] and c3 = b64.[!i + 3] in
        (match b64_val c0, b64_val c1 with
         | Some v0, Some v1 ->
             Buffer.add_char buf (Char.chr ((v0 lsl 2) lor (v1 lsr 4)));
             if c2 <> '=' then begin
               match b64_val c2 with
               | Some v2 ->
                   Buffer.add_char buf (Char.chr (((v1 land 0x0f) lsl 4) lor (v2 lsr 2)));
                   if c3 <> '=' then begin
                     match b64_val c3 with
                     | Some v3 ->
                         Buffer.add_char buf (Char.chr (((v2 land 0x03) lsl 6) lor v3))
                     | None -> ok := false
                   end
               | None -> ok := false
             end else if c3 <> '=' then ok := false
         | _ -> ok := false);
        i := !i + 4
      done;
      if not !ok then None
      else
        let raw = Buffer.contents buf in
        if String.length raw <> 32 then None
        else
          let hex = Buffer.create 64 in
          String.iter (fun c -> Buffer.add_string hex (Printf.sprintf "%02x" (Char.code c))) raw;
          Some (Buffer.contents hex)

(* Extract bare package name from a versioned spec (e.g. "pandas>=2.0" -> "pandas")
   and percent-encode characters disallowed in purl names. *)
let sanitize_purl_name spec =
  let trimmed = String.trim spec in
  let n = String.length trimmed in
  let stop = ref 0 in
  while !stop < n && not (
    match trimmed.[!stop] with
    | ' ' | '\t' | '>' | '<' | '=' | '!' | '~' | ';' | '[' | '@' -> true
    | _ -> false)
  do
    incr stop
  done;
  let name = String.sub trimmed 0 !stop in
  let buf = Buffer.create (String.length name) in
  String.iter (fun c ->
    match c with
    | 'a'..'z' | 'A'..'Z' | '0'..'9' | '-' | '_' | '.' -> Buffer.add_char buf c
    | ch -> Buffer.add_string buf (Printf.sprintf "%%%02X" (Char.code ch))
  ) name;
  Buffer.contents buf

let utc_date_iso () =
  let tm = Unix.gmtime (Unix.gettimeofday ()) in
  Printf.sprintf "%04d-%02d-%02d" (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday

let make_relative_path ~dir path =
  let prefix = if String.ends_with ~suffix:"/" dir then dir else dir ^ "/" in
  if String.starts_with ~prefix path then
    String.sub path (String.length prefix) (String.length path - String.length prefix)
  else path

let read_project_info dir warnings =
  let fallback = {
    pi_name = Filename.basename (if dir = "." then Sys.getcwd () else dir);
    pi_version = "0.0.0";
    pi_description = "";
    pi_license = "UNSPECIFIED";
    pi_r_pkgs = [];
    pi_py_pkgs = [];
    pi_jl_pkgs = [];
    pi_tools = [];
  } in
  let toml_path = Filename.concat dir "tproject.toml" in
  match Artifact_meta.read_small_file toml_path with
  | None ->
      warnings := "tproject.toml not found; using fallback project metadata." :: !warnings;
      fallback
  | Some content ->
      (try
         let toml = Otoml.Parser.from_string content in
         let get_s path default =
           try Otoml.find toml Otoml.get_string path with _ -> default
         in
         let get_list path =
           try Otoml.find toml (Otoml.get_array Otoml.get_string) path with _ -> []
         in
         {
           pi_name = get_s ["project"; "name"] fallback.pi_name;
           pi_version = get_s ["project"; "version"] fallback.pi_version;
           pi_description = get_s ["project"; "description"] "";
           pi_license = get_s ["project"; "license"] "UNSPECIFIED";
           pi_r_pkgs = get_list ["r-dependencies"; "packages"];
           pi_py_pkgs = get_list ["py-dependencies"; "packages"];
           pi_jl_pkgs = get_list ["jl-dependencies"; "packages"];
           pi_tools = get_list ["additional-tools"; "packages"];
         }
       with exn ->
         warnings := Printf.sprintf "Failed to parse tproject.toml (%s); using fallback metadata." (Printexc.to_string exn) :: !warnings;
         fallback)

let read_flake_lock dir warnings : flake_input list =
  let lock_path = Filename.concat dir "flake.lock" in
  match Artifact_meta.read_small_file lock_path with
  | None ->
      warnings := "flake.lock not found; flake inputs omitted." :: !warnings;
      []
  | Some raw ->
      (try
         match Yojson.Safe.from_string raw with
         | `Assoc top ->
             (match List.assoc_opt "nodes" top with
              | Some (`Assoc nodes) ->
                  List.filter_map (fun (name, v) ->
                    if name = "root" then None
                    else
                      match v with
                      | `Assoc entry ->
                          (match List.assoc_opt "locked" entry with
                           | Some (`Assoc locked) ->
                               Some {
                                 fi_name = name;
                                 fi_type = Artifact_meta.assoc_str "type" locked;
                                 fi_owner = Artifact_meta.assoc_str "owner" locked;
                                 fi_repo = Artifact_meta.assoc_str "repo" locked;
                                 fi_url = Artifact_meta.assoc_str "url" locked;
                                 fi_path = Artifact_meta.assoc_str "path" locked;
                                 fi_rev = Artifact_meta.assoc_str "rev" locked;
                                 fi_nar_hash = Artifact_meta.assoc_str "narHash" locked;
                                 fi_last_modified =
                                   (match List.assoc_opt "lastModified" locked with
                                    | Some v -> Artifact_meta.json_to_int v
                                    | None -> None);
                               }
                           | _ -> None)
                      | _ -> None
                  ) nodes
                  |> List.sort (fun a b -> String.compare a.fi_name b.fi_name)
              | _ -> [])
         | _ ->
             warnings := "flake.lock did not contain a JSON object." :: !warnings;
             []
       with Yojson.Json_error msg ->
         warnings := Printf.sprintf "Failed to parse flake.lock: %s" msg :: !warnings;
         [])

let read_latest_nodes ~include_meta dir warnings : string option * node_record list =
  let pipeline_dir = Filename.concat dir "_pipeline" in
  match Artifact_meta.latest_build_log_in_dir pipeline_dir with
  | None ->
      warnings := "No build logs found in _pipeline/." :: !warnings;
      (None, [])
  | Some log_path ->
      let log_name = Filename.basename log_path in
      let raw_nodes = Artifact_meta.load_build_log_nodes_cached log_path in
      let records =
        List.map (fun (nm, n) ->
          let deps =
            match List.assoc_opt "dependencies" n with
            | Some (`List ds) ->
                List.filter_map (function `String s -> Some s | _ -> None) ds
            | _ -> []
          in
          let path = Artifact_meta.assoc_str "path" n in
          let foreign_meta =
            if not include_meta then None
            else
              match path with
              | Some p -> Artifact_meta.read_meta_json_of_artifact p
              | None -> None
          in
          let duration =
            match List.assoc_opt "duration" n with
            | Some v -> Artifact_meta.json_to_float v
            | None -> None
          in
          {
            nr_name = nm;
            nr_runtime = Option.value ~default:"T" (Artifact_meta.assoc_str "runtime" n);
            nr_serializer = Option.value ~default:"default" (Artifact_meta.assoc_str "serializer" n);
            nr_status = Option.value ~default:"Unknown" (Artifact_meta.assoc_str "status" n);
            nr_path = path;
            nr_deps = deps;
            nr_script = Artifact_meta.assoc_str "script" n;
            nr_script_hash = Artifact_meta.assoc_str "script_hash" n;
            nr_duration = duration;
            nr_foreign_meta = foreign_meta;
          }
        ) raw_nodes
      in
      (Some log_name, records)

let extract_intents_from_file ~dir path warnings : intent_record list =
  match Artifact_meta.read_small_file path with
  | None -> []
  | Some content ->
      (try
         let lexbuf = Lexing.from_string content in
         let program = Parser.program Lexer.token lexbuf in
         let rec exprs_in_expr (e : Ast.expr) =
           e :: List.concat_map exprs_in_expr (Ast.children_of_expr e)
         in
         let all_exprs =
           List.concat_map (fun s -> List.concat_map exprs_in_expr (Ast.children_of_stmt s)) program
         in
         let rel_file = make_relative_path ~dir path in
         List.filter_map (fun (e : Ast.expr) ->
           match e.Ast.node with
           | Ast.IntentDef pairs ->
               let fields =
                 List.map (fun (k, ve) ->
                   let v_str =
                     match ve.Ast.node with
                     | Ast.Value (Ast.VString s) -> s
                     | _ -> Nix_unparse.expr_to_string ve
                   in
                   (k, v_str)
                 ) pairs
               in
               Some { ir_file = rel_file; ir_fields = fields }
           | _ -> None
         ) all_exprs
       with exn ->
         warnings := Printf.sprintf "Skipped intents in %s: %s" (make_relative_path ~dir path) (Printexc.to_string exn) :: !warnings;
         [])

let rec collect_t_files_recursive dir =
  try
    if not (Sys.file_exists dir && Sys.is_directory dir) then []
    else
      Array.to_list (Sys.readdir dir)
      |> List.sort String.compare
      |> List.concat_map (fun entry ->
        if String.starts_with ~prefix:"." entry then []
        else
          let full = Filename.concat dir entry in
          if Sys.is_directory full then collect_t_files_recursive full
          else if String.ends_with ~suffix:".t" entry then [full]
          else []
      )
  with Sys_error _ -> []

let collect_intents ~dir ?file warnings =
  match file with
  | Some f -> extract_intents_from_file ~dir f warnings
  | None ->
      let src_dir = Filename.concat dir "src" in
      let candidates = collect_t_files_recursive src_dir in
      List.concat_map (fun p -> extract_intents_from_file ~dir p warnings) candidates

let opt_str_json = function Some s -> `String s | None -> `Null
let opt_int_json = function Some i -> `Int i | None -> `Null
let opt_float_json = function Some f -> `Float f | None -> `Null

let to_native_json ~project ~flake_inputs ~build_log ~nodes ~intents ~warnings : Yojson.Safe.t =
  let flake_json =
    List.map (fun fi ->
      `Assoc [
        ("name", `String fi.fi_name);
        ("type", opt_str_json fi.fi_type);
        ("owner", opt_str_json fi.fi_owner);
        ("repo", opt_str_json fi.fi_repo);
        ("url", opt_str_json fi.fi_url);
        ("path", opt_str_json fi.fi_path);
        ("rev", opt_str_json fi.fi_rev);
        ("nar_hash", opt_str_json fi.fi_nar_hash);
        ("last_modified", opt_int_json fi.fi_last_modified);
      ]
    ) flake_inputs
  in
  let nodes_json =
    List.map (fun nr ->
      let base = [
        ("node", `String nr.nr_name);
        ("runtime", `String nr.nr_runtime);
        ("serializer", `String nr.nr_serializer);
        ("status", `String nr.nr_status);
        ("path", opt_str_json nr.nr_path);
        ("dependencies", `List (List.map (fun d -> `String d) nr.nr_deps));
        ("script", opt_str_json nr.nr_script);
        ("script_hash", opt_str_json nr.nr_script_hash);
        ("duration", opt_float_json nr.nr_duration);
      ] in
      let with_meta =
        match nr.nr_foreign_meta with
        | Some m -> base @ [("foreign_meta", m)]
        | None -> base
      in
      `Assoc with_meta
    ) nodes
  in
  let intents_json =
    List.map (fun ir ->
      `Assoc [
        ("file", `String ir.ir_file);
        ("fields", `Assoc (List.map (fun (k, v) -> (k, `String v)) ir.ir_fields));
      ]
    ) intents
  in
  `Assoc [
    ("schema_version", `String "1.0");
    ("tlang_version", `String Version.version);
    ("project", `Assoc [
      ("name", `String project.pi_name);
      ("version", `String project.pi_version);
      ("description", `String project.pi_description);
      ("license", `String project.pi_license);
      ("r_packages", `List (List.map (fun s -> `String s) project.pi_r_pkgs));
      ("python_packages", `List (List.map (fun s -> `String s) project.pi_py_pkgs));
      ("julia_packages", `List (List.map (fun s -> `String s) project.pi_jl_pkgs));
      ("additional_tools", `List (List.map (fun s -> `String s) project.pi_tools));
    ]);
    ("build_log", opt_str_json build_log);
    ("flake_inputs", `List flake_json);
    ("nodes", `List nodes_json);
    ("intents", `List intents_json);
    ("warnings", `List (List.map (fun w -> `String w) warnings));
  ]

let to_ro_crate_json ~project ~flake_inputs ~build_log ~nodes ~intents : Yojson.Safe.t =
  let input_ids = List.map (fun fi -> `Assoc [("@id", `String ("#flake-" ^ fi.fi_name))]) flake_inputs in
  let node_ids = List.map (fun nr -> `Assoc [("@id", `String ("#node-" ^ nr.nr_name))]) nodes in
  let intent_ids = List.mapi (fun i _ -> `Assoc [("@id", `String (Printf.sprintf "#intent-%d" (i + 1)))]) intents in
  let root_desc =
    if project.pi_description <> "" then project.pi_description
    else "Reproducible T language analysis pipeline"
  in
  let metadata_descriptor =
    `Assoc [
      ("@type", `String "CreativeWork");
      ("@id", `String "ro-crate-metadata.json");
      ("conformsTo", `Assoc [("@id", `String "https://w3id.org/ro/crate/1.1")]);
      ("about", `Assoc [("@id", `String "./")]);
    ]
  in
  let root_dataset =
    `Assoc [
      ("@id", `String "./");
      ("@type", `String "Dataset");
      ("name", `String project.pi_name);
      ("version", `String project.pi_version);
      ("description", `String root_desc);
      ("datePublished", `String (utc_date_iso ()));
      ("license", `String project.pi_license);
      ("mentions", `List (input_ids @ node_ids @ intent_ids));
      ("additionalProperty", `List [
        `Assoc [("@type", `String "PropertyValue"); ("name", `String "tlang_version"); ("value", `String Version.version)];
        `Assoc [("@type", `String "PropertyValue"); ("name", `String "build_log"); ("value", opt_str_json build_log)];
      ]);
    ]
  in
  let flake_entities =
    List.map (fun fi ->
      let props =
        List.filter_map (fun (k, v_opt) ->
          match v_opt with
          | Some v -> Some (`Assoc [("@type", `String "PropertyValue"); ("name", `String k); ("value", `String v)])
          | None -> None
        ) [
          ("type", fi.fi_type);
          ("owner", fi.fi_owner);
          ("repo", fi.fi_repo);
          ("url", fi.fi_url);
          ("path", fi.fi_path);
          ("rev", fi.fi_rev);
          ("narHash", fi.fi_nar_hash);
          ("lastModified", Option.map string_of_int fi.fi_last_modified);
        ]
      in
      `Assoc [
        ("@id", `String ("#flake-" ^ fi.fi_name));
        ("@type", `String "SoftwareSourceCode");
        ("name", `String fi.fi_name);
        ("additionalProperty", `List props);
      ]
    ) flake_inputs
  in
  let node_entities =
    List.map (fun nr ->
      let props = ref [
        `Assoc [("@type", `String "PropertyValue"); ("name", `String "runtime"); ("value", `String nr.nr_runtime)];
        `Assoc [("@type", `String "PropertyValue"); ("name", `String "serializer"); ("value", `String nr.nr_serializer)];
        `Assoc [("@type", `String "PropertyValue"); ("name", `String "status"); ("value", `String nr.nr_status)];
      ] in
      (match nr.nr_path with
       | Some p -> props := !props @ [`Assoc [("@type", `String "PropertyValue"); ("name", `String "nixStorePath"); ("value", `String p)]]
       | None -> ());
      (match nr.nr_script_hash with
       | Some h -> props := !props @ [`Assoc [("@type", `String "PropertyValue"); ("name", `String "scriptHash"); ("value", `String h)]]
       | None -> ());
      (match nr.nr_duration with
       | Some d -> props := !props @ [`Assoc [("@type", `String "PropertyValue"); ("name", `String "durationSeconds"); ("value", `Float d)]]
       | None -> ());
      (match nr.nr_foreign_meta with
       | Some m ->
           (* Stringify foreignMeta so JSON-LD processors do not drop unknown keys. *)
           props := !props @ [`Assoc [("@type", `String "PropertyValue"); ("name", `String "foreignMeta"); ("value", `String (Yojson.Safe.to_string m))]]
       | None -> ());
      `Assoc [
        ("@id", `String ("#node-" ^ nr.nr_name));
        ("@type", `String "CreateAction");
        ("name", `String nr.nr_name);
        ("object", `List (List.map (fun d -> `Assoc [("@id", `String ("#node-" ^ d))]) nr.nr_deps));
        ("additionalProperty", `List !props);
      ]
    ) nodes
  in
  let intent_entities =
    List.mapi (fun i ir ->
      let props =
        List.map (fun (k, v) ->
          `Assoc [("@type", `String "PropertyValue"); ("name", `String k); ("value", `String v)]
        ) ir.ir_fields
      in
      `Assoc [
        ("@id", `String (Printf.sprintf "#intent-%d" (i + 1)));
        ("@type", `String "CreativeWork");
        ("name", `String ir.ir_file);
        ("additionalProperty", `List props);
      ]
    ) intents
  in
  `Assoc [
    ("@context", `String "https://w3id.org/ro/crate/1.1/context");
    ("@graph", `List (metadata_descriptor :: root_dataset :: flake_entities @ node_entities @ intent_entities));
  ]

let to_sbom_json ~project ~flake_inputs ~nodes : Yojson.Safe.t =
  let seen_refs = Hashtbl.create 32 in
  let add_unique bom_ref comp =
    if Hashtbl.mem seen_refs bom_ref then None
    else begin
      Hashtbl.add seen_refs bom_ref ();
      Some comp
    end
  in
  let mk_pkg_component ~purl_type ~namespace spec =
    let clean = sanitize_purl_name spec in
    if clean = "" then None
    else
      let purl =
        match namespace with
        | Some ns -> Printf.sprintf "pkg:%s/%s/%s" purl_type ns clean
        | None -> Printf.sprintf "pkg:%s/%s" purl_type clean
      in
      add_unique purl
        (`Assoc [
          ("type", `String "library");
          ("bom-ref", `String purl);
          ("name", `String clean);
          ("purl", `String purl);
        ])
  in
  let flake_components =
    List.filter_map (fun fi ->
      let bom_ref = "nix:" ^ fi.fi_name in
      let ver = Option.value ~default:"locked" fi.fi_rev in
      let hashes =
        match fi.fi_nar_hash with
        | Some sri ->
            (match sri_sha256_to_hex sri with
             | Some hex -> [("hashes", `List [`Assoc [("alg", `String "SHA-256"); ("content", `String hex)]])]
             | None -> [])
        | None -> []
      in
      add_unique bom_ref
        (`Assoc ([
          ("type", `String "library");
          ("bom-ref", `String bom_ref);
          ("name", `String fi.fi_name);
          ("version", `String ver);
        ] @ hashes))
    ) flake_inputs
  in
  let pkg_components =
    List.filter_map (mk_pkg_component ~purl_type:"cran" ~namespace:None) project.pi_r_pkgs
    @ List.filter_map (mk_pkg_component ~purl_type:"pypi" ~namespace:None) project.pi_py_pkgs
    @ List.filter_map (mk_pkg_component ~purl_type:"generic" ~namespace:(Some "julia")) project.pi_jl_pkgs
    @ List.filter_map (mk_pkg_component ~purl_type:"generic" ~namespace:(Some "nix")) project.pi_tools
  in
  let node_components =
    List.filter_map (fun nr ->
      let bom_ref = "node:" ^ nr.nr_name in
      add_unique bom_ref
        (`Assoc [
          ("type", `String "data");
          ("bom-ref", `String bom_ref);
          ("name", `String nr.nr_name);
          ("version", `String nr.nr_status);
        ])
    ) nodes
  in
  let node_deps =
    List.map (fun nr ->
      let valid_deps =
        List.filter (fun d -> Hashtbl.mem seen_refs ("node:" ^ d)) nr.nr_deps
      in
      `Assoc [
        ("ref", `String ("node:" ^ nr.nr_name));
        ("dependsOn", `List (List.map (fun d -> `String ("node:" ^ d)) valid_deps));
      ]
    ) nodes
  in
  `Assoc [
    ("bomFormat", `String "CycloneDX");
    ("specVersion", `String "1.5");
    ("version", `Int 1);
    ("metadata", `Assoc [
      ("component", `Assoc [
        ("type", `String "application");
        ("name", `String project.pi_name);
        ("version", `String project.pi_version);
      ]);
      ("tools", `List [
        `Assoc [("name", `String "tlang"); ("version", `String Version.version)];
      ]);
    ]);
    ("components", `List (flake_components @ pkg_components @ node_components));
    ("dependencies", `List node_deps);
  ]

let generate ?(dir=".") ?file ?(include_meta=true) ~format () : (string, string) result =
  let fmt = String.lowercase_ascii (String.trim format) in
  if fmt <> "ro-crate" && fmt <> "sbom" && fmt <> "json" then
    Error (Printf.sprintf "Unknown provenance format \"%s\". Supported formats: ro-crate, sbom, json." format)
  else begin
    let warnings = ref [] in
    let project = read_project_info dir warnings in
    let flake_inputs = read_flake_lock dir warnings in
    let (build_log, nodes) = read_latest_nodes ~include_meta dir warnings in
    let intents = collect_intents ~dir ?file warnings in
    let warnings_list = List.rev !warnings in
    let json =
      match fmt with
      | "ro-crate" -> to_ro_crate_json ~project ~flake_inputs ~build_log ~nodes ~intents
      | "sbom" -> to_sbom_json ~project ~flake_inputs ~nodes
      | _ -> to_native_json ~project ~flake_inputs ~build_log ~nodes ~intents ~warnings:warnings_list
    in
    Ok (Yojson.Safe.pretty_to_string json ^ "\n")
  end

let write_bundle ?(dir=".") ?file ?output ?(include_meta=true) ~format () : (string, string) result =
  match generate ~dir ?file ~include_meta ~format () with
  | Error msg -> Error msg
  | Ok payload ->
      (match output with
       | None -> Ok payload
       | Some out_path ->
           try
             let oc = open_out_bin out_path in
             Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
               output_string oc payload);
             Ok payload
           with Sys_error msg -> Error msg)
