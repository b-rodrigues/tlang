-- tests/pipeline/test_lab12_poly.t
-- Lab 12: Polynomial Regression and Step Functions
-- Source: https://www.science.smith.edu/~jcrouser/SDS293/labs/2016/

import stats
import dataframe

p = pipeline {
    wage_raw = node(
        command = <{ 
            read_csv("tests/pipeline/data/Wage.csv")
        }>,
        serializer = "arrow"
    );

    -- T node: Prepare data with poly
    -- We use degree 4 as in the lab.
    -- Default poly in R is orthogonal, but we use raw=TRUE for easier comparison
    -- with our current simple power-based poly().
    t_data = node(
        command = <{
            -- Use eval(expr(...)) to allow splicing !!!
            cols = poly(wage_raw.age, 4, raw = true)
            eval(expr(mutate(wage_raw, !!!cols)))
        }>,
        serializer = "arrow",
        deserializer = "arrow"
    );

    -- T node: Fit model using T's lm
    t_model = node(
        command = <{
            if (is_error(t_data)) {
                print("t_data loading failed!")
                print(t_data)
                exit(1)
            } else {
                lm(t_data, wage ~ poly1 + poly2 + poly3 + poly4)
            }
        }>,
        deserializer = "arrow"
    );

    -- R node: Fit model using R for comparison
    r_model = node(
        command = <{
            # Pre-compute polynomial terms to avoid r2pmml formula errors
            df <- wage_raw
            p <- poly(df$age, 4, raw = TRUE)
            df$poly1 <- p[,1]
            df$poly2 <- p[,2]
            df$poly3 <- p[,3]
            df$poly4 <- p[,4]
            fit <- lm(wage ~ poly1 + poly2 + poly3 + poly4, data = df)
            fit
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    );
}

print("Building Lab 12 (Polynomial Regression) pipeline...")
res = build_pipeline(p, verbose=1)

if (is_error(res)) {
    print("Build failed:")
    print(res)
} else {
    print("Build successful.")
    
    mt = read_node("t_model")
    mr = read_node("r_model")

    print("\nT Model R-squared:", mt.r_squared)
    print("R Model R-squared:", mr.r_squared)

    -- In T, summary() returns a Dict with _tidy_df
    print("\nT Model Coefficients:")
    coefs_t = summary(mt)._tidy_df |> select($term, $estimate)
    print(coefs_t)
    
    print("\nR Model Coefficients:")
    coefs_r = summary(mr)._tidy_df |> select($term, $estimate)
    print(coefs_r)
    
    diff = mt.r_squared - mr.r_squared
    if (abs(diff) < 0.0001) {
        print("\nSUCCESS: T and R models match (R-squared).")
    } else {
        print("\nFAILURE: Significant difference between T and R models.")
    }
}
