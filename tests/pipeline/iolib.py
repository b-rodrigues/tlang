# tests/pipeline/iolib.py
import pandas as pd

def py_read_csv(path):
    return pd.read_csv(path)

def py_write_csv(df, path):
    # index=False ensures we don't add an unnamed index column
    df.to_csv(path, index=False)
