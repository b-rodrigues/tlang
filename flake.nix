{
  description = "A development environment for the T programming language";

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
      in
      {
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

            # 2. Enhanced Development Tools (Highly Recommended)
            # ----------------------------------------------------
            # A powerful interactive REPL for OCaml, great for testing code snippets.
            ocamlVersion.utop

            # The OCaml Language Server for editor features like autocompletion,
            # type hints, and go-to-definition in editors like VSCode.
            pkgs.ocaml-lsp

            # The standard OCaml code formatter to keep your code clean.
            pkgs.ocamlformat
            # RPC version needed for Dune to run the formatter automatically.
            pkgs.ocamlformat-rpc
          ];
        };
      }
    );
} 
