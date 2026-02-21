(* src/package_manager/scaffold.ml *)
(* Directory/file creation for `t init package` and `t init project` *)

open Package_types

(* --- Utility Helpers --- *)

let create_dir path =
  if not (Sys.file_exists path) then
    let rec mkdir_p dir =
      if Sys.file_exists dir then ()
      else begin
        mkdir_p (Filename.dirname dir);
        (try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
      end
    in
    mkdir_p path

let write_file path content =
  let ch = open_out path in
  output_string ch content;
  close_out ch

let git_init dir =
  let cmd = Printf.sprintf "git init %s" (Filename.quote dir) in
  let code = Sys.command cmd in
  if code <> 0 then
    Printf.eprintf "Warning: git init failed (exit code %d)\n" code

let default_tlang_tag = "v0.5.0"

(* Strip the "v" prefix from a tag to get a plain version number. *)
let strip_v_prefix tag =
  if String.starts_with ~prefix:"v" tag then
    String.sub tag 1 (String.length tag - 1)
  else
    tag

(* Validate and sanitize a tag string to ensure it only contains safe characters.
   This prevents potential code injection when the tag is used in templates.
   Only allows alphanumeric characters, dots, hyphens, and the "v" prefix. *)
let sanitize_tag tag =
  let is_safe_char c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') || c = '.' || c = '-' || c = 'v'
  in
  let rec check i =
    if i >= String.length tag then true
    else if is_safe_char tag.[i] then check (i + 1)
    else false
  in
  if check 0 then tag else default_tlang_tag

(* Parse a semantic version tag.
   This parser handles basic semver tags (vX.Y.Z or X.Y.Z) but does NOT handle
   pre-release versions (e.g., "v1.0.0-alpha") or build metadata (e.g., "v1.0.0+build123").
   Tags with hyphens or plus signs will be silently ignored.
   See https://semver.org/spec/v2.0.0.html for the full semver specification. *)
let parse_semver tag =
  let without_v =
    if String.starts_with ~prefix:"v" tag then String.sub tag 1 (String.length tag - 1)
    else tag
  in
  let parse_component s =
    let rec scan i =
      if i < String.length s && s.[i] >= '0' && s.[i] <= '9' then scan (i + 1)
      else i
    in
    let n = scan 0 in
    if n = 0 then None else int_of_string_opt (String.sub s 0 n)
  in
  match String.split_on_char '.' without_v with
  | [major; minor; patch] ->
      begin match parse_component major, parse_component minor, parse_component patch with
      | Some ma, Some mi, Some pa -> Some (ma, mi, pa)
      | _ -> None
      end
  | _ -> None

let compare_semver (a_ma, a_mi, a_pa) (b_ma, b_mi, b_pa) =
  match compare a_ma b_ma with
  | 0 ->
      begin match compare a_mi b_mi with
      | 0 -> compare a_pa b_pa
      | c -> c
      end
  | c -> c

let latest_tlang_tag () =
  let cmd = "git ls-remote --tags https://github.com/b-rodrigues/tlang.git" in
  let ic = Unix.open_process_in cmd in
  let rec read_tags acc =
    match input_line ic with
    | line ->
        begin match String.split_on_char '\t' line with
        | [_sha; refname] when String.starts_with ~prefix:"refs/tags/" refname ->
            let prefix_len = String.length "refs/tags/" in
            let tag = String.sub refname prefix_len (String.length refname - prefix_len) in
            if String.starts_with ~prefix:"v" tag && not (String.ends_with ~suffix:"^{}" tag) then
              read_tags (tag :: acc)
            else
              read_tags acc
        | _ -> read_tags acc
        end
    | exception End_of_file -> List.rev acc
  in
  let tags = read_tags [] in
  let status = Unix.close_process_in ic in
  (match status with
   | Unix.WEXITED 0 -> ()
   | Unix.WEXITED code ->
       Printf.eprintf
         "Warning: command `%s` exited with code %d; using default tlang tag %s if needed.\n%!"
         cmd code default_tlang_tag
   | Unix.WSIGNALED signal | Unix.WSTOPPED signal ->
       Printf.eprintf
         "Warning: command `%s` was terminated by signal %d; using default tlang tag %s if needed.\n%!"
         cmd signal default_tlang_tag);
  let versioned_tags =
    List.fold_left
      (fun acc tag ->
         match parse_semver tag with
         | Some semver -> (semver, tag) :: acc
         | None -> acc)
      []
      tags
  in
  match versioned_tags with
  | [] -> default_tlang_tag
  | (semver, tag) :: rest ->
      let _, latest_tag =
        List.fold_left
          (fun (best_semver, best_tag) (candidate_semver, candidate_tag) ->
             if compare_semver candidate_semver best_semver > 0 then
               (candidate_semver, candidate_tag)
             else
               (best_semver, best_tag))
          (semver, tag)
          rest
      in
      latest_tag

(* ================================================================ *)
(* Package Templates                                                *)
(* ================================================================ *)

let package_description_toml = {|[package]
name = "{{name}}"
version = "0.1.0"
description = "A brief description of what {{name}} does"
authors = ["{{author}}"]
license = "{{license}}"
homepage = ""
repository = ""

[dependencies]
# T packages this package depends on
# Format: package = { git = "repository-url", tag = "version" }

[t]
# Minimum T language version required
min_version = "{{tlang_version}}"
|}

let package_flake_nix = {|{
  description = "{{name}} — a T package";

  inputs = {
    nixpkgs.url = "github:rstats-on-nix/nixpkgs/{{nixpkgs_date}}";
    flake-utils.url = "github:numtide/flake-utils";
    t-lang.url = "github:b-rodrigues/tlang/{{tlang_tag}}";
    # Package dependencies as flake inputs
    # Add each dependency from DESCRIPTION.toml as a flake input here
  };

  outputs = { self, nixpkgs, flake-utils, t-lang }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # The package itself
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "t-{{name}}";
          version = "0.1.0";
          src = ./.;

          buildInputs = [
            # Add package dependencies here
          ];

          installPhase = ''
            mkdir -p $out/lib/t/packages/{{name}}
            cp -r src $out/lib/t/packages/{{name}}/
            if [ -d "help" ]; then
              cp -r help $out/lib/t/packages/{{name}}/
            fi
          '';

          meta = {
            description = "{{name}} — a T package";
          };
        };

        # Development shell for hacking on the package
        devShells.default = pkgs.mkShell {
          buildInputs = [
            t-lang.packages.${system}.default
            pkgs.pandoc  # For documentation generation
          ];

          shellHook = ''
            echo "=========================================="
            echo "T Package Development Environment"
            echo "Package: {{name}}"
            echo "=========================================="
            echo ""
            echo "Available commands:"
            echo "  t repl              - Start T REPL"
            echo "  t run <file>        - Run a T file"
            echo "  t test              - Run package tests"
            echo "  t doc --parse .     - Parse sources for documentation"
            echo "  t doc --generate    - Generate documentation"
            echo ""
            echo "Source files: src/"
            echo "Tests: tests/"
            echo ""
          '';
        };
      }
    );
}
|}

let package_readme = {|# {{name}}

A T package.

## Description

A brief description of what {{name}} does.

## Installation

Add the following to the `[dependencies]` section of your `tproject.toml`:

```toml
[dependencies]
{{name}} = { git = "https://github.com/username/{{name}}", tag = "v0.1.0" }
```

Then run `nix develop` to enter the environment with the package available.

## Usage

```t
-- Example usage of {{name}} functions
```

## Development

Enter the development shell:

```bash
nix develop
```

Run tests:

```bash
t test
```

## License

{{license}}
|}

let package_changelog = {|# Changelog

All notable changes to this package will be documented in this file.

## [0.1.0] - {{date}}

### Added
- Initial release
|}

let package_gitignore = {|# Build artifacts
_build/
result
*.exe

# Editor files
*~
.#*
\#*#
.merlin

# OS files
.DS_Store
Thumbs.db
|}

let package_src_example = {|-- {{name}} — main source file
--
-- Add your T functions here. Each function should include T-Doc comments
-- starting with --# to be picked up by the documentation generator.

--# Greet someone
--#
--# A placeholder function that returns a friendly greeting.
--#
--# @name greet
--# @param name :: String The name of the person to greet.
--# @return :: String A greeting message.
--# @example
--#   greet("world")
--#   -- Returns: "Hello, world!"
--#
--# @export
greet = \(name: String -> String) sprintf("Hello, %s!", name)
|}

let package_test_example = {|-- tests/test-{{name}}.t
-- Tests for {{name}}

-- Test: greet function
result = greet("world")
assert(result == "Hello, world!")
|}

(* ================================================================ *)
(* Project Templates                                                *)
(* ================================================================ *)

let project_tproject_toml = {|[project]
name = "{{name}}"
description = "A T data analysis project"

[dependencies]
# T packages this project depends on
# Format: package = { git = "repository-url", tag = "version" }
# Example:
# stats = { git = "https://github.com/t-lang/stats", tag = "v0.5.0" }

[t]
# Minimum T language version required
min_version = "{{tlang_version}}"
|}

(* project_flake_nix is generated dynamically by Nix_generator.generate_project_flake
   to ensure dependencies are declared as proper flake inputs (locked in flake.lock)
   rather than fetched via builtins.fetchGit which fails in pure evaluation mode. *)

let project_readme = {|# {{name}}

A T data analysis project.

## Getting Started

1. Enter the reproducible environment:

```bash
nix develop
```

2. Run the analysis:

```bash
t run src/pipeline.t
```

3. Start the interactive REPL:

```bash
t repl
```

## Project Structure

- `src/` — T source files
- `data/` — Input data files
- `outputs/` — Generated outputs
- `tests/` — Test files

## Dependencies

Dependencies are managed **declaratively** via `tproject.toml`.

To add a new dependency:

1. Add it to the `[dependencies]` section of `tproject.toml`:
   ```toml
   [dependencies]
   my-pkg = { git = "https://github.com/user/my-pkg", tag = "v0.1.0" }
   ```
2. Run `nix develop` — the package is automatically fetched
3. Commit `tproject.toml`

No imperative install commands — `flake.nix` reads `tproject.toml` directly.

## License

{{license}}
|}

let project_gitignore = {|# Build artifacts
_build/
result
*.exe

# Generated outputs (regenerated from source)
outputs/

# Editor files
*~
.#*
\#*#
.merlin

# OS files
.DS_Store
Thumbs.db
|}

let project_pipeline_example = {|-- {{name}} — main pipeline script
--
-- Run with: t run src/pipeline.t

-- import my_stats
-- import data_utils[read_clean, normalize]

-- p = pipeline {
--   raw = read_csv("data/dataset.csv")
--   clean = read_clean(raw)              -- uses imported function
--   normed = normalize(clean)            -- uses imported function
--   result = weighted_mean(normed.$x, normed.$w)  -- uses imported function
-- }

-- build_pipeline(p)

print("Hello from {{name}} pipeline!")
|}

(* ================================================================ *)
(* Scaffolding Logic                                                *)
(* ================================================================ *)

(* Cache the resolved tlang tag for the duration of the process to avoid
   repeated network calls to latest_tlang_tag on every scaffold operation. *)
let resolved_tlang_tag_cache : string option ref = ref None

let resolve_tlang_tag () =
  match !resolved_tlang_tag_cache with
  | Some tag -> tag
  | None ->
      let tag =
        try latest_tlang_tag () with
        | exn ->
            prerr_endline
              ("Warning: Failed to resolve latest tlang tag, using default: "
               ^ Printexc.to_string exn);
            default_tlang_tag
      in
      let sanitized_tag = sanitize_tag tag in
      resolved_tlang_tag_cache := Some sanitized_tag;
      sanitized_tag

(** Scaffold a new T package *)
let scaffold_package (opts : scaffold_options) : (unit, string) result =
  match validate_name opts.target_name with
  | Error msg -> Error msg
  | Ok _name ->
    let dir = opts.target_name in
    (* Check if directory exists *)
    if Sys.file_exists dir && not opts.force then
      Error (Printf.sprintf "Directory '%s' already exists. Use --force to overwrite." dir)
    else begin
      let tlang_tag = resolve_tlang_tag () in
      let tlang_version = strip_v_prefix tlang_tag in
      let ctx = [
        ("tlang_tag", tlang_tag);
        ("tlang_version", tlang_version)
      ] @ Template_engine.context_of_options opts in
      let sub = Template_engine.substitute ctx in
      (* Create directory structure *)
      create_dir dir;
      create_dir (Filename.concat dir "src");
      create_dir (Filename.concat dir "tests");
      create_dir (Filename.concat dir "examples");
      create_dir (Filename.concat dir "docs");
      create_dir (Filename.concat dir "docs/reference");
      create_dir (Filename.concat dir "help");
      (* Write files from templates *)
      write_file (Filename.concat dir "DESCRIPTION.toml") (sub package_description_toml);
      write_file (Filename.concat dir "flake.nix") (sub package_flake_nix);
      write_file (Filename.concat dir "README.md") (sub package_readme);
      write_file (Filename.concat dir "CHANGELOG.md") (sub package_changelog);
      write_file (Filename.concat dir "LICENSE") (Printf.sprintf "Licensed under %s\n\nSee https://spdx.org/licenses/%s.html for full text.\n" opts.license opts.license);
      write_file (Filename.concat dir ".gitignore") package_gitignore;
      write_file (Filename.concat dir "src/main.t") (sub package_src_example);
      write_file (Filename.concat dir (Printf.sprintf "tests/test-%s.t" opts.target_name)) (sub package_test_example);
      write_file (Filename.concat dir "docs/index.md") (Printf.sprintf "# %s\n\nPackage documentation.\n" opts.target_name);
      (* Git init *)
      if not opts.no_git then git_init dir;
      (* Success message *)
      Printf.printf "✓ Package '%s' created successfully!\n\n" opts.target_name;
      Printf.printf "  %s/\n" dir;
      Printf.printf "  ├── DESCRIPTION.toml\n";
      Printf.printf "  ├── flake.nix\n";
      Printf.printf "  ├── README.md\n";
      Printf.printf "  ├── CHANGELOG.md\n";
      Printf.printf "  ├── LICENSE\n";
      Printf.printf "  ├── .gitignore\n";
      Printf.printf "  ├── src/\n";
      Printf.printf "  │   └── main.t\n";
      Printf.printf "  ├── tests/\n";
      Printf.printf "  │   └── test-%s.t\n" opts.target_name;
      Printf.printf "  ├── examples/\n";
      Printf.printf "  └── docs/\n";
      Printf.printf "      └── index.md\n";
      Printf.printf "\nNext steps:\n";
      Printf.printf "  cd %s\n" dir;
      Printf.printf "  nix develop           # Enter development shell\n";
      Printf.printf "  t repl                # Start the REPL\n";
      Printf.printf "  t run src/main.t      # Run the example\n";
      Printf.printf "  t test                # Run tests\n";
      Ok ()
    end



(* ================================================================ *)
(* Interactive Prompts                                              *)
(* ================================================================ *)

let prompt_string label default =
  Printf.printf "%s [%s]: " label default;
  flush stdout;
  let line = try read_line () with End_of_file -> "" in
  if String.trim line = "" then default else String.trim line

let interactive_init ?(placeholder="my_package") default_name =
  Printf.printf "\nInitializing new T package/project...\n";
  let name = if default_name = "" then prompt_string "Name" placeholder else default_name in
  let author = prompt_string "Author" (try Sys.getenv "USER" with Not_found -> "Anonymous") in
  let license = prompt_string "License [EUPL-1.2, GPL-3.0-or-later, MIT] (visit https://spdx.org/licenses/ for all licenses)" "EUPL-1.2" in
  let t = Unix.gmtime (Unix.gettimeofday ()) in
  let today = Printf.sprintf "%04d-%02d-%02d" (1900 + t.Unix.tm_year) (t.Unix.tm_mon + 1) t.Unix.tm_mday in
  let nixpkgs_date = prompt_string "Nixpkgs date (rstats-on-nix branch)" today in
  Printf.printf "\n";
  {
    target_name = name;
    author = author;
    license = license;
    nixpkgs_date = nixpkgs_date;
    no_git = false;
    force = false;
    interactive = false; (* Already interactive *)
  }

(** Scaffold a new T project *)
let scaffold_project (opts : scaffold_options) : (unit, string) result =
  match validate_name opts.target_name with
  | Error msg -> Error msg
  | Ok _name ->
    let dir = opts.target_name in
    (* Check if directory exists *)
    if Sys.file_exists dir && not opts.force then
      Error (Printf.sprintf "Directory '%s' already exists. Use --force to overwrite." dir)
    else begin
      let tlang_tag = resolve_tlang_tag () in
      let tlang_version = strip_v_prefix tlang_tag in
      let ctx = [
        ("tlang_tag", tlang_tag);
        ("tlang_version", tlang_version)
      ] @ Template_engine.context_of_options opts in
      let sub = Template_engine.substitute ctx in
      (* Create directory structure *)
      create_dir dir;
      create_dir (Filename.concat dir "src");
      create_dir (Filename.concat dir "data");
      create_dir (Filename.concat dir "outputs");
      create_dir (Filename.concat dir "tests");
      (* Write files from templates *)
      write_file (Filename.concat dir "tproject.toml") (sub project_tproject_toml);
      let flake_content = Nix_generator.generate_project_flake
        ~project_name:opts.target_name
        ~nixpkgs_date:opts.nixpkgs_date
        ~t_version:tlang_version
        ~deps:[] in
      write_file (Filename.concat dir "flake.nix") flake_content;
      write_file (Filename.concat dir "README.md") (sub project_readme);
      write_file (Filename.concat dir ".gitignore") project_gitignore;
      write_file (Filename.concat dir "src/pipeline.t") (sub project_pipeline_example);
      (* Git init *)
      if not opts.no_git then git_init dir;
      (* Success message *)
      Printf.printf "✓ Project '%s' created successfully!\n\n" opts.target_name;
      Printf.printf "  %s/\n" dir;
      Printf.printf "  ├── tproject.toml\n";
      Printf.printf "  ├── flake.nix\n";
      Printf.printf "  ├── README.md\n";
      Printf.printf "  ├── .gitignore\n";
      Printf.printf "  ├── src/\n";
      Printf.printf "  │   └── pipeline.t\n";
      Printf.printf "  ├── data/\n";
      Printf.printf "  ├── outputs/\n";
      Printf.printf "  └── tests/\n";
      Printf.printf "\nNext steps:\n";
      Printf.printf "  cd %s\n" dir;
      Printf.printf "  nix develop           # Enter reproducible environment\n";
      Printf.printf "  t repl                # Start the REPL\n";
      Printf.printf "  t run src/pipeline.t  # Run the pipeline\n";
      Ok ()
    end

(** Parse CLI flags for init commands.
    Returns scaffold_options or an error message. *)
let parse_init_flags (args : string list) : (scaffold_options, string) result =
  let name = ref None in
  let author = ref "Your Name <email@example.com>" in
  let license = ref "EUPL-1.2" in
  let t = Unix.gmtime (Unix.gettimeofday ()) in
  let today = Printf.sprintf "%04d-%02d-%02d" (1900 + t.Unix.tm_year) (t.Unix.tm_mon + 1) t.Unix.tm_mday in
  let nixpkgs_date = ref today in
  let no_git = ref false in
  let force = ref false in
  let show_help = ref false in
  let error = ref None in
  let rec parse = function
    | [] -> ()
    | "--author" :: v :: rest -> author := v; parse rest
    | "--license" :: v :: rest -> license := v; parse rest
    | "--nixpkgs-date" :: v :: rest -> nixpkgs_date := v; parse rest
    | "--no-git" :: rest -> no_git := true; parse rest
    | "--force" :: rest -> force := true; parse rest
    | "--interactive" :: rest -> parse rest (* Handled in repl.ml mainly, but we can flag it *)
    | "--help" :: _ -> show_help := true
    | arg :: rest ->
        if String.length arg > 0 && arg.[0] = '-' then
          error := Some (Printf.sprintf "Unknown option: %s" arg)
        else begin
          (match !name with
           | None -> name := Some arg
           | Some _ -> error := Some (Printf.sprintf "Unexpected argument: %s" arg));
          parse rest
        end
  in
  parse args;
  if !show_help then
    Error "Usage: t init package|project <name> [options]\n\n\
           Options:\n\
           \  --author <name>    Author name and email (default: \"Your Name <email@example.com>\")\n\
           \  --license <id>     License identifier (default: EUPL-1.2)\n\
           \  --nixpkgs-date <YYYY-MM-DD>  Nixpkgs branch date (default: today)\n\
           \  --no-git           Skip git init\n\
           \  --force            Overwrite existing directory\n\
           \  --help             Show this help\n\
           \  --interactive      Prompt for options"
  else match !error with
  | Some msg -> Error msg
  | None ->
    match !name with
    | Some n ->
      Ok {
        target_name = n;
        author = !author;
        license = !license;
        nixpkgs_date = !nixpkgs_date;
        no_git = !no_git;
        force = !force;
        interactive = List.mem "--interactive" args;
      }
    | None ->
        if List.mem "--interactive" args then
          Ok {
            target_name = "";
            author = !author;
            license = !license;
            nixpkgs_date = !nixpkgs_date;
            no_git = !no_git;
            force = !force;
            interactive = true;
          }
        else
          Error "Missing package/project name. Usage: t init package|project <name>"
