-- tests/pipeline/test_pmml_inspection.t

p = pipeline {
    data_node = node(
        command = <{ read_csv("tests/pipeline/data/mtcars_simple.csv") }>,
        runtime = T,
        serializer = "arrow"
    );
    
    r_model = node(
        command = <{
            lm(mpg ~ wt + hp, data = data_node)
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    );
    
    t_inspect = node(
        command = <{
            model = r_model
            
            [
                nobs: nobs(model),
                df_residual: df_residual(model),
                sigma: sigma(model),
                coef: coef(model),
                conf_int: conf_int(model),
                vcov: vcov(model),
                score: score(data_node, model)
            ]
        }>,
        runtime = T,
        deserializer = [r_model: "pmml", data_node: "arrow"]
    )
}

res = build_pipeline(p)
if (is_error(res)) {
    print("Pipeline failed:", res)
    exit(1)
}

-- Print results of inspection
print("--- Inspection Results (from T node via PMML) ---")
inspect_res = read_node("t_inspect")
print(inspect_res)
print("--- End of Results ---")

print("SUCCESS")
