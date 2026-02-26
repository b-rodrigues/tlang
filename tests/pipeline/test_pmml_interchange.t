-- test_pmml_interchange.t

model_node = node(
    command = <{
        # In R
        data <- read.csv("data/mtcars.csv", sep="|", header=TRUE)
        fit <- lm(mpg ~ wt + hp, data = data)
        fit
    }>,
    runtime = "R",
    serializer = "pmml"
)

-- Native T prediction
preds_node = node(
    command = <{
        model = model_node
        
        print("Model coefficients:")
        print(model.coefficients)
        
        print("Tidy summary via summary(model):")
        print(summary(model))
        
        -- Use the CSV data
        test_df = read_csv("data/mtcars.csv", separator: "|")
        
        p = predict(test_df, model)
        print("Predictions:")
        print(p)
        p
    }>,
    runtime = "T",
    deserializer = "pmml"
)

model_py_node = node(
    command = <{
        # In Python
        import pandas as pd
        import numpy as np
        from sklearn.linear_model import LinearRegression
        from scipy import stats
        
        data = pd.read_csv("data/mtcars.csv", sep="|")
        X_df = data[["wt", "hp"]]
        y = data["mpg"]
        
        model = LinearRegression()
        model.fit(X_df, y)
        
        # Calculate OLS statistics for PMML enrichment
        params = np.append(model.intercept_, model.coef_)
        preds = model.predict(X_df)
        X_mat = np.append(np.ones((len(X_df),1)), X_df.values, axis=1)
        
        n, p = X_mat.shape
        dof = n - p
        mse = np.sum((y - preds)**2) / dof
        var_b = mse * (np.linalg.inv(X_mat.T @ X_mat).diagonal())
        sd_b = np.sqrt(var_b)
        ts_b = params / sd_b
        p_values = [2 * (1 - stats.t.cdf(np.abs(i), dof)) for i in ts_b]
        
        # Attach properties for the T PMML bridge to find
        model.std_errors_ = sd_b
        model.t_stats_ = ts_b
        model.p_values_ = p_values
        model.nobs_ = n
        model.r2_ = model.score(X_df, y)
        model.df_residual_ = dof
        model.sigma_ = np.sqrt(mse)
        
        model
    }>,
    runtime = "Python",
    serializer = "pmml"
)

-- Native T prediction using Python model
preds_py_node = node(
    command = <{
        model = model_py_node
        test_df = read_csv("data/mtcars.csv", separator: "|")
        p = predict(test_df, model)
        print("Python model predictions in T:")
        print(p)
        p
    }>,
    runtime = "T",
    deserializer = "pmml"
)

p = pipeline {
    model_node = model_node
    preds_node = preds_node
    model_py_node = model_py_node
    preds_py_node = preds_py_node
}

print("Populating and building pipeline...")
res = build_pipeline(p)

if (is_error(res)) {
    print("FATAL: Pipeline build failed!")
    print(res)
    exit(1)
} else {
    print("Pipeline build successful.")
}

-- Verify R
results_r = read_node("preds_node")
if (is_error(results_r)) {
    print("Error reading results_r:")
    print(results_r)
    exit(1)
} else {
    print("Verified Predictions in T (from R):")
    print(head(results_r))
}

-- Verify Python
results_py = read_node("preds_py_node")
if (is_error(results_py)) {
    print("Error reading results_py:")
    print(results_py)
    exit(1)
} else {
    print("Verified Predictions in T (from Python):")
    print(head(results_py))
}

-- Final check
expected = [23.5723294033, 22.583482564, 25.2758187247]

-- Check first value from both
val_r = get(results_r, 0)
val_py = get(results_py, 0)
exp = get(expected, 0)

print("First prediction (R):", val_r)
print("First prediction (Py):", val_py)
print("Expected:", exp)

if (abs(val_r - exp) < 0.001) {
    if (abs(val_py - exp) < 0.001) {
        print("SUCCESS: Native T predictions match both R and Python models!")
        0
    } else {
        print("FAILED: Python prediction mismatch. Delta:", abs(val_py - exp))
        exit(1)
    }
} else {
    print("FAILED: R prediction mismatch. Delta:", abs(val_r - exp))
    exit(1)
}
