# tests/golden/generate_simple_onnx.py
import os
import pandas as pd
import numpy as np
import onnx
from onnx import helper, TensorProto
from sklearn.linear_model import LinearRegression

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(base_dir, "data")
    expected_dir = os.path.join(base_dir, "expected")
    os.makedirs(data_dir, exist_ok=True)
    os.makedirs(expected_dir, exist_ok=True)

    # 1. Linear regression Model: hp ~ wt (mtcars)
    mtcars_path = os.path.join(data_dir, "mtcars.csv")
    if not os.path.exists(mtcars_path):
        # Fallback if mtcars.csv is not generated yet
        mtcars = pd.DataFrame({"wt": [2.62, 2.875, 2.32], "hp": [110, 110, 93]})
    else:
        mtcars = pd.read_csv(mtcars_path)
        
    X = mtcars[["wt"]].values.astype(np.float32)
    y = mtcars["hp"].values.astype(np.float32)
    
    model = LinearRegression().fit(X, y)
    W_raw = model.coef_.reshape(1, 1).astype(np.float32)
    B_raw = model.intercept_.reshape(1).astype(np.float32)
    
    # Simple Y = X*W + B graph
    w_init = helper.make_tensor("W", TensorProto.FLOAT, [1, 1], W_raw.flatten())
    b_init = helper.make_tensor("B", TensorProto.FLOAT, [1], B_raw.flatten())
    
    input_x = helper.make_tensor_value_info('X', TensorProto.FLOAT, [None, 1])
    output_y = helper.make_tensor_value_info('Y', TensorProto.FLOAT, [None, 1])
    
    node_matmul = helper.make_node("MatMul", ["X", "W"], ["matmul_out"])
    node_add = helper.make_node("Add", ["matmul_out", "B"], ["Y"])
    
    graph = helper.make_graph(
        [node_matmul, node_add], 
        "simple_reg", 
        [input_x], 
        [output_y], 
        initializer=[w_init, b_init]
    )
    onx = helper.make_model(graph, producer_name="t-golden-gen")
    
    onnx_path = os.path.join(data_dir, "mtcars_hp_reg.onnx")
    with open(onnx_path, "wb") as f:
        f.write(onx.SerializeToString())
    
    # 2. Expected Predictions
    preds = model.predict(X)
    pd.DataFrame({"pred": preds.flatten()}).to_csv(
        os.path.join(expected_dir, "mtcars_onnx_reg_predictions.csv"),
        index=False
    )
    print(f"Generated {onnx_path}")

if __name__ == "__main__":
    main()
