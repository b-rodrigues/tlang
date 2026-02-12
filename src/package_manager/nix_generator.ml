(* src/package_manager/nix_generator.ml *)
(* Generate and update flake.nix files from T package dependencies *)

open Package_types

(** Convert a git URL like "https://github.com/user/repo" to a flake input
    like "github:user/repo/tag".
    Supports github.com and gitlab.com URLs. *)
let git_url_to_flake_input (dep : dependency) : (string, string) result =
  let url = dep.git_url in
  let tag = dep.tag in
  (* Strip trailing .git if present *)
  let url = if String.length url > 4 && String.sub url (String.length url - 4) 4 = ".git"
            then String.sub url 0 (String.length url - 4) else url in
  (* Try to parse github.com URLs *)
  let try_prefix prefix scheme =
    let plen = String.length prefix in
    if String.length url >= plen && String.sub url 0 plen = prefix then
      let path = String.sub url plen (String.length url - plen) in
      (* Strip trailing / if present *)
      let path = if String.length path > 0 && path.[String.length path - 1] = '/'
                 then String.sub path 0 (String.length path - 1) else path in
      Some (Printf.sprintf "%s:%s/%s" scheme path tag)
    else None
  in
  match try_prefix "https://github.com/" "github" with
  | Some input -> Ok input
  | None ->
  match try_prefix "https://gitlab.com/" "gitlab" with
  | Some input -> Ok input
  | None ->
    (* For other URLs, use git+url *)
    Ok (Printf.sprintf "git+%s?ref=%s" url tag)

(** Nix-safe identifier: replace hyphens with hyphens (they're valid in Nix),
    but ensure it doesn't start with a digit *)
let nix_safe_name name =
  if String.length name > 0 && name.[0] >= '0' && name.[0] <= '9'
  then "_" ^ name
  else name

(** Generate a complete project flake.nix from dependencies *)
let generate_project_flake
    ~(project_name : string)
    ~(nixpkgs_date : string)
    ~(t_version : string)
    ~(deps : dependency list) : string =
  let buf = Buffer.create 2048 in
  (* Inputs section *)
  let dep_input_names = List.map (fun d -> nix_safe_name d.dep_name) deps in
  let all_output_args =
    ["self"; "nixpkgs"; "flake-utils"; "t-lang"] @ dep_input_names in
  Buffer.add_string buf "{\n";
  Printf.bprintf buf "  description = \"%s — a T data analysis project\";\n\n"
    project_name;
  Buffer.add_string buf "  inputs = {\n";
  Printf.bprintf buf "    nixpkgs.url = \"github:rstats-on-nix/nixpkgs/%s\";\n"
    nixpkgs_date;
  Buffer.add_string buf "    flake-utils.url = \"github:numtide/flake-utils\";\n";
  Printf.bprintf buf "    t-lang.url = \"github:b-rodrigues/tlang/v%s\";\n"
    t_version;
  if deps <> [] then begin
    Buffer.add_string buf "\n";
    Buffer.add_string buf "    # T packages — synced from tproject.toml by 't update'\n";
    List.iter (fun dep ->
      match git_url_to_flake_input dep with
      | Ok input ->
        Printf.bprintf buf "    %s.url = \"%s\";\n"
          (nix_safe_name dep.dep_name) input
      | Error _ -> ()
    ) deps
  end;
  Buffer.add_string buf "  };\n\n";
  (* nixConfig *)
  Buffer.add_string buf "  nixConfig = {\n";
  Buffer.add_string buf "    extra-substituters = [\n";
  Buffer.add_string buf "      \"https://rstats-on-nix.cachix.org\"\n";
  Buffer.add_string buf "    ];\n";
  Buffer.add_string buf "    extra-trusted-public-keys = [\n";
  Buffer.add_string buf "      \"rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0=\"\n";
  Buffer.add_string buf "    ];\n";
  Buffer.add_string buf "  };\n\n";
  (* Outputs *)
  Printf.bprintf buf "  outputs = { %s }:\n"
    (String.concat ", " all_output_args);
  Buffer.add_string buf "    flake-utils.lib.eachDefaultSystem (system:\n";
  Buffer.add_string buf "      let\n";
  Buffer.add_string buf "        pkgs = nixpkgs.legacyPackages.${system};\n";
  if deps <> [] then begin
    Buffer.add_string buf "\n";
    Buffer.add_string buf "        # T package dependencies (from tproject.toml)\n";
    Buffer.add_string buf "        tPackages = [\n";
    List.iter (fun dep ->
      Printf.bprintf buf "          %s.packages.${system}.default\n"
        (nix_safe_name dep.dep_name)
    ) deps;
    Buffer.add_string buf "        ];\n"
  end;
  Buffer.add_string buf "      in\n";
  Buffer.add_string buf "      {\n";
  Buffer.add_string buf "        devShells.default = pkgs.mkShell {\n";
  Buffer.add_string buf "          buildInputs = [\n";
  Buffer.add_string buf "            t-lang.packages.${system}.default\n";
  if deps <> [] then
    Buffer.add_string buf "          ] ++ tPackages;\n"
  else
    Buffer.add_string buf "          ];\n";
  Buffer.add_string buf "\n";
  Buffer.add_string buf "          shellHook = ''\n";
  Printf.bprintf buf "            echo \"==================================================\"\n";
  Printf.bprintf buf "            echo \"T Project: %s\"\n" project_name;
  Printf.bprintf buf "            echo \"==================================================\"\n";
  Buffer.add_string buf "            echo \"\"\n";
  Buffer.add_string buf "            echo \"Available commands:\"\n";
  Buffer.add_string buf "            echo \"  t repl              - Start T REPL\"\n";
  Buffer.add_string buf "            echo \"  t run <file>        - Run a T file\"\n";
  Buffer.add_string buf "            echo \"  t test              - Run tests\"\n";
  Buffer.add_string buf "            echo \"\"\n";
  Buffer.add_string buf "          '';\n";
  Buffer.add_string buf "        };\n";
  Buffer.add_string buf "      }\n";
  Buffer.add_string buf "    );\n";
  Buffer.add_string buf "}\n";
  Buffer.contents buf

(** Generate a complete package flake.nix from dependencies *)
let generate_package_flake
    ~(package_name : string)
    ~(package_version : string)
    ~(nixpkgs_date : string)
    ~(t_version : string)
    ~(deps : dependency list) : string =
  let buf = Buffer.create 2048 in
  let dep_input_names = List.map (fun d -> nix_safe_name d.dep_name) deps in
  let all_output_args =
    ["self"; "nixpkgs"; "flake-utils"; "t-lang"] @ dep_input_names in
  Buffer.add_string buf "{\n";
  Printf.bprintf buf "  description = \"%s — a T package\";\n\n"
    package_name;
  Buffer.add_string buf "  inputs = {\n";
  Printf.bprintf buf "    nixpkgs.url = \"github:rstats-on-nix/nixpkgs/%s\";\n"
    nixpkgs_date;
  Buffer.add_string buf "    flake-utils.url = \"github:numtide/flake-utils\";\n";
  Printf.bprintf buf "    t-lang.url = \"github:b-rodrigues/tlang/v%s\";\n"
    t_version;
  if deps <> [] then begin
    Buffer.add_string buf "\n";
    Buffer.add_string buf "    # Package dependencies — synced from DESCRIPTION.toml by 't update'\n";
    List.iter (fun dep ->
      match git_url_to_flake_input dep with
      | Ok input ->
        Printf.bprintf buf "    %s.url = \"%s\";\n"
          (nix_safe_name dep.dep_name) input
      | Error _ -> ()
    ) deps
  end;
  Buffer.add_string buf "  };\n\n";
  (* Outputs *)
  Printf.bprintf buf "  outputs = { %s }:\n"
    (String.concat ", " all_output_args);
  Buffer.add_string buf "    flake-utils.lib.eachDefaultSystem (system:\n";
  Buffer.add_string buf "      let\n";
  Buffer.add_string buf "        pkgs = nixpkgs.legacyPackages.${system};\n";
  Buffer.add_string buf "      in\n";
  Buffer.add_string buf "      {\n";
  (* packages.default *)
  Buffer.add_string buf "        packages.default = pkgs.stdenv.mkDerivation {\n";
  Printf.bprintf buf "          pname = \"t-%s\";\n" package_name;
  Printf.bprintf buf "          version = \"%s\";\n" package_version;
  Buffer.add_string buf "          src = ./.;\n\n";
  Buffer.add_string buf "          buildInputs = [\n";
  Buffer.add_string buf "            t-lang.packages.${system}.default\n";
  List.iter (fun dep ->
    Printf.bprintf buf "            %s.packages.${system}.default\n"
      (nix_safe_name dep.dep_name)
  ) deps;
  Buffer.add_string buf "          ];\n\n";
  Buffer.add_string buf "          installPhase = ''\n";
  Printf.bprintf buf "            mkdir -p $out/lib/t/packages/%s\n" package_name;
  Printf.bprintf buf "            cp -r src/* $out/lib/t/packages/%s/\n" package_name;
  Buffer.add_string buf "          '';\n\n";
  Buffer.add_string buf "          meta = {\n";
  Printf.bprintf buf "            description = \"%s — a T package\";\n" package_name;
  Buffer.add_string buf "          };\n";
  Buffer.add_string buf "        };\n\n";
  (* devShells.default *)
  Buffer.add_string buf "        devShells.default = pkgs.mkShell {\n";
  Buffer.add_string buf "          buildInputs = [\n";
  Buffer.add_string buf "            t-lang.packages.${system}.default\n";
  List.iter (fun dep ->
    Printf.bprintf buf "            %s.packages.${system}.default\n"
      (nix_safe_name dep.dep_name)
  ) deps;
  Buffer.add_string buf "          ];\n";
  Buffer.add_string buf "        };\n";
  Buffer.add_string buf "      }\n";
  Buffer.add_string buf "    );\n";
  Buffer.add_string buf "}\n";
  Buffer.contents buf

(** Update a flake.nix file in-place or create a new one.
    Backs up the original to flake.nix.bak if it exists.
    [kind] is either `Project` or `Package`. *)
type flake_kind = Project | Package

let install_flake
    ~(kind : flake_kind)
    ~(name : string)
    ~(version : string)
    ~(nixpkgs_date : string)
    ~(t_version : string)
    ~(deps : dependency list)
    ~(dir : string)
    ~(dry_run : bool) : (string, string) result =
  let flake_path = Filename.concat dir "flake.nix" in
  let content = match kind with
    | Project ->
      generate_project_flake ~project_name:name ~nixpkgs_date ~t_version ~deps
    | Package ->
      generate_package_flake ~package_name:name ~package_version:version
        ~nixpkgs_date ~t_version ~deps
  in
  if dry_run then begin
    Printf.printf "=== Dry run: flake.nix would be written to %s ===\n\n" flake_path;
    Printf.printf "%s\n" content;
    Ok content
  end else begin
    (* Backup existing flake.nix *)
    (if Sys.file_exists flake_path then begin
      let bak = flake_path ^ ".bak" in
      let ch = open_in flake_path in
      let old = really_input_string ch (in_channel_length ch) in
      close_in ch;
      let ch_out = open_out bak in
      output_string ch_out old;
      close_out ch_out
    end);
    (* Write new flake.nix *)
    let ch = open_out flake_path in
    output_string ch content;
    close_out ch;
    Ok content
  end
