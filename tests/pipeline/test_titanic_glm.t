
p = pipeline {
    data_node = node(
        command = <{
            # Use local file (already wget-ed)
            df <- read.csv("titanic.csv")
            # Select numeric predictors and target
            df <- df[, c("Survived", "Pclass", "Age", "Fare")]
            df <- na.omit(df)
            df
        }>,
        runtime = R,
        serializer = "arrow"
    );

    r_model_node = node(
        command = <{
            data_node$Survived <- as.factor(data_node$Survived)
            glm(Survived ~ Pclass + Age + Fare, data = data_node, family = binomial(link = "logit"))
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    );

    py_model_node = node(
        command = <{
import statsmodels.api as sm
# Select predictors and add constant
X = data_node[['Pclass', 'Age', 'Fare']]
X = sm.add_constant(X)
y = data_node['Survived']
# Fit model using matrix API
py_model_node = sm.GLM(y, X, family=sm.families.Binomial()).fit()
import os
t_write_pmml(py_model_node, os.path.expandvars("$out/artifact"))
        }>,
        runtime = Python,
        serializer = "pmml",
        deserializer = "arrow"
    )
}

print("Building Titanic GLM pipeline (R + Python)...")
res = build_pipeline(p, verbose=1)

if (is_error(res)) {
    print("Pipeline build failed:")
    print(res)
} else {
    print("Reading artifacts...")
    df_clean = read_node("data_node")
    r_model    = read_node("r_model_node")
    py_model   = read_node("py_model_node")

    print("Computing predictions in T (R Model)...")
    t_preds_r = predict(df_clean, r_model)

    print("Computing predictions in T (Python Model)...")
    t_preds_py = predict(df_clean, py_model)

    -- Compare R-model vs Python-model predictions in T
    diff = t_preds_r .- t_preds_py
    mae = mean(abs(diff))
    
    print("MAE between predictions from R and Python models (evaluated in T):")
    print(mae)

    -- Threshold for float comparisons across runtimes/libraries
    if (mae < 0.001) {
        print("SUCCESS: R and Python models yield identical predictions in T!")
    } else {
        print("FAILURE: Predictions significantly different.")
        print("Sample diff:")
        print(head(diff))
    }
}
