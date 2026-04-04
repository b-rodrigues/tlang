-- test_pmml_interchange.t

data_node = node(
    command = read_csv("data/mtcars.csv", separator: "|"),
    serializer = "^csv"
)

model_node = node(
    command = <{
        # In R
        lm(mpg ~ wt + hp, data = data_node)
    }>,
    runtime = "R",
    deserializer = "^csv",
    serializer = "pmml"
)

-- Native T prediction
preds_node = node(
    command = <{
        print("Model coefficients:")
        print(model_node.coefficients)
        
        print("Tidy summary via summary(model_node):")
        print(summary(model_node))
        
        p = predict(data_node, model_node)
        print("Predictions:")
        print(p)
        p
    }>,
    runtime = "T",
    deserializer = [data_node: "^csv", model_node: "pmml"]
)

model_py_node = node(
    command = <{
# In Python
import pandas as pd
import numpy as np
from sklearn.linear_model import LinearRegression
from scipy import stats

data = data_node
X_df = data[["wt", "hp"]]
y = data["mpg"]

model_py_node = LinearRegression()
model_py_node.fit(X_df, y)

# Calculate OLS statistics for PMML enrichment
params = np.append(model_py_node.intercept_, model_py_node.coef_)
preds = model_py_node.predict(X_df)
X_mat = np.append(np.ones((len(X_df),1)), X_df.values, axis=1)

n, p = X_mat.shape
dof = n - p
mse = np.sum((y - preds)**2) / dof
var_b = mse * (np.linalg.inv(X_mat.T @ X_mat).diagonal())
sd_b = np.sqrt(var_b)
ts_b = params / sd_b
p_values = [2 * (1 - stats.t.cdf(np.abs(i), dof)) for i in ts_b]

# Attach properties for the T PMML bridge to find
model_py_node.std_errors_ = sd_b
model_py_node.t_stats_ = ts_b
model_py_node.p_values_ = p_values
model_py_node.nobs_ = n
model_py_node.r2_ = model_py_node.score(X_df, y)
model_py_node.df_residual_ = dof
model_py_node.sigma_ = np.sqrt(mse)

model_py_node
    }>,
    runtime = "Python",
    deserializer = "^csv",
    serializer = "pmml"
)

-- Native T prediction using Python model
preds_py_node = node(
    command = <{
        p = predict(data_node, model_py_node)
        print("Python model predictions in T:")
        print(p)
        p
    }>,
    runtime = "T",
    deserializer = [data_node: "^csv", model_py_node: "pmml"]
)

model_sm_node = node(
    command = <{
import statsmodels.api as sm
import pandas as pd

# Load data - data_node is already a pandas DataFrame
# predictors: wt, hp
X = data_node[["wt", "hp"]]
X = sm.add_constant(X)
y = data_node["mpg"]

# Fit GLM with Gaussian family (equivalent to OLS)
model_sm_node = sm.GLM(y, X, family=sm.families.Gaussian()).fit()
model_sm_node
    }>,
    runtime = "Python",
    deserializer = "^csv",
    serializer = "pmml"
)

-- Native T prediction using StatsModels model
preds_sm_node = node(
    command = <{
        p = predict(data_node, model_sm_node)
        print("StatsModels predictions in T:")
        print(p)
        p
    }>,
    runtime = "T",
    deserializer = [data_node: "^csv", model_sm_node: "pmml"]
)

p = pipeline {
    data_node = data_node
    model_node = model_node
    preds_node = preds_node
    model_py_node = model_py_node
    preds_py_node = preds_py_node
    model_sm_node = model_sm_node
    preds_sm_node = preds_sm_node
}

print("Populating and building pipeline...")
res = build_pipeline(p, verbose=1)

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

-- Verify Python (scikit-learn)
results_py = read_node("preds_py_node")
if (is_error(results_py)) {
    print("Error reading results_py:")
    print(results_py)
    exit(1)
} else {
    print("Verified Predictions in T (from scikit-learn):")
    print(head(results_py))
}

-- Verify Python (StatsModels)
results_sm = read_node("preds_sm_node")
if (is_error(results_sm)) {
    print("Error reading results_sm:")
    print(results_sm)
    exit(1)
} else {
    print("Verified Predictions in T (from StatsModels):")
    print(head(results_sm))
}

-- Final check
expected = [23.5723294033, 22.583482564, 25.2758187247]

-- Check first value from all
val_r = get(results_r, 0)
val_py = get(results_py, 0)
val_sm = get(results_sm, 0)
expected_val = get(expected, 0)

print("First prediction (R):", val_r)
print("First prediction (Py):", val_py)
print("First prediction (SM):", val_sm)
print("Expected:", expected_val)

if (abs(val_r - expected_val) < 0.001) {
    if (abs(val_py - expected_val) < 0.001) {
        if (abs(val_sm - expected_val) < 0.001) {
            print("SUCCESS: Native T predictions match R, scikit-learn, and StatsModels models!")
            0
        } else {
            print("FAILED: StatsModels prediction mismatch. Delta:", abs(val_sm - expected_val))
            exit(1)
        }
    } else {
        print("FAILED: scikit-learn prediction mismatch. Delta:", abs(val_py - expected_val))
        exit(1)
    }
} else {
    print("FAILED: R prediction mismatch. Delta:", abs(val_r - expected_val))
    exit(1)
}
