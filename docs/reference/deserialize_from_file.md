# deserialize_from_file

Binary Deserialization

Reads a serialized T value from a file. Verifies an integrity digest before unmarshalling to reject tampered or externally-supplied artifacts.  SECURITY NOTE: OCaml Marshal is not safe for fully untrusted input. The MD5 digest check detects accidental corruption only — MD5 is not cryptographically secure and provides no protection against intentional tampering. Only load .tobj files produced by your own T installation.

## Parameters

- **path** (`String`): Source file path.


## Returns

String] Value or error.

