#!/usr/bin/env python
import os

import pandas as pd
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn2pmml import sklearn2pmml
from sklearn2pmml.pipeline import PMMLPipeline


def main() -> None:
    base_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(base_dir, "data")
    expected_dir = os.path.join(base_dir, "expected")

    os.makedirs(data_dir, exist_ok=True)
    os.makedirs(expected_dir, exist_ok=True)

    iris_path = os.path.join(data_dir, "iris.csv")
    mtcars_path = os.path.join(data_dir, "mtcars.csv")

    iris = pd.read_csv(iris_path)
    iris_x = iris.drop(columns=["Species"])
    iris_y = iris["Species"]

    clf = RandomForestClassifier(n_estimators=50, random_state=123)
    clf_pipe = PMMLPipeline([("classifier", clf)])
    clf_pipe.fit(iris_x, iris_y)

    sklearn2pmml(clf_pipe, os.path.join(data_dir, "iris_sklearn_rf.pmml"), with_repr=True)

    iris_preds = clf_pipe.predict(iris_x)
    pd.DataFrame({"pred": iris_preds}).to_csv(
        os.path.join(expected_dir, "iris_sklearn_rf_predictions.csv"),
        index=False,
    )

    mtcars = pd.read_csv(mtcars_path)
    mtcars_numeric = mtcars.select_dtypes(include=["number"])
    mtcars_y = mtcars_numeric["mpg"]
    mtcars_x = mtcars_numeric.drop(columns=["mpg"])

    reg = RandomForestRegressor(n_estimators=100, random_state=123)
    reg_pipe = PMMLPipeline([("regressor", reg)])
    reg_pipe.fit(mtcars_x, mtcars_y)

    sklearn2pmml(reg_pipe, os.path.join(data_dir, "mtcars_sklearn_rf.pmml"), with_repr=True)

    mtcars_preds = reg_pipe.predict(mtcars_x)
    pd.DataFrame({"pred": mtcars_preds}).to_csv(
        os.path.join(expected_dir, "mtcars_sklearn_rf_predictions.csv"),
        index=False,
    )


if __name__ == "__main__":
    main()
