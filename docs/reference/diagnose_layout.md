# Check the documented record layout against a natality file

Looks at the first `n` records. For each field it computes the share of
non-blank values that are not a documented code, or that fall outside
every documented range. If the layout is shifted somewhere, a run of bad
fields starts at the shift, and FILLER bytes that should be blank are
not. Bytes beyond the documented record length are summarised
separately.

## Usage

``` r
diagnose_layout(file, n = 20000L, year = 2025, threshold = 0.01)

# S3 method for class 'natality_diagnosis'
print(x, ...)
```

## Arguments

- file:

  Path to the fixed-width natality file.

- n:

  Number of records to inspect.

- year:

  Data year; see
  [`natality_years()`](https://github.com/vjcitn/nchsNatality/reference/natality_years.md).

- threshold:

  Fields whose share of undocumented values exceeds this are reported.

- x:

  A `natality_diagnosis`.

- ...:

  Ignored.

## Value

An object of class `natality_diagnosis`: a list with `record_lengths`
(table), `fields` (one row per field with `nonblank` and `bad` shares),
`anchors` (value tables for a few fields with known codes),
`filler_nonblank`, `bad_fields`, and, for records longer than
documented, `tail_values` and `tail_nonblank`. It has a print method.

## Examples

``` r
if (FALSE) { # \dontrun{
diagnose_layout("Nat2025PublicUS.c20260624.r20260922.txt")
} # }
```
