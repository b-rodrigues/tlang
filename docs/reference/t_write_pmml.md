# t_write_pmml

Write a PMML model file

Writes a model dictionary back to a PMML file on disk. Currently, this primarily supports pass-through copying of models that were originally loaded from PMML.

## Parameters

- **model** (`Dict`): The model dictionary.

- **path** (`String`): The destination file path.


## Returns

The path to the written file.

## See Also

[t_read_pmml](t_read_pmml.html)

