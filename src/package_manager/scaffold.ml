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
min_version = "{{t_version}}"
|}

let package_flake_nix = {|{
  description = "{{name}} — a T package";

  inputs = {
    nixpkgs.url = "github:rstats-on-nix/nixpkgs/{{nixpkgs_date}}";
    flake-utils.url = "github:numtide/flake-utils";
    t-lang.url = "github:b-rodrigues/tlang/v{{t_version}}";
    # Package dependencies as flake inputs
    # (auto-added by 't install' from DESCRIPTION.toml)
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
            t-lang.packages.${system}.default
            # Add package dependencies here
          ];

          installPhase = ''
            mkdir -p $out/lib/t/packages/{{name}}
            cp -r src/* $out/lib/t/packages/{{name}}/
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
            echo "  t document .        - Generate documentation"
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

Add the following to your `tproject.toml`:

```toml
[dependencies]
{{name}} = { git = "https://github.com/username/{{name}}", tag = "v0.1.0" }
```

Then run:

```bash
t install
```

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
-- Add your T functions here.
-- Each function should include documentation.
--
-- @doc
-- Example function
--
-- @description
-- A placeholder function that returns a greeting.
--
-- @param name A string with someone's name
-- @return A greeting string
-- @example
-- greet("world")
-- @end
greet = \(name) -> "Hello, " + name + "!"
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
min_version = "{{t_version}}"
|}

let project_flake_nix = {|{
  description = "{{name}} — a T data analysis project";

  inputs = {
    # Pin to a specific date for reproducibility
    nixpkgs.url = "github:rstats-on-nix/nixpkgs/{{nixpkgs_date}}";
    flake-utils.url = "github:numtide/flake-utils";
    t-lang.url = "github:b-rodrigues/tlang/v{{t_version}}";

    # T packages — auto-added by 't install' command from tproject.toml
  };

  # Configure cachix for R packages
  nixConfig = {
    extra-substituters = [
      "https://rstats-on-nix.cachix.org"
    ];
    extra-trusted-public-keys = [
      "rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0="
    ];
  };

  outputs = { self, nixpkgs, flake-utils, t-lang }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Collect all T package dependencies
        tPackages = [
          # (auto-populated by 't install')
        ];
      in
      {
        # Development environment
        devShells.default = pkgs.mkShell {
          buildInputs = [
            t-lang.packages.${system}.default
          ] ++ tPackages;

          shellHook = ''
            echo "=================================================="
            echo "T Project: {{name}}"
            echo "=================================================="
            echo ""
            echo "Available commands:"
            echo "  t repl              - Start T REPL"
            echo "  t run <file>        - Run a T file"
            echo "  t test              - Run tests"
            echo ""
            echo "Source files: src/"
            echo "Data: data/"
            echo "Outputs: outputs/"
            echo ""
          '';
        };
      }
    );
}
|}

let project_readme = {|# {{name}}

A T data analysis project.

## Getting Started

1. Enter the reproducible environment:

```bash
nix develop
```

2. Run the analysis:

```bash
t run src/analysis.t
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

Dependencies are declared in `tproject.toml` and pinned via `flake.lock`.

To add a new dependency:

1. Add it to `tproject.toml`
2. Run `t install`
3. Commit both `tproject.toml` and `flake.lock`

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

let project_analysis_example = {|-- {{name}} — main analysis script
--
-- Run with: t run src/analysis.t

-- Load your data
-- data = read_csv("data/dataset.csv")

-- Analyse
-- result = data |> filter($column > 0) |> summarize(mean = mean($column))

-- Save results
-- write_csv(result, "outputs/result.csv")

print("Hello from {{name}}!")
|}

(* ================================================================ *)
(* Scaffolding Logic                                                *)
(* ================================================================ *)

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
      let ctx = Template_engine.context_of_options opts in
      let sub = Template_engine.substitute ctx in
      (* Create directory structure *)
      create_dir dir;
      create_dir (Filename.concat dir "src");
      create_dir (Filename.concat dir "tests");
      create_dir (Filename.concat dir "examples");
      create_dir (Filename.concat dir "docs");
      create_dir (Filename.concat dir "docs/reference");
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
      let ctx = Template_engine.context_of_options opts in
      let sub = Template_engine.substitute ctx in
      (* Create directory structure *)
      create_dir dir;
      create_dir (Filename.concat dir "src");
      create_dir (Filename.concat dir "data");
      create_dir (Filename.concat dir "outputs");
      create_dir (Filename.concat dir "tests");
      (* Write files from templates *)
      write_file (Filename.concat dir "tproject.toml") (sub project_tproject_toml);
      write_file (Filename.concat dir "flake.nix") (sub project_flake_nix);
      write_file (Filename.concat dir "README.md") (sub project_readme);
      write_file (Filename.concat dir ".gitignore") project_gitignore;
      write_file (Filename.concat dir "src/analysis.t") (sub project_analysis_example);
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
      Printf.printf "  │   └── analysis.t\n";
      Printf.printf "  ├── data/\n";
      Printf.printf "  ├── outputs/\n";
      Printf.printf "  └── tests/\n";
      Printf.printf "\nNext steps:\n";
      Printf.printf "  cd %s\n" dir;
      Printf.printf "  nix develop           # Enter reproducible environment\n";
      Printf.printf "  t repl                # Start the REPL\n";
      Printf.printf "  t run src/analysis.t  # Run the analysis\n";
      Ok ()
    end

(** Parse CLI flags for init commands.
    Returns (name option, scaffold_options) *)
let parse_init_flags (args : string list) : (scaffold_options, string) result =
  let name = ref None in
  let author = ref "Your Name <email@example.com>" in
  let license = ref "EUPL-1.2" in
  let no_git = ref false in
  let force = ref false in
  let rec parse = function
    | [] -> ()
    | "--author" :: v :: rest -> author := v; parse rest
    | "--license" :: v :: rest -> license := v; parse rest
    | "--no-git" :: rest -> no_git := true; parse rest
    | "--force" :: rest -> force := true; parse rest
    | "--help" :: _ ->
        Printf.printf "Usage: t init package|project <name> [options]\n\n";
        Printf.printf "Options:\n";
        Printf.printf "  --author <name>    Author name and email (default: \"Your Name <email@example.com>\")\n";
        Printf.printf "  --license <id>     License identifier (default: EUPL-1.2)\n";
        Printf.printf "  --no-git           Skip git init\n";
        Printf.printf "  --force            Overwrite existing directory\n";
        Printf.printf "  --help             Show this help\n";
        exit 0
    | arg :: rest ->
        if String.length arg > 0 && arg.[0] = '-' then begin
          Printf.eprintf "Unknown option: %s\n" arg;
          exit 1
        end else begin
          (match !name with
           | None -> name := Some arg
           | Some _ -> Printf.eprintf "Unexpected argument: %s\n" arg; exit 1);
          parse rest
        end
  in
  parse args;
  match !name with
  | None -> Error "Missing package/project name. Usage: t init package|project <name>"
  | Some n ->
    Ok {
      target_name = n;
      author = !author;
      license = !license;
      no_git = !no_git;
      force = !force;
    }
