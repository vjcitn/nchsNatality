# Read the natality public-use file

Reads fields by byte position with
[`vroom::vroom_fwf()`](https://vroom.tidyverse.org/reference/vroom_fwf.html).
Bytes beyond the last documented field are never read, so a file whose
records are longer than the guide says is read correctly as long as the
documented fields are where the guide puts them (see
[`diagnose_layout()`](https://github.com/vjcitn/nchsNatality/reference/diagnose_layout.md)).

## Usage

``` r
read_natality(
  file,
  cols = NULL,
  n_max = Inf,
  raw = FALSE,
  na_unknown = TRUE,
  year = 2025,
  ...
)
```

## Arguments

- file:

  Path to the fixed-width natality file.

- cols:

  Field names to read. The default is every field except FILLER.

- n_max:

  Number of records to read.

- raw:

  If `TRUE`, return every field as the character code in the file.

- na_unknown:

  For numeric fields, turn the documented "unknown", "not stated" and
  "not applicable" codes (e.g. DBWT 9999, BMI 99.9, ILLB_R 888/999,
  APGAR10 88) into `NA`.

- year:

  Data year; see
  [`natality_years()`](https://github.com/vjcitn/nchsNatality/reference/natality_years.md).

- ...:

  Passed to
  [`vroom::vroom_fwf()`](https://vroom.tidyverse.org/reference/vroom_fwf.html),
  e.g. `num_threads`.

## Value

A `data.table`. Numeric fields (`kind == "numeric"` in
[`natality_layout()`](https://github.com/vjcitn/nchsNatality/reference/natality_layout.md))
are integer (BMI is double). Categorical fields are character codes, for
use with
[`label_natality()`](https://github.com/vjcitn/nchsNatality/reference/label_natality.md).
Blank fields, which the guide uses for items not on the certificate or
from non-reporting areas, are `NA`.

## Examples

``` r
if (FALSE) { # \dontrun{
f <- "Nat2025PublicUS.c20260624.r20260922.txt"
z <- read_natality(f, n_max = 10000)
z <- read_natality(f, cols = c("MAGER", "DBWT", "COMBGEST", "SEX"))
} # }
```
