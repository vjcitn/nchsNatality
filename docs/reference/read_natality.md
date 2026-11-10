# Read the natality public-use file

Reads fields by byte position with
[`vroom::vroom_fwf()`](https://vroom.tidyverse.org/reference/vroom_fwf.html),
or, if a sharded Parquet directory (as written by
[`natality_pack()`](https://github.com/vjcitn/nchsNatality/reference/natality_pack.md))
is available, queries that instead via DuckDB — same result, far less
I/O. Bytes beyond the last documented field are never read, so a file
whose records are longer than the guide says is read correctly as long
as the documented fields are where the guide puts them (see
[`diagnose_layout()`](https://github.com/vjcitn/nchsNatality/reference/diagnose_layout.md)).

## Usage

``` r
read_natality(
  file = NULL,
  cols = NULL,
  n_max = Inf,
  raw = FALSE,
  na_unknown = TRUE,
  year = 2025,
  parquet_dir = NULL,
  ...
)
```

## Source

The fixed-width file itself is downloaded from NCHS at
<https://www.cdc.gov/nchs/data_access/vitalstatsonline.htm#Downloadable>;
this function reads a copy already on disk and does not download it.

## Arguments

- file:

  Path to the fixed-width natality file. `NULL` (the default) resolves
  from `NCHS_NAT_PATH` or `NCHS_NAT_PARQUET`; see above.

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

- parquet_dir:

  A directory written by
  [`natality_pack()`](https://github.com/vjcitn/nchsNatality/reference/natality_pack.md)
  to query instead of `file`. `NULL` (the default) resolves from
  `NCHS_NAT_PARQUET`; see above. Ignored if `file` is given explicitly.

- ...:

  Passed to
  [`vroom::vroom_fwf()`](https://vroom.tidyverse.org/reference/vroom_fwf.html)
  when reading text, e.g. `num_threads`. Ignored when reading from
  Parquet.

## Value

A `data.table`. Numeric fields (`kind == "numeric"` in
[`natality_layout()`](https://github.com/vjcitn/nchsNatality/reference/natality_layout.md))
are integer (BMI is double). Categorical fields are character codes, for
use with
[`label_natality()`](https://github.com/vjcitn/nchsNatality/reference/label_natality.md).
Blank fields, which the guide uses for items not on the certificate or
from non-reporting areas, are `NA`.

## Choosing text vs Parquet

`file` and `parquet_dir` default to `NULL`, meaning "resolve from the
environment": `NCHS_NAT_PARQUET`, if it names a directory with a
`storage.csv` and at least one `*.parquet` file in it, is used;
otherwise `NCHS_NAT_PATH` is used. Passing `file` or `parquet_dir`
explicitly pins the source and skips that resolution. Either way the
result has the same shape: same columns, same types, same `na_unknown`
sentinel handling — see `inst/adrs/` for the reasoning. Row order is
**not** part of that contract:
[`natality_pack()`](https://github.com/vjcitn/nchsNatality/reference/natality_pack.md)
sorts and shards rows for compression (see its documentation), so
reading from Parquet returns the same rows as from text, as a set, but
not necessarily in the same order.

## Examples

``` r
if (nchar(f <- Sys.getenv("NCHS_NAT_PATH"))>0) {
  z <- read_natality(f, n_max = 10000)
  z <- read_natality(f, cols = c("MAGER", "DBWT", "COMBGEST", "SEX"))
  } else { "NCHS_NAT_PATH not set in visible environment" }
#> [1] "NCHS_NAT_PATH not set in visible environment"
```
