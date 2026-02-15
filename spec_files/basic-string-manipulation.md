# Built-in String Functions (Core Language)

These should be:

* Small
* Predictable
* Non-regex (or extremely minimal regex exposure)
* Required to implement `lexis`
* Comparable to arithmetic primitives

Think: low-level operations.

---

## 1. Basic Inspection

```t
length(s)
is_empty(s)
```

---

## 2. Basic Substring Operations

```t
substring(s, start, end)
slice(s, start, end)          # alias or alternative
char_at(s, i)
```

No pattern logic here — purely positional.

---

## 3. Basic Search (Non-regex)

```t
index_of(s, sub)
last_index_of(s, sub)
contains(s, sub)
starts_with(s, prefix)
ends_with(s, suffix)
```

Literal matching only.

---

## 4. Basic Modification (Literal)

```t
replace(s, old, new)
replace_first(s, old, new)
```

Literal only — no regex.

---

## 5. Case Transformation

```t
to_lower(s)
to_upper(s)
```

That’s it.

No:

* trim
* split with regex
* pattern extraction
* advanced normalization
* tokenization

Keep core minimal and orthogonal.


# What Should NOT Be Built-in

To keep boundaries clean, do NOT include in core:

* Regex functions
* Trim helpers
* Split on pattern
* Case styling (snake/camel)
* Padding
* Tokenization helpers
* Capture group extraction
