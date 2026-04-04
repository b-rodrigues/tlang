# GLM Support in the T Model Bridge

## 1. Motivation

Generalised Linear Models are the natural extension after OLS. The infrastructure is already in place — PMML's `<RegressionModel>` element supports link functions natively, and the enrichment pattern established for linear models applies directly. What GLMs add is:

* A **family** (the error distribution: Gaussian, Binomial, Poisson, Gamma, …)
* A **link function** (identity, logit, log, inverse, probit, cloglog, …)
* A **dispersion parameter** (estimated or fixed)
* Deviance-based goodness-of-fit in place of R²
* Coefficient tables that report **z-statistics** rather than t-statistics (because inference is asymptotic)

These differences are small relative to what already exists, but they must be handled precisely or the `summary` output will silently report the wrong thing.

---

## 2. PMML Representation

PMML encodes a GLM as a `<RegressionModel>` with a `normalizationMethod` attribute for the link. The mapping is:

| GLM link    | PMML `normalizationMethod` |
| ----------- | -------------------------- |
| identity    | `none`                     |
| logit       | `logit`                    |
| log         | `exp` (inverse of log)     |
| probit      | `probit`                   |
| cloglog     | `cloglog`                  |
| inverse     | (custom extension — see §4)|

Most families are implicit in the link choice, but we record family explicitly in a PMML `<Extension>` element to avoid ambiguity and to carry dispersion.

---

## 3. T-Side IR Extension

The existing `regression_model` record is extended:

```ocaml
type family =
  | Gaussian
  | Binomial
  | Poisson
  | Gamma
  | InverseGaussian
  | QuasiPoisson   (* dispersion estimated freely *)
  | QuasiBinomial

type link =
  | Identity
  | Logit
  | Log
  | Probit
  | Cloglog
  | Inverse
  | Sqrt

type glm_stats = {
  null_deviance       : float;
  null_deviance_df    : int;
  residual_deviance   : float;
  residual_deviance_df: int;
  dispersion          : float;     (* 1.0 for Binomial/Poisson *)
  aic                 : float;
  log_likelihood      : float;
}

type regression_model = {
  family      : family;
  link        : link;
  coefficients: (string * float) list;
  std_errors  : (string * float) list;
  z_stats     : (string * float) list;
  p_values    : (string * float) list;
  intercept   : float;
  glm_stats   : glm_stats option;  (* None for plain OLS *)
}
```

The `glm_stats` field is `None` for a plain `lm`, so existing linear model paths are unaffected.

The exported JSON extension uses snake_case field names such as
`null_deviance` and `null_deviance_df`; the dotted R summary members
`null.deviance` and `df.null` are only the source fields used to populate them.

---

## 4. Runtime Enrichment (R)

R's `glm` summary object carries everything needed. The enrichment function runs after `r2pmml` exports the base XML and injects the missing attributes before the artifact is finalised:

```r
t_export_glm <- function(fit, path) {
  # Base export via r2pmml
  r2pmml::r2pmml(fit, path)

  doc <- XML::xmlParse(path)
  root <- XML::xmlRoot(doc)

  s      <- summary(fit)
  coef_m <- s$coefficients          # matrix: Estimate, Std.Error, z/t, Pr
  fmt    <- function(x) sprintf("%.15g", x)

  # --- per-coefficient stats ---
  # r2pmml places intercept as <NumericPredictor name="(Intercept)" ...>
  for (nm in rownames(coef_m)) {
    safe <- if (nm == "(Intercept)") "\\(Intercept\\)" else nm
    xpath <- sprintf(
      "//pmml:NumericPredictor[@name='%s']", safe
    )
    nodes <- XML::getNodeSet(doc, xpath,
                             namespaces = c(pmml = "http://www.dmg.org/PMML-4_4"))
    for (nd in nodes) {
      XML::xmlAttrs(nd)[["stdError"]]   <- fmt(coef_m[nm, "Std. Error"])
      XML::xmlAttrs(nd)[["zStatistic"]] <- fmt(coef_m[nm, 3])   # col 3 = z or t
      XML::xmlAttrs(nd)[["pValue"]]     <- fmt(coef_m[nm, 4])
    }
  }

  # --- model-level GLM stats via Extension ---
  reg_node <- XML::getNodeSet(
    doc, "//pmml:RegressionModel",
    namespaces = c(pmml = "http://www.dmg.org/PMML-4_4")
  )[[1]]

  glm_ext <- XML::newXMLNode("Extension",
    attrs = list(
      name  = "GLMStats",
      value = jsonlite::toJSON(list(
        family              = family(fit)$family,
        link                = family(fit)$link,
        null_deviance       = fmt(s$null.deviance),
        null_deviance_df    = s$df.null,
        residual_deviance   = fmt(s$deviance),
        residual_deviance_df= s$df.residual,
        dispersion          = fmt(s$dispersion),
        aic                 = fmt(s$aic),
        log_likelihood      = fmt(as.numeric(logLik(fit)))
      ), auto_unbox = TRUE)
    )
  )
  XML::addChildren(reg_node, glm_ext)

  XML::saveXML(doc, file = path)
  invisible(path)
}
```

The same context-aware XPath pattern from the linear model bridge is reused. The `z/t` column (column 3 of the coefficient matrix) works for both `lm` (t) and `glm` (z) — the attribute is named `zStatistic` in both cases; `summary(model)` in T labels it appropriately based on the family field.

---

## 5. Python Runtime — statsmodels GLMs via JPMML-StatsModels

### 5.1 Overview

The Python GLM path mirrors the R path structurally. Both delegate to a JPMML-backed converter that accepts a pickle file and emits PMML. The converter for statsmodels is **JPMML-StatsModels**, a dedicated library in the same JPMML family as the `r2pmml` backend used on the R side.

The workflow is:

```
statsmodels fit → pickle → JPMML-StatsModels CLI → PMML → T enrichment (if needed)
```

Users never interact with any of these steps. `t_export_glm` orchestrates the full pipeline internally.

---

### 5.2 Supported Models

JPMML-StatsModels supports the following GLM configurations natively:

**Families:** `Binomial`, `Gaussian`, `Poisson`

**Link functions:** `identity`, `log`, `logit`

This covers the large majority of practical GLM usage. Families outside this set (Gamma, InverseGaussian, Quasi variants) are not supported on the Python path in the initial implementation — users requiring those should train in R.

---

### 5.3 Implementation

```python
import subprocess
import pickle
import tempfile
import os

def t_export_glm(results, path: str) -> str:
    """
    Export a fitted statsmodels GLM result to PMML.

    Parameters
    ----------
    results : statsmodels results object
        The return value of model.fit(). Must be a supported GLM type.
    path : str
        Destination path for the PMML file.
    """
    _assert_supported(results)

    with tempfile.TemporaryDirectory() as tmp:
        pkl_path = os.path.join(tmp, "model.pkl")
        results.save(pkl_path, remove_data=True)

        jar_path = _resolve_jpmml_statsmodels_jar()

        subprocess.run(
            [
                "java", "-jar", jar_path,
                "--pkl-input",  pkl_path,
                "--pmml-output", path,
            ],
            check=True,
            capture_output=True,
        )

    return path


def _assert_supported(results):
    import statsmodels.genmod.generalized_linear_model as glm_module

    supported_families = {"Binomial", "Gaussian", "Poisson"}
    supported_links    = {"identity", "log", "logit"}

    if hasattr(results, "family"):
        family_name = type(results.family).__name__
        link_name   = type(results.family.link).__name__.lower()

        if family_name not in supported_families:
            raise ValueError(
                f"GLM family '{family_name}' is not supported on the Python path. "
                f"Train in R to use this family."
            )
        if link_name not in supported_links:
            raise ValueError(
                f"Link function '{link_name}' is not supported on the Python path. "
                f"Train in R to use this link."
            )


def _resolve_jpmml_statsmodels_jar() -> str:
    # T's Nix derivation places the JAR at a well-known path.
    # This function reads that path from the T runtime environment.
    jar = os.environ.get("T_JPMML_STATSMODELS_JAR")
    if not jar or not os.path.exists(jar):
        raise RuntimeError(
            "JPMML-StatsModels JAR not found. "
            "Ensure the t-pmml-java derivation is present in your environment."
        )
    return jar
```

---

### 5.4 Enrichment

Before writing any enrichment code, verify the raw PMML output from JPMML-StatsModels against a real fit. Because JPMML-StatsModels is purpose-built for a library that carries full inference results, it may already emit `stdError`, `tStatistic`, and `pValue` attributes on `NumericPredictor` elements without any post-processing. The R side requires enrichment because `r2pmml` omits those attributes by default; the statsmodels side may not have the same gap.

The verification procedure:

```python
import statsmodels.api as sm
import pandas as pd

data = sm.datasets.spector.load_pandas().data
fit  = sm.GLM(
    data["GRADE"],
    sm.add_constant(data[["GPA", "TUCE", "PSI"]]),
    family = sm.families.Binomial()
).fit()

t_export_glm(fit, "/tmp/test_glm.pmml")
```

Then inspect `/tmp/test_glm.pmml` for:

```xml
<NumericPredictor name="GPA" coefficient="..." stdError="..." pValue="..."/>
```

If those attributes are present, no enrichment layer is needed on the Python path. If they are absent, apply the same post-processing pattern used on the R side, reading from `results.bse`, `results.tvalues`, and `results.pvalues` respectively.

---

### 5.5 Node API

Identical to the R path — no new syntax:

```python
logit_model = node(
    command = <{
        import statsmodels.api as sm
        fit = sm.GLM(y, X, family=sm.families.Binomial()).fit()
        t_export_glm(fit, "$out/artifact")
    }>,
    runtime = Python,
    serializer = "pmml"
)
```

---

### 5.6 Java Dependency

Both the R and Python PMML serializer paths depend on a JRE (Java 11+) at conversion time. This is not a new constraint — `r2pmml` has the same requirement. The `t-pmml-java` Nix derivation should provision the JAR and expose `T_JPMML_STATSMODELS_JAR` and `T_JPMML_SKLEARN_JAR` as environment variables, keeping JAR version management inside Nix and invisible to users.

---

### 5.7 Capability Comparison

| Capability | R (`r2pmml`) | Python (`jpmml-statsmodels`) |
|---|---|---|
| OLS / WLS | ✓ | ✓ |
| GLM Binomial/logit | ✓ | ✓ |
| GLM Poisson/log | ✓ | ✓ |
| GLM Gamma | ✓ | ✗ |
| Quasi families | ✓ | ✗ |
| Inference stats in PMML | via enrichment | verify first |
| Java required | ✓ | ✓ | 

---

## 6. T-Side PMML Parser Extension

The parser reads the `Extension[@name='GLMStats']` element and populates the `glm_stats` record. The link function is mapped from the string value using a small lookup:

```ocaml
let link_of_string = function
  | "identity" | "Identity" -> Identity
  | "logit"    | "Logit"    -> Logit
  | "log"      | "Log"      -> Log
  | "probit"   | "Probit"   -> Probit
  | "cloglog"  | "Cloglog"  -> Cloglog
  | "inverse"  | "Inverse"  -> Inverse
  | "sqrt"     | "Sqrt"     -> Sqrt
  | s -> failwithf "Unknown link function: %s" s

let family_of_string = function
  | "gaussian"  | "Gaussian"          -> Gaussian
  | "binomial"  | "Binomial"          -> Binomial
  | "poisson"   | "Poisson"           -> Poisson
  | "Gamma"     | "gamma"             -> Gamma
  | "inverse.gaussian" | "InverseGaussian" -> InverseGaussian
  | "quasipoisson"  | "QuasiPoisson"  -> QuasiPoisson
  | "quasibinomial" | "QuasiBinomial" -> QuasiBinomial
  | s -> failwithf "Unknown GLM family: %s" s
```

The `normalizationMethod` attribute is still parsed for the link (as a cross-check), but the `Extension` value is authoritative because it also carries family and dispersion.

---

## 7. Execution Semantics

Prediction for a GLM follows the standard two-step:

```
η = intercept + Σ (β_i × x_i)     (* linear predictor *)
μ = link⁻¹(η)                      (* inverse link      *)
```

The inverse link functions are:

| Link     | Inverse (μ = …)       |
| -------- | --------------------- |
| identity | η                     |
| logit    | 1 / (1 + exp(−η))     |
| log      | exp(η)                |
| probit   | Φ(η) (normal CDF)     |
| cloglog  | 1 − exp(−exp(η))      |
| inverse  | 1 / η                 |
| sqrt     | η²                    |

`predict(df, model)` returns μ (the fitted mean on the response scale) by default. A `type = "link"` option can expose η for users who need it, mirroring R's `predict.glm` interface.

---

## 8. `summary` and `fit_stats` Output

```
summary(model)

Family:   Binomial
Link:     logit

Coefficients:
              Estimate   Std. Error   z value   Pr(>|z|)
(Intercept)    1.5461       0.3214      4.81     < 0.001  ***
age           -0.0423       0.0088     -4.82     < 0.001  ***
income         0.0012       0.0003      3.91     < 0.001  ***

Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' '
```

```
fit_stats(model)

Null deviance:     214.3  on 199 df
Residual deviance: 183.7  on 197 df
AIC:               189.7
Log-likelihood:   -91.85
Dispersion:         1.00
```

For Quasi families, dispersion is reported as estimated rather than fixed at 1.

---

## 9. Node API

No new syntax is required. The existing `"pmml"` keyword is sufficient:

```python
logit_model = node(
    command = <{ glm(accepted ~ age + income, data = data, family = binomial) }>,
    runtime = R,
    serializer = "pmml"
)

predictions = node(
    command = <{ predict(logit_model, new_data) }>,
    runtime = T
)
```

T detects the GLM family from the parsed IR and routes to the appropriate evaluator automatically.

---

## 10. Phasing

GLM support slots into **Phase 3** of the existing plan, immediately after linear models, as a natural extension rather than a separate phase. The recommended rollout order within Phase 3 is:

1. Gaussian GLM with identity link (validates the enrichment pipeline against `lm` output)
2. Binomial / logit (the most common case)
3. Poisson / log
4. Gamma / inverse
5. Quasi families (dispersion estimation adds a small wrinkle)

Each step is independently testable via the round-trip validation strategy already specified: sample predictions in R, compare against T evaluator, fail if tolerance exceeded.

---

That covers the GLM extension. The main things to keep in mind as you implement: the z-vs-t labelling in `summary`, the dispersion field (it matters for standard errors in Quasi models), and the context-aware XPath matching during enrichment to avoid clobbering `MiningSchema` entries that happen to share a variable name with a coefficient.
