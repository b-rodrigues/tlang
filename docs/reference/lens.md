# lens

Lens Library

Lenses provide a robust way to focus on, retrieve, and update nested data structures. Historically implemented as functional closures, Tlang lenses are now structured serializable objects (VLens), allowing them to be passed across Nix-isolated pipeline boundaries.  Retrieval should primarily be performed via the unified `get(data, lens)` primitive. Updates are performed via `over(data, lens, func)`.

