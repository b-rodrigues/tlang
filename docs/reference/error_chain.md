# error_chain

Chain errors to preserve provenance

Explicitly chains two errors together by setting the second error as the cause of the first error.

## Parameters

- **err1** (`Error`): The primary or outer Error.

- **err2** (`Error`): The underlying cause Error.


## Returns

The chained Error value.

