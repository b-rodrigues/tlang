-- Source: https://www.science.smith.edu/~jcrouser/SDS293/labs/2016/
import stats
import dataframe

p = pipeline {
    hitters_raw = node(
        command = <{ read_csv("tests/pipeline/data/Hitters.csv") }>,
        serializer = "arrow"
    );

    data_node = node(
        command = <{
            # Prepare data: Drop Player column and NA
            df <- hitters_raw[, -1] # Player column
            df <- na.omit(df)
            df
        }>,
        runtime = R,
        serializer = "arrow",
        deserializer = "arrow"
    );

    r_model = node(
        command = <{
            library(glmnet)
            # glmnet needs matrix input
            x <- model.matrix(Salary ~ ., data_node)[, -1]
            y <- data_node$Salary
            # Ridge regression (alpha=0) with fixed lambda=4
            fit <- glmnet(x, y, alpha = 0, lambda = 4, standardize = TRUE)
            fit
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    );

    py_model = node(
        command = <{
import pandas as pd
import numpy as np
from sklearn.linear_model import Ridge
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline
from sklearn2pmml.pipeline import PMMLPipeline

# Ridge in sklearn with alpha=4
X = pd.get_dummies(data_node.drop('Salary', axis=1), drop_first=True).astype(float)
y = data_node['Salary']

# Use PMMLPipeline to include scaling
py_model = PMMLPipeline([
    ("scaler", StandardScaler()),
    ("ridge", Ridge(alpha=4))
])
py_model.fit(X, y)
        }>,
        runtime = Python,
        serializer = "pmml",
        deserializer = "arrow"
    )
}

print("Building Lab 10 (Hitters Ridge Regression) pipeline...")
res = build_pipeline(p, verbose=1)

if (is_error(res)) {
    print("Pipeline build failed:")
    print(res)
} else {
    print("Build successful.")
    
    df = read_node("data_node")
    m_r = read_node("r_model")
    m_py = read_node("py_model")
    
    print("\n--- R Model Summary ---")
    print(summary(m_r))
    
    print("\n--- Python Model Summary ---")
    print(summary(m_py))
    
    print("\nComparing coefficients...")
    print("R Coefficients:")
    print(m_r.coefficients)
    print("Python Coefficients:")
    print(m_py.coefficients)
}
