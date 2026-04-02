# tests/golden/generate_simple_onnx.py
import os
import pandas as pd
import numpy as np
import onnx
from onnx import helper, TensorProto
from sklearn.linear_model import LinearRegression, LogisticRegression

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(base_dir, "data")
    expected_dir = os.path.join(base_dir, "expected")
    os.makedirs(data_dir, exist_ok=True)
    os.makedirs(expected_dir, exist_ok=True)

    # 1. Linear regression Model: hp ~ wt (mtcars)
    mtcars_path = os.path.join(data_dir, "mtcars.csv")
    if not os.path.exists(mtcars_path):
        mtcars = pd.DataFrame({"wt": [2.62, 2.875, 2.32], "hp": [110, 110, 93]})
    else:
        mtcars = pd.read_csv(mtcars_path)
        
    X_reg = mtcars[["wt"]].values.astype(np.float32)
    y_reg = mtcars["hp"].values.astype(np.float32)
    
    model_reg = LinearRegression().fit(X_reg, y_reg)
    W_reg_raw = model_reg.coef_.reshape(1, 1).astype(np.float32)
    B_reg_raw = model_reg.intercept_.reshape(1).astype(np.float32)
    
    w_reg_init = helper.make_tensor("W_reg", TensorProto.FLOAT, [1, 1], W_reg_raw.flatten())
    b_reg_init = helper.make_tensor("B_reg", TensorProto.FLOAT, [1], B_reg_raw.flatten())
    
    input_x_reg = helper.make_tensor_value_info('X', TensorProto.FLOAT, [None, 1])
    output_y_reg = helper.make_tensor_value_info('Y', TensorProto.FLOAT, [None, 1])
    
    node_matmul_reg = helper.make_node("MatMul", ["X", "W_reg"], ["matmul_reg_out"])
    node_add_reg = helper.make_node("Add", ["matmul_reg_out", "B_reg"], ["Y"])
    
    graph_reg = helper.make_graph(
        [node_matmul_reg, node_add_reg], 
        "simple_reg", 
        [input_x_reg], 
        [output_y_reg], 
        initializer=[w_reg_init, b_reg_init]
    )
    onx_reg = helper.make_model(graph_reg, producer_name="t-golden-gen")
    
    onnx_reg_path = os.path.join(data_dir, "mtcars_hp_reg.onnx")
    with open(onnx_reg_path, "wb") as f:
        f.write(onx_reg.SerializeToString())
    
    preds_reg = model_reg.predict(X_reg)
    pd.DataFrame({"pred": preds_reg.flatten()}).to_csv(
        os.path.join(expected_dir, "mtcars_onnx_reg_predictions.csv"),
        index=False
    )
    print(f"Generated {onnx_reg_path}")

    # 2. Logistic Regression Model: Species ~ . (iris)
    iris_path = os.path.join(data_dir, "iris.csv")
    if not os.path.exists(iris_path):
        iris = pd.DataFrame({
            "Sepal.Length": [5.1, 4.9, 4.7],
            "Sepal.Width": [3.5, 3.0, 3.2],
            "Petal.Length": [1.4, 1.4, 1.3],
            "Petal.Width": [0.2, 0.2, 0.2],
            "Species": ["setosa", "setosa", "setosa"]
        })
    else:
        iris = pd.read_csv(iris_path)
    
    features = ["Sepal.Length", "Sepal.Width", "Petal.Length", "Petal.Width"]
    X_clf = iris[features].values.astype(np.float32)
    iris['Species_code'] = iris['Species'].astype('category').cat.codes
    y_clf = iris['Species_code']
    
    model_clf = LogisticRegression(solver='lbfgs', max_iter=1000).fit(X_clf, y_clf)
    W_clf_raw = model_clf.coef_.T.astype(np.float32)
    B_clf_raw = model_clf.intercept_.astype(np.float32)
    
    w_clf_init = helper.make_tensor("W_clf", TensorProto.FLOAT, [4, 3], W_clf_raw.flatten())
    b_clf_init = helper.make_tensor("B_clf", TensorProto.FLOAT, [3], B_clf_raw.flatten())
    
    input_x_clf = helper.make_tensor_value_info('X_clf', TensorProto.FLOAT, [None, 4])
    output_y_clf = helper.make_tensor_value_info('Y_output', TensorProto.FLOAT, [None])
    
    node_matmul_clf = helper.make_node("MatMul", ["X_clf", "W_clf"], ["scores"])
    node_add_clf = helper.make_node("Add", ["scores", "B_clf"], ["scores_biased"])
    node_argmax_clf = helper.make_node("ArgMax", ["scores_biased"], ["argmax_out"], axis=1)
    node_cast_clf = helper.make_node("Cast", ["argmax_out"], ["Y_output"], to=TensorProto.FLOAT)
    
    graph_clf = helper.make_graph(
        [node_matmul_clf, node_add_clf, node_argmax_clf, node_cast_clf], 
        "iris_clf", 
        [input_x_clf], 
        [output_y_clf], 
        initializer=[w_clf_init, b_clf_init]
    )
    onx_clf = helper.make_model(graph_clf, producer_name="t-golden-gen")
    
    onnx_clf_path = os.path.join(data_dir, "iris_logreg.onnx")
    with open(onnx_clf_path, "wb") as f:
        f.write(onx_clf.SerializeToString())
    
    preds_class = model_clf.predict(X_clf).astype(float)
    pd.DataFrame({"pred": preds_class}).to_csv(
        os.path.join(expected_dir, "iris_onnx_logreg_predictions.csv"),
        index=False
    )
    print(f"Generated {onnx_clf_path}")

if __name__ == "__main__":
    main()
