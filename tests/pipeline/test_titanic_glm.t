
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

    model_node = node(
        command = <{
            data_node$Survived <- as.factor(data_node$Survived)
            glm(Survived ~ Pclass + Age + Fare, data = data_node, family = binomial(link = "logit"))
        }>,
        runtime = R,
        serializer = "pmml",
        deserializer = "arrow"
    );

    r_pred_node = node(
        command = <{
            data_node$Survived <- as.factor(data_node$Survived)
            fit <- glm(Survived ~ Pclass + Age + Fare, data = data_node, family = binomial(link = "logit"))
            preds <- predict(fit, data_node, type = "response")
            data.frame(preds = as.numeric(preds))
        }>,
        runtime = R,
        serializer = "arrow",
        deserializer = "arrow"
    )
}

print("Building Titanic GLM pipeline...")
res = build_pipeline(p)

if (is_error(res)) {
    print("Pipeline build failed:")
    print(res)
} else {
    print("Reading artifacts...")
    df_clean = read_node("data_node")
    model    = read_node("model_node")
    r_preds_df = read_node("r_pred_node")
    r_preds = pull(r_preds_df, "preds")

    print("Computing predictions in T...")
    t_preds = predict(df_clean, model)

    -- Compute MAE
    -- Compute MAE
    diff = r_preds .- t_preds
    mae = mean(abs(diff))
    
    print("Mean Absolute Error Between R and T:")
    print(mae)

    -- Use a large enough threshold for float comparisons (due to PMML truncation)
    if (mae < 0.001) {
        print("SUCCESS: T predictions match R predictions!")
    } else {
        print("FAILURE: Predictions significantly different.")
    }
}
