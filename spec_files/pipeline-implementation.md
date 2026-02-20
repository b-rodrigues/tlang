# T Pipeline Compilation with Nix
*(Design Document)*

## 1. Overview and Motivation

T is designed to be a reproducible-first and pipeline-first language. Currently, pipelines execute sequentially and dynamically within an interactive T session (as detailed in `docs/pipeline_tutorial.md`). However, for non-interactive analysis, heavy data-crunching, and strict reproducibility, we need a robust build orchestration engine.

Taking inspiration from the **`rixpress`** R package, we will leverage **Nix** as the underlying execution engine for T pipelines. By transcompiling a T pipeline into a Nix derivation graph (`pipeline.nix`), we gain several powerful capabilities:

- **Hermetic Execution**: Each pipeline node runs in total isolation.
- **Content-addressable Caching**: Nix automatically caches intermediate results (in `/nix/store/`). If node `B`'s logic changes, only `B` and its downstream descendents re-execute.
- **Language-Agnostic Orchestration**: Gives us the future flexibility to integrate other languages (Python, R) seamlessly, just like `rixpress` does with `rxp_py()` and `rxp_r()`.

## 2. User Experience (UX)

The user writes a standard T pipeline script (`analysis.t`):

```t
p = pipeline {
  raw_data = read_csv("sales.csv")
  filtered = filter(raw_data, $amount > 100)
  summary = summarize(filtered, $total = sum($amount))
}
```

Instead of running it interactively to evaluate everything in-memory, the user can now leverage T's new pipeline built-ins directly from within the `t` REPL or scripts:

```t
-- Builds pipeline.nix under the hood and executes nix-build
build_pipeline(p)

-- Read the artifact back from the Nix store cache into an object
s = read_node("summary")

-- Lazily load the node variable 'summary' directly into the environment
load_node("summary")
```

The CLI tool will also provide equivalent proxy commands for external orchestration:
- `t pipeline build analysis.t`
- `t pipeline read summary`

## 3. Implementation Details

We will generate a `pipeline.nix` file that maps 1-to-1 with the pipeline's DAG.

### 3.1 Mapping T Nodes to Derivations

In **`rixpress`**, the pipeline is built from an R `list()` containing explicit node factory calls like `rxp_r()`, `rxp_py()`, etc., which makes it easy to assemble derivations.

In **T**, the language's native `pipeline { ... }` block provides an even cleaner design! The T parser already constructs a strict Abstract Syntax Tree (AST) where every assignment (e.g., `summary = summarize(...)`) is captured as an isolated node *before* it gets evaluated.
Because `p` encapsulates its own AST dependency graph, `build_pipeline(p)` simply iterates over the node graph inside `p`. By default, it transpiles every T assignment into an isolated Nix derivation.

*(For future Polyglot support (Python, R, Julia), we could easily extend this by adding functions like `py_node("...")` into T's base library to serve as an explicit derivation typing hook inside the `pipeline { ... }` block).*

For a standard T node like `summary = summarize(filtered, $total = sum($amount))`, `t` will generate a derivation snippet inside `pipeline.nix`:

```nix
  summary = stdenv.mkDerivation {
    name = "summary";
    # The Nix environment, typically pointing to the project's default.nix
    buildInputs = [ t_lang_env upstream_derivation_filtered ];

    buildCommand = ''
      # 1. Provide the upstream dependency paths via environment variables
      export T_NODE_filtered=${filtered}

      # 2. Generate a temporary T script that evaluates only this node
      cat << 'EOF' > node_script.t
      -- Load dependencies from upstream derivations
      filtered = deserialize(os.getenv("T_NODE_filtered") + "/artifact.tobj")
      
      -- Execute the node expression
      summary = summarize(filtered, $total = sum($amount))
      
      -- Serialize the output
      serialize(summary, "$out/artifact.tobj")
      EOF

      # 3. Execute the script using T
      mkdir -p $out
      t run node_script.t
    '';
  };
```

### 3.2 Serialization and Deserialization (Encoders/Decoders)

Like in `rixpress` where data is serialized between Python, R, and Julia, T needs a mechanism to pass state between derivations. 

- **DataFrames**: Use Arrow IPC format for zero-copy deserialization.
- **Standard structures** (Int, List, Dict, AST models): Use an internal binary serialization format (`.tobj`), or fall back to JSON.
- The functions `serialize(obj, path)` and `deserialize(path)` will need to be added to T's standard Base or System package.

### 3.3 The Final Pipeline Derivation

At the end of `pipeline.nix`, a target derivation collects the entire graph so that running `nix-build` evaluates all necessary paths:

```nix
  pipeline_output = stdenv.mkDerivation {
    name = "pipeline_output";
    buildInputs = [ raw_data filtered summary ];
    buildCommand = ''
      mkdir -p $out
      cp -r ${raw_data} $out/raw_data
      cp -r ${filtered} $out/filtered
      cp -r ${summary} $out/summary
    '';
  };
```

## 4. Analogy to `rixpress`

From `rixpress`, we borrow the following architectural concepts:
1. **Derivation Builders**: `rxp_r()` generates `makeRDerivation` templates. In T, the pipeline AST transpiler iterates the `Pipeline` object natively and generates `mkDerivation` templates.
2. **Artifact Bridging**: We decouple the steps. `build_pipeline(p)` creates `pipeline.nix` and triggers evaluation.
3. **Cache Retrieval**: Because everything is in `/nix/store`, identical computations instantly cache-hit. The `load_node("node_name")` and `read_node("node_name")` builtin T functions act seamlessly as retrieval wrappers (mirroring `rxp_load()` and `rxp_read()`) so data scientists immediately get objects back in their runtime session without thinking about Nix paths.

## 5. Development Roadmap for Pipeline Compilation

1. **AST Graph Transpiler**: Write `src/pipeline/nix_emitter.ml` to iterate over an unevaluated `Pipeline` AST object and output the `pipeline.nix` skeleton.
2. **Interactive Base Functions**: Expose `build_pipeline(p)`, `read_node(name)`, and `load_node(name)` uniformly to the REPL.
3. **Serialization Builtins**: Add `serialize()` and `deserialize()` core functions bridging standard types to `.tobj` artifacts in the Nix store.
4. **Sub-process Wrapping**: Wire `build_pipeline(p)` to safely invoke the generated `nix-build` underneath.

## 6. Lower-Level Implementation Details (OCaml)

This section maps out the concrete steps required in the T compiler's OCaml codebase.

### 6.1 AST Modifications

The pipeline graph is captured as a `VPipeline` object in `ast.ml`, which contains `pipeline_node`s. To support transpilation, we must ensure each node retains its exact string expression representation (or can be precisely unparsed back to T code).  

```ocaml
type expr =
  | EPipeline of pipeline_node list
  (* ... existing AST nodes ... *)

and pipeline_node = {
  name : string;
  body : expr;
  dependencies : string list; (* Automatically resolved by existing topo-sort *)
}
```

### 6.2 The Nix Emitter (`src/pipeline/nix_emitter.ml`)

The core engine of this feature will reside in `nix_emitter.ml`. Its primary function, `emit_pipeline (p : VPipeline) : string`, processes the nodes in topological order.

1. **Header Generation**: Outputs standard Nix boilerplate (`{ pkgs ? import <nixpkgs> {} }: let defaultPkgs = ...`).
2. **Node Traversal**: For each `pipeline_node`, it generates a `stdenv.mkDerivation`.
   - The `buildInputs` list dynamically references the names of the upstream upstream derivations using the `dependencies` list.
   - The T code representation of `node.body` is formatted into a local `node_script.t` string using a new function `Ast_unparse.unparse_expr(node.body)`.
3. **Target Assembly**: A final derivation combining all nodes is appended to the `.nix` string.

### 6.3 Executing and Mapping the Store Path (`src/eval.ml` and `src/pipeline/builder.ml`)

When a user calls `build_pipeline(p)`:
1. `eval.ml` intercepts the call, handing the `VPipeline` to `Nix_emitter.emit_pipeline`.
2. The generated string is written to a temporary or project-level `pipeline.nix`.
3. T invokes the Nix build system using a sub-process (e.g., `Unix.open_process_in`):
   ```bash
   nix-build pipeline.nix --no-out-link --print-out-paths
   ```
4. The stdout of this command provides the exact `/nix/store/...-pipeline_output` path.
5. T records this mapping in a lightweight project registry (`.t_pipeline_registry.json`), linking each `node.name` to its output sub-folder inside the store path (e.g., `{"summary": "/nix/store/.../summary/artifact.tobj"}`).

### 6.4 Serialization Engine (`src/serialization.ml`)

To move data seamlessly across process boundaries:
- We introduce `serialize(val, path)` and `deserialize(path)` bindings accessible natively in T.
- **DataFrames**: Use the existing Arrow C GLib bindings to dump the `VDataFrame` memory representation directly to IPC format.
- **Primitives (Lists, Dicts, Strings, Ints)**: Handled recursively via OCaml's `Marshal` module (writing to `.tobj` files) or a fast binary JSON format mapping purely to `Ast.value`.

### 6.5 Data Retrieval Builtins (`src/packages/core/pipeline.ml`)

Functions like `read_node(name)` and `load_node(name)` will:
1. Look up the requested `name` inside the `.t_pipeline_registry.json`.
2. Extract the absolute `/nix/store/` path.
3. Call the internal `deserialize()` logic to reconstruct the `Ast.value`.
4. Return the value to the REPL (for `read_node`), or inject it into the evaluating `Environment` block (for `load_node`).
