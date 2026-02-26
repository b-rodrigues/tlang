-- test_pmml_interchange.t

model_node = node(
    command = <{
        # In R
        fit <- lm(mpg ~ wt + hp, data = mtcars)
        fit
    }>,
    runtime = "R",
    serializer = "pmml"
)

-- Native T prediction
preds_node = node(
    command = <{
        model = model_node
        -- predicted values for mtcars
        print("Model coefficients:")
        print(model.coefficients)
        
        -- We need data to predict on. Let's use mtcars.
        -- Note: read_csv or similar is needed if we didn't pass it through.
        -- For simplicity in this test, let's assume we have it or use a subset.
        
        -- Actually, mtcars is built-in in R, but not in T.
        -- Let's create a small dataframe in T for testing.
        test_df = dataframe([
            [wt: 2.62, hp: 110.0, mpg: 21.0],
            [wt: 2.875, hp: 110.0, mpg: 21.0],
            [wt: 2.32, hp: 93.0, mpg: 22.8]
        ])
        
        p = predict(test_df, model)
        print("Predictions:")
        print(p)
        p
    }>,
    runtime = "T",
    deserializer = "pmml"
)

p = pipeline {
    model_node = model_node
    preds_node = preds_node
}

print("Building pipeline...")
res = build_pipeline(p)

-- Verify
results = read_node("preds_node")
print("Verified Predictions in T:")
print(results)

-- Final check
expected = [23.5723294033, 22.583482564, 25.2758187247]
-- Check first value
if (abs(get(results, 0) - get(expected, 0)) < 0.001) {
    print("Test Passed: Native T predictions match R model via PMML")
} else {
    print("Test Failed: Predictions do not match expectations")
}
