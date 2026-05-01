import os
import pandas as pd
import numpy as np
from sklearn.linear_model import LogisticRegression
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(base_dir, "data")
    expected_dir = os.path.join(base_dir, "expected")
    
    os.makedirs(data_dir, exist_ok=True)
    os.makedirs(expected_dir, exist_ok=True)

    # 1. Simple Logistic Regression on Iris
    iris_path = os.path.join(data_dir, "iris.csv")
    iris = pd.read_csv(iris_path)
    X = iris.drop(columns=["Species"]).values.astype(np.float32)
    from sklearn.preprocessing import LabelEncoder
    le = LabelEncoder()
    y = le.fit_transform(iris["Species"].values)
    
    clf = LogisticRegression(max_iter=1000, random_state=123, solver='lbfgs')
    clf.fit(X, y)
    
    # Export to ONNX
    initial_type = [('float_input', FloatTensorType([None, 4]))]
    onx = convert_sklearn(clf, initial_types=initial_type)
    
    onnx_path = os.path.join(data_dir, "iris_logreg.onnx")
    with open(onnx_path, "wb") as f:
        f.write(onx.SerializeToString())
    
    # Generate expected predictions
    preds = clf.predict(X)
    pd.DataFrame({"pred": preds.astype(float)}).to_csv(
        os.path.join(expected_dir, "iris_onnx_logreg_predictions.csv"),
        index=False
    )
    print(f"Generated {onnx_path}")

    # 2. Decision Tree Classifier on Iris
    from sklearn.tree import DecisionTreeClassifier
    dt_clf = DecisionTreeClassifier(random_state=123)
    dt_clf.fit(X, y)
    
    dt_onx = convert_sklearn(dt_clf, initial_types=initial_type)
    dt_onnx_path = os.path.join(data_dir, "iris_dt.onnx")
    with open(dt_onnx_path, "wb") as f:
        f.write(dt_onx.SerializeToString())
        
    dt_preds = dt_clf.predict(X)
    pd.DataFrame({"pred": dt_preds.astype(float)}).to_csv(
        os.path.join(expected_dir, "iris_onnx_dt_predictions.csv"),
        index=False
    )
    print(f"Generated {dt_onnx_path}")

if __name__ == "__main__":
    main()
