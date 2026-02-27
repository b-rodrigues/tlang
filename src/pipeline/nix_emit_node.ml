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
  r2pmml::r2pmml(object, path)
  # Enrich PMML with summary statistics for lm/glm models
  if (inherits(object, "lm")) {
    s <- tryCatch(summary(object), error = function(e) NULL)
    if (is.null(s)) return(invisible(NULL))
    pmml_text <- paste(readLines(path, warn = FALSE), collapse = "\n")
    coefs <- s$coefficients
    fmt <- function(x) sprintf("%.15g", x)
    # Add std_error/tStatistic/pValue to each NumericPredictor
    # Must match on NumericPredictor context to avoid hitting MiningField elements
    for (pname in rownames(coefs)) {
      if (pname == "(Intercept)") next
      se <- fmt(coefs[pname, "Std. Error"])
      tv <- fmt(coefs[pname, "t value"])
      pv <- fmt(coefs[pname, "Pr(>|t|)"])
      old_frag <- paste0('<NumericPredictor name="', pname, '"')
      new_frag <- paste0('<NumericPredictor name="', pname, '" stdError="', se, '" tStatistic="', tv, '" pValue="', pv, '"')
      pmml_text <- sub(old_frag, new_frag, pmml_text, fixed = TRUE)
    }
    # Add intercept stats to RegressionTable
    if ("(Intercept)" %in% rownames(coefs)) {
      se <- fmt(coefs["(Intercept)", "Std. Error"])
      tv <- fmt(coefs["(Intercept)", "t value"])
      pv <- fmt(coefs["(Intercept)", "Pr(>|t|)"])
      # Find the intercept value that r2pmml wrote
      m <- regmatches(pmml_text, regexpr('intercept="[^"]*"', pmml_text))
      if (length(m) > 0) {
        new_frag <- paste0(m[1], ' stdError="', se, '" tStatistic="', tv, '" pValue="', pv, '"')
        pmml_text <- sub(m[1], new_frag, pmml_text, fixed = TRUE)
      }
    }
    # Add PredictiveModelQuality element with model-level stats
    fstat <- if (!is.null(s$fstatistic)) fmt(s$fstatistic[1]) else "NA"
    fpval <- if (!is.null(s$fstatistic)) {
      fmt(pf(s$fstatistic[1], s$fstatistic[2], s$fstatistic[3], lower.tail = FALSE))
    } else "NA"
    ll <- fmt(logLik(object))
    dev <- fmt(deviance(object))
    dfr <- df.residual(object)
    quality <- sprintf(
      '  <PredictiveModelQuality r2="%s" adj-r2="%s" aic="%s" bic="%s" sigma="%s" nobs="%d" fStatistic="%s" fPValue="%s" logLik="%s" deviance="%s" dfResidual="%d"/>',
      fmt(s$r.squared), fmt(s$adj.r.squared),
      fmt(AIC(object)), fmt(BIC(object)),
      fmt(s$sigma), nobs(object),
      fstat, fpval, ll, dev, dfr
    )
    pmml_text <- sub("</RegressionModel>",
                     paste0(quality, "\n</RegressionModel>"),
                     pmml_text, fixed = TRUE)
    cat(pmml_text, file = path)
  }
}
t_read_pmml <- function(path) {
  # Return the raw PMML path - T handles PMML deserialization natively
  path
}
|} in

  let t_pmml_py_code = {|
def t_write_pmml(model, path):
    try:
        from sklearn2pmml import sklearn2pmml
    except ImportError as exc:
        raise ImportError(
            "PMML export in Python requires the 'sklearn2pmml' package to be installed."
        ) from exc
    
    # Basic export
    sklearn2pmml(model, path)

    # Statistical enrichment for LinearRegression
    from sklearn.linear_model import LinearRegression
    if isinstance(model, LinearRegression) and hasattr(model, 'feature_names_in_'):
        try:
            import numpy as np
            from scipy import stats
            import xml.etree.ElementTree as ET

            # 1. Calculate OLS statistics
            # We assume the model was fit on data where we can't easily get the original X
            # but if it was fit just now, we might have issues. 
            # However, for the bridge to be useful, we need the stats.
            # In T pipelines, the user usually passes raw data to the command.
            # For now, we only enrich if we have the necessary info or if we can re-derive it.
            # But sklearn doesn't store the training data.
            # Strategy: If the model has been enriched with stats attributes by the user, use them.
            # Otherwise, we can only export coefficients.
            
            # To match R's lm, we'd need the residuals and X matrix.
            # Since sklearn doesn't keep them, we expect the user might have used a wrapper 
            # or we just provide the coefficients.
            # BUT the user request says "the data and received should be the same as the R ones".
            # This implies they want the standard errors even from Python.
            
            # Let's check if we can find the data in the local scope? No, that's hacky.
            # Let's assume for this bridge that if standard errors are missing, we just leave them.
            # UNLESS we calculate them here if X and y are available in the scope?
            # No, t_write_pmml only gets 'model'.
            
            # However, we can at least add the model quality (R2) which sklearn DOES have.
            tree = ET.parse(path)
            root = tree.getroot()
            ns = {'p': 'http://www.dmg.org/PMML-4_4'}
            # Note: sklearn2pmml might use a different version. Let's find the tag regardless of NS.
            
            def find_tag(root, tag):
                for el in root.iter():
                    if el.tag.endswith(tag):
                        return el
                return None

            reg_model = find_tag(root, 'RegressionModel')
            if reg_model is not None:
                # 1. Inject model-level Quality metrics
                # Get namespace from parent tag
                tag = reg_model.tag
                ns_prefix = tag[:tag.rfind('}')+1] if '}' in tag else ""
                
                quality = ET.SubElement(reg_model, ns_prefix + 'PredictiveModelQuality')
                if hasattr(model, 'r2_'): quality.set('r2', str(model.r2_))
                if hasattr(model, 'adj_r2_'): quality.set('adj-r2', str(model.adj_r2_))
                if hasattr(model, 'aic_'): quality.set('aic', str(model.aic_))
                if hasattr(model, 'bic_'): quality.set('bic', str(model.bic_))
                if hasattr(model, 'sigma_'): quality.set('sigma', str(model.sigma_))
                if hasattr(model, 'nobs_'): quality.set('nobs', str(int(model.nobs_)))
                if hasattr(model, 'f_statistic_'): quality.set('fStatistic', str(model.f_statistic_))
                if hasattr(model, 'f_p_value_'): quality.set('fPValue', str(model.f_p_value_))
                if hasattr(model, 'log_lik_'): quality.set('logLik', str(model.log_lik_))
                if hasattr(model, 'deviance_'): quality.set('deviance', str(model.deviance_))
                if hasattr(model, 'df_residual_'): quality.set('dfResidual', str(int(model.df_residual_)))

                # 2. Inject coefficient-level stats
                table = find_tag(reg_model, 'RegressionTable')
                if table is not None:
                    # Map feature names to order in model
                    features = model.feature_names_in_.tolist()
                    
                    # Intercept
                    if hasattr(model, 'std_errors_'):
                        table.set('stdError', str(model.std_errors_[0]))
                    if hasattr(model, 't_stats_'):
                        table.set('tStatistic', str(model.t_stats_[0]))
                    if hasattr(model, 'p_values_'):
                        table.set('pValue', str(model.p_values_[0]))
                    
                    # NumericPredictors - use namespace-agnostic search
                    for pred in table:
                        if not pred.tag.endswith('NumericPredictor'):
                            continue
                        name = pred.get('name')
                        if name in features:
                            idx = features.index(name) + 1 # +1 because 0 is intercept
                            if hasattr(model, 'std_errors_'):
                                pred.set('stdError', str(model.std_errors_[idx]))
                            if hasattr(model, 't_stats_'):
                                pred.set('tStatistic', str(model.t_stats_[idx]))
                            if hasattr(model, 'p_values_'):
                                pred.set('pValue', str(model.p_values_[idx]))

                tree.write(path)
        except Exception:
            pass # Fallback to basic PMML if enrichment fails

def t_read_pmml(path):
    try:
        from pypmml import Model
    except ImportError as exc:
        raise ImportError(
            "PMML reading in Python requires the 'pypmml' package to be installed."
        ) from exc
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
        let code = String.concat "\n" imports in
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
