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

## 5. Runtime Enrichment (Python)

For `statsmodels.GLM`:

```python
import xml.etree.ElementTree as ET
import json, re

def t_export_glm(fit, path):
    # sklearn2pmml handles base export
    sklearn2pmml_pipeline_to_pmml(fit, path)

    tree = ET.parse(path)
    root = tree.getroot()
    ns   = {"pmml": "http://www.dmg.org/PMML-4_4"}
    fmt  = lambda x: f"{x:.15g}"

    summary = fit.summary2().tables[1]   # param table
    for _, row in summary.iterrows():
        name = row.name
        xpath = f".//pmml:NumericPredictor[@name='{name}']"
        for nd in root.findall(xpath, ns):
            nd.set("stdError",   fmt(row["Std.Err."]))
            nd.set("zStatistic", fmt(row["z"]))
            nd.set("pValue",     fmt(row["P>|z|"]))

    reg = root.find(".//pmml:RegressionModel", ns)
    ext = ET.SubElement(reg, "Extension")
    ext.set("name", "GLMStats")
    ext.set("value", json.dumps({
        "family"              : fit.family.__class__.__name__,
        "link"                : fit.family.link.__class__.__name__,
        "null_deviance"       : fmt(fit.null_deviance),
        "null_deviance_df"    : int(fit.df_null),
        "residual_deviance"   : fmt(fit.deviance),
        "residual_deviance_df": int(fit.df_resid),
        "dispersion"          : fmt(fit.scale),
        "aic"                 : fmt(fit.aic),
        "log_likelihood"      : fmt(float(fit.llf))
    }))

    tree.write(path, xml_declaration=True, encoding="utf-8")
```

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
