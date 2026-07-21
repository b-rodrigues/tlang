# fetchurl

Fetch a URL

Downloads a file from a URL. In the REPL, wraps curl. In a pipeline, creates a node that uses Nix's builtins.fetchurl to fetch the asset into the Nix store, making it available downstream.

## Parameters

- **url** (`String`): The URL to download.

- **sha256** (`String`): (Optional) Expected SHA-256 hash (required in pipeline mode).

- **serializer** (`String`): (Optional) Serializer format for pipeline mode. Defaults to "bin". Use "text" for plain text files.

- **output** (`String`): (Optional) Output file path (REPL mode only). Defaults to the basename of the URL.

- **dest** (`String`): (Optional) Output directory (REPL mode only). Defaults to the current directory.


## Returns

| Node In REPL mode, returns the file path as a String. In pipeline mode, returns a Node value.

## Examples

```t
data = fetchurl("https://example.com/data.csv", output = "data.csv")
p = pipeline {
data = fetchurl("https://example.com/data.csv", sha256 = "abc123...")
}
```

