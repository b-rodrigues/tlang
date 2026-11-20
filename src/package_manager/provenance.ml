(* src/package_manager/provenance.ml *)
(* Pure, hermetic reproducibility & audit bundle generator for T projects.
   Reads local tproject.toml, flake.lock, _pipeline/ build logs + foreign_meta
   sidecars, and intent { ... } blocks to emit RO-Crate 1.1 JSON-LD,
   CycloneDX 1.5 SBOM JSON, or T-native provenance JSON. *)

type flake_input = {
  fi_name : string;
  fi_type : string option;
  fi_owner : string option;
  fi_repo : string option;
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
  pi_r_pkgs : string list;
  pi_py_pkgs : string list;
  pi_jl_pkgs : string list;
  pi_tools : string list;
}

let read_file_opt path =
  try
    let ch = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr ch) (fun () ->
      let n = in_channel_length ch in
      if n > 4 * 1024 * 1024 then None
      else Some (really_input_string ch n))
  with Sys_error _ -> None

let assoc_str key pairs =
  match List.assoc_opt key pairs with
  | Some (`String s) when String.trim s <> "" -> Some (String.trim s)
  | _ -> None

let assoc_int key pairs =
  match List.assoc_opt key pairs with
  | Some (`Int i) -> Some i
  | _ -> None

let assoc_float key pairs =
  match List.assoc_opt key pairs with
  | Some (`Float f) -> Some f
  | Some (`Int i) -> Some (float_of_int i)
  | _ -> None

let read_project_info dir =
  let fallback = {
    pi_name = Filename.basename (if dir = "." then Sys.getcwd () else dir);
    pi_version = "0.0.0";
    pi_description = "";
    pi_r_pkgs = [];
    pi_py_pkgs = [];
    pi_jl_pkgs = [];
    pi_tools = [];
  } in
  let toml_path = Filename.concat dir "tproject.toml" in
  match read_file_opt toml_path with
  | None -> fallback
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
           pi_r_pkgs = get_list ["r-dependencies"; "packages"];
           pi_py_pkgs = get_list ["py-dependencies"; "packages"];
           pi_jl_pkgs = get_list ["jl-dependencies"; "packages"];
           pi_tools = get_list ["additional-tools"; "packages"];
         }
       with _ -> fallback)

let read_flake_lock dir : flake_input list =
  let lock_path = Filename.concat dir "flake.lock" in
  match read_file_opt lock_path with
  | None -> []
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
                                 fi_type = assoc_str "type" locked;
                                 fi_owner = assoc_str "owner" locked;
                                 fi_repo = assoc_str "repo" locked;
                                 fi_rev = assoc_str "rev" locked;
                                 fi_nar_hash = assoc_str "narHash" locked;
                                 fi_last_modified = assoc_int "lastModified" locked;
                               }
                           | _ -> None)
                      | _ -> None
                  ) nodes
                  |> List.sort (fun a b -> String.compare a.fi_name b.fi_name)
              | _ -> [])
         | _ -> []
       with Yojson.Json_error _ -> [])

let read_foreign_meta_for_path path =
  let meta_path =
    try
      if Sys.file_exists path && Sys.is_directory path then
        Filename.concat path "meta"
      else
        Filename.concat (Filename.dirname path) "meta"
    with Sys_error _ -> ""
  in
  if meta_path = "" || not (try Sys.file_exists meta_path with Sys_error _ -> false) then None
  else
    match read_file_opt meta_path with
    | None -> None
    | Some raw ->
        (try Some (Yojson.Safe.from_string raw) with Yojson.Json_error _ -> None)

let read_latest_nodes dir : string option * node_record list =
  let pipeline_dir = Filename.concat dir "_pipeline" in
  match Schema_check.latest_build_log_in_dir pipeline_dir with
  | None -> (None, [])
  | Some log_path ->
      let log_name = Filename.basename log_path in
      (match read_file_opt log_path with
       | None -> (Some log_name, [])
       | Some raw ->
           (try
              match Yojson.Safe.from_string raw with
              | `Assoc top ->
                  (match List.assoc_opt "nodes" top with
                   | Some (`List nodes) ->
                       let records =
                         List.filter_map (function
                           | `Assoc n ->
                               (match assoc_str "node" n with
                                | None -> None
                                | Some nm ->
                                    let deps =
                                      match List.assoc_opt "dependencies" n with
                                      | Some (`List ds) ->
                                          List.filter_map (function `String s -> Some s | _ -> None) ds
                                      | _ -> []
                                    in
                                    let path = assoc_str "path" n in
                                    let foreign_meta =
                                      match path with
                                      | Some p -> read_foreign_meta_for_path p
                                      | None -> None
                                    in
                                    Some {
                                      nr_name = nm;
                                      nr_runtime = Option.value ~default:"T" (assoc_str "runtime" n);
                                      nr_serializer = Option.value ~default:"default" (assoc_str "serializer" n);
                                      nr_status = Option.value ~default:"Unknown" (assoc_str "status" n);
                                      nr_path = path;
                                      nr_deps = deps;
                                      nr_script = assoc_str "script" n;
                                      nr_script_hash = assoc_str "script_hash" n;
                                      nr_duration = assoc_float "duration" n;
                                      nr_foreign_meta = foreign_meta;
                                    })
                           | _ -> None
                         ) nodes
                       in
                       (Some log_name, records)
                   | _ -> (Some log_name, []))
              | _ -> (Some log_name, [])
            with Yojson.Json_error _ -> (Some log_name, [])))

let extract_intents_from_file path : intent_record list =
  match read_file_opt path with
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
               Some { ir_file = path; ir_fields = fields }
           | _ -> None
         ) all_exprs
       with _ -> [])

let collect_intents ~dir ?file () =
  match file with
  | Some f -> extract_intents_from_file f
  | None ->
      let src_dir = Filename.concat dir "src" in
      let candidates =
        try
          if Sys.file_exists src_dir && Sys.is_directory src_dir then
            Array.to_list (Sys.readdir src_dir)
            |> List.filter (fun f -> String.ends_with ~suffix:".t" f)
            |> List.sort String.compare
            |> List.map (Filename.concat src_dir)
          else []
        with Sys_error _ -> []
      in
      List.concat_map extract_intents_from_file candidates

let opt_str_json = function Some s -> `String s | None -> `Null

let to_native_json ~project ~flake_inputs ~build_log ~nodes ~intents : Yojson.Safe.t =
  let flake_json =
    List.map (fun fi ->
      `Assoc [
        ("name", `String fi.fi_name);
        ("type", opt_str_json fi.fi_type);
        ("owner", opt_str_json fi.fi_owner);
        ("repo", opt_str_json fi.fi_repo);
        ("rev", opt_str_json fi.fi_rev);
        ("nar_hash", opt_str_json fi.fi_nar_hash);
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
      ("r_packages", `List (List.map (fun s -> `String s) project.pi_r_pkgs));
      ("python_packages", `List (List.map (fun s -> `String s) project.pi_py_pkgs));
      ("julia_packages", `List (List.map (fun s -> `String s) project.pi_jl_pkgs));
      ("additional_tools", `List (List.map (fun s -> `String s) project.pi_tools));
    ]);
    ("build_log", opt_str_json build_log);
    ("flake_inputs", `List flake_json);
    ("nodes", `List nodes_json);
    ("intents", `List intents_json);
  ]

let to_ro_crate_json ~project ~flake_inputs ~build_log ~nodes ~intents : Yojson.Safe.t =
  let input_ids = List.map (fun fi -> `Assoc [("@id", `String ("#flake-" ^ fi.fi_name))]) flake_inputs in
  let node_ids = List.map (fun nr -> `Assoc [("@id", `String ("#node-" ^ nr.nr_name))]) nodes in
  let root_desc =
    let intent_notes =
      List.concat_map (fun ir ->
        List.map (fun (k, v) -> Printf.sprintf "%s: %s" k v) ir.ir_fields
      ) intents
    in
    match project.pi_description, intent_notes with
    | "", [] -> "Reproducible T language analysis pipeline"
    | d, [] -> d
    | "", notes -> String.concat "; " notes
    | d, notes -> d ^ " — " ^ String.concat "; " notes
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
      ("hasPart", `List (input_ids @ node_ids));
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
        ) [("type", fi.fi_type); ("owner", fi.fi_owner); ("repo", fi.fi_repo); ("rev", fi.fi_rev); ("narHash", fi.fi_nar_hash)]
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
      (match nr.nr_foreign_meta with
       | Some m -> props := !props @ [`Assoc [("@type", `String "PropertyValue"); ("name", `String "foreignMeta"); ("value", m)]]
       | None -> ());
      `Assoc [
        ("@id", `String ("#node-" ^ nr.nr_name));
        ("@type", `String "File");
        ("name", `String nr.nr_name);
        ("isBasedOn", `List (List.map (fun d -> `Assoc [("@id", `String ("#node-" ^ d))]) nr.nr_deps));
        ("additionalProperty", `List !props);
      ]
    ) nodes
  in
  `Assoc [
    ("@context", `String "https://w3id.org/ro/crate/1.1/context");
    ("@graph", `List (metadata_descriptor :: root_dataset :: flake_entities @ node_entities));
  ]

let to_sbom_json ~project ~flake_inputs ~nodes : Yojson.Safe.t =
  let mk_pkg_component ecosystem name =
    `Assoc [
      ("type", `String "library");
      ("bom-ref", `String (Printf.sprintf "pkg:%s/%s" ecosystem name));
      ("name", `String name);
      ("purl", `String (Printf.sprintf "pkg:%s/%s" ecosystem name));
    ]
  in
  let flake_components =
    List.map (fun fi ->
      let ver = Option.value ~default:"locked" fi.fi_rev in
      let hashes =
        match fi.fi_nar_hash with
        | Some h -> [("hashes", `List [`Assoc [("alg", `String "SHA-256"); ("content", `String h)]])]
        | None -> []
      in
      `Assoc ([
        ("type", `String "library");
        ("bom-ref", `String ("nix:" ^ fi.fi_name));
        ("name", `String fi.fi_name);
        ("version", `String ver);
      ] @ hashes)
    ) flake_inputs
  in
  let pkg_components =
    List.map (mk_pkg_component "cran") project.pi_r_pkgs
    @ List.map (mk_pkg_component "pypi") project.pi_py_pkgs
    @ List.map (mk_pkg_component "julia") project.pi_jl_pkgs
    @ List.map (mk_pkg_component "nix") project.pi_tools
  in
  let node_deps =
    List.map (fun nr ->
      `Assoc [
        ("ref", `String ("node:" ^ nr.nr_name));
        ("dependsOn", `List (List.map (fun d -> `String ("node:" ^ d)) nr.nr_deps));
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
    ("components", `List (flake_components @ pkg_components));
    ("dependencies", `List node_deps);
  ]

let generate ?(dir=".") ?file ~format () : (string, string) result =
  let fmt = String.lowercase_ascii (String.trim format) in
  if fmt <> "ro-crate" && fmt <> "sbom" && fmt <> "json" then
    Error (Printf.sprintf "Unknown provenance format \"%s\". Supported formats: ro-crate, sbom, json." format)
  else begin
    let project = read_project_info dir in
    let flake_inputs = read_flake_lock dir in
    let (build_log, nodes) = read_latest_nodes dir in
    let intents = collect_intents ~dir ?file () in
    let json =
      match fmt with
      | "ro-crate" -> to_ro_crate_json ~project ~flake_inputs ~build_log ~nodes ~intents
      | "sbom" -> to_sbom_json ~project ~flake_inputs ~nodes
      | _ -> to_native_json ~project ~flake_inputs ~build_log ~nodes ~intents
    in
    Ok (Yojson.Safe.pretty_to_string json ^ "\n")
  end

let write_bundle ?(dir=".") ?file ?output ~format () : (string, string) result =
  match generate ~dir ?file ~format () with
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
