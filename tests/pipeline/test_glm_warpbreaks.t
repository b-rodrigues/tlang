import stats
import dataframe

p = pipeline {
    data_node = node(
        command = <{
            data(warpbreaks)
            # Warpbreaks is in 'datasets' (base R)
            warpbreaks
        }>,
        runtime = R,
        serializer = "arrow"
    );

    # Poisson model with interaction between wool and tension
    r_poisson = node(
        command = <{
            glm(breaks ~ wool * tension, family = "poisson", data = data_node)
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    );

    # Negative Binomial model for comparison (often better for count data)
    r_nb = node(
        command = <{
            library(MASS)
            glm.nb(breaks ~ wool * tension, data = data_node)
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    );

    # Python Poisson model with formula
    py_poisson = node(
        command = <{
import statsmodels.api as sm
import statsmodels.formula.api as smf
import os
# Interaction in statsmodels formula
model = smf.glm(formula='breaks ~ wool * tension', data=data_node, family=sm.families.Poisson()).fit()
t_write_pmml(model, os.path.expandvars("$out/artifact"))
        }>,
        runtime = Python,
        serializer = "pmml",
        deserializer = "arrow"
    )
}

print("Building Warpbreaks Pipeline...")
res = build_pipeline(p)

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
    
    mae = mean(abs(preds_r .- preds_py))
    print("\nPoisson MAE (R vs Py) in T:")
    print(mae)
    
    if (mae < 1e-4) {
        print("SUCCESS: Warpbreaks predictions match!")
    } else {
        print("WARNING: Warpbreaks predictions differ.")
    }
}
