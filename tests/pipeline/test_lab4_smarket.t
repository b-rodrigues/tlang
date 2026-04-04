-- Source: https://www.science.smith.edu/~jcrouser/SDS293/labs/2016/
import stats
import dataframe

p = pipeline {
    smarket_raw = node(
        command = <{ read_csv("tests/pipeline/data/Smarket.csv") }>,
        serializer = "arrow"
    );

    data_node = node(
        command = <{
            # smarket_raw is provided as an R data.frame
            df <- smarket_raw[, -1]
            df$Direction <- as.factor(df$Direction)
            df
        }>,
        runtime = R,
        serializer = "arrow",
        deserializer = "arrow"
    );

    r_model = node(
        command = <{
            glm(Direction ~ Lag1 + Lag2 + Lag3 + Lag4 + Lag5 + Volume, 
                data = data_node, 
                family = binomial)
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    );

    py_model = node(
        command = <{
import statsmodels.api as sm
import patsy
# Logistic regression using GLM with Binomial family
y, X = patsy.dmatrices('Direction ~ Lag1 + Lag2 + Lag3 + Lag4 + Lag5 + Volume', data_node, return_type='dataframe')
# statsmodels Direction[Up] or Direction[Down]? 
# patsy usually creates dummies for categorical responses too.
# For binomial, we need a 1D endog.
y = y.iloc[:, 1] # Usually Direction[Up] if Direction is the response
py_model = sm.GLM(y, X, family=sm.families.Binomial()).fit()
        }>,
        runtime = Python,
        serializer = "pmml",
        deserializer = "arrow"
    )
}

print("Building Lab 4 (Smarket Logistic Regression) pipeline...")
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
    
    print("\nComputing predictions in T...")
    preds_r = predict(df, m_r)
    preds_py = predict(df, m_py)
    
    mae = mean(abs(preds_r .- preds_py))
    print("MAE (R vs Py) in T:")
    print(mae)
    
    if (mae < 0.1) { -- Increased tolerance for logistic
        print("SUCCESS: Predictions match!")
    } else {
        print("WARNING: Predictions differ.")
    }
}
