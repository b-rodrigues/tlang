{
  description = "T — A Functional Language for Tabular Data";

  inputs = {
    nixpkgs.url = "github:rstats-on-nix/nixpkgs/2026-03-05";
    flake-utils.url = "github:numtide/flake-utils";
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

  outputs = { self, nixpkgs, flake-utils }:
    # This function creates the outputs for common system architectures
    # (x86_64-linux, aarch64-darwin, etc.)
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Use the Nix packages for the specified system
        pkgs = nixpkgs.legacyPackages.${system};



        # Build R with specific packages
        R-with-packages = pkgs.rWrapper.override {
          packages = with pkgs.rPackages; [
            dplyr
            readr
            testthat
            stringr
            tidyr
            purrr
            broom
            jsonlite
            arrow
            r2pmml
            faraway
            MASS
            forcats
          ];
        };

        python-with-packages = pkgs.python314.withPackages (p: with p; [
          pandas
          pyarrow
          scikit-learn
          sklearn2pmml
          statsmodels
        ]);

        # Pin a specific version of OCaml for reproducibility.
        ocamlVersion = pkgs.ocaml-ng.ocamlPackages_5_4;


        # Build the T language executable
        t-lang = pkgs.stdenv.mkDerivation {
          pname = "t-lang";
          version = "0.5.0-alpha";

          src = ./.;

          nativeBuildInputs = [
            ocamlVersion.ocaml
            ocamlVersion.findlib
            pkgs.dune_3
            ocamlVersion.menhir
            # pkg-config — resolves C library flags for arrow-glib, gobject, glib
            pkgs.pkg-config
            pkgs.makeWrapper
            pkgs.autoPatchelfHook
          ];

          buildInputs = [
            ocamlVersion.menhirLib
            # linenoise — lightweight readline alternative for REPL line editing and history
            ocamlVersion.linenoise
            # otoml — TOML parsing library for package management (DESCRIPTION.toml, tproject.toml)
            ocamlVersion.otoml
            ocamlVersion.xmlm
            ocamlVersion.lsp
            ocamlVersion.jsonrpc
            # Arrow C++ — provides arrow.pc that arrow-glib depends on
            pkgs.arrow-cpp
            # Arrow C GLib — Apache Arrow columnar data library
            # Provides GArrowTable, GArrowCSVReader, GArrowCompute
            pkgs.arrow-glib
            # GLib/GObject — arrow-glib.h includes <glib-object.h> from GLib.
            # Must be listed explicitly so pkg-config can resolve gobject-2.0
            # and glib-2.0, and the compiler can find their headers.
            pkgs.glib
            pkgs.glib.dev
            # Owl — OCaml numerical library for linear algebra and statistics
            # Used by Arrow-Owl bridge for matrix operations in lm(), cor()
            # ocamlVersion.owl
            pkgs.jpmml-statsmodels
          ];

          buildPhase = ''
            export PKG_CONFIG_PATH="${pkgs.arrow-cpp}/lib/pkgconfig:${pkgs.glib.dev}/lib/pkgconfig:${pkgs.arrow-glib}/lib/pkgconfig:$PKG_CONFIG_PATH"
            dune build src/repl.exe src/lsp_server.exe
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp _build/default/src/repl.exe $out/bin/.t-unwrapped
            cp _build/default/src/lsp_server.exe $out/bin/.t-lsp-unwrapped
            
            makeWrapper $out/bin/.t-unwrapped $out/bin/t \
              --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath [ pkgs.arrow-glib pkgs.glib pkgs.arrow-cpp ]}" \
              --set T_JPMML_STATSMODELS_JAR "${pkgs.jpmml-statsmodels}/share/java/jpmml-statsmodels.jar"
              
            makeWrapper $out/bin/.t-lsp-unwrapped $out/bin/t-lsp \
              --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath [ pkgs.arrow-glib pkgs.glib pkgs.arrow-cpp ]}"
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

            # Lightweight readline alternative for REPL line editing and history
            ocamlVersion.linenoise

            # TOML parsing library for package management
            ocamlVersion.otoml
            ocamlVersion.xmlm
            ocamlVersion.lsp
            ocamlVersion.jsonrpc

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
            ocamlVersion.ocamlformat-rpc-lib

            # Markdown to HTML compiler
            pkgs.pandoc

            # 3. Arrow C GLib — Apache Arrow columnar data library
            # -------------------------------------------------------
            # Arrow C++ — provides arrow.pc that arrow-glib depends on
            pkgs.arrow-cpp
            # Required for Arrow-backed DataFrame operations.
            pkgs.arrow-glib
            # GLib/GObject — arrow-glib.h includes <glib-object.h> from GLib.
            pkgs.glib
            pkgs.glib.dev
            pkgs.pkg-config

            # 4. Owl — OCaml numerical library (OPTIONAL)
            # -------------------------------------------------------
            # Provides matrix operations, linear algebra (BLAS/LAPACK),
            # and statistical functions. Used by Arrow-Owl bridge for
            # optimized computation in lm(), cor(), and future ML ops.
            # Uncomment when owl is available in your OCaml package set:
            # ocamlVersion.owl

            # 5. R and Python environments for testing
            R-with-packages
            python-with-packages
            pkgs.actionlint
            pkgs.shellcheck
            pkgs.jpmml-statsmodels
            pkgs.jre
          ];

          shellHook = ''
            if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
              export TLANG_REPO_ROOT="$repo_root"
            elif [[ -f "$PWD/dune-project" ]]; then
              export TLANG_REPO_ROOT="$PWD"
            fi
            export TLANG_DEV_BIN="$(mktemp -d "${TMPDIR:-/tmp}/tlang-shell-bin.XXXXXX")"
            trap 'rm -rf "$TLANG_DEV_BIN"' EXIT
            cat > "$TLANG_DEV_BIN/t" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

repo_root="${TLANG_REPO_ROOT:-}"

if [[ -z "$repo_root" || ! -f "$repo_root/dune-project" ]]; then
  if command -v git >/dev/null 2>&1; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  fi
fi

if [[ -z "$repo_root" || ! -f "$repo_root/dune-project" ]]; then
  echo "Unable to locate the T repository root for the dev-shell 't' wrapper." >&2
  exit 1
fi

exec dune exec --root "$repo_root" src/repl.exe -- "$@"
EOF
            chmod +x "$TLANG_DEV_BIN/t"
            export PATH="$TLANG_DEV_BIN:$PATH"

            echo "═══════════════════════════════════════════════"
            echo "T Language Development Environment"
            echo "═══════════════════════════════════════════════"
            echo ""
            echo "Available commands:"
            echo "  dune build           - Build the project"
            echo "  t                    - Start the T CLI via the current dev shell"
            echo "  t repl               - Start REPL explicitly"
            echo "  t run file.t         - Run a T file"
            echo "  t --help             - Show CLI help"
            echo "  dune test            - Run tests"
            echo "  dune clean           - Clean build artifacts"
            echo "  R                    - Launch R console"
            echo ""
            echo "Golden tests:"
            echo "  Rscript tests/golden/generate_datasets.R       - Generate test data"
            echo "  Rscript tests/golden/generate_expected.R       - Generate dplyr outputs"
            echo "  Rscript tests/golden/generate_expected_stats.R - Generate stats outputs"
            echo ""
            echo "Quick start: t"
            echo ""
          '';
        };
      }
    );
}
