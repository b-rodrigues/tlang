-- T helper functions for CSV I/O in pipeline nodes
t_write_csv = \(df: DataFrame, path: String -> Null) write_csv(df, path)
t_read_csv = \(path: String -> DataFrame) read_csv(path)
