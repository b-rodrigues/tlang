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
            # Prepare data: Year before 2005 for training
            df <- smarket_raw[, -1]
            df$Direction <- as.factor(df$Direction)
            df
        }>,
        runtime = R,
        serializer = "arrow",
        deserializer = "arrow"
    );

    -- LDA model in R and Python (results as predictions because PMML support varies)
    r_preds = node(
        command = <{
            library(MASS)
            train <- data_node[data_node$Year < 2005, ]
            test <- data_node[data_node$Year >= 2005, ]
            fit <- lda(Direction ~ Lag1 + Lag2, data = train)
            preds <- predict(fit, test)$class
            data.frame(Direction = as.character(preds))
        }>,
        runtime = R,
        serializer = "arrow",
        deserializer = "arrow"
    );

    py_preds = node(
        command = <{
import pandas as pd
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis

train = data_node[data_node['Year'] < 2005]
test = data_node[data_node['Year'] >= 2005]

X_train = train[['Lag1', 'Lag2']]
y_train = train['Direction']
X_test = test[['Lag1', 'Lag2']]

py_lda = LinearDiscriminantAnalysis()
py_lda.fit(X_train, y_train)
preds = py_lda.predict(X_test)
py_preds = pd.DataFrame({'Direction': preds})
        }>,
        runtime = Python,
        serializer = "arrow",
        deserializer = "arrow"
    );
}

print("Building Lab 5 (LDA on Smarket) pipeline...")
res = build_pipeline(p, verbose=1)

if (is_error(res)) {
    print("Pipeline build failed:")
    print(res)
} else {
    print("Build successful.")
    
    r_p = read_node("r_preds")
    py_p = read_node("py_preds")
    
    -- Compare predictions
    match = sum(to_integer(r_p.Direction .== py_p.Direction))
    total = length(r_p.Direction)
    
    print("\nComparison of R and Python LDA predictions:")
    print("Total test observations: ", total)
    print("Matching predictions: ", match)
    
    if (match == total) {
        print("SUCCESS: R and Python predictions match perfectly.")
    } else {
        print("WARNING: R and Python predictions differ!")
        print("Match rate: ", (match / total))
    }
}
