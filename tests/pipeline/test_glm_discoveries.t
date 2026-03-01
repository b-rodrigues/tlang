import stats
import dataframe

p = pipeline {
    data_node = node(
        command = <{
            data(discoveries)
            disc <- data.frame(count = as.numeric(discoveries),
                               year = seq(0, (length(discoveries) - 1)))
            disc$yearSqr <- disc$year^2
            disc
        }>,
        runtime = R,
        serializer = "arrow"
    );

    poisson_r = node(
        command = <{
            glm(count ~ year + yearSqr, family = "poisson", data = data_node)
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    );

    nb_r = node(
        command = <{
            library(MASS)
            # Use glm.nb for Negative Binomial
            glm.nb(count ~ year + yearSqr, data = data_node)
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    );

    poisson_py = node(
        command = <{
import statsmodels.api as sm
import os
y = data_node['count']
X = sm.add_constant(data_node[['year', 'yearSqr']])
model = sm.GLM(y, X, family=sm.families.Poisson()).fit()
t_write_pmml(model, os.path.expandvars("$out/artifact"))
        }>,
        runtime = Python,
        serializer = "pmml",
        deserializer = "arrow"
    );

    nb_py = node(
        command = <{
import statsmodels.api as sm
import os
y = data_node['count']
X = sm.add_constant(data_node[['year', 'yearSqr']])
# NB in statsmodels (using NegativeBinomial or GLM with family)
# GLM with NB family is more flexible for links
model = sm.GLM(y, X, family=sm.families.NegativeBinomial()).fit()
t_write_pmml(model, os.path.expandvars("$out/artifact"))
        }>,
        runtime = Python,
        serializer = "pmml",
        deserializer = "arrow"
    )
}

print("Building Discoveries (Count Response) pipeline...")
res = build_pipeline(p)

if (is_error(res)) {
    print("Pipeline build failed:")
    print(res)
} else {
    print("Build successful.")
    
    df = read_node("data_node")
    p_r = read_node("poisson_r")
    p_py = read_node("poisson_py")
    nb_r = read_node("nb_r")
    nb_py = read_node("nb_py")
    
    print("\n--- Poisson (R) Summary ---")
    print(summary(p_r))
    
    print("\n--- Poisson (Python) Summary ---")
    print(summary(p_py))

    print("\n--- NegBinomial (R) Summary ---")
    print(summary(nb_r))
    
    print("\n--- NegBinomial (Python) Summary ---")
    print(summary(nb_py))

    print("\nComputing predictions in T...")
    -- All predictors are numeric (year, yearSqr, const)
    -- T's predict() expects 'const' if statsmodels used sm.add_constant
    -- statsmodels uses 'const' as intercept name in PMML
    -- r2pmml uses '(Intercept)'
    
    -- T's predict() handles standard intercept names: (Intercept), Intercept, const
    
    preds_p_r = predict(df, p_r)
    preds_p_py = predict(df, p_py)
    
    preds_nb_r = predict(df, nb_r)
    preds_nb_py = predict(df, nb_py)
    
    mae_p = mean(abs(preds_p_r .- preds_p_py))
    mae_nb = mean(abs(preds_nb_r .- preds_nb_py))
    
    print("\nPoisson MAE (R vs Py) in T:")
    print(mae_p)
    print("NegBinomial MAE (R vs Py) in T:")
    print(mae_nb)
    
    if (mae_p < 1e-5) {
        print("SUCCESS: Poisson predictions match!")
    } else {
        print("WARNING: Poisson predictions differ.")
    }

    if (mae_nb < 1e-4) {
        print("SUCCESS: NegBinomial predictions match!")
    } else {
        print("WARNING: NegBinomial predictions differ.")
    }
}
