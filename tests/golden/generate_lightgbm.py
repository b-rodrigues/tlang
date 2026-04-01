#!/usr/bin/env python
import os
import pandas as pd
from lightgbm import LGBMClassifier, LGBMRegressor
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
    iris.columns = [c.replace(".", "_").lower() for c in iris.columns] # LightGBM likes clean names
    iris_x = iris.drop(columns=["species"])
    iris_y = (iris["species"] == "setosa").astype(int)

    # LightGBM (binary classification)
    lgb_clf = LGBMClassifier(
        n_estimators=10,
        max_depth=3,
        learning_rate=0.1,
        min_child_samples=1,
        min_data_in_bin=1,
        random_state=123,
        verbose=-1
    )
    lgb_clf_pipe = PMMLPipeline([("classifier", lgb_clf)])
    lgb_clf_pipe.fit(iris_x, iris_y)

    sklearn2pmml(lgb_clf_pipe, os.path.join(data_dir, "iris_lgb_bin.pmml"), with_repr=True)

    lgb_clf_preds = lgb_clf_pipe.predict(iris_x)
    pd.DataFrame({"pred": lgb_clf_preds}).to_csv(
        os.path.join(expected_dir, "iris_lgb_bin_predictions.csv"),
        index=False,
    )

    # LightGBM (regression)
    mtcars = pd.read_csv(mtcars_path)
    mtcars_numeric = mtcars.select_dtypes(include=["number"])
    mtcars_y = mtcars_numeric["mpg"]
    mtcars_x = mtcars_numeric.drop(columns=["mpg"])
    mtcars_x.columns = [c.replace(".", "_").lower() for c in mtcars_x.columns]

    lgb_reg = LGBMRegressor(
        n_estimators=20,
        max_depth=3,
        learning_rate=0.1,
        min_child_samples=1,
        min_data_in_bin=1,
        random_state=123,
        verbose=-1
    )
    lgb_reg_pipe = PMMLPipeline([("regressor", lgb_reg)])
    lgb_reg_pipe.fit(mtcars_x, mtcars_y)

    sklearn2pmml(lgb_reg_pipe, os.path.join(data_dir, "mtcars_lgb_reg.pmml"), with_repr=True)

    lgb_reg_preds = lgb_reg_pipe.predict(mtcars_x)
    pd.DataFrame({"pred": lgb_reg_preds}).to_csv(
        os.path.join(expected_dir, "mtcars_lgb_reg_predictions.csv"),
        index=False,
    )

if __name__ == "__main__":
    main()
