---
description: Lint GitHub Actions workflows using actionlint
---

1. Identify the workflow file(s) that were modified.
2. Run actionlint via the Nix development shell:
// turbo
nix develop --command actionlint .github/workflows/<filename>.yml
3. If errors are found, correct them and repeat.
