{
  description = "T — A Functional Language for Tabular Data";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    # This function creates the outputs for common system architectures
    # (x86_64-linux, aarch64-darwin, etc.)
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Use the Nix packages for the specified system
        pkgs = nixpkgs.legacyPackages.${system};

        # Pin a specific version of OCaml for reproducibility.
        # OCaml 5.1 is a modern, solid choice.
        ocamlVersion = pkgs.ocaml-ng.ocamlPackages_5_1;

        # Build the T language executable
        t-lang = pkgs.stdenv.mkDerivation {
          pname = "t-lang";
          version = "0.1.0-alpha";

          src = ./.;

          nativeBuildInputs = [
            ocamlVersion.ocaml
            ocamlVersion.findlib
            pkgs.dune_3
            ocamlVersion.menhir
          ];

          buildInputs = [
            ocamlVersion.menhirLib
          ];

          buildPhase = ''
            dune build src/repl.exe
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp _build/default/src/repl.exe $out/bin/t
            chmod +x $out/bin/t
          '';

          meta = with pkgs.lib; {
            description = "T — A Functional Language for Tabular Data";
            homepage = "https://tstats-project.org";
            license = licenses.eupl12;
            maintainers = [ ];
            platforms = platforms.unix;
          };
        };
      in
      {
        # The default package - allows `nix build` and `nix run`
        packages.default = t-lang;

        # Make it runnable with `nix run`
        apps.default = {
          type = "app";
          program = "${t-lang}/bin/t";
        };

        # This defines the development shell that `nix develop` will activate.
        devShells.default = pkgs.mkShell {

          # These are the packages that will be available in your shell.
          buildInputs = [
            # 1. Core Build Toolchain (Required)
            # ------------------------------------
            # The OCaml compiler itself
            ocamlVersion.ocaml

            # The Dune build system
            pkgs.dune_3

            # The Menhir parser generator (required by your dune file)
            ocamlVersion.menhir
            ocamlVersion.menhirLib

            # OCaml package manager - provides setup hooks for OCAMLPATH
            ocamlVersion.findlib

            # 2. Enhanced Development Tools (Highly Recommended)
            # ----------------------------------------------------
            # A powerful interactive REPL for OCaml, great for testing code snippets.
            ocamlVersion.utop

            # The OCaml Language Server for editor features like autocompletion,
            # type hints, and go-to-definition in editors like VSCode.
            ocamlVersion.ocaml-lsp

            # The standard OCaml code formatter to keep your code clean.
            ocamlVersion.ocamlformat
            # RPC version needed for Dune to run the formatter automatically.
            ocamlVersion.ocamlformat-rpc
          ];

          shellHook = ''
            echo "═══════════════════════════════════════════════"
            echo "T Language Development Environment"
            echo "═══════════════════════════════════════════════"
            echo ""
            echo "Available commands:"
            echo "  dune build           - Build the project"
            echo "  dune exec src/repl.exe - Start the T REPL"
            echo "  dune test            - Run tests"
            echo "  dune clean           - Clean build artifacts"
            echo ""
            echo "Quick start: dune exec src/repl.exe"
            echo ""
          '';
        };
      }
    );
}
