import stats
import dataframe

p = pipeline {
    data_node = node(
        command = <{
            library(faraway)
            data(hsb)
            # Select relevant columns and handle factors
            # We convert binary target to integer for easier comparison
            hsb$target <- as.integer(hsb$prog == "academic")
            # We keep factors as is for the formula-based fitting in R and Python
            hsb
        }>,
        runtime = R,
        serializer = "arrow"
    );

    r_model_node = node(
        command = <{
            # Logistic regression as in the article
            # Formula: target ~ ses + schtyp + read + write + science + socst
            glm(target ~ ses + schtyp + read + write + science + socst, 
                family = binomial(link = "logit"), 
                data = data_node)
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    );

    py_model_node = node(
        command = <{
import statsmodels.api as sm
import statsmodels.formula.api as smf
import os

# Fit GLM using formula API (handles categorical 'ses' and 'schtyp' automatically)
# We expect data_node to have strings/factors that statsmodels can handle
model = smf.glm(formula='target ~ ses + schtyp + read + write + science + socst',
                data=data_node, 
                family=sm.families.Binomial()).fit()

t_write_pmml(model, os.path.expandvars("$out/artifact"))
        }>,
        runtime = Python,
        serializer = "pmml",
        deserializer = "arrow"
    )
}

print("Building HSB (Binary Logistic) pipeline...")
res = build_pipeline(p)

if (is_error(res)) {
    print("Pipeline build failed:")
    print(res)
} else {
    print("Build successful.")
    
    df = read_node("data_node")
    r_model = read_node("r_model_node")
    py_model = read_node("py_model_node")
    
    print("\n--- R Model Summary ---")
    s_r = summary(r_model)
    print(s_r)
    
    print("\n--- Python Model Summary ---")
    s_py = summary(py_model)
    print(s_py)
    
    print("\nComparing R and Python coefficients...")
    -- Both should have seslow, sesmiddle, schtyppublic etc.
    -- We can compare them by joining the tidy dataframes
    
    print("\nR Coefficients:")
    print(r_model.coefficients)
    
    print("\nPython Coefficients:")
    print(py_model.coefficients)
    
    print("\nComputing predictions in T (R Model)...")
    preds_r = predict(df, r_model)
    
    print("Computing predictions in T (Python Model)...")
    preds_py = predict(df, py_model)
    
    mae = mean(abs(preds_r .- preds_py))
    print("\nMAE between R and Python predictions in T:")
    print(mae)
    
    if (mae < 1e-4) {
        print("SUCCESS: Predictions from both models match perfectly in T!")
    } else {
        print("WARNING: Significant difference in predictions.")
    }
}
