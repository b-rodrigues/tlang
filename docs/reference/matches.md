# matches

Match columns by regex

Selection helper that returns columns whose names match a regular expression. Patterns are compiled with PCRE2 in UTF-8 mode, so `.` matches a code point and classes like `\\p{L}` are supported.

