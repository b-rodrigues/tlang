# T Pipeline Demos

This page lists real-world T projects that demonstrate the power of polyglot, reproducible orchestration. Most of these demos are available in the [tstats-project/t_demos](https://github.com/tstats-project/t_demos) repository.

## Visualization & Reporting

### [Plotting & Visual Metadata Capture](plotting.html)
- **Repo**: `plotting_pipeline_t`
- **Description**: Demonstrates how T captures structural metadata from `ggplot2` (R) and `matplotlib` (Python).
- **Key Features**: Polyglot plots, metadata extraction, Nix-reproducible charts.

### [Quarto Literate Programming](literate-programming-quarto.html)
- **Repo**: `quarto_test_t`
- **Description**: Shows how to embed T pipeline results in a Quarto report.
- **Key Features**: Auto-substitution of `read_node()`, Nix-built reports.

## Statistical Modeling

### [Model Comparison: R vs Python](models.html)
- **Repo**: `model_comparison_t`
- **Description**: Compares GLM results across R and Python nodes within the same pipeline.
- **Key Features**: Concurrent R and Python environments, PMML interchange.

### [Titanic Survival](pmml_tutorial.html)
- **Repo**: `glm_titanic_t`
- **Description**: A classic statistical modeling pipeline using the Titanic dataset.
- **Key Features**: Data cleaning, logistic regression, result serialization.

## Advanced Orchestration

### [ONNX & PMML Interchange](pmml_tutorial.html)
- **Repo**: `onnx_exchange_t` / `pmml_interchange_t`
- **Description**: Moving trained models between high-level languages and T's native scoring engine.
- **Key Features**: `predict()` across language boundaries, standardized model storage.

### [Lenses & Dynamic Pipelines](lens.html)
- **Repo**: `deep_data_lenses_t` / `dynamic_pipeline_operator_t`
- **Description**: Demonstrates functional updates to immutable configurations and dynamic DAG generation.
- **Key Features**: Pipeline-as-code, functional composition.

---

## Running the Demos

To try any of these demos locally:

1.  **Clone the demos repository**:
    ```bash
    git clone https://github.com/tstats-project/t_demos
    cd t_demos/<project_name>
    ```
2.  **Bootstrap the T environment**:
    If you don't have the `t` command installed yet, use Nix to get it directly from the source repository:
    ```bash
    nix shell github:b-rodrigues/tlang
    ```
3.  **Synchronize dependencies**:
    T uses `tproject.toml` to manage dependencies. Run this to generate the project's local `flake.nix`:
    ```bash
    t update
    ```
4.  **Enter the project shell**:
    ```bash
    nix develop
    ```
5.  **Run the pipeline**:
    ```bash
    t run src/pipeline.t
    ```
