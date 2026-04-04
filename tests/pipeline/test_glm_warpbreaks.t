import stats
import dataframe

p = pipeline {
    data_node = node(
        command = <{
            data(warpbreaks)
            warpbreaks$wool <- as.character(warpbreaks$wool)
            warpbreaks$tension <- as.character(warpbreaks$tension)
            warpbreaks
        }>,
        runtime = R,
        serializer = "arrow"
    );

    -- Poisson model with interaction between wool and tension
    r_poisson = node(
        command = <{
            data_node$wool <- as.factor(data_node$wool)
            data_node$tension <- as.factor(data_node$tension)
            glm(breaks ~ wool * tension, family = "poisson", data = data_node)
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    );

    -- Negative Binomial model for comparison (often better for count data)
    r_nb = node(
        command = <{
            library(MASS)
            data_node$wool <- as.factor(data_node$wool)
            data_node$tension <- as.factor(data_node$tension)
            glm.nb(breaks ~ wool * tension, data = data_node)
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    );

    -- Python Poisson model with formula
    py_poisson = node(
        command = <{
import statsmodels.api as sm
import patsy
data_node['wool'] = data_node['wool'].astype('category')
data_node['tension'] = data_node['tension'].astype('category')
y, X = patsy.dmatrices('breaks ~ wool * tension', data_node, return_type='dataframe')
y = y.iloc[:, 0]
# Note: jpmml-statsmodels has issues with Poisson log link so this might still fail,
# but using array API prevents Series cast exceptions.
py_poisson = sm.GLM(y, X, family=sm.families.Poisson()).fit()
        }>,
        runtime = Python,
        serializer = "pmml",
        deserializer = "arrow"
    )
}

print("Building Warpbreaks Pipeline...")
res = build_pipeline(p, verbose=1)

if (is_error(res)) {
    print("Pipeline build failed.")
    print(res)
} else {
    print("Build successful.")
    df = read_node("data_node")
    m_p_r  = read_node("r_poisson")
    m_nb_r = read_node("r_nb")
    m_p_py = read_node("py_poisson")
    
    print("\n--- Warpbreaks Poisson (R) Summary ---")
    print(summary(m_p_r))
    
    print("\n--- Warpbreaks NegBinom (R) Summary ---")
    print(summary(m_nb_r))

    print("\n--- Warpbreaks Poisson (Python) Summary ---")
    print(summary(m_p_py))

    print("\nComputing predictions in T...")
    preds_r = predict(df, m_p_r)
    preds_py = predict(df, m_p_py)
    
    if (is_error(preds_py)) {
        print("PYTHON PREDS ERROR:")
        print(preds_py)
    }
    
    mae = mean(abs(preds_r .- preds_py))
    print("\nPoisson MAE (R vs Py) in T:")
    print(mae)
    
    if (mae < 0.005) {
        print("SUCCESS: Warpbreaks predictions match!")
    } else {
        print("WARNING: Warpbreaks predictions differ.")
    }
}
