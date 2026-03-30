{
  description = "T — A Functional Language for Tabular Data";

  inputs = {
    nixpkgs.url = "github:rstats-on-nix/nixpkgs/2026-03-29";
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
            randomForest
            xgboost
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
          xgboost
          sklearn2pmml
          statsmodels
          nbformat
          ipykernel
        ]);

        # Pin a specific version of OCaml for reproducibility.
        ocamlVersion = pkgs.ocaml-ng.ocamlPackages_5_4;


        # Build the T language executable
        t-lang = pkgs.stdenv.mkDerivation {
          pname = "t-lang";
          version = pkgs.lib.replaceStrings ["\n"] [""] (builtins.readFile ./VERSION);

          src = ./.;

          nativeBuildInputs = [
            ocamlVersion.ocaml
            ocamlVersion.findlib
            pkgs.dune_3
            ocamlVersion.menhir
            # pkg-config — resolves C library flags for arrow-glib, gobject, glib
            pkgs.pkg-config
            pkgs.makeWrapper
            ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
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
            pkgs.gettext
            # Owl — OCaml numerical library for linear algebra and statistics
            # Used by Arrow-Owl bridge for matrix operations in lm(), cor()
            # ocamlVersion.owl
            pkgs.jpmml-statsmodels
          ];

          buildPhase = ''
            export PKG_CONFIG_PATH="${pkgs.arrow-cpp}/lib/pkgconfig:${pkgs.glib.dev}/lib/pkgconfig:${pkgs.glib}/lib/pkgconfig:${pkgs.arrow-glib}/lib/pkgconfig:$PKG_CONFIG_PATH"
            export T_ARROW_CFLAGS="-I${pkgs.arrow-cpp}/include -I${pkgs.arrow-glib}/include -I${pkgs.glib.dev}/include -I${pkgs.glib.dev}/include/glib-2.0 -I${pkgs.glib.out}/lib/glib-2.0/include"
            export T_ARROW_LIBS="-L${pkgs.arrow-cpp}/lib -L${pkgs.arrow-glib}/lib -L${pkgs.glib.out}/lib -larrow -larrow-glib -lparquet -lparquet-glib -lglib-2.0 -lgobject-2.0 -lgio-2.0"
            dune build src/repl.exe src/lsp_server.exe
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp _build/default/src/repl.exe $out/bin/.t-unwrapped
            cp _build/default/src/lsp_server.exe $out/bin/.t-lsp-unwrapped
            mkdir -p $out/share/tlang/quarto
            cp -r editors/quarto/tlang/_extensions/tlang $out/share/tlang/quarto/
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

          # Pre-computed Arrow C flags — these become env vars automatically.
          # Unlike shellHook or pkg-config, mkShell attributes are always set,
          # even with `nix develop --command`. This avoids issues where a
          # system pkg-config (e.g. Homebrew) shadows the Nix one.
          T_ARROW_CFLAGS = builtins.concatStringsSep " " [
            "-I${pkgs.arrow-cpp}/include"
            "-I${pkgs.arrow-glib}/include"
            "-I${pkgs.glib.dev}/include"
            "-I${pkgs.glib.dev}/include/glib-2.0"
            "-I${pkgs.glib.out}/lib/glib-2.0/include"
          ];
          T_ARROW_LIBS = builtins.concatStringsSep " " [
            "-L${pkgs.arrow-cpp}/lib"
            "-L${pkgs.arrow-glib}/lib"
            "-L${pkgs.glib.out}/lib"
            "-larrow" "-larrow-glib"
            "-lparquet" "-lparquet-glib"
            "-lglib-2.0" "-lgobject-2.0" "-lgio-2.0"
          ];


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
            pkgs.quarto

            # 3. Arrow C GLib — Apache Arrow columnar data library
            # -------------------------------------------------------
            # Arrow C++ — provides arrow.pc that arrow-glib depends on
            pkgs.arrow-cpp
            # Required for Arrow-backed DataFrame operations.
            pkgs.arrow-glib
            # GLib/GObject — arrow-glib.h includes <glib-object.h> from GLib.
            pkgs.glib
            pkgs.glib.dev
            pkgs.gettext
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

            # 6. Local Project Binaries (Wrappers for development)
            (pkgs.writeShellScriptBin "t" ''
              repo_root="''${TLANG_REPO_ROOT:-$PWD}"
              if [[ -f "$repo_root/_build/default/src/repl.exe" ]]; then
                exec "$repo_root/_build/default/src/repl.exe" "$@"
              elif [[ -L "$repo_root/result" && -f "$repo_root/result/bin/t" ]]; then
                exec "$repo_root/result/bin/t" "$@"
              else
                echo "Error: T is not built. Please run 'dune build' first." >&2
                exit 1
              fi
            '')

            (pkgs.writeShellScriptBin "t-lsp" ''
              repo_root="''${TLANG_REPO_ROOT:-$PWD}"
              if [[ -f "$repo_root/_build/default/src/lsp_server.exe" ]]; then
                exec "$repo_root/_build/default/src/lsp_server.exe" "$@"
              elif [[ -L "$repo_root/result" && -f "$repo_root/result/bin/t-lsp" ]]; then
                exec "$repo_root/result/bin/t-lsp" "$@"
              else
                echo "Error: T LSP server is not built. Please run 'dune build src/lsp_server.exe' first." >&2
                exit 1
              fi
            '')

            # 7. Editor Extension Development
            # ------------------------------------
            pkgs.nodejs
          ];

          shellHook = ''
            export PKG_CONFIG_PATH="${pkgs.arrow-cpp}/lib/pkgconfig:${pkgs.glib.dev}/lib/pkgconfig:${pkgs.glib}/lib/pkgconfig:${pkgs.arrow-glib}/lib/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

            if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
              export TLANG_REPO_ROOT="$repo_root"
            elif [[ -f "$PWD/dune-project" ]]; then
              export TLANG_REPO_ROOT="$PWD"
            fi

            echo "═══════════════════════════════════════════════"
            echo "T Language Development Environment"
            echo "═══════════════════════════════════════════════"
            echo ""
            echo "Available commands:"
            echo "  dune build           - Build the project (REPL)"
            echo "  dune build src/lsp_server.exe - Build the LSP server"
            echo "  t                    - Run the language (fast path)"
            echo "  t-lsp                - Run the language server"
            echo "  dune test            - Run tests"
            echo ""
            echo "Quick start: dune build && t"
            echo ""
          '';
        };
      }
    );
}
