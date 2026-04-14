open Ast
open Nix_utils

let indent_string s n =
  let lines = String.split_on_char '\n' s in
  let non_empty_lines = List.filter (fun l -> String.trim l <> "") lines in
  let common_indent =
    match non_empty_lines with
    | [] -> 0
    | first :: _ ->
        let rec count_spaces i =
          if i < String.length first && first.[i] = ' ' then count_spaces (i + 1) else i
        in
        let initial = count_spaces 0 in
        List.fold_left (fun acc line ->
          let rec count i =
            if i < String.length line && line.[i] = ' ' && (i < acc) then count (i + 1) else i
          in
          if String.trim line = "" then acc else count 0
        ) initial non_empty_lines
  in
  let indent = String.make n ' ' in
  lines
  |> List.map (fun line ->
       if String.trim line = "" then ""
       else
         let stripped = if String.length line >= common_indent then String.sub line common_indent (String.length line - common_indent) else line in
         indent ^ stripped)
  |> String.concat "\n"

let emit_node (name, expr) deps all_pipeline_node_names import_lines runtime serializer deserializer env_vars runtime_args functions includes noop script shell shell_args =
  (* Safety net: only include actual nodes in this pipeline as Nix buildInputs.
     The evaluator already filters p_deps, but this guards against any edge cases. *)
  let deps = List.filter (fun d -> List.mem d all_pipeline_node_names) deps in
  let is_valid_env_var_name key =
    let is_initial = function
      | 'A' .. 'Z' | 'a' .. 'z' | '_' -> true
      | _ -> false
    in
    let is_continue = function
      | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' -> true
      | _ -> false
    in
    String.length key > 0
    && is_initial key.[0]
    && let rec loop idx =
         idx >= String.length key
         || (is_continue key.[idx] && loop (idx + 1))
       in
       loop 1
  in
  let sanitize_env_var_suffix s =
    let buffer = Buffer.create (String.length s) in
    String.iter (function
      | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' as c -> Buffer.add_char buffer c
      | _ -> Buffer.add_char buffer '_'
    ) s;
    let sanitized = Buffer.contents buffer in
    if sanitized = "" then "_" else sanitized
  in
  let dep_env_var_name dep = "T_NODE_" ^ sanitize_env_var_suffix dep in



  if noop then
    Printf.sprintf {|
  %s = pkgs.runCommand "%s" {} ''
    mkdir -p $out
    echo "Build skipped for %s" > $out/NOOPBUILD
  '';|} name name name
  else
  let eval_expr_safe e = Eval.eval_expr (ref Ast.Env.empty) e in
  let ser_val = eval_expr_safe serializer in
  let des_val = eval_expr_safe deserializer in

  let get_format = function
    | Ast.VSerializer s -> Some s.s_format
    | Ast.VString s | Ast.VSymbol s -> Some (let s = if String.starts_with ~prefix:"^" s then String.sub s 1 (String.length s - 1) else s in String.lowercase_ascii s)
    | Ast.VDict pairs -> 
        (match List.assoc_opt "format" pairs with
         | Some (VString s) | Some (VSymbol s) -> Some (String.lowercase_ascii s)
         | _ -> None)
    | _ -> None
  in

  let get_polyglot_snippet ~lang ~kind v =
    match v, lang, kind with
    | Ast.VSerializer s, "R", "writer" -> s.s_r_writer
    | Ast.VSerializer s, "R", "reader" -> s.s_r_reader
    | Ast.VSerializer s, "Python", "writer" -> s.s_py_writer
    | Ast.VSerializer s, "Python", "reader" -> s.s_py_reader
    | Ast.VDict pairs, lang, kind ->
        let key = (match lang, kind with
          | "R", "writer" -> "r_writer" | "R", "reader" -> "r_reader"
          | "Python", "writer" -> "py_writer" | "Python", "reader" -> "py_reader"
          | _ -> "unknown") in
        (match List.assoc_opt key pairs with Some (VRawCode s) -> Some s | _ -> None)
    | _ -> None
  in

  let ser_fmt = get_format ser_val in
  let is_ser f = match ser_fmt with Some sf -> sf = f | None -> false in
  
  let is_fmt_in_des f = 
    match des_val with
    | Ast.VDict pairs -> List.exists (fun (_, v) -> get_format v = Some f) pairs
    | _ -> get_format des_val = Some f
  in

  let ext, extra_input = match runtime with
    | "R" -> 
        "R", "r-env"
    | "Python" -> 
        "py", "py-env"
    | "Quarto" ->
        "sh", "r-env py-env"
    | "sh" ->
        "sh", "pkgs.bash"
    | _ -> "t", ""
  in

  let deps_inputs = String.concat " " (if extra_input = "" then deps else extra_input :: deps) in
  let deps_exports =
    deps
    |> List.map (fun d -> Printf.sprintf "      export %s=${%s}\n" (dep_env_var_name d) d)
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

  let env_value_to_string = function
    | Ast.VString s -> Some s
    | Ast.VSymbol s -> Some s
    | Ast.VInt i -> Some (string_of_int i)
    (* 15 significant digits is enough to round-trip IEEE-754 doubles predictably
       for environment-variable use without forcing trailing noise. *)
    | Ast.VFloat f -> Some (Printf.sprintf "%.15g" f)
    | Ast.VBool true -> Some "true"
    | Ast.VBool false -> Some "false"
    | Ast.(VNA NAGeneric) -> None
    | _ -> None
  in
  let arg_value_to_strings = function
    | Ast.VList items ->
        items
        |> List.map snd
        |> List.filter_map env_value_to_string
    | value ->
        (match env_value_to_string value with
         | Some s -> [s]
         | None -> [])
  in
  let shell_args_tokens =
    shell_args
    |> List.map (fun expr ->
      let value = Eval.eval_expr (ref (Ast.Env.empty)) expr in
      match env_value_to_string value with
      | Some s -> s
      | None -> Nix_unparse.unparse_expr expr)
  in
  let sh_cli_args_tokens =
    runtime_args
    |> List.map snd
    |> List.concat_map arg_value_to_strings
  in
  let shell_quote_words words =
    String.concat " " (List.map shell_single_quote words)
  in
  let shell_set_args_block words =
    match words with
    | [] -> ""
    | _ -> Printf.sprintf "      set -- %s\n" (shell_quote_words words)
  in
  let shell_uses_command_string args =
    List.exists (fun arg -> arg = "-c" || arg = "-lc" || arg = "-cl") args
  in
  let is_simple_exec_command cmd =
    let looks_like_env_assignment =
      let rec find_equals idx =
        if idx >= String.length cmd then
          None
        else if cmd.[idx] = '=' then
          Some idx
        else
          find_equals (idx + 1)
      in
      let is_assignment_name_char = function
        | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' -> true
        | _ -> false
      in
      match find_equals 0 with
      | Some eq_idx when eq_idx > 0 ->
          let name = String.sub cmd 0 eq_idx in
          let starts_ok =
            match name.[0] with
            | 'A' .. 'Z' | 'a' .. 'z' | '_' -> true
            | _ -> false
          in
          starts_ok
          && let rec loop idx =
               idx >= String.length name
               || (is_assignment_name_char name.[idx] && loop (idx + 1))
             in
             loop 1
      | _ -> false
    in
    let rec loop i =
      if i >= String.length cmd then
        true
      else
        match cmd.[i] with
        | ' ' | '\t' | '\n' | '\r'
        | '\'' | '"' | '`' | '$' | '\\'
        | ';' | '&' | '|' | '<' | '>'
        | '(' | ')' | '{' | '}' | '[' | ']' ->
            false
        | _ -> loop (i + 1)
    in
    cmd <> "" && not looks_like_env_assignment && loop 0
  in
  let flag_key_to_cli_format key =
    String.map (fun c -> if c = '_' then '-' else c) key
  in
  let quarto_cli_tokens =
    if runtime <> "Quarto" then
      []
    else
      (* These keys are handled specially for Quarto nodes: `subcommand` and the
         input-file keys are emitted positionally, while `output_dir` is reserved
         so Quarto outputs always land under $out/artifact. *)
      let reserved_keys = [ "subcommand"; "path"; "file"; "qmd_file"; "input"; "output_dir" ] in
      let lookup_values key =
        match List.assoc_opt key runtime_args with
        | Some value -> arg_value_to_strings value
        | None -> []
      in
      let find_first_values keys =
        Option.value ~default:[] (List.find_map (fun key ->
          let values = lookup_values key in
          if values = [] then None else Some values
        ) keys)
      in
      let subcommand_tokens =
        match lookup_values "subcommand" with
        | [] -> [ "render" ]
        | values -> values
      in
      let input_tokens =
        match script with
        | Some script_path -> [ script_path ]
        | None -> find_first_values [ "path"; "file"; "qmd_file"; "input" ]
      in
      let option_tokens =
        runtime_args
        |> List.filter_map (fun (key, value) ->
          if List.mem key reserved_keys then
            None
          else
            let flag = "--" ^ flag_key_to_cli_format key in
            let tokens =
              match value with
              | Ast.VBool true -> [ flag ]
              | Ast.VBool false | Ast.(VNA NAGeneric) -> []
              | Ast.VList items ->
                  items
                  |> List.map snd
                  |> List.filter_map env_value_to_string
                  |> List.concat_map (fun s -> [ flag; s ])
              | other ->
                  (match env_value_to_string other with
                   | Some s -> [ flag; s ]
                   | None -> [])
            in
            Some tokens)
        |> List.concat
      in
      subcommand_tokens @ input_tokens @ option_tokens @ [ "--output-dir"; ".quarto-output" ]
  in
  let quarto_cli_args_block =
    quarto_cli_tokens
    |> List.map (fun token -> Printf.sprintf "      cli_args+=(%s)" (shell_single_quote token))
    |> String.concat "\n"
  in
  let env_var_block =
    env_vars
    |> List.filter_map (fun (key, value) ->
      match env_value_to_string value with
      | Some s -> Some (Printf.sprintf "    %s = %s;" (nix_double_quote key) (nix_double_quote s))
      | None -> None
    )
    |> String.concat "\n"
  in

  let src_block = "    src = sources;" in



  let source_files =
    if runtime = "R" then
      funcs |> List.map (fun f -> Printf.sprintf "      echo \"source('%s')\" >> node_script.R" f) |> String.concat "\n"
    else if runtime = "Python" then
      funcs |> List.map (fun f -> Printf.sprintf "      echo \"exec(open('%s').read())\" >> node_script.py" f) |> String.concat "\n"
    else if runtime = "Quarto" then
      ""
    else
      funcs |> List.map (fun f -> Printf.sprintf "      echo %s >> node_script.t" (shell_single_quote (Printf.sprintf "import \"%s\"" f))) |> String.concat "\n"
  in
  
  (* Use is_ser instead of is_builtin for serializer checks *)
  let is_arrow_ser  = is_ser "arrow" in
  let is_arrow_des  = is_fmt_in_des "arrow" in
  let is_csv_ser    = is_ser "csv" in
  let is_csv_des    = is_fmt_in_des "csv" in
  let is_pmml_ser   = is_ser "pmml" in
  let is_pmml_des   = is_fmt_in_des "pmml" in
  let is_onnx_ser   = is_ser "onnx" in
  let is_onnx_des   = is_fmt_in_des "onnx" in

  (* Helper: inject runtime-specific helper code into the node script. *)
  let make_injection ~enabled ~r_code ~py_code =
    if enabled then
      match runtime with
      | "R"      -> Printf.sprintf "      cat << 'EOF' >> node_script.R\n%s\nEOF" r_code
      | "Python" -> Printf.sprintf "      cat << 'EOF' >> node_script.py\n%s\nEOF" py_code
      | _        -> ""
    else ""
  in

  let t_json_r_code = {|
r_write_json <- function(object, path) {
  jsonlite::write_json(object, path, auto_unbox = TRUE, null = "null")
}
r_read_json <- function(path) {
  jsonlite::read_json(path, simplifyVector = TRUE)
}
|} in

  let t_csv_r_code = {|
r_write_csv <- function(object, path) {
  if (inherits(object, "data.frame")) {
    write.csv(object, path, row.names = FALSE)
  } else {
    write.csv(as.data.frame(object), path, row.names = FALSE)
  }
}
r_read_csv <- function(path) {
  read.csv(path, stringsAsFactors = FALSE)
}
|} in

  let t_csv_py_code = {|
import pandas as _pd
def py_write_csv(obj, path):
    if hasattr(obj, 'to_pandas'):
        obj = obj.to_pandas()
    if hasattr(obj, 'to_csv'):
        obj.to_csv(path, index=False)
    else:
        _pd.DataFrame(obj).to_csv(path, index=False)
def py_read_csv(path):
    return _pd.read_csv(path)
|} in

  let t_json_py_code = {|
import json
def py_write_json(obj, path):
    with open(path, "w") as f:
        json.dump(obj, f)
def py_read_json(path):
    with open(path) as f:
        return json.load(f)
|} in

  let t_pickle_py_code = {|
import os
import pickle

def serialize(obj, path):
    # Use standard pickle by default.
    # We only switch to cloudpickle/dill if we detect a complex plot object
    # that standard pickle likely cannot handle (due to lambdas/internal state).
    use_enhanced = False
    try:
        mod = type(obj).__module__
        if mod.startswith(("matplotlib", "seaborn", "plotly", "altair", "plotnine")):
            use_enhanced = True
    except Exception:
        pass

    if use_enhanced:
        try:
            import dill
            with open(path, "wb") as f:
                dill.dump(obj, f)
            return
        except Exception:
            pass
        try:
            import cloudpickle as cp
            with open(path, "wb") as f:
                cp.dump(obj, f)
            return
        except Exception:
            pass

    with open(path, "wb") as f:
        pickle.dump(obj, f)

def deserialize(path):
    # Try standard pickle first for maximum compatibility
    try:
        import pickle
        with open(path, "rb") as f:
            return pickle.load(f)
    except Exception:
        pass

    # Try dill next (more robust for Bokeh)
    try:
        import dill
        with open(path, "rb") as f:
            return dill.load(f)
    except Exception:
        pass
    
    # Try cloudpickle as last resort
    try:
        import cloudpickle as cp
        with open(path, "rb") as f:
            return cp.load(f)
    except Exception:
        pass
    
    # Final chance (if cloudpickle import failed but we didn't return)
    with open(path, "rb") as f:
        return pickle.load(f)
|} in

  let t_arrow_r_code = {|
r_write_arrow <- function(object, path) {
  arrow::write_ipc_file(as.data.frame(object), path)
}
r_read_arrow <- function(path) {
  arrow::read_ipc_file(path)
}
|} in

  let t_arrow_py_code = {|
import pyarrow as pa
import pyarrow.ipc as ipc
import pandas as pd

def py_write_arrow(df, path):
    if hasattr(df, 'to_arrow'):
        table = df.to_arrow()
    elif isinstance(df, pd.DataFrame):
        table = pa.Table.from_pandas(df)
    else:
        table = df
    with pa.OSFile(path, 'wb') as f:
        with ipc.new_file(f, table.schema) as writer:
            writer.write_table(table)

def py_read_arrow(path):
    with pa.OSFile(path, 'rb') as f:
        return ipc.open_file(f).read_pandas()
|} in

  let t_pmml_r_code = {|
r_write_pmml <- function(object, path) {
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
r_read_pmml <- function(path) {
  path
}
|} in

  let t_pmml_py_code = {|
import os
import subprocess
import tempfile
import pickle

def py_write_pmml(model, path):
    # Check if it's a statsmodels model
    is_sm = False
    try:
        import statsmodels.base.wrapper as sm_wrapper
        if isinstance(model, sm_wrapper.ResultsWrapper):
            is_sm = True
        else:
            # Fallback for different statsmodels versions or types
            kls = type(model).__name__
            if "ResultsWrapper" in kls or hasattr(model, 'save'):
                # Double check it's not a False positive (sklearn models don't have .save)
                if hasattr(model, 'model') and hasattr(model, 'params'):
                    is_sm = True
    except ImportError: pass

    if is_sm:
        return py_export_sm_model(model, path)

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

def py_export_sm_model(results, path):
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

def py_read_pmml(path):
    class JPMMLModel:
        def __init__(self, pmml_path):
            self.pmml_path = pmml_path
        
        def predict(self, df):
            import subprocess
            import tempfile
            import os
            import pandas as pd

            jar_path = os.environ.get("T_JPMML_EVALUATOR_JAR")
            if not jar_path or not os.path.exists(jar_path):
                raise RuntimeError("T_JPMML_EVALUATOR_JAR not found in environment.")

            with tempfile.TemporaryDirectory() as tmp:
                in_path = os.path.join(tmp, "input.csv")
                out_path = os.path.join(tmp, "output.csv")
                
                # Write input (CSV standardized bridge)
                df.to_csv(in_path, index=False)
                
                # Execute JPMML
                subprocess.run([
                    "java", "-jar", jar_path,
                    "--model", self.pmml_path,
                    "--input", in_path,
                    "--output", out_path
                ], check=True)
                
                # Read output
                return pd.read_csv(out_path)
    
    return JPMMLModel(path)
|} in

  let t_error_py_code = {|
import json
import os
import sys
import traceback

def py_write_error(msg, path):
    if isinstance(msg, dict) and msg.get("type") == "VError":
        err_info = msg
    else:
        traceback_text = msg if isinstance(msg, str) else str(msg)
        message_lines = [line for line in traceback_text.splitlines() if line.strip()]
        err_info = {
            "type": "VError",
            "code": "RuntimeError",
            "message": message_lines[-1].strip() if message_lines else traceback_text,
            "na_count": 0,
            "context": {
                "runtime_traceback": traceback_text,
                "node_status": "errored"
            },
            "location": None
        }
    with open(path, "w") as f:
        json.dump(err_info, f)
    with open(os.path.join(os.path.dirname(path), "class"), "w") as f:
        f.write("VError")

def py_is_error(obj):
    return isinstance(obj, dict) and obj.get("type") == "VError"

def py_write_warnings(warnings_list, path):
    cleaned = [str(w.message if hasattr(w, "message") else w) for w in warnings_list]
    if cleaned:
        with open(path, "w") as f:
            json.dump(cleaned, f)
|} in

  let t_error_r_code = {|
r_write_error <- function(msg, path) {
  if (is.list(msg) && !is.null(msg$type) && msg$type == "VError") {
    err_info <- msg
  } else {
    err_info <- list(
      type = "VError",
      code = "RuntimeError",
      message = as.character(msg),
      na_count = 0,
      context = list(
        runtime_traceback = as.character(msg),
        node_status = "errored"
      ),
      location = NULL
    )
  }
  jsonlite::write_json(err_info, path, auto_unbox = TRUE)
  writeLines("VError", file.path(dirname(path), "class"))
}

r_is_error <- function(obj) {
  is.list(obj) && !is.null(obj$type) && obj$type == "VError"
}

r_write_warnings <- function(warns, path) {
  if (length(warns) > 0) {
    jsonlite::write_json(as.character(warns), path, auto_unbox = TRUE)
  }
}
|} in

  let t_onnx_r_code = {|
r_write_onnx <- function(object, path) {
  # The 'onnx' R package provides Protobuf bindings but no direct model-to-onnx conversion for arbitrary R models (like lm, xgbtree).
  stop("ONNX serialization is not currently supported for R models in T. Consider using PMML (^pmml) for model interchange or training/exporting your model from Python.")
}

r_read_onnx <- function(path) {
  if (!requireNamespace("onnx", quietly = TRUE))
    stop("Package 'onnx' is required for ONNX deserialization in R.")
  if (exists("onnx", where="package:onnx") && !is.null(onnx::onnx$load_model)) {
    onnx::onnx$load_model(path)
  } else {
    onnx::load_from_file(path)
  }
}
|} in

  let t_onnx_py_code = {|
def _infer_n_features(model):
    import numpy as np
    if hasattr(model, 'n_features_in_'):
        return int(model.n_features_in_)
    if hasattr(model, 'coef_'):
        c = np.array(model.coef_)
        return c.shape[-1] if c.ndim >= 1 else 1
    if hasattr(model, 'in_features'):
        return int(model.in_features)
    modules = getattr(model, 'modules', None)
    if callable(modules):
        for module in model.modules():
            if hasattr(module, 'in_features'):
                return int(module.in_features)
    raise RuntimeError(
        "Unable to infer ONNX input feature count. "
        "Expected a scikit-learn model (n_features_in_, coef_), "
        "a PyTorch model (in_features, modules), or another model "
        "with explicit feature metadata."
    )

def _make_dummy_input(model):
    import torch
    return torch.randn(1, _infer_n_features(model))

def py_write_onnx(model, path):
    import numpy as np
    try:
        from skl2onnx import convert_sklearn
        from skl2onnx.common.data_types import FloatTensorType
        n_features = _infer_n_features(model)
        initial_types = [("input", FloatTensorType([None, n_features]))]
        onnx_model = convert_sklearn(model, initial_types=initial_types)
        with open(path, "wb") as f:
            f.write(onnx_model.SerializeToString())
        return path
    except ImportError:
        pass
    try:
        import torch
        dummy = _make_dummy_input(model)
        torch.onnx.export(model, dummy, path, opset_version=17)
        return path
    except ImportError:
        pass
    raise RuntimeError(
        "ONNX export in Python requires 'skl2onnx' (for scikit-learn models) "
        "or 'torch' (for PyTorch models). Install the appropriate package."
    )

def py_read_onnx(path):
    try:
        import onnxruntime as rt
        return rt.InferenceSession(path)
    except ImportError:
        raise RuntimeError(
            "ONNX deserialization requires 'onnxruntime'. "
            "Install it with: pip install onnxruntime"
        )
|} in

  let json_injection   = make_injection ~enabled:true  ~r_code:t_json_r_code  ~py_code:t_json_py_code in
  let csv_injection    = make_injection ~enabled:(is_csv_ser   || is_csv_des)   ~r_code:t_csv_r_code   ~py_code:t_csv_py_code in
  let arrow_injection  = make_injection ~enabled:(is_arrow_ser || is_arrow_des) ~r_code:t_arrow_r_code ~py_code:t_arrow_py_code in
  let pmml_injection   = make_injection ~enabled:(is_pmml_ser  || is_pmml_des)  ~r_code:t_pmml_r_code  ~py_code:t_pmml_py_code in
  let onnx_injection   = make_injection ~enabled:(is_onnx_ser  || is_onnx_des)  ~r_code:t_onnx_r_code  ~py_code:t_onnx_py_code in
  let pickle_injection =
    if runtime = "Python" then
      Printf.sprintf "      cat << 'EOF' >> node_script.py\n%s\nEOF" t_pickle_py_code
    else ""
  in

  let error_injection =
    match runtime with
    | "R"      -> Printf.sprintf "      cat << 'EOF' >> node_script.R\n%s\nEOF" t_error_r_code
    | "Python" -> Printf.sprintf "      cat << 'EOF' >> node_script.py\n%s\nEOF" t_error_py_code
    | _        -> ""
  in

  let visualization_r_code = {|
r_non_empty_string <- function(value) {
  is.character(value) && length(value) > 0 && !is.na(value[[1]]) && nzchar(value[[1]])
}

r_compact_named_list <- function(entries) {
  entries <- Filter(Negate(is.null), entries)
  if (length(entries) == 0) {
    list()
  } else {
    do.call(c, entries)
  }
}

r_mapping_to_list <- function(mapping) {
  if (is.null(mapping) || length(mapping) == 0) {
    return(list())
  }
  r_compact_named_list(lapply(names(mapping), function(name) {
    value <- mapping[[name]]
    label <- tryCatch(rlang::as_label(value), error = function(e) NULL)
    if (is.null(label) || !nzchar(label)) NULL else setNames(list(label), name)
  }))
}

r_labels_to_list <- function(plot) {
  label_keys <- c("title", "subtitle", "caption", "x", "y", "colour", "color", "fill")
  r_compact_named_list(lapply(label_keys, function(key) {
    value <- plot$labels[[key]]
    if (r_non_empty_string(value)) setNames(list(as.character(value[[1]])), key) else NULL
  }))
}

r_layers_to_list <- function(plot) {
  if (is.null(plot$layers) || length(plot$layers) == 0) {
    list()
  } else {
    as.list(vapply(plot$layers, function(layer) {
      geom_class <- class(layer$geom)[1]
      sub("^Geom", "", geom_class)
    }, character(1)))
  }
}

r_extract_plot_metadata <- function(object) {
  if (!inherits(object, "ggplot")) {
    return(NULL)
  }
  labels <- r_labels_to_list(object)
  title <- labels$title
  if (!r_non_empty_string(title)) {
    title <- NULL
  } else {
    title <- as.character(title[[1]])
  }
  mapping <- r_mapping_to_list(object$mapping)
  metadata <- list(
    class = "ggplot",
    backend = "R",
    title = title,
    mapping = mapping,
    labels = labels,
    layers = r_layers_to_list(object),
    `_display_keys` = c("class", "backend", "title", "mapping", "labels", "layers")
  )
  metadata
}

r_visual_class <- function(object) {
  metadata <- r_extract_plot_metadata(object)
  if (!is.null(metadata)) {
    metadata$class
  } else {
    as.character(class(object)[1])
  }
}

r_save_viz_metadata <- function(object, path) {
  metadata <- r_extract_plot_metadata(object)
  if (is.null(metadata)) {
    return(FALSE)
  }
  jsonlite::write_json(metadata, path, auto_unbox = TRUE, null = "null")
  TRUE
}
|} in

  let visualization_py_code = {|
import json

def _py_clean_mapping_value(value):
    text = str(value)
    if text.startswith("after_stat(") or text.startswith("stage("):
        return text
    if text.startswith("'") and text.endswith("'"):
        return text[1:-1]
    return text

def _py_compact_dict(entries):
    return {key: value for key, value in entries.items() if value not in (None, "", [], {})}

def _py_plotnine_mapping(mapping):
    if mapping is None:
        return {}
    return _py_compact_dict({key: _py_clean_mapping_value(value) for key, value in mapping.items()})

def _py_plotnine_labels(obj):
    labels_obj = getattr(obj, "labels", None)
    if labels_obj is None:
        return {}
    return _py_compact_dict({
        "title": getattr(labels_obj, "title", None),
        "subtitle": getattr(labels_obj, "subtitle", None),
        "caption": getattr(labels_obj, "caption", None),
        "x": getattr(labels_obj, "x", None),
        "y": getattr(labels_obj, "y", None),
        "color": getattr(labels_obj, "color", None),
        "fill": getattr(labels_obj, "fill", None),
    })

def _py_plotnine_layers(obj):
    layers = []
    for layer in getattr(obj, "layers", []) or []:
        geom = getattr(layer, "geom", None)
        geom_name = type(geom).__name__ if geom is not None else None
        if geom_name:
            layers.append(geom_name.replace("geom_", ""))
    return layers

def _py_matplotlib_layers(ax):
    layers = []
    if getattr(ax, "lines", None):
        layers.extend(type(line).__name__ for line in ax.lines)
    if getattr(ax, "collections", None):
        layers.extend(type(collection).__name__ for collection in ax.collections)
    if getattr(ax, "patches", None):
        layers.extend(type(patch).__name__ for patch in ax.patches if type(patch).__name__ != "Spine")
    if getattr(ax, "images", None):
        layers.extend(type(image).__name__ for image in ax.images)
    deduped = []
    for layer in layers:
        if layer not in deduped:
            deduped.append(layer)
    return deduped

def py_extract_plot_metadata(obj):
    try:
        from plotnine.ggplot import ggplot as PlotnineGGPlot
    except Exception:
        PlotnineGGPlot = None
    if PlotnineGGPlot is not None and isinstance(obj, PlotnineGGPlot):
        labels = _py_plotnine_labels(obj)
        return {
            "class": "plotnine",
            "backend": "Python",
            "title": labels.get("title"),
            "mapping": _py_plotnine_mapping(getattr(obj, "mapping", None)),
            "labels": labels,
            "layers": _py_plotnine_layers(obj),
            "_display_keys": ["class", "backend", "title", "mapping", "labels", "layers"],
        }

    try:
        from matplotlib.figure import Figure as MatplotlibFigure
        from matplotlib.axes import Axes as MatplotlibAxes
    except Exception:
        MatplotlibFigure = ()
        MatplotlibAxes = ()

    figure = None
    axes = None
    # Default title; backend-specific extraction below can replace it, and the
    # later figure/axes fallback only runs when the title is still empty.
    title = None
    viz_class = "matplotlib"

    # Seaborn support
    try:
        # Check by module name to avoid hard dependency on seaborn in the extractor
        obj_type = type(obj)
        if obj_type.__module__.startswith("seaborn"):
            viz_class = "seaborn"
            if hasattr(obj, "fig"):
                figure = obj.fig
            elif hasattr(obj, "figure"):
                figure = obj.figure
            if figure and not axes:
                axes = figure.axes[0] if getattr(figure, "axes", None) else None
    except Exception:
        pass

    # Plotly support
    try:
        obj_type = type(obj)
        if obj_type.__module__.startswith("plotly"):
            viz_class = "plotly"
            if hasattr(obj, "layout") and obj.layout.title:
                t = obj.layout.title
                if hasattr(t, "text"):
                    title = t.text
                elif isinstance(t, str):
                    title = t
    except Exception:
        pass

    # Altair support
    try:
        if type(obj).__module__.startswith("altair"):
            viz_class = "altair"
            if hasattr(obj, "title") and obj.title:
                title = str(obj.title)
    except Exception:
        pass

    if figure is None and axes is None:
        if MatplotlibFigure and isinstance(obj, MatplotlibFigure):
            figure = obj
            axes = obj.axes[0] if getattr(obj, "axes", None) else None
        elif MatplotlibAxes and isinstance(obj, MatplotlibAxes):
            axes = obj
            figure = getattr(obj, "figure", None)
    if figure is None and axes is None:
        if viz_class not in ["plotly", "altair"]:
            return None
    else:
        suptitle = getattr(figure, "_suptitle", None) if figure is not None else None
        if title is None and suptitle is not None:
            text = suptitle.get_text()
            if text:
                title = text
        if title is None and axes is not None:
            text = axes.get_title()
            if text:
                title = text

    labels = _py_compact_dict({
        "title": title,
        "x": axes.get_xlabel() if axes is not None else None,
        "y": axes.get_ylabel() if axes is not None else None,
    })
    return {
        "class": viz_class,
        "backend": "Python",
        "title": title,
        "mapping": {},
        "labels": labels,
        "layers": _py_matplotlib_layers(axes) if axes is not None else [],
        "_display_keys": ["class", "backend", "title", "mapping", "labels", "layers"],
    }

def py_visual_class(obj):
    metadata = py_extract_plot_metadata(obj)
    if metadata is not None:
        return metadata.get("class", "matplotlib")
    return type(obj).__name__

def py_save_viz_metadata(obj, path):
    metadata = py_extract_plot_metadata(obj)
    if metadata is not None:
        with open(path, "w") as f:
            json.dump(metadata, f)
|} in

  let visualization_injection =
    match runtime with
    | "R" -> Printf.sprintf "      cat << 'EOF' >> node_script.R\n%s\nEOF" visualization_r_code
    | "Python" -> Printf.sprintf "      cat << 'EOF' >> node_script.py\n%s\nEOF" visualization_py_code
    | _ -> ""
  in

  (* Logic for deserializing dependencies *)
  let deps_script_lines =
    if runtime = "Quarto" || runtime = "sh" then
      ""
    else
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
        let strategy_expr = match deserializer.Ast.node with
          | Ast.ListLit items -> (match lookup_in_list dep_name items with Some e -> e | None -> Ast.mk_expr (Ast.Var "default"))
          | Ast.DictLit items -> (match lookup_in_dict dep_name items with Some e -> e | None -> Ast.mk_expr (Ast.Var "default"))
          | Ast.Value (Ast.VDict items) ->
              (match List.assoc_opt dep_name items with
               | Some v -> Ast.mk_expr (Ast.Value v)
               | None -> Ast.mk_expr (Ast.Var "default"))
          | _ -> deserializer

        in
        let strategy_is_string = match strategy_expr.Ast.node with Ast.Value (Ast.VString _) -> true | _ -> false in
        let strategy = Nix_unparse.expr_to_string strategy_expr in

        let read_fns = match runtime with
          | "R" -> [ "json", "r_read_json"; "arrow", "r_read_arrow"; "pmml", "r_read_pmml"; "onnx", "r_read_onnx"; "csv", "r_read_csv"; ]
          | "Python" -> [ "json", "py_read_json"; "arrow", "py_read_arrow"; "pmml", "py_read_pmml"; "onnx", "py_read_onnx"; "csv", "py_read_csv"; ]
          | _ -> [ "json", "t_read_json"; "arrow", "read_arrow"; "pmml", "t_read_pmml"; "onnx", "t_read_onnx"; "csv", "read_csv"; ]
        in
        let des_node_val = eval_expr_safe strategy_expr in
        let des_fn = match get_format des_node_val with
          | Some fmt ->
              (match get_polyglot_snippet ~lang:runtime ~kind:"reader" des_node_val with
               | Some snippet -> snippet
               | None -> List.assoc_opt fmt read_fns |> Option.value ~default:fmt)
          | None ->
            if strategy = "default" then
              (if runtime = "R" then "readRDS" else if runtime = "Python" then "deserialize" else "deserialize")
            else if strategy_is_string then
              (match List.assoc_opt strategy read_fns with Some fn -> fn | None -> strategy)
            else
              strategy
        in
        
        let dep_var = dep_env_var_name dep_name in
        match runtime with
        | "R" ->
            Printf.sprintf {|      echo "if (file.exists(file.path(\"$%s\", \"class\")) && readLines(file.path(\"$%s\", \"class\"), 1) == \"VError\") {" >> node_script.R
      echo "  %s <- r_read_json(file.path(\"$%s\", \"artifact\"))" >> node_script.R
      echo "} else {" >> node_script.R
      echo "  %s <- %s(file.path(\"$%s\", \"artifact\"))" >> node_script.R
      echo "}" >> node_script.R|} dep_var dep_var dep_name dep_var dep_name des_fn dep_var
        | "Python" ->
            Printf.sprintf {|      echo "if os.path.exists(os.path.join(\"$%s\", \"class\")) and open(os.path.join(\"$%s\", \"class\")).read().strip() == \"VError\":" >> node_script.py
      echo "    %s = py_read_json(os.path.join(\"$%s\", \"artifact\"))" >> node_script.py
      echo "else:" >> node_script.py
      echo "    %s = %s(os.path.join(\"$%s\", \"artifact\"))" >> node_script.py|} dep_var dep_var dep_name dep_var dep_name des_fn dep_var
        | _ ->
            Printf.sprintf "      echo \"%s = %s(\\\"$%s/artifact\\\")\" >> node_script.%s" dep_name des_fn dep_var ext
      in
      deps
      |> List.map get_des_call
      |> String.concat "\n"
  in
  let quarto_read_node_substitutions =
    match runtime, script with
    | "Quarto", Some script_path ->
        deps
      |> List.map (fun d ->
          let double_quoted_read_node = Printf.sprintf {|read_node(\"%s\")|} d in
          let double_quoted_store_path = Printf.sprintf "'%s/artifact'" ("$" ^ dep_env_var_name d) in
          let single_quoted_read_node = Printf.sprintf {|read_node('%s')|} d in
          let single_quoted_store_path = Printf.sprintf "'%s/artifact'" ("$" ^ dep_env_var_name d) in
          Printf.sprintf
            {|      sed -i -e "s|%s|%s|g" -e "s|%s|%s|g" %s|}
            double_quoted_read_node
            double_quoted_store_path
            single_quoted_read_node
            single_quoted_store_path
            (shell_single_quote script_path))
        |> String.concat "\n"
    | _ -> ""
  in

  let expr_s = Nix_unparse.unparse_expr expr in
  let ser_expr_is_string = match serializer.Ast.node with Ast.Value (Ast.VString _) -> true | _ -> false in
  let ser_s = Nix_unparse.expr_to_string serializer in
  let uses_default_serializer = ser_s = "default" in
  let ser_call =
    let write_fns = match runtime with
      | "R" -> [ "json", "r_write_json"; "arrow", "r_write_arrow"; "pmml", "r_write_pmml"; "onnx", "r_write_onnx"; "csv", "r_write_csv"; ]
      | "Python" -> [ "json", "py_write_json"; "arrow", "py_write_arrow"; "pmml", "py_write_pmml"; "onnx", "py_write_onnx"; "csv", "py_write_csv"; ]
      | _ -> [ "json", "t_write_json"; "arrow", "write_arrow"; "pmml", "t_write_pmml"; "onnx", "t_write_onnx"; "csv", "write_csv"; ]
    in
    match get_format ser_val with
    | Some fmt ->
        (match get_polyglot_snippet ~lang:runtime ~kind:"writer" ser_val with
         | Some snippet -> snippet
         | None -> List.assoc_opt fmt write_fns |> Option.value ~default:fmt)
    | None ->
        if ser_s = "default" then
          (if runtime = "R" then "saveRDS" else if runtime = "Python" then "serialize" else "serialize")
        else if ser_expr_is_string then
          (match List.assoc_opt ser_s write_fns with Some fn -> fn | None -> ser_s)
        else
          ser_s
  in

  let is_raw_code = match expr.Ast.node with RawCode _ -> true | _ -> false in

  let r_emit_artifact value_name =
    let viz_call = Printf.sprintf "  r_save_viz_metadata(%s, file.path(Sys.getenv('out'), 'viz'))" value_name in
    let artifact_path = "file.path(Sys.getenv('out'), 'artifact')" in
    if uses_default_serializer then
      Printf.sprintf {|%s
  %s(%s, %s)|} viz_call ser_call value_name artifact_path
    else
      Printf.sprintf {|  %s(%s, %s)|} ser_call value_name artifact_path
  in

  let py_emit_artifact value_name =
    let viz_call = Printf.sprintf "    py_save_viz_metadata(%s, os.path.join(os.environ['out'], 'viz'))" value_name in
    let artifact_path = "os.path.join(os.environ['out'], 'artifact')" in
    if uses_default_serializer then
      Printf.sprintf {|%s
    %s(%s, %s)|} viz_call ser_call value_name artifact_path
    else
      Printf.sprintf {|    %s(%s, %s)|} ser_call value_name artifact_path
  in

  let is_import_line line =
    let l = String.trim line in
    if runtime = "Python" then
      String.starts_with ~prefix:"import " l || String.starts_with ~prefix:"from " l
    else if runtime = "R" then
      String.starts_with ~prefix:"library(" l || String.starts_with ~prefix:"require(" l
    else false
  in

  let hoisted_imports =
    if is_raw_code then
      let lines = String.split_on_char '\n' expr_s in
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

  let is_assignment_stmt s =
    let depth = ref 0 in
    let found_assignment = ref false in
    for i = 0 to String.length s - 1 do
      match s.[i] with
      | '(' | '[' | '{' -> incr depth
      | ')' | ']' | '}' -> if !depth > 0 then decr depth
      | '=' when !depth = 0 ->
          let is_comparison =
            (i > 0 && (match s.[i-1] with '<' | '>' | '!' | '=' -> true | _ -> false)) ||
            (i < String.length s - 1 && s.[i+1] = '=')
          in
          if not is_comparison then found_assignment := true
      | _ -> ()
    done;
    !found_assignment
  in

  let get_assignment_name s =
    let depth = ref 0 in
    let found_pos = ref (-1) in
    for i = 0 to String.length s - 1 do
      if !found_pos = -1 then
        match s.[i] with
        | '(' | '[' | '{' -> incr depth
        | ')' | ']' | '}' -> if !depth > 0 then decr depth
        | '=' when !depth = 0 ->
            let is_comparison =
              (i > 0 && (match s.[i-1] with '<' | '>' | '!' | '=' -> true | _ -> false)) ||
              (i < String.length s - 1 && s.[i+1] = '=')
            in
            if not is_comparison then found_pos := i
        | _ -> ()
    done;
    if !found_pos = -1 then None
    else
      let left = String.sub s 0 !found_pos in
      let rec trim_right_ops t =
        if t = "" then ""
        else
          let last = t.[String.length t - 1] in
          if List.mem last ['+'; '-'; '*'; '/'; '%'; '&'; '|'; '^'; '<'; '>'; ':'] then
            trim_right_ops (String.sub t 0 (String.length t - 1) |> String.trim)
          else t
      in
      let t = String.trim left |> trim_right_ops in
      let name = match String.split_on_char ':' t with
        | [] -> t
        | h :: _ -> String.trim h
      in
      Some name
  in

  (* expr_s with import/library lines removed, for use in assignment wrappers *)
  let expr_s_no_imports, _python_was_auto_returned =
    if is_raw_code then
      let lines = String.split_on_char '\n' expr_s in
      let is_comment_line line =
        let l = String.trim line in
        if runtime = "Python" then String.starts_with ~prefix:"#" l
        else if runtime = "R" then String.starts_with ~prefix:"#" l
        else false
      in
      let non_imports = List.filter (fun l -> not (is_import_line l) && not (is_comment_line l)) lines in
      (* Remove leading/trailing blank lines after stripping *)
      let non_imports = List.filter (fun l -> String.trim l <> "") non_imports in
      if runtime = "Python" && not (raw_assigns_to name expr_s) then
         match List.rev non_imports with
         | last :: rest when
             let l = String.trim last in
             not (is_assignment_stmt l) &&
             not (String.starts_with ~prefix:"print(" l) &&
             not (String.starts_with ~prefix:"raise " l) &&
             not (String.starts_with ~prefix:"import " l) &&
             not (String.starts_with ~prefix:"from " l) &&
             not (String.starts_with ~prefix:"if " l) &&
             not (String.starts_with ~prefix:"for " l) &&
             not (String.starts_with ~prefix:"while " l) &&
             not (String.starts_with ~prefix:"with " l) &&
             not (String.starts_with ~prefix:"def " l) &&
             not (String.starts_with ~prefix:"class " l) &&
             not (String.starts_with ~prefix:"assert " l) &&
             not (String.starts_with ~prefix:"yield " l) &&
             not (String.starts_with ~prefix:"del " l) &&
             not (String.starts_with ~prefix:"global " l) &&
             not (String.starts_with ~prefix:"nonlocal " l) &&
             not (String.starts_with ~prefix:"return " l)
             ->
             let last_trimmed = String.trim last in
             let spaces = ref 0 in
             while !spaces < String.length last && (last.[!spaces] = ' ' || last.[!spaces] = '\t') do
               incr spaces
             done;
             let ind = String.sub last 0 !spaces in
             String.concat "\n" (List.rev ((ind ^ "return " ^ last_trimmed) :: rest)), true
         | last :: rest ->
             (match get_assignment_name last with
              | Some n ->
                  let spaces = ref 0 in
                  while !spaces < String.length last && (last.[!spaces] = ' ' || last.[!spaces] = '\t') do
                    incr spaces
                  done;
                  let ind = String.sub last 0 !spaces in
                  String.concat "\n" (List.rev ((ind ^ "return " ^ n) :: last :: rest)), true
              | None -> String.concat "\n" non_imports, false)
         | _ -> String.concat "\n" non_imports, false
      else if runtime = "T" then
         match List.rev non_imports with
         | last :: rest when (is_assignment_stmt last) ->
             (match get_assignment_name last with
              | Some n -> String.concat "\n" (List.rev (n :: last :: rest)), false
              | None -> String.concat "\n" non_imports, false)
         | _ -> String.concat "\n" non_imports, false
      else
        String.concat "\n" non_imports, false
    else expr_s, false
  in




  let assign_script_lines =
    if runtime = "Quarto" then
      ""
    else match script with
    | Some script_path ->
        (* Script-based node: source the external script file.
           The script should assign the result to a variable named after the node.
           All pipeline dependencies are already available as variables from deps_script_lines.
           Use shell_single_quote to safely embed the source/exec call in an echo command. *)
        if runtime = "sh" then
          let shell_cmd = match shell with Some s -> s | None -> "sh" in
          let script_tokens = shell_cmd :: shell_args_tokens @ [ script_path ] @ sh_cli_args_tokens in
          Printf.sprintf "      printf '%%s\\n' %s >> node_script.sh"
            (shell_single_quote ("exec " ^ shell_quote_words script_tokens))
        else if runtime = "R" then
          let r_source = shell_single_quote (Printf.sprintf {|source("%s")|} script_path) in
          let r_ser = shell_single_quote (Printf.sprintf {|%s
  writeLines(r_visual_class(%s), file.path(Sys.getenv('out'), 'class'))|} (r_emit_artifact name) name) in
          Printf.sprintf {|      echo %s >> node_script.R
      echo %s >> node_script.R
|} r_source r_ser
        else if runtime = "Python" then
          let py_exec = shell_single_quote (Printf.sprintf {|exec(open("%s").read(), globals())|} script_path) in
          let py_ser = shell_single_quote (Printf.sprintf {|%s
    with open(os.path.join(os.environ['out'], 'class'), 'w') as f:
        f.write(py_visual_class(%s))|} (py_emit_artifact name) name) in
          Printf.sprintf {|      echo %s >> node_script.py
      echo %s >> node_script.py
|} py_exec py_ser
        else
          let t_import = shell_single_quote (Printf.sprintf {|      import "%s"|} script_path) in
          Printf.sprintf {|      echo %s >> node_script.t
      echo "      res1 = %s(%s, \"$out/artifact\")" >> node_script.t
      echo "      if (is_error(res1)) { print(\"Serialization failed:\"); print(res1); exit(1) } else { 0 }" >> node_script.t
      echo "      res2 = write_text(\"$out/class\", type(%s))" >> node_script.t
      echo "      if (is_error(res2)) { print(\"Class write failed:\"); print(res2); exit(1) } else { 0 }" >> node_script.t|} t_import ser_call name name
    | None ->
    if runtime = "R" then
      if is_raw_code then
        Printf.sprintf {|      echo "captured_warns <- list()" >> node_script.R
      echo "%s <- withCallingHandlers({" >> node_script.R
      echo "  local({" >> node_script.R
      echo "    tryCatch({" >> node_script.R
      cat <<'EOF' >> node_script.R
%s
EOF
      echo "    }, error = function(e) {" >> node_script.R
      echo "      r_write_error(e, \"$out/artifact\")" >> node_script.R
      echo "      quit(save = 'no', status = 0)" >> node_script.R
      echo "    })" >> node_script.R
      echo "  })" >> node_script.R
      echo "}, warning = function(w) {" >> node_script.R
      echo "  captured_warns <<- append(captured_warns, conditionMessage(w))" >> node_script.R
      echo "  invokeRestart('muffleWarning')" >> node_script.R
      echo "})" >> node_script.R
       echo "if (r_is_error(%s)) {" >> node_script.R
       echo "  r_write_error(%s, file.path(Sys.getenv('out'), 'artifact'))" >> node_script.R
       echo "} else {" >> node_script.R
       cat <<'EOF' >> node_script.R
%s
EOF
       echo "  writeLines(r_visual_class(%s), file.path(Sys.getenv('out'), 'class'))" >> node_script.R
       echo "  r_write_warnings(captured_warns, file.path(Sys.getenv('out'), 'warnings'))" >> node_script.R
       echo "}" >> node_script.R|} name expr_s_no_imports name name (r_emit_artifact name) name
      else
        Printf.sprintf {|      echo "captured_warns <- list()" >> node_script.R
      echo "tryCatch({" >> node_script.R
      echo "  %s <- withCallingHandlers({" >> node_script.R
      cat <<'EOF' >> node_script.R
%s <- %s
EOF
      echo "  }, warning = function(w) {" >> node_script.R
      echo "    captured_warns <<- append(captured_warns, conditionMessage(w))" >> node_script.R
      echo "    invokeRestart('muffleWarning')" >> node_script.R
      echo "  })" >> node_script.R
      echo "}, error = function(e) {" >> node_script.R
      echo "  r_write_error(e, \"$out/artifact\")" >> node_script.R
      echo "  quit(save = 'no', status = 0)" >> node_script.R
      echo "})" >> node_script.R
       echo "if (r_is_error(%s)) {" >> node_script.R
       echo "  r_write_error(%s, file.path(Sys.getenv('out'), 'artifact'))" >> node_script.R
       echo "} else {" >> node_script.R
       cat <<'EOF' >> node_script.R
%s
EOF
       echo "  writeLines(r_visual_class(%s), file.path(Sys.getenv('out'), 'class'))" >> node_script.R
       echo "  r_write_warnings(captured_warns, file.path(Sys.getenv('out'), 'warnings'))" >> node_script.R
       echo "}" >> node_script.R|} name name expr_s name name (r_emit_artifact name) name
    else if runtime = "Python" then
      if is_raw_code then
        if raw_assigns_to name expr_s then
           (* Statement-style: raw code explicitly assigns to node name — use as-is *)
           Printf.sprintf {|      echo "import warnings" >> node_script.py
      echo "try:" >> node_script.py
      echo "    with warnings.catch_warnings(record=True) as captured_warns:" >> node_script.py
      echo "        warnings.simplefilter('always')" >> node_script.py
      cat <<'EOF' >> node_script.py
%s
EOF
      echo "except Exception as e:" >> node_script.py
      echo "    py_write_error(traceback.format_exc(), \"$out/artifact\")" >> node_script.py
      echo "    sys.exit(0)" >> node_script.py
      echo "if py_is_error(%s):" >> node_script.py
      echo "    py_write_error(%s, os.path.join(os.environ['out'], 'artifact'))" >> node_script.py
      echo "else:" >> node_script.py
      cat <<'EOF' >> node_script.py
%s
EOF
      echo "    with open(os.path.join(os.environ['out'], 'class'), 'w') as f: f.write(py_visual_class(%s))" >> node_script.py
      echo "    py_write_warnings(captured_warns, os.path.join(os.environ['out'], 'warnings'))" >> node_script.py|} (indent_string expr_s 8) name name (py_emit_artifact name) name
        else
          let globals_decl =
            if deps = [] then ""
            else Printf.sprintf "    global %s\n" (String.concat ", " deps)
          in
          Printf.sprintf {|      echo "def __node_runner():" >> node_script.py
%s      cat <<'EOF' >> node_script.py
%s
EOF
      echo "    return" >> node_script.py
      echo "try:" >> node_script.py
      echo "    import warnings" >> node_script.py
      echo "    with warnings.catch_warnings(record=True) as captured_warns:" >> node_script.py
      echo "        warnings.simplefilter('always')" >> node_script.py
      echo "        %s = __node_runner()" >> node_script.py
      echo "except Exception as e:" >> node_script.py
      echo "    py_write_error(traceback.format_exc(), os.path.join(os.environ['out'], 'artifact'))" >> node_script.py
      echo "    sys.exit(0)" >> node_script.py
      echo "if py_is_error(%s):" >> node_script.py
      echo "    py_write_error(%s, os.path.join(os.environ['out'], 'artifact'))" >> node_script.py
      echo "else:" >> node_script.py
      cat <<'EOF' >> node_script.py
%s
EOF
      echo "    with open(os.path.join(os.environ['out'], 'class'), 'w') as f: f.write(py_visual_class(%s))" >> node_script.py
      echo "    py_write_warnings(captured_warns, os.path.join(os.environ['out'], 'warnings'))" >> node_script.py|}
            (if globals_decl = "" then "" else Printf.sprintf "      echo %s >> node_script.py\n" (shell_single_quote globals_decl))
            (indent_string expr_s_no_imports 4) name name name (py_emit_artifact name) name
      else
        Printf.sprintf {|      echo "import warnings" >> node_script.py
      echo "try:" >> node_script.py
      echo "    with warnings.catch_warnings(record=True) as captured_warns:" >> node_script.py
      echo "        warnings.simplefilter('always')" >> node_script.py
      cat <<'EOF' >> node_script.py
%s
EOF
      echo "except Exception as e:" >> node_script.py
      echo "    py_write_error(traceback.format_exc(), os.path.join(os.environ['out'], 'artifact'))" >> node_script.py
      echo "    sys.exit(0)" >> node_script.py
      echo "if py_is_error(%s):" >> node_script.py
      echo "    py_write_error(%s, os.path.join(os.environ['out'], 'artifact'))" >> node_script.py
      echo "else:" >> node_script.py
      cat <<'EOF' >> node_script.py
%s
EOF
      echo "    with open(os.path.join(os.environ['out'], 'class'), 'w') as f: f.write(py_visual_class(%s))" >> node_script.py
      echo "    py_write_warnings(captured_warns, os.path.join(os.environ['out'], 'warnings'))" >> node_script.py|} (indent_string (Printf.sprintf "%s = %s" name expr_s) 8) name name (py_emit_artifact name) name
    else if runtime = "sh" then
      (match expr.Ast.node with
      | RawCode { raw_text; _ } ->
          Printf.sprintf "      cat <<'EOF' >> node_script.sh\n%s\nEOF" raw_text
      | Value (VString cmd) | Value (VSymbol cmd) ->
          if shell = None && shell_args_tokens = [] && sh_cli_args_tokens <> [] && is_simple_exec_command cmd then
            let set_args = shell_set_args_block sh_cli_args_tokens in
            Printf.sprintf {|%s      printf '%%s\n' %s >> node_script.sh|}
              set_args
              (shell_single_quote (Printf.sprintf "exec %s \"$@\"" (shell_single_quote cmd)))
          else
            let set_args = shell_set_args_block sh_cli_args_tokens in
            Printf.sprintf {|%s      cat <<'EOF' >> node_script.sh
%s
EOF|} set_args cmd
      | _ -> "      printf '%%s\\n' true >> node_script.sh")
    else (* T runtime *)
      if is_raw_code then
        Printf.sprintf {|      echo "      %s = {" >> node_script.t
      cat <<'EOF' >> node_script.t
%s
EOF
      echo "      }" >> node_script.t
      echo "      res1 = %s(%s, \"$out/artifact\")" >> node_script.t
      echo "      if (is_error(res1)) { print(\"Serialization failed:\"); print(res1); exit(1) } else { 0 }" >> node_script.t
      echo "      res2 = write_text(\"$out/class\", type(%s))" >> node_script.t
      echo "      if (is_error(res2)) { print(\"Class write failed:\"); print(res2); exit(1) } else { 0 }" >> node_script.t|} name expr_s_no_imports ser_call name name
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
    | "Quarto" ->
        let cli_block =
          if quarto_cli_args_block = "" then ""
          else quarto_cli_args_block ^ "\n"
        in
        Printf.sprintf {|
      rm -rf .quarto-output
      export HOME=$TMPDIR
      export QUARTO_R=${r-env}/bin/R
      export QUARTO_PYTHON=${py-env}/bin/python
      cli_args=()
%s      quarto "''${cli_args[@]}"
      if [ -d .quarto-output ]; then
        cp -r .quarto-output $out/artifact
      elif [ -d "$(dirname "%s")/.quarto-output" ]; then
        cp -r "$(dirname "%s")/.quarto-output" $out/artifact
      else
        echo "ERROR: .quarto-output not found."
        find . -name ".quarto-output" -type d
        ls -R
        exit 1
      fi
      echo "QuartoOutput" > $out/class|} cli_block (match script with Some s -> s | None -> ".") (match script with Some s -> s | None -> ".")
    | "sh" ->
        let shell_cmd = match shell with Some s -> s | None -> "sh" in
        let launcher =
          if shell_uses_command_string shell_args_tokens then
            String.concat " "
              (shell_single_quote shell_cmd
               :: List.map shell_single_quote shell_args_tokens
               @ [ shell_single_quote ". ./node_script.sh" ])
          else
            String.concat " "
              (shell_single_quote shell_cmd
               :: List.map shell_single_quote shell_args_tokens
               @ [ shell_single_quote "node_script.sh" ])
        in
        let hermetic_env =
          let node_env =
            env_vars
            |> List.filter_map (fun (key, value) ->
              if not (is_valid_env_var_name key) then
                None
              else
              match env_value_to_string value with
              | Some s -> Some (Printf.sprintf "%s=%s" key (shell_single_quote s))
              | None -> None)
          in
          let dep_env =
            deps
            |> List.map (fun dep ->
              let env_name = dep_env_var_name dep in
              Printf.sprintf "%s=\"$%s\"" env_name env_name)
          in
          String.concat " "
            ([ "env -i"; "HOME=\"$TMPDIR\""; "PATH=\"$PATH\""; "TMPDIR=\"$TMPDIR\"" ]
             @ dep_env @ node_env)
        in
        Printf.sprintf "%s %s > $out/artifact\n      echo ShellOutput > $out/class" hermetic_env launcher
    | _ -> "t run --unsafe --mode repl node_script.t"
  in

  Printf.sprintf {|
  %s = stdenv.mkDerivation {
    name = "%s";
    buildInputs = [ tBin %s ] ++ globalBuildInputs;
    T_JPMML_STATSMODELS_JAR = "${pkgs.jpmml-statsmodels}/share/java/jpmml-statsmodels.jar";
    T_JPMML_EVALUATOR_JAR = "${pkgs.jpmml-evaluator}/share/java/jpmml-evaluator.jar";
    MPLCONFIGDIR = ".";
%s
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
 |} name name deps_inputs src_block env_var_block deps_exports ext error_injection visualization_injection json_injection csv_injection arrow_injection pmml_injection onnx_injection pickle_injection imports_echo source_files hoisted_imports deps_script_lines quarto_read_node_substitutions assign_script_lines run_cmd
