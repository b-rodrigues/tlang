# prefetch

Prefetch a URL and compute its SHA-256 hash

Downloads a URL via nix-prefetch-url and returns its SHA-256 hash. The file is stored in the Nix store so that fetchurl in pipeline mode finds it cached and does not re-download.

## Parameters

- **url** (`String`): The URL to prefetch.


## Returns

The SHA-256 hash of the downloaded content.

## Examples

```t
hash = prefetch("https://example.com/data.csv")
print(hash)
```

## See Also

[fetchurl](fetchurl.html)

