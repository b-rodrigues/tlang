open Nix_utils

let emit_node (name, expr) deps import_lines runtime serializer deserializer functions includes noop =
  if noop then
    Printf.sprintf {|
  %s = pkgs.runCommand "%s" {} ''
    mkdir -p $out
    echo "Build skipped for %s" > $out/NOOPBUILD
  '';|} name name name
  else
  let has_strategy name =
    match deserializer with
    | Ast.Value (Ast.VString s) -> s = name
    | Ast.Var s -> s = name
    | Ast.ListLit items ->
        List.exists (fun (_, e) -> match e with Ast.Value (Ast.VString s) | Ast.Var s -> s = name | _ -> false) items
    | Ast.DictLit items ->
        List.exists (fun (_, e) -> match e with Ast.Value (Ast.VString s) | Ast.Var s -> s = name | _ -> false) items
    | _ -> false
  in
  let is_builtin expr name = match expr with Ast.Value (Ast.VString s) -> s = name | _ -> false in
  let is_pmml_ser = is_builtin serializer "pmml" in
  let is_pmml_des = has_strategy "pmml" in
  let is_json_des = has_strategy "json" in
  let is_arrow_des = has_strategy "arrow" in

  let ext, extra_input = match runtime with
    | "R" -> 
        let inputs = if is_pmml_ser || is_pmml_des then "r-env pkgs.jre" else "r-env" in
        "R", inputs
    | "Python" -> 
        let inputs = if is_pmml_ser || is_pmml_des then "py-env pkgs.jre" else "py-env" in
        "py", inputs
    | _ -> "t", ""
  in

  let deps_inputs = String.concat " " (if extra_input = "" then deps else extra_input :: deps) in
  let deps_exports =
    deps
    |> List.map (fun d -> Printf.sprintf "      export T_NODE_%s=${%s}\n" d d)
    |> String.concat ""
  in
  let imports_echo =
    if runtime = "T" then
      import_lines
      |> List.map (fun line ->
        Printf.sprintf "      echo %s >> node_script.t" (shell_single_quote line))
      |> String.concat "\n"
    else ""
  in
  
  let eval_string_list lst =
    lst
    |> List.map (Eval.eval_expr (ref (Ast.Env.empty)))
    |> List.map (function Ast.VString s -> s | _ -> "")
    |> List.filter (fun s -> s <> "")
  in
  let funcs = eval_string_list functions in
  let _incs = eval_string_list includes in

  let src_block = "    src = sources;" in



  let source_files =
    if runtime = "R" then
      funcs |> List.map (fun f -> Printf.sprintf "      echo \"source('%s')\" >> node_script.R" f) |> String.concat "\n"
    else if runtime = "Python" then
      funcs |> List.map (fun f -> Printf.sprintf "      echo \"exec(open('%s').read())\" >> node_script.py" f) |> String.concat "\n"
    else
      funcs |> List.map (fun f -> Printf.sprintf "      echo %s >> node_script.t" (shell_single_quote (Printf.sprintf "import \"%s\"" f))) |> String.concat "\n"
  in
  
  let is_json_ser = match serializer with Ast.Value (Ast.VString "json") -> true | _ -> false in
  let is_arrow_ser = match serializer with Ast.Value (Ast.VString "arrow") -> true | _ -> false in

  let t_json_r_code = {|
t_write_json <- function(object, path) {
  jsonlite::write_json(object, path, auto_unbox = TRUE, null = "null")
}
t_read_json <- function(path) {
  jsonlite::read_json(path, simplifyVector = TRUE)
}
|} in

  let t_json_py_code = {|
import json
def t_write_json(obj, path):
    with open(path, "w") as f:
        json.dump(obj, f)
def t_read_json(path):
    with open(path) as f:
        return json.load(f)
|} in

  let t_arrow_r_code = {|
t_write_arrow <- function(object, path) {
  arrow::write_ipc_file(as.data.frame(object), path)
}
t_read_arrow <- function(path) {
  arrow::read_ipc_file(path)
}
|} in

  let t_arrow_py_code = {|
import pyarrow as pa
import pyarrow.ipc as ipc
import pandas as pd

def t_write_arrow(df, path):
    if isinstance(df, pd.DataFrame):
        table = pa.Table.from_pandas(df)
    else:
        table = df
    with pa.OSFile(path, 'wb') as f:
        with ipc.new_file(f, table.schema) as writer:
            writer.write_table(table)

def t_read_arrow(path):
    with pa.OSFile(path, 'rb') as f:
        return ipc.open_file(f).read_pandas()
|} in

  let t_pmml_r_code = {|
t_write_pmml <- function(object, path) {
  if (inherits(object, "glmnet")) {
    r2pmml::r2pmml(object, path, lambda.s = object$lambda[1])
  } else {
    r2pmml::r2pmml(object, path)
  }
  
  # Enrichment for lm/glm/glmnet models
  if (inherits(object, "lm") || inherits(object, "glmnet")) {
    doc <- tryCatch(XML::xmlParse(path), error = function(e) NULL)
    if (is.null(doc)) return(invisible(NULL))
    
    root <- XML::xmlRoot(doc)
    fmt <- function(x) sprintf("%.15g", x)
    
    if (inherits(object, "glmnet")) {
      # For glmnet, we pull the coefficients for the current lambda
      # Note: object$lambda[1] was used for export
      coef_m <- as.matrix(coef(object, s = object$lambda[1]))
      
      coef_list <- list()
      for (nm in rownames(coef_m)) {
        coef_list[[nm]] <- list(
          estimate = coef_m[nm, 1]
        )
      }
      
      reg_nodes <- XML::getNodeSet(doc, "//*[local-name()='RegressionModel' or local-name()='GeneralRegressionModel' or local-name()='MiningModel']")
      if (length(reg_nodes) > 0) {
        reg_node <- reg_nodes[[1]]
        glm_ext <- XML::newXMLNode("Extension",
          attrs = list(
            name  = "GLMStats",
            value = jsonlite::toJSON(list(
              family              = "Gaussian", # glmnet default for alpha=0 is Gaussian if not specified
              link                = "identity",
              coefficients        = coef_list
            ), auto_unbox = TRUE)
          )
        )
        XML::addChildren(reg_node, glm_ext)
        XML::saveXML(doc, file = path)
      }
      return(invisible(NULL))
    }

    s <- tryCatch(summary(object), error = function(e) NULL)
    if (is.null(s)) return(invisible(NULL))
    
    coef_m <- s$coefficients
    is_glm <- inherits(object, "glm")
    
    # Update NumericPredictors and RegressionTable (for Intercept)
    for (nm in rownames(coef_m)) {
      # Namespace-agnostic XPath
      xpath_np <- sprintf("//*[local-name()='NumericPredictor' and @name='%s']", nm)
      if (nm == "(Intercept)") {
         xpath_np <- "//*[local-name()='NumericPredictor' and @name='(Intercept)']"
      }
      
      nodes <- XML::getNodeSet(doc, xpath_np)
      for (nd in nodes) {
        XML::xmlAttrs(nd)[["stdError"]]   <- fmt(coef_m[nm, "Std. Error"])
        stat_name <- if (is_glm) "zStatistic" else "tStatistic"
        XML::xmlAttrs(nd)[[stat_name]]    <- fmt(coef_m[nm, 3])
        XML::xmlAttrs(nd)[["pValue"]]     <- fmt(coef_m[nm, 4])
      }
      
      if (nm == "(Intercept)") {
        xpath_rt <- "//*[local-name()='RegressionTable']"
        nodes_rt <- XML::getNodeSet(doc, xpath_rt)
        for (nd in nodes_rt) {
          XML::xmlAttrs(nd)[["stdError"]]   <- fmt(coef_m[nm, "Std. Error"])
          stat_name <- if (is_glm) "zStatistic" else "tStatistic"
          XML::xmlAttrs(nd)[[stat_name]]    <- fmt(coef_m[nm, 3])
          XML::xmlAttrs(nd)[["pValue"]]     <- fmt(coef_m[nm, 4])
        }
      }
    }
    
    # Model-level statistics
    reg_nodes <- XML::getNodeSet(doc, "//*[local-name()='RegressionModel' or local-name()='GeneralRegressionModel']")
    if (length(reg_nodes) > 0) {
      reg_node <- reg_nodes[[1]]
      
      if (is_glm) {
        # Prepare coefficient data as JSON for fallback
        coef_list <- list()
        for (nm in rownames(coef_m)) {
          coef_list[[nm]] <- list(
            estimate = coef_m[nm, 1],
            std_error = coef_m[nm, 2],
            statistic = coef_m[nm, 3],
            p_value = coef_m[nm, 4]
          )
        }

        # GLM Specific Stats (Extension)
        glm_ext <- XML::newXMLNode("Extension",
          attrs = list(
            name  = "GLMStats",
            value = jsonlite::toJSON(list(
              family              = family(object)$family,
              link                = family(object)$link,
              null_deviance       = fmt(s$null.deviance),
              null_deviance_df    = s$df.null,
              residual_deviance   = fmt(s$deviance),
              residual_deviance_df= s$df.residual,
              dispersion          = fmt(s$dispersion),
              aic                 = fmt(s$aic),
              log_likelihood      = fmt(as.numeric(logLik(object))),
              coefficients        = coef_list
            ), auto_unbox = TRUE)
          )
        )
        XML::addChildren(reg_node, glm_ext)
      } else {
        # LM Specific Stats (PredictiveModelQuality)
        fstat <- if (!is.null(s$fstatistic)) fmt(s$fstatistic[1]) else "NA"
        fpval <- if (!is.null(s$fstatistic)) {
          fmt(pf(s$fstatistic[1], s$fstatistic[2], s$fstatistic[3], lower.tail = FALSE))
        } else "NA"
        
        quality <- XML::newXMLNode("PredictiveModelQuality",
          attrs = list(
            r2 = fmt(s$r.squared),
            `adj-r2` = fmt(s$adj.r.squared),
            aic = fmt(AIC(object)),
            bic = fmt(BIC(object)),
            sigma = fmt(s$sigma),
            nobs = nobs(object),
            fStatistic = fstat,
            fPValue = fpval,
            logLik = fmt(as.numeric(logLik(object))),
            deviance = fmt(deviance(object)),
            dfResidual = df.residual(object)
          )
        )
        XML::addChildren(reg_node, quality)
      }
    }
    
    XML::saveXML(doc, file = path)
  }
}
t_read_pmml <- function(path) {
  path
}
|} in

  let t_pmml_py_code = {|
import os
import subprocess
import tempfile
import pickle

def t_write_pmml(model, path):
    # Check if it's a statsmodels model
    is_sm = False
    try:
        import statsmodels.base.wrapper as sm_wrapper
        if isinstance(model, sm_wrapper.ResultsWrapper):
            is_sm = True
    except ImportError: pass

    if is_sm:
        return t_export_sm_model(model, path)

    # Otherwise assume sklearn
    try:
        from sklearn2pmml import sklearn2pmml
    except ImportError as exc:
        raise ImportError(
            "PMML export in Python requires the 'sklearn2pmml' package for sklearn models."
        ) from exc
    
    # Basic export
    sklearn2pmml(model, path)
    # sklearn-specific enrichment omitted for brevity here, should follow previous pattern if needed
    _enrich_sklearn_pmml(model, path)

def t_export_sm_model(results, path):
    _assert_supported(results)

    with tempfile.TemporaryDirectory() as tmp:
        pkl_path = os.path.join(tmp, "model.pkl")
        results.save(pkl_path, remove_data=False)

        jar_path = _resolve_jpmml_statsmodels_jar()

        subprocess.run(
            [
                "java", "-jar", jar_path,
                "--pkl-input",  pkl_path,
                "--pmml-output", path,
            ],
            check=True,
        )

    _enrich_sm_model_pmml(results, path)
    return path

def _assert_supported(results):
    import statsmodels.genmod.generalized_linear_model as glm_module

    supported_families = {"Binomial", "Gaussian", "Poisson"}
    supported_links    = {"identity", "log", "logit"}

    if hasattr(results, "family") and results.family is not None:
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

def _resolve_jpmml_statsmodels_jar():
    jar = os.environ.get("T_JPMML_STATSMODELS_JAR")
    if not jar or not os.path.exists(jar):
        raise RuntimeError(
            "JPMML-StatsModels JAR not found. "
            "Ensure the t-pmml-java derivation is present in your environment."
        )
    return jar

def _enrich_sklearn_pmml(model, path):
    from sklearn.linear_model import LinearRegression
    if isinstance(model, LinearRegression) and hasattr(model, 'feature_names_in_'):
        try:
            import xml.etree.ElementTree as ET
            tree = ET.parse(path)
            root = tree.getroot()
            reg_model = None
            for el in root.iter():
                if el.tag.endswith('RegressionModel'):
                    reg_model = el
                    break
            if reg_model is not None:
                tag = reg_model.tag
                ns_prefix = tag[:tag.rfind('}')+1] if '}' in tag else ""
                quality = ET.SubElement(reg_model, ns_prefix + 'PredictiveModelQuality')
                for attr in ['r2_', 'adj_r2_', 'aic_', 'bic_', 'sigma_', 'nobs_', 'f_statistic_', 'f_p_value_', 'log_lik_', 'deviance_', 'df_residual_']:
                    if hasattr(model, attr):
                        quality.set(attr.replace('_', "").replace('adjr2', 'adj-r2'), str(getattr(model, attr)))
                tree.write(path)
        except Exception: pass

def _enrich_sm_model_pmml(results, path):
    import json
    try:
        import xml.etree.ElementTree as ET
        tree = ET.parse(path)
        root = tree.getroot()
        reg_model = None
        for el in root.iter():
            if el.tag.endswith('RegressionModel') or el.tag.endswith('GeneralRegressionModel'):
                reg_model = el
                break
        if reg_model is not None:
            tag = reg_model.tag
            ns_prefix = tag[:tag.rfind('}')+1] if '}' in tag else ""
            
            if hasattr(results, "family") and results.family is not None:
                fam = type(results.family).__name__
                lnk = type(results.family.link).__name__.lower()
            else:
                fam = "Gaussian"
                lnk = "identity"
            
            coef_list = {}
            for name, coef in results.params.items():
                c_dict = {"estimate": float(coef)}
                try: c_dict["std_error"] = float(results.bse[name])
                except Exception: pass
                try:
                    stat = results.tvalues[name] if hasattr(results, 'tvalues') else (results.zvalues[name] if hasattr(results, 'zvalues') else None)
                    if stat is not None: c_dict["statistic"] = float(stat)
                except Exception: pass
                try: c_dict["p_value"] = float(results.pvalues[name])
                except Exception: pass
                coef_list[name] = c_dict
                
            glm_stats = {
                "family": fam,
                "link": lnk,
                "coefficients": coef_list
            }
            if hasattr(results, 'null_deviance'): glm_stats["null_deviance"] = str(float(results.null_deviance))
            if hasattr(results, 'df_null'): glm_stats["null_deviance_df"] = int(results.df_null)
            if hasattr(results, 'deviance'): glm_stats["residual_deviance"] = str(float(results.deviance))
            if hasattr(results, 'df_resid'): glm_stats["residual_deviance_df"] = int(results.df_resid)
            if hasattr(results, 'scale'): glm_stats["dispersion"] = str(float(results.scale))
            if hasattr(results, 'aic'): glm_stats["aic"] = str(float(results.aic))
            if hasattr(results, 'llf'): glm_stats["log_likelihood"] = str(float(results.llf))
            
            glm_ext = ET.SubElement(reg_model, ns_prefix + 'Extension')
            glm_ext.set('name', 'GLMStats')
            glm_ext.set('value', json.dumps(glm_stats))
            
            for el in reg_model.iter():
                if el.tag.endswith('NumericPredictor'):
                    nm = el.get('name')
                    if nm and nm in results.params:
                        try: el.set('stdError', str(results.bse[nm]))
                        except Exception: pass
                        try: el.set('zStatistic', str(results.tvalues[nm]))
                        except Exception: pass
                        try: el.set('pValue', str(results.pvalues[nm]))
                        except Exception: pass
                elif el.tag.endswith('RegressionTable'):
                    if 'const' in results.params:
                        try: el.set('stdError', str(results.bse['const']))
                        except Exception: pass
                        try: el.set('zStatistic', str(results.tvalues['const']))
                        except Exception: pass
                        try: el.set('pValue', str(results.pvalues['const']))
                        except Exception: pass

            tree.write(path)
    except Exception:
        pass

def t_read_pmml(path):
    try:
        from pypmml import Model
    except ImportError:
        return path # Fallback to path
    return Model.load(path)
|} in

  let json_injection =
    if is_json_ser || is_json_des then
      if runtime = "R" then
        Printf.sprintf "      cat << 'EOF' >> node_script.R\n%s\nEOF" t_json_r_code
      else if runtime = "Python" then
        Printf.sprintf "      cat << 'EOF' >> node_script.py\n%s\nEOF" t_json_py_code
      else ""
    else ""
  in

  let arrow_injection =
    if is_arrow_ser || is_arrow_des then
      if runtime = "R" then
        Printf.sprintf "      cat << 'EOF' >> node_script.R\n%s\nEOF" t_arrow_r_code
      else if runtime = "Python" then
        Printf.sprintf "      cat << 'EOF' >> node_script.py\n%s\nEOF" t_arrow_py_code
      else ""
    else ""
  in

  let pmml_injection =
    if is_pmml_ser || is_pmml_des then
      if runtime = "R" then
        Printf.sprintf "      cat << 'EOF' >> node_script.R\n%s\nEOF" t_pmml_r_code
      else if runtime = "Python" then
        Printf.sprintf "      cat << 'EOF' >> node_script.py\n%s\nEOF" t_pmml_py_code
      else ""
    else ""
  in

  (* Logic for deserializing dependencies *)
  let deps_script_lines =
    let get_des_call dep_name =
      let rec lookup_in_list target = function
        | [] -> None
        | (Some n, e) :: _ when n = target -> Some e
        | _ :: rest -> lookup_in_list target rest
      in
      let rec lookup_in_dict target = function
        | [] -> None
        | (n, e) :: _ when n = target -> Some e
        | _ :: rest -> lookup_in_dict target rest
      in
      let strategy_expr = match deserializer with
        | Ast.ListLit items -> (match lookup_in_list dep_name items with Some e -> e | None -> deserializer)
        | Ast.DictLit items -> (match lookup_in_dict dep_name items with Some e -> e | None -> deserializer)
        | _ -> deserializer
      in
      let strategy_is_string = match strategy_expr with Ast.Value (Ast.VString _) -> true | _ -> false in
      let strategy = Nix_unparse.expr_to_string strategy_expr in
      
      if strategy = "default" then
        (if runtime = "R" then "readRDS" else "deserialize")
      else if strategy_is_string then
        if strategy = "json" then "t_read_json"
        else if strategy = "arrow" then "t_read_arrow"
        else if strategy = "pmml" then "t_read_pmml"
        else strategy
      else
        strategy
    in
    deps
    |> List.map (fun d ->
      let des_call = get_des_call d in
      if runtime = "R" then
        Printf.sprintf "      echo \"%s <- %s(\\\"$T_NODE_%s/artifact\\\")\" >> node_script.%s" d des_call d ext
      else
        Printf.sprintf "      echo \"%s = %s(\\\"$T_NODE_%s/artifact\\\")\" >> node_script.%s" d des_call d ext)
    |> String.concat "\n"
  in

  let expr_s = Nix_unparse.unparse_expr expr in
  let ser_expr_is_string = match serializer with Ast.Value (Ast.VString _) -> true | _ -> false in
  let ser_s = Nix_unparse.expr_to_string serializer in
  let ser_call =
    if ser_s = "default" then
      (if runtime = "R" then "saveRDS" else "serialize")
    else if ser_expr_is_string then
      if ser_s = "json" then "t_write_json"
      else if ser_s = "arrow" then "t_write_arrow"
      else if ser_s = "pmml" then "t_write_pmml"
      else ser_s
    else
      ser_s
  in

  let is_raw_code = match expr with RawCode _ -> true | _ -> false in

  let hoisted_imports =
    if is_raw_code then
      let lines = String.split_on_char '\n' expr_s in
      let is_import_line line =
        let l = String.trim line in
        if runtime = "Python" then
          String.starts_with ~prefix:"import " l || String.starts_with ~prefix:"from " l
        else if runtime = "R" then
          String.starts_with ~prefix:"library(" l || String.starts_with ~prefix:"require(" l
        else false
      in
      let imports = List.filter is_import_line lines in
      if imports = [] then ""
      else
        let code = String.concat "\n" (List.map String.trim imports) in
        Printf.sprintf "      cat <<'EOF' >> node_script.%s\n%s\nEOF\n" ext code
    else ""
  in

  (* Check if raw code string contains a Python assignment to node_name.
     Looks for `name = ` (assignment, not `==` comparison) at the start of a line. *)
  let raw_assigns_to name s =
    let prefix = name ^ " = " in
    let prefix_eq = name ^ " ==" in
    String.split_on_char '\n' s
    |> List.exists (fun line ->
      let l = String.trim line in
      String.length l >= String.length prefix &&
      String.sub l 0 (String.length prefix) = prefix &&
      not (String.length l >= String.length prefix_eq &&
           String.sub l 0 (String.length prefix_eq) = prefix_eq))
  in

  let assign_script_lines =
    if runtime = "R" then
      if is_raw_code then
        Printf.sprintf {|      echo "%s <- local({" >> node_script.R
      cat <<'EOF' >> node_script.R
%s
EOF
      echo "})" >> node_script.R
      echo "%s(%s, \"$out/artifact\")" >> node_script.R
      echo "writeLines(as.character(class(%s)[1]), \"$out/class\")" >> node_script.R|} name expr_s ser_call name name
      else
        Printf.sprintf {|      cat <<'EOF' >> node_script.R
%s <- %s
EOF
      echo "%s(%s, \"$out/artifact\")" >> node_script.R
      echo "writeLines(as.character(class(%s)[1]), \"$out/class\")" >> node_script.R|} name expr_s ser_call name name
    else if runtime = "Python" then
      if is_raw_code then
        if raw_assigns_to name expr_s then
          (* Statement-style: raw code explicitly assigns to node name — use as-is *)
          Printf.sprintf {|      cat <<'EOF' >> node_script.py
%s
EOF
      echo "%s(%s, \"$out/artifact\")" >> node_script.py
      echo "with open(\"$out/class\", \"w\") as f: f.write(type(%s).__name__)" >> node_script.py|} expr_s ser_call name name
        else
          (* Expression-style: wrap with assignment to node name *)
          Printf.sprintf {|      cat <<'EOF' >> node_script.py
%s = (%s)
EOF
      echo "%s(%s, \"$out/artifact\")" >> node_script.py
      echo "with open(\"$out/class\", \"w\") as f: f.write(type(%s).__name__)" >> node_script.py|} name expr_s ser_call name name
      else
        Printf.sprintf {|      cat <<'EOF' >> node_script.py
%s = %s
EOF
      echo "%s(%s, \"$out/artifact\")" >> node_script.py
      echo "with open(\"$out/class\", \"w\") as f: f.write(type(%s).__name__)" >> node_script.py|} name expr_s ser_call name name
    else
      if is_raw_code then
        Printf.sprintf {|      echo "      %s = {" >> node_script.t
      cat <<'EOF' >> node_script.t
%s
EOF
      echo "      }" >> node_script.t
      echo "      res1 = %s(%s, \"$out/artifact\")" >> node_script.t
      echo "      if (is_error(res1)) { print(\"Serialization failed:\"); print(res1); exit(1) } else { 0 }" >> node_script.t
      echo "      res2 = write_text(\"$out/class\", type(%s))" >> node_script.t
      echo "      if (is_error(res2)) { print(\"Class write failed:\"); print(res2); exit(1) } else { 0 }" >> node_script.t|} name expr_s ser_call name name
      else
        Printf.sprintf {|      cat <<'EOF' >> node_script.t
      %s = %s
EOF
      echo "      res1 = %s(%s, \"$out/artifact\")" >> node_script.t
      echo "      if (is_error(res1)) { print(\"Serialization failed:\"); print(res1); exit(1) } else { 0 }" >> node_script.t
      echo "      res2 = write_text(\"$out/class\", type(%s))" >> node_script.t
      echo "      if (is_error(res2)) { print(\"Class write failed:\"); print(res2); exit(1) } else { 0 }" >> node_script.t|} name expr_s ser_call name name
  in

  (* Runtime specific build command *)
  let run_cmd = match runtime with
    | "R" -> "Rscript node_script.R"
    | "Python" -> "python node_script.py"
    | _ -> "t run --unsafe node_script.t"
  in

  Printf.sprintf {|
  %s = stdenv.mkDerivation {
    name = "%s";
    buildInputs = [ tBin %s ];
    T_JPMML_STATSMODELS_JAR = "${pkgs.jpmml-statsmodels}/share/java/jpmml-statsmodels.jar";
%s
    buildCommand = ''
      cp -r $src/* . || true
      chmod -R u+w .
%s
      cat << EOF > node_script.%s
EOF
%s
%s
%s
%s
%s
%s
%s
%s
      mkdir -p $out
      %s
    '';
  };
|} name name deps_inputs src_block deps_exports ext json_injection arrow_injection pmml_injection imports_echo source_files hoisted_imports deps_script_lines assign_script_lines run_cmd
