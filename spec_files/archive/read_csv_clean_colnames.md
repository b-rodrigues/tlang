## Goal

Add an optional argument `clean_colnames` to `read_csv`.
When `clean_colnames = true`, column names are normalized into a safe, consistent identifier format (e.g. snake_case ASCII).

---

## 1. API & semantics

### Function signature

* `read_csv(path, ..., clean_colnames = false)`

### Behavioral contract

* If `clean_colnames = false`: column names are returned **exactly as in the CSV**.
* If `true`: column names are transformed deterministically by a documented cleaning algorithm.
* Cleaning happens **after parsing the header**, before constructing the DataFrame / table object.
* The transformation is:

  * Pure (no dependence on data values)
  * Stable across platforms
  * Idempotent (running it twice yields the same result)

---

## 2. Define a column-name normalization pipeline

Implement cleaning as a **pipeline of small, ordered transformations**, not one monolithic regex.

Suggested stages:

1. **Unicode normalization**

   * Normalize to NFKD
   * Strip diacritics (`é → e`)
   * Keep original string for error messages if needed

2. **Case normalization**

   * Convert to lowercase early

3. **Symbol expansion (semantic replacements)**

   * Replace known symbols with words:

     * `%` → `percent`
     * `€` → `euro`
     * `$` → `dollar`
     * `£` → `pound`
     * `¥` → `yen`
   * Maintain this as a **lookup table**, not regex soup

4. **Punctuation and separator handling**

   * Replace runs of non-alphanumeric characters with `_`

     * `.`, `-`, space, `/`, `:` → `_`
   * Collapse multiple underscores into one
   * Trim leading/trailing underscores

5. **Digit handling**

   * Preserve digits (`a_1`, `x2023`)
   * If name starts with a digit, prefix with a safe marker (e.g. `_` or `x_`)

6. **Empty or invalid names**

   * If result is empty, assign a fallback:

     * `col_1`, `col_2`, …

---

## 3. Collision resolution

Cleaning can produce duplicates:

* `"A.1"` → `a_1`
* `"A-1"` → `a_1`

Plan:

* Detect duplicates after cleaning
* Disambiguate deterministically:

  * `a_1`, `a_1_2`, `a_1_3`, …
* Keep the **first occurrence unchanged**

Optionally:

* Store a mapping `{original → cleaned}` in metadata for debugging.

---

## 4. Integration point in `read_csv`

1. Parse CSV header into `raw_colnames`
2. If `clean_colnames`:

   * Call `clean_colnames(raw_colnames)`
   * Validate uniqueness
3. Construct DataFrame with final names

Important:

* Do **not** interleave cleaning with CSV parsing logic.
* The CSV reader should not know *how* names are cleaned, only *that* they are.

---

## 5. Extensibility hooks (future-proofing)

Design `clean_colnames` as:

* A standalone function (or module)
* Internally configurable via:

  * Symbol map
  * Case policy
  * Prefix strategy for digits

This allows later extensions like:

* `clean_colnames = "snake" | "camel"`
* User-supplied cleaning function
* Locale-specific symbol maps

---

## 6. Testing strategy

### Unit tests

* Symbol handling:

  * `"MILLION€"` → `million_euro`
  * `"growth%"` → `growth_percent`
* Punctuation:

  * `"A.1"` → `a_1`
  * `"foo---bar"` → `foo_bar`
* Unicode:

  * `"café"` → `cafe`
* Collisions:

  * `["A.1", "A-1"]` → `["a_1", "a_1_2"]`

### Property tests

* Output matches `[a-z0-9_]+`
* Idempotence: `clean(clean(x)) == clean(x)`
* No empty names

---

## 7. Documentation

Document clearly:

* Exact transformation rules
* Collision behavior
* Examples table (before → after)
* Guarantee of stability across versions (or versioned behavior if you expect changes)
