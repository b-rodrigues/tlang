# Specification: Lazy Pipeline Evaluation for Cross-Pipeline Dependencies

## The Problem: Eager Evaluation Flaw
Current T pipelines (`pipeline { ... }` blocks) attempt to evaluate T-runtime nodes immediately during the definition phase. This creates a "Name Resolution Deadlock" when composing pipelines programmatically:

1.  **Direct Reference**: If a node in `pipeline_A` references a node in `pipeline_B` before they are combined via `union()`, the T evaluator throws a `NameError` because the dependency is not yet in scope.
2.  **Proxy Interference**: If a proxy variable is provided in the outer environment to satisfy the name lookup, the evaluator assumes it is a standard variable rather than a node dependency. It then tries to run the node command immediately, leading to type errors (e.g., calling `mutate` on a Node object instead of a DataFrame).

## Current Workaround: The Dependency Proxy Pattern
Users must currently use a "placeholder and filter" pattern to safely define cross-pipeline T dependencies:

```t
-- Workaround required in version <= 0.51.x
extension = pipeline {
  -- 1. Declare a noop placeholder to satisfy the lexer/evaluator
  upstream_node = node(noop = true)
  
  -- 2. Define the dependent node using RawCode to defer execution
  downstream_node = node(
    command = <{ upstream_node |> mutate(...) }>,
    runtime = T
  )
}

-- 3. Filter out placeholder while preserving the dependency link
extension_clean = extension |> filter_node($name != "upstream_node")

-- 4. Union to resolve the reference
final_p = union(base_p, extension_clean)
```

## Ideal Behavior (Goal)
The `pipeline` evaluator should be modified to be **naming-aware and lazier**. If a name lookup fails during the evaluation of a T node, the engine should:
1.  Verify if the name appears as a free variable in the node's command.
2.  If so, automatically treat it as a **cross-pipeline dependency**.
3.  Defer the node evaluation (marking it as `<unbuilt>`) instead of failing.
4.  Allow `union()` or `chain()` to satisfy the dependency later.

### Proposed "Ideal" Code:
```t
-- How dynamic extension SHOULD look
extension = pipeline {
  extra_step = (final_status |> mutate($msg = "Clean syntax!"))
}

-- The union() operator should handle the wiring automatically
final_p = union(modified_p, extension)
```

## Implementation Notes
To implement this, the `eval_or_defer` function in `src/eval.ml` should catch `NameError` exceptions during the T node execution phase and return a `VComputedNode` wrap-around for the "unresolved" reference. The `p_deps` calculation must also be updated to ensure these "dangling" names are preserved in the pipeline metadata.

### Constraints & Compatibility
The lazy resolution mechanism must not interfere with T's other static analysis features:
1.  **Metadata Preservation**: Even when a node's evaluation is deferred, its metadata (runtime, `serializer`, `deserializer`, `noop` status) must still be parsed and stored in the `VPipeline` object. This ensures that `inspect_pipeline` and other tools remain accurate.
2.  **Serializer Compatibility**: T performs compatibility checks between producer serializers and consumer deserializers during the `build_pipeline` phase. By correctly adding the unresolved name to `p_deps`, the builder can still perform these checks once the pipelines are combined and the reference is satisfied.
3.  **Environment Integrity**: Deferral is triggered based on a lexical approximation of cross-pipeline dependencies, currently implemented using the set of free variables in the node's command. This heuristic may include identifiers in function position and can therefore treat some ordinary naming errors or typos as external dependencies, deferring them instead of immediately raising a `NameError`. To mitigate this, deferral for the `None` (missing from environment) case is further restricted to only names that are known pipeline nodes within the current pipeline block, ensuring function-call identifiers do not cause silent deferral. A more precise analysis — for example, distinguishing data-node references from expected functions and globals — would be required in the future to fully enforce this constraint for external cross-pipeline references as well.
