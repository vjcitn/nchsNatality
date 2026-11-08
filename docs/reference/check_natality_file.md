# Check line endings and record length of a natality file

Reads only the first `nbytes` bytes.

## Usage

``` r
check_natality_file(file, nbytes = 100000L, year = 2025)
```

## Arguments

- file:

  Path to the fixed-width natality file.

- nbytes:

  Number of bytes to inspect.

- year:

  Data year, used for the documented record length.

## Value

Invisibly, a list with `terminator` (`"LF"`, `"CRLF"`, `"CR only"` or
`"none"`), `record_length` (the distinct lengths seen, excluding line
endings), `documented_length` and `quotes` (number of `"` bytes). A
summary is printed.

## Examples

``` r
f <- tempfile()
writeLines(strrep(" ", 1330), f)
check_natality_file(f)
#> terminator: LF; record length(s) in first 1331 bytes: 1330 (guide documents 1330); '"' bytes: 0
```
